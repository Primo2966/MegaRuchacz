# Pamięć agenta: graf wiedzy vs wektory vs hybryda — twarde dowody

Rozpoznanie z 2026-09-24. Tylko źródła z liczbami. Przy każdym wyniku podaję, kto mierzył, na czym i jak mocny to dowód.

**Skala siły dowodu:**
- **[NIEZALEŻNY]**: mierzył ktoś, kto nie jest autorem żadnej z porównywanych metod (reprodukcja albo benchmark akademicki).
- **[AUTOR]**: autorzy mierzą własną metodę, zwykle na własnym zbiorze albo we własnej konfiguracji konkurencji. Słabszy dowód.
- **[KONKURENT]**: dostawca mierzy konkurenta. Najsłabszy dowód, bo ma interes w złym wyniku.
- **[NIEPEŁNY]**: liczba ze streszczenia, abstraktu albo źródła wtórnego, nie sprawdzona w tabeli pracy.

---

## 1. Graf wiedzy vs wektory vs hybryda w pamięci konwersacyjnej

### 1a. Pomiary kontrolowane i reprodukcje (najmocniejsze dowody)

| Praca | Kto | Zbiór | Wynik | Siła |
|---|---|---|---|---|
| [MemDelta (arXiv 2606.29914)](https://arxiv.org/abs/2606.29914) | K. Wang, niezależny | LongMemEval-S, 500 pytań, 3 rodziny modeli | Zwykły RAG na surowych wypowiedziach 47,2% vs pełny kontekst 49,8% (GPT-4o-mini, różnica nieistotna, p=0,34). **Sama zmiana modelu embeddingów daje +6,2 pp** (p=0,004). Mem0 bije RAG na MiniLM o +11 pp, ale **przegrywa o 1,2 pp z RAG na lepszym embeddingu**. Na 2 z 6 typów pytań Mem0 remisuje z RAG (72,7 vs 73,9%) przy **~50× wyższym koszcie**. Ekstrakcja Mem0 to ponad 1000 wywołań LLM. | [NIEZALEŻNY] |
| [Reproducing LightMem (arXiv 2607.29104)](https://arxiv.org/abs/2607.29104) | University of Queensland / CSIRO (Zuccon, Koopman), niezależni | LongMemEval-S, 444 pytania, Qwen3-30B, sędzia gpt-5.5 | Pełny kontekst 60,8%, **naiwny RAG 67,3%**, LightMem 57,0–70,7% zależnie od ustawień. Przy tej samej głębokości wyszukiwania naiwny RAG wygrywa średnio o 2,4–4,8 pp. **Zmiana samego retrievera: 58,1% (BM25) → 75,5% (Qwen3-Embedding-4B).** Naiwny RAG + SPLADE-v3 top-10 daje 78,8%, czyli więcej niż LightMem z wyrocznią (77,7%). Wyrocznia z dowodami: RAG 89,0% vs LightMem 77,7%, więc budowa pamięci **gubi informację**. Fuzja BM25 + wyszukiwanie wektorowe: „brak stałej korzyści”. | [NIEZALEŻNY] |
| [ConvoMem (arXiv 2511.10523)](https://arxiv.org/abs/2511.10523) | Pakhomov, Nijkamp, Xiong (Salesforce) | własny, 75 336 par pytanie-odpowiedź | Do ~150 rozmów pełny kontekst daje 70–82%, Mem0 30–45%. Progi: poniżej 30 rozmów najlepszy pełny kontekst, 30–150 jeszcze akceptowalny, powyżej 150 potrzebny RAG albo hybryda (koszt i opóźnienie). | [NIEZALEŻNY wobec Mem0], ale na własnym zbiorze |
| [Ground Truth First (arXiv 2607.21962)](https://arxiv.org/abs/2607.21962) | Q. Spencer, jeden autor | syntetyczny, ~380 pytań, 6 symulowanych użytkowników, horyzont 3 i 9 tygodni | **„Tenure crossover”**: po 3 tygodniach prowadzi prosta „mapa” faktów, po 9 tygodniach jej trafność spada z 96% do 72%, a **graf z typowanym pochodzeniem faktów rośnie do 90%**. Pełna historia wygrywa po 3 tygodniach, po 9 traci przewagę i kosztuje ~2× więcej. Źle zapisane fakty zawodzą w 24% przypadków, dobrze zapisane w 2%. | [AUTOR] (autor wydaje bibliotekę Veracium); dane syntetyczne |
| [Mnemis (arXiv 2602.15313)](https://arxiv.org/abs/2602.15313), tabela 1: ponowne uruchomienie metod bazowych | autorzy Mnemis (metoda konkurencyjna) | LoCoMo, GPT-4o-mini | Pełny kontekst 72,3; **RAG 68,2; Mem0 61,3; Zep (graf) 58,5** | [KONKURENT wobec Mem0/Zep, ale nie wobec RAG] [NIEPEŁNY] |

**Wniosek z niezależnych pomiarów:** na obu głównych benchmarkach (LongMemEval, LoCoMo) dobrze ustawiony zwykły RAG dorównuje systemom z LLM-ową strukturyzacją (Mem0, LightMem, graf Zep) albo je bije. **Największą dźwignią jest jakość embeddingu, retrievera i rankingu (+6 do +17 pp), a nie struktura pamięci.**

### 1b. Wyniki autorów i spory dostawców (słabe dowody)

| Źródło | Liczby | Siła |
|---|---|---|
| [Zep/Graphiti: Rasmussen i in. 2025](https://arxiv.org/abs/2501.13956) | LongMemEval: Zep 71,2% (GPT-4o) vs pełny kontekst ~60,2%. Największe zyski na pytaniach czasowych i obejmujących wiele sesji. | [AUTOR] |
| [Mem0 (arXiv 2504.19413)](https://arxiv.org/html/2504.19413), LoCoMo, metryka J | Mem0 66,88; **Mem0g (graf) 68,44**; Zep 65,99; najlepszy RAG 60,97; **pełny kontekst 72,90** (26k tokenów, p95 17 s). Graf wygrywa w pytaniach **czasowych** (58,1 vs 55,5) i open-domain, a **przegrywa w jednoskokowych (65,7 vs 67,1) i wieloskokowych (47,2 vs 51,2)**. Budowa pamięci: Mem0 ~7k tokenów na rozmowę, Mem0g ~14k (2×), Zep ponad 600k. | [AUTOR] + [KONKURENT wobec Zep] |
| [Zep: „Is Mem0 really SOTA”](https://blog.getzep.com/lies-damn-lies-statistics-is-mem0-really-sota-in-agent-memory/) vs [Mem0, issue #5](https://github.com/getzep/zep-papers/issues/5) | Zep o sobie na LoCoMo: 84%, potem poprawione na 75,14%. Mem0 po replikacji: Zep 58,44%. | [KONKURENT] w obie strony, nierozstrzygnięte |
| [Mem0 research 2026](https://mem0.ai/research) | Mem0: LoCoMo 92,5, LongMemEval 94,4 (~6,9k tokenów na zapytanie) | [AUTOR]. Zgłaszane problemy z odtworzeniem wyników (issues #2800, #3943, #3944 według [ATANT v1.1](https://arxiv.org/abs/2604.10981)) |

Uwaga: Mem0 **przestał domyślnie używać własnego trybu grafowego**. Według ich własnej pracy graf był wolniejszy (~2× opóźnienie p95), droższy (2× tokenów) i słabszy w pytaniach jedno- i wieloskokowych.

### 1c. GraphRAG na dokumentach (nie rozmowach): niezależny benchmark akademicki

[When to use Graphs in RAG / GraphRAG-Bench (arXiv 2506.05690, ICLR 2026)](https://arxiv.org/abs/2506.05690), Xiamen University + PolyU. [NIEZALEŻNY] wobec testowanych metod, model GPT-4o-mini:

| Zadanie | Novel: RAG / RAG+rerank | Novel: najlepszy graf | Medical: RAG / RAG+rerank | Medical: najlepszy graf |
|---|---|---|---|---|
| Wyszukanie faktu | 58,76 / **60,92** | HippoRAG2 60,14 | 63,72 / 64,73 | HippoRAG2 66,28 |
| Rozumowanie złożone | 41,35 / 42,93 | **HippoRAG2 53,38** | 57,61 / 58,64 | HippoRAG2 61,98 |
| Streszczenie | 50,08 / 51,30 | **MS-GraphRAG 64,40** | 63,72 / 65,75 | Fast-GraphRAG 67,88 |
| Twórcze | 41,52 / 38,26 | HippoRAG2 48,28 | 58,94 / 60,61 | HippoRAG2 68,05 |

Tokeny promptu na zapytanie: RAG ~900, HippoRAG2 ~1 000, LightRAG ~100 000, MS-GraphRAG global ~331 000.
Wniosek autorów: przy prostym wyszukiwaniu faktów graf dokłada szumu. Wygrywa przy rozumowaniu wieloskokowym i streszczaniu całości (+10–14 pp).
Wcześniejsze pomiary cytowane w tej pracy: GraphRAG −13,4% vs RAG na Natural Questions i −16,6% na pytaniach wrażliwych na czas (Han i in. 2025); +4,5% na wieloskokowym HotpotQA przy 2,3× wolniejszym działaniu (Zhou i in. 2025). [NIEPEŁNY: liczby z cytatu]

### Kiedy graf realnie wygrywa (podsumowanie)
- **Pytania czasowe, „co się zmieniło”, aktualizacje wiedzy**: Zep +11 pp vs pełny kontekst [AUTOR]; Mem0g +2,6 pp w pytaniach czasowych [AUTOR]; graf z pochodzeniem faktów wygrywa przy dłuższym horyzoncie [AUTOR, dane syntetyczne]. Brak niezależnego potwierdzenia na prawdziwych danych.
- **Rozumowanie wieloskokowe i streszczanie całego zbioru**: +10–14 pp [NIEZALEŻNY, ale na dokumentach, nie rozmowach].
- **Przerost formy**: pojedyncze fakty („jaki był tytuł…”, „co ustaliliśmy o X”). Tu RAG jest co najmniej tak dobry jak graf we wszystkich niezależnych pomiarach.

---

## 2. Koszt budowy grafu

| System | Koszt indeksowania | Kto mierzył | Siła |
|---|---|---|---|
| MS-GraphRAG | ~5 wywołań LLM oraz ~2 800 tokenów wejścia i ~630 wyjścia **na fragment**. Na zbiorze medycznym 17 638 wywołań, w tym 16 354 streszczenia encji i relacji oraz 1 085 raportów społeczności. | [KG²RAG, arXiv 2502.06864](https://arxiv.org/abs/2502.06864); GraphRAG-Bench | [NIEZALEŻNY] |
| MS-GraphRAG | ~40k tokenów na dokument (~0,10 USD na dokument z gpt-4o); dla 100k dokumentów ~10 000 USD | [RAGU, arXiv 2607.11683](https://arxiv.org/abs/2607.11683) | szacunek rzędu wielkości [NIEPEŁNY] |
| LightRAG | 1 wywołanie oraz ~1 270 tokenów wejścia i ~380 wyjścia na fragment; ~8–10k tokenów na dokument | KG²RAG; [LiteSemRAG, 2604.16350](https://arxiv.org/abs/2604.16350) | [NIEZALEŻNY] |
| LightRAG (koszt łączny) | ponad 757 mln tokenów na HotpotQA vs 62 mln dla naiwnego RAG (~12×) | cytowane w wynikach wyszukiwania | [NIEPEŁNY] |
| Graphiti / Zep | Kilka wywołań na epizod: ekstrakcja węzłów, deduplikacja, ekstrakcja krawędzi, **osobne rozstrzygnięcie każdej krawędzi** (liczba rośnie z liczbą faktów). Sama ekstrakcja 0,3–1,5 s; ~50 epizodów na minutę. | [README serwera MCP Graphiti](https://github.com/getzep/graphiti/blob/main/mcp_server/README.md), [issue #1193](https://github.com/getzep/graphiti/issues/1193) | dokumentacja + zgłoszenia użytkowników |
| Zep | ponad 600k tokenów na rozmowę LoCoMo (przy 26k tokenów tekstu, czyli ~23×) | praca Mem0 | [KONKURENT] |
| Mem0 / Mem0g | ~7k / ~14k tokenów na rozmowę (0,27× / 0,54× długości tekstu) | praca Mem0 | [AUTOR] |
| LightMem | 73k–120k tokenów i 65–118 wywołań LLM na próbkę; koszt zwraca się dopiero po ~321 pytaniach | reprodukcja z UQ | [NIEZALEŻNY] |

**Przeliczenie na nasz przypadek (szacunek, nie pomiar):** 55 000 fragmentów × (1–5 wywołań i ~1,6–3,4k tokenów na fragment) daje **~90–190 mln tokenów i 55–275 tys. wywołań** na jednorazowe zbudowanie grafu w stylu LightRAG/GraphRAG. Przy obecnych ~60k tokenów za porcję wyławiania faktów to równowartość **~1 500–3 000 porcji**. Do tego dochodzi koszt każdej aktualizacji: GraphRAG przebudowuje społeczności, a LightRAG i Graphiti aktualizują przyrostowo, ale płacą za każdy epizod.

---

## 3. Wyszukiwanie po polsku: czy `multilingual-e5-small` to rozsądny wybór

### PIRB (41 zadań, polski), NDCG@10

Liczby dla modeli wielojęzycznych pochodzą z tabeli w [Parameter-Efficient Retrievers for Polish (arXiv 2609.12913)](https://arxiv.org/abs/2609.12913), Dadas i in. (OPI PIB, zespół, który zbudował PIRB). Liczby dla modeli mmlw pochodzą z kart modeli na Hugging Face (ci sami autorzy). Rozmiary modeli: karty na Hugging Face.

| Model | Parametry | Wymiar | PIRB NDCG@10 | Uwagi |
|---|---|---|---|---|
| BM25 | — | — | 45,71 | |
| **multilingual-e5-small (nasz)** | ~118M | 384 | **50,65** | [NIEPEŁNY: liczba z wyciągu tabeli] |
| mmlw-retrieval-e5-small | ~118M | 384 | 52,34 | [karta modelu](https://huggingface.co/sdadas/mmlw-retrieval-e5-small); prefiksy query:/passage: |
| multilingual-e5-base | ~278M | 768 | 53,12 | |
| **mmlw-retrieval-roberta-base** | ~124M | 768 | **56,38** | [karta modelu](https://huggingface.co/sdadas/mmlw-retrieval-roberta-base); prefiks „zapytanie: ” |
| bge-m3 | ~568M | 1024 | 55,75 | |
| multilingual-e5-large | ~560M | 1024 | 57,29 | |
| mmlw-retrieval-roberta-large-v2 | ~435M | 1024 | 60,71 | [karta](https://huggingface.co/sdadas/mmlw-retrieval-roberta-large-v2) |
| PolDense (17M–1B) | 17M–1B | | do 64,11 (1B) | nowe, wrzesień 2026, „front Pareto dla każdego rozmiaru” [AUTOR] |

### PL-MTEB (średnia z zadań wyszukiwania): [Poświata i in., arXiv 2405.10138](https://arxiv.org/abs/2405.10138)
multilingual-e5-small **42,43** · e5-base 44,01 · e5-large 48,98 · mmlw-e5-small 42,83 · **mmlw-roberta-base 49,92** · mmlw-e5-large 52,63 · mmlw-roberta-large 52,71.

**Siła dowodu:** PIRB i PL-MTEB zbudował ten sam ośrodek, który wydał modele mmlw i PolDense, więc dla mmlw to [AUTOR]. Dla e5 i bge-m3 to pomiar niezależny od ich autorów. Zbiory to głównie QA, Wikipedia, prawo i medycyna. **Nie ma polskiego benchmarku na rozmowach z czatu ani na słownictwie e-commerce**, więc przełożenie na nasze archiwum jest przybliżone.

**Wniosek:** e5-small jest najsłabszym sensownym modelem na liście (+5 pkt nad BM25). **mmlw-retrieval-roberta-base przy praktycznie tym samym rozmiarze (~124M) daje +5,7 NDCG@10 na PIRB i +7,5 na PL-MTEB.** To najtańsza realna poprawa na CPU. Koszt: wektory 768 zamiast 384 (2× więcej miejsca: 55k × 768 × 4 B ≈ 170 MB we float32) i jednorazowe przeliczenie 55k fragmentów. Model jest polskojęzyczny, więc może gorzej radzić sobie z fragmentami po angielsku i niemiecku (kod, tytuły z eBay DE). Tam przewagę mogą mieć modele wielojęzyczne; trzeba to sprawdzić na własnych danych.
Skala efektu z niezależnych prac o pamięci: sama zamiana embeddingu dawała +6,2 pp trafności odpowiedzi (MemDelta), a zamiana retrievera do +17 pp (reprodukcja LightMem).

### Lokalny re-ranking po polsku (PIRB, kategoria Rerankers, NDCG@10)
[polish-reranker-base-ranknet](https://huggingface.co/sdadas/polish-reranker-base-ranknet) 60,32 (~124M) · polish-reranker-large-ranknet 62,65 · [polish-reranker-bge-v2](https://huggingface.co/sdadas/polish-reranker-bge-v2) 64,21 (568M) · [polish-reranker-roberta-v3](https://huggingface.co/sdadas/polish-reranker-roberta-v3) do 66,21 (435M, kontekst 8k, w części zadań bije Qwen3-Reranker-8B) [AUTOR]. Reranker nałożony na 20–50 najlepszych kandydatów podnosi wynik o kilka do kilkunastu punktów ponad sam retriever (retriever ~50–58, po rerankingu ~60–66). Na CPU model ~124M przy 20–50 parach to rząd setek milisekund do kilku sekund. **U nas tego nie mierzono.**

---

## 4. Pamięć „na żądanie” vs „zawsze w kontekście”

| Praca | Kto / zbiór | Liczby | Siła |
|---|---|---|---|
| [Lost in the Middle (Liu i in., TACL 2024)](https://arxiv.org/abs/2307.03172) | Stanford/Berkeley; QA na wielu dokumentach, 10/20/30 dokumentów | GPT-3.5-Turbo, 20 dokumentów: odpowiedź w 1. dokumencie ~75,8%, w środku **53,8%, czyli gorzej niż bez żadnych dokumentów (56,1%)**. Krzywa w kształcie U u wszystkich testowanych modeli. | [NIEZALEŻNY], ale na starszych modelach |
| [NoLiMa (Adobe, ICML 2025)](https://arxiv.org/abs/2502.05167) | 13 modeli z kontekstem ≥128k; szukana informacja bez dosłownego pokrycia słów z pytaniem | Przy **32k tokenów 11 z 13 modeli spada poniżej 50% wyniku bazowego**. GPT-4o: 99,3% → 69,7% (32k) → 56% (128k). „Efektywna długość” (co najmniej 85% wyniku bazowego) często **≤2k tokenów**; GPT-4.1 ~16k. | [NIEZALEŻNY] |
| [Context Rot (Chroma, lipiec 2025)](https://www.trychroma.com/research/context-rot) | 18 modeli (GPT-4.1, Claude 4, Gemini 2.5, Qwen3) | Jakość spada **przy każdym wydłużeniu kontekstu**, nie tylko blisko limitu. Spada szybciej, gdy szukana treść mało przypomina pytanie i gdy w kontekście są „rozpraszacze” na ten sam temat. | Raport firmy od baz wektorowych (interes w RAG); kod do powtórzenia jest jawny |
| [LongMemEval (Wu i in., ICLR 2025)](https://arxiv.org/abs/2410.10813) | 500 pytań, historia ~115k tokenów | Długi kontekst: spadek o 30–60% względem wyroczni. GPT-4o z pełnym kontekstem ~60–64%, a 87–92%, gdy dostaje tylko właściwe sesje. | [NIEZALEŻNY] wobec modeli |
| ConvoMem | patrz 1a | Pełny kontekst wygrywa do ~30 rozmów, jest akceptowalny do ~150 | [NIEZALEŻNY wobec Mem0] |

**Wniosek dla stałego kontekstu:** jakość zaczyna spadać już przy kilku tysiącach tokenów, gdy model musi skojarzyć treść bez dosłownego pokrycia słów (NoLiMa: efektywna długość ≤2k u wielu modeli, ~16k u lepszych). Najbardziej szkodzą **rozpraszacze na ten sam temat** (Chroma), a to dokładnie to, co daje plik faktów pełen podobnych wpisów o zapachach i SKU. To uzasadnia twardy sufit warstwy stałej (~8k znaków ≈ 2–3k tokenów) i przenoszenie reszty do wyszukiwania na żądanie. Nie znalazłem pomiaru dokładnie dla „pliku faktów doklejanego do system promptu”.

---

## 5. Nowe techniki 2025–2026

| Technika | Wynik | Siła |
|---|---|---|
| **Lepszy ranking zamiast struktury**: [SmartSearch (arXiv 2603.15599)](https://arxiv.org/abs/2603.15599) | Bez LLM przy zapisie: dopasowanie podciągów ważone encjami (NER) plus fuzja rankingów CrossEncoder i ColBERT, **na CPU ~650 ms**. LoCoMo 93,5%, LongMemEval-S 88,4%, 8,5× mniej tokenów niż pełny kontekst. Kluczowe: **recall 98,6%, ale bez dobrego rankingu tylko 22,5% dowodów przeżywa przycięcie do budżetu tokenów**. Wąskim gardłem jest ranking. | [AUTOR] |
| **Klucze indeksu rozszerzone o wyciągnięte fakty i zapytanie świadome czasu**: LongMemEval | Fakty doklejone do klucza indeksu: +4% recall@k i +5% trafności. Rozszerzenie zapytania o czas: +7–11% recall na pytaniach czasowych. Najlepiej działa podział na pojedyncze tury (nie całe sesje). | [AUTOR benchmarku], niezależny wobec metod |
| **Pamięć hierarchiczna / drzewo czasowe**: [TiMem (ACL Findings 2026)](https://arxiv.org/abs/2601.02845) | LongMemEval-S 76,88% (gpt-4o-mini) przy ~1,3k tokenów na zapytanie; w tej samej pracy Mem0 64,96%, MemOS 68,68%. Ablacja: płaskie przeszukanie wszystkich 5 poziomów daje 55,4%, więc **hierarchia pomaga tylko w parze z hierarchicznym wyszukiwaniem**. | [AUTOR] |
| **Streszczenia i kompresja (LightMem, ICLR 2026)** | Autorzy: +2–7,7 pp nad A-Mem. Reprodukcja: przewaga tylko przy bardzo ciasnym budżecie (+5,5 pp przy ~330 tokenach); przy ~935 tokenach już −0,9 pp. Metoda gubi informację (wyrocznia 77,7 vs 89,0). | [AUTOR] vs [NIEZALEŻNY]; pomiar niezależny obala ogólną przewagę |
| **Izolacja tur i przycinanie pod zapytanie**: [Back to Basics (arXiv 2604.11628)](https://arxiv.org/abs/2604.11628) | Tylko wyszukiwanie i generacja, bez grafu i streszczeń. Autorzy deklarują przewagę nad metodami hierarchicznymi. | [AUTOR] [NIEPEŁNY: abstrakt bez liczb] |
| **Lokalny re-ranking po polsku** | patrz sekcja 3: polish-reranker-* 60–66 NDCG@10 vs retrievery 50–58 | [AUTOR modeli] |
| Hybryda BM25 + wektory (RRF) | Reprodukcja LightMem: fuzja BM25 z wyszukiwaniem wektorowym nie daje stałej korzyści na LongMemEval (po angielsku). Przy polskiej odmianie wyrazów BM25 bez lematyzacji jest słabszy (PIRB: 45,7). | [NIEZALEŻNY], ale po angielsku |

---

## Wnioski dla naszego przypadku (jedna osoba, ~55k fragmentów, polski, lokalnie, ograniczony budżet)

1. **Graf się teraz nie opłaci.** Budowa to ~90–190 mln tokenów (szacunek z kosztów na fragment w LightRAG/GraphRAG), czyli 1 500–3 000 naszych porcji. Niezależne pomiary (MemDelta, reprodukcja LightMem, GraphRAG-Bench na faktach) pokazują, że dobrze ustawiony RAG przy pytaniach o fakty dorównuje systemom z LLM-ową strukturą albo je bije. Graf wygrywa tylko przy pytaniach „co się zmieniło w czasie” i wieloskokowych, i to głównie w pomiarach autorów.
2. **Najtańsza dźwignia to embedding.** mmlw-retrieval-roberta-base (~124M, CPU) daje +5,7 na PIRB i +7,5 na PL-MTEB nad e5-small. W pracach o pamięci sama zamiana embeddingu dawała +6 do +17 pp trafności.
3. **Druga dźwignia to lokalny reranker na 20–50 najlepszych wynikach** (polish-reranker-base-ranknet ~124M albo roberta-v3 435M). SmartSearch: wąskim gardłem jest ranking, nie recall.
4. **Tanie zamienniki „grafu czasowego”:** data w kluczu indeksu plus rozszerzenie zapytania o czas (+7–11% recall na pytaniach czasowych, LongMemEval) oraz fakty doklejone do kluczy indeksu (+4% recall).
5. **Stały kontekst trzymać mały.** NoLiMa i Chroma: jakość spada już od kilku tysięcy tokenów, najbardziej przez podobne tematycznie wpisy.
6. **Czego nie sprawdzono:** żadna z liczb nie pochodzi z polskich rozmów z czatu. Przed zmianą modelu warto zrobić własny test na ~50–100 pytaniach z Lore (recall@10: e5-small vs mmlw vs mmlw z rerankerem).
