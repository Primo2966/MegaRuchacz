"""Paths, SQLite schema and shared helpers (embeddings)."""

from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import sys
import threading
import time
from dataclasses import dataclass
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

DB_NAME = "lore.db"
MODELS_NAME = "lore_models"

# names used before the rename — taken over on startup instead of rebuilt from scratch
LEGACY_DB_NAME = "historia.db"
LEGACY_MODELS_NAME = "historia_modele"


def _data_home() -> Path:
    """Where Lore keeps its own data — deliberately not tied to any AI tool's directory.

    Order: the environment variable wins, then ~/.claude when a database already sits
    there (an existing install must not lose its history), and only a fresh install
    goes to ~/.lore. Nothing is ever moved between the two.
    """
    # LORE_HOME is the current name; CLAUDE_HISTORIA_HOME stays supported for older setups
    chosen = os.environ.get("LORE_HOME") or os.environ.get("CLAUDE_HISTORIA_HOME")
    if chosen:
        return Path(chosen)
    previous = Path.home() / ".claude"
    if any((previous / name).exists() for name in (DB_NAME, LEGACY_DB_NAME)):
        return previous
    return Path.home() / ".lore"


# source of the transcripts to index — that one belongs next to Claude Code and stays there
CLAUDE_HOME = Path(os.environ.get("LORE_HOME") or os.environ.get("CLAUDE_HISTORIA_HOME") or Path.home() / ".claude")
PROJECTS_DIR = CLAUDE_HOME / "projects"

DATA_HOME = _data_home()
DB_PATH = DATA_HOME / DB_NAME
MODELS_DIR = DATA_HOME / MODELS_NAME

# ---------------------------------------------------------------- embedding models


@dataclass(frozen=True)
class EmbedModel:
    """One embedding model Lore can run. The prefixes belong to the model, they are not a detail:
    each model was trained with its own, and a wrong one costs more quality than the model switch
    gains (measured 2026-09-24, .claude/raporty/pamiec-test-modeli.md)."""

    name: str             # what meta.embed_model records
    dim: int
    query_prefix: str
    passage_prefix: str
    pooling: str          # member of fastembed's PoolingType
    model_file: str
    size_mb: int
    # A pinned download: repo, exact commit, sha256 of every file. Empty = fastembed fetches
    # `name` by itself, the way e5-small always was.
    source: str | None = None
    revision: str | None = None
    files: tuple[tuple[str, str], ...] = ()


E5_SMALL = EmbedModel(
    name="intfloat/multilingual-e5-small", dim=384,
    query_prefix="query: ", passage_prefix="passage: ",
    pooling="MEAN", model_file="onnx/model.onnx", size_mb=470,
)

# The authors publish PyTorch weights only. The ONNX file comes from a third-party export, pinned to
# one commit and to the sha256 of every file: what was compared on 2026-09-24 against a local
# optimum export (itself checked against PyTorch, see lore/bench/prepare.py) is byte for byte what
# every later download gets — a changed or replaced file is refused, not used.
# Model card: "zapytanie: " before a query, NOTHING before a passage; CLS pooling (1_Pooling).
MMLW_BASE = EmbedModel(
    name="sdadas/mmlw-retrieval-roberta-base", dim=768,
    query_prefix="zapytanie: ", passage_prefix="",
    pooling="CLS", model_file="onnx/model.onnx", size_mb=496,
    source="dawidplaskowski/mmlw-retrieval-roberta-base_onnx",
    revision="464ca1f2a74793b4c6e52fbc258001d48f6a115b",
    files=(
        ("config.json", "14f112d155898677b25951484d648da23875398e9064ec4482119224e950e53e"),
        ("tokenizer.json", "be3fe041cdd8b194576bfdff6a0fe8782e682ac81d398b967305b69eea2dcf73"),
        ("tokenizer_config.json", "b63cb2fc1a3c1c2fd550a12cc4533467c037ce6fdad4580fe8d6689b3219d498"),
        ("special_tokens_map.json", "8c785abebea9ae3257b61681b4e6fd8365ceafde980c21970d001e834cf10835"),
        ("onnx/model.onnx", "3f0afb9acc448cc074cc186689062c228429894ff6b11a1e198f648e673d3d48"),
    ),
)

MODELS = {m.name: m for m in (E5_SMALL, MMLW_BASE)}

# The configured model: a fresh install starts with it, an older database is converted to it
# (python -m lore.migrate). Until the conversion finishes, the database keeps using its own.
EMBED_MODEL = MMLW_BASE.name
EMBED_DIM = MMLW_BASE.dim
# every database written before the model was recorded holds e5-small vectors — nothing else was used
LEGACY_EMBED_MODEL = E5_SMALL.name

META_MODEL = "embed_model"        # model of the vectors in `vectors` — the ONLY ones search ranks
META_NEXT = "embed_model_next"    # model being built in `vectors_next` during a conversion
NEXT_TABLE = "vectors_next"
NEXT_SCHEMA = f"""
CREATE TABLE IF NOT EXISTS {NEXT_TABLE} (
    chunk_id INTEGER PRIMARY KEY REFERENCES chunks(id) ON DELETE CASCADE,
    emb      BLOB NOT NULL
);
"""

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
    id         INTEGER PRIMARY KEY,
    project    TEXT NOT NULL,
    session    TEXT NOT NULL,
    file       TEXT NOT NULL,
    line       INTEGER NOT NULL,
    part       INTEGER NOT NULL DEFAULT 0,
    ts         TEXT NOT NULL,
    role       TEXT NOT NULL,
    text       TEXT NOT NULL,
    -- when the row landed HERE, as opposed to `ts`, which is when it was said. The two are not the
    -- same axis: the indexer runs every ten minutes, so a chunk can enter the database long after
    -- its own date (a delayed transcript, an import from another machine). Only this one ever
    -- grows, which is why the harvest walks it — see lore/facts.py.
    indexed_at TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_chunks_file ON chunks(file, line, part);
CREATE INDEX IF NOT EXISTS idx_chunks_ts ON chunks(ts);
CREATE INDEX IF NOT EXISTS idx_chunks_project ON chunks(project);
CREATE INDEX IF NOT EXISTS idx_chunks_indexed ON chunks(indexed_at, id);
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
    migrate_indexed_at(conn)  # before the schema script: its index needs the column to exist
    conn.executescript(SCHEMA)
    if rebuild_fts:
        conn.execute("INSERT INTO chunks_fts(chunks_fts) VALUES('rebuild')")
        log("full-text index rebuilt after the rename")
    record_embed_model(conn)
    warn_on_model_mismatch(conn)
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


def migrate_indexed_at(conn: sqlite3.Connection) -> int:
    """Adds chunks.indexed_at to a database that predates it. Returns the rows filled in.

    Idempotent and cheap to repeat: the column is added once, and the backfill only ever touches
    rows still carrying the empty default.

    The old rows get their own `ts`, NOT the moment of the migration. Stamping fifty thousand
    chunks with "now" would make three years of archive look like it arrived today, and the first
    harvest after the migration would push the whole thing through the model in one go. With `ts`
    the existing read marker keeps meaning exactly what it meant, nothing moves backwards, and
    everything indexed from here on carries the real moment it landed.
    """
    if "chunks" not in _tables(conn):
        return 0  # a brand new database — SCHEMA creates the column with the table
    if "indexed_at" not in _columns(conn, "chunks"):
        conn.execute("ALTER TABLE chunks ADD COLUMN indexed_at TEXT NOT NULL DEFAULT ''")
    filled = conn.execute("UPDATE chunks SET indexed_at = ts WHERE indexed_at = ''").rowcount
    if filled:
        log(f"indexed_at filled in for {filled} older chunks (from their own date)")
    return filled


def _migrate_roles(conn: sqlite3.Connection) -> None:
    """Role labels stored in rows: narzedzie/wynik/podsumowanie/rozmowa -> tool/result/summary/conversation."""
    for old, new in (("narzedzie", "tool"), ("wynik", "result"),
                     ("podsumowanie", "summary"), ("rozmowa", "conversation")):
        for prefix in ("", "agent:"):
            conn.execute("UPDATE chunks SET role=? WHERE role=?", (prefix + new, prefix + old))


# ---------------------------------------------------------------- which model the vectors belong to

# a conversion whose progress file has not moved for this long is not running any more: one batch
# takes ~10 s on this CPU, so ten minutes of silence is a dead process, not a slow one
MIGRATION_STALE_S = 10 * 60

_warned: set[tuple] = set()


def migration_progress_path() -> Path:
    """lore.migration.json next to the database — the conversion rewrites it after every batch."""
    return DB_PATH.with_name(DB_PATH.stem + ".migration.json")


def _meta(conn: sqlite3.Connection, key: str) -> str | None:
    r = conn.execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
    return r[0] if r else None


def active_model(conn: sqlite3.Connection) -> str | None:
    """The model the vectors in `vectors` were computed with. Search embeds the query with this
    one and nothing else — whatever the configuration says."""
    return _meta(conn, META_MODEL)


def model_spec(name: str | None = None) -> EmbedModel:
    """The registry entry of a model (the configured one by default). Unknown = loud error."""
    name = name or EMBED_MODEL
    spec = MODELS.get(name)
    if spec is None:
        raise ModelUnavailable(f"unknown embedding model {name!r} - Lore can run only: {', '.join(MODELS)}")
    return spec


def record_embed_model(conn: sqlite3.Connection) -> str:
    """Writes down, once, which model the stored vectors come from.

    A brand new database gets the configured model. A database that already holds chunks but has
    no record predates this function — and until then Lore only ever ran e5-small.
    """
    have = active_model(conn)
    if have:
        return have
    has_rows = conn.execute("SELECT EXISTS(SELECT 1 FROM chunks) OR EXISTS(SELECT 1 FROM vectors)").fetchone()[0]
    name = LEGACY_EMBED_MODEL if has_rows else EMBED_MODEL
    conn.execute("INSERT OR IGNORE INTO meta(key, value) VALUES (?, ?)", (META_MODEL, name))
    return active_model(conn) or name


def has_table(conn: sqlite3.Connection, name: str) -> bool:
    return conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)).fetchone() is not None


def pid_alive(pid: int) -> bool:
    """Is a process with this pid still running? (A hard kill or a power cut leaves no other trace.)"""
    if pid <= 0:
        return False
    if sys.platform == "win32":
        import ctypes
        k32 = ctypes.WinDLL("kernel32", use_last_error=True)
        handle = k32.OpenProcess(0x1000 | 0x00100000, False, pid)  # QUERY_LIMITED_INFORMATION | SYNCHRONIZE
        if not handle:
            return ctypes.get_last_error() == 5  # access denied = it exists, just not ours
        try:
            return k32.WaitForSingleObject(handle, 0) == 0x102  # WAIT_TIMEOUT = still running
        finally:
            k32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def read_migration_progress() -> dict | None:
    """The progress file as the conversion left it, plus `stale` when a "running" one is not running.

    Not running = its process is gone, or it has not written for MIGRATION_STALE_S.
    An unreadable file is reported as such, never taken for "no conversion".
    """
    p = migration_progress_path()
    if not p.exists():
        return None
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        return {"state": "unreadable", "message": f"cannot read {p}: {e!r}"}
    if data.get("state") == "running":
        try:
            age = time.time() - p.stat().st_mtime
        except OSError:
            age = 0.0
        gone = isinstance(data.get("pid"), int) and not pid_alive(data["pid"])
        if gone or age > MIGRATION_STALE_S:
            data["stale"] = True
            why = f"its process {data.get('pid')} is gone" if gone else f"it stopped writing progress {age / 60:.0f} min ago"
            data["message"] = (f"the conversion is NOT running - {why} (computer switched off, window closed, "
                               "killed); run it again, it resumes where it stopped")
    return data


def vector_status(conn: sqlite3.Connection) -> dict:
    """Which model the vectors belong to, whether that is the configured one, and how far the conversion is.

    `state`: ok | incomplete (the right model, but some chunks lack a valid vector) |
    migration_needed | migrating | unknown_model. Anything but ok carries a `warning`.
    """
    active = active_model(conn)
    target = EMBED_MODEL
    total = conn.execute("SELECT count(*) FROM chunks").fetchone()[0]
    out: dict = {"model": active, "configured": target, "chunks": total}
    spec = MODELS.get(active or "")
    if spec is not None:
        size = spec.dim * 4
        valid, invalid = conn.execute(
            "SELECT coalesce(sum(length(emb) = ?), 0), coalesce(sum(length(emb) != ?), 0) FROM vectors",
            (size, size)).fetchone()
        out["vectors"], out["vectors_wrong_size"] = int(valid), int(invalid)
    cmd = "uv --directory <lore> run python -m lore.migrate"
    if active == target:
        missing = total - out.get("vectors", 0)
        if missing > 0 or out.get("vectors_wrong_size"):
            out["state"] = "incomplete"
            out["warning"] = (f"{missing} of {total} chunks have no valid {target} vector "
                              f"({out.get('vectors_wrong_size', 0)} of the wrong size, excluded from ranking) "
                              f"- repair: {cmd}")
        else:
            out["state"] = "ok"
    else:
        building = _meta(conn, META_NEXT) == target and has_table(conn, NEXT_TABLE)
        done = conn.execute(f"SELECT count(*) FROM {NEXT_TABLE}").fetchone()[0] if building else 0
        out["converted"] = done
        if spec is None:
            out["state"] = "unknown_model"
            semantic = "semantic search is OFF (full text only) - these vectors cannot be queried"
        else:
            out["state"] = "migrating" if building else "migration_needed"
            semantic = f"semantic search keeps using {active} alone, never a mix of the two"
        out["warning"] = (f"vectors in the database were computed with {active}, Lore is configured for {target}: "
                          f"{semantic}, until the conversion finishes ({done}/{total} chunks converted) - {cmd}")
    progress = read_migration_progress()
    if progress is not None:
        out["progress"] = progress
    return out


def warn_on_model_mismatch(conn: sqlite3.Connection) -> None:
    """Says it out loud (stderr, once per process and state) when the vectors are not the configured model's."""
    active = active_model(conn)
    if active == EMBED_MODEL:
        return
    key = (str(DB_PATH), active, EMBED_MODEL)
    if key in _warned:
        return
    _warned.add(key)
    log("WARNING: " + vector_status(conn)["warning"])


# ---------------------------------------------------------------- embeddings


class ModelUnavailable(RuntimeError):
    """The embedding model cannot be downloaded or loaded — the message says what happened and what now."""


_models: dict[str, object] = {}
_model_lock = threading.Lock()


def embedding_model(name: str | None = None):
    """Lazy, one-off load of an ONNX model (the first use downloads it — hundreds of MB).

    One model in RAM per process: a process only ever needs the model of the vectors it works on,
    and after a conversion the old one is dead weight.
    """
    spec = model_spec(name)
    m = _models.get(spec.name)
    if m is None:
        with _model_lock:
            m = _models.get(spec.name)
            if m is None:
                m = _load_model(spec)
                _models.clear()
                _models[spec.name] = m
    return m


def _load_model(spec: EmbedModel):
    from fastembed import TextEmbedding
    from fastembed.common.model_description import ModelSource, PoolingType

    _take_over_legacy_models()
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    kw = {}
    if spec.files:
        kw["specific_model_path"] = str(fetch_pinned(spec))
    # fastembed knows neither model — we register them (ONNX file, pooling, normalization)
    if spec.name not in {m["model"] for m in TextEmbedding.list_supported_models()}:
        TextEmbedding.add_custom_model(
            model=spec.name,
            pooling=getattr(PoolingType, spec.pooling),
            normalization=True,
            sources=ModelSource(hf=spec.source or spec.name),
            dim=spec.dim,
            model_file=spec.model_file,
            size_in_gb=spec.size_mb / 1000,
        )
    log(f"loading model {spec.name} ...")
    try:
        m = TextEmbedding(model_name=spec.name, cache_dir=str(MODELS_DIR), **kw)
    except Exception as e:
        raise ModelUnavailable(
            f"cannot load the embedding model {spec.name} (~{spec.size_mb} MB, kept in {MODELS_DIR}): {e!r}. "
            "On first use it is downloaded from huggingface.co - check the network and try again"
        ) from e
    log("model ready")
    return m


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def fetch_pinned(spec: EmbedModel) -> Path:
    """Makes sure every pinned file of the model is on disk and is exactly the checked one.

    Downloads go through huggingface_hub at the pinned commit (a half-finished download stays in a
    side file and resumes next time; it never shows up as the model). Each file is hashed once and
    remembered by size+mtime in `.verified.json`, so a warm start does not read 500 MB. A file with
    a different sha256 is deleted and refused.
    """
    target = MODELS_DIR / spec.name.replace("/", "--")
    marker = target / ".verified.json"
    try:
        verified = json.loads(marker.read_text(encoding="utf-8"))
    except FileNotFoundError:
        verified = {}  # first run
    except (OSError, ValueError) as e:
        log(f"{marker} unreadable ({e!r}) - hashing the model files again")
        verified = {}
    changed = False
    for rel, sha in spec.files:
        path = target / rel
        if path.exists():
            st = path.stat()
            if verified.get(rel) == {"sha256": sha, "size": st.st_size, "mtime_ns": st.st_mtime_ns}:
                continue
            if _sha256(path) == sha:
                verified[rel] = {"sha256": sha, "size": st.st_size, "mtime_ns": st.st_mtime_ns}
                changed = True
                continue
            log(f"{path} differs from the pinned file - downloading it again")
            path.unlink()
        _download(spec, rel, target)
        got = _sha256(path)
        if got != sha:
            path.unlink(missing_ok=True)
            raise ModelUnavailable(
                f"downloaded {rel} of {spec.name} has sha256 {got}, expected {sha} - refused and removed. "
                f"The repository {spec.source} changed; nothing in the database was touched"
            )
        st = path.stat()
        verified[rel] = {"sha256": sha, "size": st.st_size, "mtime_ns": st.st_mtime_ns}
        changed = True
    if changed:
        target.mkdir(parents=True, exist_ok=True)
        marker.write_text(json.dumps(verified, indent=1), encoding="utf-8")
    return target


def _download(spec: EmbedModel, rel: str, target: Path) -> None:
    from huggingface_hub import hf_hub_download

    log(f"downloading {spec.source}/{rel} (model {spec.name}, ~{spec.size_mb} MB in total) ...")
    try:
        hf_hub_download(spec.source, rel, revision=spec.revision, local_dir=str(target))
    except Exception as e:
        raise ModelUnavailable(
            f"cannot download the embedding model {spec.name} (~{spec.size_mb} MB) from "
            f"huggingface.co/{spec.source}: {e!r}. Nothing in the database was changed - the vectors "
            "it has keep working; try again once the network is back (the download resumes)"
        ) from e


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


def embed_passages(texts: list[str], batch: int = 32, model: str | None = None) -> np.ndarray:
    """Vectors for chunks, with the passage prefix of the given model (the configured one by default).

    Texts are sorted by length: ONNX pads to the longest item in a batch, so mixing short
    tool lines with long answers wasted several times more time and RAM.
    """
    spec = model_spec(model)
    if not texts:
        return np.zeros((0, spec.dim), dtype=np.float32)
    m = embedding_model(spec.name)
    order = sorted(range(len(texts)), key=lambda i: len(texts[i]))
    vecs = list(m.embed([spec.passage_prefix + texts[i] for i in order], batch_size=batch))
    out = np.empty((len(texts), spec.dim), dtype=np.float32)
    out[order] = np.vstack(vecs)
    return _normalize(out)


def embed_query(query: str, model: str | None = None) -> np.ndarray:
    """Query vector with the query prefix of the given model — it MUST be the model of the vectors it meets."""
    spec = model_spec(model)
    m = embedding_model(spec.name)
    vecs = list(m.embed([spec.query_prefix + query]))
    return _normalize(np.vstack(vecs))[0]


# ---------------------------------------------------------------- dates

def now_iso() -> str:
    """'2026-09-16T10:00:00.000Z' — the same shape the transcripts use, so string compare orders right."""
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def ts_to_local(ts: str) -> str:
    """ISO UTC ('2026-09-11T06:27:15.470Z') -> 'YYYY-MM-DD HH:MM' in local time."""
    try:
        d = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        if d.tzinfo is None:
            d = d.replace(tzinfo=timezone.utc)
        return d.astimezone().strftime("%Y-%m-%d %H:%M")
    except Exception:
        return ts[:16].replace("T", " ")
