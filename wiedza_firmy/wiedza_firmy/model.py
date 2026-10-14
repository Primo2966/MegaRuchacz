"""Model wektorow przy instalacji: pobiera brakujace pliki, sprawdza sumy sha256, laduje na probe.

    python -m wiedza_firmy.model

Kod wyjscia 0 = model na miejscu i dziala; 1 = nie (powod na stderr). Pliki: sciezki.katalog_modeli().
"""

from __future__ import annotations

import sys
import time

from . import sciezki
from .pliki import utf8_na_wyjsciu
from .wektory import ModelNiedostepny, WektoryLore


def main() -> int:
    utf8_na_wyjsciu()
    t0 = time.monotonic()
    try:
        w = WektoryLore()
        w.zaladuj()
        wektor = w.pytanie("próba modelu")
    except ModelNiedostepny as e:
        print(f"BLAD: model niedostepny: {e}", file=sys.stderr)
        return 1
    if wektor.shape != (w.wymiar,):
        print(f"BLAD: model zwrocil wektor {wektor.shape}, oczekiwany ({w.wymiar},)", file=sys.stderr)
        return 1
    print(f"model {w.model} sprawdzony i zaladowany w {time.monotonic() - t0:.1f} s ({sciezki.katalog_modeli()})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
