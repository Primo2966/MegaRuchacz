"""Daily harvest of durable facts out of recent conversations.

Reads the chunks indexed since the last run, asks a model for the facts together with the layer
each of them belongs to (durable / current / reference), and drops them into a waiting room
(~/.claude/wiedza/kandydaci.md), grouped by that layer. This module never writes into the rules
the agent obeys — that is lore.verify's job, and it does it by itself, once the fact has been
checked and found not to contradict anything.

Every fact leaves a trail behind in wiedza/zrodla.md: which conversations it was read out of and
when. Not next to the fact in the rules, because those are sent with every session and pay for
every character — here it costs nothing and answers the only question that matters afterwards,
"where did this come from".

A fact the model hands back AGAIN (already waiting, already written down) is not proposed twice,
but its sighting still goes to the trail, with the full list of conversations of the batch. That
repetition is the evidence lore.verify needs before it lets a fact into the durable layer: a fact
heard in two different conversations has earned it, a fact heard once only lives in the current
layer until it ages out.

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
SOURCES_NAME = "zrodla.md"  # where every fact came from — written here and by lore.verify
# The events of the trail lore.verify reads back — one name each, so the two modules cannot drift.
SIGHTED = "wyłowiony"  # the first time a fact came out of the conversations
SIGHTED_AGAIN = "wyłowiony ponownie"  # the same fact once more — the evidence for promotion
# The field holding EVERY conversation of the batch. The readable source next to it names only
# the first MAX_NAMED_SESSIONS; "i 2 innych" cannot tell whether two sightings share a conversation.
SESSIONS_FIELD = "sesje:"
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

Propozycje wyłowione automatycznie z rozmów. Sprawdza je `lore.verify` — sam, bez pytania — i wpisuje
do warstwy bieżącej (wygasa po 14 dniach). Do stałej fakt przechodzi dopiero wtedy, gdy padł w co
najmniej dwóch różnych rozmowach. Tu zostaje tylko to, czego automat nie ma prawa rozstrzygnąć:

- `[!]` odrzucone — podana ścieżka nie istnieje,
- `[?]` sporne — przeczy temu, co już jest zapisane; którą wersję zostawić, decydujesz Ty,
- `[x]` odhaczone ręcznie — automat tego nie rusza.

Nawias po dacie mówi, dokąd wpis należy: (stala/podsekcja), (biezaca), (referencyjna:plik.md).
Skąd się wzięły — w ~/.claude/wiedza/zrodla.md.
"""

SOURCES_HEADER = """# Skąd się wzięły fakty

Jedna linia na zdarzenie: `data | zdarzenie | szczegóły | treść faktu`. „wyłowiony” mówi, z których
rozmów fakt pochodzi („sesje:” — komplet identyfikatorów), „wyłowiony ponownie” — że padł znowu,
„wpisany” — kiedy trafił do warstwy bieżącej, „awansowany” — kiedy przeszedł do stałej, bo padł
w co najmniej dwóch różnych rozmowach, „wygasł” — kiedy zniknął z bieżącej po 14 dniach.

Żeby znaleźć rozmowę: `lore_search` po treści faktu, zawężony do podanej daty albo sesji.
Ten plik NIE jest doklejany do rozmów — dlatego trop stoi tu, a nie przy wpisie w wiedzy.

"""

_BULLET = re.compile(r"^\s*(?:[-*\u2022]|\d+[.)])\s*")
# the label in brackets is optional on purpose: entries written before the layers existed are read
# as the default one instead of dropping out of the duplicate check.
# '!' and '?' belong in the box as well — lore.verify marks a rejected and a disputed entry that
# way, and an entry missed here would be harvested again tomorrow as if it were new.
_CANDIDATE_LINE = re.compile(r"^\s*-\s*\[[ xX!?]\]\s*(?:\[\d{4}-\d{2}-\d{2}\]\s*)?"
                             r"(?:\((stala|biezaca|referencyjna)(?:[/:]([^)]*))?\)\s*)?(.+)$")
_LEADING_DAY = re.compile(r"^\[\d{4}-\d{2}-\d{2}\]\s*")  # the date a "biezaca" entry carries
# the reason lore.verify glues to an entry it did not let through — part of the verdict, not of
# the fact; counted in, the same sentence would look new and be proposed all over again
_REASON = re.compile(r"\s*\((?:nie znaleziono|sporne|nie mieści się):.*$")
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

MAX_NAMED_SESSIONS = 3  # beyond that the trail says "and others" — it is a pointer, not an index


@dataclass
class Piece:
    """One row of the window: what it says, when it was said, when it landed, and where it sits."""
    chunk_id: int
    said: str  # `ts` — the moment of the conversation
    landed: str  # `indexed_at` — the moment it entered the database
    session: str  # the conversation it was read out of — this is what the trail points at
    text: str


@dataclass
class Material:
    texts: list[str] = field(default_factory=list)  # chronological
    chars: int = 0
    last_ts: str = ""  # indexing stamp of the last chunk taken — where the marker goes
    last_id: int | None = None  # and its id, so the next run starts exactly here
    sessions: list[str] = field(default_factory=list)  # the conversations it was read out of
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

    def source(self) -> str:
        """Where this batch came from, in one line — enough to find the conversation again.

        The window is the CONVERSATION dates, not the indexing ones: somebody asking "where did
        this come from" months later remembers when it was said, not when the indexer got to it.
        """
        if not self.texts:
            return ""
        named = self.sessions[:MAX_NAMED_SESSIONS]
        tail = f" i {len(self.sessions) - len(named)} innych" if len(self.sessions) > len(named) else ""
        window = f"rozmowy {self.first_said[:10]}..{self.last_said[:10]}"
        return f"{window} (sesje: {', '.join(named)}{tail})" if named else window

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
        f"SELECT id, ts, session, role, text, {INDEXED} FROM chunks WHERE ({where}){floor}"
        f" ORDER BY {INDEXED}, id",
        (*args, zero) if zero else args,
    ).fetchall()
    kept = [
        Piece(cid, ts, landed, session, f"[{ts_to_local(ts)}] {role}: {text}")
        for cid, ts, session, role, text, landed in rows
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
    # the other half of the trail: the conversations this batch was read out of. The window it
    # covers is first_said..last_said, set just above — see Material.source().
    for piece in kept[:taken]:
        if piece.session and piece.session not in material.sessions:
            material.sessions.append(piece.session)
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
        _PASS.add(usage)  # the same call, counted a second time for the history — see record_pass
    counted["fakty"] += max(0, found)
    _PASS.facts += max(0, found)
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
        _PASS.messages += max(0, read.messages)
        if read.first:
            _PASS.first = min(_PASS.first or read.first, read.first)
        if read.last:
            _PASS.last = max(_PASS.last, read.last)
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


# ---------------------------------------------------------------- the history of what it cost

# .koszt-cyklu.txt answers "what did TODAY cost" and keeps exactly two days, because two days are
# all the cycle ever shows. The question that comes after a month — "is this growing or shrinking,
# and what did the whole month cost me" — cannot be answered out of two days, so every pass leaves
# one line here as well. One line per PASS, not per day: a day of catching up is several passes,
# and only the per-pass number tells a one-off backlog (312 600 tokens in five calls on 2026-09-24)
# apart from a new normal.
JOURNAL_NAME = ".koszt-historia.tsv"
# Tab separated with a header row: read by eye as columns, loaded by a script without writing a
# parser — PowerShell with `Import-Csv -Delimiter "`t"`, Python with csv.DictReader. A comment
# header would have broken both, which is why the summaries live in their own file below.
JOURNAL_COLUMNS = ("kiedy", "narzedzie", "wywolania", "tokeny", "tokeny_zrodlo", "znaki_wyslane",
                   "znaki_odebrane", "wiadomosci", "zakres_od", "zakres_do", "fakty")
JOURNAL_SUMS = ("wywolania", "tokeny", "znaki_wyslane", "znaki_odebrane", "wiadomosci", "fakty")
# Two limits, because they guard two different things. The days are what the user asks about: more
# than a year back, so "what did the month cost" and "is this year worse than last" both still have
# material. The line count is what keeps a catch-up day from blowing the file up — -Nadrabiaj writes
# one line per pass, so a single day can add dozens; 2000 lines is around a quarter of a megabyte,
# small enough that the whole journal is read on every pass without anybody noticing.
JOURNAL_DAYS = 400
JOURNAL_MAX_ROWS = 2000
# The summaries go into their OWN file, in the `klucz: wartosc` shape of .koszt-cyklu.txt and
# .cykl-stan: the PowerShell side already has the code that reads that shape, and showing the last
# week costs one small file instead of parsing the whole journal every time.
SUMMARY_NAME = ".koszt-podsumowanie.txt"
WINDOWS = (7, 30)  # the two spans the user asks in: "this week" and "this month"


def journal_path() -> Path:
    """A function, not a constant — KNOWLEDGE_DIR is redirected in tests, exactly as for the tally."""
    return KNOWLEDGE_DIR / JOURNAL_NAME


def summary_path() -> Path:
    return KNOWLEDGE_DIR / SUMMARY_NAME


@dataclass
class Pass:
    """What ONE pass cost, from its first model call to the line it leaves in the journal.

    The daily tally adds passes together; the history keeps them apart. Both are counted from the
    same `Usage` objects, so the two files can never tell different stories about the same call.
    """
    tool: str = ""
    calls: int = 0
    sent: int = 0
    received: int = 0
    tokens: int = 0
    measured: bool = True  # stays true only while EVERY call reported numbers of its own
    facts: int = 0
    messages: int = 0
    first: str = ""  # the oldest message handed to the model, 'YYYY-MM-DD HH:MM'
    last: str = ""

    def add(self, usage: Usage) -> None:
        self.tool = usage.tool or self.tool
        self.calls += 1
        self.sent += usage.sent
        self.received += usage.received
        self.tokens += usage.tokens
        self.measured = self.measured and usage.measured

    def source(self) -> str:
        """'pomiar' / 'szacunek', and empty while nothing was called: a pass with no calls has no
        token count to describe, and calling that zero a measurement would be the one lie this
        file must never tell."""
        if not self.calls:
            return ""
        return "pomiar" if self.measured else "szacunek"

    def row(self, when: str) -> dict[str, str]:
        return {"kiedy": when, "narzedzie": self.tool, "wywolania": str(self.calls),
                "tokeny": str(self.tokens), "tokeny_zrodlo": self.source(),
                "znaki_wyslane": str(self.sent), "znaki_odebrane": str(self.received),
                "wiadomosci": str(self.messages), "zakres_od": self.first,
                "zakres_do": self.last, "fakty": str(self.facts)}


_PASS = Pass()


def start_pass() -> None:
    """Opens a new pass. catch_up goes round several times inside one process, and without this the
    second line would carry the first one's calls on top of its own."""
    global _PASS
    _PASS = Pass()


def record_pass(when: str | None = None) -> None:
    """Closes the pass: one line into the journal, and the summaries counted again out of it.

    Measuring must never cost the harvest itself, so nothing here is allowed to raise. It is not
    allowed to go quiet either: a journal that cannot be written says so in the log AND in the
    summary file, under `nieprawidlowosc`, where whatever shows this to the user will find it.
    """
    when = when or datetime.now().strftime("%Y-%m-%d %H:%M")
    row = _PASS.row(when)
    start_pass()
    problem = ""
    try:
        rows = append_journal(row)
    except OSError as e:
        problem = f"nie udało się dopisać przebiegu {when} do {JOURNAL_NAME}: {e}"
        log(problem)
        rows = read_journal()
    try:
        # the summary is dated NOW, not by the line just written: its windows say "the last seven
        # days up to today", and anchoring them on a back-dated pass would move the whole span
        write_summary(rows, problem=problem)
    except OSError as e:
        log(f"the cost summary was not written to {SUMMARY_NAME}: {e}")


def append_journal(row: dict[str, str]) -> list[dict[str, str]]:
    """Adds one line and gives back the whole journal, trimmed.

    Appending is the normal path — the file is rewritten only on the rare pass that pushes it past
    one of its limits, so the usual cost of the history is one line written at the end of the file.
    """
    KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    path = journal_path()
    header = "" if _has_header(path) else "\t".join(JOURNAL_COLUMNS) + "\n"
    with open(path, "a", encoding="utf-8", newline="\n") as f:
        f.write(header + _journal_line(row) + "\n")
    rows = read_journal()
    kept = trim_journal(rows)
    if len(kept) != len(rows):
        _rewrite_journal(kept)
    return kept


def read_journal() -> list[dict[str, str]]:
    """The journal read back, oldest first. A line that does not fit the columns is skipped rather
    than guessed at — and it is said out loud, because a silently dropped line is a lost cost."""
    lines = _lines(journal_path())
    if lines and lines[0].startswith(JOURNAL_COLUMNS[0]):
        lines = lines[1:]
    out = []
    for line in lines:
        if not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) != len(JOURNAL_COLUMNS):
            log(f"{JOURNAL_NAME}: a line with {len(fields)} of {len(JOURNAL_COLUMNS)} columns was"
                f" skipped — the cost it carried is not counted anywhere: {line[:80]}")
            continue
        out.append(dict(zip(JOURNAL_COLUMNS, fields)))
    return out


def trim_journal(rows: list[dict[str, str]], today: str | None = None) -> list[dict[str, str]]:
    """Both limits at once: nothing older than JOURNAL_DAYS days, and never more than
    JOURNAL_MAX_ROWS lines — whichever bites first."""
    cutoff = _days_back(today or datetime.now().strftime("%Y-%m-%d"), JOURNAL_DAYS)
    kept = [r for r in rows if r.get("kiedy", "")[:10] >= cutoff]
    return kept[-JOURNAL_MAX_ROWS:]


def _has_header(path: Path) -> bool:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.readline().startswith(JOURNAL_COLUMNS[0])
    except OSError:
        return False  # no file yet, or no file we can read — either way the header has to be written


def _journal_line(row: dict[str, str]) -> str:
    """One row as a line. Tabs and newlines inside a value would move every column after them, so
    they become spaces before they ever reach the file."""
    return "\t".join(" ".join(str(row.get(key, "")).split()) for key in JOURNAL_COLUMNS)


def _rewrite_journal(rows: list[dict[str, str]]) -> None:
    body = "\t".join(JOURNAL_COLUMNS) + "\n" + "".join(_journal_line(r) + "\n" for r in rows)
    journal_path().write_text(body, encoding="utf-8", newline="\n")


def _days_back(day: str, days: int) -> str:
    """'YYYY-MM-DD' minus N days. A stamp that is not a date pushes the cutoff to the beginning of
    time instead of dropping everything: losing the history to a confused clock is the worse bug."""
    try:
        return (datetime.strptime(day[:10], "%Y-%m-%d")
                - timedelta(days=max(0, days))).strftime("%Y-%m-%d")
    except ValueError:
        return ""


def write_summary(rows: list[dict[str, str]], problem: str = "", now: str | None = None) -> None:
    KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    now = now or datetime.now().strftime("%Y-%m-%d %H:%M")
    pairs = summarize(rows, now, problem)
    summary_path().write_text("".join(f"{key}: {value}\n" for key, value in pairs.items()),
                              encoding="utf-8", newline="\n")


def summarize(rows: list[dict[str, str]], now: str, problem: str = "") -> dict[str, str]:
    """The journal boiled down to the pairs somebody can show without counting anything again.

    `zaktualizowano` is there so that silence cannot pass for health: a stamp from three days ago
    on a cycle that runs daily says by itself that something stopped.
    """
    out = {"zaktualizowano": now, "przebiegi": str(len(rows)),
           "najstarszy": rows[0].get("kiedy", "") if rows else "",
           "najnowszy": rows[-1].get("kiedy", "") if rows else "",
           "granica_dni": str(JOURNAL_DAYS), "granica_wierszy": str(JOURNAL_MAX_ROWS)}
    for days in WINDOWS:
        out.update(_window(rows, days, now[:10]))
    out["nieprawidlowosc"] = problem or _anomaly(rows)
    return out


def _window(rows: list[dict[str, str]], days: int, today: str) -> dict[str, str]:
    """One span, summed. Every key carries its span in the name and its first day next to it —
    a number of tokens without the period it covers says nothing about what anything cost."""
    prefix = f"dni{days}."
    since = _days_back(today, days - 1)  # today counts as one of the days
    inside = [r for r in rows if r.get("kiedy", "")[:10] >= since]
    out = {prefix + "od": since, prefix + "do": today, prefix + "przebiegi": str(len(inside)),
           prefix + "tokeny_zrodlo": _window_source(inside)}
    for key in JOURNAL_SUMS:
        out[prefix + key] = str(sum(_number(r, key) for r in inside))
    tokens = sum(_number(r, "tokeny") for r in inside)
    # tokens are counted in thousands, so a decimal place there would be noise, not precision
    out[prefix + "tokeny_na_przebieg"] = str(round(tokens / len(inside))) if inside else "0"
    out[prefix + "wywolania_na_przebieg"] = _average(inside, "wywolania")
    out[prefix + "fakty_na_przebieg"] = _average(inside, "fakty")
    return out


def _average(rows: list[dict[str, str]], key: str) -> str:
    """One decimal place: 1.2 calls a pass is a different story from 5.0, and both round to a lie."""
    if not rows:
        return "0.0"
    return f"{sum(_number(r, key) for r in rows) / len(rows):.1f}"


def _window_source(rows: list[dict[str, str]]) -> str:
    """One estimated pass makes the whole span an estimate — the same rule as inside a single day."""
    sources = {r.get("tokeny_zrodlo", "") for r in rows if _number(r, "wywolania")}
    if not sources:
        return ""
    return "pomiar" if sources == {"pomiar"} else "szacunek"


def _anomaly(rows: list[dict[str, str]]) -> str:
    """An empty journal is only ever normal before the first pass. Once .koszt-cyklu.txt knows of
    calls that were paid for, an empty history is a fault to be shown, not 'no data yet'."""
    if rows:
        return ""
    saved = read_cost()
    calls = _number(saved, "wywolania") + _number(saved, PREVIOUS + "wywolania")
    if not calls:
        return ""
    return (f"dziennik {JOURNAL_NAME} jest pusty, a {COST_NAME} zna {calls} wywołań modelu"
            f" (dzień {saved.get('data', '?')}) — historia przebiegów się nie zapisuje")


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
        layer, detail = m.group(1) or DEFAULT_LAYER, (m.group(2) or "").strip()
        text = _REASON.sub("", m.group(3)).strip()
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
            # the date of a "biezaca" entry is not part of the fact: left in, the same sentence
            # would look new every day and the current layer would fill up with copies of itself
            known.add(normalize(_LEADING_DAY.sub("", _BULLET.sub("", line).strip())))
    known.discard("")
    return known


def note_sources(facts: list[Fact], source: str, day: str, sessions: list[str] | tuple = (),
                 event: str = SIGHTED) -> None:
    """Writes down, for each fact, which conversations it was read out of.

    A separate file on purpose — see the module docstring. It is a record of the job, never
    a reason to lose the job: a file that cannot be written says so in the log and that is all.
    `sessions` is the complete list of the batch; '-' when it is not known (lore.verify then
    counts the sighting as no evidence of a second conversation, which is the safe side).
    """
    if not source or not facts:
        return
    ids = " ".join(sessions) or "-"
    try:
        KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
        first_time = not (KNOWLEDGE_DIR / SOURCES_NAME).exists()
        with open(KNOWLEDGE_DIR / SOURCES_NAME, "a", encoding="utf-8", newline="\n") as f:
            if first_time:
                f.write(SOURCES_HEADER)
            for fact in facts:
                f.write(f"- {day} | {event} | {fact.label()} | {source} | {SESSIONS_FIELD} {ids}"
                        f" | {fact.text}\n")
    except OSError as e:
        log(f"the trail of {len(facts)} facts was not written to {SOURCES_NAME}: {e}")


def append_facts(facts: list[Fact], day: str | None = None, source: str = "",
                 sessions: list[str] | tuple = ()) -> list[Fact]:
    """Appends the facts nobody knows yet, grouped by layer; returns the ones actually written.

    Grouped, because the layer is what decides where lore.verify puts the fact afterwards, and
    because whatever it hands back to the user reads better sorted than as one flat list. The
    date sits in every entry — the "biezaca" ones are aged out by it later.

    A fact that is already known is not written again, but its sighting goes to the trail: that
    it came up once more, in which conversations, is exactly what promotes it later.
    """
    known = known_facts()
    fresh, again, seen = [], [], set()
    for fact in facts:
        key = normalize(fact.text)
        if not key or key in seen:
            continue  # the model likes to repeat itself inside one answer as well — one sighting
        seen.add(key)
        (again if key in known else fresh).append(fact)
    day = day or datetime.now().strftime("%Y-%m-%d")
    note_sources(again, source, day, sessions, event=SIGHTED_AGAIN)
    if not fresh:
        return []
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
    note_sources(fresh, source, day, sessions)
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
    start_pass()  # this pass gets its own line in the history — catch_up calls us several times
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
    out["added"] = append_facts(out["facts"], source=material.source(), sessions=material.sessions)
    record_cost(found=len(out["facts"]), read=read)  # the call was counted inside ask_model
    # and the same numbers once more, as one line of the history. Only the passes that got this
    # far leave a line: a pass that found no material called nobody and cost nothing, and a row of
    # zeros would only pull the averages the user reads down towards nothing.
    record_pass()
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
        again = {normalize(f.text) for f in r["facts"]} - {normalize(f.text) for f in r["added"]}
        again.discard("")
        if again:  # not new, but not lost either — the repetition is what promotes a fact later
            log(f"heard again (only a sighting in {SOURCES_NAME}): {len(again)}")
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
