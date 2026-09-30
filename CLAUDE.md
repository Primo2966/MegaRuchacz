# MegaRuchacz — repozytorium narzędzia

Zasady kierownika są globalne: blok `MegaRuchacz:kierownik` w `~/.claude/CLAUDE.md`.
Ich źródło to `szablony-global/claude/zasady-kierownika.md` — zmienia się je tam
i wgrywa przez `narzedzia\instaluj-globalnie.ps1`, nigdy ręcznie. Tu stoi wyłącznie
to, co dotyczy budowania samego MegaRuchacza.

## Cisza jest zakazana

Ustalone 2026-09-17, po tym jak jednego dnia złamaliśmy tę zasadę w trzech
niezależnych miejscach. Dotyczy wszystkiego, co budujemy w tym projekcie.

**Nic nie ma prawa zawieść bez śladu.** Konkretnie:

- **Sufit nie ucina — sufit krzyczy.** Gdy tekst nie mieści się w limicie, na jego
  POCZĄTKU ma stanąć ostrzeżenie (początek przeżywa ucięcie zawsze), a narzędzie,
  które ten tekst składa, ma odmówić zapisu zamiast zapisać kadłubek i zameldować
  sukces.
- **Brak wiadomości nie może znaczyć „wszystko gra".** Każdy mechanizm chodzący
  w tle zostawia znacznik „byłem tu"; jego nieświeżość sama w sobie jest alarmem.
- **Puste `catch { }` jest zabronione.** Wolno nie przerywać pracy, nie wolno
  milczeć: błąd idzie do stanu i jest meldowany przy następnej okazji.
- **Liczba bez jednostki użytkownika to kłamstwo.** „Na wiadomość" i „na sesję" to
  różne pieniądze; mnożenie przez zmyśloną stałą („sesji na dobę") zaciemnia
  zamiast wyjaśniać.
- **Fałszywy alarm jest gorszy niż brak alarmu** — uczy ignorować ostrzeżenia.
  Alarm ma mieć próg z uzasadnieniem zapisanym obok, a nie liczbę z powietrza.

**Każde zabezpieczenie wymaga próby negatywnej.** Zabezpieczenie, którego nikt nie
próbował złamać, było 2026-09-17 martwe w trzech przypadkach na trzy — zawsze
wyglądało na działające. Dopóki nie widziałeś, jak reaguje na złamanie, nie liczy
się za zrobione.

## Konwencje pracy w tym repo

Każdy worker dostaje ten plik sam — kierownik nie wkleja tych zasad do zleceń.

- **Bez worktree.** Testy wymagają PowerShella, a w kopii roboczej Claude Code blokuje
  każde jego wywołanie. Workerzy pracują równolegle w tym samym katalogu, każdy
  wyłącznie na plikach ze swojego zlecenia.
- **Kodowanie plików sprawdzasz przed zmianą i po niej** — BOM i końce linii, bajtowo
  (np. `node`), bo narzędzia Git Bash przekłamują CR (`sed -i` je zdejmuje, `grep`
  źle liczy). Pliki `.ps1` z polskimi znakami (np. `zasobnik\nadzorca.ps1`) muszą mieć
  BOM — bez niego PowerShell 5.1 czyta je jako ANSI.
- **Testy niewidoczne** — żadnych okien konsoli ani dymków na ekranie użytkownika, także
  z procesów, które test uruchamia (`-WindowStyle Hidden`, `CreateNoWindow`). Okno
  nadzorcy testujesz na kopii (wzór `zasobnik\test-p7.ps1`): własny zamek, poza ekranem
  (-5000, 0), bez paska zadań, ikony i dozoru, `-Proba`, bez `SetForegroundWindow`,
  klawiatura wyłączona, a bezpiecznik w kopii `stan-nadzorcy.ps1` trzyma cykl wiedzy na
  sucho (`Ruszaj-Cykl` i spółka). Pułapki: mapa, „TEST okna bez ekranu”. Po teście żadna
  kopia nie zostaje w procesach.
- **Commit:** `git add` tylko własnych plików (nigdy `-A`), commit lokalny z linią
  `Co-Authored-By`, którą podaje Claude Code (zasada „bez atrybucji” dotyczy tylko
  projektu WMS). Zablokowany indeks (`index.lock`) — odczekaj kilka sekund i ponów.
- **Push, `ZMIANY.md` i `.megaruchacz\mapa.md` robi kierownik** na koniec rundy — worker
  podaje w raporcie, co tam dopisać.
- **Wspólne zasoby** — restart nadzorcy, pliki w `~\.claude`, zadania Harmonogramu,
  instalatory globalne — rusza tylko worker, któremu zlecenie to wprost przydziela.
- **Restart nadzorcy** (działający proces zostaje na starym kodzie): zatrzymaj
  `powershell.exe`, którego wiersz poleceń zawiera `zasobnik\nadzorca.ps1` tego repo
  (nie kopie testowe), potem `Start-ScheduledTask MegaRuchaczNadzorca` (póki stary
  działa, Harmonogram odrzuca drugi start) i sprawdź, że proces wstał.
