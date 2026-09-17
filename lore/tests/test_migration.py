"""Taking over a database left by the previous, Polish-named version of the module.

Everything happens on a throwaway database built here — the real one is never touched.
"""

from __future__ import annotations

import sqlite3

import pytest

from lore import db

# the schema exactly as it was before the rename
LEGACY_SCHEMA = """
CREATE TABLE IF NOT EXISTS pliki (
    sciezka  TEXT PRIMARY KEY,
    mtime    REAL NOT NULL,
    rozmiar  INTEGER NOT NULL,
    offset   INTEGER NOT NULL DEFAULT 0,
    linia    INTEGER NOT NULL DEFAULT 0,
    projekt  TEXT,
    sesja    TEXT
);
CREATE TABLE IF NOT EXISTS fragmenty (
    id      INTEGER PRIMARY KEY,
    projekt TEXT NOT NULL,
    sesja   TEXT NOT NULL,
    plik    TEXT NOT NULL,
    linia   INTEGER NOT NULL,
    czesc   INTEGER NOT NULL DEFAULT 0,
    ts      TEXT NOT NULL,
    rola    TEXT NOT NULL,
    tekst   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_fragmenty_plik ON fragmenty(plik, linia, czesc);
CREATE INDEX IF NOT EXISTS idx_fragmenty_ts ON fragmenty(ts);
CREATE INDEX IF NOT EXISTS idx_fragmenty_projekt ON fragmenty(projekt);
CREATE VIRTUAL TABLE IF NOT EXISTS fragmenty_fts USING fts5(
    tekst,
    content='fragmenty',
    content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);
CREATE TABLE IF NOT EXISTS wektory (
    fragment_id INTEGER PRIMARY KEY REFERENCES fragmenty(id) ON DELETE CASCADE,
    emb         BLOB NOT NULL
);
CREATE TABLE IF NOT EXISTS meta (
    klucz   TEXT PRIMARY KEY,
    wartosc TEXT
);
"""

TS = "2026-09-16T10:00:00.000Z"
ROWS = [
    (1, "projekt-a", "sesja-1", "C:/t/a.jsonl", 1, 0, TS, "rozmowa", "user: are we moving the indexer?"),
    (2, "projekt-a", "sesja-1", "C:/t/a.jsonl", 3, 0, TS, "narzedzie", "[narzedzie: Bash] ls"),
    (3, "projekt-b", "sesja-2", "C:/t/b.jsonl", 1, 0, TS, "agent:wynik", "done"),
]
EMB = b"\x00" * (384 * 4)


def _build_legacy(path) -> None:
    """A small database in the old format, with rows, full-text index and vectors."""
    conn = sqlite3.connect(path, isolation_level=None)
    conn.executescript(LEGACY_SCHEMA)
    for r in ROWS:
        conn.execute("INSERT INTO fragmenty VALUES (?,?,?,?,?,?,?,?,?)", r)
        conn.execute("INSERT INTO fragmenty_fts(rowid, tekst) VALUES (?,?)", (r[0], r[8]))
        conn.execute("INSERT INTO wektory(fragment_id, emb) VALUES (?,?)", (r[0], EMB))
    conn.execute("INSERT INTO pliki VALUES ('C:/t/a.jsonl', 1.0, 10, 5, 2, 'projekt-a', 'sesja-1')")
    conn.execute("INSERT INTO meta VALUES ('ostatnie_indeksowanie', ?)", (TS,))
    conn.close()


@pytest.fixture
def home(tmp_path, monkeypatch):
    """Points the module at a temporary directory instead of ~/.claude."""
    monkeypatch.setattr(db, "DB_PATH", tmp_path / "lore.db")
    return tmp_path


def test_legacy_database_is_moved_not_copied(home):
    _build_legacy(home / "historia.db")

    conn = db.connect()
    conn.close()

    assert (home / "lore.db").exists()
    assert not (home / "historia.db").exists()


def test_rows_survive_the_rename(home):
    _build_legacy(home / "historia.db")

    conn = db.connect()
    try:
        assert conn.execute("SELECT count(*) FROM chunks").fetchone()[0] == len(ROWS)
        assert conn.execute("SELECT project, session, file, line, part, role, text FROM chunks WHERE id=1").fetchone() == (
            "projekt-a", "sesja-1", "C:/t/a.jsonl", 1, 0, "conversation", ROWS[0][8],
        )
        assert [r[0] for r in conn.execute("SELECT role FROM chunks ORDER BY id")] == [
            "conversation", "tool", "agent:result",
        ]
        assert conn.execute("SELECT path, size, line, project FROM files").fetchone() == (
            "C:/t/a.jsonl", 10, 2, "projekt-a",
        )
        assert conn.execute("SELECT chunk_id FROM vectors ORDER BY chunk_id").fetchall() == [(1,), (2,), (3,)]
        assert conn.execute("SELECT value FROM meta WHERE key='last_indexed'").fetchone()[0] == TS
        # the full-text index was rebuilt against the renamed table
        assert [r[0] for r in conn.execute("SELECT rowid FROM chunks_fts WHERE chunks_fts MATCH 'indexer'")] == [1]
    finally:
        conn.close()


def test_migration_runs_twice_without_damage(home):
    _build_legacy(home / "historia.db")

    first = db.connect()
    rows = first.execute("SELECT id, role, text FROM chunks ORDER BY id").fetchall()
    first.close()

    second = db.connect()
    try:
        assert second.execute("SELECT id, role, text FROM chunks ORDER BY id").fetchall() == rows
        assert db.migrate_legacy_names(second) is False  # nothing left to rename
        assert [r[0] for r in second.execute("SELECT rowid FROM chunks_fts WHERE chunks_fts MATCH 'indexer'")] == [1]
    finally:
        second.close()


def test_the_indexing_stamp_is_added_to_an_existing_database_without_losing_a_row(home):
    """53 549 chunks of real memory go through this — not one of them may be lost or re-indexed."""
    _build_legacy(home / "historia.db")

    conn = db.connect()
    try:
        assert conn.execute("SELECT count(*) FROM chunks").fetchone()[0] == len(ROWS)
        assert [r[0] for r in conn.execute("SELECT text FROM chunks ORDER BY id")] == [r[8] for r in ROWS]
        assert "indexed_at" in {r[1] for r in conn.execute("PRAGMA table_info(chunks)")}
    finally:
        conn.close()


def test_the_old_rows_keep_their_own_date_instead_of_looking_freshly_added(home):
    """Stamping them with the moment of the migration would make three years of archive look like
    it arrived today, and the first harvest after the upgrade would read the whole of it."""
    _build_legacy(home / "historia.db")

    conn = db.connect()
    try:
        assert [r[0] for r in conn.execute("SELECT indexed_at FROM chunks ORDER BY id")] == [TS] * len(ROWS)
        assert conn.execute("SELECT count(*) FROM chunks WHERE indexed_at <> ts").fetchone()[0] == 0
    finally:
        conn.close()


def test_adding_the_indexing_stamp_twice_changes_nothing(home):
    _build_legacy(home / "historia.db")

    first = db.connect()
    first.close()

    second = db.connect()
    try:
        assert db.migrate_indexed_at(second) == 0  # nothing left to fill in
        assert [r[0] for r in second.execute("SELECT indexed_at FROM chunks ORDER BY id")] == [TS] * len(ROWS)
    finally:
        second.close()


def test_a_row_written_without_the_stamp_is_filled_in_on_the_next_open(home):
    """A half-finished insert must not leave a chunk with an empty stamp lying around for ever."""
    conn = db.connect()
    conn.execute("INSERT INTO chunks(project, session, file, line, part, ts, role, text) "
                 "VALUES ('p','s','f',1,0,?,'user','bez znacznika')", (TS,))
    conn.close()

    again = db.connect()
    try:
        assert again.execute("SELECT indexed_at FROM chunks").fetchone()[0] == TS
    finally:
        again.close()


def test_fresh_database_needs_no_migration(home):
    conn = db.connect()
    try:
        assert db.migrate_legacy_names(conn) is False
        tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        assert {"chunks", "files", "vectors", "meta", "chunks_fts"} <= tables
        conn.execute("INSERT INTO chunks(project, session, file, line, part, ts, role, text) "
                     "VALUES ('p','s','f',1,0,?,'user','hello')", (TS,))
        assert conn.execute("SELECT count(*) FROM chunks").fetchone()[0] == 1
    finally:
        conn.close()


def test_existing_new_database_wins_over_the_legacy_file(home):
    db.connect().close()  # the new file already exists
    _build_legacy(home / "historia.db")

    conn = db.connect()
    try:
        assert conn.execute("SELECT count(*) FROM chunks").fetchone()[0] == 0
    finally:
        conn.close()
    assert (home / "historia.db").exists()  # the old file is left alone, nothing is lost
