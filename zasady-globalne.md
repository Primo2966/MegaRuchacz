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

---
<!-- TREŚĆ DO WSTRZYKNIĘCIA PONIŻEJ TEJ LINII -->

## Pamięć rozmów (Lore)

Na tej maszynie działa przeszukiwalna pamięć **wszystkich** rozmów — moduł `lore`,
narzędzia `lore_search` i `lore_context`. Indeksowanie chodzi samo w tle, co
10 minut, i obejmuje inne okna, inne projekty oraz wcześniejsze dni.

**Na starcie każdego niebanalnego zadania zrób jedno wyszukanie w Lore.** Jedno —
nie serię. Zanim zaczniesz rozpoznanie, zanim zadasz użytkownikowi pytanie
o kontekst, zanim założysz, że czegoś nie ustalaliście. Jedno wywołanie kosztuje
ułamek tego, co runda pytań albo rozpoznanie powtarzające cudzą pracę.

„Niebanalne" znaczy: cokolwiek, co wymaga zrozumienia projektu, wraca do tematu
sprzed dziś, albo dotyczy decyzji. Nie rób tego przy „popraw literówkę" ani przy
pytaniu, na które odpowiedź masz przed oczami.

Poza tym sięgaj do Lore zawsze, gdy:

- użytkownik powołuje się na wcześniejsze ustalenie — „ustaliliśmy", „jak
  w tamtym projekcie", „mówiłem ci kiedyś", „wróćmy do tego",
- masz zadać pytanie, które brzmi jak już kiedyś zadane (konfiguracja, dane
  dostępowe, wybór podejścia),
- masz uruchomić rozpoznanie w kwestii wyglądającej na rozstrzygniętą wcześniej.

**Znalezisko z pamięci to trop, nie dowód.** W zapisie siedzą też pomysły
porzucone, ślepe uliczki i decyzje później odwrócone. Zanim na czymś zbudujesz
działanie — potwierdź to w plikach, w konfiguracji albo u użytkownika. Nigdy nie
przedstawiaj fragmentu rozmowy jako aktualnego stanu projektu.

Gdy coś stamtąd wyciągasz, powiedz to jednym zdaniem („to ustalaliśmy
wtedy-a-wtedy w projekcie X"), żeby użytkownik wiedział, skąd się to wzięło
i mógł zaprzeczyć.

## Zapisywanie wiedzy — nie czekaj, aż ktoś poprosi

Użytkownik tłumaczy te same rzeczy w kółko, w różnych oknach: jak zbudowana jest
firma, ile czego jest, co znaczą numery, dokąd to wszystko zmierza. To jego czas,
marnowany na przypominanie czegoś, co można było zapisać raz.

**Gdy użytkownik wyjaśnia Ci coś trwałego, czego nie ma w plikach — sam zaproponuj
zapisanie.** Jednym zdaniem, w trakcie, bez robienia z tego ceremonii. Nie czekaj
na polecenie „zapamiętaj".

Trwałe znaczy: fakt o firmie, produkcie, procesie albo o tym, jak użytkownik chce
pracować. Nie zapisujesz bieżącego stanu zadania, chwilowych decyzji ani rzeczy,
które wynikają wprost z kodu.

Gdzie to trafia:

- **Krótkie i zawsze potrzebne** (czym się zajmujemy, jak pracujemy, nazewnictwo,
  dokąd zmierzamy) → sekcja „Wiedza o firmie" w tym samym pliku, poza tym blokiem.
- **Długie dane referencyjne** (tabele, listy numerów, cenniki, szczegóły
  integracji) → osobny plik w katalogu `wiedza/` obok tego pliku. W sekcji „Wiedza
  o firmie" zostaje wtedy jedna linia: że taki plik istnieje i co w nim jest.
  Czytasz go dopiero wtedy, gdy rozmowa go dotyczy — nie przy każdym zadaniu.

**Zapisane nie znaczy prawdziwe na zawsze.** Jeśli użytkownik mówi coś sprzecznego
z zapisem, nie kłóć się z plikiem — zapytaj, co jest aktualne, i popraw wpis.
