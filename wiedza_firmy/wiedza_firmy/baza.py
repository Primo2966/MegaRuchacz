"""Baza wpisow: SQLite (wpisy + FTS5 + wektory 768) i wyszukiwanie hybrydowe z filtrem uprawnien.

Filtr uprawnien jest JEDNYM warunkiem SQL (`warunek_uprawnien`) dokladanym do obu kanalow
(pelnotekstowego i wektorowego) - wpis spoza uprawnien nie wchodzi do rankingu w ogole, wiec nie ma
czego "odfiltrowac pozniej". Ten sam warunek wycina wpisy usuniete (usuniety IS NOT NULL).

Usuniecie jest miekkie: wiersz zostaje (kto, kiedy, dlaczego), znika tylko z wynikow. Ponowny import
tej samej tresci w tym samym temacie go nie wskrzesza.
"""

from __future__ import annotations

import re
import sqlite3
import threading
from contextlib import closing
from dataclasses import dataclass, field
from datetime import date, datetime, timezone
from pathlib import Path

import numpy as np

from .pliki import log
from .uprawnienia import POZIOMY, TAJNE, Uprawnienia, poziomy_do
from .wektory import ModelNiedostepny, Wektoryzator

NA_KANAL = 30  # tyle najlepszych z kazdego kanalu idzie do RRF (jak w Lore)

SCHEMAT = """
CREATE TABLE IF NOT EXISTS wpisy (
    id              INTEGER PRIMARY KEY,
    tresc           TEXT NOT NULL,
    temat           TEXT NOT NULL,
    poufnosc        TEXT NOT NULL CHECK (poufnosc IN ('jawne', 'wewnetrzne', 'wrazliwe')),
    autor           TEXT NOT NULL,
    data_ustalenia  TEXT NOT NULL,
    zrodlo          TEXT NOT NULL DEFAULT '',
    program         TEXT NOT NULL DEFAULT '',
    dodano          TEXT NOT NULL,
    dodal           TEXT NOT NULL DEFAULT '',
    -- miekkie usuniecie: NULL = wpis zywy; slad (kto, dlaczego) zostaje
    usuniety        TEXT,
    usunal          TEXT,
    powod_usuniecia TEXT
);
CREATE INDEX IF NOT EXISTS idx_wpisy_temat ON wpisy(temat, poufnosc);
CREATE VIRTUAL TABLE IF NOT EXISTS wpisy_fts USING fts5(
    tresc,
    content='wpisy',
    content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);
CREATE TABLE IF NOT EXISTS wektory (
    wpis_id INTEGER PRIMARY KEY REFERENCES wpisy(id),
    emb     BLOB NOT NULL
);
CREATE TABLE IF NOT EXISTS meta (
    klucz   TEXT PRIMARY KEY,
    wartosc TEXT
);
"""

META_MODEL = "model_wektorow"
_DATA = re.compile(r"^\d{4}-\d{2}-\d{2}$")


class BladWpisu(ValueError):
    """Wpis nie moze powstac - komunikat mowi, co poprawic. Zadnego zapisu polowy partii."""


@dataclass
class NowyWpis:
    tresc: str
    temat: str
    poufnosc: str
    autor: str
    data_ustalenia: str
    zrodlo: str = ""
    program: str = ""


@dataclass
class WynikDodania:
    dodane: list[int] = field(default_factory=list)
    duplikaty: int = 0           # ta sama tresc w tym samym temacie juz jest
    usuniete_wczesniej: int = 0  # byla i zostala usunieta - nie wraca
    zamaskowane: int = 0         # w tresci byl sekret, zamieniony na [MASKED]
    uwagi: list[str] = field(default_factory=list)


def teraz() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def warunek_uprawnien(upr: Uprawnienia, temat: str | None = None) -> tuple[str, list] | None:
    """Warunek SQL na alias `w` (tabela wpisy): tylko zywe wpisy, ktore osoba moze widziec.
    None = osoba nie widzi niczego (wtedy nie ma po co pytac bazy)."""
    if upr.admin:
        if temat:
            return "w.usuniety IS NULL AND w.temat = ?", [temat]
        return "w.usuniety IS NULL", []
    czesci, args = [], []
    for t, najwyzszy in sorted(upr.tematy.items()):
        if temat and t != temat:
            continue
        poziomy = poziomy_do(najwyzszy)
        if not poziomy:
            continue
        czesci.append(f"(w.temat = ? AND w.poufnosc IN ({', '.join('?' * len(poziomy))}))")
        args += [t, *poziomy]
    if not czesci:
        return None
    return "w.usuniety IS NULL AND (" + " OR ".join(czesci) + ")", args


def _wszystkie_zywe(temat: str | None) -> tuple[str, list]:
    if temat:
        return "w.usuniety IS NULL AND w.temat = ?", [temat]
    return "w.usuniety IS NULL", []


class Baza:
    def __init__(self, sciezka: Path, wektoryzator: Wektoryzator | None) -> None:
        self.sciezka = Path(sciezka)
        self.wektoryzator = wektoryzator
        self._zamek_zapisu = threading.Lock()
        with closing(self.polacz()) as conn:
            conn.executescript(SCHEMAT)

    def polacz(self) -> sqlite3.Connection:
        self.sciezka.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(self.sciezka, timeout=60, isolation_level=None)
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA synchronous=NORMAL")
        conn.execute("PRAGMA foreign_keys=ON")
        return conn

    # ------------------------------------------------------------ zapis

    def dodaj(self, wpisy: list[NowyWpis], dodal: str, znane_tematy: set[str]) -> WynikDodania:
        """Dodaje partie wpisow. Najpierw kontrola CALEJ partii - jeden zly wpis = odmowa wszystkich."""
        from lore.masking import mask

        wynik = WynikDodania()
        gotowe: list[NowyWpis] = []
        for nr, w in enumerate(wpisy, 1):
            opis = f"wpis {nr} ({w.tresc[:40]!r})"
            if not w.tresc or not w.tresc.strip():
                raise BladWpisu(f"{opis}: pusta tresc")
            if w.poufnosc == TAJNE:
                raise BladWpisu(f"{opis}: poufnosc tajne - takie rzeczy nie trafiaja do bazy (wytnij je z wpisu)")
            if w.poufnosc not in POZIOMY:
                raise BladWpisu(f"{opis}: poufnosc {w.poufnosc!r} - dozwolone: {', '.join(POZIOMY)}")
            if w.temat not in znane_tematy:
                raise BladWpisu(f"{opis}: nieznany temat {w.temat!r} (znane: {', '.join(sorted(znane_tematy)) or 'brak - wczytaj tematy'})")
            if not w.autor or not w.autor.strip():
                raise BladWpisu(f"{opis}: brak autora")
            if not _DATA.match(w.data_ustalenia or ""):
                raise BladWpisu(f"{opis}: data ustalenia {w.data_ustalenia!r} - format RRRR-MM-DD")
            try:
                date.fromisoformat(w.data_ustalenia)
            except ValueError as e:
                raise BladWpisu(f"{opis}: data ustalenia {w.data_ustalenia!r} nie istnieje") from e
            tresc = mask(w.tresc.strip())
            if tresc != w.tresc.strip():
                wynik.zamaskowane += 1
            gotowe.append(NowyWpis(tresc, w.temat, w.poufnosc, w.autor.strip(), w.data_ustalenia,
                                   w.zrodlo.strip(), w.program.strip()))

        with self._zamek_zapisu, closing(self.polacz()) as conn:
            nowe: list[NowyWpis] = []
            for w in gotowe:
                byl = conn.execute("SELECT usuniety FROM wpisy WHERE tresc = ? AND temat = ? "
                                   "ORDER BY usuniety IS NULL DESC LIMIT 1", (w.tresc, w.temat)).fetchone()
                if byl is None and not any(n.tresc == w.tresc and n.temat == w.temat for n in nowe):
                    nowe.append(w)
                elif byl is not None and byl[0] is not None:
                    wynik.usuniete_wczesniej += 1
                else:
                    wynik.duplikaty += 1
            wektory = None
            if nowe and self.wektoryzator is not None:
                try:
                    wektory = self.wektoryzator.pasaze([w.tresc for w in nowe])
                except ModelNiedostepny as e:
                    wynik.uwagi.append(f"wpisy zapisane BEZ wektorow (szuka je tylko pelny tekst), model niedostepny: {e}")
            elif nowe:
                wynik.uwagi.append("wpisy zapisane BEZ wektorow - serwer pracuje bez modelu")
            kiedy = teraz()
            conn.execute("BEGIN IMMEDIATE")
            try:
                for i, w in enumerate(nowe):
                    cur = conn.execute(
                        "INSERT INTO wpisy (tresc, temat, poufnosc, autor, data_ustalenia, zrodlo, program, dodano, dodal) "
                        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                        (w.tresc, w.temat, w.poufnosc, w.autor, w.data_ustalenia, w.zrodlo, w.program, kiedy, dodal))
                    wid = cur.lastrowid
                    conn.execute("INSERT INTO wpisy_fts (rowid, tresc) VALUES (?, ?)", (wid, w.tresc))
                    if wektory is not None:
                        conn.execute("INSERT INTO wektory (wpis_id, emb) VALUES (?, ?)",
                                     (wid, np.asarray(wektory[i], dtype=np.float32).tobytes()))
                    wynik.dodane.append(wid)
                if wektory is not None and nowe:
                    self._ustaw_model(conn)
                conn.execute("COMMIT")
            except BaseException:
                conn.execute("ROLLBACK")
                raise
        return wynik

    def _ustaw_model(self, conn: sqlite3.Connection) -> None:
        conn.execute("INSERT INTO meta (klucz, wartosc) VALUES (?, ?) ON CONFLICT(klucz) DO UPDATE SET wartosc = excluded.wartosc",
                     (META_MODEL, self.wektoryzator.model))

    def usun(self, wpis_id: int, powod: str, kto: str) -> str:
        """'usuniety' | 'nie_ma' | 'juz_usuniety'. Powod obowiazkowy - to slad dla nastepnych."""
        if not powod or not powod.strip():
            raise BladWpisu("podaj powod usuniecia - zostaje w sladzie")
        with self._zamek_zapisu, closing(self.polacz()) as conn:
            r = conn.execute("SELECT usuniety FROM wpisy WHERE id = ?", (wpis_id,)).fetchone()
            if r is None:
                return "nie_ma"
            if r[0] is not None:
                return "juz_usuniety"
            conn.execute("UPDATE wpisy SET usuniety = ?, usunal = ?, powod_usuniecia = ? WHERE id = ?",
                         (teraz(), kto, powod.strip(), wpis_id))
            return "usuniety"

    def uzupelnij_wektory(self) -> int:
        """Liczy brakujace wektory zywych wpisow; wektory innego modelu liczy od nowa. Zwraca liczbe."""
        if self.wektoryzator is None:
            return 0
        with self._zamek_zapisu, closing(self.polacz()) as conn:
            r = conn.execute("SELECT wartosc FROM meta WHERE klucz = ?", (META_MODEL,)).fetchone()
            if r is not None and r[0] != self.wektoryzator.model:
                log(f"wektory w bazie sa z modelu {r[0]}, serwer ma {self.wektoryzator.model} - licze wszystkie od nowa")
                conn.execute("DELETE FROM wektory")
            braki = conn.execute("SELECT w.id, w.tresc FROM wpisy w LEFT JOIN wektory v ON v.wpis_id = w.id "
                                 "WHERE v.wpis_id IS NULL AND w.usuniety IS NULL ORDER BY w.id").fetchall()
            if not braki:
                if r is None and conn.execute("SELECT 1 FROM wektory LIMIT 1").fetchone():
                    self._ustaw_model(conn)
                return 0
            wektory = self.wektoryzator.pasaze([t for _, t in braki])
            conn.execute("BEGIN IMMEDIATE")
            try:
                for (wid, _), v in zip(braki, wektory):
                    conn.execute("INSERT OR REPLACE INTO wektory (wpis_id, emb) VALUES (?, ?)",
                                 (wid, np.asarray(v, dtype=np.float32).tobytes()))
                self._ustaw_model(conn)
                conn.execute("COMMIT")
            except BaseException:
                conn.execute("ROLLBACK")
                raise
            return len(braki)

    # ------------------------------------------------------------ odczyt

    def _kanal_fts(self, conn: sqlite3.Connection, pytanie: str, warunek: tuple[str, list], ile: int) -> list[int]:
        from lore.search import _fts_query

        q = _fts_query(pytanie)
        if not q:
            return []
        sql, args = warunek
        return [r[0] for r in conn.execute(
            f"SELECT w.id FROM wpisy_fts JOIN wpisy w ON w.id = wpisy_fts.rowid "
            f"WHERE wpisy_fts MATCH ? AND {sql} ORDER BY bm25(wpisy_fts) LIMIT ?", [q, *args, ile])]

    def _podobienstwa(self, conn: sqlite3.Connection, wektor: np.ndarray | None,
                      warunek: tuple[str, list]) -> tuple[list[int], np.ndarray]:
        """(id, podobienstwo kosinusowe) pytania do kazdego widocznego wpisu z wektorem (wektory sa znormalizowane)."""
        pusto = ([], np.zeros(0, dtype=np.float32))
        if wektor is None:
            return pusto
        sql, args = warunek
        wiersze = conn.execute(f"SELECT v.wpis_id, v.emb FROM wektory v JOIN wpisy w ON w.id = v.wpis_id WHERE {sql}",
                               args).fetchall()
        if not wiersze:
            return pusto
        macierz = np.vstack([np.frombuffer(e, dtype=np.float32) for _, e in wiersze])
        if macierz.shape[1] != wektor.shape[0]:
            return pusto
        return [w[0] for w in wiersze], macierz @ wektor

    def _prog(self) -> float | None:
        """Prog trafnosci modelu (wektory.PROGI_TRAFNOSCI); None = model bez progu, wyniki bez odciecia."""
        return getattr(self.wektoryzator, "prog_trafnosci", None)

    def _ranking(self, conn: sqlite3.Connection, pytanie: str, wektor: np.ndarray | None,
                 warunek: tuple[str, list], limit: int) -> tuple[list[int], set[int]]:
        """(kolejnosc RRF obu kanalow po progu trafnosci, id trafione slowami).

        Prog dziala na podobienstwie kosinusowym, w OBU kanalach: wpis ponizej progu odpada takze wtedy,
        gdy pasuje slowem - zapytanie pelnotekstowe to "slowo1 OR slowo2 ...", wiec samo "jak" albo "do"
        lapie polowe bazy. Wpis bez wektora (dodany bez modelu) nie ma czym byc oceniony - zostaje, jesli
        trafil slowami. Bez wektora pytania (model niedostepny) - bez progu, jak w kroku 1.
        """
        from lore.search import _rrf

        slowami = self._kanal_fts(conn, pytanie, warunek, NA_KANAL)
        ids, podobienstwo = self._podobienstwa(conn, wektor, warunek)
        znaczeniem = [ids[i] for i in np.argsort(-podobienstwo)[:NA_KANAL]]
        prog = self._prog() if wektor is not None else None
        if prog is not None:
            sim = dict(zip(ids, podobienstwo.tolist()))
            slowami = [i for i in slowami if i not in sim or sim[i] >= prog]
            znaczeniem = [i for i in znaczeniem if sim[i] >= prog]
        return _rrf([slowami, znaczeniem])[:limit], set(slowami)

    def _wektor_pytania(self, conn: sqlite3.Connection, pytanie: str, uwagi: list[str]) -> np.ndarray | None:
        if self.wektoryzator is None:
            uwagi.append("serwer pracuje bez modelu - wyszukiwanie tylko pelnotekstowe")
            return None
        r = conn.execute("SELECT wartosc FROM meta WHERE klucz = ?", (META_MODEL,)).fetchone()
        if r is not None and r[0] != self.wektoryzator.model:
            uwagi.append(f"wektory w bazie sa z modelu {r[0]}, a serwer ma {self.wektoryzator.model} - "
                         "wyszukiwanie tylko pelnotekstowe do czasu przeliczenia")
            return None
        try:
            return np.asarray(self.wektoryzator.pytanie(pytanie), dtype=np.float32)
        except ModelNiedostepny as e:
            uwagi.append(f"model niedostepny - wyszukiwanie tylko pelnotekstowe: {e}")
            return None

    def szukaj(self, pytanie: str, upr: Uprawnienia, temat: str | None = None, limit: int = 8) -> dict:
        """{'wyniki': [wiersze], 'ukryte': [(temat, poufnosc)], 'uwagi': [...]}.

        `wyniki` pochodza WYLACZNIE z wpisow przepuszczonych przez warunek_uprawnien w SQL.
        `ukryte` to tylko temat i poziom (nigdy tresc) wpisow spoza uprawnien, ktore pasuja do pytania
        slowami (kanal pelnotekstowy) i bylyby w pierwszych `limit` przy pelnym dostepie - z nich
        powstaje podpowiedz "poproś admina". Osoba bez zadnych uprawnien nie dostaje nawet tego.
        Oba kanaly ida przez prog trafnosci (`_ranking`): nic ponad progiem = pusta lista.
        """
        uwagi: list[str] = []
        widoczne = warunek_uprawnien(upr, temat)
        with closing(self.polacz()) as conn:
            wektor = self._wektor_pytania(conn, pytanie, uwagi)
            wyniki: list[dict] = []
            if widoczne is not None:
                kolejnosc, _ = self._ranking(conn, pytanie, wektor, widoczne, limit)
                for wid in kolejnosc:
                    r = conn.execute("SELECT id, tresc, temat, poufnosc, autor, data_ustalenia, zrodlo, program "
                                     "FROM wpisy WHERE id = ?", (wid,)).fetchone()
                    wyniki.append(dict(zip(("id", "tresc", "temat", "poufnosc", "autor", "data_ustalenia",
                                            "zrodlo", "program"), r)))
            ukryte: list[tuple[str, str]] = []
            if not upr.admin and not upr.puste:
                # ten sam ranking i prog co wyzej, tylko przy pelnym dostepie: podpowiedz "poproś admina"
                # pada tylko dla wpisu, ktory bylby wynikiem - nie dla szumu ponizej progu
                pelny, trafione = self._ranking(conn, pytanie, wektor, _wszystkie_zywe(temat), limit)
                for wid in pelny:
                    if wid not in trafione:
                        continue
                    t, p = conn.execute("SELECT temat, poufnosc FROM wpisy WHERE id = ?", (wid,)).fetchone()
                    if not upr.widzi(t, p) and (t, p) not in ukryte:
                        ukryte.append((t, p))
        return {"wyniki": wyniki, "ukryte": ukryte, "uwagi": uwagi}

    def statystyka(self) -> dict:
        with closing(self.polacz()) as conn:
            zywe = conn.execute("SELECT COUNT(*) FROM wpisy WHERE usuniety IS NULL").fetchone()[0]
            usuniete = conn.execute("SELECT COUNT(*) FROM wpisy WHERE usuniety IS NOT NULL").fetchone()[0]
            bez_wektora = conn.execute("SELECT COUNT(*) FROM wpisy w LEFT JOIN wektory v ON v.wpis_id = w.id "
                                       "WHERE v.wpis_id IS NULL AND w.usuniety IS NULL").fetchone()[0]
            r = conn.execute("SELECT wartosc FROM meta WHERE klucz = ?", (META_MODEL,)).fetchone()
        return {"wpisy": zywe, "usuniete": usuniete, "bez_wektora": bez_wektora, "model": r[0] if r else None}
