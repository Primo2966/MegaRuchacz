"""Step 1: copy the real database (read-only) and get every model into LORE_BENCH_DIR.

    python prepare.py            # copy + models
    python prepare.py --only-db  # refresh only the database copy

The copy goes through the SQLite backup API from a read-only connection, so a running indexer
is not disturbed and the WAL content is included. Models without an ONNX file on the hub are
exported from PyTorch here (torch is needed only for this step).
"""

from __future__ import annotations

import argparse
import sqlite3
import time

from common import EMBEDDERS, RERANKERS, SOURCE_DB, bench_dir, copy_db_path, embedder, export_dir, log


def copy_db() -> None:
    dst_path = copy_db_path()
    if dst_path.exists():
        dst_path.unlink()
    t = time.perf_counter()
    src = sqlite3.connect(f"file:{SOURCE_DB.as_posix()}?mode=ro", uri=True)
    dst = sqlite3.connect(dst_path)
    try:
        src.backup(dst)
    finally:
        src.close()
    n_chunks = dst.execute("SELECT count(*) FROM chunks").fetchone()[0]
    n_vec = dst.execute("SELECT count(*) FROM vectors").fetchone()[0]
    dst.close()
    log(f"copied {SOURCE_DB} -> {dst_path}: {n_chunks} chunks, {n_vec} vectors, {time.perf_counter() - t:.1f}s")


def _export(name: str, kind: str) -> None:
    """PyTorch -> ONNX through optimum (dynamic batch/sequence, tokenizer files fastembed needs).

    A hand-written torch.onnx.export traced to a graph that was off by up to 1.9 on the hidden
    states (seen 2026-09-24) - hence optimum, and hence the check below after every export.
    """
    out = export_dir(name)
    if (out / "model.onnx").exists():
        log(f"{name}: already exported")
        return
    import torch
    from optimum.exporters.onnx import main_export
    from transformers import AutoModel, AutoModelForSequenceClassification, AutoTokenizer

    out.mkdir(parents=True, exist_ok=True)
    task = "feature-extraction" if kind == "embed" else "text-classification"
    main_export(name, output=out, task=task, library_name="transformers")
    tok = AutoTokenizer.from_pretrained(name)
    cls = AutoModel if kind == "embed" else AutoModelForSequenceClassification
    # fp32 reference: some checkpoints are stored in fp16
    model = cls.from_pretrained(name, dtype=torch.float32).eval()
    _check(name, kind, model, tok, out)


def _check(name, kind, model, tok, out) -> None:
    """The exported graph must give the same numbers as PyTorch — otherwise the benchmark lies."""
    import numpy as np
    import onnxruntime as ort
    import torch

    texts = ["zapytanie: jak ustawić tytuł na eBay", "Ätherisches Öl Lavendel 10ml Bio"]
    enc = tok(texts, padding=True, return_tensors="pt")
    with torch.no_grad():
        r = model(**enc)
        ref = (r.last_hidden_state if kind == "embed" else r.logits).numpy()
    sess = ort.InferenceSession(str(out / "model.onnx"), providers=["CPUExecutionProvider"])
    got = sess.run(None, {"input_ids": enc["input_ids"].numpy(), "attention_mask": enc["attention_mask"].numpy()})[0]
    diff = float(np.abs(ref - got).max())
    if diff > 1e-3:
        del sess
        (out / "model.onnx").unlink()  # otherwise the next run would take it as "already exported"
        raise SystemExit(f"{name}: ONNX export differs from PyTorch by {diff} - not using it")
    log(f"{name}: exported, max |onnx - torch| = {diff:.2e}")


def models() -> None:
    for key, cfg in EMBEDDERS.items():
        if cfg["export"]:
            _export(cfg["hf"], "embed")
        list(embedder(key).embed(["test"]))  # downloads / loads, fails loudly if broken
    for key, cfg in RERANKERS.items():
        if cfg["export"]:
            _export(cfg["hf"], "rerank")
        else:
            from common import CrossEncoder
            CrossEncoder(key).score("test", ["test"])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only-db", action="store_true")
    a = ap.parse_args()
    log(f"bench dir: {bench_dir()}")
    copy_db()
    if not a.only_db:
        models()


if __name__ == "__main__":
    main()
