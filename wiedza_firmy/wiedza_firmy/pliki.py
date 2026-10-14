"""Zapis plikow JSON jednym krokiem (plik obok + os.replace) - przerwany zapis nie zostawia kadlubka."""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime
from pathlib import Path


def zapisz_json(sciezka: Path, dane: object) -> None:
    sciezka.parent.mkdir(parents=True, exist_ok=True)
    tymczasowy = sciezka.with_name(sciezka.name + f".tmp-{os.getpid()}")
    tymczasowy.write_text(json.dumps(dane, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tymczasowy, sciezka)


def czytaj_json(sciezka: Path) -> object:
    return json.loads(sciezka.read_text(encoding="utf-8-sig"))


def utf8_na_wyjsciu() -> None:
    """Konsola Windows bywa w cp1252 - polska nazwa tematu nie moze wywrocic polecenia."""
    for strumien in (sys.stdout, sys.stderr):
        try:
            strumien.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError) as e:
            print(f"[wiedza-firmy] nie przestawilem kodowania {strumien!r}: {e!r}", file=sys.__stderr__)


def log(*args: object) -> None:
    """Dziennik idzie na stderr - stdout nalezy do CLI (tokeny, wyniki)."""
    print(datetime.now().strftime("%H:%M:%S"), "[wiedza-firmy]", *args, file=sys.stderr, flush=True)
