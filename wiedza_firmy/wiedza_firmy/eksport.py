"""Eksport calej bazy (zywe wpisy) do pliku w formacie importu, z id wpisow.

    python -m wiedza_firmy.eksport <plik.md> [--nadpisz]

Po co: przeklasyfikowanie na przyszlosc (np. nowa kategoria). Eksport -> poprawka tematow w pliku
(`## temat:` = glowny, `[+a,b]` = dodatkowe) -> `python -m wiedza_firmy.ustaw_tematy <plik>`.

Kazdy wpis ma `[#id]` przed data. Tresc idzie w jednej linii (wewnetrzne konce linii i wielokrotne spacje
zamienione na jedna spacje - tak samo sklada je import). Wpisy usuniete nie wchodza do eksportu (liczba
pominietych stoi w naglowku). Przed zapisem plik jest parsowany z powrotem i porownany z baza - eksport,
ktorego nie da sie wczytac jeden do jednego, jest odmowa, nie zapisanym kadlubkiem.
Tylko lokalnie na serwerze - bez uprawnien, czyta wszystko.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from . import sciezki
from .baza import Baza, teraz
from .importuj import BladFormatu, parsuj_z_liniami
from .pliki import utf8_na_wyjsciu


class BladEksportu(RuntimeError):
    pass


def jedna_linia(tekst: str) -> str:
    return " ".join(tekst.split())


def tekst_eksportu(baza: Baza) -> tuple[str, int, int]:
    """(tekst pliku, liczba wpisow, liczba pominietych usunietych). Sprawdzony powrotnym parsowaniem."""
    wszystkie = baza.wpisy_z_tematami(z_usunietymi=True)
    zywe = [w for w in wszystkie.values() if w["usuniety"] is None]
    usuniete = len(wszystkie) - len(zywe)
    linie = [f"# Eksport wiedzy firmy {teraz()}: {len(zywe)} wpisow (pominiete usuniete: {usuniete})",
             "# [#id] to id wpisu w bazie (dla ustaw_tematy); '## temat:' = temat glowny, [+a,b] = tematy dodatkowe",
             ""]
    ustawienia = {"autor": None, "program": None, "zrodlo": None}
    sekcja = None
    for w in sorted(zywe, key=lambda w: (w["temat"], w["id"])):
        glowne = [t for t, g in w["tematy"] if g]
        if glowne != [w["temat"]]:
            raise BladEksportu(f"wpis {w['id']}: temat glowny w wpisy_tematy {glowne} rozny od wpisy.temat "
                               f"{w['temat']!r} - baza niespojna, eksport przerwany")
        if w["temat"] != sekcja:
            linie += [f"## temat: {w['temat']}"] if linie[-1] == "" else ["", f"## temat: {w['temat']}"]
            sekcja = w["temat"]
        for klucz in ("autor", "program", "zrodlo"):
            if ustawienia[klucz] != w[klucz]:
                linie.append(f"{klucz}: {jedna_linia(w[klucz])}".rstrip())
                ustawienia[klucz] = w[klucz]
        dodatkowe = [t for t, g in w["tematy"] if not g]
        znacznik = f"[+{','.join(dodatkowe)}] " if dodatkowe else ""
        linie.append(f"- [#{w['id']}] [{w['data_ustalenia']}] [{w['poufnosc']}] {znacznik}{jedna_linia(w['tresc'])}")
    tekst = "\n".join(linie) + "\n"
    if zywe:
        _sprawdz_powrotnie(tekst, zywe)
    return tekst, len(zywe), usuniete


def _sprawdz_powrotnie(tekst: str, zywe: list[dict]) -> None:
    try:
        wczytane = parsuj_z_liniami(tekst, "eksport")
    except BladFormatu as e:
        raise BladEksportu(f"eksport nie wczytuje sie z powrotem: {e}") from e
    oczekiwane = {w["id"]: w for w in zywe}
    if sorted(x.id for x in wczytane if x.id is not None) != sorted(oczekiwane) or any(x.id is None for x in wczytane):
        raise BladEksportu("eksport po wczytaniu ma inne id wpisow niz baza")
    for x in wczytane:
        w = oczekiwane[x.id]
        pary = [("tresc", x.wpis.tresc, jedna_linia(w["tresc"])), ("temat", x.wpis.temat, w["temat"]),
                ("tematy dodatkowe", list(x.wpis.tematy_dodatkowe), [t for t, g in w["tematy"] if not g]),
                ("poufnosc", x.wpis.poufnosc, w["poufnosc"]), ("data", x.wpis.data_ustalenia, w["data_ustalenia"]),
                ("autor", x.wpis.autor, jedna_linia(w["autor"])), ("program", x.wpis.program, jedna_linia(w["program"])),
                ("zrodlo", x.wpis.zrodlo, jedna_linia(w["zrodlo"]))]
        for pole, z_pliku, z_bazy in pary:
            if z_pliku != z_bazy:
                raise BladEksportu(f"wpis {x.id} (linia {x.linia}): {pole} po wczytaniu {z_pliku!r}, w bazie {z_bazy!r}")


def main(argv: list[str] | None = None) -> int:
    utf8_na_wyjsciu()
    p = argparse.ArgumentParser(prog="python -m wiedza_firmy.eksport")
    p.add_argument("plik", type=Path)
    p.add_argument("--nadpisz", action="store_true", help="zastap istniejacy plik")
    a = p.parse_args(argv)

    if a.plik.exists() and not a.nadpisz:
        print(f"ODMOWA: {a.plik} juz istnieje (--nadpisz, zeby zastapic)", file=sys.stderr)
        return 1
    if not sciezki.plik_bazy().exists():
        print(f"ODMOWA: nie ma bazy {sciezki.plik_bazy()}", file=sys.stderr)
        return 1
    try:
        tekst, ile, usuniete = tekst_eksportu(Baza(sciezki.plik_bazy(), None))
    except BladEksportu as e:
        print(f"ODMOWA (nic nie zapisano): {e}", file=sys.stderr)
        return 1
    a.plik.parent.mkdir(parents=True, exist_ok=True)
    tymczasowy = a.plik.with_name(a.plik.name + f".tmp-{os.getpid()}")
    tymczasowy.write_bytes(tekst.encode("utf-8"))
    os.replace(tymczasowy, a.plik)
    print(f"zapisano {ile} wpisow do {a.plik} (pominiete usuniete: {usuniete})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
