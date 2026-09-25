# Sprawdzenie P7: pomiar otwarcia sesji (-Start) + trzy widoki okna nadzorcy.
#   powershell -ExecutionPolicy Bypass -File zasobnik	est-p7.ps1 [-Kopia C:\dev\claude-worker] [-Zrzuty <kat>] [-Dom <kat domowy>] [-Przedrostek P7] [-BezOkna]
# Porownanie starych trybow koszt-pamieci.ps1 idzie tylko wtedy, gdy obok lezy
# p7-przedkoszt-pamieci.ps1 (kopia sprzed zmiany) - inaczej jest pomijane.
# Okno testowe ma wlasny zamek (nie rusza dzialajacego nadzorcy), dozor wylaczony,
# -Proba; czeka, az liczby sie policza, robi zrzuty trzech widokow i zamyka sie samo.
param(
  [string]$Kopia = "C:\dev\claude-worker",
  [string]$Zrzuty = "C:\dev\claude-worker\.megaruchacz\raporty",
  [string]$Dom = $HOME,
  [string]$Przedrostek = "P7",
  [switch]$BezOkna,
  [switch]$BezNegatywnych
)
$ErrorActionPreference = "Stop"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("test-p7-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$wyniki = @()
function Wynik($nazwa, $ok, $opis) {
  $script:wyniki += [pscustomobject]@{ Test = $nazwa; OK = [bool]$ok; Opis = $opis }
  $z = "NIE"; if ($ok) { $z = "TAK" }
  Write-Host ("[{0}] {1} - {2}" -f $z, $nazwa, $opis)
}
function Wolaj($skrypt, [string[]]$argumenty) {
  $wy = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $skrypt @argumenty 2>&1
  return [pscustomobject]@{ Kod = $LASTEXITCODE; Tekst = (($wy | ForEach-Object { "$_" }) -join "`n") }
}
$koszt = Join-Path $Kopia "narzedzia\koszt-pamieci.ps1"

# 1. pomiar na prawdziwych transkryptach
$r = Wolaj $koszt @("-Start", "-KatalogDomowy", $Dom)
$j = $null
try { $j = $r.Tekst | ConvertFrom-Json } catch { Wynik "-Start JSON" $false $_.Exception.Message }
if ($j) {
  Wynik "-Start JSON" ($r.Tekst -notmatch '[^\x00-\x7F]') "kod $($r.Kod), ASCII"
  Wynik "-Start sesje zmierzone" ((-not $j.Powod) -and ($j.Sesje.Liczba -ge 3) -and ($j.Sesje.Mediana -gt 10000)) "mediana $($j.Sesje.Mediana) z $($j.Sesje.Liczba) sesji (min $($j.Sesje.Min), max $($j.Sesje.Max)); powod '$($j.Powod)'"
  Wynik "-Start workerzy zmierzeni" (($j.Workerzy.Liczba -ge 1) -and ($j.Workerzy.Mediana -gt 5000)) "mediana $($j.Workerzy.Mediana) z $($j.Workerzy.Liczba)"
  Wynik "-Start czesc MegaRuchacza" (($j.MegaRuchaczSesja -gt 0) -and ($j.MegaRuchaczSesja -eq ($j.MegaRuchaczStart + $j.MegaRuchaczWiadomosc))) "sesja $($j.MegaRuchaczSesja) = start $($j.MegaRuchaczStart) + wiadomosc $($j.MegaRuchaczWiadomosc)"
}

if (-not $BezNegatywnych) {
  # 2. proby negatywne pomiaru: brak katalogu, pusty katalog, smieci w transkryptach
  $pusty = Join-Path $tmp "dom-pusty"; New-Item -ItemType Directory -Force -Path $pusty | Out-Null
  $jn = (Wolaj $koszt @("-Start", "-KatalogDomowy", $pusty)).Tekst | ConvertFrom-Json
  Wynik "negatywna: brak transkryptow" (($jn.Powod -like "nie ma katalogu z transkryptami*") -and ($null -eq $jn.Sesje)) $jn.Powod
  $smiec = Join-Path $tmp "dom-smieci"
  $kp = Join-Path $smiec ".claude\projects\C--x"; New-Item -ItemType Directory -Force -Path $kp | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $kp "a.jsonl"), "to nie jest json`n{""type"":""user"",""message"":{""content"":""x""}}`n")
  [System.IO.File]::WriteAllText((Join-Path $kp "b.jsonl"), "")
  $jn = (Wolaj $koszt @("-Start", "-KatalogDomowy", $smiec)).Tekst | ConvertFrom-Json
  Wynik "negatywna: transkrypty bez odpowiedzi" (($jn.Powod -like "*nie ma ani jednej sesji*") -and ($jn.Sesje.Liczba -eq 0)) $jn.Powod

  # 3. stare tryby - kod wyjscia i tekst jak przed zmiana (stara kopia w scratchpadzie)
  $stary = Join-Path $PSScriptRoot "p7-przed\koszt-pamieci.ps1"
  if (Test-Path $stary) {
    $tryby = [ordered]@{ "domyslny" = @("-Zwykly"); "zwiezle" = @("-Zwiezle"); "dane" = @("-Dane", "-Zwykly"); "rozbicie" = @("-Rozbicie", "-Zwykly")
                         "sufity" = @("-TylkoSufity", "-Zwykly"); "projekt" = @("-Zwykly", "-Projekt", $Kopia); "warstwy" = @("-Warstwy") }
    foreach ($k in $tryby.Keys) {
      $a = @("-Zrodlo", $Kopia) + $tryby[$k]
      $s = Wolaj $stary $a; $n = Wolaj $koszt $a
      $sT = ($s.Tekst.Replace($stary, "<S>") -replace '\d{2}:\d{2}(:\d{2})?', 'GG:MM')
      $nT = ($n.Tekst.Replace($koszt, "<S>") -replace '\d{2}:\d{2}(:\d{2})?', 'GG:MM')
      Wynik "stary tryb $k" (($sT -eq $nT) -and ($s.Kod -eq $n.Kod)) "kod przed $($s.Kod), po $($n.Kod); tekst $(if ($sT -eq $nT) { 'identyczny' } else { 'ROZNY' })"
    }
  }
}

if ($BezOkna) { Write-Host "Wynik: $(@($wyniki | Where-Object { $_.OK }).Count) z $($wyniki.Count) TAK"; exit 0 }

# 4. okno
$zrodloOkna = Get-Content -LiteralPath (Join-Path $Kopia "zasobnik\nadzorca.ps1") -Raw -Encoding UTF8
$stanPlik = Join-Path $Kopia "zasobnik\stan-nadzorcy.ps1"
$raportOkna = Join-Path $tmp "okno.txt"
$test = @"
`$script:TestKrok = 0
`$script:TestLog = @()
function Test-Zrzut([string]`$nazwa) {
  [System.Windows.Forms.Application]::DoEvents()
  `$b = `$script:Okno.Bounds
  `$bmp = New-Object System.Drawing.Bitmap(`$b.Width, `$b.Height)
  `$g = [System.Drawing.Graphics]::FromImage(`$bmp)
  `$g.Dispose()
  # DrawToBitmap, nie zrzut ekranu: rysuje samo okno, nawet gdy cos je zaslania
  `$script:Okno.DrawToBitmap(`$bmp, (New-Object System.Drawing.Rectangle(0, 0, `$b.Width, `$b.Height)))
  `$p = Join-Path "$Zrzuty" ("$Przedrostek-" + `$nazwa + ".png")
  `$bmp.Save(`$p); `$bmp.Dispose()
  `$script:TestLog += "zrzut: `$p"
}
# Kontrolki wychodzace poza prawa krawedz swojego rodzica = tekst uciety po cichu.
function Test-Wystajace(`$c, `$sciezka) {
  `$l = @()
  foreach (`$d in `$c.Controls) {
    if (-not `$d.Visible) { continue }
    if ((`$d.Right -gt (`$c.ClientSize.Width + 1)) -and -not (`$c -is [System.Windows.Forms.ScrollableControl] -and `$c.AutoScroll)) {
      `$l += "`$sciezka/`$(`$d.GetType().Name) '`$(("" + `$d.Text).Substring(0, [math]::Min(40, ("" + `$d.Text).Length)))' prawa=`$(`$d.Right) > `$(`$c.ClientSize.Width)"
    }
    `$l += Test-Wystajace `$d "`$sciezka/`$(`$d.GetType().Name)"
  }
  return `$l
}
`$script:TestZegar = New-Object System.Windows.Forms.Timer
`$script:TestZegar.Interval = 1000
`$script:TestZegar.Add_Tick({
  `$script:TestKrok++
  if ((`$script:TestKrok -lt 150) -and ((-not `$script:DaneCzas) -or `$script:Licze -or (`$null -eq `$script:Start))) { return }
  `$script:TestZegar.Stop()
  try {
    `$script:TestLog += "okno: " + `$script:Okno.Bounds + "; ekran: " + [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    `$script:TestLog += "gotowe po `$(`$script:TestKrok) s; start: " + (`$script:Start | ConvertTo-Json -Depth 2 -Compress).Substring(0, 200)
    `$script:TestLog += "karta startu: " + ((`$script:KartaStart.Controls | ForEach-Object { `$_.Text }) -join " | ")
    Test-Zrzut "przeglad"
    `$script:TestLog += Test-Wystajace `$script:WidokPrzeglad "przeglad"
    if (`$script:WidokPrzeglad.VerticalScroll.Visible) {
      `$script:WidokPrzeglad.AutoScrollPosition = New-Object System.Drawing.Point(0, 10000)
      `$script:WidokPrzeglad.Refresh()
      Test-Zrzut "przeglad-dol"
      `$script:WidokPrzeglad.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
    }
    `$script:BSzczegoly.PerformClick()
    [System.Windows.Forms.Application]::DoEvents()
    `$script:TestLog += "szczegoly: kart " + `$script:ListaSzczegolow.Controls.Count + ", wysokosc " + `$script:ListaSzczegolow.Height
    Test-Zrzut "szczegoly"
    `$script:TestLog += Test-Wystajace `$script:WidokSzczegoly "szczegoly"
    `$wys = `$script:ListaSzczegolow.Height; `$okno = `$script:WidokSzczegoly.ClientSize.Height; `$nr = 2
    for (`$y = `$okno - 60; `$y -lt `$wys; `$y += `$okno - 60) {
      `$script:WidokSzczegoly.AutoScrollPosition = New-Object System.Drawing.Point(0, `$y)
      `$script:WidokSzczegoly.Refresh()
      Test-Zrzut ("szczegoly-" + `$nr); `$nr++
      if (`$nr -gt 8) { break }
    }
    `$script:BWarstwy.PerformClick()
    [System.Windows.Forms.Application]::DoEvents()
    `$script:TestLog += "warstwy: " + `$script:ListaWarstw.Items.Count + " pozycji; " + `$script:LWarstwy.Text
    foreach (`$it in `$script:ListaWarstw.Items) {
      `$it.Selected = `$true
      [System.Windows.Forms.Application]::DoEvents()
    }
    `$script:ListaWarstw.Items[0].Selected = `$true
    [System.Windows.Forms.Application]::DoEvents()
    Test-Zrzut "warstwy"
    `$script:TestLog += Test-Wystajace `$script:WidokWarstwy "warstwy"
    `$script:BPrzeglad.PerformClick()
  } catch { `$script:TestLog += "WYWROTKA TESTU: " + `$_.Exception.Message + " @ " + `$_.InvocationInfo.PositionMessage }
  `$script:TestLog += "wywrotki nadzorcy: " + (`$script:NadzWywrotki -join " || ")
  [System.IO.File]::WriteAllLines("$raportOkna", [string[]]`$script:TestLog, (New-Object System.Text.UTF8Encoding(`$true)))
  `$script:Okno.Close()
  `$script:Ikona.Visible = `$false
  [System.Windows.Forms.Application]::Exit()
})
`$script:TestZegar.Start()
"@
$kod = $zrodloOkna.Replace('. (Join-Path $PSScriptRoot "stan-nadzorcy.ps1")', ". `"$stanPlik`"")
$kod = $kod.Replace('"Local\MegaRuchacz-Nadzorca"', '"Local\MegaRuchacz-Nadzorca-TEST-P7"')
$kod = $kod.Replace('$script:Zegar.Start()', '# dozor wylaczony w tescie')
$kod = $kod.Replace('if ($Pokaz) { Pokaz-Okno }', "if (`$Pokaz) { Pokaz-Okno }`r`n$test")
foreach ($kotwica in @('MegaRuchacz-Nadzorca-TEST-P7', 'dozor wylaczony w tescie', 'TestZegar', $stanPlik)) {
  if (-not $kod.Contains($kotwica)) { Wynik "okno: przygotowanie" $false "nie podmienilem kotwicy '$kotwica'"; exit 1 }
}
$kopiaOkna = Join-Path $tmp "nadzorca-test.ps1"
[System.IO.File]::WriteAllText($kopiaOkna, $kod, (New-Object System.Text.UTF8Encoding($true)))
$r = Wolaj $kopiaOkna @("-Zrodlo", $Kopia, "-KatalogDomowy", $Dom, "-Pokaz", "-Proba")
if (Test-Path $raportOkna) {
  $txt = Get-Content -LiteralPath $raportOkna -Encoding UTF8
  $txt | Write-Host
  $zle = @($txt | Where-Object { $_ -like "WYWROTKA*" })
  $wywr = @($txt | Where-Object { ($_ -like "wywrotki nadzorcy:*") -and ($_.Trim() -ne "wywrotki nadzorcy:") })
  $wyst = @($txt | Where-Object { $_ -match 'prawa=\d+ >' })
  Wynik "okno: trzy widoki bez wywrotki" (($zle.Count -eq 0) -and ($wywr.Count -eq 0)) "kod $($r.Kod)"
  Wynik "okno: nic nie wystaje poza karte" ($wyst.Count -eq 0) "$($wyst.Count) kontrolek wystaje"
} else {
  Wynik "okno" $false "okno nie zostawilo raportu (kod $($r.Kod)): $($r.Tekst)"
}
Write-Host ""
Write-Host "Wynik: $(@($wyniki | Where-Object { $_.OK }).Count) z $($wyniki.Count) TAK. Pliki robocze: $tmp"
if (@($wyniki | Where-Object { -not $_.OK }).Count -gt 0) { exit 1 }
exit 0
