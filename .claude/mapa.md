# Mapa projektu

Co gdzie lezy. Uzupelniaja to raporty scouta - kierownik czyta stad, zanim
wysle kogokolwiek na rozpoznanie.

<!-- przyklad:
## Autoryzacja
- src/auth/session.ts - tworzenie i walidacja sesji
- src/auth/login.ts   - endpoint logowania
-->

## Aktualizacja wdrozen (mechanizm wersji)

- `narzedzia/straznik-zasad.ps1` - straznik wolany hookiem SessionStart; funkcje: `Rejestr-Modulow` (l.78, moduly `workerzy` i `pamiec`, pola `pytaj`/`instalator`/`aktualizacja`), `Pilnuj-Zasad` (l.250, blok zasad w ~/.claude/CLAUDE.md), `Pilnuj-Wersji` (l.304, porownanie wersji), `Nanies-Poprawki` (l.234, kopiuje pliki ze zrodla do `.claude/` projektu), `Napraw-Hooki` (l.193, dokleja brakujace hooki do settings.json).
- Porownanie wersji: najwyzszy naglowek `## X.Y.Z` w `ZMIANY.md` zrodla (`Wersja-Narzedzia`) kontra klucz `modul.<nazwa>.wersja` w `.claude/megaruchacz-wersja.txt` projektu.
- Regula: patch -> `Nanies-Poprawki` sam; minor -> pliki wchodza, nowa funkcja tylko proponowana; major -> nic, komunikat o recznym `wdroz.ps1`. Modul z `aktualizacja = "instalator"` (np. `pamiec`) nigdy nie aktualizuje sie sam - straznik podaje komende.
- Odmowy zapamietywane w pliku wersji: `modul.<x>.status: odrzucony`, `modul.<x>.odrzucone`, `modul.<x>.zaproponowane`. Ustawia je `straznik-zasad.ps1 -Odrzuc <modul>`.
- `.claude/megaruchacz-wersja.txt` - pisany przez `wdroz.ps1` (l.352-374); klucze `zrodlo:` (BEZWZGLEDNA sciezka do repo narzedzia), `commit:`, `data:`, `modul.*`.
- Sciezka do repo zrodlowego jest zaszywana bezwzglednie tez w hooku SessionStart w `settings.json` - generuje to `dodajStraznika()` w `wdroz.ps1` (l.294). Przeniesienie repo psuje hook; straznik przy nieistniejacym `-Zrodlo` milczy i konczy zerem.
- `wdroz.ps1` - jedyny instalator; czyta rejestr modulow przez `straznik-zasad.ps1 -Moduly`, na koncu robi samosprawdzenie (sekcja od l.378).

### Czego tu nie ma

- Nigdzie w repo nie ma `git pull`, `git fetch` ani zadnego odwolania do `origin` - jedyne uzycie gita poza worktree to `git -C $Zrodlo rev-parse --short HEAD` w `wdroz.ps1:356`. Kopia repo narzedzia na dysku nigdy nie odswieza sie sama.
- Nie ma zadania w Harmonogramie Windows aktualizujacego narzedzie. Zadania rejestruja tylko: `cykl-dzienny.ps1`, `instaluj-lore.ps1`, `wyciagnij-fakty.ps1`, `aktualizuj-wiedze.ps1`, `koszt-pamieci.ps1` - wszystkie dotycza Lore/pamieci, nie wersji narzedzia.
- `narzedzia/cykl-dzienny.ps1` nie wola ani `wdroz.ps1`, ani straznika.

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

- `wdroz.ps1:207-217` - kopiuje `.claude/agents/*.md` (4 role); nadpisuje cudze pliki dopiero po kopii
  zapasowej, rozpoznaje swoje po znaczniku `kierownik-template`.
- `wdroz.ps1:220-234` - `worklog.md` i `mapa.md` tylko gdy ich nie ma; `CLAUDE.md` zrodla ->
  `.claude/megaruchacz-zasady.md`, plus `orchestrator-reminder.json` i `mr-log.js`.
- `wdroz.ps1:236-251` - generuje `.claude/megaruchacz-sesja.json`: JSON z
  `hookSpecificOutput.additionalContext` = cala tresc zasad (ladunek hooka SessionStart).
- `wdroz.ps1:253-311` - pisze `.claude/settings.json`: `worktree = {baseRef:"fresh", bgIsolation:"worktree"}`
  oraz 5 hookow (kazdy `shell:"bash"`, timeout 5 s, 15 s dla straznika):
  SessionStart -> `cat megaruchacz-sesja.json` (pelne zasady raz na sesje);
  SessionStart -> `narzedzia/straznik-zasad.ps1` (wersje/poprawki, sciezka bezwzgledna);
  UserPromptSubmit -> `cat orchestrator-reminder.json` (przypomnienie przy kazdym enterze);
  SubagentStart -> `node mr-log.js`; SubagentStop -> `node mr-log.js stop`.
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
