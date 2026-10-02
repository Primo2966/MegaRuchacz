# Odczyt stanu dla nadzorcy w zasobniku - CALA arytmetyka i wszystkie wywolania
# skryptow siedza tutaj, a zasobnik\nadzorca.ps1 robi z tego okno i powiadomienia.
# Rozdzial jest z premedytacja: okna nie da sie uruchomic bez pulpitu, a ten plik
# przechodzi w calosci bez GUI (nadzorca.ps1 -Raz), wiec da sie go naprawde sprawdzic.
#
# Zasada nadrzedna tego pliku pochodzi z sekcji "Cisza jest zakazana" w CLAUDE.md:
# kazda funkcja, ktorej cos sie nie udalo, ZWRACA POWOD, a nie pustke. Nigdzie nie
# ma pustego catch - potkniecie idzie do dziennika nadzorcy i do pliku stanu,
# skad melduje sie przy najblizszej okazji.
#
# Ten plik NICZEGO nie liczy drugi raz. Rachunek liczy narzedzia\koszt-pamieci.ps1,
# aktualizacje robi narzedzia\straznik-zasad.ps1 -Tlo, cykl chodzi z
# narzedzia\cykl-dzienny.ps1 - tutaj sa tylko wywolania i odczyt tego, co zapisza.
#
# Dot-sourcowany, wiec sam z siebie nic nie robi. Przed uzyciem: Ustaw-Nadzorce.
#
# BUDOWA (P28a, 30.09.2026). Ten plik trzyma ustawienia (sciezki $script:Nadz...,
# stale z uzasadnieniem, zasade zwracania list) i wczytuje reszte z
# zasobnik\nadzorca\ - jeden plik na temat, kazdy z naglowkiem (co w nim jest
# i skad jest wolany):
#   stan-podstawy.ps1   pliki "klucz: wartosc", dziennik i wywrotki, Wolaj-Gita,
#                       Wolaj-Skrypt, Odpal-W-Tle
#   stan-wersja.ps1     numer wersji, porownanie z serwerem, aktualizacja
#   stan-cykl.ps1       cykl wiedzy: stan, opis, czy ruszac, start
#   stan-rachunek.ps1   rachunek za pamiec i otwarcie okna rozmowy (koszt-pamieci.ps1)
#   stan-zuzycie.ps1    dzienne zuzycie tokenow (licznik C#, liczenie w osobnym procesie)
#   stan-koszt.ps1      prawdziwy koszt dnia (rozmowy i workerzy), werdykt, alarmy rachunku
#   stan-alarmy.ps1     alarmy: jeden na sprawe na dobe, wywrotki straznika
#   stan-po-ludzku.ps1  jezyk czlowieka: odmiana, daty, zdania, szacunek kosztu cyklu
#   stan-skille.ps1     polecane skille: codzienne sprawdzenie, operacje, stan
#   stan-kopia.ps1      kopia zapasowa na Dysk Google: stan, linia na Przeglad, alarm
#   stan-instalacja.ps1 ktore moduly sa zainstalowane (rejestr instalacji), alarm przy
#                       nieczytelnym rejestrze
#   stan-zbieranie.ps1  Zbierz-Wszystko - jeden obiekt danych dla okna i dozoru
# "Ten plik" w komentarzach modulow znaczy stan-nadzorcy.ps1 razem z modulami -
# tak wczytuje go okno, osobne procesy krokow (nadzorca\licz-krok.ps1) i osobny
# proces liczenia zuzycia ($script:NadzTenPlik). Brak modulu, blad skladni albo
# plik bez znacznika na koncu (pusty albo uciety) = wyjatek z nazwa modulu:
# nadzorca.ps1 odmawia wtedy startu, a krok w tle konczy sie bledem z tym
# powodem. Nowy modul: nazwa na liscie przy wczytywaniu i ostatnia linia
# $script:NadzModuly["nazwa"] = $true. Moduly zapisane jak ten plik: UTF-8 ZE
# ZNACZNIKIEM BOM i konce linii CRLF.

# ------------------------------------------------------------------ ustawienia

# Sciezki i stan ustawiane przez Ustaw-Nadzorce - zaden odczyt nie zaklada
# katalogu domowego z gory, bo proba negatywna podstawia swoj.
#
# PRZEDROSTEK "Nadz" NIE JEST OZDOBA. Ten plik jest dot-sourcowany, wiec jego
# zakres skryptowy to TEN SAM zakres, w ktorym siedza parametry nadzorca.ps1.
# Nazwane wprost ($script:Zrodlo, $script:Proba) kasowaly parametry wolajacego
# w chwili wczytania - i nadzorca dostawal pusta sciezke zrodla oraz tryb probny
# przestawiony na $false, czyli startowal cykl mimo "-Proba". Zlapane 24.09.2026.
$script:NadzZrodlo        = $null
$script:NadzDom           = $null
$script:NadzPlikStanu     = $null   # ~\.claude\.megaruchacz-zasobnik.txt - slad "bylem tu", wywrotki, znaczniki alarmow
$script:NadzPlikDziennika = $null   # ~\.claude\.megaruchacz-zasobnik.log - co nadzorca robil
$script:NadzWiedza        = $null
$script:NadzProba         = $false  # tryb probny: nic nie zapisuje i nie startuje cyklu
$script:NadzWywrotki      = @()

# ZASADA ZWRACANIA LIST - jedna w calym pliku, bo mieszanie dwoch konwencji
# wyprodukowalo tu 24.09.2026 FALSZYWY ALARM ("straznik sie wywrocil" przy
# pustej liscie wywrotek), a falszywy alarm jest gorszy niz brak alarmu.
# Zmierzone w PowerShellu 5.1:
#   return $l  (pusta)          -> wolajacy dostaje $null
#   return ,$l (pusta)          -> wolajacy dostaje tablice 0-elementowa   <- chcemy tego
#   @(f), gdy f konczy sie ",$l" -> tablica 1-elementowa, w srodku tamta tablica  <- pulapka
# Dlatego: KAZDA funkcja oddajaca liste konczy sie "return ,$cos",
# a wolajacy NIE owija jej w @(). Owijac wolno zmienne, nie wywolania.
$LINII_DZIENNIKA   = 300
$WYWROTEK_NAJWYZEJ = 5
# Czas na wywolanie gita. Krotki, bo okno czeka - lepiej powiedziec "nie zdazylem"
# niz zawiesic ikone na minute.
$CZAS_GIT          = 10
$CZAS_GIT_FETCH    = 25
# Jak czesto nadzorca zaglada do sieci po nowsza wersje narzedzia. Pol godziny,
# bo to jedyne siegniecie sieciowe w calym programie, a numer wersji nie zmienia
# sie czesciej niz raz na kilka godzin.
$MINUT_MIEDZY_POBRANIAMI = 30
# Powyzej tylu godzin od ostatniego przebiegu cykl uznajemy za stojacy. Doba,
# bo taki jest jego rytm: ma ruszac raz dziennie. Liczba pochodzi wprost
# ze zlecenia uzytkownika, nie z powietrza.
$GODZIN_CYKL_STOI  = 24
# Sciezka TEGO pliku - liczenie zuzycia tokenow (Policz-Zuzycie) chodzi w osobnym
# procesie, ktory wczytuje ten sam plik (sprawdzone 28.09.2026: przy
# dot-sourcingu $PSCommandPath na gorze pliku to ten plik, nie wolajacy).
$script:NadzTenPlik       = $PSCommandPath

# --- moduly ------------------------------------------------------------------
# Wczytujemy je od razu - to same definicje i stale, nic sie nie wywoluje.
# Zmienne z przedrostkiem "nadz" z tego samego powodu, co $script:Nadz...: ten
# plik laduje w zakresie wolajacego (nadzorca.ps1, watek w tle), wiec nazwa bez
# przedrostka mogla nadpisac jego zmienna.
if (-not $PSScriptRoot) { throw "stan-nadzorcy.ps1: nie wiem, gdzie leza moduly zasobnik\nadzorca\stan-*.ps1 (plik nie jest wczytany z dysku)" }
$nadzKatalogModulow = Join-Path $PSScriptRoot "nadzorca"
$script:NadzModuly = @{}
foreach ($nadzModul in @("podstawy", "wersja", "cykl", "rachunek", "zuzycie", "koszt", "alarmy", "po-ludzku", "skille", "kopia", "instalacja", "zbieranie")) {
  $nadzPlikModulu = Join-Path $nadzKatalogModulow "stan-$nadzModul.ps1"
  try { . $nadzPlikModulu }
  catch { throw "stan-nadzorcy.ps1: nie da sie wczytac modulu $nadzPlikModulu ($($_.Exception.Message))" }
  if (-not $script:NadzModuly[$nadzModul]) {
    throw "stan-nadzorcy.ps1: modul $nadzPlikModulu nie wczytal sie do konca (nie ma znacznika na jego koncu - plik pusty albo uciety)"
  }
}

# Ustaw-Nadzorce stoi PO wczytaniu modulow, i to celowo: watek w tle okna
# (KOD_KROKU w nadzorca\w-tle.ps1) wczytuje ten plik tylko wtedy, gdy tej funkcji
# jeszcze nie ma. Po nieudanym wczytaniu nastepny krok sprobuje wiec od nowa i
# znow powie, czego brakuje - zamiast wolac funkcje, ktorych nie ma.
function Ustaw-Nadzorce([string]$zrodlo, [string]$dom, [bool]$proba) {
  $script:NadzZrodlo        = $zrodlo.TrimEnd('\')
  $script:NadzDom           = $dom.TrimEnd('\')
  $script:NadzProba         = $proba
  $script:NadzWiedza        = Join-Path $script:NadzDom ".claude\wiedza"
  $script:NadzPlikStanu     = Join-Path $script:NadzDom ".claude\.megaruchacz-zasobnik.txt"
  $script:NadzPlikDziennika = Join-Path $script:NadzDom ".claude\.megaruchacz-zasobnik.log"
  $script:NadzWywrotki      = @()
}
