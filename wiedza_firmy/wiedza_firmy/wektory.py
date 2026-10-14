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


class Wektoryzator(Protocol):
    model: str
    wymiar: int

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
