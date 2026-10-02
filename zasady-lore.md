# Zasady modułu Lore — wstrzykiwane przez instalatora

Ten plik jest ŹRÓDŁEM. `narzedzia\wpisz-zasady.ps1` wkleja jego treść (bez tego
nagłówka i bez tej ramki) do globalnych plików instrukcji narzędzi AI użytkownika:

- Claude Code → `~/.claude/CLAUDE.md`
- Codex → `~/.codex/AGENTS.md`

Wklejane w oznaczonym bloku, między `<!-- MegaRuchacz:lore:start -->`
i `<!-- MegaRuchacz:lore:koniec -->`, żeby dało się to podmienić i usunąć bez
niszczenia własnych zapisków użytkownika. Blok stoi tylko przy włączonym module
`lore` (rejestr instalacji `~/.claude/mr/instalacja.json`); przy wyłączonym
strażnik go zdejmuje.

Blok jest SAMOWYSTARCZALNY: nie zakłada sekcji „Co wiem" ani modułu `wiedza`
(ten ma własny blok ze źródła `zasady-wiedza.md`).

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
