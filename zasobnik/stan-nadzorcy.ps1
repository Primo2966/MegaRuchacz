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

# Jedna linia i kod wyjscia: 0 = nic nie jest ucinane i zaden prog nie przekroczony,
# 1 = jedno z dwojga. Progi siedza w koszt-pamieci.ps1 razem z uzasadnieniem -
# nadzorca ich NIE powtarza, bo drugi komplet liczb zaczalby klamac przy pierwszej
# zmianie tamtych.
function Linia-Rachunku {
  $skrypt = Join-Path $script:NadzZrodlo "narzedzia\koszt-pamieci.ps1"
  $r = Wolaj-Skrypt $skrypt @("-KatalogDomowy", ('"' + $script:NadzDom + '"'), "-Zrodlo", ('"' + $script:NadzZrodlo + '"'), "-Zwiezle", "-Zwykly") 120
  $w = [pscustomobject]@{ Linia = $null; Kod = $null; Powod = "" }
  if (-not $r.ok) {
    $w.Powod = $r.powod
    return $w
  }
  $linie = @(($r.tekst -split '\r?\n') | Where-Object { "$_".Trim() })
  if ($linie.Count -gt 0) { $w.Linia = $linie[0].Trim() }
  $w.Kod = $r.kod
  if (-not $w.Linia) { $w.Powod = "koszt-pamieci.ps1 -Zwiezle nic nie wypisal (kod $($r.kod))" }
  return $w
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
function Alarm([string]$temat, [string]$tytul, [string]$tresc) {
  return [pscustomobject]@{ Temat = $temat; Tytul = $tytul; Tresc = $tresc }
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

  # 2. i 3. Ucinanie i prog kosztu - jedno i drugie widac po kodzie 1
  # z koszt-pamieci.ps1 -Zwiezle; rozroznia je slowo w tej samej linii.
  if ($rachunek.Kod -eq 1 -and $rachunek.Linia) {
    if ($rachunek.Linia -match 'UCINANE') {
      $alarmy += Alarm "ucinane" "MegaRuchacz: część tekstu jest ucinana po cichu" (
        "Skrócony tekst nie dochodzi do modelu, a nikt o tym nie mówi. " +
        "Kliknij ikonę MegaRuchacza i rozwiń [Szczegóły] - tam widać, która pozycja nie mieści się w limicie. " +
        "Najczęściej pomaga skrócenie sekcji 'Co wiem' w Twoim pliku z wiedzą. " +
        "Rachunek mowi: $($rachunek.Linia). " +
        "Plik do skrocenia: $($script:NadzDom)\.claude\CLAUDE.md")
    } else {
      $alarmy += Alarm "koszt" "MegaRuchacz: pamięć kosztuje więcej, niż powinna" (
        "Kliknij ikonę MegaRuchacza i rozwiń [Szczegóły] - tam widać, która pozycja urosła. " +
        "Rachunek mowi: $($rachunek.Linia). " +
        "Progi i ich uzasadnienie sa w $($script:NadzZrodlo)\narzedzia\koszt-pamieci.ps1")
    }
  } elseif ($rachunek.Powod) {
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
function Trzy-Liczby($rachunek, $cykl) {
  $naWiadomosc = [pscustomobject]@{
    Naglowek = "Każda Twoja wiadomość kosztuje"
    Liczba   = $null
    Opis     = "Przypomnienie zasad doklejane do każdego Twojego zdania."
    Ogon     = ""
    Powod    = ""
  }
  $naSesje = [pscustomobject]@{
    Naglowek = "Otwarcie nowej sesji"
    Liczba   = $null
    Opis     = "Wiedza o Tobie i o firmie, wczytywana raz na początku rozmowy."
    Ogon     = ""
    Powod    = ""
  }
  $naDobe = [pscustomobject]@{
    Naglowek = "Raz dziennie, nauka z rozmów"
    Liczba   = $null
    Opis     = "Jedyne miejsce, w którym naprawdę płacisz za wywołanie modelu - reszta to doklejony tekst."
    Ogon     = ""
    Powod    = ""
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
  } else {
    $naDobe.Powod = "nauka z rozmów nie policzyła jeszcze ani razu swojego kosztu"
    if ($cykl) {
      foreach ($p in $cykl.Powody) { if ("$p" -match 'koszt') { $naDobe.Powod = $p } }
    }
  }

  return ,@($naWiadomosc, $naSesje, $naDobe)
}

# STAN JEDNYM RZUTEM OKA - kilka krotkich zdan zamiast akapitow. Zadnych nazw
# plikow i zadnych sciezek: te sa pod [Szczegoly] i tam jest ich miejsce.
function Linie-Stanu($wersja, $cykl) {
  $linie = @()

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
#   ZOLTY    - czegos NIE WIEMY i trzeba to sprawdzic, ale nic sie jeszcze nie pali.
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
                    "($kiedy: $(Liczba-Ludzka $cykl.Koszt) tokenów na $($cykl.KosztWywolan) $(Odmiana ([int]$cykl.KosztWywolan) 'wywołanie' 'wywołania' 'wywołań')).")
  } elseif (-not $s.Powod) {
    $s.Powod = "nie ma pomiaru poprzedniego przebiegu, więc nie mam po czym szacować"
  }

  if (($null -ne $s.Porcje) -and ($null -ne $s.NaPorcje)) {
    $s.Tokeny = [long]($s.Porcje * $s.NaPorcje)
  }
  return $s
}
