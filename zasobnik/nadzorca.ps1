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
# UKLAD OKNA - przepisany 24.09.2026, bo poprzedni sypal wszystkim naraz.
#
# Uzytkownik nie jest programista i powiedzial wprost: "pelno informacji w ryj
# mam rzuconych, nie wiem na co patrzec". Stare okno pokazywalo jednym krojem
# i jedna waga: wersje, stan gita, rozbicie kosztow z paskami, stan cyklu,
# kolejke, alarmy i sciezki do plikow .ps1. Stad cztery decyzje:
#
# 1. TRZY LICZBY NA WIERZCHU, duze, kazda z jednym zdaniem CZYM JEST (nie
#    z czego sie sklada). To sa te same liczby, ktore stoja w rozbiciu - tylko
#    wyjete na wierzch. Rozbicie, paski i sciezki ida pod [Szczegoly].
# 2. SEKCJA ROZWIJANA, a nie zakladki. Zakladka z nazwa w rodzaju "Rozbicie"
#    wisialaby na wierzchu zawsze i zapraszala do klikania w zargon; przycisk
#    "Pokaz szczegoly" jest schowany dopoty, dopoki ktos go nie chce, a okno
#    w stanie normalnym miesci sie na ekranie bez przewijania.
# 3. SEKCJA PROBLEMOW ZNIKA, gdy problemow nie ma - nie zostawia pustej ramki.
#    Gdy jest problem, stoi jako pierwsza, na kolorowym tle, z porada bez zargonu.
# 4. KAZDY PRZYCISK MOWI, CO ZROBI, a ten jeden, ktory wydaje tokeny, ma szacunek
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
  $d = [pscustomobject]@{ Wersja = $null; Cykl = $null; Rachunek = $null; Alarmy = @(); Pamiec = $null; Przeliczanie = $null }

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
      $lista += Problem (Waga-Alarmu $a.Temat) (Bez-Przedrostka $a.Tytul) (Porada-Ludzka $a.Tresc) $a.Tresc
    }
    if ((-not $d.Rachunek) -or (-not $d.Cykl)) {
      $lista += Problem "uwaga" "Nie wszystko udało się odczytać" (
        "Część liczb w tym oknie może być niepełna, a alarmów w ogóle nie policzyłem. " +
        "Rozwiń szczegóły - tam stoi, czego zabrakło.") ""
    }
  } else {
    $lista += Problem "uwaga" "Nie mam jeszcze żadnych liczb" (
      "Nic się nie policzyło. Rozwiń szczegóły albo zajrzyj do dziennika nadzorcy.") ""
  }

  if (@($wywrotki).Count -gt 0) {
    $lista += Problem "uwaga" "Przy poprzednim przebiegu coś się nie udało" (
      "MegaRuchacz potknął się w tle. Pełna treść jest w szczegółach.") ((@($wywrotki)) -join " | ")
  }

  # Czerwone przed zoltymi: pierwsza rzecz na ekranie ma byc ta, ktora naprawde
  # czegos wymaga, a nie ta, ktorej akurat nie wiemy.
  $lista = @($lista | Sort-Object -Property @{ Expression = { if ($_.Waga -eq "pilne") { 0 } else { 1 } } })
  return ,$lista
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
  $l += "MegaRuchacz - nadzorca"
  $stempel = "przed chwilą"
  if ($czas) { $stempel = $czas.ToString('yyyy-MM-dd HH:mm:ss') }
  $l += "liczby sprawdzone: $stempel  (okno przelicza je samo przy każdym otwarciu i co $Minut min)"
  $l += ""

  if (@($problemy).Count -eq 0) {
    $l += "CO WYMAGA UWAGI"
    $l += "  nic - w oknie tej sekcji wtedy w ogóle nie ma i nie zajmuje miejsca"
  } else {
    $l += "CO WYMAGA UWAGI   (w oknie stoi jako PIERWSZE, na kolorowym tle)"
    foreach ($p in $problemy) {
      $znak = "[?]"
      if ($p.Waga -eq "pilne") { $znak = "[!]" }
      $l += "  $znak $($p.Tytul)"
      if ($p.Porada) { $l += "      $($p.Porada)" }
    }
  }
  $l += ""

  $l += "ILE TO KOSZTUJE"
  $r = $null; $c = $null
  if ($d) { $r = $d.Rachunek; $c = $d.Cykl }
  # Bez @() wokol wywolania - te funkcje koncza sie na "return ,$lista", wiec
  # owiniecie ich w @() daje tablice z jedna tablica w srodku (pulapka opisana
  # w naglowku stan-nadzorcy.ps1). Owijac wolno zmienne, nie wywolania.
  $trzy = @()
  try { $trzy = Trzy-Liczby $r $c }
  catch { Zanotuj-Wywrotke "trzy liczby do wydruku" $_; $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy" }
  foreach ($t in $trzy) {
    $l += "  $($t.Naglowek)"
    if ($null -ne $t.Liczba) {
      $ogon = ""
      if ($t.Ogon) { $ogon = "   ($($t.Ogon))" }
      $l += "      ~$(Liczba-Ludzka $t.Liczba) tokenów$ogon"
    } else {
      $l += "      nie wiem - $($t.Powod)"
    }
    $l += "      $($t.Opis)"
  }
  $l += ""

  $l += "STAN"
  if (@($problemy).Count -eq 0) { $l += "  Wszystko gra - nic nie wymaga Twojej uwagi." }
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
  $l += "  [Pokaż szczegóły - z czego to się składa i gdzie to leży]"
  $l += "      Rozwija sekcję niżej. Nic nie uruchamia i nic nie kosztuje."
  $l += "  [Zamknij okno]"
  $l += "      Okno znika, ikona w zasobniku zostaje i pilnuje dalej."
  return ,$l
}

# Szczegoly: wszystko to, co w starym oknie lezalo na wierzchu. Tu jest ich
# miejsce - pod przyciskiem, dla tego, kto ich szuka.
function Zbuduj-Szczegoly($d, $wywrotkiNadzorcy, $rozbicie) {
  $l = @()
  $l += "SZCZEGÓŁY   (w oknie schowane pod przyciskiem [Pokaż szczegóły])"
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

  $l += "== ALARMY, PELNA TRESC RAZEM Z KOMENDAMI =="
  $alarmy = @()
  if ($d) { $alarmy = @($d.Alarmy) }
  if ($alarmy.Count -eq 0) {
    if ($d -and $d.Cykl -and $d.Rachunek) { $l += "  nic nie wymaga uwagi" }
    else { $l += "  NIE WIADOMO - brakuje danych, wiec alarmow nie policzylem" }
  } else {
    foreach ($a in $alarmy) {
      $l += "  [$($a.Temat)] $($a.Tytul)"
      $l += "      $($a.Tresc)"
    }
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
$script:Okno          = $null
$script:Ikona         = $null
$script:Przewijak     = $null
$script:Root          = $null
$script:LPodtytul     = $null
$script:PanelProblemy = $null
$script:PanelLiczby   = $null
$script:PanelStan     = $null
$script:BSzczegoly    = $null
$script:PoleSzczegoly = $null
$script:Pasek         = $null
$script:BAktualizuj   = $null
$script:LAktualizuj   = $null
$script:BCykl         = $null
$script:LCykl         = $null
$script:ZegarOtwarcia = $null
$script:PanelZmian    = $null   # linie zmian w pamieci, schowane pod "pokaz zmiany"
$script:LinkZmian     = $null
# Rozwiniecie listy zmian przezywa przeliczenie okna - inaczej lista zwijalaby
# sie sama co kwadrans, w trakcie czytania.
$script:ZmianyRozwiniete = $false

# Bufor: ostatnio zebrane liczby i GODZINA, z ktorej pochodza. Ta godzina jest
# pokazywana zawsze - okno, ktore pokazuje stare liczby jako biezace, klamie.
$script:Dane      = $null
$script:DaneCzas  = $null
$script:DaneBlad  = $null
$script:Rozbicie  = $null   # rozbicie rachunku liczymy dopiero, gdy ktos rozwinie szczegoly
$script:Wywrotki  = @()
$script:Licze     = $false
$script:Problemy  = @()
# Gdy sekcja szczegolow pokazuje cudzy tekst (odpowiedz straznika po pobraniu
# nowszej wersji), przeliczenie danych NIE ma jej podmieniac - uzytkownik
# czytalby wtedy co innego, niz przed chwila kliknal.
$script:SzczegolyZajete = $false

# --- wyglad ------------------------------------------------------------------
# KOLOR TYLKO TAM, GDZIE NIESIE ZNACZENIE. Czerwony wylacznie przy sprawie,
# ktora wymaga dzialania, zolty przy "czegos nie wiem", zielony przy jednym
# zdaniu "wszystko gra". Cala reszta jest szara albo czarna. Tecza w oknie
# uczy ignorowania kolorow, a wtedy czerwony tez przestaje dzialac.
$script:KolTekst  = [System.Drawing.Color]::FromArgb(28, 28, 30)
$script:KolSzary  = [System.Drawing.Color]::FromArgb(106, 108, 112)
$script:KolPilne  = [System.Drawing.Color]::FromArgb(176, 32, 32)
$script:KolUwaga  = [System.Drawing.Color]::FromArgb(146, 98, 0)
$script:KolDobrze = [System.Drawing.Color]::FromArgb(24, 104, 56)
$script:TloPilne  = [System.Drawing.Color]::FromArgb(253, 236, 236)
$script:TloUwaga  = [System.Drawing.Color]::FromArgb(255, 248, 227)
$script:TloPaska  = [System.Drawing.Color]::FromArgb(246, 246, 248)

# Hierarchia robi sie krojem i wielkoscia, nie kolorem: liczba 22 pt, naglowek
# nad nia 8,75 pt, zdanie pod nia 8,75 pt. Czcionki sa WSPOLNE dla wszystkich
# etykiet - tworzone przy kazdym odmalowaniu wyciekalyby uchwytami GDI.
$script:CzDuza   = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
$script:CzTytul  = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
$script:CzGruba  = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
$script:CzZwykla = New-Object System.Drawing.Font("Segoe UI", 9.75)
$script:CzMala   = New-Object System.Drawing.Font("Segoe UI", 8.75)
$script:CzStala  = New-Object System.Drawing.Font("Consolas", 9.5)

# Szerokosci. Okno ma 780 px; po odjeciu ramki, marginesow i MIEJSCA NA PIONOWY
# SUWAK zostaje 700 px na tresc. Trzy kafelki po 228 z marginesami daja 696,
# wiec suwak poziomy nie pojawia sie nawet wtedy, gdy tresc jest dluga -
# a tekst wyjezdzajacy poza krawedz bylby ucieciem po cichu.
$script:SzerTresc   = 700
$script:SzerKafelka = 228
$script:SzerKarty   = 696

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
  $script:LPodtytul.Text = "Sprawdzone $kiedy. Okno liczy to samo za każdym razem, gdy je otwierasz, i co $Minut min w tle."
}

function Karta-Problemu($p) {
  $k = Pionowy $script:SzerKarty
  $k.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 10)
  $k.Margin  = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
  $kolor = $script:KolUwaga
  $k.BackColor = $script:TloUwaga
  if ($p.Waga -eq "pilne") { $kolor = $script:KolPilne; $k.BackColor = $script:TloPilne }
  $k.Controls.Add((Etykieta-Zawijana $p.Tytul $script:CzGruba $kolor ($script:SzerKarty - 30)))
  if ($p.Porada) {
    $k.Controls.Add((Etykieta-Zawijana $p.Porada $script:CzZwykla $script:KolTekst ($script:SzerKarty - 30)))
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
  $k = Pionowy $script:SzerKafelka
  $k.Margin = New-Object System.Windows.Forms.Padding(0, 0, 4, 0)
  $szer = $script:SzerKafelka - 12
  $k.Controls.Add((Etykieta-Zawijana $t.Naglowek $script:CzMala $script:KolSzary $szer))
  if ($null -ne $t.Liczba) {
    $w = Poziomy
    $duza = Etykieta ("~" + (Liczba-Ludzka $t.Liczba)) $script:CzDuza $script:KolTekst
    $duza.Margin = New-Object System.Windows.Forms.Padding(0, 0, 5, 0)
    $w.Controls.Add($duza)
    $jed = Etykieta "tokenów" $script:CzZwykla $script:KolSzary
    $jed.Margin = New-Object System.Windows.Forms.Padding(0, 19, 0, 0)
    $w.Controls.Add($jed)
    $k.Controls.Add($w)
    if ($t.Ogon) { $k.Controls.Add((Etykieta-Zawijana $t.Ogon $script:CzMala $script:KolSzary $szer)) }
  } else {
    # Zero znaczyloby "nic nie kosztuje" - a my po prostu nie wiemy. Mowimy to
    # wprost i podajemy powod, zamiast pokazac liczbe, ktorej nie mamy.
    $k.Controls.Add((Etykieta "nie wiem" $script:CzDuza $script:KolUwaga))
    $k.Controls.Add((Etykieta-Zawijana $t.Powod $script:CzMala $script:KolUwaga $szer))
  }
  $k.Controls.Add((Etykieta-Zawijana $t.Opis $script:CzMala $script:KolSzary $szer))
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
      "Liczb jeszcze nie ma - nie udało się ich złożyć. Powód jest w szczegółach.") $script:CzZwykla $script:KolUwaga $script:SzerTresc))
    return
  }
  foreach ($t in $trzy) { $script:PanelLiczby.Controls.Add((Kafelek-Liczby $t)) }
}

function Odmaluj-Stan {
  if (-not $script:PanelStan -or $script:PanelStan.IsDisposed) { return }
  Wyczysc-Panel $script:PanelStan
  if (@($script:Problemy).Count -eq 0) {
    $script:PanelStan.Controls.Add((Etykieta "Wszystko gra - nic nie wymaga Twojej uwagi." $script:CzGruba $script:KolDobrze))
  }
  $linie = @()
  if ($script:Dane) {
    try { $linie = Linie-Stanu $script:Dane.Wersja $script:Dane.Cykl $script:Dane.Przeliczanie }
    catch { Zanotuj-Wywrotke "zlozenie linii stanu" $_ }
  }
  foreach ($l in $linie) {
    $script:PanelStan.Controls.Add((Etykieta-Zawijana $l $script:CzZwykla $script:KolSzary $script:SzerTresc))
  }
  Dodaj-Zmiany-Pamieci
}

# "Pamiec dzis: 2 zmiany" jedna linia, a obok odnosnik [pokaz zmiany], ktory
# rozwija linie z identyfikatorami i zdanie, jak cofnac. Rozwijanie tylko
# przelacza widocznosc - nie przebudowuje panelu, bo kontrolka zwalniana we
# wlasnej procedurze klikniecia potrafi wywrocic WinForms.
function Dodaj-Zmiany-Pamieci {
  $script:PanelZmian = $null
  $script:LinkZmian = $null
  $pz = $null
  if ($script:Dane) { $pz = $script:Dane.Pamiec }
  $o = $null
  try { $o = Opis-Zmian-Pamieci $pz }
  catch { Zanotuj-Wywrotke "zlozenie zmian w pamieci" $_ }
  if (-not $o) {
    $script:PanelStan.Controls.Add((Etykieta-Zawijana "Pamięć: nie udało się złożyć listy zmian - powód jest w dzienniku nadzorcy." $script:CzZwykla $script:KolUwaga $script:SzerTresc))
    return
  }
  $kolor = $script:KolSzary
  if ($o.Uwaga) { $kolor = $script:KolUwaga }
  if (@($o.Zmiany).Count -eq 0) {
    $script:PanelStan.Controls.Add((Etykieta-Zawijana $o.Linia $script:CzZwykla $kolor $script:SzerTresc))
    return
  }

  $wiersz = Poziomy
  $wiersz.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
  $lin = Etykieta $o.Linia $script:CzZwykla $kolor
  $lin.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
  $wiersz.Controls.Add($lin)
  $script:LinkZmian = New-Object System.Windows.Forms.LinkLabel
  $script:LinkZmian.AutoSize = $true
  $script:LinkZmian.Font = $script:CzZwykla
  $script:LinkZmian.Margin = New-Object System.Windows.Forms.Padding(0)
  $wiersz.Controls.Add($script:LinkZmian)
  $script:PanelStan.Controls.Add($wiersz)

  $script:PanelZmian = Pionowy ($script:SzerTresc - 16)
  $script:PanelZmian.Margin = New-Object System.Windows.Forms.Padding(16, 2, 0, 4)
  foreach ($z in $o.Zmiany) {
    $script:PanelZmian.Controls.Add((Etykieta-Zawijana $z $script:CzMala $script:KolTekst ($script:SzerTresc - 16)))
  }
  if ($o.Porada) {
    $p = Etykieta-Zawijana $o.Porada $script:CzZwykla $script:KolTekst ($script:SzerTresc - 16)
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

# Wysokosc dobierana pod tresc, a nie na sztywno: w stanie normalnym okno ma sie
# miescic na ekranie BEZ PRZEWIJANIA, a po rozwinieciu szczegolow urosnac tylko
# do wysokosci pulpitu. Gdy tresc i tak nie mieszcza sie w ekranie, zostaje
# przewijanie panelu - nic nie znika.
function Dopasuj-Wysokosc {
  if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
  try {
    $script:Root.PerformLayout()
    $ramka = $script:Okno.Height - $script:Okno.ClientSize.Height
    $trzeba = $script:Root.PreferredSize.Height + $script:Przewijak.Padding.Vertical + $script:Pasek.Height + $ramka + 10
    $pulpit = [System.Windows.Forms.Screen]::FromControl($script:Okno).WorkingArea.Height
    $script:Okno.Height = [math]::Max(360, [math]::Min($trzeba, $pulpit - 60))
  } catch { Zanotuj-Wywrotke "dobranie wysokosci okna" $_ }
}

function Odmaluj-Okno {
  if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
  $script:Okno.SuspendLayout()
  try {
    Odmaluj-Podtytul
    Odmaluj-Problemy
    Odmaluj-Liczby
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
    $script:PoleSzczegoly.Text = "Licze rozbicie rachunku..."
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
    if ($script:PoleSzczegoly -and $script:PoleSzczegoly.Visible -and (-not $script:SzczegolyZajete)) {
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
  $f.Size = New-Object System.Drawing.Size(780, 600)
  $f.MinimumSize = New-Object System.Drawing.Size(760, 360)
  $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
  $f.BackColor = [System.Drawing.Color]::White
  try { $f.Icon = Ikona-Nadzorcy } catch { Zanotuj-Wywrotke "ikona okna" $_ }

  # Pasek przyciskow siedzi na formularzu, a nie w przewijanej tresci - ma byc
  # pod reka zawsze, takze po rozwinieciu szczegolow.
  $script:Pasek = New-Object System.Windows.Forms.TableLayoutPanel
  $script:Pasek.Dock = [System.Windows.Forms.DockStyle]::Bottom
  $script:Pasek.AutoSize = $true
  $script:Pasek.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
  $script:Pasek.ColumnCount = 3
  $script:Pasek.RowCount = 2
  $script:Pasek.Padding = New-Object System.Windows.Forms.Padding(16, 10, 16, 10)
  $script:Pasek.BackColor = $script:TloPaska
  $script:Pasek.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 39))) | Out-Null
  $script:Pasek.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 39))) | Out-Null
  $script:Pasek.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 22))) | Out-Null
  $script:Pasek.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38))) | Out-Null
  $script:Pasek.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null

  $script:BAktualizuj = Nowy-Przycisk "Sprawdź i pobierz nowszą wersję MegaRuchacza"
  $script:BCykl       = Nowy-Przycisk "Przeczytaj zaległe rozmowy"
  $bZamknij           = Nowy-Przycisk "Zamknij okno"
  $script:LAktualizuj = Etykieta-Zawijana "" $script:CzMala $script:KolSzary 270
  $script:LCykl       = Etykieta-Zawijana "" $script:CzMala $script:KolSzary 270
  $lZamknij           = Etykieta-Zawijana "Ikona w zasobniku zostaje i pilnuje dalej." $script:CzMala $script:KolSzary 150

  $script:Pasek.Controls.Add($script:BAktualizuj, 0, 0)
  $script:Pasek.Controls.Add($script:BCykl, 1, 0)
  $script:Pasek.Controls.Add($bZamknij, 2, 0)
  $script:Pasek.Controls.Add($script:LAktualizuj, 0, 1)
  $script:Pasek.Controls.Add($script:LCykl, 1, 1)
  $script:Pasek.Controls.Add($lZamknij, 2, 1)

  # Przewijak istnieje po to, zeby przy malym ekranie albo po rozwinieciu
  # szczegolow tresc dalo sie przesunac, a nie zeby zniknela pod krawedzia.
  $script:Przewijak = New-Object System.Windows.Forms.Panel
  $script:Przewijak.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:Przewijak.AutoScroll = $true
  $script:Przewijak.BackColor = [System.Drawing.Color]::White
  $script:Przewijak.Padding = New-Object System.Windows.Forms.Padding(20, 16, 20, 16)

  $script:Root = Pionowy $script:SzerTresc
  $script:Root.Dock = [System.Windows.Forms.DockStyle]::Top

  $lTytul = Etykieta "MegaRuchacz" $script:CzTytul $script:KolTekst
  $lTytul.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 1)
  $script:LPodtytul = Etykieta-Zawijana "Przeliczam, to potrwa kilka sekund..." $script:CzMala $script:KolSzary $script:SzerTresc
  $script:LPodtytul.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)

  $script:PanelProblemy = Pionowy $script:SzerTresc
  $script:PanelProblemy.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
  $script:PanelProblemy.Visible = $false

  $script:PanelLiczby = Poziomy
  $script:PanelLiczby.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 16)

  $script:PanelStan = Pionowy $script:SzerTresc
  $script:PanelStan.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)

  $script:BSzczegoly = New-Object System.Windows.Forms.Button
  $script:BSzczegoly.Text = "Pokaż szczegóły - z czego to się składa i gdzie to leży"
  $script:BSzczegoly.Font = $script:CzZwykla
  $script:BSzczegoly.FlatStyle = [System.Windows.Forms.FlatStyle]::System
  $script:BSzczegoly.AutoSize = $true
  $script:BSzczegoly.Height = 30
  $script:BSzczegoly.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)

  $script:PoleSzczegoly = New-Object System.Windows.Forms.TextBox
  $script:PoleSzczegoly.Multiline = $true
  $script:PoleSzczegoly.ReadOnly = $true
  $script:PoleSzczegoly.WordWrap = $false
  $script:PoleSzczegoly.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
  $script:PoleSzczegoly.Font = $script:CzStala
  $script:PoleSzczegoly.BackColor = [System.Drawing.Color]::White
  $script:PoleSzczegoly.Size = New-Object System.Drawing.Size($script:SzerTresc, 300)
  $script:PoleSzczegoly.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
  $script:PoleSzczegoly.Visible = $false

  $script:Root.Controls.Add($lTytul)
  $script:Root.Controls.Add($script:LPodtytul)
  $script:Root.Controls.Add($script:PanelProblemy)
  $script:Root.Controls.Add($script:PanelLiczby)
  $script:Root.Controls.Add($script:PanelStan)
  $script:Root.Controls.Add($script:BSzczegoly)
  $script:Root.Controls.Add($script:PoleSzczegoly)
  $script:Przewijak.Controls.Add($script:Root)

  $f.Controls.Add($script:Przewijak)
  $f.Controls.Add($script:Pasek)
  $f.Add_FormClosed({
    $script:Okno = $null; $script:Root = $null; $script:Przewijak = $null
    $script:LPodtytul = $null; $script:PanelProblemy = $null; $script:PanelLiczby = $null
    $script:PanelStan = $null; $script:BSzczegoly = $null; $script:PoleSzczegoly = $null
    $script:Pasek = $null; $script:BAktualizuj = $null; $script:LAktualizuj = $null
    $script:BCykl = $null; $script:LCykl = $null
    $script:PanelZmian = $null; $script:LinkZmian = $null
  })

  # --- co robia przyciski ---

  $script:BSzczegoly.Add_Click({
    $script:SzczegolyZajete = $false
    if ($script:PoleSzczegoly.Visible) {
      $script:PoleSzczegoly.Visible = $false
      $script:BSzczegoly.Text = "Pokaż szczegóły - z czego to się składa i gdzie to leży"
    } else {
      Napelnij-Szczegoly
      $script:PoleSzczegoly.Visible = $true
      $script:BSzczegoly.Text = "Ukryj szczegóły"
    }
    Dopasuj-Wysokosc
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
    # przelaczy szczegoly - dlatego znacznik "zajete".
    $script:SzczegolyZajete = $true
    if (-not $script:PoleSzczegoly.Visible) {
      $script:PoleSzczegoly.Visible = $true
      $script:BSzczegoly.Text = "Ukryj szczegóły"
      Dopasuj-Wysokosc
    }
    $script:PoleSzczegoly.Text = "Pobieram nowszą wersję - strażnik sprawdza serwer i nanosi poprawki..."
    $script:Okno.Refresh()
    $wynik = @()
    try { $wynik = Aktualizuj }
    catch { Zanotuj-Wywrotke "aktualizacja" $_; $wynik = @("NIE UDALO SIE: $($_.Exception.Message)") }
    $script:PoleSzczegoly.Lines = [string[]](
      @("CO POWIEDZIAŁ STRAŻNIK", "") + $wynik +
      @("", "To jest odpowiedź na kliknięcie, nie zwykła zawartość szczegółów.",
            "Kliknij [Ukryj szczegóły], żeby wrócić do normalnego widoku."))
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
