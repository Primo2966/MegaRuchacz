"""Baza wpisow: SQLite (wpisy + FTS5 + wektory 768) i wyszukiwanie hybrydowe z filtrem uprawnien.

Filtr uprawnien jest JEDNYM warunkiem SQL (`warunek_uprawnien`) dokladanym do obu kanalow
(pelnotekstowego i wektorowego) - wpis spoza uprawnien nie wchodzi do rankingu w ogole, wiec nie ma
czego "odfiltrowac pozniej". Ten sam warunek wycina wpisy usuniete (usuniety IS NOT NULL).

Wpis ma kilka tematow (od 0.3.0, tabela `wpisy_tematy`, dokladnie jeden glowny = `wpisy.temat`).
Widocznosc: tematy zwykle dzialaja na LUB (wystarczy jeden), tematy z osobnym uprawnieniem na I (trzeba
kazdego), a poziom poufnosci wpisu musi miescic sie w uprawnieniu w temacie, przez ktory osoba wpis widzi.

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
-- od 0.3.0: wszystkie tematy wpisu; glowny = wpisy.temat (trzymany w obu miejscach, zmieniany razem)
CREATE TABLE IF NOT EXISTS wpisy_tematy (
    wpis_id  INTEGER NOT NULL REFERENCES wpisy(id),
    temat_id TEXT NOT NULL,
    glowny   INTEGER NOT NULL DEFAULT 0 CHECK (glowny IN (0, 1)),
    PRIMARY KEY (wpis_id, temat_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_wpisy_tematy_glowny ON wpisy_tematy(wpis_id) WHERE glowny = 1;
CREATE INDEX IF NOT EXISTS idx_wpisy_tematy_temat ON wpisy_tematy(temat_id);
"""

META_MODEL = "model_wektorow"
META_SCHEMAT = "wersja_schematu"
WERSJA_SCHEMATU = 2  # 1 = 0.1-0.2 (jeden temat w wpisy.temat), 2 = 0.3 (wpisy_tematy)
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
    tematy_dodatkowe: tuple[str, ...] = ()  # poza glownym `temat`; bez powtorzen i bez glownego


@dataclass
class WynikDodania:
    dodane: list[int] = field(default_factory=list)
    duplikaty: int = 0           # ta sama tresc w tym samym temacie juz jest
    usuniete_wczesniej: int = 0  # byla i zostala usunieta - nie wraca
    zamaskowane: int = 0         # w tresci byl sekret, zamieniony na [MASKED]
    uwagi: list[str] = field(default_factory=list)


def sprawdz_tematy_dodatkowe(glowny: str, dodatkowe: tuple[str, ...] | list[str], znane_tematy: set[str],
                             opis: str) -> None:
    """Tematy dodatkowe: znane, bez powtorzen i bez tematu glownego. Blad = BladWpisu (odmowa calosci)."""
    widziane: set[str] = set()
    for t in dodatkowe:
        if t == glowny:
            raise BladWpisu(f"{opis}: temat glowny {t!r} powtorzony w tematach dodatkowych")
        if t in widziane:
            raise BladWpisu(f"{opis}: temat dodatkowy {t!r} powtorzony")
        if t not in znane_tematy:
            raise BladWpisu(f"{opis}: nieznany temat dodatkowy {t!r} (znane: {', '.join(sorted(znane_tematy)) or 'brak'})")
        widziane.add(t)


def teraz() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


_MA_TEMAT = "EXISTS (SELECT 1 FROM wpisy_tematy wt WHERE wt.wpis_id = w.id AND {})"
_NIE_MA_TEMATU = "NOT EXISTS (SELECT 1 FROM wpisy_tematy wt WHERE wt.wpis_id = w.id AND {})"


def _wsrod(kolumna: str, zbior: frozenset[str] | set[str]) -> tuple[str, list]:
    """`kolumna IN (...)`; pusty zbior = falsz (stala, bez polegania na `IN ()`)."""
    if not zbior:
        return "0", []
    return f"{kolumna} IN ({', '.join('?' * len(zbior))})", sorted(zbior)


def warunek_uprawnien(upr: Uprawnienia, temat: str | None = None,
                      zwykle: frozenset[str] | set[str] = frozenset()) -> tuple[str, list] | None:
    """Warunek SQL na alias `w` (tabela wpisy): tylko zywe wpisy, ktore osoba moze widziec.
    None = osoba nie widzi niczego (wtedy nie ma po co pytac bazy).

    `zwykle` = id tematow BEZ osobnego uprawnienia. Kazdy inny temat (tez nieznany i caly zbior, gdy listy
    tematow nie da sie odczytac) liczy sie jak temat z osobnym uprawnieniem - blad listy zaweza, nie poszerza.
    Wpis jest widoczny, gdy jednoczesnie:
      - kazdy jego temat specjalny osoba ma do poziomu >= poufnosc wpisu (I),
      - osoba ma do poziomu >= poufnosc ktorykolwiek z jego tematow zwyklych (LUB), a gdy wpis nie ma
        zwyklych - ktorykolwiek temat w ogole (wpis bez tematow nie jest widoczny dla nikogo poza adminem),
      - przy `temat`: ten temat jest wsrod tematow wpisu i osoba widzi wpis przez niego.
    """
    if upr.admin:
        if temat:
            return "w.usuniety IS NULL AND " + _MA_TEMAT.format("wt.temat_id = ?"), [temat]
        return "w.usuniety IS NULL", []
    czesci, d_args = [], []
    for t, najwyzszy in sorted(upr.tematy.items()):
        poziomy = poziomy_do(najwyzszy)
        if not poziomy:
            continue
        czesci.append(f"(wt.temat_id = ? AND w.poufnosc IN ({', '.join('?' * len(poziomy))}))")
        d_args += [t, *poziomy]
    if not czesci:
        return None
    if temat and not upr.poziomy(temat):
        return None
    d = "(" + " OR ".join(czesci) + ")"  # osoba widzi wpis przez temat wiersza wt
    zw, zw_args = _wsrod("wt.temat_id", zwykle)
    sql = ("w.usuniety IS NULL"
           f" AND {_NIE_MA_TEMATU.format(f'NOT ({zw}) AND NOT {d}')}"
           f" AND ({_MA_TEMAT.format(f'({zw}) AND {d}')}"
           f" OR ({_NIE_MA_TEMATU.format(f'({zw})')} AND {_MA_TEMAT.format(d)}))")
    args = [*zw_args, *d_args, *zw_args, *d_args, *zw_args, *d_args]
    if temat:
        sql += " AND " + _MA_TEMAT.format(f"wt.temat_id = ? AND {d}")
        args += [temat, *d_args]
    return sql, args


def _wszystkie_zywe(temat: str | None) -> tuple[str, list]:
    if temat:
        return "w.usuniety IS NULL AND " + _MA_TEMAT.format("wt.temat_id = ?"), [temat]
    return "w.usuniety IS NULL", []


def temat_podpowiedzi(upr: Uprawnienia, tematy_wpisu: list[str], poufnosc: str,
                      zwykle: frozenset[str] | set[str]) -> str | None:
    """Temat do podpowiedzi "poproś admina" dla wpisu, ktorego osoba NIE widzi (tematy_wpisu: glowny pierwszy).

    None = wpis ma temat z osobnym uprawnieniem, do ktorego osoba nie ma zadnego dostepu - jego nazwy
    nie zdradzamy (podpowiedz bez nazwy). Inaczej temat, ktory blokuje: specjalny ze zbyt niskim poziomem,
    zwykly ze zbyt niskim poziomem, a gdy zadnego nie ma - pierwszy zwykly (glowny, jesli zwykly).
    """
    specjalne = [t for t in tematy_wpisu if t not in zwykle]
    if any(not upr.poziomy(t) for t in specjalne):
        return None
    for t in specjalne:
        if not upr.widzi(t, poufnosc):
            return t
    zwykle_wpisu = [t for t in tematy_wpisu if t in zwykle]
    for t in zwykle_wpisu:
        if upr.poziomy(t):
            return t
    return zwykle_wpisu[0] if zwykle_wpisu else None


class Baza:
    def __init__(self, sciezka: Path, wektoryzator: Wektoryzator | None) -> None:
        self.sciezka = Path(sciezka)
        self.wektoryzator = wektoryzator
        self._zamek_zapisu = threading.Lock()
        self.kopia_migracji = self._kopia_przed_migracja()  # zanim SCHEMAT cokolwiek doda
        with closing(self.polacz()) as conn:
            conn.executescript(SCHEMAT)
        self._migruj()

    # ------------------------------------------------------------ schemat

    @staticmethod
    def _wersja_schematu(conn: sqlite3.Connection) -> int:
        r = conn.execute("SELECT wartosc FROM meta WHERE klucz = ?", (META_SCHEMAT,)).fetchone()
        return int(r[0]) if r else 1

    def kopia(self, opis: str) -> Path:
        """Kopia calej bazy obok niej (API backup SQLite - spojna takze przy WAL). Blad = wyjatek, nie cisza."""
        znacznik = datetime.now().strftime("%Y%m%d-%H%M%S")
        cel = self.sciezka.with_name(f"{self.sciezka.name}.kopia-{opis}-{znacznik}")
        n = 1
        while cel.exists():
            n += 1
            cel = self.sciezka.with_name(f"{self.sciezka.name}.kopia-{opis}-{znacznik}-{n}")
        with closing(self.polacz()) as zrodlo, closing(sqlite3.connect(cel)) as kopia:
            zrodlo.backup(kopia)
        return cel

    def _kopia_przed_migracja(self) -> Path | None:
        """Kopia istniejacej bazy w starym schemacie, ktora ma wpisy - przed jakakolwiek zmiana. Inaczej None."""
        if not self.sciezka.exists():
            return None
        with closing(self.polacz()) as conn:
            tabele = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
            if "wpisy" not in tabele or ("meta" in tabele and self._wersja_schematu(conn) >= WERSJA_SCHEMATU):
                return None
            if not conn.execute("SELECT COUNT(*) FROM wpisy").fetchone()[0]:
                return None
        kopia = self.kopia(f"przed-schematem-{WERSJA_SCHEMATU}")
        log(f"baza {self.sciezka} w starym schemacie - kopia przed migracja: {kopia}")
        return kopia

    def _migruj(self) -> None:
        """Schemat 1 -> 2: kazdy wpis dostaje w wpisy_tematy swoj dotychczasowy temat jako glowny.

        Idempotentna (wersja w `meta`; druga migracja nic nie robi). Kopie robi wczesniej _kopia_przed_migracja.
        Calosc w jednej transakcji z kontrola na koncu - nieudana migracja to wyjatek i wpisy_tematy bez zmian.
        """
        with closing(self.polacz()) as conn:
            if self._wersja_schematu(conn) >= WERSJA_SCHEMATU:
                bez = conn.execute("SELECT COUNT(*) FROM wpisy w WHERE NOT EXISTS (SELECT 1 FROM wpisy_tematy wt "
                                   "WHERE wt.wpis_id = w.id AND wt.glowny = 1)").fetchone()[0]
                if bez:
                    log(f"UWAGA baza {self.sciezka}: {bez} wpisow bez tematu glownego w wpisy_tematy - "
                        "widzi je tylko admin (python -m wiedza_firmy.eksport, potem ustaw_tematy)")
                return
            wpisow = conn.execute("SELECT COUNT(*) FROM wpisy").fetchone()[0]
        with self._zamek_zapisu, closing(self.polacz()) as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                if self._wersja_schematu(conn) < WERSJA_SCHEMATU:  # inny proces mogl zdazyc przed nami
                    conn.execute("INSERT INTO wpisy_tematy (wpis_id, temat_id, glowny) SELECT w.id, w.temat, 1 "
                                 "FROM wpisy w WHERE NOT EXISTS (SELECT 1 FROM wpisy_tematy wt WHERE wt.wpis_id = w.id)")
                    zle = conn.execute("SELECT COUNT(*) FROM wpisy w WHERE NOT EXISTS (SELECT 1 FROM wpisy_tematy wt "
                                       "WHERE wt.wpis_id = w.id AND wt.glowny = 1 AND wt.temat_id = w.temat)").fetchone()[0]
                    if zle:
                        raise RuntimeError(f"migracja {self.sciezka}: {zle} wpisow bez tematu glownego po migracji - "
                                           "wycofuje, baza bez zmian")
                    conn.execute("INSERT INTO meta (klucz, wartosc) VALUES (?, ?) ON CONFLICT(klucz) DO UPDATE SET "
                                 "wartosc = excluded.wartosc", (META_SCHEMAT, str(WERSJA_SCHEMATU)))
                conn.execute("COMMIT")
            except BaseException:
                conn.execute("ROLLBACK")
                raise
        if wpisow:
            log(f"baza zmigrowana do schematu {WERSJA_SCHEMATU} (wiele tematow na wpis): {wpisow} wpisow, "
                "dotychczasowy temat = glowny")

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
            sprawdz_tematy_dodatkowe(w.temat, w.tematy_dodatkowe, znane_tematy, opis)
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
                                   w.zrodlo.strip(), w.program.strip(), tuple(w.tematy_dodatkowe)))

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
                    conn.executemany("INSERT INTO wpisy_tematy (wpis_id, temat_id, glowny) VALUES (?, ?, ?)",
                                     [(wid, w.temat, 1), *((wid, t, 0) for t in w.tematy_dodatkowe)])
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

    @staticmethod
    def _tematy_wpisu(conn: sqlite3.Connection, wid: int) -> list[tuple[str, bool]]:
        """[(temat_id, glowny)], glowny pierwszy, reszta alfabetycznie."""
        return [(t, bool(g)) for t, g in conn.execute(
            "SELECT temat_id, glowny FROM wpisy_tematy WHERE wpis_id = ? ORDER BY glowny DESC, temat_id", (wid,))]

    def szukaj(self, pytanie: str, upr: Uprawnienia, temat: str | None = None, limit: int = 8,
               zwykle: frozenset[str] | set[str] = frozenset()) -> dict:
        """{'wyniki': [wiersze], 'ukryte': [(temat | None, poufnosc)], 'uwagi': [...]}.

        `wyniki` pochodza WYLACZNIE z wpisow przepuszczonych przez warunek_uprawnien w SQL; kazdy ma
        `tematy` = WSZYSTKIE tematy wpisu [(id, glowny)] - co z nich pokazac pytajacemu, decyduje wiedza.py.
        `zwykle` = tematy bez osobnego uprawnienia (warunek_uprawnien; pusty = wszystkie licza sie jak specjalne).
        `ukryte` to tylko temat i poziom (nigdy tresc) wpisow spoza uprawnien, ktore pasuja do pytania
        slowami (kanal pelnotekstowy) i bylyby w pierwszych `limit` przy pelnym dostepie - z nich
        powstaje podpowiedz "poproś admina". Temat None = blokuje temat z osobnym uprawnieniem, ktorego
        osoba nie ma wcale (nazwy nie zdradzamy). Osoba bez zadnych uprawnien nie dostaje nawet tego.
        Oba kanaly ida przez prog trafnosci (`_ranking`): nic ponad progiem = pusta lista.
        """
        uwagi: list[str] = []
        widoczne = warunek_uprawnien(upr, temat, zwykle)
        with closing(self.polacz()) as conn:
            wektor = self._wektor_pytania(conn, pytanie, uwagi)
            wyniki: list[dict] = []
            if widoczne is not None:
                kolejnosc, _ = self._ranking(conn, pytanie, wektor, widoczne, limit)
                for wid in kolejnosc:
                    r = conn.execute("SELECT id, tresc, temat, poufnosc, autor, data_ustalenia, zrodlo, program "
                                     "FROM wpisy WHERE id = ?", (wid,)).fetchone()
                    wiersz = dict(zip(("id", "tresc", "temat", "poufnosc", "autor", "data_ustalenia",
                                       "zrodlo", "program"), r))
                    wiersz["tematy"] = self._tematy_wpisu(conn, wid)
                    wyniki.append(wiersz)
            ukryte: list[tuple[str | None, str]] = []
            if not upr.admin and not upr.puste:
                # ten sam ranking i prog co wyzej, tylko przy pelnym dostepie: podpowiedz "poproś admina"
                # pada tylko dla wpisu, ktory bylby wynikiem - nie dla szumu ponizej progu
                pelny, trafione = self._ranking(conn, pytanie, wektor, _wszystkie_zywe(temat), limit)
                pokazane = {w["id"] for w in wyniki}
                for wid in pelny:
                    if wid not in trafione or wid in pokazane:
                        continue
                    if widoczne is not None:  # widocznosc rozstrzyga ten sam warunek SQL, nie jego kopia w Pythonie
                        sql, args = widoczne
                        if conn.execute(f"SELECT 1 FROM wpisy w WHERE w.id = ? AND {sql}", [wid, *args]).fetchone():
                            continue
                    p = conn.execute("SELECT poufnosc FROM wpisy WHERE id = ?", (wid,)).fetchone()[0]
                    t = temat_podpowiedzi(upr, [t for t, _ in self._tematy_wpisu(conn, wid)], p, zwykle)
                    if (t, p) not in ukryte:
                        ukryte.append((t, p))
        return {"wyniki": wyniki, "ukryte": ukryte, "uwagi": uwagi}

    # ------------------------------------------------------------ eksport i przeklasyfikowanie (CLI)

    def wpisy_z_tematami(self, ids: list[int] | None = None, z_usunietymi: bool = False) -> dict[int, dict]:
        """id -> wiersz wpisu + `tematy` [(id, glowny)], po id rosnaco. Tylko dla CLI na serwerze (bez uprawnien)."""
        pola = ("id", "tresc", "temat", "poufnosc", "autor", "data_ustalenia", "zrodlo", "program", "usuniety")
        warunek, args = ("1", []) if z_usunietymi else ("usuniety IS NULL", [])
        if ids is not None:
            warunek += f" AND id IN ({', '.join('?' * len(ids))})" if ids else " AND 0"
            args = [*args, *ids]
        with closing(self.polacz()) as conn:
            wynik = {}
            for r in conn.execute(f"SELECT {', '.join(pola)} FROM wpisy WHERE {warunek} ORDER BY id", args):
                wiersz = dict(zip(pola, r))
                wiersz["tematy"] = self._tematy_wpisu(conn, r[0])
                wynik[r[0]] = wiersz
        return wynik

    def ustaw_tematy(self, nowe: dict[int, tuple[str, tuple[str, ...]]], znane_tematy: set[str]) -> int:
        """Podmienia liste tematow wpisow: id -> (glowny, dodatkowe). Tresci nie rusza. Jedna transakcja:
        nieznane id, nieznany temat albo zle dodatkowe = BladWpisu i nic nie zmienione. Zwraca liczbe wpisow."""
        for wid, (glowny, dodatkowe) in nowe.items():
            if glowny not in znane_tematy:
                raise BladWpisu(f"wpis {wid}: nieznany temat {glowny!r}")
            sprawdz_tematy_dodatkowe(glowny, dodatkowe, znane_tematy, f"wpis {wid}")
        with self._zamek_zapisu, closing(self.polacz()) as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                for wid, (glowny, dodatkowe) in nowe.items():
                    if conn.execute("SELECT 1 FROM wpisy WHERE id = ?", (wid,)).fetchone() is None:
                        raise BladWpisu(f"nie ma wpisu {wid}")
                    conn.execute("DELETE FROM wpisy_tematy WHERE wpis_id = ?", (wid,))
                    conn.executemany("INSERT INTO wpisy_tematy (wpis_id, temat_id, glowny) VALUES (?, ?, ?)",
                                     [(wid, glowny, 1), *((wid, t, 0) for t in dodatkowe)])
                    conn.execute("UPDATE wpisy SET temat = ? WHERE id = ?", (glowny, wid))
                conn.execute("COMMIT")
            except BaseException:
                conn.execute("ROLLBACK")
                raise
        return len(nowe)

    def statystyka(self) -> dict:
        with closing(self.polacz()) as conn:
            zywe = conn.execute("SELECT COUNT(*) FROM wpisy WHERE usuniety IS NULL").fetchone()[0]
            usuniete = conn.execute("SELECT COUNT(*) FROM wpisy WHERE usuniety IS NOT NULL").fetchone()[0]
            bez_wektora = conn.execute("SELECT COUNT(*) FROM wpisy w LEFT JOIN wektory v ON v.wpis_id = w.id "
                                       "WHERE v.wpis_id IS NULL AND w.usuniety IS NULL").fetchone()[0]
            r = conn.execute("SELECT wartosc FROM meta WHERE klucz = ?", (META_MODEL,)).fetchone()
        return {"wpisy": zywe, "usuniete": usuniete, "bez_wektora": bez_wektora, "model": r[0] if r else None}
