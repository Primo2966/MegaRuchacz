"""Trasy /klient/* (krok 3, 0.4.0): komputer pracownika sam bierze token i wysyla wpisy do wiedzy firmy.

Umowa (raport wiedza-firmy-krok3-projekt.md sekcja 2), na niej buduja klient (narzedzia/wiedza-firmy-klient)
i wtyczka JFTools - zmiana ksztaltu tylko razem z nimi:

- POST /klient/token  (BEZ tokenu) {computerId, ts, nonce, podpis[, wymien]} -> 200 {token, osoba, wynik}
  albo {kod, opis}: 400 zle_dane | 401 zly_podpis (takze ts poza +-300 s i powtorzony nonce) |
  403 nieznany_komputer / zablokowany | 409 juz_wydany | 429 za_czesto | 503 jftools_niedostepny / wylaczone.
  Podpis: podpis.py. Klucz publiczny komputera z JFTools (GET keys). Jeden token na komputer: drugi tylko
  z "wymien": true (stary przestaje dzialac). Wpis w osoby.json: `komputer-<id>`, wystawil "auto".
- GET /klient/status  -> {status: active|pending|blocked|nieznany, osoba, komputer, ...}; blocked/nieznany = 403.
- GET /klient/tematy  (takze pending) -> {tematy, zasady, wersja}; zasady z zasady-klienta.md w katalogu danych.
- POST /klient/wpisy  {paczka_id, wpisy[<=100]} -> {wyniki: [{klucz, wynik: dodano|duplikat|usuniety_wczesniej|blad,
  opis?}]}; pending = 409 czeka_na_zatwierdzenie, blocked/nieznany = 403. Autor = owner.name z JFTools, bez
  niego nazwa komputera; pole autora z ciala nie jest czytane wcale.

Poza /klient/token kazda trasa wymaga `Authorization: Bearer <token>` (401 jak w /mcp). Trasy dzialaja tylko
w trybie JFTools (WIEDZA_FIRMY_UPRAWNIENIA=jftools) - bez niego 503 "wylaczone".

Kazda proba tokenu idzie do zgloszenia-klientow.log (czas | komputer | wynik | adres | opis - bez podpisu,
nonce i tokenu), liczniki od startu procesu do serwer-zyje.json (Klienci.stan).
"""

from __future__ import annotations

import hashlib
import json
import re
import threading
import time
from collections import deque
from datetime import date
from typing import Any, Callable

from starlette.concurrency import run_in_threadpool
from starlette.responses import JSONResponse

from . import jftools, osoby, podpis, sciezki
from .baza import BladWpisu, NowyWpis, sprawdz_wpis
from .pliki import log
from .wiedza import Wiedza

LIMIT_WPISOW = 100
# 100 wpisow po kilka KB z zapasem; wiecej = odmowa przed czytaniem calosci do pamieci.
LIMIT_CIALA = 2_000_000
OKNO_TS_S = 300
PAMIEC_NONCE_S = 600
# Komputer prosi o token raz (i przy wymianie); 30 prob na 10 min z jednego adresu przepuszcza biuro za jednym
# NAT-em przy instalacji na wszystkich komputerach naraz, a zatrzymuje zgadywanie / pompowanie zapytan do JFTools.
LIMIT_PROB_IP = 30
OKNO_PROB_IP_S = 600
NONCE = re.compile(r"^[A-Za-z0-9_-]{16,128}$")
LICZBA = re.compile(r"^(0|[1-9][0-9]{0,15})$")
STATUSY_KLIENTA = ("active", "pending", "blocked")
SCIEZKI = {"/klient/token": "POST", "/klient/status": "GET", "/klient/tematy": "GET", "/klient/wpisy": "POST"}
KOD_STATUSU = {"blocked": "zablokowany", "nieznany": "nieznany_komputer"}
OPIS_STATUSU = {"blocked": jftools.KOMUNIKAT_BLOCKED, "nieznany": jftools.KOMUNIKAT_NIEZNANY,
                "pending": jftools.KOMUNIKAT_PENDING}


class _Odmowa(Exception):
    def __init__(self, http: int, cialo: dict) -> None:
        super().__init__(cialo.get("kod"))
        self.http = http
        self.cialo = cialo


def _token_z_naglowka(scope: dict[str, Any]) -> str | None:
    for klucz, wartosc in scope.get("headers") or []:
        if klucz.lower() == b"authorization":
            naglowek = wartosc.decode("latin-1")
            if naglowek[:7].lower() == "bearer ":
                return naglowek[7:].strip() or None
            return None
    return None


def _odpowiedz(http: int, cialo: dict, naglowki: dict | None = None) -> JSONResponse:
    return JSONResponse(cialo, status_code=http, headers={"cache-control": "no-store", **(naglowki or {})})


class Klienci:
    """Aplikacja ASGI tras /klient/*. Jedna na proces - trzyma nonce, limity prob i liczniki."""

    def __init__(self, wiedza: Wiedza, zrodlo: Any, zegar: Callable[[], float] = time.time) -> None:
        self.wiedza = wiedza
        self.zrodlo = zrodlo
        self.zegar = zegar
        self._zamek = threading.Lock()
        self._nonce: dict[tuple[str, str], float] = {}
        self._proby_ip: dict[str, deque[float]] = {}
        self._zasady_stan: str | None = None
        self._liczniki: dict[str, Any] = {
            "od": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "tokeny": {},    # wynik proby tokenu -> ile
            "odmowy": {},    # "<trasa> <kod>" -> ile (status, tematy, wpisy)
            "wpisy": {"paczki": 0, "dodano": 0, "duplikat": 0, "usuniety_wczesniej": 0, "blad": 0},
            "ostatnia_proba_tokenu": None,
        }

    # ------------------------------------------------------------ znacznik zycia i dziennik

    def stan(self) -> dict:
        """Do serwer-zyje.json: liczniki od startu procesu (nie od poczatku swiata)."""
        with self._zamek:
            kopia = json.loads(json.dumps(self._liczniki))
            kopia["pamiec_nonce"] = len(self._nonce)
        kopia["zasady_klienta"] = self._zasady_stan or "jeszcze nie czytane"
        return {"liczniki_od_startu": kopia}

    def _licz(self, grupa: str, klucz: str, ile: int = 1) -> None:
        with self._zamek:
            self._liczniki[grupa][klucz] = self._liczniki[grupa].get(klucz, 0) + ile

    def _zapisz_probe(self, komputer: str, wynik: str, adres: str, opis: str = "") -> None:
        czas = time.strftime("%Y-%m-%dT%H:%M:%S")
        linia = f"{czas} | komputer {komputer or '?'} | {wynik} | {adres} | {opis}".replace("\n", " ")
        self._licz("tokeny", wynik)
        with self._zamek:
            self._liczniki["ostatnia_proba_tokenu"] = linia
        try:
            sciezka = sciezki.dziennik_zgloszen_klientow()
            sciezka.parent.mkdir(parents=True, exist_ok=True)
            with open(sciezka, "a", encoding="utf-8") as f:
                f.write(linia + "\n")
        except OSError as e:  # proba i tak jest w dzienniku serwera i licznikach - ale glosno
            log(f"BLAD zapisu {sciezki.dziennik_zgloszen_klientow()}: {e!r}")
        log(f"klient token: {linia}")

    # ------------------------------------------------------------ ASGI

    async def __call__(self, scope: dict[str, Any], receive: Any, send: Any) -> None:
        sciezka, metoda = scope.get("path") or "", scope.get("method") or ""
        adres = (scope.get("client") or ("?", 0))[0]
        oczekiwana = SCIEZKI.get(sciezka)
        osoba = None
        if sciezka != "/klient/token":
            osoba = await run_in_threadpool(self._osoba, _token_z_naglowka(scope))
            if osoba is None:
                log(f"401 {adres} {metoda} {sciezka}: brak albo nieznany token")
                await _odpowiedz(401, {"error": "unauthorized", "message": "Brak albo nieznany token (Authorization: Bearer)."},
                                 {"www-authenticate": 'Bearer realm="wiedza-firmy"'})(scope, receive, send)
                return
        if oczekiwana is None:
            await _odpowiedz(404, {"kod": "nie_ma_trasy", "opis": f"nie ma {sciezka}"})(scope, receive, send)
            return
        if metoda != oczekiwana:
            await _odpowiedz(405, {"kod": "zla_metoda", "opis": f"{sciezka} przyjmuje tylko {oczekiwana}"},
                             {"allow": oczekiwana})(scope, receive, send)
            return
        try:
            cialo = await self._cialo(scope, receive) if metoda == "POST" else b""
            if sciezka == "/klient/token":
                http, dane = await run_in_threadpool(self.token, cialo, adres)
            elif sciezka == "/klient/status":
                http, dane = await run_in_threadpool(self.status, osoba)
            elif sciezka == "/klient/tematy":
                http, dane = await run_in_threadpool(self.tematy, osoba)
            else:
                http, dane = await run_in_threadpool(self.wpisy, osoba, cialo)
        except _Odmowa as o:  # tu tylko za duze cialo - token() zapisuje swoje odmowy sam
            http, dane = o.http, o.cialo
            if sciezka == "/klient/token":
                self._zapisz_probe("", o.cialo.get("kod", "?"), adres, o.cialo.get("opis", ""))
        except Exception as e:  # nic nie ginie po cichu: 500 z opisem w dzienniku
            log(f"BLAD {metoda} {sciezka} ({adres}): {e!r}")
            http, dane = 500, {"kod": "blad_serwera", "opis": "Błąd serwera wiedzy - szczegóły w jego dzienniku."}
            if sciezka == "/klient/token":
                self._zapisz_probe("", "blad_serwera", adres, repr(e)[:200])
        await _odpowiedz(http, dane)(scope, receive, send)

    def _osoba(self, token: str | None) -> str | None:
        if not token:
            return None
        try:
            return self.zrodlo.osoba_dla_tokenu(token)
        except Exception as e:  # zrodlo lezy -> nikt nie wchodzi, ale glosno
            log(f"BLAD zrodla uprawnien (/klient): {e!r} - odmawiam")
            return None

    async def _cialo(self, scope: dict[str, Any], receive: Any) -> bytes:
        for klucz, wartosc in scope.get("headers") or []:
            if klucz.lower() == b"content-length" and wartosc.isdigit() and int(wartosc) > LIMIT_CIALA:
                raise _Odmowa(413, {"kod": "za_duzo", "opis": f"ciało ponad {LIMIT_CIALA} bajtów"})
        czesci: list[bytes] = []
        rozmiar = 0
        while True:
            komunikat = await receive()
            if komunikat.get("type") == "http.disconnect":
                break
            kawalek = komunikat.get("body", b"")
            rozmiar += len(kawalek)
            if rozmiar > LIMIT_CIALA:
                raise _Odmowa(413, {"kod": "za_duzo", "opis": f"ciało ponad {LIMIT_CIALA} bajtów"})
            czesci.append(kawalek)
            if not komunikat.get("more_body"):
                break
        return b"".join(czesci)

    @staticmethod
    def _json(cialo: bytes) -> dict:
        try:
            dane = json.loads(cialo.decode("utf-8-sig") or "null")
        except (UnicodeDecodeError, ValueError):
            raise _Odmowa(400, {"kod": "zle_dane", "opis": "ciało nie jest JSON-em"}) from None
        if not isinstance(dane, dict):
            raise _Odmowa(400, {"kod": "zle_dane", "opis": "oczekiwany obiekt JSON"})
        return dane

    # ------------------------------------------------------------ POST /klient/token

    def _limit_prob(self, adres: str) -> bool:
        teraz = self.zegar()
        with self._zamek:
            proby = self._proby_ip.setdefault(adres, deque())
            while proby and teraz - proby[0] > OKNO_PROB_IP_S:
                proby.popleft()
            if len(proby) >= LIMIT_PROB_IP:
                return False
            proby.append(teraz)
            for a in [a for a, p in self._proby_ip.items() if not p]:
                del self._proby_ip[a]
            return True

    def _nonce_nowy(self, komputer: str, nonce: str) -> bool:
        teraz = self.zegar()
        with self._zamek:
            for k in [k for k, t in self._nonce.items() if teraz - t > PAMIEC_NONCE_S]:
                del self._nonce[k]
            if (komputer, nonce) in self._nonce:
                return False
            self._nonce[(komputer, nonce)] = teraz
            return True

    def token(self, cialo: bytes, adres: str) -> tuple[int, dict]:
        komputer = ""

        def odmowa(http: int, kod: str, opis: str, **dodatki: Any) -> tuple[int, dict]:
            self._zapisz_probe(komputer, kod, adres, opis)
            return http, {"kod": kod, "opis": opis, **dodatki}

        if not self._limit_prob(adres):
            return odmowa(429, "za_czesto", f"ponad {LIMIT_PROB_IP} prób z tego adresu w {OKNO_PROB_IP_S // 60} min")
        if not isinstance(self.zrodlo, jftools.ZrodloJFTools):
            return odmowa(503, "wylaczone", "serwer wiedzy działa bez JFTools (WIEDZA_FIRMY_UPRAWNIENIA) - "
                                            "tokenów dla komputerów nie wydaje")
        try:
            dane = self._json(cialo)
        except _Odmowa as o:
            return odmowa(o.http, o.cialo["kod"], o.cialo["opis"])
        surowy_id, surowy_ts = dane.get("computerId"), dane.get("ts")
        nonce, podpis_klienta, wymien = dane.get("nonce"), dane.get("podpis"), dane.get("wymien", False)
        if isinstance(surowy_id, bool) or not isinstance(surowy_id, (int, str)) \
                or not jftools.ID_KOMPUTERA.match(str(surowy_id).strip()):
            return odmowa(400, "zle_dane", "computerId: numer komputera z JFTools")
        komputer = str(surowy_id).strip()
        if isinstance(surowy_ts, bool) or not isinstance(surowy_ts, (int, str)) or not LICZBA.match(str(surowy_ts)):
            return odmowa(400, "zle_dane", "ts: sekundy Unix jako liczba całkowita")
        ts = int(surowy_ts)
        if not isinstance(nonce, str) or not NONCE.match(nonce):
            return odmowa(400, "zle_dane", "nonce: 16-128 znaków A-Z a-z 0-9 _ -")
        if not isinstance(wymien, bool):
            return odmowa(400, "zle_dane", "wymien: true albo false")
        teraz = int(self.zegar())
        if abs(teraz - ts) > OKNO_TS_S:
            return odmowa(401, "zly_podpis", f"znacznik czasu różni się od zegara serwera o {teraz - ts} s "
                                             f"(dozwolone ±{OKNO_TS_S} s) - sprawdź zegar komputera",
                          czas_serwera=teraz)
        try:
            klucz = self.zrodlo.klucze.klucz(komputer)
        except jftools.BladJFTools as e:
            return odmowa(503, "jftools_niedostepny", f"nie da się pobrać kluczy z JFTools ({e}) - spróbuj później")
        if klucz is None:
            dostep, ostrzezenie = self.zrodlo.dostep(komputer)
            if dostep is None:
                return odmowa(503, "jftools_niedostepny", ostrzezenie or "JFTools nie odpowiada")
            if dostep.status == "blocked":
                return odmowa(403, "zablokowany", jftools.KOMUNIKAT_BLOCKED)
            # pending/active bez klucza w keys = lista sprzed chwili (WAZNOSC_KLUCZY_S) albo zapis klucza w panelu zly
            return odmowa(403, "nieznany_komputer", "JFTools nie podaje klucza tego komputera"
                          if dostep.status in STATUSY_KLIENTA else jftools.KOMUNIKAT_NIEZNANY)
        try:
            podpis.sprawdz(klucz["publicKey"], podpis.tekst_do_podpisu(komputer, ts, nonce), podpis_klienta)
        except podpis.BladPodpisu as e:
            return odmowa(401, "zly_podpis", str(e))
        if not self._nonce_nowy(komputer, nonce):
            return odmowa(401, "zly_podpis", "ten nonce był już użyty - każda prośba ma mieć nowy")
        try:
            token, wynik = osoby.wydaj_token_komputera(komputer, wymien, sciezka=self.zrodlo.sciezka)
        except (osoby.BladOsob, OSError, ValueError) as e:
            log(f"BLAD wydania tokenu komputerowi {komputer}: {e!r}")
            return odmowa(500, "blad_serwera", "nie udało się zapisać tokenu - szczegóły w dzienniku serwera")
        if wynik == "reczny":
            return odmowa(409, "juz_wydany", f"wpis {osoby.osoba_komputera(komputer)} założono ręcznie - "
                                             "token wydaje admin (python -m wiedza_firmy.osoby token)")
        if wynik == "juz_wydany":
            return odmowa(409, "juz_wydany", 'ten komputer ma już token; nowy tylko z "wymien": true '
                                             "(stary przestanie działać)")
        self._zapisz_probe(komputer, wynik, adres, f"status w JFTools: {klucz.get('status') or '?'}")
        return 200, {"token": token, "osoba": osoby.osoba_komputera(komputer), "wynik": wynik}

    # ------------------------------------------------------------ trasy z tokenem

    def _stan_komputera(self, osoba: str, trasa: str) -> tuple[str, str, Any, str | None]:
        """(status, komputer, dostep, ostrzezenie) albo _Odmowa (503 bez JFTools, 403 bez komputera)."""
        if not isinstance(self.zrodlo, jftools.ZrodloJFTools):
            self._licz("odmowy", f"{trasa} wylaczone")
            raise _Odmowa(503, {"kod": "wylaczone", "opis": "serwer wiedzy działa bez JFTools - trasy klienta wyłączone"})
        wpis = self.zrodlo.wpis_osoby(osoba) or {}
        komputer = wpis.get("komputer")
        if not komputer:
            self._licz("odmowy", f"{trasa} brak_komputera")
            raise _Odmowa(403, {"kod": "brak_komputera", "status": "nieznany", "osoba": osoba, "komputer": None,
                                "opis": jftools.KOMUNIKAT_BEZ_KOMPUTERA})
        dostep, ostrzezenie = self.zrodlo.dostep(komputer)
        if dostep is None:
            self._licz("odmowy", f"{trasa} jftools_niedostepny")
            raise _Odmowa(503, {"kod": "jftools_niedostepny", "opis": ostrzezenie or "JFTools nie odpowiada"})
        status = dostep.status if dostep.status in STATUSY_KLIENTA else "nieznany"
        return status, komputer, dostep, ostrzezenie

    def _bez_dostepu(self, trasa: str, status: str, osoba: str, komputer: str) -> None:
        if status in KOD_STATUSU:
            self._licz("odmowy", f"{trasa} {KOD_STATUSU[status]}")
            raise _Odmowa(403, {"kod": KOD_STATUSU[status], "status": status, "osoba": osoba, "komputer": komputer,
                                "opis": OPIS_STATUSU[status]})

    def status(self, osoba: str) -> tuple[int, dict]:
        status, komputer, dostep, ostrzezenie = self._stan_komputera(osoba, "status")
        odp: dict = {"status": status, "osoba": osoba, "komputer": komputer,
                     "nazwa_komputera": dostep.nazwa, "wlasciciel": dostep.wlasciciel}
        if status in OPIS_STATUSU:
            odp["opis"] = OPIS_STATUSU[status]
        if ostrzezenie:
            odp["uwagi"] = [ostrzezenie]
        if status in KOD_STATUSU:
            self._licz("odmowy", f"status {KOD_STATUSU[status]}")
            return 403, {"kod": KOD_STATUSU[status], **odp}
        return 200, odp

    def _zasady(self) -> str:
        sciezka = sciezki.plik_zasad_klienta()
        try:
            tekst, stan = sciezka.read_text(encoding="utf-8-sig"), "ok"
        except FileNotFoundError:
            tekst, stan = "", f"BRAK pliku {sciezka} - klienci dostaja puste zasady"
        except (OSError, UnicodeDecodeError) as e:
            tekst, stan = "", f"BLAD odczytu {sciezka} ({e!r}) - klienci dostaja puste zasady"
        if stan != self._zasady_stan:  # do dziennika przy kazdej zmianie, nie przy kazdym zapytaniu
            log(f"zasady klienta: {stan}")
            self._zasady_stan = stan
        return tekst

    def tematy(self, osoba: str) -> tuple[int, dict]:
        status, komputer, _dostep, ostrzezenie = self._stan_komputera(osoba, "tematy")
        self._bez_dostepu("tematy", status, osoba, komputer)
        tematy, blad, uwaga = self.wiedza._tematy()
        if blad:
            self._licz("odmowy", "tematy tematy_niedostepne")
            return 503, {"kod": "tematy_niedostepne", "opis": blad}
        lista = [t.jako_slownik() for t in tematy.values()]
        zasady = self._zasady()
        wersja = hashlib.sha256(json.dumps({"tematy": lista, "zasady": zasady}, ensure_ascii=False,
                                           sort_keys=True).encode("utf-8")).hexdigest()
        odp: dict = {"tematy": lista, "zasady": zasady, "wersja": wersja, "status": status}
        uwagi = [u for u in (uwaga, ostrzezenie) if u]
        if uwagi:
            odp["uwagi"] = uwagi
        return 200, odp

    @staticmethod
    def _nowy_wpis(w: Any, autor: str) -> NowyWpis:
        """Wpis z ciala klienta; pole autora (gdyby bylo) nie jest czytane - autor przychodzi z JFTools."""
        if not isinstance(w, dict):
            raise BladWpisu("wpis nie jest obiektem")

        def tekst(pole: str, domyslny: str | None = None) -> str:
            wartosc = w.get(pole, domyslny)
            if wartosc is None:
                wartosc = domyslny
            if not isinstance(wartosc, str):
                raise BladWpisu(f"pole {pole}: oczekiwany tekst")
            return wartosc

        dodatkowe = w.get("tematy_dodatkowe") or []
        if not isinstance(dodatkowe, list) or not all(isinstance(t, str) for t in dodatkowe):
            raise BladWpisu("pole tematy_dodatkowe: oczekiwana lista id tematów")
        return NowyWpis(tresc=tekst("tresc", ""), temat=tekst("temat", ""), poufnosc=tekst("poufnosc", ""),
                        autor=autor, data_ustalenia=tekst("data", date.today().isoformat()),
                        zrodlo=tekst("zrodlo", ""), program=tekst("program", ""), tematy_dodatkowe=tuple(dodatkowe))

    def wpisy(self, osoba: str, cialo: bytes) -> tuple[int, dict]:
        status, komputer, dostep, ostrzezenie = self._stan_komputera(osoba, "wpisy")
        self._bez_dostepu("wpisy", status, osoba, komputer)
        if status == "pending":
            self._licz("odmowy", "wpisy czeka_na_zatwierdzenie")
            return 409, {"kod": "czeka_na_zatwierdzenie", "status": status, "osoba": osoba, "komputer": komputer,
                         "opis": jftools.KOMUNIKAT_PENDING}
        dane = self._json(cialo)
        wpisy = dane.get("wpisy")
        if not isinstance(wpisy, list):
            return 400, {"kod": "zle_dane", "opis": "wpisy: oczekiwana lista"}
        if len(wpisy) > LIMIT_WPISOW:
            self._licz("odmowy", "wpisy za_duzo")
            return 413, {"kod": "za_duzo", "opis": f"najwyżej {LIMIT_WPISOW} wpisów w paczce (jest {len(wpisy)})",
                         "limit": LIMIT_WPISOW}
        paczka = str(dane.get("paczka_id") or "")[:100]
        autor = dostep.wlasciciel or dostep.nazwa or osoba
        tematy, blad, _uwaga = self.wiedza._tematy()
        if blad:
            self._licz("odmowy", "wpisy tematy_niedostepne")
            return 503, {"kod": "tematy_niedostepne", "opis": blad}
        znane = set(tematy)
        wyniki: list[dict | None] = [None] * len(wpisy)
        dobre: list[tuple[int, NowyWpis]] = []
        for i, w in enumerate(wpisy):
            klucz = w.get("klucz") if isinstance(w, dict) else None
            try:
                nowy = self._nowy_wpis(w, autor)
                sprawdz_wpis(nowy, i + 1, znane)
                dobre.append((i, nowy))
            except BladWpisu as e:
                wyniki[i] = {"klucz": klucz, "wynik": "blad", "opis": str(e)}
        odp: dict = {"paczka_id": paczka, "autor": autor}
        uwagi: list[str] = [ostrzezenie] if ostrzezenie else []
        if dobre:
            try:
                wynik = self.wiedza.baza.dodaj([n for _, n in dobre], dodal=osoba, znane_tematy=znane)
                for (i, _), stan in zip(dobre, wynik.stany, strict=True):
                    wyniki[i] = {"klucz": wpisy[i].get("klucz"), "wynik": stan}
                if wynik.zamaskowane:
                    uwagi.append(f"w {wynik.zamaskowane} wpisach był sekret - zapisano go jako [MASKED]")
                uwagi.extend(wynik.uwagi)
            except BladWpisu as e:  # nie powinno sie zdarzyc po sprawdz_wpis - ale glosno, per wpis
                log(f"BLAD zapisu paczki {paczka!r} od {osoba}: {e}")
                for i, _ in dobre:
                    wyniki[i] = {"klucz": wpisy[i].get("klucz"), "wynik": "blad", "opis": str(e)}
        odp["wyniki"] = wyniki
        if uwagi:
            odp["uwagi"] = uwagi
        self._licz("wpisy", "paczki")
        for w in wyniki:
            self._licz("wpisy", w["wynik"])
        ile = {k: sum(1 for w in wyniki if w["wynik"] == k) for k in ("dodano", "duplikat", "usuniety_wczesniej", "blad")}
        log(f"klient wpisy: {osoba} (autor {autor}) paczka {paczka!r}: " + ", ".join(f"{k} {v}" for k, v in ile.items()))
        return 200, odp
