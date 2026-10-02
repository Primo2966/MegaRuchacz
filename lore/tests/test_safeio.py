"""lore.safeio — memory files written so a power cut cannot zero them, and never built on when it did.

The negative tests are the point: each one breaks a file the way 2026-10-02 broke them (the full
size, nothing but 0x00 inside) and checks that the run refuses, writes nothing, copies nothing and
names the last healthy copy.
"""
from __future__ import annotations

import os

import pytest

from lore import facts, safeio, verify

from test_verify import RULES


def zero_out(path):
    """What the power cut did: the size stays, the content becomes zeros."""
    path.write_bytes(b"\0" * path.stat().st_size)


# ---------------------------------------------------------------- writing

def test_write_text_replaces_whole_file_and_leaves_no_temp(tmp_path):
    p = tmp_path / "CLAUDE.md"
    p.write_text("stare\n", encoding="utf-8")
    safeio.write_text(p, "nowe\nżółć\n")
    assert p.read_bytes() == "nowe\nżółć\n".encode("utf-8")
    assert [x.name for x in tmp_path.iterdir()] == ["CLAUDE.md"]


def test_write_text_newline_none_keeps_platform_line_ending(tmp_path):
    p = tmp_path / ".ostatnie-wyciaganie"
    safeio.write_text(p, "2026-10-01T06:00:00.000Z\n", newline=None)
    assert p.read_bytes() == ("2026-10-01T06:00:00.000Z" + os.linesep).encode()


def test_write_text_fsyncs_before_the_swap(tmp_path, monkeypatch):
    order = []
    real_fsync, real_replace = os.fsync, os.replace
    monkeypatch.setattr(safeio.os, "fsync", lambda fd: (order.append("fsync"), real_fsync(fd)))
    monkeypatch.setattr(safeio.os, "replace", lambda a, b: (order.append("replace"), real_replace(a, b)))
    safeio.write_text(tmp_path / "a.md", "x\n")
    assert order[:2] == ["fsync", "replace"]


def test_write_text_refuses_zero_bytes(tmp_path):
    p = tmp_path / "a.md"
    p.write_text("zdrowy\n", encoding="utf-8")
    with pytest.raises(ValueError):
        safeio.write_text(p, "ab\0cd")
    assert p.read_text(encoding="utf-8") == "zdrowy\n"


def test_write_text_retries_a_file_held_open_for_a_moment(tmp_path, monkeypatch):
    real_replace, tries = os.replace, []

    def busy_twice(a, b):
        tries.append(1)
        if len(tries) <= 2:
            raise PermissionError("held open by the guard")
        real_replace(a, b)
    monkeypatch.setattr(safeio.os, "replace", busy_twice)
    monkeypatch.setattr(safeio, "REPLACE_PAUSE_S", 0)
    p = tmp_path / "a.md"
    safeio.write_text(p, "nowe\n")
    assert p.read_text(encoding="utf-8") == "nowe\n" and len(tries) == 3


def test_write_text_that_cannot_swap_leaves_the_old_file_and_no_temp(tmp_path, monkeypatch):
    def always_busy(a, b):
        raise PermissionError("held open")
    monkeypatch.setattr(safeio.os, "replace", always_busy)
    monkeypatch.setattr(safeio, "REPLACE_PAUSE_S", 0)
    p = tmp_path / "a.md"
    p.write_text("stary\n", encoding="utf-8")
    with pytest.raises(PermissionError):
        safeio.write_text(p, "nowy\n")
    assert p.read_text(encoding="utf-8") == "stary\n"
    assert [x.name for x in tmp_path.iterdir()] == ["a.md"]


def test_append_text_writes_the_header_once_and_fsyncs(tmp_path, monkeypatch):
    synced = []
    real_fsync = os.fsync
    monkeypatch.setattr(safeio.os, "fsync", lambda fd: (synced.append(fd), real_fsync(fd)))
    p = tmp_path / "zrodla.md"
    safeio.append_text(p, "- a\n", header="# Nagłówek\n")
    safeio.append_text(p, "- b\n", header="# Nagłówek\n")
    assert p.read_text(encoding="utf-8") == "# Nagłówek\n- a\n- b\n"
    assert len(synced) == 2


def test_copy_file_refuses_to_copy_zeros(tmp_path):
    src = tmp_path / "CLAUDE.md"
    src.write_text("treść\n", encoding="utf-8")
    zero_out(src)
    with pytest.raises(safeio.ZeroedMemory):
        safeio.copy_file(src, tmp_path / "kopia.md")
    assert not (tmp_path / "kopia.md").exists()


# ---------------------------------------------------------------- finding zeros

@pytest.fixture
def home(tmp_path, monkeypatch):
    """~/.claude with CLAUDE.md, wiedza\\ and the daily copies, all inside tmp_path."""
    claude = tmp_path / ".claude"
    knowledge = claude / "wiedza"
    knowledge.mkdir(parents=True)
    monkeypatch.setattr(safeio, "CLAUDE_HOME", claude)
    monkeypatch.setattr(safeio, "DAILY_DIR", claude / "mr" / "kopie-dzienne")
    (claude / "CLAUDE.md").write_text(RULES, encoding="utf-8")
    (knowledge / "kandydaci.md").write_text("# Kandydaci\n", encoding="utf-8")
    (knowledge / ".ostatnie-wyciaganie").write_text("2026-10-01T06:00:00.000Z\n", encoding="utf-8")
    return claude


def test_healthy_files_pass_the_guard(home):
    safeio.guard(safeio.memory_files(home / "wiedza", [home / "CLAUDE.md"]))


def test_a_binary_file_in_wiedza_is_not_a_false_alarm(home):
    (home / "wiedza" / "zdjecie.png").write_bytes(b"\x89PNG\0\0\0")
    safeio.guard(safeio.memory_files(home / "wiedza", [home / "CLAUDE.md"]))


def test_zeroed_state_file_stops_the_guard(home):
    zero_out(home / "wiedza" / ".ostatnie-wyciaganie")
    with pytest.raises(safeio.ZeroedMemory) as e:
        safeio.guard(safeio.memory_files(home / "wiedza", [home / "CLAUDE.md"]))
    assert ".ostatnie-wyciaganie" in str(e.value) and "ALARM" in str(e.value)


def test_the_alarm_names_the_daily_copy_first(home):
    daily = home / "mr" / "kopie-dzienne" / "wczoraj" / ".claude" / "CLAUDE.md"
    daily.parent.mkdir(parents=True)
    daily.write_text(RULES, encoding="utf-8")
    (home / "CLAUDE.md.bak-20261001-100946").write_text(RULES, encoding="utf-8")
    zero_out(home / "CLAUDE.md")
    assert safeio.healthy_copy(home / "CLAUDE.md") == daily
    assert str(daily) in safeio.describe_zeroed(safeio.find_zeroed([home / "CLAUDE.md"]))


def test_a_zeroed_backup_is_never_named_as_healthy(home):
    bak = home / "CLAUDE.md.bak-20261002-080447"
    bak.write_text(RULES, encoding="utf-8")
    zero_out(bak)
    zero_out(home / "CLAUDE.md")
    assert safeio.healthy_copy(home / "CLAUDE.md") is None
    assert "zdrowej kopii nie znalazlem" in safeio.describe_zeroed(safeio.find_zeroed([home / "CLAUDE.md"]))


# ---------------------------------------------------------------- the runs refuse

def test_verify_refuses_a_zeroed_claude_md_and_writes_nothing(tmp_path, monkeypatch):
    knowledge = tmp_path / "wiedza"
    knowledge.mkdir()
    rules = tmp_path / "CLAUDE.md"
    rules.write_text(RULES, encoding="utf-8")
    zero_out(rules)
    (knowledge / "kandydaci.md").write_text("# Kandydaci\n\n- [ ] [2026-10-02] (biezaca) Fakt.\n",
                                            encoding="utf-8")
    monkeypatch.setattr(verify, "KNOWLEDGE_DIR", knowledge)
    monkeypatch.setattr(facts, "KNOWLEDGE_DIR", knowledge)
    monkeypatch.setattr(verify, "CANDIDATES_PATH", knowledge / "kandydaci.md")
    monkeypatch.setattr(verify, "INSTRUCTION_PATHS", (rules, tmp_path / ".codex" / "AGENTS.md"))
    monkeypatch.setattr(verify, "BACKUP_DIR", knowledge / "kopie")
    before = {p.name: p.read_bytes() for p in [rules, knowledge / "kandydaci.md"]}

    assert verify.main([]) == verify.EXIT_ZEROED

    assert {p.name: p.read_bytes() for p in [rules, knowledge / "kandydaci.md"]} == before
    assert not (knowledge / "kopie").exists()  # no "backup" of the zeros
    assert sorted(p.name for p in knowledge.iterdir()) == ["kandydaci.md"]


def test_harvest_refuses_a_zeroed_waiting_room_before_anything_runs(tmp_path, monkeypatch):
    knowledge = tmp_path / "wiedza"
    knowledge.mkdir()
    marker = knowledge / ".ostatnie-wyciaganie"
    marker.write_text("2026-10-01T06:00:00.000Z\n", encoding="utf-8")
    waiting = knowledge / "kandydaci.md"
    waiting.write_text("# Kandydaci\n", encoding="utf-8")
    zero_out(waiting)
    monkeypatch.setattr(facts, "KNOWLEDGE_DIR", knowledge)
    monkeypatch.setattr(facts, "MARKER_PATH", marker)
    monkeypatch.setattr(facts, "CANDIDATES_PATH", waiting)
    monkeypatch.setattr(facts, "RULES_PATH", tmp_path / "CLAUDE.md")
    monkeypatch.setattr(facts, "CODEX_RULES_PATH", tmp_path / "AGENTS.md")
    ran = []
    monkeypatch.setattr(facts, "_use_by_keyword", lambda dry_run: ran.append("use"))
    monkeypatch.setattr(facts, "run", lambda **kw: ran.append("run"))
    before = {p.name: p.read_bytes() for p in knowledge.iterdir()}

    assert facts.main([]) == facts.EXIT_ZEROED

    assert ran == []  # neither the use check nor the harvest got as far as starting
    assert {p.name: p.read_bytes() for p in knowledge.iterdir()} == before


def test_catch_up_called_directly_refuses_too(tmp_path, monkeypatch):
    knowledge = tmp_path / "wiedza"
    knowledge.mkdir()
    rules = tmp_path / "CLAUDE.md"
    rules.write_text(RULES, encoding="utf-8")
    zero_out(rules)
    monkeypatch.setattr(facts, "KNOWLEDGE_DIR", knowledge)
    monkeypatch.setattr(facts, "RULES_PATH", rules)
    monkeypatch.setattr(facts, "CODEX_RULES_PATH", tmp_path / "AGENTS.md")
    with pytest.raises(safeio.ZeroedMemory):
        facts.catch_up(dry_run=True)
