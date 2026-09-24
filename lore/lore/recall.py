"""Automatic recall: a few archive fragments glued to every user message (UserPromptSubmit hook).

Why this exists: the model does not reach for lore_search on its own — in practice it was called
in roughly one session out of three, although the rules ask for it in every non-trivial one. So
the hook searches by itself and the model gets the best two or three hits as a lead.

Why full-text only (FTS5/BM25), without the vector model: this runs on EVERY enter and the budget
for the whole hook is under one second. Measured 2026-09-24 on the real database (56k chunks):
a bare Python start ~40-50 ms, the FTS query ~1 ms per term, the whole run 70-140 ms — while
loading the embedding model from scratch takes 4.7-7.4 s. A long-lived process holding the model
would fit the budget, but it is one more thing that must be alive, restarted and watched on two
machines. The price of the choice: no semantic matching — a hit needs the same words (or the same
word stem, see _terms) as the message; a question worded differently from the old conversation
finds nothing. That is why the threshold is strict: better nothing than noise on every message.

Deliberately standalone (stdlib only, no import of lore.db): importing lore.db pulls numpy
(0.15 s warm, over 1 s cold) and db.connect() WRITES (migrations, schema). Here the database is
opened read-only.

Protocol (the hook calls `python -m lore.recall`): JSON on stdin
    {"prompt": str, "session": str | None, "budget": int}
and one JSON line on stdout
    {"status": "hits" | "empty" | "skipped" | "error", "reason": str, "block": str, "ms": int}.
The block is never longer than `budget` characters.
"""

from __future__ import annotations

import json
import math
import os
import re
import sqlite3
import sys
import time
import unicodedata
from datetime import datetime, timezone
from pathlib import Path

DB_NAME = "lore.db"

# Only what people said and what was concluded. Tool calls and their output (half the archive)
# are raw file contents and command logs — they match many words and explain nothing; worker
# transcripts (agent:*) are long internal monologues of the same kind.
ROLES = ("user", "assistant", "summary", "conversation")
ROLE_LABEL = {"user": "uzytkownik", "assistant": "asystent", "summary": "streszczenie", "conversation": "rozmowa"}

# Below this many characters a message is an acknowledgement ("ok", "tak", ".", "dzieki"),
# not a question — searching for it only costs time and invites noise.
MIN_PROMPT_CHARS = 12
# A hit must share at least this many words with the message (two for a message with up to three
# searchable words, three above that), AND carry at least MIN_COVERAGE of their combined weight
# (idf). One shared word is a coincidence: in 56k chunks almost any single word matches
# something. Tuned on the ten sample messages in .claude/raporty/podpowiedz-z-archiwum.md —
# at 0.5 half of the hits were noise, at 0.6 one in ten.
MIN_MATCHED = 2
MIN_COVERAGE = 0.6
# Two hits whose windows share at least this part of their words tell the same thing (a rule
# restated in two conversations, a pasted message) — the second one is paid for and adds nothing.
SAME_TEXT = 0.4
# Both are counted inside one stretch of this many characters (see window()) — about two
# sentences, a little more than the snippet the model gets to see.
SCORE_WINDOW = 300
# A word found in more than this share of chunks is dropped from the search altogether. Not
# lower: the archive is dominated by a few projects, so their key words ("alibaba", "robot",
# "wiadomosc") are common — dropping them at 5 % left "dostawy" + "wyslal" and matched Amazon
# shipments to a question about the Alibaba robot. Common words stay, just with a low idf.
MAX_DF_SHARE = 0.25
# The rarest words describe the message best; more of them only dilutes the coverage.
MAX_TERMS = 8
CANDIDATES = 40
# Two, not three: whatever is glued in stays in the conversation history and is re-read on every
# later model call (see the budget in narzedzia/przypomnienie.js). The third hit was the weakest
# one in every sample, i.e. the most expensive per unit of use.
MAX_HITS = 2
# Shorter than this a fragment says nothing — better one readable hit than two stubs.
MIN_SNIPPET = 110
# Longer than this is a quote, not a lead; the full text is one lore_context call away.
MAX_SNIPPET = 240

HEADER = "Z ARCHIWUM (Lore, automat) - trop, nie dowod; moze byc nieaktualne. Calosc: lore_context(id)."

STOP = set("""
ale albo ani aby bardzo bez bo byc byl byla bylo byly bedzie beda bez chce chcesz ci cie co czy
czyli dla do dobrze gdy gdzie go ich ile im iz ja jak jaki jakie jako je jego jej jest jestem jesli
juz ktora ktore ktory kto lub ma mam mamy masz mi mnie moge moze mozna my na nad nam nas nic nie niech
nim no o od oraz po pod potem przez przy sa sie sobie tak tam tego tej ten teraz to tu tutaj tych tylko
ty wiec wszystko wtedy z za ze zeby zrob zrobic prosze dzieki okej ok the and for with that this from
are was were you your have has not but can will what how why when which into then than also just
sprawdz dlaczego czemu dodaj napisz ustaw dziala mowi powiedz pokaz zobacz trzeba musi mozesz dalej
jeszcze nowy nowa nowe wszystkie kazdy kazda kazde zamiast chodzi robi jakis sprawa rzecz
""".split())

_WORD = re.compile(r"\w+", re.UNICODE)
_SPACE = re.compile(r"\s+")


# ---------------------------------------------------------------- paths


def data_home() -> Path:
    """Where the database sits — the same rule as db._data_home (a test keeps the two in step).

    Copied instead of imported: lore.db imports numpy, and that alone can eat the whole budget.
    """
    chosen = os.environ.get("LORE_HOME") or os.environ.get("CLAUDE_HISTORIA_HOME")
    if chosen:
        return Path(chosen)
    previous = Path.home() / ".claude"
    if any((previous / name).exists() for name in (DB_NAME, "historia.db")):
        return previous
    return Path.home() / ".lore"


def open_readonly(path: Path) -> sqlite3.Connection:
    if not path.exists():
        raise FileNotFoundError(f"brak bazy {path}")
    conn = sqlite3.connect(f"file:{path.as_posix()}?mode=ro", uri=True, timeout=0.3)
    conn.execute("PRAGMA query_only=ON")
    return conn


# ---------------------------------------------------------------- text


def fold(text: str) -> str:
    """Lowercase without diacritics, character by character — the length stays the same, so a
    position found in the folded text is valid in the original (needed to cut the snippet)."""
    out = []
    for ch in text.lower():
        if ch == "ł":
            out.append("l")
            continue
        d = unicodedata.normalize("NFKD", ch)
        out.append(d[0] if d else ch)
    return "".join(out)


def _terms(prompt: str) -> list[str]:
    """Words worth searching for, as FTS terms. Longer words become a stem with `*`: Polish
    inflects, and "zapachy" has to find "zapach" and "zapachow" (the tokenizer does no stemming).
    Short words lose only a vowel ending ("ebayu" -> ebay*, "robot" -> robot*): cutting a
    consonant off a five-letter word turned "robot" into "robo*", which matches "robocza"."""
    out, seen = [], set()
    for w in _WORD.findall(fold(prompt)):
        if w.isdigit():
            if len(w) < 2:
                continue
            term = w
        else:
            if len(w) < 3 or w in STOP or "_" in w:
                continue
            if len(w) >= 7:
                term = w[:-2] + "*"
            elif len(w) >= 5:
                term = (w[:-1] if w[-1] in "aeiouy" else w) + "*"
            else:
                term = w
        if term not in seen:
            seen.add(term)
            out.append(term)
    return out


def _fts(term: str) -> str:
    return f'"{term[:-1]}"*' if term.endswith("*") else f'"{term}"'


def _occurrences(term: str, folded: str) -> list[int]:
    stem = term[:-1] if term.endswith("*") else term
    pat = r"\b" + re.escape(stem) + (r"" if term.endswith("*") else r"\b")
    return [m.start() for m in re.finditer(pat, folded)]


def window(folded: str, terms: list[str], width: int,
           weights: dict[str, float] | None = None) -> tuple[int, set[str]]:
    """Start of the `width`-long stretch of text holding the most (weight of) distinct words,
    and those words. Scoring by the window, not the whole chunk: a long chunk contains nearly
    every common stem somewhere, and words scattered over two thousand characters are not
    about the same thing."""
    hits = sorted((pos, t) for t in terms for pos in _occurrences(t, folded))
    best_start, best_terms, best_score = 0, set(), -1.0
    for pos, _ in hits:
        start = max(0, pos - width // 5)
        inside = {t for p, t in hits if start <= p < start + width}
        score = sum((weights or {}).get(t, 1.0) for t in inside)
        if score > best_score:
            best_start, best_terms, best_score = start, inside, score
    return best_start, best_terms


def snippet(text: str, terms: list[str], width: int, weights: dict[str, float] | None = None) -> str:
    """The piece of `text` of about `width` characters holding the most distinct matched words."""
    text = _SPACE.sub(" ", text).strip()
    if len(text) <= width:
        return text
    start, _ = window(fold(text), terms, width, weights)
    if start > 0:
        space = text.find(" ", start)
        start = space + 1 if 0 <= space < start + 20 else start
    end = min(len(text), start + width - 2)
    if end < len(text):
        space = text.rfind(" ", start, end)
        end = space if space > start + width // 2 else end
    return ("…" if start > 0 else "") + text[start:end].strip() + ("…" if end < len(text) else "")


def _project(name: str) -> str:
    name = re.sub(r"^[A-Za-z]--(dev-)?", "", name or "?")
    return name if len(name) <= 18 else "…" + name[-17:]


def _age_days(ts: str, now: datetime) -> tuple[str, int]:
    try:
        when = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return ts[:10], -1
    return when.astimezone().strftime("%Y-%m-%d"), max(0, (now - when).days)


def _age_label(days: int) -> str:
    if days < 0:
        return "data nieznana"
    if days == 0:
        return "dzis"
    if days == 1:
        return "wczoraj"
    return f"sprzed {days} dni"


# ---------------------------------------------------------------- search


def _nothing(status: str, reason: str) -> dict:
    return {"status": status, "reason": reason, "block": "", "ids": []}


def recall(prompt: str, session: str | None, budget: int, conn: sqlite3.Connection,
           exclude: list[int] | None = None, now: datetime | None = None) -> dict:
    """The block to glue in (possibly empty) plus why. Never raises for "nothing found".

    `session` — the conversation the message belongs to: its own chunks are an echo, not memory.
    `exclude` — chunk ids already glued into this conversation: they are still in its history,
    so repeating them costs money and adds nothing.
    """
    now = now or datetime.now(timezone.utc)
    if len(prompt.strip()) < MIN_PROMPT_CHARS:
        return _nothing("skipped", "krotka wiadomosc")
    terms = _terms(prompt)
    if len(terms) < MIN_MATCHED:
        return _nothing("skipped", "za malo slow do szukania")
    if budget < len(HEADER) + MIN_SNIPPET + 60:
        return _nothing("skipped", f"brak miejsca pod sufitem ({budget} znakow)")

    total = conn.execute("SELECT count(*) FROM chunks").fetchone()[0] or 1
    weights: dict[str, float] = {}
    for t in terms:
        df = conn.execute("SELECT count(*) FROM chunks_fts WHERE chunks_fts MATCH ?", [_fts(t)]).fetchone()[0]
        if df == 0 or df / total > MAX_DF_SHARE:
            continue
        # df below 3 is usually a typo or a one-off string; do not let it outweigh everything
        weights[t] = math.log(total / max(df, 3))
    if len(weights) < MIN_MATCHED:
        return _nothing("empty", "za malo slow wspolnych z archiwum")
    terms = sorted(weights, key=lambda t: -weights[t])[:MAX_TERMS]
    full = sum(weights[t] for t in terms)
    need = MIN_MATCHED if len(terms) <= 3 else MIN_MATCHED + 1

    roles = ",".join("?" * len(ROLES))
    rows = conn.execute(
        f"SELECT c.id, c.session, c.role, c.ts, c.project, c.text FROM chunks_fts x JOIN chunks c ON c.id = x.rowid "
        f"WHERE chunks_fts MATCH ? AND c.role IN ({roles}) AND c.session != ? "
        f"ORDER BY bm25(chunks_fts) LIMIT ?",
        [" OR ".join(_fts(t) for t in terms), *ROLES, session or "", CANDIDATES],
    ).fetchall()

    skip = set(exclude or [])
    scored, best = [], 0.0
    for rank, (cid, sess, role, ts, project, text) in enumerate(rows):
        if cid in skip:
            continue
        folded = fold(_SPACE.sub(" ", text))
        start, inside = window(folded, terms, SCORE_WINDOW, weights)
        matched = [t for t in terms if t in inside]
        coverage = sum(weights[t] for t in matched) / full
        best = max(best, coverage)
        if len(matched) >= need and coverage >= MIN_COVERAGE:
            words = set(_WORD.findall(folded[start:start + SCORE_WINDOW]))
            scored.append((-coverage, rank, cid, sess, role, ts, project, text, matched, words))
    scored.sort(key=lambda s: s[:2])

    hits, seen_sessions, taken = [], set(), []
    for neg, _, cid, sess, role, ts, project, text, matched, words in scored:
        if sess in seen_sessions:
            continue  # one voice per conversation
        if any(len(words & w) >= SAME_TEXT * min(len(words), len(w)) for w in taken):
            continue  # the same fact retold in another conversation: once is enough
        seen_sessions.add(sess)
        taken.append(words)
        hits.append((cid, role, ts, project, text, matched, -neg))
        if len(hits) >= MAX_HITS:
            break
    if not hits:
        return _nothing("empty", f"nic ponad prog ({len(rows)} kandydatow, najlepsze pokrycie {best:.2f})")

    block, used = _block(hits, budget, now, weights)
    if not block:
        return _nothing("skipped", f"trafienia sa, ale nie mieszcza sie w {budget} znakach")
    cover = ", ".join(f"#{h[0]}={h[6]:.2f}" for h in used)
    return {"status": "hits", "reason": f"{len(used)} z {len(rows)} kandydatow; pokrycie {cover}",
            "block": block, "ids": [h[0] for h in used]}


def _block(hits: list, budget: int, now: datetime, weights: dict[str, float] | None = None) -> tuple[str, list]:
    while hits:
        heads = []
        for cid, role, ts, project, *_ in hits:
            date, days = _age_days(ts, now)
            heads.append(f"- #{cid} {date} ({_age_label(days)}) {_project(project)}, {ROLE_LABEL.get(role, role)}: ")
        room = budget - len(HEADER) - sum(len(h) + 1 for h in heads)
        width = min(MAX_SNIPPET, room // len(hits))
        if width >= MIN_SNIPPET:
            lines = [h + snippet(hit[4], hit[5], width, weights) for h, hit in zip(heads, hits)]
            block = HEADER + "\n" + "\n".join(lines)
            if len(block) <= budget:
                return block, hits
        hits = hits[:-1]  # does not fit: drop the weakest hit instead of cutting all of them to stubs
    return "", []


# ---------------------------------------------------------------- entry point


def main() -> int:
    started = time.perf_counter()
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        req = json.loads(sys.stdin.buffer.read().decode("utf-8") or "{}")
        conn = open_readonly(data_home() / DB_NAME)
        try:
            out = recall(str(req.get("prompt") or ""), req.get("session"), int(req.get("budget") or 0), conn,
                         exclude=[int(x) for x in req.get("exclude") or []])
        finally:
            conn.close()
    except Exception as e:  # reported to the hook, which records it — not swallowed
        out = _nothing("error", f"{type(e).__name__}: {e}"[:200])
    out["ms"] = round((time.perf_counter() - started) * 1000)
    print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())

