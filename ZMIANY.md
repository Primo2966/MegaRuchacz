# Historia wersji

Każda zmiana wypychana na gita dostaje tu wpis. Numer rośnie wg zasady:
pierwsza cyfra — przebudowa łamiąca zgodność, druga — nowa funkcja,
trzecia — poprawka.

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
