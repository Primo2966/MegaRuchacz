"""Use of a durable fact found in the transcripts by its own words — without the model."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

import pytest

from lore import facts, usage, verify

NOW = datetime.now(timezone.utc)

CASE_FACT = "Sprawa dyfuzora w Amazon UK ma numer 12345678901 i czeka na odpowiedź."
COMMON_FACT = "Cena kuriera wynosi tyle, ile podał użytkownik w rozmowie o wysyłce."
PAIR_FACT = "Robot startuje z Magazyn2 przez start.bat na serwerze w biurze."
PINNED_FACT = "Nie jest programistą."

RULES = f"""# Ustalenia

## Co wiem

### O użytkowniku

- {PINNED_FACT}
- {CASE_FACT}
- {COMMON_FACT}
- {PAIR_FACT}

### Bieżące

_(pusto)_
"""


def ago(hours: float) -> str:
    return facts.iso_utc(NOW - timedelta(hours=hours))


def automaton_wrote(*texts: str) -> None:
    facts.KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    with open(facts.KNOWLEDGE_DIR / facts.SOURCES_NAME, "a", encoding="utf-8", newline="\n") as f:
        for text in texts:
            f.write(f"- 2026-09-17 | awansowany | stala: O użytkowniku -> CLAUDE.md"
                    f" | z 2 rozmów; zmiana A-260917-1 | {text}\n")


@pytest.fixture
def knowledge(tmp_path, monkeypatch, environment):
    """Rules with three facts of the automaton and one pinned; transcripts in a sandbox."""
    directory = tmp_path / "wiedza"
    monkeypatch.setattr(facts, "KNOWLEDGE_DIR", directory)
    monkeypatch.setattr(facts, "RULES_PATH", tmp_path / "CLAUDE.md")
    monkeypatch.setattr(facts, "CODEX_RULES_PATH", tmp_path / "AGENTS.md")
    facts.RULES_PATH.write_text(RULES, encoding="utf-8")
    automaton_wrote(CASE_FACT, COMMON_FACT, PAIR_FACT)
    (directory / usage.MARKER_NAME).write_text(ago(2) + "\n", encoding="utf-8")
    return environment


def said_by_agent(env, *pieces, name: str = "rozmowa", ts: str | None = None, tool: dict | None = None):
    """A transcript where the agent writes `pieces` (and, optionally, calls a tool)."""
    directory = env.projects / "projekt"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{name}.jsonl"
    with open(path, "a", encoding="utf-8", newline="\n") as f:
        for piece in pieces:
            content = [{"type": "text", "text": piece}]
            if tool:
                content.append({"type": "tool_use", "name": "Bash", "input": tool})
            f.write(json.dumps({"type": "assistant", "sessionId": name, "timestamp": ts or ago(1),
                                "message": {"role": "assistant", "content": content}},
                               ensure_ascii=False) + "\n")
    return path


def used_lines() -> list[str]:
    path = facts.KNOWLEDGE_DIR / facts.SOURCES_NAME
    return [x for x in path.read_text(encoding="utf-8").splitlines() if f"| {facts.USED} |" in x]


def last_used(text: str) -> str | None:
    return verify.read_trail(facts.KNOWLEDGE_DIR / facts.SOURCES_NAME).last_used(verify.fact_key(text))


# ---------------------------------------------------------------- the words

def test_only_data_like_words_of_the_fact_alone_are_taken():
    words = usage.candidates("Sprawa 12345678901, ASIN B0TEST1234, cena 50,76 £, karta 1234,"
                             " plik start.bat na Magazyn2, marka MARKAX, PUŁAPKA, 2026-09-30,"
                             " m.in. kadzidła, serwer/komputer, „What steps have you taken already?”")
    assert words["12345678901"] == "strong" and words["B0TEST1234"] == "strong"
    assert words["What steps have you taken already?"] == "strong"
    assert words["start.bat"] == words["Magazyn2"] == words["MARKAX"] == "weak"
    assert words["serwer/komputer"] == "weak"  # prose with a slash: never strong, however long
    for prose_or_chance in ("Sprawa", "cena", "50,76", "5025", "PUŁAPKA", "2026-09-30", "m.in",
                            "kadzidła", "karta"):
        assert prose_or_chance not in words


def test_a_word_standing_elsewhere_in_the_rules_is_not_the_facts_own():
    own = usage._flat("- Sprawa 12345678901 dotyczy MegaRuchacz.")
    whole = usage._flat("- Sprawa 12345678901 dotyczy MegaRuchacz.\n- MegaRuchacz ma moduły.")
    words = usage.signatures("Sprawa 12345678901 dotyczy MegaRuchacz.", own, whole)
    assert [w.word for w in words] == ["12345678901"]


# ---------------------------------------------------------------- (a) a characteristic word is a use

def test_the_agent_writing_the_facts_own_number_is_a_use(knowledge):
    said_by_agent(knowledge, "Sprawdziłem: sprawa 12345678901 nadal czeka na SDS.", ts=ago(1))

    r = usage.run()

    assert list(r["used"]) == [CASE_FACT]
    [line] = used_lines()
    assert line.endswith(f"| {CASE_FACT}") and "słowa: 12345678901" in line
    assert f"{facts.SESSIONS_FIELD} rozmowa" in line
    assert last_used(CASE_FACT) == datetime.now().strftime("%Y-%m-%d")
    assert (facts.KNOWLEDGE_DIR / usage.MARKER_NAME).read_text(encoding="utf-8").strip() > ago(1)


def test_a_tool_call_carrying_the_word_is_a_use_too(knowledge):
    said_by_agent(knowledge, "Już sprawdzam.", tool={"command": "gh issue view 12345678901"})

    assert list(usage.run()["used"]) == [CASE_FACT]


def test_two_weak_words_together_are_a_use_one_alone_is_not(knowledge):
    said_by_agent(knowledge, "Odpalam start.bat i patrzę w log.", name="jedno")
    assert usage.run()["used"] == {}

    said_by_agent(knowledge, "Na Magazyn2 uruchamiam start.bat.", name="dwa",
                  ts=facts.iso_utc(datetime.now(timezone.utc)))  # after the first pass
    assert list(usage.run()["used"]) == [PAIR_FACT]


def test_the_model_and_the_keywords_both_count_and_the_later_day_decides(knowledge):
    facts.note_sources([facts.Fact(CASE_FACT, "stala")], "rozmowy 2026-01-01..2026-01-01",
                       "2026-01-01", ["stara"], event=facts.USED)  # what the model marked long ago
    said_by_agent(knowledge, "Sprawa 12345678901 — nic nowego.")

    usage.run()

    assert last_used(CASE_FACT) == datetime.now().strftime("%Y-%m-%d")


def test_only_what_came_after_the_marker_counts_and_nothing_is_read_twice(knowledge):
    path = said_by_agent(knowledge, "Sprawa 12345678901 z przedwczoraj.", ts=ago(48))
    assert usage.run()["used"] == {}  # older than the marker

    with open(path, "a", encoding="utf-8", newline="\n") as f:  # the same file grows
        f.write(json.dumps({"type": "assistant", "sessionId": "rozmowa", "timestamp": ago(0),
                            "message": {"role": "assistant", "content": "Nic o sprawach."}}) + "\n")
    r = usage.run()
    assert r["used"] == {} and r["records"] == 1  # read from the saved offset: the new line only


def test_editing_the_rules_is_upkeep_not_use(knowledge):
    said_by_agent(knowledge, "Poprawiam wiedzę.",
                  tool={"file_path": "C:\\Users\\<uzytkownik>\\.claude\\CLAUDE.md", "new_string": CASE_FACT})

    assert usage.run()["used"] == {}


def test_a_dry_run_reports_and_writes_nothing(knowledge):
    said_by_agent(knowledge, "Sprawa 12345678901.")
    marker = (facts.KNOWLEDGE_DIR / usage.MARKER_NAME).read_text(encoding="utf-8")

    r = usage.run(dry_run=True)

    assert list(r["used"]) == [CASE_FACT] and used_lines() == []
    assert (facts.KNOWLEDGE_DIR / usage.MARKER_NAME).read_text(encoding="utf-8") == marker
    assert not (facts.KNOWLEDGE_DIR / usage.OFFSETS_NAME).exists()


def test_the_daily_harvest_runs_the_keyword_check(knowledge, monkeypatch, tmp_path):
    monkeypatch.setattr(facts, "DB_PATH", tmp_path / "lore.db")
    monkeypatch.setattr(facts, "MARKER_PATH", facts.KNOWLEDGE_DIR / ".ostatnie-wyciaganie")
    monkeypatch.setattr(facts, "MARKER_ID_PATH", facts.KNOWLEDGE_DIR / ".ostatnie-wyciaganie-id")
    monkeypatch.setattr(facts, "DAY_ZERO_PATH", facts.KNOWLEDGE_DIR / ".dzien-zero-wyboru")
    monkeypatch.setattr(facts, "CANDIDATES_PATH", facts.KNOWLEDGE_DIR / "kandydaci.md")
    said_by_agent(knowledge, "Sprawa 12345678901 — wysłane.")

    assert facts.main(argv=[]) == 0  # no messages of the user: the model is not even called

    assert last_used(CASE_FACT) == datetime.now().strftime("%Y-%m-%d")


# ---------------------------------------------------------------- (b) a common word is not

def test_a_common_word_of_the_fact_is_not_a_use(knowledge):
    said_by_agent(knowledge, "Cena kuriera wynosi tyle, ile podał użytkownik w rozmowie o wysyłce?"
                             " Sprawa Robot startuje na serwerze w biurze.")

    r = usage.run()

    assert r["used"] == {} and used_lines() == []


# ---------------------------------------------------------------- (c) a fact without such words

def test_a_fact_without_characteristic_words_is_left_to_the_model(knowledge, capsys):
    said_by_agent(knowledge, "Nic ciekawego.")

    r = usage.run()
    usage.report(r)

    assert r["without_words"] == 1 and r["with_words"] == 2  # COMMON_FACT: no word of its own
    assert "only the model's check" in capsys.readouterr().err


def test_no_fact_of_the_automaton_reads_nothing_and_says_so(knowledge, capsys):
    (facts.KNOWLEDGE_DIR / facts.SOURCES_NAME).unlink()  # every entry pinned now
    said_by_agent(knowledge, "Sprawa 12345678901.")

    r = usage.run()
    usage.report(r)

    assert r["checked"] == 0 and r["files"] == 0 and r["bytes"] == 0
    assert "nothing to look for" in capsys.readouterr().err


def test_a_failing_check_does_not_stop_the_harvest_and_is_said(knowledge, monkeypatch, capsys):
    def broken(**_):
        raise RuntimeError("zepsute")
    monkeypatch.setattr(usage, "run", broken)

    facts._use_by_keyword(False)

    assert "UWAGA: the use check by keyword failed" in capsys.readouterr().err


# ---------------------------------------------------------------- (d) negative probes

def test_probe_the_use_test_notices_the_check_switched_off(knowledge, monkeypatch, tmp_path):
    """The same as test_the_daily_harvest_runs_the_keyword_check, with the mechanism removed: the
    use must then be missing — otherwise that test proves nothing."""
    monkeypatch.setattr(facts, "_use_by_keyword", lambda dry_run: None)
    monkeypatch.setattr(facts, "DB_PATH", tmp_path / "lore.db")
    monkeypatch.setattr(facts, "MARKER_PATH", facts.KNOWLEDGE_DIR / ".ostatnie-wyciaganie")
    monkeypatch.setattr(facts, "MARKER_ID_PATH", facts.KNOWLEDGE_DIR / ".ostatnie-wyciaganie-id")
    monkeypatch.setattr(facts, "DAY_ZERO_PATH", facts.KNOWLEDGE_DIR / ".dzien-zero-wyboru")
    monkeypatch.setattr(facts, "CANDIDATES_PATH", facts.KNOWLEDGE_DIR / "kandydaci.md")
    said_by_agent(knowledge, "Sprawa 12345678901 — wysłane.")

    facts.main(argv=[])

    assert last_used(CASE_FACT) is None


def test_probe_without_the_data_only_rule_a_common_word_would_count(knowledge, monkeypatch):
    """The probe of (b): with every longer word taken as a signature, the plain sentence of
    test_a_common_word_of_the_fact_is_not_a_use would count as a use."""
    monkeypatch.setattr(usage, "kind", lambda token: "strong" if len(token) > 4 else None)
    said_by_agent(knowledge, "Cena kuriera wynosi tyle, ile podał użytkownik.")

    assert usage.run()["used"] != {}


def test_probe_a_single_weak_word_would_count_without_the_pair_rule(knowledge, monkeypatch):
    monkeypatch.setattr(usage.Watch, "hits",
                        lambda self, hay: [s for s in self.words if usage._count(s.needle, hay)])
    said_by_agent(knowledge, "Odpalam start.bat i patrzę w log.")

    assert list(usage.run()["used"]) == [PAIR_FACT]
