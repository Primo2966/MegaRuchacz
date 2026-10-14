"""Prawdziwy model mmlw - tylko gdy juz lezy na tym komputerze. NIGDY nie pobiera (HF_HUB_OFFLINE=1).

Gdzie szukamy: WIEDZA_FIRMY_TEST_MODELE, potem ~/.claude/lore_models i ~/.lore/lore_models (pamiec Lore).
Brak = test pominiety z powodem, nie zaliczony po cichu.
"""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from wiedza_firmy.wektory import MODEL


def _katalog_z_modelem() -> Path | None:
    from lore import db

    kandydaci = [os.environ.get("WIEDZA_FIRMY_TEST_MODELE"), Path.home() / ".claude" / "lore_models",
                 Path.home() / ".lore" / "lore_models"]
    spec = db.MODELS[MODEL]
    for k in filter(None, kandydaci):
        katalog = Path(k) / MODEL.replace("/", "--")
        if all((katalog / rel).is_file() for rel, _ in spec.files):
            return Path(k)
    return None


KATALOG = _katalog_z_modelem()
pytestmark = pytest.mark.skipif(KATALOG is None, reason="modelu mmlw nie ma na tym komputerze - test go nie pobiera")


def test_prawdziwy_model_raz_na_proces_i_szuka_po_znaczeniu(katalog, monkeypatch):
    from lore import db

    from wiedza_firmy import osoby, sciezki
    from wiedza_firmy.baza import Baza, NowyWpis
    from wiedza_firmy.uprawnienia import ZrodloPlikowe
    from wiedza_firmy.wektory import WektoryLore
    from wiedza_firmy.wiedza import Wiedza

    monkeypatch.setenv("WIEDZA_FIRMY_MODELE", str(KATALOG))
    monkeypatch.setenv("HF_HUB_OFFLINE", "1")
    w = WektoryLore()
    w.zaladuj()
    pierwszy = db.embedding_model(MODEL)
    WektoryLore().zaladuj()
    assert db.embedding_model(MODEL) is pierwszy  # drugi raz nie laduje
    assert list(db._models) == [MODEL]

    osoby.nowa("ela")
    osoby.nadaj("ela", "temat-a", "wewnetrzne")
    baza = Baza(sciezki.plik_bazy(), w)
    baza.dodaj([
        NowyWpis("Gotowe komplety grafik przenosimy do folderu GOTOWE.", "temat-a", "jawne", "Anna", "2026-10-01"),
        NowyWpis("Kot sąsiada śpi na parapecie w kuchni.", "temat-a", "jawne", "Anna", "2026-10-02"),
        NowyWpis("Gotowe obrazki produktowe kładziemy do katalogu GOTOWE.", "temat-b", "jawne", "Bartek", "2026-10-03"),
    ], dodal="test", znane_tematy={"temat-a", "temat-b"})
    wiedza = Wiedza(baza)
    upr = ZrodloPlikowe(sciezki.plik_osob()).uprawnienia("ela")
    # pytanie bez wspolnych slow z wpisem - trafic moze tylko kanal wektorowy
    odp = wiedza.szukaj_wiedzy(upr, "gdzie odkładamy skończone obrazki?", limit=2)
    assert "uwagi" not in odp, odp.get("uwagi")
    assert "folderu GOTOWE" in odp["wyniki"][0]["tresc"]
    assert all(r["temat"] == "temat-a" for r in odp["wyniki"])


# Dane, na ktorych dobrano wektory.PROGI_TRAFNOSCI (opis pomiaru przy stalej). Wymyslone - repo jest publiczne.
KALIBRACJA_WPISY = [
    "Gotowe komplety grafik przenosimy do folderu GOTOWE, robocze zostają w ROBOCZE.",
    "Trzy komplety mają błędy w oryginałach i czekają na grafika.",
    "Numery w nawiasie kwadratowym w nazwie zestawu to numery jego składników, np. ZESTAW[0102] to składniki 01 i 02.",
    "Grafiki robimy w jednym darmowym programie, nie zapisujemy plików PSD.",
    "Komputer w magazynie ma stałą nazwę w sieci i łączy się przez VPN.",
    "Tytuł oferty na portalu aukcyjnym ma limit 80 znaków; najmocniejsza fraza na początku.",
    "Paczki do magazynu zewnętrznego opisujemy numerem i dopiskiem FBA.",
    "Faktury od dostawców księgowa dostaje do 5. dnia miesiąca.",
    "Naklejki z kodem kreskowym drukujemy na drukarce etykiet w skali 180%.",
    "Numeracja serii kadzidełek nie pokrywa się z numeracją olejków.",
]
KALIBRACJA_TRAFNE = [  # (pytanie, numer wpisu, ktory ma byc pierwszy)
    ("gdzie odkładamy skończone obrazki?", 0),
    ("w jakim folderze trzymamy gotowe grafiki", 0),
    ("które komplety grafik mają błędy?", 1),
    ("co oznaczają cyfry w nawiasie w nazwie zestawu?", 2),
    ("jak rozpoznać skład zestawu po nazwie", 2),
    ("w jakim programie robimy grafiki?", 3),
    ("czy zapisywać pliki w photoshopie", 3),
    ("jak połączyć się z komputerem w magazynie", 4),
    ("ile znaków może mieć tytuł oferty", 5),
    ("jak nazywać paczki wysyłane do Amazona", 6),
    ("do kiedy przekazać faktury księgowej", 7),
    ("w jakiej skali drukować naklejki z kodem", 8),
    ("czy numer kadzidełka to ten sam numer co olejku", 9),
]
KALIBRACJA_OBCE = [
    "jaka będzie jutro pogoda w Paryżu?", "przepis na szarlotkę z kruszonką",
    "kto wygrał mistrzostwa świata w piłce nożnej 2018", "jak zainstalować bibliotekę numpy w pythonie",
    "ile kosztuje bilet do kina", "jak wymienić olej w samochodzie", "najlepsze filmy science fiction",
    "what is the capital of Australia", "jak się nazywa prezydent Francji", "co to jest fotosynteza",
    "gdzie jest najbliższa apteka", "jak długo gotować jajko na twardo",
]


def test_prawdziwy_model_prog_trafnosci(katalog, monkeypatch):
    from wiedza_firmy import sciezki
    from wiedza_firmy.baza import Baza, NowyWpis
    from wiedza_firmy.uprawnienia import Uprawnienia
    from wiedza_firmy.wektory import PROGI_TRAFNOSCI, WektoryLore
    from wiedza_firmy.wiedza import KOMUNIKAT_BRAK_USTALEN, Wiedza

    monkeypatch.setenv("WIEDZA_FIRMY_MODELE", str(KATALOG))
    monkeypatch.setenv("HF_HUB_OFFLINE", "1")
    w = WektoryLore()
    w.zaladuj()
    assert w.prog_trafnosci == PROGI_TRAFNOSCI[MODEL]
    baza = Baza(sciezki.plik_bazy(), w)
    wynik = baza.dodaj([NowyWpis(t, "temat-a", "jawne", "Anna", "2026-10-01") for t in KALIBRACJA_WPISY],
                       dodal="test", znane_tematy={"temat-a"})
    ids = wynik.dodane
    wiedza = Wiedza(baza)
    admin = Uprawnienia(osoba="admin", admin=True)
    for pytanie, nr in KALIBRACJA_TRAFNE:
        odp = wiedza.szukaj_wiedzy(admin, pytanie)
        assert odp["wyniki"] and odp["wyniki"][0]["id"] == ids[nr], (pytanie, odp)
    for pytanie in KALIBRACJA_OBCE:
        odp = wiedza.szukaj_wiedzy(admin, pytanie)
        assert odp["wyniki"] == [] and odp["komunikat"] == KOMUNIKAT_BRAK_USTALEN, (pytanie, odp["wyniki"][:1])
