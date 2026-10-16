"""Uprawnienia i tematy z panelu JFTools (wtyczka mcp-ecommerce-sterowanie, zakladka "Wiedza firmy").

DOMYSLNIE WYLACZONE. Bez WIEDZA_FIRMY_UPRAWNIENIA=jftools serwer dziala dokladnie jak w kroku 1:
osoby.json + tematy.json, zadnego zapytania do JFTools. Nieznana wartosc zmiennej albo brak sekretu
przy "jftools" = serwer nie startuje (BladUstawien), zamiast po cichu wrocic do pliku.

Po wlaczeniu:
- token -> osoba nadal z osoby.json (tokeny nie wychodza z serwera), osoba -> komputer z pola `komputer`
  (`python -m wiedza_firmy.osoby ustaw-komputer <osoba> <id>`), komputer -> granty z JFTools:
  GET <baza>/knowledge-permissions?computer=<id>, naglowek x-webhook-secret.
- Flaga admin zostaje w osoby.json. Pole "admin" z odpowiedzi JFTools jest pomijane - zdalny panel
  nie robi nikogo adminem. Pole `uprawnienia` z osoby.json jest wtedy pomijane.
- Status komputera inny niz active (pending, blocked, 404) = zero uprawnien z komunikatem dlaczego.
- Tematy: GET <baza>/knowledge-topics, odswiezane w tle (0.4.3: zapytanie nie czeka, gdy jakas lista jest);
  gdy JFTools nie odpowiada - ostatnia znana lista, potem tematy.json.
- Krok 3 (0.4.0): wlasciciel komputera z pola `owner: {email, name}` odpowiedzi knowledge-permissions (autor
  wpisow z klienta: name, bez niego email, dopiero potem nazwa komputera), klucze publiczne komputerow z GET <baza>/keys (KluczeJFTools, podpis przy /klient/token),
  komputer usuniety z JFTools (404) = znacznik `wygasl` na jego wpisie `komputer-<id>` w osoby.json.

Pamiec jak w ecommerce-helper (src/ecommerce_helper/uprawnienia.py): odpowiedz wazna 10 min (komputer bez
dostepu - 1 min, zeby nadane uprawnienia zadzialaly szybko), zapytanie ma limit 3 s, po bledzie 30 s bez
ponawiania. Gdy JFTools nie odpowiada (siec, limit czasu, zly sekret, zla odpowiedz), obowiazuja ostatnio
znane uprawnienia, najwyzej sprzed godziny (PAMIEC_MAX_S), potem zero. Kazda awaria idzie do dziennika, a odpowiedz
narzedzia mowi "uprawnienia z pamieci z <czas>" albo dlaczego nie ma zadnych.
0.4.4: znany aktywny komputer z przeterminowanym wpisem nie czeka na JFTools - odswiezenie idzie w tle
(decyzja uzytkownika z 2026-10-16, granice w ZrodloJFTools._z_pamieci).
"""

from __future__ import annotations

import json
import os
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Mapping

from . import osoby as osoby_mod
from . import sciezki
from . import tematy as tematy_mod
from .pliki import log
from .uprawnienia import POZIOMY, Uprawnienia, ZrodloPlikowe

ENV_TRYB = "WIEDZA_FIRMY_UPRAWNIENIA"
ENV_URL = "WIEDZA_FIRMY_JFTOOLS_URL"
ENV_SEKRET = "WIEDZA_FIRMY_JFTOOLS_SEKRET"
TRYB_PLIK = "plik"
TRYB_JFTOOLS = "jftools"
# Ta sama baza publicznych tras wtyczki co w ecommerce-helper (ECOMMERCE_HELPER_UPRAWNIENIA_URL bez /permissions).
URL_DOMYSLNY = "https://tools.jfinvesting.pl/api/public/mcp-ecommerce-sterowanie"
SCIEZKA_UPRAWNIEN = "/knowledge-permissions"
SCIEZKA_TEMATOW = "/knowledge-topics"
SCIEZKA_KLUCZY = "/keys"
# Klucze komputerow: lista wazna 30 s (zablokowany komputer znika z niej w JFTools - najwyzej tyle moze jeszcze
# dostac token). Komputera nie ma na liscie = pytamy od nowa (swiezo zgloszony), ale nie czesciej niz co 5 s -
# /klient/token jest bez tokenu i nie moze byc pompka zapytan do JFTools.
WAZNOSC_KLUCZY_S = 30.0
ODSTEP_KLUCZY_S = 5.0

LIMIT_ZAPYTANIA_S = 3.0
WAZNOSC_S = 600.0
WAZNOSC_BEZ_DOSTEPU_S = 60.0
PRZERWA_PO_BLEDZIE_S = 30.0
# Ostatnio znane uprawnienia przy lezacym JFTools - najwyzej tyle od ostatniej udanej odpowiedzi, potem zero.
# Inaczej niz w ecommerce-helper (tam 10 min = tyle co waznosc, wiec po wygasnieciu pamieci aktywny komputer
# traci dostep od razu): godzina przykrywa krotka awarie albo przenosiny panelu, a odebrane w panelu
# uprawnienie i tak nie przezyje awarii dluzej niz godzine.
PAMIEC_MAX_S = 3600.0
# Lista tematow bez udanego odswiezenia dluzej niz godzine = UWAGA w dzienniku przy kazdej nieudanej probie.
# Tematy nie daja dostepu (stara lista nikomu nic nie otwiera), ale nowy albo przemianowany w panelu temat
# nie dociera do serwera; godzina = ta sama granica co PAMIEC_MAX_S: krotka awarie przemilczamy (sam BLAD),
# dluzsza znaczy, ze JFTools lezy na serio albo zmienil sie sekret - admin ma to zobaczyc.
STARA_LISTA_TEMATOW_S = 3600.0

STATUSY = ("pending", "active", "blocked")
# Odpowiedzi rozstrzygajace, nie awarie: zero dostepu bez siegania po pamiec (pamiec zostaje nimi zastapiona).
NIEZNANY = "nieznany"      # 404: komputera nie ma w JFTools (usuniety albo nigdy nie zarejestrowany)
ZLE_ID = "zle_id"          # 400: wtyczka odrzucila parametr computer (id komputera to liczba)
# id komputera tak, jak przyjmuje je wtyczka (src/public.ts: /^[1-9][0-9]{0,9}$/)
ID_KOMPUTERA = re.compile(r"^[1-9][0-9]{0,9}$")

GDZIE_NADAC = "JFTools → Wiedza firmy"
KOMUNIKAT_BEZ_KOMPUTERA = ("Twoja osoba nie ma przypisanego komputera z JFTools — poproś admina "
                           "(python -m wiedza_firmy.osoby ustaw-komputer).")
KOMUNIKAT_PENDING = f"Ten komputer czeka na uprawnienia. Admin nada je w {GDZIE_NADAC}."
KOMUNIKAT_BLOCKED = f"Ten komputer ma zablokowany dostęp. Admin może go odblokować w {GDZIE_NADAC}."
KOMUNIKAT_NIEZNANY = f"Ten komputer nie jest zarejestrowany w JFTools. Admin doda go w {GDZIE_NADAC}."
KOMUNIKAT_ZLE_ID = ("JFTools odrzuca id komputera przypisane Twojej osobie — poproś admina o poprawienie "
                    "(python -m wiedza_firmy.osoby ustaw-komputer).")
KOMUNIKATY_STATUSU = {"pending": KOMUNIKAT_PENDING, "blocked": KOMUNIKAT_BLOCKED, NIEZNANY: KOMUNIKAT_NIEZNANY,
                      ZLE_ID: KOMUNIKAT_ZLE_ID}


class BladJFTools(Exception):
    """JFTools nie dal odpowiedzi, ktorej mozna uzyc (bez sekretow w tresci)."""


class BladUstawien(ValueError):
    """Zle ustawienia zrodla uprawnien - serwer nie startuje, komunikat mowi, co poprawic."""


def baza_url(url: str) -> str:
    """Baza publicznych tras wtyczki; przyjmuje tez adres z koncowka /permissions (jak w ecommerce-helper)."""
    baza = (url or "").strip().rstrip("/")
    for koncowka in ("/permissions", SCIEZKA_UPRAWNIEN, SCIEZKA_TEMATOW):
        if baza.endswith(koncowka):
            baza = baza[: -len(koncowka)]
    return baza


def pobierz_json(url: str, sekret: str, limit_s: float, parametry: Mapping[str, str] | None = None) -> Any:
    """GET z naglowkiem x-webhook-secret. 404 -> NIEZNANY, 400 -> ZLE_ID, inny kod niz 200 / siec / nie-JSON ->
    BladJFTools (401/403 = zly sekret, 5xx = blad panelu: awaria, nie odpowiedz)."""
    if parametry:
        url = f"{url}?{urllib.parse.urlencode(parametry)}"
    zadanie = urllib.request.Request(url, headers={"x-webhook-secret": sekret, "Accept": "application/json",
                                                       # Cloudflare przed JFTools odrzuca domyslny Python-urllib (Error 1010)
                                                       "User-Agent": "wiedza-firmy"})
    try:
        with urllib.request.urlopen(zadanie, timeout=limit_s) as odp:
            kod, cialo = odp.status, odp.read()
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return NIEZNANY
        if e.code == 400:
            return ZLE_ID
        raise BladJFTools(f"HTTP {e.code}") from None
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        powod = getattr(e, "reason", None) or e
        raise BladJFTools(f"brak polaczenia: {str(powod)[:200]}") from None
    if kod != 200:
        raise BladJFTools(f"HTTP {kod}")
    try:
        return json.loads(cialo.decode("utf-8-sig"))
    except ValueError:
        raise BladJFTools("odpowiedz nie jest JSON-em") from None


# --------------------------------------------------------------------------- uprawnienia komputera


@dataclass
class Dostep:
    status: str  # active | pending | blocked | nieznany (404) | zle_id (400)
    nazwa: str = ""
    granty: dict[str, str] = field(default_factory=dict)  # temat_id -> najwyzszy poziom
    wlasciciel: str = ""  # owner.name z JFTools (0.4.0); pusty = panel nie przypisal osoby albo stara wtyczka
    wlasciciel_email: str = ""  # owner.email - autor wpisow, gdy panel ma przy komputerze sam e-mail bez nazwiska

    @property
    def autor(self) -> str:
        """Podpis wpisow z tego komputera: imie i nazwisko wlasciciela, bez nich jego e-mail, potem nazwa komputera."""
        return self.wlasciciel or self.wlasciciel_email or self.nazwa

    @classmethod
    def z_odpowiedzi(cls, dane: Any, komputer: str) -> tuple["Dostep", list[str]]:
        """Sprawdzona odpowiedz + lista pominietych grantow. Cokolwiek niejasnego w statusie = BladJFTools."""
        if dane in (NIEZNANY, ZLE_ID):
            return cls(status=dane), []
        if not isinstance(dane, dict) or not isinstance(dane.get("computer"), dict):
            raise BladJFTools("odpowiedz bez obiektu computer")
        kmp = dane["computer"]
        status = str(kmp.get("status") or "").strip().lower()
        if status not in STATUSY:
            raise BladJFTools(f"nieznany status komputera: {status[:30]!r}")
        if "id" in kmp and str(kmp["id"]).strip() != str(komputer):
            raise BladJFTools(f"odpowiedz dotyczy innego komputera ({str(kmp['id'])[:30]!r}, pytano o {komputer!r})")
        surowe = dane.get("grants")
        if surowe is None:
            surowe = {}
        if not isinstance(surowe, dict):
            raise BladJFTools("grants nie jest obiektem temat -> poziom")
        granty: dict[str, str] = {}
        pominiete: list[str] = []
        for temat, poziom in surowe.items():
            if poziom in POZIOMY:
                granty[str(temat)] = poziom
            else:
                pominiete.append(f"{temat}={str(poziom)[:30]!r}")
        # owner: {"email": str|null, "name": str|null} albo null (wtyczka 84b58e6); name null = admin nie wpisal osoby
        wlasciciel = wlasciciel_email = ""
        owner = dane.get("owner")
        if isinstance(owner, dict):
            if isinstance(owner.get("name"), str):
                wlasciciel = owner["name"].strip()
            elif owner.get("name") is not None:
                pominiete.append(f"owner.name={str(owner.get('name'))[:60]!r} (oczekiwany tekst albo null)")
            if isinstance(owner.get("email"), str):
                wlasciciel_email = owner["email"].strip()
            elif owner.get("email") is not None:
                pominiete.append(f"owner.email={str(owner.get('email'))[:60]!r} (oczekiwany tekst albo null)")
        elif owner is not None:
            pominiete.append(f"owner={str(owner)[:60]!r} (oczekiwany obiekt {{email, name}} albo null)")
        return cls(status=status, nazwa=str(kmp.get("name") or "").strip(), granty=granty,
                   wlasciciel=wlasciciel, wlasciciel_email=wlasciciel_email), pominiete


@dataclass
class _Pamiec:
    znany: Dostep | None = None
    czas: float | None = None  # ostatnia UDANA odpowiedz JFTools o tym komputerze
    blad_czas: float | None = None
    blad: str | None = None
    zamek: threading.Lock = field(default_factory=threading.Lock)  # stan wpisu; nigdy w trakcie zapytania do JFTools
    zamek_pytania: threading.Lock = field(default_factory=threading.Lock)  # jedno zapytanie na komputer naraz
    watek: threading.Thread | None = None  # odswiezanie w tle; zywy = drugiego nie startujemy


def _godzina(czas: float) -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(czas))


class ZrodloJFTools(ZrodloPlikowe):
    """Token, admin i komputer osoby z osoby.json; tematy i poziomy komputera z JFTools."""

    def __init__(self, sciezka: Path, url: str = URL_DOMYSLNY, sekret: str = "", *,
                 pobierz: Callable[[str], Any] | None = None, limit_s: float = LIMIT_ZAPYTANIA_S,
                 waznosc_s: float = WAZNOSC_S, waznosc_bez_dostepu_s: float = WAZNOSC_BEZ_DOSTEPU_S,
                 przerwa_po_bledzie_s: float = PRZERWA_PO_BLEDZIE_S, pamiec_max_s: float = PAMIEC_MAX_S,
                 zegar: Callable[[], float] = time.time) -> None:
        super().__init__(sciezka)
        self.url = baza_url(url) + SCIEZKA_UPRAWNIEN
        self.klucze = KluczeJFTools(url, sekret, limit_s=limit_s, zegar=zegar)
        self.waznosc_s = waznosc_s
        self.waznosc_bez_dostepu_s = waznosc_bez_dostepu_s
        self.przerwa_po_bledzie_s = przerwa_po_bledzie_s
        self.pamiec_max_s = pamiec_max_s
        self.zegar = zegar
        self._pobierz = pobierz or (lambda komputer: pobierz_json(self.url, sekret, limit_s, {"computer": komputer}))
        self._pamieci: dict[str, _Pamiec] = {}
        self._zamek_pamieci = threading.Lock()
        self.ostatni_blad: str | None = None  # do znacznika zycia: "<czas> komputer X: <przyczyna>"

    def _pamiec(self, komputer: str) -> _Pamiec:
        with self._zamek_pamieci:
            return self._pamieci.setdefault(komputer, _Pamiec())

    def _ostatnio_znany(self, p: _Pamiec) -> tuple[Dostep | None, str]:
        powod = p.blad or "brak odpowiedzi"
        if p.znany is not None and p.czas is not None and self.zegar() - p.czas <= self.pamiec_max_s:
            return p.znany, f"uprawnienia z pamięci z {_godzina(p.czas)} — JFTools nie odpowiada ({powod})"
        return None, (f"Nie da się teraz sprawdzić uprawnień w JFTools ({powod}), a serwer nie ma ich w pamięci "
                      f"z ostatnich {int(self.pamiec_max_s // 60)} min — spróbuj za kilka minut; jeśli to trwa, "
                      "daj znać adminowi.")

    def _z_pamieci(self, p: _Pamiec, komputer: str, w_tle: bool) -> tuple[Dostep | None, str | None] | None:
        """Odpowiedz bez czekania na JFTools albo None = trzeba zapytac i poczekac. Wolane pod p.zamek.

        0.4.4 - decyzja uzytkownika z 2026-10-16: znany AKTYWNY komputer z przeterminowanym wpisem (starszym
        niz waznosc_s) dostaje ostatnio znane uprawnienia od razu, a pytanie do JFTools idzie w tle (jedno naraz,
        po bledzie nie czesciej niz co przerwa_po_bledzie_s). Wczesniej co ~10 min jedno szukaj_wiedzy czekalo
        na JFTools do 3 s. Swiadomie zaakceptowany koszt: uprawnienie odebrane w panelu JFTools moze jeszcze
        zadzialac do konca jednego odswiezenia (~10 min plus czas zapytania w tle) - zapytanie, ktore odpali
        odswiezenie, dostaje stare granty; nastepne po odswiezeniu juz to, co powiedzial JFTools (blocked,
        404 = odmowa). Okres waznosci (waznosc_s) sie NIE wydluza: przeterminowany wpis tylko przeczekuje
        odswiezenie w tle.
        Granice (bezpieczenstwo):
        - komputer nieznany serwerowi (zadnej udanej odpowiedzi) - czeka na JFTools jak dotad, nigdy na kredyt;
        - komputer bez dostepu (pending, blocked, 404, 400) - czeka jak dotad: stary wpis i tak jest odmowa,
          a czekanie sprawia, ze uprawnienie nadane w panelu dziala od pierwszego zapytania po minucie;
        - wpis starszy niz pamiec_max_s (godzina bez udanej odpowiedzi o tym komputerze) - nie wraca od razu:
          zapytanie czeka na JFTools, a gdy ten nie odpowiada - odmowa + UWAGA w dzienniku. To ta sama granica,
          co przy awarii przed 0.4.4 (PAMIEC_MAX_S), wiec odebrane uprawnienie nie przezyje awarii ani
          bezczynnosci komputera dluzej niz godzine; odmowa jest bezpieczniejsza niz granty sprzed godziny."""
        teraz = self.zegar()
        if p.znany is not None and p.czas is not None and p.blad_czas is None:
            limit = self.waznosc_s if p.znany.status == "active" else self.waznosc_bez_dostepu_s
            if teraz - p.czas < limit:
                return p.znany, None
        if w_tle and p.znany is not None and p.znany.status == "active" and p.czas is not None \
                and teraz - p.czas <= self.pamiec_max_s:
            po_przerwie = p.blad_czas is None or teraz - p.blad_czas >= self.przerwa_po_bledzie_s
            if po_przerwie and not (p.watek is not None and p.watek.is_alive()):
                p.watek = threading.Thread(target=self._odswiez_w_tle, args=(komputer, p),
                                           name=f"uprawnienia-jftools-{komputer}", daemon=True)
                p.watek.start()
            if p.blad_czas is None:
                return p.znany, None
            return self._ostatnio_znany(p)
        if p.blad_czas is not None and teraz - p.blad_czas < self.przerwa_po_bledzie_s:
            return self._ostatnio_znany(p)
        return None

    def _zapytaj(self, komputer: str, p: _Pamiec) -> tuple[Dostep | None, str | None]:
        """Jedno zapytanie do JFTools i zapis wyniku. Wolane pod p.zamek_pytania, BEZ p.zamek (trwa do limit_s)."""
        try:
            nowy, pominiete = Dostep.z_odpowiedzi(self._pobierz(komputer), komputer)
        except Exception as e:  # siec, limit czasu, 401/403, zla odpowiedz - nigdy "wszystko"
            with p.zamek:
                p.blad_czas = self.zegar()
                p.blad = str(e)[:200] if isinstance(e, BladJFTools) else f"{type(e).__name__}: {str(e)[:200]}"
                self.ostatni_blad = f"{_godzina(p.blad_czas)} komputer {komputer}: {p.blad}"
                dostep, ostrzezenie = self._ostatnio_znany(p)
                blad, czas = p.blad, p.czas
            log(f"BLAD JFTools (uprawnienia komputera {komputer}): {blad} - "
                f"{'ostatnio znane z ' + _godzina(czas) if dostep else 'zero uprawnien'}")
            if dostep is None and czas is not None:  # komputer znany, ale ostatnia udana odpowiedz za stara
                log(f"UWAGA JFTools (uprawnienia komputera {komputer}): brak udanego odswiezenia od "
                    f"{int((self.zegar() - czas) // 60)} min (prog {int(self.pamiec_max_s // 60)} min) - "
                    "odmowa, dopoki JFTools nie odpowie")
            return dostep, ostrzezenie
        if pominiete:
            log(f"UWAGA JFTools komputer {komputer}: pominiete z odpowiedzi (granty z nieznanym poziomem, zly owner): {', '.join(pominiete)}")
        with p.zamek:
            poprzedni = p.znany.status if p.znany else None
            if nowy.status != poprzedni or p.blad_czas is not None:
                log(f"JFTools komputer {komputer}: status {nowy.status}, tematow {len(nowy.granty)}")
            p.znany, p.czas, p.blad_czas, p.blad = nowy, self.zegar(), None, None
        if nowy.status != poprzedni:
            self._oznacz_wygasly(komputer, nowy.status == NIEZNANY)
        return nowy, None

    def _odswiez_w_tle(self, komputer: str, p: _Pamiec) -> None:
        try:
            with p.zamek_pytania:
                self._zapytaj(komputer, p)
        except Exception as e:  # _zapytaj sam lapie awarie JFTools; tu tylko bledy w samym kodzie
            log(f"BLAD odswiezania uprawnien komputera {komputer} w tle: {type(e).__name__}: {str(e)[:200]}")

    def dostep(self, komputer: str) -> tuple[Dostep | None, str | None]:
        """(dostep, ostrzezenie). dostep None = nie wiadomo (JFTools milczy, nic znanego z PAMIEC_MAX_S)
        - wtedy ostrzezenie mowi dlaczego. Ostrzezenie przy dostepie = dostep z pamieci."""
        p = self._pamiec(komputer)
        with p.zamek:
            wynik = self._z_pamieci(p, komputer, w_tle=True)
        if wynik is not None:
            return wynik
        with p.zamek_pytania:  # jedno zapytanie na komputer naraz; inne watki czekaja na jego wynik
            with p.zamek:  # ktos mogl zapytac, gdy czekalismy - jego wynik (albo przerwa po bledzie) wystarczy
                wynik = self._z_pamieci(p, komputer, w_tle=False)
            if wynik is not None:
                return wynik
            return self._zapytaj(komputer, p)

    def _oznacz_wygasly(self, komputer: str, wygasl: bool) -> None:
        """Komputer usuniety z JFTools (404) -> `wygasl` na jego wpisie automatycznym; wrocil -> znacznik znika."""
        try:
            if osoby_mod.oznacz_wygasly(komputer, wygasl, self.sciezka):
                log(f"osoby: {osoby_mod.osoba_komputera(komputer)} "
                    f"{'oznaczony jako wygasl (komputer usuniety z JFTools)' if wygasl else 'juz nie wygasl'}")
        except Exception as e:  # nie przerywa odpowiedzi - dostep i tak liczy sie z JFTools, ale glosno
            log(f"BLAD zapisu znacznika wygasl dla komputera {komputer} w {self.sciezka}: {e!r}")

    def wpis_osoby(self, osoba: str) -> dict | None:
        """Sprawdzony wpis osoby z osoby.json (token_sha256, admin, uprawnienia, komputer) albo None."""
        return self._odswiez().get(osoba)

    def uprawnienia(self, osoba: str) -> Uprawnienia:
        wpis = self._odswiez().get(osoba)
        if wpis is None:
            return Uprawnienia(osoba=osoba)
        if wpis["admin"]:
            return Uprawnienia(osoba=osoba, admin=True, zrodlo="admin w osoby.json na serwerze")
        komputer = wpis.get("komputer")
        if not komputer:
            return Uprawnienia(osoba=osoba, komunikat=KOMUNIKAT_BEZ_KOMPUTERA, zrodlo="JFTools (brak komputera)")
        dostep, ostrzezenie = self.dostep(komputer)
        if dostep is None:
            return Uprawnienia(osoba=osoba, komunikat=ostrzezenie, ostrzezenie=ostrzezenie,
                               zrodlo=f"JFTools, komputer #{komputer}")
        kto = f"„{dostep.nazwa}” (#{komputer})" if dostep.nazwa else f"#{komputer}"
        zrodlo = f"JFTools ({GDZIE_NADAC}), komputer {kto}"
        if dostep.status != "active":
            return Uprawnienia(osoba=osoba, komunikat=KOMUNIKATY_STATUSU.get(dostep.status, KOMUNIKAT_NIEZNANY),
                               zrodlo=zrodlo, ostrzezenie=ostrzezenie, status=dostep.status)
        return Uprawnienia(osoba=osoba, tematy=dict(dostep.granty), zrodlo=zrodlo, ostrzezenie=ostrzezenie,
                           status=dostep.status)

    def stan(self) -> dict:
        """Do znacznika zycia serwera."""
        return {"tryb": TRYB_JFTOOLS, "url": self.url, "ostatni_blad": self.ostatni_blad,
                "ostatni_blad_kluczy": self.klucze.ostatni_blad}


# --------------------------------------------------------------------------- klucze komputerow (krok 3)


class KluczeJFTools:
    """GET <baza>/keys: {computers: [{id, name, status, publicKey: "ssh-ed25519 <b64>"}]} - tylko pending i active
    (zablokowanych i usunietych wtyczka nie podaje). Sluzy wylacznie do sprawdzenia podpisu przy /klient/token."""

    def __init__(self, url: str = URL_DOMYSLNY, sekret: str = "", *, pobierz: Callable[[], Any] | None = None,
                 limit_s: float = LIMIT_ZAPYTANIA_S, waznosc_s: float = WAZNOSC_KLUCZY_S,
                 odstep_s: float = ODSTEP_KLUCZY_S, zegar: Callable[[], float] = time.time) -> None:
        self.url = baza_url(url) + SCIEZKA_KLUCZY
        self.waznosc_s = waznosc_s
        self.odstep_s = odstep_s
        self.zegar = zegar
        self._pobierz = pobierz or (lambda: pobierz_json(self.url, sekret, limit_s))
        self._znane: dict[str, dict] = {}
        self._czas: float | None = None
        self._zamek = threading.Lock()
        self.ostatni_blad: str | None = None

    @staticmethod
    def _z_odpowiedzi(dane: Any) -> dict[str, dict]:
        if not isinstance(dane, dict) or not isinstance(dane.get("computers"), list):
            raise BladJFTools("keys: odpowiedz bez listy computers")
        wynik: dict[str, dict] = {}
        for k in dane["computers"]:
            if not isinstance(k, dict):
                continue
            kid = k.get("id")
            kid = str(kid).strip() if isinstance(kid, (str, int)) and not isinstance(kid, bool) else ""
            if ID_KOMPUTERA.match(kid) and isinstance(k.get("publicKey"), str):
                wynik[kid] = {"publicKey": k["publicKey"], "name": str(k.get("name") or "").strip(),
                              "status": str(k.get("status") or "").strip().lower()}
        return wynik

    def klucz(self, komputer: str) -> dict | None:
        """{publicKey, name, status} komputera albo None (nie ma go w keys: zablokowany, usuniety, nieznany).
        JFTools nie odpowiada = BladJFTools (bez klucza nie ma czym sprawdzic podpisu - nic z pamieci)."""
        with self._zamek:
            teraz = self.zegar()
            if self._czas is not None and teraz - self._czas < self.waznosc_s and komputer in self._znane:
                return self._znane[komputer]
            if self._czas is not None and teraz - self._czas < self.odstep_s:
                return self._znane.get(komputer)
            try:
                dane = self._pobierz()
                if dane in (NIEZNANY, ZLE_ID):
                    raise BladJFTools(f"HTTP {404 if dane == NIEZNANY else 400} na keys")
                self._znane = self._z_odpowiedzi(dane)
            except Exception as e:
                opis = str(e)[:200] if isinstance(e, BladJFTools) else f"{type(e).__name__}: {str(e)[:200]}"
                self.ostatni_blad = f"{_godzina(self.zegar())}: {opis}"
                log(f"BLAD JFTools (keys): {opis}")
                raise BladJFTools(opis) from None
            self._czas = self.zegar()
            return self._znane.get(komputer)


# --------------------------------------------------------------------------- tematy


def _tematy_z_odpowiedzi(dane: Any) -> tuple[list[tematy_mod.Temat], list[str]]:
    """Tablica tematow z JFTools (id, nazwa, opis, przyklady, osobne_uprawnienie, kolejnosc - kolejnosc juz
    ustawiona przez wtyczke). Zly wpis wypada (z opisem), nie cala lista."""
    if not isinstance(dane, list):
        raise BladJFTools("knowledge-topics: oczekiwana lista tematow")
    lista: list[tematy_mod.Temat] = []
    pominiete: list[str] = []
    widziane: set[str] = set()
    for nr, t in enumerate(dane, 1):
        tid = t.get("id") if isinstance(t, dict) else None
        tid = str(tid).strip() if isinstance(tid, (str, int)) and not isinstance(tid, bool) else ""
        nazwa = t.get("nazwa") if isinstance(t, dict) else None
        if not tematy_mod._ID.match(tid) or tid in widziane or not isinstance(nazwa, str) or not nazwa.strip():
            pominiete.append(f"temat nr {nr} ({tid[:30]!r})")
            continue
        widziane.add(tid)
        opis = t.get("opis") if isinstance(t.get("opis"), str) else ""
        przyklady = t.get("przyklady") if isinstance(t.get("przyklady"), list) else []
        lista.append(tematy_mod.Temat(tid, nazwa.strip(), opis.strip(),
                                      tuple(str(p).strip() for p in przyklady if isinstance(p, str) and p.strip()),
                                      t.get("osobne_uprawnienie") is True))
    return lista, pominiete


class TematyJFTools:
    """Tematy z JFTools z pamiecia; przy awarii ostatnia znana lista (bez limitu wieku - tematy nie daja
    dostepu do niczego), a bez niej tematy.json serwera. Kazde zastepstwo idzie do `uwaga` odpowiedzi.

    0.4.3: zapytanie nie czeka na JFTools, gdy jest juz jakas lista. Przeterminowana lista wraca od razu,
    a odswiezenie idzie w tle (jedno naraz, po bledzie nie czesciej niz co przerwa_po_bledzie_s). Czeka
    tylko pierwsze zapytanie po starcie, zanim serwer zna jakakolwiek liste z JFTools - jak dotad."""

    def __init__(self, url: str = URL_DOMYSLNY, sekret: str = "", plik_tematow: Path | None = None, *,
                 pobierz: Callable[[], Any] | None = None, limit_s: float = LIMIT_ZAPYTANIA_S,
                 waznosc_s: float = WAZNOSC_S, przerwa_po_bledzie_s: float = PRZERWA_PO_BLEDZIE_S,
                 stara_lista_s: float = STARA_LISTA_TEMATOW_S, zegar: Callable[[], float] = time.time) -> None:
        self.url = baza_url(url) + SCIEZKA_TEMATOW
        self.plik_tematow = plik_tematow
        self.waznosc_s = waznosc_s
        self.przerwa_po_bledzie_s = przerwa_po_bledzie_s
        self.stara_lista_s = stara_lista_s
        self.zegar = zegar
        self._pobierz = pobierz or (lambda: pobierz_json(self.url, sekret, limit_s))
        self._znane: dict[str, tematy_mod.Temat] | None = None
        self._czas: float | None = None
        self._blad: str | None = None
        self._blad_czas: float | None = None
        self._zamek = threading.Lock()
        self._watek: threading.Thread | None = None  # odswiezanie w tle; zywy = drugiego nie startujemy

    def _zastepstwo(self) -> tuple[dict[str, tematy_mod.Temat], str | None, str | None]:
        if self._znane is not None and self._czas is not None:
            return self._znane, None, f"lista tematów z pamięci z {_godzina(self._czas)} — JFTools nie odpowiada ({self._blad})"
        try:
            z_pliku = tematy_mod.slownik(self.plik_tematow or sciezki.plik_tematow())
        except tematy_mod.BladTematow as e:
            return {}, (f"JFTools nie odpowiada ({self._blad}), a lista tematów na serwerze jest uszkodzona ({e}) "
                        "- zgłoś adminowi"), None
        return z_pliku, None, f"lista tematów z pliku serwera — JFTools nie odpowiada ({self._blad})"

    def _pobierz_liste(self) -> dict[str, tematy_mod.Temat] | None:
        """Jedno zapytanie do JFTools BEZ zamka (moze trwac do limit_s). None = awaria, juz zapisana i w dzienniku."""
        try:
            dane = self._pobierz()
            if dane in (NIEZNANY, ZLE_ID):
                raise BladJFTools(f"HTTP {404 if dane == NIEZNANY else 400} na knowledge-topics")
            lista, pominiete = _tematy_z_odpowiedzi(dane)
        except Exception as e:
            opis = str(e)[:200] if isinstance(e, BladJFTools) else f"{type(e).__name__}: {str(e)[:200]}"
            with self._zamek:
                self._blad_czas, self._blad = self.zegar(), opis
                znane, czas = self._znane, self._czas
            if znane is not None and czas is not None:
                wiek = self.zegar() - czas
                log(f"BLAD JFTools (tematy): {opis} - zostaje ostatnia znana lista z {_godzina(czas)}")
                if wiek > self.stara_lista_s:
                    log(f"UWAGA JFTools (tematy): lista tematow ma {int(wiek // 60)} min (prog "
                        f"{int(self.stara_lista_s // 60)} min) - zmiany tematow w panelu nie docieraja do serwera")
            else:
                log(f"BLAD JFTools (tematy): {opis} - lista z tematy.json")
            return None
        if pominiete:
            log(f"UWAGA JFTools: tematy z blednym id albo bez nazwy pominiete: {', '.join(pominiete)}")
        nowe = {t.id: t for t in lista}
        with self._zamek:
            if self._blad_czas is not None and self._znane is not None:
                log(f"JFTools (tematy) znowu odpowiada - tematow {len(nowe)}")
            self._znane, self._czas, self._blad, self._blad_czas = nowe, self.zegar(), None, None
        return nowe

    def _odswiez_w_tle(self) -> None:
        try:
            self._pobierz_liste()
        except Exception as e:  # _pobierz_liste sam lapie awarie JFTools; tu tylko bledy w samym kodzie
            log(f"BLAD odswiezania tematow w tle: {type(e).__name__}: {str(e)[:200]}")

    def slownik(self) -> tuple[dict[str, tematy_mod.Temat], str | None, str | None]:
        """(tematy, blad, uwaga). blad = nie da sie uzyc zadnej listy; uwaga = lista zastepcza."""
        with self._zamek:
            teraz = self.zegar()
            if self._znane is not None and self._czas is not None:
                swieza = self._blad_czas is None and teraz - self._czas < self.waznosc_s
                po_przerwie = self._blad_czas is None or teraz - self._blad_czas >= self.przerwa_po_bledzie_s
                if not swieza and po_przerwie and not (self._watek is not None and self._watek.is_alive()):
                    self._watek = threading.Thread(target=self._odswiez_w_tle, name="tematy-jftools", daemon=True)
                    self._watek.start()
                if self._blad_czas is None:
                    return self._znane, None, None
                return self._zastepstwo()
            if self._blad_czas is not None and teraz - self._blad_czas < self.przerwa_po_bledzie_s:
                return self._zastepstwo()
        # Zadnej listy z JFTools jeszcze nie ma: czekamy na odpowiedz (jak przed 0.4.3) zamiast zgadywac.
        # Rownolegle pierwsze zapytania moga zapytac JFTools kazde osobno - zdarza sie tylko tuz po starcie.
        nowe = self._pobierz_liste()
        if nowe is not None:
            return nowe, None, None
        with self._zamek:
            return self._zastepstwo()


# --------------------------------------------------------------------------- ustawienia procesu


def zbuduj_zrodla(environ: Mapping[str, str] | None = None) -> tuple[ZrodloPlikowe, TematyJFTools | None]:
    """Zrodlo uprawnien i tematow wg zmiennych. Bez WIEDZA_FIRMY_UPRAWNIENIA (albo =plik) - jak w kroku 1."""
    environ = os.environ if environ is None else environ
    tryb = str(environ.get(ENV_TRYB) or "").strip().lower()
    if tryb in ("", TRYB_PLIK):
        return ZrodloPlikowe(sciezki.plik_osob()), None
    if tryb != TRYB_JFTOOLS:
        raise BladUstawien(f"{ENV_TRYB}={tryb!r} - dozwolone: {TRYB_PLIK} (domyslnie) albo {TRYB_JFTOOLS}")
    url = str(environ.get(ENV_URL) or URL_DOMYSLNY).strip()
    sekret = str(environ.get(ENV_SEKRET) or "").strip()
    if not sekret:
        raise BladUstawien(f"{ENV_TRYB}={TRYB_JFTOOLS} bez {ENV_SEKRET} - JFTools odrzuci kazde zapytanie; "
                           "ustaw sekret wtyczki (ten sam co ECOMMERCE_HELPER_UPRAWNIENIA_SEKRET)")
    if not url.lower().startswith(("https://", "http://")):
        raise BladUstawien(f"{ENV_URL}={url!r} - oczekiwany adres http(s)")
    return ZrodloJFTools(sciezki.plik_osob(), url, sekret), TematyJFTools(url, sekret)
