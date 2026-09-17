# Szablony trybu workerow dla Codex CLI

Odpowiednik modulu `workerzy` (dzis tylko Claude Code). Tu lezy sama TRESC -
wpiecie w `wdroz.ps1` to osobne, jeszcze niezrobione zadanie.

## Co gdzie ma trafic

- `agents/*.toml` -> `<projekt>/.codex/agents/`. Nazwa agenta z pola `name`, nie z nazwy pliku.
- `zasady-kierownika.md` -> `<projekt>/AGENTS.md` (Codex czyta max 32 KiB na plik).
- `hooks.json` -> `<projekt>/.codex/hooks.json`.
- Znaczniki: `{{PROJEKT}}` - korzen projektu, `{{ZRODLO}}` - korzen repo MegaRuchacza;
  oba bezwzglednie, ukosniki w przod.
- Rejestr i mapa celowo w `<projekt>/.megaruchacz/`, NIE w `.codex/` - piaskownica
  trzyma `.codex/` rekurencyjnie tylko do odczytu, wiec hook nic by tam nie dopisal.

## Czego jeszcze nie ma

- `narzedzia/mr-log-codex.js` - skrypt dla `SubagentStart`/`SubagentStop`
  (odpowiednik `.claude/mr-log.js`). NIE ISTNIEJE; bez niego rejestr milczy.
- `.megaruchacz/zasady-sesja.json` i `.megaruchacz/przypomnienie.json` - ladunki
  `hookSpecificOutput.additionalContext`, do wygenerowania przez instalator. Domyslny
  `additionalContextLimit` to ~2500 tokenow, wiec pelne zasady jada przez `AGENTS.md`.
- `SubagentStart` przyjmuje `matcher` po `agent_type` - tu celowo go nie ma.

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

**Hooki wymagaja zgody uzytkownika:** hook niezarzadzany nie ruszy, dopoki uzytkownik
nie zatwierdzi go poleceniem `/hooks`. Codex liczy hash definicji - kazda zmiana
komendy albo skryptu kasuje zaufanie i trzeba zatwierdzic od nowa.
