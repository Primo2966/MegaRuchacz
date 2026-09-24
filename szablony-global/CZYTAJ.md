# Szablony instalacji GLOBALNEJ

Tu leży treść, którą wdraża `narzedzia\instaluj-globalnie.ps1` — jedna instalacja
na cały komputer, dla wszystkich projektów i wszystkich trzech narzędzi naraz.

## Co gdzie trafia

- `claude/agents/*.md` → `~/.claude/agents/`. Role dla Claude Code. To samo co
  `.claude/agents/*.md` w wdrożeniu per projekt, ale stan pracy w `.megaruchacz/`
  (wspólny dla Claude Code, Codeksa i opencode), a nie w `.claude/`.
- `claude/mr-log.js` → `~/.claude/megaruchacz-mr-log.js`. Rejestr workerów Claude
  Code; pisze do `<projekt>/.megaruchacz/worklog.md` i do `~/.claude/mr-okna/`
  (panel nadzoru). Hooki `SubagentStart`/`Stop` w `~/.claude/settings.json` wołają go.
- `../.claude/orchestrator-reminder.json` → `~/.claude/mr/orchestrator-reminder.json`,
  ładunek przypomnienia; hook `UserPromptSubmit` woła `narzedzia/przypomnienie.js`
  (awaryjnie `|| cat` tego pliku).
- Komplet hooków w `~/.claude/settings.json` (strażnik na `SessionStart`,
  przypomnienie, jeden rejestr) układa i naprawia `narzedzia/straznik-zasad.ps1`
  (`-NaprawGlobalne` z instalatora, a potem sam przy każdym starcie sesji). Przy
  okazji zdejmuje z projektów stare hooki projektowe MegaRuchacza, które dublowały
  globalne (wyjątek: projekt wdrożony `wdroz.ps1 -WymusProjektowo`).
- Zasady (`../szablony-opencode/zasady-kierownika.md`) → blok
  `MegaRuchacz:kierownik` w `~/.claude/CLAUDE.md` i `~/.codex/AGENTS.md`.
- Role opencode i Codeksa instalator bierze z `../szablony-opencode/agents/`
  i `../szablony-codex/agents/` — nie ma tu ich kopii, żeby się nie rozjechały.

## Znaczniki

- Blok zasad: `<!-- MegaRuchacz:kierownik:start -->` … `<!-- MegaRuchacz:kierownik:koniec -->`
  (inny niż blok wiedzy z `wpisz-zasady.ps1`, żeby się nie nadpisywały).
- Znacznik instalacji: `~/.claude/.megaruchacz-global` (z polem `zrodlo:`).
  `wdroz.ps1` go widzi i nie wdraża nic per projekt; strażnik po nim poznaje,
  że ma pilnować hooków globalnych.

## Dlaczego stan w projekcie, a nie globalnie

Rejestr zadań i mapa projektu są z natury projektowe — każdy projekt ma swoje.
Trzymanie ich globalnie (wspólny plik dla wszystkich) pomieszałoby zadania z różnych
repozytoriów. Dlatego instalacja globalna daje wspólne **role i zasady**, a stan
zostawia w `.megaruchacz/` każdego projektu, zakładany leniwie.
