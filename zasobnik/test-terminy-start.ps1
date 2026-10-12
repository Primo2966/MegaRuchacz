# Sprawdzenie odlozenia przypomnien z terminem swiezo po starcie Windows (2026-10-12): najwczesniej
# $MINUT_PO_STARCIE_WINDOWS (5) min po starcie albo wybudzeniu systemu, liczone od startu SYSTEMU, nie
# nadzorcy; nadzorca uruchomiony pozno rusza od razu; w ikonie jednorazowy zegar sprawdza ponownie
# zaraz po uplywie tych minut (nie przy nastepnym dozorze ani o pelnej godzinie); tryb -Raz zegara
# nie planuje; kazde odlozenie ma zdanie w dzienniku nadzorcy.
#   powershell -ExecutionPolicy Bypass -File zasobnik\test-terminy-start.ps1 [-Zrodlo <repo>] [-Zostaw]
# Czas startu systemu jest wstrzykiwany (parametr Czy-Sprawdzac-Terminy, a w sciezce dozoru podmieniona
# Start-Systemu) - prawdziwy odczyt idzie raz, tylko do sprawdzenia, ze cos zwraca. Wszystko na kopii
# kodu zasobnik\ w katalogu tymczasowym, sztucznym katalogu domowym i atrapie zasobnik\terminy.ps1,
# ktora tylko zapisuje, ze ja wolano (Odpal-W-Tle: conhost --headless, bez okna). Przebiegi w osobnych
# procesach bez okna konsoli; po kazdym test czeka, az zniknie kazdy proces z katalogiem testu.
# Sabotaze na kopii kodu - kazdy MUSI zostac zlapany (co najmniej jedna z jego prob pada):
#   S1 bez odlozenia, S2 zegar do pelnej godziny zamiast 5 min, S3 bez zegara (czeka na nastepny dozor),
#   S4 liczone od startu nadzorcy zamiast systemu, S5 odlozenie bez wpisu w dzienniku.
param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Zostaw
)
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { Write-Warning "konsola bez UTF-8: $($_.Exception.Message)" }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("test-terminy-start-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$UTF8 = New-Object System.Text.UTF8Encoding($false)
$UTF8BOM = New-Object System.Text.UTF8Encoding($true)
# Jeden przebieg (z czekaniem na zegar ~3 s, a w sabotazu "pelna godzina" do limitu czekania) miesci sie
# z zapasem w 120 s; dluzej = zwis, ubijamy i liczymy jako porazke.
$LIMIT_PRZEBIEGU_S = 120
$CZEKAJ_NA_PROCESY_S = 30

$script:wyniki = @()
function Wynik($nazwa, $ok, $opis) {
  $script:wyniki += [pscustomobject]@{ Test = $nazwa; OK = [bool]$ok; Opis = $opis }
  $z = "NIE"; if ($ok) { $z = "TAK" }
  Write-Host ("[{0}] {1} - {2}" -f $z, $nazwa, $opis)
}

# ------------------------------------------------------------------ przebieg (osobny proces)
# Wypisuje "WYNIK|TAK/NIE|<id>|<opis>" na kazda probe. Kod brany z -Kod (kopia zasobnik\).
$przebieg = @'
param([string]$Kod, [string]$ZrodloAtrapa, [string]$Dom, [string]$LogTerminow)
$ErrorActionPreference = "Stop"
function P([string]$id, $ok, [string]$opis) { $z = "NIE"; if ($ok) { $z = "TAK" }; Write-Output ("WYNIK|{0}|{1}|{2}" -f $z, $id, (($opis -replace '[\r\n|]+', ' ').Trim())) }
function Dziennik { $p = Join-Path $Dom ".claude\.megaruchacz-zasobnik.log"; if (Test-Path -LiteralPath $p) { return [System.IO.File]::ReadAllText($p) }; return "" }
function Start-Atrapa([double]$minutTemu, [string]$co = "starcie", [datetime]$od = [datetime]::Now) {
  return [pscustomobject]@{ Kiedy = $od.AddMinutes(-$minutTemu); Co = $co; Skad = "atrapa testu"; Blad = "" }
}
try {
  Add-Type -AssemblyName System.Windows.Forms
  $script:ModulyOkna = @{}
  . (Join-Path $Kod "zasobnik\stan-nadzorcy.ps1")
  Ustaw-Nadzorce $ZrodloAtrapa $Dom $false
  . (Join-Path $Kod "zasobnik\nadzorca\dozor.ps1")

  # --- A. sama decyzja, start wstrzykniety parametrem; "teraz" = dzis 10:00 (w godzinach 8-20)
  $t = [datetime]::Today.AddHours(10)
  $script:NadzTerminyOstatnio = $null
  $c = Czy-Sprawdzac-Terminy $t (Start-Atrapa 1 "starcie" $t)
  P "A1" ((-not $c.Ruszac) -and ($c.Odlozone -eq $t.AddMinutes(4)) -and ($c.Powod -like "terminy odlozone do 10:04 - 5 min po starcie Windows*")) "swiezy start (1 min): odlozone do 10:04 - Ruszac=$($c.Ruszac) Odlozone=$($c.Odlozone) Powod=$($c.Powod)"
  $c = Czy-Sprawdzac-Terminy $t (Start-Atrapa (4 + 59 / 60) "starcie" $t)
  P "A2" ((-not $c.Ruszac) -and $c.Odlozone) "4 min 59 s po starcie: jeszcze odlozone - Ruszac=$($c.Ruszac) Powod=$($c.Powod)"
  $c = Czy-Sprawdzac-Terminy $t (Start-Atrapa 5 "starcie" $t)
  P "A3" ($c.Ruszac -and (-not $c.Odlozone)) "rowno 5 min po starcie: rusza - Ruszac=$($c.Ruszac) Powod=$($c.Powod)"
  $c = Czy-Sprawdzac-Terminy $t (Start-Atrapa 120 "starcie" $t)
  P "A4" ($c.Ruszac -and (-not $c.Odlozone) -and ($c.Powod -like "pierwszy przebieg*")) "nadzorca wstal po 2 h pracy komputera: rusza od razu - Ruszac=$($c.Ruszac) Powod=$($c.Powod)"
  $script:NadzTerminyOstatnio = $t.AddMinutes(-90)
  $c = Czy-Sprawdzac-Terminy $t (Start-Atrapa 2 "wybudzeniu" $t)
  P "A5" ((-not $c.Ruszac) -and ($c.Powod -like "*5 min po wybudzeniu Windows*")) "godzinny przebieg 2 min po wybudzeniu: odlozony - Ruszac=$($c.Ruszac) Powod=$($c.Powod)"
  $c = Czy-Sprawdzac-Terminy $t (Start-Atrapa 300 "starcie" $t)
  P "A6" ($c.Ruszac -and (-not $c.Odlozone)) "godzinny przebieg bez swiezego startu: rusza - Ruszac=$($c.Ruszac) Powod=$($c.Powod)"
  $tn = [datetime]::Today.AddHours(22)
  $script:NadzTerminyOstatnio = $tn.AddMinutes(-90)
  $c = Czy-Sprawdzac-Terminy $tn (Start-Atrapa 1 "wybudzeniu" $tn)
  P "A7" ((-not $c.Ruszac) -and (-not $c.Odlozone) -and ($c.Powod -like "poza godzinami*")) "22:00 po wybudzeniu: poza godzinami, bez odlozenia i zegara - Odlozone=$($c.Odlozone) Powod=$($c.Powod)"
  $script:NadzTerminyOstatnio = $null
  $c = Czy-Sprawdzac-Terminy $t ([pscustomobject]@{ Kiedy = $null; Co = "starcie"; Skad = ""; Blad = "ATRAPA-BLEDU-ODCZYTU" })
  P "A8" ($c.Ruszac -and ($c.Powod -like "*ATRAPA-BLEDU-ODCZYTU*")) "start nieczytelny: nie blokuje i mowi o tym - Ruszac=$($c.Ruszac) Powod=$($c.Powod)"
  $s = Start-Systemu
  P "A9" (($s.Kiedy -is [datetime]) -and ($s.Kiedy -le [datetime]::Now) -and ($s.Kiedy -gt [datetime]::Now.AddYears(-5)) -and $s.Skad -and ($s.Co -in @("starcie", "wybudzeniu"))) "prawdziwy odczyt startu Windows: $($s.Kiedy) ($($s.Co); $($s.Skad)) Blad=$($s.Blad)"

  # --- B. sciezka dozoru: start podmieniony (Start-Systemu), atrapa terminy.ps1 w zrodle
  $script:StartAtrapy = $null
  function Start-Systemu { return $script:StartAtrapy }
  # Reszta decyzji dozoru jako atrapy - do sprawdzenia, ze dozor w ikonie (Po-Dozorze) i -Raz (Dozor)
  # przekazuja wlasciwy tryb do Dozor-Terminy.
  function Czy-Ruszac-Cykl($i) { return [pscustomobject]@{ Ruszac = $false; Powod = "atrapa testu" } }
  function Czy-Sprawdzac-Skille($i) { return [pscustomobject]@{ Ruszac = $false; Powod = "atrapa testu" } }
  function Ustaw-Instalacje-Okna($i) { }
  function Po-Kroku($k) { }
  function Nieswiezy-Kawalek($k) { return $false }

  # B1: -Raz (Dozor -> Dozor-Po-Danych bez ikony) - odlozone, zegara nie ma, dziennik mowi oba.
  $script:NadzTerminyOstatnio = $null
  $script:StartAtrapy = Start-Atrapa 1
  $d0 = (Dziennik).Length
  Dozor-Po-Danych ([pscustomobject]@{ Instalacja = $null; Alarmy = @() }) { param($a, $b) }
  $dz = (Dziennik).Substring($d0)
  P "B1" (($null -eq $script:NadzTerminyOstatnio) -and ($null -eq $script:ZegarTerminowPoStarcie) -and ($dz -match "terminy odlozone do \d\d:\d\d - 5 min po starcie Windows") -and ($dz -match "ponownego sprawdzenia nie planuje")) "-Raz: odlozone bez zegara, w dzienniku: $dz"

  # B2: ikona (Po-Dozorze) 4 min 57 s po starcie - odlozone, zegar na ok. 3 s + zapas.
  $script:StartAtrapy = Start-Atrapa (5 - 3 / 60)
  $d0 = (Dziennik).Length
  $t0 = [datetime]::Now
  Po-Dozorze ([pscustomobject]@{ Stan = "ok"; Wynik = [pscustomobject]@{ Instalacja = $null; Alarmy = @() }; Powod = "" })
  $dz = (Dziennik).Substring($d0)
  $iv = -1; if ($script:ZegarTerminowPoStarcie) { $iv = $script:ZegarTerminowPoStarcie.Interval }
  P "B2" (($null -eq $script:NadzTerminyOstatnio) -and ($iv -ge 1000) -and ($iv -le 8000) -and ($dz -match "terminy odlozone do \d\d:\d\d - 5 min po starcie Windows.*sprawdze ponownie o")) "ikona: odlozone, zegar=$iv ms, w dzienniku: $dz"

  # B3: zegar odpala zaraz po uplywie 5 min i rusza terminy (atrapa terminy.ps1 zapisuje wolanie).
  $do = [datetime]::Now.AddSeconds(15)
  while (([datetime]::Now -lt $do) -and ($null -eq $script:NadzTerminyOstatnio)) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
  $sek = ([datetime]::Now - $t0).TotalSeconds
  $do = [datetime]::Now.AddSeconds(15)
  while (([datetime]::Now -lt $do) -and -not (Test-Path -LiteralPath $LogTerminow)) { Start-Sleep -Milliseconds 200 }
  $wol = ""; if (Test-Path -LiteralPath $LogTerminow) { $wol = [System.IO.File]::ReadAllText($LogTerminow) }
  $dz = (Dziennik).Substring($d0)
  P "B3" (($null -ne $script:NadzTerminyOstatnio) -and ($sek -ge 2) -and ($sek -le 10) -and ($null -eq $script:ZegarTerminowPoStarcie) -and ($dz -match "minelo 5 min po starcie Windows") -and ($wol -match [regex]::Escape("-Zrodlo $ZrodloAtrapa"))) ("zegar ruszyl terminy po {0:N1} s; zegar sprzatniety={1}; atrapa terminy.ps1: {2}; dziennik: {3}" -f $sek, ($null -eq $script:ZegarTerminowPoStarcie), $wol.Trim(), $dz)

  # B4: nadzorca uruchomiony 2 h po starcie Windows - rusza od razu, bez zegara.
  if ($script:ZegarTerminowPoStarcie) { $script:ZegarTerminowPoStarcie.Stop(); $script:ZegarTerminowPoStarcie = $null }
  $script:NadzTerminyOstatnio = $null
  $script:StartAtrapy = Start-Atrapa 120
  $d0 = (Dziennik).Length
  Dozor-Terminy $true
  $dz = (Dziennik).Substring($d0)
  P "B4" (($null -ne $script:NadzTerminyOstatnio) -and ($null -eq $script:ZegarTerminowPoStarcie) -and ($dz -match "sprawdzam przypomnienia z terminem")) "pozny start nadzorcy: rusza od razu, w dzienniku: $dz"
  $wyw = @($script:NadzWywrotki)
  P "B5" ($wyw.Count -eq 0) "zadnej wywrotki w przebiegu: $($wyw -join ' || ')"
} catch {
  P "PRZEBIEG" $false "wywrotka przebiegu: $($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
}
'@
$plikPrzebiegu = Join-Path $tmp "przebieg.ps1"
[System.IO.File]::WriteAllText($plikPrzebiegu, $przebieg, $UTF8BOM)
$WSZYSTKIE = @("A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "B1", "B2", "B3", "B4", "B5")

# Kopia kodu: zasobnik\stan-nadzorcy.ps1 i zasobnik\nadzorca\ (stan-nadzorcy laduje moduly z nadzorca\ obok siebie).
function Kopia-Kodu([string]$nazwa) {
  $k = Join-Path $tmp "kod-$nazwa"
  New-Item -ItemType Directory -Force -Path (Join-Path $k "zasobnik") | Out-Null
  Copy-Item -LiteralPath (Join-Path $Zrodlo "zasobnik\stan-nadzorcy.ps1") -Destination (Join-Path $k "zasobnik")
  Copy-Item -LiteralPath (Join-Path $Zrodlo "zasobnik\nadzorca") -Destination (Join-Path $k "zasobnik") -Recurse
  return $k
}
# Podmiana w kopii; kotwica musi stac dokladnie raz - inaczej sabotaz bylby pusty i "zlapany" za darmo.
function Sabotuj([string]$kod, [string]$plik, [string]$co, [string]$naCo) {
  $p = Join-Path $kod $plik
  $txt = [System.IO.File]::ReadAllText($p)
  $ile = ([regex]::Matches($txt, [regex]::Escape($co))).Count
  if ($ile -ne 1) { throw "sabotaz: kotwica w $plik stoi $ile razy (ma raz): $co" }
  [System.IO.File]::WriteAllText($p, $txt.Replace($co, $naCo), $UTF8BOM)
}

function Procesy-Testu {
  return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($tmp) -and $_.ProcessId -ne $PID })
}
function Czekaj-Na-Procesy {
  $do = (Get-Date).AddSeconds($CZEKAJ_NA_PROCESY_S)
  while (((Get-Date) -lt $do) -and (@(Procesy-Testu).Count -gt 0)) { Start-Sleep -Milliseconds 300 }
  foreach ($p in @(Procesy-Testu)) {
    try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; Write-Host "ubity zalegly proces $($p.ProcessId): $($p.CommandLine)" }
    catch { Write-Host "nie ubilem procesu $($p.ProcessId): $($_.Exception.Message)" }
  }
}

# Jeden przebieg na danej kopii kodu: wlasny dom i wlasne zrodlo z atrapa terminy.ps1. Zwraca slownik id -> wynik.
function Przebieg([string]$nazwa, [string]$kod) {
  $baza = Join-Path $tmp "run-$nazwa"
  $dom = Join-Path $baza "dom"
  $zr = Join-Path $baza "zrodlo"
  New-Item -ItemType Directory -Force -Path (Join-Path $dom ".claude\mr"), (Join-Path $zr "zasobnik") | Out-Null
  $log = Join-Path $baza "terminy-wolania.log"
  [System.IO.File]::WriteAllText((Join-Path $zr "zasobnik\terminy.ps1"),
    "Add-Content -LiteralPath '$log' -Value (`$args -join ' ')`r`n", $UTF8BOM)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$plikPrzebiegu`" -Kod `"$kod`" -ZrodloAtrapa `"$zr`" -Dom `"$dom`" -LogTerminow `"$log`""
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $pr = [System.Diagnostics.Process]::Start($psi)
  $zadWy = $pr.StandardOutput.ReadToEndAsync()
  $zadBl = $pr.StandardError.ReadToEndAsync()
  $r = @{}
  if (-not $pr.WaitForExit($LIMIT_PRZEBIEGU_S * 1000)) {
    try { $pr.Kill() } catch { Write-Host "nie ubilem przebiegu ${nazwa}: $($_.Exception.Message)" }
    $r["PRZEBIEG"] = [pscustomobject]@{ OK = $false; Opis = "przebieg $nazwa przekroczyl $LIMIT_PRZEBIEGU_S s" }
  }
  $pr.WaitForExit()
  foreach ($l in @("$($zadWy.Result)" -split '\r?\n')) {
    if ($l -match '^WYNIK\|(TAK|NIE)\|([^|]+)\|(.*)$') { $r[$Matches[2]] = [pscustomobject]@{ OK = ($Matches[1] -eq "TAK"); Opis = $Matches[3] } }
  }
  if ("$($zadBl.Result)".Trim()) { $r["STDERR"] = [pscustomobject]@{ OK = $false; Opis = ("$($zadBl.Result)" -replace '\s+', ' ').Trim() } }
  Czekaj-Na-Procesy
  return $r
}

try {
  # ------------------------------------------------------------- wlasciwy przebieg
  $r = Przebieg "czysty" (Kopia-Kodu "czysty")
  foreach ($id in $WSZYSTKIE) {
    if ($r.ContainsKey($id)) { Wynik $id $r[$id].OK $r[$id].Opis } else { Wynik $id $false "proba nie wykonala sie (przebieg urwany?)" }
  }
  foreach ($id in @("PRZEBIEG", "STDERR")) { if ($r.ContainsKey($id)) { Wynik $id $false $r[$id].Opis } }

  # ------------------------------------------------------------- sabotaze
  $sabotaze = @(
    @{ N = "S1 bez odlozenia"; Plik = "zasobnik\nadzorca\stan-terminy.ps1"; Co = 'if ($teraz -lt $od) {'; NaCo = 'if ($false) {'; Lapie = @("A1", "A2", "A5", "B1", "B2") },
    @{ N = "S2 zegar do pelnej godziny"; Plik = "zasobnik\nadzorca\dozor.ps1"
       Co = '$ms = [int][math]::Max(1000, [math]::Ceiling(($kiedy - [datetime]::Now)'
       NaCo = '$kiedy = $kiedy.Date.AddHours($kiedy.Hour + 1); $ms = [int][math]::Max(1000, [math]::Ceiling(($kiedy - [datetime]::Now)'; Lapie = @("B2", "B3") },
    @{ N = "S3 bez zegara (czeka na nastepny dozor)"; Plik = "zasobnik\nadzorca\dozor.ps1"
       Co = 'Zaplanuj-Terminy-Po-Starcie ([datetime]$ct.Odlozone)'; NaCo = '$null = $ct.Odlozone'; Lapie = @("B2", "B3") },
    @{ N = "S4 od startu nadzorcy zamiast systemu"; Plik = "zasobnik\nadzorca\stan-terminy.ps1"
       Co = 'if ($null -eq $s) { $s = Start-Systemu }'
       NaCo = '$s = [pscustomobject]@{ Kiedy = [datetime]::Now; Co = "starcie"; Skad = "start nadzorcy"; Blad = "" }'; Lapie = @("A1", "A2", "A3", "A4", "A5", "A6", "B4") },
    @{ N = "S5 odlozenie bez wpisu w dzienniku"; Plik = "zasobnik\nadzorca\dozor.ps1"
       Co = 'Notuj "dozor: $($ct.Powod); sprawdze ponownie o'; NaCo = '$null = "dozor: $($ct.Powod); sprawdze ponownie o'; Lapie = @("B2") }
  )
  $i = 0
  foreach ($s in $sabotaze) {
    $i++
    $kod = Kopia-Kodu "sabotaz$i"
    Sabotuj $kod $s.Plik $s.Co $s.NaCo
    $rs = Przebieg "sabotaz$i" $kod
    $padly = @($s.Lapie | Where-Object { $rs.ContainsKey($_) -and (-not $rs[$_].OK) })
    Wynik "sabotaz: $($s.N)" ($padly.Count -gt 0) "padly proby: $(if ($padly) { $padly -join ', ' } else { 'ZADNA - sabotaz przeszedl niezauwazony' })"
  }
} catch {
  Wynik "test bez wywrotki" $false "$($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
} finally {
  Czekaj-Na-Procesy
}
Wynik "sprzatanie: zadnego procesu z katalogu testu" (@(Procesy-Testu).Count -eq 0) ((@(Procesy-Testu) | ForEach-Object { "$($_.ProcessId) $($_.CommandLine)" }) -join ' || ')

$zle = @($script:wyniki | Where-Object { -not $_.OK })
if (-not $Zostaw -and $zle.Count -eq 0) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Host "katalog testu zostaje: $tmp" }
Write-Host ""
Write-Host "Wynik: $(@($script:wyniki).Count - $zle.Count) z $(@($script:wyniki).Count) OK"
if ($zle.Count -gt 0) { exit 1 }
exit 0
