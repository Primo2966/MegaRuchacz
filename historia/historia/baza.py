"""Ścieżki, schemat SQLite i wspólne narzędzia (embeddingi)."""

from __future__ import annotations

import os
import sqlite3
import sys
import threading
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
for _strumien in (sys.stderr,):
    try:
        _strumien.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

KATALOG_CLAUDE = Path(os.environ.get("CLAUDE_HISTORIA_HOME", Path.home() / ".claude"))
KATALOG_PROJEKTOW = KATALOG_CLAUDE / "projects"
SCIEZKA_BAZY = KATALOG_CLAUDE / "historia.db"
KATALOG_MODELI = KATALOG_CLAUDE / "historia_modele"

MODEL_EMB = "intfloat/multilingual-e5-small"
WYMIAR_EMB = 384

SCHEMAT = """
CREATE TABLE IF NOT EXISTS pliki (
    sciezka  TEXT PRIMARY KEY,
    mtime    REAL NOT NULL,
    rozmiar  INTEGER NOT NULL,
    offset   INTEGER NOT NULL DEFAULT 0,
    linia    INTEGER NOT NULL DEFAULT 0,
    projekt  TEXT,
    sesja    TEXT
);
CREATE TABLE IF NOT EXISTS fragmenty (
    id      INTEGER PRIMARY KEY,
    projekt TEXT NOT NULL,
    sesja   TEXT NOT NULL,
    plik    TEXT NOT NULL,
    linia   INTEGER NOT NULL,
    czesc   INTEGER NOT NULL DEFAULT 0,
    ts      TEXT NOT NULL,
    rola    TEXT NOT NULL,
    tekst   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_fragmenty_plik ON fragmenty(plik, linia, czesc);
CREATE INDEX IF NOT EXISTS idx_fragmenty_ts ON fragmenty(ts);
CREATE INDEX IF NOT EXISTS idx_fragmenty_projekt ON fragmenty(projekt);
CREATE VIRTUAL TABLE IF NOT EXISTS fragmenty_fts USING fts5(
    tekst,
    content='fragmenty',
    content_rowid='id',
    tokenize='unicode61 remove_diacritics 2'
);
CREATE TABLE IF NOT EXISTS wektory (
    fragment_id INTEGER PRIMARY KEY REFERENCES fragmenty(id) ON DELETE CASCADE,
    emb         BLOB NOT NULL
);
CREATE TABLE IF NOT EXISTS meta (
    klucz   TEXT PRIMARY KEY,
    wartosc TEXT
);
"""


def polacz() -> sqlite3.Connection:
    """Otwiera bazę (tworzy schemat, WAL, długi busy_timeout — kilka okien może pisać naraz)."""
    SCIEZKA_BAZY.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(SCIEZKA_BAZY, timeout=180, isolation_level=None, check_same_thread=False)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.executescript(SCHEMAT)
    return conn


def log(*args) -> None:
    """Logowanie wyłącznie na stderr — stdout należy do protokołu MCP."""
    print(datetime.now().strftime("%H:%M:%S"), "[historia]", *args, file=sys.stderr, flush=True)


# ---------------------------------------------------------------- embeddingi

_model = None
_model_lock = threading.Lock()


def model_embeddingow():
    """Leniwe, jednorazowe załadowanie modelu ONNX (pierwsze uruchomienie pobiera ~120 MB)."""
    global _model
    if _model is None:
        with _model_lock:
            if _model is None:
                from fastembed import TextEmbedding
                from fastembed.common.model_description import ModelSource, PoolingType

                # fastembed nie ma e5-small wbudowanego — rejestrujemy go z oficjalnego repo HF (pliki ONNX)
                if MODEL_EMB not in {m["model"] for m in TextEmbedding.list_supported_models()}:
                    TextEmbedding.add_custom_model(
                        model=MODEL_EMB,
                        pooling=PoolingType.MEAN,
                        normalization=True,
                        sources=ModelSource(hf=MODEL_EMB),
                        dim=WYMIAR_EMB,
                        model_file="onnx/model.onnx",
                        size_in_gb=0.47,
                    )
                KATALOG_MODELI.mkdir(parents=True, exist_ok=True)
                log(f"ładuję model {MODEL_EMB} ...")
                _model = TextEmbedding(model_name=MODEL_EMB, cache_dir=str(KATALOG_MODELI))
                log("model gotowy")
    return _model


def _normalizuj(m: np.ndarray) -> np.ndarray:
    m = np.asarray(m, dtype=np.float32)
    normy = np.linalg.norm(m, axis=1, keepdims=True)
    normy[normy == 0] = 1.0
    return m / normy


def embedduj_passages(teksty: list[str], batch: int = 32) -> np.ndarray:
    """Wektory dla fragmentów — prefiks `passage: ` to wymóg modeli e5.

    Teksty sortujemy po długości: ONNX paduje do najdłuższego w batchu, więc mieszanie
    krótkich linii narzędzi z długimi odpowiedziami marnowało kilkukrotnie czas i RAM.
    """
    if not teksty:
        return np.zeros((0, WYMIAR_EMB), dtype=np.float32)
    m = model_embeddingow()
    kolejnosc = sorted(range(len(teksty)), key=lambda i: len(teksty[i]))
    wek = list(m.embed(["passage: " + teksty[i] for i in kolejnosc], batch_size=batch))
    wynik = np.empty((len(teksty), WYMIAR_EMB), dtype=np.float32)
    wynik[kolejnosc] = np.vstack(wek)
    return _normalizuj(wynik)


def embedduj_zapytanie(zapytanie: str) -> np.ndarray:
    m = model_embeddingow()
    wek = list(m.embed(["query: " + zapytanie]))
    return _normalizuj(np.vstack(wek))[0]


# ---------------------------------------------------------------- daty

def ts_na_lokalny(ts: str) -> str:
    """ISO UTC ('2026-09-11T06:27:15.470Z') -> 'YYYY-MM-DD HH:MM' w czasie lokalnym."""
    try:
        d = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        if d.tzinfo is None:
            d = d.replace(tzinfo=timezone.utc)
        return d.astimezone().strftime("%Y-%m-%d %H:%M")
    except Exception:
        return ts[:16].replace("T", " ")
