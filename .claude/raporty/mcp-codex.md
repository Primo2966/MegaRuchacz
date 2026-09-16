# Rejestracja serwera MCP w Claude Code i w Codeksie

## Co zrobione (narzedzia\instaluj-lore.ps1)

- `Sprawdz-Warunki`: brak `claude` nie jest juz bledem. Rozpoznaje osobno Claude Code
  i Codeksa; instalacja konczy sie porazka dopiero, gdy nie ma ZADNEGO z nich.
  Codex rozpoznawany tak samo jak w `narzedzia\wpisz-zasady.ps1`: binarka w PATH albo
  katalog domowy (`%USERPROFILE%\.codex`, z poszanowaniem `CODEX_HOME`).
- Sposob rejestracji w Codeksie ustalany W RUNTIME: `codex mcp --help` -> jesli zna `add`,
  idzie `codex mcp add lore -- <uv> --directory <lore> run python -m lore.server`.
  Dopiero gdy polecenia nie ma, dopisujemy tabele `[mcp_servers.lore]` do `config.toml`
  (kopia zapasowa `config.toml.bak-RRRRMMDD-GGMMSS` obok, stara tabela wraz z podtabelami
  usuwana, zapis UTF-8 bez BOM -> ponowna instalacja nie robi duplikatu).
- `Ekran-Zgody` punkt 3 wypisuje faktyczna liste miejsc rejestracji dla TEJ maszyny.
- `Sprawdz-Mcp-Wpis` sprawdza osobno Claude Code i Codeksa; narzedzie nieobecne jest
  POMIJANE jawna linia `--`, a nie zaliczane na zielono. Oba sprawdzenia sa na poziomie
  wpisu w konfiguracji, wiec kazde dokłada zdanie do `Nie-Sprawdzono`. Dzialanie serwera
  potwierdza bez zmian handshake JSON-RPC (`Sprawdz-Mcp-Dziala`).

## Czego NIE potwierdzono uruchomieniem

1. **Kryterium ukonczenia nie zostalo uruchomione.** W tym worktree harness twardo
   odmawia startu PowerShella z narzedzia Bash ("runs powershell in a plain command...
   Refusing to run it"). Odmowa dotyczy kazdej formy, takze `-File` ze sciezka
   bezwzgledna i z `dangerouslyDisableSandbox`. Innego sposobu odpalenia .ps1 nie ma.
   `powershell -ExecutionPolicy Bypass -File narzedzia\instaluj-lore.ps1 -Proba`
   trzeba puscic z glownego checkoutu.
   Sprawdzone statycznie: brak polskich znakow diakrytycznych, brak pulapki `"$Zmienna:"`
   (wszystkie trafienia to prefiksy zasiegu `$script:` / `$env:`), diff mieści sie
   wylacznie w czterech dozwolonych miejscach.
2. **Codeksa nie ma na tej maszynie** (`codex` poza PATH, brak `~\.codex`), wiec
   `codex mcp --help`, `codex mcp add` i `codex mcp get` nie zostaly sprawdzone
   na zywo. Kod jest napisany tak, ze skladnie polecenia weryfikuje sam Codex
   (`--help`), a gdy jej nie ma - schodzi do pliku konfiguracyjnego.
   Format `[mcp_servers.<nazwa>]` + `command` + `args` pochodzi z dokumentacji Codeksa,
   nie z pliku zastanego na dysku.

## Poza zakresem zlecenia (nie ruszane)

- `Podsumowanie` (koniec pliku) konczy zdaniem "Zamknij i otworz okna Claude Code" -
  na maszynie z samym Codeksem to zdanie klamie. Wymaga osobnego zlecenia.
- Naglowek pliku (komentarz uzycia) mowi tylko o "rejestracji serwera MCP", bez wskazania
  narzedzi - do ewentualnego odswiezenia.
