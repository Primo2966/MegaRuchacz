# narzedzia\instalacja\lore-czesci.ps1 - czesci instalacji Lore, kazda do zalozenia i do zdjecia osobno.
#
# Do 0.26 wszystko siedzialo w jednym narzedzia\instaluj-lore.ps1: srodowisko, MCP, zadanie
# LoreIndex, nadzorca i przeliczanie szly razem, a usunac nie dalo sie niczego. Instalator
# z wyborem modulow potrzebuje ich osobno - modul "wiedza" bierze rdzen (srodowisko + baza +
# indeks BEZ modelu), modul "lore" doklada model wektorow i serwer MCP. Stad ten plik:
#
#   srodowisko  uv sync w <repo>\lore (.venv, ~196 MB)             Lore-Zainstaluj-Srodowisko / Lore-Usun-Srodowisko
#   indeks      zadanie LoreIndex co 10 min; z -TylkoTekst bez       Lore-Zaloz-Zadanie-Indeksu / Lore-Usun-Zadanie-Indeksu
#               modelu (python -m lore.index --text-only)
#   baza        lore.db (schemat i zapis trybu indeksu)              Lore-Zapisz-Tryb / Lore-Usun-Dane
#   model       model wektorow ~496 MB w <dom Lore>\lore_models      Lore-Pobierz-Model / Lore-Usun-Model
#   mcp         serwer "lore" w Claude Code, Codeksie i opencode     Lore-Zarejestruj-Mcp / Lore-Wyrejestruj-Mcp
#   sprzatanie  stare zadania (MegaRuchaczOdswiez, LoreCykl...)      Lore-Usun-Stare-Zadania
# Nadzorca NIE jest czescia Lore - zaklada go zasobnik\zainstaluj-zasobnik.ps1 (modul baza);
# stare wywolanie instaluj-lore.ps1 dalej go wola, tak jak przed podzialem.
#
# Wczytuja go kropka: narzedzia\instaluj-lore.ps1 (okno konsoli, stary wyglad) i skrypty modulow
# (przez narzedzia\instalacja\wspolne.ps1). Wolajacy dostarcza zmienne $Zrodlo, $KatalogDomowy,
# $Proba i funkcje Krok, Plan, Ostrzezenie - kazdy w swoim formacie wyjscia. Potem wola
# Lore-Przygotuj. Blad, po ktorym dalej nie ma sensu isc, leci wyjatkiem (throw) z trescia po
# polsku dla laika - wolajacy decyduje, czy konczy, czy melduje i idzie dalej. Nic tu nie milczy:
# czego nie dalo sie zrobic, to albo wyjatek, albo Ostrzezenie.

# ---------------------------------------------------------------- stale (te same nazwy co w monolicie)

$script:NazwaMcp      = "lore"
$script:NazwaZadania  = "LoreIndex"
$script:InterwalMin   = 10
# Zadanie, ktore kiedys co godzine odswiezalo samo narzedzie. Aktualizacja idzie dzis wylacznie
# przy starcie sesji (hook narzedzia AI), wiec zadanie okresowe jest zbedne. Nazwa zostaje po to,
# zeby je zdjac z maszyn, na ktorych powstalo.
$script:NazwaZadaniaOdswiez = "MegaRuchaczOdswiez"
# Zadania cyklu wiedzy o sztywnych godzinach - cykl rusza dzis przy pierwszej sesji dnia
# (straznik) i z dozoru nadzorcy, wiec kazde z nich albo dublowalo robote, albo nie robilo nic:
#   LoreCykl, LoreCyklPonow - caly cykl przy zalogowaniu i jego ponawianie co 10 min
#   LoreFacts (08:05), LoreWiedza (poniedzialki 08:25) - kroki 1/2 i 2/2 cyklu
# LoreIndex ZOSTAJE (to warunek, zeby bylo z czego wylawiac), LoreKoszt tez (punkt odniesienia).
$script:ZadaniaCyklu  = @("LoreCykl", "LoreCyklPonow", "LoreFacts", "LoreWiedza")
# Model wyszukiwania po sensie: sdadas/mmlw-retrieval-roberta-base (768 wym.) od 2026-09-24.
# Nazwa i wymiar siedza w lore\lore\db.py; katalog modelu nazywa sie jak model (/ -> --).
$script:RozmiarModelu = "~496 MB"
$script:KatalogModelu = "sdadas--mmlw-retrieval-roberta-base"
$script:MinModelMB    = 200   # model wazy ~496 MB; kilka bajtow to przerwane pobranie, nie model
# Przeliczenie archiwum na nowy model (lore.migrate) - szacunek z 2026-09-24 dla archiwum rzedu
# kilkudziesieciu tysiecy fragmentow; postep i prognoze pisze lore.migration.json.
$script:CzasPrzeliczania = "~2-4 h"
# Pliki bazy Lore obok lore.db - tyle zdejmuje Lore-Usun-Dane i nic poza tym.
$script:PlikiBazyLore = @("lore.db", "lore.db-wal", "lore.db-shm", "lore.lock", "lore.migration.json",
                          "lore.migration.lock", "lore.migrate.log", "lore.migrate.out.log",
                          "lore.index.log", "lore.index.out.log")

# ---------------------------------------------------------------- przygotowanie

# Katalog danych Lore - liczony DOKLADNIE tak jak w lore\lore\db.py (_data_home): zmienna
# srodowiskowa ma pierwszenstwo, potem ~\.claude, jesli baza juz tam jest (stara instalacja nie
# moze zgubic historii), a swieza instalacja -> ~\.lore. Rozjazd z Pythonem oznaczalby, ze
# instalator usuwa albo sprawdza inna baze niz ta, ktorej uzywa Lore.
function Lore-Katalog-Danych([string]$dom) {
  if ($env:LORE_HOME) { return $env:LORE_HOME }
  if ($env:CLAUDE_HISTORIA_HOME) { return $env:CLAUDE_HISTORIA_HOME }
  $poprzedni = Join-Path $dom ".claude"
  if ((Test-Path (Join-Path $poprzedni "lore.db")) -or (Test-Path (Join-Path $poprzedni "historia.db"))) { return $poprzedni }
  return (Join-Path $dom ".lore")
}

# Najpierw PATH, potem miejsca, pod ktore uv laduje sam albo z WinGeta, i katalog programow
# MegaRuchacza (narzedzia\instalacja\zaleznosci.ps1 kladzie tam wersje przenosna).
function Znajdz-Uv {
  $cmd = Get-Command uv -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return $cmd.Source }
  $kandydaci = @()
  if ($env:LOCALAPPDATA) {
    $kandydaci += (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\uv.exe")
    $kandydaci += (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\astral-sh.uv_*\uv.exe")
    $kandydaci += (Join-Path $env:LOCALAPPDATA "MegaRuchacz\uv\uv.exe")
  }
  if ($env:USERPROFILE) {
    $kandydaci += (Join-Path $env:USERPROFILE ".local\bin\uv.exe")
    $kandydaci += (Join-Path $env:USERPROFILE ".cargo\bin\uv.exe")
  }
  foreach ($k in $kandydaci) {
    $traf = Get-ChildItem -Path $k -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($traf) { return $traf.FullName }
  }
  return $null
}

function Lore-Przygotuj {
  $script:Lore   = Join-Path $Zrodlo "lore"
  $script:Dom    = Lore-Katalog-Danych $KatalogDomowy
  $script:Baza   = Join-Path $script:Dom "lore.db"
  $script:Modele = Join-Path $script:Dom "lore_models"
  $script:Uv     = Znajdz-Uv
  $script:PythonVenv = Join-Path $script:Lore ".venv\Scripts\python.exe"
}

# Wywolanie programu z przechwyceniem calego wyjscia (stdout + stderr). $ErrorActionPreference
# = Continue tylko na czas wywolania: uv pisze postep na stderr, a przy "Stop" pierwsza taka
# linia konczylaby skrypt wyjatkiem NativeCommandError, choc nic zlego sie nie stalo.
function Lore-Wolaj([string]$program, [string[]]$argumenty) {
  $stare = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $global:LASTEXITCODE = 0
    $wy = & $program @argumenty 2>&1
    $kod = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $stare
  }
  return [pscustomobject]@{ Kod = $kod; Tekst = (@($wy | ForEach-Object { "$_" }) -join "`n") }
}

function Uruchom-Uv([string[]]$dalej) {
  # wspolne wywolanie: uv --directory <lore> run <dalej...>  -> kod wyjscia + caly tekst
  return (Lore-Wolaj $script:Uv (@("--directory", $script:Lore, "run") + $dalej))
}

function Ostatnia-Linia($tekst) {
  ($tekst -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
}

# Usuwa plik albo katalog razem z zawartoscia. Zwraca $null, gdy go juz nie ma, inaczej powod.
# PowerShell 5.1 (Remove-Item) nie przechodzi przez sciezki dluzsze niz 260 znakow, a .venv ma
# gleboko zagniezdzone pakiety (fastembed\late_interaction_multimodal\...) - wtedy rd/del
# z przedrostkiem \\?\, ktory tego limitu nie ma. Plik trzymany przez proces zostaje - i to mowimy.
function Usun-Drzewo([string]$sciezka) {
  if (-not (Test-Path -LiteralPath $sciezka)) { return $null }
  $blad = $null
  try { Remove-Item -LiteralPath $sciezka -Recurse -Force -ErrorAction Stop } catch { $blad = $_.Exception.Message }
  if (Test-Path -LiteralPath $sciezka) {
    $pelna = (Resolve-Path -LiteralPath $sciezka).ProviderPath
    $dluga = if ($pelna.StartsWith("\\")) { "\\?\UNC\" + $pelna.Substring(2) } else { "\\?\" + $pelna }
    $katalog = (Get-Item -LiteralPath $pelna -Force).PSIsContainer
    $polecenie = if ($katalog) { "rd /s /q `"$dluga`"" } else { "del /f /q `"$dluga`"" }
    $wy = & cmd.exe /d /c $polecenie 2>&1
    if (Test-Path -LiteralPath $sciezka) { return $(if ($wy) { (@($wy) -join " ").Trim() } elseif ($blad) { $blad } else { "nadal jest" }) }
  }
  return $null
}

# Python ze srodowiska Lore WPROST, bez "uv run": sprawdzenie stanu nie moze po cichu zakladac
# ani synchronizowac srodowiska (uv run robi to sam, gdy .venv nie ma albo jest nieaktualne).
# Katalog roboczy = <repo>\lore, bo projekt nie jest instalowany jako pakiet (package = false).
function Lore-Python-Wprost([string]$kodPy) {
  if (-not (Test-Path $script:PythonVenv)) { return [pscustomobject]@{ Kod = -1; Tekst = "nie ma srodowiska Lore ($($script:PythonVenv))" } }
  $tu = Get-Location
  try {
    Set-Location -LiteralPath $script:Lore
    return (Lore-Wolaj $script:PythonVenv @("-c", $kodPy))
  } finally {
    Set-Location -LiteralPath $tu
  }
}

# Python >= 3.12 widziany przez uv (zna swoje wlasne instalacje, PATH-u nie potrzebuje).
function Lore-Znajdz-Pythona {
  if (-not $script:Uv) { return $null }
  $w = Lore-Wolaj $script:Uv @("python", "find", ">=3.12")
  if ($w.Kod -ne 0) { return $null }
  return (Ostatnia-Linia $w.Tekst)
}

# ---------------------------------------------------------------- srodowisko Pythona

function Lore-Srodowisko-Jest { return (Test-Path $script:PythonVenv) }

function Lore-Zainstaluj-Srodowisko {
  if ($Proba) { Plan "uv --directory $($script:Lore) sync   (zaleznosci Pythona do $($script:Lore)\.venv, ~196 MB)"; return }
  if (-not $script:Uv) { throw "nie ma programu uv - bez niego nie zaloze srodowiska Pythona Lore" }
  $w = Lore-Wolaj $script:Uv @("--directory", $script:Lore, "sync")
  if ($w.Kod -ne 0) {
    $powod = Ostatnia-Linia $w.Tekst
    if ($w.Tekst -match '(?i)(failed to fetch|dns|connect|timed out|network|offline)') {
      throw "uv sync nie pobral zaleznosci (kod $($w.Kod)) - brak internetu albo serwer pypi.org niedostepny: $powod"
    }
    throw "uv sync nie powiodl sie (kod $($w.Kod)): $powod"
  }
  Krok "srodowisko Pythona Lore gotowe ($($script:Lore)\.venv)"
}

# Procesy Pythona ze srodowiska TEGO repo (serwer MCP z otwartego okna, indeksowanie, przeliczanie).
# Po sciezce pliku wykonywalnego - inna kopia narzedzia (np. testowa) nie jest nasza.
function Lore-Procesy-Srodowiska {
  $korzen = (Join-Path $script:Lore ".venv").TrimEnd('\') + '\'
  try {
    return @(Get-CimInstance Win32_Process -ErrorAction Stop |
              Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($korzen, [System.StringComparison]::OrdinalIgnoreCase) })
  } catch {
    Ostrzezenie "nie moge zajrzec do listy procesow ($($_.Exception.Message)) - nie wiem, czy cos uzywa srodowiska Lore"
    return @()
  }
}

# Zwraca $true, gdy srodowiska juz nie ma. Pliki trzymane przez dzialajacy proces nie znikna -
# wtedy Ostrzezenie z sciezka i powodem, a nie udawanie, ze sie udalo.
function Lore-Usun-Srodowisko {
  $venv = Join-Path $script:Lore ".venv"
  if (-not (Test-Path $venv)) { Krok "srodowiska Pythona Lore nie ma - nie ma czego usuwac"; return $true }
  $procesy = @(Lore-Procesy-Srodowiska)
  if ($Proba) {
    if ($procesy.Count -gt 0) { Plan "zatrzymalbym $($procesy.Count) proces(y) Lore (PID $(($procesy | ForEach-Object { $_.ProcessId }) -join ', '))" }
    Plan "usunalbym $venv (~196 MB)"
    return $true
  }
  foreach ($p in $procesy) {
    try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; Krok "zatrzymany proces Lore (PID $($p.ProcessId)) - uzywal usuwanego srodowiska" }
    catch { Ostrzezenie "nie udalo sie zatrzymac procesu Lore PID $($p.ProcessId): $($_.Exception.Message)" }
  }
  if ($procesy.Count -gt 0) { Start-Sleep -Milliseconds 800 }
  $blad = Usun-Drzewo $venv
  if ($blad) {
    Ostrzezenie "nie udalo sie usunac calego $venv ($blad) - pewnie trzyma go otwarte okno Claude Code z serwerem lore. Zamknij okna i uruchom usuwanie jeszcze raz."
    return $false
  }
  Krok "usuniete srodowisko Pythona Lore ($venv, ~196 MB)"
  return $true
}

# ---------------------------------------------------------------- zadanie LoreIndex

# Jedno zrodlo prawdy o zadaniu: pytamy harmonogram, nie wlasna pamiec o tym, ze przed chwila
# cos zarejestrowalismy. $wzorzec to fragment akcji, po ktorym poznajemy, ze to NASZE zadanie,
# a nie cudze o tej samej nazwie. Zwraca Ok, Jest, Opis, Argumenty.
function Stan-Zadania($nazwa, $wzorzec) {
  if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
    return [pscustomobject]@{ Ok = $false; Jest = $null; Opis = "brak Get-ScheduledTask - nie mam czym sprawdzic harmonogramu"; Argumenty = "" }
  }
  $z = Get-ScheduledTask -TaskName $nazwa -ErrorAction SilentlyContinue
  if (-not $z) {
    return [pscustomobject]@{ Ok = $false; Jest = $false; Opis = "harmonogram nie zna zadania $nazwa"; Argumenty = "" }
  }
  $akcje = @($z.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" })
  $razem = $akcje -join " | "
  if ($z.State -eq "Disabled") {
    return [pscustomobject]@{ Ok = $false; Jest = $true; Opis = "zadanie istnieje, ale jest wylaczone (Disabled) - nie uruchomi sie"; Argumenty = $razem }
  }
  $pasujace = @($akcje | Where-Object { $_ -match $wzorzec })
  if ($pasujace.Count -eq 0) {
    return [pscustomobject]@{ Ok = $false; Jest = $true; Opis = "zadanie istnieje, ale jego akcja nie uruchamia $wzorzec"; Argumenty = $razem }
  }
  return [pscustomobject]@{ Ok = $true; Jest = $true; Opis = "stan: $($z.State)"; Argumenty = $razem }
}

# Rejestracja zadania przez XML.
# UWAGA - sprawdzone 2026-09-16: zakladanie zadania przez obiekty (New-ScheduledTaskPrincipal
# + Register-ScheduledTask -Principal) konczy sie "Odmowa dostepu" u zwyklego, niepodniesionego
# uzytkownika. Ta sama operacja podana jako XML przechodzi bez uprawnien administratora.
# -Force nadpisuje zadanie o tej samej nazwie - ponowna instalacja podmienia, nie doklada.
function Zarejestruj-Zadanie($nazwa, $opis, $argumenty, $interwal) {
  $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
  $start = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
  $argXml = [System.Security.SecurityElement]::Escape($argumenty)
  $opisXml = [System.Security.SecurityElement]::Escape($opis)
  $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>$opisXml</Description>
    <URI>\$nazwa</URI>
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
        <Interval>PT${interwal}M</Interval>
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
  Register-ScheduledTask -TaskName $nazwa -Xml $xml -Force -ErrorAction Stop | Out-Null
}

# Argumenty zadania. conhost --headless: zadanie chodzi co kilkanascie minut i nikt nie chce
# ogladac mrugajacego okna konsoli. --text-only = indeks bez modelu (modul wiedza bez lore).
function Argumenty-Indeksu([bool]$tylkoTekst = $false) {
  $a = "--headless `"$($script:Uv)`" --directory `"$($script:Lore)`" run python -m lore.index"
  if ($tylkoTekst) { $a += " --text-only" }
  return $a
}

# Stan zadania LoreIndex razem z trybem, w jakim chodzi: TylkoTekst = $true/$false, $null gdy
# zadania nie ma albo nie jest nasze.
function Lore-Stan-Indeksu {
  $s = Stan-Zadania $script:NazwaZadania "lore\.index"
  $tryb = $null
  if ($s.Ok) { $tryb = [bool]($s.Argumenty -match '--text-only') }
  $s | Add-Member -NotePropertyName TylkoTekst -NotePropertyValue $tryb -Force
  return $s
}

function Lore-Zaloz-Zadanie-Indeksu([bool]$tylkoTekst = $false) {
  $argumenty = Argumenty-Indeksu $tylkoTekst
  $jak = if ($tylkoTekst) { "bez modelu wektorow (tylko tekst)" } else { "z wektorami (pelne Lore)" }
  if ($Proba) {
    Plan "zadanie $($script:NazwaZadania) w Harmonogramie: indeks rozmow co $($script:InterwalMin) min, $jak"
    Plan "  akcja: conhost.exe $argumenty"
    return
  }
  if (-not $script:Uv) { throw "nie ma programu uv - zadanie $($script:NazwaZadania) nie mialoby czym indeksowac" }
  try {
    Zarejestruj-Zadanie $script:NazwaZadania "Lore - przyrostowe indeksowanie rozmow" $argumenty $script:InterwalMin
  } catch {
    throw "nie udalo sie zalozyc zadania $($script:NazwaZadania): $($_.Exception.Message) (jesli to 'Odmowa dostepu' - zasady tej maszyny moga wymagac uprawnien administratora)"
  }
  # UWAGA - audyt na obcej maszynie: instalator wypisal "indeks odswiezany co 10 min", a
  # Get-ScheduledTask nie znajdowal potem zadnego zadania. Samo przejscie Register-ScheduledTask
  # bez wyjatku niczego nie dowodzi - pytamy harmonogram, takze o tryb.
  $stan = Lore-Stan-Indeksu
  if (-not $stan.Ok) { throw "zadanie $($script:NazwaZadania) nie powstalo: $($stan.Opis) - harmonogram przyjal polecenie, ale zadania tam nie ma" }
  if ($stan.TylkoTekst -ne $tylkoTekst) { throw "zadanie $($script:NazwaZadania) powstalo w zlym trybie (akcja: $($stan.Argumenty))" }
  Krok "zadanie $($script:NazwaZadania) jest w Harmonogramie ($($stan.Opis)) - indeks rozmow co $($script:InterwalMin) min, $jak"
}

function Lore-Usun-Zadanie-Indeksu {
  $stan = Stan-Zadania $script:NazwaZadania "lore\.index"
  if ($stan.Jest -eq $false) { Krok "zadania $($script:NazwaZadania) nie ma w Harmonogramie - nie ma czego zdejmowac"; return }
  if ($Proba) { Plan "zdjalbym zadanie $($script:NazwaZadania) z Harmonogramu"; return }
  try {
    # -Confirm:$false - domyslnie Unregister-ScheduledTask pyta, a nikt nie wcisnie klawisza
    Unregister-ScheduledTask -TaskName $script:NazwaZadania -Confirm:$false -ErrorAction Stop
  } catch {
    throw "nie udalo sie zdjac zadania $($script:NazwaZadania): $($_.Exception.Message)"
  }
  if ((Stan-Zadania $script:NazwaZadania "lore\.index").Jest) { throw "zadanie $($script:NazwaZadania) nadal jest w Harmonogramie - zdejmij je recznie" }
  Krok "zadanie $($script:NazwaZadania) zdjete z Harmonogramu"
}

# Pierwszy przebieg indeksu w tle, od razu - zeby nie czekac na zadanie. Osobny proces bez okna,
# nie Start-ScheduledTask: proces dziedziczy srodowisko wolajacego (katalog domowy), a zadanie
# z Harmonogramu chodzi zawsze na prawdziwym katalogu uzytkownika. Wyjscie do pliku obok bazy.
function Lore-Indeksuj-W-Tle([bool]$tylkoTekst = $false) {
  $argumenty = @("--directory", "`"$($script:Lore)`"", "run", "python", "-m", "lore.index")
  if ($tylkoTekst) { $argumenty += "--text-only" }
  if ($Proba) { Plan "pierwszy przebieg indeksu rozmow w tle: uv $($argumenty -join ' ')"; return }
  New-Item -ItemType Directory -Force -Path $script:Dom | Out-Null
  $log = Join-Path $script:Dom "lore.index.log"
  $logWy = Join-Path $script:Dom "lore.index.out.log"
  try {
    $p = Start-Process -FilePath $script:Uv -ArgumentList $argumenty -WindowStyle Hidden -PassThru `
      -RedirectStandardError $log -RedirectStandardOutput $logWy -ErrorAction Stop
    Krok "pierwsze indeksowanie rozmow ruszylo w tle (PID $($p.Id)); przy duzym archiwum trwa dluzej - dziennik: $log"
  } catch {
    Ostrzezenie "nie udalo sie uruchomic indeksowania w tle ($($_.Exception.Message)) - zrobi je zadanie $($script:NazwaZadania) w ciagu $($script:InterwalMin) min"
  }
}

# ---------------------------------------------------------------- baza lore.db

# Zaklada baze (schemat, idempotentnie) i zapisuje tryb indeksu od razu - Stan i okno nadzorcy
# maja widziec "tylko tekst" juz teraz, nie dopiero po pierwszym przebiegu zadania.
function Lore-Zapisz-Tryb([bool]$tylkoTekst) {
  $jak = if ($tylkoTekst) { "tylko tekst (bez wektorow)" } else { "tekst + wektory" }
  if ($Proba) { Plan "baza rozmow $($script:Baza): schemat i tryb indeksu - $jak"; return }
  $flaga = if ($tylkoTekst) { "True" } else { "False" }
  $w = Uruchom-Uv @("python", "-c", "from lore.db import connect, record_index_mode, DB_PATH; c = connect(); record_index_mode(c, $flaga); print('BAZA', DB_PATH)")
  if ($w.Kod -ne 0 -or $w.Tekst -notmatch 'BAZA (.+)') { throw "nie udalo sie zalozyc bazy rozmow: $(Ostatnia-Linia $w.Tekst)" }
  $sciezka = $Matches[1].Trim()
  if ($sciezka -ine $script:Baza) {
    Ostrzezenie "Lore uzywa bazy $sciezka, a instalator liczyl $($script:Baza) - sprawdz zmienne LORE_HOME / CLAUDE_HISTORIA_HOME"
  }
  Krok "baza rozmow gotowa ($sciezka), tryb indeksu: $jak"
}

# Tryb indeksu zapisany w bazie i liczby fragmentow - prosto z SQLite (tylko odczyt), bez modelu.
# Skrypt idzie przez plik: cudzyslowy wewnatrz argumentu gina w PowerShellu 5.1 po drodze do
# programu zewnetrznego, a SQL z kluczem w apostrofach inaczej sie nie da zapisac.
$script:PyStanBazy = @'
import os, sqlite3, sys
sys.path.insert(0, os.getcwd())  # skrypt z pliku ma w sys.path SWOJ katalog - lore lezy w roboczym
from pathlib import Path
from lore.db import DB_PATH
p = Path(DB_PATH)
if not p.exists():
    print('BAZA 0 - 0 0')
    sys.exit(0)
c = sqlite3.connect('file:' + p.as_posix() + '?mode=ro', uri=True)
t = {r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")}
def one(sql, *a):
    r = c.execute(sql, a).fetchone()
    return r[0] if r else None
mode = one('SELECT value FROM meta WHERE key=?', 'index_mode') if 'meta' in t else None
chunks = one('SELECT count(*) FROM chunks') if 'chunks' in t else 0
vectors = one('SELECT count(*) FROM vectors') if 'vectors' in t else 0
print('BAZA', 1, mode or '-', chunks, vectors)
'@

function Lore-Stan-Bazy {
  $plikPy = Join-Path $env:TEMP "lore-stan-bazy-$PID.py"
  [System.IO.File]::WriteAllText($plikPy, $script:PyStanBazy, (New-Object System.Text.UTF8Encoding($false)))
  try {
    if (-not (Test-Path $script:PythonVenv)) { $w = [pscustomobject]@{ Kod = -1; Tekst = "nie ma srodowiska Lore ($($script:PythonVenv))" } }
    else {
      $tu = Get-Location
      try { Set-Location -LiteralPath $script:Lore; $w = Lore-Wolaj $script:PythonVenv @($plikPy) }
      finally { Set-Location -LiteralPath $tu }
    }
  } finally {
    Remove-Item -LiteralPath $plikPy -Force -ErrorAction SilentlyContinue
  }
  $m = [regex]::Match($w.Tekst, 'BAZA (\d) (\S+) (\d+) (\d+)')
  if ($w.Kod -ne 0 -or -not $m.Success) {
    return [pscustomobject]@{ Ok = $false; Jest = $null; Tryb = $null; Fragmentow = 0; Wektorow = 0; Opis = (Ostatnia-Linia $w.Tekst) }
  }
  $tryb = $m.Groups[2].Value
  if ($tryb -eq '-') { $tryb = $null }
  return [pscustomobject]@{ Ok = $true; Jest = ($m.Groups[1].Value -eq '1'); Tryb = $tryb
    Fragmentow = [int]$m.Groups[3].Value; Wektorow = [int]$m.Groups[4].Value; Opis = "" }
}

# Dane uzytkownika: baza rozmow i pliki obok niej. Wolac WYLACZNIE przy -UsunDane i tylko wtedy,
# gdy ani wiedza, ani lore z niej nie korzystaja - to sprawdza wolajacy.
function Lore-Usun-Dane {
  $sa = @($script:PlikiBazyLore | ForEach-Object { Join-Path $script:Dom $_ } | Where-Object { Test-Path $_ })
  if ($sa.Count -eq 0) { Krok "bazy rozmow nie ma ($($script:Baza)) - nie ma czego usuwac"; return $true }
  $mb = [math]::Round((($sa | ForEach-Object { (Get-Item -LiteralPath $_).Length }) | Measure-Object -Sum).Sum / 1MB)
  if ($Proba) { Plan "usunalbym baze rozmow ($mb MB): $($sa -join ', ')"; return $true }
  $zle = @()
  foreach ($p in $sa) {
    try { Remove-Item -LiteralPath $p -Force -ErrorAction Stop } catch { $zle += "$p ($($_.Exception.Message))" }
  }
  if ($zle.Count -gt 0) { Ostrzezenie "nie udalo sie usunac: $($zle -join '; ') - plik trzyma pewnie dzialajacy proces Lore"; return $false }
  # swiezy katalog ~\.lore, w ktorym nic juz nie zostalo, tez znika; ~\.claude zostaje zawsze
  if ((Split-Path -Leaf $script:Dom) -eq ".lore" -and (Test-Path $script:Dom) -and
      @(Get-ChildItem -LiteralPath $script:Dom -Force -ErrorAction SilentlyContinue).Count -eq 0) {
    Remove-Item -LiteralPath $script:Dom -Force -ErrorAction SilentlyContinue
  }
  Krok "usunieta baza rozmow ($mb MB, $($script:Baza))"
  return $true
}

# ---------------------------------------------------------------- model wektorow

function Lore-Stan-Modelu {
  $plik = Join-Path $script:Modele "$($script:KatalogModelu)\onnx\model.onnx"
  if (-not (Test-Path $plik)) { return [pscustomobject]@{ Ok = $false; Jest = $false; MB = 0; Opis = "modelu nie ma ($plik)" } }
  $mb = [int]((Get-Item -LiteralPath $plik).Length / 1MB)
  if ($mb -lt $script:MinModelMB) {
    return [pscustomobject]@{ Ok = $false; Jest = $true; MB = $mb; Opis = "plik modelu ma $mb MB, a powinien co najmniej $($script:MinModelMB) MB - pobranie nie doszlo do konca" }
  }
  return [pscustomobject]@{ Ok = $true; Jest = $true; MB = $mb; Opis = "model na dysku: $mb MB" }
}

# Model sciaga sie leniwie, przy pierwszym liczeniu wektora. Sprawdzenie "czy katalog istnieje"
# przechodzilo na maszynie, ktora nigdy nic nie indeksowala - dlatego liczymy wektor NAPRAWDE:
# to wymusza pobranie i od razu pokazuje, czy model dziala.
function Lore-Pobierz-Model {
  if ($Proba) { Plan "pobranie modelu wektorow $($script:RozmiarModelu) do $($script:Modele) (jednorazowo, z huggingface.co) i probny wektor"; return }
  Krok "pobieram i sprawdzam model wektorow ($($script:RozmiarModelu), jednorazowo; przy wolnym laczu to kilka minut)"
  $kodPy = "from pathlib import Path; from lore.db import EMBED_DIM, MODELS_DIR, embed_query; " +
           "v = embed_query('czy ten model dziala'); " +
           "mb = sum(f.stat().st_size for f in Path(MODELS_DIR).rglob('*') if f.is_file()) // (1024*1024); " +
           "print('MODEL', len(v), EMBED_DIM, mb)"
  $w = Uruchom-Uv @("python", "-c", $kodPy)
  $m = [regex]::Match($w.Tekst, 'MODEL (\d+) (\d+) (\d+)')
  if ($w.Kod -ne 0 -or -not $m.Success) {
    $powod = Ostatnia-Linia $w.Tekst
    if ($w.Tekst -match '(?i)(cannot download|offline|connection|resolve|timed out|huggingface)') {
      throw "nie udalo sie pobrac modelu wektorow - brak internetu albo huggingface.co niedostepne (pobranie wznowi sie przy nastepnej probie): $powod"
    }
    throw "model wektorow nie dziala: $powod"
  }
  $wymiar = [int]$m.Groups[1].Value; $oczekiwany = [int]$m.Groups[2].Value; $mb = [int]$m.Groups[3].Value
  if ($wymiar -ne $oczekiwany) { throw "model wektorow liczy wektor $wymiar wymiarow zamiast $oczekiwany" }
  if ($mb -lt $script:MinModelMB) { throw "katalog modelu ma $mb MB, a powinien co najmniej $($script:MinModelMB) MB - pobranie nie doszlo do konca ($($script:Modele))" }
  Krok "model wektorow dziala (wektor $wymiar wymiarow, katalog modelu: $mb MB)"
}

# Model to nie dane uzytkownika (da sie pobrac drugi raz), ale ~0,5-1 GB na dysku - zdejmujemy
# go razem z modulem lore. Caly katalog lore_models, takze stary model e5-small sprzed 2026-09-24.
function Lore-Usun-Model {
  if (-not (Test-Path $script:Modele)) { Krok "modelu wektorow nie ma - nie ma czego usuwac"; return $true }
  $mb = [math]::Round(((Get-ChildItem -LiteralPath $script:Modele -Recurse -File -Force -ErrorAction SilentlyContinue |
          Measure-Object -Property Length -Sum).Sum) / 1MB)
  if ($Proba) { Plan "usunalbym model wektorow ($mb MB): $($script:Modele)"; return $true }
  $blad = Usun-Drzewo $script:Modele
  if ($blad) {
    Ostrzezenie "nie udalo sie usunac calego modelu $($script:Modele) ($blad) - uzywa go pewnie serwer lore w otwartym oknie; zamknij okna i usun ten katalog recznie albo uruchom usuwanie jeszcze raz"
    return $false
  }
  Krok "usuniety model wektorow ($mb MB, $($script:Modele))"
  return $true
}

# Stan wektorow w bazie (lore\lore\db.py, vector_status): ok | incomplete | migration_needed |
# migrating | unknown_model | text_only. Zwraca .Stan (albo $null, gdy nie dalo sie odczytac),
# .Ostrzezenie, .Trwa, .Procent i .Tekst (surowe wyjscie na wypadek bledu).
function Stan-Wektorow {
  # POSTEP: stan pliku postepu przeliczania (running/done/...) i czy proces naprawde zyje -
  # "running" ze stalym znacznikiem to przeliczanie, ktore padlo.
  $kodPy = "from lore.db import connect, vector_status; s = vector_status(connect()); " +
           "print('WEKTORY', s['state']); print(s.get('warning','') or s.get('note','')); p = s.get('progress') or {}; " +
           "print('POSTEP', p.get('state','brak'), 'padl' if p.get('stale') else 'zyje', p.get('percent','?'))"
  $w = Uruchom-Uv @("python", "-c", $kodPy)
  $linie = @($w.Tekst -split "`r?`n")
  $stan = $null
  $ostrz = ""
  for ($i = 0; $i -lt $linie.Count; $i++) {
    $m = [regex]::Match($linie[$i], '^WEKTORY (\S+)')
    if ($m.Success) {
      $stan = $m.Groups[1].Value
      if ($i + 1 -lt $linie.Count) { $ostrz = $linie[$i + 1].Trim() }
      break
    }
  }
  $mp = [regex]::Match($w.Tekst, '(?m)^POSTEP (\S+) (\S+) (\S+)')
  $trwa = $mp.Success -and $mp.Groups[1].Value -eq "running" -and $mp.Groups[2].Value -eq "zyje"
  $procent = if ($mp.Success) { $mp.Groups[3].Value } else { "?" }
  if ($w.Kod -ne 0) { $stan = $null }
  # db.py podaje polecenie z miejscem na katalog - podstawiamy prawdziwy.
  $ostrz = $ostrz.Replace("<lore>", $script:Lore)
  return [pscustomobject]@{ Stan = $stan; Ostrzezenie = $ostrz; Trwa = $trwa; Procent = $procent; Tekst = $w.Tekst }
}

function Polecenie-Przeliczania {
  return "uv --directory $($script:Lore) run python -m lore.migrate"
}

# Archiwum policzone starym modelem albo fragmenty bez wektora (np. po trybie "tylko tekst")
# liczymy w tle. lore.migrate sam obniza sobie priorytet, trzyma blokade (drugi proces odchodzi
# bez szkody ze stanem "busy") i po przerwaniu rusza od miejsca, w ktorym stanal.
# Zwraca $true, gdy przeliczanie wlasnie ruszylo.
function Lore-Uruchom-Przeliczanie {
  if ($Proba) { Plan "gdy archiwum ma fragmenty bez wektora albo ze starego modelu: $(Polecenie-Przeliczania) - w tle, bez okna"; return $false }
  $s = Stan-Wektorow
  if (@("migration_needed", "migrating", "incomplete") -notcontains $s.Stan) { return $false }
  if ($s.Trwa) { Krok "przeliczanie wektorow juz trwa ($($s.Procent)%) - drugiego nie startuje"; return $false }
  New-Item -ItemType Directory -Force -Path $script:Dom | Out-Null
  $log = Join-Path $script:Dom "lore.migrate.log"
  $logWyjscia = Join-Path $script:Dom "lore.migrate.out.log"
  try {
    Start-Process -FilePath $script:Uv -ArgumentList @("--directory", "`"$($script:Lore)`"", "run", "python", "-m", "lore.migrate") `
      -WindowStyle Hidden -RedirectStandardError $log -RedirectStandardOutput $logWyjscia -ErrorAction Stop | Out-Null
    $co = if ($s.Stan -eq "incomplete") { "liczenie brakujacych wektorow" } else { "przeliczanie archiwum na nowy model ($($script:CzasPrzeliczania))" }
    Krok "$co ruszylo w tle (obnizony priorytet) - wyszukiwanie dziala w tym czasie; postep: $(Join-Path $script:Dom 'lore.migration.json')"
    return $true
  } catch {
    Ostrzezenie "nie udalo sie uruchomic przeliczania w tle: $($_.Exception.Message) - uruchom recznie: $(Polecenie-Przeliczania)"
    return $false
  }
}

# ---------------------------------------------------------------- serwer MCP

# Serwer MCP rejestrujemy w KAZDYM narzedziu, ktore zastaniemy na tej maszynie. Codex i opencode
# rozpoznajemy jak narzedzia\wpisz-zasady.ps1 i wdroz.ps1: binarka w PATH albo katalog, ktory
# narzedzie po sobie zostawia. Katalogi liczone od $KatalogDomowy (testy na kopii domu).
function Lore-Wykryj-Narzedzia {
  $script:Claude = $null
  $cl = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cl) { $script:Claude = $cl.Source }

  $script:Codex    = $null
  $script:CodexDom = Join-Path $KatalogDomowy ".codex"
  if ($env:CODEX_HOME) { $script:CodexDom = $env:CODEX_HOME }
  $script:CodexCfg = Join-Path $script:CodexDom "config.toml"
  $script:CodexMa  = $false   # czy ten Codex zna wlasne polecenie "codex mcp add"
  $cx = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cx) { $script:Codex = $cx.Source }
  $script:CodexJest = [bool]$script:Codex -or (Test-Path $script:CodexDom)
  if ($script:Codex) {
    # pytamy sam Codex, czy zna "codex mcp" - jedyny pewny sposob (samo --help nic nie zmienia)
    $pomoc = Lore-Wolaj $script:Codex @("mcp", "--help")
    if ($pomoc.Kod -eq 0 -and $pomoc.Tekst -match '\badd\b') { $script:CodexMa = $true }
  }

  $script:Opencode    = $null
  $script:OpencodeDom = Join-Path $KatalogDomowy ".config\opencode"
  $script:OpencodeCfg = Join-Path $script:OpencodeDom "opencode.json"
  $oc = Get-Command opencode -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($oc) { $script:Opencode = $oc.Source }
  $script:OpencodeJest = [bool]$script:Opencode -or (Test-Path $script:OpencodeDom)
}

function Lore-Jakiekolwiek-Narzedzie { return ([bool]$script:Claude -or $script:CodexJest -or $script:OpencodeJest) }

# jedno polecenie serwera dla wszystkich narzedzi - rozjazd miedzy nimi byloby najgorszym
# mozliwym bledem: jedno okno widzi Lore, drugie sie wywala
function Lore-Polecenie-Serwera { return @($script:Uv, "--directory", $script:Lore, "run", "python", "-m", "lore.server") }

function Lore-Czytaj-Json-Opencode {
  $raw = [System.IO.File]::ReadAllText($script:OpencodeCfg)
  if ($raw.Length -gt 0 -and [int]$raw[0] -eq 65279) { $raw = $raw.Substring(1) }
  if (-not $raw.Trim()) { return [pscustomobject]@{} }
  return ($raw | ConvertFrom-Json)
}

function Lore-Kopia-Obok([string]$plik) {
  $kopia = "$plik.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
  Copy-Item -LiteralPath $plik -Destination $kopia -Force
  return $kopia
}

# Tabela [mcp_servers.<nazwa>] razem z podtabelami ([mcp_servers.lore.env]) - inaczej zostalaby sierota.
function Lore-Bez-Tabeli-Codex([string[]]$linie) {
  $wynik = @()
  $pomijam = $false
  foreach ($l in $linie) {
    if ($l -match "^\s*\[+\s*mcp_servers\.$($script:NazwaMcp)\s*(\.|\])") { $pomijam = $true; continue }
    if ($pomijam -and $l -match '^\s*\[') { $pomijam = $false }
    if (-not $pomijam) { $wynik += $l }
  }
  # puste linie z konca ucinamy, zeby nie rosly przy kazdej kolejnej instalacji
  $ile = $wynik.Count
  while ($ile -gt 0 -and -not $wynik[$ile - 1].Trim()) { $ile-- }
  return @($wynik | Select-Object -First $ile)
}

# Zwraca liste narzedzi, w ktorych serwer jest zarejestrowany. Blad rejestracji = wyjatek.
function Lore-Zarejestruj-Mcp {
  $polecenie = Lore-Polecenie-Serwera
  $gdzie = @()

  # ---- opencode (zapis do opencode.json - nie ma wlasnego polecenia "mcp add").
  # Idempotentnie: wpis mcp.<nazwa> jest nadpisywany, reszta pliku zostaje.
  if (-not $script:OpencodeJest) {
    Krok "opencode: nie ma go na tej maszynie - pomijam"
  } elseif ($Proba) {
    Plan "opencode: wpis mcp.$($script:NazwaMcp) (type=local, enabled=true) w $($script:OpencodeCfg), stary plik skopiowany obok"
  } else {
    New-Item -ItemType Directory -Force -Path $script:OpencodeDom | Out-Null
    $s = $null
    if (Test-Path $script:OpencodeCfg) {
      try { $s = Lore-Czytaj-Json-Opencode }
      catch { throw "rejestracja w opencode nie powiodla sie - $($script:OpencodeCfg) nie jest czystym JSON-em, nie ruszam go" }
      $kopia = Lore-Kopia-Obok $script:OpencodeCfg
      Krok "opencode: kopia zapasowa starej konfiguracji: $kopia"
    } else {
      $s = [pscustomobject]@{ '$schema' = 'https://opencode.ai/config.json' }
    }
    if (-not ($s.PSObject.Properties.Name -contains 'mcp') -or $null -eq $s.mcp) {
      $s | Add-Member -NotePropertyName mcp -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $wpis = [pscustomobject]@{ type = 'local'; command = @($polecenie); enabled = $true }
    if ($s.mcp.PSObject.Properties.Name -contains $script:NazwaMcp) { $s.mcp.($script:NazwaMcp) = $wpis }
    else { $s.mcp | Add-Member -NotePropertyName $script:NazwaMcp -NotePropertyValue $wpis -Force }
    [System.IO.File]::WriteAllText($script:OpencodeCfg, ($s | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
    Krok "opencode: wpis mcp.$($script:NazwaMcp) jest w $($script:OpencodeCfg)"
    $gdzie += "opencode"
  }

  # ---- Claude Code
  if ($script:Claude) {
    $argumenty = @("mcp", "add", "--scope", "user", $script:NazwaMcp, "--") + $polecenie
    if ($Proba) {
      Plan "Claude Code: claude mcp remove $($script:NazwaMcp) -s user (gdy wpis juz jest), potem claude $($argumenty -join ' ')"
    } else {
      # idempotentnie: stary wpis najpierw kasujemy, zeby ponowna instalacja nie zrobila duplikatu
      if ((Lore-Wolaj $script:Claude @("mcp", "get", $script:NazwaMcp)).Kod -eq 0) {
        Krok "Claude Code: wpis $($script:NazwaMcp) juz jest - podmieniam na aktualny"
        [void](Lore-Wolaj $script:Claude @("mcp", "remove", $script:NazwaMcp, "-s", "user"))
      }
      $w = Lore-Wolaj $script:Claude $argumenty
      if ($w.Kod -ne 0) { throw "rejestracja serwera $($script:NazwaMcp) w Claude Code nie powiodla sie (kod $($w.Kod)): $(Ostatnia-Linia $w.Tekst)" }
      Krok "Claude Code: serwer $($script:NazwaMcp) zarejestrowany dla uzytkownika - widoczny we wszystkich projektach"
      $gdzie += "claude"
    }
  } else {
    Krok "Claude Code: nie ma go na tej maszynie - pomijam"
  }

  # ---- Codex CLI
  if (-not $script:CodexJest) {
    Krok "Codex: nie ma go na tej maszynie - pomijam"
    return $gdzie
  }
  if ($script:CodexMa) {
    $argCodex = @("mcp", "add", $script:NazwaMcp, "--") + $polecenie
    if ($Proba) { Plan "Codex: codex mcp remove $($script:NazwaMcp) (gdy wpis juz jest), potem codex $($argCodex -join ' ')"; return $gdzie }
    if ((Lore-Wolaj $script:Codex @("mcp", "get", $script:NazwaMcp)).Kod -eq 0) {
      Krok "Codex: wpis $($script:NazwaMcp) juz jest - podmieniam na aktualny"
      [void](Lore-Wolaj $script:Codex @("mcp", "remove", $script:NazwaMcp))
    }
    $w = Lore-Wolaj $script:Codex $argCodex
    if ($w.Kod -ne 0) { throw "rejestracja serwera $($script:NazwaMcp) w Codeksie nie powiodla sie (kod $($w.Kod)): $(Ostatnia-Linia $w.Tekst)" }
    Krok "Codex: serwer $($script:NazwaMcp) zarejestrowany poleceniem 'codex mcp add'"
    return ($gdzie + "codex")
  }
  # Codex bez wlasnego polecenia - tabela w config.toml. Stara tabela leci w calosci, dopiero
  # potem doklejamy swieza, a caly plik laduje wczesniej do kopii z data.
  if ($Proba) { Plan "Codex: tabela [mcp_servers.$($script:NazwaMcp)] w $($script:CodexCfg) (stary plik skopiowany obok)"; return $gdzie }
  $cytuj = { param($s) '"' + ((($s -replace '\\', '\\') -replace '"', '\"')) + '"' }
  if (-not (Test-Path $script:CodexDom)) { New-Item -ItemType Directory -Force -Path $script:CodexDom | Out-Null }
  $linie = @()
  if (Test-Path $script:CodexCfg) {
    $kopia = Lore-Kopia-Obok $script:CodexCfg
    Krok "Codex: kopia zapasowa starej konfiguracji: $kopia"
    $linie = @(Lore-Bez-Tabeli-Codex @(Get-Content -LiteralPath $script:CodexCfg))
    if ($linie.Count -gt 0) { $linie += "" }
  }
  $linie += "[mcp_servers.$($script:NazwaMcp)]"
  $linie += "command = " + (& $cytuj $polecenie[0])
  $linie += "args = [" + (($polecenie | Select-Object -Skip 1 | ForEach-Object { & $cytuj $_ }) -join ", ") + "]"
  # bez BOM - to plik TOML, a nie kazdy czytnik BOM wybacza
  [System.IO.File]::WriteAllLines($script:CodexCfg, [string[]]$linie, (New-Object System.Text.UTF8Encoding($false)))
  Krok "Codex: tabela [mcp_servers.$($script:NazwaMcp)] jest w $($script:CodexCfg)"
  return ($gdzie + "codex")
}

# Odwrotnosc Lore-Zarejestruj-Mcp. Narzedzie bez wpisu = nic do roboty (bez kopii, bez zapisu).
# Plik, ktorego nie da sie bezpiecznie przeczytac, zostaje nietkniety - wyjatek z powodem.
function Lore-Wyrejestruj-Mcp {
  if ($script:OpencodeJest -and (Test-Path $script:OpencodeCfg)) {
    $s = $null
    try { $s = Lore-Czytaj-Json-Opencode }
    catch { throw "nie moge zdjac serwera z opencode - $($script:OpencodeCfg) nie jest czystym JSON-em, nie ruszam go" }
    if ($s.mcp -and ($s.mcp.PSObject.Properties.Name -contains $script:NazwaMcp)) {
      if ($Proba) { Plan "opencode: usunalbym wpis mcp.$($script:NazwaMcp) z $($script:OpencodeCfg)" }
      else {
        $kopia = Lore-Kopia-Obok $script:OpencodeCfg
        [void]$s.mcp.PSObject.Properties.Remove($script:NazwaMcp)
        [System.IO.File]::WriteAllText($script:OpencodeCfg, ($s | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
        Krok "opencode: wpis mcp.$($script:NazwaMcp) usuniety z $($script:OpencodeCfg) (kopia: $kopia)"
      }
    } else { Krok "opencode: serwera $($script:NazwaMcp) tam nie ma" }
  }

  if ($script:Claude) {
    if ((Lore-Wolaj $script:Claude @("mcp", "get", $script:NazwaMcp)).Kod -eq 0) {
      if ($Proba) { Plan "Claude Code: claude mcp remove $($script:NazwaMcp) -s user" }
      else {
        $w = Lore-Wolaj $script:Claude @("mcp", "remove", $script:NazwaMcp, "-s", "user")
        if ($w.Kod -ne 0 -or (Lore-Wolaj $script:Claude @("mcp", "get", $script:NazwaMcp)).Kod -eq 0) {
          throw "nie udalo sie zdjac serwera $($script:NazwaMcp) z Claude Code (kod $($w.Kod)): $(Ostatnia-Linia $w.Tekst)"
        }
        Krok "Claude Code: serwer $($script:NazwaMcp) wyrejestrowany (otwarte okna maja go do zamkniecia)"
      }
    } else { Krok "Claude Code: serwera $($script:NazwaMcp) tam nie ma" }
  }

  if (-not $script:CodexJest) { return }
  if ($script:CodexMa) {
    if ((Lore-Wolaj $script:Codex @("mcp", "get", $script:NazwaMcp)).Kod -eq 0) {
      if ($Proba) { Plan "Codex: codex mcp remove $($script:NazwaMcp)"; return }
      $w = Lore-Wolaj $script:Codex @("mcp", "remove", $script:NazwaMcp)
      if ($w.Kod -ne 0) { throw "nie udalo sie zdjac serwera $($script:NazwaMcp) z Codeksa (kod $($w.Kod)): $(Ostatnia-Linia $w.Tekst)" }
      Krok "Codex: serwer $($script:NazwaMcp) wyrejestrowany"
    } else { Krok "Codex: serwera $($script:NazwaMcp) tam nie ma" }
    return
  }
  if (Test-Path $script:CodexCfg) {
    $stare = @(Get-Content -LiteralPath $script:CodexCfg)
    $nowe = @(Lore-Bez-Tabeli-Codex $stare)
    $byla = @($stare | Where-Object { $_ -match "^\s*\[+\s*mcp_servers\.$($script:NazwaMcp)\s*(\.|\])" }).Count -gt 0
    if (-not $byla) { Krok "Codex: tabeli [mcp_servers.$($script:NazwaMcp)] tam nie ma"; return }
    if ($Proba) { Plan "Codex: usunalbym tabele [mcp_servers.$($script:NazwaMcp)] z $($script:CodexCfg)"; return }
    $kopia = Lore-Kopia-Obok $script:CodexCfg
    [System.IO.File]::WriteAllLines($script:CodexCfg, [string[]]$nowe, (New-Object System.Text.UTF8Encoding($false)))
    Krok "Codex: tabela [mcp_servers.$($script:NazwaMcp)] usunieta z $($script:CodexCfg) (kopia: $kopia)"
  }
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

# Prawdziwe wywolanie: serwer startuje tym samym poleceniem, ktore trafilo do konfiguracji,
# i rozmawiamy z nim po JSON-RPC - initialize, tools/list, tools/call lore_stats. Zepsuty serwer
# nie ma jak tego przejsc. Zwraca Ok i Opis.
function Lore-Sprawdz-Mcp-Dziala {
  $plikProby = Join-Path $env:TEMP "lore-mcp-proba-$PID.py"
  [System.IO.File]::WriteAllText($plikProby, $script:ProbaMcp, (New-Object System.Text.UTF8Encoding($false)))
  try {
    $w = Uruchom-Uv (@("python", $plikProby) + (Lore-Polecenie-Serwera))
    if ($w.Kod -eq 0 -and $w.Tekst -match 'MCP OK (\d+)') {
      return [pscustomobject]@{ Ok = $true; Opis = "handshake i lore_stats przeszly, narzedzi: $($Matches[1])" }
    }
    return [pscustomobject]@{ Ok = $false; Opis = (Ostatnia-Linia $w.Tekst) }
  } finally {
    Remove-Item -LiteralPath $plikProby -Force -ErrorAction SilentlyContinue
  }
}

# Stan wektorow bez "uv run" (sprawdzenie stanu nie synchronizuje srodowiska) i tylko na
# istniejacej bazie - connect() zalozylby pusta. Pola jak w Stan-Wektorow.
function Lore-Stan-Wektorow-Wprost {
  if (-not (Test-Path $script:Baza)) { return [pscustomobject]@{ Stan = $null; Ostrzezenie = "nie ma bazy $($script:Baza)"; Trwa = $false; Procent = "?"; Tekst = "" } }
  $kodPy = "from lore.db import connect, vector_status; s = vector_status(connect()); " +
           "print('WEKTORY', s['state']); print(s.get('warning','') or s.get('note','')); p = s.get('progress') or {}; " +
           "print('POSTEP', p.get('state','brak'), 'padl' if p.get('stale') else 'zyje', p.get('percent','?'))"
  $w = Lore-Python-Wprost $kodPy
  $m = [regex]::Match($w.Tekst, '(?m)^WEKTORY (\S+)\s*\r?\n(.*)$')
  $mp = [regex]::Match($w.Tekst, '(?m)^POSTEP (\S+) (\S+) (\S+)')
  $stan = if ($w.Kod -eq 0 -and $m.Success) { $m.Groups[1].Value } else { $null }
  $ostrz = if ($m.Success) { $m.Groups[2].Value.Trim().Replace("<lore>", $script:Lore) } else { Ostatnia-Linia $w.Tekst }
  $trwa = $mp.Success -and $mp.Groups[1].Value -eq "running" -and $mp.Groups[2].Value -eq "zyje"
  return [pscustomobject]@{ Stan = $stan; Ostrzezenie = $ostrz; Trwa = $trwa; Procent = $(if ($mp.Success) { $mp.Groups[3].Value } else { "?" }); Tekst = $w.Tekst }
}

# Gdzie serwer jest zarejestrowany - lista nazw narzedzi. To sprawdzenie WPISU, nie dzialania.
function Lore-Stan-Mcp {
  $jest = @()
  if ($script:Claude -and (Lore-Wolaj $script:Claude @("mcp", "get", $script:NazwaMcp)).Kod -eq 0) { $jest += "claude" }
  if ($script:CodexJest) {
    if ($script:CodexMa) {
      if ((Lore-Wolaj $script:Codex @("mcp", "get", $script:NazwaMcp)).Kod -eq 0) { $jest += "codex" }
    } elseif ((Test-Path $script:CodexCfg) -and ((Get-Content -LiteralPath $script:CodexCfg -Raw) -match "(?m)^\s*\[\s*mcp_servers\.$($script:NazwaMcp)\s*\]")) {
      $jest += "codex"
    }
  }
  if ($script:OpencodeJest -and (Test-Path $script:OpencodeCfg)) {
    $s = $null
    try { $s = Lore-Czytaj-Json-Opencode } catch { Ostrzezenie "$($script:OpencodeCfg) nie jest czystym JSON-em - nie widze w nim wpisu serwera" }
    if ($s -and $s.mcp -and ($s.mcp.PSObject.Properties.Name -contains $script:NazwaMcp) -and $s.mcp.($script:NazwaMcp).command) { $jest += "opencode" }
  }
  return $jest
}

# ---------------------------------------------------------------- stare zadania (sprzatanie)

# Brak zadania to normalna sytuacja - na swiezej maszynie nie ma czego zdejmowac i nikt
# o tym nie musi slyszec.
function Jest-Stare-Odswiezanie {
  if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return $false }
  return [bool](Get-ScheduledTask -TaskName $script:NazwaZadaniaOdswiez -ErrorAction SilentlyContinue)
}

function Stare-Zadania-Cyklu {
  if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return @() }
  return @($script:ZadaniaCyklu | Where-Object { Get-ScheduledTask -TaskName $_ -ErrorAction SilentlyContinue })
}

# Zdejmuje oba rodzaje starych zadan. Zwraca $true, gdy po wszystkim zadnego nie ma.
function Lore-Usun-Stare-Zadania {
  $sa = @()
  if (Jest-Stare-Odswiezanie) { $sa += $script:NazwaZadaniaOdswiez }
  $sa += @(Stare-Zadania-Cyklu)
  if ($sa.Count -eq 0) { return $true }
  if ($Proba) { foreach ($n in $sa) { Plan "zdjalbym stare zadanie $n z Harmonogramu (cykl i aktualizacja nie chodza juz o sztywnych godzinach)" }; return $true }
  foreach ($n in $sa) {
    # -Confirm:$false, bo domyslnie Unregister-ScheduledTask pyta, a nikt nie wcisnie klawisza
    try { Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction Stop }
    catch { Ostrzezenie "nie udalo sie zdjac starego zadania ${n}: $($_.Exception.Message)" }
  }
  $zostaly = @()
  if (Jest-Stare-Odswiezanie) { $zostaly += $script:NazwaZadaniaOdswiez }
  $zostaly += @(Stare-Zadania-Cyklu)
  if ($zostaly.Count -gt 0) { Ostrzezenie "nadal sa w Harmonogramie: $($zostaly -join ', ') - usun je recznie"; return $false }
  Krok "zdjete stare zadania: $($sa -join ', ') - aktualizacja idzie przy starcie sesji, a cykl wiedzy przy pierwszej sesji dnia"
  return $true
}
