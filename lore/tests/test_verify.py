"""Verifying the facts: what gets confirmed by itself, what gets flagged and what stays untouched."""

from __future__ import annotations

import pytest

from lore import verify

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

CANDIDATES_HEADER = "# Kandydaci do trwałej wiedzy\n\n"


@pytest.fixture
def sandbox(tmp_path, monkeypatch):
    """The whole cycle inside tmp_path — the real ~/.claude must not be touched by the tests."""
    knowledge = tmp_path / "wiedza"
    monkeypatch.setattr(verify, "KNOWLEDGE_DIR", knowledge)
    monkeypatch.setattr(verify, "CANDIDATES_PATH", knowledge / "kandydaci.md")
    monkeypatch.setattr(verify, "RULES_PATH", tmp_path / "CLAUDE.md")
    monkeypatch.setattr(verify, "BACKUP_DIR", knowledge / "kopie")
    (tmp_path / "CLAUDE.md").write_text(RULES, encoding="utf-8")
    return tmp_path


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
    assert f"- Robot do Alibaby leży w `{p}`." in rules_text(sandbox)
    assert r["backup"] and verify.BACKUP_DIR.exists()


def test_a_confirmed_fact_lands_in_the_guessed_subsection(sandbox):
    p = existing(sandbox)
    candidates(sandbox, f"Firma sprzedaje olejki, cennik leży w `{p}`.", f"Kod robota to `{p}`.")

    verify.run()

    text = rules_text(sandbox)
    firma = text.index("### O firmie")
    nad_czym = text.index("### Nad czym pracuje")
    assert firma < text.index("Firma sprzedaje olejki") < nad_czym
    assert nad_czym < text.index("Kod robota to")
    assert verify.EMPTY_MARKER not in text.split("### Nad czym pracuje")[1].split("###")[0]


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


def test_an_unverifiable_fact_is_left_exactly_as_it_was(sandbox):
    candidates(sandbox, "Użytkownik nie jest programistą i nie chce nim być.")
    before = verify.CANDIDATES_PATH.read_text(encoding="utf-8")

    r = verify.run()

    assert r["approved"] == [] and r["suspicious"] == [] and r["waiting"] == 1
    assert verify.CANDIDATES_PATH.read_text(encoding="utf-8") == before


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
    assert r["backup"] == str(copies[0])


def test_nothing_blows_up_without_a_waiting_room(sandbox):
    r = verify.run()

    assert r["approved"] == [] and r["waiting"] == 0 and r["stale"] == []
    assert not verify.CANDIDATES_PATH.exists()
    assert verify.main(argv=[]) == 0
    assert verify.main(argv=["--proba"]) == 0
