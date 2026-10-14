"""Wspolne srodowisko testow: wlasny katalog danych, tematy-atrapy, osoby-atrapy, wektory-atrapy.

Nic nie jest pobierane: `WektoryAtrapa` liczy wektor z samych slow (haszowanie), bez modelu.
Wszystkie dane sa wymyslone - repo jest publiczne.
"""

from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from dataclasses import dataclass

import numpy as np
import pytest

from wiedza_firmy import osoby, sciezki
from wiedza_firmy.baza import Baza, NowyWpis
from wiedza_firmy.uprawnienia import ZrodloPlikowe
from wiedza_firmy.wiedza import Wiedza

TEMATY = [
    {"id": "temat-a", "nazwa": "Temat A", "opis": "atrapa A", "przyklady": ["przyklad A"], "osobne_uprawnienie": False},
    {"id": "temat-b", "nazwa": "Temat B", "opis": "atrapa B", "przyklady": ["przyklad B"], "osobne_uprawnienie": False},
    {"id": "temat-c", "nazwa": "Temat C", "opis": "atrapa C", "przyklady": ["przyklad C"], "osobne_uprawnienie": True},
]

# Slowa-znaczniki: kazde stoi w DOKLADNIE jednym wpisie, wiec jego obecnosc w odpowiedzi = wyciek.
WPISY = [
    NowyWpis("Zielona papuga lata nad magazynem w poniedzialki.", "temat-a", "jawne", "Anna", "2026-10-01"),
    NowyWpis("Fioletowy kalafior stoi w szafie numer siedem.", "temat-a", "wewnetrzne", "Anna", "2026-10-02"),
    NowyWpis("Pomaranczowy pingwin zna haslo do sejfu z kanapkami.", "temat-a", "wrazliwe", "Anna", "2026-10-03"),
    NowyWpis("Turkusowy zyrafa liczy kartony co piatek.", "temat-b", "jawne", "Bartek", "2026-10-04"),
    NowyWpis("Granatowy jez pilnuje drukarki w biurze.", "temat-c", "wewnetrzne", "Celina", "2026-10-05"),
]

DIM = 64


def _slowa(tekst: str) -> list[str]:
    bez = unicodedata.normalize("NFKD", tekst.lower())
    bez = "".join(c for c in bez if not unicodedata.combining(c))
    return [s for s in re.findall(r"\w+", bez) if len(s) > 2]


class WektoryAtrapa:
    """Worek slow zhaszowany do DIM wymiarow, znormalizowany. Te same slowa = bliskie wektory."""

    model = "test/atrapa"
    wymiar = DIM

    def __init__(self) -> None:
        self.wywolania = 0

    def _wektor(self, tekst: str) -> np.ndarray:
        v = np.zeros(DIM, dtype=np.float32)
        for s in _slowa(tekst):
            v[int(hashlib.sha256(s.encode()).hexdigest(), 16) % DIM] += 1.0
        n = np.linalg.norm(v)
        return v / n if n else v

    def pasaze(self, teksty: list[str]) -> np.ndarray:
        self.wywolania += 1
        return np.vstack([self._wektor(t) for t in teksty]) if teksty else np.zeros((0, DIM), dtype=np.float32)

    def pytanie(self, tekst: str) -> np.ndarray:
        return self._wektor(tekst)


@dataclass
class Srodowisko:
    baza: Baza
    wiedza: Wiedza
    zrodlo: ZrodloPlikowe
    tokeny: dict[str, str]

    def upr(self, osoba: str):
        return self.zrodlo.uprawnienia(osoba)


@pytest.fixture
def katalog(tmp_path, monkeypatch):
    monkeypatch.setenv("WIEDZA_FIRMY_HOME", str(tmp_path / "dane"))
    monkeypatch.setenv("WIEDZA_FIRMY_MODELE", str(tmp_path / "brak-modelu"))
    sciezki.katalog_danych().mkdir(parents=True)
    sciezki.plik_tematow().write_text(json.dumps(TEMATY, ensure_ascii=False), encoding="utf-8")
    return tmp_path


@pytest.fixture
def srodowisko(katalog) -> Srodowisko:
    """Osoby: admin; ania-a (A do wewnetrzne); ania-a-jawne (A tylko jawne); bez-uprawnien (zalozona,
    zero uprawnien); wszystko-b (B do wrazliwe)."""
    tokeny = {
        "admin": osoby.nowa("admin", admin=True),
        "ania-a": osoby.nowa("ania-a"),
        "ania-a-jawne": osoby.nowa("ania-a-jawne"),
        "bez-uprawnien": osoby.nowa("bez-uprawnien"),
        "wszystko-b": osoby.nowa("wszystko-b"),
    }
    osoby.nadaj("ania-a", "temat-a", "wewnetrzne")
    osoby.nadaj("ania-a-jawne", "temat-a", "jawne")
    osoby.nadaj("wszystko-b", "temat-b", "wrazliwe")
    baza = Baza(sciezki.plik_bazy(), WektoryAtrapa())
    wynik = baza.dodaj([NowyWpis(**vars(w)) for w in WPISY], dodal="test", znane_tematy={t["id"] for t in TEMATY})
    assert len(wynik.dodane) == len(WPISY)
    return Srodowisko(baza, Wiedza(baza), ZrodloPlikowe(sciezki.plik_osob()), tokeny)
