# Mapa projektu

Co gdzie lezy. Uzupelniaja to raporty scouta - kierownik czyta stad, zanim
wysle kogokolwiek na rozpoznanie.

<!-- przyklad:
## Autoryzacja
- src/auth/session.ts - tworzenie i walidacja sesji
- src/auth/login.ts   - endpoint logowania
-->

## Audyt historii gita (przed publikacja na GitHub)
- Repo ma 21 commitow na jednej galezi `main`, remote juz ustawiony na github.com/Primo2966/MegaRuchacz.
- Wszystkie commity: autor/committer = przemyslaw.flieger@gmail.com (imie i nazwisko w metadanych, adres prywatny gmail, nie noreply). Jeden unikalny adres w calej historii.
- Katalog `historia/` zostal w calosci przemianowany na `lore/` w commicie 6fa1c0e (git widzi to jako delete+add) - to nie jest wyciek, tresc przeniesiona, nie usunieta z projektu.
- W historii (lore/README.md, wczesniej historia/README.md) jest przykladowa sciezka `C:\Users\Primo\.claude.json` - nazwa windowsowego konta uzytkownika w dokumentacji, niska wrazliwosc.
- `.claude/plan-repo.md` w historii zawiera zdanie ze repo mialo byc PRYWATNE, dostep przez zaproszenie - to plan wewnetrzny kierownika projektu, nie dane klienta/firmy trzeciej.
- Brak w calej historii: kluczy API/tokenow (ghp_, sk-, AKIA), plikow .env/credentials/.pem, plikow binarnych (najwiekszy obiekt to uv.lock ~293KB, tekstowy), nazw firm trzecich/SKU.
- Najwieksze bloby w historii to same pliki tekstowe (uv.lock, .py, .ps1, .md, .js) - zero prawdziwych binariow.

## Audyt plikow sledzonych (working tree, przed publikacja) — 2026-09-16
- `.claude/plan-repo.md:121-123` — wprost wymienia prywatna sciezke/projekt `C:\dev\Aliebaba-Primo\WMS_Official` jako "nazwa prywatnego projektu do posprzatania"; sam kod juz to usunieto (sprawdzone: brak w `nowe-zadanie.ps1` i `rozszerzenie/package.json`), ale nazwa zostaje zaszyta w tym pliku planistycznym. Blokujace przed publikacja.
- `.claude/plan-repo.md` (caly plik) — notatka robocza kierownika projektu z ustaleniami sesji (m.in. "Repo: Primo2966/MegaRuchacz, PRYWATNE"), nie jest dokumentacja produktu — nie pasuje do publicznego repo, do usuniecia/przeniesienia poza repo.
- `rozszerzenie/LICENSE.txt:1` — tresc to tylko "Uzytek wewnetrzny." — sprzeczne z publikacja open-source, wymaga realnej tresci licencji przed upublicznieniem.
- `lore/README.md:63` — sciezka `C:\Users\Primo\.claude.json` (nazwa konta windows), niska wrazliwosc, kosmetyczne.
- Sprawdzone i czyste: brak sekretow/tokenow/kluczy API w tresci sledzonych plikow (`git grep` po `sk-`, `ghp_`, `AKIA`, `BEGIN ... PRIVATE KEY`, `password=` itp. — trafienia to tylko kod maskujacy sekrety w `lore/lore/masking.py` i dokumentacja tego mechanizmu), brak adresow e-mail, brak prywatnych IP, `.gitignore` poprawnie wyklucza `.venv`, bazy, `*.vsix`, `node_modules`.
