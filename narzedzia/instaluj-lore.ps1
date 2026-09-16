# Instalator modulu pamieci rozmow "Lore" - stawia calosc jednym poleceniem:
# srodowisko Pythona (uv), rejestracja serwera MCP, zadanie w harmonogramie,
# a na koniec test, czy to naprawde dziala.
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File narzedzia\instaluj-lore.ps1
#   ... -Zrodlo <sciezka>   katalog glowny repozytorium (domyslnie: katalog nad narzedzia\)
#   ... -BezPytania         pomija ekran zgody (dla instalatora nadrzednego, ktory juz ja zebral)
#   ... -Proba              wypisuje, co by zrobil, i NIE robi nic
#   ... -TylkoSprawdz       sam test juz zainstalowanego modulu

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$BezPytania,
  [switch]$Proba,
  [switch]$TylkoSprawdz
)

$NazwaMcp      = "lore"
$NazwaZadania  = "LoreIndex"
$InterwalMin   = 10
$RozmiarModelu = "~465 MB"

$script:Uv     = $null
$script:Claude = $null
$script:Lore   = $null
$script:Baza   = Join-Path $env:USERPROFILE ".claude\lore.db"
$script:Modele = Join-Path $env:USERPROFILE ".claude\lore_models"
$script:Kroki  = @()   # wyniki sprawdzen do koncowego podsumowania

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

function Zapisz-Wynik($nazwa, $ok, $opis) {
  $script:Kroki += [pscustomobject]@{ Nazwa = $nazwa; Ok = [bool]$ok; Opis = $opis }
  $etykieta = if ($ok) { "OK  " } else { "BLAD" }
  $kolor    = if ($ok) { "Green" } else { "Red" }
  $linia    = "  $etykieta  $nazwa"
  if ($opis) { $linia += " - $opis" }
  Write-Host $linia -ForegroundColor $kolor
}

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
  Naglowek "Warunki wstepne"
  $braki = @()

  $script:Uv = Znajdz-Uv
  if ($script:Uv) {
    Krok "uv      : $($script:Uv)"
  } else {
    $braki += "uv (menedzer srodowisk Pythona). Zainstaluj:  winget install --id astral-sh.uv"
  }

  if ($script:Uv) {
    # uv zna swoje wlasne instalacje Pythona, wiec pytamy jego, a nie PATH-a
    $py = & $script:Uv python find ">=3.12" 2>&1
    if ($LASTEXITCODE -eq 0) {
      Krok "Python  : $($py | Select-Object -Last 1)"
    } else {
      $braki += "Python 3.12 lub nowszy. Zainstaluj:  uv python install 3.12"
    }
  }

  $cl = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cl) {
    $script:Claude = $cl.Source
    Krok "claude  : $($script:Claude)"
  } else {
    $braki += "claude (Claude Code w PATH - bez niego nie da sie zarejestrowac serwera MCP). Zainstaluj:  npm install -g @anthropic-ai/claude-code"
  }

  if (Test-Path (Join-Path $script:Lore "pyproject.toml")) {
    Krok "modul   : $($script:Lore)"
  } else {
    $braki += "katalog modulu: nie widze $($script:Lore)\pyproject.toml - wskaz repozytorium przez  -Zrodlo <sciezka>"
  }

  if ($braki.Count -gt 0) {
    Write-Host ""
    Blad "brakuje tego, bez czego instalacja nie ma sensu:"
    foreach ($b in $braki) { Write-Host "  - $b" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "Nic nie zostalo zmienione."
    exit 1
  }
}

# ---------------------------------------------------------------- zgoda uzytkownika

function Ekran-Zgody {
  Naglowek "Co zaraz stanie sie na tym komputerze"
  Write-Host @"
  Lore to lokalna, przeszukiwalna pamiec Twoich rozmow z Claude Code.

  1. Powstanie LOKALNA baza SQLite z wyszukiwaniem pelnotekstowym i semantycznym
     (znajduje po sensie zdania, nie tylko po doslownym slowie).
        baza  : $($script:Baza)
  2. Przy pierwszym uruchomieniu pobierze sie z internetu model jezykowy, $RozmiarModelu.
        model : $($script:Modele)
  3. Zostanie zarejestrowany serwer MCP o nazwie "$NazwaMcp" dla Twojego uzytkownika.
     UWAGA: od tej chwili agent AI ma dostep do TRESCI wszystkich Twoich rozmow
     z Claude Code na tej maszynie - ze wszystkich projektow i wszystkich okien.
  4. Powstanie zadanie w Harmonogramie zadan Windows ("$NazwaZadania"), ktore odswieza
     indeks co $InterwalMin minut i startuje razem z Twoim zalogowaniem.

  Nic nie wychodzi poza ta maszyne: baza, model i samo wyszukiwanie dzialaja lokalnie,
  bez zewnetrznych API. Jedynym ruchem w sieci jest jednorazowe pobranie modelu.
"@
}

function Zapytaj-O-Zgode {
  Ekran-Zgody
  if ($Proba) {
    Write-Host ""
    Plan "tutaj instalator poprosilby o potwierdzenie"
    return
  }
  if ($BezPytania) {
    Write-Host ""
    Krok "zgoda zebrana wczesniej (-BezPytania) - nie pytam"
    return
  }
  Write-Host ""
  $odp = Read-Host "  Instalowac? wpisz 'tak', zeby kontynuowac"
  if ($odp -notmatch '^\s*(t|tak|y|yes)\s*$') {
    Write-Host ""
    Write-Host "Przerwane na zyczenie - nic nie zostalo zmienione."
    exit 0
  }
}

# ---------------------------------------------------------------- instalacja

function Zainstaluj-Srodowisko {
  Naglowek "Srodowisko Pythona"
  if ($Proba) {
    Plan "uv --directory $($script:Lore) sync   (sciaga zaleznosci modulu do .venv)"
    return
  }
  & $script:Uv --directory $script:Lore sync
  if ($LASTEXITCODE -ne 0) {
    Blad "uv sync nie powiodl sie (kod $LASTEXITCODE) - przerywam, zeby nie zostawic polowicznej instalacji."
    exit 1
  }
  Krok "zaleznosci gotowe"
}

function Zarejestruj-Mcp {
  Naglowek "Serwer MCP ($NazwaMcp)"
  $argumenty = @("mcp", "add", "--scope", "user", $NazwaMcp, "--",
                 $script:Uv, "--directory", $script:Lore, "run", "python", "-m", "lore.server")
  if ($Proba) {
    Plan "claude mcp remove $NazwaMcp -s user   (tylko jesli wpis juz istnieje)"
    Plan "claude $($argumenty -join ' ')"
    return
  }
  # idempotentnie: stary wpis najpierw kasujemy, zeby ponowna instalacja nie zrobila duplikatu
  & $script:Claude mcp get $NazwaMcp > $null 2>&1
  if ($LASTEXITCODE -eq 0) {
    Krok "wpis o tej nazwie juz jest - usuwam stary"
    & $script:Claude mcp remove $NazwaMcp -s user > $null 2>&1
  }
  & $script:Claude @argumenty
  if ($LASTEXITCODE -ne 0) {
    Blad "rejestracja serwera MCP nie powiodla sie (kod $LASTEXITCODE)."
    exit 1
  }
  Krok "zarejestrowany dla uzytkownika - widoczny we wszystkich projektach"
}

function Zaloz-Zadanie {
  Naglowek "Zadanie w harmonogramie ($NazwaZadania)"
  # conhost --headless: zadanie chodzi co kilka minut i nikt nie chce ogladac mrugajacego okna konsoli
  $argumenty = "--headless `"$($script:Uv)`" --directory `"$($script:Lore)`" run python -m lore.index"
  if ($Proba) {
    Plan "Register-ScheduledTask -TaskName $NazwaZadania -Force   (nadpisuje istniejace, nie doklada drugiego)"
    Plan "  akcja     : conhost.exe $argumenty"
    Plan "  wyzwalacz : przy zalogowaniu uzytkownika, potem co $InterwalMin min bez konca"
    return
  }
  try {
    $akcja     = New-ScheduledTaskAction -Execute "conhost.exe" -Argument $argumenty -ErrorAction Stop
    $wyzwalacz = New-ScheduledTaskTrigger -AtLogOn -ErrorAction Stop
    # powtarzania nie da sie podac wprost przy wyzwalaczu logowania - bierzemy je z jednorazowego
    $wzorzec = New-ScheduledTaskTrigger -Once -At (Get-Date) `
                 -RepetitionInterval (New-TimeSpan -Minutes $InterwalMin) -ErrorAction Stop
    $wyzwalacz.Repetition = $wzorzec.Repetition
    $ustawienia = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
                    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                    -ExecutionTimeLimit (New-TimeSpan -Hours 2) -ErrorAction Stop
    $kto = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -ErrorAction Stop
    # -Force nadpisuje zadanie o tej samej nazwie zamiast zakladac drugie
    Register-ScheduledTask -TaskName $NazwaZadania -Action $akcja -Trigger $wyzwalacz `
      -Settings $ustawienia -Principal $kto -Force -ErrorAction Stop `
      -Description "Lore - przyrostowe indeksowanie rozmow Claude Code" | Out-Null
  } catch {
    Blad "nie udalo sie zalozyc zadania: $($_.Exception.Message)"
    exit 1
  }
  Krok "indeks odswiezany co $InterwalMin min"
}

# ---------------------------------------------------------------- sprawdzenie instalacji

function Uruchom-Uv([string[]]$dalej) {
  # wspolne wywolanie: uv --directory <lore> run <dalej...>  -> kod wyjscia + caly tekst
  $wyjscie = & $script:Uv --directory $script:Lore run @dalej 2>&1
  return [pscustomobject]@{ Kod = $LASTEXITCODE; Tekst = ($wyjscie | Out-String) }
}

function Ostatnia-Linia($tekst) {
  ($tekst -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
}

function Sprawdz-Testy {
  $w = Uruchom-Uv @("pytest", "-q")
  $ile = [regex]::Match($w.Tekst, '(\d+) passed').Groups[1].Value
  if ($w.Kod -eq 0) {
    Zapisz-Wynik "testy modulu" $true "przeszlo: $ile"
  } else {
    Zapisz-Wynik "testy modulu" $false "pytest zwrocil kod $($w.Kod): $(Ostatnia-Linia $w.Tekst)"
  }
}

function Sprawdz-Import {
  $w = Uruchom-Uv @("python", "-c", "from lore import server")
  if ($w.Kod -eq 0) {
    Zapisz-Wynik "import serwera MCP" $true $null
  } else {
    Zapisz-Wynik "import serwera MCP" $false "$(Ostatnia-Linia $w.Tekst)"
  }
}

function Sprawdz-Indeksowanie {
  Krok "indeksuje rozmowy (pierwszy raz trwa - pobiera sie model)..."
  $w = Uruchom-Uv @("python", "-m", "lore.index")
  if ($w.Kod -eq 0) {
    Zapisz-Wynik "indeksowanie rozmow" $true $null
  } else {
    Zapisz-Wynik "indeksowanie rozmow" $false "kod $($w.Kod): $(Ostatnia-Linia $w.Tekst)"
  }
}

function Sprawdz-Baze {
  # liczby prosto z bazy - connect() zaklada schemat i jest idempotentne
  $kodPy = 'from lore.db import connect; c = connect(); ' +
           'print(c.execute("SELECT count(*) FROM files").fetchone()[0], c.execute("SELECT count(*) FROM chunks").fetchone()[0])'
  $w = Uruchom-Uv @("python", "-c", $kodPy)
  $m = [regex]::Match($w.Tekst, '(?m)^\s*(\d+)\s+(\d+)\s*$')
  if ($w.Kod -eq 0 -and $m.Success) {
    Zapisz-Wynik "zawartosc bazy" $true "plikow: $($m.Groups[1].Value), kawalkow: $($m.Groups[2].Value)"
  } else {
    Zapisz-Wynik "zawartosc bazy" $false "nie udalo sie odczytac statystyk z $($script:Baza)"
  }
}

function Sprawdz-Mcp {
  $lista = & $script:Claude mcp list 2>&1 | Out-String
  $linia = ($lista -split "`r?`n" | Where-Object { $_ -match "^\s*$NazwaMcp\s*:" } | Select-Object -First 1)
  if (-not $linia) {
    Zapisz-Wynik "serwer MCP widoczny" $false "claude mcp list nie pokazuje wpisu $NazwaMcp"
  } elseif ($linia -match "Connected") {
    Zapisz-Wynik "serwer MCP widoczny" $true "polaczony"
  } else {
    Zapisz-Wynik "serwer MCP widoczny" $false "wpis jest, ale nie jest polaczony"
  }
}

function Sprawdz-Instalacje {
  Naglowek "Sprawdzenie, czy to naprawde dziala"
  if ($Proba) {
    Plan "uv --directory $($script:Lore) run pytest -q"
    Plan "uv --directory $($script:Lore) run python -c ""from lore import server"""
    Plan "uv --directory $($script:Lore) run python -m lore.index   (jeden przebieg indeksowania)"
    Plan "odczyt z bazy: ile plikow i kawalkow zaindeksowano ($($script:Baza))"
    Plan "claude mcp list - czy $NazwaMcp jest polaczony"
    return
  }
  Sprawdz-Testy
  Sprawdz-Import
  Sprawdz-Indeksowanie
  Sprawdz-Baze
  Sprawdz-Mcp
}

function Podsumowanie {
  Naglowek "Podsumowanie"
  foreach ($k in $script:Kroki) {
    $etykieta = if ($k.Ok) { "OK  " } else { "BLAD" }
    $kolor    = if ($k.Ok) { "Green" } else { "Red" }
    $linia    = "  $etykieta  $($k.Nazwa)"
    if ($k.Opis) { $linia += " - $($k.Opis)" }
    Write-Host $linia -ForegroundColor $kolor
  }
  $zle = @($script:Kroki | Where-Object { -not $_.Ok })
  Write-Host ""
  if ($zle.Count -gt 0) {
    Blad "instalacja NIE jest kompletna: $($zle.Count) z $($script:Kroki.Count) sprawdzen nie przeszlo."
    exit 1
  }
  Write-Host "Gotowe. Zamknij i otworz okna Claude Code - serwer $NazwaMcp podepnie sie przy starcie." -ForegroundColor Green
  exit 0
}

# ---------------------------------------------------------------- przebieg

Write-Host ""
Write-Host "Instalator modulu pamieci rozmow Lore"
if ($Proba)        { Ostrzezenie "TRYB PROBNY - tylko pokazuje plan, niczego nie zmienia" }
if ($TylkoSprawdz) { Ostrzezenie "TRYB SPRAWDZANIA - tylko test juz zainstalowanego modulu" }

$sciezka = Resolve-Path $Zrodlo -ErrorAction SilentlyContinue
if (-not $sciezka) {
  Blad "nie ma takiego katalogu: $Zrodlo"
  exit 1
}
$Zrodlo = $sciezka.Path
$script:Lore = Join-Path $Zrodlo "lore"

Sprawdz-Warunki

if (-not $TylkoSprawdz) {
  Zapytaj-O-Zgode
  Zainstaluj-Srodowisko
  Zarejestruj-Mcp
  Zaloz-Zadanie
}

Sprawdz-Instalacje

if ($Proba) {
  Write-Host ""
  Write-Host "TRYB PROBNY - nic nie zostalo zmienione. Uruchom bez -Proba, zeby zainstalowac."
  exit 0
}

Podsumowanie
