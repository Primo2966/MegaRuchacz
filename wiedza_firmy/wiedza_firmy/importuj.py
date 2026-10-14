"""Import wsadu ustalen z pliku Markdown.

    python -m wiedza_firmy.importuj <plik.md> [--na-sucho]

Format (przyklad: przyklady/wsad.przyklad.md):

    # Tytul - dowolny, pomijany
    autor: Anna
    program: claude-code
    zrodlo: rozmowy o grafikach, pazdziernik
    poufnosc: jawne                       <- domyslny poziom dla wpisow bez [poziomu]

    ## temat: przyklad-grafiki
    - [2026-10-01] [wewnetrzne] Tresc ustalenia.
      Linia z wcieciem to ciag dalszy tego samego wpisu.
    - [2026-10-02] Wpis z domyslnym poziomem.
    - [2026-10-03] [jawne] [+przyklad-produkty,przyklad-it] Wpis w kilku tematach naraz.

`## temat:` to temat glowny wpisu. Opcjonalny znacznik `[+temat2,temat3]` po poziomie (albo po dacie, gdy
poziomu nie ma) dodaje tematy dodatkowe; bez znacznika wpis ma tylko temat glowny. Temat spoza listy
serwera, powtorzony albo rowny glownemu = odmowa calego pliku z numerem linii.

`[#id]` przed data (pisze go `python -m wiedza_firmy.eksport`) to id wpisu w bazie - czyta go
`ustaw_tematy`; import go pomija i o tym mowi (nowe wpisy dostaja nowe id).

Linie `klucz: wartosc` (autor, program, zrodlo, poufnosc, temat) obowiazuja dla kolejnych wpisow.
Kazda inna linia, ktorej parser nie rozumie, to blad z numerem linii - zadnego zgadywania. Caly plik
idzie albo w calosci, albo wcale. Ta sama tresc w tym samym temacie drugi raz nie wchodzi, a wpis
usuniety przez admina nie wraca przy ponownym imporcie.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

from . import sciezki, tematy
from .baza import Baza, BladWpisu, NowyWpis, sprawdz_tematy_dodatkowe
from .pliki import utf8_na_wyjsciu

_WPIS = re.compile(r"^- (?:\[#(?P<id>\d+)\]\s*)?\[(?P<data>[^\]]*)\]\s*(?:\[(?P<poziom>[a-ząćęłńóśźż]+)\]\s*)?"
                   r"(?:\[\+(?P<dodatkowe>[^\]]*)\]\s*)?(?P<tresc>.*)$")
_KLUCZ = re.compile(r"^(?P<klucz>autor|program|zrodlo|poufnosc|temat):\s*(?P<wartosc>.*)$")
_TEMAT = re.compile(r"^##\s+temat:\s*(?P<temat>\S+)\s*$")


class BladFormatu(ValueError):
    pass


@dataclass
class WpisZPliku:
    linia: int
    id: int | None  # [#id] z eksportu; None = wpis bez id
    wpis: NowyWpis


def parsuj(tekst: str, nazwa: str = "wsad", znane_tematy: set[str] | None = None) -> list[NowyWpis]:
    return [w.wpis for w in parsuj_z_liniami(tekst, nazwa, znane_tematy)]


def parsuj_z_liniami(tekst: str, nazwa: str = "wsad", znane_tematy: set[str] | None = None) -> list[WpisZPliku]:
    """Wpisy z numerem linii i id. `znane_tematy` podane = temat glowny i dodatkowe spoza listy to BladFormatu
    z numerem linii (bez listy sprawdza je dopiero Baza.dodaj, juz bez numeru linii)."""
    ustawienia = {"autor": "", "program": "", "zrodlo": "", "poufnosc": "", "temat": ""}
    wpisy: list[WpisZPliku] = []
    ostatni: NowyWpis | None = None
    for nr, linia in enumerate(tekst.splitlines(), 1):
        gdzie = f"{nazwa}:{nr}"
        if not linia.strip():
            ostatni = None
            continue
        if ostatni is not None and linia.startswith("  ") and not linia.lstrip().startswith("- ["):
            ostatni.tresc += " " + linia.strip()
            continue
        ostatni = None
        if linia.startswith("# "):
            continue
        if linia.startswith("#"):
            m = _TEMAT.match(linia)
            if not m:
                raise BladFormatu(f"{gdzie}: naglowek inny niz '## temat: <id>' - {linia!r}")
            ustawienia["temat"] = m["temat"]
            continue
        m = _KLUCZ.match(linia)
        if m:
            ustawienia[m["klucz"]] = m["wartosc"].strip()
            continue
        m = _WPIS.match(linia)
        if not m:
            raise BladFormatu(f"{gdzie}: nie rozumiem linii - {linia!r} (wpis: '- [RRRR-MM-DD] [poziom] tresc')")
        poziom = m["poziom"] or ustawienia["poufnosc"]
        if not poziom:
            raise BladFormatu(f"{gdzie}: wpis bez poziomu poufnosci i bez 'poufnosc:' wyzej")
        if not ustawienia["temat"]:
            raise BladFormatu(f"{gdzie}: wpis przed pierwszym '## temat: <id>'")
        if not m["tresc"].strip():
            raise BladFormatu(f"{gdzie}: pusta tresc wpisu")
        dodatkowe: tuple[str, ...] = ()
        if m["dodatkowe"] is not None:
            dodatkowe = tuple(t.strip() for t in m["dodatkowe"].split(","))
            if not all(dodatkowe):
                raise BladFormatu(f"{gdzie}: pusty temat w [+...] - wzor: [+temat2,temat3]")
        if znane_tematy is not None:
            for t in (ustawienia["temat"], *dodatkowe):
                if t not in znane_tematy:
                    raise BladFormatu(f"{gdzie}: nieznany temat {t!r} (znane: {', '.join(sorted(znane_tematy)) or 'brak'})")
        try:
            sprawdz_tematy_dodatkowe(ustawienia["temat"], dodatkowe, set(znane_tematy or {ustawienia["temat"], *dodatkowe}),
                                     gdzie)
        except BladWpisu as e:
            raise BladFormatu(str(e)) from e
        ostatni = NowyWpis(tresc=m["tresc"].strip(), temat=ustawienia["temat"], poufnosc=poziom,
                           autor=ustawienia["autor"], data_ustalenia=m["data"].strip(),
                           zrodlo=ustawienia["zrodlo"], program=ustawienia["program"], tematy_dodatkowe=dodatkowe)
        wpisy.append(WpisZPliku(nr, int(m["id"]) if m["id"] else None, ostatni))
    if not wpisy:
        raise BladFormatu(f"{nazwa}: brak wpisow")
    return wpisy


def main(argv: list[str] | None = None) -> int:
    utf8_na_wyjsciu()
    p = argparse.ArgumentParser(prog="python -m wiedza_firmy.importuj")
    p.add_argument("plik", type=Path)
    p.add_argument("--na-sucho", action="store_true", help="tylko sprawdz plik, nic nie zapisuj")
    p.add_argument("--bez-modelu", action="store_true",
                   help="zapisz bez wektorow (serwer dolicza je sam przy starcie)")
    p.add_argument("--dodal", default="import", help="kto wgrywa (slad w bazie)")
    a = p.parse_args(argv)

    try:
        znane = set(tematy.slownik())
        if not znane:
            print(f"ODMOWA: brak tematow na serwerze ({sciezki.plik_tematow()}) - najpierw: "
                  "python -m wiedza_firmy.tematy wczytaj <plik.json>", file=sys.stderr)
            return 1
        z_liniami = parsuj_z_liniami(a.plik.read_text(encoding="utf-8-sig"), a.plik.name, znane)
    except (OSError, BladFormatu, tematy.BladTematow) as e:
        print(f"ODMOWA: {e}", file=sys.stderr)
        return 1
    wpisy = [w.wpis for w in z_liniami]
    z_id = sum(1 for w in z_liniami if w.id is not None)
    if z_id:
        print(f"UWAGA: {z_id} wpisow ma [#id] (plik z eksportu) - import je pomija i dodaje wpisy jako nowe "
              "(ta sama tresc w tym samym temacie glownym nie wejdzie drugi raz). Zmiana tematow istniejacych "
              "wpisow: python -m wiedza_firmy.ustaw_tematy", file=sys.stderr)
    podzial = Counter((w.temat, w.poufnosc) for w in wpisy)
    for (t, poz), n in sorted(podzial.items()):
        print(f"  {t} / {poz}: {n}")
    wielu = sum(1 for w in wpisy if w.tematy_dodatkowe)
    if wielu:
        print(f"  w tym z tematami dodatkowymi: {wielu}")
    if a.na_sucho:
        print(f"na sucho: {len(wpisy)} wpisow poprawnych formalnie, nic nie zapisano")
        return 0

    wektory = None
    if not a.bez_modelu:
        from .wektory import WektoryLore

        wektory = WektoryLore()
    baza = Baza(sciezki.plik_bazy(), wektory)
    try:
        wynik = baza.dodaj(wpisy, dodal=a.dodal, znane_tematy=znane)
    except BladWpisu as e:
        print(f"ODMOWA (nic nie zapisano): {e}", file=sys.stderr)
        return 1
    print(f"dodano {len(wynik.dodane)}, juz byly {wynik.duplikaty}, usuniete wczesniej (nie wracaja) "
          f"{wynik.usuniete_wczesniej}, z zamaskowanym sekretem {wynik.zamaskowane}")
    for u in wynik.uwagi:
        print(f"UWAGA: {u}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
