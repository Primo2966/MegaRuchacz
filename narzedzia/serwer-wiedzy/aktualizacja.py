"""Samoaktualizacja serwera "Wiedza firmy" z PUBLICZNEGO repo Primo2966/MegaRuchacz.

Bez gita i bez tokenu (na Pakowanie2 nie ma ani gita, ani uv). Jedno przejscie:

  1. zamek <kat>\\.aktualizacja.lock - dwa przebiegi naraz nie podmieniaja kodu,
  2. sha galezi main z API GitHuba; ten sam co ostatnio = koniec (bez pobierania),
  3. pobranie zipballa (twardy limit czasu i rozmiaru), sprawdzenie WSZYSTKICH
     sciezek w archiwum (zadnych "..", dyskow, sciezek bezwzglednych),
  4. zbudowanie nowego drzewa kodu obok (tylko wiedza_firmy\\ i lore\\lore\\ plus
     lore\\pyproject.toml - nic innego z repo), porownanie z obecnym,
  5. sprawdzenie, ze nowy kod sie importuje (uruchom.py --sprawdz) - PRZED podmiana,
  6. zaleznosci pip, gdy zmienila sie ich lista (blad = stary kod zostaje),
  7. podmiana jednym rename'em katalogu kod\\, ponowne sprawdzenie importu, przy
     bledzie powrot do starego katalogu.

Katalog danych (%APPDATA%\\wiedza-firmy\\) nie jest nigdy ruszany: podmiana dotyczy
tylko <kat>\\kod\\, a gdy katalog danych lezy w obszarze podmiany - odmowa.

Cisza zakazana: kazdy przebieg zapisuje <kat>\\stan\\aktualizacja.json (status,
przyczyna, ostatni sukces) i linie w <kat>\\stan\\aktualizacja.log.

Kody wyjscia: 0 aktualna / nic do zrobienia, 10 kod podmieniony (straznik
restartuje serwer), 1 blad, 3 zamek zajety.

  python aktualizacja.py --kat C:\\dev\\wiedza-firmy [--dane <kat danych>] [--zip <plik>] [--wymus]
  python aktualizacja.py --kat C:\\dev\\wiedza-firmy --zaleznosci
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import tomllib
import urllib.error
import urllib.request
import zipfile
from datetime import datetime
from pathlib import Path

REPO = "Primo2966/MegaRuchacz"
GALAZ = "main"
URL_API = "https://api.github.com"
USER_AGENT = "wiedza-firmy-aktualizacja"

LIMIT_SHA_S = 15.0
LIMIT_POBIERANIA_S = 90.0
LIMIT_SPRAWDZENIA_S = 120.0
LIMIT_PIP_S = 900.0
MAKS_ROZMIAR_ZIP = 100 * 1024 * 1024
# Zamek starszy niz to uznajemy za porzucony (proces ubity w trakcie): dluzej
# niz najdluzszy krok (pip, 15 min), zeby nie przejac zamka zywego przebiegu.
WAZNOSC_ZAMKA_S = 20 * 60

PLIK_ZAMKA = ".aktualizacja.lock"
PREFIKS_NOWY = ".kod-nowy-"
PREFIKS_STARY = ".kod-stary-"
PREFIKS_ZIP = ".aktualizacja-zip-"

# Z archiwum bierzemy wylacznie to (wzgledem katalogu glownego repo).
KATALOGI_KODU = ("wiedza_firmy/", "lore/lore/")
PLIKI_KODU = ("lore/pyproject.toml",)
POMIJANE = ("__pycache__",)
WYMAGANE = ("wiedza_firmy/pyproject.toml", "lore/lore/db.py")

# Tylko do testow: symulowana awaria po podmianie (sprawdza cofanie).
ENV_AWARIA = "SERWER_WIEDZY_AWARIA"

KOD_AKTUALNA, KOD_ZAKTUALIZOWANO, KOD_BLAD, KOD_ZAMEK = 0, 10, 1, 3


class BladAktualizacji(Exception):
    """Blad z przyczyna nadajaca sie do stanu i dziennika."""


def teraz() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


# --- stan i dziennik ---------------------------------------------------------

def kat_stanu(kat: Path) -> Path:
    return kat / "stan"


def czytaj_stan(kat: Path) -> dict:
    try:
        return json.loads((kat_stanu(kat) / "aktualizacja.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def zapisz_stan(kat: Path, dane: dict) -> None:
    k = kat_stanu(kat)
    k.mkdir(parents=True, exist_ok=True)
    cel = k / "aktualizacja.json"
    tmp = cel.with_name(f"aktualizacja.json.{os.getpid()}.tmp")
    tmp.write_text(json.dumps(dane, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, cel)


def dziennik(kat: Path, tekst: str) -> None:
    k = kat_stanu(kat)
    k.mkdir(parents=True, exist_ok=True)
    with open(k / "aktualizacja.log", "a", encoding="utf-8") as f:
        f.write(f"{teraz()} {tekst}\n")


def odnotuj(kat: Path, status: str, przyczyna: str, **pola) -> None:
    """Jedyne miejsce zapisu wyniku: stan + dziennik. Ostatni sukces przechodzi
    z poprzedniego stanu, zeby po serii bledow bylo widac, od kiedy nie dziala."""
    poprzedni = czytaj_stan(kat)
    stan = {
        "czas": teraz(),
        "status": status,
        "przyczyna": przyczyna,
        "sha": pola.pop("sha", poprzedni.get("sha")),
        "ostatni_sukces": poprzedni.get("ostatni_sukces"),
    }
    if status in ("aktualna", "zaktualizowano"):
        stan["ostatni_sukces"] = stan["czas"]
    stan.update(pola)
    zapisz_stan(kat, stan)
    znak = "BLAD" if status == "blad" else status.upper()
    dziennik(kat, f"{znak}: {przyczyna}" + (f" (sha {stan['sha']})" if stan.get("sha") else ""))


# --- pomocnicze --------------------------------------------------------------

def usun(sciezka: Path) -> None:
    if sciezka.is_dir() and not sciezka.is_symlink():
        shutil.rmtree(sciezka, ignore_errors=True)
    elif sciezka.exists():
        sciezka.unlink()
    if sciezka.exists():
        dziennik(sciezka.parent, f"UWAGA: nie udalo sie usunac {sciezka}")


def przenies(z: Path, do: Path, proby: int = 10) -> None:
    """rename z ponowieniem - antywirus/indeksator potrafi na moment trzymac plik."""
    for i in range(proby):
        try:
            os.replace(z, do)
            return
        except PermissionError:
            if i == proby - 1:
                raise
            time.sleep(0.3)


def wewnatrz(a: Path, b: Path) -> bool:
    """Czy a lezy w b (albo jest b)."""
    a, b = a.resolve(), b.resolve()
    return a == b or b in a.parents


def pliki_drzewa(katalog: Path) -> dict[str, bytes]:
    wynik: dict[str, bytes] = {}
    if not katalog.is_dir():
        return wynik
    for korzen, katalogi, nazwy in os.walk(katalog):
        katalogi[:] = [k for k in katalogi if k not in POMIJANE]
        for n in nazwy:
            if n.endswith(".pyc"):
                continue
            p = Path(korzen) / n
            wynik[p.relative_to(katalog).as_posix()] = p.read_bytes()
    return wynik


def zamek(kat: Path) -> bool:
    sciezka = kat / PLIK_ZAMKA
    for _ in range(2):
        try:
            fd = os.open(sciezka, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            with os.fdopen(fd, "w") as f:
                f.write(f"{os.getpid()} {teraz()}\n")
            return True
        except FileExistsError:
            try:
                wiek = time.time() - sciezka.stat().st_mtime
            except OSError:
                continue  # wlasnie zniknal
            if wiek <= WAZNOSC_ZAMKA_S:
                return False
            dziennik(kat, f"UWAGA: porzucony zamek ({wiek:.0f} s) - przejmuje")
            sciezka.unlink(missing_ok=True)
    return False


# --- GitHub ------------------------------------------------------------------

def _w_watku(praca, limit_s: float, co: str):
    """Twardy limit czasu (urllib nie pilnuje DNS ani nawiazania polaczenia)."""
    wynik: dict = {}

    def _p() -> None:
        try:
            wynik["ok"] = praca()
        except BaseException as exc:
            wynik["blad"] = exc

    w = threading.Thread(target=_p, daemon=True)
    w.start()
    w.join(limit_s)
    if w.is_alive():
        raise BladAktualizacji(f"{co}: przekroczony limit {limit_s:.0f} s")
    if "blad" in wynik:
        exc = wynik["blad"]
        if isinstance(exc, BladAktualizacji):
            raise exc
        if isinstance(exc, urllib.error.HTTPError):
            raise BladAktualizacji(f"{co}: GitHub odpowiedzial HTTP {exc.code}") from None
        raise BladAktualizacji(f"{co}: {type(exc).__name__}: {exc}") from None
    return wynik["ok"]


def sha_zdalne(url_api: str) -> str:
    def praca() -> str:
        zad = urllib.request.Request(
            f"{url_api}/repos/{REPO}/commits/{GALAZ}",
            headers={"Accept": "application/vnd.github.sha", "User-Agent": USER_AGENT})
        with urllib.request.urlopen(zad, timeout=LIMIT_SHA_S) as odp:
            return odp.read(200).decode("ascii", "replace").strip()

    sha = _w_watku(praca, LIMIT_SHA_S + 1, "sprawdzenie wersji na GitHubie")
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise BladAktualizacji(f"GitHub zwrocil dziwny sha: {sha[:60]!r}")
    return sha


def pobierz_zip(url_api: str, cel: Path) -> None:
    koniec = time.monotonic() + LIMIT_POBIERANIA_S

    def praca() -> None:
        zad = urllib.request.Request(f"{url_api}/repos/{REPO}/zipball/{GALAZ}",
                                     headers={"User-Agent": USER_AGENT})
        rozmiar = 0
        with urllib.request.urlopen(zad, timeout=30) as odp, open(cel, "wb") as f:
            while True:
                if time.monotonic() > koniec:
                    raise BladAktualizacji("pobieranie: przekroczony limit czasu")
                kawalek = odp.read(65536)
                if not kawalek:
                    break
                rozmiar += len(kawalek)
                if rozmiar > MAKS_ROZMIAR_ZIP:
                    raise BladAktualizacji("pobieranie: archiwum za duze")
                f.write(kawalek)

    _w_watku(praca, LIMIT_POBIERANIA_S + 1, "pobieranie archiwum")


# --- archiwum ----------------------------------------------------------------

def sprawdz_sciezki(nazwy: list[str]) -> str:
    """Wszystkie wpisy pod jednym katalogiem glownym, bez wyjscia poza niego.
    Zwraca nazwe katalogu glownego."""
    korzenie = set()
    for n in nazwy:
        czesci = n.replace("\\", "/").split("/")
        if n.startswith(("/", "\\")) or ":" in n or ".." in czesci:
            raise BladAktualizacji(f"podejrzana sciezka w archiwum: {n!r} - odrzucam cale archiwum")
        if czesci[0]:
            korzenie.add(czesci[0])
    if len(korzenie) != 1:
        raise BladAktualizacji(f"archiwum nie ma jednego katalogu glownego ({len(korzenie)})")
    return korzenie.pop()


def zbuduj_drzewo(zip_sciezka: Path, cel: Path) -> str:
    """Rozpakowuje z archiwum tylko pliki serwera do `cel`. Zwraca katalog glowny."""
    try:
        with zipfile.ZipFile(zip_sciezka) as zf:
            nazwy = zf.namelist()
            korzen = sprawdz_sciezki(nazwy)
            for info in zf.infolist():
                if info.is_dir():
                    continue
                rel = info.filename.replace("\\", "/")[len(korzen) + 1:]
                if not (rel.startswith(KATALOGI_KODU) or rel in PLIKI_KODU):
                    continue
                if any(c in POMIJANE for c in rel.split("/")) or rel.endswith(".pyc"):
                    continue
                docelowy = cel.joinpath(*rel.split("/"))
                docelowy.parent.mkdir(parents=True, exist_ok=True)
                with zf.open(info) as zr, open(docelowy, "wb") as zw:
                    shutil.copyfileobj(zr, zw)  # zla suma CRC = wyjatek
    except zipfile.BadZipFile as exc:
        raise BladAktualizacji(f"uszkodzone archiwum: {exc}") from None
    except (OSError, EOFError, ValueError) as exc:
        raise BladAktualizacji(f"uszkodzone archiwum albo blad zapisu: {type(exc).__name__}: {exc}") from None
    brak = [w for w in WYMAGANE if not cel.joinpath(*w.split("/")).is_file()]
    if brak:
        raise BladAktualizacji(
            "w archiwum nie ma " + ", ".join(brak)
            + " - kod serwera wiedzy nie jest jeszcze w repo (galaz main)?")
    return korzen


# --- zaleznosci --------------------------------------------------------------

def _nazwa_pakietu(wymaganie: str) -> str:
    m = re.match(r"\s*([A-Za-z0-9][A-Za-z0-9._-]*)", wymaganie)
    return re.sub(r"[-_.]+", "-", m.group(1)).lower() if m else ""


def zaleznosci(kod: Path) -> list[str]:
    """Zaleznosci z wiedza_firmy\\pyproject.toml plus te z lore\\pyproject.toml,
    ktorych wiedza_firmy nie podaje sama. Z lore pomijamy mcp (o wersji mcp
    decyduje serwer wiedzy) i sam pakiet lore (dostarczamy go sciezka)."""
    pp = kod / "wiedza_firmy" / "pyproject.toml"
    if not pp.is_file():
        raise BladAktualizacji(f"brak {pp} - nie wiem, jakie zaleznosci instalowac")
    try:
        wf = tomllib.loads(pp.read_text(encoding="utf-8")).get("project", {}).get("dependencies", [])
    except (OSError, ValueError) as exc:
        raise BladAktualizacji(f"nieczytelny {pp}: {exc}") from None
    wynik = [d for d in wf if _nazwa_pakietu(d) != "lore"]
    znane = {_nazwa_pakietu(d) for d in wynik}
    lp = kod / "lore" / "pyproject.toml"
    if lp.is_file():
        try:
            lore = tomllib.loads(lp.read_text(encoding="utf-8")).get("project", {}).get("dependencies", [])
        except (OSError, ValueError) as exc:
            raise BladAktualizacji(f"nieczytelny {lp}: {exc}") from None
        wynik += [d for d in lore if _nazwa_pakietu(d) not in znane and _nazwa_pakietu(d) != "mcp"]
    return wynik


def pip_install(kat: Path, wymagania: list[str]) -> None:
    if not wymagania:
        return
    log = kat_stanu(kat) / "pip.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    with open(log, "a", encoding="utf-8") as wy:
        wy.write(f"\n=== {teraz()} pip install {' '.join(wymagania)}\n")
        wy.flush()
        try:
            proc = subprocess.run(
                [sys.executable, "-m", "pip", "install", "--disable-pip-version-check",
                 "--no-input", *wymagania],
                stdin=subprocess.DEVNULL, stdout=wy, stderr=subprocess.STDOUT,
                timeout=LIMIT_PIP_S, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        except subprocess.TimeoutExpired:
            raise BladAktualizacji(f"pip przekroczyl limit {LIMIT_PIP_S:.0f} s (szczegoly: {log})") from None
        except OSError as exc:
            raise BladAktualizacji(f"nie da sie uruchomic pip: {exc}") from None
    if proc.returncode != 0:
        raise BladAktualizacji(f"pip zakonczyl sie kodem {proc.returncode} (szczegoly: {log})")


# --- sprawdzenie kodu ----------------------------------------------------------

def sprawdz_kod(kat: Path, kod: Path, modul: str) -> None:
    uruchom = Path(__file__).resolve().parent / "uruchom.py"
    try:
        proc = subprocess.run(
            [sys.executable, str(uruchom), "--kod", str(kod), "--sprawdz", modul],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=LIMIT_SPRAWDZENIA_S,
            env={**os.environ, "LORE_HOME": os.environ.get("LORE_HOME", str(kat / "lore-dane"))},
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    except subprocess.TimeoutExpired:
        raise BladAktualizacji(f"sprawdzenie importu {modul}: limit {LIMIT_SPRAWDZENIA_S:.0f} s") from None
    if proc.returncode != 0:
        opis = (proc.stderr or proc.stdout or "").strip().splitlines()
        raise BladAktualizacji(f"nowy kod sie nie importuje ({modul}): {opis[-1] if opis else proc.returncode}")


# --- glowna logika -------------------------------------------------------------

def sprzataj(kat: Path) -> None:
    for p in kat.iterdir():
        if p.name.startswith((PREFIKS_NOWY, PREFIKS_STARY, PREFIKS_ZIP)):
            usun(p)


def aktualizuj(kat: Path, dane: Path, modul: str, *, zip_lokalny: Path | None,
               url_api: str, wymus: bool) -> int:
    kod = kat / "kod"
    # Dane nigdy w obszarze podmiany: podmiana przenosi i kasuje caly kod\.
    if wewnatrz(dane, kod) or wewnatrz(kod, dane) or wewnatrz(kat, dane):
        odnotuj(kat, "blad", f"katalog danych {dane} lezy w obszarze podmiany kodu {kod} - odmawiam")
        return KOD_BLAD
    kat.mkdir(parents=True, exist_ok=True)
    if not zamek(kat):
        dziennik(kat, "ZAMEK_ZAJETY: inny przebieg aktualizacji trwa - pomijam")
        stan = czytaj_stan(kat)
        stan.update({"czas_zamka": teraz(), "zamek": "zajety"})
        zapisz_stan(kat, stan)
        return KOD_ZAMEK
    try:
        sprzataj(kat)
        stan = czytaj_stan(kat)
        sha = None
        if zip_lokalny is None:
            sha = sha_zdalne(url_api)
            if sha == stan.get("sha") and kod.is_dir() and not wymus:
                odnotuj(kat, "aktualna", "bez zmian na GitHubie", sha=sha, kod_zmieniony=False)
                return KOD_AKTUALNA
            zip_sciezka = kat / f"{PREFIKS_ZIP}{os.getpid()}.zip"
            pobierz_zip(url_api, zip_sciezka)
        else:
            zip_sciezka = zip_lokalny
        nowy = kat / f"{PREFIKS_NOWY}{os.getpid()}"
        korzen = zbuduj_drzewo(zip_sciezka, nowy)
        if sha is None:
            sha = korzen.rsplit("-", 1)[-1]
        if kod.is_dir() and pliki_drzewa(nowy) == pliki_drzewa(kod):
            odnotuj(kat, "aktualna", "kod serwera bez zmian", sha=sha, kod_zmieniony=False)
            return KOD_AKTUALNA
        # Zaleznosci przed sprawdzeniem importu (nowy kod moze potrzebowac nowego pakietu).
        # pip tylko dodaje pakiety - gdy potem sprawdzenie padnie, stary kod dalej dziala.
        if not kod.is_dir() or zaleznosci(nowy) != zaleznosci(kod):
            pip_install(kat, zaleznosci(nowy))
        sprawdz_kod(kat, nowy, modul)
        stary = kat / f"{PREFIKS_STARY}{os.getpid()}"
        byl = kod.is_dir()
        if byl:
            przenies(kod, stary)
        try:
            przenies(nowy, kod)
            if os.environ.get(ENV_AWARIA) == "po_podmianie":
                raise BladAktualizacji("symulowana awaria po podmianie (test)")
            sprawdz_kod(kat, kod, modul)
        except Exception as exc:
            cofnij(kod, stary, nowy, byl)
            if isinstance(exc, BladAktualizacji):
                raise BladAktualizacji(f"{exc} - przywrocono poprzedni kod") from None
            raise BladAktualizacji(f"podmiana nieudana ({type(exc).__name__}: {exc}) - przywrocono poprzedni kod") from None
        usun(stary)
        odnotuj(kat, "zaktualizowano", "kod serwera podmieniony", sha=sha, sha_poprzedni=stan.get("sha"),
                kod_zmieniony=True)
        return KOD_ZAKTUALIZOWANO
    except BladAktualizacji as exc:
        odnotuj(kat, "blad", str(exc), kod_zmieniony=False)
        return KOD_BLAD
    except Exception as exc:  # nic nie ma prawa przejsc bez sladu
        odnotuj(kat, "blad", f"nieoczekiwany {type(exc).__name__}: {exc}", kod_zmieniony=False)
        return KOD_BLAD
    finally:
        try:
            sprzataj(kat)
        except OSError as exc:
            dziennik(kat, f"UWAGA: sprzatanie: {exc}")
        (kat / PLIK_ZAMKA).unlink(missing_ok=True)


def cofnij(kod: Path, stary: Path, nowy: Path, byl: bool) -> None:
    if kod.exists():
        przenies(kod, nowy)  # nieudany nowy kod idzie do sprzatniecia
    if byl:
        przenies(stary, kod)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Samoaktualizacja serwera Wiedza firmy")
    p.add_argument("--kat", required=True, help="katalog instalacji (C:\\dev\\wiedza-firmy)")
    p.add_argument("--dane", help="katalog danych (domyslnie %%APPDATA%%\\wiedza-firmy)")
    p.add_argument("--modul", default=None, help="modul serwera do sprawdzenia importu")
    p.add_argument("--zip", help="lokalne archiwum zamiast GitHuba (pierwsza instalacja, testy)")
    p.add_argument("--url-api", default=URL_API)
    p.add_argument("--wymus", action="store_true", help="pobierz nawet przy tym samym sha")
    p.add_argument("--zaleznosci", action="store_true", help="tylko pip install zaleznosci obecnego kodu")
    a = p.parse_args(argv)
    kat = Path(a.kat)
    konf = {}
    try:
        konf = json.loads((kat / "serwer-wiedzy.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        pass
    modul = a.modul or konf.get("modul") or "wiedza_firmy.serwer"
    if a.zaleznosci:
        try:
            wym = zaleznosci(kat / "kod")
            pip_install(kat, wym)
        except BladAktualizacji as exc:
            dziennik(kat, f"BLAD zaleznosci: {exc}")
            print(f"[BLAD] {exc}", file=sys.stderr)
            return KOD_BLAD
        dziennik(kat, f"zaleznosci zainstalowane: {', '.join(wym) or '(brak)'}")
        print(f"OK: zaleznosci zainstalowane: {', '.join(wym) or '(brak)'}")
        return KOD_AKTUALNA
    dane = Path(a.dane or konf.get("dane") or Path(os.environ.get("APPDATA", "")) / "wiedza-firmy")
    kod_wyjscia = aktualizuj(kat, dane, modul, zip_lokalny=Path(a.zip) if a.zip else None,
                             url_api=a.url_api.rstrip("/"), wymus=a.wymus)
    stan = czytaj_stan(kat)
    print(f"{stan.get('status', '?')}: {stan.get('przyczyna', '')}" if kod_wyjscia != KOD_ZAMEK
          else "zamek_zajety: inny przebieg aktualizacji trwa")
    return kod_wyjscia


if __name__ == "__main__":
    sys.exit(main())
