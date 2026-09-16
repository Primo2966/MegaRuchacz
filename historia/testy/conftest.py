"""Wspólna izolacja testów: własna piaskownica zamiast ~/.claude, własna baza, zero prawdziwych danych."""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

# musi polecieć PRZED importem historia.baza — ścieżki są stałymi modułu liczonymi przy imporcie
_PIASKOWNICA = Path(tempfile.mkdtemp(prefix="historia-testy-"))
os.environ["CLAUDE_HISTORIA_HOME"] = str(_PIASKOWNICA)

import numpy as np  # noqa: E402
import pytest  # noqa: E402

from historia import baza, indeksuj  # noqa: E402

TS = "2026-09-16T10:00:00.000Z"


def _zerowe_wektory(teksty: list[str], batch: int = 32) -> np.ndarray:
    """Podmiana za embedduj_passages — testy sprawdzają cięcie i przyrostowość, nie model."""
    return np.zeros((len(teksty), baza.WYMIAR_EMB), dtype=np.float32)


def rekord(rola: str, tekst: str, sesja: str = "sesja-testowa", ts: str = TS) -> dict:
    """Jeden wiersz transkryptu w formacie Claude Code."""
    if rola == "user":
        return {"type": "user", "sessionId": sesja, "timestamp": ts, "message": {"role": "user", "content": tekst}}
    return {
        "type": "assistant",
        "sessionId": sesja,
        "timestamp": ts,
        "message": {"role": "assistant", "content": [{"type": "text", "text": tekst}]},
    }


@dataclass
class Srodowisko:
    conn: object
    projekty: Path
    _nr: list[int] = field(default_factory=lambda: [0])

    def transkrypt(self, *wypowiedzi: tuple[str, str], nazwa: str = "sesja-testowa") -> Path:
        """Tworzy ~/projects/testy/<nazwa>.jsonl z podanych par (rola, tekst)."""
        katalog = self.projekty / "projekt-testowy"
        katalog.mkdir(parents=True, exist_ok=True)
        p = katalog / f"{nazwa}.jsonl"
        p.write_text("", encoding="utf-8")
        self.dopisz(p, *wypowiedzi)
        return p

    def dopisz(self, p: Path, *wypowiedzi: tuple[str, str]) -> None:
        with open(p, "a", encoding="utf-8", newline="\n") as f:
            for rola, tekst in wypowiedzi:
                f.write(json.dumps(rekord(rola, tekst, sesja=p.stem), ensure_ascii=False) + "\n")

    def indeksuj(self, p: Path) -> int:
        return indeksuj.przetworz_plik(self.conn, p)

    def teksty(self) -> list[str]:
        return [r[0] for r in self.conn.execute("SELECT tekst FROM fragmenty ORDER BY id")]

    def wiersze(self) -> list[tuple]:
        return list(self.conn.execute("SELECT linia, czesc, rola, tekst FROM fragmenty ORDER BY id"))

    def stan_pliku(self, p: Path) -> tuple[float, int, int, int]:
        return self.conn.execute("SELECT mtime, rozmiar, offset, linia FROM pliki WHERE sciezka=?", (str(p),)).fetchone()


@pytest.fixture
def srodowisko(tmp_path, monkeypatch):
    """Pusta baza w katalogu tymczasowym + własne katalogi transkryptów."""
    projekty = tmp_path / "projects"
    projekty.mkdir()
    dom = tmp_path / "dom"
    dom.mkdir()
    monkeypatch.setattr(baza, "SCIEZKA_BAZY", tmp_path / "historia.db")
    monkeypatch.setattr(indeksuj, "SCIEZKA_BAZY", tmp_path / "historia.db")
    monkeypatch.setattr(indeksuj, "PLIK_BLOKADY", tmp_path / "historia.lock")
    monkeypatch.setattr(indeksuj, "KATALOG_PROJEKTOW", projekty)
    monkeypatch.setattr(indeksuj, "KATALOG_DOMOWY", dom)
    monkeypatch.setattr(indeksuj, "embedduj_passages", _zerowe_wektory)
    conn = baza.polacz()
    try:
        yield Srodowisko(conn=conn, projekty=projekty)
    finally:
        conn.close()
