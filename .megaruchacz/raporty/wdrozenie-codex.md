# Wdrozenie trybu workerow dla Codeksa w `wdroz.ps1`

## Co powstalo

- `narzedzia/mr-log-codex.js` — hook `SubagentStart`/`SubagentStop`. Czyta zdarzenie ze
  stdin (`agent_id`, `agent_type`, `permission_mode`), dopisuje `START`/`KONIEC` do
  `<projekt>/.megaruchacz/worklog.md` (katalog tworzy sam). `start` nic nie wypisuje
  (wyjscie `SubagentStart` idzie do podagenta jako kontekst), `stop` zwraca
  `{"continue":true}`.
- `szablony-codex/przypomnienie.json` — ladunek `UserPromptSubmit`, kopiowany doslownie,
  odpowiednik `.claude/orchestrator-reminder.json`.
- `.megaruchacz/zasady-sesja.json` — sklada instalator node'em. Wariant **krotki**, gdy
  pelne zasady weszly do `AGENTS.md`; **pelny** (13,1 tys. znakow, ~4,4 tys. tokenow,
  limit w `hooks.json` to 8000), gdy `AGENTS.md` nie dalo sie ruszyc.
- `wdroz.ps1`, czesc „4b. Codex CLI”: role `.codex/agents/*.toml`, zasady do `AGENTS.md`
  miedzy znaczniki `MegaRuchacz:start/koniec`, `.megaruchacz/` (worklog, mapa, zasady,
  ladunki, `wersja.txt`), `.codex/hooks.json` z podstawionymi `{{PROJEKT}}`/`{{ZRODLO}}`.

## Decyzje, ktorych zlecenie nie rozstrzygalo

1. **`AGENTS.md` a zakaz ruszania sledzonych plikow.** `CZYTAJ.md` kaze polozyc tam
   zasady, a skrypt obiecuje nie dotykac sledzonych plikow repozytorium. Rozstrzygniete
   tak: pliku nie ma → tworzymy; jest nasz blok → podmieniamy (po kopii zapasowej); jest
   cudzy i **niesledzony** → dopisujemy blok na koncu (po kopii); jest cudzy i **sledzony
   w gicie albo nieczytelny jako UTF-8** → NIE RUSZAMY, mowimy o tym wprost, a zasady ida
   pelnym ladunkiem hooka. Sprawdzenie przez `git ls-files --error-unmatch`.
2. **`hooks.json` scalany, nie nadpisywany.** Zlecenie mowilo „kopiuj”, ale to skasowaloby
   cudze hooki. Node dokłada tylko brakujace grupy, poznajac swoje po `statusMessage`
   (bez cudzyslowow — po `JSON.stringify` porownanie calego polecenia nigdy by nie trafilo).
   Kody wyjscia jak przy `settings.json`: 0 dopisane, 3 cudzy plik nie jest JSON-em,
   4 wszystko juz bylo.
3. **Wykrywanie Codeksa:** `codex` w PATH **albo** istniejacy `$CODEX_HOME` / `~/.codex`.
   Na tej maszynie nie ma ani jednego, stad przelacznik `-WymusCodex` do testow.
4. **Pliki stanu `.megaruchacz/`** powstaja puste (naglowek + zdanie dla scouta), a nie
   przez kopiowanie `.claude/worklog.md` i `mapa.md` ze zrodla — tamte zawieraja zywy stan
   repozytorium MegaRuchacza i w cudzym projekcie nie maja czego szukac.
5. **Wersja:** `.megaruchacz/wersja.txt` (format „klucz: wartosc”, ten sam, ktory czyta
   `Czytaj-Klucze` straznika) plus klucze `codex.wersja` / `codex.data` w istniejacym
   `.claude/megaruchacz-wersja.txt`. Straznik zachowuje nieznane klucze przy zapisie,
   wiec nic nie ginie.
6. **`.mr-okna` (panel nadzoru) celowo pominiete** — `mr-log-codex.js` prowadzi sam
   rejestr, tak jak mowilo zlecenie. Workerzy Codeksa nie beda widoczni w panelu.

## Czego to NIE robi

- **Straznik zasad nie odswieza czesci codeksowej.** `Nanies-Poprawki` w
  `narzedzia/straznik-zasad.ps1` zna tylko `.claude/`, a tego pliku nie wolno mi bylo
  ruszac. Nowsza wersje plikow Codeksa nanosi dzis wylacznie ponowne uruchomienie
  `wdroz.ps1`. Instalator mowi o tym przez `Nie-Sprawdzono`. **To jest naturalne
  nastepne zadanie.**
- Rejestr modulow (`Rejestr-Modulow` w strazniku) nadal zna tylko `workerzy` i `pamiec` —
  czesc codeksowa jedzie w module `workerzy`, bez wlasnego wpisu.

## Co sprawdzono uruchomieniem, a co nie

Sprawdzone naprawde (node):

- `mr-log-codex.js start|stop` na katalogu probnym — linie `START`/`KONIEC` w
  `.megaruchacz/worklog.md`, `stop` zwraca `{"continue":true}`.
- Oba ladunki node'a wyjete z `wdroz.ps1` i uruchomione na probnym projekcie: powstaje
  poprawny `zasady-sesja.json` (`hookSpecificOutput.additionalContext`), a scalanie
  `hooks.json` jest idempotentne (drugi przebieg: kod 4, „juz jest”).
- Regula wyciagania sciezek z `hooks.json` (ta sama, co w samosprawdzeniu) — znajduje trzy
  sciezki i poprawnie melduje brak nieistniejacego pliku.
- `szablony-codex/hooks.json` i `przypomnienie.json` parsuja sie jako JSON.
- Rownowaga nawiasow w `wdroz.ps1` — wlasnym zgrubnym kontrolerem (pomija komentarze,
  napisy i here-stringi).

NIE sprawdzone:

- **Skladnia `wdroz.ps1` tokenizerem PowerShella i caly przebieg instalatora** — w kopii
  roboczej narzedzie odmawia uruchomienia powershella („Refusing to run it”).
- **Pliki `*.toml` nie przeszly przez prawdziwy parser TOML-a** — na maszynie nie ma
  Pythona (`tomllib`) ani biblioteki TOML dla node'a. Sprawdzone strukturalnie: `name`,
  `description`, `developer_instructions` i domkniete `'''` (zmiana dotyczyla wylacznie
  komentarza w pierwszej linii — znacznik `kierownik-template`).
- Czy hooki Codeksa faktycznie wystartuja — wymaga zatwierdzenia przez czlowieka
  poleceniem `/hooks`, i po kazdej zmienionej definicji od nowa.
