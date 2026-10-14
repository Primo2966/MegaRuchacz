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
| `osoby.json` | `osoba -> {token_sha256, admin, uprawnienia: {temat_id: najwyzszy_poziom}, komputer?}` — sam token nigdy nie jest zapisywany; `komputer` = id komputera z JFTools (tylko w trybie JFTools) |
| `serwer-zyje.json` | znacznik „byłem tu” serwera, odświeżany co 60 s (czas, pid, stan modelu, liczby wpisów, problem z plikiem osób, próg trafności, a w trybie JFTools: adres i ostatni błąd JFTools) |
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
- Źródło uprawnień to protokół `uprawnienia.ZrodloUprawnien`: `ZrodloPlikowe` (`osoby.json`, domyślnie)
  albo `jftools.ZrodloJFTools` (panel JFTools, niżej).

## Uprawnienia z JFTools (od 0.2.0)

Domyślnie **wyłączone**: bez zmiennej `WIEDZA_FIRMY_UPRAWNIENIA` (albo z wartością `plik`) serwer działa jak
w 0.1.0, z `osoby.json` i `tematy.json`, i nie wysyła żadnych zapytań do JFTools.

Po włączeniu:

- token → osoba nadal z `osoby.json` (tokeny nie wychodzą z serwera); osoba → komputer z pola `komputer`;
  komputer → tematy i poziomy z `GET <baza>/knowledge-permissions?computer=<id>` (nagłówek `x-webhook-secret`);
- flaga `admin` zostaje w `osoby.json`; pole `admin` z odpowiedzi JFTools jest pomijane, a pole `uprawnienia`
  z `osoby.json` nie daje wtedy nic;
- komputer `pending`/`blocked`, nieznany (404) albo z błędnym id (400) = zero uprawnień i komunikat, dlaczego;
- tematy (nazwy, opisy) z `GET <baza>/knowledge-topics`; gdy JFTools nie odpowiada, serwer bierze ostatnią
  znaną listę, a gdy jej nie ma, `tematy.json`; odpowiedź mówi to w `uwagi`;
- pamięć tak jak w ecommerce-helper: odpowiedź ważna 10 min (komputer bez dostępu 1 min), limit zapytania 3 s,
  po błędzie 30 s bez ponawiania;
- gdy JFTools nie odpowiada (sieć, limit czasu, zły sekret, zła odpowiedź), obowiązują ostatnio znane uprawnienia,
  najwyżej sprzed godziny, a potem zero. Każda awaria trafia do dziennika serwera i do `serwer-zyje.json`.
  `moje_uprawnienia` pokazuje w polu `zrodlo_uprawnien` „uprawnienia z pamięci z <czas> — JFTools nie odpowiada (…)”,
  a pozostałe narzędzia podają to samo w `uwagi`.

Zmienne:

| zmienna | wartość |
|---|---|
| `WIEDZA_FIRMY_UPRAWNIENIA` | `jftools` włącza; puste albo `plik` = osoby.json; inna wartość = serwer nie startuje |
| `WIEDZA_FIRMY_JFTOOLS_SEKRET` | sekret tras publicznych wtyczki (ten sam co `ECOMMERCE_HELPER_UPRAWNIENIA_SEKRET`); brak przy `jftools` = serwer nie startuje |
| `WIEDZA_FIRMY_JFTOOLS_URL` | opcjonalnie, baza tras wtyczki; domyślnie `https://tools.jfinvesting.pl/api/public/mcp-ecommerce-sterowanie` (adres z końcówką `/permissions` też działa) |

Włączenie na Pakowanie2:

1. W JFTools → Wiedza firmy: tematy i uprawnienia komputerów nadane.
2. Każdej osobie, która nie jest adminem: `python -m wiedza_firmy.osoby ustaw-komputer <osoba> <id komputera z JFTools>`
   (`-` zdejmuje; `lista` pokazuje przypisania).
3. W środowisku procesu serwera ustawić `WIEDZA_FIRMY_UPRAWNIENIA=jftools` i `WIEDZA_FIRMY_JFTOOLS_SEKRET=<sekret>`,
   potem restart serwera. W dzienniku startu: `uprawnienia: JFTools https://…/knowledge-permissions`.
4. Sprawdzenie: `moje_uprawnienia` z tokenu osoby pokazuje `zrodlo_uprawnien` z nazwą komputera.

Wyłączenie: usunąć `WIEDZA_FIRMY_UPRAWNIENIA` i zrestartować — serwer wraca do `osoby.json`.

## Próg trafności (od 0.2.0)

`szukaj_wiedzy` zwraca tylko wpisy, których podobieństwo do pytania (wektory mmlw) przekracza próg modelu
(`wektory.PROGI_TRAFNOSCI`, dla mmlw 0,735; jak go dobrano — komentarz przy stałej i
`tests/test_model_prawdziwy.py`). Próg działa też na wpisy znalezione słowami, bo zapytanie pełnotekstowe to
„słowo1 OR słowo2…”. Gdy nic go nie przekracza: `wyniki: []` i `komunikat: "Brak ustaleń na ten temat."`.
Bez modelu (sam pełny tekst) progu nie ma, a odpowiedź mówi to w `uwagi`. Słaba strona: pytanie po niemiecku
do polskiego wpisu wypada poniżej progu.

## Polecenia

Uruchamiane z katalogu `wiedza_firmy\` (tu leży `pyproject.toml`), np. `uv run python -m ...`
albo pythonem z venv serwera:

```
python -m wiedza_firmy.tematy wczytaj <plik.json>      # przykład: przyklady/tematy.przyklad.json
python -m wiedza_firmy.osoby nowa <osoba> [--admin]     # wypisuje token RAZ
python -m wiedza_firmy.osoby nadaj <osoba> <temat> <jawne|wewnetrzne|wrazliwe>
python -m wiedza_firmy.osoby odbierz|token|usun <osoba> ... ; python -m wiedza_firmy.osoby lista
python -m wiedza_firmy.osoby ustaw-komputer <osoba> <id|->   # tryb JFTools: komputer osoby
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

Testy niczego nie pobierają: wektory liczy atrapa, a JFTools udaje lokalny serwer HTTP na 127.0.0.1
(`tests/test_jftools.py`). Test prawdziwego modelu rusza tylko wtedy, gdy model
już leży na komputerze (`~/.claude/lore_models`, `~/.lore/lore_models` albo `WIEDZA_FIRMY_TEST_MODELE`).
W innym wypadku zostaje pominięty z podanym powodem.
