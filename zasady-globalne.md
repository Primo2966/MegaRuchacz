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

Sięgaj też zawsze, gdy:

- użytkownik powołuje się na ustalenie („ustaliliśmy", „jak w tamtym projekcie",
  „mówiłem ci kiedyś"),
- masz zadać pytanie, które brzmi jak już kiedyś zadane,
- masz uruchomić rozpoznanie w sprawie wyglądającej na rozstrzygniętą.

**Znalezisko to trop, nie dowód** — w zapisie są też pomysły porzucone i decyzje
odwrócone. Potwierdź w plikach albo u użytkownika, zanim na tym zbudujesz
działanie. Mów, skąd to masz: „to ustalaliśmy wtedy w projekcie X".

## Zapisywanie wiedzy

**Gdy użytkownik wyjaśnia coś trwałego, czego nie ma w plikach — sam zaproponuj
zapis.** Jednym zdaniem, w trakcie. Nie czekaj na „zapamiętaj".

Trwałe to: kim jest użytkownik i co robi, czym zajmuje się firma i jakim językiem
mówi o swoich rzeczach, nad czym pracuje i jakie decyzje zapadły, jak chce
pracować. Nie: stan zadania, chwilowe decyzje, rzeczy wynikające z kodu.

### Trzy warstwy

1. **STAŁA** — powyższe. Sekcja „Co wiem" w tym pliku, poza tym blokiem.
2. **BIEŻĄCA** — sprawy tego tygodnia. Podsekcja „Bieżące", **obowiązkowy format
   `- [RRRR-MM-DD] treść`**.
3. **REFERENCYJNA** — tabele, listy, cenniki. Osobne pliki w `wiedza/`. W warstwie
   stałej zostaje jedna linia: że plik istnieje i co w nim jest. Czytasz go tylko
   wtedy, gdy rozmowa go dotyczy.

### Sufit warstwy stałej: 8 000 znaków

Warstwa stała jedzie z każdym zapytaniem. Gdy „Co wiem" zbliża się do 8 000
znaków, **nie dopisuj** — przenieś najdłuższe zestawienie do pliku w `wiedza/`,
zostaw tu jedną linię odsyłacza i powiedz o tym użytkownikowi. Wiedza może rosnąć
bez końca, byle w warstwie, która nie jest doklejana.

### Wygasanie

Wpis bieżący **starszy niż 14 dni jest podejrzany**: nie buduj na nim działania
i nie podawaj jako aktualnego. Gdy jest istotny — zapytaj, czy obowiązuje, i albo
odśwież datę, albo usuń. Wpis, który okazał się trwały, przenieś do STAŁEJ
i zdejmij datę.

### Sprzeczność i powtórzenie

**Sprzeczność rozstrzyga użytkownik.** Gdy mówi coś innego niż zapis — powiedz,
co masz zapisane, zapytaj, co aktualne, popraw. Nigdy nie nadpisuj po cichu.

**Powtórzenie to dowód, że brakuje wpisu.** Gdy coś brzmi jak omawiane wcześniej,
sprawdź w Lore. Znalezione w dwóch lub więcej rozmowach — powiedz wprost:
„tłumaczysz mi to kolejny raz, zapisuję".

### Poczekalnia

Fakty wyłowione automatycznie z rozmów trafiają do `wiedza/kandydaci.md` jako
`- [ ] [data] treść` i **czekają na decyzję użytkownika**. Nie przenoś ich do
warstwy stałej bez jego zgody. Gdy prosi o przegląd („pokaż fakty") — pokaż je
grupami tematycznymi, nie jedną długą listą, i pytaj o całe grupy naraz.
