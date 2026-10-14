"""Serwer HTTP: proba negatywna (3) - brak i zly token = 401 - oraz osoba z tokenu przy kazdym zadaniu.

Klient testowy Starlette rozmawia z ta sama aplikacja ASGI, ktora uruchamia uvicorn (bez sieci).
"""

from __future__ import annotations

import json

import pytest
from starlette.testclient import TestClient

from wiedza_firmy import osoby
from wiedza_firmy.serwer import aplikacja
from wiedza_firmy.uprawnienia import KOMUNIKAT_BRAK_UPRAWNIEN

ADRES = "http://127.0.0.1:8766"
NAGLOWKI = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json",
            "MCP-Protocol-Version": "2025-06-18"}


@pytest.fixture
def klient(srodowisko):
    with TestClient(aplikacja(srodowisko.wiedza, srodowisko.zrodlo, host="127.0.0.1"), base_url=ADRES) as k:
        yield k


def zadanie(klient, token, metoda="tools/list", params=None, autoryzacja=None):
    naglowki = dict(NAGLOWKI)
    if autoryzacja is not None:
        naglowki["Authorization"] = autoryzacja
    elif token is not None:
        naglowki["Authorization"] = f"Bearer {token}"
    return klient.post("/mcp", headers=naglowki,
                       json={"jsonrpc": "2.0", "id": 1, "method": metoda, "params": params or {}})


def narzedzie(klient, token, nazwa, **argumenty) -> dict:
    r = zadanie(klient, token, "tools/call", {"name": nazwa, "arguments": argumenty})
    assert r.status_code == 200, r.text
    wynik = r.json()["result"]
    assert not wynik.get("isError"), wynik
    assert len(wynik["content"]) == 1
    return json.loads(wynik["content"][0]["text"])


# ---------------------------------------------------------------- (3) 401

@pytest.mark.parametrize("autoryzacja", [
    None,                       # brak naglowka
    "Bearer ",                  # pusty token
    "Bearer zly-token-123",     # nieznany token
    "Basic YWRtaW46YWRtaW4=",   # inny schemat
])
def test_3_bez_tokenu_i_ze_zlym_tokenem_401(klient, autoryzacja):
    naglowki = dict(NAGLOWKI)
    if autoryzacja is not None:
        naglowki["Authorization"] = autoryzacja
    for metoda, params in (("tools/list", {}), ("tools/call", {"name": "szukaj_wiedzy", "arguments": {"pytanie": "papuga"}})):
        r = klient.post("/mcp", headers=naglowki, json={"jsonrpc": "2.0", "id": 1, "method": metoda, "params": params})
        assert r.status_code == 401, (autoryzacja, metoda, r.text)
        assert "papuga" not in r.text.lower()
        assert r.headers["www-authenticate"].startswith("Bearer")


def test_3_dobry_token_w_zlym_schemacie_401(klient, srodowisko):
    token = srodowisko.tokeny["admin"]
    for autoryzacja in (token, f"Basic {token}", f"Token {token}", f"Bearer{token}"):
        assert zadanie(klient, None, autoryzacja=autoryzacja).status_code == 401, autoryzacja


def test_3_inne_sciezki_tez_401_bez_tokenu(klient):
    for sciezka in ("/", "/mcp/", "/cokolwiek"):
        assert klient.get(sciezka).status_code == 401


def test_3_token_usunietej_osoby_401(klient, srodowisko):
    token = srodowisko.tokeny["ania-a"]
    assert zadanie(klient, token).status_code == 200
    osoby.usun("ania-a")
    assert zadanie(klient, token).status_code == 401


def test_dobry_token_widzi_narzedzia(klient, srodowisko):
    r = zadanie(klient, srodowisko.tokeny["ania-a"])
    assert r.status_code == 200
    nazwy = {t["name"] for t in r.json()["result"]["tools"]}
    assert nazwy == {"szukaj_wiedzy", "tematy", "moje_uprawnienia", "dodaj_wpis", "usun_wpis"}


# ---------------------------------------------------------------- osoba z tokenu, zadanie po zadaniu

def test_1_przez_http_temat_a_nie_widzi_b(klient, srodowisko):
    odp = narzedzie(klient, srodowisko.tokeny["ania-a"], "szukaj_wiedzy", pytanie="Turkusowy zyrafa liczy kartony co piatek")
    assert "turkusowy" not in json.dumps(odp, ensure_ascii=False).lower()
    assert all(w["temat"] == "temat-a" for w in odp["wyniki"])


def test_2_przez_http_wewnetrzne_nie_widzi_wrazliwego(klient, srodowisko):
    odp = narzedzie(klient, srodowisko.tokeny["ania-a"], "szukaj_wiedzy", pytanie="Pomaranczowy pingwin zna haslo do sejfu")
    assert "pingwin" not in json.dumps(odp, ensure_ascii=False).lower()


def test_4_przez_http_bez_uprawnien_nic(klient, srodowisko):
    token = srodowisko.tokeny["bez-uprawnien"]
    assert narzedzie(klient, token, "szukaj_wiedzy", pytanie="zielona papuga") == {"wyniki": [], "komunikat": KOMUNIKAT_BRAK_UPRAWNIEN}
    assert narzedzie(klient, token, "tematy") == {"tematy": [], "komunikat": KOMUNIKAT_BRAK_UPRAWNIEN}
    assert narzedzie(klient, token, "moje_uprawnienia")["komunikat"] == KOMUNIKAT_BRAK_UPRAWNIEN


def test_6_przez_http_nie_admin_nie_zapisuje_a_admin_tak(klient, srodowisko):
    zwykly, admin = srodowisko.tokeny["ania-a"], srodowisko.tokeny["admin"]
    assert "blad" in narzedzie(klient, zwykly, "dodaj_wpis", tresc="Srebrny delfin", temat="temat-a", poufnosc="jawne")
    assert "blad" in narzedzie(klient, zwykly, "usun_wpis", id=1, powod="chce")
    dodany = narzedzie(klient, admin, "dodaj_wpis", tresc="Srebrny delfin myje okna", temat="temat-a", poufnosc="jawne")
    assert "dodano" in dodany
    # (5) przez HTTP: usuniety znika
    assert narzedzie(klient, admin, "usun_wpis", id=dodany["dodano"], powod="test")["usunieto"] == dodany["dodano"]
    assert "delfin" not in json.dumps(narzedzie(klient, admin, "szukaj_wiedzy", pytanie="srebrny delfin"), ensure_ascii=False).lower()


def test_osoba_liczy_sie_dla_kazdego_zadania_osobno(klient, srodowisko):
    """Na przemian admin i osoba bez uprawnien - nic nie przechodzi z jednego zadania na drugie."""
    for _ in range(3):
        admin = narzedzie(klient, srodowisko.tokeny["admin"], "moje_uprawnienia")
        nikt = narzedzie(klient, srodowisko.tokeny["bez-uprawnien"], "szukaj_wiedzy", pytanie="papuga")
        assert admin["osoba"] == "admin" and admin["admin"] is True
        assert nikt["wyniki"] == []


def test_naglowek_host_spoza_listy_odrzucony(srodowisko):
    """Na 127.0.0.1 SDK wlacza ochrone przed DNS rebinding - obcy Host nie przechodzi nawet z tokenem."""
    with TestClient(aplikacja(srodowisko.wiedza, srodowisko.zrodlo, host="127.0.0.1"), base_url="http://zly-host") as k:
        assert zadanie(k, srodowisko.tokeny["admin"]).status_code == 421
