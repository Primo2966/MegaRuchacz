"""lore_stats per source program (Claude Code, Codex, OpenCode) and the OpenCode state from meta —
a fault of the OpenCode read must be visible in the stats, not only in the indexer's log."""

from __future__ import annotations

import json
import os
import time

from lore import index, search

from test_opencode import FakeOpencode


def _old(p) -> None:
    old = time.time() - index.TAIL_CLOSING_AGE_S - 1
    os.utime(p, (old, old))


def _codex_file(env) -> None:
    d = index.CODEX_SESSIONS_DIR / "2026" / "09" / "16"
    d.mkdir(parents=True)
    p = d / "rollout-2026-09-16T10-00-00-0199aaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl"
    rows = [{"timestamp": "2026-09-16T10:00:00.000Z", "type": "response_item",
             "payload": {"type": "message", "role": role,
                         "content": [{"type": "input_text" if role == "user" else "output_text", "text": text}]}}
            for role, text in (("user", "Pytanie z Codeksa."), ("assistant", "Odpowiedź z Codeksa."))]
    p.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
    _old(p)


def _set_status(env, value: str) -> None:
    env.conn.execute("INSERT INTO meta(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                     (index.META_OPENCODE, value))


def test_files_and_chunks_are_counted_per_program(environment):
    _old(environment.transcript(("user", "Pytanie z Claude Code."), ("assistant", "Odpowiedź z Claude Code.")))
    _codex_file(environment)
    oc = FakeOpencode(index.opencode_db())
    try:
        for sid in ("ses_a", "ses_b"):
            oc.session(sid)
            oc.message(sid, "user", f"Pytanie z OpenCode {sid}.")
            oc.message(sid, "assistant", "Odpowiedź z OpenCode.")
    finally:
        oc.conn.close()

    assert index.index(environment.conn, quiet=True) == 4
    s = search.stats(environment.conn)
    src = s["sources"]
    assert {k: (v["files"], v["chunks"]) for k, v in src.items()} == {
        "Claude Code": (1, 1), "Codex": (1, 1), "OpenCode": (2, 2)}
    assert sum(v["chunks"] for v in src.values()) == s["chunks"]
    assert src["OpenCode"]["status"].startswith("ok ")
    assert "UWAGA" not in s


def test_no_opencode_is_a_calm_note_not_a_warning(environment):
    index.index_opencode(environment.conn, quiet=True)
    s = search.stats(environment.conn)
    assert "UWAGA" not in s
    assert s["sources"]["OpenCode"]["status"] == "absent"
    assert s["sources"]["OpenCode"]["note"] == search.OPENCODE_ABSENT


def test_never_checked_is_said_too(environment):
    s = search.stats(environment.conn)
    assert "UWAGA" not in s
    assert s["sources"]["OpenCode"]["status"] is None
    assert s["sources"]["OpenCode"]["note"] == search.OPENCODE_UNCHECKED


def test_a_recorded_fault_stands_first_in_the_stats(environment):
    """The negative test: meta says BLAD -> the very first key of the result says it."""
    _set_status(environment, "BLAD 2026-10-06T08:00:00Z: opencode.db: no table 'part'")
    s = search.stats(environment.conn)
    assert next(iter(s)) == "UWAGA"
    assert "BLAD 2026-10-06T08:00:00Z: opencode.db: no table 'part'" in s["UWAGA"]
    assert s["sources"]["OpenCode"]["status"].startswith("BLAD ")


def test_a_real_schema_fault_reaches_the_stats(environment):
    """End to end: an OpenCode database of an unknown shape -> the indexer records BLAD -> stats shows it."""
    import sqlite3
    path = index.opencode_db()
    path.parent.mkdir(parents=True, exist_ok=True)
    c = sqlite3.connect(path)
    c.execute("CREATE TABLE session (id text PRIMARY KEY)")
    c.commit()
    c.close()
    index.index_opencode(environment.conn, quiet=True)
    s = search.stats(environment.conn)
    assert next(iter(s)) == "UWAGA" and "BLAD" in s["UWAGA"]


def test_an_unknown_state_is_not_taken_for_ok(environment):
    _set_status(environment, "cos-nowego")
    assert next(iter(search.stats(environment.conn))) == "UWAGA"
