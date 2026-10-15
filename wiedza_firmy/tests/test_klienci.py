"""Krok 3: trasy /klient/* - komputer sam bierze token (podpis kluczem z JFTools keys) i wysyla wpisy.

Proby negatywne: zly podpis (inny klucz, inny tekst, smieci), stary i przyszly ts, powtorzony nonce, drugi token
bez "wymien", komputer spoza keys (usuniety, zablokowany), blocked -> 403 i puste narzedzia MCP, pending -> 409 na
wpisach, autor z ciala ignorowany, limit 100 wpisow, limit prob z adresu, trasy bez Bearera, tryb bez JFTools.
JFTools to atrapa z test_jftools.py (prawdziwe HTTP na 127.0.0.1), ksztalty jak we wtyczce 84b58e6 (K3-Z2).
"""

from __future__ import annotations

import base64
import json
import hashlib
import shutil
import struct
import subprocess
import sys

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from starlette.testclient import TestClient

from test_jftools import SEKRET, AtrapaJFTools, Zegar, odpowiedz
from wiedza_firmy import jftools, klienci as klienci_mod, osoby, podpis, sciezki
from wiedza_firmy.baza import NowyWpis
from wiedza_firmy.jftools import KOMUNIKAT_BLOCKED, KOMUNIKAT_PENDING, ZrodloJFTools
from wiedza_firmy.klienci import Klienci
from wiedza_firmy.pliki import czytaj_json
from wiedza_firmy.serwer import aplikacja

ADRES = "http://127.0.0.1:8766"
NAGLOWKI_MCP = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json",
                "MCP-Protocol-Version": "2025-06-18"}


def nowy_klucz() -> tuple[Ed25519PrivateKey, str]:
    prywatny = Ed25519PrivateKey.generate()
    publiczny = prywatny.public_key().public_bytes(serialization.Encoding.OpenSSH, serialization.PublicFormat.OpenSSH)
    return prywatny, publiczny.decode() + " komentarz@pc"


class Swiat:
    """JFTools (atrapa) z komputerami 12 (active, wlasciciel), 13 (pending), 14 (blocked), 15 (active, bez wlasciciela)."""

    def __init__(self, srodowisko, atrapa: AtrapaJFTools) -> None:
        self.sr, self.atrapa = srodowisko, atrapa
        self.zegar = Zegar()
        self.klucze: dict[str, Ed25519PrivateKey] = {}
        publiczne = {}
        for kid in ("12", "13", "14", "15"):
            self.klucze[kid], publiczne[kid] = nowy_klucz()
        atrapa.komputery = {
            "12": odpowiedz("12", "active", {"temat-a": "wewnetrzne"}, nazwa="PC-ELA",
                            owner={"email": "ela@example.com", "name": "Ela Testowa"}),
            "13": odpowiedz("13", "pending", nazwa="PC-NOWY", owner={"email": None, "name": None}),
            "14": odpowiedz("14", "blocked", nazwa="PC-ZLY", owner={"email": "zly@example.com", "name": "Zly"}),
            "15": odpowiedz("15", "active", {"temat-a": "jawne"}, nazwa="PC-ELA-2", owner=None),
        }
        # jak wtyczka: keys podaje pending + active, bez blocked
        atrapa.klucze = {"computers": [{"id": int(k), "name": atrapa.komputery[k]["computer"]["name"],
                                        "status": atrapa.komputery[k]["computer"]["status"], "publicKey": publiczne[k]}
                                       for k in ("12", "13", "15")]}
        self.publiczne = publiczne
        self.zrodlo = ZrodloJFTools(sciezki.plik_osob(), atrapa.url, SEKRET, limit_s=0.5, zegar=self.zegar)
        self.klienci = Klienci(srodowisko.wiedza, self.zrodlo, zegar=self.zegar)
        self.k = TestClient(aplikacja(srodowisko.wiedza, self.zrodlo, host="127.0.0.1", klienci=self.klienci),
                            base_url=ADRES)
        self._nr = 0

    def nonce(self) -> str:
        self._nr += 1
        return f"nonce-testowy-{self._nr:06d}"

    def cialo(self, kid: str, klucz: Ed25519PrivateKey | None = None, ts: int | None = None,
              nonce: str | None = None, **dodatki) -> dict:
        ts = int(self.zegar.t) if ts is None else ts
        nonce = nonce or self.nonce()
        sygnatura = (klucz or self.klucze[kid]).sign(podpis.tekst_do_podpisu(kid, ts, nonce).encode("utf-8"))
        return {"computerId": int(kid), "ts": ts, "nonce": nonce,
                "podpis": base64.b64encode(sygnatura).decode(), **dodatki}

    def token(self, kid: str, **kw):
        return self.k.post("/klient/token", json=self.cialo(kid, **kw))

    def daj_token(self, kid: str) -> str:
        r = self.token(kid)
        assert r.status_code == 200, r.text
        return r.json()["token"]

    def get(self, sciezka: str, token: str | None):
        return self.k.get(sciezka, headers={"Authorization": f"Bearer {token}"} if token else {})

    def wpisy(self, token: str, wpisy: list, **dodatki):
        return self.k.post("/klient/wpisy", headers={"Authorization": f"Bearer {token}"},
                           json={"paczka_id": "p1", "wpisy": wpisy, **dodatki})

    def narzedzie(self, token: str, nazwa: str, **argumenty) -> dict:
        r = self.k.post("/mcp", headers={**NAGLOWKI_MCP, "Authorization": f"Bearer {token}"},
                        json={"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                              "params": {"name": nazwa, "arguments": argumenty}})
        assert r.status_code == 200, r.text
        return json.loads(r.json()["result"]["content"][0]["text"])

    def mija(self, s: float) -> None:
        self.zegar.t += s


@pytest.fixture
def swiat(srodowisko):
    a = AtrapaJFTools()
    s = Swiat(srodowisko, a)
    with s.k:
        yield s
    a.zatrzymaj()


def wpis(tresc: str, temat: str = "temat-a", poufnosc: str = "jawne", klucz: str | None = None, **inne) -> dict:
    return {"klucz": klucz or hashlib.sha256(f"{tresc}|{temat}".encode()).hexdigest()[:16], "tresc": tresc,
            "temat": temat, "tematy_dodatkowe": [], "poufnosc": poufnosc, "data": "2026-10-14",
            "zrodlo": "rozmowa", "program": "claude-code", **inne}


def osoby_json() -> dict:
    return czytaj_json(sciezki.plik_osob())


def dziennik() -> str:
    p = sciezki.dziennik_zgloszen_klientow()
    return p.read_text(encoding="utf-8") if p.exists() else ""


# ---------------------------------------------------------------- token: droga szczesliwa


def test_token_wydany_raz_wpis_w_osobach_i_dziala(swiat):
    r = swiat.token("12")
    assert r.status_code == 200, r.text
    odp = r.json()
    assert odp["osoba"] == "komputer-12" and odp["wynik"] == "wydano" and len(odp["token"]) >= 40
    wpis_osoby = osoby_json()["komputer-12"]
    assert wpis_osoby["wystawil"] == "auto" and wpis_osoby["komputer"] == "12" and wpis_osoby["admin"] is False
    assert wpis_osoby["token_sha256"] == hashlib.sha256(odp["token"].encode()).hexdigest()
    assert odp["token"] not in sciezki.plik_osob().read_text(encoding="utf-8")
    assert "wystawiony" in wpis_osoby
    st = swiat.get("/klient/status", odp["token"])
    assert st.status_code == 200, st.text
    assert st.json() == {"status": "active", "osoba": "komputer-12", "komputer": "12",
                             "nazwa_komputera": "PC-ELA", "wlasciciel": "Ela Testowa"}
    # ten sam token dziala w MCP: uprawnienia komputera z JFTools
    assert swiat.narzedzie(odp["token"], "moje_uprawnienia")["uprawnienia"][0]["temat"] == "temat-a"
    linia = dziennik().strip().splitlines()[-1]
    assert "| komputer 12 | wydano |" in linia
    assert odp["token"] not in dziennik() and "nonce-testowy" not in dziennik()


def test_token_pending_tez_dostaje(swiat):
    token = swiat.daj_token("13")
    assert swiat.get("/klient/status", token).json()["status"] == "pending"


# ---------------------------------------------------------------- token: proby negatywne


def test_zly_podpis_innym_kluczem_innym_tekstem_i_smieci(swiat):
    obcy, _ = nowy_klucz()
    assert swiat.token("12", klucz=obcy).json()["kod"] == "zly_podpis"
    # podpis dobrym kluczem, ale pod innym nonce niz w zadaniu
    cialo = swiat.cialo("12")
    cialo["nonce"] = swiat.nonce()
    r = swiat.k.post("/klient/token", json=cialo)
    assert r.status_code == 401 and r.json()["kod"] == "zly_podpis"
    # podpis cudzego komputera (13) pod prosba o 12
    cialo = swiat.cialo("12", klucz=swiat.klucze["13"])
    assert swiat.k.post("/klient/token", json=cialo).json()["kod"] == "zly_podpis"
    for smiec in ("", "abc", "!!!", base64.b64encode(b"x" * 64).decode(), "A" * 5000):
        cialo = swiat.cialo("12")
        cialo["podpis"] = smiec
        r = swiat.k.post("/klient/token", json=cialo)
        assert r.status_code == 401 and r.json()["kod"] == "zly_podpis", smiec[:10]
    assert "komputer-12" not in (osoby_json() if sciezki.plik_osob().exists() else {})
    assert dziennik().count("| zly_podpis |") == 8


@pytest.mark.parametrize("przesuniecie", [-301, 301, -3600, 10**6])
def test_stary_albo_przyszly_ts(swiat, przesuniecie):
    r = swiat.token("12", ts=int(swiat.zegar.t) + przesuniecie)
    assert r.status_code == 401 and r.json()["kod"] == "zly_podpis"
    assert r.json()["czas_serwera"] == int(swiat.zegar.t)
    assert "komputer-12" not in osoby_json()


def test_ts_na_granicy_okna_przechodzi(swiat):
    assert swiat.token("12", ts=int(swiat.zegar.t) - 300).status_code == 200


def test_powtorzony_nonce_odrzucony_nawet_z_wymien(swiat):
    cialo = swiat.cialo("12", wymien=True)
    assert swiat.k.post("/klient/token", json=cialo).status_code == 200
    r = swiat.k.post("/klient/token", json=cialo)  # dokladna powtorka (np. podsluchana) - nonce zuzyty
    assert r.status_code == 401 and r.json()["kod"] == "zly_podpis" and "nonce" in r.json()["opis"]
    # po 10 min nonce wypada z pamieci, ale wtedy ts jest dawno poza oknem
    swiat.mija(601)
    assert swiat.k.post("/klient/token", json=cialo).json()["kod"] == "zly_podpis"


def test_drugi_token_tylko_z_wymien(swiat):
    stary = swiat.daj_token("12")
    r = swiat.token("12")
    assert r.status_code == 409 and r.json()["kod"] == "juz_wydany"
    assert swiat.token("12", wymien=False).json()["kod"] == "juz_wydany"
    assert swiat.get("/klient/status", stary).status_code == 200  # odmowa nie rusza starego tokenu
    r = swiat.token("12", wymien=True)
    assert r.status_code == 200 and r.json()["wynik"] == "wymieniono"
    nowy = r.json()["token"]
    assert swiat.get("/klient/status", stary).status_code == 401
    assert swiat.get("/klient/status", nowy).status_code == 200
    assert "wymieniony" in osoby_json()["komputer-12"]


def test_reczny_wpis_o_tej_nazwie_nie_nadpisany(swiat):
    osoby.nowa("komputer-12")
    przed = osoby_json()["komputer-12"]["token_sha256"]
    for wymien in (False, True):
        r = swiat.token("12", wymien=wymien)
        assert r.status_code == 409 and r.json()["kod"] == "juz_wydany"
    assert osoby_json()["komputer-12"]["token_sha256"] == przed


def test_komputer_spoza_keys(swiat):
    # 77: JFTools go nie zna (404) - podpis nawet nie jest sprawdzany, bo nie ma czym
    klucz, _ = nowy_klucz()
    swiat.klucze["77"] = klucz
    r = swiat.token("77")
    assert r.status_code == 403 and r.json()["kod"] == "nieznany_komputer"
    # 14: zablokowany - nie ma go w keys, knowledge-permissions mowi blocked
    r = swiat.token("14")
    assert r.status_code == 403 and r.json()["kod"] == "zablokowany"
    assert not ({"komputer-77", "komputer-14"} & set(osoby_json() if sciezki.plik_osob().exists() else {}))
    assert "| komputer 14 | zablokowany |" in dziennik() and "| komputer 77 | nieznany_komputer |" in dziennik()


def test_zablokowany_po_odczycie_kluczy_traci_klucz_po_odswiezeniu(swiat):
    swiat.daj_token("12")
    swiat.atrapa.klucze["computers"] = [k for k in swiat.atrapa.klucze["computers"] if k["id"] != 12]
    swiat.atrapa.komputery["12"]["computer"]["status"] = "blocked"
    swiat.mija(jftools.WAZNOSC_KLUCZY_S + 1)
    r = swiat.token("12", wymien=True)
    assert r.status_code == 403 and r.json()["kod"] == "zablokowany"


@pytest.mark.parametrize("cialo", [
    "nie json", [], {"computerId": "abc", "ts": 1, "nonce": "x" * 20, "podpis": "x"},
    {"computerId": 12, "ts": "jutro", "nonce": "x" * 20, "podpis": "x"},
    {"computerId": 12, "ts": 1, "nonce": "krotki", "podpis": "x"},
    {"computerId": 12, "ts": 1, "nonce": "zly|nonce|z|kreska", "podpis": "x"},
    {"computerId": True, "ts": 1, "nonce": "x" * 20, "podpis": "x"},
])
def test_zle_dane_400(swiat, cialo):
    r = swiat.k.post("/klient/token", content=json.dumps(cialo) if not isinstance(cialo, str) else cialo)
    assert r.status_code == 400 and r.json()["kod"] == "zle_dane"


def test_wymien_nie_bool_400(swiat):
    assert swiat.token("12", wymien="tak").status_code == 400


def test_limit_prob_z_adresu(swiat):
    for _ in range(klienci_mod.LIMIT_PROB_IP):
        assert swiat.k.post("/klient/token", content="{}").status_code == 400
    r = swiat.token("12")
    assert r.status_code == 429 and r.json()["kod"] == "za_czesto"
    swiat.mija(klienci_mod.OKNO_PROB_IP_S + 1)
    assert swiat.token("12").status_code == 200


def test_jftools_lezy_przy_tokenie_503(swiat):
    swiat.atrapa.klucze = 500
    r = swiat.token("12")
    assert r.status_code == 503 and r.json()["kod"] == "jftools_niedostepny"
    assert "| jftools_niedostepny |" in dziennik()
    assert swiat.zrodlo.stan()["ostatni_blad_kluczy"]


# ---------------------------------------------------------------- SSHSIG (ssh-keygen -Y sign)


def _napis(b: bytes) -> bytes:
    return struct.pack(">I", len(b)) + b


def sshsig(prywatny: Ed25519PrivateKey, tekst: str, przestrzen: str = "jfwiedza", klucz_w_bloku=None) -> str:
    """Blok SSHSIG zlozony jak w OpenSSH (PROTOCOL.sshsig), sha512."""
    pub = (klucz_w_bloku or prywatny).public_key().public_bytes(serialization.Encoding.Raw,
                                                                 serialization.PublicFormat.Raw)
    blob_klucza = _napis(b"ssh-ed25519") + _napis(pub)
    podpisane = (b"SSHSIG" + _napis(przestrzen.encode()) + _napis(b"") + _napis(b"sha512")
                 + _napis(hashlib.sha512(tekst.encode()).digest()))
    sygnatura = _napis(b"ssh-ed25519") + _napis(prywatny.sign(podpisane))
    blob = (b"SSHSIG" + struct.pack(">I", 1) + _napis(blob_klucza) + _napis(przestrzen.encode()) + _napis(b"")
            + _napis(b"sha512") + _napis(sygnatura))
    b64 = base64.b64encode(blob).decode()
    return "\n".join(["-----BEGIN SSH SIGNATURE-----", *[b64[i:i + 70] for i in range(0, len(b64), 70)],
                      "-----END SSH SIGNATURE-----"]) + "\n"


def test_sshsig_przyjety_a_zla_przestrzen_i_obcy_klucz_odrzucone(swiat):
    ts, nonce = int(swiat.zegar.t), swiat.nonce()
    tekst = podpis.tekst_do_podpisu("12", ts, nonce)
    obcy, _ = nowy_klucz()
    for zly in (sshsig(swiat.klucze["12"], tekst, przestrzen="file"),
                sshsig(obcy, tekst),                                       # obcy klucz w bloku
                sshsig(obcy, tekst, klucz_w_bloku=swiat.klucze["12"]),     # blok udaje klucz 12, podpis obcy
                sshsig(swiat.klucze["12"], tekst + "x")):
        r = swiat.k.post("/klient/token", json={"computerId": 12, "ts": ts, "nonce": nonce, "podpis": zly})
        assert r.status_code == 401 and r.json()["kod"] == "zly_podpis", r.text
    r = swiat.k.post("/klient/token", json={"computerId": 12, "ts": ts, "nonce": nonce,
                                            "podpis": sshsig(swiat.klucze["12"], tekst)})
    assert r.status_code == 200, r.text


@pytest.mark.skipif(not shutil.which("ssh-keygen"), reason="brak ssh-keygen w PATH")
def test_sshsig_z_prawdziwego_ssh_keygen(swiat, tmp_path):
    """Zgodnosc z zapasowa droga klienta: ssh-keygen -Y sign -n jfwiedza na pliku z samym tekstem."""
    plik_klucza = tmp_path / "id_ed25519"
    plik_klucza.write_bytes(swiat.klucze["12"].private_bytes(serialization.Encoding.PEM,
                                                             serialization.PrivateFormat.OpenSSH,
                                                             serialization.NoEncryption()))
    ts, nonce = int(swiat.zegar.t), swiat.nonce()
    plik = tmp_path / "prosba.txt"
    plik.write_bytes(podpis.tekst_do_podpisu("12", ts, nonce).encode("utf-8"))
    bez_okna = {"creationflags": subprocess.CREATE_NO_WINDOW} if sys.platform == "win32" else {}
    wynik = subprocess.run(["ssh-keygen", "-q", "-Y", "sign", "-n", "jfwiedza", "-f", str(plik_klucza), str(plik)],
                           capture_output=True, text=True, timeout=30, **bez_okna)
    assert wynik.returncode == 0, wynik.stderr
    sig = (tmp_path / "prosba.txt.sig").read_text(encoding="ascii")
    r = swiat.k.post("/klient/token", json={"computerId": 12, "ts": ts, "nonce": nonce, "podpis": sig})
    assert r.status_code == 200, r.text


# ---------------------------------------------------------------- Bearer i tryb bez JFTools


def test_trasy_klienta_bez_tokenu_401(swiat):
    for metoda, sciezka in (("GET", "/klient/status"), ("GET", "/klient/tematy"), ("POST", "/klient/wpisy"),
                            ("GET", "/klient/cokolwiek")):
        for naglowki in ({}, {"Authorization": "Bearer zly"}, {"Authorization": "Basic eDp5"}):
            r = swiat.k.request(metoda, sciezka, headers=naglowki, json={"wpisy": []})
            assert r.status_code == 401, (sciezka, naglowki, r.text)


def test_zla_metoda_405(swiat):
    token = swiat.daj_token("12")
    assert swiat.get("/klient/token", None).status_code == 405
    assert swiat.k.post("/klient/status", headers={"Authorization": f"Bearer {token}"}).status_code == 405


def test_tryb_plikowy_trasy_wylaczone(srodowisko):
    with TestClient(aplikacja(srodowisko.wiedza, srodowisko.zrodlo, host="127.0.0.1"), base_url=ADRES) as k:
        r = k.post("/klient/token", json={"computerId": 12, "ts": 1, "nonce": "x" * 20, "podpis": "x"})
        assert r.status_code == 503 and r.json()["kod"] == "wylaczone"
        r = k.get("/klient/status", headers={"Authorization": f"Bearer {srodowisko.tokeny['ania-a']}"})
        assert r.status_code == 503 and r.json()["kod"] == "wylaczone"


def test_osoba_bez_komputera_403(swiat):
    r = swiat.get("/klient/status", swiat.sr.tokeny["admin"])
    assert r.status_code == 403 and r.json()["kod"] == "brak_komputera"


# ---------------------------------------------------------------- blocked, pending, usuniety


def test_blocked_403_wszedzie_puste_narzedzia_a_odblokowanie_przywraca_ten_sam_token(swiat):
    token = swiat.daj_token("12")
    assert swiat.narzedzie(token, "szukaj_wiedzy", pytanie="Zielona papuga lata nad magazynem")["wyniki"]
    swiat.atrapa.komputery["12"]["computer"]["status"] = "blocked"
    swiat.atrapa.komputery["12"]["grants"] = {}
    swiat.mija(jftools.WAZNOSC_S + 1)
    for sciezka in ("/klient/status", "/klient/tematy"):
        r = swiat.get(sciezka, token)
        assert r.status_code == 403 and r.json()["kod"] == "zablokowany" and r.json()["status"] == "blocked", sciezka
    r = swiat.wpisy(token, [wpis("Zablokowany cos pisze")])
    assert r.status_code == 403 and r.json()["kod"] == "zablokowany"
    odp = swiat.narzedzie(token, "szukaj_wiedzy", pytanie="Zielona papuga lata nad magazynem")
    assert odp["wyniki"] == [] and odp["komunikat"] == KOMUNIKAT_BLOCKED
    assert swiat.narzedzie(token, "tematy") == {"tematy": [], "komunikat": KOMUNIKAT_BLOCKED}
    assert swiat.narzedzie(token, "dodaj_wpis", tresc="Zablokowany przez MCP", temat="temat-a",
                           poufnosc="jawne") == {"blad": KOMUNIKAT_BLOCKED}
    assert "zablokowany przez mcp" not in json.dumps(
        swiat.narzedzie(swiat.sr.tokeny["admin"], "szukaj_wiedzy", pytanie="Zablokowany przez MCP"),
        ensure_ascii=False).lower()
    # odblokowanie w panelu -> ten sam token znowu dziala (po wygasnieciu pamieci 1 min dla komputera bez dostepu)
    swiat.atrapa.komputery["12"]["computer"]["status"] = "active"
    swiat.atrapa.komputery["12"]["grants"] = {"temat-a": "wewnetrzne"}
    swiat.mija(jftools.WAZNOSC_BEZ_DOSTEPU_S + 1)
    assert swiat.get("/klient/status", token).json()["status"] == "active"
    assert swiat.narzedzie(token, "szukaj_wiedzy", pytanie="Zielona papuga lata nad magazynem")["wyniki"]


def test_pending_tematy_tak_wpisy_409_narzedzia_puste(swiat):
    token = swiat.daj_token("13")
    r = swiat.get("/klient/tematy", token)
    assert r.status_code == 200 and {t["id"] for t in r.json()["tematy"]} == {"temat-a", "temat-b", "temat-c"}
    r = swiat.wpisy(token, [wpis("Pending cos pisze")])
    assert r.status_code == 409 and r.json()["kod"] == "czeka_na_zatwierdzenie"
    assert swiat.narzedzie(token, "szukaj_wiedzy", pytanie="papuga")["komunikat"] == KOMUNIKAT_PENDING
    assert swiat.narzedzie(token, "dodaj_wpis", tresc="Pending przez MCP", temat="temat-a",
                           poufnosc="jawne") == {"blad": KOMUNIKAT_PENDING}
    assert swiat.sr.baza.statystyka()["wpisy"] == 5


def test_usuniety_z_jftools_wygasl_403_i_powrot(swiat):
    token = swiat.daj_token("12")
    assert "wygasl" not in osoby_json()["komputer-12"]
    swiat.get("/klient/status", token)  # status active trafia do pamieci
    del swiat.atrapa.komputery["12"]
    swiat.mija(jftools.WAZNOSC_S + 1)
    r = swiat.get("/klient/status", token)
    assert r.status_code == 403 and r.json()["kod"] == "nieznany_komputer" and r.json()["status"] == "nieznany"
    assert osoby_json()["komputer-12"]["wygasl"]
    assert swiat.wpisy(token, [wpis("Usuniety cos pisze")]).status_code == 403
    assert swiat.narzedzie(token, "szukaj_wiedzy", pytanie="papuga")["wyniki"] == []


# ---------------------------------------------------------------- wpisy


def test_wpisy_autor_z_jftools_a_nie_z_ciala_i_wyniki_per_wpis(swiat):
    token = swiat.daj_token("12")
    usuniety = swiat.sr.baza.dodaj([NowyWpis("Stary wpis usuniety przez admina", "temat-a", "jawne", "Ktos",
                                             "2026-10-01")], dodal="t", znane_tematy={"temat-a"}).dodane[0]
    swiat.sr.baza.usun(usuniety, "test", kto="admin")
    paczka = [
        wpis("Czerwony slon myje okna w srody", klucz="k1", autor="admin"),
        wpis("Zielona papuga lata nad magazynem w poniedzialki.", klucz="k2"),        # jest w bazie (conftest)
        wpis("Stary wpis usuniety przez admina", klucz="k3"),
        wpis("Tajny kod", poufnosc="tajne", klucz="k4"),
        wpis("Nieznany temat", temat="temat-zly", klucz="k5"),
        {"klucz": "k6", "tresc": 123, "temat": "temat-a", "poufnosc": "jawne"},
        wpis("Czerwony slon myje okna w srody", klucz="k7"),                           # dubel w tej samej paczce
        "nie obiekt",
    ]
    r = swiat.wpisy(token, paczka, autor="admin")
    assert r.status_code == 200, r.text
    odp = r.json()
    assert odp["autor"] == "Ela Testowa" and odp["paczka_id"] == "p1"
    wyniki = {w["klucz"]: w["wynik"] for w in odp["wyniki"]}
    assert wyniki == {"k1": "dodano", "k2": "duplikat", "k3": "usuniety_wczesniej", "k4": "blad", "k5": "blad",
                      "k6": "blad", "k7": "duplikat", None: "blad"}
    assert all(w.get("opis") for w in odp["wyniki"] if w["wynik"] == "blad")
    znaleziony = swiat.narzedzie(swiat.sr.tokeny["admin"], "szukaj_wiedzy", pytanie="Czerwony slon myje okna")
    assert znaleziony["wyniki"][0]["autor"] == "Ela Testowa"
    assert "admin" not in {w["autor"] for w in znaleziony["wyniki"]}
    # druga taka sama paczka (podwojny tick klienta) - nic nowego
    r2 = swiat.wpisy(token, [wpis("Czerwony slon myje okna w srody", klucz="k1")])
    assert r2.json()["wyniki"] == [{"klucz": "k1", "wynik": "duplikat"}]
    liczniki = swiat.klienci.stan()["liczniki_od_startu"]
    assert liczniki["wpisy"]["dodano"] == 1 and liczniki["wpisy"]["paczki"] == 2 and liczniki["tokeny"]["wydano"] == 1


def test_wpisy_bez_wlasciciela_autor_to_nazwa_komputera(swiat):
    token = swiat.daj_token("15")
    r = swiat.wpisy(token, [wpis("Brazowy kret kopie w ogrodzie")])
    assert r.json()["autor"] == "PC-ELA-2" and r.json()["wyniki"][0]["wynik"] == "dodano"


def test_wpisy_owner_z_samym_emailem_autor_to_email(swiat, capsys):
    # tak wyglada dzis wiekszosc komputerow w JFTools (np. PRIMO-DZIK: sam e-mail, bez imienia i nazwiska)
    swiat.atrapa.komputery["15"]["owner"] = {"email": " x@example.com ", "name": None}
    token = swiat.daj_token("15")
    assert swiat.wpisy(token, [wpis("Szary kret")]).json()["autor"] == "x@example.com"
    assert "pominiete z odpowiedzi" not in capsys.readouterr().err


def test_wpisy_owner_bez_name_i_emaila_autor_to_nazwa_komputera(swiat):
    swiat.atrapa.komputery["15"]["owner"] = {"email": None, "name": None}
    token = swiat.daj_token("15")
    assert swiat.wpisy(token, [wpis("Rudy kret")]).json()["autor"] == "PC-ELA-2"


def test_limit_100_wpisow(swiat):
    token = swiat.daj_token("12")
    r = swiat.wpisy(token, [wpis(f"Wpis numer {i} z paczki") for i in range(101)])
    assert r.status_code == 413 and r.json()["kod"] == "za_duzo" and r.json()["limit"] == 100
    assert swiat.sr.baza.statystyka()["wpisy"] == 5
    r = swiat.wpisy(token, [wpis(f"Wpis numer {i} z paczki") for i in range(100)])
    assert r.status_code == 200 and sum(w["wynik"] == "dodano" for w in r.json()["wyniki"]) == 100


def test_wpisy_zle_cialo_400(swiat):
    token = swiat.daj_token("12")
    h = {"Authorization": f"Bearer {token}"}
    assert swiat.k.post("/klient/wpisy", headers=h, content="nie json").status_code == 400
    assert swiat.k.post("/klient/wpisy", headers=h, json={"wpisy": "x"}).status_code == 400


def test_wpisy_za_duze_cialo_413(swiat):
    token = swiat.daj_token("12")
    r = swiat.k.post("/klient/wpisy", headers={"Authorization": f"Bearer {token}"},
                     content=b"x" * (klienci_mod.LIMIT_CIALA + 1))
    assert r.status_code == 413


# ---------------------------------------------------------------- tematy i zasady


def test_tematy_zasady_z_pliku_a_brak_pliku_to_pusty_tekst_i_dziennik(swiat, capsys):
    token = swiat.daj_token("12")
    r = swiat.get("/klient/tematy", token)
    assert r.status_code == 200 and r.json()["zasady"] == ""
    assert "BRAK pliku" in capsys.readouterr().err
    assert "BRAK" in swiat.klienci.stan()["liczniki_od_startu"]["zasady_klienta"]
    wersja_bez = r.json()["wersja"]
    sciezki.plik_zasad_klienta().write_text("Nie wysylaj hasel.\n", encoding="utf-8")
    r = swiat.get("/klient/tematy", token)
    assert r.json()["zasady"] == "Nie wysylaj hasel.\n" and r.json()["wersja"] != wersja_bez
    assert swiat.get("/klient/tematy", token).json()["wersja"] == r.json()["wersja"]
    t = r.json()["tematy"][0]
    assert set(t) >= {"id", "nazwa", "opis", "przyklady", "osobne_uprawnienie"}


# ---------------------------------------------------------------- owner w odpowiedzi JFTools


def test_owner_ksztalty():
    d, pom = jftools.Dostep.z_odpowiedzi(odpowiedz("1", owner={"email": "a@b", "name": " Ola "}), "1")
    assert d.wlasciciel == "Ola" and d.wlasciciel_email == "a@b" and d.autor == "Ola" and pom == []
    for owner in (None, {"email": None, "name": None}, {"email": "a@b", "name": None}):
        d, pom = jftools.Dostep.z_odpowiedzi(odpowiedz("1", owner=owner), "1")
        assert d.wlasciciel == "" and pom == [], owner
        assert d.autor == ("a@b" if owner and owner["email"] else "PC Eli"), owner
    d, pom = jftools.Dostep.z_odpowiedzi(odpowiedz("1", owner={"email": 5, "name": None}), "1")
    assert d.wlasciciel_email == "" and d.autor == "PC Eli" and pom
    d, pom = jftools.Dostep.z_odpowiedzi(odpowiedz("1", owner="Ola"), "1")
    assert d.wlasciciel == "" and pom
    stara = odpowiedz("1")
    del stara["owner"]  # wtyczka sprzed 84b58e6
    assert jftools.Dostep.z_odpowiedzi(stara, "1") == (jftools.Dostep("active", "PC Eli", {}, ""), [])


class _Koniec(BaseException):
    pass


def test_liczniki_w_znaczniku_zycia(swiat, monkeypatch):
    from wiedza_firmy import serwer

    swiat.daj_token("12")
    swiat.token("12")  # juz_wydany

    def stop(_s):
        raise _Koniec

    monkeypatch.setattr(serwer.time, "sleep", stop)
    with pytest.raises(_Koniec):
        serwer._zyje(swiat.sr.baza, swiat.zrodlo, serwer.StanSerwera(), "127.0.0.1", 8766, swiat.klienci)
    znacznik = czytaj_json(sciezki.znacznik_serwera())
    liczniki = znacznik["klienci"]["liczniki_od_startu"]
    assert liczniki["tokeny"] == {"wydano": 1, "juz_wydany": 1}
    assert "| juz_wydany |" in liczniki["ostatnia_proba_tokenu"]
    assert "ostatni_blad_kluczy" in znacznik["uprawnienia"]


def test_token_za_duze_cialo_413_i_w_dzienniku(swiat):
    r = swiat.k.post("/klient/token", content=b"x" * (klienci_mod.LIMIT_CIALA + 1))
    assert r.status_code == 413 and r.json()["kod"] == "za_duzo"
    assert "| komputer ? | za_duzo |" in dziennik()


# ---------------------------------------------------------------- zgodnosc z klientem (Z6, a5cfa72)

KLIENT_PY = __import__("pathlib").Path(__file__).resolve().parents[2] / "narzedzia" / "wiedza-firmy-klient" / "klient.py"


@pytest.mark.skipif(not KLIENT_PY.is_file(), reason=f"brak {KLIENT_PY} (kopia serwera bez narzedzi klienta)")
def test_zgodnosc_z_podpisem_klient_py(swiat, tmp_path, monkeypatch):
    """Podpis i cialo dokladnie jak w klient.py (Klucz.podpisz, TEKST_PODPISU, computerId liczba, nonce token_hex(16)),
    klucz w pliku OpenSSH jak id_ed25519 z ssh-keygen / ecommerce-helper. Rozjazd formatu = ten test pada."""
    import importlib.util
    import secrets

    spec = importlib.util.spec_from_file_location("klient_wiedzy_firmy", KLIENT_PY)
    klient = importlib.util.module_from_spec(spec)
    monkeypatch.setitem(sys.modules, spec.name, klient)  # dataclass szuka modulu w sys.modules
    spec.loader.exec_module(klient)
    plik = tmp_path / "id_ed25519"
    plik.write_bytes(swiat.klucze["12"].private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.OpenSSH,
                                                      serialization.NoEncryption()))
    klucz = klient.Klucz(prywatny=plik, publiczny=swiat.publiczne["12"], zrodlo="wlasny")
    cid = 12  # w body w typie z JFTools (liczba), w podpisie jako tekst - jak w Klient.pobierz_token
    ts, nonce = int(swiat.zegar.t), secrets.token_hex(16)
    cialo = {"computerId": cid, "ts": ts, "nonce": nonce,
             "podpis": klucz.podpisz(klient.TEKST_PODPISU.format(computerId=cid, ts=ts, nonce=nonce))}
    r = swiat.k.post("/klient/token", json=cialo)
    assert r.status_code == 200, r.text
    assert klient.TEKST_PODPISU.format(computerId=cid, ts=ts, nonce=nonce) == podpis.tekst_do_podpisu("12", ts, nonce)
    # ten sam podpis pod innym komputerem nie przechodzi
    cialo = {"computerId": 15, "ts": ts, "nonce": secrets.token_hex(16)}
    cialo["podpis"] = klucz.podpisz(klient.TEKST_PODPISU.format(computerId=15, **{k: cialo[k] for k in ("ts", "nonce")}))
    assert swiat.k.post("/klient/token", json=cialo).json()["kod"] == "zly_podpis"
