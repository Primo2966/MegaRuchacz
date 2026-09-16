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
