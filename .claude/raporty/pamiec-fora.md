# Pamięć dla agentów AI: co naprawdę mówią praktycy (rozpoznanie 2026-09-24)

Oznaczenia: **[D]** doświadczenie z użycia (pierwsza ręka) · **[B]** badanie/pomiar · **[O]** opinia/argument · **[2R]** relacja z drugiej ręki · **[V]** źródło sprzedające konkurencyjny produkt pamięci (stronnicze).

Uwaga o źródłach: wyszukiwarka nie zwróciła ANI JEDNEGO wątku z Reddita (ani r/ClaudeAI, ani r/LocalLLaMA). Głosy "z forów" pochodzą z Hacker News, GitHub Issues i blogów. Reddit pojawia się tylko w relacjach z drugiej ręki. Dużo materiału o pamięci pochodzi od firm, które ją sprzedają (Mem0, Zep, Vectorize/Hindsight, Milvus, Papr) — oznaczam je [V].

---

## 1. Czy grafy wiedzy się sprawdzają, czy to moda?

- **[D] Graf porzucony na rzecz SQLite.** Użytkownik *brainless* (HN) zbudował własny graf na RocksDB: "I found it hard to ask LLM to traverse it." Przeszedł na SQLite, bo "LLMs are really good at using sqlite3". Jeden głos. https://news.ycombinator.com/item?id=45329322
- **[D] Wektory pomogły tam, gdzie słowa kluczowe zawodziły** — *muzani* (HN): wielojęzyczne synonimy ("credit card"/"kartu") dawały fałszywe trafienia przy wyszukiwaniu po słowach; wektory to rozwiązały. Jeden głos, ale dokładnie nasz przypadek (PL/DE/EN). Ten sam wątek.
- **[B] Zwykły plik pobił wyspecjalizowane narzędzia pamięci na benchmarku LoCoMo** — Letta: 74,0% przy samej historii w pliku i narzędziach plikowych, więcej niż wariant grafowy Mem0 (68,5% wg relacji trzeciej). Uzasadnienie: modele są wytrenowane na narzędziach plikowych; grafy "can be harder for the model to understand". Letta też jest firmą od pamięci. https://www.letta.com/blog/benchmarking-ai-agent-memory/
- **[B] Pomiar z Show HN (OKF Agent Memory)**: czyste BM25 bez wektorów 18/100 trafień na 1. miejscu, cięższe narzędzie agentmemory 14/100 (plus cztery porty i proces w tle). Mała próba, autor jest stroną. https://news.ycombinator.com/item?id=49581240
- **[O] Książka o agentach kodujących (arXiv, sierpień 2026)**: "Add memory infrastructure only for measured retrieval failures" — przykład projektu z grafem i bazą wektorów, zanim ktokolwiek zadał pierwsze pytanie. Autor sam przyznaje, że teza jest "contested". https://arxiv.org/pdf/2608.13867
- **[V/O] Za grafem**: Graphiti/Zep jako jedyne mają "ważność w czasie" faktów (kiedy fakt był prawdziwy); na LongMemEval, podzadanie czasowe: Zep 63,8% vs Mem0 49,0%. Ale benchmarki producentów są wzajemnie podważane (Zep 84% skorygowane do 75,14%, Mem0 powtórzył i dostał 58,44%). Rada recenzenta: 30 pytań z własnych danych mówi więcej niż ich benchmarki. https://atlan.com/know/zep-vs-mem0/ , https://vectorize.io/articles/mem0-vs-zep
- **[2R/V] Koszt grafu**: Graphiti puszcza przebieg modelu na każdy kawałek rozmowy (wyłuskanie encji i relacji), a samodzielne utrzymanie wymaga Neo4j/FalkorDB. Te same źródła.
- **[O] Pozycja środkowa, powtarzana w wielu miejscach**: najpierw hybryda wektory + pełny tekst (BM25) — "the correct first move" — graf dopiero przy konkretnych porażkach: ta sama osoba pod różnymi nazwami, pytania wymagające łączenia faktów, fakty zmieniające się w czasie. https://hindsight.vectorize.io/blog/2026/08/24/knowledge-graphs-vs-vector-search-agent-memory [V]
- **[O] Trend "graf z linków w markdownie"**: Basic Memory, Obsidian Memory MCP — pliki .md z linkami `[[...]]` zamiast bazy grafowej. https://pypi.org/project/basic-memory/

**Wniosek do pyt. 1:** Nie znalazłem nikogo, kto z pierwszej ręki opisał, że przejście na graf poprawiło mu pamięć agenta kodującego. Znalazłem jedno odejście od grafu (do SQL) i kilka pomiarów, w których prostsze wygrywa. Argumenty za grafem pochodzą niemal wyłącznie od producentów grafów.

---

## 2. Stały plik doklejany kontra wyszukiwanie na żądanie — czy model sam sięga po narzędzie?

- **[D] Najmocniejszy dowód: 0 wywołań w 252 sesjach.** Zgłoszenie w memsearch (Milvus): mimo że zapis działał miesiącami (35 dziennych logów, indeks zdrowy), skill przypominania był wywołany "0 times across 252 sessions". Automatycznie docierało tylko to, co hook SessionStart dokleił (2 ostatnie dni) — starsze rzeczy były "effectively unreachable". Częściowa przyczyna to błąd (podpowiedź szła do użytkownika, nie do modelu), ale model też nie sięgał po narzędzie sam. Poprawka zgłaszającego: wyszukiwanie wykonywane W HOOKU i wynik wstrzykiwany do promptu — mediana 1,5 s na zapytanie, wyciągnęło poprawny kontekst sprzed miesiąca. https://github.com/zilliztech/memsearch/issues/738
- **[D] ramblurr (HN)**: "the agent isn't using the retrieval tools enough to make it useful." Brak odpowiedzi w wątku. https://news.ycombinator.com/item?id=47449389
- **[D] Autor mcp-server-memory**: nawet z podpowiedziami w odpowiedziach narzędzia "I couldn't get Claude to store memories" — potrzebna wskazówka w prompcie. https://glama.ai/mcp/servers/@g0t4/mcp-server-memory-file/blob/e86b9f5ec1f624be5c23292d5357eb55c7838d12/README.md
- **[D] Wpis na DEV (marzec 2026)**: memory-MCP na SQLite — "When Claude remembered to use it, it was actually pretty good"; trzeba było przypominać przez CLAUDE.md, "it's not autonomous". Wynik łączony ok. 80% oczekiwanej ciągłości. https://dev.to/gonewx/i-tried-3-different-ways-to-fix-claude-codes-memory-problem-heres-what-actually-worked-30fk
- **[O] ClaudeLog**: "Memory MCP is only useful if Claude remembers to consult it." https://claudelog.com/claude-code-mcps/memory-mcp/
- **[D] Stały plik działa zaskakująco dobrze w małej skali** — *daxaur* (HN): płaskie MEMORY.md czytane na starcie, "works better than you'd expect"; kilkaset linii wystarcza przy osobistym asystencie. https://news.ycombinator.com/threads?id=daxaur
- **[D] Ale stały plik też bywa ignorowany** — *bigbezet* (HN): agenci nie zawsze słuchają AGENTS.md, zwłaszcza przy dużym kontekście; "If we want to guarantee that something happens, we should use hooks." *esperent*: "I already have to fight the agent constantly." https://news.ycombinator.com/item?id=47486287
- **[B] Badanie ETH Zurych (arXiv 2602.11988)**: pliki kontekstowe nie podnoszą skuteczności zadań w sposób istotny statystycznie, a koszt rośnie o ponad 20%. Pliki generowane przez model: ok. -3% skuteczności; pisane przez ludzi: ok. +4%. Agenci **wykonują** polecenia z pliku (np. użycie `uv` z ~0 do 1,6 razy na zadanie) — problem nie w ignorowaniu, tylko w dokładaniu roboty. Zalecenie: tylko to, czego nie da się wyczytać z kodu. https://arxiv.org/abs/2602.11988 . Uwaga: inne badanie (2601.20404) pokazało odwrotny efekt kosztowy (ok. -20% tokenów wyjścia); późniejsza ablacja (2607.27250) — brak poprawy poprawności. To pojedyncze badania, nie wyrok.
- **[Oficjalne] Dokumentacja Claude Code**: pamięć to kontekst, nie wymuszona konfiguracja; krótszy CLAUDE.md = lepsze przestrzeganie. Tekst wstrzykiwany hookiem pisać jako fakty, nie rozkazy, bo inaczej może zadziałać obrona przed wstrzyknięciem promptu. https://code.claude.com/docs/en/memory , https://code.claude.com/docs/en/hooks
- **[O] Cytat przypisywany autorowi claude-code-semantic-memory**: "Build systems, not intentions." https://github.com/openclaw/openclaw/issues/12213

**Wniosek do pyt. 2:** Najlepiej udokumentowany punkt. Wiele niezależnych głosów: model **nie sięga sam** po narzędzie wyszukiwania pamięci; niezawodne jest tylko to, co wjeżdża do kontekstu automatycznie (plik przy starcie albo hook wstrzykujący wyniki wyszukiwania do promptu). Instrukcja w CLAUDE.md "szukaj w pamięci" pomaga, ale nie gwarantuje.

---

## 3. Problemy powtarzające się u wszystkich

- **Śmieci / model nie wie, co warto pamiętać** — [D] *bigbezet*: agent "would not really understand what is important"; tworzył "a lot of bloat". [D] *chrisdudek*: "agents have no clue what's worth remembering" — jego rozwiązanie: agent notuje, człowiek decyduje. https://news.ycombinator.com/item?id=47486287
- **Stara pamięć szkodzi** — [D] *gaigalas*: po usunięciu wpisu o sesji debugowania agent "just unlocked itself again"; harness "replaying the trauma". [D] *esperent*: notatki o porzuconych podejściach przywracają stary kod. [D] *chrisdudek*: jednostronne notatki w dzienniku robią z agenta "yes-man". Ten sam wątek.
- **Pamięć przecieka między tematami** — [D] Simon Willison o pamięci ChatGPT: dopisało do obrazka "Half Moon Bay", bo wspomniał o tym kiedyś; nie chce, by hobby wpływało na pracę; chce wiedzieć, co jest w kontekście. Później chwalił pamięć ograniczoną do projektu. https://simonwillison.net/2025/May/21/chatgpt-new-memory/
- **Sprzeczności** — [O] na HN padło pytanie ("hates espresso but loves coffee"), nikt nie podał działającego rozwiązania. https://news.ycombinator.com/item?id=45329322 . [O/V] Ogólna rada branży: nie kasować, tylko oznaczać stary fakt jako zastąpiony; trzymać odnośnik do źródłowej rozmowy. https://hindsight.vectorize.io/blog/2026/05/21/agent-memory-consolidation
- **Pamięć przepisywana przez model psuje się z czasem** — [B] arXiv 2605.12978: przy ciągłej konsolidacji przez LLM użyteczność pamięci najpierw rośnie, potem spada, może zejść **poniżej braku pamięci**. https://arxiv.org/pdf/2605.12978
- **Błędny wpis się rozprzestrzenia** — [B] arXiv 2505.16067: złe rekordy psują kolejne zadania; ścisłe, selektywne dodawanie z początku przegrywa, po ok. 2000 wykonaniach wygrywa. https://arxiv.org/pdf/2505.16067
- **Ciche ucinanie** — [V/2R] Mem0 o Claude Code: MEMORY.md ucinany po 200 liniach bez ostrzeżenia. https://mem0.ai/blog/how-memory-works-in-claude-code . [V] Milvus: po tygodniach indeks pełen sprzeczności i nieaktualnych odnośników. https://milvus.io/blog/claude-code-memory-memsearch.md
- **Rosnący koszt** — [D] Cline, dyskusja #2979: ok. 300 tys. tokenów po ~5 iteracjach mimo Memory Bank. https://github.com/cline/cline/discussions/2979 . Standardowy Memory Bank każe czytać WSZYSTKIE pliki na starcie każdego zadania.
- **Brak metryk** — [D] *AndyNemmity* (HN): "I don't think there are reasonable metrics." Phil Schmid: skutki złej strategii wychodzą dopiero po czasie. https://news.ycombinator.com/item?id=47449389 , https://www.philschmid.de/memory-in-agents
- **Halucynowane wspomnienia** — tylko badania: HaluMem (benchmark fałszywych/nieistotnych wpisów) i MemR3 (fałszywe pozytywy przy wyłuskiwaniu). Nie znalazłem relacji z pierwszej ręki o "wymyślonych wspomnieniach" w agentach kodujących. https://arxiv.org/pdf/2511.03506

---

## 4. Automatyczne wyławianie faktów z rozmów

- **[B] ChatGPT robi to masowo**: z 7 051 aktualizacji pamięci tylko 4,64% z polecenia użytkownika, 95,36% wyłuskane automatycznie. https://arxiv.org/pdf/2609.14697
- **[2R] Skutki w ChatGPT** (zebrane z r/ChatGPT i X przez autora na Medium): "context rot", zaśmiecanie nieistotnym; cytowany użytkownik: "you have to turn it off to trust any answer." https://medium.com/@nirajkvinit/the-double-edged-sword-of-chatgpts-memory-promise-pitfalls-and-practical-fixes-298359dcb1a5 . Przewodnik naprawczy: przypadkowe wzmianki stają się trwałymi faktami; fakt zapisany bez uzasadnienia. https://mindlock.io/blog/how-to-fix-chatgpt-memory-issues
- **[D] Ask HN "Mem0 stores memories, but doesn't learn user patterns"**: Mem0/Letta tylko zapisują fakty ("user prefers Python"); autor uznał, że najwięcej sygnału niosą **poprawki użytkownika** (np. próg zmieniany 3 razy z 85% na 80%) i zbudował zapis zdarzeń: co agent dał, co użytkownik zmienił, co przyjął. https://news.ycombinator.com/item?id=46891715
- **[D] sdesol (HN)**: po każdej wiadomości tani model pisze krótki opis ze słowami kluczowymi; przy pytaniu model rozwija zapytanie na kilka fraz. Krytyka *adastra22*: kruche i droższe niż embeddingi. https://news.ycombinator.com/item?id=45329322
- **[D] kageroumado (HN)**: baza każdej wiadomości + streszczenia poziomu 0, okresowo scalane w poziom 1 z samymi lekcjami; wyniki narzędzi stopniowo wycinane; "outperforming every other solution I tried". Jeden głos, zastosowanie: osobisty asystent. https://news.ycombinator.com/item?id=47449389
- **[D] Odsiewanie przez człowieka** — *chrisdudek*: agent zapisuje, człowiek wybiera. *slake* (HN) proponuje przegląd przez człowieka — tylko pomysł. https://news.ycombinator.com/item?id=47486287
- **[O] Zalecenia odsiewu, powtarzane w kilku źródłach**: wysoki próg wpisu; "poczekalnia" (bufor próbny, awans po weryfikacji, deduplikacji, ocenie ważności — przegląd arXiv 2603.07670); link z faktu do źródłowej rozmowy; nie streszczać streszczeń. OpenAI cookbook: konsolidacja to najbardziej zawodny etap. https://arxiv.org/html/2603.07670v1 , https://developers.openai.com/cookbook/examples/agents_sdk/context_personalization
- **[O/V] Anthropic sam to robi** w Claude Code: auto memory + "Auto Dream" (między sesjami czyta transkrypty, scala fakty, usuwa sprzeczne, przycina indeks do 200 linii) — według odczytu kodu przez Mem0, część za flagami. Brak niezależnych relacji o skuteczności. https://mem0.ai/blog/how-memory-works-in-claude-code

---

## 5. Ograniczanie kosztu kontekstu — co komuś zadziałało

- **[B] Krótko i tylko to, czego nie ma w kodzie** — ETH (pyt. 2): każdy plik kontekstu podnosi koszt ok. 20%; zawartość, którą agent i tak by odkrył, jest czystym kosztem. https://developer.upsun.com/posts/ai/agents-md-less-is-more
- **[Oficjalne] Indeks + pliki tematyczne na żądanie** — Claude Code ładuje tylko pierwsze 200 linii / 25 KB MEMORY.md, reszta w plikach tematycznych czytanych w razie potrzeby. Zasada projektowa: nie zapisuj ścieżek, historii git, wzorców kodu — da się je odczytać na żywo. https://code.claude.com/docs/en/memory , https://harrisonsec.com/blog/claude-code-memory-first-principles-tradeoffs/ . [O] ShipWithAI: wpis w indeksie = wskaźnik poniżej 150 znaków, nie treść. https://shipwithai.io/blog/claude-code-memory-md-fix
- **[D] Hook z top-k zamiast wszystkiego** — memsearch #738 (1,5 s; k=8 lepsze niż k=5; uwaga: wynik 0,500 oznaczał "brak dopasowania", więc próg >0,5 stał na podłodze); claude-mem wstrzykuje domyślnie 5 obserwacji, ciężką robotę zleca procesowi w tle. https://github.com/zilliztech/memsearch/issues/738 , https://docs.claude-mem.ai/hooks-architecture
- **[O] Koszt samych narzędzi MCP** — definicje narzędzi każdego serwera MCP jadą z każdą wiadomością (do ok. 18 tys. tokenów na turę wg MindStudio; liczba z jednego źródła), a 50+ narzędzi pogarsza rozumowanie. https://www.mindstudio.ai/blog/claude-code-mcp-server-token-overhead
- **[D] Hierarchiczne streszczenia + wycinanie wyników narzędzi** — kageroumado (pyt. 4): jedna nieprzerwana sesja bez kompaktowania.
- **[O] Leksykalne wyszukiwanie z twardym budżetem** poniżej ok. 50 tys. notatek bije bazę wektorową — twierdzenie jednego autora newslettera, bez danych. https://theaioperator.io/p/how-i-gave-claude-code-memory-without
- **[D] Kontrargument** — *renewiltord* (HN): próbował SQLite + embeddingi, bez poprawy; "Best is still to just stuff things in context." https://news.ycombinator.com/item?id=47486287
- **[B/2R] Graf taniej** — TERAG (relacja z newslettera): ok. 80% skuteczności GraphRAG przy 3–11% tokenów wyjścia. https://aimemory.substack.com/p/ai-memory-monthly-october-2025

---

## Odniesienie do naszego podejścia

**Potwierdzają:**
- Archiwum w SQLite z hybrydą pełny tekst + wektory = dokładnie "pierwszy krok", który zaleca większość źródeł; graf dopiero przy zmierzonych porażkach.
- Wielojęzyczne wektory mają realne uzasadnienie (przypadek *muzani*).
- Pliki markdown doklejane na starcie + warstwa referencyjna na żądanie = to samo co Claude Code (indeks 200 linii + pliki tematyczne) i to, co praktycy chwalą w małej skali.
- Poczekalnia z decyzją człowieka (kandydaci.md) = zalecenie z kilku niezależnych źródeł (*chrisdudek*, przegląd arXiv 2603.07670); ścisłe dodawanie wygrywa w długim okresie.
- Wygasanie po 14 dniach = odpowiedź na "stara pamięć szkodzi" (*gaigalas*, *esperent*).

**Przeczą / ostrzegają:**
- **Wyszukiwanie przez MCP, po które model ma sięgać sam, prawdopodobnie jest używane rzadko.** Najmocniejszy dowód (0 w 252 sesjach) i kilka zbieżnych głosów. Instrukcja w CLAUDE.md pomaga, ale praktycy przechodzą na hook `UserPromptSubmit`, który sam szuka i wstrzykuje top-k wyników. Warto zmierzyć na naszych transkryptach, ile razy `lore_search` faktycznie pada.
- Najlepszym sygnałem do wyławiania wydają się **poprawki** użytkownika (Ask HN 46891715) — warto sprawdzić, czy nasza ekstrakcja je wyróżnia.
- Ciągłe przepisywanie/scalanie pamięci przez model może ją z czasem pogarszać (arXiv 2605.12978) — dobrze, że fakty czekają na decyzję człowieka; źle byłoby automatyczne scalanie warstwy stałej.
- Stała warstwa to koszt przy każdym zapytaniu, a wg ETH treść, którą agent i tak odczyta z plików/API, nie poprawia wyników. Warto przejrzeć stałą warstwę pod kątem "czy da się to odczytać na żywo".

**Czego nie znalazłem:** relacji z Reddita (brak wyników w wyszukiwarce), relacji z pierwszej ręki o udanym przejściu na graf w agencie kodującym, relacji o halucynowanych wspomnieniach w agentach kodujących.
