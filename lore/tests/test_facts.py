"""Daily harvest of facts: what gets picked, what gets cut off and what lands in the waiting room."""

from __future__ import annotations

import json
import re
from datetime import datetime, timedelta, timezone

import pytest

from lore import facts

ENTRY = re.compile(r"^- \[ \] \[\d{4}-\d{2}-\d{2}\] (.+)$")
NOW = datetime.now(timezone.utc)  # one fixed point, so the same `ago` gives the very same string


def ago(hours: float) -> str:
    return facts.iso_utc(NOW - timedelta(hours=hours))


@pytest.fixture
def waiting_room(tmp_path, monkeypatch, environment):
    """The whole harvest inside tmp_path — the real ~/.claude must not be touched by the tests."""
    knowledge = tmp_path / "wiedza"
    monkeypatch.setattr(facts, "KNOWLEDGE_DIR", knowledge)
    monkeypatch.setattr(facts, "MARKER_PATH", knowledge / ".ostatnie-wyciaganie")
    monkeypatch.setattr(facts, "CANDIDATES_PATH", knowledge / "kandydaci.md")
    monkeypatch.setattr(facts, "RULES_PATH", tmp_path / "CLAUDE.md")
    monkeypatch.setattr(facts, "DB_PATH", tmp_path / "lore.db")
    return environment


def add(environment, ts: str, role: str, text: str, line: int = 1) -> None:
    environment.conn.execute(
        "INSERT INTO chunks(project, session, file, line, part, ts, role, text) VALUES (?,?,?,?,?,?,?,?)",
        ("test-project", "test-session", "test.jsonl", line, 0, ts, role, text),
    )


def answers(*lines: str):
    """Stand-in for the model — the tests must not need the network nor `claude` in PATH."""
    return lambda material: "\n".join(lines)


def recorder(seen: list[str]):
    """Stand-in that only writes down what it was given — for checking that nothing is skipped."""
    return lambda material: seen.append(material) or ""


def numbers(material: str) -> list[str]:
    """The '000' markers of the chunks handed to the model, in the order they were handed over."""
    return re.findall(r"user: (\d{3}) ", material)


def backlog(environment, count: int, size: int = 2000) -> None:
    """`count` numbered chunks, one per hour, far above the character cap in total."""
    for i in range(count):
        add(environment, ago(count - i), "user", f"{i:03d} " + "x" * size, line=i + 1)
    facts.write_marker(ago(count + 1))


def entries(waiting_room_path) -> list[str]:
    return [m.group(1) for m in (ENTRY.match(x) for x in waiting_room_path.read_text(encoding="utf-8").splitlines()) if m]


# ---------------------------------------------------------------- picking the material

def test_takes_only_chunks_newer_than_the_marker(waiting_room):
    add(waiting_room, ago(30), "user", "stare ustalenie")
    add(waiting_room, ago(2), "user", "nowe ustalenie")
    facts.write_marker(ago(10))

    material = facts.collect(waiting_room.conn, facts.since_marker())

    assert [t.split(": ", 1)[1] for t in material.texts] == ["nowe ustalenie"]


def test_missing_marker_means_the_last_day(waiting_room):
    add(waiting_room, ago(48), "user", "przedwczoraj")
    add(waiting_room, ago(3), "user", "dzis rano")

    assert not facts.MARKER_PATH.exists()
    material = facts.collect(waiting_room.conn, facts.since_marker())

    assert [t.split(": ", 1)[1] for t in material.texts] == ["dzis rano"]


def test_cap_takes_the_oldest_and_leaves_the_rest_as_a_backlog(waiting_room):
    backlog(waiting_room, 40)

    material = facts.collect(waiting_room.conn, facts.since_marker())

    assert material.chars <= facts.MAX_INPUT_CHARS
    assert material.pending == 40 - len(material.texts) > 0
    assert numbers(material.joined())[0] == "000"  # the oldest goes first, nothing is jumped over
    assert material.last_ts == ago(40 - len(material.texts) + 1)  # the timestamp of the last one taken
    assert material.runs_left() >= 1


def test_the_cut_does_not_fall_inside_one_turn(waiting_room):
    # parts of one turn share a timestamp — cutting between them would lose the tail for good,
    # because the next run asks for 'ts > marker'
    for i in range(40):
        add(waiting_room, ago(40 - i // 2), "user", f"{i:03d} " + "x" * 2000, line=i + 1)
    facts.write_marker(ago(48))

    material = facts.collect(waiting_room.conn, facts.since_marker())

    assert len(material.texts) % 2 == 0  # both parts of the last turn are in
    assert material.pending == 40 - len(material.texts)
    assert material.dropped == 0


def test_tool_noise_is_filtered_out(waiting_room):
    add(waiting_room, ago(1), "user", "pracuje na Windowsie")
    add(waiting_room, ago(1), "tool", "[tool: Bash] ls -la")
    add(waiting_room, ago(1), "result", "total 128 drwxr-xr-x")
    add(waiting_room, ago(1), "agent:tool", "[tool: Read] plik.py")
    add(waiting_room, ago(1), "assistant", "zapamietam to")
    facts.write_marker(ago(2))

    material = facts.collect(waiting_room.conn, facts.since_marker())

    assert [t.split(": ", 1)[1] for t in material.texts] == ["pracuje na Windowsie", "zapamietam to"]


# ---------------------------------------------------------------- the waiting room

def test_facts_land_in_the_waiting_room_in_the_agreed_format(waiting_room):
    add(waiting_room, ago(1), "user", "moja firma sprzedaje oleje na eBay")
    facts.write_marker(ago(2))

    r = facts.run(ask=answers("- Firma użytkownika sprzedaje oleje na eBay.", "", "Użytkownik pracuje na Windowsie."),
                  conn=waiting_room.conn)

    assert r["status"] == "ok"
    assert entries(facts.CANDIDATES_PATH) == [
        "Firma użytkownika sprzedaje oleje na eBay.",
        "Użytkownik pracuje na Windowsie.",
    ]
    assert facts.CANDIDATES_PATH.read_text(encoding="utf-8").startswith("# Kandydaci")


def test_a_structured_answer_is_taken_out_of_the_envelope(waiting_room):
    # what `claude -p --output-format json --json-schema` really returns
    envelope = json.dumps({"type": "result", "is_error": False, "result": "{\"fakty\": [\"ignorowane\"]}",
                           "structured_output": {"fakty": ["Firma użytkownika to Primo Oils.", "urywek"]}})
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))

    r = facts.run(ask=lambda material: envelope, conn=waiting_room.conn)

    assert r["facts"] == ["Firma użytkownika to Primo Oils."]  # the envelope wins, the scrap is dropped
    assert entries(facts.CANDIDATES_PATH) == ["Firma użytkownika to Primo Oils."]


def test_an_empty_list_of_facts_does_not_fall_back_to_the_envelope_text(waiting_room):
    envelope = json.dumps({"type": "result", "structured_output": {"fakty": []}})
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))

    r = facts.run(ask=lambda material: envelope, conn=waiting_room.conn)

    assert r["facts"] == [] and r["added"] == []
    assert not facts.CANDIDATES_PATH.exists()


def test_the_rules_file_is_never_written_to(waiting_room):
    facts.RULES_PATH.write_text("# Ustalenia\n", encoding="utf-8")
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))

    facts.run(ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)

    assert facts.RULES_PATH.read_text(encoding="utf-8") == "# Ustalenia\n"


def test_a_second_run_does_not_duplicate_a_fact(waiting_room):
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))
    ask = answers("Użytkownik pracuje na Windowsie.")

    first = facts.run(ask=ask, conn=waiting_room.conn)
    facts.write_marker(ago(2))  # as if the marker had not moved — the same material once more
    second = facts.run(ask=answers("użytkownik pracuje na windowsie"), conn=waiting_room.conn)

    assert len(first["added"]) == 1
    assert second["added"] == []
    assert entries(facts.CANDIDATES_PATH) == ["Użytkownik pracuje na Windowsie."]


def test_a_fact_already_standing_in_the_rules_is_not_proposed(waiting_room):
    facts.RULES_PATH.write_text("# Ustalenia\n- Użytkownik pracuje na Windowsie!\n", encoding="utf-8")
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))

    r = facts.run(ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)

    assert r["added"] == []
    assert not facts.CANDIDATES_PATH.exists()


def test_the_marker_moves_only_after_a_real_run(waiting_room):
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))
    before = facts.since_marker()

    facts.run(dry_run=True, ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)
    assert facts.since_marker() == before
    assert not facts.CANDIDATES_PATH.exists()

    facts.run(ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)
    assert facts.since_marker() > before


# ---------------------------------------------------------------- working off a backlog

def test_the_marker_stops_at_the_last_processed_fragment(waiting_room):
    backlog(waiting_room, 40)
    seen = []

    r = facts.run(ask=recorder(seen), conn=waiting_room.conn)

    assert r["pending"] > 0
    assert facts.since_marker() == ago(40 - r["chunks"] + 1)  # where we got to, not "now"
    assert facts.since_marker() < ago(0)
    assert numbers(seen[0])[0] == "000"


def test_the_next_runs_continue_and_skip_nothing(waiting_room):
    backlog(waiting_room, 60)
    seen = []

    results = facts.catch_up(runs=10, ask=recorder(seen), conn=waiting_room.conn)

    assert [n for material in seen for n in numbers(material)] == [f"{i:03d}" for i in range(60)]
    assert results[-1]["pending"] == 0
    assert len(results) == len(seen) > 1  # it really took more than one pass


def test_a_run_after_catching_up_has_nothing_to_do(waiting_room):
    backlog(waiting_room, 60)
    facts.catch_up(runs=10, ask=answers(), conn=waiting_room.conn)

    r = facts.run(ask=answers("nic nowego nie powinno powstac"), conn=waiting_room.conn)

    assert r["status"] == "no-material"
    assert r["chunks"] == 0
    assert not facts.CANDIDATES_PATH.exists()


def test_catching_up_does_at_most_the_requested_number_of_passes(waiting_room):
    backlog(waiting_room, 60)
    seen = []

    assert len(facts.catch_up(runs=3, ask=recorder(seen), conn=waiting_room.conn)) == 3

    # the backlog is gone by now — a further -Nadrabiaj 3 stops after the first, empty pass
    rest = facts.catch_up(runs=3, ask=recorder(seen), conn=waiting_room.conn)
    assert len(rest) == 1 and rest[0]["status"] == "no-material"


def test_catching_up_understood_from_the_command_line(waiting_room):
    assert facts._options([]) == (False, 1)
    assert facts._options(["--proba", "--nadrabiaj", "3"]) == (True, 3)
    assert facts._options(["--nadrabiaj"]) == (False, 1)


# ---------------------------------------------------------------- nothing may blow up

def test_an_empty_database_is_not_an_error(waiting_room):
    r = facts.run(ask=answers("nic z tego nie powinno wyjsc"), conn=waiting_room.conn)

    assert r["status"] == "no-material"
    assert r["added"] == []
    assert not facts.CANDIDATES_PATH.exists()
    assert facts.main(argv=[]) == 0


def test_a_missing_database_is_not_an_error(waiting_room, tmp_path, monkeypatch):
    monkeypatch.setattr(facts, "DB_PATH", tmp_path / "nie-ma-takiej.db")

    r = facts.run(ask=answers("cokolwiek"))

    assert r["status"] == "no-database"
    assert not (tmp_path / "nie-ma-takiej.db").exists()  # a missing database is not created here
    assert facts.main(argv=[]) == 0


def test_no_claude_in_path_ends_with_code_one(waiting_room, monkeypatch):
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))
    before = facts.since_marker()
    monkeypatch.setattr(facts.shutil, "which", lambda name: None)

    with pytest.raises(facts.ModelMissing):
        facts.ask_model("material")
    assert facts.main(argv=[]) == 1
    assert facts.since_marker() == before  # the marker stays, tomorrow has to catch up
    assert not facts.CANDIDATES_PATH.exists()
