# Proba kopii zapasowej (narzedzia\kopia-zapasowa.ps1) po przebudowie z 17.10.2026: od 05.10
# kazdy przebieg konczyl sie BLEDEM, bo w C:\dev\tools\pgdata dzialal Postgres, a stare kopie
# nie byly nigdy kasowane (~36 GB w 16 dni). Sprawdza:
#   B. katalog danych bazy (Postgres) pominiety jako informacja, nie blad; plik zablokowany przez
#      inny proces = ostrzezenie z nazwa, reszta kopii idzie, stan OK; zablokowany od -Trzymaj dni
#      = linia BLAD (przyczyna=PLIKI, bez blad=); po zwolnieniu plik wchodzi do kopii
#   R. rotacja: zostaje -Trzymaj ostatnich dni, starszy dzien wlany do pelnej (nowsza wersja
#      wygrywa), dzien sprzed nowszej pelnej skasowany, starsza pelna skasowana dopiero po
#      wypadnieciu nowszej z okna; nic innego w folderze kopii nie ruszone; folder kopii
#      usuniety przy zachowanym indeksie = nowa pelna kopia (nie dziurawy przyrost)
#   M. brak miejsca = stan=BLAD, przyczyna=BRAK_MIEJSCA, linia ALARM, nic nie skopiowane;
#      brak folderu nad celem = przyczyna=BRAK_CELU; okno nadzorcy: brak miejsca to sprawa pilna
#   S. proby negatywne: sabotaze na kopii skryptu kopii - kazdy MUSI byc zlapany.
# Wszystko w %TEMP% (sztuczny dom, sztuczny cel) - prawdziwy G:\ ani dom nie sa ruszane.
#   powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File narzedzia\test-kopia-rotacja.ps1 [-Zostaw]
# Kod wyjscia: 0 = wszystkie proby przeszly, 1 = ktoras nie.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Zostaw
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 }
catch { Write-Host "UWAGA: konsola nie przestawila sie na UTF-8 ($($_.Exception.Message))" }
$T = Join-Path $env:TEMP ("mr-kr-" + (Get-Date -Format "MMdd-HHmmss"))
$script:Zle = 0
$bezBom = New-Object System.Text.UTF8Encoding($false)

function Sprawdz([string]$co, [bool]$ok, [string]$szczegol = "") {
  $linia = $(if ($ok) { "OK    " } else { "BLAD  " }) + $co
  if ($szczegol -and -not $ok) { $linia += " -- $szczegol" }
  Write-Host $linia
  if (-not $ok) { $script:Zle++ }
}

function Odpal([string]$skrypt, [string[]]$argumenty) {
  $ErrorActionPreference = "Continue"   # stderr skryptu to tresc do sprawdzenia, nie wyjatek
  $wy = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File $skrypt @argumenty 2>&1
  return [pscustomobject]@{ Kod = $LASTEXITCODE; Tekst = (($wy | ForEach-Object { "$_" }) -join "`n") }
}

function Tekst([string]$p, [string]$t, $czas = $null) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
  [System.IO.File]::WriteAllText($p, $t, $bezBom)
  if ($czas) { [System.IO.File]::SetLastWriteTime($p, $czas) }
}
function Czytaj([string]$p) { if (Test-Path -LiteralPath $p) { return [System.IO.File]::ReadAllText($p) } return "" }
function Linie-Stanu([string]$stan, [string]$wzor) { return @($stan -split "\r?\n" | Where-Object { $_ -match $wzor }) }
function W-Kopii([string]$kat, [string]$p) { return $kat + "\C" + $p.Substring(2) }   # C:\x -> <kat>\C\x
function Dni-Zmian([string]$cel) {
  if (-not (Test-Path -LiteralPath "$cel\zmiany")) { return "" }
  return ((@(Get-ChildItem -LiteralPath "$cel\zmiany" -Directory | ForEach-Object { $_.Name }) | Sort-Object) -join ",")
}

# ---------------------------------------------------------------- B. bazy i blokady
function Scen-Blokady([string]$skrypt, [string]$kat) {
  $H = Join-Path $kat "dom"; $cel = Join-Path $kat "cel"; $proj = Join-Path $H "proj"
  New-Item -ItemType Directory -Force -Path $cel | Out-Null
  Tekst "$proj\a.txt" "zwykly plik projektu"
  Tekst "$proj\zablokowany.txt" "plik trzymany przez inny program"
  # katalog danych dzialajacego Postgresa - jak C:\dev\tools\pgdata
  Tekst "$proj\pgdata\PG_VERSION" "16"
  Tekst "$proj\pgdata\postmaster.pid" "1234"
  Tekst "$proj\pgdata\postgresql.conf" "port = 5432"
  Tekst "$proj\pgdata\base\1\1259" "strona tabeli"
  $stanP = "$H\.claude\mr\kopia-stan.txt"
  $wsp = @("-KatalogDomowy", $H, "-Zrodla", $proj, "-Cel", $cel, "-Trzymaj", "7")
  $p = [ordered]@{}
  $blokada = [System.IO.File]::Open("$proj\zablokowany.txt", 'Open', 'Read', 'None')
  try {
    $r1 = Odpal $skrypt ($wsp + @("-Data", "2026-10-01"))
    $s1 = Czytaj $stanP
    $w1 = "$cel\pelna-2026-10-01"
    $p["Postgres pominiety bez bledu: kod 0, stan=OK, linia BAZA z nazwa katalogu"] = @((($r1.Kod -eq 0) -and ($s1 -match '(?m)^stan=OK\r?$') -and
      ((Linie-Stanu $s1 '^BAZA DANYCH pominieta').Count -eq 1) -and ($s1 -match [regex]::Escape("$proj\pgdata")) -and ((Linie-Stanu $s1 '^BLAD').Count -eq 0)), "kod $($r1.Kod); stan: $s1 || $($r1.Tekst)")
    $p["pliki bazy nie trafiaja do kopii, reszta projektu tak"] = @(((-not (Test-Path -LiteralPath (W-Kopii $w1 "$proj\pgdata"))) -and (Test-Path -LiteralPath (W-Kopii $w1 "$proj\a.txt"))), "")
    $wu = @(Linie-Stanu $s1 '^W UZYCIU')
    $p["zablokowany plik = ostrzezenie z nazwa, stan OK, w_uzyciu=1"] = @((($wu.Count -eq 1) -and ($wu[0] -like "*$proj\zablokowany.txt") -and ($s1 -match '(?m)^w_uzyciu=1\r?$') -and
      ($s1 -match '(?m)^bledy=0\r?$') -and ($s1 -match '(?m)^przyczyna=\r?$')), "stan: $s1")
    $p["zablokowany plik wymieniony w dzienniku"] = @(((Czytaj "$cel\dziennik.txt") -match 'W UZYCIU[^\r\n]*zablokowany\.txt'), "")
    $r2 = Odpal $skrypt ($wsp + @("-Data", "2026-10-05"))
    $s2 = Czytaj $stanP
    $p["blokada od 4 dni (< 7): dalej stan OK, linia mowi od kiedy"] = @((($r2.Kod -eq 0) -and ($s2 -match '(?m)^stan=OK\r?$') -and
      ((Linie-Stanu $s2 '^W UZYCIU[^:]*od 2026-10-01').Count -eq 1)), "kod $($r2.Kod); stan: $s2")
    $r3 = Odpal $skrypt ($wsp + @("-Data", "2026-10-08"))
    $s3 = Czytaj $stanP
    $bl = @(Linie-Stanu $s3 '^BLAD')
    $p["blokada od 7 dni: linia BLAD z nazwa, przyczyna=PLIKI, bez blad= (kopia poszla)"] = @((($r3.Kod -eq 1) -and ($s3 -match '(?m)^stan=BLAD\r?$') -and ($s3 -match '(?m)^przyczyna=PLIKI\r?$') -and
      ($bl.Count -eq 1) -and ($bl[0] -like "*od 2026-10-01*zablokowany.txt") -and -not ($s3 -match '(?m)^blad=')), "kod $($r3.Kod); stan: $s3")
  } finally { $blokada.Dispose() }
  $r4 = Odpal $skrypt ($wsp + @("-Data", "2026-10-09"))
  $s4 = Czytaj $stanP
  $p["po zwolnieniu: plik w kopii, stan OK, licznik blokad wyczyszczony"] = @((($r4.Kod -eq 0) -and ($s4 -match '(?m)^stan=OK\r?$') -and
    (Test-Path -LiteralPath (W-Kopii "$cel\zmiany\2026-10-09" "$proj\zablokowany.txt")) -and -not (Test-Path -LiteralPath "$H\.claude\mr\kopia-w-uzyciu.tsv")), "kod $($r4.Kod); stan: $s4")
  return $p
}

# ---------------------------------------------------------------- R. rotacja
function Scen-Rotacja([string]$skrypt, [string]$kat) {
  $H = Join-Path $kat "dom"; $cel = Join-Path $kat "cel"; $proj = Join-Path $H "proj"
  New-Item -ItemType Directory -Force -Path $cel | Out-Null
  $wsp = @("-KatalogDomowy", $H, "-Zrodla", $proj, "-Cel", $cel, "-Trzymaj", "2")
  $f = "$proj\f.txt"
  $p = [ordered]@{}
  $kody = @()
  function Dzien([int]$n, [string[]]$dodatkowe = @()) {
    $d = "2026-10-{0:D2}" -f $n
    Tekst $f "wersja $d" ([datetime]"2026-10-01").AddDays($n)
    Tekst "$proj\g-$d.txt" "nowy plik z $d"
    $r = Odpal $skrypt ($wsp + @("-Data", $d) + $dodatkowe)
    return $r.Kod
  }
  $kody += Dzien 1
  # cudze rzeczy w folderze kopii - rotacja nie ma prawa ich dotknac
  Tekst "$cel\inne\notatka.txt" "moja notatka"
  Tekst "$cel\zmiany\notatki-recznie\x.txt" "reczny katalog bez daty"
  $kody += Dzien 2; $kody += Dzien 3
  $p["po 3 dniach (trzymam 2): nic jeszcze nie wlane (dzien 01 to pelna)"] = @(((Dni-Zmian $cel) -eq "2026-10-02,2026-10-03,notatki-recznie"), "zmiany: $(Dni-Zmian $cel)")
  $kody += Dzien 4
  $pf = W-Kopii "$cel\pelna-2026-10-01" $f
  $p["dzien 4: wlany TYLKO najstarszy dzien (02), 03 i 04 zostaja"] = @((((Dni-Zmian $cel) -eq "2026-10-03,2026-10-04,notatki-recznie") -and ((Czytaj $pf) -eq "wersja 2026-10-02") -and
    (Test-Path -LiteralPath (W-Kopii "$cel\pelna-2026-10-01" "$proj\g-2026-10-02.txt"))), "zmiany: $(Dni-Zmian $cel); f w pelnej: $(Czytaj $pf)")
  $kody += Dzien 5
  $p["dzien 5: pelna ma wersje z 03 (nowsza wygrywa), najnowsza wersja w zmiany\05"] = @((((Czytaj $pf) -eq "wersja 2026-10-03") -and
    ((Czytaj (W-Kopii "$cel\zmiany\2026-10-05" $f)) -eq "wersja 2026-10-05")), "f w pelnej: $(Czytaj $pf)")
  $kody += Dzien 6 @("-Pierwsza")
  $p["-Pierwsza w dniu 6: dzien 04 (sprzed nowej pelnej) skasowany, stara pelna jeszcze zostaje"] = @((((Dni-Zmian $cel) -eq "2026-10-05,notatki-recznie") -and
    (Test-Path -LiteralPath "$cel\pelna-2026-10-01") -and (Test-Path -LiteralPath "$cel\pelna-2026-10-06")), "zmiany: $(Dni-Zmian $cel)")
  $kody += Dzien 7; $kody += Dzien 8
  $pf6 = W-Kopii "$cel\pelna-2026-10-06" $f
  $p["dzien 8: stara pelna-01 skasowana dopiero po wypadnieciu pelnej-06 z okna"] = @(((-not (Test-Path -LiteralPath "$cel\pelna-2026-10-01")) -and ((Czytaj $pf6) -eq "wersja 2026-10-06") -and
    ((Dni-Zmian $cel) -eq "2026-10-07,2026-10-08,notatki-recznie")), "zmiany: $(Dni-Zmian $cel); pelne: $((Get-ChildItem -LiteralPath $cel -Directory -Filter 'pelna-*' | ForEach-Object { $_.Name }) -join ',')")
  $p["rotacja nie ruszyla cudzych plikow w folderze kopii"] = @((((Czytaj "$cel\inne\notatka.txt") -eq "moja notatka") -and ((Czytaj "$cel\zmiany\notatki-recznie\x.txt") -eq "reczny katalog bez daty")), "")
  $p["rotacja opisana w dzienniku i stanie"] = @((((Czytaj "$cel\dziennik.txt") -match 'rotacja \(trzymam 2 ostatnich dni kopii\): wlane do pelna-2026-10-01') -and
    ((Czytaj "$H\.claude\mr\kopia-stan.txt") -match '(?m)^rotacja=')), "")
  $p["wszystkie przebiegi rotacji z kodem 0"] = @((@($kody | Where-Object { $_ -ne 0 }).Count -eq 0), "kody: $($kody -join ',')")
  # folder kopii usuniety (jak 17.10 przy odzyskiwaniu miejsca), indeks zostal
  Remove-Item -LiteralPath $cel -Recurse -Force
  New-Item -ItemType Directory -Force -Path $cel | Out-Null
  $r = Odpal $skrypt ($wsp + @("-Data", "2026-10-09"))
  $p["folder kopii pusty, indeks jest: robi PELNA ze wszystkimi plikami, nie przyrost"] = @((($r.Kod -eq 0) -and (Test-Path -LiteralPath (W-Kopii "$cel\pelna-2026-10-09" "$proj\g-2026-10-02.txt")) -and
    ((Czytaj "$cel\dziennik.txt") -match 'nie ma pelnej kopii')), "kod $($r.Kod): $($r.Tekst)")
  return $p
}

# ---------------------------------------------------------------- M. miejsce i cel
function Scen-Miejsce([string]$skrypt, [string]$kat) {
  $H = Join-Path $kat "dom"; $cel = Join-Path $kat "cel"; $proj = Join-Path $H "proj"
  New-Item -ItemType Directory -Force -Path $cel | Out-Null
  Tekst "$proj\a.txt" ("x" * 5000)
  $stanP = "$H\.claude\mr\kopia-stan.txt"
  $p = [ordered]@{}
  $r = Odpal $skrypt @("-KatalogDomowy", $H, "-Zrodla", $proj, "-Cel", $cel, "-Data", "2026-10-01", "-WolneBajty", "1000")
  $s = Czytaj $stanP
  $p["brak miejsca: kod 1, stan=BLAD, przyczyna=BRAK_MIEJSCA, linia ALARM, blad="] = @((($r.Kod -eq 1) -and ($s -match '(?m)^stan=BLAD\r?$') -and ($s -match '(?m)^przyczyna=BRAK_MIEJSCA\r?$') -and
    ((Linie-Stanu $s '^ALARM BRAK MIEJSCA').Count -eq 1) -and ($s -match '(?m)^blad=brak miejsca')), "kod $($r.Kod); stan: $s || $($r.Tekst)")
  $p["brak miejsca: nic nie skopiowane, indeksu nie ma"] = @(((@(Get-ChildItem -LiteralPath $cel -Directory).Count -eq 0) -and -not (Test-Path -LiteralPath "$H\.claude\mr\kopia-indeks.tsv")), "")
  $r2 = Odpal $skrypt @("-KatalogDomowy", $H, "-Zrodla", $proj, "-Cel", "$kat\nie-ma\ani-tego\Backup", "-Data", "2026-10-02")
  $s2 = Czytaj $stanP
  $p["brak folderu nad celem: kod 1, stan=BLAD, przyczyna=BRAK_CELU, blad= z powodem"] = @((($r2.Kod -eq 1) -and ($s2 -match '(?m)^stan=BLAD\r?$') -and ($s2 -match '(?m)^przyczyna=BRAK_CELU\r?$') -and
    ($s2 -match '(?m)^blad=nie ma katalogu nad celem')), "kod $($r2.Kod); stan: $s2")
  return [pscustomobject]@{ Proby = $p; Dom = $H; StanBrakMiejsca = $s }
}

$kopia = Join-Path $Zrodlo "narzedzia\kopia-zapasowa.ps1"
try {
  New-Item -ItemType Directory -Force -Path $T | Out-Null
  Write-Host "--- B. bazy danych i pliki zablokowane"
  $PB = Scen-Blokady $kopia (Join-Path $T "b")
  foreach ($n in $PB.Keys) { Sprawdz $n $PB[$n][0] $PB[$n][1] }
  Write-Host "--- R. rotacja"
  $PR = Scen-Rotacja $kopia (Join-Path $T "r")
  foreach ($n in $PR.Keys) { Sprawdz $n $PR[$n][0] $PR[$n][1] }
  Write-Host "--- M. brak miejsca i brak celu"
  $M = Scen-Miejsce $kopia (Join-Path $T "m")
  foreach ($n in $M.Proby.Keys) { Sprawdz $n $M.Proby[$n][0] $M.Proby[$n][1] }

  # okno nadzorcy (zasobnik\nadzorca\stan-kopia.ps1) na stanie "brak miejsca" - sprawa pilna od razu
  . (Join-Path $Zrodlo "zasobnik\stan-nadzorcy.ps1")
  Ustaw-Nadzorce $Zrodlo $M.Dom $true
  [System.IO.File]::WriteAllText("$($M.Dom)\.claude\mr\kopia-stan.txt", $M.StanBrakMiejsca, $bezBom)
  $o = Ocena-Kopii (Stan-Kopii) $null
  Sprawdz "okno nadzorcy: brak miejsca = pilny alarm z powodem" (($o.Alarm) -and ($o.AlarmWaga -eq "pilne") -and ("$($o.Linia) $($o.Porada) $($o.Tresc)" -like "*BRAK MIEJSCA*")) "linia: $($o.Linia) | porada: $($o.Porada) | waga: $($o.AlarmWaga)"

  # ---------------------------------------------------------------- S. sabotaze
  Write-Host "--- S. proby negatywne na kopii kopia-zapasowa.ps1"
  $katSab = Join-Path $T "zrodlo-sab\narzedzia"
  New-Item -ItemType Directory -Force -Path $katSab | Out-Null
  Copy-Item -Recurse (Join-Path $Zrodlo "narzedzia\instalacja") (Join-Path $katSab "instalacja")
  Copy-Item (Join-Path $Zrodlo "narzedzia\kopia-zapasowa-domyslne.json") $katSab
  $skryptSab = Join-Path $katSab "kopia-zapasowa.ps1"
  $oryg = [System.IO.File]::ReadAllText($kopia)
  $sabotaze = @(
    @{ Nazwa = "dzialajacy Postgres znow BLEDEM (jak do 17.10)"; Scen = "B"; Proba = "Postgres pominiety bez bledu: kod 0, stan=OK, linia BAZA z nazwa katalogu"
       Kotwica = 'Powod = "BAZA: katalog danych bazy "'; Zamiana = 'Powod = "BLAD: katalog danych bazy "' },
    @{ Nazwa = "zablokowany plik od razu BLEDEM"; Scen = "B"; Proba = "zablokowany plik = ostrzezenie z nazwa, stan OK, w_uzyciu=1"
       Kotwica = 'if ($dniBlokady -ge $Trzymaj) {'; Zamiana = 'if ($true) {' },
    @{ Nazwa = "dlugo zablokowany plik nigdy nie staje sie bledem"; Scen = "B"; Proba = "blokada od 7 dni: linia BLAD z nazwa, przyczyna=PLIKI, bez blad= (kopia poszla)"
       Kotwica = 'if ($dniBlokady -ge $Trzymaj) {'; Zamiana = 'if ($false) {' },
    @{ Nazwa = "rotacja wylaczona (nic nie kasuje)"; Scen = "R"; Proba = "dzien 4: wlany TYLKO najstarszy dzien (02), 03 i 04 zostaja"
       Kotwica = '  try { $opisRotacji = Rotacja }'; Zamiana = '  try { $opisRotacji = "" }' },
    @{ Nazwa = "rotacja o jeden dzien za gorliwa"; Scen = "R"; Proba = "dzien 4: wlany TYLKO najstarszy dzien (02), 03 i 04 zostaja"
       Kotwica = 'Select-Object -First $Trzymaj)'; Zamiana = 'Select-Object -First ($Trzymaj - 1))' },
    @{ Nazwa = "stara pelna kasowana od razu po -Pierwsza"; Scen = "R"; Proba = "-Pierwsza w dniu 6: dzien 04 (sprzed nowej pelnej) skasowany, stara pelna jeszcze zostaje"
       Kotwica = 'if (-not ($zostaja -contains $dataBazy)) {'; Zamiana = 'if ($true) {' },
    @{ Nazwa = "pusty folder kopii = zwykly przyrost (dziurawa kopia)"; Scen = "R"; Proba = "folder kopii pusty, indeks jest: robi PELNA ze wszystkimi plikami, nie przyrost"
       Kotwica = 'if (-not $Pelna -and $indeksJest -and $pelne.Count -eq 0) {'; Zamiana = 'if ($false) {' },
    @{ Nazwa = "sprawdzenie wolnego miejsca usuniete"; Scen = "M"; Proba = "brak miejsca: kod 1, stan=BLAD, przyczyna=BRAK_MIEJSCA, linia ALARM, blad="
       Kotwica = 'if ($wolne -ge 0 -and $wolne -lt $potrzeba) {'; Zamiana = 'if ($false) {' })
  $nr = 0
  foreach ($s in $sabotaze) {
    $nr++
    if (-not $oryg.Contains($s.Kotwica)) { Sprawdz "sabotaz '$($s.Nazwa)' zlapany" $false "kotwicy nie ma w ${kopia}: $($s.Kotwica)"; continue }
    [System.IO.File]::WriteAllText($skryptSab, $oryg.Replace($s.Kotwica, $s.Zamiana), $bezBom)
    $kat = Join-Path $T "s$nr"
    $wyn = switch ($s.Scen) { "B" { Scen-Blokady $skryptSab $kat } "R" { Scen-Rotacja $skryptSab $kat } "M" { (Scen-Miejsce $skryptSab $kat).Proby } }
    $wzor = switch ($s.Scen) { "B" { $PB } "R" { $PR } "M" { $M.Proby } }
    $proba = $wyn[$s.Proba]
    Sprawdz "sabotaz '$($s.Nazwa)' zlapany przez probe '$($s.Proba)'" ((-not $proba[0]) -and $wzor[$s.Proba][0]) "proba z sabotazem przeszla: $($proba[1])"
  }
} catch {
  Sprawdz "test przeszedl bez wywrotki" $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)"
} finally {
  if (-not $Zostaw -and (Test-Path -LiteralPath $T)) {
    try { Remove-Item -LiteralPath $T -Recurse -Force }
    catch { Write-Host "UWAGA: nie udalo sie usunac plikow roboczych $T ($($_.Exception.Message))" }
  }
}

if ($Zostaw) { Write-Host "Pliki robocze: $T" }
if ($script:Zle -gt 0) { Write-Host "WYNIK: $($script:Zle) prob nie przeszlo"; exit 1 }
Write-Host "WYNIK: wszystkie proby przeszly"
exit 0
