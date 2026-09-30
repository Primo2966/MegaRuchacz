# Nadzorca MegaRuchacza - ikona w zasobniku Windows.
#
# PO CO TO ISTNIEJE. Do 0.17.0 rachunek za pamiec, start cyklu wiedzy i ALARM
# O CISZY wisialy w calosci na hookach SessionStart. Gdy hook nie odpalal,
# milknal razem z nim takze mechanizm, ktory mial wykryc, ze nic nie chodzi -
# i tak przez tydzien (17-24.09.2026) nikt nie zobaczyl ani jednej liczby.
# Wykrywacz ciszy, ktory milknie razem z tym, co wykrywa, jest bezuzyteczny.
# Dlatego nadzorca jest PROGRAMEM OSOBNYM: startuje przy zalogowaniu z zadania
# w Harmonogramie, nie wie nic o tym, czy uzytkownik otworzyl Claude Code,
# i to ON jest odtad glownym wyzwalaczem cyklu. Hooki zostaja jako droga zapasowa.
#
# DLACZEGO POWERSHELL, A NIE NODE ANI PYTHON. Warunek ze zlecenia brzmial:
# ikona w zasobniku BEZ instalowania czegokolwiek nowego u uzytkownika i bez
# mrugajacej konsoli. Node nie ma zasobnika we wbudowanych modulach (trzeba by
# dolozyc pakiet natywny), Python potrzebowalby pystray i pillow - w obu
# wypadkach to nowa zaleznosc. PowerShell 5.1 jest w Windows z definicji, a razem
# z nim System.Windows.Forms i System.Drawing, czyli NotifyIcon, menu i dymki.
# Zero instalacji. Okno konsoli nie mrugnie, bo zadanie startuje przez
# "conhost.exe --headless powershell.exe -WindowStyle Hidden" - ta sama sztuczka,
# ktorej uzywa juz narzedzia\straznik-zasad.ps1.
#
# --------------------------------------------------------------------------
# UKLAD OKNA - przepisany 24.09.2026 dwa razy. Najpierw, bo poprzedni sypal
# wszystkim naraz; potem, bo byl sciana tekstu bez statystyk.
#
# Uzytkownik nie jest programista i powiedzial wprost: "pelno informacji w ryj
# mam rzuconych, nie wiem na co patrzec", a potem: "przerob okienko, aby bylo
# ladniejsze, miescilo wszystko w sobie. Moze jakies statystyki". Stad decyzje:
#
# 1. KARTY, NIE TEKST. Jasnoszare tlo, na nim biale karty z cienka ramka, kroj
#    Segoe UI. Kolor tylko tam, gdzie niesie znaczenie: czerwien przy sprawie do
#    zrobienia, zolty przy "czegos nie wiem" i przy informacji, zielen przy
#    "wszystko gra", bursztyn na slupku dnia nadrabiania. Reszta szara.
# 2. TRZY LICZBY KOSZTOW jako trzy karty obok siebie: duza liczba, pod nia
#    jedno zdanie CZYM JEST. Karta nauki z rozmow ma dopisek, za jaki okres
#    i czy to bylo nadrabianie - bez niego drogi dzien wygladal jak nowa norma.
# 3. STATYSTYKA NAUKI: wykres slupkowy z 30 dni (jeden slupek na dzien, dzien
#    nadrabiania innym kolorem, prog zwyklego dnia przerywana linia), obok sumy
#    7 i 30 dni, srednia na dzien nauki i typowy zwykly dzien. Malo danych nie
#    daje pustego wykresu bez slowa - okno mowi, ze statystyka dopiero sie zbiera.
# 4. DWA WIDOKI W JEDNYM OKNIE: [Przeglad] i [Szczegoly], przelacznik u gory.
#    Szczegoly (rozbicie, sciezki, pelne tresci alarmow) nie wydluzaja juz okna -
#    zajmuja miejsce przegladu, wiec okno ma stala szerokosc i wysokosc dobrana
#    pod przeglad, bez przewijania na zwyklym ekranie.
# 5. SEKCJA PROBLEMOW ZNIKA, gdy problemow nie ma - nie zostawia pustej ramki.
#    Gdy jest problem, stoi jako pierwsza, na kolorowym tle, z porada bez zargonu
#    i dopiskiem, czy trzeba cos zrobic ("dla informacji - nic nie trzeba robic").
# 6. KAZDY PRZYCISK MOWI, CO ZROBI, a ten jeden, ktory wydaje tokeny, ma szacunek
#    kosztu w samej etykiecie i pyta o zgode. 24.09.2026 jedno kliknieciem
#    "Uruchom cykl teraz" poszlo 312 609 tokenow bez slowa ostrzezenia.
#
# 7. 25.09.2026 (P7): okno szersze (liczone z ekranu), karta "Otwarcie sesji"
#    na Przegladzie (zmierzona calosc z transkryptow i udzial MegaRuchacza),
#    Szczegoly jako karty sekcji zamiast jednego pola tekstu, podglad warstwy
#    z dwiema kolumnami nad trescia.
# 8. 28.09.2026 (P14): dwa kafelki "dokleja do kazdej wiadomosci" i "doklada
#    na otwarcie sesji" usuniete - dublowaly liczby z karty "Otwarcie sesji".
#    Te liczby stoja teraz tylko tam, rozpisane pod paskiem. Kafelek nauki
#    z rozmow na cala szerokosc, z duza liczba jako procent jednego otwarcia
#    sesji: na Przegladzie kazda liczba MegaRuchacza jest w tej samej mierze.
# 9. 28.09.2026 (P17): koszt nauki z powrotem w TOKENACH - karta, wykres (os
#    w tys. tokenow), przycisk, pytanie o zgode i werdykt. Uzytkownik: "te 20%,
#    to nie wiem czego". Jedyne porownanie: udzial w calym dziennym zuzyciu
#    tokenow w rozmowach z Claude (Zuzycie-Dzienne w stan-nadzorcy.ps1).
#    Procent otwarcia okna rozmowy zostal tylko w karcie "Otwarcie okna rozmowy".
# 10. 29.09.2026 (P18): czwarta zakladka "Skille" - polecane skille z bazy
#    skille\katalog.psd1, stan, przyciski Zainstaluj / Aktualizuj teraz / Cofnij.
#    Dozor raz na dobe odpala w tle narzedzia\skille.ps1 -Tryb codziennie.
# 11. 30.09.2026 (P20): lista skilli w grupach zwijanych (na starcie same naglowki
#    z liczbami, pasek z lewej przy grupie z problemem albo nowsza wersja), stan
#    "autor usunal" (szary) i przycisk "Usun u mnie" z kopia zapasowa.
# 12. 30.09.2026 (P21): uzytkownik: "zeby tak dziwnie nie otwierala sie, gdy rano
#    ja klikam ... zeby nie zmieniala swojego rozmiaru w dziki sposob". Okno ma od
#    pierwszej chwili stala wysokosc, wszystko, co wola skrypty, liczy sie w watkach
#    w tle (sekcja "liczenie w tle i ekran ladowania"), a zakladka bez kompletu
#    danych z dzis ma nad soba ekran ladowania z lista krokow.
#
# PRZYCISKU [ODSWIEZ] NIE MA I NIE MA GO BYC. Istnial tylko dlatego, ze okno
# nie odswiezalo sie samo - byl obejsciem braku, nie funkcja. Dzis okno liczy
# od nowa przy otwarciu to, czego nie ma z dzis, starsze niz kwadrans odswieza
# po cichu, a dozor przelicza wszystko co kwadrans; recznemu sprawdzeniu
# zostala pozycja w menu ikony, dla tego, kto wlasnie cos poprawil i chce
# zobaczyc skutek natychmiast.
#
# POLSKIE ZNAKI. Kod i komentarze sa bez ogonkow, ale teksty widoczne w oknie
# maja je miec. Dlatego ten plik ORAZ stan-nadzorcy.ps1 sa zapisane w UTF-8
# ZE ZNACZNIKIEM BOM: bez BOM-u PowerShell 5.1 czyta plik jako ANSI i w oknie
# wychodza krzaki. To sie w tym projekcie zdarzylo juz dwa razy.
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File zasobnik\nadzorca.ps1
#     -Zrodlo <kat>         katalog glowny narzedzia (domyslnie: katalog nad zasobnik\)
#     -KatalogDomowy <kat>  podmiana katalogu domowego (testy, proba negatywna)
#     -Minut <n>            co ile minut dozor sprawdza stan (domyslnie 15)
#     -Pokaz                otwiera okno od razu po starcie
#     -Raz                  JEDEN przebieg dozoru bez petli i bez stalej ikony;
#                           wszystko wypisuje na ekran. Tego trybu uzywa sprawdzenie
#                           i proba negatywna - okna nie da sie sprawdzic bez pulpitu
#     -Raport               sam wydruk okna na ekran, bez dozoru i bez alarmow
#     -Proba                nie startuje cyklu i nic nie zapisuje
#     -Cicho                nie pokazuje dymkow, sam wydruk (tylko z -Raz)
#
# Do OGLADANIA okna bez ryzyka wydania choc jednego tokena:
#   powershell -ExecutionPolicy Bypass -File zasobnik\nadzorca.ps1 -Pokaz -Proba
# "-Proba" zatrzymuje Ruszaj-Cykl na sucho, wiec ani dozor, ani przycisk nie
# uruchomia prawdziwego czytania rozmow.
#
# Proba negatywna sekcji problemow - podstawiamy pusty katalog domowy, w ktorym
# nic nigdy nie chodzilo, wiec alarmy musza sie odezwac:
#   powershell -ExecutionPolicy Bypass -File zasobnik\nadzorca.ps1 -Raport -Proba -KatalogDomowy C:\Temp\pusty
#
# Proba negatywna listy zmian w pamieci - w podstawionym katalogu domowym
# kladziemy wlasny .claude\wiedza\.wiedza-stan.txt (NIGDY prawdziwy): z dwiema
# liniami meldunek_N ma pokazac obie z identyfikatorami, z "meldunek: bez zmian"
# jedna linie, a bez pliku - "nie wiem", nigdy zero.
#
# Proba negatywna kosztu nauki i statystyki - w podstawionym katalogu domowym
# kladziemy wlasne .claude\wiedza\.koszt-cyklu.txt i .koszt-historia.tsv (NIGDY
# prawdziwe) i ogladamy wydruk -Raport -Proba:
#   - zwykly, jednodniowy przebieg nad progiem   -> [!] czerwony alarm "za zwykly dzien",
#   - nadrabianie rozmow sprzed wielu dni       -> [i] zolta informacja "nadrabiala zaleglosc",
#   - brak historii                             -> "statystyka dopiero sie zbiera", zadnego zera.
# Informacja [i] nie idzie na dymek i nie podnosi kodu wyjscia -Raz.
#
# Kod wyjscia w trybie -Raz: 0 gdy nie bylo alarmow, 1 gdy byl choc jeden.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [string]$KatalogDomowy = $HOME,
  [int]$Minut = 15,
  [switch]$Pokaz,
  [switch]$Raz,
  [switch]$Raport,
  [switch]$Proba,
  [switch]$Cicho
)

. (Join-Path $PSScriptRoot "stan-nadzorcy.ps1")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Ustaw-Nadzorce $Zrodlo $KatalogDomowy ([bool]$Proba)

# WYKRES. .NET Framework 4.x ma wbudowana kontrolke wykresow
# (System.Windows.Forms.DataVisualization) - nic do instalowania. Na maszynie
# uzytkownika lezy w GAC (sprawdzone 24.09.2026: C:\Windows\Microsoft.NET\assembly\
# GAC_MSIL\System.Windows.Forms.DataVisualization\v4.0_4.0.0.0__31bf3856ad364e35).
# Gdyby sie nie zaladowala albo wywrocila przy rysowaniu, slupki rysuje sam
# nadzorca (Graphics w zdarzeniu Paint) - wykres ma byc tak czy owak, a powod
# idzie do dziennika i do szczegolow. Proba ladowania jest takze w trybie
# -Raport, zeby wydruk mowil, czym okno naprawde rysuje.
$script:JestChart     = $false
$script:ChartZawiodl  = $false
$script:PowodBezChart = ""
try {
  Add-Type -AssemblyName System.Windows.Forms.DataVisualization -ErrorAction Stop
  $script:JestChart = $true
} catch {
  try {
    Add-Type -AssemblyName "System.Windows.Forms.DataVisualization, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35" -ErrorAction Stop
    $script:JestChart = $true
  } catch {
    $script:PowodBezChart = $_.Exception.Message
    Notuj "wykres: kontrolka Chart sie nie zaladowala ($($script:PowodBezChart)) - slupki rysuje sam nadzorca"
  }
}

function Opis-Rysownika {
  if ($script:JestChart -and (-not $script:ChartZawiodl)) {
    return "rysuje go wbudowana w Windows kontrolka Chart (.NET Framework, nic do instalowania)"
  }
  return "słupki rysuje sam nadzorca, bo kontrolka Chart nie jest dostępna: $($script:PowodBezChart)"
}

# Bez katalogu zrodlowego nadzorca nie ma czego wolac i pokazywalby same
# "NIE WIADOMO" - a to wyglada jak usterka narzedzia, nie jak zla sciezka.
# Mowimy wprost i konczymy, zamiast udawac, ze cos nadzorujemy.
if (-not (Test-Path (Join-Path $Zrodlo "narzedzia\koszt-pamieci.ps1"))) {
  Write-Error "nadzorca: w '$Zrodlo' nie ma narzedzia\koszt-pamieci.ps1 - podaj wlasciwy -Zrodlo"
  exit 2
}

# Sufity Windows na dymek. Nie sa nasze - to twarde granice API powiadomien.
# Zgodnie z zasada "sufit nie ucina, sufit krzyczy" skrocony tekst dostaje
# ostrzezenie NA POCZATKU (poczatek przezywa uciecie zawsze), a cala tresc
# i tak idzie do okna oraz do dziennika, wiec nic nie ginie po cichu.
$MAX_TYTUL = 60
$MAX_TRESC = 240

function Skroc-Na-Dymek([string]$tekst, [int]$limit, [string]$ostrzezenie) {
  if (-not $tekst) { return "" }
  if ($tekst.Length -le $limit) { return $tekst }
  $zapas = $limit - $ostrzezenie.Length
  if ($zapas -lt 10) { return $ostrzezenie.Substring(0, [math]::Min($ostrzezenie.Length, $limit)) }
  return $ostrzezenie + $tekst.Substring(0, $zapas)
}

# Ikona. Bierzemy logo narzedzia z katalogu zrodlowego; gdy go nie ma albo nie
# da sie wczytac, zostaje ikona systemowa - program ma sie pokazac w zasobniku
# tak czy owak, bo bez ikony nie ma calego nadzorcy.
function Ikona-Nadzorcy {
  $plik = Join-Path $Zrodlo "logo.png"
  if (Test-Path $plik) {
    try {
      $obraz = [System.Drawing.Image]::FromFile($plik)
      $male = New-Object System.Drawing.Bitmap($obraz, 32, 32)
      $obraz.Dispose()
      return [System.Drawing.Icon]::FromHandle($male.GetHicon())
    } catch {
      Zanotuj-Wywrotke "wczytanie ikony z $plik" $_
    }
  }
  return [System.Drawing.SystemIcons]::Application
}

# ------------------------------------------------------------- zbieranie danych

# Zbierz-Wszystko mieszka od 0.22.4 (P21) w stan-nadzorcy.ps1: okno liczy dane
# w watku w tle, ktory wczytuje sam stan-nadzorcy.ps1 - funkcja musi byc tam.

# ------------------------------------------------------- co wymaga uwagi TERAZ

function Problem([string]$waga, [string]$tytul, [string]$porada, [string]$pelne) {
  return [pscustomobject]@{ Waga = $waga; Tytul = $tytul; Porada = $porada; Pelne = $pelne }
}

# Tytuly alarmow zaczynaja sie od "MegaRuchacz: ", bo ida takze na dymek, gdzie
# trzeba powiedziec, kto wola. W oknie MegaRuchacza ten przedrostek jest szumem.
function Bez-Przedrostka([string]$tytul) {
  if (-not $tytul) { return "" }
  return ($tytul -replace '^\s*MegaRuchacz\s*:\s*', '')
}

# JEDNA lista spraw wymagajacych uwagi - ta sama dla okna i dla wydruku -Raport,
# zeby nie dalo sie ich rozjechac. Pusta lista znaczy "nic sie nie pali" i wtedy
# w oknie ta sekcja W OGOLE NIE ISTNIEJE, a nie stoi pusta.
#
# Cisza jest zakazana, wiec na liscie sa nie tylko alarmy, ale tez KAZDY powod,
# dla ktorego liczby moga byc niepelne: nieudane odswiezenie, brak rachunku albo
# stanu cyklu, wywrotka z poprzedniego przebiegu. Stare liczby pokazane jako
# biezace byly przez tydzien najdrozszym bledem tego narzedzia.
function Zbierz-Problemy($d, $wywrotki, [string]$blad, $czasDanych) {
  $lista = @()

  if ($blad) {
    $ogon = "Nie mam żadnych świeżych liczb do pokazania."
    if ($czasDanych) { $ogon = "Liczby niżej są sprzed $($czasDanych.ToString('HH:mm')) i mogą być nieaktualne." }
    $lista += Problem "uwaga" "Nie udało się przeliczyć liczb" $ogon $blad
  }

  if ($d) {
    foreach ($a in @($d.Alarmy)) {
      $lista += Problem (Waga-Z-Alarmu $a) (Bez-Przedrostka $a.Tytul) (Porada-Z-Alarmu $a) $a.Tresc
    }
    # Informacje (np. "nauka nadrabiala zaleglosc") stoja w oknie razem z alarmami,
    # na zoltym tle, ale z dopiskiem, ze nic nie trzeba robic - i nie ida na dymek.
    foreach ($a in @($d.Informacje)) {
      $lista += Problem "info" (Bez-Przedrostka $a.Tytul) (Porada-Z-Alarmu $a) $a.Tresc
    }
    if ((-not $d.Rachunek) -or (-not $d.Cykl)) {
      $lista += Problem "uwaga" "Nie wszystko udało się odczytać" (
        "Część liczb w tym oknie może być niepełna, a alarmów w ogóle nie policzyłem. " +
        "Otwórz zakładkę Szczegóły - tam stoi, czego zabrakło.") ""
    }
  } else {
    $lista += Problem "uwaga" "Nie mam jeszcze żadnych liczb" (
      "Nic się nie policzyło. Otwórz zakładkę Szczegóły albo zajrzyj do dziennika nadzorcy.") ""
  }

  if (@($wywrotki).Count -gt 0) {
    $lista += Problem "uwaga" "Przy poprzednim przebiegu coś się nie udało" (
      "MegaRuchacz potknął się w tle. Pełna treść jest w zakładce Szczegóły.") ((@($wywrotki)) -join " | ")
  }

  # Skille (P18): nieudane albo dawno niewykonane codzienne sprawdzenie - sam plik
  # znacznika, bez wolania skryptu.
  try {
    foreach ($p in (Problemy-Skilli)) { $lista += Problem $p.Waga $p.Tytul $p.Porada $p.Pelne }
  } catch { Zanotuj-Wywrotke "odczyt znacznika skilli" $_ }

  # Czerwone przed zoltymi, zolte przed informacjami: pierwsza rzecz na ekranie
  # ma byc ta, ktora naprawde czegos wymaga, a nie ta, ktorej akurat nie wiemy.
  $lista = @($lista | Sort-Object -Property @{ Expression = { Kolejnosc-Wagi $_.Waga } })
  return ,$lista
}

function Kolejnosc-Wagi([string]$waga) {
  if ($waga -eq "pilne") { return 0 }
  if ($waga -eq "info") { return 2 }
  return 1
}

# Waga niesiona przez sam alarm wygrywa; bez niej - wedlug tematu, jak dotad.
function Waga-Z-Alarmu($a) {
  if ($a.Waga) { return $a.Waga }
  return (Waga-Alarmu $a.Temat)
}

# Porada gotowa (alarmy kosztu mowia same, za co i za jaki okres) albo odsiana
# z tresci bez sciezek i komend, jak dotad.
function Porada-Z-Alarmu($a) {
  if ($a.Porada) { return $a.Porada }
  return (Porada-Ludzka $a.Tresc)
}

# Ile spraw naprawde wymaga uwagi - informacje sie nie licza. Od tego zalezy,
# czy w oknie stoi "Wszystko gra".
function Ile-Wymaga-Uwagi($problemy) {
  return @(@($problemy) | Where-Object { $_ -and ($_.Waga -ne "info") }).Count
}

# ------------------------------------------------------------- napisy przyciskow

# Napisy powstaja TUTAJ, w jednym miejscu, i ten sam tekst widzi uzytkownik
# w oknie oraz w wydruku -Raport. Gdyby powstawaly osobno, wydruk mowilby
# o przycisku, ktorego w oknie nie ma - a tak wlasnie zaczyna sie nieufnosc
# do narzedzia.
#
# Etykieta przycisku, ktory wydaje tokeny, NIESIE SZACUNEK KOSZTU. Uzytkownik ma
# zobaczyc liczbe zanim kliknie, a nie dowiedziec sie o niej z rachunku nazajutrz.
#
# P17 (28.09.2026): koszt na przycisku w TOKENACH. Procent otwarcia okna
# rozmowy (P15) nic uzytkownikowi nie mowil przy koszcie dziennym; porownanie
# z calym dziennym zuzyciem ($zuzycie = Zuzycie-Dzienne) stoi w pytaniu o zgode.
# Bez slowa "zalegle": czytanie i tak idzie samo raz dziennie, przycisk robi to
# tylko wczesniej - i opis mowi to wprost.
function Napisy-Przyciskow($d, $zuzycie = $null) {
  $n = [pscustomobject]@{
    Aktualizuj     = "Sprawdź i pobierz nowszą wersję MegaRuchacza"
    AktualizujOpis = "Nie kosztuje nic. Zagląda na serwer po poprawki i nanosi je."
    Cykl           = "Przeczytaj teraz nowe rozmowy"
    CyklOpis       = "Nie musisz - MegaRuchacz robi to sam raz dziennie. Zapyta o zgodę."
    CyklWlaczony   = $true
    Szacunek       = $null
  }

  if ($d -and $d.Wersja -and ($null -ne $d.Wersja.Nowsza) -and ($d.Wersja.Nowsza -gt 0)) {
    $n.Aktualizuj = "Pobierz nowszą wersję MegaRuchacza ($($d.Wersja.Nowsza) do pobrania)"
  }

  $s = $null
  if ($d) {
    try { $s = Szacunek-Cyklu $d.Cykl }
    catch { Zanotuj-Wywrotke "szacunek kosztu czytania rozmow" $_ }
  }
  $n.Szacunek = $s

  if ($d -and $d.Cykl -and $d.Cykl.Pracuje) {
    # Drugi przebieg w tej samej chwili nic nie da, a kosztowalby drugi raz.
    $n.CyklWlaczony = $false
    $n.CyklOpis = "Wyłączone: czytanie rozmów właśnie trwa. Liczby odświeżą się same, gdy skończy."
  } elseif (-not $s) {
    $n.Cykl = "Przeczytaj teraz nowe rozmowy (koszt: nie wiem)"
    $n.CyklOpis = "Nie musisz - robi to sam raz dziennie. Nie mam danych, żeby oszacować koszt; przed startem zapyta o zgodę."
  } elseif (($null -ne $s.Porcje) -and ($s.Porcje -le 0)) {
    $n.CyklWlaczony = $false
    $n.CyklOpis = "Wyłączone: nic nie czeka, wszystkie rozmowy są już przeczytane."
  } elseif ($null -ne $s.Tokeny) {
    $n.Cykl = "Przeczytaj teraz nowe rozmowy ($(Tokeny-Okolo $s.Tokeny) tokenów)"
    $n.CyklOpis = "Nie musisz - robi to sam raz dziennie. Zapyta o zgodę i pokaże, skąd ta liczba."
  } else {
    $n.Cykl = "Przeczytaj teraz nowe rozmowy (koszt: nie wiem)"
    $n.CyklOpis = "Nie umiem oszacować kosztu: $($s.Powod). Przed startem zapyta o zgodę."
  }
  return $n
}

# ----------------------------------------------------------- wydruk tego, co widac

# Czesc MegaRuchacza rozpisana na dwa kawalki, ktore laik rozroznia (P14,
# 28.09.2026). Do tej pory te same liczby staly drugi raz w dwoch kafelkach pod
# karta ("dokleja do kazdej wiadomosci", "doklada na otwarcie sesji") i
# uzytkownik pytal, czym to sie rozni. Teraz stoja TYLKO tu, w tej samej mierze
# co reszta Przegladu: procent jednego otwarcia sesji. Liczby z pomiaru -Start,
# niczego nie przeliczamy; brak liczby to "nie wiem", nigdy zero.
function Skladniki-Mr($start, $o) {
  $lista = @()
  if (-not $start -or -not $o -or -not $o.Zmierzone) { return ,$lista }
  foreach ($x in @(
      @("raz na start rozmowy: zasady i wiedza o Tobie i firmie", $start.MrStart, "", ""),
      @("przy każdej Twojej wiadomości: przypomnienie zasad", $start.MrWiadomosc, "+", "stała dopłata - tyle samo, czy piszesz dwa słowa, czy długi tekst"))) {
    $liczba = "nie wiem"; $proc = ""
    if ($null -ne $x[1]) {
      $liczba = "$($x[2])$(Liczba-Ludzka ([long]$x[1]))"
      $proc = Procent-Drobny ([double]$x[1]) ([double]$o.Razem)
    }
    $uw = ""
    if ($null -ne $x[1]) { $uw = $x[3] }
    $lista += [pscustomobject]@{ Napis = $x[0]; Liczba = $liczba; Proc = $proc; Uwaga = $uw }
  }
  return ,$lista
}

# Przod okna jako tekst: dokladnie te sekcje i w tej samej kolejnosci, co
# w oknie. Ten wydruk jest jedynym sposobem sprawdzenia ukladu bez pulpitu.
function Zbuduj-Przod($d, $problemy, $czas, $start, $zuzycie = $null) {
  $l = @()
  $l += "MegaRuchacz - nadzorca                      [ Przegląd | Szczegóły | Warstwy pamięci ]   <- przełącznik widoków u góry okna"
  $stempel = "przed chwilą"
  if ($czas) { $stempel = $czas.ToString('yyyy-MM-dd HH:mm:ss') }
  $l += "liczby sprawdzone: $stempel  (okno odświeża je samo w tle co $Minut min; starsze niż dzisiejsze liczy od nowa przy otwarciu)"
  $l += ""

  $l += "WERDYKT   (w oknie: pierwsza karta, duże zdanie - zielone: mało, czerwone: dużo, żółte: nie wiadomo)"
  $wd = $null
  try { $wd = Werdykt-Kosztu $start $(if ($d) { $d.Rachunek } else { $null }) $(if ($d) { $d.Cykl } else { $null }) $zuzycie }
  catch { Zanotuj-Wywrotke "werdykt do wydruku" $_ }
  if (-not $wd) {
    $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy"
  } else {
    $l += "  [$($wd.Stan)] $($wd.Zdanie)"
    if ($wd.Wyjasnienie) { $l += "  $($wd.Wyjasnienie)" }
    if ($wd.Nauka) { $l += "  $($wd.Nauka)" }
  }
  $l += ""

  $wazne =@(@($problemy) | Where-Object { $_.Waga -ne "info" })
  $info  = @(@($problemy) | Where-Object { $_.Waga -eq "info" })
  if (($wazne.Count -eq 0) -and ($info.Count -eq 0)) {
    $l += "CO WYMAGA UWAGI"
    $l += "  nic - w oknie tej sekcji wtedy w ogóle nie ma i nie zajmuje miejsca"
    $l += ""
  }
  if ($wazne.Count -gt 0) {
    $l += "CO WYMAGA UWAGI   (w oknie: karty na samej górze, czerwone [!] albo żółte [?])"
    foreach ($p in $wazne) {
      $znak = "[?]"
      if ($p.Waga -eq "pilne") { $znak = "[!]" }
      $l += "  $znak $($p.Tytul)"
      if ($p.Porada) { $l += "      $($p.Porada)" }
    }
    $l += ""
  }
  if ($info.Count -gt 0) {
    $l += "WARTO WIEDZIEĆ   (w oknie: żółta karta z dopiskiem 'dla informacji - nic nie trzeba robić', bez dymka)"
    foreach ($p in $info) {
      $l += "  [i] $($p.Tytul)"
      if ($p.Porada) { $l += "      $($p.Porada)" }
    }
    $l += ""
  }

  $l += "OTWARCIE OKNA ROZMOWY   (w oknie: karta z dużą liczbą i paskiem - MegaRuchacz kontra sam Claude Code)"
  $os = $null
  try { $os = Opis-Startu $start } catch { Zanotuj-Wywrotke "otwarcie okna rozmowy do wydruku" $_ }
  if (-not $os) {
    $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy"
  } elseif (-not $os.Zmierzone) {
    $l += "  nie zmierzono, bo $($os.Powod)."
    if ($null -ne $os.Mr) { $l += "  sama część MegaRuchacza (z rachunku): ~$(Liczba-Ludzka $os.Mr) tokenów - procentu nie ma, bo nie ma całości" }
  } else {
    $l += "  Otwarcie okna rozmowy: ~$(Okolo $os.Razem) tokenów. Z tego MegaRuchacz: $(Okolo $os.Mr) ($($os.MrProc)) · Claude Code sam: $(Okolo $os.Cc) ($($os.CcProc))"
    foreach ($sk in (Skladniki-Mr $start $os)) { $l += "      $($sk.Napis): $($sk.Liczba)   ($($sk.Proc))" }
    $zw = Zdanie-Wiadomosci $start
    if ($zw) { $l += "      $zw" }
    $l += "  $($os.Portfel)"
    $l += "  $($os.Podstawa) $($os.Zakres)   (drobnym drukiem)"
  }
  $l += ""

  $l += "NAUKA Z ROZMÓW   (w oknie: karta na całą szerokość pod otwarciem okna rozmowy)"
  $r = $null; $c = $null
  if ($d) { $r = $d.Rachunek; $c = $d.Cykl }
  $trzy = @()
  try { $trzy = @(Liczba-Nauki $r $c) }
  catch { Zanotuj-Wywrotke "koszt nauki do wydruku" $_; $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy" }
  foreach ($t in $trzy) {
    $l += "  | $($t.Naglowek)"
    if ($null -ne $t.Liczba) {
      $tn = Teksty-Nauki $t $zuzycie
      $l += "  |   $($tn.Duza)  (duża liczba w oknie)  $($tn.Jednostka)"
      if ($t.Znacznik) {
        $zn = "[$($t.Znacznik)]"
        if ($t.ZnacznikWaga -eq "pilne") { $zn = "$zn  (czerwony napis)" }
        elseif ($t.ZnacznikWaga) { $zn = "$zn  (żółty napis)" }
        $l += "  |   $zn"
      }
      $l += "  |   $($tn.Porownanie)$(if (-not $tn.PorownanieJest) { '  (żółty napis)' })"
      if ($tn.Drobny) { $l += "  |   $($tn.Drobny)   (drobnym drukiem)" }
    } else {
      $l += "  |   nie wiem - $($t.Powod)"
    }
    $l += "  |   $($t.Opis)"
  }
  $l += ""

  $st = $null
  try { $st = Statystyka-Okna $r }
  catch { Zanotuj-Wywrotke "statystyka nauki do wydruku" $_ }
  $l += "KOSZT CZYTANIA ROZMÓW - OSTATNIE 30 DNI   (w oknie: dalszy ciąg karty nauki, wykres słupkowy w tysiącach tokenów - $(Opis-Rysownika))"
  if (-not $st) {
    $l += "  NIE UDALO SIE ZLOZYC STATYSTYKI - szczegoly w dzienniku nadzorcy"
  } else {
    $l += Linie-Statystyki $st $r $zuzycie
  }
  $l += ""

  $l += "STAN   (w oknie: karta z dwiema kolumnami - co i jak)"
  if ((Ile-Wymaga-Uwagi $problemy) -eq 0) { $l += "  Wszystko gra - nic nie wymaga Twojej uwagi." }
  $linie = @()
  if ($d) {
    try { $linie = Linie-Stanu $d.Wersja $d.Cykl $d.Przeliczanie }
    catch { Zanotuj-Wywrotke "linie stanu do wydruku" $_; $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy" }
  }
  foreach ($x in $linie) { $l += "  $x" }
  $pm = $null
  try { $pm = Opis-Zmian-Pamieci $(if ($d) { $d.Pamiec } else { $null }) }
  catch { Zanotuj-Wywrotke "zmiany w pamieci do wydruku" $_; $l += "  NIE UDALO SIE ZLOZYC ZMIAN W PAMIECI - szczegoly w dzienniku nadzorcy" }
  if ($pm) {
    $l += "  $($pm.Linia)"
    if (@($pm.Zmiany).Count -gt 0) {
      $l += "      (w oknie schowane pod [pokaż zmiany])"
      foreach ($x in $pm.Zmiany) { $l += "      $x" }
    }
    if ($pm.Porada) { $l += "      $($pm.Porada)" }
  }
  $l += ""

  $l += "PRZYCISKI W OKNIE - co się stanie po kliknięciu"
  $n = Napisy-Przyciskow $d $zuzycie
  $l += "  [$($n.Aktualizuj)]"
  $l += "      $($n.AktualizujOpis)"
  $wl = ""
  if (-not $n.CyklWlaczony) { $wl = "  (przycisk nieaktywny)" }
  $l += "  [$($n.Cykl)]$wl"
  $l += "      $($n.CyklOpis)"
  if ($n.Szacunek) { foreach ($z in $n.Szacunek.Podstawa) { $l += "      $z" } }
  $l += "  [Przegląd] / [Szczegóły] / [Warstwy pamięci]  (przełącznik u góry)"
  $l += "      Szczegóły i warstwy - z czego to się składa i gdzie to leży - zajmują miejsce przeglądu. Nic nie uruchamiają i nic nie kosztują."
  $l += "  [Zamknij okno]"
  $l += "      Okno znika, ikona w zasobniku zostaje i pilnuje dalej."
  return ,$l
}

# Statystyka jako tekst: to samo, co wykres w oknie, tylko paskami ze znakow.
# Sluzy wydrukowi -Raport, czyli sprawdzeniu bez pulpitu.
function Linie-Statystyki($st, $rachunek, $zuzycie = $null) {
  $l = @()
  $zDanymi = @(@($st.Dni) | Where-Object { $_.Jest })
  if ($zDanymi.Count -gt 0) {
    $max = [long]1
    foreach ($x in $zDanymi) { if ($x.Razem -gt $max) { $max = $x.Razem } }
    foreach ($x in $zDanymi) {
      $dl = [int][math]::Round(30.0 * $x.Razem / $max)
      $pasek = ("#" * [math]::Max(0, $dl))
      if (($x.Razem -gt 0) -and ($dl -lt 1)) { $pasek = "|" }
      $rodzaj = @()
      if ($x.Zwykle -gt 0)      { $rodzaj += "zwykły dzień" }
      if ($x.Nadrabianie -gt 0) { $rodzaj += "rozmowy z kilku dni" }
      if ($x.Nieznane -gt 0)    { $rodzaj += "nie wiadomo, z których dni" }
      $l += ("  {0}  {1,-30}  {2,9}  {3}" -f $x.Dzien.ToString('dd.MM'), $pasek, (Liczba-Ludzka $x.Razem), ($rodzaj -join " + "))
    }
  } else {
    $l += "  (wykres bez słupków - w oknie w jego miejscu stoi zdanie niżej)"
  }
  $l += ("  Ostatnie 7 dni: {0}   |   ostatnie {1} dni: {2}" -f (Koszt-Po-Ludzku $st.Suma7), $st.OknoDni, (Koszt-Po-Ludzku $st.Suma30))
  if ($null -ne $st.Srednia) {
    $l += ("  Średnio na dzień nauki: {0} (z {1} {2})" -f (Koszt-Po-Ludzku $st.Srednia), $st.SredniaDni, (Odmiana $st.SredniaDni 'dnia' 'dni' 'dni'))
  } else {
    $l += "  Średnio na dzień nauki: jeszcze nie wiem"
  }
  if (($null -ne $st.Typowy) -and ($st.TypowychDni -gt 0)) {
    $l += ("  Zwykły dzień (rozmowy z poprzedniego dnia): {0} - typowa wartość z {1} {2}" -f (Koszt-Po-Ludzku $st.Typowy), $st.TypowychDni, (Odmiana $st.TypowychDni 'dnia' 'dni' 'dni'))
  } else {
    $l += "  Zwykły dzień (rozmowy z poprzedniego dnia): jeszcze nie wiem - w historii nie ma ani jednego takiego dnia"
  }
  if ($null -ne $st.Prog) {
    $l += "  $(Zdanie-Progu $st $zuzycie)  (w oknie przerywana czerwona linia, gdy mieści się w skali)"
  }
  if ($st.Uwaga) { $l += "  $($st.Uwaga)" }
  return ,$l
}

function Tokeny-Albo-Brak($n) {
  if ($null -eq $n) { return "brak danych" }
  return "~$(Liczba-Ludzka $n) tokenów"
}

# "~40 000 tokenów (40 477)" - od P17 koszt nauki wszedzie w tokenach; procent
# otwarcia okna rozmowy przy koszcie dziennym nic nie mowil.
function Koszt-Po-Ludzku($n) {
  if ($null -eq $n) { return "brak danych" }
  return "$(Tokeny-Okolo $n) tokenów ($(Liczba-Ludzka $n))"
}

# Prog zwyklego dnia (z koszt-pamieci.ps1, cykl.prog) po ludzku: "tu zaczyna
# sie drogo" w tokenach i - gdy jest z czym porownac - jako udzial w calym
# dziennym zuzyciu. Liczba progu idzie z rachunku, tu tylko ja ubieramy w slowa.
function Zdanie-Progu($st, $zuzycie = $null) {
  if (-not $st -or ($null -eq $st.Prog)) { return "" }
  $t = "Drogo dopiero od $(Tokeny-Okolo $st.Prog) tokenów za zwykły dzień"
  if ($zuzycie -and ($zuzycie.Stan -eq "jest")) { $t += " ($(Procent-Udzialu ([double]$st.Prog) ([double]$zuzycie.Srednia)) dziennego zużycia)" }
  return "$t."
}

# SZCZEGOLY JAKO SEKCJE, NIE SCIANA TEKSTU (przebudowane 25.09.2026). Uzytkownik:
# "Szczegoly brzydko wygladaja". Do tej pory byl to jeden TextBox z liniami
# "== NAGLOWEK ==" i dwukropkami. Teraz Sekcje-Szczegolow sklada LISTE SEKCJI
# (tytul, jedno zdanie "co to jest", wiersze etykieta/wartosc, tabele) - okno
# rysuje z niej karty, a wydruk -Raport ten sam tekst. Jedna struktura dla obu,
# zeby wydruk nie mowil o czyms, czego w oknie nie ma.
# Kolejnosc: najpierw to, co wymaga uwagi, potem pieniadze, potem stan, na koncu
# gdzie co lezy. Informacje sa te same co wczesniej - nic nie wypadlo, tylko
# stoja w porzadku i po ludzku.

function Nowa-Sekcja([string]$tytul, [string]$opis) {
  return [pscustomobject]@{ Tytul = $tytul; Opis = $opis; Elementy = (New-Object System.Collections.ArrayList) }
}

function Dodaj-Wiersze($s, $wiersze) {
  foreach ($w in @($wiersze)) {
    if ($w) { [void]$s.Elementy.Add([pscustomobject]@{ Rodzaj = "wiersz"; Etykieta = "$($w.Etykieta)"; Wartosc = "$($w.Wartosc)"; Waga = "$($w.Waga)" }) }
  }
}

function Dodaj-Wiersz($s, [string]$etykieta, [string]$wartosc, [string]$waga = "") {
  Dodaj-Wiersze $s @(Wiersz $etykieta $wartosc $waga)
}

function Dodaj-Tekst($s, [string]$tekst, [string]$waga = "") {
  [void]$s.Elementy.Add([pscustomobject]@{ Rodzaj = "tekst"; Tekst = $tekst; Waga = $waga })
}

function Dodaj-Podtytul($s, [string]$tekst) {
  [void]$s.Elementy.Add([pscustomobject]@{ Rodzaj = "podtytul"; Tekst = $tekst })
}

# Kolumna: @{ N = naglowek; S = szerokosc w oknie (0 = reszta); P = do prawej;
# Pasek = wartosc to procent rysowany paskiem }. Wiersze: tablice napisow.
function Dodaj-Tabele($s, $kolumny, $wiersze) {
  $w = New-Object System.Collections.ArrayList
  foreach ($r in @($wiersze)) { [void]$w.Add([string[]]@($r)) }
  [void]$s.Elementy.Add([pscustomobject]@{ Rodzaj = "tabela"; Kolumny = @($kolumny); Wiersze = $w })
}

# koszt-pamieci.ps1 pisze samym ASCII (tak musi - patrz tamten plik). Do okna
# oddajemy te same slowa z ogonkami, zeby "wiadomosci" nie wygladalo na usterke.
# Tylko pelne slowa ze znanej listy - nieznane zostaja, jak byly.
# Pary, nie slownik: klucze slownika w PowerShellu nie roznia wielkosci liter,
# a "KAZDEJ" i "kazdej" to dwa rozne slowa w wydruku. Porownanie jest dokladne.
$SLOWA_Z_OGONKAMI = @(
  @("uczenie sie na wczesniejszych rozmowach", "nauka z wcześniejszych rozmów"),
  # P16: "sesja" nic uzytkownikowi nie mowi - jednostka jest otwarcie okna rozmowy.
  # Frazy przed pojedynczymi slowami; koszt-pamieci.ps1 zostaje, jak byl.
  @("przy starcie sesji", "przy otwarciu okna rozmowy"), @("na start sesji", "przy otwarciu okna rozmowy"),
  @("start sesji", "otwarcie okna rozmowy"), @("otwarcia sesji", "otwarcia okna rozmowy"),
  @("otwarciu sesji", "otwarciu okna rozmowy"), @("ostatnich sesji", "ostatnich rozmów"),
  @("KAZDEJ", "każdej"), @("kazdej", "każdej"), @("wiadomosci", "wiadomości"), @("wiadomosc", "wiadomość"),
  @("tokenow", "tokenów"), @("RAZ NA DOBE", "raz na dobę"), @("RAZ", "raz"), @("uczenie sie", "nauka"),
  @("wczesniejszych", "wcześniejszych"), @("stala", "stała"), @("biezaca", "bieżąca"), @("dzis", "dziś"),
  @("wywolan", "wywołań"), @("faktow", "faktów"), @("zwykly", "zwykły"), @("dzien", "dzień"),
  @("placona", "płacona"), @("wolaniem", "wołaniem"), @("wygasaja", "wygasają"), @("kosztuja", "kosztują"),
  @("dopoki", "dopóki"), @("wpisow", "wpisów"), @("pamiec", "pamięć"), @("sciezka", "ścieżka"),
  @("caly", "cały"), @("czesc", "część"), @("Biezace", "Bieżące"), @("rozmow", "rozmów"), @("zadan", "zadań"),
  @("czlowiek", "człowiek"), @("recznie", "ręcznie"), @("sie", "się"), @("kazdej", "każdej"),
  @("zaden", "żaden"), @("siega", "sięga"), @("narzedziami", "narzędziami"),
  @("niz", "niż"), @("prog", "próg"), @("calosc", "całość"), @("porownuje", "porównuje"), @("mierze", "mierzę"),
  @("Udzialu", "Udziału"), @("calym", "całym"), @("calosci", "całości"), @("transkryptow", "transkryptów"),
  @("zaleglosci", "zaległości")
)
function Po-Polsku([string]$t) {
  if (-not $t) { return "" }
  foreach ($p in $SLOWA_Z_OGONKAMI) {
    $t = [regex]::Replace($t, "(?<![\p{L}])" + [regex]::Escape($p[0]) + "(?![\p{L}])", $p[1])
  }
  return $t
}

# Rozbicie z koszt-pamieci.ps1 -Rozbicie jako tabele: wiersz pozycji ma postac
# "  nazwa  ####  1 234  54%  uwaga". Linia, ktora nie pasuje do wzorca, NIE
# ginie - idzie jako zwykly tekst pod tabela, w tej samej kolejnosci.
#
# P15: kolumna "% otwarcia sesji" - kazda liczba tokenow MegaRuchacza takze
# w mierze Przegladu ($o = Opis-Startu). Pozycje Codeksa jej nie dostaja: jego
# otwarcia sesji nikt nie mierzy, a procent od sesji Claude Code bylby falszywy.
function Dodaj-Rozbicie($s, $rozbicie, $o = $null) {
  $kol = @(@{ N = "Pozycja"; S = 250 }, @{ N = "Udział"; S = 170; Pasek = $true }, @{ N = "Tokeny"; S = 100; P = $true },
           @{ N = ""; S = 60; P = $true }, @{ N = "% otwarcia okna rozmowy"; S = 180; P = $true }, @{ N = "Uwaga"; S = 0 })
  $wiersze = @()
  $zrzuc = {
    if ($wiersze.Count -gt 0) { Dodaj-Tabele $s $kol $wiersze; Set-Variable -Name wiersze -Value @() -Scope 1 }
  }
  $pierwsza = $true
  $codex = $false
  foreach ($linia in @($rozbicie)) {
    $l = "$linia"
    if (-not $l.Trim()) { continue }
    if ($pierwsza -and ($l -match '^MegaRuchacz - ')) { $pierwsza = $false; continue }
    $pierwsza = $false
    $m = [regex]::Match($l, '^\s{2}(\S.*?)\s+([#|]+)\s+(\d[\d ]*\d|\d)(?:\s+(\d+)%)?(?:\s+(.*?))?\s*$')
    if ($m.Success) {
      $proc = ""
      if ($m.Groups[4].Success) { $proc = $m.Groups[4].Value }
      $pasek = $proc
      if (-not $pasek) { $pasek = "100"; if ($m.Groups[2].Value -eq "|") { $pasek = "0" } }
      $procTxt = ""
      if ($proc) { $procTxt = "$proc%" }
      $sesja = ""
      $tok = [long]($m.Groups[3].Value -replace ' ', '')
      if ((-not $codex) -and ($tok -gt 0)) { $sesja = Proc-Sesji $tok $o }
      elseif ($codex) { $sesja = "nie mierzę" }
      $wiersze += ,@((Po-Polsku $m.Groups[1].Value.Trim()), $pasek, $m.Groups[3].Value, $procTxt, $sesja, (Po-Polsku $m.Groups[5].Value.Trim()))
      continue
    }
    & $zrzuc
    if ($l -match '^\S') { $codex = ($l -match '^Codex') }
    if ($l -match '^\S') {
      Dodaj-Podtytul $s (Z-Wielkiej (Po-Polsku $l.Trim()))
    } else {
      Dodaj-Tekst $s (Po-Polsku $l.Trim()) "szary"
    }
  }
  & $zrzuc
}

function Sekcje-Szczegolow($d, $wywrotkiNadzorcy, $rozbicie, $start) {
  $lista = @()

  # 1. Co wymaga uwagi - pelna tresc, razem z komendami, ktorych nie ma na wierzchu.
  $s = Nowa-Sekcja "Co wymaga uwagi - pełna treść" "To samo, co karty na górze Przeglądu, ale w całości: z nazwami plików i komendami."
  $alarmy = @()
  if ($d) { $alarmy = @($d.Alarmy) + @($d.Informacje) }
  if ($alarmy.Count -eq 0) {
    if ($d -and $d.Cykl -and $d.Rachunek) { Dodaj-Tekst $s "Nic nie wymaga uwagi." "dobrze" }
    else { Dodaj-Tekst $s "Nie wiadomo - brakuje danych, więc alarmów nie policzyłem." "uwaga" }
  } else {
    foreach ($a in $alarmy) {
      $waga = Waga-Z-Alarmu $a
      $etyk = "Do sprawdzenia"; $kol = "uwaga"
      if ($waga -eq "pilne") { $etyk = "Wymaga działania"; $kol = "pilne" }
      elseif ($waga -eq "info") { $etyk = "Dla informacji"; $kol = "uwaga" }
      Dodaj-Wiersz $s $etyk (Bez-Przedrostka $a.Tytul) $kol
      Dodaj-Wiersz $s "" (Po-Polsku "$($a.Tresc)") "szary"
    }
  }
  if ($d -and $d.Rachunek -and $d.Rachunek.Linia) {
    Dodaj-Wiersz $s "Linia rachunku" (Po-Polsku "$($d.Rachunek.Linia)") "szary"
    Dodaj-Wiersz $s "" "te same liczby, które strażnik pokazuje przy otwarciu okna rozmowy" "szary"
  }
  $lista += $s

  # 2. Otwarcie okna rozmowy - skad liczby z karty na Przegladzie.
  $s = Nowa-Sekcja "Otwarcie okna rozmowy - skąd ta liczba" "Ile tokenów Claude wczytuje, gdy otwierasz nowe okno rozmowy (liczone przy pierwszej wiadomości), i jaka część z tego to MegaRuchacz."
  $o = $null
  try { $o = Opis-Startu $start } catch { Zanotuj-Wywrotke "opis otwarcia okna rozmowy do szczegolow" $_ }
  if (-not $start) {
    Dodaj-Tekst $s "Jeszcze nie zmierzone - pomiar rusza przy otwarciu okna." "szary"
  } elseif (-not $o -or -not $o.Zmierzone) {
    $pw = "nie wiadomo dlaczego"
    if ($o -and $o.Powod) { $pw = $o.Powod }
    Dodaj-Wiersz $s "Całość" "nie zmierzono, bo $pw" "uwaga"
    if ($o -and ($null -ne $o.Mr)) { Dodaj-Wiersz $s "MegaRuchacz (rachunek)" "~$(Liczba-Ludzka $o.Mr) tokenów - bez całości nie ma z czego policzyć procentu" }
  } else {
    Dodaj-Wiersz $s "Razem na otwarcie" "~$(Liczba-Ludzka $o.Razem) tokenów (mediana z $($o.Sesji) $(Odmiana $o.Sesji 'rozmowy' 'rozmów' 'rozmów'))"
    # Bez rozbicia na start + przypomnienie (P14): te dwie liczby stoja jako
    # naglowki w sekcji "Rachunek za pamiec" tuz nizej - drugi raz tu tylko mylil.
    Dodaj-Wiersz $s "MegaRuchacz" "~$(Liczba-Ludzka $o.Mr) tokenów ($($o.MrProc)) - to, co dokłada przy otwarciu okna rozmowy, i przypomnienie doklejone do pierwszej wiadomości; każdą pozycję pokazuje sekcja niżej"
    Dodaj-Wiersz $s "Claude Code sam" "~$(Liczba-Ludzka $o.Cc) tokenów ($($o.CcProc)) - jego instrukcje, opisy narzędzi (także z serwerów MCP), lista skilli"
    # "(22%)" to udzial w starcie WORKERA, nie w otwarciu sesji - dopisujemy to wprost (P15)
    if ($o.Worker) { Dodaj-Wiersz $s "Start workera" (($o.WorkerZdanie -replace '^Start jednego workera: ', '') -replace '\((\d+%)\)', '($1 startu workera)') }
    else { Dodaj-Wiersz $s "Start workera" ($o.WorkerZdanie -replace '^Start jednego workera: ', '') "uwaga" }
    Dodaj-Wiersz $s "Jak to zmierzone" ("W każdym transkrypcie Claude Code pierwsza odpowiedź modelu ma pole usage: suma input_tokens, " +
      "cache_creation_input_tokens i cache_read_input_tokens to cały kontekst w tej chwili. Od tego odejmuję Twoją pierwszą wiadomość " +
      "(jej znaki / 3) i biorę medianę z ostatnich rozmów.") "szary"
    Dodaj-Wiersz $s "" "Część MegaRuchacza to rachunek narzędzia (znaki / 3 - szacunek), całość to prawdziwe liczby z transkryptów." "szary"
    Dodaj-Wiersz $s "Transkrypty" "$($start.Katalog)" "szary"
    $ws = @()
    foreach ($x in @(@($start.Sesje.Lista) | Sort-Object { "$($_.Kiedy)" } -Descending)) {
      $kiedy = "$($x.Kiedy)"
      $dt = Data-Lub-Nic $kiedy
      if ($dt) { $kiedy = $dt.ToLocalTime().ToString('dd.MM HH:mm') }
      $proj = ("$($x.Plik)" -split '\\')[0]
      # katalog projektu w transkryptach to sciezka z myslnikami - bez litery dysku czyta sie lepiej
      $proj = $proj -replace '^[A-Za-z]--', ''
      $ws += ,@($kiedy, $proj, (Liczba-Ludzka $x.Kontekst), (Liczba-Ludzka $x.BezWiadomosci))
    }
    if ($ws.Count -gt 0) {
      Dodaj-Podtytul $s "Rozmowy, z których jest mediana"
      Dodaj-Tabele $s @(@{ N = "Kiedy"; S = 110 }, @{ N = "Projekt"; S = 0 }, @{ N = "Kontekst"; S = 110; P = $true }, @{ N = "Bez Twojej wiadomości"; S = 170; P = $true }) $ws
    }
    $ww = @()
    foreach ($x in @(@($start.Workerzy.Lista) | Sort-Object { "$($_.Kiedy)" } -Descending)) {
      $kiedy = "$($x.Kiedy)"
      $dt = Data-Lub-Nic $kiedy
      if ($dt) { $kiedy = $dt.ToLocalTime().ToString('dd.MM HH:mm') }
      $ww += ,@($kiedy, "$($x.Rola)", (Liczba-Ludzka $x.BezWiadomosci))
    }
    if ($ww.Count -gt 0) {
      Dodaj-Podtytul $s "Workerzy, z których jest mediana (bez treści zlecenia)"
      Dodaj-Tabele $s @(@{ N = "Kiedy"; S = 110 }, @{ N = "Rola"; S = 140 }, @{ N = "Start"; S = 110; P = $true }) $ww
    }
  }
  $lista += $s

  # 3. Rachunek pozycja po pozycji.
  $s = Nowa-Sekcja "Rachunek za pamięć, pozycja po pozycji" "Co MegaRuchacz dokleja do rozmowy i ile to waży. Liczy narzędzie koszt-pamieci (znaki podzielone przez 3 - szacunek)."
  if ($null -ne $rozbicie) { Dodaj-Rozbicie $s $rozbicie $o }
  else { Dodaj-Tekst $s "Jeszcze nie policzone." "szary" }
  $lista += $s

  # 4. Nauka z rozmow.
  $s = Nowa-Sekcja "Nauka z rozmów" "Raz dziennie MegaRuchacz czyta Twoje rozmowy i wyciąga z nich fakty do pamięci. To jedyne miejsce, gdzie naprawdę woła model."
  if ($d -and $d.Cykl) { Dodaj-Wiersze $s (Opis-Cyklu $d.Cykl $o) }
  else { Dodaj-Tekst $s "Nie udało się odczytać - szczegóły w dzienniku nadzorcy." "uwaga" }
  $lista += $s

  # 5. Historia kosztu nauki - te same dni i sumy, co na wykresie, plus zrodlo.
  $s = Nowa-Sekcja "Koszt nauki dzień po dniu" "Liczby, z których rysuje się wykres na Przeglądzie."
  $rach = $null
  if ($d) { $rach = $d.Rachunek }
  $st = $null
  try { $st = Statystyka-Okna $rach }
  catch { Zanotuj-Wywrotke "statystyka nauki do szczegolow" $_ }
  if ($st) {
    $skad = "nie wiadomo"; $wagaSkad = "uwaga"
    switch ($st.Zrodlo) {
      "historia"  { $skad = "dziennik przebiegów nauki (.koszt-historia.tsv)"; $wagaSkad = "" }
      "plik-dnia" { $skad = "tylko ostatni pomiar (.koszt-cyklu.txt) - dziennika przebiegów jeszcze nie ma"; $wagaSkad = "uwaga" }
      "brak"      { $skad = "nic - $($st.Powod)"; $wagaSkad = "uwaga" }
    }
    Dodaj-Wiersz $s "Dni wzięte z" $skad $wagaSkad
    $sumy = "nie ma czego sumować"
    if ($st.SumyZ -eq "podsumowanie") { $sumy = "podsumowanie liczone przez samą naukę (.koszt-podsumowanie.txt)" }
    elseif ($st.SumyZ -eq "dni") { $sumy = "zsumowane z dni poniżej (podsumowania nie ma)" }
    Dodaj-Wiersz $s "Sumy 7 i 30 dni" $sumy
    Dodaj-Wiersz $s "Wykres" (Opis-Rysownika)
    $pj = Jak-Sesji $st.Prog $o
    if ($pj) { $pj = " ($pj)" }
    Dodaj-Wiersz $s "Próg zwykłego dnia" "$(Tokeny-Albo-Brak $st.Prog)$pj - uzasadnienie na górze narzedzia\koszt-pamieci.ps1"
    $dni = @()
    foreach ($x in @(@($st.Dni) | Where-Object { $_.Jest })) {
      $dni += ,@($x.Dzien.ToString('yyyy-MM-dd'), (Liczba-Ludzka $x.Razem), (Proc-Sesji $x.Razem $o), (Liczba-Ludzka $x.Zwykle), (Liczba-Ludzka $x.Nadrabianie), (Liczba-Ludzka $x.Nieznane))
    }
    if ($dni.Count -gt 0) {
      Dodaj-Tabele $s @(@{ N = "Dzień"; S = 120 }, @{ N = "Razem"; S = 110; P = $true }, @{ N = "% otwarcia okna rozmowy"; S = 190; P = $true }, @{ N = "Zwykły dzień"; S = 120; P = $true },
                        @{ N = "Nadrabianie"; S = 120; P = $true }, @{ N = "Okres nieznany"; S = 130; P = $true }) $dni
    } else {
      Dodaj-Tekst $s "Jeszcze nie ma ani jednego dnia z kosztem." "szary"
    }
    if ($st.Uwaga) { Dodaj-Tekst $s "$($st.Uwaga)" "szary" }
  } else {
    Dodaj-Tekst $s "Nie udało się złożyć - szczegóły w dzienniku nadzorcy." "uwaga"
  }
  $lista += $s

  # 6. Zmiany w pamieci - razem z komenda cofania, ktora na wierzchu jest zdaniem.
  $s = Nowa-Sekcja "Zmiany w pamięci" "Co ostatnia nauka dopisała albo zmieniła w wiedzy o Tobie i o firmie."
  if ($d -and $d.Pamiec) {
    $pz = $d.Pamiec
    if ($pz.Dzien) { Dodaj-Wiersz $s "Dzień nauki" "$($pz.Dzien.ToString('yyyy-MM-dd'))" }
    if (-not $pz.Wiadomo) { Dodaj-Wiersz $s "Nie wiadomo" "$($pz.Powod)" "uwaga" }
    if ($pz.Naglowek) { Dodaj-Wiersz $s "Meldunek" "$($pz.Naglowek)" }
    foreach ($x in $pz.Zmiany) { Dodaj-Wiersz $s "" "$($x.Tresc)" }
    Dodaj-Wiersz $s "Jak cofnąć" "powiedz Claude'owi: cofnij zmianę <id> - albo ręcznie:" "szary"
    Dodaj-Wiersz $s "" "uv --directory $Zrodlo\lore run python -m lore.verify --cofnij <id>" "szary"
    Dodaj-Wiersz $s "Plik" "$($pz.Plik)" "szary"
  } else {
    Dodaj-Tekst $s "Nie udało się odczytać - szczegóły w dzienniku nadzorcy." "uwaga"
  }
  if ($d -and $d.Przeliczanie -and $d.Przeliczanie.Plik) {
    Dodaj-Wiersz $s "Przeliczanie archiwum" "jest plik $($d.Przeliczanie.Plik)"
    if ($d.Przeliczanie.Powod) { Dodaj-Wiersz $s "" "$($d.Przeliczanie.Powod)" "szary" }
  }
  $lista += $s

  # 7. Wersja.
  $s = Nowa-Sekcja "Wersja MegaRuchacza" "Czy na serwerze czeka coś nowszego. Pobiera to przycisk na dole okna - za darmo."
  if ($d -and $d.Wersja) { Dodaj-Wiersze $s (Opis-Wersji $d.Wersja) }
  else { Dodaj-Tekst $s "Nie udało się ustalić - szczegóły w dzienniku nadzorcy." "uwaga" }
  $lista += $s

  # 8. Nadzorca i pliki.
  $s = Nowa-Sekcja "Nadzorca i gdzie co leży" "Ślad samego nadzorcy (tej ikony w zasobniku) i ścieżki, gdyby trzeba było zajrzeć ręcznie."
  $stan = Czytaj-Klucze (Join-Path $KatalogDomowy ".claude\.megaruchacz-zasobnik.txt")
  if ($stan["byl"]) { Dodaj-Wiersz $s "Ostatni dozór" "$($stan['byl']) (tryb $($stan['byl.tryb']))" }
  else { Dodaj-Wiersz $s "Ostatni dozór" "brak zapisu - to pierwszy przebieg albo nie mogę pisać do pliku stanu" "uwaga" }
  if ($stan["cykl.ruszony"]) { Dodaj-Wiersz $s "Naukę ruszył" "$($stan['cykl.ruszony'])" }
  if (@($wywrotkiNadzorcy).Count -gt 0) {
    foreach ($w in @($wywrotkiNadzorcy)) { Dodaj-Wiersz $s "Wywrotka" "$w" "pilne" }
  } else {
    Dodaj-Wiersz $s "Wywrotki" "żadnych od ostatniego startu"
  }
  Dodaj-Wiersz $s "Dziennik nadzorcy" "$(Join-Path $KatalogDomowy '.claude\.megaruchacz-zasobnik.log')" "szary"
  Dodaj-Wiersz $s "Narzędzie" "$Zrodlo" "szary"
  Dodaj-Wiersz $s "Katalog domowy" "$KatalogDomowy" "szary"
  Dodaj-Wiersz $s "Zebrane" "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "szary"
  $lista += $s

  return ,$lista
}

# Te same sekcje jako tekst - dla wydruku -Raport, jedynego sprawdzenia bez pulpitu.
function Tabela-Na-Tekst($el) {
  $l = @()
  $n = @($el.Kolumny).Count
  $szer = @()
  for ($i = 0; $i -lt $n; $i++) {
    $k = $el.Kolumny[$i]
    $m = "$($k.N)".Length
    foreach ($r in $el.Wiersze) {
      $v = "$($r[$i])"
      if ($k.Pasek) { $v = "#" * [int][math]::Round([double]("0" + $v) / 5) }
      if ($v.Length -gt $m) { $m = $v.Length }
    }
    $szer += [math]::Min($m, 60)
  }
  $fmt = {
    param($wartosci)
    $cz = @()
    for ($i = 0; $i -lt $n; $i++) {
      $v = "$($wartosci[$i])"
      if ($i -eq $n - 1) { $cz += $v; continue }
      if ($el.Kolumny[$i].P) { $cz += $v.PadLeft($szer[$i]) } else { $cz += $v.PadRight($szer[$i]) }
    }
    return ("    " + ($cz -join "  ")).TrimEnd()
  }
  $l += & $fmt @($el.Kolumny | ForEach-Object { "$($_.N)" })
  foreach ($r in $el.Wiersze) {
    $w = @()
    for ($i = 0; $i -lt $n; $i++) {
      $v = "$($r[$i])"
      if ($el.Kolumny[$i].Pasek) { $v = "#" * [int][math]::Round([double]("0" + $v) / 5) }
      $w += $v
    }
    $l += & $fmt $w
  }
  return ,$l
}

function Zbuduj-Szczegoly($d, $wywrotkiNadzorcy, $rozbicie, $start) {
  $l = @()
  $l += "SZCZEGÓŁY   (w oknie: zakładka Szczegóły - każda sekcja to osobna biała karta, najważniejsze na górze)"
  $l += ""
  foreach ($s in (Sekcje-Szczegolow $d $wywrotkiNadzorcy $rozbicie $start)) {
    $l += "== $($s.Tytul.ToUpper()) =="
    if ($s.Opis) { $l += "   $($s.Opis)" }
    foreach ($e in $s.Elementy) {
      switch ($e.Rodzaj) {
        "wiersz" {
          $zn = ""
          if ($e.Waga -eq "pilne") { $zn = "[!] " } elseif ($e.Waga -eq "uwaga") { $zn = "[?] " }
          if ($e.Etykieta) { $l += ("  {0,-24}: {1}{2}" -f $e.Etykieta, $zn, $e.Wartosc) }
          else { $l += ("  {0,-24}  {1}{2}" -f "", $zn, $e.Wartosc) }
        }
        "tekst"    { $l += "  $($e.Tekst)" }
        "podtytul" { $l += "  -- $($e.Tekst)" }
        "tabela"   { $l += Tabela-Na-Tekst $e }
      }
    }
    $l += ""
  }
  return ,$l
}

# Podpowiedz przy ikonie. NotifyIcon.Text ma twardy sufit 63 znakow, wiec tekst
# jest budowany tak, zeby sie zmiescil, a nie ciety po fakcie.
function Podpowiedz($d) {
  $w = "?"
  if ($d -and $d.Wersja -and $d.Wersja.Lokalna) { $w = $d.Wersja.Lokalna }
  $c = "nauka ?"
  if ($d -and $d.Cykl) {
    $g = Godzin-Od-Cyklu $d.Cykl
    if ($null -eq $g) { $c = "nauka NIGDY" }
    elseif ($g -lt 24) { $c = "nauka dzis" }
    else { $c = "nauka stoi $([int]($g / 24)) dni" }
  }
  $a = ""
  if ($d -and (@($d.Alarmy).Count -gt 0)) { $a = " UWAGA x$(@($d.Alarmy).Count)" }
  $t = "MegaRuchacz ${w} - ${c}${a}"
  if ($t.Length -gt 63) { $t = $t.Substring(0, 63) }
  return $t
}

# -------------------------------------------------------------------- dozor

# Jeden przebieg dozoru: zebrac stan, ruszyc cykl jesli trzeba, wystrzelic
# alarmy, zostawic slad "bylem tu". Wolany z zegara co $Minut i raz przy starcie.
# $pokazDymek to skrypt-blok przyjmujacy tytul i tresc - dzieki temu ten sam
# dozor dziala z ikona w zasobniku i bez niej (tryb -Raz).
#
# $zSieci: to DOZOR zaglada po nowsza wersje, a nie okno. Pobranie potrafi trwac
# kilkanascie sekund, a okno ma sie otwierac natychmiast - wiec siec obslugujemy
# tam, gdzie nikt nie czeka. Samo pobranie i tak jest dlawione do raz na pol
# godziny wewnatrz Stan-Wersji.
function Dozor($pokazDymek, [bool]$zKolejka, [bool]$zSieci) {
  $d = Zbierz-Wszystko $zSieci $zKolejka
  Dozor-Po-Danych $d $pokazDymek
  return $d
}

# Druga polowa dozoru - decyzje na gotowych danych. Osobno od P21: w ikonie dane
# licza sie w watku w tle (Rusz-Dozor), a decyzje zapadaja tu, w watku okna,
# gdy dane przyjda - w tej samej kolejnosci co dotad.
function Dozor-Po-Danych($d, $pokazDymek) {
  # Cykl wiedzy - to jest teraz GLOWNY wyzwalacz, niezalezny od hookow.
  try {
    $czy = Czy-Ruszac-Cykl
    if ($czy.Ruszac) {
      Notuj "dozor: ruszam cykl wiedzy ($($czy.Powod))"
      $poszlo = Ruszaj-Cykl
      if (-not $poszlo) {
        & $pokazDymek "MegaRuchacz: nie udalo sie ruszyc cyklu" (
          "Proba startu narzedzia\cykl-dzienny.ps1 nie powiodla sie. " +
          "Uruchom recznie: powershell -ExecutionPolicy Bypass -File $Zrodlo\narzedzia\cykl-dzienny.ps1")
      }
    } else {
      Notuj "dozor: cyklu nie ruszam - $($czy.Powod)"
    }
  } catch { Zanotuj-Wywrotke "decyzja o starcie cyklu" $_ }

  # Polecane skille (P18) - raz na dobe sprawdzenie i pobranie nowszych wersji,
  # w tle i bez okna. Pierwszy przebieg na maszynie tylko spisuje, co jest.
  try {
    $cs = Czy-Sprawdzac-Skille
    if ($cs.Ruszac) {
      Notuj "dozor: sprawdzam skille ($($cs.Powod))"
      if (-not (Ruszaj-Skille)) { Zanotuj-Wywrotke "start codziennego sprawdzenia skilli" "Odpal-W-Tle nie wystartowal narzedzia\skille.ps1" }
    } else {
      Notuj "dozor: skilli nie sprawdzam - $($cs.Powod)"
    }
  } catch { Zanotuj-Wywrotke "decyzja o sprawdzeniu skilli" $_ }

  # Alarmy - jeden na sprawe na dobe, zeby nie uczyly ignorowania.
  foreach ($a in @($d.Alarmy)) {
    if (Alarm-Juz-Byl $a.Temat) { Notuj "alarm [$($a.Temat)] juz dzis byl - nie powtarzam"; continue }
    & $pokazDymek $a.Tytul $a.Tresc
    Notuj "ALARM [$($a.Temat)] $($a.Tytul) :: $($a.Tresc)"
    Odnotuj-Alarm $a.Temat
  }

  Zapisz-Obecnosc "dozor"
}

# --------------------------------------------------------------- tryby bez GUI

if ($Raz -or $Raport) {
  # Teksty okna maja polskie znaki, a konsola Windows startuje na stronie
  # kodowej, ktora ich nie zna. Bez tej linii wydruk sprawdzenia wyglada jak
  # usterka kodowania, choc w samym oknie wszystko jest w porzadku.
  try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 }
  catch { Write-Warning "nie przestawilem konsoli na UTF-8, polskie znaki moga wyjsc jako krzaki: $($_.Exception.Message)" }

  # Wywrotki z poprzedniego przebiegu meldujemy PRZED praca - inaczej nowy
  # przebieg nadpisalby slad po starym i nikt by sie o nim nie dowiedzial.
  $stare = @()
  try { $stare = Odbierz-Wywrotki } catch { Write-Warning "nie odczytalem wywrotek: $($_.Exception.Message)" }
  foreach ($w in $stare) { Write-Output "POPRZEDNIO SIE WYWROCILO: $w" }

  if ($Raport) {
    $d = Zbierz-Wszystko $true $true
    $probl = Zbierz-Problemy $d $stare "" ([datetime]::Now)
    $start = $null
    try { $start = Pomiar-Startu } catch { Zanotuj-Wywrotke "pomiar otwarcia okna rozmowy" $_ }
    $zu = $null
    try { $zu = Zuzycie-Dzienne $true } catch { Zanotuj-Wywrotke "dzienne zuzycie tokenow" $_ }
    $roz = @()
    try { $roz = Rachunek-Rozbicie }
    catch { Zanotuj-Wywrotke "rachunek za pamiec (rozbicie)" $_; $roz = @("  NIE UDALO SIE POLICZYC - szczegoly w dzienniku nadzorcy") }
    Zbuduj-Przod $d $probl ([datetime]::Now) $start $zu | ForEach-Object { Write-Output $_ }
    Write-Output ""
    Zbuduj-Szczegoly $d $stare $roz $start | ForEach-Object { Write-Output $_ }
    Zapisz-Obecnosc "raport"
    exit 0
  }

  # Dymek takze w tym trybie - proba negatywna ma zobaczyc PRAWDZIWE
  # powiadomienie, a nie zapewnienie, ze by sie pokazalo.
  $dymek = {
    param($tytul, $tresc)
    # Pokazujemy CALA tresc i osobno to, co naprawde wchodzi na dymek - roznica
    # miedzy jednym a drugim jest tym, co sufit obcial, a to ma byc widac.
    $naDymekTytul = Skroc-Na-Dymek $tytul $MAX_TYTUL "[skrocone] "
    $naDymekTresc = Skroc-Na-Dymek $tresc $MAX_TRESC "[skrocone - calosc w oknie MegaRuchacza] "
    Write-Host ""
    Write-Host "POWIADOMIENIE"
    Write-Host "  tytul: $tytul"
    Write-Host "  tresc: $tresc"
    Write-Host "  na dymku, tytul ($($naDymekTytul.Length) zn.): $naDymekTytul"
    Write-Host "  na dymku, tresc ($($naDymekTresc.Length) zn.): $naDymekTresc"
    if ($Cicho) { Write-Host "  (-Cicho: dymka nie pokazuje)"; return }
    try {
      $n = New-Object System.Windows.Forms.NotifyIcon
      $n.Icon = Ikona-Nadzorcy
      $n.Visible = $true
      $n.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Warning
      $n.BalloonTipTitle = $naDymekTytul
      $n.BalloonTipText  = $naDymekTresc
      $n.ShowBalloonTip(15000)
      $do = [datetime]::Now.AddSeconds(6)
      while ([datetime]::Now -lt $do) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
      $n.Visible = $false
      $n.Dispose()
      Write-Host "  (dymek pokazany w zasobniku)"
    } catch {
      Write-Host "  (DYMKA NIE DALO SIE POKAZAC: $($_.Exception.Message))"
      Zanotuj-Wywrotke "pokazanie dymka" $_
    }
  }

  $d = Dozor $dymek $true $false
  Write-Output ""
  $probl = Zbierz-Problemy $d $stare "" ([datetime]::Now)
  $start = $null
  try { $start = Pomiar-Startu } catch { Zanotuj-Wywrotke "pomiar otwarcia okna rozmowy" $_ }
  $zu = $null
  try { $zu = Zuzycie-Dzienne $true } catch { Zanotuj-Wywrotke "dzienne zuzycie tokenow" $_ }
  $roz = @()
  try { $roz = Rachunek-Rozbicie }
  catch { Zanotuj-Wywrotke "rachunek za pamiec (rozbicie)" $_; $roz = @("  NIE UDALO SIE POLICZYC - szczegoly w dzienniku nadzorcy") }
  Zbuduj-Przod $d $probl ([datetime]::Now) $start $zu | ForEach-Object { Write-Output $_ }
  Write-Output ""
  Zbuduj-Szczegoly $d $stare $roz $start | ForEach-Object { Write-Output $_ }
  if (@($d.Alarmy).Count -gt 0) { exit 1 }
  exit 0
}

# ------------------------------------------------------------------------ GUI
# Wszystko ponizej ma byc na poziomie skryptu, a nie w cudzych funkcjach:
# procedury obslugi zdarzen WinForms odpalaja sie po powrocie z funkcji,
# w ktorej je zapisano, wiec siegaja wylacznie po $script: i po funkcje skryptu.

[System.Windows.Forms.Application]::EnableVisualStyles()

# Jeden nadzorca na sesje. Drugi - wstawiony np. przez recznie odpalone zadanie -
# dublowalby alarmy i mogl ruszyc cykl dwa razy. Porzucony zamek (poprzedni
# przebieg padl w polowie) liczy sie jako wolny, inaczej jedna wywrotka
# blokowalaby start do konca sesji. Ta sama konstrukcja co w cykl-dzienny.ps1.
$script:Zamek = New-Object System.Threading.Mutex($false, "Local\MegaRuchacz-Nadzorca")
$mojZamek = $false
try { $mojZamek = $script:Zamek.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $mojZamek = $true }
if (-not $mojZamek) {
  Notuj "nadzorca juz chodzi w tej sesji - drugiego nie uruchamiam"
  exit 0
}

# --- stan okna ---------------------------------------------------------------
$script:Okno           = $null
$script:Ikona          = $null
$script:Naglowek       = $null   # pasek u gory: tytul, podtytul, przelacznik widokow
$script:LPodtytul      = $null
$script:BPrzeglad      = $null   # przelacznik [Przeglad | Szczegoly]
$script:BSzczegoly     = $null
$script:WidokPrzeglad  = $null   # karty - przewijane tylko wtedy, gdy ekran jest za niski
$script:WidokSzczegoly = $null   # karty sekcji szczegolow, przewijane
$script:Root           = $null
$script:PanelProblemy  = $null
$script:PanelLiczby    = $null
$script:KartaStat      = $null
$script:PanelStan      = $null
$script:ListaSzczegolow = $null  # karty sekcji w zakladce Szczegoly (od 25.09.2026 zamiast jednego pola tekstu)
$script:KartaStart     = $null   # karta "Otwarcie sesji" na Przegladzie
$script:KartaWerdykt   = $null   # jedno zdanie na samej gorze: MegaRuchacz kosztuje malo / duzo / nie wiadomo (P15)
# Pomiar otwarcia sesji z transkryptow (Pomiar-Startu). Liczony przy otwarciu okna
# (gdy nie ma swiezego) i przy recznym przeliczeniu - nie w dozorze co kwadrans,
# bo nikt go wtedy nie oglada.
$script:Start          = $null
$script:UdzialStartu   = 0.0
# Dzienne zuzycie tokenow w rozmowach z Claude (Zuzycie-Dzienne, P17) - jedyne
# sensowne porownanie dla kosztu nauki. Liczone w osobnym procesie; gdy trwa,
# zegar co 3 s zaglada do pliku podrecznego i odmalowuje okno po wyniku.
$script:Zuzycie        = $null
$script:ZegarZuzycia   = $null
$script:PodgladInfo    = $null   # dwie kolumny nad trescia podgladu warstwy
$script:BWarstwy       = $null   # trzeci przycisk przelacznika
$script:WidokWarstwy   = $null   # warstwy pamieci: lista po lewej, podglad po prawej
$script:LWarstwy       = $null   # jedno zdanie podsumowania nad lista
$script:ListaWarstw    = $null
$script:PodgladWarstwy = $null
# Odpowiedz Warstwy-Pamieci - liczona dopiero przy wejsciu w zakladke, bo wola
# osobny proces, a przeglad ma sie otwierac bez czekania.
$script:DaneWarstw     = $null
# Zakladka "Skille" (P18): lista po lewej (wiersze-karty, bo opis ma sie zawinac,
# a nie uciac trzema kropkami), szczegoly i przyciski po prawej.
$script:BSkille        = $null   # czwarty przycisk przelacznika
$script:WidokSkille    = $null
$script:LSkille        = $null   # zdanie o bezpieczenstwie + podsumowanie
$script:BSkilleTeraz   = $null   # "Sprawdz teraz" - wszystkie skille
$script:ListaSkilli    = $null   # przewijany panel z wierszami
$script:SkilleInfo     = $null   # dwie kolumny o wybranym skillu
$script:SkillePrzyciski = $null
$script:BSkillInstaluj = $null
$script:BSkillAktualizuj = $null
$script:BSkillCofnij   = $null
$script:BSkillUsun     = $null   # "Usun u mnie" - tylko skill usuniety przez autora (P20)
$script:GrupySkilli    = @{}     # rozwiniete grupy (id zrodla -> $true), do zamkniecia okna
$script:NaglowkiGrup   = @{}     # id -> naglowek grupy (przewijanie do niego po kliknieciu)
$script:ZnacznikiGrup  = @{}     # id -> kolor paska z lewej naglowka albo $null
$script:SkillePodglad  = $null   # co sie zmienilo / wynik operacji
$script:DaneSkilli     = $null   # odpowiedz Stan-Skilli
$script:SkillWybrany   = ""
$script:WierszeSkilli  = @{}
$script:ZegarSkilli    = $null
$script:SkilleOperacjaOd = $null
$script:SkilleOperacjaOpis = ""
$script:Pasek          = $null
$script:BAktualizuj    = $null
$script:LAktualizuj    = $null
$script:BCykl          = $null
$script:LCykl          = $null
$script:PanelZmian     = $null   # linie zmian w pamieci, schowane pod "pokaz zmiany"
$script:LinkZmian      = $null
# Rozwiniecie listy zmian przezywa przeliczenie okna - inaczej lista zwijalaby
# sie sama co kwadrans, w trakcie czytania.
$script:ZmianyRozwiniete = $false
$script:Widok          = "przeglad"
# Dane, z ktorych rysuje sie wykres w zdarzeniu Paint - procedura obslugi siega
# wylacznie po $script:, wiec odkladamy je tutaj przy kazdym odmalowaniu.
$script:StatWykresu    = $null
# Jednostka osi wykresu (Ustaw-Miare-Wykresu): od P17 zawsze tysiace tokenow.
$script:WykresDz       = 1000.0
$script:WykresProc     = $false
# Wykres bez karty nauki nad soba (nie dalo sie jej zlozyc) rysuje pelna ramke.
$script:StatSama       = $false
# Wywrotka rysowania meldowana RAZ, a nie przy kazdym odmalowaniu - Paint
# przychodzi dziesiatki razy na minute i zasypalby dziennik.
$script:RysowanieZawiodlo = $false
$script:RamkaZawiodla     = $false

# Bufor: ostatnio zebrane liczby i GODZINA, z ktorej pochodza. Ta godzina jest
# pokazywana zawsze - okno, ktore pokazuje stare liczby jako biezace, klamie.
$script:Dane      = $null
$script:DaneCzas  = $null
$script:DaneBlad  = $null
$script:Rozbicie  = $null   # rozbicie rachunku liczymy dopiero, gdy ktos otworzy szczegoly
$script:Wywrotki  = @()
$script:Licze     = $false
$script:Problemy  = @()
# Gdy widok szczegolow pokazuje cudzy tekst (odpowiedz straznika po pobraniu
# nowszej wersji), przeliczenie danych NIE ma go podmieniac - uzytkownik
# czytalby wtedy co innego, niz przed chwila kliknal.
$script:SzczegolyZajete = $false
# Liczenie w tle i ekran ladowania (P21) - opis przy Rusz-Krok.
$script:StanKawalkow   = @{}     # UWAGA: nie "$script:Kawalki" - PowerShell nie rozroznia wielkosci liter, to bylby $KAWALKI. id kawalka danych -> Czas, Nieudany, Krok (trwajacy), Ostatni
$script:KolejkaKrokow  = New-Object System.Collections.ArrayList   # czekaja na wolne miejsce
$script:KrokiAktywne   = New-Object System.Collections.ArrayList   # otwieraja watek albo licza
$script:WolniRobotnicy = New-Object System.Collections.ArrayList   # otwarte watki bez pracy
$script:Zombie         = New-Object System.Collections.ArrayList   # przerwane po limicie, do sprzatniecia
$script:ZegarKrokow    = $null
$script:KrokDozoru     = $null
$script:CzasyKrokow    = @{}     # id -> ile trwal ostatnio (s), do paska postepu
$script:BladZegaraKrokow = ""
$script:Ladowanie      = $null   # ekran ladowania na wierzchu: widok, kawalki, kroki, od, BladOd
$script:WidokLadowania = $null
$script:ListaKrokow    = $null
$script:WierszeKrokow  = @{}
$script:PasekLadowania = $null
$script:PostepLadowania = 0.0
$script:LLadowanieTytul = $null
$script:LLadowanieOpis = $null
$script:LLadowanieStopka = $null
$script:BPokazTeraz    = $null
$script:TykKrokow      = 0
$script:DoOdmalowania  = @{ przeglad = $true; szczegoly = $true; warstwy = $true; skille = $true }
$script:SkillePoOperacji = $null
$script:PolozenieOkna  = $null   # gdzie uzytkownik zostawil okno - nastepne otwarcie stanie tam samo
$script:PrzydzialPoPokazaniu = $false   # w trakcie budowy okna kroki tylko staja w kolejce (P21)

# --- wyglad ------------------------------------------------------------------
# KOLOR TYLKO TAM, GDZIE NIESIE ZNACZENIE. Czerwony wylacznie przy sprawie,
# ktora wymaga dzialania, zolty przy "czegos nie wiem" i przy informacji,
# zielony przy jednym zdaniu "wszystko gra", bursztyn na slupku dnia
# nadrabiania (ten sam ton, co zolta informacja o nim). Cala reszta jest szara
# albo granatowo-szara. Tecza w oknie uczy ignorowania kolorow.
$script:KolTekst  = [System.Drawing.Color]::FromArgb(28, 28, 30)
$script:KolSzary  = [System.Drawing.Color]::FromArgb(106, 108, 112)
$script:KolPilne  = [System.Drawing.Color]::FromArgb(176, 32, 32)
$script:KolUwaga  = [System.Drawing.Color]::FromArgb(146, 98, 0)
$script:KolDobrze = [System.Drawing.Color]::FromArgb(24, 104, 56)
$script:TloPilne  = [System.Drawing.Color]::FromArgb(253, 236, 236)
$script:TloUwaga  = [System.Drawing.Color]::FromArgb(255, 248, 227)
$script:TloPaska  = [System.Drawing.Color]::FromArgb(250, 250, 251)
$script:TloOkna   = [System.Drawing.Color]::FromArgb(243, 244, 246)
$script:TloKarty  = [System.Drawing.Color]::White
$script:TloPrzel  = [System.Drawing.Color]::FromArgb(228, 230, 234)
$script:TloZnacz  = [System.Drawing.Color]::FromArgb(238, 240, 243)
$script:KolRamki  = [System.Drawing.Color]::FromArgb(224, 226, 230)
$script:KolSiatki = [System.Drawing.Color]::FromArgb(236, 237, 240)
$script:KolOsi    = [System.Drawing.Color]::FromArgb(200, 203, 208)
$script:KolSlupek = [System.Drawing.Color]::FromArgb(92, 108, 130)
$script:KolNadrab = [System.Drawing.Color]::FromArgb(214, 160, 52)
$script:KolNiezn  = [System.Drawing.Color]::FromArgb(176, 182, 190)
# Pasek otwarcia sesji: MegaRuchacz spokojnym niebieskim (to jedyny akcent
# w oknie, ktory nie jest sygnalem ostrzezenia), Claude Code jasnoszarym tlem.
$script:KolMr     = [System.Drawing.Color]::FromArgb(47, 95, 168)
$script:KolCc     = [System.Drawing.Color]::FromArgb(214, 218, 224)
$script:PioroRamki = New-Object System.Drawing.Pen($script:KolRamki)

# Hierarchia robi sie krojem i wielkoscia, nie kolorem. Czcionki sa WSPOLNE dla
# wszystkich etykiet - tworzone przy kazdym odmalowaniu wyciekalyby uchwytami GDI.
# "Segoe UI Semibold" jest w kazdym Windows 10/11; gdyby go nie bylo, Windows
# podstawia zwykly kroj - okno dalej dziala, tylko ciensze.
$script:CzDuza        = New-Object System.Drawing.Font("Segoe UI Semibold", 20)
$script:CzTytul       = New-Object System.Drawing.Font("Segoe UI Semibold", 15)
$script:CzGruba       = New-Object System.Drawing.Font("Segoe UI Semibold", 10.5)
$script:CzSrednia     = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$script:CzZwykla      = New-Object System.Drawing.Font("Segoe UI", 9.75)
$script:CzZwyklaGruba = New-Object System.Drawing.Font("Segoe UI Semibold", 9.75)
$script:CzMala        = New-Object System.Drawing.Font("Segoe UI", 8.75)
$script:CzMalaGruba   = New-Object System.Drawing.Font("Segoe UI Semibold", 8.75)
$script:CzStala       = New-Object System.Drawing.Font("Consolas", 9.5)
$script:CzStalaMala   = New-Object System.Drawing.Font("Consolas", 9)

# Szerokosci - od 25.09.2026 liczone z ekranu, a nie na sztywno. Uzytkownik:
# "wez cale te okna szersze zrob, bardziej czytelne". Okno ma do 1240 px wnetrza
# (na 1920 i 2560 px szerokosci - tyle; na malym ekranie mniej, ale nigdy
# szerzej niz obszar roboczy minus 80 px i nigdy wezej niz 900). Tresc to okno
# minus marginesy po 28 px i 20 px na pionowy suwak, gdy ekran jest za niski -
# suwak poziomy nie ma prawa sie pojawic, a tekst wyjezdzajacy poza krawedz
# bylby ucieciem po cichu.
$script:ObszarEkranu = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$script:SzerOkna    = [int][math]::Max(900, [math]::Min(1240, $script:ObszarEkranu.Width - 80))
$script:Margines    = 28
$script:SzerTresc   = $script:SzerOkna - 2 * $script:Margines - 20
$script:SzerKarty   = $script:SzerTresc
$script:Odstep      = 16
$script:SzerEtykiety = 220   # lewa kolumna w karcie stanu i w szczegolach

# ZLAPANE 24.09.2026 NA PROBIE Z PRAWDZIWYM OKNEM, i to jest dokladnie ten rodzaj
# usterki, dla ktorego istnieje zasada "cisza jest zakazana": proces startowany
# z ukryta konsola (-WindowStyle Hidden, a tak wlasnie robi to zadanie
# w Harmonogramie) przekazuje SW_HIDE ze STARTUPINFO pierwszemu oknu, jakie
# stworzy. Form.Show() konczy sie wtedy bez bledu, okno POWSTAJE - i jest
# niewidzialne. Uzytkownik klikalby ikone i nie dzialoby sie NIC, bez sladu
# w dzienniku. Dlatego po kazdym Show() wymuszamy pokazanie wprost.
Add-Type -Namespace MegaRuchacz -Name Pulpit -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr uchwyt, int jak);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr uchwyt);
'@
$SW_POKAZ = 5   # SW_SHOW

function Wymus-Pokazanie($formularz) {
  try {
    [MegaRuchacz.Pulpit]::ShowWindow($formularz.Handle, $SW_POKAZ) | Out-Null
    [MegaRuchacz.Pulpit]::SetForegroundWindow($formularz.Handle) | Out-Null
  } catch { Zanotuj-Wywrotke "wymuszenie pokazania okna" $_ }
}

# --- klocki okna -------------------------------------------------------------

function Etykieta([string]$tekst, $czcionka, $kolor) {
  $l = New-Object System.Windows.Forms.Label
  $l.AutoSize = $true
  $l.Font = $czcionka
  $l.ForeColor = $kolor
  $l.BackColor = [System.Drawing.Color]::Transparent
  $l.Text = "$tekst"
  $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
  return $l
}

# Etykieta zawijana ma podana MAKSYMALNA szerokosc, a nie stala - dzieki temu
# dluga porada laduje w kilku wierszach zamiast wyjechac poza okno. Tekst, ktory
# wyjezdza poza okno, jest uciety po cichu, a tego w tym projekcie nie wolno.
function Etykieta-Zawijana([string]$tekst, $czcionka, $kolor, [int]$szerokosc) {
  $l = Etykieta $tekst $czcionka $kolor
  $l.MaximumSize = New-Object System.Drawing.Size($szerokosc, 0)
  return $l
}

function Pionowy([int]$szerokosc) {
  $p = New-Object System.Windows.Forms.FlowLayoutPanel
  $p.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
  $p.WrapContents = $false
  $p.AutoSize = $true
  $p.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
  $p.Margin = New-Object System.Windows.Forms.Padding(0)
  $p.Padding = New-Object System.Windows.Forms.Padding(0)
  if ($szerokosc -gt 0) { $p.MinimumSize = New-Object System.Drawing.Size($szerokosc, 0) }
  return $p
}

function Poziomy {
  $p = New-Object System.Windows.Forms.FlowLayoutPanel
  $p.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
  $p.WrapContents = $false
  $p.AutoSize = $true
  $p.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
  $p.Margin = New-Object System.Windows.Forms.Padding(0)
  $p.Padding = New-Object System.Windows.Forms.Padding(0)
  return $p
}

# Biala karta z cienka szara ramka. Ramke rysujemy sami w Paint - BorderStyle
# daje czarna kreske, ktora wyglada jak okno z Windows 95.
function Nowa-Karta([int]$szerokosc) {
  $k = Pionowy $szerokosc
  $k.BackColor = $script:TloKarty
  $k.Padding = New-Object System.Windows.Forms.Padding(22, 16, 22, 16)
  $k.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)
  $k.Add_Paint({ param($nadawca, $e) Obrysuj $nadawca $e })
  return $k
}

function Obrysuj($kontrolka, $e) {
  try {
    $e.Graphics.DrawRectangle($script:PioroRamki, 0, 0, $kontrolka.Width - 1, $kontrolka.Height - 1)
  } catch {
    if (-not $script:RamkaZawiodla) { $script:RamkaZawiodla = $true; Zanotuj-Wywrotke "rysowanie ramki karty" $_ }
  }
}

# Ramka karty, ktora jest dalszym ciagiem karty nad nia (wykres pod karta
# nauki): lewa, prawa i dolna kreska. Gorna tylko wtedy, gdy karty nad nia
# nie ma ($script:StatSama) - inaczej wisialaby bez ramki od gory.
function Obrysuj-Ciag-Dalszy($kontrolka, $e) {
  try {
    $w = $kontrolka.Width - 1; $h = $kontrolka.Height - 1
    $e.Graphics.DrawLine($script:PioroRamki, 0, 0, 0, $h)
    $e.Graphics.DrawLine($script:PioroRamki, $w, 0, $w, $h)
    $e.Graphics.DrawLine($script:PioroRamki, 0, $h, $w, $h)
    if ($script:StatSama) { $e.Graphics.DrawLine($script:PioroRamki, 0, 0, $w, 0) }
  } catch {
    if (-not $script:RamkaZawiodla) { $script:RamkaZawiodla = $true; Zanotuj-Wywrotke "rysowanie ramki wykresu" $_ }
  }
}

function Wyczysc-Panel($panel) {
  if (-not $panel) { return }
  while ($panel.Controls.Count -gt 0) {
    $c = $panel.Controls[0]
    $panel.Controls.RemoveAt(0)
    try { $c.Dispose() }
    catch { Notuj "nie udalo sie zwolnic kontrolki okna: $($_.Exception.Message)" }
  }
}

function Nowy-Przycisk([string]$napis) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $napis
  $b.Height = 34
  $b.Dock = [System.Windows.Forms.DockStyle]::Fill
  $b.Font = $script:CzZwykla
  $b.FlatStyle = [System.Windows.Forms.FlatStyle]::System
  $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 4)
  return $b
}

# Jeden z dwoch przyciskow przelacznika [Przeglad | Szczegoly]: plaski, bez
# ramki, wybrany jest bialy na szarym tle - jak przelacznik w ustawieniach Windows.
function Przycisk-Przelacznika([string]$napis, [int]$x, [int]$szer = 124) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $napis
  $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
  $b.FlatAppearance.BorderSize = 0
  $b.Size = New-Object System.Drawing.Size($szer, 32)
  $b.Location = New-Object System.Drawing.Point($x, 3)
  $b.Cursor = [System.Windows.Forms.Cursors]::Hand
  $b.TabStop = $false
  return $b
}

function Styl-Przelacznika($b, [bool]$wybrany) {
  if (-not $b -or $b.IsDisposed) { return }
  if ($wybrany) {
    $b.BackColor = [System.Drawing.Color]::White
    $b.ForeColor = $script:KolTekst
    $b.Font = $script:CzZwyklaGruba
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::White
  } else {
    $b.BackColor = $script:TloPrzel
    $b.ForeColor = $script:KolSzary
    $b.Font = $script:CzZwykla
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(236, 238, 241)
  }
}

# --- klocki szczegolow (25.09.2026) --------------------------------------------
# Z tych trzech klockow skladaja sie karty w zakladce Szczegoly: wiersz
# "etykieta | wartosc", tabela z liczbami wyrownanymi do prawej i sama karta
# sekcji z tytulem i jednym zdaniem "co to jest". Zawijanie zamiast ucinania -
# tekst, ktory wyjezdza poza karte, bylby ucieciem po cichu.

function Kolor-Wagi([string]$waga) {
  switch ($waga) {
    "pilne"  { return $script:KolPilne }
    "uwaga"  { return $script:KolUwaga }
    "szary"  { return $script:KolSzary }
    "dobrze" { return $script:KolDobrze }
  }
  return $script:KolTekst
}

function Wiersz-Dwukolumnowy([string]$etykieta, [string]$wartosc, $kolor, [int]$szer, [int]$szerEtykiety) {
  $w = Poziomy
  $w.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 5)
  $e = Etykieta-Zawijana $etykieta $script:CzZwykla $script:KolSzary ($szerEtykiety - 12)
  $e.MinimumSize = New-Object System.Drawing.Size($szerEtykiety, 0)
  $e.UseMnemonic = $false
  $w.Controls.Add($e)
  $v = Etykieta-Zawijana $wartosc $script:CzZwykla $kolor ($szer - $szerEtykiety)
  $v.UseMnemonic = $false
  $w.Controls.Add($v)
  return $w
}

# Tabela: TableLayoutPanel, kolumny o stalej szerokosci (ostatnia z zerem dostaje
# reszte), liczby do prawej, cienka kreska pod kazdym wierszem. Kolumna "Pasek"
# rysuje procent poziomym paskiem - udzial widac, zanim sie przeczyta liczbe.
function Tabela-Kontrolka($el, [int]$szer) {
  $t = New-Object System.Windows.Forms.TableLayoutPanel
  $t.AutoSize = $true
  $t.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
  $t.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 10)
  $t.Padding = New-Object System.Windows.Forms.Padding(0)
  $kol = @($el.Kolumny)
  $t.ColumnCount = $kol.Count
  $zajete = 0
  foreach ($k in $kol) { if ($k.S -gt 0) { $zajete += [int]$k.S } }
  $szerokosci = @()
  foreach ($k in $kol) {
    $s = [int]$k.S
    if ($s -le 0) { $s = [math]::Max(120, $szer - $zajete - 4) }
    $szerokosci += $s
    [void]$t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, $s)))
  }
  $t.RowCount = $el.Wiersze.Count + 1
  $t.Add_CellPaint({
    param($nadawca, $e)
    try {
      $y = $e.CellBounds.Bottom - 1
      $e.Graphics.DrawLine($script:PioroRamki, $e.CellBounds.Left, $y, $e.CellBounds.Right, $y)
    } catch { if (-not $script:RamkaZawiodla) { $script:RamkaZawiodla = $true; Zanotuj-Wywrotke "rysowanie kreski w tabeli" $_ } }
  })
  $wiersz = 0
  $wszystkie = @(,[string[]]@($kol | ForEach-Object { "$($_.N)" })) + @($el.Wiersze)
  foreach ($r in $wszystkie) {
    [void]$t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    for ($i = 0; $i -lt $kol.Count; $i++) {
      $k = $kol[$i]
      $v = ""
      if ($i -lt @($r).Count) { $v = "$($r[$i])" }
      if (($wiersz -gt 0) -and $k.Pasek) {
        $p = New-Object System.Windows.Forms.Panel
        $p.Size = New-Object System.Drawing.Size(($szerokosci[$i] - 16), 22)
        $p.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
        $p.BackColor = $script:TloKarty
        $proc = 0
        [void][int]::TryParse($v, [ref]$proc)
        $pas = New-Object System.Windows.Forms.Panel
        $pas.BackColor = $script:KolMr
        $pas.Location = New-Object System.Drawing.Point(0, 7)
        $pas.Size = New-Object System.Drawing.Size([math]::Max(2, [int](($szerokosci[$i] - 16) * [math]::Min(100, $proc) / 100.0)), 9)
        if ($proc -le 0) { $pas.BackColor = $script:KolOsi }
        $p.Controls.Add($pas)
        $t.Controls.Add($p, $i, $wiersz)
        continue
      }
      $cz = $script:CzZwykla; $kolor = $script:KolTekst
      if ($wiersz -eq 0) { $cz = $script:CzMalaGruba; $kolor = $script:KolSzary }
      $l = Etykieta-Zawijana $v $cz $kolor ($szerokosci[$i] - 12)
      $l.UseMnemonic = $false
      $l.Margin = New-Object System.Windows.Forms.Padding(0, 4, 12, 5)
      if ($k.P) {
        $l.Anchor = [System.Windows.Forms.AnchorStyles]::Right
        $l.TextAlign = [System.Drawing.ContentAlignment]::TopRight
      }
      $t.Controls.Add($l, $i, $wiersz)
    }
    $wiersz++
  }
  return $t
}

function Karta-Sekcji($s) {
  $k = Nowa-Karta $script:SzerKarty
  $k.Padding = New-Object System.Windows.Forms.Padding(22, 16, 22, 14)
  $k.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)
  $szer = $script:SzerKarty - 44
  $tyt = Etykieta-Zawijana $s.Tytul $script:CzSrednia $script:KolTekst $szer
  $tyt.UseMnemonic = $false
  $k.Controls.Add($tyt)
  if ($s.Opis) {
    $o = Etykieta-Zawijana $s.Opis $script:CzZwykla $script:KolSzary $szer
    $o.UseMnemonic = $false
    $o.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 12)
    $k.Controls.Add($o)
  }
  foreach ($e in $s.Elementy) {
    switch ($e.Rodzaj) {
      "wiersz" { $k.Controls.Add((Wiersz-Dwukolumnowy $e.Etykieta $e.Wartosc (Kolor-Wagi $e.Waga) $szer $script:SzerEtykiety)) }
      "tekst" {
        $l = Etykieta-Zawijana $e.Tekst $script:CzZwykla (Kolor-Wagi $e.Waga) $szer
        $l.UseMnemonic = $false
        $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 5)
        $k.Controls.Add($l)
      }
      "podtytul" {
        $l = Etykieta-Zawijana $e.Tekst $script:CzZwyklaGruba $script:KolTekst $szer
        $l.UseMnemonic = $false
        $l.Margin = New-Object System.Windows.Forms.Padding(0, 12, 0, 2)
        $k.Controls.Add($l)
      }
      "tabela" { $k.Controls.Add((Tabela-Kontrolka $e $szer)) }
    }
  }
  return $k
}

# Jedna karta z samym tekstem - "licze...", odpowiedz straznika, wywrotka.
function Karta-Komunikatu([string]$tytul, [string[]]$linie, $kolor) {
  $s = Nowa-Sekcja $tytul ""
  foreach ($x in @($linie)) { [void]$s.Elementy.Add([pscustomobject]@{ Rodzaj = "tekst"; Tekst = "$x"; Waga = "" }) }
  $k = Karta-Sekcji $s
  if ($kolor) { foreach ($c in $k.Controls) { if ($c -is [System.Windows.Forms.Label] -and ($c.Font -eq $script:CzZwykla)) { $c.ForeColor = $kolor } } }
  return $k
}

# --- werdykt na samej gorze Przegladu (P15, 28.09.2026) ------------------------
# Jedno zdanie duza czcionka, ktore czlowiek nieznajacy MegaRuchacza zrozumie
# w piec sekund: ile MegaRuchacz kosztuje w stosunku do calosci i czy to malo.
# Stan i slowa sklada Werdykt-Kosztu (stan-nadzorcy.ps1) - tu tylko kolor:
# zielony = malo, czerwony = duzo, zolty = nie wiadomo (i wtedy tlo karty tez
# zolte, zeby "nie wiem" nie wygladalo jak "wszystko gra").
function Odmaluj-Werdykt {
  if (-not $script:KartaWerdykt -or $script:KartaWerdykt.IsDisposed) { return }
  Wyczysc-Panel $script:KartaWerdykt
  $szer = $script:SzerKarty - 44
  $r = $null; $c = $null
  if ($script:Dane) { $r = $script:Dane.Rachunek; $c = $script:Dane.Cykl }
  $w = $null
  try { $w = Werdykt-Kosztu $script:Start $r $c $script:Zuzycie } catch { Zanotuj-Wywrotke "werdykt kosztu" $_ }
  $script:KartaWerdykt.BackColor = $script:TloKarty
  if (-not $w) {
    $script:KartaWerdykt.BackColor = $script:TloUwaga
    $script:KartaWerdykt.Controls.Add((Etykieta-Zawijana "Nie udało się ocenić, ile kosztuje MegaRuchacz - powód jest w dzienniku nadzorcy." $script:CzGruba $script:KolUwaga $szer))
    return
  }
  $kol = $script:KolSzary
  switch ($w.Stan) {
    "malo"        { $kol = $script:KolDobrze }
    "duzo"        { $kol = $script:KolPilne; $script:KartaWerdykt.BackColor = $script:TloPilne }
    "nie wiadomo" { $kol = $script:KolUwaga; $script:KartaWerdykt.BackColor = $script:TloUwaga }
  }
  $z = Etykieta-Zawijana $w.Zdanie $script:CzTytul $kol $szer
  $z.UseMnemonic = $false
  $script:KartaWerdykt.Controls.Add($z)
  # Prog i nauka jednym akapitem pod zdaniem - okno ma sie miescic na ekranie
  # bez przewijania, a karta otwarcia sesji tuz nizej i tak mowi, co jest 100%.
  $reszta = (@($w.Wyjasnienie, $w.Nauka) | Where-Object { $_ }) -join " "
  if ($reszta) {
    $x = Etykieta-Zawijana $reszta $script:CzZwykla $script:KolTekst $szer
    $x.UseMnemonic = $false
    $x.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $script:KartaWerdykt.Controls.Add($x)
  }
}

# --- karta "Otwarcie sesji" na Przegladzie ------------------------------------
# Odpowiedz na pytanie uzytkownika "ile tokenow na otwarcie sesji i jaki to
# procent tego, co dokleja MegaRuchacz". Jedna duza liczba, pasek z dwoma
# kawalkami, dwa wiersze legendy z liczbami wyrownanymi do prawej i jedno
# zdanie, co to znaczy dla portfela. Gdy pomiaru nie ma - "nie zmierzono, bo...",
# bez paska i bez procentu: 0% czytaloby sie jak "MegaRuchacz nic nie kosztuje".
function Wiersz-Legendy-Startu($panel, $kolor, [string]$napis, [string]$liczba, [string]$proc) {
  $w = Poziomy
  $w.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
  $kw = New-Object System.Windows.Forms.Panel
  $kw.Size = New-Object System.Drawing.Size(12, 12)
  $kw.BackColor = $kolor
  $kw.Margin = New-Object System.Windows.Forms.Padding(0, 5, 10, 0)
  $w.Controls.Add($kw)
  $n = Etykieta $napis $script:CzZwykla $script:KolTekst
  $n.AutoSize = $false
  $n.Size = New-Object System.Drawing.Size(430, 22)
  $n.UseMnemonic = $false
  $w.Controls.Add($n)
  $l = Etykieta $liczba $script:CzZwyklaGruba $script:KolTekst
  $l.AutoSize = $false
  $l.Size = New-Object System.Drawing.Size(110, 22)
  $l.TextAlign = [System.Drawing.ContentAlignment]::TopRight
  $w.Controls.Add($l)
  $p = Etykieta $proc $script:CzZwykla $script:KolSzary
  $p.AutoSize = $false
  $p.Size = New-Object System.Drawing.Size(110, 22)
  $p.TextAlign = [System.Drawing.ContentAlignment]::TopRight
  $w.Controls.Add($p)
  $panel.Controls.Add($w)
}

# Wiersz skladnika pod wierszem MegaRuchacza: wciety pod kwadracik legendy,
# szary, te same kolumny liczby i procentu co wiersz nad nim.
function Wiersz-Skladnika-Startu($panel, $sk) {
  $w = Poziomy
  $w.Margin = New-Object System.Windows.Forms.Padding(22, 0, 0, 2)
  $n = Etykieta "$($sk.Napis)" $script:CzMala $script:KolSzary
  $n.AutoSize = $false
  $n.Size = New-Object System.Drawing.Size(430, 20)
  $n.UseMnemonic = $false
  $w.Controls.Add($n)
  $l = Etykieta "$($sk.Liczba)" $script:CzMala $script:KolSzary
  $l.AutoSize = $false
  $l.Size = New-Object System.Drawing.Size(110, 20)
  $l.TextAlign = [System.Drawing.ContentAlignment]::TopRight
  $w.Controls.Add($l)
  $p = Etykieta "$($sk.Proc)" $script:CzMala $script:KolSzary
  $p.AutoSize = $false
  $p.Size = New-Object System.Drawing.Size(110, 20)
  $p.TextAlign = [System.Drawing.ContentAlignment]::TopRight
  $w.Controls.Add($p)
  # P16: "+115 przy kazdej wiadomosci" po ludzku, w tym samym wierszu - bez nowej linii
  if ($sk.Uwaga) {
    $u = Etykieta "- $($sk.Uwaga)" $script:CzMala $script:KolSzary
    $u.Margin = New-Object System.Windows.Forms.Padding(16, 0, 0, 0)
    $w.Controls.Add($u)
  }
  $panel.Controls.Add($w)
}

function Rysuj-Pasek-Startu($g, $rozmiar) {
  try {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    $g.Clear($script:TloKarty)
    $w = [int]$rozmiar.Width; $h = [int]$rozmiar.Height
    $cc = New-Object System.Drawing.SolidBrush($script:KolCc)
    $mr = New-Object System.Drawing.SolidBrush($script:KolMr)
    try {
      $g.FillRectangle($cc, 0, 0, $w, $h)
      $szerMr = [int][math]::Round($w * [double]$script:UdzialStartu)
      if ($szerMr -lt 3) { $szerMr = 3 }   # kawalek ma byc widoczny, choc maly
      $g.FillRectangle($mr, 0, 0, $szerMr, $h)
    } finally { $cc.Dispose(); $mr.Dispose() }
  } catch {
    if (-not $script:RysowanieZawiodlo) { $script:RysowanieZawiodlo = $true; Zanotuj-Wywrotke "rysowanie paska otwarcia okna rozmowy" $_ }
  }
}

function Odmaluj-Start {
  if (-not $script:KartaStart -or $script:KartaStart.IsDisposed) { return }
  Wyczysc-Panel $script:KartaStart
  $szer = $script:SzerKarty - 44
  $tyt = Etykieta "Otwarcie okna rozmowy - nasza miara 100%" $script:CzGruba $script:KolTekst
  $script:KartaStart.Controls.Add($tyt)
  # P16 (28.09.2026): uzytkownik nie wie, co to "sesja" - dla niego to okno, w ktorym
  # pisze, a pisac mozna dwa slowa albo miliony tokenow. Jednostka jest wiec to, co
  # Claude wczytuje przy OTWARCIU nowego okna rozmowy, i tu, raz, stoi to wprost.
  $ileTxt = "swoje instrukcje"
  $o = $null
  if ($null -ne $script:Start) {
    try { $o = Opis-Startu $script:Start } catch { Zanotuj-Wywrotke "opis otwarcia okna rozmowy" $_ }
  }
  if ($o -and $o.Zmierzone) { $ileTxt = "~$(Okolo $o.Razem) tokenów swoich instrukcji" }
  $pod = Etykieta-Zawijana "Za każdym razem, gdy otwierasz nowe okno rozmowy z Claude, zanim napiszesz słowo, Claude wczytuje $ileTxt. To nasza miara 100%." $script:CzMala $script:KolSzary $szer
  $pod.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
  $script:KartaStart.Controls.Add($pod)

  if ($null -eq $script:Start) {
    $script:KartaStart.Controls.Add((Etykieta-Zawijana "Liczę, ile Claude wczytuje na starcie rozmowy - to potrwa kilka sekund..." $script:CzZwykla $script:KolSzary $szer))
    return
  }
  if (-not $o -or -not $o.Zmierzone) {
    $pw = "nie wiadomo dlaczego - to samo w sobie jest usterką"
    if ($o -and $o.Powod) { $pw = $o.Powod }
    $script:KartaStart.Controls.Add((Etykieta "nie zmierzono" $script:CzDuza $script:KolUwaga))
    $script:KartaStart.Controls.Add((Etykieta-Zawijana "Nie zmierzono, bo $pw." $script:CzZwykla $script:KolUwaga $szer))
    if ($o -and ($null -ne $o.Mr)) {
      $czescMr = "Sama część MegaRuchacza (z rachunku): ~$(Liczba-Ludzka $o.Mr) tokenów."
      if ($o.Mr -le 0) { $czescMr = "Rachunek MegaRuchacza też nie znalazł nic doklejanego przy otwarciu okna rozmowy - powód jest w zakładce Szczegóły." }
      $x = Etykieta-Zawijana ("$czescMr " +
        "Bez zmierzonej całości nie da się powiedzieć, jaki to procent - dlatego procentu tu nie ma.") $script:CzZwykla $script:KolSzary $szer
      $x.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
      $script:KartaStart.Controls.Add($x)
    }
    return
  }

  $script:UdzialStartu = $o.UdzialMr
  $wiersz = Poziomy
  $duza = Etykieta ("~" + (Okolo $o.Razem)) $script:CzDuza $script:KolTekst
  $duza.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
  $wiersz.Controls.Add($duza)
  $jed = Etykieta "tokenów przy każdym otwarciu okna rozmowy - to jest 100%" $script:CzZwykla $script:KolSzary
  $jed.Margin = New-Object System.Windows.Forms.Padding(0, 14, 0, 0)
  $wiersz.Controls.Add($jed)
  $script:KartaStart.Controls.Add($wiersz)

  $pasek = New-Object System.Windows.Forms.PictureBox
  $pasek.Size = New-Object System.Drawing.Size($szer, 14)
  $pasek.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 10)
  $pasek.Add_Paint({ param($nadawca, $e) Rysuj-Pasek-Startu $e.Graphics $nadawca.ClientSize })
  $script:KartaStart.Controls.Add($pasek)

  Wiersz-Legendy-Startu $script:KartaStart $script:KolMr "MegaRuchacz - razem, z tego:" "~$(Okolo $o.Mr)" $o.MrProc
  foreach ($sk in (Skladniki-Mr $script:Start $o)) { Wiersz-Skladnika-Startu $script:KartaStart $sk }
  Wiersz-Legendy-Startu $script:KartaStart $script:KolCc "Claude Code sam - jego własne instrukcje i podłączone dodatki" "~$(Okolo $o.Cc)" $o.CcProc

  $p = Etykieta-Zawijana $o.Portfel $script:CzZwykla $script:KolTekst $szer
  $p.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 6)
  $script:KartaStart.Controls.Add($p)
  # Start workera stoi w Szczegolach - na Przegladzie tylko to, co laik rozumie (P15).
  $pods = (@($o.Podstawa, $o.Zakres) | Where-Object { $_ }) -join " "
  $script:KartaStart.Controls.Add((Etykieta-Zawijana $pods $script:CzMala $script:KolSzary $szer))
}

# --- wykres ------------------------------------------------------------------
# Te same dane rysuja dwie drogi: kontrolka Chart (gdy sie zaladowala) albo
# wlasne slupki w Paint. Skala i prog sa liczone RAZ, tutaj, zeby obie drogi
# pokazywaly dokladnie to samo.

# Gorna granica osi: najwyzszy slupek plus zapas, zaokraglona do "ladnej" liczby.
# Prog zwyklego dnia wchodzi do skali tylko wtedy, gdy jest najwyzej dwa razy
# wyzej niz najwyzszy slupek - inaczej zgniotlby wszystkie slupki do kresek,
# a legenda mowi wtedy wprost, ze prog jest daleko ponad nimi.
# MIARA OSI. $script:WykresDz to dzielnik "tokeny -> jednostka osi". Ustawia go
# Odmaluj-Statystyke przed rysowaniem; skala zwracana jest juz w tej jednostce.
# P15 dal tu procent jednego otwarcia sesji.
# P17 (28.09.2026): os ZAWSZE w tysiacach tokenow. Procent otwarcia okna
# rozmowy przy koszcie dziennym nic uzytkownikowi nie mowil. Przelacznik
# $script:WykresProc zostaje (rysowanie go obsluguje), ale nie jest wlaczany.
function Ustaw-Miare-Wykresu {
  $script:WykresDz = 1000.0
  $script:WykresProc = $false
}

function Etykieta-Osi([double]$v) {
  if ($v -le 0) { return "0" }
  $pl = [System.Globalization.CultureInfo]::GetCultureInfo("pl-PL")
  if ($script:WykresProc) { return ($v.ToString("0.#", $pl) + "%") }
  return ($v.ToString("0.#", $pl) + " tys.")
}

function Skala-Wykresu($st) {
  $max = [double]0
  foreach ($d in @($st.Dni)) { if ($d.Razem -gt $max) { $max = [double]$d.Razem } }
  if ($max -le 0) { $max = 1000 }
  $gora = $max
  if (Prog-Widoczny $st) { $gora = [math]::Max($gora, [double]$st.Prog) }
  $gora = $gora * 1.1 / $script:WykresDz
  $potega = [math]::Pow(10, [math]::Floor([math]::Log10($gora)))
  foreach ($m in @(1, 2, 2.5, 4, 5, 10)) {
    if (($m * $potega) -ge $gora) { return [double]($m * $potega) }
  }
  return [double](10 * $potega)
}

function Prog-Widoczny($st) {
  if ((-not $st) -or ($null -eq $st.Prog) -or ($st.Prog -le 0)) { return $false }
  $max = [double]0
  foreach ($d in @($st.Dni)) { if ($d.Razem -gt $max) { $max = [double]$d.Razem } }
  return ([double]$st.Prog -le (2 * $max))
}

function Opis-Dnia-Wykresu($d) {
  $cz = @()
  if ($d.Zwykle -gt 0)      { $cz += "zwykły dzień" }
  if ($d.Nadrabianie -gt 0) { $cz += "rozmowy z kilku dni naraz" }
  if ($d.Nieznane -gt 0)    { $cz += "nie wiadomo, z których dni" }
  return "$($d.Dzien.ToString('dd.MM')): $(Liczba-Ludzka $d.Razem) tokenów ($($cz -join ' + '))"
}

# Droga pierwsza: wbudowana kontrolka Chart. Wyjatek z tej funkcji przelacza
# okno na droge druga (wlasne slupki) - patrz Wstaw-Wykres.
function Nowy-Chart($st) {
  $ch = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
  $ch.BackColor = [System.Drawing.Color]::White
  $ch.AntiAliasing = [System.Windows.Forms.DataVisualization.Charting.AntiAliasingStyles]::All
  $ch.TextAntiAliasingQuality = [System.Windows.Forms.DataVisualization.Charting.TextAntiAliasingQuality]::High

  $ob = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea("obszar")
  $ob.BackColor = [System.Drawing.Color]::White
  foreach ($os in @($ob.AxisX, $ob.AxisY)) {
    $os.LineColor = $script:KolOsi
    $os.MajorTickMark.Enabled = $false
    $os.LabelStyle.Font = $script:CzMala
    $os.LabelStyle.ForeColor = $script:KolSzary
  }
  $ob.AxisX.MajorGrid.Enabled = $false
  $ob.AxisX.IsLabelAutoFit = $false
  $ob.AxisY.MajorGrid.LineColor = $script:KolSiatki
  $skala = Skala-Wykresu $st
  $ob.AxisY.Minimum = 0
  $ob.AxisY.Maximum = $skala
  $ob.AxisY.Interval = $skala / 2.0
  if ($script:WykresProc) {
    $ob.AxisY.LabelStyle.Format = "0.#'%'"
    $ob.AxisY.Title = "% otwarcia`nokna rozmowy"
  } else {
    $ob.AxisY.LabelStyle.Format = "0"
    $ob.AxisY.Title = "tys. tokenów"
  }
  $ob.AxisY.TitleFont = $script:CzMala
  $ob.AxisY.TitleForeColor = $script:KolSzary
  if (Prog-Widoczny $st) {
    $linia = New-Object System.Windows.Forms.DataVisualization.Charting.StripLine
    $linia.IntervalOffset = [double]$st.Prog / $script:WykresDz
    $linia.StripWidth = 0
    $linia.BorderColor = $script:KolPilne
    $linia.BorderDashStyle = [System.Windows.Forms.DataVisualization.Charting.ChartDashStyle]::Dash
    $linia.BorderWidth = 1
    $linia.Text = "tu zaczyna się drogo"
    $linia.TextAlignment = [System.Drawing.StringAlignment]::Far
    $linia.TextLineAlignment = [System.Drawing.StringAlignment]::Far
    $linia.ForeColor = $script:KolPilne
    $linia.Font = $script:CzMala
    $ob.AxisY.StripLines.Add($linia) | Out-Null
  }
  $ch.ChartAreas.Add($ob) | Out-Null

  $serie = @(
    @{ Nazwa = "zwykle";      Kolor = $script:KolSlupek; Pole = "Zwykle" },
    @{ Nazwa = "nieznane";    Kolor = $script:KolNiezn;  Pole = "Nieznane" },
    @{ Nazwa = "nadrabianie"; Kolor = $script:KolNadrab; Pole = "Nadrabianie" }
  )
  foreach ($opis in $serie) {
    $s = New-Object System.Windows.Forms.DataVisualization.Charting.Series($opis.Nazwa)
    $s.ChartArea = "obszar"
    $s.ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::StackedColumn
    $s.Color = $opis.Kolor
    $s["PointWidth"] = "0.62"
    foreach ($d in @($st.Dni)) {
      $i = $s.Points.AddY([double]$d.($opis.Pole) / $script:WykresDz)
      if ($d.Jest) { $s.Points[$i].ToolTip = (Opis-Dnia-Wykresu $d) }
    }
    $ch.Series.Add($s) | Out-Null
  }
  # Podpisy dni co tydzien, liczac od dzis wstecz - tak, zeby dzisiejszy dzien
  # mial podpis zawsze. Punkty sa numerowane od 1.
  $n = @($st.Dni).Count
  for ($i = $n; $i -ge 1; $i -= 7) {
    # szeroki zakres podpisu (tydzien), inaczej Chart lamie "28.08" na dwie linie
    $ob.AxisX.CustomLabels.Add([double]($i - 3), [double]($i + 3), $st.Dni[$i - 1].Dzien.ToString('dd.MM')) | Out-Null
  }
  return $ch
}

# Droga druga: wlasne slupki. Uzywana, gdy kontrolki Chart nie ma albo sie
# wywrocila, i ZAWSZE wtedy, gdy nie ma czego rysowac - wtedy w miejscu wykresu
# stoi zdanie, ze statystyka dopiero sie zbiera, a nie puste pole.
function Rysuj-Slupki($g, $rozmiar, $st) {
  $pedzle = @()
  $piora = @()
  try {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.Clear([System.Drawing.Color]::White)
    $szer = [float]$rozmiar.Width
    $wys = [float]$rozmiar.Height
    $szary = New-Object System.Drawing.SolidBrush($script:KolSzary); $pedzle += $szary
    $wSrodku = New-Object System.Drawing.StringFormat
    $wSrodku.Alignment = [System.Drawing.StringAlignment]::Center
    $wSrodku.LineAlignment = [System.Drawing.StringAlignment]::Center

    if ((-not $st) -or ($st.DniZDanymi -eq 0)) {
      $tekst = "Brak danych do wykresu."
      if ($st -and $st.Uwaga) { $tekst = $st.Uwaga }
      $g.DrawString($tekst, $script:CzZwykla, $szary, (New-Object System.Drawing.RectangleF(24, 0, ($szer - 48), $wys)), $wSrodku)
      return
    }

    $lewy = [float]54; $prawy = [float]6; $gora = [float]10; $dol = [float]22
    $w = $szer - $lewy - $prawy
    $h = $wys - $gora - $dol
    $skala = Skala-Wykresu $st
    $siatka = New-Object System.Drawing.Pen($script:KolSiatki); $piora += $siatka
    $os = New-Object System.Drawing.Pen($script:KolOsi); $piora += $os
    $doPrawej = New-Object System.Drawing.StringFormat
    $doPrawej.Alignment = [System.Drawing.StringAlignment]::Far
    $doPrawej.LineAlignment = [System.Drawing.StringAlignment]::Center
    foreach ($f in @(0.5, 1.0)) {
      $y = $gora + $h - [float]($h * $f)
      $g.DrawLine($siatka, [float]$lewy, [float]$y, [float]($lewy + $w), [float]$y)
      $g.DrawString((Etykieta-Osi ($skala * $f)), $script:CzMala, $szary, (New-Object System.Drawing.RectangleF(0, ($y - 9), ($lewy - 6), 18)), $doPrawej)
    }
    $g.DrawString("0", $script:CzMala, $szary, (New-Object System.Drawing.RectangleF(0, ($gora + $h - 9), ($lewy - 6), 18)), $doPrawej)

    $kolory = @{ Zwykle = $script:KolSlupek; Nieznane = $script:KolNiezn; Nadrabianie = $script:KolNadrab }
    $pedzelDla = @{}
    foreach ($klucz in @($kolory.Keys)) {
      $p = New-Object System.Drawing.SolidBrush($kolory[$klucz]); $pedzle += $p; $pedzelDla[$klucz] = $p
    }
    $dni = @($st.Dni)
    $n = $dni.Count
    $slot = $w / $n
    $bw = [float][math]::Max(3, $slot * 0.62)
    for ($i = 0; $i -lt $n; $i++) {
      $d = $dni[$i]
      $x = [float]($lewy + $i * $slot + ($slot - $bw) / 2)
      $podstawa = $gora + $h
      foreach ($pole in @("Zwykle", "Nieznane", "Nadrabianie")) {
        $ile = [double]$d.$pole / $script:WykresDz
        if ($ile -le 0) { continue }
        $hh = [float]($h * $ile / $skala)
        if ($hh -lt 1) { $hh = [float]1 }   # dzien z kosztem ma byc widoczny, choc maly
        $g.FillRectangle($pedzelDla[$pole], $x, [float]($podstawa - $hh), $bw, $hh)
        $podstawa = $podstawa - $hh
      }
      if ((($n - 1 - $i) % 7) -eq 0) {
        $g.DrawString($d.Dzien.ToString('dd.MM'), $script:CzMala, $szary,
          (New-Object System.Drawing.RectangleF(($x + $bw / 2 - 24), ($gora + $h + 3), 48, 16)), $wSrodku)
      }
    }
    $g.DrawLine($os, [float]$lewy, [float]($gora + $h), [float]($lewy + $w), [float]($gora + $h))

    if (Prog-Widoczny $st) {
      $y = $gora + $h - [float]($h * [double]$st.Prog / $script:WykresDz / $skala)
      $prog = New-Object System.Drawing.Pen($script:KolPilne); $piora += $prog
      $prog.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
      $g.DrawLine($prog, [float]$lewy, [float]$y, [float]($lewy + $w), [float]$y)
      $czerwony = New-Object System.Drawing.SolidBrush($script:KolPilne); $pedzle += $czerwony
      $nad = New-Object System.Drawing.StringFormat
      $nad.Alignment = [System.Drawing.StringAlignment]::Far
      $g.DrawString("tu zaczyna się drogo", $script:CzMala, $czerwony, (New-Object System.Drawing.RectangleF($lewy, ($y - 16), $w, 16)), $nad)
    }
  } catch {
    if (-not $script:RysowanieZawiodlo) { $script:RysowanieZawiodlo = $true; Zanotuj-Wywrotke "rysowanie wykresu" $_ }
  } finally {
    foreach ($p in $pedzle) { try { $p.Dispose() } catch { Notuj "nie zwolnilem pedzla wykresu" } }
    foreach ($p in $piora) { try { $p.Dispose() } catch { Notuj "nie zwolnilem piora wykresu" } }
  }
}

function Wstaw-Wykres($gospodarz, $st) {
  if ($st -and ($st.DniZDanymi -gt 0) -and $script:JestChart -and (-not $script:ChartZawiodl)) {
    try {
      $ch = Nowy-Chart $st
      $ch.Dock = [System.Windows.Forms.DockStyle]::Fill
      $gospodarz.Controls.Add($ch)
      return
    } catch {
      # Cisza jest zakazana: wywrotka kontrolki nie znika - idzie do dziennika
      # i do szczegolow (Opis-Rysownika), a okno rysuje slupki samo.
      $script:ChartZawiodl = $true
      $script:PowodBezChart = "kontrolka Chart się wywróciła: $($_.Exception.Message)"
      Zanotuj-Wywrotke "wykres przez kontrolke Chart - dalej rysuje slupki sam" $_
    }
  }
  $pb = New-Object System.Windows.Forms.PictureBox
  $pb.Dock = [System.Windows.Forms.DockStyle]::Fill
  $pb.BackColor = [System.Drawing.Color]::White
  $pb.Add_Paint({ param($nadawca, $e) Rysuj-Slupki $e.Graphics $nadawca.ClientSize $script:StatWykresu })
  $pb.Add_Resize({ param($nadawca, $e) $nadawca.Invalidate() })
  $gospodarz.Controls.Add($pb)
}

# --- odmalowanie -------------------------------------------------------------

function Odmaluj-Podtytul {
  if (-not $script:LPodtytul -or $script:LPodtytul.IsDisposed) { return }
  if ($script:Ladowanie) {
    $script:LPodtytul.ForeColor = $script:KolSzary
    $script:LPodtytul.Text = "Wczytuję dane - postęp krok po kroku poniżej."
    return
  }
  if ($script:Licze) {
    $script:LPodtytul.ForeColor = $script:KolSzary
    if ($script:DaneCzas) {
      $script:LPodtytul.Text = "Przeliczam... na razie widzisz liczby sprzed $($script:DaneCzas.ToString('HH:mm'))."
    } else {
      $script:LPodtytul.Text = "Przeliczam, to potrwa kilka sekund..."
    }
    return
  }
  if ($script:DaneBlad) {
    $script:LPodtytul.ForeColor = $script:KolUwaga
    if ($script:DaneCzas) {
      $script:LPodtytul.Text = "Przeliczenie się nie udało - liczby są sprzed $($script:DaneCzas.ToString('HH:mm'))."
    } else {
      $script:LPodtytul.Text = "Przeliczenie się nie udało i nie mam żadnych liczb."
    }
    return
  }
  $script:LPodtytul.ForeColor = $script:KolSzary
  $kiedy = "przed chwilą"
  if ($script:DaneCzas) { $kiedy = Kiedy-Ludzko $script:DaneCzas }
  $script:LPodtytul.Text = "Sprawdzone $kiedy. Liczby odświeżają się same w tle co $Minut min."
}

function Karta-Problemu($p) {
  $k = Pionowy $script:SzerKarty
  $k.Padding = New-Object System.Windows.Forms.Padding(22, 14, 22, 14)
  $k.Margin  = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)
  $kolor = $script:KolUwaga
  $k.BackColor = $script:TloUwaga
  $podpis = "Do sprawdzenia"
  if ($p.Waga -eq "pilne") { $kolor = $script:KolPilne; $k.BackColor = $script:TloPilne; $podpis = "Wymaga działania" }
  elseif ($p.Waga -eq "info") { $podpis = "Dla informacji - nic nie trzeba robić" }
  $szer = $script:SzerKarty - 44
  $k.Controls.Add((Etykieta $podpis.ToUpper() $script:CzMalaGruba $kolor))
  $k.Controls.Add((Etykieta-Zawijana $p.Tytul $script:CzGruba $kolor $szer))
  if ($p.Porada) {
    $k.Controls.Add((Etykieta-Zawijana $p.Porada $script:CzZwykla $script:KolTekst $szer))
  }
  return $k
}

function Odmaluj-Problemy {
  if (-not $script:PanelProblemy -or $script:PanelProblemy.IsDisposed) { return }
  Wyczysc-Panel $script:PanelProblemy
  # Bez @() - patrz uwaga o "return ,$lista" w naglowku stan-nadzorcy.ps1.
  $script:Problemy = Zbierz-Problemy $script:Dane $script:Wywrotki $script:DaneBlad $script:DaneCzas
  if (@($script:Problemy).Count -eq 0) {
    # Niewidoczna kontrolka nie bierze udzialu w ukladaniu, wiec sekcja bez
    # problemow NIE ZOSTAWIA po sobie ani pustej ramki, ani odstepu.
    $script:PanelProblemy.Visible = $false
    return
  }
  foreach ($p in $script:Problemy) { $script:PanelProblemy.Controls.Add((Karta-Problemu $p)) }
  $script:PanelProblemy.Visible = $true
}

# Karta nauki z rozmow - na cala szerokosc, pod "Otwarcie sesji". Do 28.09.2026
# (P14) byla trzecim z trzech kafelkow; dwa pierwsze dublowaly karte otwarcia
# sesji i zniknely.
# P17 (28.09.2026): duza liczba to TOKENY dziennie. Uzytkownik: "te 20%, to nie
# wiem czego" - procent otwarcia okna rozmowy nie ma sensu przy koszcie
# dziennym. Pod liczba jedno zdanie porownania z calym dziennym zuzyciem
# tokenow w rozmowach z Claude ($zu = Zuzycie-Dzienne) albo, gdy go nie ma,
# "nie mam z czym porownac, bo ..." na zolto - nigdy zero.
function Kafelek-Liczby($t, $zu) {
  $k = Nowa-Karta $script:SzerKarty
  # bez odstepu pod spodem - wykres kosztu nauki jest dalszym ciagiem tej karty (P15)
  $k.Margin = New-Object System.Windows.Forms.Padding(0)
  $szer = $script:SzerKarty - 44
  $k.Controls.Add((Etykieta-Zawijana $t.Naglowek $script:CzGruba $script:KolTekst $szer))
  if ($null -ne $t.Liczba) {
    $tn = Teksty-Nauki $t $zu
    $w = Poziomy
    $w.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $duza = Etykieta $tn.Duza $script:CzDuza $script:KolTekst
    $duza.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
    $w.Controls.Add($duza)
    $jed = Etykieta $tn.Jednostka $script:CzZwykla $script:KolSzary
    $jed.Margin = New-Object System.Windows.Forms.Padding(0, 14, 0, 0)
    $w.Controls.Add($jed)
    $k.Controls.Add($w)
    # Dopisek "z jakich dni i czy zalegle" - kolor tylko wtedy, gdy niesie
    # znaczenie (czerwony: zwykly dzien nad progiem; zolty: zalegle rozmowy
    # albo dni nieznane); zwykly dzien dostaje neutralna szara plakietke.
    if ($t.Znacznik) {
      $kol = $script:KolSzary; $tlo = $script:TloZnacz
      if ($t.ZnacznikWaga -eq "pilne") { $kol = $script:KolPilne; $tlo = $script:TloPilne }
      elseif ($t.ZnacznikWaga) { $kol = $script:KolUwaga; $tlo = $script:TloUwaga }
      $z = Etykieta $t.Znacznik $script:CzMalaGruba $kol
      $z.UseMnemonic = $false
      $z.BackColor = $tlo
      $z.Padding = New-Object System.Windows.Forms.Padding(6, 2, 6, 3)
      $z.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 2)
      # P17: w wierszu duzej liczby, gdy sie miesci - karta dostala zdanie
      # porownania i drobny druk, a okno ma sie miescic bez przewijania.
      # Gdy sie nie miesci, osobna linia jak dotad (wiersz sie nie zawija).
      if (($w.PreferredSize.Width + 14 + $z.PreferredSize.Width) -le $szer) {
        $z.Margin = New-Object System.Windows.Forms.Padding(14, 12, 0, 0)
        $w.Controls.Add($z)
      } else {
        $k.Controls.Add($z)
      }
    }
    # Porownanie z calym dniem - zwykla czcionka, bo to odpowiedz na "duzo czy
    # malo?"; zolte, gdy porownania nie ma.
    $kolP = $script:KolTekst
    if (-not $tn.PorownanieJest) { $kolP = $script:KolUwaga }
    $por = Etykieta-Zawijana $tn.Porownanie $script:CzZwykla $kolP $szer
    $por.UseMnemonic = $false
    $por.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)
    $k.Controls.Add($por)
    if ($tn.Drobny) {
      $dd = Etykieta-Zawijana $tn.Drobny $script:CzMala $script:KolSzary $szer
      $dd.UseMnemonic = $false
      $dd.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
      $k.Controls.Add($dd)
    }
  } else {
    # Zero znaczyloby "nic nie kosztuje" - a my po prostu nie wiemy. Mowimy to
    # wprost i podajemy powod, zamiast pokazac liczbe, ktorej nie mamy.
    $k.Controls.Add((Etykieta "nie wiem" $script:CzDuza $script:KolUwaga))
    $k.Controls.Add((Etykieta-Zawijana $t.Powod $script:CzMala $script:KolUwaga $szer))
  }
  $opis = Etykieta-Zawijana $t.Opis $script:CzMala $script:KolSzary $szer
  $opis.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)
  $k.Controls.Add($opis)
  return $k
}

function Odmaluj-Liczby {
  if (-not $script:PanelLiczby -or $script:PanelLiczby.IsDisposed) { return }
  Wyczysc-Panel $script:PanelLiczby
  $r = $null; $c = $null
  if ($script:Dane) { $r = $script:Dane.Rachunek; $c = $script:Dane.Cykl }
  $t = $null
  try { $t = Liczba-Nauki $r $c }
  catch { Zanotuj-Wywrotke "zlozenie kosztu nauki" $_ }
  $script:StatSama = (-not $t)
  if (-not $t) {
    $script:PanelLiczby.Controls.Add((Etykieta-Zawijana (
      "Kosztu nauki jeszcze nie ma - nie udało się go złożyć. Powód jest w zakładce Szczegóły.") $script:CzZwykla $script:KolUwaga $script:SzerTresc))
    return
  }
  $script:PanelLiczby.Controls.Add((Kafelek-Liczby $t $script:Zuzycie))
}

function Liczba-Boczna($panel, [string]$podpis, [string]$wartosc) {
  $panel.Controls.Add((Etykieta $podpis $script:CzMala $script:KolSzary))
  $w = Etykieta $wartosc $script:CzSrednia $script:KolTekst
  $w.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
  $panel.Controls.Add($w)
}

function Znak-Legendy($panel, $kolor, [string]$napis) {
  $kw = New-Object System.Windows.Forms.Panel
  $kw.Size = New-Object System.Drawing.Size(10, 10)
  $kw.BackColor = $kolor
  $kw.Margin = New-Object System.Windows.Forms.Padding(0, 5, 6, 0)
  $panel.Controls.Add($kw)
  $t = Etykieta $napis $script:CzMala $script:KolSzary
  $t.Margin = New-Object System.Windows.Forms.Padding(0, 2, 14, 0)
  $panel.Controls.Add($t)
}

function Odmaluj-Statystyke {
  if (-not $script:KartaStat -or $script:KartaStat.IsDisposed) { return }
  Wyczysc-Panel $script:KartaStat
  $r = $null
  if ($script:Dane) { $r = $script:Dane.Rachunek }
  $st = $null
  try { $st = Statystyka-Okna $r }
  catch { Zanotuj-Wywrotke "statystyka nauki do okna" $_ }
  $script:StatWykresu = $st
  $szer = $script:SzerKarty - 44
  Ustaw-Miare-Wykresu

  $script:KartaStat.Controls.Add((Etykieta "Koszt czytania rozmów - ostatnie 30 dni" $script:CzZwyklaGruba $script:KolTekst))
  if (-not $st) {
    $script:KartaStat.Controls.Add((Etykieta-Zawijana "Statystyki nie udało się złożyć - powód jest w dzienniku nadzorcy." $script:CzZwykla $script:KolUwaga $szer))
    return
  }

  $wiersz = Poziomy
  $wiersz.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 4)
  $gospodarz = New-Object System.Windows.Forms.Panel
  # 130 px, nie 160 (P17): karta nauki dostala zdanie porownania i drobny druk,
  # a okno ma sie dalej miescic na ekranie bez przewijania.
  $gospodarz.Size = New-Object System.Drawing.Size(($szer - 340), 130)
  $gospodarz.Margin = New-Object System.Windows.Forms.Padding(0)
  $gospodarz.BackColor = [System.Drawing.Color]::White
  Wstaw-Wykres $gospodarz $st
  $wiersz.Controls.Add($gospodarz)

  # Liczby po prawej w tej samej mierze, co os: tokeny (P17). Dokladna liczba
  # drobno w podpisie, zaokraglona duzo.
  $boczne = Pionowy 300
  $boczne.Margin = New-Object System.Windows.Forms.Padding(40, 0, 0, 0)
  $boczna = {
    param([string]$podpis, $n, [string]$brak)
    if ($null -eq $n) { Liczba-Boczna $boczne $podpis $brak; return }
    Liczba-Boczna $boczne "$podpis · dokładnie $(Liczba-Ludzka $n)" "$(Tokeny-Okolo $n) tokenów"
  }
  # Trzy liczby, nie cztery (P15): srednia na dzien nauki powtarzala sume
  # podzielona przez dni i nie mowila laikowi nic nowego - stoi w wydruku -Raport.
  & $boczna "Ostatnie 7 dni" $st.Suma7 "brak danych"
  & $boczna "Ostatnie $($st.OknoDni) dni" $st.Suma30 "brak danych"
  if (($null -ne $st.Typowy) -and ($st.TypowychDni -gt 0)) {
    & $boczna "Zwykły dzień (z $($st.TypowychDni) $(Odmiana $st.TypowychDni 'dnia' 'dni' 'dni'))" $st.Typowy ""
  } else {
    Liczba-Boczna $boczne "Zwykły dzień" "jeszcze nie wiem"
  }
  $wiersz.Controls.Add($boczne)
  $script:KartaStat.Controls.Add($wiersz)

  if ($st.DniZDanymi -gt 0) {
    $leg = Poziomy
    $leg.Margin = New-Object System.Windows.Forms.Padding(54, 0, 0, 2)
    Znak-Legendy $leg $script:KolSlupek "zwykły dzień: rozmowy z poprzedniego dnia"
    Znak-Legendy $leg $script:KolNadrab "rozmowy z kilku dni naraz"
    if (@(@($st.Dni) | Where-Object { $_.Nieznane -gt 0 }).Count -gt 0) { Znak-Legendy $leg $script:KolNiezn "nie wiadomo, z których dni" }
  }
  # Prog "tu zaczyna sie drogo" pelnym zdaniem - w wierszu legendy, gdy sa
  # slupki (jedna linia mniej), inaczej osobno. Czerwony tylko wtedy, gdy
  # czerwona linia stoi na wykresie; gdy prog jest daleko ponad slupkami,
  # zdanie jest szare - to informacja, nie alarm.
  if ($null -ne $st.Prog) {
    $zp = Zdanie-Progu $st $script:Zuzycie
    $kolP = $script:KolSzary
    if ((Prog-Widoczny $st) -and ($st.DniZDanymi -gt 0)) { $zp = "- - czerwona linia: tu zaczyna się drogo. $zp"; $kolP = $script:KolPilne }
    elseif ($st.DniZDanymi -gt 0) { $zp = "$zp Słupki są daleko poniżej." }
    if ($st.DniZDanymi -gt 0) {
      $u = Etykieta-Zawijana $zp $script:CzMala $kolP ($szer - 54 - $leg.PreferredSize.Width - 10)
      $u.Margin = New-Object System.Windows.Forms.Padding(10, 2, 0, 0)
      $leg.Controls.Add($u)
    } else {
      $u = Etykieta-Zawijana $zp $script:CzMala $kolP $szer
      $u.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
      $script:KartaStat.Controls.Add($u)
    }
  }
  if ($st.DniZDanymi -gt 0) { $script:KartaStat.Controls.Add($leg) }
  # Uwaga o zbierajacej sie statystyce stoi pod wykresem ZAWSZE, gdy danych jest
  # malo - takze wtedy, gdy w samym wykresie jest juz jej tresc (bez danych).
  if ($st.Uwaga -and ($st.DniZDanymi -gt 0)) {
    $u = Etykieta-Zawijana $st.Uwaga $script:CzMala $script:KolSzary $szer
    $u.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    $script:KartaStat.Controls.Add($u)
  }
}

# Wiersz karty stanu: "Nauka z rozmow: ostatnio dzis o 09:12" rozdzielone na
# dwie kolumny - co (szare) i jak (czarne). Linie przychodza gotowe z Linie-Stanu.
function Wiersz-Stanu([string]$linia, $kolorWartosci) {
  $w = Poziomy
  $w.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 5)
  $szer = $script:SzerKarty - 44
  $i = $linia.IndexOf(": ")
  if ($i -gt 0) {
    $e = Etykieta-Zawijana $linia.Substring(0, $i) $script:CzZwykla $script:KolSzary $script:SzerEtykiety
    $e.MinimumSize = New-Object System.Drawing.Size($script:SzerEtykiety, 0)
    $w.Controls.Add($e)
    $w.Controls.Add((Etykieta-Zawijana (Z-Wielkiej $linia.Substring($i + 2)) $script:CzZwykla $kolorWartosci ($szer - $script:SzerEtykiety)))
  } else {
    $w.Controls.Add((Etykieta-Zawijana $linia $script:CzZwykla $kolorWartosci $szer))
  }
  return $w
}

function Odmaluj-Stan {
  if (-not $script:PanelStan -or $script:PanelStan.IsDisposed) { return }
  Wyczysc-Panel $script:PanelStan
  $tyt = Etykieta "Stan" $script:CzGruba $script:KolTekst
  $tyt.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
  $script:PanelStan.Controls.Add($tyt)
  if ((Ile-Wymaga-Uwagi $script:Problemy) -eq 0) {
    $ok = Etykieta "Wszystko gra - nic nie wymaga Twojej uwagi." $script:CzZwyklaGruba $script:KolDobrze
    $ok.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
    $script:PanelStan.Controls.Add($ok)
  }
  $linie = @()
  if ($script:Dane) {
    try { $linie = Linie-Stanu $script:Dane.Wersja $script:Dane.Cykl $script:Dane.Przeliczanie }
    catch { Zanotuj-Wywrotke "zlozenie linii stanu" $_ }
  }
  foreach ($l in $linie) { $script:PanelStan.Controls.Add((Wiersz-Stanu $l $script:KolTekst)) }
  Dodaj-Zmiany-Pamieci
}

# "Pamiec dzis: 2 zmiany" jedna linia, a obok odnosnik [pokaz zmiany], ktory
# rozwija linie z identyfikatorami i zdanie, jak cofnac. Rozwijanie tylko
# przelacza widocznosc - nie przebudowuje panelu, bo kontrolka zwalniana we
# wlasnej procedurze klikniecia potrafi wywrocic WinForms.
function Dodaj-Zmiany-Pamieci {
  $script:PanelZmian = $null
  $script:LinkZmian = $null
  $szer = $script:SzerKarty - 44
  $pz = $null
  if ($script:Dane) { $pz = $script:Dane.Pamiec }
  $o = $null
  try { $o = Opis-Zmian-Pamieci $pz }
  catch { Zanotuj-Wywrotke "zlozenie zmian w pamieci" $_ }
  if (-not $o) {
    $script:PanelStan.Controls.Add((Wiersz-Stanu "Pamięć: nie udało się złożyć listy zmian - powód jest w dzienniku nadzorcy." $script:KolUwaga))
    return
  }
  $kolor = $script:KolTekst
  if ($o.Uwaga) { $kolor = $script:KolUwaga }
  if (@($o.Zmiany).Count -eq 0) {
    $script:PanelStan.Controls.Add((Wiersz-Stanu $o.Linia $kolor))
    return
  }

  $wiersz = Wiersz-Stanu $o.Linia $kolor
  $script:LinkZmian = New-Object System.Windows.Forms.LinkLabel
  $script:LinkZmian.AutoSize = $true
  $script:LinkZmian.Font = $script:CzZwykla
  $script:LinkZmian.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
  $wiersz.Controls.Add($script:LinkZmian)
  $script:PanelStan.Controls.Add($wiersz)

  $script:PanelZmian = Pionowy ($szer - $script:SzerEtykiety)
  $script:PanelZmian.Margin = New-Object System.Windows.Forms.Padding($script:SzerEtykiety, 0, 0, 4)
  foreach ($z in $o.Zmiany) {
    $script:PanelZmian.Controls.Add((Etykieta-Zawijana $z $script:CzMala $script:KolTekst ($szer - $script:SzerEtykiety)))
  }
  if ($o.Porada) {
    $p = Etykieta-Zawijana $o.Porada $script:CzZwykla $script:KolTekst ($szer - $script:SzerEtykiety)
    $p.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    $script:PanelZmian.Controls.Add($p)
  }
  $script:PanelStan.Controls.Add($script:PanelZmian)
  Ustaw-Rozwiniecie-Zmian

  $script:LinkZmian.Add_LinkClicked({
    $script:ZmianyRozwiniete = -not $script:ZmianyRozwiniete
    # Okno nie rosnie od rozwiniecia (P21) - Przeglad sie przewija.
    Ustaw-Rozwiniecie-Zmian
  })
}

function Ustaw-Rozwiniecie-Zmian {
  if (-not $script:PanelZmian -or $script:PanelZmian.IsDisposed) { return }
  $script:PanelZmian.Visible = $script:ZmianyRozwiniete
  if ($script:LinkZmian -and -not $script:LinkZmian.IsDisposed) {
    if ($script:ZmianyRozwiniete) { $script:LinkZmian.Text = "ukryj zmiany" }
    else { $script:LinkZmian.Text = "pokaż zmiany" }
  }
}

function Odmaluj-Przyciski {
  if (-not $script:BCykl -or $script:BCykl.IsDisposed) { return }
  $n = Napisy-Przyciskow $script:Dane $script:Zuzycie
  $script:BAktualizuj.Text = $n.Aktualizuj
  $script:LAktualizuj.Text = $n.AktualizujOpis
  $script:BCykl.Text       = $n.Cykl
  $script:LCykl.Text       = $n.CyklOpis
  $script:BCykl.Enabled    = $n.CyklWlaczony
}

# DOPASUJ-WYSOKOSC USUNIETE (P21, 30.09.2026). Dobieralo wysokosc okna pod tresc
# Przegladu po KAZDYM odmalowaniu - a tresc rosla w miare dochodzenia danych, wiec
# okno wstawalo w 1089 px (puste karty) i po kilku sekundach skakalo do 1347 px,
# przesuwajac sie w gore. Teraz wysokosc liczy sie raz, przy budowie okna
# (Wysokosc-Okna), a Przeglad, gdy sie nie miesci, przewija sie w miejscu.

function Odmaluj-Okno {
  if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
  # Przewiniecie przezywa odmalowanie - ciche odswiezenie w tle nie ma prawa
  # wyrzucic czytajacego na gore.
  $przewiniecie = 0
  try { if ($script:WidokPrzeglad) { $przewiniecie = -$script:WidokPrzeglad.AutoScrollPosition.Y } }
  catch { Zanotuj-Wywrotke "odczyt przewiniecia przegladu" $_ }
  $script:DoOdmalowania["przeglad"] = $false
  $script:Okno.SuspendLayout()
  try {
    Odmaluj-Podtytul
    Odmaluj-Werdykt
    Odmaluj-Problemy
    Odmaluj-Start
    Odmaluj-Liczby
    Odmaluj-Statystyke
    Odmaluj-Stan
    Odmaluj-Przyciski
  } catch {
    Zanotuj-Wywrotke "odmalowanie okna" $_
    if ($script:LPodtytul -and -not $script:LPodtytul.IsDisposed) {
      $script:LPodtytul.ForeColor = $script:KolPilne
      $script:LPodtytul.Text = "NIE UDAŁO SIĘ ZŁOŻYĆ OKNA: $($_.Exception.Message)"
    }
  } finally {
    $script:Okno.ResumeLayout($true)
  }
  if ($przewiniecie -gt 0) {
    try { $script:WidokPrzeglad.AutoScrollPosition = New-Object System.Drawing.Point(0, $przewiniecie) }
    catch { Zanotuj-Wywrotke "przywrocenie przewiniecia przegladu" $_ }
  }
}

# --- dane dla okna -----------------------------------------------------------

function Pokaz-Karty-Szczegolow($karty) {
  $p = $script:ListaSzczegolow
  if (-not $p -or $p.IsDisposed) { return }
  $p.SuspendLayout()
  try {
    Wyczysc-Panel $p
    foreach ($k in @($karty)) { $p.Controls.Add($k) }
  } finally { $p.ResumeLayout($true) }
  try { $script:WidokSzczegoly.AutoScrollPosition = New-Object System.Drawing.Point(0, 0) }
  catch { Zanotuj-Wywrotke "przewiniecie szczegolow na gore" $_ }
}

# Samo rysowanie - rozbicie liczy krok w tle "rozbicie" (P21), a do czasu, az
# bedzie, nad zakladka stoi ekran ladowania.
function Napelnij-Szczegoly {
  if (-not $script:ListaSzczegolow -or $script:ListaSzczegolow.IsDisposed) { return }
  if ($null -eq $script:Rozbicie) { return }
  $script:DoOdmalowania["szczegoly"] = $false
  try {
    $karty = @()
    foreach ($s in (Sekcje-Szczegolow $script:Dane $script:Wywrotki $script:Rozbicie $script:Start)) { $karty += (Karta-Sekcji $s) }
    Pokaz-Karty-Szczegolow $karty
  } catch {
    Zanotuj-Wywrotke "zlozenie szczegolow" $_
    Pokaz-Karty-Szczegolow @(Karta-Komunikatu "Nie udało się złożyć szczegółów" @("$($_.Exception.Message)", "Pełny ślad jest w dzienniku nadzorcy.") $script:KolPilne)
  }
}

# --- warstwy pamieci -----------------------------------------------------------
# Wszystko o warstwach pochodzi z Warstwy-Pamieci (narzedzia\koszt-pamieci.ps1
# -Warstwy) - okno nie zna zadnej sciezki samo z siebie. Samo tylko CZYTA plik
# wybranej warstwy do podgladu i niczego nie zapisuje.

$KOLEJNOSC_KIEDY = @("start", "wiadomosc", "zadanie", "nieuzywane")

function Kiedy-Po-Ludzku([string]$k) {
  switch ($k) {
    "start"      { return "Raz, przy otwarciu okna rozmowy" }
    "wiadomosc"  { return "Przy każdej wiadomości" }
    "zadanie"    { return "Tylko na żądanie" }
    "nieuzywane" { return "Nieużywane - nikt ich nie wczytuje" }
  }
  return "Inne ($k)"
}

function Trwalosc-Po-Ludzku([string]$t) {
  switch ($t) {
    "stala"      { return "stała" }
    "tymczasowa" { return "tymczasowa" }
    "mieszana"   { return "stała + tymcz." }
  }
  return "$t"
}

function Stan-Po-Ludzku([string]$s) {
  switch ($s) {
    "jest"       { return "jest" }
    "pusty"      { return "pusta" }
    "brak"       { return "BRAK" }
    "blad"       { return "BŁĄD ODCZYTU" }
    "nieaktywna" { return "teraz nieaktywna" }
  }
  return "$s"
}

function Rozmiar-Ludzki($bajty) {
  if ($null -eq $bajty) { return "rozmiar nieznany" }
  if ($bajty -lt 1024)    { return "$bajty B" }
  if ($bajty -lt 1048576) { return "$([math]::Round($bajty / 1024, 1)) KB" }
  return "$([math]::Round($bajty / 1048576, 1)) MB"
}

# Kolumna "Rozmiar": liczba znakow, a gdy jej nie ma - krotko, dlaczego nie ma.
# Brak pliku ma byc widoczny w samej liscie, nie dopiero po kliknieciu.
function Rozmiar-Warstwy($wa) {
  switch ("$($wa.Stan)") {
    "brak" {
      if ($wa.Rodzaj -eq "katalog") { return "BRAK KATALOGU" }
      if (($wa.Rodzaj -eq "podwarstwa") -and $wa.Istnieje) { return "BRAK SEKCJI" }
      return "BRAK PLIKU"
    }
    "blad"       { return "BŁĄD ODCZYTU" }
    "pusty"      { return "pusta" }
    "nieaktywna" { return "teraz nic" }
  }
  if ($wa.Rodzaj -eq "katalog") { return "$(@($wa.Pliki).Count) plików" }
  if ($wa.Rodzaj -eq "baza")    { return (Rozmiar-Ludzki $wa.Bajty) }
  if ($null -ne $wa.Znaki)      { return "$(Liczba-Ludzka $wa.Znaki) zn." }
  if ($null -ne $wa.Limit)      { return "do $(Liczba-Ludzka $wa.Limit) zn." }
  return "nieznany"
}

# Ten sam rozmiar pelnym zdaniem, z jednostka - do podgladu.
function Rozmiar-Opisowy($wa) {
  if ($wa.Rodzaj -eq "baza") { return (Rozmiar-Ludzki $wa.Bajty) + " (bazy nie liczy się w znakach)" }
  if ($wa.Rodzaj -eq "katalog") { return "$(@($wa.Pliki).Count) plików" }
  if ($null -ne $wa.Znaki) {
    $t = "$(Liczba-Ludzka $wa.Znaki) znaków"
    if ($null -ne $wa.Tokeny) {
      # P15: tokeny takze jako procent jednego otwarcia sesji Claude Code.
      # Warstwy Codeksa bez procentu - jego otwarcia sesji nikt nie mierzy.
      $js = ""
      if ("$($wa.Nazwa)" -notmatch 'tylko Codex') {
        $o = $null
        try { if ($script:Start) { $o = Opis-Startu $script:Start } } catch { Zanotuj-Wywrotke "opis otwarcia okna rozmowy do warstwy" $_ }
        $js = Jak-Sesji $wa.Tokeny $o
      }
      if ($js) { $t += " (~$(Liczba-Ludzka $wa.Tokeny) tokenów, $js)" }
      else { $t += " (~$(Liczba-Ludzka $wa.Tokeny) tokenów)" }
    }
    return $t
  }
  if ($null -ne $wa.Limit) { return "do $(Liczba-Ludzka $wa.Limit) znaków, za każdym razem inna treść" }
  return "nieznany"
}

# Jedno zdanie po ludzku nad lista. KAZDA liczba w nim odnosi sie do tej samej
# podstawy - warstw glownych (bez podwarstw i pojedynczych plikow wiedzy) - i kazdy
# podzial sumuje sie do ich liczby. Do 2026-09-25 "kiedy" liczylo sie od warstw
# glownych, a "stala/tymczasowa" od podwarstw: 12 warstw, a stalych i tymczasowych
# razem 18 - dla czlowieka sprzecznosc. Warstwa, ktorej podwarstwy sa roznej
# trwalosci (globalny CLAUDE.md, katalog wiedzy), liczy sie jako mieszana i zdanie
# mowi wprost, co w niej jest tymczasowe.
function Zdanie-Warstw($dw) {
  $wszystkie = @($dw.Warstwy)
  $glowne = @($wszystkie | Where-Object { -not $_.Rodzic })
  $ile = $glowne.Count
  $czesci = @()
  foreach ($k in $KOLEJNOSC_KIEDY) {
    $n = @($glowne | Where-Object { $_.Kiedy -eq $k }).Count
    switch ($k) {
      "start"      { $czesci += "$n przy otwarciu okna rozmowy" }
      "wiadomosc"  { $czesci += "$n przy każdej wiadomości" }
      "zadanie"    { $czesci += "$n tylko na żądanie" }
      "nieuzywane" { if ($n -gt 0) { $czesci += "$n $(Odmiana $n 'nieużywana' 'nieużywane' 'nieużywanych')" } }
    }
  }
  # "kiedy" spoza znanych czterech tez musi sie pokazac - inaczej suma sie nie zgodzi
  $inne = @($glowne | Where-Object { $KOLEJNOSC_KIEDY -notcontains "$($_.Kiedy)" }).Count
  if ($inne -gt 0) { $czesci += "$inne $(Odmiana $inne 'inna' 'inne' 'innych')" }
  $z = "$ile $(Odmiana $ile 'warstwa' 'warstwy' 'warstw') pamięci: " + ($czesci -join ", ") + "."

  # Trwalosc warstwy glownej: jej wlasna, a gdy ma podwarstwy roznej trwalosci - mieszana.
  $st = 0; $tm = 0; $nz = 0
  $mieszane = @()
  foreach ($g in $glowne) {
    $dzieci = @($wszystkie | Where-Object { "$($_.Rodzic)" -eq "$($g.Id)" })
    $rodzaje = @($dzieci | ForEach-Object { "$($_.Trwalosc)" } | Select-Object -Unique)
    $tr = "$($g.Trwalosc)"
    if ($rodzaje.Count -gt 1) { $tr = "mieszana" }
    switch ($tr) {
      "stala"      { $st++ }
      "tymczasowa" { $tm++ }
      "mieszana" {
        $tymcz = @($dzieci | Where-Object { $_.Trwalosc -eq "tymczasowa" } | ForEach-Object { "$($_.Nazwa)" })
        if ($tymcz.Count -gt 0) { $mieszane += "$($g.Nazwa) - tymczasowe w niej tylko: $($tymcz -join ', ')" }
        else { $mieszane += "$($g.Nazwa)" }
      }
      default { $nz++ }
    }
  }
  $trw = @()
  $trw += "$st $(Odmiana $st 'stała' 'stałe' 'stałych')"
  $trw += "$tm $(Odmiana $tm 'tymczasowa' 'tymczasowe' 'tymczasowych')"
  if ($mieszane.Count -gt 0) { $trw += "$($mieszane.Count) $(Odmiana $mieszane.Count 'mieszana' 'mieszane' 'mieszanych')" }
  if ($nz -gt 0) { $trw += "$nz o nieznanej trwałości" }
  $z += " Z tych $ile" + ": " + ($trw -join ", ")
  if ($mieszane.Count -gt 0) { $z += " (" + ($mieszane -join "; ") + ")" }
  $z += "."

  # Braki tez na tej samej podstawie: warstwa glowna liczy sie raz, gdy brakuje
  # jej samej albo ktorejkolwiek z jej podwarstw.
  $zle = 0
  foreach ($g in $glowne) {
    $rodzina = @($g) + @($wszystkie | Where-Object { "$($_.Rodzic)" -eq "$($g.Id)" })
    if (@($rodzina | Where-Object { ($_.Stan -eq "brak") -or ($_.Stan -eq "blad") }).Count -gt 0) { $zle++ }
  }
  if ($zle -gt 0) { $z += " Brak pliku albo błąd odczytu w $zle z $ile - zaznaczone na czerwono." }
  return $z
}

# Etykieta podsumowania rosnie razem z tekstem - uciety koniec zdania bylby
# ucieciem po cichu, a tego w tym projekcie nie wolno.
function Dopasuj-Etykiete($l) {
  if (-not $l -or $l.IsDisposed) { return }
  try {
    $szer = [math]::Max(200, $l.ClientSize.Width)
    $roz = [System.Windows.Forms.TextRenderer]::MeasureText($l.Text, $l.Font,
             (New-Object System.Drawing.Size($szer, 0)), [System.Windows.Forms.TextFormatFlags]::WordBreak)
    $l.Height = $roz.Height + 10
  } catch { Zanotuj-Wywrotke "dopasowanie wysokosci podsumowania warstw" $_ }
}

# Samo rysowanie - liste liczy krok w tle "warstwy" (P21).
function Napelnij-Warstwy {
  if (-not $script:ListaWarstw -or $script:ListaWarstw.IsDisposed) { return }
  if ($null -eq $script:DaneWarstw) { return }
  $script:DoOdmalowania["warstwy"] = $false
  $dw = $script:DaneWarstw
  $lv = $script:ListaWarstw
  $lv.BeginUpdate()
  try {
    $lv.Items.Clear()
    $lv.Groups.Clear()
    if ($dw.Powod) {
      $script:LWarstwy.ForeColor = $script:KolPilne
      $script:LWarstwy.Text = "NIE UDAŁO SIĘ ZEBRAĆ LISTY WARSTW: $($dw.Powod)"
      $script:PodgladWarstwy.Text = ("Lista warstw jest pusta, bo jej zebranie się nie udało - to nie znaczy, że warstw nie ma." + "`r`n`r`n" +
        "Powód: $($dw.Powod)" + "`r`n`r`n" + "Spróbuj ręcznie:" + "`r`n" +
        "powershell -ExecutionPolicy Bypass -File $(Join-Path $script:NadzZrodlo 'narzedzia\koszt-pamieci.ps1') -Warstwy")
      return
    }
    $grupy = @{}
    foreach ($k in $KOLEJNOSC_KIEDY) {
      $g = New-Object System.Windows.Forms.ListViewGroup -ArgumentList @((Kiedy-Po-Ludzku $k), [System.Windows.Forms.HorizontalAlignment]::Left)
      [void]$lv.Groups.Add($g)
      $grupy[$k] = $g
    }
    foreach ($wa in @($dw.Warstwy)) {
      $klucz = "$($wa.Kiedy)"
      if (-not $grupy.ContainsKey($klucz)) {
        # nieznany rodzaj "kiedy" nie znika - dostaje wlasna grupe
        $g = New-Object System.Windows.Forms.ListViewGroup -ArgumentList @((Kiedy-Po-Ludzku $klucz), [System.Windows.Forms.HorizontalAlignment]::Left)
        [void]$lv.Groups.Add($g)
        $grupy[$klucz] = $g
      }
      $nazwa = Po-Polsku "$($wa.Nazwa)"
      if ($wa.Rodzic) { $nazwa = "      › " + $nazwa }
      $it = New-Object System.Windows.Forms.ListViewItem -ArgumentList @(,[string]$nazwa)
      [void]$it.SubItems.Add([string](Trwalosc-Po-Ludzku $wa.Trwalosc))
      [void]$it.SubItems.Add([string](Rozmiar-Warstwy $wa))
      $it.Group = $grupy[$klucz]
      $it.Tag = $wa
      $it.ToolTipText = "$($wa.Nazwa) - $($wa.Sciezka)"
      if (($wa.Stan -eq "brak") -or ($wa.Stan -eq "blad")) { $it.ForeColor = $script:KolPilne }
      elseif (($wa.Kiedy -eq "nieuzywane") -or ($wa.Stan -eq "nieaktywna") -or ($wa.Stan -eq "pusty")) { $it.ForeColor = $script:KolSzary }
      [void]$lv.Items.Add($it)
    }
    $zd = Zdanie-Warstw $dw
    $script:LWarstwy.ForeColor = $script:KolTekst
    if (@($dw.Uwagi).Count -gt 0) {
      $zd += " UWAGA: " + (@($dw.Uwagi) -join "; ")
      $script:LWarstwy.ForeColor = $script:KolUwaga
    }
    $script:LWarstwy.Text = Po-Polsku $zd
    Pokaz-Info-Warstwy $null
    $pocz = @("Kliknij warstwę po lewej, żeby zobaczyć, co w niej jest.", "",
              "Lista zebrana: $($dw.Wygenerowano). Projekt: $($dw.Projekt).")
    if (@($dw.Uwagi).Count -gt 0) { $pocz += @("", "UWAGI:") + @($dw.Uwagi | ForEach-Object { "  - $_" }) }
    $script:PodgladWarstwy.Lines = [string[]]$pocz
  } finally {
    $lv.EndUpdate()
    Dopasuj-Etykiete $script:LWarstwy
  }
}

# Podglad tylko do odczytu. Nad trescia - dwie kolumny z tym, co o warstwie
# wiadomo (kiedy sie wczytuje, stan, rozmiar, kto pisze, sciezka); pod nimi sama
# tresc. Podwarstwa i ladunek hooka pokazuja tekst z koszt-pamieci.ps1 (kawalek
# pliku albo to, co hook naprawde wysyla), zwykly plik czytamy tutaj, katalog to
# lista plikow, bazy nie wczytujemy wcale.
function Pokaz-Info-Warstwy($wa) {
  $info = $script:PodgladInfo
  if (-not $info -or $info.IsDisposed) { return }
  $info.SuspendLayout()
  try {
    Wyczysc-Panel $info
    if (-not $wa) { return }
    $szer = [math]::Max(300, $info.Parent.ClientSize.Width - $info.Parent.Padding.Horizontal - 12)
    $t = Etykieta-Zawijana (Po-Polsku "$($wa.Nazwa)") $script:CzSrednia $script:KolTekst $szer
    $t.UseMnemonic = $false
    $t.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $info.Controls.Add($t)
    $st = "$($wa.Stan)"
    $kolSt = $script:KolDobrze
    if (($st -eq "brak") -or ($st -eq "blad")) { $kolSt = $script:KolPilne }
    elseif (($st -eq "nieaktywna") -or ($st -eq "pusty")) { $kolSt = $script:KolSzary }
    $e = 130
    $info.Controls.Add((Wiersz-Dwukolumnowy "Wczytuje się" (Kiedy-Po-Ludzku "$($wa.Kiedy)") $script:KolTekst $szer $e))
    $info.Controls.Add((Wiersz-Dwukolumnowy "Stan" (Stan-Po-Ludzku $st) $kolSt $szer $e))
    $info.Controls.Add((Wiersz-Dwukolumnowy "Rozmiar" (Rozmiar-Opisowy $wa) $script:KolTekst $szer $e))
    $info.Controls.Add((Wiersz-Dwukolumnowy "Trwałość" (Trwalosc-Po-Ludzku "$($wa.Trwalosc)") $script:KolTekst $szer $e))
    if ($wa.Zmieniony) { $info.Controls.Add((Wiersz-Dwukolumnowy "Zmieniony" "$($wa.Zmieniony)" $script:KolTekst $szer $e)) }
    $info.Controls.Add((Wiersz-Dwukolumnowy "Kto pisze" (Po-Polsku "$($wa.KtoPisze)") $script:KolTekst $szer $e))
    if ($wa.Opis) { $info.Controls.Add((Wiersz-Dwukolumnowy "Co to jest" (Po-Polsku "$($wa.Opis)") $script:KolTekst $szer $e)) }
    $info.Controls.Add((Wiersz-Dwukolumnowy "Ścieżka" "$($wa.Sciezka)" $script:KolSzary $szer $e))
    $kreska = New-Object System.Windows.Forms.Panel
    $kreska.Size = New-Object System.Drawing.Size($szer, 1)
    $kreska.BackColor = $script:KolRamki
    $kreska.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 8)
    $info.Controls.Add($kreska)
  } finally { $info.ResumeLayout($true) }
}

function Pokaz-Podglad($wa) {
  if (-not $script:PodgladWarstwy -or $script:PodgladWarstwy.IsDisposed -or -not $wa) { return }
  Pokaz-Info-Warstwy $wa
  $l = New-Object System.Collections.Generic.List[string]
  $st = "$($wa.Stan)"
  if (($st -eq "brak") -or ($st -eq "blad")) {
    $l.Add("NIE MA CZEGO POKAZAĆ: $($wa.Brak)")
  } elseif ($st -eq "nieaktywna") {
    $l.Add("Teraz nic się nie dokleja: $($wa.Brak)")
  } elseif ($st -eq "pusty") {
    $l.Add("Warstwa jest pusta: $($wa.Brak)")
  } elseif ($wa.Rodzaj -eq "baza") {
    $l.Add("Bazy nie wczytuję do podglądu - to $(Rozmiar-Ludzki $wa.Bajty) danych. Model sięga do niej narzędziami lore_search i lore_context.")
  } elseif ($wa.Rodzaj -eq "katalog") {
    $l.Add("Pliki w katalogu ($(@($wa.Pliki).Count)):")
    $l.Add("")
    foreach ($pl in @($wa.Pliki)) { $l.Add(("{0,-30} {1,10}  {2}" -f "$($pl.Nazwa)", (Rozmiar-Ludzki $pl.Bajty), "$($pl.Zmieniony)")) }
    $l.Add("")
    $l.Add("Pliki .md z tego katalogu są na liście po lewej - kliknij, żeby zobaczyć treść.")
  } elseif ("$($wa.Tresc)" -ne "") {
    if ($wa.Rodzaj -eq "ladunek") {
      $l.Add("Poniżej tekst, który hook naprawdę wysyła do modelu (pole additionalContext), a nie surowy JSON:")
      $l.Add("")
    }
    $l.Add(("$($wa.Tresc)" -replace '\r?\n', "`r`n"))
  } else {
    if ($wa.Rodzaj -eq "doklejka") {
      $l.Add("Samej doklejki nikt nie zapisuje - poniżej plik stanu, z którego korzysta:")
      $l.Add("")
    } elseif ($wa.Rodzaj -eq "ladunek") {
      $l.Add("Nie udało się wyciągnąć tekstu, który hook wysyła - poniżej surowy plik:")
      $l.Add("")
    }
    try {
      $l.Add(([System.IO.File]::ReadAllText("$($wa.Sciezka)", [System.Text.Encoding]::UTF8) -replace '\r?\n', "`r`n"))
    } catch {
      Zanotuj-Wywrotke "podglad warstwy $($wa.Sciezka)" $_
      $l.Add("NIE UDAŁO SIĘ ODCZYTAĆ PLIKU: $($_.Exception.Message)")
    }
  }
  $script:PodgladWarstwy.Text = ($l -join "`r`n")
  $script:PodgladWarstwy.SelectionStart = 0
  $script:PodgladWarstwy.ScrollToCaret()
}

# Przelaczenie widoku. Szczegoly napelniaja sie przy wejsciu - chyba ze stoi
# w nich odpowiedz na klikniecie (SzczegolyZajete), ktorej nie wolno podmienic.
# Od P21 dane kazdej zakladki licza sie w tle (Wejdz-Do-Widoku): brak danych z dzis
# = ekran ladowania, dane nieswieze = widok od razu i ciche odswiezenie. Nieudana
# proba liczy sie od nowa przy nastepnym wejsciu, zamiast zostawiac stary blad.
function Pokaz-Widok([string]$nazwa) {
  if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
  $script:Widok = $nazwa
  $szcz = ($nazwa -eq "szczegoly")
  $warst = ($nazwa -eq "warstwy")
  $skil = ($nazwa -eq "skille")
  $przeg = (-not ($szcz -or $warst -or $skil))
  $script:WidokSzczegoly.Visible = $szcz
  $script:WidokWarstwy.Visible = $warst
  $script:WidokSkille.Visible = $skil
  $script:WidokPrzeglad.Visible = $przeg
  Styl-Przelacznika $script:BPrzeglad $przeg
  Styl-Przelacznika $script:BSzczegoly $szcz
  Styl-Przelacznika $script:BWarstwy $warst
  Styl-Przelacznika $script:BSkille $skil
  Wejdz-Do-Widoku $nazwa
}

# ------------------------------------------------------------ zakladka Skille (P18)
# Dane liczy narzedzia\skille.ps1 -Tryb stan -Json (Stan-Skilli w stan-nadzorcy.ps1) -
# tutaj jest tylko wyglad i przyciski. Przyciski NIE czekaja na koniec operacji: skrypt
# idzie w tle bez okna, a zegar co 2 s zaglada do operacja.txt i odmalowuje zakladke.

$ZDANIE_BEZPIECZENSTWA = "Skille to instrukcje od zewnętrznych autorów. Aktualizują się same raz dziennie, wyłącznie z listy zaufanych źródeł poniżej - każda zmiana jest zapisana i da się ją cofnąć."

function Data-Krotko([string]$t) {
  $d = Data-Lub-Nic $t
  if (-not $d) { return "" }
  return $d.ToString('yyyy-MM-dd')
}

function Wersja-Krotko([string]$commit, [string]$data) {
  if (-not $commit) { return "nieznana" }
  $k = $commit.Substring(0, [math]::Min(7, $commit.Length))
  $d = Data-Krotko $data
  if ($d) { return "z $d (oznaczenie $k)" }
  return "oznaczenie $k"
}

# Stan skilla po ludzku: krotki napis na liste i kolor. Blad sprawdzenia wygrywa na
# liscie (czerwony), ale szczegoly mowia tez, co wiadomo z ostatniego udanego razu.
function Napis-Skilla($s) {
  $wstrzymany = @($s.cele | Where-Object { $_.wstrzymany }).Count -gt 0
  if ($s.blad) { return @("nie udało się sprawdzić", $script:KolPilne) }
  if ($s.dzisZaktualizowany -and $s.stan -eq "zgodny") { return @("nowa wersja pobrana dziś", $script:KolDobrze) }
  # Autor usunal skill - neutralnie (szaro): to nie usterka, kopia u Ciebie dziala.
  if ($s.stan -eq "usuniety") {
    if ($s.zainstalowany) { return @("autor go usunął - Twoja kopia działa", $script:KolSzary) }
    return @("autor go usunął", $script:KolSzary)
  }
  switch ("$($s.stan)") {
    "zgodny"    { return @("aktualny", $script:KolDobrze) }
    "starszy"   { if ($wstrzymany) { return @("cofnięty - nie aktualizuję sam", $script:KolSzary) }; return @("czeka nowsza wersja", $script:KolUwaga) }
    "zmieniony" { return @("zmieniony ręcznie - nie ruszam", $script:KolUwaga) }
    "brak"      { return @("nie zainstalowany", $script:KolSzary) }
    "nieznany"  { return @("jeszcze nie sprawdzony", $script:KolSzary) }
  }
  return @("$($s.stan)", $script:KolSzary)
}

function Zdanie-Stanu-Skilla($s) {
  $wstrzymany = @($s.cele | Where-Object { $_.wstrzymany }).Count -gt 0
  switch ("$($s.stan)") {
    "zgodny"    { return "Masz najnowszą wersję od autora." }
    "starszy"   {
      if ($wstrzymany) { return "Masz starszą wersję, bo cofnąłeś ostatnią aktualizację. Sam jej nie ponowię - kliknij `„Aktualizuj teraz`”, gdy zechcesz." }
      return "Masz starszą wersję od autora. Nowsza podmieni się sama przy najbliższym codziennym sprawdzeniu (z kopią starej) - albo kliknij `„Aktualizuj teraz`”." }
    "zmieniony" { return "Ktoś zmienił ten skill ręcznie - jego treść nie pasuje do żadnej wersji autora. Nie nadpisuję go sam. `„Aktualizuj teraz`” zapyta o zgodę, a Twoja wersja trafi do kopii." }
    "brak"      { return "Nie masz go zainstalowanego." }
    "nieznany"  { return "Jest na dysku, ale jeszcze go nie sprawdzałem - kliknij `„Sprawdź teraz`”." }
    "usuniety"  {
      $kiedy = Data-Krotko "$($s.usuniety.od)"
      $t = "Autor usunął ten skill ze swojego źródła$(if ($kiedy) { " (zauważone $kiedy)" }) - nowych wersji już nie będzie. To nie jest błąd."
      if ($s.zainstalowany) { return "$t Twoja kopia zostaje nietknięta i działa jak dotąd. Jeśli go nie potrzebujesz, kliknij `„Usuń u mnie`” - zrobię kopię zapasową, więc da się go przywrócić." }
      return "$t Nie masz go, a zainstalować się go już nie da."
    }
  }
  return "$($s.stan)"
}

function Opis-Celu($c) {
  switch ("$($c.stan)") {
    "brak"      { return "nie zainstalowany" }
    "zgodny"    { return "aktualny, wersja $(Wersja-Krotko $c.commit $c.data)" }
    "starszy"   { return "starsza wersja $(Wersja-Krotko $c.commit $c.data)$(if ($c.wstrzymany) { ' - cofnięty, wstrzymany' })" }
    "zmieniony" { return "zmieniony ręcznie" }
    "nieznany"  { return "jeszcze nie sprawdzony" }
  }
  return "$($c.stan)"
}

# Wiersz listy: nazwa i stan w pierwszej linii, opis zawiniety pod spodem. Caly
# wiersz jest klikalny (Tag = nazwa skilla); wybrany ma szare tlo. Wciety wzgledem
# naglowka grupy (P20) - widac, do ktorej grupy nalezy.
function Wiersz-Skilla($s, [int]$szer) {
  $t = New-Object System.Windows.Forms.TableLayoutPanel
  $t.ColumnCount = 2
  $t.RowCount = 2
  $t.AutoSize = $true
  $t.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
  $t.MinimumSize = New-Object System.Drawing.Size($szer, 0)
  $t.MaximumSize = New-Object System.Drawing.Size($szer, 0)
  $t.Padding = New-Object System.Windows.Forms.Padding(34, 7, 12, 7)
  $t.Margin = New-Object System.Windows.Forms.Padding(0)
  $t.BackColor = $script:TloKarty
  $t.Cursor = [System.Windows.Forms.Cursors]::Hand
  $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
  $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null
  $nazwa = "$($s.folder)"
  if ($s.robocza) { $nazwa += "  · wersja robocza autora" }
  $ln = Etykieta $nazwa $script:CzZwyklaGruba $script:KolTekst
  $ln.UseMnemonic = $false
  $ns = Napis-Skilla $s
  $ls = Etykieta $ns[0] $script:CzMalaGruba $ns[1]
  $ls.UseMnemonic = $false
  $ls.Anchor = [System.Windows.Forms.AnchorStyles]::Right
  $lo = Etykieta-Zawijana "$($s.opis)" $script:CzMala $script:KolSzary ($szer - 50)
  $lo.UseMnemonic = $false
  $t.Controls.Add($ln, 0, 0)
  $t.Controls.Add($ls, 1, 0)
  $t.Controls.Add($lo, 0, 1)
  $t.SetColumnSpan($lo, 2)
  foreach ($c in @($t, $ln, $ls, $lo)) {
    $c.Tag = "$($s.nazwa)"
    $c.Add_Click({ param($nadawca, $e) try { Wybierz-Skill "$($nadawca.Tag)" } catch { Zanotuj-Wywrotke "wybor skilla" $_ } })
  }
  # cienka kreska pod wierszem
  $t.Add_Paint({ param($nadawca, $e) try { $e.Graphics.DrawLine($script:PioroRamki, 32, $nadawca.Height - 1, $nadawca.Width - 12, $nadawca.Height - 1) } catch { if (-not $script:RamkaZawiodla) { $script:RamkaZawiodla = $true; Zanotuj-Wywrotke "kreska pod skillem" $_ } } })
  return $t
}

# GRUPY ZWIJANE (P20). Uzytkownik: "skille w apce powinny byc w grupach z mozliwoscia
# rozwiniecia, a nie od razu widoczny kazdy skill". Na starcie lista pokazuje same
# naglowki grup (zrodel); klikniecie naglowka rozwija grupe. Co jest rozwiniete, okno
# pamieta do zamkniecia ($script:GrupySkilli: id -> $true). Grupa z problemem ma
# czerwony pasek z lewej, grupa z nowsza wersja do pobrania - bursztynowy; reszta
# bez paska. Tak samo jak na liscie: kolor tylko tam, gdzie cos wymaga uwagi.

# Liczby grupy: ile skilli, ile masz, ile czeka nowsza wersja, ile ma problem (nie udalo
# sie sprawdzic albo pobrac), ile zmienionych recznie i ile autor usunal.
function Liczby-Grupy($z) {
  $sk = @($z.skille)
  return [pscustomobject]@{
    Ile = $sk.Count
    Masz = @($sk | Where-Object { ($_.stan -ne "brak") -and (($_.stan -ne "usuniety") -or $_.zainstalowany) }).Count
    Starsze = @($sk | Where-Object { $_.stan -eq "starszy" }).Count
    Problem = @($sk | Where-Object { $_.blad }).Count
    Zmienione = @($sk | Where-Object { $_.stan -eq "zmieniony" }).Count
    Usuniete = @($sk | Where-Object { $_.stan -eq "usuniety" }).Count
  }
}

# Opis grupy do naglowka - z danych zrodla ($z) albo recznie (grupa "spoza bazy").
function Grupa-Zrodla($z) {
  $g = [pscustomobject]@{
    Id = "$($z.id)"; Tytul = "$($z.nazwa)"; Opis = "$($z.opis)"; Liczby = ""; Napis = ""; KolorNapisu = $script:KolSzary
    Znacznik = $null; Blad = ""; Uwaga = ""; Rozwijalny = $true
  }
  if ($z.rodzaj -ne "skille") {
    $g.Rozwijalny = $false; $g.Uwaga = "$($z.uwaga)"; $g.Napis = "nic do instalowania"
    return $g
  }
  $l = Liczby-Grupy $z
  $cz = @("$($l.Ile) $(Odmiana $l.Ile 'skill' 'skille' 'skilli')", "masz $($l.Masz)", "nowsza wersja: $($l.Starsze)", "problem: $($l.Problem)")
  if ($l.Zmienione -gt 0) { $cz += "zmienione ręcznie: $($l.Zmienione)" }
  if ($l.Usuniete -gt 0) { $cz += "autor usunął: $($l.Usuniete)" }
  $g.Liczby = $cz -join "   ·   "
  if ($z.blad) {
    $g.Blad = "Nie udało się pobrać ($(Data-Krotko $z.sprawdzono)): $($z.blad)"
    $g.Napis = "błąd pobrania"; $g.KolorNapisu = $script:KolPilne; $g.Znacznik = $script:KolPilne
  } elseif ($l.Problem -gt 0) {
    $g.Napis = "problem: $($l.Problem)"; $g.KolorNapisu = $script:KolPilne; $g.Znacznik = $script:KolPilne
  } elseif ($l.Starsze -gt 0) {
    $g.Napis = "nowsza wersja: $($l.Starsze)"; $g.KolorNapisu = $script:KolUwaga; $g.Znacznik = $script:KolUwaga
  } else {
    $g.Napis = "w porządku"
  }
  return $g
}

function Naglowek-Grupy($g, [int]$szer) {
  $rozw = $g.Rozwijalny -and [bool]$script:GrupySkilli[$g.Id]
  $script:ZnacznikiGrup[$g.Id] = $g.Znacznik
  $t = New-Object System.Windows.Forms.TableLayoutPanel
  $t.ColumnCount = 2
  $t.RowCount = 4
  $t.AutoSize = $true
  $t.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
  $t.MinimumSize = New-Object System.Drawing.Size($szer, 0)
  $t.MaximumSize = New-Object System.Drawing.Size($szer, 0)
  $t.Padding = New-Object System.Windows.Forms.Padding(16, 10, 12, 10)
  $t.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 1)
  $t.BackColor = $script:TloZnacz
  if ($g.Rozwijalny) { $t.Cursor = [System.Windows.Forms.Cursors]::Hand }
  $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
  $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null
  # strzalka: rozwinieta w dol, zwinieta w prawo (znaki z Unicode, zeby nie zalezaly od kodowania pliku)
  $strz = ""
  if ($g.Rozwijalny) { $strz = $(if ($rozw) { [string][char]0x25BC } else { [string][char]0x25B6 }) + "  " }
  $ln = Etykieta-Zawijana ($strz + $g.Tytul) $script:CzGruba $script:KolTekst ($szer - 190)
  $ln.UseMnemonic = $false
  $ls = Etykieta $g.Napis $script:CzMalaGruba $g.KolorNapisu
  $ls.UseMnemonic = $false
  $ls.Anchor = [System.Windows.Forms.AnchorStyles]::Right
  $t.Controls.Add($ln, 0, 0)
  $t.Controls.Add($ls, 1, 0)
  $wiersz = 1
  $wciecie = $(if ($g.Rozwijalny) { 20 } else { 0 })
  foreach ($para in @(@($g.Opis, $script:KolSzary), @($g.Liczby, $script:KolTekst), @($g.Blad, $script:KolPilne), @($g.Uwaga, $script:KolUwaga))) {
    if (-not $para[0]) { continue }
    $l = Etykieta-Zawijana $para[0] $script:CzMala $para[1] ($szer - 50)
    $l.UseMnemonic = $false
    $l.Margin = New-Object System.Windows.Forms.Padding($wciecie, 2, 0, 0)
    if ($wiersz -ge $t.RowCount) { $t.RowCount = $wiersz + 1 }
    $t.Controls.Add($l, 0, $wiersz)
    $t.SetColumnSpan($l, 2)
    $wiersz++
  }
  if ($g.Rozwijalny) {
    foreach ($c in @($t) + @($t.Controls)) {
      $c.Tag = $g.Id
      $c.Add_Click({ param($nadawca, $e) try { Przelacz-Grupe "$($nadawca.Tag)" } catch { Zanotuj-Wywrotke "rozwiniecie grupy skilli" $_ } })
    }
  } else { $t.Tag = $g.Id }
  # pasek z lewej (kolor stanu grupy) i kreska pod naglowkiem
  $t.Add_Paint({ param($nadawca, $e)
    try {
      $kol = $script:ZnacznikiGrup["$($nadawca.Tag)"]
      if ($null -ne $kol) {
        $pedzel = New-Object System.Drawing.SolidBrush($kol)
        try { $e.Graphics.FillRectangle($pedzel, 0, 0, 5, $nadawca.Height) } finally { $pedzel.Dispose() }
      }
      $e.Graphics.DrawLine($script:PioroRamki, 0, $nadawca.Height - 1, $nadawca.Width, $nadawca.Height - 1)
    } catch { if (-not $script:RamkaZawiodla) { $script:RamkaZawiodla = $true; Zanotuj-Wywrotke "pasek grupy skilli" $_ } }
  })
  $script:NaglowkiGrup[$g.Id] = $t
  return $t
}

# Wiersz pod naglowkiem rozwinietej grupy: kiedy sprawdzone i jaka jest najnowsza wersja.
function Wiersz-Sprawdzenia($z, [int]$szer) {
  $p = Pionowy $szer
  $p.Padding = New-Object System.Windows.Forms.Padding(34, 6, 12, 4)
  $p.BackColor = $script:TloKarty
  $t = $(if ($z.sprawdzono) { "Sprawdzone $($z.sprawdzono). Najnowsza wersja autora: $(Wersja-Krotko $z.commit $z.data)." } else { "Jeszcze nie sprawdzane." })
  $l = Etykieta-Zawijana $t $script:CzMala $script:KolSzary ($szer - 50)
  $l.UseMnemonic = $false
  $p.Controls.Add($l)
  return $p
}

function Przelacz-Grupe([string]$id) {
  if (-not $id) { return }
  $script:GrupySkilli[$id] = -not [bool]$script:GrupySkilli[$id]
  Napelnij-Skille $true
  $n = $script:NaglowkiGrup[$id]
  if ($n -and -not $n.IsDisposed) { $script:ListaSkilli.ScrollControlIntoView($n) }
}

function Znajdz-Skill([string]$nazwa) {
  if (-not $script:DaneSkilli -or -not $script:DaneSkilli.Dane) { return $null }
  foreach ($z in @($script:DaneSkilli.Dane.zrodla)) {
    foreach ($s in @($z.skille)) { if ($s.nazwa -eq $nazwa) { return @($s, $z) } }
  }
  return $null
}

function Zdanie-Skilli($d) {
  $l = $d.liczniki
  $t = ""
  $t += "W bazie $($l.wBazie) $(Odmiana $l.wBazie 'skill' 'skille' 'skilli') - aktualne: $($l.zgodne), czeka nowsza wersja: $($l.starsze), zmienione ręcznie: $($l.zmienione), niezainstalowane: $($l.brak)."
  if ($l.usuniete -gt 0) { $t += " Autor usunął: $($l.usuniete)." }
  if ($l.dzisZaktualizowane -gt 0) { $t += " Dziś pobrano nowe wersje: $($l.dzisZaktualizowane)." }
  if ($l.bledy -gt 0) { $t += " Nie udało się sprawdzić: $($l.bledy)." }
  $zn = $d.znacznik
  if ($zn -and $zn.dzien) {
    $t += " Codzienne sprawdzenie: $($zn.start)"
    if ($zn.wynik -eq "blad") { $t += " - BŁĄD." } elseif ($zn.wynik -eq "pracuje") { $t += " - trwa." } else { $t += " - w porządku." }
  } else { $t += " Codziennego sprawdzenia jeszcze nie było." }
  return $t
}

# $tylkoLista - rozwiniecie/zwiniecie grupy: przebudowa samej listy z danych, ktore juz
# sa, bez ruszania prawej strony (wynik operacji ani wybrany skill nie znikaja).
# Samo rysowanie - stan skilli liczy krok w tle "skille" (P21).
function Napelnij-Skille([bool]$tylkoLista = $false) {
  if (-not $script:ListaSkilli -or $script:ListaSkilli.IsDisposed) { return }
  if ($null -eq $script:DaneSkilli) { return }
  if (-not $tylkoLista) { $script:DoOdmalowania["skille"] = $false }
  $ds = $script:DaneSkilli
  $lista = $script:ListaSkilli
  $lista.SuspendLayout()
  try {
    $script:WierszeSkilli = @{}
    $script:NaglowkiGrup = @{}
    $script:ZnacznikiGrup = @{}
    $wnetrze = $lista.Controls[0]
    Wyczysc-Panel $wnetrze
    if ($ds.Powod -or -not $ds.Dane) {
      $script:LSkille.ForeColor = $script:KolPilne
      $script:LSkille.Text = "NIE UDAŁO SIĘ ZEBRAĆ LISTY SKILLI: $($ds.Powod)"
      Pokaz-Info-Skilla $null
      $script:SkillePodglad.Text = ("Lista jest pusta, bo jej zebranie się nie udało - to nie znaczy, że nie masz skilli." + "`r`n`r`n" +
        "Powód: $($ds.Powod)" + "`r`n`r`n" + "Spróbuj ręcznie:" + "`r`n" +
        "powershell -ExecutionPolicy Bypass -File $(Skrypt-Skilli)")
      return
    }
    $d = $ds.Dane
    # wiersze dokladane jeden po drugim - uklad liczony raz, na koncu (rozwiniecie grupy ~2x szybciej)
    $wnetrze.SuspendLayout()
    $szer = [math]::Max(300, $lista.ClientSize.Width - [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth - 2)
    foreach ($z in @($d.zrodla)) {
      $g = Grupa-Zrodla $z
      $wnetrze.Controls.Add((Naglowek-Grupy $g $szer))
      if (-not ($g.Rozwijalny -and $script:GrupySkilli[$g.Id])) { continue }
      $wnetrze.Controls.Add((Wiersz-Sprawdzenia $z $szer))
      foreach ($s in @($z.skille)) {
        $w = Wiersz-Skilla $s $szer
        $script:WierszeSkilli["$($s.nazwa)"] = $w
        $wnetrze.Controls.Add($w)
      }
    }
    $spoza = @($d.spozaBazy | ForEach-Object { "$($_.folder)" } | Select-Object -Unique)
    if ($spoza.Count -gt 0) {
      $g = [pscustomobject]@{
        Id = "__spoza"; Tytul = "Zainstalowane, spoza bazy"; Opis = "Twoje własne i z innych źródeł. MegaRuchacz ich nie sprawdza i nie rusza."
        Liczby = "$($spoza.Count) $(Odmiana $spoza.Count 'skill' 'skille' 'skilli')"; Napis = ""; KolorNapisu = $script:KolSzary
        Znacznik = $null; Blad = ""; Uwaga = ""; Rozwijalny = $true
      }
      $wnetrze.Controls.Add((Naglowek-Grupy $g $szer))
      if ($script:GrupySkilli["__spoza"]) {
        $p = Pionowy $szer
        $p.Padding = New-Object System.Windows.Forms.Padding(34, 8, 12, 12)
        $p.BackColor = $script:TloKarty
        $lsp = Etykieta-Zawijana ($spoza -join ", ") $script:CzMala $script:KolTekst ($szer - 50)
        $lsp.UseMnemonic = $false
        $p.Controls.Add($lsp)
        $wnetrze.Controls.Add($p)
      }
    }
    $wnetrze.ResumeLayout($true)
    if ($tylkoLista) {
      # sam wybrany wiersz podswietlony (jesli jego grupa jest rozwinieta), prawa strona bez zmian
      $w = $script:WierszeSkilli[$script:SkillWybrany]
      if ($w) { $w.BackColor = $script:TloPrzel }
      return
    }
    $script:LSkille.ForeColor = $script:KolTekst
    if ($d.liczniki.bledy -gt 0 -or ($d.znacznik -and $d.znacznik.wynik -eq "blad")) { $script:LSkille.ForeColor = $script:KolPilne }
    $script:LSkille.Text = Zdanie-Skilli $d
    if ($script:SkillWybrany -and (Znajdz-Skill $script:SkillWybrany)) { Wybierz-Skill $script:SkillWybrany }
    else { $script:SkillWybrany = ""; Pokaz-Info-Skilla $null; Pokaz-Przeglad-Skilli }
  } finally {
    $lista.ResumeLayout($true)
    # etykieta sama dopasowuje wysokosc (AutoSize z MaximumSize)
  }
}

# Prawa strona, gdy nic nie jest wybrane: czym jest ta zakladka, ostatnie codzienne
# sprawdzenie i ostatnia operacja - zeby wynik klikniecia nie znikal po odswiezeniu.
function Pokaz-Przeglad-Skilli {
  if (-not $script:SkillePodglad -or $script:SkillePodglad.IsDisposed) { return }
  $d = $script:DaneSkilli.Dane
  $l = New-Object System.Collections.Generic.List[string]
  $l.Add("Kliknij grupę po lewej, żeby ją rozwinąć, a potem skill - zobaczysz, co robi, jaką masz wersję i co się zmieniło przy ostatniej aktualizacji. Grupa z czerwonym paskiem ma problem, z bursztynowym - nowszą wersję do pobrania.")
  $l.Add("")
  $l.Add("Jak to działa:")
  $l.Add("- Raz dziennie MegaRuchacz sam sprawdza źródła i pobiera nowsze wersje skilli, które masz pod opieką.")
  $l.Add("- Gdy pobranie się nie uda, próbuje jeszcze 5 razy (po 5 s, 15 s, 30 s, 1 min i 2 min). Błąd pokazuje dopiero wtedy, gdy wszystkie próby zawiodą.")
  $l.Add("- Gdy autor przeniesie skill w swoim repozytorium, MegaRuchacz sam go znajdzie. Gdy autor skill usunie, Twoja kopia zostaje i działa dalej.")
  $l.Add("- Przed każdą podmianą robi kopię starej wersji. `„Cofnij ostatnią aktualizację`” przywraca ją co do bajtu.")
  $l.Add("- Skilla zmienionego ręcznie nie nadpisuje nigdy sam.")
  $l.Add("- Gdzie instaluje: " + ((@($d.cele | Where-Object { $_.jest }) | ForEach-Object { "$($_.nazwa) ($($_.katalog))" }) -join "; ") + ". opencode czyta te same katalogi.")
  $zn = $d.znacznik
  $l.Add("")
  if ($zn -and $zn.dzien) {
    $l.Add("Ostatnie codzienne sprawdzenie: $($zn.start) - $($zn.koniec), wynik: $(if ($zn.wynik -eq 'ok') { 'w porządku' } else { $zn.wynik }), pobranych nowych wersji: $($zn.zaktualizowano).")
    if ($zn.pierwszy -eq "True") { $l.Add("To był pierwszy przebieg na tym komputerze - tylko spisał, co masz. Nowsze wersje pobiera od następnego.") }
    if ($zn.powod) { $l.Add("Powód błędu: $($zn.powod)") }
  } else { $l.Add("Codziennego sprawdzenia jeszcze nie było - ruszy samo w ciągu kwadransa.") }
  $op = $d.operacja
  if ($op -and $op.tryb -and $op.tryb -ne "codziennie") {
    $l.Add("Ostatnia operacja z przycisku: $($op.tryb) $($op.skill) - $($op.start), wynik: $($op.wynik).")
    if ($op.powod) { $l.Add("Powód: $($op.powod)") }
  }
  $l.Add("")
  $l.Add("Dziennik zmian: $($d.dziennik)")
  $l.Add("Kopie zapasowe: $($d.kopie)")
  $script:SkillePodglad.Text = ($l -join "`r`n")
}

function Pokaz-Info-Skilla($para) {
  $info = $script:SkilleInfo
  if (-not $info -or $info.IsDisposed) { return }
  $info.SuspendLayout()
  try {
    Wyczysc-Panel $info
    $szer = [math]::Max(300, $info.Parent.ClientSize.Width - $info.Parent.Padding.Horizontal - 12)
    if (-not $para) {
      $t = Etykieta-Zawijana "Polecane skille" $script:CzSrednia $script:KolTekst $szer
      $info.Controls.Add($t)
      Ustaw-Przyciski-Skilla $null
      return
    }
    $s = $para[0]; $z = $para[1]
    $tyt = "$($s.folder)"
    $t = Etykieta-Zawijana $tyt $script:CzSrednia $script:KolTekst $szer
    $t.UseMnemonic = $false
    $t.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $info.Controls.Add($t)
    $e = 130
    $info.Controls.Add((Wiersz-Dwukolumnowy "Do czego jest" "$($s.opis)" $script:KolTekst $szer $e))
    $ns = Napis-Skilla $s
    $info.Controls.Add((Wiersz-Dwukolumnowy "Stan" (Zdanie-Stanu-Skilla $s) $ns[1] $szer $e))
    if ($s.blad) { $info.Controls.Add((Wiersz-Dwukolumnowy "Błąd" "$($s.blad)" $script:KolPilne $szer $e)) }
    if ($s.przeniesiony) {
      $info.Controls.Add((Wiersz-Dwukolumnowy "Przeniesiony" "Autor przeniósł go w swoim repo z $($s.przeniesiony.z) do $($s.przeniesiony.na) (zauważone $(Data-Krotko "$($s.przeniesiony.kiedy)")). MegaRuchacz sam bierze go z nowego miejsca." $script:KolSzary $szer $e))
    }
    foreach ($c in @($s.cele)) {
      $oc = Opis-Celu $c
      # przy skillu usunietym przez autora "aktualny" nic nie znaczy - jest po prostu Twoja kopia
      if ($s.stan -eq "usuniety" -and $c.stan -ne "brak") { $oc = "masz kopię$(if ($c.commit) { ' - ostatnia wersja od autora ' + (Wersja-Krotko $c.commit $c.data) })" }
      $info.Controls.Add((Wiersz-Dwukolumnowy "$($c.nazwa)" $oc $script:KolTekst $szer $e))
    }
    if ($s.najnowszy) { $info.Controls.Add((Wiersz-Dwukolumnowy "Najnowsza" (Wersja-Krotko $s.najnowszy.commit $s.najnowszy.data) $script:KolTekst $szer $e)) }
    if ($s.sprawdzono) { $info.Controls.Add((Wiersz-Dwukolumnowy "Sprawdzone" "$($s.sprawdzono)" $script:KolTekst $szer $e)) }
    $info.Controls.Add((Wiersz-Dwukolumnowy "Źródło" "$($z.nazwa) - $($z.adres)" $script:KolSzary $szer $e))
    Ustaw-Przyciski-Skilla $s
  } finally { $info.ResumeLayout($true) }
}

function Ustaw-Przyciski-Skilla($s) {
  $pracuje = [bool]$script:SkilleOperacjaOd
  $script:BSkilleTeraz.Enabled = -not $pracuje
  $script:SkillePrzyciski.Visible = [bool]$s
  if (-not $s) { return }
  $usun = ($s.stan -eq "usuniety")
  $inst = (($s.stan -eq "brak") -or (@($s.brakujeW).Count -gt 0)) -and -not $usun
  $akt = ($s.stan -eq "starszy") -or ($s.stan -eq "zmieniony")
  $cof = ($null -ne $s.zmiana) -and (@("aktualizacja", "nadpisanie", "usuniecie") -contains "$($s.zmiana.rodzaj)")
  $script:BSkillInstaluj.Enabled = $inst -and -not $pracuje
  # Zainstalowany u jednego narzedzia, brak u drugiego - przycisk mowi wprost, gdzie doda.
  $script:BSkillInstaluj.Text = $(if (($s.stan -ne "brak") -and (@($s.brakujeW).Count -gt 0)) { "Dodaj dla: " + (@($s.brakujeW) -join ", ") } else { "Zainstaluj" })
  $script:BSkillAktualizuj.Visible = -not $usun
  $script:BSkillAktualizuj.Enabled = $akt -and -not $pracuje
  $script:BSkillUsun.Visible = $usun
  $script:BSkillUsun.Enabled = $usun -and [bool]$s.zainstalowany -and -not $pracuje
  $script:BSkillCofnij.Text = $(if ($cof -and "$($s.zmiana.rodzaj)" -eq "usuniecie") { "Przywróć usunięty" } else { "Cofnij ostatnią aktualizację" })
  $script:BSkillCofnij.Enabled = $cof -and -not $pracuje
}

# Podglad: co sie zmienilo przy ostatniej aktualizacji (pliki, opisy zmian od autora),
# a dla zmienionego recznie - czym rozni sie od najblizszej wersji autora.
function Podglad-Skilla($s) {
  $l = New-Object System.Collections.Generic.List[string]
  foreach ($c in @($s.cele)) {
    if ($c.najblizszy) { $l.Add("$($c.nazwa): czym Twoja wersja różni się od autora - $($c.najblizszy)"); $l.Add("") }
  }
  $zm = $s.zmiana
  if ($zm -and ($zm.rodzaj -eq "usuniecie")) {
    $l.Add("Usunięty u Ciebie na Twoje życzenie: $($zm.kiedy) (autor wcześniej usunął go ze swojego źródła).")
    $l.Add("Kopia zapasowa: $($zm.kopia)")
    $l.Add("`„Przywróć usunięty`” wgra go z tej kopii co do bajtu.")
    return ($l -join "`r`n")
  }
  if ($s.stan -eq "usuniety") {
    $l.Add("Autor usunął ten skill ze swojego źródła (nie ma go już pod $($s.usuniety.sciezka) ani nigdzie indziej w jego repozytorium).")
    $l.Add("")
    if ($s.zainstalowany) {
      $l.Add("Twoja kopia zostaje nietknięta i działa dalej - MegaRuchacz jej nie skasuje sam. Nie dostanie już tylko nowych wersji.")
      $l.Add("Jeśli go nie potrzebujesz: `„Usuń u mnie`” skasuje go z Twojego komputera, a wcześniej zrobi kopię zapasową.")
    } else {
      $l.Add("Nie masz go zainstalowanego, a zainstalować go się już nie da.")
    }
    return ($l -join "`r`n")
  }
  if ((-not $zm) -and ($s.stan -eq "brak")) {
    $gdzie = (@($script:DaneSkilli.Dane.cele | Where-Object { $_.jest }) | ForEach-Object { "$($_.nazwa)" }) -join " i "
    $l.Add("Nie masz go jeszcze. `„Zainstaluj`” wgra najnowszą wersję od autora dla: $gdzie. Od tej chwili będzie się sam aktualizował raz dziennie.")
  } elseif ((-not $zm) -and ($s.stan -eq "zmieniony")) {
    $l.Add("Nie aktualizuję go sam, bo Twoja wersja różni się od każdej wersji autora - aktualizacja skasowałaby Twoje zmiany.")
  } elseif (-not $zm) {
    $l.Add("Od kiedy jest pod opieką MegaRuchacza, ten skill nie był jeszcze aktualizowany.")
  } elseif ($zm.rodzaj -eq "cofniecie") {
    $l.Add("Ostatnio: cofnięcie aktualizacji, $($zm.kiedy).")
    $l.Add("Przywrócona kopia: $($zm.kopia)")
    if ($zm.poprzednia) { $l.Add("Wersja sprzed cofnięcia leży w: $($zm.poprzednia)") }
  } else {
    $l.Add("Ostatnia aktualizacja: $($zm.kiedy)$(if ($zm.rodzaj -eq 'nadpisanie') { ' (nadpisanie wersji zmienionej ręcznie, za Twoją zgodą)' }).")
    $l.Add("Wersja: $(Wersja-Krotko $zm.z $zm.zData)  ->  $(Wersja-Krotko $zm.na $zm.naData)")
    $l.Add("Pliki: nowe $(@($zm.dodane).Count), zmienione $(@($zm.zmienione).Count), usunięte $(@($zm.usuniete).Count).")
    foreach ($p in @($zm.dodane)) { $l.Add("  + $p") }
    foreach ($p in @($zm.zmienione)) { $l.Add("  ~ $p") }
    foreach ($p in @($zm.usuniete)) { $l.Add("  - $p") }
    if (@($zm.opisy).Count -gt 0) {
      $l.Add("")
      $l.Add("Opisy zmian od autora (po angielsku, najnowsze na górze):")
      foreach ($o in @($zm.opisy)) { $l.Add("  $o") }
    }
    $l.Add("")
    $l.Add("Kopia poprzedniej wersji: $($zm.kopia)")
  }
  return ($l -join "`r`n")
}

function Wybierz-Skill([string]$nazwa) {
  $para = Znajdz-Skill $nazwa
  if (-not $para) { return }
  foreach ($k in @($script:WierszeSkilli.Keys)) {
    $w = $script:WierszeSkilli[$k]
    if ($w -and -not $w.IsDisposed) {
      $w.BackColor = $(if ($k -eq $nazwa) { $script:TloPrzel } else { $script:TloKarty })
    }
  }
  $script:SkillWybrany = $nazwa
  $wiersz = $script:WierszeSkilli[$nazwa]
  if ($wiersz -and -not $wiersz.IsDisposed) { $script:ListaSkilli.ScrollControlIntoView($wiersz) }
  Pokaz-Info-Skilla $para
  $script:SkillePodglad.Text = Podglad-Skilla $para[0]
  $script:SkillePodglad.SelectionStart = 0
  $script:SkillePodglad.ScrollToCaret()
}

# Klikniecie przycisku: start w tle, zegar co 2 s. Koniec rozpoznajemy po operacja.txt
# z poczatkiem nie wczesniejszym niz klikniecie i wynikiem innym niz "pracuje".
function Rusz-Operacje-Skilli([string]$tryb, [string]$skill, [bool]$wymus, [string]$opis) {
  $powod = Operacja-Na-Skillach $tryb $skill $wymus
  if ($powod) {
    $script:SkillePodglad.Text = "NIE UDAŁO SIĘ URUCHOMIĆ: $powod"
    return
  }
  $script:SkilleOperacjaOd = [datetime]::Now.AddSeconds(-1)
  $script:SkilleOperacjaOpis = $opis
  $script:SkillePodglad.Text = "$opis`r`n`r`nPracuję w tle - to potrwa od kilku sekund do kilku minut (pierwsze pobranie źródeł jest najdłuższe). Okno odświeży się samo."
  Ustaw-Przyciski-Skilla $(if ($skill) { (Znajdz-Skill $skill)[0] } else { $null })
  if (-not $script:ZegarSkilli) {
    $script:ZegarSkilli = New-Object System.Windows.Forms.Timer
    $script:ZegarSkilli.Interval = 2000
    $script:ZegarSkilli.Add_Tick({
      try { Sprawdz-Operacje-Skilli }
      catch { $script:ZegarSkilli.Stop(); $script:SkilleOperacjaOd = $null; Zanotuj-Wywrotke "zegar operacji na skillach" $_ }
    })
  }
  $script:ZegarSkilli.Start()
}

function Sprawdz-Operacje-Skilli {
  if (-not $script:SkilleOperacjaOd) { $script:ZegarSkilli.Stop(); return }
  $op = Operacja-Skilli
  $start = Data-Lub-Nic $op["start"]
  $minelo = ([datetime]::Now - $script:SkilleOperacjaOd).TotalSeconds
  $koniec = $false; $tekst = ""
  if ($start -and ($start -ge $script:SkilleOperacjaOd) -and ($op["wynik"] -ne "pracuje")) {
    $koniec = $true
    $log = @()
    try { $log = [System.IO.File]::ReadAllLines((Join-Path (Katalog-Stanu-Skilli) "operacja.log"), [System.Text.Encoding]::UTF8) }
    catch { $log = @("(nie udało się odczytać wydruku operacji: $($_.Exception.Message))") }
    $tekst = "$($script:SkilleOperacjaOpis) - $(if ($op['wynik'] -eq 'ok') { 'GOTOWE' } else { 'SKOŃCZONE Z BŁĘDEM' }) ($($op['koniec']))`r`n`r`n" + ($log -join "`r`n")
  } elseif (($op["wynik"] -eq "pracuje") -and $start -and ($start -lt $script:SkilleOperacjaOd) -and ($minelo -gt 10)) {
    $koniec = $true
    $tekst = "Nie ruszyłem, bo właśnie trwa inna operacja na skillach ($($op['tryb']) od $($op['start'])). Spróbuj za chwilę."
  } elseif ($minelo -gt 900) {
    $koniec = $true
    $tekst = "Po 15 minutach operacja wciąż nie zapisała wyniku. Sprawdź dziennik: $(Join-Path (Katalog-Stanu-Skilli) 'dziennik.log')"
    Zanotuj-Wywrotke "operacja na skillach" "brak wyniku po 15 min ($($script:SkilleOperacjaOpis))"
  }
  if (-not $koniec) { return }
  $script:ZegarSkilli.Stop()
  $script:SkilleOperacjaOd = $null
  if ($script:WidokSkille -and -not $script:WidokSkille.IsDisposed) {
    $script:SkillePodglad.Text = $tekst
    $script:SkillePodglad.SelectionStart = 0
    $script:SkillePodglad.ScrollToCaret()
    # Lista po operacji liczy sie w tle (P21); wynik operacji wraca na prawa
    # strone po przebudowie listy (Wyrenderuj-Widok).
    $script:SkillePoOperacji = $tekst
    [void](Rusz-Krok "skille")
  }
}

# Dzienne zuzycie tokenow (P17): odczyt pliku podrecznego, a gdy wyniku z dzis
# nie ma - liczenie w osobnym procesie. Okno nie czeka: zegar co 3 s sprawdza,
# czy wynik juz jest, i wtedy odmalowuje okno. Zegar staje sam, gdy stan
# przestaje byc "licze" (wynik albo powod, czemu go nie ma - nigdy wieczne "licze":
# Zuzycie-Dzienne po $MINUT_LICZENIA_ZUZYCIA zamienia je na powod).
function Odswiez-Zuzycie {
  try { $script:Zuzycie = Zuzycie-Dzienne $false }
  catch {
    Zanotuj-Wywrotke "dzienne zuzycie tokenow" $_
    $script:Zuzycie = [pscustomobject]@{ Stan = "brak"; Powod = "odczyt się wywrócił: $($_.Exception.Message)" }
  }
  if (-not $script:Zuzycie -or ($script:Zuzycie.Stan -ne "licze")) {
    if ($script:ZegarZuzycia) { $script:ZegarZuzycia.Stop() }
    return
  }
  if (-not $script:ZegarZuzycia) {
    $script:ZegarZuzycia = New-Object System.Windows.Forms.Timer
    $script:ZegarZuzycia.Interval = 3000
    $script:ZegarZuzycia.Add_Tick({
      try {
        $przed = $script:Zuzycie.Stan
        Odswiez-Zuzycie
        if ($script:Zuzycie.Stan -ne $przed) { Odmaluj-Okno }
      } catch {
        $script:ZegarZuzycia.Stop()
        Zanotuj-Wywrotke "zegar dziennego zuzycia tokenow" $_
      }
    })
  }
  $script:ZegarZuzycia.Start()
}

# --- liczenie w tle i ekran ladowania (P21, 30.09.2026) ----------------------
# Uzytkownik: "Czy mozna cos zrobic z sama apka, zeby tak dziwnie nie otwierala
# sie, gdy rano ja klikam? Nie moze byc jakies okno postepu wczytywanych danych,
# zeby nie zmieniala swojego rozmiaru w dziki sposob?"
#
# NAGRANIE PRZED ZMIANA (P21, zrzuty co 200 ms + zegar kontrolny watku okna)
# pokazalo trzy rzeczy naraz: okno wstawalo w wysokosci policzonej dla PUSTYCH
# kart (1089 px); 150 ms pozniej caly interfejs stawal na ~3,7 s, bo Odswiez-Dane
# wolalo koszt-pamieci.ps1 (-Dane, -Start) w watku okna; potem karty rosly,
# Dopasuj-Wysokosc podnosilo okno do 1347 px, a po kolejnych 3 s (dzienne
# zuzycie) karty przestawialy sie jeszcze raz. Zakladki stawaly na 1,2-2,2 s.
#
# TERAZ:
# - okno ma od pierwszej chwili stala wysokosc (Pokaz-Okno) i samo jej nie zmienia,
# - wszystko, co wola skrypty, liczy sie w osobnych watkach (runspace'ach), ktore
#   wczytuja stan-nadzorcy.ps1; watek okna co 150 ms tylko zaglada, co gotowe,
# - zakladka bez kompletu danych z dzis ma nad soba ekran ladowania z lista krokow;
#   karty buduja sie RAZ, z kompletem, i dopiero wtedy ekran znika,
# - dane z dzis pokazuja sie od razu; starsze niz $MINUT_SWIEZOSCI min odswiezaja
#   sie po cichu i zakladka odmalowuje sie raz, gdy odswiezanie sie skonczy,
# - kazdy krok ma limit czasu wyprowadzony z limitow tego, co wola (nizej); po nim
#   krok jest przerywany, a ekran ladowania mowi przy nim, co sie stalo.

# Ile krokow naraz. Kazdy to watek plus zwykle jeden proces powershell.exe
# (~70 MB). Trzy wystarczaja, zeby trzy kroki Przegladu szly rownolegle;
# reszta zakladek dochodzi, gdy zwolni sie miejsce.
$KROKI_NARAZ = 3
# Dozor przelicza dane co $Minut min - liczby mlodsze niz to sa tak swieze, jak
# cokolwiek, co okno mogloby policzyc. Takie pokazujemy bez liczenia.
$MINUT_SWIEZOSCI = [math]::Max(1, $Minut)
# Po nieudanym kroku ekran ladowania stoi jeszcze tyle sekund z bledem na wierzchu
# (z przyciskiem "Pokaz od razu"): tyle trwa przeczytanie jednego zdania. Ten sam
# powod zostaje potem w karcie i w Szczegolach - nic nie znika.
$SEKUNDY_PO_BLEDZIE = 5
# Najwyzsza wysokosc okna. Przeglad z kompletem danych zmierzony 30.09.2026 =
# 1351 px okna; 1400 zostawia miejsce na karte problemu. Na nizszym ekranie okno
# ma obszar roboczy minus 40 px, a Przeglad sie przewija - jak dotad.
$WYS_OKNA_MAX = 1400
# LIMITY CZASU KROKOW - kazdy z limitu tego, co krok woła, nie "na oko":
#  - koszt-pamieci.ps1 i skille.ps1 ida przez Wolaj-Skrypt z wlasnym limitem
#    (120 s / 90 s) i same oddaja powod "nie skonczyl w N s". Limit kroku = tamten
#    + 30 s na start watku (zmierzone ~0,3 s) i odczyt: przerwanie przez okno to
#    ostatnia deska ratunku, gdyby watek utknal gdzie indziej;
#  - "dane" wola jeszcze gita bez sieci (Stan-Wersji, Stan-Cyklu, po 10 s) -> 180 s;
#  - dozor pobiera dodatkowo z sieci (git fetch 25 s) -> 240 s;
#  - dzienne zuzycie czeka na osobny proces liczacy: P17 zmierzyl 6-7 s dla 337 MB
#    transkryptow, 30.09 bylo 2,7 s - 60 s to ~10 razy zapasu na zimny dysk. Potem
#    karta mowi "jeszcze sie liczy" i dociaga wynik sama (Odswiez-Zuzycie), a samo
#    liczenie ma swoj limit $MINUT_LICZENIA_ZUZYCIA w stan-nadzorcy.ps1.
$SEKUNDY_ZUZYCIA = 60
$LIMIT_DOZORU = 240
# Kawalki danych. Zwykle = ile sekund zwykle trwa (do paska postepu, zanim krok
# zmierzy sie sam). PowodToBlad = zwrocony powod to porazka (nastepne wejscie
# liczy od nowa z ekranem ladowania); przy pozostalych powod to wynik ("nie
# zmierzono, bo..."), ktory karta pokazuje, a liczyc od nowa nie ma po co.
$KAWALKI = [ordered]@{
  dane     = @{ Napis = "Sprawdzam stan MegaRuchacza i liczę rachunek za pamięć"; Kod = 'Zbierz-Wszystko $false $true'; Limit = 180; Zwykle = 3; PowodToBlad = $false }
  start    = @{ Napis = "Liczę koszt otwarcia okna rozmowy"; Kod = 'Pomiar-Startu'; Limit = 150; Zwykle = 2; PowodToBlad = $false }
  zuzycie  = @{ Napis = "Sprawdzam dzienne zużycie tokenów"; Limit = ($SEKUNDY_ZUZYCIA + 30); Zwykle = 4; PowodToBlad = $false
                Kod = ('$z = Zuzycie-Dzienne $false; $do = [datetime]::Now.AddSeconds(' + $SEKUNDY_ZUZYCIA + '); ' +
                       'while (($z.Stan -eq "licze") -and ([datetime]::Now -lt $do)) { Start-Sleep -Milliseconds 400; $z = Zuzycie-Dzienne $false }; $z') }
  rozbicie = @{ Napis = "Liczę rozbicie rachunku pozycja po pozycji"; Kod = 'Rachunek-Rozbicie'; Limit = 150; Zwykle = 2; PowodToBlad = $true }
  warstwy  = @{ Napis = "Zbieram listę warstw pamięci"; Kod = 'Warstwy-Pamieci'; Limit = 150; Zwykle = 2; PowodToBlad = $true }
  skille   = @{ Napis = "Sprawdzam skille"; Kod = 'Stan-Skilli'; Limit = 120; Zwykle = 2; PowodToBlad = $true }
}
# Czego potrzebuje kazda zakladka, zeby pokazac karty w komplecie.
$WIDOK_KAWALKI = @{
  przeglad  = @("dane", "start", "zuzycie")
  szczegoly = @("dane", "start", "rozbicie")
  warstwy   = @("warstwy")
  skille    = @("skille")
}
$NAZWY_WIDOKOW = @{ przeglad = "Przegląd"; szczegoly = "Szczegóły"; warstwy = "Warstwy pamięci"; skille = "Skille" }
foreach ($id in $KAWALKI.Keys) { $script:StanKawalkow[$id] = [pscustomobject]@{ Id = $id; Czas = $null; Nieudany = $false; Krok = $null; Ostatni = $null } }

# Kod wykonywany w watku w tle. Wczytuje stan-nadzorcy.ps1 (raz na watek), ustawia
# te same sciezki co okno i oddaje wynik razem z wywrotkami, zeby trafily do
# okna, a nie zginely razem z watkiem. NadzZuzycieOdpalone jedzie tam i z powrotem:
# to dlawik "liczenie zuzycia najwyzej raz na ... min" z Zuzycie-Dzienne.
$KOD_KROKU = @'
param($PlikStanu, $Zrodlo, $Dom, $Proba, $Kod, $Odpalone)
if (-not (Get-Command Ustaw-Nadzorce -ErrorAction SilentlyContinue)) { . $PlikStanu }
Ustaw-Nadzorce $Zrodlo $Dom $Proba
$script:NadzZuzycieOdpalone = $Odpalone
$wynik = & ([scriptblock]::Create($Kod))
[pscustomobject]@{ Wynik = $wynik; Wywrotki = @($script:NadzWywrotki); Odpalone = $script:NadzZuzycieOdpalone }
'@

function Czas-Kawalka([string]$id) {
  # dane przychodza takze z dozoru - ich czas to czas danych w oknie
  if ($id -eq "dane") { if ($script:Dane) { return $script:DaneCzas } else { return $null } }
  return $script:StanKawalkow[$id].Czas
}

# Brak = nie ma danych z dzis albo ostatnia proba sie nie udala. Wtedy zakladka
# czeka na nie za ekranem ladowania.
function Brakuje-Kawalka([string]$id) {
  $c = Czas-Kawalka $id
  if (-not $c) { return $true }
  if ($c.Date -ne [datetime]::Today) { return $true }
  if (($id -ne "dane") -and $script:StanKawalkow[$id].Nieudany) { return $true }
  return $false
}

function Nieswiezy-Kawalek([string]$id) {
  $c = Czas-Kawalka $id
  if (-not $c) { return $true }
  if ($id -eq "zuzycie") {
    # srednia dzienna nie zmienia sie w ciagu dnia - z dzis znaczy swieza
    if ($script:Zuzycie -and ($script:Zuzycie.Stan -eq "jest")) { return $false }
    if ($script:Zuzycie -and ($script:Zuzycie.Stan -eq "licze")) { return $true }
  }
  return ((([datetime]::Now - $c).TotalMinutes) -ge $MINUT_SWIEZOSCI)
}

function Krok-Trwa($k) { return ($k -and (@("czeka", "otwiera", "liczy") -contains $k.Stan)) }

function Nowy-Krok([string]$id, [string]$kawalek, [string]$napis, [string]$kod, [int]$limit) {
  return [pscustomobject]@{
    Id = $id; Kawalek = $kawalek; Napis = $napis; Kod = $kod; Limit = $limit
    Stan = "czeka"; Od = $null; Koniec = $null; Powod = ""; Wynik = $null
    PS = $null; Uchwyt = $null; Robotnik = $null; Po = $null
  }
}

# Start kroku dla kawalka danych. Trwajacy krok nie rusza drugi raz - oddajemy
# ten, ktory juz liczy. $kod podmienia polecenie (menu: dane razem z siecia).
function Rusz-Krok([string]$id, [string]$kod = "") {
  $kaw = $script:StanKawalkow[$id]
  if (Krok-Trwa $kaw.Krok) { return $kaw.Krok }
  $def = $KAWALKI[$id]
  if (-not $kod) { $kod = $def.Kod }
  $k = Nowy-Krok $id $id $def.Napis $kod $def.Limit
  $kaw.Krok = $k
  [void]$script:KolejkaKrokow.Add($k)
  if (@("dane", "start", "zuzycie") -contains $id) { $script:Licze = $true }
  Wlacz-Zegar-Krokow
  Obsluz-Kroki
  return $k
}

# Dozor co kwadrans: dane w tle, decyzje po powrocie (Dozor-Po-Danych). Gdy
# poprzedni przebieg jeszcze trwa, ten jest pomijany - dwa naraz nie maja sensu.
function Rusz-Dozor {
  if (Krok-Trwa $script:KrokDozoru) {
    Notuj "dozor: poprzedni przebieg jeszcze trwa (od $($script:KrokDozoru.Od)) - ten pomijam"
    return
  }
  $k = Nowy-Krok "dozor" "" "Dozór" 'Zbierz-Wszystko $true $true' $LIMIT_DOZORU
  $k.Po = { param($k) Po-Dozorze $k }
  $script:KrokDozoru = $k
  [void]$script:KolejkaKrokow.Add($k)
  Wlacz-Zegar-Krokow
  Obsluz-Kroki
}

function Po-Dozorze($k) {
  if (($k.Stan -eq "blad") -or ($k.Stan -eq "czas")) {
    Zanotuj-Wywrotke "przebieg dozoru" $k.Powod
    return
  }
  $d = $k.Wynik
  try { Dozor-Po-Danych $d $script:Dymek } catch { Zanotuj-Wywrotke "przebieg dozoru (decyzje)" $_ }
  $script:Dane = $d
  $script:DaneCzas = [datetime]::Now
  $script:DaneBlad = $null
  Po-Kroku "dane"
}

function Wlacz-Zegar-Krokow {
  if (-not $script:ZegarKrokow) {
    $script:ZegarKrokow = New-Object System.Windows.Forms.Timer
    $script:ZegarKrokow.Interval = 150
    $script:ZegarKrokow.Add_Tick({
      try { Obsluz-Kroki; $script:BladZegaraKrokow = "" }
      catch {
        # Nie przerywamy (kroki musza sie dokonczyc), ale kazda NOWA wywrotka idzie do
        # dziennika. "Nowa" = inne miejsce w kodzie, a nie inny tekst - tekst potrafi
        # nosic zmieniajaca sie liczbe i zasypalby dziennik co 150 ms (zlapane w probie P21).
        $klucz = "$($_.Exception.GetType().Name)@$($_.InvocationInfo.ScriptLineNumber)"
        if ($script:BladZegaraKrokow -ne $klucz) {
          $script:BladZegaraKrokow = $klucz
          Zanotuj-Wywrotke "zegar krokow w tle" $_
        }
      }
      try { Straznik-Ladowania }
      catch { if ($script:BladZegaraKrokow -ne "straznik") { $script:BladZegaraKrokow = "straznik"; Zanotuj-Wywrotke "straznik ekranu ladowania" $_ } }
    })
  }
  if (-not $script:ZegarKrokow.Enabled) { $script:ZegarKrokow.Start() }
}

# Serce: co 150 ms. Konczy gotowe kroki, przerywa te po limicie, daje prace
# czekajacym, sprzata przerwane watki, odmalowuje ekran ladowania.
function Obsluz-Kroki {
  $teraz = [datetime]::Now
  foreach ($k in @($script:KrokiAktywne)) {
    $minelo = 0
    if ($k.Od) { $minelo = ($teraz - $k.Od).TotalSeconds }
    if ($k.Stan -eq "otwiera") {
      $st = "$($k.Robotnik.RunspaceStateInfo.State)"
      if ($st -eq "Opened") { Uruchom-Krok $k }
      elseif (($st -eq "Broken") -or ($st -eq "Closed")) {
        $pw = "$($k.Robotnik.RunspaceStateInfo.Reason)"
        try { $k.Robotnik.Dispose() } catch { Notuj "nie dalo sie zwolnic zepsutego watku: $($_.Exception.Message)" }
        $k.Robotnik = $null
        Zakoncz-Krok $k "blad" "nie udało się uruchomić liczenia w tle ($pw)"
      }
      elseif ($minelo -gt $k.Limit) { Przerwij-Krok $k }
    } elseif ($k.Stan -eq "liczy") {
      if ($k.Uchwyt.IsCompleted) { Odbierz-Krok $k }
      elseif ($minelo -gt $k.Limit) { Przerwij-Krok $k }
    }
  }
  while ((-not $script:PrzydzialPoPokazaniu) -and ($script:KrokiAktywne.Count -lt $KROKI_NARAZ) -and ($script:KolejkaKrokow.Count -gt 0)) {
    $k = $script:KolejkaKrokow[0]
    $script:KolejkaKrokow.RemoveAt(0)
    Przydziel-Robotnika $k
  }
  foreach ($z in @($script:Zombie)) {
    $st = "$($z.PS.InvocationStateInfo.State)"
    if (@("Stopped", "Completed", "Failed") -contains $st) {
      try { $z.PS.Dispose(); if ($z.Rs) { $z.Rs.Dispose() } } catch { Notuj "nie dalo sie zwolnic przerwanego watku: $($_.Exception.Message)" }
      $script:Zombie.Remove($z)
    }
  }
  $script:Licze = $false
  foreach ($id in @("dane", "start", "zuzycie")) { if (Krok-Trwa $script:StanKawalkow[$id].Krok) { $script:Licze = $true } }
  if ($script:Ladowanie) { Sprawdz-Ladowanie }
  $pusto = ($script:KrokiAktywne.Count -eq 0) -and ($script:KolejkaKrokow.Count -eq 0) -and ($script:Zombie.Count -eq 0) -and (-not $script:Ladowanie)
  if ($pusto) {
    # Nic nie liczy - watki oddaja pamiec, zegar staje. Nastepne otwarcie
    # okna otworzy nowe (w tle, ~0,2 s).
    foreach ($rs in @($script:WolniRobotnicy)) {
      try { $rs.Dispose() } catch { Notuj "nie dalo sie zwolnic watku: $($_.Exception.Message)" }
    }
    $script:WolniRobotnicy.Clear()
    if ($script:ZegarKrokow) { $script:ZegarKrokow.Stop() }
  }
}

function Przydziel-Robotnika($k) {
  $k.Od = [datetime]::Now
  [void]$script:KrokiAktywne.Add($k)
  if ($script:WolniRobotnicy.Count -gt 0) {
    $k.Robotnik = $script:WolniRobotnicy[0]
    $script:WolniRobotnicy.RemoveAt(0)
    Uruchom-Krok $k
    return
  }
  try {
    # OpenAsync: otwarcie watku (~0,2 s) nie blokuje okna; krok rusza w Obsluz-Kroki,
    # gdy watek jest gotowy.
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $k.Robotnik = $rs
    $k.Stan = "otwiera"
    $rs.OpenAsync()
  } catch {
    Zakoncz-Krok $k "blad" "nie udało się utworzyć wątku do liczenia w tle: $($_.Exception.Message)"
  }
}

function Uruchom-Krok($k) {
  try {
    $ps = [powershell]::Create()
    $ps.Runspace = $k.Robotnik
    [void]$ps.AddScript($KOD_KROKU).AddArgument($script:NadzTenPlik).AddArgument($script:NadzZrodlo).AddArgument($script:NadzDom).AddArgument([bool]$script:NadzProba).AddArgument($k.Kod).AddArgument($script:NadzZuzycieOdpalone)
    $k.PS = $ps
    $k.Uchwyt = $ps.BeginInvoke()
    $k.Stan = "liczy"
  } catch {
    Zakoncz-Krok $k "blad" "nie udało się uruchomić liczenia w tle: $($_.Exception.Message)"
  }
}

function Odbierz-Krok($k) {
  $opak = $null; $blad = ""
  try {
    $wy = $k.PS.EndInvoke($k.Uchwyt)
    if ($wy.Count -gt 0) { $opak = $wy[$wy.Count - 1] }
    if (-not $opak -or ($null -eq $opak.PSObject.Properties["Wynik"])) {
      $bl = @($k.PS.Streams.Error | Select-Object -First 1)
      $blad = "liczenie nie oddało wyniku"
      if ($bl.Count -gt 0) { $blad += ": $($bl[0])" }
      $opak = $null
    }
  } catch {
    $e = $_.Exception
    while ($e.InnerException) { $e = $e.InnerException }
    $blad = "$($e.Message)"
  }
  # Watek wraca do puli tylko po czystym koncu - po wywrotce zaczynamy na swiezym.
  try { $k.PS.Dispose() } catch { Notuj "nie dalo sie zwolnic polecenia w tle: $($_.Exception.Message)" }
  if ($k.Robotnik) {
    if ($blad) { try { $k.Robotnik.Dispose() } catch { Notuj "nie dalo sie zwolnic watku po wywrotce: $($_.Exception.Message)" } }
    else { [void]$script:WolniRobotnicy.Add($k.Robotnik) }
  }
  $k.PS = $null; $k.Robotnik = $null
  if ($blad) { Zakoncz-Krok $k "blad" $blad; return }
  foreach ($w in @($opak.Wywrotki)) { if ($w) { $script:NadzWywrotki += "$w" } }
  if ($k.Id -eq "zuzycie") { $script:NadzZuzycieOdpalone = $opak.Odpalone }
  $k.Wynik = $opak.Wynik
  Zakoncz-Krok $k "ok" ""
}

function Przerwij-Krok($k) {
  $pw = "nie skończyło się w $($k.Limit) s - przerwałem"
  if ($k.PS) {
    try { [void]$k.PS.BeginStop($null, $null) } catch { Notuj "przerwanie kroku $($k.Id): $($_.Exception.Message)" }
    [void]$script:Zombie.Add([pscustomobject]@{ PS = $k.PS; Rs = $k.Robotnik })
  } elseif ($k.Robotnik) {
    try { $k.Robotnik.Dispose() } catch { Notuj "nie dalo sie zwolnic watku po limicie: $($_.Exception.Message)" }
  }
  $k.PS = $null; $k.Robotnik = $null
  Zanotuj-Wywrotke "liczenie w tle: $($k.Napis)" $pw
  Zakoncz-Krok $k "czas" $pw
}

# Wynik kroku trafia do zmiennych okna. Porazka (wywrotka albo limit) zostawia
# po sobie powod w tych samych miejscach, w ktorych stawialy go stare "catch" -
# karta mowi "nie zmierzono, bo...", a nie pokazuje pustki.
function Zakoncz-Krok($k, [string]$stan, [string]$powod) {
  $script:KrokiAktywne.Remove($k)
  $k.Koniec = [datetime]::Now
  $k.Stan = $stan
  $k.Powod = $powod
  if ($k.Od) { $script:CzasyKrokow[$k.Id] = ($k.Koniec - $k.Od).TotalSeconds }
  $id = $k.Kawalek
  if ($id) {
    $porazka = ($stan -ne "ok")
    try {
      switch ($id) {
        "dane" {
          if ($porazka) { $script:DaneBlad = $powod }
          else { $script:Dane = $k.Wynik; $script:DaneCzas = $k.Koniec; $script:DaneBlad = $null }
        }
        "start" {
          if ($porazka) { $script:Start = [pscustomobject]@{ Powod = "pomiar się wywrócił: $powod"; MrSesja = $null } }
          else { $script:Start = $k.Wynik }
        }
        "zuzycie" {
          if ($porazka) { $script:Zuzycie = [pscustomobject]@{ Stan = "brak"; Powod = "odczyt się wywrócił: $powod" } }
          else {
            $script:Zuzycie = $k.Wynik
            # dalej liczy (dluzej niz $SEKUNDY_ZUZYCIA) - zegar co 3 s dociagnie wynik sam
            if ($script:Zuzycie.Stan -eq "licze") { Odswiez-Zuzycie }
          }
        }
        "rozbicie" {
          if ($porazka) { $script:Rozbicie = @("  NIE UDALO SIE POLICZYC ROZBICIA: $powod") }
          else { $script:Rozbicie = $k.Wynik }
        }
        "warstwy" {
          if ($porazka) { $script:DaneWarstw = [pscustomobject]@{ Warstwy = @(); Uwagi = @(); Powod = $powod; Wygenerowano = ""; TrybGlobalny = $null; Projekt = "" } }
          else { $script:DaneWarstw = $k.Wynik }
        }
        "skille" {
          if ($porazka) { $script:DaneSkilli = [pscustomobject]@{ Dane = $null; Powod = $powod } }
          else { $script:DaneSkilli = $k.Wynik }
        }
      }
    } catch { Zanotuj-Wywrotke "przyjecie wyniku kroku $id" $_ }
    if ($porazka) {
      if ($stan -eq "blad") { Zanotuj-Wywrotke "liczenie w tle: $($k.Napis)" $powod }
    } else {
      # Krok przeszedl, ale oddal powod ("nie zmierzono, bo...") - to tez ma byc
      # widac przy kroku, nie tylko w karcie.
      $pw = ""
      try { $pw = Powod-Kawalka $id } catch { Zanotuj-Wywrotke "powod kroku $id" $_ }
      if ($pw) { $k.Stan = "uwaga"; $k.Powod = $pw }
    }
    $kaw = $script:StanKawalkow[$id]
    $kaw.Czas = $k.Koniec
    $kaw.Nieudany = $porazka -or (($k.Stan -eq "uwaga") -and $KAWALKI[$id].PowodToBlad)
    $kaw.Ostatni = $k
    if ($kaw.Krok -eq $k) { $kaw.Krok = $null }
  }
  if ($k.Po) {
    try { & $k.Po $k } catch { Zanotuj-Wywrotke "dokonczenie kroku $($k.Id)" $_ }
  }
  if ($id) { Po-Kroku $id }
}

# Powod, ktory zwrocil sam wynik - pusty, gdy wszystko jest.
function Powod-Kawalka([string]$id) {
  switch ($id) {
    "dane" {
      if (-not $script:Dane) { return "nic nie wróciło" }
      if (-not $script:Dane.Rachunek) { return "rachunek za pamięć się nie policzył - szczegóły w dzienniku nadzorcy" }
      if ($script:Dane.Rachunek.Powod) { return "rachunek za pamięć: $($script:Dane.Rachunek.Powod)" }
      if (-not $script:Dane.Cykl) { return "nie odczytałem stanu nauki z rozmów - szczegóły w dzienniku nadzorcy" }
    }
    "start" { if ($script:Start -and $script:Start.Powod) { return "nie zmierzono, bo $($script:Start.Powod)" } }
    "zuzycie" {
      if ($script:Zuzycie -and ($script:Zuzycie.Stan -eq "licze")) { return "liczy się dłużej niż $SEKUNDY_ZUZYCIA s - pokażę resztę, a porównanie dojdzie samo, gdy będzie" }
      if ($script:Zuzycie -and ($script:Zuzycie.Stan -eq "brak")) { return "$($script:Zuzycie.Powod)" }
    }
    "rozbicie" {
      $l = @(@($script:Rozbicie) | Where-Object { "$_" -match 'NIE UDALO SIE|RACHUNEK PUSTY' } | Select-Object -First 1)
      if ($l.Count -gt 0) { return "$($l[0])".Trim() }
    }
    "warstwy" { if ($script:DaneWarstw -and $script:DaneWarstw.Powod) { return "$($script:DaneWarstw.Powod)" } }
    "skille" { if ($script:DaneSkilli -and $script:DaneSkilli.Powod) { return "$($script:DaneSkilli.Powod)" } }
  }
  return ""
}

# Po kazdym kroku: zakladki, ktore z niego korzystaja, sa do odmalowania. Ekran
# ladowania decyduje sam (Sprawdz-Ladowanie); bez niego biezaca zakladka
# odmalowuje sie RAZ, gdy zaden z jej krokow juz nie liczy.
function Po-Kroku([string]$id) {
  foreach ($w in @($WIDOK_KAWALKI.Keys)) { if (@($WIDOK_KAWALKI[$w]) -contains $id) { $script:DoOdmalowania[$w] = $true } }
  if (($id -eq "dane") -and $script:Ikona) {
    try { $script:Ikona.Text = Podpowiedz $script:Dane } catch { Zanotuj-Wywrotke "podpowiedz przy ikonie" $_ }
  }
  if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
  if ($script:Ladowanie) { return }
  Odswiez-Widoczne
}

function Odswiez-Widoczne {
  $w = $script:Widok
  if (-not $script:DoOdmalowania[$w]) { Odmaluj-Podtytul; return }
  foreach ($id in @($WIDOK_KAWALKI[$w])) { if (Krok-Trwa $script:StanKawalkow[$id].Krok) { Odmaluj-Podtytul; return } }
  Wyrenderuj-Widok $w
}

function Wyrenderuj-Widok([string]$w) {
  switch ($w) {
    "przeglad"  { Odmaluj-Okno }
    "szczegoly" {
      Odmaluj-Podtytul
      if (-not $script:SzczegolyZajete) {
        # Budowa kilkudziesieciu kart trwa ~1,3 s (zmierzone 30.09.2026) i musi isc
        # w watku okna. Za pierwszym razem najpierw jedno zdanie, zeby klikniecie
        # dalo znak od razu, a nie wygladalo na zawieszenie.
        if ($script:ListaSzczegolow -and ($script:ListaSzczegolow.Controls.Count -eq 0) -and $script:Okno.Visible) {
          Pokaz-Karty-Szczegolow @(Karta-Komunikatu "Układam zakładkę..." @("Kilkadziesiąt kart z liczbami - to trwa około sekundy.") $null)
          $script:Okno.Update()
        }
        Napelnij-Szczegoly
      }
    }
    "warstwy"   { Odmaluj-Podtytul; Napelnij-Warstwy }
    "skille" {
      Odmaluj-Podtytul
      # w trakcie operacji z przycisku lista stoi (zegar operacji ja odswiezy po koncu)
      $narysowana = $script:ListaSkilli -and ($script:ListaSkilli.Controls.Count -gt 0) -and ($script:ListaSkilli.Controls[0].Controls.Count -gt 0)
      if ($script:SkilleOperacjaOd -and $narysowana) { return }
      Napelnij-Skille
      if ($script:SkillePoOperacji -and $script:SkillePodglad -and -not $script:SkillePodglad.IsDisposed) {
        $script:SkillePodglad.Text = $script:SkillePoOperacji
        $script:SkillePodglad.SelectionStart = 0
        $script:SkillePodglad.ScrollToCaret()
      }
      $script:SkillePoOperacji = $null
    }
  }
}

# Wejscie do zakladki (takze przy otwarciu okna). Brak danych z dzis -> ekran
# ladowania; dane nieswieze -> zakladka od razu, odswiezenie po cichu. Przy
# otwarciu okna w tle rusza tez to, czego brakuje innym zakladkom - przelaczenie
# ma byc od razu.
function Wejdz-Do-Widoku([string]$widok, [bool]$otwarcie = $false) {
  if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
  if (($widok -eq "szczegoly") -and $script:SzczegolyZajete) { Ukryj-Ladowanie; return }
  $ids = @($WIDOK_KAWALKI[$widok])
  $kroki = @{}
  $brak = $false
  foreach ($id in $ids) {
    $b = Brakuje-Kawalka $id
    if ($b) { $brak = $true }
    if ($b -or (Nieswiezy-Kawalek $id)) { $kroki[$id] = Rusz-Krok $id }
    elseif (Krok-Trwa $script:StanKawalkow[$id].Krok) { $kroki[$id] = $script:StanKawalkow[$id].Krok }
  }
  if ($otwarcie) {
    foreach ($w in @("przeglad", "szczegoly", "warstwy", "skille")) {
      foreach ($id in @($WIDOK_KAWALKI[$w])) { if (Brakuje-Kawalka $id) { [void](Rusz-Krok $id) } }
    }
  }
  # Kroki ogladanej zakladki na poczatek kolejki - nie czekaja za tlem innych zakladek.
  foreach ($id in @($ids)[($ids.Count - 1)..0]) {
    $k = $script:StanKawalkow[$id].Krok
    if ($k -and ($k.Stan -eq "czeka") -and $script:KolejkaKrokow.Contains($k)) {
      $script:KolejkaKrokow.Remove($k)
      $script:KolejkaKrokow.Insert(0, $k)
    }
  }
  Obsluz-Kroki
  if ($brak) { Pokaz-Ladowanie $widok $ids $kroki; return }
  Ukryj-Ladowanie
  if ($script:DoOdmalowania[$widok]) { Wyrenderuj-Widok $widok } else { Odmaluj-Podtytul }
}

# Recznie zlecone przeliczenie (menu, po pobraniu nowszej wersji): Przeglad zostaje
# na ekranie, liczy sie w tle i odmalowuje raz na koncu.
function Przelicz-W-Tle([string]$kodDanych = "") {
  $k = Rusz-Krok "dane" $kodDanych
  [void](Rusz-Krok "start")
  [void](Rusz-Krok "zuzycie")
  return $k
}

# --- ekran ladowania -----------------------------------------------------------
# Biala karta na miejscu zakladki: tytul, jedno zdanie, pasek postepu i lista
# krokow - kazdy z kolkiem (czeka), obracajacym sie znakiem (liczy), ptaszkiem
# (gotowe), wykrzyknikiem (gotowe z powodem) albo krzyzykiem (nie udalo sie / po
# limicie), z czasem po prawej i powodem po ludzku pod spodem. Wiersze maja stale
# wymiary - zmienia sie tylko tekst, wiec nic nie skacze.
$ZNAK_CZEKA = [string][char]0x25CB
$ZNAKI_LICZY = @([string][char]0x25D0, [string][char]0x25D3, [string][char]0x25D1, [string][char]0x25D2)
$ZNAK_OK = [string][char]0x2713
$ZNAK_BLAD = [string][char]0x2717

function Zbuduj-Ladowanie {
  $p = New-Object System.Windows.Forms.Panel
  $p.Dock = [System.Windows.Forms.DockStyle]::Fill
  $p.AutoScroll = $true
  $p.BackColor = $script:TloOkna
  $p.Padding = New-Object System.Windows.Forms.Padding($script:Margines, 4, $script:Margines, 8)
  $p.Visible = $false
  $root = Pionowy $script:SzerTresc
  $root.Dock = [System.Windows.Forms.DockStyle]::Top
  $karta = Nowa-Karta $script:SzerKarty
  $karta.Padding = New-Object System.Windows.Forms.Padding(28, 22, 28, 22)
  $szer = $script:SzerKarty - 56
  $script:LLadowanieTytul = Etykieta "Wczytuję dane" $script:CzTytul $script:KolTekst
  $script:LLadowanieOpis = Etykieta-Zawijana "" $script:CzZwykla $script:KolSzary $szer
  $script:LLadowanieOpis.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
  $script:PasekLadowania = New-Object System.Windows.Forms.PictureBox
  $script:PasekLadowania.Size = New-Object System.Drawing.Size($szer, 8)
  $script:PasekLadowania.Margin = New-Object System.Windows.Forms.Padding(0, 16, 0, 18)
  $script:PasekLadowania.Add_Paint({ param($nadawca, $e) Rysuj-Pasek-Ladowania $e.Graphics $nadawca.ClientSize })
  $script:ListaKrokow = Pionowy $szer
  $script:LLadowanieStopka = Etykieta-Zawijana "" $script:CzMala $script:KolSzary $szer
  $script:LLadowanieStopka.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
  $script:BPokazTeraz = New-Object System.Windows.Forms.Button
  $script:BPokazTeraz.Text = "Pokaż od razu"
  $script:BPokazTeraz.Font = $script:CzZwykla
  $script:BPokazTeraz.FlatStyle = [System.Windows.Forms.FlatStyle]::System
  $script:BPokazTeraz.Size = New-Object System.Drawing.Size(160, 32)
  $script:BPokazTeraz.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
  $script:BPokazTeraz.Visible = $false
  $script:BPokazTeraz.Add_Click({
    try { if ($script:Ladowanie) { $script:Ladowanie.Od_Razu = $true; Sprawdz-Ladowanie } }
    catch { Zanotuj-Wywrotke "przycisk Pokaz od razu" $_ }
  })
  foreach ($c in @($script:LLadowanieTytul, $script:LLadowanieOpis, $script:PasekLadowania, $script:ListaKrokow, $script:LLadowanieStopka, $script:BPokazTeraz)) { $karta.Controls.Add($c) }
  $root.Controls.Add($karta)
  $p.Controls.Add($root)
  return $p
}

function Rysuj-Pasek-Ladowania($g, $rozmiar) {
  try {
    $w = [int]$rozmiar.Width; $h = [int]$rozmiar.Height
    $tlo = New-Object System.Drawing.SolidBrush($script:KolCc)
    $pel = New-Object System.Drawing.SolidBrush($script:KolMr)
    try {
      $g.FillRectangle($tlo, 0, 0, $w, $h)
      $g.FillRectangle($pel, 0, 0, [int]($w * [math]::Min(1.0, [math]::Max(0.0, $script:PostepLadowania))), $h)
    } finally { $tlo.Dispose(); $pel.Dispose() }
  } catch {
    if (-not $script:RysowanieZawiodlo) { $script:RysowanieZawiodlo = $true; Zanotuj-Wywrotke "rysowanie paska postepu" $_ }
  }
}

function Wiersz-Kroku([string]$id, [int]$szer) {
  $kol = Pionowy $szer
  $w = Poziomy
  $z = Etykieta $ZNAK_CZEKA $script:CzGruba $script:KolSzary
  $z.AutoSize = $false; $z.Size = New-Object System.Drawing.Size(28, 26); $z.Margin = New-Object System.Windows.Forms.Padding(0)
  $n = Etykieta $KAWALKI[$id].Napis $script:CzZwykla $script:KolTekst
  $n.AutoSize = $false; $n.Size = New-Object System.Drawing.Size(($szer - 28 - 250), 26); $n.Margin = New-Object System.Windows.Forms.Padding(0)
  $n.UseMnemonic = $false
  $s = Etykieta "" $script:CzZwykla $script:KolSzary
  $s.AutoSize = $false; $s.Size = New-Object System.Drawing.Size(250, 26); $s.Margin = New-Object System.Windows.Forms.Padding(0)
  $s.TextAlign = [System.Drawing.ContentAlignment]::TopRight
  $w.Controls.Add($z); $w.Controls.Add($n); $w.Controls.Add($s)
  $d = Etykieta-Zawijana "" $script:CzMala $script:KolPilne ($szer - 28)
  $d.Margin = New-Object System.Windows.Forms.Padding(28, 0, 0, 8)
  $d.UseMnemonic = $false
  $d.Visible = $false
  $kol.Controls.Add($w); $kol.Controls.Add($d)
  $script:WierszeKrokow[$id] = @{ Znak = $z; Napis = $n; Stan = $s; Szczegol = $d }
  return $kol
}

function Pokaz-Ladowanie([string]$widok, $ids, $kroki) {
  if (-not $script:WidokLadowania -or $script:WidokLadowania.IsDisposed) { return }
  $script:Ladowanie = [pscustomobject]@{ Widok = $widok; Kawalki = @($ids); Kroki = $kroki; Od = [datetime]::Now; BladOd = $null; Od_Razu = $false }
  $szer = $script:SzerKarty - 56
  $script:WidokLadowania.SuspendLayout()
  try {
    Wyczysc-Panel $script:ListaKrokow
    $script:WierszeKrokow = @{}
    foreach ($id in $ids) { $script:ListaKrokow.Controls.Add((Wiersz-Kroku $id $szer)) }
    if ($widok -eq "przeglad") {
      if ((-not $script:DaneCzas) -or ($script:DaneCzas.Date -ne [datetime]::Today) -or (-not $script:Start)) { $o = "Pierwsze otwarcie dziś - liczę wszystko od nowa. Zwykle trwa to kilka sekund." }
      else { $o = "Części liczb nie ma jeszcze z dzisiaj - liczę je teraz. Zwykle trwa to kilka sekund." }
    } else {
      $o = "Zakładka `„$($NAZWY_WIDOKOW[$widok])`” potrzebuje danych, których jeszcze nie ma - zbieram je."
    }
    $script:LLadowanieOpis.Text = "$o Okno możesz w tym czasie przesuwać i przełączać zakładki - liczenie idzie w tle."
    $script:BPokazTeraz.Visible = $false
    Odmaluj-Kroki
    $script:WidokLadowania.Visible = $true
  } finally { $script:WidokLadowania.ResumeLayout($true) }
  Odmaluj-Podtytul
}

function Ukryj-Ladowanie {
  $script:Ladowanie = $null
  if ($script:WidokLadowania -and -not $script:WidokLadowania.IsDisposed) { $script:WidokLadowania.Visible = $false }
}

function Ustaw-Tekst($kontrolka, [string]$tekst, $kolor) {
  if ($kontrolka.Text -ne $tekst) { $kontrolka.Text = $tekst }
  if ($kolor -and ($kontrolka.ForeColor -ne $kolor)) { $kontrolka.ForeColor = $kolor }
}

function Sekundy-Ludzko([double]$s) {
  $pl = [System.Globalization.CultureInfo]::GetCultureInfo("pl-PL")
  if ($s -lt 10) { return ($s.ToString("0.0", $pl) + " s") }
  return ([int][math]::Round($s)).ToString() + " s"
}

# Odmalowanie wierszy - tylko teksty i kolory, bez przebudowy (wolane co 150 ms).
function Odmaluj-Kroki {
  $l = $script:Ladowanie
  if (-not $l) { return }
  $script:TykKrokow++
  $teraz = [datetime]::Now
  $suma = 0.0
  foreach ($id in $l.Kawalki) {
    $r = $script:WierszeKrokow[$id]
    if (-not $r) { continue }
    $k = $l.Kroki[$id]
    $szczegol = ""
    if (-not $k) {
      $c = Czas-Kawalka $id
      Ustaw-Tekst $r.Znak $ZNAK_OK $script:KolDobrze
      Ustaw-Tekst $r.Stan $(if ($c) { "gotowe wcześniej (z $($c.ToString('HH:mm')))" } else { "gotowe" }) $script:KolSzary
      $suma += 1.0
    } else {
      switch ($k.Stan) {
        "czeka" { Ustaw-Tekst $r.Znak $ZNAK_CZEKA $script:KolSzary; Ustaw-Tekst $r.Stan "czeka na swoją kolej" $script:KolSzary }
        { ($_ -eq "otwiera") -or ($_ -eq "liczy") } {
          $s = 0.0; if ($k.Od) { $s = ($teraz - $k.Od).TotalSeconds }
          Ustaw-Tekst $r.Znak $ZNAKI_LICZY[[int]([math]::Floor($script:TykKrokow / 2)) % 4] $script:KolMr
          Ustaw-Tekst $r.Stan "liczę... $(Sekundy-Ludzko $s)" $script:KolTekst
          $zw = [double]$KAWALKI[$id].Zwykle
          if ($script:CzasyKrokow.ContainsKey($id)) { $zw = [math]::Max(0.5, [double]$script:CzasyKrokow[$id]) }
          $suma += [math]::Min(0.9, $s / (1.5 * $zw))
        }
        "ok" { Ustaw-Tekst $r.Znak $ZNAK_OK $script:KolDobrze; Ustaw-Tekst $r.Stan "gotowe ($(Sekundy-Ludzko (($k.Koniec - $k.Od).TotalSeconds)))" $script:KolSzary; $suma += 1.0 }
        "uwaga" {
          Ustaw-Tekst $r.Znak "!" $script:KolUwaga; Ustaw-Tekst $r.Stan "gotowe, ale z uwagą" $script:KolUwaga; $suma += 1.0
          $szczegol = $k.Powod
        }
        "blad" { Ustaw-Tekst $r.Znak $ZNAK_BLAD $script:KolPilne; Ustaw-Tekst $r.Stan "nie udało się" $script:KolPilne; $suma += 1.0; $szczegol = $k.Powod }
        "czas" { Ustaw-Tekst $r.Znak $ZNAK_BLAD $script:KolPilne; Ustaw-Tekst $r.Stan "przerwane po $($k.Limit) s" $script:KolPilne; $suma += 1.0; $szczegol = $k.Powod }
      }
    }
    if ($szczegol) {
      $kolS = $script:KolPilne; if ($k.Stan -eq "uwaga") { $kolS = $script:KolUwaga }
      Ustaw-Tekst $r.Szczegol ((Z-Wielkiej $szczegol).TrimEnd('.') + ".") $kolS
      if (-not $r.Szczegol.Visible) { $r.Szczegol.Visible = $true }
    } elseif ($r.Szczegol.Visible) { $r.Szczegol.Visible = $false }
  }
  $n = [math]::Max(1, @($l.Kawalki).Count)
  $p = $suma / $n
  if ([math]::Abs($p - $script:PostepLadowania) -gt 0.001) { $script:PostepLadowania = $p; $script:PasekLadowania.Invalidate() }
  if ($l.BladOd) {
    $zostalo = [int][math]::Max(0.0, [math]::Ceiling([double]$SEKUNDY_PO_BLEDZIE - ($teraz - $l.BladOd).TotalSeconds))
    Ustaw-Tekst $script:LLadowanieStopka "Nie wszystko się udało - powód stoi przy kroku wyżej. Resztę pokażę za $([math]::Max(0, $zostalo)) s; ten sam powód zostanie w karcie i w zakładce Szczegóły." $script:KolUwaga
  } else {
    $lim = ($l.Kawalki | ForEach-Object { $KAWALKI[$_].Limit } | Measure-Object -Maximum).Maximum
    Ustaw-Tekst $script:LLadowanieStopka "Żaden krok nie liczy się bez końca: najdłużej po $lim s przerywam go i piszę tu, dlaczego." $script:KolSzary
  }
}

# Czy ekran ladowania moze zejsc: wszystkie kroki tej zakladki skonczone. Gdy ktorys
# sie nie udal, ekran stoi jeszcze $SEKUNDY_PO_BLEDZIE s (albo do "Pokaz od razu").
# Karty buduja sie POD ekranem ladowania i dopiero potem on znika - jedno odmalowanie.
function Sprawdz-Ladowanie {
  $l = $script:Ladowanie
  if (-not $l) { return }
  Odmaluj-Kroki
  $zle = $false
  foreach ($id in $l.Kawalki) {
    $k = $l.Kroki[$id]
    if (-not $k) { continue }
    if (Krok-Trwa $k) { return }
    if ($k.Stan -ne "ok") { $zle = $true }
  }
  if ($zle) {
    if (-not $l.BladOd) {
      $l.BladOd = [datetime]::Now
      $script:BPokazTeraz.Visible = $true
      Odmaluj-Kroki
      return
    }
    if ((-not $l.Od_Razu) -and ((([datetime]::Now) - $l.BladOd).TotalSeconds -lt $SEKUNDY_PO_BLEDZIE)) { return }
  }
  $w = $l.Widok
  if ($w -eq $script:Widok) { Wyrenderuj-Widok $w }
  Ukryj-Ladowanie
  Odmaluj-Podtytul
}

# Ostatnia deska ratunku: ekran ladowania, ktory stoi dluzej niz najdluzszy limit
# jego krokow + czas na przeczytanie bledu + 15 s zapasu, zdejmujemy sila - cos
# poszlo nie tak w samym oknie (np. wywrotka w Obsluz-Kroki przy kazdym tyknieciu).
# Nie po cichu: wywrotka do dziennika i zolta karta "nie udalo sie przeliczyc".
function Straznik-Ladowania {
  $l = $script:Ladowanie
  if (-not $l) { return }
  $lim = ($l.Kawalki | ForEach-Object { $KAWALKI[$_].Limit } | Measure-Object -Maximum).Maximum + $SEKUNDY_PO_BLEDZIE + 15
  $minelo = ([datetime]::Now - $l.Od).TotalSeconds
  if ($minelo -le $lim) { return }
  $pw = "ekran ładowania stał ponad $lim s, więc zdjąłem go awaryjnie - część liczb może być niepełna (szczegóły w dzienniku nadzorcy)"
  Zanotuj-Wywrotke "ekran ladowania" $pw
  $script:DaneBlad = $pw
  Ukryj-Ladowanie
  try { Wyrenderuj-Widok $script:Widok } catch { Zanotuj-Wywrotke "odmalowanie po zdjeciu ekranu ladowania" $_ }
}

# Ekran pod kursorem - tam jest ikona, ktora wlasnie kliknieto.
function Obszar-Okna {
  try { return [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea }
  catch { Zanotuj-Wywrotke "ekran pod kursorem" $_; return [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea }
}

# --- budowa okna -------------------------------------------------------------

function Pokaz-Okno {
  if ($script:Okno -and -not $script:Okno.IsDisposed) {
    $script:Okno.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $script:Okno.Show()
    Wymus-Pokazanie $script:Okno
    Wejdz-Do-Widoku $script:Widok
    return
  }

  $f = New-Object System.Windows.Forms.Form
  $f.Text = "MegaRuchacz"
  $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
  $f.MaximizeBox = $false
  # STALY ROZMIAR OD PIERWSZEJ CHWILI (P21): wysokosc z ekranu, raz - okno nie
  # rosnie ani nie skacze w miare dochodzenia danych. Polozenie: tam, gdzie
  # uzytkownik zostawil okno ostatnio (gdy nadal miesci sie na ktoryms ekranie),
  # inaczej srodek ekranu pod kursorem.
  $obszar = Obszar-Okna
  $f.ClientSize = New-Object System.Drawing.Size($script:SzerOkna, 720)
  $f.Height = [int][math]::Min($WYS_OKNA_MAX, $obszar.Height - 40)
  $f.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
  $poz = New-Object System.Drawing.Point(($obszar.Left + [int](($obszar.Width - $f.Width) / 2)), ($obszar.Top + [int](($obszar.Height - $f.Height) / 2)))
  if ($script:PolozenieOkna) {
    $prost = New-Object System.Drawing.Rectangle($script:PolozenieOkna, $f.Size)
    foreach ($ekran in [System.Windows.Forms.Screen]::AllScreens) {
      if ($ekran.WorkingArea.Contains($prost)) { $poz = $script:PolozenieOkna; break }
    }
  }
  $f.Location = $poz
  $f.BackColor = $script:TloOkna
  $f.Font = $script:CzZwykla
  try { $f.Icon = Ikona-Nadzorcy } catch { Zanotuj-Wywrotke "ikona okna" $_ }

  # Pasek przyciskow siedzi na formularzu, a nie w przewijanej tresci - ma byc
  # pod reka zawsze, w obu widokach.
  $script:Pasek = New-Object System.Windows.Forms.TableLayoutPanel
  $script:Pasek.Dock = [System.Windows.Forms.DockStyle]::Bottom
  $script:Pasek.AutoSize = $true
  $script:Pasek.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
  $script:Pasek.ColumnCount = 3
  $script:Pasek.RowCount = 2
  $script:Pasek.Padding = New-Object System.Windows.Forms.Padding($script:Margines, 14, $script:Margines, 14)
  $script:Pasek.BackColor = $script:TloPaska
  $script:Pasek.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 39))) | Out-Null
  $script:Pasek.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 39))) | Out-Null
  $script:Pasek.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 22))) | Out-Null
  $script:Pasek.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38))) | Out-Null
  $script:Pasek.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null
  # cienka kreska nad paskiem - oddziela przyciski od tresci bez ciezkiej ramki
  $script:Pasek.Add_Paint({ param($nadawca, $e) try { $e.Graphics.DrawLine($script:PioroRamki, 0, 0, $nadawca.Width, 0) } catch { if (-not $script:RamkaZawiodla) { $script:RamkaZawiodla = $true; Zanotuj-Wywrotke "rysowanie kreski nad przyciskami" $_ } } })

  $script:BAktualizuj = Nowy-Przycisk "Sprawdź i pobierz nowszą wersję MegaRuchacza"
  $script:BCykl       = Nowy-Przycisk "Przeczytaj teraz nowe rozmowy"
  $bZamknij           = Nowy-Przycisk "Zamknij okno"
  $szerOpisu = [int]($script:SzerOkna * 0.39) - 24
  $script:LAktualizuj = Etykieta-Zawijana "" $script:CzMala $script:KolSzary $szerOpisu
  $script:LCykl       = Etykieta-Zawijana "" $script:CzMala $script:KolSzary $szerOpisu
  $lZamknij           = Etykieta-Zawijana "Ikona w zasobniku zostaje i pilnuje dalej." $script:CzMala $script:KolSzary 160

  $script:Pasek.Controls.Add($script:BAktualizuj, 0, 0)
  $script:Pasek.Controls.Add($script:BCykl, 1, 0)
  $script:Pasek.Controls.Add($bZamknij, 2, 0)
  $script:Pasek.Controls.Add($script:LAktualizuj, 0, 1)
  $script:Pasek.Controls.Add($script:LCykl, 1, 1)
  $script:Pasek.Controls.Add($lZamknij, 2, 1)

  # Naglowek: tytul i podtytul po lewej, przelacznik widokow po prawej.
  $script:Naglowek = New-Object System.Windows.Forms.Panel
  $script:Naglowek.Dock = [System.Windows.Forms.DockStyle]::Top
  $script:Naglowek.Height = 88
  $script:Naglowek.BackColor = $script:TloOkna
  $lTytul = Etykieta "MegaRuchacz" $script:CzTytul $script:KolTekst
  $lTytul.Location = New-Object System.Drawing.Point(($script:Margines - 3), 14)
  $script:LPodtytul = Etykieta-Zawijana "Przeliczam, to potrwa kilka sekund..." $script:CzZwykla $script:KolSzary ($script:SzerOkna - 2 * $script:Margines)
  $script:LPodtytul.Location = New-Object System.Drawing.Point($script:Margines, 54)
  # Przelacznik trzech widokow na linii tytulu, po prawej; podtytul biegnie pod
  # nim na cala szerokosc.
  # P18: czwarty przycisk "Skille" - panel szerszy o 104 px (100 px przycisku + 4 odstepu).
  $przel = New-Object System.Windows.Forms.Panel
  $przel.Size = New-Object System.Drawing.Size(530, 38)
  $przel.Location = New-Object System.Drawing.Point(($script:SzerOkna - $script:Margines - 530), 10)
  $przel.BackColor = $script:TloPrzel
  $script:BPrzeglad  = Przycisk-Przelacznika "Przegląd" 3 124
  $script:BSzczegoly = Przycisk-Przelacznika "Szczegóły" 131 124
  $script:BWarstwy   = Przycisk-Przelacznika "Warstwy pamięci" 259 164
  $script:BSkille    = Przycisk-Przelacznika "Skille" 427 100
  $przel.Controls.Add($script:BPrzeglad)
  $przel.Controls.Add($script:BSzczegoly)
  $przel.Controls.Add($script:BWarstwy)
  $przel.Controls.Add($script:BSkille)
  $script:Naglowek.Controls.Add($lTytul)
  $script:Naglowek.Controls.Add($script:LPodtytul)
  $script:Naglowek.Controls.Add($przel)

  # Widok przegladu: karty jedna pod druga. Przewija sie wylacznie wtedy, gdy
  # ekran jest nizszy niz tresc - wtedy nic nie znika pod krawedzia.
  $script:WidokPrzeglad = New-Object System.Windows.Forms.Panel
  $script:WidokPrzeglad.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:WidokPrzeglad.AutoScroll = $true
  $script:WidokPrzeglad.BackColor = $script:TloOkna
  $script:WidokPrzeglad.Padding = New-Object System.Windows.Forms.Padding($script:Margines, 4, $script:Margines, 8)

  $script:Root = Pionowy $script:SzerTresc
  $script:Root.Dock = [System.Windows.Forms.DockStyle]::Top

  $script:PanelProblemy = Pionowy $script:SzerTresc
  $script:PanelProblemy.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
  $script:PanelProblemy.Visible = $false

  $script:KartaWerdykt = Nowa-Karta $script:SzerKarty
  $script:KartaStart = Nowa-Karta $script:SzerKarty

  $script:PanelLiczby = Poziomy
  $script:PanelLiczby.Margin = New-Object System.Windows.Forms.Padding(0)

  # Wykres to dalszy ciag karty nauki (P15): bez gornej kreski i bez odstepu,
  # dolna kreska karty nauki robi za przedzialke. Okno ma sie zmiescic na
  # ekranie bez przewijania - osobna karta kosztowala ~40 px. Gdy karty nauki
  # nie ma (nie dalo sie jej zlozyc), wykres rysuje pelna ramke sam.
  $script:KartaStat = Pionowy $script:SzerKarty
  $script:KartaStat.BackColor = $script:TloKarty
  $script:KartaStat.Padding = New-Object System.Windows.Forms.Padding(22, 10, 22, 16)
  $script:KartaStat.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)
  $script:KartaStat.Add_Paint({ param($nadawca, $e) Obrysuj-Ciag-Dalszy $nadawca $e })
  $script:PanelStan = Nowa-Karta $script:SzerKarty
  $script:PanelStan.Margin = New-Object System.Windows.Forms.Padding(0)

  $script:Root.Controls.Add($script:KartaWerdykt)
  $script:Root.Controls.Add($script:PanelProblemy)
  $script:Root.Controls.Add($script:KartaStart)
  $script:Root.Controls.Add($script:PanelLiczby)
  $script:Root.Controls.Add($script:KartaStat)
  $script:Root.Controls.Add($script:PanelStan)
  $script:WidokPrzeglad.Controls.Add($script:Root)

  # Widok szczegolow: ten sam obszar, karty sekcji jedna pod druga, przewijane
  # w miejscu - okno nie rosnie od tego ani o piksel.
  $script:WidokSzczegoly = New-Object System.Windows.Forms.Panel
  $script:WidokSzczegoly.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:WidokSzczegoly.AutoScroll = $true
  $script:WidokSzczegoly.BackColor = $script:TloOkna
  $script:WidokSzczegoly.Padding = New-Object System.Windows.Forms.Padding($script:Margines, 4, $script:Margines, 12)
  $script:WidokSzczegoly.Visible = $false
  $script:ListaSzczegolow = Pionowy $script:SzerTresc
  $script:ListaSzczegolow.Dock = [System.Windows.Forms.DockStyle]::Top
  $script:WidokSzczegoly.Controls.Add($script:ListaSzczegolow)

  # Widok warstw pamieci: zdanie podsumowania u gory, pod nim dwie biale karty -
  # lista warstw pogrupowana wedlug tego, kiedy sie wczytuja, i podglad tylko
  # do odczytu. Ten sam obszar co pozostale widoki, okno nie rosnie.
  $script:WidokWarstwy = New-Object System.Windows.Forms.Panel
  $script:WidokWarstwy.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:WidokWarstwy.BackColor = $script:TloOkna
  $script:WidokWarstwy.Padding = New-Object System.Windows.Forms.Padding($script:Margines, 4, $script:Margines, 14)
  $script:WidokWarstwy.Visible = $false

  $script:LWarstwy = New-Object System.Windows.Forms.Label
  $script:LWarstwy.AutoSize = $false
  $script:LWarstwy.UseMnemonic = $false
  $script:LWarstwy.Dock = [System.Windows.Forms.DockStyle]::Top
  $script:LWarstwy.Height = 44
  $script:LWarstwy.Font = $script:CzZwyklaGruba
  $script:LWarstwy.ForeColor = $script:KolTekst
  $script:LWarstwy.BackColor = [System.Drawing.Color]::Transparent
  $script:LWarstwy.Text = "Zbieram listę warstw pamięci..."

  $cialoW = New-Object System.Windows.Forms.Panel
  $cialoW.Dock = [System.Windows.Forms.DockStyle]::Fill
  $cialoW.BackColor = $script:TloOkna

  $kartaLista = New-Object System.Windows.Forms.Panel
  $kartaLista.Dock = [System.Windows.Forms.DockStyle]::Left
  $kartaLista.Width = [int]($script:SzerTresc * 0.48)
  $kartaLista.BackColor = $script:TloKarty
  $kartaLista.Padding = New-Object System.Windows.Forms.Padding(1)
  $kartaLista.Add_Paint({ param($nadawca, $e) Obrysuj $nadawca $e })
  $script:ListaWarstw = New-Object System.Windows.Forms.ListView
  $script:ListaWarstw.View = [System.Windows.Forms.View]::Details
  $script:ListaWarstw.FullRowSelect = $true
  $script:ListaWarstw.HideSelection = $false
  $script:ListaWarstw.MultiSelect = $false
  $script:ListaWarstw.ShowGroups = $true
  $script:ListaWarstw.ShowItemToolTips = $true
  $script:ListaWarstw.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
  $script:ListaWarstw.BorderStyle = [System.Windows.Forms.BorderStyle]::None
  $script:ListaWarstw.Font = $script:CzZwykla
  $script:ListaWarstw.BackColor = $script:TloKarty
  $script:ListaWarstw.ForeColor = $script:KolTekst
  $script:ListaWarstw.Dock = [System.Windows.Forms.DockStyle]::Fill
  # Wyzsze wiersze: WinForms nie ma na to wlasciwosci, ale wysokosc wiersza
  # idzie za wysokoscia obrazka z SmallImageList - pusty obrazek 1 x 26 px
  # daje liste, ktora sie czyta, a nie mruzy oczy.
  $wierszWys = New-Object System.Windows.Forms.ImageList
  $wierszWys.ImageSize = New-Object System.Drawing.Size(1, 26)
  $script:ListaWarstw.SmallImageList = $wierszWys
  [void]$script:ListaWarstw.Columns.Add("Warstwa", ($kartaLista.Width - 100 - 116 - 26))
  [void]$script:ListaWarstw.Columns.Add("Trwałość", 100)
  [void]$script:ListaWarstw.Columns.Add("Rozmiar", 116)
  $kartaLista.Controls.Add($script:ListaWarstw)

  $odstepW = New-Object System.Windows.Forms.Panel
  $odstepW.Dock = [System.Windows.Forms.DockStyle]::Left
  $odstepW.Width = 14
  $odstepW.BackColor = $script:TloOkna

  $kartaPodglad = New-Object System.Windows.Forms.Panel
  $kartaPodglad.Dock = [System.Windows.Forms.DockStyle]::Fill
  $kartaPodglad.BackColor = $script:TloKarty
  $kartaPodglad.Padding = New-Object System.Windows.Forms.Padding(18, 14, 6, 6)
  $kartaPodglad.Add_Paint({ param($nadawca, $e) Obrysuj $nadawca $e })
  $script:PodgladWarstwy = New-Object System.Windows.Forms.TextBox
  $script:PodgladWarstwy.Multiline = $true
  $script:PodgladWarstwy.ReadOnly = $true
  # CLAUDE.md i mapa potrafia miec po kilkadziesiat tysiecy znakow - domyslny
  # sufit pola (32 767) nie ma prawa uciac konca pliku po cichu
  $script:PodgladWarstwy.MaxLength = [int]::MaxValue
  $script:PodgladWarstwy.WordWrap = $true
  $script:PodgladWarstwy.BorderStyle = [System.Windows.Forms.BorderStyle]::None
  $script:PodgladWarstwy.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
  # Consolas 9, a nie 9.5: pliki maja twarde lamanie ~80 znakow i przy 9.5 kazda
  # dluzsza linia zostawiala sierote w nastepnym wierszu
  $script:PodgladWarstwy.Font = $script:CzStalaMala
  $script:PodgladWarstwy.BackColor = $script:TloKarty
  $script:PodgladWarstwy.ForeColor = $script:KolTekst
  $script:PodgladWarstwy.Dock = [System.Windows.Forms.DockStyle]::Fill
  $kartaPodglad.Controls.Add($script:PodgladWarstwy)
  $script:PodgladInfo = Pionowy 0
  $script:PodgladInfo.Dock = [System.Windows.Forms.DockStyle]::Top
  $script:PodgladInfo.BackColor = $script:TloKarty
  $kartaPodglad.Controls.Add($script:PodgladInfo)

  # Dokowanie od ostatnio dodanej: wypelniajacy podglad pierwszy, potem odstep,
  # na koncu lista - ona dokuje sie pierwsza, czyli najbardziej z lewej.
  $cialoW.Controls.Add($kartaPodglad)
  $cialoW.Controls.Add($odstepW)
  $cialoW.Controls.Add($kartaLista)
  $script:WidokWarstwy.Controls.Add($cialoW)
  $script:WidokWarstwy.Controls.Add($script:LWarstwy)

  # Widok skilli (P18): u gory zdanie o bezpieczenstwie z podsumowaniem i przycisk
  # "Sprawdz teraz", pod nimi lista (wiersze z zawinietym opisem, pogrupowane wedlug
  # zrodla) i karta szczegolow z przyciskami. Ten sam obszar, okno nie rosnie.
  $script:WidokSkille = New-Object System.Windows.Forms.Panel
  $script:WidokSkille.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:WidokSkille.BackColor = $script:TloOkna
  $script:WidokSkille.Padding = New-Object System.Windows.Forms.Padding($script:Margines, 4, $script:Margines, 14)
  $script:WidokSkille.Visible = $false

  # Gora: po lewej zdanie o bezpieczenstwie (szare, stale) i pod nim podsumowanie
  # (kolor wedlug stanu), po prawej przycisk. Zdanie o bezpieczenstwie nie czerwienieje
  # przy bledzie - czerwone jest tylko to, co naprawde sie nie udalo.
  $goraS = New-Object System.Windows.Forms.Panel
  $goraS.Dock = [System.Windows.Forms.DockStyle]::Top
  $goraS.Height = 64
  $goraS.BackColor = $script:TloOkna
  $prawaS = New-Object System.Windows.Forms.Panel
  $prawaS.Dock = [System.Windows.Forms.DockStyle]::Right
  $prawaS.Width = 164
  $prawaS.Padding = New-Object System.Windows.Forms.Padding(14, 2, 0, 0)
  $script:BSkilleTeraz = New-Object System.Windows.Forms.Button
  $script:BSkilleTeraz.Text = "Sprawdź teraz"
  $script:BSkilleTeraz.Font = $script:CzZwykla
  $script:BSkilleTeraz.FlatStyle = [System.Windows.Forms.FlatStyle]::System
  $script:BSkilleTeraz.Height = 34
  $script:BSkilleTeraz.Dock = [System.Windows.Forms.DockStyle]::Top
  $prawaS.Controls.Add($script:BSkilleTeraz)
  $lewaS = Pionowy 0
  $lewaS.Dock = [System.Windows.Forms.DockStyle]::Fill
  $lewaS.AutoSize = $false
  $szerZdania = $script:SzerTresc - 164 - 4
  $lBezp = Etykieta-Zawijana $ZDANIE_BEZPIECZENSTWA $script:CzMala $script:KolSzary $szerZdania
  $lBezp.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
  $script:LSkille = Etykieta-Zawijana "Zbieram listę skilli..." $script:CzZwyklaGruba $script:KolTekst $szerZdania
  $script:LSkille.UseMnemonic = $false
  $lewaS.Controls.Add($lBezp)
  $lewaS.Controls.Add($script:LSkille)
  $goraS.Controls.Add($lewaS)
  $goraS.Controls.Add($prawaS)
  # Wysokosc gory idzie za tekstem - podsumowanie nie ma prawa uciac sie pod lista.
  $script:LSkille.Add_SizeChanged({ param($nadawca, $e) try { $nadawca.Parent.Parent.Height = [math]::Max(48, $nadawca.Bottom + 12) } catch { Zanotuj-Wywrotke "wysokosc podsumowania skilli" $_ } })

  $cialoS = New-Object System.Windows.Forms.Panel
  $cialoS.Dock = [System.Windows.Forms.DockStyle]::Fill
  $cialoS.BackColor = $script:TloOkna

  $kartaListaS = New-Object System.Windows.Forms.Panel
  $kartaListaS.Dock = [System.Windows.Forms.DockStyle]::Left
  $kartaListaS.Width = [int]($script:SzerTresc * 0.56)
  $kartaListaS.BackColor = $script:TloKarty
  $kartaListaS.Padding = New-Object System.Windows.Forms.Padding(1)
  $kartaListaS.Add_Paint({ param($nadawca, $e) Obrysuj $nadawca $e })
  $script:ListaSkilli = New-Object System.Windows.Forms.Panel
  $script:ListaSkilli.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:ListaSkilli.AutoScroll = $true
  $script:ListaSkilli.BackColor = $script:TloKarty
  $wnetrzeS = Pionowy 0
  $wnetrzeS.Location = New-Object System.Drawing.Point(0, 0)
  $script:ListaSkilli.Controls.Add($wnetrzeS)
  $kartaListaS.Controls.Add($script:ListaSkilli)

  $odstepS = New-Object System.Windows.Forms.Panel
  $odstepS.Dock = [System.Windows.Forms.DockStyle]::Left
  $odstepS.Width = 14
  $odstepS.BackColor = $script:TloOkna

  $kartaInfoS = New-Object System.Windows.Forms.Panel
  $kartaInfoS.Dock = [System.Windows.Forms.DockStyle]::Fill
  $kartaInfoS.BackColor = $script:TloKarty
  $kartaInfoS.Padding = New-Object System.Windows.Forms.Padding(18, 14, 6, 6)
  $kartaInfoS.Add_Paint({ param($nadawca, $e) Obrysuj $nadawca $e })
  $script:SkillePodglad = New-Object System.Windows.Forms.TextBox
  $script:SkillePodglad.Multiline = $true
  $script:SkillePodglad.ReadOnly = $true
  $script:SkillePodglad.MaxLength = [int]::MaxValue
  $script:SkillePodglad.WordWrap = $true
  $script:SkillePodglad.BorderStyle = [System.Windows.Forms.BorderStyle]::None
  $script:SkillePodglad.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
  $script:SkillePodglad.Font = $script:CzMala
  $script:SkillePodglad.BackColor = $script:TloKarty
  $script:SkillePodglad.ForeColor = $script:KolTekst
  $script:SkillePodglad.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:SkillePrzyciski = Poziomy
  $script:SkillePrzyciski.Dock = [System.Windows.Forms.DockStyle]::Top
  $script:SkillePrzyciski.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 10)
  $script:BSkillInstaluj = New-Object System.Windows.Forms.Button
  $script:BSkillAktualizuj = New-Object System.Windows.Forms.Button
  $script:BSkillCofnij = New-Object System.Windows.Forms.Button
  $script:BSkillUsun = New-Object System.Windows.Forms.Button
  # "Usun u mnie" stoi w miejscu "Aktualizuj teraz" (widac zawsze jeden z nich) -
  # rzad przyciskow nie robi sie szerszy niz karta.
  foreach ($para in @(@($script:BSkillInstaluj, "Zainstaluj", 140), @($script:BSkillAktualizuj, "Aktualizuj teraz", 130), @($script:BSkillUsun, "Usuń u mnie", 130), @($script:BSkillCofnij, "Cofnij ostatnią aktualizację", 200))) {
    $para[0].Text = $para[1]
    $para[0].Font = $script:CzZwykla
    $para[0].FlatStyle = [System.Windows.Forms.FlatStyle]::System
    $para[0].Size = New-Object System.Drawing.Size($para[2], 32)
    $para[0].Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    $script:SkillePrzyciski.Controls.Add($para[0])
  }
  $script:SkilleInfo = Pionowy 0
  $script:SkilleInfo.Dock = [System.Windows.Forms.DockStyle]::Top
  $script:SkilleInfo.BackColor = $script:TloKarty
  $kartaInfoS.Controls.Add($script:SkillePodglad)
  $kartaInfoS.Controls.Add($script:SkillePrzyciski)
  $kartaInfoS.Controls.Add($script:SkilleInfo)

  $cialoS.Controls.Add($kartaInfoS)
  $cialoS.Controls.Add($odstepS)
  $cialoS.Controls.Add($kartaListaS)
  $script:WidokSkille.Controls.Add($cialoS)
  $script:WidokSkille.Controls.Add($goraS)

  # Ekran ladowania (P21) - ten sam obszar co zakladki, dodany PIERWSZY, wiec lezy
  # na wierzchu wszystkich widokow i zaslania je, dopoki zakladka nie ma kompletu.
  $script:WidokLadowania = Zbuduj-Ladowanie

  # Kolejnosc dodawania ma znaczenie: WinForms dokuje od ostatnio dodanej
  # kontrolki, wiec wypelniajace widoki ida PIERWSZE, a naglowek i pasek po nich.
  $f.Controls.Add($script:WidokLadowania)
  $f.Controls.Add($script:WidokSkille)
  $f.Controls.Add($script:WidokWarstwy)
  $f.Controls.Add($script:WidokSzczegoly)
  $f.Controls.Add($script:WidokPrzeglad)
  $f.Controls.Add($script:Naglowek)
  $f.Controls.Add($script:Pasek)
  # Polozenie zapamietane do nastepnego otwarcia - okno staje tam, gdzie je zostawiono.
  $f.Add_FormClosing({
    try { if ($script:Okno.WindowState -eq [System.Windows.Forms.FormWindowState]::Normal) { $script:PolozenieOkna = $script:Okno.Location } }
    catch { Zanotuj-Wywrotke "zapamietanie polozenia okna" $_ }
  })
  $f.Add_FormClosed({
    # Dane (DaneWarstw, DaneSkilli, Rozbicie...) zostaja - to nie kontrolki. Drugie
    # otwarcie tego samego dnia pokazuje je od razu (P21); swiezosc pilnuja kawalki.
    $script:Ladowanie = $null; $script:WidokLadowania = $null; $script:ListaKrokow = $null; $script:WierszeKrokow = @{}
    $script:PasekLadowania = $null; $script:LLadowanieTytul = $null; $script:LLadowanieOpis = $null
    $script:LLadowanieStopka = $null; $script:BPokazTeraz = $null
    foreach ($w in @($script:DoOdmalowania.Keys)) { $script:DoOdmalowania[$w] = $true }
    $script:Okno = $null; $script:Root = $null; $script:Naglowek = $null
    $script:WidokPrzeglad = $null; $script:WidokSzczegoly = $null
    $script:LPodtytul = $null; $script:PanelProblemy = $null; $script:PanelLiczby = $null
    $script:KartaStat = $null; $script:PanelStan = $null
    $script:BPrzeglad = $null; $script:BSzczegoly = $null; $script:ListaSzczegolow = $null
    $script:KartaStart = $null; $script:KartaWerdykt = $null; $script:PodgladInfo = $null
    $script:Pasek = $null; $script:BAktualizuj = $null; $script:LAktualizuj = $null
    $script:BCykl = $null; $script:LCykl = $null
    $script:PanelZmian = $null; $script:LinkZmian = $null
    $script:BWarstwy = $null; $script:WidokWarstwy = $null; $script:LWarstwy = $null
    $script:ListaWarstw = $null; $script:PodgladWarstwy = $null
    if ($script:ZegarSkilli) { $script:ZegarSkilli.Stop() }
    $script:BSkille = $null; $script:WidokSkille = $null; $script:LSkille = $null; $script:BSkilleTeraz = $null
    $script:ListaSkilli = $null; $script:SkilleInfo = $null; $script:SkillePrzyciski = $null; $script:SkillePodglad = $null
    $script:BSkillInstaluj = $null; $script:BSkillAktualizuj = $null; $script:BSkillCofnij = $null; $script:BSkillUsun = $null
    $script:WierszeSkilli = @{}; $script:SkilleOperacjaOd = $null; $script:SkillePoOperacji = $null
    $script:GrupySkilli = @{}; $script:NaglowkiGrup = @{}; $script:ZnacznikiGrup = @{}
    $script:Widok = "przeglad"
    $script:SzczegolyZajete = $false
  })

  # --- co robia przyciski ---

  $script:BPrzeglad.Add_Click({
    $script:SzczegolyZajete = $false
    Pokaz-Widok "przeglad"
  })
  $script:BSzczegoly.Add_Click({
    if ($script:Widok -eq "szczegoly") { return }
    $script:SzczegolyZajete = $false
    Pokaz-Widok "szczegoly"
  })
  $script:BWarstwy.Add_Click({
    if ($script:Widok -eq "warstwy") { return }
    $script:SzczegolyZajete = $false
    Pokaz-Widok "warstwy"
  })
  $script:BSkille.Add_Click({
    if ($script:Widok -eq "skille") { return }
    $script:SzczegolyZajete = $false
    Pokaz-Widok "skille"
  })
  # Przyciski skilli nie wydaja tokenow - pytaja tylko wtedy, gdy maja nadpisac
  # skill zmieniony recznie (domyslnie podswietlone "Nie").
  $script:BSkilleTeraz.Add_Click({
    try { Rusz-Operacje-Skilli "aktualizuj" "" $false "Sprawdzam wszystkie źródła i pobieram nowsze wersje skilli pod opieką" }
    catch { Zanotuj-Wywrotke "przycisk Sprawdz teraz (skille)" $_ }
  })
  $script:BSkillInstaluj.Add_Click({
    try {
      $n = $script:SkillWybrany
      if ($n) { Rusz-Operacje-Skilli "instaluj" $n $false "Instaluję $n" }
    } catch { Zanotuj-Wywrotke "przycisk Zainstaluj (skille)" $_ }
  })
  $script:BSkillAktualizuj.Add_Click({
    try {
      $n = $script:SkillWybrany
      $para = Znajdz-Skill $n
      if (-not $para) { return }
      $wymus = $false
      if ($para[0].stan -eq "zmieniony") {
        $odp = [System.Windows.Forms.MessageBox]::Show($script:Okno,
          ("Skill `„$($para[0].folder)`” był zmieniony ręcznie - jego treść nie pasuje do żadnej wersji autora." + "`r`n`r`n" +
           "Czy zastąpić go najnowszą wersją od autora? Twoja wersja trafi do kopii zapasowej i przycisk `„Cofnij ostatnią aktualizację`” ją przywróci." + "`r`n`r`n" +
           "Po kliknięciu Nie nie stanie się nic."),
          "Zastąpić skill zmieniony ręcznie?", [System.Windows.Forms.MessageBoxButtons]::YesNo,
          [System.Windows.Forms.MessageBoxIcon]::Question, [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($odp -ne [System.Windows.Forms.DialogResult]::Yes) { Notuj "skille: nadpisanie $n - uzytkownik nie potwierdzil"; return }
        $wymus = $true
      }
      Rusz-Operacje-Skilli "aktualizuj" $n $wymus "Aktualizuję $n"
    } catch { Zanotuj-Wywrotke "przycisk Aktualizuj teraz (skille)" $_ }
  })
  $script:BSkillCofnij.Add_Click({
    try {
      $n = $script:SkillWybrany
      if ($n) { Rusz-Operacje-Skilli "cofnij" $n $false "Cofam ostatnią zmianę $n" }
    } catch { Zanotuj-Wywrotke "przycisk Cofnij (skille)" $_ }
  })
  # Usun u mnie (P20): tylko skill usuniety przez autora, zawsze z pytaniem (domyslnie "Nie").
  $script:BSkillUsun.Add_Click({
    try {
      $n = $script:SkillWybrany
      $para = Znajdz-Skill $n
      if (-not $para -or $para[0].stan -ne "usuniety") { return }
      $odp = [System.Windows.Forms.MessageBox]::Show($script:Okno,
        ("Autor usunął skill `„$($para[0].folder)`” ze swojego źródła. Twoja kopia nadal działa." + "`r`n`r`n" +
         "Czy usunąć go z Twojego komputera? Najpierw zrobię kopię zapasową - przycisk `„Przywróć usunięty`” wgra go z powrotem." + "`r`n`r`n" +
         "Po kliknięciu Nie nie stanie się nic."),
        "Usunąć skill?", [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question, [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
      if ($odp -ne [System.Windows.Forms.DialogResult]::Yes) { Notuj "skille: usuniecie $n - uzytkownik nie potwierdzil"; return }
      Rusz-Operacje-Skilli "usun" $n $false "Usuwam $n"
    } catch { Zanotuj-Wywrotke "przycisk Usun u mnie (skille)" $_ }
  })

  # Klikniecie warstwy pokazuje jej tresc po prawej. Wywrotka podgladu idzie
  # do dziennika i na ekran - nie zostawia starego podgladu udajacego nowy.
  $script:ListaWarstw.Add_SelectedIndexChanged({
    try {
      if ($script:ListaWarstw.SelectedItems.Count -gt 0) { Pokaz-Podglad $script:ListaWarstw.SelectedItems[0].Tag }
    } catch {
      Zanotuj-Wywrotke "podglad warstwy pamieci" $_
      if ($script:PodgladWarstwy -and -not $script:PodgladWarstwy.IsDisposed) {
        $script:PodgladWarstwy.Text = "NIE UDAŁO SIĘ POKAZAĆ TEJ WARSTWY: $($_.Exception.Message)"
      }
    }
  })

  # Przycisk bezpieczny - NIE pyta o zgode, bo nie wydaje ani jednego tokena.
  # Robi DOKLADNIE to, co hook Codeksa: wola straznik-zasad.ps1 -Tlo
  # (fetch + merge --ff-only, nigdy reset --hard). Warunki odmowy - brudne
  # drzewo, rozjechana historia, brak zdalnej - naleza do straznika i to on
  # je wypisuje; my pokazujemy, co powiedzial.
  $script:BAktualizuj.Add_Click({
    $script:BAktualizuj.Enabled = $false
    $script:LAktualizuj.Text = "Pobieram... to potrwa do dwóch minut."
    # Odpowiedz straznika ma zostac na ekranie do czasu, az uzytkownik sam
    # przelaczy widok - dlatego znacznik "zajete", ustawiony PRZED przelaczeniem.
    $script:SzczegolyZajete = $true
    Pokaz-Widok "szczegoly"
    Pokaz-Karty-Szczegolow @(Karta-Komunikatu "Pobieram nowszą wersję" @("Strażnik sprawdza serwer i nanosi poprawki - to potrwa do dwóch minut.") $null)
    $script:Okno.Refresh()
    $wynik = @()
    try { $wynik = Aktualizuj }
    catch { Zanotuj-Wywrotke "aktualizacja" $_; $wynik = @("NIE UDALO SIE: $($_.Exception.Message)") }
    Pokaz-Karty-Szczegolow @(Karta-Komunikatu "Co powiedział strażnik" (@($wynik) + @("",
      "To jest odpowiedź na kliknięcie, nie zwykła zawartość szczegółów. Kliknij [Przegląd], żeby wrócić do liczb.")) $null)
    $script:Okno.Refresh()
    $script:BAktualizuj.Enabled = $true
    # Po pobraniu nowszej wersji liczby licza sie od nowa w tle (P21); rozbicie
    # i warstwy moga byc juz z innego kodu - przy wejsciu w zakladke licza sie od nowa.
    $script:StanKawalkow["rozbicie"].Czas = $null
    $script:StanKawalkow["warstwy"].Czas = $null
    [void](Przelicz-W-Tle)
  })

  # JEDYNY przycisk w tym oknie, ktory wydaje tokeny - i dlatego jedyny, ktory
  # pyta. 24.09.2026 jego poprzednik ("Uruchom cykl teraz") wydal jednym
  # kliknieciem 312 609 tokenow, nie mowiac o tym ani slowa wczesniej.
  # Domyslnie podswietlone jest "Nie": przypadkowy Enter ma nic nie kosztowac.
  $script:BCykl.Add_Click({
    $n = Napisy-Przyciskow $script:Dane $script:Zuzycie
    $s = $n.Szacunek
    $t = @()
    # P17: tokeny i udzial w calym dziennym zuzyciu - bez procentu otwarcia okna rozmowy.
    $porownaj = {
      param($tokeny)
      $ud = ""
      try { $ud = Udzial-W-Dniu $tokeny $script:Zuzycie } catch { Zanotuj-Wywrotke "udzial w dziennym zuzyciu w pytaniu o zgode" $_ }
      if ($ud) { return "To $ud." }
      $bp = "Nie mam z czym porównać."
      try { $bp = (Z-Wielkiej (Bez-Porownania $script:Zuzycie)) + "." } catch { Zanotuj-Wywrotke "brak porownania w pytaniu o zgode" $_ }
      return $bp
    }
    if ($s -and ($null -ne $s.Tokeny)) {
      $t += "Przeczytanie nowych rozmów będzie kosztować około $(Liczba-Ludzka $s.Tokeny) tokenów."
      $t += (& $porownaj $s.Tokeny)
      $t += "Nie musisz tego robić - MegaRuchacz czyta rozmowy sam raz dziennie. Ten przycisk robi to tylko wcześniej."
    } else {
      $t += "NIE WIEM, ile to będzie kosztować."
      if ($s -and $s.Powod) { $t += "Powód: $($s.Powod)." }
      if ($script:Dane -and $script:Dane.Cykl -and ($null -ne $script:Dane.Cykl.Koszt)) {
        $t += "Poprzednie czytanie kosztowało ~$(Liczba-Ludzka $script:Dane.Cykl.Koszt) tokenów - takiego rzędu liczby się spodziewaj."
        $t += (& $porownaj $script:Dane.Cykl.Koszt)
      }
    }
    $t += ""
    if ($s) { foreach ($z in $s.Podstawa) { $t += $z } }
    $t += ""
    $t += "To jedyny przycisk w tym oknie, który naprawdę wydaje tokeny."
    $t += "Kliknij Tak, żeby uruchomić. Po kliknięciu Nie nie stanie się nic."
    $odp = [System.Windows.Forms.MessageBox]::Show(
      $script:Okno, ($t -join "`r`n"), "Przeczytać teraz nowe rozmowy?",
      [System.Windows.Forms.MessageBoxButtons]::YesNo,
      [System.Windows.Forms.MessageBoxIcon]::Warning,
      [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($odp -ne [System.Windows.Forms.DialogResult]::Yes) {
      Notuj "czytanie zaleglych rozmow: uzytkownik nie potwierdzil - nic nie ruszylo"
      return
    }

    $poszlo = $false
    try { $poszlo = Ruszaj-Cykl } catch { Zanotuj-Wywrotke "reczny start czytania rozmow" $_ }
    if ($poszlo) {
      $script:BCykl.Enabled = $false
      $script:LCykl.Text = "Czytanie ruszyło w tle. Potrwa kilka minut, liczby odświeżą się same."
      Notuj "czytanie zaleglych rozmow ruszylo z okna po potwierdzeniu kosztu"
    } else {
      $script:LCykl.Text = "NIE UDAŁO SIĘ uruchomić - szczegóły w oknie obok."
      [System.Windows.Forms.MessageBox]::Show(
        $script:Okno,
        ("Nie udało się uruchomić czytania rozmów." + "`r`n`r`n" +
         "Spróbuj ręcznie:" + "`r`n" +
         "powershell -ExecutionPolicy Bypass -File $Zrodlo\narzedzia\cykl-dzienny.ps1" + "`r`n`r`n" +
         "Ślad w $(Join-Path $KatalogDomowy '.claude\.megaruchacz-zasobnik.log')"),
        "Nie udało się", [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
  })

  $bZamknij.Add_Click({ $script:Okno.Close() })

  $script:Okno = $f
  # Tresc (karty albo ekran ladowania) sklada sie PRZED pokazaniem okna - pierwsze
  # odmalowanie jest od razu docelowe, bez pustych kart (P21).
  $script:Widok = "przeglad"
  Styl-Przelacznika $script:BPrzeglad $true
  Styl-Przelacznika $script:BSzczegoly $false
  Styl-Przelacznika $script:BWarstwy $false
  Styl-Przelacznika $script:BSkille $false
  Odmaluj-Przyciski
  # Watki do liczenia otwieraja sie dopiero PO pokazaniu okna - okno ma stanac
  # na ekranie jak najszybciej, a kroki i tak juz stoja na liscie jako "czeka".
  $script:PrzydzialPoPokazaniu = $true
  try { Wejdz-Do-Widoku "przeglad" $true } finally { $script:PrzydzialPoPokazaniu = $false }
  $f.Show()
  Wymus-Pokazanie $f
  Obsluz-Kroki
}

# ----------------------------------------------------------------- ikona i menu

$script:Ikona = New-Object System.Windows.Forms.NotifyIcon
$script:Ikona.Icon = Ikona-Nadzorcy
$script:Ikona.Text = "MegaRuchacz - zbieram dane"
$script:Ikona.Visible = $true

# Dymki (powiadomienia Windows) wylaczone 28.09.2026 na prosbe uzytkownika - wyskakiwaly
# przy kazdym alarmie. Alarm nie znika w cisze: zostaje w podpowiedzi ikony (najechanie
# myszka), w czerwonej karcie na gorze okna i w dzienniku. $true przywraca dymki.
$script:PokazujDymki = $false

function Pokaz-Dymek([string]$tytul, [string]$tresc) {
  if (-not $script:PokazujDymki) {
    try { Notuj "dymek pominiety (dymki wylaczone): $tytul" } catch { Zanotuj-Wywrotke "wpis o pominietym dymku" $_ }
    return
  }
  try {
    $script:Ikona.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Warning
    $script:Ikona.BalloonTipTitle = Skroc-Na-Dymek $tytul $MAX_TYTUL "[skrocone] "
    $script:Ikona.BalloonTipText  = Skroc-Na-Dymek $tresc $MAX_TRESC "[skrocone - calosc w oknie MegaRuchacza] "
    $script:Ikona.ShowBalloonTip(20000)
  } catch { Zanotuj-Wywrotke "pokazanie dymka" $_ }
}
$script:Dymek = { param($tytul, $tresc) Pokaz-Dymek $tytul $tresc }

function Nowa-Pozycja([string]$napis, $akcja) {
  $p = New-Object System.Windows.Forms.ToolStripMenuItem
  $p.Text = $napis
  $p.Add_Click($akcja)
  return $p
}

# W MENU NIE MA JUZ "Uruchom cykl teraz". Ta pozycja wydawala setki tysiecy
# tokenow jednym kliknieciem, bez slowa o koszcie i bez pytania. Czytanie rozmow
# da sie odpalic wylacznie przyciskiem w oknie, ktory pokazuje szacunek i pyta -
# jedna droga do wydawania pieniedzy, i to ta, ktora ostrzega.
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Items.Add((Nowa-Pozycja "Otwórz okno MegaRuchacza" { Pokaz-Okno })) | Out-Null
# Recznemu przeliczeniu zostaje miejsce TUTAJ, a nie w oknie: okno liczy samo,
# ale kto wlasnie cos poprawil (np. skrocil CLAUDE.md), chce zobaczyc skutek
# natychmiast, nie po kwadransie.
#
# Ta pozycja SAMA LICZY i nic nie uruchamia - swiadomie nie wola Dozoru, bo
# dozor przy okazji startuje czytanie rozmow, gdy wypada na nie pora. Pozycja
# menu nazwana "przelicz liczby" nie ma prawa wydac ani jednego tokena.
$menu.Items.Add((Nowa-Pozycja "Przelicz liczby teraz (nic nie kosztuje)" {
  try {
    # P21: w tle - ikona i otwarte okno nie staja na czas liczenia.
    $k = Przelicz-W-Tle 'Zbierz-Wszystko $true $true'
    $script:StanKawalkow["rozbicie"].Czas = $null
    if (-not $k.Po) {
      $k.Po = {
        param($k)
        if (($k.Stan -eq "ok") -or ($k.Stan -eq "uwaga")) { Pokaz-Dymek "MegaRuchacz: przeliczone" "Liczby sa swieze. Kliknij ikone, zeby je zobaczyc." }
        else { Pokaz-Dymek "MegaRuchacz: nie przeliczylem" "Nie udalo sie przeliczyc liczb: $($k.Powod)" }
      }
    }
  } catch {
    Zanotuj-Wywrotke "reczne przeliczenie z menu" $_
    Pokaz-Dymek "MegaRuchacz: nie przeliczylem" "Nie udalo sie przeliczyc liczb: $($_.Exception.Message)"
  }
})) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$menu.Items.Add((Nowa-Pozycja "Zamknij MegaRuchacza (ikona zniknie)" {
  Notuj "nadzorca zakonczony z menu - do najblizszego zalogowania nikt nie pilnuje cyklu"
  $script:Ikona.Visible = $false
  [System.Windows.Forms.Application]::Exit()
})) | Out-Null
$script:Ikona.ContextMenuStrip = $menu
$script:Ikona.Add_MouseClick({
  param($nadawca, $e)
  if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Pokaz-Okno }
})

# ------------------------------------------------------------------ zegar dozoru

# Pierwszy przebieg po 5 sekundach, a nie od razu: ikona ma sie pojawic
# natychmiast, a nie po kilkunastu sekundach liczenia rachunku.
$script:Pierwszy = $true
$script:Zegar = New-Object System.Windows.Forms.Timer
$script:Zegar.Interval = 5000
$script:Zegar.Add_Tick({
  if ($script:Pierwszy) {
    $script:Pierwszy = $false
    $script:Zegar.Interval = [math]::Max(1, $Minut) * 60 * 1000
  }
  try {
    # $zSieci = $true: po nowsza wersje zaglada dozor, bo tu nikt nie czeka
    # przed ekranem. Od P21 dane licza sie w watku w tle (git fetch potrafi trwac
    # do 25 s, a otwarte okno ani ikona nie maja wtedy stawac); decyzje, alarmy
    # i odmalowanie otwartego okna - w Po-Dozorze, gdy dane przyjda.
    Rusz-Dozor
  } catch { Zanotuj-Wywrotke "przebieg dozoru" $_ }
})
$script:Zegar.Start()

# Wywrotki z poprzedniego uruchomienia - nadzorca, ktory sie wczoraj wywrocil,
# ma o tym powiedziec, a nie udawac, ze wstal czysty. Zostaja tez w pamieci
# sesji, zeby okno pokazalo je jako zolta karte w sekcji problemow.
try {
  $stare = Odbierz-Wywrotki
  $script:Wywrotki = @($stare)
  if ($script:Wywrotki.Count -gt 0) {
    $ogon = ""
    if ($script:Wywrotki.Count -gt 1) { $ogon = " (i jeszcze $($script:Wywrotki.Count - 1))" }
    Pokaz-Dymek "MegaRuchacz: nadzorca wywrocil sie poprzednio" (
      "$($script:Wywrotki[0])${ogon}. Kliknij ikone - w oknie jest komplet. " +
      "Dziennik: $(Join-Path $KatalogDomowy '.claude\.megaruchacz-zasobnik.log')")
  }
} catch { Zanotuj-Wywrotke "odczyt wywrotek przy starcie" $_ }

Notuj "nadzorca wystartowal (zrodlo $Zrodlo, dozor co $Minut min)"
Zapisz-Obecnosc "start"
if ($Pokaz) { Pokaz-Okno }

try {
  [System.Windows.Forms.Application]::Run()
} catch {
  # Wywrotka calego programu. Slad idzie na dysk, zeby nastepny start mogl
  # o niej zameldowac - nadzorca ginacy po cichu bylby dokladnie tym samym
  # problemem, dla ktorego rozwiazania powstal.
  Zanotuj-Wywrotke "petla glowna nadzorcy" $_
  Zapisz-Obecnosc "wywrotka"
} finally {
  try { $script:Ikona.Visible = $false; $script:Ikona.Dispose() }
  catch { Notuj "nie udalo sie sprzatnac ikony przy zamykaniu" }
}
