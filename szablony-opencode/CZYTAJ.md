# Szablony trybu workerow dla opencode

Odpowiednik modulu `workerzy` z Claude Code. Tu lezy sama TRESC - wdraza to
`wdroz.ps1` (czesc "4c. opencode"), gdy widzi opencode na maszynie.

## Co gdzie ma trafic

- `agents/*.md` -> `<projekt>/.opencode/agents/`. Nazwa agenta bierze sie z nazwy
  pliku. Swoje pliki instalator rozpoznaje po znaczniku `kierownik-template` w tresci.
  Role maja `mode: subagent` i wlasne uprawnienia (`implementer` pisze, pozostale
  trzy maja `edit: deny`).
- `plugins/mr-log.js` -> `<projekt>/.opencode/plugins/mr-log.js`. To zamiennik
  hookow Codeksa: slucha zdarzen sesji (`session.created` / `session.idle` /
  `session.deleted`) i dopisuje START/KONIEC workera do `.megaruchacz/worklog.md`.
  opencode laduje kazdy plik z `.opencode/plugins/` sam, bez zadnego zatwierdzania.
Wtyczka robi jeszcze dwie rzeczy: odswieza znacznik `~/.claude/.megaruchacz-opencode-zyje`
(dowod, ze dziala) i gdy `AGENTS.md` nie ma bloku zasad, dokłada
  `.megaruchacz/zasady-kierownika.md` jako plik instrukcji (`config.instructions`) -
  dzięki temu zasady docierają także wtedy, gdy `AGENTS.md` jest sledzony w gicie
  i instalator go nie ruszył. Gdy blok w `AGENTS.md` jest, wtyczka nic nie dokłada
  (żadnego podwójnego ładowania).
- `zasady-kierownika.md` -> `<projekt>/AGENTS.md`, miedzy znaczniki
  `<!-- MegaRuchacz:start -->` i `<!-- MegaRuchacz:koniec -->`. opencode czyta
  `AGENTS.md` sam, bez zadnego hooka - ta sama droga co Codex. Gdy `AGENTS.md`
  jest sledzony w gicie, instalator go NIE RUSZA.
- Kopia zasad laduje takze w `<projekt>/.megaruchacz/zasady-kierownika.md`, zeby
  mial ja pod reka takze Codex i zeby dalo sie je przejrzec bez otwierania AGENTS.md.
- Rejestr i mapa celowo w `<projekt>/.megaruchacz/` - wspolne dla opencode i Codeksa.

## Dlaczego wtyczka, a nie hooki

opencode nie ma hookow uruchamianych komenda, ktore trzeba zatwierdzac. Ma wtyczki
ladowane z `.opencode/plugins/`. Dlatego:

- **nic nie trzeba zatwierdzac** - wystarczy ponowne otwarcie okna;
- **rejestr dziala od razu**, bo wtyczka startuje razem z opencode;
- **wtyczka startuje strażnika zasad w tle.** Pod Claude Code i Codeksem rolę tę
  pełni hook `SessionStart`; opencode takiego hooka nie ma, więc wtyczka woła
  `straznik-zasad.ps1 -Tlo` raz na proces (ślad idzie do
  `~\.claude\.megaruchacz-tlo.log`). Dzięki temu samoaktualizacja narzędzia
  i pilnowanie bloków zasad działają także tutaj.
- **aktualizacja jest cicha** - strażnik zasad podmienia plik wtyczki przy
  podbiciu wersji, tak samo jak role i zasady.

Wtyczka pisze tez znacznik `~/.claude/.megaruchacz-opencode-zyje` przy kazdym starcie
opencode. To odpowiedz na pytanie "czy wtyczka w ogole sie zaladowala": rejestr,
ktory milczy, musi byc odroznialny od rejestru, ktory nie chodzi. Bez znacznika
wtyczka nie dziala.

## Czego tryb workerow pod opencode NIE POTRAFI

1. **Pracy w tle nie ma.** Watek glowny czeka na wszystkich podagentow i dopiero
   wtedy odpowiada. Dlatego zasady kaza rozdawac cala runde naraz, jednym
   wywolaniem podagentow.
2. **Izolacji przez worktree nie ma.** Podagent dziedziczy katalog rodzica -
   rozlacznosc plikow pilnuje wylacznie tresc zlecenia i rejestr.
3. **Worker nie zapyta w trakcie pracy.** Brak kanalu zwrotnego: konczy raportem
   `WYMAGA DECYZJI`, a kierownik puszcza go drugi raz.
4. **`edit: deny` blokuje narzedzia zapisu, nie bash.** Scout i verifier maja
   wylaczony `edit`, ale `bash` zostaje - dopiero tresc ich promptu zabrania
   pisania przez powloke. To slabsza granica niz piaskownica Codeksa.

## Co odswieza straznik, a czego nie rusza

Straznik (`narzedzia\straznik-zasad.ps1`, funkcja `Nanies-Poprawki`) nanosi poprawki
takze na czesc opencode - na tych samych zasadach co na `.claude\`: zmiana trzeciej
cyfry wersji wchodzi sama. Obejmuje `.opencode\agents\*.md` i
`.opencode\plugins\mr-log.js`. Blok zasad w `AGENTS.md` odswieza wspolna funkcja
`Odswiez-Agents` - ta sama, ktorej uzywa czesc codeksowa.

Poprawek wtyczki nie trzeba zatwierdzac - inaczej niz `hooks.json` w Codeksie.
