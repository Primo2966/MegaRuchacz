"""Daily harvest of durable facts out of recent conversations.

Reads the chunks indexed since the last run, asks a model for facts that stay true, and drops
them into a waiting room (~/.claude/wiedza/kandydaci.md). Nothing is ever written to the rules
the agent obeys (~/.claude/CLAUDE.md) — an automaton can carve a nonsense taken out of context
into stone, so the machine proposes and the human approves.

Run: uv --directory C:\\dev\\claude-worker\\lore run python -m lore.facts [--proba] [--nadrabiaj N]
"""

from __future__ import annotations

import json
import math
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

from .db import CLAUDE_HOME, DB_PATH, connect, log, ts_to_local

KNOWLEDGE_DIR = CLAUDE_HOME / "wiedza"
MARKER_PATH = KNOWLEDGE_DIR / ".ostatnie-wyciaganie"
CANDIDATES_PATH = KNOWLEDGE_DIR / "kandydaci.md"
RULES_PATH = CLAUDE_HOME / "CLAUDE.md"  # read only — the waiting room is the only thing we write

# a cost limit, not a suggestion: one run never sends more than this to the model
MAX_INPUT_CHARS = 60_000
DEFAULT_WINDOW_H = 24
# tool calls and their output are noise, not knowledge about the user ("agent:" prefix included)
SKIPPED_ROLES = frozenset({"tool", "result"})
MIN_FACT_CHARS = 10  # a single word is not a fact
MODEL_TIMEOUT_S = 300

# --safe-mode: no CLAUDE.md, no MCP servers, no hooks — the extractor must not pull the user's
#   rules into the answer, nor start the lore server again from inside a lore job.
# --no-session-persistence: without it every run leaves a transcript holding yesterday's material,
#   the indexer picks it up and the next run harvests its own output.
# --permission-prompts none: nobody is sitting at the console at 08:05 to answer a prompt.
# --json-schema: `claude -p` is an agent, not a text endpoint — asked for plain text it adds
#   questions and offers of help around the list. A schema gives a list and nothing else.
FACTS_SCHEMA = json.dumps({
    "type": "object",
    "properties": {"fakty": {"type": "array", "items": {"type": "string"}}},
    "required": ["fakty"],
    "additionalProperties": False,
}, ensure_ascii=False)
MODEL_ARGS = ("-p", "--safe-mode", "--no-session-persistence", "--permission-prompts", "none",
              "--output-format", "json", "--json-schema", FACTS_SCHEMA)

PROMPT = """Na wejściu (stdin) dostajesz fragmenty rozmów użytkownika z agentem AI.

Wypisz wyłącznie TRWAŁE fakty o użytkowniku, jego firmie, jego produktach i sposobie pracy — takie,
które będą prawdziwe za pół roku i które warto znać w każdym nowym oknie rozmowy.

Pomiń: bieżący stan zadań, chwilowe decyzje, plany na dziś, opisy błędów i wszystko, co i tak widać
w kodzie (nazwy plików, funkcji, struktura repozytorium).

To jest automat: Twoja odpowiedź leci wprost do pliku, nikt jej teraz nie czyta. Nie zwracaj się do
użytkownika, nie zadawaj pytań, nie proponuj działań, niczego nie zapisuj i nie sięgaj po narzędzia
— jedyne, co masz zrobić, to wypisać listę.

Każdy fakt w jednej linii, po polsku, bez numeracji, bez nagłówków i bez pogrubień.
Jeśli nie ma ani jednego takiego faktu — nie wypisuj nic."""

CANDIDATES_HEADER = """# Kandydaci do trwałej wiedzy

Propozycje wyłowione automatycznie z rozmów — jeszcze nic nie znaczą. Odhacz to, co prawdziwe,
i przenieś do ~/.claude/CLAUDE.md ręcznie; nic stąd nie trafia tam samo.

"""

_BULLET = re.compile(r"^\s*(?:[-*\u2022]|\d+[.)])\s*")
_CANDIDATE_LINE = re.compile(r"^\s*-\s*\[[ xX]\]\s*(?:\[\d{4}-\d{2}-\d{2}\]\s*)?(.+)$")
_PUNCTUATION = re.compile(r"[^\w\s]", re.UNICODE)


class ModelMissing(RuntimeError):
    """`claude` is not in PATH — there is nothing to extract the facts with."""


# ---------------------------------------------------------------- the run marker

def iso_utc(d: datetime) -> str:
    """'2026-09-16T08:05:00.000Z' — the same shape the transcripts use, so plain string compare works."""
    return d.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def since_marker() -> str:
    """ISO of the last run; a missing or broken marker means 'the last 24 hours'."""
    try:
        saved = MARKER_PATH.read_text(encoding="utf-8").strip()
    except OSError:
        saved = ""
    if saved:
        try:
            datetime.fromisoformat(saved.replace("Z", "+00:00"))
            return saved
        except ValueError:
            log(f"unreadable marker {MARKER_PATH.name}: {saved!r} — falling back to the last {DEFAULT_WINDOW_H} h")
    return iso_utc(datetime.now(timezone.utc) - timedelta(hours=DEFAULT_WINDOW_H))


def write_marker(ts: str) -> None:
    """The marker moves only after a run that really asked the model — a failed run has to catch up."""
    KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    MARKER_PATH.write_text(ts + "\n", encoding="utf-8")


# ---------------------------------------------------------------- material for the model

@dataclass
class Material:
    texts: list[str] = field(default_factory=list)  # chronological
    chars: int = 0
    last_ts: str = ""  # where the marker goes after a successful run
    pending: int = 0  # chunks left for the next runs
    pending_chars: int = 0
    dropped: int = 0  # lost on a single timestamp bigger than the whole cap — normally 0

    def joined(self) -> str:
        return "\n\n".join(self.texts)

    def runs_left(self) -> int:
        return math.ceil(self.pending_chars / MAX_INPUT_CHARS)


def collect(conn: sqlite3.Connection, since: str) -> Material:
    """Chunks newer than `since`, OLDEST first up to the cap.

    Oldest first on purpose: the marker moves exactly as far as we got, so a backlog after a few
    days away is worked off run by run instead of being silently skipped over.
    """
    rows = conn.execute(
        "SELECT ts, role, text FROM chunks WHERE ts > ? ORDER BY ts, id", (since,)
    ).fetchall()
    kept = [
        (ts, f"[{ts_to_local(ts)}] {role}: {text}")
        for ts, role, text in rows
        if role.split(":")[-1] not in SKIPPED_ROLES
    ]
    material = Material()
    taken = 0
    for ts, piece in kept:
        if material.chars + len(piece) > MAX_INPUT_CHARS:
            break
        material.texts.append(piece)
        material.chars += len(piece)
        material.last_ts = ts
        taken += 1
    taken += _align_to_timestamp(material, kept, taken)
    rest = kept[taken:]
    material.pending = len(rest)
    material.pending_chars = sum(len(p) for _, p in rest)
    return material


def _align_to_timestamp(material: Material, kept: list[tuple[str, str]], taken: int) -> int:
    """Moves the cut onto a timestamp boundary — 'ts > marker' would drop the rest of a split turn.

    Returns how many further chunks leave the backlog: normally 0, and only in the degenerate case
    of one timestamp heavier than the whole cap the leftovers of that turn (counted as dropped).
    """
    if taken == 0 or taken == len(kept) or material.last_ts != kept[taken][0]:
        return 0
    back = taken
    while back and kept[back - 1][0] == material.last_ts:
        back -= 1
    if back == 0:  # a single turn larger than the cap — we take what fits and lose its tail
        material.dropped = sum(1 for ts, _ in kept[taken:] if ts == material.last_ts)
        log(f"one timestamp ({material.last_ts}) exceeds the {MAX_INPUT_CHARS} character cap"
            f" — {material.dropped} chunks of that turn are skipped")
        return material.dropped
    del material.texts[back:]
    material.chars = sum(len(t) for t in material.texts)
    material.last_ts = kept[back - 1][0]
    return back - taken  # negative: those chunks go back to the backlog


# ---------------------------------------------------------------- the model

def ask_model(material: str) -> str:
    """`claude -p`: the instruction in argv, the material on stdin — 60 k characters do not fit in argv.

    It runs in an empty scratch directory on purpose: started in a repository it answers about
    that code, and started in the knowledge directory it starts tidying the files it finds there.
    """
    exe = shutil.which("claude")
    if not exe:
        raise ModelMissing("no `claude` in PATH")
    empty = tempfile.mkdtemp(prefix="lore-facts-")
    try:
        r = subprocess.run(
            [exe, *MODEL_ARGS, PROMPT], input=material, capture_output=True, cwd=empty,
            text=True, encoding="utf-8", errors="replace", timeout=MODEL_TIMEOUT_S,
        )
    finally:
        shutil.rmtree(empty, ignore_errors=True)
    if r.returncode != 0:
        raise RuntimeError(f"claude -p returned {r.returncode}: {(r.stderr or '').strip()[:200]}")
    return r.stdout or ""


def parse_facts(output: str) -> list[str]:
    """Model output -> facts: the structured answer when there is one, otherwise line by line."""
    structured = _structured(output)
    facts = []
    # an empty list from the envelope means "no facts" — it must not fall back to the raw text
    for raw in output.splitlines() if structured is None else structured:
        line = _BULLET.sub("", raw).strip()
        if len(line) < MIN_FACT_CHARS or line.startswith("#") or line.endswith(("?", ":")):
            continue  # a question or a heading above a list is not a fact
        facts.append(line)
    return facts


def _structured(output: str) -> list[str] | None:
    """The `--output-format json` envelope -> the list of facts; None when it is plain text."""
    try:
        envelope = json.loads(output)
        answer = envelope.get("structured_output") or json.loads(envelope.get("result") or "")
        facts = answer["fakty"]
    except (AttributeError, KeyError, TypeError, ValueError):
        return None
    return [str(f) for f in facts] if isinstance(facts, list) else None


# ---------------------------------------------------------------- the waiting room

def normalize(text: str) -> str:
    """Comparison key: lower case, no punctuation, single spaces. Deliberately nothing smarter."""
    return " ".join(_PUNCTUATION.sub(" ", text.lower()).split())


def _lines(path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []


def known_facts() -> set[str]:
    """Normalized facts already waiting in the candidates file or already standing in the rules."""
    known = set()
    for line in _lines(CANDIDATES_PATH):
        m = _CANDIDATE_LINE.match(line)
        if m:
            known.add(normalize(m.group(1)))
    for line in _lines(RULES_PATH):
        known.add(normalize(_BULLET.sub("", line).strip()))
    known.discard("")
    return known


def append_facts(facts: list[str], day: str | None = None) -> list[str]:
    """Appends the facts nobody knows yet; returns the ones actually written."""
    known = known_facts()
    fresh = []
    for fact in facts:
        key = normalize(fact)
        if not key or key in known:
            continue
        known.add(key)  # the model likes to repeat itself inside one answer as well
        fresh.append(fact)
    if not fresh:
        return []
    day = day or datetime.now().strftime("%Y-%m-%d")
    KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    first_time = not CANDIDATES_PATH.exists()
    with open(CANDIDATES_PATH, "a", encoding="utf-8", newline="\n") as f:
        if first_time:
            f.write(CANDIDATES_HEADER)
        for fact in fresh:
            f.write(f"- [ ] [{day}] {fact}\n")
    return fresh


# ---------------------------------------------------------------- the whole run

def run(dry_run: bool = False, ask=ask_model, conn: sqlite3.Connection | None = None) -> dict:
    """One pass: material -> model -> waiting room. Never raises on missing data, only reports it."""
    since = since_marker()
    own = conn is None
    if own and not DB_PATH.exists():
        return {"status": "no-database", "since": since, "chunks": 0, "chars": 0, "pending": 0,
                "runs_left": 0, "dropped": 0, "facts": [], "added": [],
                "note": f"no database at {DB_PATH} — index the conversations first"}
    if own:
        conn = connect()
    try:
        material = collect(conn, since)
    finally:
        if own:
            conn.close()
    out = {"status": "ok", "since": since, "chunks": len(material.texts), "chars": material.chars,
           "pending": material.pending, "runs_left": material.runs_left(),
           "dropped": material.dropped, "facts": [], "added": []}
    if not material.texts:
        out["status"] = "no-material"
        out["note"] = f"no conversations newer than {since}"
        return out
    if dry_run:
        out["status"] = "dry-run"
        out["model_available"] = shutil.which("claude") is not None
        return out
    out["facts"] = parse_facts(ask(material.joined()))
    out["added"] = append_facts(out["facts"])
    write_marker(material.last_ts)  # exactly as far as we got, so the next run picks up from here
    return out


def catch_up(runs: int = 1, dry_run: bool = False, ask=ask_model,
             conn: sqlite3.Connection | None = None) -> list[dict]:
    """Up to `runs` passes in a row, stopping early once the backlog is worked off."""
    out = []
    for _ in range(max(1, runs)):
        r = run(dry_run=dry_run, ask=ask, conn=conn)
        out.append(r)
        # a dry run changes nothing, so a second pass would only repeat the same answer
        if dry_run or r["status"] != "ok" or not r["pending"]:
            break
    return out


def _report(r: dict) -> None:
    if r["status"] in ("no-database", "no-material"):
        log(r["note"])
        return
    tail = f", {r['dropped']} chunks dropped" if r["dropped"] else ""
    log(f"material: {r['chunks']} chunks, {r['chars']} characters since {r['since']}{tail}")
    if r["status"] == "dry-run":
        log(f"dry run — nothing written; claude in PATH: {'yes' if r['model_available'] else 'NO'}")
    else:
        log(f"facts from the model: {len(r['facts'])}, new in {CANDIDATES_PATH}: {len(r['added'])}")
        for fact in r["added"]:
            log(f"  + {fact}")
    if r["pending"]:
        log(f"backlog: {r['pending']} chunks waiting, about {r['runs_left']} more run(s)"
            f" — catch up with:  -Nadrabiaj {r['runs_left']}")


def _options(argv: list[str]) -> tuple[bool, int]:
    dry_run = bool({"--proba", "--dry-run"} & set(argv))
    runs = 1
    if "--nadrabiaj" in argv:
        value = argv[argv.index("--nadrabiaj") + 1:argv.index("--nadrabiaj") + 2]
        runs = int(value[0]) if value and value[0].isdigit() else 1
    return dry_run, max(1, runs)


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    dry_run, runs = _options(argv)
    try:
        results = catch_up(runs=runs, dry_run=dry_run)
    except ModelMissing as e:
        log(f"{e} — install Claude Code: npm install -g @anthropic-ai/claude-code")
        return 1
    except Exception as e:  # a scheduled task must end with a readable line, not a traceback
        log(f"extracting facts failed: {e!r}")
        return 1
    for i, r in enumerate(results, 1):
        if len(results) > 1:
            log(f"--- pass {i}/{len(results)}")
        _report(r)
    return 0


if __name__ == "__main__":
    sys.exit(main())
