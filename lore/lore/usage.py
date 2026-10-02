"""Use of a durable fact found WITHOUT the model — by its characteristic words in the transcripts.

The daily model call (lore.facts) marks the facts the agent used, but it sees only the chosen
messages of the user and ~200 characters of the agent's answer before each of them. A fact the
agent applied quietly, in a long answer or in a command, is invisible to it — and an unseen use
lets the fact fall asleep after SLEEP_DAYS (lore.verify), so the user would have to say it again,
which is exactly what he asked not to do (2026-10-01).

This pass costs 0 tokens: for every fact of the AUTOMATON in the durable layer it picks a few words
that point at that fact and nothing else (see signatures()), and looks for them in everything the
agent wrote and did since the last pass — the full text of its answers and the input of its tool
calls, in Claude Code and Codex transcripts, subagents included. A hit is a use: the same USED line
in wiedza/zrodla.md the model writes (lore.facts.note_used), so lore.verify takes the later of the
two dates without knowing which of them found it.

Read once per day, only what is new: the transcript files are read from where the previous pass
stopped (a byte offset per file, .ostatnie-uzycie-pozycje.json), files untouched since the last
pass (.ostatnie-uzycie) are not opened at all, and a file seen for the first time is streamed line
by line, its older records skipped by their stamp. Nothing is held in memory but one line.

The automaton's CURRENT facts that may still be promoted are checked as well (since 2026-10-01): a
use on another day, in another conversation than the one the fact came out of, counts as the second
conversation a promotion needs (lore.verify.Trail.confirmations) — the user does not want to repeat
himself. Only a strong word may confirm that way; see the rule below, point 5.

The pinned facts are not checked (they never fall asleep, they are never promoted), and neither are
the dormant ones: waking a fact up on a keyword is the one mistake that puts it back in front of
every session, and the model's check (which lists the dormant facts) is the safer judge there.
"""

from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

from . import facts, index, safeio
from .db import log

MARKER_NAME = ".ostatnie-uzycie"  # the moment the last pass started — "byłem tu" for this pass
OFFSETS_NAME = ".ostatnie-uzycie-pozycje.json"  # {file: byte offset read up to}
SOURCE_LABEL = "transkrypty, bez modelu"  # how such a line of the trail says where it came from

# ---------------------------------------------------------------- which words point at a fact
#
# The rule (the user's priority: a missed use costs a repetition, a false one keeps a dead fact in
# front of every session for months — so in doubt the word is NOT taken):
#
# 1. Only words that look like DATA, never prose: a token with a digit, an e-mail, an identifier
#    (camelCase, a file name, a path, a SKU with brackets — a letter or digit on both sides of one
#    of _ / \ . @ [ ] :, 5+ characters), a word in capitals of 5+ letters (a brand: MARKAX), or a phrase of 2+
#    words and 12+ characters the fact puts in quotes or backticks. An ordinary word ("cena",
#    "Amazon", "Discord") is never taken, capitalised or not: Polish puts a capital at the start of
#    every sentence and the agent says such words all day long about anything.
# 2. Too little to be specific is dropped: under 4 characters; a number with fewer than 5 digits
#    (prices 50,76 and 12,70, a card's last 4 digits, "180 dni" — they turn up by chance in any
#    calculation); dates, times and years (every transcript is full of them).
# 3. The word must be the fact's OWN: it may not stand anywhere else in the instruction files —
#    not in another entry, not in the rules. "PRZYKLAD" or "MegaRuchacz" stand in many places, so
#    the agent writing them says nothing about THIS fact. The same uniqueness keeps two facts from
#    holding each other awake.
# 4. Strong and weak. STRONG — one hit is a use: 5+ digits (a case number, ASIN digits, NIP, an IP,
#    a channel id), letters with 3+ digits in 8+ characters (B0TEST1234), an e-mail, an identifier
#    of 15+ characters (searchListingsItems, SKU/PRZYKLAD/FBA), a quoted phrase. These do not
#    appear by chance — except plain words joined by a slash ("serwer/komputer" is prose, measured
#    on the real rules 2026-10-01), which stay weak however long they are. WEAK — Magazyn2, start.bat, MARKAX: a single one appears whenever the agent
#    works NEAR the subject, so a weak word counts only together with ANOTHER weak word of the same
#    fact in the same record of the transcript.
# A fact left with no strong word and fewer than two weak ones has no signature: only the model's
# check marks its use (and the pass says how many such facts there are).
# 5. Promotion (a CURRENT fact moving to the durable layer on a use, 2026-10-01). A promoted fact
#    stands in front of every session for at least half a year, so the bar is higher here than for
#    keeping a durable fact awake. A use found by a STRONG word may stand in for the second
#    conversation by itself: such a word is data that stands nowhere else in the instruction files
#    and does not come up by chance (a case number, an ASIN, an e-mail, a quoted phrase) — the agent
#    writing it on another day, in a conversation the fact did not come from, took it from the fact.
#    And it is never the only evidence: the fact had to come out of the user's own words first,
#    the model's label must call it durable, at most MAX_PROMOTIONS go per run, under the ceiling,
#    every promotion can be undone, and a durable fact nobody uses falls asleep after SLEEP_DAYS.
#    A PAIR OF WEAK WORDS may NOT promote: two of them meet whenever the agent works near the
#    subject (Magazyn2 and start.bat turn up in every session about the robot) — that is being
#    close to the topic, not relying on the fact. Such a use is written with facts.USED_WEAK in its
#    source: it keeps a durable fact awake, and lore.verify does not count it for a promotion.

MIN_CHARS = 4
MIN_DIGITS = 5  # below this a number is a price, a quantity or a card's tail — see the rule, 2.
STRONG_CODE_DIGITS, STRONG_CODE_CHARS = 3, 8
STRONG_IDENTIFIER_CHARS = 15
PHRASE_WORDS, PHRASE_CHARS = 2, 12
CAPS_CHARS = 5
IDENTIFIER_CHARS = 5  # "m.in", "o.o" are abbreviations, not names of anything
# capitals that are emphasis, not a name — the rules shout these and so does the agent
SHOUTED = frozenset({"PUŁAPKA", "UWAGA", "WAŻNE", "NIGDY", "ZAWSZE", "TYLKO", "WYŁĄCZNIE", "ALARM",
                     "PILNE", "BRAK", "NOTE", "WARNING", "TODO", "ERROR"})

_STRIP = ".,;:!?(){}„”“\"'«»*`<>"
_QUOTED = re.compile(r"[„“\"]([^„“”\"\n]+)[”\"]|`([^`\n]+)`")
_DATEISH = re.compile(r"^(\d{4}-\d{2}(-\d{2})?|\d{1,2}[:.]\d{2}([:.]\d{2})?|\d{1,2}\.\d{1,2}(\.\d{2,4})?"
                      r"|(19|20)\d{2})$")
_EMAIL = re.compile(r"^[\w.+-]+@[\w-]+(\.[\w-]+)+$")
# a separator inside — not the hyphen: "e-commerce", "biało-czerwony" are prose
_JOINED = re.compile(r"[^\W_][_/\\.@\[\]:]+[^\W_]|[\w][\[\]]|[\[\]][\w]")
_CAMEL = re.compile(r"[a-ząćęłńóśźż][A-ZĄĆĘŁŃÓŚŹŻ]")


@dataclass(frozen=True)
class Signature:
    word: str  # as written in the fact
    strong: bool

    @property
    def needle(self) -> str:
        return " ".join(self.word.split()).lower()


def _clean(token: str) -> str:
    token = token.strip(_STRIP)
    if not ("[" in token and "]" in token):  # a SKU keeps its brackets, a stray bracket goes
        token = token.strip("[]").strip(_STRIP)
    return token


def kind(token: str) -> str | None:
    """'strong', 'weak' or None for one word of a fact — the rule above, points 1, 2 and 4."""
    if len(token) < MIN_CHARS or _DATEISH.match(token):
        return None
    digits = sum(c.isdigit() for c in token)
    letters = sum(c.isalpha() for c in token)
    if _EMAIL.match(token):
        return "strong"
    if digits >= MIN_DIGITS:
        return "strong"
    if letters and digits >= STRONG_CODE_DIGITS and len(token) >= STRONG_CODE_CHARS:
        return "strong"
    if "/" in token and all(part.isalpha() for part in token.split("/")):
        # words with a slash between them are mostly prose ("serwer/komputer", "ticketów/zgłoszeń")
        # and only sometimes a name ("obra/superpowers") — never strong, however long
        return "weak" if len(token) >= IDENTIFIER_CHARS else None
    identifier = bool(_JOINED.search(token) or _CAMEL.search(token))
    if identifier and len(token) >= STRONG_IDENTIFIER_CHARS:
        return "strong"
    if digits and not letters:
        return None  # a number too short to mean anything by itself: 50,76  5025  +175
    if letters and digits:
        return "weak"
    if identifier and len(token) >= IDENTIFIER_CHARS:
        return "weak"
    if letters >= CAPS_CHARS and token.isupper() and token not in SHOUTED:
        return "weak"
    return None


def candidates(text: str) -> dict[str, str]:
    """Every word and quoted phrase of a fact that may point at it -> 'strong' / 'weak'."""
    out: dict[str, str] = {}
    for m in _QUOTED.finditer(text):
        inside = (m.group(1) or m.group(2) or "").strip()
        if len(inside.split()) >= PHRASE_WORDS and len(inside) >= PHRASE_CHARS:
            out[inside] = "strong"
    for raw in text.split():
        token = _clean(raw)
        found = kind(token)
        if found and token not in out:
            out[token] = found
    return out


def _pattern(needle: str) -> re.Pattern:
    """The word as a whole word: 'B0TEST1234' is not found inside 'XB0TEST1234Z'."""
    return re.compile(r"(?<!\w)" + re.escape(needle) + r"(?!\w)")


def _count(needle: str, haystack: str) -> int:
    return len(_pattern(needle).findall(haystack)) if needle in haystack else 0


def signatures(text: str, own: str, everything: str) -> list[Signature]:
    """The words of a fact that point at it alone — the rule above, point 3 on top of the others.

    `own` is the text of the fact as it stands in the files (every copy of it), `everything` the
    whole of the instruction files: a word counted more often in everything than in own stands
    somewhere else as well and is dropped. Lowercase both, whitespace collapsed by the caller.
    Returns [] when what is left cannot ever count as a use (no strong word, fewer than 2 weak)."""
    out = []
    for word, strength in candidates(text).items():
        needle = " ".join(word.split()).lower()
        if _count(needle, everything) > _count(needle, own):
            continue
        out.append(Signature(word, strength == "strong"))
    if not any(s.strong for s in out) and len(out) < 2:
        return []
    return out


def _flat(text: str) -> str:
    return " ".join(text.split()).lower()


@dataclass
class Watch:
    """One fact and the words it is recognised by."""
    text: str
    words: list[Signature]

    def hits(self, haystack: str) -> list[Signature]:
        """The words found in one record; [] unless they add up to a use (one strong, two weak)."""
        found = [s for s in self.words if _count(s.needle, haystack)]
        if any(s.strong for s in found) or len(found) >= 2:
            return found
        return []


def watched() -> tuple[list[Watch], list[str]]:
    """(facts with a signature, facts without one) — the automaton's facts of the durable layer
    and its current ones that may still be promoted (verify.Trail.use_matters)."""
    from . import verify  # verify imports facts; at call time both are complete

    trail = verify.read_trail(facts.KNOWLEDGE_DIR / facts.SOURCES_NAME)
    texts, own, everything = [], {}, []
    for path in facts.instruction_paths():
        lines = facts._lines(path)
        everything.extend(lines)
        for e in verify.entries(lines):
            if not trail.use_matters(e):  # durable of the automaton, or current and promotable
                continue
            if e.key not in own:
                texts.append(e.text)
                own[e.key] = []
            own[e.key].extend(e.lines)
    whole = _flat("\n".join(everything))
    with_words, without = [], []
    for text in texts:
        words = signatures(text, _flat("\n".join(own[verify.fact_key(text)])), whole)
        (with_words.append(Watch(text, words)) if words else without.append(text))
    return with_words, without


# ---------------------------------------------------------------- what the agent wrote and did

# a tool call that writes the knowledge itself is upkeep, not use: an Edit of CLAUDE.md carries
# the whole fact and would keep every fact it touches awake
_UPKEEP = re.compile(r"(CLAUDE\.md|AGENTS\.md|[\\/]wiedza[\\/])", re.IGNORECASE)


def _strings(value) -> list[str]:
    """Every string inside a tool input — the values, not their JSON (no doubled backslashes)."""
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        return [s for v in value.values() for s in _strings(v)]
    if isinstance(value, list):
        return [s for v in value for s in _strings(v)]
    return []


def _tool_text(inp) -> str:
    target = inp.get("file_path") or inp.get("path") or inp.get("notebook_path") \
        if isinstance(inp, dict) else None
    if isinstance(target, str) and _UPKEEP.search(target):
        return ""
    return "\n".join(_strings(inp))


def agent_text(rec: dict) -> str | None:
    """What the agent wrote or did in one transcript record; None when the record is not its own.

    Claude Code: the text blocks of an assistant message and the input of its tool calls (thinking
    is stored empty). Codex: the output_text of an assistant message and the arguments of a call.
    """
    if rec.get("type") == "assistant":
        content = (rec.get("message") or {}).get("content")
        if isinstance(content, str):
            return content
        parts = []
        for b in content if isinstance(content, list) else []:
            if not isinstance(b, dict):
                continue
            if b.get("type") == "text" and isinstance(b.get("text"), str):
                parts.append(b["text"])
            elif b.get("type") == "tool_use":
                parts.append(_tool_text(b.get("input")))
        return "\n".join(p for p in parts if p)
    payload = rec.get("payload")
    if rec.get("type") != "response_item" or not isinstance(payload, dict):
        return None
    if payload.get("type") == "message" and payload.get("role") == "assistant":
        return "\n".join(b.get("text", "") for b in payload.get("content") or []
                         if isinstance(b, dict) and b.get("type") == "output_text"
                         and isinstance(b.get("text"), str))
    if payload.get("type") in ("function_call", "custom_tool_call", "local_shell_call"):
        raw = payload.get("arguments") or payload.get("input") or payload.get("action")
        if isinstance(raw, str):
            try:
                raw = json.loads(raw)
            except ValueError:
                return "" if _UPKEEP.search(raw) else raw
        return _tool_text(raw)
    return None


_OWN = (b'"assistant"', b'"response_item"')  # cheap test before json.loads, any spacing


@dataclass
class Found:
    """The latest record a fact was found in."""
    ts: str
    session: str
    words: list[str]
    sessions: list[str] = field(default_factory=list)
    # the same, kept apart for the records with a strong word (True) and with weak words only
    # (False): one USED line each, so that a weak hit never lends its day or conversation to a
    # line that may promote — see the rule, point 5
    by_strength: dict = field(default_factory=dict)

    def add(self, ts: str, session: str, words: list[str]) -> None:
        if ts >= self.ts:
            self.ts, self.session, self.words = ts, session, words
        if session not in self.sessions:
            self.sessions.append(session)


@dataclass
class Scan:
    files: int = 0  # opened this pass
    bytes: int = 0  # read this pass
    records: int = 0  # of the agent, past the marker
    offsets: dict = field(default_factory=dict)
    found: dict = field(default_factory=dict)  # fact text -> Found


def _read_file(path: Path, start: int, since: str | None, watches: list[Watch], scan: Scan) -> int:
    """Streams one file from `start`; returns the offset of the end of its last complete line.
    `since` filters by stamp — only for a file read from the beginning (no offset saved yet)."""
    session_default = session_of(path)
    with open(path, "rb") as f:
        f.seek(start)
        pos = start
        for raw in f:
            if not raw.endswith(b"\n"):
                break  # still being written — read next time, from here
            pos += len(raw)
            scan.bytes += len(raw)
            if not any(mark in raw for mark in _OWN):
                continue
            try:
                rec = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(rec, dict):
                continue
            ts = rec.get("timestamp") if isinstance(rec.get("timestamp"), str) else ""
            if since and ts and ts <= since:
                continue
            text = agent_text(rec)
            if not text:
                continue
            scan.records += 1
            haystack = _flat(text)
            for w in watches:
                words = w.hits(haystack)
                if not words:
                    continue
                session = rec.get("sessionId") or session_default
                names = [s.word for s in words]
                found = scan.found.setdefault(w.text, Found(ts, session, names))
                found.add(ts, session, names)
                strong = any(s.strong for s in words)
                found.by_strength.setdefault(strong, Found(ts, session, names)).add(ts, session, names)
    return pos


_UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.IGNORECASE)


def session_of(path: Path) -> str:
    """The conversation a transcript belongs to, named the way the harvest names it — the trail
    compares the two, and a use may not confirm a fact inside the conversation it came out of.
    lore.index takes it from the place of the file (a subagent: its parent's directory) and, for
    Codex, from session_meta, whose id is the uuid at the end of 'rollout-...-<uuid>'."""
    try:
        session = index.describe_file(path)[1]
    except ValueError:
        session = path.stem
    m = _UUID.search(session)
    return m.group(0) if m and session.startswith("rollout-") else session


def marker_path() -> Path:
    return facts.KNOWLEDGE_DIR / MARKER_NAME


def offsets_path() -> Path:
    return facts.KNOWLEDGE_DIR / OFFSETS_NAME


def read_marker() -> str:
    saved = facts._saved(marker_path())
    if saved and facts._is_iso(saved):
        return saved
    if saved:
        log(f"unreadable marker {MARKER_NAME}: {saved!r} — looking back {facts.DEFAULT_WINDOW_H} h")
    return facts.iso_utc(datetime.now(timezone.utc) - timedelta(hours=facts.DEFAULT_WINDOW_H))


def read_offsets() -> dict[str, int]:
    try:
        data = json.loads(offsets_path().read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except (OSError, ValueError) as e:  # costs one slower pass (reading by stamp), loses nothing
        log(f"unreadable {OFFSETS_NAME}: {e} — files are read by their stamps this time")
        return {}
    return {k: v for k, v in data.items() if isinstance(v, int)} if isinstance(data, dict) else {}


def scan(watches: list[Watch], since: str, offsets: dict[str, int]) -> Scan:
    """Every transcript touched after `since`, from its saved offset (or by stamp, from the start)."""
    out = Scan()
    try:
        cutoff = datetime.fromisoformat(since.replace("Z", "+00:00")).timestamp()
    except ValueError:
        cutoff = 0.0
    for path in index.find_files():
        key = str(path)
        try:
            st = path.stat()
        except OSError:
            continue
        start = offsets.get(key)
        if start is not None and start > st.st_size:
            start = None  # the file was rewritten — read it again, by stamp
        if st.st_mtime <= cutoff or start == st.st_size:
            if start is not None:
                out.offsets[key] = start  # untouched — keep the place for the day it grows
            continue
        try:
            out.offsets[key] = _read_file(path, start or 0, None if start is not None else since,
                                          watches, out)
        except OSError as e:  # one unreadable file must not hide the others — but it is said
            log(f"UWAGA: transcript {path} could not be read for the use check: {e}")
            if start is not None:
                out.offsets[key] = start
            continue
        out.files += 1
    return out


def _local_day(ts: str) -> str:
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().strftime("%Y-%m-%d")
    except ValueError:
        return datetime.now().strftime("%Y-%m-%d")


def note(found: dict) -> None:
    """USED lines in the shape of the model's, with the words the fact was found by — one for the
    records with a strong word, one for those with weak words only (marked facts.USED_WEAK: it
    keeps a fact awake, but lore.verify does not promote on it — the rule above, point 5)."""
    for text, hit in found.items():
        for strong, part in sorted((hit.by_strength or {True: hit}).items(), reverse=True):
            words = ", ".join(w.replace("|", "/") for w in part.words)
            label = SOURCE_LABEL if strong else f"{SOURCE_LABEL}, {facts.USED_WEAK}"
            facts.note_sources([facts.Fact(text, "stala")], f"{label}, słowa: {words}",
                               _local_day(part.ts), part.sessions, event=facts.USED)


def run(dry_run: bool = False, since: str | None = None,
        watches: list[Watch] | None = None) -> dict:
    """One pass. A dry run reads and reports, but writes neither the trail nor the markers.
    `since` and `watches` — for measuring on real data without touching its state."""
    started = facts.iso_utc(datetime.now(timezone.utc))
    clock = time.perf_counter()
    without: list[str] = []
    if watches is None:
        watches, without = watched()
    since = since or read_marker()
    out = {"since": since, "checked": len(watches) + len(without), "with_words": len(watches),
           "without_words": len(without), "files": 0, "bytes": 0, "records": 0, "used": {},
           "seconds": 0.0, "dry_run": dry_run}
    if watches:
        s = scan(watches, since, read_offsets())
        out.update(files=s.files, bytes=s.bytes, records=s.records, used=s.found)
        offsets = s.offsets
    else:
        offsets = None  # nothing to look for: nothing read, and nothing waits to be read later
    out["seconds"] = round(time.perf_counter() - clock, 2)
    if dry_run:
        return out
    note(out["used"])
    facts.KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    if offsets is not None:
        safeio.write_text(offsets_path(), json.dumps(offsets, ensure_ascii=False), newline=None)
    safeio.write_text(marker_path(), started + "\n", newline=None)
    return out


def report(r: dict) -> None:
    """What the pass did — zero included: silence would look the same as a pass that never ran."""
    head = "use by keyword (no model)" + (" — dry run, nothing written" if r["dry_run"] else "")
    if not r["checked"]:
        log(f"{head}: no fact of the automaton in the durable layer — nothing to look for")
        return
    log(f"{head}: transcripts since {r['since']}: {r['files']} files,"
        f" {r['bytes'] / 1_000_000:.1f} MB, {r['records']} records of the agent, {r['seconds']} s;"
        f" facts checked: {r['with_words']}, used: {len(r['used'])}")
    for text, hit in r["used"].items():
        log(f"  * {text}  (słowa: {', '.join(hit.words)})")
    if r["without_words"]:
        log(f"{r['without_words']} facts of the automaton have no characteristic word"
            f" — only the model's check can mark their use")
