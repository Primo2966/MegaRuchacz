"""Import wsadu z Markdown: format, odmowa calosci przy bledzie, brak wskrzeszania usunietych."""

from __future__ import annotations

from pathlib import Path

import pytest

from wiedza_firmy import importuj, sciezki, tematy
from wiedza_firmy.baza import Baza
from wiedza_firmy.importuj import BladFormatu, parsuj

PRZYKLADY = Path(__file__).resolve().parents[1] / "przyklady"


def test_przyklad_wsadu_sie_parsuje():
    wpisy = parsuj((PRZYKLADY / "wsad.przyklad.md").read_text(encoding="utf-8"))
    assert len(wpisy) == 3
    assert wpisy[0].poufnosc == "jawne" and wpisy[0].autor == "Anna" and wpisy[0].temat == "przyklad-grafiki"
    assert wpisy[1].poufnosc == "wewnetrzne"
    assert wpisy[2].tresc.endswith("np. ZESTAW[0102] to składniki 01 i 02.")


@pytest.mark.parametrize("tekst, fragment", [
    ("autor: A\n- [2026-10-01] [jawne] x", "przed pierwszym"),
    ("autor: A\n## temat: t\n- [2026-10-01] x", "bez poziomu"),
    ("## temat: t\njakas luzna linia", ":2: nie rozumiem"),
    ("## Temat t\n- [2026-10-01] [jawne] x", "naglowek"),
    ("# tytul\n", "brak wpisow"),
])
def test_bledy_formatu_z_numerem_linii(tekst, fragment):
    with pytest.raises(BladFormatu, match=fragment):
        parsuj(tekst, "wsad")


def _plik(tmp_path, tekst: str) -> Path:
    p = tmp_path / "wsad.md"
    p.write_text(tekst, encoding="utf-8")
    return p


def _wpisy() -> int:
    b = Baza(sciezki.plik_bazy(), None)
    return b.statystyka()["wpisy"]


def test_import_cli_calosc_albo_nic(katalog, tmp_path, capsys):
    tematy.main(["wczytaj", str(PRZYKLADY / "tematy.przyklad.json")])
    zly = _plik(tmp_path, "autor: A\n## temat: przyklad-grafiki\n- [2026-10-01] [jawne] dobry\n"
                          "- [2026-10-01] [tajne] haslo do czegos\n")
    assert importuj.main([str(zly), "--bez-modelu"]) == 1
    assert _wpisy() == 0
    zla_data = _plik(tmp_path, "autor: A\n## temat: przyklad-grafiki\n- [2026-10-01] [jawne] dobry\n"
                               "- [2026-13-01] [jawne] zly\n")
    assert importuj.main([str(zla_data), "--bez-modelu"]) == 1
    assert _wpisy() == 0
    obcy = _plik(tmp_path, "autor: A\n## temat: nie-ma-takiego\n- [2026-10-01] [jawne] x\n")
    assert importuj.main([str(obcy), "--bez-modelu"]) == 1
    assert _wpisy() == 0


def test_import_cli_na_sucho_nic_nie_zapisuje(katalog, capsys):
    tematy.main(["wczytaj", str(PRZYKLADY / "tematy.przyklad.json")])
    assert importuj.main([str(PRZYKLADY / "wsad.przyklad.md"), "--na-sucho"]) == 0
    assert not sciezki.plik_bazy().exists()


def test_import_cli_dwa_razy_bez_duplikatow(katalog, capsys):
    tematy.main(["wczytaj", str(PRZYKLADY / "tematy.przyklad.json")])
    assert importuj.main([str(PRZYKLADY / "wsad.przyklad.md"), "--bez-modelu"]) == 0
    assert "dodano 3" in capsys.readouterr().out
    assert importuj.main([str(PRZYKLADY / "wsad.przyklad.md"), "--bez-modelu"]) == 0
    assert "dodano 0, juz byly 3" in capsys.readouterr().out
    assert _wpisy() == 3


def test_import_bez_tematow_odmowa(katalog, capsys):
    sciezki.plik_tematow().unlink()
    assert importuj.main([str(PRZYKLADY / "wsad.przyklad.md"), "--bez-modelu"]) == 1


def test_wektory_dopisywane_pozniej(katalog):
    """Wpisy zapisane bez modelu dostaja wektory przy uzupelnieniu (start serwera); inny model = od nowa."""
    from conftest import WektoryAtrapa

    tematy.main(["wczytaj", str(PRZYKLADY / "tematy.przyklad.json")])
    assert importuj.main([str(PRZYKLADY / "wsad.przyklad.md"), "--bez-modelu"]) == 0
    b = Baza(sciezki.plik_bazy(), WektoryAtrapa())
    assert b.statystyka()["bez_wektora"] == 3
    assert b.uzupelnij_wektory() == 3
    assert b.statystyka() == {"wpisy": 3, "usuniete": 0, "bez_wektora": 0, "model": "test/atrapa"}
    assert b.uzupelnij_wektory() == 0

    class InnyModel(WektoryAtrapa):
        model = "test/inny"

    b2 = Baza(sciezki.plik_bazy(), InnyModel())
    assert b2.uzupelnij_wektory() == 3
    assert b2.statystyka()["model"] == "test/inny"
