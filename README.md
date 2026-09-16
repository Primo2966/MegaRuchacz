<img src="logo.png" width="110" align="right" alt="">

# MegaRuchacz

Tryb pracy, w którym agent AI przestaje być wykonawcą, a staje się **kierownikiem**:
przyjmuje od Ciebie zadanie po zadaniu, rozdaje je workerom pracującym równolegle
w izolowanych kopiach repozytorium i melduje efekt prostym językiem.

Kluczowa różnica wobec zwykłej pracy z agentem: **nie czekasz**. Rzucasz zadanie,
dostajesz klawiaturę z powrotem w sekundach i piszesz następne. Roboty pilnuje
kierownik, nie Ty.

W zestawie jest też **Lore — przeszukiwalna pamięć wszystkich Twoich rozmów** z agentem —
żeby ustalenie z innego okna sprzed tygodnia nie przepadło.

---

## Co tu jest

| Co | Do czego |
|---|---|
| `CLAUDE.md` | zasady kierownika — serce modułu `workerzy` |
| `zasady-globalne.md` | zasady wpisywane do plików instrukcji narzędzi AI |
| `.claude/agents/` | prompty czterech ról: implementer, scout, verifier, zastępca |
| `lore/` | moduł `pamiec` — serwer MCP z przeszukiwalną pamięcią rozmów |
| `narzedzia/` | instalator pamięci, wpisywanie zasad, strażnik |
| `rozszerzenie/` | panel VS Code: lista okien zadaniowych, licznik workerów |
| `wdroz.ps1` | główny instalator — wdraża wybrane moduły do projektu |
| `nowe-zadanie.ps1` | zakłada izolowaną kopię repo na jedno zadanie |
| `ZMIANY.md` | historia wersji — co doszło i co się zmieniło |

## Cztery role

- **implementer** — wprowadza konkretną zmianę w wyznaczonych plikach. Pracuje
  w osobnej kopii repozytorium, więc dwa zadania w tych samych plikach mogą lecieć
  naprawdę równolegle.
- **scout** — rozpoznanie: gdzie co leży. Tylko czyta, niczego nie blokuje.
- **verifier** — sprawdza pojedynczą zmianę: czy działa i czy nie psuje reszty.
- **zastępca** — sprawdza, czy **całość** nadal trzyma się kupy po serii
  równoległych zmian. Uruchamiany w punktach scalenia, nie po każdym zadaniu.

## Wymagania

- **Windows** — instalator jest w PowerShellu. Wersji na Linuksa i maca nie ma
  i na razie nie planujemy; to świadoma decyzja, nie przeoczenie.
- **git** — izolacja workerów stoi na `git worktree`.
- **Node.js** — na nim działa mechanizm zapisujący, co robią workerzy.
- **Claude Code** — pełny tryb (workerzy, hooki, izolacja) działa tam.
- **Python 3.12 + `uv`** — tylko jeśli chcesz Lore, czyli pamięci rozmów.

## Instalacja

```powershell
# w katalogu projektu, do którego chcesz wdrożyć tryb
powershell -ExecutionPolicy Bypass -File <ścieżka>\wdroz.ps1
```

Instalator **przed zrobieniem czegokolwiek mówi, co zamierza**: jakie pliki zapisze
i gdzie, że dopisze hooki uruchamiane przy starcie sesji, i że wpisze zasady do
Twoich plików instrukcji. O każdy moduł pyta osobno — odmowa `pamiec` nie blokuje
reszty.

**Na koniec sam sprawdza, czy to naprawdę działa** i wypisuje wynik punkt po
punkcie. Jeśli coś nie wyszło, mówi wprost co i kończy błędem, zamiast udawać
sukces.

Po instalacji **zamknij i otwórz Claude Code na nowo**, żeby zasady się załadowały.

### Co się dzieje po instalacji, bez Twojego udziału

**Zasady pilnują się same.** Przy starcie każdej sesji sprawdzane jest, czy blok
zasad nadal siedzi w plikach instrukcji. Jeśli ktoś go skasował, nadpisał plik
albo zmienił konfigurację — wpisuje się z powrotem i dostajesz o tym jedną linię.
Gdy wszystko się zgadza, nie widzisz nic.

**Poprawki nakładają się same.** Gdy ściągniesz nowszą wersję narzędzia
(`git pull`), wszystkie projekty, w których je wdrożyłeś, podciągną się przy
najbliższym otwarciu okna. Zasada jest taka:

| Zmiana wersji | Co się dzieje |
|---|---|
| trzecia cyfra (0.5.0 → 0.5.1) | poprawka nakłada się sama, jedna linia informacji |
| druga cyfra (0.5 → 0.6) | poprawki wchodzą, **nowa funkcja jest proponowana** z opisem kosztu |
| pierwsza cyfra (0.x → 1.0) | nic automatycznie, trzeba wdrożyć ręcznie |

Odmowa nowej funkcji jest zapamiętywana — nie będzie o nią pytać przy każdym
oknie. **Twoje pliki robocze** (rejestr zadań, mapa projektu) nigdy nie są
nadpisywane. Nic nie sięga do sieci przy starcie sesji.

## Dwa moduły — bierzesz jeden albo oba

Narzędzie nie jest jedną całością. Składa się z **dwóch niezależnych modułów**
i każdy instaluje się osobno. Możesz wziąć sam tryb pracy, samą pamięć, albo obydwa.

### Moduł `workerzy` — rozdawanie roboty

**Co daje:** agent przestaje być wykonawcą, a staje się kierownikiem. Ty rzucasz
zadanie i **od razu piszesz następne** — nie czekasz, aż skończy. Zadania lecą
równolegle, każde w osobnej kopii repozytorium, więc nie wchodzą sobie w pliki.
Po udanej robocie zmiany same wracają do `main`, a kopie znikają. Ty widzisz
meldunek po ludzku, nie surowe raporty.

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
| **Codex w Orce** | tak — workerów odpala Orca | czytnik w przygotowaniu |
| **Codex sam z siebie** | nie — brak mechanizmu | czytnik w przygotowaniu |
| **Claude Desktop** (aplikacja) | **nie** | da się, ale ręcznie — patrz niżej |
| Zwykły GPT, ChatGPT w przeglądarce | nie | nie |

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

- **Nasz instalator tego nie robi.** Rejestruje Lore wyłącznie dla Claude Code.
  W Desktopie trzeba dopisać wpis ręcznie.
- **Tego wariantu nie sprawdzaliśmy.** Powinien działać, ale nie ręczymy —
  nie testowaliśmy go u siebie.

Lore indeksuje transkrypty Claude Code, więc w Desktopie przeszukiwałbyś swoją
historię z Claude Code. To nadal użyteczne, ale warto wiedzieć, czego szukasz.

### Skąd biorą się workerzy — źródło różnic w tabeli

- W **Claude Code** worker to narzędzie, które ma sam model — odpala go, kiedy
  uzna za stosowne.
- W **Orce** worker to osobna sesja, którą odpala **Orca**, a nie model. Orce
  jest w zasadzie obojętne, co siedzi w tej sesji: `--agent claude`
  i `--agent codex` są równorzędne.

Dlatego Codex podpięty do Orki dostaje rozdawanie roboty „z zewnątrz" — nie
dlatego, że nabył nową umiejętność, tylko dlatego, że steruje nim coś, co ją ma.
Codex uruchomiony samodzielnie, poza Orką, workerów nie ma i mieć nie będzie.

Tam, gdzie w tabeli jest „nie", zasady nadal działają jako sposób pracy — agent
po prostu wykonuje wszystko sam, zamiast rozdawać.

## Lore — pamięć rozmów

Serwer MCP indeksujący transkrypty do lokalnej bazy z wyszukiwaniem pełnotekstowym
i semantycznym (zapytanie po niemiecku znajdzie rozmowę po polsku). Baza i model
zostają **na Twojej maszynie** — nic nie wychodzi na zewnątrz.

Agent sięga do niej, gdy powołujesz się na wcześniejsze ustalenie albo gdy ma zadać
pytanie, które już kiedyś padło w innym oknie. Znalezisko z pamięci traktuje jako
trop do sprawdzenia, nie jako dowód — w zapisie rozmów siedzą też pomysły porzucone
i decyzje później odwrócone.

## Stan i dług — co jeszcze nie działa

Wolimy to napisać, niż udawać, że jest komplet.

- **Czytnik transkryptów Codeksa nie istnieje.** Lore indeksuje dziś wyłącznie
  rozmowy z Claude Code. Wiadomo, gdzie Codex trzyma swoje (`~/.codex/sessions`),
  ale bez prawdziwych próbek nie piszemy czytnika na ślepo.
- **Druga warstwa pamięci jest pusta.** Zamysł jest taki: tania warstwa faktów
  wczytywana zawsze, plus droga warstwa wyszukiwania po rozmowach. Ta druga
  działa. Pierwsza ma zrobiony mechanizm i regułę, ale zapełnia się dopiero
  z użycia — automatycznego wyciągania faktów z archiwum jeszcze nie ma.
- **Panel VS Code** ma zaszytą ścieżkę do skryptu i działa tylko przy repozytorium
  w konkretnej lokalizacji.
- **Tylko Windows.** Instalator jest w PowerShellu; wersji na Linuksa i maca nie
  planujemy, dopóki nikt ich nie potrzebuje.
- **Mierzymy na oko.** Reguły w `CLAUDE.md` mają uzasadnienia, ale nie mamy liczb,
  które by potwierdzały, ile faktycznie oszczędzają.

Co jest przetestowane: moduł pamięci ma **18 testów** (`uv run pytest` w `lore/`),
a instalator sprawdza sam siebie po każdym wdrożeniu.
