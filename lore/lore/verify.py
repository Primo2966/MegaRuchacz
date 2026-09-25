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

One thing stops a fact on the way in, and says so out loud: a claim that can be checked and does
NOT hold (a path that is not there) — rejected, stays flagged in the waiting room.

A claim that CONTRADICTS something already written down no longer waits for the user either (by
2026-09-24 that queue was the second pile nobody answered): the NEWER VERSION WINS. Over an entry
the automaton wrote itself it wins at once; over a PINNED entry (anything the automaton did not
write — the rules from before it existed and whatever the user had written down) only once the new
version has been heard in two different conversations — a pinned entry is often a trap or a ban
("PUŁAPKA w SQP", "zakaz next build"), and one misread sentence must not swap it out. Until then
the new version waits in the current layer with a note of what it contradicts. The loser is never
deleted: it goes to wiedza/historia-zmian.md.

The durable layer refreshes itself as well — otherwise nothing ever leaves it and, at the ceiling,
it blocks everything new. An entry the automaton put there and nobody confirmed for SLEEP_DAYS
falls asleep: it moves to wiedza/uspione.md (the reference layer, not sent with the sessions) and
wakes up, back into the durable layer, the first time it is heard again. Pinned entries never fall
asleep — their whole point is that they work without being mentioned.

Every such change (replacement, falling asleep, waking up, promotion) gets a short id and a copy of
every file it touched, and `--cofnij <id|RRRR-MM-DD>` takes it back — see undo(). What changed
today is written, id by id, into the summary of the run (.wiedza-stan.txt, keys "meldunek*").

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
Undo: uv --directory C:\\dev\\claude-worker\\lore run python -m lore.verify --cofnij <id|RRRR-MM-DD>
List: uv --directory C:\\dev\\claude-worker\\lore run python -m lore.verify --zmiany [RRRR-MM-DD]
"""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from .db import CLAUDE_HOME, log
from .facts import (DORMANT_NAME, PENDING_NOTE, SESSIONS_FIELD, SIGHTED, SIGHTED_AGAIN,
                    SOURCES_HEADER, SOURCES_NAME, dormant_entry, normalize)

KNOWLEDGE_DIR = CLAUDE_HOME / "wiedza"
CANDIDATES_PATH = KNOWLEDGE_DIR / "kandydaci.md"
BACKUP_DIR = KNOWLEDGE_DIR / "kopie"
STATE_NAME = ".wiedza-stan.txt"  # 'klucz: wartosc', the same shape as .koszt-cyklu.txt
HISTORY_NAME = "historia-zmian.md"  # every automatic change, for a human to read — and the losers
JOURNAL_NAME = ".zmiany.jsonl"  # the same changes for undo(): the ops and the state after each

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
# How long an entry the automaton put into the durable layer stays there without being heard again.
# 90 days is the user's decision (2026-09-24): a fact about his work comes up at least once a
# quarter, and one that did not is paying its place in every session for nothing. It is not lost —
# it moves to wiedza/uspione.md and comes back the first time it is heard. Pinned entries (see
# Trail.is_auto) never fall asleep, whatever this number says.
SLEEP_DAYS = 90
# The summary of a run shows the day's changes one line each, at most this many; the head line gives
# the totals and says where the rest is, so what did not fit is announced, not cut off quietly.
REPORT_LINES = 5
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


# The user works on two machines, and one fact may name the path on each: 'na biurowej w
# `C:\\dev\\x`, na domowej w `D:\\y`'. The home one never exists on the office disk, and flagging
# it was a false alarm (2026-09-25). Only the path the fact ties to the other machine is let go —
# a missing path with no such tie is still flagged.
_OTHER_MACHINE = re.compile(r"\bdomow\w*|\bw\s+domu\b|\bprzem\b", re.IGNORECASE)
# 'katalog domowy' is a home DIRECTORY, not the home machine
_HOME_DIRECTORY = re.compile(r"\bkatalog\w*\s+domow\w*", re.IGNORECASE)
_CLAUSE_END = re.compile(r";|\.\s")


def _names_other_machine(text: str) -> bool:
    return bool(_OTHER_MACHINE.search(_HOME_DIRECTORY.sub(" ", text)))


def _lead_ins(text: str, paths: list[str]) -> dict[str, str]:
    """The words right before each path: from the previous path (or clause end) up to this one."""
    spots = sorted((text.find(p), p) for p in paths)
    out, last = {}, 0
    for start, p in spots:
        if start < 0:
            out[p] = ""  # not found verbatim (a bare path with odd spacing) — no tie assumed
            continue
        lead = text[last:start]
        cut = [m.end() for m in _CLAUSE_END.finditer(lead)]
        out[p] = lead[cut[-1]:] if cut else lead
        last = start + len(p)
    return out


def check_paths(text: str, exists) -> list[Check]:
    if on_another_machine(text):
        return []
    paths = paths_in(text)
    checks = [Check(p, exists(p)) for p in paths]
    if not _names_other_machine(text):
        return checks
    lead = _lead_ins(text, paths)
    # a path introduced as the other machine's is not checkable here
    checks = [c for c in checks if c.ok or not _names_other_machine(lead[c.claim])]
    # the fact names two machines and the one here holds: the rest is the other machine's
    if any(c.ok for c in checks):
        checks = [c for c in checks if c.ok]
    return checks


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

# Settled by the rule "the newer version wins" (see the module docstring) — never by deleting the
# loser without a word: it goes to the history with the id of the change, and the change can be
# taken back. A pinned entry needs the new version from two different conversations first.
#
# The detection is deliberately narrow — the same sentence with ONE detail changed:
#   "Postgres stoi w C:\\dev\\pgsql"  vs  "Postgres stoi w D:\\pgsql"      (a value swapped)
#   "Redis nie jest potrzebny"        vs  "Redis jest potrzebny"           (a negation flipped)
# Narrow, because a false clash would now swap out a healthy entry. The price is stated plainly:
# a contradiction phrased in other words is NOT caught and the new fact enters on its own, next to
# the old one. That is a known hole, not a solved problem — see the report of the run, which says
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


def clashes(text: str, standing: list) -> list:
    """Every standing entry (Entry) the fact contradicts — all of them, not the first one only:
    whether the entry is pinned or the automaton's decides what happens, so all of them count."""
    subject, claim = skeleton(text)
    if len(subject.split()) < MIN_SKELETON_WORDS:
        return []
    out = []
    for entry in standing:
        other_subject, other_claim = skeleton(entry.text)
        if other_subject == subject and other_claim != claim:
            out.append(entry)
    return out


QUOTE_LIMIT = 120  # a quote is a pointer to the entry, not a copy of it
# The note a waiting entry carries in the current layer — that layer is sent with every session,
# so the quote there is shorter than in the history.
PENDING_QUOTE_LIMIT = 70


def _quote(entry: str, limit: int = QUOTE_LIMIT) -> str:
    short = " ".join(entry.split())
    return short if len(short) <= limit else short[:limit].rstrip() + "…"


# ---------------------------------------------------------------- the waiting room

@dataclass
class Candidate:
    """One entry of the waiting room, read back with the layer label the harvest gave it."""
    text: str
    layer: str = "stala"
    detail: str = ""  # the subsection for "stala", the file name for "referencyjna"
    day: str = ""  # the day it was harvested — the trail back to the conversation
    pointer: str = ""  # "referencyjna" only: the line that stands in place of the whole listing
    against: str = ""  # it contradicts this pinned entry and waits for a second conversation

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
        return current_entry(self.day or today, self.shown, self.against)


def current_entry(day: str, text: str, against: str = "") -> str:
    """The text of a "### Bieżące" entry: its date, the fact and — while it waits to replace a
    pinned entry — the note of what it contradicts (facts.PENDING_NOTE reads it back)."""
    note = f" (przeczy: „{_quote(against, PENDING_QUOTE_LIMIT)}”)" if against else ""
    return f"[{day}] {text}{note}"


@dataclass
class Reviewed:
    lines: list[str] = field(default_factory=list)  # the new content of the waiting room
    approved: list[Candidate] = field(default_factory=list)  # new entries of the current layer
    suspicious: list[tuple[str, list[str]]] = field(default_factory=list)  # a claim that does not hold
    # always empty since "the newer version wins" — nothing waits for the user any more; the key
    # stays so that what reads the summary does not break
    disputed: list[tuple[str, str]] = field(default_factory=list)
    replacing: list["Replacement"] = field(default_factory=list)  # a newer version, taking a place
    pending: list[Candidate] = field(default_factory=list)  # among approved: waiting on a pinned one
    waiting: int = 0  # still in the waiting room: the rejected ones


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


def review_candidates(lines: list[str], exists=None, standing: list | None = None,
                      trail: "Trail | None" = None) -> Reviewed:
    """Empties the waiting room: everything that is not rejected goes.

    `standing` are the entries already written down (Entry, or a bare sentence — read as pinned);
    they decide the contradictions, and `trail` says from how many conversations the new version
    came. There is no ceiling to check here: the ceiling of the durable layer is checked where
    something is promoted into it or replaces something there.
    """
    exists = exists or path_exists
    trail = trail or Trail()
    standing = [e if isinstance(e, Entry) else Entry(e, False, "", []) for e in (standing or [])]
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
        pending = candidate  # its "odsyłacz:" line, if any, comes next and leaves with it
        # a listing stands in the file as its pointer, not as itself — there is no entry of its own
        # to take the place of, so it goes in as it always did
        found = clashes(candidate.text, standing) if candidate.layer != "referencyjna" else []
        _settle(candidate, found, standing, trail, out)
    return out


def _settle(candidate: Candidate, found: list, standing: list, trail: "Trail",
            out: Reviewed) -> None:
    """The newer version wins — at once over the automaton's entry, over a pinned one only when it
    was heard in MIN_CONVERSATIONS different conversations. `standing` is kept up to date, so that
    two candidates of one run settle between themselves the same way (the later one is newer)."""
    pinned = [e for e in found if not e.auto]
    auto = [e for e in found if e.auto]
    heard = conversations(trail.evidence(fact_key(candidate.text)))
    if pinned and heard < MIN_CONVERSATIONS:
        candidate.against = pinned[0].text
        waiting = Entry(candidate.text, True, CURRENT_SUBSECTION, [], candidate.day, pinned[0].text,
                        auto=True)
        out.pending.append(candidate)
        mine = [e for e in auto if e.current]  # an older waiting version of it — the newer one wins
        if mine:
            out.replacing.append(Replacement(candidate.text, mine[0], mine[1:], candidate.day,
                                             candidate.against, candidate, heard))
            _swap(standing, mine, waiting)
        else:
            out.approved.append(candidate)
            standing.append(waiting)
        return
    if not found:
        out.approved.append(candidate)
        standing.append(Entry(candidate.text, True, CURRENT_SUBSECTION, [], candidate.day,
                              auto=True))
        return
    # the durable version first: that is the one every session reads
    target = pinned[0] if pinned else sorted(auto, key=lambda e: e.current)[0]
    rest = [e for e in auto if e is not target]  # another pinned one is the user's — left alone
    out.replacing.append(Replacement(candidate.text, target, rest, candidate.day, "", candidate,
                                     heard))
    _swap(standing, [target] + rest, Entry(candidate.text, target.current, target.heading, [],
                                           candidate.day, auto=True))


def _swap(standing: list, gone: list, new: "Entry") -> None:
    standing[:] = [e for e in standing if all(e is not g for g in gone)]
    standing.append(new)


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
        return PENDING_NOTE.sub("", _UNCONFIRMED.sub("", joined)).strip().lstrip("-*").strip()

    @property
    def against(self) -> str:
        """The quote of the pinned entry a waiting entry contradicts; '' for every other entry."""
        m = PENDING_NOTE.search(_UNCONFIRMED.sub("", " ".join(p.strip() for p in self.lines)))
        return m.group(0).strip()[len("(przeczy:"):-1].strip().strip("„”") if m else ""


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
    return insert_entry(body, [f"- {fact}"], heading)


def insert_entry(body: list[str], entry: list[str], heading: str) -> list[str]:
    """insert_fact for an entry already written out — possibly wrapped over several lines."""
    idx = _heading_index(body, heading)
    if idx is None:
        tail = body + ([] if body and not body[-1].strip() else [""])
        return tail + [heading, ""] + entry + [""]
    end = idx + 1
    while end < len(body) and not body[end].strip().startswith(("### ", "## ")):
        end += 1
    kept = [line for line in body[idx + 1:end] if line.strip() != EMPTY_MARKER]
    while kept and not kept[-1].strip():
        kept.pop()
    if not kept or kept[0].strip():
        kept.insert(0, "")
    return body[:idx + 1] + kept + list(entry) + [""] + body[end:]


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
    """One line of a file stripped down to the fact itself — no bullet, no date, no warning, no
    note of what it contradicts."""
    bare = PENDING_NOTE.sub("", _UNCONFIRMED.sub("", line))
    return _LEADING_DAY.sub("", bare.strip().lstrip("-*").strip())


def facts_in(lines: list[str]) -> set[str]:
    """What this file already says, normalized — a fact standing here is not written down twice.

    The date of a "biezaca" entry is taken off first: left in, it would make the same sentence
    look new every single day and the current layer would fill up with copies of itself.
    """
    known = {normalize(_entry_text(line)) for line in lines}
    known.discard("")
    return known


@dataclass
class FileResult:
    """What one pass did to one instruction file."""
    path: Path
    stale: list[tuple[str, list[str]]] = field(default_factory=list)
    healed: list[str] = field(default_factory=list)
    added: list[str] = field(default_factory=list)  # new facts, written into the current layer
    expired: list[str] = field(default_factory=list)  # taken out of the current layer by their age
    changed: bool = False
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
# ...and the ones of the refreshing durable layer and of "the newer version wins"
SLEPT, WOKEN = "uśpiony", "obudzony"
REPLACED, REPLACED_BY = "zastąpiony", "wpisany w miejsce"  # the loser and the winner of a clash
UNDONE = "cofnięty"
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
    """What wiedza/zrodla.md knows, read back for the decisions: promote, let expire, put to sleep,
    wake up — and which entries are the automaton's at all."""
    sightings: dict = field(default_factory=dict)  # fact key -> [Sighting], oldest first
    written: set = field(default_factory=set)  # keys of entries the automaton put into "Bieżące"
    pointers: dict = field(default_factory=dict)  # key of a pointer line -> key of its listing
    # keys of entries the automaton put into the DURABLE layer: promoted, woken up, the winner of
    # a clash — and the ones written straight there in the week that was allowed (2026-09-17..24)
    auto_durable: set = field(default_factory=set)
    confirmed: dict = field(default_factory=dict)  # key -> the latest day it was put in or kept
    undone: dict = field(default_factory=dict)  # key -> the latest day a change of it was undone

    def evidence(self, key) -> list[Sighting]:
        """The sightings behind an entry — for a reference pointer, those of its listing."""
        return self.sightings.get(self.pointers.get(key, key), [])

    def is_auto(self, entry: "Entry") -> bool:
        """Did the automaton write this entry? What it did not write is PINNED: the rules from before
        it existed and whatever the user had written down himself. The trail is the only proof —
        an entry with no event behind it counts as the user's, which is the safe side: a pinned
        entry never falls asleep and is replaced only on the word of two conversations."""
        return entry.key in (self.written if entry.current else self.auto_durable)

    def last_confirmed(self, key) -> str | None:
        """The last day the fact was heard in a conversation — or put into the durable layer, or
        kept there by an undone sleep, whichever is later."""
        days = [s.day for s in self.evidence(key)]
        if key in self.confirmed:
            days.append(self.confirmed[key])
        return max(days) if days else None

    def blocked(self, key) -> bool:
        """A change the user took back is not redone by the next run on the same evidence: it waits
        for the fact to be heard again, after the day of the undo."""
        day = self.undone.get(key)
        return day is not None and not any(s.day > day for s in self.evidence(key))

    def confirm(self, key, day: str) -> None:
        self.confirmed[key] = max(day, self.confirmed.get(key, day))


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
        day, event, detail = parts[0].strip(), parts[1].strip(), parts[2].strip()
        if event in (SIGHTED, SIGHTED_AGAIN):
            if len(parts) == 6 and parts[4].startswith(SESSIONS_FIELD):
                sessions, text = _sessions(parts[4]), parts[5]
            else:  # the format from before the full list of sessions
                sessions, text = _old_sessions(parts[3]), " | ".join(parts[4:])
            out.sightings.setdefault(fact_key(text), []).append(
                Sighting(day, detail, sessions, text.strip()))
            continue
        key = fact_key(" | ".join(parts[4:]))
        if event == WRITTEN and detail.startswith("biezaca"):
            out.written.add(key)
            pointer = _POINTER_NOTE.search(parts[3])
            if pointer:
                out.written.add(fact_key(pointer.group(1)))
                out.pointers[fact_key(pointer.group(1))] = key
        elif event == WRITTEN and detail.startswith("stala"):
            # the week the automaton wrote straight into the durable layer — its entries, too
            out.auto_durable.add(key)
            out.confirm(key, day)
        elif event in (PROMOTED, WOKEN):
            out.auto_durable.add(key)
            out.confirm(key, day)
        elif event == REPLACED_BY:
            if detail.startswith("biezaca"):
                out.written.add(key)
            else:
                out.auto_durable.add(key)
                out.confirm(key, day)
        elif event == UNDONE:
            if detail.startswith(CHANGE_KINDS["U"]):
                out.confirm(key, day)  # the user wants it back — that counts as hearing it again
            else:
                out.undone[key] = max(day, out.undone.get(key, day))
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
    dormant: "Dormant | None" = None  # not a promotion but a fact waking up out of uspione.md

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
                      room: int | None, wakes: list[Promotion] | tuple = ()) -> Promotions:
    """Which entries of the current layer move to the durable one in this run.

    `current` — the sentences of the current layer, this run's newcomers included; `durable` — the
    keys already standing in the durable layer (nothing there is moved or doubled — this is not
    a migration backwards); `room` — characters left under the ceiling, None when not measured;
    `wakes` — dormant facts heard again: they come back under the same limit and the same ceiling,
    and before the promotions, since they have been in the durable layer once already.

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
        if trail.blocked(key):
            continue  # the user took this promotion back — it waits to be heard again
        earned.append(Promotion(text, promotion_heading(text, sightings[-1].label), heard,
                                min(s.day for s in sightings)))
    earned.sort(key=lambda p: (-p.conversations, p.first_seen))  # the most repeated first
    earned = [w for w in wakes if w.key not in durable] + [p for p in earned
                                                           if p.key not in {w.key for w in wakes}]
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


def settle_file(path: Path, lines: list[str], approved: list[Candidate], exists, today: str,
                leaving: set | frozenset = frozenset()) -> tuple[FileResult, list[str]]:
    """The part of a run that has no id to take back: audits what stands in one file, lets the
    expired entries out of the current layer and the approved facts it does not know yet in, with
    their date — never anywhere else. Returns the new lines; writing is the caller's business.
    The changes that DO get an id (see Change) are applied on top of this, one by one.
    """
    bounds = section_bounds(lines)
    if bounds is None:
        return FileResult(path, note=f"no '{KNOWLEDGE_HEADING}' section in {path}"
                                     " — nothing approved automatically"), lines
    start, end = bounds
    audited = audit_rules(lines[start:end], exists, today)
    out = FileResult(path, stale=audited.stale, healed=audited.healed)
    body, out.expired = _drop_current(audited.body, set(leaving))
    known = facts_in(lines[:start] + body + lines[end:])
    for candidate in approved:
        key = normalize(candidate.shown)
        if not key or key in known:
            continue  # already written down here, possibly in other words than the waiting room used
        known.add(key)
        body = insert_fact(body, candidate.entry(today), CURRENT_SUBSECTION)
        out.added.append(candidate.text)
    out.changed = body != lines[start:end]
    # only the body of the section is swapped — the lines around it are the very same objects
    return out, lines[:start] + body + lines[end:]


# ---------------------------------------------------------------- pinned and the automaton's

@dataclass(eq=False)
class Entry:
    """One entry of "## Co wiem" — where it stands and whose it is."""
    text: str  # the fact alone: no bullet, no date, no mark, no note of what it contradicts
    current: bool  # it stands in "### Bieżące"
    heading: str  # the subsection it stands under; '' above the first one
    lines: list[str]  # as written in the file
    day: str = ""  # the date of a current entry
    against: str = ""  # a waiting entry: the (quoted) pinned entry it is to replace
    auto: bool = False  # the automaton wrote it; everything else is pinned — see Trail.is_auto

    @property
    def key(self) -> tuple:
        return fact_key(self.text)


def _headings(body: list[str]) -> list[str]:
    """For every line of the body, the subsection heading it stands under ('' above the first)."""
    out, heading = [], ""
    for line in body:
        if SUBHEADING_RE.match(line.strip()):
            heading = line.strip()
        out.append(heading)
    return out


def entries(lines: list[str]) -> list[Entry]:
    """Every entry of the "## Co wiem" section of a file, in the order they stand."""
    bounds = section_bounds(lines)
    if bounds is None:
        return []
    body = lines[bounds[0]:bounds[1]]
    heads = _headings(body)
    out = []
    for b in bullets(body):
        heading = heads[b.start]
        current = bool(CURRENT_HEADING_RE.match(heading))
        day = _DAY.match(b.text)
        text = _LEADING_DAY.sub("", b.text)
        if text:
            out.append(Entry(text, current, heading, list(b.lines), day.group(1) if day else "",
                             b.against if current else ""))
    return out


def _find(lines: list[str], key, current: bool) -> tuple[int, int, str] | None:
    """(start, end, heading) of the entry with this key in the given layer; absolute line numbers."""
    bounds = section_bounds(lines)
    if bounds is None:
        return None
    body = lines[bounds[0]:bounds[1]]
    heads = _headings(body)
    for b in bullets(body):
        in_current = bool(CURRENT_HEADING_RE.match(heads[b.start]))
        if in_current == current and fact_key(_LEADING_DAY.sub("", b.text)) == key:
            return bounds[0] + b.start, bounds[0] + b.end, heads[b.start]
    return None


def _entry_key(entry: list[str]) -> tuple:
    return fact_key(_LEADING_DAY.sub("", Bullet(0, len(entry), entry).text))


# ---------------------------------------------------------------- the dormant facts

DORMANT_HEADER = """# Uśpione fakty

Wpisy, które automat kiedyś dopisał do trwałej wiedzy, a potem przez {days} dni nikt ich nie
potwierdził w rozmowie. Tu nie kosztują nic — ten plik nie jest doklejany do rozmów. Fakt, który
padnie znowu, wraca do trwałej wiedzy sam. Wpisy przypięte (napisane ręcznie) nigdy tu nie trafiają.

Jedna linia na fakt: `data uśpienia | podsekcja | identyfikator zmiany | treść`.
Cofnięcie uśpienia: `python -m lore.verify --cofnij <identyfikator>`.
"""


@dataclass
class Dormant:
    slept: str  # the day it fell asleep
    heading: str  # its subsection, without the hashes
    change: str  # the id of the change that put it here
    text: str

    @property
    def line(self) -> str:
        return f"- {self.slept} | {self.heading} | {self.change} | {self.text}"

    @property
    def key(self) -> tuple:
        return fact_key(self.text)


def read_dormant(lines: list[str]) -> list[Dormant]:
    return [Dormant(*parsed) for parsed in map(dormant_entry, lines) if parsed]


# ---------------------------------------------------------------- the files of one run

def _render(lines: list[str], newline: str) -> str:
    return newline.join(lines) + (newline if lines else "")


def _sha(text: str | None) -> str | None:
    return None if text is None else hashlib.sha256(text.encode("utf-8")).hexdigest()


class Workspace:
    """Every file one run may change, held in memory until the end. That is what lets each change
    that gets an id be recorded with the exact state before and after it — and be taken back."""

    def __init__(self) -> None:
        self.lines: dict[Path, list[str]] = {}
        self.newline: dict[Path, str] = {}
        self.existed: dict[Path, bool] = {}

    def load(self, path: Path) -> None:
        raw = _read(path)
        self.lines[path] = (raw or "").splitlines()
        self.newline[path] = _newline(raw or "")
        self.existed[path] = raw is not None

    def text(self, path: Path) -> str | None:
        """The file as it would be written now; None for a file that is not there and stays so."""
        lines = self.lines[path]
        if not lines and not self.existed[path]:
            return None
        return _render(lines, self.newline[path])


# One change is a list of operations on the files, each of them with its exact inverse — that is
# what undo() falls back on when a file changed since and its copy can no longer be put back whole.
#   wstaw  (plik, sekcja, linie)            an entry added at the end of a subsection
#   wyjmij (plik, biezaca, sekcja, linie)   an entry taken out (found by its key, not its bytes)
#   podmien(plik, biezaca, stare, nowe)     an entry replaced in its place
#   uspij / zbudz (plik, linia)             a line added to / taken out of wiedza/uspione.md

def _inverse(op: dict) -> dict:
    kind = op["op"]
    if kind == "wstaw":
        return {"op": "wyjmij", "plik": op["plik"], "sekcja": op["sekcja"], "linie": op["linie"],
                "biezaca": bool(CURRENT_HEADING_RE.match(op["sekcja"]))}
    if kind == "wyjmij":
        return {"op": "wstaw", "plik": op["plik"], "sekcja": op["sekcja"] or DEFAULT_SUBSECTION,
                "linie": op["linie"]}
    if kind == "podmien":
        return {**op, "stare": op["nowe"], "nowe": op["stare"]}
    return {**op, "op": "zbudz" if kind == "uspij" else "uspij"}


def _apply(ws: Workspace, op: dict) -> bool:
    """One operation on the files in memory; False when there was nothing to apply it to."""
    path = Path(op["plik"])
    lines = ws.lines[path]
    kind = op["op"]
    if kind == "uspij":
        if not any(line.strip() for line in lines):
            lines = DORMANT_HEADER.format(days=SLEEP_DAYS).splitlines()
        ws.lines[path] = lines + [op["linia"]]
        return True
    if kind == "zbudz":
        wanted = dormant_entry(op["linia"])
        for i, line in enumerate(lines):
            here = dormant_entry(line)
            if line == op["linia"] or (here and wanted and fact_key(here[3]) == fact_key(wanted[3])):
                ws.lines[path] = lines[:i] + lines[i + 1:]
                return True
        return False
    if kind == "wstaw":
        bounds = section_bounds(lines)
        if bounds is None:
            return False
        body = insert_entry(lines[bounds[0]:bounds[1]], op["linie"], op["sekcja"])
        ws.lines[path] = lines[:bounds[0]] + body + lines[bounds[1]:]
        return True
    old = op["linie"] if kind == "wyjmij" else op["stare"]
    found = _find(lines, _entry_key(old), op["biezaca"])
    if found is None:
        return False
    start, end, heading = found
    if kind == "podmien":
        ws.lines[path] = lines[:start] + list(op["nowe"]) + lines[end:]
        return True
    ws.lines[path] = _refill(lines[:start] + lines[end:], heading)
    return True


def _refill(lines: list[str], heading: str) -> list[str]:
    """A subsection left without a single entry gets its placeholder back — as _drop_current does."""
    bounds = section_bounds(lines)
    if bounds is None or not heading:
        return lines
    body = lines[bounds[0]:bounds[1]]
    idx = _heading_index(body, heading)
    if idx is None:
        return lines
    end = idx + 1
    while end < len(body) and not SUBHEADING_RE.match(body[end].strip()):
        end += 1
    part = body[idx:end]
    if bullets(part[1:]) or any(line.strip() == EMPTY_MARKER for line in part):
        return lines
    while len(part) > 1 and not part[-1].strip():
        part.pop()
    part += ["", EMPTY_MARKER, ""]
    return lines[:bounds[0]] + body[:idx] + part + body[end:] + lines[bounds[1]:]


CHANGE_KINDS = {"A": "awans", "U": "uśpienie", "O": "obudzenie", "Z": "zastąpienie"}


@dataclass
class Change:
    """One automatic change the user can take back by its id."""
    kind: str  # a key of CHANGE_KINDS
    subject: str  # the fact it is about: promoted, put to sleep, woken, or the winner of a clash
    old: str = ""  # a replacement: the fact that lost
    heading: str = ""
    note: str = ""  # a few words for the history
    id: str = ""
    ops: list = field(default_factory=list)
    before: dict = field(default_factory=dict)  # path -> the whole text before (None: no file)
    after: dict = field(default_factory=dict)  # path -> sha256 of the whole text after

    def record(self, day: str) -> dict:
        return {"id": self.id, "dzien": day, "rodzaj": CHANGE_KINDS[self.kind],
                "przedmiot": self.subject, "stare": self.old, "sekcja": self.heading,
                "opis": self.note, "ops": self.ops,
                "pliki": {p: {"kopia": None, "po": sha} for p, sha in self.after.items()}}


class Changes:
    """The changes of one run, applied to the files in memory one after another."""

    def __init__(self, ws: Workspace, today: str, taken: int) -> None:
        self.ws, self.today, self.done = ws, today, []
        self.count = taken  # the ids of the day already given out — by earlier runs of the day

    def commit(self, change: Change, ops: list[dict]) -> bool:
        ops = [op for op in ops if op]
        if not ops:
            return False
        self.count += 1
        change.id = f"{change.kind}-{self.today[2:4]}{self.today[5:7]}{self.today[8:10]}-{self.count}"
        touched = list(dict.fromkeys(op["plik"] for op in ops))
        change.before = {p: self.ws.text(Path(p)) for p in touched}
        applied = []
        for op in ops:
            if op["op"] == "uspij":  # the dormant line names the change that put it there
                op = {**op, "linia": op["linia"].replace(" | {id} | ", f" | {change.id} | ", 1)}
            if _apply(self.ws, op):
                applied.append(op)
        change.ops = applied
        change.after = {p: _sha(self.ws.text(Path(p))) for p in touched}
        self.done.append(change)
        return True


def _layer_ops(ws: Workspace, files: list[Path], key, current: bool) -> list[dict]:
    """Taking one entry out of one layer of every file it stands in."""
    ops = []
    for path in files:
        found = _find(ws.lines[path], key, current)
        if found:
            start, end, heading = found
            ops.append({"op": "wyjmij", "plik": str(path), "biezaca": current, "sekcja": heading,
                        "linie": ws.lines[path][start:end]})
    return ops


def sleep_ops(ws: Workspace, files: list[Path], entry: Entry, dormant_path: Path,
              today: str) -> list[dict]:
    ops = _layer_ops(ws, files, entry.key, False)
    if ops:
        heading = (entry.heading or DEFAULT_SUBSECTION).lstrip("#").strip()
        ops.append({"op": "uspij", "plik": str(dormant_path),
                    "linia": Dormant(today, heading, "{id}", entry.text).line})
    return ops


def durable_ops(ws: Workspace, files: list[Path], text: str, heading: str) -> list[dict]:
    """A fact moving into the durable layer: out of the current one wherever it waits there, in
    under its heading wherever the durable layer does not have it yet."""
    key = fact_key(text)
    ops = _layer_ops(ws, files, key, True)
    for path in files:
        if section_bounds(ws.lines[path]) is not None and _find(ws.lines[path], key, False) is None:
            ops.append({"op": "wstaw", "plik": str(path), "sekcja": heading,
                        "linie": [f"- {text}"]})
    return ops


@dataclass
class Replacement:
    """A newer version of a fact taking the place of an older one — see _settle."""
    new: str
    target: Entry
    extra: list  # other versions of the same thing the automaton wrote — they go as well
    day: str  # the date the new version carries when it lands in the current layer
    against: str = ""  # it still waits for a pinned entry: the note stays with it
    candidate: Candidate | None = None  # it came out of the waiting room this run
    heard: int = 0  # in how many different conversations the new version was heard


def replace_ops(ws: Workspace, files: list[Path], r: Replacement, today: str) -> list[dict]:
    t = r.target
    new = [f"- {current_entry(r.day or today, r.new, r.against)}"] if t.current else [f"- {r.new}"]
    new_key = fact_key(r.new)
    ops = []
    for path in files:
        lines = ws.lines[path]
        if section_bounds(lines) is None:
            continue
        found = _find(lines, t.key, t.current)
        if found:
            ops.append({"op": "podmien", "plik": str(path), "biezaca": t.current,
                        "stare": lines[found[0]:found[1]], "nowe": new})
        elif _find(lines, new_key, t.current) is None:
            # the old version was never in this file — the new one goes in anyway, as a new fact
            # would, so that the files of both tools say the same
            ops.append({"op": "wstaw", "plik": str(path), "linie": new,
                        "sekcja": CURRENT_SUBSECTION if t.current
                        else (t.heading or DEFAULT_SUBSECTION)})
    for e in r.extra:
        if e.key != t.key or e.current != t.current:
            ops += _layer_ops(ws, files, e.key, e.current)
    return ops


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


def note_expiry(text: str, written: str, files: list[Path], day: str) -> None:
    _note(f"- {day} | {EXPIRED} | biezaca -> {_where(files)} | wpis z {written or '?'},"
          f" starszy niz {CURRENT_DAYS} dni | {text}\n", text)


def _flat(text: str) -> str:
    """A fact quoted inside a trail line — the ' | ' of the format must not appear in it."""
    return _quote(text).replace("|", "/")


def note_change(c: Change, day: str) -> None:
    """The trail line(s) of one change — read back by read_trail: whose entries are the automaton's,
    when a fact was last put in, what the user took back."""
    files = [Path(p) for p in c.after if Path(p).name != DORMANT_NAME]
    where = f"stala: {c.heading.lstrip('# ').strip()} -> {_where(files)}"
    if c.kind == "A":
        line = f"- {day} | {PROMOTED} | {where} | {c.note}; zmiana {c.id} | {c.subject}\n"
    elif c.kind == "O":
        line = f"- {day} | {WOKEN} | {where} | zmiana {c.id}; {c.note} | {c.subject}\n"
    elif c.kind == "U":
        line = f"- {day} | {SLEPT} | {where} | zmiana {c.id}; {c.note} | {c.subject}\n"
    else:
        layer = f"biezaca -> {_where(files)}" if c.heading == CURRENT_SUBSECTION else where
        line = (f"- {day} | {REPLACED} | {layer} | zmiana {c.id}; przez: {_flat(c.subject)}"
                f" | {c.old}\n"
                f"- {day} | {REPLACED_BY} | {layer} | zmiana {c.id}; zamiast: {_flat(c.old)}"
                f" | {c.subject}\n")
    _note(line, c.subject)


# ---------------------------------------------------------------- the history and the way back

HISTORY_HEADER = """# Historia zmian w wiedzy

Każda zmiana, którą automat zrobił sam: awans do wiedzy stałej, uśpienie, obudzenie, zastąpienie
starszej wersji nowszą. Nic stąd nie jest doklejane do rozmów. Stara wersja faktu nie ginie — stoi
tutaj. Każdą zmianę cofa jedno polecenie:

    uv --directory <repo>\\lore run python -m lore.verify --cofnij <identyfikator albo RRRR-MM-DD>

"""


def history_line(c: Change, day: str) -> str:
    if c.kind == "Z":
        return f"- [{c.id}] {c.old} — zastąpione {day} przez: {c.subject}"
    if c.kind == "U":
        return f"- [{c.id}] {c.subject} — uśpione {day} ({c.note}), leży w wiedza/{DORMANT_NAME}"
    heading = c.heading.lstrip("# ").strip()
    if c.kind == "O":
        return f"- [{c.id}] {c.subject} — obudzone {day}, wróciło do stałej ({heading}): {c.note}"
    return f"- [{c.id}] {c.subject} — awansowane {day} do stałej ({heading}), {c.note}"


def _append(name: str, header: str, lines: list[str]) -> None:
    """One more piece of an append-only file — a failure is logged, never swallowed."""
    if not lines:
        return
    try:
        KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
        path = KNOWLEDGE_DIR / name
        first_time = not path.exists()
        with open(path, "a", encoding="utf-8", newline="\n") as f:
            if first_time and header:
                f.write(header)
            f.write("".join(line + "\n" for line in lines))
    except OSError as e:
        log(f"{len(lines)} line(s) were not written to {name}: {e}")


def read_journal() -> list[dict]:
    """The journal of the changes: records of changes and records of undoing them, oldest first.
    A line that does not parse is reported, not skipped quietly — it is a change nobody can undo."""
    raw = _read(KNOWLEDGE_DIR / JOURNAL_NAME)
    out = []
    for n, line in enumerate((raw or "").splitlines(), 1):
        if not line.strip():
            continue
        try:
            out.append(json.loads(line))
        except ValueError as e:
            log(f"{JOURNAL_NAME}, line {n} does not parse ({e}) — that change cannot be undone")
    return out


def _undone(records: list[dict]) -> set[str]:
    return {r["cofnieto"] for r in records if "cofnieto" in r}


def save_changes(changes: list[Change], day: str) -> None:
    """Persists the changes of a run: a copy of every file each of them touched (the state just
    before it), the journal record, the history line and the trail line. The copies go first —
    a change recorded without its copy could only be undone by content, never exactly."""
    if not changes:
        return
    records = []
    for c in changes:
        rec = c.record(day)
        for path, text in c.before.items():
            rec["pliki"][path]["bylo"] = text is not None
            if text is None:
                continue  # the file was not there — undoing means removing it again
            copy = BACKUP_DIR / "zmiany" / f"{c.id}-{Path(path).name}"
            try:
                copy.parent.mkdir(parents=True, exist_ok=True)
                with open(copy, "w", encoding="utf-8", newline="") as f:
                    f.write(text)
                rec["pliki"][path]["kopia"] = str(copy)
            except OSError as e:
                log(f"no copy of {path} before {c.id}: {e} — it can be undone by content only")
        records.append(json.dumps(rec, ensure_ascii=False))
    _append(JOURNAL_NAME, "", records)
    _append(HISTORY_NAME, HISTORY_HEADER, [history_line(c, day) for c in changes])
    for c in changes:
        note_change(c, day)


REPORT_QUOTE = 60
_REPORT_VERBS = {"Z": "zmienilem", "U": "uspilem", "O": "obudzilem", "A": "awansowalem"}


def report_lines(records: list[dict], day: str) -> list[str]:
    """The day's changes for a human: a head line with the totals, then one line per change with
    the id that takes it back. No changes is one line saying so — never an empty report."""
    undone = _undone(records)
    done = [r for r in records if "id" in r and r.get("dzien") == day and r["id"] not in undone]
    if not done:
        return ["bez zmian"]
    count = {kind: sum(r["id"].startswith(kind + "-") for r in done) for kind in _REPORT_VERBS}
    head = (f"zmienilem {count['Z']}, uspilem {count['U']}, obudzilem {count['O']},"
            f" awansowalem {count['A']} - cofniecie: python -m lore.verify --cofnij <id>"
            f" (albo --cofnij {day})")
    if len(done) > REPORT_LINES:
        head = (f"UWAGA: {len(done)} zmian, pokazuje {REPORT_LINES} - pelna lista w"
                f" wiedza/{HISTORY_NAME}; " + head)
    lines = [head]
    for r in done[:REPORT_LINES]:
        kind = r["id"][0]
        what = f"„{_quote(r['przedmiot'], REPORT_QUOTE)}”"
        if kind == "Z":
            what = f"„{_quote(r['stare'], REPORT_QUOTE)}” -> {what}"
        lines.append(f"{r['id']} {_REPORT_VERBS.get(kind, kind)}: {what}")
    return lines


def _read_exact(path: Path) -> str | None:
    """The file byte for byte (no newline translation) — what the recorded sha was taken of."""
    try:
        return path.read_bytes().decode("utf-8")
    except (OSError, UnicodeDecodeError):
        return None


def undo(target: str, day: str | None = None) -> dict:
    """Takes back one change (by its id) or every change of one day (RRRR-MM-DD), newest first.

    Exactly when it can: a file still in the very state the change left it in gets its copy from
    before the change back, byte for byte. A file that changed since (a later run, the user's own
    edit) is not overwritten — the change is reversed entry by entry instead, and anything that
    cannot be found any more is reported, not skipped quietly.
    """
    today = day or datetime.now().strftime("%Y-%m-%d")
    records = read_journal()
    undone = _undone(records)
    changes = [r for r in records if "id" in r]
    wanted = target.strip()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", wanted):
        chosen = [r for r in changes if r["dzien"] == wanted and r["id"] not in undone]
    else:
        chosen = [r for r in changes if r["id"].casefold() == wanted.casefold()]
        if chosen and chosen[0]["id"] in undone:
            return {"status": "juz-cofniete", "undone": [], "problems": [],
                    "note": f"zmiana {chosen[0]['id']} jest juz cofnieta"}
    if not chosen:
        return {"status": "brak", "undone": [], "problems": [],
                "note": f"nie ma zmiany {wanted} do cofniecia (lista: --zmiany)"}
    out = {"status": "ok", "undone": [], "problems": [], "exact": [], "by_content": []}
    for rec in reversed(chosen):
        how = _undo_one(rec, out)
        out["undone"].append(rec["id"])
        _append(JOURNAL_NAME, "", [json.dumps({"cofnieto": rec["id"], "dzien": today,
                                               "sposob": how}, ensure_ascii=False)])
        _append(HISTORY_NAME, HISTORY_HEADER, [f"- [{rec['id']}] cofnięte {today} ({how})"])
        subject = rec["przedmiot"]
        _note(f"- {today} | {UNDONE} | {rec['rodzaj']} {rec['id']} | {how} | {subject}\n", subject)
    if out["problems"]:
        out["status"] = "czesciowo"
    refresh_report(today)
    return out


def _undo_one(rec: dict, out: dict) -> str:
    exact = True
    for path_str, snap in rec["pliki"].items():
        path = Path(path_str)
        if _sha(_read_exact(path)) == snap["po"]:  # untouched since — the copy goes back whole
            try:
                _restore(path, snap)
                out["exact"].append(f"{rec['id']}: {path.name}")
                continue
            except OSError as e:
                out["problems"].append(f"{rec['id']}: {path.name}: {e} - cofam po tresci")
        exact = False
        _undo_by_content(rec, path, out)
    return "dokladnie" if exact else "po tresci"


def _restore(path: Path, snap: dict) -> None:
    if not snap.get("bylo", True):
        path.unlink(missing_ok=True)  # the change created the file — it goes again
        return
    copy = _read_exact(Path(snap["kopia"])) if snap.get("kopia") else None
    if copy is None:
        raise OSError(f"no copy from before the change ({snap.get('kopia') or 'never taken'})")
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(copy)


def _op_text(op: dict) -> str:
    return " ".join(op.get("linie") or op.get("nowe") or [op.get("linia", "")])


def _undo_by_content(rec: dict, path: Path, out: dict) -> None:
    ws = Workspace()
    ws.load(path)
    for op in reversed([op for op in rec["ops"] if op["plik"] == str(path)]):
        if not _apply(ws, _inverse(op)):
            out["problems"].append(f"{rec['id']}: {path.name}: nie znaleziono"
                                   f" „{_quote(_op_text(op), REPORT_QUOTE)}”")
    text = ws.text(path)
    try:
        if text is None:
            path.unlink(missing_ok=True)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(text)
        out["by_content"].append(f"{rec['id']}: {path.name}")
    except OSError as e:
        out["problems"].append(f"{rec['id']}: {path.name}: {e}")


def refresh_report(day: str) -> None:
    """After an undo the summary of the day must not keep announcing what is gone."""
    path = KNOWLEDGE_DIR / STATE_NAME
    raw = _read(path)
    if raw is None:
        return
    kept = [line for line in raw.splitlines() if not line.startswith(REPORT_KEY)]
    lines = kept + _report_state(report_lines(read_journal(), day))
    try:
        path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    except OSError as e:
        log(f"the summary was not refreshed after the undo: {e}")


REPORT_KEY = "meldunek"


def _report_state(lines: list[str]) -> list[str]:
    """The report as 'klucz: wartosc' lines: meldunek (the head), meldunek_1..N (one change each)."""
    return [f"{REPORT_KEY}: {lines[0]}"] + [f"{REPORT_KEY}_{i}: {line}"
                                              for i, line in enumerate(lines[1:], 1)]


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
        # nothing waits for the user any more ("the newer version wins"): always 0, kept for
        # aktualizuj-wiedze.ps1, which warns when it is not
        "sporne": str(len(r["disputed"])),
        "zastapione": str(len(r["replaced"])),
        "uspione": str(len(r["slept"])),
        "obudzone": str(len(r["woken"])),
        # a newer version of a pinned entry, heard in one conversation so far — it waits in the
        # current layer, not in a queue for the user
        "czeka_na_druga_rozmowe": str(r["pending"]),
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
    for key, what in (("replaced", "zastapiono"), ("slept", "uspiono"), ("woken", "obudzono")):
        if r[key]:
            tail.append(f"{what} {len(r[key])}")
    if r["pending"]:
        tail.append(f"{r['pending']} czeka na druga rozmowe (przeczy przypietemu)")
    if entered or promoted or r["replaced"] or r["slept"] or r["woken"]:
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
        lines += _report_state(r["report"])
        (KNOWLEDGE_DIR / STATE_NAME).write_text("\n".join(lines) + "\n",
                                                encoding="utf-8", newline="\n")
    except OSError as e:
        log(f"the summary of this run was not written to {STATE_NAME}: {e}")


# ---------------------------------------------------------------- the whole run

def run(dry_run: bool = False, exists=None, day: str | None = None) -> dict:
    """One pass: waiting room -> the current layer of every instruction file, the facts heard in two
    conversations -> the durable layer, newer versions in place of older ones, the long unconfirmed
    ones to sleep and back, the old ones of the current layer out, plus an audit of what stands.

    Everything happens in memory first: the part without an id (settle_file), then each change with
    an id on top of it, recorded with the state before and after — and only then is anything written.
    """
    exists = exists or path_exists
    today = day or datetime.now().strftime("%Y-%m-%d")
    out = {"status": "dry-run" if dry_run else "ok", "approved": [], "suspicious": [],
           "disputed": [], "over_limit": [], "deferred": [], "waiting": 0, "stale": [],
           "healed": [], "backups": [], "files": [], "added": {}, "entered": [], "promoted": [],
           "expired": [], "own_old": [], "references": [], "stable_chars": 0, "compared": 0,
           "replaced": [], "slept": [], "woken": [], "pending": 0, "changes": [],
           "report": [], "powod": ""}
    files = instruction_files()
    out["files"] = [str(path) for path in files]
    ws = Workspace()
    for path in files:
        ws.load(path)
    dormant_path = KNOWLEDGE_DIR / DORMANT_NAME
    ws.load(dormant_path)
    original = {path: list(ws.lines[path]) for path in [*files, dormant_path]}
    trail = read_trail()
    journal = read_journal()

    # what already stands in the files decides: what a new fact may contradict and whether that is
    # a pinned entry, what is already durable, how much room the durable layer still has, what
    # has gone unconfirmed for too long. Measured BEFORE writing.
    standing: list[Entry] = []
    for path in files:
        for e in entries(original[path]):
            e.auto = trail.is_auto(e)
            if not any(s.text == e.text and s.current == e.current for s in standing):
                standing.append(e)
    durable = {e.key for e in standing if not e.current}
    current: list[tuple[str, str]] = []
    _merge(current, [(e.day, e.text) for e in standing if e.current],
           key=lambda item: fact_key(item[1]))
    out["compared"] = len(standing)
    out["stable_chars"] = max((stable_chars(original[p]) for p in files), default=0)

    raw_candidates = _read(CANDIDATES_PATH)
    reviewed = review_candidates((raw_candidates or "").splitlines(), exists, standing, trail)
    out["suspicious"] = list(reviewed.suspicious)
    out["disputed"] = list(reviewed.disputed)
    out["waiting"] = reviewed.waiting

    writable = [p for p in files if section_bounds(original[p]) is not None]
    if not writable:
        # nowhere to put them — the facts stay in the waiting room instead of quietly disappearing
        out["note"] = "; ".join(f"no '{KNOWLEDGE_HEADING}' section in {p}"
                                " — nothing approved automatically" for p in files) or (
            f"none of the instruction files exists ({', '.join(str(p) for p in INSTRUCTION_PATHS)})"
            " — nothing approved automatically")
        out["powod"] = _reason(out)
        out["report"] = report_lines(journal, today)
        if not dry_run:
            if raw_candidates is not None and reviewed.suspicious:
                _write(CANDIDATES_PATH, reviewed.lines, _newline(raw_candidates))
            write_state(out, today)
        return out

    for c in reviewed.approved:  # a newcomer's pointer stands for its listing, as in note_source
        if c.layer == "referencyjna":
            trail.pointers[fact_key(c.shown)] = fact_key(c.text)

    # 1. what nobody confirmed for SLEEP_DAYS leaves the durable layer — the automaton's entries only
    slept = []
    for e in standing:
        last = trail.last_confirmed(e.key) if e.auto and not e.current else None
        age = _age(last, today) if last else None
        if age is not None and age > SLEEP_DAYS:
            slept.append((e, last))
    left = min((room_for_facts(_without(original[p], [e for e, _ in slept])) for p in writable),
               default=None)

    # 2. the newer versions — out of the waiting room, and those waiting on a pinned entry that
    #    have now been heard in a second conversation
    replacements = []
    for rep in reviewed.replacing + _confirmed_waiting(standing, trail, reviewed.replacing):
        grow = 0 if rep.target.current else len(rep.new) - len(rep.target.text)
        if left is not None and grow > left:
            out["over_limit"].append(rep.new)  # the ceiling stops it and says so
            if rep.candidate is not None:  # not lost: it waits in the current layer meanwhile
                rep.candidate.against = rep.target.text
                reviewed.approved.append(rep.candidate)
                reviewed.pending.append(rep.candidate)
            continue
        if left is not None:
            left -= max(0, grow)
        replacements.append(rep)
    out["approved"] = [c.text for c in reviewed.approved]

    # 3. the dormant facts heard again, and the promotions — one limit, one ceiling
    wakes = []
    for d in read_dormant(ws.lines[dormant_path]):
        sightings = trail.evidence(d.key)
        if any(s.day >= d.slept for s in sightings) and not trail.blocked(d.key):
            wakes.append(Promotion(d.text, f"### {d.heading}", conversations(sightings),
                                   min(s.day for s in sightings), dormant=d))
    waiting = ({e.key for e in standing if e.current and e.against}
               | {fact_key(c.shown) for c in reviewed.pending})
    gone = {e.key for r in replacements for e in [r.target, *r.extra]}
    candidates = ([text for _, text in current] + [c.shown for c in reviewed.approved])
    candidates = [t for t in candidates if fact_key(t) not in waiting | gone]
    candidates += [r.new for r in replacements if r.target.current and not r.against]
    chosen = choose_promotions(candidates, trail, durable, left, wakes)
    out["deferred"] = [p.text for p in chosen.deferred]
    out["over_limit"] += [p.text for p in chosen.over_limit]
    leaving, out["own_old"] = expiring(current, trail, today, {p.key for p in chosen.chosen})

    # the part without an id: the audit, what aged out, what came in
    for path in files:
        result, ws.lines[path] = settle_file(path, ws.lines[path], reviewed.approved, exists,
                                             today, set(leaving))
        if result.note is None:
            _merge(out["stale"], result.stale, key=lambda item: item[0])
            _merge(out["healed"], result.healed)
            _merge(out["entered"], result.added)
            _merge(out["expired"], result.expired)
            if result.added:
                out["added"][str(path)] = result.added
    entered = list(out["entered"])

    # the changes with an id, one after another on top of it
    changes = Changes(ws, today, sum(1 for r in journal if "id" in r and r.get("dzien") == today))
    for e, last in slept:
        c = Change("U", e.text, heading=e.heading or DEFAULT_SUBSECTION,
                   note=f"ostatnio potwierdzone {last}")
        if changes.commit(c, sleep_ops(ws, writable, e, dormant_path, today)):
            out["slept"].append(e.text)
    for r in replacements:
        whose = "automatu" if r.target.auto else f"przypiętego, nowa wersja z {r.heard} rozmów"
        c = Change("Z", r.new, old=r.target.text, note=f"wpis {whose}",
                   heading=CURRENT_SUBSECTION if r.target.current
                   else (r.target.heading or DEFAULT_SUBSECTION))
        if changes.commit(c, replace_ops(ws, writable, r, today)):
            out["replaced"].append((r.target.text, r.new, c.id))
    for p in chosen.chosen:
        if p.dormant is not None:
            c = Change("O", p.text, heading=p.heading,
                       note=f"uśpione {p.dormant.slept}, padło znowu w rozmowie")
            ops = [{"op": "zbudz", "plik": str(dormant_path), "linia": p.dormant.line}]
            if changes.commit(c, ops + durable_ops(ws, writable, p.text, p.heading)):
                out["woken"].append(p.text)
        else:
            c = Change("A", p.text, heading=p.heading,
                       note=f"z {p.conversations} rozmów, pierwszy raz {p.first_seen}")
            if changes.commit(c, durable_ops(ws, writable, p.text, p.heading)):
                out["promoted"].append(p.text)
    # a newcomer promoted in the same run went through the current layer on its way — it is
    # reported once, as promoted
    moved = {fact_key(t) for t in out["promoted"] + out["woken"]}
    out["entered"] = [c.text for c in reviewed.approved
                      if c.text in entered and fact_key(c.shown) not in moved]
    out["pending"] = len({e.key for p in writable for e in entries(ws.lines[p])
                          if e.current and e.against})
    out["changes"] = [c.id for c in changes.done]
    out["powod"] = _reason(out)
    if dry_run:
        out["report"] = report_lines(journal + [c.record(today) for c in changes.done], today)
        return out

    for path in files:
        if ws.lines[path] != original[path]:
            out["backups"].append(str(backup_file(path)))
            _write(path, ws.lines[path], ws.newline[path])
    if ws.lines[dormant_path] != original[dormant_path]:
        _write(dormant_path, ws.lines[dormant_path], ws.newline[dormant_path])
    save_changes(changes.done, today)
    for candidate in reviewed.approved:
        if candidate.layer == "referencyjna":
            target = write_reference(candidate, day)
            if target:
                out["references"].append(target)
        if candidate.text in entered:
            note_source(candidate, writable, today)
    written_on = {fact_key(text): d for d, text in current}
    for text in out["expired"]:
        note_expiry(text, written_on.get(fact_key(text), ""), writable, today)
    if raw_candidates is not None and reviewed.lines != raw_candidates.splitlines():
        _write(CANDIDATES_PATH, reviewed.lines, _newline(raw_candidates))
    out["report"] = report_lines(read_journal(), today)
    write_state(out, today)
    return out


def _without(lines: list[str], gone: list[Entry]) -> list[str]:
    """The file with these durable entries taken out — to measure the room they leave behind."""
    for e in gone:
        found = _find(lines, e.key, False)
        if found:
            lines = lines[:found[0]] + lines[found[1]:]
    return lines


def _confirmed_waiting(standing: list[Entry], trail: Trail, settled: list) -> list:
    """Newer versions that waited in the current layer for a second conversation and got it: they
    take the place of the durable entry they contradict. A version whose replacement the user took
    back waits for a new sighting (Trail.blocked)."""
    handled = {k for r in settled for k in (fact_key(r.new), r.target.key)}
    out = []
    for e in standing:
        if not (e.current and e.against and e.auto) or e.key in handled or trail.blocked(e.key):
            continue
        targets = [x for x in clashes(e.text, standing) if not x.current]
        pinned = [x for x in targets if not x.auto]
        heard = conversations(trail.evidence(e.key))
        if not targets or (pinned and heard < MIN_CONVERSATIONS):
            continue
        target = pinned[0] if pinned else targets[0]
        out.append(Replacement(e.text, target, [e] + [x for x in targets if x.auto and x is not target],
                               e.day, "", None, heard))
        handled |= {e.key, target.key}
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
        f" replaced: {len(r['replaced'])}, asleep: {len(r['slept'])}, woken: {len(r['woken'])},"
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
    for line in r["report"]:  # the day's changes, each with the id that takes it back
        log(f"meldunek: {line}")


def _list_changes(day: str | None) -> None:
    """The changes of one day (all of them without a day), newest last, marked when undone."""
    records = read_journal()
    undone = _undone(records)
    shown = [r for r in records if "id" in r and (day is None or r.get("dzien") == day)]
    if not shown:
        log(f"no automatic changes{' on ' + day if day else ''}")
    for r in shown:
        mark = " (cofnieta)" if r["id"] in undone else ""
        old = f"„{_quote(r['stare'], REPORT_QUOTE)}” -> " if r.get("stare") else ""
        log(f"{r['id']}{mark} {r['rodzaj']}: {old}„{_quote(r['przedmiot'], REPORT_QUOTE)}”")


def _undo_command(target: str) -> int:
    r = undo(target)
    if r["status"] in ("brak", "juz-cofniete"):
        log(r["note"])
        return 1
    log(f"undone: {', '.join(r['undone'])}")
    for item in r["exact"]:
        log(f"  = {item}  (restored byte for byte from the copy taken before the change)")
    for item in r["by_content"]:
        log(f"  ~ {item}  (the file changed since — reversed entry by entry)")
    for item in r["problems"]:
        log(f"  ! {item}")
    return 0 if r["status"] == "ok" else 2


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    dry_run = bool({"--proba", "--dry-run"} & set(argv))
    try:
        for flag in ("--cofnij", "--zmiany"):
            if flag in argv:
                value = argv[argv.index(flag) + 1:argv.index(flag) + 2]
                if flag == "--zmiany":
                    _list_changes(value[0] if value else None)
                    return 0
                if not value:
                    log("--cofnij needs a change id (e.g. Z-260924-1) or a day (RRRR-MM-DD);"
                        " the changes: --zmiany")
                    return 1
                return _undo_command(value[0])
        r = run(dry_run=dry_run)
    except Exception as e:  # a scheduled task must end with a readable line, not a traceback
        log(f"verifying the facts failed: {e!r}")
        return 1
    _report(r)
    return 0


if __name__ == "__main__":
    sys.exit(main())
