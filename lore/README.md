# lore — pamięć rozmów Claude Code (lokalny serwer MCP)

Przeszukiwalna (pełnotekstowo + wektorowo) pamięć **wszystkich** rozmów Claude Code na tej
maszynie. Cel: pracujesz w kilku oknach naraz i nie chcesz powtarzać ustaleń — Claude sam
pyta „co ustaliliśmy o X" i dostaje fragmenty z innych sesji z datą.

Wszystko działa lokalnie, bez zewnętrznych API. Nic nie wychodzi z komputera.

## Jak to działa

```
~/.claude/projects/<projekt>/*.jsonl          (transkrypty Claude Code)
        │  lore/index.py  — przyrostowo, tylko nowe linie
        ▼
~/.claude/lore.db                              (SQLite)
   ├─ chunks      id, project, session, file, line, part, ts, role, text
   ├─ chunks_fts  FTS5 (unicode61 remove_diacritics 2: „zolty" znajdzie „żółty")
   ├─ vectors     embeddingi float32[384] (intfloat/multilingual-e5-small, ONNX przez fastembed)
   └─ files       co już przetworzono (mtime, rozmiar, offset bajtowy, nr linii)
        │  lore/server.py  — MCPServer przez stdio
        ▼
Claude Code (każde okno, każdy projekt) → narzędzia: lore_search, lore_context,
                                                      lore_reindex, lore_stats
```

**Kawałki (chunks)**: wypowiedzi użytkownika w całości, odpowiedzi asystenta (bloki `text`),
wywołania narzędzi jako jedna linia `[tool: nazwa] skrót inputu`, wyniki narzędzi
(pierwsze 400 znaków), podsumowania kompaktowania (rola `summary`). Pliki subagentów
(`<sesja>/subagents/*.jsonl`) są indeksowane z prefiksem roli `agent:` — bez ich szumu
narzędziowego. Teksty > 1500 znaków są cięte na kawałki z zakładką 200 znaków.

**Maskowanie sekretów** (przed zapisem do bazy): `Bearer …`, `token/secret/password/
api_key/refresh_token = …`, klucze `sk-…`, `AKIA…`, `ghp_…`, `ctx7sk-…`, JWT, ciągi hex
≥ 32 znaków i base64 ≥ 32 znaków → `[MASKED]`. Zobacz `lore/masking.py`.

**Wyszukiwanie** (`lore_search`): top-30 z FTS5 (BM25) + top-30 kosinus po wektorach
(numpy, brute force) → Reciprocal Rank Fusion. Zapytanie po niemiecku znajdzie rozmowę po
polsku (wspólna przestrzeń wielojęzyczna). Prefiksy `query:`/`passage:` zgodnie z wymogiem e5.

## Uruchamianie

Wymagania: `uv` (winget `astral-sh.uv`), Python 3.12 (`uv python install 3.12`).
Zależności instalują się same przy pierwszym `uv run`. Model embeddingów (~470 MB)
pobiera się raz do `~/.claude/lore_models/`.

```powershell
# ręczne przeindeksowanie (przyrostowe — dokłada tylko nowe linie)
uv --directory C:\dev\claude-worker\lore run python -m lore.index

# serwer MCP (normalnie uruchamia go Claude Code)
uv --directory C:\dev\claude-worker\lore run python -m lore.server
```

Serwer przy starcie sam uruchamia indeksowanie przyrostowe w wątku w tle.
Dodatkowo zadanie harmonogramu Windows odświeża indeks co 30 min.

## Rejestracja w Claude Code (globalnie, wszystkie projekty)

```powershell
claude mcp add --scope user lore -- <ścieżka>\uv.exe --directory C:\dev\claude-worker\lore run python -m lore.server
```

Wpis ląduje w `C:\Users\Primo\.claude.json` → `mcpServers.lore`. Po rejestracji trzeba
zrestartować okna Claude Code.

## Przejście ze starej wersji (`historia`)

Przy pierwszym starcie moduł sam przejmuje dotychczasowe dane, nic nie licząc od nowa:

- `~/.claude/historia.db` (razem z `-wal`/`-shm`) jest **przenoszony** na `~/.claude/lore.db`,
- stare tabele `fragmenty` / `pliki` / `wektory` dostają nowe nazwy (`chunks` / `files` /
  `vectors`) wraz z kolumnami, a indeks pełnotekstowy jest przebudowywany,
- katalog modelu `~/.claude/historia_modele` jest przenoszony na `~/.claude/lore_models`,
- zmienna `CLAUDE_HISTORIA_HOME` nadal działa, jeśli nie ustawiono `LORE_HOME`.

Migracja jest idempotentna — kolejne uruchomienia nic już nie ruszają.

## Pełne przeindeksowanie od zera

Zamknij okna Claude Code (żeby serwer nie trzymał bazy), usuń `~/.claude/lore.db`
(oraz `lore.db-wal`, `lore.db-shm`) i uruchom indekser. Model nie jest pobierany ponownie.

## Narzędzia MCP

| narzędzie | co robi |
|---|---|
| `lore_search(query, project?, since?, until?, limit=8)` | hybrydowe wyszukiwanie; zwraca datę, projekt, sesję, rolę, tekst ≤ 600 zn., id |
| `lore_context(id, count=3)` | pełna wypowiedź + `count` poprzednich i następnych z tej samej sesji |
| `lore_reindex()` | indeksowanie przyrostowe teraz; zwraca liczbę nowych kawałków |
| `lore_stats()` | liczba sesji/kawałków, per projekt, data ostatniego indeksowania, rozmiar bazy |

## Uwagi

- Daty w wynikach są w czasie lokalnym; filtry `since`/`until` porównują z ISO UTC
  z transkryptów (różnica maks. 2 h na granicy dnia).
- Kilka procesów (okna + harmonogram) może indeksować naraz: plik `lore.lock` + transakcje
  `BEGIN IMMEDIATE` z ponownym sprawdzeniem offsetu chronią przed duplikatami.
- Zmienna `LORE_HOME` nadpisuje katalog `~/.claude` (do testów).
