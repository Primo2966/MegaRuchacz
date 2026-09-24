"""Step 3: embed every chunk of the database copy with one model and time it.

    python embed_corpus.py e5-small
    python embed_corpus.py mmlw-roberta-base
    python embed_corpus.py mmlw-roberta-base --sample 2000   # throughput probe only, nothing saved

Same procedure as production (lore.db.embed_passages: sort by length, batches of 32, fastembed
ONNX on CPU), in slices of 2000 so progress is visible. The result goes to
LORE_BENCH_DIR/vectors-<model>.npz together with the wall-clock time; the database copy itself
is not modified.
"""

from __future__ import annotations

import argparse
import json
import random
import time

import numpy as np

from common import EMBEDDERS, QUERIES_FILE, bench_dir, embed_passages, embedder, log, open_copy, vectors_path

SLICE = 2000


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("model", choices=sorted(EMBEDDERS))
    ap.add_argument("--sample", type=int, default=0, help="embed a random sample, report speed, save nothing")
    ap.add_argument("--subset", type=int, default=0,
                    help="embed and SAVE a sample: every chunk the test set needs + random ones up to N "
                         "(evaluate.py then restricts all variants to it)")
    a = ap.parse_args()

    conn = open_copy()
    rows = conn.execute("SELECT id, text FROM chunks ORDER BY id").fetchall()
    conn.close()
    if a.sample:
        random.seed(7)
        rows = random.sample(rows, a.sample)
    elif a.subset:
        need = set()
        for line in QUERIES_FILE.read_text(encoding="utf-8").splitlines():
            need.update(json.loads(line)["relevant"])
        random.seed(7)
        rest = [r for r in rows if r[0] not in need]
        pick = need | {r[0] for r in random.sample(rest, max(0, a.subset - len(need)))}
        rows = [r for r in rows if r[0] in pick]
        log(f"subset: {len(need)} chunks required by the test set + {len(rows) - len(need)} random")
    ids = np.array([r[0] for r in rows], dtype=np.int64)
    texts = [r[1] for r in rows]
    chars = sum(len(t) for t in texts)

    embedder(a.model)  # load outside the timed part - loading is paid once per process, not per chunk
    parts = []
    t0 = time.perf_counter()
    for i in range(0, len(texts), SLICE):
        parts.append(embed_passages(a.model, texts[i:i + SLICE]))
        done = min(i + SLICE, len(texts))
        el = time.perf_counter() - t0
        log(f"{a.model}: {done}/{len(texts)} chunks, {el:.0f}s, {done / el:.1f} chunks/s")
    total = time.perf_counter() - t0
    matrix = np.vstack(parts)

    stats = {"model": a.model, "chunks": len(texts), "chars": chars, "seconds": round(total, 1),
             "chunks_per_s": round(len(texts) / total, 2), "sample": bool(a.sample), "subset": bool(a.subset)}
    log(json.dumps(stats))
    if a.sample:
        return
    np.savez(vectors_path(a.model), ids=ids, matrix=matrix)
    (bench_dir() / f"embed-time-{a.model}.json").write_text(json.dumps(stats), encoding="utf-8")


if __name__ == "__main__":
    main()
