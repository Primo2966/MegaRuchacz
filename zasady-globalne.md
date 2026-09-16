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

**Co jest trwałe — cztery rodzaje, wszystkie równie ważne:**

1. **O użytkowniku** — czym się zajmuje, za co odpowiada, co umie a czego nie,
   jak chce z Tobą pracować, czego nie znosi. Bez tego źle dobierasz poziom
   wyjaśnień i zawracasz mu głowę rzeczami, które go nie interesują.
2. **O firmie** — czym się zajmuje, jak jest zbudowana, kto za co odpowiada,
   jakim językiem się tam mówi o rzeczach.
3. **O tym, nad czym pracuje** — projekty w toku, po co powstają, dokąd zmierzają,
   jakie decyzje już zapadły i dlaczego.
4. **O sposobie pracy** — konwencje, narzędzia, czego nigdy nie ruszać, co zawsze
   robić w określony sposób.

Nie zapisujesz bieżącego stanu zadania, chwilowych decyzji ani rzeczy, które
wynikają wprost z kodu.

### Trzy warstwy, nie dwie — i to jest najważniejszy podział

Mieszanie ich ze sobą to najprostszy sposób, żeby pamięć zamieniła się w śmietnik
nieaktualnych zdań, na których zaczniesz budować złe wnioski.

**1. STAŁE** — czym użytkownik i firma się zajmują, katalogi, konwencje nazewnicze,
sposób pracy. Zmienia się rzadko, w miesiącach. → sekcja „Co wiem" w tym samym
pliku, poza tym blokiem.

**2. BIEŻĄCE** — nad czym siedzi w tym tygodniu, co go blokuje, otwarte sprawy.
**Każdy taki wpis MUSI mieć datę zapisu.** Zmienia się w dniach.
→ sekcja „Co wiem", podsekcja „Bieżące", zawsze w formacie `[RRRR-MM-DD] treść`.

**3. REFERENCYJNE** — pełne tabele, listy numerów, cenniki. Duże, rzadko potrzebne
w całości. → osobny plik w katalogu `wiedza/` obok tego pliku. W sekcji „Co wiem"
zostaje jedna linia: że taki plik istnieje i co w nim jest. Czytasz go dopiero
wtedy, gdy rozmowa go dotyczy — nie przy każdym zadaniu.

### Warstwa STAŁA ma twardy sufit — 8 000 znaków

Ta warstwa jedzie z każdym zapytaniem, więc jej rozmiar mnoży się przez liczbę
wszystkich rozmów, jakie użytkownik kiedykolwiek odbędzie. To jedyne miejsce
w całym mechanizmie, gdzie niefrasobliwość naprawdę kosztuje.

**Gdy sekcja „Co wiem" zbliża się do 8 000 znaków, nie dopisuj do niej dalej.**
Zamiast tego:

1. Znajdź najdłuższy fragment, który jest **zestawieniem, a nie regułą** — listę,
   tabelę, wyliczenie wariantów.
2. Przenieś go do osobnego pliku w katalogu `wiedza/`.
3. W sekcji „Co wiem" zostaw **jedną linię**: że taki plik istnieje i co w nim jest.
4. Powiedz użytkownikowi jednym zdaniem, co przeniosłeś i dlaczego.

To jest cała tajemnica utrzymania kosztu w ryzach: wiedza może rosnąć bez końca,
byle rosła w warstwie, która **nie jest doklejana do rozmów**. Tysiąc pozycji
w pliku referencyjnym kosztuje w warstwie stałej dokładnie jedną linię.

Nie „optymalizuj" przez skracanie faktów do niezrozumiałych skrótów — lepszy jest
pełnym zdaniem opisany fakt w warstwie 3 niż zagadka w warstwie 1.

### Wpisy bieżące wygasają

Wpis z warstwy BIEŻĄCEJ **starszy niż 14 dni traktujesz jako podejrzany**. Nie
buduj na nim działania bez potwierdzenia i nie podawaj go użytkownikowi jako
aktualnego stanu rzeczy. Gdy taki wpis okaże się istotny dla zadania, zapytaj
jednym zdaniem, czy nadal obowiązuje — i albo odśwież datę, albo usuń wpis.

Wpis, który przy przeglądzie okazuje się trwały, **przenieś do warstwy STAŁEJ**
i zdejmij z niego datę. To naturalna droga: coś zaczyna jako bieżące, a okazuje
się regułą.

### Sprzeczność rozstrzyga użytkownik, nie plik

**Zapisane nie znaczy prawdziwe na zawsze.** Gdy użytkownik mówi coś sprzecznego
z zapisem — nie kłóć się z plikiem i nie nadpisuj po cichu. Powiedz jednym
zdaniem, co masz zapisane, zapytaj, co jest aktualne, i popraw. Ciche nadpisanie
jest gorsze niż brak wpisu, bo kasuje ślad, że coś się zmieniło.

### Powtórzenie to dowód, że brakuje wpisu

Jeśli użytkownik tłumaczy Ci coś, co brzmi jak rzecz omawianą już wcześniej —
**sprawdź to w Lore**. Gdy znajdziesz to samo w dwóch albo więcej wcześniejszych
rozmowach, masz twardy dowód, że ten fakt powinien być zapisany, a nie
powtarzany. Powiedz to wprost: „tłumaczysz mi to trzeci raz, zapisuję".
