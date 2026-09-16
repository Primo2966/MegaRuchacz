"""Confronting the harvested facts with reality — whatever a machine can check, it checks itself.

The waiting room (~/.claude/wiedza/kandydaci.md) fills up faster than anybody reads it, so a fact
carrying a claim that can be verified without a human does not wait for one: an existing path
confirms it, a missing one makes it suspect. The same check runs over the facts already standing
in the rules (~/.claude/CLAUDE.md, section "## Co wiem") — a directory moved without a word makes
a rule silently false, and nothing but a check will ever notice.

Writing to the rules is allowed, but ONLY inside "## Co wiem"; everything above it and the whole
block between the MegaRuchacz markers is off limits, and the file is copied aside before a change.

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

KNOWLEDGE_DIR = CLAUDE_HOME / "wiedza"
CANDIDATES_PATH = KNOWLEDGE_DIR / "kandydaci.md"
RULES_PATH = CLAUDE_HOME / "CLAUDE.md"  # written, but never outside the "## Co wiem" section
BACKUP_DIR = KNOWLEDGE_DIR / "kopie"

KNOWLEDGE_HEADING = "## Co wiem"
GUARD_MARKER = "<!-- MegaRuchacz:start -->"  # from here down the file belongs to the installer
DEFAULT_SUBSECTION = "### Nad czym pracuje"
EMPTY_MARKER = "_(pusto)_"  # placeholder of an empty subsection — the first entry replaces it

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

_CANDIDATE = re.compile(r"^(\s*-\s*\[)([ xX!])(\]\s*(?:\[\d{4}-\d{2}-\d{2}\]\s*)?)(.+)$")
_NOT_FOUND = re.compile(r"\s*\(nie znaleziono:[^)]*\)\s*$")
_BULLET_START = re.compile(r"^\s{0,3}[-*]\s+\S")
_UNCONFIRMED = re.compile(r"\s*<!--\s*niepotwierdzone[^>]*-->\s*$")


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


# ---------------------------------------------------------------- the waiting room

@dataclass
class Reviewed:
    lines: list[str] = field(default_factory=list)  # the new content of the waiting room
    approved: list[str] = field(default_factory=list)  # confirmed — they move to the rules
    suspicious: list[tuple[str, list[str]]] = field(default_factory=list)
    waiting: int = 0  # still there, with nobody but the user able to decide


def review_candidates(lines: list[str], exists=None) -> Reviewed:
    """Sorts the waiting room: confirmed out, unconfirmed marked '[!]', unverifiable untouched."""
    exists = exists or path_exists
    out = Reviewed()
    for line in lines:
        m = _CANDIDATE.match(line)
        if not m or m.group(2) not in (" ", "!"):  # '[x]' is the user's own decision, not ours
            out.lines.append(line)
            continue
        text = _NOT_FOUND.sub("", m.group(4)).rstrip()
        verdict = verify(text, exists)
        if verdict.confirmed:
            out.approved.append(text)
            continue  # the line disappears from here and shows up in the rules
        if verdict.missing:
            out.suspicious.append((text, verdict.missing))
            text += f" (nie znaleziono: {', '.join(verdict.missing)})"
            out.lines.append(f"{m.group(1)}!{m.group(3)}{text}")
        else:
            out.lines.append(line)
        out.waiting += 1
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


def _heading_index(body: list[str], heading: str) -> int | None:
    for i, line in enumerate(body):
        if line.strip() == heading:
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


def backup_rules(day: str | None = None) -> Path:
    """A copy with the date in the name, taken before every change to the rules."""
    day = day or datetime.now().strftime("%Y-%m-%d-%H%M%S")
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    target = BACKUP_DIR / f"CLAUDE-{day}.md"
    shutil.copy2(RULES_PATH, target)
    return target


# ---------------------------------------------------------------- the whole run

def run(dry_run: bool = False, exists=None, day: str | None = None) -> dict:
    """One pass: waiting room -> rules, plus an audit of what already stands in the rules."""
    exists = exists or path_exists
    out = {"status": "dry-run" if dry_run else "ok", "approved": [], "suspicious": [],
           "waiting": 0, "stale": [], "healed": [], "backup": None}
    raw_candidates = _read(CANDIDATES_PATH)
    reviewed = review_candidates((raw_candidates or "").splitlines(), exists)
    out["approved"] = list(reviewed.approved)
    out["suspicious"] = list(reviewed.suspicious)
    out["waiting"] = reviewed.waiting

    raw_rules = _read(RULES_PATH)
    rules_lines = (raw_rules or "").splitlines()
    bounds = section_bounds(rules_lines) if raw_rules is not None else None
    if bounds is None:
        out["note"] = f"no '{KNOWLEDGE_HEADING}' section in {RULES_PATH} — nothing approved automatically"
        out["approved"] = []
        if not dry_run and raw_candidates is not None and reviewed.suspicious:
            _write(CANDIDATES_PATH, reviewed.lines, _newline(raw_candidates))
        return out

    start, end = bounds
    audited = audit_rules(rules_lines[start:end], exists, day)
    out["stale"] = audited.stale
    out["healed"] = audited.healed
    body = audited.body
    for fact in reviewed.approved:
        body = insert_fact(body, fact, subsection_for(fact))
    changed_rules = body != rules_lines[start:end]
    if dry_run:
        return out
    if changed_rules:
        out["backup"] = str(backup_rules())
        # only the body of the section is swapped — the lines around it are the very same objects
        _write(RULES_PATH, rules_lines[:start] + body + rules_lines[end:], _newline(raw_rules))
    if raw_candidates is not None and reviewed.lines != raw_candidates.splitlines():
        _write(CANDIDATES_PATH, reviewed.lines, _newline(raw_candidates))
    return out


def _write(path: Path, lines: list[str], newline: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(newline.join(lines) + (newline if lines else ""))


def _report(r: dict) -> None:
    if r.get("note"):
        log(r["note"])
    head = "dry run — nothing written; " if r["status"] == "dry-run" else ""
    log(f"{head}approved automatically: {len(r['approved'])},"
        f" waiting for a decision: {r['waiting']},"
        f" standing facts that stopped checking out: {len(r['stale'])}")
    for fact in r["approved"]:
        log(f"  + {fact}")
    for fact, missing in r["suspicious"]:
        log(f"  ? {fact}  (nie znaleziono: {', '.join(missing)})")
    for fact, missing in r["stale"]:
        log(f"  ! {fact}  (nie ma: {', '.join(missing)})")
    for fact in r["healed"]:
        log(f"  ~ {fact}  — confirmed again, the warning is gone")
    if r["backup"]:
        log(f"copy of the rules before the change: {r['backup']}")


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
