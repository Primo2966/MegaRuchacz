"""Testy klienta Wiedzy firmy na atrapach: JFTools + jfwiedza (jeden serwer HTTP w watku), `claude`
(atrapa_claude.py) i przeglad (atrapa_przeglad.py). Prawdziwa konfiguracja Claude Code nietknieta.

    uv --directory C:\\dev\\claude-worker\\lore run pytest C:\\dev\\claude-worker\\narzedzia\\wiedza-firmy-klient\\tests -q
"""

from __future__ import annotations

import base64
import json
import re
import secrets
import socket
import sys
import threading
import time
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest
from cryptography.hazmat.primitives import serialization as s
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import load_ssh_public_key

TU = Path(__file__).resolve().parent
sys.path.insert(0, str(TU.parent))

import klient as K  # noqa: E402

JFTOOLS = "/api/public/mcp-ecommerce-sterowanie"
ZNACZNIK = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\|(ok|blad)\|[^|\n]*\n$")


class Atrapa:
    """Serwer z umowy (sekcja 2 projektu krok 3): register-self w JFTools i /klient/* w jfwiedza."""

    def __init__(self):
        self.status = "pending"
        self.status_403 = False  # /klient/status dla zablokowanego: 403 zamiast 200 {status: blocked}
        self.wpisy_403 = False  # /klient/wpisy odmawia mimo statusu active
        self.komputery: dict[str, dict] = {}
        self.wydane: dict[str, str] = {}  # computerId -> token
        self.nonce: set[str] = set()
        self.odebrane: Counter = Counter()  # klucz -> ile razy przyszedl w POST /klient/wpisy
        self.wpisy: dict[str, dict] = {}
        self.bledne: set[str] = set()  # klucze, dla ktorych serwer zwraca wynik 'blad'
        self.pady: Counter = Counter()  # sciezka -> ile razy jeszcze odpowiedziec 500
        self.wywolania: list[tuple[str, str]] = []
        self.limit_429 = 0  # ile razy register-self odpowie 429
        self.zamek = threading.Lock()

    def zajeta(self, nazwa: str, poza: str | None) -> bool:
        return any(k["name"].lower() == nazwa.lower() for c, k in self.komputery.items() if c != poza)

    def ile(self, metoda: str, sciezka: str) -> int:
        return sum(1 for w in self.wywolania if w == (metoda, sciezka))

    def komputer_z_tokenu(self, naglowek: str) -> str | None:
        t = naglowek[7:] if naglowek.startswith("Bearer ") else ""
        return next((c for c, tok in self.wydane.items() if tok == t), None)

    def obsluz(self, metoda: str, sciezka: str, naglowki, cialo):
        with self.zamek:
            self.wywolania.append((metoda, sciezka))
            if self.pady[sciezka] > 0:
                self.pady[sciezka] -= 1
                return 500, {"error": "atrapa: awaria"}
            if (metoda, sciezka) == ("POST", f"{JFTOOLS}/register-self"):
                # ksztalt jak w wtyczce (K3-Z2.md): computerId liczba, zajeta nazwa -> NAZWA-2, 400/429 z "error"
                if self.limit_429 > 0:
                    self.limit_429 -= 1
                    return 429, {"error": "Za dużo zgłoszeń z tego adresu.", "retryAfterSec": 1234}
                nazwa = cialo["computerName"]
                if not re.fullmatch(r"[A-Za-z0-9-]{3,40}", nazwa) or not cialo["publicKey"].startswith("ssh-ed25519 "):
                    return 400, {"error": "Zła nazwa komputera albo klucz."}
                pub = " ".join(cialo["publicKey"].split()[:2])
                for cid, k in self.komputery.items():
                    if k["pub"] == pub:
                        k["name"] = nazwa if k["name"] != nazwa and not self.zajeta(nazwa, cid) else k["name"]
                        return 200, {"computerId": int(cid), "name": k["name"], "status": self.status, "fingerprint": "SHA256:x"}
                n = 2
                wolna = nazwa
                while self.zajeta(wolna, None):
                    wolna, n = f"{nazwa}-{n}", n + 1
                cid = str(100 + len(self.komputery))
                self.komputery[cid] = {"pub": pub, "name": wolna}
                return 200, {"computerId": int(cid), "name": wolna, "status": "pending", "fingerprint": "SHA256:x"}
            if (metoda, sciezka) == ("POST", "/klient/token"):
                assert isinstance(cialo["computerId"], int), cialo  # typ z JFTools, nie tekst
                cid = str(cialo["computerId"])
                if cid not in self.komputery:
                    return 404, {"kod": "nieznany_komputer"}
                if self.status == "blocked":
                    return 403, {"kod": "zablokowany"}
                if abs(time.time() - int(cialo["ts"])) > 300 or cialo["nonce"] in self.nonce:
                    return 401, {"kod": "zly_podpis"}
                tekst = f"jfwiedza-token|{cid}|{cialo['ts']}|{cialo['nonce']}".encode()
                try:
                    load_ssh_public_key(self.komputery[cid]["pub"].encode()).verify(base64.b64decode(cialo["podpis"]), tekst)
                except Exception:
                    return 401, {"kod": "zly_podpis"}
                self.nonce.add(cialo["nonce"])
                if cid in self.wydane and not cialo.get("wymien"):
                    return 409, {"kod": "juz_wydany"}
                self.wydane[cid] = secrets.token_urlsafe(32)
                return 200, {"token": self.wydane[cid], "osoba": f"komputer-{cid}"}
            cid = self.komputer_z_tokenu(naglowki.get("Authorization") or "")
            if cid is None:
                return 401, {"kod": "zly_token"}
            if (metoda, sciezka) == ("GET", "/klient/status"):
                if self.status == "blocked" and self.status_403:
                    return 403, {"status": "blocked"}
                return 200, {"status": self.status, "osoba": "Ala" if self.status == "active" else "", "komputer": cid}
            if (metoda, sciezka) == ("GET", "/klient/tematy"):
                return 200, {"tematy": [{"id": "temat-a"}], "zasady": "# Zasady (atrapa)", "wersja": "v1"}
            if (metoda, sciezka) == ("POST", "/klient/wpisy"):
                if self.status == "pending":
                    return 409, {"kod": "czeka_na_zatwierdzenie"}
                if self.status != "active" or self.wpisy_403:
                    return 403, {"kod": "zablokowany"}
                if len(cialo["wpisy"]) > 100:
                    return 400, {"kod": "za_duzo"}
                wyniki = []
                for w in cialo["wpisy"]:
                    self.odebrane[w["klucz"]] += 1
                    assert "autor" not in w and "wynik" not in w, w
                    if w["klucz"] in self.bledne:
                        wyniki.append({"klucz": w["klucz"], "wynik": "blad", "opis": "atrapa: zly temat"})
                    elif w["klucz"] in self.wpisy:
                        wyniki.append({"klucz": w["klucz"], "wynik": "duplikat"})
                    else:
                        self.wpisy[w["klucz"]] = w
                        wyniki.append({"klucz": w["klucz"], "wynik": "dodano"})
                return 200, {"wyniki": wyniki}
            return 404, {"error": "nie ma takiej trasy"}


def uruchom_atrape(atrapa: Atrapa) -> ThreadingHTTPServer:
    class Obsluga(BaseHTTPRequestHandler):
        def _odpowiedz(self, metoda):
            dlugosc = int(self.headers.get("Content-Length") or 0)
            cialo = json.loads(self.rfile.read(dlugosc)) if dlugosc else None
            kod, dane = atrapa.obsluz(metoda, self.path.split("?")[0], self.headers, cialo)
            tresc = json.dumps(dane).encode()
            self.send_response(kod)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(tresc)))
            self.end_headers()
            self.wfile.write(tresc)

        def do_GET(self):
            self._odpowiedz("GET")

        def do_POST(self):
            self._odpowiedz("POST")

        def log_message(self, *a):
            pass

    serwer = ThreadingHTTPServer(("127.0.0.1", 0), Obsluga)
    threading.Thread(target=serwer.serve_forever, daemon=True).start()
    return serwer


def wolny_port() -> int:
    with socket.socket() as gn:
        gn.bind(("127.0.0.1", 0))
        return gn.getsockname()[1]


class Srodowisko:
    def __init__(self, tmp: Path, atrapa: Atrapa, port: int):
        self.tmp, self.atrapa = tmp, atrapa
        self.home = tmp / "home"
        self.profil = tmp / "profil"
        self.claude_stan = tmp / "claude-stan.json"
        self.przeglad_log = tmp / "przeglad-wywolania.txt"
        self.url = f"http://127.0.0.1:{port}"
        self.ustaw_konfiguracje(self.url)

    def ustaw_konfiguracje(self, serwer: str, jftools: str | None = None) -> None:
        self.home.mkdir(parents=True, exist_ok=True)
        K.zapisz_json(self.home / "konfiguracja.json", {
            "serwer_url": serwer, "jftools_url": jftools or self.url + JFTOOLS,
            "claude_polecenie": [sys.executable, str(TU / "atrapa_claude.py")],
            "przeglad_polecenie": [sys.executable, str(TU / "atrapa_przeglad.py"), "--profil", "klient", "--format", "json"]})

    def run(self, *argv: str) -> int:
        return K.main(list(argv))

    def znacznik(self, krok: str) -> str:
        return (self.home / "znaczniki" / f"{krok}.txt").read_text(encoding="utf-8")

    def stan(self) -> dict:
        return json.loads((self.home / "stan.json").read_text(encoding="utf-8"))

    def claude(self) -> dict:
        return json.loads(self.claude_stan.read_text(encoding="utf-8")) if self.claude_stan.exists() else {"serwery": {}}

    def przeglady(self) -> int:
        return len(self.przeglad_log.read_text(encoding="utf-8").splitlines()) if self.przeglad_log.exists() else 0

    def kolejka(self) -> list[dict]:
        out = []
        for p in sorted((self.home / "kolejka").glob("*.json")):
            d = json.loads(p.read_text(encoding="utf-8"))
            out.extend(d["wpisy"] if isinstance(d, dict) else d)
        return out


@pytest.fixture
def sr(tmp_path, monkeypatch):
    atrapa = Atrapa()
    serwer = uruchom_atrape(atrapa)
    srod = Srodowisko(tmp_path, atrapa, serwer.server_address[1])
    monkeypatch.setenv("WIEDZA_FIRMY_KLIENT_HOME", str(srod.home))
    monkeypatch.setenv("USERPROFILE", str(srod.profil))  # zadnego prawdziwego .ecommerce-helper-mcp
    monkeypatch.setenv("COMPUTERNAME", "TEST_PC 7")
    monkeypatch.setenv("ATRAPA_CLAUDE_STAN", str(srod.claude_stan))
    monkeypatch.setenv("ATRAPA_PRZEGLAD_LOG", str(srod.przeglad_log))
    monkeypatch.delenv("ATRAPA_PRZEGLAD_PADA", raising=False)

    def nie_wolno(*a, **k):
        raise AssertionError("test nie moze szukac prawdziwego `claude`")
    monkeypatch.setattr(K.shutil, "which", nie_wolno)
    yield srod
    serwer.shutdown()
    serwer.server_close()


def token_z_mcp(sr: Srodowisko) -> str:
    naglowek = sr.claude()["serwery"]["jfwiedza"]["headers"][0]
    assert naglowek.startswith("Authorization: Bearer ")
    return naglowek.split(" ", 2)[2]


# ---------------------------------------------------------------- przeplyw

def test_pelny_przeplyw_pending_active_wysylka(sr):
    assert sr.run("tick") == 0
    a = sr.atrapa
    assert a.ile("POST", f"{JFTOOLS}/register-self") == 1
    cid = str(sr.stan()["computerId"])
    assert a.komputery[cid]["name"] == "TEST-PC-7"  # nazwa oczyszczona do formatu JFTools
    assert token_z_mcp(sr) == a.wydane[cid]
    assert sr.claude()["serwery"]["jfwiedza"]["url"] == sr.url + "/mcp"
    assert sr.przeglady() == 1
    assert json.loads((sr.home / "tematy-cache.json").read_text(encoding="utf-8"))["wersja"] == "v1"
    assert len(sr.kolejka()) == 150
    assert a.ile("POST", "/klient/wpisy") == 0  # pending - nic nie wyslane
    assert "czeka na zatwierdzenie" in sr.znacznik("wysylka")
    for krok in ("zgloszenie", "token", "przeglad", "wysylka"):
        assert ZNACZNIK.match(sr.znacznik(krok)), krok
        assert "|ok|" in sr.znacznik(krok), (krok, sr.znacznik(krok))

    a.status = "active"
    assert sr.run("tick") == 0
    assert a.ile("POST", "/klient/wpisy") == 2  # 100 + 50
    assert len(a.wpisy) == 150 and set(a.odebrane.values()) == {1}
    assert sr.kolejka() == []
    wyslane = json.loads((sr.home / "wyslano" / "przeglad-atrapa.json").read_text(encoding="utf-8"))["wpisy"]
    assert len(wyslane) == 150 and {w["wynik"] for w in wyslane} == {"dodano"}
    assert sr.przeglady() == 1  # przeglad tylko raz
    assert "zakonczony" in sr.znacznik("przeglad") and "wyslano 150" in sr.znacznik("wysylka")
    assert a.ile("POST", f"{JFTOOLS}/register-self") == 1 and a.ile("POST", "/klient/token") == 1


def test_podwojny_tick_bez_dubli(sr):
    sr.atrapa.status = "active"
    assert sr.run("tick") == 0
    assert sr.run("tick") == 0
    a = sr.atrapa
    assert len(a.wpisy) == 150 and set(a.odebrane.values()) == {1}
    assert a.ile("POST", "/klient/wpisy") == 2
    assert a.ile("POST", "/klient/token") == 1 and a.ile("POST", f"{JFTOOLS}/register-self") == 1
    assert sr.przeglady() == 1
    wywolania = [w[:2] for w in sr.claude()["wywolania"]]
    assert wywolania.count(["mcp", "add"]) == 1


def test_rownolegly_tick_czeka_na_zamek(sr, monkeypatch):
    monkeypatch.setattr(K, "CZEKAJ_RECZNIE_S", 1)
    sr.atrapa.status = "active"
    inny = K.Klient(sr.home)
    assert inny.zamek.zdobadz(0)
    try:
        assert sr.run("tick") == 0  # zajety zamek - pomija, nie blad
        assert sr.atrapa.wywolania == []
        assert sr.run("wyslij") == 2
    finally:
        inny.zamek.zwolnij()
    assert sr.run("tick") == 0
    assert len(sr.atrapa.wpisy) == 150


def test_blad_sieci_ponowienie(sr):
    martwy = f"http://127.0.0.1:{wolny_port()}"
    sr.ustaw_konfiguracje(martwy)
    assert sr.run("tick") == 1
    assert "|ok|" in sr.znacznik("zgloszenie")  # JFTools odpowiada
    assert "|blad|" in sr.znacznik("token") and "ponowie" in sr.znacznik("token")
    assert "|blad|" in sr.znacznik("wysylka") and "|blad|" in sr.znacznik("przeglad")
    sr.ustaw_konfiguracje(sr.url)
    sr.atrapa.status = "active"
    sr.atrapa.pady["/klient/wpisy"] = 1  # pierwsza paczka pada 500
    assert sr.run("tick") == 1
    assert "|blad|" in sr.znacznik("wysylka") and "ponowie" in sr.znacznik("wysylka")
    assert len(sr.kolejka()) == 150 and sr.atrapa.wpisy == {}  # nic nie zginelo
    assert sr.run("tick") == 0
    assert len(sr.atrapa.wpisy) == 150 and sr.kolejka() == []
    assert "|ok|" in sr.znacznik("wysylka")


def test_zablokowany_403_nic_nie_wysyla(sr):
    assert sr.run("tick") == 0  # pending, kolejka z przegladu gotowa
    sr.atrapa.status, sr.atrapa.status_403 = "blocked", True
    assert sr.run("tick") == 1
    assert sr.atrapa.ile("POST", "/klient/wpisy") == 0
    assert len(sr.kolejka()) == 150
    z = sr.znacznik("wysylka")
    assert "|blad|" in z and "blocked" in z and "nic nie wyslano" in z


def test_403_przy_wysylce_mimo_statusu_active(sr):
    assert sr.run("tick") == 0
    sr.atrapa.status, sr.atrapa.wpisy_403 = "active", True
    assert sr.run("wyslij") == 1
    assert sr.atrapa.ile("POST", "/klient/wpisy") == 1 and len(sr.kolejka()) == 150
    assert "odmowil" in sr.znacznik("wysylka")


def test_zablokowany_przed_tokenem(sr):
    sr.atrapa.status = "blocked"
    assert sr.run("zglos") == 1
    assert "zablokowany" in sr.znacznik("token") and not (sr.home / "token.dpapi").exists()
    assert "jfwiedza" not in sr.claude()["serwery"]


# ---------------------------------------------------------------- token

def test_token_zapisany_nie_jawnym_tekstem(sr, capsys):
    assert sr.run("zglos") == 0
    token = token_z_mcp(sr)
    zapisany = (sr.home / "token.dpapi").read_bytes()
    assert token.encode() not in zapisany and base64.b64encode(token.encode()) not in zapisany
    assert K.dpapi_odszyfruj(zapisany).decode() == token
    for p in sr.home.rglob("*"):
        if p.is_file():
            assert token.encode() not in p.read_bytes(), p
    wyjscie = capsys.readouterr()
    assert token not in wyjscie.out and token not in wyjscie.err


def test_podmiana_innego_tokenu_w_mcp(sr):
    K.zapisz_json(sr.claude_stan, {"serwery": {"jfwiedza": {"url": sr.url + "/mcp", "headers": ["Authorization: Bearer stary"]}},
                                   "wywolania": []})
    assert sr.run("zglos") == 0
    cid = str(sr.stan()["computerId"])
    assert token_z_mcp(sr) == sr.atrapa.wydane[cid]
    wywolania = [w[:2] for w in sr.claude()["wywolania"]]
    assert ["mcp", "remove"] in wywolania and ["mcp", "add"] in wywolania
    assert "podmieniony" in sr.znacznik("token")


def test_reinstalacja_wymienia_token(sr):
    assert sr.run("zglos") == 0
    stary = token_z_mcp(sr)
    (sr.home / "token.dpapi").unlink()
    (sr.home / "stan.json").unlink()  # klucz zostaje - ten sam komputer
    assert sr.run("zglos") == 0
    nowy = token_z_mcp(sr)
    assert nowy != stary and sr.atrapa.ile("POST", "/klient/token") == 3  # juz_wydany -> wymiana
    assert len(sr.atrapa.komputery) == 1


def test_ecommerce_helper_ten_sam_komputer(sr):
    kat = sr.profil / ".ecommerce-helper-mcp"
    kat.mkdir(parents=True)
    k = Ed25519PrivateKey.generate()
    (kat / "id_ed25519").write_bytes(k.private_bytes(s.Encoding.PEM, s.PrivateFormat.OpenSSH, s.NoEncryption()))
    pub = k.public_key().public_bytes(s.Encoding.OpenSSH, s.PublicFormat.OpenSSH).decode()
    (kat / "id_ed25519.pub").write_text(pub + " ecommerce-helper-mcp:ala@PC\n", encoding="ascii")
    # instalator ecommerce-helper (PowerShell) pisze z BOM
    (kat / "komputer.json").write_text(json.dumps({"computerId": 77, "name": "ALA-PC", "status": "active",
                                                   "publicKey": pub}), encoding="utf-8-sig")
    sr.atrapa.komputery["77"] = {"pub": pub, "name": "ALA-PC"}
    assert sr.run("zglos") == 0
    assert sr.atrapa.ile("POST", f"{JFTOOLS}/register-self") == 0
    assert sr.stan()["computerId"] == 77 and sr.stan()["klucz_zrodlo"] == "ecommerce-helper"
    assert token_z_mcp(sr) == sr.atrapa.wydane["77"]
    assert not (sr.home / "klucz" / "id_ed25519").exists()


# ---------------------------------------------------------------- przeglad, kolejka, konfiguracja

def test_przeglad_pada_i_wznawia(sr, monkeypatch):
    monkeypatch.setenv("ATRAPA_PRZEGLAD_PADA", "1")
    assert sr.run("tick") == 1
    assert sr.stan()["przeglad"]["stan"] == "blad"
    assert "|blad|" in sr.znacznik("przeglad") and "wznowie" in sr.znacznik("przeglad")
    monkeypatch.delenv("ATRAPA_PRZEGLAD_PADA")
    assert sr.run("tick") == 0
    assert sr.stan()["przeglad"]["stan"] == "zakonczony" and sr.przeglady() == 2
    assert sr.run("przeglad") == 0 and sr.przeglady() == 2  # zakonczony - nie powtarza
    assert sr.run("przeglad", "--ponow") == 0 and sr.przeglady() == 3


def test_bledne_wpisy_zostaja_w_kolejce(sr):
    sr.atrapa.status = "active"
    sr.run("zglos")
    kolejka = sr.home / "kolejka"
    wpisy = [{"klucz": f"k{i}", "tresc": f"t{i}", "temat": "temat-a", "tematy_dodatkowe": [], "poufnosc": "wewnetrzne",
              "data": "2026-10-14", "zrodlo": "dzienny", "program": "claude-code", "autor": "NIE WYSYLAC"} for i in range(3)]
    K.zapisz_json(kolejka / "dzienne-2026-10-14.json", {"format": "wiedza-firmy-kolejka/1", "wpisy": wpisy + [{"tresc": "bez klucza"}]})
    sr.atrapa.bledne = {"k1"}
    assert sr.run("wyslij") == 1
    assert [w["klucz"] for w in sr.kolejka()] == ["k1"]
    assert set(sr.atrapa.wpisy) == {"k0", "k2"}
    z = sr.znacznik("wysylka")
    assert "|blad|" in z and "zly temat" in z and "bez klucza" in z
    assert len(list((sr.home / "odrzucone").glob("*.json"))) == 1
    sr.atrapa.bledne = set()
    assert sr.run("wyslij") == 0
    assert sr.kolejka() == [] and sr.atrapa.odebrane == Counter({"k0": 1, "k1": 2, "k2": 1})


def test_brak_konfiguracji_krzyczy(sr):
    (sr.home / "konfiguracja.json").unlink()
    assert sr.run("tick") == 1
    for krok in ("zgloszenie", "token", "wysylka", "przeglad"):
        assert "|blad|" in sr.znacznik(krok) and "konfiguracja.json" in sr.znacznik(krok)
    assert sr.atrapa.wywolania == []


def test_brak_domyslnych_adresow_w_kodzie():
    kod = (TU.parent / "klient.py").read_text(encoding="utf-8")
    assert "192.168." not in kod and "jfinvesting" not in kod and "8766" not in kod


def test_zajeta_nazwa_i_429_z_jftools(sr, monkeypatch):
    sr.atrapa.komputery["5"] = {"pub": "ssh-ed25519 INNY", "name": "test-pc-7"}
    sr.atrapa.limit_429 = 1
    assert sr.run("zglos") == 1
    z = sr.znacznik("zgloszenie")
    assert "|blad|" in z and "429" in z and "ponowie" in z
    assert "czeka na zgloszenie" in sr.znacznik("token")
    assert sr.run("zglos") == 0
    assert sr.stan()["nazwa"] == "TEST-PC-7-2"  # nazwa z odpowiedzi, nie wyslana
    assert "TEST-PC-7-2" in sr.znacznik("zgloszenie")


def test_nazwa_komputera_format_jftools(monkeypatch):
    for surowa, oczekiwana in (("ŁUKASZ_PC", "LUKASZ-PC"), ("Zażółć PC", "Zazolc-PC"), ("A", "komputer-A"),
                               ("X" * 50, "X" * 40), ("biuro--gosia ", "biuro-gosia")):
        monkeypatch.setenv("COMPUTERNAME", surowa)
        assert K.nazwa_komputera() == oczekiwana
        assert re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]{2,39}", oczekiwana)


def test_nieczytelny_token_wymieniany(sr):
    assert sr.run("zglos") == 0
    (sr.home / "token.dpapi").write_bytes(b"to nie jest blob DPAPI")
    sr.atrapa.status = "active"
    assert sr.run("tick") == 0
    cid = str(sr.stan()["computerId"])
    assert K.dpapi_odszyfruj((sr.home / "token.dpapi").read_bytes()).decode() == sr.atrapa.wydane[cid]
    assert token_z_mcp(sr) == sr.atrapa.wydane[cid] and len(sr.atrapa.wpisy) == 150
