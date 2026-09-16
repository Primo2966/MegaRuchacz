"""Incrementality: the open tail of a file, resuming and no duplicates."""

from __future__ import annotations

import os
import time

LONG = "x" * 2000  # longer than a chunk — its own group, cut into two parts
OTHER_LONG = "y" * 2000
LONG_AGO = 48 * 60 * 60


def test_open_tail_does_not_reach_the_database(environment):
    p = environment.transcript(("user", "Are we moving the indexer?"), ("assistant", "I suggest e5-small."))

    assert environment.index(p) == 0  # the group may still grow
    assert environment.texts() == []
    assert environment.file_state(p)[2] == 0  # the offset stops before the open group


def test_closing_the_group_stores_the_glued_pair(environment):
    p = environment.transcript(("user", "Are we moving the indexer?"), ("assistant", "I suggest e5-small."))
    environment.index(p)
    environment.append(p, ("assistant", LONG))

    assert environment.index(p) == 3  # the glued pair + two parts of the long turn
    line, part, role, text = environment.rows()[0]
    assert (line, part, role) == (1, 0, "conversation")
    assert text == "user: Are we moving the indexer?\n\nassistant: I suggest e5-small."


def test_resuming_adds_data_and_does_not_duplicate(environment):
    p = environment.transcript(("user", "Are we moving the indexer?"), ("assistant", "I suggest e5-small."))
    environment.index(p)
    environment.append(p, ("assistant", LONG))
    environment.index(p)
    after_closing = environment.texts()

    environment.append(p, ("user", "yes, do it"))
    assert environment.index(p) == 0  # an open tail again
    assert environment.texts() == after_closing

    environment.append(p, ("assistant", "Done, the indexer is running."), ("user", OTHER_LONG))
    assert environment.index(p) == 3  # a new glued pair + the long turn
    texts = environment.texts()
    assert texts[:len(after_closing)] == after_closing
    assert texts[len(after_closing)] == "user: yes, do it\n\nassistant: Done, the indexer is running."
    assert len(texts) == len(set(texts))


def test_no_duplicates_when_indexing_twice(environment):
    p = environment.transcript(
        ("user", "Are we moving the indexer?"),
        ("assistant", "I suggest e5-small."),
        ("user", "yes, do it"),
        ("assistant", LONG),
    )
    assert environment.index(p) == 3
    first = environment.rows()

    assert environment.index(p) == 0  # nothing has changed
    assert environment.rows() == first

    # a forced re-read of the whole file (e.g. after losing state) does not add a second copy
    environment.conn.execute("UPDATE files SET mtime=0, offset=0, line=0 WHERE path=?", (str(p),))
    assert environment.index(p) == 3
    assert [(p_, r, t) for _, p_, r, t in environment.rows()] == [(p_, r, t) for _, p_, r, t in first]


def test_old_file_closes_its_tail(environment):
    p = environment.transcript(("user", "Are we moving the indexer?"), ("assistant", "I suggest e5-small."))
    assert environment.index(p) == 0

    long_ago = time.time() - LONG_AGO
    os.utime(p, (long_ago, long_ago))
    # the state in the database matches the file — we close the tail despite no changes
    environment.conn.execute(
        "UPDATE files SET mtime=?, size=? WHERE path=?", (p.stat().st_mtime, p.stat().st_size, str(p))
    )

    assert environment.index(p) == 1
    assert environment.texts() == ["user: Are we moving the indexer?\n\nassistant: I suggest e5-small."]
    assert environment.file_state(p)[2] == p.stat().st_size
    assert environment.index(p) == 0  # a closed tail does not come back


def test_single_long_turn_is_stored_right_away(environment):
    p = environment.transcript(("assistant", LONG))

    assert environment.index(p) == 2  # a long turn has nothing to be glued with
    assert [(p_, r) for _, p_, r, _ in environment.rows()] == [(0, "assistant"), (1, "assistant")]
