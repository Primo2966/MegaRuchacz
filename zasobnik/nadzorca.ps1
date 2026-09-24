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
# PRZYCISKU [ODSWIEZ] NIE MA I NIE MA GO BYC. Istnial tylko dlatego, ze okno
# nie odswiezalo sie samo - byl obejsciem braku, nie funkcja. Dzis okno przelicza
# sie przy kazdym otwarciu i przy kazdym przebiegu dozoru; recznemu sprawdzeniu
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

# Cztery rzeczy ze zlecenia, w kolejnosci od najczesciej ogladanej: rachunek,
# cykl, wersja, alarmy - plus slad samego nadzorcy, bo on tez ma nie milczec
# o sobie. Zbierane raz, zeby dozor i okno nie liczyly tego samego dwa razy.
function Zbierz-Wszystko([bool]$zSieci, [bool]$zKolejka) {
  $d = [pscustomobject]@{ Wersja = $null; Cykl = $null; Rachunek = $null; Alarmy = @(); Informacje = @(); Pamiec = $null; Przeliczanie = $null }

  try { $d.Wersja = Stan-Wersji $zSieci }
  catch { Zanotuj-Wywrotke "odczyt wersji narzedzia" $_ }

  # Oba odczyty to same pliki na dysku, bez wolania skryptow - ulamek sekundy.
  try { $d.Pamiec = Stan-Zmian-Pamieci }
  catch { Zanotuj-Wywrotke "odczyt zmian w pamieci" $_ }

  try { $d.Przeliczanie = Postep-Przeliczania }
  catch { Zanotuj-Wywrotke "odczyt postepu przeliczania archiwum" $_ }

  try { $d.Cykl = Stan-Cyklu $zKolejka }
  catch { Zanotuj-Wywrotke "odczyt stanu cyklu" $_ }

  try { $d.Rachunek = Linia-Rachunku }
  catch { Zanotuj-Wywrotke "rachunek za pamiec (linia)" $_ }

  if ($d.Cykl -and $d.Rachunek) {
    try { $d.Alarmy = Zbierz-Alarmy $d.Cykl $d.Rachunek }
    catch { Zanotuj-Wywrotke "skladanie alarmow" $_ }
  }
  # Zolte informacje (np. nauka nadrabiala zaleglosc) - osobno od alarmow, bo
  # alarmy ida na dymek, a informacja nie ma prawa wyskakiwac jak ostrzezenie.
  if ($d.Rachunek) {
    try { $d.Informacje = Zbierz-Informacje $d.Rachunek }
    catch { Zanotuj-Wywrotke "skladanie informacji o koszcie nauki" $_ }
  }
  return $d
}

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
function Napisy-Przyciskow($d) {
  $n = [pscustomobject]@{
    Aktualizuj     = "Sprawdź i pobierz nowszą wersję MegaRuchacza"
    AktualizujOpis = "Nie kosztuje nic. Zagląda na serwer po poprawki i nanosi je."
    Cykl           = "Przeczytaj zaległe rozmowy"
    CyklOpis       = "Wysyła zaległe rozmowy do modelu, żeby się z nich uczył. Zapyta o zgodę."
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
    $n.Cykl = "Przeczytaj zaległe rozmowy (koszt: nie wiem)"
    $n.CyklOpis = "Nie mam danych, żeby oszacować koszt. Przed startem i tak zapyta o zgodę."
  } elseif (($null -ne $s.Porcje) -and ($s.Porcje -le 0)) {
    $n.CyklWlaczony = $false
    $n.CyklOpis = "Wyłączone: nic nie czeka, wszystkie rozmowy są już przeczytane."
  } elseif ($null -ne $s.Tokeny) {
    $n.Cykl = "Przeczytaj zaległe rozmowy (~$(Liczba-Ludzka $s.Tokeny) tokenów)"
    $n.CyklOpis = "Tyle mniej więcej wyda to jedno kliknięcie. Zapyta o zgodę i pokaże, skąd ta liczba."
  } else {
    $n.Cykl = "Przeczytaj zaległe rozmowy (koszt: nie wiem)"
    $n.CyklOpis = "Nie umiem oszacować kosztu: $($s.Powod). Przed startem zapyta o zgodę."
  }
  return $n
}

# ----------------------------------------------------------- wydruk tego, co widac

# Przod okna jako tekst: dokladnie te sekcje i w tej samej kolejnosci, co
# w oknie. Ten wydruk jest jedynym sposobem sprawdzenia ukladu bez pulpitu.
function Zbuduj-Przod($d, $problemy, $czas) {
  $l = @()
  $l += "MegaRuchacz - nadzorca                      [ Przegląd | Szczegóły ]   <- przełącznik widoków u góry okna"
  $stempel = "przed chwilą"
  if ($czas) { $stempel = $czas.ToString('yyyy-MM-dd HH:mm:ss') }
  $l += "liczby sprawdzone: $stempel  (okno przelicza je samo przy każdym otwarciu i co $Minut min)"
  $l += ""

  $wazne = @(@($problemy) | Where-Object { $_.Waga -ne "info" })
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
    $l += "WARTO WIEDZIEĆ   (w oknie: żółta karta z dopiskiem „dla informacji - nic nie trzeba robić”, bez dymka)"
    foreach ($p in $info) {
      $l += "  [i] $($p.Tytul)"
      if ($p.Porada) { $l += "      $($p.Porada)" }
    }
    $l += ""
  }

  $l += "ILE TO KOSZTUJE   (w oknie: trzy karty obok siebie)"
  $r = $null; $c = $null
  if ($d) { $r = $d.Rachunek; $c = $d.Cykl }
  # Bez @() wokol wywolania - te funkcje koncza sie na "return ,$lista", wiec
  # owiniecie ich w @() daje tablice z jedna tablica w srodku (pulapka opisana
  # w naglowku stan-nadzorcy.ps1). Owijac wolno zmienne, nie wywolania.
  $trzy = @()
  try { $trzy = Trzy-Liczby $r $c }
  catch { Zanotuj-Wywrotke "trzy liczby do wydruku" $_; $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy" }
  foreach ($t in $trzy) {
    $l += "  | $($t.Naglowek)"
    if ($null -ne $t.Liczba) {
      $ogon = ""
      if ($t.Ogon) { $ogon = "   ($($t.Ogon))" }
      $l += "  |   ~$(Liczba-Ludzka $t.Liczba) tokenów$ogon"
      if ($t.Znacznik) {
        $zn = "[$($t.Znacznik)]"
        if ($t.ZnacznikWaga -eq "pilne") { $zn = "$zn  (czerwony napis)" }
        elseif ($t.ZnacznikWaga) { $zn = "$zn  (żółty napis)" }
        $l += "  |   $zn"
      }
    } else {
      $l += "  |   nie wiem - $($t.Powod)"
    }
    $l += "  |   $($t.Opis)"
  }
  $l += ""

  $st = $null
  try { $st = Statystyka-Okna $r }
  catch { Zanotuj-Wywrotke "statystyka nauki do wydruku" $_ }
  $l += "KOSZT NAUKI Z ROZMÓW - OSTATNIE 30 DNI   (w oknie: wykres słupkowy - $(Opis-Rysownika))"
  if (-not $st) {
    $l += "  NIE UDALO SIE ZLOZYC STATYSTYKI - szczegoly w dzienniku nadzorcy"
  } else {
    $l += Linie-Statystyki $st $r
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
  $n = Napisy-Przyciskow $d
  $l += "  [$($n.Aktualizuj)]"
  $l += "      $($n.AktualizujOpis)"
  $wl = ""
  if (-not $n.CyklWlaczony) { $wl = "  (przycisk nieaktywny)" }
  $l += "  [$($n.Cykl)]$wl"
  $l += "      $($n.CyklOpis)"
  if ($n.Szacunek) { foreach ($z in $n.Szacunek.Podstawa) { $l += "      $z" } }
  $l += "  [Przegląd] / [Szczegóły]  (przełącznik u góry)"
  $l += "      Szczegóły - z czego to się składa i gdzie to leży - zajmują miejsce przeglądu. Nic nie uruchamiają i nic nie kosztują."
  $l += "  [Zamknij okno]"
  $l += "      Okno znika, ikona w zasobniku zostaje i pilnuje dalej."
  return ,$l
}

# Statystyka jako tekst: to samo, co wykres w oknie, tylko paskami ze znakow.
# Sluzy wydrukowi -Raport, czyli sprawdzeniu bez pulpitu.
function Linie-Statystyki($st, $rachunek) {
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
      if ($x.Nadrabianie -gt 0) { $rodzaj += "nadrabianie" }
      if ($x.Nieznane -gt 0)    { $rodzaj += "okres nieznany" }
      $l += ("  {0}  {1,-30}  {2,9}  {3}" -f $x.Dzien.ToString('dd.MM'), $pasek, (Liczba-Ludzka $x.Razem), ($rodzaj -join " + "))
    }
  } else {
    $l += "  (wykres bez słupków - w oknie w jego miejscu stoi zdanie niżej)"
  }
  $l += ("  Ostatnie 7 dni: {0}   |   ostatnie {1} dni: {2}" -f (Tokeny-Albo-Brak $st.Suma7), $st.OknoDni, (Tokeny-Albo-Brak $st.Suma30))
  if ($null -ne $st.Srednia) {
    $l += ("  Średnio na dzień nauki: ~{0} tokenów (z {1} {2})" -f (Liczba-Ludzka $st.Srednia), $st.SredniaDni, (Odmiana $st.SredniaDni 'dnia' 'dni' 'dni'))
  } else {
    $l += "  Średnio na dzień nauki: jeszcze nie wiem"
  }
  if (($null -ne $st.Typowy) -and ($st.TypowychDni -gt 0)) {
    $l += ("  Zwykły dzień (bez nadrabiania): ok. {0} tokenów - typowa wartość z {1} {2}" -f (Okolo $st.Typowy), $st.TypowychDni, (Odmiana $st.TypowychDni 'dnia' 'dni' 'dni'))
  } else {
    $l += "  Zwykły dzień (bez nadrabiania): jeszcze nie wiem - w historii nie ma ani jednego dnia bez nadrabiania"
  }
  if ($null -ne $st.Prog) {
    $l += "  Próg zwykłego dnia: $(Liczba-Ludzka $st.Prog) tokenów (w oknie przerywana czerwona linia, gdy mieści się w skali)"
  }
  if ($st.Uwaga) { $l += "  $($st.Uwaga)" }
  return ,$l
}

function Tokeny-Albo-Brak($n) {
  if ($null -eq $n) { return "brak danych" }
  return "~$(Liczba-Ludzka $n) tokenów"
}

# Szczegoly: wszystko to, co w starym oknie lezalo na wierzchu. Tu jest ich
# miejsce - w zakladce Szczegoly, dla tego, kto ich szuka.
function Zbuduj-Szczegoly($d, $wywrotkiNadzorcy, $rozbicie) {
  $l = @()
  $l += "SZCZEGÓŁY   (w oknie: zakładka Szczegóły, przełącznik u góry)"
  $l += "zebrane $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  $l += "narzedzie      : $Zrodlo"
  $l += "katalog domowy : $KatalogDomowy"
  $l += ""

  $l += "== WERSJA NARZEDZIA =="
  if ($d -and $d.Wersja) { $l += Opis-Wersji $d.Wersja }
  else { $l += "  NIE UDALO SIE USTALIC - szczegoly w dzienniku nadzorcy" }
  $l += ""

  $l += "== RACHUNEK ZA PAMIEC, POZYCJA PO POZYCJI =="
  $l += "   (liczy narzedzia\koszt-pamieci.ps1 -Rozbicie - to ten sam wydruk, nie druga kopia)"
  if ($null -ne $rozbicie) { $l += @($rozbicie) }
  else { $l += "  jeszcze nie policzone" }
  $l += ""

  $l += "== NAUKA Z ROZMOW (cykl wiedzy) =="
  if ($d -and $d.Cykl) { $l += Opis-Cyklu $d.Cykl }
  else { $l += "  NIE UDALO SIE ODCZYTAC - szczegoly w dzienniku nadzorcy" }
  $l += ""

  # Skad sa liczby na wykresie - te same dni i sumy, co w oknie, plus zrodlo.
  $l += "== NAUKA Z ROZMOW - HISTORIA KOSZTU (to, co na wykresie) =="
  $rach = $null
  if ($d) { $rach = $d.Rachunek }
  $st = $null
  try { $st = Statystyka-Okna $rach }
  catch { Zanotuj-Wywrotke "statystyka nauki do szczegolow" $_ }
  if ($st) {
    $skad = "nie wiadomo"
    switch ($st.Zrodlo) {
      "historia"  { $skad = "dziennik przebiegow (.koszt-historia.tsv)" }
      "plik-dnia" { $skad = "tylko ostatni pomiar (.koszt-cyklu.txt) - dziennika przebiegow jeszcze nie ma" }
      "brak"      { $skad = "nic - $($st.Powod)" }
    }
    $l += "  dni z             : $skad"
    $sumy = "nie ma czego sumowac"
    if ($st.SumyZ -eq "podsumowanie") { $sumy = "podsumowanie liczone przez sama nauke (.koszt-podsumowanie.txt)" }
    elseif ($st.SumyZ -eq "dni") { $sumy = "zsumowane z dni ponizej (podsumowania nie ma)" }
    $l += "  sumy 7/30 dni z   : $sumy"
    $l += "  wykres            : $(Opis-Rysownika)"
    $l += "  prog zwyklego dnia: $(Tokeny-Albo-Brak $st.Prog) (uzasadnienie na gorze narzedzia\koszt-pamieci.ps1)"
    foreach ($x in @(@($st.Dni) | Where-Object { $_.Jest })) {
      $l += ("    {0}  razem {1,9}   zwykly dzien {2,9}   nadrabianie {3,9}   okres nieznany {4,9}" -f `
             $x.Dzien.ToString('yyyy-MM-dd'), (Liczba-Ludzka $x.Razem), (Liczba-Ludzka $x.Zwykle),
             (Liczba-Ludzka $x.Nadrabianie), (Liczba-Ludzka $x.Nieznane))
    }
    if ($st.Uwaga) { $l += "  $($st.Uwaga)" }
  } else {
    $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy"
  }
  $l += ""

  # Surowy meldunek modulu pamieci - razem z komenda cofania, ktora na wierzchu
  # jest zastapiona zdaniem "powiedz Claude'owi".
  $l += "== ZMIANY W PAMIECI (meldunek ostatniej nauki) =="
  if ($d -and $d.Pamiec) {
    $pz = $d.Pamiec
    $l += "  plik            : $($pz.Plik)"
    if ($pz.Dzien) { $l += "  dzien nauki     : $($pz.Dzien.ToString('yyyy-MM-dd'))" }
    if (-not $pz.Wiadomo) { $l += "  NIE WIADOMO     : $($pz.Powod)" }
    if ($pz.Naglowek) { $l += "  meldunek        : $($pz.Naglowek)" }
    foreach ($x in $pz.Zmiany) { $l += "                    $($x.Tresc)" }
    $l += "  cofniecie       : uv --directory $Zrodlo\lore run python -m lore.verify --cofnij <id>"
  } else {
    $l += "  NIE UDALO SIE ODCZYTAC - szczegoly w dzienniku nadzorcy"
  }
  if ($d -and $d.Przeliczanie -and $d.Przeliczanie.Plik) {
    $l += "  przeliczanie    : jest plik $($d.Przeliczanie.Plik)"
    if ($d.Przeliczanie.Powod) { $l += "                    $($d.Przeliczanie.Powod)" }
  }
  $l += ""

  $l += "== ALARMY I INFORMACJE, PELNA TRESC RAZEM Z KOMENDAMI =="
  $alarmy = @()
  if ($d) { $alarmy = @($d.Alarmy) + @($d.Informacje) }
  if ($alarmy.Count -eq 0) {
    if ($d -and $d.Cykl -and $d.Rachunek) { $l += "  nic nie wymaga uwagi" }
    else { $l += "  NIE WIADOMO - brakuje danych, wiec alarmow nie policzylem" }
  } else {
    foreach ($a in $alarmy) {
      $waga = Waga-Z-Alarmu $a
      $l += "  [$($a.Temat), $waga] $($a.Tytul)"
      $l += "      $($a.Tresc)"
    }
  }
  if ($d -and $d.Rachunek -and $d.Rachunek.Linia) {
    $l += "  linia rachunku (ta sama, co widzi straznik przy starcie sesji):"
    $l += "      $($d.Rachunek.Linia)"
  }
  $l += ""

  $l += "== NADZORCA =="
  $stan = Czytaj-Klucze (Join-Path $KatalogDomowy ".claude\.megaruchacz-zasobnik.txt")
  if ($stan["byl"]) { $l += "  ostatni dozor   : $($stan['byl']) (tryb $($stan['byl.tryb']))" }
  else { $l += "  ostatni dozor   : brak zapisu - to pierwszy przebieg albo nie moge pisac do pliku stanu" }
  if ($stan["cykl.ruszony"]) { $l += "  cykl startowany : $($stan['cykl.ruszony'])" }
  if (@($wywrotkiNadzorcy).Count -gt 0) {
    $l += "  WYWROTKI Z POPRZEDNICH PRZEBIEGOW:"
    foreach ($w in @($wywrotkiNadzorcy)) { $l += "      $w" }
  }
  $l += "  dziennik        : $(Join-Path $KatalogDomowy '.claude\.megaruchacz-zasobnik.log')"
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

  # Alarmy - jeden na sprawe na dobe, zeby nie uczyly ignorowania.
  foreach ($a in @($d.Alarmy)) {
    if (Alarm-Juz-Byl $a.Temat) { Notuj "alarm [$($a.Temat)] juz dzis byl - nie powtarzam"; continue }
    & $pokazDymek $a.Tytul $a.Tresc
    Notuj "ALARM [$($a.Temat)] $($a.Tytul) :: $($a.Tresc)"
    Odnotuj-Alarm $a.Temat
  }

  Zapisz-Obecnosc "dozor"
  return $d
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
    $roz = @()
    try { $roz = Rachunek-Rozbicie }
    catch { Zanotuj-Wywrotke "rachunek za pamiec (rozbicie)" $_; $roz = @("  NIE UDALO SIE POLICZYC - szczegoly w dzienniku nadzorcy") }
    Zbuduj-Przod $d $probl ([datetime]::Now) | ForEach-Object { Write-Output $_ }
    Write-Output ""
    Zbuduj-Szczegoly $d $stare $roz | ForEach-Object { Write-Output $_ }
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
  $roz = @()
  try { $roz = Rachunek-Rozbicie }
  catch { Zanotuj-Wywrotke "rachunek za pamiec (rozbicie)" $_; $roz = @("  NIE UDALO SIE POLICZYC - szczegoly w dzienniku nadzorcy") }
  Zbuduj-Przod $d $probl ([datetime]::Now) | ForEach-Object { Write-Output $_ }
  Write-Output ""
  Zbuduj-Szczegoly $d $stare $roz | ForEach-Object { Write-Output $_ }
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
$script:WidokSzczegoly = $null   # pole z pelnym tekstem szczegolow
$script:Root           = $null
$script:PanelProblemy  = $null
$script:PanelLiczby    = $null
$script:KartaStat      = $null
$script:PanelStan      = $null
$script:PoleSzczegoly  = $null
$script:Pasek          = $null
$script:BAktualizuj    = $null
$script:LAktualizuj    = $null
$script:BCykl          = $null
$script:LCykl          = $null
$script:ZegarOtwarcia  = $null
$script:PanelZmian     = $null   # linie zmian w pamieci, schowane pod "pokaz zmiany"
$script:LinkZmian      = $null
# Rozwiniecie listy zmian przezywa przeliczenie okna - inaczej lista zwijalaby
# sie sama co kwadrans, w trakcie czytania.
$script:ZmianyRozwiniete = $false
$script:Widok          = "przeglad"
# Dane, z ktorych rysuje sie wykres w zdarzeniu Paint - procedura obslugi siega
# wylacznie po $script:, wiec odkladamy je tutaj przy kazdym odmalowaniu.
$script:StatWykresu    = $null
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

# Szerokosci. Tresc ma 800 px: trzy karty kosztow po 256 z dwoma odstepami po 16.
# Okno ma 866 px wnetrza: 24 marginesu z kazdej strony plus miejsce na pionowy
# suwak, gdyby ekran byl za niski - wtedy suwak poziomy i tak sie nie pojawia,
# a tekst wyjezdzajacy poza krawedz bylby ucieciem po cichu.
$script:SzerTresc   = 800
$script:SzerKarty   = 800
$script:SzerKafelka = 256
$script:Odstep      = 16
$script:SzerOkna    = 866
$script:SzerEtykiety = 170   # lewa kolumna w karcie stanu

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
  $k.Padding = New-Object System.Windows.Forms.Padding(16, 10, 16, 10)
  $k.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
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
function Przycisk-Przelacznika([string]$napis, [int]$x) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $napis
  $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
  $b.FlatAppearance.BorderSize = 0
  $b.Size = New-Object System.Drawing.Size(104, 28)
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

# --- wykres ------------------------------------------------------------------
# Te same dane rysuja dwie drogi: kontrolka Chart (gdy sie zaladowala) albo
# wlasne slupki w Paint. Skala i prog sa liczone RAZ, tutaj, zeby obie drogi
# pokazywaly dokladnie to samo.

# Gorna granica osi: najwyzszy slupek plus zapas, zaokraglona do "ladnej" liczby.
# Prog zwyklego dnia wchodzi do skali tylko wtedy, gdy jest najwyzej dwa razy
# wyzej niz najwyzszy slupek - inaczej zgniotlby wszystkie slupki do kresek,
# a legenda mowi wtedy wprost, ze prog jest daleko ponad nimi.
function Skala-Wykresu($st) {
  $max = [double]0
  foreach ($d in @($st.Dni)) { if ($d.Razem -gt $max) { $max = [double]$d.Razem } }
  if ($max -le 0) { $max = 1000 }
  $gora = $max
  if (Prog-Widoczny $st) { $gora = [math]::Max($gora, [double]$st.Prog) }
  $gora = $gora * 1.1
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

function Tysiace($n) {
  if ($n -le 0) { return "0" }
  return "$(Liczba-Ludzka ([math]::Round([double]$n / 1000))) tys."
}

function Opis-Dnia-Wykresu($d) {
  $cz = @()
  if ($d.Zwykle -gt 0)      { $cz += "zwykły dzień" }
  if ($d.Nadrabianie -gt 0) { $cz += "nadrabianie zaległości" }
  if ($d.Nieznane -gt 0)    { $cz += "okres nieznany" }
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
  $skala = (Skala-Wykresu $st) / 1000.0
  $ob.AxisY.Minimum = 0
  $ob.AxisY.Maximum = $skala
  $ob.AxisY.Interval = $skala / 2.0
  $ob.AxisY.LabelStyle.Format = "0"
  $ob.AxisY.Title = "tys. tokenów"
  $ob.AxisY.TitleFont = $script:CzMala
  $ob.AxisY.TitleForeColor = $script:KolSzary
  if (Prog-Widoczny $st) {
    $linia = New-Object System.Windows.Forms.DataVisualization.Charting.StripLine
    $linia.IntervalOffset = [double]$st.Prog / 1000.0
    $linia.StripWidth = 0
    $linia.BorderColor = $script:KolPilne
    $linia.BorderDashStyle = [System.Windows.Forms.DataVisualization.Charting.ChartDashStyle]::Dash
    $linia.BorderWidth = 1
    $linia.Text = "próg zwykłego dnia"
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
      $i = $s.Points.AddY([double]$d.($opis.Pole) / 1000.0)
      if ($d.Jest) { $s.Points[$i].ToolTip = (Opis-Dnia-Wykresu $d) }
    }
    $ch.Series.Add($s) | Out-Null
  }
  # Podpisy dni co tydzien, liczac od dzis wstecz - tak, zeby dzisiejszy dzien
  # mial podpis zawsze. Punkty sa numerowane od 1.
  $n = @($st.Dni).Count
  for ($i = $n; $i -ge 1; $i -= 7) {
    $ob.AxisX.CustomLabels.Add([double]($i - 0.5), [double]($i + 0.5), $st.Dni[$i - 1].Dzien.ToString('dd.MM')) | Out-Null
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
      $g.DrawString((Tysiace ($skala * $f)), $script:CzMala, $szary, (New-Object System.Drawing.RectangleF(0, ($y - 9), ($lewy - 6), 18)), $doPrawej)
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
        $ile = [double]$d.$pole
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
      $y = $gora + $h - [float]($h * [double]$st.Prog / $skala)
      $prog = New-Object System.Drawing.Pen($script:KolPilne); $piora += $prog
      $prog.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
      $g.DrawLine($prog, [float]$lewy, [float]$y, [float]($lewy + $w), [float]$y)
      $czerwony = New-Object System.Drawing.SolidBrush($script:KolPilne); $pedzle += $czerwony
      $nad = New-Object System.Drawing.StringFormat
      $nad.Alignment = [System.Drawing.StringAlignment]::Far
      $g.DrawString("próg zwykłego dnia", $script:CzMala, $czerwony, (New-Object System.Drawing.RectangleF($lewy, ($y - 16), $w, 16)), $nad)
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
  $script:LPodtytul.Text = "Sprawdzone $kiedy. Okno liczy to samo przy każdym otwarciu i co $Minut min w tle."
}

function Karta-Problemu($p) {
  $k = Pionowy $script:SzerKarty
  $k.Padding = New-Object System.Windows.Forms.Padding(16, 10, 16, 12)
  $k.Margin  = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
  $kolor = $script:KolUwaga
  $k.BackColor = $script:TloUwaga
  $podpis = "Do sprawdzenia"
  if ($p.Waga -eq "pilne") { $kolor = $script:KolPilne; $k.BackColor = $script:TloPilne; $podpis = "Wymaga działania" }
  elseif ($p.Waga -eq "info") { $podpis = "Dla informacji - nic nie trzeba robić" }
  $szer = $script:SzerKarty - 32
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

function Kafelek-Liczby($t) {
  $k = Nowa-Karta $script:SzerKafelka
  $k.Margin = New-Object System.Windows.Forms.Padding(0, 0, $script:Odstep, 10)
  $szer = $script:SzerKafelka - 32
  $k.Controls.Add((Etykieta-Zawijana $t.Naglowek $script:CzMala $script:KolSzary $szer))
  if ($null -ne $t.Liczba) {
    $w = Poziomy
    $duza = Etykieta ("~" + (Liczba-Ludzka $t.Liczba)) $script:CzDuza $script:KolTekst
    $duza.Margin = New-Object System.Windows.Forms.Padding(0, 2, 5, 0)
    $w.Controls.Add($duza)
    $jed = Etykieta "tokenów" $script:CzZwykla $script:KolSzary
    $jed.Margin = New-Object System.Windows.Forms.Padding(0, 16, 0, 0)
    $w.Controls.Add($jed)
    $k.Controls.Add($w)
    if ($t.Ogon) { $k.Controls.Add((Etykieta-Zawijana $t.Ogon $script:CzMala $script:KolSzary $szer)) }
    # Dopisek "za jaki okres i czy to nadrabianie" - kolor tylko wtedy, gdy
    # niesie znaczenie (czerwony: zwykly dzien nad progiem; zolty: nadrabianie
    # albo okres nieznany); zwykly dzien dostaje neutralna szara plakietke.
    if ($t.Znacznik) {
      $kol = $script:KolSzary; $tlo = $script:TloZnacz
      if ($t.ZnacznikWaga -eq "pilne") { $kol = $script:KolPilne; $tlo = $script:TloPilne }
      elseif ($t.ZnacznikWaga) { $kol = $script:KolUwaga; $tlo = $script:TloUwaga }
      $z = Etykieta-Zawijana $t.Znacznik $script:CzMalaGruba $kol $szer
      $z.BackColor = $tlo
      $z.Padding = New-Object System.Windows.Forms.Padding(6, 2, 6, 3)
      $z.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
      $k.Controls.Add($z)
    }
  } else {
    # Zero znaczyloby "nic nie kosztuje" - a my po prostu nie wiemy. Mowimy to
    # wprost i podajemy powod, zamiast pokazac liczbe, ktorej nie mamy.
    $k.Controls.Add((Etykieta "nie wiem" $script:CzDuza $script:KolUwaga))
    $k.Controls.Add((Etykieta-Zawijana $t.Powod $script:CzMala $script:KolUwaga $szer))
  }
  $opis = Etykieta-Zawijana $t.Opis $script:CzMala $script:KolSzary $szer
  $opis.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
  $k.Controls.Add($opis)
  return $k
}

function Odmaluj-Liczby {
  if (-not $script:PanelLiczby -or $script:PanelLiczby.IsDisposed) { return }
  Wyczysc-Panel $script:PanelLiczby
  $r = $null; $c = $null
  if ($script:Dane) { $r = $script:Dane.Rachunek; $c = $script:Dane.Cykl }
  $trzy = @()
  try { $trzy = Trzy-Liczby $r $c }
  catch { Zanotuj-Wywrotke "zlozenie trzech liczb" $_ }
  if (@($trzy).Count -eq 0) {
    $script:PanelLiczby.Controls.Add((Etykieta-Zawijana (
      "Liczb jeszcze nie ma - nie udało się ich złożyć. Powód jest w zakładce Szczegóły.") $script:CzZwykla $script:KolUwaga $script:SzerTresc))
    return
  }
  $karty = @()
  foreach ($t in $trzy) { $karty += (Kafelek-Liczby $t) }
  # Trzy karty rowne wysokoscia - nierowne wygladaja jak zrobione byle jak.
  $max = 0
  foreach ($kk in $karty) {
    $h = $kk.GetPreferredSize((New-Object System.Drawing.Size($script:SzerKafelka, 0))).Height
    if ($h -gt $max) { $max = $h }
  }
  foreach ($kk in $karty) {
    $kk.MinimumSize = New-Object System.Drawing.Size($script:SzerKafelka, $max)
    $script:PanelLiczby.Controls.Add($kk)
  }
  $karty[$karty.Count - 1].Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
}

function Liczba-Boczna($panel, [string]$podpis, [string]$wartosc) {
  $panel.Controls.Add((Etykieta $podpis $script:CzMala $script:KolSzary))
  $w = Etykieta $wartosc $script:CzSrednia $script:KolTekst
  $w.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
  $panel.Controls.Add($w)
}

function Znak-Legendy($panel, $kolor, [string]$napis) {
  $kw = Etykieta "■" $script:CzZwykla $kolor
  $kw.Margin = New-Object System.Windows.Forms.Padding(0, 0, 2, 0)
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
  $szer = $script:SzerKarty - 32

  $script:KartaStat.Controls.Add((Etykieta "Koszt nauki z rozmów - ostatnie 30 dni" $script:CzGruba $script:KolTekst))
  if (-not $st) {
    $script:KartaStat.Controls.Add((Etykieta-Zawijana "Statystyki nie udało się złożyć - powód jest w dzienniku nadzorcy." $script:CzZwykla $script:KolUwaga $szer))
    return
  }

  $wiersz = Poziomy
  $wiersz.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 4)
  $gospodarz = New-Object System.Windows.Forms.Panel
  $gospodarz.Size = New-Object System.Drawing.Size(536, 180)
  $gospodarz.Margin = New-Object System.Windows.Forms.Padding(0)
  $gospodarz.BackColor = [System.Drawing.Color]::White
  Wstaw-Wykres $gospodarz $st
  $wiersz.Controls.Add($gospodarz)

  $boczne = Pionowy ($szer - 536 - 20)
  $boczne.Margin = New-Object System.Windows.Forms.Padding(20, 0, 0, 0)
  Liczba-Boczna $boczne "Ostatnie 7 dni" (Tokeny-Albo-Brak $st.Suma7)
  Liczba-Boczna $boczne "Ostatnie $($st.OknoDni) dni" (Tokeny-Albo-Brak $st.Suma30)
  if ($null -ne $st.Srednia) {
    Liczba-Boczna $boczne "Średnio na dzień nauki (z $($st.SredniaDni) $(Odmiana $st.SredniaDni 'dnia' 'dni' 'dni'))" "~$(Liczba-Ludzka $st.Srednia) tokenów"
  } else {
    Liczba-Boczna $boczne "Średnio na dzień nauki" "jeszcze nie wiem"
  }
  if (($null -ne $st.Typowy) -and ($st.TypowychDni -gt 0)) {
    Liczba-Boczna $boczne "Zwykły dzień, bez nadrabiania (z $($st.TypowychDni) $(Odmiana $st.TypowychDni 'dnia' 'dni' 'dni'))" "ok. $(Okolo $st.Typowy) tokenów"
  } else {
    Liczba-Boczna $boczne "Zwykły dzień, bez nadrabiania" "jeszcze nie wiem"
  }
  $wiersz.Controls.Add($boczne)
  $script:KartaStat.Controls.Add($wiersz)

  if ($st.DniZDanymi -gt 0) {
    $leg = Poziomy
    $leg.Margin = New-Object System.Windows.Forms.Padding(54, 0, 0, 2)
    Znak-Legendy $leg $script:KolSlupek "zwykły dzień"
    Znak-Legendy $leg $script:KolNadrab "nadrabianie zaległości"
    if (@(@($st.Dni) | Where-Object { $_.Nieznane -gt 0 }).Count -gt 0) { Znak-Legendy $leg $script:KolNiezn "okres nieznany" }
    if ($null -ne $st.Prog) {
      $napis = "- - próg zwykłego dnia: $(Liczba-Ludzka $st.Prog)"
      if (-not (Prog-Widoczny $st)) { $napis = "próg zwykłego dnia ($(Liczba-Ludzka $st.Prog)) - daleko ponad słupkami" }
      $leg.Controls.Add((Etykieta $napis $script:CzMala $script:KolPilne))
    }
    $script:KartaStat.Controls.Add($leg)
  }
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
  $w.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
  $szer = $script:SzerKarty - 32
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
  $szer = $script:SzerKarty - 32
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
    Ustaw-Rozwiniecie-Zmian
    Dopasuj-Wysokosc
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
  $n = Napisy-Przyciskow $script:Dane
  $script:BAktualizuj.Text = $n.Aktualizuj
  $script:LAktualizuj.Text = $n.AktualizujOpis
  $script:BCykl.Text       = $n.Cykl
  $script:LCykl.Text       = $n.CyklOpis
  $script:BCykl.Enabled    = $n.CyklWlaczony
}

# Wysokosc dobierana pod PRZEGLAD, a nie na sztywno: na zwyklym ekranie okno
# ma sie miescic bez przewijania. Szczegoly zajmuja to samo miejsce (widok
# obok, nie pod spodem), wiec przelaczenie nie szarpie oknem. Gdy tresc i tak
# nie miesci sie na ekranie, przeglad sie przewija - nic nie znika.
function Dopasuj-Wysokosc {
  if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
  try {
    $script:Root.PerformLayout()
    $ramka = $script:Okno.Height - $script:Okno.ClientSize.Height
    $trzeba = $script:Naglowek.Height + $script:Root.PreferredSize.Height + $script:WidokPrzeglad.Padding.Vertical +
              $script:Pasek.Height + $ramka + 4
    $obszar = [System.Windows.Forms.Screen]::FromControl($script:Okno).WorkingArea
    $script:Okno.Height = [math]::Max(420, [math]::Min($trzeba, $obszar.Height - 40))
    # Okno wysrodkowane przy starcie na innej wysokosci po zmianie wysokosci
    # wystawaloby dolem za ekran - a razem z nim przyciski.
    if ($script:Okno.Bottom -gt $obszar.Bottom) {
      $script:Okno.Top = [math]::Max($obszar.Top, $obszar.Bottom - $script:Okno.Height)
    }
  } catch { Zanotuj-Wywrotke "dobranie wysokosci okna" $_ }
}

function Odmaluj-Okno {
  if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
  $script:Okno.SuspendLayout()
  try {
    Odmaluj-Podtytul
    Odmaluj-Problemy
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
  Dopasuj-Wysokosc
}

# --- dane dla okna -----------------------------------------------------------

function Napelnij-Szczegoly {
  if (-not $script:PoleSzczegoly -or $script:PoleSzczegoly.IsDisposed) { return }
  if ($null -eq $script:Rozbicie) {
    $script:PoleSzczegoly.Text = "Liczę rozbicie rachunku..."
    $script:Okno.Refresh()
    try { $script:Rozbicie = Rachunek-Rozbicie }
    catch {
      Zanotuj-Wywrotke "rachunek za pamiec (rozbicie)" $_
      $script:Rozbicie = @("  NIE UDALO SIE POLICZYC ROZBICIA: $($_.Exception.Message)")
    }
  }
  try { $script:PoleSzczegoly.Lines = [string[]](Zbuduj-Szczegoly $script:Dane $script:Wywrotki $script:Rozbicie) }
  catch {
    Zanotuj-Wywrotke "zlozenie szczegolow" $_
    $script:PoleSzczegoly.Text = "NIE UDALO SIE ZLOZYC SZCZEGOLOW: $($_.Exception.Message)"
  }
  $script:PoleSzczegoly.SelectionStart = 0
  $script:PoleSzczegoly.ScrollToCaret()
}

# Przelaczenie widoku. Szczegoly napelniaja sie przy wejsciu - chyba ze stoi
# w nich odpowiedz na klikniecie (SzczegolyZajete), ktorej nie wolno podmienic.
function Pokaz-Widok([string]$nazwa) {
  if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
  $script:Widok = $nazwa
  $szcz = ($nazwa -eq "szczegoly")
  $script:WidokSzczegoly.Visible = $szcz
  $script:WidokPrzeglad.Visible = (-not $szcz)
  Styl-Przelacznika $script:BPrzeglad (-not $szcz)
  Styl-Przelacznika $script:BSzczegoly $szcz
  if ($szcz -and (-not $script:SzczegolyZajete)) { Napelnij-Szczegoly }
}

# Przeliczenie BEZ zagladania do sieci - po nowsza wersje chodzi dozor, ktory
# nikogo nie trzyma. Dzieki temu otwarcie okna nie czeka na gita.
function Odswiez-Dane {
  $script:Licze = $true
  Odmaluj-Podtytul
  if ($script:Okno -and -not $script:Okno.IsDisposed) { $script:Okno.Refresh() }
  try {
    $script:Dane = Zbierz-Wszystko $false $true
    $script:DaneCzas = [datetime]::Now
    $script:DaneBlad = $null
    $script:Rozbicie = $null
    if (($script:Widok -eq "szczegoly") -and (-not $script:SzczegolyZajete)) {
      Napelnij-Szczegoly
    }
  } catch {
    # Cisza jest zakazana: nieudane przeliczenie MA byc widoczne w oknie jako
    # zolta karta, a nie schowane za starymi liczbami udajacymi biezace.
    Zanotuj-Wywrotke "przeliczenie danych dla okna" $_
    $script:DaneBlad = $_.Exception.Message
  }
  $script:Licze = $false
}

# Okno ODSWIEZA SIE SAMO przy kazdym otwarciu - dlatego nie ma przycisku
# [Odswiez]. Przeliczenie rusza dopiero po odmalowaniu okna (stad zegar na
# 150 ms zamiast wolania wprost): uzytkownik widzi najpierw liczby z bufora
# razem z godzina, z ktorej pochodza, a nie pusty ekran przez kilka sekund.
function Zaplanuj-Przeliczenie {
  if (-not $script:ZegarOtwarcia) {
    $script:ZegarOtwarcia = New-Object System.Windows.Forms.Timer
    $script:ZegarOtwarcia.Add_Tick({
      $script:ZegarOtwarcia.Stop()
      Odswiez-Dane
      Odmaluj-Okno
      if ($script:Ikona) {
        try { $script:Ikona.Text = Podpowiedz $script:Dane } catch { Zanotuj-Wywrotke "podpowiedz przy ikonie" $_ }
      }
    })
  }
  $script:ZegarOtwarcia.Stop()
  $script:ZegarOtwarcia.Interval = 150
  $script:ZegarOtwarcia.Start()
}

# --- budowa okna -------------------------------------------------------------

function Pokaz-Okno {
  if ($script:Okno -and -not $script:Okno.IsDisposed) {
    $script:Okno.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $script:Okno.Show()
    Wymus-Pokazanie $script:Okno
    Odmaluj-Okno
    Zaplanuj-Przeliczenie
    return
  }

  $f = New-Object System.Windows.Forms.Form
  $f.Text = "MegaRuchacz"
  $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
  $f.MaximizeBox = $false
  $f.ClientSize = New-Object System.Drawing.Size($script:SzerOkna, 720)
  $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
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
  $script:Pasek.Padding = New-Object System.Windows.Forms.Padding(24, 12, 24, 12)
  $script:Pasek.BackColor = $script:TloPaska
  $script:Pasek.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 39))) | Out-Null
  $script:Pasek.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 39))) | Out-Null
  $script:Pasek.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 22))) | Out-Null
  $script:Pasek.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38))) | Out-Null
  $script:Pasek.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null
  # cienka kreska nad paskiem - oddziela przyciski od tresci bez ciezkiej ramki
  $script:Pasek.Add_Paint({ param($nadawca, $e) try { $e.Graphics.DrawLine($script:PioroRamki, 0, 0, $nadawca.Width, 0) } catch { if (-not $script:RamkaZawiodla) { $script:RamkaZawiodla = $true; Zanotuj-Wywrotke "rysowanie kreski nad przyciskami" $_ } } })

  $script:BAktualizuj = Nowy-Przycisk "Sprawdź i pobierz nowszą wersję MegaRuchacza"
  $script:BCykl       = Nowy-Przycisk "Przeczytaj zaległe rozmowy"
  $bZamknij           = Nowy-Przycisk "Zamknij okno"
  $script:LAktualizuj = Etykieta-Zawijana "" $script:CzMala $script:KolSzary 290
  $script:LCykl       = Etykieta-Zawijana "" $script:CzMala $script:KolSzary 290
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
  $script:Naglowek.Height = 70
  $script:Naglowek.BackColor = $script:TloOkna
  $lTytul = Etykieta "MegaRuchacz" $script:CzTytul $script:KolTekst
  $lTytul.Location = New-Object System.Drawing.Point(22, 12)
  $script:LPodtytul = Etykieta-Zawijana "Przeliczam, to potrwa kilka sekund..." $script:CzMala $script:KolSzary 560
  $script:LPodtytul.Location = New-Object System.Drawing.Point(25, 44)
  $przel = New-Object System.Windows.Forms.Panel
  $przel.Size = New-Object System.Drawing.Size(214, 34)
  $przel.Location = New-Object System.Drawing.Point(($script:SzerOkna - 24 - 214), 20)
  $przel.BackColor = $script:TloPrzel
  $script:BPrzeglad  = Przycisk-Przelacznika "Przegląd" 3
  $script:BSzczegoly = Przycisk-Przelacznika "Szczegóły" 107
  $przel.Controls.Add($script:BPrzeglad)
  $przel.Controls.Add($script:BSzczegoly)
  $script:Naglowek.Controls.Add($lTytul)
  $script:Naglowek.Controls.Add($script:LPodtytul)
  $script:Naglowek.Controls.Add($przel)

  # Widok przegladu: karty jedna pod druga. Przewija sie wylacznie wtedy, gdy
  # ekran jest nizszy niz tresc - wtedy nic nie znika pod krawedzia.
  $script:WidokPrzeglad = New-Object System.Windows.Forms.Panel
  $script:WidokPrzeglad.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:WidokPrzeglad.AutoScroll = $true
  $script:WidokPrzeglad.BackColor = $script:TloOkna
  $script:WidokPrzeglad.Padding = New-Object System.Windows.Forms.Padding(24, 4, 24, 8)

  $script:Root = Pionowy $script:SzerTresc
  $script:Root.Dock = [System.Windows.Forms.DockStyle]::Top

  $script:PanelProblemy = Pionowy $script:SzerTresc
  $script:PanelProblemy.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
  $script:PanelProblemy.Visible = $false

  $script:PanelLiczby = Poziomy
  $script:PanelLiczby.Margin = New-Object System.Windows.Forms.Padding(0)

  $script:KartaStat = Nowa-Karta $script:SzerKarty
  $script:PanelStan = Nowa-Karta $script:SzerKarty
  $script:PanelStan.Margin = New-Object System.Windows.Forms.Padding(0)

  $script:Root.Controls.Add($script:PanelProblemy)
  $script:Root.Controls.Add($script:PanelLiczby)
  $script:Root.Controls.Add($script:KartaStat)
  $script:Root.Controls.Add($script:PanelStan)
  $script:WidokPrzeglad.Controls.Add($script:Root)

  # Widok szczegolow: ten sam obszar, biala karta z polem tekstowym, ktore
  # przewija sie samo - okno nie rosnie od tego ani o piksel.
  $script:WidokSzczegoly = New-Object System.Windows.Forms.Panel
  $script:WidokSzczegoly.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:WidokSzczegoly.BackColor = $script:TloOkna
  $script:WidokSzczegoly.Padding = New-Object System.Windows.Forms.Padding(24, 4, 24, 12)
  $script:WidokSzczegoly.Visible = $false
  $kartaSz = New-Object System.Windows.Forms.Panel
  $kartaSz.Dock = [System.Windows.Forms.DockStyle]::Fill
  $kartaSz.BackColor = $script:TloKarty
  $kartaSz.Padding = New-Object System.Windows.Forms.Padding(12, 10, 4, 4)
  $kartaSz.Add_Paint({ param($nadawca, $e) Obrysuj $nadawca $e })
  $script:PoleSzczegoly = New-Object System.Windows.Forms.TextBox
  $script:PoleSzczegoly.Multiline = $true
  $script:PoleSzczegoly.ReadOnly = $true
  $script:PoleSzczegoly.WordWrap = $false
  $script:PoleSzczegoly.BorderStyle = [System.Windows.Forms.BorderStyle]::None
  $script:PoleSzczegoly.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
  $script:PoleSzczegoly.Font = $script:CzStala
  $script:PoleSzczegoly.BackColor = $script:TloKarty
  $script:PoleSzczegoly.ForeColor = $script:KolTekst
  $script:PoleSzczegoly.Dock = [System.Windows.Forms.DockStyle]::Fill
  $kartaSz.Controls.Add($script:PoleSzczegoly)
  $script:WidokSzczegoly.Controls.Add($kartaSz)

  # Kolejnosc dodawania ma znaczenie: WinForms dokuje od ostatnio dodanej
  # kontrolki, wiec wypelniajace widoki ida PIERWSZE, a naglowek i pasek po nich.
  $f.Controls.Add($script:WidokSzczegoly)
  $f.Controls.Add($script:WidokPrzeglad)
  $f.Controls.Add($script:Naglowek)
  $f.Controls.Add($script:Pasek)
  $f.Add_FormClosed({
    $script:Okno = $null; $script:Root = $null; $script:Naglowek = $null
    $script:WidokPrzeglad = $null; $script:WidokSzczegoly = $null
    $script:LPodtytul = $null; $script:PanelProblemy = $null; $script:PanelLiczby = $null
    $script:KartaStat = $null; $script:PanelStan = $null
    $script:BPrzeglad = $null; $script:BSzczegoly = $null; $script:PoleSzczegoly = $null
    $script:Pasek = $null; $script:BAktualizuj = $null; $script:LAktualizuj = $null
    $script:BCykl = $null; $script:LCykl = $null
    $script:PanelZmian = $null; $script:LinkZmian = $null
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
    $script:PoleSzczegoly.Text = "Pobieram nowszą wersję - strażnik sprawdza serwer i nanosi poprawki..."
    $script:Okno.Refresh()
    $wynik = @()
    try { $wynik = Aktualizuj }
    catch { Zanotuj-Wywrotke "aktualizacja" $_; $wynik = @("NIE UDALO SIE: $($_.Exception.Message)") }
    $script:PoleSzczegoly.Lines = [string[]](
      @("CO POWIEDZIAŁ STRAŻNIK", "") + $wynik +
      @("", "To jest odpowiedź na kliknięcie, nie zwykła zawartość szczegółów.",
            "Kliknij [Przegląd], żeby wrócić do liczb."))
    $script:Okno.Refresh()
    $script:BAktualizuj.Enabled = $true
    $script:Rozbicie = $null
    Odswiez-Dane
    Odmaluj-Okno
  })

  # JEDYNY przycisk w tym oknie, ktory wydaje tokeny - i dlatego jedyny, ktory
  # pyta. 24.09.2026 jego poprzednik ("Uruchom cykl teraz") wydal jednym
  # kliknieciem 312 609 tokenow, nie mowiac o tym ani slowa wczesniej.
  # Domyslnie podswietlone jest "Nie": przypadkowy Enter ma nic nie kosztowac.
  $script:BCykl.Add_Click({
    $n = Napisy-Przyciskow $script:Dane
    $s = $n.Szacunek
    $t = @()
    if ($s -and ($null -ne $s.Tokeny)) {
      $t += "Przeczytanie zaległych rozmów będzie kosztować około $(Liczba-Ludzka $s.Tokeny) tokenów."
    } else {
      $t += "NIE WIEM, ile to będzie kosztować."
      if ($s -and $s.Powod) { $t += "Powód: $($s.Powod)." }
      if ($script:Dane -and $script:Dane.Cykl -and ($null -ne $script:Dane.Cykl.Koszt)) {
        $t += "Poprzednie czytanie kosztowało ~$(Liczba-Ludzka $script:Dane.Cykl.Koszt) tokenów - takiego rzędu liczby się spodziewaj."
      }
    }
    $t += ""
    if ($s) { foreach ($z in $s.Podstawa) { $t += $z } }
    $t += ""
    $t += "To jedyny przycisk w tym oknie, który naprawdę wydaje tokeny."
    $t += "Kliknij Tak, żeby uruchomić. Po kliknięciu Nie nie stanie się nic."
    $odp = [System.Windows.Forms.MessageBox]::Show(
      $script:Okno, ($t -join "`r`n"), "Przeczytać zaległe rozmowy?",
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
  Pokaz-Widok "przeglad"
  $f.Show()
  Wymus-Pokazanie $f
  Odmaluj-Okno
  Zaplanuj-Przeliczenie
}

# ----------------------------------------------------------------- ikona i menu

$script:Ikona = New-Object System.Windows.Forms.NotifyIcon
$script:Ikona.Icon = Ikona-Nadzorcy
$script:Ikona.Text = "MegaRuchacz - zbieram dane"
$script:Ikona.Visible = $true

function Pokaz-Dymek([string]$tytul, [string]$tresc) {
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
    $d = Zbierz-Wszystko $true $true
    $script:Dane = $d
    $script:DaneCzas = [datetime]::Now
    $script:DaneBlad = $null
    $script:Rozbicie = $null
    $script:Ikona.Text = Podpowiedz $d
    Odmaluj-Okno
    Pokaz-Dymek "MegaRuchacz: przeliczone" "Liczby sa swieze. Kliknij ikone, zeby je zobaczyc."
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
    # przed ekranem. Okno dostaje gotowa odpowiedz i otwiera sie od razu.
    $d = Dozor $script:Dymek $true $true
    $script:Dane = $d
    $script:DaneCzas = [datetime]::Now
    $script:DaneBlad = $null
    $script:Rozbicie = $null
    $script:Ikona.Text = Podpowiedz $d
    # Otwarte okno ma sie odswiezyc samo - uzytkownik nie ma go zamykac
    # i otwierac po to, zeby zobaczyc nowe liczby.
    Odmaluj-Okno
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
