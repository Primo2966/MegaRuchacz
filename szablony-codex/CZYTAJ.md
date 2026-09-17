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
  nadpisuje cudzych; swoje poznaje po `statusMessage`.
- **`timeout` w kazdym hooku podajemy JAWNIE i tak ma zostac.** Skrot zaufania Codex
  liczy z definicji hooka juz po normalizacji, wiec wartosc domyslna tez do niego
  wchodzi - gdyby zmienila sie w nowszej wersji Codeksa, zatwierdzenie uzytkownika
  przestaloby pasowac. Jawna liczba trzyma skrot stabilny.
- Znaczniki: `{{PROJEKT}}` - korzen projektu, `{{ZRODLO}}` - korzen repo MegaRuchacza;
  oba bezwzglednie, ukosniki w przod.
- Rejestr i mapa celowo w `<projekt>/.megaruchacz/`, NIE w `.codex/` - piaskownica
  trzyma `.codex/` rekurencyjnie tylko do odczytu, wiec hook nic by tam nie dopisal.
- `.megaruchacz/zasady-sesja.json` sklada instalator: `hookSpecificOutput.additionalContext`,
  krotkie, gdy pelne zasady sa juz w `AGENTS.md`, a pelne, gdy ich tam nie ma
  (`additionalContextLimit` w `hooks.json` podniesiony do 8000).
- `narzedzia/mr-log-codex.js` - skrypt dla `SubagentStart`/`SubagentStop`, dopisuje
  START i KONIEC workera do `<projekt>/.megaruchacz/worklog.md`.
- `SubagentStart` przyjmuje `matcher` po `agent_type` - tu celowo go nie ma.

## Czego jeszcze nie ma

- Straznik zasad NIE odswieza czesci codeksowej - nowsza wersje tych plikow nanosi
  dopiero ponowne uruchomienie `wdroz.ps1`.
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
