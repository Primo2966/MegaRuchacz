# zasobnik\nadzorca\stan-podstawy.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Podstawy, z ktorych korzysta caly nadzorca: pliki
# "klucz: wartosc" (Czytaj-Klucze, Zapisz-Klucze, Dopisz-Klucze), dziennik
# i wywrotki (Notuj, Zanotuj-Wywrotke, Zapisz-Obecnosc, Odbierz-Wywrotki), liczby
# i daty (Liczba-Ludzka, Data-Lub-Nic) i wolanie innych programow: git z limitem
# (Wolaj-Gita), skrypt w osobnym procesie (Wolaj-Skrypt), start w tle bez okna
# (Odpal-W-Tle).
# Skad wolane: z kazdego modulu stanu i okna oraz z nadzorca.ps1. Wczytuje go
# stan-nadzorcy.ps1 kropka jako pierwszy - tu sa same definicje.

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

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["podstawy"] = $true
