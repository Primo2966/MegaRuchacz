<img src="logo.svg" width="96" align="right" alt="">

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

| Katalog | Co to |
|---|---|
| `CLAUDE.md` | zasady kierownika — serce całości |
| `.claude/agents/` | prompty czterech ról: implementer, scout, verifier, zastępca |
| `.claude/` | konfiguracja hooków i pliki stanu |
| `lore/` | Lore — serwer MCP z przeszukiwalną pamięcią rozmów (składnik opcjonalny) |
| `rozszerzenie/` | panel VS Code: lista okien zadaniowych, licznik workerów |
| `wdroz.ps1` | instalator — wdraża tryb do wskazanego projektu |
| `nowe-zadanie.ps1` | zakłada izolowaną kopię repo na jedno zadanie |

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

Instalator **przed zrobieniem czegokolwiek powie, co zamierza**: co zapisze, gdzie,
i czy ma dołożyć Lore. Lore wymaga osobnej zgody, bo oznacza
pobranie ~465 MB modelu i danie agentowi dostępu do treści Twoich rozmów.
Odmowa nie blokuje reszty — dostajesz sam tryb pracy.

Po instalacji **zamknij i otwórz Claude Code na nowo**, żeby zasady się załadowały.

## Co działa gdzie — uczciwie

| Narzędzie | Zasady pracy | Rozdawanie roboty workerom | Lore (pamięć rozmów) |
|---|---|---|---|
| Claude Code | tak | tak — własnym narzędziem | tak |
| Claude Code w Orce | tak | tak | tak |
| Codex w Orce | tak | tak — workerów odpala Orka | w przygotowaniu |
| Codex sam z siebie | tak | **nie** | w przygotowaniu |
| Zwykły GPT i reszta | tak | nie | nie |

Różnica między dwoma ostatnimi wierszami jest istotna i sprowadza się do tego,
**skąd biorą się workerzy**:

- W Claude Code worker to narzędzie, które ma sam model — odpala go, kiedy uzna
  za stosowne.
- W Orce worker to osobna sesja, którą odpala **Orca**, a nie model. Orce jest
  w zasadzie obojętne, co siedzi w tej sesji: `--agent claude` i `--agent codex`
  są równorzędne.

Dlatego Codex podpięty do Orki dostaje rozdawanie roboty „z zewnątrz" — nie dlatego,
że nabył nową umiejętność, tylko dlatego, że steruje nim coś, co ją ma. Codex
uruchomiony samodzielnie, poza Orką, workerów nie ma i mieć nie będzie.

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

## Stan i dług

Rzeczy, o których wiemy, że są niedokończone:

- **Brak testów** w części odpowiadającej za historię rozmów.
- **Czytnik transkryptów Codeksa** jeszcze nie istnieje.
- **Panel VS Code** ma zaszytą ścieżkę do skryptu i działa tylko przy repozytorium
  w konkretnej lokalizacji.
