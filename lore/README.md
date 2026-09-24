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
~/.lore/lore.db                                (SQLite)
   ├─ chunks      id, project, session, file, line, part, ts, role, text
   ├─ chunks_fts  FTS5 (unicode61 remove_diacritics 2: „zolty" znajdzie „żółty")
   ├─ vectors     embeddingi float32[768] (sdadas/mmlw-retrieval-roberta-base, ONNX przez fastembed;
   │              baza sprzed zmiany modelu trzyma tu e5-small [384] do czasu migracji)
   ├─ vectors_next wektory nowego modelu budowane podczas migracji (poza rankingiem)
   ├─ meta        m.in. embed_model — którym modelem liczono `vectors`
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
polsku (wspólna przestrzeń wielojęzyczna). Pytanie jest liczone **tym samym modelem, co wektory
w bazie** (`meta.embed_model`), z prefiksami z karty modelu: mmlw — `zapytanie: ` przed pytaniem,
nic przed fragmentem; e5 — `query:`/`passage:`.

**Model**: `sdadas/mmlw-retrieval-roberta-base` (768 wymiarów, ~500 MB). Plik ONNX pochodzi
z eksportu `dawidplaskowski/mmlw-retrieval-roberta-base_onnx`, przypiętego do jednego commita
i sumy sha256 każdego pliku — podmieniony plik jest odrzucany, nie używany. Pomiar z 2026-09-24
na 60 pytaniach z rozmów autora: top10 90% wobec 80% dla e5-small, lepiej także po niemiecku
i angielsku — `.claude/raporty/pamiec-test-modeli.md`, kod pomiaru w `lore/bench/`.

**Automatyczne przypomnienie** (`lore/recall.py`, wołane przez `narzedzia/przypomnienie.js`
przy każdej wiadomości): samo FTS5, bez modelu wektorowego (budżet < 1 s), najwyżej 2 fragmenty,
z progiem trafności; bazę otwiera tylko do odczytu.

## Gdzie leżą dane

Baza i katalog modelu to **własne dane Lore** i nie mieszkają w katalogu żadnego
narzędzia AI — na maszynie z samym Codexem katalog `~/.claude` mógłby w ogóle nie istnieć.
Katalog danych ustala się w tej kolejności:

1. zmienna `LORE_HOME` (albo starsza `CLAUDE_HISTORIA_HOME`) — ma pierwszeństwo,
2. `~/.claude`, jeśli leży tam już baza (`lore.db` albo `historia.db`) — dotychczasowe
   instalacje działają dalej w miejscu, nic nie jest przenoszone ani kopiowane,
3. `~/.lore` — świeża instalacja.

Transkrypty to co innego: czyta się je tam, gdzie zapisują je same narzędzia
(`~/.claude/projects`, `~/.codex/sessions`), i to się nie zmienia.

## Uruchamianie

Wymagania: `uv` (winget `astral-sh.uv`), Python 3.12 (`uv python install 3.12`).
Zależności instalują się same przy pierwszym `uv run`. Model embeddingów (~500 MB)
pobiera się raz do `<katalog danych>/lore_models/` (domyślnie `~/.lore/lore_models/`).

```powershell
# ręczne przeindeksowanie (przyrostowe — dokłada tylko nowe linie)
uv --directory C:\dev\claude-worker\lore run python -m lore.index

# serwer MCP (normalnie uruchamia go Claude Code)
uv --directory C:\dev\claude-worker\lore run python -m lore.server
```

Serwer przy starcie sam uruchamia indeksowanie przyrostowe w wątku w tle.
Dodatkowo zadanie harmonogramu Windows `LoreIndex` (zakłada je `narzedzia\instaluj-lore.ps1`)
odświeża indeks co 10 min od zalogowania.

## Zmiana modelu wektorowego (migracja)

Świeża baza od razu liczy modelem mmlw. Baza sprzed zmiany (e5-small) **działa dalej na starym
modelu**, dopóki jej nie przeliczysz — wyszukiwanie nigdy nie miesza dwóch modeli w jednym
rankingu, a nowe fragmenty dostają do tego czasu wektor starego modelu. Przeliczenie nie rusza samo:

```powershell
# przeliczenie archiwum w tle, partiami po 64 fragmenty (u autora ~2 h na CPU dla ~56 tys. fragmentów)
uv --directory C:\dev\claude-worker\lore run python -m lore.migrate

# stan: jaki model ma baza, ile przeliczono, tempo, szacowany koniec
uv --directory C:\dev\claude-worker\lore run python -m lore.migrate --status
```

- Nowe wektory idą do osobnej tabeli `vectors_next`; wyszukiwanie korzysta ze starych aż do
  przełączenia, które jest jedną transakcją (usuń starą tabelę, przemianuj nową, zapisz model).
- Każda partia to osobna transakcja: przerwanie (zamknięte okno, wyłączony komputer) traci
  najwyżej jedną partię, a ponowne uruchomienie rusza od miejsca, w którym stanęło.
- Postęp leży w `lore.migration.json` obok bazy (odświeżany po każdej partii); czyta go też
  nadzorca w zasobniku. Stan „running" ze starym znacznikiem życia = martwy proces.
- Na bazie już przeliczonej to samo polecenie **naprawia**: dolicza brakujące wektory i te
  o złym rozmiarze. Nic do naprawy = szybkie „nic".
- Do końca migracji `lore_stats` (pole `vectors`) i log każdego procesu Lore mówią wprost, że
  baza ma inny model niż skonfigurowany.

## Rejestracja w Claude Code (globalnie, wszystkie projekty)

```powershell
claude mcp add --scope user lore -- <ścieżka>\uv.exe --directory C:\dev\claude-worker\lore run python -m lore.server
```

Wpis ląduje w `C:\Users\<twoje-konto>\.claude.json` → `mcpServers.lore`. Po rejestracji trzeba
zrestartować okna Claude Code.

## Przejście ze starej wersji (`historia`)

Przy pierwszym starcie moduł sam przejmuje dotychczasowe dane, nic nie licząc od nowa:

- `~/.claude/historia.db` (razem z `-wal`/`-shm`) jest **przenoszony** na `~/.claude/lore.db`,
- stare tabele `fragmenty` / `pliki` / `wektory` dostają nowe nazwy (`chunks` / `files` /
  `vectors`) wraz z kolumnami, a indeks pełnotekstowy jest przebudowywany,
- katalog modelu `~/.claude/historia_modele` jest przenoszony na `~/.claude/lore_models`,
- zmienna `CLAUDE_HISTORIA_HOME` nadal działa, jeśli nie ustawiono `LORE_HOME`,
- wszystko zostaje w `~/.claude` — do `~/.lore` idą tylko instalacje od zera.

Migracja jest idempotentna — kolejne uruchomienia nic już nie ruszają.

## Pełne przeindeksowanie od zera

Zamknij okna Claude Code (żeby serwer nie trzymał bazy), usuń `lore.db` z katalogu danych
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
- Zmienna `LORE_HOME` nadpisuje i katalog danych, i katalog transkryptów Claude Code
  (do testów: cała robota idzie wtedy na katalogu tymczasowym) — patrz „Gdzie leżą dane".
