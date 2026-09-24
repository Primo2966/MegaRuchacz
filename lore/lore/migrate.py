"""Re-embedding the archive with the configured model — in the background, in batches, resumable.

Run:    uv --directory C:\\dev\\claude-worker\\lore run python -m lore.migrate
Status: uv --directory C:\\dev\\claude-worker\\lore run python -m lore.migrate --status

Why it is safe to run next to a working Lore:
- the new vectors go to their own table (`vectors_next`). `vectors` keeps the old model's vectors
  and search ranks ONLY those, with the query embedded by that same old model, until the switch.
  Two models never meet in one ranking — a mixed ranking would return rubbish without a word;
- every batch is its own short transaction: an interruption (window closed, computer switched off)
  loses at most one batch, and the next run carries on from the chunks that still lack a new vector;
- chunks the indexer adds meanwhile get the old model's vector (search keeps covering them) and
  are picked up by the conversion before the switch;
- the switch — drop the old table, rename the new one, record the model — is one transaction, taken
  only when every chunk existing at that moment has a new vector;
- the progress file (lore.migration.json next to the database) is rewritten after every batch: how
  many out of how many, pace, estimate, heartbeat. "running" with an old heartbeat = a dead process.

With the database already on the configured model, the same command repairs it: chunks with no
vector or with a vector of the wrong size (written by an old process that still ran the previous
model) are embedded again. Nothing to repair = a quick no-op.
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
import time

from . import db
from .db import NEXT_TABLE, embed_passages, log, now_iso
from .index import _acquire_lock, _refresh_lock, _release_lock

BATCH = 64  # ~8 s of CPU per batch with mmlw: little to lose on interruption, negligible overhead


def lock_path():
    return db.DB_PATH.with_name(db.DB_PATH.stem + ".migration.lock")


def _clear_dead_lock(lock) -> None:
    """A lock left by a conversion whose process no longer exists (power cut, hard kill) is removed
    at once — otherwise resuming right after a restart would be refused for the next 15 minutes."""
    try:
        pid = int(lock.read_text(encoding="utf-8").strip() or "0")
    except FileNotFoundError:
        return
    except (OSError, ValueError) as e:
        log(f"lock {lock} unreadable ({e!r}) - leaving it to the age rule")
        return
    if not db.pid_alive(pid):
        log(f"removing the lock of a conversion that is no longer running (pid {pid})")
        lock.unlink(missing_ok=True)


class Progress:
    """The progress file. Written atomically (tmp + replace): a reader never sees half a file."""

    def __init__(self, source: str | None, target: str, mode: str) -> None:
        self.data = {
            "state": "running", "mode": mode, "from": source, "to": target,
            "done": 0, "total": 0, "percent": 0.0, "embedded_this_run": 0,
            "rate_per_min": None, "eta_min": None,
            "started": now_iso(), "updated": now_iso(), "pid": os.getpid(), "message": "",
        }
        self._t0 = time.time()

    def update(self, conn: sqlite3.Connection, **kw) -> None:
        d = self.data
        d.update(kw)
        d["done"], d["total"] = _counts(conn, d["to"])
        d["percent"] = round(100.0 * d["done"] / d["total"], 1) if d["total"] else 100.0
        elapsed = time.time() - self._t0
        if d["embedded_this_run"] and elapsed > 0:
            rate = d["embedded_this_run"] / elapsed * 60
            d["rate_per_min"] = round(rate, 1)
            d["eta_min"] = round((d["total"] - d["done"]) / rate, 1) if rate else None
        d["updated"] = now_iso()
        self.write()

    def write(self) -> None:
        p = db.migration_progress_path()
        tmp = p.with_name(p.name + ".tmp")
        tmp.write_text(json.dumps(self.data, ensure_ascii=False, indent=1), encoding="utf-8")
        os.replace(tmp, p)


def _counts(conn: sqlite3.Connection, target: str) -> tuple[int, int]:
    total = conn.execute("SELECT count(*) FROM chunks").fetchone()[0]
    if db.active_model(conn) != target:  # still converting: only the table aside counts
        done = conn.execute(f"SELECT count(*) FROM {NEXT_TABLE}").fetchone()[0] if db.has_table(conn, NEXT_TABLE) else 0
    else:  # repairing, or just switched
        done = conn.execute("SELECT count(*) FROM vectors WHERE length(emb) = ?",
                            (db.model_spec(target).dim * 4,)).fetchone()[0]
    return done, total


# ---------------------------------------------------------------- the two modes

def _prepare_conversion(conn: sqlite3.Connection, target: str) -> None:
    """Creates `vectors_next` for `target`, or keeps the one a previous run left (that IS the resume)."""
    conn.execute("BEGIN IMMEDIATE")
    try:
        if db._meta(conn, db.META_NEXT) != target or not db.has_table(conn, NEXT_TABLE):
            # nothing started, or a half-built table of ANOTHER model: that one is useless here
            conn.execute(f"DROP TABLE IF EXISTS {NEXT_TABLE}")
            conn.execute(db.NEXT_SCHEMA)
            conn.execute("INSERT INTO meta(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                         (db.META_NEXT, target))
            log(f"conversion to {target} started from zero")
        else:
            log(f"conversion to {target} resumed")
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise


def _drop_leftover(conn: sqlite3.Connection) -> None:
    """A database already on the configured model does not need a half-built table of anything."""
    if not db.has_table(conn, NEXT_TABLE) and db._meta(conn, db.META_NEXT) is None:
        return
    conn.execute("BEGIN IMMEDIATE")
    try:
        conn.execute(f"DROP TABLE IF EXISTS {NEXT_TABLE}")
        conn.execute("DELETE FROM meta WHERE key=?", (db.META_NEXT,))
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise
    log(f"removed a leftover {NEXT_TABLE} table")


def _pending(conn: sqlite3.Connection, mode: str, dim: int, after: int, batch: int) -> list[tuple[int, str]]:
    if mode == "convert":
        sql = (f"SELECT c.id, c.text FROM chunks c WHERE c.id > ? AND NOT EXISTS "
               f"(SELECT 1 FROM {NEXT_TABLE} n WHERE n.chunk_id = c.id) ORDER BY c.id LIMIT ?")
        return conn.execute(sql, (after, batch)).fetchall()
    sql = ("SELECT c.id, c.text FROM chunks c LEFT JOIN vectors v ON v.chunk_id = c.id "
           "WHERE c.id > ? AND (v.chunk_id IS NULL OR length(v.emb) != ?) ORDER BY c.id LIMIT ?")
    return conn.execute(sql, (after, dim * 4, batch)).fetchall()


def _store(conn: sqlite3.Connection, mode: str, target: str, rows: list[tuple[int, str]], emb) -> None:
    table = NEXT_TABLE if mode == "convert" else "vectors"
    conn.execute("BEGIN IMMEDIATE")
    try:
        # the world may have moved while the batch was being embedded — check before writing
        key, expected = (db.META_NEXT, target) if mode == "convert" else (db.META_MODEL, target)
        now = db._meta(conn, key)
        if now != expected:
            raise RuntimeError(f"meta {key} changed to {now!r} while embedding (expected {expected!r}) - stopping")
        for (cid, text), v in zip(rows, emb):
            # only if the chunk still exists with the SAME text (remask may have rewritten it meanwhile)
            conn.execute(f"INSERT OR REPLACE INTO {table}(chunk_id, emb) SELECT id, ? FROM chunks WHERE id=? AND text=?",
                         (v.tobytes(), cid, text))
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise


def _switch(conn: sqlite3.Connection, target: str) -> bool:
    """New vectors become THE vectors — only if every chunk has one. False = new chunks arrived, go on."""
    dim = db.model_spec(target).dim
    conn.execute("BEGIN IMMEDIATE")
    try:
        missing = conn.execute(f"SELECT count(*) FROM chunks c WHERE NOT EXISTS "
                               f"(SELECT 1 FROM {NEXT_TABLE} n WHERE n.chunk_id = c.id)").fetchone()[0]
        if missing:
            conn.execute("ROLLBACK")
            return False
        bad = conn.execute(f"SELECT count(*) FROM {NEXT_TABLE} WHERE length(emb) != ?", (dim * 4,)).fetchone()[0]
        if bad:
            raise RuntimeError(f"{bad} vectors in {NEXT_TABLE} are not {dim}-dimensional - refusing to switch")
        old = db.active_model(conn)
        conn.execute("DROP TABLE vectors")
        conn.execute(f"ALTER TABLE {NEXT_TABLE} RENAME TO vectors")
        conn.execute("INSERT INTO meta(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                     (db.META_MODEL, target))
        conn.execute("DELETE FROM meta WHERE key=?", (db.META_NEXT,))
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise
    log(f"switched: search now uses {target}; the {old} vectors are deleted")
    return True


# ---------------------------------------------------------------- the run

def run(conn: sqlite3.Connection | None = None, batch: int = BATCH, target: str | None = None) -> dict:
    """Converts (or repairs) until done. Returns the final progress record.

    Raises on errors and on KeyboardInterrupt — after writing the reason into the progress file.
    """
    target = target or db.EMBED_MODEL
    spec = db.model_spec(target)
    lock = lock_path()
    _clear_dead_lock(lock)
    if not _acquire_lock(lock):
        log(f"another conversion is running (lock {lock}) - not starting a second one")
        return {"state": "busy", "message": f"another conversion holds {lock}"}
    own = conn is None
    if own:
        conn = db.connect()
    progress = None
    try:
        source = db.active_model(conn)
        mode = "repair" if source == target else "convert"
        progress = Progress(source, target, mode)
        if mode == "convert":
            _prepare_conversion(conn, target)
        else:
            _drop_leftover(conn)
        progress.update(conn, message=f"{mode}: {source} -> {target}")
        log(f"{mode}: {progress.data['done']}/{progress.data['total']} chunks already have a {target} vector")
        after = 0
        while True:
            rows = _pending(conn, mode, spec.dim, after, batch)
            if not rows:
                if after:
                    after = 0  # one more pass from the start: chunks added below the cursor meanwhile
                    continue
                if mode == "convert" and not _switch(conn, target):
                    continue
                break
            emb = embed_passages([t for _, t in rows], model=target)
            _store(conn, mode, target, rows, emb)
            after = rows[-1][0]
            progress.update(conn, embedded_this_run=progress.data["embedded_this_run"] + len(rows))
            _refresh_lock(lock)
            d = progress.data
            log(f"{d['done']}/{d['total']} ({d['percent']}%), {d['rate_per_min']}/min, ~{d['eta_min']} min left")
        progress.update(conn, state="done", message=f"all chunks have {target} vectors; search uses {target}")
        log(progress.data["message"])
        return progress.data
    except KeyboardInterrupt:
        if progress:
            progress.update(conn, state="interrupted",
                            message="interrupted - run the same command again, it resumes where it stopped")
        raise
    except Exception as e:
        if progress:
            progress.update(conn, state="error", message=f"{e!r}"[:2000])
        else:  # failed before the first write: the file must still say so, not keep an old "done"
            p = Progress(None, target, "?")
            p.data.update(state="error", message=f"{e!r}"[:2000])
            p.write()
        raise
    finally:
        _release_lock(lock)
        if own:
            conn.close()


def _lower_priority() -> None:
    """Two hours of full CPU must not make the computer sluggish — the user works on it meanwhile."""
    try:
        if sys.platform == "win32":
            import ctypes
            from ctypes import wintypes
            below_normal = 0x4000
            k32 = ctypes.WinDLL("kernel32", use_last_error=True)
            k32.GetCurrentProcess.restype = wintypes.HANDLE  # a 64-bit pseudo-handle, not a C int
            k32.SetPriorityClass.argtypes = [wintypes.HANDLE, wintypes.DWORD]
            k32.SetPriorityClass.restype = wintypes.BOOL
            if not k32.SetPriorityClass(k32.GetCurrentProcess(), below_normal):
                log(f"could not lower the process priority (error {ctypes.get_last_error()}) - "
                    "the conversion competes with foreground work")
        else:
            os.nice(10)
    except Exception as e:
        log(f"could not lower the process priority: {e!r}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--status", action="store_true", help="print the state of the vectors and exit")
    ap.add_argument("--batch", type=int, default=BATCH)
    a = ap.parse_args()
    if a.status:
        conn = db.connect()
        try:
            print(json.dumps(db.vector_status(conn), ensure_ascii=False, indent=1))
        finally:
            conn.close()
        return 0
    _lower_priority()
    try:
        r = run(batch=max(1, a.batch))
    except KeyboardInterrupt:
        log("interrupted - progress kept; run again to resume")
        return 130
    except Exception as e:
        log(f"conversion FAILED: {e!r} - search keeps using the vectors it had; details in {db.migration_progress_path()}")
        return 1
    return 0 if r.get("state") == "done" else 2


if __name__ == "__main__":
    sys.exit(main())
