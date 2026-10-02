# Proba negatywna zabezpieczenia przed wyzerowanymi plikami pamieci (awaria 2026-10-02).
# Wszystko dzieje sie w kopii: katalog domowy, projekt i katalog zrodlowy (bez .git - straznik
# nie siegnie wtedy do sieci ani do prawdziwego repo) w %TEMP%. Prawdziwe pliki nie sa ruszane.
#
# Uzycie:  powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File narzedzia\test-zera.ps1 [-Zostaw]
# Kod wyjscia: 0 = wszystkie proby przeszly, 1 = ktoras nie.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Zostaw
)

$ErrorActionPreference = "Stop"
$T = Join-Path $env:TEMP ("mr-test-zera-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$Z = Join-Path $T "zrodlo"
$H = Join-Path $T "dom"
$P = Join-Path $T "projekt"
$script:Wynik = @()
$script:Zle = 0

function Sprawdz([string]$co, [bool]$ok, [string]$szczegol = "") {
  $linia = $(if ($ok) { "OK    " } else { "BLAD  " }) + $co
  if (-not $ok -and $szczegol) { $linia += " -- $szczegol" }
  $script:Wynik += $linia
  Write-Host $linia
  if (-not $ok) { $script:Zle++ }
}

function Skrot-Pliku([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Skrot-Katalogu([string]$kat) {
  if (-not (Test-Path $kat)) { return "" }
  return (@(Get-ChildItem -LiteralPath $kat -Recurse -File -Force | Sort-Object FullName |
            ForEach-Object { $_.FullName.Substring($kat.Length) + "=" + (Skrot-Pliku $_.FullName) }) -join ";")
}
function Wyzeruj([string]$p) { $n = (Get-Item -LiteralPath $p).Length; [System.IO.File]::WriteAllBytes($p, (New-Object byte[] $n)) }
function Wyzeruj-Ogon([string]$p, [int]$ile) {
  $b = [System.IO.File]::ReadAllBytes($p)
  for ($i = $b.Length - $ile; $i -lt $b.Length; $i++) { $b[$i] = 0 }
  [System.IO.File]::WriteAllBytes($p, $b)
}
function Odpal([string]$skrypt, [string[]]$argumenty) {
  $ErrorActionPreference = "Continue"   # stderr skryptu to tresc do sprawdzenia, nie wyjatek
  $wy = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File $skrypt @argumenty 2>&1
  return [pscustomobject]@{ Kod = $LASTEXITCODE; Tekst = (($wy | ForEach-Object { "$_" }) -join "`n") }
}
function Ma-Zero([string]$p) { return ([Array]::IndexOf([System.IO.File]::ReadAllBytes($p), [byte]0) -ge 0) }
function Pliki-Bak { return @(Get-ChildItem -LiteralPath (Join-Path $H ".claude") -File -Force -Filter "CLAUDE.md.bak-*").Count }

try {
  # ------------------------------------------------------------ kopia zrodla i domu
  New-Item -ItemType Directory -Force -Path $Z, $P, (Join-Path $H ".claude\wiedza"), (Join-Path $H ".codex"),
    (Join-Path $H ".config\opencode") | Out-Null
  foreach ($k in @("narzedzia", "szablony-global", "szablony-opencode", "szablony-codex", "zasobnik")) {
    if (Test-Path (Join-Path $Zrodlo $k)) { Copy-Item -Recurse (Join-Path $Zrodlo $k) (Join-Path $Z $k) }
  }
  foreach ($f in @("zasady-globalne.md", "ZMIANY.md")) { Copy-Item (Join-Path $Zrodlo $f) (Join-Path $Z $f) }

  $nl = "`n"
  [System.IO.File]::WriteAllText((Join-Path $H ".claude\CLAUDE.md"),
    "# Ustalenia globalne$nl$nl## Co wiem$nl$nl- [2026-10-01] Fakt testowy.$nl", (New-Object System.Text.UTF8Encoding($false)))
  $w = Odpal (Join-Path $Z "narzedzia\wpisz-zasady.ps1") @("-Zrodlo", $Z, "-KatalogDomowy", $H)
  Sprawdz "zdrowy dom: wpisz-zasady wpisuje blok" ($w.Kod -eq 0) $w.Tekst
  Set-Content -LiteralPath (Join-Path $H ".config\opencode\AGENTS.md") -Value "# wlasny plik opencode uzytkownika" -Encoding ASCII
  $wiedza = Join-Path $H ".claude\wiedza"
  Set-Content -LiteralPath (Join-Path $wiedza "kandydaci.md") -Value "# Kandydaci do trwalej wiedzy" -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $wiedza "zrodla.md") -Value ("# Skad sie wziely fakty`r`n" + ("- 2026-10-01 | wpisany | x`r`n" * 50)) -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $wiedza ".ostatnie-wyciaganie") -Value "2026-10-01T06:00:00.000Z" -Encoding ASCII
  $wczoraj = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
  Set-Content -LiteralPath (Join-Path $wiedza ".cykl-stan") -Value "data: $wczoraj`r`nstatus: ok" -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $H ".claude\.megaruchacz-global") -Value "zrodlo: $Z`r`nwariant: claude" -Encoding ASCII
  $kopie = Join-Path $Z "narzedzia\kopie-dzienne.ps1"
  $claude = Join-Path $H ".claude\CLAUDE.md"
  $baza = Join-Path $H ".claude\mr\kopie-dzienne"

  # ------------------------------------------------------------ zdrowy dom
  $r = Odpal $kopie @("-Rotuj", "-KatalogDomowy", $H, "-Zrodlo", $Z)
  Sprawdz "zdrowy dom: rotacja robi kopie 'wczoraj'" (($r.Kod -eq 0) -and (Test-Path (Join-Path $baza "wczoraj\.claude\CLAUDE.md"))) $r.Tekst
  $r = Odpal $kopie @("-Rotuj", "-KatalogDomowy", $H, "-Zrodlo", $Z)
  Sprawdz "zdrowy dom: druga rotacja tego samego dnia nic nie robi" (($r.Kod -eq 0) -and ($r.Tekst -match "dzisiejsza juz jest")) $r.Tekst
  $s = Odpal (Join-Path $Z "narzedzia\straznik-zasad.ps1") @("-Zrodlo", $Z, "-Projekt", $P, "-KatalogDomowy", $H)
  Sprawdz "zdrowy dom: straznik bez alarmu o zerach" ($s.Tekst -notmatch "wyzerowane") $s.Tekst
  # sciezka zdrowa nie moze byc zablokowana: usuniety blok Lore straznik ma wpisac z powrotem
  # (do 0.25.2 pierwsza wersja kontroli zer brala pusta liste za jeden wyzerowany plik)
  $trescCm = [System.IO.File]::ReadAllText($claude)   # nie $t - PowerShell nie rozroznia wielkosci liter, a $T to katalog testu
  $i = $trescCm.IndexOf("<!-- MegaRuchacz:start -->"); $j = $trescCm.IndexOf("<!-- MegaRuchacz:koniec -->")
  [System.IO.File]::WriteAllText($claude, $trescCm.Substring(0, $i) + $trescCm.Substring($j + 27), (New-Object System.Text.UTF8Encoding($false)))
  $s = Odpal (Join-Path $Z "narzedzia\straznik-zasad.ps1") @("-Zrodlo", $Z, "-Projekt", $P, "-KatalogDomowy", $H)
  Sprawdz "zdrowy dom: straznik wpisuje usuniety blok z powrotem" ([System.IO.File]::ReadAllText($claude).Contains("<!-- MegaRuchacz:start -->")) $s.Tekst
  $stanS = [System.IO.File]::ReadAllText((Join-Path $H ".claude\.megaruchacz-straznik.txt"))
  Sprawdz "zdrowy dom: straznik bez wywrotek" ($stanS -notmatch "blad\.\d") $stanS

  # ------------------------------------------------------------ CLAUDE.md wyzerowany
  Wyzeruj $claude
  $przed = Skrot-Pliku $claude
  $bakPrzed = Pliki-Bak
  $ocPrzed = Skrot-Pliku (Join-Path $H ".config\opencode\AGENTS.md")
  $s = Odpal (Join-Path $Z "narzedzia\straznik-zasad.ps1") @("-Zrodlo", $Z, "-Projekt", $P, "-KatalogDomowy", $H)
  $pierwsza = (($s.Tekst -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
  Sprawdz "zera: straznik alarmuje w PIERWSZEJ linii" ($pierwsza -match "ALARM: wyzerowane pliki pamieci") $s.Tekst
  Sprawdz "zera: straznik wskazuje zdrowa kopie i polecenie" (($s.Tekst -match "ostatnia zdrowa kopia: .*kopie-dzienne\\wczoraj") -and ($s.Tekst -match "-Przywroc")) $s.Tekst
  Sprawdz "zera: straznik nie ruszyl CLAUDE.md" ((Skrot-Pliku $claude) -eq $przed)
  Sprawdz "zera: straznik nie zrobil kopii .bak zer" ((Pliki-Bak) -eq $bakPrzed)
  Sprawdz "zera: straznik nie ruszyl kopii dla opencode" ((Skrot-Pliku (Join-Path $H ".config\opencode\AGENTS.md")) -eq $ocPrzed)

  $w = Odpal (Join-Path $Z "narzedzia\wpisz-zasady.ps1") @("-Zrodlo", $Z, "-KatalogDomowy", $H)
  Sprawdz "zera: wpisz-zasady odmawia (kod 1)" (($w.Kod -eq 1) -and ($w.Tekst -match "bajty 0x00|wyzerowane")) $w.Tekst
  Sprawdz "zera: wpisz-zasady nie ruszyl pliku ani nie zrobil kopii" (((Skrot-Pliku $claude) -eq $przed) -and ((Pliki-Bak) -eq $bakPrzed))

  Remove-Item -LiteralPath (Join-Path $baza ".ostatnia-rotacja") -ErrorAction SilentlyContinue   # nowy dzien dla rotacji
  $kopiePrzed = Skrot-Katalogu $baza
  $r = Odpal $kopie @("-Rotuj", "-KatalogDomowy", $H, "-Zrodlo", $Z)
  Sprawdz "zera: rotacja odmawia (kod 2) z alarmem" (($r.Kod -eq 2) -and ($r.Tekst -match "ALARM")) $r.Tekst
  Sprawdz "zera: kopie wczoraj/przedwczoraj nietkniete" ((Skrot-Katalogu $baza) -eq $kopiePrzed)

  $wiedzaPrzed = Skrot-Katalogu $wiedza
  $c = Odpal (Join-Path $Z "narzedzia\cykl-dzienny.ps1") @("-Zrodlo", $Z, "-KatalogDomowy", $H)
  $stanC = Get-Content -LiteralPath (Join-Path $wiedza ".cykl-stan") -Raw
  $ost = Get-Content -LiteralPath (Join-Path $wiedza "cykl-ostatni.txt") -Raw -ErrorAction SilentlyContinue
  Sprawdz "zera: cykl nie rusza i mowi dlaczego" (($c.Tekst -match "cykl NIE rusza") -and ($c.Tekst -match "ALARM")) $c.Tekst
  Sprawdz "zera: cykl zapisal stan 'wyzerowane' (dozor go nie powtarza)" (($stanC -match "status: wyzerowane") -and ($ost -match "status: wyzerowane")) "$stanC / $ost"
  Sprawdz "zera: cykl nie ruszyl CLAUDE.md ani kopii" (((Skrot-Pliku $claude) -eq $przed) -and ((Skrot-Katalogu $baza) -eq $kopiePrzed))

  # okno nadzorcy: sam modul alarmow, bez okna (Alarm-Wyzerowanej-Pamieci)
  $script:NadzModuly = @{}
  $script:NadzDom = $H
  $script:NadzZrodlo = $Z
  . (Join-Path $Z "zasobnik\nadzorca\stan-alarmy.ps1")
  $a = Alarm-Wyzerowanej-Pamieci
  Sprawdz "zera: okno nadzorcy dostaje pilny alarm" (($null -ne $a) -and ($a.Waga -eq "pilne") -and ($a.Tresc -match "CLAUDE.md") -and ($a.Tresc -match "-Przywroc"))

  # ------------------------------------------------------------ przywrocenie jednym poleceniem
  $r = Odpal $kopie @("-Przywroc", "-KatalogDomowy", $H, "-Zrodlo", $Z)
  Sprawdz "przywrocenie: CLAUDE.md wraca z kopii 'wczoraj'" (($r.Kod -eq 0) -and ((Skrot-Pliku $claude) -eq (Skrot-Pliku (Join-Path $baza "wczoraj\.claude\CLAUDE.md")))) $r.Tekst
  $dowod = @(Get-ChildItem -LiteralPath $baza -Directory -Filter "przed-przywroceniem-*")
  Sprawdz "przywrocenie: wyzerowany stan zostal jako dowod" (($dowod.Count -eq 1) -and (Test-Path (Join-Path $dowod[0].FullName ".claude\CLAUDE.md")))
  Sprawdz "przywrocenie: okno nadzorcy juz bez alarmu" ($null -eq (Alarm-Wyzerowanej-Pamieci))

  # ------------------------------------------------------------ ogon zrodla.md wyzerowany (jak 02.10)
  Wyzeruj-Ogon (Join-Path $wiedza "zrodla.md") 100
  $s = Odpal (Join-Path $Z "narzedzia\straznik-zasad.ps1") @("-Zrodlo", $Z, "-Projekt", $P, "-KatalogDomowy", $H)
  Sprawdz "ogon zer w wiedza\zrodla.md: straznik alarmuje" ($s.Tekst -match "zrodla.md \(100 z ") $s.Tekst
  $r = Odpal $kopie @("-Rotuj", "-KatalogDomowy", $H, "-Zrodlo", $Z)
  Sprawdz "ogon zer w wiedza\zrodla.md: rotacja odmawia" ($r.Kod -eq 2) $r.Tekst
  $r = Odpal $kopie @("-Przywroc", "-Plik", "zrodla.md", "-KatalogDomowy", $H, "-Zrodlo", $Z)
  Sprawdz "przywrocenie jednego pliku po nazwie" (($r.Kod -eq 0) -and -not (Ma-Zero (Join-Path $wiedza "zrodla.md"))) $r.Tekst

  # ------------------------------------------------------------ wyzerowana kopia 'wczoraj' nie wypycha 'przedwczoraj'
  Remove-Item -LiteralPath (Join-Path $baza ".ostatnia-rotacja") -ErrorAction SilentlyContinue
  $r = Odpal $kopie @("-Rotuj", "-KatalogDomowy", $H, "-Zrodlo", $Z)   # teraz jest i wczoraj, i przedwczoraj
  Remove-Item -LiteralPath (Join-Path $baza ".ostatnia-rotacja") -ErrorAction SilentlyContinue
  $przedwPrzed = Skrot-Katalogu (Join-Path $baza "przedwczoraj")
  Wyzeruj (Join-Path $baza "wczoraj\.claude\CLAUDE.md")
  $r = Odpal $kopie @("-Rotuj", "-KatalogDomowy", $H, "-Zrodlo", $Z)
  Sprawdz "wyzerowana 'wczoraj': rotacja odklada ja na bok" (($r.Kod -eq 0) -and ($r.Tekst -match "uszkodzona-")) $r.Tekst
  Sprawdz "wyzerowana 'wczoraj': 'przedwczoraj' zostaje stara" ((Skrot-Katalogu (Join-Path $baza "przedwczoraj")) -eq $przedwPrzed)
  Sprawdz "wyzerowana 'wczoraj': nowa 'wczoraj' zdrowa" (-not (Ma-Zero (Join-Path $baza "wczoraj\.claude\CLAUDE.md")))
} catch {
  Sprawdz "przebieg testu" $false "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)"
} finally {
  if (-not $Zostaw) {
    # straznik odpala w tle liczenie kosztu, ktore dopisuje pliki do kopii jeszcze chwile po nas -
    # po tescie nic z kopii nie zostaje w procesach
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
