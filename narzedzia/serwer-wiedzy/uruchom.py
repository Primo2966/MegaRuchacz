"""Uruchamianie kodu serwera "Wiedza firmy" z katalogu instalacji (Pakowanie2).

Kod serwera nie jest instalowany pip-em: samoaktualizacja (aktualizacja.py)
podmienia katalog `kod\\` (wiedza_firmy\\ + lore\\lore\\ z repo MegaRuchacza),
a ten plik ustawia sciezki importu i uruchamia wskazany modul jak `python -m`.
Dziala z oboma ukladami pakietu: `wiedza_firmy\\__init__.py` (plaski) albo
`wiedza_firmy\\wiedza_firmy\\__init__.py` / `wiedza_firmy\\src\\wiedza_firmy\\`
(pyproject obok pakietu, jak w lore\\).

Srodowisko (gdy nie jest juz ustawione):
  WIEDZA_FIRMY_HOME = "dane" z <kat>\\serwer-wiedzy.json - CLI przez SSH (osoby, tematy,
                      import, model) widzi te same dane co serwer pod straznikiem,
  LORE_HOME         = <kat>\\lore-dane - lore nie zaklada niczego w profilu uzytkownika
                      (~\\.lore); model i tak lezy tam, gdzie wskaze wiedza_firmy (dane\\modele).

  python uruchom.py wiedza_firmy.osoby nowa ela        # dowolny modul z argumentami
  python uruchom.py wiedza_firmy.model                 # model: pobranie, sumy SHA-256, proba
  python uruchom.py --sprawdz wiedza_firmy.serwer      # czy kod sie importuje (kod wyjscia 0/1)
  python uruchom.py --kod <inny katalog kodu> ...      # np. sprawdzenie nowej wersji przed podmiana
"""

from __future__ import annotations

import importlib
import importlib.util
import json
import os
import runpy
import sys
from pathlib import Path

KAT = Path(__file__).resolve().parents[1]  # <kat>\narzedzia\uruchom.py -> <kat>


def sciezki_kodu(kod: Path) -> list[Path]:
    """Katalogi do sys.path dla danego drzewa kodu. Brak pakietu = czytelny blad."""
    wf = kod / "wiedza_firmy"
    if (wf / "__init__.py").is_file():
        baza = kod
    elif (wf / "wiedza_firmy" / "__init__.py").is_file():
        baza = wf
    elif (wf / "src" / "wiedza_firmy" / "__init__.py").is_file():
        baza = wf / "src"
    else:
        raise SystemExit(f"[BLAD] w {kod} nie ma pakietu wiedza_firmy (brak __init__.py)")
    lore = kod / "lore"
    if not (lore / "lore" / "__init__.py").is_file():
        raise SystemExit(f"[BLAD] w {kod} nie ma pakietu lore (brak lore\\lore\\__init__.py)")
    return [baza, lore]


def przygotuj(kod: Path) -> None:
    sciezki = [str(p) for p in sciezki_kodu(kod)]
    # katalog tego skryptu nie ma byc na sciezce (aktualizacja.py, kopia.py to nie moduly serwera)
    tu = Path(__file__).resolve().parent
    sys.path[:] = [p for p in sys.path if p and Path(p).resolve() != tu]
    sys.path[0:0] = sciezki
    stara = os.environ.get("PYTHONPATH", "")
    os.environ["PYTHONPATH"] = os.pathsep.join(sciezki + ([stara] if stara else []))
    os.environ.setdefault("LORE_HOME", str(KAT / "lore-dane"))
    if not os.environ.get("WIEDZA_FIRMY_HOME"):
        try:
            dane = json.loads((KAT / "serwer-wiedzy.json").read_text(encoding="utf-8")).get("dane")
        except (OSError, ValueError):
            dane = None  # brak konfiguracji = domyslne %APPDATA%\wiedza-firmy z wiedza_firmy
        if dane:
            os.environ["WIEDZA_FIRMY_HOME"] = dane


def sprawdz(modul: str) -> int:
    try:
        importlib.import_module("wiedza_firmy")
        if importlib.util.find_spec(modul) is None:
            print(f"[BLAD] brak modulu {modul}", file=sys.stderr)
            return 1
        importlib.import_module(modul)  # tez skladnia i zaleznosci modulu serwera (start jest pod __main__)
        if importlib.util.find_spec("lore.db") is None:
            print("[BLAD] brak modulu lore.db", file=sys.stderr)
            return 1
    except BaseException as exc:  # SyntaxError, ImportError, SystemExit z __init__ - wszystko to blad
        print(f"[BLAD] kod sie nie importuje: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 1
    print(f"OK: wiedza_firmy i {modul} sie importuja")
    return 0


def main(argv: list[str]) -> int:
    kod = KAT / "kod"
    if len(argv) >= 2 and argv[0] == "--kod":
        kod = Path(argv[1])
        argv = argv[2:]
    if not argv:
        print(__doc__)
        return 2
    przygotuj(kod)
    if argv[0] == "--sprawdz":
        return sprawdz(argv[1] if len(argv) > 1 else "wiedza_firmy")
    modul, reszta = argv[0], argv[1:]
    sys.argv = [modul] + reszta
    runpy.run_module(modul, run_name="__main__", alter_sys=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
