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
from pathlib import Path

from . import sciezki, tematy
from .baza import Baza, BladWpisu, NowyWpis
from .pliki import utf8_na_wyjsciu

_WPIS = re.compile(r"^- \[(?P<data>[^\]]*)\]\s*(?:\[(?P<poziom>[a-ząćęłńóśźż]+)\]\s*)?(?P<tresc>.*)$")
_KLUCZ = re.compile(r"^(?P<klucz>autor|program|zrodlo|poufnosc|temat):\s*(?P<wartosc>.*)$")
_TEMAT = re.compile(r"^##\s+temat:\s*(?P<temat>\S+)\s*$")


class BladFormatu(ValueError):
    pass


def parsuj(tekst: str, nazwa: str = "wsad") -> list[NowyWpis]:
    ustawienia = {"autor": "", "program": "", "zrodlo": "", "poufnosc": "", "temat": ""}
    wpisy: list[NowyWpis] = []
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
        ostatni = NowyWpis(tresc=m["tresc"].strip(), temat=ustawienia["temat"], poufnosc=poziom,
                           autor=ustawienia["autor"], data_ustalenia=m["data"].strip(),
                           zrodlo=ustawienia["zrodlo"], program=ustawienia["program"])
        wpisy.append(ostatni)
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
        wpisy = parsuj(a.plik.read_text(encoding="utf-8-sig"), a.plik.name)
        znane = set(tematy.slownik())
    except (OSError, BladFormatu, tematy.BladTematow) as e:
        print(f"ODMOWA: {e}", file=sys.stderr)
        return 1
    if not znane:
        print(f"ODMOWA: brak tematow na serwerze ({sciezki.plik_tematow()}) - najpierw: "
              "python -m wiedza_firmy.tematy wczytaj <plik.json>", file=sys.stderr)
        return 1
    obce = sorted({w.temat for w in wpisy} - znane)
    if obce:
        print(f"ODMOWA: tematy spoza listy serwera: {', '.join(obce)}", file=sys.stderr)
        return 1
    podzial = Counter((w.temat, w.poufnosc) for w in wpisy)
    for (t, poz), n in sorted(podzial.items()):
        print(f"  {t} / {poz}: {n}")
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
