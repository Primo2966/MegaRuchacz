# Mapa projektu

Tryb pracy: bez worktree — testy wymagają PowerShella, a w kopii roboczej Claude Code go blokuje. Workerzy równolegle w tym samym katalogu, każdy na swoich plikach.

Co gdzie lezy - czyta to kierownik przed wyslaniem scouta i worker na starcie; scout dopisuje
ustalenia (tylko `Edit`, bez przepisywania calosci). Numerow linii nie ma z premedytacja
(rozjezdzaly sie i wprowadzaly w blad) - funkcje szukaj po nazwie: `grep -n "function Nazwa"`.
Stare rozpoznania i opisy sprzed 30.09 (dokumentacja Codeksa, Orca, odcisk zaufania hookow,
inwentarz warstw z 25.09, budowa okna sprzed podzialu, pomiary P23/P30 w calosci) leza w
`.megaruchacz/mapa-archiwum.md` - szukaj tam grepem, nie czytaj calosci.

## Szkielet repo

- `wdroz.ps1` - instalator per projekt (sekcje "# 1. Workerzy", "# 2. Pliki stanu", "# 3. Zasady
  + payloady", "# 4. settings.json", "4b. Codex CLI", "# 6. Znacznik wersji"); rejestr modulow
  bierze z `straznik-zasad.ps1 -Moduly`, konczy samosprawdzeniem.
- `narzedzia/`: `instaluj-globalnie.ps1` (tryb globalny), `instaluj-lore.ps1` (Lore: uv, serwer MCP,
  zadanie `LoreIndex`), `straznik-zasad.ps1` (hook SessionStart), `przypomnienie.js` (hook
  UserPromptSubmit), `koszt-pamieci.ps1` + `koszt/` (rachunek), `cykl-dzienny.ps1` ->
  `wyciagnij-fakty.ps1` + `aktualizuj-wiedze.ps1` (cykl wiedzy), `przekop-archiwum.ps1`
  (jednorazowy przekop archiwum), `skille.ps1`, `kierownik-cele.ps1` (ktore pliki dostaja blok
  kierownika - wspolne instalatora i straznika), `sufit-ladunku.ps1` (sufity ladunkow hookow -
  wspolne wdroz i straznika), `wpisz-zasady.ps1` (blok Lore/Wiedza ze `zasady-globalne.md`),
  `mr-log-codex.js` (rejestr START/KONIEC pod Codeksem), `orca-ustawienia.js` (ustawienia Orki
  miedzy komputerami).
- `zasobnik/` - okno nadzorcy: `nadzorca.ps1`, `stan-nadzorcy.ps1`, moduly `nadzorca/`,
  `zainstaluj-zasobnik.ps1` (zadanie `MegaRuchaczNadzorca`), `test-p7.ps1`.
- `lore/` - pamiec rozmow (Python, uv): `lore/lore/`, `lore/tests/`, `lore/bench/`.
- `skille/katalog.psd1` - baza polecanych skilli.
- `szablony-global/claude/` (zasady kierownika, 5 rol, `mr-log.js`), `szablony-codex/`,
  `szablony-opencode/` - zrodla tego, co kopiuja instalatory (`CZYTAJ.md` w kazdym).
- `rozszerzenie/` (panel VS Code: okna zadaniowe, worktree), `nowe-zadanie.ps1` (worktree + nowe
  okno VS Code), `wyczysc-historie.sh` (jednorazowe czyszczenie historii przed upublicznieniem).
- `ZMIANY.md` - historia wersji; wersja narzedzia = najwyzszy naglowek `## X.Y.Z`.
- `.megaruchacz/`: `mapa.md` (sledzona), `mapa-archiwum.md`, `worklog.md` (od P36 poza gitem -
  `.gitignore`; dopisuja go hooki i kierownik na kazdej maszynie osobno), `raporty/` (czesc sledzona).
- `CLAUDE.md` repo: "Cisza jest zakazana" + "Konwencje pracy w tym repo" (bez worktree, kodowanie
  sprawdzane bajtowo, testy niewidoczne, commit bez `Co-Authored-By`, push/ZMIANY/mapa robi
  kierownik, restart nadzorcy).
- Maszyny: biurowa `C:\dev\claude-worker` (Claude Code, tryb globalny); domowa
  `D:\OrcaSpace\MegaRuchacz` (uzytkownik `<login-domowy>`, Codex/Orka; nowsze wersje pobiera straznik `-Tlo`
  przy starcie sesji Codeksa i przycisk w oknie). SSH przez Tailscale:
  `~\.claude\wiedza\polaczenia-ssh.md`.

## Straznik i aktualizacja (`narzedzia/straznik-zasad.ps1`)

- Wolany hookiem `SessionStart`: pod Claude Code zwykly przebieg (w trybie globalnym wpis w
  `~\.claude\settings.json`), pod Codeksem `-Tlo` (async, nic nie wstrzykuje - slad w
  `~\.claude\.megaruchacz-tlo.log`). Stan: `~\.claude\.megaruchacz-straznik.txt`; bledy
  `Zanotuj-Wywrotke` (meldowane przy nastepnym otwarciu okna). Funkcje: `Rejestr-Modulow` (moduly
  `workerzy`, `pamiec`), `Odswiez-Zrodlo`, `Pilnuj-Zasad` (blok Lore w `~\.claude\CLAUDE.md`
  i `~\.codex\AGENTS.md`), `Pilnuj-Kierownika`, `Pilnuj-Kopii-Opencode`, `Pilnuj-Wersji` ->
  `Nanies-Poprawki` -> `Nanies-Poprawki-Codex`, `Napraw-Hooki` / `Napraw-Hooki-Codex` (tylko
  BRAKUJACE hooki), `Pilnuj-Hookow-Globalnych`, `Projekt-Bez-Hookow`, `Pilnuj-Sufitu-Zawsze`,
  `Zglos-Koszt` / `Wypisz-Koszt-Codex` (+ `Odcisk-Rachunku`),
  `Zglos-Odsylacze`, `Powiedz-Wazne`.
- Wersje wdrozen per projekt: najwyzszy `## X.Y.Z` w `ZMIANY.md` zrodla kontra `modul.<nazwa>.wersja`
  w `<projekt>\.claude\megaruchacz-wersja.txt` (klucze `zrodlo:` - BEZWZGLEDNA sciezka repo,
  `commit:`, `data:`, `modul.*`, `codex.wersja` / `codex.data`, od P33 opcjonalnie `codex: tak`;
  blizniak `.megaruchacz/wersja.txt` dla Codeksa). Patch -> `Nanies-Poprawki` sam; minor -> pliki
  wchodza, nowa funkcja tylko proponowana; major -> komunikat o recznym `wdroz.ps1`. Modul
  z `aktualizacja = "instalator"` (`pamiec`) nigdy sam. Odmowy: `modul.<x>.status: odrzucony`,
  `.odrzucone`, `.zaproponowane` (`straznik-zasad.ps1 -Odrzuc <modul>`).
- Sciezka zrodla zaszyta bezwzglednie w hooku (`dodajStraznika()` w `wdroz.ps1`, `{{ZRODLO}}`
  w `szablony-codex/hooks.json`); przeniesienie repo psuje hook, a straznik przy nieistniejacym
  `-Zrodlo` milczy i konczy zerem.
- Codex w projektach (P33): `Nanies-Poprawki-Codex` / `Napraw-Hooki-Codex` pracuja na
  `<projekt>\.codex`, nigdy na `~\.codex`, i tylko gdy `Codex-W-Projekcie`: hooki MegaRuchacza
  w `<projekt>\.codex\hooks.json`, role z `kierownik-template` w `<projekt>\.codex\agents` albo
  `codex: tak` w pliku wersji; inaczej jedna linia "Codex w tym projekcie: role i hooki pominiete"
  (bez Codeksa nigdzie - cisza). Dziala przy podbiciu wersji wdrozenia; od razu: `wdroz.ps1 -WymusCodex`.
- `Odcisk-Rachunku` = SHA256 z "nazwa=SHA256" pliku `koszt-pamieci.ps1` i wszystkich
  `narzedzia\koszt\*.ps1` (kolejnosc porzadkowa; bez `koszt\` - sam plik). Zmiana w module
  uniewaznia zapamietana linie w `~\.claude\.megaruchacz-koszt*.txt` (P33).
- Straznik NIE czyta stdin (od P43; alarm dlugiej rozmowy usuniety). Stary klucz `dluga_rozmowa`
  w `.megaruchacz-straznik.txt` zostaje, nikt go nie czyta.

### Kto odswieza kopie narzedzia (`Odswiez-Zrodlo`)

- PIERWSZY krok kazdego przebiegu straznika i jedyne miejsce, ktore siega do zdalnej: `git fetch
  --quiet`, potem wylacznie `git merge --ff-only --no-overwrite-ignore @{u}` (goly `--ff-only`
  po cichu nadpisuje plik ignorowany, ktory dodaje nowa wersja).
- Kiedy: przy starcie sesji; zwykly przebieg najwyzej raz na 60 min na katalog (znacznik
  `~\.claude\.megaruchacz-pobranie.txt`), `-Tlo` (Codex) bez dlawika - decyzja uzytkownika. Limity:
  zwykly 5 s na komende gita i 6 s na `fetch` (hook ma 15 s), `-Tlo` 30 s i 60 s. Bez pytan o haslo
  (`GIT_TERMINAL_PROMPT=0`, `credential.interactive=never`).
- Warunki odmowy (od P36): brak gita; nie repozytorium; galaz bez zdalnej albo odpiety HEAD; fetch
  nieudany; zdalna bez nowosci (cisza); HISTORIA ROZJECHANA (glosno, nie scala); git odmowil
  przewiniecia - nadpisalby lokalna zmiane, plik spoza gita albo ignorowany (glosno, z lista plikow).
  Samo "brudne repo" NIE jest powodem - do P36 bylo i jeden raport spoza gita blokowal pobieranie
  na zawsze (dom od 28.09).
- `Plan-Przewiniecia` dzieli pliki na: robocze, lokalne zmiany w plikach zmienianych przez nowa
  wersje, pliki spoza gita tam, gdzie nowa wersja kladzie swoje, zmiany po `git add`.
- Pliki robocze (`$WZORY_PLIKOW_ROBOCZYCH`: `.megaruchacz/worklog.md`, `.megaruchacz/raporty/*`,
  pliki wdrozenia `.codex/*`, `.opencode/*`, `.claude/megaruchacz-*`, `.megaruchacz/{wersja.txt,
  zasady-*,przypomnienie.json}`; MAPY celowo nie ma - jej zmiana blokuje jak kod): kopia
  w `~\.claude\.megaruchacz-kopia-zrodla\z<skrot sciezki>\<czas>\` (spis `spis.txt`, MD5); gdy git
  odmawia WYLACZNIE przez nie - zdjete z drogi i druga proba; potem oddane, nigdy nie nadpisujac
  innej tresci (wtedy kopia zostaje, glosny meldunek, wynik `kopia`). Przerwany przebieg:
  `Dokoncz-Przerwane` najpierw oddaje pliki. Blokada `Local\MegaRuchacz-zrodlo`.
- Wynik kazdej proby w stanie straznika: `aktualizacja.kiedy/zrodlo/wynik/powod/pliki/kopia`;
  `wynik` = pobrane | aktualne | zablokowane | rozjechane | nieudane | kopia | bez-sieci |
  bez-zdalnej | nie-repo | bez-gita. Zdania do czlowieka: `Powiedz-Wazne` (w `-Tlo` tez `mow.*` ->
  ladunek Codeksa). Przycisk w oknie jeszcze tego nie czyta (spec: raport P36 pkt 6, zadanie P37).
- Zadnego `reset --hard`, `checkout -f`, `clean`, `stash`. Udane przewiniecie = jedna linia (stara ->
  nowa wersja). Limit 6 s na `merge` w trybie okna moglby przy duzej aktualizacji zostawic
  `index.lock` (dzis < 1 s).
- Nie ma zadania Harmonogramu aktualizujacego narzedzie (`MegaRuchaczOdswiez` z 0.13.0 `wdroz.ps1`
  zdejmuje). Poza `Odswiez-Zrodlo` git tylko do odczytu (`rev-parse --short HEAD`, `ls-files`).

## Instalacja globalna, zasady kierownika, role

- Tryb globalny (od 0.19.0; znacznik `~\.claude\.megaruchacz-global`: `zrodlo/wersja/data/wariant`):
  hooki MegaRuchacza w GLOBALNYM `~\.claude\settings.json` - dzialaja w KAZDYM projekcie Claude Code
  na maszynie; projektowy `.claude\settings.json` repo ma tylko `{"hooks": {}, "worktree": {...}}`
  (pilnuje `Projekt-Bez-Hookow`; wyjatek `projektowo: wymuszone` z `wdroz.ps1 -WymusProjektowo`).
- `narzedzia/instaluj-globalnie.ps1`: aktualizacja `-BezPytania`, plan `-Proba`, `-Usun`,
  `-WariantZasad claude|opencode`, `-Codex`. `[CmdletBinding()]` - nieznana flaga = blad, kod 1.
  PULAPKA PS 5.1: w skrypcie z `[CmdletBinding()]` uruchomionym przez `-File` `$PSScriptRoot` /
  `$PSCommandPath` w wartosciach domyslnych `param()` sa PUSTE - domyslne sciezki liczyc pod `param()`.
  Role: `$RoleClaude` (5, z projektantem), `$RoleOpencode` (4 - brak szablonu projektanta). Role
  `~\.codex\agents` i hooki `~\.codex\hooks.json` tylko z `-Codex` albo gdy sa tam juz hooki/role
  MegaRuchacza (`Codex-Od-MegaRuchacza`); inaczej jedna linia "pominiete". `$KomendaCodex` (dawne
  `$Codex` kolidowalo z flaga - PS nie rozroznia wielkosci liter). `-Usun` nie zdejmuje rol i hookow
  Codeksa z `~\.codex`.
- Zasady kierownika: `szablony-global/claude/zasady-kierownika.md` = ZRODLO wariantu Claude Code
  (blok `MegaRuchacz:kierownik` w `~\.claude\CLAUDE.md`, sufit ~11 000 znakow ze znacznikami,
  30.09 ~10 990; tez `.claude\megaruchacz-zasady.md` wdrozen per projekt).
  `szablony-opencode/zasady-kierownika.md` - wariant opencode/Codex (`~\.codex\AGENTS.md`,
  `~\.claude\CLAUDE.md` na maszynie bez Claude Code; 30.09 jeszcze stare zasady).
  `szablony-codex/zasady-kierownika.md` - AGENTS.md projektu przy wdrozeniu Codeksa. Blok kierownika
  wpisuje i AKTUALIZUJE wylacznie instalator; straznik `Pilnuj-Kierownika` tylko dopisuje brakujacy.
  opencode czyta pierwszy istniejacy z `~\.config\opencode\AGENTS.md` i `~\.claude\CLAUDE.md`, wiec
  ten pierwszy = KOPIA `CLAUDE.md` z blokiem w wariancie opencode (znacznik
  `<!-- MegaRuchacz:kopia-dla-opencode` w 1. linii; `Pilnuj-Kopii-Opencode`). Wspolny kod:
  `narzedzia/kierownik-cele.ps1`.
- Role Claude Code: jedno zrodlo `szablony-global/claude/agents/*.md` (instalator -> `~\.claude\agents\`,
  wdroz -> `.claude\agents\`; swoje rozpoznaje po `kierownik-template`). implementer i projektant
  (`model: inherit`; projektant = implementer + `Skill`, zadania z wygladem), scout, verifier,
  zastepca (`model: sonnet`; scout ma `Edit` tylko do mapy, verifier tylko przy ryzyku, zastepca na
  zadanie). Limit raportu i "WYMAGA DECYZJI" / `SendMessage` stoja w rolach. Wbudowani do odczytu
  dostaja od kierownika `model: "sonnet"` (np. Explore); `claude-code-guide` zostaje na haiku;
  general-purpose nigdy (start ~153 tys. tokenow zamiast ~23 tys.).
- Stan pracy: `<projekt>\.megaruchacz\` (`worklog.md`, `mapa.md`, `raporty\`). W innych repo na
  biurowej leza jeszcze stare `.claude\` z mapami sprzed 0.19.0 (projekt-a, projekt-b,
  projekt-c, projekt-d).

## Co leci do modelu (hooki i warstwy pamieci)

- Raz na sesje: `~\.claude\CLAUDE.md` (w kazdym projekcie; "Co wiem" stala - sufit 8000 znakow,
  "Biezace" `- [RRRR-MM-DD]`, blok `<!-- MegaRuchacz:start/koniec -->` Lore/Wiedza - utrzymuje
  `Pilnuj-Zasad`, blok kierownika - instalator) i `CLAUDE.md` projektu; straznik (SessionStart) nic
  nie wstrzykuje poza liniami do czlowieka. `~\.claude\mr\megaruchacz-sesja.json` (`Zbuduj-Sesje`)
  w trybie globalnym NIKT nie czyta (relikt po 0.20.0). Natywna pamiec Claude Code
  `~\.claude\projects\C--dev-claude-worker\memory\` - pusta.
- Kazda wiadomosc: UserPromptSubmit -> `narzedzia/przypomnienie.js` z ladunkiem
  `~\.claude\mr\orchestrator-reminder.json` (725 znakow; projektowa kopia w `.claude\` martwa
  w trybie globalnym). Wejscie czytane NAJPIERW: powiadomienie (`<task-notification>` albo
  `[SYSTEM NOTIFICATION...]` na poczatku promptu) -> pusty stdout, slad w
  `~\.claude\wiedza\.powiadomienia-stan.json` (`MR_POWIADOMIENIA_STAN`, klucz `powiadomienia`).
  Transkryptu hook nie czyta (od P43). Inaczej dokleja: linie cyklu
  z `~\.claude\wiedza\.cykl-postep`, 1-2 fragmenty "Z ARCHIWUM" (`lore\lore\recall.py`, FTS5; stan
  `.archiwum-stan.json`), alarm awarii Lore; sufit doklejki 1500 znakow.
- Rejestr: `~\.claude\megaruchacz-mr-log.js` (SubagentStart/Stop, globalny) dopisuje START/KONIEC do
  `.megaruchacz\worklog.md` i rejestr okien `<rodzic-repo>\.mr-okna\<ID>.json`; `.claude\mr-log.js`
  repo to szablon wdrozen per projekt.
- Na zadanie (bez hooka): mapa, rejestr, pliki `~\.claude\wiedza\*.md`, MCP `lore_search` / `lore_context`.

## Lore - pamiec rozmow (`lore/`)

- Baza: `LORE_HOME` > `~\.claude\lore.db`, gdy istnieje (biurowa, ~425 MB) > `~\.lore\`.
  `lore/lore/`: `index.py` (przyrostowe indeksowanie transkryptow, zadanie `LoreIndex`), `db.py`
  (sciezki, schemat, embeddingi), `search.py` (FTS5 + wektory, RRF), `server.py` (MCP `lore`:
  `lore_search`, `lore_context`, `lore_stats`), `recall.py` ("Z ARCHIWUM"), `facts.py` (wylawianie
  faktow; `MODEL_ARGS` z `--model sonnet` od P25 - tez przekop archiwum `mining.py`),
  `selection.py` (ktore wiadomosci ida do modelu), `verify.py` (weryfikacja, wpis do "Co wiem",
  odsylacze), `migrate.py` (przeliczenie wektorow), `masking.py` (sekrety). Testy: `uv --directory
  lore run pytest` (01.10: 410).
- Cykl wiedzy: `narzedzia/cykl-dzienny.ps1` rusza przy pierwszej sesji dnia (straznik, osobny proces)
  i z okna (`Ruszaj-Cykl`) - bez zadania w Harmonogramie (`LoreCykl`, `LoreCyklPonow`, `LoreWiedza` to
  nazwy tylko do zdejmowania) -> `wyciagnij-fakty.ps1` + `aktualizuj-wiedze.ps1`; stan
  w `~\.claude\wiedza\`: `.cykl-stan`, `.cykl-postep`, `.koszt-cyklu.txt`, `.wiedza-stan.txt`.
- Pliki wiedzy (od 0.22.2): KAZDY `~\.claude\wiedza\*.md` ma odsylacz w "### Dane referencyjne"; bez
  worka `do-nazwania.md`. Zestawienie idzie do pliku nazwanego przez model (`facts.py`: `FACTS_SCHEMA`
  wymaga `plik`, `with_known_files()`) albo z tresci (`name_from_text`); bez nazwy -> "Biezace"
  + UWAGA. Plik i odsylacz razem: `verify.py` `place_references` (wycofanie `undo_references`);
  kompletnosc: `ensure_pointers` w cyklu + `Zglos-Odsylacze` w strazniku. Bez odsylacza:
  `facts.TECHNICAL_FILES` (kandydaci, zrodla, historia-zmian, uspione, README), `uspione-archiwum-RRRR.md`
  (`facts.is_technical`, `ARCHIVE_PATTERN`) i pliki z kropka. PULAPKA: `straznik-zasad.ps1`
  (`Zglos-Odsylacze`, `$techniczne`) nie zna jeszcze wzorca `uspione-archiwum-\d{4}\.md` - dopisac,
  zanim pierwszy plik archiwum powstanie (najwczesniej ~2028).
- Stala warstwa wiedzy - usypianie (P39): fakt AUTOMATU zasypia po `SLEEP_DAYS = 180` dniach od
  pozniejszej z dat: ostatnie UZYCIE przez agenta albo wzmianka uzytkownika (`verify.Trail.last_confirmed`
  / `last_used`). Uzycie zaznacza dzienny przebieg modelu (`facts.watched_facts` -> lista na koncu
  materialu, pole `uzyte` w schemacie, slad "uzyty" w `wiedza/zrodla.md`); sufit listy
  `MAX_WATCHED_CHARS = 7 500` zn. (~2,6 tys. tokenow). Uzycie lub wzmianka budzi uspiony fakt (cofniecie
  przez uzytkownika czeka na JEGO slowo). Uspione > `ARCHIVE_DAYS = 730` ->
  `wiedza/uspione-archiwum-<rok uspienia>.md`, linia 1:1, blad zapisu zostawia ja w `uspione.md`.
  Przypiete (bez zdarzenia automatu w sladzie) nie zasypiaja nigdy. Pulapki: model widzi tylko wybrane
  wiadomosci uzytkownika + 200 zn. odpowiedzi agenta; Codex bez `--json-schema` nie zwraca `uzyte`
  (glosne "no uzyte field").
- Uzycie faktu bez modelu (P44): `lore/lore/usage.py`, wolane z `facts.main()` (`_use_by_keyword`) przed
  przebiegiem modelu (0 tokenow). Dla faktow AUTOMATU ze stalej (nie uspionych) dobiera slowa-dane
  wlasne faktu (regula w komentarzu modulu: liczby 5+ cyfr, kody, identyfikatory, e-mail, cytaty; slowo
  nie moze stac nigdzie indziej w plikach instrukcji; slabe tylko w parze) i szuka ich w pelnych
  odpowiedziach agenta i wejsciach narzedzi w transkryptach (`index.find_files`). Czyta strumieniowo od
  pozycji per plik (`wiedza/.ostatnie-uzycie-pozycje.json`) i znacznika `wiedza/.ostatnie-uzycie`;
  trafienie = linia "uzyty" w `zrodla.md` ze zrodlem "transkrypty, bez modelu, slowa: ...". Edycje
  `CLAUDE.md`/`AGENTS.md`/`wiedza\` to nie uzycie. Pomiar 2026-10-01: 160 MB / 24 h w 0,7 s.
- Awans przez UZYCIE (0.24.1): `verify.Trail.confirmations` liczy do `MIN_CONVERSATIONS` wzmianki ORAZ
  linie "uzyty" z dnia POZNIEJSZEGO niz pierwsze wylowienie i ze znanym zbiorem sesji; zliczane razem
  przez `conversations()` (rozlaczne zbiory), wiec uzycie w rozmowie zrodlowej nic nie dodaje; bez
  wylowienia 0. Linia ze zrodlem `facts.USED_WEAK` ("tylko slabe slowa", sama para slabych slow) trzyma
  fakt w stalej, ale nie awansuje (regula 5 w `usage.py`). Model i `usage.py` patrza teraz takze na
  biezace fakty automatu, ktore moga awansowac (`Trail.use_matters`: nie etykieta "biezaca", nie
  przypiete). `usage.session_of` nazywa rozmowe jak indeks (Codex: uuid z `rollout-...-<uuid>`).

## Rachunek za pamiec (`narzedzia/koszt-pamieci.ps1` + `narzedzia/koszt/`)

- Od P27 `koszt-pamieci.ps1` = PLIK WEJSCIOWY: param, progi z uzasadnieniem, ladowanie modulow,
  przebieg i exit kazdego trybu (BUDOWA w naglowku). Tryby: domyslny (pelny raport; to samo pisze
  zadanie `LoreKoszt` o 08:15 do `~\.claude\wiedza\koszt-ostatni.txt`), `-Zwykly`, `-Zwiezle` (linia
  straznika), `-Dane` (klucz: wartosc dla okna), `-Rozbicie`, `-TylkoSufity`, `-Warstwy` (JSON warstw
  dla okna), `-Start` (otwarcie sesji z transkryptow), `-ZalozZadanie` / `-UsunZadanie`; do tego
  `-Narzedzie Claude|Codex`, `-Projekt`, `-Zrodlo`, `-KatalogDomowy`.
- Moduly (naglowek "co i skad wolane"): `podstawy`, `warstwy` (`Zmierz-Warstwy` - warstwy CLAUDE.md,
  `Pozycja`), `sufity` (`Sufit`, `Limit-Hooka`, `Ladunek-Hooka` - wyciaga pole JSON ladunku,
  `Tryb-Sufity`), `nauka` (koszt cyklu, `Ocena-Cyklu`, `Statystyka-Nauki`), `baza-lore` (winsqlite3),
  `pomiar-dzienny` (`Zaloz-Zadanie`, `Poprzedni-Pomiar`), `pomiar` (`Etap-Pomiar`: hooki, ladunki,
  `$sufity`), `kubelki` (`Etap-Kubelki`: `$kubWiadomosc` / `$kubSesja` + Codex - warstwy z plikami
  zrodlowymi), `otwarcie` (`Pomiar-Otwarcia`, `Tryb-Start`; `$rolyWorkerow` = te same role co
  `$RoleClaude`), `tryb-warstwy`, `alarmy` (`Etap-Ocena`, `Rachunek-Narzedzia`, `Linia-Narzedzia`),
  `tryb-dane`, `tryb-rozbicie`, `raport-pelny`.
- Etapy i tryby = funkcje wolane KROPKA (zasieg skryptu). exit trybow i `$PSScriptRoot` /
  `$PSCommandPath` TYLKO w pliku wejsciowym (exit w pliku wczytanym kropka konczy tylko ten plik;
  exit w funkcji z modulu - caly skrypt). Nowy modul: nazwa na liscie w pliku wejsciowym + ostatnia
  linia `$script:ModulyKosztu["nazwa"] = $true`; brak, blad albo uciety modul = kod 1 z powodem,
  pusty stdout.
- Alarm "MegaRuchacz kosztuje duzo" (P35): `$AlarmCzesciOtwarcia` = 15000 TOKENOW czesci MegaRuchacza
  (start + przypomnienie; 30.09 Claude Code ~9 100, Codex ~5 100), nie procent - procent zalezy od
  wagi dodatkow ustawianej przez admina proxy. `NadProgiem` liczone zawsze (bez calosci, takze
  Codex); procent calosci tylko do pokazania. `-Dane`: `udzial.prog_tokeny` (klucz `udzial.prog`
  zniknal), `udzial.mr`, `udzial.start`; prog drukuja tez `tryb-rozbicie` i `raport-pelny`.
- Kto wola: straznik (w procesie, `2>$null`), okno (`Wolaj-Skrypt`, osobny proces: `-Rozbicie`,
  `-Dane -Zwykly`, `-Warstwy`, `-Start`), `LoreKoszt` (`| Set-Content`). Test lore
  `test_the_ceiling_matches_the_number_the_cost_script_reports` czyta `$ProgStalej` z pliku
  wejsciowego. Przerobki sprawdza zestaw rownowaznosci 212 przypadkow przed/po (opis w raporcie P27;
  skrypty byly w scratchpadzie). Komentarze w `lore\lore\facts.py`, `verify.py`,
  `narzedzia\sufit-ladunku.ps1` wskazuja funkcje "w koszt-pamieci.ps1" - leza w `koszt\`.

## Nadzorca (zasobnik) - okno

- Od P28a PLIKI WEJSCIOWE + 22 moduly w `zasobnik/nadzorca/` (BUDOWA w naglowku obu).
  `zasobnik/nadzorca.ps1` = param (`-Zrodlo`, `-KatalogDomowy`, `-Minut`, `-Pokaz`, `-Raz`, `-Raport`,
  `-Proba`, `-Cicho`), start, tryby bez GUI, zamek `Local\MegaRuchacz-Nadzorca`, ikona z menu, zegar
  dozoru, petla i WSZYSTKIE exit. Moduly wczytuje w dwoch miejscach: przed trybami bez GUI
  `przeglad-tresc`, `szczegoly`, `dozor`; po zamku reszta. `zasobnik/stan-nadzorcy.ps1` = ustawienia
  `$script:Nadz...`, `$script:NadzTenPlik`, wczytanie `nadzorca/stan-*.ps1`, DOPIERO POTEM
  `Ustaw-Nadzorce` (`$KOD_KROKU` wczytuje stan, gdy jej nie ma - po bledzie probuje znowu).
- Okno: `przeglad-tresc` (`Zbierz-Problemy`, `Napisy-Przyciskow`, `Zbuduj-Przod` - Przeglad jako
  tekst), `szczegoly` (`Sekcje-Szczegolow`, `Sekcja-Kosztu`, `Dodaj-Wykres`, `Zbuduj-Szczegoly`,
  `Napelnij-Szczegoly`), `dozor` (`Dozor` dla -Raz; `Rusz-Dozor` -> `Po-Dozorze` -> `Dozor-Po-Danych`),
  `wyglad` (wszystkie `$script:` okna, kolory, czcionki, `Wymus-Pokazanie`), `karty` (klocki:
  `Nowa-Karta`, `Nowy-Przycisk`, `Wiersz-Dwukolumnowy`, `Tabela-Kontrolka`, `Karta-Sekcji`,
  `Karta-Komunikatu`), `przeglad` (`Odmaluj-Werdykt`, `Odmaluj-Koszt`, `Odmaluj-Start`,
  `Odmaluj-Problemy`, `Odmaluj-Stan`, `Odmaluj-Okno`), `wykres` (`Panel-Wykresu`, `Wstaw-Wykres`;
  Chart albo wlasne slupki), `warstwy`, `skille`, `w-tle`, `ladowanie`, `okno` (`Pokaz-Okno`,
  `Pokaz-Widok`).
- Stan: `stan-podstawy` (`Czytaj-Klucze` / `Zapisz-Klucze`, `Notuj`, `Zanotuj-Wywrotke`, `Wolaj-Gita`,
  `Wolaj-Skrypt`, `Odpal-W-Tle`), `stan-wersja` (`Stan-Wersji` - fetch + `rev-list HEAD...@{u}`,
  `Opis-Wersji`, `Aktualizuj` -> `straznik-zasad.ps1 -Tlo`), `stan-cykl` (`Stan-Cyklu`, `Ruszaj-Cykl`),
  `stan-rachunek` (wolania `koszt-pamieci.ps1`: `Rachunek-Rozbicie`, `Linia-Rachunku`,
  `Warstwy-Pamieci`, `Pomiar-Startu`, `Opis-Startu`), `stan-zuzycie` (licznik C#, `Policz-Zuzycie`
  w osobnym procesie, `Zuzycie-Dzienne`), `stan-koszt` (`Koszt-Dzis`, `Teksty-Kosztu`,
  `Werdykt-Kosztu`, `Wzrost-Do-Progu`, `Alarmy-Rachunku`), `stan-alarmy` (`Zbierz-Alarmy`, jeden
  alarm na sprawe na dobe), `stan-po-ludzku` (odmiana, daty, `Linie-Stanu`, `Szacunek-Cyklu`),
  `stan-skille`, `stan-zbieranie` (`Zbierz-Wszystko` -> `$script:Dane`).
- Modul: naglowek "co i skad wolane", UTF-8 Z BOM, CRLF, ostatnia linia `$script:ModulyOkna["x"] =
  $true` / `$script:NadzModuly["x"] = $true`; bez exit i `$PSScriptRoot` / `$PSCommandPath`. Brak,
  blad skladni albo uciety modul: kod 3 (`Odmowa-Nadzorcy`: stderr + "NIE WSTALEM: ..."
  w `~\.claude\.megaruchacz-zasobnik.log`); krok w tle - blad z nazwa modulu. Kody: 1 w -Raz = alarm,
  2 zly -Zrodlo, 3 odmowa startu.
- Zakladki (panele `Dock=Fill` przelaczane `Pokaz-Widok`, nie `TabControl`): Przeglad, Szczegoly,
  Warstwy pamieci, Skille. Wszystko, co wola skrypty, liczy sie w OSOBNYCH PROCESACH powershell.exe
  (`w-tle.ps1` -> skrypt kroku `nadzorca\licz-krok.ps1`, ktory dot-source'uje `$script:NadzTenPlik`
  i liczy kawalek po NAZWIE switchem; P38: dawniej runspace'y, ale kod watku skladany ze stringa
  wygladal Defenderowi na omijanie zabezpieczen PowerShella - falszywy alarm na wlasnym kodzie):
  kawalki `$KAWALKI` (dane, start, zuzycie, rozbicie, warstwy, skille, koszt) i `$WIDOK_KAWALKI`
  (czego potrzebuje zakladka); stan `$script:StanKawalkow` (PULAPKA: nie `$script:Kawalki` - PS nie
  rozroznia wielkosci liter). Silnik: `Rusz-Krok` -> kolejka (`$KROKI_NARAZ` = 3) -> `Przydziel-Proces`
  (powershell.exe -NoProfile -File, wynik Export-Clixml do pliku tymczasowego, limit -> zabicie procesu)
  -> zegar 150 ms `Obsluz-Kroki` -> `Odbierz-Krok` / `Przerwij-Krok` -> `Zakoncz-Krok` -> `Po-Kroku`
  / `Wyrenderuj-Widok`.
  `Wejdz-Do-Widoku`: brak danych z dzis albo Nieudany -> ekran ladowania (`ladowanie.ps1`:
  `Pokaz-Ladowanie`, `Odmaluj-Kroki`, `Straznik-Ladowania`); starsze niz `-Minut` -> ciche
  odswiezenie. `Napelnij-*` TYLKO rysuja. Okno: stala wysokosc `min($WYS_OKNA_MAX=1400, obszar-40)`
  liczona raz w `Pokaz-Okno`; dane nie sa zerowane w FormClosed, zmienne kontrolek tak.
- Przeglad (P26, P35): werdykt (`Werdykt-Kosztu`: malo / duzo / nie wiadomo z `udzial.mr`,
  `udzial.start`, `udzial.prog_tokeny` jednego `-Dane`; "nie wiadomo" = brak progu albo
  `udzial.start` <= 0), karta "Ile tokenow naprawde zuzywasz" (`Odmaluj-Koszt`; licznik C#
  `MegaRuchacz.Tokeny.Licznik` - MAX z linii tego samego `message.id`, rozmowy / workerzy,
  `$WERSJA_ZUZYCIA` = "2" w `~\.claude\.megaruchacz-zuzycie.txt`; od P43 dwie kolumny: tabelka
  dzis/srednio 330 px + najdrozsze zadania workerow z kolumna rola/projekt `$szDop` 230 px; bez listy
  rozmow, progu i stopki "!"), otwarcie okna rozmowy, problemy,
  nauka, stan, przyciski. Wykres "Koszt czytania rozmow - ostatnie 30 dni" od P35 w Szczegolach
  (`Dodaj-Wykres` -> `Karta-Sekcji` -> `Panel-Wykresu`). Tresc Przegladu 1055 z 1121 px (okno
  1256x1352 na 2560x1440) - z karta problemu sie przewija.
- Konwencje: pliki okna UTF-8 ZE ZNACZNIKIEM BOM (bez niego PS 5.1 -> krzaki; bylo dwa razy); kod
  i komentarze bez polskich znakow, teksty w oknie z polskimi; nazwy PascalCase-po-polsku z myslnikiem.
- Produkcyjnie staly proces z zadania `MegaRuchaczNadzorca` (`conhost.exe --headless powershell.exe
  -WindowStyle Hidden -File ...nadzorca.ps1`); kodu sam nie przeladowuje - po zmianie restart (CLAUDE.md
  repo). Tryby testowe: `-Raz` (jeden dozor), `-Raport` (tresc okna tekstem), `-Proba` (nic nie
  zapisuje, nie wola modelu).
- Znane bledy (zadanie P37): `Rachunek-Rozbicie` zapetla sie, gdy `koszt-pamieci.ps1 -Rozbicie` nic
  nie wypisze (kod 1) - `-Raport` wisi na 100% CPU, w oknie krok "rozbicie" stoi do limitu;
  najpewniej to tez zawieszanie przy nieistniejacym `-KatalogDomowy` (P28a). Przycisk aktualizacji
  nie czyta `aktualizacja.*` (spec P36 pkt 6).
- TEST okna bez ekranu: kopia CALEGO `zasobnik/nadzorca/` + pliki wejsciowe, wlasny zamek, (-5000, 0),
  `ShowInTaskbar = $false`, bez ikony i dozoru, `-Proba`, bezpieczniki cyklu/skilli/tla/aktualizacji
  w kopii stanu, bez `SetForegroundWindow` (kotwica w `wyglad.ps1`; `$script:Okno = $f` w `okno.ps1`),
  `KeyPreview` + tlumienie `KeyDown`, `Application.add_ThreadException`. Prawdziwe okno tylko na
  osobnym, niewidocznym pulpicie Windows (CreateDesktop + CreateProcess z lpDesktop) - PULAPKA: tam
  nie ma paska zadan, okno wychodzi wyzsze (1400 zamiast 1352), obszar podac z prawdziwego pulpitu.
  Zrzut "ustalony": `Refresh()` + dwa identyczne zrzuty. `zasobnik/test-p7.ps1 -BezOkna` bezpieczny;
  czesc z oknem NIE ukrywa okna i nie czeka na dane Warstw - tylko na ukrytym pulpicie. Nagrywanie
  otwarcia (P21): `SendMessageTimeout` NIE wykrywa blokady watku okna. Test okna P43: scratchpad sesji
  1ca517cc, `p43\test-okno.ps1` + `scenariusz.ps1` (wzor P35, ukryty pulpit, `-Kod` = zlozona kopia
  `zasobnik`); hook i straznik PRZED/PO: `p43\test-hook.js`, `p43\test-straznik.js`.

## Polecane skille (od 0.22.0)

- `skille/katalog.psd1` - BAZA: zrodla (Id, Nazwa, Adres, Galaz, Sciezka, Opis, Rodzaj
  `skille`/`aplikacja`, Uwaga) i skille (Nazwa = katalog w repo, Opis po polsku; opcjonalnie Sciezka,
  Folder = nazwa u uzytkownika, Robocza). UTF-8 z BOM, wartosci w POJEDYNCZYCH cudzyslowach
  (PowerShell traktuje „ ” jak cudzyslow). Czytane `Import-PowerShellDataFile`. `code-review` Matta
  ma `Folder = matt-code-review` (uzytkownik zmienil nazwe i odwolania w 4 skillach - te 5 wykrywa
  sie jako "zmienione").
  Od P49 (0.25.0) zrodla `vibecode` (withkynam/vibecode-pro-max-kit, Sciezka `.claude/skills`, 33 `vc-*`)
  i `obsidian` (kepano/obsidian-skills, 6 skilli) oraz listy `Wlasne` i `Inne` (Folder, Opis, Skad, Uwaga):
  Wlasne = "Twoj wlasny" (tylko te wolno spakowac), Inne = znane zrodlo poza opieka (orchestration =
  stablyai/orca przez `npx skills`, dowiazanie do `~.agentsskills` + `~.agents.skill-lock.json`;
  synced = kopia skilli konta claude.ai, pisze ja Claude Code). Kazdy inny katalog spoza bazy = "zrodlo
  nieznane". Rozpoznanie zrodel 42 skilli spoza bazy: `.megaruchacz/raporty/P49.md`.
- `narzedzia/skille.ps1` - CALA logika (UTF-8 z BOM). `-Tryb stan|wykryj|instaluj|aktualizuj|cofnij|
  codziennie|usun|spakuj`, `-Skill`, `-ZeZrodla`, `-KatalogDomowy`, `-Katalog`, `-BezSieci`, `-Wymus`,
  `-Przerwy "5,15,30,60,120"`, `-Json` (stan dla okna, ASCII \uXXXX). Kody: 0 ok, 1 blad, 2 zle
  wywolanie, 3 zajete (zamek `Local\MegaRuchacz-Skille-<skrot domu>`). Siec: `Krok-Pobrania` (clone
  `--filter=blob:none --no-checkout` albo fetch) i `Krok-Rozpakowania` (sparse-checkout + `reset
  --hard` w NASZEJ kopii zrodla) przez `Z-Ponowieniem` (rundy, kazda proba w dzienniku); `Czy-Siec`,
  `Powod-Sieci-Po-Ludzku`. PULAPKA: `$SEKUNDY_PRZERW`, nie `$PRZERWY` (= parametr `-Przerwy`).
  Przenosiny: `Szukaj-Przenosin` (jedno `ls-tree`; jeden katalog o tej nazwie = `przeniesiony`,
  zaden = `usuniety`, kilka = blad), `Zastosuj-Przenosiny`, `Usun-Skill` (tylko `usuniety`, z kopia).
  Dalej `Przygotuj-Zrodlo`, `Najnowsze-Wersje`, `Historia-Zrodla` (jedno `git log` z pathspec
  `:(glob)**/<nazwa>/**` - kazdy stan katalogu), `Odcisk-Lokalny` (skrot "blob" surowy + po CRLF->LF,
  typ C# `MegaRuchacz.SkilleOdcisk`), `Ocen-Cel` (brak/zgodny/starszy/zmieniony), `Wykryj`,
  `Aktualizuj-Skill` (przed kopia sprawdza, czy `SKILL.md` nowej wersji jest w kopii zrodla),
  `Instaluj-Skill`, `Cofnij-Skill`, `Zrob-Kopie`, `Wgraj-Wersje`, `Stan-Dla-Okna`. Git przez
  `System.Diagnostics.Process` z `CreateNoWindow`.
  Paczka (P49): `-Tryb spakuj -Skill <folder>|*` [-Dokad] -> `Spakuj-Skille` (tylko lista Wlasne, bez sieci
  i bez Wykryj): `Szukaj-Wrazliwych` (tablica `$WRAZLIWE` + `Czy-Niewinne`; plik binarny = znalezisko;
  jedna linia = jedno znalezisko; fragment pokazywany tylko dla IP/maila/loginu) -> odmowa = BLAD z plikiem
  i linia; inaczej ZIP (`ZipArchive`, wpisy `<folder>/...` + `JAK-ZAINSTALOWAC.txt` UTF-8 z BOM, zapis przez
  `.tmp` i sprawdzenie wpisow/rozmiarow) na Pulpit (`GetFolderPath('Desktop')` tylko dla prawdziwego domu),
  `$DomDesktop` albo `$DomDownloads`; sciezka w wydruku i w `operacja.txt` (`paczka:`). `Stan-Dla-Okna`:
  `spozaBazy[]` z `rodzaj` wlasny/inne/nieznane, opis, skad, uwaga, `opisAutora` (z SKILL.md, `Opis-Z-SkillMd`),
  sciezka, dowiazanie; liczniki `wlasne`, `nieznane`. PULAPKA: „ i ” w stringu "..." PowerShell bierze za
  cudzyslow - pisac `„...`”.
- Stan poza repo: `~\.claude\mr\skille\` - `stan.json` (per skill per cel), `znacznik.txt` (codzienny
  przebieg), `dziennik.log`, `operacja.txt` + `operacja.log` (dla okna), `kopie\<folder>\<stempel>\<cel>\`
  (limit 10 na skill), `repo\<id>\`, `tmp\`.
- Cele: `claude` = `~\.claude\skills` (zawsze); `codex` = `~\.agents\skills`, gdy jest `~\.codex` albo
  Codex Orki (`$HOME` Codex bierze z profilu Windows - na kopii domu tego nie sprawdzisz). opencode
  czyta oba katalogi sam. Skill z `allow_implicit_invocation: false` (np. `retro`) Codex pomija
  w promcie - to nie blad.
- Reguly: pierwszy `codziennie` na maszynie tylko spisuje; aktualizacja tylko skilli pod opieka
  w stanie `starszy`; `zmieniony` nigdy bez `-Wymus` (okno pyta); po `cofnij` skill `wstrzymany`;
  skill `usuniety` przez autora - bez aktualizacji, kopia u uzytkownika nietknieta.
- Codziennie: dozor (`dozor.ps1`) -> `Czy-Sprawdzac-Skille` (znacznik z dzis? inna operacja? dlawik
  120 min) -> `Ruszaj-Skille` -> `Odpal-Skille` / `Odpal-W-Tle` (conhost --headless); funkcje
  w `zasobnik/nadzorca/stan-skille.ps1` (`Stan-Skilli`, `Operacja-Na-Skillach`, `Problemy-Skilli` -
  karta na Przegladzie). Bez zadania w Harmonogramie.
- Zakladka (`zasobnik/nadzorca/skille.ps1`): wiersze `TableLayoutPanel` w przewijanym panelu (opis
  zawiniety - ListView ucinal). Grupy zwijane: `Grupa-Zrodla` + `Liczby-Grupy` -> `Naglowek-Grupy`
  (pasek `$script:ZnacznikiGrup`: czerwony = problem, bursztyn = nowsza), klik -> `Przelacz-Grupe` ->
  `Napelnij-Skille $false $true`; rozwiniete w `$script:GrupySkilli`. Spoza bazy (P49, `Skille-Spoza`):
  grupy `__wlasne`, `__inne`, `__nieznane`, wiersze przez `Wiersz-Skilla` z nazwa `__spoza:<folder>`
  (`Znajdz-Skill` zwraca `@($s, $null)`, `$s.spoza`); przyciski `$script:BSkillSpakuj` / `BSkillSpakujWszystkie`
  (okno.ps1, zmienne w wyglad.ps1) widac tylko przy "Twoj wlasny" - wtedy cztery zwykle sa ukryte.
  Test okna P49: scratchpad 1ca517cc `p49	est-okno.ps1` + `scenariusz-p49.ps1` (wzor P43).
  `$script:BSkillUsun` ("Usun u mnie") w miejscu "Aktualizuj teraz". Dalej `Wiersz-Skilla`,
  `Pokaz-Info-Skilla`, `Podglad-Skilla`, `Wybierz-Skill`, `Rusz-Operacje-Skilli` +
  `Sprawdz-Operacje-Skilli` (zegar 2 s na `operacja.txt`).

## Codex i Orca - najwazniejsze (rozpoznania w archiwum)

- Codex 0.157 na biurowej: `C:\Users\<uzytkownik>\.codex\packages\standalone\` (+ npm w `C:\dev\tools\node\`);
  `~\.codex\AGENTS.md` pisze straznik (blok Lore + kierownik w wariancie opencode/Codex; "Co wiem"
  do Codeksa NIE trafia). Rol `~\.codex\agents` i hookow `~\.codex\hooks.json` tu nie ma (instalator
  zaklada je tylko z `-Codex` albo gdy juz sa). Zywe logowanie trzyma Orka
  (`...\orca\codex-runtime-home\home\auth.json`). Co Codex dostaje na start, bez logowania:
  `codex debug prompt-input` (z `CODEX_HOME=<kat>`).
- Hook na Windows Codex odpala przez `powershell.exe -NoProfile -Command "<commandWindows>"`:
  `$zmienna` rozwija opakowanie (przypisania psuja hook), `||` nie dziala (PS 5.1). Bezpiecznie:
  `node "<skrypt>" "<arg>"` albo `powershell ... -File "<skrypt>"` - bez `$`. Codex bez konsoli daje
  hookowi widoczne okno (nie da sie schowac z `hooks.json`; pomiary `raporty/P11.md`).
- Zaufanie hookow (`trusted_hash` w `config.toml`) liczone WYLACZNIE z definicji hooka (zdarzenie,
  matcher, command, timeout, async...) - edycja skryptu nie kasuje zaufania; `timeout` podawac jawnie.
- Orka przy starcie Codeksa przenosi z `~\.codex` do swojego CODEX_HOME `AGENTS.md`, skills, hooks
  (katalog), plugins itp. - NIE `hooks.json`, `agents\`, `config.toml`, wiec zasady tylko do
  `~\.codex\AGENTS.md`; plik, ktorego Orka sama nie zalozyla, blokuje kopiowanie na zawsze. Orca
  orkiestruje procesy i stan (`orca orchestration ...`: Run/Task/Dispatch), MegaRuchacz - zachowanie;
  w repo dla Orki jest tylko `narzedzia/orca-ustawienia.js`.
- Subagenci Codeksa: watek glowny CZEKA na wyniki (brak odpowiednika `run_in_background`), brak
  `SendMessage` do kierownika, ograniczanie tylko `sandbox_mode = "read-only"`, worktree to funkcja
  watku, nie subagenta.

## Transkrypty i koszt tokenow (pomiary)

- `~\.claude\projects\<projekt>\<sesja>.jsonl` (rozmowa glowna), `...\<sesja>\subagents\agent-<id>.jsonl`
  + `agent-<id>.meta.json` (`agentType`, `description`, `model` - typ podagenta jest TAM). Wywolanie =
  unikalne `message.id` z `message.usage` (odpowiedz bywa w kilku liniach; `output_tokens` = MAX),
  pomijac `<synthetic>` i `cc-proxy` (`msg_ccproxy`). Kontekst = input + cache_creation + cache_read.
  Ta sama sesja bywa w DWOCH katalogach projektu. Czasy w UTC. Wstrzykniecia hookow: linie
  `type:"attachment"`, `attachment.type = "hook_additional_context"`. Transkryptow Codeksa na biurowej nie ma.
- Bufor: Claude Code pisze 1-godzinny (zapis 2x wejscie, odczyt 0.1x; Opus 5.5 0.05x); peka po
  przerwie > 60 min, zmianie modelu, kompaktowaniu; od 14.09 nowa rozmowa zwykle zapisuje caly
  kontekst od nowa. Tekst z UserPromptSubmit bufora nie psuje, ale zostaje w historii. ~10 wywolan
  modelu na wiadomosc uzytkownika. Codex: odczyt 0.1x, bufor 30 min.
- Dodatki MCP (P23, P30, P32; liczby w `raporty/P23-dodatki-liczby.md`): od 14.09 narzedzia MCP nie sa
  odkladane (ostatni `deferred_tools_delta` 11.09) - 108,5-122,7 tys. tokenow na KAZDE wywolanie
  rozmowy glownej i podagenta z pelnym zestawem (general-purpose, Explore, Plan...; role MegaRuchacza
  bez MCP startuja z 10-41 tys.); w cenniku API 17-20% kosztu. Ruch idzie przez proxy
  `ANTHROPIC_BASE_URL` (<ADRES-PROXY>); z `ENABLE_TOOL_SEARCH=true` odkladanie przez to proxy
  DZIALA (sprawdzone `claude -p`: ToolSearch `select:` -> `tool_reference` -> uzycie; kontekst ~50 zamiast
  ~141 tys.) - wlaczenie po stronie admina proxy. PULAPKA pomiaru `claude -p`: mierz od 2. odpowiedzi
  (serwery MCP dolaczaja po `system/init`). Podproces `claude -p` z Basha workera nie znajduje Git
  Basha (hook straznika pada) - bez wplywu na liczby.
