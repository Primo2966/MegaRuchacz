# Proba cyklu wiedzy na maszynie z samym OpenCode (bez Claude Code i bez Codeksa).
#
# A. cykl-dzienny.ps1 (jego funkcje, wyjete z pliku bez uruchamiania cyklu): wykrywanie narzedzi
#    widzi OpenCode, adres sieci bierze z dostawcy w auth.json, zalogowanie z istnienia auth.json;
#    komunikaty "brak narzedzia" wymieniaja opencode i nie przypisuja bledu zlemu narzedziu.
# B. aktualizuj-wiedze.ps1 -BezWylawiania na sztucznym katalogu domowym (USERPROFILE podmieniony,
#    wiec ~ w lore\lore\verify.py to dom testu): fakt z poczekalni trafia do
#    ~\.config\opencode\AGENTS.md, CLAUDE.md i ~\.codex NIE powstaja; licznik surowej struktury
#    w poczekalni wychodzi na wierzch jako UWAGA.
# Proby negatywne: plik OpenCode bez sekcji "## Co wiem" - nic nie wpisane, plik co do bajtu,
#    a przebieg MOWI dlaczego (powod), zamiast milczec; zaden plik instrukcji - glosna UWAGA.
#
# Model nie jest wolany (-BezWylawiania). Wszystko w %TEMP%; prawdziwe ~\.claude, ~\.codex
# i ~\.config\opencode nie sa ruszane.
#
# Uzycie:  powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File narzedzia\test-cykl-opencode.ps1 [-Zostaw]
# Kod wyjscia: 0 = wszystkie proby przeszly, 1 = ktoras nie.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Zostaw
)

$ErrorActionPreference = "Stop"
$T = Join-Path $env:TEMP ("mr-test-cykl-opencode-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$script:Wynik = @()
$script:Zle = 0
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$ZZ = [char]0x017C; $AA = [char]0x0105
$BIEZACE = "### Bie${ZZ}${AA}ce"
$Systemowe = "$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\WindowsPowerShell\v1.0"

function Sprawdz([string]$co, [bool]$ok, [string]$szczegol = "") {
  $linia = $(if ($ok) { "OK    " } else { "BLAD  " }) + $co
  if (-not $ok -and $szczegol) { $linia += " -- " + $szczegol.Substring(0, [Math]::Min(1500, $szczegol.Length)) }
  $script:Wynik += $linia
  Write-Host $linia
  if (-not $ok) { $script:Zle++ }
}

function Zapisz([string]$p, [string]$t) { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null; [System.IO.File]::WriteAllText($p, $t, $Utf8) }
function Czytaj([string]$p) { if (-not (Test-Path -LiteralPath $p)) { return $null }; return [System.IO.File]::ReadAllText($p, $Utf8) }
function Skrot([string]$p) { if (-not (Test-Path -LiteralPath $p)) { return "brak" }; return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }

# Dom z samym OpenCode: jego plik instrukcji (z sekcja "Co wiem" albo bez), logowanie do openrouter
# i poczekalnia z jednym zdaniem i jednym kawalkiem JSON-a zamiast zdania.
function Nowy-Dom([string]$nazwa, [string]$agents) {
  $dom = Join-Path $T "dom-$nazwa"
  if ($agents) { Zapisz (Join-Path $dom ".config\opencode\AGENTS.md") $agents }
  Zapisz (Join-Path $dom ".local\share\opencode\auth.json") '{"openrouter":{"type":"api","key":"nie-prawdziwy"}}'
  $kandydaci = "# Kandydaci do trwalej wiedzy`n`n" +
    "- [ ] [2026-10-06] Katalog testu cyklu lezy w ``$T``.`n" +
    "- [ ] [2026-10-06] {`"warstwa`": `"stala`", `"tresc`": `"Zdanie z JSON-a`"}`n"
  Zapisz (Join-Path $dom ".claude\wiedza\kandydaci.md") $kandydaci
  return $dom
}

$AGENTS = "# Zasady globalne (OpenCode)`n`n## Co wiem`n`n### O u${ZZ}ytkowniku`n`n_(pusto)_`n`n" +
  "### Nad czym pracuje`n`n_(pusto)_`n`n$BIEZACE`n`n_(pusto)_`n`n### Dane referencyjne`n`n_(pusto)_`n`n" +
  "<!-- MegaRuchacz:lore:start -->`n## Pami$([char]0x0119)$([char]0x0107) rozm$([char]0x00F3)w (Lore)`n`n- regula`n`n<!-- MegaRuchacz:lore:koniec -->`n"

# aktualizuj-wiedze.ps1 w osobnym procesie bez okna: dom testu jako USERPROFILE/HOME (Path.home()
# w Pythonie), LORE_HOME na jego .claude. PATH i LOCALAPPDATA zostaja - uv musi sie znalezc.
function Aktualizuj([string]$dom) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $skrypt = Join-Path $Zrodlo "narzedzia\aktualizuj-wiedze.ps1"
  $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$skrypt`" -Zrodlo `"$Zrodlo`" -BezWylawiania -KatalogDomowy `"$(Join-Path $dom '.claude')`""
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $Utf8
  $e = $psi.EnvironmentVariables
  $e["USERPROFILE"] = $dom; $e["HOME"] = $dom; $e["HOMEDRIVE"] = $dom.Substring(0, 2); $e["HOMEPATH"] = $dom.Substring(2)
  foreach ($k in @("CODEX_HOME", "LORE_HOME", "CLAUDE_CONFIG_DIR", "CLAUDE_HISTORIA_HOME", "LORE_MODEL_CLI")) { if ($e.ContainsKey($k)) { $e.Remove($k) } }
  $p = [System.Diagnostics.Process]::Start($psi)
  $bledy = $p.StandardError.ReadToEndAsync()
  $wy = $p.StandardOutput.ReadToEnd()
  $p.WaitForExit()
  return [pscustomobject]@{ Kod = $p.ExitCode; Tekst = ($wy + $bledy.Result) }
}

$staryPath = $env:PATH
try {
  New-Item -ItemType Directory -Force -Path $T | Out-Null

  # ------------------------------------------------------------ A. funkcje cyklu
  $bledyParsera = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Zrodlo "narzedzia\cykl-dzienny.ps1"), [ref]$null, [ref]$bledyParsera)
  Sprawdz "cykl-dzienny.ps1 parsuje sie bez bledow" ($bledyParsera.Count -eq 0) "$bledyParsera"
  $potrzebne = @("Znajdz-Narzedzia", "Adres-Opencode", "Jest-Zalogowany", "Znajdz-Przeszkode", "Rozpoznaj-Powod", "Ostrzezenie", "Jest-Siec")
  foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($potrzebne -contains $f.Name) { . ([scriptblock]::Create($f.Extent.Text)) }
  }

  $dom = Nowy-Dom "funkcje" $AGENTS
  $KatalogDomowy = $dom   # funkcje cyklu czytaja ten parametr skryptu
  $bin = Join-Path $T "bin"
  Zapisz (Join-Path $bin "opencode.cmd") "@echo off`r`necho opencode testowy`r`n"
  $env:PATH = "$bin;$Systemowe"
  $lista = Znajdz-Narzedzia
  Sprawdz "A: sam OpenCode w PATH - wykryty jako jedyne narzedzie" ((($lista | ForEach-Object { $_.Nazwa }) -join ",") -eq "OpenCode") (($lista | ForEach-Object { $_.Nazwa }) -join ",")
  Sprawdz "A: siec dla OpenCode sprawdzana u dostawcy z auth.json (openrouter.ai)" ($lista.Count -eq 1 -and $lista[0].Adres -eq "openrouter.ai") "$($lista[0].Adres)"
  Sprawdz "A: auth.json OpenCode = zalogowany" ((Jest-Zalogowany $lista[0]) -eq $true)
  Remove-Item -LiteralPath (Join-Path $dom ".local\share\opencode\auth.json")
  Sprawdz "A: bez auth.json - adres zapasowy models.dev i zalogowanie 'nie wiadomo' (nie blokuje)" (((Adres-Opencode) -eq "models.dev") -and ($null -eq (Jest-Zalogowany $lista[0])))

  $env:PATH = $Systemowe
  $lista = Znajdz-Narzedzia
  $przeszkoda = Znajdz-Przeszkode $lista
  Sprawdz "A (negatywna): bez zadnego narzedzia - przeszkoda wymienia opencode" (($lista.Count -eq 0) -and ($przeszkoda -match "opencode")) "$przeszkoda"
  $env:PATH = $staryPath

  $p = Rozpoznaj-Powod "UWAGA: no agent CLI in PATH - looked for ``claude``, ``codex``, ``opencode``, found none" 1
  Sprawdz "A (negatywna): 'no agent CLI' nie jest przypisany Claude Code" (($p -match "zadnego") -and ($p -notmatch "Claude Code")) $p
  $p = Rozpoznaj-Powod "LORE_MODEL_CLI=opencode, but no ``opencode`` in PATH (tools this knows: ``claude``, ``codex``, ``opencode``)" 1
  Sprawdz "A: wymuszony opencode, ktorego nie ma - komunikat mowi o opencode" ($p -match "polecenia opencode") $p
  $p = Rozpoznaj-Powod "LORE_MODEL_CLI=codex, but no ``codex`` in PATH (tools this knows: ``claude``, ``codex``, ``opencode``)" 1
  Sprawdz "A: wymuszony codex, ktorego nie ma - komunikat mowi o codex, nie o claude" ($p -match "polecenia codex") $p

  # ------------------------------------------------------------ B. sam OpenCode: fakt trafia do jego pliku
  $dom = Nowy-Dom "opencode" $AGENTS
  $plik = Join-Path $dom ".config\opencode\AGENTS.md"
  $w = Aktualizuj $dom
  $oc = Czytaj $plik
  Sprawdz "B: aktualizuj-wiedze kod 0" ($w.Kod -eq 0) $w.Tekst
  Sprawdz "B: fakt w ~\.config\opencode\AGENTS.md, w warstwie biezacej" ($oc -match [regex]::Escape("- [2026-10-06] Katalog testu cyklu lezy w ``$T``.")) $oc
  Sprawdz "B: kawalek JSON-a NIE wpisany do pliku OpenCode" ($oc -notmatch "Zdanie z JSON-a") $oc
  Sprawdz "B: CLAUDE.md i ~\.codex nie zalozone" ((-not (Test-Path (Join-Path $dom ".claude\CLAUDE.md"))) -and (-not (Test-Path (Join-Path $dom ".codex"))))
  Sprawdz "B: licznik surowej struktury w poczekalni pokazany jako UWAGA" ($w.Tekst -match "UWAGA\s+1 wpisow poczekalni to surowa struktura") $w.Tekst
  Sprawdz "B: 'obowiazujaca wiedza' wskazuje plik OpenCode, nie CLAUDE.md" (($w.Tekst -match [regex]::Escape("obowiazujaca wiedza : $plik")) -and ($w.Tekst -notmatch "obowiazujaca wiedza : .*CLAUDE\.md")) $w.Tekst
  $stan = Czytaj (Join-Path $dom ".claude\wiedza\.wiedza-stan.txt")
  Sprawdz "B: stan cyklu - surowa_struktura_odrzucona: 1, pliki: 1" (($stan -match "(?m)^surowa_struktura_odrzucona: 1\s*$") -and ($stan -match "(?m)^pliki: 1\s*$")) $stan

  # ------------------------------------------------------------ surowa struktura stojaca juz w pliku
  # Jak w domu do 02.10: kawalek JSON-a w biezacej warstwie pliku instrukcji - licznik na wierzchu.
  $dom = Nowy-Dom "w-plikach" ($AGENTS.Replace("$BIEZACE`n`n_(pusto)_", "$BIEZACE`n`n- [2026-10-01] {`"fakty`":[],`"uzyte`":[]}"))
  $w = Aktualizuj $dom
  Sprawdz "w plikach: kod 0 i UWAGA o surowej strukturze w plikach instrukcji" (($w.Kod -eq 0) -and ($w.Tekst -match "UWAGA\s+1 wpisow w plikach instrukcji to surowa struktura")) $w.Tekst
  Sprawdz "w plikach: stan cyklu - surowa_struktura_w_plikach: 1" ((Czytaj (Join-Path $dom ".claude\wiedza\.wiedza-stan.txt")) -match "(?m)^surowa_struktura_w_plikach: 1\s*$")

  # ------------------------------------------------------------ negatywna: plik OpenCode bez "## Co wiem"
  $bez = "# Zasady globalne (OpenCode)`n`nNic tu nie ma.`n"
  $dom = Nowy-Dom "bez-sekcji" $bez
  $plik = Join-Path $dom ".config\opencode\AGENTS.md"
  $przed = Skrot $plik
  $w = Aktualizuj $dom
  Sprawdz "bez sekcji: kod 0, plik OpenCode co do bajtu" (($w.Kod -eq 0) -and ((Skrot $plik) -eq $przed)) $w.Tekst
  Sprawdz "bez sekcji: przebieg mowi, ze w pliku OpenCode nie ma '## Co wiem' (nie cisza)" ($w.Tekst -match ("powod\s+:.*Co wiem.*" + [regex]::Escape($plik))) $w.Tekst
  Sprawdz "bez sekcji: fakt czeka w poczekalni" ((Czytaj (Join-Path $dom ".claude\wiedza\kandydaci.md")) -match "Katalog testu cyklu")

  # ------------------------------------------------------------ negatywna: zadnego pliku instrukcji
  $dom = Nowy-Dom "zadne" $null
  $w = Aktualizuj $dom
  Sprawdz "zadne: kod 0 i glosna UWAGA, ze wiedza nie ma gdzie wejsc" (($w.Kod -eq 0) -and ($w.Tekst -match "UWAGA\s+nie ma tu zadnego pliku instrukcji")) $w.Tekst
  Sprawdz "zadne: zaden plik instrukcji nie zalozony" ((-not (Test-Path (Join-Path $dom ".config\opencode\AGENTS.md"))) -and (-not (Test-Path (Join-Path $dom ".claude\CLAUDE.md"))))
} catch {
  Sprawdz "przebieg testu" $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)"
} finally {
  $env:PATH = $staryPath
  if (-not $Zostaw) {
    Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($T) -and $_.ProcessId -ne $PID } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    for ($i = 0; ($i -lt 15) -and (Test-Path -LiteralPath $T); $i++) {
      Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
      if (Test-Path -LiteralPath $T) { Start-Sleep -Seconds 1 }
    }
    if (Test-Path -LiteralPath $T) { Write-Host "UWAGA: nie udalo sie sprzatnac $T" }
  }
  else { Write-Host "kopia zostaje: $T" }
}

Write-Host ""
if ($script:Zle -gt 0) { Write-Host "NIE PRZESZLO: $($script:Zle) z $($script:Wynik.Count)"; exit 1 }
Write-Host "PRZESZLO: $($script:Wynik.Count) z $($script:Wynik.Count)"
exit 0
