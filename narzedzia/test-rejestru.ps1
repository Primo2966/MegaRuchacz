# Proba rejestru instalacji (P59a): dla kazdego rodzaju rejestru - brak pliku, wszystko, tylko wiedza,
# tylko lore, tylko kierownik, sama baza, plik wyzerowany - sprawdza bloki w CLAUDE.md i AGENTS.md
# Codeksa, kopie dla opencode, hooki w settings.json, start cyklu wiedzy i wyjscie przypomnienia.
# Do tego: straznik dwa razy z rzedu nic nie zmienia, migracja starego bloku na dwa z "Co wiem" co do
# bajtu, wylaczenie modulu zdejmuje jego blok i hook, wlaczenie przywraca, a rejestr nieczytelny
# (proba negatywna) nie zdejmuje niczego i daje alarm.
# Wszystko dzieje sie w kopii: katalogi domowe, projekt i katalog zrodlowy (bez .git - straznik nie
# siegnie do sieci ani do prawdziwego repo) w %TEMP%. Cykl wiedzy i kolejka faktow to w kopii zaslepki,
# ktore tylko zostawiaja slad - prawdziwy cykl nie rusza. Prawdziwe pliki nie sa ruszane.
#
# Uzycie:  powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File narzedzia\test-rejestru.ps1 [-Zostaw]
# (Skrypty modulow instalatora sprawdza osobno narzedzia\instalacja\test-moduly.ps1.)
# Kod wyjscia: 0 = wszystkie proby przeszly, 1 = ktoras nie.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Zostaw
)

$ErrorActionPreference = "Stop"
$T = Join-Path $env:TEMP ("mr-test-rejestru-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$Z = Join-Path $T "zrodlo"
$P = Join-Path $T "projekt"
$script:Wynik = @()
$script:Zle = 0
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$KCM = "<!-- MegaRuchacz:kierownik:start -->"

function Sprawdz([string]$co, [bool]$ok, [string]$szczegol = "") {
  $linia = $(if ($ok) { "OK    " } else { "BLAD  " }) + $co
  if (-not $ok -and $szczegol) { $linia += " -- $szczegol" }
  $script:Wynik += $linia
  Write-Host $linia
  if (-not $ok) { $script:Zle++ }
}

function Odpal([string]$skrypt, [string[]]$argumenty) {
  $ErrorActionPreference = "Continue"   # stderr skryptu to tresc do sprawdzenia, nie wyjatek
  $wy = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File $skrypt @argumenty 2>&1
  return [pscustomobject]@{ Kod = $LASTEXITCODE; Tekst = (($wy | ForEach-Object { "$_" }) -join "`n") }
}
function Straznik([string]$dom, [string[]]$dodatkowe = @()) {
  return (Odpal (Join-Path $Z "narzedzia\straznik-zasad.ps1") (@("-Zrodlo", $Z, "-Projekt", $P, "-KatalogDomowy", $dom) + $dodatkowe))
}
function Wpisz([string]$dom, [string[]]$dodatkowe = @()) {
  return (Odpal (Join-Path $Z "narzedzia\wpisz-zasady.ps1") (@("-Zrodlo", $Z, "-KatalogDomowy", $dom) + $dodatkowe))
}

function Czytaj([string]$p) { return [System.IO.File]::ReadAllText($p, $Utf8) }
function Zapisz([string]$p, [string]$t) { [System.IO.File]::WriteAllText($p, $t, $Utf8) }
function Skrot([string]$p) { if (-not (Test-Path -LiteralPath $p)) { return "brak" }; return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Ma-Zero([string]$p) { return ([Array]::IndexOf([System.IO.File]::ReadAllBytes($p), [byte]0) -ge 0) }
function Ile-Bak([string]$dom) { return @(Get-ChildItem -LiteralPath $dom -Recurse -File -Force -Filter "*.bak-*").Count }
function Ma([string]$tekst, [string]$co) { return ($tekst.IndexOf($co, [System.StringComparison]::Ordinal) -ge 0) }
function Przed-Znacznikiem([string]$tekst) {
  $i = $tekst.IndexOf("<!-- MegaRuchacz:", [System.StringComparison]::Ordinal)
  if ($i -lt 0) { return $tekst }
  return $tekst.Substring(0, $i)
}

# Nasze hooki w settings.json: "zdarzenie/rodzaj" (rodzaj jak Rodzaj-Hooka w strazniku) i cudze w calosci.
function Hooki([string]$plik) {
  $s = (Czytaj $plik) | ConvertFrom-Json
  $nasze = @(); $cudze = @()
  foreach ($z in @($s.hooks.PSObject.Properties | ForEach-Object { $_.Name })) {
    foreach ($g in @($s.hooks.$z)) {
      foreach ($h in @($g.hooks)) {
        $c = "$($h.command)"
        if ($c -match '[\\/]\.orca[\\/]') { $cudze += "$z|$c"; continue }
        if ($c -like "*straznik-zasad.ps1*") { $nasze += "$z/straznik" }
        elseif ($c -like "*orchestrator-reminder.json*") { $nasze += "$z/przypomnienie" }
        elseif ($c -match 'mr-log\.js') { $nasze += "$z/rejestr" }
        else { $cudze += "$z|$c" }
      }
    }
  }
  return [pscustomobject]@{ Nasze = @($nasze | Sort-Object); Cudze = @($cudze | Sort-Object) }
}

# Hook przypomnienia uruchomiony tak, jak robi to Claude Code: JSON na wejsciu, ladunek z wyjscia.
# Sciezki stanu i Lore przez zmienne srodowiskowe skryptu - zadnej zaleznosci od prawdziwego domu.
function Przypomnij([string]$dom, [string]$prompt = "Jak dziala robot do zamowien?") {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "node"
  $psi.Arguments = '"' + (Join-Path $Z "narzedzia\przypomnienie.js") + '" "' + (Join-Path $dom ".claude\mr\orchestrator-reminder.json") +
                   '" "' + (Join-Path $dom ".claude\wiedza\.cykl-postep") + '"'
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $Utf8
  $psi.EnvironmentVariables["MR_INSTALACJA"] = (Join-Path $dom ".claude\mr\instalacja.json")
  $psi.EnvironmentVariables["MR_INSTALACJA_ALARM"] = (Join-Path $dom ".claude\mr\.instalacja-alarm.json")
  $psi.EnvironmentVariables["MR_ARCHIWUM_STAN"] = (Join-Path $dom "archiwum-stan.json")
  $psi.EnvironmentVariables["MR_POWIADOMIENIA_STAN"] = (Join-Path $dom "powiadomienia-stan.json")
  $psi.EnvironmentVariables["MR_LORE_PYTHON"] = (Join-Path $dom "nie-ma-pythona.exe")
  $psi.EnvironmentVariables["LORE_HOME"] = (Join-Path $dom "bez-lore")
  $p = [System.Diagnostics.Process]::Start($psi)
  $p.StandardInput.Write('{"prompt":"' + $prompt + '","session_id":"test-sesja"}')
  $p.StandardInput.Close()
  $wy = $p.StandardOutput.ReadToEnd()
  [void]$p.StandardError.ReadToEnd()
  $p.WaitForExit()
  $kontekst = ""
  if ($wy.Trim()) { $kontekst = (($wy | ConvertFrom-Json).hookSpecificOutput.additionalContext) }
  return [pscustomobject]@{ Kod = $p.ExitCode; Wyjscie = $wy; Kontekst = "$kontekst" }
}

function Rejestr([string]$dom, $moduly) {
  $kat = Join-Path $dom ".claude\mr"
  New-Item -ItemType Directory -Force -Path $kat | Out-Null
  $p = Join-Path $kat "instalacja.json"
  if ($null -eq $moduly) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue; return }
  if ($moduly -is [string]) { Zapisz $p $moduly; return }
  if ($moduly -is [byte[]]) { [System.IO.File]::WriteAllBytes($p, $moduly); return }
  $j = [ordered]@{ wersja = 1; moduly = $moduly; kopia = $null; narzedzia = $null; data = "2026-10-02 10:00:00" }
  Zapisz $p ($j | ConvertTo-Json -Depth 4)
}

# ------------------------------------------------------------ katalog zrodlowy (kopia + zaslepki)
New-Item -ItemType Directory -Force -Path $Z, $P, (Join-Path $Z ".claude"), (Join-Path $Z "lore") | Out-Null
foreach ($k in @("narzedzia", "szablony-global", "szablony-opencode", "szablony-codex")) {
  Copy-Item -Recurse (Join-Path $Zrodlo $k) (Join-Path $Z $k)
}
foreach ($f in @("zasady-lore.md", "zasady-wiedza.md", "ZMIANY.md", ".claude\orchestrator-reminder.json")) {
  Copy-Item (Join-Path $Zrodlo $f) (Join-Path $Z $f)
}
# lore\pyproject.toml - straznik uznaje po nim, ze kod cyklu jest (Ruszaj-Cykl); sam cykl i kolejka to zaslepki
Zapisz (Join-Path $Z "lore\pyproject.toml") "[project]`r`nname = ""lore-zaslepka""`r`n"
Zapisz (Join-Path $Z "narzedzia\wyciagnij-fakty.ps1") ("param([string]`$Zrodlo, [switch]`$Kolejka)`r`n" +
  "Write-Output ""kolejka.kawalki: 3""`r`nWrite-Output ""kolejka.przebiegi: 1""`r`nexit 0`r`n")
Zapisz (Join-Path $Z "narzedzia\cykl-dzienny.ps1") ("param([string]`$Zrodlo, [string]`$KatalogDomowy)`r`n" +
  "`$w = Join-Path `$KatalogDomowy "".claude\wiedza""`r`n" +
  "[IO.File]::WriteAllText((Join-Path `$w "".cykl-stan""), ""data: "" + (Get-Date -Format yyyy-MM-dd) + ""``r``nstatus: ok``r``n"")`r`n" +
  "[IO.File]::WriteAllText((Join-Path `$w "".cykl-ruszyl-test""), (Get-Date -Format o))`r`n")

. (Join-Path $Z "narzedzia\kierownik-cele.ps1")
$kierClaude   = (Czytaj (Join-Path $Z "szablony-global\claude\zasady-kierownika.md")).Trim() -replace "`r`n", "`n"
$kierOpencode = (Czytaj (Join-Path $Z "szablony-opencode\zasady-kierownika.md")).Trim() -replace "`r`n", "`n"
$zrodloUkosniki = $Z.Replace("\", "/")

# Stan "sprzed P59a": stary wspolny blok MegaRuchacz:start pod "Co wiem", blok kierownika na koncu,
# kopia dla opencode, komplet czterech hookow plus cudze (Orka), cykl wczoraj, rachunek bez przeliczania.
# Nazwy stalych nie moga sie zderzyc z innymi zmiennymi - PowerShell nie rozroznia wielkosci liter
# (pierwsza wersja tego testu nadpisala "Co wiem" odciskiem plikow przez $przed / $PRZED).
$COWIEM = "# Ustalenia globalne`n`n## Co wiem`n`n### O użytkowniku`n`n- Pisze po polsku: zażółć gęślą jaźń.`n`n### Bieżące`n`n- [2026-10-01] Fakt testowy.`n`n"
# (bez cudzyslowow drukarskich: PowerShell bierze je za zwykle i rozcina nimi napis)
$STARY = "<!-- MegaRuchacz:start -->`n## Pamięć rozmów (Lore)`n`nStara treść Lore.`n`n## Wiedza (Co wiem)`n`nStara treść wiedzy.`n<!-- MegaRuchacz:koniec -->"
$BLOK_KIER = "$KCM`n$kierClaude`n<!-- MegaRuchacz:kierownik:koniec -->"
function Nowy-Dom([string]$nazwa, $moduly) {
  $dom = Join-Path $T "dom-$nazwa"
  $kc = Join-Path $dom ".claude"
  New-Item -ItemType Directory -Force -Path (Join-Path $kc "wiedza"), (Join-Path $kc "mr"), (Join-Path $dom ".codex"), (Join-Path $dom ".config\opencode") | Out-Null
  $cm = $COWIEM + $STARY + "`n`n" + $BLOK_KIER + "`n"
  Zapisz (Join-Path $kc "CLAUDE.md") $cm
  $ag = ($STARY + "`n`n" + "$KCM`n$kierOpencode`n<!-- MegaRuchacz:kierownik:koniec -->" + "`n") -replace "`n", "`r`n"
  Zapisz (Join-Path $dom ".codex\AGENTS.md") $ag
  Zapisz (Join-Path $dom ".config\opencode\AGENTS.md") (Kopia-Dla-Opencode $cm (Czytaj (Join-Path $Z "szablony-opencode\zasady-kierownika.md")))
  Zapisz (Join-Path $kc ".megaruchacz-global") "zrodlo: $Z`r`nwariant: claude`r`n"
  Zapisz (Join-Path $kc "history.jsonl") "{}`n"
  Copy-Item (Join-Path $Z ".claude\orchestrator-reminder.json") (Join-Path $kc "mr\orchestrator-reminder.json")
  Copy-Item (Join-Path $Z "szablony-global\claude\mr-log.js") (Join-Path $kc "megaruchacz-mr-log.js")
  $d = $kc.Replace("\", "/")
  $straz = 'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $zrodloUkosniki + '/narzedzia/straznik-zasad.ps1" -Zrodlo "' + $zrodloUkosniki + '" -Projekt "$CLAUDE_PROJECT_DIR" || true'
  $przyp = 'node "' + $zrodloUkosniki + '/narzedzia/przypomnienie.js" "' + $d + '/mr/orchestrator-reminder.json" || cat "' + $d + '/mr/orchestrator-reminder.json"'
  $s = [ordered]@{
    hooks = [ordered]@{
      SessionStart = @(
        [ordered]@{ hooks = @([ordered]@{ type = "command"; command = 'node "C:/Users/x/.orca/hooks/start.js"'; timeout = 5 }) },
        [ordered]@{ hooks = @([ordered]@{ type = "command"; command = $straz; shell = "bash"; timeout = 15; statusMessage = "MegaRuchacz: straznik zasad" }) })
      UserPromptSubmit = @([ordered]@{ hooks = @([ordered]@{ type = "command"; command = $przyp; shell = "bash"; timeout = 5 }) })
      SubagentStart = @([ordered]@{ hooks = @([ordered]@{ type = "command"; command = ('node "' + $d + '/megaruchacz-mr-log.js"'); timeout = 5; statusMessage = "MegaRuchacz: wpis do rejestru pracy" }) })
      SubagentStop = @([ordered]@{ hooks = @([ordered]@{ type = "command"; command = ('node "' + $d + '/megaruchacz-mr-log.js" stop'); timeout = 5; statusMessage = "MegaRuchacz: wpis do rejestru pracy" }) })
      PreToolUse = @([ordered]@{ matcher = "Bash"; hooks = @([ordered]@{ type = "command"; command = "echo cudzy-hook" }) })
    }
    theme = "dark"
  }
  Zapisz (Join-Path $kc "settings.json") ($s | ConvertTo-Json -Depth 10)
  $wczoraj = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
  Zapisz (Join-Path $kc "wiedza\.cykl-stan") "data: $wczoraj`r`nstatus: ok`r`n"
  Zapisz (Join-Path $kc ".megaruchacz-koszt.txt") ("proba: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`r`npelny: " + (Get-Date -Format 'yyyy-MM-dd') + "`r`n")
  Rejestr $dom $moduly
  return $dom
}

function Postep([string]$dom) {
  Zapisz (Join-Path $dom ".claude\wiedza\.cykl-postep") ("stan: pracuje`r`nczas: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "`r`nlinia: CYKL-TESTOWY czytam rozmowy`r`n")
}
function Czekaj-Na-Cykl([string]$dom, [int]$sekund) {
  $znacznik = Join-Path $dom ".claude\wiedza\.cykl-ruszyl-test"
  for ($i = 0; $i -lt ($sekund * 4); $i++) {
    if (Test-Path -LiteralPath $znacznik) { return $true }
    Start-Sleep -Milliseconds 250
  }
  return (Test-Path -LiteralPath $znacznik)
}

# Stan plikow, ktore straznik ma prawo zmienic - do proby "drugi przebieg nic nie zmienia".
function Odcisk([string]$dom) {
  return ((@("CLAUDE.md", "settings.json") | ForEach-Object { Skrot (Join-Path $dom ".claude\$_") }) +
          @((Skrot (Join-Path $dom ".codex\AGENTS.md")), (Skrot (Join-Path $dom ".config\opencode\AGENTS.md")))) -join ";"
}

# Sprawdzenie jednego domu wzgledem oczekiwan: co ma stac, a czego ma nie byc.
function Sprawdz-Dom([string]$co, [string]$dom, $ocz, [bool]$migracja) {
  $cm = Czytaj (Join-Path $dom ".claude\CLAUDE.md")
  $ag = Czytaj (Join-Path $dom ".codex\AGENTS.md")
  foreach ($n in @("lore", "wiedza")) {
    $jest = Ma $cm "<!-- MegaRuchacz:${n}:start -->"
    Sprawdz "${co}: blok $n w CLAUDE.md $(if ($ocz[$n]) { 'jest' } else { 'nie ma' })" ($jest -eq [bool]$ocz[$n])
    $jestA = Ma $ag "<!-- MegaRuchacz:${n}:start -->"
    Sprawdz "${co}: blok $n w AGENTS.md Codeksa $(if ($ocz[$n]) { 'jest' } else { 'nie ma' })" ($jestA -eq [bool]$ocz[$n])
  }
  Sprawdz "${co}: stary wspolny blok zniknal (CLAUDE.md i AGENTS.md)" ((-not (Ma $cm "<!-- MegaRuchacz:start -->")) -and (-not (Ma $ag "<!-- MegaRuchacz:start -->")))
  Sprawdz "${co}: blok kierownika $(if ($ocz.kierownik) { 'jest' } else { 'nie ma' }) (CLAUDE.md, AGENTS.md)" (((Ma $cm $KCM) -eq [bool]$ocz.kierownik) -and ((Ma $ag $KCM) -eq [bool]$ocz.kierownik))
  if ($ocz.kierownik) {
    Sprawdz "${co}: blok kierownika w CLAUDE.md co do bajtu" ($cm.EndsWith($BLOK_KIER + "`n")) ($cm.Substring([Math]::Max(0, $cm.Length - 200)))
  }
  if ($migracja) {
    if ($ocz.lore -or $ocz.wiedza -or $ocz.kierownik) {
      Sprawdz "${co}: 'Co wiem' (wszystko przed pierwszym blokiem) co do bajtu" ((Przed-Znacznikiem $cm) -ceq $COWIEM) (Przed-Znacznikiem $cm)
    } else {
      Sprawdz "${co}: zostalo samo 'Co wiem' (bez pustych linii na koncu)" ($cm -ceq ($COWIEM.TrimEnd("`n") + "`n")) $cm
    }
  }
  $oc = Join-Path $dom ".config\opencode\AGENTS.md"
  if ($ocz.kierownik) {
    $ok = (Test-Path -LiteralPath $oc) -and ((Czytaj $oc) -ceq (Kopia-Dla-Opencode $cm (Czytaj (Join-Path $Z "szablony-opencode\zasady-kierownika.md"))))
    Sprawdz "${co}: kopia dla opencode zgodna z CLAUDE.md (wariant opencode)" $ok
  } else {
    Sprawdz "${co}: kopii dla opencode nie ma (kierownik wylaczony)" (-not (Test-Path -LiteralPath $oc))
  }
  $h = Hooki (Join-Path $dom ".claude\settings.json")
  $chciane = @("SessionStart/straznik")
  if ($ocz.kierownik -or $ocz.lore -or $ocz.wiedza) { $chciane += "UserPromptSubmit/przypomnienie" }
  if ($ocz.kierownik) { $chciane += @("SubagentStart/rejestr", "SubagentStop/rejestr") }
  $chciane = @($chciane | Sort-Object)
  Sprawdz "${co}: hooki MegaRuchacza = $($chciane -join ', ')" ((($h.Nasze) -join ",") -eq ($chciane -join ",")) ($h.Nasze -join ",")
  Sprawdz "${co}: cudze hooki nietkniete" ((($h.Cudze) -join ",") -eq ('PreToolUse|echo cudzy-hook,SessionStart|node "C:/Users/x/.orca/hooks/start.js"')) ($h.Cudze -join ",")
  $zera = @(@((Join-Path $dom ".claude\CLAUDE.md"), (Join-Path $dom ".codex\AGENTS.md"), (Join-Path $dom ".claude\settings.json")) | Where-Object { Ma-Zero $_ })
  Sprawdz "${co}: zadnych bajtow 0x00" ($zera.Count -eq 0) ($zera -join ", ")
  Sprawdz "${co}: konce linii zachowane (CLAUDE.md LF, AGENTS.md CRLF)" ((-not $cm.Contains("`r")) -and (-not ($ag -replace "`r`n", "").Contains("`n")))
}

try {
  # ------------------------------------------------------------ macierz rejestrow
  $WSZYSTKO = [ordered]@{ wiedza = $true;  lore = $true;  kierownik = $true;  skille = $true;  kopia = $false }
  $macierz = @(
    @{ nazwa = "brak pliku";      rej = $null; ocz = @{ lore = $true;  wiedza = $true;  kierownik = $true  } },
    @{ nazwa = "wszystko";        rej = $WSZYSTKO;    ocz = @{ lore = $true;  wiedza = $true;  kierownik = $true  } },
    @{ nazwa = "tylko wiedza";    rej = [ordered]@{ wiedza = $true;  lore = $false; kierownik = $false; skille = $false; kopia = $false }; ocz = @{ lore = $false; wiedza = $true;  kierownik = $false } },
    @{ nazwa = "tylko lore";      rej = [ordered]@{ wiedza = $false; lore = $true;  kierownik = $false; skille = $false; kopia = $false }; ocz = @{ lore = $true;  wiedza = $false; kierownik = $false } },
    @{ nazwa = "tylko kierownik"; rej = [ordered]@{ wiedza = $false; lore = $false; kierownik = $true;  skille = $false; kopia = $false }; ocz = @{ lore = $false; wiedza = $false; kierownik = $true  } },
    @{ nazwa = "sama baza";       rej = [ordered]@{ wiedza = $false; lore = $false; kierownik = $false; skille = $false; kopia = $false }; ocz = @{ lore = $false; wiedza = $false; kierownik = $false } },
    @{ nazwa = "plik wyzerowany"; rej = (New-Object byte[] 64); ocz = @{ lore = $true;  wiedza = $true;  kierownik = $true  }; alarm = $true }
  )
  $domy = @{}
  foreach ($m in $macierz) {
    $n = $m.nazwa
    $dom = Nowy-Dom ($n -replace ' ', '-') $m.rej
    $domy[$n] = $dom
    $s = Straznik $dom
    Sprawdz "${n}: straznik konczy sie zerem" ($s.Kod -eq 0) $s.Tekst
    $alarm = ($s.Tekst -match "ALARM - nie umiem odczytac rejestru instalacji")
    Sprawdz "${n}: alarm o rejestrze $(if ($m.alarm) { 'jest' } else { 'go nie ma' })" ($alarm -eq [bool]$m.alarm) $s.Tekst
    Sprawdz "${n}: bez wywrotek i nieudanych napraw" (($s.Tekst -notmatch "wywrocil|nie wyszla|nie udalo sie") -and ((Czytaj (Join-Path $dom ".claude\.megaruchacz-straznik.txt")) -notmatch "blad\.\d")) $s.Tekst
    Sprawdz-Dom $n $dom $m.ocz $true

    # cykl wiedzy: zaslepka zostawia slad, gdy straznik ja wystartowal
    $ruszyl = Czekaj-Na-Cykl $dom $(if ($m.ocz.wiedza) { 15 } else { 2 })
    Sprawdz "${n}: cykl wiedzy $(if ($m.ocz.wiedza) { 'rusza' } else { 'nie rusza' })" ($ruszyl -eq [bool]$m.ocz.wiedza)

    # drugi przebieg: nic sie nie zmienia
    $odcisk1 = Odcisk $dom
    $bak = Ile-Bak $dom
    $s2 = Straznik $dom
    Sprawdz "${n}: drugi przebieg straznika nic nie zmienia" (((Odcisk $dom) -eq $odcisk1) -and ((Ile-Bak $dom) -eq $bak) -and
      ($s2.Tekst -notmatch "poprawione|uporzadkowane|zdjalem|wpisalem|dostal wlasna")) $s2.Tekst

    # przypomnienie
    Postep $dom
    $r = Przypomnij $dom
    Sprawdz "${n}: przypomnienie konczy sie zerem" ($r.Kod -eq 0) $r.Wyjscie
    Sprawdz "${n}: ladunek kierownika $(if ($m.ocz.kierownik) { 'jest' } else { 'go nie ma' })" ((Ma $r.Kontekst "TRYB MEGARUCHACZA") -eq [bool]$m.ocz.kierownik) $r.Kontekst
    Sprawdz "${n}: linia cyklu $(if ($m.ocz.wiedza) { 'jest' } else { 'jej nie ma' })" ((Ma $r.Kontekst "CYKL-TESTOWY") -eq [bool]$m.ocz.wiedza) $r.Kontekst
    $arch = Test-Path -LiteralPath (Join-Path $dom "archiwum-stan.json")
    Sprawdz "${n}: podpowiedz z archiwum $(if ($m.ocz.lore) { 'szukana' } else { 'nieruszana' })" ($arch -eq [bool]$m.ocz.lore)
    if (-not $m.ocz.wiedza) {
      Sprawdz "${n}: plik postepu cyklu nietkniety" (Test-Path -LiteralPath (Join-Path $dom ".claude\wiedza\.cykl-postep"))
    }
    if (-not ($m.ocz.kierownik -or $m.ocz.wiedza -or $m.ocz.lore)) {
      Sprawdz "${n}: przypomnienie nie wypisuje nic" (-not $r.Wyjscie.Trim()) $r.Wyjscie
    }
    $pierwsza = (($r.Kontekst -split "`n") | Select-Object -First 1)
    if ($m.alarm) {
      Sprawdz "${n}: przypomnienie - alarm o rejestrze w PIERWSZEJ linii" ($pierwsza -match "^UWAGA: nie umiem odczytac rejestru instalacji") $r.Kontekst
      $r2 = Przypomnij $dom
      Sprawdz "${n}: przypomnienie - alarm nie powtarza sie przy kazdej wiadomosci" (-not (Ma $r2.Kontekst "rejestru instalacji")) $r2.Kontekst
    } else {
      Sprawdz "${n}: przypomnienie bez alarmu o rejestrze" (-not (Ma $r.Kontekst "rejestru instalacji")) $r.Kontekst
    }
  }

  # ------------------------------------------------------------ wylaczanie i wlaczanie modulow na jednym domu
  $dom = $domy["wszystko"]
  Rejestr $dom ([ordered]@{ wiedza = $false; lore = $true; kierownik = $false; skille = $true; kopia = $false })
  $s = Straznik $dom
  Sprawdz "wylaczenie wiedzy i kierownika: straznik melduje zdjecie" (($s.Tekst -match "zdjety blok wiedza") -and ($s.Tekst -match "zdjalem blok zasad kierownika")) $s.Tekst
  Sprawdz-Dom "po wylaczeniu" $dom @{ lore = $true; wiedza = $false; kierownik = $false } $true
  Rejestr $dom $WSZYSTKO
  $s = Straznik $dom
  Sprawdz-Dom "po ponownym wlaczeniu" $dom @{ lore = $true; wiedza = $true; kierownik = $true } $true
  Sprawdz "po ponownym wlaczeniu: kolejnosc blokow lore, wiedza, kierownik" ((Czytaj (Join-Path $dom ".claude\CLAUDE.md")) -match "(?s)lore:start.*lore:koniec.*wiedza:start.*wiedza:koniec.*kierownik:start")
  $odcisk1 = Odcisk $dom
  $s2 = Straznik $dom
  Sprawdz "po ponownym wlaczeniu: drugi przebieg nic nie zmienia" ((Odcisk $dom) -eq $odcisk1) $s2.Tekst

  # ------------------------------------------------------------ proba negatywna: rejestr nieczytelny
  # Uciety JSON, ktory po "wyrozumialym" odczycie znaczylby "wszystko wylaczone" - nie wolno z niego
  # zdjac niczego, ma byc alarm.
  $odcisk1 = Odcisk $dom
  $bak = Ile-Bak $dom
  Rejestr $dom '{"wersja":1,"moduly":{"wiedza":false,"lore":false,"kierownik":false'
  $s = Straznik $dom
  Sprawdz "rejestr nieczytelny: alarm" ($s.Tekst -match "ALARM - nie umiem odczytac rejestru instalacji") $s.Tekst
  Sprawdz "rejestr nieczytelny: nic nie zdjete ani nie zmienione" (((Odcisk $dom) -eq $odcisk1) -and ((Ile-Bak $dom) -eq $bak)) $s.Tekst
  Sprawdz-Dom "rejestr nieczytelny" $dom @{ lore = $true; wiedza = $true; kierownik = $true } $true
  $w = Wpisz $dom
  Sprawdz "rejestr nieczytelny: wpisz-zasady ostrzega i nic nie zdejmuje" (($w.Kod -eq 0) -and ($w.Tekst -match "niczego nie zdejmuje") -and ((Odcisk $dom) -eq $odcisk1)) $w.Tekst
  $r = Przypomnij $dom
  Sprawdz "rejestr nieczytelny: przypomnienie z alarmem i pelne" (($r.Kontekst -match "^UWAGA: nie umiem odczytac rejestru instalacji") -and (Ma $r.Kontekst "TRYB MEGARUCHACZA")) $r.Kontekst

  # ------------------------------------------------------------ -Dopasuj (dla instalatora)
  $dom = Nowy-Dom "dopasuj" ([ordered]@{ wiedza = $true; lore = $false; kierownik = $false; skille = $false; kopia = $false })
  $d = Straznik $dom @("-Dopasuj")
  Sprawdz "-Dopasuj: kod 0" ($d.Kod -eq 0) $d.Tekst
  Sprawdz-Dom "-Dopasuj" $dom @{ lore = $false; wiedza = $true; kierownik = $false } $true
  $cm = Czytaj (Join-Path $dom ".claude\CLAUDE.md")
  Zapisz (Join-Path $dom ".claude\CLAUDE.md") ($cm + "`n<!-- MegaRuchacz:wiedza:start -->`n")
  $przedCm = Skrot (Join-Path $dom ".claude\CLAUDE.md")
  $d = Straznik $dom @("-Dopasuj")
  Sprawdz "-Dopasuj: zdublowany znacznik = kod 1 i plik nietkniety" (($d.Kod -eq 1) -and ((Skrot (Join-Path $dom ".claude\CLAUDE.md")) -eq $przedCm)) $d.Tekst

  # ------------------------------------------------------------ wpisz-zasady: -Blok i -Usun
  $dom = Nowy-Dom "wpisz" $null
  $plik = Join-Path $dom ".claude\CLAUDE.md"
  $w = Wpisz $dom @("-Usun", "-Blok", "lore")
  $cm = Czytaj $plik
  Sprawdz "wpisz -Usun -Blok lore na starym bloku: zostaje sam blok wiedza" (($w.Kod -eq 0) -and (Ma $cm "wiedza:start") -and -not (Ma $cm "lore:start") -and -not (Ma $cm "MegaRuchacz:start -->")) $w.Tekst
  Sprawdz "wpisz -Usun -Blok lore: 'Co wiem' i blok kierownika co do bajtu" (((Przed-Znacznikiem $cm) -ceq $COWIEM) -and $cm.EndsWith($BLOK_KIER + "`n"))
  $w = Wpisz $dom @("-Blok", "lore")
  $cm = Czytaj $plik
  Sprawdz "wpisz -Blok lore: lore wraca przed wiedze" (($w.Kod -eq 0) -and ($cm -match "(?s)lore:start.*lore:koniec.*wiedza:start")) $w.Tekst
  $przedCm = Skrot $plik
  $w = Wpisz $dom @("-Usun", "-Proba")
  Sprawdz "wpisz -Usun -Proba: plik nietkniety" (($w.Kod -eq 0) -and ((Skrot $plik) -eq $przedCm)) $w.Tekst
  $w = Wpisz $dom @("-Usun")
  $cm = Czytaj $plik
  Sprawdz "wpisz -Usun: oba bloki zdjete, kierownik zostaje" (($w.Kod -eq 0) -and -not (Ma $cm "lore:start") -and -not (Ma $cm "wiedza:start") -and (Ma $cm $KCM)) $w.Tekst
  $w = Wpisz $dom @("-Blok", "cos")
  Sprawdz "wpisz -Blok z nieznana nazwa: kod 1" ($w.Kod -eq 1) $w.Tekst

  # ------------------------------------------------------------ rachunek za pamiec rozumie nowe bloki
  $dom = $domy["brak pliku"]
  $k = Odpal (Join-Path $Z "narzedzia\koszt-pamieci.ps1") @("-KatalogDomowy", $dom, "-Zrodlo", $Z, "-Warstwy")
  $warstwy = $null
  try { $warstwy = $k.Tekst | ConvertFrom-Json } catch { $warstwy = $null }
  $idy = @()
  if ($warstwy) { $idy = @(@($warstwy.Warstwy) + @($warstwy) | ForEach-Object { $_.Id } | Where-Object { $_ }) }
  Sprawdz "koszt -Warstwy: bloki lore i wiedza jako osobne podwarstwy" (($idy -contains "claude-globalny-blok-lore") -and ($idy -contains "claude-globalny-blok-wiedza")) ($k.Tekst.Substring(0, [Math]::Min(400, $k.Tekst.Length)))
  Sprawdz "koszt -Warstwy: bez wiersza 'brak' starego bloku" (-not ($idy -contains "claude-globalny-blok"))
  $dom = $domy["tylko lore"]
  $k = Odpal (Join-Path $Z "narzedzia\koszt-pamieci.ps1") @("-KatalogDomowy", $dom, "-Zrodlo", $Z)
  Sprawdz "koszt przy kierowniku wylaczonym: ladunek przypomnienia nie liczony" ($k.Tekst -match "modul kierownik wylaczony w rejestrze instalacji") ($k.Tekst.Substring(0, [Math]::Min(600, $k.Tekst.Length)))

  # ------------------------------------------------------------ szybkosc przypomnienia
  $dom = $domy["wszystko"]
  Rejestr $dom $WSZYSTKO
  $czasy = @()
  for ($i = 0; $i -lt 15; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    [void](Przypomnij $dom)
    $sw.Stop()
    $czasy += $sw.ElapsedMilliseconds
  }
  $mediana = (@($czasy | Sort-Object))[7]
  Sprawdz "przypomnienie szybkie: mediana $mediana ms z 15 (prog 500 ms, hook ma 5 s)" ($mediana -lt 500) ($czasy -join ",")
} catch {
  Sprawdz "przebieg testu" $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)"
} finally {
  if (-not $Zostaw) {
    # po tescie nic z kopii nie zostaje w procesach (zaslepka cyklu, liczenie w tle)
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
