"""Daily harvest of facts: what gets picked, what gets cut off and what lands in the waiting room."""

from __future__ import annotations

import json
import math
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
    monkeypatch.setattr(facts, "MARKER_ID_PATH", knowledge / ".ostatnie-wyciaganie-id")
    monkeypatch.setattr(facts, "DAY_ZERO_PATH", knowledge / ".dzien-zero")
    monkeypatch.setattr(facts, "CANDIDATES_PATH", knowledge / "kandydaci.md")
    monkeypatch.setattr(facts, "RULES_PATH", tmp_path / "CLAUDE.md")
    monkeypatch.setattr(facts, "DB_PATH", tmp_path / "lore.db")
    facts.start_pass()  # the pass accumulator is module state — no test may inherit another's calls
    return environment


def add(environment, ts: str, role: str, text: str, line: int = 1, landed: str | None = None) -> int:
    """One chunk. `landed` is when it entered the database — by default the moment it was said."""
    cur = environment.conn.execute(
        "INSERT INTO chunks(project, session, file, line, part, ts, role, text, indexed_at)"
        " VALUES (?,?,?,?,?,?,?,?,?)",
        ("test-project", "test-session", "test.jsonl", line, 0, ts, role, text,
         ts if landed is None else landed),
    )
    return cur.lastrowid


def set_day_zero(ts: str) -> None:
    """Draws the day-zero line by hand, so a test can say what happened before and after it."""
    facts.KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    facts.DAY_ZERO_PATH.write_text(ts + "\n", encoding="utf-8")


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
    # parts of one turn share a timestamp — half a turn read out of context is worth less to the
    # model, so the cut is pushed back onto the boundary
    for i in range(40):
        add(waiting_room, ago(40 - i // 2), "user", f"{i:03d} " + "x" * 2000, line=i + 1)
    facts.write_marker(ago(48))

    material = facts.collect(waiting_room.conn, facts.since_marker())

    assert len(material.texts) % 2 == 0  # both parts of the last turn are in
    assert material.pending == 40 - len(material.texts)
    assert material.missing() == 0  # and what did not fit is waiting, not gone


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


# ---------------------------------------------------------------- the indexing axis

def test_a_chunk_indexed_after_the_marker_passed_its_date_is_still_read(waiting_room):
    """The whole point of the axis: `ts` says when it was said, indexing happens ten minutes later.

    With the old 'ts > marker' rule such a chunk fell out of the window the moment it was written
    and nobody ever heard of it again.
    """
    set_day_zero(ago(100))
    add(waiting_room, ago(5), "user", "pierwsza rozmowa")
    facts.run(ask=answers(), conn=waiting_room.conn)
    assert facts.since_marker().stamp == ago(5)

    # the indexer catches up with a turn that was SAID before the marker
    add(waiting_room, ago(6), "user", "spozniony transkrypt", landed=ago(1))
    seen = []
    r = facts.run(ask=recorder(seen), conn=waiting_room.conn)

    assert r["chunks"] == 1 and "spozniony transkrypt" in seen[0]


def test_a_chunk_that_lands_behind_the_marker_is_caught_by_its_id_and_reported(waiting_room):
    """Backdated on both axes — a hand edit, an import. The id is the second door, and the fact
    that it had to be used is a number the user gets to see."""
    set_day_zero(ago(100))
    add(waiting_room, ago(5), "user", "pierwsza rozmowa")
    facts.run(ask=answers(), conn=waiting_room.conn)

    add(waiting_room, ago(9), "user", "wpisane wstecz, obiema datami")
    seen = []
    r = facts.run(ask=recorder(seen), conn=waiting_room.conn)

    assert r["chunks"] == 1 and "wpisane wstecz" in seen[0]
    assert r["late"] == 1
    assert facts.read_cost()["spoznione"] == "1"


def test_a_cut_inside_one_indexing_pass_leaves_nothing_behind(waiting_room):
    """One pass writes all of its chunks under a single stamp. Without the id in the marker,
    everything after the cut would sit below it for ever — this is the same hole, one level down."""
    set_day_zero(ago(100))
    for i in range(60):
        add(waiting_room, ago(60 - i), "user", f"{i:03d} " + "x" * 2000, line=i + 1, landed=ago(1))
    facts.write_marker(ago(90))
    seen = []

    results = facts.catch_up(runs=10, ask=recorder(seen), conn=waiting_room.conn)

    assert [n for material in seen for n in numbers(material)] == [f"{i:03d}" for i in range(60)]
    assert results[-1]["pending"] == 0
    assert len(seen) > 1  # it really was cut inside the pass


def test_a_chunk_with_no_indexing_stamp_is_not_invisible(waiting_room):
    """Written by an older indexer or by hand: the empty default falls back to its own date instead
    of dropping out of every window there will ever be."""
    waiting_room.conn.execute(
        "INSERT INTO chunks(project, session, file, line, part, ts, role, text)"
        " VALUES ('p','s','f',1,0,?,'user','kawalek bez znacznika zaindeksowania')", (ago(1),))
    facts.write_marker(ago(2))
    set_day_zero(ago(100))

    material = facts.collect(waiting_room.conn, facts.since_marker(), facts.day_zero())

    assert len(material.texts) == 1


def test_a_marker_from_before_the_id_existed_does_not_read_the_archive_again(waiting_room):
    """The upgrade itself: a marker file holding a date and nothing else, and an archive whose rows
    got `indexed_at = ts` from the migration. The first run after it must read the new material only."""
    for i in range(30):
        add(waiting_room, ago(50 + i), "user", f"stara rozmowa numer {i} " * 20, line=i + 1)
    add(waiting_room, ago(2), "user", "nowa rozmowa po aktualizacji")
    facts.KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    facts.MARKER_PATH.write_text(ago(3) + "\n", encoding="utf-8")  # the old format: a date alone
    assert not facts.MARKER_ID_PATH.exists()
    seen = []

    r = facts.run(ask=recorder(seen), conn=waiting_room.conn)

    assert r["chunks"] == 1 and "nowa rozmowa po aktualizacji" in seen[0]
    assert "stara rozmowa" not in seen[0]
    assert facts.MARKER_ID_PATH.exists()  # from here on the marker carries the id as well


# ---------------------------------------------------------------- day zero

def test_a_fresh_install_does_not_swallow_the_archive_it_found(waiting_room):
    """Three years of transcripts, pulled into the database within the hour of the install. Day zero
    is drawn on the first run, and everything indexed before it stays where it is."""
    for i in range(50):
        add(waiting_room, ago(24 * 30 * (i + 1)), "user", f"stara rozmowa numer {i} " * 20,
            line=i + 1, landed=ago(0.2))
    assert not facts.MARKER_PATH.exists() and not facts.DAY_ZERO_PATH.exists()

    r = facts.run(ask=answers("nic z archiwum nie powinno wyjsc"), conn=waiting_room.conn)

    assert (r["status"], r["chunks"]) == ("no-material", 0)
    assert not facts.CANDIDATES_PATH.exists()
    assert r["before_zero"] == 50  # counted and said out loud, not swallowed in silence
    assert facts.read_cost()["sprzed_dnia_zero"] == "50"
    assert facts.DAY_ZERO_PATH.exists()


def test_day_zero_of_a_running_install_is_the_read_marker_so_the_backlog_survives(waiting_room):
    """An install that has been harvesting for weeks: drawing the line at "now" would throw away
    everything still waiting at the marker."""
    add(waiting_room, ago(3), "user", "wczorajsza rozmowa, jeszcze nieprzeczytana")
    facts.write_marker(ago(10))

    r = facts.run(ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)

    assert facts.DAY_ZERO_PATH.read_text(encoding="utf-8").strip() == ago(10)
    assert r["chunks"] == 1


def test_day_zero_is_drawn_once_and_then_left_alone(waiting_room):
    set_day_zero(ago(30))

    assert facts.day_zero() == ago(30)
    facts.write_marker(ago(1))
    assert facts.day_zero() == ago(30)  # a marker moving later does not move the line


def test_a_chunk_indexed_after_day_zero_counts_even_though_it_was_said_before_it(waiting_room):
    """The other side of the same coin: old by its date, new to this database."""
    set_day_zero(ago(5))
    facts.write_marker(ago(5))
    add(waiting_room, ago(20), "user", "powiedziane przed instalacja, zaindeksowane po niej",
        landed=ago(1))
    seen = []

    r = facts.run(ask=recorder(seen), conn=waiting_room.conn)

    assert r["chunks"] == 1 and "przed instalacja" in seen[0]
    assert r["before_zero"] == 0


# ---------------------------------------------------------------- the controls of one pass

def test_the_run_says_how_much_was_in_range_and_how_much_the_model_saw(waiting_room):
    set_day_zero(ago(100))
    add(waiting_room, ago(3), "user", "pierwsza wiadomosc uzytkownika")
    add(waiting_room, ago(3), "tool", "[tool: Bash] ls -la")
    add(waiting_room, ago(2), "user", "druga wiadomosc uzytkownika")
    facts.write_marker(ago(9))

    r = facts.run(ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)

    assert (r["in_range"], r["candidates"], r["chunks"]) == (3, 2, 2)
    assert (r["missing"], r["late"]) == (0, 0)
    assert facts.read_cost()["pominiete"] == "0"


def test_the_backlog_is_not_counted_as_material_that_went_missing(waiting_room):
    """A false alarm teaches people to ignore alarms: what waits for the next run is not lost."""
    backlog(waiting_room, 40)
    set_day_zero(ago(100))

    r = facts.run(ask=answers(), conn=waiting_room.conn)

    assert r["pending"] > 0 and r["missing"] == 0


def test_the_cycle_can_tell_how_many_messages_were_read_and_from_when(waiting_room):
    """The cycle says "przeczytane X wiadomości z okresu od-do" without paying for a model call."""
    set_day_zero(ago(100))
    add(waiting_room, ago(5), "user", "pierwsza wiadomosc")
    add(waiting_room, ago(3), "user", "druga wiadomosc")
    facts.write_marker(ago(9))

    facts.run(ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)
    saved = facts.read_cost()

    assert saved["wiadomosci"] == "2"
    assert saved["zakres_od"] == facts.ts_to_local(ago(5))
    assert saved["zakres_do"] == facts.ts_to_local(ago(3))


def test_the_messages_of_several_passes_add_up_and_the_range_grows(waiting_room):
    backlog(waiting_room, 60)
    set_day_zero(ago(100))

    results = facts.catch_up(runs=10, ask=answers(), conn=waiting_room.conn)
    saved = facts.read_cost()

    assert saved["wiadomosci"] == str(sum(r["chunks"] for r in results))
    assert saved["zakres_od"] == facts.ts_to_local(ago(60))  # the oldest of the day
    assert saved["zakres_do"] == facts.ts_to_local(ago(1))  # and the newest


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


def test_an_entry_rejected_by_the_verifier_is_not_harvested_again(waiting_room):
    """'[!]' and '[?]' are boxes lore.verify writes — an entry it flagged is still known here."""
    facts.KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    facts.CANDIDATES_PATH.write_text(
        "- [!] [2026-09-16] (stala/praca) Użytkownik pracuje na Windowsie. (nie znaleziono: X)\n"
        "- [?] [2026-09-16] Redis nie jest potrzebny. (sporne: przeczy wpisowi „X”)\n",
        encoding="utf-8")
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))

    r = facts.run(ask=answers("Użytkownik pracuje na Windowsie.", "Redis nie jest potrzebny."),
                  conn=waiting_room.conn)

    assert r["added"] == []


def test_a_fact_standing_in_the_current_layer_is_not_proposed_again(waiting_room):
    # "### Bieżące" carries the date inside the entry; taken for part of the fact, the same
    # sentence would look new every single day
    facts.RULES_PATH.write_text("# Ustalenia\n- [2026-09-16] Trwa przenoszenie magazynu.\n",
                                encoding="utf-8")
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))

    r = facts.run(ask=answers("Trwa przenoszenie magazynu."), conn=waiting_room.conn)

    assert r["added"] == []


def test_a_dormant_fact_heard_again_is_a_sighting_not_a_new_candidate(waiting_room):
    """Put to sleep by lore.verify, it is still known here: the repetition is what wakes it up."""
    facts.KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    (facts.KNOWLEDGE_DIR / facts.DORMANT_NAME).write_text(
        "# Uśpione fakty\n\n- 2026-12-20 | O użytkowniku | U-261220-1 | Użytkownik pracuje na"
        " Windowsie.\n", encoding="utf-8")
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))

    r = facts.run(ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)

    assert r["added"] == []
    assert "| wyłowiony ponownie |" in trail(None) and "Użytkownik pracuje na Windowsie." in trail(None)


def test_a_waiting_entry_with_its_note_is_not_proposed_again(waiting_room):
    # the note of what it contradicts is lore.verify's, not part of the fact
    facts.RULES_PATH.write_text("# Ustalenia\n- [2026-09-16] Redis jest potrzebny na tej maszynie."
                                " (przeczy: „Redis nie jest potrzebny na tej maszynie.”)\n",
                                encoding="utf-8")
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))

    r = facts.run(ask=answers("Redis jest potrzebny na tej maszynie."), conn=waiting_room.conn)

    assert r["added"] == []


# ---------------------------------------------------------------- where a fact came from

def trail(path) -> str:
    return (facts.KNOWLEDGE_DIR / facts.SOURCES_NAME).read_text(encoding="utf-8")


def test_the_harvest_writes_down_which_conversations_a_fact_came_from(waiting_room):
    """The user's own question: 'I don't know where this came from'. It has to be answerable."""
    waiting_room.conn.execute(
        "INSERT INTO chunks(project, session, file, line, part, ts, role, text)"
        " VALUES (?,?,?,?,?,?,?,?)",
        ("test-project", "rozmowa-o-ebayu", "a.jsonl", 1, 0, ago(1), "user", "cokolwiek"))
    facts.write_marker(ago(2))

    facts.run(ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)

    line = trail(facts.KNOWLEDGE_DIR)
    assert "wyłowiony" in line and "rozmowa-o-ebayu" in line
    assert "Użytkownik pracuje na Windowsie." in line


def test_the_trail_is_not_written_into_the_waiting_room_entry(waiting_room):
    """It is kept apart on purpose — the layer it feeds is sent with every session."""
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))

    facts.run(ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)

    assert "test-session" not in facts.CANDIDATES_PATH.read_text(encoding="utf-8")


def test_a_dry_run_leaves_no_trail(waiting_room):
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))

    facts.run(dry_run=True, ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)

    assert not (facts.KNOWLEDGE_DIR / facts.SOURCES_NAME).exists()


def test_a_fact_already_standing_in_the_rules_is_not_proposed(waiting_room):
    facts.RULES_PATH.write_text("# Ustalenia\n- Użytkownik pracuje na Windowsie!\n", encoding="utf-8")
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))

    r = facts.run(ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)

    assert r["added"] == []
    assert not facts.CANDIDATES_PATH.exists()


# ---------------------------------------------------------------- repetition: the evidence for promotion

def said_in(environment, session: str, ts: str, text: str = "cokolwiek") -> None:
    """One user chunk of the given conversation."""
    environment.conn.execute(
        "INSERT INTO chunks(project, session, file, line, part, ts, role, text, indexed_at)"
        " VALUES (?,?,?,?,?,?,?,?,?)",
        ("test-project", session, f"{session}.jsonl", 1, 0, ts, "user", text, ts))


def test_the_trail_names_every_conversation_of_the_batch(waiting_room):
    """The readable part stops at MAX_NAMED_SESSIONS; the evidence needs all of them."""
    names = [f"rozmowa-{n}" for n in range(facts.MAX_NAMED_SESSIONS + 2)]
    for n, name in enumerate(names):
        said_in(waiting_room, name, ago(5 - n * 0.1))
    facts.write_marker(ago(6))

    facts.run(ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)

    line = [x for x in trail(facts.KNOWLEDGE_DIR).splitlines() if "| wyłowiony |" in x][0]
    assert "i 2 innych" in line  # the readable pointer is unchanged
    assert f"| {facts.SESSIONS_FIELD} {' '.join(names)} |" in line


def test_a_fact_heard_again_leaves_a_sighting_but_no_second_entry(waiting_room):
    said_in(waiting_room, "rozmowa-a", ago(5))
    facts.write_marker(ago(6))
    facts.run(ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)
    said_in(waiting_room, "rozmowa-b", ago(1))

    r = facts.run(ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)

    assert r["added"] == []
    assert entries(facts.CANDIDATES_PATH) == ["Użytkownik pracuje na Windowsie."]
    again = [x for x in trail(facts.KNOWLEDGE_DIR).splitlines() if "| wyłowiony ponownie |" in x]
    assert len(again) == 1 and f"{facts.SESSIONS_FIELD} rozmowa-b |" in again[0]


def test_a_fact_repeated_inside_one_answer_is_one_sighting(waiting_room):
    said_in(waiting_room, "rozmowa-a", ago(1))
    facts.write_marker(ago(2))

    facts.run(ask=answers("Użytkownik pracuje na Windowsie.", "Użytkownik pracuje na Windowsie!"),
              conn=waiting_room.conn)

    assert trail(facts.KNOWLEDGE_DIR).count("Użytkownik pracuje na Windowsie") == 1


PIPELINE_RULES = """# Ustalenia

## Co wiem

### O użytkowniku

- Nie jest programistą.

### Bieżące

_(pusto)_

### Dane referencyjne

_(pusto)_
"""


def test_harvest_and_verification_together_promote_only_after_a_second_conversation(
        waiting_room, tmp_path, monkeypatch):
    """The whole way, with a stand-in model: once -> current; again in the SAME conversation ->
    still current; in ANOTHER conversation -> durable, and gone from the current layer."""
    from lore import verify
    monkeypatch.setattr(facts, "CODEX_RULES_PATH", tmp_path / "brak-codexa" / "AGENTS.md")
    monkeypatch.setattr(verify, "KNOWLEDGE_DIR", facts.KNOWLEDGE_DIR)
    monkeypatch.setattr(verify, "CANDIDATES_PATH", facts.CANDIDATES_PATH)
    monkeypatch.setattr(verify, "BACKUP_DIR", facts.KNOWLEDGE_DIR / "kopie")
    monkeypatch.setattr(verify, "INSTRUCTION_PATHS", (facts.RULES_PATH,))
    facts.RULES_PATH.write_text(PIPELINE_RULES, encoding="utf-8")
    fact = "Użytkownik pracuje na dwóch maszynach, biurowej i domowej."
    model = sorted_answer({"tresc": fact, "warstwa": "stala", "podsekcja": "uzytkownik"})

    def durable() -> str:
        return facts.RULES_PATH.read_text(encoding="utf-8").split("### Bieżące")[0]

    def current() -> str:
        return facts.RULES_PATH.read_text(encoding="utf-8").split("### Bieżące")[1]

    said_in(waiting_room, "rozmowa-pierwsza", ago(5))
    facts.write_marker(ago(6))
    facts.run(ask=model, conn=waiting_room.conn)
    verify.run()
    assert fact in current() and fact not in durable()

    said_in(waiting_room, "rozmowa-pierwsza", ago(3))  # the same conversation, a later batch
    facts.run(ask=model, conn=waiting_room.conn)
    assert verify.run()["promoted"] == []
    assert fact in current() and fact not in durable()

    said_in(waiting_room, "rozmowa-druga", ago(1))
    facts.run(ask=model, conn=waiting_room.conn)
    r = verify.run()

    assert r["promoted"] == [fact]
    assert f"- {fact}" in durable() and fact not in current()


def test_the_marker_moves_only_after_a_real_run(waiting_room):
    add(waiting_room, ago(1), "user", "cokolwiek")
    facts.write_marker(ago(2))
    before = facts.since_marker()

    facts.run(dry_run=True, ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)
    assert facts.since_marker() == before
    assert not facts.CANDIDATES_PATH.exists()

    facts.run(ask=answers("Użytkownik pracuje na Windowsie."), conn=waiting_room.conn)
    assert facts.since_marker().stamp > before.stamp


# ---------------------------------------------------------------- working off a backlog

def test_the_marker_stops_at_the_last_processed_fragment(waiting_room):
    backlog(waiting_room, 40)
    seen = []

    r = facts.run(ask=recorder(seen), conn=waiting_room.conn)

    assert r["pending"] > 0
    assert facts.since_marker().stamp == ago(40 - r["chunks"] + 1)  # where we got to, not "now"
    assert facts.since_marker().stamp < ago(0)
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


# ---------------------------------------------------------------- what the day cost

def usage(sent: int = 300, received: int = 60, tokens: int = 120, measured: bool = True,
          tool: str = "claude") -> facts.Usage:
    """One counted call, without going anywhere near a real tool."""
    return facts.Usage(tool, sent, received, tokens, measured)


def test_runs_of_the_same_day_add_up(waiting_room):
    """The cycle goes several times over when it catches up — the user asks what the DAY cost."""
    facts.record_cost(usage(sent=300, received=60, tokens=120), found=2, day="2026-09-17")
    facts.record_cost(usage(sent=200, received=40, tokens=80), found=3, day="2026-09-17")

    saved = facts.read_cost()

    assert saved["data"] == "2026-09-17"
    assert (saved["wywolania"], saved["znaki_wyslane"], saved["znaki_odebrane"]) == ("2", "500", "100")
    assert (saved["tokeny"], saved["fakty"]) == ("200", "5")
    assert facts.PREVIOUS + "data" not in saved  # the first day has no yesterday to compare with


def test_a_new_day_starts_from_zero_and_keeps_the_previous_one(waiting_room):
    facts.record_cost(usage(sent=300, received=60, tokens=120), found=2, day="2026-09-16")
    facts.record_cost(usage(sent=90, received=9, tokens=33), found=1, day="2026-09-17")

    saved = facts.read_cost()

    assert (saved["data"], saved["wywolania"]) == ("2026-09-17", "1")
    assert (saved["tokeny"], saved["fakty"], saved["znaki_wyslane"]) == ("33", "1", "90")
    assert (saved["poprzedni.data"], saved["poprzedni.wywolania"]) == ("2026-09-16", "1")
    assert (saved["poprzedni.tokeny"], saved["poprzedni.fakty"]) == ("120", "2")


def test_only_one_day_back_is_kept(waiting_room):
    """Two columns get shown, so two are stored — a history nobody reads is only weight."""
    for day in ("2026-09-15", "2026-09-16", "2026-09-17"):
        facts.record_cost(usage(), found=1, day=day)

    saved = facts.read_cost()

    assert (saved["data"], saved["poprzedni.data"]) == ("2026-09-17", "2026-09-16")
    assert not [key for key in saved if key.startswith(facts.PREVIOUS + facts.PREVIOUS)]


def test_the_tokens_of_a_claude_run_are_the_real_ones(waiting_room, unforced, monkeypatch):
    """`claude -p --output-format json` reports what it was billed — better than any estimate."""
    envelope = json.dumps({"type": "result", "result": "- fakt",
                           "usage": {"input_tokens": 12, "cache_creation_input_tokens": 30000,
                                     "cache_read_input_tokens": 500, "output_tokens": 88}})
    monkeypatch.setattr(facts.shutil, "which", installed("claude"))
    monkeypatch.setattr(facts.subprocess, "run",
                        lambda argv, **kwargs: subprocess.CompletedProcess(argv, 0, envelope, ""))

    facts.ask_model("material")
    saved = facts.read_cost()

    assert (saved["narzedzie"], saved["tokeny_zrodlo"], saved["wywolania"]) == ("claude", "pomiar", "1")
    assert saved["tokeny"] == str(12 + 30000 + 500 + 88)  # the cache counts too: it is billed
    assert saved["znaki_wyslane"] == str(len(facts.PROMPT) + len("material"))


def test_without_a_reported_count_the_tokens_are_marked_as_an_estimate(waiting_room, codex):
    """Codex prints a session, not an envelope — a guess may be used, but not called a measurement."""
    facts.ask_model("material")
    saved = facts.read_cost()

    assert (saved["narzedzie"], saved["tokeny_zrodlo"]) == ("codex", "szacunek")
    sent, received = int(saved["znaki_wyslane"]), int(saved["znaki_odebrane"])
    assert int(saved["tokeny"]) == math.ceil((sent + received) / facts.CHARS_PER_TOKEN)


def test_one_estimated_call_makes_the_whole_day_an_estimate(waiting_room):
    facts.record_cost(usage(measured=True), day="2026-09-17")
    facts.record_cost(usage(measured=False, tool="codex"), day="2026-09-17")

    assert facts.read_cost()["tokeny_zrodlo"] == "szacunek"


def test_the_facts_of_a_run_land_in_the_tally(one_chunk):
    facts.run(ask=sorted_answer(*MIXED), conn=one_chunk.conn)

    assert facts.read_cost()["fakty"] == str(len(MIXED))


def test_a_cost_file_that_cannot_be_written_does_not_stop_the_harvest(one_chunk, capsys):
    """Measuring is not the job: a blocked file costs the numbers, never the facts."""
    facts.KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    (facts.KNOWLEDGE_DIR / facts.COST_NAME).mkdir()  # a directory where the file wants to be

    r = facts.run(ask=sorted_answer(MIXED[1]), conn=one_chunk.conn)

    assert [f.text for f in r["added"]] == [MIXED[1]["tresc"]]
    assert facts.CANDIDATES_PATH.exists()
    assert facts.COST_NAME in capsys.readouterr().err  # and it does not vanish quietly either


# ---------------------------------------------------------------- the history of what it cost

def pass_line(when: str, tokens: int = 1000, calls: int = 1, found: int = 2, messages: int = 30,
              measured: bool = True, tool: str = "claude") -> None:
    """One whole pass written into the journal, without a database and without a model."""
    facts.start_pass()
    for _ in range(calls):
        facts.record_cost(usage(tokens=tokens // max(1, calls), measured=measured, tool=tool),
                          day=when[:10])
    facts.record_cost(found=found, day=when[:10],
                      read=facts.Reading(messages=messages, first=when, last=when))
    facts.record_pass(when=when)


def journal_lines() -> list[str]:
    return facts.journal_path().read_text(encoding="utf-8").splitlines()


def summary() -> dict[str, str]:
    out = {}
    for line in facts.summary_path().read_text(encoding="utf-8").splitlines():
        key, _, value = line.partition(":")
        out[key.strip()] = value.strip()
    return out


def test_every_pass_leaves_its_own_line(waiting_room):
    """The point of the journal: a day of catching up is several passes, and the per-pass number is
    the one that tells a one-off backlog from a new normal."""
    pass_line("2026-09-17 08:05", tokens=300, found=2, messages=40)
    pass_line("2026-09-17 08:12", tokens=700, found=3, messages=50)

    lines = journal_lines()

    assert lines[0] == "\t".join(facts.JOURNAL_COLUMNS)  # a header, so Import-Csv can read it
    assert len(lines) == 3
    rows = facts.read_journal()
    assert [r["kiedy"] for r in rows] == ["2026-09-17 08:05", "2026-09-17 08:12"]
    assert [r["tokeny"] for r in rows] == ["300", "700"]
    assert [r["fakty"] for r in rows] == ["2", "3"]
    assert [r["wiadomosci"] for r in rows] == ["40", "50"]
    assert [r["narzedzie"] for r in rows] == ["claude", "claude"]
    assert [r["zakres_od"] for r in rows] == ["2026-09-17 08:05", "2026-09-17 08:12"]


def test_a_pass_of_several_calls_is_still_one_line(waiting_room):
    pass_line("2026-09-17 08:05", tokens=900, calls=3, found=4)

    rows = facts.read_journal()

    assert len(rows) == 1
    assert (rows[0]["wywolania"], rows[0]["tokeny"], rows[0]["fakty"]) == ("3", "900", "4")


def test_a_guessed_call_marks_the_whole_pass_as_an_estimate(waiting_room):
    pass_line("2026-09-17 08:05", measured=False, tool="codex")

    assert facts.read_journal()[0]["tokeny_zrodlo"] == "szacunek"


def test_the_journal_forgets_what_is_older_than_the_day_limit(waiting_room):
    old = (datetime.now() - timedelta(days=facts.JOURNAL_DAYS + 5)).strftime("%Y-%m-%d %H:%M")
    edge = (datetime.now() - timedelta(days=facts.JOURNAL_DAYS - 1)).strftime("%Y-%m-%d %H:%M")
    pass_line(old)
    pass_line(edge)
    pass_line(datetime.now().strftime("%Y-%m-%d %H:%M"))

    kept = [r["kiedy"] for r in facts.read_journal()]

    assert old not in kept
    assert edge in kept  # the limit cuts at the day, it does not round the whole span away


def test_the_journal_never_grows_past_its_line_limit(waiting_room, monkeypatch):
    """A day of catching up writes one line a pass — the cap is what keeps that from running away."""
    monkeypatch.setattr(facts, "JOURNAL_MAX_ROWS", 3)
    for minute in range(5):
        pass_line(f"2026-09-17 08:0{minute}", tokens=100 * minute)

    rows = facts.read_journal()

    assert len(rows) == 3
    assert [r["kiedy"] for r in rows] == ["2026-09-17 08:02", "2026-09-17 08:03", "2026-09-17 08:04"]
    assert journal_lines()[0] == "\t".join(facts.JOURNAL_COLUMNS)  # the rewrite keeps the header


def test_the_summaries_add_up_seven_and_thirty_days(waiting_room):
    """Written down so that showing the week costs one small file, not the whole journal."""
    today = datetime.now()
    for days, tokens in ((0, 1000), (3, 2000), (10, 4000), (40, 8000)):
        pass_line((today - timedelta(days=days)).strftime("%Y-%m-%d %H:%M"), tokens=tokens, found=1)

    s = summary()

    assert (s["dni7.tokeny"], s["dni7.przebiegi"]) == ("3000", "2")
    assert (s["dni30.tokeny"], s["dni30.przebiegi"]) == ("7000", "3")
    assert s["dni7.tokeny_na_przebieg"] == "1500"
    assert s["dni30.fakty_na_przebieg"] == "1.0"
    assert s["dni30.wywolania_na_przebieg"] == "1.0"
    assert s["dni7.od"] == (today - timedelta(days=6)).strftime("%Y-%m-%d")  # the period, by the number
    assert (s["przebiegi"], s["nieprawidlowosc"]) == ("4", "")


def test_one_guessed_pass_makes_the_whole_window_an_estimate(waiting_room):
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    pass_line(now, measured=True)
    pass_line(now, measured=False, tool="codex")

    assert summary()["dni7.tokeny_zrodlo"] == "szacunek"


def test_a_journal_that_cannot_be_written_does_not_stop_the_harvest(one_chunk, capsys):
    """The same rule as for the tally: a blocked file costs the numbers, never the facts."""
    facts.KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    facts.journal_path().mkdir()  # a directory where the file wants to be

    r = facts.run(ask=sorted_answer(MIXED[1]), conn=one_chunk.conn)

    assert [f.text for f in r["added"]] == [MIXED[1]["tresc"]]
    assert facts.JOURNAL_NAME in capsys.readouterr().err
    assert facts.JOURNAL_NAME in summary()["nieprawidlowosc"]  # and the trail outlives the console


def test_an_empty_journal_after_calls_already_paid_for_is_a_fault(waiting_room):
    """'Nothing yet' and 'the history stopped recording' must not look the same."""
    facts.record_cost(usage(), found=1, day="2026-09-17")
    facts.write_summary(facts.read_journal(), now="2026-09-17 09:00")

    assert "pusty" in summary()["nieprawidlowosc"]


def test_an_empty_journal_before_the_first_call_is_not_a_fault(waiting_room):
    """A false alarm teaches people to ignore alarms — an unused machine is not a broken one."""
    facts.write_summary(facts.read_journal(), now="2026-09-17 09:00")

    assert summary()["nieprawidlowosc"] == ""


def test_a_damaged_line_is_skipped_out_loud(waiting_room, capsys):
    pass_line("2026-09-17 08:05")
    with open(facts.journal_path(), "a", encoding="utf-8", newline="\n") as f:
        f.write("2026-09-17 08:30\tclaude\n")

    rows = facts.read_journal()

    assert len(rows) == 1
    assert facts.JOURNAL_NAME in capsys.readouterr().err


def test_a_run_leaves_a_line_of_history_and_the_old_tally_untouched(one_chunk):
    """The journal is an addition: narzedzia\\koszt-pamieci.ps1 still reads .koszt-cyklu.txt."""
    facts.run(ask=sorted_answer(*MIXED), conn=one_chunk.conn)

    saved = facts.read_cost()
    rows = facts.read_journal()

    assert set(saved) == {"data", *facts.COST_KEYS}  # exactly the old keys, nothing added
    assert saved["fakty"] == str(len(MIXED))
    assert len(rows) == 1
    assert (rows[0]["fakty"], rows[0]["wiadomosci"]) == (str(len(MIXED)), "1")
