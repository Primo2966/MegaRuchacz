"""Step 2: turn the private label file into the committed test set (queries.jsonl).

    python build_set.py                      # reads LORE_BENCH_DIR/spec.jsonl
    python build_set.py --spec other.jsonl

Why two files. The repository is public, and the questions are verbatim messages from the
user's own conversations (SKUs, suppliers, prices, account ids). So the readable labels stay in
spec.jsonl next to the database copy, and the repository gets only pointers: which chunk the
question was cut from (chunk id + character range + hash) and which chunk ids count as a hit.
Everything is reproducible on the machine that owns the archive and says nothing to anyone else.

A spec line:
    {"id": "pl01", "lang": "pl|de|en|code", "kind": "...", "src": <chunk id the question comes from>,
     "q": "<verbatim substring of that chunk>", "ans": "<regex a correct hit must match>",
     "roles": [optional list of roles a hit may have]}

Rules applied here, the same for every model:
- the archive "as of the question": only chunks older than the question, minus the last two
  hours of the same session (that part was still in the conversation's own context);
- chunks that contain the question itself (copies, other transcripts of the same session) are
  excluded from the pool - finding your own question is not a hit;
- a hit is any remaining chunk matching `ans`. A question with no hit is refused, loudly.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timedelta
from pathlib import Path

from common import QUERIES_FILE, bench_dir, log, open_copy, sha1

MAX_RELEVANT_SHARE = 0.01  # an answer pattern matching over 1% of the archive is not an answer


def _norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip().lower()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", type=Path, default=None)
    a = ap.parse_args()
    spec_path = a.spec or bench_dir() / "spec.jsonl"
    specs = [json.loads(l) for l in spec_path.read_text(encoding="utf-8").splitlines() if l.strip()]

    conn = open_copy()
    rows = conn.execute("SELECT id, ts, session, file, line, role, text FROM chunks").fetchall()
    by_id = {r[0]: r for r in rows}
    norm_text = {r[0]: _norm(r[6]) for r in rows}
    total = len(rows)

    out, problems, seen_ids = [], [], set()
    for s in specs:
        sid = s["id"]
        if sid in seen_ids:
            problems.append(f"{sid}: duplicate id")
            continue
        seen_ids.add(sid)
        src = by_id.get(s["src"])
        if not src:
            problems.append(f"{sid}: source chunk {s['src']} not in the copy")
            continue
        start = src[6].find(s["q"])
        if start < 0:
            problems.append(f"{sid}: query is not a verbatim substring of chunk {s['src']}")
            continue
        qts, qsession = src[1], src[2]
        near = (datetime.fromisoformat(qts.replace("Z", "+00:00")) - timedelta(hours=2)).strftime(
            "%Y-%m-%dT%H:%M:%S.000Z")
        probe = _norm(s["q"])[:60]
        rx = re.compile(s["ans"], re.I | re.S)
        roles = set(s.get("roles") or [])
        exclude, relevant = [], []
        for r in rows:
            cid, ts, session = r[0], r[1], r[2]
            if not (ts < qts and (session != qsession or ts < near)):
                continue
            if probe in norm_text[cid]:
                exclude.append(cid)
                continue
            if rx.search(r[6]) and (not roles or r[5] in roles):
                relevant.append(cid)
        if not relevant:
            problems.append(f"{sid}: no chunk in the archive before the question matches the answer pattern")
            continue
        if len(relevant) > MAX_RELEVANT_SHARE * total:
            problems.append(f"{sid}: answer pattern matches {len(relevant)} chunks - too generic to mean anything")
            continue
        turns = {(by_id[c][3], by_id[c][4]) for c in relevant}
        out.append({
            "id": sid, "lang": s["lang"], "kind": s["kind"],
            "src": s["src"], "q_start": start, "q_end": start + len(s["q"]), "q_sha1": sha1(s["q"]),
            "query_ts": qts, "query_session": qsession,
            "relevant": sorted(relevant), "relevant_turns": len(turns), "exclude": sorted(exclude),
        })
        log(f"{sid} [{s['lang']}] relevant chunks={len(relevant)} turns={len(turns)} excluded={len(exclude)}")

    for p in problems:
        log("REFUSED " + p)
    QUERIES_FILE.write_text("".join(json.dumps(o, ensure_ascii=False) + "\n" for o in out), encoding="utf-8")
    langs = {}
    for o in out:
        langs[o["lang"]] = langs.get(o["lang"], 0) + 1
    log(f"written {len(out)} questions to {QUERIES_FILE} ({langs}); refused {len(problems)}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
