"""Hybrid search: FTS5 (BM25) + cosine over vectors, merged with RRF."""

from __future__ import annotations

import re
import sqlite3
import threading
from dataclasses import dataclass

import numpy as np

from .db import (EMBED_DIM, MODELS, ModelUnavailable, active_model, connect, embed_query, log, now_iso,
                 ts_to_local, vector_status)

TOP_PER_CHANNEL = 30
RRF_K = 60
MAX_SNIPPET = 600

_TOKEN = re.compile(r"\w+", re.UNICODE)


def _fts_query(q: str) -> str:
    """Turns arbitrary text into a safe FTS5 query: "tok1" OR "tok2" ..."""
    toks = [t for t in _TOKEN.findall(q) if len(t) > 1 or t.isdigit()]
    if not toks:
        return ""
    return " OR ".join(f'"{t}"' for t in toks)


def _filters(project: str | None, since: str | None, until: str | None) -> tuple[str, list]:
    where, args = [], []
    if project:
        where.append("c.project LIKE ?")
        args.append(f"%{project}%")
    if since:
        where.append("c.ts >= ?")
        args.append(since.strip())
    if until:
        u = until.strip()
        if len(u) == 10:
            u += "T23:59:59Z"
        where.append("c.ts <= ?")
        args.append(u)
    return (" AND ".join(where) if where else "1=1"), args


# ---------------------------------------------------------------- vector cache

@dataclass(frozen=True)
class _Snapshot:
    """Vectors of ONE model plus the name of that model. The query is embedded with `model` and
    compared with `matrix` only — the two cannot come from different models by construction."""

    model: str | None
    ids: np.ndarray
    matrix: np.ndarray


_EMPTY = _Snapshot(None, np.zeros(0, dtype=np.int64), np.zeros((0, EMBED_DIM), dtype=np.float32))


class _VectorCache:
    """The whole embedding matrix in RAM (scale: tens of thousands x 384-768 float32).

    Only the `vectors` table is ever read — during a conversion the new model's vectors wait in
    `vectors_next` and stay out of the ranking until the switch replaces the table as a whole.
    """

    def __init__(self) -> None:
        self.snapshot = _EMPTY
        self._state: tuple = ()
        self._lock = threading.Lock()

    def refresh(self, conn: sqlite3.Connection) -> _Snapshot:
        # one read transaction: the model name and the vectors must come from the same moment,
        # not from both sides of a switch
        began = not conn.in_transaction
        if began:
            conn.execute("BEGIN")
        try:
            model = active_model(conn)
            r = conn.execute("SELECT count(*), coalesce(max(chunk_id), 0) FROM vectors").fetchone()
            state = (model, int(r[0]), int(r[1]))
            if state == self._state:
                return self.snapshot
            with self._lock:
                if state != self._state:
                    self.snapshot = self._load(conn, model)
                    self._state = state
                return self.snapshot
        finally:
            if began:
                conn.execute("COMMIT")

    @staticmethod
    def _load(conn: sqlite3.Connection, model: str | None) -> _Snapshot:
        spec = MODELS.get(model or "")
        if spec is None:
            log(f"WARNING: vectors of an unknown model {model!r} - semantic search is OFF, full text only "
                "(python -m lore.migrate converts them)")
            return _Snapshot(model, _EMPTY.ids, _EMPTY.matrix)
        size = spec.dim * 4
        ids, rows, wrong = [], [], 0
        for cid, emb in conn.execute("SELECT chunk_id, emb FROM vectors ORDER BY chunk_id"):
            if len(emb) != size:  # e.g. written by an old process still running the previous model
                wrong += 1
                continue
            ids.append(cid)
            rows.append(np.frombuffer(emb, dtype=np.float32))
        if wrong:
            log(f"WARNING: {wrong} vectors are not {spec.dim}-dimensional ({model}) - left out of the ranking; "
                "python -m lore.migrate re-embeds them")
        if not rows:
            return _Snapshot(model, _EMPTY.ids, np.zeros((0, spec.dim), dtype=np.float32))
        return _Snapshot(model, np.array(ids, dtype=np.int64), np.vstack(rows))


_cache = _VectorCache()
# the last reason the vector channel had to stand aside (shown in stats) — never swallowed
last_vector_error: str | None = None


# ---------------------------------------------------------------- channels

def _fts_channel(conn, q: str, where: str, args: list, limit: int) -> list[int]:
    fq = _fts_query(q)
    if not fq:
        return []
    rows = conn.execute(
        f"SELECT c.id FROM chunks_fts x JOIN chunks c ON c.id = x.rowid "
        f"WHERE chunks_fts MATCH ? AND {where} ORDER BY bm25(chunks_fts) LIMIT ?",
        [fq, *args, limit],
    ).fetchall()
    return [r[0] for r in rows]


def _vector_channel(conn, q: str, where: str, args: list, limit: int, filtered: bool) -> list[int]:
    global last_vector_error
    snap = _cache.refresh(conn)
    if len(snap.ids) == 0:
        return []
    try:
        v = embed_query(q, model=snap.model)
    except ModelUnavailable as e:
        # full text still answers; the reason is logged and kept for stats, not dropped
        last_vector_error = f"{now_iso()} {e}"
        log(f"WARNING: semantic search skipped, full text only: {e}")
        return []
    ids, m = snap.ids, snap.matrix
    if filtered:
        allowed = {r[0] for r in conn.execute(f"SELECT c.id FROM chunks c WHERE {where}", args)}
        keep = np.fromiter((i in allowed for i in ids), dtype=bool, count=len(ids))
        if not keep.any():
            return []
        ids, m = ids[keep], m[keep]
    sc = m @ v
    n = min(limit, len(sc))
    top = np.argpartition(-sc, n - 1)[:n]
    top = top[np.argsort(-sc[top])]
    return [int(ids[i]) for i in top]


def _rrf(lists: list[list[int]]) -> list[int]:
    scores: dict[int, float] = {}
    for lst in lists:
        for r, cid in enumerate(lst):
            scores[cid] = scores.get(cid, 0.0) + 1.0 / (RRF_K + r + 1)
    return [cid for cid, _ in sorted(scores.items(), key=lambda kv: -kv[1])]


# ---------------------------------------------------------------- API

def search(query: str, project: str | None = None, since: str | None = None, until: str | None = None,
           limit: int = 8, conn: sqlite3.Connection | None = None) -> list[dict]:
    own = conn is None
    if own:
        conn = connect()
    try:
        where, args = _filters(project, since, until)
        filtered = bool(args)
        fts = _fts_channel(conn, query, where, args, TOP_PER_CHANNEL)
        vec = _vector_channel(conn, query, where, args, TOP_PER_CHANNEL, filtered)
        order = _rrf([fts, vec])
        if not order:
            return []
        out, seen = [], set()
        for cid in order:
            r = conn.execute("SELECT id, project, session, file, line, ts, role, text FROM chunks WHERE id=?", (cid,)).fetchone()
            if not r:
                continue
            key = (r[3], r[4])  # parts of the same turn are shown once
            if key in seen:
                continue
            seen.add(key)
            out.append({
                "id": r[0],
                "date": ts_to_local(r[5]),
                "project": r[1],
                "session": r[2][:8],
                "role": r[6],
                "text": r[7][:MAX_SNIPPET],
                "source": "fts+vector" if cid in fts and cid in vec else ("fts" if cid in fts else "vector"),
            })
            if len(out) >= limit:
                break
        return out
    finally:
        if own:
            conn.close()


def _full_text(conn, file: str, line: int, role: str) -> str:
    rows = conn.execute(
        "SELECT part, text FROM chunks WHERE file=? AND line=? AND role=? ORDER BY part", (file, line, role)
    ).fetchall()
    from .index import OVERLAP
    out = ""
    for part, t in rows:
        if part == 0:
            out += ("\n" if out else "") + t
        else:
            out += t[OVERLAP:]  # parts are joined without repeating the overlap
    return out


def context(chunk_id: int, count: int = 3, conn: sqlite3.Connection | None = None) -> dict:
    own = conn is None
    if own:
        conn = connect()
    try:
        r = conn.execute("SELECT project, session, file, line FROM chunks WHERE id=?", (chunk_id,)).fetchone()
        if not r:
            return {"error": f"no chunk with id {chunk_id}"}
        project, session, file, line = r
        before = [x[0] for x in conn.execute(
            "SELECT DISTINCT line FROM chunks WHERE file=? AND line<? ORDER BY line DESC LIMIT ?", (file, line, count))]
        after = [x[0] for x in conn.execute(
            "SELECT DISTINCT line FROM chunks WHERE file=? AND line>? ORDER BY line ASC LIMIT ?", (file, line, count))]
        lines = sorted(before) + [line] + after
        turns = []
        for ln in lines:
            for cid, ts, role in conn.execute(
                "SELECT min(id), ts, role FROM chunks WHERE file=? AND line=? GROUP BY role ORDER BY min(id)", (file, ln)):
                turns.append({
                    "id": cid,
                    "date": ts_to_local(ts),
                    "role": role,
                    "text": _full_text(conn, file, ln, role),
                    "is_match": ln == line,
                })
        return {"project": project, "session": session, "turns": turns}
    finally:
        if own:
            conn.close()


def stats(conn: sqlite3.Connection | None = None) -> dict:
    own = conn is None
    if own:
        conn = connect()
    try:
        sessions, total = conn.execute("SELECT count(DISTINCT session), count(*) FROM chunks").fetchone()
        files = conn.execute("SELECT count(*) FROM files").fetchone()[0]
        per = [
            {"project": p, "sessions": s, "chunks": n, "last": ts_to_local(t)}
            for p, s, n, t in conn.execute(
                "SELECT project, count(DISTINCT session), count(*), max(ts) FROM chunks GROUP BY project ORDER BY max(ts) DESC")
        ]
        last = conn.execute("SELECT value FROM meta WHERE key='last_indexed'").fetchone()
        from .db import DB_PATH
        size = DB_PATH.stat().st_size if DB_PATH.exists() else 0
        return {
            "sessions": sessions, "chunks": total, "files": files,
            "last_indexed": ts_to_local(last[0]) if last else None,
            "database": str(DB_PATH), "size_MB": round(size / 1e6, 1),
            "vectors": vector_status(conn),
            "last_vector_error": last_vector_error,
            "projects": per,
        }
    finally:
        if own:
            conn.close()
