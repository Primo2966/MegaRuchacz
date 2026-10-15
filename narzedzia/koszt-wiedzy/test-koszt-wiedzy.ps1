# Proba strony "Koszt tworzenia wiedzy z rozmow" (narzedzia\koszt-wiedzy\koszt-wiedzy.ps1).
# Wszystko w %TEMP%: sztuczny katalog domowy z dziennikami obu wersji i z atrapami transkryptow
# Claude Code. Zero wolan modelu, zero sieci, zadnego okna - przegladarki test nie otwiera.
#   powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File narzedzia\koszt-wiedzy\test-koszt-wiedzy.ps1 [-Zostaw]
# Kod wyjscia: 0 = wszystkie proby przeszly, 1 = ktoras nie.
#
# Co musi byc prawda:
#   - liczenie: dzien tanszej wersji z zakres_do (bez zakresu - dzien przed przebiegiem), dwa
#     przebiegi jednego dnia sie sumuja, cale zuzycie dnia = ten sam licznik co okno nadzorcy
#     (odpowiedz w kilku liniach liczona raz, najwieksze wartosci; workerzy wliczeni),
#   - procenty: od calego dnia z odczytem z cache i bez niego, suma okresu od dni z danymi,
#   - brak dziennika pelnej wersji: strona powstaje, karta "brak danych", proba z 14.10 w tabeli,
#   - dzien z bledem przebiegu (obu wersji) na czerwono z opisem,
#   - dni zakonczone ida do pliku podrecznego i nie licza sie drugi raz.
# Proby negatywne (kazda MUSI byc zlapana): brak licznika, uciety modul, zepsuta linia dziennika
# pelnej wersji i tanszej, zepsuty plik podreczny, zly -Dzis.

param(
  [string]$Zrodlo = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
  [switch]$Zostaw
)

$ErrorActionPreference = "Stop"
$Katalog = Join-Path $env:TEMP ("mr-test-koszt-wiedzy-" + (Get-Date -Format "yyyyMMdd-HHmmss") + "-" + $PID)
$H = Join-Path $Katalog "dom"
$Wiedza = Join-Path $H ".claude\wiedza"
$Mr = Join-Path $H ".claude\mr"
$Projekty = Join-Path $H ".claude\projects"
$Strona = Join-Path $Katalog "strona.html"
$Generator = Join-Path $Zrodlo "narzedzia\koszt-wiedzy\koszt-wiedzy.ps1"
$UTF8 = New-Object System.Text.UTF8Encoding($false)
$script:Zle = 0

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
function Generuj([string[]]$dodatki = @(), [string]$skrypt = $Generator) {
  if (Test-Path -LiteralPath $Strona) { Remove-Item -LiteralPath $Strona -Force }
  $arg = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $skrypt, "-KatalogDomowy", $H,
           "-Wyjscie", $Strona) + $dodatki
  if ($dodatki -notcontains "-Dzis") { $arg += @("-Dzis", "2026-10-20") }
  $wy = & powershell.exe @arg 2>&1
  return [pscustomobject]@{ Kod = $LASTEXITCODE; Tekst = (($wy | ForEach-Object { "$_" }) -join "`n"); Html = (Czytaj $Strona) }
}
# Odpowiedz modelu w formacie transkryptu Claude Code (to, co czyta licznik okna nadzorcy)
function Linia-Odpowiedzi($id, $czas, $we, $tw, $od, $wy) {
  return ('{"type":"assistant","message":{"id":"' + $id + '","role":"assistant","model":"claude-test","content":[],"usage":{"input_tokens":' +
          $we + ',"cache_creation_input_tokens":' + $tw + ',"cache_read_input_tokens":' + $od + ',"output_tokens":' + $wy + '}},"timestamp":"' + $czas + '"}')
}

try {
  # ------------------------------------------------------------- dane wejsciowe
  $nag = "kiedy`tnarzedzie`twywolania`ttokeny`ttokeny_zrodlo`tznaki_wyslane`tznaki_odebrane`twiadomosci`tzakres_od`tzakres_do`tfakty"
  Zapisz (Join-Path $Wiedza ".koszt-historia.tsv") (@(
    $nag,
    "2026-10-16 08:00`tclaude`t1`t500`tpomiar`t1`t1`t1`t`t`t1",
    "2026-10-18 08:00`tclaude`t1`t1000`tpomiar`t1`t1`t1`t2026-10-17 08:00`t2026-10-17 10:00`t1",
    "2026-10-18 09:00`tclaude`t1`t2000`tpomiar`t1`t1`t1`t2026-10-17 12:00`t2026-10-17 18:00`t2",
    "2026-10-19 08:00`tclaude`t1`t30000`tpomiar`t1`t1`t1`t2026-10-16 09:00`t2026-10-18 18:00`t5",
    "smiec bez tabulatorow",
    "2026-10-20 08:05`tclaude`t1`t12000`tpomiar`t1`t1`t1`t2026-10-19 08:00`t2026-10-19 18:00`t8"
  ) -join "`r`n")
  Zapisz (Join-Path $Wiedza "cykl-ostatni.txt") "data: 2026-10-17 08:00`r`nstatus: odlozony`r`npowod: brak sieci`r`nopis: cykl odlozony (brak sieci)`r`n"
  $plikPelnej = Join-Path $Mr "wiedza-firmy\koszty.jsonl"
  $jsonl = @(
    '{"dzien":"2026-10-19","czas":"2026-10-20T03:00:00","wersja":"pelny","wywolan":20,"wejscie":0,"cache_zapis":200000,"cache_odczyt":200000,"wyjscie":200000,"razem":600000,"usd":1.2,"faktow":60,"ok":true,"blad":null}',
    '{"dzien":"2026-10-18","czas":"2026-10-19T03:00:00","wersja":"pelny","wywolan":1,"wejscie":1000,"cache_zapis":0,"cache_odczyt":0,"wyjscie":0,"razem":1000,"usd":0.01,"faktow":0,"ok":false,"blad":"limit wyczerpany"}',
    '{zepsute'
  ) -join "`n"
  Zapisz $plikPelnej $jsonl
  # Transkrypty: 19.10 = 6 000 000 tokenow (odczyt z cache 5 000 000), w tym odpowiedz zapisana
  # w dwoch liniach (pierwsza z czesciowym output) i worker w ...\subagents\; 18.10 = 1 000 000 bez cache.
  Zapisz (Join-Path $Projekty "proj\sesja.jsonl") (@(
    (Linia-Odpowiedzi "msg_a" "2026-10-19T10:00:00.000Z" 0 100000 3000000 1),
    (Linia-Odpowiedzi "msg_a" "2026-10-19T10:00:01.000Z" 0 100000 3000000 400000),
    (Linia-Odpowiedzi "msg_c" "2026-10-18T10:00:00.000Z" 1000000 0 0 0),
    '{"type":"user","message":{"role":"user","content":"tekst z \"usage\":{ w srodku"},"timestamp":"2026-10-19T09:00:00.000Z"}'
  ) -join "`n")
  Zapisz (Join-Path $Projekty "proj\sesja\subagents\agent-1.jsonl") (Linia-Odpowiedzi "msg_b" "2026-10-19T11:00:00.000Z" 0 500000 2000000 0)

  # ------------------------------------------------------------- A. funkcje
  Write-Host "--- A. funkcje (dane.ps1, strona.ps1)"
  $script:ModulyKosztuWiedzy = @{}
  . (Join-Path $Zrodlo "narzedzia\koszt-wiedzy\dane.ps1")
  . (Join-Path $Zrodlo "narzedzia\koszt-wiedzy\strona.ps1")
  $t = Czytaj-Tansza (Join-Path $Wiedza ".koszt-historia.tsv")
  Sprawdz "tansza: dzien z zakres_do (przebieg 20.10 -> rozmowy 19.10)" ($t.Dni["2026-10-19"].Tokeny -eq 12000)
  Sprawdz "tansza: dwa przebiegi jednego dnia rozmow sie sumuja (tokeny, fakty, przebiegi)" (($t.Dni["2026-10-17"].Tokeny -eq 3000) -and ($t.Dni["2026-10-17"].Fakty -eq 3) -and ($t.Dni["2026-10-17"].Przebiegi -eq 2))
  Sprawdz "tansza: przebieg bez zakresu -> dzien przed przebiegiem" ($t.Dni["2026-10-15"].Tokeny -eq 500)
  Sprawdz "tansza: zepsuta linia policzona, nie zgadnieta" ($t.Pominiete -eq 1) "Pominiete=$($t.Pominiete)"
  $p = Czytaj-Pelna $plikPelnej
  Sprawdz "pelna: dobry dzien wczytany" (($p.Dni["2026-10-19"].Razem -eq 600000) -and ($p.Dni["2026-10-19"].Faktow -eq 60) -and $p.Dni["2026-10-19"].Ok)
  Sprawdz "pelna: dzien z bledem ma opis" ((-not $p.Dni["2026-10-18"].Ok) -and ($p.Dni["2026-10-18"].Blad -eq "limit wyczerpany"))
  Sprawdz "pelna: zepsuta linia policzona" ($p.Zle -eq 1) "Zle=$($p.Zle)"
  $dwa = Join-Path $Katalog "dwa.jsonl"
  Zapisz $dwa (@('{"dzien":"2026-10-10","ok":false,"blad":"x","faktow":9,"wejscie":5,"cache_zapis":5,"cache_odczyt":5,"wyjscie":5,"usd":0.5}',
    '{"dzien":"2026-10-10","ok":true,"razem":100,"faktow":4,"usd":0.25,"wywolan":3}',
    '{"dzien":"2026-10-11","ok":false,"blad":"pierwszy","razem":10}',
    '{"dzien":"2026-10-11","ok":false,"blad":"drugi","razem":10}') -join "`n")
  $p2 = Czytaj-Pelna $dwa
  $d10 = $p2.Dni["2026-10-10"]
  Sprawdz "pelna: kilka prob dnia - tokeny i $ sumowane, fakty z ostatniej udanej, dzien udany" (($d10.Razem -eq 120) -and ([math]::Abs($d10.Usd - 0.75) -lt 1e-9) -and ($d10.Faktow -eq 4) -and $d10.Ok -and ($null -eq $d10.Blad) -and ($d10.NieudaneWczesniej -eq 1)) "$($d10 | Out-String)"
  $d11 = $p2.Dni["2026-10-11"]
  Sprawdz "pelna: zadna proba nie przeszla = blad z liczba prob i ostatnim bledem" ((-not $d11.Ok) -and ($d11.Razem -eq 20) -and ($d11.Blad -eq "2 prób, żadna nie przeszła; ostatni błąd: drugi")) "$($d11.Blad)"
  $brakP = Dolacz-Probe (Czytaj-Pelna (Join-Path $Katalog "nie-ma.jsonl"))
  Sprawdz "pelna: brak dziennika = Jest false + proba 14.10" ((-not $brakP.Jest) -and $brakP.Dni["2026-10-14"].Proba -and ($brakP.Dni["2026-10-14"].Razem -eq 300120) -and ($brakP.Dni["2026-10-14"].Faktow -eq 63))
  $bt = Blad-Tanszej (Join-Path $Wiedza "cykl-ostatni.txt")
  Sprawdz "tansza: odlozony cykl 17.10 = blad dnia rozmow 16.10" (($bt.Dzien -eq "2026-10-16") -and ($bt.Opis -match "brak sieci"))
  Zapisz (Join-Path $Katalog "ok.txt") "data: 2026-10-17 08:00`r`nstatus: ok`r`n"
  Sprawdz "tansza: cykl ok to nie blad" ($null -eq (Blad-Tanszej (Join-Path $Katalog "ok.txt")))
  Sprawdz "procenty po polsku" (((Proc-Pl 0.2) -eq "0,2%") -and ((Proc-Pl 12.4) -eq "12%") -and ((Proc-Pl 0.0123) -eq "0,012%") -and ((Proc-Pl $null) -eq "?"))
  Sprawdz "odmiana" (((Odmiana 1 "fakt" "fakty" "faktów") -eq "fakt") -and ((Odmiana 3 "fakt" "fakty" "faktów") -eq "fakty") -and ((Odmiana 12 "fakt" "fakty" "faktów") -eq "faktów") -and ((Odmiana 22 "fakt" "fakty" "faktów") -eq "fakty"))
  $cale = [pscustomobject]@{ Dni = @{ "2026-10-19" = [pscustomobject]@{ Razem = [long]6000000; Odczyt = [long]5000000 } } }
  $w = @(Zloz-Dni @("2026-10-19") $t $null $p $cale)
  Sprawdz "procent z cache i bez cache, iloraz" ((([math]::Abs($w[0].ProcTansza - 0.2)) -lt 1e-9) -and (([math]::Abs($w[0].ProcPelna - 10)) -lt 1e-9) -and
    (([math]::Abs($w[0].ProcTanszaBezCache - 1.2)) -lt 1e-9) -and (([math]::Abs($w[0].ProcPelnaBezCache - 40)) -lt 1e-9) -and (([math]::Abs($w[0].Iloraz - 50)) -lt 1e-9)) `
    "$($w[0].ProcTansza) $($w[0].ProcPelna) $($w[0].ProcTanszaBezCache) $($w[0].ProcPelnaBezCache) $($w[0].Iloraz)"

  # ------------------------------------------------------------- B. caly przebieg
  Write-Host "--- B. caly przebieg na sztucznym katalogu domowym"
  $g = Generuj
  Sprawdz "kod 2 (strona jest, ale dzienniki maja zepsute linie - to musi byc powiedziane)" ($g.Kod -eq 2) "kod $($g.Kod): $($g.Tekst)"
  Sprawdz "strona zapisana" ($g.Html -match "<h1>Koszt tworzenia wiedzy z rozmów</h1>")
  Sprawdz "uwagi o zepsutych liniach na stronie" (($g.Html -match "1 linii dziennika .*koszty\.jsonl nie da się odczytać") -and ($g.Html -match "1 linii dziennika .*koszt-historia\.tsv nie da się odczytać"))
  Sprawdz "karty: wczoraj 19.10, cały dzień 6,0 mln" ($g.Html -match "Wczoraj, 19\.10\.2026</b> · cały dzień Claude: 6,0 mln")
  Sprawdz "karta tanszej: 12 000 tokenow, 0,2%, 8 faktow, 1 wywolanie" (($g.Html -match "12 000 <small>tokenów") -and ($g.Html -match "0,2% całego dnia") -and ($g.Html -match "8 faktów · 1 wywołanie"))
  Sprawdz "karta pelnej: 600 000, 10%, 60 faktow, 20 wywolan, koszt" (($g.Html -match "600 000 <small>tokenów") -and ($g.Html -match "10% całego dnia") -and ($g.Html -match "60 faktów · 20 wywołań") -and ($g.Html -match "koszt: 1,20 \$"))
  Sprawdz "pelna = 50x tansza" ($g.Html -match "<b>50×</b>")
  Sprawdz "cale zuzycie 18.10 = 1,0 mln (ten sam licznik: odpowiedz raz, najwieksze wartosci)" ($g.Html -match "18\.10\.2026 nd</td><td>1,0</td>")
  Sprawdz "dzien z bledem pelnej wersji na czerwono z opisem" (($g.Html -match '<tr class="zbledem"><td>18\.10\.2026') -and ($g.Html -match "Pełna wersja: limit wyczerpany"))
  Sprawdz "dzien z bledem tanszej (cykl odlozony) na czerwono z opisem" (($g.Html -match '<tr class="zbledem"><td>16\.10\.2026') -and ($g.Html -match "Tańsza wersja: poranny automat 2026-10-17 08:00: cykl odlozony \(brak sieci\)"))
  Sprawdz "proba z 14.10 w tabeli, oznaczona" ($g.Html -match '14\.10\.2026 śr</td><td>0</td>.*?<span class="znacznik">próba</span> 300 120')
  Sprawdz "nadrabianie opisane przy dniu 18.10? (karty pokazuja 19.10 - tylko tabela: 30 000, 3%)" ($g.Html -match "18\.10\.2026 nd</td><td>1,0</td><td>30 000</td><td>3%</td><td>5</td>")
  Sprawdz "suma okresu: tansza 42 000 = 0,6%, pelna 601 000 = 8,6% (w tym proba nie - ten dzien bez rozmow)" (($g.Html -match "42 000 tokenów w 2 dniach = 0,6%") -and ($g.Html -match "601 000 tokenów w 2 dniach = 8,6%"))
  Sprawdz "stopka: % z cache i drugi % bez cache" (($g.Html -match "razem z odczytem z cache \(w tym okresie 71% wszystkich tokenów\)") -and ($g.Html -match "tańsza najwyżej 2,1%, pełna 20% całego zużycia"))
  Sprawdz "wykres SVG w pliku, nic z sieci" (($g.Html -match "<svg viewBox") -and ($g.Html -notmatch "https?://") -and ($g.Html -notmatch "<script"))
  $pod = Join-Path $Mr "koszt-wiedzy-dni.tsv"
  Sprawdz "plik podreczny zapisany (dni 14-19.10)" (@((Czytaj $pod) -split '\r?\n' | Where-Object { $_ -match '^2026-10-1[4-9]\t' }).Count -eq 6) (Czytaj $pod)

  # ------------------------------------------------------------- C. plik podreczny
  Write-Host "--- C. dni zakonczone nie licza sie drugi raz"
  Zapisz $pod ((Czytaj $pod) -replace "(?m)^2026-10-18\t2\t1000000\t", "2026-10-18`t2`t7777777`t")
  Remove-Item -LiteralPath $Projekty -Recurse -Force
  $g = Generuj
  Sprawdz "liczby z pliku podrecznego (zmieniony 18.10 = 7,8 mln), bez transkryptow" (($g.Html -match "18\.10\.2026 nd</td><td>7,8</td>") -and ($g.Tekst -match "6 z pliku podrecznego, 0 policzone teraz")) $g.Tekst
  Zapisz $pod ((Czytaj $pod) + "2026-10-18`t2`tsmiec`n")
  $g = Generuj
  Sprawdz "NEG zepsuta linia pliku podrecznego - uwaga, nie cisza" ($g.Html -match "plik podręczny całego zużycia .*1 nieczytelnych linii") $g.Tekst

  # ------------------------------------------------------------- D. brak dziennika pelnej wersji
  Write-Host "--- D. brak dziennika pelnej wersji"
  Remove-Item -LiteralPath $plikPelnej -Force
  $g = Generuj
  Sprawdz "strona powstaje, karta pelnej: brak danych" (($g.Kod -ne 1) -and ($g.Html -match '<section class="karta p"><h3>Pełne czytanie dnia \(wiedza firmy\)</h3><div class="brak">brak danych</div>'))
  Sprawdz "powod: dziennika jeszcze nie ma - i to nie jest uwaga na gorze" (($g.Html -match "dziennika pełnej wersji jeszcze nie ma") -and ($g.Html -notmatch "<li>Pełna wersja"))
  Sprawdz "proba opisana: po optymalizacji (wykres)" ($g.Html -match "14\.10\.2026 · pełna: 300 120 tokenów \(próba 14\.10 \(po optymalizacji\)\)")
  Sprawdz "proba z 14.10 dalej w tabeli" ($g.Html -match '<span class="znacznik">próba</span> 300 120')

  # ------------------------------------------------------------- E. proby negatywne
  Write-Host "--- E. proby negatywne"
  $bezLicznika = Join-Path $Katalog "zrodlo-bez-licznika"
  New-Item -ItemType Directory -Force -Path $bezLicznika | Out-Null
  Remove-Item -LiteralPath $pod -Force
  $g = Generuj @("-Zrodlo", $bezLicznika)
  Sprawdz "NEG brak licznika: kod 2, uwaga na stronie, procenty '?'" (($g.Kod -eq 2) -and ($g.Html -match "Całe zużycie dnia nie jest policzone") -and ($g.Html -match "\?\s*całego dnia")) "kod $($g.Kod)"
  $kopia = Join-Path $Katalog "kopia-generatora"
  New-Item -ItemType Directory -Force -Path $kopia | Out-Null
  Copy-Item (Join-Path $Zrodlo "narzedzia\koszt-wiedzy\*.ps1") $kopia
  $dane = Join-Path $kopia "dane.ps1"
  [System.IO.File]::WriteAllText($dane, ((Czytaj $dane) -replace '(?m)^\$script:ModulyKosztuWiedzy\["dane"\] = \$true\s*$', ''), (New-Object System.Text.UTF8Encoding($true)))
  $g = Generuj @("-Zrodlo", $Zrodlo) (Join-Path $kopia "koszt-wiedzy.ps1")
  Sprawdz "NEG uciety modul: kod 1 i powod, zadnej strony udajacej sukces" (($g.Kod -eq 1) -and ($g.Tekst -match "nie wczytal sie do konca") -and (-not $g.Html)) "kod $($g.Kod): $($g.Tekst)"
  $g = Generuj @("-Dzis", "jutro")
  Sprawdz "NEG zly -Dzis: kod 1, strona bledu z powodem" (($g.Kod -eq 1) -and ($g.Html -match "Strony nie udało się zbudować") -and ($g.Html -match "zly parametr -Dzis")) "kod $($g.Kod)"

  # ------------------------------------------------------------- F. wpiecia
  Write-Host "--- F. wpiecia w cykl dzienny i menu zasobnika"
  foreach ($plik in @("narzedzia\cykl-dzienny.ps1", "zasobnik\nadzorca.ps1")) {
    $bledy = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Zrodlo $plik), [ref]$null, [ref]$bledy)
    Sprawdz "$plik parsuje sie bez bledow" (@($bledy).Count -eq 0) "$bledy"
  }
  $cykl = Czytaj (Join-Path $Zrodlo "narzedzia\cykl-dzienny.ps1")
  Sprawdz "cykl: jedno wywolanie po porannym czytaniu" (([regex]::Matches($cykl, '(?m)^\s+Odswiez-Koszt-Wiedzy\s*$').Count -eq 1) -and ($cykl -match '\$kodWeryfikacji = Sprawdz-Wiedze\r?\n\s+Odswiez-Koszt-Wiedzy'))
  $nadz = Czytaj (Join-Path $Zrodlo "zasobnik\nadzorca.ps1")
  Sprawdz "menu: pozycja 'Koszt tworzenia wiedzy' wola generator z -Otworz" (($nadz -match 'Nowa-Pozycja "Koszt tworzenia wiedzy"') -and ($nadz -match 'koszt-wiedzy\\koszt-wiedzy\.ps1') -and ($nadz -match '-Otworz"'))
} catch {
  Sprawdz "test przeszedl bez wywrotki" $false "$($_.Exception.Message) (linia $($_.InvocationInfo.ScriptLineNumber))"
} finally {
  if (-not $Zostaw) {
    try { Remove-Item -LiteralPath $Katalog -Recurse -Force -ErrorAction Stop }
    catch { Write-Host "UWAGA: nie udalo sie sprzatnac $Katalog ($($_.Exception.Message))" }
  } else { Write-Host "zostawione: $Katalog" }
}

if ($script:Zle -gt 0) { Write-Host "WYNIK: $($script:Zle) prob nie przeszlo"; exit 1 }
Write-Host "WYNIK: wszystkie proby przeszly"
exit 0
