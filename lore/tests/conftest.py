"""Shared test isolation: a sandbox instead of ~/.claude, an own database, zero real data."""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

# must happen BEFORE lore.db is imported — the paths are module constants computed at import time
_SANDBOX = Path(tempfile.mkdtemp(prefix="lore-tests-"))
os.environ["LORE_HOME"] = str(_SANDBOX)

import numpy as np  # noqa: E402
import pytest  # noqa: E402

from lore import db, index  # noqa: E402

TS = "2026-09-16T10:00:00.000Z"


def _zero_vectors(texts: list[str], batch: int = 32, model: str | None = None) -> np.ndarray:
    """Stand-in for embed_passages — the tests check chunking and incrementality, not the model."""
    return np.zeros((len(texts), db.model_spec(model).dim), dtype=np.float32)


def record(role: str, text: str, session: str = "test-session", ts: str = TS) -> dict:
    """One transcript row in the Claude Code format."""
    if role == "user":
        return {"type": "user", "sessionId": session, "timestamp": ts, "message": {"role": "user", "content": text}}
    return {
        "type": "assistant",
        "sessionId": session,
        "timestamp": ts,
        "message": {"role": "assistant", "content": [{"type": "text", "text": text}]},
    }


@dataclass
class Environment:
    conn: object
    projects: Path
    _nr: list[int] = field(default_factory=lambda: [0])

    def transcript(self, *turns: tuple[str, str], name: str = "test-session") -> Path:
        """Creates ~/projects/test-project/<name>.jsonl out of the given (role, text) pairs."""
        directory = self.projects / "test-project"
        directory.mkdir(parents=True, exist_ok=True)
        p = directory / f"{name}.jsonl"
        p.write_text("", encoding="utf-8")
        self.append(p, *turns)
        return p

    def append(self, p: Path, *turns: tuple[str, str]) -> None:
        with open(p, "a", encoding="utf-8", newline="\n") as f:
            for role, text in turns:
                f.write(json.dumps(record(role, text, session=p.stem), ensure_ascii=False) + "\n")

    def index(self, p: Path) -> int:
        return index.process_file(self.conn, p)

    def texts(self) -> list[str]:
        return [r[0] for r in self.conn.execute("SELECT text FROM chunks ORDER BY id")]

    def rows(self) -> list[tuple]:
        return list(self.conn.execute("SELECT line, part, role, text FROM chunks ORDER BY id"))

    def file_state(self, p: Path) -> tuple[float, int, int, int]:
        return self.conn.execute("SELECT mtime, size, offset, line FROM files WHERE path=?", (str(p),)).fetchone()


@pytest.fixture
def environment(tmp_path, monkeypatch):
    """An empty database in a temporary directory + own transcript directories."""
    projects = tmp_path / "projects"
    projects.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    monkeypatch.setattr(db, "DB_PATH", tmp_path / "lore.db")
    monkeypatch.setattr(index, "DB_PATH", tmp_path / "lore.db")
    monkeypatch.setattr(index, "LOCK_PATH", tmp_path / "lore.lock")
    monkeypatch.setattr(index, "PROJECTS_DIR", projects)
    monkeypatch.setattr(index, "HOME_DIR", home)
    monkeypatch.setattr(index, "CODEX_SESSIONS_DIR", home / ".codex" / "sessions")
    monkeypatch.setattr(index, "embed_passages", _zero_vectors)
    conn = db.connect()
    try:
        yield Environment(conn=conn, projects=projects)
    finally:
        conn.close()
