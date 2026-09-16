# historia — pamięć rozmów Claude Code (lokalny serwer MCP)

Przeszukiwalna (pełnotekstowo + wektorowo) pamięć **wszystkich** rozmów Claude Code na tej
maszynie. Cel: pracujesz w kilku oknach naraz i nie chcesz powtarzać ustaleń — Claude sam
pyta „co ustaliliśmy o X" i dostaje fragmenty z innych sesji z datą.

Wszystko działa lokalnie, bez zewnętrznych API. Nic nie wychodzi z komputera.

## Jak to działa

```
~/.claude/projects/<projekt>/*.jsonl          (transkrypty Claude Code)
        │  historia/indeksuj.py  — przyrostowo, tylko nowe linie
        ▼
~/.claude/historia.db                          (SQLite)
   ├─ fragmenty      id, projekt, sesja, plik, linia, ts, rola, tekst
   ├─ fragmenty_fts  FTS5 (unicode61 remove_diacritics 2: „zolty" znajdzie „żółty")
   ├─ wektory        embeddingi float32[384] (intfloat/multilingual-e5-small, ONNX przez fastembed)
   └─ pliki          co już przetworzono (mtime, rozmiar, offset bajtowy, nr linii)
        │  historia/serwer.py  — FastMCP przez stdio
        ▼
Claude Code (każde okno, każdy projekt) → narzędzia: szukaj_historii, kontekst_historii,
                                                      reindeksuj, statystyki_historii
```

**Fragmenty**: wypowiedzi użytkownika w całości, odpowiedzi asystenta (bloki `text`),
wywołania narzędzi jako jedna linia `[narzędzie: nazwa] skrót inputu`, wyniki narzędzi
(pierwsze 400 znaków), podsumowania kompaktowania (`podsumowanie`). Pliki subagentów
(`<sesja>/subagents/*.jsonl`) są indeksowane z prefiksem roli `agent:` — bez ich szumu
narzędziowego. Fragmenty > 1500 znaków są cięte na kawałki z zakładką 200 znaków.

**Maskowanie sekretów** (przed zapisem do bazy): `Bearer …`, `token/secret/password/
api_key/refresh_token = …`, klucze `sk-…`, `AKIA…`, `ghp_…`, `ctx7sk-…`, JWT, ciągi hex
≥ 32 znaków i base64 ≥ 32 znaków → `[MASKED]`. Zobacz `historia/maskowanie.py`.

**Wyszukiwanie** (`szukaj_historii`): top-30 z FTS5 (BM25) + top-30 kosinus po wektorach
(numpy, brute force) → Reciprocal Rank Fusion. Zapytanie po niemiecku znajdzie rozmowę po
polsku (wspólna przestrzeń wielojęzyczna). Prefiksy `query:`/`passage:` zgodnie z wymogiem e5.

## Uruchamianie

Wymagania: `uv` (winget `astral-sh.uv`), Python 3.12 (`uv python install 3.12`).
Zależności instalują się same przy pierwszym `uv run`. Model embeddingów (~470 MB)
pobiera się raz do `~/.claude/historia_modele/`.

```powershell
# ręczne przeindeksowanie (przyrostowe — dokłada tylko nowe linie)
uv --directory C:\dev\claude-historia run python -m historia.indeksuj

# serwer MCP (normalnie uruchamia go Claude Code)
uv --directory C:\dev\claude-historia run python -m historia.serwer
```

Serwer przy starcie sam uruchamia indeksowanie przyrostowe w wątku w tle.
Dodatkowo zadanie harmonogramu Windows `ClaudeHistoriaIndeks` odświeża indeks co 30 min
(`schtasks /Query /TN ClaudeHistoriaIndeks`).

## Rejestracja w Claude Code (globalnie, wszystkie projekty)

```powershell
claude mcp add --scope user historia -- <ścieżka>\uv.exe --directory C:\dev\claude-historia run python -m historia.serwer
```

Wpis ląduje w `C:\Users\Primo\.claude.json` → `mcpServers.historia`. Po rejestracji trzeba
zrestartować okna Claude Code.

## Pełne przeindeksowanie od zera

Zamknij okna Claude Code (żeby serwer nie trzymał bazy), usuń `~/.claude/historia.db`
(oraz `historia.db-wal`, `historia.db-shm`) i uruchom indekser. Model nie jest pobierany ponownie.

## Narzędzia MCP

| narzędzie | co robi |
|---|---|
| `szukaj_historii(zapytanie, projekt?, od?, do?, limit=8)` | hybrydowe wyszukiwanie; zwraca datę, projekt, sesję, rolę, fragment ≤ 600 zn., id |
| `kontekst_historii(id, ile=3)` | pełna wypowiedź + `ile` poprzednich i następnych z tej samej sesji |
| `reindeksuj()` | indeksowanie przyrostowe teraz; zwraca liczbę nowych fragmentów |
| `statystyki_historii()` | liczba sesji/fragmentów, per projekt, data ostatniego indeksowania, rozmiar bazy |

## Uwagi

- Daty w wynikach są w czasie lokalnym; filtry `od`/`do` porównują z ISO UTC z transkryptów
  (różnica maks. 2 h na granicy dnia).
- Kilka procesów (okna + harmonogram) może indeksować naraz: plik `historia.lock` + transakcje
  `BEGIN IMMEDIATE` z ponownym sprawdzeniem offsetu chronią przed duplikatami.
- Zmienna `CLAUDE_HISTORIA_HOME` nadpisuje katalog `~/.claude` (do testów).
