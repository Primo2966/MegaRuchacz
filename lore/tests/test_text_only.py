"""Full text only: the indexer of a machine with the knowledge module but without the lore module.

The text-only pass must never reach for the embedding model (no load, no 496 MB download), must
say so in the database (meta index_mode), and vector_status must read the missing vectors as a
chosen state - not as the "incomplete" alarm. Switching lore back on gives the chunks their vectors.
Every model call in here is a trap: touching it fails the test.
"""

from __future__ import annotations

import os
import sys
import time

import numpy as np
import pytest

from lore import db, index, migrate

LONG = "x" * 2000  # longer than a chunk - its own, closed group, stored at once
LONG_AGO = 48 * 60 * 60


def _trap(*args, **kwargs):
    raise AssertionError("the embedding model was reached in the text-only mode")


@pytest.fixture
def no_model(monkeypatch):
    """Any way to the model ends the test - the direct one and the lazy loader under it."""
    monkeypatch.setattr(index, "embed_passages", _trap)
    monkeypatch.setattr(db, "embedding_model", _trap)
    monkeypatch.setattr(db, "_load_model", _trap)


def _closed_transcript(environment, *turns):
    p = environment.transcript(*turns)
    old = time.time() - LONG_AGO
    os.utime(p, (old, old))  # the tail is closed - everything goes in now
    return p


def _vectors(conn) -> int:
    return conn.execute("SELECT count(*) FROM vectors").fetchone()[0]


def test_text_only_pass_stores_chunks_without_vectors_and_never_touches_the_model(environment, no_model):
    _closed_transcript(environment, ("user", "Jak ustawilismy API Allegro?"), ("assistant", "Przez klucz w sekretach."))

    new = index.index(environment.conn, quiet=True, text_only=True)

    assert new == 1
    assert _vectors(environment.conn) == 0
    hit = environment.conn.execute("SELECT count(*) FROM chunks_fts WHERE chunks_fts MATCH 'allegro'").fetchone()[0]
    assert hit == 1  # full text finds it at once
    assert db.index_mode(environment.conn) == db.INDEX_TEXT


def test_vector_status_names_text_only_as_a_state_not_an_alarm(environment, no_model):
    _closed_transcript(environment, ("user", "pierwsza rzecz"), ("assistant", LONG))
    index.index(environment.conn, quiet=True, text_only=True)

    s = db.vector_status(environment.conn)

    assert s["state"] == "text_only"
    assert "warning" not in s  # a false alarm would teach to ignore the real ones
    assert s["missing"] == s["chunks"] > 0
    assert "lore" in s["note"] and "semantic search is off" in s["note"]


def test_the_same_database_without_the_mode_is_still_an_alarm(environment):
    """Negative check: missing vectors in the NORMAL mode stay "incomplete" with a warning."""
    _closed_transcript(environment, ("user", "druga rzecz"), ("assistant", LONG))
    index.index(environment.conn, quiet=True, text_only=True)
    db.record_index_mode(environment.conn, False)  # somebody indexes the normal way again

    s = db.vector_status(environment.conn)

    assert s["state"] == "incomplete"
    assert "lore.migrate" in s["warning"]


def test_text_only_silences_the_model_mismatch_warning(environment, monkeypatch, no_model):
    environment.conn.execute("UPDATE meta SET value='intfloat/multilingual-e5-small' WHERE key=?", (db.META_MODEL,))
    db.record_index_mode(environment.conn, True)
    said = []
    monkeypatch.setattr(db, "log", lambda *a: said.append(" ".join(str(x) for x in a)))
    monkeypatch.setattr(db, "_warned", set())

    db.warn_on_model_mismatch(environment.conn)
    assert said == []
    assert db.vector_status(environment.conn)["state"] == "text_only"

    db.record_index_mode(environment.conn, False)  # back to vectors: the old model IS a problem again
    db.warn_on_model_mismatch(environment.conn)
    assert said and "WARNING" in said[0]


def test_switching_lore_on_records_vectors_and_migrate_fills_the_text_only_chunks(environment, monkeypatch, no_model):
    _closed_transcript(environment, ("user", "trzecia rzecz"), ("assistant", LONG))
    index.index(environment.conn, quiet=True, text_only=True)
    assert _vectors(environment.conn) == 0

    dim = db.model_spec().dim
    monkeypatch.setattr(migrate, "embed_passages",
                        lambda texts, batch=32, model=None: np.ones((len(texts), dim), dtype=np.float32))
    db.record_index_mode(environment.conn, False)  # what the first normal pass after installing lore does
    assert db.vector_status(environment.conn)["state"] == "incomplete"

    result = migrate.run(environment.conn, batch=8)  # lock and progress file sit next to the test database

    assert result["state"] == "done"
    s = db.vector_status(environment.conn)
    assert s["state"] == "ok"
    assert _vectors(environment.conn) == s["chunks"]


class _Conn:
    """The test database behind a connection whose close() main() may call - the fixture closes it."""

    def __init__(self, real):
        self.real = real

    def execute(self, *args):
        return self.real.execute(*args)

    def close(self):
        pass


def test_main_reads_the_flag(environment, monkeypatch):
    seen = []

    def fake_index(conn=None, quiet=False, text_only=False):
        seen.append(text_only)
        return 0

    monkeypatch.setattr(index, "index", fake_index)
    monkeypatch.setattr(index, "connect", lambda: _Conn(environment.conn))
    monkeypatch.setattr(sys, "argv", ["lore.index", "--text-only"])
    index.main()
    monkeypatch.setattr(sys, "argv", ["lore.index"])
    index.main()

    assert seen == [True, False]


def test_remask_in_text_only_drops_stale_vectors_and_never_embeds(environment, no_model):
    _closed_transcript(environment, ("user", "jak ustawic polaczenie z baza"), ("assistant", LONG))
    index.index(environment.conn, quiet=True, text_only=True)
    cid = environment.conn.execute("SELECT id FROM chunks ORDER BY id LIMIT 1").fetchone()[0]
    # a vector left from the time lore was on, and a text stored before its masking pattern existed
    environment.conn.execute("INSERT INTO vectors(chunk_id, emb) VALUES (?, ?)",
                             (cid, np.zeros(db.model_spec().dim, dtype=np.float32).tobytes()))
    environment.conn.execute("INSERT INTO chunks_fts(chunks_fts, rowid, text) SELECT 'delete', id, text FROM chunks WHERE id=?", (cid,))
    environment.conn.execute("UPDATE chunks SET text = text || ' password=TAJNEHASLO123' WHERE id=?", (cid,))
    environment.conn.execute("INSERT INTO chunks_fts(rowid, text) SELECT id, text FROM chunks WHERE id=?", (cid,))

    changed = index.remask(environment.conn, text_only=True)

    assert changed == 1
    text = environment.conn.execute("SELECT text FROM chunks WHERE id=?", (cid,)).fetchone()[0]
    assert "TAJNEHASLO123" not in text
    # the old vector still encoded the unmasked password - it must not survive the remask
    assert environment.conn.execute("SELECT count(*) FROM vectors WHERE chunk_id=?", (cid,)).fetchone()[0] == 0
