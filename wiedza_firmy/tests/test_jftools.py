"""Krok 2: uprawnienia i tematy z JFTools - przez prawdziwe HTTP do atrapy wtyczki na 127.0.0.1.

Proby negatywne: komputer pending / blocked / nieznany -> zero; zly sekret (403) -> zero, nie "wszystko";
JFTools lezy przy pustej pamieci -> zero; lezy przy pamieci -> ostatnio znane z ostrzezeniem; odpowiedz
o innym komputerze, nieznany status, "admin": true z panelu -> nic wiecej niz granty. Przelacznik wylaczony
-> dokladnie ZrodloPlikowe z kroku 1 (cala reszta testow chodzi na nim).
"""

from __future__ import annotations

import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

import pytest

from wiedza_firmy import jftools, osoby, sciezki
from wiedza_firmy.jftools import (KOMUNIKAT_BEZ_KOMPUTERA, KOMUNIKAT_BLOCKED, KOMUNIKAT_NIEZNANY, KOMUNIKAT_PENDING,
                                  TematyJFTools, ZrodloJFTools)
from wiedza_firmy.uprawnienia import KOMUNIKAT_BRAK_UPRAWNIEN, ZrodloPlikowe
from wiedza_firmy.wiedza import Wiedza

SEKRET = "sekret-atrapy-123"


class AtrapaJFTools:
    """Wtyczka JFTools na niby: knowledge-permissions, knowledge-topics i keys, sprawdza x-webhook-secret.
    Ksztalty jak we wtyczce 84b58e6 (raport K3-Z2): keys = {computers: [{id, name, status, publicKey}]}."""

    def __init__(self) -> None:
        self.komputery: dict[str, object] = {}   # id -> odpowiedz JSON albo kod HTTP (int)
        self.tematy: object = []
        self.klucze: object = {"computers": []}  # odpowiedz keys albo kod HTTP (int)
        self.sekret = SEKRET
        self.zwloka_s = 0.0
        self.zapytania: list[tuple[str, dict, str | None]] = []
        atrapa = self

        class Obsluga(BaseHTTPRequestHandler):
            def log_message(self, *args) -> None:  # bez smiecenia w wyjsciu testow
                pass

            def do_GET(self) -> None:
                u = urlparse(self.path)
                parametry = {k: v[0] for k, v in parse_qs(u.query).items()}
                atrapa.zapytania.append((u.path, parametry, self.headers.get("x-webhook-secret")))
                if atrapa.zwloka_s:
                    time.sleep(atrapa.zwloka_s)
                if self.headers.get("x-webhook-secret") != atrapa.sekret:
                    return self._odpowiedz(403, {"error": "forbidden"})
                if u.path.endswith("/knowledge-permissions"):
                    komputer = parametry.get("computer", "")
                    # jak wtyczka (src/public.ts): zly parametr 400, nieznany komputer 404
                    dane = atrapa.komputery.get(komputer, 404) if jftools.ID_KOMPUTERA.match(komputer) else 400
                elif u.path.endswith("/knowledge-topics"):
                    dane = atrapa.tematy
                elif u.path.endswith("/keys"):
                    dane = atrapa.klucze
                else:
                    dane = 404
                if isinstance(dane, int):
                    return self._odpowiedz(dane, {"error": "x"})
                self._odpowiedz(200, dane)

            def _odpowiedz(self, kod: int, dane: object) -> None:
                cialo = json.dumps(dane).encode("utf-8")
                self.send_response(kod)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(cialo)))
                self.end_headers()
                self.wfile.write(cialo)

        self.serwer = ThreadingHTTPServer(("127.0.0.1", 0), Obsluga)
        self.url = f"http://127.0.0.1:{self.serwer.server_address[1]}/api/public/mcp-ecommerce-sterowanie"
        self._watek = threading.Thread(target=self.serwer.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True)
        self._watek.start()

    def zatrzymaj(self) -> None:
        if self.serwer is not None:
            self.serwer.shutdown()
            self.serwer.server_close()
            self.serwer = None

    def ile(self, sciezka: str) -> int:
        return sum(1 for p, _, _ in self.zapytania if p.endswith(sciezka))


def odpowiedz(id_: str, status: str = "active", grants: dict | None = None, admin: bool = False, nazwa="PC Eli",
              owner: object = None):
    """knowledge-permissions jak we wtyczce 84b58e6: owner = {email, name} (pola moga byc null) albo null."""
    return {"computer": {"id": id_, "name": nazwa, "status": status}, "owner": owner, "admin": admin,
            "grants": grants or {}}


class Zegar:
    def __init__(self) -> None:
        self.t = 1_800_000_000.0

    def __call__(self) -> float:
        return self.t


@pytest.fixture
def atrapa():
    a = AtrapaJFTools()
    yield a
    a.zatrzymaj()


@pytest.fixture
def jft(srodowisko, atrapa):
    """srodowisko z conftest + osoba ela na komputerze 12 + zrodlo JFTools z udawanym zegarem."""
    srodowisko.tokeny["ela"] = osoby.nowa("ela")
    osoby.ustaw_komputer("ela", "12")
    osoby.ustaw_komputer("ania-a", "13")  # ma w pliku temat-a, ale w trybie JFTools plik nie daje uprawnien
    zegar = Zegar()
    zrodlo = ZrodloJFTools(sciezki.plik_osob(), atrapa.url, SEKRET, limit_s=0.5, zegar=zegar)
    return srodowisko, atrapa, zrodlo, zegar


def tekst(odp: dict) -> str:
    return json.dumps(odp, ensure_ascii=False).lower()


# ---------------------------------------------------------------- aktywny komputer

def test_aktywny_komputer_dostaje_granty_z_jftools(jft):
    sr, atrapa, zrodlo, _ = jft
    atrapa.komputery["12"] = odpowiedz("12", grants={"temat-a": "wewnetrzne"})
    upr = zrodlo.uprawnienia("ela")
    assert dict(upr.tematy) == {"temat-a": "wewnetrzne"} and not upr.admin
    odp = sr.wiedza.szukaj_wiedzy(upr, "zielona papuga fioletowy kalafior pomaranczowy pingwin turkusowy", limit=10)
    assert {w["poufnosc"] for w in odp["wyniki"]} == {"jawne", "wewnetrzne"}
    for znacznik in ("pingwin", "turkusowy"):
        assert znacznik not in " ".join(w["tresc"].lower() for w in odp["wyniki"])
    moje = sr.wiedza.moje_uprawnienia(upr)
    assert "JFTools" in moje["zrodlo_uprawnien"] and "PC Eli" in moje["zrodlo_uprawnien"]
    # zapytanie poszlo z sekretem i id komputera
    assert atrapa.zapytania[-1] == ("/api/public/mcp-ecommerce-sterowanie/knowledge-permissions", {"computer": "12"},
                                    SEKRET)


def test_plik_nie_daje_uprawnien_w_trybie_jftools(jft):
    sr, atrapa, zrodlo, _ = jft
    atrapa.komputery["13"] = odpowiedz("13", grants={})
    upr = zrodlo.uprawnienia("ania-a")  # w osoby.json: temat-a do wewnetrzne
    assert upr.puste
    assert sr.wiedza.szukaj_wiedzy(upr, "zielona papuga")["wyniki"] == []


def test_admin_z_jftools_nie_robi_admina_a_zly_poziom_wypada(jft):
    sr, atrapa, zrodlo, _ = jft
    atrapa.komputery["12"] = odpowiedz("12", admin=True, grants={"temat-a": "tajne", "temat-b": "wszystko",
                                                                 "temat-c": "jawne"})
    upr = zrodlo.uprawnienia("ela")
    assert upr.admin is False
    assert dict(upr.tematy) == {"temat-c": "jawne"}
    assert sr.wiedza.usun_wpis(upr, 1, "chce") == {"blad": "Tylko admin może usuwać wpisy."}


def test_admin_lokalny_i_bez_komputera_nie_pytaja_jftools(jft):
    sr, atrapa, zrodlo, _ = jft
    assert zrodlo.uprawnienia("admin").admin is True
    upr = zrodlo.uprawnienia("bez-uprawnien")
    assert upr.puste and upr.komunikat == KOMUNIKAT_BEZ_KOMPUTERA
    assert sr.wiedza.szukaj_wiedzy(upr, "zielona papuga") == {"wyniki": [], "komunikat": KOMUNIKAT_BEZ_KOMPUTERA}
    assert atrapa.ile("/knowledge-permissions") == 0
    # token nadal tylko z pliku
    assert zrodlo.osoba_dla_tokenu(sr.tokeny["ela"]) == "ela"
    assert zrodlo.osoba_dla_tokenu("zly-token") is None


# ---------------------------------------------------------------- status inny niz active = zero

@pytest.mark.parametrize("status,komunikat", [("pending", KOMUNIKAT_PENDING), ("blocked", KOMUNIKAT_BLOCKED)])
def test_komputer_nieaktywny_zero_nawet_z_grantami(jft, status, komunikat):
    sr, atrapa, zrodlo, _ = jft
    atrapa.komputery["12"] = odpowiedz("12", status=status, grants={"temat-a": "wrazliwe", "temat-b": "wrazliwe"})
    upr = zrodlo.uprawnienia("ela")
    assert upr.puste and upr.komunikat == komunikat
    for pytanie in ("zielona papuga", "pomaranczowy pingwin", "turkusowy zyrafa"):
        assert sr.wiedza.szukaj_wiedzy(upr, pytanie) == {"wyniki": [], "komunikat": komunikat}
    assert sr.wiedza.tematy(upr)["tematy"] == []
    assert sr.wiedza.moje_uprawnienia(upr)["uprawnienia"] == []


def test_komputer_nieznany_w_jftools_zero(jft):
    sr, atrapa, zrodlo, _ = jft
    upr = zrodlo.uprawnienia("ela")  # atrapa nie zna komputera 12 -> 404
    assert upr.puste and upr.komunikat == KOMUNIKAT_NIEZNANY and upr.ostrzezenie is None


def test_usuniety_komputer_404_i_zle_id_400_to_zero_a_nie_pamiec(jft):
    sr, atrapa, zrodlo, zegar = jft
    atrapa.komputery["12"] = odpowiedz("12", grants={"temat-a": "wrazliwe"})
    assert not zrodlo.uprawnienia("ela").puste
    del atrapa.komputery["12"]  # admin usunal komputer w panelu
    zegar.t += jftools.WAZNOSC_S + 1
    upr = zrodlo.uprawnienia("ela")
    assert upr.puste and upr.komunikat == KOMUNIKAT_NIEZNANY and upr.ostrzezenie is None
    # id, ktorego wtyczka nie przyjmuje (wpisane recznie w osoby.json) -> 400 -> zero, tez bez pamieci
    dane = json.loads(sciezki.plik_osob().read_text(encoding="utf-8"))
    dane["ela"]["komputer"] = "PC-Eli"
    sciezki.plik_osob().write_text(json.dumps(dane), encoding="utf-8")
    upr = zrodlo.uprawnienia("ela")
    assert upr.puste and upr.komunikat == jftools.KOMUNIKAT_ZLE_ID and upr.ostrzezenie is None


@pytest.mark.parametrize("zla", [
    {"computer": {"id": "99", "status": "active"}, "grants": {"temat-a": "wrazliwe"}},   # inny komputer
    {"computer": {"id": "12", "status": "admin"}, "grants": {"temat-a": "wrazliwe"}},    # nieznany status
    {"computer": {"id": "12"}, "grants": {"temat-a": "wrazliwe"}},                        # bez statusu
    {"status": "active", "grants": {"temat-a": "wrazliwe"}},                              # bez obiektu computer
    {"computer": {"id": "12", "status": "active"}, "grants": [["temat-a", "wrazliwe"]]}, # grants nie obiekt
    ["active"],
])
def test_zla_odpowiedz_jftools_zero(jft, zla, capsys):
    sr, atrapa, zrodlo, _ = jft
    atrapa.komputery["12"] = zla
    upr = zrodlo.uprawnienia("ela")
    assert upr.puste and not upr.admin
    assert "Nie da się teraz sprawdzić uprawnień w JFTools" in upr.komunikat
    assert "BLAD JFTools" in capsys.readouterr().err


# ---------------------------------------------------------------- zly sekret i awarie

def test_zly_sekret_403_zero_a_nie_wszystko(jft, capsys):
    sr, atrapa, zrodlo, _ = jft
    atrapa.komputery["12"] = odpowiedz("12", grants={"temat-a": "wrazliwe"})
    atrapa.sekret = "inny-sekret"
    upr = zrodlo.uprawnienia("ela")
    assert upr.puste and not upr.admin
    assert "HTTP 403" in upr.komunikat
    odp = sr.wiedza.szukaj_wiedzy(upr, "zielona papuga")
    assert odp["wyniki"] == [] and "HTTP 403" in odp["komunikat"]
    assert "papuga" not in tekst({k: v for k, v in odp.items() if k != "komunikat"})
    assert "BLAD JFTools" in capsys.readouterr().err
    assert "HTTP 403" in zrodlo.stan()["ostatni_blad"]


def test_jftools_lezy_pusta_pamiec_zero(jft, capsys):
    sr, atrapa, zrodlo, _ = jft
    atrapa.zatrzymaj()
    upr = zrodlo.uprawnienia("ela")
    assert upr.puste and "Nie da się teraz sprawdzić uprawnień w JFTools" in upr.komunikat
    moje = sr.wiedza.moje_uprawnienia(upr)
    assert moje["uprawnienia"] == [] and "JFTools" in moje["komunikat"]
    assert moje["komunikat"] != KOMUNIKAT_BRAK_UPRAWNIEN
    assert "BLAD JFTools" in capsys.readouterr().err


def test_jftools_lezy_przy_pamieci_ostatnio_znane_z_ostrzezeniem(jft, capsys):
    sr, atrapa, zrodlo, zegar = jft
    atrapa.komputery["12"] = odpowiedz("12", grants={"temat-a": "jawne"})
    assert dict(zrodlo.uprawnienia("ela").tematy) == {"temat-a": "jawne"}
    kiedy = jftools._godzina(zegar.t)
    zegar.t += jftools.WAZNOSC_S + 1  # pamiec wygasla, trzeba zapytac
    atrapa.zatrzymaj()
    upr = zrodlo.uprawnienia("ela")
    assert dict(upr.tematy) == {"temat-a": "jawne"}
    assert upr.ostrzezenie.startswith(f"uprawnienia z pamięci z {kiedy}")
    moje = sr.wiedza.moje_uprawnienia(upr)
    assert moje["zrodlo_uprawnien"].startswith(f"uprawnienia z pamięci z {kiedy}")
    assert moje["uprawnienia"][0]["temat"] == "temat-a"
    odp = sr.wiedza.szukaj_wiedzy(upr, "zielona papuga")
    assert "papuga" in odp["wyniki"][0]["tresc"].lower()
    assert any(u.startswith("uprawnienia z pamięci") for u in odp["uwagi"])
    assert "BLAD JFTools" in capsys.readouterr().err


def test_pamiec_starsza_niz_limit_zero(jft):
    sr, atrapa, zrodlo, zegar = jft
    atrapa.komputery["12"] = odpowiedz("12", grants={"temat-a": "jawne"})
    assert not zrodlo.uprawnienia("ela").puste
    zegar.t += jftools.PAMIEC_MAX_S + 1
    atrapa.zatrzymaj()
    upr = zrodlo.uprawnienia("ela")
    assert upr.puste and "Nie da się teraz sprawdzić" in upr.komunikat


def test_limit_czasu_zapytania(jft):
    sr, atrapa, zrodlo, _ = jft
    atrapa.komputery["12"] = odpowiedz("12", grants={"temat-a": "jawne"})
    atrapa.zwloka_s = 2.0
    t0 = time.monotonic()
    upr = zrodlo.uprawnienia("ela")
    assert time.monotonic() - t0 < 1.8
    assert upr.puste


# ---------------------------------------------------------------- pamiec

def test_pamiec_10_min_dla_aktywnego_1_min_dla_czekajacego(jft):
    sr, atrapa, zrodlo, zegar = jft
    atrapa.komputery["12"] = odpowiedz("12", status="pending")
    assert zrodlo.uprawnienia("ela").puste
    atrapa.komputery["12"] = odpowiedz("12", grants={"temat-a": "jawne"})  # admin nadal uprawnienia
    zegar.t += 30
    assert zrodlo.uprawnienia("ela").puste           # jeszcze z pamieci
    zegar.t += 31
    assert not zrodlo.uprawnienia("ela").puste       # po minucie - swiezo
    n = atrapa.ile("/knowledge-permissions")
    zegar.t += jftools.WAZNOSC_S - 1
    zrodlo.uprawnienia("ela")
    assert atrapa.ile("/knowledge-permissions") == n  # aktywny: 10 min bez pytania
    zegar.t += 2
    zrodlo.uprawnienia("ela")
    assert atrapa.ile("/knowledge-permissions") == n + 1


def test_po_bledzie_przerwa_bez_ponawiania(jft):
    sr, atrapa, zrodlo, zegar = jft
    atrapa.sekret = "inny"
    zrodlo.uprawnienia("ela")
    zrodlo.uprawnienia("ela")
    assert atrapa.ile("/knowledge-permissions") == 1
    zegar.t += jftools.PRZERWA_PO_BLEDZIE_S + 1
    atrapa.sekret = SEKRET
    atrapa.komputery["12"] = odpowiedz("12", grants={"temat-a": "jawne"})
    assert not zrodlo.uprawnienia("ela").puste
    assert atrapa.ile("/knowledge-permissions") == 2


# ---------------------------------------------------------------- tematy

TEMATY_JFT = [
    {"id": "temat-a", "nazwa": "Temat A z panelu", "opis": "opis z JFTools", "przyklady": ["p"],
     "osobne_uprawnienie": False, "kolejnosc": 1},
    {"id": "temat-x", "nazwa": "Temat X", "opis": "", "przyklady": [], "osobne_uprawnienie": True, "kolejnosc": 2},
    {"id": "ZLE ID", "nazwa": "zly", "kolejnosc": 3},
]


def test_tematy_z_jftools_i_zastepstwa(jft, capsys):
    sr, atrapa, zrodlo, zegar = jft
    atrapa.tematy = TEMATY_JFT
    zt = TematyJFTools(atrapa.url, SEKRET, zegar=zegar, limit_s=0.5)
    wiedza = Wiedza(sr.baza, zrodlo_tematow=zt)
    admin = zrodlo.uprawnienia("admin")
    odp = wiedza.tematy(admin)
    assert {t["id"]: t["nazwa"] for t in odp["tematy"]} == {"temat-a": "Temat A z panelu", "temat-x": "Temat X"}
    assert "uwagi" not in odp
    assert "ZLE ID" in capsys.readouterr().err
    # dodawanie zna tematy z JFTools: temat-x jest, temat-b (tylko w pliku) nie
    assert "dodano" in wiedza.dodaj_wpis(admin, "Nowa rzecz w X", "temat-x", "jawne")
    assert "nieznany temat" in wiedza.dodaj_wpis(admin, "Nowa rzecz w B", "temat-b", "jawne")["blad"]
    # pamiec 10 min
    zegar.t += 60
    wiedza.tematy(admin)
    assert atrapa.ile("/knowledge-topics") == 1
    # JFTools lezy -> ostatnia znana lista z uwaga
    zegar.t += jftools.WAZNOSC_S
    atrapa.zatrzymaj()
    odp = wiedza.tematy(admin)
    assert {t["id"] for t in odp["tematy"]} == {"temat-a", "temat-x"}
    assert odp["uwagi"][0].startswith("lista tematów z pamięci z")
    assert "BLAD JFTools (tematy)" in capsys.readouterr().err


def test_tematy_nie_tablica_to_awaria_i_tematy_json(jft):
    sr, atrapa, zrodlo, zegar = jft
    atrapa.tematy = {"topics": TEMATY_JFT}
    wiedza = Wiedza(sr.baza, zrodlo_tematow=TematyJFTools(atrapa.url, SEKRET, zegar=zegar, limit_s=0.5))
    odp = wiedza.tematy(zrodlo.uprawnienia("admin"))
    assert {t["id"] for t in odp["tematy"]} == {"temat-a", "temat-b", "temat-c"}
    assert "oczekiwana lista tematow" in odp["uwagi"][0]


def test_tematy_jftools_lezy_bez_pamieci_tematy_json(jft):
    sr, atrapa, zrodlo, zegar = jft
    atrapa.sekret = "inny"  # 403
    wiedza = Wiedza(sr.baza, zrodlo_tematow=TematyJFTools(atrapa.url, SEKRET, zegar=zegar, limit_s=0.5))
    odp = wiedza.tematy(zrodlo.uprawnienia("admin"))
    assert {t["id"] for t in odp["tematy"]} == {"temat-a", "temat-b", "temat-c"}
    assert odp["uwagi"] == ["lista tematów z pliku serwera — JFTools nie odpowiada (HTTP 403)"]


# ---------------------------------------------------------------- przelacznik

def test_przelacznik_domyslnie_wylaczony_to_zrodlo_plikowe(katalog):
    for environ in ({}, {jftools.ENV_TRYB: ""}, {jftools.ENV_TRYB: "plik"},
                    {jftools.ENV_URL: "http://x", jftools.ENV_SEKRET: "s"}):
        zrodlo, tematy = jftools.zbuduj_zrodla(environ)
        assert type(zrodlo) is ZrodloPlikowe and tematy is None, environ


@pytest.mark.parametrize("environ", [
    {jftools.ENV_TRYB: "jftools"},                                            # bez sekretu
    {jftools.ENV_TRYB: "jftool", jftools.ENV_SEKRET: "s"},                    # literowka - nie wracamy po cichu do pliku
    {jftools.ENV_TRYB: "jftools", jftools.ENV_SEKRET: "s", jftools.ENV_URL: "tools.jfinvesting.pl"},
])
def test_przelacznik_zle_ustawienia_odmowa_startu(katalog, environ):
    with pytest.raises(jftools.BladUstawien):
        jftools.zbuduj_zrodla(environ)


def test_przelacznik_jftools_adresy(katalog):
    zrodlo, tematy = jftools.zbuduj_zrodla({jftools.ENV_TRYB: "JFTools", jftools.ENV_SEKRET: "s"})
    assert isinstance(zrodlo, ZrodloJFTools)
    assert zrodlo.url == "https://tools.jfinvesting.pl/api/public/mcp-ecommerce-sterowanie/knowledge-permissions"
    assert tematy.url == "https://tools.jfinvesting.pl/api/public/mcp-ecommerce-sterowanie/knowledge-topics"
    # adres skopiowany z ecommerce-helper (z /permissions) tez dziala
    zrodlo, _ = jftools.zbuduj_zrodla({jftools.ENV_TRYB: "jftools", jftools.ENV_SEKRET: "s",
                                       jftools.ENV_URL: "https://h/api/public/w/permissions/"})
    assert zrodlo.url == "https://h/api/public/w/knowledge-permissions"


def test_serwer_nie_startuje_przy_zlych_ustawieniach(katalog, monkeypatch, capsys):
    from wiedza_firmy import serwer

    def start(*a, **k):  # gdyby odmowa nie zadzialala - padnij od razu, zamiast ladowac model i sluchac na porcie
        raise AssertionError("serwer ruszyl mimo zlych ustawien")

    monkeypatch.setattr(serwer, "WektoryLore", start)
    monkeypatch.setenv(jftools.ENV_TRYB, "jftools")
    monkeypatch.delenv(jftools.ENV_SEKRET, raising=False)
    assert serwer.main(["--port", "1"]) == 2
    assert "serwer nie startuje" in capsys.readouterr().err


# ---------------------------------------------------------------- HTTP: caly serwer z JFTools

def test_serwer_http_z_jftools_pending_i_aktywny(jft):
    from starlette.testclient import TestClient

    from test_serwer_http import ADRES, narzedzie, zadanie
    from wiedza_firmy.serwer import aplikacja

    sr, atrapa, zrodlo, zegar = jft
    atrapa.komputery["12"] = odpowiedz("12", status="pending", grants={"temat-a": "wrazliwe"})
    with TestClient(aplikacja(sr.wiedza, zrodlo, host="127.0.0.1"), base_url=ADRES) as k:
        assert zadanie(k, "zly-token").status_code == 401
        odp = narzedzie(k, sr.tokeny["ela"], "szukaj_wiedzy", pytanie="zielona papuga")
        assert odp == {"wyniki": [], "komunikat": KOMUNIKAT_PENDING}
        atrapa.komputery["12"] = odpowiedz("12", grants={"temat-a": "jawne"})
        zegar.t += jftools.WAZNOSC_BEZ_DOSTEPU_S + 1
        odp = narzedzie(k, sr.tokeny["ela"], "szukaj_wiedzy", pytanie="zielona papuga")
        assert "papuga" in odp["wyniki"][0]["tresc"].lower()
        moje = narzedzie(k, sr.tokeny["ela"], "moje_uprawnienia")
        assert moje["uprawnienia"][0]["do_poziomu"] == "jawne" and "JFTools" in moje["zrodlo_uprawnien"]


# ---------------------------------------------------------------- CLI i plik osob

def test_cli_ustaw_komputer(katalog, capsys):
    osoby.nowa("ela")
    assert osoby.main(["ustaw-komputer", "ela", "12"]) == 0
    assert json.loads(sciezki.plik_osob().read_text(encoding="utf-8"))["ela"]["komputer"] == "12"
    assert osoby.main(["lista"]) == 0
    assert "[komputer 12]" in capsys.readouterr().out
    for zle in ("dwa slowa", "PC-Eli", "0", "012"):
        assert osoby.main(["ustaw-komputer", "ela", zle]) == 1, zle
    assert osoby.main(["ustaw-komputer", "nikt", "12"]) == 1
    assert osoby.main(["ustaw-komputer", "ela", "-"]) == 0
    assert "komputer" not in json.loads(sciezki.plik_osob().read_text(encoding="utf-8"))["ela"]


def test_zly_komputer_w_pliku_pomijany_z_meldunkiem(katalog):
    osoby.nowa("ela")
    dane = json.loads(sciezki.plik_osob().read_text(encoding="utf-8"))
    dane["ela"]["komputer"] = True
    sciezki.plik_osob().write_text(json.dumps(dane), encoding="utf-8")
    zrodlo = ZrodloJFTools(sciezki.plik_osob(), "http://127.0.0.1:9", SEKRET)
    upr = zrodlo.uprawnienia("ela")
    assert upr.puste and upr.komunikat == KOMUNIKAT_BEZ_KOMPUTERA
    assert "komputer=True" in zrodlo.blad
