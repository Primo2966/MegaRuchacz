"""Prog trafnosci (baza.Baza._ranking): pytanie spoza tematow -> pusto z komunikatem, pasujace -> wynik.

Atrapa wektorow z conftest ma 64 wymiary i czesto zderza slowa w haszu (przypadkowe podobienstwo 0,3-0,5),
wiec tu jest jej wersja bez zderzen. Wartosc progu dla prawdziwego modelu sprawdza test_model_prawdziwy.py.
"""

from __future__ import annotations

import hashlib

import numpy as np
import pytest
from conftest import TEMATY, WPISY, WektoryAtrapa, _slowa

from wiedza_firmy import sciezki
from wiedza_firmy.baza import Baza, NowyWpis
from wiedza_firmy.wiedza import KOMUNIKAT_BRAK_USTALEN, Wiedza

WYMIAR = 1 << 16


class WektoryZProgiem(WektoryAtrapa):
    model = "test/atrapa-bez-zderzen"
    wymiar = WYMIAR
    prog_trafnosci = 0.3

    def _wektor(self, tekst: str) -> np.ndarray:
        v = np.zeros(WYMIAR, dtype=np.float32)
        for s in _slowa(tekst):
            v[int(hashlib.sha256(s.encode()).hexdigest(), 16) % WYMIAR] += 1.0
        n = np.linalg.norm(v)
        return v / n if n else v


@pytest.fixture
def prog(srodowisko):
    wektory = WektoryZProgiem()
    baza = Baza(sciezki.katalog_danych() / "prog.db", wektory)
    baza.dodaj([NowyWpis(**vars(w)) for w in WPISY], dodal="test", znane_tematy={t["id"] for t in TEMATY})
    return baza, Wiedza(baza), srodowisko


def tresci(odp: dict) -> str:
    return " ".join(w["tresc"].lower() for w in odp["wyniki"])


def test_pytanie_spoza_tematow_pusto_z_komunikatem(prog):
    baza, wiedza, sr = prog
    odp = wiedza.szukaj_wiedzy(sr.upr("admin"), "przepis na szarlotke z kruszonka")
    assert odp["wyniki"] == []
    assert odp["komunikat"] == KOMUNIKAT_BRAK_USTALEN
    # proba kontrolna: bez progu ten sam serwer oddaje wszystkie 5 wpisow jako "wyniki" (szum, ktory wycinamy)
    baza.wektoryzator.prog_trafnosci = None
    assert len(wiedza.szukaj_wiedzy(sr.upr("admin"), "przepis na szarlotke z kruszonka")["wyniki"]) == len(WPISY)


def test_pytanie_pasujace_daje_wynik(prog):
    baza, wiedza, sr = prog
    odp = wiedza.szukaj_wiedzy(sr.upr("admin"), "zielona papuga")
    assert [w["tresc"] for w in odp["wyniki"]] == [WPISY[0].tresc]
    assert "komunikat" not in odp


def test_samo_wspolne_male_slowo_nie_przechodzi(prog):
    """Zapytanie pelnotekstowe to OR slow: "co" trafia wpis "...kartony co piatek". Prog dziala i na ten kanal."""
    baza, wiedza, sr = prog
    odp = wiedza.szukaj_wiedzy(sr.upr("admin"), "co slychac u sasiadow")
    assert odp["wyniki"] == [] and odp["komunikat"] == KOMUNIKAT_BRAK_USTALEN
    baza.wektoryzator.prog_trafnosci = None  # kontrola: bez progu "co" wystarczalo
    assert "kartony" in tresci(wiedza.szukaj_wiedzy(sr.upr("admin"), "co slychac u sasiadow"))


def test_podpowiedz_bez_dostepu_tylko_ponad_progiem(prog):
    baza, wiedza, sr = prog
    odp = wiedza.szukaj_wiedzy(sr.upr("ania-a"), "co slychac u sasiadow")
    assert "bez_dostepu" not in odp
    # wpis ponad progiem w temacie bez dostepu nadal daje podpowiedz
    odp = wiedza.szukaj_wiedzy(sr.upr("ania-a"), "turkusowy zyrafa liczy kartony")
    assert odp["bez_dostepu"] == ["są wpisy w temacie Temat B, nie masz dostępu — poproś admina"]
    assert odp["komunikat"] == KOMUNIKAT_BRAK_USTALEN and "kartony" not in tresci(odp)


def test_wpis_bez_wektora_przechodzi_slowami(prog):
    baza, wiedza, sr = prog
    wektory, baza.wektoryzator = baza.wektoryzator, None
    baza.dodaj([NowyWpis("Srebrny delfin myje okna.", "temat-a", "jawne", "Anna", "2026-10-10")], dodal="test",
               znane_tematy={"temat-a"})
    baza.wektoryzator = wektory
    odp = wiedza.szukaj_wiedzy(sr.upr("admin"), "srebrny delfin")
    assert tresci(odp) == "srebrny delfin myje okna."


def test_model_bez_progu_dziala_jak_dawniej(srodowisko):
    """Atrapa z conftest nie ma prog_trafnosci - reszta testow kroku 1 chodzi bez odciecia."""
    assert getattr(srodowisko.baza.wektoryzator, "prog_trafnosci", None) is None
    odp = srodowisko.wiedza.szukaj_wiedzy(srodowisko.upr("admin"), "przepis na szarlotke z kruszonka")
    assert odp["wyniki"]
