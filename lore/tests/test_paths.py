"""Where Lore keeps its own data — the environment variables, the old path, the new one.

Everything runs on a fake home directory; the real ~/.claude and ~/.lore are never touched.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from lore import db


@pytest.fixture
def home(tmp_path, monkeypatch):
    """A throwaway home directory with no variables set — a machine with a fresh install."""
    monkeypatch.setattr(Path, "home", classmethod(lambda cls: tmp_path))
    monkeypatch.delenv("LORE_HOME", raising=False)
    monkeypatch.delenv("CLAUDE_HISTORIA_HOME", raising=False)
    return tmp_path


def old_home(home: Path, database: str = db.DB_NAME) -> Path:
    """Simulates an install made before the move: ~/.claude with a database inside."""
    previous = home / ".claude"
    previous.mkdir(parents=True, exist_ok=True)
    (previous / database).write_text("", encoding="utf-8")
    return previous


def test_fresh_install_goes_to_own_directory(home):
    assert db._data_home() == home / ".lore"


def test_existing_database_keeps_the_old_directory(home):
    previous = old_home(home)
    assert db._data_home() == previous


def test_database_left_by_the_polish_version_also_keeps_the_old_directory(home):
    """historia.db is taken over in place — the fresh path would not find it at all."""
    previous = old_home(home, db.LEGACY_DB_NAME)
    assert db._data_home() == previous


def test_empty_old_directory_does_not_count(home):
    """~/.claude exists on every machine with Claude Code — only a database means an install."""
    (home / ".claude").mkdir()
    assert db._data_home() == home / ".lore"


def test_variable_wins_over_the_old_database(home, monkeypatch, tmp_path):
    old_home(home)
    monkeypatch.setenv("LORE_HOME", str(tmp_path / "wskazany"))
    assert db._data_home() == tmp_path / "wskazany"


def test_older_variable_still_works(home, monkeypatch, tmp_path):
    monkeypatch.setenv("CLAUDE_HISTORIA_HOME", str(tmp_path / "stara-zmienna"))
    assert db._data_home() == tmp_path / "stara-zmienna"


def test_current_variable_has_priority_over_the_older_one(home, monkeypatch, tmp_path):
    monkeypatch.setenv("CLAUDE_HISTORIA_HOME", str(tmp_path / "stara-zmienna"))
    monkeypatch.setenv("LORE_HOME", str(tmp_path / "nowa-zmienna"))
    assert db._data_home() == tmp_path / "nowa-zmienna"


def test_data_paths_sit_in_the_data_directory():
    assert db.DB_PATH == db.DATA_HOME / db.DB_NAME
    assert db.MODELS_DIR == db.DATA_HOME / db.MODELS_NAME


def test_transcripts_are_read_from_the_claude_directory():
    """The source of the transcripts stays next to Claude Code — that is a different directory."""
    assert db.PROJECTS_DIR == db.CLAUDE_HOME / "projects"
