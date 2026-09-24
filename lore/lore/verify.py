"""Confronting the harvested facts with reality — whatever a machine can check, it checks itself.

The waiting room (~/.claude/wiedza/kandydaci.md) used to be a queue to click through, and by the
morning of 2026-09-17 it held ninety entries nobody had read: a review that never happens is not
a safeguard, it is a pile. So a fact does NOT wait for a human any more — it goes in by itself,
and the user is told afterwards what arrived.

But it goes in ONLY to the current layer ("### Bieżące", dated), never straight into the durable
one. Letting every harvested fact into the durable layer was tried for a week (2026-09-17..24):
one run pushed what every session starts with from ~2 941 to ~4 946 tokens (+68%) with sixty facts
at once, and memory rewritten by a model over and over first improves and then degrades, at times
below having no memory at all (arXiv 2605.12978). The current layer ages out after 14 days, so
a wrong fact disappears by itself. A fact is PROMOTED to the durable layer only once it has been
heard in at least two different conversations (the trail in wiedza/zrodla.md says which), and
only a few per run — see MAX_PROMOTIONS.

Two things stop a fact on the way in, and each of them says so out loud:

* a claim that can be checked and does NOT hold (a path that is not there) — rejected, stays flagged,
* a claim that CONTRADICTS something already written down — the one case a machine must not settle,
  because it would have to guess which version is true; it stays, marked as disputed, quoting the
  entry it clashes with.

A promotion that would push the durable layer over its 8 000 character ceiling does not happen —
the fact stays in the current layer and the run says the ceiling is what stopped it.

The same check runs over the facts already standing in the instruction files — a directory moved
without a word makes a rule silently false, and nothing but a check will ever notice.

A confirmed fact goes to EVERY instruction file this machine has, not only to the one of Claude
Code: the user works in one tool today and in another tomorrow, and a fact written down in a file
the other tool never reads is a fact nobody knows.

Writing is allowed, but ONLY inside "## Co wiem"; everything above it and the whole block between
the MegaRuchacz markers is off limits, and a file is copied aside (wiedza/kopie) before a change —
facts entering without being asked have to have a way back.

Run: uv --directory C:\\dev\\claude-worker\\lore run python -m lore.verify [--proba]
"""

from __future__ import annotations

import re
import shutil
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from .db import CLAUDE_HOME, log
from .facts import (SESSIONS_FIELD, SIGHTED, SIGHTED_AGAIN, SOURCES_HEADER, SOURCES_NAME,
                    normalize)

KNOWLEDGE_DIR = CLAUDE_HOME / "wiedza"
CANDIDATES_PATH = KNOWLEDGE_DIR / "kandydaci.md"
BACKUP_DIR = KNOWLEDGE_DIR / "kopie"
STATE_NAME = ".wiedza-stan.txt"  # 'klucz: wartosc', the same shape as .koszt-cyklu.txt

# The instruction files of the tools the user may be running — written, but never outside the
# "## Co wiem" section. A list on purpose: another tool is one more line here and nothing else.
# A file that is not there means the tool is not installed — it is skipped, never created.
INSTRUCTION_PATHS = (
    CLAUDE_HOME / "CLAUDE.md",
    Path.home() / ".codex" / "AGENTS.md",
)

KNOWLEDGE_HEADING = "## Co wiem"
GUARD_MARKER = "<!-- MegaRuchacz:start -->"  # from here down the file belongs to the installer
DEFAULT_SUBSECTION = "### Nad czym pracuje"
EMPTY_MARKER = "_(pusto)_"  # placeholder of an empty subsection — the first entry replaces it

# The three layers the harvest labels a fact with (lore.facts.LAYERS) mapped onto the places they
# live in. The label decides; the keyword guess below is only for the entries written before the
# labels existed — there are still dozens of those in the waiting room.
STABLE_SUBSECTIONS = {
    "uzytkownik": "### O użytkowniku",
    "firma": "### O firmie",
    "projekty": DEFAULT_SUBSECTION,
    "praca": "### Jak pracuje",
}
CURRENT_SUBSECTION = "### Bieżące"
REFERENCE_SUBSECTION = "### Dane referencyjne"

# The ceiling of the durable layer. narzedzia\koszt-pamieci.ps1 ($ProgStalej) is where it is
# decided and reported; it is repeated here as a constant on purpose — a Python run must not
# depend on parsing a PowerShell script, and a number that drifts apart is caught by
# test_the_ceiling_matches_the_cost_script.
STABLE_LIMIT = 8000

# How long an entry of the current layer lives: the same 14 days as $DniWaznosci in
# narzedzia\koszt-pamieci.ps1 and "Wygasanie" in the global rules. Past that, an entry the automaton
# wrote itself is taken out by itself — that is what makes letting a fact in on ONE conversation's
# word safe. An entry the user wrote by hand is only counted: throwing it away is his call.
CURRENT_DAYS = 14
# "Repetition is the evidence": heard in this many DIFFERENT conversations, a fact has earned the
# durable layer. Two, because one is exactly the case that went wrong — a single conversation's
# passing remark became a rule for every session that followed.
MIN_CONVERSATIONS = 2
# At most this many promotions per run; the most repeated go first, the rest wait in the current
# layer for the next run (and the run says so). Why 3: an entry of the durable layer is ~110
# characters on average (measured on the real file 2026-09-24: 49 entries, 5 410 characters), so
# three are ~330 characters, ~110 tokens at the 3 characters per token koszt-pamieci.ps1 uses —
# about 4% of the ~2 941 tokens every session started with before the jump. The jump itself was
# sixty facts, +68%, in one run. At three a day the growth is small enough to be read in the
# summary of each run, and still quick enough that a fact heard twice waits days, not weeks.
MAX_PROMOTIONS = 3
CURRENT_HEADING_RE = re.compile(r"^###\s+Bie")  # written both with and without the Polish tail
SUBHEADING_RE = re.compile(r"^#{1,3}\s")

# Deliberately crude: keywords, no model call. Classifying a one-line fact is not worth a round
# trip to a model, and a fact put in the wrong subsection is still a fact the user can move.
SUBSECTION_HINTS = (
    ("### O firmie", ("firma", "firmy", "firmie", "firmę", "marka", "marki", "marką", "sprzeda",
                      "asortyment", "produkt", "klient", "sklep", "hurt", "magazyn", "oferty")),
    ("### Dane referencyjne", ("identyfikator", "sku", "asin", "klucz api", "numer konta",
                               "zestawienie", "słownik", "mapowanie")),
    ("### Jak pracuje", ("woli", "zwykle", "zasada", "nawyk", "oczekuje", "wymaga", "raport",
                         "zawsze", "nigdy", "najpierw")),
    ("### O użytkowniku", ("nie jest", "nie chce", "ceni", "lubi", "mieszka", "nazywa się")),
)

_DRIVE = re.compile(r"^[A-Za-z]:[\\/]")
_BACKTICKED = re.compile(r"`([^`\r\n]+)`")
_QUOTED = re.compile(r"\"([^\"\r\n]+)\"")
# an example, not a path: <katalog>, C:\..., %USERPROFILE%, a wildcard
_PLACEHOLDER = re.compile(r"[<>*?]|\.\.\.|\u2026|%[^%\s]+%")
_TRAILING = " \t.,;:!?)]}'\"`\u201e\u201d\u00bb"

# A waiting room entry: the box, the day it was harvested, the layer label written by lore.facts,
# and the fact itself. Both the day and the label are optional — entries predating them are read
# as a durable fact of an unknown day instead of dropping out of the run.
_CANDIDATE = re.compile(
    r"^(?P<head>\s*-\s*\[)(?P<box>[ xX!?])(?P<mid>\]\s*(?:\[(?P<day>\d{4}-\d{2}-\d{2})\]\s*)?)"
    r"(?P<label>\((?P<layer>stala|biezaca|referencyjna)(?:[/:](?P<detail>[^)]*))?\)\s*)?"
    r"(?P<text>.+)$")
# the continuation line lore.facts writes under a "referencyjna" entry
_POINTER_LINE = re.compile(r"^\s+odsy[łl]acz:\s*(.+)$")
_NOT_FOUND = re.compile(r"\s*\(nie znaleziono:[^)]*\)\s*$")
_DISPUTED = re.compile(r"\s*\(sporne:\s.*$")  # the quote inside may hold brackets of its own
_OVER_LIMIT = re.compile(r"\s*\(nie mieści się:[^)]*\)\s*$")
_BULLET_START = re.compile(r"^\s{0,3}[-*]\s+\S")
_UNCONFIRMED = re.compile(r"\s*<!--\s*niepotwierdzone[^>]*-->\s*$")
_LEADING_DAY = re.compile(r"^\[\d{4}-\d{2}-\d{2}\]\s*")  # the date a "biezaca" entry carries


# ---------------------------------------------------------------- what can be checked at all

@dataclass
class Check:
    """One machine-checkable claim taken out of a fact, with its verdict."""
    claim: str
    ok: bool
    kind: str = "path"


# Windows hides the extension of an executable in everyday speech: a fact says
# 'pg_ctl' where the file on disk is 'pg_ctl.exe'. Checking the bare name alone
# reported healthy facts as broken, which teaches the user to ignore the warnings.
_EXECUTABLE_SUFFIXES = (".exe", ".cmd", ".bat", ".ps1", ".com")


def path_exists(raw: str) -> bool:
    """A malformed path is 'does not exist', not a crash — the text comes from a model."""
    try:
        p = Path(raw)
        if p.exists():
            return True
        # only for a name with no suffix of its own — 'robot.js' must not become 'robot.js.exe'
        if not p.suffix:
            return any(Path(raw + s).exists() for s in _EXECUTABLE_SUFFIXES)
        return False
    except (OSError, ValueError):
        return False


def paths_in(text: str) -> list[str]:
    """Windows paths in a sentence: quoted ones whole, bare ones token by token."""
    found: list[str] = []
    rest = text
    for pattern in (_BACKTICKED, _QUOTED):
        parts, last = [], 0
        for m in pattern.finditer(rest):
            inner = m.group(1).strip()
            if not _DRIVE.match(inner):
                continue  # not a path — leave it in place, a path may still hide inside
            found.append(inner)  # quoted: the spaces belong to the path, nothing to guess
            parts.append(rest[last:m.start()])
            last = m.end()
        parts.append(rest[last:])
        rest = " ".join(parts)
    found.extend(_bare_paths(rest))
    return _clean(found)


def _bare_paths(text: str) -> list[str]:
    """Paths in plain text, where nothing marks where they end — a heuristic, not a parser."""
    tokens = text.split()
    out, i = [], 0
    while i < len(tokens):
        piece = tokens[i].lstrip("(`\"'\u201e")
        i += 1
        if not _DRIVE.match(piece):
            continue
        # a space inside a path is believable only while the next word still carries a separator;
        # a new drive letter starts another path instead of extending this one
        while i < len(tokens) and ("\\" in tokens[i] or "/" in tokens[i]) and not _DRIVE.match(tokens[i]):
            piece += " " + tokens[i]
            i += 1
        out.append(piece)
    return out


def _clean(raw: list[str]) -> list[str]:
    """Trims the sentence punctuation, drops the examples, removes duplicates — order kept."""
    out, seen = [], set()
    for item in raw:
        # the placeholder is looked for BEFORE trimming — 'C:\\dev\\...' would otherwise lose its
        # dots to the sentence punctuation and pass as the real directory 'C:\\dev\\'
        if _PLACEHOLDER.search(item):
            continue
        p = item.rstrip(_TRAILING).strip()
        if not _DRIVE.match(p):
            continue
        key = p.casefold().rstrip("\\/")
        if key in seen:
            continue
        seen.add(key)
        out.append(p)
    return out


# A fact can state plainly that the path lives on ANOTHER machine ('na laptopie
# pakowanie2', 'na serwerze 192.168.0.105'). Looking for it on this disk always
# fails, and reporting that as 'the fact stopped checking out' is a false alarm —
# the fact may well be true over there. Such a fact is simply not checkable here.
_ELSEWHERE = re.compile(
    r"\b(?:na|w)\s+(?:laptopie|serwerze|maszynie|komputerze|hoscie|hoście)\b"
    r"|\bpakowanie2\b"
    r"|\b(?:192\.168|10\.)\d",
    re.IGNORECASE,
)


def on_another_machine(text: str) -> bool:
    return bool(_ELSEWHERE.search(text))


def check_paths(text: str, exists) -> list[Check]:
    if on_another_machine(text):
        return []
    return [Check(p, exists(p)) for p in paths_in(text)]


# The one place to plug in another kind of check (a database table, an HTTP endpoint, a git remote):
# a function taking the fact text and returning its Checks — everything below works on Checks alone.
CHECKERS = (check_paths,)


@dataclass
class Verdict:
    checks: list[Check] = field(default_factory=list)

    @property
    def checkable(self) -> bool:
        return bool(self.checks)

    @property
    def missing(self) -> list[str]:
        return [c.claim for c in self.checks if not c.ok]

    @property
    def confirmed(self) -> bool:
        """Confirmed means: there was something to check and all of it holds."""
        return self.checkable and not self.missing


def verify(text: str, exists=None) -> Verdict:
    exists = exists or path_exists
    return Verdict([c for checker in CHECKERS for c in checker(text, exists)])


# ---------------------------------------------------------------- contradiction

# THE one thing this automaton is not allowed to settle. Everything else it can be wrong about
# cheaply — a fact in the wrong subsection is one move for the user. Picking between two versions
# of the same fact is different: whichever it picks, the loser disappears without a word and the
# winner may be the false one, and that kind of quiet mistake lives for months.
#
# The detection is deliberately narrow — the same sentence with ONE detail changed:
#   "Postgres stoi w C:\\dev\\pgsql"  vs  "Postgres stoi w D:\\pgsql"      (a value swapped)
#   "Redis nie jest potrzebny"        vs  "Redis jest potrzebny"           (a negation flipped)
# Narrow, because a false alarm sends the user back to a queue we have just abolished. The price
# is stated plainly: a contradiction phrased in other words is NOT caught and the new fact enters
# on its own. That is a known hole, not a solved problem — see the report of the run, which says
# how many entries were compared.
_NEGATIONS = frozenset({"nie", "nigdy", "bez", "żaden", "żadna", "żadne", "żadnego", "brak",
                        "zaden", "zadna", "zadne", "zadnego"})
_NUMBER = re.compile(r"^\d+$")
MIN_SKELETON_WORDS = 3  # below that the "same sentence" is any sentence — pure false alarm


def skeleton(text: str) -> tuple[str, tuple[str, ...]]:
    """The sentence split into what it is ABOUT and what it CLAIMS.

    The subject is the wording with every concrete value taken out; the claim is those values —
    paths, numbers and negations, the three things two versions of one fact differ in.
    """
    rest = text
    values = []
    for p in paths_in(text):
        values.append(p.casefold().rstrip("\\/"))
        rest = rest.replace(p, " ")
    words = []
    for w in normalize(rest).split():
        if _NUMBER.match(w) or w in _NEGATIONS:
            values.append(w)
        else:
            words.append(w)
    return " ".join(words), tuple(sorted(values))


def contradicted_by(text: str, standing: list[str]) -> str | None:
    """The standing entry the fact clashes with, or None. The first clash wins — one is enough."""
    subject, claim = skeleton(text)
    if len(subject.split()) < MIN_SKELETON_WORDS:
        return None
    for entry in standing:
        other_subject, other_claim = skeleton(entry)
        if other_subject == subject and other_claim != claim:
            return entry
    return None


QUOTE_LIMIT = 120  # a quote is a pointer to the entry, not a copy of it


def _quote(entry: str) -> str:
    short = " ".join(entry.split())
    return short if len(short) <= QUOTE_LIMIT else short[:QUOTE_LIMIT].rstrip() + "…"


# ---------------------------------------------------------------- the waiting room

@dataclass
class Candidate:
    """One entry of the waiting room, read back with the layer label the harvest gave it."""
    text: str
    layer: str = "stala"
    detail: str = ""  # the subsection for "stala", the file name for "referencyjna"
    day: str = ""  # the day it was harvested — the trail back to the conversation
    pointer: str = ""  # "referencyjna" only: the line that stands in place of the whole listing

    @property
    def heading(self) -> str:
        """Always the current layer, whatever the label says — the label only decides where the
        fact goes IF it is promoted later (see promotion_heading)."""
        return CURRENT_SUBSECTION

    @property
    def shown(self) -> str:
        """The sentence that stands in the file — the reference layer only leaves a pointer behind,
        the listing itself goes to wiedza/<plik>."""
        if self.layer == "referencyjna":
            return self.pointer or f"Szczegóły w ~/.claude/wiedza/{self.detail}"
        return self.text

    def entry(self, today: str) -> str:
        """What actually stands in the current layer: the sentence with its date, which the ageing
        reads. An entry without a harvest date gets the day it was written — undated, it would
        never expire."""
        return f"[{self.day or today}] {self.shown}"


@dataclass
class Reviewed:
    lines: list[str] = field(default_factory=list)  # the new content of the waiting room
    approved: list[Candidate] = field(default_factory=list)  # they go into the knowledge, by themselves
    suspicious: list[tuple[str, list[str]]] = field(default_factory=list)  # a claim that does not hold
    disputed: list[tuple[str, str]] = field(default_factory=list)  # (fact, the entry it contradicts)
    waiting: int = 0  # still there, with nobody but the user able to decide


def _flag(m: re.Match, box: str, text: str) -> str:
    """The entry written back with another box and a reason glued to it — the head, the date and
    the layer label stay byte for byte. Built by hand, not by %-formatting: a fact may well say
    '100% marży' and formatting would blow up on it."""
    return f"{m.group('head')}{box}{m.group('mid')}{m.group('label') or ''}{text}"


def _read_candidate(m: re.Match) -> Candidate:
    text = _OVER_LIMIT.sub("", _DISPUTED.sub("", _NOT_FOUND.sub("", m.group("text")))).rstrip()
    layer = m.group("layer") or "stala"
    detail = (m.group("detail") or "").strip()
    return Candidate(text, layer, detail, m.group("day") or "")


def review_candidates(lines: list[str], exists=None, standing: list[str] | None = None) -> Reviewed:
    """Empties the waiting room: everything that is not rejected or disputed goes.

    `standing` are the facts already written down (they decide the contradictions). There is no
    ceiling to check here any more: what goes, goes to the current layer, which ages out by itself;
    the ceiling of the durable layer is checked where something is promoted into it.
    """
    exists = exists or path_exists
    standing = list(standing or [])
    out = Reviewed()
    pending: Candidate | None = None  # the entry the next "odsyłacz:" line belongs to
    for line in lines:
        pointer = _POINTER_LINE.match(line)
        if pointer:
            if pending is None:  # nothing to attach it to — it stays exactly where it is
                out.lines.append(line)
            else:
                pending.pointer = pointer.group(1).strip()
            continue  # it travels with its fact instead of staying behind as an orphan
        pending = None
        m = _CANDIDATE.match(line)
        if not m or m.group("box") not in (" ", "!", "?"):  # '[x]' is the user's decision, not ours
            out.lines.append(line)
            continue
        candidate = _read_candidate(m)
        verdict = verify(candidate.text, exists)
        if verdict.missing:
            out.suspicious.append((candidate.text, verdict.missing))
            out.lines.append(_flag(m, "!", f"{candidate.text}"
                                           f" (nie znaleziono: {', '.join(verdict.missing)})"))
            out.waiting += 1
            continue
        clash = contradicted_by(candidate.text, standing)
        if clash is not None:
            out.disputed.append((candidate.text, clash))
            out.lines.append(_flag(m, "?", f"{candidate.text} (sporne: przeczy wpisowi"
                                          f" \u201e{_quote(clash)}\u201d)"))
            out.waiting += 1
            continue
        out.approved.append(candidate)
        standing.append(candidate.text)  # two candidates of one run can contradict each other too
        pending = candidate  # its "odsyłacz:" line, if any, comes next and leaves with it
    return out


# ---------------------------------------------------------------- the rules ("## Co wiem")

def section_bounds(lines: list[str]) -> tuple[int, int] | None:
    """(start, end) of the body of '## Co wiem'; None when the section is not there at all."""
    start = None
    for i, line in enumerate(lines):
        if line.strip().startswith(KNOWLEDGE_HEADING):
            start = i + 1
            break
    if start is None:
        return None
    for j in range(start, len(lines)):
        stripped = lines[j].strip()
        if stripped.startswith("## ") or stripped == GUARD_MARKER:
            return start, j
    return start, len(lines)


def _subsection_bounds(body: list[str], heading: re.Pattern) -> tuple[int, int] | None:
    """(start, end) of a subsection inside the body — end is the next heading of any level."""
    start = None
    for i, line in enumerate(body):
        if heading.match(line.strip()):
            start = i
            break
    if start is None:
        return None
    for j in range(start + 1, len(body)):
        if SUBHEADING_RE.match(body[j].strip()):
            return start, j
    return start, len(body)


def stable_chars(lines: list[str]) -> int:
    """How many characters the durable layer of a file takes — the number the ceiling applies to.

    Counted exactly the way narzedzia\\koszt-pamieci.ps1 (Zmierz-Warstwy) counts it: the whole
    "## Co wiem" section together with its heading, minus the "### Bieżące" subsection, joined
    with newlines. Two different numbers under one threshold would mean one of them is lying —
    and the user is told the cost by that script, not by this one.
    """
    bounds = section_bounds(lines)
    if bounds is None:
        return 0
    start, end = bounds
    body = lines[start:end]
    current = _subsection_bounds(body, CURRENT_HEADING_RE)
    if current is not None:
        body = body[:current[0]] + body[current[1]:]
    return len("\n".join([lines[start - 1]] + body))


def room_for_facts(lines: list[str]) -> int:
    """Characters left before the ceiling; never negative — an already fat file takes nothing new."""
    return max(0, STABLE_LIMIT - stable_chars(lines))


@dataclass
class Bullet:
    start: int
    end: int  # exclusive
    lines: list[str]

    @property
    def text(self) -> str:
        """The whole entry in one line — an entry wrapped over several lines is still one fact."""
        joined = " ".join(part.strip() for part in self.lines)
        return _UNCONFIRMED.sub("", joined).strip().lstrip("-*").strip()


def bullets(body: list[str]) -> list[Bullet]:
    """Entries of the section, together with their wrapped continuation lines."""
    out, i = [], 0
    while i < len(body):
        if not _BULLET_START.match(body[i]):
            i += 1
            continue
        end = i + 1
        while end < len(body) and body[end].startswith((" ", "\t")) and body[end].strip() \
                and not _BULLET_START.match(body[end]):
            end += 1
        out.append(Bullet(i, end, body[i:end]))
        i = end
    return out


def subsection_for(text: str) -> str:
    """Which subsection a confirmed fact goes to — a guess, with a safe default when unsure."""
    low = text.lower()
    for heading, hints in SUBSECTION_HINTS:
        if any(hint in low for hint in hints):
            return heading
    return DEFAULT_SUBSECTION


_POLISH = str.maketrans("ąćęłńóśźż", "acelnoszz")


def _heading_key(heading: str) -> str:
    """'### Bieżące' and '### Biezace' are the same subsection — the user writes it both ways,
    and a second heading created next to the first one would split the layer in two."""
    return heading.strip().lower().translate(_POLISH)


def _heading_index(body: list[str], heading: str) -> int | None:
    wanted = _heading_key(heading)
    for i, line in enumerate(body):
        if _heading_key(line) == wanted:
            return i
    return None


def insert_fact(body: list[str], fact: str, heading: str) -> list[str]:
    """Appends the fact at the end of its subsection (creating the subsection if it is missing)."""
    entry = f"- {fact}"
    idx = _heading_index(body, heading)
    if idx is None:
        tail = body + ([] if body and not body[-1].strip() else [""])
        return tail + [heading, "", entry, ""]
    end = idx + 1
    while end < len(body) and not body[end].strip().startswith(("### ", "## ")):
        end += 1
    kept = [line for line in body[idx + 1:end] if line.strip() != EMPTY_MARKER]
    while kept and not kept[-1].strip():
        kept.pop()
    if not kept or kept[0].strip():
        kept.insert(0, "")
    return body[:idx + 1] + kept + [entry, ""] + body[end:]


@dataclass
class Audited:
    body: list[str] = field(default_factory=list)
    stale: list[tuple[str, list[str]]] = field(default_factory=list)  # stopped checking out
    healed: list[str] = field(default_factory=list)  # marked earlier, true again


def audit_rules(body: list[str], exists=None, day: str | None = None) -> Audited:
    """Marks the standing facts that no longer check out — marks, never deletes.

    A missing path may be a network drive that is simply not mounted right now, so the entry only
    gets a comment; throwing a fact away is the user's decision, not the automaton's.
    """
    exists = exists or path_exists
    day = day or datetime.now().strftime("%Y-%m-%d")
    out = Audited(body=list(body))
    for bullet in reversed(bullets(body)):  # from the end, so the indexes above stay valid
        text = bullet.text
        verdict = verify(text, exists)
        marked = any(_UNCONFIRMED.search(line) for line in bullet.lines)
        clean = [_UNCONFIRMED.sub("", line) for line in bullet.lines]
        if verdict.missing:
            note = f" <!-- niepotwierdzone {day}: nie ma {', '.join(verdict.missing)} -->"
            clean[-1] = clean[-1].rstrip() + note
            out.stale.append((text, verdict.missing))
        elif marked and verdict.confirmed:
            out.healed.append(text)  # the drive is back — the warning goes away
        elif not marked:
            continue
        out.body[bullet.start:bullet.end] = clean
    out.stale.reverse()
    out.healed.reverse()
    return out


# ---------------------------------------------------------------- writing

def _read(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return None


def _newline(raw: str) -> str:
    """Keeps the line endings the file already uses — a whole-file rewrite is not a change."""
    return "\r\n" if "\r\n" in raw else "\n"


def instruction_files() -> list[Path]:
    """The instruction files that really exist here — a missing one means the tool is not used."""
    return [path for path in INSTRUCTION_PATHS if path.is_file()]


def backup_file(path: Path, day: str | None = None) -> Path:
    """A copy with the date in the name, taken before every change; the name follows the source."""
    day = day or datetime.now().strftime("%Y-%m-%d-%H%M%S")
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    target = BACKUP_DIR / f"{path.stem}-{day}.md"
    shutil.copy2(path, target)
    return target


def _entry_text(line: str) -> str:
    """One line of a file stripped down to the fact itself — no bullet, no date, no warning."""
    return _LEADING_DAY.sub("", _UNCONFIRMED.sub("", line).strip().lstrip("-*").strip())


def facts_in(lines: list[str]) -> set[str]:
    """What this file already says, normalized — a fact standing here is not written down twice.

    The date of a "biezaca" entry is taken off first: left in, it would make the same sentence
    look new every single day and the current layer would fill up with copies of itself.
    """
    known = {normalize(_entry_text(line)) for line in lines}
    known.discard("")
    return known


def standing_facts(lines: list[str]) -> list[str]:
    """The facts of one file that are in force — the "## Co wiem" section, entry by entry.

    They are what a new fact is confronted with: a contradiction can only be found against
    something that is actually written down.
    """
    bounds = section_bounds(lines)
    if bounds is None:
        return []
    start, end = bounds
    return [text for text in (_LEADING_DAY.sub("", b.text) for b in bullets(lines[start:end]))
            if text]


@dataclass
class FileResult:
    """What one pass did to one instruction file."""
    path: Path
    stale: list[tuple[str, list[str]]] = field(default_factory=list)
    healed: list[str] = field(default_factory=list)
    added: list[str] = field(default_factory=list)  # new facts, written into the current layer
    promoted: list[str] = field(default_factory=list)  # moved from the current layer to the durable
    expired: list[str] = field(default_factory=list)  # taken out of the current layer by their age
    changed: bool = False
    backup: str | None = None
    note: str | None = None  # set when the file has no "## Co wiem" — nothing was written


# ---------------------------------------------------------------- the two layers of "## Co wiem"

_DAY = re.compile(r"^\[(\d{4}-\d{2}-\d{2})\]")


def fact_key(text: str) -> tuple[str, tuple[str, ...]]:
    """'The same fact', decided without a model — a model call on every run is a cost every day.

    The skeleton the contradiction check uses: the wording with the values taken out, plus the
    values (paths, numbers, negations). A contradiction is the same wording with ANOTHER claim;
    a repetition is the same wording with the SAME claim — so both halves have to be equal.
    Deliberately narrow: one fact said in other words is NOT recognised as a repetition. The price
    of that is small and known — such a fact just stays in the current layer and ages out; a wrong
    promotion would instead ride along with every session for months.
    """
    return skeleton(_LEADING_DAY.sub("", text.strip()))


def _layers(lines: list[str]) -> tuple[list[str], list[tuple[str, str]]]:
    """The entries of '## Co wiem' split in two: the durable ones, and (day, sentence) of the
    current ones — the day is '' when the entry carries none."""
    bounds = section_bounds(lines)
    if bounds is None:
        return [], []
    body = lines[bounds[0]:bounds[1]]
    current = _subsection_bounds(body, CURRENT_HEADING_RE)
    if current is None:
        return [b.text for b in bullets(body) if b.text], []
    durable = body[:current[0]] + body[current[1]:]
    now = []
    for b in bullets(body[current[0]:current[1]]):
        m = _DAY.match(b.text)
        now.append((m.group(1) if m else "", _LEADING_DAY.sub("", b.text)))
    return [b.text for b in bullets(durable) if b.text], now


def _drop_current(body: list[str], keys: set) -> tuple[list[str], list[str]]:
    """Takes the entries with these keys out of "### Bieżące" — nowhere else; returns the new
    body and the sentences that went. An emptied subsection gets its placeholder back."""
    bounds = _subsection_bounds(body, CURRENT_HEADING_RE)
    if bounds is None or not keys:
        return list(body), []
    start, end = bounds
    part = body[start:end]
    gone = []
    for b in reversed(bullets(part)):  # from the end, so the indexes above stay valid
        if fact_key(b.text) in keys:
            gone.append(_LEADING_DAY.sub("", b.text))
            del part[b.start:b.end]
    if gone and not bullets(part):
        while len(part) > 1 and not part[-1].strip():
            part.pop()
        part += ["", EMPTY_MARKER, ""]
    gone.reverse()
    return body[:start] + part + body[end:], gone


# ---------------------------------------------------------------- repetition is the evidence

WRITTEN, PROMOTED, EXPIRED = "wpisany", "awansowany", "wygasł"  # the events this module writes
_OLD_SESSIONS = re.compile(r"\(sesje:\s*([^)]*)\)")
_POINTER_NOTE = re.compile(r";\s*odsyłacz:\s*(.+)$")


@dataclass
class Sighting:
    """One time the harvest brought a fact out of the conversations — one line of the trail."""
    day: str
    label: str  # 'stala/firma', 'biezaca', 'referencyjna:plik.md' — what the model called it
    sessions: frozenset[str] | None  # the conversations of that batch; None = not known in full
    text: str


@dataclass
class Trail:
    """What wiedza/zrodla.md knows, read back for the two decisions: promote, and let expire."""
    sightings: dict = field(default_factory=dict)  # fact key -> [Sighting], oldest first
    written: set = field(default_factory=set)  # keys of entries the automaton put into "Bieżące"
    pointers: dict = field(default_factory=dict)  # key of a pointer line -> key of its listing

    def evidence(self, key) -> list[Sighting]:
        """The sightings behind an entry — for a reference pointer, those of its listing."""
        return self.sightings.get(self.pointers.get(key, key), [])


def _sessions(raw: str) -> frozenset[str] | None:
    ids = raw[len(SESSIONS_FIELD):].split()
    return frozenset(ids) if ids and ids != ["-"] else None


def _old_sessions(source: str) -> frozenset[str] | None:
    """The sessions of a line written before the full list existed — only when it names them all:
    'i 2 innych' hides exactly the ones that could be shared with another sighting."""
    m = _OLD_SESSIONS.search(source)
    if not m or " innych" in m.group(1):
        return None
    return frozenset(s.strip() for s in m.group(1).split(",") if s.strip()) or None


def read_trail() -> Trail:
    """The trail parsed; a line it cannot read is skipped — no evidence is the safe side here."""
    out = Trail()
    raw = _read(KNOWLEDGE_DIR / SOURCES_NAME)
    for line in (raw or "").splitlines():
        if not line.startswith("- "):
            continue
        parts = line[2:].split(" | ", 5)
        if len(parts) < 5:
            continue
        day, event = parts[0].strip(), parts[1].strip()
        if event in (SIGHTED, SIGHTED_AGAIN):
            if len(parts) == 6 and parts[4].startswith(SESSIONS_FIELD):
                sessions, text = _sessions(parts[4]), parts[5]
            else:  # the format from before the full list of sessions
                sessions, text = _old_sessions(parts[3]), " | ".join(parts[4:])
            out.sightings.setdefault(fact_key(text), []).append(
                Sighting(day, parts[2].strip(), sessions, text.strip()))
        elif event == WRITTEN and parts[2].strip().startswith("biezaca"):
            text = " | ".join(parts[4:])
            out.written.add(fact_key(text))
            pointer = _POINTER_NOTE.search(parts[3])
            if pointer:
                out.written.add(fact_key(pointer.group(1)))
                out.pointers[fact_key(pointer.group(1))] = fact_key(text)
    return out


def conversations(sightings: list[Sighting]) -> int:
    """In how many DIFFERENT conversations a fact was heard, counted on the safe side.

    The model reads a whole batch and does not say which conversation a fact came from, so a
    sighting is tied to the set of conversations of its batch. Two sightings count as two
    conversations only when their sets share nothing: one conversation often spans two batches
    (the real trail of 2026-09-24 has exactly that — one session, two days, two batches), and a
    fact repeated inside it is one conversation's word, not two. Greedy, smallest sets first: at
    worst it counts too few, which costs a promotion, never a wrong one.
    """
    taken: set[str] = set()
    count = 0
    for group in sorted((s.sessions for s in sightings if s.sessions), key=len):
        if taken.isdisjoint(group):
            taken |= group
            count += 1
    return count


@dataclass
class Promotion:
    text: str  # the sentence as it stands in the current layer, without its date
    heading: str  # where it goes in the durable layer
    conversations: int
    first_seen: str

    @property
    def key(self) -> tuple:
        return fact_key(self.text)


def promotion_heading(text: str, label: str) -> str:
    if label.startswith("referencyjna"):
        return REFERENCE_SUBSECTION
    if label.startswith("stala/"):
        return STABLE_SUBSECTIONS.get(label[len("stala/"):]) or subsection_for(text)
    return subsection_for(text)


@dataclass
class Promotions:
    chosen: list[Promotion] = field(default_factory=list)
    deferred: list[Promotion] = field(default_factory=list)  # earned it, over MAX_PROMOTIONS
    over_limit: list[Promotion] = field(default_factory=list)  # earned it, no room under the ceiling


def choose_promotions(current: list[str], trail: Trail, durable: set,
                      room: int | None) -> Promotions:
    """Which entries of the current layer move to the durable one in this run.

    `current` — the sentences of the current layer, this run's newcomers included; `durable` — the
    keys already standing in the durable layer (nothing there is moved or doubled — this is not
    a migration backwards); `room` — characters left under the ceiling, None when not measured.

    A fact the model itself labelled "biezaca" is not promoted however often it comes back: it said
    the thing changes in days, and the durable layer never ages out.
    """
    earned, seen = [], set()
    for text in current:
        key = fact_key(text)
        if key in seen or key in durable:
            continue
        seen.add(key)
        sightings = trail.evidence(key)
        heard = conversations(sightings)
        if heard < MIN_CONVERSATIONS or sightings[-1].label.startswith("biezaca"):
            continue
        earned.append(Promotion(text, promotion_heading(text, sightings[-1].label), heard,
                                min(s.day for s in sightings)))
    earned.sort(key=lambda p: (-p.conversations, p.first_seen))  # the most repeated first
    out, left = Promotions(), room
    for p in earned:
        if len(out.chosen) >= MAX_PROMOTIONS:
            out.deferred.append(p)
            continue
        cost = len(f"- {p.text}") + 1
        if left is not None and cost > left:
            # the ceiling stops it, and says so — it stays in the current layer meanwhile
            out.over_limit.append(p)
            continue
        if left is not None:
            left -= cost
        out.chosen.append(p)
    return out


def _age(day: str, today: str) -> int | None:
    try:
        return (datetime.strptime(today, "%Y-%m-%d") - datetime.strptime(day, "%Y-%m-%d")).days
    except ValueError:
        return None


def expiring(current: list[tuple[str, str]], trail: Trail, today: str,
             keep: set) -> tuple[dict, list[str]]:
    """Entries of the current layer past CURRENT_DAYS: {key: sentence} of those the automaton
    wrote (they go), and the sentences of those the user wrote himself (only counted — the global
    rules tell the agent to ask him about them, deleting is not the automaton's call)."""
    leaving, own = {}, []
    for day, text in current:
        age = _age(day, today)
        key = fact_key(text)
        if age is None or age <= CURRENT_DAYS or key in keep:
            continue
        if key in trail.written:
            leaving[key] = text
        else:
            own.append(text)
    return leaving, own


def update_file(path: Path, approved: list[Candidate], exists=None, day: str | None = None,
                dry_run: bool = False, promoted: list[Promotion] | tuple = (),
                leaving: set | frozenset = frozenset()) -> FileResult:
    """Audits what stands in one file, then: the promoted facts leave the current layer for the
    durable one, the expired ones leave the current layer, and the approved facts it does not know
    yet come into the current layer with their date — never anywhere else.
    """
    raw = _read(path)
    lines = (raw or "").splitlines()
    bounds = section_bounds(lines) if raw is not None else None
    if bounds is None:
        return FileResult(path, note=f"no '{KNOWLEDGE_HEADING}' section in {path}"
                                     " — nothing approved automatically")
    start, end = bounds
    today = day or datetime.now().strftime("%Y-%m-%d")
    audited = audit_rules(lines[start:end], exists, day)
    out = FileResult(path, stale=audited.stale, healed=audited.healed)
    moving = {p.key for p in promoted}
    body, gone = _drop_current(audited.body, moving | set(leaving))
    gone_keys = {fact_key(text) for text in gone}
    out.expired = [text for text in gone if fact_key(text) not in moving]
    known = facts_in(lines[:start] + body + lines[end:])
    for p in promoted:
        key = normalize(p.text)
        if key and key not in known:
            known.add(key)
            body = insert_fact(body, p.text, p.heading)
            out.promoted.append(p.text)
        elif p.key in gone_keys:  # already durable here — only its copy in the current layer went
            out.promoted.append(p.text)
    for candidate in approved:
        if fact_key(candidate.shown) in moving:
            continue  # heard twice already — it goes straight to the durable layer, above
        entry = candidate.entry(today)
        key = normalize(_LEADING_DAY.sub("", entry))
        if not key or key in known:
            continue  # already written down here, possibly in other words than the waiting room used
        known.add(key)
        body = insert_fact(body, entry, CURRENT_SUBSECTION)
        out.added.append(candidate.text)
    out.changed = body != lines[start:end]
    if dry_run or not out.changed:
        return out
    out.backup = str(backup_file(path))
    # only the body of the section is swapped — the lines around it are the very same objects
    _write(path, lines[:start] + body + lines[end:], _newline(raw))
    return out


# ---------------------------------------------------------------- the reference layer

REFERENCE_HEADER = """# {name}

Zestawienie wyłowione z rozmów. W trwałej wiedzy stoi w jego miejsce jedna linia odsyłacza —
ten plik czytamy tylko wtedy, gdy rozmowa go dotyczy.
"""


def write_reference(candidate: Candidate, day: str | None = None) -> str | None:
    """The listing itself, put away in wiedza/<plik>; returns the path when something was written.

    Written once per run, not once per instruction file: the pointer belongs to every tool, the
    listing belongs to the disk.
    """
    name = candidate.detail or "do-nazwania.md"
    target = KNOWLEDGE_DIR / Path(name).name  # never outside the knowledge directory
    key = normalize(candidate.text)
    existing = _read(target)
    if existing is not None:
        if key in {normalize(_entry_text(line)) for line in existing.splitlines()}:
            return None
        backup_file(target, day)
    KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    with open(target, "a", encoding="utf-8", newline="\n") as f:
        if existing is None:
            f.write(REFERENCE_HEADER.format(name=target.stem))
        f.write(f"\n- {candidate.text}\n")
    return str(target)


# ---------------------------------------------------------------- where a fact came from

# wiedza/zrodla.md (SOURCES_NAME) — shared with lore.facts, which writes the harvest side of the
# same trail. It lives in a file of its own and not next to the fact on purpose: the durable layer
# is sent with every single session and has an 8 000 character ceiling, so a dozen characters of
# provenance per entry would be paid for over and over again, by a user who looks at it once
# a month. In the knowledge stands the fact; where it came from is one grep away.
# The same file is what the promotion reads back (read_trail) — the trail is also the evidence.


def _note(line: str, what: str) -> None:
    try:
        KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
        first_time = not (KNOWLEDGE_DIR / SOURCES_NAME).exists()
        with open(KNOWLEDGE_DIR / SOURCES_NAME, "a", encoding="utf-8", newline="\n") as f:
            if first_time:
                f.write(SOURCES_HEADER)
            f.write(line)
    except OSError as e:  # the trail is a record of the job, never a reason to lose the job
        log(f"the trail of '{what[:40]}' was not written to {SOURCES_NAME}: {e}")


def _where(files: list[Path]) -> str:
    return ", ".join(path.name for path in files) or "-"


def note_source(candidate: Candidate, files: list[Path], day: str) -> None:
    """One line: when it was written into the current layer, where, and which day it was harvested.

    With that day and the wording of the fact, lore_search finds the conversation it came out of —
    which is the whole question the user was asking: "where did this come from". The label the
    harvest gave it stays in the line; for a listing, so does the pointer that stands for it — that
    is how a pointer in the current layer is tied back to the sightings of its listing.
    """
    origin = f"wyłowiony {candidate.day}" if candidate.day else "wyłowiony kiedyś (wpis bez daty)"
    label = f"{candidate.layer}/{candidate.detail}" if candidate.detail else candidate.layer
    origin += f" jako {label}"
    if candidate.layer == "referencyjna":
        origin += f"; odsyłacz: {candidate.shown.replace('|', '/')}"
    _note(f"- {day} | {WRITTEN} | biezaca -> {_where(files)} | {origin} | {candidate.text}\n",
          candidate.text)


def note_promotion(p: Promotion, files: list[Path], day: str) -> None:
    where = p.heading.lstrip("# ").strip()
    _note(f"- {day} | {PROMOTED} | stala: {where} -> {_where(files)} | z {p.conversations} rozmów,"
          f" pierwszy raz {p.first_seen} | {p.text}\n", p.text)


def note_expiry(text: str, written: str, files: list[Path], day: str) -> None:
    _note(f"- {day} | {EXPIRED} | biezaca -> {_where(files)} | wpis z {written or '?'},"
          f" starszy niz {CURRENT_DAYS} dni | {text}\n", text)


# ---------------------------------------------------------------- the report of the run

def _state(r: dict, day: str) -> dict[str, str]:
    """The run in 'klucz: wartosc' pairs — what the cycle shows the user in one line.

    The first keys keep their old names, narzedzia\\aktualizuj-wiedze.ps1 reads them: "stala" is
    now what was PROMOTED, "biezaca" what came in. The keys after them say the same plainly, plus
    what the new rule adds: what aged out, what waits for a promotion.
    """
    entered, promoted = len(r["entered"]), len(r["promoted"])
    return {
        "data": day,
        "przebieg": r["status"],
        "dopisane": str(entered + promoted),
        "stala": str(promoted),
        "biezaca": str(entered),
        "referencyjna": str(len(r["references"])),
        "weszlo_do_biezacej": str(entered),
        "awansowane_do_stalej": str(promoted),
        "odrzucone": str(len(r["suspicious"])),
        "sporne": str(len(r["disputed"])),
        "wygasle": str(len(r["expired"])),
        # earned a promotion, but the run already took MAX_PROMOTIONS — they stay in the current
        # layer and go first next time
        "awans_odlozony_limitem": str(len(r["deferred"])),
        "wstrzymane_progiem": str(len(r["over_limit"])),
        # older than CURRENT_DAYS, written by the user himself — left for him to decide
        "stare_reczne_w_biezacej": str(len(r["own_old"])),
        # how far the contradiction check could reach at all — it compares against these entries
        # and nothing else, so a small number here means a small guarantee
        "porownane_wpisy": str(r["compared"]),
        "czeka": str(r["waiting"]),
        "prog_stalej": f"{r['stable_chars']}/{STABLE_LIMIT}",
        "przestaly_sie_potwierdzac": str(len(r["stale"])),
        "pliki": str(len(r["files"])),
        "kopie": str(len(r["backups"])),
        "powod": r["powod"],
    }


def _reason(r: dict) -> str:
    """Why the run ended the way it did — ALWAYS filled in.

    A pass that wrote nothing must say so out loud; looking exactly like a pass that never ran is
    how a dead mechanism goes unnoticed for weeks.
    """
    if r.get("note"):
        return r["note"]
    entered, promoted = len(r["entered"]), len(r["promoted"])
    tail = []
    if r["deferred"]:
        tail.append(f"{len(r['deferred'])} czeka na awans (limit {MAX_PROMOTIONS} na przebieg)")
    if r["over_limit"]:
        tail.append(f"{len(r['over_limit'])} wstrzymane progiem warstwy stalej")
    if r["expired"]:
        tail.append(f"wygaslo {len(r['expired'])} z biezacej")
    if entered or promoted:
        head = (f"dopisano {entered + promoted} faktow (do biezacej {entered},"
                f" awans do stalej {promoted})")
        return "; ".join([head] + tail)
    held = []
    if r["suspicious"]:
        held.append(f"{len(r['suspicious'])} odrzucone (nie ma podanych sciezek)")
    if r["disputed"]:
        held.append(f"{len(r['disputed'])} sporne - czekaja na decyzje uzytkownika")
    held += tail
    if held:
        return "nic nie doszlo: " + ", ".join(held)
    if r["waiting"]:
        return f"nic nie doszlo: {r['waiting']} wpisow zostalo w poczekalni"
    return "nic nie doszlo: w poczekalni nie bylo nowych faktow"


def write_state(r: dict, day: str) -> None:
    try:
        KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
        lines = [f"{key}: {value}" for key, value in _state(r, day).items()]
        (KNOWLEDGE_DIR / STATE_NAME).write_text("\n".join(lines) + "\n",
                                                encoding="utf-8", newline="\n")
    except OSError as e:
        log(f"the summary of this run was not written to {STATE_NAME}: {e}")


# ---------------------------------------------------------------- the whole run

def run(dry_run: bool = False, exists=None, day: str | None = None) -> dict:
    """One pass: waiting room -> the current layer of every instruction file, the facts heard in two
    conversations -> the durable layer, the old ones out, plus an audit of what stands there."""
    exists = exists or path_exists
    today = day or datetime.now().strftime("%Y-%m-%d")
    out = {"status": "dry-run" if dry_run else "ok", "approved": [], "suspicious": [],
           "disputed": [], "over_limit": [], "deferred": [], "waiting": 0, "stale": [],
           "healed": [], "backups": [], "files": [], "added": {}, "entered": [], "promoted": [],
           "expired": [], "own_old": [], "references": [], "stable_chars": 0, "compared": 0,
           "powod": ""}
    files = instruction_files()
    out["files"] = [str(path) for path in files]
    contents = {path: (_read(path) or "").splitlines() for path in files}

    # what already stands in the files decides three things: what a new fact may contradict, what
    # is already durable, and how much room the durable layer still has. Measured BEFORE writing.
    standing: list[str] = []
    durable: set = set()
    current: list[tuple[str, str]] = []
    for lines in contents.values():
        _merge(standing, standing_facts(lines))
        stable, now = _layers(lines)
        durable |= {fact_key(text) for text in stable}
        _merge(current, now, key=lambda item: fact_key(item[1]))
    out["compared"] = len(standing)
    out["stable_chars"] = max((stable_chars(lines) for lines in contents.values()), default=0)
    room = min((room_for_facts(lines) for lines in contents.values()), default=None)

    raw_candidates = _read(CANDIDATES_PATH)
    reviewed = review_candidates((raw_candidates or "").splitlines(), exists, standing)
    out["approved"] = [c.text for c in reviewed.approved]
    out["suspicious"] = list(reviewed.suspicious)
    out["disputed"] = list(reviewed.disputed)
    out["waiting"] = reviewed.waiting

    trail = read_trail()
    for c in reviewed.approved:  # a newcomer's pointer stands for its listing, as in note_source
        if c.layer == "referencyjna":
            trail.pointers[fact_key(c.shown)] = fact_key(c.text)
    chosen = choose_promotions([text for _, text in current] + [c.shown for c in reviewed.approved],
                               trail, durable, room)
    out["deferred"] = [p.text for p in chosen.deferred]
    out["over_limit"] = [p.text for p in chosen.over_limit]
    leaving, out["own_old"] = expiring(current, trail, today, {p.key for p in chosen.chosen})

    results = [update_file(path, reviewed.approved, exists, today, dry_run, chosen.chosen,
                           set(leaving)) for path in files]
    for r in results:
        _merge(out["stale"], r.stale, key=lambda item: item[0])
        _merge(out["healed"], r.healed)
        _merge(out["entered"], r.added)
        _merge(out["promoted"], r.promoted)
        _merge(out["expired"], r.expired)
        if r.added:
            out["added"][str(r.path)] = r.added
        if r.backup:
            out["backups"].append(r.backup)
    if not any(r.note is None for r in results):
        # nowhere to put them — the facts stay in the waiting room instead of quietly disappearing
        out["approved"] = []
        out["note"] = "; ".join(r.note for r in results) or (
            f"none of the instruction files exists ({', '.join(str(p) for p in INSTRUCTION_PATHS)})"
            " — nothing approved automatically")
        out["powod"] = _reason(out)
        if not dry_run:
            if raw_candidates is not None and reviewed.suspicious:
                _write(CANDIDATES_PATH, reviewed.lines, _newline(raw_candidates))
            write_state(out, today)
        return out
    out["powod"] = _reason(out)
    if dry_run:
        return out
    for candidate in reviewed.approved:
        if candidate.layer == "referencyjna":
            target = write_reference(candidate, day)
            if target:
                out["references"].append(target)
        if candidate.text in out["entered"]:
            note_source(candidate, files, today)
    for p in chosen.chosen:
        if p.text in out["promoted"]:
            note_promotion(p, files, today)
    written_on = {fact_key(text): d for d, text in current}
    for text in out["expired"]:
        note_expiry(text, written_on.get(fact_key(text), ""), files, today)
    if raw_candidates is not None and reviewed.lines != raw_candidates.splitlines():
        _write(CANDIDATES_PATH, reviewed.lines, _newline(raw_candidates))
    write_state(out, today)
    return out


def _merge(into: list, items: list, key=lambda item: item) -> None:
    """Adds what is not there yet — the same fact stands in several files and is reported once."""
    seen = {key(item) for item in into}
    for item in items:
        if key(item) not in seen:
            seen.add(key(item))
            into.append(item)


def _write(path: Path, lines: list[str], newline: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(newline.join(lines) + (newline if lines else ""))


def _report(r: dict) -> None:
    if r.get("note"):
        log(r["note"])
    head = "dry run — nothing written; " if r["status"] == "dry-run" else ""
    log(f"{head}instruction files: {len(r['files'])},"
        f" into the current layer: {len(r['entered'])},"
        f" promoted to the durable layer: {len(r['promoted'])},"
        f" expired: {len(r['expired'])},"
        f" rejected: {len(r['suspicious'])},"
        f" disputed — for the user to settle: {len(r['disputed'])},"
        f" standing facts that stopped checking out: {len(r['stale'])}")
    log(f"why: {r['powod']}")  # a run that added nothing says so — silence is not an answer
    log(f"durable layer: {r['stable_chars']}/{STABLE_LIMIT} characters")
    for path in r["files"]:
        log(f"  -> {path}: {len(r['added'].get(path, []))} new")
    for fact in r["approved"]:
        log(f"  + {fact}")
    for fact in r["promoted"]:
        log(f"  ^ {fact}  (awans: padł w co najmniej {MIN_CONVERSATIONS} różnych rozmowach)")
    for fact in r["deferred"]:
        log(f"  ^? {fact}  (zasłużył na awans, czeka: limit {MAX_PROMOTIONS} na przebieg)")
    for fact in r["expired"]:
        log(f"  - {fact}  (wygasł: starszy niż {CURRENT_DAYS} dni)")
    for fact in r["own_old"]:
        log(f"  - ? {fact}  (starszy niż {CURRENT_DAYS} dni, wpisany ręcznie — decyzja użytkownika)")
    for fact, missing in r["suspicious"]:
        log(f"  ? {fact}  (nie znaleziono: {', '.join(missing)})")
    for fact, entry in r["disputed"]:
        log(f"  <> {fact}  (sporne: przeczy wpisowi „{_quote(entry)}”)")
    for fact in r["over_limit"]:
        log(f"  = {fact}  (awans wstrzymany: nie mieści się w progu {STABLE_LIMIT} znaków"
            f" warstwy stałej)")
    for fact, missing in r["stale"]:
        log(f"  ! {fact}  (nie ma: {', '.join(missing)})")
    for fact in r["healed"]:
        log(f"  ~ {fact}  — confirmed again, the warning is gone")
    for target in r["references"]:
        log(f"listing put away in: {target}")
    for backup in r["backups"]:
        log(f"copy taken before the change: {backup}")


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    dry_run = bool({"--proba", "--dry-run"} & set(argv))
    try:
        r = run(dry_run=dry_run)
    except Exception as e:  # a scheduled task must end with a readable line, not a traceback
        log(f"verifying the facts failed: {e!r}")
        return 1
    _report(r)
    return 0


if __name__ == "__main__":
    sys.exit(main())
