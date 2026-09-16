# Straznik sam pobiera nowa wersje narzedzia

## Co doszlo w `narzedzia\straznik-zasad.ps1`

- `Wolaj-Gita($argumenty, $sekundy)` - wola git.exe przez `Start-Process` z limitem
  czasu (`WaitForExit(ms)`, po przekroczeniu `Kill()`), wyjscie i bledy do plikow
  tymczasowych. Zwraca `.ok` / `.tekst`. Nigdy nie rzuca wyjatkiem.
- `Odswiez-Zrodlo` - wywolywana jako pierwsza w przebiegu, przed `Pilnuj-Zasad`
  i `Pilnuj-Wersji`, we wlasnym `try {} catch {}`.

## Kolejnosc decyzji w `Odswiez-Zrodlo`

1. Znacznik czasu - jesli ostatnie sprawdzenie bylo mniej niz 60 minut temu, koniec.
2. Brak `git` w PATH -> cisza.
3. `rev-parse --is-inside-work-tree` != "true" (nie repozytorium) -> cisza.
4. Zapis znacznika czasu (proba byla prawdziwa, wiec nie ponawiamy co okno).
5. `status --porcelain` niepuste -> jedna linia "sa niezapisane zmiany", koniec.
6. Brak galezi sledzonej (`@{u}`) albo odpiety HEAD -> cisza.
7. `fetch --quiet` (6 s, `GIT_TERMINAL_PROMPT=0`, `credential.interactive=never`);
   nieudany = brak sieci -> cisza.
8. `rev-list --left-right --count HEAD...@{u}`: zdalnych 0 -> cisza; lokalnych > 0
   (rozjazd) -> linia "nie scalam sam"; inaczej `merge --ff-only` (6 s).
9. Po udanym przewinieciu zawsze jedna linia: wersja z `ZMIANY.md` przed -> po,
   a gdy numer sie nie zmienil - ile nowych zmian weszlo.

Zadnego `reset --hard`, `checkout -f`, `clean` ani `--autostash`. Jedyna komenda
zmieniajaca stan to `merge --ff-only` na czystym drzewie.

## Ograniczenie czestotliwosci

Plik `~\.claude\.megaruchacz-pobranie.txt` (format "klucz: wartosc", ten sam co
reszta plikow stanu). Klucz to `z` + MD5 sciezki zrodla pisanej malymi literami,
wartosc to data ostatniej proby. Plik lezy w katalogu domowym, a nie przy
`megaruchacz-wersja.txt` projektu, bo katalog zrodlowy jest jeden na maszyne -
dziesiec otwartych okien ma odpytac siec raz, nie dziesiec razy. Odstep:
`$MINUT_MIEDZY_POBRANIAMI = 60` (stala na gorze skryptu).

Limity czasu (6 s na fetch, 6 s na merge, 5 s na komendy lokalne) sa dobrane pod
15-sekundowy budzet hooka `SessionStart` z `Napraw-Hooki`.

## NIESPRAWDZONE URUCHOMIENIEM - do zrobienia poza worktree

Worker byl odpalony w worktree, a izolacja worktree odmawia uruchomienia
JAKIEJKOLWIEK komendy `powershell` (komunikat: "this command runs powershell in a
plain command; what it reads or is handed as shell text cannot be shown not to run
git"). Odmowa dotyczy tez `-Moduly` i utrzymuje sie przy wylaczonej piaskownicy.
Kod nie zostal wiec ani razu wykonany - ponizsze trzeba przejsc w glownym repo:

```powershell
# 1. kontrakt z wdroz.ps1 - ma wyjsc poprawny JSON
powershell -NoProfile -File narzedzia\straznik-zasad.ps1 -Moduly

# 2. brudne drzewo - ma wypisac linie "sa niezapisane zmiany" i skonczyc kodem 0
powershell -NoProfile -File narzedzia\straznik-zasad.ps1 -KatalogDomowy $env:TEMP\mr-test-dom

# 3. zrodlo nie jest repozytorium - ma przejsc cicho
mkdir $env:TEMP\mr-nierepo -Force; copy ZMIANY.md $env:TEMP\mr-nierepo
powershell -NoProfile -File narzedzia\straznik-zasad.ps1 -Zrodlo $env:TEMP\mr-nierepo -KatalogDomowy $env:TEMP\mr-test-dom
```

Przed kazdym kolejnym przebiegiem trzeba skasowac
`$env:TEMP\mr-test-dom\.claude\.megaruchacz-pobranie.txt`, inaczej zadziala
godzinna przerwa i straznik pominie gita.

Pelne przejscie sciezki fast-forward wymaga scenariusza z lokalnym `origin`:
bare repo -> klon jako zrodlo -> commit z ZMIANY.md o wyzszym numerze wpychany
z drugiego klonu -> uruchomienie straznika na pierwszym klonie. Oczekiwane:
jedna linia "narzedzie podciagniete z gita - wersja X -> Y".
