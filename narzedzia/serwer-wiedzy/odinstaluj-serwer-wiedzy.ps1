<#
Odinstalowanie serwera "Wiedza firmy" (Pakowanie2): zdejmuje zadanie Harmonogramu
WiedzaFirmyHttp, regule zapory WiedzaFirmyHttp-TCP i zamyka proces serwera
(Stop-ScheduledTask zabija tylko straznika - python trzymajacy port zamykamy osobno).

NIC nie kasuje z dysku: dane (%APPDATA%\wiedza-firmy\ - baza, tematy, osoby),
kopie zapasowe (<Kat>\kopie\) i program (<Kat>\) zostaja. Program mozna potem
usunac recznie; kopie przenies wczesniej w bezpieczne miejsce.

  powershell -NoProfile -ExecutionPolicy Bypass -File odinstaluj-serwer-wiedzy.ps1 [-Proba]
#>
[CmdletBinding()]
param(
  [switch]$Proba,
  [int]$Port = 8766,
  [string]$Kat = 'C:\dev\wiedza-firmy',
  [string]$Atrapy = ''   # TYLKO TESTY
)
$ErrorActionPreference = 'Stop'
$NazwaZadania = 'WiedzaFirmyHttp'
$NazwaReguly = 'WiedzaFirmyHttp-TCP'

function Ok([string]$t) { Write-Host "  [OK] $t" -ForegroundColor Green }
function Info([string]$t) { Write-Host "  $t" }
function Plan([string]$t) { Write-Host "  [proba] $t" -ForegroundColor DarkGray }

function Czy-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Jest-Zadanie { return [bool](Get-ScheduledTask -TaskName $NazwaZadania -ErrorAction SilentlyContinue) }
function Usun-Zadanie {
  Stop-ScheduledTask -TaskName $NazwaZadania -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $NazwaZadania -Confirm:$false
}
function Jest-Regula { return [bool](Get-NetFirewallRule -Name $NazwaReguly -ErrorAction SilentlyContinue) }
function Usun-Regule { Remove-NetFirewallRule -Name $NazwaReguly }
function Procesy-Serwera {
  # python na porcie serwera + straznik (powershell z straznik.ps1 tej instalacji w linii polecen)
  $wynik = @()
  foreach ($id in @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)) {
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($p -and $p.ProcessName -like 'python*') { $wynik += $id }
  }
  $wzor = [regex]::Escape((Join-Path $Kat 'narzedzia\straznik.ps1'))
  $wynik += @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match $wzor } | Select-Object -ExpandProperty ProcessId)
  return $wynik
}
function Zabij([int]$id) { & taskkill.exe /pid $id /t /f 2>&1 | Out-Null }

if ($Atrapy) { . $Atrapy }

if (-not (Czy-Admin)) { Write-Host '[BLAD] Uruchom jako administrator.' -ForegroundColor Red; exit 1 }

Write-Host "=== Zadanie $NazwaZadania"
if (-not (Jest-Zadanie)) { Info 'nie ma - pomijam' }
elseif ($Proba) { Plan 'zatrzymalbym i usunal zadanie' }
else { Usun-Zadanie; Ok 'zadanie usuniete' }

Write-Host "=== Procesy serwera (port $Port, straznik)"
$ids = @(Procesy-Serwera)
if (-not $ids.Count) { Info 'nic nie dziala' }
elseif ($Proba) { Plan "zamknalbym procesy: $($ids -join ', ')" }
else { foreach ($id in $ids) { Zabij $id }; Ok "zamkniete: $($ids -join ', ')" }

Write-Host "=== Zapora $NazwaReguly"
if (-not (Jest-Regula)) { Info 'nie ma - pomijam' }
elseif ($Proba) { Plan 'usunalbym regule' }
else { Usun-Regule; Ok 'regula usunieta' }

Write-Host ''
Info "Dane zostaly bez zmian: $(Join-Path $env:APPDATA 'wiedza-firmy')"
Info "Program i kopie zapasowe zostaly bez zmian: $Kat (kopie w $(Join-Path $Kat 'kopie'))"
exit 0
