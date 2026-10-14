# wiedza_firmy — serwer MCP „Wiedza firmy”

Wspólna baza krótkich ustaleń pracowników firmy. Jeden proces na serwerze, wszyscy łączą się
przez HTTP. Wyszukiwanie hybrydowe (pełnotekstowe FTS5 + wektory modelu
`sdadas/mmlw-retrieval-roberta-base` z Lore), uprawnienia: **temat × poziom poufności**.

Repo jest publiczne: w repo jest tylko kod i przykłady z wymyślonymi danymi. Tematy firmy,
wpisy, osoby i tokeny żyją wyłącznie w katalogu danych serwera.

## Dane serwera

`WIEDZA_FIRMY_HOME` (domyślnie `%APPDATA%\wiedza-firmy`):

| plik | co |
|---|---|
| `wiedza.db` | SQLite: `wpisy` (miękkie usuwanie: `usuniety`, `usunal`, `powod_usuniecia`), `wpisy_fts`, `wektory` (float32), `meta` |
| `tematy.json` | lista tematów: `id`, `nazwa`, `opis`, `przyklady[]`, `osobne_uprawnienie` |
| `osoby.json` | `osoba -> {token_sha256, admin, uprawnienia: {temat_id: najwyzszy_poziom}}` — sam token nigdy nie jest zapisywany |
| `serwer-zyje.json` | znacznik „byłem tu” serwera, odświeżany co 60 s (czas, pid, stan modelu, liczby wpisów, problem z plikiem osób) |
| `modele\` | model wektorów (`WIEDZA_FIRMY_MODELE` zmienia miejsce) |

Kod Lore: katalog `lore` obok `wiedza_firmy` albo `WIEDZA_FIRMY_LORE`. Potrzebne pliki:
`lore/lore/__init__.py`, `db.py`, `search.py`, `masking.py`.

## Uprawnienia

- Poziomy: `jawne < wewnetrzne < wrazliwe`. „temat: wewnetrzne” daje jawne i wewnętrzne w tym temacie.
  `tajne` nie trafia do bazy wcale.
- Brak tokenu albo nieznany token: **401**, nic się nie wykonuje.
- Znany token bez uprawnień: narzędzia działają, ale nic nie zwracają („Nie masz jeszcze uprawnień — poproś admina.”).
- Admin widzi wszystko i jako jedyny może dodawać i usuwać wpisy.
- Filtr uprawnień jest warunkiem SQL w obu kanałach wyszukiwania. Wpisy spoza uprawnień nie dostają się
  do rankingu. Podpowiedź „są wpisy w temacie X — poproś admina” podaje tylko nazwę tematu, bez treści,
  i to tylko wtedy, gdy ukryty wpis pasuje do pytania słowami i trafiłby do pierwszych wyników.
- Źródło uprawnień to protokół `uprawnienia.ZrodloUprawnien`. Krok 1 korzysta z `ZrodloPlikowe` (`osoby.json`).

## Polecenia

Uruchamiane z katalogu `wiedza_firmy\` (tu leży `pyproject.toml`), np. `uv run python -m ...`
albo pythonem z venv serwera:

```
python -m wiedza_firmy.tematy wczytaj <plik.json>      # przykład: przyklady/tematy.przyklad.json
python -m wiedza_firmy.osoby nowa <osoba> [--admin]     # wypisuje token RAZ
python -m wiedza_firmy.osoby nadaj <osoba> <temat> <jawne|wewnetrzne|wrazliwe>
python -m wiedza_firmy.osoby odbierz|token|usun <osoba> ... ; python -m wiedza_firmy.osoby lista
python -m wiedza_firmy.importuj <plik.md> [--na-sucho] [--bez-modelu]   # format: przyklady/wsad.przyklad.md
python -m wiedza_firmy.model                            # pobiera brakujące pliki modelu, sprawdza sumy, ładuje
python -m wiedza_firmy.serwer [--host 0.0.0.0] [--port 8766]
```

Serwer: streamable HTTP pod `/mcp` w trybie bezstanowym (każde żądanie niesie swój token).
`WIEDZA_FIRMY_HOSTY` (opcjonalnie, nazwy i adresy rozdzielone przecinkami) włącza sprawdzanie nagłówka
Host także przy `0.0.0.0`.

Narzędzia MCP: `szukaj_wiedzy(pytanie, temat?, limit=8)`, `tematy()`, `moje_uprawnienia()`, a tylko
dla admina: `dodaj_wpis(...)` i `usun_wpis(id, powod)`.

## Testy

```
uv --directory wiedza_firmy run pytest
```

Testy niczego nie pobierają: wektory liczy atrapa. Test prawdziwego modelu rusza tylko wtedy, gdy model
już leży na komputerze (`~/.claude/lore_models`, `~/.lore/lore_models` albo `WIEDZA_FIRMY_TEST_MODELE`).
W innym wypadku zostaje pominięty z podanym powodem.
