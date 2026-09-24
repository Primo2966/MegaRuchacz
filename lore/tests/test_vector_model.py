"""Changing the embedding model: which model the vectors belong to, the conversion, and search meanwhile.

Every test works on a throwaway database with made-up models — no real model is loaded, nothing
is downloaded. The made-up vectors carry a fingerprint of the model that produced them, so a
vector of the wrong model is visible, not just "a vector".
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import time

import numpy as np
import pytest

from lore import db, index, migrate, search

OLD = "test/old-model"
NEW = "test/new-model"
WIDE = "test/new-wide-model"
DIM = 8
OLD_SPEC = db.EmbedModel(OLD, DIM, "q: ", "p: ", "MEAN", "model.onnx", 1)
NEW_SPEC = db.EmbedModel(NEW, DIM, "zapytanie: ", "", "CLS", "model.onnx", 1)  # SAME size as the old one
WIDE_SPEC = db.EmbedModel(WIDE, 12, "zapytanie: ", "", "CLS", "model.onnx", 1)

NO_FTS_HIT = "qqqzzz"  # matches no chunk in full text: whatever comes back came from the vectors


def e(i: int, dim: int = DIM) -> np.ndarray:
    v = np.zeros(dim, dtype=np.float32)
    v[i] = 1.0
    return v


def fingerprint(model: str, dim: int) -> np.ndarray:
    """What the made-up models embed every passage as: OLD -> e2, NEW/WIDE -> e3."""
    return e(2 if model == OLD else 3, dim)


class Fake:
    """Stand-in for embed_passages / embed_query that records which model was asked for."""

    def __init__(self) -> None:
        self.passages: list[tuple[str, list[str]]] = []
        self.queries: list[str] = []
        self.passage_vector = fingerprint
        self.on_passages = None  # a hook: raise, switch models, ...

    def embed_passages(self, texts, batch=32, model=None):
        model = model or db.EMBED_MODEL
        self.passages.append((model, list(texts)))
        if self.on_passages:
            self.on_passages(model, texts)
        dim = db.model_spec(model).dim
        return np.vstack([self.passage_vector(model, dim) for _ in texts]) if texts else np.zeros((0, dim), np.float32)

    def embed_query(self, query, model=None):
        self.queries.append(model)
        return e(0, db.model_spec(model).dim)

    def embedded(self, model: str) -> list[str]:
        return [t for m, texts in self.passages if m == model for t in texts]


@pytest.fixture
def lore(environment, monkeypatch):
    """A fresh database whose vectors are OLD's, configured for NEW, with fake embedders everywhere."""
    for spec in (OLD_SPEC, NEW_SPEC, WIDE_SPEC):
        monkeypatch.setitem(db.MODELS, spec.name, spec)
    monkeypatch.setattr(db, "EMBED_MODEL", NEW)
    fake = Fake()
    monkeypatch.setattr(migrate, "embed_passages", fake.embed_passages)
    monkeypatch.setattr(index, "embed_passages", fake.embed_passages)
    monkeypatch.setattr(search, "embed_query", fake.embed_query)
    monkeypatch.setattr(search, "_cache", search._VectorCache())
    set_active(environment.conn, OLD)
    environment.fake = fake
    return environment


def set_active(conn, model: str) -> None:
    conn.execute("UPDATE meta SET value=? WHERE key=?", (model, db.META_MODEL))


def add_chunk(conn, text: str, vector: np.ndarray | None, line: int | None = None) -> int:
    """One chunk with its full-text entry and (optionally) its vector, the way the indexer writes them."""
    line = line or (conn.execute("SELECT coalesce(max(line), 0) + 1 FROM chunks").fetchone()[0])
    cid = conn.execute(
        "INSERT INTO chunks(project, session, file, line, part, ts, role, text, indexed_at) VALUES (?,?,?,?,?,?,?,?,?)",
        ("test-project", "s1", "C:/t/s1.jsonl", line, 0, "2026-09-16T10:00:00.000Z", "user", text, "x"),
    ).lastrowid
    conn.execute("INSERT INTO chunks_fts(rowid, text) VALUES (?,?)", (cid, text))
    if vector is not None:
        conn.execute("INSERT INTO vectors(chunk_id, emb) VALUES (?,?)", (cid, np.asarray(vector, np.float32).tobytes()))
    return cid


def stored(conn, table: str = "vectors") -> dict[int, np.ndarray]:
    return {cid: np.frombuffer(emb, dtype=np.float32) for cid, emb in conn.execute(f"SELECT chunk_id, emb FROM {table}")}


def progress() -> dict:
    return json.loads(db.migration_progress_path().read_text(encoding="utf-8"))


def archive(conn, n: int) -> list[int]:
    return [add_chunk(conn, f"ustalenie numer {i} o olejkach", fingerprint(OLD, DIM)) for i in range(n)]


# ---------------------------------------------------------------- which model the database holds

def test_fresh_database_starts_on_the_configured_model_without_conversion(environment):
    conn = environment.conn
    assert db.active_model(conn) == db.EMBED_MODEL == db.MMLW_BASE.name
    assert db.vector_status(conn)["state"] == "ok"
    r = migrate.run(conn=conn)
    assert (r["state"], r["mode"], r["done"], r["total"]) == ("done", "repair", 0, 0)
    assert not db.has_table(conn, db.NEXT_TABLE)


def test_database_from_before_the_record_is_taken_for_e5_and_reported(tmp_path, monkeypatch, capsys):
    """An existing install has chunks and 384-float vectors, but no record of the model."""
    path = tmp_path / "old-install.db"
    raw = __import__("sqlite3").connect(path)
    raw.executescript(db.SCHEMA)
    raw.execute("INSERT INTO chunks(project, session, file, line, ts, role, text) VALUES ('p','s','f',1,'t','user','x')")
    raw.execute("INSERT INTO vectors(chunk_id, emb) VALUES (1, ?)", (np.zeros(384, np.float32).tobytes(),))
    raw.commit()
    raw.close()
    monkeypatch.setattr(db, "DB_PATH", path)
    conn = db.connect()
    try:
        assert db.active_model(conn) == db.E5_SMALL.name
        err = capsys.readouterr().err
        assert "WARNING" in err and "configured for sdadas/mmlw-retrieval-roberta-base" in err
        st = search.stats(conn)["vectors"]
        assert st["state"] == "migration_needed" and st["vectors"] == 1 and "lore.migrate" in st["warning"]
    finally:
        conn.close()


def test_unknown_model_in_the_database_is_reported_and_search_falls_back_to_full_text(lore, capsys):
    conn = lore.conn
    hit = add_chunk(conn, "klucze do Allegro leza w pliku env", e(0))
    set_active(conn, "somebody/unknown-model")
    st = db.vector_status(conn)
    assert st["state"] == "unknown_model" and "semantic search is OFF" in st["warning"]
    results = search.search("klucze Allegro", conn=conn)
    assert [r["id"] for r in results] == [hit] and results[0]["source"] == "fts"
    assert lore.fake.queries == []  # no query was embedded with a model the vectors do not belong to
    assert "unknown model" in capsys.readouterr().err


# ---------------------------------------------------------------- search during the conversion

def test_new_vectors_never_enter_the_ranking_before_the_switch(lore):
    """Break attempt: the new model's vectors are built so that each would win against the query —
    if they leaked into the ranking during the conversion, every chunk would tie for first place."""
    conn = lore.conn
    a = add_chunk(conn, "pierwszy", e(0))   # the only OLD vector pointing at the query
    b = add_chunk(conn, "drugi", e(2))
    c = add_chunk(conn, "trzeci", e(4))
    lore.fake.passage_vector = lambda model, dim: e(0, dim)  # every NEW vector = the query direction
    calls = []

    def stop_after_two(model, texts):
        calls.append(model)
        if len(calls) == 3:
            raise KeyboardInterrupt

    lore.fake.on_passages = stop_after_two
    with pytest.raises(KeyboardInterrupt):
        migrate.run(conn=conn, batch=1)
    assert sorted(stored(conn, db.NEXT_TABLE)) == [a, b]  # half-way: two new vectors wait aside

    results = search.search(NO_FTS_HIT, conn=conn)
    snap = search._cache.snapshot
    assert snap.model == OLD and sorted(snap.ids.tolist()) == [a, b, c]  # three rows, not five
    assert np.array_equal(snap.matrix[list(snap.ids).index(b)], e(2))   # b's OLD vector, not the new one
    assert results[0]["id"] == a
    assert search._vector_channel(conn, NO_FTS_HIT, "1=1", [], 3, False)[0] == a
    assert set(lore.fake.queries) == {OLD}  # the query was embedded with the model of those vectors

    lore.fake.on_passages = None
    assert migrate.run(conn=conn, batch=1)["state"] == "done"
    search.search(NO_FTS_HIT, conn=conn)
    snap = search._cache.snapshot
    assert snap.model == NEW and lore.fake.queries[-1] == NEW
    assert all(np.array_equal(v, e(0)) for v in snap.matrix)  # now only the new ones


def test_search_works_throughout_the_conversion(lore):
    conn = lore.conn
    ids = archive(conn, 5)
    seen = []

    def search_meanwhile(model, texts):
        # full text AND vectors answer at every stage of the conversion
        r = search.search("olejkach", conn=conn, limit=10)
        seen.append((len(r), {x["source"] for x in r}))

    lore.fake.on_passages = search_meanwhile
    migrate.run(conn=conn, batch=2)
    assert len(seen) == 3 and all(n == 5 and src == {"fts+vector"} for n, src in seen)
    assert {x["id"] for x in search.search("olejkach", conn=conn, limit=10)} == set(ids)


# ---------------------------------------------------------------- interruption and resume

def test_interrupted_conversion_resumes_where_it_stopped(lore):
    conn = lore.conn
    ids = archive(conn, 10)
    batches = []

    def power_cut(model, texts):
        batches.append(list(texts))
        if len(batches) == 3:
            raise KeyboardInterrupt  # the computer switched off during the third batch

    lore.fake.on_passages = power_cut
    with pytest.raises(KeyboardInterrupt):
        migrate.run(conn=conn, batch=3)
    p = progress()
    assert (p["state"], p["done"], p["total"], p["from"], p["to"]) == ("interrupted", 6, 10, OLD, NEW)
    assert db.active_model(conn) == OLD  # nothing switched: search still has all ten OLD vectors
    assert len(stored(conn)) == 10 and all(np.array_equal(v, fingerprint(OLD, DIM)) for v in stored(conn).values())
    first_run = {t for b in batches[:2] for t in b}

    lore.fake.on_passages = None
    lore.fake.passages.clear()
    r = migrate.run(conn=conn, batch=3)
    second_run = set(lore.fake.embedded(NEW))
    assert len(second_run) == 4 and not (second_run & first_run)  # only the rest, nothing twice
    assert (r["state"], r["done"], r["total"]) == ("done", 10, 10)
    assert db.active_model(conn) == NEW and db._meta(conn, db.META_NEXT) is None
    assert not db.has_table(conn, db.NEXT_TABLE)
    assert sorted(stored(conn)) == ids and all(np.array_equal(v, fingerprint(NEW, DIM)) for v in stored(conn).values())
    assert progress()["state"] == "done"


def test_a_dead_conversion_is_reported_as_stale(lore):
    conn = lore.conn
    archive(conn, 2)
    lore.fake.on_passages = lambda model, texts: (_ for _ in ()).throw(KeyboardInterrupt)
    with pytest.raises(KeyboardInterrupt):
        migrate.run(conn=conn, batch=1)
    # a hard kill leaves "running" behind — simulate that, with the heartbeat an hour old
    p = db.migration_progress_path()
    data = progress()
    data["state"] = "running"
    p.write_text(json.dumps(data), encoding="utf-8")
    old = time.time() - 3600
    os.utime(p, (old, old))
    got = db.vector_status(conn)["progress"]
    assert got["stale"] is True and "resumes where it stopped" in got["message"]


def dead_pid() -> int:
    """The pid of a process that has just finished."""
    p = subprocess.Popen([sys.executable, "-c", "pass"])
    p.wait()
    return p.pid


def test_a_hard_killed_conversion_is_reported_at_once_and_resumes_at_once(lore):
    conn = lore.conn
    archive(conn, 3)
    # what a power cut leaves behind: a fresh "running" file and a lock, both of a process that is gone
    pid = dead_pid()
    db.migration_progress_path().write_text(json.dumps({"state": "running", "pid": pid, "done": 1, "total": 3}),
                                            encoding="utf-8")
    migrate.lock_path().write_text(str(pid))
    got = db.vector_status(conn)["progress"]
    assert got["stale"] is True and f"process {pid} is gone" in got["message"]
    assert migrate.run(conn=conn)["state"] == "done"  # not "busy" for the next 15 minutes


def test_second_conversion_at_the_same_time_is_refused(lore):
    conn = lore.conn
    archive(conn, 1)
    migrate.lock_path().write_text(str(os.getpid()))  # a live process holds it
    assert migrate.run(conn=conn)["state"] == "busy"
    assert db.active_model(conn) == OLD and not db.has_table(conn, db.NEXT_TABLE)


# ---------------------------------------------------------------- the indexer meanwhile

def test_chunks_indexed_during_the_conversion_get_converted_before_the_switch(lore):
    conn = lore.conn
    archive(conn, 4)
    state = {"indexed": False}

    def new_conversation_arrives(model, texts):
        if model == NEW and not state["indexed"]:
            state["indexed"] = True
            p = lore.transcript(("user", "nowa rozmowa w trakcie przeliczania " * 90))
            assert lore.index(p) >= 1

    lore.fake.on_passages = new_conversation_arrives
    migrate.run(conn=conn, batch=2)
    total = conn.execute("SELECT count(*) FROM chunks").fetchone()[0]
    assert total > 4
    # the indexer embedded the new chunk with the model active at that time (OLD) ...
    assert any("nowa rozmowa" in t for t in lore.fake.embedded(OLD))
    # ... and the conversion caught it before switching: every chunk has a NEW vector
    vecs = stored(conn)
    assert len(vecs) == total and all(np.array_equal(v, fingerprint(NEW, DIM)) for v in vecs.values())


def test_switch_waits_for_a_chunk_that_arrived_at_the_last_moment(lore, monkeypatch):
    """Break attempt: the indexer adds a chunk between the last "nothing left" and the switch."""
    conn = lore.conn
    archive(conn, 3)
    real_pending = migrate._pending
    late = {}

    def pending(conn_, mode, dim, after, batch):
        rows = real_pending(conn_, mode, dim, after, batch)
        if not rows and after == 0 and not late:
            late["id"] = add_chunk(conn, "spozniony fragment", fingerprint(OLD, DIM))
        return rows

    monkeypatch.setattr(migrate, "_pending", pending)
    r = migrate.run(conn=conn, batch=2)
    assert r["state"] == "done" and "spozniony fragment" in lore.fake.embedded(NEW)
    vecs = stored(conn)
    assert late["id"] in vecs and np.array_equal(vecs[late["id"]], fingerprint(NEW, DIM))
    assert len(vecs) == 4 and all(np.array_equal(v, fingerprint(NEW, DIM)) for v in vecs.values())


def test_indexer_racing_the_switch_does_not_leave_old_vectors_behind(lore):
    """Break attempt: the indexer embeds with OLD, the conversion switches to NEW before it writes."""
    conn = lore.conn
    archive(conn, 2)
    other = {"switched": False}

    def switch_behind_its_back(model, texts):
        if model == OLD and not other["switched"]:
            other["switched"] = True
            assert migrate.run()["state"] == "done"  # another process, own connection

    lore.fake.on_passages = switch_behind_its_back
    p = lore.transcript(("user", "rozmowa, ktora trafia na przelaczenie modelu " * 60))
    assert lore.index(p) >= 1
    assert db.active_model(conn) == NEW
    vecs = stored(conn)
    assert len(vecs) == conn.execute("SELECT count(*) FROM chunks").fetchone()[0]
    assert all(np.array_equal(v, fingerprint(NEW, DIM)) for v in vecs.values())


def test_vector_of_the_wrong_size_is_excluded_reported_and_repaired(lore, monkeypatch, capsys):
    """An old process still running the previous model writes an 8-float vector into a 12-float database."""
    conn = lore.conn
    monkeypatch.setattr(db, "EMBED_MODEL", WIDE)
    set_active(conn, WIDE)
    good = add_chunk(conn, "dobry", e(0, 12))
    bad = add_chunk(conn, "zly", e(0, DIM))
    results = search.search(NO_FTS_HIT, conn=conn)
    assert [r["id"] for r in results] == [good]
    assert "not 12-dimensional" in capsys.readouterr().err
    st = db.vector_status(conn)
    assert (st["state"], st["vectors_wrong_size"]) == ("incomplete", 1)
    r = migrate.run(conn=conn)
    assert (r["mode"], r["state"]) == ("repair", "done")
    assert lore.fake.embedded(WIDE) == ["zly"]
    assert len(stored(conn)[bad]) == 12 and db.vector_status(conn)["state"] == "ok"


def test_remask_during_the_conversion_drops_the_stale_new_vector(lore, monkeypatch):
    conn = lore.conn
    cid = add_chunk(conn, "tekst", fingerprint(OLD, DIM))
    migrate._prepare_conversion(conn, NEW)
    conn.execute(f"INSERT INTO {db.NEXT_TABLE}(chunk_id, emb) VALUES (?,?)", (cid, fingerprint(NEW, DIM).tobytes()))
    monkeypatch.setattr(index, "mask", lambda t: t + " [zamaskowane]")
    assert index.remask(conn) == 1
    assert cid not in stored(conn, db.NEXT_TABLE)  # a new vector of the OLD text would be wrong


# ---------------------------------------------------------------- the download

def _pinned(tmp_path, monkeypatch, content: bytes):
    monkeypatch.setattr(db, "MODELS_DIR", tmp_path / "models")
    spec = db.EmbedModel("test/pinned", DIM, "", "", "CLS", "onnx/model.onnx", 1, source="someone/export",
                         revision="abc", files=(("onnx/model.onnx", hashlib.sha256(b"the checked file").hexdigest()),))
    calls = []

    def fake_download(repo, rel, revision=None, local_dir=None):
        calls.append((repo, rel, revision))
        target = os.path.join(local_dir, rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as f:
            f.write(content)
        return target

    monkeypatch.setattr("huggingface_hub.hf_hub_download", fake_download)
    return spec, calls


def test_pinned_download_is_checked_and_remembered(tmp_path, monkeypatch):
    spec, calls = _pinned(tmp_path, monkeypatch, b"the checked file")
    d = db.fetch_pinned(spec)
    assert calls == [("someone/export", "onnx/model.onnx", "abc")] and (d / ".verified.json").exists()
    db.fetch_pinned(spec)
    assert len(calls) == 1  # a warm start does not touch the network
    (d / "onnx" / "model.onnx").write_bytes(b"damaged on disk")
    db.fetch_pinned(spec)
    assert len(calls) == 2 and (d / "onnx" / "model.onnx").read_bytes() == b"the checked file"


def test_download_with_a_different_file_is_refused(tmp_path, monkeypatch):
    spec, _ = _pinned(tmp_path, monkeypatch, b"something else entirely")
    with pytest.raises(db.ModelUnavailable, match="refused and removed"):
        db.fetch_pinned(spec)
    assert not (db.MODELS_DIR / "test--pinned" / "onnx" / "model.onnx").exists()


def test_no_network_leaves_the_old_model_working(lore, tmp_path, monkeypatch):
    """The real embed_passages, the real download path — and no network. The conversion must stop
    loudly, and the database must stay exactly as it was, still searchable."""
    conn = lore.conn
    ids = archive(conn, 3)
    add_chunk(conn, "klucze do Allegro", e(0))
    monkeypatch.setattr(db, "MODELS_DIR", tmp_path / "models")
    monkeypatch.setattr(db, "_models", {})
    pinned = db.EmbedModel(NEW, DIM, "zapytanie: ", "", "CLS", "onnx/model.onnx", 496, source="someone/export",
                           revision="abc", files=(("onnx/model.onnx", "0" * 64),))
    monkeypatch.setitem(db.MODELS, NEW, pinned)
    monkeypatch.setattr(migrate, "embed_passages", db.embed_passages)

    def offline(*a, **k):
        raise OSError("[WinError 10051] network is unreachable")

    monkeypatch.setattr("huggingface_hub.hf_hub_download", offline)
    with pytest.raises(db.ModelUnavailable, match="cannot download"):
        migrate.run(conn=conn)
    p = progress()
    assert p["state"] == "error" and "cannot download" in p["message"] and "network is unreachable" in p["message"]
    assert db.active_model(conn) == OLD and len(stored(conn)) == 4
    assert len(stored(conn, db.NEXT_TABLE)) == 0
    r = search.search("klucze Allegro", conn=conn)
    assert r and r[0]["source"] == "fts+vector" and set(lore.fake.queries) == {OLD}
    assert set(ids) <= {x["id"] for x in search.search("olejkach", conn=conn, limit=10)}
