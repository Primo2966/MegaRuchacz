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
function Zbuduj-Przod($d, $problemy, $czas, $start) {
  $l = @()
  $l += "MegaRuchacz - nadzorca                      [ Przegląd | Szczegóły | Warstwy pamięci ]   <- przełącznik widoków u góry okna"
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
    $l += "WARTO WIEDZIEĆ   (w oknie: żółta karta z dopiskiem 'dla informacji - nic nie trzeba robić', bez dymka)"
    foreach ($p in $info) {
      $l += "  [i] $($p.Tytul)"
      if ($p.Porada) { $l += "      $($p.Porada)" }
    }
    $l += ""
  }

  $l += "OTWARCIE SESJI   (w oknie: karta z dużą liczbą i paskiem - MegaRuchacz kontra sam Claude Code)"
  $os = $null
  try { $os = Opis-Startu $start } catch { Zanotuj-Wywrotke "otwarcie sesji do wydruku" $_ }
  if (-not $os) {
    $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy"
  } elseif (-not $os.Zmierzone) {
    $l += "  nie zmierzono, bo $($os.Powod)."
    if ($null -ne $os.Mr) { $l += "  sama część MegaRuchacza (z rachunku): ~$(Liczba-Ludzka $os.Mr) tokenów - procentu nie ma, bo nie ma całości" }
  } else {
    $l += "  Otwarcie sesji: ~$(Okolo $os.Razem) tokenów. Z tego MegaRuchacz: $(Okolo $os.Mr) ($($os.MrProc)) · Claude Code sam: $(Okolo $os.Cc) ($($os.CcProc))"
    $l += "  $($os.Portfel)"
    $l += "  $($os.Podstawa) $($os.Zakres)"
    $l += "  $($os.WorkerZdanie)"
  }
  $l += ""

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
  $l += "  [Przegląd] / [Szczegóły] / [Warstwy pamięci]  (przełącznik u góry)"
  $l += "      Szczegóły i warstwy - z czego to się składa i gdzie to leży - zajmują miejsce przeglądu. Nic nie uruchamiają i nic nie kosztują."
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
  @("KAZDEJ", "każdej"), @("kazdej", "każdej"), @("wiadomosci", "wiadomości"), @("wiadomosc", "wiadomość"),
  @("tokenow", "tokenów"), @("RAZ NA DOBE", "raz na dobę"), @("RAZ", "raz"), @("uczenie sie", "nauka"),
  @("wczesniejszych", "wcześniejszych"), @("stala", "stała"), @("biezaca", "bieżąca"), @("dzis", "dziś"),
  @("wywolan", "wywołań"), @("faktow", "faktów"), @("zwykly", "zwykły"), @("dzien", "dzień"),
  @("placona", "płacona"), @("wolaniem", "wołaniem"), @("wygasaja", "wygasają"), @("kosztuja", "kosztują"),
  @("dopoki", "dopóki"), @("wpisow", "wpisów"), @("pamiec", "pamięć"), @("sciezka", "ścieżka"),
  @("caly", "cały"), @("czesc", "część"), @("Biezace", "Bieżące"), @("rozmow", "rozmów"), @("zadan", "zadań"),
  @("czlowiek", "człowiek"), @("recznie", "ręcznie"), @("sie", "się"), @("kazdej", "każdej"),
  @("zaden", "żaden"), @("siega", "sięga"), @("narzedziami", "narzędziami")
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
function Dodaj-Rozbicie($s, $rozbicie) {
  $kol = @(@{ N = "Pozycja"; S = 250 }, @{ N = "Udział"; S = 170; Pasek = $true }, @{ N = "Tokeny"; S = 100; P = $true },
           @{ N = ""; S = 60; P = $true }, @{ N = "Uwaga"; S = 0 })
  $wiersze = @()
  $zrzuc = {
    if ($wiersze.Count -gt 0) { Dodaj-Tabele $s $kol $wiersze; Set-Variable -Name wiersze -Value @() -Scope 1 }
  }
  $pierwsza = $true
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
      $wiersze += ,@((Po-Polsku $m.Groups[1].Value.Trim()), $pasek, $m.Groups[3].Value, $procTxt, (Po-Polsku $m.Groups[5].Value.Trim()))
      continue
    }
    & $zrzuc
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
      Dodaj-Wiersz $s "" "$($a.Tresc)" "szary"
    }
  }
  if ($d -and $d.Rachunek -and $d.Rachunek.Linia) {
    Dodaj-Wiersz $s "Linia rachunku" "$($d.Rachunek.Linia)" "szary"
    Dodaj-Wiersz $s "" "ta sama, którą strażnik pokazuje przy starcie sesji" "szary"
  }
  $lista += $s

  # 2. Otwarcie sesji - skad liczby z karty na Przegladzie.
  $s = Nowa-Sekcja "Otwarcie sesji - skąd ta liczba" "Ile tokenów wchodzi do modelu przy pierwszej wiadomości w sesji i jaka część z tego to MegaRuchacz."
  $o = $null
  try { $o = Opis-Startu $start } catch { Zanotuj-Wywrotke "opis otwarcia sesji do szczegolow" $_ }
  if (-not $start) {
    Dodaj-Tekst $s "Jeszcze nie zmierzone - pomiar rusza przy otwarciu okna." "szary"
  } elseif (-not $o -or -not $o.Zmierzone) {
    $pw = "nie wiadomo dlaczego"
    if ($o -and $o.Powod) { $pw = $o.Powod }
    Dodaj-Wiersz $s "Całość" "nie zmierzono, bo $pw" "uwaga"
    if ($o -and ($null -ne $o.Mr)) { Dodaj-Wiersz $s "MegaRuchacz (rachunek)" "~$(Liczba-Ludzka $o.Mr) tokenów - bez całości nie ma z czego policzyć procentu" }
  } else {
    Dodaj-Wiersz $s "Razem na otwarcie" "~$(Liczba-Ludzka $o.Razem) tokenów (mediana z $($o.Sesji) sesji)"
    Dodaj-Wiersz $s "MegaRuchacz" "~$(Liczba-Ludzka $o.Mr) tokenów ($($o.MrProc)) - $(Liczba-Ludzka $start.MrStart) na start + $(Liczba-Ludzka $start.MrWiadomosc) przypomnienia doklejonego do pierwszej wiadomości"
    Dodaj-Wiersz $s "Claude Code sam" "~$(Liczba-Ludzka $o.Cc) tokenów ($($o.CcProc)) - jego instrukcje, opisy narzędzi (także z serwerów MCP), lista skilli"
    if ($o.Worker) { Dodaj-Wiersz $s "Start workera" ($o.WorkerZdanie -replace '^Start jednego workera: ', '') }
    else { Dodaj-Wiersz $s "Start workera" ($o.WorkerZdanie -replace '^Start jednego workera: ', '') "uwaga" }
    Dodaj-Wiersz $s "Jak to zmierzone" ("W każdym transkrypcie Claude Code pierwsza odpowiedź modelu ma pole usage: suma input_tokens, " +
      "cache_creation_input_tokens i cache_read_input_tokens to cały kontekst w tej chwili. Od tego odejmuję Twoją pierwszą wiadomość " +
      "(jej znaki / 3) i biorę medianę z ostatnich sesji.") "szary"
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
      Dodaj-Podtytul $s "Sesje, z których jest mediana"
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
  if ($null -ne $rozbicie) { Dodaj-Rozbicie $s $rozbicie }
  else { Dodaj-Tekst $s "Jeszcze nie policzone." "szary" }
  $lista += $s

  # 4. Nauka z rozmow.
  $s = Nowa-Sekcja "Nauka z rozmów" "Raz dziennie MegaRuchacz czyta Twoje rozmowy i wyciąga z nich fakty do pamięci. To jedyne miejsce, gdzie naprawdę woła model."
  if ($d -and $d.Cykl) { Dodaj-Wiersze $s (Opis-Cyklu $d.Cykl) }
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
    Dodaj-Wiersz $s "Próg zwykłego dnia" "$(Tokeny-Albo-Brak $st.Prog) - uzasadnienie na górze narzedzia\koszt-pamieci.ps1"
    $dni = @()
    foreach ($x in @(@($st.Dni) | Where-Object { $_.Jest })) {
      $dni += ,@($x.Dzien.ToString('yyyy-MM-dd'), (Liczba-Ludzka $x.Razem), (Liczba-Ludzka $x.Zwykle), (Liczba-Ludzka $x.Nadrabianie), (Liczba-Ludzka $x.Nieznane))
    }
    if ($dni.Count -gt 0) {
      Dodaj-Tabele $s @(@{ N = "Dzień"; S = 120 }, @{ N = "Razem"; S = 110; P = $true }, @{ N = "Zwykły dzień"; S = 120; P = $true },
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
    $start = $null
    try { $start = Pomiar-Startu } catch { Zanotuj-Wywrotke "pomiar otwarcia sesji" $_ }
    $roz = @()
    try { $roz = Rachunek-Rozbicie }
    catch { Zanotuj-Wywrotke "rachunek za pamiec (rozbicie)" $_; $roz = @("  NIE UDALO SIE POLICZYC - szczegoly w dzienniku nadzorcy") }
    Zbuduj-Przod $d $probl ([datetime]::Now) $start | ForEach-Object { Write-Output $_ }
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
  try { $start = Pomiar-Startu } catch { Zanotuj-Wywrotke "pomiar otwarcia sesji" $_ }
  $roz = @()
  try { $roz = Rachunek-Rozbicie }
  catch { Zanotuj-Wywrotke "rachunek za pamiec (rozbicie)" $_; $roz = @("  NIE UDALO SIE POLICZYC - szczegoly w dzienniku nadzorcy") }
  Zbuduj-Przod $d $probl ([datetime]::Now) $start | ForEach-Object { Write-Output $_ }
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
# Pomiar otwarcia sesji z transkryptow (Pomiar-Startu). Liczony przy otwarciu okna
# i przy recznym przeliczeniu - nie w dozorze co kwadrans, bo nikt go wtedy nie oglada.
$script:Start          = $null
$script:UdzialStartu   = 0.0
$script:PodgladInfo    = $null   # dwie kolumny nad trescia podgladu warstwy
$script:BWarstwy       = $null   # trzeci przycisk przelacznika
$script:WidokWarstwy   = $null   # warstwy pamieci: lista po lewej, podglad po prawej
$script:LWarstwy       = $null   # jedno zdanie podsumowania nad lista
$script:ListaWarstw    = $null
$script:PodgladWarstwy = $null
# Odpowiedz Warstwy-Pamieci - liczona dopiero przy wejsciu w zakladke, bo wola
# osobny proces, a przeglad ma sie otwierac bez czekania.
$script:DaneWarstw     = $null
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
# bylby ucieciem po cichu. Trzy karty kosztow dziela tresc po rowno.
$script:ObszarEkranu = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$script:SzerOkna    = [int][math]::Max(900, [math]::Min(1240, $script:ObszarEkranu.Width - 80))
$script:Margines    = 28
$script:SzerTresc   = $script:SzerOkna - 2 * $script:Margines - 20
$script:SzerKarty   = $script:SzerTresc
$script:Odstep      = 16
$script:SzerKafelka = [int][math]::Floor(($script:SzerTresc - 2 * $script:Odstep) / 3)
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
    if (-not $script:RysowanieZawiodlo) { $script:RysowanieZawiodlo = $true; Zanotuj-Wywrotke "rysowanie paska otwarcia sesji" $_ }
  }
}

function Odmaluj-Start {
  if (-not $script:KartaStart -or $script:KartaStart.IsDisposed) { return }
  Wyczysc-Panel $script:KartaStart
  $szer = $script:SzerKarty - 44
  $tyt = Etykieta "Otwarcie sesji" $script:CzGruba $script:KolTekst
  $script:KartaStart.Controls.Add($tyt)
  $pod = Etykieta-Zawijana "Ile tokenów trafia do modelu, zanim napiszesz pierwsze słowo - i ile z tego dokłada MegaRuchacz." $script:CzMala $script:KolSzary $szer
  $pod.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
  $script:KartaStart.Controls.Add($pod)

  if ($null -eq $script:Start) {
    $script:KartaStart.Controls.Add((Etykieta-Zawijana "Mierzę w transkryptach Claude Code - to potrwa kilka sekund..." $script:CzZwykla $script:KolSzary $szer))
    return
  }
  $o = $null
  try { $o = Opis-Startu $script:Start } catch { Zanotuj-Wywrotke "opis otwarcia sesji" $_ }
  if (-not $o -or -not $o.Zmierzone) {
    $pw = "nie wiadomo dlaczego - to samo w sobie jest usterką"
    if ($o -and $o.Powod) { $pw = $o.Powod }
    $script:KartaStart.Controls.Add((Etykieta "nie zmierzono" $script:CzDuza $script:KolUwaga))
    $script:KartaStart.Controls.Add((Etykieta-Zawijana "Nie zmierzono, bo $pw." $script:CzZwykla $script:KolUwaga $szer))
    if ($o -and ($null -ne $o.Mr)) {
      $czescMr = "Sama część MegaRuchacza (z rachunku): ~$(Liczba-Ludzka $o.Mr) tokenów."
      if ($o.Mr -le 0) { $czescMr = "Rachunek MegaRuchacza też nie znalazł nic doklejanego do sesji - powód jest w zakładce Szczegóły." }
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
  $jed = Etykieta "tokenów na otwarcie każdej sesji" $script:CzZwykla $script:KolSzary
  $jed.Margin = New-Object System.Windows.Forms.Padding(0, 14, 0, 0)
  $wiersz.Controls.Add($jed)
  $script:KartaStart.Controls.Add($wiersz)

  $pasek = New-Object System.Windows.Forms.PictureBox
  $pasek.Size = New-Object System.Drawing.Size($szer, 14)
  $pasek.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 10)
  $pasek.Add_Paint({ param($nadawca, $e) Rysuj-Pasek-Startu $e.Graphics $nadawca.ClientSize })
  $script:KartaStart.Controls.Add($pasek)

  Wiersz-Legendy-Startu $script:KartaStart $script:KolMr "MegaRuchacz - zasady i wiedza o Tobie ($(Liczba-Ludzka $script:Start.MrStart)) + przypomnienie ($(Liczba-Ludzka $script:Start.MrWiadomosc))" "~$(Okolo $o.Mr)" $o.MrProc
  Wiersz-Legendy-Startu $script:KartaStart $script:KolCc "Claude Code sam - jego instrukcje i opisy narzędzi (MCP)" "~$(Okolo $o.Cc)" $o.CcProc

  $p = Etykieta-Zawijana $o.Portfel $script:CzZwykla $script:KolTekst $szer
  $p.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 6)
  $script:KartaStart.Controls.Add($p)
  $pods = (@($o.Podstawa, $o.Zakres, $o.WorkerZdanie) | Where-Object { $_ }) -join " "
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

function Kafelek-Liczby($t) {
  $k = Nowa-Karta $script:SzerKafelka
  $k.Margin = New-Object System.Windows.Forms.Padding(0, 0, $script:Odstep, 14)
  $szer = $script:SzerKafelka - 44
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
  $karty[$karty.Count - 1].Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)
}

function Liczba-Boczna($panel, [string]$podpis, [string]$wartosc) {
  $panel.Controls.Add((Etykieta $podpis $script:CzMala $script:KolSzary))
  $w = Etykieta $wartosc $script:CzSrednia $script:KolTekst
  $w.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 5)
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

  $script:KartaStat.Controls.Add((Etykieta "Koszt nauki z rozmów - ostatnie 30 dni" $script:CzGruba $script:KolTekst))
  if (-not $st) {
    $script:KartaStat.Controls.Add((Etykieta-Zawijana "Statystyki nie udało się złożyć - powód jest w dzienniku nadzorcy." $script:CzZwykla $script:KolUwaga $szer))
    return
  }

  $wiersz = Poziomy
  $wiersz.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 4)
  $gospodarz = New-Object System.Windows.Forms.Panel
  $gospodarz.Size = New-Object System.Drawing.Size(($szer - 340), 170)
  $gospodarz.Margin = New-Object System.Windows.Forms.Padding(0)
  $gospodarz.BackColor = [System.Drawing.Color]::White
  Wstaw-Wykres $gospodarz $st
  $wiersz.Controls.Add($gospodarz)

  $boczne = Pionowy 300
  $boczne.Margin = New-Object System.Windows.Forms.Padding(40, 0, 0, 0)
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
    $script:Okno.Height = [math]::Max([math]::Min(760, $obszar.Height - 40), [math]::Min($trzeba, $obszar.Height - 40))
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
  Dopasuj-Wysokosc
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

function Napelnij-Szczegoly {
  if (-not $script:ListaSzczegolow -or $script:ListaSzczegolow.IsDisposed) { return }
  if ($null -eq $script:Rozbicie) {
    Pokaz-Karty-Szczegolow @(Karta-Komunikatu "Liczę rozbicie rachunku..." @("To potrwa kilka sekund.") $null)
    $script:Okno.Refresh()
    try { $script:Rozbicie = Rachunek-Rozbicie }
    catch {
      Zanotuj-Wywrotke "rachunek za pamiec (rozbicie)" $_
      $script:Rozbicie = @("  NIE UDALO SIE POLICZYC ROZBICIA: $($_.Exception.Message)")
    }
  }
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
    "start"      { return "Raz, przy starcie sesji" }
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
    if ($null -ne $wa.Tokeny) { $t += " (~$(Liczba-Ludzka $wa.Tokeny) tokenów)" }
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
      "start"      { $czesci += "$n przy starcie sesji" }
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

function Napelnij-Warstwy {
  if (-not $script:ListaWarstw -or $script:ListaWarstw.IsDisposed) { return }
  if ($null -eq $script:DaneWarstw) {
    $script:LWarstwy.ForeColor = $script:KolSzary
    $script:LWarstwy.Text = "Zbieram listę warstw pamięci..."
    $script:Okno.Refresh()
    try { $script:DaneWarstw = Warstwy-Pamieci }
    catch {
      Zanotuj-Wywrotke "lista warstw pamieci" $_
      $script:DaneWarstw = [pscustomobject]@{ Warstwy = @(); Uwagi = @(); Powod = $_.Exception.Message; Wygenerowano = ""; TrybGlobalny = $null; Projekt = "" }
    }
  }
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
# Warstwy licza sie przy pierwszym wejsciu; nieudana proba liczy sie od nowa
# przy nastepnym, zamiast zostawiac na ekranie stary blad.
function Pokaz-Widok([string]$nazwa) {
  if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
  $script:Widok = $nazwa
  $szcz = ($nazwa -eq "szczegoly")
  $warst = ($nazwa -eq "warstwy")
  $przeg = (-not ($szcz -or $warst))
  $script:WidokSzczegoly.Visible = $szcz
  $script:WidokWarstwy.Visible = $warst
  $script:WidokPrzeglad.Visible = $przeg
  Styl-Przelacznika $script:BPrzeglad $przeg
  Styl-Przelacznika $script:BSzczegoly $szcz
  Styl-Przelacznika $script:BWarstwy $warst
  if ($szcz -and (-not $script:SzczegolyZajete)) { Napelnij-Szczegoly }
  if ($warst) {
    if ($script:DaneWarstw -and $script:DaneWarstw.Powod) { $script:DaneWarstw = $null }
    if (($null -eq $script:DaneWarstw) -or ($script:ListaWarstw.Items.Count -eq 0)) { Napelnij-Warstwy }
  }
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
    $script:DaneWarstw = $null
    try { $script:Start = Pomiar-Startu }
    catch { Zanotuj-Wywrotke "pomiar otwarcia sesji" $_; $script:Start = [pscustomobject]@{ Powod = "pomiar się wywrócił: $($_.Exception.Message)"; MrSesja = $null } }
    if (($script:Widok -eq "szczegoly") -and (-not $script:SzczegolyZajete)) {
      Napelnij-Szczegoly
    }
    if ($script:Widok -eq "warstwy") { Napelnij-Warstwy }
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
  $script:BCykl       = Nowy-Przycisk "Przeczytaj zaległe rozmowy"
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
  $przel = New-Object System.Windows.Forms.Panel
  $przel.Size = New-Object System.Drawing.Size(426, 38)
  $przel.Location = New-Object System.Drawing.Point(($script:SzerOkna - $script:Margines - 426), 10)
  $przel.BackColor = $script:TloPrzel
  $script:BPrzeglad  = Przycisk-Przelacznika "Przegląd" 3 124
  $script:BSzczegoly = Przycisk-Przelacznika "Szczegóły" 131 124
  $script:BWarstwy   = Przycisk-Przelacznika "Warstwy pamięci" 259 164
  $przel.Controls.Add($script:BPrzeglad)
  $przel.Controls.Add($script:BSzczegoly)
  $przel.Controls.Add($script:BWarstwy)
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

  $script:KartaStart = Nowa-Karta $script:SzerKarty

  $script:PanelLiczby = Poziomy
  $script:PanelLiczby.Margin = New-Object System.Windows.Forms.Padding(0)

  $script:KartaStat = Nowa-Karta $script:SzerKarty
  $script:PanelStan = Nowa-Karta $script:SzerKarty
  $script:PanelStan.Margin = New-Object System.Windows.Forms.Padding(0)

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

  # Kolejnosc dodawania ma znaczenie: WinForms dokuje od ostatnio dodanej
  # kontrolki, wiec wypelniajace widoki ida PIERWSZE, a naglowek i pasek po nich.
  $f.Controls.Add($script:WidokWarstwy)
  $f.Controls.Add($script:WidokSzczegoly)
  $f.Controls.Add($script:WidokPrzeglad)
  $f.Controls.Add($script:Naglowek)
  $f.Controls.Add($script:Pasek)
  $f.Add_FormClosed({
    $script:Okno = $null; $script:Root = $null; $script:Naglowek = $null
    $script:WidokPrzeglad = $null; $script:WidokSzczegoly = $null
    $script:LPodtytul = $null; $script:PanelProblemy = $null; $script:PanelLiczby = $null
    $script:KartaStat = $null; $script:PanelStan = $null
    $script:BPrzeglad = $null; $script:BSzczegoly = $null; $script:ListaSzczegolow = $null
    $script:KartaStart = $null; $script:PodgladInfo = $null
    $script:Pasek = $null; $script:BAktualizuj = $null; $script:LAktualizuj = $null
    $script:BCykl = $null; $script:LCykl = $null
    $script:PanelZmian = $null; $script:LinkZmian = $null
    $script:BWarstwy = $null; $script:WidokWarstwy = $null; $script:LWarstwy = $null
    $script:ListaWarstw = $null; $script:PodgladWarstwy = $null; $script:DaneWarstw = $null
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
    try { $script:Start = Pomiar-Startu }
    catch { Zanotuj-Wywrotke "pomiar otwarcia sesji" $_; $script:Start = [pscustomobject]@{ Powod = "pomiar się wywrócił: $($_.Exception.Message)"; MrSesja = $null } }
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
