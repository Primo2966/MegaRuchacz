# Zasady globalne — wstrzykiwane przez instalatora

Ten plik jest ŹRÓDŁEM. Instalator wkleja jego treść (bez tego nagłówka i bez tej
ramki) do globalnych plików instrukcji narzędzi AI użytkownika:

- Claude Code → `~/.claude/CLAUDE.md`
- Codex → `~/.codex/AGENTS.md`

Wklejane w oznaczonym bloku, między `<!-- MegaRuchacz:start -->`
i `<!-- MegaRuchacz:koniec -->`, żeby dało się to podmienić i usunąć bez
niszczenia własnych zapisków użytkownika.

Dotyczy zachowań obowiązujących we WSZYSTKICH projektach, nie tylko tam, gdzie
wdrożony jest tryb MegaRuchacza. Rzeczy związane z rozdawaniem roboty workerom
są w `CLAUDE.md`, nie tutaj.

**Ten tekst jedzie z KAŻDYM zapytaniem użytkownika.** Każde zbędne zdanie jest
mnożone przez liczbę wszystkich jego rozmów. Pisz regułę i jej warunki, nie
uzasadnienie — pełne wyjaśnienia „dlaczego tak" należą do `README.md`, który
czytają ludzie, a nie do tego bloku, który czyta model. Przy zmianach sprawdzaj
rozmiar: `narzedzia\koszt-pamieci.ps1`.

---
<!-- TREŚĆ DO WSTRZYKNIĘCIA PONIŻEJ TEJ LINII -->

## Pamięć rozmów (Lore)

Działa przeszukiwalna pamięć wszystkich rozmów na tej maszynie — narzędzia
`lore_search` i `lore_context`. Obejmuje inne okna, projekty i wcześniejsze dni.

**Na starcie każdego niebanalnego zadania zrób jedno wyszukanie.** Jedno, nie
serię. Niebanalne = wymaga zrozumienia projektu, wraca do tematu sprzed dziś albo
dotyczy decyzji. Nie przy literówce.

Sięgaj też zawsze, gdy użytkownik powołuje się na ustalenie („ustaliliśmy",
„mówiłem ci kiedyś"), gdy masz zadać pytanie brzmiące jak już zadane albo robić
rozpoznanie w sprawie wyglądającej na rozstrzygniętą.

**Znalezisko to trop, nie dowód** — także fragmenty „Z ARCHIWUM" doklejane
automatycznie do wiadomości. W zapisie są pomysły porzucone i decyzje odwrócone.
Potwierdź w plikach albo u użytkownika, zanim na tym zbudujesz działanie. Mów,
skąd to masz.

## Wiedza („Co wiem")

Automat raz dziennie wyławia fakty z wiadomości użytkownika i wpisuje je sam,
bez pytania. Warstwy:

1. **BIEŻĄCA** — podsekcja „Bieżące", format `- [RRRR-MM-DD] treść`. Tu trafia
   każdy nowy fakt.
2. **STAŁA** — reszta „Co wiem". Fakt z bieżącej awansuje sam, gdy padnie w dwóch
   różnych rozmowach. Wpisy dodane ręcznie są przypięte — nigdy nie zasypiają.
3. **REFERENCYJNA** — pliki w `wiedza/`, w stałej jedna linia odsyłacza. Czytaj
   je tylko, gdy rozmowa ich dotyczy.

**Gdy użytkownik wyjaśnia coś trwałego, czego nie ma w plikach, albo tłumaczy coś
kolejny raz — sam zaproponuj zapis w stałej**, jednym zdaniem. Trwałe: kim jest,
czym zajmuje się firma i jak mówi o swoich rzeczach, projekty i decyzje, sposób
pracy. Nie: stan zadania, rzeczy wynikające z kodu.

**Sufit stałej: 8 000 znaków.** Blisko sufitu nie dopisuj — przenieś najdłuższe
zestawienie do `wiedza/`, zostaw odsyłacz i powiedz o tym.

**Wpis bieżący starszy niż 14 dni jest podejrzany** — nie buduj na nim działania.
Wpisy automatu znikają same; przy ręcznym zapytaj, czy obowiązuje, i odśwież datę
albo usuń.

**Sprzeczność: wygrywa nowsze.** Gdy użytkownik mówi coś innego niż zapis — popraw
wpis i powiedz jednym zdaniem, co było. Resztę rozstrzyga automat; stara wersja
idzie do `wiedza/historia-zmian.md`. Nie pytaj użytkownika o zatwierdzanie faktów.

**„Cofnij <id>"** → `uv --directory <katalog lore> run python -m lore.verify
--cofnij <id>` (ten katalog, z którego chodzi serwer MCP `lore`; lista: `--zmiany`).
