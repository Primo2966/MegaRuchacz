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
$MinModelMB    = 200   # model wazy ~465 MB; kilka bajtow to przerwane pobranie, nie model

# Katalog danych Lore - liczony tak samo jak w lore\db.py: zmienna srodowiskowa ma
# pierwszenstwo (dzieki temu test idzie na katalogu tymczasowym, a nie na prawdziwej
# bazie), potem stary ~\.claude, jesli baza juz tam jest, a swieza instalacja -> ~\.lore.
$Poprzedni  = Join-Path $env:USERPROFILE ".claude"
$script:Dom = Join-Path $env:USERPROFILE ".lore"
if ((Test-Path (Join-Path $Poprzedni "lore.db")) -or (Test-Path (Join-Path $Poprzedni "historia.db"))) {
  $script:Dom = $Poprzedni
}
if ($env:CLAUDE_HISTORIA_HOME) { $script:Dom = $env:CLAUDE_HISTORIA_HOME }
if ($env:LORE_HOME)            { $script:Dom = $env:LORE_HOME }

$script:Uv     = $null
$script:Claude = $null
$script:Lore   = $null
$script:Baza   = Join-Path $script:Dom "lore.db"
$script:Modele = Join-Path $script:Dom "lore_models"
$script:Kroki  = @()   # wyniki sprawdzen do koncowego podsumowania
$script:Niepelne = @() # rzeczy, ktorych sprawdzenie NIE obejmuje - do podsumowania

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

# Sprawdzenie, ktore potwierdza tylko zapis na dysku albo obecnosc wpisu, nie
# nazywa sie "dziala". Takie rzeczy ida tutaj i wracaja w podsumowaniu wprost.
function Nie-Sprawdzono($tekst) {
  $script:Niepelne += $tekst
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

  # Serwer MCP rejestrujemy w KAZDYM narzedziu, ktore zastaniemy na tej maszynie.
  # Brak jednego z nich to normalna sytuacja - dopiero brak obu konczy instalacje.
  $cl = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cl) {
    $script:Claude = $cl.Source
    Krok "claude  : $($script:Claude)"
  } else {
    Krok "claude  : nie widze Claude Code na tej maszynie - pomijam"
  }

  # Codex rozpoznajemy tak samo jak narzedzia\wpisz-zasady.ps1: binarka w PATH
  # albo katalog domowy, ktory Codex po sobie zostawia.
  $script:Codex     = $null
  $script:CodexDom  = Join-Path $env:USERPROFILE ".codex"
  if ($env:CODEX_HOME) { $script:CodexDom = $env:CODEX_HOME }
  $script:CodexCfg  = Join-Path $script:CodexDom "config.toml"
  $script:CodexMa   = $false   # czy ten Codex zna wlasne polecenie "codex mcp add"
  $cx = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cx) { $script:Codex = $cx.Source }
  $script:CodexJest = [bool]$script:Codex -or (Test-Path $script:CodexDom)

  if ($script:Codex) {
    # pytamy sam Codex, czy zna "codex mcp" - to jedyny pewny sposob; grzebanie
    # w config.toml zostawiamy na wypadek, gdy polecenia nie ma (samo --help nic nie zmienia)
    $pomoc = & $script:Codex mcp --help 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $pomoc -match '\badd\b') { $script:CodexMa = $true }
    if ($script:CodexMa) {
      Krok "codex   : $($script:Codex) (rejestracja przez 'codex mcp add')"
    } else {
      Krok "codex   : $($script:Codex) (nie zna 'codex mcp add' - wpis pojdzie do $($script:CodexCfg))"
    }
  } elseif ($script:CodexJest) {
    Krok "codex   : nie ma binarki w PATH, ale jest $($script:CodexDom) - wpis pojdzie do $($script:CodexCfg)"
  } else {
    Krok "codex   : nie widze Codeksa na tej maszynie - pomijam"
  }

  if (-not $script:Claude -and -not $script:CodexJest) {
    $braki += "narzedzie, w ktorym dalo by sie zarejestrowac serwer MCP - nie ma ani Claude Code, ani Codeksa. Zainstaluj jedno z nich:  npm install -g @anthropic-ai/claude-code   albo   npm install -g @openai/codex"
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
  # Punkt 3 ma mowic prawde o TEJ maszynie - wymieniamy tylko te narzedzia,
  # ktore Sprawdz-Warunki naprawde na niej znalazlo.
  $gdzie = @()
  if ($script:Claude) { $gdzie += "Claude Code - przez 'claude mcp add', w zasiegu Twojego uzytkownika" }
  if ($script:CodexJest) {
    if ($script:CodexMa) { $gdzie += "Codex CLI - przez 'codex mcp add'" }
    else                 { $gdzie += "Codex CLI - wpisem w $($script:CodexCfg) (stary plik zostanie skopiowany obok)" }
  }
  $lista = ($gdzie | ForEach-Object { "        - $_" }) -join "`n"

  Naglowek "Co zaraz stanie sie na tym komputerze"
  Write-Host @"
  Lore to lokalna, przeszukiwalna pamiec Twoich rozmow z Claude Code.

  1. Powstanie LOKALNA baza SQLite z wyszukiwaniem pelnotekstowym i semantycznym
     (znajduje po sensie zdania, nie tylko po doslownym slowie).
        baza  : $($script:Baza)
  2. Przy pierwszym uruchomieniu pobierze sie z internetu model jezykowy, $RozmiarModelu.
        model : $($script:Modele)
  3. Serwer MCP o nazwie "$NazwaMcp" zostanie zarejestrowany wszedzie tam, gdzie
     widze narzedzie, ktore go przyjmie:
$lista
     UWAGA: od tej chwili agent AI ma dostep do TRESCI wszystkich Twoich rozmow
     zebranych na tej maszynie - ze wszystkich projektow i wszystkich okien.
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
  # jedno polecenie serwera dla wszystkich narzedzi - rozjazd miedzy nimi byloby
  # najgorszym mozliwym bledem: jedno okno widzi Lore, drugie sie wywala
  $polecenie = @($script:Uv, "--directory", $script:Lore, "run", "python", "-m", "lore.server")

  # ---- Claude Code
  if ($script:Claude) {
    $argumenty = @("mcp", "add", "--scope", "user", $NazwaMcp, "--") + $polecenie
    if ($Proba) {
      Plan "claude mcp remove $NazwaMcp -s user   (tylko jesli wpis juz istnieje)"
      Plan "claude $($argumenty -join ' ')"
    } else {
      # idempotentnie: stary wpis najpierw kasujemy, zeby ponowna instalacja nie zrobila duplikatu
      & $script:Claude mcp get $NazwaMcp > $null 2>&1
      if ($LASTEXITCODE -eq 0) {
        Krok "Claude Code : wpis o tej nazwie juz jest - usuwam stary"
        & $script:Claude mcp remove $NazwaMcp -s user > $null 2>&1
      }
      & $script:Claude @argumenty
      if ($LASTEXITCODE -ne 0) {
        Blad "rejestracja w Claude Code nie powiodla sie (kod $LASTEXITCODE)."
        exit 1
      }
      Krok "Claude Code : zarejestrowany dla uzytkownika - widoczny we wszystkich projektach"
    }
  } else {
    if ($Proba) { Plan "Claude Code : nie ma go na tej maszynie - pomijam" }
    else        { Krok "Claude Code : nie ma go na tej maszynie - pomijam" }
  }

  # ---- Codex CLI
  if (-not $script:CodexJest) {
    if ($Proba) { Plan "Codex       : nie ma go na tej maszynie - pomijam" }
    else        { Krok "Codex       : nie ma go na tej maszynie - pomijam" }
    return
  }

  if ($script:CodexMa) {
    $argCodex = @("mcp", "add", $NazwaMcp, "--") + $polecenie
    if ($Proba) {
      Plan "codex mcp remove $NazwaMcp   (tylko jesli wpis juz istnieje)"
      Plan "codex $($argCodex -join ' ')"
      return
    }
    & $script:Codex mcp get $NazwaMcp > $null 2>&1
    if ($LASTEXITCODE -eq 0) {
      Krok "Codex       : wpis o tej nazwie juz jest - usuwam stary"
      & $script:Codex mcp remove $NazwaMcp > $null 2>&1
    }
    & $script:Codex @argCodex
    if ($LASTEXITCODE -ne 0) {
      Blad "rejestracja w Codeksie nie powiodla sie (kod $LASTEXITCODE)."
      exit 1
    }
    Krok "Codex       : zarejestrowany poleceniem 'codex mcp add'"
    return
  }

  # Codex bez wlasnego polecenia - zostaje dopisanie tabeli do config.toml.
  # Idempotentnie: stara tabela [mcp_servers.<nazwa>] leci w calosci, dopiero
  # potem doklejamy swieza, a caly plik laduje wczesniej do kopii z data.
  if ($Proba) {
    Plan "kopia zapasowa $($script:CodexCfg) obok, z data w nazwie"
    Plan "usuniecie starej tabeli [mcp_servers.$NazwaMcp] z $($script:CodexCfg), jesli tam jest"
    Plan "dopisanie [mcp_servers.$NazwaMcp] z command/args: $($polecenie -join ' ')"
    return
  }
  $cytuj = { param($s) '"' + ((($s -replace '\\', '\\') -replace '"', '\"')) + '"' }
  if (-not (Test-Path $script:CodexDom)) { New-Item -ItemType Directory -Force -Path $script:CodexDom | Out-Null }
  $linie = @()
  if (Test-Path $script:CodexCfg) {
    $kopia = "$($script:CodexCfg).bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    Copy-Item $script:CodexCfg $kopia -Force
    Krok "Codex       : kopia zapasowa starej konfiguracji: $kopia"
    $pomijam = $false
    foreach ($l in (Get-Content $script:CodexCfg)) {
      # lapiemy tez podtabele w rodzaju [mcp_servers.lore.env] - inaczej zostalaby sierota
      if ($l -match "^\s*\[+\s*mcp_servers\.$NazwaMcp\s*(\.|\])") { $pomijam = $true; continue }
      if ($pomijam -and $l -match '^\s*\[') { $pomijam = $false }
      if (-not $pomijam) { $linie += $l }
    }
    # puste linie z konca ucinamy, zeby nie rosly przy kazdej kolejnej instalacji
    $ile = $linie.Count
    while ($ile -gt 0 -and -not $linie[$ile - 1].Trim()) { $ile-- }
    $linie = @($linie | Select-Object -First $ile)
    if ($linie.Count -gt 0) { $linie += "" }
  }
  $linie += "[mcp_servers.$NazwaMcp]"
  $linie += "command = " + (& $cytuj $polecenie[0])
  $linie += "args = [" + (($polecenie | Select-Object -Skip 1 | ForEach-Object { & $cytuj $_ }) -join ", ") + "]"
  # bez BOM - to plik TOML, a nie kazdy czytnik BOM wybacza
  [System.IO.File]::WriteAllLines($script:CodexCfg, [string[]]$linie, (New-Object System.Text.UTF8Encoding($false)))
  Krok "Codex       : wpis [mcp_servers.$NazwaMcp] jest w $($script:CodexCfg)"
}

# Jedno zrodlo prawdy o zadaniu: pytamy harmonogram, nie wlasna pamiec o tym,
# ze przed chwila cos zarejestrowalismy. Zwraca (Ok, Opis).
function Stan-Zadania {
  if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
    return [pscustomobject]@{ Ok = $false; Opis = "brak Get-ScheduledTask - nie mam czym sprawdzic harmonogramu" }
  }
  $z = Get-ScheduledTask -TaskName $NazwaZadania -ErrorAction SilentlyContinue
  if (-not $z) {
    return [pscustomobject]@{ Ok = $false; Opis = "harmonogram nie zna zadania $NazwaZadania" }
  }
  if ($z.State -eq "Disabled") {
    return [pscustomobject]@{ Ok = $false; Opis = "zadanie istnieje, ale jest wylaczone (Disabled) - nie uruchomi sie" }
  }
  $akcje = @($z.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" })
  $pasujace = @($akcje | Where-Object { $_ -match "lore\.index" })
  if ($pasujace.Count -eq 0) {
    return [pscustomobject]@{ Ok = $false; Opis = "zadanie istnieje, ale jego akcja nie uruchamia lore.index" }
  }
  return [pscustomobject]@{ Ok = $true; Opis = "stan: $($z.State)" }
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
  # UWAGA - sprawdzone 2026-09-16: zakladanie zadania przez obiekty
  # (New-ScheduledTaskPrincipal + Register-ScheduledTask -Principal) konczy sie
  # "Odmowa dostepu" u zwyklego, niepodniesionego uzytkownika. Ta sama operacja
  # podana jako XML przechodzi bez uprawnien administratora. Dlatego XML.
  try {
    $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $start = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    $argXml = [System.Security.SecurityElement]::Escape($argumenty)
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Lore - przyrostowe indeksowanie rozmow</Description>
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
    <Enabled>true</Enabled>
  </Settings>
  <Triggers>
    <TimeTrigger>
      <StartBoundary>$start</StartBoundary>
      <Repetition>
        <Interval>PT${InterwalMin}M</Interval>
      </Repetition>
      <Enabled>true</Enabled>
    </TimeTrigger>
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
  # UWAGA - audyt na obcej maszynie: instalator wypisal "indeks odswiezany co 10 min",
  # a Get-ScheduledTask nie znajdowal potem zadnego zadania. Samo przejscie
  # Register-ScheduledTask bez wyjatku niczego nie dowodzi - pytamy harmonogram.
  $stan = Stan-Zadania
  if (-not $stan.Ok) {
    Blad "zadanie $NazwaZadania nie powstalo: $($stan.Opis)"
    Krok "harmonogram przyjal polecenie, ale zadania tam nie ma - sprawdz zasady tej maszyny"
    exit 1
  }
  Krok "zadanie $NazwaZadania jest w harmonogramie ($($stan.Opis)) - indeks odswiezany co $InterwalMin min"
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

function Sprawdz-Zadanie {
  $stan = Stan-Zadania
  Zapisz-Wynik "zadanie w harmonogramie ($NazwaZadania)" $stan.Ok $stan.Opis
}

function Sprawdz-Model {
  # Model sciaga sie leniwie, przy pierwszym liczeniu wektora. Sprawdzenie "czy
  # katalog istnieje" przechodzilo na maszynie, ktora nigdy nic nie indeksowala,
  # bo model nie byl wtedy potrzebny. Dlatego liczymy wektor NAPRAWDE - to
  # wymusza pobranie i od razu pokazuje, czy model dziala.
  Krok "sprawdzam model semantyczny (jesli go nie ma, pobiera sie teraz, $RozmiarModelu)..."
  $kodPy = "from pathlib import Path; from lore.db import EMBED_DIM, MODELS_DIR, embed_query; " +
           "v = embed_query('czy ten model dziala'); " +
           "mb = sum(f.stat().st_size for f in Path(MODELS_DIR).rglob('*') if f.is_file()) // (1024*1024); " +
           "print('MODEL', len(v), EMBED_DIM, mb)"
  $w = Uruchom-Uv @("python", "-c", $kodPy)
  $m = [regex]::Match($w.Tekst, 'MODEL (\d+) (\d+) (\d+)')
  if ($w.Kod -ne 0 -or -not $m.Success) {
    Zapisz-Wynik "model semantyczny" $false "nie udalo sie policzyc wektora: $(Ostatnia-Linia $w.Tekst)"
    return
  }
  $wymiar     = [int]$m.Groups[1].Value
  $oczekiwany = [int]$m.Groups[2].Value
  $mb         = [int]$m.Groups[3].Value
  if ($wymiar -ne $oczekiwany) {
    Zapisz-Wynik "model semantyczny" $false "wektor ma $wymiar wymiarow zamiast $oczekiwany"
  } elseif ($mb -lt $MinModelMB) {
    Zapisz-Wynik "model semantyczny" $false "katalog modelu ma $mb MB, a powinien miec co najmniej $MinModelMB MB - pobranie nie doszlo do konca ($($script:Modele))"
  } else {
    Zapisz-Wynik "model semantyczny" $true "wektor $wymiar wymiarow, model na dysku: $mb MB"
  }
}

function Sprawdz-Baze {
  # liczby prosto z bazy - connect() zaklada schemat i jest idempotentne
  # UWAGA: cudzyslowy podwojne wewnatrz argumentu gina przy przekazywaniu do
  # zewnetrznego programu w PowerShell 5.1 - Python dostaje SQL bez cudzyslowow
  # i wywala sie na skladni. Dlatego w kodzie Pythona sa pojedyncze.
  #
  # Zero plikow i zero kawalkow samo w sobie nie znaczy nic: tak samo wyglada
  # swieza maszyna i calkiem zepsuty indekser. Rozroznia je dopiero liczba
  # transkryptow, ktore indekser POWINIEN widziec - stad find_files().
  $kodPy = "from lore.db import connect; from lore.index import find_files; c = connect(); " +
           "print('BAZA', c.execute('SELECT count(*) FROM files').fetchone()[0], " +
           "c.execute('SELECT count(*) FROM chunks').fetchone()[0], len(find_files()))"
  $w = Uruchom-Uv @("python", "-c", $kodPy)
  $m = [regex]::Match($w.Tekst, 'BAZA (\d+) (\d+) (\d+)')
  if ($w.Kod -ne 0 -or -not $m.Success) {
    Zapisz-Wynik "zawartosc bazy" $false "nie udalo sie odczytac statystyk z $($script:Baza): $(Ostatnia-Linia $w.Tekst)"
    return
  }
  $plikow   = [int]$m.Groups[1].Value
  $kawalkow = [int]$m.Groups[2].Value
  $zrodel   = [int]$m.Groups[3].Value
  if ($zrodel -eq 0 -and $plikow -eq 0) {
    Zapisz-Wynik "zawartosc bazy" $true "na tej maszynie nie ma jeszcze czego indeksowac - zero transkryptow, zero wpisow"
  } elseif ($plikow -eq 0) {
    Zapisz-Wynik "zawartosc bazy" $false "indekser widzi $zrodel transkryptow, a baza jest pusta - indeksowanie nie zadzialalo"
  } elseif ($kawalkow -eq 0) {
    Zapisz-Wynik "zawartosc bazy" $false "zaindeksowano $plikow plikow, ale zero fragmentow - nie ma czego szukac"
  } else {
    Zapisz-Wynik "zawartosc bazy" $true "plikow: $plikow z $zrodel widocznych, kawalkow: $kawalkow"
  }
}

function Sprawdz-Mcp-Wpis {
  # To jest sprawdzenie REJESTRACJI, nie dzialania - lista wpisow pokaze serwer
  # takze na maszynie, na ktorej on nie wstaje. Od dzialania jest handshake nizej.
  # Narzedzia, ktorego tu nie ma, NIE zaliczamy na zielono - mowimy, ze pominiete.
  if ($script:Claude) {
    $lista = & $script:Claude mcp list 2>&1 | Out-String
    $linia = ($lista -split "`r?`n" | Where-Object { $_ -match "^\s*$NazwaMcp\s*:" } | Select-Object -First 1)
    if (-not $linia) {
      Zapisz-Wynik "serwer MCP w Claude Code" $false "claude mcp list nie pokazuje wpisu $NazwaMcp"
    } else {
      Zapisz-Wynik "serwer MCP w Claude Code" $true "wpis $NazwaMcp jest w konfiguracji uzytkownika"
    }
    Nie-Sprawdzono "czy Twoj klient Claude Code podepnie serwer $NazwaMcp przy starcie - to widac dopiero w nowym oknie"
  } else {
    Write-Host "  --    serwer MCP w Claude Code - pominiete, nie ma Claude Code na tej maszynie" -ForegroundColor DarkGray
  }

  if (-not $script:CodexJest) {
    Write-Host "  --    serwer MCP w Codeksie - pominiete, nie ma Codeksa na tej maszynie" -ForegroundColor DarkGray
    return
  }
  if ($script:CodexMa) {
    $opis = & $script:Codex mcp get $NazwaMcp 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
      Zapisz-Wynik "serwer MCP w Codeksie" $true "codex mcp get $NazwaMcp znajduje wpis"
    } else {
      Zapisz-Wynik "serwer MCP w Codeksie" $false "codex mcp get $NazwaMcp nic nie znajduje: $(Ostatnia-Linia $opis)"
    }
  } else {
    $tresc = ""
    if (Test-Path $script:CodexCfg) { $tresc = Get-Content $script:CodexCfg -Raw }
    if ($tresc -match "(?m)^\s*\[\s*mcp_servers\.$NazwaMcp\s*\]") {
      Zapisz-Wynik "serwer MCP w Codeksie" $true "tabela [mcp_servers.$NazwaMcp] jest w $($script:CodexCfg)"
    } else {
      Zapisz-Wynik "serwer MCP w Codeksie" $false "nie ma tabeli [mcp_servers.$NazwaMcp] w $($script:CodexCfg)"
    }
  }
  Nie-Sprawdzono "czy Codex wstanie z serwerem $NazwaMcp - wpis jest, ale podpiecie widac dopiero w nowej sesji Codeksa"
}

# Proba serwera MCP - leci do pliku tymczasowego i odpala sie pod Pythonem z uv.
# Sam stdlib, zeby dzialala niezaleznie od tego, co siedzi w .venv modulu.
$script:ProbaMcp = @'
"""Rozmowa z serwerem MCP po stdio: initialize -> tools/list -> tools/call lore_stats.
Kod wyjscia 0 i linia "MCP OK <liczba narzedzi>" tylko wtedy, gdy serwer naprawde odpowiedzial."""
import json
import queue
import subprocess
import sys
import threading

CZAS = 180  # sekund na odpowiedz - pierwszy start moze jeszcze pobierac model


def main():
    polecenie = sys.argv[1:]
    if not polecenie:
        print("proba MCP: brak polecenia serwera")
        return 1
    p = subprocess.Popen(polecenie, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, encoding="utf-8", errors="replace", bufsize=1)
    linie = queue.Queue()
    bledy = []

    def czytaj_wyjscie():
        for linia in p.stdout:
            linie.put(linia)
        linie.put(None)

    def czytaj_bledy():
        for linia in p.stderr:  # serwer loguje na stderr - nie wolno zapchac rury
            bledy.append(linia.rstrip())

    threading.Thread(target=czytaj_wyjscie, daemon=True).start()
    threading.Thread(target=czytaj_bledy, daemon=True).start()

    def wyslij(obj):
        p.stdin.write(json.dumps(obj) + "\n")
        p.stdin.flush()

    def odpowiedz(ident):
        # w strumieniu sa tez notyfikacje - czekamy na swoje id
        while True:
            linia = linie.get(timeout=CZAS)
            if linia is None:
                raise RuntimeError("serwer zamknal wyjscie bez odpowiedzi")
            linia = linia.strip()
            if not linia:
                continue
            try:
                d = json.loads(linia)
            except ValueError:
                continue
            if d.get("id") == ident:
                if "error" in d:
                    raise RuntimeError("serwer odpowiedzial bledem: %s" % d["error"])
                return d.get("result", {})

    try:
        wyslij({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "instaluj-lore", "version": "1"}}})
        odpowiedz(1)
        wyslij({"jsonrpc": "2.0", "method": "notifications/initialized"})
        wyslij({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        narzedzia = [t.get("name") for t in odpowiedz(2).get("tools", [])]
        if "lore_search" not in narzedzia:
            print("proba MCP: serwer nie wystawia lore_search (widze: %s)" % ", ".join(narzedzia))
            return 1
        # lore_stats tylko czyta - bezpieczne, a dotyka bazy, wiec cos naprawde robi
        wyslij({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                "params": {"name": "lore_stats", "arguments": {}}})
        odpowiedz(3)
        print("MCP OK %d" % len(narzedzia))
        return 0
    except queue.Empty:
        print("proba MCP: serwer nie odpowiedzial w %d s" % CZAS)
        return 1
    except Exception as e:
        ogon = "; ".join([b for b in bledy if b][-3:])
        print("proba MCP: %s%s" % (e, (" | " + ogon) if ogon else ""))
        return 1
    finally:
        try:
            p.kill()
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
'@

function Sprawdz-Mcp-Dziala {
  # Prawdziwe wywolanie: uruchamiamy serwer tym samym poleceniem, ktore trafilo
  # do konfiguracji, i rozmawiamy z nim po JSON-RPC - initialize, tools/list,
  # tools/call lore_stats. Zepsuty serwer nie ma jak tego przejsc.
  $plikProby = Join-Path $env:TEMP "lore-mcp-proba-$PID.py"
  [System.IO.File]::WriteAllText($plikProby, $script:ProbaMcp, (New-Object System.Text.UTF8Encoding($false)))
  try {
    $w = Uruchom-Uv @("python", $plikProby, $script:Uv, "--directory", $script:Lore, "run", "python", "-m", "lore.server")
    if ($w.Kod -eq 0 -and $w.Tekst -match 'MCP OK (\d+)') {
      Zapisz-Wynik "serwer MCP odpowiada na wywolanie" $true "handshake i lore_stats przeszly, narzedzi: $($Matches[1])"
    } else {
      Zapisz-Wynik "serwer MCP odpowiada na wywolanie" $false "$(Ostatnia-Linia $w.Tekst)"
    }
  } finally {
    Remove-Item $plikProby -Force -ErrorAction SilentlyContinue
  }
}

function Sprawdz-Instalacje {
  Naglowek "Sprawdzenie, czy to naprawde dziala"
  if ($Proba) {
    Plan "uv --directory $($script:Lore) run pytest -q"
    Plan "uv --directory $($script:Lore) run python -c ""from lore import server"""
    Plan "Get-ScheduledTask $NazwaZadania - czy zadanie istnieje i nie jest wylaczone"
    Plan "uv --directory $($script:Lore) run python -m lore.index   (jeden przebieg indeksowania)"
    Plan "policzenie wektora modelem i rozmiar katalogu $($script:Modele) (min. $MinModelMB MB)"
    Plan "odczyt z bazy: ile plikow i kawalkow wobec liczby widocznych transkryptow ($($script:Baza))"
    if ($script:Claude) { Plan "claude mcp list - czy wpis $NazwaMcp jest w konfiguracji Claude Code" }
    else                { Plan "Claude Code - pominiete, nie ma go na tej maszynie" }
    if (-not $script:CodexJest) { Plan "Codex - pominiete, nie ma go na tej maszynie" }
    elseif ($script:CodexMa)    { Plan "codex mcp get $NazwaMcp - czy Codex zna ten wpis" }
    else                        { Plan "czy w $($script:CodexCfg) jest tabela [mcp_servers.$NazwaMcp]" }
    Plan "handshake JSON-RPC z serwerem ${NazwaMcp}: initialize + tools/list + lore_stats"
    return
  }
  Sprawdz-Testy
  Sprawdz-Import
  Sprawdz-Zadanie
  Sprawdz-Indeksowanie
  Sprawdz-Model
  Sprawdz-Baze
  Sprawdz-Mcp-Wpis
  Sprawdz-Mcp-Dziala
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
  if ($script:Niepelne.Count -gt 0) {
    Write-Host ""
    Write-Host "  Czego to sprawdzenie NIE obejmuje:" -ForegroundColor DarkGray
    foreach ($n in $script:Niepelne) { Write-Host "  -  $n" -ForegroundColor DarkGray }
  }
  $zle = @($script:Kroki | Where-Object { -not $_.Ok })
  Write-Host ""
  if ($zle.Count -gt 0) {
    Blad "instalacja NIE jest kompletna: $($zle.Count) z $($script:Kroki.Count) sprawdzen nie przeszlo."
    exit 1
  }
  $gdzie = @()
  if ($script:Claude)    { $gdzie += "okna Claude Code" }
  if ($script:CodexJest) { $gdzie += "sesje Codeksa" }
  $co = if ($gdzie.Count -gt 0) { $gdzie -join " i " } else { "okna narzedzia AI" }
  Write-Host "Gotowe. Zamknij i otworz $co - serwer $NazwaMcp podepnie sie przy starcie." -ForegroundColor Green
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
