"""Step 4: run every variant over the test set and write the numbers.

    python evaluate.py                 # all variants, results -> LORE_BENCH_DIR/results.json
    python evaluate.py --rerank-top 30

Search is a replica of lore/search.py (FTS5 BM25 top 30 + cosine top 30, RRF k=60, parts of one
turn shown once), run on the database copy "as of the question" (see build_set.py). A variant
with a reranker re-scores the first N fused candidates with a cross-encoder and keeps the rest
behind them.

Metrics, per question: rank of the first turn that contains a correct chunk. Hit@1/5/10 and
MRR@10, overall and split into Polish vs non-Polish questions. Latency per question, measured on
this CPU: query embedding + FTS + vector scan over the full matrix + reranking.
"""

from __future__ import annotations

import argparse
import json
import statistics
import time
from datetime import datetime, timedelta

import numpy as np

from common import (EMBEDDERS, QUERIES_FILE, RERANKERS, CrossEncoder, bench_dir, dir_size, embed_passages,
                    embed_query, export_dir, fts_channel, log, open_copy, rrf, sha1, vector_channel, vectors_path)

VARIANTS = [
    # name, embedder, reranker (None = no reranking), vectors source
    ("a  e5-small hybryda (dzis)", "e5-small", None),
    ("b  mmlw-roberta-base hybryda", "mmlw-roberta-base", None),
    ("c  mmlw + polish-reranker-base", "mmlw-roberta-base", "polish-reranker-base"),
    ("c2 mmlw + jina-reranker-v2-multi", "mmlw-roberta-base", "jina-reranker-v2-multi"),
    ("a2 e5-small + polish-reranker-base", "e5-small", "polish-reranker-base"),
    ("a3 e5-small + jina-reranker-v2-multi", "e5-small", "jina-reranker-v2-multi"),
]
DIAGNOSTIC = [("bm25 sam", None), ("wektory e5-small same", "e5-small"), ("wektory mmlw same", "mmlw-roberta-base")]


def load_queries(conn) -> list[dict]:
    qs = []
    for line in QUERIES_FILE.read_text(encoding="utf-8").splitlines():
        q = json.loads(line)
        text = conn.execute("SELECT text FROM chunks WHERE id=?", (q["src"],)).fetchone()
        if not text:
            raise SystemExit(f"{q['id']}: source chunk {q['src']} missing from the copy - archive changed")
        q["text"] = text[0][q["q_start"]:q["q_end"]]
        if sha1(q["text"]) != q["q_sha1"]:
            raise SystemExit(f"{q['id']}: question text differs from the one labelled - archive changed")
        qs.append(q)
    return qs


def production_e5(conn) -> tuple[np.ndarray, np.ndarray]:
    rows = conn.execute("SELECT chunk_id, emb FROM vectors ORDER BY chunk_id").fetchall()
    ids = np.fromiter((r[0] for r in rows), dtype=np.int64, count=len(rows))
    return ids, np.vstack([np.frombuffer(r[1], dtype=np.float32) for r in rows])


def load_matrix(conn, key: str) -> tuple[np.ndarray, np.ndarray, str]:
    p = vectors_path(key)
    if p.exists():
        z = np.load(p)
        return z["ids"], z["matrix"], "przeliczone w tym badaniu"
    if key == "e5-small":
        ids, m = production_e5(conn)
        return ids, m, "wektory z produkcyjnej bazy (kopia)"
    raise SystemExit(f"no vectors for {key} - run embed_corpus.py {key}")


def check_e5_matches_production(conn) -> float:
    """Our e5 pipeline must reproduce production vectors, or variant (a) is not what users get."""
    rows = conn.execute("SELECT c.id, c.text, v.emb FROM chunks c JOIN vectors v ON v.chunk_id=c.id "
                        "ORDER BY c.id LIMIT 64").fetchall()
    mine = embed_passages("e5-small", [r[1] for r in rows])
    prod = np.vstack([np.frombuffer(r[2], dtype=np.float32) for r in rows])
    return float((mine * prod).sum(axis=1).min())


class Pool:
    """Per-question candidate mask over one vector matrix (archive as of the question)."""

    def __init__(self, conn, ids: np.ndarray) -> None:
        meta = {r[0]: (r[1], r[2]) for r in conn.execute("SELECT id, ts, session FROM chunks")}
        self.ids = ids
        self.ts = np.array([meta[i][0] for i in ids])
        self.session = np.array([meta[i][1] for i in ids])

    def mask(self, q: dict) -> np.ndarray:
        near = (datetime.fromisoformat(q["query_ts"].replace("Z", "+00:00")) - timedelta(hours=2)
                ).strftime("%Y-%m-%dT%H:%M:%S.000Z")
        m = (self.ts < q["query_ts"]) & ((self.session != q["query_session"]) | (self.ts < near))
        if q["exclude"]:
            m &= ~np.isin(self.ids, np.array(q["exclude"], dtype=np.int64))
        return m


def turn_ranking(conn, chunk_order: list[int]) -> list[tuple]:
    seen, out = set(), []
    for cid in chunk_order:
        r = conn.execute("SELECT file, line FROM chunks WHERE id=?", (cid,)).fetchone()
        if r and r not in seen:
            seen.add(r)
            out.append(r)
    return out


def first_hit(conn, ranking: list[tuple], q: dict, cache: dict) -> int | None:
    key = q["id"]
    if key not in cache:
        cache[key] = {tuple(r) for r in conn.execute(
            f"SELECT file, line FROM chunks WHERE id IN ({','.join('?' * len(q['relevant']))})", q["relevant"])}
    rel = cache[key]
    for i, t in enumerate(ranking[:10]):
        if t in rel:
            return i + 1
    return None


def summarize(ranks: list[int | None]) -> dict:
    n = len(ranks)
    if not n:
        return {}
    return {
        "n": n,
        "top1": round(100 * sum(1 for r in ranks if r and r <= 1) / n, 1),
        "top5": round(100 * sum(1 for r in ranks if r and r <= 5) / n, 1),
        "top10": round(100 * sum(1 for r in ranks if r and r <= 10) / n, 1),
        "mrr10": round(sum(1 / r for r in ranks if r) / n, 3),
    }


def breakdown(qs: list[dict], ranks: list) -> dict:
    by = {"wszystkie": [], "PL": [], "nie-PL": []}
    for q, r in zip(qs, ranks):
        by["wszystkie"].append(r)
        by["PL" if q["lang"] == "pl" else "nie-PL"].append(r)
        by.setdefault(q["lang"], []).append(r)
    return {k: summarize(v) for k, v in by.items()}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rerank-top", type=int, default=30)
    a = ap.parse_args()

    conn = open_copy()
    qs = load_queries(conn)
    log(f"{len(qs)} questions")
    results = {"questions": len(qs), "rerank_top": a.rerank_top, "variants": {}, "diagnostic": {},
               "models": {}, "per_question": {}}

    cos = check_e5_matches_production(conn)
    results["e5_pipeline_vs_production_min_cosine"] = round(cos, 5)
    log(f"e5 pipeline vs production vectors: min cosine {cos:.5f}")
    if cos < 0.999:
        raise SystemExit("our e5 embedding does not reproduce production vectors - variant (a) would be wrong")

    matrices, pools, qvecs, qtimes = {}, {}, {}, {}
    for key in EMBEDDERS:
        ids, m, src = load_matrix(conn, key)
        matrices[key] = (ids, m)
        results["models"][key] = {"vectors": src, "chunks_with_vectors": int(len(ids)),
                                  "dim": int(m.shape[1])}
    # every variant searches the same archive: if one model was computed on a sample only,
    # the others (and BM25) are cut down to that sample too - otherwise the comparison is rigged
    common_ids = set.intersection(*(set(map(int, ids)) for ids, _ in matrices.values()))
    n_all = conn.execute("SELECT count(*) FROM chunks").fetchone()[0]
    allowed = None if len(common_ids) >= n_all else common_ids
    results["archive_used"] = len(common_ids)
    if allowed is not None:
        log(f"SAMPLE: all variants restricted to {len(common_ids)} of {n_all} chunks")
        lost = [q["id"] for q in qs if not set(q["relevant"]) & common_ids]
        if lost:
            raise SystemExit(f"the sample lacks every correct chunk for {lost} - rebuild the sample")
        for key, (ids, m) in list(matrices.items()):
            keep = np.isin(ids, np.fromiter(common_ids, dtype=np.int64))
            matrices[key] = (ids[keep], m[keep])
    full_scan = {}
    rng = np.random.default_rng(0)
    for key in EMBEDDERS:
        ids, m = matrices[key]
        pools[key] = Pool(conn, ids)
        # cosine scan at the FULL archive size, whatever sample the ranking used
        big = rng.standard_normal((n_all, m.shape[1]), dtype=np.float32)
        v = big[0]
        runs = []
        for _ in range(15):
            t = time.perf_counter()
            sc = big @ v
            np.argpartition(-sc, 29)[:30]
            runs.append(time.perf_counter() - t)
        full_scan[key] = statistics.median(runs)
        del big
        # the first call loads the model - not part of a query
        embed_query(key, "rozgrzewka")
        qvecs[key], qtimes[key] = [], []
        for q in qs:
            t = time.perf_counter()
            qvecs[key].append(embed_query(key, q["text"]))
            qtimes[key].append(time.perf_counter() - t)

    fts_lists, fts_times = [], []
    for q in qs:
        t = time.perf_counter()
        fts_channel(conn, q, q["text"], set(q["exclude"]))  # timed the production way (LIMIT 30)
        fts_times.append(time.perf_counter() - t)
        fts_lists.append(fts_channel(conn, q, q["text"], set(q["exclude"]), allowed=allowed))

    vec_lists, vec_times = {}, {}
    for key in EMBEDDERS:
        ids, m = matrices[key]
        vec_lists[key], vec_times[key] = [], []
        for q, v in zip(qs, qvecs[key]):
            t = time.perf_counter()
            mask = pools[key].mask(q)
            vec_lists[key].append(vector_channel(v, ids, m, mask))
            vec_times[key].append(time.perf_counter() - t)

    rel_cache: dict = {}
    texts = {}

    def chunk_text(cid: int) -> str:
        if cid not in texts:
            texts[cid] = conn.execute("SELECT text FROM chunks WHERE id=?", (cid,)).fetchone()[0]
        return texts[cid]

    for name, key in DIAGNOSTIC:
        ranks = []
        for i, q in enumerate(qs):
            order = fts_lists[i] if key is None else vec_lists[key][i]
            ranks.append(first_hit(conn, turn_ranking(conn, order), q, rel_cache))
        results["diagnostic"][name] = breakdown(qs, ranks)

    rerankers: dict = {}
    for name, key, rr in VARIANTS:
        ranks, lat, rr_times = [], [], []
        if rr and rr not in rerankers:
            rerankers[rr] = CrossEncoder(rr)
            rerankers[rr].score("rozgrzewka", ["rozgrzewka"])
        for i, q in enumerate(qs):
            order = rrf([fts_lists[i], vec_lists[key][i]])
            t_rr = 0.0
            if rr:
                head = order[:a.rerank_top]
                t = time.perf_counter()
                sc = rerankers[rr].score(q["text"], [chunk_text(c) for c in head])
                t_rr = time.perf_counter() - t
                order = [head[j] for j in np.argsort(-sc, kind="stable")] + order[a.rerank_top:]
            rank = first_hit(conn, turn_ranking(conn, order), q, rel_cache)
            ranks.append(rank)
            results["per_question"].setdefault(q["id"], {})[name] = rank
            lat.append(qtimes[key][i] + fts_times[i] + full_scan[key] + t_rr)
            rr_times.append(t_rr)
        res = breakdown(qs, ranks)
        res["latency_ms_median"] = round(1000 * statistics.median(lat))
        res["latency_ms_p90"] = round(1000 * sorted(lat)[int(0.9 * (len(lat) - 1))])
        res["rerank_ms_median"] = round(1000 * statistics.median(rr_times))
        results["variants"][name] = res
        log(f"{name}: {res['wszystkie']} PL={res['PL']} nie-PL={res['nie-PL']} "
            f"latency median {res['latency_ms_median']} ms")

    # latency components measured on the full archive size, independent of which ids have vectors
    results["latency_components_ms_median"] = {
        "fts": round(1000 * statistics.median(fts_times), 1),
        **{f"query_embed {k}": round(1000 * statistics.median(v), 1) for k, v in qtimes.items()},
        **{f"vector_scan_full_archive {k}": round(1000 * v, 1) for k, v in full_scan.items()},
    }
    results["archive_chunks"] = n_all

    sizes = {"e5-small": dir_size(bench_dir() / "models" / "fastembed", "*.onnx")}
    for key, cfg in EMBEDDERS.items():
        if cfg["export"]:
            sizes[key] = dir_size(export_dir(cfg["hf"]), "*.onnx")
    for key, cfg in RERANKERS.items():
        sizes[key] = dir_size(export_dir(cfg["hf"]), "*.onnx")
    results["model_onnx_mb"] = {k: round(v / 1e6) for k, v in sizes.items()}
    for key in EMBEDDERS:
        p = bench_dir() / f"embed-time-{key}.json"
        if p.exists():
            results["models"][key]["embed_time"] = json.loads(p.read_text(encoding="utf-8"))

    out = bench_dir() / "results.json"
    out.write_text(json.dumps(results, ensure_ascii=False, indent=1), encoding="utf-8")
    log(f"written {out}")


if __name__ == "__main__":
    main()
