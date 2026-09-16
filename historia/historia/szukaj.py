"""Wyszukiwanie hybrydowe: FTS5 (BM25) + kosinus po wektorach, scalone przez RRF."""

from __future__ import annotations

import re
import sqlite3
import threading

import numpy as np

from .baza import WYMIAR_EMB, embedduj_zapytanie, polacz, ts_na_lokalny

TOP_KANAL = 30
RRF_K = 60
MAX_FRAGMENT = 600

_TOKEN = re.compile(r"\w+", re.UNICODE)


def _zapytanie_fts(q: str) -> str:
    """Zamienia dowolny tekst na bezpieczne zapytanie FTS5: "tok1" OR "tok2" ..."""
    toks = [t for t in _TOKEN.findall(q) if len(t) > 1 or t.isdigit()]
    if not toks:
        return ""
    return " OR ".join(f'"{t}"' for t in toks)


def _warunki(projekt: str | None, od: str | None, do: str | None) -> tuple[str, list]:
    war, par = [], []
    if projekt:
        war.append("f.projekt LIKE ?")
        par.append(f"%{projekt}%")
    if od:
        war.append("f.ts >= ?")
        par.append(od.strip())
    if do:
        d = do.strip()
        if len(d) == 10:
            d += "T23:59:59Z"
        war.append("f.ts <= ?")
        par.append(d)
    return (" AND ".join(war) if war else "1=1"), par


# ---------------------------------------------------------------- cache wektorów

class _CacheWektorow:
    """Cała macierz embeddingów w RAM (skala: dziesiątki tysięcy x 384 float32)."""

    def __init__(self) -> None:
        self.ids = np.zeros(0, dtype=np.int64)
        self.macierz = np.zeros((0, WYMIAR_EMB), dtype=np.float32)
        self._stan: tuple[int, int] = (-1, -1)
        self._lock = threading.Lock()

    def odswiez(self, conn: sqlite3.Connection) -> None:
        r = conn.execute("SELECT count(*), coalesce(max(fragment_id), 0) FROM wektory").fetchone()
        stan = (int(r[0]), int(r[1]))
        if stan == self._stan:
            return
        with self._lock:
            if stan == self._stan:
                return
            rows = conn.execute("SELECT fragment_id, emb FROM wektory ORDER BY fragment_id").fetchall()
            if rows:
                self.ids = np.fromiter((x[0] for x in rows), dtype=np.int64, count=len(rows))
                self.macierz = np.vstack([np.frombuffer(x[1], dtype=np.float32) for x in rows])
            else:
                self.ids = np.zeros(0, dtype=np.int64)
                self.macierz = np.zeros((0, WYMIAR_EMB), dtype=np.float32)
            self._stan = stan


_cache = _CacheWektorow()


# ---------------------------------------------------------------- kanały

def _kanal_fts(conn, q: str, gdzie: str, par: list, limit: int) -> list[int]:
    fq = _zapytanie_fts(q)
    if not fq:
        return []
    rows = conn.execute(
        f"SELECT f.id FROM fragmenty_fts x JOIN fragmenty f ON f.id = x.rowid "
        f"WHERE fragmenty_fts MATCH ? AND {gdzie} ORDER BY bm25(fragmenty_fts) LIMIT ?",
        [fq, *par, limit],
    ).fetchall()
    return [r[0] for r in rows]


def _kanal_wektorowy(conn, q: str, gdzie: str, par: list, limit: int, filtry: bool) -> list[int]:
    _cache.odswiez(conn)
    if len(_cache.ids) == 0:
        return []
    v = embedduj_zapytanie(q)
    ids, m = _cache.ids, _cache.macierz
    if filtry:
        dozw = {r[0] for r in conn.execute(f"SELECT f.id FROM fragmenty f WHERE {gdzie}", par)}
        maska = np.fromiter((i in dozw for i in ids), dtype=bool, count=len(ids))
        if not maska.any():
            return []
        ids, m = ids[maska], m[maska]
    sc = m @ v
    n = min(limit, len(sc))
    top = np.argpartition(-sc, n - 1)[:n]
    top = top[np.argsort(-sc[top])]
    return [int(ids[i]) for i in top]


def _rrf(listy: list[list[int]]) -> list[int]:
    wynik: dict[int, float] = {}
    for lista in listy:
        for r, fid in enumerate(lista):
            wynik[fid] = wynik.get(fid, 0.0) + 1.0 / (RRF_K + r + 1)
    return [fid for fid, _ in sorted(wynik.items(), key=lambda kv: -kv[1])]


# ---------------------------------------------------------------- API

def szukaj(zapytanie: str, projekt: str | None = None, od: str | None = None, do: str | None = None,
           limit: int = 8, conn: sqlite3.Connection | None = None) -> list[dict]:
    wlasne = conn is None
    if wlasne:
        conn = polacz()
    try:
        gdzie, par = _warunki(projekt, od, do)
        filtry = bool(par)
        fts = _kanal_fts(conn, zapytanie, gdzie, par, TOP_KANAL)
        wek = _kanal_wektorowy(conn, zapytanie, gdzie, par, TOP_KANAL, filtry)
        kolejnosc = _rrf([fts, wek])
        if not kolejnosc:
            return []
        wyniki, widziane = [], set()
        for fid in kolejnosc:
            r = conn.execute("SELECT id, projekt, sesja, plik, linia, ts, rola, tekst FROM fragmenty WHERE id=?", (fid,)).fetchone()
            if not r:
                continue
            klucz = (r[3], r[4])  # kawałki tej samej wypowiedzi pokazujemy raz
            if klucz in widziane:
                continue
            widziane.add(klucz)
            wyniki.append({
                "id": r[0],
                "data": ts_na_lokalny(r[5]),
                "projekt": r[1],
                "sesja": r[2][:8],
                "rola": r[6],
                "fragment": r[7][:MAX_FRAGMENT],
                "zrodlo": "fts+wektor" if fid in fts and fid in wek else ("fts" if fid in fts else "wektor"),
            })
            if len(wyniki) >= limit:
                break
        return wyniki
    finally:
        if wlasne:
            conn.close()


def _pelny_tekst(conn, plik: str, linia: int, rola: str) -> str:
    rows = conn.execute(
        "SELECT czesc, tekst FROM fragmenty WHERE plik=? AND linia=? AND rola=? ORDER BY czesc", (plik, linia, rola)
    ).fetchall()
    from .indeksuj import ZAKLADKA
    out = ""
    for cz, t in rows:
        if cz == 0:
            out += ("\n" if out else "") + t
        else:
            out += t[ZAKLADKA:]  # sklejamy kawałki bez powtarzania zakładki
    return out


def kontekst(fragment_id: int, ile: int = 3, conn: sqlite3.Connection | None = None) -> dict:
    wlasne = conn is None
    if wlasne:
        conn = polacz()
    try:
        r = conn.execute("SELECT projekt, sesja, plik, linia FROM fragmenty WHERE id=?", (fragment_id,)).fetchone()
        if not r:
            return {"blad": f"brak fragmentu o id {fragment_id}"}
        projekt, sesja, plik, linia = r
        przed = [x[0] for x in conn.execute(
            "SELECT DISTINCT linia FROM fragmenty WHERE plik=? AND linia<? ORDER BY linia DESC LIMIT ?", (plik, linia, ile))]
        po = [x[0] for x in conn.execute(
            "SELECT DISTINCT linia FROM fragmenty WHERE plik=? AND linia>? ORDER BY linia ASC LIMIT ?", (plik, linia, ile))]
        linie = sorted(przed) + [linia] + po
        wypowiedzi = []
        for ln in linie:
            for fid, ts, rola in conn.execute(
                "SELECT min(id), ts, rola FROM fragmenty WHERE plik=? AND linia=? GROUP BY rola ORDER BY min(id)", (plik, ln)):
                wypowiedzi.append({
                    "id": fid,
                    "data": ts_na_lokalny(ts),
                    "rola": rola,
                    "tekst": _pelny_tekst(conn, plik, ln, rola),
                    "to_ten": ln == linia,
                })
        return {"projekt": projekt, "sesja": sesja, "wypowiedzi": wypowiedzi}
    finally:
        if wlasne:
            conn.close()


def statystyki(conn: sqlite3.Connection | None = None) -> dict:
    wlasne = conn is None
    if wlasne:
        conn = polacz()
    try:
        sesje, fragm = conn.execute("SELECT count(DISTINCT sesja), count(*) FROM fragmenty").fetchone()
        pliki = conn.execute("SELECT count(*) FROM pliki").fetchone()[0]
        per = [
            {"projekt": p, "sesje": s, "fragmenty": n, "ostatnio": ts_na_lokalny(t)}
            for p, s, n, t in conn.execute(
                "SELECT projekt, count(DISTINCT sesja), count(*), max(ts) FROM fragmenty GROUP BY projekt ORDER BY max(ts) DESC")
        ]
        ost = conn.execute("SELECT wartosc FROM meta WHERE klucz='ostatnie_indeksowanie'").fetchone()
        from .baza import SCIEZKA_BAZY
        rozmiar = SCIEZKA_BAZY.stat().st_size if SCIEZKA_BAZY.exists() else 0
        return {
            "sesje": sesje, "fragmenty": fragm, "pliki": pliki,
            "ostatnie_indeksowanie": ts_na_lokalny(ost[0]) if ost else None,
            "baza": str(SCIEZKA_BAZY), "rozmiar_MB": round(rozmiar / 1e6, 1),
            "projekty": per,
        }
    finally:
        if wlasne:
            conn.close()
