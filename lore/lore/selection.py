"""Which of the user's messages the daily harvest hands to the model — the strongest signal only.

Reading everything the user wrote was measured and found wanting: of the first 90 facts fished out
of the whole of it, 5 turned out useful. What really works in the user's knowledge came out of the
moments he had to CORRECT the agent. So the harvest reads three kinds of message and nothing else:

- a correction ("nie, to nie tak", "przecież mówiłem", "miało być…", irritation) — found by the
  words and their position, never by asking a model. The patterns were built on the real archive
  (2 603 messages of the user, Polish, colloquial, full of typos and swearing) — see CORRECTION_*;
- a repetition — the message says again what the user already said in ANOTHER conversation
  ("powtórzenie to dowód, że brakuje wpisu") — see Echoes for how and why the threshold is what it is;
- an explicit "zapamiętaj" and its variants — these always go.

Each chosen message travels with the tail of the model's reply before it: a correction without the
thing it corrects cannot be understood.

Where the messages come from: a user turn is a `user` chunk of the main session, OR one of the turns
glued into a `conversation` chunk. The indexer glues short neighbouring turns into one chunk with
their roles as prefixes ("user: …\\n\\nassistant: …", index.TURN_SEPARATOR); in the week before this
module 238 of the user's 283 messages sat inside such chunks, invisible to the harvest. They are split
back here along those prefixes — the index and its schema stay as they are.

Never read: anything under an `agent:` role (a subagent's transcript — its "user" is the manager's
brief) and the prompt of a scheduled task (facts.AUTOMATED_PREFIXES).

Dry run on the real archive (read only, no model):
    uv --directory C:\\dev\\claude-worker\\lore run python -m lore.selection [--dni 7] [--probki PLIK]
"""

from __future__ import annotations

import math
import random
import re
import sqlite3
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

from .db import DB_PATH, log, ts_to_local
from .index import MIXED_ROLE, OVERLAP, TURN_SEPARATOR
from .masking import mask

CORRECTION, REPETITION, REMEMBER = "poprawka", "powtorzenie", "zapamietaj"
REASONS = (CORRECTION, REPETITION, REMEMBER)

# The roles of the MAIN session. A glued chunk of a subagent is "agent:conversation" and never
# matches; its turns are the manager's brief and the subagent's work, not the user.
USER_ROLE, REPLY_ROLE = "user", "assistant"
MAIN_ROLES = (USER_ROLE, MIXED_ROLE)  # the only rows a user message can live in
_TURN = re.compile(r"(?:^|" + re.escape(TURN_SEPARATOR) + r")(user|assistant|tool|result|summary): ")
AUTOMATED_PREFIXES = ("<scheduled-task",)  # kept equal to facts.AUTOMATED_PREFIXES by a test

# What the model gets of one message. Pastes are the problem: the archive holds user messages of
# 15 000 - 72 000 characters (Seller Central pages, support mails, console dumps), and one of them
# would eat the whole budget of a day. The user types his own words before and after a paste, so the
# head and the tail are kept, the middle is cut OUT LOUD (the marker says how much). The detection
# looks at the same two zones (of the message without its tagged pastes, see searched()), so what
# made a message chosen is in what the model reads — short of a trigger typed in the middle of a
# message longer than both zones together, next to a tagged paste: rare, and accepted.
HEAD_CHARS, TAIL_CHARS = 700, 500
# The tail of the model's reply before the message. A correction answers the END of a reply — its
# last claim or question — so the tail is the part worth paying for. 200 characters is one or two
# sentences (~65 tokens). Measured on the week before 2026-09-24 (28 chosen messages, median 80
# characters): the whole material at 100 / 200 / 300 / 400 characters of context is 8 557 / 11 282 /
# 13 982 / 16 682 characters. At 200 the context is half of the bill; 100 is about half a sentence,
# too little to carry the claim being corrected — judge by the samples of the dry run.
REPLY_CHARS = 200
OPENING_CHARS = 160  # "at the beginning of the message" — the corrections open with it

_PL = str.maketrans("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ", "acelnoszzACELNOSZZ")
_IMAGE = re.compile(r"^(?:\s*\[image #\d+\]\s*)+", re.I)
# What the user pasted is not what the user said — often it is the agent's own earlier answer,
# with the agent's "za dużo" and "pamiętaj" in it. Claude Code wraps a big paste in these tags.
_PASTE = re.compile(r"<pasted_content\b.*?(?:</pasted_content[^>]*>|$)", re.S | re.I)


def fold(text: str) -> str:
    """Lower case, Polish letters without their tails: 'źle' and 'zle' are the same word here.

    The user often types without the tails, often with them, often half and half; the patterns are
    written once, tail-less, and match both.
    """
    return text.translate(_PL).lower()


def zones(text: str) -> str:
    """The head and the tail of a long message, the only parts that are searched and sent."""
    if len(text) <= HEAD_CHARS + TAIL_CHARS:
        return text
    return text[:HEAD_CHARS] + "\n" + text[-TAIL_CHARS:]


def searched(text: str) -> str:
    """What the signal patterns look at: the user's own words — tagged pastes out, then the zones."""
    return fold(zones(_PASTE.sub(" ", text)))


def trimmed(text: str) -> str:
    """The message as the model reads it — the cut in the middle is marked, never silent."""
    if len(text) <= HEAD_CHARS + TAIL_CHARS:
        return text
    cut = len(text) - HEAD_CHARS - TAIL_CHARS
    return f"{text[:HEAD_CHARS]} […wycięto {cut} znaków ze środka…] {text[-TAIL_CHARS:]}"


def opening(text: str) -> str:
    """The first words the user typed: images and pasted blocks in front of them do not count."""
    head = _PASTE.sub(" ", _IMAGE.sub("", text[:HEAD_CHARS]))
    return fold(head.lstrip(" \t\r\n\"'„>@-*"))[:OPENING_CHARS]


# ---------------------------------------------------------------- the three signals

# Built on the real archive, 2026-09-24: every pattern below was checked against the user's own
# messages, typos included ("nei", "przeiz", "ustaliloismy", "zapmaietaj", "sobei", "pamioetaj").
# Deliberately NOT a correction: "nie rozumiem" (14 messages opened with it — confusion about what
# the agent said, not a claim about how things are), a bare "czemu …?" (mostly real questions),
# "nie wiem", "nie mam" (reports, not corrections).
_NEG_VERB = (r"(?:rob|pisz|tworz|dawaj|dodawaj|ruszaj|zmieniaj|usuwaj|wysylaj|dotykaj|kasuj|wywalaj|"
             r"instaluj|commituj|pushuj|wdrazaj|uzywaj|sciagaj|pytaj|odpalaj|uruchamiaj|zgaduj|"
             r"wymyslaj|kombinuj|zmyslaj|mieszaj|licz|dziel|wstawiaj|pokazuj|\w{2,}aj|\w{2,}uj)\b")
CORRECTION_OPENINGS = re.compile(
    r"^(?:(?:a|no|ale|oj)\s+)?(?:"
    r"n+(?:ie|ei)+\s*[,.!;:\-–]"  # "nie," "nie." "nie!" — a bare no ("nnie" is a typo of it)
    r"|n+(?:ie|ei)\s+n(?:ie|ei)\b"  # "nie nie"
    r"|n+(?:ie|ei)\s+(?:tak|o\s+to|to\b|ten\b|ta\b|te\b|tu\b|tam\b|tym\b|tego\b|chodzi|chce|chcialem|"
    r"zgadzam|prawda|do\s+konca|jest\s+to|ma\s+(?:byc|opcji|sensu)|mialo|mial|mowilem|pisalem|"
    r"musisz|wolno|mozna|powinno|powinienes|" + _NEG_VERB + r")"
    r"|zle\b|bledn|bzdur"
    r"|kurw|kurde|ja\s+pierd|jprdl|wtf|co\s+(?:ty|jest\s+kurwa)|halo\b|serio\s*\?|obudz"
    r"|(?:ma|maja|mial|miala|mialo|mialy)\s+byc\b"
    r"|(?:czemu|dlaczego)\s+(?:znowu|znow|nadal|ciagle|dalej|wciaz)"
    r"|to\s+(?:na\s+pewno\s+)?n(?:ie|ei)\s+(?:tak|to\b|ten\b|ta\b|jest\s+(?:to|tak|prawda|blad))"
    r"|przestan"
    r")"
)
CORRECTION_ANYWHERE = re.compile(
    r"\bprzeci(?:ez|esz|z|rz|e)\b|\bprzeiz\b"  # "przecież" and the ways it gets typed
    r"|\b(?:juz\s+)?(?:ci\s+)?(?:mowil(?:em|am)|mowilem|pisal(?:em|am)\s+(?:ci|juz)|"
    r"tlumaczyl(?:em|am)|wytlumac\w*(?:em|am)|podawal(?:em|am)\s+ci|podal(?:em|am)\s+ci)\b"
    r"|\bustal\w{0,5}smy\b"  # ustalilismy, ustaliloismy
    r"|\bile\s+razy\b|\bpo\s+raz\s+(?:kolejny|drugi|trzeci|enty)\b|\bkolejny\s+raz\b"
    r"|\bczemu\s+znowu\b|\bznowu\s+(?:to\s+samo|nie\b|zle|ten\s+sam)"
    r"|\bmial[aoy]?\s+byc\b"
    r"|\bnie\s+tak\s+(?:mialo|mial|mowilem|jak\s+(?:mowilem|chcialem|pisalem))\b"
    r"|\bnie\s+o\s+to\s+(?:chodzi|mi)\b|\bnie\s+chodzi\s+mi\b|\bchodzilo\s+mi\b"
    r"|\bco\s+ty\s+(?:robisz|pierdol\w*|wyprawiasz|gadasz|piszesz|wymyslasz|odpierdal\w*)\b"
    r"|\bobudz\s+sie\b|\bogarnij\s+sie\b|\bnie\s+rozumiesz\b|\bzapomnij\s+o\b|\bpo\s+c?huj\b"
    r"|\bprzestan\w*|\bmial(?:es|as)\b|\bzostaw\b[^.?!\n]{0,30}\bw\s+spokoju\b"
    r"|\bza\s+(?:duzo|duze|dlugie|dlugi|malo)\b"  # "o 1200 znaków za duże" — the output was wrong
    r"|\bkurw\w*|\bpierd\w*|\bspierdol\w*|\bc?huj\w*|\bjeban\w*|\bzjeb\w*"
    r"|\bwkurw\w*|\bdenerwuj\w*|\bdebil\w*"
)
REMEMBER_PATTERNS = re.compile(
    r"\bza\w{0,2}m\w{1,3}t\s?aj(?:cie)?\b"  # zapamietaj, zapamiętaj, zapmaietaj
    r"|\bpam\w{0,2}etaj(?:cie)?\b"  # pamietaj, pamiętaj, pamioetaj — not "pamietasz", not "pamietam"
    r"|\bmusisz\s+(?:to\s+)?(?:za)?pamietac\b"
    r"|\bzapisz\s+(?:\w+\s+){0,2}?sob\w*"  # zapisz sobie, zapisz go sobie, zapisz sobei
    r"|\bzapisz\s+to\b(?!\s+(?:do|w)\s+(?:planu|pliku|todo|repo|bazy|excel\w*|csv|arkusz\w*))"
    r"|\bzapisz\b[^.?!\n]{0,40}\b(?:pamieci|wiedzy|claude\.?md|agents\.?md|zasad\w*|regul\w*)"
    r"|\bzanotuj\b|\bnie\s+zap+om\w*n\w*\b|\bmiej\s+na\s+uwadze\b"
    r"|\bod\s+(?:teraz|dzis|dzisiaj)\b[^.?!\n]{0,60}\b(?:zawsze|nigdy|masz|chce|chcialbym)\b"
)


def is_remember(text: str) -> bool:
    """An explicit "remember this" — it goes whether or not anything else speaks for it."""
    return bool(REMEMBER_PATTERNS.search(searched(text)))


def is_correction(text: str, reply: str) -> bool:
    """The user correcting the agent. Only right after a reply of the model: the first message of a
    conversation corrects nothing, whatever words it opens with."""
    if not reply:
        return False
    return bool(CORRECTION_OPENINGS.search(opening(text))
                or CORRECTION_ANYWHERE.search(searched(text)))


# ---------------------------------------------------------------- messages out of the chunks

@dataclass
class Message:
    """One message of the user, cut out of whatever chunk it was stored in."""
    chunk_id: int
    file: str
    line: int
    session: str
    said: str  # `ts` — for a glued chunk the moment of its first turn
    landed: str
    text: str
    reply: str = ""  # the model's reply right before it, '' when there was none
    reasons: list[str] = field(default_factory=list)
    echo: str = ""  # a repetition: when the user said the same thing in the other conversation

    def piece(self) -> str:
        """What the model reads: when, why, the end of the reply, the message itself."""
        why = ", ".join(self.reasons)
        if self.echo:
            why += f" (to samo mówił już w innej rozmowie {ts_to_local(self.echo)[:10]})"
        return f"[{ts_to_local(self.said)}] {why}\n{self.context()}user: {redact(trimmed(self.text))}"

    def context(self) -> str:
        """The line with the end of the model's reply — '' when the message follows no reply."""
        reply = " ".join(self.reply.split())[-REPLY_CHARS:]
        return f"model: …{redact(reply)}\n" if reply else ""


# rows are (id, ts, session, file, line, part, role, text, landed)
Row = tuple


def turns(role: str, text: str) -> list[tuple[str, str]]:
    """A chunk -> its turns. A glued chunk carries every turn's role as a prefix; anything else is
    one turn of its own role. A user turn that itself contained "\\n\\nassistant: " would be split
    there — it never happened in the archive, and the price would be half a message, not a wrong one."""
    if role != MIXED_ROLE:
        return [(role, text)]
    parts = _TURN.split(text)
    return [(parts[i], parts[i + 1]) for i in range(1, len(parts) - 1, 2)]


def automated(text: str) -> bool:
    return text.lstrip().startswith(AUTOMATED_PREFIXES)


def messages(rows: list[Row]) -> list[Message]:
    """The user's messages of the main session, in the order of the rows, each with the reply it
    follows when that reply is among the rows. Parts of one long message (one turn cut into several
    chunks, overlapping by index.OVERLAP) are glued back into one."""
    out: list[Message] = []
    reply: dict[str, str] = {}  # file -> the last reply of the model seen in it
    for cid, ts, session, file, line, part, role, text, landed in rows:
        if role not in (*MAIN_ROLES, REPLY_ROLE):
            continue
        if role == USER_ROLE and part and out and (out[-1].file, out[-1].line) == (file, line):
            out[-1].text += text[OVERLAP:]  # the next part of the same message
            continue
        if role == REPLY_ROLE:
            reply[file] = text if not part else reply.get(file, "") + text[OVERLAP:]
            continue
        for who, said in turns(role, text):
            if who == REPLY_ROLE:
                reply[file] = said
            elif who == USER_ROLE and said.strip() and not automated(said):
                out.append(Message(cid, file, line, session, ts, landed, said, reply.get(file, "")))
    return out


def previous_reply(conn: sqlite3.Connection, msg: Message) -> str:
    """The reply before a message that opens the window — it was indexed in an earlier pass."""
    rows = conn.execute(
        "SELECT role, text FROM chunks WHERE file = ? AND line < ? AND role IN (?, ?)"
        " ORDER BY line DESC, part DESC LIMIT 5", (msg.file, msg.line, REPLY_ROLE, MIXED_ROLE),
    ).fetchall()
    for role, text in rows:
        said = [t for who, t in turns(role, text) if who == REPLY_ROLE]
        if said:
            return said[-1]
    return ""


# ---------------------------------------------------------------- repetitions, without a model

# Why letters and not the stored vectors: (1) the vectors of the archive are being converted to
# another model right now (lore.migrate), and a threshold measured on one model means nothing on the
# other; (2) the glued chunks, where most of the user's recent messages live, have ONE vector for
# the user and the model together — the user's own sentence has no vector of its own; (3) the user
# types with many typos, which character trigrams forgive and words do not.
#
# The threshold, measured 2026-09-24 on 1 172 messages of 40-800 characters since 2026-08-01, each
# against every earlier one of another conversation (cosine of tf-idf character trigrams):
#   >= 0.90   8 pairs — ALL the same text within a day: one conversation carried into a new window
#             (resume / fork), not the user repeating himself — hence COPY_* below;
#   0.50-0.90 15 pairs — mostly the same fact said again ("sroper jest tu github…/sroper",
#             "WMS_Official tu jest nasz magazyn", the Primo2966 account and its e-mail);
#   0.40-0.50 19 pairs — about half of them real ("jfamazon.7m.pl usunięte, zapomnij o tej domenie");
#   0.35-0.40 27 pairs — nearly all only the same topic ("sprawdź czy live…"), not the same claim.
# 0.40 keeps ~34 pairs in 55 days, about one message every two days.
ECHO_THRESHOLD = 0.40
COPY_SIMILARITY, COPY_HOURS = 0.90, 48
# Typed messages only. Above ~800 characters a message is a paste (Seller Central pages, support
# mails, console output) and pastes repeat by their nature: measured with them in, pasted pages
# topped the list. Below 40 it is "tak, rób dalej", which repeats in every conversation.
ECHO_MIN_CHARS, ECHO_MAX_CHARS = 40, 800
_COMMON_SHARE = 0.5  # a trigram in more than half of the messages says nothing about any of them
# The weights are corpus statistics: on a handful of messages every shared trigram is "common" and
# nothing ever looks repeated. Below this the log says so instead of the count silently being zero.
MIN_ARCHIVE = 50
MEASURED_ON = "1 172 messages"


def _normal(text: str) -> str:
    return " ".join(re.findall(r"[a-z0-9]+", fold(text)))


def _trigrams(text: str) -> Counter:
    t = f" {_normal(text)} "
    return Counter(t[i:i + 3] for i in range(len(t) - 2))


def echo_candidate(text: str) -> bool:
    return ECHO_MIN_CHARS <= len(text.strip()) <= ECHO_MAX_CHARS


def _hours(a: str, b: str) -> float:
    try:
        return abs((datetime.fromisoformat(a.replace("Z", "+00:00"))
                    - datetime.fromisoformat(b.replace("Z", "+00:00"))).total_seconds()) / 3600
    except ValueError:
        return math.inf


class Echoes:
    """Everything the user has typed in the archive, searchable by 'did he say this before'."""

    def __init__(self, archive: list[Message]):
        self.docs = [m for m in archive if echo_candidate(m.text)]
        if len(self.docs) < MIN_ARCHIVE:
            log(f"only {len(self.docs)} typed messages in the archive — too few to tell a repeated"
                f" claim from common words (the threshold was measured on {MEASURED_ON});"
                f" repetitions will rarely be found until the archive grows")
        grams = [_trigrams(m.text) for m in self.docs]
        df = Counter(g for doc in grams for g in doc)
        n = max(1, len(self.docs))
        self.idf = {g: math.log(n / c) for g, c in df.items() if c <= _COMMON_SHARE * n}
        self.postings: dict[str, list[tuple[int, float]]] = defaultdict(list)
        for i, doc in enumerate(grams):
            for g, w in self._vector(doc).items():
                self.postings[g].append((i, w))

    @classmethod
    def of(cls, conn: sqlite3.Connection) -> "Echoes":
        rows = conn.execute(
            "SELECT id, ts, session, file, line, part, role, text, indexed_at FROM chunks"
            " WHERE role IN (?, ?) ORDER BY file, line, part", MAIN_ROLES,
        ).fetchall()
        return cls(messages(rows))

    def _vector(self, doc: Counter) -> dict[str, float]:
        v = {g: (1 + math.log(c)) * self.idf[g] for g, c in doc.items() if g in self.idf}
        norm = math.sqrt(sum(x * x for x in v.values())) or 1.0
        return {g: x / norm for g, x in v.items()}

    def best(self, msg: Message) -> tuple[float, str]:
        """(similarity, when) of the closest earlier message of ANOTHER conversation."""
        if not echo_candidate(msg.text):
            return 0.0, ""
        score: dict[int, float] = defaultdict(float)
        for g, w in self._vector(_trigrams(msg.text)).items():
            for i, x in self.postings.get(g, ()):
                score[i] += w * x
        top, when = 0.0, ""
        for i, s in score.items():
            other = self.docs[i]
            if other.session == msg.session or other.said >= msg.said or s <= top:
                continue
            if s >= COPY_SIMILARITY and _hours(other.said, msg.said) < COPY_HOURS:
                continue  # the same conversation carried into a new window, not a repetition
            top, when = s, other.said
        return top, when

    def find(self, msg: Message) -> str:
        """When the user already said this in another conversation; '' when he did not."""
        s, when = self.best(msg)
        return when if s >= ECHO_THRESHOLD else ""


# ---------------------------------------------------------------- the choice

@dataclass
class Choice:
    reviewed: list[Message]  # every message of the user in the rows
    chosen: list[Message]  # the ones worth a model's time, in the order of the rows
    duplicates: int = 0  # the same message twice in one conversation of the batch, sent once

    def counts(self) -> Counter:
        return Counter(r for m in self.chosen for r in m.reasons)


def reasons(msg: Message, echoes: "Echoes | None") -> list[str]:
    """Why a message is worth reading — empty when it is not."""
    out = []
    if is_correction(msg.text, msg.reply):
        out.append(CORRECTION)
    if echoes is not None:
        msg.echo = echoes.find(msg)
        if msg.echo:
            out.append(REPETITION)
    if is_remember(msg.text):
        out.append(REMEMBER)
    return out


def choose(conn: sqlite3.Connection, rows: list[Row], echoes: "Echoes | None" = None) -> Choice:
    """The messages of the rows, and which of them go to the model."""
    reviewed, stored = [], set()
    for msg in messages(rows):
        # one conversation stored under two files (Orca keeps its own copy of the transcript):
        # the same words at the same moment are one message, reviewed once
        key = (msg.said, _normal(msg.text))
        if key not in stored:
            stored.add(key)
            reviewed.append(msg)
    for msg in reviewed:
        if not msg.reply:  # the reply sits in a chunk of an earlier pass — one indexed lookup
            msg.reply = previous_reply(conn, msg)
    if echoes is None and any(echo_candidate(m.text) for m in reviewed):
        echoes = Echoes.of(conn)
    chosen, seen, duplicates = [], set(), 0
    for msg in reviewed:
        msg.reasons = reasons(msg, echoes)
        if not msg.reasons:
            continue
        # the same words twice in ONE conversation are sent once; in two conversations they stay
        # two — which conversations a fact was heard in is the evidence lore.verify promotes by
        key = (msg.session, _normal(msg.text))
        if key in seen:
            duplicates += 1
            continue
        seen.add(key)
        chosen.append(msg)
    return Choice(reviewed, chosen, duplicates)


# ---------------------------------------------------------------- secrets

# The archive is masked when it is indexed (lore.masking), and still a key slipped through: a token
# pasted with "zapisz sobie ten klucz" — exactly the kind of message this module picks. Whatever
# looks like a key does not reach the model: a fact built from it would ride in the rules for months.
_LONG_TOKEN = re.compile(r"(?<![\w/])(?=[\w\-]*\d)(?=[\w\-]*[A-Za-z])[\w\-]{20,}(?![\w/])")
_SECRET_WORD = re.compile(r"(?i)\b(has[lł]o|haslo|password|passwd|pass|token|klucz\w*|key|pin)"
                          r"(\s*[:=]?\s*)(\S{6,})")


def redact(text: str) -> str:
    """lore.masking plus the long mixed tokens it missed, and whatever follows 'hasło'/'token'."""
    return _SECRET_WORD.sub(lambda m: m.group(1) + m.group(2) + "[MASKED]",
                            _LONG_TOKEN.sub("[MASKED]", mask(text)))


_SHORT_SECRET = re.compile(r"(?<![\w/])(?=\S*\d)(?=\S*[A-Za-z])[A-Za-z0-9$!@#%^&*_\-]{8,}(?![\w/])")


def redact_sample(text: str) -> str:
    """For the samples a human reads in a file: harsher still — any word mixing letters and digits.
    A SKU or an ASIN masked there costs nothing; a password shown there is out for good."""
    return _SHORT_SECRET.sub("[MASKED]", redact(text))


# ---------------------------------------------------------------- the dry run

def _old_rule(rows: list[Row]) -> tuple[int, int]:
    """What the harvest before this module would have sent: every pure `user` chunk, whole."""
    kept = [(ts, text) for _, ts, _, _, _, _, role, text, _ in rows
            if role == USER_ROLE and not automated(text)]
    return len(kept), sum(len(f"[{ts_to_local(ts)}] user: {text}") for ts, text in kept)


def dry_run(conn: sqlite3.Connection, days: int = 7, samples: int = 10, seed: int = 7) -> dict:
    """The new rules against the old ones on the last `days` days of the archive — nothing written."""
    since = (datetime.now(timezone.utc) - timedelta(days=days)).isoformat(timespec="milliseconds")
    since = since.replace("+00:00", "Z")
    rows = conn.execute(
        "SELECT id, ts, session, file, line, part, role, text, indexed_at FROM chunks"
        " WHERE ts >= ? ORDER BY file, line, part", (since,),
    ).fetchall()
    choice = choose(conn, rows)
    old_messages, old_chars = _old_rule(rows)
    chars = sum(len(m.piece()) for m in choice.chosen)
    context = sum(len(m.context()) for m in choice.chosen)
    rejected = [m for m in choice.reviewed if not m.reasons]
    rng = random.Random(seed)
    lengths = sorted(len(m.text) for m in choice.chosen)
    return {
        "since": since, "days": days, "rows": len(rows),
        "old_messages": old_messages, "old_chars": old_chars,
        "reviewed": len(choice.reviewed), "chosen": len(choice.chosen),
        "duplicates": choice.duplicates, "counts": choice.counts(), "chars": chars,
        "context_chars": context,
        "median_chosen": lengths[len(lengths) // 2] if lengths else 0,
        "in_glued": sum(1 for m in choice.reviewed if m.text and _in_glued(rows, m)),
        "chosen_sample": rng.sample(choice.chosen, min(samples, len(choice.chosen))),
        "rejected_sample": rng.sample(rejected, min(samples, len(rejected))),
    }


def _in_glued(rows: list[Row], msg: Message) -> bool:
    return any(r[0] == msg.chunk_id and r[6] == MIXED_ROLE for r in rows)


def _line(text: str, limit: int = 180) -> str:
    one = " ".join(redact_sample(text).split())
    return one if len(one) <= limit else one[:limit].rstrip() + "…"


def report(r: dict) -> str:
    counts = r["counts"]
    out = [
        f"# Próba na sucho: wybór materiału do nauki — ostatnie {r['days']} dni",
        "",
        f"Archiwum od {r['since'][:16]} UTC, {r['rows']} kawałków. Nic nie zapisano, model nie był wołany.",
        "",
        "| | stare reguły | nowe reguły |",
        "|---|---|---|",
        f"| wiadomości użytkownika widziane | {r['old_messages']} (tylko kawałki `user`) |"
        f" {r['reviewed']} (w tym {r['in_glued']} z kawałków `conversation`) |",
        f"| wiadomości do modelu | {r['old_messages']} | {r['chosen']} |",
        f"| znaki do modelu | {r['old_chars']} | {r['chars']} (w tym kontekst odpowiedzi: {r['context_chars']}) |",
        "",
        f"Powody (jedna wiadomość może mieć kilka): poprawka {counts.get(CORRECTION, 0)},"
        f" powtórzenie {counts.get(REPETITION, 0)}, zapamiętaj {counts.get(REMEMBER, 0)}."
        f" Wysłane raz, choć padły dwa razy w jednej rozmowie: {r['duplicates']}."
        f" Mediana długości wybranej wiadomości: {r['median_chosen']} znaków.",
        "",
        f"## {len(r['chosen_sample'])} losowych WYBRANYCH",
        "",
    ]
    for m in r["chosen_sample"]:
        out.append(f"- [{ts_to_local(m.said)[:10]}] ({', '.join(m.reasons)}) {_line(m.text)}")
        if m.reply:
            out.append(f"  - odpowiada na: …{_line(m.reply[-REPLY_CHARS:], 120)}")
    out += ["", f"## {len(r['rejected_sample'])} losowych ODRZUCONYCH", ""]
    out += [f"- [{ts_to_local(m.said)[:10]}] {_line(m.text)}" for m in r["rejected_sample"]]
    out += ["", "Sekrety zamaskowane: wszystko, co wygląda na klucz, token albo hasło → [MASKED]."]
    return "\n".join(out) + "\n"


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    days = int(argv[argv.index("--dni") + 1]) if "--dni" in argv else 7
    path = Path(argv[argv.index("--probki") + 1]) if "--probki" in argv else None
    if not DB_PATH.exists():
        log(f"no database at {DB_PATH}")
        return 1
    from .mining import open_readonly  # here, not above: mining imports facts, which imports us
    conn = open_readonly()
    try:
        r = dry_run(conn, days)
    finally:
        conn.close()
    text = report(r)
    if path:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        log(f"samples written to {path}")
    log(f"old rules: {r['old_messages']} messages, {r['old_chars']} chars;"
        f" new rules: {r['chosen']} of {r['reviewed']} messages, {r['chars']} chars")
    return 0


if __name__ == "__main__":
    sys.exit(main())
