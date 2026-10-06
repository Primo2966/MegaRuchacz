# Proba listy narzedzi AI (kierownik-cele.ps1 Narzedzia-AI): zasady MegaRuchacza trafiaja do pliku
# instrukcji KAZDEGO narzedzia, ktore jest na maszynie - Claude Code (~\.claude\CLAUDE.md), Codex
# (~\.codex\AGENTS.md), OpenCode (~\.config\opencode\AGENTS.md) - w dowolnej kombinacji, i tylko tam.
# Kombinacje: tylko Codex, tylko OpenCode, wszystkie trzy, zadne. Do tego: OpenCode przy CLAUDE.md
# (opencode czyta wtedy tylko swoj plik - zasady ani zdublowane, ani zgubione), stara kopia CLAUDE.md
# dla opencode (do 0.27) zamieniona na samodzielny plik, wlasny plik opencode uzytkownika, istniejaca
# sekcja "Co wiem" nietknieta, instalator globalny, wtyczka opencode bez podwojnego ladowania.
# Proby negatywne: plik, ktory przekroczylby limit Codeksa (32 KiB) - odmowa zapisu z ostrzezeniem
# w PIERWSZEJ linii, plik co do bajtu, bez kopii (a ten sam plik ponizej limitu - zapisany).
#
# Wszystko w kopii w %TEMP%: katalogi domowe, projekt, katalog zrodlowy (bez .git). Procesy potomne
# dostaja PATH bez claude/codex/opencode (wykrywanie ma widziec tylko to, co test polozyl w domu)
# i dom testu jako USERPROFILE. Prawdziwe ~\.claude, ~\.codex i ~\.config\opencode nie sa ruszane.
#
# Uzycie:  powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File narzedzia\test-narzedzia-ai.ps1 [-Zostaw]
# Kod wyjscia: 0 = wszystkie proby przeszly, 1 = ktoras nie.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Zostaw
)

$ErrorActionPreference = "Stop"
$T = Join-Path $env:TEMP ("mr-test-narzedzia-ai-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$Z = Join-Path $T "zrodlo"
$P = Join-Path $T "projekt"
$script:Wynik = @()
$script:Zle = 0
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Systemowe = "$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\WindowsPowerShell\v1.0;$env:SystemRoot\System32\Wbem"
$KL = "<!-- MegaRuchacz:lore:start -->"; $KW = "<!-- MegaRuchacz:wiedza:start -->"; $KK = "<!-- MegaRuchacz:kierownik:start -->"
$KOPIA = "<!-- MegaRuchacz:kopia-dla-opencode"
$ZZ = [char]0x017C; $AA = [char]0x0105
$BIEZACE = "### Bie${ZZ}${AA}ce"

function Sprawdz([string]$co, [bool]$ok, [string]$szczegol = "") {
  $linia = $(if ($ok) { "OK    " } else { "BLAD  " }) + $co
  if (-not $ok -and $szczegol) { $linia += " -- " + $szczegol.Substring(0, [Math]::Min(1500, $szczegol.Length)) }
  $script:Wynik += $linia
  Write-Host $linia
  if (-not $ok) { $script:Zle++ }
}

# Proces potomny bez okna, z domem testu i PATH bez narzedzi AI.
function Odpal([string]$dom, [string]$skrypt, [string[]]$argumenty, [string]$path = $Systemowe) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $a = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $skrypt) + $argumenty
  $psi.Arguments = (($a | ForEach-Object { if ($_ -match '[\s"]' -or $_ -eq "") { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join " ")
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $Utf8
  $e = $psi.EnvironmentVariables
  $e["PATH"] = $path
  $e["USERPROFILE"] = $dom; $e["HOME"] = $dom; $e["HOMEDRIVE"] = $dom.Substring(0, 2); $e["HOMEPATH"] = $dom.Substring(2)
  $e["LOCALAPPDATA"] = (Join-Path $T "localappdata"); $e["APPDATA"] = (Join-Path $T "appdata")
  foreach ($k in @("CODEX_HOME", "LORE_HOME", "CLAUDE_CONFIG_DIR", "CLAUDE_HISTORIA_HOME")) { if ($e.ContainsKey($k)) { $e.Remove($k) } }
  $p = [System.Diagnostics.Process]::Start($psi)
  $bledy = $p.StandardError.ReadToEndAsync()
  $wy = $p.StandardOutput.ReadToEnd()
  $p.WaitForExit()
  return [pscustomobject]@{ Kod = $p.ExitCode; Tekst = ($wy + $bledy.Result) }
}
function Wpisz([string]$dom, [string[]]$dod = @()) { return (Odpal $dom (Join-Path $Z "narzedzia\wpisz-zasady.ps1") (@("-Zrodlo", $Z, "-KatalogDomowy", $dom) + $dod)) }
function Dopasuj([string]$dom) { return (Odpal $dom (Join-Path $Z "narzedzia\straznik-zasad.ps1") @("-Dopasuj", "-Zrodlo", $Z, "-Projekt", $P, "-KatalogDomowy", $dom)) }

function Czytaj([string]$p) { if (-not (Test-Path -LiteralPath $p)) { return $null }; return [System.IO.File]::ReadAllText($p, $Utf8) }
function Zapisz([string]$p, [string]$t) { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null; [System.IO.File]::WriteAllText($p, $t, $Utf8) }
function Skrot([string]$p) { if (-not (Test-Path -LiteralPath $p)) { return "brak" }; return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Ile([string]$t, [string]$co) { if ($null -eq $t) { return 0 }; return ([regex]::Matches($t, [regex]::Escape($co))).Count }
function Ile-Bak([string]$dom) { return @(Get-ChildItem -LiteralPath $dom -Recurse -File -Force -Filter "*.bak-*").Count }
function Pierwsza([string]$t) { return (($t -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1) }
function Odcisk([string]$dom) { return (@(".claude\CLAUDE.md", ".codex\AGENTS.md", ".config\opencode\AGENTS.md") | ForEach-Object { Skrot (Join-Path $dom $_) }) -join ";" }

$WSZYSTKO = '{"wersja":1,"moduly":{"wiedza":true,"lore":true,"kierownik":true,"skille":false,"kopia":false},"kopia":null,"narzedzia":null,"data":"2026-10-06 10:00:00"}'
# Dom testu: rejestr instalacji (lezy w .claude\mr - sam katalog .claude NIE jest sladem Claude Code)
# i slady wybranych narzedzi: claude = .claude.json, codex = .codex, opencode = .config\opencode.
function Nowy-Dom([string]$nazwa, [string[]]$narzedzia) {
  $dom = Join-Path $T "dom-$nazwa"
  Zapisz (Join-Path $dom ".claude\mr\instalacja.json") $WSZYSTKO
  if ($narzedzia -contains "claude") { Zapisz (Join-Path $dom ".claude.json") "{}" }
  if ($narzedzia -contains "codex") { New-Item -ItemType Directory -Force -Path (Join-Path $dom ".codex") | Out-Null }
  if ($narzedzia -contains "opencode") { New-Item -ItemType Directory -Force -Path (Join-Path $dom ".config\opencode") | Out-Null }
  return $dom
}

# Plik narzedzia po pelnej instalacji zasad: kazdy blok dokladnie raz, wlasciwy wariant kierownika,
# "Co wiem" dokladnie raz i NAD pierwszym blokiem (granica sekcji w verify.py).
$NaglClaude = $null; $NaglOc = $null
function Sprawdz-Plik([string]$co, [string]$tekst, [string]$wariant) {
  $ok = ($null -ne $tekst) -and ((Ile $tekst $KL) -eq 1) -and ((Ile $tekst $KW) -eq 1) -and ((Ile $tekst $KK) -eq 1)
  Sprawdz "${co}: bloki lore, wiedza, kierownik - kazdy dokladnie raz" $ok "lore $(Ile $tekst $KL), wiedza $(Ile $tekst $KW), kierownik $(Ile $tekst $KK)"
  if (-not $tekst) { return }
  $chciany = if ($wariant -eq "claude") { $NaglClaude } else { $NaglOc }
  $inny = if ($wariant -eq "claude") { $NaglOc } else { $NaglClaude }
  Sprawdz "${co}: blok kierownika w wariancie $wariant (i bez drugiego wariantu)" ($tekst.Contains($chciany) -and -not $tekst.Contains($inny))
  $iCw = $tekst.IndexOf("## Co wiem"); $iZn = $tekst.IndexOf("<!-- MegaRuchacz:")
  Sprawdz "${co}: '## Co wiem' raz, nad pierwszym blokiem, z podsekcja Biezace" (((Ile $tekst "## Co wiem") -eq 1) -and ($iCw -ge 0) -and ($iCw -lt $iZn) -and $tekst.Contains($BIEZACE)) "Co wiem $iCw, znacznik $iZn"
  Sprawdz "${co}: bez naglowka starej kopii dla opencode" (-not $tekst.Contains($KOPIA))
}

# Pelny przebieg jak u uzytkownika: wpisz-zasady (po zmianie rejestru), straznik -Dopasuj (blok kierownika),
# potem drugi -Dopasuj, ktory nie ma prawa nic zmienic.
function Zainstaluj([string]$co, [string]$dom) {
  $w = Wpisz $dom
  Sprawdz "${co}: wpisz-zasady kod 0" ($w.Kod -eq 0) $w.Tekst
  $d = Dopasuj $dom
  Sprawdz "${co}: straznik -Dopasuj kod 0" ($d.Kod -eq 0) $d.Tekst
  $odc = Odcisk $dom; $bak = Ile-Bak $dom
  $d2 = Dopasuj $dom
  $w2 = Wpisz $dom
  Sprawdz "${co}: drugi -Dopasuj i drugie wpisz-zasady nic nie zmieniaja" (($d2.Kod -eq 0) -and ($w2.Kod -eq 0) -and ((Odcisk $dom) -eq $odc) -and ((Ile-Bak $dom) -eq $bak)) ($d2.Tekst + " | " + $w2.Tekst)
  return [pscustomobject]@{ Wpisz = $w; Dopasuj = $d }
}

try {
  # ------------------------------------------------------------ katalog zrodlowy (kopia, bez .git)
  New-Item -ItemType Directory -Force -Path $Z, $P, (Join-Path $Z ".claude"), (Join-Path $Z "lore") | Out-Null
  foreach ($k in @("narzedzia", "szablony-global", "szablony-opencode", "szablony-codex")) { Copy-Item -Recurse (Join-Path $Zrodlo $k) (Join-Path $Z $k) }
  foreach ($f in @("zasady-lore.md", "zasady-wiedza.md", "ZMIANY.md", ".claude\orchestrator-reminder.json")) { Copy-Item (Join-Path $Zrodlo $f) (Join-Path $Z $f) }
  $NaglClaude = ((Czytaj (Join-Path $Z "szablony-global\claude\zasady-kierownika.md")).Trim() -split "`r?`n")[0]
  $NaglOc = ((Czytaj (Join-Path $Z "szablony-opencode\zasady-kierownika.md")).Trim() -split "`r?`n")[0]
  Sprawdz "przygotowanie: naglowki wariantow kierownika rozne" ($NaglClaude -and $NaglOc -and ($NaglClaude -ne $NaglOc)) "$NaglClaude | $NaglOc"

  # ------------------------------------------------------------ lista narzedzi: jeden wpis = jedno narzedzie
  . (Join-Path $Z "narzedzia\kierownik-cele.ps1")
  $lista = @(Narzedzia-AI)
  Sprawdz "lista: claude, codex, opencode - plik, polecenie, slady, wariant, limit" ((($lista | ForEach-Object { $_.Id }) -join ",") -eq "claude,codex,opencode" -and
    (@($lista | Where-Object { $_.Plik -and $_.Polecenie -and $_.Slady -and $_.Wariant -and ($null -ne $_.Limit) }).Count -eq 3) -and ((Narzedzie-AI "codex").Limit -eq 32768))

  # ------------------------------------------------------------ tylko Codex
  $dom = Nowy-Dom "codex" @("codex")
  [void](Zainstaluj "tylko Codex" $dom)
  Sprawdz-Plik "tylko Codex - ~/.codex/AGENTS.md" (Czytaj (Join-Path $dom ".codex\AGENTS.md")) "opencode"
  Sprawdz "tylko Codex: CLAUDE.md i plik OpenCode NIE zalozone" ((-not (Test-Path (Join-Path $dom ".claude\CLAUDE.md"))) -and (-not (Test-Path (Join-Path $dom ".config\opencode"))))

  # ------------------------------------------------------------ tylko OpenCode
  $dom = Nowy-Dom "opencode" @("opencode")
  [void](Zainstaluj "tylko OpenCode" $dom)
  Sprawdz-Plik "tylko OpenCode - ~/.config/opencode/AGENTS.md" (Czytaj (Join-Path $dom ".config\opencode\AGENTS.md")) "opencode"
  Sprawdz "tylko OpenCode: CLAUDE.md i AGENTS.md Codeksa NIE zalozone" ((-not (Test-Path (Join-Path $dom ".claude\CLAUDE.md"))) -and (-not (Test-Path (Join-Path $dom ".codex"))))

  # ------------------------------------------------------------ wszystkie trzy (CLAUDE.md uzytkownika)
  # OpenCode bez wlasnego pliku czytal dotad CLAUDE.md - jego plik ma zaczac sie od tej tresci (notatka
  # i fakt z "Co wiem" nie gina), z blokiem kierownika w SWOIM wariancie i bez dubli.
  $dom = Nowy-Dom "trzy" @("claude", "codex", "opencode")
  $notatka = "Notatka uzytkownika: zazolc gesla jazn."
  $fakt = "- [2026-10-05] Fakt testowy z CLAUDE.md."
  Zapisz (Join-Path $dom ".claude\CLAUDE.md") ("# Ustalenia globalne`n`n$notatka`n`n## Co wiem`n`n$BIEZACE`n`n$fakt`n")
  [void](Zainstaluj "wszystkie trzy" $dom)
  $cm = Czytaj (Join-Path $dom ".claude\CLAUDE.md")
  $cx = Czytaj (Join-Path $dom ".codex\AGENTS.md")
  $oc = Czytaj (Join-Path $dom ".config\opencode\AGENTS.md")
  Sprawdz-Plik "wszystkie trzy - CLAUDE.md" $cm "claude"
  Sprawdz-Plik "wszystkie trzy - AGENTS.md Codeksa" $cx "opencode"
  Sprawdz-Plik "wszystkie trzy - AGENTS.md OpenCode" $oc "opencode"
  Sprawdz "wszystkie trzy: CLAUDE.md - notatka i fakt na miejscu" ($cm.Contains($notatka) -and $cm.Contains($fakt))
  Sprawdz "wszystkie trzy: OpenCode (czyta TYLKO swoj plik) ma notatke i fakt z CLAUDE.md - nic nie zgubione" ($oc.Contains($notatka) -and $oc.Contains($fakt)) $oc
  Sprawdz "wszystkie trzy: OpenCode - notatka i fakt po jednym razie (nic zdublowane)" (((Ile $oc $notatka) -eq 1) -and ((Ile $oc $fakt) -eq 1))
  Sprawdz "wszystkie trzy: Codex dostal pusty szkielet, a nie cudzy fakt" (-not $cx.Contains($fakt))

  # ------------------------------------------------------------ zadne
  $dom = Nowy-Dom "zadne" @()
  $w = Wpisz $dom
  Sprawdz "zadne: wpisz-zasady kod 0 i glosna UWAGA (nie cisza)" (($w.Kod -eq 0) -and ($w.Tekst -match "UWAGA\s+nie widze tu zadnego narzedzia AI")) $w.Tekst
  $d = Dopasuj $dom
  Sprawdz "zadne: straznik -Dopasuj kod 0" ($d.Kod -eq 0) $d.Tekst
  Sprawdz "zadne: zaden plik instrukcji nie zalozony" ((Odcisk $dom) -eq "brak;brak;brak") (Odcisk $dom)

  # ------------------------------------------------------------ stara kopia CLAUDE.md dla opencode (do 0.27)
  $dom = Nowy-Dom "kopia" @("claude", "opencode")
  [void](Zainstaluj "stara kopia - przygotowanie" $dom)
  $cm = Czytaj (Join-Path $dom ".claude\CLAUDE.md")
  $kopia = "$KOPIA - plik zaklada i odswieza MegaRuchacz (narzedzia\straznik-zasad.ps1): kopia. Nie edytuj. -->`n`n" + (Z-Blokiem-Kierownika $cm (Czytaj (Join-Path $Z "szablony-opencode\zasady-kierownika.md")))
  Zapisz (Join-Path $dom ".config\opencode\AGENTS.md") $kopia
  $d = Dopasuj $dom
  $oc = Czytaj (Join-Path $dom ".config\opencode\AGENTS.md")
  Sprawdz "stara kopia: straznik -Dopasuj kod 0 i melduje zamiane na samodzielny plik" (($d.Kod -eq 0) -and ($d.Tekst -match "stara kopia")) $d.Tekst
  Sprawdz "stara kopia: zostala tresc bez linii naglowka, co do bajtu" ($oc -ceq ($kopia.Substring($kopia.IndexOf("`n`n") + 2))) $oc.Substring(0, [Math]::Min(300, $oc.Length))
  Sprawdz-Plik "stara kopia - po zamianie" $oc "opencode"

  # ------------------------------------------------------------ wlasny plik opencode uzytkownika
  # Do 0.27 nie ruszany - opencode nie dostawal wtedy zadnych zasad. Teraz jak AGENTS.md Codeksa:
  # tresc uzytkownika zostaje, bloki i szkielet dochodza.
  $dom = Nowy-Dom "wlasny-oc" @("opencode")
  $wlasny = "# Moje zasady opencode`n`nOdpowiadaj krotko.`n"
  Zapisz (Join-Path $dom ".config\opencode\AGENTS.md") $wlasny
  [void](Zainstaluj "wlasny plik opencode" $dom)
  $oc = Czytaj (Join-Path $dom ".config\opencode\AGENTS.md")
  Sprawdz-Plik "wlasny plik opencode" $oc "opencode"
  Sprawdz "wlasny plik opencode: tresc uzytkownika na poczatku, co do bajtu" ($oc.StartsWith($wlasny.TrimEnd("`n"))) $oc.Substring(0, [Math]::Min(200, $oc.Length))

  # ------------------------------------------------------------ istniejaca sekcja "Co wiem" nietknieta
  # Jak w domu 06.10: sekcja PO bloku kierownika, z wpisami. Drugiej nie zakladamy, wpisy zostaja.
  $dom = Nowy-Dom "cowiem" @("codex")
  [void](Zainstaluj "Co wiem - przygotowanie" $dom)
  $cx = Czytaj (Join-Path $dom ".codex\AGENTS.md")
  $i = $cx.IndexOf("## Co wiem"); $j = $cx.IndexOf("<!-- MegaRuchacz:")
  $wpisy = "## Co wiem`r`n`r`n$BIEZACE`r`n`r`n- [2026-10-01] Wpis domowy pierwszy.`r`n- [2026-10-02] Wpis domowy drugi.`r`n"
  $cxPo = $cx.Substring(0, $i) + $cx.Substring($j)
  $cxPo = $cxPo.TrimEnd("`r", "`n") + "`r`n`r`n" + $wpisy
  Zapisz (Join-Path $dom ".codex\AGENTS.md") $cxPo
  $przed = Skrot (Join-Path $dom ".codex\AGENTS.md")
  $w = Wpisz $dom; $d = Dopasuj $dom
  Sprawdz "Co wiem za blokami: wpisz-zasady i straznik nie zmieniaja pliku (sekcja jest, nic do dolozenia)" (($w.Kod -eq 0) -and ($d.Kod -eq 0) -and ((Skrot (Join-Path $dom ".codex\AGENTS.md")) -eq $przed)) ($w.Tekst + " | " + $d.Tekst)

  # ------------------------------------------------------------ proba negatywna: sufit Codeksa
  # AGENTS.md uzytkownika ~31 KiB bez naszych blokow: z blokami przekroczylby 32 KiB, a Codex wczytuje
  # tylko poczatek - koniec pliku (nasze zasady) przepadlby po cichu. Odmowa, plik co do bajtu.
  $dom = Nowy-Dom "sufit" @("codex")
  $duzy = "# Moje zasady Codeksa`r`n`r`n" + ((1..560 | ForEach-Object { "- linia uzytkownika do wypelnienia pliku, numer {0:D5}`r`n" -f $_ }) -join "")
  Zapisz (Join-Path $dom ".codex\AGENTS.md") $duzy
  $ileB = (Get-Item (Join-Path $dom ".codex\AGENTS.md")).Length
  Sprawdz "sufit: plik testowy ponizej 32 KiB, a z blokami ponad" (($ileB -lt 32768) -and ($ileB -gt 26000)) "$ileB B"
  $przed = Skrot (Join-Path $dom ".codex\AGENTS.md"); $bak = Ile-Bak $dom
  $w = Wpisz $dom
  Sprawdz "sufit: wpisz-zasady kod 1" ($w.Kod -eq 1) $w.Tekst
  Sprawdz "sufit: ostrzezenie w PIERWSZEJ linii wyjscia (odmowa zapisu, limit, plik)" ((Pierwsza $w.Tekst) -match "^BLAD\s+ODMOWA ZAPISU \(Codex\):.*32768 B.*NIE zapisalem") (Pierwsza $w.Tekst)
  Sprawdz "sufit: plik co do bajtu, bez kopii .bak (zadnego kadluba)" (((Skrot (Join-Path $dom ".codex\AGENTS.md")) -eq $przed) -and ((Ile-Bak $dom) -eq $bak))
  $d = Dopasuj $dom
  Sprawdz "sufit: straznik -Dopasuj kod 1, UWAGA z odmowa w PIERWSZEJ linii" (($d.Kod -eq 1) -and ((Pierwsza $d.Tekst) -match "^MegaRuchacz: UWAGA - ODMOWA ZAPISU \(Codex\)")) $d.Tekst
  Sprawdz "sufit: straznik nie dopisal bloku kierownika ponad limit (UWAGA, plik co do bajtu)" (($d.Tekst -match "brakuje bloku zasad kierownika i NIE wpisalem go") -and ((Skrot (Join-Path $dom ".codex\AGENTS.md")) -eq $przed) -and ((Ile-Bak $dom) -eq $bak)) $d.Tekst
  # ta sama sciezka ponizej limitu przechodzi - to sufit blokuje, nie cos innego
  $maly = "# Moje zasady Codeksa`r`n`r`n" + ((1..200 | ForEach-Object { "- linia uzytkownika do wypelnienia pliku, numer {0:D5}`r`n" -f $_ }) -join "")
  Zapisz (Join-Path $dom ".codex\AGENTS.md") $maly
  [void](Zainstaluj "sufit - plik ponizej limitu" $dom)
  $cx = Czytaj (Join-Path $dom ".codex\AGENTS.md")
  Sprawdz-Plik "sufit - plik ponizej limitu" $cx "opencode"
  Sprawdz "sufit - plik ponizej limitu: po zapisie nadal ponizej 32 KiB" ((Get-Item (Join-Path $dom ".codex\AGENTS.md")).Length -le 32768)

  # ------------------------------------------------------------ instalator globalny: opencode i wszystkie trzy
  foreach ($k in @(@{ n = "oc"; t = @("opencode") }, @{ n = "trzy"; t = @("claude", "codex", "opencode") })) {
    $dom = Nowy-Dom "glob-$($k.n)" $k.t
    $g = Odpal $dom (Join-Path $Z "narzedzia\instaluj-globalnie.ps1") @("-BezPytania", "-Zrodlo", $Z, "-KatalogDomowy", $dom)
    Sprawdz "instaluj-globalnie ($($k.t -join ', ')): kod 0, samosprawdzenie bez bledow" (($g.Kod -eq 0) -and ($g.Tekst -notmatch "(?m)^\s*BLAD")) $g.Tekst
    $oc = Czytaj (Join-Path $dom ".config\opencode\AGENTS.md")
    Sprawdz "instaluj-globalnie ($($k.t -join ', ')): OpenCode - jeden blok kierownika w wariancie opencode" (((Ile $oc $KK) -eq 1) -and $oc.Contains($NaglOc) -and -not $oc.Contains($NaglClaude))
    $cm = Czytaj (Join-Path $dom ".claude\CLAUDE.md")
    if ($k.t -contains "claude") { Sprawdz "instaluj-globalnie (trzy): CLAUDE.md - jeden blok w wariancie claude" (((Ile $cm $KK) -eq 1) -and $cm.Contains($NaglClaude)) }
    else { Sprawdz "instaluj-globalnie (tylko opencode): w CLAUDE.md zadnego bloku kierownika" ((Ile $cm $KK) -eq 0) }
  }

  # ------------------------------------------------------------ wtyczka opencode: bez podwojnego ladowania
  # config doklada .megaruchacz/zasady-kierownika.md tylko wtedy, gdy zasad nie ma ani w AGENTS.md
  # projektu, ani w globalnym pliku, ktory opencode czyta.
  $proj = Join-Path $T "projekt-oc"
  Zapisz (Join-Path $proj ".megaruchacz\zasady-kierownika.md") "# zasady"
  $wtyczka = (Join-Path $Z "szablony-opencode\plugins\mr-log.js").Replace("\", "/")
  $js = "import('file:///$wtyczka').then(async (m) => { const h = await m.MrLog({ directory: process.argv[1] }); const cfg = {}; await h.config(cfg); console.log(JSON.stringify(cfg.instructions || [])) })"
  $domW = Join-Path $T "dom-wtyczka"
  New-Item -ItemType Directory -Force -Path $domW | Out-Null
  $wyniki = @{}
  foreach ($stan in @("brak", "globalny", "claude")) {
    if ($stan -eq "globalny") { Zapisz (Join-Path $domW ".config\opencode\AGENTS.md") "x`n$KK`ny`n<!-- MegaRuchacz:kierownik:koniec -->`n" }
    if ($stan -eq "claude") { Remove-Item -LiteralPath (Join-Path $domW ".config\opencode\AGENTS.md"); Zapisz (Join-Path $domW ".claude\CLAUDE.md") "x`n$KK`ny`n<!-- MegaRuchacz:kierownik:koniec -->`n" }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Command node -CommandType Application | Select-Object -First 1).Source
    $psi.Arguments = '-e "' + $js.Replace('"', '\"') + '" "' + $proj + '"'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables["USERPROFILE"] = $domW; $psi.EnvironmentVariables["HOME"] = $domW
    $pr = [System.Diagnostics.Process]::Start($psi); $o = $pr.StandardOutput.ReadToEnd(); $er = $pr.StandardError.ReadToEnd(); $pr.WaitForExit()
    $wyniki[$stan] = ($o + $er).Trim()
  }
  Sprawdz "wtyczka: bez zasad w plikach globalnych doklada .megaruchacz/zasady-kierownika.md" ($wyniki["brak"] -match "zasady-kierownika\.md") $wyniki["brak"]
  Sprawdz "wtyczka: blok kierownika w ~/.config/opencode/AGENTS.md - nic nie doklada" ($wyniki["globalny"] -eq "[]") $wyniki["globalny"]
  Sprawdz "wtyczka: bez pliku opencode, blok w ~/.claude/CLAUDE.md - nic nie doklada" ($wyniki["claude"] -eq "[]") $wyniki["claude"]
} catch {
  Sprawdz "przebieg testu" $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)"
} finally {
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
