# Pamięć dla agentów AI — przegląd projektów na GitHubie vs Lore

Data: 2026-09-24. Gwiazdki i daty ostatniego pusha pobrane na żywo z GitHub API (`gh api repos/...`) tego dnia.
Opisy mechaniki z README/dokumentacji/kodu repozytoriów (linki przy każdym projekcie). Benchmarki opisane jako
**twierdzenia autorów**, chyba że zaznaczono inaczej.

## Punkt odniesienia: Lore (nasze)
SQLite + FTS5 + wektory (multilingual-e5-small, lokalnie) + RRF, MCP (`lore_search`, `lore_context`); raz dziennie
model wyławia fakty tylko z wiadomości użytkownika; trzy warstwy tekstu: STAŁA (~2,7k tok. doklejana zawsze),
BIEŻĄCA (14 dni), REFERENCYJNA (na żądanie). Sprzeczności: rozstrzyga użytkownik. Wszystko lokalne.

## Tabela porównawcza

| Projekt | ★ / ostatni push | Na czym stoi | Co i jak trafia do kontekstu | Wygasanie / sprzeczności | Lokalnie bez API? | MCP / Claude Code / Codex |
|---|---|---|---|---|---|---|
| **claude-mem** (thedotmack) | 94,6k / 2026-09-24 | SQLite+FTS5 + Chroma (wektory) | SessionStart: **tylko indeks** (tabela ID/tytuł/typ/koszt w tokenach, ~800 tok. na 50 obserwacji); szczegóły agent dociąga narzędziami | brak jawnego mechanizmu sprzeczności (dziennik obserwacji) | częściowo: domyślnie hostowany „observer” (logowanie, trial), da się własny klucz/plan Anthropic; Windows opisany | plugin CC (hooki), 4 narzędzia MCP; inne hosty |
| **basic-memory** | 4,0k / 2026-09-24 | pliki Markdown + SQLite (FTS + wektory FastEmbed), graf z wikilinków | SessionStart: krótki brief z aktywnych zadań i ostatniej pracy (`recallTimeframe` 3d); reszta przez `build_context`/`search` | ręcznie (to Twoje pliki); brak automatycznej inwalidacji | **tak** (SQLite, FastEmbed lokalnie) | MCP + plugin CC + plugin Codex; Windows wspierany |
| **mcp-memory-service** (doobidoo) | 2,0k / 2026-09-24 | sqlite-vec + BM25, ONNX lokalnie; graf z typowanymi krawędziami | hooki startu sesji wstrzykują dobrane semantycznie wspomnienia; reszta przez MCP | „consolidation”: zanik (decay) + kompresja; krawędź `contradicts` | **tak** | MCP; lista klientów obejmuje CC i Codex CLI |
| **MemPalace** | 59,3k / 2026-09-23 | dosłowne przechowywanie rozmów, Chroma/SQLite; graf czasowy w SQLite | `mempalace wake-up` ładuje kontekst startowy; reszta wyszukiwaniem (45 narzędzi MCP) | graf z oknami ważności (`invalidate`, `timeline`) | **tak** (zero LLM do wyszukiwania) | MCP, import sesji CC (`mine ~/.claude/projects`) |
| **Letta / Letta Code** (MemGPT) | 24,9k (letta) / 3,4k (letta-code) | bloki pamięci w kontekście + archiwum wektorowe; MemFS w git | **agent sam edytuje** stałe bloki (limit rozmiaru na blok); archiwum przeszukuje narzędziem; „sleeptime/dreaming” porządkuje w tle | agent przepisuje blok (nadpisanie), historia w git | tryb lokalny istnieje, ale domyślnie Letta Cloud; potrzebny klucz LLM | osobny harness, nie dodatek; `claude-subconscious` = demo „nie do produkcji” |
| **mem0** | 65,9k / 2026-09-23 | wektory (+BM25 + encje) | aplikacja woła `search` przy każdej wiadomości i wkleja top-k | **od v3 (IV 2026): ADD-only, bez UPDATE/DELETE** — nic nie jest nadpisywane, aktualność rozstrzyga wyszukiwanie z uwzględnieniem czasu | domyślnie OpenAI (gpt-5-mini + text-embedding-3-small); da się Ollama | serwer MCP (OpenMemory), skille do CC/Codex |
| **Graphiti** (Zep) | 31,1k / 2026-09-24 | czasowy graf wiedzy (bi-temporal) + wektory + BM25 | aplikacja odpytuje graf (hybryda + przejścia grafu), wynik wkleja | **najlepsze w stawce**: fakty mają okno ważności, sprzeczny fakt unieważnia stary (nie kasuje) | **nie**: Neo4j/FalkorDB/Neptune + LLM ze structured output (domyślnie OpenAI); Kuzu wycofywany | serwer MCP w repo |
| **Zep** | 4,9k / 2026-09-18 | usługa zarządzana na Graphiti | złożony „context block” z grafu | jak Graphiti | **nie** (chmura) | plugin do CC/Codex (osobne repo) |
| **cognee** | 31,0k / 2026-09-24 | graf + wektory (+ sesje); w 1.0 może stać na jednym Postgresie | plugin CC: **wstrzykuje trafne fragmenty przy każdym promptcie**, sesję synchronizuje do grafu na koniec | `improve` (feedback), `forget` ręcznie; brak czasowej inwalidacji faktów | ingest+wyszukiwanie bez LLM tak; budowa grafu wymaga LLM (API lub Ollama) | plugin CC i Codex, MCP |
| **supermemory** | 30,9k / 2026-09-24 | graf + wektory (silnik własny) | profil (stałe + ostatnie) przez `/context`; plugin CC: model sam decyduje, czy szukać przed turą | twierdzą: obsługa sprzeczności i automatyczne zapominanie | plugin wymaga klucza chmury; tryb `supermemory local` (lokalne embeddingi, LLM przez Ollamę) — **nie sprawdziłem, czy silnik lokalny jest otwarty** | plugin CC i Codex, MCP (hostowany) |
| **MemOS** (MemTensor) | 11,6k / 2026-09-23 | self-host: Neo4j+Qdrant; plugin lokalny: SQLite FTS5+wektory | automatyczne przywołanie przed zadaniem, zapis po udanej turze | dedup, „skill evolution” | plugin lokalny tak (ale dla OpenClaw/Hermes/DeepSeek Harness) | brak oficjalnego pluginu CC/Codex |
| **MCP memory (oficjalny)**, modelcontextprotocol/servers `src/memory` | 90,6k (całe repo) / 2026-09-22 | graf encji/relacji w pliku JSON, bez wektorów | nic automatycznie; agent woła `read_graph`/`search_nodes` | brak | **tak** | MCP |

## Po akapicie na projekt

**claude-mem** — https://github.com/thedotmack/claude-mem , https://docs.claude-mem.ai/progressive-disclosure
Najbliższy nam architektonicznie (SQLite+FTS5, hybryda z wektorami Chroma, hooki CC) i najpopularniejszy. Kluczowa różnica: przy
starcie sesji wstrzykuje **indeks, nie treść** — tabelę z ID, tytułem, typem i szacowanym kosztem w tokenach każdej pozycji;
pełne obserwacje agent dociąga sam (`search` → `timeline` → `get_observations`). Autorzy podają „~10x oszczędności tokenów” —
ich szacunek, bez niezależnego pomiaru. Zapamiętuje obserwacje z użycia narzędzi (nie fakty z wiadomości użytkownika), więc to
bardziej dziennik pracy niż profil osoby. Uwaga: od niedawna domyślny jest hostowany „observer” z logowaniem i okresem próbnym
(plus token kryptowalutowy wspomniany w README) — sygnał komercjalizacji; tryb z własnym kluczem/planem istnieje.

**basic-memory** — https://github.com/basicmachines-co/basic-memory , plugin: `plugins/claude-code/README.md` w repo
Pamięć jako zwykłe pliki Markdown (wikilinki tworzą graf) + lokalny indeks SQLite z FTS i wektorami FastEmbed, opcjonalny
reranking. Plugin CC: przy SessionStart krótki brief z aktywnych zadań i pracy z ostatnich 3 dni (`recallTimeframe`), przed
kompaktowaniem zapis „checkpointu”, komendy `bm-decide`, `bm-orient`. Jest też plugin Codex — jedna baza dla obu naszych narzędzi.
Sprzeczności rozstrzyga człowiek/agent edytując plik — jak u nas. Licencja AGPL, część funkcji w płatnej chmurze.

**mcp-memory-service** — https://github.com/doobidoo/mcp-memory-service
Lokalnie: sqlite-vec + BM25, embeddingi ONNX, hooki startu sesji dla CC, konsolidacja z zanikiem i kompresją starych wspomnień,
krawędzie typu `causes/fixes/contradicts`. W README cytat użytkownika, który podpiął pod jedną bazę CC, Claude Desktop, Codex CLI
i OpenCode (anegdota, nie dowód). Benchmark LongMemEval R@5 80,4% (tura) / 86% (sesja) — pomiar autorów, ale opisany uczciwie
(model all-MiniLM-L6-v2, bez LLM) i z odniesieniem do krytyki MemPalace.

**MemPalace** — https://github.com/MemPalace/mempalace
Filozofia odwrotna do „wyławiania faktów”: trzyma rozmowy **dosłownie** i polega na dobrym wyszukiwaniu. LongMemEval R@5 96,6%
bez żadnego LLM — **twierdzenie autorów, zakwestionowane**: społeczny przegląd kodu (issue #27) wykazał, że wynik mierzy zwykły
ChromaDB, a nie ich architekturę; opiekunowie przyznali większość punktów. Pozytyw: sami nie porównują się z Mem0/Zep („różne
metryki”), podają wynik na zbiorze odłożonym (98,4%). Ma czasowy graf w SQLite z unieważnianiem faktów. Wniosek: nasz Lore
(archiwum dosłowne + hybryda) idzie w tym samym kierunku.

**Letta / MemGPT** — https://github.com/letta-ai/letta-code , https://github.com/letta-ai/claude-subconscious
Model „pamięci jak system operacyjny”: mały zestaw **bloków pamięci zawsze w kontekście, które agent sam przepisuje** (z limitem
rozmiaru), archiwum przeszukiwane narzędziem, „sleeptime/dreaming” — agent w tle porządkuje pamięć. Najbliższe naszej warstwie
STAŁEJ, tylko redaktorem jest agent, a nie cykl dzienny + zgoda użytkownika. Kod główny przeniósł się do Letta Code (osobny
harness — trzeba by zmienić narzędzie pracy). `claude-subconscious` podpina agenta Letty pod CC, ale autorzy sami piszą, że to
demo nie do produkcji. Blog Letty (VIII 2025): agent z samym systemem plików + grep dostał 74% na LoCoMo, więcej niż zgłaszane
68,5% Mem0 — też pomiar dostawcy (gpt-4o-mini, bez kategorii adversarial), ale ważny argument: **iteracyjne wyszukiwanie przez
agenta dorównuje wyspecjalizowanym pamięciom**. https://www.letta.com/blog/benchmarking-ai-agent-memory/

**mem0** — https://github.com/mem0ai/mem0
Najpopularniejsza biblioteka „warstwy pamięci”. Zmiana z IV 2026 (v3): ekstrakcja **ADD-only, jedno wywołanie LLM, bez
UPDATE/DELETE** — wcześniejsze rozstrzyganie sprzeczności przez LLM porzucili; stare fakty zostają, aktualność rozstrzyga
wyszukiwanie z uwzględnieniem czasu. Wstrzykiwanie: aplikacja przy każdej wiadomości robi `search` i wkleja top-k (~7k tokenów
na zapytanie w ich benchmarku). Wyniki 92,5 LoCoMo / 94,4 LongMemEval są **własne i z platformy zarządzanej, która wg README ma
optymalizacje niedostępne w wersji open source**. Domyślnie OpenAI.

**Graphiti / Zep** — https://github.com/getzep/graphiti , artykuł https://arxiv.org/abs/2501.13956
Jedyny projekt, który naprawdę rozwiązuje „nowy fakt przeczy staremu”: krawędzie grafu mają okna ważności (bi-temporalnie),
sprzeczny fakt unieważnia poprzedni, historia zostaje, można pytać „co było prawdą w marcu”. Cena: Neo4j/FalkorDB (Docker lub
Neo4j Desktop) + LLM ze structured output przy każdym zapisie; lokalny Kuzu jest wycofywany. Co wkleić, decyduje aplikacja
(wyszukiwanie hybrydowe + przejścia grafu). Benchmarki: spór Zep vs Mem0 o LoCoMo dał **cztery różne wyniki dla tego samego
systemu (65,99 / 84 / 58,44 / 75,14)**, w tym błąd arytmetyczny po stronie Zep — dlatego liczb dostawców nie należy porównywać.
https://ai-coding.wiselychen.com/agent-memory-benchmark-rashomon-filesystem/

**cognee** — https://github.com/topoteretes/cognee , plugin: https://github.com/topoteretes/cognee-integrations/tree/main/integrations/claude-code
Graf + wektory, operacje `remember/recall/improve/forget`. Plugin CC (i Codex, wspólna konfiguracja `~/.cognee/.env`) zapisuje
prompty i ślady narzędzi, **przy każdym promptcie wstrzykuje trafne fragmenty**, na koniec sesji przenosi wiedzę do grafu. Tryb
lokalny stawia serwer Pythona (port 8011) i nadal wymaga `LLM_API_KEY` do budowy grafu (albo Ollamy). Benchmark BEAM — autorzy
sami zaznaczają konfigurację „benchmark-specific”.

**supermemory** — https://github.com/supermemoryai/supermemory , https://github.com/supermemoryai/claude-supermemory
Produkt chmurowy z otwartymi pluginami (CC, Codex). Plugin CC: „reasoned recall” — model przed każdą turą decyduje, czy w ogóle
szukać; profil użytkownika (stałe fakty + ostatnia aktywność) przez `/context`. Twierdzą, że obsługują sprzeczności i zapominanie.
„#1 na każdym benchmarku” — własne twierdzenie; wydali też otwarte MemoryBench do porównań. Tryb `npx supermemory local`
z lokalnymi embeddingami i Ollamą — licencji silnika nie weryfikowałem.

**MemOS** — https://github.com/MemTensor/MemOS
Rozbudowany „system operacyjny pamięci”; self-host wymaga Neo4j + Qdrant, plugin lokalny (SQLite FTS5 + wektory) jest dla
OpenClaw/Hermes/DeepSeek Harness, nie dla CC/Codex. Wyniki 88,83 LoCoMo / 89,20 LongMemEval — własne.

**Oficjalny serwer MCP „memory”** — https://github.com/modelcontextprotocol/servers/tree/main/src/memory
Graf encji/relacji/obserwacji w jednym pliku JSON, bez wektorów, bez automatyki. Punkt odniesienia „najprostszego grafu”; forki
z Neo4j/DuckDB/SQLite (np. shaneholloman/mcp-knowledge-graph 891★, memory-graph/memory-graph 247★) są małe.

**Wbudowana pamięć Claude Code** — https://code.claude.com/docs/en/memory
CLAUDE.md ładowany w całości przy starcie; auto-memory `MEMORY.md` — **pierwsze 200 linii lub 25 KB**; importy `@plik` też
ładują się od razu; **`.claude/rules/` z polem `paths:` ładuje się dopiero, gdy agent dotyka pasujących plików**. Darmowy
mechanizm „doklejaj tylko gdy potrzebne” — ale działa po ścieżkach plików, nie po temacie rozmowy.

## Wnioski dla Lore (moje, do weryfikacji)

1. **Grafy wiedzy nie rozwiązują naszego głównego kosztu.** Rozwiązują sprzeczności w czasie (Graphiti), ale kosztem Neo4j + LLM
   przy każdym zapisie. Przy jednej osobie i kilkuset faktach to armata na muchy.
2. **Kierunek branży przy „co wstrzyknąć”: indeks zamiast treści** (claude-mem), krótki brief z ostatnich dni (basic-memory)
   albo wyszukiwanie na żądanie z decyzją modelu (supermemory, Letta). Żaden z dużych projektów nie dokleja pełnego profilu jak my.
3. **Sprawdzone lokalnie dziś:** w transkryptach CC widać `cache_read_input_tokens` (np. 29 761 z cache przy 2 tokenach świeżego
   wejścia). Stały plik na początku kontekstu jest więc najpewniej czytany z cache promptów (cena ~10% zwykłej).
   Zanim cokolwiek przebudujemy — **zmierzyć z transkryptów, ile warstwa STAŁA realnie kosztuje po uwzględnieniu cache**.
   Możliwe, że 5 000 tokenów na start to w pieniądzach ułamek tego, co wygląda.
4. Benchmarki (LoCoMo, LongMemEval) to pomiary dostawców na własnych ustawieniach; audyty wskazują błędy w samym LoCoMo
   (~99 błędnych odpowiedzi wzorcowych na 1 540 wg audytu Penfield Labs — też dostawcy). Nie opierać na nich decyzji.

## Źródła dodatkowe
- Letta, „Is a Filesystem All You Need?”: https://www.letta.com/blog/benchmarking-ai-agent-memory/
- Przegląd sporu o LoCoMo: https://ai-coding.wiselychen.com/agent-memory-benchmark-rashomon-filesystem/
- Esej o „teatrze benchmarków”: https://essays.bloo-mind.ai/posts/2026-05-20-mem-eval/
- MemPalace issue #27: https://github.com/MemPalace/mempalace/issues/27
