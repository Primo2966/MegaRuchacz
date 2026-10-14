"""Lista tematow: tematy.json na serwerze (w repo tylko przyklad - przyklady/tematy.przyklad.json).

Temat: {id, nazwa, opis, przyklady: [..], osobne_uprawnienie: bool}. `osobne_uprawnienie` oznacza
tematy nadawane tylko wprost i swiadomie (np. SEO, dostawcy, IT) - informacja dla admina i pytajacego.

CLI:
    python -m wiedza_firmy.tematy wczytaj <plik.json>   sprawdza i zapisuje jako tematy.json serwera
    python -m wiedza_firmy.tematy lista
"""

from __future__ import annotations

import argparse
import re
import sqlite3
import sys
from dataclasses import dataclass
from pathlib import Path

from . import sciezki
from .pliki import czytaj_json, utf8_na_wyjsciu, zapisz_json

_ID = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")


class BladTematow(ValueError):
    """Plik tematow nie nadaje sie do uzycia - komunikat mowi, co poprawic."""


@dataclass(frozen=True)
class Temat:
    id: str
    nazwa: str
    opis: str
    przyklady: tuple[str, ...]
    osobne_uprawnienie: bool

    def jako_slownik(self) -> dict:
        return {"id": self.id, "nazwa": self.nazwa, "opis": self.opis, "przyklady": list(self.przyklady),
                "osobne_uprawnienie": self.osobne_uprawnienie}


def sprawdz(surowe: object) -> list[Temat]:
    """Pelna kontrola listy tematow. Pierwszy blad = odmowa calosci (zadnego zapisu polowy)."""
    if not isinstance(surowe, list) or not surowe:
        raise BladTematow("oczekiwana niepusta lista tematow")
    tematy: list[Temat] = []
    widziane: set[str] = set()
    for nr, t in enumerate(surowe, 1):
        if not isinstance(t, dict):
            raise BladTematow(f"temat nr {nr}: oczekiwany obiekt")
        tid = t.get("id")
        if not isinstance(tid, str) or not _ID.match(tid):
            raise BladTematow(f"temat nr {nr}: id {tid!r} - male litery, cyfry, '-' lub '_', do 64 znakow")
        if tid in widziane:
            raise BladTematow(f"temat {tid}: id powtorzone")
        widziane.add(tid)
        for pole in ("nazwa", "opis"):
            if not isinstance(t.get(pole), str) or not t[pole].strip():
                raise BladTematow(f"temat {tid}: brak pola {pole} (admin wybiera po opisie, puste nie wolno)")
        przyklady = t.get("przyklady")
        if not isinstance(przyklady, list) or not przyklady or not all(isinstance(p, str) and p.strip() for p in przyklady):
            raise BladTematow(f"temat {tid}: przyklady musza byc niepusta lista tekstow")
        osobne = t.get("osobne_uprawnienie", False)
        if not isinstance(osobne, bool):
            raise BladTematow(f"temat {tid}: osobne_uprawnienie musi byc true/false")
        tematy.append(Temat(tid, t["nazwa"].strip(), t["opis"].strip(), tuple(p.strip() for p in przyklady), osobne))
    return tematy


def wczytaj(sciezka: Path | None = None) -> list[Temat]:
    """Tematy serwera. Brak pliku = pusta lista (nic nie da sie dodac); zly plik = BladTematow."""
    sciezka = sciezka or sciezki.plik_tematow()
    if not sciezka.exists():
        return []
    try:
        surowe = czytaj_json(sciezka)
    except (OSError, ValueError) as e:
        raise BladTematow(f"nie da sie odczytac {sciezka}: {e!r}") from e
    return sprawdz(surowe)


def slownik(sciezka: Path | None = None) -> dict[str, Temat]:
    return {t.id: t for t in wczytaj(sciezka)}


def _osierocone(nowe_id: set[str]) -> dict[str, int]:
    """Tematy z zywymi wpisami w bazie, ktorych nie ma na nowej liscie."""
    baza = sciezki.plik_bazy()
    if not baza.exists():
        return {}
    conn = sqlite3.connect(baza)
    try:
        if conn.execute("SELECT 1 FROM sqlite_master WHERE name = 'wpisy_tematy'").fetchone():
            # od 0.3.0 wpis ma kilka tematow - liczy sie kazdy, nie tylko glowny
            wiersze = conn.execute("SELECT wt.temat_id, COUNT(*) FROM wpisy_tematy wt JOIN wpisy w ON w.id = wt.wpis_id "
                                   "WHERE w.usuniety IS NULL GROUP BY wt.temat_id").fetchall()
        else:
            wiersze = conn.execute("SELECT temat, COUNT(*) FROM wpisy WHERE usuniety IS NULL GROUP BY temat").fetchall()
    except sqlite3.Error as e:
        print(f"UWAGA: nie sprawdzilem wpisow w bazie {baza} pod katem usunietych tematow: {e!r}", file=sys.stderr)
        return {}
    finally:
        conn.close()
    return {t: n for t, n in wiersze if t not in nowe_id}


def main(argv: list[str] | None = None) -> int:
    utf8_na_wyjsciu()
    p = argparse.ArgumentParser(prog="python -m wiedza_firmy.tematy")
    sub = p.add_subparsers(dest="polecenie", required=True)
    w = sub.add_parser("wczytaj", help="sprawdz plik JSON z tematami i zapisz go jako tematy serwera")
    w.add_argument("plik", type=Path)
    sub.add_parser("lista", help="pokaz tematy serwera")
    a = p.parse_args(argv)

    if a.polecenie == "wczytaj":
        try:
            tematy = sprawdz(czytaj_json(a.plik))
        except (OSError, ValueError) as e:
            print(f"ODMOWA: {a.plik}: {e}", file=sys.stderr)
            return 1
        zapisz_json(sciezki.plik_tematow(), [t.jako_slownik() for t in tematy])
        print(f"zapisano {len(tematy)} tematow do {sciezki.plik_tematow()}")
        sieroty = _osierocone({t.id for t in tematy})
        if sieroty:
            opis = ", ".join(f"{t} ({n})" for t, n in sorted(sieroty.items()))
            print(f"UWAGA: w bazie sa wpisy w tematach spoza nowej listy: {opis}. Nie znikaja; "
                  "widza je admin i osoby z uprawnieniem do tych tematow (temat spoza listy liczy sie jak "
                  "temat z osobnym uprawnieniem: trzeba go miec, zeby widziec wpis)", file=sys.stderr)
        return 0

    try:
        tematy = wczytaj()
    except BladTematow as e:
        print(f"BLAD: {e}", file=sys.stderr)
        return 1
    if not tematy:
        print(f"brak tematow ({sciezki.plik_tematow()} nie istnieje)")
    for t in tematy:
        znak = " [osobne uprawnienie]" if t.osobne_uprawnienie else ""
        print(f"{t.id}: {t.nazwa}{znak} - {t.opis}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
