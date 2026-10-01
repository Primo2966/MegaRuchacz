"""Use of a durable fact found in the transcripts by its own words — without the model."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone

import pytest

from lore import facts, index, usage, verify

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


# ---------------------------------------------------------------- a CURRENT fact used elsewhere
#
# The user's decision (2026-10-01): a current fact the agent uses on another day, in a conversation
# it did not come out of, counts as the second conversation a promotion needs. lore.verify decides
# (Trail.confirmations); here — that the words find it and that the USED line carries what it needs.

CURRENT_FACT = "Zgłoszenie DG na amazon.de ma numer 10987654321."
WEAK_CURRENT = "Robot A+ startuje z Magazyn3 przez uruchom.bat w biurze."
SHORT_LIVED = "Dziś sprawa 99887766554 czeka na kuriera."
HEARD_ON = "2026-09-20"
SOURCE_SESSION = "rozmowa-zrodlo"
CODEX_UUID = "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b"


def harvested(text: str, day: str = HEARD_ON, label: str = "stala/firma",
              session: str = SOURCE_SESSION) -> None:
    """Heard once in `session` and written into the current layer — as the automaton does."""
    layer, _, detail = label.partition("/")
    facts.note_sources([facts.Fact(text, layer, detail or facts.DEFAULT_SECTION)],
                       f"rozmowy {day}..{day}", day, [session])
    with open(facts.KNOWLEDGE_DIR / facts.SOURCES_NAME, "a", encoding="utf-8", newline="\n") as f:
        f.write(f"- {day} | {verify.WRITTEN} | biezaca -> CLAUDE.md | wpisany sam | {text}\n")


def with_current(*entries: tuple[str, str]) -> None:
    body = "".join(f"- [{day}] {text}\n" for text, day in entries)
    facts.RULES_PATH.write_text(RULES.replace("### Bieżące\n\n_(pusto)_\n", f"### Bieżące\n\n{body}"),
                                encoding="utf-8")


def confirmations(text: str) -> int:
    return verify.read_trail(facts.KNOWLEDGE_DIR / facts.SOURCES_NAME).confirmations(
        verify.fact_key(text))


@pytest.fixture
def current(knowledge):
    with_current((CURRENT_FACT, HEARD_ON), (WEAK_CURRENT, HEARD_ON), (SHORT_LIVED, HEARD_ON))
    harvested(CURRENT_FACT)
    harvested(WEAK_CURRENT)
    harvested(SHORT_LIVED, label="biezaca")
    return knowledge


def test_the_current_facts_that_may_be_promoted_are_looked_for_too(current):
    with_words, _ = usage.watched()
    texts = [w.text for w in with_words]

    assert CURRENT_FACT in texts and WEAK_CURRENT in texts
    assert SHORT_LIVED not in texts  # the model called it short-lived: never promoted, use or not


# (a) another day, another conversation, a strong word -> confirmed

def test_a_current_fact_used_by_its_word_on_another_day_elsewhere_is_confirmed(current):
    said_by_agent(current, "Sprawa 10987654321 na DE już sklasyfikowana.", name="inna-rozmowa")

    r = usage.run()

    assert CURRENT_FACT in r["used"]
    [line] = [x for x in used_lines() if x.endswith(CURRENT_FACT)]
    assert facts.USED_WEAK not in line and f"{facts.SESSIONS_FIELD} inna-rozmowa" in line
    assert confirmations(CURRENT_FACT) == 2  # heard once + used elsewhere = promotion


# (b) its own conversation, or the same day -> recorded as a use, but not confirmed

def test_a_current_fact_echoed_in_its_own_conversation_is_not_confirmed(current):
    said_by_agent(current, "Zapisuję: sprawa 10987654321.", name=SOURCE_SESSION)

    assert CURRENT_FACT in usage.run()["used"]  # a use — it is recorded
    assert confirmations(CURRENT_FACT) == 1  # but the fact's own conversation adds nothing


def test_a_current_fact_used_on_the_day_it_was_heard_is_not_confirmed(knowledge):
    today = datetime.now().strftime("%Y-%m-%d")
    with_current((CURRENT_FACT, today))
    harvested(CURRENT_FACT, day=today)
    said_by_agent(knowledge, "Sprawa 10987654321 czeka.", name="inna-rozmowa")

    assert CURRENT_FACT in usage.run()["used"]
    assert confirmations(CURRENT_FACT) == 1  # another conversation, but the same day


def test_a_current_fact_found_by_weak_words_only_is_kept_but_not_confirmed(current):
    said_by_agent(current, "Na Magazyn3 odpalam uruchom.bat.", name="inna-rozmowa")

    assert WEAK_CURRENT in usage.run()["used"]
    [line] = [x for x in used_lines() if x.endswith(WEAK_CURRENT)]
    assert facts.USED_WEAK in line  # written down as a use, so it would keep a durable fact awake
    assert last_used(WEAK_CURRENT) == datetime.now().strftime("%Y-%m-%d")
    assert confirmations(WEAK_CURRENT) == 1  # but two weak words never promote — usage rule 5


def test_strong_and_weak_hits_of_one_fact_get_a_line_each(knowledge):
    said_by_agent(knowledge, "Na Magazyn2 uruchamiam start.bat.", name="slabe")
    said_by_agent(knowledge, "Sprawa 12345678901.", name="mocne")
    combined = "Robot z Magazyn2 przez start.bat, sprawa 12345678901."
    flat = usage._flat(combined)
    watch = usage.Watch(combined, usage.signatures(combined, flat, flat))

    usage.note(usage.scan([watch], ago(2), {}).found)

    lines = [x for x in used_lines() if x.endswith(combined)]
    assert len(lines) == 2
    [weak] = [x for x in lines if facts.USED_WEAK in x]
    [strong] = [x for x in lines if facts.USED_WEAK not in x]
    assert f"{facts.SESSIONS_FIELD} slabe" in weak and f"{facts.SESSIONS_FIELD} mocne" in strong


def said_in_codex(text: str) -> None:
    """A Codex transcript of the conversation CODEX_UUID, where the agent writes `text`."""
    path = (index.CODEX_SESSIONS_DIR / "2026" / "10" / "01"
            / f"rollout-2026-10-01T10-00-00-{CODEX_UUID}.jsonl")
    path.parent.mkdir(parents=True, exist_ok=True)
    rec = {"type": "response_item", "timestamp": ago(1),
           "payload": {"type": "message", "role": "assistant",
                       "content": [{"type": "output_text", "text": text}]}}
    path.write_text(json.dumps(rec, ensure_ascii=False) + "\n", encoding="utf-8")


def codex_echo() -> int:
    """The fact heard in a Codex conversation and echoed there by the agent the next day."""
    with_current((CURRENT_FACT, HEARD_ON))
    harvested(CURRENT_FACT, session=CODEX_UUID)  # the harvest names it by session_meta's id
    said_in_codex("Zapisuję: sprawa 10987654321.")
    assert CURRENT_FACT in usage.run()["used"]
    return confirmations(CURRENT_FACT)


def test_a_transcript_is_named_like_the_harvest_names_its_conversation(environment):
    codex = index.CODEX_SESSIONS_DIR / "2026" / f"rollout-2026-10-01T10-00-00-{CODEX_UUID}.jsonl"

    assert usage.session_of(codex) == CODEX_UUID
    assert usage.session_of(environment.projects / "projekt" / "abc.jsonl") == "abc"
    assert usage.session_of(environment.projects / "projekt" / "abc" / "subagents" / "agent-1.jsonl") == "abc"


def test_an_echo_in_its_own_codex_conversation_is_not_confirmed(knowledge):
    assert codex_echo() == 1


# (d) negative probes

def test_probe_named_by_the_file_the_codex_echo_would_confirm(knowledge, monkeypatch):
    """The probe of the test above: named after the file, as before 2026-10-01, the Codex
    conversation would not match the one the harvest knows and its echo would confirm the fact."""
    monkeypatch.setattr(usage, "session_of", lambda path: path.stem)

    assert codex_echo() == 2


def test_probe_without_the_weak_mark_two_weak_words_would_promote(current, monkeypatch):
    """The probe of the weak-words test: a line written without the mark lore.verify looks for
    counts as a confirmation — so that mark, and nothing else, is what stops the promotion."""
    monkeypatch.setattr(facts, "USED_WEAK", "znacznik, którego verify nie zna")
    said_by_agent(current, "Na Magazyn3 odpalam uruchom.bat.", name="inna-rozmowa")

    usage.run()

    assert confirmations(WEAK_CURRENT) == 2


def test_probe_without_the_current_layer_nothing_would_be_confirmed(current, monkeypatch):
    """The probe of (a): looking only at the durable layer, as before 2026-10-01, the current fact's
    use is never found — so (a) proves the current layer is now looked at."""
    monkeypatch.setattr(verify.Trail, "use_matters",
                        lambda self, e: not e.current and self.is_auto(e))
    said_by_agent(current, "Sprawa 10987654321 na DE już sklasyfikowana.", name="inna-rozmowa")

    assert CURRENT_FACT not in usage.run()["used"]
    assert confirmations(CURRENT_FACT) == 1
