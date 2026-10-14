"""Wektory wpisow i pytan: model mmlw z Lore, ladowany RAZ na proces.

Model lezy w sciezki.katalog_modeli() (nie w katalogu Lore): przestawiamy lore.db.MODELS_DIR przed
pierwszym uzyciem. Lore trzyma jeden zaladowany model na proces (db.embedding_model) - drugi
odczyt nie laduje go ponownie.

Testy podstawiaja wlasny obiekt z tym samym interfejsem (`Wektoryzator`) - nic nie pobieraja.
"""

from __future__ import annotations

from typing import Protocol

import numpy as np

from . import sciezki

MODEL = "sdadas/mmlw-retrieval-roberta-base"

# Prog trafnosci: najmniejsze podobienstwo kosinusowe pytania i wpisu, przy ktorym wpis jest wynikiem
# (baza.Baza._ranking, oba kanaly). Bez progu szukaj_wiedzy zawsze oddawal `limit` najblizszych wpisow,
# takze na pytanie spoza wszystkich tematow - sam szum.
#
# mmlw, pomiar 2026-10-14 (tests/test_model_prawdziwy.py, 10 wymyslonych ustalen firmowych):
# - 13 pytan pasujacych do konkretnego wpisu, w wiekszosci bez wspolnych slow: 0,773 .. 0,889;
# - 12 pytan spoza firmy (pogoda, przepis, pilka, numpy, bilet do kina, fotosynteza...): najblizszy wpis
#   0,623 .. 0,698; pytania firmowe bez odpowiedzi w bazie (urlop szefa, godziny biura, kurs euro, wifi):
#   0,692 .. 0,729;
# - prog 0,735 to srodek luki 0,698 .. 0,773 (zapas ok. 0,04 w obie strony).
# Znane slabe strony: pytanie po niemiecku do polskiego wpisu wypada ponizej progu (0,661), a jednowyrazowe
# smieci ("a", "test", "jak") ledwo nad nim (0,74 .. 0,75). Inny model = inne podobienstwa, wiec prog jest
# per model; model spoza tej tabeli dziala bez progu, a serwer melduje to w dzienniku i znaczniku zycia.
PROGI_TRAFNOSCI: dict[str, float] = {
    MODEL: 0.735,
}


class Wektoryzator(Protocol):
    model: str
    wymiar: int
    # opcjonalnie: prog_trafnosci: float | None - brak atrybutu = bez progu (baza.Baza._prog)

    def pasaze(self, teksty: list[str]) -> np.ndarray:
        """Znormalizowane wektory wpisow, ksztalt (len(teksty), wymiar)."""

    def pytanie(self, tekst: str) -> np.ndarray:
        """Znormalizowany wektor pytania, ksztalt (wymiar,)."""


class ModelNiedostepny(RuntimeError):
    """Modelu nie da sie zaladowac - wyszukiwanie zostaje pelnotekstowe, a odpowiedz to mowi."""


class WektoryLore:
    """mmlw przez lore.db: prefiks pytania "zapytanie: ", bez prefiksu wpisu, CLS, 768 wymiarow."""

    def __init__(self, model: str = MODEL) -> None:
        from lore import db

        if model not in db.MODELS:
            raise ModelNiedostepny(f"Lore nie zna modelu {model} (zna: {', '.join(db.MODELS)})")
        db.MODELS_DIR = sciezki.katalog_modeli()
        self._db = db
        self.model = model
        self.wymiar = db.MODELS[model].dim
        self.prog_trafnosci: float | None = PROGI_TRAFNOSCI.get(model)

    def zaladuj(self) -> None:
        """Sprawdza pliki modelu sumami (pobiera brakujace) i laduje go do pamieci procesu."""
        try:
            self._db.fetch_pinned(self._db.MODELS[self.model])
            self._db.embedding_model(self.model)
        except Exception as e:
            raise ModelNiedostepny(f"{e}") from e

    def pasaze(self, teksty: list[str]) -> np.ndarray:
        try:
            return self._db.embed_passages(teksty, model=self.model)
        except Exception as e:
            raise ModelNiedostepny(f"{e}") from e

    def pytanie(self, tekst: str) -> np.ndarray:
        try:
            return self._db.embed_query(tekst, model=self.model)
        except Exception as e:
            raise ModelNiedostepny(f"{e}") from e
