# Codzienne wylawianie trwalych faktow z wczorajszych rozmow.
#
# Przeglada rozmowy zaindeksowane od ostatniego przebiegu, prosi model o fakty, ktore beda
# prawdziwe za pol roku, i dopisuje je do POCZEKALNI: %USERPROFILE%\.claude\wiedza\kandydaci.md
# Do obowiazujacej wiedzy (~\.claude\CLAUDE.md) nie trafia nic samo - czlowiek zatwierdza recznie.
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File narzedzia\wyciagnij-fakty.ps1
#   ... -Zrodlo <sciezka>   katalog glowny repozytorium (domyslnie: katalog nad narzedzia\)
#   ... -Proba              pokazuje, co by zrobil, i NIE zapisuje niczego
#   ... -Nadrabiaj <N>      do N przebiegow pod rzad; konczy wczesniej, gdy zaleglosci sie skoncza
#   ... -Kolejka            wypisuje SAME LICZBY o stanie kolejki i konczy; nic nie zapisuje
#   ... -ZalozZadanie       zaklada zadanie "LoreFacts" w harmonogramie (codziennie 08:05)
#   ... -UsunZadanie        kasuje to zadanie

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Proba,
  [int]$Nadrabiaj = 1,
  [switch]$Kolejka,
  [switch]$ZalozZadanie,
  [switch]$UsunZadanie
)

$NazwaZadania = "LoreFacts"
$Godzina      = "08:05"

$script:Uv   = $null
$script:Lore = $null

# ---------------------------------------------------------------- wypisywanie

function Naglowek($tekst) {
  Write-Host ""
  Write-Host $tekst -ForegroundColor Cyan
  Write-Host ("-" * $tekst.Length) -ForegroundColor DarkGray
}

function Krok($tekst)        { Write-Host "  $tekst" }
function Plan($tekst)        { Write-Host "  [PROBA] $tekst" -ForegroundColor DarkGray }
function Ostrzezenie($tekst) { Write-Host "UWAGA  $tekst" -ForegroundColor Yellow }
function Blad($tekst)        { Write-Host "BLAD  $tekst" -ForegroundColor Red }

# ---------------------------------------------------------------- warunki wstepne

function Znajdz-Uv {
  # najpierw PATH, a jak nie ma - sciezki, pod ktore uv laduje z WinGeta
  $cmd = Get-Command uv -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return $cmd.Source }
  $link = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\uv.exe"
  if (Test-Path $link) { return (Resolve-Path $link).Path }
  $wzorzec = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\astral-sh.uv_*\uv.exe"
  $trafienie = Get-ChildItem $wzorzec -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($trafienie) { return $trafienie.FullName }
  return $null
}

function Sprawdz-Warunki {
  $sciezka = Resolve-Path $Zrodlo -ErrorAction SilentlyContinue
  if (-not $sciezka) {
    Blad "nie ma takiego katalogu: $Zrodlo"
    exit 1
  }
  $script:Lore = Join-Path $sciezka.Path "lore"
  if (-not (Test-Path (Join-Path $script:Lore "pyproject.toml"))) {
    Blad "nie widze $($script:Lore)\pyproject.toml - wskaz repozytorium przez  -Zrodlo <sciezka>"
    exit 1
  }
  $script:Uv = Znajdz-Uv
  if (-not $script:Uv) {
    Blad "nie znalazlem uv (menedzer srodowisk Pythona). Zainstaluj:  winget install --id astral-sh.uv"
    exit 1
  }
}

# ---------------------------------------------------------------- zadanie w harmonogramie

function Argumenty-Zadania {
  # conhost --headless: zadanie chodzi samo rano i nikt nie chce ogladac mrugajacego okna konsoli
  return "--headless `"$($script:Uv)`" --directory `"$($script:Lore)`" run python -m lore.facts --nadrabiaj $Nadrabiaj"
}

function Zaloz-Zadanie {
  Naglowek "Zadanie w harmonogramie ($NazwaZadania)"
  $argumenty = Argumenty-Zadania
  if ($Proba) {
    Plan "Register-ScheduledTask -TaskName $NazwaZadania -Force   (nadpisuje istniejace, nie doklada drugiego)"
    Plan "  akcja     : conhost.exe $argumenty"
    Plan "  wyzwalacz : codziennie o $Godzina, z nadrobieniem po wlaczeniu komputera"
    exit 0
  }
  # UWAGA - sprawdzone 2026-09-16: zakladanie zadania przez obiekty
  # (New-ScheduledTaskPrincipal + Register-ScheduledTask -Principal) konczy sie
  # "Odmowa dostepu" u zwyklego, niepodniesionego uzytkownika. Ta sama operacja
  # podana jako XML przechodzi bez uprawnien administratora. Dlatego XML.
  try {
    $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $czesci = $Godzina -split ":"
    $start = (Get-Date -Hour ([int]$czesci[0]) -Minute ([int]$czesci[1]) -Second 0).ToString("yyyy-MM-ddTHH:mm:ss")
    $argXml = [System.Security.SecurityElement]::Escape($argumenty)
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Lore - codzienne wylawianie trwalych faktow z rozmow (do poczekalni)</Description>
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
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
    <StartWhenAvailable>true</StartWhenAvailable>
    <Enabled>true</Enabled>
  </Settings>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>$start</StartBoundary>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
      <Enabled>true</Enabled>
    </CalendarTrigger>
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
  } catch {
    Blad "nie udalo sie zalozyc zadania: $($_.Exception.Message)"
    Krok "jesli to 'Odmowa dostepu' - zasady tej maszyny moga wymagac uprawnien administratora"
    exit 1
  }
  # StartWhenAvailable: gdy komputer byl o $Godzina wylaczony, zadanie ruszy przy najblizszej okazji
  Krok "fakty wylawiane codziennie o $Godzina (z nadrobieniem po wlaczeniu komputera)"
  Krok "propozycje laduja w: $(Join-Path $env:USERPROFILE '.claude\wiedza\kandydaci.md')"
  exit 0
}

function Usun-Zadanie {
  Naglowek "Usuwanie zadania ($NazwaZadania)"
  if ($Proba) {
    Plan "Unregister-ScheduledTask -TaskName $NazwaZadania -Confirm:`$false"
    exit 0
  }
  $zadanie = Get-ScheduledTask -TaskName $NazwaZadania -ErrorAction SilentlyContinue
  if (-not $zadanie) {
    Krok "takiego zadania nie ma - nie ma czego kasowac"
    exit 0
  }
  try {
    Unregister-ScheduledTask -TaskName $NazwaZadania -Confirm:$false -ErrorAction Stop
  } catch {
    Blad "nie udalo sie usunac zadania: $($_.Exception.Message)"
    exit 1
  }
  Krok "usuniete - poczekalnia i dotychczasowi kandydaci zostaja nietkniete"
  exit 0
}

# ---------------------------------------------------------------- stan kolejki

# Cykl dzienny decyduje na podstawie tych liczb, ile materialu wziac - i dlatego dostaje
# je jako liczby, a nie jako zdanie do rozszyfrowania. Wyczytywanie ich z tekstu przebiegu
# ("-Nadrabiaj 4") juz raz zawiodlo: cykl te liczbe czytal, ale uzywal tylko do podsumowania.
# Przebieg probny nie wola modelu i niczego nie zapisuje (znacznika nie przesuwa), a zmierzony
# 2026-09-17 trwa 0,4 s - wolno go wiec zrobic PRZED decyzja, ile brac.
# apostrofy, nie cudzyslowy: kod idzie do pythona jako JEDEN argument, a cudzyslow w
# argumencie programu natywnego przechodzi przez escapowanie Windowsa - po co ryzykowac
$KodKolejki = @'
from lore import facts;r=facts.run(dry_run=True);print('kolejka.status: %s' % r.get('status',''));print('kolejka.kawalki: %d' % (r.get('chunks',0)+r.get('pending',0)));print('kolejka.przebiegi: %d' % ((r.get('runs_left',0)+1) if r.get('chunks',0) else 0))
'@

function Pokaz-Kolejke {
  # "+1": runs_left liczy sie od tego, co ZOSTAJE po biezacej porcji, a proba tej porcji
  # nie zabrala. Pelne domkniecie kolejki to wiec ta porcja plus reszta.
  & $script:Uv --directory $script:Lore run python -c $KodKolejki
  $kod = $LASTEXITCODE
  if ($kod -ne 0) { Blad "nie udalo sie odczytac stanu kolejki (kod $kod)" }
  exit $kod
}

# ---------------------------------------------------------------- jeden przebieg

function Wyciagnij-Fakty {
  Naglowek "Wylawianie faktow z rozmow"
  if ($Proba) { Ostrzezenie "TRYB PROBNY - tylko pokazuje material, niczego nie zapisuje" }
  $argumenty = @("--directory", $script:Lore, "run", "python", "-m", "lore.facts", "--nadrabiaj", "$Nadrabiaj")
  if ($Proba) { $argumenty += "--proba" }
  & $script:Uv @argumenty
  $kod = $LASTEXITCODE
  if ($kod -ne 0) {
    Blad "wyciaganie faktow nie powiodlo sie (kod $kod) - szczegoly w liniach powyzej"
  }
  exit $kod
}

# ---------------------------------------------------------------- przebieg

if ($Nadrabiaj -lt 1) { $Nadrabiaj = 1 }

Sprawdz-Warunki

if ($Kolejka)      { Pokaz-Kolejke }
if ($UsunZadanie)  { Usun-Zadanie }
if ($ZalozZadanie) { Zaloz-Zadanie }

Wyciagnij-Fakty
