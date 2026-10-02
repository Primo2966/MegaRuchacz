# Audyt sufitow pamieci i zasad. Odpowiada na dwa pytania, ktore nie moga zostac
# bez odpowiedzi: CZY COS JEST UCINANE PO CICHU i CZY KOSZT ROSNIE NIEZAUWAZENIE.
# Poza tym rozdziela trzy rachunki, ktore latwo ze soba pomylic: ile tokenow
# dokleja sie do KAZDEJ wiadomosci (przypomnienie z hooka UserPromptSubmit),
# ile wchodzi RAZ, przy starcie sesji (bloki zasad, w tym blok kierownika, +
# warstwa stala i biezaca, a z -Projekt takze CLAUDE.md projektu),
# a ile kosztuje RAZ NA DOBE cykl wiedzy - czyli jedyne miejsce w tym narzedziu,
# w ktorym naprawde wola sie model i wydaje tokeny uzytkownika. Dwa pierwsze to
# TEKST doklejany do rozmowy, trzeci to PRAWDZIWE WYWOLANIE - i wlasnie dlatego
# nie sumuja sie w jedna liczbe.
# Dwa pierwsze rachunki liczymy OSOBNO DLA KAZDEGO NARZEDZIA (Claude Code, Codex):
# kazde z tego, co naprawde trafia do JEGO modelu, i kazde z wlasnym
# sprawdzeniem progow - Claude Code nie czyta ~\.codex\AGENTS.md, Codex nie czyta
# ~\.claude\CLAUDE.md, wiec wspolna suma bylaby liczba, ktorej nikt nie placi.
# Sam ten skrypt modelu nie wola: czysta arytmetyka na plikach.
#
# CALY RACHUNEK NA ZADANIE - jedna komenda do wklejenia w terminal:
#   powershell -ExecutionPolicy Bypass -File C:\dev\claude-worker\narzedzia\koszt-pamieci.ps1
# Wypisuje, ktora pamiec ile kosztuje przy kazdej wiadomosci i przy starcie
# sesji, pozycja po pozycji. Ta sama komenda jest na koncu kazdego raportu.
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File narzedzia\koszt-pamieci.ps1
#     -KatalogDomowy <kat>   podmiana bazy sciezek (domyslnie katalog domowy; testy)
#     -Zrodlo <kat>          katalog narzedzia (domyslnie katalog nad tym skryptem)
#     -Projekt <kat>         projekt z wdrozonym Codeksem: mierzymy wtedy ladunki
#                            hookow, ktore tam naprawde leza, a nie same szablony;
#                            pod Claude Code do startu sesji dochodzi wtedy
#                            CLAUDE.md tego projektu
#     -TylkoSufity           SAME sufity: kazda para (ladunek, limit) w jednej linii,
#                            kod 1 gdy cokolwiek wystaje - do odpalenia po kazdej
#                            zmianie zasad, bez czekania na reszte raportu
#     -Zwiezle               DOKLADNIE JEDNA linia do pokazania przy starcie sesji
#     -Dane                  to samo co -Zwiezle (klucz "linia"), a do tego alarmy z waga,
#                            ocena kosztu nauki (zwykly dzien czy nadrabianie) i dni
#                            z historii - linie "klucz: wartosc" dla nadzorcy w zasobniku
#                            (zasobnik\stan-nadzorcy.ps1). Liczone tutaj i tylko tutaj
#     -Rozbicie              kilkanascie linii: te same trzy rachunki rozbite na pozycje,
#                            z paskiem, udzialem i sciezka przy kazdej. Straznik pokazuje
#                            to RAZ dziennie, przy pierwszej sesji
#     -Zwykly                bez kolorow (do zapisu wydruku w pliku)
#     -Narzedzie <nazwa>     Claude albo Codex: czyj rachunek jest DOMYSLNY - ten idzie
#                            w linii -Zwiezle/-Dane, jego progi podnosza kod wyjscia
#                            i jego kubelki stoja w rozbiciu pierwsze. Bez parametru:
#                            Claude Code, gdy jest na maszynie, inaczej Codex.
#                            Kazde narzedzie ma WLASNY rachunek (patrz "rachunki
#                            narzedzi" nizej) - liczba bez nazwy narzedzia klamie
#     -Warstwy               JSON z lista WSZYSTKICH warstw pamieci (zakladka "Warstwy
#                            pamieci" w oknie nadzorcy): kiedy sie wczytuje, stala czy
#                            tymczasowa, kto pisze, ile znakow, czy plik jest. Zbudowany
#                            na tych samych pozycjach, co rachunek, plus warstwy na
#                            zadanie i nieuzywane - lista warstw zyje TYLKO tutaj.
#                            Wyjscie w samym ASCII (polskie znaki jako \uXXXX), bo
#                            przekierowane wyjscie PowerShella 5.1 psuje ogonki
#     -Start                 JSON z POMIAREM otwarcia sesji z transkryptow Claude Code
#                            (<dom>.claudeprojects): mediana kontekstu przy pierwszej
#                            odpowiedzi modelu, osobno sesje i workerzy, plus czesc
#                            MegaRuchacza z rachunku - dla okna nadzorcy. Samo ASCII
#     -ZalozZadanie          codzienny raport o 08:15 do <dom>\.claude\wiedza\koszt-ostatni.txt
#     -UsunZadanie           kasuje to zadanie
#
# Kod wyjscia: 0 gdy nic nie jest ucinane i zaden prog alarmowy nie jest
# przekroczony, 1 gdy cokolwiek z tego zachodzi - zeby dalo sie to podpiac jako
# sprawdzenie. Zolta INFORMACJA (np. nauka nadrabiala zaleglosc) kodu NIE podnosi:
# mowi, co sie stalo i dlaczego, ale niczego nie trzeba naprawiac.
#
# WARTOSCI SUFITOW CZYTAMY Z PLIKOW, KTORE JE USTALAJA (straznik, hooks.json,
# facts.py, index.py). Wpisane tu na sztywno zaczelyby klamac przy pierwszej
# zmianie tamtych plikow - a audyt, ktory klamie, jest gorszy niz jego brak.
#
# Skrypt TYLKO CZYTA CLAUDE.md - nigdy do niego nie pisze. Brak pliku, brak sekcji,
# brak katalogu wiedzy czy bazy Lore to nie awaria, tylko mniej danych w raporcie.
#
# BUDOWA. Ten plik trzyma parametry, progi (nizej, razem z uzasadnieniem) i przebieg:
# ktory etap idzie po ktorym i jakim kodem wyjscia konczy sie kazdy tryb. Reszta
# lezy w narzedzia\koszt\ - jeden plik na temat, zeby do zmiany wystarczylo
# przeczytac jeden kawalek (kazdy ma naglowek: co w nim jest i skad jest wolany):
#   podstawy.ps1        raport (Linia), liczby i teksty, czytanie plikow
#   warstwy.ps1         pomiar warstw CLAUDE.md (Zmierz-Warstwy), pozycje rachunku
#   sufity.ps1          sufity (Sufit, Limit-Hooka, Ladunek-Hooka) i tryb -TylkoSufity
#   nauka.ps1           koszt cyklu wiedzy, historia i ocena kosztu nauki
#   baza-lore.ps1       liczby z bazy Lore (winsqlite3.dll, bez zaleznosci)
#   pomiar-dzienny.ps1  zadanie LoreKoszt w Harmonogramie i poprzedni POMIAR
#   pomiar.ps1          etap: co leci do modelu - warstwy, hooki, ladunki, sufity
#   kubelki.ps1         etap: rachunki Claude Code i Codeksa, narzedzie domyslne
#   otwarcie.ps1        pomiar otwarcia sesji z transkryptow i tryb -Start
#   tryb-warstwy.ps1    tryb -Warstwy (lista warstw dla okna nadzorcy)
#   alarmy.ps1          etap: ocena nauki, rachunek kazdego narzedzia, alarmy, linia
#   tryb-dane.ps1       tryb -Dane (klucz: wartosc dla nadzorcy)
#   tryb-rozbicie.ps1   tryb -Rozbicie (kubelki z paskami)
#   raport-pelny.ps1    pelny raport (tez dzienny raport zadania LoreKoszt)
# Etapy i tryby to funkcje wolane KROPKA (". Etap-Pomiar"), wiec biegna w zasiegu
# tego skryptu: zmienne, ktore ustawiaja, widzi dalszy przebieg - tak samo, jak
# gdyby ich tresc stala tutaj. Dwie rzeczy zostaja w tym pliku i nie wolno ich
# przenosic do modulow: exit trybow (exit w samym pliku wczytanym kropka konczy
# tylko tamten plik, a skrypt szedlby dalej) i $PSScriptRoot / $PSCommandPath
# (w module wskazuja modul, nie ten skrypt).

param(
  [string]$KatalogDomowy = $HOME,
  [string]$Zrodlo = "",
  [string]$Projekt = "",
  [switch]$TylkoSufity,
  [switch]$Zwiezle,
  [switch]$Dane,
  [switch]$Rozbicie,
  [switch]$Zwykly,
  [ValidateSet("", "Claude", "Codex")]
  [string]$Narzedzie = "",
  [switch]$Warstwy,
  [switch]$Start,
  [switch]$ZalozZadanie,
  [switch]$UsunZadanie
)

# Stary wspolny blok zasad pamieci (do P59a). Od P59a zasady pamieci to dwa bloki nazwane
# <!-- MegaRuchacz:lore:start --> i <!-- MegaRuchacz:wiedza:start --> - Zmierz-Warstwy liczy je
# razem z innymi blokami nazwanymi (np. kierownik), a ten znacznik zostaje dla pliku jeszcze
# niezmigrowanego (stary blok zamienia na nowe straznik, Pilnuj-Zasad).
$ZnacznikStart  = "<!-- MegaRuchacz:start -->"
$ZnacznikKoniec = "<!-- MegaRuchacz:koniec -->"

$NazwaZadania   = "LoreKoszt"
$GodzinaZadania = "08:15"

# ~3 znaki na token to przyblizenie dla polszczyzny - patrz adnotacja w raporcie
$ZnakiNaToken   = 3
$DniWaznosci    = 14
# pomiar kosztu cyklu starszy niz tyle dni znaczy, ze cykl przestal chodzic -
# ta sama liczba, co w straznik-zasad.ps1 przy meldunku o cyklu
$DniCyklStary   = 2
$ProgStalej     = 8000
$ProgBiezacych  = 15
$ProgPoczekalni = 10
# powyzej tylu procent sufitu wiersz jest zolty - zapas konczy sie wczesniej,
# niz czlowiek zdazy zauwazyc
$ProgCiasno     = 80
# wzrost kosztu od poprzedniego pomiaru, ktory ma byc widoczny. Czerwonym
# alarmem jest TYLKO wtedy, gdy po skoku czesc MegaRuchacza w otwarciu sesji
# przekracza $AlarmCzesciOtwarcia; ponizej to wpis informacyjny - skok z 9 000
# na 11 000 tokenow nikomu nie szkodzi, a czerwien za niego uczy ignorowac alarmy
$ProgWzrostu    = 20

# --- progi alarmowe ----------------------------------------------------------
# TO SA NASZE LICZBY DO ZMIANY, NIE PRAWA NATURY. Zadna z nich nie pochodzi
# z dokumentacji Claude Code ani Codeksa - dobralismy je tak, zeby alarm odzywal
# sie rzadko i zawsze wtedy, gdy jest co zrobic. Kazda zmienia sie tutaj, jedna
# linijka, i nic poza tym plikiem o nich nie wie.
#
# $AlarmCzesciOtwarcia - LICZBA TOKENOW, ktora MegaRuchacz (start sesji +
#   przypomnienie przy pierwszej wiadomosci) dokleja do KAZDEGO otwarcia sesji
#   swojego narzedzia - ta sama czesc, ktora liczy ten rachunek (znaki / 3).
#   30.09.2026: Claude Code ~9 100 (start 8 968 + przypomnienie 115), Codex ~5 100.
#   Prog 15 000 = dzisiejsza czesc Claude Code plus ~65%: dopisana wiedza i drobne
#   zmiany zasad sie zmieszcza, rozrost, przy ktorym skracanie ma sens - juz nie.
#   DLACZEGO TOKENY, A NIE PROCENT (decyzja uzytkownika 30.09.2026). Do tego dnia
#   progiem byl procent calego otwarcia sesji (10%). Ale procent zalezy od wagi
#   dodatkow - opisow narzedzi z serwerow MCP, ktore dokleja Claude Code - a te
#   ustawia administrator proxy: po wlaczeniu odkladania narzedzi otwarcie spadnie
#   z ~191 000 do ~75 000 tokenow i te same ~9 100 tokenow MegaRuchacza dalyby
#   ~12%, czyli czerwony alarm, choc MegaRuchacz nie urosl ani o znak. Stala liczba
#   tokenow mierzy tylko to, na co MegaRuchacz ma wplyw. Procent calego otwarcia
#   (calosc z transkryptow, Pomiar-Otwarcia) zostaje do POKAZYWANIA - linia,
#   rozbicie, raport i okno nadzorcy - ale o alarmie nie decyduje.
#   Gdy startu sesji nie da sie zmierzyc (nie ma CLAUDE.md, plik sie nie czyta),
#   czesc wychodzi zanizona i alarm nie swieci - linia mowi wtedy wprost "startu
#   sesji nie umiem zmierzyc", a okno nadzorcy pokazuje "nie wiadomo".
# $AlarmUdzialu - jedna pozycja zjadajaca wiecej niz tyle procent swojego
#   rachunku. Nie chodzi o sam rozmiar, tylko o to, ze skracanie czegokolwiek
#   innego nic nie da. Dzis najdrozsza pozycja (warstwa stala) ma 64%, wiec prog
#   stoi nad tym, a nie pod: alarm, ktory swieci sie od pierwszego dnia i tak
#   jak swiecil, przestaje byc alarmem.
# $MinPozycjiDoUdzialu - ponizej tylu pozycji w rachunku udzial nic nie mowi
#   (przy dwoch pozycjach jedna prawie zawsze ma ponad polowe), wiec alarm
#   o udziale w ogole sie nie odzywa.
# $AlarmCyklu - koszt nauki z rozmow (cykl wiedzy) za ZWYKLY dzien, czyli taki,
#   w ktorym nauka czytala material z jednego dnia (patrz $DniMaterialuZwyklego).
#   Skad 350 000 - bo prog wpisany bez uzasadnienia dwa razy juz po cichu psul
#   dzialanie, a 24.09.2026 swiecil na czerwono bez powodu:
#     - pierwsza wersja (120 000) zakladala ~24 000 tokenow na jedno wywolanie
#       modelu: MAX_INPUT_CHARS = 60 000 znakow materialu (lore\lore\facts.py)
#       plus polecenie i odpowiedz. POMIAR z 24.09.2026 (.koszt-cyklu.txt,
#       tokeny_zrodlo: pomiar) dal 312 609 tokenow na 5 wywolan, czyli ~62 500
#       na wywolanie - ponad dwa i pol raza wiecej. Samego materialu bylo tam
#       ~84 000 tokenow (252 578 wyslanych znakow / 3); reszte doklada kazde
#       wywolanie narzedzia AI niezaleznie od tego, ile jest do czytania,
#     - na JEDNO podejscie cykl bierze najwyzej $MaxNadrabiania = 5 wywolan
#       (narzedzia\cykl-dzienny.ps1), czyli 5 * 62 500 = ~312 500 tokenow,
#     - 350 000 to jedno pelne podejscie plus ~12% zapasu na wahania narzutu.
#   Przy starym progu alarm odzywal sie na zupelnie zwyczajnym, jednym podejsciu -
#   a falszywy alarm uczy ignorowania. Powyzej progu na ZWYKLYM dniu znaczy, ze
#   cykl wracal po kolejne raty ze swiezymi rozmowami ($MaxProb = 5 podejsc na
#   dobe) - i to jest ten moment, w ktorym uzytkownik ma sie o tym dowiedziec.
#   Dzien NADRABIANIA (material sprzed wielu dni) przekracza ten prog z natury
#   rzeczy i dostaje zolta informacje, nie czerwony alarm.
#   Gdyby zmienil sie $MaxNadrabiania albo narzut wywolania, prog trzeba przeliczyc.
# $DniMaterialuZwyklego - zwykly dzien nauki czyta rozmowy z poprzedniego dnia,
#   bo cykl chodzi raz na dobe. Gdy najstarsza przeczytana wiadomosc jest starsza
#   o WIECEJ niz tyle dni od dnia przebiegu, przebieg NADRABIAL zaleglosc.
#   1, bo taki jest rytm cyklu - nie liczba z powietrza. Jedna spozniona rozmowa
#   sprzed kilku dni tez robi z dnia nadrabianie: to blad w strone zoltej
#   informacji, a nie czerwonego alarmu - swiadomie, bo falszywy alarm jest gorszy.
# $ProgInformacjiNauki - od ilu tokenow dzien NADRABIANIA dostaje zolta informacje
#   "dlaczego tyle". 125 000 = dwa wywolania po zmierzone ~62 500: ponizej dzien
#   nadrabiania kosztuje tyle, co spokojny zwykly dzien, i nie ma czego tlumaczyc.
#   To nie jest alarm i nie podnosi kodu wyjscia.
# $DniWzrostuCyklu, $ProcWzrostuCyklu - drugi powod do czerwieni: koszt zwyklego
#   dnia rosnie dzien po dniu. Jeden czy dwa drozsze dni to zwykle gestsza praca;
#   trzy wzrosty z rzedu, kazdy o co najmniej 20%, to juz ~1,7 raza w cztery dni -
#   trend, a nie przypadek. Dni nadrabiania sie tu nie licza, bo sa jednorazowe.
# $DniStatystyki - ile ostatnich dni pokazuje statystyka w oknie nadzorcy: tyle,
#   ile dluzsze okno podsumowania w lore\lore\facts.py (WINDOWS = (7, 30)).
$AlarmCzesciOtwarcia  = 15000
$AlarmUdzialu         = 70
$MinPozycjiDoUdzialu  = 3
$AlarmCyklu           = 350000
$DniMaterialuZwyklego = 1
$ProgInformacjiNauki  = 125000
$DniWzrostuCyklu      = 3
$ProcWzrostuCyklu     = 20
$DniStatystyki        = 30

# Przedrostek ladunku hooka startowego Codeksa - MUSI brzmiec tak samo jak
# w straznik-zasad.ps1 (Zbuduj-Sesje-Codex) i w wdroz.ps1, bo inaczej liczymy
# dlugosc czegos, czego nikt nie wysyla.
$PrzedrostekZasad = "Zasady pracy w tym projekcie (tryb MegaRuchacz). Stosuj je przez cala sesje:`n`n"

# --- moduly -------------------------------------------------------------------
# Wszystkie pliki z narzedzia\koszt\ wczytujemy tu, zanim cokolwiek policzymy -
# to same definicje funkcji. Brak modulu, blad skladni albo plik bez znacznika na
# koncu (pusty albo uciety) to nie "mniej danych", tylko niepelny rachunek:
# odmawiamy wtedy liczenia (kod 1, powod na strumien bledow), zamiast oddac linie,
# ktora wyglada na prawdziwa.
$katModulowKosztu = $PSScriptRoot
if ((-not $katModulowKosztu) -and $PSCommandPath) { $katModulowKosztu = Split-Path -Parent $PSCommandPath }
if ((-not $katModulowKosztu) -and $Zrodlo) { $katModulowKosztu = Join-Path $Zrodlo "narzedzia" }
if (-not $katModulowKosztu) {
  Write-Error "koszt-pamieci.ps1: nie wiem, gdzie leza moduly narzedzia\koszt\ (skrypt nie jest uruchomiony z pliku) - podaj -Zrodlo"
  exit 1
}
$katModulowKosztu = Join-Path $katModulowKosztu "koszt"
$script:ModulyKosztu = @{}
foreach ($modulKosztu in @("podstawy", "warstwy", "sufity", "nauka", "baza-lore", "pomiar-dzienny", "pomiar",
                           "kubelki", "otwarcie", "tryb-warstwy", "alarmy", "tryb-dane", "tryb-rozbicie", "raport-pelny")) {
  $plikModuluKosztu = Join-Path $katModulowKosztu "$modulKosztu.ps1"
  try { . $plikModuluKosztu }
  catch {
    Write-Error "koszt-pamieci.ps1: nie da sie wczytac modulu $plikModuluKosztu ($($_.Exception.Message)) - bez niego rachunek bylby niepelny, wiec nic nie licze"
    exit 1
  }
  if (-not $script:ModulyKosztu[$modulKosztu]) {
    Write-Error "koszt-pamieci.ps1: modul $plikModuluKosztu nie wczytal sie do konca (nie ma znacznika na jego koncu - plik pusty albo uciety) - nic nie licze"
    exit 1
  }
}
# Rejestr instalacji (narzedzia\instalacja\stan.ps1, od P59a): przy module kierownik wylaczonym
# narzedzia\przypomnienie.js nie dokleja ladunku z pliku, wiec rachunek go nie liczy (Etap-Pomiar).
# Starsza kopia bez umowy, brak rejestru albo rejestr nieczytelny = jak dotad.
$plikRejestruInstalacji = Join-Path (Split-Path -Parent $katModulowKosztu) "instalacja\stan.ps1"
if (Test-Path -LiteralPath $plikRejestruInstalacji) { . $plikRejestruInstalacji }

# --- przebieg ----------------------------------------------------------------

if (-not (Test-Path -LiteralPath $KatalogDomowy)) {
  Write-Error "Nie ma takiego katalogu domowego: $KatalogDomowy"
  exit 1
}
$KatalogDomowy = (Resolve-Path -LiteralPath $KatalogDomowy).Path

if (-not $Zrodlo) {
  $katSkryptu = $PSScriptRoot
  if ((-not $katSkryptu) -and $PSCommandPath) { $katSkryptu = Split-Path -Parent $PSCommandPath }
  if ($katSkryptu) { $Zrodlo = Split-Path -Parent $katSkryptu }
}

$katKlaudii   = Join-Path $KatalogDomowy ".claude"
$plikClaude   = Join-Path $katKlaudii "CLAUDE.md"
$katWiedzy    = Join-Path $katKlaudii "wiedza"
$plikKandydat = Join-Path $katWiedzy "kandydaci.md"
$plikOstatni  = Join-Path $katWiedzy "koszt-ostatni.txt"
$plikZnacznik = Join-Path $katWiedzy ".ostatnie-wyciaganie"
# koszt cyklu wiedzy - pisze go sam cykl po wylowieniu faktow; tego pliku moze
# nie byc i to NIE jest awaria, tylko "cykl jeszcze nie liczyl kosztu"
$plikCyklKoszt   = Join-Path $katWiedzy ".koszt-cyklu.txt"
$plikCyklOstatni = Join-Path $katWiedzy "cykl-ostatni.txt"
# historia przebiegow nauki i jej podsumowania 7/30 dni - pisze je samo
# wylawianie (lore\lore\facts.py, record_pass). Brak = historia dopiero sie zbiera.
$plikHistoria    = Join-Path $katWiedzy ".koszt-historia.tsv"
$plikPodsum      = Join-Path $katWiedzy ".koszt-podsumowanie.txt"
$bazaLore     = Join-Path $katKlaudii "lore.db"
$plikAgents   = Join-Path $KatalogDomowy ".codex\AGENTS.md"
# Modul kierownik odznaczony w instalatorze - TYLKO przy rejestrze czytelnym (nieczytelny = wszystko
# wlaczone, tak jak go traktuje przypomnienie.js).
$script:KierownikWylaczony = $false
# Tak samo modul wiedza (P64): bez niego rachunek nie mowi o nauce "jeszcze nie liczone, cykl nie mial
# okazji sie odpalic" - nauki po prostu nie ma z wyboru uzytkownika.
$script:WiedzaWylaczona = $false
if (Get-Command Czytaj-Instalacje -ErrorAction SilentlyContinue) {
  $rejestrInstalacji = Czytaj-Instalacje $KatalogDomowy
  $kierownikWRejestrze = $rejestrInstalacji.moduly.kierownik   # brak klucza = wlaczony (umowa stan.ps1)
  $script:KierownikWylaczony = ((-not $rejestrInstalacji.blad) -and ($null -ne $kierownikWRejestrze) -and -not [bool]$kierownikWRejestrze)
  $wiedzaWRejestrze = $rejestrInstalacji.moduly.wiedza
  $script:WiedzaWylaczona = ((-not $rejestrInstalacji.blad) -and ($null -ne $wiedzaWRejestrze) -and -not [bool]$wiedzaWRejestrze)
}

if ($UsunZadanie)  { Usun-Zadanie }
if ($ZalozZadanie) { Zaloz-Zadanie $PSCommandPath $KatalogDomowy $plikOstatni }

# zrodla sufitow - kazdy limit czytamy z pliku, ktory go naprawde ustala
$plikStraznika = Join-Path $Zrodlo "narzedzia\straznik-zasad.ps1"
# Sufit rzadzi ten, ktory NAPRAWDE lezy w projekcie - szablon w repo mowi tylko,
# co instalator by tam wpisal. Gdy projekt jest podany i ma wlasny .codex\hooks.json,
# limity czytamy stamtad; inaczej zostaje szablon.
$plikHookow    = Join-Path $Zrodlo "szablony-codex\hooks.json"
$skadHookow    = "szablony-codex\hooks.json"
if ($Projekt) {
  $hookiProjektu = Join-Path $Projekt ".codex\hooks.json"
  if (Test-Path -LiteralPath $hookiProjektu) {
    $plikHookow = $hookiProjektu
    $skadHookow = $hookiProjektu
  }
}
$plikZasadWzor = Join-Path $Zrodlo "szablony-codex\zasady-kierownika.md"
$plikPrzypWzor = Join-Path $Zrodlo "szablony-codex\przypomnienie.json"
$plikFaktow    = Join-Path $Zrodlo "lore\lore\facts.py"
$plikIndeksu   = Join-Path $Zrodlo "lore\lore\index.py"
$plikSzukania  = Join-Path $Zrodlo "lore\lore\search.py"
$plikKopania   = Join-Path $Zrodlo "lore\lore\mining.py"

# --- etapy i tryby ------------------------------------------------------------
# Kazdy etap i tryb to funkcja z narzedzia\koszt\ wolana KROPKA: biegnie w zasiegu
# tego skryptu, jak gdyby jej tresc stala tutaj. Kolejnosc jest kolejnoscia
# liczenia - pozniejszy etap korzysta ze zmiennych ustawionych przez wczesniejszy.
# Tryby wypisuja swoje, a exit z kodem stoi TUTAJ.

. Etap-Pomiar     # koszt\pomiar.ps1  - warstwy, hooki, ladunki obu narzedzi, sufity
. Etap-Kubelki    # koszt\kubelki.ps1 - rachunki Claude Code i Codeksa

if ($Start) {     # koszt\otwarcie.ps1 - pomiar otwarcia sesji jako JSON
  . Tryb-Start
  exit 0
}

if ($Warstwy) {   # koszt\tryb-warstwy.ps1 - lista warstw jako JSON
  . Tryb-Warstwy
  exit 0
}

. Etap-Ocena      # koszt\alarmy.ps1 - nauka, rachunek kazdego narzedzia, alarmy, jedna linia

if ($Zwiezle) {
  Write-Output $liniaZwiezla
  exit $kodWyjscia
}

if ($Dane) {      # koszt\tryb-dane.ps1 - klucz: wartosc dla nadzorcy
  . Tryb-Dane
  exit $kodDanych
}

if ($Rozbicie) {  # koszt\tryb-rozbicie.ps1 - kubelki z paskami
  . Tryb-Rozbicie
  exit 0
}

if ($TylkoSufity) {   # koszt\sufity.ps1 - kod 1, gdy cokolwiek jest ucinane
  . Tryb-Sufity
  if ($cosUcinane) { exit 1 }
  exit 0
}

# Pelny raport (koszt\raport-pelny.ps1). Sciezke skryptu do komendy na koncu
# raportu liczymy tutaj - w module $PSCommandPath wskazywalby modul.
$sciezkaSkryptu = $PSCommandPath
if (-not $sciezkaSkryptu) { $sciezkaSkryptu = Join-Path $Zrodlo "narzedzia\koszt-pamieci.ps1" }
. Raport-Pelny

if ($cosUcinane -or $alarmy.Count -gt 0) { exit 1 }
exit 0
