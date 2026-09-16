"""Hybrid search: FTS5 (BM25) + cosine over vectors, merged with RRF."""

from __future__ import annotations

import re
import sqlite3
import threading

import numpy as np

from .db import EMBED_DIM, connect, embed_query, ts_to_local

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

class _VectorCache:
    """The whole embedding matrix in RAM (scale: tens of thousands x 384 float32)."""

    def __init__(self) -> None:
        self.ids = np.zeros(0, dtype=np.int64)
        self.matrix = np.zeros((0, EMBED_DIM), dtype=np.float32)
        self._state: tuple[int, int] = (-1, -1)
        self._lock = threading.Lock()

    def refresh(self, conn: sqlite3.Connection) -> None:
        r = conn.execute("SELECT count(*), coalesce(max(chunk_id), 0) FROM vectors").fetchone()
        state = (int(r[0]), int(r[1]))
        if state == self._state:
            return
        with self._lock:
            if state == self._state:
                return
            rows = conn.execute("SELECT chunk_id, emb FROM vectors ORDER BY chunk_id").fetchall()
            if rows:
                self.ids = np.fromiter((x[0] for x in rows), dtype=np.int64, count=len(rows))
                self.matrix = np.vstack([np.frombuffer(x[1], dtype=np.float32) for x in rows])
            else:
                self.ids = np.zeros(0, dtype=np.int64)
                self.matrix = np.zeros((0, EMBED_DIM), dtype=np.float32)
            self._state = state


_cache = _VectorCache()


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
    _cache.refresh(conn)
    if len(_cache.ids) == 0:
        return []
    v = embed_query(q)
    ids, m = _cache.ids, _cache.matrix
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
            "projects": per,
        }
    finally:
        if own:
            conn.close()
