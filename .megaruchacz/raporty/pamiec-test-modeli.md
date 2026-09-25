# Lore: czy wymienić model wektorowy — pomiar na rozmowach użytkownika

Pomiar z 2026-09-24, na kopii prawdziwej bazy (`~/.claude/lore.db`, 55 954 fragmenty, 778 plików
rozmów, 2026-05-18 → 2026-09-24). Nic nie zostało zapisane do prawdziwej bazy ani do `~/.claude`;
żaden model językowy nie był wołany. Kod i zbiór testowy: `lore/bench/`.

## Werdykt

**Wymienić e5-small na `sdadas/mmlw-retrieval-roberta-base` (hybryda bez zmian). Rerankera na razie
nie dokładać.** mmlw poprawia trafność i dla pytań polskich, i — wbrew obawie — dla niepolskich;
koszt to jednorazowe ~2 h przeliczenia archiwum na CPU, ~3× wolniejsze bieżące indeksowanie,
+86 MB wektorów i +15 ms na zapytanie. Reranker kosztuje ~8 s na zapytanie na tym CPU, polski
nie daje zysku netto, a wielojęzyczny (najlepszy wynik) ma licencję niekomercyjną.

## Wyniki (60 pytań; ranking na próbce 16 000 fragmentów — patrz niżej)

| wariant | grupa | top1 | top5 | top10 | MRR@10 |
|---|---|---:|---:|---:|---:|
| **a** e5-small hybryda (dziś) | wszystkie (n=60) | 43,3% | 71,7% | 80,0% | 0,538 |
| | PL (n=37) | 43,2% | 70,3% | 78,4% | 0,526 |
| | nie-PL (n=23) | 43,5% | 73,9% | 82,6% | 0,558 |
| **b** mmlw-roberta-base hybryda | wszystkie | 50,0% | 81,7% | **90,0%** | **0,637** |
| | PL | 48,6% | 81,1% | 83,8% | 0,618 |
| | nie-PL | 52,2% | 82,6% | 100% | 0,666 |
| **c** b + polish-reranker-base (top 30) | wszystkie | 48,3% | 85,0% | 90,0% | 0,653 |
| | PL | 51,4% | 86,5% | 89,2% | 0,676 |
| | nie-PL | 43,5% | 82,6% | 91,3% | 0,615 |
| c2 b + jina-reranker-v2-multi (top 30) | wszystkie | 58,3% | 93,3% | 95,0% | 0,718 |
| | PL | 59,5% | 89,2% | 91,9% | 0,719 |
| | nie-PL | 56,5% | 100% | 100% | 0,717 |
| a2 a + polish-reranker-base | wszystkie | 46,7% | 78,3% | 83,3% | 0,609 |
| a3 a + jina-reranker-v2-multi | wszystkie | 51,7% | 86,7% | 90,0% | 0,670 |

Koszty (CPU tej maszyny, 16 wątków; czas zapytania = osadzenie pytania + FTS na pełnej bazie +
skan wektorów w rozmiarze pełnego archiwum + reranking):

| wariant | zapytanie, mediana / p90 | przeindeksowanie 55 954 fragm. | model(e) na dysku | wektory w bazie |
|---|---:|---:|---:|---:|
| a | 45 / 67 ms | ~38 min (ekstrapolacja) | 470 MB | 86 MB (384 wym.) |
| b | 60 / 86 ms | **~2 h** (ekstrapolacja) | 496 MB | 172 MB (768 wym.) |
| c | 8,4 / 9,0 s | ~2 h | 496 + 498 MB | 172 MB |
| c2 | 8,4 / 8,9 s | ~2 h | 496 + 1 114 MB | 172 MB |
| a2 / a3 | 7,8 / 8,0 s | ~38 min | 470 + 498 / 1 114 MB | 86 MB |

Tempo osadzania zmierzone na tych samych 2 000 losowych fragmentach: e5 24,3 fragm./s, mmlw
7,8 fragm./s (3,1× wolniej); drugi pomiar mmlw na 16 000 fragmentach: 7,4 fragm./s. Składowe
zapytania: FTS 35 ms, osadzenie pytania e5 6 ms / mmlw 19 ms, skan wektorów 3 / 5 ms.

**Czy różnice są realne, czy to szum (60 pytań):** test znaków na parach pytań.
- b vs a: lepiej w 20 pytaniach, gorzej w 8 (p = 0,04). Osobno PL 12:5, nie-PL 8:3 — kierunek ten sam,
  ale każda grupa osobno jest za mała na pewność.
- c vs b (polski reranker): 16 lepiej, 16 gorzej — **zero zysku netto**; pomaga pytaniom polskim
  (MRR 0,618 → 0,676), szkodzi niepolskim (0,666 → 0,615).
- c2 vs b (jina): 18:10 (p = 0,19) — najlepszy wynik, ale jeszcze nie rozstrzygnięty statystycznie.

**Obawa „polski model przegra na niemieckim/angielskim” się nie potwierdziła:** same wektory
(bez BM25) — e5 top10 65% / MRR 0,35, mmlw 92% / 0,64; dla nie-PL e5 65% / 0,30, mmlw 96% / 0,53.
W hybrydzie: po niemiecku mmlw 8/8 w top10 (e5 7/8), po angielsku 11/11 (e5 8/11), kod 4/4 obie.

**Obserwacja uboczna:** sam BM25 (top10 83%, MRR 0,528) jest tu praktycznie tak dobry jak dzisiejsza
hybryda z e5 (80%, 0,538) — kanał wektorowy e5 prawie nic nie dokłada. Z mmlw dokłada wyraźnie.

**Skala zawyżenia przez próbkę:** dzisiejszy wariant (a) policzony na **pełnym** archiwum daje
top10 60,0% i MRR 0,352 (na próbce 80,0% / 0,538). Dla mmlw pełnego pomiaru nie ma — wymagałby
2 h przeliczenia. Kierunek różnicy powinien się utrzymać, jej wielkość — niekoniecznie.

## Jak zbudowano zbiór testowy (60 pytań) — od tego zależy wiarygodność

**Pytania nie są wymyślone.** Każde to dosłowny wycinek z archiwum, wybrany ręcznie spośród
kandydatów wyłowionych automatycznie:

| rodzaj | ile | skąd |
|---|---|---|
| „powrót do tematu” | 20 | wiadomości użytkownika z odwołaniem do wcześniejszych ustaleń („pamiętasz…”, „przypomnij…”, „znowu…”, „mówiłem…”, „jak ostatnio”) |
| pytanie o fakt ustalony wcześniej | 10 | pytania użytkownika („gdzie jest…”, „z którego klucza…”), na które odpowiedź leży w starszej rozmowie |
| prawdziwe zapytania do Lore | 8 | wywołania `szukaj_historii` zapisane w archiwum — tak naprawdę pytali agenci (z 11 odrzucone 3: dwa pytania o samo narzędzie, jedno bez jednoznacznej odpowiedzi); jedno z nich jest po niemiecku |
| niemieckie tytuły / frazy SEO | 7 | tytuły i listy fraz po niemiecku z poleceń dla workerów i z wklejek Amazona |
| angielskie pytania do dostawców | 11 | angielskie pytania do dostawców maszyn, wysłane ponownie 3 dni po pierwszej analizie |
| kod / komunikaty błędów | 4 | błędy wklejone przez użytkownika (TypeScript, Postgres), nazwa funkcji |

Języki: **37 polskich, 23 niepolskie** (8 DE, 11 EN, 4 kod). Mediana długości pytania 89 znaków.

**Trafienie = fragment, który zawiera odpowiedź.** Dla każdego pytania ręcznie ustalone wyrażenie
regularne opisujące fakt-odpowiedź (np. adres panelu, nazwa parametru Next.js, kwota), sprawdzone
na podglądzie trafień. Mediana: 13 fragmentów-trafień na pytanie (11 wypowiedzi).

**Archiwum „z chwili pytania”** — wspólne dla wszystkich wariantów:
- tylko fragmenty starsze niż pytanie;
- bez ostatnich 2 godzin tej samej sesji (to było jeszcze w kontekście rozmowy);
- bez fragmentów zawierających samo pytanie (kopie, podwójnie zaindeksowane transkrypty) —
  znalezienie własnego pytania nie jest trafieniem;
- 29 z 60 pytań ma trafienia w innej sesji niż pytanie, 31 — tylko w tej samej sesji, ale starsze
  niż 2 godziny (część sesji ciągnie się tygodniami).

Odpowiedź musi też być rzadka: wzorzec pasujący do więcej niż 1% archiwum jest odrzucany.
Po ręcznym przeglądzie próbek trafień zawężono 7 wzorców (jeden łapał ponad 1% archiwum, inne
przypadkowe liczby albo inny temat); 1 pytanie odpadło, bo odpowiedź nie istniała przed pytaniem,
1 — bo jego „trafienia” były kopiami samego pytania.

**Prywatność.** Repozytorium jest publiczne, więc do `lore/bench/queries.jsonl` trafiły tylko
wskaźniki (id fragmentu, zakres znaków, SHA-1, id trafień). Treść pytań i wzorców leży w
`%TEMP%\lorebench\spec.jsonl` — tylko na tej maszynie i tylko w katalogu tymczasowym.

## Warianty i uczciwość porównania

- Wszystkie warianty to wierna kopia `lore/search.py`: BM25 (FTS5) top 30 + wektory top 30, RRF k=60,
  części jednej wypowiedzi liczone raz. Liczy się pierwsza **wypowiedź** zawierająca trafienie.
- **Prefiksy wg kart modeli:** e5 `query: ` / `passage: ` (jak w produkcji); mmlw `zapytanie: ` dla
  pytania i **brak** prefiksu dla fragmentu, pooling CLS, normalizacja. Rerankery dostają surowe
  pytanie i surowy fragment (do 512 tokenów).
- **Silnik jak w produkcji:** ONNX Runtime przez fastembed 0.8.0, CPU. mmlw i polski reranker nie mają
  ONNX na Hugging Face — wyeksportowane lokalnie (optimum), każdy eksport sprawdzony liczbowo
  względem PyTorch (max różnica ~2e-6). Pierwsza, ręczna próba eksportu dawała różnice do 1,9 —
  kontrola to złapała i odrzuciła plik.
- **Wariant (a) = dokładnie to, co dziś działa:** wektory e5 wzięte z kopii bazy produkcyjnej;
  kontrola, że nasz kod liczy e5 identycznie jak produkcja: minimalny cosinus = 1,00000 (64 fragmenty).
- **Reranker (c): `sdadas/polish-reranker-base-ranknet`** — najlżejszy reranker z czołówki PIRB
  (124M parametrów, ta sama rodzina i tokenizer co mmlw, Apache-2.0, CPU), na 30 pierwszych
  kandydatów z fuzji. Ponieważ połowa ryzyka to fragmenty niepolskie, dołożyłem kontrolę **(c2):
  `jinaai/jina-reranker-v2-base-multilingual`** (278M, wielojęzyczny, rozumie kod; **licencja
  CC-BY-NC-4.0 — do użytku w firmie nie nadaje się bez licencji komercyjnej**). Warianty a2/a3
  pokazują, ile daje sam reranker bez zmiany modelu wektorowego.

## Próbka zamiast pełnego archiwum — i co z tego wynika

Pełne przeliczenie 55 954 fragmentów modelem mmlw na tym CPU to ok. 2 godziny, więc ranking
liczony jest na **próbce 16 000 fragmentów**: wszystkie 1 080 fragmentów-trafień + 14 920 losowych.
**Wszystkie warianty (także BM25 i dzisiejsze e5) szukają w tej samej próbce**, więc porównanie
między wariantami jest uczciwe. Bezwzględne procenty są przez to **zawyżone** (mniej
„rozpraszaczy” niż w prawdziwym archiwum) — do porównań, nie do obiecywania.

Czasy przeindeksowania to **ekstrapolacja** z pomiaru na tej samej losowej próbce 2 000 fragmentów
dla obu modeli (i drugi pomiar tempa mmlw na 16 000). Czas zapytania mierzony na pełnym rozmiarze:
FTS na całej kopii bazy, skan wektorów na macierzy 55 954 × wymiar.

## Słabości tego pomiaru (od największej)

1. **Próbka, nie pełne archiwum.** Ranking na 16 000 z 55 954 fragmentów; bezwzględne liczby
   zawyżone (dla e5: 80% → 60% top10 po przejściu na pełne archiwum). Różnica b–a na pełnym
   archiwum niezmierzona.
2. **Etykiety nadał jeden oceniający (worker), wzorcami tekstowymi.** Wzorzec łapie fragmenty
   z konkretnym faktem, ale pomija odpowiedź sformułowaną innymi słowami. Jeśli model wektorowy
   znajdzie taką parafrazę, liczy się to jako pudło — więc przewaga modeli wektorowych jest tu
   raczej zaniżona niż zawyżona. Użytkownik etykiet nie weryfikował.
3. **Mało pytań i mało źródeł.** 60 pytań z 14 sesji; 11 angielskich pochodzi z jednej rozmowy
   (dostawcy maszyn), niemieckie w większości z jednej linii produktów (kadzidełka). Różnice
   w podgrupach poniżej ~15 pkt proc. to szum.
4. **Reranking mierzony na 30 kandydatach po ~500 znaków.** Czas ~8 s/zapytanie da się skrócić
   (mniej kandydatów, krótszy tekst), ale tego nie mierzyłem.

## Co z tym zrobić (propozycja, nic nie wdrożone)

- Wymiana w `lore/lore/db.py`: `EMBED_MODEL`, `EMBED_DIM=768`, prefiks `zapytanie: ` dla pytań,
  brak prefiksu dla fragmentów, pooling CLS, plik ONNX z eksportu (mmlw nie ma ONNX na Hugging
  Face — trzeba go wyeksportować i gdzieś hostować albo eksportować u użytkownika, co wymaga torcha).
- Przeliczenie całej bazy (~2 h CPU) jako jednorazowa migracja; w tym czasie wyszukiwanie może
  działać na samym BM25 (to, jak widać, niewiele gorzej od dzisiejszej hybrydy).
- Reranker: wrócić do tematu, jeśli pojawi się lżejszy wielojęzyczny model z licencją komercyjną
  albo wolno będzie wydać sekundy na zapytanie.

## Poza zakresem, ale do wiadomości

- `lore/pyproject.toml` **nie został ruszony**: dopisanie grupy zależności zmienia `uv.lock`, którego
  nie wolno mi było dotknąć, a instalator robi `uv sync`. Zależności badania są w
  `lore/bench/requirements.txt` do osobnego, jednorazowego venv.
- Przy przeglądaniu archiwum trafiłem na **niezamaskowany token API BaseLinkera** w wiadomości
  użytkownika z 2026-05-21 (fragment #31781 w bazie Lore). Maskowanie go nie złapało (format
  cyfry-myślniki-znaki). Treści tokenu tu nie powtarzam.

## Jak powtórzyć

`lore/bench/README.md`. Wyniki surowe: `%TEMP%\lorebench\results.json` (próbka) i
`results-full-e5.json` (e5 na pełnym archiwum). Kopia bazy, wektory mmlw i modele leżą w
`%TEMP%\lorebench` (3,4 GB) — do skasowania, kiedy nie będą potrzebne (razem z nim zniknie
czytelna wersja pytań `spec.jsonl`; wskaźniki w repo działają dalej na tej bazie).
