# Szablony trybu workerow dla Codex CLI

Odpowiednik modulu `workerzy` z Claude Code. Tu lezy sama TRESC - wdraza to
`wdroz.ps1` (czesc "4b. Codex CLI"), gdy widzi Codeksa na maszynie.

## Co gdzie ma trafic

- `agents/*.toml` -> `<projekt>/.codex/agents/`. Nazwa agenta z pola `name`, nie z nazwy pliku.
  Swoje pliki instalator rozpoznaje po znaczniku `kierownik-template` w pierwszej linii.
- `zasady-kierownika.md` -> `<projekt>/AGENTS.md`, miedzy znaczniki
  `<!-- MegaRuchacz:start -->` i `<!-- MegaRuchacz:koniec -->` (Codex czyta max 32 KiB
  na plik). Kopia robocza laduje w `<projekt>/.megaruchacz/zasady-kierownika.md`.
  Gdy `AGENTS.md` jest sledzony w gicie, instalator go NIE RUSZA - wtedy zasady ida
  pelnym ladunkiem hooka `SessionStart`.
- `przypomnienie.json` -> `<projekt>/.megaruchacz/przypomnienie.json` (ladunek
  `UserPromptSubmit`, kopiowany doslownie).
- `hooks.json` -> `<projekt>/.codex/hooks.json`. Instalator DOKLADA swoje grupy, nie
  nadpisuje cudzych; swoje poznaje po `statusMessage`. Dlatego KAZDY hook siedzi we
  wlasnej grupie z wlasnym `statusMessage` - drugi hook dolozony do istniejacej grupy
  nigdy by nie doszedl tam, gdzie ta grupa juz stoi (znacznik brany jest z `hooks[0]`).
- `SessionStart` ma TRZY grupy: zasady kierownika (ladunek `additionalContext`),
  rachunek za pamiec agenta - `straznik-zasad.ps1 -KosztCodex` - i samoaktualizacje
  narzedzia - `straznik-zasad.ps1 -Tlo`. Ta ostatnia nie dopisuje
  do rozmowy ani slowa (brak `additionalContextLimit`, tryb `-Tlo` nic nie wypisuje;
  slad zostaje w `~\.claude\.megaruchacz-tlo.log`) i ma `async: true`, wiec start
  sesji na nia nie czeka. `timeout` 300 s jest wiekszy niz wlasne limity straznika
  na gita (30 s na polecenie, 60 s na `fetch`) - o przerwaniu ma decydowac straznik,
  a nie Codex w polowie operacji na repozytorium.
- Rachunek za pamiec musi byc OSOBNA grupa, a nie dopiskiem do ktorejkolwiek
  z tamtych. Hook w tle celowo milczy do modelu, a ladunek z zasadami
  (`.megaruchacz\zasady-sesja.json`) jest statyczny - koszt zmienia sie co dzien,
  wiec trzeba by go przegenerowywac przy kazdym starcie. `-KosztCodex` niczego nie
  liczy: czyta gotowa linie z `~\.claude\.megaruchacz-koszt.txt`, ktora odswieza
  hook `-Tlo`. Gdy liczby nie ma albo jest starsza niz 30 h, linia mowi to wprost.
  Ucinanie idzie na POCZATEK linii, slowem `UWAGA` - alarm schowany w srodku zdania
  jest alarmem, ktorego nikt nie widzi. `additionalContextLimit` 1000 to z okladem
  dwa razy tyle, ile ma najdluzszy wariant tej linii (alarm + adnotacja o dacie).
- **`timeout` w kazdym hooku podajemy JAWNIE i tak ma zostac.** Skrot zaufania Codex
  liczy z definicji hooka juz po normalizacji, wiec wartosc domyslna tez do niego
  wchodzi - gdyby zmienila sie w nowszej wersji Codeksa, zatwierdzenie uzytkownika
  przestaloby pasowac. Jawna liczba trzyma skrot stabilny.
- Znaczniki: `{{PROJEKT}}` - korzen projektu, `{{ZRODLO}}` - korzen repo MegaRuchacza;
  oba bezwzglednie, ukosniki w przod.
- Rejestr i mapa celowo w `<projekt>/.megaruchacz/`, NIE w `.codex/` - piaskownica
  trzyma `.codex/` rekurencyjnie tylko do odczytu, wiec hook nic by tam nie dopisal.
- `.megaruchacz/zasady-sesja.json` skladaja instalator i straznik (ta sama tresc w dwoch
  miejscach - poprawiac razem): `hookSpecificOutput.additionalContext`,
  krotkie, gdy pelne zasady sa juz w `AGENTS.md`, a pelne, gdy ich tam nie ma
  (`additionalContextLimit` w `hooks.json` podniesiony do 8000).
- `narzedzia/mr-log-codex.js` - skrypt dla `SubagentStart`/`SubagentStop`, dopisuje
  START i KONIEC workera do `<projekt>/.megaruchacz/worklog.md`.
- `SubagentStart` przyjmuje `matcher` po `agent_type` - tu celowo go nie ma.

## Co odswieza straznik, a czego nie rusza

Straznik (`narzedzia\straznik-zasad.ps1`, funkcja `Nanies-Poprawki`) nanosi poprawki
takze na czesc codeksowa - na tych samych zasadach co na `.claude\`: zmiana trzeciej
cyfry wersji wchodzi sama. Obejmuje `.codex\agents\*.toml`, `.megaruchacz\zasady-kierownika.md`,
`.megaruchacz\przypomnienie.json`, ladunek `.megaruchacz\zasady-sesja.json` i blok
zasad w `AGENTS.md` (tylko miedzy znacznikami; gdy ich nie ma - nie rusza pliku).

`.codex\hooks.json` to wyjatek. Tresc skryptu wskazanego przez hook mozna poprawiac
do woli, ale zmiana samej DEFINICJI (linia wywolania, `timeout`, `matcher`, `async`)
kasuje zatwierdzenie uzytkownika. Dlatego straznik grup, ktore juz tam stoja, NIE
RUSZA w ogole - dopisuje wylacznie brakujace i za kazdym razem mowi jedna linia,
ze trzeba powtorzyc `/hooks`. Nigdy po cichu.

## Czego jeszcze nie ma

- Rejestr okien `.mr-okna` (panel nadzoru) prowadzi tylko `mr-log.js` z Claude Code;
  workerzy Codeksa go nie zasilaja.

## Czego tryb workerow pod Codeksem NIE POTRAFI

1. **Pracy w tle nie ma.** Watek glowny czeka na wszystkich podagentow i dopiero wtedy
   odpowiada; uzytkownik czeka razem z nim. Dlatego zasady kaza rozdawac cala runde naraz.
2. **Izolacji przez worktree nie ma.** Podagent dziedziczy katalog rodzica - rozlacznosc
   plikow pilnuje wylacznie tresc zlecenia i rejestr.
3. **Worker nie zapyta w trakcie pracy.** Brak odpowiednika `SendMessage`: konczy
   raportem `WYMAGA DECYZJI`, a kierownik puszcza go drugi raz.

`sandbox_mode = "read-only"` blokuje ZAPIS, nie pojedyncze narzedzia - dlatego scout
nie dopisze do mapy sam, tylko oddaje blok "Do mapy". Nadpisania rodzica
(`/permissions`, `--yolo`) biora gore nad plikiem agenta.

**Hooki wymagaja zgody uzytkownika - jednej, nie za kazdym razem:** hook niezarzadzany
nie ruszy, dopoki uzytkownik nie zatwierdzi go poleceniem `/hooks`. Skrot (`hook_hash`
w `codex-rs/hooks`, po `NormalizedHookIdentity`) liczy sie WYLACZNIE z definicji hooka:
zdarzenie, `matcher`, `command`, `timeout`, `async`. Tresc skryptu wskazanego przez
`command` do skrotu NIE wchodzi - sprawdzone 2026-09-17 w zrodlach Codeksa i potwierdzone
odtworzeniem trzech zapisanych wartosci `trusted_hash`. Czyli nasze pozniejsze poprawki
w skryptach zaufania nie uniewazniaja, aktualizacja samego Codeksa tez nie (zatwierdzenie
lezy w jego `config.toml`). Ponownego zatwierdzenia wymaga wylacznie zmiana samej linii
wywolania, `timeout`, `matcher` albo `async`.
