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
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

from pathlib import Path

from .db import CLAUDE_HOME, DB_PATH, connect, log, ts_to_local

KNOWLEDGE_DIR = CLAUDE_HOME / "wiedza"
MARKER_PATH = KNOWLEDGE_DIR / ".ostatnie-wyciaganie"
# The id of the last chunk read goes into its OWN file, not next to the date: two PowerShell tools
# read .ostatnie-wyciaganie and parse the whole of it as a date (narzedzia\cykl-dzienny.ps1 ->
# Czytaj-Znacznik, narzedzia\koszt-pamieci.ps1 -> Kolejka-Lore). Anything appended there would
# quietly turn their marker into "never read anything".
MARKER_ID_PATH = KNOWLEDGE_DIR / ".ostatnie-wyciaganie-id"
DAY_ZERO_PATH = KNOWLEDGE_DIR / ".dzien-zero"  # when this machine started learning — see day_zero()
CANDIDATES_PATH = KNOWLEDGE_DIR / "kandydaci.md"
COST_NAME = ".koszt-cyklu.txt"  # next to .cykl-stan, in the same 'klucz: wartosc' shape
RULES_PATH = CLAUDE_HOME / "CLAUDE.md"  # read only — the waiting room is the only thing we write
CODEX_RULES_PATH = Path.home() / ".codex" / "AGENTS.md"


def instruction_paths() -> tuple[Path, ...]:
    """Every instruction file the user may have — for the duplicate check only.

    A function, not a constant: RULES_PATH is redirected in tests, and a tuple frozen at import
    time would ignore that. Kept in step with INSTRUCTION_PATHS in verify.py, which is what
    actually writes into these files.
    """
    return (RULES_PATH, CODEX_RULES_PATH)

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
# the same rule in SQL, for the counting queries: "user" and "agent:user", nothing else
HARVESTED_SQL = " OR ".join(f"role = '{r}' OR role LIKE '%:{r}'" for r in sorted(HARVESTED_ROLES))
MIN_FACT_CHARS = 10  # a single word is not a fact
MODEL_TIMEOUT_S = 300

# The axis the harvest walks: when a chunk landed in the database, not when it was said. `ts` is the
# moment of the conversation, but indexing runs on its own every ten minutes, so a chunk can be
# written AFTER the marker has already moved past its date — and "ts > marker" would then never show
# it to anybody again. `indexed_at` only ever grows, so a marker walking it cannot jump over a row.
# COALESCE: a row written before the column existed (or by hand) carries the empty default, and a
# plain comparison would hide it for good; falling back to its own date at worst repeats the old
# behaviour instead of losing the row silently.
INDEXED = "COALESCE(NULLIF(indexed_at, ''), ts)"

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
    """No agent CLI in PATH — there is nothing to extract the facts with. See MODEL_CLIS."""


# ---------------------------------------------------------------- the run marker

def iso_utc(d: datetime) -> str:
    """'2026-09-16T08:05:00.000Z' — the same shape the transcripts use, so plain string compare works."""
    return d.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _saved(path) -> str:
    """The single line a marker file holds; '' when there is no file or it cannot be read."""
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def _is_iso(text: str) -> bool:
    try:
        datetime.fromisoformat(text.replace("Z", "+00:00"))
        return True
    except ValueError:
        return False


@dataclass(frozen=True)
class Marker:
    """How far the harvest has got on the indexing axis: the stamp of the last chunk read, and its id.

    The id is the tiebreaker. One indexing pass writes all of its chunks under a single stamp, so a
    marker made of the stamp alone would either lose the rest of that pass (when the cap cut inside
    it) or hand it over twice. A marker written before this axis existed has no id — it is then read
    on the stamp alone, which is exactly the old behaviour, because the migration gave every older
    row `indexed_at = ts`.
    """
    stamp: str
    chunk_id: int | None = None

    def window(self) -> tuple[str, tuple]:
        """The WHERE clause for 'everything this marker has not read yet', plus its arguments.

        The `id` half is the second door: a row whose stamp somehow lands BEHIND the marker (a clock
        set back, a database edited by hand) still has a higher id, so it is picked up instead of
        disappearing. Nothing is read twice — a run always takes a prefix of this window in
        (stamp, id) order, so everything already read sits below both halves.
        """
        if self.chunk_id is None:
            return f"{INDEXED} > ?", (self.stamp,)
        return f"{INDEXED} > ? OR id > ?", (self.stamp, self.chunk_id)


def since_marker() -> Marker:
    """Where the last run stopped; a missing or broken marker means 'the last 24 hours'."""
    saved = _saved(MARKER_PATH)
    if saved and _is_iso(saved):
        return Marker(saved, _saved_id())
    if saved:
        log(f"unreadable marker {MARKER_PATH.name}: {saved!r} — falling back to the last {DEFAULT_WINDOW_H} h")
    return Marker(iso_utc(datetime.now(timezone.utc) - timedelta(hours=DEFAULT_WINDOW_H)))


def _saved_id() -> int | None:
    """The chunk id that goes with the marker date; None when it was never written."""
    saved = _saved(MARKER_ID_PATH)
    if saved.isdigit():
        return int(saved)
    if saved:
        log(f"unreadable {MARKER_ID_PATH.name}: {saved!r} — the marker is read on its date alone")
    return None


def write_marker(marker: "Marker | str") -> None:
    """The marker moves only after a run that really asked the model — a failed run has to catch up."""
    marker = marker if isinstance(marker, Marker) else Marker(marker)
    KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    MARKER_PATH.write_text(marker.stamp + "\n", encoding="utf-8")
    if marker.chunk_id is None:
        MARKER_ID_PATH.unlink(missing_ok=True)  # an id left from before would point somewhere else
    else:
        MARKER_ID_PATH.write_text(f"{marker.chunk_id}\n", encoding="utf-8")


def day_zero() -> str:
    """The moment this machine started learning. Nothing indexed earlier is ever harvested.

    A fresh install finds years of transcripts on the disk and the indexer pulls all of them into
    the database within the hour. Without a floor the first harvest would walk that whole archive —
    conversations from before the tool existed, paid for in tokens, without anybody asking for it.
    The line is drawn once, on the first run that gets this far: at the existing read marker when
    there is one (an install caught in the middle of a backlog must not lose it), and at "now" on a
    machine that has never harvested anything.

    A trial run writes it as well: the dry run exists to report the numbers the real run would give,
    and it cannot do that with the floor still undecided.
    """
    saved = _saved(DAY_ZERO_PATH)
    if saved and _is_iso(saved):
        return saved
    if saved:
        log(f"unreadable {DAY_ZERO_PATH.name}: {saved!r} — drawing the line again")
    start = _saved(MARKER_PATH)
    if not (start and _is_iso(start)):
        start = iso_utc(datetime.now(timezone.utc))
    try:
        KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
        DAY_ZERO_PATH.write_text(start + "\n", encoding="utf-8")
        log(f"day zero set to {start} — chunks indexed before it are never harvested")
    except OSError as e:  # the floor still holds for this run; it is simply decided again next time
        log(f"day zero could not be written to {DAY_ZERO_PATH.name}: {e}")
    return start


# ---------------------------------------------------------------- material for the model

@dataclass
class Piece:
    """One row of the window: what it says, when it was said, when it landed, and where it sits."""
    chunk_id: int
    said: str  # `ts` — the moment of the conversation
    landed: str  # `indexed_at` — the moment it entered the database
    text: str


@dataclass
class Material:
    texts: list[str] = field(default_factory=list)  # chronological
    chars: int = 0
    last_ts: str = ""  # indexing stamp of the last chunk taken — where the marker goes
    last_id: int | None = None  # and its id, so the next run starts exactly here
    pending: int = 0  # chunks left for the next runs
    pending_chars: int = 0
    in_range: int = 0  # rows the window matched, every role
    candidates: int = 0  # of those, the ones a harvest is allowed to read (HARVESTED_ROLES)
    late: int = 0  # taken although their stamp sits BEHIND the marker — the hole, measured
    before_zero: int = 0  # never harvested at all: indexed before day zero
    first_said: str = ""  # the conversation dates of what really went to the model
    last_said: str = ""

    def joined(self) -> str:
        return "\n\n".join(self.texts)

    def runs_left(self) -> int:
        return math.ceil(self.pending_chars / MAX_INPUT_CHARS)

    def marker(self) -> Marker:
        return Marker(self.last_ts, self.last_id)

    def missing(self) -> int:
        """Candidates that neither went to the model nor wait in the backlog. Always 0 — if it ever
        is not, material disappeared between the query and the prompt and somebody has to hear it."""
        return max(0, self.candidates - len(self.texts) - self.pending)


def collect(conn: sqlite3.Connection, marker: Marker, zero: str = "") -> Material:
    """Chunks the marker has not read yet, OLDEST first up to the cap.

    Oldest first on purpose: the marker moves exactly as far as we got, so a backlog after a few
    days away is worked off run by run instead of being silently skipped over.

    `zero` is day zero — the moment this machine started learning. Everything indexed before it is
    left alone (and counted, never swallowed): that is the archive from before the tool existed.
    """
    where, args = marker.window()
    floor = f" AND {INDEXED} >= ?" if zero else ""
    rows = conn.execute(
        f"SELECT id, ts, role, text, {INDEXED} FROM chunks WHERE ({where}){floor}"
        f" ORDER BY {INDEXED}, id",
        (*args, zero) if zero else args,
    ).fetchall()
    kept = [
        Piece(cid, ts, landed, f"[{ts_to_local(ts)}] {role}: {text}")
        for cid, ts, role, text, landed in rows
        if role.split(":")[-1] in HARVESTED_ROLES
    ]
    material = Material(in_range=len(rows), candidates=len(kept))
    if marker.chunk_id is not None:  # only the id half of the window can bring such a row in
        material.late = sum(1 for piece in kept if piece.landed <= marker.stamp)
    material.before_zero = _before_zero(conn, where, args, zero)
    taken = 0
    for piece in kept:
        if material.chars + len(piece.text) > MAX_INPUT_CHARS:
            break
        material.texts.append(piece.text)
        material.chars += len(piece.text)
        material.last_ts, material.last_id = piece.landed, piece.chunk_id
        taken += 1
    taken += _align_to_turn(material, kept, taken)
    # the oldest and the newest CONVERSATION date of what was taken — "przeczytane X wiadomości
    # z okresu od-do". Not the first and the last of the list: the list runs in indexing order,
    # and a late transcript lands among chunks that were said after it.
    said = sorted(piece.said for piece in kept[:taken])
    material.first_said = said[0] if said else ""
    material.last_said = said[-1] if said else ""
    rest = kept[taken:]
    material.pending = len(rest)
    material.pending_chars = sum(len(p.text) for p in rest)
    return material


def _before_zero(conn: sqlite3.Connection, where: str, args: tuple, zero: str) -> int:
    """How much the day-zero floor held back this time — the conversations from before the install.

    Said out loud rather than dropped in silence: it is knowledge lying in the archive that we
    deliberately do not use, and the user may one day want it dug out on purpose (lore.mining).
    """
    if not zero:
        return 0
    row = conn.execute(
        f"SELECT count(*) FROM chunks WHERE ({where}) AND {INDEXED} < ? AND ({HARVESTED_SQL})",
        (*args, zero),
    ).fetchone()
    return int(row[0] or 0)


def _align_to_turn(material: Material, kept: list[Piece], taken: int) -> int:
    """Moves the cut onto a turn boundary, so one turn is not split between two prompts.

    Parts of one turn share a `ts`. Nothing is lost when the cut does fall inside one — the marker
    carries the id of the last chunk taken, so the tail is the first thing the next run sees — but a
    half turn read out of context is worth less to the model, so we push the cut back.

    Returns how many chunks go back to the backlog (a negative number), or 0 when nothing moves.
    """
    if taken == 0 or taken == len(kept) or kept[taken - 1].said != kept[taken].said:
        return 0
    back = taken
    while back and kept[back - 1].said == kept[taken].said:
        back -= 1
    if back == 0:  # one turn heavier than the whole cap: take what fits, the rest waits its turn
        log(f"one turn ({kept[taken].said}) exceeds the {MAX_INPUT_CHARS} character cap"
            f" — it is split across runs, nothing is skipped")
        return 0
    del material.texts[back:]
    material.chars = sum(len(t) for t in material.texts)
    material.last_ts, material.last_id = kept[back - 1].landed, kept[back - 1].chunk_id
    return back - taken  # negative: those chunks go back to the backlog


# ---------------------------------------------------------------- the tool that carries the model

# The model does not live in this process: it is reached through whichever agent CLI the machine
# happens to have — Claude Code on one, Codex on another. Wiring `claude` in was enough to kill the
# whole knowledge layer on a Codex-only machine, so the tool is looked up when it is needed and
# every caller goes through find_model_cli(). A third tool is one row in MODEL_CLIS, nothing else.
MODEL_CLI_ENV = "LORE_MODEL_CLI"  # forces one of them by name — for testing and for overriding

# stands in MODEL_CLIS for the file the tool is told to write its answer to — the real path is a
# temporary one, made per call in ask_model and substituted here at the last moment
ANSWER_SLOT = "<plik-odpowiedzi>"
ANSWER_NAME = "odpowiedz.txt"  # inside the scratch directory, so cleaning up is one rmtree

# 2026-09-17: every switch below is confirmed by a real `codex exec --help` printout from a machine
#   that has Codex. `-` really is "read the prompt from stdin" (the material does not fit in argv)
#   and --skip-git-repo-check really lets it run outside a repository, which the scratch directory is.
# --output-last-message: without it stdout carries the whole run of the session, not the answer, and
#   a transcript of the agent thinking out loud would land in the waiting room as "facts".
# --color never: no terminal escape codes inside the text we are about to parse.
# -s read-only: extracting facts is pure text work — it has no business writing or running anything.
#   It cannot hang either: `codex exec` is the non-interactive mode, so a refused action ends the run
#   instead of waiting for someone to approve it at a console nobody is sitting at.
CODEX_ARGS = ("exec", "--skip-git-repo-check", "--color", "never", "-s", "read-only",
              "--output-last-message", ANSWER_SLOT, "-")

# best first: when both are installed Claude Code wins, because its switches and its JSON envelope
# are the ones this module was measured against
MODEL_CLIS = (
    # name, switches before the prompt, instruction goes on stdin too, switches read off the tool
    ("claude", MODEL_ARGS, False, True),
    ("codex", CODEX_ARGS, True, True),
)


@dataclass(frozen=True)
class ModelCLI:
    """One agent CLI: where it is, how the prompt gets in, how the answer comes back out."""
    name: str
    exe: str
    args: tuple[str, ...]
    prompt_on_stdin: bool
    verified: bool  # its switches were read off the tool itself, not guessed from documentation

    def answer_in_file(self) -> bool:
        """True when the tool is told to write the answer to a file instead of printing it."""
        return ANSWER_SLOT in self.args

    def invocation(self, instruction: str, material: str, answer_path: Path) -> tuple[list[str], str]:
        """(argv, stdin) — the 60 k of material never fits in argv, so it always goes on stdin.

        Claude Code takes the instruction in argv and reads the material from stdin. Codex `exec`
        wants a single prompt instead, so there the two are glued and handed over together.
        """
        args = [str(answer_path) if a == ANSWER_SLOT else a for a in self.args]
        if self.prompt_on_stdin:
            return [self.exe, *args], f"{instruction}\n\n{material}"
        return [self.exe, *args, instruction], material

    def answer(self, stdout: str, answer_path: Path) -> str:
        """The answer alone, from wherever the tool put it."""
        return _codex_answer(stdout, answer_path) if self.answer_in_file() else stdout


def _codex_answer(stdout: str, answer_path: Path) -> str:
    """The Codex answer, read from the file --output-last-message was pointed at.

    Its stdout is the run of the session — reasoning, tool calls, timings — with the answer somewhere
    inside; parsing that would carry the agent's own chatter into the waiting room as facts. The file
    holds the last message and nothing else, so it is read instead of stdout being sifted.
    """
    try:
        answer = answer_path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        answer = ""
    if not answer:
        tail = " ".join(stdout.split())[-200:]
        raise RuntimeError(f"codex left no answer in {answer_path.name} (--output-last-message)"
                           f" — the run ended without a final message; its output ended with:"
                           f" {tail or '(nothing)'}")
    return answer


def model_clis() -> tuple[ModelCLI, ...]:
    """Every known tool that is really installed, best first. Empty on a machine with none."""
    return tuple(
        ModelCLI(name, exe, args, prompt_on_stdin, verified)
        for name, args, prompt_on_stdin, verified in MODEL_CLIS
        if (exe := shutil.which(name))
    )


def find_model_cli() -> ModelCLI:
    """The tool to ask. LORE_MODEL_CLI wins; without it the first installed one from MODEL_CLIS."""
    found = model_clis()
    wanted = (os.environ.get(MODEL_CLI_ENV) or "").strip().lower()
    known = ", ".join(f"`{name}`" for name, *_ in MODEL_CLIS)
    if wanted:
        for cli in found:
            if cli.name == wanted:
                return cli
        raise ModelMissing(f"{MODEL_CLI_ENV}={wanted}, but no `{wanted}` in PATH"
                           f" (tools this knows: {known})")
    if found:
        return found[0]
    raise ModelMissing(f"no agent CLI in PATH — looked for {known}, found none")


def available_model_cli() -> ModelCLI | None:
    """The same choice, without raising — for the dry run, which only reports what it would use."""
    try:
        return find_model_cli()
    except ModelMissing:
        return None


# ---------------------------------------------------------------- the model

def ask_model(material: str, instruction: str = PROMPT) -> str:
    """Asks whichever tool this machine has: the instruction and the material, the answer back.

    It runs in an empty scratch directory on purpose: started in a repository it answers about
    that code, and started in the knowledge directory it starts tidying the files it finds there.
    The file a tool may be asked to write its answer to lives in that same directory, so it is swept
    away with it whatever happens — a clean run, a timeout or a crash.
    """
    cli = find_model_cli()
    empty = tempfile.mkdtemp(prefix="lore-facts-")
    answer_path = Path(empty) / ANSWER_NAME
    argv, stdin = cli.invocation(instruction, material, answer_path)
    try:
        r = subprocess.run(
            argv, input=stdin, capture_output=True, cwd=empty,
            text=True, encoding="utf-8", errors="replace", timeout=MODEL_TIMEOUT_S,
        )
        if r.returncode != 0:
            raise RuntimeError(f"{cli.name} returned {r.returncode}:"
                               f" {(r.stderr or '').strip()[:200]}")
        answer = cli.answer(r.stdout or "", answer_path)
        record_cost(Usage.of(cli.name, len(instruction) + len(material), answer, r.stdout or ""))
        return answer
    finally:
        shutil.rmtree(empty, ignore_errors=True)


# ---------------------------------------------------------------- what the day cost

# This call is the only place in the whole tool where the user's tokens are really spent —
# everything else glues ready-made text together. Unmeasured, that cost grows unnoticed, so every
# call writes down what it sent, what came back and what it was billed for, and the whole day is
# added up in one small file beside .cykl-stan; the PowerShell side reads it with the code it
# already has for its own state files.
COST_KEYS = ("narzedzie", "wywolania", "znaki_wyslane", "znaki_odebrane", "tokeny",
             "tokeny_zrodlo", "fakty", "wiadomosci", "zakres_od", "zakres_do",
             "spoznione", "pominiete", "sprzed_dnia_zero")
COUNTED_KEYS = ("wywolania", "znaki_wyslane", "znaki_odebrane", "tokeny", "fakty",
                "wiadomosci", "spoznione", "pominiete")  # these add up over the day
# "przeczytane X wiadomości z okresu od-do" — the cycle says that line without asking a model, so
# the numbers behind it are written down here, where it already reads the cost.
RANGE_KEYS = ("zakres_od", "zakres_do")  # the earliest and the latest message of the day
PEAK_KEYS = ("sprzed_dnia_zero",)  # a state, not a sum: the biggest number the day has seen
PREVIOUS = "poprzedni."  # yesterday under the same keys, so "wczoraj / dziś" can be shown
CHARS_PER_TOKEN = 3  # the estimate narzedzia\koszt-pamieci.ps1 uses for Polish — see tokeny_zrodlo
# `claude -p --output-format json` really carries the numbers it was billed by — checked against
# a live run on 2026-09-17, not read off documentation. The cache lines count as well: the user
# pays for them too, and on a 60 k prompt they are most of the bill.
TOKEN_FIELDS = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens",
                "output_tokens")


def cost_path() -> Path:
    """Where the tally lands. A function, not a constant: KNOWLEDGE_DIR is redirected in tests."""
    return KNOWLEDGE_DIR / COST_NAME


def measured_tokens(stdout: str) -> int:
    """The real token count out of the tool's own envelope; 0 when it does not report one.

    Codex prints its session instead of an envelope, so there the answer is 0 and the caller falls
    back to the character estimate — a number marked as a guess beats a guess dressed as a measurement.
    """
    try:
        usage = json.loads(stdout)["usage"]
        return sum(int(usage.get(field) or 0) for field in TOKEN_FIELDS)
    except (AttributeError, KeyError, TypeError, ValueError):
        return 0


@dataclass
class Usage:
    """One call to the model, counted: what went in, what came back, what it cost."""
    tool: str = ""
    sent: int = 0  # characters of the instruction plus the material
    received: int = 0
    tokens: int = 0
    measured: bool = False  # tokens read off the tool itself, not guessed from the characters

    @classmethod
    def of(cls, tool: str, sent: int, answer: str, stdout: str) -> "Usage":
        received = len(answer)
        tokens = measured_tokens(stdout)
        if tokens:
            return cls(tool, sent, received, tokens, True)
        return cls(tool, sent, received, math.ceil((sent + received) / CHARS_PER_TOKEN))


def read_cost() -> dict[str, str]:
    """The saved pairs. A missing or unreadable file simply means 'nothing counted yet'."""
    out = {}
    for line in _lines(cost_path()):
        key, sep, value = line.partition(":")
        if sep and key.strip():
            out[key.strip()] = value.strip()
    return out


def _number(saved: dict[str, str], key: str) -> int:
    try:
        return int(saved.get(key) or 0)
    except ValueError:  # a hand-edited or half-written line is worth 0, not a crash at 08:05
        return 0


@dataclass
class Reading:
    """What one harvest really read — the numbers the cycle shows the user, and its two controls.

    The controls are the point: `late` and `missing` are 0 on a healthy run, and anything else means
    material was about to fall out of the learning. A run that reports nothing is not the same as a
    run that reports zero.
    """
    messages: int = 0  # chunks that really went to the model
    first: str = ""  # local time of the oldest message handed over, 'YYYY-MM-DD HH:MM'
    last: str = ""
    late: int = 0  # read although their stamp was behind the marker — the hole, caught
    missing: int = 0  # in range, not read, not waiting either — must always be 0
    before_zero: int = 0  # left alone because they predate day zero

    @classmethod
    def of(cls, material: Material) -> "Reading":
        return cls(len(material.texts),
                   ts_to_local(material.first_said) if material.first_said else "",
                   ts_to_local(material.last_said) if material.last_said else "",
                   material.late, material.missing(), material.before_zero)


def record_cost(usage: Usage | None = None, found: int = 0, day: str | None = None,
                read: Reading | None = None) -> None:
    """Adds one call — and the facts it brought — to today's tally.

    Runs of the same day add up: the cycle goes several times over when it is catching up on
    a backlog, and the user asks what the DAY cost. A new day starts from zero and pushes the old
    numbers under `poprzedni.`, so "wczoraj / dziś" can be put side by side; nothing older is kept,
    because nothing older is ever shown.

    This is a measurement, not the job: a file that cannot be written must not cost the user the
    harvest itself. It does not disappear quietly either — the reason goes into the log.
    """
    day = day or datetime.now().strftime("%Y-%m-%d")
    saved = read_cost()
    new_day = saved.get("data") != day
    counted = {key: 0 if new_day else _number(saved, key) for key in COUNTED_KEYS}
    tool = "" if new_day else saved.get("narzedzie", "")
    source = "" if new_day else saved.get("tokeny_zrodlo", "")
    if usage is not None:
        counted["wywolania"] += 1
        counted["znaki_wyslane"] += usage.sent
        counted["znaki_odebrane"] += usage.received
        counted["tokeny"] += usage.tokens
        tool = usage.tool
        # one estimated call makes the whole sum an estimate: calling a partly guessed total
        # a measurement would be a lie in the one place that reports what this costs
        source = "pomiar" if usage.measured and source in ("", "pomiar") else "szacunek"
    counted["fakty"] += max(0, found)
    span = {key: "" if new_day else saved.get(key, "") for key in RANGE_KEYS}
    peak = {key: 0 if new_day else _number(saved, key) for key in PEAK_KEYS}
    if read is not None:
        counted["wiadomosci"] += max(0, read.messages)
        counted["spoznione"] += max(0, read.late)
        counted["pominiete"] += max(0, read.missing)
        # the day's range grows at both ends; 'YYYY-MM-DD HH:MM' sorts by itself, so min/max are
        # enough, and a run that read nothing leaves the range it found alone
        if read.first:
            span["zakres_od"] = min(span["zakres_od"] or read.first, read.first)
        if read.last:
            span["zakres_do"] = max(span["zakres_do"], read.last)
        peak["sprzed_dnia_zero"] = max(peak["sprzed_dnia_zero"], read.before_zero)
    entry = {"data": day, "narzedzie": tool, "tokeny_zrodlo": source, **span,
             **{key: str(peak[key]) for key in PEAK_KEYS},
             **{key: str(counted[key]) for key in COUNTED_KEYS}}
    try:
        _write_cost(entry, _yesterday(saved, new_day))
    except OSError as e:
        log(f"the cost of this run was not written to {COST_NAME}: {e}")


def _yesterday(saved: dict[str, str], new_day: bool) -> dict[str, str]:
    """The block that goes under `poprzedni.`: the day that has just ended, or the one kept so far."""
    if new_day and saved.get("data"):
        return {"data": saved["data"], **{key: saved.get(key, "") for key in COST_KEYS}}
    return {key: saved.get(PREVIOUS + key, "") for key in ("data", *COST_KEYS)}


def _write_cost(entry: dict[str, str], previous: dict[str, str]) -> None:
    KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    lines = [f"{key}: {entry[key]}" for key in ("data", *COST_KEYS)]
    if previous.get("data"):  # skipped on the very first day, when there is no yesterday yet
        lines += [f"{PREVIOUS}{key}: {previous.get(key, '')}" for key in ("data", *COST_KEYS)]
    cost_path().write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")


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
    """Normalized facts already waiting in the candidates file or already standing in the rules.

    Every instruction file on this machine counts, not only Claude Code's: a fact approved into
    the Codex file would otherwise look unknown here and come back to the waiting room tomorrow,
    asking the user to approve the same sentence over and over.
    """
    known = {normalize(f.text) for f in waiting_facts()}
    for path in instruction_paths():
        for line in _lines(path):
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

def _empty_run() -> dict:
    """The shape every run returns, so a caller never has to guess which keys are there.

    A function, not a constant: the two lists would otherwise be shared between all the runs of
    one process.
    """
    return {"chunks": 0, "chars": 0, "pending": 0, "runs_left": 0, "in_range": 0, "candidates": 0,
            "late": 0, "missing": 0, "before_zero": 0, "from": "", "to": "",
            "facts": [], "added": []}


def run(dry_run: bool = False, ask=ask_model, conn: sqlite3.Connection | None = None) -> dict:
    """One pass: material -> model -> waiting room. Never raises on missing data, only reports it."""
    marker = since_marker()
    own = conn is None
    if own and not DB_PATH.exists():
        return {**_empty_run(), "status": "no-database", "since": marker.stamp, "day_zero": "",
                "note": f"no database at {DB_PATH} — index the conversations first"}
    zero = day_zero()
    if own:
        conn = connect()
    try:
        material = collect(conn, marker, zero)
    finally:
        if own:
            conn.close()
    read = Reading.of(material)
    out = {**_empty_run(), "status": "ok", "since": marker.stamp, "day_zero": zero,
           "chunks": len(material.texts), "chars": material.chars, "pending": material.pending,
           "runs_left": material.runs_left(), "in_range": material.in_range,
           "candidates": material.candidates, "late": read.late, "missing": read.missing,
           "before_zero": read.before_zero, "from": read.first, "to": read.last}
    if not material.texts:
        out["status"] = "no-material"
        out["note"] = f"nothing indexed after {marker.stamp}"
        # a run that read nothing has nothing to add up — unless it has something to WARN about,
        # and then the number has to reach the cycle, not only the log
        if not dry_run and (read.before_zero or read.late or read.missing):
            record_cost(read=read)
        return out
    if dry_run:
        out["status"] = "dry-run"
        cli = available_model_cli()
        out["model_available"] = cli is not None
        out["model_cli"] = cli.name if cli else ""
        return out
    out["facts"] = parse_facts(ask(material.joined()))
    out["added"] = append_facts(out["facts"])
    record_cost(found=len(out["facts"]), read=read)  # the call was counted inside ask_model
    write_marker(material.marker())  # exactly as far as we got, so the next run picks up from here
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


def _controls(r: dict) -> None:
    """The two checks of one pass, and what day zero held back. Zero is reported by silence here;
    anything else is a sentence, because both numbers mean material nearly fell out of the learning."""
    if r["late"]:
        log(f"{r['late']} chunks were indexed behind the marker — the old 'ts > marker' rule would"
            f" have hidden them for good; they went to the model this time")
    if r["missing"]:
        log(f"ALARM: {r['missing']} chunks of the window went neither to the model nor to the"
            f" backlog — material is disappearing between the query and the prompt")
    if r["before_zero"]:
        log(f"{r['before_zero']} chunks skipped as older than day zero ({r['day_zero']}) — the"
            f" archive from before the install is never harvested on its own; to go through it on"
            f" purpose use narzedzia\\przekop-archiwum.ps1")


def _report(r: dict) -> None:
    if r["status"] == "no-database":
        log(r["note"])
        return
    if r["status"] == "no-material":
        log(r["note"])
        _controls(r)
        return
    log(f"material: {r['chunks']} chunks, {r['chars']} characters indexed after {r['since']}"
        f" (messages from {r['from']} to {r['to']})")
    _controls(r)
    if r["status"] == "dry-run":
        log(f"dry run — nothing written; model tool: {r['model_cli'] or 'NONE in PATH'}")
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
        log(f"{e} — install Claude Code (npm install -g @anthropic-ai/claude-code) or Codex")
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
