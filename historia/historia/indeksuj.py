"""Indekser przyrostowy transkryptów Claude Code (~/.claude/projects/**/*.jsonl oraz ~/<uuid>*.jsonl z Orki).

Uruchomienie: uv --directory C:\\dev\\claude-historia run python -m historia.indeksuj
"""

from __future__ import annotations

import json
import os
import re
import sqlite3
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from .baza import KATALOG_PROJEKTOW, SCIEZKA_BAZY, embedduj_passages, log, polacz
from .maskowanie import maskuj

DLUGOSC_KAWALKA = 1500
ZAKLADKA = 200
KROK = DLUGOSC_KAWALKA - ZAKLADKA
MAX_INPUT_NARZEDZIA = 200
MAX_WYNIK_NARZEDZIA = 400
MIN_DLUGOSC = 3

SEPARATOR_WYPOWIEDZI = "\n\n"
ROLA_MIESZANA = "rozmowa"
# ostatniej grupy nie zapisujemy — sesja może ją jeszcze dopisać; ale nie czekamy w nieskończoność
WIEK_ZAMYKAJACY_OGON_S = 24 * 60 * 60

PLIK_BLOKADY = SCIEZKA_BAZY.with_suffix(".lock")
BLOKADA_PRZETERMINOWANA_S = 15 * 60

# sesje uruchamiane przez Orcę zapisują transkrypty luźno w katalogu domowym
KATALOG_DOMOWY = Path.home()
PROJEKT_DOMOWY = "orca"
_UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.I)

# wiersze użytkownika generowane przez samo Claude Code, bez wartości dla pamięci
_SZUM_PREFIKSY = (
    "<task-notification>",
    "<local-command",
    "<ide_opened_file>",
    "<ide_selection>",
    "<command-name>",
    "<command-message>",
    "<bash-input>",
    "<bash-stdout>",
    "<bash-stderr>",
    "[Request interrupted",
    "Base directory for this skill",
    "Caveat: The messages below",
)
_SYSTEM_REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.DOTALL)


@dataclass
class Wypowiedz:
    """Jedna wypowiedź z transkryptu — materiał wejściowy do grupowania."""

    linia: int
    ts: str
    rola: str
    tekst: str


@dataclass
class Fragment:
    linia: int
    czesc: int
    ts: str
    rola: str
    tekst: str


# ---------------------------------------------------------------- parsowanie rekordów

def _tekst_z_content(content) -> str:
    """Łączy bloki `text` (albo zwraca string) — dla wyników narzędzi."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    return ""


def _skrot_inputu(inp) -> str:
    if isinstance(inp, dict):
        # najbardziej mówiące pola na początek
        for k in ("command", "description", "pattern", "file_path", "query", "prompt", "zapytanie"):
            if k in inp and isinstance(inp[k], str):
                return " ".join(inp[k].split())[:MAX_INPUT_NARZEDZIA]
        s = json.dumps(inp, ensure_ascii=False)
    else:
        s = str(inp)
    return " ".join(s.split())[:MAX_INPUT_NARZEDZIA]


def _oczysc_tekst_uzytkownika(t: str) -> str:
    t = _SYSTEM_REMINDER.sub("", t).strip()
    if not t or t.startswith(_SZUM_PREFIKSY):
        return ""
    return t


def fragmenty_z_rekordu(rec: dict, prefiks_roli: str = "") -> list[tuple[str, str]]:
    """Zwraca listę (rola, tekst) z jednego wiersza JSONL. Pusta lista = pomiń."""
    typ = rec.get("type")
    if typ not in ("user", "assistant"):
        return []
    if rec.get("isMeta") or rec.get("isApiErrorMessage"):
        return []
    msg = rec.get("message") or {}
    content = msg.get("content")
    wynik: list[tuple[str, str]] = []

    if typ == "user":
        if rec.get("isCompactSummary"):
            t = _tekst_z_content(content).strip()
            if t:
                wynik.append((prefiks_roli + "podsumowanie", t))
            return wynik
        if isinstance(content, str):
            t = _oczysc_tekst_uzytkownika(content)
            if t:
                wynik.append((prefiks_roli + "user", t))
            return wynik
        if isinstance(content, list):
            teksty = []
            for b in content:
                if not isinstance(b, dict):
                    continue
                bt = b.get("type")
                if bt == "text":
                    t = _oczysc_tekst_uzytkownika(b.get("text", ""))
                    if t:
                        teksty.append(t)
                elif bt == "tool_result" and not prefiks_roli:  # szum narzędziowy subagentów pomijamy
                    t = " ".join(_tekst_z_content(b.get("content")).split())
                    if t:
                        if b.get("is_error"):
                            t = "[błąd] " + t
                        wynik.append((prefiks_roli + "wynik", t[:MAX_WYNIK_NARZEDZIA]))
            if teksty:
                wynik.insert(0, (prefiks_roli + "user", "\n".join(teksty)))
        return wynik

    # assistant
    if isinstance(content, str):
        if content.strip():
            wynik.append((prefiks_roli + "assistant", content.strip()))
        return wynik
    if isinstance(content, list):
        teksty = []
        for b in content:
            if not isinstance(b, dict):
                continue
            bt = b.get("type")
            if bt == "text":
                t = b.get("text", "").strip()
                if t:
                    teksty.append(t)
            elif bt == "tool_use" and not prefiks_roli:
                nazwa = b.get("name", "?")
                wynik.append((prefiks_roli + "narzedzie", f"[narzędzie: {nazwa}] {_skrot_inputu(b.get('input'))}"))
        if teksty:
            wynik.insert(0, (prefiks_roli + "assistant", "\n".join(teksty)))
    return wynik


def potnij(tekst: str) -> list[str]:
    if len(tekst) <= DLUGOSC_KAWALKA:
        return [tekst]
    kawalki = []
    i = 0
    while i < len(tekst):
        kawalki.append(tekst[i : i + DLUGOSC_KAWALKA])
        if i + DLUGOSC_KAWALKA >= len(tekst):
            break
        i += KROK
    return kawalki


# ---------------------------------------------------------------- grupowanie wypowiedzi

def _za_dluga(w: Wypowiedz) -> bool:
    return len(w.tekst) > DLUGOSC_KAWALKA


def pogrupuj(wypowiedzi: list[Wypowiedz]) -> list[list[Wypowiedz]]:
    """Skleja kolejne wypowiedzi w grupy mieszczące się w jednym kawałku.

    Samotne „tak, rób to" ma pusty wektor — pytanie, którego dotyczy, siedzi w innym wpisie.
    Dlatego krótkie wypowiedzi trafiają do bazy razem z sąsiadami. Wypowiedź dłuższa niż
    kawałek stanowi własną grupę (i jest cięta jak dotąd).
    """
    grupy: list[list[Wypowiedz]] = []
    biezaca: list[Wypowiedz] = []
    dlugosc = 0
    for w in wypowiedzi:
        if _za_dluga(w):
            if biezaca:
                grupy.append(biezaca)
                biezaca, dlugosc = [], 0
            grupy.append([w])
            continue
        koszt = len(w.rola) + 2 + len(w.tekst)  # "rola: tekst"
        razem = dlugosc + len(SEPARATOR_WYPOWIEDZI) + koszt if biezaca else koszt
        if biezaca and razem > DLUGOSC_KAWALKA:
            grupy.append(biezaca)
            biezaca, dlugosc, razem = [], 0, koszt
        biezaca.append(w)
        dlugosc = razem
    if biezaca:
        grupy.append(biezaca)
    return grupy


def _fragmenty_z_grupy(grupa: list[Wypowiedz], prefiks_roli: str) -> list[Fragment]:
    """Grupa -> kawałki gotowe do zapisu. Sklejone wypowiedzi dostają prefiks roli w treści."""
    role = {w.rola for w in grupa}
    rola = role.pop() if len(role) == 1 else prefiks_roli + ROLA_MIESZANA
    if len(grupa) == 1:
        tekst = grupa[0].tekst  # pojedyncza wypowiedź zostaje taka, jaka była
    else:
        tekst = SEPARATOR_WYPOWIEDZI.join(f"{w.rola}: {w.tekst}" for w in grupa)
    pierwsza = grupa[0]
    return [Fragment(pierwsza.linia, cz, pierwsza.ts, rola, k) for cz, k in enumerate(potnij(tekst))]


def _ogon_otwarty(grupa: list[Wypowiedz], mtime: float) -> bool:
    """Czy ostatnia grupa może jeszcze urosnąć o wypowiedź, której nikt jeszcze nie dopisał."""
    if len(grupa) == 1 and _za_dluga(grupa[0]):
        return False  # długiej wypowiedzi i tak nie sklejamy z sąsiadami
    return time.time() - mtime <= WIEK_ZAMYKAJACY_OGON_S


# ---------------------------------------------------------------- pliki

def _pliki_domowe() -> list[Path]:
    """Transkrypty sesji Orca: ~/<uuid>.jsonl oraz zawartość ~/<uuid>/ (bez schodzenia po całym $HOME)."""
    if not KATALOG_DOMOWY.is_dir():
        return []
    pliki: list[Path] = []
    try:
        wpisy = list(KATALOG_DOMOWY.iterdir())
    except OSError:
        return []
    for w in wpisy:
        try:
            if w.is_file():
                if w.suffix == ".jsonl":
                    pliki.append(w)
            elif w.is_dir() and _UUID.fullmatch(w.name):
                pliki.extend(q for q in w.rglob("*.jsonl") if q.is_file())
        except OSError:  # np. katalog bez prawa odczytu
            continue
    return pliki


def znajdz_pliki() -> list[Path]:
    pliki: list[Path] = []
    if KATALOG_PROJEKTOW.is_dir():
        pliki.extend(p for p in KATALOG_PROJEKTOW.rglob("*.jsonl") if p.is_file())
    pliki.extend(_pliki_domowe())
    return sorted(pliki)


def opisz_plik(p: Path) -> tuple[str, str, str]:
    """(projekt, sesja, prefiks roli) na podstawie położenia pliku."""
    try:
        rel = p.relative_to(KATALOG_PROJEKTOW).parts
    except ValueError:
        # Orca: ~/<uuid>.jsonl albo ~/<uuid>/subagents/.../agent-xxx.jsonl
        rel = p.relative_to(KATALOG_DOMOWY).parts
        if len(rel) == 1:
            return PROJEKT_DOMOWY, p.stem, ""
        return PROJEKT_DOMOWY, rel[0], "agent:"
    projekt = rel[0] if len(rel) > 1 else "?"
    if len(rel) == 2:
        return projekt, p.stem, ""
    # <projekt>/<sesja>/subagents/.../agent-xxx.jsonl
    return projekt, rel[1], "agent:"


def _etykieta(p: Path) -> str:
    """Krótka ścieżka do logu — pliki spoza katalogu projektów pokazujemy samą nazwą."""
    try:
        return str(p.relative_to(KATALOG_PROJEKTOW))
    except ValueError:
        return p.name


def _czytaj_nowe_linie(p: Path, offset: int) -> tuple[list[tuple[int, str]], int]:
    """Zwraca [(nr_bajtu_poczatku, linia)] od offsetu i nowy offset (tylko pełne linie)."""
    linie = []
    with open(p, "rb") as f:
        f.seek(offset)
        poz = offset
        while True:
            raw = f.readline()
            if not raw:
                break
            if not raw.endswith(b"\n"):
                break  # niedokończona linia — ktoś jeszcze pisze
            linie.append((poz, raw.decode("utf-8", errors="replace")))
            poz += len(raw)
    return linie, poz


def _wypowiedzi_z_linii(linie: list[tuple[int, str]], start_linia: int, prefiks_roli: str, ts_domyslny: str) -> tuple[list[Wypowiedz], str, str | None]:
    """Parsuje linie -> wypowiedzi. Zwraca (wypowiedzi, ostatni_ts, sessionId z rekordów)."""
    fr: list[Wypowiedz] = []
    ts = ts_domyslny
    sesja_z_rekordu = None
    nr = start_linia
    for _, l in linie:
        nr += 1
        l = l.strip()
        if not l or not l.startswith("{"):
            continue
        try:
            rec = json.loads(l)
        except json.JSONDecodeError:
            continue
        if not isinstance(rec, dict):
            continue
        ts = rec.get("timestamp") or ts
        if sesja_z_rekordu is None and rec.get("sessionId"):
            sesja_z_rekordu = rec["sessionId"]
        for rola, tekst in fragmenty_z_rekordu(rec, prefiks_roli):
            # samotne surogaty UTF-16 (uszkodzone emoji w JSON) wywracają tokenizer i SQLite
            tekst = maskuj(tekst).encode("utf-8", errors="replace").decode("utf-8").strip()
            if len(tekst) < MIN_DLUGOSC:
                continue
            fr.append(Wypowiedz(nr, ts, rola, tekst))
    return fr, ts, sesja_z_rekordu


def _granica_grupy(grupa: list[Wypowiedz], linie: list[tuple[int, str]], start_linia: int, koniec_offset: int) -> tuple[int, int]:
    """(offset, numer linii) tuż za ostatnią linią grupy — punkt wznowienia po jej domknięciu."""
    ostatnia = max(w.linia for w in grupa)
    nastepna = ostatnia - start_linia  # indeks kolejnej linii w `linie`
    return (linie[nastepna][0] if nastepna < len(linie) else koniec_offset), ostatnia


# ---------------------------------------------------------------- blokada między procesami

def _zajmij_blokade() -> bool:
    for _ in range(2):
        try:
            fd = os.open(PLIK_BLOKADY, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, str(os.getpid()).encode())
            os.close(fd)
            return True
        except FileExistsError:
            try:
                wiek = time.time() - PLIK_BLOKADY.stat().st_mtime
            except FileNotFoundError:
                continue
            if wiek > BLOKADA_PRZETERMINOWANA_S:
                log(f"usuwam przeterminowaną blokadę ({wiek:.0f}s)")
                try:
                    PLIK_BLOKADY.unlink()
                except FileNotFoundError:
                    pass
                continue
            return False
    return False


def _odswiez_blokade() -> None:
    try:
        os.utime(PLIK_BLOKADY, None)
    except FileNotFoundError:
        pass


def _zwolnij_blokade() -> None:
    try:
        PLIK_BLOKADY.unlink()
    except FileNotFoundError:
        pass


# ---------------------------------------------------------------- główna pętla

def _usun_fragmenty_pliku(conn: sqlite3.Connection, sciezka: str, od_linii: int | None = None) -> None:
    """Kasuje fragmenty pliku — całe albo tylko te powyżej punktu wznowienia (zabezpieczenie przed duplikatami)."""
    if od_linii is None:
        warunek, argi = "plik=?", (sciezka,)
    else:
        warunek, argi = "plik=? AND linia>?", (sciezka, od_linii)
    ids = [r[0] for r in conn.execute(f"SELECT id FROM fragmenty WHERE {warunek}", argi)]
    if not ids:
        return
    for i in ids:
        conn.execute("INSERT INTO fragmenty_fts(fragmenty_fts, rowid, tekst) SELECT 'delete', id, tekst FROM fragmenty WHERE id=?", (i,))
    conn.execute(f"DELETE FROM wektory WHERE fragment_id IN (SELECT id FROM fragmenty WHERE {warunek})", argi)
    conn.execute(f"DELETE FROM fragmenty WHERE {warunek}", argi)


def _ogon_do_domkniecia(offset: int, st: os.stat_result) -> bool:
    """Plik bez zmian, ale wisi na nim niezapisana grupa, której już nic nie dopisze."""
    return offset < st.st_size and time.time() - st.st_mtime > WIEK_ZAMYKAJACY_OGON_S


def przetworz_plik(conn: sqlite3.Connection, p: Path) -> int:
    """Dokłada nowe linie z jednego pliku. Zwraca liczbę nowych fragmentów."""
    sciezka = str(p)
    st = p.stat()
    row = conn.execute("SELECT mtime, rozmiar, offset, linia FROM pliki WHERE sciezka=?", (sciezka,)).fetchone()
    if row and row[0] == st.st_mtime and row[1] == st.st_size and not _ogon_do_domkniecia(row[2], st):
        return 0
    offset, start_linia = (row[2], row[3]) if row else (0, 0)
    od_nowa = False
    if st.st_size < offset:
        od_nowa = True  # plik skrócony/nadpisany — indeksujemy od zera
        offset, start_linia = 0, 0

    projekt, sesja, prefiks_roli = opisz_plik(p)
    ostatni_ts = ""
    if row and not od_nowa:
        r = conn.execute("SELECT ts FROM fragmenty WHERE plik=? ORDER BY linia DESC, czesc DESC LIMIT 1", (sciezka,)).fetchone()
        ostatni_ts = r[0] if r else ""
    if not ostatni_ts:
        ostatni_ts = datetime.fromtimestamp(st.st_mtime, tz=timezone.utc).isoformat().replace("+00:00", "Z")

    linie, koniec_offset = _czytaj_nowe_linie(p, offset)
    wypowiedzi, _, sesja_rec = _wypowiedzi_z_linii(linie, start_linia, prefiks_roli, ostatni_ts)
    if not prefiks_roli and sesja_rec:
        sesja = sesja_rec

    grupy = pogrupuj(wypowiedzi)
    if grupy and _ogon_otwarty(grupy[-1], st.st_mtime):
        grupy.pop()  # ostatnia grupa może jeszcze urosnąć — zapiszemy ją, gdy się domknie
    if grupy:
        # offset zatrzymujemy na końcu ostatniej ZAMKNIĘTEJ grupy: resztę przeczytamy ponownie
        nowy_offset, nowa_linia = _granica_grupy(grupy[-1], linie, start_linia, koniec_offset)
    elif wypowiedzi:
        nowy_offset, nowa_linia = offset, start_linia
    else:
        nowy_offset, nowa_linia = koniec_offset, start_linia + len(linie)
    fragmenty = [f for g in grupy for f in _fragmenty_z_grupy(g, prefiks_roli)]

    # embeddingi liczymy poza transakcją (nie trzymamy blokady zapisu przez minuty)
    emb = embedduj_passages([f.tekst for f in fragmenty]) if fragmenty else None

    conn.execute("BEGIN IMMEDIATE")
    try:
        # ktoś mógł zdążyć przed nami (drugie okno / harmonogram)
        row2 = conn.execute("SELECT mtime, rozmiar, offset FROM pliki WHERE sciezka=?", (sciezka,)).fetchone()
        if row2 and row2[0] == st.st_mtime and row2[1] == st.st_size and row2[2] >= nowy_offset:
            conn.execute("ROLLBACK")
            return 0
        if od_nowa:
            _usun_fragmenty_pliku(conn, sciezka)
        else:
            _usun_fragmenty_pliku(conn, sciezka, od_linii=start_linia)
        for i, f in enumerate(fragmenty):
            cur = conn.execute(
                "INSERT INTO fragmenty(projekt, sesja, plik, linia, czesc, ts, rola, tekst) VALUES (?,?,?,?,?,?,?,?)",
                (projekt, sesja, sciezka, f.linia, f.czesc, f.ts, f.rola, f.tekst),
            )
            fid = cur.lastrowid
            conn.execute("INSERT INTO fragmenty_fts(rowid, tekst) VALUES (?,?)", (fid, f.tekst))
            conn.execute("INSERT INTO wektory(fragment_id, emb) VALUES (?,?)", (fid, emb[i].tobytes()))
        conn.execute(
            "INSERT INTO pliki(sciezka, mtime, rozmiar, offset, linia, projekt, sesja) VALUES (?,?,?,?,?,?,?) "
            "ON CONFLICT(sciezka) DO UPDATE SET mtime=excluded.mtime, rozmiar=excluded.rozmiar, "
            "offset=excluded.offset, linia=excluded.linia, projekt=excluded.projekt, sesja=excluded.sesja",
            (sciezka, st.st_mtime, st.st_size, nowy_offset, nowa_linia, projekt, sesja),
        )
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise
    return len(fragmenty)


def indeksuj(conn: sqlite3.Connection | None = None, cicho: bool = False) -> int:
    """Pełny przebieg przyrostowy po wszystkich plikach. Zwraca liczbę nowych fragmentów."""
    if not _zajmij_blokade():
        if not cicho:
            log("inny proces właśnie indeksuje — pomijam")
        return 0
    wlasne = conn is None
    if wlasne:
        conn = polacz()
    start = time.time()
    nowe = 0
    pliki_zmienione = 0
    try:
        pliki = znajdz_pliki()
        for p in pliki:
            try:
                n = przetworz_plik(conn, p)
            except sqlite3.OperationalError as e:
                log(f"pominięto {p.name}: {e}")
                continue
            except Exception as e:
                log(f"błąd w {p}: {e!r}")
                continue
            if n:
                nowe += n
                pliki_zmienione += 1
                if not cicho:
                    log(f"+{n:5d}  {_etykieta(p)}")
            _odswiez_blokade()
        conn.execute(
            "INSERT INTO meta(klucz, wartosc) VALUES ('ostatnie_indeksowanie', ?) "
            "ON CONFLICT(klucz) DO UPDATE SET wartosc=excluded.wartosc",
            (datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),),
        )
        if not cicho:
            log(f"gotowe: {nowe} nowych fragmentów z {pliki_zmienione}/{len(pliki)} plików w {time.time() - start:.1f}s")
    finally:
        _zwolnij_blokade()
        if wlasne:
            conn.close()
    return nowe


def przemaskuj(conn: sqlite3.Connection) -> int:
    """Ponownie maskuje wszystkie fragmenty (po zmianie wzorców); zmienione dostają nowe embeddingi."""
    zmienione: list[tuple[int, str]] = []
    for fid, tekst in conn.execute("SELECT id, tekst FROM fragmenty"):
        nowy = maskuj(tekst)
        if nowy != tekst:
            zmienione.append((fid, nowy))
    if not zmienione:
        return 0
    emb = embedduj_passages([t for _, t in zmienione])
    conn.execute("BEGIN IMMEDIATE")
    try:
        for i, (fid, nowy) in enumerate(zmienione):
            conn.execute("INSERT INTO fragmenty_fts(fragmenty_fts, rowid, tekst) SELECT 'delete', id, tekst FROM fragmenty WHERE id=?", (fid,))
            conn.execute("UPDATE fragmenty SET tekst=? WHERE id=?", (nowy, fid))
            conn.execute("INSERT INTO fragmenty_fts(rowid, tekst) VALUES (?,?)", (fid, nowy))
            conn.execute("UPDATE wektory SET emb=? WHERE fragment_id=?", (emb[i].tobytes(), fid))
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise
    log(f"przemaskowano {len(zmienione)} fragmentów")
    return len(zmienione)


def main() -> int:
    conn = polacz()
    try:
        if "--przemaskuj" in sys.argv:
            przemaskuj(conn)
        nowe = indeksuj(conn)
        sesje = conn.execute("SELECT count(DISTINCT sesja) FROM fragmenty").fetchone()[0]
        fragm = conn.execute("SELECT count(*) FROM fragmenty").fetchone()[0]
        log(f"baza: {SCIEZKA_BAZY} | sesji: {sesje} | fragmentów: {fragm} | nowych teraz: {nowe}")
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
