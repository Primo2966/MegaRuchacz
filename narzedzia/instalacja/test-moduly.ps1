# narzedzia\instalacja\test-moduly.ps1 - testy skryptow modulow (modul-*.ps1), zaleznosci.ps1
# i starego narzedzia\instaluj-lore.ps1 - WYLACZNIE na kopiach.
#
# Co jest kopia, a co prawdziwe:
#   - repo: git clone tego repo (HEAD) + nalozone niezapisane w gicie pliki tego, co sie testuje
#     (narzedzia\instalacja\, narzedzia\instaluj-lore.ps1, lore\), w katalogu z "MRTEST" w nazwie;
#     cudze niezapisane zmiany (inni workerzy) do kopii nie trafiaja
#   - katalog domowy: osobny, pusty na kazdy scenariusz. Procesy potomne maja USERPROFILE,
#     LOCALAPPDATA, APPDATA i TEMP w katalogu testu; uv dostaje prawdziwa pamiec podreczna
#     (UV_CACHE_DIR, UV_PYTHON_INSTALL_DIR), wiec srodowisko Pythona stawia sie bez sieci
#   - Harmonogram jest jeden na maszyne, dlatego w KOPII repo: nazwy zadan z przedrostkiem MRTEST-,
#     data startu 2099 (zadanie nigdy samo nie ruszy - inaczej chodziloby na prawdziwym katalogu
#     domowym), start nadzorcy zablokowany, a zamykanie nadzorcy widzi tylko procesy z kopii
#   - claude i codex to atrapy w PATH (zapisuja wywolania, pamietaja wpisy MCP); prawdziwych
#     narzedzi w PATH testu nie ma
#   - model wektorow: kopia prawdziwego katalogu modelu (bez pobierania 496 MB)
# Przed i po: odcisk prawdziwych zadan MegaRuchacza, PATH uzytkownika, rejestru modulow, trybu
# prawdziwej bazy Lore i procesu nadzorcy - musza sie zgadzac, a zadna prawdziwa konfiguracja nie
# moze wskazywac katalogu testu. Na koniec znikaja wszystkie zadania MRTEST-* i procesy z kopii.
#
# Uzycie:
#   powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File narzedzia\instalacja\test-moduly.ps1
#     [-Katalog <kat>]        gdzie zalozyc katalog testu (domyslnie %TEMP%); nazwa i tak dostaje MRTEST
#     [-Tylko baza,wiedza]    tylko wybrane scenariusze: zaleznosci baza wiedza lore wiedzalore
#                             kierownik skille kopia rejestr proba stary usunczysty
#     [-BezSieci]             bez prawdziwego pobierania programow (zaleznosci: tylko proby)
#     [-Zostaw]               nie kasuj katalogu testu (zadania MRTEST-* znikaja zawsze)
# Kod wyjscia: 0 = wszystko przeszlo, 1 = cos nie.

param(
  [string]$Katalog = $env:TEMP,
  [string[]]$Tylko = @(),
  [switch]$BezSieci,
  [switch]$Zostaw
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$RepoPrawdziwe = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$T = Join-Path $Katalog ("MRTEST-" + (Get-Date -Format "MMdd-HHmmss"))   # krotko: .venv ma sciezki blisko 260 znakow
$Repo = Join-Path $T "repo"
$Bin = Join-Path $T "bin"
# TEMP procesow potomnych: krotka sciezka. Pod glebokim katalogiem testu pytest (testy Lore w starym
# wywolaniu instaluj-lore) zakladal tmp_path dluzszy niz 260 znakow i 3 testy padaly na samej sciezce.
$TmpKrotki = Join-Path ([System.IO.Path]::GetTempPath()) ("MRTEST-tmp-" + (Get-Date -Format "MMdd-HHmmss"))
$Wynik = @()
$script:Zle = 0
$script:Info = @()
$Scenariusze = @("zaleznosci", "baza", "wiedza", "lore", "wiedzalore", "kierownik", "skille", "kopia", "rejestr", "proba", "stary", "usunczysty")
$wybrane = @($Tylko | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ })
if ($wybrane.Count -eq 0) { $wybrane = $Scenariusze }

function Sprawdz([string]$co, [bool]$ok, [string]$szczegol = "") {
  $linia = $(if ($ok) { "OK    " } else { "BLAD  " }) + $co
  if (-not $ok -and $szczegol) {
    $s = ($szczegol -replace "\s+", " ")
    if ($s.Length -gt 2400) { $s = $s.Substring(0, 400) + " [...] " + $s.Substring($s.Length - 2000) }   # koniec wydruku mowi najwiecej
    $linia += " -- " + $s
  }
  $script:Wynik += $linia
  Write-Host $linia
  if (-not $ok) { $script:Zle++ }
}
function Info([string]$t) { $script:Info += $t; Write-Host "INFO  $t" }

function Q([string]$a) {
  if ($a -eq "") { return '""' }
  if ($a -notmatch '[\s"]') { return $a }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"'); $u = 0
  foreach ($c in $a.ToCharArray()) {
    if ($c -eq '\') { $u++; continue }
    if ($c -eq '"') { [void]$sb.Append(('\' * ($u * 2 + 1)) + '"'); $u = 0; continue }
    if ($u) { [void]$sb.Append('\' * $u); $u = 0 }
    [void]$sb.Append($c)
  }
  if ($u) { [void]$sb.Append('\' * ($u * 2)) }
  [void]$sb.Append('"'); return $sb.ToString()
}

# ---------------------------------------------------------------- odcisk prawdziwego stanu

$PythonPrawdziwy = Join-Path $RepoPrawdziwe "lore\.venv\Scripts\python.exe"
$ZadaniaPrawdziwe = @("MegaRuchaczNadzorca", "LoreIndex", "LoreKoszt", "MegaRuchaczKopia", "MegaRuchaczOdswiez", "LoreCykl", "LoreCyklPonow", "LoreFacts", "LoreWiedza")

function Py-Baza([string]$baza) {
  # tryb indeksu, liczba fragmentow i wektorow - tylko odczyt
  $py = Join-Path $T "baza.py"
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
'@, (New-Object System.Text.UTF8Encoding($false)))
  }
  $wy = & $PythonPrawdziwy $py $baza 2>&1
  return (($wy | Select-Object -Last 1) | ConvertFrom-Json)
}

function Odcisk-Prawdziwy {
  $o = [ordered]@{}
  foreach ($n in $ZadaniaPrawdziwe) {
    $z = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
    $o["zadanie.$n"] = if ($z) { (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes((Export-ScheduledTask -TaskName $n))))).Hash } else { "-" }
  }
  $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment")
  $o["path.uzytkownika"] = [string]$k.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  $k.Close()
  $rej = Join-Path $HOME ".claude\mr\instalacja.json"
  $o["rejestr"] = if (Test-Path $rej) { (Get-FileHash $rej).Hash } else { "-" }
  $bazaP = Join-Path $HOME ".claude\lore.db"
  $o["baza.tryb"] = if (Test-Path $bazaP) { "" + (Py-Baza $bazaP).tryb } else { "-" }
  $o["nadzorca.pid"] = (@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf((Join-Path $RepoPrawdziwe "zasobnik\nadzorca.ps1"), [StringComparison]::OrdinalIgnoreCase) -ge 0 } | ForEach-Object { $_.ProcessId } | Sort-Object) -join ",")
  return $o
}

function Prawdziwe-Wskazuja-Test {
  $zle = @()
  foreach ($p in @(".claude\settings.json", ".claude.json", ".claude\CLAUDE.md", ".codex\config.toml", ".codex\AGENTS.md", ".codex\hooks.json", ".config\opencode\opencode.json", ".claude\mr\instalacja.json")) {
    $f = Join-Path $HOME $p
    if ((Test-Path $f) -and ([System.IO.File]::ReadAllText($f).IndexOf("MRTEST", [StringComparison]::OrdinalIgnoreCase) -ge 0)) { $zle += $p }
  }
  return $zle
}

function Zdejmij-Zadania-Testu {
  foreach ($z in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "MRTEST-*" })) {
    try { Unregister-ScheduledTask -TaskName $z.TaskName -Confirm:$false -ErrorAction Stop } catch { Write-Host "BLAD  nie zdjalem zadania $($z.TaskName): $($_.Exception.Message)" }
  }
}

function Procesy-Testu {
  return @(Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($T, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
}

function Czekaj-Na-Tlo([int]$sekundy = 240) {
  $wzor = Join-Path $Repo "lore"
  $koniec = (Get-Date).AddSeconds($sekundy)
  while ((Get-Date) -lt $koniec) {
    $p = @(Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($wzor, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
    if ($p.Count -eq 0) { return $true }
    Start-Sleep -Milliseconds 700
  }
  return $false
}

# ---------------------------------------------------------------- kopia repo i atrapy

function Podmien([string]$wzgl, [string]$stary, [string]$nowy, [int]$ile) {
  $p = Join-Path $Repo $wzgl
  $t = [System.IO.File]::ReadAllText($p)
  $jest = ([regex]::Matches($t, [regex]::Escape($stary))).Count
  if ($jest -ne $ile) { throw "podmiana w kopii ${wzgl}: '$stary' wystepuje $jest razy, a mialo $ile - plik sie zmienil, test nie jest bezpieczny" }
  [System.IO.File]::WriteAllText($p, $t.Replace($stary, $nowy), (New-Object System.Text.UTF8Encoding($true)))
}

function Przygotuj-Kopie {
  New-Item -ItemType Directory -Force -Path $T, $Bin, $TmpKrotki, (Join-Path $T "localappdata"), (Join-Path $T "appdata") | Out-Null
  Git-Cicho @("clone", "--quiet", "--no-hardlinks", $RepoPrawdziwe, $Repo)
  # to, co sie testuje: niezapisane w gicie pliki z zakresu instalatora i Lore
  $zakres = @("narzedzia/instalacja/", "narzedzia/instaluj-lore.ps1", "lore/lore/", "lore/tests/")
  $zmiany = @(& git -C $RepoPrawdziwe status --porcelain --untracked-files=all 2>$null)
  foreach ($l in $zmiany) {
    $sc = $l.Substring(3).Trim('"')
    if (-not ($zakres | Where-Object { $sc.StartsWith($_) })) { continue }
    $skad = Join-Path $RepoPrawdziwe ($sc -replace '/', '\')
    $dokad = Join-Path $Repo ($sc -replace '/', '\')
    if (Test-Path -LiteralPath $skad -PathType Leaf) {
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dokad) | Out-Null
      Copy-Item -LiteralPath $skad -Destination $dokad -Force
    }
  }
  # nazwy zadan w CALEJ kopii (*.ps1) - z MRTEST- na poczatku
  $wzor = '(?<![\w-])(MegaRuchaczNadzorca|LoreIndex|LoreKoszt|MegaRuchaczKopia|MegaRuchaczOdswiez|LoreCyklPonow|LoreCykl|LoreFacts|LoreWiedza)(?!\w)'
  $trafione = @{}
  foreach ($f in @(Get-ChildItem -LiteralPath $Repo -Recurse -File -Filter "*.ps1" | Where-Object { $_.FullName -notlike "*\.git\*" })) {
    $b = [System.IO.File]::ReadAllBytes($f.FullName)
    $bom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
    $t = [System.IO.File]::ReadAllText($f.FullName)
    $n = [regex]::Matches($t, $wzor).Count
    if ($n -eq 0) { continue }
    $trafione[$f.FullName.Substring($Repo.Length + 1)] = $n
    [System.IO.File]::WriteAllText($f.FullName, [regex]::Replace($t, $wzor, 'MRTEST-$1'), (New-Object System.Text.UTF8Encoding($bom)))
  }
  foreach ($musi in @("narzedzia\instalacja\lore-czesci.ps1", "narzedzia\instalacja\wspolne.ps1", "zasobnik\zainstaluj-zasobnik.ps1", "narzedzia\koszt-pamieci.ps1", "narzedzia\kopia-zapasowa.ps1")) {
    if (-not $trafione.ContainsKey($musi)) { throw "w kopii $musi nie znalazlem nazwy zadania do przemianowania - test nie jest bezpieczny" }
  }
  # data startu 2099: zadanie z kopii nigdy samo nie ruszy (chodziloby na prawdziwym domu)
  Podmien "narzedzia\instalacja\lore-czesci.ps1" '$start = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")' '$start = "2099-01-01T00:00:00"' 1
  Podmien "narzedzia\koszt\pomiar-dzienny.ps1" '$start = (Get-Date -Format "yyyy-MM-dd") + "T"' '$start = "2099-01-01" + "T"' 1
  Podmien "narzedzia\kopia-zapasowa.ps1" '$start = (Get-Date -Format "yyyy-MM-dd") + "T"' '$start = "2099-01-01" + "T"' 1
  # nadzorca z kopii nie startuje (okno!), a zamykanie widzi tylko procesy z katalogu MRTEST
  Podmien "zasobnik\zainstaluj-zasobnik.ps1" "Start-ScheduledTask -TaskName `$NazwaZadania -ErrorAction Stop" 'throw "MRTEST: start nadzorcy zablokowany w tescie"' 1
  Podmien "zasobnik\zainstaluj-zasobnik.ps1" "'nadzorca\.ps1'" "'MRTEST.*nadzorca\.ps1'" 2

  # atrapy narzedzi AI: zapisuja wywolania i pamietaja wpisy MCP w katalogu domowym procesu
  [System.IO.File]::WriteAllText((Join-Path $Bin "atrapa.ps1"), @'
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
    "remove" {
      if ($env:ATRAPA_PSUJ_REMOVE) { "Error: cannot write config"; exit 1 }   # proba negatywna
      if ($s.Contains($r[2])) { $s.Remove($r[2]); Zapisz; "Removed $($r[2])"; exit 0 } else { "No MCP server named $($r[2])"; exit 1 }
    }
  }
}
exit 0
'@, (New-Object System.Text.UTF8Encoding($false)))
  foreach ($n in @("claude", "codex")) {
    [System.IO.File]::WriteAllText((Join-Path $Bin "$n.cmd"), "@echo off`r`npowershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"%~dp0atrapa.ps1`" $n %*`r`nexit /b %ERRORLEVEL%`r`n", (New-Object System.Text.ASCIIEncoding))
  }
  # node bez katalogu C:\dev\tools\node (lezy tam prawdziwy claude) - twarde dowiazanie samego node.exe
  $node = (Get-Command node -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
  if ($node) { New-Item -ItemType HardLink -Path (Join-Path $Bin "node.exe") -Target $node.Source | Out-Null }
}

# ---------------------------------------------------------------- uruchamianie modulow

$UvPrawdziwy = (Get-Command uv -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
$GitPrawdziwy = (Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
$KatUv = Split-Path -Parent $UvPrawdziwy
$KatGit = Split-Path -Parent $GitPrawdziwy
$Systemowe = "$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\WindowsPowerShell\v1.0;$env:SystemRoot\System32\Wbem"

function Srodowisko([string]$dom, [hashtable]$zmiany = @{}) {
  $s = @{
    USERPROFILE = $dom; HOME = $dom; HOMEDRIVE = $dom.Substring(0, 2); HOMEPATH = $dom.Substring(2)
    LOCALAPPDATA = (Join-Path $T "localappdata"); APPDATA = (Join-Path $T "appdata")
    TEMP = $TmpKrotki; TMP = $TmpKrotki
    UV_CACHE_DIR = $script:UvCache; UV_PYTHON_INSTALL_DIR = $script:UvPython
    PATH = "$Bin;$KatUv;$KatGit;$Systemowe"
    LORE_HOME = $null; CLAUDE_HISTORIA_HOME = $null; CODEX_HOME = $null; CLAUDE_CONFIG_DIR = $null
    ANTHROPIC_API_KEY = $null; ANTHROPIC_AUTH_TOKEN = $null; OPENAI_API_KEY = $null; HF_HUB_OFFLINE = $null
    UV_PYTHON_PREFERENCE = $null; VIRTUAL_ENV = $null; PYTHONPATH = $null; UV_OFFLINE = $null
  }
  foreach ($k in $zmiany.Keys) { $s[$k] = $zmiany[$k] }
  return $s
}

function Uruchom([string]$skrypt, [string[]]$argumenty, [hashtable]$srod, [int]$sekundy = 1200) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
  $psi.Arguments = (@("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", (Q $skrypt)) + @($argumenty | ForEach-Object { Q $_ })) -join " "
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.WorkingDirectory = $T   # nic wzglednego nie moze wyladowac w katalogu, z ktorego odpalono test (repo)
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
  foreach ($k in $srod.Keys) {
    if ($null -eq $srod[$k]) { if ($psi.EnvironmentVariables.ContainsKey($k)) { $psi.EnvironmentVariables.Remove($k) } }
    else { $psi.EnvironmentVariables[$k] = $srod[$k] }
  }
  $p = [System.Diagnostics.Process]::Start($psi)
  $wy = $p.StandardOutput.ReadToEndAsync(); $bl = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($sekundy * 1000)) { & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null; return [pscustomobject]@{ Kod = -1; Tekst = "NIE SKONCZYL W $sekundy s"; W = $null; Kroki = @(); Uwagi = @() } }
  $p.WaitForExit()
  $tekst = $wy.Result + $(if ($bl.Result.Trim()) { "`nSTDERR: " + $bl.Result } else { "" })
  $linie = @($tekst -split "`r?`n")
  $ost = ($linie | Where-Object { $_.Trim() -and $_ -notlike "STDERR:*" } | Select-Object -Last 1)
  $w = $null
  if ($ost -like "WYNIK: *") { try { $w = $ost.Substring(7) | ConvertFrom-Json } catch { $w = $null } }
  return [pscustomobject]@{ Kod = $p.ExitCode; Tekst = $tekst; W = $w
    Kroki = @($linie | Where-Object { $_ -like "KROK: *" } | ForEach-Object { $_.Substring(6) })
    Uwagi = @($linie | Where-Object { $_ -like "UWAGA: *" } | ForEach-Object { $_.Substring(7) }) }
}

function Modul([string]$nazwa, [string]$akcja, [string]$dom, [string[]]$dalej = @(), [hashtable]$zmiany = @{}) {
  $a = @("-Akcja", $akcja, "-KatalogDomowy", $dom, "-Zrodlo", $Repo) + @($dalej | Where-Object { $_ })   # $null z pustej tablicy bylby argumentem ""
  $r = Uruchom (Join-Path $Repo "narzedzia\instalacja\modul-$nazwa.ps1") $a (Srodowisko $dom $zmiany)
  # umowa wyjscia sprawdzana przy KAZDYM wywolaniu
  $umowa = ($null -ne $r.W) -and ($r.W.modul -eq $nazwa) -and ($r.W.akcja -eq $akcja) -and (($r.Kod -eq 0) -eq [bool]$r.W.ok) -and ($null -ne $r.W.kroki)
  if (-not $umowa) { Sprawdz "$nazwa $akcja ${dalej}: umowa wyjscia (WYNIK w ostatniej linii, ok zgodne z kodem $($r.Kod))" $false $r.Tekst }
  return $r
}

function Dom([string]$nazwa) {
  $d = Join-Path $T "dom-$nazwa"
  # AppData jak w prawdziwym domu: bez niego GetFolderPath daje pusty napis (patrz Ustaw-Katalog-Domowy)
  New-Item -ItemType Directory -Force -Path (Join-Path $d ".claude"), (Join-Path $d "AppData\Local"), (Join-Path $d "AppData\Roaming") | Out-Null
  return $d
}

function Rozmowa([string]$dom, [string]$tekst) {
  $kat = Join-Path $dom ".claude\projects\C--projekt-testowy"
  New-Item -ItemType Directory -Force -Path $kat | Out-Null
  $p = Join-Path $kat "sesja-1.jsonl"
  $ts = "2026-09-30T10:00:00.000Z"
  $l1 = @{ type = "user"; sessionId = "sesja-1"; timestamp = $ts; message = @{ role = "user"; content = $tekst } } | ConvertTo-Json -Compress -Depth 5
  $l2 = @{ type = "assistant"; sessionId = "sesja-1"; timestamp = $ts; message = @{ role = "assistant"; content = @(@{ type = "text"; text = ("Odpowiedz testowa. " * 120) }) } } | ConvertTo-Json -Compress -Depth 6
  [System.IO.File]::WriteAllText($p, "$l1`n$l2`n", (New-Object System.Text.UTF8Encoding($false)))
  (Get-Item $p).LastWriteTime = (Get-Date).AddDays(-3)   # ogon zamkniety - indeks bierze wszystko od razu
}

function Rejestr([string]$dom) {
  $p = Join-Path $dom ".claude\mr\instalacja.json"
  if (-not (Test-Path $p)) { return $null }
  return ([System.IO.File]::ReadAllText($p) | ConvertFrom-Json)
}

function Hooki([string]$dom, [string]$zdarzenie, [string]$wzor) {
  $p = Join-Path $dom ".claude\settings.json"
  if (-not (Test-Path $p)) { return 0 }
  $s = [System.IO.File]::ReadAllText($p) | ConvertFrom-Json
  if (-not $s.hooks -or -not ($s.hooks.PSObject.Properties.Name -contains $zdarzenie)) { return 0 }
  return @(@($s.hooks.$zdarzenie) | ForEach-Object { @($_.hooks) } | Where-Object { ("" + $_.command) -match $wzor }).Count
}

function Zadanie([string]$nazwa) { return (Get-ScheduledTask -TaskName "MRTEST-$nazwa" -ErrorAction SilentlyContinue) }
function Akcja-Zadania([string]$nazwa) { $z = Zadanie $nazwa; if (-not $z) { return "" }; return (@($z.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments)" }) -join " ") }

function Odcisk-Domu([string]$dom) {
  # .atrapa-* to dziennik i stan atrap claude/codex - pisza je same atrapy, nie moduly; AppData\ to
  # pamieci podreczne systemu i PowerShella (ModuleAnalysisCache) - jak w kazdym prawdziwym domu
  return (@(Get-ChildItem -LiteralPath $dom -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike ".atrapa-*" -and $_.FullName.Substring($dom.Length) -notlike "\AppData\*" } | Sort-Object FullName |
            ForEach-Object { $_.FullName.Substring($dom.Length) + "=" + (Get-FileHash -LiteralPath $_.FullName).Hash }) -join ";")
}

function Zasiej-Model([string]$dom) {
  $cel = Join-Path $dom ".lore\lore_models\sdadas--mmlw-retrieval-roberta-base"
  & robocopy.exe $script:ModelKopia $cel /E /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy modelu do $cel nie wyszedl (kod $LASTEXITCODE)" }
}

function Stub-Mcp([string]$dom, [string]$narz) {
  $p = Join-Path $dom ".atrapa-$narz.json"
  if (-not (Test-Path $p)) { return $null }
  return ((Get-Content $p -Raw | ConvertFrom-Json).lore)
}

# ---------------------------------------------------------------- scenariusze

function Scenariusz-Zaleznosci {
  $z = Join-Path $Repo "narzedzia\instalacja\zaleznosci.ps1"
  $dom = Dom "zaleznosci"
  $r = Uruchom $z @("-Akcja", "Sprawdz", "-Potrzebne", "uv,python,git,node") (Srodowisko $dom)
  Sprawdz "zaleznosci: Sprawdz widzi uv, python (przez uv), git, node" (($r.Kod -eq 0) -and $r.W.ok -and (@($r.W.brakuje).Count -eq 0) -and (@($r.W.programy).Count -eq 4)) $r.Tekst
  $r = Uruchom $z @("-Akcja", "Sprawdz", "-Potrzebne", "uv,cobol") (Srodowisko $dom)
  Sprawdz "zaleznosci: nieznany program = odmowa z lista znanych" (($r.Kod -eq 1) -and ($r.W.komunikat -match "cobol") -and ($r.W.komunikat -match "znam")) $r.Tekst
  # PATH bez katalogu atrap (tam lezy node.exe dla scenariusza kierownik) - nie kasujemy go, bo
  # kolejne scenariusze go potrzebuja (pelny przebieg padal na tym 02.10)
  $golo = Srodowisko $dom @{ PATH = $Systemowe }
  $r = Uruchom $z @("-Akcja", "Sprawdz", "-Potrzebne", "uv,git,node") $golo
  Sprawdz "zaleznosci: bez programow Sprawdz = ok:false i brakuje uv, git, node" (($r.Kod -eq 1) -and ((@($r.W.brakuje) -join ",") -eq "uv,git,node")) $r.Tekst
  $r = Uruchom $z @("-Akcja", "Instaluj", "-Potrzebne", "uv,python,git,node", "-Proba", "-KatalogProgramow", (Join-Path $T "programy-proba")) $golo
  Sprawdz "zaleznosci: -Proba pokazuje plan (winget albo zip) i niczego nie instaluje" (($r.Kod -eq 0) -and (($r.Kroki -join " ") -match "zip") -and -not (Test-Path (Join-Path $T "programy-proba"))) $r.Tekst
  # brak internetu: serwer posredniczacy, ktorego nie ma (port zamkniety) - tak samo jak brak sieci
  $przed = (Odcisk-Prawdziwy)["path.uzytkownika"]
  $r = Uruchom $z @("-Akcja", "Instaluj", "-Potrzebne", "uv", "-BezWinget", "-Proxy", "http://127.0.0.1:9", "-BezZmianyPath", "-KatalogProgramow", (Join-Path $T "programy-bez-sieci")) $golo
  Sprawdz "zaleznosci: brak internetu = ok:false z czytelnym powodem" (($r.Kod -eq 1) -and ((($r.Uwagi -join " ") + $r.W.komunikat) -match "brak internetu|nie odpowiada")) $r.Tekst
  $r = Uruchom $z @("-Akcja", "Instaluj", "-Potrzebne", "git", "-Proxy", "http://127.0.0.1:9", "-BezZmianyPath", "-KatalogProgramow", (Join-Path $T "programy-bez-sieci")) $golo
  Sprawdz "zaleznosci: brak winget i brak internetu = winget pominiety z powodem, potem odmowa" (($r.Kod -eq 1) -and (($r.Kroki -join " ") -match "winget") -and ((($r.Uwagi -join " ") + $r.W.komunikat) -match "brak internetu|nie odpowiada")) $r.Tekst
  if ($BezSieci) { Info "zaleznosci: prawdziwe pobranie wersji przenosnych pominiete (-BezSieci)"; return }
  $prog = Join-Path $T "programy"
  $r = Uruchom $z @("-Akcja", "Instaluj", "-Potrzebne", "uv,git,node", "-BezWinget", "-BezZmianyPath", "-KatalogProgramow", $prog) $golo 1800
  $uvOk = Test-Path (Join-Path $prog "uv\uv.exe"); $gitOk = Test-Path (Join-Path $prog "git\cmd\git.exe"); $nodeOk = Test-Path (Join-Path $prog "node\node.exe")
  Sprawdz "zaleznosci: instalacja przenosna uv + MinGit + Node do katalogu testu (zip, suma SHA-256)" (($r.Kod -eq 0) -and $uvOk -and $gitOk -and $nodeOk -and (($r.Kroki -join " ") -match "SHA-256")) $r.Tekst
  if ($gitOk) {
    $wy = & (Join-Path $prog "git\cmd\git.exe") --version 2>&1
    Sprawdz "zaleznosci: przenosny git dziala" ($LASTEXITCODE -eq 0) "$wy"
  }
  $r2 = Uruchom $z @("-Akcja", "Instaluj", "-Potrzebne", "python", "-BezWinget", "-BezZmianyPath", "-KatalogProgramow", $prog) (Srodowisko $dom @{ PATH = $Systemowe; UV_PYTHON_INSTALL_DIR = (Join-Path $T "python-test"); UV_PYTHON_PREFERENCE = "only-managed" }) 1800
  Sprawdz "zaleznosci: Python 3.12 przez uv do katalogu testu" (($r2.Kod -eq 0) -and (@(Get-ChildItem (Join-Path $T "python-test") -Directory -Filter "cpython-3.12*" -ErrorAction SilentlyContinue).Count -gt 0)) $r2.Tekst
  $r3 = Uruchom $z @("-Akcja", "Instaluj", "-Potrzebne", "uv,git,node", "-BezWinget", "-BezZmianyPath", "-KatalogProgramow", $prog) $golo
  Sprawdz "zaleznosci: drugi raz Instaluj = 'wszystko jest', nic nie pobiera" (($r3.Kod -eq 0) -and ($r3.W.komunikat -match "wszystko jest")) $r3.Tekst
  Sprawdz "zaleznosci: PATH uzytkownika nietkniety (-BezZmianyPath)" ((Odcisk-Prawdziwy)["path.uzytkownika"] -eq $przed)
}

function Scenariusz-Baza {
  $dom = Dom "baza"
  $r = Modul "baza" "Stan" $dom
  Sprawdz "baza: Stan na pustym domu = nie zainstalowana" (($r.Kod -eq 0) -and ($r.W.zainstalowany -eq $false)) $r.Tekst
  $r = Modul "baza" "Instaluj" $dom @("-BezStartu")
  $rej = Rejestr $dom
  Sprawdz "baza: Instaluj ok" ($r.Kod -eq 0) $r.Tekst
  Sprawdz "baza: swiezy dom dostaje rejestr ze wszystkimi modulami wylaczonymi" (($null -ne $rej) -and -not ($rej.moduly.wiedza -or $rej.moduly.lore -or $rej.moduly.kierownik -or $rej.moduly.skille -or $rej.moduly.kopia)) ($rej | ConvertTo-Json -Compress)
  Sprawdz "baza: hook straznika na SessionStart (jeden, wskazuje kopie)" ((Hooki $dom "SessionStart" ([regex]::Escape($Repo.Replace('\', '/')) + '/narzedzia/straznik-zasad\.ps1')) -eq 1)
  Sprawdz "baza: zadanie nadzorcy (MRTEST-) uruchamia nadzorca.ps1 z kopii" ((Akcja-Zadania "MegaRuchaczNadzorca").IndexOf((Join-Path $Repo "zasobnik\nadzorca.ps1"), [StringComparison]::OrdinalIgnoreCase) -ge 0) (Akcja-Zadania "MegaRuchaczNadzorca")
  Sprawdz "baza: zadanie raportu kosztu (MRTEST-LoreKoszt) z domem testu" ((Akcja-Zadania "LoreKoszt") -match [regex]::Escape($dom)) (Akcja-Zadania "LoreKoszt")
  Sprawdz "baza: klon git z galezia sledzaca rozpoznany" ((($r.Kroki -join " ") -match "klon git, galaz sledzi")) ($r.Kroki -join " | ")
  $r = Modul "baza" "Stan" $dom
  Sprawdz "baza: Stan po instalacji = zainstalowana, nie dziala tylko przez wylaczony nadzorca (-BezStartu)" (($r.W.zainstalowany -eq $true) -and ($r.W.dziala -eq $false) -and (@($r.W.problemy).Count -eq 1) -and ((@($r.W.problemy) -join " ") -match "nadzorca nie chodzi")) ($r.W | ConvertTo-Json -Compress -Depth 5)
  $r = Modul "baza" "Instaluj" $dom @("-BezStartu")
  Sprawdz "baza: drugi Instaluj ok, hook dalej jeden, rejestr bez zmian" (($r.Kod -eq 0) -and ((Hooki $dom "SessionStart" 'straznik-zasad\.ps1') -eq 1) -and -not ((Rejestr $dom).moduly.wiedza)) $r.Tekst
  # Usun odmawia, gdy wlaczony jest jakis modul
  . (Join-Path $Repo "narzedzia\instalacja\stan.ps1")
  Ustaw-Modul "wiedza" $true $dom
  $r = Modul "baza" "Usun" $dom
  Sprawdz "baza: Usun odmawia, gdy modul wiedza jest wlaczony" (($r.Kod -eq 1) -and ($r.W.komunikat -match "wiedza") -and [bool](Zadanie "MegaRuchaczNadzorca")) $r.Tekst
  Ustaw-Modul "wiedza" $false $dom
  $r = Modul "baza" "Usun" $dom
  Sprawdz "baza: Usun ok - hooki, nadzorca i LoreKoszt zdjete" (($r.Kod -eq 0) -and ((Hooki $dom "SessionStart" 'straznik-zasad') -eq 0) -and -not (Zadanie "MegaRuchaczNadzorca") -and -not (Zadanie "LoreKoszt")) $r.Tekst
  $r = Modul "baza" "Stan" $dom
  Sprawdz "baza: Stan po Usun = nie zainstalowana" ($r.W.zainstalowany -eq $false) $r.Tekst
  $r = Modul "baza" "Usun" $dom @("-UsunDane")
  Sprawdz "baza: Usun -UsunDane drugi raz bez szkody, pliki stanu straznika zniknely" (($r.Kod -eq 0) -and @(Get-ChildItem (Join-Path $dom ".claude") -Force -Filter ".megaruchacz-straznik*" -ErrorAction SilentlyContinue).Count -eq 0) $r.Tekst
  # proby negatywne
  $dom2 = Dom "baza-bez-gita"
  $przed = Odcisk-Domu $dom2
  $r = Modul "baza" "Instaluj" $dom2 @("-BezStartu") @{ PATH = "$Bin;$KatUv;$Systemowe" }
  Sprawdz "baza: brak gita = odmowa, brakuje git, nic nie zmienione" (($r.Kod -eq 1) -and (@($r.W.brakuje) -contains "git") -and ((Odcisk-Domu $dom2) -eq $przed) -and -not (Zadanie "MegaRuchaczNadzorca")) $r.Tekst
  # bezpiecznik testu: bez -BezStartu kopia zainstaluj-zasobnik.ps1 probuje wystartowac nadzorce,
  # a w kopii start jest zablokowany - okno nadzorcy z kopii nie moze sie pokazac
  $dom3 = Dom "baza-start"
  $r = Modul "baza" "Instaluj" $dom3
  $kopiaChodzi = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf((Join-Path $Repo "zasobnik\nadzorca.ps1"), [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count
  Sprawdz "bezpiecznik testu: start nadzorcy z kopii zablokowany (UWAGA, zaden proces nadzorcy z kopii)" (($kopiaChodzi -eq 0) -and (($r.Uwagi -join " ") -match "zablokowany w tescie|nie udalo sie wystartowac")) $r.Tekst
  [void](Modul "baza" "Usun" $dom3)
  $zip = Join-Path $T "repo-zip"
  & robocopy.exe $Repo $zip /E /XD .git .venv /NFL /NDL /NJH /NJS /NP | Out-Null
  $r = Uruchom (Join-Path $zip "narzedzia\instalacja\modul-baza.ps1") @("-Akcja", "Instaluj", "-Proba", "-KatalogDomowy", $dom2, "-Zrodlo", $zip) (Srodowisko $dom2)
  Sprawdz "baza: folder bez .git (rozpakowany ZIP) = glosna UWAGA o aktualizacjach" (($r.Kod -eq 0) -and (($r.Uwagi -join " ") -match "nie jest klonem git")) $r.Tekst
}

function Scenariusz-Wiedza {
  $dom = Dom "wiedza"
  Rozmowa $dom "Jak ustawilismy indeks bez modelu? Test trybu tylko tekst."
  [void](Modul "baza" "Instaluj" $dom @("-BezStartu"))
  $r = Modul "wiedza" "Instaluj" $dom
  Sprawdz "wiedza bez lore: Instaluj ok" ($r.Kod -eq 0) $r.Tekst
  $rej = Rejestr $dom
  Sprawdz "wiedza bez lore: rejestr wiedza=true, lore=false" ($rej.moduly.wiedza -and -not $rej.moduly.lore) ($rej | ConvertTo-Json -Compress)
  Sprawdz "wiedza bez lore: zadanie LoreIndex w trybie --text-only" ((Akcja-Zadania "LoreIndex") -match "lore\.index --text-only") (Akcja-Zadania "LoreIndex")
  $cm = [System.IO.File]::ReadAllText((Join-Path $dom ".claude\CLAUDE.md"))
  $pod = @("### O u$([char]0x017C)ytkowniku", "### O firmie", "### Nad czym pracuje", "### Jak pracuje", "### Bie$([char]0x017C)$([char]0x0105)ce", "### Dane referencyjne")
  Sprawdz "wiedza: szkielet '## Co wiem' z szescioma podsekcjami jak w verify.py" (($cm -match "(?m)^## Co wiem") -and (@($pod | Where-Object { $cm.Contains($_) }).Count -eq 6)) $cm
  # granica sekcji w verify.py: pod ostatnia podsekcja szkieletu stoi znacznik bloku MegaRuchacza
  # (po P59a: blok wiedzy z rejestru), bez zadnego naglowka "## " pomiedzy
  $iCw = $cm.IndexOf("### Dane referencyjne"); $iG = $cm.IndexOf("<!-- MegaRuchacz:", [Math]::Max(0, $iCw))
  Sprawdz "wiedza: zaraz pod szkieletem stoi znacznik bloku MegaRuchacza (granica sekcji dla verify.py)" (($iCw -ge 0) -and ($iG -gt $iCw) -and ($cm.Substring($iCw, $iG - $iCw) -notmatch "(?m)^## ")) $cm
  Sprawdz "wiedza: katalog wiedza\ i kopia dzienna 'wczoraj'" ((Test-Path (Join-Path $dom ".claude\wiedza")) -and (Test-Path (Join-Path $dom ".claude\mr\kopie-dzienne\wczoraj"))) $r.Tekst
  Sprawdz "wiedza: brak zalogowania claude/codex = UWAGA, nie odmowa" ((($r.Uwagi -join " ") -match "zalogowania|zaloguj")) ($r.Uwagi -join " | ")
  Sprawdz "wiedza: tlo indeksu skonczylo sie" (Czekaj-Na-Tlo)
  $b = Py-Baza (Join-Path $dom ".lore\lore.db")
  Sprawdz "wiedza bez lore: baza w trybie 'text', fragmenty bez wektorow" (($b.tryb -eq "text") -and ($b.fragmenty -gt 0) -and ($b.wektory -eq 0)) ($b | ConvertTo-Json -Compress)
  Sprawdz "wiedza bez lore: model wektorow NIE zostal pobrany" (-not (Test-Path (Join-Path $dom ".lore\lore_models")))
  $r = Modul "wiedza" "Stan" $dom
  Sprawdz "wiedza: Stan = zainstalowana, nie dziala tylko przez brak zalogowanego CLI" (($r.W.zainstalowany -eq $true) -and ($r.W.dziala -eq $false) -and (@($r.W.problemy).Count -eq 1) -and ((@($r.W.problemy) -join " ") -match "zalogowanego")) ($r.W | ConvertTo-Json -Compress -Depth 5)
  Set-Content -LiteralPath (Join-Path $dom ".claude\.credentials.json") -Value "{}" -Encoding ASCII
  $r = Modul "wiedza" "Stan" $dom
  Sprawdz "wiedza: Stan po zalogowaniu = dziala (tryb tylko tekst to stan, nie alarm)" (($r.W.dziala -eq $true) -and ($r.W.szczegoly.baza_tryb -eq "text")) ($r.W | ConvertTo-Json -Compress -Depth 5)
  $r = Modul "wiedza" "Instaluj" $dom
  $cm2 = [System.IO.File]::ReadAllText((Join-Path $dom ".claude\CLAUDE.md"))
  Sprawdz "wiedza: drugi Instaluj ok, 'Co wiem' dalej jedno" (($r.Kod -eq 0) -and ([regex]::Matches($cm2, "(?m)^## Co wiem").Count -eq 1)) $r.Tekst
  [void](Czekaj-Na-Tlo)
  $r = Modul "wiedza" "Usun" $dom
  Sprawdz "wiedza: Usun ok - zadanie i srodowisko zdjete (lore wylaczony)" (($r.Kod -eq 0) -and -not (Zadanie "LoreIndex") -and -not (Test-Path (Join-Path $Repo "lore\.venv"))) $r.Tekst
  Sprawdz "wiedza: Usun bez -UsunDane zostawia wiedza\, 'Co wiem' i lore.db" ((Test-Path (Join-Path $dom ".claude\wiedza")) -and ([System.IO.File]::ReadAllText((Join-Path $dom ".claude\CLAUDE.md")) -match "## Co wiem") -and (Test-Path (Join-Path $dom ".lore\lore.db")))
  Sprawdz "wiedza: rejestr wiedza=false" (-not (Rejestr $dom).moduly.wiedza)
  $r = Modul "wiedza" "Stan" $dom
  Sprawdz "wiedza: Stan po Usun = nie zainstalowana" ($r.W.zainstalowany -eq $false) $r.Tekst
  $r = Modul "wiedza" "Instaluj" $dom
  [void](Czekaj-Na-Tlo)
  $r = Modul "wiedza" "Usun" $dom @("-UsunDane")
  $cm3 = [System.IO.File]::ReadAllText((Join-Path $dom ".claude\CLAUDE.md"))
  Sprawdz "wiedza: Usun -UsunDane usuwa wiedza\, kopie dzienne, 'Co wiem' (kopia CLAUDE.md obok) i lore.db" (($r.Kod -eq 0) -and -not (Test-Path (Join-Path $dom ".claude\wiedza")) -and -not (Test-Path (Join-Path $dom ".claude\mr\kopie-dzienne")) -and ($cm3 -notmatch "## Co wiem") -and (@(Get-ChildItem (Join-Path $dom ".claude") -Filter "CLAUDE.md.bak-*").Count -gt 0) -and -not (Test-Path (Join-Path $dom ".lore\lore.db"))) $r.Tekst
  # Dom z blokiem kierownika: szkielet ma stanac nad nim. To bezpieczne tylko dlatego, ze verify.py (od P59a)
  # konczy sekcje na KAZDYM znaczniku MegaRuchacza - warunek sprawdzany wprost, inaczej fakty szlyby do bloku.
  Sprawdz "warunek: verify.py konczy 'Co wiem' na kazdym znaczniku <!-- MegaRuchacz: (GUARD_PREFIX)" ([System.IO.File]::ReadAllText((Join-Path $Repo "lore\lore\verify.py")) -match '(?m)^GUARD_PREFIX\s*=\s*"<!-- MegaRuchacz:"')
  $dom5 = Dom "wiedza-kierownik"
  [System.IO.File]::WriteAllText((Join-Path $dom5 ".claude\CLAUDE.md"), "# Ustalenia globalne`n`n<!-- MegaRuchacz:kierownik:start -->`n# MegaRuchacz - kierownik`n<!-- MegaRuchacz:kierownik:koniec -->`n")
  [void](Modul "baza" "Instaluj" $dom5 @("-BezStartu"))   # rejestr: bez niego lore liczy sie jako wlaczone (indeks z wektorami)
  # Rejestr zgodny z plikiem: blok kierownika stoi, wiec kierownik wlaczony. Od P64 Po-Zmianie-Rejestru wola
  # straznik -Dopasuj, a ten blok kierownika wylaczonego w rejestrze zdejmuje od razu (tak jak przy starcie sesji).
  . (Join-Path $Repo "narzedzia\instalacja\stan.ps1")
  Ustaw-Modul "kierownik" $true $dom5
  $r = Modul "wiedza" "Instaluj" $dom5
  $wyglad = [System.IO.File]::ReadAllText((Join-Path $dom5 ".claude\CLAUDE.md"))
  $iCw = $wyglad.IndexOf("## Co wiem"); $iK = $wyglad.IndexOf("<!-- MegaRuchacz:kierownik:start -->"); $iDane = $wyglad.IndexOf("### Dane referencyjne")
  $miedzy = if ($iDane -ge 0 -and $iK -gt $iDane) { $wyglad.Substring($iDane, $iK - $iDane) } else { "?" }
  Sprawdz "wiedza: dom z blokiem kierownika - szkielet nad nim, bez pustego starego bloku MegaRuchacz:start" (($r.Kod -eq 0) -and ($iCw -ge 0) -and ($iCw -lt $iK) -and ($miedzy -notmatch "MegaRuchacz:start")) $wyglad
  [void](Czekaj-Na-Tlo)
  $r = Modul "wiedza" "Usun" $dom5
  Ustaw-Modul "kierownik" $false $dom5   # baza odmawia, dopoki jakis modul jest wlaczony
  [void](Modul "baza" "Usun" $dom5)
  Sprawdz "wiedza: po przypadku z blokiem kierownika sprzatniete (zadanie LoreIndex zdjete)" (($r.Kod -eq 0) -and -not (Zadanie "LoreIndex")) $r.Tekst
  # wyzerowany CLAUDE.md (zanik pradu) = odmowa, plik nietkniety, bez kopii zer
  $dom4 = Dom "wiedza-zera"
  [System.IO.File]::WriteAllBytes((Join-Path $dom4 ".claude\CLAUDE.md"), (New-Object byte[] 300))
  $przed = Odcisk-Domu $dom4
  $r = Modul "wiedza" "Instaluj" $dom4
  Sprawdz "wiedza: wyzerowany CLAUDE.md = odmowa z alarmem i poleceniem przywrocenia, nic nie ruszone" (($r.Kod -eq 1) -and ($r.W.komunikat -match "ALARM: wyzerowane") -and ($r.W.komunikat -match "-Przywroc") -and ((Odcisk-Domu $dom4) -eq $przed) -and -not (Zadanie "LoreIndex")) $r.Tekst
  # brak uv = odmowa bez zmian
  $dom2 = Dom "wiedza-bez-uv"
  $przed = Odcisk-Domu $dom2
  $r = Modul "wiedza" "Instaluj" $dom2 @() @{ PATH = "$Bin;$KatGit;$Systemowe" }
  Sprawdz "wiedza: brak uv = odmowa, brakuje uv i python, nic nie zmienione" (($r.Kod -eq 1) -and (@($r.W.brakuje) -contains "uv") -and ((Odcisk-Domu $dom2) -eq $przed) -and -not (Zadanie "LoreIndex")) $r.Tekst
}

function Scenariusz-Lore {
  if (-not $script:ModelKopia) { Info "lore: pominiete - nie ma prawdziwego modelu do skopiowania (test nie pobiera 496 MB)"; return }
  $dom = Dom "lore"
  Rozmowa $dom "Pytanie do Lore z wektorami: jak liczymy koszt pamieci?"
  Zasiej-Model $dom
  [void](Modul "baza" "Instaluj" $dom @("-BezStartu"))
  $r = Modul "lore" "Instaluj" $dom
  Sprawdz "lore sam: Instaluj ok" ($r.Kod -eq 0) $r.Tekst
  $mcp = Stub-Mcp $dom "claude"
  Sprawdz "lore: serwer zarejestrowany w Claude Code poleceniem z kopii" (("" + $mcp) -match ([regex]::Escape((Join-Path $Repo "lore")) + " run python -m lore\.server")) "$mcp"
  Sprawdz "lore: serwer zarejestrowany tez w Codeksie (codex mcp add)" (("" + (Stub-Mcp $dom "codex")) -match "lore\.server")
  Sprawdz "lore: zadanie LoreIndex z wektorami (bez --text-only)" (((Akcja-Zadania "LoreIndex") -match "lore\.index") -and ((Akcja-Zadania "LoreIndex") -notmatch "text-only")) (Akcja-Zadania "LoreIndex")
  Sprawdz "lore: model policzyl probny wektor i serwer odpowiedzial po MCP" ((($r.Kroki -join " ") -match "model wektorow dziala") -and (($r.Kroki -join " ") -match "odpowiada na wywolanie MCP")) ($r.Kroki -join " | ")
  Sprawdz "lore: tlo indeksu skonczylo sie" (Czekaj-Na-Tlo)
  $b = Py-Baza (Join-Path $dom ".lore\lore.db")
  Sprawdz "lore: baza w trybie 'vectors', kazdy fragment ma wektor" (($b.tryb -eq "vectors") -and ($b.fragmenty -gt 0) -and ($b.wektory -eq $b.fragmenty)) ($b | ConvertTo-Json -Compress)
  $r = Modul "lore" "Stan" $dom
  Sprawdz "lore: Stan = dziala" (($r.W.zainstalowany -eq $true) -and ($r.W.dziala -eq $true)) ($r.W | ConvertTo-Json -Compress -Depth 5)
  $r = Modul "lore" "Instaluj" $dom
  $log = Get-Content (Join-Path $dom ".atrapa-claude.log") -Raw
  Sprawdz "lore: drugi Instaluj ok - stary wpis podmieniony (remove + add), dalej jeden" (($r.Kod -eq 0) -and ($log -match "mcp remove lore") -and ([regex]::Matches($log, "mcp add").Count -eq 2) -and (Stub-Mcp $dom "claude")) $r.Tekst
  [void](Czekaj-Na-Tlo)
  # serwera nie da sie zdjac (atrapa claude odmawia "mcp remove") = lore zostaje wlaczone w rejestrze
  $r = Modul "lore" "Usun" $dom @() @{ ATRAPA_PSUJ_REMOVE = "1" }
  Sprawdz "lore: nieudane zdjecie serwera MCP = odmowa, rejestr dalej lore=true, model i zadanie zostaja" (($r.Kod -eq 1) -and ($r.W.komunikat -match "nie zdjalem serwera MCP") -and (Rejestr $dom).moduly.lore -and (Test-Path (Join-Path $dom ".lore\lore_models")) -and [bool](Zadanie "LoreIndex")) $r.Tekst
  $r = Modul "lore" "Usun" $dom
  Sprawdz "lore: Usun ok - serwer wyrejestrowany wszedzie" (($r.Kod -eq 0) -and -not (Stub-Mcp $dom "claude") -and -not (Stub-Mcp $dom "codex")) $r.Tekst
  Sprawdz "lore: Usun zdejmuje model, zadanie i srodowisko (wiedza wylaczona), lore.db zostaje" (-not (Test-Path (Join-Path $dom ".lore\lore_models")) -and -not (Zadanie "LoreIndex") -and -not (Test-Path (Join-Path $Repo "lore\.venv")) -and (Test-Path (Join-Path $dom ".lore\lore.db")))
  Sprawdz "lore: rejestr lore=false" (-not (Rejestr $dom).moduly.lore)
  $r = Modul "lore" "Usun" $dom @("-UsunDane")
  Sprawdz "lore: Usun -UsunDane usuwa baze rozmow" (($r.Kod -eq 0) -and -not (Test-Path (Join-Path $dom ".lore\lore.db"))) $r.Tekst
  # brak internetu przy modelu: HF_HUB_OFFLINE, modelu na dysku nie ma
  $dom2 = Dom "lore-bez-sieci"
  Rozmowa $dom2 "cos"
  $r = Modul "lore" "Instaluj" $dom2 @() @{ HF_HUB_OFFLINE = "1" }
  Sprawdz "lore: brak internetu przy modelu = odmowa z powodem, rejestr i MCP nietkniete" (($r.Kod -eq 1) -and ($r.W.komunikat -match "brak internetu") -and -not (Stub-Mcp $dom2 "claude") -and -not ((Rejestr $dom2) -and (Rejestr $dom2).moduly.lore)) $r.Tekst
  [void](Modul "lore" "Usun" $dom2)
  # brak narzedzia, w ktorym da sie zarejestrowac serwer
  $dom3 = Dom "lore-bez-narzedzi"
  $przed = Odcisk-Domu $dom3
  $r = Modul "lore" "Instaluj" $dom3 @() @{ PATH = "$KatUv;$KatGit;$Systemowe" }
  Sprawdz "lore: brak Claude Code, Codeksa i opencode = odmowa, nic nie zmienione" (($r.Kod -eq 1) -and ($r.W.komunikat -match "nie ma narzedzia") -and ((Odcisk-Domu $dom3) -eq $przed)) $r.Tekst
}

function Scenariusz-WiedzaLore {
  if (-not $script:ModelKopia) { Info "wiedza+lore: pominiete - nie ma modelu do skopiowania"; return }
  $dom = Dom "wiedzalore"
  Rozmowa $dom "Najpierw tylko tekst, potem wektory."
  Set-Content -LiteralPath (Join-Path $dom ".claude\.credentials.json") -Value "{}" -Encoding ASCII
  [void](Modul "baza" "Instaluj" $dom @("-BezStartu"))
  $r = Modul "wiedza" "Instaluj" $dom
  [void](Czekaj-Na-Tlo)
  $b = Py-Baza (Join-Path $dom ".lore\lore.db")
  Sprawdz "wiedza+lore: najpierw wiedza - tylko tekst, zero wektorow" (($r.Kod -eq 0) -and ($b.tryb -eq "text") -and ($b.wektory -eq 0) -and ($b.fragmenty -gt 0)) ($b | ConvertTo-Json -Compress)
  Zasiej-Model $dom
  $r = Modul "lore" "Instaluj" $dom
  Sprawdz "wiedza+lore: lore przelacza zadanie na wektory i liczy brakujace w tle" (($r.Kod -eq 0) -and ((Akcja-Zadania "LoreIndex") -notmatch "text-only") -and (($r.Kroki -join " ") -match "liczenie brakujacych wektorow")) $r.Tekst
  [void](Czekaj-Na-Tlo)
  $b = Py-Baza (Join-Path $dom ".lore\lore.db")
  Sprawdz "wiedza+lore: po lore.migrate kazdy fragment z trybu tekstowego ma wektor" (($b.tryb -eq "vectors") -and ($b.wektory -eq $b.fragmenty)) ($b | ConvertTo-Json -Compress)
  $sw = Modul "wiedza" "Stan" $dom; $sl = Modul "lore" "Stan" $dom
  Sprawdz "wiedza+lore: oba moduly dzialaja" (($sw.W.dziala -eq $true) -and ($sl.W.dziala -eq $true)) (($sw.W | ConvertTo-Json -Compress -Depth 5) + " / " + ($sl.W | ConvertTo-Json -Compress -Depth 5))
  $r = Modul "lore" "Usun" $dom
  $b = Py-Baza (Join-Path $dom ".lore\lore.db")
  Sprawdz "wiedza+lore: Usun lore - zadanie wraca do --text-only, srodowisko zostaje, model znika" (($r.Kod -eq 0) -and ((Akcja-Zadania "LoreIndex") -match "text-only") -and (Test-Path (Join-Path $Repo "lore\.venv")) -and -not (Test-Path (Join-Path $dom ".lore\lore_models")) -and ($b.tryb -eq "text")) $r.Tekst
  $sw = Modul "wiedza" "Stan" $dom
  Sprawdz "wiedza+lore: wiedza dalej dziala bez lore" ($sw.W.dziala -eq $true) ($sw.W | ConvertTo-Json -Compress -Depth 5)
  $r = Modul "wiedza" "Usun" $dom
  Sprawdz "wiedza+lore: Usun wiedza - teraz zadanie i srodowisko znikaja" (($r.Kod -eq 0) -and -not (Zadanie "LoreIndex") -and -not (Test-Path (Join-Path $Repo "lore\.venv"))) $r.Tekst
}

function Scenariusz-Kierownik {
  $dom = Dom "kierownik"
  Set-Content -LiteralPath (Join-Path $dom ".claude\history.jsonl") -Value "" -Encoding ASCII   # "Claude Code tu pracuje" - wariant claude
  New-Item -ItemType Directory -Force -Path (Join-Path $dom ".codex\agents") | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $dom ".codex\hooks.json"), '{"hooks":{"SubagentStart":[{"hooks":[{"type":"command","command":"node cudzy.js"}]}]}}')
  [void](Modul "baza" "Instaluj" $dom @("-BezStartu"))
  . (Join-Path $Repo "narzedzia\instalacja\stan.ps1")
  $s = Czytaj-Instalacje $dom; $s | Add-Member -NotePropertyName narzedzia -NotePropertyValue ([pscustomobject]@{ claude = $true; codex = $true; opencode = $false }) -Force; Zapisz-Instalacje $s $dom
  $r = Modul "kierownik" "Instaluj" $dom
  Sprawdz "kierownik: Instaluj ok" ($r.Kod -eq 0) $r.Tekst
  $role = @(Get-ChildItem (Join-Path $dom ".claude\agents") -Filter "*.md" -ErrorAction SilentlyContinue | Where-Object { (Get-Content $_.FullName -Raw) -match "kierownik-template" })
  Sprawdz "kierownik: piec rol, blok zasad, rejestr, ladunek, znacznik" (($role.Count -eq 5) -and ([regex]::Matches([System.IO.File]::ReadAllText((Join-Path $dom ".claude\CLAUDE.md")), "MegaRuchacz:kierownik:start").Count -eq 1) -and (Test-Path (Join-Path $dom ".claude\megaruchacz-mr-log.js")) -and (Test-Path (Join-Path $dom ".claude\mr\orchestrator-reminder.json")) -and (Test-Path (Join-Path $dom ".claude\.megaruchacz-global"))) $r.Tekst
  Sprawdz "kierownik: hooki START/KONIEC i przypomnienie po jednym" (((Hooki $dom "SubagentStart" 'mr-log\.js') -eq 1) -and ((Hooki $dom "SubagentStop" 'mr-log\.js') -eq 1) -and ((Hooki $dom "UserPromptSubmit" 'przypomnienie\.js') -eq 1))
  Sprawdz "kierownik: rejestr narzedzia.codex = true -> role Codeksa" (@(Get-ChildItem (Join-Path $dom ".codex\agents") -Filter "*.toml" -ErrorAction SilentlyContinue).Count -ge 4) $r.Tekst
  $r = Modul "kierownik" "Stan" $dom
  Sprawdz "kierownik: Stan = dziala" (($r.W.zainstalowany -eq $true) -and ($r.W.dziala -eq $true)) ($r.W | ConvertTo-Json -Compress -Depth 5)
  $r = Modul "kierownik" "Instaluj" $dom
  Sprawdz "kierownik: drugi Instaluj ok - blok i hooki dalej po jednym" (($r.Kod -eq 0) -and ([regex]::Matches([System.IO.File]::ReadAllText((Join-Path $dom ".claude\CLAUDE.md")), "MegaRuchacz:kierownik:start").Count -eq 1) -and ((Hooki $dom "SubagentStart" 'mr-log\.js') -eq 1)) $r.Tekst
  $r = Modul "kierownik" "Usun" $dom
  $role = @(Get-ChildItem (Join-Path $dom ".claude\agents") -Filter "*.md" -ErrorAction SilentlyContinue | Where-Object { (Get-Content $_.FullName -Raw) -match "kierownik-template" })
  Sprawdz "kierownik: Usun ok - role i blok zdjete, rejestr kierownik=false" (($r.Kod -eq 0) -and ($role.Count -eq 0) -and ([System.IO.File]::ReadAllText((Join-Path $dom ".claude\CLAUDE.md")) -notmatch "MegaRuchacz:kierownik") -and -not (Rejestr $dom).moduly.kierownik) $r.Tekst
  $hc = [System.IO.File]::ReadAllText((Join-Path $dom ".codex\hooks.json"))
  Sprawdz "kierownik: role i hooki rejestru Codeksa zdjete, cudzy hook Codeksa zostal" ((@(Get-ChildItem (Join-Path $dom ".codex\agents") -Filter "*.toml" -ErrorAction SilentlyContinue | Where-Object { (Get-Content $_.FullName -Raw) -match "kierownik-template" }).Count -eq 0) -and ($hc -notmatch "mr-log-codex") -and ($hc -match "cudzy\.js")) $hc
  Sprawdz "kierownik: hook straznika (baza) zostal" ((Hooki $dom "SessionStart" 'straznik-zasad\.ps1') -eq 1)
  $znaRejestr = [System.IO.File]::ReadAllText((Join-Path $Repo "narzedzia\straznik-zasad.ps1")) -match 'Czytaj-Instalacje|instalacja\\stan\.ps1'
  $sa = ((Hooki $dom "SubagentStart" 'mr-log\.js') -gt 0) -or (Test-Path (Join-Path $dom ".claude\mr\orchestrator-reminder.json")) -or (Test-Path (Join-Path $dom ".claude\megaruchacz-mr-log.js"))
  if ($znaRejestr) { Sprawdz "kierownik: po Usun nie ma hookow rejestru, ladunku przypomnienia ani megaruchacz-mr-log.js (straznik zna rejestr)" (-not $sa) }
  elseif ($sa) { Info "kierownik: straznik w kopii (HEAD) nie zna jeszcze rejestru - po Usun przywrocil hooki rejestru/ladunek (samonaprawa P63 C4; poprawia P59a)" }
}

# git pisze ostrzezenia na stderr - przy $ErrorActionPreference = Stop kazde byloby wyjatkiem
function Git-Cicho([string[]]$a) {
  $stare = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  try { $wy = & git @a 2>&1; $kod = $LASTEXITCODE } finally { $ErrorActionPreference = $stare }
  if ($kod -ne 0) { throw "git $($a -join ' ') zakonczyl sie kodem ${kod}: $($wy -join ' ')" }
}

function Scenariusz-Skille {
  $src = Join-Path $T "zrodlo-skilli"
  New-Item -ItemType Directory -Force -Path (Join-Path $src "skills\test-skill") | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $src "skills\test-skill\SKILL.md"), "---`nname: test-skill`ndescription: skill testowy`n---`n# Test`n")
  Git-Cicho @("-C", $src, "init", "-q", "-b", "main")
  Git-Cicho @("-C", $src, "config", "core.autocrlf", "false")
  Git-Cicho @("-C", $src, "config", "uploadpack.allowFilter", "true")
  Git-Cicho @("-C", $src, "add", "-A")
  Git-Cicho @("-C", $src, "-c", "user.name=test", "-c", "user.email=test@test", "commit", "-q", "-m", "start")
  $adres = "file:///" + $src.Replace('\', '/')
  $kat = Join-Path $T "katalog-skilli.psd1"
  [System.IO.File]::WriteAllText($kat, "@{`r`n  Wersja = 1`r`n  Zrodla = @(`r`n    @{ Id = 'test'; Nazwa = 'Test'; Adres = '$adres'; Galaz = 'main'; Sciezka = 'skills'; Opis = 'zrodlo testowe'; Skille = @( @{ Nazwa = 'test-skill'; Opis = 'skill testowy' } ) }`r`n  )`r`n}`r`n", (New-Object System.Text.UTF8Encoding($true)))
  $dom = Dom "skille"
  $r = Modul "skille" "Instaluj" $dom @("-KatalogSkilli", $kat)
  Sprawdz "skille: Instaluj ok - przejecie pod opieke zapisalo stan, rejestr skille=true" (($r.Kod -eq 0) -and (Test-Path (Join-Path $dom ".claude\mr\skille\stan.json")) -and (Rejestr $dom).moduly.skille) $r.Tekst
  $r = Modul "skille" "Instaluj" $dom @("-KatalogSkilli", $kat)
  Sprawdz "skille: drugi Instaluj ok" ($r.Kod -eq 0) $r.Tekst
  $r = Modul "skille" "Stan" $dom @("-KatalogSkilli", $kat)
  Sprawdz "skille: Stan = zainstalowane i dzialaja" (($r.W.zainstalowany -eq $true) -and ($r.W.dziala -eq $true)) ($r.W | ConvertTo-Json -Compress -Depth 5)
  $r = Modul "skille" "Usun" $dom
  Sprawdz "skille: Usun ok - rejestr false, stan opieki zostaje" (($r.Kod -eq 0) -and -not (Rejestr $dom).moduly.skille -and (Test-Path (Join-Path $dom ".claude\mr\skille"))) $r.Tekst
  $r = Modul "skille" "Usun" $dom @("-UsunDane")
  Sprawdz "skille: Usun -UsunDane usuwa stan opieki, katalog skilli zostaje" (($r.Kod -eq 0) -and -not (Test-Path (Join-Path $dom ".claude\mr\skille")) -and (Test-Path (Join-Path $dom ".claude\skills"))) $r.Tekst
  $r = Modul "skille" "Instaluj" (Dom "skille-zly") @("-KatalogSkilli", (Join-Path $T "nie-ma.psd1"))
  Sprawdz "skille: brak bazy polecanych skilli = odmowa" (($r.Kod -eq 1) -and ($r.W.komunikat -match "nie ma bazy")) $r.Tekst
  $dom3 = Dom "skille-bez-gita"
  $r = Modul "skille" "Instaluj" $dom3 @("-KatalogSkilli", $kat) @{ PATH = "$Bin;$KatUv;$Systemowe" }
  Sprawdz "skille: brak gita = odmowa, brakuje git" (($r.Kod -eq 1) -and (@($r.W.brakuje) -contains "git") -and -not (Rejestr $dom3)) $r.Tekst
}

function Scenariusz-Kopia {
  $dom = Dom "kopia"
  $cel = Join-Path $T "kopie-cel"
  New-Item -ItemType Directory -Force -Path (Join-Path $dom "dane"), (Join-Path $dom "dane\cache") | Out-Null
  . (Join-Path $Repo "narzedzia\instalacja\stan.ps1")
  $r = Modul "kopia" "Instaluj" $dom
  Sprawdz "kopia: bez rejestru = odmowa z odeslaniem do ustawien domyslnych skryptu kopii" (($r.Kod -eq 1) -and ($r.W.komunikat -match "kopia-zapasowa-domyslne\.json") -and -not (Zadanie "MegaRuchaczKopia") -and -not (Rejestr $dom)) $r.Tekst
  $s = Czytaj-Instalacje $dom; Zapisz-Instalacje $s $dom
  $r = Modul "kopia" "Instaluj" $dom
  Sprawdz "kopia: rejestr bez pola kopia = odmowa" (($r.Kod -eq 1) -and ($r.W.komunikat -match "nie ma ustawien kopii") -and -not (Zadanie "MegaRuchaczKopia")) $r.Tekst
  $s = Czytaj-Instalacje $dom
  $s | Add-Member -NotePropertyName kopia -NotePropertyValue ([pscustomobject]@{ zrodla = @("~\dane"); cel = $cel; wykluczenia = @([pscustomobject]@{ sciezka = "~\dane\cache"; powod = "test"; katalog = $true }) }) -Force
  Zapisz-Instalacje $s $dom
  $r = Modul "kopia" "Instaluj" $dom
  Sprawdz "kopia: Instaluj ok - folder celu zalozony, zadanie MRTEST-MegaRuchaczKopia, rejestr kopia=true" (($r.Kod -eq 0) -and (Test-Path $cel) -and [bool](Zadanie "MegaRuchaczKopia") -and (Rejestr $dom).moduly.kopia) $r.Tekst
  Sprawdz "kopia: '~' w zrodlach rozwiniete do domu, wykluczenia wypisane" ((($r.Kroki -join " ") -match ([regex]::Escape((Join-Path $dom "dane")))) -and (($r.Kroki -join " ") -match "wykluczone z kopii \(1\)")) ($r.Kroki -join " | ")
  $r = Modul "kopia" "Instaluj" $dom
  Sprawdz "kopia: drugi Instaluj ok" ($r.Kod -eq 0) $r.Tekst
  $r = Modul "kopia" "Stan" $dom
  Sprawdz "kopia: Stan = dziala" (($r.W.zainstalowany -eq $true) -and ($r.W.dziala -eq $true)) ($r.W | ConvertTo-Json -Compress -Depth 5)
  Set-Content -LiteralPath (Join-Path $dom ".claude\mr\kopia-stan.txt") -Value "stan=BLAD`r`nostatnia=2026-10-01 12:30:00" -Encoding ASCII
  $r = Modul "kopia" "Stan" $dom
  Sprawdz "kopia: Stan po nieudanej kopii = nie dziala z powodem" (($r.W.dziala -eq $false) -and ((@($r.W.problemy) -join " ") -match "BLAD")) ($r.W | ConvertTo-Json -Compress -Depth 5)
  $r = Modul "kopia" "Usun" $dom
  Sprawdz "kopia: Usun ok - zadanie zdjete, folder z kopiami zostaje" (($r.Kod -eq 0) -and -not (Zadanie "MegaRuchaczKopia") -and (Test-Path $cel) -and (Test-Path (Join-Path $dom ".claude\mr\kopia-stan.txt"))) $r.Tekst
  $r = Modul "kopia" "Usun" $dom @("-UsunDane")
  Sprawdz "kopia: Usun -UsunDane usuwa stan kopii, folder z kopiami zostaje" (($r.Kod -eq 0) -and -not (Test-Path (Join-Path $dom ".claude\mr\kopia-stan.txt")) -and (Test-Path $cel)) $r.Tekst
  # rejestr z celem, ale bez listy zrodel = pliki Claude'a i Codeksa (jak w kopia-zapasowa.ps1)
  $dom2 = Dom "kopia-bez-zrodel"
  $s = Czytaj-Instalacje $dom2
  $s | Add-Member -NotePropertyName kopia -NotePropertyValue ([pscustomobject]@{ cel = (Join-Path $T "kopie-cel-2") }) -Force
  Zapisz-Instalacje $s $dom2
  $r = Modul "kopia" "Instaluj" $dom2
  Sprawdz "kopia: cel bez zrodel = UWAGA 'tylko pliki Claude'a i Codeksa'" (($r.Kod -eq 0) -and (($r.Uwagi -join " ") -match "tylko pliki Claude'a i Codeksa") -and ($r.W.szczegoly.tylko_pliki_claude_codex -eq $true)) $r.Tekst
  [void](Modul "kopia" "Usun" $dom2)
  # komputer sprzed instalatora z wlaczona kopia: pierwszy zapis rejestru (tu: wylaczenie skilli)
  # przenosi ustawienia domyslne do pola kopia - inaczej kopia-zapasowa.ps1 skonczylaby sie bledem
  $dom3 = Dom "kopia-sprzed-rejestru"
  New-Item -ItemType Directory -Force -Path (Join-Path $dom3 ".claude\mr") | Out-Null
  Set-Content -LiteralPath (Join-Path $dom3 ".claude\mr\kopia-stan.txt") -Value "stan=OK" -Encoding ASCII
  $r = Modul "skille" "Usun" $dom3
  $rj = Rejestr $dom3
  $dom_json = [System.IO.File]::ReadAllText((Join-Path $Repo "narzedzia\kopia-zapasowa-domyslne.json")) | ConvertFrom-Json
  Sprawdz "kopia: zalozenie rejestru przenosi ustawienia domyslne kopii (cel, zrodla, wykluczenia)" (($r.Kod -eq 0) -and $rj.moduly.kopia -and ($rj.kopia.cel -eq $dom_json.cel) -and (@($rj.kopia.wykluczenia).Count -eq @($dom_json.wykluczenia).Count) -and (@($rj.kopia.zrodla).Count -eq @($dom_json.zrodla).Count)) ($rj | ConvertTo-Json -Compress -Depth 5)
}

function Scenariusz-Rejestr {
  $dom = Dom "rejestr-zepsuty"
  New-Item -ItemType Directory -Force -Path (Join-Path $dom ".claude\mr") | Out-Null
  [System.IO.File]::WriteAllBytes((Join-Path $dom ".claude\mr\instalacja.json"), [byte[]](0, 0, 0, 0, 0, 0, 0, 0))   # wyzerowany jak po zaniku pradu
  $przed = Odcisk-Domu $dom
  foreach ($m in @("baza", "wiedza", "lore", "kierownik", "skille", "kopia")) {
    foreach ($a in @("Instaluj", "Usun")) {
      $dalej = @(); if ($m -eq "baza") { $dalej = @("-BezStartu") }
      $r = Modul $m $a $dom $dalej
      Sprawdz "rejestr nieczytelny: $m $a = odmowa z powodem" (($r.Kod -eq 1) -and ($r.W.komunikat -match "rejestr")) $r.Tekst
    }
    $r = Modul $m "Stan" $dom
    Sprawdz "rejestr nieczytelny: $m Stan melduje blad rejestru" (($r.Kod -eq 1) -and ((@($r.W.problemy) -join " ") -match "rejestr")) $r.Tekst
  }
  Sprawdz "rejestr nieczytelny: w domu nic sie nie zmienilo" ((Odcisk-Domu $dom) -eq $przed)
  Sprawdz "rejestr nieczytelny: zadne zadanie MRTEST- nie powstalo" (@(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "MRTEST-*" }).Count -eq 0)
}

function Scenariusz-Proba {
  $dom = Dom "proba"
  Rozmowa $dom "proba"
  $przed = Odcisk-Domu $dom
  foreach ($m in @("baza", "wiedza", "lore", "kierownik", "skille", "kopia")) {
    $r = Modul $m "Instaluj" $dom @("-Proba")
    $okKopia = ($m -eq "kopia") -and ($r.Kod -eq 1) -and ($r.W.komunikat -match "ustawien kopii")   # bez ustawien w rejestrze odmawia takze na probie
    Sprawdz "proba: $m Instaluj -Proba (kroki z [proba], nic nie zmienione)" ((($r.Kod -eq 0) -and ($r.W.proba -eq $true) -and (($r.Kroki -join " ") -match "\[proba\]")) -or $okKopia) $r.Tekst
    $r = Modul $m "Usun" $dom @("-Proba", "-UsunDane")
    Sprawdz "proba: $m Usun -Proba -UsunDane" (($r.W.proba -eq $true) -and ($r.Kod -eq 0 -or ($m -eq "baza"))) $r.Tekst
  }
  Sprawdz "proba: w domu nic sie nie zmienilo" ((Odcisk-Domu $dom) -eq $przed)
  Sprawdz "proba: zadne zadanie MRTEST- nie powstalo" (@(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "MRTEST-*" }).Count -eq 0)
  $r = Uruchom (Join-Path $Repo "narzedzia\instalacja\modul-wiedza.ps1") @("-Akcja", "Napraw", "-KatalogDomowy", $dom) (Srodowisko $dom)
  Sprawdz "umowa: nieznana akcja = WYNIK ok:false" (($r.Kod -eq 1) -and ($r.W.ok -eq $false) -and ($r.W.komunikat -match "Napraw")) $r.Tekst
  $r = Uruchom (Join-Path $Repo "narzedzia\instalacja\modul-wiedza.ps1") @("-Akcja", "Stan", "-Nieznany", "1") (Srodowisko $dom)
  Sprawdz "umowa: nieznany parametr = kod 1, bez WYNIK (porazka po stronie wolajacego)" (($r.Kod -ne 0) -and ($null -eq $r.W)) $r.Tekst
}

function Scenariusz-Stary {
  $il = Join-Path $Repo "narzedzia\instaluj-lore.ps1"
  $dom = Dom "stary"
  Rozmowa $dom "stare wywolania instaluj-lore"
  $sr = Srodowisko $dom
  $r = Uruchom $il @("-Proba", "-Zrodlo", $Repo, "-KatalogDomowy", $dom) $sr
  Sprawdz "instaluj-lore: stare wywolanie -Proba (warunki, ekran zgody, plan, kod 0)" (($r.Kod -eq 0) -and ($r.Tekst -match "Warunki wstepne") -and ($r.Tekst -match "Co zaraz stanie sie") -and ($r.Tekst -match "TRYB PROBNY - nic nie zostalo zmienione")) $r.Tekst
  $r = Uruchom $il @("-UsunOdswiezanie", "-Proba", "-Zrodlo", $Repo) $sr
  Sprawdz "instaluj-lore: -UsunOdswiezanie -Proba" (($r.Kod -eq 0) -and ($r.Tekst -match "TRYB SPRZATANIA")) $r.Tekst
  $r = Uruchom $il @("-TylkoOdswiezanie", "-Zrodlo", $Repo) $sr
  Sprawdz "instaluj-lore: stary -TylkoOdswiezanie dziala jak sprzatanie" (($r.Kod -eq 0) -and ($r.Tekst -match "Gotowe - narzedzie aktualizuje sie")) $r.Tekst
  $r = Uruchom $il @("-Czesci", "Srodowisko,Bajka", "-Zrodlo", $Repo) $sr
  Sprawdz "instaluj-lore: nieznana czesc = kod 1" (($r.Kod -eq 1) -and ($r.Tekst -match "nie znam czesci")) $r.Tekst
  $r = Uruchom $il @("-Czesci", "Srodowisko,Indeks", "-TylkoTekst", "-BezPytania", "-Zrodlo", $Repo, "-KatalogDomowy", $dom) $sr
  Sprawdz "instaluj-lore: same czesci Srodowisko+Indeks w trybie tylko tekst (testy Lore w kopii przechodza)" (($r.Kod -eq 0) -and ($r.Tekst -match "OK    testy modulu") -and ((Akcja-Zadania "LoreIndex") -match "text-only")) $r.Tekst
  $r = Uruchom $il @("-Usun", "-Czesci", "Indeks,Srodowisko", "-Zrodlo", $Repo, "-KatalogDomowy", $dom) $sr
  Sprawdz "instaluj-lore: -Usun zdejmuje zadanie i srodowisko, baza zostaje" (($r.Kod -eq 0) -and -not (Zadanie "LoreIndex") -and -not (Test-Path (Join-Path $Repo "lore\.venv")) -and (Test-Path (Join-Path $dom ".lore\lore.db"))) $r.Tekst
  if (-not $script:ModelKopia) { Info "instaluj-lore: pelne stare wywolanie pominiete - nie ma modelu do skopiowania"; return }
  # pelne stare wywolanie, tak jak wola je wdroz.ps1: wszystkie czesci razem z nadzorca. Start nadzorcy
  # z kopii jest zablokowany, wiec JEDYNE sprawdzenie, ktore ma nie przejsc, to "nadzorca w zasobniku".
  $dom2 = Dom "stary-pelny"
  Rozmowa $dom2 "pelne stare wywolanie"
  Zasiej-Model $dom2
  $r = Uruchom $il @("-Zrodlo", $Repo, "-BezPytania", "-KatalogDomowy", $dom2) (Srodowisko $dom2)
  $zle = @([regex]::Matches($r.Tekst, '(?m)^\s*BLAD\s+(\S.*)$') | ForEach-Object { $_.Groups[1].Value.Trim() } | Where-Object { $_ -notmatch '^instalacja NIE jest kompletna' } | Sort-Object -Unique)
  Sprawdz "instaluj-lore: pelne stare wywolanie -BezPytania - wszystko OK poza nadzorca (jego start zablokowany w kopii)" ((@($zle | Where-Object { $_ -notmatch '^nadzorca w zasobniku' }).Count -eq 0) -and ($r.Tekst -match "OK\s+serwer MCP odpowiada na wywolanie") -and ($r.Tekst -match "OK\s+model semantyczny") -and [bool](Zadanie "MegaRuchaczNadzorca") -and (("" + (Stub-Mcp $dom2 "claude")) -match "lore\.server")) $r.Tekst
  [void](Czekaj-Na-Tlo)
  $r = Uruchom $il @("-TylkoSprawdz", "-Zrodlo", $Repo, "-KatalogDomowy", $dom2) (Srodowisko $dom2)
  Sprawdz "instaluj-lore: stare -TylkoSprawdz sprawdza bez instalowania" (($r.Tekst -match "TRYB SPRAWDZANIA") -and ($r.Tekst -match "OK\s+zadanie w harmonogramie") -and ($r.Tekst -notmatch "Srodowisko Pythona\s*-{5}")) $r.Tekst
  $r = Uruchom $il @("-Usun", "-Czesci", "Mcp,Model,Indeks,Srodowisko,Nadzorca", "-UsunDane", "-Zrodlo", $Repo, "-KatalogDomowy", $dom2) (Srodowisko $dom2)
  Sprawdz "instaluj-lore: -Usun wszystkich czesci z -UsunDane (MCP, model, zadanie, srodowisko, nadzorca, baza)" (($r.Kod -eq 0) -and -not (Stub-Mcp $dom2 "claude") -and -not (Test-Path (Join-Path $dom2 ".lore\lore_models")) -and -not (Zadanie "LoreIndex") -and -not (Zadanie "MegaRuchaczNadzorca") -and -not (Test-Path (Join-Path $dom2 ".lore\lore.db"))) $r.Tekst
}

function Scenariusz-UsunNaCzystym {
  # okno instalatora wola Usun dla odznaczonych modulow - na swiezej maszynie nie moze to nic zepsuc
  $dom = Dom "usun-czysty"
  [void](Modul "baza" "Instaluj" $dom @("-BezStartu"))
  $przedZadania = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "MRTEST-*" } | ForEach-Object { $_.TaskName } | Sort-Object) -join ","
  foreach ($m in @("wiedza", "lore", "kierownik", "skille", "kopia")) {
    $r = Modul $m "Usun" $dom
    Sprawdz "usun na czystym: $m Usun = ok, nic do zdjecia" ($r.Kod -eq 0) $r.Tekst
  }
  $rej = Rejestr $dom
  Sprawdz "usun na czystym: rejestr dalej - wszystkie moduly wylaczone" (-not ($rej.moduly.wiedza -or $rej.moduly.lore -or $rej.moduly.kierownik -or $rej.moduly.skille -or $rej.moduly.kopia)) ($rej | ConvertTo-Json -Compress)
  $poZadania = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "MRTEST-*" } | ForEach-Object { $_.TaskName } | Sort-Object) -join ","
  Sprawdz "usun na czystym: zadne nowe zadanie nie powstalo" ($przedZadania -eq $poZadania) "przed: $przedZadania / po: $poZadania"
  Sprawdz "usun na czystym: hook straznika (baza) zostal" ((Hooki $dom "SessionStart" 'straznik-zasad\.ps1') -eq 1)
}

# ---------------------------------------------------------------- przebieg

$odciskPrzed = $null
try {
  Zdejmij-Zadania-Testu   # resztki po przerwanym przebiegu
  New-Item -ItemType Directory -Force -Path $T | Out-Null
  $script:BylyWRepo = @(@("Microsoft", "AppData") | Where-Object { Test-Path -LiteralPath (Join-Path $RepoPrawdziwe $_) })
  $odciskPrzed = Odcisk-Prawdziwy
  Write-Host "Katalog testu: $T"
  Przygotuj-Kopie
  $script:UvCache = (& $UvPrawdziwy cache dir 2>$null | Select-Object -Last 1)
  $script:UvPython = (& $UvPrawdziwy python dir 2>$null | Select-Object -Last 1)
  $modelP = Join-Path $HOME ".claude\lore_models\sdadas--mmlw-retrieval-roberta-base"
  $script:ModelKopia = $null
  if ((Test-Path (Join-Path $modelP "onnx\model.onnx")) -and (@("lore", "wiedzalore", "stary") | Where-Object { $wybrane -contains $_ })) {
    $script:ModelKopia = Join-Path $T "model\sdadas--mmlw-retrieval-roberta-base"
    & robocopy.exe $modelP $script:ModelKopia /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "nie skopiowalem modelu do katalogu testu (robocopy $LASTEXITCODE)" }
  }
  Sprawdz "kopia repo przygotowana (zadania MRTEST-, data 2099, start nadzorcy zablokowany)" $true
  foreach ($s in $Scenariusze) {
    if ($wybrane -notcontains $s) { continue }
    Write-Host ""; Write-Host "=== $s ===" -ForegroundColor Cyan
    try {
      switch ($s) {
        "zaleznosci" { Scenariusz-Zaleznosci } "baza" { Scenariusz-Baza } "wiedza" { Scenariusz-Wiedza } "lore" { Scenariusz-Lore }
        "wiedzalore" { Scenariusz-WiedzaLore } "kierownik" { Scenariusz-Kierownik } "skille" { Scenariusz-Skille } "kopia" { Scenariusz-Kopia }
        "rejestr" { Scenariusz-Rejestr } "proba" { Scenariusz-Proba } "stary" { Scenariusz-Stary } "usunczysty" { Scenariusz-UsunNaCzystym }
      }
    } catch {
      Sprawdz "scenariusz $s wywrocil sie" $false ($_.Exception.Message + " " + $_.InvocationInfo.PositionMessage)
    }
    [void](Czekaj-Na-Tlo 120)
    Zdejmij-Zadania-Testu
  }
} catch {
  Sprawdz "przygotowanie testu" $false ($_.Exception.Message + " " + $_.InvocationInfo.PositionMessage)
} finally {
  Zdejmij-Zadania-Testu
  foreach ($p in @(Procesy-Testu)) { try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop } catch { Write-Host "BLAD  nie zatrzymalem procesu testu $($p.ProcessId)" } }
  Start-Sleep -Milliseconds 500
  Sprawdz "po tescie: zadnego zadania MRTEST-" (@(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like "MRTEST-*" }).Count -eq 0)
  Sprawdz "po tescie: zaden proces z kopii nie zostal" (@(Procesy-Testu).Count -eq 0)
  if ($odciskPrzed) {
    $po = Odcisk-Prawdziwy
    foreach ($k in $odciskPrzed.Keys) { Sprawdz "prawdziwy stan bez zmian: $k" ($odciskPrzed[$k] -eq $po[$k]) "przed: $($odciskPrzed[$k]) / po: $($po[$k])" }
  }
  $wskazuja = @(Prawdziwe-Wskazuja-Test)
  Sprawdz "zadna prawdziwa konfiguracja nie wskazuje katalogu testu" ($wskazuja.Count -eq 0) ($wskazuja -join ", ")
  # wyciek przez pusty GetFolderPath (patrz Ustaw-Katalog-Domowy): PowerShell z podstawionym domem bez
  # AppData pisal Microsoft\...\ModuleAnalysisCache wzgledem katalogu roboczego - do repo
  $wyciek = @(@("Microsoft", "AppData") | Where-Object { (Test-Path -LiteralPath (Join-Path $RepoPrawdziwe $_)) -and ($script:BylyWRepo -notcontains $_) })
  Sprawdz "w katalogu repo nie przybylo Microsoft\ ani AppData\ (zapis wzgledem katalogu roboczego)" ($wyciek.Count -eq 0) ($wyciek -join ", ")
  if (Test-Path -LiteralPath $TmpKrotki) {
    try { Remove-Item -LiteralPath $TmpKrotki -Recurse -Force -ErrorAction Stop } catch { & cmd.exe /d /c "rd /s /q `"\\?\$TmpKrotki`"" 2>&1 | Out-Null }
    if (Test-Path -LiteralPath $TmpKrotki) { Write-Host "UWAGA katalog tymczasowy testu nie dal sie usunac w calosci: $TmpKrotki" }
  }
  if (-not $Zostaw -and (Test-Path -LiteralPath $T)) {
    try { Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction Stop } catch { & cmd.exe /d /c "rd /s /q `"\\?\$T`"" 2>&1 | Out-Null }   # sciezki > 260 znakow w .venv
    if (Test-Path -LiteralPath $T) { Write-Host "UWAGA katalog testu nie dal sie usunac w calosci: $T" }
  }
  Write-Host ""
  Write-Host ("Wynik: {0} sprawdzen, {1} nie przeszlo." -f $script:Wynik.Count, $script:Zle)
  foreach ($i in $script:Info) { Write-Host "INFO  $i" }
}
if ($script:Zle -gt 0) { exit 1 }
exit 0
