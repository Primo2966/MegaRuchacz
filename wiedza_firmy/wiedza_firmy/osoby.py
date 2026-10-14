"""Osoby i ich uprawnienia w kroku 1: osoby.json na serwerze (w repo NIGDY - tylko skroty tokenow i tak).

W pliku lezy wylacznie sha256 tokenu. Sam token wypisuje sie RAZ, przy zalozeniu albo wymianie;
zgubiony = nowy token (`token`), starego nie da sie odczytac.

CLI:
    python -m wiedza_firmy.osoby nowa <osoba> [--admin]      zaklada osobe, wypisuje token raz
    python -m wiedza_firmy.osoby token <osoba>               nowy token (stary przestaje dzialac)
    python -m wiedza_firmy.osoby nadaj <osoba> <temat> <poziom>
    python -m wiedza_firmy.osoby odbierz <osoba> <temat>
    python -m wiedza_firmy.osoby usun <osoba>
    python -m wiedza_firmy.osoby ustaw-komputer <osoba> <id>   komputer z JFTools (krok 2; "-" zdejmuje)
    python -m wiedza_firmy.osoby lista

Krok 2 (WIEDZA_FIRMY_UPRAWNIENIA=jftools): tematy i poziomy osoby bierze serwer z JFTools dla jej
komputera; `nadaj`/`odbierz` dzialaja wtedy tylko na plik i nie maja wplywu. Admin zostaje w tym pliku.

Krok 3 (0.4.0): komputer sam bierze token (POST /klient/token, wydaj_token_komputera). Wpis nazywa sie
`komputer-<id>`: {token_sha256, admin: false, uprawnienia: {}, komputer, wystawiony, wystawil: "auto"};
komputer usuniety z JFTools (404) dostaje `wygasl: <czas>` (oznacz_wygasly).
"""

from __future__ import annotations

import argparse
import re
import secrets
import sys
import threading
import time
from pathlib import Path

from . import sciezki, tematy
from .pliki import czytaj_json, utf8_na_wyjsciu, zapisz_json
from .uprawnienia import POZIOMY, TAJNE, skrot_tokenu


class BladOsob(ValueError):
    pass


PREFIKS_KOMPUTERA = "komputer-"
WYSTAWIL_AUTO = "auto"
# Zapis osoby.json z serwera (tokeny komputerow, znacznik wygasl) idzie z wielu watkow naraz - jeden na raz.
_ZAMEK_ZAPISU = threading.Lock()


def osoba_komputera(komputer: str) -> str:
    return f"{PREFIKS_KOMPUTERA}{komputer}"


def _czas() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def _wczytaj(sciezka: Path) -> dict:
    if not sciezka.exists():
        return {}
    dane = czytaj_json(sciezka)
    if not isinstance(dane, dict):
        raise BladOsob(f"{sciezka}: oczekiwany obiekt osoba -> wpis; popraw plik recznie, nic nie zmienilem")
    return dane


def nowy_token() -> str:
    return secrets.token_urlsafe(32)


def nowa(osoba: str, admin: bool = False, sciezka: Path | None = None) -> str:
    sciezka = sciezka or sciezki.plik_osob()
    osoba = osoba.strip()
    if not osoba:
        raise BladOsob("pusta nazwa osoby")
    dane = _wczytaj(sciezka)
    if osoba in dane:
        raise BladOsob(f"osoba {osoba} juz istnieje - nowy token: python -m wiedza_firmy.osoby token {osoba}")
    token = nowy_token()
    dane[osoba] = {"token_sha256": skrot_tokenu(token), "admin": bool(admin), "uprawnienia": {}}
    zapisz_json(sciezka, dane)
    return token


def wymien_token(osoba: str, sciezka: Path | None = None) -> str:
    sciezka = sciezka or sciezki.plik_osob()
    dane = _wczytaj(sciezka)
    if osoba not in dane:
        raise BladOsob(f"nie ma osoby {osoba}")
    token = nowy_token()
    dane[osoba]["token_sha256"] = skrot_tokenu(token)
    zapisz_json(sciezka, dane)
    return token


def nadaj(osoba: str, temat: str, poziom: str, sciezka: Path | None = None) -> None:
    sciezka = sciezka or sciezki.plik_osob()
    if poziom == TAJNE:
        raise BladOsob("tajne nie istnieje w bazie - nie ma czego nadawac")
    if poziom not in POZIOMY:
        raise BladOsob(f"poziom {poziom!r} - dozwolone: {', '.join(POZIOMY)}")
    znane = tematy.slownik()
    if temat not in znane:
        raise BladOsob(f"nie ma tematu {temat!r} w {sciezki.plik_tematow()} (znane: {', '.join(znane) or 'brak'})")
    dane = _wczytaj(sciezka)
    if osoba not in dane:
        raise BladOsob(f"nie ma osoby {osoba} - najpierw: python -m wiedza_firmy.osoby nowa {osoba}")
    dane[osoba].setdefault("uprawnienia", {})[temat] = poziom
    zapisz_json(sciezka, dane)


def odbierz(osoba: str, temat: str, sciezka: Path | None = None) -> bool:
    sciezka = sciezka or sciezki.plik_osob()
    dane = _wczytaj(sciezka)
    if osoba not in dane:
        raise BladOsob(f"nie ma osoby {osoba}")
    bylo = dane[osoba].get("uprawnienia", {}).pop(temat, None) is not None
    zapisz_json(sciezka, dane)
    return bylo


def usun(osoba: str, sciezka: Path | None = None) -> None:
    sciezka = sciezka or sciezki.plik_osob()
    dane = _wczytaj(sciezka)
    if dane.pop(osoba, None) is None:
        raise BladOsob(f"nie ma osoby {osoba}")
    zapisz_json(sciezka, dane)


def ustaw_komputer(osoba: str, komputer: str | None, sciezka: Path | None = None) -> None:
    """Id komputera z JFTools dla osoby; None zdejmuje przypisanie."""
    sciezka = sciezka or sciezki.plik_osob()
    if komputer is not None:
        komputer = komputer.strip()
        if not re.match(r"^[1-9][0-9]{0,9}$", komputer):
            raise BladOsob(f"id komputera {komputer!r} - numer komputera z JFTools (np. 12)")
    dane = _wczytaj(sciezka)
    if osoba not in dane:
        raise BladOsob(f"nie ma osoby {osoba} - najpierw: python -m wiedza_firmy.osoby nowa {osoba}")
    if komputer is None:
        dane[osoba].pop("komputer", None)
    else:
        dane[osoba]["komputer"] = komputer
    zapisz_json(sciezka, dane)


def wydaj_token_komputera(komputer: str, wymien: bool = False, sciezka: Path | None = None) -> tuple[str | None, str]:
    """(token, wynik) dla komputera, ktory podpisal prosbe swoim kluczem (sprawdza klienci.py, nie ta funkcja).
    wynik: "wydano" | "wymieniono" | "juz_wydany" (jest token, a nie ma wymien) | "reczny" (wpis o tej nazwie
    zalozono recznie - automat go nie nadpisze). Token tylko przy wydano/wymieniono, raz."""
    sciezka = sciezka or sciezki.plik_osob()
    if not re.match(r"^[1-9][0-9]{0,9}$", str(komputer)):
        raise BladOsob(f"id komputera {komputer!r} - numer komputera z JFTools")
    osoba = osoba_komputera(komputer)
    with _ZAMEK_ZAPISU:
        dane = _wczytaj(sciezka)
        wpis = dane.get(osoba)
        if wpis is not None and (not isinstance(wpis, dict) or wpis.get("wystawil") != WYSTAWIL_AUTO):
            return None, "reczny"
        if wpis is not None and wpis.get("token_sha256") and not wymien:
            return None, "juz_wydany"
        token = nowy_token()
        if wpis is None:
            dane[osoba] = {"token_sha256": skrot_tokenu(token), "admin": False, "uprawnienia": {},
                           "komputer": str(komputer), "wystawiony": _czas(), "wystawil": WYSTAWIL_AUTO}
            wynik = "wydano"
        else:
            wpis["token_sha256"] = skrot_tokenu(token)
            wpis["wymieniony"] = _czas()
            wynik = "wymieniono"
        zapisz_json(sciezka, dane)
    return token, wynik


def oznacz_wygasly(komputer: str, wygasl: bool, sciezka: Path | None = None) -> bool:
    """Znacznik `wygasl` na wpisie `komputer-<id>` (komputer usuniety z JFTools albo wrocil). True = zmiana.
    Sam znacznik niczego nie odbiera - dostep i tak liczy sie od nowa z JFTools; to slad dla admina."""
    sciezka = sciezka or sciezki.plik_osob()
    osoba = osoba_komputera(komputer)
    with _ZAMEK_ZAPISU:
        dane = _wczytaj(sciezka)
        wpis = dane.get(osoba)
        if not isinstance(wpis, dict) or wpis.get("wystawil") != WYSTAWIL_AUTO:
            return False
        if wygasl == bool(wpis.get("wygasl")):
            return False
        if wygasl:
            wpis["wygasl"] = _czas()
        else:
            wpis.pop("wygasl", None)
        zapisz_json(sciezka, dane)
    return True


def main(argv: list[str] | None = None) -> int:
    utf8_na_wyjsciu()
    p = argparse.ArgumentParser(prog="python -m wiedza_firmy.osoby")
    sub = p.add_subparsers(dest="polecenie", required=True)
    n = sub.add_parser("nowa", help="zaloz osobe i wypisz jej token (jedyny raz)")
    n.add_argument("osoba")
    n.add_argument("--admin", action="store_true", help="moze dodawac i usuwac wpisy, widzi wszystko")
    t = sub.add_parser("token", help="nowy token dla osoby (stary przestaje dzialac)")
    t.add_argument("osoba")
    d = sub.add_parser("nadaj", help="uprawnienie do tematu do danego poziomu wlacznie")
    d.add_argument("osoba")
    d.add_argument("temat")
    d.add_argument("poziom", choices=POZIOMY)
    o = sub.add_parser("odbierz", help="zabierz uprawnienie do tematu")
    o.add_argument("osoba")
    o.add_argument("temat")
    u = sub.add_parser("usun", help="usun osobe (jej token przestaje dzialac)")
    u.add_argument("osoba")
    k = sub.add_parser("ustaw-komputer", help="komputer z JFTools, z ktorego osoba bierze uprawnienia (krok 2)")
    k.add_argument("osoba")
    k.add_argument("komputer", help='id komputera w JFTools; "-" zdejmuje przypisanie')
    sub.add_parser("lista", help="osoby i uprawnienia (bez tokenow)")
    a = p.parse_args(argv)

    try:
        if a.polecenie == "nowa":
            token = nowa(a.osoba, a.admin)
            print(f"osoba {a.osoba} zalozona{' (admin)' if a.admin else ''}. Token - zapisz go teraz, drugi raz sie nie pokaze:")
            print(token)
        elif a.polecenie == "token":
            print(f"nowy token dla {a.osoba} - stary juz nie dziala; zapisz go teraz:")
            print(wymien_token(a.osoba))
        elif a.polecenie == "nadaj":
            nadaj(a.osoba, a.temat, a.poziom)
            print(f"{a.osoba}: {a.temat} do poziomu {a.poziom} wlacznie")
        elif a.polecenie == "odbierz":
            bylo = odbierz(a.osoba, a.temat)
            print(f"{a.osoba}: {a.temat} odebrany" if bylo else f"{a.osoba} nie mial(a) uprawnienia do {a.temat}")
        elif a.polecenie == "usun":
            usun(a.osoba)
            print(f"osoba {a.osoba} usunieta")
        elif a.polecenie == "ustaw-komputer":
            komputer = None if a.komputer.strip() == "-" else a.komputer
            ustaw_komputer(a.osoba, komputer)
            print(f"{a.osoba}: komputer {komputer}" if komputer else f"{a.osoba}: bez komputera")
        else:
            dane = _wczytaj(sciezki.plik_osob())
            if not dane:
                print(f"brak osob ({sciezki.plik_osob()})")
            for osoba, wpis in dane.items():
                upr = ", ".join(f"{k}: {v}" for k, v in (wpis.get("uprawnienia") or {}).items()) or "brak uprawnien"
                komputer = f" [komputer {wpis['komputer']}]" if wpis.get("komputer") else ""
                auto = " [token automatyczny]" if wpis.get("wystawil") == WYSTAWIL_AUTO else ""
                wygasl = f" [WYGASL {wpis['wygasl']}: komputer usuniety z JFTools]" if wpis.get("wygasl") else ""
                print(f"{osoba}{' [admin]' if wpis.get('admin') is True else ''}{komputer}{auto}{wygasl} - {upr}")
    except (BladOsob, tematy.BladTematow, OSError, ValueError) as e:
        print(f"ODMOWA: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
