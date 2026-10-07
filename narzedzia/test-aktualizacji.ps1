# narzedzia\test-aktualizacji.ps1 - proba aktualizacji automatycznej MegaRuchacza (2026-10-07):
# narzedzia\aktualizuj-megaruchacza.ps1, straznik-zasad.ps1 -TylkoPobierz, zegar w nadzorcy
# (zasobnik\nadzorca\dozor.ps1) i alarm o jej ciszy (zasobnik\nadzorca\stan-zbieranie.ps1).
#
# Co sprawdza (kazde zabezpieczenie razem z proba jego zlamania):
#   1  pierwszy przebieg bez znacznika naniesienia -> naniesienie (instaluj-globalnie podnosi numer
#      w .megaruchacz-global) i restart nadzorcy (stary proces zamkniety, nowy z zadania Harmonogramu)
#   2  nic nowego -> "aktualne", bez naniesienia i bez restartu
#   3  nowa wersja na serwerze -> "zaktualizowano" z wersja_przed/po, skille dograne (modul wlaczony),
#      nadzorca spod innej sciezki (kopia testowa, inne repo) przezywa restart; skille zawodza -> uwaga
#   4  lokalna zmiana w pliku, ktory zmienia nowa wersja -> "blad" z powodem, zmiana nietknieta;
#      po jej zdjeciu -> zaktualizowano
#   5  blokada: trzymana przez test -> drugi przebieg konczy sie kodem 3 i nie rusza stanu;
#      dwa starty naraz -> jeden przebieg
#   6  restart: zadanie Harmonogramu nie istnieje -> nadzorca wprost + uwaga; nadzorca pada na
#      starcie -> "blad"; po naprawie -> gotowe
#   7  straznik zajety dluzej niz czeka -TylkoPobierz -> "zajete" -> blad z miekka przyczyna; pomocnik
#      restartu bez blokady -> blad, nikogo nie zamyka (razem ~4 min; -BezCzekaniaNaBlokade pomija)
#   8  alarm Alarm-Aktualizacji (slady zegara w nadzorcy): obie sprawy po obu stronach progu, brak
#      falszywych alarmow i brak drugiej karty dla tego, co pokazuje karta Stan (Ocena-Aktualizacji)
#   9  zegar w dozorze: odpala po zadanym czasie, zostawia slady; bez skryptu - wywrotka, bez sladu
#
# BEZPIECZENSTWO (wzor: instalator\test-calosci.ps1):
#  - repo: git clone tego repo + pliki tej zmiany z dysku (i z -Nakladka); "origin" kopii to
#    zamrozony goly klon, do ktorego "nowe wersje" wypycha osobny klon-pisarz - straznik nigdy nie
#    siega do prawdziwego serwera;
#  - zasobnik\nadzorca.ps1 w kopii to zaslepka (nie pokazuje ikony, czeka na plik stopu),
#    narzedzia\skille.ps1 - zaslepka zapisujaca wywolanie (bez GitHuba);
#  - restart idzie na WLASNE zadanie Harmonogramu MRTEST-AKT-<stempel> (bez wyzwalaczy, ukryte),
#    zdejmowane na koncu; zamykane sa tylko procesy z katalogu testu;
#  - procesy testu: USERPROFILE/HOME/APPDATA/TEMP w katalogu testu, bez CLAUDE*/CODEX_*/ORCA_*/LORE_*;
#  - przed i po: odcisk prawdziwego stanu (pliki aktualizacji i instalacji w ~\.claude, zadanie
#    MegaRuchaczNadzorca, PID prawdziwego nadzorcy) - musi sie zgadzac.
#  Okien nie ma: procesy z CreateNoWindow, zaslepka nadzorcy przez conhost --headless.
#
# Uzycie (niewidocznie):
#   powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File narzedzia\test-aktualizacji.ps1
#     [-Katalog <kat>] [-Nakladka <kat z plikami w ukladzie repo>] [-Zostaw] [-BezCzekaniaNaBlokade]
# Kod wyjscia: 0 = wszystko przeszlo, 1 = cos nie.
param(
  [string]$Katalog = $env:TEMP,
  [string]$Nakladka = "",
  [switch]$Zostaw,
  [switch]$BezCzekaniaNaBlokade
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$RepoPrawdziwe = Split-Path -Parent $PSScriptRoot
$Stempel = Get-Date -Format 'MMdd-HHmmss'
$T = Join-Path $Katalog "MRTEST-A-$Stempel"
$Repo = Join-Path $T 'repo'
$Origin = Join-Path $T 'origin.git'
$Pisarz = Join-Path $T 'pisarz'
$Dom = Join-Path $T 'dom'
$Bin = Join-Path $T 'bin'
$Tmp = Join-Path $T 'tmp'
$Zadanie = "MRTEST-AKT-$Stempel"
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:Zle = 0
$script:Ok = 0

# Pliki tej zmiany - kopia bierze je z dysku (sa niezapisane albo swiezo zapisane), reszta z HEAD.
$MOJE = @('narzedzia\aktualizuj-megaruchacza.ps1', 'narzedzia\straznik-zasad.ps1', 'narzedzia\test-aktualizacji.ps1',
          'zasobnik\nadzorca\dozor.ps1', 'zasobnik\nadzorca\stan-zbieranie.ps1')

function Sprawdz([string]$co, [bool]$ok, [string]$szczegol = '') {
  $linia = $(if ($ok) { 'OK    ' } else { 'BLAD  ' }) + $co
  if (-not $ok -and $szczegol) { $linia += ' -- ' + (($szczegol -replace '\s+', ' ').Trim()) }
  Write-Host $linia
  if ($ok) { $script:Ok++ } else { $script:Zle++ }
}
function Info([string]$t) { Write-Host "INFO  $t" }
function Czytaj([string]$p) { if (-not (Test-Path -LiteralPath $p)) { return $null }; return [System.IO.File]::ReadAllText($p, $Utf8) }
function Skrot-Pliku([string]$p) { if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return '-' }; return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Git-Cicho([string[]]$a) {
  $stare = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $wy = & git @a 2>&1; $kod = $LASTEXITCODE } finally { $ErrorActionPreference = $stare }
  if ($kod -ne 0) { throw "git $($a -join ' ') zakonczyl sie kodem ${kod}: $($wy -join ' ')" }
  return (($wy | ForEach-Object { "$_" }) -join "`n").Trim()
}
function Skrot16([string]$t) {
  $md5 = [System.Security.Cryptography.MD5]::Create()
  try { return ([System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($t))).Replace('-', '')).Substring(0, 16) } finally { $md5.Dispose() }
}

# ---------------------------------------------------------------- odcisk prawdziwego stanu

$RealNadzorca = Join-Path $RepoPrawdziwe 'zasobnik\nadzorca.ps1'
function Odcisk-Prawdziwy {
  $o = [ordered]@{}
  foreach ($p in @('.claude\mr\aktualizacja.json', '.claude\mr\aktualizacja-naniesione.txt', '.claude\mr\aktualizacja.log',
                   '.claude\.megaruchacz-global', '.claude\mr\instalacja.json', '.claude\settings.json')) { $o["plik.$p"] = Skrot-Pliku (Join-Path $HOME $p) }
  $z = Get-ScheduledTask -TaskName 'MegaRuchaczNadzorca' -ErrorAction SilentlyContinue
  $o['zadanie'] = if ($z) { "$($z.State) " + (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes((Export-ScheduledTask -TaskName 'MegaRuchaczNadzorca'))))).Hash } else { '-' }
  $o['nadzorca.pid'] = (@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($RealNadzorca, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | ForEach-Object { $_.ProcessId } | Sort-Object) -join ',')
  return $o
}

function Procesy-Testu {
  return @(Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($T, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
}
function Stuby {
  $s = Join-Path $Repo 'zasobnik\nadzorca.ps1'
  return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($s, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | ForEach-Object { [int]$_.ProcessId } | Sort-Object)
}

# ---------------------------------------------------------------- kopia repo, origin, dom

function Przygotuj {
  New-Item -ItemType Directory -Force -Path $T, $Bin, $Tmp, $Dom | Out-Null
  [void](Git-Cicho @('clone', '--quiet', '--no-hardlinks', $RepoPrawdziwe, $Repo))
  foreach ($w in $MOJE) {
    $skad = Join-Path $RepoPrawdziwe $w
    if ($Nakladka -and (Test-Path -LiteralPath (Join-Path $Nakladka $w))) { $skad = Join-Path $Nakladka $w }
    if (Test-Path -LiteralPath $skad) { Copy-Item -LiteralPath $skad -Destination (Join-Path $Repo $w) -Force }
  }
  # Zaslepka nadzorcy: zapisuje, ze wstala, i czeka na plik stopu (najdluzej 15 min). Z pliku
  # "stub-pada.txt" konczy sie od razu - jak nadzorca z bledem w kodzie.
  [System.IO.File]::WriteAllText((Join-Path $Repo 'zasobnik\nadzorca.ps1'), @'
param([string]$Zrodlo = "")
$t = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
Add-Content -LiteralPath (Join-Path $t 'stub-nadzorcy.log') -Value ("wstal " + $PID)
if (Test-Path -LiteralPath (Join-Path $t 'stub-pada.txt')) { exit 7 }
$do = (Get-Date).AddMinutes(15)
while ((Get-Date) -lt $do) { if (Test-Path -LiteralPath (Join-Path $t 'stub-stop.txt')) { break }; Start-Sleep -Seconds 1 }
exit 0
'@, $Utf8)
  # Zaslepka skilli: zapisuje wywolanie; kod wyjscia z pliku skille-kod.txt (domyslnie 0).
  [System.IO.File]::WriteAllText((Join-Path $Repo 'narzedzia\skille.ps1'), @'
$t = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Add-Content -LiteralPath (Join-Path $t 'skille-wolania.log') -Value ($args -join ' ')
$k = Join-Path $t 'skille-kod.txt'
if (Test-Path -LiteralPath $k) { exit ([int](Get-Content -LiteralPath $k -Raw).Trim()) }
exit 0
'@, $Utf8)
  [void](Git-Cicho @('-C', $Repo, '-c', 'user.name=MRTEST', '-c', 'user.email=mrtest@example.invalid', 'add', '-A'))
  [void](Git-Cicho @('-C', $Repo, '-c', 'user.name=MRTEST', '-c', 'user.email=mrtest@example.invalid', 'commit', '--quiet', '--allow-empty', '-m', 'MRTEST: stan roboczy i zaslepki'))
  [void](Git-Cicho @('clone', '--quiet', '--bare', $Repo, $Origin))
  [void](Git-Cicho @('-C', $Repo, 'remote', 'set-url', 'origin', $Origin))
  [void](Git-Cicho @('-C', $Repo, 'fetch', '--quiet', 'origin'))
  [void](Git-Cicho @('-C', $Repo, 'branch', '--quiet', '--set-upstream-to=origin/main', 'main'))
  [void](Git-Cicho @('clone', '--quiet', $Origin, $Pisarz))

  foreach ($k in @('.claude\mr', 'AppData\Local', 'AppData\Roaming')) { New-Item -ItemType Directory -Force -Path (Join-Path $Dom $k) | Out-Null }
  [System.IO.File]::WriteAllText((Join-Path $Dom '.claude\CLAUDE.md'), "# Moje ustalenia`r`n`r`nNotatka testowa (to zostaje).`r`n", $Utf8)
  [System.IO.File]::WriteAllText((Join-Path $Dom '.claude\settings.json'), "{`n  ""theme"": ""dark""`n}`n", $Utf8)
  [System.IO.File]::WriteAllText((Join-Path $Dom '.claude\.megaruchacz-global'), "zrodlo: $Repo`nwersja: 0.0.1`nwariant: claude`ndata: 2026-01-01 00:00`n", $Utf8)
  Ustaw-Rejestr $false

  # node bez katalogu z prawdziwym claude (instaluj-globalnie widzi narzedzia po PATH) - samo node.exe
  $node = Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($node) { New-Item -ItemType HardLink -Path (Join-Path $Bin 'node.exe') -Target $node.Source | Out-Null }

  # Wlasne zadanie Harmonogramu - bez wyzwalaczy (samo nigdy nie ruszy), ukryte, przez conhost --headless.
  $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
  $arg = [System.Security.SecurityElement]::Escape('--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $Repo 'zasobnik\nadzorca.ps1') + '" -Zrodlo "' + $Repo + '"')
  $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>MRTEST - test-aktualizacji.ps1, zdejmowane na koncu testu</Description></RegistrationInfo>
  <Principals><Principal id="Author"><UserId>$sid</UserId><LogonType>InteractiveToken</LogonType></Principal></Principals>
  <Settings>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <ExecutionTimeLimit>PT1H</ExecutionTimeLimit>
    <Hidden>true</Hidden>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author"><Exec><Command>conhost.exe</Command><Arguments>$arg</Arguments></Exec></Actions>
</Task>
"@
  Register-ScheduledTask -TaskName $Zadanie -Xml $xml -Force -ErrorAction Stop | Out-Null
}

function Ustaw-Rejestr([bool]$skille) {
  $j = [ordered]@{ wersja = 1; moduly = [ordered]@{ wiedza = $false; lore = $false; kierownik = $true; skille = $skille; kopia = $false }
                   kopia = $null; narzedzia = [ordered]@{ claude = $true; codex = $false; opencode = $false }; baza = $true; data = '2026-10-07 10:00:00' }
  [System.IO.File]::WriteAllText((Join-Path $Dom '.claude\mr\instalacja.json'), ($j | ConvertTo-Json -Depth 4), $Utf8)
}

# ---------------------------------------------------------------- uruchamianie

$Systemowe = "$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\WindowsPowerShell\v1.0;$env:SystemRoot\System32\Wbem"
$KatGit = Split-Path -Parent ((Get-Command git -CommandType Application | Select-Object -First 1).Source)
# git z samego mingw64\bin pada przy fetch (0xC0000005, sprawdzone 2026-10-07) - potrzebuje tez
# usr\bin (jak $KatBash w instalator\test-calosci.ps1)
$KatGitUsr = @((Join-Path (Split-Path -Parent (Split-Path -Parent $KatGit)) 'usr\bin'), (Join-Path (Split-Path -Parent $KatGit) 'usr\bin')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$ZmienneZakazane = '^(LORE_|CLAUDE|CODEX_|ANTHROPIC_|OPENAI_|ORCA_|HF_|VIRTUAL_ENV$|PYTHONPATH$)'

function Nowe-Psi([string]$plik, [string[]]$argumenty, [string]$dom = $Dom) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $q = { param($a) if ($a -eq '') { '""' } elseif ($a -notmatch '[\s"]') { $a } else { '"' + ($a -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' } }
  $psi.Arguments = (@('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $plik) + $argumenty | ForEach-Object { & $q "$_" }) -join ' '
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $T
  foreach ($k in @($psi.EnvironmentVariables.Keys)) { if ($k -match $ZmienneZakazane) { $psi.EnvironmentVariables.Remove($k) } }
  $s = @{ USERPROFILE = $dom; HOME = $dom; HOMEDRIVE = $dom.Substring(0, 2); HOMEPATH = $dom.Substring(2)
          LOCALAPPDATA = (Join-Path $dom 'AppData\Local'); APPDATA = (Join-Path $dom 'AppData\Roaming'); TEMP = $Tmp; TMP = $Tmp
          PATH = (@($Bin, $KatGit, $KatGitUsr, $Systemowe) | Where-Object { $_ }) -join ';' }
  foreach ($k in $s.Keys) { $psi.EnvironmentVariables[$k] = $s[$k] }
  return $psi
}

function Odpal([string]$plik, [string[]]$argumenty, [int]$sekundy = 900, [string]$dom = $Dom) {
  $p = [System.Diagnostics.Process]::Start((Nowe-Psi $plik $argumenty $dom))
  $wy = $p.StandardOutput.ReadToEndAsync(); $bl = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($sekundy * 1000)) { & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null; return [pscustomobject]@{ Kod = -1; Tekst = "nie skonczyl w $sekundy s" } }
  $p.WaitForExit()
  return [pscustomobject]@{ Kod = $p.ExitCode; Tekst = ($wy.Result + "`n" + $bl.Result).Trim() }
}

$Akt = Join-Path $Repo 'narzedzia\aktualizuj-megaruchacza.ps1'
$PlikStanu = Join-Path $Dom '.claude\mr\aktualizacja.json'
$PlikZnacznika = Join-Path $Dom '.claude\mr\aktualizacja-naniesione.txt'
$PlikLogu = Join-Path $Dom '.claude\mr\aktualizacja.log'

function Aktualizuj([string[]]$extra = @(), [string]$zadanie = $Zadanie) {
  return (Odpal $Akt (@('-Zrodlo', $Repo, '-KatalogDomowy', $Dom, '-ZadanieNadzorcy', $zadanie) + $extra))
}
function Stan { $t = Czytaj $PlikStanu; if (-not $t) { return $null }; return ($t | ConvertFrom-Json) }
# Po restarcie stan konczy pomocnik (osobny proces) - czekamy na etap koncowy.
function Czekaj-Na-Koniec([int]$sekundy = 240) {
  $do = (Get-Date).AddSeconds($sekundy)
  while ((Get-Date) -lt $do) {
    $s = $null; try { $s = Stan } catch { $s = $null }
    if ($s -and (@('gotowe', 'blad') -contains $s.etap)) { return $s }
    Start-Sleep -Milliseconds 500
  }
  return (Stan)
}
function Znacznik { $z = @{}; foreach ($l in @((Czytaj $PlikZnacznika) -split '\r?\n')) { if ($l -match '^([\w.]+):\s*(.*)$') { $z[$Matches[1]] = $Matches[2].Trim() } }; return $z }
function Usun-Z-Znacznika([string]$klucz) {
  $l = @(((Czytaj $PlikZnacznika) -split '\r?\n') | Where-Object { $_ -and ($_ -notmatch ('^' + [regex]::Escape($klucz) + ':')) })
  [System.IO.File]::WriteAllText($PlikZnacznika, (($l -join "`r`n") + "`r`n"), $Utf8)
}
function Log-Od([int]$od) { $l = @([System.IO.File]::ReadAllLines($PlikLogu, $Utf8)); if ($l.Count -le $od) { return '' }; return (($l[$od..($l.Count - 1)]) -join "`n") }
function Linii-Logu { if (-not (Test-Path -LiteralPath $PlikLogu)) { return 0 }; return @([System.IO.File]::ReadAllLines($PlikLogu, $Utf8)).Count }
function Wersja-Repo { $n = $null; foreach ($m in [regex]::Matches((Czytaj (Join-Path $Repo 'ZMIANY.md')), '(?m)^##\s+(\d+)\.(\d+)\.(\d+)')) { $w = [version]("{0}.{1}.{2}" -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value); if (-not $n -or $w -gt $n) { $n = $w } }; return "$n" }
function Wypchnij-Wersje([string]$wersja) {
  $p = Join-Path $Pisarz 'ZMIANY.md'
  $t = Czytaj $p
  $i = $t.IndexOf("`n## ")
  $nowy = $t.Substring(0, $i + 1) + "## $wersja`r`n`r`n- MRTEST: wersja z testu aktualizacji`r`n`r`n" + $t.Substring($i + 1)
  [System.IO.File]::WriteAllText($p, $nowy, $Utf8)
  [void](Git-Cicho @('-C', $Pisarz, '-c', 'user.name=MRTEST', '-c', 'user.email=mrtest@example.invalid', 'commit', '--quiet', '-am', "MRTEST $wersja"))
  [void](Git-Cicho @('-C', $Pisarz, 'push', '--quiet', 'origin', 'HEAD:main'))
}
function Global-Wersja { $m = [regex]::Match("" + (Czytaj (Join-Path $Dom '.claude\.megaruchacz-global')), '(?m)^wersja:\s*(\S+)'); return $m.Groups[1].Value }
function Stary-Stub {
  # nadzorca "sprzed aktualizacji": zaslepka uruchomiona wprost, poza zadaniem
  $a = '--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $Repo 'zasobnik\nadzorca.ps1') + '" -Zrodlo "' + $Repo + '"'
  Start-Process -FilePath conhost.exe -ArgumentList $a -WindowStyle Hidden | Out-Null
  $do = (Get-Date).AddSeconds(20)
  while ((Get-Date) -lt $do) { $s = @(Stuby); if ($s.Count -gt 0) { return $s }; Start-Sleep -Milliseconds 300 }
  return @()
}

# ================================================================= PRZEBIEG
$OdciskPrzed = Odcisk-Prawdziwy
foreach ($z in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'MRTEST-AKT-*' })) { Unregister-ScheduledTask -TaskName $z.TaskName -Confirm:$false }
try {
  Przygotuj
  Info "katalog testu: $T"

  # --- kodowanie plikow tej zmiany
  foreach ($w in $MOJE) {
    $p = Join-Path $Repo $w
    if (-not (Test-Path -LiteralPath $p)) { continue }
    $b = [System.IO.File]::ReadAllBytes($p)
    $bom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
    $pl = @($b | Where-Object { $_ -gt 127 }).Count -gt 0
    $lf = 0; $crlf = 0; for ($i = 0; $i -lt $b.Length; $i++) { if ($b[$i] -eq 10) { if ($i -gt 0 -and $b[$i - 1] -eq 13) { $crlf++ } else { $lf++ } } }
    Sprawdz "kodowanie ${w}: CRLF$(if ($pl) { ' i BOM (polskie znaki)' })" (($lf -eq 0) -and ((-not $pl) -or $bom)) "BOM $bom, LF $lf, CRLF $crlf"
  }

  # --- 1. pierwszy przebieg: brak znacznika naniesienia -> nanosi i restartuje
  $stary = @(Stary-Stub)
  Sprawdz "1: zaslepka starego nadzorcy chodzi" ($stary.Count -eq 1) "procesy: $($stary -join ',')"
  $wersja0 = Wersja-Repo
  $head0 = Git-Cicho @('-C', $Repo, 'rev-parse', 'HEAD')
  $r = Aktualizuj
  $s = Czekaj-Na-Koniec
  Sprawdz "1: kod 0" ($r.Kod -eq 0) $r.Tekst
  Sprawdz "1: gotowe / zaktualizowano / krok 4 z 4" ($s.etap -eq 'gotowe' -and $s.wynik -eq 'zaktualizowano' -and $s.krok -eq 4 -and $s.krokow -eq 4) ($s | ConvertTo-Json -Compress)
  Sprawdz "1: wersja_przed = wersja_po = $wersja0" ($s.wersja_przed -eq $wersja0 -and $s.wersja_po -eq $wersja0) "$($s.wersja_przed) / $($s.wersja_po)"
  Sprawdz "1: start, koniec, sprawdzone (ISO), reczna false" (($s.start -match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$') -and ($s.koniec -match '^\d{4}-') -and ($s.sprawdzone -match '^\d{4}-') -and ($s.reczna -eq $false)) ($s | ConvertTo-Json -Compress)
  Sprawdz "1: instaluj-globalnie podniosl numer w .megaruchacz-global (0.0.1 -> $wersja0)" ((Global-Wersja) -eq $wersja0) (Global-Wersja)
  $log = Czytaj $PlikLogu
  foreach ($k in @('wolam instaluj-globalnie', 'wolam wpisz-zasady', 'wolam straznik -Dopasuj', 'pomocnik restartu wystartowal poza drzewem nadzorcy (WMI')) { Sprawdz "1: dziennik: $k" ($log.Contains($k)) "" }
  Sprawdz "1: skille wylaczone w rejestrze - nie wolane" ((-not $log.Contains('wolam skille')) -and -not (Test-Path (Join-Path $T 'skille-wolania.log'))) ""
  $zn = Znacznik
  Sprawdz "1: znacznik naniesienia: naniesione i nadzorca = HEAD" ($zn['naniesione'] -eq $head0 -and $zn['nadzorca'] -eq $head0 -and $zn['naniesione.wersja'] -eq $wersja0) ((Czytaj $PlikZnacznika))
  $po = @(Stuby)
  Sprawdz "1: stary nadzorca zamkniety, nowy wstal z zadania" ((@($po | Where-Object { $stary -contains $_ }).Count -eq 0) -and ($po.Count -eq 1)) "przed $($stary -join ','), po $($po -join ',')"
  Sprawdz "1: w dzienniku start przez zadanie Harmonogramu" ($log.Contains("wystartowane zadanie Harmonogramu $Zadanie") -or (Czytaj $PlikLogu).Contains("wystartowane zadanie Harmonogramu $Zadanie")) ""
  $sz = Czytaj (Join-Path $Dom '.claude\.megaruchacz-straznik.txt')
  Sprawdz "1: straznik zostawil byl.pobierz, nie byl.tlo" (($sz -match '(?m)^byl\.pobierz:') -and ($sz -notmatch '(?m)^byl\.tlo:')) $sz
  $bs = [System.IO.File]::ReadAllBytes($PlikStanu)
  Sprawdz "1: aktualizacja.json: UTF-8 bez BOM, bez zostawionych plikow tymczasowych" (($bs[0] -ne 0xEF) -and (@(Get-ChildItem -LiteralPath (Join-Path $Dom '.claude\mr') -Force -Filter '*.tmp-*').Count -eq 0)) ""
  Sprawdz "1: notatka uzytkownika w CLAUDE.md nietknieta" ((Czytaj (Join-Path $Dom '.claude\CLAUDE.md')).Contains('Notatka testowa (to zostaje).')) ""

  # --- 2. nic nowego
  $stubPrzed = @(Stuby)
  $od = Linii-Logu
  $r = Aktualizuj
  $s = Stan
  $dl = Log-Od $od
  Sprawdz "2: nic nowego - kod 0, gotowe / aktualne" ($r.Kod -eq 0 -and $s.etap -eq 'gotowe' -and $s.wynik -eq 'aktualne') ($s | ConvertTo-Json -Compress)
  Sprawdz "2: bez naniesienia i bez restartu" ((-not $dl.Contains('wolam instaluj-globalnie')) -and (-not $dl.Contains('pomocnik')) -and ((@(Stuby) -join ',') -eq ($stubPrzed -join ','))) $dl
  Sprawdz "2: wersja_przed = wersja_po, krok 1" ($s.wersja_przed -eq $wersja0 -and $s.wersja_po -eq $wersja0 -and $s.krok -eq 1) ($s | ConvertTo-Json -Compress)

  # --- 3. nowa wersja na serwerze (+ skille wlaczone)
  # Obcy nadzorca (ta sama zaslepka pod INNA sciezka - jak kopia testowa test-p7 albo drugie repo):
  # restart tego repo nie ma prawa go zamknac.
  $obcy = Join-Path $T 'obcy\x\zasobnik\nadzorca.ps1'
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $obcy) | Out-Null
  [System.IO.File]::WriteAllText($obcy, ((Czytaj (Join-Path $Repo 'zasobnik\nadzorca.ps1')) -replace 'stub-nadzorcy\.log', 'stub-obcy.log'), $Utf8)
  Start-Process -FilePath conhost.exe -ArgumentList ('--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $obcy + '"') -WindowStyle Hidden | Out-Null
  $do = (Get-Date).AddSeconds(20)
  $pidObcy = $null
  while ((Get-Date) -lt $do -and -not $pidObcy) {
    $pidObcy = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($obcy, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | ForEach-Object { $_.ProcessId }) | Select-Object -First 1
    Start-Sleep -Milliseconds 300
  }
  Ustaw-Rejestr $true
  Wypchnij-Wersje '99.1.0'
  $stubPrzed = @(Stuby)
  $r = Aktualizuj
  $s = Czekaj-Na-Koniec
  Sprawdz "3: nowa wersja - kod 0, gotowe / zaktualizowano" ($r.Kod -eq 0 -and $s.etap -eq 'gotowe' -and $s.wynik -eq 'zaktualizowano') ($s | ConvertTo-Json -Compress)
  Sprawdz "3: wersja_przed $wersja0, wersja_po 99.1.0" ($s.wersja_przed -eq $wersja0 -and $s.wersja_po -eq '99.1.0') "$($s.wersja_przed) / $($s.wersja_po)"
  Sprawdz "3: kopia przewinieta na wersje z serwera" ((Git-Cicho @('-C', $Repo, 'rev-parse', 'HEAD')) -eq (Git-Cicho @('-C', $Pisarz, 'rev-parse', 'HEAD'))) ""
  Sprawdz "3: .megaruchacz-global ma 99.1.0 (naniesione nowym kodem)" ((Global-Wersja) -eq '99.1.0') (Global-Wersja)
  $sk = Czytaj (Join-Path $T 'skille-wolania.log')
  Sprawdz "3: skille wlaczone - dograne (-Tryb instaluj -Wbudowane)" ("$sk" -match '-Tryb instaluj -Wbudowane') "$sk"
  $po = @(Stuby)
  Sprawdz "3: restart - nowy proces nadzorcy" (($po.Count -eq 1) -and ($stubPrzed -notcontains $po[0])) "przed $($stubPrzed -join ','), po $($po -join ',')"
  Sprawdz "3: nadzorca spod innej sciezki przezyl restart" ($pidObcy -and [bool](Get-Process -Id $pidObcy -ErrorAction SilentlyContinue)) "PID obcego: $pidObcy"

  # --- 3b. skille zawodza - uwaga, nie blad
  [System.IO.File]::WriteAllText((Join-Path $T 'skille-kod.txt'), '1', $Utf8)
  Wypchnij-Wersje '99.1.1'
  $r = Aktualizuj
  $s = Czekaj-Na-Koniec
  Sprawdz "3b: skille z kodem 1 - dalej zaktualizowano, z uwaga o skillach" ($s.wynik -eq 'zaktualizowano' -and (@($s.uwagi) -join ' ') -match 'skilli') ($s | ConvertTo-Json -Compress)
  Remove-Item -LiteralPath (Join-Path $T 'skille-kod.txt') -Force

  # --- 4. lokalna zmiana w pliku, ktory zmienia nowa wersja
  Wypchnij-Wersje '99.2.0'
  $zm = Join-Path $Repo 'ZMIANY.md'
  [System.IO.File]::AppendAllText($zm, "`r`nMRTEST: lokalna zmiana uzytkownika`r`n", $Utf8)
  $headPrzed = Git-Cicho @('-C', $Repo, 'rev-parse', 'HEAD')
  $stubPrzed = @(Stuby)
  $r = Aktualizuj
  $s = Stan
  Sprawdz "4: zablokowane - kod 1, etap blad, wynik blad, przyczyna zablokowane" ($r.Kod -eq 1 -and $s.etap -eq 'blad' -and $s.wynik -eq 'blad' -and $s.przyczyna -eq 'zablokowane') ($s | ConvertTo-Json -Compress)
  Sprawdz "4: powod po ludzku i z plikiem (ZMIANY.md)" (("$($s.powod)" -match 'nadpisa') -and ("$($s.powod)" -match 'ZMIANY\.md')) "$($s.powod)"
  Sprawdz "4: lokalna zmiana nietknieta, HEAD bez zmian, bez restartu" (((Czytaj $zm).Contains('MRTEST: lokalna zmiana uzytkownika')) -and ((Git-Cicho @('-C', $Repo, 'rev-parse', 'HEAD')) -eq $headPrzed) -and ((@(Stuby) -join ',') -eq ($stubPrzed -join ','))) ""
  Sprawdz "4: sprawdzone odswiezone (serwer odpowiedzial)" ("$($s.sprawdzone)" -match '^\d{4}-') ""
  [void](Git-Cicho @('-C', $Repo, 'checkout', '--quiet', '--', 'ZMIANY.md'))
  $r = Aktualizuj
  $s = Czekaj-Na-Koniec
  Sprawdz "4: po zdjeciu zmiany - zaktualizowano do 99.2.0" ($s.wynik -eq 'zaktualizowano' -and $s.wersja_po -eq '99.2.0') ($s | ConvertTo-Json -Compress)

  # --- 5. blokada
  $blok = New-Object System.Threading.Mutex($false, ("Local\MegaRuchacz-aktualizacja-" + (Skrot16 $Repo.TrimEnd('\').ToLower())))
  [void]$blok.WaitOne(0)
  $przedB = Skrot-Pliku $PlikStanu
  $od = Linii-Logu
  $r = Aktualizuj
  $blok.ReleaseMutex(); $blok.Dispose()
  Sprawdz "5: blokada trzymana - kod 3, stan nietkniety co do bajtu" ($r.Kod -eq 3 -and (Skrot-Pliku $PlikStanu) -eq $przedB) "kod $($r.Kod) $($r.Tekst)"
  Sprawdz "5: w dzienniku slad odpuszczenia" ((Log-Od $od).Contains('inny przebieg aktualizacji wlasnie pracuje')) (Log-Od $od)
  $kody = @()
  for ($proba = 1; $proba -le 3; $proba++) {
    $p1 = [System.Diagnostics.Process]::Start((Nowe-Psi $Akt @('-Zrodlo', $Repo, '-KatalogDomowy', $Dom, '-ZadanieNadzorcy', $Zadanie)))
    $p2 = [System.Diagnostics.Process]::Start((Nowe-Psi $Akt @('-Zrodlo', $Repo, '-KatalogDomowy', $Dom, '-ZadanieNadzorcy', $Zadanie)))
    foreach ($p in @($p1, $p2)) { [void]$p.StandardOutput.ReadToEndAsync(); [void]$p.StandardError.ReadToEndAsync() }
    [void]$p1.WaitForExit(300000); [void]$p2.WaitForExit(300000)
    $kody = @($p1.ExitCode, $p2.ExitCode) | Sort-Object
    if (($kody -join ',') -eq '0,3') { break }
    Info "dwa starty naraz, proba ${proba}: kody $($kody -join ',') - powtarzam"
  }
  Sprawdz "5: dwa starty naraz - jeden przebieg (kody 0 i 3)" (($kody -join ',') -eq '0,3') "kody $($kody -join ',')"
  Sprawdz "5: po dwoch startach stan spojny (gotowe / aktualne)" ((Stan).etap -eq 'gotowe' -and (Stan).wynik -eq 'aktualne') ((Stan) | ConvertTo-Json -Compress)

  # --- 6. restart: brak zadania, nadzorca padajacy na starcie, naprawa
  Usun-Z-Znacznika 'nadzorca'
  $stubPrzed = @(Stuby)
  $r = Aktualizuj @() "MRTEST-AKT-brak-$Stempel"
  $s = Czekaj-Na-Koniec
  $po = @(Stuby)
  Sprawdz "6: zadania nie ma - nadzorca wstal wprost, gotowe z uwaga o Harmonogramie" ($s.etap -eq 'gotowe' -and ((@($s.uwagi) -join ' ') -match 'Harmonogramu') -and $po.Count -eq 1 -and ($stubPrzed -notcontains $po[0])) ($s | ConvertTo-Json -Compress)
  Sprawdz "6: znacznik nadzorca odnotowany po udanym restarcie" ((Znacznik)['nadzorca'] -eq (Git-Cicho @('-C', $Repo, 'rev-parse', 'HEAD'))) ""
  [System.IO.File]::WriteAllText((Join-Path $T 'stub-pada.txt'), 'x', $Utf8)
  Usun-Z-Znacznika 'nadzorca'
  $r = Aktualizuj
  $s = Czekaj-Na-Koniec 300
  Sprawdz "6: nadzorca pada na starcie - etap blad, przyczyna restart, powod mowi co zrobic" ($s.etap -eq 'blad' -and $s.przyczyna -eq 'restart' -and ("$($s.powod)" -match 'zaloguj')) ($s | ConvertTo-Json -Compress)
  Sprawdz "6: znacznik nadzorca NIE odnotowany po nieudanym restarcie" (-not (Znacznik)['nadzorca']) ""
  Remove-Item -LiteralPath (Join-Path $T 'stub-pada.txt') -Force
  $r = Aktualizuj
  $s = Czekaj-Na-Koniec
  Sprawdz "6: po naprawie - nastepny przebieg restartuje i konczy gotowe" ($s.etap -eq 'gotowe' -and $s.wynik -eq 'zaktualizowano' -and @(Stuby).Count -eq 1) ($s | ConvertTo-Json -Compress)

  # --- 7. straznik zajety dluzej, niz -TylkoPobierz czeka
  if (-not $BezCzekaniaNaBlokade) {
    $zr = New-Object System.Threading.Mutex($false, 'Local\MegaRuchacz-zrodlo')
    $mamZr = $false
    try { $mamZr = $zr.WaitOne(30000) } catch { $mamZr = $true }
    if ($mamZr) {
      $t0 = Get-Date
      $r = Aktualizuj
      $sek = [int]((Get-Date) - $t0).TotalSeconds
      $zr.ReleaseMutex()
      $s = Stan
      Sprawdz "7: blokada pobierania zajeta - straznik czekal ~120 s, wynik zajete -> blad z miekka przyczyna" ($r.Kod -eq 1 -and $s.przyczyna -eq 'zajete' -and $sek -ge 115) "kod $($r.Kod), $sek s, $($s | ConvertTo-Json -Compress)"
    } else { Sprawdz "7: blokada pobierania" $false "nie dostalem Local\MegaRuchacz-zrodlo w 30 s (pobiera prawdziwy straznik?)" }
    $zr.Dispose()
    # Pomocnik restartu, ktoremu nikt nie oddaje blokady aktualizacji: po 120 s blad, nikogo nie zamyka.
    $stubPrzed = @(Stuby)
    $blok = New-Object System.Threading.Mutex($false, ("Local\MegaRuchacz-aktualizacja-" + (Skrot16 $Repo.TrimEnd('\').ToLower())))
    [void]$blok.WaitOne(0)
    $t0 = Get-Date
    $r = Odpal $Akt @('-Restart', '-Zrodlo', $Repo, '-KatalogDomowy', $Dom, '-ZadanieNadzorcy', $Zadanie, '-Commit', 'abc')
    $sek = [int]((Get-Date) - $t0).TotalSeconds
    $blok.ReleaseMutex(); $blok.Dispose()
    $s = Stan
    Sprawdz "7: pomocnik bez blokady - po ~120 s blad blokada-pomocnika, nadzorca nietkniety" ($r.Kod -eq 1 -and $s.przyczyna -eq 'blokada-pomocnika' -and $sek -ge 115 -and ((@(Stuby) -join ',') -eq ($stubPrzed -join ','))) "kod $($r.Kod), $sek s, $($s | ConvertTo-Json -Compress)"
  } else { Info "7 pominiete (-BezCzekaniaNaBlokade)" }

  # --- 8. alarm Alarm-Aktualizacji (w osobnym procesie, na wlasnym domu)
  $DomA = Join-Path $T 'dom-alarm'
  New-Item -ItemType Directory -Force -Path (Join-Path $DomA '.claude\mr') | Out-Null
  $skryptA = Join-Path $T 'alarm.ps1'
  [System.IO.File]::WriteAllText($skryptA, @'
param([string]$Zr, [string]$Dom, [string]$Json, [string]$Stan, [string]$Zbierz = "")
$ErrorActionPreference = "Stop"
. (Join-Path $Zr "zasobnik\stan-nadzorcy.ps1")
Ustaw-Nadzorce $Zr $Dom $true
$pj = Join-Path $Dom ".claude\mr\aktualizacja.json"
if ($Json -eq "BRAK") { Remove-Item -LiteralPath $pj -Force -ErrorAction SilentlyContinue } else { [IO.File]::WriteAllText($pj, $Json) }
[IO.File]::WriteAllText((Join-Path $Dom ".claude\.megaruchacz-zasobnik.txt"), ($Stan -replace '\|', "`r`n"))
if ($Zbierz) { $d = Zbierz-Wszystko $false $false; $a = @($d.Alarmy | Where-Object { $_.Temat -eq "aktualizacja" }) | Select-Object -First 1 }
else { $a = Alarm-Aktualizacji }
if ($a) { "ALARM|$($a.Temat)|$($a.Waga)|$($a.Tytul)" } else { "BRAK" }
'@, $Utf8)
  $f = { param($d) (Get-Date).AddMinutes(-$d).ToString('yyyy-MM-ddTHH:mm:ss') }
  $g = { param($d) (Get-Date).AddMinutes(-$d).ToString('yyyy-MM-dd HH:mm:ss') }
  function J($etap, $przyczyna = '', $start = 1, $koniec = 1, $spr = 1, $pid_ = 999999) {
    $o = [ordered]@{ etap = $etap; krok = 1; krokow = 4; opis = 'x'; wynik = $(if ($etap -eq 'blad') { 'blad' } elseif ($etap -eq 'gotowe') { 'aktualne' } else { '' })
                     start = (& $f $start); koniec = $(if ($null -ne $koniec) { & $f $koniec } else { '' }); sprawdzone = $(if ($null -ne $spr) { & $f $spr } else { '' })
                     powod = 'Powod testowy. Co zrobic.'; przyczyna = $przyczyna; pid = $pid_ }
    return ($o | ConvertTo-Json -Compress)
  }
  $przypadki = @(
    @{ n = 'brak pliku i sladow zegara - cisza (zaden falszywy alarm)'; j = 'BRAK'; s = ''; w = 'BRAK' },
    @{ n = 'blad bez sladow zegara - cisza (blad pokazuje karta Stan, bez drugiej karty)'; j = (J 'blad' 'zablokowane'); s = ''; w = 'BRAK' },
    @{ n = 'blad po zleceniu - cisza (karta Stan)'; j = (J 'blad' 'zablokowane' 20 19 19); s = "byl: $(& $g 5)|aktualizacja.zaplanowana: $(& $g 300)|aktualizacja.zlecona: $(& $g 240)"; w = 'BRAK' },
    @{ n = 'przebieg w toku od 2 h, zlecony 2 h temu - cisza (urwany przebieg pokazuje karta Stan)'; j = (J 'nanosze' '' 120 $null 120); s = "aktualizacja.zlecona: $(& $g 120)"; w = 'BRAK' },
    @{ n = 'zlecona 20 min temu, ostatni koniec 30 min temu - alarm uwaga'; j = (J 'gotowe' '' 31 30 30); s = "aktualizacja.zlecona: $(& $g 20)"; w = 'ALARM|aktualizacja|uwaga' },
    @{ n = 'zlecona 20 min temu, koniec 19 min temu - cisza'; j = (J 'gotowe' '' 20 19 19); s = "aktualizacja.zlecona: $(& $g 20)"; w = 'BRAK' },
    @{ n = 'zlecona 5 min temu, ostatni koniec 30 min temu - cisza (prog 15 min)'; j = (J 'gotowe' '' 31 30 30); s = "aktualizacja.zlecona: $(& $g 5)"; w = 'BRAK' },
    @{ n = 'zlecona 20 min temu, pliku postepu brak - cisza (brak pliku pokazuje karta Stan)'; j = 'BRAK'; s = "aktualizacja.zlecona: $(& $g 20)"; w = 'BRAK' },
    @{ n = 'zlecona 20 min temu, plik postepu nieczytelny - cisza (karta Stan)'; j = '{ to nie jest json'; s = "aktualizacja.zlecona: $(& $g 20)"; w = 'BRAK' },
    @{ n = 'zlecona 20 min temu, ostatnie sprawdzenie 4 h temu - cisza (nieswiezosc pokazuje karta Stan)'; j = (J 'gotowe' '' 241 240 240); s = "aktualizacja.zlecona: $(& $g 20)"; w = 'BRAK' },
    @{ n = 'zegar wstal 4 h temu, nic nie zlecil, nadzorca chodzi, reczna aktualizacja 30 min temu - alarm uwaga'; j = (J 'gotowe' '' 31 30 30); s = "byl: $(& $g 5)|aktualizacja.zaplanowana: $(& $g 240)"; w = 'ALARM|aktualizacja|uwaga' },
    @{ n = 'zegar wstal 2 h temu, nic nie zlecil - cisza (prog 3 h)'; j = (J 'gotowe' '' 31 30 30); s = "byl: $(& $g 5)|aktualizacja.zaplanowana: $(& $g 120)"; w = 'BRAK' },
    @{ n = 'zegar wstal 4 h temu, nadzorca nie chodzi od 2 h - cisza'; j = (J 'gotowe' '' 31 30 30); s = "byl: $(& $g 120)|aktualizacja.zaplanowana: $(& $g 240)"; w = 'BRAK' },
    @{ n = 'ostatnie zlecenie 4 h temu, reczna aktualizacja 30 min temu, nadzorca chodzi - alarm uwaga'; j = (J 'gotowe' '' 31 30 30); s = "byl: $(& $g 5)|aktualizacja.zaplanowana: $(& $g 600)|aktualizacja.zlecona: $(& $g 240)"; w = 'ALARM|aktualizacja|uwaga' },
    @{ n = 'zlecona 30 min temu, gotowe po niej, nadzorca chodzi - cisza'; j = (J 'gotowe' '' 30 29 29); s = "byl: $(& $g 5)|aktualizacja.zaplanowana: $(& $g 600)|aktualizacja.zlecona: $(& $g 30)"; w = 'BRAK' }
  )
  foreach ($c in $przypadki) {
    $wy = Odpal $skryptA @('-Zr', $Repo, '-Dom', $DomA, '-Json', $c.j, '-Stan', $c.s) 120 $DomA
    $ostatnia = @(($wy.Tekst -split '\r?\n') | Where-Object { $_ -match '^(ALARM|BRAK)' } | Select-Object -Last 1)
    Sprawdz "8: $($c.n)" (($ostatnia.Count -eq 1) -and $ostatnia[0].StartsWith($c.w)) "$($wy.Tekst)"
  }
  $wy = Odpal $skryptA @('-Zr', $Repo, '-Dom', $DomA, '-Json', (J 'gotowe' '' 31 30 30), '-Stan', "aktualizacja.zlecona: $(& $g 20)", '-Zbierz', '1') 300 $DomA
  Sprawdz "8: Zbierz-Wszystko niesie alarm aktualizacji w Alarmy" ($wy.Tekst -match 'ALARM\|aktualizacja\|uwaga') "$($wy.Tekst)"

  # --- 9. zegar w dozorze (osobny proces; zrodlo z zaslepka aktualizacji, zeby nic naprawde nie ruszylo)
  $ZrZ = Join-Path $T 'zrodlo-zegar'
  New-Item -ItemType Directory -Force -Path (Join-Path $ZrZ 'narzedzia') | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $ZrZ 'narzedzia\aktualizuj-megaruchacza.ps1'), "Add-Content -LiteralPath '$(Join-Path $T 'zegar-wolania.log')' -Value (`$args -join ' ')`r`n", $Utf8)
  $DomZ = Join-Path $T 'dom-zegar'
  New-Item -ItemType Directory -Force -Path (Join-Path $DomZ '.claude\mr') | Out-Null
  $skryptZ = Join-Path $T 'zegar.ps1'
  [System.IO.File]::WriteAllText($skryptZ, @'
param([string]$Zr, [string]$ZrAkt, [string]$Dom, [int]$Czekaj = 25)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
$script:ModulyOkna = @{}
. (Join-Path $Zr "zasobnik\stan-nadzorcy.ps1")
Ustaw-Nadzorce $ZrAkt $Dom $false
. (Join-Path $Zr "zasobnik\nadzorca\dozor.ps1")
$SEKUNDY_DO_PIERWSZEJ_AKTUALIZACJI = 2
$t0 = Get-Date
Zaplanuj-Aktualizacje
Zaplanuj-Aktualizacje
$do = (Get-Date).AddSeconds($Czekaj)
while ((Get-Date) -lt $do) {
  [System.Windows.Forms.Application]::DoEvents()
  $s = Czytaj-Klucze $script:NadzPlikStanu
  if ($s["aktualizacja.zlecona"] -or ($script:NadzWywrotki.Count -gt 0)) { break }
  Start-Sleep -Milliseconds 100
}
$s = Czytaj-Klucze $script:NadzPlikStanu
"ZAPLANOWANA=" + $s["aktualizacja.zaplanowana"]
"ZLECONA=" + $s["aktualizacja.zlecona"]
"SEKUND=" + [int]((Get-Date) - $t0).TotalSeconds
"INTERWAL=" + $script:ZegarAutoAktualizacji.Interval
"WYWROTKI=" + ($script:NadzWywrotki -join " || ")
'@, $Utf8)
  $wy = Odpal $skryptZ @('-Zr', $Repo, '-ZrAkt', $ZrZ, '-Dom', $DomZ) 120 $DomZ
  $do = (Get-Date).AddSeconds(20)
  while ((Get-Date) -lt $do -and -not (Test-Path (Join-Path $T 'zegar-wolania.log'))) { Start-Sleep -Milliseconds 300 }
  $zw = Czytaj (Join-Path $T 'zegar-wolania.log')
  Sprawdz "9: zegar odpalil po zadanym czasie, slady zaplanowana i zlecona" (($wy.Tekst -match 'ZAPLANOWANA=\d{4}') -and ($wy.Tekst -match 'ZLECONA=\d{4}') -and ($wy.Tekst -match 'SEKUND=([2-9]|1\d)\b')) $wy.Tekst
  Sprawdz "9: po pierwszym odpaleniu zegar co 60 min" ($wy.Tekst -match 'INTERWAL=3600000') $wy.Tekst
  Sprawdz "9: skrypt aktualizacji zawolany w tle z -Zrodlo i -KatalogDomowy, jeden raz" (("$zw" -match [regex]::Escape("-Zrodlo $ZrZ -KatalogDomowy $DomZ")) -and (@(("$zw" -split '\r?\n') | Where-Object { $_ }).Count -eq 1)) "$zw"
  $ZrBez = Join-Path $T 'zrodlo-bez-skryptu'
  New-Item -ItemType Directory -Force -Path $ZrBez | Out-Null
  $DomZ2 = Join-Path $T 'dom-zegar2'
  New-Item -ItemType Directory -Force -Path (Join-Path $DomZ2 '.claude\mr') | Out-Null
  $wy = Odpal $skryptZ @('-Zr', $Repo, '-ZrAkt', $ZrBez, '-Dom', $DomZ2, '-Czekaj', '10') 120 $DomZ2
  Sprawdz "9: bez skryptu aktualizacji - wywrotka zanotowana, slad zlecona NIE powstaje" (($wy.Tekst -match 'WYWROTKI=.*start aktualizacji automatycznej.*nie ma') -and ($wy.Tekst -match '(?m)^ZLECONA=\s*$')) $wy.Tekst

} catch {
  Sprawdz "przebieg testu bez wywrotki" $false "$($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
} finally {
  # sprzatanie: zaslepki nadzorcy, zadanie testowe, procesy z katalogu testu
  try { [System.IO.File]::WriteAllText((Join-Path $T 'stub-stop.txt'), 'x', $Utf8) } catch { Write-Host "nie zalozylem pliku stopu: $($_.Exception.Message)" }
  Start-Sleep -Seconds 3
  foreach ($p in @(Procesy-Testu)) { try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop } catch { Write-Host "nie zamknalem PID $($p.ProcessId): $($_.Exception.Message)" } }
  foreach ($z in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'MRTEST-AKT-*' })) {
    try { Unregister-ScheduledTask -TaskName $z.TaskName -Confirm:$false -ErrorAction Stop } catch { Write-Host "nie zdjalem zadania $($z.TaskName): $($_.Exception.Message)" }
  }
}
Start-Sleep -Seconds 2
Sprawdz "sprzatanie: zadnego procesu z katalogu testu" (@(Procesy-Testu).Count -eq 0) ((@(Procesy-Testu) | ForEach-Object { "$($_.ProcessId) $($_.CommandLine)" }) -join ' || ')
Sprawdz "sprzatanie: zadnego zadania MRTEST-AKT-*" (@(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'MRTEST-AKT-*' }).Count -eq 0) ""
$OdciskPo = Odcisk-Prawdziwy
$rozne = @($OdciskPrzed.Keys | Where-Object { $OdciskPrzed[$_] -ne $OdciskPo[$_] })
Sprawdz "prawdziwy stan nietkniety (pliki aktualizacji i instalacji, zadanie nadzorcy, PID nadzorcy)" ($rozne.Count -eq 0) (($rozne | ForEach-Object { "${_}: $($OdciskPrzed[$_]) -> $($OdciskPo[$_])" }) -join '; ')
if (-not $Zostaw -and $script:Zle -eq 0) { Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue } else { Info "katalog testu zostaje: $T" }
Write-Host ""
Write-Host "Wynik: $($script:Ok) z $($script:Ok + $script:Zle) OK"
if ($script:Zle -gt 0) { exit 1 }
exit 0
