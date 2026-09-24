# Mapa projektu

Co gdzie lezy. Uzupelniaja to raporty scouta - kierownik czyta stad, zanim
wysle kogokolwiek na rozpoznanie.

<!-- przyklad:
## Autoryzacja
- src/auth/session.ts - tworzenie i walidacja sesji
- src/auth/login.ts   - endpoint logowania
-->

## Aktualizacja wdrozen (mechanizm wersji)

Numerow linii tu nie ma z premedytacja - rozjezdzaly sie przy kazdej zmianie
i dwa razy wprowadzily w blad. Funkcje szukaj po nazwie (`grep -n "^function "`).

- `narzedzia/straznik-zasad.ps1` - straznik wolany hookiem `SessionStart`. Pod Claude Code
  zwykly przebieg (wpis w `.claude/settings.json`), pod Codeksem przebieg `-Tlo`
  (grupa w `.codex/hooks.json`, `async`, nic nie wstrzykuje do rozmowy - slad idzie
  do dziennika `~/.claude/.megaruchacz-tlo.log`). Funkcje: `Rejestr-Modulow` (moduly
  `workerzy` i `pamiec`, pola `pytaj`/`instalator`/`aktualizacja`), `Odswiez-Zrodlo`
  (pobranie nowszej wersji samego narzedzia - patrz nizej), `Pilnuj-Zasad` (blok zasad
  w `~/.claude/CLAUDE.md` ORAZ w `~/.codex/AGENTS.md`, gdy katalog Codeksa istnieje),
  `Pilnuj-Wersji` (porownanie wersji), `Nanies-Poprawki` (kopiuje pliki ze zrodla do
  `.claude/` projektu), `Nanies-Poprawki-Codex` (`.codex/agents/`, `.megaruchacz/*`,
  blok w `AGENTS.md`, ladunki hookow), `Napraw-Hooki` i `Napraw-Hooki-Codex` (dokladaja
  wylacznie BRAKUJACE hooki), `Pilnuj-Sufitu-Zawsze` (sufit ladunku przy kazdym przebiegu),
  `Zglos-Koszt` / `Wypisz-Koszt-Codex` (rachunek za pamiec agenta).
- Porownanie wersji: najwyzszy naglowek `## X.Y.Z` w `ZMIANY.md` zrodla (`Wersja-Narzedzia`)
  kontra klucz `modul.<nazwa>.wersja` w `.claude/megaruchacz-wersja.txt` projektu.
- Regula: patch -> `Nanies-Poprawki` sam; minor -> pliki wchodza, nowa funkcja tylko
  proponowana; major -> nic, komunikat o recznym `wdroz.ps1`. Modul z `aktualizacja = "instalator"`
  (np. `pamiec`) nigdy nie aktualizuje sie sam - straznik podaje komende.
- Odmowy zapamietywane w pliku wersji: `modul.<x>.status: odrzucony`, `modul.<x>.odrzucone`,
  `modul.<x>.zaproponowane`. Ustawia je `straznik-zasad.ps1 -Odrzuc <modul>`.
- `.claude/megaruchacz-wersja.txt` - zaklada `wdroz.ps1` (sekcja "6. Znacznik wersji"), potem
  przesuwa `Pilnuj-Wersji`; klucze `zrodlo:` (BEZWZGLEDNA sciezka do repo narzedzia), `commit:`,
  `data:`, `modul.*`, a przy wdrozeniu dla Codeksa takze `codex.wersja` / `codex.data`.
  Drugi plik tego samego formatu lezy w `.megaruchacz/wersja.txt` - pisze go `wdroz.ps1`
  i odswieza `Nanies-Poprawki-Codex`.
- Sciezka do repo zrodlowego jest zaszywana bezwzglednie tez w hooku `SessionStart`
  w `settings.json` - generuje to `dodajStraznika()` w `wdroz.ps1` (i `{{ZRODLO}}`
  w `szablony-codex/hooks.json` po stronie Codeksa). Przeniesienie repo psuje hook;
  straznik przy nieistniejacym `-Zrodlo` milczy i konczy zerem.
- `wdroz.ps1` - jedyny instalator; czyta rejestr modulow przez `straznik-zasad.ps1 -Moduly`,
  na koncu robi samosprawdzenie.

### Kto odswieza kopie narzedzia (od 0.13.0)

- Robi to `Odswiez-Zrodlo` w `narzedzia/straznik-zasad.ps1` - PIERWSZY krok kazdego przebiegu
  straznika, przed jakimkolwiek porownywaniem wersji. To jedyne miejsce w repo, ktore siega
  do zdalnej: `git fetch --quiet`, a potem wylacznie `git merge --ff-only @{u}`.
- Kiedy: przy starcie sesji. W przebiegu zwyklym (Claude Code) nie czesciej niz raz na
  60 minut na katalog zrodlowy - znacznik w `~/.claude/.megaruchacz-pobranie.txt`, klucz to
  skrot sciezki, bo dziesiec otwartych okien ma odpytac zdalna raz. W trybie `-Tlo` (hook
  Codeksa) dlawika NIE MA z decyzji uzytkownika: pobranie ma sie dziac przy kazdym starcie sesji.
- Limity czasu: przebieg zwykly 5 s na komende gita i 6 s na `fetch` (caly hook ma 15 s),
  tryb `-Tlo` odpowiednio 30 s i 60 s (nikt tam nie czeka). Zadnych pytan o haslo
  (`GIT_TERMINAL_PROMPT=0`, `credential.interactive=never`).
- Warunki odmowy - kazdy konczy sie cisza albo jedna linia, nigdy sila:
  brak gita w PATH; katalog zrodlowy nie jest repozytorium; NIEZAPISANE ZMIANY w zrodle
  (mowi o tym glosno i zostaje na tym, co jest); galaz bez zdalnej albo odpiety HEAD;
  `fetch` sie nie udal (brak sieci albo dostepu); zdalna nie ma nic nowego; HISTORIA
  ROZJECHANA (sa commity lokalne, ktorych nie ma na zdalnej - mowi glosno, nie scala);
  `merge --ff-only` odrzucony przez gita.
- Zadnego `reset --hard`, `checkout -f`, `clean` ani autostash - cudza praca jest wazniejsza
  niz swiezosc narzedzia. Udane przewiniecie ZAWSZE konczy sie jedna linia o tym,
  co sie zmienilo (stara -> nowa wersja albo liczba zmian).

### Czego tu nie ma

- Nie ma zadania w Harmonogramie Windows aktualizujacego narzedzie. `MegaRuchaczOdswiez`
  istnialo tylko w 0.13.0 - w 0.14.0 zostalo usuniete, a `wdroz.ps1` ZDEJMUJE je z maszyn,
  gdzie zdazylo powstac. Zadania rejestruja dzis tylko: `cykl-dzienny.ps1`, `instaluj-lore.ps1`,
  `wyciagnij-fakty.ps1`, `aktualizuj-wiedze.ps1`, `koszt-pamieci.ps1` - wszystkie dotycza
  Lore/pamieci, nie wersji narzedzia.
- `narzedzia/cykl-dzienny.ps1` nie wola ani `wdroz.ps1`, ani straznika.
- Poza `Odswiez-Zrodlo` git sluzy tylko do odczytu: `git -C $Zrodlo rev-parse --short HEAD`
  (znacznik commitu we `wdroz.ps1`) i `git ls-files` (sprawdzenie, czy plik jest sledzony).

## Codex CLI - hooki, instrukcje, subagenci (rozpoznanie 2026-09-17)

Dokumentacja zrodlowa: repo `openai/codex/docs/*.md` to same odsylacze; tresc jest na
`https://developers.openai.com/codex/<strona>` - **dopisanie `.md` do adresu daje czysty markdown**
(np. `https://developers.openai.com/codex/hooks.md`). Indeks: `https://learn.chatgpt.com/llms.txt`.

- HOOKI ISTNIEJA i maja `SessionStart`. Zdarzenia: `SessionStart`, `SessionEnd`, `UserPromptSubmit`,
  `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `Interrupt`,
  `SubagentStart`, `SubagentStop`, `Stop`. Zrodlo: `developers.openai.com/codex/hooks.md`.
- Lokalizacje hookow: `~/.codex/hooks.json`, `~/.codex/config.toml` (inline `[[hooks.SessionStart]]`),
  `<repo>/.codex/hooks.json`, `<repo>/.codex/config.toml`. Wszystkie pasujace hooki ze wszystkich
  warstw uruchamiaja sie razem - warstwa wyzsza NIE nadpisuje nizszej.
- Format identyczny jak w Claude Code: `hooks` -> zdarzenie -> grupa z `matcher` -> lista
  `{type:"command", command, timeout, statusMessage, additionalContextLimit}`. `timeout` w SEKUNDACH
  (domyslnie 600; `SessionEnd`/`Interrupt` 1 s, max 3 s). `commandWindows` / `command_windows` to
  nadpisanie komendy tylko dla Windows. Handlery `prompt` i `agent` sa parsowane, ale POMIJANE.
- `SessionStart` UMIE wstrzyknac tekst do kontekstu modelu: zwykly tekst na stdout albo JSON
  `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}` - trafia jako
  dodatkowy kontekst developerski. Limit `additionalContextLimit` (domyslnie ~2500 tokenow).
  `matcher` dla tego zdarzenia dziala na `source`: `startup`, `resume`, `clear`, `compact`.
- ZAUFANIE: hook nie-zarzadzany nie ruszy, dopoki nie zostanie zatwierdzony. Codex liczy hash
  definicji; zmiana hooka kasuje zaufanie. Interaktywnie: `/hooks` w CLI. Jednorazowo:
  `--dangerously-bypass-hook-trust`. Bez czlowieka i na stale: hooki ZARZADZANE w
  `requirements.toml` (`[hooks] managed_dir` / `windows_managed_dir`) - te sa zaufane z definicji.
  Sciezka na Windows: `%ProgramData%\OpenAI\Codex\requirements.toml` (wymaga praw administratora),
  zrodlo `learn.chatgpt.com/docs/enterprise/managed-configuration.md`.
- Trwale zaufanie ma tez postac NIEUDOKUMENTOWANEGO klucza w `config.toml`:
  `[hooks.state.'<sciezka-hooks.json>:<zdarzenie_snake>:<idx>:<idx>']` z polami `enabled = true`
  i `trusted_hash = "sha256:..."`. Nie ma tego w oficjalnym `config-reference`. Algorytm liczenia
  hasha USTALONY - patrz sekcja "Odcisk palca zaufania hookow". Zywy przyklad zapisany przez Orke:
  `C:\Users\Primo\AppData\Roaming\orca\codex-runtime-home\home\config.toml`.
- Wylaczenie calosci: `[features] hooks = false` w `config.toml`.
- INSTRUKCJE STALE (odpowiednik CLAUDE.md) to `AGENTS.md`. Kolejnosc: (1) globalny katalog domowy
  Codeksa - `~/.codex` albo `$CODEX_HOME` - najpierw `AGENTS.override.md`, w razie braku `AGENTS.md`
  (tylko jeden plik z tego poziomu); (2) projekt - od korzenia repo w dol do biezacego katalogu,
  w kazdym katalogu `AGENTS.override.md`, potem `AGENTS.md`, potem nazwy z
  `project_doc_fallback_filenames`, najwyzej jeden plik na katalog; (3) sklejane od korzenia w dol -
  pliki blizsze cwd wygrywaja, bo sa dalej w promcie. Limit `project_doc_max_bytes` = 32 KiB.
  Wczytywane raz na sesje. Zrodlo: `developers.openai.com/codex/guides/agents-md.md`.
- SUBAGENCI SA natywnie w Codex CLI, wlaczeni domyslnie; `/agent` przelacza watki. Wlasne definicje
  to pliki TOML w `~/.codex/agents/` (osobiste) albo `<repo>/.codex/agents/` (projektowe), jeden
  agent na plik, wymagane pole `developer_instructions`. Zrodlo: `developers.openai.com/codex/subagents.md`.

### Codex na TEJ maszynie

- Polecenia `codex` nie ma w PATH; katalogu `C:\Users\Primo\.codex\` NIE MA.
- Orca trzyma wlasny CODEX_HOME w `C:\Users\Primo\AppData\Roaming\orca\codex-runtime-home\home\`:
  `hooks.json` (8 zdarzen, kazde wola ten sam skrypt), `config.toml` (`[hooks.state]` z zaufaniem),
  `.orca-hook-trust-provenance.json` (kopia zaufania po stronie Orki), `config.toml.bak`.
- `C:\Users\Primo\.orca\agent-hooks\codex-hook.cmd` - hook Orki dla Codeksa: POST na
  `http://127.0.0.1:%ORCA_AGENT_HOOK_PORT%/hook/codex`, nie zwraca `additionalContext`.
  Obok `claude-hook.cmd` i `claude-statusline.cmd` - analogiczne dla Claude Code.

## Tryb workerow: na czym stoi w Claude Code (inwentarz 2026-09-17)

Bez numerow linii - te same powody co wyzej. Sekcje we `wdroz.ps1` sa ponumerowane
komentarzami ("# 1. Workerzy", "# 4. settings.json" itd.), wiec szukaj po nich.

- `wdroz.ps1`, sekcja "1. Workerzy" - kopiuje `.claude/agents/*.md` (4 role: implementer,
  scout, verifier, zastepca); nadpisuje cudze pliki dopiero po kopii zapasowej,
  rozpoznaje swoje po znaczniku `kierownik-template`.
- `wdroz.ps1`, sekcja "2. Pliki stanu" - `worklog.md` i `mapa.md` tylko gdy ich nie ma.
  Sekcja "3. Zasady + payloady": `CLAUDE.md` zrodla -> `.claude/megaruchacz-zasady.md`,
  plus `orchestrator-reminder.json` i `mr-log.js`, a node sklada
  `.claude/megaruchacz-sesja.json`: JSON z `hookSpecificOutput.additionalContext`
  = cala tresc zasad (ladunek hooka SessionStart).
- `wdroz.ps1`, sekcja "4. settings.json" - pisze `.claude/settings.json`:
  `worktree = {baseRef:"fresh", bgIsolation:"worktree"}` oraz 5 hookow
  (kazdy `shell:"bash"`, timeout 5 s, 15 s dla straznika):
  SessionStart -> `cat megaruchacz-sesja.json` (pelne zasady raz na sesje);
  SessionStart -> `narzedzia/straznik-zasad.ps1` (wersje/poprawki, sciezka bezwzgledna);
  UserPromptSubmit -> `cat orchestrator-reminder.json` (przypomnienie przy kazdym enterze);
  SubagentStart -> `node mr-log.js`; SubagentStop -> `node mr-log.js stop`.
- `wdroz.ps1`, sekcja "4b. Codex CLI" - to samo wdrozenie po stronie Codeksa: role TOML
  do `.codex/agents/`, hooki do `.codex/hooks.json` (szablon `szablony-codex/hooks.json`,
  podstawiane `{{PROJEKT}}` i `{{ZRODLO}}`), zasady do `AGENTS.md` projektu, a rejestr,
  mapa i ladunki hookow do `<projekt>/.megaruchacz/` - bo piaskownica Codeksa trzyma
  `.codex/` rekurencyjnie tylko do odczytu. Start i koniec workera dopisuje
  `narzedzia/mr-log-codex.js`.
- `.claude/mr-log.js` - wolany z SubagentStart/SubagentStop; czyta payload ze stdin (`agent_type`,
  `description`), dopisuje linie START/KONIEC do `.claude/worklog.md` i aktualizuje rejestr okien
  `<rodzic-repo>/.mr-okna/<ID>.json` (pola `aktywni`, `lacznie`, `puls`) dla panelu nadzoru.
  Zwraca `{"suppressOutput":true}`.
- `.claude/agents/*.md` - naglowek YAML: `name`, `description`, `tools` (lista narzedzi po przecinku),
  opcjonalnie `model` (scout/verifier: sonnet) i `effort: high`. Reszta pliku to prompt roli.
  scout ma `tools: Read, Grep, Glob, Bash, Edit` (Edit wylacznie po to, zeby dopisywac do mapy).
- `CLAUDE.md` (korzen) opiera sie na: Agent tool z `run_in_background`, `isolation:"worktree"`
  (twarda blokada zapisu poza worktree), `SendMessage` do `main` (worker pyta i czeka),
  wstrzykiwanie zasad przez SessionStart + UserPromptSubmit, komenda `/batch`.

## Codex a tryb workerow (rozpoznanie 2026-09-17)

- Subagenci Codeksa DZIALAJA ROWNOLEGLE i spawnuje je MODEL, nie czlowiek: `/agent` (alias
  `/subagents`) tylko przelacza watki (`learn.chatgpt.com/docs/developer-commands.md?surface=cli`,
  sekcja "Switch agent threads with /agent"). Wyzwalaczem jest prompt ALBO instrukcja w `AGENTS.md`
  ("Codex can also follow applicable AGENTS.md or skill instructions that request delegation").
  Limit rownoleglosci: `[agents] max_concurrent_threads_per_session` (alias `agents.max_threads`).
  Zrodlo: `developers.openai.com/codex/subagents.md`.
- RoZNICA: "When many agents are running, Codex waits until all requested results are available,
  then returns a consolidated response" - watek glowny CZEKA. Nie ma odpowiednika
  `run_in_background`, ktory oddaje klawiature uzytkownikowi w trakcie pracy workerow.
- Definicja wlasnego agenta: plik TOML, jeden agent na plik, `~/.codex/agents/` (osobiste) lub
  `<repo>/.codex/agents/` (projektowe). Wymagane: `name`, `description`, `developer_instructions`.
  Opcjonalnie dowolne klucze `config.toml`: `model`, `model_reasoning_effort`, `sandbox_mode`,
  `[mcp_servers.*]`, `[[skills.config]]`. Nazwa agenta z pola `name`, nie z nazwy pliku.
  Wbudowani: `default`, `worker`, `explorer` (wlasny o tej samej nazwie wygrywa).
- OGRANICZANIE NARZEDZI: nie ma listy `tools` jak w Claude Code. Jedyny mechanizm to
  `sandbox_mode = "read-only"` w pliku agenta (przyklady `pr_explorer`, `reviewer` w dokumentacji) -
  to blokuje ZAPIS, nie pojedyncze narzedzia. Reszta ustawien dziedziczy sie po rodzicu, a
  interaktywne nadpisania rodzica (`/permissions`, `--yolo`) sa REAPLIKOWANE na dziecko i biora
  gore nad plikiem agenta.
- IZOLACJA: worktree w Codeksie to funkcja WATKU/czatu (desktop: przelacznik "Worktree" pod
  kompozytorem, `learn.chatgpt.com/docs/environments/git-worktrees.md`), nie parametr subagenta.
  W dokumentacji NIE MA ani slowa o worktree dla subagentow - subagent dziedziczy katalog roboczy
  rodzica. Granica zapisu to sandbox: `workspace-write` pozwala pisac w katalogu roboczym, a zapis
  poza nim wymaga ZATWIERDZENIA CZLOWIEKA (nie jest twardo zablokowany);
  `<root>/.git`, `<root>/.agents`, `<root>/.codex` sa rekurencyjnie read-only.
  Zrodlo: `developers.openai.com/codex/sandbox.md`. Przelacznik `codex exec --worktree` NIE
  WYSTEPUJE w zadnej ze stron dokumentacji (sprawdzone: sandbox, subagents, hooks,
  developer-commands, non-interactive-mode, git-worktrees).
- WIADOMOSCI OD WORKERA DO KIEROWNIKA: brak odpowiednika `SendMessage`. Dokumentacja opisuje tylko
  kierunek rodzic->dziecko ("steer a running subagent", `agents.interrupt_message`). Pytanie
  subagenta trafia do CZLOWIEKA jako approval overlay z etykieta watku (klawisz `o`), a w trybie
  nieinteraktywnym akcja po prostu KONCZY SIE BLEDEM zwroconym do rodzica.
- HOOKI dla trybu workerow: `SubagentStart` (matcher po `agent_type`; pola `agent_id`, `agent_type`,
  `permission_mode`; stdout w postaci zwyklego tekstu ALBO `additionalContext` trafia jako dodatkowy
  kontekst deweloperski DO SUBAGENTA - to odpowiednik naszego wstrzykiwania roli),
  `SubagentStop` (oczekuje JSON-a; `continue:false` przerywa), `UserPromptSubmit` (obsluguje
  `additionalContext`, `matcher` ignorowany). Zrodlo: `developers.openai.com/codex/hooks.md`.
- Zywy przyklad zaufania hookow pisanego programowo: Orca wpisuje do `config.toml` KAZDY klucz
  `[hooks.state]` w DWoCH wariantach sciezki - z `\` i z `/` - najwyrazniej nie wiedzac, ktora
  normalizacje Codex porownuje. Nazwy zdarzen w kluczu sa snake_case (`session_start`,
  `user_prompt_submit`, `subagent_start`, `subagent_stop`).

### Czego o Codeksie NIE USTALONO

- Czy `codex exec --worktree` istnieje i czy dotyczy subagentow - NIEPOTWIERDZONE (brak w docs,
  polecenia `codex` nie ma na tej maszynie, wiec nie da sie sprawdzic `--help`).
- Czy subagent moze dostac inny `cwd` niz rodzic - NIEPOTWIERDZONE.

## Odcisk palca zaufania hookow Codeksa (`trusted_hash`) - ROZSTRZYGNIETE 2026-09-17

**Hash liczony jest WYLACZNIE z definicji hooka. Tresc skryptu wskazanego przez `command`
NIE wchodzi do hasha - edycja skryptu NIE kasuje zaufania.** Zatwierdza sie raz.

- Kod zrodlowy: `openai/codex` -> `codex-rs/hooks/src/engine/discovery.rs`, funkcja `hook_hash`
  (ok. l.775) + struktura `NormalizedHookIdentity` (l.768). Komentarz nad nia wprost:
  "Hash a normalized, config-derived identity instead of source text".
- Sam skrot: `codex-rs/config/src/fingerprint.rs`, `version_for_toml` (l.53) - sha256 z
  kanonicznego (klucze posortowane, bez spacji) JSON-a, prefiks `sha256:`.
- Do hasha wchodzi dokladnie: `event_name` (snake_case, np. `session_start`), `matcher`
  (pominiety gdy pusty) oraz JEDEN znormalizowany handler: `type`, `command`, `timeout`,
  `async`, opcjonalnie `commandWindows` / `statusMessage` / `additionalContextLimit`.
  NIE wchodzi: sciezka pliku `hooks.json`, tresc skryptu, indeksy z klucza `[hooks.state]`.
- Postac hashowanego JSON-a (zweryfikowana):
  `{"event_name":"session_start","hooks":[{"async":false,"command":"<cmd>","timeout":10,"type":"command"}]}`
- DOWOD EMPIRYCZNY: odtworzono co do znaku 3 z 8 wartosci `trusted_hash` zapisanych przez Orke w
  `...\orca\codex-runtime-home\home\config.toml` (session_start, user_prompt_submit, stop).
  Poboczne potwierdzenie: te 8 hookow ma IDENTYCZNA definicje i ten sam skrypt, a rozne hashe -
  rozni je wylacznie `event_name`.
- Definicje: `codex-rs/config/src/hook_config.rs` - `MatcherGroup` (l.154), `HookHandlerConfig`
  (l.163, enum tagowany polem `type`; warianty `command`, `mcp_tool`, `prompt`, `agent`).
- Trwalosc przy aktualizacji Codeksa: `trusted_hash` siedzi w `config.toml` uzytkownika, wiec
  aktualizacja binarki go nie kasuje. Ryzyko jest jedno: zmiana NORMALIZACJI w nowej wersji
  (inna domyslna wartosc `timeout`, dopisanie nowego pola do handlera). Dlatego w naszym hooku
  zawsze podawaj `timeout` JAWNIE - hook bez `timeout` dostaje wartosc domyslna dopiero przy
  normalizacji i jest bardziej podatny na rozjazd hasha.
- Wniosek wdrozeniowy: samoaktualizacje wolno wpiac w `SessionStart` Codeksa - uzytkownik
  zatwierdza `/hooks` RAZ, a my mozemy potem dowolnie poprawiac tresc skryptu. Ponownego
  zatwierdzenia wymaga tylko zmiana samej linii `command` / `timeout` / `matcher`.

## Orca - wbudowana orkiestracja (rozpoznanie 2026-09-17)

Orca to osobna aplikacja (Electron) instalowana w `C:\Users\Primo\AppData\Local\Programs\orca\`.
Binarka CLI: `resources\bin\orca.exe` (+ `orca.cmd`). Stan runtime w
`C:\Users\Primo\AppData\Roaming\orca\` - m.in. `orchestration.db` (SQLite, stan Runow/Taskow/
Dispatchow), `agent-sessions`, `terminal-history`, `codex-runtime-home`.

- `C:\Users\Primo\.claude\skills\orchestration\SKILL.md` - TYLKO ZAJAWKA (discovery stub).
  Prawdziwy przewodnik jest w binarce: `orca skills get orchestration` (compact), `--full`
  (kernel + wszystkie referencje), `--reference references/<plik>.md`.
- ZRODLO PRZEWODNIKA NA DYSKU, bez uruchamiania Orki:
  `...\orca\resources\app.asar.unpacked\out\cli\bundled-skill-guides.js` - eksportuje
  `BUNDLED_SKILL_GUIDES` (tablica 8 skilli, pola `markdown`, `fullMarkdown`, `references`).
  Skill `orchestration`: kernel 13 KB, `fullMarkdown` 42 KB, 7 referencji: `coordinator-loop`,
  `worker-contract`, `placement-and-remote`, `messaging-and-gates`, `recovery-and-cleanup`,
  `low-level-topology`, `legacy-contract-migration`.
- Kod komend: `...\out\cli\handlers\orchestration\*.js` (worker-launch-handler, gate-handlers,
  message-*, task-handlers, run-handlers, dispatch-handlers, worker-observation-handlers),
  specyfikacje w `...\out\cli\specs\orchestration.js` i `orchestration-worker-specs.js`.

### Model pojeciowy Orki

Run (trwala przestrzen nazw + skrzynka koordynatora; NIE planuje i NIE umieszcza workerow)
-> Task (praca) -> Dispatch (jedna autorytatywna proba wykonania Taska). Autorytet zycia
workera pochodzi z aktywnego Dispatcha, nie z tytulu terminala ani widocznego panelu.

- Komendy (z `out\cli`): `run-create/run-list/run-show/run-use/run-current`,
  `task-create/task-list/task-update`, `worker-start/worker-list/worker-show/worker-read/
  worker-stop/worker-abandon/worker-retain/worker-release`, `check` (z `--wait --types
  worker_done,escalation,question --timeout-ms`, `--ack`, `--peek`, `--all`, `--terminal`),
  `send`, `reply`, `ask`, `inbox`, `gate-create/gate-list/gate-resolve`,
  `coordinator-start/coordinator-stop`, `dispatch --inject`, `reset`, `summary`, `state`.
- IZOLACJA: `worker-start --worktree current | new-child | new-top-level | id:<repo::sciezka>`,
  plus `--name`, `--setup run`, `--repo`, `--on <serwer>` (SSH/WSL/zdalny host Orki).
  Domyslna REKOMENDACJA Orki to `current` - worktree tylko na zyczenie albo przy realnym
  konflikcie. Workspace moze byc zwyklym FOLDEREM (bez gita).
- SILNIKI MIESZANE: `--agent claude | codex | cursor | opencode | gemini | droid | grok`
  (adresy grupowe `@claude`, `@codex`, `@opencode`, `@gemini`, `@droid`, `@grok`, `@cursor`,
  `@all`, `@idle`, `@worktree:<id>`). `--model <id>` i `--effort` (wymaga `--model`).
- WIADOMOSCI: dwukierunkowe, trwale, FIFO. Worker pyta blokujaco `ask` (durable question,
  wznawiane po timeoucie po ID wiadomosci), koordynator odpowiada `reply --id`. Adres
  `dispatch:<id>` / `run:<id>`. Skrzynka koordynatora odtwarza te sama paczke (do 50
  wiadomosci) az do `--ack <deliveryId>`.
- GRAF ZADAN: `task-create --deps <json_array>`, `task-list --ready --brief`. Orca sama
  przestawia zadanie na `ready`. Workerzy moga rozdawac dalej (zagniezdzanie), ale jest
  limit glebokosci - blad `nested_worker_depth_exceeded`; nowy Run go NIE resetuje.
- BRAMKI DECYZYJNE: `gate-create --task --question --options`, `gate-resolve`, `gate-list`.
- KONTRAKT WORKERA (kernel): dokladnie jeden `worker_done` z obu ID, `--outcome
  succeeded|failed` i **trzyzdaniowym streszczeniem**; dluzsze tresci przez `--report-path`;
  `--files-modified`; heartbeat tylko w rytmie z preambuly; po `worker_done` bezczynnosc.
- KONTRAKT ZLECENIA (`Task-spec contract`): Target, Change, Constraints, Ownership,
  Observable acceptance.
- ROZLICZENIE: po kazdym settlement dokladnie jedno z: ponowne uzycie terminala /
  `worker-retain` / `worker-release`. Tura koordynatora nie moze sie skonczyc, dopoki
  `worker-list --terminal-state reclaimable` cos zwraca.
- GDZIE DZIALA: to CLI, wiec model wola je z wnetrza sesji (skill jest w `~/.claude/skills`),
  a Orca dodatkowo wstrzykuje workerowi preambule z Task ID i Dispatch ID. Stan widac
  rownolegle w aplikacji Orki.

### Orca a MegaRuchacz - granica

- Orca orkiestruje PROCESY I STAN (trwala baza, cykl zycia workera, placement, poczta,
  DAG, bramki). MegaRuchacz orkiestruje ZACHOWANIE (wstrzykiwane zasady: kiedy dzielic,
  kiedy NIE dzielic, mapa projektu, rejestr `worklog.md`, limit raportu, sprzatanie galezi).
- Pokrycie jest realne w trzech miejscach: limit raportu (Orca: 3 zdania + `--report-path`),
  samowystarczalne zlecenie (Orca: Task-spec contract) i pytanie blokujace
  (Orca: `ask`/`reply`, MegaRuchacz: `SendMessage` do `main`).
- Czego Orca NIE MA: mapy projektu (odpowiednika `.claude/mapa.md`), reguly "kiedy NIE
  rozdawac" (debugowanie, jedna gleboka zmiana, drobiazg) ani obowiazku commita przed
  kasowaniem kopii roboczej. `task-list --ready` jest nazwane "external memory", ale to
  pamiec o ZADANIACH, nie o tym, gdzie co lezy w repo.
- W repo `claude-worker` jest tylko `narzedzia\orca-ustawienia.js` (przenoszenie sekcji
  `settings`/`ui` z `orca-data.json` miedzy komputerami) - `wdroz.ps1` ani
  `straznik-zasad.ps1` NIE wspominaja o Orce i nic dla niej nie wdrazaja.
- `C:\Users\Primo\.claude\mr\megaruchacz-zasady-orca.md` - ISTNIEJE wariant zasad kierownika
  pod Orke (rozdawanie przez `orca orchestration run-create` / `task-create` / `worker-start
  --worktree new-child --agent claude`, odbior przez `check --wait`, plaskie drzewo).
  NIE jest sledzony w gicie i nie wdraza go instalator - lezy tylko na tej maszynie.

## Koszt tekstu w kontekscie a pamiec podreczna modelu (prompt caching) - rozpoznanie 2026-09-24

- Transkrypty Claude Code: `C:\Users\Primo\.claude\projects\<projekt>\<sesja>.jsonl` (glowna sesja),
  podagenci w podkatalogach `subagents` / pliki `agent-*`. Wiadomosc asystenta: `message.usage` z polami
  `input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `cache_creation.ephemeral_1h_input_tokens`.
  Jedna odpowiedz modelu bywa zapisana w kilku liniach - liczyc unikalne `message.id`, pomijac model `<synthetic>`.
- Wstrzykniecia hookow sa w transkrypcie jako linie `type:"attachment"` z `attachment.type = "hook_additional_context"`
  (`hookName` np. `SessionStart:startup`); CLAUDE.md i warstwy startowe jada w PIERWSZEJ wiadomosci, za promptem systemowym.
- Claude Code uzywa bufora 1-godzinnego (`ephemeral_1h`, 100% zapisow) - zapis kosztuje 2x zwykle wejscie, odczyt 0.1x
  (Opus 5 / 4.x), 0.05x (Opus 5.5). Zrodlo: `https://docs.claude.com/en/docs/build-with-claude/prompt-caching.md` (sekcja Pricing).
- Bufor miedzy sesjami obejmuje tylko prompt systemowy + narzedzia (~20-35 tys. tokenow); CLAUDE.md i warstwy startowe
  zapisuja sie od nowa w kazdej sesji i potem sa czytane z bufora przy KAZDYM wywolaniu modelu (nie raz na sesje).
- Tekst wstrzykniety hookiem `UserPromptSubmit` NIE psuje bufora (dokleja sie na koncu); zostaje w historii,
  wiec kazde przypomnienie jest potem czytane przy kazdym kolejnym wywolaniu.
- Bufor peka (wszystko po prompcie systemowym zapisywane od nowa) praktycznie zawsze po przerwie > 60 min
  oraz przy zmianie modelu i kompaktowaniu.
- Na tej maszynie srednio ~10 wywolan modelu na jedna wiadomosc uzytkownika (petla narzedzi) - "koszt na wiadomosc"
  trzeba mnozyc przez wywolania, nie przez wiadomosci.
- `narzedzia/koszt-pamieci.ps1` liczy warstwy startowe jako placone RAZ na sesje (znaki / 3) - bez bufora i bez krotnosci wywolan.
- Codex/OpenAI: odczyt z bufora 0.1x, zapis 1.25x przez API (GPT-5.6+), w rozliczeniu kredytami Codeksa brak doplaty za zapis;
  bufor zyje 30 min od ostatniego uzycia. Zrodla: `https://developers.openai.com/api/docs/guides/prompt-caching.md`,
  `https://developers.openai.com/codex/pricing.md`. Transkryptow Codeksa (`~\.codex\sessions`) na tej maszynie NIE MA.
