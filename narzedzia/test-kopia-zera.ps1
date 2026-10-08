# Proba kopii zapasowej (narzedzia\kopia-zapasowa.ps1) i jej sprawy w oknie
# (zasobnik\nadzorca\stan-kopia.ps1) przy plikach z zerami - od 08.10.2026, gdy Przeglad
# pokazywal czerwona sprawe "pominela 21 plikow z samymi zerami", z czego 19 to smieci
# (kosz skilli, jednorazowy skrypt przypomnienia), a 2 to dzienniki z jedna dziura.
# Wszystko w %TEMP%: sztuczny katalog domowy i sztuczny cel kopii - prawdziwy G:\ ani dom
# nie sa ruszane. Kopia idzie przez -KatalogDomowy/-Zrodla/-Cel/-Data, okno bez okna
# (same funkcje stan-kopia.ps1 po wczytaniu stan-nadzorcy.ps1).
#   powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File narzedzia\test-kopia-zera.ps1 [-Zostaw]
# Kod wyjscia: 0 = wszystkie proby przeszly, 1 = ktoras nie.
#
# Scenariusz (dwa przebiegi kopii): 01.10 zdrowy dom -> pelna-2026-10-01; potem uszkodzenia
# i 02.10 -> zmiany\2026-10-02. Uszkodzenia:
#   history.jsonl         blok 847 B zer od bajtu 5000, potem dopisane linie (ok. 6%)
#   mr\przypomnienia.log  blok 311 B zer od bajtu 2960 w 5 411 B (5,75% - jak naprawde)
#   wiedza\zly.md         caly z zer, zdrowa wersja w pelna-2026-10-01
#   mr\nowy.md            caly z zer, nowy - zadnej wersji w kopii
#   mr\duzo-zer.log       25% zer w srodku (ponad prog)       - alarm
#   mr\ogon.log           zera na samym koncu (swieze)        - alarm
#   skills\.trash\...     caly z zer, kosz skilli             - wykluczony, bez alarmu
#   mr\terminy\zrob-1.ps1 caly z zer, skrypt startowy         - wykluczony, bez alarmu
# Proby negatywne: sabotaze na kopii skryptu kopii (wykluczenie kosza usuniete, dziura
# pominieta jak dawniej, plik caly z zer wziety do kopii) i na kopii stan-kopia.ps1 (usuniety
# plik dalej "uszkodzony", dziura dalej "uszkodzona") - kazdy MUSI byc zlapany.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Zostaw
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 }
catch { Write-Host "UWAGA: konsola nie przestawila sie na UTF-8 ($($_.Exception.Message)) - porownania z ogonkami moga pasc" }
$T = Join-Path $env:TEMP ("mr-kz-" + (Get-Date -Format "MMdd-HHmmss"))
$script:Zle = 0
$bezBom = New-Object System.Text.UTF8Encoding($false)
$zBom = New-Object System.Text.UTF8Encoding($true)

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

function Linie([string]$co, [int]$od, [int]$ile) {
  $sb = New-Object System.Text.StringBuilder
  for ($i = $od; $i -lt $od + $ile; $i++) { [void]$sb.Append("{""display"":""$co numer $i"",""timestamp"":17913540$('{0:D5}' -f $i)}`n") }
  return $sb.ToString()
}
function Zapisz([string]$p, [byte[]]$b) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
  [System.IO.File]::WriteAllBytes($p, $b)
}
function Tekst([string]$p, [string]$t) { Zapisz $p ($bezBom.GetBytes($t)) }
function Zera([string]$p, [int]$od, [int]$ile) {
  $b = [System.IO.File]::ReadAllBytes($p)
  for ($i = $od; $i -lt $od + $ile; $i++) { $b[$i] = 0 }
  [System.IO.File]::WriteAllBytes($p, $b)
}
function Odmlodz([string]$p) { [System.IO.File]::SetLastWriteTime($p, (Get-Date).AddMinutes(5)) }
function Skrot([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Napis-Dlugi([int]$dl) {
  $sb = New-Object System.Text.StringBuilder
  $i = 0
  while ($sb.Length -lt $dl) { [void]$sb.Append("2026-10-0$((($i % 9) + 1)) 12:00:00 przypomnienie #$i - wpis dziennika`n"); $i++ }
  return $sb.ToString().Substring(0, $dl)
}

# Zdrowy dom (przed 1. przebiegiem).
function Przygotuj-Dom([string]$H) {
  $c = Join-Path $H ".claude"
  Tekst "$c\CLAUDE.md" "# Ustalenia globalne`n`n## Co wiem`n`n- [2026-10-01] Fakt testowy.`n"
  Tekst "$c\history.jsonl" (Linie "wiadomosc" 0 200)
  Tekst "$c\mr\przypomnienia.log" (Napis-Dlugi 5411)
  Tekst "$c\wiedza\zly.md" ("# Plik wiedzy`n`n" + ("- zdrowy wpis wiedzy o firmie`n" * 60))
  Tekst "$c\skills\dobry\SKILL.md" "---`nname: dobry`n---`n# Dobry skill`n"
  # smieci, ktore naprawde byly wyzerowane 08.10 - maja byc wykluczone, nie alarmowane
  Zapisz "$c\skills\.trash\1791354082537-8600-Pu5peb\google-workspace\SKILL.md" (New-Object byte[] 14863)
  Zapisz "$c\mr\terminy\zrob-1.ps1" (New-Object byte[] 1022)
}

# Uszkodzenia miedzy 1. a 2. przebiegiem.
function Uszkodz-Dom([string]$H) {
  $c = Join-Path $H ".claude"
  Zera "$c\history.jsonl" 5000 847
  [System.IO.File]::AppendAllText("$c\history.jsonl", (Linie "pozniejsza" 0 20), $bezBom)
  Odmlodz "$c\history.jsonl"
  Zera "$c\mr\przypomnienia.log" 2960 311
  Odmlodz "$c\mr\przypomnienia.log"
  $n = (Get-Item -LiteralPath "$c\wiedza\zly.md").Length
  [System.IO.File]::WriteAllBytes("$c\wiedza\zly.md", (New-Object byte[] $n))
  Odmlodz "$c\wiedza\zly.md"
  Zapisz "$c\mr\nowy.md" (New-Object byte[] 900)
  Tekst "$c\mr\duzo-zer.log" (Napis-Dlugi 4000); Zera "$c\mr\duzo-zer.log" 1500 1000
  Tekst "$c\mr\ogon.log" (Napis-Dlugi 5000); [System.IO.File]::AppendAllText("$c\mr\ogon.log", (New-Object string ([char]0), 100), $bezBom)
}

# Caly scenariusz kopii na danym skrypcie w swiezym katalogu. Zwraca tablice prob
# (Nazwa -> @(ok, szczegol)), zeby te same proby ocenic na skrypcie prawdziwym i na sabotazu.
function Scenariusz([string]$skrypt, [string]$kat) {
  $H = Join-Path $kat "dom"; $cel = Join-Path $kat "cel"
  New-Item -ItemType Directory -Force -Path $cel | Out-Null
  Przygotuj-Dom $H
  $c = Join-Path $H ".claude"
  $zdrowaHistoria = Skrot "$c\history.jsonl"
  $wsp = @("-KatalogDomowy", $H, "-Zrodla", "$H\.claude", "-Cel", $cel)
  $r1 = Odpal $skrypt ($wsp + @("-Data", "2026-10-01"))
  Uszkodz-Dom $H
  $r2 = Odpal $skrypt ($wsp + @("-Data", "2026-10-02"))
  $stan = ""
  if (Test-Path -LiteralPath "$c\mr\kopia-stan.txt") { $stan = [System.IO.File]::ReadAllText("$c\mr\kopia-stan.txt") }
  $dziennik = ""
  if (Test-Path -LiteralPath "$cel\dziennik.txt") { $dziennik = [System.IO.File]::ReadAllText("$cel\dziennik.txt") }
  $w1 = "$cel\pelna-2026-10-01\C" + $H.Substring(2)
  $w2 = "$cel\zmiany\2026-10-02\C" + $H.Substring(2)
  $alarmy = @($stan -split "\r?\n" | Where-Object { $_ -match '^ALARM ' })
  $dziury = @($stan -split "\r?\n" | Where-Object { $_ -match '^DZIURA W PLIKU' })
  $p = [ordered]@{}
  $p["przebiegi kopii przeszly (kod 0, potem 2 = alarm)"] = @((($r1.Kod -eq 0) -and ($r2.Kod -eq 2)), "kody $($r1.Kod)/$($r2.Kod): $($r1.Tekst) || $($r2.Tekst)")
  $p["kosz skilli pominiety bez alarmu"] = @((-not ($stan -match 'skills\\\.trash')) -and -not (Test-Path -LiteralPath "$w1\.claude\skills\.trash"), "stan: $stan")
  $p["skrypt startowy zrob-1.ps1 pominiety bez alarmu"] = @((-not ($stan -match 'zrob-1\.ps1')) -and -not (Test-Path -LiteralPath "$w1\.claude\mr\terminy\zrob-1.ps1"), "stan: $stan")
  $hist2 = "$w2\.claude\history.jsonl"
  $p["history.jsonl z dziura skopiowany (bajt w bajt)"] = @(((Test-Path -LiteralPath $hist2) -and ((Skrot $hist2) -eq (Skrot "$c\history.jsonl"))), "w kopii: $(Test-Path -LiteralPath $hist2)")
  $p["poprzednia zdrowa history.jsonl nietknieta w pelna-2026-10-01"] = @(((Test-Path -LiteralPath "$w1\.claude\history.jsonl") -and ((Skrot "$w1\.claude\history.jsonl") -eq $zdrowaHistoria)), "")
  $dh = @($dziury | Where-Object { $_ -like "*\.claude\history.jsonl - *" })
  $p["wpis DZIURA dla history.jsonl: offset, dlugosc, poprzednia wersja"] = @((($dh.Count -eq 1) -and ($dh[0] -match 'od bajtu 5000 dl\. 847 B') -and
    $dh[0].Contains("ostatnia wersja w kopii: $w1\.claude\history.jsonl (z 2026-10-01)")), "wpisy: $($dziury -join ' | ')")
  $dp = @($dziury | Where-Object { $_ -like "*\.claude\mr\przypomnienia.log - *" })
  $p["przypomnienia.log z dziura skopiowany, wpis DZIURA 311 B od 2960"] = @(((Test-Path -LiteralPath "$w2\.claude\mr\przypomnienia.log") -and ($dp.Count -eq 1) -and ($dp[0] -match 'od bajtu 2960 dl\. 311 B')), "wpisy: $($dziury -join ' | ')")
  $p["dziury nie sa alarmem (dziury=2, alarmy=4)"] = @((($stan -match '(?m)^dziury=2\r?$') -and ($stan -match '(?m)^alarmy=4\r?$') -and -not ($alarmy -match 'history\.jsonl|przypomnienia\.log')), "alarmy: $($alarmy -join ' | ')")
  $p["dziury w dzienniku kopii"] = @((($dziennik -match 'DZIURA W PLIKU[^\r\n]*history\.jsonl') -and ($dziennik -match 'skopiowane mimo dziury 2')), "")
  $az = @($alarmy | Where-Object { $_ -like "*\.claude\wiedza\zly.md - *" })
  $p["zly.md (caly z zer) NIE skopiowany, alarm z miejscem zdrowej wersji"] = @(((-not (Test-Path -LiteralPath "$w2\.claude\wiedza\zly.md")) -and ($az.Count -eq 1) -and
    $az[0].Contains("ostatnia wersja w kopii: $w1\.claude\wiedza\zly.md (z 2026-10-01)")), "alarmy: $($alarmy -join ' | ')")
  $an = @($alarmy | Where-Object { $_ -like "*\.claude\mr\nowy.md - *" })
  $p["nowy.md (caly z zer) NIE skopiowany, alarm mowi, ze wersji nie ma"] = @(((-not (Test-Path -LiteralPath "$w2\.claude\mr\nowy.md")) -and ($an.Count -eq 1) -and ($an[0] -match 'w kopii nie ma zadnej wersji')), "alarmy: $($alarmy -join ' | ')")
  $p["25% zer w srodku i zera na koncu - dalej alarm, nie dziura"] = @(((-not (Test-Path -LiteralPath "$w2\.claude\mr\duzo-zer.log")) -and (-not (Test-Path -LiteralPath "$w2\.claude\mr\ogon.log")) -and
    (@($alarmy -match 'duzo-zer\.log').Count -eq 1) -and (@($alarmy -match 'ogon\.log').Count -eq 1)), "alarmy: $($alarmy -join ' | ')")
  return [pscustomobject]@{ Proby = $p; Dom = $H; Cel = $cel; W1 = $w1 }
}

$kopia = Join-Path $Zrodlo "narzedzia\kopia-zapasowa.ps1"
$plikStanuKopii = Join-Path $Zrodlo "zasobnik\nadzorca\stan-kopia.ps1"
try {
  New-Item -ItemType Directory -Force -Path $T | Out-Null

  # ---------------------------------------------------------------- A. kopia na prawdziwym skrypcie
  Write-Host "--- A. kopia (prawdziwy skrypt)"
  $Scen = Scenariusz $kopia (Join-Path $T "a")
  foreach ($n in $Scen.Proby.Keys) { Sprawdz $n $Scen.Proby[$n][0] $Scen.Proby[$n][1] }

  # ---------------------------------------------------------------- B. sprawa w oknie (stan-kopia.ps1)
  Write-Host "--- B. sprawa na Przegladzie i Szczegoly"
  . (Join-Path $Zrodlo "zasobnik\stan-nadzorcy.ps1")
  Ustaw-Nadzorce $Zrodlo $Scen.Dom $true
  $c = Join-Path $Scen.Dom ".claude"

  $k = Stan-Kopii; $o = Ocena-Kopii $k $null
  Sprawdz "4 cale/duze zera = czerwona sprawa z liczba i 'i 1 inny'" (($o.Alarm) -and ($o.AlarmWaga -eq "pilne") -and ($o.Tytul -like "*pominęła 4 pliki*") -and ($o.Porada -like "*i 1 inny*")) "tytul: $($o.Tytul) | porada: $($o.Porada)"
  Sprawdz "sprawa nie wspomina dziur ani smieci" (-not ("$($o.Porada) $($o.Tresc) $($o.Linia)" -match 'history\.jsonl|przypomnienia\.log|\.trash|zrob-1')) "porada: $($o.Porada) | tresc: $($o.Tresc)"

  Remove-Item -LiteralPath "$c\mr\duzo-zer.log", "$c\mr\ogon.log" -Force
  $k = Stan-Kopii; $o = Ocena-Kopii $k $null
  $wz = "$($Scen.W1)\.claude\wiedza\zly.md"
  Sprawdz "sprawa nazywa zly.md i mowi, skad wziac zdrowa wersje (sciezka i data)" ($o.Porada.Contains("~\.claude\wiedza\zly.md - zdrowa wersja jest w kopii z 2026-10-01: skopiuj $wz na miejsce uszkodzonego pliku") -and (Test-Path -LiteralPath $wz)) "porada: $($o.Porada)"
  Sprawdz "sprawa nazywa nowy.md i mowi wprost, ze wersji w kopii nie ma" ($o.Porada.Contains("~\.claude\mr\nowy.md - w kopii nie ma żadnej jego wersji")) "porada: $($o.Porada)"
  Sprawdz "linia na Przeglad z nazwami plikow" (($o.Waga -eq "pilne") -and $o.Linia.Contains("~\.claude\wiedza\zly.md") -and $o.Linia.Contains("~\.claude\mr\nowy.md")) "linia: $($o.Linia)"

  $wiersze = @(Opis-Kopii $k $null)
  $wd = @($wiersze | Where-Object { $_.Etykieta -eq "Skopiowane mimo dziury" })
  $wdl = @($wiersze | Where-Object { $_.Wartosc -like "*history.jsonl - 1 blok zer*" })
  Sprawdz "Szczegoly: dziury jako informacja (bez czerwieni), z plikiem i offsetem" (($wd.Count -eq 1) -and ($wd[0].Waga -ne "pilne") -and ($wd[0].Waga -ne "uwaga") -and ($wdl.Count -eq 1) -and ($wdl[0].Wartosc -match 'od bajtu 5000 dl\. 847 B')) "wiersze: $(($wiersze | ForEach-Object { "$($_.Etykieta)=$($_.Wartosc)[$($_.Waga)]" }) -join ' / ')"

  # naprawa: zly.md znow zdrowy, nowy.md usuniety -> sprawa znika sama
  function Napraw { Tekst "$c\wiedza\zly.md" "# Plik wiedzy`n`n- odtworzony`n"; Remove-Item -LiteralPath "$c\mr\nowy.md" -Force }
  function Zepsuj { Zapisz "$c\wiedza\zly.md" (New-Object byte[] 1200); Zapisz "$c\mr\nowy.md" (New-Object byte[] 900) }
  function Proba-Naprawy {
    $o = Ocena-Kopii (Stan-Kopii) $null
    return [pscustomobject]@{ Ok = ((-not $o.Alarm) -and ($o.Waga -ne "pilne") -and ($o.Linia -like "*nic nie trzeba robić*")); Opis = "alarm=$($o.Alarm) waga=$($o.Waga) linia: $($o.Linia)" }
  }
  Napraw
  $pn = Proba-Naprawy
  Sprawdz "po naprawie i usunieciu plikow sprawa znika" $pn.Ok $pn.Opis

  # stary zapis (sprzed 08.10): dziura w history.jsonl liczona jako uszkodzenie, kosz skilli tez.
  # Dziura juz nie jest "nadal uszkodzona" (kopia ja wezmie), kosz jest - i sprawa mowi, gdzie szukac.
  $stanA = [System.IO.File]::ReadAllText("$c\mr\kopia-stan.txt")
  $trash = "$c\skills\.trash\1791354082537-8600-Pu5peb\google-workspace\SKILL.md"
  $stary = "stan=ALARM`r`nostatnia=$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))`r`nrodzaj=przyrostowa`r`ncel=$($Scen.Cel)\zmiany\2026-10-02`r`nplikow=5`r`nmb=0.1`r`nalarmy=2`r`nbledy=0`r`n" +
           "ALARM WYZEROWANY PLIK - NIE skopiowany (zdrowa wersja zostaje w starszej kopii): $c\history.jsonl - blok co najmniej 847 bajtow 0x00 od bajtu 5000`r`n" +
           "ALARM WYZEROWANY PLIK - NIE skopiowany (zdrowa wersja zostaje w starszej kopii): $trash - blok co najmniej 14863 bajtow 0x00 od bajtu 0`r`n"
  [System.IO.File]::WriteAllText("$c\mr\kopia-stan.txt", $stary, $bezBom)
  function Proba-Starego {
    $k = Stan-Kopii; $o = Ocena-Kopii $k $null
    return [pscustomobject]@{ Ok = (($k.UszkodzoneTeraz -eq 1) -and $o.Alarm -and ($o.Porada -like "*google-workspace\SKILL.md - starszej wersji szukaj w kopii $($Scen.Cel) *") -and -not ($o.Porada -match 'history\.jsonl'))
                              Opis = "nadal=$($k.UszkodzoneTeraz) porada: $($o.Porada)" }
  }
  $ps = Proba-Starego
  Sprawdz "stary zapis: dziura juz nie jest alarmem, kosz nazwany z miejscem szukania" $ps.Ok $ps.Opis

  # ---------------------------------------------------------------- C. sabotaze stan-kopia.ps1
  Write-Host "--- C. proby negatywne na kopii stan-kopia.ps1"
  $oryginal = [System.IO.File]::ReadAllText($plikStanuKopii, [System.Text.Encoding]::UTF8)
  $kopiaSab = Join-Path $T "stan-kopia-sabotaz.ps1"
  $sabotazeOkna = @(
    @{ Nazwa = "usuniety plik dalej uszkodzony"; Kotwica = 'if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }'
       Zamiana = 'if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $lista += $w; continue }'; Przed = { Zepsuj; Napraw }; Proba = "Proba-Naprawy"; Stan = $stanA },
    @{ Nazwa = "dziura dalej uszkodzona"; Kotwica = 'if (-not $dziura) { $lista += $w }'; Zamiana = '$lista += $w'
       Przed = { }; Proba = "Proba-Starego"; Stan = $stary })
  foreach ($s in $sabotazeOkna) {
    if (-not $oryginal.Contains($s.Kotwica)) { Sprawdz "sabotaz '$($s.Nazwa)' zlapany" $false "kotwicy nie ma w ${plikStanuKopii}: $($s.Kotwica)"; continue }
    [System.IO.File]::WriteAllText($kopiaSab, $oryginal.Replace($s.Kotwica, $s.Zamiana), $zBom)
    & $s.Przed
    if ($s.Stan) { [System.IO.File]::WriteAllText("$c\mr\kopia-stan.txt", $s.Stan, $bezBom) }
    . $kopiaSab
    $pod = $null
    try { $pod = & $s.Proba } catch { $pod = [pscustomobject]@{ Ok = $false; Opis = "WYWROTKA: $($_.Exception.Message)" } }
    . $plikStanuKopii
    $po = & $s.Proba
    Sprawdz "sabotaz '$($s.Nazwa)' zlapany" ((-not $pod.Ok) -and $po.Ok) "z sabotazem: $($pod.Opis) || po przywroceniu: $($po.Opis)"
  }

  # ---------------------------------------------------------------- D. sabotaze kopia-zapasowa.ps1
  Write-Host "--- D. proby negatywne na kopii kopia-zapasowa.ps1"
  # Kopia skryptu obok kopii narzedzia\instalacja (umowa rejestru) - jak w repo.
  $katSab = Join-Path $T "zrodlo-sab\narzedzia"
  New-Item -ItemType Directory -Force -Path $katSab | Out-Null
  Copy-Item -Recurse (Join-Path $Zrodlo "narzedzia\instalacja") (Join-Path $katSab "instalacja")
  Copy-Item (Join-Path $Zrodlo "narzedzia\kopia-zapasowa-domyslne.json") $katSab
  $skryptSab = Join-Path $katSab "kopia-zapasowa.ps1"
  $orygKopii = [System.IO.File]::ReadAllText($kopia)
  $sabotaze = @(
    @{ Nazwa = "wykluczenie kosza skilli usuniete"; Proba = "kosz skilli pominiety bez alarmu"
       Kotwica = 'Regula "^$eH\\\.claude\\skills\\\.trash$"'; Zamiana = '# Regula "^$eH\\\.claude\\skills\\\.trash$"' },
    @{ Nazwa = "dziura pominieta jak dawniej (prog 0)"; Proba = "history.jsonl z dziura skopiowany (bajt w bajt)"
       Kotwica = '$ProgDziur = 0.10'; Zamiana = '$ProgDziur = 0' },
    @{ Nazwa = "plik caly z zer wziety do kopii jako dziura"; Proba = "zly.md (caly z zer) NIE skopiowany, alarm z miejscem zdrowej wersji"
       Kotwica = 'if (zera && (zaDuzo || zerowyKoniec || caly)) {'; Zamiana = 'if (zera && zaDuzo && !same) {' })
  $nr = 0
  foreach ($s in $sabotaze) {
    $nr++
    if (-not $orygKopii.Contains($s.Kotwica)) { Sprawdz "sabotaz '$($s.Nazwa)' zlapany" $false "kotwicy nie ma w ${kopia}: $($s.Kotwica)"; continue }
    [System.IO.File]::WriteAllText($skryptSab, $orygKopii.Replace($s.Kotwica, $s.Zamiana), $bezBom)
    $wyn = Scenariusz $skryptSab (Join-Path $T "s$nr")
    $proba = $wyn.Proby[$s.Proba]
    Sprawdz "sabotaz '$($s.Nazwa)' zlapany przez probe '$($s.Proba)'" ((-not $proba[0]) -and $Scen.Proby[$s.Proba][0]) "proba z sabotazem przeszla: $($proba[1])"
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
