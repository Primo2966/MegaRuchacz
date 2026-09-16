"""Serwer MCP „historia" (stdio, SDK mcp 2.x — MCPServer, dawniej FastMCP) — pamięć wszystkich rozmów Claude Code na tej maszynie.

Uruchomienie: uv --directory C:\\dev\\claude-historia run python -m historia.serwer
"""

from __future__ import annotations

import threading

from mcp.server.mcpserver import MCPServer

from . import szukaj as _szukaj
from .baza import log
from .indeksuj import indeksuj

mcp = MCPServer(
    "historia",
    instructions=(
        "Pamięć wszystkich rozmów Claude Code na tej maszynie (wszystkie projekty i okna). "
        "Na starcie zadania wywołaj szukaj_historii, żeby sprawdzić, co już ustalono w innych sesjach, "
        "zanim zaczniesz pytać użytkownika o rzeczy, które mógł już wyjaśnić gdzie indziej."
    ),
)

_blokada_indeksowania = threading.Lock()


def _indeksuj_w_tle() -> None:
    with _blokada_indeksowania:
        try:
            n = indeksuj(cicho=True)
            log(f"indeksowanie w tle: +{n} fragmentów")
        except Exception as e:  # nie wolno wywrócić serwera
            log(f"indeksowanie w tle nie powiodło się: {e!r}")


@mcp.tool()
def szukaj_historii(zapytanie: str, projekt: str | None = None, od: str | None = None,
                    do: str | None = None, limit: int = 8) -> list[dict]:
    """Przeszukuje historię WSZYSTKICH rozmów Claude Code na tej maszynie (inne okna, inne projekty,
    wcześniejsze dni). Użyj na starcie zadania, żeby sprawdzić, co już ustalono w innych oknach —
    np. „co ustaliliśmy o wariantach olejków na eBay", „jak konfigurowaliśmy Allegro API".
    Wyszukiwanie hybrydowe: pełnotekstowe (polski/niemiecki/angielski, bez znaczenia diakrytyki)
    + semantyczne (wielojęzyczne embeddingi — zapytanie po niemiecku znajdzie rozmowę po polsku).

    Args:
        zapytanie: pytanie lub słowa kluczowe w dowolnym języku.
        projekt: opcjonalny filtr — fragment nazwy katalogu projektu (np. "ecommerce-helper").
        od: opcjonalna data początkowa ISO (np. "2026-09-01").
        do: opcjonalna data końcowa ISO (np. "2026-09-11").
        limit: ile wyników zwrócić (domyślnie 8).

    Zwraca listę: data (YYYY-MM-DD HH:MM, czas lokalny), projekt, sesja (skrót), rola
    (user / assistant / narzedzie / wynik / podsumowanie; prefiks "agent:" = subagent),
    fragment (≤600 znaków), id (do kontekst_historii).
    """
    return _szukaj.szukaj(zapytanie, projekt=projekt, od=od, do=do, limit=max(1, min(limit, 50)))


@mcp.tool()
def kontekst_historii(id: int, ile: int = 3) -> dict:
    """Pokazuje pełną wypowiedź o podanym id (z szukaj_historii) oraz `ile` poprzednich
    i `ile` następnych wypowiedzi z tej samej sesji, chronologicznie — żeby zrozumieć,
    w jakim kontekście coś ustalono."""
    return _szukaj.kontekst(id, ile=max(0, min(ile, 20)))


@mcp.tool()
def reindeksuj() -> dict:
    """Uruchamia indeksowanie przyrostowe transkryptów (dokłada tylko nowe wypowiedzi).
    Użyj, gdy chcesz mieć pewność, że widzisz to, co przed chwilą ustalono w innym oknie."""
    if not _blokada_indeksowania.acquire(timeout=300):
        return {"nowe_fragmenty": 0, "uwaga": "indeksowanie w tle wciąż trwa"}
    try:
        n = indeksuj(cicho=True)
    finally:
        _blokada_indeksowania.release()
    return {"nowe_fragmenty": n}


@mcp.tool()
def statystyki_historii() -> dict:
    """Liczba zaindeksowanych sesji i fragmentów (łącznie i per projekt), data ostatniego
    indeksowania, położenie i rozmiar bazy."""
    return _szukaj.statystyki()


def main() -> None:
    threading.Thread(target=_indeksuj_w_tle, name="historia-indeksowanie", daemon=True).start()
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
