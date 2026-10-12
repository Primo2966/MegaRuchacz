# Sprawdzenie trybu "sam" w tle (zasobnik\terminy.ps1, 2026-10-08): claude -p bez okna, znacznik
# WYNIK w pierwszej linii odpowiedzi, wynik zawsze na trwale w ~\.claude\mr\przypomnienia-wyniki\
# <id>.json + .md, okno terminala (claude --resume z naglowkiem MUSISZ) tylko gdy potrzebny
# czlowiek, odhaczenie tylko przy "nic", tryb "przypomnij" bez zmian.
# Od 2026-10-12 (awaria 08:03 - trzy rownolegle claude -p padly na odswiezaniu logowania): Claude
# po kolei (kolejka), blad przejsciowy ponawiany do 3 razy, kazdy blad = zadanie samo na jutro
# i okno niepowodzenia (nigdy terminal), powod bledu takze z odpowiedzi Claude, "Zrob teraz"
# czeka na kolejke, porownanie katalogu projektu po normalizacji sciezki.
#   powershell -ExecutionPolicy Bypass -File zasobnik\test-terminy-tlo.ps1 [-Zrodlo <repo>]
# Wszystko na kopii terminy.ps1, sztucznym katalogu domowym i testowym pliku przypomnien. Claude to
# atrapa (claude.cmd -> node atrapa.js; scenariusz ze zmiennej MR_TEST_SCENARIUSZ, kazde wywolanie
# zapisane z argumentami, katalogiem, stdin i godzina). Otwieracz okna terminala i okno przypomnien
# w kopii podmienione na atrapy, ktore tylko zapisuja, z czym je wolano - zadne okno nie powstaje.
# Kopia ma wlasne zamki (start, okno, kolejka Claude) i pauze miedzy probami 1 s zamiast 60 s.
# Procesy bez okna konsoli; po kazdym przebiegu test czeka, az zniknie kazdy proces z katalogiem
# testu w wierszu polecen (takze proces w tle -Wykonaj i atrapa ubita po limicie czasu).
# Sabotaze na kopii (kazdy MUSI zostac zlapany): brak znacznika uznany za "nic", brak zapisu
# wyniku, okno przy "nic", usuniete ponawianie, rownolegly start, po porazce "w toku" zamiast
# jutra, powod tylko ze stderr, porownanie katalogu bez normalizacji, "Zrob teraz" bez kolejki.
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
$logCzasow = "$logAtrapy.czasy"
$logOkien = Join-Path $tmp "atrapa-okna.jsonl"
$logOknaPrzyp = Join-Path $tmp "atrapa-okno-przypomnien.txt"
$logNiep = Join-Path $tmp "atrapa-okno-niepowodzenia.jsonl"
$znakSprobuj = Join-Path $tmp "atrapa-sprobuj.txt"
$oryginal = Join-Path $Zrodlo "zasobnik\terminy.ps1"
$BezBom = New-Object System.Text.UTF8Encoding($false)
$ZBom = New-Object System.Text.UTF8Encoding($true)
# Limit czasu w kopii - atrapa scenariusza "czas" spi 120 s, wiec limit musi ja ubic.
$LIMIT_TESTU_S = 4
# Pauza miedzy probami w kopii (produkcyjnie $SEKUND_MIEDZY_PROBAMI = 60 s).
$PAUZA_TESTU_S = 1
# Jak dlugo czekamy na koniec wszystkich procesow jednego przebiegu (glowny + w tle + atrapa).
$CZEKAJ_NA_PROCESY_S = 60
# Zamek kolejki Claude w kopii (prawdziwy moglby trzymac dzialajacy wlasnie nadzorca).
$KOLEJKA_TESTU = "Local\MegaRuchacz-Terminy-Claude-TEST-TLA"
# "Zrob teraz" przy zajetej kolejce: tyle trzyma ja osobny proces; Claude ma ruszyc dopiero potem.
$MS_TRZYMANIA_KOLEJKI = 4000

$script:wyniki = @()
function Wynik($nazwa, $ok, $opis) {
  $script:wyniki += [pscustomobject]@{ Test = $nazwa; OK = [bool]$ok; Opis = $opis }
  $z = "NIE"; if ($ok) { $z = "TAK" }
  Write-Host ("[{0}] {1} - {2}" -f $z, $nazwa, $opis)
}

# ---------------------------------------------------------------- atrapa claude
# Scenariusze z bledem logowania licza wywolania po liczbie linii w logu atrapy (przed dopisaniem).
$atrapaJs = @'
const fs = require("fs");
const scen = process.env.MR_TEST_SCENARIUSZ || "nic";
const log = process.env.MR_TEST_ATRAPA_LOG;
const t = Date.now();
let stdin = "";
try { stdin = fs.readFileSync(0, "utf8"); } catch (e) { stdin = "BLAD STDIN " + e.message; }
const nr = (fs.existsSync(log) ? fs.readFileSync(log, "utf8").split("\n").filter(Boolean).length : 0) + 1;
fs.appendFileSync(log, JSON.stringify({ scen, nr, t, argv: process.argv.slice(2), cwd: process.cwd(),
  stdin, wTle: process.env.MR_PRZYPOMNIENIE_W_TLE || "" }) + "\n");
const wynik = (result) => process.stdout.write(JSON.stringify({ type: "result", subtype: "success", is_error: false,
  result, session_id: "sesja-test-" + scen, permission_denials: [] }));
const nic = () => wynik("WYNIK: NIC_NIE_MUSISZ\n\nSprawdziłem logi, wszystko gra. Zażółć gęślą jaźń.");
// Dokladnie to, co 2026-10-12 zwrocil prawdziwy claude -p (stdout JSON, stderr pusty, kod 1).
const oauth = () => { process.stdout.write(JSON.stringify({ type: "result", subtype: "success", is_error: true,
  result: "Failed to refresh OAuth token: another Claude Code process is refreshing it or exited mid-refresh. This is usually transient; retry in a minute, and if it persists close other Claude Code processes or sign in again",
  session_id: "sesja-test-" + scen })); process.exitCode = 1; };
switch (scen) {
  case "nic": case "ukosniki": nic(); break;
  case "czlowiek": wynik("**WYNIK: POTRZEBUJE_CIEBIE: zatwierdź zmianę ceny P1 na Amazon UK**\n\nCena różni się o 2 £, propozycja w pliku."); break;
  case "brak": wynik("Zrobiłem wszystko, oto raport bez znacznika."); break;
  case "kod": process.stderr.write("error: unknown option '--zla-flaga'"); process.exitCode = 1; break;
  case "przeciazenie": process.stderr.write("API Error: 529 {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"Overloaded\"}}"); process.exitCode = 1; break;
  case "czas": setTimeout(() => wynik("WYNIK: NIC_NIE_MUSISZ\nza pozno"), 120000); break;
  case "json": process.stdout.write("to nie jest {json"); break;
  case "oauth": if (nr <= 2) oauth(); else nic(); break;
  case "oauth-na-stale": oauth(); break;
  case "oauth-sprobuj": if (nr <= 3) oauth(); else nic(); break;
  case "wolno": setTimeout(() => { fs.appendFileSync(log + ".czasy", JSON.stringify({ id: process.env.MR_PRZYPOMNIENIE_W_TLE, start: t, koniec: Date.now() }) + "\n"); nic(); }, 2000); break;
  default: process.stderr.write("atrapa: nieznany scenariusz " + scen); process.exitCode = 3;
}
'@
[System.IO.File]::WriteAllText((Join-Path $katAtrapy "atrapa.js"), $atrapaJs, $BezBom)
$atrapaCmd = Join-Path $katAtrapy "claude.cmd"
[System.IO.File]::WriteAllText($atrapaCmd, "@node `"%~dp0atrapa.js`" %*`r`n", $BezBom)

# ---------------------------------------------------------------- kopia terminy.ps1
# Atrapy wstrzykniete PO wszystkich definicjach (pozniejsza definicja funkcji wygrywa). Okno
# niepowodzenia (Okno-Przypomnien "niepowodzenie") zapisuje, z czym je wolano, a przy
# MR_TEST_SPROBUJ raz "klika" Sprobuj teraz; zwykle okno przy MR_TEST_ZROB_TERAZ "klika" Zrob teraz.
$atrapy = @"
# ------------------------------------------------------------------------- przebieg
function Sciezka-Claude { return '$atrapaCmd' }
function Otworz-Terminal([string]`$kat, [string]`$id, [string]`$start) {
  `$z = [ordered]@{ kat = `$kat; id = `$id; start = `$start; skrypt = [System.IO.File]::ReadAllText(`$start, [System.Text.Encoding]::UTF8) }
  [System.IO.File]::AppendAllText('$logOkien', ((`$z | ConvertTo-Json -Compress) + "``r``n"), (New-Object System.Text.UTF8Encoding(`$false)))
  return "ATRAPA okna terminala"
}
function Okno-Przypomnien(`$pozycje, [string]`$rodzaj = "") {
  if (`$rodzaj -eq "niepowodzenie") {
    `$q = @(`$pozycje)[0]
    `$z = [ordered]@{ id = `$q.id; termin = `$q.termin; opis = `$q.opis; uwaga = `$q.uwaga; przeniesione = `$q.przeniesione }
    [System.IO.File]::AppendAllText('$logNiep', ((`$z | ConvertTo-Json -Compress) + "``r``n"), (New-Object System.Text.UTF8Encoding(`$false)))
    if (`$env:MR_TEST_SPROBUJ -and -not (Test-Path -LiteralPath '$znakSprobuj')) {
      [System.IO.File]::WriteAllText('$znakSprobuj', "klik")
      `$ok = Sprobuj-Teraz `$q
      [System.IO.File]::AppendAllText('$znakSprobuj', " wynik: `$ok")
    }
    return
  }
  [System.IO.File]::AppendAllText('$logOknaPrzyp', ((@(`$pozycje) | ForEach-Object { "#`$(`$_.id)" }) -join ",") + "``r``n")
  if (`$env:MR_TEST_ZROB_TERAZ) { [void](Uruchom-Claude @(`$pozycje)[0] "uruchomione przyciskiem (test)") }
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
    @{ K = '"Local\MegaRuchacz-Terminy-Okno"'; Z = '"Local\MegaRuchacz-Terminy-Okno-TEST-TLA"' },
    @{ K = '"Local\MegaRuchacz-Terminy-Claude"'; Z = "`"$KOLEJKA_TESTU`"" })
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

# Czeka, az zniknie kazdy proces testu; ubija resztke. Zwraca opisy tych, ktore zostaly.
function Czekaj-Na-Procesy {
  $zostale = @()
  $do = (Get-Date).AddSeconds($CZEKAJ_NA_PROCESY_S)
  while ((Get-Date) -lt $do) {
    $zostale = Procesy-Testu
    if ($zostale.Count -eq 0) { break }
    Start-Sleep -Milliseconds 300
  }
  foreach ($z in $zostale) { try { Stop-Process -Id $z.ProcessId -Force } catch { Write-Warning "nie ubilem $($z.ProcessId): $($_.Exception.Message)" } }
  return @($zostale | ForEach-Object { "$($_.Name) $($_.ProcessId)" })
}

function Czytaj([string]$f) { if (Test-Path -LiteralPath $f) { return [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8) } else { return "" } }
function Linie-Json([string]$f) { return @((Czytaj $f) -split "\r?\n" | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json }) }

# ---------------------------------------------------------------- przebieg
$dzis = (Get-Date).ToString("yyyy-MM-dd")
$jutro = (Get-Date).AddDays(1).ToString("yyyy-MM-dd")
function Linia([int]$id, [string]$tresc, [string]$tryb, [string]$proj = $projekt) { return "- [ ] #$id $dzis | $proj | $tresc | sprawdź: w logach | tryb: $tryb | dodane $dzis" }
$TRESC = "Sprawdzić logi synchronizacji eBay i porównać stany (zażółć)"

# Jeden przebieg kopii: czysty stan (albo zachowany, -Dalej), atrapa w scenariuszu, glowny
# proces bez okna, potem czekanie na procesy w tle. Zwraca wszystko, co da sie sprawdzic.
function Uruchom([string]$kopia, [string]$scen, [string[]]$linie, [switch]$Dalej) {
  if (-not $Dalej) {
    foreach ($x in @($dziennik, $logAtrapy, $logCzasow, $logOkien, $logOknaPrzyp, $logNiep, $znakSprobuj)) { if (Test-Path -LiteralPath $x) { Remove-Item -LiteralPath $x -Force } }
    foreach ($x in @($katWynikow, (Join-Path $katMr "terminy"))) { if (Test-Path -LiteralPath $x) { Remove-Item -LiteralPath $x -Recurse -Force } }
    [System.IO.File]::WriteAllLines($plikP, [string[]](@("# Przypomnienia - plik testowy test-terminy-tlo.ps1", "") + $linie), $BezBom)
  }
  $env:MR_TEST_SCENARIUSZ = $scen
  $env:MR_TEST_ATRAPA_LOG = $logAtrapy
  $t0 = Get-Date
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$kopia`" -Zrodlo `"$Zrodlo`" -KatalogDomowy `"$dom`" -Plik `"$plikP`" -Dzis $dzis -LimitSekund $LIMIT_TESTU_S -PauzaSekund $PAUZA_TESTU_S"
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
  $zostale = Czekaj-Na-Procesy
  $r = [pscustomobject]@{
    Kod = $p.ExitCode; Zabity = $zabity; Wyjscie = "$($wy.Result)$($bl.Result)".Trim(); Sekund = [int]((Get-Date) - $t0).TotalSeconds
    Zostale = @($zostale)
    Dziennik = (Czytaj $dziennik); Przypomnienia = (Czytaj $plikP); OknoPrzyp = (Czytaj $logOknaPrzyp)
    Claude = @(Linie-Json $logAtrapy); Okna = @(Linie-Json $logOkien); Niep = @(Linie-Json $logNiep); Czasy = @(Linie-Json $logCzasow)
    Sprobuj = (Czytaj $znakSprobuj)
    Json = $null; JsonTekst = ""; Md = ""; MdBom = $false
  }
  $fj = Join-Path $katWynikow "1.json"
  if (Test-Path -LiteralPath $fj) {
    $r.JsonTekst = Czytaj $fj
    try { $r.Json = $r.JsonTekst | ConvertFrom-Json } catch { $r.Json = $null }
  }
  $fm = Join-Path $katWynikow "1.md"
  if (Test-Path -LiteralPath $fm) { $b = [System.IO.File]::ReadAllBytes($fm); $r.MdBom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB); $r.Md = Czytaj $fm }
  return $r
}

# ---------------------------------------------------------------- oceny
$POLA = @("id", "tresc", "projekt", "start", "koniec", "wynik", "co_zrobic", "powod", "raport", "session_id", "projekt_katalog")
$UWAGA_KATALOGU = "nie ma na tym komputerze"

# Wspolne dla kazdego przebiegu z jednym zadaniem "sam" (#1): przebieg czysty, atrapa wolana
# $wywolan razy jak trzeba, wynik zapisany z kompletem pol. Zwraca liste usterek.
function Usterki-Wspolne($u, [string]$scen, [int]$wywolan = 1) {
  $z = @()
  if ($u.Zabity -or $u.Kod -ne 0) { $z += "glowny przebieg: kod $($u.Kod), zabity=$($u.Zabity), wyjscie '$($u.Wyjscie)'" }
  if ($u.Zostale.Count -gt 0) { $z += "zostaly procesy: $($u.Zostale -join ', ')" }
  if ($u.Dziennik -match 'WYWROTKA') { $z += "WYWROTKA w dzienniku" }
  if ($u.Claude.Count -ne $wywolan) { $z += "atrapa claude wolana $($u.Claude.Count) razy zamiast $wywolan" }
  if ($u.Claude.Count -gt 0) {
    $c = $u.Claude[0]
    $a = " " + ($c.argv -join " ") + " "
    foreach ($f in @(" -p ", " --output-format json ", " --permission-mode dontAsk ")) { if (-not $a.Contains($f)) { $z += "brak '$($f.Trim())' w argumentach: $a" } }
    if ($a -match 'dangerously|bypassPermissions') { $z += "uprawnienia poszerzone: $a" }
    if ($c.cwd.TrimEnd('\') -ne $projekt) { $z += "katalog '$($c.cwd)' zamiast projektu" }
    foreach ($f in @("WYNIK: NIC_NIE_MUSISZ", "WYNIK: POTRZEBUJE_CIEBIE:", $TRESC, "Niczego nie zmieniaj na produkcji")) { if (-not $c.stdin.Contains($f)) { $z += "polecenie bez '$f'" } }
    if ($c.stdin.Contains($UWAGA_KATALOGU)) { $z += "falszywa uwaga, ze katalogu projektu nie ma" }
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
function Data-Linii([string]$tekst, [int]$id) {
  $m = [regex]::Match($tekst, "(?m)^- \[.\] #$id (\d{4}-\d{2}-\d{2}) ")
  if ($m.Success) { return $m.Groups[1].Value }
  return "?"
}

# Zadanie wymagajace czlowieka: okno terminala z naglowkiem i --resume, zostaje w toku.
function Usterki-Okna($u, [string]$naglowek, [string]$sesja) {
  $z = @()
  if ($u.Niep.Count -ne 0) { $z += "okno niepowodzenia przy wyniku 'czlowiek'" }
  if ($u.Okna.Count -ne 1) { return @($z) + @("okien terminala $($u.Okna.Count) zamiast 1") }
  $o = $u.Okna[0]
  if ($o.kat.TrimEnd('\') -ne $projekt) { $z += "okno w '$($o.kat)'" }
  if (-not $o.skrypt.Contains($naglowek)) { $z += "skrypt okna bez naglowka '$naglowek'" }
  $iNagl = $o.skrypt.IndexOf($naglowek); $iClaude = $o.skrypt.IndexOf("& '$atrapaCmd'")
  if ($iClaude -lt 0 -or $iNagl -gt $iClaude) { $z += "naglowek nie stoi przed startem claude" }
  $bledy = $null
  [void][System.Management.Automation.Language.Parser]::ParseInput($o.skrypt, [ref]$null, [ref]$bledy)
  if (@($bledy).Count -gt 0) { $z += "skrypt okna sie nie parsuje: $(@($bledy | ForEach-Object { $_.Message }) -join '; ')" }
  if (-not $o.skrypt.Contains("--resume '$sesja'")) { $z += "brak --resume '$sesja'" }
  if ((Stan-Linii $u.Przypomnienia 1) -ne "~") { $z += "status '$(Stan-Linii $u.Przypomnienia 1)' zamiast w toku" }
  return $z
}

# Blad: wynik "blad" z powodem, zadanie samo na jutro (otwarte, data jutro), okno niepowodzenia
# ze zdaniem dla czlowieka, zadnego terminala. $fragmenty - wszystkie musza stac w powodzie i w oknie.
function Usterki-Niepowodzenia($u, [string[]]$fragmenty) {
  $z = @()
  if ($u.Json -and $u.Json.wynik -ne "blad") { $z += "wynik '$($u.Json.wynik)' zamiast blad" }
  foreach ($f in $fragmenty) { if ($u.Json -and -not "$($u.Json.powod)".Contains($f)) { $z += "powod bez '$f': '$($u.Json.powod)'" } }
  if ($u.Okna.Count -ne 0) { $z += "otwarty terminal ($($u.Okna.Count)) - ma byc tylko okno niepowodzenia" }
  if ((Stan-Linii $u.Przypomnienia 1) -ne " ") { $z += "status '$(Stan-Linii $u.Przypomnienia 1)' zamiast otwarte (na jutro)" }
  if ((Data-Linii $u.Przypomnienia 1) -ne $jutro) { $z += "termin '$(Data-Linii $u.Przypomnienia 1)' zamiast jutro $jutro" }
  if ($u.Niep.Count -ne 1) { $z += "okien niepowodzenia $($u.Niep.Count) zamiast 1"; return $z }
  $n = $u.Niep[0]
  if ("$($n.id)" -ne "1" -or $n.przeniesione -ne $true -or $n.termin -ne $jutro) { $z += "okno niepowodzenia: id '$($n.id)', przeniesione '$($n.przeniesione)', termin '$($n.termin)'" }
  foreach ($f in @("Nie udało się wykonać przypomnienia #1 (Sprawdzić logi", "), bo: ", "Przeniesione na jutro.") + @($fragmenty)) {
    if (-not "$($n.uwaga)".Contains($f)) { $z += "okno niepowodzenia bez '$f': '$($n.uwaga)'" }
  }
  return $z
}

# Kilka zadan "sam" naraz: Claude po kolei - kazdy start po koncu poprzedniego.
function Usterki-Kolejki($u, [int]$ile) {
  $z = @()
  if ($u.Kod -ne 0 -or $u.Dziennik -match 'WYWROTKA') { $z += "kod $($u.Kod), wyjscie '$($u.Wyjscie)'" }
  if ($u.Zostale.Count -gt 0) { $z += "zostaly procesy: $($u.Zostale -join ', ')" }
  if ($u.Claude.Count -ne $ile -or $u.Czasy.Count -ne $ile) { $z += "wywolan claude $($u.Claude.Count), zakonczonych $($u.Czasy.Count) zamiast $ile" }
  $kol = @($u.Czasy | Sort-Object { [double]$_.start })
  for ($i = 1; $i -lt $kol.Count; $i++) {
    if ([double]$kol[$i].start -lt [double]$kol[$i - 1].koniec) { $z += "#$($kol[$i].id) ruszyl $([double]$kol[$i - 1].koniec - [double]$kol[$i].start) ms przed koncem #$($kol[$i - 1].id)" }
  }
  foreach ($id in 1..$ile) { if ((Stan-Linii $u.Przypomnienia $id) -ne "x") { $z += "#$id nie odhaczone ('$(Stan-Linii $u.Przypomnienia $id)')" } }
  if ($u.Okna.Count -ne 0 -or $u.Niep.Count -ne 0) { $z += "okna: terminal $($u.Okna.Count), niepowodzenia $($u.Niep.Count)" }
  if ($u.Dziennik -notmatch 'czeka w kolejce') { $z += "w dzienniku ani jednego 'czeka w kolejce'" }
  return $z
}

# "Zrob teraz" przy zajetej kolejce: osobny proces trzyma zamek kolejki $MS_TRZYMANIA_KOLEJKI ms,
# skrypt startowy okna (zrob-1.ps1, napisany przez kopie) ma ruszyc atrape claude dopiero po jego
# zwolnieniu. Zwraca liste usterek.
$trzymacz = Join-Path $tmp "trzymacz-kolejki.ps1"
[System.IO.File]::WriteAllText($trzymacz, @'
param([string]$Nazwa, [int]$Ms, [string]$Znak)
$z = New-Object System.Threading.Mutex($false, $Nazwa)
if (-not $z.WaitOne(10000)) { [System.IO.File]::WriteAllText($Znak, "nie wzialem zamka"); exit 1 }
[System.IO.File]::WriteAllText($Znak, "trzymam")
Start-Sleep -Milliseconds $Ms
[System.IO.File]::WriteAllText($Znak, "puszczam " + [DateTimeOffset]::Now.ToUnixTimeMilliseconds())
$z.ReleaseMutex(); $z.Dispose()
exit 0
'@, $BezBom)
function Usterki-Zrob-Teraz($u) {
  $z = @()
  if ($u.Kod -ne 0 -or $u.Dziennik -match 'WYWROTKA') { $z += "kod $($u.Kod), wyjscie '$($u.Wyjscie)'" }
  if ($u.Okna.Count -ne 1) { return @($z) + @("okien terminala $($u.Okna.Count) zamiast 1 (Zrob teraz)") }
  $start = $u.Okna[0].start
  $bledy = $null
  [void][System.Management.Automation.Language.Parser]::ParseInput($u.Okna[0].skrypt, [ref]$null, [ref]$bledy)
  if (@($bledy).Count -gt 0) { return @($z) + @("skrypt startowy sie nie parsuje: $(@($bledy | ForEach-Object { $_.Message }) -join '; ')") }
  if (Test-Path -LiteralPath $logAtrapy) { Remove-Item -LiteralPath $logAtrapy -Force }
  $znak = Join-Path $tmp "trzymacz-kolejki.txt"
  if (Test-Path -LiteralPath $znak) { Remove-Item -LiteralPath $znak -Force }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$trzymacz`" -Nazwa `"$KOLEJKA_TESTU`" -Ms $MS_TRZYMANIA_KOLEJKI -Znak `"$znak`""
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $tr = [System.Diagnostics.Process]::Start($psi)
  $do = (Get-Date).AddSeconds(20)
  while (((Czytaj $znak) -ne "trzymam") -and ((Get-Date) -lt $do) -and -not $tr.HasExited) { Start-Sleep -Milliseconds 50 }
  if ((Czytaj $znak) -ne "trzymam") { $z += "trzymacz kolejki nie trzyma: '$(Czytaj $znak)'" }
  $env:MR_TEST_SCENARIUSZ = "nic"
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$start`""
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  $s = [System.Diagnostics.Process]::Start($psi)
  $s.StandardInput.Close()
  $wy = $s.StandardOutput.ReadToEndAsync(); $bl = $s.StandardError.ReadToEndAsync()
  if (-not $s.WaitForExit(30000)) { $s.Kill(); $z += "skrypt startowy nie skonczyl w 30 s" }
  $s.WaitForExit()
  if (-not $tr.WaitForExit(20000)) { $tr.Kill(); $z += "trzymacz nie skonczyl" }
  $zostale = Czekaj-Na-Procesy
  if ($zostale.Count -gt 0) { $z += "zostaly procesy: $($zostale -join ', ')" }
  $puszczam = 0.0
  if ((Czytaj $znak) -match '^puszczam (\d+)$') { $puszczam = [double]$Matches[1] } else { $z += "trzymacz: '$(Czytaj $znak)'" }
  $c = @(Linie-Json $logAtrapy)
  if ($c.Count -ne 1) { $z += "skrypt startowy wolal claude $($c.Count) razy (wyjscie: $("$($wy.Result)$($bl.Result)".Trim()))" }
  elseif ([double]$c[0].t -lt $puszczam) { $z += "claude ruszyl $($puszczam - [double]$c[0].t) ms PRZED zwolnieniem kolejki" }
  if ("$($wy.Result)" -notmatch 'Czekam,.*zadanie z przypomnienia') { $z += "skrypt nie powiedzial, ze czeka na kolejke" }
  return $z
}

# Przypadki: Scen = scenariusz atrapy, Linie = plik przypomnien, Env = dodatkowe zmienne,
# Ocena = lista usterek. Sabotaze uzywaja tych samych przypadkow.
$PRZYPADKI = [ordered]@{
  "nic" = @{ Opis = "NIC_NIE_MUSISZ: bez okna, wynik zapisany, zadanie odhaczone"; Ocena = { param($u)
    $z = @(Usterki-Wspolne $u "nic")
    if ($u.Json) {
      if ($u.Json.wynik -ne "nic" -or $u.Json.co_zrobic -ne "" -or $u.Json.session_id -ne "sesja-test-nic") { $z += "wynik '$($u.Json.wynik)', co '$($u.Json.co_zrobic)', sesja '$($u.Json.session_id)'" }
      if (-not $u.Json.raport.Contains("Zażółć gęślą jaźń")) { $z += "raport bez pelnej tresci (polskie litery): '$($u.Json.raport)'" }
    }
    if ($u.Okna.Count -ne 0 -or $u.Niep.Count -ne 0) { $z += "otwarte okna: terminal $($u.Okna.Count), niepowodzenia $($u.Niep.Count)" }
    if ((Stan-Linii $u.Przypomnienia 1) -ne "x") { $z += "nie odhaczone: '$(Stan-Linii $u.Przypomnienia 1)'" }
    $z } }
  "czlowiek" = @{ Opis = "POTRZEBUJE_CIEBIE: okno z --resume i naglowkiem MUSISZ, zostaje w toku (bez zmian)"; Ocena = { param($u)
    $z = @(Usterki-Wspolne $u "czlowiek")
    $co = "zatwierdź zmianę ceny P1 na Amazon UK"
    if ($u.Json -and ($u.Json.wynik -ne "czlowiek" -or $u.Json.co_zrobic -ne $co)) { $z += "wynik '$($u.Json.wynik)', co '$($u.Json.co_zrobic)'" }
    $z += @(Usterki-Okna $u "MUSISZ: $co" "sesja-test-czlowiek")
    $z } }
  "brak" = @{ Opis = "brak znacznika = blad bez ponawiania (1 wywolanie), na jutro, okno niepowodzenia"; Ocena = { param($u)
    $z = @(Usterki-Wspolne $u "brak" 1)
    $z += @(Usterki-Niepowodzenia $u @("brak znacznika WYNIK"))
    $z } }
  "kod" = @{ Opis = "blad nieprzejsciowy (kod 1, nieznana opcja) = 1 wywolanie, powod ze stderr, na jutro"; Ocena = { param($u)
    $z = @(Usterki-Wspolne $u "kod" 1)
    $z += @(Usterki-Niepowodzenia $u @("kodem 1", "unknown option", "bez ponawiania"))
    $z } }
  "czas" = @{ Opis = "limit czasu: proces ubity z dziecmi, blad bez ponawiania, na jutro"; Ocena = { param($u)
    $z = @(Usterki-Wspolne $u "czas" 1)
    if ($u.Sekund -gt 40) { $z += "trwalo $($u.Sekund) s - limit $LIMIT_TESTU_S s nie zadzialal" }
    $z += @(Usterki-Niepowodzenia $u @("przekroczony limit czasu"))
    $z } }
  "json" = @{ Opis = "nieczytelny JSON = blad bez ponawiania, na jutro"; Ocena = { param($u)
    $z = @(Usterki-Wspolne $u "json" 1)
    $z += @(Usterki-Niepowodzenia $u @("nieczytelna odpowiedź", "to nie jest {json"))
    $z } }
  "oauth" = @{ Opis = "blad logowania 2 razy (tylko w JSON, stderr pusty), za 3. razem wyszlo: 3 wywolania, odhaczone, bez okna"; Ocena = { param($u)
    $z = @(Usterki-Wspolne $u "oauth" 3)
    if ($u.Json -and $u.Json.wynik -ne "nic") { $z += "wynik '$($u.Json.wynik)', powod '$($u.Json.powod)'" }
    if ((Stan-Linii $u.Przypomnienia 1) -ne "x") { $z += "nie odhaczone: '$(Stan-Linii $u.Przypomnienia 1)'" }
    if ($u.Okna.Count -ne 0 -or $u.Niep.Count -ne 0) { $z += "otwarte okna: terminal $($u.Okna.Count), niepowodzenia $($u.Niep.Count)" }
    foreach ($n in 1..2) { if ($u.Dziennik -notmatch "w tle #1: proba $n z 3 nieudana, blad przejsciowy \(Claude nie mógł się zalogować") { $z += "brak w dzienniku 'proba $n z 3 nieudana'" } }
    $kol = @($u.Claude | Sort-Object { [double]$_.t })
    if ($kol.Count -ge 2 -and ([double]$kol[1].t - [double]$kol[0].t) -lt ($PAUZA_TESTU_S * 1000)) { $z += "druga proba bez pauzy" }
    $z } }
  "oauth-na-stale" = @{ Opis = "blad logowania 3 razy: na jutro, powod z odpowiedzi Claude, okno niepowodzenia (nie --resume)"; Ocena = { param($u)
    $z = @(Usterki-Wspolne $u "oauth-na-stale" 3)
    $z += @(Usterki-Niepowodzenia $u @("Claude nie mógł się zalogować, bo kilka okien naraz odnawiało logowanie", "Failed to refresh OAuth token: another Claude Code process", "prób: 3 z 3"))
    $z } }
  "przeciazenie" = @{ Opis = "API przeciazone (529 w stderr) 3 razy: ponawiane, na jutro, powod po ludzku"; Ocena = { param($u)
    $z = @(Usterki-Wspolne $u "przeciazenie" 3)
    $z += @(Usterki-Niepowodzenia $u @("serwery Claude były przeciążone", "529", "prób: 3 z 3"))
    $z } }
  "wolno" = @{ Opis = "trzy zadania 'sam' naraz: Claude po kolei, starty sie nie nakladaja, wszystkie odhaczone"
    Linie = { @((Linia 1 $TRESC "sam"), (Linia 2 $TRESC "sam"), (Linia 3 $TRESC "sam")) }
    Ocena = { param($u) @(Usterki-Kolejki $u 3) } }
  "oauth-sprobuj" = @{ Opis = "okno niepowodzenia -> 'Sprobuj teraz': z powrotem na dzis, nowy przebieg w tle, odhaczone"; Env = @{ MR_TEST_SPROBUJ = "1" }; Ocena = { param($u)
    $z = @()
    if ($u.Kod -ne 0 -or $u.Dziennik -match 'WYWROTKA') { $z += "kod $($u.Kod), wyjscie '$($u.Wyjscie)'" }
    if ($u.Zostale.Count -gt 0) { $z += "zostaly procesy: $($u.Zostale -join ', ')" }
    if ($u.Claude.Count -ne 4) { $z += "wywolan claude $($u.Claude.Count) zamiast 4 (3 nieudane + Sprobuj teraz)" }
    if ($u.Niep.Count -ne 1) { $z += "okien niepowodzenia $($u.Niep.Count) zamiast 1" }
    if ($u.Sprobuj -ne "klik wynik: True") { $z += "Sprobuj teraz: '$($u.Sprobuj)'" }
    if ($u.Dziennik -notmatch 'przycisk Sprobuj teraz #1: w tle') { $z += "brak w dzienniku 'przycisk Sprobuj teraz #1: w tle'" }
    if ((Stan-Linii $u.Przypomnienia 1) -ne "x") { $z += "nie odhaczone po Sprobuj teraz: '$(Stan-Linii $u.Przypomnienia 1)' $(Data-Linii $u.Przypomnienia 1)" }
    if ($u.Json -and $u.Json.wynik -ne "nic") { $z += "ostatni wynik '$($u.Json.wynik)'" }
    $z } }
  "ukosniki" = @{ Opis = "projekt zapisany z '/', koncowym '/' i malymi literami: bez falszywej uwagi, ze katalogu nie ma"
    Linie = { @(Linia 1 $TRESC "sam" ($projekt.Replace('\', '/').ToLowerInvariant() + '/')) }
    Ocena = { param($u)
      $z = @()
      if ($u.Kod -ne 0 -or $u.Dziennik -match 'WYWROTKA') { $z += "kod $($u.Kod), wyjscie '$($u.Wyjscie)'" }
      if ($u.Claude.Count -ne 1) { $z += "wywolan claude $($u.Claude.Count)" }
      else {
        if ($u.Claude[0].stdin.Contains($UWAGA_KATALOGU)) { $z += "falszywa uwaga, ze katalogu projektu nie ma" }
        if ($u.Claude[0].cwd.TrimEnd('\') -ine $projekt) { $z += "katalog '$($u.Claude[0].cwd)' zamiast projektu" }
      }
      if ((Stan-Linii $u.Przypomnienia 1) -ne "x") { $z += "nie odhaczone: '$(Stan-Linii $u.Przypomnienia 1)'" }
      $z } }
  "zrob-teraz" = @{ Opis = "'Zrob teraz' przy zajetej kolejce: Claude rusza dopiero po jej zwolnieniu, okno mowi, ze czeka"
    Scen = "nic"; Env = @{ MR_TEST_ZROB_TERAZ = "1" }
    Linie = { @(Linia 1 "Kliknąć w Seller Central" "przypomnij") }
    Ocena = { param($u) @(Usterki-Zrob-Teraz $u) }
    Dzialal = { param($u) ($u.Kod -eq 0) -and ($u.Okna.Count -eq 1) } }
}

# Jeden przypadek na danej kopii. Zwraca usterki i to, czy kopia w ogole zadzialala.
function Przypadek([string]$kopia, [string]$nazwa) {
  $c = $PRZYPADKI[$nazwa]
  $scen = $nazwa; if ($c.Scen) { $scen = $c.Scen }
  $linie = @(Linia 1 $TRESC "sam"); if ($c.Linie) { $linie = @(& $c.Linie) }
  $env_ = @{}; if ($c.Env) { $env_ = $c.Env }
  foreach ($k in $env_.Keys) { Set-Item -Path "Env:\$k" -Value $env_[$k] }
  try {
    $u = Uruchom $kopia $scen $linie
    $z = @(& $c.Ocena $u)
  } finally { foreach ($k in $env_.Keys) { Remove-Item -Path "Env:\$k" -ErrorAction SilentlyContinue } }
  $dzialal = ($u.Kod -eq 0) -and ($u.Claude.Count -ge 1)
  if ($c.Dzialal) { $dzialal = [bool](& $c.Dzialal $u) }
  return [pscustomobject]@{ U = $u; Z = $z; Dzialal = $dzialal }
}

# ---------------------------------------------------------------- przebiegi
try {
  $prawdziwa = Kopia "prawdziwa" @()
  foreach ($nazwa in $PRZYPADKI.Keys) {
    $w = Przypadek $prawdziwa $nazwa
    Wynik $PRZYPADKI[$nazwa].Opis ($w.Z.Count -eq 0) "$(if ($w.Z) { $w.Z -join ' | ' } else { "ok ($($w.U.Sekund) s)" })"
    if ($nazwa -eq "czlowiek") {
      # Najwyzej jedno samoczynne uruchomienie: kolejne sprawdzenie tego samego dnia nic nie odpala.
      $u2 = Uruchom $prawdziwa "czlowiek" @() -Dalej
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
  [System.IO.File]::WriteAllLines($plikP, [string[]](@(Linia 1 $TRESC "sam")), $BezBom)
  foreach ($x in @($logAtrapy, $logOkien)) { if (Test-Path -LiteralPath $x) { Remove-Item -LiteralPath $x -Force } }
  $wyProby = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $prawdziwa -Zrodlo $Zrodlo -KatalogDomowy $dom -Plik $plikP -Dzis $dzis -Proba 2>&1 | Out-String
  Start-Sleep -Milliseconds 1500
  $ok = (-not (Test-Path -LiteralPath $logAtrapy)) -and ((Stan-Linii ([System.IO.File]::ReadAllText($plikP)) 1) -eq " ") -and ($wyProby -match "uruchomilbym w tle") -and ((Procesy-Testu).Count -eq 0)
  Wynik "-Proba: nic nie uruchamia i nie zmienia, tylko mowi" $ok "wyjscie: $(($wyProby -split "`n" | Where-Object { $_ -match 'w tle' }) -join ' ')"

  # ------------------------------------------------------------ proby negatywne
  $sabotaze = @(
    @{ Nazwa = "brak znacznika uznany za 'nic'"; Przypadek = "brak"
       K = '$w.Powod = "brak znacznika WYNIK w pierwszej linii odpowiedzi"'; Z = '$w.Wynik = "nic"' },
    @{ Nazwa = "brak zapisu wyniku"; Przypadek = "nic"
       K = '$sciezka = Zapisz-Wynik $p $kat $start $koniec $w'; Z = '$sciezka = ""' },
    @{ Nazwa = "okno przy 'nic'"; Przypadek = "nic"
       K = 'if ($w.Wynik -ne "nic") {'; Z = 'if ($true) {' },
    @{ Nazwa = "usuniete ponawianie"; Przypadek = "oauth"
       K = 'if (-not (($w.Wynik -eq "blad") -and $w.Przejsciowy -and ($nrProby -lt $PROB_W_TLE))) { break }'; Z = 'break' },
    @{ Nazwa = "rownolegly start (bez kolejki)"; Przypadek = "wolno"
       K = 'try { $kolejka = Zajmij-Kolejke "w tle #$id" }'; Z = 'try { $kolejka = $null }' },
    @{ Nazwa = "po porazce zostaje 'w toku' zamiast jutra"; Przypadek = "oauth-na-stale"
       K = 'if (Zmien-Status "przesun" @("$id", "jutro") "w tle #${id}: blad - przesuniecie na jutro")'; Z = 'if ($false)' },
    @{ Nazwa = "powod tylko ze stderr"; Przypadek = "oauth-na-stale"
       K = 'if (-not $trescBledu) { if ($j -and "$($j.result)".Trim()) { $trescBledu = "$($j.result)".Trim() } else { $trescBledu = $tekst } }'; Z = '# sabotaz: tylko stderr' },
    @{ Nazwa = "katalog porownywany bez normalizacji"; Przypadek = "ukosniki"
       K = 'if ((Sciezka-Do-Porownania $katalog) -ne (Sciezka-Do-Porownania $p.projekt)) {'; Z = 'if ($katalog -ne $p.projekt) {' },
    @{ Nazwa = "'Zrob teraz' bez czekania na kolejke"; Przypadek = "zrob-teraz"
       K = ') + (Linie-Czekania-Na-Kolejke) + @('; Z = ') + @(' })
  $nr = 0
  foreach ($s in $sabotaze) {
    $nr++
    try { $kop = Kopia "sabotaz$nr" @(@{ K = $s.K; Z = $s.Z }) }
    catch { Wynik "negatywna: sabotaz '$($s.Nazwa)' wylapany" $false "przygotowanie: $($_.Exception.Message)"; continue }
    $w = Przypadek $kop $s.Przypadek
    Wynik "negatywna: sabotaz '$($s.Nazwa)' wylapany przez przypadek '$($s.Przypadek)'" (($w.Z.Count -gt 0) -and $w.Dzialal) "z sabotazem: $(if ($w.Z) { $w.Z -join ' | ' } else { 'NIE ZLAPANY' }); kopia dzialala: $($w.Dzialal)"
  }
} catch {
  Wynik "WYWROTKA TESTU" $false "$($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
} finally {
  foreach ($k in @("MR_TEST_SCENARIUSZ", "MR_TEST_ATRAPA_LOG", "MR_TEST_SPROBUJ", "MR_TEST_ZROB_TERAZ")) { Remove-Item "Env:\$k" -ErrorAction SilentlyContinue }
}

# Po tescie zaden proces (kopia, proces w tle, atrapa, trzymacz) nie moze zostac.
$zostale = Procesy-Testu
foreach ($z in $zostale) { try { Stop-Process -Id $z.ProcessId -Force } catch { Write-Warning "nie ubilem $($z.ProcessId): $($_.Exception.Message)" } }
Wynik "po tescie zaden proces testu nie zostal" ($zostale.Count -eq 0) "pozostalych: $($zostale.Count)"

Write-Host ""
Write-Host "Wynik: $(@($script:wyniki | Where-Object { $_.OK }).Count) z $($script:wyniki.Count) TAK. Pliki robocze: $tmp"
if (@($script:wyniki | Where-Object { -not $_.OK }).Count -gt 0) { exit 1 }
exit 0
