"""MCP server "lore" (stdio, mcp SDK 2.x — MCPServer, formerly FastMCP) — memory of every Claude Code conversation on this machine.

Run: uv --directory C:\\dev\\claude-worker\\lore run python -m lore.server
"""

from __future__ import annotations

import threading

from mcp.server.mcpserver import MCPServer

from . import search as _search
from .db import log
from .index import index

mcp = MCPServer(
    "lore",
    instructions=(
        "Memory of every Claude Code conversation on this machine (all projects and windows). "
        "Call lore_search when you start a task, to check what has already been settled in other "
        "sessions, before you ask the user about things they may have explained elsewhere."
    ),
)

_indexing_lock = threading.Lock()


def _index_in_background() -> None:
    with _indexing_lock:
        try:
            n = index(quiet=True)
            log(f"background indexing: +{n} chunks")
        except Exception as e:  # the server must not go down
            log(f"background indexing failed: {e!r}")


@mcp.tool()
def lore_search(query: str, project: str | None = None, since: str | None = None,
                until: str | None = None, limit: int = 8) -> list[dict]:
    """Searches the history of ALL Claude Code conversations on this machine (other windows, other
    projects, earlier days). Use it when you start a task, to check what has already been settled in
    other windows — e.g. "what did we decide about oil variants on eBay", "how did we configure the
    Allegro API". Hybrid search: full text (Polish/German/English, diacritics ignored) + semantic
    (multilingual embeddings — a German query finds a Polish conversation).

    Args:
        query: a question or keywords, in any language.
        project: optional filter — part of the project directory name (e.g. "ecommerce-helper").
        since: optional start date, ISO (e.g. "2026-09-01").
        until: optional end date, ISO (e.g. "2026-09-11").
        limit: how many results to return (8 by default).

    Returns a list of: date (YYYY-MM-DD HH:MM, local time), project, session (short), role
    (user / assistant / tool / result / summary; the "agent:" prefix means a subagent),
    text (<=600 characters), id (for lore_context).
    """
    return _search.search(query, project=project, since=since, until=until, limit=max(1, min(limit, 50)))


@mcp.tool()
def lore_context(id: int, count: int = 3) -> dict:
    """Shows the full turn with the given id (from lore_search) plus `count` preceding and
    `count` following turns from the same session, in chronological order — so you can see
    in what context something was settled."""
    return _search.context(id, count=max(0, min(count, 20)))


@mcp.tool()
def lore_reindex() -> dict:
    """Runs incremental indexing of the transcripts (adds only new turns).
    Use it when you want to be sure you see what was settled a moment ago in another window."""
    if not _indexing_lock.acquire(timeout=300):
        return {"new_chunks": 0, "note": "background indexing is still running"}
    try:
        n = index(quiet=True)
    finally:
        _indexing_lock.release()
    return {"new_chunks": n}


@mcp.tool()
def lore_stats() -> dict:
    """Number of indexed sessions and chunks (in total and per project), the date of the last
    indexing run, the location and size of the database, and the state of the vectors: which
    model they belong to and how far a conversion to the configured model is (with a warning
    whenever they do not match)."""
    return _search.stats()


def main() -> None:
    threading.Thread(target=_index_in_background, name="lore-indexing", daemon=True).start()
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
