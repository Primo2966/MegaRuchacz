# Sprawdzenie trybu "sam" w tle (zasobnik\terminy.ps1, 2026-10-08): claude -p bez okna, znacznik
# WYNIK w pierwszej linii odpowiedzi, wynik zawsze na trwale w ~\.claude\mr\przypomnienia-wyniki\
# <id>.json + .md, okno (claude --resume z naglowkiem MUSISZ / NIE UDALO SIE) tylko gdy potrzebny
# czlowiek albo cos poszlo zle, odhaczenie tylko przy "nic", tryb "przypomnij" bez zmian.
#   powershell -ExecutionPolicy Bypass -File zasobnik\test-terminy-tlo.ps1 [-Zrodlo <repo>]
# Wszystko na kopii terminy.ps1, sztucznym katalogu domowym i testowym pliku przypomnien. Claude to
# atrapa (claude.cmd -> node atrapa.js; scenariusz ze zmiennej MR_TEST_SCENARIUSZ, kazde wywolanie
# zapisane z argumentami, katalogiem i stdin). Otwieracz okna terminala i okno przypomnien w kopii
# podmienione na atrapy, ktore tylko zapisuja, z czym je wolano - zadne okno nie powstaje. Procesy
# bez okna konsoli; po kazdym przebiegu test czeka, az zniknie kazdy proces z katalogiem testu
# w wierszu polecen (takze proces w tle -Wykonaj i atrapa ubita po limicie czasu).
# Sabotaze na kopii: brak znacznika uznany za "nic", brak zapisu wyniku, okno przy "nic" -
# kazdy MUSI zostac zlapany.
param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { Write-Warning "konsola bez UTF-8: $($_.Exception.Message)" }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("test-terminy-tlo-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$dom = Join-Path $tmp "dom"
$katMr = Join-Path $dom ".claude\mr"
$projekt = Join-Path $tmp "projekt"
$katAtrapy = Join-Path $tmp "atrapa"
foreach ($k in @($katMr, $projekt, $katAtrapy)) { New-Item -ItemType Directory -Force -Path $k | Out-Null }
$plikP = Join-Path $katMr "przypomnienia.md"
$dziennik = Join-Path $katMr "przypomnienia.log"
$katWynikow = Join-Path $katMr "przypomnienia-wyniki"
$logAtrapy = Join-Path $tmp "atrapa-claude.jsonl"
$logOkien = Join-Path $tmp "atrapa-okna.jsonl"
$logOknaPrzyp = Join-Path $tmp "atrapa-okno-przypomnien.txt"
$oryginal = Join-Path $Zrodlo "zasobnik\terminy.ps1"
$BezBom = New-Object System.Text.UTF8Encoding($false)
$ZBom = New-Object System.Text.UTF8Encoding($true)
# Limit czasu w kopii - atrapa scenariusza "czas" spi 120 s, wiec limit musi ja ubic.
$LIMIT_TESTU_S = 4
# Jak dlugo czekamy na koniec wszystkich procesow jednego przebiegu (glowny + w tle + atrapa).
$CZEKAJ_NA_PROCESY_S = 60

$script:wyniki = @()
function Wynik($nazwa, $ok, $opis) {
  $script:wyniki += [pscustomobject]@{ Test = $nazwa; OK = [bool]$ok; Opis = $opis }
  $z = "NIE"; if ($ok) { $z = "TAK" }
  Write-Host ("[{0}] {1} - {2}" -f $z, $nazwa, $opis)
}

# ---------------------------------------------------------------- atrapa claude
$atrapaJs = @'
const fs = require("fs");
const scen = process.env.MR_TEST_SCENARIUSZ || "nic";
let stdin = "";
try { stdin = fs.readFileSync(0, "utf8"); } catch (e) { stdin = "BLAD STDIN " + e.message; }
fs.appendFileSync(process.env.MR_TEST_ATRAPA_LOG, JSON.stringify({ scen, argv: process.argv.slice(2), cwd: process.cwd(),
  stdin, wTle: process.env.MR_PRZYPOMNIENIE_W_TLE || "" }) + "\n");
const wynik = (result) => process.stdout.write(JSON.stringify({ type: "result", subtype: "success", is_error: false,
  result, session_id: "sesja-test-" + scen, permission_denials: [] }));
switch (scen) {
  case "nic": wynik("WYNIK: NIC_NIE_MUSISZ\n\nSprawdziłem logi, wszystko gra. Zażółć gęślą jaźń."); break;
  case "czlowiek": wynik("**WYNIK: POTRZEBUJE_CIEBIE: zatwierdź zmianę ceny P1 na Amazon UK**\n\nCena różni się o 2 £, propozycja w pliku."); break;
  case "brak": wynik("Zrobiłem wszystko, oto raport bez znacznika."); break;
  case "kod": process.stderr.write("API Error: 529 overloaded"); process.exitCode = 1; break;
  case "czas": setTimeout(() => wynik("WYNIK: NIC_NIE_MUSISZ\nza pozno"), 120000); break;
  case "json": process.stdout.write("to nie jest {json"); break;
  default: process.stderr.write("atrapa: nieznany scenariusz " + scen); process.exitCode = 3;
}
'@
[System.IO.File]::WriteAllText((Join-Path $katAtrapy "atrapa.js"), $atrapaJs, $BezBom)
$atrapaCmd = Join-Path $katAtrapy "claude.cmd"
[System.IO.File]::WriteAllText($atrapaCmd, "@node `"%~dp0atrapa.js`" %*`r`n", $BezBom)

# ---------------------------------------------------------------- kopia terminy.ps1
# Atrapy wstrzykniete PO wszystkich definicjach (pozniejsza definicja funkcji wygrywa).
$atrapy = @"
# ------------------------------------------------------------------------- przebieg
function Sciezka-Claude { return '$atrapaCmd' }
function Otworz-Terminal([string]`$kat, [string]`$id, [string]`$start) {
  `$z = [ordered]@{ kat = `$kat; id = `$id; start = `$start; skrypt = [System.IO.File]::ReadAllText(`$start, [System.Text.Encoding]::UTF8) }
  [System.IO.File]::AppendAllText('$logOkien', ((`$z | ConvertTo-Json -Compress) + "``r``n"), (New-Object System.Text.UTF8Encoding(`$false)))
  return "ATRAPA okna terminala"
}
function Okno-Przypomnien(`$pozycje) {
  [System.IO.File]::AppendAllText('$logOknaPrzyp', ((@(`$pozycje) | ForEach-Object { "#`$(`$_.id)" }) -join ",") + "``r``n")
}
"@
$zrodloSkryptu = [System.IO.File]::ReadAllText($oryginal, [System.Text.Encoding]::UTF8)
function Ile([string]$w, [string]$co) { return ([regex]::Matches($w, [regex]::Escape($co))).Count }
# Kazda kotwica musi wystapic dokladnie raz - inaczej porazka przygotowania, a nie test,
# ktory po cichu sprawdza co innego.
function Kopia([string]$wariant, [hashtable[]]$podmiany) {
  $wsp = @(
    @{ K = '# ------------------------------------------------------------------------- przebieg'; Z = $atrapy },
    @{ K = '"Local\MegaRuchacz-Terminy-Start"'; Z = '"Local\MegaRuchacz-Terminy-Start-TEST-TLA"' },
    @{ K = '"Local\MegaRuchacz-Terminy-Okno"'; Z = '"Local\MegaRuchacz-Terminy-Okno-TEST-TLA"' })
  $kod = $zrodloSkryptu
  foreach ($p in @($wsp) + @($podmiany)) {
    $n = Ile $kod $p.K
    if ($n -ne 1) { throw "kopia '$wariant': kotwica wystepuje $n razy (ma byc 1): $($p.K)" }
    $kod = $kod.Replace($p.K, $p.Z)
  }
  $plik = Join-Path $tmp "terminy-$wariant.ps1"
  [System.IO.File]::WriteAllText($plik, $kod, $ZBom)
  return $plik
}

function Procesy-Testu {
  return @(Get-CimInstance Win32_Process | Where-Object { "$($_.CommandLine)" -like "*$tmp*" -and $_.ProcessId -ne $PID })
}

# ---------------------------------------------------------------- przebieg
$dzis = (Get-Date).ToString("yyyy-MM-dd")
function Linia([int]$id, [string]$tresc, [string]$tryb) { return "- [ ] #$id $dzis | $projekt | $tresc | sprawdź: w logach | tryb: $tryb | dodane $dzis" }
$TRESC = "Sprawdzić logi synchronizacji eBay i porównać stany (zażółć)"

# Jeden przebieg kopii: czysty stan (albo zachowany, -Dalej), atrapa w scenariuszu, glowny
# proces bez okna, potem czekanie na proces w tle. Zwraca wszystko, co da sie sprawdzic.
function Uruchom([string]$kopia, [string]$scen, [string[]]$linie, [switch]$Dalej) {
  if (-not $Dalej) {
    foreach ($x in @($dziennik, $logAtrapy, $logOkien, $logOknaPrzyp)) { if (Test-Path -LiteralPath $x) { Remove-Item -LiteralPath $x -Force } }
    if (Test-Path -LiteralPath $katWynikow) { Remove-Item -LiteralPath $katWynikow -Recurse -Force }
    [System.IO.File]::WriteAllLines($plikP, [string[]](@("# Przypomnienia - plik testowy test-terminy-tlo.ps1", "") + $linie), $BezBom)
  }
  $env:MR_TEST_SCENARIUSZ = $scen
  $env:MR_TEST_ATRAPA_LOG = $logAtrapy
  $t0 = Get-Date
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$kopia`" -Zrodlo `"$Zrodlo`" -KatalogDomowy `"$dom`" -Plik `"$plikP`" -Dzis $dzis -LimitSekund $LIMIT_TESTU_S"
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  $p = [System.Diagnostics.Process]::Start($psi)
  $wy = $p.StandardOutput.ReadToEndAsync(); $bl = $p.StandardError.ReadToEndAsync()
  $zabity = $false
  if (-not $p.WaitForExit(60000)) { $p.Kill(); $p.WaitForExit(5000) | Out-Null; $zabity = $true }
  $p.WaitForExit()
  $zostale = @()
  $do = (Get-Date).AddSeconds($CZEKAJ_NA_PROCESY_S)
  while ((Get-Date) -lt $do) {
    $zostale = Procesy-Testu
    if ($zostale.Count -eq 0) { break }
    Start-Sleep -Milliseconds 300
  }
  foreach ($z in $zostale) { try { Stop-Process -Id $z.ProcessId -Force } catch { Write-Warning "nie ubilem $($z.ProcessId): $($_.Exception.Message)" } }
  $czytaj = { param($f) if (Test-Path -LiteralPath $f) { return [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8) } else { return "" } }
  $r = [pscustomobject]@{
    Kod = $p.ExitCode; Zabity = $zabity; Wyjscie = "$($wy.Result)$($bl.Result)".Trim(); Sekund = [int]((Get-Date) - $t0).TotalSeconds
    Zostale = @($zostale | ForEach-Object { "$($_.Name) $($_.ProcessId)" })
    Dziennik = (& $czytaj $dziennik); Przypomnienia = (& $czytaj $plikP); OknoPrzyp = (& $czytaj $logOknaPrzyp)
    Claude = @((& $czytaj $logAtrapy) -split "\r?\n" | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
    Okna = @((& $czytaj $logOkien) -split "\r?\n" | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
    Json = $null; JsonTekst = ""; Md = ""; MdBom = $false
  }
  $fj = Join-Path $katWynikow "1.json"
  if (Test-Path -LiteralPath $fj) {
    $r.JsonTekst = & $czytaj $fj
    try { $r.Json = $r.JsonTekst | ConvertFrom-Json } catch { $r.Json = $null }
  }
  $fm = Join-Path $katWynikow "1.md"
  if (Test-Path -LiteralPath $fm) { $b = [System.IO.File]::ReadAllBytes($fm); $r.MdBom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB); $r.Md = & $czytaj $fm }
  return $r
}

# ---------------------------------------------------------------- oceny
$POLA = @("id", "tresc", "projekt", "start", "koniec", "wynik", "co_zrobic", "powod", "raport", "session_id", "projekt_katalog")

# Wspolne dla kazdego przebiegu z jednym zadaniem "sam" (#1): przebieg czysty, atrapa wolana raz
# jak trzeba, wynik zapisany z kompletem pol. Zwraca liste usterek.
function Usterki-Wspolne($u, [string]$scen) {
  $z = @()
  if ($u.Zabity -or $u.Kod -ne 0) { $z += "glowny przebieg: kod $($u.Kod), zabity=$($u.Zabity), wyjscie '$($u.Wyjscie)'" }
  if ($u.Zostale.Count -gt 0) { $z += "zostaly procesy: $($u.Zostale -join ', ')" }
  if ($u.Dziennik -match 'WYWROTKA') { $z += "WYWROTKA w dzienniku" }
  if ($u.Claude.Count -ne 1) { $z += "atrapa claude wolana $($u.Claude.Count) razy" }
  else {
    $c = $u.Claude[0]
    $a = " " + ($c.argv -join " ") + " "
    foreach ($f in @(" -p ", " --output-format json ", " --permission-mode dontAsk ")) { if (-not $a.Contains($f)) { $z += "brak '$($f.Trim())' w argumentach: $a" } }
    if ($a -match 'dangerously|bypassPermissions') { $z += "uprawnienia poszerzone: $a" }
    if ($c.cwd.TrimEnd('\') -ne $projekt) { $z += "katalog '$($c.cwd)' zamiast projektu" }
    foreach ($f in @("WYNIK: NIC_NIE_MUSISZ", "WYNIK: POTRZEBUJE_CIEBIE:", $TRESC, "Niczego nie zmieniaj na produkcji")) { if (-not $c.stdin.Contains($f)) { $z += "polecenie bez '$f'" } }
    if ($c.wTle -ne "1") { $z += "MR_PRZYPOMNIENIE_W_TLE='$($c.wTle)'" }
  }
  $j = $u.Json
  if (-not $j) { $z += "brak pliku wyniku 1.json (albo nieczytelny)" }
  else {
    $nazwy = @($j.PSObject.Properties.Name)
    $brak = @($POLA | Where-Object { $nazwy -notcontains $_ }); $nadm = @($nazwy | Where-Object { $POLA -notcontains $_ })
    if ($brak.Count -or $nadm.Count) { $z += "pola wyniku: brak [$($brak -join ',')], nadmiarowe [$($nadm -join ',')]" }
    if (-not ($j.id -is [int] -and $j.id -eq 1) -or $u.JsonTekst -notmatch '"id":\s*1\s*,') { $z += "id nie jest liczba 1: '$($j.id)'" }
    if ($j.tresc -ne $TRESC) { $z += "tresc '$($j.tresc)'" }
    if ($j.projekt -ne $projekt -or $j.projekt_katalog -ne $projekt) { $z += "projekt '$($j.projekt)' / '$($j.projekt_katalog)'" }
    foreach ($pole in @("start", "koniec")) {
      $d = [datetimeoffset]::MinValue
      if (-not [datetimeoffset]::TryParseExact("$($j.$pole)", "yyyy-MM-ddTHH:mm:sszzz", [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$d)) { $z += "$pole nie ISO: '$($j.$pole)'" }
    }
    if (-not $u.Md -or -not $u.MdBom) { $z += "brak 1.md z BOM" }
    elseif ($j.raport -and -not $u.Md.Contains(($j.raport -split "\r?\n")[0])) { $z += "1.md bez raportu" }
  }
  if ($u.Dziennik -notmatch "w tle #1: wynik ") { $z += "brak linii 'w tle #1: wynik' w dzienniku" }
  return $z
}

function Stan-Linii([string]$tekst, [int]$id) {
  $m = [regex]::Match($tekst, "(?m)^- \[(.)\] #$id ")
  if ($m.Success) { return $m.Groups[1].Value }
  return "?"
}

# Zadanie wymagajace czlowieka albo blad: okno z naglowkiem, zostaje w toku.
function Usterki-Okna($u, [string]$naglowek, [bool]$wznowienie, [string]$sesja) {
  $z = @()
  if ($u.Okna.Count -ne 1) { return @("okien terminala $($u.Okna.Count) zamiast 1") }
  $o = $u.Okna[0]
  if ($o.kat.TrimEnd('\') -ne $projekt) { $z += "okno w '$($o.kat)'" }
  if (-not $o.skrypt.Contains($naglowek)) { $z += "skrypt okna bez naglowka '$naglowek'" }
  $iNagl = $o.skrypt.IndexOf($naglowek); $iClaude = $o.skrypt.IndexOf("& '$atrapaCmd'")
  if ($iClaude -lt 0 -or $iNagl -gt $iClaude) { $z += "naglowek nie stoi przed startem claude" }
  $bledy = $null
  [void][System.Management.Automation.Language.Parser]::ParseInput($o.skrypt, [ref]$null, [ref]$bledy)
  if (@($bledy).Count -gt 0) { $z += "skrypt okna sie nie parsuje: $(@($bledy | ForEach-Object { $_.Message }) -join '; ')" }
  if ($wznowienie) { if (-not $o.skrypt.Contains("--resume '$sesja'")) { $z += "brak --resume '$sesja'" } }
  else {
    if ($o.skrypt.Contains("--resume")) { $z += "--resume bez sesji" }
    if (-not $o.skrypt.Contains($TRESC)) { $z += "nowa rozmowa bez tresci zadania" }
  }
  if ((Stan-Linii $u.Przypomnienia 1) -ne "~") { $z += "status '$(Stan-Linii $u.Przypomnienia 1)' zamiast w toku" }
  return $z
}

$PRZYPADKI = [ordered]@{
  "nic" = { param($u)
    $z = @(Usterki-Wspolne $u "nic")
    if ($u.Json) {
      if ($u.Json.wynik -ne "nic" -or $u.Json.co_zrobic -ne "" -or $u.Json.session_id -ne "sesja-test-nic") { $z += "wynik '$($u.Json.wynik)', co '$($u.Json.co_zrobic)', sesja '$($u.Json.session_id)'" }
      if (-not $u.Json.raport.Contains("Zażółć gęślą jaźń")) { $z += "raport bez pelnej tresci (polskie litery): '$($u.Json.raport)'" }
    }
    if ($u.Okna.Count -ne 0) { $z += "otwarte okna terminala: $($u.Okna.Count)" }
    if ((Stan-Linii $u.Przypomnienia 1) -ne "x") { $z += "nie odhaczone: '$(Stan-Linii $u.Przypomnienia 1)'" }
    $z }
  "czlowiek" = { param($u)
    $z = @(Usterki-Wspolne $u "czlowiek")
    $co = "zatwierdź zmianę ceny P1 na Amazon UK"
    if ($u.Json -and ($u.Json.wynik -ne "czlowiek" -or $u.Json.co_zrobic -ne $co)) { $z += "wynik '$($u.Json.wynik)', co '$($u.Json.co_zrobic)'" }
    $z += @(Usterki-Okna $u "MUSISZ: $co" $true "sesja-test-czlowiek")
    $z }
  "brak" = { param($u)
    $z = @(Usterki-Wspolne $u "brak")
    if ($u.Json -and ($u.Json.wynik -ne "blad" -or $u.Json.powod -notmatch "brak znacznika")) { $z += "wynik '$($u.Json.wynik)', powod '$($u.Json.powod)'" }
    $z += @(Usterki-Okna $u "NIE UDAŁO SIĘ: brak znacznika" $true "sesja-test-brak")
    $z }
  "kod" = { param($u)
    $z = @(Usterki-Wspolne $u "kod")
    if ($u.Json -and ($u.Json.wynik -ne "blad" -or $u.Json.powod -notmatch "kodem 1" -or $u.Json.raport -notmatch "529")) { $z += "wynik '$($u.Json.wynik)', powod '$($u.Json.powod)', raport '$($u.Json.raport)'" }
    $z += @(Usterki-Okna $u "NIE UDAŁO SIĘ: Claude Code zakończył się kodem 1" $false "")
    $z }
  "czas" = { param($u)
    $z = @(Usterki-Wspolne $u "czas")
    if ($u.Json -and ($u.Json.wynik -ne "blad" -or $u.Json.powod -notmatch "limit czasu")) { $z += "wynik '$($u.Json.wynik)', powod '$($u.Json.powod)'" }
    if ($u.Sekund -gt 40) { $z += "trwalo $($u.Sekund) s - limit $LIMIT_TESTU_S s nie zadzialal" }
    $z += @(Usterki-Okna $u "NIE UDAŁO SIĘ: przekroczony limit czasu" $false "")
    $z }
  "json" = { param($u)
    $z = @(Usterki-Wspolne $u "json")
    if ($u.Json -and ($u.Json.wynik -ne "blad" -or $u.Json.powod -notmatch "nieczytelna")) { $z += "wynik '$($u.Json.wynik)', powod '$($u.Json.powod)'" }
    $z += @(Usterki-Okna $u "NIE UDAŁO SIĘ: nieczytelna odpowiedź" $false "")
    $z }
}
$OPISY = @{
  "nic" = "NIC_NIE_MUSISZ: bez okna, wynik zapisany, zadanie odhaczone"
  "czlowiek" = "POTRZEBUJE_CIEBIE: okno z --resume i naglowkiem MUSISZ, zostaje w toku"
  "brak" = "brak znacznika = blad, okno z --resume i NIE UDALO SIE"
  "kod" = "kod wyjscia != 0 = blad, okno z nowa rozmowa (bez sesji)"
  "czas" = "limit czasu: proces ubity z dziecmi, blad, okno"
  "json" = "nieczytelny JSON = blad, okno"
}
function Linie-Jednego([string]$tryb) { return @(Linia 1 $TRESC $tryb) }

# ---------------------------------------------------------------- przebiegi
try {
  $prawdziwa = Kopia "prawdziwa" @()
  foreach ($scen in $PRZYPADKI.Keys) {
    $u = Uruchom $prawdziwa $scen (Linie-Jednego "sam")
    $z = @(& $PRZYPADKI[$scen] $u)
    Wynik $OPISY[$scen] ($z.Count -eq 0) "$(if ($z) { $z -join ' | ' } else { "ok ($($u.Sekund) s)" })"
    if ($scen -eq "czlowiek") {
      # Najwyzej jedno samoczynne uruchomienie: kolejne sprawdzenie tego samego dnia nic nie odpala.
      $u2 = Uruchom $prawdziwa $scen @() -Dalej
      $ok = ($u2.Kod -eq 0) -and ($u2.Claude.Count -eq 1) -and ($u2.Okna.Count -eq 1) -and ((Stan-Linii $u2.Przypomnienia 1) -eq "~") -and (-not $u2.OknoPrzyp)
      Wynik "drugie sprawdzenie tego dnia nie uruchamia zadania w toku ponownie" $ok "wywolan claude $($u2.Claude.Count), okien $($u2.Okna.Count), okno przypomnien '$($u2.OknoPrzyp.Trim())'"
    }
  }

  # Tryb "przypomnij" bez zmian: do okna z przyciskami, bez claude, bez wyniku; obok "sam" (#2).
  $lin = @((Linia 1 "Kliknąć w Seller Central" "przypomnij"), (Linia 2 $TRESC "sam"))
  $u = Uruchom $prawdziwa "nic" $lin
  $z = @()
  if ($u.Kod -ne 0 -or $u.Dziennik -match 'WYWROTKA') { $z += "kod $($u.Kod), wyjscie '$($u.Wyjscie)'" }
  if ($u.OknoPrzyp.Trim() -ne "#1") { $z += "okno przypomnien z '$($u.OknoPrzyp.Trim())' zamiast #1" }
  if ($u.Przypomnienia -notmatch [regex]::Escape($lin[0])) { $z += "linia #1 zmieniona" }
  if (Test-Path -LiteralPath (Join-Path $katWynikow "1.json")) { $z += "jest wynik dla #1" }
  if ($u.Claude.Count -ne 1 -or $u.Claude[0].wTle -ne "2") { $z += "claude wolany $($u.Claude.Count) razy, dla '$(@($u.Claude | ForEach-Object { $_.wTle }) -join ',')'" }
  if ((Stan-Linii $u.Przypomnienia 2) -ne "x" -or -not (Test-Path -LiteralPath (Join-Path $katWynikow "2.json"))) { $z += "#2 (sam, nic) nie odhaczone albo bez wyniku" }
  if ($u.Okna.Count -ne 0) { $z += "okna terminala: $($u.Okna.Count)" }
  if ($u.Zostale.Count -gt 0) { $z += "zostaly procesy: $($u.Zostale -join ', ')" }
  Wynik "tryb 'przypomnij' bez zmian: okno z przyciskami, bez claude i bez wyniku" ($z.Count -eq 0) "$(if ($z) { $z -join ' | ' } else { 'ok' })"

  # Proba (-Proba) niczego nie uruchamia.
  $env:MR_TEST_SCENARIUSZ = "nic"
  [System.IO.File]::WriteAllLines($plikP, [string[]](Linie-Jednego "sam"), $BezBom)
  foreach ($x in @($logAtrapy, $logOkien)) { if (Test-Path -LiteralPath $x) { Remove-Item -LiteralPath $x -Force } }
  $wyProby = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $prawdziwa -Zrodlo $Zrodlo -KatalogDomowy $dom -Plik $plikP -Dzis $dzis -Proba 2>&1 | Out-String
  Start-Sleep -Milliseconds 1500
  $ok = (-not (Test-Path -LiteralPath $logAtrapy)) -and ((Stan-Linii ([System.IO.File]::ReadAllText($plikP)) 1) -eq " ") -and ($wyProby -match "uruchomilbym w tle") -and ((Procesy-Testu).Count -eq 0)
  Wynik "-Proba: nic nie uruchamia i nie zmienia, tylko mowi" $ok "wyjscie: $(($wyProby -split "`n" | Where-Object { $_ -match 'w tle' }) -join ' ')"

  # ------------------------------------------------------------ proby negatywne
  $sabotaze = @(
    @{ Nazwa = "brak znacznika uznany za 'nic'"; Scen = "brak"
       K = '$w.Powod = "brak znacznika WYNIK w pierwszej linii odpowiedzi"'; Z = '$w.Wynik = "nic"' },
    @{ Nazwa = "brak zapisu wyniku"; Scen = "nic"
       K = '$sciezka = Zapisz-Wynik $p $kat $start $koniec $w'; Z = '$sciezka = ""' },
    @{ Nazwa = "okno przy 'nic'"; Scen = "nic"
       K = 'if ($w.Wynik -ne "nic") {'; Z = 'if ($true) {' })
  $nr = 0
  foreach ($s in $sabotaze) {
    $nr++
    try { $kop = Kopia "sabotaz$nr" @(@{ K = $s.K; Z = $s.Z }) }
    catch { Wynik "negatywna: sabotaz '$($s.Nazwa)' wylapany" $false "przygotowanie: $($_.Exception.Message)"; continue }
    $u = Uruchom $kop $s.Scen (Linie-Jednego "sam")
    $z = @(& $PRZYPADKI[$s.Scen] $u)
    $dzialal = ($u.Claude.Count -eq 1) -and ($u.Kod -eq 0)
    Wynik "negatywna: sabotaz '$($s.Nazwa)' wylapany przez przypadek '$($s.Scen)'" (($z.Count -gt 0) -and $dzialal) "z sabotazem: $(if ($z) { $z -join ' | ' } else { 'NIE ZLAPANY' }); kopia dzialala: $dzialal"
  }
} catch {
  Wynik "WYWROTKA TESTU" $false "$($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
} finally {
  Remove-Item Env:\MR_TEST_SCENARIUSZ -ErrorAction SilentlyContinue
  Remove-Item Env:\MR_TEST_ATRAPA_LOG -ErrorAction SilentlyContinue
}

# Po tescie zaden proces (kopia, proces w tle, atrapa) nie moze zostac.
$zostale = Procesy-Testu
foreach ($z in $zostale) { try { Stop-Process -Id $z.ProcessId -Force } catch { Write-Warning "nie ubilem $($z.ProcessId): $($_.Exception.Message)" } }
Wynik "po tescie zaden proces testu nie zostal" ($zostale.Count -eq 0) "pozostalych: $($zostale.Count)"

Write-Host ""
Write-Host "Wynik: $(@($script:wyniki | Where-Object { $_.OK }).Count) z $($script:wyniki.Count) TAK. Pliki robocze: $tmp"
if (@($script:wyniki | Where-Object { -not $_.OK }).Count -gt 0) { exit 1 }
exit 0
