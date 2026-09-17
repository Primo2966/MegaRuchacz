"""A one-off dig through the WHOLE archive — knowledge found by repetition, not by reading.

The daily harvest (lore.facts) only ever sees yesterday. Everything the user explained in the
months before it sits in the archive unread, and pushing fifty thousand chunks through a model
costs tens of dollars. The vectors already know where the repetitions are: chunks that mean the
same thing lie close together even when the words and the language differ. A cluster of such
chunks coming from MANY SEPARATE SESSIONS means exactly one thing — the user had to explain that
thing over and over, window after window. That is a candidate for a fact, and it comes with its
own evidence.

The model then reads one representative per cluster — a few dozen snippets instead of the archive.

The database is opened read only. The run marker of the daily harvest is NOT moved unless it is
asked for explicitly: moving it is a decision to skip material for good.

Run: uv --directory C:\\dev\\claude-worker\\lore run python -m lore.mining
     [--proba] [--ile N] [--przesun-znacznik]
"""

from __future__ import annotations

import sqlite3
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from . import facts
from .db import DB_PATH, EMBED_DIM, log, ts_to_local

# e5 keeps even unrelated sentences around 0.7-0.8, so the threshold has to sit well above that:
# below ~0.85 whole unrelated topics melt into one cluster and the evidence stops meaning anything.
# Tighter than 0.9 and the same thought reworded in another language falls out of its own cluster.
SIMILARITY = 0.88
MIN_SESSIONS = 3  # the heart of it: the same thing in 3 different windows, not 3 times in one window
# "ok", "tak", "dalej" repeat across hundreds of sessions and would win every ranking; a thing the
# user had to explain over and over is never four words long
MIN_CHARS = 80
# Only what the USER said. The first run on a real archive put the assistant's own
# report boilerplate at the top of the ranking — "task set up, now I'm checking it",
# "yes, safe to push, the run came out clean" — repeated across 34 sessions because
# the assistant writes status the same way every time. That is a repeated FORM, not
# repeated knowledge. What the user had to explain over and over is what we are after.
MINED_ROLES = ("user",)
DEFAULT_CLUSTERS = 60  # how many representatives the model gets to read
PREVIEW = 10  # clusters listed in the dry run, so the quality can be judged before paying anything
BATCH = 256  # rows of the similarity matrix at once — 256 x 52 000 float32 is ~50 MB
MAX_SNIPPET = 700
MAX_PREVIEW_SNIPPET = 160


# ---------------------------------------------------------------- the archive, read only

def open_readonly(path: Path | None = None) -> sqlite3.Connection:
    """Opens the archive with no way to write to it — this job reads a lot and must not touch a byte.

    mode=ro is enforced by SQLite itself; query_only is the second lock on the same door.
    """
    path = path or DB_PATH
    conn = sqlite3.connect(f"{path.as_uri()}?mode=ro", uri=True, timeout=60, check_same_thread=False)
    conn.execute("PRAGMA query_only=ON")
    return conn


@dataclass
class Chunk:
    """One chunk of the archive — only what the clustering and the snippet need."""
    id: int
    session: str
    ts: str
    text: str


def load(conn: sqlite3.Connection) -> tuple[list[Chunk], np.ndarray]:
    """Chunks that have a vector, minus the noise, plus their embedding matrix (rows aligned)."""
    rows = conn.execute(
        "SELECT c.id, c.session, c.ts, c.role, c.text, v.emb "
        "FROM chunks c JOIN vectors v ON v.chunk_id = c.id ORDER BY c.id"
    ).fetchall()
    chunks, vectors = [], []
    for cid, session, ts, role, text, emb in rows:
        if role.split(":")[-1] not in MINED_ROLES or len(text.strip()) < MIN_CHARS:
            continue
        vec = np.frombuffer(emb, dtype=np.float32)
        if vec.shape[0] != EMBED_DIM:  # a truncated blob is a reason to skip a row, not to crash
            continue
        chunks.append(Chunk(int(cid), session, ts, text))
        vectors.append(vec)
    if not chunks:
        return [], np.zeros((0, EMBED_DIM), dtype=np.float32)
    return chunks, _unit(np.vstack(vectors))


def newest_ts(conn: sqlite3.Connection) -> str:
    """The last timestamp in the archive — where the marker would land. Every role counts here."""
    row = conn.execute("SELECT max(ts) FROM chunks").fetchone()
    return (row[0] if row else "") or ""


def _unit(m: np.ndarray) -> np.ndarray:
    """Rows to unit length, so a dot product is the cosine. The stored vectors already are — almost."""
    m = np.asarray(m, dtype=np.float32)
    norms = np.linalg.norm(m, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    return m / norms


# ---------------------------------------------------------------- clustering, without a model

def cluster(matrix: np.ndarray, threshold: float = SIMILARITY, batch: int = BATCH) -> list[list[int]]:
    """Greedy leader clustering: the first free row becomes a seed, everything close enough joins it.

    Counted in batches on purpose — the full similarity matrix of the archive is terabytes, while
    one batch of rows against the whole matrix is tens of megabytes. Every row is multiplied once,
    so the whole thing is a single sweep.
    """
    n = len(matrix)
    owner = np.full(n, -1, dtype=np.int64)
    groups: list[list[int]] = []
    for start in range(0, n, batch):
        stop = min(start + batch, n)
        if (owner[start:stop] != -1).all():
            continue  # every row here already joined an earlier seed — nothing to multiply
        sims = matrix[start:stop] @ matrix.T
        for i in range(stop - start):
            seed = start + i
            if owner[seed] != -1:
                continue
            near = np.nonzero(sims[i] >= threshold)[0]
            free = near[owner[near] == -1]  # a chunk belongs to the first seed that caught it
            owner[free] = len(groups)
            groups.append([int(x) for x in free])
    return groups


@dataclass
class Cluster:
    """A cluster that passed the session test, carrying the evidence of how strong its repetition is."""
    members: list[int]
    representative: int  # index of the chunk closest to the middle
    sessions: int
    months: int
    first_ts: str
    last_ts: str

    def strength(self) -> tuple[int, int, int]:
        """Different sessions first, then the spread over months, then sheer size."""
        return self.sessions, self.months, len(self.members)


def describe(groups: list[list[int]], chunks: list[Chunk], matrix: np.ndarray,
             min_sessions: int = MIN_SESSIONS) -> list[Cluster]:
    """Groups -> clusters worth reading, strongest first.

    A group living inside a single session is dropped here: ten chunks of one long discussion are
    one discussion, not knowledge repeated to every new window.
    """
    out = []
    for members in groups:
        sessions = {chunks[i].session for i in members}
        if len(sessions) < min_sessions:
            continue
        stamps = sorted(chunks[i].ts for i in members)
        out.append(Cluster(
            members=members,
            representative=_representative(members, matrix),
            sessions=len(sessions),
            # 'YYYY-MM': something coming back for half a year is worth more than a busy single week
            months=len({s[:7] for s in stamps}),
            first_ts=stamps[0],
            last_ts=stamps[-1],
        ))
    out.sort(key=Cluster.strength, reverse=True)
    return out


def _representative(members: list[int], matrix: np.ndarray) -> int:
    """The member closest to the middle of the cluster — the one saying what all of them say.

    Not the seed: the seed is merely whichever chunk the sweep reached first, and it can sit on the
    edge of the cluster.
    """
    block = matrix[members]
    centre = block.mean(axis=0)
    norm = float(np.linalg.norm(centre))
    if norm:
        centre = centre / norm
    return int(members[int(np.argmax(block @ centre))])


# ---------------------------------------------------------------- material for the model

def snippet(text: str, limit: int = MAX_SNIPPET) -> str:
    one = " ".join(text.split())
    return one if len(one) <= limit else one[:limit].rstrip() + "\u2026"


def material(clusters: list[Cluster], chunks: list[Chunk],
             max_chars: int = facts.MAX_INPUT_CHARS) -> str:
    """One representative per cluster, each carrying the evidence of its own repetition.

    The session count travels next to the snippet on purpose: it is the strongest hint the model
    gets that a sentence is durable knowledge and not a remark someone made once.
    """
    pieces, total = [], 0
    for c in clusters:
        chunk = chunks[c.representative]
        piece = (f"[sesje: {c.sessions}, miesiace: {c.months}, "
                 f"{ts_to_local(c.first_ts)[:10]} - {ts_to_local(c.last_ts)[:10]}]\n"
                 f"{snippet(chunk.text)}")
        if total + len(piece) > max_chars:
            break
        pieces.append(piece)
        total += len(piece)
    return "\n\n".join(pieces)


PROMPT = facts.PROMPT + """

Ten materiał jest szczególny. To nie są kolejne fragmenty z jednego dnia, tylko PRZEDSTAWICIELE
SKUPISK: urywki, które w całym archiwum rozmów powtórzyły się w wielu osobnych oknach. Nagłówek
każdego urywka mówi, w ilu różnych sesjach i w ilu miesiącach ta sama rzecz wracała. Im wyższe te
liczby, tym pewniejsze, że masz przed sobą trwałą wiedzę, a nie jednorazową uwagę — traktuj je jako
dowód wagi, a nie jako treść faktu. Samych liczb do faktów nie przepisuj."""


def ask_model(text: str) -> str:
    """The daily harvest's call with the mining instruction — same tool, same switches, same envelope.

    Which agent CLI the machine has is decided there, once, so a Codex-only machine digs through the
    archive as well; the only thing this job changes is the instruction.
    """
    return facts.ask_model(text, instruction=PROMPT)


# ---------------------------------------------------------------- the whole run

def run(limit: int = DEFAULT_CLUSTERS, dry_run: bool = False, move_marker: bool = False,
        ask=ask_model, conn: sqlite3.Connection | None = None) -> dict:
    """One dig: archive -> clusters -> a handful of representatives -> model -> waiting room."""
    own = conn is None
    if own and not DB_PATH.exists():
        return {"status": "no-database", "chunks": 0, "groups": 0, "clusters": 0, "taken": [],
                "preview": [], "facts": [], "added": [], "marker": "", "newest": "",
                "note": f"no database at {DB_PATH} — index the conversations first"}
    if own:
        conn = open_readonly()
    try:
        chunks, matrix = load(conn)
        newest = newest_ts(conn)
    finally:
        if own:
            conn.close()
    groups = cluster(matrix)
    clusters = describe(groups, chunks, matrix)
    taken = clusters[:max(1, limit)]
    out = {"status": "ok", "chunks": len(chunks), "groups": len(groups), "clusters": len(clusters),
           "taken": taken, "facts": [], "added": [], "marker": "", "newest": newest,
           "preview": [(c.sessions, c.months, snippet(chunks[c.representative].text, MAX_PREVIEW_SNIPPET))
                       for c in taken[:PREVIEW]]}
    if not chunks:
        out["status"] = "no-material"
        out["note"] = "no chunks with vectors in the archive — index the conversations first"
        return out
    if not taken:
        out["status"] = "no-clusters"
        out["note"] = (f"{len(groups)} clusters found, none of them reaching {MIN_SESSIONS} different"
                       f" sessions — nothing worth paying a model for")
        return out
    if dry_run:
        out["status"] = "dry-run"
        cli = facts.available_model_cli()
        out["model_available"] = cli is not None
        out["model_cli"] = cli.name if cli else ""
        return out
    out["facts"] = facts.parse_facts(ask(material(taken, chunks)))
    out["added"] = facts.append_facts(out["facts"])
    facts.record_cost(found=len(out["facts"]))  # same tally as the daily harvest: same tokens paid
    if move_marker and newest:
        facts.write_marker(newest)
        out["marker"] = newest
    return out


def _report(r: dict, move_marker: bool) -> None:
    if r["status"] in ("no-database", "no-material", "no-clusters"):
        log(r["note"])
        return
    log(f"archive: {r['chunks']} chunks read, {r['groups']} clusters,"
        f" {r['clusters']} of them from at least {MIN_SESSIONS} different sessions")
    if r["status"] == "dry-run":
        log("dry run — nothing written, no model called;"
            f" model tool: {r['model_cli'] or 'NONE in PATH'}")
        log(f"{len(r['taken'])} clusters would go to the model, the strongest {len(r['preview'])} of them:")
        for sessions, months, text in r["preview"]:
            log(f"  [{sessions} sesji / {months} mies.] {text}")
    else:
        log(f"facts from the model: {len(r['facts'])}, new in {facts.CANDIDATES_PATH}: {len(r['added'])}")
        for fact in r["added"]:
            log(f"  + ({fact.label()}) {fact.text}")
    _report_marker(r, move_marker)


def _report_marker(r: dict, move_marker: bool) -> None:
    """Moving the marker skips material for good — it gets spelled out either way."""
    if r["marker"]:
        log(f"marker moved to {r['marker']} — the daily harvest will NOT read anything older than that")
    elif move_marker:
        log("marker NOT moved — the run never got as far as the model")
    else:
        log("marker untouched: the daily harvest will still walk through this material on its own."
            f" To skip it, run again with -PrzesunZnacznik (marker -> {r['newest'] or 'the last chunk'},"
            " everything older is never harvested again)")


def _options(argv: list[str]) -> tuple[bool, int, bool]:
    dry_run = bool({"--proba", "--dry-run"} & set(argv))
    limit = DEFAULT_CLUSTERS
    if "--ile" in argv:
        value = argv[argv.index("--ile") + 1:argv.index("--ile") + 2]
        if value and value[0].isdigit():
            limit = int(value[0])
    return dry_run, max(1, limit), "--przesun-znacznik" in argv


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    dry_run, limit, move_marker = _options(argv)
    try:
        r = run(limit=limit, dry_run=dry_run, move_marker=move_marker)
    except facts.ModelMissing as e:
        log(f"{e} — install Claude Code (npm install -g @anthropic-ai/claude-code) or Codex")
        return 1
    except Exception as e:  # a one-off job still ends with a readable line, not a traceback
        log(f"digging through the archive failed: {e!r}")
        return 1
    _report(r, move_marker)
    return 0


if __name__ == "__main__":
    sys.exit(main())
