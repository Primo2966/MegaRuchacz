"""Codzienna kopia zapasowa danych serwera "Wiedza firmy".

Kopiuje z katalogu danych (%APPDATA%\\wiedza-firmy\\):
  - kazda baze *.db przez API kopii SQLite (Connection.backup) - spojny obraz
    nawet wtedy, gdy serwer akurat pisze; zwykle kopiowanie pliku w locie
    potrafi zlapac polowe transakcji,
  - pliki *.json (tematy, osoby) - kazdy sprawdzony, ze jest poprawnym JSON-em
    (plik w trakcie zapisu = ponowna proba).
Kazda kopia bazy przechodzi PRAGMA integrity_check, zanim zostanie uznana.

Kopia trafia do <cel>\\RRRR-MM-DD_HHMMSS\\ (najpierw katalog roboczy, rename po
sukcesie - niepelna kopia nigdy nie wyglada na gotowa) z plikiem kopia.json
(sumy SHA-256, rozmiary). Kopie starsze niz --dni (14) sa usuwane; ruszane sa
tylko katalogi o nazwie w tym formacie. Opcjonalny drugi cel (np. Dysk Google)
dostaje to samo; jego blad daje status "czesciowo" - widoczny, nie cichy.

Wynik: <kat>\\stan\\kopia.json + linia w <kat>\\stan\\kopia.log. Kod wyjscia 0 = ok,
1 = blad, 2 = czesciowo (lokalna jest, drugi cel nie).

  python kopia.py --kat C:\\dev\\wiedza-firmy [--dane <kat>] [--cel <kat>] [--dni 14] [--drugi-cel <kat>]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sqlite3
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

WZOR_KATALOGU = re.compile(r"^(\d{4}-\d{2}-\d{2})_\d{6}$")
PROBY_JSON = 5
# Ile czekamy na baze zablokowana przez serwer w trakcie zapisu (backup ponawia krok).
LIMIT_BAZY_S = 120.0


class BladKopii(Exception):
    pass


def teraz() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for blok in iter(lambda: f.read(1 << 20), b""):
            h.update(blok)
    return h.hexdigest()


def kopiuj_baze(zrodlo: Path, cel: Path) -> dict:
    """Spojna kopia przez API kopii SQLite + integrity_check kopii."""
    # zwykle polaczenie, nie mode=ro: po awarii serwera tylko ono umie wycofac "goracy" dziennik
    src = sqlite3.connect(zrodlo, timeout=LIMIT_BAZY_S)
    try:
        dst = sqlite3.connect(cel)
        try:
            # Calosc w jednym kroku = jedna transakcja odczytu = jeden spojny obraz. Krokami po
            # kawalku kopia zaczyna sie od nowa po kazdym zapisie serwera i moze nie skonczyc nigdy.
            src.backup(dst, pages=-1, sleep=0.1)
        finally:
            dst.close()
    except sqlite3.Error as exc:
        raise BladKopii(f"kopia bazy {zrodlo.name}: {exc}") from None
    finally:
        src.close()
    return sprawdz_baze(cel)


def sprawdz_baze(sciezka: Path) -> dict:
    try:
        con = sqlite3.connect(f"file:{sciezka.as_posix()}?mode=ro", uri=True)
        try:
            wynik = [r[0] for r in con.execute("PRAGMA integrity_check").fetchall()]
            tabele = con.execute("SELECT count(*) FROM sqlite_master WHERE type='table'").fetchone()[0]
        finally:
            con.close()
    except sqlite3.Error as exc:
        raise BladKopii(f"kopia {sciezka.name} nie otwiera sie: {exc}") from None
    if wynik != ["ok"]:
        raise BladKopii(f"kopia {sciezka.name} nie przeszla integrity_check: {'; '.join(wynik[:3])}")
    return {"integrity_check": "ok", "tabel": tabele}


def kopiuj_json(zrodlo: Path, cel: Path) -> None:
    ostatni = ""
    for _ in range(PROBY_JSON):
        dane = zrodlo.read_bytes()
        try:
            json.loads(dane.decode("utf-8-sig"))
        except (ValueError, UnicodeDecodeError) as exc:
            ostatni = str(exc)
            time.sleep(0.5)  # serwer moze akurat zapisywac
            continue
        cel.write_bytes(dane)
        return
    raise BladKopii(f"{zrodlo.name} nie jest poprawnym JSON-em ({PROBY_JSON} prob): {ostatni}")


def zrob_kopie(dane: Path, cel: Path) -> Path:
    if not dane.is_dir():
        raise BladKopii(f"brak katalogu danych {dane}")
    bazy = sorted(dane.glob("*.db"))
    jsony = sorted(dane.glob("*.json"))
    if not bazy:
        raise BladKopii(f"w {dane} nie ma zadnej bazy *.db - nie ma czego kopiowac")
    cel.mkdir(parents=True, exist_ok=True)
    nazwa = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    roboczy = cel / f".w-toku-{nazwa}"
    gotowy = cel / nazwa
    roboczy.mkdir()
    try:
        opis: dict = {"czas": teraz(), "zrodlo": str(dane), "pliki": {}}
        for b in bazy:
            info = kopiuj_baze(b, roboczy / b.name)
            opis["pliki"][b.name] = {**info, "sha256": sha256(roboczy / b.name),
                                     "rozmiar": (roboczy / b.name).stat().st_size}
        for j in jsony:
            kopiuj_json(j, roboczy / j.name)
            opis["pliki"][j.name] = {"sha256": sha256(roboczy / j.name),
                                     "rozmiar": (roboczy / j.name).stat().st_size}
        (roboczy / "kopia.json").write_text(json.dumps(opis, ensure_ascii=False, indent=1), encoding="utf-8")
        os.replace(roboczy, gotowy)
    except BaseException:
        shutil.rmtree(roboczy, ignore_errors=True)
        raise
    return gotowy


def usun_stare(cel: Path, dni: int, zostaw: Path) -> list[str]:
    """Usuwa katalogi kopii starsze niz `dni`; nic innego nie rusza."""
    granica = (datetime.now() - timedelta(days=dni)).strftime("%Y-%m-%d")
    usuniete = []
    for p in cel.iterdir():
        m = WZOR_KATALOGU.match(p.name)
        if not p.is_dir() or not m or p == zostaw:
            continue
        if m.group(1) < granica:
            shutil.rmtree(p, ignore_errors=True)
            usuniete.append(p.name)
    # resztki po przerwanych kopiach
    for p in cel.glob(".w-toku-*"):
        if p.is_dir() and time.time() - p.stat().st_mtime > 3600:
            shutil.rmtree(p, ignore_errors=True)
    return usuniete


def kopiuj_drugi_cel(gotowy: Path, drugi: Path, dni: int) -> list[str]:
    if not drugi.is_dir():
        raise BladKopii(f"drugi cel {drugi} niedostepny (brak dysku/katalogu)")
    roboczy = drugi / f".w-toku-{gotowy.name}"
    shutil.rmtree(roboczy, ignore_errors=True)
    shutil.copytree(gotowy, roboczy)
    os.replace(roboczy, drugi / gotowy.name)
    return usun_stare(drugi, dni, drugi / gotowy.name)


def zapisz_stan(kat: Path, stan: dict) -> None:
    k = kat / "stan"
    k.mkdir(parents=True, exist_ok=True)
    plik = k / "kopia.json"
    try:
        poprzedni = json.loads(plik.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        poprzedni = {}
    stan.setdefault("ostatni_sukces", poprzedni.get("ostatni_sukces"))
    tmp = plik.with_name(f"kopia.json.{os.getpid()}.tmp")
    tmp.write_text(json.dumps(stan, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, plik)
    with open(k / "kopia.log", "a", encoding="utf-8") as f:
        znak = {"ok": "OK", "blad": "BLAD", "czesciowo": "CZESCIOWO"}.get(stan["status"], stan["status"])
        f.write(f"{stan['czas']} {znak}: {stan.get('przyczyna') or stan.get('katalog', '')}\n")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Kopia zapasowa danych serwera Wiedza firmy")
    p.add_argument("--kat", required=True, help="katalog instalacji (tu stan\\ i domyslnie kopie\\)")
    p.add_argument("--dane", help="katalog danych (domyslnie %%APPDATA%%\\wiedza-firmy)")
    p.add_argument("--cel", help="katalog kopii (domyslnie <kat>\\kopie)")
    p.add_argument("--dni", type=int, default=14)
    p.add_argument("--drugi-cel", default=None, help="drugie miejsce kopii, np. Dysk Google")
    a = p.parse_args(argv)
    kat = Path(a.kat)
    konf = {}
    try:
        konf = json.loads((kat / "serwer-wiedzy.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        pass
    dane = Path(a.dane or konf.get("dane") or Path(os.environ.get("APPDATA", "")) / "wiedza-firmy")
    cel = Path(a.cel or kat / "kopie")
    drugi = a.drugi_cel if a.drugi_cel is not None else konf.get("drugi_cel_kopii") or ""
    stan: dict = {"czas": teraz()}
    try:
        gotowy = zrob_kopie(dane, cel)
        stan.update(status="ok", katalog=str(gotowy), ostatni_sukces=stan["czas"],
                    usuniete=usun_stare(cel, a.dni, gotowy))
        if drugi:
            try:
                stan["usuniete_drugi_cel"] = kopiuj_drugi_cel(gotowy, Path(drugi), a.dni)
                stan["drugi_cel"] = "ok"
            except (BladKopii, OSError) as exc:
                stan.update(status="czesciowo", drugi_cel="blad",
                            przyczyna=f"lokalna kopia jest, drugi cel nie: {exc}")
    except (BladKopii, OSError, sqlite3.Error) as exc:
        stan.update(status="blad", przyczyna=str(exc))
    except Exception as exc:  # nic bez sladu
        stan.update(status="blad", przyczyna=f"nieoczekiwany {type(exc).__name__}: {exc}")
    zapisz_stan(kat, stan)
    print(f"{stan['status']}: {stan.get('przyczyna') or stan.get('katalog')}")
    return {"ok": 0, "czesciowo": 2}.get(stan["status"], 1)


if __name__ == "__main__":
    sys.exit(main())
