"""Shared pieces of the embedding benchmark: paths, safety guard, models, a replica of lore search.

Nothing here imports the production package `lore.*` — the benchmark must not open the real
database through `lore.db.connect()`, because that one migrates and writes.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

import numpy as np

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

HERE = Path(__file__).resolve().parent
QUERIES_FILE = HERE / "queries.jsonl"

# the real database is only ever READ (sqlite backup API, read-only URI)
SOURCE_DB = Path(os.environ.get("LORE_BENCH_SOURCE") or Path.home() / ".claude" / "lore.db")

# the same constants as lore/search.py — the replica has to rank exactly like production
TOP_PER_CHANNEL = 30
RRF_K = 60
_TOKEN = re.compile(r"\w+", re.UNICODE)

# places the benchmark must never write into
_FORBIDDEN = [Path.home() / ".claude", Path.home() / ".lore"]


def bench_dir() -> Path:
    """Working directory for the DB copy, vectors and models. Must be set and must be outside
    the real Lore data — the benchmark refuses to start otherwise instead of writing anywhere."""
    raw = os.environ.get("LORE_BENCH_DIR")
    if not raw:
        sys.exit("LORE_BENCH_DIR is not set - point it at a temporary directory (see bench/README.md)")
    d = Path(raw).resolve()
    for bad in _FORBIDDEN:
        bad = bad.resolve()
        if d == bad or bad in d.parents:
            sys.exit(f"LORE_BENCH_DIR={d} lies inside {bad} - refusing, the real Lore data is read-only here")
    d.mkdir(parents=True, exist_ok=True)
    # model downloads go to the bench dir too, never to the user's HF cache or lore_models
    os.environ.setdefault("HF_HOME", str(d / "hf"))
    os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
    return d


def copy_db_path() -> Path:
    return bench_dir() / "lore-kopia.db"


def open_copy() -> sqlite3.Connection:
    p = copy_db_path()
    if not p.exists():
        sys.exit(f"no database copy at {p} - run prepare.py first")
    return sqlite3.connect(p)


def log(*args) -> None:
    print(datetime.now().strftime("%H:%M:%S"), *args, file=sys.stderr, flush=True)


def sha1(text: str) -> str:
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:16]


# ---------------------------------------------------------------- models

EMBEDDERS = {
    # (a) production: exactly the registration from lore/db.py
    "e5-small": {
        "hf": "intfloat/multilingual-e5-small", "dim": 384, "pooling": "MEAN",
        "query_prefix": "query: ", "passage_prefix": "passage: ",
        "model_file": "onnx/model.onnx", "export": False,
    },
    # (b) Polish retriever; the model card demands "zapytanie: " for queries and NO passage prefix,
    # CLS pooling (1_Pooling/config.json). No ONNX on the hub -> exported locally by prepare.py.
    "mmlw-roberta-base": {
        "hf": "sdadas/mmlw-retrieval-roberta-base", "dim": 768, "pooling": "CLS",
        "query_prefix": "zapytanie: ", "passage_prefix": "",
        "model_file": "model.onnx", "export": True,
    },
}

RERANKERS = {
    # Polish cross-encoder from the same lab as mmlw, ~124M, Apache-2.0; raw logit = score
    "polish-reranker-base": {"hf": "sdadas/polish-reranker-base-ranknet", "export": True},
    # multilingual control (PL/DE/EN + code), ~278M, ONNX on the hub; CC-BY-NC-4.0 licence
    "jina-reranker-v2-multi": {"hf": "jinaai/jina-reranker-v2-base-multilingual", "export": False,
                               "model_file": "onnx/model.onnx"},
}


def export_dir(name: str) -> Path:
    return bench_dir() / "models" / "export" / name.replace("/", "--")


def dir_size(path: Path, pattern: str = "*") -> int:
    return sum(f.stat().st_size for f in path.rglob(pattern) if f.is_file())


_embedders: dict[str, object] = {}


def embedder(key: str):
    if key in _embedders:
        return _embedders[key]
    from fastembed import TextEmbedding
    from fastembed.common.model_description import ModelSource, PoolingType

    cfg = EMBEDDERS[key]
    name = cfg["hf"]
    if name not in {m["model"] for m in TextEmbedding.list_supported_models()}:
        TextEmbedding.add_custom_model(
            model=name, pooling=getattr(PoolingType, cfg["pooling"]), normalization=True,
            sources=ModelSource(hf=name), dim=cfg["dim"], model_file=cfg["model_file"], size_in_gb=0.5,
        )
    kw = {"cache_dir": str(bench_dir() / "models" / "fastembed")}
    if cfg["export"]:
        kw["specific_model_path"] = str(export_dir(name))
    log(f"loading embedder {name}")
    m = TextEmbedding(model_name=name, **kw)
    _embedders[key] = m
    return m


def _normalize(m: np.ndarray) -> np.ndarray:
    m = np.asarray(m, dtype=np.float32)
    n = np.linalg.norm(m, axis=1, keepdims=True)
    n[n == 0] = 1.0
    return m / n


def embed_passages(key: str, texts: list[str], batch: int = 32) -> np.ndarray:
    """Same procedure as lore.db.embed_passages: sort by length, batch 32, normalise."""
    cfg = EMBEDDERS[key]
    if not texts:
        return np.zeros((0, cfg["dim"]), dtype=np.float32)
    m = embedder(key)
    order = sorted(range(len(texts)), key=lambda i: len(texts[i]))
    vecs = list(m.embed([cfg["passage_prefix"] + texts[i] for i in order], batch_size=batch))
    out = np.empty((len(texts), cfg["dim"]), dtype=np.float32)
    out[order] = np.vstack(vecs)
    return _normalize(out)


def embed_query(key: str, query: str) -> np.ndarray:
    cfg = EMBEDDERS[key]
    return _normalize(np.vstack(list(embedder(key).embed([cfg["query_prefix"] + query]))))[0]


class CrossEncoder:
    """Minimal ONNX cross-encoder: tokenizer.json + model.onnx, score = first logit."""

    def __init__(self, key: str) -> None:
        import onnxruntime as ort
        from tokenizers import Tokenizer

        cfg = RERANKERS[key]
        if cfg["export"]:
            d = export_dir(cfg["hf"])
            model_path = d / "model.onnx"
        else:
            from huggingface_hub import snapshot_download
            # local_dir: the hub cache uses symlinks, which Windows refuses without developer mode
            d = Path(snapshot_download(cfg["hf"], allow_patterns=[cfg["model_file"], "*.json"],
                                       local_dir=export_dir(cfg["hf"])))
            model_path = d / cfg["model_file"]
        self.dir = d
        self.model_path = model_path
        self.tok = Tokenizer.from_file(str(d / "tokenizer.json"))
        self.tok.enable_truncation(max_length=512, strategy="only_second")
        pad_id = json.loads((d / "config.json").read_text(encoding="utf-8")).get("pad_token_id", 1)
        self.tok.enable_padding(pad_id=pad_id)
        log(f"loading reranker {cfg['hf']}")
        self.sess = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
        self.inputs = {i.name for i in self.sess.get_inputs()}

    def score(self, query: str, docs: list[str], batch: int = 8) -> np.ndarray:
        out = []
        for i in range(0, len(docs), batch):
            enc = self.tok.encode_batch([(query, d) for d in docs[i:i + batch]])
            feed = {
                "input_ids": np.array([e.ids for e in enc], dtype=np.int64),
                "attention_mask": np.array([e.attention_mask for e in enc], dtype=np.int64),
            }
            if "token_type_ids" in self.inputs:
                feed["token_type_ids"] = np.zeros_like(feed["input_ids"])
            logits = self.sess.run(None, feed)[0]
            out.append(np.asarray(logits, dtype=np.float32).reshape(len(enc), -1)[:, 0])
        return np.concatenate(out) if out else np.zeros(0, dtype=np.float32)


# ---------------------------------------------------------------- vectors of the copy

def vectors_path(key: str) -> Path:
    return bench_dir() / f"vectors-{key}.npz"


def load_vectors(key: str) -> tuple[np.ndarray, np.ndarray]:
    p = vectors_path(key)
    if not p.exists():
        sys.exit(f"no vectors for {key} at {p} - run embed_corpus.py first")
    z = np.load(p)
    return z["ids"], z["matrix"]


# ---------------------------------------------------------------- search replica

def fts_query(q: str) -> str:
    toks = [t for t in _TOKEN.findall(q) if len(t) > 1 or t.isdigit()]
    return " OR ".join(f'"{t}"' for t in toks)


def pool_bounds(q: dict) -> tuple[str, str, str]:
    """What the archive looked like when the question was asked: everything before it, minus the
    last two hours of the very same conversation (that part was still in the model's own context).

    "Same conversation" is the session id, not the file: a resumed session is continued from
    another folder, and some transcripts are indexed twice under two paths with one session id.
    """
    qts = q["query_ts"]
    near = datetime.fromisoformat(qts.replace("Z", "+00:00")) - timedelta(hours=2)
    return qts, q["query_session"], near.strftime("%Y-%m-%dT%H:%M:%S.000Z")


POOL_SQL = "(c.ts < ? AND (c.session != ? OR c.ts < ?))"


def fts_channel(conn: sqlite3.Connection, q: dict, text: str, exclude: set[int], limit: int = TOP_PER_CHANNEL,
                allowed: set[int] | None = None) -> list[int]:
    """BM25 top `limit`. `allowed` restricts the archive to a sample (when not every chunk has
    vectors of every model) - then far more rows are fetched and filtered, same ordering."""
    fq = fts_query(text)
    if not fq:
        return []
    fetch = limit + len(exclude) if allowed is None else 20000
    rows = conn.execute(
        f"SELECT c.id FROM chunks_fts x JOIN chunks c ON c.id = x.rowid "
        f"WHERE chunks_fts MATCH ? AND {POOL_SQL} ORDER BY bm25(chunks_fts) LIMIT ?",
        [fq, *pool_bounds(q), fetch],
    ).fetchall()
    return [r[0] for r in rows if r[0] not in exclude and (allowed is None or r[0] in allowed)][:limit]


def vector_channel(qvec: np.ndarray, ids: np.ndarray, matrix: np.ndarray, allowed: np.ndarray,
                   limit: int = TOP_PER_CHANNEL) -> list[int]:
    sc = matrix @ qvec
    sc = np.where(allowed, sc, -np.inf)
    n = min(limit, int(allowed.sum()))
    if n <= 0:
        return []
    top = np.argpartition(-sc, n - 1)[:n]
    top = top[np.argsort(-sc[top])]
    return [int(ids[i]) for i in top]


def rrf(lists: list[list[int]]) -> list[int]:
    scores: dict[int, float] = {}
    for lst in lists:
        for r, cid in enumerate(lst):
            scores[cid] = scores.get(cid, 0.0) + 1.0 / (RRF_K + r + 1)
    return [cid for cid, _ in sorted(scores.items(), key=lambda kv: -kv[1])]


class Timer:
    def __enter__(self):
        self.t = time.perf_counter()
        return self

    def __exit__(self, *a):
        self.s = time.perf_counter() - self.t
