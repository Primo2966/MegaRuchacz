"""Poziomy poufnosci, plik osob i CLI osob/tematow."""

from __future__ import annotations

import json

import pytest

from wiedza_firmy import osoby, sciezki, tematy
from wiedza_firmy.uprawnienia import POZIOMY, Uprawnienia, ZrodloPlikowe, poziomy_do, skrot_tokenu


def test_poziomy_rosna():
    assert POZIOMY == ("jawne", "wewnetrzne", "wrazliwe")
    assert poziomy_do("jawne") == ("jawne",)
    assert poziomy_do("wewnetrzne") == ("jawne", "wewnetrzne")
    assert poziomy_do("wrazliwe") == POZIOMY
    assert poziomy_do("tajne") == ()
    assert poziomy_do(None) == ()


def test_widzi():
    u = Uprawnienia("x", tematy={"a": "wewnetrzne"})
    assert u.widzi("a", "jawne") and u.widzi("a", "wewnetrzne")
    assert not u.widzi("a", "wrazliwe")
    assert not u.widzi("b", "jawne")


def test_plik_trzyma_tylko_skrot_tokenu(katalog):
    token = osoby.nowa("ela")
    surowy = sciezki.plik_osob().read_text(encoding="utf-8")
    assert token not in surowy
    assert skrot_tokenu(token) in surowy
    zrodlo = ZrodloPlikowe(sciezki.plik_osob())
    assert zrodlo.osoba_dla_tokenu(token) == "ela"
    assert zrodlo.osoba_dla_tokenu(token + "x") is None
    assert zrodlo.osoba_dla_tokenu("") is None


def test_wymiana_tokenu_uniewaznia_stary(katalog):
    stary = osoby.nowa("ela")
    nowy = osoby.wymien_token("ela")
    zrodlo = ZrodloPlikowe(sciezki.plik_osob())
    assert zrodlo.osoba_dla_tokenu(stary) is None
    assert zrodlo.osoba_dla_tokenu(nowy) == "ela"


def test_brak_pliku_osob_nikt_nie_wchodzi(katalog):
    zrodlo = ZrodloPlikowe(sciezki.plik_osob())
    assert zrodlo.osoba_dla_tokenu("cokolwiek") is None
    assert "nie ma pliku" in zrodlo.blad


def test_uszkodzony_plik_osob_nikt_nie_wchodzi(katalog):
    token = osoby.nowa("ela", admin=True)
    zrodlo = ZrodloPlikowe(sciezki.plik_osob())
    assert zrodlo.osoba_dla_tokenu(token) == "ela"
    sciezki.plik_osob().write_text("{ zepsuty", encoding="utf-8")
    assert zrodlo.osoba_dla_tokenu(token) is None
    assert zrodlo.blad


def test_zmiana_pliku_dziala_bez_restartu(katalog):
    osoby.nowa("ela")
    zrodlo = ZrodloPlikowe(sciezki.plik_osob())
    assert zrodlo.uprawnienia("ela").puste
    osoby.nadaj("ela", "temat-a", "jawne")
    assert zrodlo.uprawnienia("ela").poziomy("temat-a") == ("jawne",)
    osoby.odbierz("ela", "temat-a")
    assert zrodlo.uprawnienia("ela").puste


def test_zly_poziom_w_pliku_jest_pomijany(katalog):
    osoby.nowa("ela")
    dane = json.loads(sciezki.plik_osob().read_text(encoding="utf-8"))
    dane["ela"]["uprawnienia"] = {"temat-a": "tajne", "temat-b": "jawne"}
    sciezki.plik_osob().write_text(json.dumps(dane), encoding="utf-8")
    zrodlo = ZrodloPlikowe(sciezki.plik_osob())
    upr = zrodlo.uprawnienia("ela")
    assert upr.poziomy("temat-a") == ()
    assert upr.poziomy("temat-b") == ("jawne",)
    assert "tajne" in zrodlo.blad


def test_nadaj_sprawdza_temat_i_poziom(katalog):
    osoby.nowa("ela")
    with pytest.raises(osoby.BladOsob):
        osoby.nadaj("ela", "temat-nieistniejacy", "jawne")
    with pytest.raises(osoby.BladOsob):
        osoby.nadaj("ela", "temat-a", "tajne")
    with pytest.raises(osoby.BladOsob):
        osoby.nadaj("ktos-obcy", "temat-a", "jawne")


def test_nowa_osoba_dwa_razy_odmowa(katalog):
    osoby.nowa("ela")
    with pytest.raises(osoby.BladOsob):
        osoby.nowa("ela")


def test_cli_osoby_wypisuje_token_raz(katalog, capsys):
    assert osoby.main(["nowa", "ela", "--admin"]) == 0
    token = capsys.readouterr().out.strip().splitlines()[-1]
    assert ZrodloPlikowe(sciezki.plik_osob()).osoba_dla_tokenu(token) == "ela"
    assert osoby.main(["lista"]) == 0
    assert token not in capsys.readouterr().out


def test_cli_tematy_wczytuje_przyklad(katalog, capsys):
    from pathlib import Path

    przyklad = Path(__file__).resolve().parents[1] / "przyklady" / "tematy.przyklad.json"
    assert tematy.main(["wczytaj", str(przyklad)]) == 0
    assert {t.id for t in tematy.wczytaj()} == {"przyklad-produkty", "przyklad-grafiki", "przyklad-it"}


@pytest.mark.parametrize("zly", [
    [],
    [{"id": "A", "nazwa": "x", "opis": "x", "przyklady": ["x"]}],
    [{"id": "a", "nazwa": "", "opis": "x", "przyklady": ["x"]}],
    [{"id": "a", "nazwa": "x", "opis": "x", "przyklady": []}],
    [{"id": "a", "nazwa": "x", "opis": "x", "przyklady": ["x"], "osobne_uprawnienie": "tak"}],
    [{"id": "a", "nazwa": "x", "opis": "x", "przyklady": ["x"]}, {"id": "a", "nazwa": "y", "opis": "y", "przyklady": ["y"]}],
])
def test_zle_tematy_odmowa_bez_zapisu(katalog, tmp_path, zly):
    przed = sciezki.plik_tematow().read_bytes()
    plik = tmp_path / "zle.json"
    plik.write_text(json.dumps(zly), encoding="utf-8")
    assert tematy.main(["wczytaj", str(plik)]) == 1
    assert sciezki.plik_tematow().read_bytes() == przed
