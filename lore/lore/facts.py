"""Daily harvest of durable facts out of recent conversations.

Reads the chunks indexed since the last run, asks a model for the facts together with the layer
each of them belongs to (durable / current / reference), and drops them into a waiting room
(~/.claude/wiedza/kandydaci.md), grouped by that layer. Nothing is ever written to the rules
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
# Only what the USER said. Measured on a real archive: a median day is 328 000
# characters of both sides but 41 000 of the user alone — eight times less. The
# assistant's half is mostly its own reports and summaries, which is why mining
# the archive first surfaced the assistant's report boilerplate instead of
# knowledge. The trade: a fact stated for the first time in a summary is lost,
# which is a small price for fitting a whole day under the cost cap.
HARVESTED_ROLES = frozenset({"user"})
MIN_FACT_CHARS = 10  # a single word is not a fact
MODEL_TIMEOUT_S = 300

# the three shelves of the knowledge — the model picks one per fact while it is reading the material
# anyway; sorting the same sentences in a separate pass would cost the same and buy nothing
LAYERS = ("stala", "biezaca", "referencyjna")
SECTIONS = ("uzytkownik", "firma", "projekty", "praca")  # the subsections of "## Co wiem"
DEFAULT_LAYER, DEFAULT_SECTION = "stala", "projekty"  # the safest guess: visible and easy to move
UNNAMED_FILE = "do-nazwania.md"  # a listing the model refused to name still has to land somewhere
GROUP_HEADINGS = {"stala": "## Trwałe", "biezaca": "## Bieżące",
                  "referencyjna": "## Do osobnych plików"}

# --safe-mode: no CLAUDE.md, no MCP servers, no hooks — the extractor must not pull the user's
#   rules into the answer, nor start the lore server again from inside a lore job.
# --no-session-persistence: without it every run leaves a transcript holding yesterday's material,
#   the indexer picks it up and the next run harvests its own output.
# --permission-prompts none: nobody is sitting at the console at 08:05 to answer a prompt.
# --json-schema: `claude -p` is an agent, not a text endpoint — asked for plain text it adds
#   questions and offers of help around the list. A schema gives a list and nothing else.
FACTS_SCHEMA = json.dumps({
    "type": "object",
    "properties": {"fakty": {"type": "array", "items": {
        "type": "object",
        "properties": {
            "tresc": {"type": "string"},
            "warstwa": {"type": "string", "enum": list(LAYERS)},
            "podsekcja": {"type": "string", "enum": list(SECTIONS)},
            "plik": {"type": "string"},
            "odsylacz": {"type": "string"},
        },
        "required": ["tresc", "warstwa"],
        "additionalProperties": False,
    }}},
    "required": ["fakty"],
    "additionalProperties": False,
}, ensure_ascii=False)
MODEL_ARGS = ("-p", "--safe-mode", "--no-session-persistence", "--permission-prompts", "none",
              "--output-format", "json", "--json-schema", FACTS_SCHEMA)

PROMPT = """Na wejściu (stdin) dostajesz fragmenty rozmów użytkownika z agentem AI.

Wypisz fakty, które warto znać w każdym nowym oknie rozmowy, i każdemu przypisz jedną warstwę:

- "stala" — kim jest użytkownik i czym się zajmuje, czym zajmuje się jego firma i jakim językiem
  mówi o swoich rzeczach, nad czym pracuje, jakie decyzje zapadły, jak chce pracować, jakie ma
  konwencje i zasady. Zmienia się w miesiącach. Do takiego faktu podaj też "podsekcja":
  "uzytkownik", "firma", "projekty" albo "praca".
- "biezaca" — sprawy w toku: co jest otwarte, co czeka na czyjąś decyzję, co się zacięło, jaki
  eksperyment trwa. Zmienia się w dniach.
- "referencyjna" — długie zestawienia: listy, tabele, struktury numeracji, wyliczenia wariantów.
  Poznajesz je po tym, że są długie i wyliczające, a nie po temacie. Do takiego faktu podaj
  "plik" — krótką nazwę pliku bez polskich znaków, np. "struktura-sku.md" — oraz "odsylacz",
  jedną linię, która stanie w trwałej wiedzy w miejsce całego zestawienia.

Pomiń opisy błędów i wszystko, co i tak widać w kodzie (nazwy plików, funkcji, struktura
repozytorium).

To jest automat: Twoja odpowiedź leci wprost do pliku, nikt jej teraz nie czyta. Nie zwracaj się do
użytkownika, nie zadawaj pytań, nie proponuj działań, niczego nie zapisuj i nie sięgaj po narzędzia
— jedyne, co masz zrobić, to wypisać listę.

Treść każdego faktu po polsku, w jednej linii, bez numeracji, bez nagłówków i bez pogrubień.
Jeśli nie ma ani jednego takiego faktu — zwróć pustą listę."""

CANDIDATES_HEADER = """# Kandydaci do trwałej wiedzy

Propozycje wyłowione automatycznie z rozmów — jeszcze nic nie znaczą. Odhacz to, co prawdziwe,
i przenieś do ~/.claude/CLAUDE.md ręcznie; nic stąd nie trafia tam samo.

Nawias po dacie mówi, dokąd wpis należy: (stala/podsekcja), (biezaca), (referencyjna:plik.md).
"""

_BULLET = re.compile(r"^\s*(?:[-*\u2022]|\d+[.)])\s*")
# the label in brackets is optional on purpose: entries written before the layers existed are read
# as the default one instead of dropping out of the duplicate check
_CANDIDATE_LINE = re.compile(r"^\s*-\s*\[[ xX]\]\s*(?:\[\d{4}-\d{2}-\d{2}\]\s*)?"
                             r"(?:\((stala|biezaca|referencyjna)(?:[/:]([^)]*))?\)\s*)?(.+)$")
_PUNCTUATION = re.compile(r"[^\w\s]", re.UNICODE)
_POLISH = str.maketrans("ąćęłńóśźż", "acelnoszz")


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
        if role.split(":")[-1] in HARVESTED_ROLES
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


@dataclass
class Fact:
    """A fact with the shelf it belongs to — the layer decides where the human moves it later."""
    text: str
    layer: str = DEFAULT_LAYER
    section: str = DEFAULT_SECTION  # only read for the "stala" layer
    file: str = ""  # only for "referencyjna": the listing goes to ~/.claude/wiedza/<file>
    pointer: str = ""  # the single line that stands in the durable knowledge instead of the listing

    def label(self) -> str:
        """'stala/firma', 'biezaca', 'referencyjna:struktura-sku.md' — the bracket in the entry."""
        if self.layer == "referencyjna":
            return f"referencyjna:{self.file}"
        if self.layer == "stala":
            return f"stala/{self.section}"
        return self.layer


def parse_facts(output: str) -> list[Fact]:
    """Model output -> facts: the structured answer when there is one, otherwise line by line."""
    structured = _structured(output)
    facts = []
    # an empty list from the envelope means "no facts" — it must not fall back to the raw text
    for raw in output.splitlines() if structured is None else structured:
        fact = _as_fact(raw)
        if fact is not None:
            facts.append(fact)
    return facts


def _as_fact(raw) -> Fact | None:
    """One item of the answer -> Fact. A missing or made-up layer falls back to the default one:
    a fact in the wrong subsection costs one move, a dropped fact is gone for good."""
    item = {"tresc": raw} if isinstance(raw, str) else raw if isinstance(raw, dict) else None
    if item is None:
        return None
    text = " ".join(_BULLET.sub("", str(item.get("tresc") or "")).split())
    if len(text) < MIN_FACT_CHARS or text.startswith("#") or text.endswith(("?", ":")):
        return None  # a question or a heading above a list is not a fact
    layer = str(item.get("warstwa") or "").strip().lower()
    if layer not in LAYERS:
        return Fact(text)
    if layer == "referencyjna":
        name = file_name(str(item.get("plik") or ""))
        pointer = " ".join(str(item.get("odsylacz") or "").split())
        return Fact(text, layer, file=name, pointer=pointer or f"Szczegóły w ~/.claude/wiedza/{name}")
    section = str(item.get("podsekcja") or "").strip().lower()
    return Fact(text, layer, section if section in SECTIONS else DEFAULT_SECTION)


def file_name(proposed: str) -> str:
    """The model's file name, made harmless: ASCII, no path, always .md."""
    stem = re.sub(r"\.md$", "", proposed.strip().lower()).translate(_POLISH)
    stem = re.sub(r"[^a-z0-9]+", "-", stem).strip("-")
    return f"{stem}.md" if stem else UNNAMED_FILE


def _structured(output: str) -> list | None:
    """The `--output-format json` envelope -> the list of facts; None when it is plain text."""
    try:
        envelope = json.loads(output)
        answer = envelope.get("structured_output") or json.loads(envelope.get("result") or "")
        facts = answer["fakty"]
    except (AttributeError, KeyError, TypeError, ValueError):
        return None
    return list(facts) if isinstance(facts, list) else None


# ---------------------------------------------------------------- the waiting room

def normalize(text: str) -> str:
    """Comparison key: lower case, no punctuation, single spaces. Deliberately nothing smarter."""
    return " ".join(_PUNCTUATION.sub(" ", text.lower()).split())


def _lines(path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return []


def waiting_facts() -> list[Fact]:
    """The waiting room read back. An entry without the bracket predates the layers — it counts
    as the default one, so the fifty-odd older candidates keep working."""
    out = []
    for line in _lines(CANDIDATES_PATH):
        m = _CANDIDATE_LINE.match(line)
        if not m:
            continue
        layer, detail, text = m.group(1) or DEFAULT_LAYER, (m.group(2) or "").strip(), m.group(3).strip()
        if layer == "referencyjna":
            out.append(Fact(text, layer, file=detail or UNNAMED_FILE))
        else:
            out.append(Fact(text, layer, detail if detail in SECTIONS else DEFAULT_SECTION))
    return out


def known_facts() -> set[str]:
    """Normalized facts already waiting in the candidates file or already standing in the rules."""
    known = {normalize(f.text) for f in waiting_facts()}
    for line in _lines(RULES_PATH):
        known.add(normalize(_BULLET.sub("", line).strip()))
    known.discard("")
    return known


def append_facts(facts: list[Fact], day: str | None = None) -> list[Fact]:
    """Appends the facts nobody knows yet, grouped by layer; returns the ones actually written.

    Grouped, because a human approves a whole shelf at once — fifty entries in one flat list get
    read by nobody. The date sits in every entry, so the "biezaca" ones can be aged out later.
    """
    known = known_facts()
    fresh = []
    for fact in facts:
        key = normalize(fact.text)
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
        for layer in LAYERS:
            group = [fact for fact in fresh if fact.layer == layer]
            if not group:
                continue
            f.write(f"\n{GROUP_HEADINGS[layer]} — {day}\n\n")
            for fact in group:
                f.write(f"- [ ] [{day}] ({fact.label()}) {fact.text}\n")
                if fact.pointer:  # the line that goes into the durable knowledge in its place
                    f.write(f"      odsyłacz: {fact.pointer}\n")
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
            log(f"  + ({fact.label()}) {fact.text}")
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
