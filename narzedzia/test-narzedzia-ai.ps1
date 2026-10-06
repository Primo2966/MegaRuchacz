# Proba listy narzedzi AI (kierownik-cele.ps1 Narzedzia-AI): zasady MegaRuchacza trafiaja do pliku
# instrukcji KAZDEGO narzedzia, ktore jest na maszynie - Claude Code (~\.claude\CLAUDE.md), Codex
# (~\.codex\AGENTS.md), OpenCode (~\.config\opencode\AGENTS.md) - w dowolnej kombinacji, i tylko tam.
# Kombinacje: tylko Codex, tylko OpenCode, wszystkie trzy, zadne. Do tego: OpenCode przy CLAUDE.md
# (opencode czyta wtedy tylko swoj plik - zasady ani zdublowane, ani zgubione), stara kopia CLAUDE.md
# dla opencode (do 0.27) zamieniona na samodzielny plik, wlasny plik opencode uzytkownika, istniejaca
# sekcja "Co wiem" nietknieta, instalator globalny, wtyczka opencode bez podwojnego ladowania.
# Ta sama wiedza w kazdym CLI: pusta "Co wiem" (zakladana i zastana) zasiana trescia najbogatszej
# sekcji, niepusta nietknieta przez zasiew; synchronizacja (Synchronizuj-Co-Wiem): zmiana w jednym
# pliku idzie do pozostalych (w obie strony), dopisy w kilku plikach polaczone na swoich miejscach,
# ta sama linia zmieniona inaczej - wygrywa nowszy plik bez zadnego meldunku (slad w stanie i .bak),
# skasowanie w nowszym pliku znika wszedzie, -WzorCoWiem jako narzedzie reczne, pierwsza
# synchronizacja bez stanu - same dopisy; Pliki-Pamieci
# (zapis-trwaly.ps1) z listy narzedzi - takze czwartego.
# Codex od 06.10 bez limitu (globalny AGENTS.md czyta w calosci - dowod w kierownik-cele.ps1): plik ponad
# 32 KiB jest zapisywany. Sufit sprawdzamy na NARZEDZIU TESTOWYM Z LIMITEM - kopia zrodla ($ZL), w ktorej
# Codex ma Limit = 32768 (tak, jak do 06.10).
# Proby negatywne: starszy plik nie wygrywa z nowszym (ani poprawka, ani skasowaniem); plik, ktory
# przekroczylby limit narzedzia - odmowa zapisu z ostrzezeniem
# w PIERWSZEJ linii, plik co do bajtu, bez kopii (a ten sam plik ponizej limitu - zapisany); zasiew
# "Co wiem" ponad limit - odmowa w PIERWSZEJ linii, sekcja pusta, reszta pliku zapisana (a mniejszy
# zasiew - przechodzi); synchronizacja ponad limit - odmowa w PIERWSZEJ linii przy kazdym
# przebiegu, plik co do bajtu, pozostale pliki zsynchronizowane, zalegly plik niczego nie kasuje.
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
# Zrodlo, z ktorego ida wpisz-zasady i straznik: $Z, a w probach sufitu $ZL (Codex z limitem 32 KiB).
$script:ZT = $Z
function Wpisz([string]$dom, [string[]]$dod = @()) { return (Odpal $dom (Join-Path $script:ZT "narzedzia\wpisz-zasady.ps1") (@("-Zrodlo", $script:ZT, "-KatalogDomowy", $dom) + $dod)) }
function Dopasuj([string]$dom) { return (Odpal $dom (Join-Path $script:ZT "narzedzia\straznik-zasad.ps1") @("-Dopasuj", "-Zrodlo", $script:ZT, "-Projekt", $P, "-KatalogDomowy", $dom)) }

function Czytaj([string]$p) { if (-not (Test-Path -LiteralPath $p)) { return $null }; return [System.IO.File]::ReadAllText($p, $Utf8) }
function Zapisz([string]$p, [string]$t) { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null; [System.IO.File]::WriteAllText($p, $t, $Utf8) }
function Skrot([string]$p) { if (-not (Test-Path -LiteralPath $p)) { return "brak" }; return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Ile([string]$t, [string]$co) { if ($null -eq $t) { return 0 }; return ([regex]::Matches($t, [regex]::Escape($co))).Count }
# Czas zapisu pliku cofniety o $minut minut - ktory plik jest "nowszy" przy synchronizacji "Co wiem".
function Wiek([string]$p, [int]$minut) { [System.IO.File]::SetLastWriteTimeUtc($p, [DateTime]::UtcNow.AddMinutes(-$minut)) }
function Ile-Bak([string]$dom) { return @(Get-ChildItem -LiteralPath $dom -Recurse -File -Force -Filter "*.bak-*").Count }
function Pierwsza([string]$t) { return (($t -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1) }
# Sekcja "Co wiem" jako niepuste linie (porownanie tresci) i plik z wycietym cialem sekcji (reszta pliku
# co do znaku) - granice z kierownik-cele.ps1, dolaczonego nizej.
function Linie-Sekcji([string]$t) { $c = Cialo-Co-Wiem $t; return (@($c) | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join "|" }
function Poza-Sekcja([string]$t) {
  $l = @($t -split "`r?`n"); $g = Granice-Co-Wiem $l
  return ((@($l | Select-Object -First ($g[0] + 1)) + @("@@ sekcja @@") + @($l | Select-Object -Skip $g[1])) -join "`n")
}
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
  # narzedzie testowe z limitem: ta sama kopia zrodla, a Codex z Limit = 32768 - do prob sufitu
  $ZL = Join-Path $T "zrodlo-sufit"
  Copy-Item -Recurse $Z $ZL
  $kcL = Join-Path $ZL "narzedzia\kierownik-cele.ps1"
  $kcT = Czytaj $kcL
  $kcT2 = $kcT.Replace('Wariant = "opencode"; Limit = 0;     Zapas = $null', 'Wariant = "opencode"; Limit = 32768; Zapas = $null')
  if ($kcT2 -ceq $kcT) { throw "narzedzie testowe z limitem: kotwica wpisu Codeksa w kierownik-cele.ps1 sie zmienila" }
  Zapisz $kcL $kcT2

  # ------------------------------------------------------------ lista narzedzi: jeden wpis = jedno narzedzie
  . (Join-Path $Z "narzedzia\kierownik-cele.ps1")
  $lista = @(Narzedzia-AI)
  Sprawdz "lista: claude, codex, opencode - plik, polecenie, slady, wariant, limit" ((($lista | ForEach-Object { $_.Id }) -join ",") -eq "claude,codex,opencode" -and
    (@($lista | Where-Object { $_.Plik -and $_.Polecenie -and $_.Slady -and $_.Wariant -and ($null -ne $_.Limit) }).Count -eq 3) -and ((Narzedzie-AI "codex").Limit -eq 0))
  Sprawdz "lista: katalogi skilli w kolejnosci wczytywania (claude .claude, codex .agents, opencode .claude/.agents/.config\opencode)" (
    ((@((Narzedzie-AI "claude").Skille) -join ";") -eq ".claude\skills") -and ((@((Narzedzie-AI "codex").Skille) -join ";") -eq ".agents\skills") -and
    ((@((Narzedzie-AI "opencode").Skille) -join ";") -eq ".claude\skills;.agents\skills;.config\opencode\skills"))

  # ------------------------------------------------------------ wykrywanie: rejestr instalacji
  # narzedzia.<id> = true w ~\.claude\mr\instalacja.json (wybor w instalatorze) = narzedzie jest, takze bez
  # sladow; false i brak sladow = nie ma; rejestr nieczytelny = RejestrBlad (wolajacy mowi), bez wywrotki.
  # PATH bez prawdziwych CLI - wykrywanie ma widziec tylko dom testu.
  $domRej = Join-Path $T "dom-rejestr"
  $pathTestu = $env:PATH
  try {
    $env:PATH = $Systemowe
    Zapisz (Join-Path $domRej ".claude\mr\instalacja.json") '{"wersja":1,"moduly":{"wiedza":true},"narzedzia":{"claude":false,"codex":true,"opencode":false}}'
    $wy = Wykryj-Narzedzia-AI $domRej   # oddaje tablice przecinkiem - bez @()
    $wc = $wy | Where-Object { $_.Id -eq "codex" }; $wo = $wy | Where-Object { $_.Id -eq "opencode" }
    Sprawdz "rejestr: codex = true bez sladow - Codex jest (dowod: rejestr instalacji), z katalogami skilli; opencode = false - nie ma" ($wc.Jest -and ($wc.Dowod -eq "rejestr instalacji") -and ((@($wc.Skille) -join ";") -eq ".agents\skills") -and -not $wo.Jest -and -not $wc.RejestrBlad) (($wy | ForEach-Object { "$($_.Id)=$($_.Jest)/$($_.Dowod)" }) -join ", ")
    Zapisz (Join-Path $domRej ".claude\mr\instalacja.json") '{"wersja":1,"moduly":{"wiedza":true},"narzedzia":{"claude":false,"codex":false,"opencode":false}}'
    Sprawdz "rejestr: PROBA NEGATYWNA - codex = false i brak sladow - zadnego narzedzia" (@(Cele-Narzedzi $domRej).Count -eq 0)
    Zapisz (Join-Path $domRej ".claude\mr\instalacja.json") "{ to nie jest json"
    $wy = Wykryj-Narzedzia-AI $domRej
    Sprawdz "rejestr: nieczytelny - RejestrBlad w kazdym wpisie, narzedzia tylko po sladach (tu zadne)" ((@($wy | Where-Object { $_.RejestrBlad -match "rejestr instalacji .* nieczytelny" }).Count -eq 3) -and (@($wy | Where-Object { $_.Jest }).Count -eq 0))
  } finally { $env:PATH = $pathTestu }

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
  Sprawdz "wszystkie trzy: Codex dostal 'Co wiem' z CLAUDE.md (fakt raz), a nie tekst spoza sekcji" (((Ile $cx $fakt) -eq 1) -and -not $cx.Contains($notatka)) $cx
  $w = Wpisz $dom
  Sprawdz "wszystkie trzy: ta sama wiedza wszedzie - bez meldunku o rozjezdzie ani synchronizacji" ($w.Tekst -notmatch "nie jest ta sama|sprzeczne|zsynchronizowana") $w.Tekst

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

  # ------------------------------------------------------------ Codex bez sufitu
  # AGENTS.md uzytkownika ~31 KiB bez naszych blokow: z blokami ponad 32 KiB - Codex czyta globalny plik
  # w calosci, wiec zapis idzie (kod 0, bloki na koncu), bez zadnej odmowy.
  $dom = Nowy-Dom "bez-sufitu" @("codex")
  $duzy = "# Moje zasady Codeksa`r`n`r`n" + ((1..560 | ForEach-Object { "- linia uzytkownika do wypelnienia pliku, numer {0:D5}`r`n" -f $_ }) -join "")
  Zapisz (Join-Path $dom ".codex\AGENTS.md") $duzy
  $w = Wpisz $dom; $d = Dopasuj $dom
  $cx = Czytaj (Join-Path $dom ".codex\AGENTS.md")
  Sprawdz "bez sufitu: Codex - wpisz-zasady i straznik kod 0, plik ponad 32 KiB zapisany, bez ODMOWY" (($w.Kod -eq 0) -and ($d.Kod -eq 0) -and (($w.Tekst + $d.Tekst) -notmatch "ODMOWA|NIE wpisalem") -and ($Utf8.GetByteCount($cx) -gt 32768) -and $cx.StartsWith($duzy)) "$($Utf8.GetByteCount($cx)) B | $($w.Tekst) | $($d.Tekst)"
  Sprawdz-Plik "bez sufitu - Codex ponad 32 KiB" $cx "opencode"

  # ------------------------------------------------------------ proba negatywna: sufit (narzedzie testowe z limitem)
  # Codex z Limit = 32768 ($ZL). AGENTS.md uzytkownika ~31 KiB bez naszych blokow: z blokami przekroczylby
  # limit, a narzedzie wczytuje tylko poczatek - koniec pliku (nasze zasady) przepadlby po cichu. Odmowa,
  # plik co do bajtu.
  $script:ZT = $ZL
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
  $script:ZT = $Z

  # ------------------------------------------------------------ ta sama wiedza: zastany pusty szkielet
  # Jak na biurowej 06.10: AGENTS.md Codeksa z samym szkieletem, CLAUDE.md z pelna wiedza. Straznik przy
  # starcie okna (sam -Dopasuj) zasiewa sekcje Codeksa trescia z CLAUDE.md; reszta pliku co do znaku.
  $wiedzaCm = ("## Co wiem`r`n`r`n### O u${ZZ}ytkowniku`r`n`r`n- Sprzedaje na Amazonie i eBayu.`r`n`r`n### O firmie`r`n`r`n" +
               "- Marka testowa, zapachy z numerami.`r`n`r`n$BIEZACE`r`n`r`n- [2026-10-05] Fakt biezacy z CLAUDE.md.`r`n`r`n" +
               "### Dane referencyjne`r`n`r`n- wiedza/test.md - odsylacz.`r`n")
  $dom = Nowy-Dom "zasiew" @("codex")
  [void](Zainstaluj "zasiew - przygotowanie (Codex z pustym szkieletem)" $dom)
  $pCx = Join-Path $dom ".codex\AGENTS.md"; $pCm = Join-Path $dom ".claude\CLAUDE.md"
  $cx0 = Czytaj $pCx
  Sprawdz "zasiew: przygotowanie - Codex ma pusty szkielet 'Co wiem'" (Pusta-Co-Wiem $cx0)
  Zapisz (Join-Path $dom ".claude.json") "{}"
  Zapisz $pCm ("# Ustalenia globalne`r`n`r`n" + $wiedzaCm)
  $d = Dopasuj $dom
  $cx = Czytaj $pCx; $cm = Czytaj $pCm
  Sprawdz "zasiew: straznik -Dopasuj kod 0, melduje pusta sekcje i zasiew" (($d.Kod -eq 0) -and ($d.Tekst -match "pusta sekcja 'Co wiem'") -and ($d.Tekst -match "poprawione")) $d.Tekst
  Sprawdz "zasiew: sekcja Codeksa = sekcja CLAUDE.md (linia w linie)" ((-not (Pusta-Co-Wiem $cx)) -and ((Linie-Sekcji $cx) -ceq (Linie-Sekcji $cm))) $cx
  Sprawdz "zasiew: reszta pliku Codeksa (nad sekcja i bloki pod nia) co do znaku" ((Poza-Sekcja $cx) -ceq (Poza-Sekcja $cx0))
  Sprawdz-Plik "zasiew - Codex po zasiewie" $cx "opencode"
  $odc = Odcisk $dom; $bak = Ile-Bak $dom
  $d2 = Dopasuj $dom; $w2 = Wpisz $dom
  Sprawdz "zasiew: drugi straznik i wpisz-zasady nic nie zmieniaja, bez meldunku o rozjezdzie" (($d2.Kod -eq 0) -and ($w2.Kod -eq 0) -and ((Odcisk $dom) -eq $odc) -and ((Ile-Bak $dom) -eq $bak) -and ($d2.Tekst + $w2.Tekst) -notmatch "nie jest ta sama") ($d2.Tekst + " | " + $w2.Tekst)

  # ------------------------------------------------------------ synchronizacja: zmiana w jednym pliku
  # Agent w rozmowie poprawia "Co wiem" we WLASNYM pliku (dopis w O firmie, poprawka w Biezace). Straznik
  # przy starcie okna (tu -Dopasuj) przenosi sekcje do pozostalych plikow: kopia .bak przed zapisem, reszta
  # plikow co do znaku, jedna linia meldunku; drugi przebieg nic nie zmienia i o "Co wiem" milczy.
  $dom = Nowy-Dom "sync" @("claude", "codex", "opencode")
  $pCx = Join-Path $dom ".codex\AGENTS.md"; $pCm = Join-Path $dom ".claude\CLAUDE.md"; $pOc = Join-Path $dom ".config\opencode\AGENTS.md"
  Zapisz $pCm ("# Ustalenia globalne`r`n`r`n" + $wiedzaCm)
  [void](Zainstaluj "synchronizacja - przygotowanie" $dom)
  Sprawdz "synchronizacja: przygotowanie - trzy pliki z ta sama wiedza" (((Linie-Sekcji (Czytaj $pCx)) -ceq (Linie-Sekcji (Czytaj $pCm))) -and ((Linie-Sekcji (Czytaj $pOc)) -ceq (Linie-Sekcji (Czytaj $pCm))))
  $cx0 = Czytaj $pCx; $oc0 = Czytaj $pOc; $bak = Ile-Bak $dom
  Zapisz $pCm ((Czytaj $pCm).Replace("- Marka testowa, zapachy z numerami.", "- Marka testowa, zapachy z numerami.`r`n- Dopis w CLAUDE.md.").Replace("- [2026-10-05] Fakt biezacy z CLAUDE.md.", "- [2026-10-05] Fakt biezacy z CLAUDE.md, poprawiony."))
  $przedCm = Skrot $pCm
  $d = Dopasuj $dom
  $cm = Czytaj $pCm; $cx = Czytaj $pCx; $oc = Czytaj $pOc
  Sprawdz "jeden plik: straznik kod 0, jedna linia: zsynchronizowana, skad i dokad" (($d.Kod -eq 0) -and ($d.Tekst -match "sekcja 'Co wiem' zsynchronizowana \(zmiany z ~/\.claude/CLAUDE\.md\), zapisana w: ~/\.codex/AGENTS\.md, ~/\.config/opencode/AGENTS\.md")) $d.Tekst
  Sprawdz "jeden plik: Codex i OpenCode maja sekcje CLAUDE.md (linia w linie, z dopisem i poprawka)" (((Linie-Sekcji $cx) -ceq (Linie-Sekcji $cm)) -and ((Linie-Sekcji $oc) -ceq (Linie-Sekcji $cm)) -and $cx.Contains("- Dopis w CLAUDE.md.") -and $oc.Contains("poprawiony.") -and -not $cx.Contains("z CLAUDE.md.`r`n")) $cx
  Sprawdz "jeden plik: CLAUDE.md nietkniety" ((Skrot $pCm) -eq $przedCm)
  Sprawdz "jeden plik: reszta plikow Codeksa i OpenCode co do znaku" (((Poza-Sekcja $cx) -ceq (Poza-Sekcja $cx0)) -and ((Poza-Sekcja $oc) -ceq (Poza-Sekcja $oc0)))
  Sprawdz "jeden plik: kopia .bak przed zapisem kazdego z dwoch plikow" ((Ile-Bak $dom) -eq ($bak + 2)) "$(Ile-Bak $dom) zamiast $($bak + 2)"
  $odc = Odcisk $dom; $bak = Ile-Bak $dom
  $d2 = Dopasuj $dom; $w2 = Wpisz $dom
  Sprawdz "jeden plik: drugi przebieg nic nie zmienia i o 'Co wiem' milczy" (($d2.Kod -eq 0) -and ($w2.Kod -eq 0) -and ((Odcisk $dom) -eq $odc) -and ((Ile-Bak $dom) -eq $bak) -and (($d2.Tekst + $w2.Tekst) -notmatch "zsynchronizowana|sprzeczne|nie jest ta sama")) ($d2.Tekst + " | " + $w2.Tekst)
  # w druga strone: agent Codeksa poprawia linie - CLAUDE.md i OpenCode dostaja poprawke, stara wersja znika
  Zapisz $pCx ((Czytaj $pCx).Replace("- Sprzedaje na Amazonie i eBayu.", "- Sprzedaje na Amazonie i eBayu (glownie DE)."))
  $d = Dopasuj $dom
  $cm = Czytaj $pCm; $oc = Czytaj $pOc; $cx = Czytaj $pCx
  Sprawdz "w druga strone: poprawka z Codeksa w CLAUDE.md i OpenCode, starej wersji nie ma" (($d.Kod -eq 0) -and ($d.Tekst -match "zmiany z ~/\.codex/AGENTS\.md") -and $cm.Contains("(glownie DE).") -and -not $cm.Contains("eBayu.`r`n") -and ((Linie-Sekcji $oc) -ceq (Linie-Sekcji $cx)) -and ((Linie-Sekcji $cm) -ceq (Linie-Sekcji $cx))) $d.Tekst

  # ------------------------------------------------------------ synchronizacja: dopisy w kilku plikach
  # Trzy CLI dopisuja rozne linie: CLAUDE.md w "O firmie", Codex i OpenCode w tym samym miejscu "Biezace".
  # Wszystkie wchodza do kazdego pliku, kazda raz i w swojej podsekcji.
  $fCm = "- Dopis A w CLAUDE.md do firmy."; $fCx = "- [2026-10-06] Dopis B w Codeksie."; $fOc = "- [2026-10-06] Dopis C w OpenCode."
  Zapisz $pCm ((Czytaj $pCm).Replace("- Dopis w CLAUDE.md.", "- Dopis w CLAUDE.md.`r`n$fCm"))
  Zapisz $pCx ((Czytaj $pCx).Replace("- [2026-10-05] Fakt biezacy z CLAUDE.md, poprawiony.", "- [2026-10-05] Fakt biezacy z CLAUDE.md, poprawiony.`r`n$fCx"))
  Zapisz $pOc ((Czytaj $pOc).Replace("- [2026-10-05] Fakt biezacy z CLAUDE.md, poprawiony.", "- [2026-10-05] Fakt biezacy z CLAUDE.md, poprawiony.`r`n$fOc"))
  $d = Dopasuj $dom
  $cm = Czytaj $pCm; $cx = Czytaj $pCx; $oc = Czytaj $pOc
  Sprawdz "dopisy: straznik kod 0, zmiany z trzech plikow" (($d.Kod -eq 0) -and ($d.Tekst -match "zmiany z ~/\.claude/CLAUDE\.md, ~/\.codex/AGENTS\.md, ~/\.config/opencode/AGENTS\.md")) $d.Tekst
  Sprawdz "dopisy: wszystkie trzy pliki z ta sama sekcja" (((Linie-Sekcji $cx) -ceq (Linie-Sekcji $cm)) -and ((Linie-Sekcji $oc) -ceq (Linie-Sekcji $cm))) $cm
  Sprawdz "dopisy: kazdy dopis dokladnie raz" (((Ile $cm $fCm) -eq 1) -and ((Ile $cm $fCx) -eq 1) -and ((Ile $cm $fOc) -eq 1)) $cm
  $iF = $cm.IndexOf("### O firmie"); $iB = $cm.IndexOf($BIEZACE); $iD = $cm.IndexOf("### Dane referencyjne")
  Sprawdz "dopisy: kazdy w swojej podsekcji (A w O firmie, B i C w Biezace, B przed C)" (($cm.IndexOf($fCm) -gt $iF) -and ($cm.IndexOf($fCm) -lt $iB) -and ($cm.IndexOf($fCx) -gt $iB) -and ($cm.IndexOf($fOc) -gt $cm.IndexOf($fCx)) -and ($cm.IndexOf($fOc) -lt $iD)) $cm

  # ------------------------------------------------------------ synchronizacja: ta sama linia zmieniona inaczej - NOWSZY WYGRYWA
  # Decyzja uzytkownika 06.10: w pelni automatycznie, bez meldunku o konflikcie. Nowszy = plik z pozniejszym
  # czasem zapisu (czasy ustawiamy recznie). Dopis z trzeciego pliku wchodzi obok; wersja przegrana zostaje
  # w kopii .bak i w stanie (nadpisane); drugi przebieg nic nie zmienia.
  $linia = "- Marka testowa, zapachy z numerami."
  $pStan = Join-Path $dom ".claude\mr\co-wiem-sync.json"
  $fOc2 = "- [2026-10-06] Dopis w OpenCode obok roznych wersji."
  Zapisz $pCm ((Czytaj $pCm).Replace($linia, "- Marka testowa AROMA, zapachy z numerami.")); Wiek $pCm 10
  Zapisz $pCx ((Czytaj $pCx).Replace($linia, "- Marka testowa NATURO, zapachy z numerami.")); Wiek $pCx 2
  Zapisz $pOc ((Czytaj $pOc).Replace($fOc, "$fOc`r`n$fOc2")); Wiek $pOc 5
  $bak = Ile-Bak $dom
  $d = Dopasuj $dom
  $cm = Czytaj $pCm; $cx = Czytaj $pCx; $oc = Czytaj $pOc
  Sprawdz "nowszy wygrywa: straznik kod 0, zsynchronizowana, ZADNEGO meldunku o konflikcie" (($d.Kod -eq 0) -and ($d.Tekst -match "zsynchronizowana") -and ($d.Tekst -notmatch "UWAGA|sprzeczn|konflikt|WzorCoWiem|nadpisan|wygral")) $d.Tekst
  Sprawdz "nowszy wygrywa: wersja z nowszego Codeksa (NATURO) we wszystkich trzech, starszej (AROMA) nigdzie" (((Linie-Sekcji $cx) -ceq (Linie-Sekcji $cm)) -and ((Linie-Sekcji $oc) -ceq (Linie-Sekcji $cm)) -and $cm.Contains("testowa NATURO") -and $oc.Contains("testowa NATURO") -and -not ($cm + $cx + $oc).Contains("AROMA")) $cm
  Sprawdz "nowszy wygrywa: dopis z OpenCode wszedzie, dokladnie raz" (((Ile $cm $fOc2) -eq 1) -and ((Ile $cx $fOc2) -eq 1)) $cm
  $bakCm = @(Get-ChildItem -LiteralPath (Split-Path -Parent $pCm) -Filter "CLAUDE.md.bak-*" | Sort-Object Name | Select-Object -Last 1)
  Sprawdz "nowszy wygrywa: przegrana wersja (AROMA) w kopii .bak CLAUDE.md przed zapisem" (((Ile-Bak $dom) -gt $bak) -and ($bakCm.Count -eq 1) -and (Czytaj $bakCm[0].FullName).Contains("testowa AROMA")) "$(Ile-Bak $dom) kopii"
  $st = Czytaj $pStan
  Sprawdz "nowszy wygrywa: slad w stanie (nadpisane: kto wygral, co nadpisano)" ($st -match '"nadpisane"' -and $st.Contains("wygral nowszy ~/.codex/AGENTS.md") -and $st.Contains("testowa NATURO") -and $st.Contains("testowa AROMA")) $st
  $odc = Odcisk $dom; $bak = Ile-Bak $dom
  $d2 = Dopasuj $dom
  Sprawdz "nowszy wygrywa: drugi przebieg nic nie zmienia i o 'Co wiem' milczy" (($d2.Kod -eq 0) -and ((Odcisk $dom) -eq $odc) -and ((Ile-Bak $dom) -eq $bak) -and ($d2.Tekst -notmatch "Co wiem|zsynchronizowana")) $d2.Tekst
  # proba negatywna: STARSZY nie wygrywa - teraz starszy jest Codex, a nowszy CLAUDE.md (pierwszy na liscie
  # i ostatni zapisany przez test jest Codex - wygrac ma i tak czas pliku, nie kolejnosc); przebieg reczny
  # (wpisz-zasady) mowi o tym zwyklym INFO, nie UWAGA
  Zapisz $pCm ((Czytaj $pCm).Replace("testowa NATURO", "testowa ZAPACH")); Wiek $pCm 1
  Zapisz $pCx ((Czytaj $pCx).Replace("testowa NATURO", "testowa ROSE")); Wiek $pCx 10
  $w = Wpisz $dom
  $cm = Czytaj $pCm; $cx = Czytaj $pCx; $oc = Czytaj $pOc
  Sprawdz "starszy nie wygrywa: ZAPACH (nowszy CLAUDE.md) wszedzie, ROSE (starszy Codex) nigdzie" (($w.Kod -eq 0) -and $cx.Contains("testowa ZAPACH") -and $oc.Contains("testowa ZAPACH") -and -not ($cm + $cx + $oc).Contains("ROSE") -and ((Linie-Sekcji $cx) -ceq (Linie-Sekcji $cm))) ($w.Tekst + " | " + $cx)
  Sprawdz "starszy nie wygrywa: wpisz-zasady - INFO o nowszym pliku, bez UWAGA o 'Co wiem'" (($w.Tekst -match "INFO\s+Co wiem - nowszy plik wygral: .*ZAPACH.*ROSE") -and ($w.Tekst -notmatch "UWAGA\s+(Co wiem|sekcja 'Co wiem')")) $w.Tekst

  # ------------------------------------------------------------ synchronizacja: skasowanie w nowszym pliku
  # Wpis skasowany w nowszym pliku znika ze wszystkich - takze gdy starszy go w tym czasie poprawil; wpis
  # skasowany w jednym pliku, a nietkniety w innych - tez znika.
  Zapisz $pOc ((Czytaj $pOc).Replace("- Dopis w CLAUDE.md.`r`n", "")); Wiek $pOc 1
  Zapisz $pCm ((Czytaj $pCm).Replace("- Dopis w CLAUDE.md.", "- Dopis w CLAUDE.md, poprawiony w starszym.")); Wiek $pCm 10
  Zapisz $pCx ((Czytaj $pCx).Replace("$fCx`r`n", "")); Wiek $pCx 5
  $d = Dopasuj $dom
  $cm = Czytaj $pCm; $cx = Czytaj $pCx; $oc = Czytaj $pOc
  Sprawdz "skasowanie: straznik kod 0, bez meldunku o konflikcie" (($d.Kod -eq 0) -and ($d.Tekst -notmatch "UWAGA|sprzeczn|konflikt")) $d.Tekst
  Sprawdz "skasowanie w nowszym (OpenCode) wygrywa z poprawka w starszym (CLAUDE.md) - linii nie ma nigdzie" ((-not ($cm + $cx + $oc).Contains("- Dopis w CLAUDE.md")) -and ((Linie-Sekcji $cx) -ceq (Linie-Sekcji $cm)) -and ((Linie-Sekcji $oc) -ceq (Linie-Sekcji $cm))) $cm
  Sprawdz "skasowanie w jednym pliku (Codex) znika z pozostalych" (-not ($cm + $oc).Contains($fCx)) $cm
  # proba negatywna: skasowanie w STARSZYM nie wygrywa z poprawka w nowszym
  Zapisz $pCm ((Czytaj $pCm).Replace("$fCm`r`n", "")); Wiek $pCm 10
  $fCmPopr = "- Dopis A w CLAUDE.md do firmy, poprawiony w Codeksie."
  Zapisz $pCx ((Czytaj $pCx).Replace($fCm, $fCmPopr)); Wiek $pCx 1
  $d = Dopasuj $dom
  $cm = Czytaj $pCm; $cx = Czytaj $pCx; $oc = Czytaj $pOc
  Sprawdz "skasowanie w starszym (CLAUDE.md) nie wygrywa z poprawka w nowszym (Codex) - poprawka wszedzie" (($d.Kod -eq 0) -and ((Ile $cm $fCmPopr) -eq 1) -and ((Ile $oc $fCmPopr) -eq 1) -and (-not ($cm + $oc).Contains("$fCm`r`n")) -and ((Linie-Sekcji $oc) -ceq (Linie-Sekcji $cx))) ($d.Tekst + " | " + $cm)

  # ------------------------------------------------------------ -WzorCoWiem: narzedzie reczne
  # Sekcja wskazanego pliku idzie do wszystkich - nawet gdy inny plik jest nowszy.
  Zapisz $pCx ((Czytaj $pCx).Replace("testowa ZAPACH", "testowa NATURO")); Wiek $pCx 10
  Zapisz $pCm ((Czytaj $pCm).Replace("testowa ZAPACH", "testowa LAWENDA")); Wiek $pCm 1
  $w = Wpisz $dom @("-WzorCoWiem", "codex")
  $cm = Czytaj $pCm; $cx = Czytaj $pCx; $oc = Czytaj $pOc
  Sprawdz "wzor: wpisz-zasady -WzorCoWiem codex - kod 0, sekcja Codeksa w CLAUDE.md i OpenCode (mimo nowszego CLAUDE.md)" (($w.Kod -eq 0) -and ($w.Tekst -match "wedlug wzoru") -and ((Linie-Sekcji $cm) -ceq (Linie-Sekcji $cx)) -and ((Linie-Sekcji $oc) -ceq (Linie-Sekcji $cx)) -and $cm.Contains("testowa NATURO") -and -not $cm.Contains("LAWENDA")) $w.Tekst
  $d = Dopasuj $dom
  Sprawdz "wzor: potem straznik milczy o 'Co wiem'" (($d.Kod -eq 0) -and ($d.Tekst -notmatch "sprzeczn|zsynchronizowana")) $d.Tekst
  $w = Wpisz $dom @("-WzorCoWiem", "nieznane")
  Sprawdz "wzor: nieznane narzedzie - kod 1" ($w.Kod -eq 1) $w.Tekst

  # ------------------------------------------------------------ synchronizacja: pierwsza, bez stanu
  # Bez zapisanego stanu nie wiadomo, czy linii brakuje, bo ja skasowano, czy bo jej nie dopisano - wiec
  # tylko dopisujemy: linia tylko w Codeksie trafia do CLAUDE.md, a linia, ktorej w Codeksie brak, wraca.
  $dom = Nowy-Dom "sync-pierwsza" @("claude", "codex")
  $pCx = Join-Path $dom ".codex\AGENTS.md"; $pCm = Join-Path $dom ".claude\CLAUDE.md"
  Zapisz $pCm ("# Ustalenia globalne`r`n`r`n" + $wiedzaCm)
  [void](Zainstaluj "pierwsza synchronizacja - przygotowanie" $dom)
  $pStan = Join-Path $dom ".claude\mr\co-wiem-sync.json"
  Sprawdz "pierwsza: przygotowanie - stan synchronizacji zapisany" (Test-Path -LiteralPath $pStan)
  Remove-Item -LiteralPath $pStan
  Zapisz $pCx ((Czytaj $pCx).Replace("- Marka testowa, zapachy z numerami.`r`n", "").Replace("- [2026-10-05] Fakt biezacy z CLAUDE.md.", "- [2026-10-05] Fakt biezacy z CLAUDE.md.`r`n- [2026-10-06] Tylko w Codeksie."))
  $d = Dopasuj $dom
  $cm = Czytaj $pCm; $cx = Czytaj $pCx
  Sprawdz "pierwsza: kod 0, 'pierwsza synchronizacja - same dopisy'" (($d.Kod -eq 0) -and ($d.Tekst -match "pierwsza synchronizacja sekcji 'Co wiem' - same dopisy")) $d.Tekst
  Sprawdz "pierwsza: oba pliki maja obie linie (nic nie skasowane), sekcje rowne" ($cm.Contains("Tylko w Codeksie") -and $cm.Contains("- Marka testowa,") -and $cx.Contains("- Marka testowa,") -and ((Linie-Sekcji $cx) -ceq (Linie-Sekcji $cm))) ($cm + " | " + $cx)
  # stan nieczytelny - jak pierwsza synchronizacja (same dopisy), z uwaga, bez wywrotki
  Zapisz $pStan "{ to nie jest json"
  Zapisz $pCx ((Czytaj $pCx).Replace("- [2026-10-06] Tylko w Codeksie.", "- [2026-10-06] Tylko w Codeksie.`r`n- [2026-10-06] Po zepsutym stanie."))
  $w = Wpisz $dom
  Sprawdz "stan nieczytelny: wpisz-zasady kod 0, uwaga o stanie, dopis przeniesiony" (($w.Kod -eq 0) -and ($w.Tekst -match "UWAGA\s+Co wiem - stan synchronizacji") -and (Czytaj $pCm).Contains("Po zepsutym stanie.")) $w.Tekst

  # ------------------------------------------------------------ proba negatywna: synchronizacja ponad sufit (narzedzie testowe z limitem)
  # Codex z Limit = 32768 ($ZL). AGENTS.md Codeksa z wlasna trescia uzytkownika tuz pod 32 KiB, a CLAUDE.md dostaje duzy dopis: Codeksowi
  # NIE zapisujemy (odmowa w PIERWSZEJ linii, przy kazdym przebiegu), OpenCode i tak dostaje swoje. Zalegly
  # Codex nie kasuje niczego, czego nie dostal, a jego wlasny dopis idzie do pozostalych.
  $script:ZT = $ZL
  $dom = Nowy-Dom "sync-sufit" @("claude", "codex", "opencode")
  $pCx = Join-Path $dom ".codex\AGENTS.md"; $pCm = Join-Path $dom ".claude\CLAUDE.md"; $pOc = Join-Path $dom ".config\opencode\AGENTS.md"
  Zapisz $pCm ("# Ustalenia globalne`r`n`r`n" + $wiedzaCm)
  [void](Zainstaluj "sufit synchronizacji - przygotowanie" $dom)
  $cx = Czytaj $pCx
  $ileLinii = [int][Math]::Floor((32768 - 1200 - $Utf8.GetByteCount($cx)) / 57)
  $wyp = (1..$ileLinii | ForEach-Object { "- linia uzytkownika Codeksa do wypelnienia, numer {0:D5}`r`n" -f $_ }) -join ""
  Zapisz $pCx ("# Moje zasady Codeksa`r`n`r`n" + $wyp + "`r`n" + $cx)
  $d = Dopasuj $dom
  $ileB = (Get-Item $pCx).Length
  Sprawdz "sufit synchronizacji: przygotowanie - Codex ponizej 32 KiB, ponad 31 KiB, straznik kod 0" (($ileB -lt 32768) -and ($ileB -gt 31000) -and ($d.Kod -eq 0)) "$ileB B | $($d.Tekst)"
  $duzo = (1..30 | ForEach-Object { "- [2026-10-06] Duzy dopis numer {0:D3} do sekcji, ktory nie zmiesci sie w pliku Codeksa." -f $_ }) -join "`r`n"
  Zapisz $pCm ((Czytaj $pCm).Replace("- [2026-10-05] Fakt biezacy z CLAUDE.md.", "- [2026-10-05] Fakt biezacy z CLAUDE.md.`r`n$duzo"))
  $przedCx = Skrot $pCx; $bak = Ile-Bak $dom
  $d = Dopasuj $dom
  Sprawdz "sufit synchronizacji: straznik kod 1, odmowa w PIERWSZEJ linii (Codex, 'Co wiem', limit)" (($d.Kod -eq 1) -and ((Pierwsza $d.Tekst) -match "^MegaRuchacz: UWAGA - ODMOWA ZAPISU \(Codex\): synchronizacja sekcji 'Co wiem'.*32768 B - NIE zapisalem")) $d.Tekst
  Sprawdz "sufit synchronizacji: Codex co do bajtu, ponizej 32 KiB" (((Skrot $pCx) -eq $przedCx) -and ((Get-Item $pCx).Length -le 32768))
  Sprawdz "sufit synchronizacji: OpenCode i tak zsynchronizowany (jedna kopia .bak - tylko jego)" (((Linie-Sekcji (Czytaj $pOc)) -ceq (Linie-Sekcji (Czytaj $pCm))) -and ((Ile-Bak $dom) -eq ($bak + 1))) "$(Ile-Bak $dom) kopii"
  $d2 = Dopasuj $dom
  Sprawdz "sufit synchronizacji: drugi przebieg - odmowa znowu w PIERWSZEJ linii (sufit krzyczy)" (($d2.Kod -eq 1) -and ((Pierwsza $d2.Tekst) -match "^MegaRuchacz: UWAGA - ODMOWA ZAPISU \(Codex\)")) $d2.Tekst
  Sprawdz "sufit synchronizacji: zalegly Codex nie skasowal duzego dopisu z CLAUDE.md" (Czytaj $pCm).Contains("numer 030")
  $fZal = "- Dopis z Codeksa przy zaleglej sekcji."
  Zapisz $pCx ((Czytaj $pCx).Replace("- Marka testowa, zapachy z numerami.", "- Marka testowa, zapachy z numerami.`r`n$fZal"))
  $d3 = Dopasuj $dom
  $cm = Czytaj $pCm; $oc = Czytaj $pOc
  Sprawdz "sufit synchronizacji: dopis zaleglego Codeksa w CLAUDE.md i OpenCode, duzy dopis zostaje" ($cm.Contains($fZal) -and $oc.Contains($fZal) -and $cm.Contains("numer 030") -and $oc.Contains("numer 030") -and ((Ile $cm $fZal) -eq 1)) $d3.Tekst
  Zapisz $pCm ((Czytaj $pCm).Replace("`r`n$duzo", ""))
  $d4 = Dopasuj $dom
  $cm = Czytaj $pCm; $cx = Czytaj $pCx; $oc = Czytaj $pOc
  Sprawdz "sufit synchronizacji: po skroceniu CLAUDE.md kod 0, trzy pliki rowne, Codex ponizej 32 KiB" (($d4.Kod -eq 0) -and ((Linie-Sekcji $cx) -ceq (Linie-Sekcji $cm)) -and ((Linie-Sekcji $oc) -ceq (Linie-Sekcji $cm)) -and $cx.Contains($fZal) -and -not $cm.Contains("Duzy dopis") -and ((Get-Item $pCx).Length -le 32768)) $d4.Tekst
  $script:ZT = $Z

  # ------------------------------------------------------------ Pliki-Pamieci (zapis-trwaly.ps1) z listy narzedzi
  # Kopie dzienne i alarm o zerach biora pliki z Pliki-Pamieci. Wolajacy bez listy (kopie-dzienne) - lista
  # dolaczana przez zapis-trwaly sam; czwarte CLI dopisane do listy - jego plik tez.
  $dom = Nowy-Dom "pamiec" @("claude", "codex", "opencode")
  [void](Zainstaluj "Pliki-Pamieci - przygotowanie" $dom)
  $skrypt = Join-Path $T "pliki-pamieci.ps1"
  Zapisz $skrypt ('param([string]$zr, [string]$dom)' + "`r`n" + '. (Join-Path $zr "narzedzia\zapis-trwaly.ps1")' + "`r`n" + 'foreach ($p in (Pliki-Pamieci $dom)) { "PLIK " + $p }' + "`r`n")
  $trzy = @(".claude\CLAUDE.md", ".codex\AGENTS.md", ".config\opencode\AGENTS.md" | ForEach-Object { "PLIK " + (Join-Path $dom $_) })
  $r = Odpal $dom $skrypt @($Z, $dom)
  Sprawdz "Pliki-Pamieci: pliki instrukcji wszystkich trzech narzedzi" (($r.Kod -eq 0) -and (@($trzy | Where-Object { -not $r.Tekst.Contains($_) }).Count -eq 0)) $r.Tekst
  $Z4 = Join-Path $T "zrodlo-czwarte"
  New-Item -ItemType Directory -Force -Path (Join-Path $Z4 "narzedzia") | Out-Null
  Copy-Item (Join-Path $Z "narzedzia\zapis-trwaly.ps1") (Join-Path $Z4 "narzedzia\zapis-trwaly.ps1")
  $kc = Czytaj (Join-Path $Z "narzedzia\kierownik-cele.ps1")
  $kc4 = $kc.Replace('".config\opencode\skills") }', ('".config\opencode\skills") },' + "`r`n" +
         '    [pscustomobject]@{ Id = "czwarte"; Nazwa = "Czwarte"; Plik = ".czwarte\AGENTS.md"; Polecenie = "czwarte"; Slady = @(".czwarte"); Wariant = "opencode"; Limit = 0; Zapas = $null; Skille = @() }'))
  if ($kc4 -ceq $kc) { throw "czwarte CLI: kotwica listy narzedzi w kierownik-cele.ps1 sie zmienila - test nie dopisal wpisu" }
  Zapisz (Join-Path $Z4 "narzedzia\kierownik-cele.ps1") $kc4
  Zapisz (Join-Path $dom ".czwarte\AGENTS.md") "# czwarte`r`n"
  $r4 = Odpal $dom $skrypt @($Z4, $dom)
  Sprawdz "Pliki-Pamieci: czwarte CLI dopisane do listy - jego plik tez (i trzy pozostale)" (($kc4 -cne $kc) -and ($r4.Kod -eq 0) -and $r4.Tekst.Contains("PLIK " + (Join-Path $dom ".czwarte\AGENTS.md")) -and (@($trzy | Where-Object { -not $r4.Tekst.Contains($_) }).Count -eq 0)) $r4.Tekst

  # ------------------------------------------------------------ proba negatywna: zasiew ponad sufit (narzedzie testowe z limitem)
  # Codex z Limit = 32768 ($ZL). Wiedza w CLAUDE.md wieksza niz to, co zostalo do 32 KiB w AGENTS.md Codeksa: zasiewu NIE ma, powod
  # w PIERWSZEJ linii (wpisz-zasady i straznik), sekcja zostaje pusta, a reszta pliku (zdjety blok lore)
  # i tak jest zapisana. Mniejsza wiedza na tej samej sciezce przechodzi - to sufit blokuje.
  $script:ZT = $ZL
  $dom = Nowy-Dom "sufit-zasiew" @("codex")
  [void](Zainstaluj "sufit zasiewu - przygotowanie (Codex z pustym szkieletem)" $dom)
  $pCx = Join-Path $dom ".codex\AGENTS.md"; $pCm = Join-Path $dom ".claude\CLAUDE.md"
  $cx0 = Czytaj $pCx
  $ileWpisow = [int][Math]::Ceiling((32768 - $Utf8.GetByteCount($cx0) + 2000) / 60)
  $wpisy = (1..$ileWpisow | ForEach-Object { "- [2026-10-01] Wpis wiedzy numer {0:D5} do wypelnienia sekcji." -f $_ }) -join "`r`n"
  Zapisz (Join-Path $dom ".claude.json") "{}"
  Zapisz $pCm ("# Ustalenia globalne`r`n`r`n## Co wiem`r`n`r`n$BIEZACE`r`n`r`n$wpisy`r`n")
  $iL = $cx0.IndexOf($KL); $kL = "<!-- MegaRuchacz:lore:koniec -->"; $jL = $cx0.IndexOf($kL) + $kL.Length
  Zapisz $pCx ($cx0.Substring(0, $iL) + $cx0.Substring($jL).TrimStart("`r", "`n"))
  Sprawdz "sufit zasiewu: przygotowanie - Codex bez bloku lore, z pusta sekcja; wiedza ponad limit" (((Ile (Czytaj $pCx) $KL) -eq 0) -and (Pusta-Co-Wiem (Czytaj $pCx)) -and ($Utf8.GetByteCount($cx0 + $wpisy) -gt 32768)) "$ileWpisow wpisow"
  $w = Wpisz $dom
  $cx = Czytaj $pCx
  Sprawdz "sufit zasiewu: wpisz-zasady kod 1" ($w.Kod -eq 1) $w.Tekst
  Sprawdz "sufit zasiewu: ostrzezenie w PIERWSZEJ linii wyjscia (odmowa, zasiew, limit)" ((Pierwsza $w.Tekst) -match "^BLAD\s+ODMOWA ZAPISU \(Codex\):.*zasiew.*32768 B.*NIE zasialem") (Pierwsza $w.Tekst)
  Sprawdz "sufit zasiewu: sekcja Codeksa nadal pusta, plik ponizej 32 KiB" ((Pusta-Co-Wiem $cx) -and ((Get-Item $pCx).Length -le 32768)) "$((Get-Item $pCx).Length) B"
  Sprawdz "sufit zasiewu: reszta pliku zapisana - blok lore wrocil (odpada sam zasiew)" ((Ile $cx $KL) -eq 1)
  $przed = Skrot $pCx
  $d = Dopasuj $dom
  Sprawdz "sufit zasiewu: straznik -Dopasuj kod 1, UWAGA z odmowa zasiewu w PIERWSZEJ linii" (($d.Kod -eq 1) -and ((Pierwsza $d.Tekst) -match "^MegaRuchacz: UWAGA - ODMOWA ZAPISU \(Codex\):.*zasiew")) $d.Tekst
  Sprawdz "sufit zasiewu: straznik nie ruszyl pliku Codeksa" ((Skrot $pCx) -eq $przed)
  $wpisyMale = (1..20 | ForEach-Object { "- [2026-10-01] Wpis wiedzy numer {0:D5} do wypelnienia sekcji." -f $_ }) -join "`r`n"
  Zapisz $pCm ("# Ustalenia globalne`r`n`r`n## Co wiem`r`n`r`n$BIEZACE`r`n`r`n$wpisyMale`r`n")
  $w = Wpisz $dom
  $cx = Czytaj $pCx
  Sprawdz "sufit zasiewu - mniejsza wiedza: kod 0, Codex zasiany, ponizej 32 KiB" (($w.Kod -eq 0) -and $cx.Contains("numer 00020") -and -not $cx.Contains("numer 00021") -and ((Get-Item $pCx).Length -le 32768)) $w.Tekst
  $script:ZT = $Z

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
