"""Paths, SQLite schema and shared helpers (embeddings)."""

from __future__ import annotations

import os
import sqlite3
import sys
import threading
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
for _stream in (sys.stderr,):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# LORE_HOME is the current name; CLAUDE_HISTORIA_HOME stays supported for older setups
CLAUDE_HOME = Path(os.environ.get("LORE_HOME") or os.environ.get("CLAUDE_HISTORIA_HOME") or Path.home() / ".claude")
PROJECTS_DIR = CLAUDE_HOME / "projects"
DB_PATH = CLAUDE_HOME / "lore.db"
MODELS_DIR = CLAUDE_HOME / "lore_models"

# names used before the rename — taken over on startup instead of rebuilt from scratch
LEGACY_DB_NAME = "historia.db"
LEGACY_MODELS_NAME = "historia_modele"

EMBED_MODEL = "intfloat/multilingual-e5-small"
EMBED_DIM = 384

SCHEMA = """
CREATE TABLE IF NOT EXISTS files (
    path     TEXT PRIMARY KEY,
    mtime    REAL NOT NULL,
    size     INTEGER NOT NULL,
    offset   INTEGER NOT NULL DEFAULT 0,
    line     INTEGER NOT NULL DEFAULT 0,
    project  TEXT,
    session  TEXT
);
CREATE TABLE IF NOT EXISTS chunks (
    id      INTEGER PRIMARY KEY,
    project TEXT NOT NULL,
    session TEXT NOT NULL,
    file    TEXT NOT NULL,
    line    INTEGER NOT NULL,
    part    INTEGER NOT NULL DEFAULT 0,
    ts      TEXT NOT NULL,
    role    TEXT NOT NULL,
    text    TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_chunks_file ON chunks(file, line, part);
CREATE INDEX IF NOT EXISTS idx_chunks_ts ON chunks(ts);
CREATE INDEX IF NOT EXISTS idx_chunks_project ON chunks(project);
CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
    text,
    content='chunks',
    content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);
CREATE TABLE IF NOT EXISTS vectors (
    chunk_id INTEGER PRIMARY KEY REFERENCES chunks(id) ON DELETE CASCADE,
    emb      BLOB NOT NULL
);
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT
);
"""


def connect() -> sqlite3.Connection:
    """Opens the database (schema, WAL, long busy_timeout — several windows may write at once)."""
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    _take_over_legacy_db()
    conn = sqlite3.connect(DB_PATH, timeout=180, isolation_level=None, check_same_thread=False)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA foreign_keys=ON")
    rebuild_fts = migrate_legacy_names(conn)
    conn.executescript(SCHEMA)
    if rebuild_fts:
        conn.execute("INSERT INTO chunks_fts(chunks_fts) VALUES('rebuild')")
        log("full-text index rebuilt after the rename")
    return conn


def log(*args) -> None:
    """Logging goes to stderr only — stdout belongs to the MCP protocol."""
    print(datetime.now().strftime("%H:%M:%S"), "[lore]", *args, file=sys.stderr, flush=True)


# ---------------------------------------------------------------- migration from the old names

def _take_over_legacy_db() -> None:
    """Moves an existing historia.db (with its WAL/SHM) to the new path — no copy, no rebuild."""
    legacy = DB_PATH.with_name(LEGACY_DB_NAME)
    if DB_PATH.exists() or not legacy.exists():
        return
    log(f"taking over {legacy.name} -> {DB_PATH.name}")
    for suffix in ("", "-wal", "-shm"):
        src = legacy.with_name(legacy.name + suffix)
        if src.exists():
            os.replace(src, DB_PATH.with_name(DB_PATH.name + suffix))


def _tables(conn: sqlite3.Connection) -> set[str]:
    return {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}


def _columns(conn: sqlite3.Connection, table: str) -> set[str]:
    return {r[1] for r in conn.execute(f"PRAGMA table_info({table})")}


def _rename_columns(conn: sqlite3.Connection, table: str, mapping: dict[str, str]) -> None:
    have = _columns(conn, table)
    for old, new in mapping.items():
        if old in have and new not in have:
            conn.execute(f"ALTER TABLE {table} RENAME COLUMN {old} TO {new}")


def migrate_legacy_names(conn: sqlite3.Connection) -> bool:
    """Renames tables/columns left from the Polish schema. Idempotent; a new database is a no-op.

    Returns True when the full-text index has to be rebuilt — its old copy is dropped here,
    because FTS5 stores the name of the content table inside its own definition.
    """
    tables = _tables(conn)
    if not {"fragmenty", "pliki", "wektory"} & tables:
        return False
    conn.execute("BEGIN IMMEDIATE")  # half a rename is worse than none
    try:
        rebuild_fts = _rename_all(conn, tables)
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise
    log("schema migrated to the new names")
    return rebuild_fts


def _rename_all(conn: sqlite3.Connection, tables: set[str]) -> bool:
    rebuild_fts = False
    if "fragmenty_fts" in tables:
        conn.execute("DROP TABLE fragmenty_fts")
        rebuild_fts = True
    if "fragmenty" in tables and "chunks" not in tables:
        conn.execute("ALTER TABLE fragmenty RENAME TO chunks")
        rebuild_fts = True
    if "chunks" in _tables(conn):
        _rename_columns(conn, "chunks", {
            "projekt": "project", "sesja": "session", "plik": "file",
            "linia": "line", "czesc": "part", "rola": "role", "tekst": "text",
        })
    for idx in ("idx_fragmenty_plik", "idx_fragmenty_ts", "idx_fragmenty_projekt"):
        conn.execute(f"DROP INDEX IF EXISTS {idx}")
    if "pliki" in tables and "files" not in tables:
        conn.execute("ALTER TABLE pliki RENAME TO files")
    if "files" in _tables(conn):
        _rename_columns(conn, "files", {
            "sciezka": "path", "rozmiar": "size", "linia": "line",
            "projekt": "project", "sesja": "session",
        })
    if "wektory" in tables and "vectors" not in tables:
        conn.execute("ALTER TABLE wektory RENAME TO vectors")
    if "vectors" in _tables(conn):
        _rename_columns(conn, "vectors", {"fragment_id": "chunk_id"})
    if "meta" in tables:
        _rename_columns(conn, "meta", {"klucz": "key", "wartosc": "value"})
        conn.execute("UPDATE OR REPLACE meta SET key='last_indexed' WHERE key='ostatnie_indeksowanie'")
    if "chunks" in _tables(conn):
        _migrate_roles(conn)
    return rebuild_fts


def _migrate_roles(conn: sqlite3.Connection) -> None:
    """Role labels stored in rows: narzedzie/wynik/podsumowanie/rozmowa -> tool/result/summary/conversation."""
    for old, new in (("narzedzie", "tool"), ("wynik", "result"),
                     ("podsumowanie", "summary"), ("rozmowa", "conversation")):
        for prefix in ("", "agent:"):
            conn.execute("UPDATE chunks SET role=? WHERE role=?", (prefix + new, prefix + old))


# ---------------------------------------------------------------- embeddings

_model = None
_model_lock = threading.Lock()


def embedding_model():
    """Lazy, one-off load of the ONNX model (the first run downloads ~120 MB)."""
    global _model
    if _model is None:
        with _model_lock:
            if _model is None:
                from fastembed import TextEmbedding
                from fastembed.common.model_description import ModelSource, PoolingType

                # fastembed has no built-in e5-small — we register it from the official HF repo (ONNX files)
                if EMBED_MODEL not in {m["model"] for m in TextEmbedding.list_supported_models()}:
                    TextEmbedding.add_custom_model(
                        model=EMBED_MODEL,
                        pooling=PoolingType.MEAN,
                        normalization=True,
                        sources=ModelSource(hf=EMBED_MODEL),
                        dim=EMBED_DIM,
                        model_file="onnx/model.onnx",
                        size_in_gb=0.47,
                    )
                _take_over_legacy_models()
                MODELS_DIR.mkdir(parents=True, exist_ok=True)
                log(f"loading model {EMBED_MODEL} ...")
                _model = TextEmbedding(model_name=EMBED_MODEL, cache_dir=str(MODELS_DIR))
                log("model ready")
    return _model


def _take_over_legacy_models() -> None:
    """Moves the old model cache instead of downloading ~470 MB again."""
    legacy = MODELS_DIR.with_name(LEGACY_MODELS_NAME)
    if MODELS_DIR.exists() or not legacy.is_dir():
        return
    try:
        os.replace(legacy, MODELS_DIR)
        log(f"taking over the model cache {legacy.name} -> {MODELS_DIR.name}")
    except OSError as e:  # a fresh download is only slow, not fatal
        log(f"cannot move the model cache: {e!r}")


def _normalize(m: np.ndarray) -> np.ndarray:
    m = np.asarray(m, dtype=np.float32)
    norms = np.linalg.norm(m, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    return m / norms


def embed_passages(texts: list[str], batch: int = 32) -> np.ndarray:
    """Vectors for chunks — the `passage: ` prefix is required by e5 models.

    Texts are sorted by length: ONNX pads to the longest item in a batch, so mixing short
    tool lines with long answers wasted several times more time and RAM.
    """
    if not texts:
        return np.zeros((0, EMBED_DIM), dtype=np.float32)
    m = embedding_model()
    order = sorted(range(len(texts)), key=lambda i: len(texts[i]))
    vecs = list(m.embed(["passage: " + texts[i] for i in order], batch_size=batch))
    out = np.empty((len(texts), EMBED_DIM), dtype=np.float32)
    out[order] = np.vstack(vecs)
    return _normalize(out)


def embed_query(query: str) -> np.ndarray:
    m = embedding_model()
    vecs = list(m.embed(["query: " + query]))
    return _normalize(np.vstack(vecs))[0]


# ---------------------------------------------------------------- dates

def ts_to_local(ts: str) -> str:
    """ISO UTC ('2026-09-11T06:27:15.470Z') -> 'YYYY-MM-DD HH:MM' in local time."""
    try:
        d = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        if d.tzinfo is None:
            d = d.replace(tzinfo=timezone.utc)
        return d.astimezone().strftime("%Y-%m-%d %H:%M")
    except Exception:
        return ts[:16].replace("T", " ")
