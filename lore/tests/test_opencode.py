"""OpenCode conversations (SQLite) in Lore — on a synthetic database shaped like OpenCode 1.18.33."""

from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import time
from datetime import datetime, timezone

import pytest

from lore import index, usage

# old enough for every tail to be closed (TAIL_CLOSING_AGE_S)
T0 = int(datetime(2026, 9, 16, 10, 0, tzinfo=timezone.utc).timestamp() * 1000)

SCHEMA = """
CREATE TABLE session (id text PRIMARY KEY, project_id text NOT NULL, parent_id text, slug text NOT NULL,
    directory text NOT NULL, title text NOT NULL, version text NOT NULL, time_created integer NOT NULL,
    time_updated integer NOT NULL);
CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL,
    time_updated integer NOT NULL, data text NOT NULL);
CREATE TABLE part (id text PRIMARY KEY, message_id text NOT NULL, session_id text NOT NULL,
    time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL);
"""


class FakeOpencode:
    """~/.local/share/opencode/opencode.db built by hand: sessions, messages and their parts."""

    def __init__(self, path):
        self.path = path
        path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(path, isolation_level=None)
        self.conn.execute("PRAGMA journal_mode=WAL")
        self.conn.executescript(SCHEMA)
        self.nr = 0

    def _id(self, prefix: str) -> str:
        self.nr += 1
        return f"{prefix}_{self.nr:06d}"

    def session(self, sid: str, directory: str = "C:/dev/claude-worker", parent: str | None = None,
                at: int = T0) -> str:
        self.conn.execute("INSERT INTO session VALUES (?,?,?,?,?,?,?,?,?)",
                          (sid, "prj", parent, sid, directory, "tytul", "1.18.33", at, at))
        return sid

    def message(self, sid: str, role: str, *texts: str, at: int | None = None, completed: bool = True,
                parts: list[dict] | None = None) -> str:
        at = at if at is not None else T0 + self.nr * 1000
        mid = self._id("msg")
        data = {"role": role, "time": {"created": at}}
        if role == "assistant" and completed:
            data["time"]["completed"] = at + 500
        self.conn.execute("INSERT INTO message VALUES (?,?,?,?,?)", (mid, sid, at, at, json.dumps(data)))
        for p in [*({"type": "text", "text": t} for t in texts), *(parts or [])]:
            self.conn.execute("INSERT INTO part VALUES (?,?,?,?,?,?)",
                              (self._id("prt"), mid, sid, at, at, json.dumps(p, ensure_ascii=False)))
        self.conn.execute("UPDATE session SET time_updated=max(time_updated, ?) WHERE id=?", (at, sid))
        return mid

    def complete(self, mid: str, at: int) -> None:
        data = json.loads(self.conn.execute("SELECT data FROM message WHERE id=?", (mid,)).fetchone()[0])
        data["time"]["completed"] = at
        self.conn.execute("UPDATE message SET data=?, time_updated=? WHERE id=?", (json.dumps(data), at, mid))


@pytest.fixture
def opencode(environment):
    db = FakeOpencode(index.opencode_db())
    yield db
    db.conn.close()


def oc_rows(env) -> list[tuple]:
    return list(env.conn.execute("SELECT project, session, file, line, role, ts, text FROM chunks ORDER BY id"))


def status(env) -> str | None:
    r = env.conn.execute("SELECT value FROM meta WHERE key=?", (index.META_OPENCODE,)).fetchone()
    return r[0] if r else None


def run(env) -> int:
    return index.index_opencode(env.conn, quiet=True)[0]


# ---------------------------------------------------------------- reading


def test_no_opencode_on_the_machine_is_quietly_skipped(environment, capsys):
    assert not index.opencode_db().exists()
    assert index.index_opencode(environment.conn) == (0, 0, 0)
    assert status(environment) == "absent"
    assert "UWAGA" not in capsys.readouterr().err


def test_user_and_assistant_text_is_indexed_reasoning_tools_and_synthetic_are_not(environment, opencode):
    sid = opencode.session("ses_a", directory="C:/dev/ecommerce-helper")
    opencode.message(sid, "user", "Zapamiętaj niebieski wariant.",
                     parts=[{"type": "text", "text": "wstrzyknięte instrukcje", "synthetic": True}])
    opencode.message(sid, "assistant", "Zapamiętam.",
                     parts=[{"type": "reasoning", "text": "prywatne rozumowanie"},
                            {"type": "tool", "tool": "bash", "state": {"input": {"command": "ls"}, "output": "x"}},
                            {"type": "step-finish", "tokens": {"input": 5}}])

    assert run(environment) == 1
    [(project, session, file, line, role, ts, text)] = oc_rows(environment)
    assert (project, session, line, role) == ("ecommerce-helper", "ses_a", 1, "conversation")
    assert file == f"{index.opencode_db()}#ses_a"
    assert ts == "2026-09-16T10:00:00.000Z"
    assert text == "user: Zapamiętaj niebieski wariant.\n\nassistant: Zapamiętam."
    assert status(environment).startswith("ok ") and "1 sessions" in status(environment)


def test_the_full_index_pass_takes_opencode_and_files_alike(environment, opencode):
    environment.transcript(("user", "Pytanie z Claude Code."), ("assistant", "Odpowiedź z Claude Code."))
    old = time.time() - index.TAIL_CLOSING_AGE_S - 1

    for p in environment.projects.rglob("*.jsonl"):
        os.utime(p, (old, old))
    sid = opencode.session("ses_b")
    opencode.message(sid, "user", "Pytanie z OpenCode.")
    opencode.message(sid, "assistant", "Odpowiedź z OpenCode.")

    assert index.index(environment.conn, quiet=True) == 2
    texts = environment.texts()
    assert any("OpenCode" in t for t in texts) and any("Claude Code" in t for t in texts)
    assert index.find_files() == list(environment.projects.rglob("*.jsonl"))  # the database is no file of theirs


def test_only_new_messages_are_read_the_next_time(environment, opencode):
    sid = opencode.session("ses_c")
    opencode.message(sid, "user", "Pierwsza decyzja " + "x" * 1500)
    opencode.message(sid, "assistant", "Zapisane " + "y" * 1500)
    assert run(environment) > 0
    first = list(environment.conn.execute("SELECT id, text FROM chunks ORDER BY id"))
    state = environment.conn.execute("SELECT size, offset, line FROM files").fetchone()
    assert state == (2, 2, 2)

    assert run(environment) == 0  # nothing changed - nothing read

    opencode.message(sid, "user", "Druga decyzja.")
    opencode.message(sid, "assistant", "Też zapisane.")
    assert run(environment) == 1
    rows = list(environment.conn.execute("SELECT id, text FROM chunks ORDER BY id"))
    assert rows[:len(first)] == first  # the stored ones were not touched
    assert rows[-1][1] == "user: Druga decyzja.\n\nassistant: Też zapisane."
    assert environment.conn.execute("SELECT line FROM chunks ORDER BY id DESC").fetchone()[0] == 3


def test_a_subagent_session_is_filed_under_its_parent(environment, opencode):
    opencode.session("ses_parent")
    opencode.session("ses_child", parent="ses_parent")
    opencode.message("ses_child", "user", "Zadanie dla pomocnika.")

    run(environment)
    [(project, session, file, _, role, _, _)] = oc_rows(environment)
    assert (session, role) == ("ses_parent", "agent:user")
    assert file.endswith("#ses_child")


def test_an_answer_still_being_written_waits_until_it_is_complete(environment, opencode):
    now = int(time.time() * 1000)
    sid = opencode.session("ses_d", at=now)
    opencode.message(sid, "user", "Pytanie " + "q" * 1600, at=now)
    mid = opencode.message(sid, "assistant", "Odpowiedź w poło" + "a" * 1600, at=now + 1, completed=False)

    run(environment)
    assert [r[4] for r in oc_rows(environment)] == ["user", "user"]  # the long question only (2 parts)

    opencode.complete(mid, now + 5)
    run(environment)
    assert "assistant" in [r[4] for r in oc_rows(environment)]


def test_undone_messages_are_indexed_again_from_zero(environment, opencode):
    sid = opencode.session("ses_e")
    opencode.message(sid, "user", "Stara wersja.")
    gone = opencode.message(sid, "assistant", "Do cofnięcia.")
    run(environment)
    opencode.conn.execute("DELETE FROM part WHERE message_id=?", (gone,))
    opencode.conn.execute("DELETE FROM message WHERE id=?", (gone,))
    opencode.message(sid, "assistant", "Nowa odpowiedź.", at=T0 + 50_000)

    run(environment)
    assert environment.texts() == ["user: Stara wersja.\n\nassistant: Nowa odpowiedź."]


def test_the_opencode_database_is_never_written(environment, opencode):
    sid = opencode.session("ses_f")
    opencode.message(sid, "user", "Tylko odczyt.")
    opencode.message(sid, "assistant", "Jasne.")
    opencode.conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    before = hashlib.sha256(opencode.path.read_bytes()).hexdigest()
    opencode.conn.execute("BEGIN IMMEDIATE")  # a running OpenCode holding a write transaction
    try:
        assert run(environment) == 1  # a WAL reader is not blocked by it
    finally:
        opencode.conn.execute("ROLLBACK")
    assert hashlib.sha256(opencode.path.read_bytes()).hexdigest() == before
    oc = index.opencode_connect()
    try:
        oc.execute("PRAGMA query_only=OFF")  # the second guard off: the connection itself is read-only
        with pytest.raises(sqlite3.OperationalError, match="readonly"):
            oc.execute("CREATE TABLE x(a)")
    finally:
        oc.close()


# ---------------------------------------------------------------- faults: said, recorded, never a crash


def test_probe_a_schema_without_a_needed_column_is_reported_not_crashed(environment, capsys):
    path = index.opencode_db()
    path.parent.mkdir(parents=True)
    c = sqlite3.connect(path)
    c.executescript(SCHEMA.replace("time_updated integer NOT NULL, data text NOT NULL);\nCREATE TABLE part",
                                   "payload text NOT NULL);\nCREATE TABLE part"))
    c.close()

    assert index.index(environment.conn, quiet=True) == 0
    assert status(environment).startswith("BLAD ") and "'message' lacks time_updated, data" in status(environment)
    assert "UWAGA: OpenCode conversations are NOT indexed" in capsys.readouterr().err


def test_probe_a_missing_table_is_reported(environment, capsys):
    path = index.opencode_db()
    path.parent.mkdir(parents=True)
    c = sqlite3.connect(path)
    c.execute("CREATE TABLE session_v2 (id text)")
    c.close()

    run(environment)
    assert "no table 'session'" in status(environment)
    assert "UWAGA" in capsys.readouterr().err


def test_probe_a_damaged_file_is_reported(environment, capsys):
    path = index.opencode_db()
    path.parent.mkdir(parents=True)
    path.write_bytes(b"to nie jest baza SQLite " * 100)

    assert run(environment) == 0
    assert status(environment).startswith("BLAD ")
    assert "UWAGA" in capsys.readouterr().err


def test_probe_unreadable_rows_are_counted_and_the_rest_is_indexed(environment, opencode, capsys):
    sid = opencode.session("ses_g")
    opencode.message(sid, "user", "Dobra wiadomość.")
    opencode.conn.execute("INSERT INTO message VALUES ('msg_zly', ?, ?, ?, '{nie json')", (sid, T0 + 90_000, T0 + 90_000))
    opencode.message(sid, "assistant", "Też dobra.", at=T0 + 95_000)

    assert run(environment) == 1
    assert environment.texts() == ["user: Dobra wiadomość.\n\nassistant: Też dobra."]
    assert "1 rows with unreadable JSON" in status(environment)
    assert "unreadable JSON" in capsys.readouterr().err


def test_a_fault_gone_clears_the_status(environment, opencode):
    index._record_opencode(environment.conn, "BLAD stary")
    opencode.session("ses_h")
    run(environment)
    assert status(environment).startswith("ok ")


# ---------------------------------------------------------------- use of a fact (lore.usage)


def test_use_check_reads_opencode_answers_and_tool_input_once(environment, opencode):
    watch = usage.Watch("Sprawa 12345678901", [usage.Signature("12345678901", True)])
    sid = opencode.session("ses_u")
    opencode.message(sid, "user", "Co ze sprawą 12345678901?")  # the user's words are no use
    opencode.message(sid, "assistant", "Sprawdzam.",
                     parts=[{"type": "tool", "tool": "bash",
                             "state": {"input": {"command": "gh issue view 12345678901"}}}])
    since = "2026-09-16T00:00:00Z"

    s = usage.scan([watch], since, {})
    assert list(s.found) == ["Sprawa 12345678901"]
    assert s.found["Sprawa 12345678901"].session == "ses_u"
    key = str(index.opencode_db())
    assert s.offsets[key] > 0

    again = usage.scan([watch], since, s.offsets)
    assert again.found == {} and again.offsets[key] == s.offsets[key]


def test_use_check_ignores_an_edit_of_the_rules(environment, opencode):
    watch = usage.Watch("Sprawa 12345678901", [usage.Signature("12345678901", True)])
    sid = opencode.session("ses_v")
    opencode.message(sid, "assistant", parts=[{"type": "tool", "tool": "edit", "state": {"input": {
        "filePath": "C:/Users/x/.claude/CLAUDE.md", "newString": "- Sprawa 12345678901"}}}])

    assert usage.scan([watch], "2026-09-16T00:00:00Z", {}).found == {}


def test_use_check_reports_a_broken_database(environment, capsys):
    path = index.opencode_db()
    path.parent.mkdir(parents=True)
    path.write_bytes(b"zepsute " * 100)
    watch = usage.Watch("Sprawa 12345678901", [usage.Signature("12345678901", True)])

    s = usage.scan([watch], "2026-09-16T00:00:00Z", {str(path): 7})
    assert s.offsets[str(path)] == 7  # the place is kept for the day it can be read again
    assert "UWAGA: OpenCode" in capsys.readouterr().err
