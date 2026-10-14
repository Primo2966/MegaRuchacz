<#
Instalator serwera "Wiedza firmy" na Pakowanie2 (Windows, Python 3.12 systemowy,
bez gita i bez uv). Wzor: instaluj-serwer-http.ps1 serwera ecommerce-helper.

Co robi (mozna uruchamiac wielokrotnie - drugi raz niczego nie psuje):
  1. katalogi <Kat>\{narzedzia,stan,kopie,lore-dane} i konfiguracja serwer-wiedzy.json,
  2. kopiuje skrypty z tego katalogu do <Kat>\narzedzia\ (straznik, aktualizacja,
     kopia, uruchom, stan, odinstalowanie),
  3. venv <Kat>\venv z Pythona systemowego (gdy go jeszcze nie ma),
  4. kod serwera: pierwsza aktualizacja (aktualizacja.py) - z GitHuba (publiczne repo
     Primo2966/MegaRuchacz, zipball main) albo z -ZrodloKodu <plik.zip>,
  5. zaleznosci z <Kat>\kod\wiedza_firmy\pyproject.toml (+ lore) pip-em do venv,
  6. sprawdzenie, ze modul serwera sie importuje,
  7. model sdadas/mmlw-retrieval-roberta-base: python -m wiedza_firmy.model - mechanizm
     przypiecia z lore (konkretny commit, suma SHA-256 kazdego pliku; inny plik = odmowa)
     plus proba zaladowania; pliki w <dane>\modele (tam szuka ich serwer),
  8. regula zapory WiedzaFirmyHttp-TCP: wejscie TCP <Port> tylko z 192.168.0.0/24,
     100.64.0.0/10 i 127.0.0.1,
  9. zadanie Harmonogramu WiedzaFirmyHttp: przy starcie systemu (30 s), biezacy
     uzytkownik jako S4U (bez hasla, dziala bez logowania), najwyzsze uprawnienia,
     restart co 1 min (999 prob), bez limitu czasu, jedna instancja; akcja =
     straznik.ps1 (petla z restartem, znacznik "bylem tu", aktualizacja, kopia),
 10. sprawdza osoby.json i (bez -BezStartu) uruchamia zadanie.

Dane (%APPDATA%\wiedza-firmy\ - baza, tematy, osoby) nie sa ruszane.

Uruchamianie (PowerShell jako administrator, na koncie, pod ktorym ma dzialac serwer):
  powershell -NoProfile -ExecutionPolicy Bypass -File instaluj-serwer-wiedzy.ps1 [-Proba]

Parametry:
  -Proba             nic nie zmienia, wypisuje plan
  -Port <n>          port serwera (domyslnie 8766; NIE 8765 - to ecommerce-helper)
  -Kat <katalog>     katalog instalacji (domyslnie C:\dev\wiedza-firmy)
  -ZrodloKodu <zip>  kod z lokalnego archiwum zamiast z GitHuba
  -Modul <nazwa>     modul serwera (domyslnie wiedza_firmy.serwer)
  -DrugiCelKopii <k> drugie miejsce kopii zapasowej (np. katalog na Dysku Google)
  -BezStartu         nie uruchamiaj zadania
  -Restartuj         zadanie juz dziala - zatrzymaj (razem z pythonem) i uruchom od nowa
  -Atrapy <plik.ps1> TYLKO TESTY: podmienia funkcje dotykajace systemu
#>
[CmdletBinding()]
param(
  [switch]$Proba,
  [int]$Port = 8766,
  [string]$Kat = 'C:\dev\wiedza-firmy',
  [string]$ZrodloKodu = '',
  [string]$Modul = 'wiedza_firmy.serwer',
  [string]$DrugiCelKopii = '',
  [string]$PythonBazowy = 'C:\Program Files\Python312\python.exe',
  [string]$Dane = '',
  [switch]$BezStartu,
  [switch]$Restartuj,
  [string]$Atrapy = ''
)
$ErrorActionPreference = 'Stop'
$NazwaZadania = 'WiedzaFirmyHttp'
$NazwaReguly = 'WiedzaFirmyHttp-TCP'
$AdresyZdalne = @('192.168.0.0/24', '100.64.0.0/10', '127.0.0.1')
$NazwaModelu = 'sdadas/mmlw-retrieval-roberta-base'
if (-not $Dane) { $Dane = Join-Path $env:APPDATA 'wiedza-firmy' }
$Narzedzia = Join-Path $Kat 'narzedzia'
$PyVenv = Join-Path $Kat 'venv\Scripts\python.exe'
$Straznik = Join-Path $Narzedzia 'straznik.ps1'
$Pliki = @('instaluj-serwer-wiedzy.ps1', 'straznik.ps1', 'aktualizacja.py', 'kopia.py', 'uruchom.py',
           'stan-serwera-wiedzy.ps1', 'odinstaluj-serwer-wiedzy.ps1', 'CZYTAJ.md')

function Krok([string]$t) { Write-Host ''; Write-Host "=== $t" -ForegroundColor Cyan }
function Ok([string]$t) { Write-Host "  [OK] $t" -ForegroundColor Green }
function Info([string]$t) { Write-Host "  $t" }
function Uwaga([string]$t) { Write-Host "  [UWAGA] $t" -ForegroundColor Yellow }
function Plan([string]$t) { Write-Host "  [proba] $t" -ForegroundColor DarkGray }
function Blad([string]$t) { Write-Host "[BLAD] $t" -ForegroundColor Red; exit 1 }

# --- operacje dotykajace systemu (testy podmieniaja je przez -Atrapy) ----------
function Czy-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Kto { return [Security.Principal.WindowsIdentity]::GetCurrent().Name }
function Python-Uruchom([string]$exe, [string[]]$argumenty) {
  $stare = $ErrorActionPreference; $ErrorActionPreference = 'Continue'  # ostrzezenia na stderr to nie blad
  try { $wy = @(& $exe @argumenty 2>&1 | ForEach-Object { "$_" }); $kod = $LASTEXITCODE }
  finally { $ErrorActionPreference = $stare }
  return [pscustomobject]@{ Kod = $kod; Tekst = $wy }
}
function Utworz-Venv { return (Python-Uruchom $PythonBazowy @('-m', 'venv', (Join-Path $Kat 'venv'))) }
function Instaluj-Zaleznosci { return (Python-Uruchom $PyVenv @((Join-Path $Narzedzia 'aktualizacja.py'), '--kat', $Kat, '--zaleznosci')) }
function Pobierz-Model { return (Python-Uruchom $PyVenv @((Join-Path $Narzedzia 'uruchom.py'), 'wiedza_firmy.model')) }
function Zaloz-Zapore {
  Get-NetFirewallRule -Name $NazwaReguly -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  New-NetFirewallRule -Name $NazwaReguly -DisplayName "Wiedza firmy HTTP MCP (TCP $Port)" `
    -Direction Inbound -Protocol TCP -LocalPort $Port -RemoteAddress $AdresyZdalne `
    -Profile Any -Action Allow | Out-Null
}
function Zaloz-Zadanie([string]$uzytkownik) {
  $arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Straznik`" -Kat `"$Kat`" -Port $Port"
  $akcja = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $arg -WorkingDirectory $Kat
  $wyzwalacz = New-ScheduledTaskTrigger -AtStartup
  $wyzwalacz.Delay = 'PT30S'
  $kto = New-ScheduledTaskPrincipal -UserId $uzytkownik -LogonType S4U -RunLevel Highest
  $ustawienia = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew -StartWhenAvailable
  Register-ScheduledTask -TaskName $NazwaZadania -Action $akcja -Trigger $wyzwalacz -Principal $kto `
    -Settings $ustawienia -Force `
    -Description 'Serwer Wiedza firmy (MCP HTTP, port 8766) - straznik z restartem, aktualizacja, kopia. narzedzia\serwer-wiedzy\instaluj-serwer-wiedzy.ps1' | Out-Null
}
function Stan-Zadania { $z = Get-ScheduledTask -TaskName $NazwaZadania -ErrorAction SilentlyContinue; if ($z) { return "$($z.State)" } return '' }
function Zatrzymaj-Zadanie {
  Stop-ScheduledTask -TaskName $NazwaZadania -ErrorAction SilentlyContinue
  # Stop-ScheduledTask zabija tylko straznika - python serwera trzeba zamknac osobno
  foreach ($id in @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)) {
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($p -and $p.ProcessName -like 'python*') { & taskkill.exe /pid $id /t /f 2>&1 | Out-Null }
  }
}
function Uruchom-Zadanie { Start-ScheduledTask -TaskName $NazwaZadania }

if ($Atrapy) { . $Atrapy }

# -----------------------------------------------------------------------------
Krok '0. Sprawdzenia'
if ($Proba) { Plan 'tryb proby: nic nie zostanie zmienione' }
if (-not (Czy-Admin)) { Blad 'Uruchom jako administrator (zapora i zadanie z najwyzszymi uprawnieniami).' }
if ($Port -eq 8765) { Blad 'Port 8765 nalezy do serwera ecommerce-helper - straznik zamknalby jego pythona.' }
if (-not (Test-Path -LiteralPath $PythonBazowy)) { Blad "Brak Pythona systemowego $PythonBazowy (parametr -PythonBazowy)." }
if ($ZrodloKodu -and -not (Test-Path -LiteralPath $ZrodloKodu)) { Blad "Brak archiwum kodu $ZrodloKodu." }
$Uzytkownik = Kto
Ok "administrator: $Uzytkownik; Python: $PythonBazowy; katalog: $Kat; dane: $Dane; port: $Port"

# -----------------------------------------------------------------------------
Krok "1. Katalogi i konfiguracja w $Kat"
$katalogi = @($Kat, $Narzedzia, (Join-Path $Kat 'stan'), (Join-Path $Kat 'kopie'), (Join-Path $Kat 'lore-dane'))
$konf = [ordered]@{
  port = $Port; modul = $Modul; argumenty = @('--host', '0.0.0.0', '--port', "$Port")
  dane = $Dane; drugi_cel_kopii = $DrugiCelKopii; repo = 'Primo2966/MegaRuchacz'; galaz = 'main'
}
$plikKonf = Join-Path $Kat 'serwer-wiedzy.json'
if ($Proba) {
  foreach ($k in $katalogi) { if (-not (Test-Path -LiteralPath $k)) { Plan "utworzylbym $k" } }
  Plan "zapisalbym $plikKonf (port $Port, modul $Modul)"
} else {
  foreach ($k in $katalogi) { New-Item -ItemType Directory -Force -Path $k | Out-Null }
  [IO.File]::WriteAllText($plikKonf, ($konf | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
  Ok 'katalogi i serwer-wiedzy.json'
}

# -----------------------------------------------------------------------------
Krok "2. Skrypty do $Narzedzia"
$tuSamo = (Test-Path -LiteralPath $Narzedzia) -and ((Resolve-Path -LiteralPath $PSScriptRoot).Path -eq (Resolve-Path -LiteralPath $Narzedzia).Path)
foreach ($p in $Pliki) {
  $z = Join-Path $PSScriptRoot $p
  if (-not (Test-Path -LiteralPath $z)) { Blad "Brak pliku $z obok instalatora." }
}
if ($tuSamo) { Info 'instalator uruchomiony z katalogu instalacji - skrypty juz na miejscu' }
elseif ($Proba) { Plan "skopiowalbym: $($Pliki -join ', ')" }
else {
  foreach ($p in $Pliki) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $p) -Destination (Join-Path $Narzedzia $p) -Force }
  Ok "$($Pliki.Count) plikow"
}

# -----------------------------------------------------------------------------
Krok "3. venv $PyVenv"
if (Test-Path -LiteralPath $PyVenv) { Ok 'venv juz jest - zostawiam' }
elseif ($Proba) { Plan "utworzylbym venv: $PythonBazowy -m venv $(Join-Path $Kat 'venv')" }
else {
  $r = Utworz-Venv
  if ($r.Kod -ne 0 -or -not (Test-Path -LiteralPath $PyVenv)) { Blad "venv nie powstal (kod $($r.Kod)): $($r.Tekst -join ' ')" }
  Ok 'venv utworzony'
}

# -----------------------------------------------------------------------------
$zrodlo = if ($ZrodloKodu) { "archiwum $ZrodloKodu" } else { 'GitHub Primo2966/MegaRuchacz (main, publiczne)' }
Krok "4. Kod serwera z: $zrodlo"
if ($Proba) { Plan "pobralbym kod (wiedza_firmy\ + lore\lore\) do $(Join-Path $Kat 'kod') przez aktualizacja.py" }
else {
  $a = @((Join-Path $Narzedzia 'aktualizacja.py'), '--kat', $Kat, '--dane', $Dane, '--modul', $Modul)
  if ($ZrodloKodu) { $a += @('--zip', $ZrodloKodu) }
  $r = Python-Uruchom $PyVenv $a
  $r.Tekst | ForEach-Object { Info $_ }
  if ($r.Kod -eq 3) { Blad 'Inna aktualizacja wlasnie trwa (zamek) - uruchom instalator ponownie za chwile.' }
  if ($r.Kod -ne 0 -and $r.Kod -ne 10) {
    Blad "Kod serwera nie zostal pobrany (szczegoly: $(Join-Path $Kat 'stan\aktualizacja.log')). Poprzedni kod (jesli byl) zostal bez zmian."
  }
  Ok 'kod serwera na miejscu'
}

# -----------------------------------------------------------------------------
$pyproject = Join-Path $Kat 'kod\wiedza_firmy\pyproject.toml'
Krok "5. Zaleznosci z $pyproject"
if ($Proba) {
  if (Test-Path -LiteralPath $pyproject) { Plan 'zainstalowalbym zaleznosci pip-em do venv' }
  else { Plan "zainstalowalbym zaleznosci z $pyproject (dzis brak pliku - przy prawdziwej instalacji kod pobiera sie w kroku 4)" }
} else {
  if (-not (Test-Path -LiteralPath $pyproject)) {
    Blad "Brak $pyproject - pakiet wiedza_firmy nie ma pyproject.toml, nie wiem, jakie zaleznosci instalowac."
  }
  $r = Instaluj-Zaleznosci
  $r.Tekst | ForEach-Object { Info $_ }
  if ($r.Kod -ne 0) { Blad "pip nie zainstalowal zaleznosci (szczegoly: $(Join-Path $Kat 'stan\pip.log'))." }
  Ok 'zaleznosci zainstalowane'
}

# -----------------------------------------------------------------------------
Krok "6. Modul serwera $Modul"
if ($Proba) { Plan "sprawdzilbym import $Modul" }
else {
  $r = Python-Uruchom $PyVenv @((Join-Path $Narzedzia 'uruchom.py'), '--sprawdz', $Modul)
  $r.Tekst | ForEach-Object { Info $_ }
  if ($r.Kod -ne 0) { Blad "Modul $Modul sie nie importuje (parametr -Modul, jesli serwer ma inna nazwe)." }
  Ok 'import dziala'
}

# -----------------------------------------------------------------------------
Krok "7. Model $NazwaModelu (przypiety commit, sumy SHA-256)"
if ($Proba) { Plan "pobralbym model (~500 MB) do $(Join-Path $Dane 'modele'), sprawdzil sumy SHA-256 i zaladowal na probe" }
else {
  $r = Pobierz-Model
  $r.Tekst | ForEach-Object { Info $_ }
  if ($r.Kod -ne 0) { Blad 'Model nie zostal pobrany albo nie zgadzaja sie sumy SHA-256 (opis wyzej). Baza, tematy i osoby bez zmian.' }
  Ok 'model sprawdzony'
}

# -----------------------------------------------------------------------------
Krok "8. Zapora: wejscie TCP $Port tylko z $($AdresyZdalne -join ', ')"
if ($Proba) { Plan "zalozylbym / odswiezylbym regule $NazwaReguly" }
else { Zaloz-Zapore; Ok "regula $NazwaReguly" }

# -----------------------------------------------------------------------------
Krok "9. Zadanie Harmonogramu $NazwaZadania (jako $Uzytkownik, S4U)"
if ($Proba) { Plan "zalozylbym zadanie: powershell -File `"$Straznik`" -Kat `"$Kat`" -Port $Port" }
else { Zaloz-Zadanie $Uzytkownik; Ok 'zadanie zapisane' }

# -----------------------------------------------------------------------------
Krok '10. Osoby i start'
$osoby = Join-Path $Dane 'osoby.json'
if (-not (Test-Path -LiteralPath $osoby)) {
  Uwaga "Nikt nie ma jeszcze dostepu ($osoby nie istnieje). Osoba: $PyVenv $(Join-Path $Narzedzia 'uruchom.py') wiedza_firmy.osoby nowa <osoba> [--admin]"
} else { Ok "osoby: $osoby" }
if ($Proba -or $BezStartu) {
  Info 'zadanie nie uruchomione (-Proba / -BezStartu)'
} else {
  $st = Stan-Zadania
  if ($st -eq 'Running' -and $Restartuj) {
    Zatrzymaj-Zadanie; Uruchom-Zadanie; Ok 'zadanie zatrzymane (razem z pythonem) i uruchomione od nowa'
  } elseif ($st -eq 'Running') {
    Info 'zadanie juz dziala - zostawiam (nowy straznik/skrypty dopiero po -Restartuj)'
  } else {
    Uruchom-Zadanie; Ok 'zadanie uruchomione'
  }
  Info "Stan: powershell -File $(Join-Path $Narzedzia 'stan-serwera-wiedzy.ps1')"
}
exit 0
