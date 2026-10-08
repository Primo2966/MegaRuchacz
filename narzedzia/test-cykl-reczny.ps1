# Proba czytania recznego z okna nadzorcy (narzedzia\cykl-dzienny.ps1 -Recznie) - od 08.10.2026,
# gdy uzytkownik wieczorem kliknal "Przeczytaj teraz nowe rozmowy", potwierdzil koszt i nie stalo
# sie nic: cykl po porannym przebiegu konczyl sie od razu ("dzisiejszy cykl juz przeszedl"), a slad
# zostawal tylko w dzienniku nadzorcy.
#
# Wszystko w %TEMP%: kopia cyklu z atrapami, sztuczny katalog domowy, wlasny zamek. Zero wolan
# modelu i zero sieci - wylawianie (wyciagnij-fakty.ps1) i weryfikacja (aktualizuj-wiedze.ps1) to
# atrapy zapisujace kazde "wolanie modelu" do pliku, a wykrywanie narzedzi AI i przeszkod dostawcy
# jest w kopii cyklu podmienione na odczyt pliku atrapy. Okno: same funkcje (Stan-Recznego,
# Ocena-Klikniecia, Napisy-Przyciskow) po wczytaniu stan-nadzorcy.ps1 w trybie probnym, bez okna.
#   powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File narzedzia\test-cykl-reczny.ps1 [-Zostaw]
# Kod wyjscia: 0 = wszystkie proby przeszly, 1 = ktoras nie.
#
# Co musi byc prawda:
#   - reczny przebieg czyta po dzisiejszym udanym przebiegu automatu (od znacznika, z limitem
#     $MaxNadrabiania), a cykl-ostatni.txt i .cykl-stan to pokazuja,
#   - automat dalej raz na dzien: po dzisiejszym "ok" i po recznym czytaniu nie czyta nic,
#     a po wyczerpanych probach stoi; nowy dzien czyta jak dotad i nie pisze .cykl-reczny,
#   - kazda odmowa daje zdanie dla czlowieka: nic nowego, zamek zajety, przeszkoda dostawcy,
#     model pada, wywrotka, przebieg, ktory zniknal, i klikniecie bez znaku zycia,
#   - reczne odlozenie nie otwiera dnia zamknietego przez automat (inaczej dozor ruszylby dzis znowu).
# Proby negatywne: sabotaze na kopii cyklu i na kopii stan-cykl.ps1 - kazdy MUSI byc zlapany.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Zostaw
)

$ErrorActionPreference = "Stop"
$Katalog = Join-Path $env:TEMP ("mr-test-cykl-reczny-" + (Get-Date -Format "yyyyMMdd-HHmmss") + "-" + $PID)
$Z = Join-Path $Katalog "zrodlo"
$H = Join-Path $Katalog "dom"
$Atr = Join-Path $Z "atrapa"
$Wiedza = Join-Path $H ".claude\wiedza"
$Zamek = "Local\MegaRuchacz-LoreCykl-test-$PID"
$Dzis = Get-Date -Format "yyyy-MM-dd"
$script:Zle = 0
$UTF8 = New-Object System.Text.UTF8Encoding($false)

function Sprawdz([string]$co, [bool]$ok, [string]$szczegol = "") {
  $linia = $(if ($ok) { "OK    " } else { "BLAD  " }) + $co
  if (-not $ok -and $szczegol) { $linia += " -- $szczegol" }
  Write-Host $linia
  if (-not $ok) { $script:Zle++ }
}

function Zapisz([string]$p, [string]$tekst) {
  $kat = Split-Path -Parent $p
  if (-not (Test-Path $kat)) { New-Item -ItemType Directory -Force -Path $kat | Out-Null }
  [System.IO.File]::WriteAllText($p, $tekst, $UTF8)
}
function Czytaj([string]$p) { if (Test-Path -LiteralPath $p) { return [System.IO.File]::ReadAllText($p) } return "" }
function Klucze([string]$p) {
  $k = @{}
  foreach ($l in ((Czytaj $p) -split '\r?\n')) {
    $m = [regex]::Match($l, '^\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*:\s*(.*?)\s*$')
    if ($m.Success) { $k[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $k
}
function Wolania-Modelu { return @((Czytaj (Join-Path $Atr "model.log")) -split '\r?\n' | Where-Object { $_.Trim() }).Count }

# ---------------------------------------------------------------- kopia cyklu z atrapami
New-Item -ItemType Directory -Force -Path (Join-Path $Z "narzedzia"), $Atr, $Wiedza | Out-Null
foreach ($f in @("zapis-trwaly.ps1", "kopie-dzienne.ps1")) { Copy-Item (Join-Path $Zrodlo "narzedzia\$f") (Join-Path $Z "narzedzia\$f") }

# Kotwice: kazda MUSI wystapic w cyklu dokladnie raz - inaczej test nie sprawdza tego, co mysli.
$Podmiany = [ordered]@{
  '"Local\MegaRuchacz-LoreCykl"' = "`"$Zamek`""
  '  $narzedzia = Znajdz-Narzedzia' = '  $narzedzia = @(@{ Nazwa = "Atrapa"; Polecenie = "atrapa"; Adres = "nigdzie" })   # TEST: bez PATH i sieci'
  '  $przeszkoda = Znajdz-Przeszkode $narzedzia' = '  $przeszkoda = $null; $pPrz = Join-Path (Split-Path -Parent $PSScriptRoot) "atrapa\przeszkoda.txt"; if (Test-Path $pPrz) { $przeszkoda = ([System.IO.File]::ReadAllText($pPrz)).Trim() }   # TEST'
}
$OrygCyklu = [System.IO.File]::ReadAllText((Join-Path $Zrodlo "narzedzia\cykl-dzienny.ps1"))
function Kopia-Cyklu([string]$nazwa, $dodatkowe = $null) {
  $tekst = $OrygCyklu
  $wszystkie = [ordered]@{}
  foreach ($k in $Podmiany.Keys) { $wszystkie[$k] = $Podmiany[$k] }
  if ($dodatkowe) { foreach ($k in $dodatkowe.Keys) { $wszystkie[$k] = $dodatkowe[$k] } }
  foreach ($k in $wszystkie.Keys) {
    $ile = ([regex]::Matches($tekst, [regex]::Escape($k))).Count
    if ($ile -ne 1) { throw "kotwica wystepuje $ile razy w cykl-dzienny.ps1: $k" }
    $tekst = $tekst.Replace($k, $wszystkie[$k])
  }
  $p = Join-Path $Z "narzedzia\$nazwa"
  [System.IO.File]::WriteAllText($p, $tekst, $UTF8)
  return $p
}

# Atrapa wylawiania: -Kolejka oddaje liczby z atrapa\kolejka.txt, -Nadrabiaj 1 to "wolanie modelu":
# linia w model.log, kolejka mniejsza o 1 przebieg / 10 kawalkow, znacznik na teraz, koszt +1000.
Zapisz (Join-Path $Z "narzedzia\wyciagnij-fakty.ps1") @'
param([string]$Zrodlo, [switch]$Kolejka, [int]$Nadrabiaj = 0)
$atr = Join-Path (Split-Path -Parent $PSScriptRoot) "atrapa"
$cz = ([System.IO.File]::ReadAllText((Join-Path $atr "kolejka.txt"))).Trim() -split '\s+'
$p = [int]$cz[0]; $kw = [int]$cz[1]
if ($Kolejka) { Write-Output "kolejka.przebiegi: $p"; Write-Output "kolejka.kawalki: $kw"; exit 0 }
Add-Content -LiteralPath (Join-Path $atr "model.log") -Value ("wolanie " + (Get-Date -Format o))
if (Test-Path (Join-Path $atr "model-pada.txt")) { Write-Output "Error: usage limit reached (atrapa)"; exit 1 }
$p = [math]::Max(0, $p - 1); $kw = [math]::Max(0, $kw - 10)
[System.IO.File]::WriteAllText((Join-Path $atr "kolejka.txt"), "$p $kw")
$w = Join-Path $env:LORE_HOME "wiedza"
[System.IO.File]::WriteAllText((Join-Path $w ".ostatnie-wyciaganie"), (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"))
$pk = Join-Path $w ".koszt-cyklu.txt"; $tok = 0; $wol = 0; $fa = 0
if (Test-Path $pk) { foreach ($l in [System.IO.File]::ReadAllLines($pk)) {
  if ($l -match '^tokeny: (\d+)') { $tok = [int]$Matches[1] }; if ($l -match '^wywolania: (\d+)') { $wol = [int]$Matches[1] }; if ($l -match '^fakty: (\d+)') { $fa = [int]$Matches[1] } } }
[System.IO.File]::WriteAllText($pk, "data: $(Get-Date -Format 'yyyy-MM-dd HH:mm')`r`ntokeny: $($tok + 1000)`r`nwywolania: $($wol + 1)`r`nfakty: $($fa + 2)`r`ntokeny_zrodlo: pomiar`r`nnarzedzie: atrapa`r`n")
if ($p -gt 0) { Write-Output "zostalo $p przebiegow - uruchom: wyciagnij-fakty.ps1 -Nadrabiaj $p" }
exit 0
'@
Zapisz (Join-Path $Z "narzedzia\aktualizuj-wiedze.ps1") @'
param([string]$Zrodlo, [switch]$BezWylawiania, [string]$KatalogDomowy)
$atr = Join-Path (Split-Path -Parent $PSScriptRoot) "atrapa"
if (Test-Path (Join-Path $atr "weryfikacja-rzuca.txt")) { throw "atrapa: weryfikacja sie wywrocila" }
Add-Content -LiteralPath (Join-Path $atr "weryfikacja.log") -Value "weryfikacja"
exit 0
'@

Zapisz (Join-Path $H ".claude\CLAUDE.md") "# Ustalenia globalne`r`n`r`n## Co wiem`r`n`r`n- [2026-10-01] Fakt testowy.`r`n"
Zapisz (Join-Path $Wiedza "kandydaci.md") "# Kandydaci`r`n"
$ZnacznikRano = (Get-Date "$Dzis 08:04").ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

# Stan przed proba: dzien w .cykl-stan, kolejka atrapy, znacznik o 08:04, czyste slady.
function Przygotuj([string]$stanDnia, [int]$przebiegi, [int]$kawalki) {
  Zapisz (Join-Path $Wiedza ".cykl-stan") $stanDnia
  Zapisz (Join-Path $Atr "kolejka.txt") "$przebiegi $kawalki"
  Zapisz (Join-Path $Wiedza ".ostatnie-wyciaganie") $ZnacznikRano
  Zapisz (Join-Path $Wiedza "cykl-ostatni.txt") "data: $Dzis 08:04`r`nstatus: ok`r`nopis: poranny przebieg automatu`r`n"
  foreach ($f in @((Join-Path $Atr "model.log"), (Join-Path $Atr "przeszkoda.txt"), (Join-Path $Atr "model-pada.txt"),
                   (Join-Path $Atr "weryfikacja-rzuca.txt"), (Join-Path $Wiedza ".cykl-reczny"), (Join-Path $Wiedza ".cykl-postep"))) {
    if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
  }
}
$DzienOk = "data: $Dzis`r`nproby: 0`r`nstatus: ok`r`nczas: $Dzis 08:04`r`nwylowione: ok`r`nzostalo: 0`r`n"

function Odpal([string]$skrypt, [bool]$recznie) {
  $arg = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $skrypt, "-Zrodlo", $Z, "-KatalogDomowy", $H)
  if ($recznie) { $arg += "-Recznie" }
  $ErrorActionPreference = "Continue"   # stderr cyklu to tresc do sprawdzenia, nie wyjatek
  $wy = & powershell.exe @arg 2>&1
  return [pscustomobject]@{ Kod = $LASTEXITCODE; Tekst = (($wy | ForEach-Object { "$_" }) -join "`n") }
}

# ---------------------------------------------------------------- funkcje okna (bez okna)
. (Join-Path $Zrodlo "zasobnik\stan-nadzorcy.ps1")
Ustaw-Nadzorce $Zrodlo $H $true
$script:ModulyOkna = @{}
. (Join-Path $Zrodlo "zasobnik\nadzorca\przeglad-tresc.ps1")
$PlikStanCyklu = Join-Path $Zrodlo "zasobnik\nadzorca\stan-cykl.ps1"

function Napisy-Z-Kolejka {
  $c = [pscustomobject]@{ Pracuje = $false; Przebiegi = 3; Kawalki = 30; Zaleglosc = 3; Koszt = 3000; KosztWywolan = 3; KosztData = (Get-Date); Data = (Get-Date) }
  $d = [pscustomobject]@{ Cykl = $c; Wersja = $null; Instalacja = $null }
  return (Napisy-Przyciskow $d $null $null ([pscustomobject]@{ Przycisk = $true; PrzyciskOpis = "" }))
}

# ---------------------------------------------------------------- proby (kazda zwraca @(ok, szczegol))
# Kazda proba to funkcja z argumentem: sciezka cyklu - te same proby ida nizej na sabotazach.

function P-AutoPoDzisiejszym($cykl) {
  Przygotuj $DzienOk 3 30
  $przed = Czytaj (Join-Path $Wiedza ".cykl-stan")
  $r = Odpal $cykl $false
  $ok = ($r.Kod -eq 0) -and ((Wolania-Modelu) -eq 0) -and ($r.Tekst -match "juz przeszedl") -and
        -not (Test-Path (Join-Path $Wiedza ".cykl-reczny")) -and ((Czytaj (Join-Path $Wiedza ".cykl-stan")) -eq $przed)
  return @($ok, "kod $($r.Kod), wolan modelu $(Wolania-Modelu): $($r.Tekst)")
}

function P-RecznyPoDzisiejszym($cykl) {
  Przygotuj $DzienOk 3 30
  $r = Odpal $cykl $true
  $rk = Klucze (Join-Path $Wiedza ".cykl-reczny")
  $ost = Klucze (Join-Path $Wiedza "cykl-ostatni.txt")
  $st = Klucze (Join-Path $Wiedza ".cykl-stan")
  $zn = (Czytaj (Join-Path $Wiedza ".ostatnie-wyciaganie")).Trim()
  $ok = ($r.Kod -eq 0) -and ((Wolania-Modelu) -eq 3) -and ($rk["stan"] -eq "koniec") -and ($rk["wynik"] -eq "ok") -and
        ($rk["przeczytane"] -eq "30") -and ($rk["od"] -eq "$Dzis 08:04") -and ($rk["tokeny"] -eq "3000") -and
        ($ost["status"] -eq "ok") -and ($ost["uruchomienie"] -eq "reczne z okna") -and ($ost["data"] -ne "$Dzis 08:04") -and
        ($st["status"] -eq "ok") -and ($st["proby"] -eq "0") -and ($zn -ne $ZnacznikRano) -and -not (Czy-Ruszac-Cykl).Ruszac
  $w = Stan-Recznego
  $ok = $ok -and $w -and $w.Udane -and $w.Dzis -and ($w.Krotki -match "Przeczytane o") -and ($w.Krotki -match "30 fragment") -and ($w.Krotki -match "od 08:04")
  return @($ok, "kod $($r.Kod), wolan $(Wolania-Modelu), reczny: $(Czytaj (Join-Path $Wiedza '.cykl-reczny')) | ostatni: $(Czytaj (Join-Path $Wiedza 'cykl-ostatni.txt')) | okno: $($w.Krotki) | $($r.Tekst)")
}

function P-AutoPoRecznym($cykl) {
  # stan zostawiony przez reczny przebieg (bez Przygotuj): automat ma nie czytac nic
  Zapisz (Join-Path $Atr "kolejka.txt") "2 20"
  if (Test-Path (Join-Path $Atr "model.log")) { Remove-Item (Join-Path $Atr "model.log") -Force }
  $r = Odpal $cykl $false
  $ok = ($r.Kod -eq 0) -and ((Wolania-Modelu) -eq 0) -and ($r.Tekst -match "juz przeszedl")
  return @($ok, "kod $($r.Kod), wolan $(Wolania-Modelu): $($r.Tekst)")
}

function P-RecznyLimit($cykl) {
  Przygotuj $DzienOk 7 70
  $r = Odpal $cykl $true
  $rk = Klucze (Join-Path $Wiedza ".cykl-reczny")
  $st = Klucze (Join-Path $Wiedza ".cykl-stan")
  $ok = ($r.Kod -eq 0) -and ((Wolania-Modelu) -eq 5) -and ($rk["wynik"] -eq "dogania") -and ($rk["zostalo"] -eq "2") -and ($st["status"] -eq "dogania")
  $w = Stan-Recznego
  $ok = $ok -and $w.Udane -and ($w.Krotki -match "Czeka jeszcze 2")
  # automat po recznym "dogania" dzis juz nie rusza - o starcie decyduja dozor i straznik (Czy-Ruszac-Cykl)
  $cz = Czy-Ruszac-Cykl
  $ok = $ok -and -not $cz.Ruszac
  return @($ok, "kod $($r.Kod), wolan $(Wolania-Modelu), dozor: $($cz.Ruszac) $($cz.Powod), reczny: $(Czytaj (Join-Path $Wiedza '.cykl-reczny')) | stan: $(Czytaj (Join-Path $Wiedza '.cykl-stan'))")
}

function P-RecznyNic($cykl) {
  Przygotuj $DzienOk 0 0
  $stPrzed = Czytaj (Join-Path $Wiedza ".cykl-stan"); $ostPrzed = Czytaj (Join-Path $Wiedza "cykl-ostatni.txt")
  $r = Odpal $cykl $true
  $rk = Klucze (Join-Path $Wiedza ".cykl-reczny")
  $w = Stan-Recznego
  $ok = ($r.Kod -eq 0) -and ((Wolania-Modelu) -eq 0) -and ($rk["wynik"] -eq "nic") -and ($rk["od"] -eq "$Dzis 08:04") -and
        ((Czytaj (Join-Path $Wiedza ".cykl-stan")) -eq $stPrzed) -and ((Czytaj (Join-Path $Wiedza "cykl-ostatni.txt")) -eq $ostPrzed) -and
        $w -and -not $w.Udane -and ($w.Krotki -match "^Nic nowego od 08:04") -and ($w.Pelny -match "Nic nowego od 08:04")
  return @($ok, "kod $($r.Kod), wolan $(Wolania-Modelu), reczny: $(Czytaj (Join-Path $Wiedza '.cykl-reczny')) | okno: $($w.Krotki) | $($r.Tekst)")
}

function P-RecznyZamekZajety($cykl) {
  Przygotuj $DzienOk 3 30
  $m = New-Object System.Threading.Mutex($false, $Zamek)
  $mam = $m.WaitOne(0)
  try { $r = Odpal $cykl $true } finally { if ($mam) { $m.ReleaseMutex() }; $m.Dispose() }
  $rk = Klucze (Join-Path $Wiedza ".cykl-reczny")
  $w = Stan-Recznego
  $ok = $mam -and ($r.Kod -eq 0) -and ((Wolania-Modelu) -eq 0) -and ($rk["wynik"] -eq "zajete") -and $w -and ($w.Krotki -match "trwa") -and ($w.Pelny -match "Nic nie zosta")
  return @($ok, "zamek wziety: $mam, wolan $(Wolania-Modelu), reczny: $(Czytaj (Join-Path $Wiedza '.cykl-reczny')) | okno: $($w.Krotki)")
}

function P-RecznyPrzeszkoda($cykl) {
  Przygotuj $DzienOk 3 30
  Zapisz (Join-Path $Atr "przeszkoda.txt") "brak sieci do: atrapa.example"
  $r = Odpal $cykl $true
  $rk = Klucze (Join-Path $Wiedza ".cykl-reczny")
  $st = Klucze (Join-Path $Wiedza ".cykl-stan")
  $w = Stan-Recznego
  $ok = ($r.Kod -eq 0) -and ((Wolania-Modelu) -eq 0) -and ($rk["wynik"] -eq "odlozony") -and ($rk["powod"] -match "brak sieci") -and
        ($st["status"] -eq "ok") -and $w -and -not $w.Udane -and ($w.Krotki -match "brak sieci") -and ($w.Pelny -match "brak sieci")
  $cz = Czy-Ruszac-Cykl   # dozor i straznik: dzien zamkniety rano zostaje zamkniety
  $ok = $ok -and -not $cz.Ruszac
  return @($ok, "dozor: $($cz.Ruszac) $($cz.Powod), wolan $(Wolania-Modelu), reczny: $(Czytaj (Join-Path $Wiedza '.cykl-reczny')) | stan: $(Czytaj (Join-Path $Wiedza '.cykl-stan')) | okno: $($w.Krotki)")
}

function P-RecznyModelPada($cykl) {
  Przygotuj $DzienOk 2 20
  Zapisz (Join-Path $Atr "model-pada.txt") "x"
  $r = Odpal $cykl $true
  $rk = Klucze (Join-Path $Wiedza ".cykl-reczny")
  $w = Stan-Recznego
  $ok = ($r.Kod -eq 0) -and ((Wolania-Modelu) -eq 1) -and ($rk["wynik"] -eq "odlozony") -and ($rk["powod"] -eq "wyczerpany limit") -and
        ((Klucze (Join-Path $Wiedza ".cykl-stan"))["status"] -eq "ok") -and ($w.Krotki -match "wyczerpany limit")
  return @($ok, "wolan $(Wolania-Modelu), reczny: $(Czytaj (Join-Path $Wiedza '.cykl-reczny')) | okno: $($w.Krotki)")
}

function P-ProbyWyczerpane($cykl) {
  Przygotuj "data: $Dzis`r`nproby: 5`r`nstatus: odlozony`r`npowod: brak sieci`r`nczas: $Dzis 12:00`r`n" 1 10
  $a = Odpal $cykl $false
  $autoNic = ((Wolania-Modelu) -eq 0) -and ($a.Tekst -match "koniec prob")
  $r = Odpal $cykl $true
  $rk = Klucze (Join-Path $Wiedza ".cykl-reczny")
  $ok = $autoNic -and ((Wolania-Modelu) -eq 1) -and ($rk["wynik"] -eq "ok")
  return @($ok, "automat stal: $autoNic, wolan $(Wolania-Modelu), reczny: $(Czytaj (Join-Path $Wiedza '.cykl-reczny')) | $($a.Tekst)")
}

function P-RecznyWywrotka($cykl) {
  Przygotuj $DzienOk 1 10
  Zapisz (Join-Path $Atr "weryfikacja-rzuca.txt") "x"
  $r = Odpal $cykl $true
  $rk = Klucze (Join-Path $Wiedza ".cykl-reczny")
  $w = Stan-Recznego
  $ok = ($r.Kod -ne 0) -and ($rk["wynik"] -eq "blad") -and ($rk["powod"] -match "atrapa: weryfikacja") -and ($w.Krotki -match "wywr") -and ($w.Pelny -match "atrapa: weryfikacja")
  return @($ok, "kod $($r.Kod), reczny: $(Czytaj (Join-Path $Wiedza '.cykl-reczny')) | okno: $($w.Krotki)")
}

function P-AutoNowyDzien($cykl) {
  $wczoraj = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
  Przygotuj "data: $wczoraj`r`nproby: 0`r`nstatus: ok`r`nczas: $wczoraj 08:00`r`nwylowione: ok`r`n" 2 20
  $r = Odpal $cykl $false
  $ost = Klucze (Join-Path $Wiedza "cykl-ostatni.txt")
  $st = Klucze (Join-Path $Wiedza ".cykl-stan")
  $ok = ($r.Kod -eq 0) -and ((Wolania-Modelu) -eq 2) -and ($st["status"] -eq "ok") -and ($st["data"] -eq $Dzis) -and
        ($ost["uruchomienie"] -eq "automat") -and -not (Test-Path (Join-Path $Wiedza ".cykl-reczny"))
  return @($ok, "kod $($r.Kod), wolan $(Wolania-Modelu), stan: $(Czytaj (Join-Path $Wiedza '.cykl-stan')) | $($r.Tekst)")
}

# Okno: przebieg, ktory zniknal bez wyniku, i ten, ktory zyje (pid tego testu to powershell).
function P-OknoPrzerwane {
  $martwy = Start-Process -FilePath "cmd.exe" -ArgumentList "/c exit 0" -WindowStyle Hidden -PassThru
  $martwy.WaitForExit()
  $teraz = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Zapisz (Join-Path $Wiedza ".cykl-reczny") "start: $teraz`r`npid: $($martwy.Id)`r`nstan: pracuje`r`nczas: $teraz`r`n"
  $w1 = Stan-Recznego
  Zapisz (Join-Path $Wiedza ".cykl-reczny") "start: $teraz`r`npid: $PID`r`nstan: pracuje`r`nczas: $teraz`r`n"
  $w2 = Stan-Recznego
  $n2 = Napisy-Z-Kolejka
  $ok = $w1.Przerwane -and -not $w1.Trwa -and ($w1.Krotki -match "bez wyniku") -and ($w1.Pelny -match "klikn") -and
        $w2.Trwa -and -not $w2.Przerwane -and (-not $n2.CyklWlaczony) -and ($n2.CyklOpis -eq $w2.Krotki)
  return @($ok, "martwy: $($w1.Krotki) | zywy: $($w2.Krotki) | przycisk: $($n2.CyklWlaczony) $($n2.CyklOpis)")
}

# Okno: klikniecie bez znaku zycia ("cisza" po $SEKUND_NA_START_RECZNEGO s), czekanie, stary wynik
# nie jest odpowiedzia na nowe klikniecie, a pod przyciskiem stoi wynik z dzis.
function P-OknoKlikniecie {
  if (Test-Path (Join-Path $Wiedza ".cykl-reczny")) { Remove-Item (Join-Path $Wiedza ".cykl-reczny") -Force }
  $teraz = Get-Date
  $o1 = Ocena-Klikniecia $null $teraz.AddSeconds(-($SEKUND_NA_START_RECZNEGO + 1)) $teraz
  $o2 = Ocena-Klikniecia $null $teraz.AddSeconds(-10) $teraz
  $stary = [pscustomobject]@{ Start = $teraz.AddMinutes(-3); Trwa = $false }
  $o3 = Ocena-Klikniecia $stary $teraz.AddSeconds(-10) $teraz
  $nowy = [pscustomobject]@{ Start = $teraz.AddSeconds(-8); Trwa = $false }
  $o4 = Ocena-Klikniecia $nowy $teraz.AddSeconds(-10) $teraz
  $script:CyklKlik = $teraz.AddSeconds(-3)
  $n1 = Napisy-Z-Kolejka
  $script:CyklKlik = $null
  $script:NapisCyklu = [pscustomobject]@{ Czas = $teraz.AddSeconds(-70); Tekst = "Czytanie rozmow nie dalo znaku zycia (TEST)" }
  $n2 = Napisy-Z-Kolejka
  $script:NapisCyklu = $null
  $sNic = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Zapisz (Join-Path $Wiedza ".cykl-reczny") "start: $sNic`r`npid: 1`r`nstan: koniec`r`nczas: $sNic`r`nwynik: nic`r`nod: $Dzis 08:04`r`n"
  $n3 = Napisy-Z-Kolejka
  $ok = ($o1 -eq "cisza") -and ($o2 -eq "czekam") -and ($o3 -eq "czekam") -and ($o4 -eq "koniec") -and
        (-not $n1.CyklWlaczony) -and ($n1.CyklOpis -match "Uruchamiam") -and ($n2.CyklOpis -match "znaku zycia \(TEST\)") -and
        ($n3.CyklOpis -match "^Nic nowego od 08:04")
  return @($ok, "oceny: $o1/$o2/$o3/$o4 | czekam: $($n1.CyklWlaczony) $($n1.CyklOpis) | cisza: $($n2.CyklOpis) | nic: $($n3.CyklOpis)")
}

# Pierwszy znak zycia recznego przebiegu - podstawa progu $SEKUND_NA_START_RECZNEGO w stan-cykl.ps1.
function P-ZnakZycia($cykl) {
  Przygotuj $DzienOk 1 10
  $start = Get-Date
  $p = Start-Process -FilePath "powershell.exe" -WindowStyle Hidden -PassThru -ArgumentList @(
    "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", "`"$cykl`"", "-Zrodlo", "`"$Z`"", "-KatalogDomowy", "`"$H`"", "-Recznie")
  $sek = $null
  while (([datetime]::Now - $start).TotalSeconds -lt 120) {
    $k = @{}
    try { $k = Klucze (Join-Path $Wiedza ".cykl-reczny") } catch { $k = @{} }   # plik bywa w chwili podmiany - nastepny obrot
    $s = $null
    if ($k["start"]) { $s = [datetime]::ParseExact($k["start"], "yyyy-MM-dd HH:mm:ss", $null) }
    if ($s -and ($s -ge $start.AddSeconds(-1))) { $sek = ([datetime]::Now - $start).TotalSeconds; break }
    Start-Sleep -Milliseconds 100
  }
  if (-not $p.WaitForExit(120000)) { try { $p.Kill() } catch { Write-Host "nie dalo sie ubic przebiegu z proby znaku zycia: $($_.Exception.Message)" } }
  $ok = ($null -ne $sek) -and ($sek -lt $SEKUND_NA_START_RECZNEGO)
  return @($ok, "pierwszy zapis po $sek s (prog $SEKUND_NA_START_RECZNEGO s)", $sek)
}

$ProbyCyklu = [ordered]@{
  "automat po dzisiejszym 'ok' nie czyta (raz na dzien)"                = "P-AutoPoDzisiejszym"
  "reczny czyta po dzisiejszym przebiegu, cykl-ostatni i stan to pokazuja" = "P-RecznyPoDzisiejszym"
  "automat po recznym czytaniu dalej nie czyta"                          = "P-AutoPoRecznym"
  "reczny trzyma limit 5 porcji, dozor po nim dzis nie rusza"            = "P-RecznyLimit"
  "reczny przy pustej kolejce: 'Nic nowego od 08:04', stan nietkniety"   = "P-RecznyNic"
  "reczny przy zajetym zamku: widoczne 'czytanie juz trwa'"              = "P-RecznyZamekZajety"
  "reczny przy przeszkodzie: widoczny powod, dzien automatu zamkniety"   = "P-RecznyPrzeszkoda"
  "reczny, model pada: widoczne 'wyczerpany limit'"                      = "P-RecznyModelPada"
  "po 5 probach automat stoi, reczny czyta (poza `$MaxProb)"             = "P-ProbyWyczerpane"
  "reczny, wywrotka w srodku: widoczny blad"                             = "P-RecznyWywrotka"
  "automat nowego dnia czyta jak dotad i nie pisze .cykl-reczny"         = "P-AutoNowyDzien"
}

$kod = 1
try {
  $Cykl = Kopia-Cyklu "cykl-dzienny.ps1"
  Write-Host "--- A. cykl-dzienny.ps1 (kopia z atrapami)"
  foreach ($nazwa in $ProbyCyklu.Keys) {
    $w = & $ProbyCyklu[$nazwa] $Cykl
    Sprawdz $nazwa $w[0] $w[1]
  }
  $zz = P-ZnakZycia $Cykl
  Sprawdz "pierwszy znak zycia recznego przebiegu przed progiem okna" $zz[0] $zz[1]
  Write-Host "      (zmierzone: $([math]::Round([double]$zz[2], 1)) s)"

  Write-Host "--- B. okno (Stan-Recznego, Ocena-Klikniecia, Napisy-Przyciskow)"
  $w = P-OknoPrzerwane; Sprawdz "okno: przebieg zniknal bez wyniku -> 'urwalo sie', zywy -> 'trwa' i przycisk wylaczony" $w[0] $w[1]
  $w = P-OknoKlikniecie; Sprawdz "okno: cisza po progu, czekanie, stary wynik nie jest odpowiedzia, wynik pod przyciskiem" $w[0] $w[1]

  Write-Host "--- C. sabotaze cyklu (kazdy MUSI byc zlapany)"
  $sabotaze = @(
    @{ Nazwa = "reczny konczy sie na dzisiejszym 'ok' jak przed 08.10"; Proba = "P-RecznyPoDzisiejszym"
       Kotwica = 'if (($stan["status"] -eq "ok") -and -not $Recznie) {'; Na = 'if ($stan["status"] -eq "ok") {' }
    @{ Nazwa = "zajety zamek po cichu"; Proba = "P-RecznyZamekZajety"
       Kotwica = '    Zapisz-Reczny "koniec" "zajete" "czytanie rozmow juz trwa (automat albo wczesniejsze klikniecie)"'; Na = '    # sabotaz: cisza' }
    @{ Nazwa = "automat tez czyta po dzisiejszym 'ok'"; Proba = "P-AutoPoDzisiejszym"
       Kotwica = 'if (($stan["status"] -eq "ok") -and -not $Recznie) {'; Na = 'if (($stan["status"] -eq "ok") -and $false) {' }
    @{ Nazwa = "reczne odlozenie otwiera dzien automatu"; Proba = "P-RecznyPrzeszkoda"
       Kotwica = 'if ($Recznie -and $script:StatusPrzed -and ($script:StatusPrzed -ne "odlozony")) {'; Na = 'if ($false) {' }
    @{ Nazwa = "reczny bez limitu porcji"; Proba = "P-RecznyLimit"
       Kotwica = '$nadrabiaj = [math]::Max(1, [math]::Min($czeka, $MaxNadrabiania))'; Na = '$nadrabiaj = [math]::Max(1, $czeka)' }
    @{ Nazwa = "pusta kolejka po cichu (bez wyniku 'nic')"; Proba = "P-RecznyNic"
       Kotwica = '    Zapisz-Reczny "koniec" "nic" "" ([ordered]@{ od = (Znacznik-Tekst $od); znacznik = (Znacznik-Tekst $od) })'; Na = '    # sabotaz: cisza' }
  )
  foreach ($s in $sabotaze) {
    $kopia = Kopia-Cyklu "cykl-dzienny-sabotaz.ps1" @{ $s.Kotwica = $s.Na }
    $w = & $s.Proba $kopia
    Sprawdz "sabotaz '$($s.Nazwa)' zlapany przez '$($s.Proba)'" (-not $w[0]) "proba z sabotazem przeszla: $($w[1])"
  }

  Write-Host "--- D. sabotaze okna (kopia stan-cykl.ps1)"
  $orygStanu = [System.IO.File]::ReadAllText($PlikStanCyklu)
  $sabotazeOkna = @(
    @{ Nazwa = "zniknieta praca udaje, ze trwa"; Proba = "P-OknoPrzerwane"
       Kotwica = '  if (-not $p) { return $false }'; Na = '  if (-not $p) { return $true }' }
    @{ Nazwa = "klikniecie bez znaku zycia czeka w nieskonczonosc"; Proba = "P-OknoKlikniecie"
       Kotwica = '    if (($teraz - [datetime]$klik).TotalSeconds -ge $SEKUND_NA_START_RECZNEGO) { return "cisza" }'; Na = '    # sabotaz' }
  )
  $kopiaStanu = Join-Path $Katalog "stan-cykl-sabotaz.ps1"
  foreach ($s in $sabotazeOkna) {
    $ile = ([regex]::Matches($orygStanu, [regex]::Escape($s.Kotwica))).Count
    if ($ile -ne 1) { Sprawdz "sabotaz '$($s.Nazwa)' zlapany" $false "kotwica wystepuje $ile razy w stan-cykl.ps1: $($s.Kotwica)"; continue }
    [System.IO.File]::WriteAllText($kopiaStanu, $orygStanu.Replace($s.Kotwica, $s.Na), (New-Object System.Text.UTF8Encoding($true)))
    . $kopiaStanu
    $pod = & $s.Proba
    . $PlikStanCyklu
    $po = & $s.Proba
    Sprawdz "sabotaz '$($s.Nazwa)' zlapany przez '$($s.Proba)'" ((-not $pod[0]) -and $po[0]) "z sabotazem: $($pod[1]) || po przywroceniu: $($po[1])"
  }
  $kod = $(if ($script:Zle -eq 0) { 0 } else { 1 })
} catch {
  Write-Host "BLAD  test sie wywrocil: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)"
  $kod = 1
} finally {
  if (-not $Zostaw) { Remove-Item -LiteralPath $Katalog -Recurse -Force -ErrorAction SilentlyContinue }
  else { Write-Host "zostawione: $Katalog" }
}

Write-Host ""
if ($kod -eq 0) { Write-Host "test-cykl-reczny: wszystko OK" } else { Write-Host "test-cykl-reczny: $($script:Zle) BLEDOW" }
exit $kod
