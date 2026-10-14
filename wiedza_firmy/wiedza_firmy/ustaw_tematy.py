"""Przeklasyfikowanie istniejacych wpisow: podmiana listy tematow wedlug pliku z eksportu.

    python -m wiedza_firmy.ustaw_tematy <plik.md> [--na-sucho]

Plik w formacie eksportu (`python -m wiedza_firmy.eksport`): kazdy wpis z `[#id]`, temat glowny z sekcji
`## temat:`, dodatkowe ze znacznika `[+a,b]`. Dla kazdego id lista tematow wpisu w bazie staje sie dokladnie
taka jak w pliku. Tresci, poziomu, daty i autora NIE zmienia - tresc sluzy tylko do sprawdzenia, ze id
wskazuje ten sam wpis (inna tresc = odmowa: plik z innej bazy albo pomylone id). Wpisow, ktorych w pliku
nie ma, nie rusza.

Calosc albo nic: wpis bez id, powtorzone id, id spoza bazy, temat spoza listy serwera, inna tresc - odmowa
calego pliku z numerem linii, zanim cokolwiek sie zmieni. Przed zapisem kopia bazy obok niej.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import sciezki, tematy
from .baza import Baza, BladWpisu
from .eksport import jedna_linia
from .importuj import BladFormatu, parsuj_z_liniami
from .pliki import utf8_na_wyjsciu


def _opis(glowny: str, dodatkowe: tuple[str, ...] | list[str]) -> str:
    return glowny + "".join(f" +{t}" for t in dodatkowe)


def main(argv: list[str] | None = None) -> int:
    utf8_na_wyjsciu()
    p = argparse.ArgumentParser(prog="python -m wiedza_firmy.ustaw_tematy")
    p.add_argument("plik", type=Path)
    p.add_argument("--na-sucho", action="store_true", help="pokaz zmiany, nic nie zapisuj")
    a = p.parse_args(argv)

    try:
        znane = set(tematy.slownik())
        if not znane:
            print(f"ODMOWA: brak tematow na serwerze ({sciezki.plik_tematow()})", file=sys.stderr)
            return 1
        wpisy = parsuj_z_liniami(a.plik.read_text(encoding="utf-8-sig"), a.plik.name, znane)
    except (OSError, BladFormatu, tematy.BladTematow) as e:
        print(f"ODMOWA: {e}", file=sys.stderr)
        return 1
    if not sciezki.plik_bazy().exists():
        print(f"ODMOWA: nie ma bazy {sciezki.plik_bazy()}", file=sys.stderr)
        return 1

    widziane: dict[int, int] = {}
    for w in wpisy:
        if w.id is None:
            print(f"ODMOWA: {a.plik.name}:{w.linia}: wpis bez [#id] - ustaw_tematy zmienia tylko istniejace wpisy "
                  "(nowe dodaje importuj)", file=sys.stderr)
            return 1
        if w.id in widziane:
            print(f"ODMOWA: {a.plik.name}:{w.linia}: id {w.id} juz bylo w linii {widziane[w.id]}", file=sys.stderr)
            return 1
        widziane[w.id] = w.linia

    baza = Baza(sciezki.plik_bazy(), None)
    w_bazie = baza.wpisy_z_tematami(ids=list(widziane), z_usunietymi=True)
    zmiany: dict[int, tuple[str, tuple[str, ...]]] = {}
    opisy: list[str] = []
    for w in wpisy:
        gdzie = f"{a.plik.name}:{w.linia}"
        stary = w_bazie.get(w.id)
        if stary is None:
            print(f"ODMOWA: {gdzie}: nie ma wpisu {w.id} w bazie", file=sys.stderr)
            return 1
        if jedna_linia(stary["tresc"]) != jedna_linia(w.wpis.tresc):
            print(f"ODMOWA: {gdzie}: wpis {w.id} ma w bazie inna tresc - plik z innej bazy albo pomylone id "
                  "(ustaw_tematy nie zmienia tresci)", file=sys.stderr)
            return 1
        if stary["poufnosc"] != w.wpis.poufnosc:
            print(f"UWAGA: {gdzie}: wpis {w.id} ma w bazie poziom {stary['poufnosc']}, w pliku {w.wpis.poufnosc} - "
                  "ustaw_tematy zmienia tylko tematy, poziom zostaje", file=sys.stderr)
        glowne = [t for t, g in stary["tematy"] if g]
        # brak glownego w wpisy_tematy (baza niespojna) = zawsze zmiana, ktora to naprawia
        stare = (glowne[0] if glowne else f"(brak; wpisy.temat={stary['temat']})",
                 tuple(sorted(t for t, g in stary["tematy"] if not g)))
        nowe = (w.wpis.temat, tuple(sorted(w.wpis.tematy_dodatkowe)))
        if stare == nowe and stary["temat"] == nowe[0]:
            continue
        zmiany[w.id] = nowe
        znak = " (usuniety)" if stary["usuniety"] else ""
        opisy.append(f"  wpis {w.id}{znak} (linia {w.linia}): {_opis(*stare)} -> {_opis(*nowe)}")

    for o in opisy:
        print(o)
    if not zmiany:
        print(f"nic do zmiany: {len(wpisy)} wpisow w pliku ma juz takie tematy")
        return 0
    if a.na_sucho:
        print(f"na sucho: zmienilbym tematy {len(zmiany)} wpisow z {len(wpisy)}, nic nie zapisano")
        return 0
    try:
        kopia = baza.kopia("przed-ustaw-tematy")
        baza.ustaw_tematy(zmiany, znane)
    except BladWpisu as e:
        print(f"ODMOWA (nic nie zmieniono): {e}", file=sys.stderr)
        return 1
    print(f"zmieniono tematy {len(zmiany)} wpisow z {len(wpisy)}; kopia bazy sprzed zmiany: {kopia}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
