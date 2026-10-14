"""Osoby i ich uprawnienia w kroku 1: osoby.json na serwerze (w repo NIGDY - tylko skroty tokenow i tak).

W pliku lezy wylacznie sha256 tokenu. Sam token wypisuje sie RAZ, przy zalozeniu albo wymianie;
zgubiony = nowy token (`token`), starego nie da sie odczytac.

CLI:
    python -m wiedza_firmy.osoby nowa <osoba> [--admin]      zaklada osobe, wypisuje token raz
    python -m wiedza_firmy.osoby token <osoba>               nowy token (stary przestaje dzialac)
    python -m wiedza_firmy.osoby nadaj <osoba> <temat> <poziom>
    python -m wiedza_firmy.osoby odbierz <osoba> <temat>
    python -m wiedza_firmy.osoby usun <osoba>
    python -m wiedza_firmy.osoby lista
"""

from __future__ import annotations

import argparse
import secrets
import sys
from pathlib import Path

from . import sciezki, tematy
from .pliki import czytaj_json, utf8_na_wyjsciu, zapisz_json
from .uprawnienia import POZIOMY, TAJNE, skrot_tokenu


class BladOsob(ValueError):
    pass


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
        else:
            dane = _wczytaj(sciezki.plik_osob())
            if not dane:
                print(f"brak osob ({sciezki.plik_osob()})")
            for osoba, wpis in dane.items():
                upr = ", ".join(f"{k}: {v}" for k, v in (wpis.get("uprawnienia") or {}).items()) or "brak uprawnien"
                print(f"{osoba}{' [admin]' if wpis.get('admin') is True else ''} - {upr}")
    except (BladOsob, tematy.BladTematow, OSError, ValueError) as e:
        print(f"ODMOWA: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
