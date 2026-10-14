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
| `wiedza.db` | SQLite: `wpisy` (miękkie usuwanie: `usuniety`, `usunal`, `powod_usuniecia`), `wpisy_tematy` (od 0.3.0: `wpis_id`, `temat_id`, `glowny`), `wpisy_fts`, `wektory` (float32), `meta` (m.in. `wersja_schematu`) |
| `wiedza.db.kopia-*` | kopie bazy: przed migracją schematu (`kopia-przed-schematem-2-…`) i przed `ustaw_tematy` (`kopia-przed-ustaw-tematy-…`) |
| `tematy.json` | lista tematów: `id`, `nazwa`, `opis`, `przyklady[]`, `osobne_uprawnienie` |
| `osoby.json` | `osoba -> {token_sha256, admin, uprawnienia: {temat_id: najwyzszy_poziom}, komputer?}` — sam token nigdy nie jest zapisywany; `komputer` = id komputera z JFTools (tylko w trybie JFTools). Od 0.4.0 wpisy `komputer-<id>` zakłada sam serwer (`wystawil: "auto"`, `wystawiony`, `wymieniony?`, `wygasl?`) |
| `serwer-zyje.json` | znacznik „byłem tu” serwera, odświeżany co 60 s (czas, pid, stan modelu, liczby wpisów, problem z plikiem osób, próg trafności, a w trybie JFTools: adres, ostatni błąd JFTools i ostatni błąd `keys`; od 0.4.0 `klienci.liczniki_od_startu`: próby tokenu wg wyniku, odmowy tras klienta, wpisy z paczek, ostatnia próba tokenu, stan pliku zasad) |
| `zgloszenia-klientow.log` | od 0.4.0: każda próba wydania tokenu komputerowi, linia `czas \| komputer <id> \| wynik \| adres \| opis` (bez podpisu, nonce i tokenu) |
| `zasady-klienta.md` | od 0.4.0, opcjonalnie: zasady przeglądu dla klientów (`GET /klient/tematy` → `zasady`); brak = pusty tekst i wpis w dzienniku serwera |
| `modele\` | model wektorów (`WIEDZA_FIRMY_MODELE` zmienia miejsce) |

Kod Lore: katalog `lore` obok `wiedza_firmy` albo `WIEDZA_FIRMY_LORE`. Potrzebne pliki:
`lore/lore/__init__.py`, `db.py`, `search.py`, `masking.py`.

## Uprawnienia

- Poziomy: `jawne < wewnetrzne < wrazliwe`. „temat: wewnetrzne” daje jawne i wewnętrzne w tym temacie.
  `tajne` nie trafia do bazy wcale.
- Brak tokenu albo nieznany token: **401**, nic się nie wykonuje.
- Znany token bez uprawnień: narzędzia działają, ale nic nie zwracają („Nie masz jeszcze uprawnień — poproś admina.”).
- Admin widzi wszystko i jako jedyny może usuwać wpisy. Dodawać może każdy ze znanym tokenem (od 0.3.1), do
  dowolnego tematu, także niewidocznego dla siebie; autorem jest wtedy zawsze on sam (parametr `autor` działa
  tylko u admina). Wyjątek (od 0.4.0): w trybie JFTools osoba, której komputer nie jest active (pending, blocked,
  usunięty), nie dodaje nic.
- Narzędzia tylko dla admina (`serwer.NARZEDZIA_ADMINA`, dziś `usun_wpis`) są niewidoczne na liście narzędzi
  (`tools/list`) dla innych — filtruje je middleware SDK `FiltrNarzedziAdmina` przy każdym żądaniu, a wynik ma
  `cacheScope: private`. Gdy źródło uprawnień nie odpowiada, lista jest ukrywana (z wpisem w logu). Odmowa przy
  wywołaniu wprost zostaje jako druga linia obrony.
- Wpis może mieć kilka tematów (od 0.3.0, niżej). Filtr uprawnień jest warunkiem SQL w obu kanałach wyszukiwania. Wpisy spoza uprawnień nie dostają się
  do rankingu. Podpowiedź „są wpisy w temacie X — poproś admina” podaje tylko nazwę tematu, bez treści,
  i to tylko wtedy, gdy ukryty wpis pasuje do pytania słowami i trafiłby do pierwszych wyników.
- Źródło uprawnień to protokół `uprawnienia.ZrodloUprawnien`: `ZrodloPlikowe` (`osoby.json`, domyślnie)
  albo `jftools.ZrodloJFTools` (panel JFTools, niżej).

## Wiele tematów na wpis (od 0.3.0)

Wpis ma jeden temat **główny** (`wpisy.temat`, sekcja `## temat:` w imporcie) i dowolnie wiele **dodatkowych**
(np. „grafika PT02 porównuje nas z konkurencją” = Grafiki + Oferty). Kto widzi wpis:

- **tematy zwykłe — LUB**: wystarczy dostęp do któregokolwiek zwykłego tematu wpisu;
- **tematy z `osobne_uprawnienie: true` (np. SEO, Dostawcy, IT) — I**: gdy wpis ma temat specjalny, trzeba mieć
  KAŻDY jego temat specjalny;
- **poziom poufności**: pytający musi mieć poziom ≥ poufności wpisu w temacie, przez który go widzi, a przy tematach
  specjalnych w każdym z nich;
- wpis bez żadnego zwykłego tematu, tylko ze specjalnymi, widzi tylko ten, kto ma wszystkie jego specjalne;
- temat spoza listy tematów (usunięty z `tematy.json`/JFTools) liczy się jak specjalny, a gdy listy nie da się
  odczytać, każdy temat liczy się jak specjalny — awaria listy zawęża widoczność, nigdy jej nie poszerza;
- admin widzi wszystko.

Wszystko to jest jednym warunkiem SQL (`baza.warunek_uprawnien`) w obu kanałach, przed rankingiem.
`szukaj_wiedzy` pokazuje w polu `tematy` (`id`, `nazwa`, `glowny`) tylko tematy, przez które pytający widzi wpis;
`temat`/`temat_nazwa` to pierwszy z nich (główny, jeśli go widzi). Podpowiedź „poproś admina” nie podaje nazwy tematu
specjalnego, do którego pytający nie ma dostępu wcale („są wpisy objęte osobnym uprawnieniem…”). `tematy()` bez zmian.
`dodaj_wpis` (MCP) przyjmuje temat główny i opcjonalnie `tematy_dodatkowe` (od 0.3.1); hurtem tematy nadaje import
albo `ustaw_tematy`.

**Migracja** starej bazy idzie sama przy pierwszym otwarciu przez 0.3.0 (serwer, import, CLI): najpierw kopia
`wiedza.db.kopia-przed-schematem-2-<czas>`, potem w jednej transakcji każdy wpis dostaje swój dotychczasowy temat jako
główny, z kontrolą na końcu (błąd = wycofanie). Wersja schematu stoi w `meta`, więc drugi start nic nie robi
i nie robi kopii. Wpis bez tematu głównego (baza niespójna) widzi tylko admin, a serwer melduje to przy starcie.

**Format importu** — znacznik tematów dodatkowych po poziomie (albo po dacie, gdy poziomu nie ma):

```
## temat: grafiki
- [2026-10-01] [wewnetrzne] [+oferty] Grafika PT02 porównuje nas z konkurencją.
- [2026-10-02] [jawne] Wpis tylko w temacie głównym, jak dotąd.
```

Bez znacznika wpis ma tylko temat główny. Temat spoza listy serwera (główny albo dodatkowy), powtórzony albo równy
głównemu = odmowa całego pliku z numerem linii. `[#id]` przed datą to id wpisu z eksportu — import go pomija i mówi o tym.

**Przeklasyfikowanie** (np. po dodaniu nowej kategorii), tylko lokalnie na serwerze:

1. `python -m wiedza_firmy.eksport wiedza.md` — cała baza (żywe wpisy) w formacie importu, każdy wpis z `[#id]`;
   treść w jednej linii. Plik jest przed zapisem wczytywany z powrotem i porównywany z bazą.
2. W pliku przenieść wpis do innej sekcji `## temat:` (zmiana głównego) albo dopisać/zmienić `[+a,b]`.
   Wpisy, których nie trzeba zmieniać, można z pliku usunąć.
3. `python -m wiedza_firmy.ustaw_tematy wiedza.md --na-sucho` — lista zmian; potem bez `--na-sucho`.
   Zmienia tylko tematy; treść musi się zgadzać z bazą (inna = odmowa: plik z innej bazy albo pomylone id).
   Wpis bez id, powtórzone id, id spoza bazy, nieznany temat = odmowa całości. Przed zapisem kopia bazy.

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

## Klient: komputer sam bierze token i wysyła wpisy (od 0.4.0)

Trasy `/klient/*` (moduł `klienci.py`, podpis w `podpis.py`) działają tylko w trybie JFTools; bez niego odpowiadają
503 `wylaczone`. Umowa z klientem (`narzedzia/wiedza-firmy-klient`) i wtyczką JFTools: raport
`.megaruchacz/raporty/wiedza-firmy-krok3-projekt.md`, sekcja 2. Rejestracja jest bez kodu zaproszenia: komputer
zgłasza się sam w JFTools (`register-self`, status pending), a dostęp daje dopiero admin, zatwierdzając go w panelu.

Przepływ:

1. Klient ma parę kluczy ed25519, a JFTools ma jego klucz publiczny (`register-self` albo `register` z ecommerce-helper).
   Jeden komputer to jeden wpis w JFTools: `computerId`.
2. `POST /klient/token` (bez tokenu) `{computerId, ts, nonce, podpis[, wymien]}`. Podpisywany tekst (UTF-8, bez końca
   linii): `jfwiedza-token|{computerId}|{ts}|{nonce}`; `ts` to sekundy Unix (liczba całkowita), a `nonce` ma 16–128
   znaków `[A-Za-z0-9_-]`. `podpis` przyjmuje dwie postacie:
   - surowy podpis ed25519 (64 bajty) w base64, np. `cryptography`: `Ed25519PrivateKey.sign(tekst)`. Tak podpisuje
     `klient.py` (test zgodności w `tests/test_klienci.py` woła jego `Klucz.podpisz`);
   - blok SSHSIG z `ssh-keygen -Y sign -n jfwiedza -f <klucz> <plik z tekstem>`.

   Serwer bierze klucz komputera z `GET <baza>/keys` JFTools (pending + active; lista ważna 30 s, ponowne pytanie
   najwyżej co 5 s), sprawdza `ts` (±300 s) i nonce (pamiętany 10 min, w pamięci procesu), zakłada w `osoby.json`
   wpis `komputer-<id>` i zwraca `{token, osoba, wynik: wydano}` jeden raz. Drugi token dostaje się tylko
   z `"wymien": true` + podpisem (`wynik: wymieniono`, a stary token przestaje działać). Bez tego serwer odpowiada 409 `juz_wydany`.
   Wpisu założonego ręcznie o tej nazwie automat nie nadpisuje.
   Odmowy `{kod, opis}`: 400 `zle_dane`; 401 `zly_podpis` (także `ts` poza oknem, wtedy z `czas_serwera`, i powtórzony
   nonce); 403 `nieznany_komputer` / `zablokowany`; 409 `juz_wydany`; 429 `za_czesto` (30 prób na 10 min z jednego
   adresu); 503 `jftools_niedostepny`. Każda próba trafia do `zgloszenia-klientow.log`.
3. `GET /klient/status` (Bearer) → `{status: active|pending|blocked|nieznany, osoba, komputer, nazwa_komputera,
   wlasciciel}`; blocked/nieznany = 403 z tym samym ciałem i `kod`.
4. `GET /klient/tematy` (Bearer, także pending) → `{tematy, zasady, wersja, status}`; `wersja` = sha256 tematów i zasad.
5. Admin zatwierdza komputer w JFTools i przypisuje osobę (`owner.name`) → status active.
6. `POST /klient/wpisy` (Bearer) `{paczka_id, wpisy: [{klucz, tresc, temat, tematy_dodatkowe[], poufnosc, data,
   zrodlo, program}]}`, najwyżej 100 (więcej = 413 `za_duzo`, nic nie zapisane) → `{paczka_id, autor, wyniki: [{klucz,
   wynik: dodano|duplikat|usuniety_wczesniej|blad, opis?}], uwagi?}`. Zły wpis odrzuca tylko siebie. Duplikat to ta sama
   treść w tym samym temacie głównym, także w obrębie jednej paczki. Autor to `owner.name` z JFTools, a gdy go nie ma,
   nazwa komputera z JFTools. Pole autora z ciała nie jest czytane. Pending dostaje 409 `czeka_na_zatwierdzenie`,
   a blocked i usunięty 403.

Unieważnianie: blokada w panelu oznacza brak komputera w `keys` (nowy token nie powstanie) i status blocked. Wtedy
`/klient/*` daje 403, narzędzia MCP z tym tokenem są puste z komunikatem, a `dodaj_wpis` odmawia (od 0.4.0 każdemu,
czyj komputer w JFTools nie jest active). Komputer usunięty z JFTools (404) dostaje w `osoby.json` znacznik `wygasl`.
Odblokowanie przywraca dostęp temu samemu tokenowi, najpóźniej po minucie (pamięć statusu komputera bez dostępu).

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
python -m wiedza_firmy.eksport <plik.md> [--nadpisz]    # cała baza w formacie importu, z [#id]
python -m wiedza_firmy.ustaw_tematy <plik.md> [--na-sucho]   # podmiana tematów istniejących wpisów wg pliku
python -m wiedza_firmy.model                            # pobiera brakujące pliki modelu, sprawdza sumy, ładuje
python -m wiedza_firmy.serwer [--host 0.0.0.0] [--port 8766]
```

Serwer: streamable HTTP pod `/mcp` w trybie bezstanowym (każde żądanie niesie swój token).
`WIEDZA_FIRMY_HOSTY` (opcjonalnie, nazwy i adresy rozdzielone przecinkami) włącza sprawdzanie nagłówka
Host także przy `0.0.0.0`.

Narzędzia MCP: `szukaj_wiedzy(pytanie, temat?, limit=8)`, `tematy()`, `moje_uprawnienia()`,
`dodaj_wpis(...)` (każdy, tylko na wyraźne „dodaj do wiedzy firmy …”), a tylko dla admina `usun_wpis(id, powod)`.
Instrukcje serwera (`serwer.INSTRUKCJE`, poniżej 4096 znaków, które czyta Claude Code) każą prośby „napisz/powiedz
coś o X” obsługiwać przez `szukaj_wiedzy`, a przed zapisem pokazać treść, temat i poufność.

## Testy

```
uv --directory wiedza_firmy run pytest
```

Testy niczego nie pobierają: wektory liczy atrapa, a JFTools udaje lokalny serwer HTTP na 127.0.0.1
(`tests/test_jftools.py`, trasy klienta: `tests/test_klienci.py`; test zgodności z `ssh-keygen -Y sign` rusza,
gdy `ssh-keygen` jest w PATH). Test prawdziwego modelu rusza tylko wtedy, gdy model
już leży na komputerze (`~/.claude/lore_models`, `~/.lore/lore_models` albo `WIEDZA_FIRMY_TEST_MODELE`).
W innym wypadku zostaje pominięty z podanym powodem.
