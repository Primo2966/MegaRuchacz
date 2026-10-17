# Proba alarmow pamieci (plan pamieci, krok 2 - 17.10.2026): alarmy widoczne, zero pytan do uzytkownika.
#   1. Rachunek (koszt-pamieci.ps1 -Dane): warstwa stala / biezaca "Co wiem" ponad sufit + 5% daje
#      alarm pamiec-stala / pamiec-biezaca i kod 1; ponad sufit, ale w zapasie 5% - cisza (falszywy alarm
#      jest gorszy niz brak); modul Wiedza wylaczony w rejestrze - cisza (automatu nie ma).
#   2. Pelny raport i -Rozbicie przy przeterminowanych wpisach i pelnej poczekalni NIE prosza
#      uzytkownika o przejrzenie, kasowanie, zatwierdzanie ani odswiezanie daty.
#   3. Okno nadzorcy (stan-po-ludzku.ps1): alarm z .wiedza-stan.txt (alarm / alarm_N /
#      wstrzymane_progiem > 0) trafia do linii o pamieci ("meldunek") na czerwono - takze przy
#      "bez zmian" i przy pliku bez meldunku; wstrzymane_progiem: 0 - cisza.
#   4. Teksty zrodlowe: straznik bez Zglos-Kandydatow, blok Wiedza bez zdan o proponowaniu zapisu,
#      pytaniu o reczne wpisy, przenoszeniu zestawien i "raz dziennie".
# Kazda regula ma probe negatywna (-Sabotaz): kopia zrodla z wycofana zmiana MUSI dac BLAD.
# Wszystko w %TEMP% (katalogi domowe i kopia zrodla); prawdziwe ~\.claude nie jest czytane ani ruszane.
#
# Uzycie:  powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File narzedzia\test-alarmy-pamieci.ps1 [-Zostaw]
# Kod wyjscia: 0 = wszystkie proby (z sabotazami) przeszly, 1 = ktoras nie.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Zostaw,
  # wewnetrzne: przebieg na kopii zrodla z wycofana zmiana - wynik ma byc BLAD
  [string]$TylkoProba = ""
)

$ErrorActionPreference = "Stop"
$T = Join-Path $env:TEMP ("mr-test-alarmy-pamieci-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$script:Zle = 0
$script:Bledy = @()
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Sprawdz([string]$co, [bool]$ok, [string]$szczegol = "") {
  $linia = $(if ($ok) { "OK    " } else { "BLAD  " }) + $co
  if (-not $ok -and $szczegol) { $linia += " -- $szczegol" }
  Write-Host $linia
  if (-not $ok) { $script:Zle++; $script:Bledy += $co }
}
function Zapisz([string]$p, [string]$t) {
  $k = Split-Path -Parent $p
  if (-not (Test-Path -LiteralPath $k)) { New-Item -ItemType Directory -Force -Path $k | Out-Null }
  [System.IO.File]::WriteAllText($p, $t, $Utf8)
}
function Odpal([string]$skrypt, [string[]]$argumenty) {
  $ErrorActionPreference = "Continue"
  $wy = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File $skrypt @argumenty 2>&1
  return [pscustomobject]@{ Kod = $LASTEXITCODE; Tekst = (($wy | ForEach-Object { "$_" }) -join "`n") }
}
function Klucze([string]$tekst) {
  $k = [ordered]@{}
  foreach ($l in ($tekst -split "`r?`n")) {
    $m = [regex]::Match($l, '^\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*:\s*(.*?)\s*$')
    if ($m.Success) { $k[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $k
}
function Tematy-Alarmow($k) {
  $t = @()
  $ile = 0
  if ("$($k['alarmy'])" -match '^\d+$') { $ile = [int]$k['alarmy'] }
  for ($i = 1; $i -le $ile; $i++) { $t += "$($k["alarm.$i.temat"])" }
  return ,$t
}
# Linie po ~100 znakow, razem ok. $znaki znakow (dokladnie liczy rachunek - tu tylko wyraznie
# nad progiem albo wyraznie pod nim, z marginesem wiekszym niz naglowki i znaki konca linii).
function Wpisy([int]$znaki, [string]$data = "") {
  $l = @()
  $n = [int][math]::Ceiling($znaki / 100)
  for ($i = 0; $i -lt $n; $i++) {
    $pre = "- "
    if ($data) { $pre = "- [$data] " }
    $l += ($pre + ("fakt numer $i ").PadRight(100 - $pre.Length, "x"))
  }
  return ($l -join "`n")
}
function Nowy-Dom([string]$nazwa, [int]$stala, [int]$biezaca, [string]$dataBiez = "", [string]$rejestr = "") {
  $dom = Join-Path $T "dom-$nazwa"
  $kc = Join-Path $dom ".claude"
  New-Item -ItemType Directory -Force -Path (Join-Path $kc "wiedza") | Out-Null
  if (-not $dataBiez) { $dataBiez = (Get-Date).ToString("yyyy-MM-dd") }
  $cm = "# Ustalenia globalne`n`n## Co wiem`n`n### O uzytkowniku`n`n" + (Wpisy $stala) +
        "`n`n### Biezace`n`n" + (Wpisy $biezaca $dataBiez) + "`n"
  Zapisz (Join-Path $kc "CLAUDE.md") $cm
  if ($rejestr) { Zapisz (Join-Path $kc "mr\instalacja.json") $rejestr }
  return $dom
}

# ------------------------------------------------------------ zestaw prob (na danym zrodle)
function Proby([string]$Z) {
  $koszt = Join-Path $Z "narzedzia\koszt-pamieci.ps1"
  $tekstKosztu = [System.IO.File]::ReadAllText($koszt)
  $mS = [regex]::Match($tekstKosztu, '(?m)^\$ProgStalej\s*=\s*(\d+)')
  $mB = [regex]::Match($tekstKosztu, '(?m)^\$SufitBiezacych\s*=\s*(\d+)')
  Sprawdz "progi: `$ProgStalej = 16000 i `$SufitBiezacych = 6000 (sama liczba - czyta ja test lore)" (
    $mS.Success -and ([int]$mS.Groups[1].Value -eq 16000) -and $mB.Success -and ([int]$mB.Groups[1].Value -eq 6000))

  # 1a. obie warstwy wyraznie ponad sufit + 5% (16 800 / 6 300)
  $dom = Nowy-Dom "ponad" 17600 6900
  $o = Odpal $koszt @("-KatalogDomowy", $dom, "-Zrodlo", $Z, "-Dane", "-Zwykly", "-Narzedzie", "Claude")
  $k = Klucze $o.Tekst
  $tem = Tematy-Alarmow $k
  Sprawdz "rachunek: stala ponad sufit + 5% -> alarm pamiec-stala" ($tem -contains "pamiec-stala") ("tematy: " + ($tem -join ",") + " | " + $o.Tekst.Substring(0, [Math]::Min(300, $o.Tekst.Length)))
  Sprawdz "rachunek: biezaca ponad sufit + 5% -> alarm pamiec-biezaca" ($tem -contains "pamiec-biezaca") ("tematy: " + ($tem -join ","))
  Sprawdz "rachunek: alarm pamieci podnosi kod wyjscia (1)" ($o.Kod -eq 1) "kod $($o.Kod)"
  $pelny = ""
  for ($i = 1; $i -le $tem.Count; $i++) { if ($tem[$i - 1] -like "pamiec-*") { $pelny += " " + $k["alarm.$i.pelny"] } }
  Sprawdz "rachunek: tresc alarmu mowi o usterce automatu, nie kaze kasowac wpisow" (
    ($pelny -match 'usterka automatu') -and ($pelny -notmatch '(?i)skasuj|przejrzyj|zatwierdz')) $pelny

  # 1b. ponad sufit, ale w zapasie 5% - cisza
  $dom = Nowy-Dom "zapas" 16300 6100
  $o = Odpal $koszt @("-KatalogDomowy", $dom, "-Zrodlo", $Z, "-Dane", "-Zwykly", "-Narzedzie", "Claude")
  $tem = Tematy-Alarmow (Klucze $o.Tekst)
  Sprawdz "rachunek: ponad sufit w zapasie 5% -> bez alarmu pamieci (falszywy alarm gorszy niz brak)" (
    -not ($tem -contains "pamiec-stala") -and -not ($tem -contains "pamiec-biezaca")) ("tematy: " + ($tem -join ","))

  # 1c. modul Wiedza wylaczony - automatu nie ma, alarm nie ma do kogo mowic
  $dom = Nowy-Dom "bez-wiedzy" 17600 6900 "" '{"wersja":1,"moduly":{"wiedza":false}}'
  $o = Odpal $koszt @("-KatalogDomowy", $dom, "-Zrodlo", $Z, "-Dane", "-Zwykly", "-Narzedzie", "Claude")
  $tem = Tematy-Alarmow (Klucze $o.Tekst)
  Sprawdz "rachunek: modul Wiedza wylaczony -> bez alarmu pamieci" (-not ($tem -contains "pamiec-stala")) ("tematy: " + ($tem -join ","))


  # 2. raport i rozbicie bez prosb do uzytkownika (wpisy sprzed miesiaca + pelna poczekalnia)
  $dom = Nowy-Dom "stare" 3000 1500 ((Get-Date).AddDays(-40).ToString("yyyy-MM-dd"))
  $kand = "# Kandydaci`n`n" + ((1..15 | ForEach-Object { "- [ ] fakt $_" }) -join "`n") + "`n"
  Zapisz (Join-Path $dom ".claude\wiedza\kandydaci.md") $kand
  $prosby = '(?i)przejrzyj|skasuj|zatwierdz|odrzuc|odswiez date|przenies najdluzsze|na Twoja decyzje'
  $r = Odpal $koszt @("-KatalogDomowy", $dom, "-Zrodlo", $Z, "-Zwykly")
  $m = [regex]::Match($r.Tekst, $prosby)
  Sprawdz "pelny raport: zadnej prosby o przejrzenie / kasowanie / zatwierdzanie wpisow" ((-not $m.Success) -and ($r.Tekst -match 'Audyt pamieci')) $(if ($m.Success) { "znalezione: " + $r.Tekst.Substring([Math]::Max(0, $m.Index - 80), [Math]::Min(200, $r.Tekst.Length - [Math]::Max(0, $m.Index - 80))) } else { $r.Tekst.Substring(0, [Math]::Min(200, $r.Tekst.Length)) })
  $r = Odpal $koszt @("-KatalogDomowy", $dom, "-Zrodlo", $Z, "-Rozbicie", "-Zwykly")
  $m = [regex]::Match($r.Tekst, $prosby)
  Sprawdz "rozbicie: zadnej prosby o przejrzenie / odswiezenie daty / kasowanie" ((-not $m.Success) -and ($r.Tekst -match 'automat zdejmie')) $(if ($m.Success) { "znalezione: " + $r.Tekst.Substring([Math]::Max(0, $m.Index - 80), [Math]::Min(200, $r.Tekst.Length - [Math]::Max(0, $m.Index - 80))) } else { $r.Tekst.Substring(0, [Math]::Min(300, $r.Tekst.Length)) })

  # 3. okno nadzorcy - linia o pamieci (w osobnym procesie, zeby modul z kopii nie mieszal sie z tym testem)
  $kat = Join-Path $T "okno"
  New-Item -ItemType Directory -Force -Path $kat | Out-Null
  $sk = Join-Path $T "okno.ps1"
  Zapisz $sk (@'
param([string]$Z, [string]$Kat)
$script:NadzModuly = @{}
$script:NadzWiedza = $Kat
function Zanotuj-Wywrotke($co, $e) { Write-Output "WYWROTKA: $co" }
. (Join-Path $Z "zasobnik\nadzorca\stan-podstawy.ps1")
. (Join-Path $Z "zasobnik\nadzorca\stan-po-ludzku.ps1")
$plik = Join-Path $Kat ".wiedza-stan.txt"
$przypadki = [ordered]@{
  "wstrzymane"   = "data: 2026-10-17`r`nwstrzymane_progiem: 13`r`nmeldunek: bez zmian`r`n"
  "zero"         = "data: 2026-10-17`r`nwstrzymane_progiem: 0`r`nmeldunek: bez zmian`r`n"
  "alarm"        = "data: 2026-10-17`r`nalarm: stala pelna samych przypietych`r`nalarm_2: drugi alarm`r`nmeldunek: zmienilem 1, uspilem 0, obudzilem 0, awansowalem 0 - cofniecie: x`r`nmeldunek_1: Z-261017-1 zmienilem: a -> b`r`n"
  "bez-meldunku" = "data: 2026-10-17`r`nwstrzymane_progiem: 2`r`n"
  "smieci"       = "data: 2026-10-17`r`nwstrzymane_progiem: duzo`r`nmeldunek: bez zmian`r`n"
}
foreach ($n in $przypadki.Keys) {
  [System.IO.File]::WriteAllText($plik, $przypadki[$n], (New-Object System.Text.UTF8Encoding($false)))
  $o = Opis-Zmian-Pamieci (Stan-Zmian-Pamieci)
  $linia = ($o.Linia -replace '[^\x20-\x7E]', '?')
  Write-Output ("WYNIK|$n|" + [int][bool]$o.Uwaga + "|" + $linia)
}
'@)
  $w = Odpal $sk @("-Z", $Z, "-Kat", $kat)
  $wyn = @{}
  foreach ($l in ($w.Tekst -split "`n")) {
    $p = $l.Split("|")
    if ($p.Count -ge 4 -and $p[0] -eq "WYNIK") { $wyn[$p[1]] = [pscustomobject]@{ Uwaga = ($p[2] -eq "1"); Linia = ($p[3..($p.Count - 1)] -join "|") } }
  }
  $x = $wyn["wstrzymane"]
  Sprawdz "okno: wstrzymane_progiem 13 przy 'bez zmian' -> UWAGA w linii o pamieci, na czerwono" (
    $x -and $x.Uwaga -and ($x.Linia -match 'UWAGA: 13 ') -and ($x.Linia -match 'bez zmian')) $(if ($x) { $x.Linia } else { $w.Tekst })
  $x = $wyn["zero"]
  Sprawdz "okno: wstrzymane_progiem 0 -> bez UWAGA (cisza przy czystym stanie)" ($x -and (-not $x.Uwaga) -and ($x.Linia -notmatch 'UWAGA')) $(if ($x) { $x.Linia } else { $w.Tekst })
  $x = $wyn["alarm"]
  Sprawdz "okno: alarm i alarm_N od modulu pamieci -> oba w linii, obok zmian" (
    $x -and $x.Uwaga -and ($x.Linia -match 'stala pelna samych przypietych') -and ($x.Linia -match 'drugi alarm') -and ($x.Linia -match '1 zmiana')) $(if ($x) { $x.Linia } else { $w.Tekst })
  $x = $wyn["bez-meldunku"]
  Sprawdz "okno: plik bez meldunku (nie wiem, co sie zmienilo) -> alarm i tak widoczny" (
    $x -and $x.Uwaga -and ($x.Linia -match 'UWAGA: 2 ')) $(if ($x) { $x.Linia } else { $w.Tekst })
  $x = $wyn["smieci"]
  Sprawdz "okno: nieczytelna liczba wstrzymanych -> zdanie 'nie umiem odczytac', nie cisza" (
    $x -and $x.Uwaga -and ($x.Linia -match 'nie umiem odczyta')) $(if ($x) { $x.Linia } else { $w.Tekst })

  # 4. teksty zrodlowe
  $stTekst = [System.IO.File]::ReadAllText((Join-Path $Z "narzedzia\straznik-zasad.ps1"))
  $bledy = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseInput($stTekst, [ref]$null, [ref]$bledy)
  $funkcje = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
  $wolania = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq "Zglos-Kandydatow" }, $true))
  Sprawdz "straznik: nie ma Zglos-Kandydatow (ani funkcji, ani wolania) i prosby 'na Twoja decyzje'" (
    (-not ($funkcje -contains "Zglos-Kandydatow")) -and ($wolania.Count -eq 0) -and ($stTekst -notmatch 'na Twoja decyzje - powiedz')) "funkcja: $($funkcje -contains 'Zglos-Kandydatow'), wolan: $($wolania.Count)"
  Sprawdz "straznik: skladnia bez bledow" (@($bledy).Count -eq 0) (@($bledy | ForEach-Object { $_.Message }) -join "; ")

  $zw = [System.IO.File]::ReadAllText((Join-Path $Z "zasady-wiedza.md"), $Utf8)
  $i = $zw.IndexOf("TREŚĆ DO WSTRZYKNIĘCIA")
  $blok = $(if ($i -ge 0) { $zw.Substring($i) } else { $zw })
  $zakazane = @("zaproponuj zapis", "przy ręcznym zapytaj", "przenieś najdłuższe", "raz dziennie", "8 000")
  $jest = @($zakazane | Where-Object { $blok.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
  Sprawdz "blok Wiedza: bez proponowania zapisu, pytania o reczne wpisy, przenoszenia zestawien, 'raz dziennie' i starego sufitu" ($jest.Count -eq 0) ("zostalo: " + ($jest -join " | "))
  Sprawdz "blok Wiedza: nowe sufity 16 000 i 6 000 oraz usypianie" (
    ($blok -match '16 000') -and ($blok -match '6 000') -and ($blok -match 'usypia')) ""
}

# ------------------------------------------------------------ sabotaze (proba negatywna)
# Kazdy: kopia zrodla z jedna zmiana wycofana; przebieg na niej MUSI dac BLAD w podanej probie.
$SABOTAZE = @(
  @{ Nazwa = "alarm pamieci wyciety z alarmy.ps1"; Plik = "narzedzia\koszt\alarmy.ps1"
     Z = '      if ($wp.Znaki -le $wp.Prog) { continue }'; Na = '      continue'
     Oczekiwany = "rachunek: stala ponad sufit + 5% -> alarm pamiec-stala" },
  @{ Nazwa = "prog alarmu bez zapasu 5%"; Plik = "narzedzia\koszt-pamieci.ps1"
     Z = '$ProcPonadSufit = 5'; Na = '$ProcPonadSufit = 0'
     Oczekiwany = "rachunek: ponad sufit w zapasie 5% -> bez alarmu pamieci (falszywy alarm gorszy niz brak)" },
  @{ Nazwa = "alarm mimo wylaczonego modulu Wiedza"; Plik = "narzedzia\koszt\alarmy.ps1"
     Z = 'if ($w.Jest -and (-not $script:WiedzaWylaczona)) {'; Na = 'if ($w.Jest) {'
     Oczekiwany = "rachunek: modul Wiedza wylaczony -> bez alarmu pamieci" },
  @{ Nazwa = "stara prosba w rozbiciu"; Plik = "narzedzia\koszt\tryb-rozbicie.ps1"
     Z = '"Starsze niz $DniWaznosci dni: $(Ile-Wpisow $wpisyStare.Count) - automat zdejmie je sam przy najblizszym przebiegu (przebiegi nie sa codzienne)."'
     Na = '"Do zrobienia: $(Ile-Wpisow $wpisyStare.Count) starsze niz $DniWaznosci dni - przejrzyj albo odswiez date."'
     Oczekiwany = "rozbicie: zadnej prosby o przejrzenie / odswiezenie daty / kasowanie" },
  @{ Nazwa = "stara prosba o poczekalnie w raporcie"; Plik = "narzedzia\koszt\raport-pelny.ps1"
     Z = '    Linia "  Faktow w poczekalni: $kandydaci - automat rozstrzyga je sam, bez udzialu uzytkownika."'
     Na = '    Linia "  Faktow czeka na zatwierdzenie: $kandydaci"'
     Oczekiwany = "pelny raport: zadnej prosby o przejrzenie / kasowanie / zatwierdzanie wpisow" },
  @{ Nazwa = "okno nie czyta wstrzymanych"; Plik = "zasobnik\nadzorca\stan-po-ludzku.ps1"
     Z = '  if ($k.Contains("wstrzymane_progiem")) {'; Na = '  if ($false) {'
     Oczekiwany = "okno: wstrzymane_progiem 13 przy 'bez zmian' -> UWAGA w linii o pamieci, na czerwono" },
  @{ Nazwa = "okno gubi alarm przy pliku bez meldunku"; Plik = "zasobnik\nadzorca\stan-po-ludzku.ps1"
     Z = "  `$z.Alarmy = @(Alarmy-Pamieci `$k)`r`n  if (-not `$k.Contains(""meldunek"")) {"
     Na = "  if (-not `$k.Contains(""meldunek"")) {`r`n    return `$z`r`n  }`r`n  `$z.Alarmy = @(Alarmy-Pamieci `$k)`r`n  if (`$false) {"
     Oczekiwany = "okno: plik bez meldunku (nie wiem, co sie zmienilo) -> alarm i tak widoczny" },
  @{ Nazwa = "Zglos-Kandydatow wraca do straznika"; Plik = "narzedzia\straznik-zasad.ps1"
     Z = '  if (-not (Modul-Wylaczony "wiedza")) {'
     Na = "  function Zglos-Kandydatow { Write-Host ""MegaRuchacz: 3 faktow czeka na Twoja decyzje - powiedz 'pokaz fakty', zeby je przejrzec."" }`r`n  if (-not (Modul-Wylaczony ""wiedza"")) {`r`n    try { Zglos-Kandydatow } catch { }"
     Oczekiwany = "straznik: nie ma Zglos-Kandydatow (ani funkcji, ani wolania) i prosby 'na Twoja decyzje'" },
  @{ Nazwa = "blok Wiedza znow kaze proponowac zapis"; Plik = "zasady-wiedza.md"
     Z = 'Sufity, wygasanie i usypianie pilnuje automat'; Na = 'Sam zaproponuj zapis w stałej. Sufity, wygasanie i usypianie pilnuje automat'
     Oczekiwany = "blok Wiedza: bez proponowania zapisu, pytania o reczne wpisy, przenoszenia zestawien, 'raz dziennie' i starego sufitu" }
)

function Kopia-Zrodla([string]$cel) {
  New-Item -ItemType Directory -Force -Path $cel, (Join-Path $cel "zasobnik") | Out-Null
  Copy-Item -Recurse (Join-Path $Zrodlo "narzedzia") (Join-Path $cel "narzedzia")
  Copy-Item -Recurse (Join-Path $Zrodlo "zasobnik\nadzorca") (Join-Path $cel "zasobnik\nadzorca")
  New-Item -ItemType Directory -Force -Path (Join-Path $cel "lore\lore") | Out-Null
  foreach ($f in @("facts.py", "index.py", "search.py", "mining.py")) {
    $p = Join-Path $Zrodlo "lore\lore\$f"
    if (Test-Path -LiteralPath $p) { Copy-Item $p (Join-Path $cel "lore\lore\$f") }
  }
  foreach ($k in @("szablony-codex", "szablony-global")) { Copy-Item -Recurse (Join-Path $Zrodlo $k) (Join-Path $cel $k) }
  Copy-Item (Join-Path $Zrodlo "zasady-wiedza.md") (Join-Path $cel "zasady-wiedza.md")
}

try {
  New-Item -ItemType Directory -Force -Path $T | Out-Null
  if ($TylkoProba) {
    # przebieg potomny: kopia zrodla juz zsabotowana, wypisz BLEDY:
    Proby $TylkoProba
    Write-Output ("BLEDY:" + ($script:Bledy -join "||"))
    exit 0
  }

  Write-Host "--- proby na zrodle $Zrodlo"
  $czyste = Join-Path $T "zrodlo"
  Kopia-Zrodla $czyste
  Proby $czyste

  Write-Host "--- sabotaze (kazdy ma dac BLAD w swojej probie)"
  $nr = 0
  foreach ($s in $SABOTAZE) {
    $nr++
    $kz = Join-Path $T "sabotaz-$nr"
    Kopia-Zrodla $kz
    $p = Join-Path $kz $s.Plik
    $bajty = [System.IO.File]::ReadAllBytes($p)
    $bom = ($bajty.Length -ge 3 -and $bajty[0] -eq 0xEF -and $bajty[1] -eq 0xBB -and $bajty[2] -eq 0xBF)
    $tx = [System.IO.File]::ReadAllText($p, $Utf8)
    $ile = ([regex]::Matches($tx, [regex]::Escape($s.Z))).Count
    if ($ile -ne 1) { Sprawdz "sabotaz '$($s.Nazwa)': kotwica w $($s.Plik)" $false "kotwica wystepuje $ile razy"; continue }
    $tx = $tx.Replace($s.Z, $s.Na)
    [System.IO.File]::WriteAllText($p, $tx, (New-Object System.Text.UTF8Encoding($bom)))
    $w = Odpal $PSCommandPath @("-Zrodlo", $Zrodlo, "-TylkoProba", $kz)
    $m = [regex]::Match($w.Tekst, '(?m)^BLEDY:(.*)$')
    $zlapane = $m.Success -and (@($m.Groups[1].Value -split '\|\|') -contains $s.Oczekiwany)
    Sprawdz "sabotaz '$($s.Nazwa)' zlapany" $zlapane $(if ($m.Success) { "bledy: " + $m.Groups[1].Value } else { $w.Tekst.Substring(0, [Math]::Min(400, $w.Tekst.Length)) })
  }
} finally {
  if (-not $Zostaw -and -not $TylkoProba) { Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue }
  elseif ($TylkoProba) { Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($TylkoProba) { exit 0 }
Write-Host ""
if ($script:Zle -gt 0) { Write-Host "WYNIK: $($script:Zle) BLEDOW"; exit 1 }
Write-Host "WYNIK: wszystkie proby przeszly"
exit 0
