"""Digging through the whole archive: what counts as a repetition, what gets read and what is skipped."""

from __future__ import annotations

import itertools
import json
import sqlite3

import numpy as np
import pytest

from lore import db, facts, mining

_LINE = itertools.count(1)


@pytest.fixture
def archive(tmp_path, monkeypatch, environment):
    """The whole dig inside tmp_path — neither the real archive nor the real knowledge is touched."""
    knowledge = tmp_path / "wiedza"
    monkeypatch.setattr(facts, "KNOWLEDGE_DIR", knowledge)
    monkeypatch.setattr(facts, "MARKER_PATH", knowledge / ".ostatnie-wyciaganie")
    monkeypatch.setattr(facts, "CANDIDATES_PATH", knowledge / "kandydaci.md")
    monkeypatch.setattr(facts, "RULES_PATH", tmp_path / "CLAUDE.md")
    monkeypatch.setattr(mining, "DB_PATH", tmp_path / "lore.db")
    return environment


# ---------------------------------------------------------------- artificial vectors

def unit(v: np.ndarray) -> np.ndarray:
    return (v / np.linalg.norm(v)).astype(np.float32)


def direction(seed: int) -> np.ndarray:
    """A unit vector standing for one topic. Two random directions in 384 dimensions are
    practically orthogonal, so separate topics never fall into one cluster by accident."""
    return unit(np.random.default_rng(seed).standard_normal(db.EMBED_DIM))


def near(base: np.ndarray, spread: float = 0.1, seed: int = 0) -> np.ndarray:
    """The same thing said in other words: a small step off the topic, well inside the threshold."""
    return unit(base + spread * direction(seed + 10_000))


def sideways(base: np.ndarray, step: float, seed: int) -> np.ndarray:
    """A step exactly across the topic — for a cluster with a known middle and known edges."""
    off = direction(seed + 20_000)
    return unit(base + step * unit(off - float(off @ base) * base))


# ---------------------------------------------------------------- material in the database

def long_text(label: str) -> str:
    """Anything below MIN_CHARS is noise and gets dropped, so the test texts look like real ones."""
    return f"{label} — ustalenie, ktore uzytkownik tlumaczyl juz w niejednym oknie, bo wracalo w kolko"


def add(archive, text: str, session: str, ts: str, vector: np.ndarray, role: str = "user") -> int:
    """One chunk with its vector, stored exactly the way the indexer stores them."""
    cur = archive.conn.execute(
        "INSERT INTO chunks(project, session, file, line, part, ts, role, text) VALUES (?,?,?,?,?,?,?,?)",
        ("test-project", session, f"{session}.jsonl", next(_LINE), 0, ts, role, text),
    )
    archive.conn.execute("INSERT INTO vectors(chunk_id, emb) VALUES (?,?)",
                         (cur.lastrowid, np.asarray(vector, dtype=np.float32).tobytes()))
    return int(cur.lastrowid)


def stamp(month: str = "09", day: int = 11) -> str:
    return f"2026-{month}-{day:02d}T10:00:00.000Z"


def repeated(archive, seed: int, sessions: list[str], months: list[str] | None = None,
             label: str = "temat") -> np.ndarray:
    """One topic said once in each of the given sessions — a cluster the vectors find by themselves."""
    base = direction(seed)
    months = months or ["09"] * len(sessions)
    for i, (session, month) in enumerate(zip(sessions, months)):
        add(archive, long_text(f"{label} {i}"), session, stamp(month, 11 + i),
            near(base, seed=seed * 100 + i))
    return base


def clusters_of(archive) -> list[mining.Cluster]:
    chunks, matrix = mining.load(archive.conn)
    return mining.describe(mining.cluster(matrix), chunks, matrix)


# ---------------------------------------------------------------- stand-ins for the model

def answer(*items: dict):
    """The model's envelope, exactly as facts.parse_facts reads it — no network, no `claude`."""
    envelope = json.dumps({"type": "result", "structured_output": {"fakty": list(items)}})
    return lambda material: envelope


def durable(text: str) -> dict:
    return {"tresc": text, "warstwa": "stala", "podsekcja": "projekty"}


def recorder(seen: list[str]):
    """Writes down what it was given and returns nothing — for checking what would be paid for."""
    return lambda material: seen.append(material) or ""


def forbidden(material: str) -> str:
    raise AssertionError("the model must not be called here")


# ---------------------------------------------------------------- the session criterion

def test_a_cluster_living_in_one_session_is_rejected(archive):
    repeated(archive, seed=1, sessions=["jedna-sesja"] * 5)

    assert len(mining.cluster(mining.load(archive.conn)[1])) == 1  # the vectors do see one cluster
    assert clusters_of(archive) == []  # one long discussion is not knowledge repeated to new windows


def test_a_cluster_from_three_sessions_is_taken(archive):
    repeated(archive, seed=2, sessions=["okno-a", "okno-b", "okno-c"])

    found = clusters_of(archive)

    assert len(found) == 1
    assert found[0].sessions == 3


def test_two_sessions_are_not_enough(archive):
    repeated(archive, seed=3, sessions=["okno-a", "okno-b", "okno-a", "okno-b"])

    assert clusters_of(archive) == []


def test_separate_topics_do_not_melt_into_one_cluster(archive):
    repeated(archive, seed=4, sessions=["a", "b", "c"], label="pierwszy")
    repeated(archive, seed=5, sessions=["d", "e", "f"], label="drugi")

    assert len(clusters_of(archive)) == 2


# ---------------------------------------------------------------- the representative

def test_the_representative_comes_from_the_middle_not_from_the_seed(archive):
    base = direction(6)
    add(archive, long_text("BRZEG lewy"), "okno-a", stamp(), sideways(base, 0.2, seed=6))
    add(archive, long_text("SRODEK"), "okno-b", stamp(), base)
    add(archive, long_text("BRZEG prawy"), "okno-c", stamp(), sideways(base, -0.2, seed=6))

    chunks, matrix = mining.load(archive.conn)
    found = mining.describe(mining.cluster(matrix), chunks, matrix)

    assert len(found) == 1
    assert chunks[found[0].members[0]].text.startswith("BRZEG lewy")  # the seed sits on the edge
    assert chunks[found[0].representative].text.startswith("SRODEK")


# ---------------------------------------------------------------- strength of the repetition

def test_clusters_are_sorted_by_sessions_then_by_the_spread_over_months(archive):
    repeated(archive, seed=7, sessions=["a1", "a2", "a3", "a4", "a5"], label="piec-sesji")
    repeated(archive, seed=8, sessions=["b1", "b2", "b3"], months=["03", "06", "09"], label="pol-roku")
    repeated(archive, seed=9, sessions=["c1", "c2", "c3"], label="jeden-tydzien")

    found = clusters_of(archive)

    assert [(c.sessions, c.months) for c in found] == [(5, 1), (3, 3), (3, 1)]


def test_the_month_span_of_a_cluster_is_counted(archive):
    repeated(archive, seed=10, sessions=["a", "b", "c"], months=["01", "01", "07"])

    found = clusters_of(archive)

    assert (found[0].months, found[0].first_ts[:7], found[0].last_ts[:7]) == (2, "2026-01", "2026-07")


# ---------------------------------------------------------------- noise

def test_tool_calls_and_their_output_are_not_clustered(archive):
    base = direction(11)
    for i, role in enumerate(("tool", "result", "agent:tool", "agent:result")):
        add(archive, long_text(f"wywolanie {i}"), f"okno-{i}", stamp(), near(base, seed=1100 + i),
            role=role)

    assert mining.load(archive.conn)[0] == []


def test_short_chunks_are_not_clustered(archive):
    base = direction(12)
    for i in range(4):
        add(archive, "ok, dalej", f"okno-{i}", stamp(), near(base, seed=1200 + i))

    assert mining.load(archive.conn)[0] == []


# ---------------------------------------------------------------- counting in batches

def test_batching_gives_the_same_clusters_as_one_big_batch():
    matrix = np.vstack([near(direction(seed), seed=seed * 10 + i)
                        for seed in range(40) for i in range(5)])

    small = mining.cluster(matrix, batch=7)
    big = mining.cluster(matrix, batch=10_000)

    assert small == big
    assert len(small) == 40
    assert sorted(len(g) for g in small) == [5] * 40


def test_a_batch_bigger_than_the_archive_does_not_break(archive):
    repeated(archive, seed=13, sessions=["a", "b", "c"])

    chunks, matrix = mining.load(archive.conn)

    assert len(mining.cluster(matrix, batch=mining.BATCH)) == 1
    assert len(chunks) == 3


def test_an_empty_archive_gives_nothing(archive):
    chunks, matrix = mining.load(archive.conn)

    assert (chunks, matrix.shape) == ([], (0, db.EMBED_DIM))
    assert mining.cluster(matrix) == []


# ---------------------------------------------------------------- the whole run

def test_the_dry_run_finds_the_clusters_and_calls_no_model(archive):
    repeated(archive, seed=14, sessions=["a", "b", "c"], label="wazne")

    r = mining.run(dry_run=True, ask=forbidden, conn=archive.conn)

    assert r["status"] == "dry-run"
    assert (r["chunks"], r["clusters"]) == (3, 1)
    assert r["preview"][0][0] == 3  # the session count goes with the preview, that is the whole point
    assert not facts.CANDIDATES_PATH.exists()


def test_the_limit_cuts_the_number_of_clusters_sent_to_the_model(archive):
    for seed in range(4):
        repeated(archive, seed=20 + seed, sessions=[f"s{seed}-1", f"s{seed}-2", f"s{seed}-3"],
                 label=f"temat{seed}")
    seen: list[str] = []

    r = mining.run(limit=2, ask=recorder(seen), conn=archive.conn)

    assert (r["clusters"], len(r["taken"])) == (4, 2)
    assert seen[0].count("[sesje: ") == 2


def test_every_snippet_carries_how_many_sessions_it_comes_from(archive):
    repeated(archive, seed=15, sessions=["a", "b", "c", "d"], months=["01", "03", "05", "09"])
    seen: list[str] = []

    mining.run(ask=recorder(seen), conn=archive.conn)

    assert "[sesje: 4, miesiace: 4," in seen[0]


def test_facts_land_in_the_waiting_room_with_their_layer(archive):
    repeated(archive, seed=16, sessions=["a", "b", "c"])

    r = mining.run(ask=answer(durable("Uzytkownik pracuje na Windowsie i uzywa PowerShella")),
                   conn=archive.conn)

    assert [f.text for f in r["added"]] == ["Uzytkownik pracuje na Windowsie i uzywa PowerShella"]
    written = facts.CANDIDATES_PATH.read_text(encoding="utf-8")
    assert "(stala/projekty) Uzytkownik pracuje na Windowsie i uzywa PowerShella" in written


def test_a_fact_already_waiting_is_not_added_twice(archive):
    repeated(archive, seed=17, sessions=["a", "b", "c"])
    facts.KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    facts.CANDIDATES_PATH.write_text(
        "- [ ] [2026-09-01] (stala/praca) Uzytkownik pracuje na Windowsie\n", encoding="utf-8")

    r = mining.run(ask=answer(durable("Uzytkownik pracuje na Windowsie."),
                              durable("Firma sprzedaje czesci do maszyn rolniczych")),
                   conn=archive.conn)

    assert [f.text for f in r["added"]] == ["Firma sprzedaje czesci do maszyn rolniczych"]


def test_a_fact_already_standing_in_the_rules_is_not_added_again(archive):
    repeated(archive, seed=18, sessions=["a", "b", "c"])
    facts.RULES_PATH.write_text("## Co wiem\n\n- Firma sprzedaje czesci do maszyn rolniczych\n",
                                encoding="utf-8")

    r = mining.run(ask=answer(durable("Firma sprzedaje czesci do maszyn rolniczych")),
                   conn=archive.conn)

    assert r["added"] == []


def test_nothing_to_read_when_no_cluster_reaches_three_sessions(archive):
    repeated(archive, seed=19, sessions=["jedna"] * 4)

    r = mining.run(ask=forbidden, conn=archive.conn)

    assert r["status"] == "no-clusters"


# ---------------------------------------------------------------- the marker

def test_the_marker_stays_where_it_was_unless_it_is_asked_for(archive):
    repeated(archive, seed=30, sessions=["a", "b", "c"])

    r = mining.run(ask=answer(durable("Cokolwiek trwalego o uzytkowniku i jego pracy")),
                   conn=archive.conn)

    assert r["marker"] == ""
    assert not facts.MARKER_PATH.exists()  # the daily harvest still walks through this material


def test_the_marker_moves_only_with_the_switch(archive):
    repeated(archive, seed=31, sessions=["a", "b", "c"], months=["01", "05", "09"])

    r = mining.run(move_marker=True, ask=answer(durable("Cokolwiek trwalego o uzytkowniku")),
                   conn=archive.conn)

    assert r["marker"] == r["newest"] == stamp("09", 13)
    assert facts.MARKER_PATH.read_text(encoding="utf-8").strip() == r["newest"]


def test_the_switch_is_off_by_default_in_the_command_line():
    assert mining._options([]) == (False, mining.DEFAULT_CLUSTERS, False)
    assert mining._options(["--proba", "--ile", "12", "--przesun-znacznik"]) == (True, 12, True)


# ---------------------------------------------------------------- the archive is never written to

def test_the_archive_is_opened_read_only(archive, tmp_path):
    repeated(archive, seed=32, sessions=["a", "b", "c"])
    conn = mining.open_readonly(tmp_path / "lore.db")
    try:
        assert len(mining.load(conn)[0]) == 3
        with pytest.raises(sqlite3.OperationalError):
            conn.execute("DELETE FROM chunks")
    finally:
        conn.close()
