# Pomiar: czy wymienić model wektorowy Lore

Badanie, nie część produkcji. Nic stąd nie jest importowane przez `lore/lore/*`, nic nie pisze
do prawdziwej bazy ani do `~/.claude` / `~/.lore` (skrypty odmawiają startu, gdy katalog roboczy
leży w środku któregoś z nich). Wynik ostatniego przebiegu: `.claude/raporty/pamiec-test-modeli.md`.

## Co jest porównywane

| wariant | model wektorowy | reranker |
|---|---|---|
| a | `intfloat/multilingual-e5-small` (dziś w Lore) | — |
| b | `sdadas/mmlw-retrieval-roberta-base` | — |
| c | jak b | `sdadas/polish-reranker-base-ranknet` na 30 pierwszych |
| c2 | jak b | `jinaai/jina-reranker-v2-base-multilingual` na 30 pierwszych (kontrola wielojęzyczna) |
| a2, a3 | jak a | te same rerankery — czy sam reranker nie wystarczy |

Wszędzie hybryda jak w `lore/search.py`: BM25 top 30 + wektory top 30, RRF k=60. Prefiksy zgodnie
z kartami modeli: e5 `query: ` / `passage: `, mmlw `zapytanie: ` / brak, pooling CLS.

## Uruchomienie

```powershell
$env:LORE_BENCH_DIR = "$env:TEMP\lorebench"      # kopia bazy, wektory, modele - poza repo
# osobny venv, patrz requirements.txt
python prepare.py                                # kopia bazy (tylko odczyt oryginału) + modele
python build_set.py                              # spec.jsonl (prywatny) -> queries.jsonl
python embed_corpus.py mmlw-roberta-base         # pełne przeliczenie archiwum, z pomiarem czasu
python embed_corpus.py e5-small --sample 2000    # tempo e5 (wektory e5 bierzemy z bazy produkcyjnej)
python evaluate.py                               # -> $LORE_BENCH_DIR\results.json
```

## Zbiór testowy

`queries.jsonl` to same wskaźniki: id fragmentu, z którego wycięto pytanie, zakres znaków, skrót
SHA-1, oraz id fragmentów uznanych za trafienie. **Treść pytań nie trafia do repozytorium**
(repo jest publiczne, a pytania to dosłowne wiadomości z rozmów użytkownika). Czytelna wersja
z etykietami leży w `$LORE_BENCH_DIR\spec.jsonl` na maszynie, na której jest archiwum.
Metoda budowy — w raporcie.
