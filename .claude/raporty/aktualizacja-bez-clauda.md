# Aktualizacja narzedzia na maszynie bez Claude Code

## Co powstalo

### 1. Tryb bezobslugowy straznika (`narzedzia\straznik-zasad.ps1`)

Nowy przelacznik `-Tlo`. W tym trybie straznik robi wylacznie dwie rzeczy:
`Odswiez-Zrodlo` (pobranie nowszej wersji z gita) i `Pilnuj-Zasad` (utrzymanie
blokow w plikach instrukcji). Nie wola `Pilnuj-Wersji`, `Zglos-Kandydatow`
ani `Zglos-Cykl` - to sa komunikaty dla czlowieka przy klawiaturze.

Zmiany szczegolowe:

- `Mow` zamiast `Write-Host` w obu tych funkcjach: w hooku idzie na ekran
  (bez zmiany zachowania), w tle do dziennika.
- `Notuj` - linie wylacznie do dziennika, w miejscach, gdzie hook milczy celowo
  (brak gita, nie repo, brak zdalnej, brak sieci, nic nowego, zasady aktualne).
  Bez tego dziennik nie odpowiadalby na pytanie "czy to w ogole chodzi".
- Dziennik: `~\.claude\.megaruchacz-tlo.log`, format `RRRR-MM-DD GG:MM | tresc`,
  przycinany do ostatnich 200 linii przy kazdym zapisie. Przebieg, w ktorym nic
  sie nie dzialo, zostawia linie "nic nie wymagalo uwagi".
- Dlawik "raz na godzine" pominiety w trybie `-Tlo` - tam czestotliwosc ustawia
  harmonogram, a nie liczba otwartych okien. Znacznik pobrania i tak jest
  zapisywany, wiec tlo dlawi hooki.
- Limity czasu gita w tle: 30 s na zwykle wywolanie, 60 s na `fetch` i `merge`
  (w hooku bez zmian: 5 s i 6 s).

### 2. Zadanie w Harmonogramie (`narzedzia\instaluj-lore.ps1`)

**Wybor: osobne zadanie `MegaRuchaczOdswiez`, nie doklejanie do `LoreIndex`.**
Powod: `LoreIndex` nalezy do opcjonalnego modulu `pamiec`, ktory uzytkownik moze
odrzucic (`straznik-zasad.ps1 -Odrzuc pamiec`), a aktualizowac ma sie narzedzie
tak czy owak; dochodzi do tego inny sensowny interwal (10 min dla indeksu, 60 min
dla pobrania z sieci).

- Rejestracja XML wyciagnieta do `Zarejestruj-Zadanie` - jedno miejsce dla obu
  zadan. Nadal XML i `-Force`, bez `-Principal` (odmowa dostepu bez podniesienia)
  i bez duplikatow przy ponownej instalacji.
- `Stan-Zadania` przyjmuje teraz nazwe i wzorzec akcji - to samo sprawdzenie
  dziala dla obu zadan.
- Akcja zadania:
  `conhost.exe --headless powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<Zrodlo>\narzedzia\straznik-zasad.ps1" -Zrodlo "<Zrodlo>" -Tlo`
- Nowy przelacznik `-TylkoOdswiezanie`: zaklada wylacznie to zadanie, bez uv,
  Pythona i MCP. Z tego korzysta `wdroz.ps1`, gdy modul `pamiec` nie wchodzi -
  inaczej odswiezanie wisialoby na module, ktory wolno odrzucic.

### 3. Zasady w pliku Codeksa

**Zapis byl juz zrobiony** - `narzedzia\wpisz-zasady.ps1` od dawna pisze do obu
plikow (`~\.claude\CLAUDE.md` i `~\.codex\AGENTS.md`), tym samym mechanizmem
znacznikow. Nie dublowalem tego.

Dziura byla gdzie indziej: `Pilnuj-Zasad` w strazniku **sprawdzal tylko
CLAUDE.md**. Na maszynie z samym Codeksem wygladalo to tak, ze blok w CLAUDE.md
sie zgadza, wiec straznik milczy - a `AGENTS.md` moglby byc pusty albo stary
i nikt by tego nie zauwazyl. Teraz `Cele-Zasad` zwraca liste plikow (Codex
dochodzi, gdy istnieje `~\.codex`), kazdy jest sprawdzany osobno, a stan skrotow
trzyma osobne klucze (`blok` dla CLAUDE.md, `blok.codex` dla AGENTS.md - stare
pliki stanu dalej sie zgadzaja).

Limit 32 KiB: `Pilnuj-Limitu` mowi jedna linia, gdy `AGENTS.md` przekroczy limit
("koniec pliku sie nie wczyta, skroc go"). Nie przycinamy pliku sami - to zapiski
uzytkownika.

### 4. `wdroz.ps1` bez Claude Code

Co robil wczesniej: nie sprawdzal w ogole, czy Claude Code istnieje. Zakladal
wpis w `.claude\settings.json`, ktorego nikt nigdy nie wykona, wymagal node'a
(bez niego dwa pliki po cichu nie powstawaly), a samosprawdzenie zglaszalo
**BLAD** "hooki daja sie uruchomic" i konczylo kodem 1 - czyli maszyna z samym
Codeksem dostawala komunikat o nieudanej instalacji, mimo ze zasady i pamiec
wchodzily poprawnie. Na koniec pisal "Zamknij i otworz Claude Code na nowo".

Teraz:

- wykrywanie `claude`, `node` i `bash` w PATH na poczatku,
- ekran zgody przed pytaniem mowi wprost, ze tryb workerow wymaga Claude Code
  i tutaj nie zadziala, oraz co dziala (zasady, odswiezanie, pamiec),
- pliki trybu workerow nadal sa zapisywane (zaczna dzialac, gdy Claude Code sie
  pojawi), ale hooki nie sa juz **wymagane** ani sprawdzane tam, gdzie nie ma
  Claude Code - to trafia do sekcji "czego to sprawdzenie NIE obejmuje",
- brak node'a nie jest cicha porazka: mowi o tym wprost i nie wymaga plikow,
  ktorych nie dalo sie zlozyc,
- nowy punkt 3) ekranu zgody: zadanie `MegaRuchaczOdswiez`,
- komunikat koncowy nie obiecuje trybu workerow tam, gdzie go nie ma.

## Czego NIE sprawdzono uruchomieniem

Kopia robocza (worktree) odmawia uruchomienia PowerShella: kazde wywolanie
`powershell -NoProfile ...` konczy sie komunikatem narzedzia "Refusing to run
it - a worktree-isolated agent's git operations must target its own worktree".
Zadna z trzech bramek z kryterium ukonczenia nie zostala wiec naprawde
uruchomiona. Sprawdzone zostalo tylko to, co dalo sie sprawdzic statycznie:
bilans nawiasow klamrowych (zgadza sie we wszystkich trzech plikach), brak
polskich znakow diakrytycznych, brak wzorca `"$Zmienna: tekst"`.

Komendy do odpalenia recznie, z katalogu repozytorium:

```powershell
powershell -NoProfile -Command "[void][System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw narzedzia\straznik-zasad.ps1), [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw narzedzia\instaluj-lore.ps1), [ref]$null)"
powershell -NoProfile -Command "[void][System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw wdroz.ps1), [ref]$null)"
powershell -NoProfile -File narzedzia\straznik-zasad.ps1 -Moduly
powershell -ExecutionPolicy Bypass -File narzedzia\instaluj-lore.ps1 -Proba
```

Warto tez zobaczyc, czy tryb tla naprawde pisze dziennik (nic nie psuje, tylko
pobiera i pilnuje zasad):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File narzedzia\straznik-zasad.ps1 -Tlo
type "$env:USERPROFILE\.claude\.megaruchacz-tlo.log"
```

Po zalozeniu zadania:

```powershell
Get-ScheduledTask MegaRuchaczOdswiez | Format-List TaskName,State
```
