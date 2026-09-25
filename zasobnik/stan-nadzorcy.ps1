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

function Ustaw-Nadzorce([string]$zrodlo, [string]$dom, [bool]$proba) {
  $script:NadzZrodlo        = $zrodlo.TrimEnd('\')
  $script:NadzDom           = $dom.TrimEnd('\')
  $script:NadzProba         = $proba
  $script:NadzWiedza        = Join-Path $script:NadzDom ".claude\wiedza"
  $script:NadzPlikStanu     = Join-Path $script:NadzDom ".claude\.megaruchacz-zasobnik.txt"
  $script:NadzPlikDziennika = Join-Path $script:NadzDom ".claude\.megaruchacz-zasobnik.log"
  $script:NadzWywrotki      = @()
}

# ------------------------------------------------------- pliki "klucz: wartosc"
# Ten sam format i ten sam odczyt, co w narzedzia\straznik-zasad.ps1 - pliki stanu
# pisza tamte skrypty, wiec czytanie ich inaczej skonczyloby sie rozjazdem.

function Bez-Bom { return (New-Object System.Text.UTF8Encoding($false)) }

function Zapisz-Tekst($sciezka, $tekst) {
  $katalog = Split-Path -Parent $sciezka
  if ($katalog -and -not (Test-Path $katalog)) { New-Item -ItemType Directory -Force -Path $katalog | Out-Null }
  [System.IO.File]::WriteAllText($sciezka, $tekst, (Bez-Bom))
}

function Czytaj-Tekst($sciezka) {
  if (-not $sciezka -or -not (Test-Path $sciezka)) { return $null }
  try { return [System.IO.File]::ReadAllText($sciezka) }
  catch { Zanotuj-Wywrotke "odczyt pliku $sciezka" $_; return $null }
}

function Klucze-Z-Tekstu($raw) {
  $stan = [ordered]@{}
  if (-not $raw) { return $stan }
  foreach ($l in ($raw -split '\r?\n')) {
    $m = [regex]::Match($l, '^\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*:\s*(.*?)\s*$')
    if ($m.Success) { $stan[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $stan
}

function Czytaj-Klucze($sciezka) { return (Klucze-Z-Tekstu (Czytaj-Tekst $sciezka)) }

function Zapisz-Klucze($sciezka, $stan) {
  $linie = @()
  foreach ($k in $stan.Keys) { $linie += ("{0}: {1}" -f $k, $stan[$k]) }
  Zapisz-Tekst $sciezka (($linie -join "`r`n") + "`r`n")
}

# Plik stanu nadzorcy trzyma rzeczy roznego rodzaju (slad obecnosci, wywrotki,
# znaczniki alarmow), wiec pisze sie do niego WYLACZNIE przez scalenie.
function Dopisz-Klucze($sciezka, $nowe) {
  $stan = Czytaj-Klucze $sciezka
  foreach ($k in $nowe.Keys) { $stan[$k] = $nowe[$k] }
  Zapisz-Klucze $sciezka $stan
}

# --------------------------------------------------------- dziennik i wywrotki

function Notuj([string]$tekst) {
  if (-not $tekst) { return }
  if ($script:NadzProba) { Write-Host "[dziennik] $tekst"; return }
  try {
    $stempel = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $stare = @()
    $raw = $null
    if (Test-Path $script:NadzPlikDziennika) { $raw = [System.IO.File]::ReadAllText($script:NadzPlikDziennika) }
    if ($raw) { $stare = @(($raw -split '\r?\n') | Where-Object { $_.Trim() }) }
    $wszystkie = @($stare + @("$stempel | $tekst"))
    if ($wszystkie.Count -gt $LINII_DZIENNIKA) { $wszystkie = @($wszystkie | Select-Object -Last $LINII_DZIENNIKA) }
    Zapisz-Tekst $script:NadzPlikDziennika (($wszystkie -join "`r`n") + "`r`n")
  } catch {
    # Ostatnie ogniwo lancucha. Dziennika nie da sie zapisac - zostaje strumien
    # bledow, ktory przy uruchomieniu z Harmonogramu i tak nikogo nie obudzi,
    # ale nie jest cisza: nastepny start zobaczy stary plik i powie, ze stoi.
    Write-Error "nadzorca: nie moge pisac do dziennika $($script:NadzPlikDziennika) - $($_.Exception.Message)"
  }
}

# Wywrotka NIE przerywa przebiegu (ikona ma zostac w zasobniku), ale zostawia
# slad w dwoch miejscach: w dzienniku od razu i w pliku stanu do zameldowania
# czlowiekowi przy najblizszym otwarciu okna albo przy nastepnym starcie.
function Zanotuj-Wywrotke([string]$zadanie, $blad) {
  $tresc = "$blad"
  if ($blad -and $blad.Exception) { $tresc = $blad.Exception.Message }
  $tresc = ($tresc -replace '[\r\n\t]+', ' ').Trim()
  if (-not $tresc) { $tresc = "wyjatek bez tresci" }
  if ($tresc.Length -gt 300) { $tresc = $tresc.Substring(0, 300) }
  $script:NadzWywrotki += ("{0} | {1}" -f $zadanie, $tresc)
  Notuj "wywrocilo sie: ${zadanie} - ${tresc}"
}

# Jeden zapis na koniec przebiegu: "bylem tu" plus wywrotki, ktore sie zebraly.
# Bez tego sladu nie da sie odroznic nadzorcy sprawnego od nadzorcy, ktorego
# Windows nie uruchomil - a to jest caly powod, dla ktorego on powstal.
function Zapisz-Obecnosc([string]$tryb) {
  if ($script:NadzProba) { return }
  try {
    $stan = Czytaj-Klucze $script:NadzPlikStanu
    $stan["byl"] = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    $stan["byl.tryb"] = $tryb
    $naj = 0
    foreach ($k in @($stan.Keys)) {
      $m = [regex]::Match($k, '^wywrotka\.(\d+)$')
      if ($m.Success -and ([int]$m.Groups[1].Value) -gt $naj) { $naj = [int]$m.Groups[1].Value }
    }
    foreach ($w in $script:NadzWywrotki) {
      if ($naj -ge $WYWROTEK_NAJWYZEJ) { break }   # piata niczego juz nie tlumaczy
      $naj++
      $stan["wywrotka.$naj"] = ("{0} | {1} | {2}" -f $tryb, (Get-Date -Format 'yyyy-MM-dd HH:mm'), $w)
    }
    Zapisz-Klucze $script:NadzPlikStanu $stan
    $script:NadzWywrotki = @()
  } catch {
    Write-Error "nadzorca: nie moge zapisac znacznika obecnosci - $($_.Exception.Message)"
  }
}

# Wywrotki z poprzednich przebiegow - zwraca gotowe linie i CZYSCI je z pliku
# stanu, bo raz zameldowany blad ma nie wracac do konca swiata.
function Odbierz-Wywrotki {
  $stan = Czytaj-Klucze $script:NadzPlikStanu
  $klucze = @($stan.Keys | Where-Object { $_ -match '^wywrotka\.\d+$' })
  if ($klucze.Count -eq 0) { return ,@() }
  $linie = @()
  foreach ($k in $klucze) {
    $cz = "$($stan[$k])" -split '\s*\|\s*', 4
    if ($cz.Count -eq 4) { $linie += "$($cz[2]) - $($cz[3]) (tryb $($cz[0]), $($cz[1]))" }
    else { $linie += "$($stan[$k])" }
    $stan.Remove($k)
  }
  if (-not $script:NadzProba) {
    try { Zapisz-Klucze $script:NadzPlikStanu $stan }
    catch { Notuj "nie udalo sie wyczyscic wywrotek z pliku stanu - wroca raz jeszcze" }
  }
  return ,$linie
}

# ------------------------------------------------------------------- pomocnicze

function Liczba-Ludzka($n) {
  try { return ([long]$n).ToString("N0", [Globalization.CultureInfo]::InvariantCulture).Replace(",", " ") }
  catch { return "$n" }
}

function Data-Lub-Nic($tekst) {
  $d = [datetime]::MinValue
  if ($tekst -and [datetime]::TryParse($tekst, [ref]$d)) { return $d }
  return $null
}

# Wywolanie gita z limitem czasu. Skopiowane z narzedzia\straznik-zasad.ps1 razem
# z dotknieciem uchwytu procesu - bez tej jednej linii Start-Process -PassThru
# oddaje obiekt, w ktorym ExitCode zostaje $null nawet po zakonczeniu procesu,
# wiec KAZDE wolanie wygladaloby na nieudane (sprawdzone 2026-09-16).
function Wolaj-Gita([string]$argumenty, [int]$sekundy) {
  $wynik = [pscustomobject]@{ ok = $false; tekst = ""; powod = "" }
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    $wynik.powod = "nie ma gita na tej maszynie"
    return $wynik
  }
  $wy = [System.IO.Path]::GetTempFileName()
  $bl = [System.IO.Path]::GetTempFileName()
  try {
    $p = Start-Process -FilePath "git" -ArgumentList $argumenty -NoNewWindow -PassThru `
           -RedirectStandardOutput $wy -RedirectStandardError $bl
    $null = $p.Handle
    if (-not $p.WaitForExit($sekundy * 1000)) {
      try { $p.Kill() } catch { Notuj "git nie dal sie ubic po przekroczeniu czasu: $argumenty" }
      $wynik.powod = "git nie odpowiedzial w ${sekundy} s"
      return $wynik
    }
    $p.WaitForExit()
    if ($p.ExitCode -eq 0) {
      $wynik.ok = $true
      $t = [System.IO.File]::ReadAllText($wy)
      if ($t) { $wynik.tekst = $t.Trim() }
    } else {
      $b = [System.IO.File]::ReadAllText($bl)
      $wynik.powod = (("$b" -replace '[\r\n]+', ' ').Trim())
      if (-not $wynik.powod) { $wynik.powod = "git zwrocil kod $($p.ExitCode)" }
    }
  } catch {
    $wynik.powod = $_.Exception.Message
  } finally {
    Remove-Item $wy, $bl -Force -ErrorAction SilentlyContinue
  }
  return $wynik
}

# Uruchomienie skryptu PowerShella osobnym procesem, z odczytem wyjscia i kodu.
# Osobny proces, a nie "&", bo wolane skrypty koncza sie przez "exit" - w tym
# samym procesie zamknelyby cale okno nadzorcy.
function Wolaj-Skrypt([string]$skrypt, [string[]]$argumenty, [int]$sekundy) {
  $wynik = [pscustomobject]@{ ok = $false; kod = $null; tekst = ""; powod = "" }
  if (-not (Test-Path $skrypt)) {
    $wynik.powod = "nie ma pliku ${skrypt}"
    return $wynik
  }
  $wy = [System.IO.Path]::GetTempFileName()
  $bl = [System.IO.Path]::GetTempFileName()
  try {
    $lista = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ('"' + $skrypt + '"')) + $argumenty
    $p = Start-Process -FilePath "powershell.exe" -ArgumentList $lista -NoNewWindow -PassThru `
           -RedirectStandardOutput $wy -RedirectStandardError $bl
    $null = $p.Handle
    if (-not $p.WaitForExit($sekundy * 1000)) {
      try { $p.Kill() } catch { Notuj "nie dalo sie ubic ${skrypt} po przekroczeniu czasu" }
      $wynik.powod = "$(Split-Path -Leaf $skrypt) nie skonczyl w ${sekundy} s"
      return $wynik
    }
    $p.WaitForExit()
    $wynik.kod = $p.ExitCode
    $wynik.ok = $true
    try { $wynik.tekst = [System.IO.File]::ReadAllText($wy) } catch { $wynik.tekst = "" }
    $b = ""
    try { $b = [System.IO.File]::ReadAllText($bl) } catch { $b = "" }
    if ($b -and $b.Trim()) { $wynik.powod = (($b -replace '[\r\n]+', ' ').Trim()) }
  } catch {
    $wynik.powod = $_.Exception.Message
  } finally {
    Remove-Item $wy, $bl -Force -ErrorAction SilentlyContinue
  }
  return $wynik
}

# Start procesu w tle bez mrugajacej konsoli - conhost --headless, a gdyby go
# nie bylo, zwykly powershell w ukrytym oknie. Ta sama para, co w straznik-zasad.ps1.
function Odpal-W-Tle([string]$skrypt, [string]$argumenty) {
  $ogon = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $skrypt + '" ' + $argumenty
  try {
    Start-Process -FilePath "conhost.exe" -ArgumentList ("--headless powershell.exe " + $ogon) `
      -WindowStyle Hidden -ErrorAction Stop | Out-Null
    return $true
  } catch { Notuj "conhost --headless nie wystartowal, probuje zwyklym powershellem" }
  try {
    Start-Process -FilePath "powershell.exe" -ArgumentList $ogon -WindowStyle Hidden -ErrorAction Stop | Out-Null
    return $true
  } catch { Zanotuj-Wywrotke "start procesu w tle ($skrypt)" $_; return $false }
}

# ----------------------------------------------------------------- numer wersji

# TA SAMA logika, co Wersja-Narzedzia w wdroz.ps1 (najwyzszy naglowek "## X.Y.Z"
# w ZMIANY.md). Przepisana, a nie dot-sourcowana, bo wdroz.ps1 to skrypt, ktory
# przy wczytaniu wykonalby sie w calosci. Gdy tamta funkcja sie zmieni, ta ma
# pojsc za nia - stad ten komentarz.
function Wersja-Narzedzia($plikZmian) {
  if (-not (Test-Path $plikZmian)) { return $null }
  $naj = $null
  $raw = Czytaj-Tekst $plikZmian
  if (-not $raw) { return $null }
  foreach ($m in [regex]::Matches($raw, '(?m)^##\s+(\d+)\.(\d+)\.(\d+)')) {
    $w = [version]("{0}.{1}.{2}" -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value)
    if ($null -eq $naj -or $w -gt $naj) { $naj = $w }
  }
  if ($null -eq $naj) { return $null }
  return $naj.ToString()
}

# Numer wersji plus odpowiedz na pytanie, czy na gicie lezy cos nowszego.
# $zSieci = $false znaczy "nie ruszaj sieci, powiedz co wiesz z ostatniego pobrania" -
# tak liczymy przy kazdym otwarciu okna, zeby nie czekalo na fetch.
# Zwraca zawsze komplet pol; gdy czegos nie da sie ustalic, w Powod stoi DLACZEGO.
function Stan-Wersji([bool]$zSieci) {
  $w = [pscustomobject]@{
    Lokalna   = $null
    Nowsza    = $null      # ile commitow zdalna ma ponad nami ($null = nie wiadomo)
    Nasze     = $null      # ile mamy lokalnych, ktorych nie ma na zdalnej
    Pobrano   = $null      # kiedy ostatnio zagladalismy do sieci
    Powod     = ""         # dlaczego nie wiadomo
  }
  $plikZmian = Join-Path $script:NadzZrodlo "ZMIANY.md"
  $w.Lokalna = Wersja-Narzedzia $plikZmian
  if (-not $w.Lokalna) { $w.Powod = "nie umiem odczytac numeru wersji z ${plikZmian}" }

  $cyt = '"' + $script:NadzZrodlo + '"'
  $repo = Wolaj-Gita "-C $cyt rev-parse --is-inside-work-tree" $CZAS_GIT
  if (-not $repo.ok -or $repo.tekst -ne "true") {
    $w.Powod = "$($script:NadzZrodlo) to nie repozytorium git - nie ma z czym porownywac"
    return $w
  }

  $stan = Czytaj-Klucze $script:NadzPlikStanu
  $w.Pobrano = Data-Lub-Nic $stan["pobranie"]
  if ($zSieci) {
    $swieze = $false
    if ($w.Pobrano -and (([datetime]::Now - $w.Pobrano).TotalMinutes -lt $MINUT_MIEDZY_POBRANIAMI)) { $swieze = $true }
    if (-not $swieze) {
      $env:GIT_TERMINAL_PROMPT = "0"
      $pobrane = Wolaj-Gita "-C $cyt -c credential.interactive=never fetch --quiet" $CZAS_GIT_FETCH
      if ($pobrane.ok) {
        $w.Pobrano = [datetime]::Now
        if (-not $script:NadzProba) {
          try { Dopisz-Klucze $script:NadzPlikStanu @{ pobranie = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') } }
          catch { Notuj "nie udalo sie zapisac znacznika pobrania" }
        }
      } else {
        $w.Powod = "nie udalo sie zajrzec do sieci ($($pobrane.powod)) - porownuje z tym, co bylo pobrane wczesniej"
      }
    }
  }

  $licznik = Wolaj-Gita "-C $cyt rev-list --left-right --count HEAD...@{u}" $CZAS_GIT
  if (-not $licznik.ok) {
    if (-not $w.Powod) { $w.Powod = "git nie policzyl roznicy wobec zdalnej ($($licznik.powod))" }
    return $w
  }
  $czesci = $licznik.tekst -split '\s+'
  if ($czesci.Count -lt 2) {
    if (-not $w.Powod) { $w.Powod = "git oddal nieczytelna odpowiedz o roznicy: $($licznik.tekst)" }
    return $w
  }
  $w.Nasze  = [int]$czesci[0]
  $w.Nowsza = [int]$czesci[1]
  return $w
}

function Opis-Wersji($w) {
  $lok = $w.Lokalna
  if (-not $lok) { $lok = "NIE WIADOMO" }
  $linie = @("  wersja na dysku : $lok")
  if ($null -eq $w.Nowsza) {
    $powod = $w.Powod
    if (-not $powod) { $powod = "nie ustalilem powodu - to samo w sobie jest usterka" }
    $linie += "  na gicie        : NIE WIADOMO - $powod"
  } elseif ($w.Nowsza -le 0) {
    $linie += "  na gicie        : nic nowszego"
  } else {
    $slowo = if ($w.Nowsza -eq 1) { "zmiana czeka" } else { "zmian czeka" }
    $linie += "  na gicie        : $($w.Nowsza) $slowo - przycisk [Aktualizuj] je pobierze"
  }
  if ($w.Nasze -gt 0) {
    $linie += "  uwaga           : masz $($w.Nasze) wlasnych commitow ponad zdalna - aktualizacja odmowi scalenia"
  }
  if ($w.Pobrano) {
    $linie += "  sprawdzone      : $($w.Pobrano.ToString('yyyy-MM-dd HH:mm'))"
  } else {
    $linie += "  sprawdzone      : jeszcze ani razu w tej instalacji"
  }
  return ,$linie
}

# ------------------------------------------------------------------ cykl wiedzy

# Wszystko, co wiadomo o cyklu: kiedy chodzil, ile czeka w kolejce, ile kosztowal.
# $zKolejka = $true doklada przebieg probny wylawiania (nie wola modelu, ~0,4 s) -
# w oknie tak, w dozorze tylko wtedy, gdy i tak zaraz startujemy cykl.
function Stan-Cyklu([bool]$zKolejka) {
  $c = [pscustomobject]@{
    Data       = $null     # kiedy ostatnio sie skonczyl (z cykl-ostatni.txt)
    Status     = $null
    Opis       = $null
    Zaleglosc  = $null     # ile przebiegow zostalo wg ostatniego podsumowania
    Kawalki    = $null     # ile kawalkow rozmow czeka NA ZYWO
    Przebiegi  = $null
    Pracuje    = $false
    Koszt      = $null     # tokeny ostatniego przebiegu
    KosztData  = $null
    KosztOpis  = $null
    KosztWywolan = $null   # ile wywolan modelu zlozylo sie na ten koszt - z tego
                           # i tylko z tego liczy sie szacunek przed przyciskiem
    Powody     = @()       # czego nie dalo sie odczytac i dlaczego
  }

  $plikOstatni = Join-Path $script:NadzWiedza "cykl-ostatni.txt"
  if (Test-Path $plikOstatni) {
    $k = Czytaj-Klucze $plikOstatni
    $c.Data      = Data-Lub-Nic $k["data"]
    $c.Status    = $k["status"]
    $c.Opis      = $k["opis"]
    if ($k["zaleglosc"] -match '^\d+$') { $c.Zaleglosc = [int]$k["zaleglosc"] }
    if (-not $c.Data) { $c.Powody += "w ${plikOstatni} nie ma czytelnej daty (klucz 'data')" }
  } else {
    $c.Powody += "nie ma ${plikOstatni} - cykl nie zakonczyl na tej maszynie ani jednego przebiegu"
  }

  $postep = Czytaj-Klucze (Join-Path $script:NadzWiedza ".cykl-postep")
  if ($postep["stan"] -eq "pracuje") {
    $kiedy = Data-Lub-Nic $postep["czas"]
    # Znacznik starszy niz trzy godziny to nie praca, tylko przebieg, ktory padl
    # w polowie - tak samo liczy to straznik przed startem cyklu.
    if ($kiedy -and (([datetime]::Now - $kiedy).TotalHours -lt 3)) { $c.Pracuje = $true }
  }

  $plikKosztu = Join-Path $script:NadzWiedza ".koszt-cyklu.txt"
  if (Test-Path $plikKosztu) {
    $k = Czytaj-Klucze $plikKosztu
    $c.KosztData = Data-Lub-Nic $k["data"]
    if ($k["tokeny"] -match '^\d+$') { $c.Koszt = [long]$k["tokeny"] }
    if ($k["wywolania"] -match '^\d+$') { $c.KosztWywolan = [int]$k["wywolania"] }
    $czesci = @()
    if ($k["wywolania"] -match '^\d+$') { $czesci += "$($k['wywolania']) wywolan $($k['narzedzie'])" }
    if ($k["fakty"] -match '^\d+$')     { $czesci += "$($k['fakty']) faktow" }
    if ($czesci.Count -gt 0) { $c.KosztOpis = ($czesci -join ", ") }
    if ($null -eq $c.Koszt) { $c.Powody += "w ${plikKosztu} nie ma liczby tokenow" }
  } else {
    $c.Powody += "nie ma ${plikKosztu} - cykl nigdy nie policzyl swojego kosztu"
  }

  if ($zKolejka) {
    $wyciagnij = Join-Path $script:NadzZrodlo "narzedzia\wyciagnij-fakty.ps1"
    $r = Wolaj-Skrypt $wyciagnij @("-Zrodlo", ('"' + $script:NadzZrodlo + '"'), "-Kolejka") 90
    if ($r.ok -and $r.kod -eq 0) {
      $k = Klucze-Z-Tekstu $r.tekst
      if ($k["kolejka.kawalki"]   -match '^\d+$') { $c.Kawalki   = [int]$k["kolejka.kawalki"] }
      if ($k["kolejka.przebiegi"] -match '^\d+$') { $c.Przebiegi = [int]$k["kolejka.przebiegi"] }
      if ($null -eq $c.Kawalki) { $c.Powody += "przebieg probny wylawiania nie oddal liczb kolejki" }
    } else {
      $powod = $r.powod
      if (-not $powod) { $powod = "kod wyjscia $($r.kod)" }
      $c.Powody += "nie dalo sie policzyc kolejki na zywo (${powod}) - zostaje liczba z ostatniego podsumowania"
    }
  }
  return $c
}

# Ile godzin cykl stoi. $null, gdy nie wiadomo - i wtedy TEZ jest problem,
# bo brak daty ostatniego przebiegu znaczy, ze cykl nie skonczyl nigdy.
function Godzin-Od-Cyklu($c) {
  if (-not $c.Data) { return $null }
  return [int]([datetime]::Now - $c.Data).TotalHours
}

function Opis-Cyklu($c) {
  $linie = @()
  if ($c.Data) {
    $godzin = Godzin-Od-Cyklu $c
    $kiedy = "$($c.Data.ToString('yyyy-MM-dd HH:mm'))"
    if ($godzin -lt 24) { $kiedy = "$kiedy (dzis, $godzin h temu)" }
    else { $kiedy = "$kiedy ($([int]($godzin / 24)) dni temu)" }
    $linie += "  ostatni przebieg: $kiedy"
    $st = $c.Status
    if (-not $st) { $st = "NIE WIADOMO - w pliku nie ma klucza 'status'" }
    $linie += "  jak poszedl     : $st"
    if ($c.Opis) { $linie += "                    $($c.Opis)" }
  } else {
    $linie += "  ostatni przebieg: NIGDY albo nie do odczytania"
  }
  if ($c.Pracuje) { $linie += "  teraz           : cykl wlasnie pracuje" }

  if ($null -ne $c.Kawalki) {
    $ogon = ""
    if ($null -ne $c.Przebiegi) { $ogon = " ($($c.Przebiegi) porcji do modelu)" }
    $linie += "  czeka w kolejce : $($c.Kawalki) kawalkow rozmow${ogon}"
  } elseif ($null -ne $c.Zaleglosc) {
    $linie += "  czeka w kolejce : $($c.Zaleglosc) przebiegow wg ostatniego podsumowania (na zywo nie policzone)"
  } else {
    $linie += "  czeka w kolejce : NIE WIADOMO"
  }

  if ($null -ne $c.Koszt) {
    $kiedy = "nieznanego dnia"
    if ($c.KosztData) { $kiedy = $c.KosztData.ToString('yyyy-MM-dd') }
    $ogon = ""
    if ($c.KosztOpis) { $ogon = " - $($c.KosztOpis)" }
    $linie += "  ostatni koszt   : ~$(Liczba-Ludzka $c.Koszt) tokenow, ${kiedy}${ogon}"
    $linie += "                    to PRAWDZIWE wywolanie modelu, osobno od rachunku wyzej"
  } else {
    $linie += "  ostatni koszt   : NIE POLICZONY ANI RAZU"
  }
  foreach ($p in $c.Powody) { $linie += "  !               : $p" }
  return ,$linie
}

# Czy cykl ma dzis ruszyc. Warunek ten sam, co dzis w straznik-zasad.ps1:
# inna data w .cykl-stan niz dzisiejsza (albo przebieg odlozony, czyli taki,
# ktorego w ogole nie bylo), do tego zaden przebieg nie pracuje w tej chwili.
# Pusta kolejka jest jedynym powodem, zeby nie ruszac - kolejki, ktorej nie
# umiemy odczytac, nie udajemy i cykl idzie, bo sam powie, co mu przeszkadza.
function Czy-Ruszac-Cykl {
  $w = [pscustomobject]@{ Ruszac = $false; Powod = "" }
  $skrypt = Join-Path $script:NadzZrodlo "narzedzia\cykl-dzienny.ps1"
  if (-not (Test-Path $skrypt)) {
    $w.Powod = "nie ma ${skrypt}"
    return $w
  }
  if (-not (Test-Path (Join-Path $script:NadzZrodlo "lore\pyproject.toml"))) {
    $w.Powod = "nie ma modulu pamieci (lore) - cykl nie mialby czego czytac"
    return $w
  }
  $dzis = Get-Date -Format 'yyyy-MM-dd'
  $stan = Czytaj-Klucze (Join-Path $script:NadzWiedza ".cykl-stan")
  if (($stan["data"] -eq $dzis) -and ($stan["status"] -ne "odlozony")) {
    $w.Powod = "cykl chodzil juz dzis ($dzis, status $($stan['status']))"
    return $w
  }
  $c = Stan-Cyklu $false
  if ($c.Pracuje) {
    $w.Powod = "cykl wlasnie pracuje"
    return $w
  }
  $w.Ruszac = $true
  $w.Powod = "ostatni przebieg: $($stan['data']), dzis jest $dzis"
  return $w
}

function Ruszaj-Cykl {
  $skrypt = Join-Path $script:NadzZrodlo "narzedzia\cykl-dzienny.ps1"
  $argumenty = '-Zrodlo "' + $script:NadzZrodlo + '" -KatalogDomowy "' + $script:NadzDom + '"'
  if ($script:NadzProba) {
    Write-Host "[proba] NIE startuje cyklu: powershell -File ${skrypt} ${argumenty}"
    return $true
  }
  $poszlo = Odpal-W-Tle $skrypt $argumenty
  if ($poszlo) {
    Notuj "wystartowal cykl wiedzy"
    try { Dopisz-Klucze $script:NadzPlikStanu @{ "cykl.ruszony" = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') } }
    catch { Notuj "nie udalo sie zapisac znacznika startu cyklu" }
  }
  return $poszlo
}

# ------------------------------------------------------------ rachunek za pamiec

# Rozbicie na trzy kubelki - JEDEN i ten sam wydruk, ktory uzytkownik zna
# z narzedzia\koszt-pamieci.ps1 -Rozbicie. Drugiego renderowania tu nie ma
# i nie ma go byc: dwie kopie tego samego rachunku rozjechalyby sie przy
# pierwszej poprawce. -Projekt nie podajemy z rozmyslem - nadzorca nie siedzi
# w zadnym projekcie, a skrypt mierzy wtedy ladunki z szablonow w $Zrodlo,
# ktore i tak sa te same, co wdrozone w projektach.
function Rachunek-Rozbicie {
  $skrypt = Join-Path $script:NadzZrodlo "narzedzia\koszt-pamieci.ps1"
  $r = Wolaj-Skrypt $skrypt @("-KatalogDomowy", ('"' + $script:NadzDom + '"'), "-Zrodlo", ('"' + $script:NadzZrodlo + '"'), "-Rozbicie", "-Zwykly") 120
  if (-not $r.ok) {
    return ,@("  NIE UDALO SIE POLICZYC RACHUNKU: $($r.powod)",
             "  sprobuj recznie: powershell -ExecutionPolicy Bypass -File ${skrypt} -Rozbicie")
  }
  $linie = @(($r.tekst -split '\r?\n') | ForEach-Object { "$_".TrimEnd() })
  while ($linie.Count -gt 0 -and $linie[-1] -eq "") { $linie = $linie[0..($linie.Count - 2)] }
  if ($linie.Count -lt 2) {
    $powod = $r.powod
    if (-not $powod) { $powod = "skrypt nic nie wypisal (kod $($r.kod))" }
    return ,@("  RACHUNEK PUSTY: $powod")
  }
  return ,$linie
}

# Rachunek za pamiec jednym wywolaniem: narzedzia\koszt-pamieci.ps1 -Dane oddaje
# linie (te sama, co -Zwiezle), alarmy z waga i okresem, ocene kosztu nauki
# (zwykly dzien czy nadrabianie) i dni do wykresu - w liniach "klucz: wartosc".
# Kod wyjscia: 0 = nic nie jest ucinane i zaden CZERWONY prog nie przekroczony,
# 1 = jedno z dwojga; zolta informacja kodu nie podnosi. Progi siedza
# w koszt-pamieci.ps1 razem z uzasadnieniem - nadzorca ich NIE powtarza, bo drugi
# komplet liczb zaczalby klamac przy pierwszej zmianie tamtych.
function Linia-Rachunku {
  $skrypt = Join-Path $script:NadzZrodlo "narzedzia\koszt-pamieci.ps1"
  $r = Wolaj-Skrypt $skrypt @("-KatalogDomowy", ('"' + $script:NadzDom + '"'), "-Zrodlo", ('"' + $script:NadzZrodlo + '"'), "-Dane", "-Zwykly") 120
  $w = [pscustomobject]@{ Linia = $null; Kod = $null; Powod = ""; Klucze = [ordered]@{} }
  if (-not $r.ok) {
    $w.Powod = $r.powod
    return $w
  }
  $w.Klucze = Klucze-Z-Tekstu $r.tekst
  $w.Kod = $r.kod
  if ($w.Klucze.Contains("linia")) { $w.Linia = "$($w.Klucze['linia'])".Trim() }
  if (-not $w.Linia) {
    $w.Powod = "koszt-pamieci.ps1 -Dane nie oddal linii rachunku (kod $($r.kod))"
    if ($r.powod) { $w.Powod = $w.Powod + " - " + $r.powod }
  }
  return $w
}

# Warstwy pamieci dla zakladki "Warstwy pamieci": narzedzia\koszt-pamieci.ps1
# -Warstwy oddaje JSON z lista warstw (kiedy sie wczytuje, stala czy tymczasowa,
# kto pisze, ile znakow, czy plik jest). Lista warstw zyje TYLKO tam - tutaj
# jest wywolanie i odczyt, bez drugiej kopii sciezek. Nieudane wywolanie albo
# smiec zamiast JSON-u to Powod, ktory okno pokazuje zamiast pustej listy.
function Warstwy-Pamieci {
  $w = [pscustomobject]@{ Warstwy = @(); Uwagi = @(); Powod = ""; Wygenerowano = ""; TrybGlobalny = $null; Projekt = "" }
  $skrypt = Join-Path $script:NadzZrodlo "narzedzia\koszt-pamieci.ps1"
  $r = Wolaj-Skrypt $skrypt @("-KatalogDomowy", ('"' + $script:NadzDom + '"'), "-Zrodlo", ('"' + $script:NadzZrodlo + '"'), "-Warstwy") 120
  if (-not $r.ok) {
    $w.Powod = $r.powod
    return $w
  }
  $tekst = "$($r.tekst)".Trim()
  if (-not $tekst) {
    $w.Powod = "koszt-pamieci.ps1 -Warstwy nic nie wypisal (kod $($r.kod))"
    if ($r.powod) { $w.Powod = $w.Powod + " - " + $r.powod }
    return $w
  }
  $j = $null
  try { $j = $tekst | ConvertFrom-Json }
  catch {
    Zanotuj-Wywrotke "odczyt listy warstw pamieci" $_
    $w.Powod = "koszt-pamieci.ps1 -Warstwy oddal cos, co nie jest JSON-em: $($_.Exception.Message)"
    return $w
  }
  if (-not $j -or ($null -eq $j.Warstwy)) {
    $w.Powod = "w odpowiedzi koszt-pamieci.ps1 -Warstwy nie ma listy warstw (kod $($r.kod))"
    return $w
  }
  $w.Warstwy = @($j.Warstwy)
  $w.Uwagi = @($j.Uwagi | Where-Object { $_ })
  $w.Wygenerowano = "$($j.Wygenerowano)"
  $w.TrybGlobalny = $j.TrybGlobalny
  $w.Projekt = "$($j.Projekt)"
  if ($r.kod -ne 0) {
    $w.Uwagi += "koszt-pamieci.ps1 -Warstwy skonczyl z kodem $($r.kod)$(if ($r.powod) { ': ' + $r.powod })"
  }
  return $w
}

# Odczyt pojedynczych kluczy z odpowiedzi -Dane. Brak klucza i smiec to $null /
# pusty tekst - "nie wiem", nigdy zero.
function Liczba-Z-Klucza($k, [string]$klucz) {
  if (-not $k) { return $null }
  $v = "$($k[$klucz])".Trim()
  if ($v -match '^-?\d+$') { return [long]$v }
  return $null
}

function Tekst-Z-Klucza($k, [string]$klucz) {
  if (-not $k) { return "" }
  return "$($k[$klucz])".Trim()
}

# Alarmy policzone w koszt-pamieci.ps1 - surowe, bez ogonkow. Po polsku ubiera
# je Alarm-Z-Rachunku nizej; tu tylko je wyjmujemy.
function Alarmy-Rachunku($rachunek) {
  $lista = @()
  if ((-not $rachunek) -or (-not $rachunek.Klucze)) { return ,$lista }
  $k = $rachunek.Klucze
  $ile = Liczba-Z-Klucza $k "alarmy"
  if ($null -eq $ile) { return ,$lista }
  for ($i = 1; $i -le $ile; $i++) {
    $lista += [pscustomobject]@{
      Temat  = (Tekst-Z-Klucza $k "alarm.$i.temat")
      Waga   = (Tekst-Z-Klucza $k "alarm.$i.waga")
      Liczba = (Liczba-Z-Klucza $k "alarm.$i.liczba")
      Prog   = (Liczba-Z-Klucza $k "alarm.$i.prog")
      Okres  = (Tekst-Z-Klucza $k "alarm.$i.okres")
      Krotko = (Tekst-Z-Klucza $k "alarm.$i.krotko")
      Pelny  = (Tekst-Z-Klucza $k "alarm.$i.pelny")
    }
  }
  return ,$lista
}

# Ocena ostatniego dnia nauki: zwykly dzien, nadrabianie, mieszany, nieznany -
# policzona w koszt-pamieci.ps1 (Ocena-Cyklu), tu tylko odczytana.
function Ocena-Nauki($rachunek) {
  $k = $null
  if ($rachunek) { $k = $rachunek.Klucze }
  return [pscustomobject]@{
    Rodzaj         = (Tekst-Z-Klucza  $k "cykl.rodzaj")
    Data           = (Data-Lub-Nic (Tekst-Z-Klucza $k "cykl.data"))
    Tokeny         = (Liczba-Z-Klucza $k "cykl.tokeny")
    Wiadomosci     = (Liczba-Z-Klucza $k "cykl.wiadomosci")
    ZakresOd       = (Tekst-Z-Klucza  $k "cykl.zakres_od")
    ZakresDo       = (Tekst-Z-Klucza  $k "cykl.zakres_do")
    Zwykle         = (Liczba-Z-Klucza $k "cykl.zwykle")
    Nadrabianie    = (Liczba-Z-Klucza $k "cykl.nadrabianie")
    Typowy         = (Liczba-Z-Klucza $k "cykl.typowy_dzien")
    TypowychDni    = (Liczba-Z-Klucza $k "cykl.typowych_dni")
    Prog           = (Liczba-Z-Klucza $k "cykl.prog")
    Wzrosty        = (Liczba-Z-Klucza $k "cykl.wzrosty")
    WzrostOd       = (Data-Lub-Nic (Tekst-Z-Klucza $k "cykl.wzrost_od"))
    WzrostOdTokeny = (Liczba-Z-Klucza $k "cykl.wzrost_od_tokeny")
    WzrostDo       = (Data-Lub-Nic (Tekst-Z-Klucza $k "cykl.wzrost_do"))
    WzrostDoTokeny = (Liczba-Z-Klucza $k "cykl.wzrost_do_tokeny")
    ProcWzrostu    = (Liczba-Z-Klucza $k "cykl.proc_wzrostu")
  }
}

# ------------------------------------------------------------------ aktualizacja

# Przycisk [Aktualizuj] robi DOKLADNIE to, co dzis robi hook Codeksa: wola
# narzedzia\straznik-zasad.ps1 -Tlo. Nie ma tu drugiej implementacji pobierania
# (fetch + merge --ff-only, nigdy reset --hard) ani drugiego kompletu warunkow
# odmowy - straznik ma je u siebie i to on jest jedynym zrodlem prawdy.
# Straznik w tym trybie milczy na ekran i pisze do ~\.claude\.megaruchacz-tlo.log,
# wiec bierzemy stad roznice: to, co dopisal, jest odpowiedzia dla czlowieka.
function Aktualizuj {
  $skrypt = Join-Path $script:NadzZrodlo "narzedzia\straznik-zasad.ps1"
  $plikLogu = Join-Path $script:NadzDom ".claude\.megaruchacz-tlo.log"
  $przed = @()
  $raw = Czytaj-Tekst $plikLogu
  if ($raw) { $przed = @(($raw -split '\r?\n') | Where-Object { $_.Trim() }) }

  if ($script:NadzProba) { return ,@("[proba] NIE wolam straznika: ${skrypt} -Tlo") }

  $r = Wolaj-Skrypt $skrypt @("-Tlo", "-Zrodlo", ('"' + $script:NadzZrodlo + '"'), "-KatalogDomowy", ('"' + $script:NadzDom + '"')) 180
  if (-not $r.ok) {
    Zanotuj-Wywrotke "aktualizacja przez straznika" $r.powod
    return ,@("NIE UDALO SIE: $($r.powod)",
             "sprobuj recznie: powershell -ExecutionPolicy Bypass -File ${skrypt} -Tlo")
  }

  $po = @()
  $raw = Czytaj-Tekst $plikLogu
  if ($raw) { $po = @(($raw -split '\r?\n') | Where-Object { $_.Trim() }) }

  # Dziennik jest obcinany z gory do stalej liczby linii, wiec porownujemy
  # tresc, a nie indeksy - inaczej po obcieciu "nowe" wyszlyby stare linie.
  $nowe = @()
  if ($po.Count -gt 0) {
    $zbior = @{}
    foreach ($l in $przed) { $zbior[$l] = $true }
    foreach ($l in $po) { if (-not $zbior.ContainsKey($l)) { $nowe += $l } }
  }
  if ($nowe.Count -eq 0) {
    # Cisza po straznikU nie znaczy "wszystko gra" - znaczy, ze nie wiemy.
    return ,@("Straznik przeszedl (kod $($r.kod)), ale nie dopisal ani jednej linii do dziennika.",
             "To NIE jest potwierdzenie, ze cos pobral - to brak odpowiedzi.",
             "Dziennik: ${plikLogu}")
  }
  Notuj "aktualizacja: $($nowe.Count) nowych linii w dzienniku straznika"
  return ,$nowe
}

# -------------------------------------------------------------------- alarmy

# Kazdy alarm ma TEMAT (po nim liczy sie "jeden na dobe"), TYTUL (do paska
# powiadomienia) i TRESC, ktora mowi CO ZROBIC. Alarm bez porady uczy tylko
# tego, zeby go zamykac nie czytajac.
# WAGA ("pilne" / "uwaga" / "info") - pusta znaczy "wedlug tematu" (Waga-Alarmu).
# PORADA - gotowe zdania dla czlowieka; pusta znaczy "odsiej je z tresci"
# (Porada-Ludzka), tak jak dotad.
function Alarm([string]$temat, [string]$tytul, [string]$tresc, [string]$waga = "", [string]$porada = "") {
  return [pscustomobject]@{ Temat = $temat; Tytul = $tytul; Tresc = $tresc; Waga = $waga; Porada = $porada }
}

# Czy alarm o tym temacie juz dzis poszedl. Jeden na sprawe na dobe - inaczej
# nadzorca zasypuje pulpit i uczy ignorowania.
function Alarm-Juz-Byl([string]$temat) {
  $stan = Czytaj-Klucze $script:NadzPlikStanu
  return ($stan["alarm.$temat"] -eq (Get-Date -Format 'yyyy-MM-dd'))
}

function Odnotuj-Alarm([string]$temat) {
  if ($script:NadzProba) { return }
  try { Dopisz-Klucze $script:NadzPlikStanu @{ "alarm.$temat" = (Get-Date -Format 'yyyy-MM-dd') } }
  catch { Notuj "nie udalo sie odnotowac alarmu ${temat} - moze sie powtorzyc" }
}

# Wywrotki straznika czytamy BEZ czyszczenia: klucze blad.* naleza do straznika
# i to on melduje je w sesji (Odbierz-Wywrotki). Gdybysmy je tu sprzatneli,
# meldunek w oknie Claude Code przepadlby na zawsze.
function Wywrotki-Straznika {
  $plik = Join-Path $script:NadzDom ".claude\.megaruchacz-straznik.txt"
  $stan = Czytaj-Klucze $plik
  $linie = @()
  foreach ($k in @($stan.Keys)) {
    if ($k -notmatch '^blad\.\d+$') { continue }
    $cz = "$($stan[$k])" -split '\s*\|\s*', 4
    if ($cz.Count -eq 4) { $linie += "$($cz[2]) - $($cz[3]) ($($cz[1]))" }
    else { $linie += "$($stan[$k])" }
  }
  return ,$linie
}

# Cztery sprawy ze zlecenia plus piata: wlasne potkniecia nadzorcy z poprzedniego
# przebiegu. Zwraca komplet alarmow BEZ patrzenia na "raz na dobe" - o tym
# decyduje ten, kto je pokazuje.
function Zbierz-Alarmy($cykl, $rachunek) {
  $alarmy = @()

  # TRESC ALARMU PISZEMY PO POLSKU Z OGONKAMI I BEZ ZARGONU, bo trafia prosto
  # na wierzch okna, do sekcji "co wymaga uwagi". Zdania z komendami i sciezkami
  # sa CELOWO osobnymi zdaniami: Porada-Ludzka odsiewa je z okna, a caly tekst
  # i tak zostaje w szczegolach i w dzienniku, wiec nic nie ginie.

  # 1. Nauka z rozmow stoi. Prog: doba - taki jest jej rytm pracy.
  $godzin = Godzin-Od-Cyklu $cykl
  if ($null -eq $godzin) {
    $alarmy += Alarm "cykl" "MegaRuchacz: nauka z rozmów nie przeszła ani razu" (
      "Nie ma zapisu ani jednego zakończonego przebiegu, więc MegaRuchacz niczego się jeszcze nie nauczył z Twoich rozmów. " +
      "Kliknij ikonę MegaRuchacza i użyj przycisku [Przeczytaj zaległe rozmowy] - pokaże koszt i zapyta o zgodę. " +
      "Jesli to nie pomoze, sprawdz recznie: powershell -ExecutionPolicy Bypass -File " +
      "$($script:NadzZrodlo)\narzedzia\cykl-dzienny.ps1 -Proba")
  } elseif ($godzin -gt $GODZIN_CYKL_STOI) {
    $dni = [int]($godzin / 24)
    $ile = if ($dni -ge 1) { "${dni} $(Odmiana $dni 'dnia' 'dni' 'dni')" } else { "${godzin} $(Odmiana $godzin 'godziny' 'godzin' 'godzin')" }
    $czeka = ""
    if ($null -ne $cykl.Kawalki)       { $czeka = " Czeka $(Liczba-Ludzka $cykl.Kawalki) $(Odmiana ([int]$cykl.Kawalki) 'fragment rozmów' 'fragmenty rozmów' 'fragmentów rozmów')." }
    elseif ($null -ne $cykl.Zaleglosc) { $czeka = " Zaległość: $($cykl.Zaleglosc) $(Odmiana ([int]$cykl.Zaleglosc) 'porcja' 'porcje' 'porcji')." }
    $alarmy += Alarm "cykl" "MegaRuchacz: nauka z rozmów stoi od ${ile}" (
      "Ostatnio przeszła $(Kiedy-Ludzko $cykl.Data).${czeka} " +
      "Kliknij ikonę MegaRuchacza i użyj przycisku [Przeczytaj zaległe rozmowy] - pokaże koszt i zapyta o zgodę. " +
      "Jesli to nie rusza, sprawdz co blokuje: powershell -ExecutionPolicy Bypass -File " +
      "$($script:NadzZrodlo)\narzedzia\cykl-dzienny.ps1 -Proba")
  }

  # 2. Ucinanie - widac po kodzie 1 i slowie UCINANE w linii rachunku.
  if (($rachunek.Kod -eq 1) -and $rachunek.Linia -and ($rachunek.Linia -match 'UCINANE')) {
    $alarmy += Alarm "ucinane" "MegaRuchacz: część tekstu jest ucinana po cichu" (
      "Skrócony tekst nie dochodzi do modelu, a nikt o tym nie mówi. " +
      "Kliknij ikonę MegaRuchacza i otwórz zakładkę Szczegóły - tam widać, która pozycja nie mieści się w limicie. " +
      "Najczęściej pomaga skrócenie sekcji 'Co wiem' w Twoim pliku z wiedzą. " +
      "Rachunek mowi: $($rachunek.Linia). " +
      "Plik do skrocenia: $($script:NadzDom)\.claude\CLAUDE.md")
  }

  # 3. Progi kosztu - KAZDY alarm osobno, z tym, ZA CO i ZA JAKI OKRES jest
  # liczba. Do 24.09.2026 stal tu jeden zbiorczy "pamiec kosztuje wiecej, niz
  # powinna", ktory za jednorazowe nadrabianie zaleglosci swiecil na czerwono
  # i mowil o pamieci, choc chodzilo o nauke z rozmow. Zolte informacje (waga
  # "info") ida osobna droga - Zbierz-Informacje - i nie wyskakuja w dymku.
  $ocena = Ocena-Nauki $rachunek
  $czerwonych = 0
  foreach ($a in (Alarmy-Rachunku $rachunek)) {
    if ($a.Waga -eq "info") { continue }
    if ($a.Waga -eq "pilne") { $czerwonych++ }
    $alarmy += Alarm-Z-Rachunku $a $ocena
  }
  # Kod 1 bez ucinania i bez ani jednego czerwonego alarmu na liscie znaczy, ze
  # nie umiemy odczytac, co rachunek zglasza - mowimy to wprost, zamiast zgadywac.
  if (($rachunek.Kod -eq 1) -and $rachunek.Linia -and ($rachunek.Linia -notmatch 'UCINANE') -and ($czerwonych -eq 0)) {
    $alarmy += Alarm "koszt" "MegaRuchacz: rachunek zgłasza przekroczony próg" (
      "Nie umiem odczytać, który próg - pełna treść jest w zakładce Szczegóły. " +
      "Rachunek mowi: $($rachunek.Linia). " +
      "Progi i ich uzasadnienie sa w $($script:NadzZrodlo)\narzedzia\koszt-pamieci.ps1") "uwaga"
  }
  if ((-not $rachunek.Linia) -and $rachunek.Powod) {
    $alarmy += Alarm "rachunek" "MegaRuchacz: nie umiem policzyć, ile kosztuje pamięć" (
      "Dopóki to trwa, nikt nie wie, ile kosztuje pamięć ani czy coś jest ucinane. " +
      "Powod: $($rachunek.Powod). " +
      "Sprawdz recznie: powershell -ExecutionPolicy Bypass -File " +
      "$($script:NadzZrodlo)\narzedzia\koszt-pamieci.ps1 -Rozbicie")
  }
  # 4. Straznik zanotowal wywrotke przy przebiegu, ktorego nikt nie ogladal.
  $wyw = Wywrotki-Straznika
  if ($wyw.Count -gt 0) {
    $ogon = ""
    if ($wyw.Count -gt 1) { $ogon = " (i jeszcze $($wyw.Count - 1))" }
    $alarmy += Alarm "wywrotka" "MegaRuchacz: aktualizacja w tle się wywróciła" (
      "Coś poszło nie tak przy przebiegu, którego nikt nie oglądał. " +
      "Kliknij ikonę MegaRuchacza i użyj przycisku [Pobierz nowszą wersję] - przejdzie jeszcze raz i powie, czy to się powtarza. " +
      "Blad: $($wyw[0])${ogon}. " +
      "Komplet w $($script:NadzDom)\.claude\.megaruchacz-straznik.txt (klucze blad.*) " +
      "oraz w $($script:NadzDom)\.claude\.megaruchacz-tlo.log")
  }

  return ,$alarmy
}

# ====================================================== jezyk, ktorym mowi czlowiek
#
# Wszystko ponizej sluzy WYLACZNIE prezentacji. Bierze liczby, ktore juz sa
# policzone wyzej, i ubiera je w zdania, ktorych uzywa uzytkownik. Ani jedna
# z tych funkcji nie liczy kosztu drugi raz: rachunek liczy
# narzedzia\koszt-pamieci.ps1, kolejke narzedzia\wyciagnij-fakty.ps1 -Kolejka,
# koszt cyklu zapisuje samo wylawianie. Jedyna arytmetyka, ktora powstaje tutaj,
# to SZACUNEK przed przyciskiem (Szacunek-Cyklu) - i on mnozy wylacznie liczby
# ZMIERZONE, zadnej stalej z powietrza.
#
# Teksty w tej sekcji maja polskie znaki i tak ma byc: ida do okna, nie do kodu.
# Plik jest zapisany w UTF-8 ZE ZNACZNIKIEM BOM - bez niego PowerShell 5.1 czyta
# go jako ANSI i zamiast "koszt rozmow" wychodza krzaki. To bylo juz dwa razy.

# Odmiana przez liczbe. Bez niej okno pisze "1 fragmentow" i od razu wyglada
# na zrobione byle jak - a ma byc tym, czemu uzytkownik ufa.
function Odmiana([int]$n, [string]$jeden, [string]$kilka, [string]$wiele) {
  if ($n -eq 1) { return $jeden }
  $ost = $n % 10
  $dwie = $n % 100
  if (($ost -ge 2) -and ($ost -le 4) -and (($dwie -lt 12) -or ($dwie -gt 14))) { return $kilka }
  return $wiele
}

# "dzis o 09:42" zamiast "2026-09-24 09:42". Data w formacie maszynowym zmusza
# czlowieka do liczenia w glowie, a okno ma odpowiadac w trzy sekundy.
function Kiedy-Ludzko($data) {
  if (-not $data) { return $null }
  $dzis = [datetime]::Now.Date
  if ($data.Date -eq $dzis)             { return "dziś o $($data.ToString('HH:mm'))" }
  if ($data.Date -eq $dzis.AddDays(-1)) { return "wczoraj o $($data.ToString('HH:mm'))" }
  $dni = [int]($dzis - $data.Date).TotalDays
  return "$($data.ToString('dd.MM')), $dni $(Odmiana $dni 'dzień' 'dni' 'dni') temu"
}

# To samo, ale SAM DZIEN. Osobna funkcja, bo .koszt-cyklu.txt zapisuje sama date
# bez godziny - "dzis o 00:00" brzmialoby jak pomiar z polnocy, czyli jak liczba,
# ktorej nikt nie zmierzyl.
function Dzien-Ludzko($data) {
  if (-not $data) { return $null }
  $dzis = [datetime]::Now.Date
  if ($data.Date -eq $dzis)             { return "dziś" }
  if ($data.Date -eq $dzis.AddDays(-1)) { return "wczoraj" }
  return $data.ToString('dd.MM')
}

# TRZY LICZBY NA WIERZCHU OKNA.
#
# Pierwsze dwie wyjmujemy z JEDNEJ linii, ktora wypisuje
# narzedzia\koszt-pamieci.ps1 -Zwiezle (mamy ja juz w $rachunek.Linia, zebrana
# przy odswiezaniu). Trzecia to koszt ostatniego przebiegu nauki, czyli to, co
# samo wylawianie zapisalo w .koszt-cyklu.txt. Nic tu nie jest liczone na nowo -
# to sa TE SAME liczby, ktore stoja w rozbiciu pod [Szczegoly], tylko wyjete
# na wierzch i opisane zdaniem.
#
# Gdy ktorejs nie da sie ustalic, pole Liczba zostaje puste, a w Powod stoi
# DLACZEGO. Okno pokazuje wtedy "nie wiem" i powod, nigdy zera: zero znaczy
# "nic nie kosztuje" i byloby najdrozszym rodzajem ciszy w calym narzedziu.
#
# PODPISY MOWIA, JAK TO SIE NAPRAWDE PLACI (poprawione 24.09.2026 po pomiarze na
# prawdziwych transkryptach, opis w .claude\mapa.md, sekcja "Koszt tekstu
# w kontekscie a pamiec podreczna modelu"). Stary podpis "Otwarcie nowej sesji
# ... raz" wprowadzal w blad: tekst WCHODZI do rozmowy raz, ale model czyta cala
# rozmowe przy kazdym swoim kroku (~10 krokow na jedna wiadomosc), tyle ze
# z bufora, za ulamek zwyklej ceny. To samo z przypomnieniem - zostaje w historii.
# Podpisy mowia to slowami, BEZ przeliczania: liczby sa te same, co w rachunku.
#
# Zdania "pamiec to ok. 1% tego, co model czyta w sesji" tu NIE MA z rozmyslem.
# Dalo by sie je policzyc z pola usage w transkryptach, ale nie tanio przy
# otwarciu okna (pojedynczy transkrypt ma do 138 MB), a liczba wpisana na sztywno
# zaczelaby klamac przy pierwszej zmianie. Gdy powstanie pomiar - tu jest miejsce.
function Trzy-Liczby($rachunek, $cykl) {
  $naWiadomosc = [pscustomobject]@{
    Naglowek = "Każda Twoja wiadomość dokleja"
    Liczba   = $null
    Opis     = "Przypomnienie zasad. Model czyta je potem przy każdym swoim kroku, ale z bufora, za ułamek ceny."
    Ogon     = "i zostają w rozmowie do końca"
    Powod    = ""
  }
  $naSesje = [pscustomobject]@{
    Naglowek = "Na otwarcie sesji wchodzi"
    Liczba   = $null
    Opis     = "Wiedza o Tobie i o firmie. Wchodzi raz, ale model czyta ją przy każdym kroku - z bufora, za ułamek ceny."
    Ogon     = "i zostają w rozmowie do końca"
    Powod    = ""
  }
  $naDobe = [pscustomobject]@{
    Naglowek = "Raz dziennie, nauka z rozmów"
    Liczba   = $null
    Opis     = "Jedyne miejsce, w którym naprawdę płacisz za wywołanie modelu - reszta to doklejony tekst."
    Ogon     = ""
    Powod    = ""
    # Za jaki okres i czy to nadrabianie - bez tego drogi dzien nadrabiania
    # wygladal na karcie jak nowa norma. Waga koloruje tylko ten jeden napis.
    Znacznik     = ""
    ZnacznikWaga = ""
  }

  if (-not $rachunek -or -not $rachunek.Linia) {
    $powod = "nie udało się policzyć rachunku"
    if ($rachunek -and $rachunek.Powod) { $powod = $rachunek.Powod }
    $naWiadomosc.Powod = $powod
    $naSesje.Powod     = $powod
  } else {
    $l = $rachunek.Linia
    $m = [regex]::Match($l, 'wiadomosc\s*\+(\d+)\s*tokenow')
    if ($m.Success) { $naWiadomosc.Liczba = [long]$m.Groups[1].Value }
    elseif ($l -match 'przypomnienia nie umiem zmierzyc') {
      $naWiadomosc.Powod = "rachunek nie znalazł gotowego przypomnienia, więc nie ma czego zmierzyć"
    } else {
      $naWiadomosc.Powod = "w odpowiedzi rachunku nie ma tej liczby: $l"
    }

    $m = [regex]::Match($l, 'start sesji\s*\+(\d+)\s*tokenow')
    if ($m.Success) { $naSesje.Liczba = [long]$m.Groups[1].Value }
    elseif ($l -match 'startu sesji nie umiem zmierzyc') {
      $naSesje.Powod = "rachunek nie umie zmierzyć tego, co wchodzi na starcie sesji"
    } else {
      $naSesje.Powod = "w odpowiedzi rachunku nie ma tej liczby: $l"
    }
  }

  if ($cykl -and ($null -ne $cykl.Koszt)) {
    $naDobe.Liczba = [long]$cykl.Koszt
    $kiedy = Dzien-Ludzko $cykl.KosztData
    if ($kiedy) { $naDobe.Ogon = "ostatnio $kiedy" } else { $naDobe.Ogon = "przy ostatnim przebiegu" }
    $o = Ocena-Nauki $rachunek
    $okres = Okres-Ludzko $o.ZakresOd $o.ZakresDo
    switch ($o.Rodzaj) {
      "nadrabianie" { $naDobe.Znacznik = "nadrabianie zaległości"; $naDobe.ZnacznikWaga = "info" }
      "mieszany"    { $naDobe.Znacznik = "częściowo nadrabianie";  $naDobe.ZnacznikWaga = "info" }
      "zwykly"      { $naDobe.Znacznik = "zwykły dzień";           $naDobe.ZnacznikWaga = "" }
      "nieznany"    { $naDobe.Znacznik = "okres nieznany";         $naDobe.ZnacznikWaga = "uwaga" }
    }
    if ($okres -and $naDobe.Znacznik) { $naDobe.Znacznik = "$($naDobe.Znacznik), rozmowy z $okres" }
    foreach ($a in (Alarmy-Rachunku $rachunek)) {
      if (($a.Temat -eq "cykl-zwykly") -or ($a.Temat -eq "cykl-rosnie")) { $naDobe.ZnacznikWaga = "pilne" }
    }
  } else {
    $naDobe.Powod = "nauka z rozmów nie policzyła jeszcze ani razu swojego kosztu"
    if ($cykl) {
      foreach ($p in $cykl.Powody) { if ("$p" -match 'koszt') { $naDobe.Powod = $p } }
    }
  }

  return ,@($naWiadomosc, $naSesje, $naDobe)
}

# ---------------------------------------------------- koszt nauki po ludzku

# "~312 600" - liczba zaokraglona do setek, do tytulow. Tylda mowi, ze to
# przyblizenie; pelna liczba stoi na karcie i w szczegolach.
function Okolo($n) {
  if ($null -eq $n) { return "?" }
  return (Liczba-Ludzka ([long]([math]::Round([double]$n / 100.0) * 100)))
}

# "16-17.09" albo "28.08-02.09" (w oknie z polpauza) - okres, za ktory
# zaplacono, jednym rzutem oka.
function Okres-Ludzko([string]$od, [string]$doo) {
  $a = Data-Lub-Nic $od
  $b = Data-Lub-Nic $doo
  if (-not $a) { return "" }
  if ((-not $b) -or ($a.Date -eq $b.Date)) { return $a.ToString('dd.MM') }
  if (($a.Month -eq $b.Month) -and ($a.Year -eq $b.Year)) { return ($a.ToString('dd') + "–" + $b.ToString('dd.MM')) }
  return ($a.ToString('dd.MM') + "–" + $b.ToString('dd.MM'))
}

# Ile kosztuje zwykly dzien. Liczba pochodzi z koszt-pamieci.ps1 (typowa wartosc
# z dni bez nadrabiania); gdy jej nie ma, mowimy to wprost - nie zgadujemy.
function Zdanie-Zwyklego-Dnia($o) {
  if ($o -and ($null -ne $o.Typowy) -and ($o.TypowychDni -gt 0)) {
    $z = "z $($o.TypowychDni) dni"
    if ($o.TypowychDni -eq 1) { $z = "z 1 dnia" }
    return "zwykły dzień kosztuje ok. $(Okolo $o.Typowy) tokenów (typowa wartość $z bez nadrabiania)"
  }
  return "ile kosztuje zwykły dzień - jeszcze nie wiem, statystyka dopiero się zbiera"
}

function Z-Wielkiej([string]$t) {
  if (-not $t) { return "" }
  return $t.Substring(0, 1).ToUpper() + $t.Substring(1)
}

# Alarm z rachunku ubrany w zdania uzytkownika. KAZDY mowi trzy rzeczy: ZA CO
# jest liczba (kazda wiadomosc, kazda sesja, nauka z rozmow), ZA JAKI OKRES
# (stan na teraz albo konkretne dni) i CZY TO SIE POWTARZA. Pelna, surowa tresc
# z koszt-pamieci.ps1 zostaje w szczegolach - nic nie ginie.
function Alarm-Z-Rachunku($a, $o) {
  $pelne = "Rachunek mowi: $($a.Krotko). $($a.Pelny) Progi i ich uzasadnienie sa w $($script:NadzZrodlo)\narzedzia\koszt-pamieci.ps1"
  $waga = $a.Waga
  if ($waga -eq "pilne") { $waga = "pilne" } elseif ($waga -eq "info") { $waga = "info" } else { $waga = "uwaga" }
  $kiedy = "ostatnio"
  if ($o -and $o.Data) { $kiedy = Dzien-Ludzko $o.Data }
  $okres = ""
  if ($o) { $okres = Okres-Ludzko $o.ZakresOd $o.ZakresDo }
  $wiad = "nieznaną liczbę wiadomości"
  if ($o -and ($null -ne $o.Wiadomosci)) {
    $wiad = "$(Liczba-Ludzka $o.Wiadomosci) $(Odmiana ([int]$o.Wiadomosci) 'wiadomość' 'wiadomości' 'wiadomości')"
  }
  $zOkresu = ""
  if ($okres) { $zOkresu = " z $okres" }
  $tytul = ""
  $porada = ""

  switch ($a.Temat) {
    "wiadomosc" {
      $tytul = "MegaRuchacz: każda wiadomość dokleja ~$(Liczba-Ludzka $a.Liczba) tokenów"
      $porada = ("To stan plików na teraz, nie koszt jednego dnia: tyle tekstu idzie do modelu z każdym Twoim zdaniem " +
                 "(próg $(Liczba-Ludzka $a.Prog)). Która pozycja urosła - w zakładce Szczegóły.")
    }
    "sesja" {
      $tytul = "MegaRuchacz: każda sesja startuje z ~$(Liczba-Ludzka $a.Liczba) tokenami"
      $porada = ("To stan plików na teraz, nie koszt jednego dnia: tyle tekstu wchodzi przy każdym otwarciu sesji " +
                 "(próg $(Liczba-Ludzka $a.Prog)). Najczęściej pomaga skrócenie sekcji 'Co wiem' w pliku z wiedzą. Co urosło - w zakładce Szczegóły.")
    }
    "udzial" {
      $tytul = "MegaRuchacz: jedna pozycja to $($a.Liczba)% rachunku"
      $porada = "Stan plików na teraz. Skracanie czegokolwiek innego nic nie da. Która to pozycja - w zakładce Szczegóły."
    }
    "wzrost" {
      $m = [regex]::Match($a.Okres, '(\d\d\.\d\d)')
      $od = "poprzedniego pomiaru"
      if ($m.Success) { $od = $m.Groups[1].Value }
      $tytul = "MegaRuchacz: start sesji urósł o $($a.Liczba)% od $od"
      $porada = "Tyle więcej tekstu wchodzi teraz przy każdym otwarciu sesji niż przy pomiarze z $od. Co doszło - w zakładce Szczegóły."
    }
    "cykl-zwykly" {
      $tytul = "MegaRuchacz: nauka $kiedy ~$(Okolo $a.Liczba) tokenów za zwykły dzień"
      $porada = ("Przeczytała $wiad$zOkresu - rozmowy z jednego dnia, a nie nadrabianie zaległości - " +
                 "i przekroczyła próg zwykłego dnia ($(Liczba-Ludzka $a.Prog)). Dla porównania: $(Zdanie-Zwyklego-Dnia $o). " +
                 "Jak to zmniejszyć - w zakładce Szczegóły.")
    }
    "cykl-rosnie" {
      $tytul = "MegaRuchacz: koszt nauki rośnie $($a.Liczba) dni z rzędu"
      $zakres = ""
      if ($o -and $o.WzrostOd -and $o.WzrostDo) {
        $zakres = " Od $($o.WzrostOd.ToString('dd.MM')) do $($o.WzrostDo.ToString('dd.MM')): z ~$(Okolo $o.WzrostOdTokeny) do ~$(Okolo $o.WzrostDoTokeny) tokenów dziennie."
      }
      $ileProc = "wyraźnie"
      if ($o -and ($null -ne $o.ProcWzrostu)) { $ileProc = "o co najmniej $($o.ProcWzrostu)%" }
      $porada = "Zwykły dzień nauki (bez nadrabiania) drożeje dzień po dniu, za każdym razem $ileProc.$zakres To trend, nie jednorazowy skok."
    }
    "cykl-nadrabianie" {
      # Brzmienie ze zlecenia uzytkownika: co konkretnie, za jaki okres i czy
      # to sie powtarza - w tej kolejnosci.
      $tytul = "MegaRuchacz: nauka z rozmów kosztowała $kiedy ~$(Okolo $a.Liczba) tokenów — bo nadrabiała zaległość"
      $wTym = ""
      if ($o -and ($o.Zwykle -gt 0)) { $wTym = " W tym ~$(Okolo $o.Zwykle) tokenów za świeże rozmowy." }
      $porada = "Przeczytała $wiad$zOkresu.$wTym Jednorazowe nadrabianie, nie nowy stały koszt; $(Zdanie-Zwyklego-Dnia $o)."
    }
    "cykl-nieznany" {
      $tytul = "MegaRuchacz: nauka $kiedy ~$(Okolo $a.Liczba) tokenów, okres nieznany"
      $porada = ("Nauka nie zapisała, z których dni czytała rozmowy, więc nie umiem powiedzieć, czy to jednorazowe nadrabianie, " +
                 "czy zwykły dzień (próg zwykłego dnia: $(Liczba-Ludzka $a.Prog)). Zakres zapisuje nowsza wersja modułu pamięci.")
    }
    "historia" {
      if ($null -ne $a.Liczba) {
        $tytul = "MegaRuchacz: dziennik kosztów nauki ma nieczytelne linie"
        $porada = "$(Liczba-Ludzka $a.Liczba) $(Odmiana ([int]$a.Liczba) 'linia jest nieczytelna' 'linie są nieczytelne' 'linii jest nieczytelnych') - ich koszt nie wchodzi do statystyki. Szczegóły - w zakładce Szczegóły."
      } else {
        $tytul = "MegaRuchacz: historia kosztów nauki się nie zapisuje"
        $porada = "Nauka sama to zgłasza, więc statystyka 7 i 30 dni jest niepełna. Co dokładnie - w zakładce Szczegóły."
      }
    }
    default {
      $tytul = "MegaRuchacz: $($a.Krotko)"
      $porada = Porada-Ludzka $a.Pelny
    }
  }
  return Alarm "koszt-$($a.Temat)" $tytul $pelne $waga $porada
}

# Zolte INFORMACJE z rachunku (dzis: nadrabianie zaleglosci). Osobno od alarmow,
# bo alarmy ida takze na dymek - a informacja "to bylo jednorazowe" wyskakujaca
# w zasobniku jak ostrzezenie bylaby dokladnie tym, na co uzytkownik sie
# skarzyl 24.09.2026. W oknie stoja razem z alarmami, na zoltym tle.
function Zbierz-Informacje($rachunek) {
  $lista = @()
  if (-not $rachunek) { return ,$lista }
  $ocena = Ocena-Nauki $rachunek
  foreach ($a in (Alarmy-Rachunku $rachunek)) {
    if ($a.Waga -ne "info") { continue }
    $lista += Alarm-Z-Rachunku $a $ocena
  }
  return ,$lista
}

# STATYSTYKA NAUKI DO OKNA: 30 dni, jeden element na dzien kalendarza (takze
# dni bez nauki - wykres ma pokazac przerwe, a nie ja zwinac). Liczby i sumy
# pochodza z koszt-pamieci.ps1 -Dane, ktory czyta dziennik przebiegow
# (.koszt-historia.tsv) i podsumowanie (.koszt-podsumowanie.txt). Tu tylko
# rozkladamy je na dni i ubieramy w zdania.
#
# Malo danych to NIE jest pusty wykres bez slowa: Uwaga mowi wprost, ze
# statystyka dopiero sie zbiera i skad sa liczby.
function Statystyka-Okna($rachunek) {
  $s = [pscustomobject]@{
    Dni = @(); DniZDanymi = 0; OknoDni = 30; Zrodlo = ""; Powod = ""
    Suma7 = $null; Suma30 = $null; SumyZ = ""; Srednia = $null; SredniaDni = 0
    Typowy = $null; TypowychDni = 0; Prog = $null; Uwaga = ""
  }
  if ((-not $rachunek) -or (-not $rachunek.Klucze) -or ($rachunek.Klucze.Count -eq 0)) {
    $s.Powod = "nie udało się policzyć rachunku"
    if ($rachunek -and $rachunek.Powod) { $s.Powod = $rachunek.Powod }
    $s.Uwaga = "Statystyki nie ma, bo nie udało się policzyć rachunku. Powód jest w zakładce Szczegóły."
    return $s
  }
  $k = $rachunek.Klucze
  $okno = Liczba-Z-Klucza $k "stat.okno_dni"
  if (($null -ne $okno) -and ($okno -gt 0)) { $s.OknoDni = [int]$okno }
  $s.Zrodlo      = Tekst-Z-Klucza  $k "stat.zrodlo"
  $s.Powod       = Tekst-Z-Klucza  $k "stat.powod"
  $s.Suma7       = Liczba-Z-Klucza $k "stat.suma7"
  $s.Suma30      = Liczba-Z-Klucza $k "stat.suma30"
  $s.SumyZ       = Tekst-Z-Klucza  $k "stat.sumy_z"
  $s.Srednia     = Liczba-Z-Klucza $k "stat.srednia"
  $sd            = Liczba-Z-Klucza $k "stat.srednia_dni"
  if ($null -ne $sd) { $s.SredniaDni = [int]$sd }
  $s.Typowy      = Liczba-Z-Klucza $k "cykl.typowy_dzien"
  $td            = Liczba-Z-Klucza $k "cykl.typowych_dni"
  if ($null -ne $td) { $s.TypowychDni = [int]$td }
  $s.Prog        = Liczba-Z-Klucza $k "cykl.prog"

  $mapa = @{}
  $ile = Liczba-Z-Klucza $k "stat.dni"
  if ($null -eq $ile) { $ile = 0 }
  for ($i = 1; $i -le $ile; $i++) {
    $cz = @((Tekst-Z-Klucza $k "stat.dzien.$i") -split '\|')
    if ($cz.Count -lt 5) { continue }
    $mapa[$cz[0]] = $cz
  }
  $dzis = [datetime]::Today
  $dni = @()
  for ($i = $s.OknoDni - 1; $i -ge 0; $i--) {
    $d = $dzis.AddDays(-$i)
    $x = [pscustomobject]@{ Dzien = $d; Razem = [long]0; Zwykle = [long]0; Nadrabianie = [long]0; Nieznane = [long]0; Jest = $false }
    $klucz = $d.ToString('yyyy-MM-dd')
    if ($mapa.ContainsKey($klucz)) {
      $cz = $mapa[$klucz]
      $x.Razem       = Na-Liczbe $cz[1]
      $x.Zwykle      = Na-Liczbe $cz[2]
      $x.Nadrabianie = Na-Liczbe $cz[3]
      $x.Nieznane    = Na-Liczbe $cz[4]
      $x.Jest = $true
      $s.DniZDanymi++
    }
    $dni += $x
  }
  $s.Dni = $dni

  if ($s.DniZDanymi -eq 0) {
    if ($s.Zrodlo -eq "historia") {
      $s.Uwaga = "W ostatnich $($s.OknoDni) dniach nauka nie kosztowała nic - nie ma czego pokazać na wykresie."
    } else {
      $s.Uwaga = "Statystyka dopiero się zbiera: nie ma jeszcze historii kosztów nauki. Pierwszy słupek pojawi się po najbliższej nauce z rozmów."
    }
  } elseif ($s.Zrodlo -eq "plik-dnia") {
    $s.Uwaga = ("Historii przebiegów jeszcze nie ma - pokazuję tylko ostatni pomiar ($($s.DniZDanymi) " +
                "$(Odmiana $s.DniZDanymi 'dzień' 'dni' 'dni')). Statystyka rośnie z każdym dniem nauki.")
  } elseif ($s.DniZDanymi -lt 7) {
    $s.Uwaga = ("Statystyka dopiero się zbiera: $($s.DniZDanymi) $(Odmiana $s.DniZDanymi 'dzień' 'dni' 'dni') z danymi. " +
                "Rośnie z każdym dniem nauki.")
  }
  return $s
}

function Na-Liczbe($t) {
  $v = "$t".Trim()
  if ($v -match '^\d+$') { return [long]$v }
  return [long]0
}

# ZMIANY W PAMIECI Z OSTATNIEJ NAUKI. Pisze je modul pamieci (lore\lore\verify.py,
# report_lines) do ~\.claude\wiedza\.wiedza-stan.txt:
#   data: RRRR-MM-DD                     dzien przebiegu
#   meldunek: bez zmian                  gdy nic sie nie zmienilo - JEDNA linia
#   meldunek: zmienilem 1, uspilem 0, obudzilem 0, awansowalem 1 - cofniecie: ...
#   meldunek: UWAGA: 12 zmian, pokazuje 10 - ...; zmienilem ...   (lista przycieta)
#   meldunek_1: Z-260924-1 zmienilem: „stare” -> „nowe”
#   meldunek_2: A-260924-2 awansowalem: „fakt”
# Tu tylko czytamy - licznik bierzemy z naglowka, bo lista bywa przycieta.
#
# Trzy stany i kazdy mowi co innego, bo "nie wiem" to nie "zero":
#   Wiadomo = $false  -> nie ma pliku albo nie ma w nim meldunku; Powod mowi dlaczego
#   Ile = 0           -> modul pamieci sam napisal "bez zmian"
#   Ile > 0           -> Zmiany z identyfikatorami, po ktorych sie cofa
function Stan-Zmian-Pamieci {
  $z = [pscustomobject]@{
    Wiadomo  = $false
    Dzien    = $null       # dzien przebiegu nauki, z klucza "data"
    Ile      = $null
    Zmiany   = @()         # pscustomobject: Id, Tresc (surowa linia meldunku)
    Naglowek = ""          # surowy naglowek meldunku - do szczegolow, z komenda cofania
    Powod    = ""
    Plik     = (Join-Path $script:NadzWiedza ".wiedza-stan.txt")
  }
  if (-not (Test-Path $z.Plik)) {
    $z.Powod = "nauka nie zapisała jeszcze podsumowania na tym komputerze"
    return $z
  }
  $k = Czytaj-Klucze $z.Plik
  $z.Dzien = Data-Lub-Nic $k["data"]
  if (-not $k.Contains("meldunek")) {
    $z.Powod = "ostatnie podsumowanie nauki nie ma listy zmian (zapisała je starsza wersja)"
    return $z
  }
  $z.Naglowek = "$($k['meldunek'])"
  if ($z.Naglowek -match '^\s*bez zmian\s*$') {
    $z.Wiadomo = $true
    $z.Ile = 0
    return $z
  }

  # Linie meldunek_N po numerze, nie po kolejnosci w pliku - "meldunek_10"
  # alfabetycznie stoi przed "meldunek_2".
  $numery = @()
  foreach ($klucz in @($k.Keys)) {
    $m = [regex]::Match($klucz, '^meldunek_(\d+)$')
    if ($m.Success) { $numery += [int]$m.Groups[1].Value }
  }
  foreach ($n in @($numery | Sort-Object)) {
    $tresc = "$($k["meldunek_$n"])"
    $id = ""
    $m = [regex]::Match($tresc, '^\s*([A-Z]-\d{6}-\d+)\b')
    if ($m.Success) { $id = $m.Groups[1].Value }
    $z.Zmiany += [pscustomobject]@{ Id = $id; Tresc = $tresc.Trim() }
  }

  $m = [regex]::Match($z.Naglowek, '^\s*UWAGA:\s*(\d+)\s+zmian')
  $s = [regex]::Match($z.Naglowek, 'zmienilem\s+(\d+),\s*uspilem\s+(\d+),\s*obudzilem\s+(\d+),\s*awansowalem\s+(\d+)')
  if ($m.Success) {
    $z.Ile = [int]$m.Groups[1].Value
  } elseif ($s.Success) {
    $z.Ile = [int]$s.Groups[1].Value + [int]$s.Groups[2].Value + [int]$s.Groups[3].Value + [int]$s.Groups[4].Value
  } elseif ($z.Zmiany.Count -gt 0) {
    $z.Ile = $z.Zmiany.Count
  } else {
    $z.Powod = "meldunek nauki jest nieczytelny: $($z.Naglowek)"
    return $z
  }
  $z.Wiadomo = $true
  return $z
}

# Linia meldunku po ludzku: slowa z ogonkami i strzalka zamiast "->".
# Modul pamieci pisze bez ogonkow, bo to samo idzie do dziennika i do konsoli.
function Zmiana-Ludzko([string]$tresc) {
  $t = $tresc
  $t = $t -replace '^(\s*[A-Z]-\d{6}-\d+\s+)zmienilem:',   '$1zmieniłem:'
  $t = $t -replace '^(\s*[A-Z]-\d{6}-\d+\s+)uspilem:',     '$1uśpiłem:'
  $t = $t -replace '^(\s*[A-Z]-\d{6}-\d+\s+)obudzilem:',   '$1obudziłem:'
  $t = $t -replace '^(\s*[A-Z]-\d{6}-\d+\s+)awansowalem:', '$1przeniosłem do stałej pamięci:'
  $t = $t -replace '\s->\s', ' → '
  return $t
}

# To, co widac w sekcji stanu: jedna linia na wierzchu, pod nia (w oknie
# schowane pod "pokaz") linie zmian i JEDNO zdanie, jak cofnac - dla czlowieka,
# nie dla programisty. Cofanie idzie przez rozmowe z Claude'em (lore.verify
# --cofnij), przycisku "Cofnij" w oknie nie ma i nie ma byc: zmiana pamieci
# jednym kliknieciem bez potwierdzenia to ryzyko.
function Opis-Zmian-Pamieci($z) {
  $o = [pscustomobject]@{ Linia = ""; Zmiany = @(); Porada = ""; Uwaga = $false }
  if (-not $z) {
    $o.Linia = "Pamięć: nie wiem, co się w niej zmieniło - nie udało się tego odczytać."
    $o.Uwaga = $true
    return $o
  }
  $kiedy = "dziś"
  if ($z.Dzien -and ($z.Dzien.Date -ne [datetime]::Now.Date)) {
    $kiedy = "przy ostatniej nauce ($(Dzien-Ludzko $z.Dzien))"
  }
  if (-not $z.Wiadomo) {
    $o.Linia = "Pamięć ${kiedy}: nie wiem, co się zmieniło - $($z.Powod)."
    $o.Uwaga = $true
    return $o
  }
  if ($z.Ile -le 0) {
    $o.Linia = "Pamięć ${kiedy}: bez zmian."
    return $o
  }
  $o.Linia = "Pamięć ${kiedy}: $($z.Ile) $(Odmiana ([int]$z.Ile) 'zmiana' 'zmiany' 'zmian')."
  foreach ($x in $z.Zmiany) { $o.Zmiany += (Zmiana-Ludzko $x.Tresc) }
  if ($z.Zmiany.Count -lt $z.Ile) {
    $o.Zmiany += "... i jeszcze $($z.Ile - $z.Zmiany.Count) - pełna lista jest w historii zmian pamięci."
  }
  $przyklad = $null
  foreach ($x in $z.Zmiany) { if ($x.Id) { $przyklad = $x.Id; break } }
  if ($przyklad) {
    $o.Porada = "Coś się nie zgadza? Powiedz Claude'owi: cofnij zmianę $przyklad"
  } else {
    $o.Porada = "Coś się nie zgadza? Powiedz Claude'owi: cofnij dzisiejsze zmiany w pamięci"
  }
  return $o
}

# PRZELICZANIE ARCHIWUM (wymiana modelu wyszukiwania, ~2 h). Format pliku postepu
# NIE JEST JESZCZE USTALONY - pisze go inny kawalek narzedzia. Dlatego:
#   - szukamy pliku po wzorcu nazwy w ~\.claude i ~\.lore (bez rekurencji
#     w glab projects\, bo tam lezy ponad gigabajt transkryptow),
#   - gdy go nie ma: Plik = $null i okno NIC nie pokazuje,
#   - gdy jest: Plik ustawiony, ale Zrobione/Wszystkie zostaja puste, dopoki ktos
#     nie podepnie odczytu formatu TUTAJ. Zgadniety format pokazalby liczby,
#     ktorych nikt nie zmierzyl. Sciezka idzie do szczegolow, zeby nie byla cisza.
$WZORCE_PRZELICZANIA = @("*przelicz*", "*migracj*", "*reindex*")

function Postep-Przeliczania {
  $p = [pscustomobject]@{ Plik = $null; Zrobione = $null; Wszystkie = $null; Powod = "" }
  $katalogi = @(
    (Join-Path $script:NadzDom ".claude"),
    (Join-Path $script:NadzDom ".claude\wiedza"),
    (Join-Path $script:NadzDom ".lore")
  )
  # Plik postepu przeliczania archiwum na nowy model (lore\lore\migrate.py):
  # ~\.claude\lore.migration.json - pola state, done, total, eta_min.
  # Pokazujemy tylko gdy przeliczanie trwa; po skonczeniu linia znika sama.
  $mig = Join-Path $script:NadzDom ".claude\lore.migration.json"
  if (Test-Path $mig) {
    $p.Plik = $mig
    try {
      $j = [System.IO.File]::ReadAllText($mig, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
      if ($j.state -eq "running" -and $null -ne $j.done -and $null -ne $j.total) {
        $p.Zrobione = [int]$j.done
        $p.Wszystkie = [int]$j.total
        if ($null -ne $j.eta_min) { $p.Powod = "zostalo ok. $([int]$j.eta_min) min" }
      } else {
        $p.Powod = "przeliczanie nie trwa (stan: $($j.state))"
      }
    } catch {
      $p.Powod = "nie umiem odczytac pliku postepu: $($_.Exception.Message)"
    }
    return $p
  }
  foreach ($kat in $katalogi) {
    if (-not (Test-Path $kat)) { continue }
    foreach ($wz in $WZORCE_PRZELICZANIA) {
      $pliki = @(Get-ChildItem -Path $kat -Filter $wz -File -Force -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending)
      if ($pliki.Count -gt 0) {
        $p.Plik = $pliki[0].FullName
        # TU PODPIAC odczyt formatu, gdy bedzie znany: ustawic $p.Zrobione i $p.Wszystkie.
        $p.Powod = "format pliku postępu nie jest jeszcze podpięty do okna"
        return $p
      }
    }
  }
  return $p
}

# STAN JEDNYM RZUTEM OKA - kilka krotkich zdan zamiast akapitow. Zadnych nazw
# plikow i zadnych sciezek: te sa pod [Szczegoly] i tam jest ich miejsce.
function Linie-Stanu($wersja, $cykl, $przeliczanie) {
  $linie = @()

  # Jedna linia i tylko wtedy, gdy postep naprawde odczytalismy - patrz
  # Postep-Przeliczania. Bez pliku albo bez podpietego formatu: nic.
  if ($przeliczanie -and ($null -ne $przeliczanie.Zrobione) -and ($null -ne $przeliczanie.Wszystkie)) {
    $linie += "Przeliczam archiwum: $(Liczba-Ludzka $przeliczanie.Zrobione) z $(Liczba-Ludzka $przeliczanie.Wszystkie)."
  }

  if ($cykl) {
    if ($cykl.Pracuje) {
      $linie += "Nauka z rozmów: właśnie trwa."
    } elseif ($cykl.Data) {
      $linie += "Nauka z rozmów: ostatnio $(Kiedy-Ludzko $cykl.Data)."
    } else {
      $linie += "Nauka z rozmów: jeszcze ani razu na tym komputerze."
    }

    if ($null -ne $cykl.Kawalki) {
      if ($cykl.Kawalki -le 0) {
        $linie += "Do przeczytania: nic nie czeka, wszystkie rozmowy są przerobione."
      } else {
        $linie += "Do przeczytania: $(Liczba-Ludzka $cykl.Kawalki) $(Odmiana ([int]$cykl.Kawalki) 'fragment rozmów' 'fragmenty rozmów' 'fragmentów rozmów')."
      }
    } elseif ($null -ne $cykl.Zaleglosc) {
      $linie += "Do przeczytania: na żywo nie policzone; przy ostatnim podsumowaniu zostawało $(Liczba-Ludzka $cykl.Zaleglosc) $(Odmiana ([int]$cykl.Zaleglosc) 'porcja' 'porcje' 'porcji')."
    } else {
      $linie += "Do przeczytania: nie wiem, nie dało się sprawdzić kolejki."
    }
  } else {
    $linie += "Nauka z rozmów: nie wiem, nie udało się odczytać jej stanu."
  }

  if ($wersja) {
    $w = "nieznana"
    if ($wersja.Lokalna) { $w = $wersja.Lokalna }
    if ($null -eq $wersja.Nowsza) {
      $powod = $wersja.Powod
      if (-not $powod) { $powod = "nie ustaliłem powodu - to samo w sobie jest usterką" }
      $linie += "Wersja narzędzia: $w. Czy jest coś nowszego - nie wiem ($powod)."
    } elseif ($wersja.Nowsza -le 0) {
      $linie += "Wersja narzędzia: $w, nic nowszego nie czeka."
    } else {
      $linie += "Wersja narzędzia: $w. Czeka $($wersja.Nowsza) $(Odmiana ([int]$wersja.Nowsza) 'nowsza zmiana' 'nowsze zmiany' 'nowszych zmian') - pobierze je przycisk na dole."
    }
  } else {
    $linie += "Wersja narzędzia: nie wiem, nie udało się jej odczytać."
  }

  return ,$linie
}

# Czerwony czy zolty. PROG Z UZASADNIENIEM, nie kolor z powietrza:
#   CZERWONY - cos jest zepsute albo kosztuje i jest konkretna rzecz do zrobienia
#              (nauka stoi, tekst jest ucinany, rachunek nad progiem, straznik sie wywrocil);
#   ZOLTY    - czegos NIE WIEMY i trzeba to sprawdzic, ale nic sie jeszcze nie pali;
#   ZOLTY "info" - wiemy, co sie stalo, i nic nie trzeba robic (np. nauka nadrabiala
#              zaleglosc). Waga niesiona przez sam alarm wygrywa z tym tematem.
# Wszystko inne zostaje neutralne. Tecza uczy ignorowania kolorow.
function Waga-Alarmu([string]$temat) {
  if ($temat -eq "rachunek") { return "uwaga" }
  return "pilne"
}

# Porada bez zargonu: zdania z komendami i sciezkami zostaja w [Szczegoly],
# na wierzchu stoi to, co uzytkownik moze zrobic sam. NIC NIE GINIE - pelna tresc
# alarmu jest zawsze w szczegolach, a gdyby po odsianiu nie zostalo ani jedno
# zdanie, oddajemy oryginal. Lepiej zargon niz pusta ramka.
function Porada-Ludzka([string]$tresc) {
  if (-not $tresc) { return "" }
  $ludzkie = @()
  $odsiane = 0
  foreach ($z in [regex]::Split($tresc, '(?<=\.)\s+')) {
    $t = "$z".Trim()
    if (-not $t) { continue }
    if ($t -match 'powershell\s+-ExecutionPolicy') { $odsiane++; continue }
    if ($t -match '\.ps1|\.log|\.db|\.txt|\.json|\\\.claude\\|\\narzedzia\\') { $odsiane++; continue }
    $ludzkie += $t
  }
  if ($ludzkie.Count -eq 0) { return $tresc }
  # Odsianie ma byc WIDOCZNE. Inaczej uzytkownik nie wie, ze jest ciag dalszy,
  # i nigdy go nie otworzy - a to jest dokladnie cicha strata tresci.
  if ($odsiane -gt 0) { $ludzkie += "Dokładna ścieżka i komenda są w szczegółach." }
  return ($ludzkie -join " ")
}

# Gorny limit porcji na JEDNO podejscie czytamy z pliku, ktory go USTALA.
# Wpisany tutaj na sztywno zaczalby klamac przy pierwszej zmianie cyklu - ta sama
# zasada, co przy sufitach w narzedzia\koszt-pamieci.ps1. $null znaczy
# "nie odczytalem" i wolajacy MA to powiedziec, a nie zgadnac.
function Max-Nadrabiania {
  $raw = Czytaj-Tekst (Join-Path $script:NadzZrodlo "narzedzia\cykl-dzienny.ps1")
  if (-not $raw) { return $null }
  $m = [regex]::Match($raw, '(?m)^\$MaxNadrabiania\s*=\s*(\d+)')
  if (-not $m.Success) { return $null }
  return [int]$m.Groups[1].Value
}

# SZACUNEK KOSZTU PRZED KLIKNIECIEM. Powstal dlatego, ze przycisk "Uruchom cykl"
# wydal 24.09.2026 jednym kliknieciem 312 609 tokenow, nie uprzedzajac o niczym.
#
# Skad ta liczba: (ile porcji pojdzie w tym podejsciu) x (ile kosztowalo jedno
# wyslanie przy POPRZEDNIM przebiegu). Oba czynniki sa ZMIERZONE - pierwszy liczy
# narzedzia\wyciagnij-fakty.ps1 -Kolejka (przebieg probny, bez wolania modelu,
# ~0,4 s), drugi stoi w .koszt-cyklu.txt, zapisany przez samo wylawianie. Zadnej
# stalej "tyle to mniej wiecej kosztuje" tu nie ma i nie ma byc.
#
# Gdy ktoregos czynnika brakuje, Tokeny zostaja puste, a w Powod stoi dlaczego.
# Okno mowi wtedy wprost "NIE WIEM, ile to bedzie kosztowac" i dalej pyta o zgode
# z podswietlonym "Nie" - koszt zgadniety bylby gorszy niz zaden.
function Szacunek-Cyklu($cykl) {
  $s = [pscustomobject]@{
    Tokeny   = $null      # szacunek calego podejscia
    NaPorcje = $null      # ile kosztowalo jedno wyslanie ostatnim razem
    Porcje   = $null      # ile porcji pojdzie TERAZ
    WKolejce = $null      # ile porcji czeka w sumie
    Kawalki  = $null
    Podstawa = @()        # zdania mowiace, z czego ta liczba wyszla
    Powod    = ""         # dlaczego nie umiem podac liczby
  }
  if (-not $cykl) {
    $s.Powod = "nie mam danych o kolejce ani o poprzednim przebiegu"
    return $s
  }
  $s.Kawalki  = $cykl.Kawalki
  $s.WKolejce = $cykl.Przebiegi

  if ($null -eq $cykl.Przebiegi) {
    $s.Powod = "nie dało się sprawdzić, ile rozmów czeka w kolejce"
  } elseif ($cykl.Przebiegi -le 0) {
    $s.Porcje = 0
    $s.Tokeny = 0
    $s.Podstawa += "Kolejka jest pusta - nie ma zaległych rozmów do przeczytania."
    return $s
  } else {
    $max = Max-Nadrabiania
    $s.Porcje = $cykl.Przebiegi
    $ile = "nieznaną liczbę fragmentów"
    if ($null -ne $cykl.Kawalki) {
      $ile = "$(Liczba-Ludzka $cykl.Kawalki) $(Odmiana ([int]$cykl.Kawalki) 'fragment' 'fragmenty' 'fragmentów')"
    }
    $s.Podstawa += "Czeka $ile rozmów, czyli $($cykl.Przebiegi) $(Odmiana ([int]$cykl.Przebiegi) 'porcja' 'porcje' 'porcji') do wysłania."
    if ($null -eq $max) {
      $s.Podstawa += "Nie odczytałem, ile porcji bierze jedno podejście - liczę tak, jakby poszły wszystkie naraz."
    } elseif ($cykl.Przebiegi -gt $max) {
      $s.Porcje = $max
      $s.Podstawa += "Jedno podejście bierze najwyżej $max $(Odmiana ([int]$max) 'porcję' 'porcje' 'porcji') - reszta poczeka do następnego razu."
    }
  }

  if (($null -ne $cykl.Koszt) -and ($null -ne $cykl.KosztWywolan) -and ($cykl.KosztWywolan -gt 0)) {
    $s.NaPorcje = [long][math]::Round([double]$cykl.Koszt / [double]$cykl.KosztWywolan)
    $kiedy = "ostatnim razem"
    if ($cykl.KosztData) { $kiedy = $cykl.KosztData.ToString('dd.MM') }
    $s.Podstawa += ("Jedno wysłanie kosztowało ostatnio ~$(Liczba-Ludzka $s.NaPorcje) tokenów " +
                    "(${kiedy}: $(Liczba-Ludzka $cykl.Koszt) tokenów na $($cykl.KosztWywolan) $(Odmiana ([int]$cykl.KosztWywolan) 'wywołanie' 'wywołania' 'wywołań')).")
  } elseif (-not $s.Powod) {
    $s.Powod = "nie ma pomiaru poprzedniego przebiegu, więc nie mam po czym szacować"
  }

  if (($null -ne $s.Porcje) -and ($null -ne $s.NaPorcje)) {
    $s.Tokeny = [long]($s.Porcje * $s.NaPorcje)
  }
  return $s
}
