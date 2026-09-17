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
   pakowanie2"). Szukanie go na tym dysku zawsze zawiedzie, a to nie znaczy,
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
