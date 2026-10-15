"""Klient "Wiedzy firmy" (jfwiedza) na komputerze pracownika - sam zglasza komputer, odbiera token,
podlacza MCP, robi jednorazowy przeglad historii i wysyla wpisy, gdy admin zatwierdzi komputer.

Podkomendy (wszystkie idempotentne, mozna wolac dowolnie czesto):
    zglos     - klucz ed25519, zgloszenie w JFTools (register-self albo computerId z ecommerce-helper),
                token z POST /klient/token (podpis kluczem), zapis tokenu przez DPAPI, `claude mcp add`
    status    - GET /klient/status: pending / active / blocked / nieznany
    przeglad  - GET /klient/tematy -> tematy-cache.json, potem przeglad.py --profil klient --format json
                (tylko raz, do skutku; --ponow uruchamia jeszcze raz mimo zakonczenia)
    wyslij    - active: kolejka\\*.json po 100 wpisow na POST /klient/wpisy; pending: tylko znacznik
    dzienny   - krok dzienny (proba od 15.10.2026, wlaczany w konfiguracja.json: "dzienny": "pelny";
                domyslnie wylaczony): zakonczone dni rozmow z Lore -> kolejka\\dzienne-<RRRR-MM-DD>.json
    tick      - po kolei to, co potrzebne: zglos, wyslij, przeglad (gdy jeszcze nie zrobiony), wyslij,
                dzienny (gdy wlaczony), wyslij

Uruchomienie (srodowisko uv Lore - ma `cryptography`):
    uv --directory C:\\dev\\claude-worker\\lore run python
        C:\\dev\\claude-worker\\narzedzia\\wiedza-firmy-klient\\klient.py tick

Pliki w <home> = %WIEDZA_FIRMY_KLIENT_HOME% (domyslnie ~\\.claude\\mr\\wiedza-firmy):
konfiguracja.json (opcjonalny: serwer_url i jftools_url nadpisuja client-config i adres domyslny; dzienny,
dzienny_od - krok dzienny, nizej), stan.json, klucz\\, token.dpapi, tematy-cache.json, kolejka\\, wyslano\\,
odrzucone\\, klient.log, dzienny\\<dzien>\\ (robocze przegladu dnia), koszty.jsonl (koszt kazdej proby dnia),
znaczniki\\{zgloszenie,token,przeglad,wysylka,status,dzienny}.txt (`czas|ok|opis` albo `czas|blad|opis`).

Krok dzienny ("dzienny": "pelny"): raz na dobe, najwczesniej DZIENNY_PO_STARCIE_S po starcie Windows,
przeglad.py --profil klient przeglada kazdy zakonczony dzien od ostatniego zrobionego do wczoraj (najwyzej
DZIENNY_NADRABIA_DNI ostatnie). Dzien = wycieta z lore.db kopia z chunkami tylko tego dnia (czas lokalny),
dzienny\\<dzien>\\dzien.db - przeglad.py czyta ja przez --baza, wiec sam sie nie zmienia. Bez dubli z pierwszym
przegladem historii: dzienny czeka, az ten sie skonczy, i bierze rozmowy od chwili jego startu (wczesniejsze
przeczytal przeglad). "dzienny_od": "RRRR-MM-DD" = historia sprzed tego dnia przejrzana inna droga (u Primo
profilem primo) - wtedy pierwszy przeglad historii jest pomijany, a dzienny zaczyna od tego dnia. Dzien musi
byc juz wczytany do Lore (indeksowanie po jego koncu), inaczej dzienny czeka. Ten sam dzien nie idzie dwa razy
(stan.json, plik dzienne-<dzien>.json w kolejka\\ albo wyslano\\, zamek dzienny.lock); nieudany wraca przy
nastepnym ticku (przeglad.py wznawia, zrobionych paczek nie powtarza). Po kazdej probie dnia jedna linia
w koszty.jsonl: tokeny i $ z kopert `claude -p` tej proby (z dziennikow koszt.tsv przegladu dnia).

Podpis tokenu: surowy podpis Ed25519 (cryptography) tekstu "jfwiedza-token|{computerId}|{ts}|{nonce}"
w UTF-8, base64 (standardowy, z dopelnieniem); serwer sprawdza go kluczem publicznym OpenSSH z JFTools.

Cisza zakazana: kazdy krok zostawia znacznik (takze "czekam na zatwierdzenie"), bledy sieci zostaja
w znaczniku i w klient.log, a kolejny tick ponawia. Token nigdy nie trafia do znacznikow ani logu.
"""

from __future__ import annotations

import argparse
import base64
import ctypes
import hashlib
import http.client
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import sys
import time
import unicodedata
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import date, datetime, time as godzina, timedelta
from pathlib import Path
from urllib.parse import urlparse

HOME_ZMIENNA = "WIEDZA_FIRMY_KLIENT_HOME"
# Publiczne trasy wtyczki JFTools (domena publiczna). Adresu serwera wiedzy (LAN) w kodzie nie ma -
# podaje go JFTools trasa GET client-config {"jfwiedza_url"}; konfiguracja.json moze nadpisac oba.
JFTOOLS_DOMYSLNY = "https://tools.jfinvesting.pl/api/public/mcp-ecommerce-sterowanie"
NAZWA_MCP = "jfwiedza"
PACZKA = 100
LIMIT_HTTP_S = 120  # paczka 64 wpisow (dzien 14.10) nie zmiescila sie w 20 s - serwer zapisal, klient zglosil timeout
LIMIT_CLAUDE_S = 90
# Ponowne `claude mcp get` (z health-checkiem serwera) najwyzej co 6 h, gdy token sie nie zmienil -
# wpis usuniety recznie wraca najpozniej po 6 h, a tick co 30 min nie odpala co chwile node'a.
SPRAWDZ_MCP_CO_S = 6 * 3600
# Zamek glowny przy dopisywaniu wyniku przegladu: przeglad trwa godzinami, a tick trzyma zamek
# najwyzej kilka minut (paczki po 20 s limitu) - 10 min to zapas, nie oczekiwanie.
CZEKAJ_NA_ZAMEK_S = 600
# Polecenia reczne (zglos, status, wyslij, przeglad) czekaja na trwajacy tick najwyzej minute.
CZEKAJ_RECZNIE_S = 60
ENTROPIA_DPAPI = b"MegaRuchacz/jfwiedza/token"
TEKST_PODPISU = "jfwiedza-token|{computerId}|{ts}|{nonce}"
POLA_WPISU = ("klucz", "tresc", "temat", "tematy_dodatkowe", "poufnosc", "data", "zrodlo", "program")
WYNIKI_GOTOWE = ("dodano", "duplikat", "usuniety_wczesniej")  # nie wysylac drugi raz
LOG_MAX_BAJTOW = 1_000_000
# Krok dzienny - opis w naglowku. Tryb "pelny" = caly dzien rozmow (proba wlasciciela 15.10.2026).
DZIENNY_TRYB = "pelny"
DZIENNY_NADRABIA_DNI = 3
DZIENNY_PO_STARCIE_S = 300
DZIENNY_TRZYMAJ_DNI = 14  # katalogi robocze dzienny\<dzien> i wpisy dni w stan.json
FORMAT_KOLEJKI = "wiedza-firmy-kolejka/1"
KOLUMNY_CHUNKOW = ("id", "project", "session", "file", "line", "part", "ts", "role", "text", "indexed_at")
ROLE_ROZMOWY = ("user", "assistant", "conversation")  # te role czyta przeglad.py (ROLE)
# koszty.jsonl: pole -> kolumna dziennika koszt.tsv przegladu (= pole usage koperty `claude -p`)
POLA_KOSZTU = (("wejscie", "input_tokens"), ("cache_zapis", "cache_creation_input_tokens"),
               ("cache_odczyt", "cache_read_input_tokens"), ("wyjscie", "output_tokens"))


class BladSieci(Exception):
    """Brak polaczenia, limit czasu, 5xx albo 429 - ponowienie przy nastepnym ticku."""


class BladKlienta(Exception):
    """Blad, ktorego ponowienie samo nie naprawi (konfiguracja, klucz, odmowa serwera)."""


def teraz() -> str:
    return datetime.now().isoformat(timespec="seconds")


def zapisz_atomowo(sciezka: Path, tresc: bytes) -> None:
    sciezka.parent.mkdir(parents=True, exist_ok=True)
    tymczasowy = sciezka.with_name(sciezka.name + ".tmp")
    tymczasowy.write_bytes(tresc)
    os.replace(tymczasowy, sciezka)


def zapisz_json(sciezka: Path, dane) -> None:
    zapisz_atomowo(sciezka, (json.dumps(dane, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))


def czytaj_json(sciezka: Path):
    return json.loads(sciezka.read_text(encoding="utf-8-sig"))


def jedna_linia(tekst: str, limit: int = 500) -> str:
    return " ".join(str(tekst).replace("|", "/").split())[:limit]


def dzis() -> date:
    return date.today()


def sekundy_od_startu() -> float:
    """Czas od startu Windows (GetTickCount64); poza Windows zegar monotoniczny."""
    if os.name == "nt":
        f = ctypes.windll.kernel32.GetTickCount64
        f.restype = ctypes.c_uint64
        return f() / 1000.0
    return time.monotonic()


def czas_lokalny(ts) -> datetime | None:
    """Znacznik czasu z Lore (ISO UTC, '...Z') albo stan.json (lokalny bez strefy) -> czas lokalny ze strefa."""
    try:
        d = datetime.fromisoformat(str(ts or "").replace("Z", "+00:00"))
    except ValueError:
        return None
    return d.astimezone()  # bez strefy = czas lokalny


def koniec_dnia(d: date) -> datetime:
    return datetime.combine(d + timedelta(days=1), godzina.min).astimezone()


# ---------------------------------------------------------------- DPAPI (bez zaleznosci, ctypes)

class _Blob(ctypes.Structure):
    _fields_ = [("cbData", ctypes.c_uint32), ("pbData", ctypes.c_void_p)]


def _dpapi(dane: bytes, szyfruj: bool) -> bytes:
    if os.name != "nt":
        raise BladKlienta("DPAPI jest tylko w Windows - tokenu nie zapisuje jawnym tekstem")
    crypt32, kernel32 = ctypes.windll.crypt32, ctypes.windll.kernel32
    kernel32.LocalFree.argtypes = [ctypes.c_void_p]
    bufor_we = ctypes.create_string_buffer(dane, len(dane))
    bufor_ent = ctypes.create_string_buffer(ENTROPIA_DPAPI, len(ENTROPIA_DPAPI))
    we = _Blob(len(dane), ctypes.cast(bufor_we, ctypes.c_void_p))
    ent = _Blob(len(ENTROPIA_DPAPI), ctypes.cast(bufor_ent, ctypes.c_void_p))
    wy = _Blob()
    funkcja = crypt32.CryptProtectData if szyfruj else crypt32.CryptUnprotectData
    funkcja.argtypes = [ctypes.POINTER(_Blob), ctypes.c_void_p if not szyfruj else ctypes.c_wchar_p,
                        ctypes.POINTER(_Blob), ctypes.c_void_p, ctypes.c_void_p, ctypes.c_uint32,
                        ctypes.POINTER(_Blob)]
    opis = "jfwiedza token" if szyfruj else None
    if not funkcja(ctypes.byref(we), opis, ctypes.byref(ent), None, None, 0x1, ctypes.byref(wy)):
        raise BladKlienta(f"DPAPI: {ctypes.WinError()}")
    try:
        return ctypes.string_at(wy.pbData, wy.cbData)
    finally:
        kernel32.LocalFree(wy.pbData)


def dpapi_zaszyfruj(dane: bytes) -> bytes:
    return _dpapi(dane, True)


def dpapi_odszyfruj(dane: bytes) -> bytes:
    return _dpapi(dane, False)


# ---------------------------------------------------------------- zamek (pada razem z procesem)

class Zamek:
    """Blokada na pliku (msvcrt w Windows) - system zwalnia ja sam, gdy proces padnie."""

    def __init__(self, sciezka: Path):
        self.sciezka = sciezka
        self._plik = None

    def zdobadz(self, czekaj_s: float = 0.0) -> bool:
        self.sciezka.parent.mkdir(parents=True, exist_ok=True)
        plik = open(self.sciezka, "a+b")
        koniec = time.monotonic() + czekaj_s
        while True:
            try:
                if os.name == "nt":
                    import msvcrt
                    plik.seek(0)
                    msvcrt.locking(plik.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(plik, fcntl.LOCK_EX | fcntl.LOCK_NB)
                self._plik = plik
                return True
            except OSError:
                if time.monotonic() >= koniec:
                    plik.close()
                    return False
                time.sleep(0.5)

    def zwolnij(self) -> None:
        if self._plik is None:
            return
        try:
            if os.name == "nt":
                import msvcrt
                self._plik.seek(0)
                msvcrt.locking(self._plik.fileno(), msvcrt.LK_UNLCK, 1)
        finally:
            self._plik.close()
            self._plik = None


# ---------------------------------------------------------------- HTTP

@dataclass
class Odp:
    kod: int
    dane: object

    def pole(self, nazwa: str) -> str:
        return str(self.dane.get(nazwa) or "") if isinstance(self.dane, dict) else ""

    def opis_bledu(self) -> str:
        szczegol = self.pole("kod") or self.pole("error") or self.pole("blad") or self.pole("opis")
        return f"HTTP {self.kod}" + (f" ({jedna_linia(szczegol, 200)})" if szczegol else "")


# Bez proxy systemowego: serwer wiedzy stoi w sieci lokalnej, a Windows przepuszczalby go przez
# proxy z rejestru (wyjatek <local> obejmuje tylko nazwy bez kropek).
_OTWIERACZ = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def zapytanie(metoda: str, url: str, cialo=None, token: str | None = None) -> Odp:
    dane = None if cialo is None else json.dumps(cialo, ensure_ascii=False).encode("utf-8")
    zadanie = urllib.request.Request(url, data=dane, method=metoda)
    zadanie.add_header("Accept", "application/json")
    zadanie.add_header("User-Agent", "megaruchacz-wiedza-firmy-klient")
    if dane is not None:
        zadanie.add_header("Content-Type", "application/json; charset=utf-8")
    if token:
        zadanie.add_header("Authorization", f"Bearer {token}")
    try:
        with _OTWIERACZ.open(zadanie, timeout=LIMIT_HTTP_S) as odp:
            kod, tresc = odp.status, odp.read()
    except urllib.error.HTTPError as e:
        kod = e.code
        try:
            tresc = e.read()
        except OSError:
            tresc = b""
    except (urllib.error.URLError, OSError, http.client.HTTPException) as e:
        powod = getattr(e, "reason", e)
        raise BladSieci(f"brak polaczenia z {urlparse(url).netloc}: {jedna_linia(powod, 200)}") from e
    try:
        wynik = json.loads(tresc.decode("utf-8")) if tresc else None
    except (UnicodeDecodeError, ValueError):
        wynik = None
    if kod >= 500 or kod == 429:
        raise BladSieci(f"{urlparse(url).path}: serwer odpowiedzial {Odp(kod, wynik).opis_bledu()}")
    return Odp(kod, wynik)


# ---------------------------------------------------------------- klucz i podpis

def bez_komentarza(linia: str) -> str:
    return " ".join(str(linia or "").split()[:2])


def nazwa_komputera() -> str:
    """COMPUTERNAME oczyszczona do formatu JFTools: [A-Za-z0-9-], 3-40 znakow (polskie litery bez ogonkow).
    Zajeta nazwe JFTools zmienia na NAZWA-2, NAZWA-3... - obowiazuje `name` z odpowiedzi register-self."""
    surowa = (os.environ.get("COMPUTERNAME") or "komputer").translate(str.maketrans("łŁ", "lL"))
    surowa = unicodedata.normalize("NFKD", surowa).encode("ascii", "ignore").decode("ascii")
    n = re.sub(r"-+", "-", re.sub(r"[^A-Za-z0-9]", "-", surowa)).strip("-")
    if len(n) < 3:
        n = ("komputer-" + n).strip("-")
    return n[:40].rstrip("-")


@dataclass
class Klucz:
    prywatny: Path
    publiczny: str  # cala linia OpenSSH (z komentarzem)
    zrodlo: str  # "wlasny" albo "ecommerce-helper"

    def podpisz(self, tekst: str) -> str:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        from cryptography.hazmat.primitives.serialization import load_ssh_private_key
        try:
            klucz = load_ssh_private_key(self.prywatny.read_bytes(), password=None)
        except (OSError, ValueError, TypeError) as e:
            raise BladKlienta(f"nie da sie wczytac klucza {self.prywatny}: {jedna_linia(e, 200)}") from e
        if not isinstance(klucz, Ed25519PrivateKey):
            raise BladKlienta(f"{self.prywatny} to nie klucz ed25519")
        return base64.b64encode(klucz.sign(tekst.encode("utf-8"))).decode("ascii")


def katalog_ecommerce_helper() -> Path:
    return Path(os.environ.get("USERPROFILE") or Path.home()) / ".ecommerce-helper-mcp"


def rejestracja_ecommerce_helper() -> tuple[Klucz, dict] | None:
    """komputer.json instalatora ecommerce-helper - wazny tylko dla obecnego klucza (jak w instaluj.ps1)."""
    kat = katalog_ecommerce_helper()
    komp, prv, pub = kat / "komputer.json", kat / "id_ed25519", kat / "id_ed25519.pub"
    if not (komp.is_file() and prv.is_file() and pub.is_file()):
        return None
    try:
        d = czytaj_json(komp)
        linia = pub.read_text(encoding="utf-8-sig").strip()
    except (OSError, ValueError):
        return None
    if not isinstance(d, dict) or not d.get("computerId") or not d.get("publicKey"):
        return None
    if not linia or bez_komentarza(linia) != bez_komentarza(d["publicKey"]):
        return None
    return Klucz(prv, linia, "ecommerce-helper"), d


# ---------------------------------------------------------------- klient

class Klient:
    def __init__(self, home: Path):
        self.home = home
        self.konf_plik = home / "konfiguracja.json"
        self.stan_plik = home / "stan.json"
        self.klucz_kat = home / "klucz"
        self.token_plik = home / "token.dpapi"
        self.tematy_plik = home / "tematy-cache.json"
        self.kolejka = home / "kolejka"
        self.wyslano = home / "wyslano"
        self.odrzucone = home / "odrzucone"
        self.znaczniki = home / "znaczniki"
        self.log_plik = home / "klient.log"
        self.log_przegladu = home / "przeglad.log"
        self.zamek = Zamek(home / "klient.lock")
        self.zamek_przegladu = Zamek(home / "przeglad.lock")
        self.zamek_dzienny = Zamek(home / "dzienny.lock")
        self.dzienny_kat = home / "dzienny"
        self.koszty_plik = home / "koszty.jsonl"
        self.stan: dict = {}
        self._token: str | None = None
        self._obce_tokeny: set[str] = set()  # token z istniejacego wpisu MCP (np. reczny token admina)
        self.przeglad_trwa = False  # przeglad w innym procesie - to nie blad ticka
        self.przeglad_pominiety = False  # dzienny_od: historie przejrzano inna droga - to nie blad ticka
        self._dni_dzienne: list[date] = []
        self._granica_dzienna: datetime | None = None

    # -------------------------------------------------- stan, znaczniki, log

    def loguj(self, tekst: str) -> None:
        tekst = self.maskuj(tekst)
        print(tekst, flush=True)
        try:
            self.home.mkdir(parents=True, exist_ok=True)
            if self.log_plik.exists() and self.log_plik.stat().st_size > LOG_MAX_BAJTOW:
                stare = self.log_plik.read_bytes()[-LOG_MAX_BAJTOW // 2:]
                zapisz_atomowo(self.log_plik, stare)
            with open(self.log_plik, "a", encoding="utf-8") as f:
                f.write(f"{teraz()} {tekst}\n")
        except OSError as e:  # log nie przerywa pracy, ale nie milczy
            print(f"UWAGA: nie da sie dopisac do {self.log_plik}: {e}", file=sys.stderr, flush=True)

    def maskuj(self, tekst: str) -> str:
        tekst = re.sub(r"Bearer\s+\S+", "Bearer ***", str(tekst))
        for t in (self._token, *self._obce_tokeny):
            if t:
                tekst = tekst.replace(t, "***")
        return tekst

    def znacznik(self, krok: str, ok: bool, opis: str) -> bool:
        opis = jedna_linia(self.maskuj(opis))
        zapisz_atomowo(self.znaczniki / f"{krok}.txt",
                       f"{teraz()}|{'ok' if ok else 'blad'}|{opis}\n".encode("utf-8"))
        self.stan.setdefault("kroki", {})[krok] = {"czas": teraz(), "ok": ok, "opis": opis}
        self.loguj(f"[{krok}] {'ok' if ok else 'BLAD'}: {opis}")
        return ok

    def wczytaj_stan(self) -> None:
        self.stan = {}
        if not self.stan_plik.exists():
            return
        try:
            d = czytaj_json(self.stan_plik)
            if not isinstance(d, dict):
                raise ValueError("to nie obiekt JSON")
            self.stan = d
        except (OSError, ValueError) as e:
            kopia = self.stan_plik.with_name(f"stan.zepsuty-{datetime.now():%Y%m%d-%H%M%S}.json")
            shutil.copyfile(self.stan_plik, kopia)
            self.stan = {"stan_odtworzony": {"czas": teraz(), "powod": jedna_linia(e, 200), "kopia": str(kopia)}}
            self.loguj(f"UWAGA: stan.json byl zepsuty ({e}) - kopia {kopia}, zaczynam od nowa")

    def zapisz_stan(self) -> None:
        self.stan["zapisano"] = teraz()
        zapisz_json(self.stan_plik, self.stan)

    def konfiguracja(self) -> tuple[str, str]:
        """(serwer_url, jftools_url). jftools: konfiguracja.json albo JFTOOLS_DOMYSLNY. serwer: konfiguracja.json,
        inaczej GET {jftools}/client-config -> jfwiedza_url (zapamietany w stan.json na wypadek awarii JFTools)."""
        d: dict = {}
        if self.konf_plik.exists():
            try:
                d = czytaj_json(self.konf_plik)
            except (OSError, ValueError) as e:
                raise BladKlienta(f"zepsuty {self.konf_plik}: {jedna_linia(e, 200)}") from e
            if not isinstance(d, dict):
                raise BladKlienta(f"{self.konf_plik} to nie obiekt JSON")
        jftools = str(d.get("jftools_url") or JFTOOLS_DOMYSLNY).strip().rstrip("/")
        serwer = str(d.get("serwer_url") or "").strip().rstrip("/")
        if serwer:
            return serwer, jftools
        try:
            odp = zapytanie("GET", f"{jftools}/client-config")
            serwer = odp.pole("jfwiedza_url").strip().rstrip("/") if odp.kod == 200 else ""
            blad = "" if serwer else f"client-config bez jfwiedza_url: {odp.opis_bledu()}"
        except BladSieci as e:
            blad = str(e)
        if serwer:
            self.stan.pop("client_config_blad", None)
            self.stan.update({"serwer_url": serwer, "serwer_url_pobrano": teraz()})
            return serwer, jftools
        self.stan["client_config_blad"] = {"czas": teraz(), "opis": jedna_linia(blad, 300)}
        if self.stan.get("serwer_url"):
            self.loguj(f"UWAGA: JFTools nie podal adresu serwera wiedzy ({blad}) - uzywam ostatniego znanego "
                       f"z {self.stan.get('serwer_url_pobrano')}")
            return str(self.stan["serwer_url"]), jftools
        raise BladKlienta(f"nie znam adresu serwera wiedzy - JFTools client-config: {blad}; ponowie przy nastepnym "
                          f"uruchomieniu")

    def ustawienie(self, klucz: str):
        try:
            d = czytaj_json(self.konf_plik)
        except (OSError, ValueError):
            return None
        return d.get(klucz) if isinstance(d, dict) else None

    def polecenie(self, klucz: str) -> list[str] | None:
        try:
            d = czytaj_json(self.konf_plik)
        except (OSError, ValueError):
            return None
        w = d.get(klucz) if isinstance(d, dict) else None
        return [str(x) for x in w] if isinstance(w, list) and w else None

    # -------------------------------------------------- token (DPAPI)

    def token(self) -> str | None:
        if self._token is None and self.token_plik.exists():
            try:
                self._token = dpapi_odszyfruj(self.token_plik.read_bytes()).decode("utf-8")
            except (BladKlienta, OSError, UnicodeDecodeError) as e:
                # np. plik z innego konta Windows - bez wymiany tokenu klient stalby w miejscu
                self.loguj(f"UWAGA: nie da sie odczytac {self.token_plik} ({jedna_linia(e, 200)}) - wymienie token")
                self.token_plik.unlink(missing_ok=True)
                self.stan["token_niewazny"] = True
        return self._token

    def zapisz_token(self, token: str) -> None:
        zapisz_atomowo(self.token_plik, dpapi_zaszyfruj(token.encode("utf-8")))
        self._token = token

    def usun_token(self) -> None:
        self.token_plik.unlink(missing_ok=True)
        self._token = None
        self.stan.pop("mcp", None)

    # -------------------------------------------------- krok: zgloszenie

    def wlasny_klucz(self) -> Klucz:
        prv, pub = self.klucz_kat / "id_ed25519", self.klucz_kat / "id_ed25519.pub"
        if not (prv.is_file() and pub.is_file()):
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
            from cryptography.hazmat.primitives import serialization as s
            k = Ed25519PrivateKey.generate()
            zapisz_atomowo(prv, k.private_bytes(s.Encoding.PEM, s.PrivateFormat.OpenSSH, s.NoEncryption()))
            linia = k.public_key().public_bytes(s.Encoding.OpenSSH, s.PublicFormat.OpenSSH).decode("ascii")
            zapisz_atomowo(pub, f"{linia} jfwiedza:{nazwa_komputera()}\n".encode("ascii"))
            self.loguj(f"utworzono klucz {prv}")
        return Klucz(prv, pub.read_text(encoding="ascii").strip(), "wlasny")

    def klucz_zapisany(self) -> Klucz | None:
        sciezka = self.stan.get("klucz_prywatny")
        if not sciezka:
            return None
        prv = Path(sciezka)
        pub = prv.with_name(prv.name + ".pub")
        try:
            linia = pub.read_text(encoding="utf-8-sig").strip()
        except OSError:
            return None
        if not prv.is_file() or bez_komentarza(linia) != self.stan.get("klucz_publiczny"):
            return None
        return Klucz(prv, linia, str(self.stan.get("klucz_zrodlo") or ""))

    def krok_zgloszenie(self, jftools: str) -> bool:
        if self.stan.get("computerId") and not self.stan.get("zglos_ponownie") and self.klucz_zapisany():
            return self.znacznik("zgloszenie", True, f"zgloszony wczesniej: {self.stan.get('nazwa')} "
                                                     f"(nr {self.stan['computerId']}, klucz {self.stan.get('klucz_zrodlo')})")
        eh = rejestracja_ecommerce_helper()
        if eh and not self.stan.get("ecommerce_helper_nieznany"):
            klucz, d = eh
            computer_id, nazwa, status = d["computerId"], str(d.get("name") or nazwa_komputera()), str(d.get("status") or "")
            skad = "computerId z ecommerce-helper (komputer.json)"
        else:
            klucz = eh[0] if eh else self.wlasny_klucz()
            nazwa = nazwa_komputera()
            odp = zapytanie("POST", f"{jftools}/register-self", {"computerName": nazwa, "publicKey": klucz.publiczny})
            if odp.kod != 200 or not odp.pole("computerId"):
                raise BladKlienta(f"JFTools nie przyjal zgloszenia: {odp.opis_bledu()}")
            # computerId w typie z JSON (liczba), nazwa z odpowiedzi - zajeta dostaje przyrostek -2, -3...
            computer_id, nazwa, status = odp.dane["computerId"], odp.pole("name") or nazwa, odp.pole("status")
            skad = "register-self"
        if self.stan.get("computerId") and str(self.stan["computerId"]) != str(computer_id):
            self.loguj(f"zmiana numeru komputera {self.stan['computerId']} -> {computer_id}: stary token do wymiany")
            self.usun_token()
            self.stan.pop("token_wydany", None)
        self.stan.update({"computerId": computer_id, "nazwa": nazwa, "klucz_zrodlo": klucz.zrodlo,
                          "klucz_prywatny": str(klucz.prywatny), "klucz_publiczny": bez_komentarza(klucz.publiczny),
                          "zgloszono": teraz()})
        if status:
            self.stan["status"] = status
        self.stan.pop("zglos_ponownie", None)
        return self.znacznik("zgloszenie", True, f"zgloszony: {nazwa} (nr {computer_id}, {skad}, status {status or '?'})")

    # -------------------------------------------------- krok: token i MCP

    def pobierz_token(self, serwer: str) -> str:
        klucz = self.klucz_zapisany()
        if klucz is None:
            self.stan["zglos_ponownie"] = True
            raise BladKlienta("brak klucza z zgloszenia - zglosze komputer ponownie przy nastepnym uruchomieniu")
        cid = self.stan["computerId"]  # w body w typie z JFTools (liczba), w podpisie jako tekst
        wymien = bool(self.stan.get("token_niewazny") or self.stan.get("token_wydany"))
        for _ in range(2):
            ts, nonce = int(time.time()), secrets.token_hex(16)
            cialo = {"computerId": cid, "ts": ts, "nonce": nonce,
                     "podpis": klucz.podpisz(TEKST_PODPISU.format(computerId=cid, ts=ts, nonce=nonce))}
            if wymien:
                cialo["wymien"] = True
            odp = zapytanie("POST", f"{serwer}/klient/token", cialo)
            if odp.kod == 200 and odp.pole("token"):
                self.zapisz_token(odp.pole("token"))
                self.stan.update({"token_wydany": teraz(), "osoba": odp.pole("osoba")})
                self.stan.pop("token_niewazny", None)
                self.stan.pop("mcp", None)
                return "nowy token" + (" (wymiana)" if wymien else "")
            kod = odp.pole("kod")
            if kod == "juz_wydany" and not wymien:
                wymien = True  # token wydany wczesniej, ale tu go nie ma (np. reinstalacja) - wymiana
                continue
            if kod == "zablokowany":
                self.stan["status"] = "blocked"
                raise BladKlienta("komputer zablokowany w JFTools - token nie zostal wydany")
            if kod == "nieznany_komputer":
                self.stan["zglos_ponownie"] = True
                if self.stan.get("klucz_zrodlo") == "ecommerce-helper":
                    self.stan["ecommerce_helper_nieznany"] = True
                raise BladKlienta(f"serwer nie zna komputera nr {cid} - zglosze go ponownie przy nastepnym uruchomieniu")
            raise BladKlienta(f"serwer nie wydal tokenu: {odp.opis_bledu()}")
        raise BladKlienta("serwer nie wydal tokenu mimo wymiany (juz_wydany)")

    def claude(self, *argumenty: str) -> subprocess.CompletedProcess:
        baza = self.polecenie("claude_polecenie")
        if baza is None:
            sciezka = shutil.which("claude")
            if not sciezka:
                raise BladKlienta("nie znaleziono programu `claude` (Claude Code) w PATH")
            baza = [sciezka]
        try:
            return subprocess.run(baza + list(argumenty), capture_output=True, timeout=LIMIT_CLAUDE_S,
                                  cwd=self.home, stdin=subprocess.DEVNULL,
                                  creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        except (OSError, subprocess.TimeoutExpired) as e:
            raise BladKlienta(f"`claude {argumenty[0]} {argumenty[1]}` nie zadzialal: {jedna_linia(e, 200)}") from e

    @staticmethod
    def _tekst(r: subprocess.CompletedProcess) -> str:
        return (r.stdout or b"").decode("utf-8", "replace") + (r.stderr or b"").decode("utf-8", "replace")

    def wpis_dziala(self, url_wpisu: str, token_wpisu: str, url: str) -> bool:
        """Istniejacy wpis MCP dziala, gdy GET /klient/status z jego tokenem pod jego adresem nie daje 401.
        Brak polaczenia: adres jak nasz = nie wiadomo (BladSieci, ponowienie), inny adres = martwy wpis."""
        baza = url_wpisu[:-len("/mcp")] if url_wpisu.endswith("/mcp") else url_wpisu
        if not baza:
            return False
        try:
            odp = zapytanie("GET", f"{baza}/klient/status", token=token_wpisu or None)
        except BladSieci:
            if url_wpisu == url:
                raise
            return False
        return odp.kod != 401

    def podlacz_mcp(self, serwer: str, token: str) -> str:
        """Dodaje wpis jfwiedza, gdy go nie ma; podmienia tylko wpis, ktory nie dziala (401). Dzialajacy wpis
        z innym tokenem (np. reczny token admina) zostaje nietkniety."""
        url = f"{serwer}/mcp"
        skrot = hashlib.sha256(token.encode("utf-8")).hexdigest()
        mcp = self.stan.get("mcp") or {}
        if mcp.get("token_sha256") == skrot and mcp.get("url") == url and \
                time.time() - float(mcp.get("sprawdzono_ts") or 0) < SPRAWDZ_MCP_CO_S:
            return "MCP podlaczony (sprawdzony niedawno)"
        r = self.claude("mcp", "get", NAZWA_MCP)
        jest = r.returncode == 0
        zmien = True
        obcy = False
        if jest:
            tekst = self._tekst(r)
            m_tok = re.search(r"Authorization:\s*Bearer\s+(\S+)", tekst)
            m_url = re.search(r"URL:\s*(\S+)", tekst)
            token_wpisu, url_wpisu = (m_tok.group(1) if m_tok else ""), (m_url.group(1) if m_url else "")
            if token_wpisu and token_wpisu != token:
                self._obce_tokeny.add(token_wpisu)
            if token_wpisu == token or self.wpis_dziala(url_wpisu, token_wpisu, url):
                zmien, obcy = False, token_wpisu != token
        if not zmien:
            opis = "MCP podlaczony" + (" (istniejacy wpis z innym tokenem dziala - zostawiony)" if obcy else "")
        else:
            if jest:
                r = self.claude("mcp", "remove", NAZWA_MCP, "-s", "user")
                if r.returncode != 0:
                    raise BladKlienta(f"`claude mcp remove {NAZWA_MCP}` nie zadzialal: {jedna_linia(self._tekst(r), 300)}")
            r = self.claude("mcp", "add", "--transport", "http", "--scope", "user", NAZWA_MCP, url,
                            "--header", f"Authorization: Bearer {token}")
            if r.returncode != 0:
                raise BladKlienta(f"`claude mcp add {NAZWA_MCP}` nie zadzialal: {jedna_linia(self._tekst(r), 300)}")
            r = self.claude("mcp", "get", NAZWA_MCP)
            if r.returncode != 0 or f"Bearer {token}" not in self._tekst(r):
                raise BladKlienta(f"po `claude mcp add` wpis {NAZWA_MCP} nie ma nowego tokenu")
            opis = "MCP podmieniony (stary wpis nie dzialal)" if jest else "MCP dodany"
        self.stan["mcp"] = {"token_sha256": skrot, "url": url, "obcy_token": obcy, "sprawdzono_ts": time.time(),
                            "sprawdzono": teraz()}
        return opis

    def krok_token(self, serwer: str) -> bool:
        if not self.stan.get("computerId") or self.stan.get("zglos_ponownie"):
            return self.znacznik("token", False, "czeka na zgloszenie komputera")
        co = "token zapisany wczesniej"
        if self.token() is None or self.stan.get("token_niewazny"):
            co = self.pobierz_token(serwer)
        return self.znacznik("token", True, f"{co}; {self.podlacz_mcp(serwer, self.token())}")

    # -------------------------------------------------- krok: status

    def pobierz_status(self, serwer: str) -> str:
        odp = zapytanie("GET", f"{serwer}/klient/status", token=self.token())
        if odp.kod == 401:
            self.stan["token_niewazny"] = True
            raise BladKlienta(f"serwer nie przyjal tokenu ({odp.opis_bledu()}) - wymienie go przy nastepnym uruchomieniu")
        if odp.kod == 403:
            status = odp.pole("status") or "blocked"
        elif odp.kod == 404:
            status = "nieznany"
        elif odp.kod == 200 and odp.pole("status"):
            status = odp.pole("status")
            if odp.pole("osoba"):
                self.stan["osoba"] = odp.pole("osoba")
        else:
            raise BladKlienta(f"dziwna odpowiedz /klient/status: {odp.opis_bledu()}")
        self.stan["status"], self.stan["status_sprawdzono"] = status, teraz()
        return status

    # -------------------------------------------------- krok: wysylka

    def pliki_kolejki(self) -> list[Path]:
        return sorted(self.kolejka.glob("*.json")) if self.kolejka.is_dir() else []

    def odloz(self, katalog: Path, nazwa: str, dane) -> Path:
        cel = katalog / nazwa
        if cel.exists():
            cel = katalog / f"{Path(nazwa).stem}-{datetime.now():%Y%m%d-%H%M%S}-{secrets.token_hex(2)}.json"
        zapisz_json(cel, dane)
        return cel

    def dopisz_wyslane(self, plik: Path, wpisy: list[dict]) -> None:
        cel = self.wyslano / plik.name
        dane = {"wpisy": []}
        if cel.exists():
            try:
                dane = czytaj_json(cel)
            except (OSError, ValueError):
                cel = self.odloz(self.wyslano, plik.name, {"wpisy": []})
                dane = {"wpisy": []}
        dane.setdefault("wpisy", []).extend(wpisy)
        zapisz_json(cel, dane)

    def zapisz_reszte(self, plik: Path, naglowek: dict, wpisy: list[dict]) -> None:
        if wpisy:
            zapisz_json(plik, {**naglowek, "wpisy": wpisy})
        else:
            plik.unlink(missing_ok=True)

    def wyslij_plik(self, serwer: str, plik: Path, licznik: dict) -> str | None:
        """Wysyla jeden plik kolejki. Zwraca powod przerwania calej wysylki albo None."""
        try:
            surowe = czytaj_json(plik)
        except (OSError, ValueError) as e:
            cel = self.odloz(self.odrzucone, plik.name, {"powod": f"zly JSON: {jedna_linia(e, 200)}",
                                                         "tresc": plik.read_text(encoding="utf-8", errors="replace")})
            plik.unlink()
            licznik["bledy"].append(f"{plik.name}: zly JSON -> {cel}")
            return None
        naglowek = {k: v for k, v in surowe.items() if k != "wpisy"} if isinstance(surowe, dict) else {}
        wpisy = surowe.get("wpisy") if isinstance(surowe, dict) else surowe
        wpisy = wpisy if isinstance(wpisy, list) else []
        poprawny = lambda w: isinstance(w, dict) and bool(w.get("klucz")) and bool(w.get("tresc"))  # noqa: E731
        reszta = [w for w in wpisy if poprawny(w)]
        zle = [w for w in wpisy if not poprawny(w)]
        if zle:  # zle wpisy od razu z kolejki - inaczej kazdy tick odkladalby je od nowa
            cel = self.odloz(self.odrzucone, plik.name, {**naglowek, "powod": "wpis bez klucza albo tresci",
                                                         "wpisy": zle})
            licznik["bledy"].append(f"{plik.name}: {len(zle)} wpisow bez klucza/tresci -> {cel}")
            self.zapisz_reszte(plik, naglowek, reszta)
        elif not reszta:  # plik bez wpisow - nic do wyslania, nie wisi w kolejce
            self.odloz(self.wyslano, plik.name, surowe)
            plik.unlink()
        nieudane: list[dict] = []
        powod = None
        while reszta:
            paczka = reszta[:PACZKA]
            paczka_id = f"{self.stan.get('computerId')}-{plik.stem}-" + \
                hashlib.sha256("\n".join(str(w["klucz"]) for w in paczka).encode("utf-8")).hexdigest()[:12]
            odp = zapytanie("POST", f"{serwer}/klient/wpisy",
                       {"paczka_id": paczka_id, "wpisy": [{k: w[k] for k in POLA_WPISU if k in w} for w in paczka]},
                       token=self.token())
            if odp.kod == 409:
                powod = "czeka na zatwierdzenie w JFTools"
            elif odp.kod == 403:
                self.stan["status"] = "blocked"
                powod = f"serwer odmowil (zablokowany albo nieznany komputer): {odp.opis_bledu()}"
            elif odp.kod == 401:
                self.stan["token_niewazny"] = True
                powod = "serwer nie przyjal tokenu - wymienie go przy nastepnym uruchomieniu"
            if powod:
                break
            wyniki = odp.dane.get("wyniki") if odp.kod == 200 and isinstance(odp.dane, dict) else None
            wg_klucza = {str(x.get("klucz")): x for x in wyniki if isinstance(x, dict)} if isinstance(wyniki, list) else {}
            if not isinstance(wyniki, list):
                licznik["bledy"].append(f"{plik.name}: paczka {paczka_id} odrzucona: {odp.opis_bledu()}")
            gotowe = []
            for w in paczka:
                x = wg_klucza.get(str(w["klucz"])) or {}
                if x.get("wynik") in WYNIKI_GOTOWE:
                    gotowe.append({**w, "wynik": x["wynik"], "wyslano": teraz()})
                    licznik[x["wynik"]] = licznik.get(x["wynik"], 0) + 1
                else:
                    nieudane.append(w)
                    if isinstance(wyniki, list):
                        licznik["bledy"].append(f"{str(w['klucz'])[:12]}: "
                                                f"{jedna_linia(x.get('opis') or x.get('wynik') or 'brak wyniku', 150)}")
            reszta = reszta[PACZKA:]
            # Po kazdej paczce zapis na dysk - padniecie w polowie nie wysle niczego drugi raz.
            if gotowe:
                self.dopisz_wyslane(plik, gotowe)
            self.zapisz_reszte(plik, naglowek, nieudane + reszta)
            licznik["wyslane"] += len(gotowe)
        return powod

    def krok_wysylka(self, serwer: str) -> bool:
        if self.token() is None:
            return self.znacznik("wysylka", False, "brak tokenu - najpierw zgloszenie komputera")
        pliki = self.pliki_kolejki()
        status = self.pobierz_status(serwer)
        w_kolejce = sum(1 for _ in pliki)
        if status == "pending":
            return self.znacznik("wysylka", True, f"czeka na zatwierdzenie w JFTools (plikow w kolejce: {w_kolejce})")
        if status != "active":
            return self.znacznik("wysylka", False, f"komputer ma status '{status}' w JFTools - nic nie wyslano "
                                                   f"(plikow w kolejce: {w_kolejce})")
        if not pliki:
            return self.znacznik("wysylka", True, "nic do wyslania")
        licznik = {"wyslane": 0, "bledy": []}
        powod = None
        for plik in pliki:
            powod = self.wyslij_plik(serwer, plik, licznik)
            if powod:
                break
        self.stan["wysylka"] = {"czas": teraz(), "wyslane": licznik["wyslane"],
                                "lacznie": int((self.stan.get("wysylka") or {}).get("lacznie") or 0) + licznik["wyslane"]}
        wynik = ", ".join(f"{k} {licznik[k]}" for k in WYNIKI_GOTOWE if licznik.get(k))
        opis = f"wyslano {licznik['wyslane']}" + (f" ({wynik})" if wynik else "")
        zostalo = sum(1 for _ in self.pliki_kolejki())
        if powod == "czeka na zatwierdzenie w JFTools":
            return self.znacznik("wysylka", True, f"{opis}; {powod} (plikow w kolejce: {zostalo})")
        if powod:
            return self.znacznik("wysylka", False, f"{opis}; przerwano: {powod} (plikow w kolejce: {zostalo})")
        if licznik["bledy"]:
            return self.znacznik("wysylka", False, f"{opis}; bledy {len(licznik['bledy'])} (zostaja w kolejce "
                                                   f"albo w odrzucone\\): " + "; ".join(licznik["bledy"][:5]))
        return self.znacznik("wysylka", True, opis)

    # -------------------------------------------------- krok: przeglad

    def pobierz_tematy(self, serwer: str) -> None:
        odp = zapytanie("GET", f"{serwer}/klient/tematy", token=self.token())
        if odp.kod != 200 or not isinstance(odp.dane, dict) or not isinstance(odp.dane.get("tematy"), list):
            if odp.kod == 401:
                self.stan["token_niewazny"] = True
            raise BladKlienta(f"nie da sie pobrac tematow: {odp.opis_bledu()}")
        zapisz_json(self.tematy_plik, {**odp.dane, "pobrano": teraz()})
        self.stan["tematy"] = {"pobrano": teraz(), "wersja": odp.pole("wersja")}

    def polecenie_przegladu(self) -> list[str]:
        return self.polecenie("przeglad_polecenie") or [
            sys.executable, str(Path(__file__).resolve().parents[1] / "wiedza-firmy-przeglad" / "przeglad.py"),
            "--profil", "klient", "--format", "json"]

    def przeglad_zrobiony(self) -> bool:
        return (self.stan.get("przeglad") or {}).get("stan") == "zakonczony"

    def uruchom_przeglad(self, polecenie: list[str] | None = None, home: Path | None = None,
                         log_plik: Path | None = None) -> tuple[bool, str]:
        """Bez zamka glownego (trwa godzinami); wynik wpisuje wolajacy. Wznawianie robi sam przeglad.py.
        Krok dzienny podaje wlasne polecenie (z --baza), home (dzienny\\<dzien>) i log."""
        polecenie = polecenie or self.polecenie_przegladu()
        home = home or self.home
        log_plik = log_plik or self.log_przegladu
        env = {**os.environ, HOME_ZMIENNA: str(home), "PYTHONIOENCODING": "utf-8"}
        home.mkdir(parents=True, exist_ok=True)
        if log_plik.exists() and log_plik.stat().st_size > LOG_MAX_BAJTOW:
            zapisz_atomowo(log_plik, log_plik.read_bytes()[-LOG_MAX_BAJTOW // 2:])
        with open(log_plik, "ab") as log:
            log.write(f"\n===== {teraz()} start: {' '.join(polecenie)}\n".encode("utf-8"))
            log.flush()
            try:
                r = subprocess.run(polecenie, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, env=env,
                                   cwd=self.home, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            except OSError as e:
                return False, f"nie da sie uruchomic przegladu: {jedna_linia(e, 200)}"
            log.write(f"===== {teraz()} koniec, kod {r.returncode}\n".encode("utf-8"))
        if r.returncode == 0:
            return True, "przeglad zakonczony"
        ogon = log_plik.read_text(encoding="utf-8", errors="replace").strip().splitlines()[-4:-1]
        # przeglad.py: 1 = dziury (ponowienie tym samym poleceniem wznawia), 2 = odmowa (np. zly tematy-cache.json)
        rodzaj = {1: "przeglad niekompletny", 2: "przeglad odmowil pracy"}.get(r.returncode, "przeglad przerwany")
        return False, f"{rodzaj} (kod {r.returncode}), wznowie przy nastepnym uruchomieniu; " \
                      f"log {log_plik}: {' / '.join(ogon)}"

    # -------------------------------------------------- krok: dzienny

    def dzienny_wlaczony(self) -> bool:
        return self.ustawienie("dzienny") == DZIENNY_TRYB

    def dzienny_od(self) -> date | None:
        """"dzienny_od" z konfiguracja.json (tylko przy wlaczonym dziennym); zly zapis to blad, nie cisza."""
        w = self.ustawienie("dzienny_od") if self.dzienny_wlaczony() else None
        if not w:
            return None
        try:
            return date.fromisoformat(str(w))
        except ValueError:
            raise BladKlienta(f"zle \"dzienny_od\" w {self.konf_plik}: {jedna_linia(w, 50)!r} (ma byc RRRR-MM-DD)") from None

    def _dzienny_od_bez_bledu(self) -> date | None:
        try:
            return self.dzienny_od()
        except BladKlienta:
            return None  # blad pokaze znacznik dzienny; przeglad historii idzie wtedy normalnie

    def baza_lore(self) -> Path:
        w = self.ustawienie("lore_baza")
        if w:
            return Path(str(w))
        lore = str(Path(__file__).resolve().parents[2] / "lore")
        if lore not in sys.path:
            sys.path.insert(0, lore)
        from lore.db import DB_PATH  # srodowisko uv Lore (jak przeglad.py)
        return DB_PATH

    def lore_wczytal_do(self, baza: Path) -> datetime | None:
        """Do kiedy Lore na pewno wczytal rozmowy: najpozniejszy indexed_at albo ts (oba ISO UTC)."""
        if not baza.exists():
            raise BladKlienta(f"brak bazy Lore: {baza}")
        conn = sqlite3.connect(f"file:{baza.as_posix()}?mode=ro", uri=True)
        try:
            kolumny = {r[1] for r in conn.execute("PRAGMA table_info(chunks)")}
            pola = "max(ts)" + (", max(indexed_at)" if "indexed_at" in kolumny else "")
            wiersz = conn.execute(f"SELECT {pola} FROM chunks").fetchone()
        finally:
            conn.close()
        czasy = [c for c in (czas_lokalny(x) for x in wiersz if x) if c]
        return max(czasy) if czasy else None

    def zbuduj_baze_dnia(self, baza: Path, dzien: date, granica: datetime | None, cel: Path) -> int:
        """Kopia tabeli chunks tylko z dnia `dzien` (czas lokalny), od `granica`. Zwraca liczbe chunkow rozmowy."""
        od, do = (dzien - timedelta(days=1)).isoformat(), (dzien + timedelta(days=2)).isoformat()  # ts jest w UTC
        src = sqlite3.connect(f"file:{baza.as_posix()}?mode=ro", uri=True)
        try:
            kolumny = {r[1] for r in src.execute("PRAGMA table_info(chunks)")}
            wybor = ", ".join(k if k in kolumny or k != "indexed_at" else "'' AS indexed_at" for k in KOLUMNY_CHUNKOW)
            wiersze = []
            for r in src.execute(f"SELECT {wybor} FROM chunks WHERE ts >= ? AND ts < ?", (od, do)):
                c = czas_lokalny(r[6])
                if c and c.date() == dzien and (granica is None or c >= granica):
                    wiersze.append(r)
        finally:
            src.close()
        cel.parent.mkdir(parents=True, exist_ok=True)
        cel.unlink(missing_ok=True)
        dst = sqlite3.connect(cel)
        try:
            dst.execute("CREATE TABLE chunks (id INTEGER PRIMARY KEY, project TEXT NOT NULL, session TEXT NOT NULL,"
                        " file TEXT NOT NULL, line INTEGER NOT NULL, part INTEGER NOT NULL DEFAULT 0, ts TEXT NOT NULL,"
                        " role TEXT NOT NULL, text TEXT NOT NULL, indexed_at TEXT NOT NULL DEFAULT '')")
            dst.executemany(f"INSERT INTO chunks VALUES ({','.join('?' * len(KOLUMNY_CHUNKOW))})", wiersze)
            dst.commit()
        finally:
            dst.close()
        return sum(1 for r in wiersze if r[7] in ROLE_ROZMOWY)

    def plik_dnia(self, d: date) -> Path:
        return self.kolejka / f"dzienne-{d.isoformat()}.json"

    def dzien_zrobiony(self, d: date) -> bool:
        s = ((self.stan.get("dzienny") or {}).get("dni") or {}).get(d.isoformat()) or {}
        return s.get("stan") == "zrobiony" or self.plik_dnia(d).exists() or (self.wyslano / self.plik_dnia(d).name).exists()

    def tematy_dzienne(self, serwer: str) -> str | None:
        """Swieze tematy z serwera, gdy jest token; przy awarii (albo bez tokenu) ostatnie z tematy-cache.json.
        Zwraca powod czekania (brak tokenu i cache) albo None."""
        if self.token() is not None:
            try:
                self.pobierz_tematy(serwer)
                return None
            except (BladSieci, BladKlienta) as e:
                if not self.tematy_plik.exists():
                    raise BladKlienta(f"brak tematow - {e}") from e
                self.loguj(f"UWAGA: tematy z serwera niedostepne ({jedna_linia(e, 200)}) - dzienny bierze "
                           f"{self.tematy_plik.name} z {(self.stan.get('tematy') or {}).get('pobrano') or '?'}")
                return None
        return None if self.tematy_plik.exists() else "czeka na token (tematy wiedzy podaje serwer)"

    def przygotuj_dzienny(self, serwer: str):
        """Pod zamkiem glownym: ktore dni przejrzec teraz. Niepusta lista = zamek dzienny.lock zdobyty (zwalnia
        przeprowadz_dzienny); [] = nic teraz (znacznik mowi czemu); False = blad (znacznik)."""
        if not self.dzienny_wlaczony():
            if (self.znaczniki / "dzienny.txt").exists():  # byl wlaczony - stary znacznik nie moze zostarzec w alarm
                self.znacznik("dzienny", True, f"wylaczony (konfiguracja.json bez \"dzienny\": \"{DZIENNY_TRYB}\")")
            return []
        if self.stan.get("status") == "blocked":
            return self.znacznik("dzienny", False, "komputer zablokowany w JFTools - dzienny przeglad wstrzymany")
        po_starcie = sekundy_od_startu()
        if po_starcie < DZIENNY_PO_STARCIE_S:
            self.znacznik("dzienny", True, f"czekam {DZIENNY_PO_STARCIE_S // 60} min po starcie Windows "
                                           f"(minelo {int(po_starcie)} s)")
            return []
        od = self.dzienny_od()
        if od:
            pierwszy, granica = od, None
        elif self.przeglad_zrobiony():
            granica = czas_lokalny((self.stan.get("przeglad") or {}).get("start"))
            if granica is None:
                return self.znacznik("dzienny", False, "stan.json nie ma czasu startu przegladu historii - nie wiem, "
                                                       "od kiedy czytac (ustaw \"dzienny_od\" albo `przeglad --ponow`)")
            pierwszy = granica.date()
        else:
            p = (self.stan.get("przeglad") or {}).get("stan") or "nie robiony"
            self.znacznik("dzienny", True, f"czeka na pierwszy przeglad calej historii ({'trwa' if self.przeglad_trwa else p})"
                                           f" - rozmowy sprzed jego startu przeczyta on sam")
            return []
        if not self.zamek_przegladu.zdobadz(0):  # np. reczne `przeglad --ponow` - nie czytac tego samego naraz
            self.znacznik("dzienny", True, "przeglad historii trwa w innym procesie - dzienny poczeka")
            return []
        self.zamek_przegladu.zwolnij()
        if not self.zamek_dzienny.zdobadz(0):
            self.loguj("dzienny przeglad juz trwa w innym procesie - nie uruchamiam drugiego")
            return []
        try:
            wczoraj = dzis() - timedelta(days=1)
            d = max(pierwszy, dzis() - timedelta(days=DZIENNY_NADRABIA_DNI))
            dni = []
            while d <= wczoraj:
                if not self.dzien_zrobiony(d):
                    dni.append(d)
                d += timedelta(days=1)
            if not dni:
                self.znacznik("dzienny", True, f"nic do zrobienia - dni do {wczoraj} zrobione (od {pierwszy})"
                              if pierwszy <= wczoraj else f"pierwszy dzien do przejrzenia: {pierwszy}")
                self.zamek_dzienny.zwolnij()
                return []
            wczytane = self.lore_wczytal_do(self.baza_lore())
            gotowe = [d for d in dni if wczytane and wczytane >= koniec_dnia(d)]
            if not gotowe:
                self.znacznik("dzienny", True, f"czekam, az Lore wczyta rozmowy z konca dnia {dni[0]} (ostatnio "
                                               f"wczytane: {wczytane.isoformat(timespec='minutes') if wczytane else 'nic'})")
                self.zamek_dzienny.zwolnij()
                return []
            czekaj = self.tematy_dzienne(serwer)
            if czekaj:
                self.znacznik("dzienny", True, f"{czekaj}; do przejrzenia: {', '.join(map(str, gotowe))}")
                self.zamek_dzienny.zwolnij()
                return []
        except BaseException:
            self.zamek_dzienny.zwolnij()
            raise
        self._granica_dzienna = granica
        self.znacznik("dzienny", True, f"przegladam dni: {', '.join(map(str, gotowe))}")
        return gotowe

    def koszt_dziennikow(self, kat: Path) -> dict[Path, int]:
        """Ile wierszy maja teraz dzienniki koszt.tsv przegladu dnia (paczki, konsolidacja, tematy dodatkowe)."""
        return {p: max(0, len(p.read_text(encoding="utf-8").splitlines()) - 1) for p in kat.rglob("koszt.tsv")}

    def koszt_proby(self, kat: Path, przed: dict[Path, int]) -> dict:
        """Suma wierszy dopisanych do koszt.tsv od `przed` - kazdy wiersz to jedno wywolanie `claude -p`,
        tokeny i $ z jego koperty (usage, total_cost_usd); wywolanie bez koperty liczy sie, tokenow nie ma."""
        s = {"wywolan": 0, **{pole: 0 for pole, _ in POLA_KOSZTU}, "usd": 0.0}
        for p in kat.rglob("koszt.tsv"):
            try:
                linie = p.read_text(encoding="utf-8").splitlines()
            except OSError:
                continue
            if not linie:
                continue
            kol = linie[0].split("\t")
            for w in linie[1:][przed.get(p, 0):]:
                d = dict(zip(kol, w.split("\t")))
                s["wywolan"] += 1
                for pole, kolumna in POLA_KOSZTU:
                    try:
                        s[pole] += int(float(d.get(kolumna) or 0))
                    except ValueError:
                        pass
                try:
                    s["usd"] += float(d.get("koszt_usd") or 0)
                except ValueError:
                    pass
        return s

    def dopisz_koszt(self, d: date, koszt: dict, faktow: int, ok: bool, blad: str | None) -> None:
        """Jedna linia koszty.jsonl na probe dnia (format ustalony ze strona kosztow - nie zmieniac)."""
        linia = {"dzien": d.isoformat(), "czas": teraz(), "wersja": DZIENNY_TRYB, "wywolan": koszt["wywolan"],
                 **{pole: koszt[pole] for pole, _ in POLA_KOSZTU},
                 "razem": sum(koszt[pole] for pole, _ in POLA_KOSZTU), "usd": round(koszt["usd"], 4),
                 "faktow": faktow, "ok": ok, "blad": None if ok else jedna_linia(blad or "blad", 500)}
        with open(self.koszty_plik, "a", encoding="utf-8", newline="\n") as f:
            f.write(json.dumps(linia, ensure_ascii=False) + "\n")

    def wpisy_pliku_dnia(self, d: date) -> list[dict]:
        p = self.plik_dnia(d)
        try:
            dane = czytaj_json(p) if p.exists() else {}
        except (OSError, ValueError):
            return []
        w = dane.get("wpisy") if isinstance(dane, dict) else None
        return w if isinstance(w, list) else []

    def przenies_kolejke_dnia(self, d: date, kat: Path) -> int:
        """Kolejka przegladu dnia (dzienny\\<dzien>\\kolejka\\przeglad-*.json) -> kolejka\\dzienne-<dzien>.json,
        atomowo, bez dubli kluczy; zrodlo mowi, z ktorego dnia. Zwraca liczbe wpisow w pliku dnia."""
        pliki = sorted((kat / "kolejka").glob("przeglad-*.json"))
        wpisy = self.wpisy_pliku_dnia(d)
        klucze = {w.get("klucz") for w in wpisy if isinstance(w, dict)}
        wersja = ""
        for p in pliki:
            dane = czytaj_json(p)
            wersja = str(dane.get("wersja_tematow") or wersja)
            for w in dane.get("wpisy") or []:
                if isinstance(w, dict) and w.get("klucz") not in klucze:
                    klucze.add(w.get("klucz"))
                    wpisy.append({**w, "zrodlo": f"dzienny przeglad rozmow (Lore) z dnia {d.isoformat()}"})
        if pliki and wpisy:
            zapisz_json(self.plik_dnia(d), {"format": FORMAT_KOLEJKI, "rodzaj": "dzienny", "dzien": d.isoformat(),
                                            "utworzono": teraz(), "wersja_tematow": wersja, "wpisy": wpisy})
        for p in pliki:  # dopiero po zapisie pliku dnia - padniecie w srodku niczego nie gubi
            p.unlink()
        return len(wpisy)

    def przejrzyj_dzien(self, d: date) -> tuple[bool, int, str]:
        """Poza zamkiem glownym (pod dzienny.lock). Zawsze konczy sie linia w koszty.jsonl."""
        kat = self.dzienny_kat / d.isoformat()
        baza_dnia = kat / "dzien.db"
        kat.mkdir(parents=True, exist_ok=True)
        przed = self.koszt_dziennikow(kat)
        faktow = 0
        try:
            shutil.copyfile(self.tematy_plik, kat / "tematy-cache.json")
            n = self.zbuduj_baze_dnia(self.baza_lore(), d, self._granica_dzienna, baza_dnia)
            if n == 0:
                ok, opis = True, "brak rozmow tego dnia - bez wywolan modelu"
            else:
                ok, opis = self.uruchom_przeglad(self.polecenie_przegladu() + ["--baza", str(baza_dnia)], kat,
                                                 kat / "przeglad.log")
                if ok:
                    faktow = self.przenies_kolejke_dnia(d, kat)
                    opis = f"{faktow} faktow w {self.plik_dnia(d).name} (z {n} fragmentow rozmow)"
        except (OSError, ValueError, sqlite3.Error, BladKlienta) as e:
            ok, opis = False, f"nieoczekiwany blad {type(e).__name__}: {jedna_linia(e, 300)}"
        finally:
            baza_dnia.unlink(missing_ok=True)  # kopia rozmow nie lezy dluzej niz trzeba
        if not ok:
            faktow = len(self.wpisy_pliku_dnia(d))
        koszt = self.koszt_proby(kat, przed)
        self.dopisz_koszt(d, koszt, faktow, ok, opis)
        return ok, faktow, f"{opis}; wywolan {koszt['wywolan']}, ${koszt['usd']:.2f}"

    def przytnij_dzienne(self) -> None:
        granica = (dzis() - timedelta(days=DZIENNY_TRZYMAJ_DNI)).isoformat()
        dni = (self.stan.get("dzienny") or {}).get("dni") or {}
        for k in [k for k in dni if k < granica]:
            dni.pop(k)
        if self.dzienny_kat.is_dir():
            for kat in self.dzienny_kat.iterdir():
                if kat.is_dir() and kat.name < granica:
                    shutil.rmtree(kat, ignore_errors=True)

    def przeprowadz_dzienny(self, dni: list[date]) -> int:
        """Przeglady dni poza zamkiem glownym (pod dzienny.lock z przygotuj_dzienny), wynik i wysylka pod glownym."""
        wyniki = []
        try:
            for d in dni:
                try:
                    wyniki.append((d, *self.przejrzyj_dzien(d)))
                except Exception as e:  # linia kosztu albo cos zupelnie nieprzewidzianego - dzien wroci
                    wyniki.append((d, False, 0, f"nieoczekiwany blad {type(e).__name__}: {jedna_linia(e, 300)}"))
        finally:
            self.zamek_dzienny.zwolnij()
        zle = [w for w in wyniki if not w[1]]
        opis = "; ".join(f"{d}: {'ok' if ok else 'BLAD'} {o}" for d, ok, _f, o in wyniki)

        def praca(serwer, jftools):
            dni_st = self.stan.setdefault("dzienny", {}).setdefault("dni", {})
            for d, ok, faktow, o in wyniki:
                s = dni_st.setdefault(d.isoformat(), {})
                s.update({"stan": "zrobiony" if ok else "blad", "proby": int(s.get("proby") or 0) + 1,
                          "faktow": faktow, "koniec": teraz(), "opis": jedna_linia(o, 300)})
            self.stan["dzienny"]["ostatni"] = teraz()
            self.przytnij_dzienne()
            self.znacznik("dzienny", not zle, opis + ("; nieudane dni ponowie przy nastepnym uruchomieniu" if zle else ""))
            return 0 if self._krok("wysylka", self.krok_wysylka, serwer) and not zle else 1
        w = self._z_zamkiem("dzienny", CZEKAJ_NA_ZAMEK_S, praca)
        if w is None:  # stan nie zapisany - plik dnia w kolejce i tak nie da zrobic dnia drugi raz
            self.znacznik("dzienny", not zle, f"{opis}; nie zapisano stanu (zamek zajety)")
            return 1
        return w

    # -------------------------------------------------- polecenia

    def _krok(self, krok: str, funkcja, *argumenty) -> bool:
        """Kazdy blad konczy sie znacznikiem - zaden krok nie pada po cichu."""
        try:
            return funkcja(*argumenty)
        except BladSieci as e:
            return self.znacznik(krok, False, f"{e} - ponowie przy nastepnym uruchomieniu")
        except BladKlienta as e:
            return self.znacznik(krok, False, str(e))
        except Exception as e:  # nieprzewidziany - tez do znacznika
            return self.znacznik(krok, False, f"nieoczekiwany blad {type(e).__name__}: {e}")

    def _z_zamkiem(self, krok_bledu: str, czekaj_s: float, praca) -> int | None:
        if not self.zamek.zdobadz(czekaj_s):
            self.loguj(f"inny proces klient.py trzyma {self.zamek.sciezka} - pomijam ({krok_bledu})")
            return None
        try:
            self.wczytaj_stan()
            try:
                serwer, jftools = self.konfiguracja()
            except BladKlienta as e:
                for k in ("zgloszenie", "token", "wysylka", "przeglad") if krok_bledu == "tick" else (krok_bledu,):
                    self.znacznik(k, False, str(e))
                self.zapisz_stan()
                return 1
            wynik = praca(serwer, jftools)
            self.zapisz_stan()
            return wynik
        finally:
            self.zwolnij_zamek()

    def zwolnij_zamek(self) -> None:
        self.zamek.zwolnij()

    def cmd_zglos(self) -> int:
        def praca(serwer, jftools):
            ok = self._krok("zgloszenie", self.krok_zgloszenie, jftools)
            ok = self._krok("token", self.krok_token, serwer) if ok else \
                self.znacznik("token", False, "czeka na zgloszenie komputera")
            return 0 if ok else 1
        w = self._z_zamkiem("zgloszenie", CZEKAJ_RECZNIE_S, praca)
        return 2 if w is None else w

    def cmd_status(self) -> int:
        def praca(serwer, jftools):
            if self.token() is None:
                self.znacznik("status", False, "brak tokenu - najpierw `klient.py zglos`")
                return 1
            ok = self._krok("status", lambda: self.znacznik("status", True, f"status: {self.pobierz_status(serwer)}"
                                                            f" (komputer {self.stan.get('computerId')}, osoba "
                                                            f"{self.stan.get('osoba') or '?'})"))
            return 0 if ok else 1
        w = self._z_zamkiem("status", CZEKAJ_RECZNIE_S, praca)
        return 2 if w is None else w

    def cmd_wyslij(self) -> int:
        w = self._z_zamkiem("wysylka", CZEKAJ_RECZNIE_S, lambda serwer, jftools: 0 if self._krok("wysylka", self.krok_wysylka, serwer) else 1)
        return 2 if w is None else w

    def przygotuj_przeglad(self, serwer: str, ponow: bool) -> bool:
        """Pod zamkiem glownym: czy przeglad jest potrzebny i czy ma tematy. True = uruchamiac."""
        if self.przeglad_zrobiony() and not ponow:
            p = self.stan["przeglad"]
            self.znacznik("przeglad", True, f"zakonczony {p.get('zakonczono')} - nie powtarzam")
            return False
        od = self._dzienny_od_bez_bledu()
        if od and not ponow:  # historie sprzed `od` przejrzano inna droga, dalej idzie krok dzienny - bez dubli
            self.przeglad_pominiety = True
            self.znacznik("przeglad", True, f"pominiety: konfiguracja dzienny_od={od} (historia sprzed tego dnia "
                                            f"przejrzana inna droga), dni od {od} robi krok dzienny")
            return False
        if self.token() is None:
            self.znacznik("przeglad", False, "czeka na token (zgloszenie komputera)")
            return False
        if not self.zamek_przegladu.zdobadz(0):
            self.przeglad_trwa = True
            self.loguj("przeglad juz trwa w innym procesie - nie uruchamiam drugiego")
            return False
        if not self._krok("przeglad", lambda: self.pobierz_tematy(serwer) or True):
            self.zamek_przegladu.zwolnij()
            return False
        p = self.stan.setdefault("przeglad", {})
        p.update({"stan": "w_toku", "start": teraz(), "proby": int(p.get("proby") or 0) + 1})
        self.znacznik("przeglad", True, f"uruchamiam przeglad historii (proba {p['proby']})")
        return True

    def przeprowadz_przeglad(self) -> int:
        """Poza zamkiem glownym (pod wlasnym, zdobytym w przygotuj_przeglad), wynik i wysylka pod glownym."""
        try:
            ok, opis = self.uruchom_przeglad()
        finally:
            self.zamek_przegladu.zwolnij()

        def praca(serwer, jftools):
            p = self.stan.setdefault("przeglad", {})
            p.update({"stan": "zakonczony" if ok else "blad", "ostatni_koniec": teraz()})
            if ok:
                p["zakonczono"] = teraz()
            self.znacznik("przeglad", ok, opis)
            return 0 if ok and self._krok("wysylka", self.krok_wysylka, serwer) else 1
        w = self._z_zamkiem("przeglad", CZEKAJ_NA_ZAMEK_S, praca)
        if w is None:  # wynik nie wpisany do stanu - przeglad powtorzy sie (wznowi) przy nastepnym ticku
            self.znacznik("przeglad", False, f"{opis}; nie zapisano wyniku (zamek zajety) - sprawdze ponownie")
            return 1
        return w

    def cmd_przeglad(self, ponow: bool) -> int:
        w = self._z_zamkiem("przeglad", CZEKAJ_RECZNIE_S, lambda serwer, jftools: 0 if self.przygotuj_przeglad(serwer, ponow) else -1)
        if w is None:
            return 2
        if w != 0:
            return 0 if w == -1 and (self.przeglad_zrobiony() or self.przeglad_trwa or self.przeglad_pominiety) else 1
        return self.przeprowadz_przeglad()

    def cmd_tick(self) -> int:
        def praca(serwer, jftools):
            self.stan["ostatni_tick"] = teraz()
            ok = self._krok("zgloszenie", self.krok_zgloszenie, jftools)
            ok = (self._krok("token", self.krok_token, serwer) if ok else
                  self.znacznik("token", False, "czeka na zgloszenie komputera")) and ok
            ok = self._krok("wysylka", self.krok_wysylka, serwer) and ok
            uruchom = self.przygotuj_przeglad(serwer, False)
            if not uruchom and not self.przeglad_zrobiony() and not self.przeglad_trwa and not self.przeglad_pominiety:
                ok = False
            # przeglad historii ma pierwszenstwo - dzienny najwczesniej przy kolejnym ticku (wylaczony tylko
            # odswieza swoj znacznik)
            if not uruchom or not self.dzienny_wlaczony():
                dni = self._krok("dzienny", self.przygotuj_dzienny, serwer)
                ok = ok and dni is not False
                self._dni_dzienne = dni or []
            return (2 if uruchom else 0) if ok else (3 if uruchom else 1)
        w = self._z_zamkiem("tick", 0, praca)
        if w is None:
            return 0  # inny tick pracuje - to nie blad
        if w in (2, 3):
            wp = self.przeprowadz_przeglad()
            return 0 if (w == 2 and wp == 0) else 1
        if self._dni_dzienne:
            wd = self.przeprowadz_dzienny(self._dni_dzienne)
            return w if wd == 0 else 1
        return w

    def cmd_dzienny(self) -> int:
        def praca(serwer, jftools):
            dni = self._krok("dzienny", self.przygotuj_dzienny, serwer)
            self._dni_dzienne = dni or []
            return 1 if dni is False else 0
        w = self._z_zamkiem("dzienny", CZEKAJ_RECZNIE_S, praca)
        if w is None:
            return 2
        return self.przeprowadz_dzienny(self._dni_dzienne) if w == 0 and self._dni_dzienne else w


def domyslny_home() -> Path:
    return Path(os.environ.get(HOME_ZMIENNA) or Path.home() / ".claude" / "mr" / "wiedza-firmy")


def main(argv: list[str] | None = None) -> int:
    for strumien in (sys.stdout, sys.stderr):
        if hasattr(strumien, "reconfigure"):
            strumien.reconfigure(encoding="utf-8", errors="replace")
    a = argparse.ArgumentParser(description="Klient Wiedzy firmy (jfwiedza) na komputerze pracownika")
    pod = a.add_subparsers(dest="polecenie", required=True)
    for nazwa in ("zglos", "status", "wyslij", "dzienny", "tick"):
        pod.add_parser(nazwa)
    p = pod.add_parser("przeglad")
    p.add_argument("--ponow", action="store_true", help="uruchom przeglad mimo zakonczenia")
    o = a.parse_args(argv)
    k = Klient(domyslny_home())
    if o.polecenie == "zglos":
        return k.cmd_zglos()
    if o.polecenie == "status":
        return k.cmd_status()
    if o.polecenie == "wyslij":
        return k.cmd_wyslij()
    if o.polecenie == "przeglad":
        return k.cmd_przeglad(o.ponow)
    if o.polecenie == "dzienny":
        return k.cmd_dzienny()
    return k.cmd_tick()


if __name__ == "__main__":
    sys.exit(main())
