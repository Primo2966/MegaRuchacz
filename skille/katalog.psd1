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
        @{ Nazwa = 'improve-codebase-architecture'; Sciezka = 'skills/engineering/improve-codebase-architecture'; Opis = 'Szuka w kodzie miejsc do uproszczenia budowy, pokazuje je w raporcie i omawia wybrane.' }
        @{ Nazwa = 'prototype';                     Sciezka = 'skills/engineering/prototype';                     Opis = 'Buduje prototyp na wyrzucenie, żeby szybko sprawdzić pomysł na logikę albo wygląd.' }
        @{ Nazwa = 'research';                      Sciezka = 'skills/engineering/research';                      Opis = 'Szuka odpowiedzi w wiarygodnych źródłach, np. dokumentacji, i zapisuje wyniki w pliku w projekcie.' }
        @{ Nazwa = 'resolving-merge-conflicts';     Sciezka = 'skills/engineering/resolving-merge-conflicts';     Opis = 'Rozwiązuje konflikty przy scalaniu zmian w gicie.' }
        @{ Nazwa = 'setup-matt-pocock-skills';      Sciezka = 'skills/engineering/setup-matt-pocock-skills';      Opis = 'Jednorazowe przygotowanie projektu pod skille Matta: gdzie zgłoszenia, etykiety, dokumentacja.' }
        @{ Nazwa = 'tdd';                           Sciezka = 'skills/engineering/tdd';                           Opis = 'Programowanie od testów: najpierw test, potem kod, potem porządki.' }
        @{ Nazwa = 'to-spec';                       Sciezka = 'skills/engineering/to-spec';                       Opis = 'Zamienia dotychczasową rozmowę w specyfikację i zapisuje ją jako zgłoszenie.' }
        @{ Nazwa = 'to-tickets';                    Sciezka = 'skills/engineering/to-tickets';                    Opis = 'Dzieli plan lub specyfikację na małe zgłoszenia z zaznaczeniem, co od czego zależy.' }
        @{ Nazwa = 'triage';                        Sciezka = 'skills/engineering/triage';                        Opis = 'Porządkuje napływające zgłoszenia: kategoria, sprawdzenie, gotowy opis zadania dla agenta.' }
        @{ Nazwa = 'wayfinder';                     Sciezka = 'skills/engineering/wayfinder';                     Opis = 'Planowanie bardzo dużej pracy, na wiele rozmów, jako mapy decyzji rozstrzyganych po kolei.' }
        @{ Nazwa = 'wizard';                        Sciezka = 'skills/engineering/wizard';                        Opis = 'Tworzy kreator, który prowadzi człowieka krok po kroku przez czynności, których agent nie zrobi sam (np. hasła, panele usług).' }
        @{ Nazwa = 'claude-handoff';                Sciezka = 'skills/in-progress/claude-handoff';                Robocza = $true; Opis = 'Przekazuje bieżącą rozmowę nowemu agentowi w tle, który od razu przejmuje pracę.' }
        @{ Nazwa = 'implement-spec';                Sciezka = 'skills/in-progress/implement-spec';                Robocza = $true; Opis = 'Wdraża całą specyfikację: rozdziela zgłoszenia między pomocników pracujących naraz i składa ich pracę w jedną całość.' }
        @{ Nazwa = 'loop-me';                       Sciezka = 'skills/in-progress/loop-me';                       Robocza = $true; Opis = 'Przepytuje o powtarzalne czynności, które chcesz zautomatyzować, i zapisuje z tego opisy procesów.' }
        @{ Nazwa = 'pr';                            Sciezka = 'skills/in-progress/pr';                            Robocza = $true; Opis = 'Szablon opisu zmiany do scalenia: podsumowanie, dowód przed i po, ryzyko.' }
        @{ Nazwa = 'retro';                         Sciezka = 'skills/in-progress/retro';                         Robocza = $true; Opis = 'Podsumowanie po pracy: co poprawić w otoczeniu agenta, żeby następnym razem szło lepiej.' }
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
      Id      = 'open-design'
      Nazwa   = 'OpenDesign (nexu-io)'
      Adres   = 'https://github.com/nexu-io/open-design'
      Galaz   = 'main'
      Sciezka = 'skills'
      Rodzaj  = 'aplikacja'
      Opis    = 'Osobna aplikacja do projektowania (program na komputer z własnym serwerem), a nie zestaw skilli.'
      Uwaga   = 'To nie są skille do zainstalowania w Claude Code ani Codeksie. W repozytorium leży aplikacja OpenDesign; jej 163 „skille” to w większości (139) krótkie odsyłacze do cudzych repozytoriów, a reszta działa tylko w jej własnym programie (serwer „od”). Żeby z niej korzystać, instaluje się samą aplikację - MegaRuchacz niczego stąd nie kopiuje.'
      Skille  = @()
    }
  )
}
