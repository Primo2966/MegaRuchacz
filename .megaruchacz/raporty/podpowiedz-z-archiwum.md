# Podpowiedz z archiwum przy kazdej wiadomosci — raport (2026-09-24)

Pliki: `narzedzia/przypomnienie.js` (hook), `lore/lore/recall.py` (szukanie), `lore/tests/test_recall.py`.

## Metoda i czasy (zmierzone na prawdziwej bazie: 55 926 kawalkow, 190 MB, tylko odczyt)

| co | czas |
|---|---|
| goly start Pythona z .venv | 40–50 ms (pierwszy raz 100 ms) |
| `import numpy` | 150 ms cieplo, 1 100 ms zimno |
| zaladowanie modelu wektorowego + jedno zapytanie | **4 700–7 400 ms** |
| zapytanie FTS5 (jedno slowo) | 0,1–0,5 ms |
| recall.py w calosci (wlasny pomiar modulu) | 36–60 ms |
| **caly hook (node + python), 10 wiadomosci x 3 przebiegi** | **mediana 185–201 ms, najgorszy 218–309 ms** |
| hook zabity bezpiecznikiem (proces wisi) | 708 ms — zasady wychodza w calosci |
| sciezka Codeksa pod Windows (powershell -> node) | ~710 ms, z czego ~550 ms to sam start PowerShella |

Wybor: **samo FTS5/BM25, bez modelu**. Model od zera nie miesci sie w budzecie 1 s nawet raz.
Dlugo zyjacy proces z modelem by sie zmiescil, ale to kolejna rzecz do pilnowania na dwoch maszynach.
**Wada:** brak dopasowania znaczeniowego — trafienie wymaga tych samych slow (albo tego samego rdzenia:
dluzsze slowa ida jako prefiks, np. `zapachy` -> `zapac*`). Pytanie ujete innymi slowami niz stara
rozmowa nie znajdzie nic. Dlatego prog jest ostry.

`recall.py` nie importuje `lore.db` (numpy + zapis przy `connect()`), otwiera baze `mode=ro` + `query_only`.

## Limit i prog

- **Limit: 450 znakow (~130–150 tokenow)** na doklejony blok, najwyzej **2 fragmenty** po 110–240 znakow.
  Rachunek: doklejony tekst zostaje w historii i jest czytany ponownie przy kazdym kolejnym wywolaniu
  (~10 na wiadomosc, z bufora ~10% ceny) — blok doklejony N wiadomosci przed koncem sesji kosztuje
  ~150 x N tokenow po pelnej cenie; w sesji na 50 wiadomosci srednio ~3–4 tys. na jedno doklejenie.
  Dodatkowo calosc ladunku miesci sie pod sufitem Codeksa 1 500 znakow (przypomnienie ~620–725 + linia
  cyklu do 300 + blok) — sprawdzone: 1 270 znakow z linia cyklu i dwoma fragmentami.
- **Prog trafnosci:** liczony w oknie 300 znakow, nie w calym kawalku (dlugi kawalek zawiera prawie
  kazdy rdzen gdzies). Trafienie musi miec >= 2 wspolne slowa (>= 3 gdy w wiadomosci sa ponad 3 slowa
  do szukania) i >= 60% wagi idf slow wiadomosci. Przy 0,5 polowa trafien byla szumem; przy 0,6 zero.
- Wiadomosci < 12 znakow i bez >= 2 sensownych slow — w ogole bez szukania.
- Tylko role `user`, `assistant`, `summary`, `conversation`; wyjscia narzedzi i monologi workerow
  (ponad polowa archiwum) pominiete.
- **Bez echa:** kawalki z tej samej sesji (`session_id` z wejscia hooka) wykluczone.
- **Bez powtorek:** identyfikatory doklejone w danej rozmowie zapamietywane w pliku stanu (40 ostatnich
  rozmow); drugi raz ten sam fragment nie idzie. Ten sam fakt z dwoch rozmow — wykrywany przez pokrywanie
  sie slow okna (dziala czesciowo, patrz pkt 10).
- Kazdy fragment: `#id data (sprzed X dni) projekt, rola:` + naglowek „trop, nie dowod; moze byc
  nieaktualne. Calosc: lore_context(id)".

## 10 wiadomosci — co doklejono i ocena

| # | wiadomosc | doklejone | ocena |
|---|---|---|---|
| 1 | ustaw tytul na ebayu dla zestawu SET3-Citrus, limit 80 znakow | #53164 (7 dni): regula 80 znakow + sklad SET3 | trafne, ale **powtarza CLAUDE.md** — zbedny koszt |
| 2 | sprawdz dlaczego robot alibaby nie wyslal wiadomosci do dostawcy | #19235 (15 dni): „robot odmowil, bo cytat przypiety do innej wiadomosci" | **przydatne** |
| 3 | ok | nic — krotka wiadomosc, bez szukania | poprawnie |
| 4 | jak dziala search query performance dla olejkow, dlaczego zero wierszy | nic — najlepsze pokrycie 0,57 < 0,6 | brak; pulapka `view_type='asin'` i tak jest w CLAUDE.md |
| 5 | zrob przeglad kandydatow na fakty w poczekalni | #54367 (6 dni): „Poczekalnia — zgoda, to byl zly pomysl" | **przydatne** (sprzeczne z CLAUDE.md — model powinien dopytac) |
| 6 | czemu worker zameldowal sukces a scalenie mowi already up to date | #53585 (7 dni): regula „zanim skasujesz kopie robocza…" | trafne, ale **powtarza CLAUDE.md projektu**; fragment brudny od logu narzedzia |
| 7 | dodaj do WMS kolumne z data dostawy w tabeli zamowien | #5541 (40 dni): decyzja „bez ALTER na ich tabelach, nowe tabele z kluczem do purchase_orders" | przydatne warunkowo (decyzja z modulu Alibaby w WMS) |
| 8 | ile kosztuje przypomnienie doklejane do kazdej wiadomosci | #54099 (6 dni): „Ile to kosztuje — dwa rachunki" | **przydatne** |
| 9 | napisz maila do klienta po niemiecku ze paczka jest w drodze | nic — pokrycie 0,59 | poprawnie (nic sensownego w archiwum) |
| 10 | kadzidelka backflow biala szalwia numer 31 zdjecia | #47500 + #53932: dwa razy ten sam fakt o numeracji | trafne, **powtarza CLAUDE.md**, a do tego duplikat |

**Uczciwie:** 7 doklejen, zero smieci; **3 naprawde przydatne + 1 warunkowo**, 3 trafne, ale zbedne,
bo powtarzaja zasady, ktore model juz ma. Probka jest stronnicza: wiadomosci ulozylem sam, znajac
tematy archiwum — prawdziwe wiadomosci sa dluzsze i luzniejsze, trafien bedzie mniej.
Najwieksza znana slabosc: **archiwum pelne jest streszczen tego, co juz stoi w CLAUDE.md**, i tego
automat nie odfiltrowuje (nie czyta plikow zasad — to kolejny koszt czasu; do decyzji).

## Proby negatywne (wszystkie: kod 0, poprawny JSON, zasady w calosci)

| przypadek | wynik |
|---|---|
| baza nie istnieje | linia `UWAGA: podpowiedz z archiwum (Lore) nie dziala - ... brak bazy` na poczatku + stan `awaria` |
| proces Lore wisi (sitecustomize z `sleep(5)`) | ubity po 650 ms, calosc 708 ms, linia UWAGA + stan |
| brak srodowiska .venv, baza jest | linia UWAGA z podpowiedzia `instaluj-lore.ps1` |
| brak i .venv, i bazy (Lore nie zainstalowane) | bez linii (to nie awaria), stan `brak-lore` |
| zamiast Pythona program zwracajacy smieci | linia UWAGA „Lore zwrocilo smieci: ..." |
| puste wejscie hooka / wejscie bez `prompt` | linia UWAGA + stan |
| ta sama awaria drugi raz pod rzad | bez linii (powtorka co 6 h), licznik w stanie `ile: 2` |
| ta sama wiadomosc drugi raz w tej samej rozmowie | za 1. razem #19235, za 2. #7816 — bez powtorki |

Stan zapisywany przy kazdym uruchomieniu (znacznik „bylem tu"): `~/.claude/wiedza/.archiwum-stan.json`
(czas, wynik, powod, ms, awaria{powod, od, ile}, pamiec powtorek).
Te same przypadki sa w `lore/tests/test_recall.py` (17 testow, w tym hook przez node).

## Uwagi / poza zakresem

- **Na tej maszynie hooki Claude Code wolaja jeszcze `cat` pliku przypomnienia, nie `przypomnienie.js`**
  (`~/.claude/settings.json` i `.claude/settings.json` projektu). Podpowiedz ruszy dopiero, gdy
  `straznik-zasad.ps1` podmieni polecenie (ma to w `Napraw-Hooki`). Nie ruszalem konfiguracji hookow.
- Codex pod Windows: sprawdzone, ze polecenie z `szablony-codex/hooks.json` (`$o=(node ...)`)
  przekazuje wejscie hooka do node — podpowiedz dziala; sam start PowerShella zjada ~550 ms z budzetu.
- **Incydent:** jedna z prob (`codex.js`) uruchomila hook bez podanego pliku postepu i zuzyla prawdziwy
  `~/.claude/wiedza/.cykl-postep` (stan `koniec` — jednorazowy meldunek „cykl wiedzy skonczony: przeczytane
  168 kawalkow…"). Skrypt usuwa go po pokazaniu, tak jak zaprojektowano; meldunek przepadl. Nie
  odtwarzalem go (nie znam dokladnej tresci pliku).
- Mozliwe dalsze kroki (do decyzji): pokazanie stanu podpowiedzi w `koszt-pamieci.ps1`/nadzorcy;
  odfiltrowanie trafien powtarzajacych CLAUDE.md.
