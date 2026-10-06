# instalator\test-calosci.ps1 - PROBA CALOSCI instalatora (P64): okno (poza ekranem, jak
# test-instalatora.ps1) z PRAWDZIWYMI skryptami modulow, na kopii repo i na kopii katalogu domowego.
#
# Kolejne kroki stoja na poprzednim (jeden dom przez cala probe):
#   a  nowa instalacja "Wszystko" z kopia zapasowa do folderu tymczasowego
#   b  zmiana: bez Pamieci rozmow (Wiedza przechodzi na indeks "tylko tekst"), potem Lore z powrotem
#   c  zmiana: bez Trybu kierownika
#   d  "Usun MegaRuchacza" bez danych ->
#      ponowna instalacja "Wszystko" -> "Usun MegaRuchacza" z danymi
# Po kazdym kroku w katalogu probnym: rejestr, bloki w CLAUDE.md / AGENTS.md Codeksa / kopii dla
# opencode, "Co wiem" co do bajtu, hooki (nasze po jednym, cudze nietkniete), role agentow, MCP,
# zadania, pliki; do tego straznik uruchomiony jak hook SessionStart niczego nie zmienia ani nie
# dubluje, a cykl wiedzy rusza tylko z modulem Wiedza.
#
# BEZPIECZENSTWO (wzor: narzedzia\instalacja\test-moduly.ps1, P59b):
#  - repo: git clone tego repo + niezapisane zmiany (poza .megaruchacz\). W KOPII: nazwy zadan
#    z przedrostkiem MRTEST- (zliczane w 5 plikach), data startu 2099, start nadzorcy zablokowany,
#    zamykanie nadzorcy widzi tylko procesy z MRTEST; "origin" kopii to zamrozony goly klon, wiec
#    straznik nie przewinie kopii; cykl wiedzy i kolejka faktow to zaslepki (zaden model nie rusza);
#  - okno i wszystko, co uruchamia: USERPROFILE/HOME/LOCALAPPDATA/APPDATA/TEMP w katalogu testu,
#    PATH z atrapami claude/codex/opencode NA POCZATKU (Odswiez-Path w oknie dokleja PATH z rejestru
#    dopiero za nim), bez CODEX_HOME/LORE_HOME/CLAUDE_CONFIG_DIR/ANTHROPIC_*/ORCA_*; uv z prawdziwa
#    pamiecia podreczna; model wektorow skopiowany z prawdziwego katalogu (bez pobierania 496 MB);
#  - przed i po: odcisk prawdziwego stanu (zadania MegaRuchacza z akcjami, PATH uzytkownika, pliki
#    konfiguracji, MCP w ~\.claude.json, PID nadzorcy) - musi sie zgadzac; zadna prawdziwa
#    konfiguracja nie moze wskazywac MRTEST; na koncu zero zadan MRTEST-* i procesow z kopii.
#  Polecane skille: modul skille pobiera prawdziwe zrodla z GitHuba (siec potrzebna; bez niej UWAGA).
#  Czego proba NIE sprawdza: startu nadzorcy (w kopii zablokowany - pokazalby okno), prawdziwej instalacji
#  programow (sa na maszynie - zaleznosci.ps1 mowi "wszystko jest"; instalacje przenosne sprawdza test-moduly),
#  prawdziwych claude/codex mcp add (atrapy) i przebiegu kopii (zadanie z data 2099). Trwa ok. 6 min.
#
# Uzycie (niewidocznie):
#   powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File instalator\test-calosci.ps1
#     [-Katalog <kat>] [-Zrzuty <kat>] [-Przedrostek P64] [-Zostaw] [-DoKroku a|b|c|d]
#   -DoKroku   zatrzymuje probe po danym kroku (kazdy krok stoi na poprzednim, wiec zawsze od a)
# Kod wyjscia: 0 = wszystko przeszlo, 1 = cos nie.
param(
  [string]$Katalog = $env:TEMP,
  [string]$Zrzuty = '',
  [string]$Przedrostek = 'P64',
  [switch]$Zostaw,
  [ValidateSet('a', 'b', 'c', 'd')][string]$DoKroku = 'd'
)
$KolejKrokow = @('a', 'b', 'c', 'd')
function Chce([string]$k) { return ($KolejKrokow.IndexOf($k) -le $KolejKrokow.IndexOf($DoKroku)) }

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$RepoPrawdziwe = Split-Path -Parent $PSScriptRoot
if (-not $Zrzuty) { $Zrzuty = Join-Path $RepoPrawdziwe '.megaruchacz\raporty' }
$Stempel = Get-Date -Format 'MMdd-HHmmss'
$T = Join-Path $Katalog "MRTEST-C-$Stempel"   # krotko: .venv ma sciezki blisko 260 znakow
$Repo = Join-Path $T 'repo'
$Bin = Join-Path $T 'bin'
$Dom = Join-Path $T 'dom'
$Projekt = Join-Path $T 'projekt'
$Kopie = Join-Path $T 'kopie'
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) "MRTEST-ct-$Stempel"
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$script:Wynik = @()
$script:Zle = 0
$script:Info = @()
$script:Log = Join-Path $T 'przebieg.log'

function Pisz-Log([string]$tx) { try { [System.IO.File]::AppendAllText($script:Log, ("{0} {1}`r`n" -f (Get-Date -Format 'HH:mm:ss'), $tx), $Utf8) } catch { Write-Host "nie zapisalem dziennika: $($_.Exception.Message)" } }
function Sprawdz([string]$co, [bool]$ok, [string]$szczegol = '') {
  $linia = $(if ($ok) { 'OK    ' } else { 'BLAD  ' }) + $co
  if (-not $ok -and $szczegol) {
    $s = ($szczegol -replace '\s+', ' ')
    if ($s.Length -gt 2400) { $s = $s.Substring(0, 400) + ' [...] ' + $s.Substring($s.Length - 2000) }
    $linia += ' -- ' + $s
  }
  $script:Wynik += $linia
  Write-Host $linia
  Pisz-Log $linia
  if (-not $ok) { $script:Zle++ }
}
function Info([string]$tx) { $script:Info += $tx; Write-Host "INFO  $tx"; Pisz-Log "INFO  $tx" }
function Czytaj([string]$p) { if (-not (Test-Path -LiteralPath $p)) { return $null }; return [System.IO.File]::ReadAllText($p, $Utf8) }
function Skrot([string]$p) { if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return '-' }; return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Ile([string]$tekst, [string]$co) { if ($null -eq $tekst) { return 0 }; return ([regex]::Matches($tekst, [regex]::Escape($co))).Count }
function Git-Cicho([string[]]$a) {
  $stare = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $wy = & git @a 2>&1; $kod = $LASTEXITCODE } finally { $ErrorActionPreference = $stare }
  if ($kod -ne 0) { throw "git $($a -join ' ') zakonczyl sie kodem ${kod}: $($wy -join ' ')" }
}

# ---------------------------------------------------------------- odcisk prawdziwego stanu

$ZadaniaPrawdziwe = @('MegaRuchaczNadzorca', 'LoreIndex', 'LoreKoszt', 'MegaRuchaczKopia', 'MegaRuchaczOdswiez', 'LoreCykl', 'LoreCyklPonow', 'LoreFacts', 'LoreWiedza')
$PlikiPrawdziwe = @('.claude\CLAUDE.md', '.claude\settings.json', '.codex\AGENTS.md', '.codex\config.toml', '.codex\hooks.json',
                    '.config\opencode\AGENTS.md', '.config\opencode\opencode.json', '.claude\mr\instalacja.json',
                    '.claude\mr\orchestrator-reminder.json', '.claude\megaruchacz-mr-log.js', '.claude\.megaruchacz-global')

function Odcisk-Prawdziwy {
  $o = [ordered]@{}
  foreach ($n in $ZadaniaPrawdziwe) {
    $z = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
    $o["zadanie.$n"] = if ($z) { (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes((Export-ScheduledTask -TaskName $n))))).Hash } else { '-' }
  }
  $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
  $o['path.uzytkownika'] = [string]$k.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  $k.Close()
  foreach ($p in $PlikiPrawdziwe) { $o["plik.$p"] = Skrot (Join-Path $HOME $p) }
  foreach ($kat in @('.claude\agents', '.codex\agents', '.config\opencode\agents')) {
    $o["katalog.$kat"] = (@(Get-ChildItem -LiteralPath (Join-Path $HOME $kat) -File -Force -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { "$($_.Name)=$((Get-FileHash -LiteralPath $_.FullName).Hash)" }) -join ';')
  }
  # ~\.claude.json pisze sam Claude Code (stan sesji) - porownujemy samo mcpServers (node, bo ConvertFrom-Json
  # w PS 5.1 nie czyta kluczy rozniacych sie wielkoscia liter)
  $o['mcp.claude.json'] = (& node -e "const j=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));process.stdout.write(JSON.stringify(j.mcpServers||null))" (Join-Path $HOME '.claude.json') 2>&1) -join ''
  $o['nadzorca.pid'] = (@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf((Join-Path $RepoPrawdziwe 'zasobnik\nadzorca.ps1'), [StringComparison]::OrdinalIgnoreCase) -ge 0 } | ForEach-Object { $_.ProcessId } | Sort-Object) -join ',')
  return $o
}

function Prawdziwe-Wskazuja-Test {
  $zle = @()
  foreach ($p in @('.claude\settings.json', '.claude.json', '.claude\CLAUDE.md', '.codex\config.toml', '.codex\AGENTS.md', '.codex\hooks.json', '.config\opencode\opencode.json', '.claude\mr\instalacja.json')) {
    $f = Join-Path $HOME $p
    if ((Test-Path $f) -and ([System.IO.File]::ReadAllText($f).IndexOf('MRTEST', [StringComparison]::OrdinalIgnoreCase) -ge 0)) { $zle += $p }
  }
  return $zle
}

function Zdejmij-Zadania-Testu {
  foreach ($z in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'MRTEST-*' })) {
    try { Unregister-ScheduledTask -TaskName $z.TaskName -Confirm:$false -ErrorAction Stop } catch { Write-Host "BLAD  nie zdjalem zadania $($z.TaskName): $($_.Exception.Message)" }
  }
}

function Procesy-Testu {
  return @(Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and (($_.CommandLine.IndexOf($T, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($_.CommandLine.IndexOf($Tmp, [StringComparison]::OrdinalIgnoreCase) -ge 0)) })
}

function Czekaj-Na-Tlo([int]$sekundy = 300) {
  $wzor = Join-Path $Repo 'lore'
  $koniec = (Get-Date).AddSeconds($sekundy)
  while ((Get-Date) -lt $koniec) {
    $p = @(Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($wzor, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and $_.CommandLine -notmatch 'lore\.server' })
    if ($p.Count -eq 0) { return $true }
    Start-Sleep -Seconds 2
  }
  return $false
}

# ---------------------------------------------------------------- kopia repo, atrapy, dom

function Podmien([string]$wzgl, [string]$stary, [string]$nowy, [int]$ile) {
  $p = Join-Path $Repo $wzgl
  $tx = [System.IO.File]::ReadAllText($p)
  $jest = ([regex]::Matches($tx, [regex]::Escape($stary))).Count
  if ($jest -ne $ile) { throw "podmiana w kopii ${wzgl}: '$stary' wystepuje $jest razy, a mialo $ile - plik sie zmienil, proba nie jest bezpieczna" }
  $b = [System.IO.File]::ReadAllBytes($p)
  $bom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
  [System.IO.File]::WriteAllText($p, $tx.Replace($stary, $nowy), (New-Object System.Text.UTF8Encoding($bom)))
}

function Przygotuj-Kopie {
  New-Item -ItemType Directory -Force -Path $T, $Bin, $Tmp, $Projekt | Out-Null
  Git-Cicho @('clone', '--quiet', '--no-hardlinks', $RepoPrawdziwe, $Repo)
  # niezapisane zmiany tego repo (proba ma isc na tym, co lezy na dysku) - bez .megaruchacz\ (mapa, raporty)
  $zmiany = @(& git -C $RepoPrawdziwe status --porcelain --untracked-files=all 2>$null)
  $ile = 0
  foreach ($l in $zmiany) {
    $sc = $l.Substring(3).Trim('"')
    if ($sc.StartsWith('.megaruchacz/')) { continue }
    if ($sc -match ' -> ') { $sc = ($sc -split ' -> ')[1] }
    $skad = Join-Path $RepoPrawdziwe ($sc -replace '/', '\')
    $dokad = Join-Path $Repo ($sc -replace '/', '\')
    if (Test-Path -LiteralPath $skad -PathType Leaf) {
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dokad) | Out-Null
      Copy-Item -LiteralPath $skad -Destination $dokad -Force
      $ile++
    } elseif (-not (Test-Path -LiteralPath $skad)) {
      Remove-Item -LiteralPath $dokad -Force -ErrorAction SilentlyContinue
    }
  }
  Info "kopia repo: HEAD + $ile niezapisanych plikow"
  # nazwy zadan w CALEJ kopii (*.ps1) - z MRTEST- na poczatku (ten sam wzorzec co test-moduly.ps1)
  $wzor = '(?<![\w-])(MegaRuchaczNadzorca|LoreIndex|LoreKoszt|MegaRuchaczKopia|MegaRuchaczOdswiez|LoreCyklPonow|LoreCykl|LoreFacts|LoreWiedza)(?!\w)'
  $trafione = @{}
  foreach ($f in @(Get-ChildItem -LiteralPath $Repo -Recurse -File -Filter '*.ps1' | Where-Object { $_.FullName -notlike '*\.git\*' })) {
    $b = [System.IO.File]::ReadAllBytes($f.FullName)
    $bom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
    $tx = [System.IO.File]::ReadAllText($f.FullName)
    $n = [regex]::Matches($tx, $wzor).Count
    if ($n -eq 0) { continue }
    $trafione[$f.FullName.Substring($Repo.Length + 1)] = $n
    [System.IO.File]::WriteAllText($f.FullName, [regex]::Replace($tx, $wzor, 'MRTEST-$1'), (New-Object System.Text.UTF8Encoding($bom)))
  }
  foreach ($musi in @('narzedzia\instalacja\lore-czesci.ps1', 'narzedzia\instalacja\wspolne.ps1', 'zasobnik\zainstaluj-zasobnik.ps1', 'narzedzia\koszt-pamieci.ps1', 'narzedzia\kopia-zapasowa.ps1')) {
    if (-not $trafione.ContainsKey($musi)) { throw "w kopii $musi nie znalazlem nazwy zadania do przemianowania - proba nie jest bezpieczna" }
  }
  # data startu 2099: zadanie z kopii nigdy samo nie ruszy (chodziloby na prawdziwym domu)
  Podmien 'narzedzia\instalacja\lore-czesci.ps1' '$start = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")' '$start = "2099-01-01T00:00:00"' 1
  Podmien 'narzedzia\koszt\pomiar-dzienny.ps1' '$start = (Get-Date -Format "yyyy-MM-dd") + "T"' '$start = "2099-01-01" + "T"' 1
  Podmien 'narzedzia\kopia-zapasowa.ps1' '$start = (Get-Date -Format "yyyy-MM-dd") + "T"' '$start = "2099-01-01" + "T"' 1
  # nadzorca z kopii nie startuje (okno!), a zamykanie widzi tylko procesy z katalogu MRTEST
  Podmien 'zasobnik\zainstaluj-zasobnik.ps1' "Start-ScheduledTask -TaskName `$NazwaZadania -ErrorAction Stop" 'throw "MRTEST: start nadzorcy zablokowany w tescie"' 1
  Podmien 'zasobnik\zainstaluj-zasobnik.ps1' "'nadzorca\.ps1'" "'MRTEST.*nadzorca\.ps1'" 2
  # cykl wiedzy i kolejka faktow: zaslepki zostawiajace slad (jak narzedzia\test-rejestru.ps1) - straznik
  # uruchomiony w probie nie moze wolac modelu ani wydac tokenow
  [System.IO.File]::WriteAllText((Join-Path $Repo 'narzedzia\wyciagnij-fakty.ps1'), "param([string]`$Zrodlo, [string]`$KatalogDomowy, [switch]`$Kolejka)`r`nWrite-Output ""kolejka.kawalki: 3""`r`nWrite-Output ""kolejka.przebiegi: 1""`r`nexit 0`r`n", $Utf8)
  [System.IO.File]::WriteAllText((Join-Path $Repo 'narzedzia\cykl-dzienny.ps1'), ("param([string]`$Zrodlo, [string]`$KatalogDomowy, [switch]`$Proba)`r`n" +
    "`$w = Join-Path `$KatalogDomowy "".claude\wiedza""`r`n" +
    "if (Test-Path -LiteralPath `$w) { [IO.File]::WriteAllText((Join-Path `$w "".cykl-ruszyl-test""), (Get-Date -Format o)) }`r`n"), $Utf8)
  # zamrozony "origin": straznik (Odswiez-Zrodlo) robi fetch + merge --ff-only - z prawdziwego repo
  # przewinalby kopie na nowsze commity bez MRTEST
  Git-Cicho @('clone', '--quiet', '--bare', $Repo, (Join-Path $T 'origin.git'))
  Git-Cicho @('-C', $Repo, 'remote', 'set-url', 'origin', (Join-Path $T 'origin.git'))
  Git-Cicho @('-C', $Repo, 'fetch', '--quiet', 'origin')
  Git-Cicho @('-C', $Repo, 'branch', '--quiet', '--set-upstream-to=origin/main', 'main')

  # atrapy narzedzi AI: zapisuja wywolania i pamietaja wpisy MCP w katalogu domowym procesu (z test-moduly.ps1)
  [System.IO.File]::WriteAllText((Join-Path $Bin 'atrapa.ps1'), @'
$narz = $args[0]; $r = @($args | Select-Object -Skip 1)
$plik = Join-Path $env:USERPROFILE ".atrapa-$narz.json"
Add-Content -LiteralPath (Join-Path $env:USERPROFILE ".atrapa-$narz.log") -Value ($r -join " ")
$s = [ordered]@{}
if (Test-Path $plik) { foreach ($p in (Get-Content $plik -Raw | ConvertFrom-Json).PSObject.Properties) { $s[$p.Name] = $p.Value } }
function Zapisz { $s | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $plik -Encoding UTF8 }
if ($r[0] -eq "mcp") {
  switch ($r[1]) {
    "--help" { "Usage: $narz mcp [add|get|remove|list]"; exit 0 }
    "get"    { if ($s.Contains($r[2])) { "$($r[2]): $($s[$r[2]])"; exit 0 } else { "No MCP server found with name: $($r[2])"; exit 1 } }
    "add"    {
      $i = [array]::IndexOf($r, "--")
      $przed = @($r[2..($i - 1)] | Where-Object { $_ -notlike "-*" -and $_ -notin @("user", "local", "project") })
      $s[$przed[-1]] = (@($r[($i + 1)..($r.Count - 1)]) -join " ")
      Zapisz; "Added stdio MCP server $($przed[-1])"; exit 0
    }
    "remove" { if ($s.Contains($r[2])) { $s.Remove($r[2]); Zapisz; "Removed $($r[2])"; exit 0 } else { "No MCP server named $($r[2])"; exit 1 } }
  }
}
exit 0
'@, $Utf8)
  foreach ($n in @('claude', 'codex', 'opencode')) {
    [System.IO.File]::WriteAllText((Join-Path $Bin "$n.cmd"), "@echo off`r`npowershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"%~dp0atrapa.ps1`" $n %*`r`nexit /b %ERRORLEVEL%`r`n", (New-Object System.Text.ASCIIEncoding))
  }
  # node bez katalogu C:\dev\tools\node (lezy tam prawdziwy claude) - twarde dowiazanie samego node.exe
  $node = (Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($node) { New-Item -ItemType HardLink -Path (Join-Path $Bin 'node.exe') -Target $node.Source | Out-Null }
}

# Dom jak u uzytkownika z Claude Code, Codeksem i opencode: wlasne notatki, cudzy hook, wlasna konfiguracja
# (wszystko to ma przejsc przez instalacje, zmiany i usuwanie nietkniete), jedna rozmowa do indeksu.
$NotatkaClaude = 'Moja notatka: odpowiadaj krotko (to zostaje).'
$NotatkaCodex = 'Codex - moja notatka (to zostaje).'
function Przygotuj-Dom {
  foreach ($k in @('.claude\projects\C--projekt-testowy', '.codex', '.config\opencode', 'AppData\Local', 'AppData\Roaming')) { New-Item -ItemType Directory -Force -Path (Join-Path $Dom $k) | Out-Null }
  [System.IO.File]::WriteAllText((Join-Path $Dom '.claude\CLAUDE.md'), "# Moje ustalenia`r`n`r`n$NotatkaClaude`r`n", $Utf8)
  [System.IO.File]::WriteAllText((Join-Path $Dom '.claude\settings.json'), "{`n  ""theme"": ""dark"",`n  ""hooks"": {`n    ""PreToolUse"": [`n      {`n        ""matcher"": ""*"",`n        ""hooks"": [`n          {`n            ""type"": ""command"",`n            ""command"": ""node C:/Users/test/.orca/hook-cudzy.js""`n          }`n        ]`n      }`n    ]`n  }`n}`n", $Utf8)
  [System.IO.File]::WriteAllText((Join-Path $Dom '.claude.json'), '{"oauthAccount":{"emailAddress":"test@example.invalid"},"projects":{}}', $Utf8)
  [System.IO.File]::WriteAllText((Join-Path $Dom '.claude\.credentials.json'), '{}', $Utf8)
  [System.IO.File]::WriteAllText((Join-Path $Dom '.codex\AGENTS.md'), "# Codex`r`n`r`n$NotatkaCodex`r`n", $Utf8)
  [System.IO.File]::WriteAllText((Join-Path $Dom '.codex\config.toml'), "model = ""gpt-test""`n", $Utf8)
  [System.IO.File]::WriteAllText((Join-Path $Dom '.codex\auth.json'), '{}', $Utf8)
  [System.IO.File]::WriteAllText((Join-Path $Dom '.config\opencode\opencode.json'), '{"$schema":"https://opencode.ai/config.json","theme":"moj-motyw"}', $Utf8)
  $p = Join-Path $Dom '.claude\projects\C--projekt-testowy\sesja-1.jsonl'
  $ts = '2026-09-30T10:00:00.000Z'
  $l1 = @{ type = 'user'; sessionId = 'sesja-1'; timestamp = $ts; message = @{ role = 'user'; content = 'Jak ustawilismy indeks bez modelu? Proba calosci instalatora.' } } | ConvertTo-Json -Compress -Depth 5
  $l2 = @{ type = 'assistant'; sessionId = 'sesja-1'; timestamp = $ts; message = @{ role = 'assistant'; content = @(@{ type = 'text'; text = ('Odpowiedz testowa. ' * 120) }) } } | ConvertTo-Json -Compress -Depth 6
  [System.IO.File]::WriteAllText($p, "$l1`n$l2`n", $Utf8)
  (Get-Item $p).LastWriteTime = (Get-Date).AddDays(-3)
}

function Zasiej-Model {
  if (-not $script:ModelKopia) { return }
  $cel = Join-Path $Dom '.lore\lore_models\sdadas--mmlw-retrieval-roberta-base'
  & robocopy.exe $script:ModelKopia $cel /E /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy modelu do $cel nie wyszedl (kod $LASTEXITCODE)" }
}

# ---------------------------------------------------------------- srodowisko procesow testu

$UvPrawdziwy = (Get-Command uv -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
$GitPrawdziwy = (Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
$KatUv = Split-Path -Parent $UvPrawdziwy
$KatGit = Split-Path -Parent $GitPrawdziwy
$KatBash = @('C:\dev\tools\git\bin', (Join-Path (Split-Path -Parent (Split-Path -Parent $KatGit)) 'bin')) | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'bash.exe') } | Select-Object -First 1
$Systemowe = "$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\WindowsPowerShell\v1.0;$env:SystemRoot\System32\Wbem"

function Srodowisko {
  $s = @{
    USERPROFILE = $Dom; HOME = $Dom; HOMEDRIVE = $Dom.Substring(0, 2); HOMEPATH = $Dom.Substring(2)
    LOCALAPPDATA = (Join-Path $Dom 'AppData\Local'); APPDATA = (Join-Path $Dom 'AppData\Roaming')
    TEMP = $Tmp; TMP = $Tmp
    UV_CACHE_DIR = $script:UvCache; UV_PYTHON_INSTALL_DIR = $script:UvPython
    PATH = (@($Bin, $KatUv, $KatGit, $KatBash, $Systemowe) | Where-Object { $_ }) -join ';'
  }
  return $s
}
# Zmienne, ktore nie maja prawa przejsc z sesji uruchamiajacej test (prawdziwa konfiguracja, Orka, proxy).
$ZmienneZakazane = '^(LORE_|CLAUDE|CODEX_|ANTHROPIC_|OPENAI_|ORCA_|HF_|UV_PYTHON_PREFERENCE$|UV_OFFLINE$|VIRTUAL_ENV$|PYTHONPATH$)'

function Nowe-Psi([string]$plik, [string[]]$argumenty) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $q = { param($a) if ($a -eq '') { '""' } elseif ($a -notmatch '[\s"]') { $a } else { '"' + ($a -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' } }
  $psi.Arguments = (@('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $plik) + $argumenty | ForEach-Object { & $q "$_" }) -join ' '
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.WorkingDirectory = $T   # nic wzglednego nie moze wyladowac w katalogu, z ktorego odpalono test (repo)
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $Utf8
  $psi.StandardErrorEncoding = $Utf8
  foreach ($k in @($psi.EnvironmentVariables.Keys)) { if ($k -match $ZmienneZakazane) { $psi.EnvironmentVariables.Remove($k) } }
  $s = Srodowisko
  foreach ($k in $s.Keys) { $psi.EnvironmentVariables[$k] = $s[$k] }
  return $psi
}

function Uruchom-Proces($psi, [int]$sekundy) {
  $p = [System.Diagnostics.Process]::Start($psi)
  $wy = $p.StandardOutput.ReadToEndAsync(); $bl = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($sekundy * 1000)) { & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null; return [pscustomobject]@{ Kod = 'LIMIT'; Tekst = "NIE SKONCZYL W $sekundy s" } }
  # Bez WaitForExit() bez limitu: proces potomny w tle (indeks, liczenie kosztu) moze trzymac odziedziczony
  # koniec rury i wtedy koniec wyjscia nie przychodzi - czekamy chwile, potem bierzemy, co jest.
  [void]$wy.Wait(15000); [void]$bl.Wait(5000)
  $tw = if ($wy.IsCompleted) { $wy.Result } else { '(wyjscie niedoczytane - rure trzyma proces potomny)' }
  $tb = if ($bl.IsCompleted) { $bl.Result } else { '' }
  return [pscustomobject]@{ Kod = $p.ExitCode; Tekst = ($tw + $(if ($tb.Trim()) { "`nSTDERR: " + $tb } else { '' })) }
}

# ---------------------------------------------------------------- okno ze scenariuszem

# Poczatek kazdego scenariusza (wczytywany kropka w okno.ps1 po zbudowaniu okna) - jak w test-instalatora.ps1.
$Wstep = @'
$script:TestRaport = '__RAPORT__'
$script:TestZrzuty = '__ZRZUTY__'
$script:TestPrzedrostek = '__PRZEDROSTEK__'
$script:TestIndeks = 0
$script:TestCzekamOd = $null
$script:TestSkonczony = $false
function Test-Pisz([string]$t) { [System.IO.File]::AppendAllText($script:TestRaport, ($t + "`r`n"), (New-Object System.Text.UTF8Encoding($false))) }
function Test-Zrzut([string]$nazwa) {
  [System.Windows.Forms.Application]::DoEvents()
  $script:Okno.Refresh()
  $b = $script:Okno.Bounds
  $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
  try {
    $script:Okno.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $b.Width, $b.Height)))
    $p = Join-Path $script:TestZrzuty ($script:TestPrzedrostek + '-' + $nazwa + '.png')
    $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
    Test-Pisz "ZRZUT $p"
  } finally { $bmp.Dispose() }
  if ($script:Tresc.VerticalScroll.Visible -and -not $script:Nakladka.Visible) {
    $script:Tresc.AutoScrollPosition = New-Object System.Drawing.Point(0, 100000)
    $script:Tresc.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
    try {
      $script:Okno.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $b.Width, $b.Height)))
      $p = Join-Path $script:TestZrzuty ($script:TestPrzedrostek + '-' + $nazwa + '-dol.png')
      $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
      Test-Pisz "ZRZUT $p"
    } finally { $bmp.Dispose() }
    $script:Tresc.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
  }
}
function Test-Koniec {
  if ($script:TestSkonczony) { return }
  $script:TestSkonczony = $true
  $script:TestZegar.Stop()
  Test-Pisz ("WYWROTKI: " + (@($script:Wywrotki) -join ' || '))
  Test-Pisz 'KONIEC'
  $script:ZamykamMimoPlanu = $true
  if ($script:Okno -and -not $script:Okno.IsDisposed) { $script:Okno.Close() }
}
function Tak([bool]$w, [string]$opis) { if ($w) { return "TAK $opis" } return "NIE $opis" }
# Stan krokow planu do raportu - przy bledzie razem ze szczegolami (wyjscie skryptu).
function Test-Kroki {
  foreach ($z in @($script:Plan)) {
    Test-Pisz ("KROK $($z.Id) = $($z.Stan) | $(($z.Komunikat -replace '\s+', ' ').Trim())")
    foreach ($u in $z.Uwagi) { Test-Pisz ("UWAGA-KROKU $($z.Id) | $u") }
    if ($z.Stan -eq 'blad') { foreach ($l in @((Szczegoly-Zadania $z) -split "`r`n")) { Test-Pisz "  | $l" } }
  }
}
# Kontrolka szukana po napisie w drzewie okna (przyciski kart i pytan nie maja zmiennych).
function Test-Kontrolka($c, [string]$napis) {
  foreach ($d in $c.Controls) {
    if ($d.Visible -and ($d.Text -eq $napis)) { return $d }
    $x = Test-Kontrolka $d $napis
    if ($x) { return $x }
  }
  return $null
}
Test-Pisz "TRYB $($script:Tryb)"
$script:TestZegar = New-Object System.Windows.Forms.Timer
$script:TestZegar.Interval = 250
$script:TestWTrakcie = $false
$script:TestZegar.Add_Tick({
  if ($script:TestSkonczony -or $script:TestWTrakcie) { return }
  $script:TestWTrakcie = $true
  $k = $null
  try {
    if ($script:TestIndeks -ge $script:TestKroki.Count) { Test-Koniec; return }
    $k = $script:TestKroki[$script:TestIndeks]
    if (-not $script:TestCzekamOd) { $script:TestCzekamOd = Get-Date }
    if ($k.Czekaj -and -not (& $k.Czekaj)) {
      $lim = 90; if ($k.Limit) { $lim = $k.Limit }
      if (((Get-Date) - $script:TestCzekamOd).TotalSeconds -gt $lim) { Test-Pisz "TIMEOUT $($k.N)"; Test-Zrzut ("BLAD-TESTU-" + $script:TestIndeks); Test-Kroki; Test-Koniec }
      return
    }
    if ($k.Zrob) { & $k.Zrob; [System.Windows.Forms.Application]::DoEvents() }
    if ($k.Zrzut) { Test-Zrzut $k.Zrzut }
    if ($k.Sprawdz) { Test-Pisz ("SPRAWDZ $($k.N): " + (& $k.Sprawdz)) }
    Test-Pisz "OK $($k.N)"
    $script:TestIndeks++
    $script:TestCzekamOd = $null
  } catch {
    $n = ''; if ($k) { $n = $k.N }
    Test-Pisz "WYJATEK $($n): $($_.Exception.Message) @ linia $($_.InvocationInfo.ScriptLineNumber)"
    Test-Kroki
    Test-Koniec
  } finally { $script:TestWTrakcie = $false }
})
$script:TestZegar.Start()
'@

# Wspolne kroki konca planu: czekamy na ekran Gotowe (albo blad), zrzut i stan krokow.
$KoniecPlanu = @'
  @{ N = 'koniec planu'; Czekaj = { ($script:Ekran -eq 'gotowe') -or (@('blad', 'przerwany') -contains $script:PlanStan) }; Limit = 2700; Zrzut = '__ETAP__-koniec'; Sprawdz = { Test-Kroki; Tak ($script:Ekran -eq 'gotowe') "plan: $($script:PlanStan), ekran: $($script:Ekran)" } }
'@

function Okno([string]$etap, [string]$kroki, [int]$limit = 3000) {
  $raport = Join-Path $T "raport-$etap.txt"
  $plik = Join-Path $T "scenariusz-$etap.ps1"
  $tresc = $Wstep.Replace('__RAPORT__', $raport).Replace('__ZRZUTY__', $Zrzuty).Replace('__PRZEDROSTEK__', $Przedrostek) + "`r`n" + $kroki.Replace('__KONIEC__', $KoniecPlanu).Replace('__ETAP__', $etap).Replace('__KOPIE__', $Kopie).Replace('__DOM__', $Dom)
  [System.IO.File]::WriteAllText($plik, $tresc.Replace("`r`n", "`n").Replace("`n", "`r`n"), $Utf8Bom)
  Pisz-Log "=== okno $etap"
  $start = Get-Date
  $r = Uruchom-Proces (Nowe-Psi (Join-Path $Repo 'instalator\okno.ps1') @('-PozaEkranem', '-KatalogDomowy', $Dom, '-Scenariusz', $plik)) $limit
  $sek = [int]((Get-Date) - $start).TotalSeconds
  if (-not (Test-Path -LiteralPath $raport)) { Sprawdz "${etap}: okno zostawilo raport" $false "kod $($r.Kod): $($r.Tekst)"; return @() }
  $tx = @(Get-Content -LiteralPath $raport -Encoding UTF8)
  foreach ($l in $tx) { Pisz-Log "  [okno $etap] $l" }
  $zle = @($tx | Where-Object { $_ -match '^(TIMEOUT|WYJATEK)' })
  $wyw = @($tx | Where-Object { ($_ -like 'WYWROTKI:*') -and ($_.Trim() -ne 'WYWROTKI:') })
  $koniec = @($tx | Where-Object { $_ -eq 'KONIEC' }).Count -gt 0
  Sprawdz "${etap}: przebieg okna ($sek s, kod $($r.Kod))" ($koniec -and $zle.Count -eq 0 -and $wyw.Count -eq 0 -and ($r.Kod -eq 0)) (($zle + $wyw) -join ' | ')
  foreach ($s in @($tx | Where-Object { $_ -match '^SPRAWDZ ' })) {
    Sprawdz "${etap}: $(($s -replace '^SPRAWDZ ', '') -replace ': (TAK|NIE) .*$', '')" ($s -match ': TAK ') ($s -replace '^.*?: (TAK|NIE) ', '')
  }
  $bledy = @($tx | Where-Object { $_ -match '^KROK \S+ = blad' })
  foreach ($b in $bledy) { Sprawdz "${etap}: krok planu bez bledu" $false (($tx | Where-Object { $_ -like '  |*' }) -join ' / ') }
  foreach ($u in @($tx | Where-Object { $_ -like 'UWAGA-KROKU*' })) { Info "${etap}: $($u.Substring(12))" }
  return $tx
}

# ---------------------------------------------------------------- odczyt domu probnego

$KL = '<!-- MegaRuchacz:lore:start -->'; $KW = '<!-- MegaRuchacz:wiedza:start -->'; $KK = '<!-- MegaRuchacz:kierownik:start -->'
$KStary = '<!-- MegaRuchacz:start -->'; $KOpencode = '<!-- MegaRuchacz:kopia-dla-opencode'

function Rejestr { $tx = Czytaj (Join-Path $Dom '.claude\mr\instalacja.json'); if (-not $tx) { return $null }; return ($tx | ConvertFrom-Json) }

function Hooki {
  $s = (Czytaj (Join-Path $Dom '.claude\settings.json')) | ConvertFrom-Json
  $w = [ordered]@{ straznik = 0; przypomnienie = 0; rejestr = 0; cudzy = 0; zlyStraznik = 0; theme = "$($s.theme)" }
  foreach ($z in @($s.hooks.PSObject.Properties | ForEach-Object { $_.Name })) {
    foreach ($g in @($s.hooks.$z)) {
      foreach ($h in @($g.hooks)) {
        $c = "$($h.command)"
        if ($c -like '*hook-cudzy.js*') { $w.cudzy++ }
        elseif ($c -like '*straznik-zasad.ps1*') { $w.straznik++; if ($c -notlike "*$($Repo.Replace('\', '/'))/narzedzia/straznik-zasad.ps1*") { $w.zlyStraznik++ } }
        elseif ($c -like '*przypomnienie.js*') { $w.przypomnienie++ }
        elseif ($c -match 'mr-log\.js') { $w.rejestr++ }
      }
    }
  }
  return [pscustomobject]$w
}

function Nasze-Role([string]$kat, [string]$filtr) {
  return @(Get-ChildItem -Path (Join-Path (Join-Path $Dom $kat) $filtr) -File -ErrorAction SilentlyContinue | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -match 'kierownik-template' }).Count
}

function Co-Wiem([string]$tekst) {
  if ($null -eq $tekst) { return $null }
  $m = [regex]::Match($tekst, '(?ms)^## Co wiem.*?(?=^## |^<!-- MegaRuchacz:|\z)')
  if ($m.Success) { return $m.Value }
  return $null
}

function Stub-Mcp([string]$narz) {
  $p = Join-Path $Dom ".atrapa-$narz.json"
  if (-not (Test-Path $p)) { return $null }
  return ((Get-Content $p -Raw | ConvertFrom-Json).lore)
}

function Zadanie([string]$n) { return (Get-ScheduledTask -TaskName "MRTEST-$n" -ErrorAction SilentlyContinue) }
function Akcja-Zadania([string]$n) { $z = Zadanie $n; if (-not $z) { return '' }; return (@($z.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join ' ') }

function Baza-Lore {
  $py = Join-Path $T 'baza.py'
  if (-not (Test-Path $py)) {
    [System.IO.File]::WriteAllText($py, @'
import json, sqlite3, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.exists():
    print(json.dumps({"jest": False})); sys.exit(0)
c = sqlite3.connect("file:" + p.as_posix() + "?mode=ro", uri=True)
t = {r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")}
one = lambda s, *a: (c.execute(s, a).fetchone() or [None])[0]
print(json.dumps({"jest": True, "tryb": one("SELECT value FROM meta WHERE key=?", "index_mode") if "meta" in t else None,
                  "fragmenty": one("SELECT count(*) FROM chunks") if "chunks" in t else 0,
                  "wektory": one("SELECT count(*) FROM vectors") if "vectors" in t else 0}))
'@, $Utf8)
  }
  $python = Join-Path $RepoPrawdziwe 'lore\.venv\Scripts\python.exe'
  $wy = & $python $py (Join-Path $Dom '.lore\lore.db') 2>&1
  try { return (($wy | Select-Object -Last 1) | ConvertFrom-Json) } catch { return [pscustomobject]@{ jest = $null; blad = "$wy" } }
}

# Pliki, ktore straznik moglby zmienic - do porownania przed/po jego przebiegu.
function Odcisk-Plikow-Domu {
  $o = [ordered]@{}
  foreach ($p in @('.claude\CLAUDE.md', '.claude\settings.json', '.codex\AGENTS.md', '.codex\hooks.json', '.codex\config.toml', '.config\opencode\AGENTS.md',
                   '.config\opencode\opencode.json', '.claude\mr\instalacja.json', '.claude\megaruchacz-mr-log.js', '.claude\mr\orchestrator-reminder.json', '.claude\.megaruchacz-global')) {
    $o[$p] = Skrot (Join-Path $Dom $p)
  }
  foreach ($kat in @('.claude\agents', '.codex\agents', '.config\opencode\agents', '.config\opencode\plugins')) {
    $o[$kat] = (@(Get-ChildItem -LiteralPath (Join-Path $Dom $kat) -File -Force -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { "$($_.Name)=$((Get-FileHash -LiteralPath $_.FullName).Hash)" }) -join ';')
  }
  return $o
}

# Straznik tak, jak wola go hook SessionStart (z projektu testowego). Nic nie ma prawa sie zmienic ani
# zdublowac; cykl wiedzy (zaslepka) rusza tylko przy wlaczonej Wiedzy.
function Straznik-Jak-Hook([string]$etap, [bool]$wiedzaWl) {
  $katW = Join-Path $Dom '.claude\wiedza'
  foreach ($f in @('.cykl-stan', '.cykl-ruszyl-test', '.cykl-postep')) { Remove-Item -LiteralPath (Join-Path $katW $f) -Force -ErrorAction SilentlyContinue }
  $przed = Odcisk-Plikow-Domu
  $r = Uruchom-Proces (Nowe-Psi (Join-Path $Repo 'narzedzia\straznik-zasad.ps1') @('-Zrodlo', $Repo, '-Projekt', $Projekt, '-KatalogDomowy', $Dom)) 240
  Pisz-Log "  [straznik $etap] kod $($r.Kod): $($r.Tekst)"
  $po = Odcisk-Plikow-Domu
  $rozne = @($przed.Keys | Where-Object { $przed[$_] -ne $po[$_] })
  Sprawdz "${etap}: straznik jak hook SessionStart niczego nie zmienil w plikach domu (kod $($r.Kod))" (($rozne.Count -eq 0) -and ($r.Kod -eq 0)) ("zmienione: " + ($rozne -join ', ') + " | wyjscie: " + $r.Tekst)
  $ruszyl = $false
  if ($wiedzaWl) {
    $do = (Get-Date).AddSeconds(30)
    while (((Get-Date) -lt $do) -and -not (Test-Path -LiteralPath (Join-Path $katW '.cykl-ruszyl-test'))) { Start-Sleep -Milliseconds 500 }
  } else { Start-Sleep -Seconds 4 }
  $ruszyl = Test-Path -LiteralPath (Join-Path $katW '.cykl-ruszyl-test')
  Sprawdz "${etap}: cykl wiedzy (zaslepka) ruszyl ze straznika tylko przy Wiedzy (Wiedza: $wiedzaWl)" ($ruszyl -eq $wiedzaWl) "ruszyl: $ruszyl; wyjscie straznika: $($r.Tekst)"
  return $r
}

# Pelny przeglad domu wobec oczekiwanych modulow. $o: wiedza lore kierownik skille kopia (bool), baza (bool),
# dane (bool - czy dane uzytkownika maja byc na dysku), coWiem (tekst sekcji do porownania co do bajtu albo $null).
function Przeglad([string]$etap, [hashtable]$o) {
  $rej = Rejestr
  $mod = @('wiedza', 'lore', 'kierownik', 'skille', 'kopia')
  if ($null -eq $rej) { Sprawdz "${etap}: rejestr istnieje" $false 'brak pliku' }
  else {
    $zgodne = @($mod | Where-Object { [bool]$rej.moduly.$_ -ne [bool]$o[$_] })
    Sprawdz "${etap}: rejestr - moduly zgodne z wyborem" ($zgodne.Count -eq 0) ("rozne: " + ($zgodne -join ', ') + " | " + ($rej.moduly | ConvertTo-Json -Compress))
    $baza = -not ($rej.PSObject.Properties.Name -contains 'baza') -or ($rej.baza -ne $false)
    Sprawdz "${etap}: rejestr - baza = $($o.baza)" ($baza -eq $o.baza) ($rej | ConvertTo-Json -Compress -Depth 5)
  }
  $cm = Czytaj (Join-Path $Dom '.claude\CLAUDE.md')
  $cx = Czytaj (Join-Path $Dom '.codex\AGENTS.md')
  $oc = Czytaj (Join-Path $Dom '.config\opencode\AGENTS.md')
  $wl = [int][bool]$o.lore; $ww = [int][bool]$o.wiedza; $wk = [int][bool]$o.kierownik
  Sprawdz "${etap}: CLAUDE.md - bloki lore $wl, wiedza $ww, kierownik $wk, bez starego bloku" (((Ile $cm $KL) -eq $wl) -and ((Ile $cm $KW) -eq $ww) -and ((Ile $cm $KK) -eq $wk) -and ((Ile $cm $KStary) -eq 0)) "lore $(Ile $cm $KL), wiedza $(Ile $cm $KW), kierownik $(Ile $cm $KK), stary $(Ile $cm $KStary)"
  Sprawdz "${etap}: CLAUDE.md - Twoja notatka nietknieta, bez bajtow 0x00" (($cm -and $cm.Contains($NotatkaClaude)) -and ([Array]::IndexOf([System.IO.File]::ReadAllBytes((Join-Path $Dom '.claude\CLAUDE.md')), [byte]0) -lt 0))
  if ($cm) {
    $iCw = $cm.IndexOf('## Co wiem'); $iL = $cm.IndexOf($KL); $iW = $cm.IndexOf($KW); $iK = $cm.IndexOf($KK)
    $kolej = @(@($iCw, $iL, $iW, $iK) | Where-Object { $_ -ge 0 })
    $posort = @($kolej | Sort-Object)
    Sprawdz "${etap}: CLAUDE.md - kolejnosc Co wiem > lore > wiedza > kierownik" (($kolej -join ',') -eq ($posort -join ',')) "pozycje: Co wiem $iCw, lore $iL, wiedza $iW, kierownik $iK"
  }
  $cw = Co-Wiem $cm
  Sprawdz "${etap}: sekcja '## Co wiem' $(if ($o.dane) { 'jest' } else { 'zniknela' }) (jedna)" ($(if ($o.dane) { $cw -and ((Ile $cm '## Co wiem') -eq 1) } else { -not $cw })) "Co wiem: $(Ile $cm '## Co wiem')"
  # Co do znaku poza pustymi liniami na koncu sekcji (zdjecie bloku pod nia moze zabrac jedna pusta linie).
  if ($o.coWiem -and $cw) { Sprawdz "${etap}: '## Co wiem' co do znaku jak po instalacji" ($cw.TrimEnd() -ceq $o.coWiem.TrimEnd()) "przed: [$($o.coWiem)] po: [$cw]" }
  Sprawdz "${etap}: AGENTS.md Codeksa - bloki lore $wl, wiedza $ww, kierownik $wk; notatka nietknieta" (((Ile $cx $KL) -eq $wl) -and ((Ile $cx $KW) -eq $ww) -and ((Ile $cx $KK) -eq $wk) -and $cx -and $cx.Contains($NotatkaCodex)) "lore $(Ile $cx $KL), wiedza $(Ile $cx $KW), kierownik $(Ile $cx $KK)"
  # Od 0.28 OpenCode ma samodzielny plik jak Codex (do 0.27: kopia CLAUDE.md z naglowkiem $KOpencode).
  $ocBezNaglowka = (-not $oc) -or (-not $oc.StartsWith($KOpencode))
  Sprawdz "${etap}: AGENTS.md OpenCode - bloki lore $wl, wiedza $ww, kierownik $wk; bez naglowka starej kopii" (((Ile $oc $KL) -eq $wl) -and ((Ile $oc $KW) -eq $ww) -and ((Ile $oc $KK) -eq $wk) -and $ocBezNaglowka) "lore $(Ile $oc $KL), wiedza $(Ile $oc $KW), kierownik $(Ile $oc $KK), pierwsza linia: $(if ($oc) { ($oc -split "`n")[0] } else { '(brak pliku)' })"
  $h = Hooki
  $oczS = [int][bool]$o.baza; $oczP = [int]([bool]($o.kierownik -or $o.wiedza -or $o.lore) -and $o.baza); $oczR = [int]([bool]$o.kierownik -and $o.baza)
  Sprawdz "${etap}: hooki - straznik $oczS, przypomnienie $oczP, rejestr pracy $(2 * $oczR) (po jednym), cudzy i ustawienia nietkniete" (($h.straznik -eq $oczS) -and ($h.zlyStraznik -eq 0) -and ($h.przypomnienie -eq $oczP) -and ($h.rejestr -eq 2 * $oczR) -and ($h.cudzy -eq 1) -and ($h.theme -eq 'dark')) ($h | ConvertTo-Json -Compress)
  $rc = Nasze-Role '.claude\agents' '*.md'; $rx = Nasze-Role '.codex\agents' '*.toml'; $ro = Nasze-Role '.config\opencode\agents' '*.md'
  Sprawdz "${etap}: role agentow $(if ($o.kierownik) { 'Claude 5, Codex 4, opencode 4' } else { 'zadnej' })" ($(if ($o.kierownik) { ($rc -eq 5) -and ($rx -eq 4) -and ($ro -eq 4) } else { ($rc + $rx + $ro) -eq 0 })) "Claude $rc, Codex $rx, opencode $ro"
  $plikiK = @('.claude\megaruchacz-mr-log.js', '.claude\mr\orchestrator-reminder.json', '.claude\.megaruchacz-global') | Where-Object { Test-Path -LiteralPath (Join-Path $Dom $_) }
  Sprawdz "${etap}: pliki kierownika (rejestr pracy, ladunek, znacznik) $(if ($o.kierownik) { 'sa' } else { 'zniknely' })" ($(if ($o.kierownik) { @($plikiK).Count -eq 3 } else { @($plikiK).Count -eq 0 })) ($plikiK -join ', ')
  $hx = Czytaj (Join-Path $Dom '.codex\hooks.json')
  Sprawdz "${etap}: hooki rejestru Codeksa $(if ($o.kierownik) { 'sa' } else { 'zniknely' })" ($(if ($o.kierownik) { $hx -and ($hx -match 'mr-log-codex\.js') } else { (-not $hx) -or ($hx -notmatch 'mr-log-codex\.js') }))
  $mc = Stub-Mcp 'claude'; $mx = Stub-Mcp 'codex'
  $ocj = (Czytaj (Join-Path $Dom '.config\opencode\opencode.json')) | ConvertFrom-Json
  $mo = ($ocj.mcp -and ($ocj.mcp.PSObject.Properties.Name -contains 'lore'))
  $mcpOk = if ($o.lore) { ("$mc" -match ([regex]::Escape((Join-Path $Repo 'lore')) + ' run python -m lore\.server')) -and ("$mx" -match 'lore\.server') -and $mo } else { (-not $mc) -and (-not $mx) -and (-not $mo) }
  Sprawdz "${etap}: serwer MCP lore $(if ($o.lore) { 'w Claude Code, Codeksie i opencode' } else { 'nigdzie' }); konfiguracja opencode i Codeksa nietknieta" ($mcpOk -and ($ocj.theme -eq 'moj-motyw') -and ((Czytaj (Join-Path $Dom '.codex\config.toml')) -match 'model = "gpt-test"')) "claude: $mc | codex: $mx | opencode: $mo"
  # zadania (MRTEST-)
  $zn = [bool](Zadanie 'MegaRuchaczNadzorca'); $zk = [bool](Zadanie 'LoreKoszt'); $zi = Akcja-Zadania 'LoreIndex'; $zc = [bool](Zadanie 'MegaRuchaczKopia')
  $oczI = if ($o.lore) { 'wektory' } elseif ($o.wiedza) { 'tekst' } else { 'brak' }
  $jestI = if (-not $zi) { 'brak' } elseif ($zi -match 'lore\.index --text-only') { 'tekst' } elseif ($zi -match 'lore\.index') { 'wektory' } else { "obce: $zi" }
  Sprawdz "${etap}: zadania - nadzorca i raport kosztu $($o.baza), indeks rozmow: $oczI, kopia $($o.kopia)" (($zn -eq $o.baza) -and ($zk -eq $o.baza) -and ($jestI -eq $oczI) -and ($zc -eq [bool]$o.kopia)) "nadzorca $zn, koszt $zk, indeks $jestI, kopia $zc"
  $venv = Test-Path -LiteralPath (Join-Path $Repo 'lore\.venv')
  $model = Test-Path -LiteralPath (Join-Path $Dom '.lore\lore_models')
  Sprawdz "${etap}: srodowisko Pythona $(if ($o.wiedza -or $o.lore) { 'jest' } else { 'zniknelo' }), model wektorow $(if ($o.lore) { 'jest' } else { 'nie ma' })" (($venv -eq [bool]($o.wiedza -or $o.lore)) -and ($model -eq [bool]$o.lore)) "venv $venv, model $model"
  if ($o.wiedza -or $o.lore) {
    $b = Baza-Lore
    $tryb = if ($o.lore) { 'vectors' } else { 'text' }
    Sprawdz "${etap}: baza rozmow w trybie '$tryb'" ($b.jest -and ($b.tryb -eq $tryb)) ($b | ConvertTo-Json -Compress)
  }
  # dane uzytkownika
  $dane = [ordered]@{
    'wiedza\' = (Test-Path -LiteralPath (Join-Path $Dom '.claude\wiedza'))
    'kopie dzienne' = (Test-Path -LiteralPath (Join-Path $Dom '.claude\mr\kopie-dzienne'))
    'lore.db' = (Test-Path -LiteralPath (Join-Path $Dom '.lore\lore.db'))
    'stan kopii' = (Test-Path -LiteralPath (Join-Path $Dom '.claude\mr\kopia-stan.txt'))
    'stan skilli' = (Test-Path -LiteralPath (Join-Path $Dom '.claude\mr\skille'))
  }
  if ($o.dane) {
    $brak = @($dane.Keys | Where-Object { -not $dane[$_] -and ($o.bezDanych -notcontains $_) })
    Sprawdz "${etap}: dane uzytkownika na dysku" ($brak.Count -eq 0) ("brakuje: " + ($brak -join ', '))
  } else {
    $sa = @($dane.Keys | Where-Object { $dane[$_] })
    Sprawdz "${etap}: dane uzytkownika usuniete" ($sa.Count -eq 0) ("zostaly: " + ($sa -join ', '))
  }
  Sprawdz "${etap}: folder kopii zapasowych nietkniety (kopie nie sa nigdy usuwane)" ((Test-Path -LiteralPath (Join-Path $Kopie 'kopia-proby.txt')) -or -not $script:KopieZasiane)
  return [pscustomobject]@{ CoWiem = $cw }
}

# ---------------------------------------------------------------- scenariusze okna

$ScenariuszNowa = @'
$script:TestKroki = @(
  @{ N = 'powitanie'; Czekaj = { $script:Ekran -eq 'powitanie' }; Zrzut = '__ETAP__-powitanie'; Sprawdz = { $n = @($script:Narzedzia | Where-Object { $_.Jest } | ForEach-Object { $_.Id }) -join ','; Tak (($script:Tryb -eq 'nowy') -and ($n -eq 'claude,codex,opencode')) "tryb $($script:Tryb), narzedzia: $n" } },
  @{ N = 'dalej'; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'wybor'; Czekaj = { $script:Ekran -eq 'wybor' } },
  @{ N = 'Wszystko'; Zrob = { $script:BWszystko.PerformClick() }; Sprawdz = { $m = $script:Wybor.Moduly; Tak ($m.wiedza -and $m.lore -and $m.kierownik -and $m.skille -and $m.kopia) 'wszystkie piec zaznaczone' } },
  @{ N = 'kopia: folder i zrodla tylko z domu'; Zrob = {
      $script:PoleCelu.Text = '__KOPIE__'
      foreach ($p in @($script:ListaZrodel.Controls)) { $cb = $p.Controls[0]; if ($cb.Tag.Sciezka -notlike '__DOM__*') { $cb.Checked = $false } else { $cb.Checked = $true } } };
    Sprawdz = { $z = @($script:Wybor.KopiaZrodla | Where-Object { $_.Zaznaczone } | ForEach-Object { $_.Sciezka }); Tak ($script:BDalej.Enabled -and ($z.Count -ge 1) -and (@($z | Where-Object { $_ -notlike '__DOM__*' }).Count -eq 0)) "zrodla: $($z -join '; ')" } },
  @{ N = 'do podsumowania'; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'podsumowanie'; Czekaj = { ($script:Ekran -eq 'podsumowanie') -and $script:Sprawdzenie -and ($script:Sprawdzenie.Zadanie.Stan -ne 'trwa') }; Limit = 180; Zrzut = '__ETAP__-podsumowanie'; Sprawdz = { $ids = @($script:PlanDoWykonania | ForEach-Object { $_.Id }) -join ','; Tak (($ids -eq 'zapamietaj,zaleznosci-Instaluj,baza-Instaluj,lore-Instaluj,wiedza-Instaluj,kierownik-Instaluj,skille-Instaluj,kopia-Instaluj,zasady') -and $script:BDalej.Enabled) "plan: $ids; programy: $($script:LProgramy.Text)" } },
  @{ N = 'zainstaluj'; Zrob = { $script:BDalej.PerformClick() } },
  __KONIEC__
)
'@

$ScenariuszBezLore = @'
$script:TestKroki = @(
  @{ N = 'wybor z obecnym stanem'; Czekaj = { $script:Ekran -eq 'wybor' }; Sprawdz = { $m = $script:Wybor.Moduly; Tak (($script:Tryb -eq 'zmiana') -and $script:BazaJest -and $m.wiedza -and $m.lore -and $m.kierownik -and $m.skille -and $m.kopia -and (-not $script:BDalej.Enabled)) "tryb $($script:Tryb), baza $($script:BazaJest)" } },
  @{ N = 'odznacz Pamiec rozmow'; Zrob = { $script:CheckboxyModulow.lore.Checked = $false } },
  @{ N = 'pytanie - zostaw dane'; Czekaj = { $script:Nakladka.Visible }; Zrzut = '__ETAP__-pytanie'; Zrob = { $script:PrzyciskiPytania[0].PerformClick() }; Sprawdz = { Tak ((-not $script:Wybor.Moduly.lore) -and (-not $script:Wybor.UsunDane.lore) -and $script:BDalej.Enabled) "znaczek: $($script:TagiModulow.lore.Text)" } },
  @{ N = 'zastosuj'; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'podsumowanie'; Czekaj = { $script:Ekran -eq 'podsumowanie' }; Zrzut = '__ETAP__-podsumowanie'; Sprawdz = { $ids = @($script:PlanDoWykonania | ForEach-Object { $_.Id }) -join ','; Tak ($ids -eq 'zapamietaj,lore-Usun,zasady') "plan: $ids" } },
  @{ N = 'tak, zastosuj'; Zrob = { $script:BDalej.PerformClick() } },
  __KONIEC__
)
'@

$ScenariuszZLore = @'
$script:TestKroki = @(
  @{ N = 'wybor bez Lore'; Czekaj = { $script:Ekran -eq 'wybor' }; Sprawdz = { Tak (($script:Tryb -eq 'zmiana') -and (-not $script:Wybor.Moduly.lore) -and $script:Wybor.Moduly.wiedza) "lore $($script:Wybor.Moduly.lore)" } },
  @{ N = 'zaznacz Pamiec rozmow'; Zrob = { $script:CheckboxyModulow.lore.Checked = $true }; Sprawdz = { Tak (($script:TagiModulow.lore.Text -eq 'dodam') -and $script:BDalej.Enabled) "znaczek: $($script:TagiModulow.lore.Text)" } },
  @{ N = 'zastosuj'; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'podsumowanie'; Czekaj = { ($script:Ekran -eq 'podsumowanie') -and $script:Sprawdzenie -and ($script:Sprawdzenie.Zadanie.Stan -ne 'trwa') }; Limit = 180; Sprawdz = { $ids = @($script:PlanDoWykonania | ForEach-Object { $_.Id }) -join ','; Tak ($ids -eq 'zapamietaj,zaleznosci-Instaluj,lore-Instaluj,zasady') "plan: $ids" } },
  @{ N = 'tak, zastosuj'; Zrob = { $script:BDalej.PerformClick() } },
  __KONIEC__
)
'@

$ScenariuszBezKierownika = @'
$script:TestKroki = @(
  @{ N = 'wybor'; Czekaj = { $script:Ekran -eq 'wybor' } },
  @{ N = 'odznacz Tryb kierownika'; Zrob = { $script:CheckboxyModulow.kierownik.Checked = $false } },
  @{ N = 'pytanie bez pola danych'; Czekaj = { $script:Nakladka.Visible }; Sprawdz = { Tak ($null -eq $script:PolePytania) 'kierownik nie trzyma danych - pytanie bez pola' }; Zrob = { $script:PrzyciskiPytania[0].PerformClick() } },
  @{ N = 'zastosuj'; Czekaj = { $script:BDalej.Enabled }; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'podsumowanie'; Czekaj = { $script:Ekran -eq 'podsumowanie' }; Sprawdz = { $ids = @($script:PlanDoWykonania | ForEach-Object { $_.Id }) -join ','; Tak ($ids -eq 'zapamietaj,kierownik-Usun,zasady') "plan: $ids" } },
  @{ N = 'tak, zastosuj'; Zrob = { $script:BDalej.PerformClick() } },
  __KONIEC__
)
'@

# Usuniecie calego MegaRuchacza: przycisk "Usun MegaRuchacza..." w trybie zmiany. __DANE__ = $true/$false.
$ScenariuszUsunWszystko = @'
$script:TestKroki = @(
  @{ N = 'wybor'; Czekaj = { $script:Ekran -eq 'wybor' }; Zrzut = '__ETAP__-wybor' },
  @{ N = 'przycisk Usun MegaRuchacza'; Zrob = { (Test-Kontrolka $script:Tresc 'Usuń MegaRuchacza…').PerformClick() } },
  @{ N = 'pytanie o usuniecie calosci'; Czekaj = { $script:Nakladka.Visible }; Zrzut = '__ETAP__-pytanie'; Sprawdz = { Tak ($script:PolePytania -and (-not $script:PolePytania.Checked)) 'pole "usun tez moje dane" domyslnie odznaczone' } },
  @{ N = 'odpowiedz na pytanie'; Zrob = { $script:PolePytania.Checked = __DANE__; $script:PrzyciskiPytania[0].PerformClick() } },
  @{ N = 'wybor po pytaniu'; Czekaj = { -not $script:Nakladka.Visible }; Zrzut = '__ETAP__-wybor-po'; Sprawdz = { $m = $script:Wybor.Moduly; Tak ($script:Wybor.UsunWszystko -and ($script:Wybor.UsunDaneWszystko -eq __DANE__) -and (-not ($m.wiedza -or $m.lore -or $m.kierownik -or $m.skille -or $m.kopia)) -and ($script:ZnaczekZawsze.Text -like 'usun*') -and $script:BDalej.Enabled) "znaczek bazy: $($script:ZnaczekZawsze.Text)" } },
  @{ N = 'zastosuj'; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'podsumowanie'; Czekaj = { $script:Ekran -eq 'podsumowanie' }; Zrzut = '__ETAP__-podsumowanie'; Sprawdz = { $ids = @($script:PlanDoWykonania | ForEach-Object { $_.Id }) -join ','; Tak ($ids -eq 'zapamietaj,kopia-Usun,skille-Usun,kierownik-Usun,wiedza-Usun,lore-Usun,baza-Usun') "plan: $ids; usun dane: $(@($script:PlanDoWykonania | Where-Object { $_.PSObject.Properties['UsunDane'] -and $_.UsunDane }).Count)" } },
  @{ N = 'tak, usun'; Zrob = { $script:BDalej.PerformClick() } },
  __KONIEC__
)
'@

$ScenariuszPonownie = @'
$script:TestKroki = @(
  @{ N = 'wybor po odinstalowaniu'; Czekaj = { $script:Ekran -eq 'wybor' }; Zrzut = '__ETAP__-wybor'; Sprawdz = { $m = $script:Wybor.Moduly; Tak (($script:Tryb -eq 'zmiana') -and (-not $script:BazaJest) -and (-not ($m.wiedza -or $m.lore -or $m.kierownik -or $m.skille -or $m.kopia)) -and ($script:ZnaczekZawsze.Text -eq '')) "tryb $($script:Tryb), baza $($script:BazaJest), znaczek bazy '$($script:ZnaczekZawsze.Text)'" } },
  @{ N = 'Wszystko'; Zrob = { $script:BWszystko.PerformClick() }; Sprawdz = { Tak (($script:ZnaczekZawsze.Text -eq 'dodam') -and $script:Wybor.Moduly.kopia) "znaczek bazy: $($script:ZnaczekZawsze.Text)" } },
  @{ N = 'kopia: ten sam folder'; Zrob = { $script:PoleCelu.Text = '__KOPIE__'; foreach ($p in @($script:ListaZrodel.Controls)) { $cb = $p.Controls[0]; if ($cb.Tag.Sciezka -notlike '__DOM__*') { $cb.Checked = $false } } } },
  @{ N = 'zastosuj'; Czekaj = { $script:BDalej.Enabled }; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'podsumowanie'; Czekaj = { ($script:Ekran -eq 'podsumowanie') -and $script:Sprawdzenie -and ($script:Sprawdzenie.Zadanie.Stan -ne 'trwa') }; Limit = 180; Zrzut = '__ETAP__-podsumowanie'; Sprawdz = { $ids = @($script:PlanDoWykonania | ForEach-Object { $_.Id }) -join ','; Tak ($ids -eq 'zapamietaj,zaleznosci-Instaluj,baza-Instaluj,lore-Instaluj,wiedza-Instaluj,kierownik-Instaluj,skille-Instaluj,kopia-Instaluj,zasady') "plan: $ids" } },
  @{ N = 'tak, zastosuj'; Zrob = { $script:BDalej.PerformClick() } },
  __KONIEC__
)
'@

# ---------------------------------------------------------------- przebieg

$odciskPrzed = $null
$script:KopieZasiane = $false
try {
  Zdejmij-Zadania-Testu   # resztki po przerwanym przebiegu
  New-Item -ItemType Directory -Force -Path $T | Out-Null
  $script:BylyWRepo = @(@('Microsoft', 'AppData') | Where-Object { Test-Path -LiteralPath (Join-Path $RepoPrawdziwe $_) })
  $odciskPrzed = Odcisk-Prawdziwy
  Write-Host "Katalog proby: $T"
  Przygotuj-Kopie
  Przygotuj-Dom
  $script:UvCache = (& $UvPrawdziwy cache dir 2>$null | Select-Object -Last 1)
  $script:UvPython = (& $UvPrawdziwy python dir 2>$null | Select-Object -Last 1)
  $modelP = Join-Path $HOME '.claude\lore_models\sdadas--mmlw-retrieval-roberta-base'
  $script:ModelKopia = $null
  if (Test-Path (Join-Path $modelP 'onnx\model.onnx')) {
    $script:ModelKopia = Join-Path $T 'model\sdadas--mmlw-retrieval-roberta-base'
    & robocopy.exe $modelP $script:ModelKopia /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "nie skopiowalem modelu do katalogu proby (robocopy $LASTEXITCODE)" }
  } else { throw "nie ma prawdziwego modelu $modelP - proba nie pobiera 496 MB" }
  Zasiej-Model
  Sprawdz 'przygotowanie: kopia repo (zadania MRTEST-, data 2099, start nadzorcy zablokowany, zamrozony origin), atrapy, dom' $true

  # --- a. nowa instalacja "Wszystko"
  [void](Okno 'a-nowa' $ScenariuszNowa)
  [void](Czekaj-Na-Tlo)
  $a = Przeglad 'a-nowa' @{ wiedza = $true; lore = $true; kierownik = $true; skille = $true; kopia = $true; baza = $true; dane = $true; bezDanych = @('stan kopii') }
  $CoWiem = $a.CoWiem
  $rej = Rejestr
  Sprawdz 'a-nowa: rejestr - ustawienia kopii (folder tymczasowy, zrodla z domu) i narzedzia' (($rej.kopia.cel -eq $Kopie) -and (@($rej.kopia.zrodla) -contains (Join-Path $Dom '.claude')) -and $rej.narzedzia.claude -and $rej.narzedzia.codex -and $rej.narzedzia.opencode) ($rej | ConvertTo-Json -Compress -Depth 5)
  # kopia "jakby przeszla": stan kopii w domu i plik w folderze kopii - do sprawdzenia, ze usuwanie kopii nie rusza
  [System.IO.File]::WriteAllText((Join-Path $Dom '.claude\mr\kopia-stan.txt'), "stan=OK`r`nostatnia=2026-10-02 12:30:00`r`ncel=$Kopie\pelna-2026-10-02`r`n", $Utf8)
  [System.IO.File]::WriteAllText((Join-Path $Dom '.claude\mr\kopia-indeks.tsv'), "x`t1`r`n", $Utf8)
  New-Item -ItemType Directory -Force -Path $Kopie | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $Kopie 'kopia-proby.txt'), 'kopia zapasowa - nie usuwac', $Utf8)
  $script:KopieZasiane = $true
  [void](Straznik-Jak-Hook 'a-nowa' $true)

  if (-not (Chce 'b')) { throw 'STOP-DOKROKU' }
  # --- b. bez Lore, potem Lore z powrotem
  [void](Okno 'b1-bez-lore' $ScenariuszBezLore)
  [void](Czekaj-Na-Tlo)
  [void](Przeglad 'b1-bez-lore' @{ wiedza = $true; lore = $false; kierownik = $true; skille = $true; kopia = $true; baza = $true; dane = $true; coWiem = $CoWiem })
  [void](Straznik-Jak-Hook 'b1-bez-lore' $true)
  Zasiej-Model   # Lore Usun zdjal model; ponowne pobranie 496 MB zastepuje kopia
  [void](Okno 'b2-z-lore' $ScenariuszZLore)
  [void](Czekaj-Na-Tlo)
  [void](Przeglad 'b2-z-lore' @{ wiedza = $true; lore = $true; kierownik = $true; skille = $true; kopia = $true; baza = $true; dane = $true; coWiem = $CoWiem })
  [void](Straznik-Jak-Hook 'b2-z-lore' $true)

  if (-not (Chce 'c')) { throw 'STOP-DOKROKU' }
  # --- c. bez kierownika
  [void](Okno 'c-bez-kierownika' $ScenariuszBezKierownika)
  [void](Przeglad 'c-bez-kierownika' @{ wiedza = $true; lore = $true; kierownik = $false; skille = $true; kopia = $true; baza = $true; dane = $true; coWiem = $CoWiem })
  [void](Straznik-Jak-Hook 'c-bez-kierownika' $true)

  if (-not (Chce 'd')) { throw 'STOP-DOKROKU' }
  # --- d. usuniecie calosci bez danych, ponowna instalacja, usuniecie z danymi
  $tx = @(Okno 'd1-usun-bez-danych' $ScenariuszUsunWszystko.Replace('__DANE__', '$false'))
  Sprawdz 'd1-usun-bez-danych: bez falszywej uwagi "nikt nie pilnuje cyklu wiedzy" (wiedza juz wylaczona)' (@($tx | Where-Object { $_ -match 'nikt nie pilnuje' }).Count -eq 0) (($tx | Where-Object { $_ -like 'UWAGA-KROKU*' }) -join ' | ')
  [void](Czekaj-Na-Tlo)
  [void](Przeglad 'd1-usun-bez-danych' @{ wiedza = $false; lore = $false; kierownik = $false; skille = $false; kopia = $false; baza = $false; dane = $true; coWiem = $CoWiem })
  [void](Straznik-Jak-Hook 'd1-usun-bez-danych' $false)
  Zasiej-Model   # Lore Usun w d1 zdjal model
  [void](Okno 'd2-ponownie' $ScenariuszPonownie)
  [void](Czekaj-Na-Tlo)
  [void](Przeglad 'd2-ponownie' @{ wiedza = $true; lore = $true; kierownik = $true; skille = $true; kopia = $true; baza = $true; dane = $true; coWiem = $CoWiem })
  [void](Straznik-Jak-Hook 'd2-ponownie' $true)
  $tx = @(Okno 'd3-usun-z-danymi' $ScenariuszUsunWszystko.Replace('__DANE__', '$true'))
  Sprawdz 'd3-usun-z-danymi: bez falszywej uwagi "nikt nie pilnuje cyklu wiedzy"' (@($tx | Where-Object { $_ -match 'nikt nie pilnuje' }).Count -eq 0) (($tx | Where-Object { $_ -like 'UWAGA-KROKU*' }) -join ' | ')
  [void](Czekaj-Na-Tlo)
  [void](Przeglad 'd3-usun-z-danymi' @{ wiedza = $false; lore = $false; kierownik = $false; skille = $false; kopia = $false; baza = $false; dane = $false })
  [void](Straznik-Jak-Hook 'd3-usun-z-danymi' $false)
  $sl = Rejestr
  Sprawdz 'd3-usun-z-danymi: zostaje tylko slad w rejestrze (baza = false), bez ustawien kopii' (($null -ne $sl) -and ($sl.baza -eq $false) -and ($null -eq $sl.kopia)) ($sl | ConvertTo-Json -Compress -Depth 5)
} catch {
  if ($_.Exception.Message -eq 'STOP-DOKROKU') { Info "proba zatrzymana po kroku $DoKroku (-DoKroku)" }
  else { Sprawdz 'przebieg proby' $false ($_.Exception.Message + ' ' + $_.InvocationInfo.PositionMessage) }
} finally {
  Zdejmij-Zadania-Testu
  foreach ($p in @(Procesy-Testu)) { try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop } catch { Write-Host "BLAD  nie zatrzymalem procesu proby $($p.ProcessId)" } }
  Start-Sleep -Seconds 1
  Sprawdz 'po probie: zadnego zadania MRTEST-' (@(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'MRTEST-*' }).Count -eq 0)
  Sprawdz 'po probie: zaden proces z kopii nie zostal' (@(Procesy-Testu).Count -eq 0)
  if ($odciskPrzed) {
    $po = Odcisk-Prawdziwy
    foreach ($k in $odciskPrzed.Keys) { Sprawdz "prawdziwy stan bez zmian: $k" ($odciskPrzed[$k] -eq $po[$k]) "przed: $($odciskPrzed[$k]) / po: $($po[$k])" }
  }
  $wskazuja = @(Prawdziwe-Wskazuja-Test)
  Sprawdz 'zadna prawdziwa konfiguracja nie wskazuje katalogu proby' ($wskazuja.Count -eq 0) ($wskazuja -join ', ')
  $wyciek = @(@('Microsoft', 'AppData') | Where-Object { (Test-Path -LiteralPath (Join-Path $RepoPrawdziwe $_)) -and ($script:BylyWRepo -notcontains $_) })
  Sprawdz 'w katalogu repo nie przybylo Microsoft\ ani AppData\' ($wyciek.Count -eq 0) ($wyciek -join ', ')
  $kopiaLogu = Join-Path ([System.IO.Path]::GetTempPath()) "test-calosci-$Stempel.log"
  if (Test-Path -LiteralPath $script:Log) { Copy-Item -LiteralPath $script:Log -Destination $kopiaLogu -Force; Write-Host "Dziennik proby: $kopiaLogu" }
  foreach ($kat in @($Tmp, $(if (-not $Zostaw) { $T }))) {
    if (-not $kat -or -not (Test-Path -LiteralPath $kat)) { continue }
    try { Remove-Item -LiteralPath $kat -Recurse -Force -ErrorAction Stop } catch { & cmd.exe /d /c "rd /s /q `"\\?\$kat`"" 2>&1 | Out-Null }
    if (Test-Path -LiteralPath $kat) { Write-Host "UWAGA katalog proby nie dal sie usunac w calosci: $kat" }
  }
  Write-Host ''
  Write-Host ("Wynik: {0} sprawdzen, {1} nie przeszlo." -f $script:Wynik.Count, $script:Zle)
  foreach ($i in $script:Info) { Write-Host "INFO  $i" }
}
if ($script:Zle -gt 0) { exit 1 }
exit 0
