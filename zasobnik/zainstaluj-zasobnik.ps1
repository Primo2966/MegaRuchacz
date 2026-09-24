# Rejestracja nadzorcy w Harmonogramie Windows: ma wstawac przy KAZDYM
# zalogowaniu, niezaleznie od tego, czy ktokolwiek otworzy Claude Code albo
# Codeksa. To jest cala roznica miedzy nim a hookami - hook nie chodzi, gdy nie
# ma sesji, a wtedy milknie tez wykrywanie ciszy.
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File zasobnik\zainstaluj-zasobnik.ps1
#     -Zrodlo <kat>     katalog glowny narzedzia (domyslnie: katalog nad zasobnik\)
#     -Proba            wypisuje, co by zrobil, i NIE robi nic
#     -TylkoSprawdz     sam stan: czy zadanie jest i czy nadzorca chodzi
#     -Usun             zdejmuje zadanie z Harmonogramu i zamyka nadzorce
#     -BezStartu        zaklada zadanie, ale nie uruchamia nadzorcy od razu
#
# Zadanie zaklada sie PRZEZ XML, a nie przez New-ScheduledTaskPrincipal - ta
# druga droga konczy sie "Odmowa dostepu" u zwyklego, niepodniesionego
# uzytkownika (sprawdzone 2026-09-16, patrz narzedzia\instaluj-lore.ps1).
#
# Akcja idzie przez conhost.exe --headless, bo inaczej przy kazdym zalogowaniu
# mrugneloby okno konsoli. ExecutionTimeLimit = PT0S, czyli bez limitu: nadzorca
# ma chodzic caly dzien, a zadanie z domyslnymi trzema dniami limitu ubiloby go
# w polowie tygodnia bez slowa.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Proba,
  [switch]$TylkoSprawdz,
  [switch]$Usun,
  [switch]$BezStartu
)

$NazwaZadania = "MegaRuchaczNadzorca"
$Nadzorca     = Join-Path $Zrodlo "zasobnik\nadzorca.ps1"

function Naglowek($tekst) {
  Write-Host ""
  Write-Host $tekst -ForegroundColor Cyan
  Write-Host ("-" * $tekst.Length) -ForegroundColor DarkGray
}
function Krok($tekst)        { Write-Host "  $tekst" }
function Plan($tekst)        { Write-Host "  [PROBA] $tekst" -ForegroundColor DarkGray }
function Ostrzezenie($tekst) { Write-Host "UWAGA  $tekst" -ForegroundColor Yellow }
function Blad($tekst)        { Write-Host "BLAD  $tekst" -ForegroundColor Red }

function Argumenty-Nadzorcy {
  return ('--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
          $Nadzorca + '" -Zrodlo "' + $Zrodlo.TrimEnd('\') + '"')
}

# Jedno zrodlo prawdy o zadaniu: pytamy Harmonogram, nie wlasna pamiec o tym,
# ze przed chwila cos zarejestrowalismy. Ten sam wzorzec co w instaluj-lore.ps1 -
# tam audyt na obcej maszynie pokazal, ze Register-ScheduledTask potrafi przejsc
# bez wyjatku i nie zalozyc niczego.
function Stan-Zadania {
  if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
    return [pscustomobject]@{ Ok = $false; Opis = "brak Get-ScheduledTask - nie mam czym sprawdzic Harmonogramu" }
  }
  $z = Get-ScheduledTask -TaskName $NazwaZadania -ErrorAction SilentlyContinue
  if (-not $z) { return [pscustomobject]@{ Ok = $false; Opis = "Harmonogram nie zna zadania $NazwaZadania" } }
  if ($z.State -eq "Disabled") {
    return [pscustomobject]@{ Ok = $false; Opis = "zadanie istnieje, ale jest wylaczone (Disabled) - nie uruchomi sie przy zalogowaniu" }
  }
  $akcje = @($z.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" })
  if (@($akcje | Where-Object { $_ -match 'nadzorca\.ps1' }).Count -eq 0) {
    return [pscustomobject]@{ Ok = $false; Opis = "zadanie o tej nazwie istnieje, ale nie uruchamia nadzorca.ps1" }
  }
  return [pscustomobject]@{ Ok = $true; Opis = "stan: $($z.State)" }
}

# Czy nadzorca chodzi TERAZ. Po wierszu polecenia procesu, bo to jedyny dowod
# niezalezny od tego, co Harmonogram sadzi o swoim zadaniu.
#
# Przecinek przed @(...) NIE JEST literowka: bez niego PowerShell rozwija pusta
# tablice do $null przy zwrocie, wiec "nie znalazlem nadzorcy" bylo nie do
# odroznienia od "nie mialem jak sprawdzic". Pierwsze uruchomienie meldowalo
# przez to "NIE WIEM" zamiast "nie chodzi" - czyli falszywy alarm, a te ucza
# ignorowania ostrzezen. $null zostaje wylacznie na prawdziwe "nie wiem".
function Procesy-Nadzorcy {
  try {
    return ,@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop |
              Where-Object { $_.CommandLine -and $_.CommandLine -match 'nadzorca\.ps1' })
  } catch {
    Ostrzezenie "nie moge zajrzec do listy procesow: $($_.Exception.Message)"
    return $null
  }
}

function Zarejestruj {
  $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
  $argXml = [System.Security.SecurityElement]::Escape((Argumenty-Nadzorcy))
  $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>MegaRuchacz - nadzorca w zasobniku: rachunek za pamiec, cykl wiedzy i alarmy, niezaleznie od hookow</Description>
    <URI>\$NazwaZadania</URI>
  </RegistrationInfo>
  <Principals>
    <Principal id="Author">
      <UserId>$sid</UserId>
      <LogonType>InteractiveToken</LogonType>
    </Principal>
  </Principals>
  <Settings>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <Hidden>true</Hidden>
    <Enabled>true</Enabled>
  </Settings>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$sid</UserId>
      <Delay>PT30S</Delay>
    </LogonTrigger>
  </Triggers>
  <Actions Context="Author">
    <Exec>
      <Command>conhost.exe</Command>
      <Arguments>$argXml</Arguments>
    </Exec>
  </Actions>
</Task>
"@
  Register-ScheduledTask -TaskName $NazwaZadania -Xml $xml -Force -ErrorAction Stop | Out-Null
}

function Zamknij-Nadzorce {
  $procesy = Procesy-Nadzorcy
  if ($null -eq $procesy) { Ostrzezenie "nie wiem, czy nadzorca chodzi - nie mialem jak sprawdzic"; return }
  if ($procesy.Count -eq 0) { Krok "nadzorca nie chodzi - nie ma czego zamykac"; return }
  foreach ($p in $procesy) {
    try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; Krok "zamknieto nadzorce (PID $($p.ProcessId))" }
    catch { Ostrzezenie "nie udalo sie zamknac PID $($p.ProcessId): $($_.Exception.Message)" }
  }
}

# ------------------------------------------------------------------ przebiegi

if (-not (Test-Path $Nadzorca)) {
  Blad "nie ma $Nadzorca - podaj wlasciwy -Zrodlo"
  exit 1
}

if ($TylkoSprawdz) {
  Naglowek "Nadzorca w zasobniku - stan"
  $stan = Stan-Zadania
  if ($stan.Ok) { Krok "zadanie ${NazwaZadania}: jest w Harmonogramie ($($stan.Opis))" }
  else { Ostrzezenie "zadanie ${NazwaZadania}: $($stan.Opis)" }
  $procesy = Procesy-Nadzorcy
  if ($null -eq $procesy) { Ostrzezenie "czy nadzorca chodzi: NIE WIEM" }
  elseif ($procesy.Count -eq 0) { Ostrzezenie "nadzorca NIE chodzi - ikony w zasobniku nie ma" }
  else { Krok "nadzorca chodzi ($($procesy.Count) proc., PID $(($procesy | ForEach-Object { $_.ProcessId }) -join ', '))" }
  if ($stan.Ok -and $procesy -and $procesy.Count -gt 0) { exit 0 }
  exit 1
}

if ($Usun) {
  Naglowek "Nadzorca w zasobniku - usuwanie"
  if ($Proba) {
    Plan "Unregister-ScheduledTask $NazwaZadania -Confirm:`$false"
    Plan "oraz zamkniecie chodzacego nadzorcy"
    exit 0
  }
  Zamknij-Nadzorce
  if (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $NazwaZadania -Confirm:$false -ErrorAction SilentlyContinue
  }
  $stan = Stan-Zadania
  if ($stan.Ok) { Blad "zadanie $NazwaZadania nadal jest w Harmonogramie - zdejmij je recznie"; exit 1 }
  Krok "zadanie $NazwaZadania zdjete z Harmonogramu"
  Krok "UWAGA: od tej chwili nikt nie pilnuje cyklu wiedzy poza hookami sesji"
  exit 0
}

Naglowek "Nadzorca w zasobniku ($NazwaZadania)"
$argumenty = Argumenty-Nadzorcy
if ($Proba) {
  Plan "Register-ScheduledTask -TaskName $NazwaZadania -Force   (nadpisuje istniejace, nie doklada drugiego)"
  Plan "  akcja     : conhost.exe $argumenty"
  Plan "  wyzwalacz : przy zalogowaniu uzytkownika, 30 s opoznienia"
  Plan "  limit     : bez limitu czasu (PT0S) - nadzorca ma chodzic caly dzien"
  if (-not $BezStartu) { Plan "  potem     : Start-ScheduledTask $NazwaZadania (zeby nie czekac na wylogowanie)" }
  exit 0
}

if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
  Blad "ta maszyna nie ma Register-ScheduledTask - nie zaloze autostartu"
  Krok "obejscie: skrot do 'conhost.exe $argumenty' wrzuc do katalogu Autostart (shell:startup)"
  exit 1
}

try {
  Zarejestruj
} catch {
  Blad "nie udalo sie zalozyc zadania: $($_.Exception.Message)"
  Krok "jesli to 'Odmowa dostepu' - zasady tej maszyny moga wymagac uprawnien administratora"
  exit 1
}

$stan = Stan-Zadania
if (-not $stan.Ok) {
  Blad "zadanie $NazwaZadania nie powstalo: $($stan.Opis)"
  Krok "Harmonogram przyjal polecenie, ale zadania tam nie ma - sprawdz zasady tej maszyny"
  exit 1
}
Krok "zadanie $NazwaZadania jest w Harmonogramie ($($stan.Opis)) - nadzorca wstaje przy kazdym zalogowaniu"

if ($BezStartu) {
  Krok "nie startuje go teraz (-BezStartu) - pojawi sie po nastepnym zalogowaniu"
  exit 0
}

# Zadanie z wyzwalaczem "przy zalogowaniu" nie odpala sie samo w chwili zalozenia,
# a uzytkownik ma zobaczyc ikone teraz, nie jutro.
$procesy = Procesy-Nadzorcy
if ($procesy -and $procesy.Count -gt 0) {
  Krok "nadzorca juz chodzi (PID $(($procesy | ForEach-Object { $_.ProcessId }) -join ', ')) - nie startuje drugiego"
  exit 0
}
try {
  Start-ScheduledTask -TaskName $NazwaZadania -ErrorAction Stop
} catch {
  Ostrzezenie "nie udalo sie wystartowac zadania teraz: $($_.Exception.Message)"
  Krok "nadzorca pojawi sie po najblizszym zalogowaniu"
  exit 0
}

# Sprawdzamy, czy naprawde wstal - "Start-ScheduledTask przeszlo bez wyjatku"
# nie jest dowodem na nic, dokladnie tak jak przy zakladaniu zadania.
Start-Sleep -Seconds 6
$procesy = Procesy-Nadzorcy
if ($null -eq $procesy) {
  Ostrzezenie "wystartowalem zadanie, ale nie mam jak sprawdzic, czy nadzorca chodzi"
  exit 0
}
if ($procesy.Count -eq 0) {
  Ostrzezenie "zadanie wystartowane, a nadzorcy nie widac wsrod procesow"
  Krok "sprawdz recznie: powershell -ExecutionPolicy Bypass -File $Nadzorca -Raz"
  exit 1
}
Krok "nadzorca chodzi (PID $(($procesy | ForEach-Object { $_.ProcessId }) -join ', ')) - ikona jest w zasobniku"
Krok "kliknij ja, zeby zobaczyc rachunek, stan cyklu i numer wersji"
exit 0
