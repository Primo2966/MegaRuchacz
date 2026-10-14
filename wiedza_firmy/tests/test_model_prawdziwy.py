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
