<#
Straznik serwera "Wiedza firmy" (Pakowanie2) - uruchamiany przez zadanie
Harmonogramu WiedzaFirmyHttp (S4U, przy starcie systemu).

Petla:
  1. co -CoIleAktualizacjaMin (i zawsze przed pierwszym startem) samoaktualizacja
     (aktualizacja.py); kod 10 = nowy kod -> serwer restartowany,
  2. zamyka stary python trzymajacy SWOJ port (np. po Stop-ScheduledTask, ktory
     zabija tylko straznika - python serwera zostaje i dalej slucha),
  3. uruchamia serwer (uruchom.py <modul>), wyjscie do stan\serwer.log,
  4. dopoki serwer zyje: co -CoIleSprawdzacS znacznik "bylem tu" stan\straznik.json
     (czas, pid, czy port slucha, wynik aktualizacji i kopii); raz dziennie po
     -GodzinaKopii kopia zapasowa (kopia.py), przy bledzie ponowienie co godzine,
  5. serwer skonczyl sie (takze kodem 0) -> wpis w dzienniku i start po 5 s.
Dziennik: stan\straznik.log (rotacja powyzej 10 MB). Nieswiezy straznik.json
sam w sobie jest alarmem (stan-serwera-wiedzy.ps1).

Zmienne WIEDZA_FIRMY_* brakujace w srodowisku (zadanie S4U nie wczytuje zmiennych
uzytkownika) dociaga z HKCU\Environment.
#>
param(
  [string]$Kat = 'C:\dev\wiedza-firmy',
  [int]$Port = 0,
  [string]$Python = '',
  [string]$Dane = '',
  [int]$CoIleSprawdzacS = 60,
  [int]$CoIleAktualizacjaMin = 60,
  [int]$GodzinaKopii = 3,
  [int]$MaksStartow = 0,          # 0 = bez konca; testy: zakoncz po N startach serwera
  [switch]$BezAktualizacji,
  [switch]$BezKopii,
  [string[]]$SerwerArgumenty = @()  # testy: argumenty pythona zamiast uruchom.py <modul>
)
$ErrorActionPreference = 'Continue'

$konf = $null
$plikKonf = Join-Path $Kat 'serwer-wiedzy.json'
if (Test-Path -LiteralPath $plikKonf) {
  try { $konf = Get-Content -LiteralPath $plikKonf -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { $konf = $null; $bladKonf = $_.Exception.Message }
}
if ($Port -le 0) { $Port = if ($konf -and $konf.port) { [int]$konf.port } else { 8766 } }
if (-not $Python) { $Python = Join-Path $Kat 'venv\Scripts\python.exe' }
if (-not $Dane) { $Dane = if ($konf -and $konf.dane) { [string]$konf.dane } else { Join-Path $env:APPDATA 'wiedza-firmy' } }
$Modul = if ($konf -and $konf.modul) { [string]$konf.modul } else { 'wiedza_firmy.serwer' }
$ArgModulu = if ($konf -and $konf.argumenty) { @($konf.argumenty | ForEach-Object { "$_" }) } else { @('--host', '0.0.0.0', '--port', "$Port") }
$Narzedzia = Join-Path $Kat 'narzedzia'
$Stan = Join-Path $Kat 'stan'
$LogStraznika = Join-Path $Stan 'straznik.log'
$LogSerwera = Join-Path $Stan 'serwer.log'
$Znacznik = Join-Path $Stan 'straznik.json'
New-Item -ItemType Directory -Force -Path $Stan | Out-Null

function Rotuj([string]$plik) {
  if ((Test-Path -LiteralPath $plik) -and ((Get-Item -LiteralPath $plik).Length -gt 10MB)) {
    Move-Item -LiteralPath $plik -Destination "$plik.1" -Force
  }
}
function Log([string]$t) {
  Rotuj $LogStraznika
  Add-Content -LiteralPath $LogStraznika -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $t) -Encoding UTF8
}
function Czytaj-Json([string]$plik) {
  if (-not (Test-Path -LiteralPath $plik)) { return $null }
  try { return (Get-Content -LiteralPath $plik -Raw -Encoding UTF8 | ConvertFrom-Json) }
  catch { Log "UWAGA: nieczytelny $plik : $($_.Exception.Message)"; return $null }
}
function Pid-Na-Porcie {
  @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique)
}

$script:serwer = $null
$script:serwerStart = $null
$script:startow = 0
$script:faza = 'start'
function Zapisz-Znacznik([string]$faza) {
  $script:faza = $faza
  $akt = Czytaj-Json (Join-Path $Stan 'aktualizacja.json')
  $kop = Czytaj-Json (Join-Path $Stan 'kopia.json')
  $dane = [ordered]@{
    czas            = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    faza            = $faza
    pid_straznika   = $PID
    pid_serwera     = $(if ($script:serwer) { $script:serwer.Id } else { $null })
    serwer_od       = $(if ($script:serwerStart) { $script:serwerStart.ToString('yyyy-MM-ddTHH:mm:sszzz') } else { $null })
    startow         = $script:startow
    port            = $Port
    port_slucha     = ((Pid-Na-Porcie).Count -gt 0)
    co_ile_s        = $CoIleSprawdzacS
    aktualizacja    = $(if ($akt) { "$($akt.status): $($akt.przyczyna)" } else { 'brak przebiegu' })
    kopia           = $(if ($kop) { "$($kop.status): $(if ($kop.przyczyna) { $kop.przyczyna } else { $kop.katalog })" } else { 'brak przebiegu' })
  }
  $tmp = "$Znacznik.tmp"
  try {
    [IO.File]::WriteAllText($tmp, ($dane | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Znacznik -Force
  } catch { Log "BLAD zapisu znacznika: $($_.Exception.Message)" }
}

function Cytuj([string]$a) { if ($a -match '[\s"]' -or $a -eq '') { '"' + ($a -replace '"', '\"') + '"' } else { $a } }

# Proces w tle bez okna; wyjscie dopisywane do pliku przez cmd (>>).
function Start-Ukryty([string[]]$argumenty, [string]$log) {
  $linia = ((@($Python) + $argumenty) | ForEach-Object { Cytuj $_ }) -join ' '
  $p = Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList "/d /s /c `"$linia >> `"$log`" 2>&1`"" `
    -WindowStyle Hidden -PassThru
  $null = $p.Handle   # bez tego PowerShell 5.1 gubi ExitCode po zakonczeniu
  return $p
}
function Zabij-Drzewo($p) {
  if ($p -and -not $p.HasExited) { & taskkill.exe /pid $p.Id /t /f 2>&1 | Out-Null }
}

# Pomocnik (aktualizacja, kopia) z limitem czasu; w trakcie znacznik dalej swiezy.
function Uruchom-Pomocnika([string]$nazwa, [string[]]$argumenty, [int]$limitMin) {
  $log = Join-Path $Stan "$nazwa-wyjscie.log"
  Rotuj $log
  $p = Start-Ukryty $argumenty $log
  $koniec = (Get-Date).AddMinutes($limitMin)
  while (-not $p.WaitForExit([Math]::Max(1, $CoIleSprawdzacS) * 1000)) {
    Zapisz-Znacznik "$nazwa w toku"
    if ((Get-Date) -gt $koniec) {
      Zabij-Drzewo $p
      Log "BLAD: $nazwa przekroczyla limit $limitMin min - przerwana"
      return -1
    }
  }
  $p.WaitForExit()
  return $p.ExitCode
}

function Aktualizuj {
  $kod = Uruchom-Pomocnika 'aktualizacja' @((Join-Path $Narzedzia 'aktualizacja.py'), '--kat', $Kat, '--dane', $Dane) 25
  $akt = Czytaj-Json (Join-Path $Stan 'aktualizacja.json')
  $opis = if ($akt) { "$($akt.status): $($akt.przyczyna)" } else { 'brak stanu aktualizacji' }
  switch ($kod) {
    0 { }
    10 { Log "aktualizacja: nowy kod ($opis)" }
    3 { Log 'aktualizacja: zamek zajety - inny przebieg' }
    default { Log "BLAD aktualizacji (kod $kod): $opis" }
  }
  return $kod
}

function Kopia-Potrzebna {
  if ($BezKopii) { return $false }
  $dzis = Get-Date -Format 'yyyy-MM-dd'
  $kop = Czytaj-Json (Join-Path $Stan 'kopia.json')
  if ($kop -and $kop.ostatni_sukces -and ("$($kop.ostatni_sukces)".StartsWith($dzis))) { return $false }
  if ((Get-Date).Hour -lt $GodzinaKopii) { return $false }
  return (((Get-Date) - $script:ostKopia).TotalMinutes -ge 60)
}
function Kopia {
  $script:ostKopia = Get-Date
  $kod = Uruchom-Pomocnika 'kopia' @((Join-Path $Narzedzia 'kopia.py'), '--kat', $Kat, '--dane', $Dane) 30
  $kop = Czytaj-Json (Join-Path $Stan 'kopia.json')
  $opis = if ($kop) { "$($kop.status): $(if ($kop.przyczyna) { $kop.przyczyna } else { $kop.katalog })" } else { 'brak stanu kopii' }
  if ($kod -eq 0) { Log "kopia zapasowa: $opis" } else { Log "BLAD kopii zapasowej (kod $kod): $opis" }
}

function Sprzataj-Port {
  foreach ($id in (Pid-Na-Porcie)) {
    $proc = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($proc -and $proc.ProcessName -like 'python*') {
      Log "port $Port zajety przez stary python, pid $id - zamykam"
      & taskkill.exe /pid $id /t /f 2>&1 | Out-Null
      Start-Sleep -Seconds 2
    } elseif ($proc) {
      Log "BLAD: port $Port zajety przez $($proc.ProcessName) (pid $id) - nie ruszam, serwer nie wstanie"
    }
  }
}

function Zmienne-Z-Rejestru {
  try {
    $env0 = Get-ItemProperty -Path 'HKCU:\Environment' -ErrorAction Stop
    foreach ($w in $env0.PSObject.Properties) {
      if ($w.Name -like 'WIEDZA_FIRMY_*' -and -not [Environment]::GetEnvironmentVariable($w.Name, 'Process')) {
        [Environment]::SetEnvironmentVariable($w.Name, "$($w.Value)", 'Process')
        Log "zmienna $($w.Name) wczytana z HKCU\Environment"
      }
    }
  } catch { Log "UWAGA: HKCU\Environment nieczytelne: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------------------
Rotuj $LogStraznika
Log "straznik start: $env:USERDOMAIN\$env:USERNAME, pid $PID, port $Port, dane $Dane"
if ($bladKonf) { Log "BLAD: nieczytelny $plikKonf ($bladKonf) - wartosci domyslne" }
Zmienne-Z-Rejestru
$env:LORE_HOME = Join-Path $Kat 'lore-dane'
$env:WIEDZA_FIRMY_HOME = $Dane   # katalog danych serwera (wiedza_firmy.sciezki)
$env:WIEDZA_FIRMY_PORT = "$Port"
$env:PYTHONUNBUFFERED = '1'
$env:PYTHONIOENCODING = 'utf-8'
$ostAkt = [datetime]::MinValue
$script:ostKopia = [datetime]::MinValue

while ($true) {
  try {
    if (-not $BezAktualizacji -and ((Get-Date) - $ostAkt).TotalMinutes -ge $CoIleAktualizacjaMin) {
      $ostAkt = Get-Date
      Zapisz-Znacznik 'aktualizacja przed startem'
      $null = Aktualizuj
    }
    Sprzataj-Port
    Rotuj $LogSerwera
    $argS = if ($SerwerArgumenty.Count) { $SerwerArgumenty } else { @((Join-Path $Narzedzia 'uruchom.py'), $Modul) + $ArgModulu }
    if (-not (Test-Path -LiteralPath $Python)) { Log "BLAD: brak $Python - uruchom instalator" }
    $script:serwer = Start-Ukryty $argS $LogSerwera
    $script:serwerStart = Get-Date
    $script:startow++
    Log "start serwera, pid $($script:serwer.Id), port $Port (start nr $($script:startow))"
    while (-not $script:serwer.HasExited) {
      Zapisz-Znacznik 'serwer dziala'
      if (Kopia-Potrzebna) { Kopia; Zapisz-Znacznik 'serwer dziala' }
      if (-not $BezAktualizacji -and ((Get-Date) - $ostAkt).TotalMinutes -ge $CoIleAktualizacjaMin) {
        $ostAkt = Get-Date
        if ((Aktualizuj) -eq 10) {
          Log 'restart serwera na nowym kodzie'
          Zabij-Drzewo $script:serwer
          break
        }
      }
      $null = $script:serwer.WaitForExit([Math]::Max(1, $CoIleSprawdzacS) * 1000)
    }
    $script:serwer.WaitForExit()
    Log "serwer zakonczony, kod $($script:serwer.ExitCode) - ponowny start za 5 s"
  } catch {
    Log "BLAD straznika: $($_.Exception.Message) - ponawiam za 5 s"
  }
  if ($MaksStartow -gt 0 -and $script:startow -ge $MaksStartow) { Zapisz-Znacznik 'koniec (limit startow)'; break }
  Zapisz-Znacznik 'przerwa przed restartem'
  Start-Sleep -Seconds 5
}
