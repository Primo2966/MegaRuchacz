# Zasady modułu Wiedza — wstrzykiwane przez instalatora

Ten plik jest ŹRÓDŁEM. `narzedzia\wpisz-zasady.ps1` wkleja jego treść (bez tego
nagłówka i bez tej ramki) do globalnych plików instrukcji narzędzi AI użytkownika:

- Claude Code → `~/.claude/CLAUDE.md`
- Codex → `~/.codex/AGENTS.md`

Wklejane w oznaczonym bloku, między `<!-- MegaRuchacz:wiedza:start -->`
i `<!-- MegaRuchacz:wiedza:koniec -->`, żeby dało się to podmienić i usunąć bez
niszczenia własnych zapisków użytkownika. Blok stoi tylko przy włączonym module
`wiedza` (rejestr instalacji `~/.claude/mr/instalacja.json`); przy wyłączonym
strażnik go zdejmuje. Sekcja „Co wiem" stoi NAD blokami MegaRuchacza i do bloku
nie należy.

Blok jest SAMOWYSTARCZALNY: nie każe używać `lore_search` ani „Z ARCHIWUM" (to
moduł `lore`, blok ze źródła `zasady-lore.md`). `{{ZRODLO}}` w treści zamienia się
przy wpisywaniu na katalog repozytorium MegaRuchacza na tej maszynie.

**Ten tekst jedzie z KAŻDYM zapytaniem użytkownika.** Każde zbędne zdanie jest
mnożone przez liczbę wszystkich jego rozmów. Pisz regułę i jej warunki, nie
uzasadnienie — pełne wyjaśnienia „dlaczego tak" należą do `README.md`, który
czytają ludzie, a nie do tego bloku, który czyta model. Przy zmianach sprawdzaj
rozmiar: `narzedzia\koszt-pamieci.ps1`.

---
<!-- TREŚĆ DO WSTRZYKNIĘCIA PONIŻEJ TEJ LINII -->

## Wiedza („Co wiem")

Automat raz dziennie wyławia fakty z wiadomości użytkownika i wpisuje je sam,
bez pytania. Warstwy:

1. **BIEŻĄCA** — podsekcja „Bieżące", format `- [RRRR-MM-DD] treść`. Tu trafia
   każdy nowy fakt.
2. **STAŁA** — reszta „Co wiem". Fakt z bieżącej awansuje sam, gdy padnie w dwóch
   różnych rozmowach albo gdy Claude go użyje w innym dniu (i w innej rozmowie).
   Wpisy dodane ręcznie są przypięte — nigdy nie zasypiają.
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

**„Cofnij <id>"** → `uv --directory "{{ZRODLO}}\lore" run python -m lore.verify --cofnij <id>`
(lista: `--zmiany`).
