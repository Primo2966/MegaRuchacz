"""Verifying the facts: what walks in by itself, what gets flagged and what stays untouched."""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from lore import facts, verify

RULES = """# Ustalenia globalne

## Co wiem

<!-- Ta sekcja rośnie z rozmów. Jedna linia = jeden trwały fakt. -->

### O użytkowniku

- Nie jest programistą i nie chce nim być.

### O firmie

- Sprzedaje produkty do aromaterapii.

### Nad czym pracuje

_(pusto)_

### Bieżące

_(pusto)_

### Dane referencyjne

_(pusto)_

<!-- MegaRuchacz:start -->
## Pamięć rozmów (Lore)

- Szukaj w historii przez `szukaj_historii`.

<!-- MegaRuchacz:koniec -->
"""

# the Codex file holds the same "## Co wiem" structure; only what stands around it differs
AGENTS = RULES.replace("# Ustalenia globalne", "# Zasady globalne (Codex)")

CANDIDATES_HEADER = "# Kandydaci do trwałej wiedzy\n\n"


@pytest.fixture
def sandbox(tmp_path, monkeypatch):
    """The whole cycle inside tmp_path — the real ~/.claude and ~/.codex stay untouched.

    Only CLAUDE.md is there from the start; a test that wants the Codex file calls `codex_file`.
    """
    knowledge = tmp_path / "wiedza"
    monkeypatch.setattr(verify, "KNOWLEDGE_DIR", knowledge)
    monkeypatch.setattr(facts, "KNOWLEDGE_DIR", knowledge)  # the harvest side of the same trail
    monkeypatch.setattr(verify, "CANDIDATES_PATH", knowledge / "kandydaci.md")
    monkeypatch.setattr(verify, "INSTRUCTION_PATHS",
                        (tmp_path / "CLAUDE.md", tmp_path / ".codex" / "AGENTS.md"))
    monkeypatch.setattr(verify, "BACKUP_DIR", knowledge / "kopie")
    (tmp_path / "CLAUDE.md").write_text(RULES, encoding="utf-8")
    return tmp_path


def codex_path(sandbox):
    return sandbox / ".codex" / "AGENTS.md"


def codex_file(sandbox, text: str = None):
    """Creates ~/.codex/AGENTS.md — the machine where the user runs Codex as well."""
    p = codex_path(sandbox)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(AGENTS if text is None else text, encoding="utf-8")
    return p


def codex_text(sandbox) -> str:
    return codex_path(sandbox).read_text(encoding="utf-8")


def candidates(sandbox, *entries: str) -> None:
    text = CANDIDATES_HEADER + "".join(f"- [ ] [2026-09-16] {e}\n" for e in entries)
    verify.CANDIDATES_PATH.parent.mkdir(parents=True, exist_ok=True)
    verify.CANDIDATES_PATH.write_text(text, encoding="utf-8")


def waiting(sandbox) -> list[str]:
    """The entries still sitting in the waiting room, together with their '[ ]' / '[!]' box."""
    lines = verify.CANDIDATES_PATH.read_text(encoding="utf-8").splitlines()
    return [line for line in lines if line.startswith("- [")]


def rules_text(sandbox) -> str:
    return (sandbox / "CLAUDE.md").read_text(encoding="utf-8")


def existing(sandbox, name: str = "robot.js") -> str:
    p = sandbox / "projekt" / name
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("// cokolwiek\n", encoding="utf-8")
    return str(p)


MISSING = "C:\\nie-ma-takiego-katalogu\\plik.js"


# ---------------------------------------------------------------- finding the paths

def test_a_bare_path_is_found(sandbox):
    p = existing(sandbox)
    assert verify.paths_in(f"Robot leży w {p} i tam go trzymamy.") == [p]


def test_a_path_in_backticks_is_found(sandbox):
    p = existing(sandbox)
    assert verify.paths_in(f"Kod robota to `{p}`, uruchamiany co noc.") == [p]


def test_a_path_with_spaces_in_backticks_keeps_the_spaces():
    assert verify.paths_in("Zdjęcia leżą w `G:\\Mój dysk\\1. AROMAHOLIK\\`") == ["G:\\Mój dysk\\1. AROMAHOLIK\\"]


def test_a_path_with_spaces_in_quotes_keeps_the_spaces():
    assert verify.paths_in('Katalog "G:\\Mój dysk\\1. AROMAHOLIK" trzyma zdjęcia') == ["G:\\Mój dysk\\1. AROMAHOLIK"]


def test_a_bare_path_with_spaces_ends_where_the_separators_end():
    text = "Zdjęcia leżą w G:\\Mój dysk\\1. AROMAHOLIK\\ i nigdzie indziej"
    assert verify.paths_in(text) == ["G:\\Mój dysk\\1. AROMAHOLIK\\"]


def test_two_paths_in_one_sentence_do_not_glue_together():
    text = "Skrypty to C:\\dev\\a.js, C:\\dev\\b.js oraz C:\\dev\\c.js."
    assert verify.paths_in(text) == ["C:\\dev\\a.js", "C:\\dev\\b.js", "C:\\dev\\c.js"]


def test_a_directory_counts_as_a_path(sandbox):
    existing(sandbox)
    katalog = str(sandbox / "projekt")
    assert verify.paths_in(f"Projekt leży w {katalog}.") == [katalog]
    assert verify.verify(f"Projekt leży w {katalog}.").confirmed


def test_example_paths_are_skipped():
    assert verify.paths_in("Repozytoria trzyma w C:\\dev\\<nazwa-projektu>") == []
    assert verify.paths_in("Katalog domowy to %USERPROFILE%\\.claude") == []
    assert verify.paths_in("Skrypty leżą w C:\\dev\\...") == []
    assert verify.paths_in("Logi to C:\\dev\\*.log") == []


def test_a_sentence_without_a_path_is_unverifiable():
    v = verify.verify("Użytkownik nie jest programistą i nie chce nim być.")
    assert not v.checkable and not v.confirmed and v.missing == []


# ---------------------------------------------------------------- the waiting room

def test_a_confirmed_fact_moves_to_the_rules(sandbox):
    p = existing(sandbox)
    candidates(sandbox, f"Robot do Alibaby leży w `{p}`.")

    r = verify.run()

    assert r["approved"] == [f"Robot do Alibaby leży w `{p}`."]
    assert waiting(sandbox) == []
    # into the current layer, with its date — never straight into the durable one
    assert f"- [2026-09-16] Robot do Alibaby leży w `{p}`." in subsection(sandbox, "### Bieżące")
    assert r["backups"] and verify.BACKUP_DIR.exists()


def test_a_fresh_fact_never_lands_in_a_durable_subsection(sandbox):
    """One conversation's word is not enough for the layer every session starts with."""
    p = existing(sandbox)
    candidates(sandbox, f"Firma sprzedaje olejki, cennik leży w `{p}`.", f"Kod robota to `{p}`.")

    verify.run()

    assert "Firma sprzedaje olejki" not in subsection(sandbox, "### O firmie")
    assert "Kod robota to" not in subsection(sandbox, "### Nad czym pracuje")
    current = subsection(sandbox, "### Bieżące")
    assert "Firma sprzedaje olejki" in current and "Kod robota to" in current
    assert verify.EMPTY_MARKER not in current


def test_a_fact_with_a_missing_path_is_flagged_and_stays(sandbox):
    candidates(sandbox, f"Robot leży w `{MISSING}`.")

    r = verify.run()

    assert r["approved"] == [] and r["waiting"] == 1
    assert r["suspicious"] == [(f"Robot leży w `{MISSING}`.", [MISSING])]
    assert waiting(sandbox) == [f"- [!] [2026-09-16] Robot leży w `{MISSING}`. (nie znaleziono: {MISSING})"]
    assert MISSING not in rules_text(sandbox)


def test_a_fact_is_flagged_when_only_one_of_its_paths_is_missing(sandbox):
    p = existing(sandbox)
    candidates(sandbox, f"Robot `{p}` pisze do `{MISSING}`.")

    verify.run()

    assert waiting(sandbox)[0].startswith("- [!] ")
    assert waiting(sandbox)[0].endswith(f"(nie znaleziono: {MISSING})")


def test_an_unverifiable_fact_goes_in_by_itself(sandbox):
    """The heart of the change: nothing is checkable in that sentence and it enters anyway.

    Waiting for a human meant waiting forever — ninety entries nobody ever read.
    """
    fact = "Użytkownik nie jest programistą i nie chce nim być."
    candidates(sandbox, fact)

    r = verify.run()

    assert r["approved"] == [fact] and r["suspicious"] == [] and r["waiting"] == 0
    assert f"- [2026-09-16] {fact}" in subsection(sandbox, "### Bieżące")
    assert waiting(sandbox) == []


def test_a_second_run_does_not_pile_up_the_flags(sandbox):
    candidates(sandbox, f"Robot leży w `{MISSING}`.")

    verify.run()
    after_first = verify.CANDIDATES_PATH.read_text(encoding="utf-8")
    verify.run()

    assert verify.CANDIDATES_PATH.read_text(encoding="utf-8") == after_first
    assert waiting(sandbox)[0].count("nie znaleziono") == 1


def test_a_flagged_fact_gets_approved_once_the_path_shows_up(sandbox):
    p = str(sandbox / "projekt" / "robot.js")
    candidates(sandbox, f"Robot leży w `{p}`.")
    verify.run()
    assert waiting(sandbox)[0].startswith("- [!] ")

    existing(sandbox)  # the drive is back
    r = verify.run()

    assert r["approved"] == [f"Robot leży w `{p}`."]
    assert waiting(sandbox) == []


def test_a_box_ticked_by_the_user_is_not_touched(sandbox):
    verify.CANDIDATES_PATH.parent.mkdir(parents=True, exist_ok=True)
    line = f"- [x] [2026-09-16] Robot leży w `{MISSING}`."
    verify.CANDIDATES_PATH.write_text(CANDIDATES_HEADER + line + "\n", encoding="utf-8")

    r = verify.run()

    assert waiting(sandbox) == [line]
    assert r["waiting"] == 0 and r["suspicious"] == []


# ---------------------------------------------------------------- the facts already in force

def test_a_standing_fact_that_stopped_checking_out_is_marked_not_deleted(sandbox):
    rules = rules_text(sandbox).replace("_(pusto)_\n\n### Bieżące",
                                        f"- Robot do Alibaby leży w `{MISSING}`.\n\n### Bieżące")
    (sandbox / "CLAUDE.md").write_text(rules, encoding="utf-8")

    r = verify.run(day="2026-09-16")

    text = rules_text(sandbox)
    assert r["stale"] == [(f"Robot do Alibaby leży w `{MISSING}`.", [MISSING])]
    assert f"- Robot do Alibaby leży w `{MISSING}`. <!-- niepotwierdzone 2026-09-16: nie ma {MISSING} -->" in text
    assert text.count("Robot do Alibaby") == 1  # marked, still there


def test_marking_a_standing_fact_is_not_repeated_on_every_run(sandbox):
    rules = rules_text(sandbox).replace("_(pusto)_\n\n### Bieżące",
                                        f"- Robot leży w `{MISSING}`.\n\n### Bieżące")
    (sandbox / "CLAUDE.md").write_text(rules, encoding="utf-8")

    verify.run(day="2026-09-16")
    after_first = rules_text(sandbox)
    verify.run(day="2026-09-17")

    assert rules_text(sandbox).count("niepotwierdzone") == 1
    assert rules_text(sandbox) == after_first.replace("2026-09-16", "2026-09-17")


def test_the_mark_goes_away_when_the_fact_checks_out_again(sandbox):
    p = existing(sandbox)
    rules = rules_text(sandbox).replace(
        "_(pusto)_\n\n### Bieżące",
        f"- Robot leży w `{p}`. <!-- niepotwierdzone 2026-09-10: nie ma {p} -->\n\n### Bieżące")
    (sandbox / "CLAUDE.md").write_text(rules, encoding="utf-8")

    r = verify.run(day="2026-09-16")

    assert r["healed"] == [f"Robot leży w `{p}`."]
    assert "niepotwierdzone" not in rules_text(sandbox)
    assert f"- Robot leży w `{p}`." in rules_text(sandbox)


def test_a_standing_fact_wrapped_over_several_lines_is_one_fact(sandbox):
    rules = rules_text(sandbox).replace(
        "_(pusto)_\n\n### Bieżące",
        f"- Robot do Alibaby chodzi co noc i jego kod leży\n  w `{MISSING}`.\n\n### Bieżące")
    (sandbox / "CLAUDE.md").write_text(rules, encoding="utf-8")

    r = verify.run(day="2026-09-16")

    assert len(r["stale"]) == 1
    assert rules_text(sandbox).count("niepotwierdzone") == 1
    assert f"  w `{MISSING}`. <!-- niepotwierdzone 2026-09-16: nie ma {MISSING} -->" in rules_text(sandbox)


def test_an_unverifiable_standing_fact_is_left_alone(sandbox):
    before = rules_text(sandbox)

    r = verify.run(day="2026-09-16")

    assert r["stale"] == [] and rules_text(sandbox) == before


# ---------------------------------------------------------------- what must never be touched

def test_everything_outside_the_knowledge_section_stays_byte_for_byte(sandbox):
    p = existing(sandbox)
    candidates(sandbox, f"Kod robota to `{p}`.")
    before = rules_text(sandbox)

    verify.run()

    after = rules_text(sandbox)
    assert after != before
    assert after.split("## Co wiem")[0] == before.split("## Co wiem")[0]
    assert after.split(verify.GUARD_MARKER)[1] == before.split(verify.GUARD_MARKER)[1]


def test_without_the_knowledge_section_nothing_is_approved(sandbox):
    (sandbox / "CLAUDE.md").write_text("# Ustalenia globalne\n\nNic tu nie ma.\n", encoding="utf-8")
    p = existing(sandbox)
    candidates(sandbox, f"Kod robota to `{p}`.")

    r = verify.run()

    assert r["approved"] == [] and "Co wiem" in r["note"]
    assert rules_text(sandbox) == "# Ustalenia globalne\n\nNic tu nie ma.\n"
    assert waiting(sandbox) == [f"- [ ] [2026-09-16] Kod robota to `{p}`."]


def test_a_dry_run_writes_nothing(sandbox):
    p = existing(sandbox)
    candidates(sandbox, f"Kod robota to `{p}`.", f"Stary kod to `{MISSING}`.")
    rules_before = rules_text(sandbox)
    candidates_before = verify.CANDIDATES_PATH.read_text(encoding="utf-8")

    r = verify.run(dry_run=True)

    assert r["status"] == "dry-run" and r["approved"] == [f"Kod robota to `{p}`."]
    assert len(r["suspicious"]) == 1
    assert rules_text(sandbox) == rules_before
    assert verify.CANDIDATES_PATH.read_text(encoding="utf-8") == candidates_before
    assert not verify.BACKUP_DIR.exists()


def test_a_copy_of_the_rules_is_made_before_the_change(sandbox):
    p = existing(sandbox)
    candidates(sandbox, f"Kod robota to `{p}`.")
    before = rules_text(sandbox)

    r = verify.run()

    assert (sandbox / "wiedza" / "kopie").is_dir()
    copies = list((sandbox / "wiedza" / "kopie").glob("CLAUDE-*.md"))
    assert len(copies) == 1 and copies[0].read_text(encoding="utf-8") == before
    assert r["backups"] == [str(copies[0])]


# ---------------------------------------------------------------- one fact, every tool's file

def test_a_confirmed_fact_lands_in_every_instruction_file(sandbox):
    codex_file(sandbox)
    p = existing(sandbox)
    candidates(sandbox, f"Kod robota to `{p}`.")

    r = verify.run()

    assert f"- [2026-09-16] Kod robota to `{p}`." in rules_text(sandbox)
    assert f"- [2026-09-16] Kod robota to `{p}`." in codex_text(sandbox)
    assert r["files"] == [str(sandbox / "CLAUDE.md"), str(codex_path(sandbox))]
    assert len(r["backups"]) == 2


def test_the_codex_file_is_never_created_when_it_is_not_there(sandbox):
    p = existing(sandbox)
    candidates(sandbox, f"Kod robota to `{p}`.")

    r = verify.run()

    assert f"- [2026-09-16] Kod robota to `{p}`." in rules_text(sandbox)
    assert not codex_path(sandbox).parent.exists()  # no Codex here — nothing to set up either
    assert r["files"] == [str(sandbox / "CLAUDE.md")]


def test_with_the_codex_file_alone_the_fact_lands_there(sandbox):
    (sandbox / "CLAUDE.md").unlink()
    codex_file(sandbox)
    p = existing(sandbox)
    candidates(sandbox, f"Kod robota to `{p}`.")

    r = verify.run()

    assert r["approved"] == [f"Kod robota to `{p}`."]
    assert f"- [2026-09-16] Kod robota to `{p}`." in codex_text(sandbox)
    assert not (sandbox / "CLAUDE.md").exists()
    assert waiting(sandbox) == []


def test_without_any_instruction_file_nothing_blows_up(sandbox):
    (sandbox / "CLAUDE.md").unlink()
    p = existing(sandbox)
    candidates(sandbox, f"Kod robota to `{p}`.")

    r = verify.run()

    assert r["approved"] == [] and r["files"] == [] and r["backups"] == []
    assert "CLAUDE.md" in r["note"] and "AGENTS.md" in r["note"]
    assert waiting(sandbox) == [f"- [ ] [2026-09-16] Kod robota to `{p}`."]
    assert not codex_path(sandbox).exists()
    assert verify.main(argv=[]) == 0


def test_a_file_without_the_knowledge_section_is_skipped_not_blocking(sandbox):
    (sandbox / "CLAUDE.md").write_text("# Ustalenia globalne\n\nNic tu nie ma.\n", encoding="utf-8")
    codex_file(sandbox)
    p = existing(sandbox)
    candidates(sandbox, f"Kod robota to `{p}`.")

    r = verify.run()

    assert r["approved"] == [f"Kod robota to `{p}`."]
    assert rules_text(sandbox) == "# Ustalenia globalne\n\nNic tu nie ma.\n"
    assert f"- [2026-09-16] Kod robota to `{p}`." in codex_text(sandbox)


def test_a_fact_already_standing_in_a_file_is_not_written_there_twice(sandbox):
    p = existing(sandbox)
    fact = f"Kod robota to `{p}`."
    (sandbox / "CLAUDE.md").write_text(
        RULES.replace("### Nad czym pracuje\n\n_(pusto)_", f"### Nad czym pracuje\n\n- {fact}"),
        encoding="utf-8")
    codex_file(sandbox)
    candidates(sandbox, fact)

    r = verify.run()

    assert rules_text(sandbox).count("Kod robota to") == 1
    assert codex_text(sandbox).count("Kod robota to") == 1
    assert r["added"] == {str(codex_path(sandbox)): [fact]}
    assert [Path(b).name.split("-")[0] for b in r["backups"]] == ["AGENTS"]


def test_a_standing_fact_is_audited_in_every_file(sandbox):
    broken = f"- Robot leży w `{MISSING}`.\n\n### Bieżące"
    (sandbox / "CLAUDE.md").write_text(RULES.replace("_(pusto)_\n\n### Bieżące", broken),
                                       encoding="utf-8")
    codex_file(sandbox, AGENTS.replace("_(pusto)_\n\n### Bieżące", broken))

    r = verify.run(day="2026-09-16")

    assert r["stale"] == [(f"Robot leży w `{MISSING}`.", [MISSING])]  # one fact, two files, one line
    assert "niepotwierdzone 2026-09-16" in rules_text(sandbox)
    assert "niepotwierdzone 2026-09-16" in codex_text(sandbox)


def test_everything_outside_the_knowledge_section_of_the_codex_file_stays_byte_for_byte(sandbox):
    codex_file(sandbox)
    p = existing(sandbox)
    candidates(sandbox, f"Kod robota to `{p}`.")
    before = codex_text(sandbox)

    verify.run()

    after = codex_text(sandbox)
    assert after != before
    assert after.split("## Co wiem")[0] == before.split("## Co wiem")[0]
    assert after.split(verify.GUARD_MARKER)[1] == before.split(verify.GUARD_MARKER)[1]


def test_every_changed_file_gets_a_copy_named_after_it(sandbox):
    codex_file(sandbox)
    p = existing(sandbox)
    candidates(sandbox, f"Kod robota to `{p}`.")

    verify.run()

    copies = sorted(c.name.split("-")[0] for c in (sandbox / "wiedza" / "kopie").glob("*.md"))
    assert copies == ["AGENTS", "CLAUDE"]


def test_nothing_blows_up_without_a_waiting_room(sandbox):
    r = verify.run()

    assert r["approved"] == [] and r["waiting"] == 0 and r["stale"] == []
    assert not verify.CANDIDATES_PATH.exists()
    assert verify.main(argv=[]) == 0
    assert verify.main(argv=["--proba"]) == 0


# ---------------------------------------------------------------- the layers

def entry(text: str, label: str = "", day: str = "2026-09-16") -> str:
    """One waiting room line exactly as lore.facts writes it."""
    bracket = f"({label}) " if label else ""
    return f"- [ ] [{day}] {bracket}{text}\n"


def waiting_room(sandbox, *lines: str) -> None:
    verify.CANDIDATES_PATH.parent.mkdir(parents=True, exist_ok=True)
    verify.CANDIDATES_PATH.write_text(CANDIDATES_HEADER + "".join(lines), encoding="utf-8")


def subsection(sandbox, heading: str) -> str:
    """What stands under one subsection of '## Co wiem'."""
    return rules_text(sandbox).split(heading)[1].split("###")[0]


def heard(text: str, label: str = "stala/projekty", *sessions: str, day: str = "2026-09-16",
          again: bool = False) -> None:
    """One sighting in the trail, written by lore.facts itself — the evidence a promotion reads.

    `sessions` are the conversations of the batch the fact came out of.
    """
    layer, _, detail = label.replace(":", "/").partition("/")
    if layer == "referencyjna":
        fact = facts.Fact(text, layer, file=detail)
    else:
        fact = facts.Fact(text, layer, detail or facts.DEFAULT_SECTION)
    facts.note_sources([fact], f"rozmowy {day}..{day}", day, list(sessions),
                       event=facts.SIGHTED_AGAIN if again else facts.SIGHTED)


def trail_lines(sandbox, *lines: str) -> None:
    """Raw lines appended to the trail — for the formats lore.facts no longer writes."""
    path = sandbox / "wiedza" / "zrodla.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8", newline="\n") as f:
        f.write("".join(line + "\n" for line in lines))


def current_entries(sandbox, *lines: str) -> None:
    """Puts entries into "### Bieżące" exactly as given (with or without their date)."""
    body = "".join(f"- {line}\n" for line in lines)
    (sandbox / "CLAUDE.md").write_text(
        rules_text(sandbox).replace("### Bieżące\n\n_(pusto)_\n", f"### Bieżące\n\n{body}"),
        encoding="utf-8")


def standing(sandbox, *facts: str) -> None:
    """Puts facts into the durable layer of the rules, as if the user had written them there."""
    body = "".join(f"- {f}\n" for f in facts)
    (sandbox / "CLAUDE.md").write_text(
        RULES.replace("### Nad czym pracuje\n\n_(pusto)_\n", f"### Nad czym pracuje\n\n{body}"),
        encoding="utf-8")


def test_the_whole_waiting_room_empties_itself(sandbox):
    waiting_room(sandbox,
                 entry("Użytkownik wystawia oferty na Amazonie i eBayu.", "stala/uzytkownik"),
                 entry("Marka firmy nazywa się AROMAHOLIK.", "stala/firma"),
                 entry("Trwa przenoszenie magazynu do nowej hali.", "biezaca"))

    r = verify.run()

    assert len(r["approved"]) == 3 and r["waiting"] == 0
    assert waiting(sandbox) == []


def test_a_promoted_fact_lands_in_the_subsection_its_label_names(sandbox):
    # the keywords would send a sentence about selling to "### O firmie" — the label decides
    fact = "Sprzedaje najpierw na Amazonie, potem na eBayu."
    heard(fact, "stala/praca", "rozmowa-a")
    heard(fact, "stala/praca", "rozmowa-b", again=True)
    waiting_room(sandbox, entry(fact, "stala/praca"))

    verify.run()

    assert "Sprzedaje najpierw na Amazonie" in subsection(sandbox, "### Jak pracuje")
    assert "Sprzedaje najpierw" not in subsection(sandbox, "### O firmie")


def test_a_promoted_fact_without_a_known_subsection_lands_by_the_keyword_guess(sandbox):
    # two lines in the format from before the full list of sessions — still read as evidence
    fact = "Firma sprzedaje olejki eteryczne."
    trail_lines(sandbox,
                f"- 2026-09-15 | wyłowiony | stala | rozmowy 2026-09-15..2026-09-15 (sesje: a) | {fact}",
                f"- 2026-09-16 | wyłowiony | stala | rozmowy 2026-09-16..2026-09-16 (sesje: b) | {fact}")
    waiting_room(sandbox, entry(fact))

    verify.run()

    assert "Firma sprzedaje olejki" in subsection(sandbox, "### O firmie")


def test_the_layer_label_does_not_leak_into_the_knowledge(sandbox):
    waiting_room(sandbox, entry("Marka firmy nazywa się AROMAHOLIK.", "stala/firma"))

    verify.run()

    assert "- [2026-09-16] Marka firmy nazywa się AROMAHOLIK." in rules_text(sandbox)
    assert "(stala/firma)" not in rules_text(sandbox)


def test_a_current_fact_lands_under_biezace_with_its_date(sandbox):
    waiting_room(sandbox, entry("Trwa przenoszenie magazynu do nowej hali.", "biezaca"))

    verify.run()

    # the ageing rule in CLAUDE.md reads that date — an entry without it never expires
    assert "- [2026-09-16] Trwa przenoszenie magazynu do nowej hali." \
        in subsection(sandbox, "### Bieżące")


def test_a_current_fact_is_not_written_again_on_the_next_run(sandbox):
    line = entry("Trwa przenoszenie magazynu do nowej hali.", "biezaca")
    waiting_room(sandbox, line)
    verify.run()
    waiting_room(sandbox, line)  # the harvest proposes the same sentence again

    verify.run()

    assert rules_text(sandbox).count("Trwa przenoszenie magazynu") == 1


def test_a_reference_fact_leaves_a_pointer_and_the_listing_goes_to_a_file(sandbox):
    waiting_room(sandbox,
                 entry("SET3-Citrus[020312] to olejki 02, 03 i 12.", "referencyjna:struktura-sku.md"),
                 "      odsyłacz: Budowa SKU zestawów — w ~/.claude/wiedza/struktura-sku.md\n")

    r = verify.run()

    # the pointer is a new fact like any other: into the current layer first
    assert "- [2026-09-16] Budowa SKU zestawów" in subsection(sandbox, "### Bieżące")
    assert "Budowa SKU zestawów" not in subsection(sandbox, "### Dane referencyjne")
    assert "SET3-Citrus" not in rules_text(sandbox)  # the listing itself never enters the rules
    listing = (sandbox / "wiedza" / "struktura-sku.md").read_text(encoding="utf-8")
    assert "SET3-Citrus[020312] to olejki 02, 03 i 12." in listing
    assert r["references"] == [str(sandbox / "wiedza" / "struktura-sku.md")]


def test_a_pointer_line_leaves_together_with_its_fact(sandbox):
    waiting_room(sandbox,
                 entry("SET3-Citrus[020312] to olejki 02, 03 i 12.", "referencyjna:struktura-sku.md"),
                 "      odsyłacz: Budowa SKU zestawów — w ~/.claude/wiedza/struktura-sku.md\n")

    verify.run()

    rest = verify.CANDIDATES_PATH.read_text(encoding="utf-8")
    assert "odsyłacz:" not in rest and waiting(sandbox) == []


def test_a_listing_is_not_written_to_its_file_twice(sandbox):
    line = entry("SET3-Citrus[020312] to olejki 02, 03 i 12.", "referencyjna:struktura-sku.md")
    waiting_room(sandbox, line)
    verify.run()
    waiting_room(sandbox, line)

    verify.run()

    listing = (sandbox / "wiedza" / "struktura-sku.md").read_text(encoding="utf-8")
    assert listing.count("SET3-Citrus") == 1


# ---------------------------------------------------------------- contradiction

LIMIT_80 = "Tytuły na eBayu mają limit 80 znaków."
LIMIT_55 = "Tytuły na eBayu mają limit 55 znaków."


def test_a_contradicting_fact_stays_and_quotes_what_it_contradicts(sandbox):
    standing(sandbox, LIMIT_80)
    waiting_room(sandbox, entry(LIMIT_55))

    r = verify.run()

    assert r["approved"] == [] and r["disputed"] == [(LIMIT_55, LIMIT_80)]
    assert waiting(sandbox) == [
        f"- [?] [2026-09-16] {LIMIT_55} (sporne: przeczy wpisowi „{LIMIT_80}”)"]


def test_a_contradicting_fact_never_reaches_the_rules(sandbox):
    standing(sandbox, LIMIT_80)
    waiting_room(sandbox, entry(LIMIT_55))

    verify.run()

    assert "55 znaków" not in rules_text(sandbox)
    assert rules_text(sandbox).count("Tytuły na eBayu") == 1


def test_a_flipped_negation_counts_as_a_contradiction(sandbox):
    # the fixture already says "Nie jest programistą i nie chce nim być."
    waiting_room(sandbox, entry("Jest programistą i chce nim być."))

    r = verify.run()

    assert [f for f, _ in r["disputed"]] == ["Jest programistą i chce nim być."]
    assert r["disputed"][0][1] == "Nie jest programistą i nie chce nim być."


def test_a_swapped_path_counts_as_a_contradiction(sandbox):
    old, new = existing(sandbox, "stary.js"), existing(sandbox, "nowy.js")
    standing(sandbox, f"Robot do Alibaby leży w `{old}`.")
    waiting_room(sandbox, entry(f"Robot do Alibaby leży w `{new}`."))

    r = verify.run()

    assert r["approved"] == [] and len(r["disputed"]) == 1
    assert r["disputed"][0][1] == f"Robot do Alibaby leży w `{old}`."


def test_a_fact_about_something_else_is_not_called_disputed(sandbox):
    """The negative probe: a false alarm here sends the user back to the queue we just abolished."""
    standing(sandbox, LIMIT_80)
    waiting_room(sandbox, entry("Tytuły na Amazonie mają limit 200 znaków."))

    r = verify.run()

    assert r["disputed"] == [] and r["approved"] == ["Tytuły na Amazonie mają limit 200 znaków."]


def test_a_short_sentence_never_raises_a_contradiction(sandbox):
    standing(sandbox, "Redis nie działa.")
    waiting_room(sandbox, entry("Redis działa."))

    r = verify.run()

    assert r["disputed"] == []  # two words of subject is any sentence at all — pure false alarm


def test_a_disputed_entry_is_not_marked_twice(sandbox):
    standing(sandbox, LIMIT_80)
    waiting_room(sandbox, entry(LIMIT_55))

    verify.run()
    after_first = verify.CANDIDATES_PATH.read_text(encoding="utf-8")
    verify.run()

    assert verify.CANDIDATES_PATH.read_text(encoding="utf-8") == after_first
    assert waiting(sandbox)[0].count("sporne") == 1


def test_a_long_entry_is_quoted_short(sandbox):
    """The quote points at the entry — copying it whole would fatten the waiting room instead."""
    old = existing(sandbox, "bardzo-dlugi-plik-robota-alibaby-chodzacego-co-noc.js")
    new = existing(sandbox, "nowy.js")
    long_fact = f"Robot do Alibaby leży w `{old}`."
    assert len(long_fact) > verify.QUOTE_LIMIT  # otherwise the test is checking nothing
    standing(sandbox, long_fact)
    waiting_room(sandbox, entry(f"Robot do Alibaby leży w `{new}`."))

    verify.run()

    quoted = waiting(sandbox)[0].split("„")[1].split("”")[0]
    assert quoted.endswith("…") and len(quoted) <= verify.QUOTE_LIMIT + 1


def test_two_candidates_of_one_run_can_contradict_each_other(sandbox):
    waiting_room(sandbox, entry(LIMIT_80), entry(LIMIT_55))

    r = verify.run()

    assert r["approved"] == [LIMIT_80]
    assert r["disputed"] == [(LIMIT_55, LIMIT_80)]


# ---------------------------------------------------------------- the ceiling of the durable layer

def leave_room(sandbox, room: int) -> None:
    """Pads the durable layer so that exactly `room` characters are left under the ceiling."""
    text = rules_text(sandbox).replace("### Nad czym pracuje\n\n_(pusto)_",
                                       "### Nad czym pracuje\n\n- X")
    short = verify.STABLE_LIMIT - room - verify.stable_chars(text.splitlines())
    text = text.replace("\n- X\n", "\n- " + "X" * (1 + max(0, short)) + "\n")
    (sandbox / "CLAUDE.md").write_text(text, encoding="utf-8")
    assert verify.room_for_facts(text.splitlines()) == room


def test_the_ceiling_matches_the_number_the_cost_script_reports():
    """Two different numbers under one threshold would mean one of them is lying to the user."""
    script = Path(verify.__file__).parents[2] / "narzedzia" / "koszt-pamieci.ps1"
    if not script.is_file():
        pytest.skip(f"nie ma {script}")
    m = re.search(r"\$ProgStalej\s*=\s*(\d+)", script.read_text(encoding="utf-8"))
    assert m is not None and int(m.group(1)) == verify.STABLE_LIMIT


def test_the_current_subsection_does_not_count_into_the_durable_layer(sandbox):
    before = verify.stable_chars(rules_text(sandbox).splitlines())
    text = rules_text(sandbox).replace("### Bieżące\n\n_(pusto)_",
                                       "### Bieżące\n\n- [2026-09-16] " + "y" * 500)
    assert verify.stable_chars(text.splitlines()) < before + 100


def heard_twice(text: str, label: str = "stala/uzytkownik") -> None:
    """The evidence a promotion needs: the same fact out of two different conversations."""
    heard(text, label, "rozmowa-a", day="2026-09-15")
    heard(text, label, "rozmowa-b", day="2026-09-16", again=True)


def test_the_ceiling_stops_a_promotion_instead_of_crossing_it_quietly(sandbox):
    fact = "Użytkownik prowadzi całą sprzedaż z jednego biura pod Poznaniem."
    leave_room(sandbox, len(f"- {fact}"))  # one character short of what the entry needs
    heard_twice(fact)
    waiting_room(sandbox, entry(fact))

    r = verify.run()

    assert r["promoted"] == [] and r["over_limit"] == [fact]
    # not lost: it stays in the current layer, where it ages out if nothing changes
    assert fact in subsection(sandbox, "### Bieżące")
    assert verify.stable_chars(rules_text(sandbox).splitlines()) <= verify.STABLE_LIMIT


def test_a_promotion_that_still_fits_goes_in(sandbox):
    """The other half of the probe — a ceiling that stops everything is not a ceiling."""
    fact = "Użytkownik prowadzi całą sprzedaż z jednego biura pod Poznaniem."
    leave_room(sandbox, len(f"- {fact}") + 1)
    heard_twice(fact)
    waiting_room(sandbox, entry(fact))

    r = verify.run()

    assert r["promoted"] == [fact] and r["over_limit"] == []
    assert fact in subsection(sandbox, "### O użytkowniku")
    assert verify.stable_chars(rules_text(sandbox).splitlines()) <= verify.STABLE_LIMIT


def test_the_ceiling_lets_through_what_fits_and_holds_back_the_rest(sandbox):
    first = "Użytkownik prowadzi całą sprzedaż z jednego biura pod Poznaniem."
    second = "Użytkownik wysyła paczki raz dziennie, zawsze po południu."
    leave_room(sandbox, len(f"- {first}") + 1)
    heard_twice(first)
    heard_twice(second)
    waiting_room(sandbox, entry(first), entry(second))

    r = verify.run()

    assert r["promoted"] == [first] and r["over_limit"] == [second]
    assert verify.stable_chars(rules_text(sandbox).splitlines()) <= verify.STABLE_LIMIT


def test_a_current_fact_is_not_stopped_by_the_ceiling(sandbox):
    leave_room(sandbox, 0)  # not one character left in the durable layer
    waiting_room(sandbox, entry("Trwa przenoszenie magazynu do nowej hali.", "biezaca"))

    r = verify.run()

    # "### Bieżące" is counted separately by narzedzia\koszt-pamieci.ps1 — it has no ceiling here
    assert r["approved"] == ["Trwa przenoszenie magazynu do nowej hali."]
    assert "Trwa przenoszenie magazynu" in subsection(sandbox, "### Bieżące")


# ---------------------------------------------------------------- the way back

def test_a_copy_is_taken_before_a_fact_walks_in_by_itself(sandbox):
    """Facts enter without being asked, so the state from before every run has to be recoverable."""
    before = rules_text(sandbox)
    waiting_room(sandbox, entry("Marka firmy nazywa się AROMAHOLIK.", "stala/firma"))

    r = verify.run()

    copies = list((sandbox / "wiedza" / "kopie").glob("CLAUDE-*.md"))
    assert len(copies) == 1 and copies[0].read_text(encoding="utf-8") == before
    assert r["backups"] == [str(copies[0])]


def test_a_copy_of_a_listing_is_taken_before_it_grows(sandbox):
    waiting_room(sandbox, entry("Olejek 02 to cytryna.", "referencyjna:zapachy.md"))
    verify.run()
    before = (sandbox / "wiedza" / "zapachy.md").read_text(encoding="utf-8")

    waiting_room(sandbox, entry("Olejek 03 to mięta.", "referencyjna:zapachy.md"))
    verify.run()

    copies = list((sandbox / "wiedza" / "kopie").glob("zapachy-*.md"))
    assert len(copies) == 1 and copies[0].read_text(encoding="utf-8") == before


# ---------------------------------------------------------------- the trail back to the conversation

def trail(sandbox) -> str:
    return (sandbox / "wiedza" / "zrodla.md").read_text(encoding="utf-8")


def test_the_trail_says_when_a_fact_was_written_and_when_it_was_harvested(sandbox):
    fact = "Marka firmy nazywa się AROMAHOLIK."
    waiting_room(sandbox, entry(fact, "stala/firma", day="2026-09-14"))

    verify.run(day="2026-09-17")

    assert ("2026-09-17 | wpisany | biezaca -> CLAUDE.md | wyłowiony 2026-09-14 jako stala/firma"
            in trail(sandbox))
    assert fact in trail(sandbox)


def test_the_trail_stays_out_of_the_rules(sandbox):
    """The durable layer is sent with every session and has a ceiling — provenance is not free."""
    fact = "Marka firmy nazywa się AROMAHOLIK."
    waiting_room(sandbox, entry(fact, "stala/firma"))

    verify.run(day="2026-09-17")

    assert f"- [2026-09-16] {fact}" in rules_text(sandbox)
    assert "2026-09-17" not in rules_text(sandbox) and "wyłowiony" not in rules_text(sandbox)


def test_an_entry_without_a_date_says_so_in_the_trail(sandbox):
    verify.CANDIDATES_PATH.parent.mkdir(parents=True, exist_ok=True)
    verify.CANDIDATES_PATH.write_text(CANDIDATES_HEADER + "- [ ] Marka firmy to AROMAHOLIK.\n",
                                      encoding="utf-8")

    verify.run(day="2026-09-17")

    assert "wpis bez daty" in trail(sandbox)


def test_a_rejected_fact_leaves_no_trail(sandbox):
    waiting_room(sandbox, entry(f"Robot leży w `{MISSING}`."))

    verify.run()

    assert not (sandbox / "wiedza" / "zrodla.md").exists()


# ---------------------------------------------------------------- the summary of a run

def state(sandbox) -> dict:
    raw = (sandbox / "wiedza" / verify.STATE_NAME).read_text(encoding="utf-8")
    return dict(line.split(": ", 1) for line in raw.splitlines() if ": " in line)


def test_the_run_leaves_a_summary_the_cycle_can_show(sandbox):
    standing(sandbox, LIMIT_80)
    waiting_room(sandbox,
                 entry("Marka firmy nazywa się AROMAHOLIK.", "stala/firma"),
                 entry("Trwa przenoszenie magazynu do nowej hali.", "biezaca"),
                 entry(LIMIT_55),
                 entry(f"Robot leży w `{MISSING}`."))

    verify.run(day="2026-09-17")

    s = state(sandbox)
    assert s["data"] == "2026-09-17" and s["dopisane"] == "2"
    # the old keys keep their names for aktualizuj-wiedze.ps1: "stala" is now what was promoted
    assert s["stala"] == "0" and s["biezaca"] == "2" and s["referencyjna"] == "0"
    assert s["weszlo_do_biezacej"] == "2" and s["awansowane_do_stalej"] == "0"
    assert s["wygasle"] == "0" and s["awans_odlozony_limitem"] == "0"
    assert s["odrzucone"] == "1" and s["sporne"] == "1" and s["czeka"] == "2"
    assert s["prog_stalej"].endswith(f"/{verify.STABLE_LIMIT}")
    assert s["powod"] == "dopisano 2 faktow (do biezacej 2, awans do stalej 0)"
    # how far the contradiction check reached — a guarantee nobody can size is no guarantee
    assert int(s["porownane_wpisy"]) == 3


def test_a_run_that_added_nothing_says_why(sandbox):
    """Silence is forbidden: a pass that did nothing must not look like a pass that never ran."""
    waiting_room(sandbox, entry(f"Robot leży w `{MISSING}`."))

    verify.run(day="2026-09-17")

    s = state(sandbox)
    assert s["dopisane"] == "0"
    assert s["powod"].startswith("nic nie doszlo") and "odrzucone" in s["powod"]


def test_an_empty_waiting_room_still_reports_a_run(sandbox):
    verify.run(day="2026-09-17")

    s = state(sandbox)
    assert s["dopisane"] == "0"
    assert s["powod"] == "nic nie doszlo: w poczekalni nie bylo nowych faktow"


def test_a_summary_names_the_ceiling_as_the_reason_when_it_is(sandbox):
    fact = "Użytkownik prowadzi całą sprzedaż z jednego biura pod Poznaniem."
    leave_room(sandbox, len(f"- {fact}"))
    heard_twice(fact)
    waiting_room(sandbox, entry(fact))

    verify.run(day="2026-09-17")

    s = state(sandbox)
    assert s["wstrzymane_progiem"] == "1" and "progiem warstwy stalej" in s["powod"]


def test_a_run_without_any_instruction_file_reports_that_too(sandbox):
    (sandbox / "CLAUDE.md").unlink()
    waiting_room(sandbox, entry("Marka firmy nazywa się AROMAHOLIK.", "stala/firma"))

    verify.run(day="2026-09-17")

    assert "CLAUDE.md" in state(sandbox)["powod"]


def test_a_dry_run_leaves_no_summary_and_no_trail(sandbox):
    waiting_room(sandbox, entry("Marka firmy nazywa się AROMAHOLIK.", "stala/firma"))

    verify.run(dry_run=True, day="2026-09-17")

    assert not (sandbox / "wiedza" / verify.STATE_NAME).exists()
    assert not (sandbox / "wiedza" / "zrodla.md").exists()


# ---------------------------------------------------------------- repetition is the evidence

TWO_MACHINES = "Użytkownik pracuje na dwóch maszynach, biurowej i domowej."


def test_a_fact_from_one_conversation_lands_in_the_current_layer_not_the_durable(sandbox):
    heard(TWO_MACHINES, "stala/uzytkownik", "rozmowa-a")
    waiting_room(sandbox, entry(TWO_MACHINES, "stala/uzytkownik"))

    r = verify.run(day="2026-09-17")

    assert r["promoted"] == [] and r["entered"] == [TWO_MACHINES]
    assert f"- [2026-09-16] {TWO_MACHINES}" in subsection(sandbox, "### Bieżące")
    assert TWO_MACHINES not in subsection(sandbox, "### O użytkowniku")


def test_the_same_fact_from_a_second_conversation_is_promoted_and_leaves_the_current_layer(sandbox):
    heard(TWO_MACHINES, "stala/uzytkownik", "rozmowa-a")
    waiting_room(sandbox, entry(TWO_MACHINES, "stala/uzytkownik"))
    verify.run(day="2026-09-17")
    # the next day the harvest hears it again, in ANOTHER conversation; it is known, so it only
    # leaves a sighting in the trail — the waiting room stays empty
    heard(TWO_MACHINES, "stala/uzytkownik", "rozmowa-b", day="2026-09-17", again=True)

    r = verify.run(day="2026-09-18")

    assert r["promoted"] == [TWO_MACHINES]
    assert f"- {TWO_MACHINES}" in subsection(sandbox, "### O użytkowniku")  # and without a date
    current = subsection(sandbox, "### Bieżące")
    assert TWO_MACHINES not in current and verify.EMPTY_MARKER in current
    assert rules_text(sandbox).count(TWO_MACHINES) == 1
    assert "| awansowany | stala: O użytkowniku -> CLAUDE.md | z 2 rozmów" in trail(sandbox)
    s = state(sandbox)
    assert s["awansowane_do_stalej"] == "1" and s["weszlo_do_biezacej"] == "0"


def test_the_same_fact_twice_from_the_same_conversation_is_not_promoted(sandbox):
    """The probe that breaks the rule on purpose: one conversation, two batches, two sightings."""
    heard(TWO_MACHINES, "stala/uzytkownik", "rozmowa-a")
    heard(TWO_MACHINES, "stala/uzytkownik", "rozmowa-a", day="2026-09-17", again=True)
    waiting_room(sandbox, entry(TWO_MACHINES, "stala/uzytkownik"))

    r = verify.run(day="2026-09-18")

    assert r["promoted"] == []
    assert TWO_MACHINES in subsection(sandbox, "### Bieżące")
    assert TWO_MACHINES not in subsection(sandbox, "### O użytkowniku")


def test_batches_sharing_a_conversation_count_as_one(sandbox):
    # the model does not say which conversation of the batch the fact came from — "b" may be both
    heard(TWO_MACHINES, "stala/uzytkownik", "rozmowa-a", "rozmowa-b")
    heard(TWO_MACHINES, "stala/uzytkownik", "rozmowa-b", "rozmowa-c", again=True)
    waiting_room(sandbox, entry(TWO_MACHINES, "stala/uzytkownik"))

    assert verify.run(day="2026-09-18")["promoted"] == []

    heard(TWO_MACHINES, "stala/uzytkownik", "rozmowa-d", day="2026-09-18", again=True)

    assert verify.run(day="2026-09-19")["promoted"] == [TWO_MACHINES]


def test_the_same_fact_in_another_order_of_values_is_still_the_same(sandbox):
    heard("Zestaw SET3 to olejki 02, 03 i 12.", "stala/firma", "rozmowa-a")
    heard("Zestaw SET3 to olejki 12, 03 i 02.", "stala/firma", "rozmowa-b", again=True)
    waiting_room(sandbox, entry("Zestaw SET3 to olejki 02, 03 i 12.", "stala/firma"))

    assert verify.run(day="2026-09-18")["promoted"] == ["Zestaw SET3 to olejki 02, 03 i 12."]


def test_another_value_is_not_the_same_fact(sandbox):
    """Same wording, another number — that is a contradiction's shape, never a repetition."""
    heard("Tytuły na eBayu mają limit 80 znaków.", "stala/firma", "rozmowa-a")
    heard("Tytuły na eBayu mają limit 55 znaków.", "stala/firma", "rozmowa-b")
    waiting_room(sandbox, entry("Tytuły na eBayu mają limit 80 znaków.", "stala/firma"))

    assert verify.run(day="2026-09-18")["promoted"] == []


def test_a_sighting_that_hides_its_other_conversations_is_no_evidence(sandbox):
    fact = "Firma sprzedaje olejki eteryczne."
    trail_lines(sandbox,
                f"- 2026-09-15 | wyłowiony | stala/firma | rozmowy x (sesje: a, b, c i 2 innych) | {fact}",
                f"- 2026-09-16 | wyłowiony | stala/firma | rozmowy y (sesje: d) | {fact}")
    waiting_room(sandbox, entry(fact, "stala/firma"))

    # "i 2 innych" may well be "d" — two conversations are not proven
    assert verify.run(day="2026-09-18")["promoted"] == []


def test_the_promotions_of_one_run_are_capped_and_the_most_repeated_go_first(sandbox):
    # different words, not different numbers — a changed number is the shape of a contradiction
    many = [f"Użytkownik dobrze sprzedaje olejek {name} na eBayu."
            for name in ("cytrynowy", "miętowy", "lawendowy", "eukaliptusowy", "pomarańczowy")]
    for fact in many:
        heard_twice(fact)
    heard(many[4], "stala/uzytkownik", "rozmowa-c", day="2026-09-16", again=True)  # three times
    waiting_room(sandbox, *(entry(fact) for fact in many))

    r = verify.run(day="2026-09-17")

    assert verify.MAX_PROMOTIONS == 3  # the number the test is sized for
    assert r["promoted"][0] == many[4] and len(r["promoted"]) == 3
    assert r["deferred"] == [fact for fact in many[:4] if fact not in r["promoted"]]
    current = subsection(sandbox, "### Bieżące")
    assert all(fact in current for fact in r["deferred"])  # not lost — waiting for the next run
    s = state(sandbox)
    assert s["awansowane_do_stalej"] == "3" and s["awans_odlozony_limitem"] == "2"
    assert "czeka na awans" in s["powod"]
    left = r["deferred"]

    r = verify.run(day="2026-09-18")

    assert r["promoted"] == left and r["deferred"] == []
    assert all(fact not in subsection(sandbox, "### Bieżące") for fact in many)


def test_a_fact_the_model_called_current_is_never_promoted(sandbox):
    fact = "Trwa przenoszenie magazynu do nowej hali."
    heard_twice(fact, "biezaca")
    waiting_room(sandbox, entry(fact, "biezaca"))

    assert verify.run(day="2026-09-17")["promoted"] == []
    assert fact in subsection(sandbox, "### Bieżące")


def test_a_fact_already_durable_is_not_moved_nor_doubled(sandbox):
    """Repetition promotes what is in the current layer — it is not a migration backwards."""
    standing(sandbox, TWO_MACHINES)
    heard_twice(TWO_MACHINES)
    waiting_room(sandbox, entry(TWO_MACHINES, "stala/uzytkownik"))
    before = rules_text(sandbox)

    r = verify.run(day="2026-09-17")

    assert r["promoted"] == [] and r["entered"] == []
    assert rules_text(sandbox) == before


def test_a_pointer_is_promoted_when_its_listing_was_heard_twice(sandbox):
    listing = "SET3-Citrus[020312] to olejki 02, 03 i 12."
    pointer = "Budowa SKU zestawów — w ~/.claude/wiedza/struktura-sku.md"
    heard(listing, "referencyjna:struktura-sku.md", "rozmowa-a")
    waiting_room(sandbox, entry(listing, "referencyjna:struktura-sku.md"),
                 f"      odsyłacz: {pointer}\n")
    verify.run(day="2026-09-17")
    assert pointer in subsection(sandbox, "### Bieżące")
    heard(listing, "referencyjna:struktura-sku.md", "rozmowa-b", day="2026-09-17", again=True)

    r = verify.run(day="2026-09-18")

    assert r["promoted"] == [pointer]
    assert f"- {pointer}" in subsection(sandbox, "### Dane referencyjne")
    assert pointer not in subsection(sandbox, "### Bieżące")
    assert "SET3-Citrus" not in rules_text(sandbox)


# ---------------------------------------------------------------- the current layer ages out

def test_an_entry_the_automaton_wrote_expires_after_fourteen_days(sandbox):
    fact = "Trwa przenoszenie magazynu do nowej hali."
    waiting_room(sandbox, entry(fact, "biezaca", day="2026-09-01"))
    verify.run(day="2026-09-01")

    r = verify.run(day="2026-09-15")  # 14 days — still in force
    assert r["expired"] == [] and fact in subsection(sandbox, "### Bieżące")

    r = verify.run(day="2026-09-16")  # 15 days — gone

    assert r["expired"] == [fact]
    assert fact not in rules_text(sandbox)
    assert verify.EMPTY_MARKER in subsection(sandbox, "### Bieżące")
    assert "| wygasł | biezaca -> CLAUDE.md | wpis z 2026-09-01" in trail(sandbox)
    s = state(sandbox)
    assert s["wygasle"] == "1" and "wygaslo 1" in s["powod"]


def test_an_old_entry_the_user_wrote_himself_is_only_counted(sandbox):
    current_entries(sandbox, "[2026-09-01] Czekam na odpowiedź hurtowni.")
    before = rules_text(sandbox)

    r = verify.run(day="2026-09-20")

    assert r["expired"] == [] and r["own_old"] == ["Czekam na odpowiedź hurtowni."]
    assert rules_text(sandbox) == before
    assert state(sandbox)["stare_reczne_w_biezacej"] == "1"


def test_expiry_takes_out_only_the_old_entries(sandbox):
    waiting_room(sandbox,
                 entry("Trwa przenoszenie magazynu do nowej hali.", "biezaca", day="2026-09-01"),
                 entry("Trwa inwentaryzacja w magazynie.", "biezaca", day="2026-09-10"))
    verify.run(day="2026-09-10")

    r = verify.run(day="2026-09-20")

    assert r["expired"] == ["Trwa przenoszenie magazynu do nowej hali."]
    current = subsection(sandbox, "### Bieżące")
    assert "- [2026-09-10] Trwa inwentaryzacja w magazynie." in current
    assert verify.EMPTY_MARKER not in current


def test_a_dry_run_neither_promotes_nor_expires(sandbox):
    heard(TWO_MACHINES, "stala/uzytkownik", "rozmowa-a", day="2026-09-10")
    waiting_room(sandbox, entry(TWO_MACHINES, "stala/uzytkownik", day="2026-09-10"),
                 entry("Trwa przenoszenie magazynu.", "biezaca", day="2026-09-01"))
    verify.run(day="2026-09-10")
    heard(TWO_MACHINES, "stala/uzytkownik", "rozmowa-b", day="2026-09-11", again=True)
    before, trail_before = rules_text(sandbox), trail(sandbox)

    r = verify.run(dry_run=True, day="2026-09-20")

    # both would happen — and nothing did
    assert r["promoted"] == [TWO_MACHINES] and r["expired"] == ["Trwa przenoszenie magazynu."]
    assert rules_text(sandbox) == before and trail(sandbox) == trail_before
