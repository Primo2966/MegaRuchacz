"""Daily harvest of facts: what gets picked, what gets cut off and what lands in the waiting room."""

from __future__ import annotations

import json
import re
import subprocess
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from lore import facts

ENTRY = re.compile(r"^- \[ \] \[(\d{4}-\d{2}-\d{2})\] \(([^)]+)\) (.+)$")
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


def sorted_answer(*items: dict):
    """Stand-in returning what the model really returns now: facts with a layer assigned."""
    envelope = json.dumps({"type": "result", "structured_output": {"fakty": list(items)}})
    return lambda material: envelope


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


def written(waiting_room_path) -> list[str]:
    return waiting_room_path.read_text(encoding="utf-8").splitlines()


def matched(waiting_room_path) -> list[re.Match]:
    return [m for m in (ENTRY.match(x) for x in written(waiting_room_path)) if m]


def entries(waiting_room_path) -> list[str]:
    """The texts alone — what the entry says, without the date and the layer."""
    return [m.group(3) for m in matched(waiting_room_path)]


def labels(waiting_room_path) -> list[str]:
    """The bracket of every entry: 'stala/firma', 'biezaca', 'referencyjna:plik.md'."""
    return [m.group(2) for m in matched(waiting_room_path)]


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


def test_only_the_user_is_harvested(waiting_room):
    """Everything but the user is dropped — see HARVESTED_ROLES for why.

    The assistant's half of a real archive is eight times the user's and is mostly
    its own reports, so harvesting it costs eight times more for noise.
    """
    add(waiting_room, ago(1), "user", "pracuje na Windowsie")
    add(waiting_room, ago(1), "tool", "[tool: Bash] ls -la")
    add(waiting_room, ago(1), "result", "total 128 drwxr-xr-x")
    add(waiting_room, ago(1), "agent:tool", "[tool: Read] plik.py")
    add(waiting_room, ago(1), "assistant", "zapamietam to")
    add(waiting_room, ago(1), "agent:user", "podzadanie od kierownika")
    facts.write_marker(ago(2))

    material = facts.collect(waiting_room.conn, facts.since_marker())

    # "agent:user" counts too: the suffix is what names the speaker
    assert [t.split(": ", 1)[1] for t in material.texts] == [
        "pracuje na Windowsie",
        "podzadanie od kierownika",
    ]


# ---------------------------------------------------------------- the layers

MIXED = (
    {"tresc": "analyzeAll zakolejkowane ponownie, czeka na przebieg.", "warstwa": "biezaca"},
    {"tresc": "Sprzedaż idzie przez Amazon i eBay, rynek niemiecki.", "warstwa": "stala",
     "podsekcja": "firma"},
    {"tresc": "Pełna struktura SKU olejków: OL-100, OL-200, OL-300.", "warstwa": "referencyjna",
     "plik": "Struktura SKU.md", "odsylacz": "Struktura SKU olejków — ~/.claude/wiedza/struktura-sku.md"},
    {"tresc": "Woli krótkie meldunki bez żargonu.", "warstwa": "stala", "podsekcja": "praca"},
)


@pytest.fixture
def one_chunk(waiting_room):
    """The smallest possible material — these tests are about the answer, not about picking it."""
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))
    return waiting_room


def test_a_durable_fact_lands_with_its_subsection(one_chunk):
    facts.run(ask=sorted_answer(MIXED[1]), conn=one_chunk.conn)

    assert labels(facts.CANDIDATES_PATH) == ["stala/firma"]
    assert entries(facts.CANDIDATES_PATH) == ["Sprzedaż idzie przez Amazon i eBay, rynek niemiecki."]


def test_a_current_fact_carries_a_date(one_chunk):
    facts.run(ask=sorted_answer(MIXED[0]), conn=one_chunk.conn)

    entry = matched(facts.CANDIDATES_PATH)[0]
    assert entry.group(1) == datetime.now().strftime("%Y-%m-%d")  # without a date it cannot age out
    assert entry.group(2) == "biezaca"


def test_a_reference_fact_gets_a_file_name_and_a_pointer_line(one_chunk):
    facts.run(ask=sorted_answer(MIXED[2]), conn=one_chunk.conn)

    assert labels(facts.CANDIDATES_PATH) == ["referencyjna:struktura-sku.md"]  # the name is tidied up
    assert "      odsyłacz: Struktura SKU olejków — ~/.claude/wiedza/struktura-sku.md" in written(facts.CANDIDATES_PATH)
    assert [f.file for f in facts.waiting_facts()] == ["struktura-sku.md"]  # and it survives a re-read


def test_a_reference_fact_without_a_name_still_gets_one(one_chunk):
    facts.run(ask=sorted_answer({"tresc": "Warianty pojemności: 10, 30, 50, 100 ml.",
                                 "warstwa": "referencyjna"}), conn=one_chunk.conn)

    assert labels(facts.CANDIDATES_PATH) == [f"referencyjna:{facts.UNNAMED_FILE}"]
    assert f"      odsyłacz: Szczegóły w ~/.claude/wiedza/{facts.UNNAMED_FILE}" in written(facts.CANDIDATES_PATH)


def test_a_missing_or_made_up_layer_falls_back_to_the_safest_shelf(one_chunk):
    facts.run(ask=sorted_answer({"tresc": "Fakt, którego nikt nie przypisał do warstwy."},
                                {"tresc": "Fakt z wymyśloną warstwą, też ma gdzieś trafić.",
                                 "warstwa": "kosmiczna"},
                                {"tresc": "Fakt z wymyśloną podsekcją, ta sama historia.",
                                 "warstwa": "stala", "podsekcja": "kuchnia"}), conn=one_chunk.conn)

    assert labels(facts.CANDIDATES_PATH) == ["stala/projekty"] * 3  # nothing is ever dropped
    assert len(entries(facts.CANDIDATES_PATH)) == 3


def test_the_entries_are_grouped_by_layer(one_chunk):
    facts.run(ask=sorted_answer(*MIXED), conn=one_chunk.conn)

    # a human approves a whole shelf at once, so the order of the answer must not survive
    assert labels(facts.CANDIDATES_PATH) == [
        "stala/firma", "stala/praca", "biezaca", "referencyjna:struktura-sku.md"]
    text = facts.CANDIDATES_PATH.read_text(encoding="utf-8")
    assert text.index("## Trwałe") < text.index("## Bieżące") < text.index("## Do osobnych plików")


def test_an_entry_in_the_old_format_is_still_read(one_chunk):
    # 54 entries written before the layers existed lie in the real waiting room — they must not stop working
    facts.KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    facts.CANDIDATES_PATH.write_text(
        facts.CANDIDATES_HEADER + "- [ ] [2026-09-01] Użytkownik pracuje na Windowsie.\n", encoding="utf-8")

    old = facts.waiting_facts()
    assert [(f.layer, f.section, f.text) for f in old] == [("stala", "projekty", "Użytkownik pracuje na Windowsie.")]

    r = facts.run(ask=answers("użytkownik pracuje na windowsie"), conn=one_chunk.conn)
    assert r["added"] == []  # the old entry still blocks the duplicate


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
    # a plain text answer says nothing about layers — everything lands on the safest shelf
    assert labels(facts.CANDIDATES_PATH) == ["stala/projekty", "stala/projekty"]
    assert facts.CANDIDATES_PATH.read_text(encoding="utf-8").startswith("# Kandydaci")


def test_a_structured_answer_is_taken_out_of_the_envelope(waiting_room):
    # what `claude -p --output-format json --json-schema` really returns
    envelope = json.dumps({"type": "result", "is_error": False, "result": "{\"fakty\": [\"ignorowane\"]}",
                           "structured_output": {"fakty": [
                               {"tresc": "Firma użytkownika to Primo Oils.", "warstwa": "stala",
                                "podsekcja": "firma"},
                               {"tresc": "urywek", "warstwa": "stala"}]}})
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))

    r = facts.run(ask=lambda material: envelope, conn=waiting_room.conn)

    # the envelope wins, the scrap is dropped
    assert [f.text for f in r["facts"]] == ["Firma użytkownika to Primo Oils."]
    assert entries(facts.CANDIDATES_PATH) == ["Firma użytkownika to Primo Oils."]
    assert labels(facts.CANDIDATES_PATH) == ["stala/firma"]


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


# ---------------------------------------------------------------- picking the tool

def installed(*names: str):
    """Stand-in for PATH: these tools are found, everything else is missing."""
    return lambda name: f"/bin/{name}" if name in names else None


@pytest.fixture
def unforced(monkeypatch):
    """No LORE_MODEL_CLI — otherwise a variable set on the real machine steers the tests."""
    monkeypatch.delenv(facts.MODEL_CLI_ENV, raising=False)


def test_with_claude_alone_the_claude_command_line_is_used(unforced, monkeypatch):
    monkeypatch.setattr(facts.shutil, "which", installed("claude"))

    cli = facts.find_model_cli()
    argv, stdin = cli.invocation("instrukcja", "material", Path("odpowiedz.txt"))

    assert (cli.name, cli.verified) == ("claude", True)
    assert argv[1:] == [*facts.MODEL_ARGS, "instrukcja"]  # the instruction in argv
    assert stdin == "material"  # the material on stdin, where 60 k characters fit
    assert not cli.answer_in_file()  # claude prints the answer, there is no file to point it at


def test_with_codex_alone_the_knowledge_layer_still_has_a_model(unforced, monkeypatch):
    """The whole point: a Codex-only machine used to raise ModelMissing and harvest nothing."""
    monkeypatch.setattr(facts.shutil, "which", installed("codex"))

    cli = facts.find_model_cli()
    argv, stdin = cli.invocation("instrukcja", "material", Path("/tmp/odpowiedz.txt"))

    assert cli.name == "codex"
    assert cli.verified  # 2026-09-17: the switches come from a real `codex exec --help`
    assert argv[1:] == [a if a != facts.ANSWER_SLOT else str(Path("/tmp/odpowiedz.txt"))
                        for a in facts.CODEX_ARGS]
    assert stdin == "instrukcja\n\nmaterial"  # codex exec takes one prompt, so both go together


def test_the_codex_command_line_expects_nobody_at_the_console(unforced, monkeypatch):
    """It runs at 08:05 from the scheduler: no colours in the text, nothing written, nothing asked."""
    monkeypatch.setattr(facts.shutil, "which", installed("codex"))

    argv, _ = facts.find_model_cli().invocation("instrukcja", "material", Path("odp.txt"))

    assert argv[-1] == "-"  # the prompt comes from stdin, so the material has no size limit
    for pair in (("--color", "never"), ("-s", "read-only")):
        assert argv[argv.index(pair[0]) + 1] == pair[1]
    assert "--output-last-message" in argv and facts.ANSWER_SLOT not in argv


def test_claude_wins_when_both_tools_are_installed(unforced, monkeypatch):
    monkeypatch.setattr(facts.shutil, "which", installed("claude", "codex"))

    assert facts.find_model_cli().name == "claude"
    assert [c.name for c in facts.model_clis()] == ["claude", "codex"]


def test_with_no_tool_at_all_the_error_says_what_was_looked_for(unforced, monkeypatch):
    monkeypatch.setattr(facts.shutil, "which", installed())

    assert facts.available_model_cli() is None
    with pytest.raises(facts.ModelMissing) as e:
        facts.find_model_cli()
    assert "claude" in str(e.value) and "codex" in str(e.value)


def test_the_environment_variable_overrides_the_order(monkeypatch):
    monkeypatch.setattr(facts.shutil, "which", installed("claude", "codex"))
    monkeypatch.setenv(facts.MODEL_CLI_ENV, "codex")

    assert facts.find_model_cli().name == "codex"


def test_a_forced_tool_that_is_missing_is_not_quietly_replaced(monkeypatch):
    """Falling back to the other one would hide a typo and bill a tool nobody asked for."""
    monkeypatch.setattr(facts.shutil, "which", installed("claude"))
    monkeypatch.setenv(facts.MODEL_CLI_ENV, "codex")

    with pytest.raises(facts.ModelMissing) as e:
        facts.find_model_cli()
    assert "codex" in str(e.value)


# ---------------------------------------------------------------- the answer coming back

# what `codex exec` really prints: the run of the session, with the answer nowhere to be parsed out
SESSION_NOISE = """[2026-09-17T08:05:00] OpenAI Codex v0.4.0
[2026-09-17T08:05:01] thinking: the user wants a list of facts
[2026-09-17T08:05:03] exec bash -lc 'ls' succeeded in 12ms
[2026-09-17T08:05:04] tokens used: 4321
"""


@pytest.fixture
def codex(unforced, monkeypatch):
    """`codex exec` stood in for: prints the session, writes the answer where it was told to.

    Codex is not installed on this machine, so the command line is checked by substitution — the
    point is what the file gets read for, not what the real tool answers.
    """
    monkeypatch.setattr(facts.shutil, "which", installed("codex"))
    seen: dict = {"answer": "- Firma użytkownika sprzedaje olejki na eBay.\n"}

    def fake_codex(argv, **kwargs):
        seen["path"] = Path(argv[argv.index("--output-last-message") + 1])
        if seen["answer"] is not None:
            seen["path"].write_text(seen["answer"], encoding="utf-8")
        return subprocess.CompletedProcess(argv, 0, SESSION_NOISE, "")

    monkeypatch.setattr(facts.subprocess, "run", fake_codex)
    return seen


def test_the_codex_answer_is_read_from_the_file_not_from_the_session(codex):
    answer = facts.ask_model("material")

    assert answer == "- Firma użytkownika sprzedaje olejki na eBay."
    assert "thinking" not in answer and "tokens used" not in answer  # the session stays out
    # and it goes straight into the parser, bullet and all
    assert [f.text for f in facts.parse_facts(answer)] == ["Firma użytkownika sprzedaje olejki na eBay."]


def test_the_temporary_answer_file_does_not_survive_the_call(codex):
    facts.ask_model("material")

    assert not codex["path"].exists()
    assert not codex["path"].parent.exists()  # the whole scratch directory goes with it


def test_a_codex_run_that_writes_no_answer_is_an_error(codex):
    codex["answer"] = None  # the file never appears — a silent empty harvest would look like "no facts"

    with pytest.raises(RuntimeError) as e:
        facts.ask_model("material")
    assert "--output-last-message" in str(e.value)
    assert "tokens used: 4321" in str(e.value)  # the tail of the session, to see what went wrong
    assert not codex["path"].exists()  # and it is cleaned up even when it blows up


def test_a_codex_run_that_writes_an_empty_answer_is_an_error(codex):
    codex["answer"] = "   \n"

    with pytest.raises(RuntimeError) as e:
        facts.ask_model("material")
    assert "--output-last-message" in str(e.value)


def test_the_dry_run_names_the_tool_it_would_use(waiting_room, unforced, monkeypatch):
    add(waiting_room, ago(1), "user", "cokolwiek, byle dluzsze niz prog")
    facts.write_marker(ago(2))
    monkeypatch.setattr(facts.shutil, "which", installed("codex"))

    r = facts.run(dry_run=True)

    assert r["status"] == "dry-run"
    assert (r["model_available"], r["model_cli"]) == (True, "codex")
