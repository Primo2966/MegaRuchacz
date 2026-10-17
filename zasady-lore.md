# Zasady modułu Lore — wstrzykiwane przez instalatora

Ten plik jest ŹRÓDŁEM. `narzedzia\wpisz-zasady.ps1` wkleja jego treść (bez tego
nagłówka i bez tej ramki) do globalnych plików instrukcji narzędzi AI użytkownika:

- Claude Code → `~/.claude/CLAUDE.md`
- Codex → `~/.codex/AGENTS.md`

Wklejane w oznaczonym bloku, między `<!-- MegaRuchacz:lore:start -->`
i `<!-- MegaRuchacz:lore:koniec -->`, żeby dało się to podmienić i usunąć bez
niszczenia własnych zapisków użytkownika. Blok stoi, gdy Lore jest zainstalowane
(flaga `lore` w rejestrze instalacji `~/.claude/mr/instalacja.json`); bez flagi
strażnik go zdejmuje. Lore jest obowiązkowe — brak flagi to stan przejściowy do
doinstalowania przez aktualizację.

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

**Wiedza firmy (jfwiedza).** Gdy dostępne jest narzędzie `szukaj_wiedzy`: na starcie
każdego zadania dotyczącego firmy (produkty, oferty, Amazon/eBay/Allegro, klienci,
wysyłki, procedury, ludzie) zrób jedno wyszukanie. Jedno, nie serię. Nie przy czysto
technicznej pracy nad kodem. Sięgaj też zawsze, gdy pada „jak u nas się robi…”,
„co wiemy o…”, albo gdy masz zapytać o coś, co mógł już ustalić ktoś inny w firmie.
Lore to rozmowy z tego komputera, jfwiedza to ustalenia całej firmy — przy temacie
firmowym oba. Gdy serwer nie odpowiada — pracuj dalej bez niego, jednym zdaniem
powiedz, że wiedza firmy jest niedostępna.

Sięgaj też zawsze, gdy użytkownik powołuje się na ustalenie („ustaliliśmy",
„mówiłem ci kiedyś"), gdy masz zadać pytanie brzmiące jak już zadane albo robić
rozpoznanie w sprawie wyglądającej na rozstrzygniętą.

**Znalezisko to trop, nie dowód** — także fragmenty „Z ARCHIWUM" doklejane
automatycznie do wiadomości. W zapisie są pomysły porzucone i decyzje odwrócone.
Potwierdź w plikach albo u użytkownika, zanim na tym zbudujesz działanie. Mów,
skąd to masz.

**Znaczek źródła — w PIERWSZEJ linii odpowiedzi.** Tylko wtedy, gdy treść odpowiedzi
faktycznie opiera się na danych z Lore (`lore_search`, `lore_context`, wstawka
„Z ARCHIWUM”) albo z wiedzy firmy (`szukaj_wiedzy`, wstawka „Z WIEDZY FIRMY”):
pierwsza linia zaczyna się od `🟣 Lore`, `🟠 jfwiedza` albo obu — krótko, sam znaczek.
Samo wyszukanie albo doklejona wstawka, z której nic nie wziąłeś do odpowiedzi
(np. odpowiedź opiera się na świeżym sprawdzeniu) — bez znaczka.
