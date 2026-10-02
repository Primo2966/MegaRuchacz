# Historia wersji

Każda zmiana wypychana na gita dostaje tu wpis. Numer rośnie wg zasady:
pierwsza cyfra — przebudowa łamiąca zgodność, druga — nowa funkcja,
trzecia — poprawka.

## 0.27.0 — 2026-10-02

- **Instalator z oknem: `instaluj.bat`.** Dwuklik otwiera okno instalatora (bez migającej konsoli, nic do
  instalowania wcześniej). Na komputerze bez MegaRuchacza sam plik `instaluj.bat` pobiera go z GitHuba, pyta
  o folder, w razie potrzeby zdobywa program git i klonuje repozytorium — dzięki temu potem działają
  aktualizacje. Ekrany: powitanie z wykrytymi narzędziami (Claude Code, Codex, opencode), wybór części,
  podsumowanie (co się stanie i jakich programów brakuje), postęp krok po kroku ze „Spróbuj ponownie”
  i „Pokaż szczegóły” przy błędzie, ekran „Gotowe” z tym, co jest do sprawdzenia.
- **Wybierasz, co chcesz mieć.** Zawsze: aplikacja przy zegarze i automatyczne aktualizacje. Do wyboru:
  **Wiedza o Tobie**, **Pamięć rozmów (Lore)**, **Tryb kierownika**, **Polecane skille**, **Kopia zapasowa**
  (folder docelowy, co kopiować i czego nie). Brakujące programy (uv, Python 3.12, git, Node.js) instalator
  doinstalowuje sam, bez uprawnień administratora — przez winget albo z paczki ZIP sprawdzonej sumą SHA-256.
  Wybór zapisuje się w `~\.claude\mr\instalacja.json` i za nim idą strażnik, przypomnienia i aplikacja przy
  zegarze.
- **Zmiana instalacji jednym przyciskiem.** W oknie aplikacji przy zegarze jest „Zmień instalację” (albo
  uruchom `instaluj.bat` jeszcze raz). Zaznaczone jest to, co masz; odznaczenie pyta w oknie, z polem „usuń też
  moje dane” — domyślnie odznaczonym, więc dane zostają i wracają po ponownym włączeniu. Pierwsze otwarcie na
  komputerze, na którym MegaRuchacz był już wcześniej, niczego nie zmienia — tylko zapisuje, co jest
  zainstalowane (kopia zapasowa przechodzi ze swoimi dotychczasowymi ustawieniami, z wyjątkami).
- **Usuwanie całego MegaRuchacza.** Przycisk „Usuń MegaRuchacza…” w trybie zmiany zdejmuje wszystko, także
  aplikację przy zegarze i aktualizacje: zasady z plików Twoich narzędzi AI, pomocników, przypomnienia, serwer
  wyszukiwania i zadania w tle. Zostaje folder z MegaRuchaczem, Twoje dane (chyba że zaznaczysz „usuń też moje
  dane”), same rozmowy, Twoje skille, zrobione kopie zapasowe i mały zapis, że MegaRuchacza nie ma — dzięki
  niemu strażnik wywołany choćby z projektu wdrożonego kiedyś `wdroz.ps1` niczego nie dokłada z powrotem.
  Ponowne uruchomienie instalatora po usunięciu dokłada wszystko, razem z aplikacją przy zegarze.
- **Wiedza o Tobie bez Pamięci rozmów.** Same pliki z wiedzą i codzienne czytanie rozmów nie wymagają już
  modelu do wyszukiwania (496 MB): indeks rozmów chodzi wtedy w trybie „tylko tekst”. Włączenie Pamięci
  rozmów później liczy brakujące wektory w tle; jej wyłączenie przełącza indeks z powrotem na sam tekst.
- **Zasady pamięci jako dwa bloki: Lore i Wiedza.** Dotychczasowy jeden blok w `CLAUDE.md` i `AGENTS.md`
  Codeksa to teraz dwa (`MegaRuchacz:lore`, `MegaRuchacz:wiedza`), każdy przy swojej części. Strażnik zamienił
  stary blok sam, w tym samym miejscu — „Co wiem” i reszta pliku bez zmian. Polecenie „Cofnij” wskazuje wprost
  folder MegaRuchacza.
- **Strażnik i przypomnienia słuchają wyboru.** Dogrywają tylko to, co należy do włączonych części, i zdejmują
  nasze bloki i hooki części wyłączonych. Przypomnienie przy każdej wiadomości: zasady kierownika tylko
  z Trybem kierownika, linia o czytaniu rozmów z Wiedzą, „Z ARCHIWUM” z Pamięcią rozmów. Codzienne czytanie
  rozmów rusza tylko z Wiedzą. Uszkodzony zapis instalacji = jedna linia alarmu i nic nie jest zdejmowane.
- **Okno aplikacji przy zegarze pokazuje tylko to, co masz.** Zakładka Skille tylko ze Skillami, karta
  i przycisk czytania rozmów tylko z Wiedzą, linia kopii tylko z Kopią, Warstwy pamięci tylko z warstwami
  zainstalowanych części. Bez Wiedzy nie ma alarmu „nauka z rozmów stoi”, a rachunek mówi „moduł Wiedza nie
  jest zainstalowany” zamiast „cykl nie miał okazji się odpalić”. Uszkodzony zapis instalacji to czerwona karta.
- **Kopia zapasowa bierze ustawienia z zapisu instalacji** — dokąd, co i czego nie kopiować, wybrane
  w oknie. Komputery sprzed instalatora kopiują jak dotąd (`narzedzia\kopia-zapasowa-domyslne.json`).
- **Fakty nie trafiają już do bloku kierownika:** sekcja „Co wiem” kończy się na każdym znaczniku MegaRuchacza.
- **Poprawki z próby całości instalatora.** Próba szła przez okno z prawdziwymi skryptami na kopii katalogu
  domowego (`instalator\test-calosci.ps1`): nowa instalacja, zmiany, usuwanie bez i z danymi, ponowna
  instalacja — prawdziwe ustawienia i zadania Harmonogramu zostały nietknięte. Wyszło przy niej: programy
  instalują się teraz przed aplikacją przy zegarze (na komputerze bez gita ten krok padał zawsze, także po
  „Spróbuj ponownie”); tryb zmiany dokłada aplikację przy zegarze, gdy jej brakuje; Tryb kierownika zdejmuje
  role Codeksa z `~\.codex`, gdzie je założył (wcześniej szukał ich w katalogu Codeksa Orki, gdy instalator
  ruszał z jej okna); skrypty pracujące na innym katalogu domowym niż Twój nie sięgają już do Twojej
  konfiguracji Codeksa i Lore przez zmienne środowiska.
- **`instaluj.bat` w ZIP-ie z GitHuba ma zawsze końce linii Windows** (`.gitattributes`) — bez tego `cmd`
  potrafi nie znaleźć etykiety w pliku z ZIP-a.
- Po aktualizacji na drugim komputerze aplikację przy zegarze trzeba raz uruchomić od nowa (jak po każdej
  zmianie jej okna).

## 0.26.0 — 2026-10-02

- **Codzienna kopia zapasowa na Dysk Google** (`narzedzia\kopia-zapasowa.ps1`, zadanie Harmonogramu
  `MegaRuchaczKopia`, codziennie o 12:30, a przegapiona rusza sama po włączeniu komputera). Kopiuje `C:\dev`
  oraz pliki Claude'a i Codeksa. Pierwsza kopia jest pełna, każda następna trafia do osobnego katalogu dnia
  i zawiera tylko pliki nowe i zmienione. Niczego nie nadpisuje i nie kasuje. Plik z samymi zerami w środku
  (uszkodzony zanikiem prądu) nie trafia do kopii, bo zdrowa wersja zostaje w starszej, a w dzienniku kopii
  staje ALARM. Bazy SQLite kopiuje bezpiecznie także wtedy, gdy są otwarte. Hasła i klucze idą do kopii tylko
  na wyraźne życzenie (`-ZSekretami`), pliki logowania nigdy. `-Proba` pokazuje, co by skopiowała, i nic nie
  zapisuje. Plik, który zniknął w trakcie kopii (np. sprzątnięty katalog roboczy agenta), to uwaga, nie błąd.
- **Okno nadzorcy pokazuje stan kopii zapasowej.** W karcie „Stan” na Przeglądzie jest jedna linia, np.
  „Kopia zapasowa: dziś o 12:30, 368 plików (445 MB), bez błędów.”. Na czerwono, z kartą „Wymaga działania”
  i dymkiem raz na dobę, gdy ostatnia udana kopia jest starsza niż dwie doby albo gdy kopia pominęła pliki,
  które nadal są uszkodzone. Pliki już naprawione dają tylko żółtą linię: wejdą do następnej kopii same.
  Szczegóły mają osobną kartę: ostatnia udana kopia, ostatni przebieg, lista pominiętych plików, błędy,
  gdzie leży kopia i jej dziennik, kiedy włącza się alarm i dlaczego. Przez pierwszą godzinę po włączeniu
  komputera stara kopia jest tylko żółta, bo zaległa właśnie rusza. Na komputerze bez kopii linia mówi „nie
  jest ustawiona” i nie ma alarmu. Przegląd bez spraw do uwagi nadal mieści się bez przewijania.
- **Skille nie mają już „kopii zapasowych” z zer.** 02.10 sprawdzenie skilli zapisało pliki jednego skilla
  tuż przed zanikiem prądu. Zostały same zera, a następna aktualizacja zrobiła z nich kopię zapasową. Teraz
  wyzerowany skill jest błędem w zakładce Skille („uszkodzony (same zera) – do naprawy”) i pilną sprawą na
  Przeglądzie. Kopii z niego nie robi nic. Codzienne sprawdzenie go nie rusza, a „Aktualizuj teraz” pyta
  osobno i wgrywa wersję od autora. „Cofnij” pomija wyzerowane kopie i przywraca starszą zdrową, a gdy takiej
  nie ma, odmawia i mówi dlaczego. Do sprawdzania zer służy ta sama reguła, co w kopii zapasowej, więc obrazy,
  czcionki i teksty w UTF-16, które mają zera z natury, nie dają fałszywego alarmu.
- **Uszkodzona kopia źródła skilli naprawia się sama.** Wyzerowany plik w wewnętrznej kopii repozytorium
  autora (było: „index file corrupt”, ponawiane sześć razy jak błąd sieci przez cztery minuty) jest teraz
  rozpoznawany od razu i kopia jest pobierana od nowa. Bez sieci to błąd źródła, a skill zostaje nietknięty.
  Z kopii źródła z zerami nic nie jest wgrywane.

## 0.25.2 — 2026-10-02

- **Pliki pamięci nie mogą już zostać wyzerowane przez zanik prądu — a gdyby jednak, nic na nich nie
  powstaje.** 02.10 o 08:03 poranny cykl wiedzy zapisał CLAUDE.md i jedenaście plików w `wiedza\`, a pół
  minuty później komputer zgasł bez zamknięcia (Kernel-Power 41). Po restarcie te pliki miały pełną
  długość i w środku same zera; strażnik dokleił do zer bloki zasad i zrobił „kopię zapasową” zer.
  Teraz cykl (`lore`), strażnik, `wpisz-zasady` i sam cykl dzienny zapisują każdy plik pamięci do pliku
  tymczasowego obok, wymuszają zapis na dysk i dopiero wtedy podmieniają stary plik. Zanik prądu
  zostawia więc stary albo nowy plik, nigdy zera. Dopisywanie (źródła faktów, poczekalnia) też idzie
  od razu na dysk.
- **Wyzerowany plik pamięci zatrzymuje wszystko i głośno to mówi.** Strażnik przy starcie okna pisze
  alarm jako pierwszą linię: który plik, ile zer, gdzie leży ostatnia zdrowa kopia i jakim poleceniem ją
  przywrócić. Do czasu przywrócenia nie wpisuje zasad, nie odświeża kopii dla opencode i nie rusza cyklu.
  Cykl wiedzy odmawia pracy, zanim cokolwiek przeczyta (stan „wyzerowane”; dozór nie ponawia go
  w kółko). `wpisz-zasady` odmawia, a kopii z wyzerowanego pliku nie robi nikt. Okno nadzorcy pokazuje
  pilny alarm „pliki pamięci są wyzerowane”.
- **Kopie dzienne „wczoraj” i „przedwczoraj”** (`~\.claude\mr\kopie-dzienne\`): CLAUDE.md, AGENTS.md
  Codeksa i opencode oraz pliki z `wiedza\`. Rotacja raz dziennie, zawsze przed cyklem wiedzy, i tylko
  ze zdrowych plików. Gdy któryś ma zera, rotacja staje i kopie zostają nietknięte. Przywrócenie
  wyzerowanych plików jednym poleceniem:
  `powershell -ExecutionPolicy Bypass -File C:\dev\claude-worker\narzedzia\kopie-dzienne.ps1 -Przywroc`
  (konkretny plik: `-Plik CLAUDE.md`, starsza kopia: `-Skad przedwczoraj`, stan kopii: `-Stan`).
  Obecny stan pliku zostaje przed przywróceniem jako dowód.

## 0.25.1 — 2026-10-01

- **Zakładka Skille już nie miga przy rozwijaniu grup.** Każde kliknięcie grupy budowało dotąd całą
  listę od nowa (do 333 elementów), a w trakcie lista znikała kawałkami: zmierzone 43–66 wymazań tła
  widocznych na ekranie, zanim tekst się dorysował, i 0,7–3,9 s, w których okno nie reagowało.
  Teraz grupa buduje się raz, a kolejne kliknięcia tylko ją chowają i pokazują; ekran zmienia się
  jednym ruchem, gdy wszystko jest gotowe (0 wymazań w trakcie, jedno odmalowanie listy naraz).
  Zwijanie i ponowne rozwijanie trwa 35–105 ms, pierwsze rozwinięcie dużej grupy ok. 0,3–0,5 s.
  Przewinięcie listy zostaje tam, gdzie było; wygląd bez zmian.

## 0.25.0 — 2026-10-01

- **Skille „spoza bazy” rozpoznane — 38 z 42 jest teraz pod opieką i aktualizuje się samo.**
  Źródła znalezione po wiadomości z 26.08 (linki do repozytoriów) i porównaniu treści plików:
  33 skille `vc-*` pochodzą z withkynam/vibecode-pro-max-kit, 5 (defuddle, json-canvas,
  obsidian-*) z kepano/obsidian-skills. Oba źródła są w bazie z opisami po polsku; vibecode — wszystkie
  aktualne, obsidian — defuddle w starszej wersji (podmieni się przy codziennym sprawdzeniu, z kopią).
- **Zakładka Skille dzieli resztę na trzy grupy:** „Twoje własne skille” (connecting-to-magazyn2,
  sqp-slowa-kluczowe — powstały w Twoich rozmowach), „Z innych źródeł, poza opieką” (orchestration —
  z aplikacji Orca, aktualizuje go narzędzie „skills”; synced — kopia skilli z konta claude.ai, którą
  dogrywa sam Claude Code) i „Źródło nieznane” (to, czego nie da się przypisać — bez zgadywania).
  Każdy skill da się kliknąć: do czego jest, skąd jest, gdzie leży.
- **„Spakuj do przekazania”** przy Twoich własnych skillach: plik ZIP na Pulpicie (albo w Pobranych)
  z wybranym skillem albo wszystkimi własnymi i instrukcją `JAK-ZAINSTALOWAC.txt` po polsku. Przed
  spakowaniem sprawdzane są hasła, klucze, tokeny, adresy IP, loginy i maile — jeśli są, paczka nie
  powstaje, a okno pokazuje plik i linię do poprawienia. Oba obecne własne skille zawierają adres IP
  komputera Magazyn2 (connecting-to-magazyn2 także klucz SSH i login), więc dziś paczka zostanie
  odmówiona, dopóki tych miejsc nie zastąpisz opisem.

## 0.24.1 — 2026-10-01

- **Fakt przechodzi do wiedzy stałej także wtedy, gdy Claude go użyje — nie musisz się powtarzać.**
  Dotąd fakt z „Bieżące” awansował tylko, gdy padł w dwóch różnych rozmowach. Teraz wystarczy też,
  że Claude go użyje w innym dniu i w innej rozmowie niż ta, w której fakt padł (powtarzanie w tej
  samej rozmowie albo tego samego dnia nic nie potwierdza). Ostrożnie przy darmowym sprawdzaniu
  słów: do awansu liczy się tylko mocne słowo faktu (np. numer sprawy, kod, cytat) — dwa słabe
  słowa utrzymają fakt w stałej, ale go nie awansują. Limit 3 awansów na przebieg zostaje.
  Na obu komputerach po aktualizacji: `instaluj-globalnie.ps1` (nowe zdanie w zasadach).

## 0.24.0 — 2026-10-01

- **README „po ludzku” i schemat pamięci.** Na górze README stoi prosty opis całości: workerzy,
  pamięć, codzienna nauka i gdzie trafia wiedza, droga faktu, aplikacja w zasobniku, aktualizacje,
  koszt, dwa komputery. Do tego jednostronicowy schemat drogi faktu `docs/schemat-pamieci.html` —
  pobierasz i otwierasz w przeglądarce. Poprawione stare, sprzeczne zapisy dalej w README (90 dni,
  „1% kosztu”).
- **Fakt w wiedzy stałej trzyma się dzięki temu, że Claude go używa.** Fakt dopisany przez automat
  zasypia dopiero po 180 dniach bez użycia i bez wzmianki (było: 90 dni bez wzmianki — trzeba było
  go powtarzać). Użycie budzi uśpiony fakt. Śpiące ponad 2 lata przechodzą do rocznego archiwum
  `wiedza\uspione-archiwum-RRRR.md` — nic nie jest kasowane. Wpisy ręczne dalej nie zasypiają nigdy.
- **Użycie faktu sprawdzane za darmo.** Codzienny przebieg szuka w pełnych odpowiedziach i działaniach
  Claude'a charakterystycznych słów faktu (numery spraw, kody, nazwy plików, cytaty — tylko takie,
  które wskazują ten jeden fakt). 0 tokenów, dzień rozmów czyta się poniżej sekundy. Zwykłe słowa się
  nie liczą: lepiej przeoczyć niż trzymać przy życiu martwy fakt. Dodatkowo model przy codziennym
  czytaniu rozmów zaznacza, których faktów użyto (najwyżej ~2,6 tys. tokenów dziennie, dziś 0).
- **Bez alarmu długiej rozmowy** (Twoja decyzja: linia przychodziła dopiero po wysłaniu wiadomości,
  kiedy koszt już poszedł). Znikła linia „taniej będzie nowe okno” w rozmowie i przy wznowieniu okna
  oraz lista najdłuższych rozmów z „!” w oknie nadzorcy. Karta „Ile tokenów naprawdę zużywasz” ma
  dwie kolumny — przy najdroższych zadaniach workerów widać też rolę i projekt. Na drugim komputerze
  po aktualizacji: restart nadzorcy i `instaluj-globalnie.ps1`.

## 0.23.1 — 2026-09-30

- **Okno nadzorcy znów liczy w tle — koniec z fałszywym alarmem antywirusa.** Po aktualizacji
  sygnatur (30.09) Microsoft Defender brał sposób, w jaki okno liczyło swoje dane w tle, za narzędzie
  do omijania zabezpieczeń PowerShella (fałszywy alarm na naszym własnym kodzie) i wywracał to
  liczenie — na komputerze domowym padał dozór co kwadrans oraz ekran ładowania okna, a w biurze
  czekało to samo po najbliższej aktualizacji. Liczenie przebudowane na zwykły, przejrzysty sposób:
  każdy krok liczy się w osobnym, niewidocznym procesie `powershell.exe` (skrypt `licz-krok.ps1`),
  bez konstrukcji, które antywirus bierze za podejrzane. Okno wygląda i działa tak samo jak wcześniej:
  stały rozmiar, ekran ładowania z krokami, limity czasu, drugie otwarcie dnia od razu z kartami.

## 0.23.0 — 2026-09-30

- **Taniej na tokenach — bez drogich workerów.** Koniec z workerem „general-purpose” (ładował
  ~153 tys. tokenów na start zamiast ~23 tys.); do zadań z wyglądem jest nowa rola `projektant`
  (narzędzia implementera + skille). Zastępca, wbudowani pomocnicy (poza `claude-code-guide`,
  który ma własny, tańszy model) i codzienne wyciąganie faktów z rozmów chodzą na Sonnecie.
  Kierownik zostaje na modelu, który wybrałeś.
- **Workerzy równolegle, wielu naraz — także bez kopii roboczych.** Każdy na swoich plikach;
  dziennik zmian, mapę i wysyłkę na GitHuba robi kierownik na koniec rundy. Verifier tylko przy
  ryzyku, zastępca na Twoją prośbę, wygląd najpierw uzgadniany w rozmowie. Stałe zasady pracy
  w tym repo stoją w `CLAUDE.md` — workerzy dostają je sami, bez przepisywania w każdym zleceniu.
- **Ostrzeżenie o długiej rozmowie.** Każdy krok Claude'a czyta całą rozmowę, więc długa kosztuje
  przy każdym kroku. Od 300 tys. tokenów kierownik dostaje jedną linię „taniej będzie nowe okno”
  (potem co +100 tys. i po przerwie ponad godzinę); strażnik mówi to samo przy wznowieniu rozmowy.
  Powiadomienia „worker skończył” nie dostają już doklejek (dotąd co czwarta szła do nikogo).
- **Okno nadzorcy: ile tokenów naprawdę zużywasz** — dziś i średnio z 7 dni, Twoje rozmowy
  kontra workerzy, najdroższe zadania i najdłuższe rozmowy; pełne liczby w Szczegółach. Rachunek
  dzienny zaniżał tekst pisany przez Claude'a 3,8 raza — poprawione. Wykres kosztu czytania rozmów
  z 30 dni przeszedł do Szczegółów, więc Przegląd znów mieści się bez przewijania.
- **Alarm „MegaRuchacz kosztuje dużo” liczy tokeny, nie procent** — drogo od ~15 000 tokenów przy
  otwarciu okna rozmowy (dziś ~9 100). Procent zależał od tego, ile dokładają dodatki, i po zmianie
  u administratora proxy dałby fałszywy czerwony alarm; dalej widać go w oknie.
- **Aktualizacja nie staje już przez „niezapisane zmiany”.** Strażnik pobiera nowszą wersję mimo
  raportów, rejestru i innych plików roboczych tej maszyny (odkłada je na bok i oddaje po
  pobraniu). Odmawia tylko wtedy, gdy nadpisałby czyjąś pracę — i mówi, które pliki blokują.
  Rejestr pracy (`worklog.md`) nie jest już w gicie: każdy komputer ma swój. Komputer, który przez
  ten błąd stoi na starej wersji (dom od 28.09), nie pobierze poprawki sam — raz trzeba go
  odblokować ręcznie, potem pobiera już sam.
- **Codex tylko tam, gdzie go chcesz.** Instalator i strażnik nie zakładają ról i hooków Codeksa
  bez pytania — tylko tam, gdzie MegaRuchacz już je założył, z flagą `-Codex` albo z linią
  `codex: tak` w pliku wersji projektu; inaczej jedna linia „pominięte”. Literówka we fladze
  instalatora kończy się błędem, zamiast po cichu przepaść.
- **Rachunek nie pokazuje liczby policzonej starym kodem** — po zmianie w którymkolwiek jego pliku
  okno mówi „przelicza się”. Rola `projektant` liczy się w pomiarze otwarcia okna i jest
  w instalatorze wszędzie (także w `-Usun` i samosprawdzeniu).
- **Porządek w kodzie, działanie bez zmian.** Rachunek (`narzedzia\koszt-pamieci.ps1`) podzielony
  na 14 modułów w `narzedzia\koszt\`, okno nadzorcy na 22 w `zasobnik\nadzorca\` — workerzy czytają
  jeden kawałek zamiast plików po 250 KB. Sprawdzone testami równoważności (212 przypadków
  rachunku; wydruki i 47 zrzutów okna przed/po bez różnic). Brakujący albo uszkodzony plik =
  odmowa z powodem, a nie liczenie z dziurą. Mapa projektu o połowę krótsza (historia rozpoznań
  w `.megaruchacz\mapa-archiwum.md`).
- Commity w repo bez linii `Co-Authored-By` — jak w projekcie WMS. Po aktualizacji potrzebny
  restart nadzorcy (do restartu stare okno mówi przy koszcie „nie znam progu”).

## 0.22.4 — 2026-09-30

- **Okno nadzorcy otwiera się spokojnie.** Przyczyna „dzikiego” otwierania rano (nagrana zrzutami
  co 200 ms): okno wstawało za niskie (liczone dla pustych kart), potem na ~4 s przestawało
  reagować, bo liczyło dane w swoim wątku, a gdy dane doszły — rosło o ~260 px i przesuwało się,
  a po kolejnych 3 s karty przestawiały się jeszcze raz. Teraz okno ma od pierwszej chwili stały
  rozmiar i samo go nie zmienia (staje tam, gdzie je ostatnio zostawiono).
- **Ekran ładowania z listą kroków.** Dopóki zakładka nie ma kompletu danych z dziś, zamiast niej
  stoi karta „Wczytuję dane” z paskiem postępu i krokami („Liczę koszt otwarcia okna rozmowy”,
  „Sprawdzam dzienne zużycie tokenów”, „Sprawdzam skille”…): kółko — czeka, kręcący się znak —
  liczy (z sekundami), ptaszek — gotowe. Karty pokazują się raz, w komplecie. Dotyczy wszystkich
  zakładek.
- **Liczenie w tle — okno reaguje od razu.** Wszystko, co woła skrypty (rachunek, pomiar otwarcia,
  zużycie, rozbicie, warstwy, skille, przebieg dozoru co kwadrans), liczy się w osobnych wątkach.
  Okno można w tym czasie przesuwać i przełączać zakładki.
- **Drugie otwarcie tego samego dnia — od razu karty**, bez ekranu ładowania; liczby starsze niż
  kwadrans odświeżają się po cichu i karta odmalowuje się raz, na końcu.
- **Krok, który się nie uda, mówi o tym przy sobie** (czerwony krzyżyk i powód po ludzku), reszta się
  ładuje, a ekran ładowania schodzi po 5 s (albo od razu przyciskiem). Każdy krok ma limit czasu
  wynikający z limitów tego, co woła (np. rachunek 180 s, pomiar 150 s, zużycie 60 s + 30 s) — po nim
  jest przerywany. Ekran ładowania, który mimo to by stał, zdejmuje strażnik i zostawia żółtą kartę.

## 0.22.3 — 2026-09-30

- **Skille w grupach zwijanych.** Zakładka „Skille” pokazuje na starcie same grupy (źródła):
  nazwa, jedno zdanie opisu i liczby — ile skilli, ile masz, ile ma nowszą wersję, ile ma problem
  (plus zmienione ręcznie i usunięte przez autora, gdy są). Kliknięcie grupy rozwija ją; okno
  pamięta, co rozwinięte, do zamknięcia. Grupa z problemem ma czerwony pasek z lewej, z nowszą
  wersją do pobrania — bursztynowy. „Zainstalowane, spoza bazy” to też zwinięta grupa.
- **Pobranie ze źródła jest ponawiane 5 razy** (po 5 s, 15 s, 30 s, 1 min, 2 min), każda próba
  w dzienniku; błąd pobrania dopiero po ostatniej, z powodem po ludzku („pod adresem … nie ma
  repozytorium”, „brak internetu”…), widoczny przy grupie. Wszystkie źródła czekają naraz, więc
  bez internetu przebieg trwa ~4 min, nie 20. Błędy, które nie są siecią, nie są ponawiane.
- **Poranny błąd 2026-09-30 to nie była awaria sieci:** Matt Pocock przeniósł `implement-spec`,
  `pr` i `retro` z `in-progress` do `engineering` i usunął `resolving-merge-conflicts`.
  Teraz: skill przeniesiony przez autora MegaRuchacz sam znajduje w nowym miejscu i aktualizuje
  normalnie (z kopią); skill usunięty przez autora to szary stan „autor go usunął — Twoja kopia
  działa”, nic się nie kasuje samo, a przycisk „Usuń u mnie” kasuje go z kopią zapasową
  („Przywróć usunięty” cofa). Baza skilli wskazuje już nowe miejsca trzech przeniesionych.
- Naprawione: aktualizacja nie rusza już skilla, którego nowej wersji nie ma w kopii źródła
  (rano `retro` poszło do podmiany ze starą ścieżką — kopia zadziałała i skill był cały, ale nie
  powinno do tego dojść). `retro` jest już w najnowszej wersji autora.

## 0.22.2 — 2026-09-30

- **Koniec z workiem `do-nazwania.md` — każde zestawienie trafia do pliku z nazwą, która mówi,
  co w nim jest.** Model musi podać nazwę pliku (wymusza to i polecenie, i schemat odpowiedzi),
  dostaje listę istniejących plików wiedzy z opisami i dopisuje do pasującego, zamiast zakładać
  nowy. Gdy nazwy nie poda albo poda byle jaką („inne.md”), nazwa powstaje z pierwszych słów
  faktu (np. `konto-tailscale-przyklad.md`). Gdy i to się nie da — fakt zostaje w „Bieżących”,
  a podsumowanie cyklu zaczyna się od „UWAGA”. Pliku bez sensownej nazwy nie ma nigdy.
- **Nowy plik wiedzy powstaje zawsze razem ze swoim odsyłaczem w „Dane referencyjne”.**
  Odsyłacz nie czeka już na drugą rozmowę w „Bieżących” (stamtąd po 14 dniach znikał i plik
  zostawał bez śladu). Brak miejsca pod progiem 8 000 znaków = pliku nie zakładam, fakt zostaje
  w „Bieżących”, cykl to melduje. Nieudany zapis = pliki zestawień i odsyłacze wycofane.
- **Strażnik kompletności:** każdy cykl sprawdza, czy każdy plik z wiedzą w `~\.claude\wiedza`
  ma odsyłacz, i brakujący dopisuje sam (opis z nagłówka pliku); czego nie da rady — melduje.
  Przy otwarciu okna strażnik zasad mówi jedną linią, gdy któregoś odsyłacza brakuje.
  Bez odsyłacza z założenia zostają tylko pliki techniczne: `kandydaci.md`, `zrodla.md`,
  `historia-zmian.md`, `uspione.md`, `README.md` i pliki z kropką.
- Stary `do-nazwania.md` rozłożony na właściwe pliki (`amazon-ebay.md`, `maszyny.md`,
  `polaczenia-ssh.md`, nowe `sprawy-odblokowania-amazon.md` i `alibaba-konto-i-dostawcy.md`)
  i usunięty; dopisany brakujący odsyłacz do `amazon-ads-dostep-dane.md`.

## 0.22.1 — 2026-09-29

- **OpenDesign usunięty z bazy skilli** — na prośbę użytkownika. To osobna aplikacja do
  projektowania, a nie skille, więc nie ma czego pokazywać w zakładce „Skille”.

## 0.22.0 — 2026-09-29

- **Nowa zakładka „Skille” w oknie MegaRuchacza — polecane skille z opisem po polsku.**
  Baza (`skille\katalog.psd1`) ma 73 skille z pięciu zestawów: Superpowers, Impeccable,
  Taste Skill, Ponytail i skille Matta Pococka; przy każdym kilka słów, do czego jest.
  Szósty adres z listy, OpenDesign, to osobna aplikacja do projektowania, a nie skille —
  stoi w zakładce z wyjaśnieniem, nic się z niej nie instaluje. Działa samo po restarcie
  nadzorcy (przy najbliższym logowaniu do Windows) — `wdroz.ps1` nie jest do tego potrzebny.
- **Wykrywa, co już masz, i bierze to pod opiekę bez ruszania plików.** Każdy skill na dysku
  jest porównywany z całą historią źródła: najnowsza wersja, któraś starsza, albo
  „zmieniony ręcznie” (nie pasuje do żadnej wersji autora). Pierwszy przebieg na komputerze
  tylko spisuje stan — niczego nie podmienia.
- **Raz dziennie sam sprawdza źródła i pobiera nowsze wersje** skilli pod opieką — w tle,
  bez żadnego okna, odpalany przez nadzorcę (jedno sprawdzenie na dobę, znacznik dnia).
  Przed każdą podmianą robi kopię starej wersji (`~\.claude\mr\skille\kopie\`), a każda
  zmiana trafia do dziennika (`~\.claude\mr\skille\dziennik.log`): skąd, z której wersji
  na którą, kiedy. Skilla zmienionego ręcznie nie nadpisuje nigdy sam.
- **Przyciski w zakładce:** Zainstaluj, Aktualizuj teraz (przy skillu zmienionym ręcznie
  pyta o zgodę), Cofnij ostatnią aktualizację (przywraca kopię co do bajtu), Sprawdź teraz.
  Błąd sieci albo złe źródło widać na czerwono w zakładce i jako sprawę na Przeglądzie.
- Instaluje dla Claude Code (`~\.claude\skills`) i — gdy na komputerze jest Codex — dla
  Codeksa (`~\.agents\skills`); opencode czyta oba te katalogi sam. To samo z wiersza
  poleceń: `narzedzia\skille.ps1` (opis trybów w nagłówku pliku).

## 0.21.3 — 2026-09-28

- **Na starcie sesji nie pokazuje się już rachunek policzony starą wersją.** Po zmianie
  rachunku na procent otwarcia sesji okno Claude Code jeszcze przez dwie godziny
  pokazywało zapamiętaną linię ze starym alarmem („każda wiadomość dokleja ~313 tokenów
  (próg 300)”), bo była „świeża” wiekiem. Zapamiętana linia niesie teraz odcisk skryptu,
  który ją policzył; linia z innej wersji rachunku albo sprzed ponad doby się nie pokazuje —
  zamiast niej stoi „rachunek się przelicza”, a gdy przeliczenie się nie udało, mówi to wprost.
- **Codex dostaje własny rachunek.** Hook `-KosztCodex` pokazywał Codeksowi liczby Claude
  Code. Teraz czyta osobny zapis (`~/.claude/.megaruchacz-koszt-codex.txt`, liczony przez
  `koszt-pamieci.ps1 -Narzedzie Codex`); przeliczenie w tle liczy od razu oba rachunki.

## 0.21.2 — 2026-09-28

- **Przypomnienie i rejestr pracy w Codeksie na Windows znowu działają.** Codex 0.157
  uruchamia każdy hook przez `powershell -Command "..."`, a nie przez `cmd` — i ten
  PowerShell zjadał zmienne (`$p`, `$o`, `$we`) z naszych poleceń. Skutek: przypomnienie
  przy każdej wiadomości w ogóle nie docierało do modelu, a start i koniec workera nie
  trafiały do `.megaruchacz\worklog.md`. Trzy hooki (UserPromptSubmit, SubagentStart,
  SubagentStop) wołają teraz `node` wprost — sprawdzone w prawdziwej sesji Codeksa.
  Strażnik i instalator podmieniają stare polecenia same; po podmianie Codex prosi
  o jednorazowe zatwierdzenie hooków poleceniem `/hooks`.
- **Czarnych okien nie da się schować po stronie MegaRuchacza — i teraz wiadomo dlaczego.**
  Okno pojawia się tylko wtedy, gdy sam Codex działa bez konsoli; wtedy okno otwiera
  jego własny PowerShell-opakowanie, zanim nasze polecenie w ogóle ruszy, a do tego
  kilkanaście okien daje sam Codex (np. przy wywołaniach gita). Proponowane
  `conhost --headless` niczego tu nie ukrywa, a do tego ucina tekst hooka — nie weszło.
  Szczegóły i pomiary: `.megaruchacz\raporty\P11.md`.

## 0.21.1 — 2026-09-25

- **Codex dostaje zasady kierownika także w Orce.** Orka uruchamia Codeksa z własnym
  katalogiem ustawień, ale przy każdym starcie sama kopiuje do niego `~/.codex/AGENTS.md`
  — wystarczy więc, że zasady są tam. Instalator i strażnik uznają Codeksa za obecnego
  także wtedy, gdy jest tylko katalog Orki. Do katalogu Orki nic nie piszemy (własny plik
  zablokowałby jej kopiowanie na zawsze).
- **opencode dostaje swój wariant zasad i dalej widzi „Co wiem”.** Na maszynie z Claude
  Code powstaje `~/.config/opencode/AGENTS.md` — kopia `~/.claude/CLAUDE.md` z blokiem
  kierownika w wersji dla opencode. Strażnik odświeża ją przy każdym starcie sesji, bo
  „Co wiem” zmienia się codziennie. Twojego własnego pliku o tej nazwie nie rusza.
- **Strażnik pilnuje bloku kierownika i nie milczy.** Gdy blok zniknie z `~/.claude/CLAUDE.md`
  albo `~/.codex/AGENTS.md`, wpisuje go z powrotem we właściwym wariancie i mówi o tym
  jedną linią. Gdy nie umie (brak szablonu, dubel) — też to mówi, zamiast udawać, że gra.
  Istniejącego bloku nie podmienia; wariant dla `CLAUDE.md` zapisuje odtąd instalator.

## 0.21.0 — 2026-09-25

- **Claude Code dostaje wreszcie swoje zasady kierownika.** Od 0.19.0 do każdej sesji
  Claude Code szła wersja pisana dla opencode/Codeksa („rozdaj naraz i czekaj”, „nie ma
  worktree”) — sprzeczna z tym, jak Claude Code naprawdę działa. Teraz instalator
  wybiera wariant według narzędzia: `~/.claude/CLAUDE.md` dostaje wersję Claude Code
  (nowe źródło: `szablony-global\claude\zasady-kierownika.md`), a `~/.codex/AGENTS.md`
  i maszyna bez Claude Code — dotychczasową wersję opencode/Codex, bez zmian.
  Wymuszenie: `instaluj-globalnie.ps1 -WariantZasad claude|opencode`.
- **Jeden komplet zasad zamiast dwóch sprzecznych.** Projektowy `CLAUDE.md` tego repo
  ma już tylko „Cisza jest zakazana”; zasady kierownika odchudzone (dublety wyrzucone,
  wpadki z 16 i 25 września zostają). Start sesji w tym repo: ~11 940 → ~6 870 tokenów;
  w innych projektach ~6 850 → ~6 290. Przypomnienie przy każdej wiadomości:
  ~207 → ~115 tokenów.
- **Rejestr, mapa i raporty w jednym miejscu: `.megaruchacz\`** — także we wdrożeniach
  per projekt pod Claude Code. W tym repo mapa i rejestr kierownika przeniesione
  i scalone.
- **Role Claude Code z jednego źródła** (`szablony-global\claude\agents`): limit raportu
  i „WYMAGA DECYZJI / SendMessage” stoją w rolach, scout ma narzędzie do zapisu mapy.
- **Rachunek za pamięć liczy `CLAUDE.md` projektu** (przy `-Projekt`), a zakładka
  warstw pokazuje mapę i rejestr z `.megaruchacz\`.
- Instalator odmawia zapisu, gdy w pliku są dwa bloki kierownika (dubel), i sprawdza,
  że blok jest dokładnie jeden i w dobrym wariancie.

## 0.20.1 — 2026-09-25

- **Automat nie flaguje już ścieżek z drugiego komputera.** Ścieżka opisana jako
  „na domowej”, „w domu” albo „<login-domowy>” nie dostaje znacznika „niepotwierdzone” tylko
  dlatego, że nie ma jej na tym komputerze.

## 0.20.0 — 2026-09-24

- **Nauka czyta tylko najsilniejszy sygnał.** Z Twoich wiadomości bierze wyłącznie
  poprawki („nie tak”, „mówiłem”), rzeczy powtórzone w innej rozmowie i „zapamiętaj”
  — plus koniec odpowiedzi, na którą reagujesz. Próba na ostatnim tygodniu: 28
  wiadomości zamiast 66, materiał 11 tys. znaków zamiast 64 tys. Stare zaległości
  puszczone — nauka zaczyna od teraz.
- **Pomiar skuteczności nauki**: `~\.claude\wiedza\.nauka-skutecznosc.txt` — ile
  wybrała, ile faktów wpisała i ile z nich przetrwało 14 dni.
- **Nowe okno nadzorcy**: przełącznik Przegląd/Szczegóły, karty kosztów, wykres
  kosztu nauki z 30 dni, sumy 7/30 dni i koszt zwykłego dnia.
- **Alarmy mówią, za co i za jaki okres.** Nadrabianie zaległości to żółta informacja,
  nie czerwony alarm. Czerwony próg zwykłego dnia nauki: 350 000 tokenów (zmierzone:
  ~62 500 na jedno wywołanie modelu). Alarm „jedna pozycja to X% rachunku” odzywa
  się tylko, gdy cały rachunek przekracza swój próg — wcześniej świecił bez powodu.
- **Bez podwójnych hooków**: przypomnienie i zasady wchodzą raz, nie dwa.

## 0.19.0 — 2026-09-24

- **Instalacja GLOBALNA: `narzedzia\instaluj-globalnie.ps1`.** Jedna komenda dla
  calego komputera. Role, zasady i rejestr dzialaja od razu w **kazdym** projekcie,
  bez wdrazania po kolei. Stan pracy (rejestr, mapa) nadal laduje w projekcie,
  w `.megaruchacz\` - zaklada go pierwszy worker, gdy zajdzie potrzeba, wiec nic
  nie zalega bezczynnie.
- **Trzy narzedzia naraz:**
  - opencode: role w `~/.config/opencode/agents`, wtyczka rejestru w `~/.config/opencode/plugins`.
  - Claude Code: role w `~/.claude/agents`, rejestr i hooki w `~/.claude/settings.json`,
    worktree ustawiony globalnie.
  - Codex: zasady w `~/.codex/AGENTS.md`, rejestr i hooki w `~/.codex/hooks.json`.
  - Zasady dla wszystkich trzech leca przez `~/.claude/CLAUDE.md` (Claude Code
    i opencode) oraz `~/.codex/AGENTS.md` (Codex), blokiem `MegaRuchacz:kierownik`.
- **`-Usun`** zdejmuje wszystko, co instalacja zalozyla. **`-Proba`** pokazuje plan.
- **Konflikt globalne/per-projekt rozwiazany.** `wdroz.ps1` po instalacji globalnej
  nie wdrazia nic w projekcie (znacznik `~/.claude/.megaruchacz-global`) - inaczej
  rejestr i zasady szlyby dwa razy. Obejscie: `-WymusProjektowo`.
- **Zweryfikowane na prawdziwym opencode i Claude Code** (na tymczasowym katalogu
  domowym): opencode widzi cztery nowe role i laduje wtyczke; rejestr Claude pisze
  do `.megaruchacz/worklog.md` w wybranym projekcie; `-Usun` czysci.
- **Znany dlug:** globalny rejestr Codeksa nie zna projektu z gory - bierze go
  z `CODEX_PROJECT_DIR` albo biezacego katalogu, wiec wymaga potwierdzenia na
  maszynie z Codeksem. Role Codeksa zapisane jako pliki w `~/.codex/agents/`,
  ale dzisiejszy Codex deklaruje role w `config.toml` - do sprawdzenia.

## 0.18.0 — 2026-09-18

- **Tryb workerow działa w opencode.** Trzeci obok Claude Code i Codeksa. Role
  (implementer, scout, verifier, zastepca) ladują do `.opencode/agents/*.md`,
  a rejestr pracy prowadzi **wtyczka** `.opencode/plugins/mr-log.js` - opencode
  laduje ja sam przy starcie, więc **nic nie trzeba zatwierdzać** (inaczej niż
  hooki Codeksa z `/hooks`). Wtyczka slucha zdarzen sesji podagentow i dopisuje
  START/KONIEC do `.megaruchacz/worklog.md`, tego samego pliku co pod Codeksem.
- **Zasady dla obu narzedzi w jednym miejscu.** AGENTS.md czyta i opencode,
  i Codex, więc blok zasad jest wspolny. Gdy na maszynie sa oba narzedzia,
  wygrywa wariant opencode - opisuje oba sposoby pisania rejestru.
- **Straznik odswieza tez czesc opencode.** Role i wtyczka nanosza sie same przy
  podbiciu wersji, bez zatwierdzania. `.megaruchacz/` jest wspolny dla Codeksa
  i opencode, dlatego straznik rozpoznaje narzedzie po jego katalogu w projekcie
  (`.codex/`, `.opencode/`) albo po poleceniu w PATH - nie po samym `.megaruchacz/`.
- **Granice trybu pod opencode** (w `szablony-opencode/CZYTAJ.md`): brak pracy
  w tle, brak izolacji przez worktree, `edit: deny` blokuje narzedzia zapisu,
  ale nie bash. To te same ograniczenia co pod Codeksem, z jedna roznica:
  nic nie wymaga zatwierdzania.
- **Znany dług:** Lore nie indeksuje jeszcze rozmow z opencode - w opencode
  przeszukuje historie Claude Code i Codeksa. Czytnik bazy `opencode.db` to
  osobna robota.

## 0.1.1 — 2026-09-16

- **Sprostowanie w README.** Poprzednia wersja twierdziła, że Codex nie ma
  workerów. To było mylące: Orca obsługuje Codeksa jako pełnoprawny silnik
  workera (`orca worktree create --agent codex`, `orca orchestration
  worker-start --agent codex`), z osobnym środowiskiem i wpiętymi hookami.
  Bez workerów jest wyłącznie Codex uruchomiony samodzielnie, poza Orką.
- Ustalona ścieżka sesji Codeksa na potrzeby przyszłego czytnika historii:
  `~/.codex/sessions` (Orca sama wskazuje ten katalog). Na maszynie biurowej
  katalog nie istnieje — brak odbytych sesji.
- Dopisany dług: cięcie tekstu na kawałki leci po liczbie znaków, w pół słowa,
  a limit 1500 znaków nie jest powiązany z limitem modelu — przy gęstym tekście
  końcówka może być po cichu obcinana.

## 0.1.0 — 2026-09-16

Pierwsza wersja w repozytorium. Do tej pory całość żyła w dwóch osobnych
katalogach na jednej maszynie.

**Scalenie**
- Tryb pracy MegaRuchacz i serwer historii rozmów połączone w jeden projekt.
- Kod historii wszedł bez środowiska Pythona i bez bazy — to rzeczy odtwarzalne.

**Zasady kierownika** (`CLAUDE.md`)
- Sprzątanie po workerach: udana zmiana jest scalana do `main`, kopia robocza
  kasowana. Użytkownik nie ogląda wiszących gałęzi.
- Gałąź bez własnych commitów kasowana bez pytania.
- Twardy limit raportu workera — 5 linii, dłuższe rzeczy do pliku.
- Worker może zadać blokujące pytanie zamiast zgadywać albo kończyć z połową roboty.
- Reguły postępowania, gdy worker zawiedzie albo zamilknie; zielony raport
  przestaje być dowodem.
- Wzorzec zlecenia dla wielu niemal identycznych zadań.

**Historia rozmów**
- Załatana luka: sesje Claude'a odpalane przez Orkę zapisują się poza indeksowanym
  katalogiem i dotąd przepadały. Odzyskane 3830 fragmentów z okresu 10.08–11.09.

**Porządki przed publikacją**
- Usunięta zaszyta na sztywno ścieżka do prywatnego projektu (skrypt i panel).
- Panel VS Code radzi sobie z pustym ustawieniem ścieżki repozytorium — spada
  na folder otwarty w edytorze.
- `.gitignore`, README, logo.

**Znany dług**
- Brak testów w części odpowiadającej za historię rozmów.
- Czytnik transkryptów Codeksa jeszcze nie istnieje — brak próbek do oparcia się.
- Panel ma zaszytą ścieżkę do skryptu i działa tylko przy repozytorium
  w konkretnej lokalizacji.
- Wpisy w rejestrze pracy dublują się — hook zapisuje każdą linię dwa razy.

## 0.1.2 — 2026-09-16

- **Przeprowadzka serwera historii do repozytorium.** Kod przeniesiony z osobnego
  katalogu do `historia/`, środowisko postawione na nowo, serwer MCP i zadanie
  harmonogramu przestawione na nową ścieżkę, stary katalog usunięty. Baza leży
  poza projektem, więc nie została ruszona.
- **Indeksowanie co 10 minut** zamiast co 30.
- Potwierdzone działanie łatki na lukę z Orką: do bazy weszły 3830 fragmentów
  rozmów, które dotąd przepadały. Baza urosła z 47 151 do 52 322 fragmentów.
- Commity podpisane właściwym adresem autora.

## 0.2.0 — 2026-09-16

- **Grupowanie wypowiedzi w kawałki indeksu.** Dotąd każda wypowiedź trafiała do
  bazy osobno, więc krótkie „tak, rób to" stawało się samodzielnym wpisem
  z własnym wektorem — semantycznie pustym, bo pytanie zostawało w innym wpisie.
  Teraz kolejne wypowiedzi z tej samej sesji są sklejane w jeden kawałek do 1500
  znaków, z zaznaczeniem, kto co powiedział. Para pytanie-odpowiedź zostaje razem.
- **Ostatnia grupa czeka na domknięcie.** Indekser nie zapisuje grupy, do której
  może jeszcze coś dojść, i nie przesuwa za nią punktu wznowienia — dzięki temu
  podział na kawałki nie zależy od tego, kiedy akurat przebiegło indeksowanie.
  Ogon domykany jest po 24 godzinach bez zmian w pliku.
- **Pierwsze testy w projekcie** — 13 sztuk (`uv run pytest`). Pokrywają sklejanie,
  limit długości, zakładkę przy długich wypowiedziach, brak duplikatów przy
  powtórnym indeksowaniu i wznowienie po dopisaniu linii.
- Zasady kierownika: obowiązkowy krok policzenia niezależnych części zadania
  przed rozdaniem workerów.

**Uwaga:** zmiana obowiązuje dla danych indeksowanych od teraz. Starsze wpisy
zostają pocięte po staremu — przebudowy bazy nie robimy.

## 0.3.0 — 2026-09-16

- **Moduł historii rozmów nazywa się teraz `lore`.** Zmiana obejmuje katalog,
  pakiet, pliki, nazwy narzędzi MCP (`lore_search`, `lore_context`, `lore_stats`,
  `lore_reindex`) oraz całe wewnętrzne nazewnictwo i komentarze — z polskiego na
  angielski. Żadne zachowanie się nie zmieniło.
- **Migracja istniejących danych, bez przebudowy.** Baza `historia.db` przeniesiona
  na `lore.db`, tabele i kolumny przemianowane, wartości ról przetłumaczone,
  katalog modelu `historia_modele` na `lore_models` (inaczej 465 MB pobierałoby się
  od nowa). Migracja jest idempotentna i działa też na bazie już nowej.
  Zachowane wszystkie 52 626 kawałków i 621 plików.
- Zmienna środowiskowa `LORE_HOME`, ze wsteczną obsługą `CLAUDE_HISTORIA_HOME`.
- **5 nowych testów migracji** — razem 18.
- Przerejestrowany serwer MCP (`historia` → `lore`) i zadanie harmonogramu
  (`ClaudeHistoriaIndeks` → `LoreIndex`).

## 0.4.0 — 2026-09-16

- **Mapa projektu ma żyć.** Dopisywanie znalezisk do `.claude/mapa.md` jest teraz
  obowiązkiem scouta, nie kierownika — scout czyta mapę przed szukaniem i dopisuje
  do niej przed oddaniem raportu. Wcześniej zasada mówiła, że mapę uzupełnia
  kierownik „raportami scouta", więc w praktyce nie uzupełniał jej nikt i każdy
  worker startował na zimno.
- **Pierwszy kontakt z nieznanym projektem** = jeden scout na szkielet mapy,
  zanim ruszy jakiekolwiek zadanie.
- **Twierdzenia o mechanice narzędzi dostają datę sprawdzenia**, plus regułę:
  jeśli coś zachowuje się inaczej, niż mówią zasady — powiedzieć to głośno,
  zamiast po cichu się dostosować.
- **Lore używane odważniej** (globalne ustalenia): jedno wyszukanie na starcie
  każdego niebanalnego zadania, zamiast tylko trzech wąskich wyzwalaczy.
- **Nowa reguła zapisywania wiedzy**: gdy użytkownik wyjaśnia coś trwałego, czego
  nie ma w plikach, agent sam proponuje zapisanie — krótkie fakty do globalnego
  pliku, długie zestawienia do `~/.claude/wiedza/`.

## 0.5.0 — 2026-09-16

Instalator wdraża wreszcie **całość**, a nie połowę. Do tej pory stawiał tryb
pracy z workerami i nie wiedział nic o pamięci ani o zasadach globalnych.

- **Podział na dwa niezależne moduły**: `workerzy` (tryb kierownika, nic nie
  pobiera) i `pamiec` (Lore). Każdy instaluje się, pomija i aktualizuje osobno.
  Rejestr modułów jest w jednym miejscu — dołożenie trzeciego to dopisanie
  pozycji, nie przebudowa.
- **Ekran zgody przed jakąkolwiek zmianą.** Instalator mówi wprost, co zapisze
  i gdzie, ile zajmie pobieranie i że agent zyska dostęp do treści rozmów.
  Odmowa modułu `pamiec` nie blokuje reszty.
- **Zasady globalne wpisywane do plików instrukcji** (`~/.claude/CLAUDE.md`,
  `~/.codex/AGENTS.md`) w oznaczonym bloku — idempotentnie, z kopią zapasową,
  bez ruszania własnych zapisków użytkownika. Da się je usunąć bez śladu.
- **Strażnik zasad** przy starcie sesji: jeśli blok zniknął albo jest
  nieaktualny, wpisuje go z powrotem i mówi o tym jedną linią. Przy zgodnym
  stanie milczy całkowicie.
- **Automatyczne aktualizacje wdrożeń.** Poprawka nakłada się sama, nowa funkcja
  jest proponowana z opisem kosztu, przebudowa wymaga ręcznego wdrożenia.
  Odmowa jest zapamiętywana. Pliki stanu (`worklog.md`, `mapa.md`) nigdy nie są
  nadpisywane. Bez sięgania do sieci przy starcie sesji.
- **Samosprawdzenie po instalacji** — 5 punktów dla modułu pamięci, komplet
  plików i poprawność konfiguracji dla trybu pracy.

**Trzy realne błędy złapane przez to samosprawdzenie i testy, nie przez przegląd
kodu:**

1. Cudzysłowy w argumencie giną przy przekazywaniu do zewnętrznego programu
   w PowerShell 5.1 — odczyt statystyk bazy cicho padał.
2. Nawias `@()` wokół konwersji JSON zwija tablicę w jeden element — instalator
   traktował oba moduły jako jeden o nazwie „workerzy pamiec".
3. Zakładanie zadania w harmonogramie przez obiekty kończy się odmową dostępu
   u zwykłego użytkownika; ta sama operacja jako XML przechodzi. Przy okazji
   zadanie działa teraz również na baterii.

**Znane ograniczenie warsztatu:** workerzy pracujący w izolowanej kopii
repozytorium nie mogą uruchamiać PowerShella, więc nie są w stanie przetestować
skryptów, które piszą. Wszystkie trzy uczciwie to zgłosiły; testy wykonał
kierownik. Przy zadaniach skryptowych trzeba to uwzględnić z góry.

## 0.6.0 — 2026-09-16

Pamięć przestaje być tylko wyszukiwarką rozmów, a staje się **wiedzą o użytkowniku**.

Powód: samo przeszukiwanie archiwum nie kończy powtarzania tych samych wyjaśnień
w każdym nowym oknie. Rozmowa to drogi nośnik — żeby odzyskać jedno ustalenie,
trzeba przeczytać akapity, w których połowa to myślenie na głos i pomysły później
odrzucone. Fakt zapisany w pliku po prostu jest, zanim ktokolwiek zapyta.

**Trzy warstwy zamiast jednej:**

1. **Stała** — kim jest użytkownik, czym zajmuje się firma, jakim językiem mówi
   o swoich rzeczach, nad czym pracuje, jak chce pracować. Rzędu stu linii,
   wczytywana przy każdej sesji.
2. **Bieżąca** — sprawy tego tygodnia, w obowiązkowym formacie `[RRRR-MM-DD]`.
   **Wpis starszy niż 14 dni przestaje być traktowany jako prawda** — agent pyta,
   czy nadal obowiązuje, zamiast budować na nim wnioski. To jest zabezpieczenie
   przed gniciem pamięci: „produkt X się męczy" jest bezcenne w środę i szkodliwe
   za miesiąc.
3. **Referencyjna** — duże zestawienia w osobnych plikach. W warstwie stałej
   zostaje jedna linia na plik, treść czytana dopiero, gdy rozmowa tego dotyczy.

**Trzy drogi, którymi wiedza tam trafia:**

- Agent **sam proponuje zapis**, gdy użytkownik tłumaczy coś trwałego — nie czeka
  na polecenie „zapamiętaj".
- **Powtórzenie jest dowodem.** Gdy to samo pojawia się w kilku wcześniejszych
  rozmowach, agent widzi to w Lore i mówi wprost, że tłumaczono mu to już kilka razy.
- **Sprzeczność rozstrzyga użytkownik.** Gdy nowa wypowiedź kłóci się z zapisem,
  agent pyta, co jest aktualne — zamiast cicho nadpisać. Ciche nadpisanie kasuje
  ślad, że coś się zmieniło.

**Poranne wyciąganie faktów** — raz dziennie przegląd rozmów z ostatniej doby.
Tylko nowy materiał, twardy sufit na wejście, wywołania narzędzi odsiane przed
wysłaniem. **Wynik ląduje w poczekalni do zatwierdzenia, nigdy wprost
w obowiązującej wiedzy** — automat proponuje, człowiek zatwierdza.

Wiedza użytkownika zostaje na jego dysku, poza repozytorium. Kto instaluje
narzędzie, dostaje pusty mechanizm, nie cudzą wiedzę.

## 0.6.1 — 2026-09-16

- **Codzienny raport kosztu pamięci** (`narzedzia\koszt-pamieci.ps1`, zadanie
  `LoreKoszt` o 08:15). Pokazuje, ile znaków i tokenów dokleja się do **każdej**
  rozmowy, ile to daje przez dobę przy rzeczywistej liczbie sesji, ile wpisów
  bieżących jest przeterminowanych i ile faktów czeka w poczekalni. Ostrzega, gdy
  warstwa stała zbliża się do sufitu.
  Nie wywołuje żadnego modelu — to czyste liczenie znaków, więc sam raport nie
  kosztuje nic.
- **Twardy sufit 8 000 znaków na warstwę stałą** wpisany w zasady, nie tylko
  w ostrzeżenie raportu. Po przekroczeniu zestawienia przenoszą się do warstwy
  referencyjnej, która nie jest doklejana do rozmów.

Pierwszy pomiar na maszynie autora: **522 tokeny na rozmowę, ~3 650 tokenów przez
dobę** przy 7 sesjach. Dla porównania sufit warstwy stałej to ~2 700 tokenów.

## 0.7.0 — 2026-09-16

- **Poranne wyławianie faktów z rozmów** (`narzedzia\wyciagnij-fakty.ps1`, zadanie
  `LoreFacts` o 08:05). Przegląda rozmowy z ostatniej doby i wypisuje trwałe fakty
  o użytkowniku, jego firmie i sposobie pracy. **Wynik ląduje w poczekalni
  (`wiedza\kandydaci.md`), nigdy wprost w obowiązującej wiedzy** — automat
  proponuje, człowiek zatwierdza.
- **Nadrabianie po przerwie bez gubienia danych.** Bierze najstarszy nieprzetworzony
  materiał, a znacznik przesuwa dokładnie tam, dokąd doszedł. Po kilku dniach
  nieobecności nadrabia partiami i mówi, ile zostało. `-Nadrabiaj N` robi to
  jednym poleceniem. Wcześniejszy projekt brał najnowsze — po dłuższej przerwie
  starsze rozmowy przepadałyby po cichu.
- **Powiadomienie o czekających faktach** przy starcie sesji. Bez tego nikt nie
  zagląda do poczekalni i cała robota idzie do kosza.
- **Zabezpieczenie przed pętlą**: przebieg wyławiania nie zapisuje własnego
  transkryptu. Bez tego indekser połykałby go i nazajutrz wyławiał własny wynik
  jako „fakt".
- 20 nowych testów, razem **38**.

Pierwszy prawdziwy przebieg wyłowił m.in. gdzie leżą zdjęcia produktów, ograniczenie
stronicowania w API Amazona i zasadę „tylko odczyt do czasu akceptacji" — czyli
dokładnie te rzeczy, które trzeba było tłumaczyć w każdym nowym oknie.

## 0.7.1 — 2026-09-16

- **Zasady globalne odchudzone o połowę** — z 6 076 do 3 032 znaków. Koszt
  doklejany do każdej rozmowy spadł z ~2 548 do ~1 533 tokenów, czyli o 40%.
  Nie ubyła żadna reguła: wycięte zostały uzasadnienia „dlaczego tak", powtórzenia
  i przykłady powtarzające samą regułę. Model potrzebuje reguły i jej warunków,
  nie perswazji — pełne wyjaśnienia zostają w README, który czytają ludzie.
- **Ostrzeżenie dla przyszłych edytorów** na górze `zasady-globalne.md`: ten tekst
  jedzie z każdym zapytaniem, więc każde zbędne zdanie mnoży się przez liczbę
  wszystkich rozmów użytkownika.

Pomiar pokazał rzecz nieoczywistą: **najdroższym elementem stale wczytywanej
pamięci nie była wiedza o użytkowniku (475 tokenów), tylko tekst samych zasad
(2 026 tokenów)** — czterokrotnie więcej. Warto mierzyć, zanim się optymalizuje.

## 0.8.0 — 2026-09-16

Pamięć zaczyna utrzymywać się sama, zamiast czekać na przeglądanie list.

- **Fakty dostają warstwę już przy wyławianiu.** Model i tak czyta materiał —
  przydzielenie warstwy to ta sama analiza, tylko bogatszy format odpowiedzi.
  Fakt trwały dostaje podsekcję, bieżący datę, długie zestawienie nazwę pliku
  referencyjnego i linię odsyłacza. Stary format wpisów nadal się czyta.
- **Automatyczne zatwierdzanie tego, co maszyna potwierdzi.** Fakt zawierający
  ścieżkę, która istnieje, nie wymaga decyzji człowieka — to po prostu prawda.
  Wchodzi do warstwy stałej sam. Fakt ze ścieżką nieistniejącą dostaje znacznik
  `[!]` i zostaje w poczekalni. Fakt niesprawdzalny (zasada, decyzja użytkownika)
  czeka na zatwierdzenie, bo żaden skrypt tego nie rozstrzygnie.
- **Sprawdzanie faktów już obowiązujących** — najgroźniejszy jest ten, który po
  cichu przestał być prawdą i nadal wygląda wiarygodnie. Taki zostaje oznaczony
  komentarzem, ale **nie skasowany**: dysk sieciowy bywa chwilowo niedostępny.
- 34 nowe testy, razem **72**.

**Dwa fałszywe alarmy wyłapane przy pierwszym uruchomieniu na żywych danych**
i naprawione od razu — bo narzędzie, które krzyczy bez powodu, uczy użytkownika
ignorowania ostrzeżeń:

1. Program na Windowsie ma rozszerzenie, którego nie widać w mowie: fakt mówi
   `pg_ctl`, na dysku leży `pg_ctl.exe`.
2. Fakt może wprost mówić, że plik leży **na innej maszynie** („na laptopie
   magazyn2"). Szukanie go na tym dysku zawsze zawiedzie, a to nie znaczy,
   że fakt jest nieprawdziwy — po prostu nie da się go sprawdzić stąd.

## 0.9.0 — 2026-09-16

- **Niezawodny cykl dzienny** (`narzedzia\cykl-dzienny.ps1`, zadanie `LoreCykl`
  przy starcie systemu i zalogowaniu). Sprawdza przed pracą, czy jest `claude`,
  sieć i limit — brak czegokolwiek to **odłożenie, nie porażka**. Ponawia co
  10 minut, najwyżej pięć razy na dobę. **Żaden dzień nie zostaje pominięty**:
  nieudany przebieg nie przesuwa znacznika, a zaległość nadrabia się partiami
  (najwyżej 5 dni na przebieg, żeby po urlopie nie przepalić limitu naraz).
- **Przekopywanie archiwum przez skupiska wektorowe** (`narzedzia\przekop-archiwum.ps1`).
  Znajduje rzeczy powtarzane w wielu sesjach **bez czytania archiwum modelem** —
  to czysta matematyka na wektorach. Model dostaje po jednym przedstawicielu ze
  skupiska, kilkadziesiąt urywków zamiast dziesiątek tysięcy. Skupisko liczy się
  tylko wtedy, gdy zawiera wypowiedzi z co najmniej 3 różnych sesji.
- **Jedna linia przy starcie sesji**: koszt pamięci i stan ostatniego cyklu.
  Gdy wszystko gra i nie ma zaległości — cisza.
- 23 nowe testy, razem **95**.

**Wpadka wyłapana na prawdziwym archiwum i naprawiona:** pierwsze uruchomienie
przekopywania wypchnęło na szczyt rankingu **własny szablon meldunku agenta**
(„zadanie ustawione, teraz sprawdzam"), powtarzany w 34 sesjach. To powtarzalna
FORMA, nie powtarzalna wiedza. Po ograniczeniu do wypowiedzi użytkownika wyszły
rzeczy tłumaczone po kilkanaście razy: konfiguracja OAuth (26 sesji),
monitorowanie załączników (18), kolejność audytu przed wypchnięciem (15).

## 0.9.1 — 2026-09-16

- **Wyławianie faktów czyta tylko wypowiedzi użytkownika.** Pomiar na prawdziwym
  archiwum: mediana dnia to **328 000 znaków** obu stron rozmowy, ale **41 000**
  samego użytkownika — **ośmiokrotna różnica**. Połowa asystenta to w większości
  jego własne meldunki i podsumowania; to samo wyszło wcześniej przy przekopywaniu
  archiwum, gdzie szablon meldunku wygrał ranking powtórzeń.
- To nie jest tylko oszczędność. Przy starym ustawieniu **sufit 60 000 znaków
  pokrywał mniej niż jedną piątą typowego dnia**, więc system byłby trwale w tyle
  i nigdy by nie nadążył. Teraz cały dzień mieści się z zapasem.
- Koszt po zmianie: **~13 700 tokenów wejścia na dzień** zamiast ~109 000.
- Świadomy kompromis: fakt wypowiedziany po raz pierwszy dopiero w podsumowaniu
  asystenta przepadnie. Niewielki procent za ośmiokrotną oszczędność.

## 0.9.2 — 2026-09-16

- **Rozróżnienie zaległości przejściowej od trwałej.** Obie wyglądały identycznie
  („czeka X dni"), a znaczą coś zupełnie innego: pierwsza się nadrobi, druga
  oznacza, że limit na jeden przebieg jest za mały i **system nigdy nie nadgoni** —
  przez miesiące wyglądając normalnie.
  Cykl porównuje teraz zaległość z poprzednim przebiegiem i mówi wprost, czy
  maleje, stoi w miejscu, czy rośnie. Przy rosnącej wypisuje ostrzeżenie razem
  z konkretną radą, co zmienić.

## 0.9.3 — 2026-09-16

- **Cykl dzienny startuje przy zalogowaniu, nie przy starcie systemu.**
  `<BootTrigger>` odpala zadanie przed zalogowaniem użytkownika, więc Windows żąda
  do jego założenia uprawnień administratora i kończy „Odmowa dostępu" u zwykłego
  użytkownika. Samo logowanie wystarcza — przed zalogowaniem i tak nie ma czego
  analizować. Wyszło przy zakładaniu zadania na żywej maszynie.
- Zadanie `LoreFacts` usunięte: cykl dzienny sam wywołuje wyławianie, więc osobne
  zadanie robiło tę samą pracę drugi raz.

Stan zadań na maszynie: `LoreIndex` (co 10 min), `LoreCykl` (przy zalogowaniu),
`LoreKoszt` (codziennie 08:15), `LoreWiedza` (poniedziałki 08:25).

## 0.9.4 — 2026-09-16

- **Przenoszenie ustawień Orki między komputerami** (`narzedzia\orca-ustawienia.js`).
  Orca trzyma wszystko w jednym pliku, w którym mieszają się ustawienia z **stanem
  konkretnej maszyny** — identyfikatorami repozytoriów, ścieżkami katalogu
  roboczego, filtrami po projektach. Skopiowanie całego pliku pokazałoby na drugim
  komputerze projekty, których tam nie ma, i schowało te, które są.
  Skrypt przenosi wygląd i preferencje, a stan maszyny pomija — **wypisując wprost,
  co pominął**. Przy wgrywaniu scala klucz po kluczu zamiast podmieniać całą sekcję,
  żeby nie skasować tego, co na maszynie docelowej ma zostać. Kopia zapasowa
  przed każdą zmianą.

## Audyt zewnętrzny — 2026-09-16, maszyna bez Claude Code

Codex przeprowadził niezależny audyt na maszynie, dla której to narzędzie nie było
budowane. **Wynik obala wcześniejszą ocenę: przywiązań do Claude Code jest
dziewięć, nie dwa.**

**Trzy znaleziska, których nie przewidzieliśmy:**

1. **Zatwierdzone fakty nigdy nie trafiłyby do Codeksa.** `verify.py` zapisuje
   wiedzę wyłącznie do `~/.claude/CLAUDE.md`. Nawet po naprawieniu indeksowania,
   rejestracji i modelu pamięć rosłaby w pliku, którego Codex nie czyta — cała
   reszta naprawy byłaby bezużyteczna.
2. **Instalator zgłosił sukces mimo dwóch realnych awarii.** Zadanie `LoreIndex`
   nie powstało, a model 465 MB nigdy się nie pobrał. Sprawdzenie przeszło, bo
   indeksowanie nie miało czego indeksować, a bazę z zerem plików uznało za OK.
   **Samosprawdzenie weryfikuje obecność wpisów, nie działanie** — dokładnie ten
   rodzaj cichej awarii, przed którym miało chronić.
3. **Format sesji Codeksa jest strukturalnie inny**: `session_meta`, `event_msg`,
   `response_item` z zagnieżdżonym `payload.type`, zamiast `user`/`assistant`.
   Dodanie katalogu do przeszukiwania nic nie da — potrzebny jest osobny czytnik.

**Pozostałe sprzężenia:** wymóg `claude.exe` w instalatorze, rejestracja MCP przez
`claude mcp`, odkrywanie transkryptów w `~/.claude/projects`, dwa wywołania modelu
przez `claude -p` (`facts.py` i `mining.py`), kontrola `claude auth` i
`api.anthropic.com` w cyklu dziennym, magazyn danych w `~/.claude`, hooki i
workery oparte na kontrakcie Claude Code.

**Co jest naprawdę przenośne:** baza SQLite, wyszukiwanie pełnotekstowe
i semantyczne, embeddingi, protokół MCP, narzędzia wyszukiwania. Rdzeń jest
neutralny — przywiązane są wszystkie krawędzie.

**Kierunek naprawy** (nie łatanie pojedynczych miejsc): wydzielić sześć styków —
źródło transkryptów, parser, backend modelowy, rejestracja MCP, docelowy plik
wiedzy, integracja z hostem — i dołożyć adapter Codeksa obok istniejącego adaptera
Claude Code. Instalować tylko adapter hosta wykrytego na maszynie.

**Osobny dług:** hooki i workery to kontrakt Claude Code, którego nie da się
odpiąć podmianą ścieżek. Dla Codeksa trzeba je przeprojektować albo świadomie
zrezygnować.

## 0.10.0 — 2026-09-16

**Naprawa najgroźniejszego znaleziska z audytu: wiedza szła w ślepy zaułek.**

- **Zatwierdzony fakt trafia do pliku instrukcji KAŻDEGO wykrytego narzędzia**,
  nie tylko Claude Code. Użytkownik pracuje dziś w jednym, jutro w drugim —
  fakt zapisany w pliku, którego drugie narzędzie nie czyta, to fakt, którego
  nikt nie zna. Lista narzędzi jest listą, nie dwoma przypadkami: dołożenie
  trzeciego to dopisanie jednej linii.
- **Plik, którego nie ma, jest pomijany**, nie zakładany — brak `~/.codex/AGENTS.md`
  znaczy po prostu, że użytkownik nie ma Codeksa.
- **Sprawdzanie faktów obowiązujących** przechodzi po wszystkich plikach.
- **Kopia zapasowa dla każdego zmienianego pliku**, z nazwą wywiedzioną z jego
  własnej nazwy, a nie zaszytą na sztywno.
- **Domknięta luka zgłoszona przez workera:** wyławianie sprawdzało duplikaty
  tylko w pliku Claude Code, więc fakt zatwierdzony do Codeksa wracałby nazajutrz
  do poczekalni i prosił o ponowne zatwierdzenie tego samego zdania.
- 10 nowych testów, razem **104**.

**Czytnik sesji Codeksa — nie powstał i nie powstanie na tej maszynie.** Worker
sprawdził i zgłosił wprost: katalogu `.codex` tu nie ma, a 57 plików sesji leży na
maszynie domowej użytkownika. Napisanie parsera z samego opisu formatu oznaczałoby
zgadywanie, gdzie siedzi rola, treść i znacznik czasu — czyli kod wyglądający na
gotowy. Ten kawałek musi powstać tam, gdzie są prawdziwe pliki.

## 0.11.0 — 2026-09-16

**Czytnik transkryptów Codeksa** (napisany na maszynie domowej, gdzie Codex
faktycznie chodzi)
- `lore/index.py` czyta teraz oba formaty: `~/.claude/projects/**/*.jsonl`
  i `~/.codex/sessions/**/*.jsonl`. Format Codeksa jest inny — zdarzenia
  `session_meta` / `event_msg` / `response_item`, treść w blokach
  `input_text` / `output_text` — więc odczyt rozdzielony na dwie funkcje
  za wspólnym szwem `ParsedRecord`.
- Dzięki temu pamięć działa też tam, gdzie nie ma Claude Code.

**Samosprawdzenie sprawdza działanie, nie obecność wpisów**
- Reguła, którą przeszło każde sprawdzenie: *gdyby ta rzecz była całkowicie
  zepsuta, czy to sprawdzenie by to wykryło?* Wcześniej połowa punktów
  odpowiadała „OK", bo plik istniał albo wpis był w konfiguracji.
- `instaluj-lore.ps1 -TylkoSprawdz` robi teraz: przebieg indeksowania, policzenie
  wektora modelem, porównanie liczby plików w bazie z liczbą widocznych
  transkryptów, handshake JSON-RPC z serwerem MCP (`initialize` + `tools/list`
  + `lore_stats`). Wyłączone zadanie w harmonogramie to błąd, nie „istnieje".
- `wdroz.ps1` odpala hooki tak, jak zrobiłby to Claude Code — przez `bash`,
  z `CLAUDE_PROJECT_DIR` — zamiast sprawdzać, czy wpis jest w `settings.json`.
- Czego sprawdzenie NIE obejmuje, wraca w podsumowaniu wprost, żeby nikt nie
  wziął „zapisane" za „działa".

**Sprawdzone na maszynie**, nie tylko w testach: 8/8 punktów zielonych, 669 z 669
transkryptów w bazie, 53 549 kawałków, model 464 MB, serwer MCP odpowiada.
Próba negatywna (wyłączone zadanie w harmonogramie) → BŁĄD i kod wyjścia 1.

## 0.12.0 — 2026-09-16

Domknięcie audytu z maszyny bez Claude Code. Narzędzie przestaje zakładać, że
Claude Code w ogóle na maszynie jest.

**Aktualizacja sama się dociąga**
- Strażnik (`narzedzia\straznik-zasad.ps1`) przy starcie okna odświeża katalog
  narzędzia z gita, zanim porówna numery wersji. Wcześniej porównywał wdrożenie
  ze starą, lokalną kopią `ZMIANY.md` i zawsze widział „wszystko aktualne" —
  wdrożenie na drugiej maszynie nie miało jak dowiedzieć się o nowej wersji.
- Pobranie jest tchórzliwe z założenia: wyłącznie `merge --ff-only`, nigdy
  `reset --hard`, `checkout -f`, `clean` ani autostash. Niezapisane zmiany,
  rozjechana historia, brak zdalnej, brak sieci — każde z nich zatrzymuje
  pobranie. Do sieci zagląda raz na godzinę, z krótkim limitem czasu, żeby nie
  opóźniać startu okna.
- **Poprawka, bez której całość nie działała wcale:** `Start-Process -PassThru`
  w PowerShellu zostawia `ExitCode` jako `$null`, dopóki nie sięgnie się po
  uchwyt procesu. Każde wywołanie gita wyglądało więc na nieudane i pobieranie
  po cichu odpuszczało. Kod wyglądał poprawnie i przeszedł kontrolę statyczną —
  wyszło dopiero przy uruchomieniu na prawdziwym klonie.

**Serwer MCP rejestruje się w każdym narzędziu obecnym na maszynie**
- Claude Code przez `claude mcp add`, Codex przez `codex mcp add`, a gdy Codex
  nie zna tego polecenia — idempotentny wpis `[mcp_servers.lore]` w jego
  `config.toml`, z kopią zapasową obok. Brak jednego z narzędzi to normalna
  sytuacja; instalacja przerywa się dopiero przy braku obu.
- Nieobecne narzędzie jest w samosprawdzeniu **pomijane jawnie**, nie zaliczane
  na zielono.

**Dane Lore mają własny katalog**
- Baza i model idą do `~\.lore`, a nie do katalogu Claude Code. Zgodność wstecz:
  istniejąca baza w `~\.claude` (także pod starą nazwą `historia.db`) jest
  wykrywana i używana dalej — nic się nie przenosi ani nie kasuje.
- Zmienne `LORE_HOME` i `CLAUDE_HISTORIA_HOME` zachowują pierwszeństwo.
- Katalogi ŹRÓDEŁ (`~\.claude\projects`, `~\.codex\sessions`) zostają przy
  swoich narzędziach — to co innego niż dane Lore.

**Model bierze się z tego, co stoi na maszynie**
- Wybór narzędzia wyprowadzony do jednego miejsca w `lore\lore\facts.py`
  (`find_model_cli`), używany też przez `mining.py`. Kolejność: `claude`, potem
  `codex`; da się wymusić zmienną `LORE_MODEL_CLI`.
- `cykl-dzienny.ps1` wykrywa narzędzia na żywo zamiast odpytywać Anthropica na
  sztywno. Krok weryfikacji nie potrzebuje modelu i idzie zawsze, także gdy
  żadnego modelu nie ma.

**Sprawdzone uruchomieniem**, nie przeczytaniem kodu: 126 testów; klon cofnięty
o dwie wersje sam przewinął się do najnowszej; próby negatywne (brudne drzewo,
katalog niebędący repozytorium) kończą się komunikatem i kodem 0, bez wywalenia
sesji; rejestr modułów, instalator w trybie próbnym i cykl dzienny w trybie
próbnym przechodzą.

**Niezweryfikowane:** składnia wywołania Codeksa (`codex exec`) przyjęta
z dokumentacji — na tej maszynie Codeksa nie ma. Oznaczone w kodzie jako
`UNVERIFIED`. Do sprawdzenia na maszynie domowej.

## 0.12.1 — 2026-09-17

Potwierdzone na maszynie domowej, gdzie stoi sam Codex, bez Claude Code.
**Pełna instalacja przeszła: 8 z 8 sprawdzeń, Codex przyjął serwer MCP, handshake
i `lore_stats` odpowiadają, w sesji Codeksa widać `lore: connected (4 tools)`.**
Baza: 57 z 57 transkryptów, 2673 kawałki, model 464 MB.

**Wywołanie Codeksa przestaje być zgadywanką**
- `codex exec --help` z działającej maszyny potwierdził to, co napisaliśmy
  z dokumentacji: `exec`, prompt ze standardowego wejścia przez `-`
  i `--skip-git-repo-check` znaczą dokładnie to, co zakładaliśmy. Oznaczenia
  `UNVERIFIED` zdjęte, z datą potwierdzenia.
- Ale wyszedł prawdziwy problem, którego dokumentacja nie zdradziłaby bez
  przeczytania: **bez `--output-last-message` na standardowe wyjście leci cały
  przebieg sesji**, nie sama odpowiedź — do faktów trafiałby śmietnik. Odpowiedź
  czytamy teraz z pliku, katalog tymczasowy sprzątany także przy wyjątku.
  Do tego `--color never` (żeby nie wciągać kodów sterujących terminala)
  i `-s read-only`, bo wyławianie faktów jest czysto tekstowe.
- Brak pliku odpowiedzi albo pusty plik to czytelny błąd, nie ciche pustki.

**Instalator nie mówi o narzędziu, którego nie ma**
- Wykrywanie działało poprawnie, ale ekran zgody i tak twierdził „pamięć rozmów
  z Claude Code" na maszynie, gdzie Claude Code nie ma. Teraz wymienia to, co
  faktycznie znalazł — i tak samo zdanie końcowe o restarcie.

**Zgodność wstecz potwierdzona w boju:** na maszynie domowej leżała już baza
w `~\.claude` (powstała dzień wcześniej). Instalator ją wykrył i zostawił na
miejscu, zamiast zakładać drugą obok — dokładnie tak, jak miało działać.

131 testów.

## 0.13.0 — 2026-09-17

Narzędzie działa bez Claude Code — także w tych częściach, które dotąd na nim wisiały.

**Samoaktualizacja nie potrzebuje już Claude Code**
- Strażnik dostał tryb `-Tlo`: robi tylko to, co ma sens bez człowieka przy
  klawiaturze (pobranie nowej wersji, pilnowanie plików zasad), a wynik dopisuje
  do dziennika `~\.claude\.megaruchacz-tlo.log`, przycinanego do 200 linii.
- Instalator zakłada drugie zadanie w Harmonogramie, `MegaRuchaczOdswiez`, co
  60 minut. Osobne, a nie doklejone do `LoreIndex`, bo `LoreIndex` należy do
  modułu `pamiec`, który wolno odrzucić — narzędzie ma się aktualizować
  niezależnie od tego wyboru.
- **Dlaczego nie hook Codeksa:** Codex liczy odcisk palca definicji hooka
  i odmawia uruchomienia, dopóki człowiek nie zatwierdzi go przez `/hooks` —
  po KAŻDEJ zmianie skryptu od nowa. Do samoaktualizacji to się nie nadaje.
  Zadanie w Harmonogramie nie wymaga ani zatwierdzania, ani praw administratora.
- Strażnik pilnuje teraz obu plików zasad: `~\.claude\CLAUDE.md` i
  `~\.codex\AGENTS.md`. Zapis do `AGENTS.md` istniał już w `wpisz-zasady.ps1`,
  ale strażnik go nie odtwarzał — po skasowaniu bloku nikt go nie przywracał.
- `wdroz.ps1` wykrywa, czego na maszynie nie ma, i mówi wprost, że tryb workerów
  tam nie zadziała, zamiast zakładać bezużyteczne wpisy i meldować sukces.

**Szablony trybu workerów dla Codeksa** (`szablony-codex\`)
- Cztery role w formacie TOML, zasady kierownika i szablon hooków.
- Zasady to **nie** kopia `CLAUDE.md`. Reguła „odpowiadasz w sekundach, robota
  leci w tle" jest pod Codeksem nieprawdziwa — wątek główny czeka na wszystkich
  podagentów. Wpisanie jej byłoby kłamstwem utrwalonym w pliku, więc zastąpiła ją
  uczciwa: rozdaj wszystkich naraz, poczekaj, podsumuj — z wnioskiem, że skoro
  czekanie kosztuje, tym ważniejsze jest nie ciąć zadań za grubo.
- Tak samo zniknęły obietnice, których Codex nie dotrzyma: twarda izolacja
  worktree (zastąpiona zasadą rozłącznych plików) i prawo workera do zadania
  pytania (zastąpione kończeniem raportem „wymaga decyzji").
- Scout w trybie tylko-do-odczytu nie może dopisać do mapy, więc oddaje gotowy
  blok tekstu. Rejestr i mapa idą do `<projekt>\.megaruchacz\`, bo Codex trzyma
  `.codex\` jako tylko do odczytu.

**Sprawdzone uruchomieniem:** składnia trzech skryptów, rejestr modułów, plan
instalatora z obydwoma zadaniami, tryb tła na brudnym katalogu (odmawia pobrania
i mówi dlaczego) oraz na cofniętym klonie — przewinął się z 0.11.0 na 0.12.1
i zapisał to w dzienniku.

**Niezrobione:** wpięcie szablonów Codeksa w instalator — brakuje skryptu
dopisującego start i koniec workera do rejestru oraz generowania ładunków dla
hooków. Wypisane w `szablony-codex\CZYTAJ.md`.

## 0.14.0 — 2026-09-17

**Tryb workerów wdraża się także do Codeksa**
- `wdroz.ps1` zapisuje role do `.codex\agents\`, hooki do `.codex\hooks.json`
  (z osobnym poleceniem dla Windowsa przy każdym), a rejestr pracy i mapę do
  `<projekt>\.megaruchacz\` — bo `.codex\` jest u Codeksa tylko do odczytu.
- Nowy `narzedzia\mr-log-codex.js` dopisuje start i koniec workera do rejestru.

**Zatwierdzanie hooków Codeksa — ustalone, nie zgadnięte**
- Odcisk palca liczony jest wyłącznie z DEFINICJI hooka (zdarzenie, `matcher`,
  `command`, `timeout`, `async`), a nie z treści skryptu. Dowód: funkcja
  `hook_hash` w źródłach Codeksa plus odtworzenie trzech zapisanych wartości
  `trusted_hash` co do znaku.
- Wniosek praktyczny: **użytkownik zatwierdza raz.** Nasze poprawki w skryptach
  zaufania nie unieważniają, aktualizacja Codeksa też nie. Wszystkie komunikaty
  mówiące „po każdej zmianie trzeba powtórzyć" były nieprawdziwe i zostały
  poprawione — w instalatorze, w README i w opisie szablonów.
- `timeout` podajemy w hookach jawnie: wartość domyślna wchodzi do skrótu dopiero
  przy normalizacji i mogłaby się zmienić w nowej wersji Codeksa, kasując zaufanie.

**Koniec zadania odświeżania co godzinę**
- Aktualizacja dzieje się przy starcie sesji. Instalator wykrywa i wyrejestrowuje
  zadanie `MegaRuchaczOdswiez` z maszyn, gdzie już powstało.

**Cykl dzienny nadrabia wg rzeczywistej kolejki, nie wg kalendarza**
- Błąd wyszedł na prawdziwym przebiegu: cykl zameldował `ok`, `nadrobione: 0`,
  a w kolejce stały 133 kawałki materiału. Liczył zaległość w **całych dniach**
  (znacznik na wczoraj = „1 dzień, biorę 1 przebieg"), podczas gdy samo wyławianie
  mówiło wprost, że potrzeba czterech. Cykl tę liczbę czytał — i używał jej
  wyłącznie do napisania podsumowania.
- `wyciagnij-fakty.ps1 -Kolejka` podaje teraz stan kolejki liczbami, bez modelu
  i bez zapisu (0,4 s), a cykl pyta o to **przed** podjęciem decyzji.
- Statusy `dogania` / `nie nadaza` zamiast fałszywego `ok`; podsumowanie mówi
  w kawałkach materiału, nie w dniach.
- `Kierunek-Zaleglosci` — ostrzeżenie o rosnącej kolejce — **nigdy się nie
  pokazywało**: czytało plik `klucz: wartość` przez `ConvertFrom-Json` w pustym
  `catch`. Poprawione; porównuje przebiegi z przebiegami, nie dni z przebiegami.

**Koniec fałszywych alarmów w samosprawdzeniu wdrożenia**
- „brak bash-a w PATH" — Claude Code odnajduje basha sam; sprawdzenie szuka teraz
  także w znanych lokalizacjach Gita, a brak to ostrzeżenie, nie błąd.
- „rejestr workerów nie działa" — działał; próba nie dowoziła zdarzenia na wejście
  skryptu przez potok PowerShella. Teraz idzie przez przekierowanie wejścia.
- Fałszywy alarm jest gorszy niż brak alarmu: uczy człowieka ignorować ostrzeżenia.

**Sprawdzone uruchomieniem:** wdrożenie do pustego projektu kończy się kodem 0
bez „Instalacja NIEPELNA", stan kolejki na prawdziwej bazie (172 kawałki,
5 przebiegów), przebieg próbny cyklu, składnia wszystkich ruszonych skryptów.

## 0.14.1 — 2026-09-17

**Codex aktualizuje narzędzie przy starcie sesji**
- Nowy hook `SessionStart` uruchamia strażnika w trybie `-Tlo`: pobiera nowszą
  wersję z gita i nanosi poprawki. Osobna grupa, nie drugi wpis w istniejącej —
  scalanie rozpoznaje wpisy po `statusMessage` pierwszego hooka w grupie, więc
  dołożony obok nigdy nie doszedłby do kogoś, kto ma już wdrożenie.
- `timeout` jawny, `commandWindows` obowiązkowo, nic nie trafia do kontekstu
  modelu — to robota w tle, nie meldunek.

**Strażnik odświeża także część codeksową**
- `Nanies-Poprawki` obejmuje `.codex\agents\`, `.megaruchacz\*`, blok w `AGENTS.md`
  i ładunki hooków. Wcześniej znał wyłącznie `.claude\`, więc jedyną drogą do
  nowszej wersji plików Codeksa było ponowne uruchomienie `wdroz.ps1`.
- `hooks.json` traktowany ostrożnie: strażnik dopisuje wyłącznie BRAKUJĄCE grupy
  i nigdy nie rusza istniejących, bo zmiana definicji hooka unieważnia
  zatwierdzenie użytkownika. Gdy coś dopisze, mówi jedną linią, że trzeba
  powtórzyć `/hooks` — nie po cichu.

**Koniec kłamstwa w ekranie zgody**
- `wdroz.ps1` w trzech miejscach obiecywał zadanie `MegaRuchaczOdswiez`, które
  „co godzinę pobiera nowszą wersję". Zadanie zostało usunięte kilka godzin
  wcześniej, a ekran zgody dalej je zapowiadał.

**README mówi prawdę o obu narzędziach**
- Obietnica „nie czekasz" była prawdziwa tylko pod Claude Code i stała jako
  główna zaleta całego projektu. Rozdzielona: pod Claude Code klawiatura wraca
  w sekundach, pod Codeksem runda idzie równolegle, ale trzeba jej poczekać.
- Przy okazji wyszły inne nieprawdy: README twierdził, że czytnika transkryptów
  Codeksa nie ma i że automatycznego wyławiania faktów nie ma (oba istnieją),
  podawał 18 testów zamiast 131 i twierdził, że serwer MCP rejestruje się
  wyłącznie dla Claude Code.

**Sprawdzone uruchomieniem:** dwukrotne wdrożenie do tego samego projektu kończy
się kodem 0 i NIE dubluje wpisów (`SessionStart` ma 2 grupy, nie 4), rejestr
modułów nadal zwraca poprawny JSON.

## 0.15.0 — 2026-09-17

Wymaganie użytkownika, dosłownie: *„nie może dojść do sytuacji, gdzie po cichu coś
się ucina bo sufit, kategorycznie nie może być"* oraz *„nie może być też, że
zapytanie o godzinę będzie mnie kosztować kilka milionów tokenów"*.

**Audyt sufitów** (`narzedzia\koszt-pamieci.ps1`)
- Sekcja „co jest ucinane w tej chwili" na samej górze raportu: ile znaków ginie,
  ile to procent i **od którego nagłówka zaczyna się ucięta część** — żeby było
  widać, co konkretnie przepada, a nie tylko że przepada.
- Tabela wszystkich sufitów: wartość, limit, zapas, skutek przekroczenia.
  Przekroczone i ciasne na górze. Rozróżnienie **sufit NASZ** (do podniesienia
  jedną linijką) od **narzuconego przez narzędzie** (32 KiB `AGENTS.md` — z tym
  trzeba żyć), bo bez tego nie wiadomo, czy da się coś zrobić.
- Limity czytane ze źródeł, nie przepisane. Przepisana liczba zaczyna kłamać przy
  pierwszej zmianie w pliku źródłowym — ta klasa błędu wyszła dziś trzy razy.
- Porównanie z poprzednim pomiarem; wzrost powyżej 20% to ostrzeżenie. To jest
  zabezpieczenie przed drugim scenariuszem: niezauważonym puchnięciem pamięci.
- Kod wyjścia 1, gdy cokolwiek jest ucinane.

**Koszt widoczny przy każdym starcie sesji** (`narzedzia\straznik-zasad.ps1`)
- Jedna linia pod Claude Code i pod Codeksem. Przy pierwszym otwarciu danego dnia
  pełniejszy rachunek z raportu dobowego.
- Liczba czytana z pliku, nie liczona na żywo — pomiar trwa ponad dwie sekundy,
  a start sesji nie ma na co czekać. Przeliczenie startuje osobno, w tle.
- Pod Codeksem osobny hook `SessionStart` podaje tę linię przez
  `additionalContext` — hook strażnika celowo nic nie wstrzykuje do rozmowy,
  więc bez tego liczba powstawałaby, ale nikt by jej nie zobaczył.

**Dwa ciche ucinania znalezione i usunięte**
- Zasady kierownika dla Codeksa: 13 129 znaków przy suficie 8 000 — ginęło 39%
  tekstu, **i to jego koniec**, od sekcji „Kiedy NIE rozdawać". Czyli reguły
  o problemach na głębokość, zawodzących workerach i meldowaniu nie docierały
  do modelu wcale.
- Przypomnienie doklejane do KAŻDEJ wiadomości: 592 znaki przy suficie 500 —
  ginęło 16% przy każdym poleceniu.
- Obie liczby były **nasze**, wpisane bez uzasadnienia. Claude Code trawi
  14 319 znaków zasad bez żadnego limitu, więc dawanie Codeksowi połowy nie miało
  podstaw. Podniesione do 24 000 i 1 500, czyli z zapasem — a gdyby pliki do nich
  dorosły, audyt powie o tym, zamiast ciąć.

**Sprawdzone uruchomieniem:** audyt wykrył oba ucinania przed poprawką i zwraca
`nic nie jest ucinane` z kodem 0 po niej; linia o koszcie pokazuje się w sesji
Claude Code i w poprawnym JSON-ie dla Codeksa.

## 0.15.1 — 2026-09-17

**Zmierzone, nie założone: Claude Code NIE ucina wstrzykiwanego tekstu.**
Doświadczenie na żywej sesji — ładunek 64 636 znaków ze znacznikami na głębokości
1k, 2k, 4k, 8k, 16k, 32k i 64k. Dotarły **wszystkie**. Zamiast ucinać, Claude Code
zapisuje całość do pliku i mówi o tym wprost („Output too large… saved to…"),
podając podgląd i ścieżkę. Czyli zachowanie, którego wymagamy od własnego kodu,
ma u siebie od początku — **dlatego świadomie NIE wpisujemy tam własnego sufitu**:
byłby czystą szkodą, ucinałby to, co narzędzie przepuszcza w całości. Codex tnie
i milczy, więc zapory zostają wyłącznie po jego stronie.

**Sufit ładunku pilnowany przy KAŻDYM przebiegu strażnika**
- Sprawdzenie wisiało pod `Pilnuj-Wersji`, a ta przerywa, gdy wersja wdrożenia
  równa się źródłowej. Sufit da się złamać bez żadnej aktualizacji — choćby
  ręcznym obniżeniem limitu — i wtedy nikt by nie zareagował. Potwierdzone próbą.
- Wspólny kod zapór wyjęty do `narzedzia\sufit-ladunku.ps1`, używany przez
  instalator i strażnika. Dwa różne komunikaty na to samo to proszenie się
  o rozjazd.

**Ładunek przestał puchnąć przy każdym przebiegu**
- `Get-Content -Raw` w PowerShell 5.1 czyta w ANSI, więc polskie znaki z pliku
  UTF-8 wracały jako krzaki, zapis je utrwalał, a plik rósł: 13 763 → 15 415 →
  i dalej bez końca. Odczyt jest teraz jawnie w UTF-8. Trzy przebiegi pod rząd:
  ta sama liczba.
- Morał na przyszłość: **narzędzie, którym mierzysz, potrafi kłamać tak samo jak
  to, które mierzysz.** Pierwszy pomiar „79 krzaków w ładunku" był fałszywy
  z dokładnie tego samego powodu co badany błąd — plik był czysty.

**Rachunek w jednostkach użytkownika**
- Koniec mnożenia przez zmyśloną liczbę sesji na dobę. Podsumowanie to dwie linie:
  `Kazda Twoja wiadomosc: +207 tokenow.` i `Start sesji: +2 941 tokenow, raz.`
- Raport rozbity na dwa kubełki (za wiadomość / za start sesji), pozycje
  posortowane malejąco z udziałem procentowym — widać, co kosztuje najwięcej.
- Alarmy z progami w jednym nazwanym bloku, z komentarzem, skąd się wzięły i że
  są do zmiany. Próg udziału ustawiony na 70%, nie 60%, bo przy 60 alarm
  świeciłby się od pierwszego dnia — uzasadnienie zapisane przy progu.

**Zasada, która wyszła dziś trzy razy z rzędu:** zabezpieczenie, którego nikt nie
próbował złamać, było martwe. Trzy na trzy. Każda zapora dostaje odtąd próbę
negatywną, albo nie liczy się za zrobioną.

## 0.16.0 — 2026-09-17

Pytanie użytkownika, które ujawniło dziurę: *„jak coś nie będzie działać w Codeksie,
to wyskoczą jakieś błędy? nie będzie cichego niedziałania?"* Odpowiedź brzmiała:
**będzie** — i częściowo sami je wbudowaliśmy.

**Brak wiadomości przestaje znaczyć „wszystko gra"**
- Strażnik zapisuje znacznik obecności przy każdym przebiegu, osobno dla każdego
  trybu: hook Claude Code, hook Codeksa, tło, uruchomienie ręczne.
- Gdy wdrożenie dla Codeksa istnieje, a jego hook nie odnotował ani jednego
  przebiegu, strażnik mówi wprost, co sprawdzić — i podaje obie możliwe przyczyny:
  niezatwierdzone hooki (`/hooks`) albo piaskownica Codeksa, która nie przepuszcza
  PowerShella.
- **Cisza melduje się krzyżowo**, bo hook, który nie chodzi, sam o sobie nigdy nie
  powie: o hookach Codeksa mówi przebieg pod Claude Code, a o hooku Claude Code —
  ładunek wstrzykiwany Codeksowi. Alarm idzie na POCZĄTEK ładunku, bo sufit tnie
  od końca.
- Zabezpieczenia przed fałszywym alarmem: wymagany katalog domowy narzędzia
  i wdrożenie w projekcie, dowód spoza naszych hooków, doba karencji od pierwszego
  zauważenia i jeden meldunek na dobę. Fałszywy alarm uczy ignorować ostrzeżenia,
  więc jest gorszy niż brak alarmu.

**Koniec połykania błędów**
- Puste `catch { }` w głównym przebiegu strażnika chroniły start sesji przed
  potknięciem jednego zadania — ale gdy padało wszystko, też było cicho. Teraz
  każda wywrotka trafia do pliku stanu z nazwą zadania i treścią wyjątku,
  a przy następnym starcie jest meldowana i czyszczona.
- Strażnik nadal nie przerywa sesji. Ma nie przeszkadzać, ale nie ma prawa milczeć.

**Opisy zgodne z kodem**
- README twierdził, że na maszynie z samym Codeksem „nie dzieje się nic samo"
  i że aktualizacja nie przychodzi — nieprawda od 0.14.1. Tym razem opis **zaniżał**
  możliwości, czyli odstraszał od rzeczy, która działa.
- Z mapy projektu usunięte wszystkie numery linii, zostały nazwy funkcji. Numery
  rozjeżdżały się przy każdej zmianie i to one były źródłem dzisiejszych pomyłek:
  mapa wskazywała linię 304, gdy funkcja siedziała w 754.

**Sprawdzone uruchomieniem, obie próby negatywne:**
- po cofnięciu znacznika o pięć dni strażnik zameldował ciszę z konkretną poradą
  i nie powtórzył meldunku tego samego dnia;
- po wstawieniu sztucznej awarii błąd trafił do stanu, został zameldowany przy
  następnym przebiegu, wyczyszczony, a czwarty przebieg był już milczący.

## 0.16.1 — 2026-09-17

**Opis mówi wreszcie, ile to kosztuje i kiedy.** README opisywał trzy warstwy
pamięci i zasady ich zapisywania, ale nigdzie nie odpowiadał na najprostsze
pytanie osoby płacącej za tokeny: co jedzie przy każdej wiadomości, co raz na
sesję, a co nie kosztuje nic. Użytkownik musiał to wyciągać z rozmowy przez
kilka wiadomości.

Nowa sekcja „Ile to kosztuje — dwa rachunki" podaje dwie liczby bez mnożeń:
około 200 tokenów przy każdej wiadomości (przypomnienie z `UserPromptSubmit`)
i około 2 940 raz przy starcie sesji (blok zasad, warstwa stała, bieżąca,
zasady kierownika). Plus to, co najważniejsze dla decyzji, gdzie co zapisywać:
warstwa referencyjna z `wiedza\` nie kosztuje nic, dopóki rozmowa jej nie
dotyczy — więc do warstwy stałej idzie wyłącznie to, co ma zmieniać zachowanie
bez pytania.

Obie liczby oznaczone jako **szacunek, nie pomiar tokenizera**.

**Historia oczyszczona z firmowego adresu.** Dwa dzisiejsze commity powstałe
w kopiach roboczych workerów były podpisane adresem firmowym i przez to
`<konto-firmowe>` trafił na listę współtwórców na GitHubie. Historia przepisana,
zawartość plików niezmieniona (sprawdzone porównaniem przed wypchnięciem).
Wymagało to wymuszonego wypchnięcia — kopie repozytorium na innych maszynach
trzeba raz wyrównać przez `git reset --hard origin/main`.

## 0.17.0 — 2026-09-17

Dzień pytań o koszty. Wszystko poniżej wynikło z jednego: *„muszę jasno wiedzieć,
która warstwa wiedzy jest gdzie doklejana i ile kosztuje"*.

**Rachunek w trzech kubełkach, w jednostkach użytkownika**
- Przy KAŻDEJ wiadomości: ~207 tokenów (przypomnienie zasad). To nie jest warstwa
  wiedzy — to instrukcja dla modelu.
- RAZ przy starcie sesji: ~2 941 tokenów (blok zasad, warstwa stała, bieżąca).
- RAZ NA DOBĘ: uczenie się na wcześniejszych rozmowach — **jedyna pozycja płacona
  prawdziwym wywołaniem modelu**. Pod Claude Code liczona pomiarem (koperta
  `usage`), pod Codeksem szacunkiem, z jawnym oznaczeniem.
- Żadnych mnożeń przez zmyśloną liczbę sesji na dobę. Przy każdej pozycji stoi,
  gdzie leży i jaki ma udział; widać, którą warstwę skracać.
- Widać też, **która warstwa wygasa**: bieżąca jest tymczasowa (14 dni), stała
  i referencyjna nie wygasają.

**Cykl rusza przy pierwszej sesji dnia, nie o 8:15**
- Godzina była wzięta znikąd. Warunek brzmi teraz: inna data niż ostatni przebieg
  ORAZ pierwsze uruchomienie Claude Code albo Codeksa w tym dniu. Wtorek → piątek
  bierze wszystko od wtorku; dni bez pracy nie istnieją.
- Zadania `LoreCykl` i `LoreWiedza` usunięte, instalator je zdejmuje.
- Postęp widać w kolejnych wiadomościach, koszt po zakończeniu.

**Dzień zerowy — nie wolno przeczytać całego archiwum**
- Przy zmianie na oś „czasu zaindeksowania" groziło, że wszystko wygląda na
  świeżo dodane i pierwszy przebieg przeczyta trzy lata rozmów jednym strzałem.
- Jest teraz zapisany moment, przed który wyławianie nigdy nie sięga. Migracja
  nadaje starym wierszom czas wywiedziony z ich własnej daty, nie moment migracji.
- **Sprawdzone na kopii prawdziwej bazy**: 54 247 kawałków, migracja 0,6 s, zero
  strat, pierwszy przebieg wziął 39 kawałków, nie archiwum.
- Materiał pominięty jako starszy niż dzień zerowy jest liczony i zgłaszany.

**Żadna rozmowa nie wypada z zakresu**
- Kawałek mógł trafić do bazy PO tym, jak znacznik przeskoczył za jego datę —
  wtedy nikt by się o nim nie dowiedział. Wybór materiału idzie teraz po czasie
  zaindeksowania, czyli po tej samej osi, po której rosną dane.

**Koniec ręcznej poczekalni**
- Fakty wchodzą do wiedzy same. W poczekalni zostają wyłącznie **sporne** —
  sprzeczne z tym, co już wiemy, z podaniem, czemu przeczą. Automat nie zgaduje,
  która wersja jest prawdziwa.
- Każdy fakt niesie trop do źródła (`wiedza\zrodla.md`, osobno — metryka przy
  każdym wpisie byłaby płacona przy każdej sesji).
- Kopia zapasowa przed każdą zmianą. Próg warstwy stałej pilnowany: automat nie
  przekroczy go po cichu.
- Wykrywanie sprzeczności jest **celowo wąskie** i to zapisane: łapie tę samą tezę
  z inną wartością albo odwrócone przeczenie, a sprzeczność powiedzianą innymi
  słowami przepuści. Szersze dawałoby fałszywe alarmy przy każdym doprecyzowaniu.

**Ścieżka Codeksa naprawiona — cztery usterki**
- Bez `node` użytkownik tracił KOMPLET zasad przy każdej wiadomości i nie widział
  z tego ani słowa. Dołożone awaryjne wyjście, tak jak pod Claude Code.
- Podmiana starego hooka nigdy nie zachodziła: warunek szukał `przypomnienie.js`,
  a stary wpis wołał `przypomnienie.json` — ciąg zawiera się w ciągu.
- Rozbicie kosztów nie docierało pod Codeksem wcale; teraz dostaje ten sam blok.
- Licznik mierzył pliki Claude Code nawet na wdrożeniu Codeksa — `AGENTS.md`,
  czyli realny koszt sesji, nie był liczony.
- Bufor niesie swój wiek: `(UWAGA: liczby sprzed 9 godzin ... to NIE jest stan na
  teraz)` zamiast podawania starych danych jako bieżących.

**Zasada projektu: „Cisza jest zakazana"** (`CLAUDE.md`) — pięć konkretów plus
wymóg próby negatywnej przy każdym zabezpieczeniu. Powód: tego dnia trzy
zabezpieczenia na trzy okazały się martwe, a każde wyglądało na działające.

198 testów.
