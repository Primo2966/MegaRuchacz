<img src="logo.png" width="110" align="right" alt="">

# MegaRuchacz

Tryb pracy, w którym agent AI przestaje być wykonawcą, a staje się **kierownikiem**:
przyjmuje od Ciebie zadanie po zadaniu, rozdaje je workerom pracującym równolegle
— pod Claude Code w izolowanych kopiach repozytorium — i melduje efekt prostym
językiem.

Kluczowa różnica wobec zwykłej pracy z agentem: zadania lecą równolegle, a pilnuje
ich kierownik, nie Ty. Pod **Claude Code** dochodzi rzecz najcenniejsza — **nie
czekasz**: rzucasz zadanie, dostajesz klawiaturę z powrotem w sekundach i piszesz
następne. Pod **Codeksem** i pod **opencode** tego nie ma: wątek główny czeka na
wszystkich podagentów, więc runda idzie naraz, ale klawiaturę odzyskujesz dopiero
po niej. Różnica między nimi: pod Codeksem hooki trzeba raz zatwierdzić
poleceniem `/hooks`, a opencode ładuje swoją wtyczkę sam — nic nie klikasz.

W zestawie jest też **Lore — przeszukiwalna pamięć wszystkich Twoich rozmów** z agentem —
żeby ustalenie z innego okna sprzed tygodnia nie przepadło.

---

## Co tu jest

| Co | Do czego |
|---|---|
| `CLAUDE.md` | zasady kierownika — serce modułu `workerzy` |
| `zasady-globalne.md` | zasady wpisywane do plików instrukcji narzędzi AI |
| `.claude/agents/` | prompty czterech ról: implementer, scout, verifier, zastępca |
| `szablony-codex/` | to samo dla Codeksa: role, zasady kierownika, hooki |
| `szablony-opencode/` | to samo dla opencode: role, zasady kierownika, wtyczka rejestru |
| `lore/` | moduł `pamiec` — serwer MCP z przeszukiwalną pamięcią rozmów |
| `narzedzia/` | instalator pamięci, wpisywanie zasad, strażnik, audyt sufitów |
| `rozszerzenie/` | panel VS Code: lista okien zadaniowych, licznik workerów |
| `wdroz.ps1` | główny instalator — wdraża wybrane moduły do projektu |
| `nowe-zadanie.ps1` | zakłada izolowaną kopię repo na jedno zadanie |
| `ZMIANY.md` | historia wersji — co doszło i co się zmieniło |

## Cztery role

- **implementer** — wprowadza konkretną zmianę w wyznaczonych plikach. Pod Claude
  Code pracuje w osobnej kopii repozytorium, więc dwa zadania w tych samych plikach
  mogą lecieć naprawdę równolegle; pod Codeksem i opencode rozłączności pilnuje
  treść zlecenia.
- **scout** — rozpoznanie: gdzie co leży. Tylko czyta, niczego nie blokuje.
- **verifier** — sprawdza pojedynczą zmianę: czy działa i czy nie psuje reszty.
- **zastępca** — sprawdza, czy **całość** nadal trzyma się kupy po serii
  równoległych zmian. Uruchamiany w punktach scalenia, nie po każdym zadaniu.

Kto pisze rejestr pracy, zależy od narzędzia: pod Claude Code hooki
`SubagentStart`/`SubagentStop`, pod Codeksem hooki z `.codex/hooks.json` (raz
zatwierdzone przez `/hooks`), a pod opencode wtyczka `.opencode/plugins/mr-log.js`,
której nie trzeba zatwierdzać.

## Wymagania

- **Windows** — instalator jest w PowerShellu. Wersji na Linuksa i maca nie ma
  i na razie nie planujemy; to świadoma decyzja, nie przeoczenie.
- **git** — izolacja workerów stoi na `git worktree`.
- **Node.js** — bez niego instalator **nie zapisze żadnych hooków ani ich
  ładunków**, ani dla Claude Code, ani dla Codeksa, i nie sprawdzi działania
  wtyczki opencode. Odpadają wtedy: zasady wstrzykiwane na starcie sesji, rejestr
  pracy workerów i cała samoobsługa strażnika. Reszta wdrożenia idzie normalnie,
  ale to nie jest drobiazg.
- **Claude Code, Codex CLI albo opencode** — wystarczy jedno. Pod Claude Code działa
  pełny tryb (workerzy w tle, hooki, izolowane kopie repozytorium); pod Codeksem
  i opencode pamięć działa w całości, a tryb workerów w wersji okrojonej — co
  dokładnie odpada, mówi tabela „Na maszynie z samym Codeksem" (pod opencode jest
  tak samo, tylko nic nie trzeba zatwierdzać).
- **Python 3.12 + `uv`** — tylko jeśli chcesz Lore, czyli pamięci rozmów.

## Instalacja

### Globalnie — raz na komputer (zalecane)

```powershell
powershell -ExecutionPolicy Bypass -File <ścieżka>\narzedzia\instaluj-globalnie.ps1
```

Jedna komenda i tryb kierownika działa w **każdym projekcie** i we **wszystkich
trzech** narzędziach naraz — nie wdrażasz nic po kolei:

- **opencode** — role w `~/.config/opencode/agents`, wtyczka rejestru w `~/.config/opencode/plugins`;
- **Claude Code** — role w `~/.claude/agents`, rejestr i hooki w `~/.claude/settings.json`;
- **Codex** — zasady w `~/.codex/AGENTS.md`, rejestr i hooki w `~/.codex/hooks.json`;
- **zasady** dla wszystkich trzech lecą przez `~/.claude/CLAUDE.md` (Claude Code i opencode)
  oraz `~/.codex/AGENTS.md` (Codex).

Stan pracy — rejestr zadań i mapa projektu — zostaje **w projekcie**, w `.megaruchacz\`.
Zakłada go pierwszy worker, gdy zajdzie potrzeba, więc nic nie zalega w projektach,
w których nie rozdajesz roboty.

Zdjąć: ten sam skrypt z `-Usun`. Zobaczyć plan bez zapisu: `-Proba`.

> **Cena tej wygody:** zasady kierownika jadą do modelu przy **każdej** sesji,
> w każdym projekcie — rzędu kilku tysięcy tokenów na okno. To nie usterka,
> to koszt „kierownik wszędzie".

### Per projekt — gdy chcesz tylko w jednym

```powershell
# w katalogu projektu, do którego chcesz wdrożyć tryb
powershell -ExecutionPolicy Bypass -File <ścieżka>\wdroz.ps1
```

Po instalacji globalnej `wdroz.ps1` **nic nie robi** w projekcie — żeby nie
dublować rejestru i zasad. Obejście, gdy naprawdę chcesz wdrożenie projektowe:
dodaj `-WymusProjektowo`.

Instalator **przed zrobieniem czegokolwiek mówi, co zamierza**: jakie pliki zapisze
i gdzie, że dopisze hooki uruchamiane przy starcie sesji, i że wpisze zasady do
Twoich plików instrukcji. O każdy moduł pyta osobno — odmowa `pamiec` nie blokuje
reszty.

**Na koniec sam sprawdza, czy to naprawdę działa** i wypisuje wynik punkt po
punkcie. Jeśli coś nie wyszło, mówi wprost co i kończy błędem, zamiast udawać
sukces.

Po instalacji **zamknij i otwórz swoje narzędzie na nowo** — Claude Code albo
Codeksa — żeby zasady się załadowały.

### Co się dzieje po instalacji, bez Twojego udziału

**Zasady pilnują się same.** Przy starcie każdej sesji sprawdzane jest, czy blok
zasad nadal siedzi w plikach instrukcji. Jeśli ktoś go skasował, nadpisał plik
albo zmienił konfigurację — wpisuje się z powrotem i dostajesz o tym jedną linię.
Gdy wszystko się zgadza, nie widzisz nic.

**Nowsza wersja narzędzia przychodzi sama.** Przy starcie sesji strażnik robi
`git fetch` w katalogu, z którego wdrażałeś narzędzie, i przewija go do nowszej
wersji. Dopiero potem porównuje, czy wdrożenie w projekcie nie zostało w tyle.
Dzięki temu poprawka wypchnięta na jednej maszynie dociera na drugą bez Twojego
udziału. Gdy coś się podciągnie, dostajesz **jedną linię: z której wersji na
którą**. Pod Claude Code do sieci zagląda **nie częściej niż raz na godzinę** —
start okna nie ma na co czekać. Pod Codeksem robi to **przy każdym starcie
sesji**, bo tam chodzi w tle i nikt na niego nie czeka.

**Obie te rzeczy robi strażnik, a wołają go hooki `SessionStart` — Claude Code
i Codeksa.** Zadania okresowego w Harmonogramie zadań Windows **nie ma**:
instalator go nie zakłada, a stare `MegaRuchaczOdswiez` ze starszej wersji zdejmuje
i mówi o tym jedną linią. Pod Codeksem strażnik chodzi w tle i robi dokładnie to
samo: pobiera nowszą wersję, pilnuje zasad, pilnuje sufitów i nanosi poprawki na
wdrożenie — tyle że melduje do dziennika `~\.claude\.megaruchacz-tlo.log`, a nie
na ekran. Jedyny warunek: hooki Codeksa trzeba raz zatwierdzić przez `/hooks`.

Wniosek praktyczny: **narzędzie nie zaktualizuje się, dopóki nie otworzysz nowego
okna**. Sesja, która chodzi od wczoraj, pracuje na wczorajszej wersji.

Pobranie jest celowo tchórzliwe — nigdy nie rusza Twojej pracy:

- **masz w katalogu narzędzia niezapisane zmiany** → nie pobiera nic, mówi o tym
  jednym zdaniem i pracuje na tym, co jest;
- **historia się rozjechała** (masz własne commity, których nie ma na zdalnej) →
  melduje i zostawia; przewija wyłącznie „do przodu", nigdy na siłę;
- **nie ma sieci, gita, zdalnej albo sieć nie odpowiada w kilka sekund** → cisza,
  sesja rusza normalnie na tym, co leży na dysku.

Dalej poprawki wchodzą do projektu według wersji:

| Zmiana wersji | Co się dzieje |
|---|---|
| trzecia cyfra (0.5.0 → 0.5.1) | poprawka nakłada się sama, jedna linia informacji |
| druga cyfra (0.5 → 0.6) | poprawki wchodzą, **nowa funkcja jest proponowana** z opisem kosztu |
| pierwsza cyfra (0.x → 1.0) | nic automatycznie, trzeba wdrożyć ręcznie |

**Czego strażnik nie zrobi za Ciebie:** nie włączy nowej funkcji (drugiej cyfry)
ani przebudowy (pierwszej) — od tego jest `wdroz.ps1`, a strażnik podaje gotową
komendę. Nie zaktualizuje też modułu `pamiec` (Lore): ten aktualizuje się
wyłącznie własnym instalatorem, bo potrafi kosztować pobieranie i zadanie
w harmonogramie.

Odmowa nowej funkcji jest zapamiętywana — nie będzie o nią pytać przy każdym
oknie. **Twoje pliki robocze** (rejestr zadań, mapa projektu) nigdy nie są
nadpisywane.

**Nic nie ucina się po cichu.** Zasady doklejane do rozmowy mają swoje sufity,
a tekst ponad sufit narzędzie obcina bez słowa — przepada wtedy koniec zasad.
Dlatego sprawdzają to i instalator, i strażnik, przy każdym przebiegu, a gdy tekst
się nie mieści, ostrzeżenie ląduje na jego **początku**: pierwsza linia to jedyne
miejsce, które na pewno dojdzie do modelu. Przy starcie sesji dostajesz jedną
linię w rodzaju `pamiec: wiadomosc +207 tokenow, start sesji +2941 tokenow, nic
nie jest ucinane` — co znaczą te dwie liczby, mówi „Ile to kosztuje — dwa
rachunki". Pełny rachunek, z tabelą wszystkich sufitów i wskazaniem, od którego
nagłówka zaczyna się ucięta część: `powershell -ExecutionPolicy Bypass -File
narzedzia\koszt-pamieci.ps1`.

**Zmierzone 2026-09-17: Claude Code nie ucina wstrzykiwanego tekstu.** Ładunek
64 636 znaków doszedł w całości — zamiast uciąć, Claude Code zapisał go do pliku
i powiedział o tym wprost. Dlatego **świadomie nie ustawiamy tam własnego
limitu**; ucinałby to, co narzędzie przepuszcza. Codex tnie i milczy, więc zapory
są wyłącznie po jego stronie. To jest pomiar, nie ostrożne założenie — nie ma
czego „poprawiać na wszelki wypadek".

## Dwa moduły — bierzesz jeden albo oba

Narzędzie nie jest jedną całością. Składa się z **dwóch niezależnych modułów**
i każdy instaluje się osobno. Możesz wziąć sam tryb pracy, samą pamięć, albo obydwa.

### Moduł `workerzy` — rozdawanie roboty

**Co daje:** agent przestaje być wykonawcą, a staje się kierownikiem. Zadania lecą
równolegle, po udanej robocie zmiany same wracają do `main`, a Ty widzisz meldunek
po ludzku, nie surowe raporty. Pod **Claude Code** dochodzą dwie rzeczy, których
pod samym Codeksem ani opencode nie ma: rzucasz zadanie i **od razu piszesz
następne**, a każdy worker siedzi w osobnej kopii repozytorium, więc nie wchodzą
sobie w pliki.

**Co kosztuje:** nic. Same pliki tekstowe, działa od razu po instalacji.

### Moduł `pamiec` (Lore) — pamięć wszystkich rozmów

**Co daje:** koniec tłumaczenia tego samego w piątym oknie. Agent może przeszukać
**wszystkie Twoje dotychczasowe rozmowy** — z innych projektów, z zeszłego
tygodnia, z okna, które dawno zamknąłeś. Szuka po znaczeniu, nie po słowach:
pytanie po angielsku znajdzie rozmowę po polsku. Do tego sam proponuje zapisanie
rzeczy, które tłumaczysz po raz kolejny.

**Co kosztuje:** ~465 MB jednorazowego pobrania (model), miejsce na bazę (u autora
170 MB po roku), wymaga Pythona, i — najważniejsze — **daje agentowi dostęp do
treści wszystkich Twoich rozmów na tej maszynie**. Instalator pyta o to osobno
i wprost. Nic nie wychodzi poza Twój komputer.

## Gdzie to działa — uczciwie

| Środowisko | `workerzy` | `pamiec` (Lore) |
|---|---|---|
| **Claude Code** (CLI, wtyczka do IDE) | tak, pełny tryb | tak, instalator sam rejestruje |
| **Claude Code w Orce** | tak | tak |
| **Codex w Orce** | tak — workerów odpala Orca | tak, instalator sam rejestruje |
| **Codex sam z siebie** | tak, w wersji dla Codeksa — bez pracy w tle i bez izolowanych kopii repozytorium; hooki wymagają jednorazowego `/hooks` | tak, instalator sam rejestruje |
| **opencode** | tak, w wersji dla opencode — bez pracy w tle i bez izolowanych kopii repozytorium; wtyczka rejestru **nie wymaga zatwierdzania** | tak, instalator sam rejestruje (wpis `mcp.lore` w `opencode.json`) |
| **Claude Desktop** (aplikacja) | **nie** | da się, ale ręcznie — patrz niżej |
| Zwykły GPT, ChatGPT w przeglądarce | nie | nie |

### Maszyna z samym Codeksem — co tam działa, a co nie

Instalator uruchomiony tam, gdzie nie ma Claude Code, **mówi to wprost przed
zapytaniem o zgodę** i nie udaje, że wdrożył więcej, niż wdrożył.

| Co | Na maszynie z samym Codeksem |
|---|---|
| zasady globalne | **działa** — Codex sam wczytuje `~/.codex/AGENTS.md` przy każdej sesji, bez żadnego hooka |
| aktualizacja narzędzia | **dzieje się sama** — hook `SessionStart` woła strażnika w tle przy każdym starcie sesji (po jednorazowym `/hooks`) |
| pilnowanie, czy zasady nie zniknęły | **też działa** — ten sam strażnik wpisuje skasowany blok z powrotem, ale mówi o tym w dzienniku, nie na ekranie |
| `pamiec` (Lore) | **działa w całości** — instalator rejestruje serwer MCP także w Codeksie, a indeks czyta `~\.codex\sessions` |
| tryb workerów (rozdawanie zadań) | **działa w wersji dla Codeksa** — role w `.codex/agents/`, zasady w `AGENTS.md` projektu, rejestr i mapa w `.megaruchacz/` |
| praca w tle | **nie ma** — wątek główny czeka na wszystkich podagentów, użytkownik czeka razem z nim |
| izolowane kopie repozytorium (worktree) | **nie ma** — rozłączności plików pilnuje wyłącznie treść zlecenia i rejestr |
| hooki (zasady na starcie, rejestr workerów) | **działają po jednorazowym zatwierdzeniu** poleceniem `/hooks` w CLI |

Pliki trybu workerów dla Claude Code instalator zapisuje i tak — zaczną działać,
jeśli Claude Code kiedyś się na tej maszynie pojawi.

**Hooki Codeksa wymagają jednego kliknięcia — jednego, nie za każdym razem.**
Codex nie uruchomi hooka, dopóki człowiek nie zatwierdzi go w CLI poleceniem
`/hooks`. Zatwierdzenie dotyczy **definicji** hooka — nazwy zdarzenia, wywoływanej
komendy i limitu czasu — a nie treści skryptu, który ta komenda uruchamia.
Sprawdzone 2026-09-17 w źródłach Codeksa (`hook_hash` w `codex-rs/hooks`)
i potwierdzone odtworzeniem zapisanych skrótów: nasze późniejsze poprawki
w skryptach zaufania NIE unieważniają. Ponownego zatwierdzenia wymagałaby dopiero
zmiana samej linii wywołania — dlatego trzymamy ją stałą, a limit czasu podajemy
jawnie.

Zasady kierownika idą w miarę możliwości przez `AGENTS.md`, który Codex czyta sam,
bez żadnego hooka. Instalator nie nadpisuje jednak `AGENTS.md` śledzonego w gicie —
w takim repozytorium zasady wejdą hookiem `SessionStart`, czyli dopiero po
zatwierdzeniu.

Uwaga na rozmiar: Codex wczytuje `AGENTS.md` **do 32 KiB** — dłuższy plik przycina
i koniec zasad przepada. Strażnik ostrzega o tym jedną linią i robi to również pod
Codeksem, tyle że ostrzeżenie idzie do dziennika `~\.claude\.megaruchacz-tlo.log`,
a nie na ekran — żeby je zobaczyć, trzeba tam zajrzeć.

### Maszyna z samym opencode — co tam działa, a co nie

To ta sama wersja co dla Codeksa, z jedną różnicą: **nic nie trzeba zatwierdzać**.
Wtyczka `.opencode/plugins/mr-log.js` ładuje się sama, a przy starcie woła w tle
strażnika zasad (samoaktualizacja, pilnowanie bloków zasad) — pod Codeksem robi to
hook `SessionStart`, którego opencode nie ma.

| Co | Na maszynie z samym opencode |
|---|---|
| zasady globalne | **działa** — opencode czyta `~/.claude/CLAUDE.md` (zgodność z Claude Code) |
| aktualizacja narzędzia | **dzieje się sama** — wtyczka woła strażnika w tle przy każdym starcie opencode |
| pilnowanie, czy zasady nie zniknęły | **też działa** — ten sam strażnik wpisuje skasowany blok z powrotem |
| `pamiec` (Lore) | **działa** — instalator rejestruje serwer MCP w `opencode.json`; indeks czyta jednak na razie tylko rozmowy Claude Code i Codeksa |
| tryb workerów | **działa** — role w `.opencode/agents/`, rejestr prowadzi wtyczka, mapa i rejestr w `.megaruchacz/` |
| praca w tle | **nie ma** — wątek główny czeka na wszystkich podagentów |
| izolowane kopie repozytorium (worktree) | **nie ma** — rozłączności plików pilnuje wyłącznie treść zlecenia i rejestr |

**Uwaga o zasadach globalnych.** opencode bierze zasady domowe z `~/.claude/CLAUDE.md`
tylko dopóki nie ma `~/.config/opencode/AGENTS.md`. Gdy ten drugi plik powstanie,
wygrywa — i `~/.claude/CLAUDE.md` przestaje być czytany. Instalator celowo go nie
zakłada, żeby nie zgubić tego, co już masz w `CLAUDE.md`.

**Gdy `AGENTS.md` jest śledzony w gicie**, instalator go nie rusza (tak samo jak
pod Codeksem). Pod Codeksem zasady ratuje wtedy hook `SessionStart`; pod opencode
robi to wtyczka — dokłada `.megaruchacz/zasady-kierownika.md` jako plik instrukcji,
o ile w `AGENTS.md` nie ma bloku MegaRuchacza. Nie ma więc podwójnego ładowania.

Granica ról czytających jest słabsza niż pod Codeksem: `edit: deny` blokuje
narzędzia zapisu (`edit`, `write`, `apply_patch`), ale nie `bash` — pisanie przez
powłokę zatrzymuje dopiero treść promptu. Pod Codeksem robi to piaskownica.

### Dlaczego Claude Desktop nie uciągnie modułu `workerzy`

Bo rozdawanie roboty stoi na trzech rzeczach, których aplikacja Claude Desktop
nie ma: **workerów** (osobnych sesji roboczych), **hooków** (kodu uruchamianego
przy starcie sesji, który wstrzykuje zasady) i **izolowanych kopii repozytorium**.
To nie jest kwestia konfiguracji — tych mechanizmów tam po prostu nie ma.
Zasady można sobie tam wkleić ręcznie jako sposób pracy, ale agent wykona
wszystko sam, po kolei.

### Jak jest z Lore w Claude Desktop

Lore to **zwykły serwer MCP** — standard, który Claude Desktop rozumie. Da się go
tam podłączyć, dopisując wpis do jego pliku konfiguracyjnego.

Dwa zastrzeżenia, żeby nie było niespodzianek:

- **Nasz instalator tego nie robi.** Rejestruje Lore w Claude Code i w Codeksie
  CLI. W Desktopie trzeba dopisać wpis ręcznie.
- **Tego wariantu nie sprawdzaliśmy.** Powinien działać, ale nie ręczymy —
  nie testowaliśmy go u siebie.

Lore indeksuje transkrypty Claude Code i Codeksa, więc w Desktopie przeszukiwałbyś
historię z tamtych narzędzi, nie z samego Desktopu.

### Skąd biorą się workerzy — źródło różnic w tabeli

- W **Claude Code** worker to narzędzie, które ma sam model — odpala go, kiedy
  uzna za stosowne.
- W **Codeksie** worker to podagent, którego również odpala sam model — tyle że
  wątek główny czeka na wszystkich naraz i dopiero wtedy odzywa się do Ciebie.
- W **Orce** worker to osobna sesja, którą odpala **Orca**, a nie model. Orce
  jest w zasadzie obojętne, co siedzi w tej sesji: `--agent claude`
  i `--agent codex` są równorzędne.

Dlatego Codex podpięty do Orki dostaje rozdawanie roboty dodatkowo „z zewnątrz" —
niezależnie od własnych podagentów.

Tam, gdzie w tabeli jest „nie", zasady nadal działają jako sposób pracy — agent
po prostu wykonuje wszystko sam, zamiast rozdawać.

## Lore — pamięć rozmów

Serwer MCP indeksujący transkrypty — Claude Code i Codeksa — do lokalnej bazy
z wyszukiwaniem pełnotekstowym i semantycznym (zapytanie po niemiecku znajdzie
rozmowę po polsku). Baza i model leżą w `~\.lore` (a jeśli baza powstała wcześniej
w `~\.claude`, zostaje tam) i **nie wychodzą poza Twoją maszynę**.

Serwer rejestrują trzy narzędzia: Claude Code, Codex CLI i opencode (wpis
`mcp.lore` w `~/.config/opencode/opencode.json`). **Rozmowy z opencode nie są
jeszcze indeksowane** — w opencode przeszukujesz historię Claude Code i Codeksa.
To znany dług, nie przeoczenie.

### Problem, który to rozwiązuje

Tłumaczysz agentowi te same rzeczy w każdym nowym oknie: czym zajmuje się firma,
co znaczą Wasze oznaczenia, jak chcesz pracować. Za każdym razem od zera.

Samo przeszukiwanie rozmów tego nie załatwia, bo **rozmowa to drogi nośnik
wiedzy**: żeby przypomnieć sobie jedno ustalenie, trzeba przeczytać akapity,
w których połowa to myślenie na głos i pomysły później odrzucone. Dlatego pamięć
jest podzielona na warstwy.

### Trzy warstwy

| Warstwa | Co tam jest | Gdzie fizycznie | Kiedy czytane | Koszt |
|---|---|---|---|---|
| **1. Stała** | kim jesteś, czym zajmuje się firma, konwencje | zwykły plik tekstowy | zawsze, przy każdej sesji | mały, ale płacony **za każdym razem** |
| **2. Bieżąca** | sprawy tego tygodnia, co Cię blokuje | ten sam plik, osobna sekcja | zawsze, **z datą i wygasaniem** | mały, płacony przy każdej sesji |
| **3. Referencyjna** | tabele, listy numerów, cenniki | osobne pliki tekstowe | **tylko gdy rozmowa tego dotyczy** | zero, dopóki nikt nie sięgnie |
| **Archiwum rozmów** | wszystko, co kiedykolwiek powiedziałeś agentowi | **baza wektorowa** (Lore) | **tylko gdy agent szuka** | jedno wyszukanie na zadanie |

**Warstwa 3 to zwykłe pliki, nie baza wektorowa.** To rozróżnienie jest ważne
i łatwo je przeoczyć:

- **Warstwy 1–3 to WIEDZA** — fakty spisane po ludzku, krótkie i sprawdzone.
  Leżą w plikach tekstowych, które możesz otworzyć i poprawić notatnikiem.
- **Baza wektorowa to ARCHIWUM ROZMÓW** — surowy zapis tego, co padło, razem
  z myśleniem na głos i pomysłami później odrzuconymi. Nie jest wiedzą, jest
  materiałem, z którego wiedza bywa wyciągana.

Dlaczego tabela SKU nie idzie do bazy wektorowej: wyszukiwanie po znaczeniu jest
świetne do „o czym my wtedy rozmawialiśmy", a bezużyteczne do „podaj mi numer
tego produktu". Przy tabeli chcesz dokładnej wartości, nie czegoś podobnego
w znaczeniu. Zwykły plik robi to lepiej, szybciej i bez modelu.

Dwie pierwsze warstwy są malutkie i wczytują się same, trzecia leży odłogiem,
dopóki nie jest potrzebna. Poniżej każda po kolei.

---

#### Warstwa 1 — STAŁA

**Gdzie leży:** sekcja `## Co wiem` w globalnym pliku instrukcji Twojego narzędzia
(`~/.claude/CLAUDE.md`, a dla Codeksa `~/.codex/AGENTS.md`), poza blokiem
wstawianym przez instalator — żeby aktualizacje narzędzia nigdy jej nie nadpisały.

**Co tam wchodzi**, w czterech kategoriach:

- **O Tobie** — czym się zajmujesz, za co odpowiadasz, czego nie chcesz robić,
  jak wolisz dostawać odpowiedzi. Bez tego agent źle dobiera poziom wyjaśnień.
- **O firmie** — czym się zajmuje, jak jest zbudowana, **jakim językiem mówi się
  tam o rzeczach**. To ostatnie jest niedoceniane: jeśli w Twojej branży „zapachy"
  znaczą asortyment, a nie metaforę, agent musi to wiedzieć, zanim zgadnie źle.
- **Nad czym pracujesz** — projekty, po co powstają, jakie decyzje już zapadły.
- **Jak pracujesz** — konwencje, narzędzia, czego nigdy nie ruszać.

**Rozmiar:** rzędu stu linii. Ma się mieścić w kilku tysiącach tokenów, bo jest
doklejana do każdej rozmowy. Gdy rośnie — znaczy, że część należy do warstwy 3.

**Jak długo żyje:** miesiącami. Zmiana wymaga Twojego potwierdzenia.

---

#### Warstwa 2 — BIEŻĄCA

**Gdzie leży:** podsekcja `### Bieżące` w tym samym pliku.

**Format jest obowiązkowy:** `- [RRRR-MM-DD] treść`. Bez daty wpis nie ma prawa
tam trafić, bo data jest jedynym mechanizmem, który chroni przed gniciem.

**Co tam wchodzi:** nad czym siedzisz w tym tygodniu, co czeka na czyjąś decyzję,
co się zacięło, jaki eksperyment jest w toku.

**Wygasanie:** wpis starszy niż **14 dni** przestaje być traktowany jako prawda.
Agent nie buduje na nim działania i nie podaje go jako aktualnego stanu rzeczy —
zamiast tego pyta jednym zdaniem, czy nadal obowiązuje. Wtedy albo odświeża datę,
albo wpis znika.

**Awans do warstwy 1:** wpis, który przy przeglądzie okazuje się trwały, przenosi
się do STAŁEJ i traci datę. To naturalna droga — rzeczy zaczynają jako bieżące,
a okazują się regułą.

---

#### Warstwa 3 — REFERENCYJNA

**Gdzie leży:** osobne pliki w katalogu `~/.claude/wiedza/`.

**Co tam wchodzi:** pełne tabele, listy numerów, cenniki, szczegóły integracji —
wszystko, co jest za długie, żeby doklejać do każdej rozmowy, a bywa potrzebne
w całości raz na jakiś czas.

**Jak agent o nich wie:** w warstwie 1 zostaje **jedna linia na plik** — że taki
plik istnieje i co w nim jest. Agent sięga po treść dopiero wtedy, gdy rozmowa
tego dotyczy. To jest cały mechanizm: indeks jest tani i zawsze obecny, zawartość
droga i czytana na żądanie.

---

### Ile to kosztuje — dwa rachunki

To są różne pieniądze, więc nie sumujemy ich w jedną liczbę.

**Przy KAŻDEJ Twojej wiadomości** doklejane jest krótkie przypomnienie zasad
pracy — hook `UserPromptSubmit`, ładunek z `.claude\orchestrator-reminder.json`
(Claude Code) albo `szablony-codex\przypomnienie.json` (Codex). Dziś **619 znaków
pod Claude Code, 592 pod Codeksem — czyli około 200 tokenów**. I nic poza tym.

**RAZ, przy starcie sesji** wchodzi reszta i siedzi w rozmowie do jej końca: blok
zasad wpisany do `~\.claude\CLAUDE.md` i `~\.codex\AGENTS.md`, warstwa **stała**,
warstwa **bieżąca** oraz zasady kierownika — pod Codeksem wstrzykiwane hookiem
`SessionStart`, pod Claude Code idące przez `CLAUDE.md`. Dziś u autora razem
**8 820 znaków, czyli około 2 940 tokenów**.

**Warstwa referencyjna — pliki w `wiedza\` — nie kosztuje nic**, dopóki rozmowa
jej nie dotyczy; agent czyta je na żądanie. To jest sedno podziału: do warstwy
stałej idzie wyłącznie to, co ma zmieniać zachowanie **bez pytania** (pułapki,
zakazy, preferencje). Wszystko, co da się sprawdzić dopiero wtedy, gdy temat się
pojawi, idzie do plików referencyjnych albo do archiwum rozmów.

Obie liczby to **szacunek, nie pomiar tokenizera**: liczymy znaki ładunku
i dzielimy przez trzy. Prawdziwy rachunek bywa o kilkanaście procent inny —
chodzi o rząd wielkości i o to, która pozycja jest najdroższa. Widać je na żywo:
jedną linią przy starcie sesji, a w całości poleceniem
`powershell -ExecutionPolicy Bypass -File narzedzia\koszt-pamieci.ps1`.

---

### Co dzieje się samo, bez Twojego udziału

| Kiedy | Co się dzieje |
|---|---|
| co 10 minut | nowe rozmowy trafiają do archiwum wektorowego |
| przy starcie komputera | przegląd wczorajszych rozmów, wyławianie faktów, przydział warstw |
| przy starcie sesji (Claude Code i Codex) | jedna linia: rachunek za pamięć, a gdy coś jest ucinane — alarm |
| raz w tygodniu | sprawdzenie, czy zapisane fakty nadal się zgadzają |

**Cykl dzienny jest odporny na przerwy.** Sprawdza przed pracą, czy jesteś
zalogowany, czy jest sieć i czy starcza limitu — a gdy czegoś brakuje, **odkłada
zamiast udawać porażkę**. Ponawia co 10 minut, najwyżej pięć razy dziennie.
Żaden dzień nie zostaje pominięty: nieudany przebieg nie przesuwa znacznika, więc
nazajutrz materiału jest po prostu więcej i nadrabia się partiami.

### Skąd wiadomo, co warto zapisać

Trzy sygnały, każdy inny:

- **Powiedziałeś to wprost** — agent proponuje zapis w trakcie rozmowy.
- **Maszyna to potwierdziła** — fakt zawierający ścieżkę, która istnieje, wchodzi
  do wiedzy bez pytania. Nie ma czego zatwierdzać, skoro to sprawdzalna prawda.
- **Powtarzałeś to wielokrotnie** — archiwum potrafi znaleźć powtórzenia **bez
  czytania go modelem**. Fragmenty o tym samym znaczeniu mają bliskie sobie
  wektory, więc skupisko wypowiedzi z wielu różnych sesji to twardy dowód, że coś
  tłumaczyłeś w kółko. Model czyta wtedy po jednym przedstawicielu ze skupiska —
  kilkadziesiąt urywków zamiast dziesiątek tysięcy.

Przy tym trzecim liczą się **wyłącznie Twoje wypowiedzi**. Pierwsze uruchomienie
na prawdziwym archiwum wypchnęło na szczyt rankingu szablon meldunku samego
agenta, powtarzany w 34 sesjach — to powtarzalna forma, nie powtarzalna wiedza.

#### Co robi poranne wyciąganie faktów

Raz dziennie przeglądane są rozmowy z ostatniej doby i wyłuskiwane z nich trwałe
fakty — modelem, który akurat jest na tej maszynie (`claude` albo `codex`).
Cztery rzeczy, które trzymają to w ryzach:

- **Tylko nowy materiał** od ostatniego przebiegu, nie całe archiwum.
- **Twardy sufit** na ilość materiału — koszt jest przewidywalny, nie rośnie
  z gadatliwością dnia.
- **Wywołania narzędzi są odsiewane** przed wysłaniem — to szum, nie wiedza.
- **Wynik trafia do poczekalni**, nie do obowiązującej wiedzy. Automat **proponuje**,
  Ty zatwierdzasz. Bo wyciągnięty z kontekstu „fakt" potrafi być bzdurą, a wpis
  w warstwie stałej jest traktowany jako prawda.

### Dlaczego wpisy bieżące wygasają

Bo to jest sposób, w jaki taka pamięć gnije. „Produkt X się męczy" jest bezcenne
w środę i **szkodliwe za miesiąc** — agent zbuduje na tym nieaktualny wniosek
i poda go jako fakt. Dlatego każdy wpis bieżący ma datę, a po dwóch tygodniach
bez potwierdzenia przestaje być traktowany jako prawda.

### Jak wiedza tam trafia

- **Agent sam proponuje zapis**, gdy tłumaczysz mu coś trwałego, czego nie ma
  w plikach. Nie czeka na polecenie „zapamiętaj".
- **Powtórzenie jest dowodem.** Jeśli to samo pojawia się w kilku wcześniejszych
  rozmowach, agent to widzi w Lore i mówi wprost: tłumaczysz mi to trzeci raz.
- **Sprzeczność rozstrzygasz Ty.** Gdy powiesz coś innego niż zapis, agent pyta,
  co jest aktualne — zamiast cicho nadpisać albo cicho trzymać się starego.

Twoja wiedza zostaje **na Twoim dysku**, poza repozytorium. Kto zainstaluje to
narzędzie, dostaje pusty mechanizm, nie cudzą wiedzę.

## Stan i dług — co jeszcze nie działa

Wolimy to napisać, niż udawać, że jest komplet.

- **Pod Codeksem i opencode strażnik melduje do dziennika, nie na ekran.** Robi
  wszystko to samo co pod Claude Code, ale żeby zobaczyć, co powiedział, trzeba
  zajrzeć do `~\.claude\.megaruchacz-tlo.log`.
- **Rejestr okien dla panelu VS Code prowadzą tylko workerzy Claude Code.**
  Podagenci Codeksa i opencode piszą do rejestru pracy, ale w panelu ich nie zobaczysz.
- **Lore nie indeksuje jeszcze rozmów z opencode.** Serwer MCP jest zarejestrowany
  i działa, ale w opencode przeszukujesz historię Claude Code i Codeksa. Czytnik
  bazy `opencode.db` to osobna robota.
- **Panel VS Code** ma zaszytą ścieżkę do skryptu i działa tylko przy repozytorium
  w konkretnej lokalizacji.
- **Tylko Windows.** Instalator jest w PowerShellu; wersji na Linuksa i maca nie
  planujemy, dopóki nikt ich nie potrzebuje.
- **Mierzymy na oko.** Reguły w `CLAUDE.md` mają uzasadnienia, ale nie mamy liczb,
  które by potwierdzały, ile faktycznie oszczędzają.

Co jest przetestowane: moduł pamięci ma **131 testów** (`uv run pytest` w `lore/`),
a instalator sprawdza sam siebie po każdym wdrożeniu.
