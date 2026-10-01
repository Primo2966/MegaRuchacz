# Baza polecanych skilli MegaRuchacza.
#
# Czyta ja narzedzia\skille.ps1 (Import-PowerShellDataFile, PowerShell 5.1) i zakladka
# 'Skille' w oknie nadzorcy. Plik jest zapisany w UTF-8 ZE ZNACZNIKIEM BOM - bez niego
# PowerShell 5.1 czyta go jako ANSI i opisy wychodza jako krzaki.
#
# DODANIE NOWEGO ZRODLA = dopisanie jednego bloku @{ ... } do listy Zrodla:
#   Id       - krotka nazwa bez spacji (klucz w stanie i w dzienniku, nie zmieniac potem)
#   Nazwa    - to, co widzi uzytkownik jako naglowek grupy
#   Adres    - adres repozytorium git (https)
#   Galaz    - galaz, z ktorej bierzemy wersje
#   Sciezka  - katalog w repo, w ktorym leza katalogi skilli (skill = <Sciezka>/<Nazwa>)
#   Opis     - jedno zdanie po polsku, dla laika: co to za zestaw
#   Rodzaj   - 'skille' (domyslnie) albo 'aplikacja' = w repo nie ma skilli do
#              zainstalowania; zrodlo jest tylko pokazywane z wyjasnieniem (Uwaga)
#   Skille   - lista @{ Nazwa; Opis } - Nazwa to katalog skilla w repo; opis po polsku
#              w kilku slowach, pisany z tresci SKILL.md, nie z nazwy.
#              Opcjonalnie: Sciezka (pelna sciezka w repo, gdy skill lezy gdzie indziej
#              niz <Sciezka>/<Nazwa>), Folder (nazwa katalogu u uzytkownika, gdy inna
#              niz w repo), Robocza = $true (autor oznaczyl skill jako wersje robocza).
#
# Stan (co jest pod opieka, z jakiego commita, kiedy sprawdzone) NIE lezy tutaj,
# tylko w ~\.claude\mr\skille\ - ten plik jest tylko lista tego, co polecamy.
@{
  Wersja = 1
  Zrodla = @(
    @{
      Id      = 'superpowers'
      Nazwa   = 'Superpowers (Jesse Vincent)'
      Adres   = 'https://github.com/obra/superpowers'
      Galaz   = 'main'
      Sciezka = 'skills'
      Opis    = 'Nawyki porządnej pracy dla agenta: plan, testy, szukanie przyczyn błędów, sprawdzenie przed ogłoszeniem sukcesu.'
      Skille  = @(
        @{ Nazwa = 'brainstorming';                  Opis = 'Zanim coś zbuduje, dopytuje o cel i wymagania i proponuje projekt do akceptacji.' }
        @{ Nazwa = 'diagnosing-superpowers';         Opis = 'Gdy praca z Superpowers poszła źle (za długo, za drogo, pominięty plan) - ustala dlaczego i pomaga zgłosić błąd autorom.' }
        @{ Nazwa = 'dispatching-parallel-agents';    Opis = 'Dzieli dwa lub więcej niezależnych zadań między kilku pomocników pracujących naraz.' }
        @{ Nazwa = 'executing-plans';                Opis = 'Wykonuje gotowy plan krok po kroku samodzielnie, z punktami kontrolnymi.' }
        @{ Nazwa = 'finishing-a-development-branch'; Opis = 'Po skończonej pracy i zielonych testach pomaga zdecydować, jak ją włączyć: scalić, zgłosić do scalenia albo odłożyć.' }
        @{ Nazwa = 'receiving-code-review';          Opis = 'Uczy przyjmować uwagi z przeglądu kodu z głową: najpierw sprawdzić, czy są słuszne, potem wprowadzać.' }
        @{ Nazwa = 'requesting-code-review';         Opis = 'Po skończonym zadaniu zleca przegląd kodu, żeby sprawdzić, czy spełnia wymagania, zanim pójdzie dalej.' }
        @{ Nazwa = 'subagent-driven-development';    Opis = 'Realizuje plan, oddając każde zadanie osobnemu pomocnikowi i sprawdzając jego pracę.' }
        @{ Nazwa = 'systematic-debugging';           Opis = 'Przy błędzie najpierw metodycznie szuka przyczyny, dopiero potem proponuje poprawkę.' }
        @{ Nazwa = 'test-driven-development';        Opis = 'Najpierw test, który pokazuje brak, potem kod, który go spełnia.' }
        @{ Nazwa = 'using-git-worktrees';            Opis = 'Przed większą pracą zakłada osobną kopię roboczą, żeby zmiany się nie mieszały.' }
        @{ Nazwa = 'using-superpowers';              Opis = 'Wprowadzenie na start rozmowy: uczy agenta szukać i używać pozostałych skilli, zanim odpowie.' }
        @{ Nazwa = 'verification-before-completion'; Opis = 'Zanim ogłosi „gotowe”, uruchamia sprawdzenie i pokazuje dowód, a nie zapewnienie.' }
        @{ Nazwa = 'writing-plans';                  Opis = 'Planowanie większej zmiany krok po kroku przed pisaniem kodu.' }
        @{ Nazwa = 'writing-skills';                 Opis = 'Pomaga pisać nowe skille i sprawdzać, czy działają.' }
      )
    }
    @{
      Id      = 'impeccable'
      Nazwa   = 'Impeccable (Paul Bakaus)'
      Adres   = 'https://github.com/pbakaus/impeccable'
      Galaz   = 'main'
      Sciezka = 'plugin/skills'
      Opis    = 'Jeden duży skill do wyglądu stron i aplikacji, z kilkudziesięcioma poleceniami.'
      Skille  = @(
        @{ Nazwa = 'impeccable'; Opis = 'Projektowanie i dopracowanie wyglądu stron i aplikacji: przegląd, krytyka, kolory, czcionki, układ, animacje (ponad 20 poleceń).' }
      )
    }
    @{
      Id      = 'taste-skill'
      Nazwa   = 'Taste Skill (Leonxlnx)'
      Adres   = 'https://github.com/Leonxlnx/taste-skill'
      Galaz   = 'main'
      Sciezka = 'skills'
      Opis    = '„Dobry gust” w projektowaniu: style stron, generowanie projektów graficznych, strony, które nie wyglądają jak szablon.'
      Skille  = @(
        @{ Nazwa = 'brandkit';                 Opis = 'Generuje obrazy księgi znaku marki: logo, kolory, makiety tożsamości wizualnej.' }
        @{ Nazwa = 'brutalist-skill';          Opis = 'Styl „surowy, techniczny” dla stron: sztywna siatka, ogromne kontrasty pisma, wygląd jak z dokumentacji technicznej.' }
        @{ Nazwa = 'gpt-tasteskill';           Opis = 'Odmiana „dobrego gustu” dla modeli GPT: strony z mocnym układem, dużą typografią i animacjami przy przewijaniu.' }
        @{ Nazwa = 'imagegen-frontend-mobile'; Opis = 'Generuje obrazy projektów ekranów aplikacji na telefon, zanim powstanie kod.' }
        @{ Nazwa = 'imagegen-frontend-web';    Opis = 'Generuje obrazy projektu strony internetowej - osobny obraz na każdą sekcję.' }
        @{ Nazwa = 'image-to-code-skill';      Opis = 'Najpierw generuje obraz projektu strony, potem pisze kod jak najwierniej do niego.' }
        @{ Nazwa = 'minimalist-skill';         Opis = 'Styl minimalistyczny jak w czasopiśmie: ciepłe, stonowane kolory, bez gradientów i ciężkich cieni.' }
        @{ Nazwa = 'output-skill';             Opis = 'Zmusza model do pisania pełnego kodu, bez skrótów w rodzaju „reszta bez zmian”.' }
        @{ Nazwa = 'redesign-skill';           Opis = 'Odświeża istniejącą stronę lub aplikację do wyglądu „premium”, nie psując działania.' }
        @{ Nazwa = 'soft-skill';               Opis = 'Uczy projektować jak droga agencja: czcionki, odstępy, cienie i animacje, po których strona wygląda drogo.' }
        @{ Nazwa = 'stitch-skill';             Opis = 'Tworzy plik z zasadami wyglądu (DESIGN.md) dla narzędzia Google Stitch.' }
        @{ Nazwa = 'taste-skill';              Opis = 'Główny skill „dobrego gustu”: strony i portfolio, które nie wyglądają jak z szablonu.' }
        @{ Nazwa = 'taste-skill-v1';           Opis = 'Pierwsza, starsza wersja taste-skill - tylko dla projektów, które na niej polegają.' }
      )
    }
    @{
      Id      = 'ponytail'
      Nazwa   = 'Ponytail (Dietrich Gebert)'
      Adres   = 'https://github.com/DietrichGebert/ponytail'
      Galaz   = 'main'
      Sciezka = 'skills'
      Opis    = 'Tryb „leniwego doświadczonego programisty”: najprostsze rozwiązanie, które działa, i przeglądy pod kątem przekombinowania.'
      Skille  = @(
        @{ Nazwa = 'ponytail';        Opis = 'Wymusza najprostsze rozwiązanie, które działa: bez zbędnego kodu, bibliotek i „na zapas”.' }
        @{ Nazwa = 'ponytail-audit';  Opis = 'Przegląd całego projektu: co usunąć albo uprościć. Sam raport, niczego nie zmienia.' }
        @{ Nazwa = 'ponytail-debt';   Opis = 'Zbiera zostawione w kodzie notatki o odłożonych skrótach w jedną listę do zrobienia.' }
        @{ Nazwa = 'ponytail-gain';   Opis = 'Pokazuje, ile kodu, pieniędzy i czasu oszczędza ponytail według pomiarów autora.' }
        @{ Nazwa = 'ponytail-help';   Opis = 'Ściągawka wszystkich trybów i poleceń ponytail.' }
        @{ Nazwa = 'ponytail-review'; Opis = 'Przegląd zmian tylko pod kątem przekombinowania: co można wyciąć i czym zastąpić.' }
      )
    }
    @{
      Id      = 'mattpocock'
      Nazwa   = 'Skille Matta Pococka'
      Adres   = 'https://github.com/mattpocock/skills'
      Galaz   = 'main'
      Sciezka = 'skills'
      Opis    = 'Droga od pomysłu do gotowego kodu: przepytywanie z planu, specyfikacja, zgłoszenia, testy, przegląd; plus pomoce do pisania.'
      Skille  = @(
        @{ Nazwa = 'ask-matt';                      Sciezka = 'skills/engineering/ask-matt';                      Opis = 'Podpowiada, który skill Matta pasuje do Twojej sytuacji.' }
        @{ Nazwa = 'codebase-design';               Sciezka = 'skills/engineering/codebase-design';               Opis = 'Wspólny słownik do projektowania modułów kodu, żeby były proste w użyciu i łatwe do testowania.' }
        @{ Nazwa = 'code-review';                   Sciezka = 'skills/engineering/code-review'; Folder = 'matt-code-review'; Opis = 'Przegląd zmian od wskazanego punktu na dwa sposoby naraz: czy trzymają się zasad projektu i czy robią to, o co prosiło zgłoszenie.' }
        @{ Nazwa = 'diagnosing-bugs';               Sciezka = 'skills/engineering/diagnosing-bugs';               Opis = 'Pętla diagnozy trudnych błędów i spowolnień: odtworzyć, zawęzić, naprawić.' }
        @{ Nazwa = 'domain-modeling';               Sciezka = 'skills/engineering/domain-modeling';               Opis = 'Porządkuje słownictwo projektu i zapisuje podjęte decyzje w dokumentach.' }
        @{ Nazwa = 'grill-with-docs';               Sciezka = 'skills/engineering/grill-with-docs';               Opis = 'Dociekliwe przepytywanie z planu, które przy okazji zapisuje dokumentację i słowniczek.' }
        @{ Nazwa = 'implement';                     Sciezka = 'skills/engineering/implement';                     Opis = 'Wykonuje pracę opisaną w specyfikacji lub zgłoszeniach: testy, sprawdzenie, przegląd, zapis zmian.' }
        @{ Nazwa = 'implement-spec';                Sciezka = 'skills/engineering/implement-spec';                Opis = 'Wdraża całą specyfikację: rozdziela zgłoszenia między pomocników pracujących naraz i składa ich pracę w jedną całość.' }
        @{ Nazwa = 'improve-codebase-architecture'; Sciezka = 'skills/engineering/improve-codebase-architecture'; Opis = 'Szuka w kodzie miejsc do uproszczenia budowy, pokazuje je w raporcie i omawia wybrane.' }
        @{ Nazwa = 'pr';                            Sciezka = 'skills/engineering/pr';                            Opis = 'Szablon opisu zmiany do scalenia: podsumowanie, dowód przed i po, ryzyko.' }
        @{ Nazwa = 'prototype';                     Sciezka = 'skills/engineering/prototype';                     Opis = 'Buduje prototyp na wyrzucenie, żeby szybko sprawdzić pomysł na logikę albo wygląd.' }
        @{ Nazwa = 'research';                      Sciezka = 'skills/engineering/research';                      Opis = 'Szuka odpowiedzi w wiarygodnych źródłach, np. dokumentacji, i zapisuje wyniki w pliku w projekcie.' }
        @{ Nazwa = 'retro';                         Sciezka = 'skills/engineering/retro';                         Opis = 'Podsumowanie po pracy: co poprawić w otoczeniu agenta, żeby następnym razem szło lepiej.' }
        @{ Nazwa = 'resolving-merge-conflicts';     Sciezka = 'skills/engineering/resolving-merge-conflicts';     Opis = 'Rozwiązuje konflikty przy scalaniu zmian w gicie.' }
        @{ Nazwa = 'setup-matt-pocock-skills';      Sciezka = 'skills/engineering/setup-matt-pocock-skills';      Opis = 'Jednorazowe przygotowanie projektu pod skille Matta: gdzie zgłoszenia, etykiety, dokumentacja.' }
        @{ Nazwa = 'tdd';                           Sciezka = 'skills/engineering/tdd';                           Opis = 'Programowanie od testów: najpierw test, potem kod, potem porządki.' }
        @{ Nazwa = 'to-spec';                       Sciezka = 'skills/engineering/to-spec';                       Opis = 'Zamienia dotychczasową rozmowę w specyfikację i zapisuje ją jako zgłoszenie.' }
        @{ Nazwa = 'to-tickets';                    Sciezka = 'skills/engineering/to-tickets';                    Opis = 'Dzieli plan lub specyfikację na małe zgłoszenia z zaznaczeniem, co od czego zależy.' }
        @{ Nazwa = 'triage';                        Sciezka = 'skills/engineering/triage';                        Opis = 'Porządkuje napływające zgłoszenia: kategoria, sprawdzenie, gotowy opis zadania dla agenta.' }
        @{ Nazwa = 'wayfinder';                     Sciezka = 'skills/engineering/wayfinder';                     Opis = 'Planowanie bardzo dużej pracy, na wiele rozmów, jako mapy decyzji rozstrzyganych po kolei.' }
        @{ Nazwa = 'wizard';                        Sciezka = 'skills/engineering/wizard';                        Opis = 'Tworzy kreator, który prowadzi człowieka krok po kroku przez czynności, których agent nie zrobi sam (np. hasła, panele usług).' }
        @{ Nazwa = 'claude-handoff';                Sciezka = 'skills/in-progress/claude-handoff';                Robocza = $true; Opis = 'Przekazuje bieżącą rozmowę nowemu agentowi w tle, który od razu przejmuje pracę.' }
        @{ Nazwa = 'loop-me';                       Sciezka = 'skills/in-progress/loop-me';                       Robocza = $true; Opis = 'Przepytuje o powtarzalne czynności, które chcesz zautomatyzować, i zapisuje z tego opisy procesów.' }
        @{ Nazwa = 'setup-ts-deep-modules';         Sciezka = 'skills/in-progress/setup-ts-deep-modules';         Robocza = $true; Opis = 'Ustawia w projekcie TypeScript pilnowanie, żeby moduły były dostępne tylko przez swoje wejścia.' }
        @{ Nazwa = 'writing-beats';                 Sciezka = 'skills/in-progress/writing-beats';                 Robocza = $true; Opis = 'Pisanie artykułu: układa zebrany materiał w kolejne kroki opowieści, wybierane razem z Tobą.' }
        @{ Nazwa = 'writing-fragments';             Sciezka = 'skills/in-progress/writing-fragments';             Robocza = $true; Opis = 'Pisanie artykułu, etap zbierania: wyciąga z rozmowy luźne fragmenty do jednego pliku.' }
        @{ Nazwa = 'writing-shape';                 Sciezka = 'skills/in-progress/writing-shape';                 Robocza = $true; Opis = 'Pisanie artykułu: kształtuje zebrany materiał w tekst akapit po akapicie.' }
        @{ Nazwa = 'git-guardrails-claude-code';    Sciezka = 'skills/misc/git-guardrails-claude-code';           Opis = 'Zakłada w Claude Code blokady groźnych poleceń gita (wypychanie, twarde cofanie, kasowanie).' }
        @{ Nazwa = 'migrate-to-shoehorn';           Sciezka = 'skills/misc/migrate-to-shoehorn';                  Opis = 'Przerabia testy w TypeScript z rzutowania „as” na bibliotekę shoehorn.' }
        @{ Nazwa = 'scaffold-exercises';            Sciezka = 'skills/misc/scaffold-exercises';                   Opis = 'Zakłada szkielet ćwiczeń do kursu: zadania, rozwiązania, objaśnienia.' }
        @{ Nazwa = 'setup-pre-commit';              Sciezka = 'skills/misc/setup-pre-commit';                     Opis = 'Ustawia sprawdzanie kodu przed każdym zapisem zmian (formatowanie, typy, testy).' }
        @{ Nazwa = 'grilling';                      Sciezka = 'skills/productivity/grilling';                     Opis = 'Bezlitośnie przepytuje z planu lub pomysłu, żeby znaleźć słabe punkty.' }
        @{ Nazwa = 'grill-me';                      Sciezka = 'skills/productivity/grill-me';                     Opis = 'Dociekliwy wywiad, który dopracowuje plan albo projekt.' }
        @{ Nazwa = 'handoff';                       Sciezka = 'skills/productivity/handoff';                      Opis = 'Streszcza rozmowę w dokument przekazania, żeby inny agent mógł przejąć pracę.' }
        @{ Nazwa = 'teach';                         Sciezka = 'skills/productivity/teach';                        Opis = 'Uczy Cię nowego tematu przez kilka rozmów: cel, lekcje, zapis postępów.' }
        @{ Nazwa = 'to-questionnaire';              Sciezka = 'skills/productivity/to-questionnaire';             Opis = 'Zamienia pytanie, na które sam nie odpowiesz, w ankietę dla osoby, która zna odpowiedź.' }
        @{ Nazwa = 'wait-what';                     Sciezka = 'skills/productivity/wait-what';                    Opis = 'Gdy odpowiedź była niezrozumiała: każe agentowi wytłumaczyć to jeszcze raz, prościej i z kontekstem.' }
        @{ Nazwa = 'writing-for-agents';            Sciezka = 'skills/productivity/writing-for-agents';           Opis = 'Zasady pisania dokumentów dla agentów: skille, AGENTS.md, CLAUDE.md.' }
      )
    }
    @{
      Id      = 'vibecode'
      Nazwa   = 'Vibecode Pro Max Kit (withkynam)'
      Adres   = 'https://github.com/withkynam/vibecode-pro-max-kit'
      Galaz   = 'main'
      Sciezka = '.claude/skills'
      Opis    = 'Zestaw do pracy „najpierw plan, potem kod” w etapach z bramkami; część skilli zakłada, że cały zestaw jest wgrany do projektu (katalog process/).'
      Skille  = @(
        @{ Nazwa = 'vc-agent-browser';          Opis = 'Sterowanie przeglądarką przez agenta (narzędzie agent-browser): klikanie, zrzuty, nagrania, testy stron.' }
        @{ Nazwa = 'vc-agent-strategy-compare'; Opis = 'Porównuje cztery sposoby podziału pracy między agentów i poleca najlepszy, z kosztem.' }
        @{ Nazwa = 'vc-audit-context';          Opis = 'Sprawdza, czy opisy projektu i skille są tam, gdzie agenci ich szukają, i czy się nie rozjechały.' }
        @{ Nazwa = 'vc-audit-plans';            Opis = 'Przegląda pliki planów: co nieaktualne, co skończone, co do archiwum.' }
        @{ Nazwa = 'vc-audit-vc';               Opis = 'Sprawdza, czy sam zestaw jest spójny: agenci, skille, README i pliki zasad.' }
        @{ Nazwa = 'vc-autopilot';              Opis = 'Tryb „autopilota”: zapisuje cel pracy w stałym formacie, żeby agent mógł prowadzić ją do końca i wznowić.' }
        @{ Nazwa = 'vc-autoresearch';           Opis = 'Pętla: szukaj braków, popraw, powtórz - aż agenci nie znajdą już nic albo cel zostanie osiągnięty.' }
        @{ Nazwa = 'vc-context-discovery';      Opis = 'Na start zadania zbiera i wczytuje opisy projektu potrzebne do tej pracy.' }
        @{ Nazwa = 'vc-debug';                  Opis = 'Szukanie błędów metodycznie: najpierw przyczyna, potem poprawka.' }
        @{ Nazwa = 'vc-docs-seeker';            Opis = 'Szuka aktualnej dokumentacji bibliotek i narzędzi (m.in. przez context7).' }
        @{ Nazwa = 'vc-feasibility-test';       Opis = 'Krótka próba, czy niesprawdzony pomysł techniczny w ogóle zadziała - z werdyktem tak / nie / nie wiadomo.' }
        @{ Nazwa = 'vc-frontend-design';        Opis = 'Dopracowany wygląd stron i aplikacji, także na wzór zrzutu ekranu albo filmu.' }
        @{ Nazwa = 'vc-generate-closeout';      Opis = 'Podsumowanie po skończonym etapie: czy gotowe do archiwum, co się rozjechało, co dalej.' }
        @{ Nazwa = 'vc-generate-context';       Opis = 'Pisze albo odświeża główny opis projektu dla agentów.' }
        @{ Nazwa = 'vc-generate-phase-program'; Opis = 'Rozpisuje dużą pracę na etapy: plan główny, cele i szkice planów każdego etapu.' }
        @{ Nazwa = 'vc-generate-plan';          Opis = 'Zamienia pomysł albo wymagania w zapisany plan wykonania.' }
        @{ Nazwa = 'vc-generate-spec';          Opis = 'Spisuje wymagania (specyfikację) do Twojej akceptacji, zanim powstanie plan.' }
        @{ Nazwa = 'vc-intent-clarify';         Opis = 'Gdy prośba jest niejasna, zadaje pytania z gotowymi odpowiedziami do wyboru.' }
        @{ Nazwa = 'vc-plan-discovery';         Opis = 'Szuka istniejących planów związanych z bieżącym zadaniem.' }
        @{ Nazwa = 'vc-predict';                Opis = 'Pięciu „ekspertów” spiera się o planowaną zmianę i wyłapuje ryzyka, zanim powstanie kod.' }
        @{ Nazwa = 'vc-problem-solving';        Opis = 'Sposoby na utknięcie: upraszczanie, odwracanie założeń, szukanie wzorców.' }
        @{ Nazwa = 'vc-publish';                Opis = 'Dla autora zestawu: wysyła poprawki zestawu do jego repozytorium.' }
        @{ Nazwa = 'vc-review-situation';       Opis = 'Tylko odczyt: podsumowuje stan repozytorium i planów do przekazania pracy.' }
        @{ Nazwa = 'vc-risk-evidence-pack';     Opis = 'Przy ryzykownej pracy zbiera komplet dowodów, zanim zmiana pójdzie dalej.' }
        @{ Nazwa = 'vc-scenario';               Opis = 'Wymyśla przypadki brzegowe i scenariusze testów, zanim powstanie kod.' }
        @{ Nazwa = 'vc-scout';                  Opis = 'Szybkie przeszukanie kodu: gdzie co leży i czego dotyczy zadanie.' }
        @{ Nazwa = 'vc-security';               Opis = 'Przegląd bezpieczeństwa kodu z oceną wagi luk i opcjonalną poprawką.' }
        @{ Nazwa = 'vc-sequential-thinking';    Opis = 'Rozwiązywanie trudnego problemu krok po kroku, z poprawianiem wcześniejszych kroków.' }
        @{ Nazwa = 'vc-setup';                  Opis = 'Jednorazowe wgranie i ustawienie całego zestawu w projekcie, z pytaniami po drodze.' }
        @{ Nazwa = 'vc-test-coverage-plan';     Opis = 'Plan testów dla zmiany: co sprawdza automat, co człowiek, czego nie da się sprawdzić.' }
        @{ Nazwa = 'vc-update';                 Opis = 'Pobiera do projektu nowszą wersję zestawu - najpierw pokazuje, co się zmieni.' }
        @{ Nazwa = 'vc-validate-findings';      Opis = 'Sprawdzenie planu przez kilku agentów naraz, z werdyktem: zielone, warunkowo, stop.' }
        @{ Nazwa = 'vc-web-testing';            Opis = 'Testy stron i aplikacji: działanie, wydajność, dostępność, różne przeglądarki.' }
      )
    }
    @{
      Id      = 'obsidian'
      Nazwa   = 'Obsidian Skills (Steph Ango, kepano)'
      Adres   = 'https://github.com/kepano/obsidian-skills'
      Galaz   = 'main'
      Sciezka = 'skills'
      Opis    = 'Skille do notatnika Obsidian i do czytania stron internetowych bez zbędnych ozdobników.'
      Skille  = @(
        @{ Nazwa = 'defuddle';          Opis = 'Czyta stronę internetową jako czysty tekst, bez menu i reklam - taniej niż zwykłe pobranie strony.' }
        @{ Nazwa = 'json-canvas';       Opis = 'Tworzy i zmienia tablice Obsidiana (.canvas): mapy myśli, schematy, połączenia.' }
        @{ Nazwa = 'knap';              Opis = 'Składa notatki z szablonu i danych (np. z tabeli CSV) narzędziem Knap.' }
        @{ Nazwa = 'obsidian-bases';    Opis = 'Tworzy w Obsidianie widoki notatek jak w bazie danych: tabele, karty, filtry.' }
        @{ Nazwa = 'obsidian-cli';      Opis = 'Obsługa notatek Obsidiana z wiersza poleceń: czytanie, tworzenie, szukanie, zadania.' }
        @{ Nazwa = 'obsidian-markdown'; Opis = 'Pisanie notatek w odmianie Markdown Obsidiana: odnośniki, osadzenia, ramki, właściwości.' }
      )
    }
  )
  # Skille, ktorych NIE ma w zadnym zrodle powyzej, a wiadomo, skad sa (P49, rozpoznanie
  # 2026-10-01: transkrypty i porownanie tresci z repozytoriami). Zakladka pokazuje je jako:
  #   Wlasne - "Twoj wlasny": powstaly u uzytkownika (dowod w Skad). Tylko te mozna
  #            spakowac do przekazania (narzedzia\skille.ps1 -Tryb spakuj).
  #   Inne   - znane zrodlo, ale poza opieka MegaRuchacza (Uwaga mowi dlaczego).
  # Kazdy inny katalog spoza bazy zakladka oznacza "zrodlo nieznane" - bez zgadywania.
  # Pola: Folder (nazwa katalogu u uzytkownika), Opis (po polsku, dla laika), Skad, Uwaga.
  Wlasne = @(
    @{ Folder = 'connecting-to-magazyn2'; Opis = 'Jak łączyć się z komputerem Magazyn2 w biurze (SSH), co na nim działa i gdzie szukać dzienników.'; Skad = 'Napisany w Twojej rozmowie 19.08.2026 (projekt projekt-g).' }
    @{ Folder = 'sqp-slowa-kluczowe';       Opis = 'Jak czytać raporty Amazon SQP i decydować, które słowa kluczowe wpisać do tytułu oferty.'; Skad = 'Napisany na Twoje zlecenie 16.09.2026 (projekt projekt-d).' }
  )
  Inne = @(
    @{ Folder = 'orchestration'; Opis = 'Koordynacja wielu agentów w aplikacji Orca: wiadomości, zadania, czekanie na wyniki.'; Skad = 'Repozytorium stablyai/orca (aplikacja Orca), wgrany 09.09.2026 narzędziem „skills” (npx skills).'; Uwaga = 'Aktualizuje go narzędzie „skills” albo Orca, nie MegaRuchacz - to dowiązanie do katalogu ~\.agents\skills, wspólnego z Codeksem.' }
    @{ Folder = 'synced';        Opis = 'Skille z Twojego konta claude.ai (np. pdf, xlsx), w podkatalogu.'; Skad = 'Kopia z konta claude.ai, którą dogrywa i odświeża sam Claude Code.'; Uwaga = 'Nie ruszać ręcznie - Claude Code nadpisuje ten katalog przy każdej synchronizacji.' }
  )
}
