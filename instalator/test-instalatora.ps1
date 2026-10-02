# Proba okna instalatora na ATRAPACH skryptow modulow - niewidoczna i bez dotykania
# prawdziwej instalacji.
#   powershell -ExecutionPolicy Bypass -File instalator\test-instalatora.ps1 [-Robocze <kat>]
#     [-Zrzuty <kat>] [-Przedrostek P59c] [-Tylko nowa,zmiana,...] [-ZrodloKlonu <adres>]
#
# Co robi:
#  - w katalogu roboczym zaklada atrapy: modul-<baza|wiedza|lore|kierownik|skille|kopia>.ps1,
#    zaleznosci.ps1 i wpisz-zasady.ps1 (wypisuja KROK/UWAGA/WYNIK jak w umowie z P59b; lore za
#    pierwszym razem celowo konczy sie bledem, skille milknie na 5 s, kopia pisze w stronie
#    kodowej OEM) oraz atrapy zlamanej umowy (brak WYNIK, ok:true z kodem 1, smieci zamiast JSON);
#  - kazdy scenariusz to osobny katalog domowy w katalogu roboczym (nigdy prawdziwy ~) i okno
#    z -PozaEkranem (-5000, 0, bez paska zadan, bez aktywacji) i -Scenariusz: scenariusz klika,
#    robi zrzuty (DrawToBitmap) i sprawdza, czy nic nie wystaje poza karte ani nie jest uciete;
#  - instaluj.bat: w repo i poza nim (ZIP z pliku), z prawdziwym ZIP-em z GitHuba (proba
#    negatywna: nie ma w nim jeszcze instalatora) i z oknem, ktore nie wstaje; przy kazdym
#    uruchomieniu obserwator okien zapisuje kazde widoczne okno nowych procesow konsoli -
#    poza oknem instalatora poza ekranem nie ma prawa byc zadnego.
# Wynik: linie [TAK]/[NIE], na koncu suma; kod 1, gdy cokolwiek NIE.
param(
  [string]$Repo = '',
  [string]$Zrzuty = '',
  [string]$Przedrostek = 'P59c',
  [string]$Robocze = '',
  [string[]]$Tylko = @(),
  [string]$ZrodloKlonu = ''
)
$ErrorActionPreference = 'Stop'
if (-not $Repo) { $Repo = Split-Path -Parent $PSScriptRoot }
if (-not $Zrzuty) { $Zrzuty = Join-Path $Repo '.megaruchacz\raporty' }
if (-not $Robocze) { $Robocze = Join-Path ([System.IO.Path]::GetTempPath()) ("test-instalatora-" + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
if (-not $ZrodloKlonu) { $ZrodloKlonu = $Repo }
$Tylko = @($Tylko | ForEach-Object { "$_" -split ',' } | Where-Object { $_ })
New-Item -ItemType Directory -Force -Path $Robocze, $Zrzuty | Out-Null
$Okno = Join-Path $Repo 'instalator\okno.ps1'
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:Wyniki = @()

function Wynik([string]$nazwa, $ok, [string]$opis) {
  $script:Wyniki += [pscustomobject]@{ Test = $nazwa; OK = [bool]$ok; Opis = $opis }
  $z = 'NIE'; if ($ok) { $z = 'TAK' }
  Write-Host ("[{0}] {1} - {2}" -f $z, $nazwa, $opis)
}
function Chce([string]$s) { return (($Tylko.Count -eq 0) -or ($Tylko -contains $s)) }
function Zapisz-Bom([string]$p, [string]$t) { [System.IO.File]::WriteAllText($p, $t.Replace("`r`n", "`n").Replace("`n", "`r`n"), $Utf8Bom) }
function Cytuj([string]$a) {
  if ($a -eq '') { return '""' }
  if ($a -notmatch '[\s"]') { return $a }
  return '"' + ($a -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

# --- atrapy --------------------------------------------------------------------
$Atrapy = Join-Path $Robocze 'atrapy'
$AtrapyZle = Join-Path $Robocze 'atrapy-zle'
$AtrapyBrak = Join-Path $Robocze 'atrapy-brak'
New-Item -ItemType Directory -Force -Path $Atrapy, $AtrapyZle, $AtrapyBrak | Out-Null

$wzorModulu = @'
# ATRAPA modul-__ID__.ps1 (test instalatora) - nic nie instaluje, tylko mowi jak prawdziwy.
param([string]$Akcja = '', [string]$KatalogDomowy = '', [string]$Zrodlo = '', [switch]$Proba, [switch]$UsunDane)
$id = '__ID__'
[System.IO.File]::AppendAllText((Join-Path $PSScriptRoot 'wywolania.log'), ("{0}|modul-{1}|{2}|UsunDane={3}|Proba={4}|Dom={5}`r`n" -f (Get-Date -Format 'HH:mm:ss.fff'), $id, $Akcja, [bool]$UsunDane, [bool]$Proba, $KatalogDomowy), (New-Object System.Text.UTF8Encoding($false)))
function K([string]$t) { Write-Output "KROK: $t"; Start-Sleep -Milliseconds 300 }
function W([bool]$ok, [string]$kom, $kroki) { Write-Output ('WYNIK: ' + (ConvertTo-Json -InputObject ([ordered]@{ ok = $ok; komunikat = $kom; kroki = [string[]]@($kroki) }) -Compress)); if ($ok) { exit 0 } else { exit 1 } }
$kroki = @()
if ($Akcja -eq 'Instaluj') {
  if (($id -eq 'lore') -and -not (Test-Path -LiteralPath (Join-Path $KatalogDomowy 'atrapa-lore-raz.txt'))) {
    [System.IO.File]::WriteAllText((Join-Path $KatalogDomowy 'atrapa-lore-raz.txt'), 'bylo')
    K 'Instaluję bibliotekę do wyszukiwania'; K 'Pobieram model do wyszukiwania rozmów (496 MB)'
    Write-Output 'blad: huggingface.co: timeout'
    W $false 'Nie udało się pobrać modelu do wyszukiwania rozmów: serwer huggingface.co nie odpowiada. Sprawdź internet i kliknij „Spróbuj ponownie”.' @('Instaluję bibliotekę do wyszukiwania')
  }
  $kroki = @('Sprawdzam, co już jest', 'Kopiuję pliki: __NAZWA__', 'Zapisuję ustawienia')
  K $kroki[0]
  if (($id -eq 'wiedza') -and (Test-Path -LiteralPath (Join-Path $KatalogDomowy 'atrapa-wolno.txt'))) { Start-Sleep -Seconds 8 }
  if ($id -eq 'kopia') {
    # Linia w stronie kodowej OEM (852), bez przestawiania wspolnej konsoli - okno ma ja odczytac.
    $s = [Console]::OpenStandardOutput(); $b = [System.Text.Encoding]::GetEncoding(852).GetBytes("KROK: Zażółć gęślą jaźń (strona kodowa 852)`r`n"); $s.Write($b, 0, $b.Length); $s.Flush()
    Write-Host 'KROK: Zakładam zadanie codziennej kopii (Write-Host)'
  }
  K $kroki[1]; K $kroki[2]
  if ($id -eq 'kierownik') { Write-Output 'UWAGA: Codex nie jest zainstalowany - tryb kierownika ustawiłem tylko dla Claude Code.' }
  if (($id -eq 'skille') -and (Test-Path -LiteralPath (Join-Path $KatalogDomowy 'atrapa-cisza.txt'))) { Start-Sleep -Seconds 5 }
  W $true 'Zainstalowane.' $kroki
}
if ($Akcja -eq 'Usun') {
  $kroki = @('Zatrzymuję zadania w tle', 'Usuwam pliki: __NAZWA__')
  if ($UsunDane) { $kroki += 'Usuwam dane' }
  foreach ($k in $kroki) { K $k }
  W $true 'Usunięte.' $kroki
}
K 'Sprawdzam stan'
W $true 'Jest.' @('Sprawdzam stan')
'@

$zaleznosci = @'
# ATRAPA zaleznosci.ps1 (test instalatora).
param([string]$Akcja = '', [string[]]$Potrzebne = @(), [switch]$Proba)
[System.IO.File]::AppendAllText((Join-Path $PSScriptRoot 'wywolania.log'), ("{0}|zaleznosci|{1}|Potrzebne={2}|Proba={3}`r`n" -f (Get-Date -Format 'HH:mm:ss.fff'), $Akcja, ($Potrzebne -join '#'), [bool]$Proba), (New-Object System.Text.UTF8Encoding($false)))
$lista = @($Potrzebne | ForEach-Object { "$_" -split ',' } | Where-Object { $_ })
$jest = @('git', 'node')
$brak = @($lista | Where-Object { $jest -notcontains $_ })
$kroki = @()
foreach ($p in $lista) {
  if ($Akcja -eq 'Sprawdz') { if ($jest -contains $p) { $t = "$p - jest" } else { $t = "$p - brak, doinstaluję" } }
  else { if ($jest -contains $p) { $t = "$p - już jest" } else { $t = "Instaluję $p" } }
  $kroki += $t; Write-Output "KROK: $t"; Start-Sleep -Milliseconds 250
}
# Jak prawdziwy zaleznosci.ps1 (P59b): Sprawdz z brakami = ok:false i kod 1, komunikat techniczny.
$kom = 'wszystko jest: ' + ($lista -join ', ')
$ok = $true
if ($brak.Count) { if ($Akcja -eq 'Sprawdz') { $ok = $false; $kom = "brakuje: $($brak -join ', ') - zainstaluj: zaleznosci.ps1 -Akcja Instaluj -Potrzebne $($brak -join ',')" } else { $kom = "Doinstalowane: $($brak -join ', ')" } }
if ($Akcja -ne 'Sprawdz') { $brak = @() }
Write-Output ('WYNIK: ' + (ConvertTo-Json -InputObject ([ordered]@{ ok = $ok; komunikat = $kom; kroki = [string[]]$kroki; brakuje = [string[]]$brak }) -Compress))
if ($ok) { exit 0 } else { exit 1 }
'@

$wpisz = @'
# ATRAPA wpisz-zasady.ps1 (test instalatora) - wyjscie jak prawdziwy (Write-Host, bez umowy KROK/WYNIK).
param([string]$Zrodlo = '', [string]$KatalogDomowy = '', [switch]$Usun, [switch]$Proba)
[System.IO.File]::AppendAllText((Join-Path $PSScriptRoot 'wywolania.log'), ("{0}|wpisz-zasady|Proba={1}|Dom={2}`r`n" -f (Get-Date -Format 'HH:mm:ss.fff'), [bool]$Proba, $KatalogDomowy), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "OK  Claude Code - blok dopisany (60 linii): $KatalogDomowy\.claude\CLAUDE.md"
Write-Host 'Gotowe - zasady wpisane. Zamknij i otworz narzedzie na nowo.'
exit 0
'@

$bazaZla = @'
# ATRAPA modul-baza.ps1 ZLAMANA UMOWA (test instalatora): kolejne wywolania - brak WYNIK, ok:true z kodem 1, smieci zamiast JSON, potem dobrze.
param([string]$Akcja = '', [string]$KatalogDomowy = '', [string]$Zrodlo = '', [switch]$Proba, [switch]$UsunDane)
$l = Join-Path $KatalogDomowy 'atrapa-baza-licznik.txt'
$n = 0; if (Test-Path -LiteralPath $l) { $n = [int](Get-Content -LiteralPath $l) }
$n++; Set-Content -LiteralPath $l -Value $n
Write-Output 'KROK: Zakładam aplikację przy zegarze'
Start-Sleep -Milliseconds 300
switch ($n) {
  1 { Write-Output 'koniec bez wyniku'; exit 0 }
  2 { Write-Output 'WYNIK: {"ok":true,"komunikat":"Zainstalowane.","kroki":[]}'; exit 1 }
  3 { Write-Output 'WYNIK: {to nie jest json'; exit 0 }
}
Write-Output 'WYNIK: {"ok":true,"komunikat":"Zainstalowane.","kroki":["Zakładam aplikację przy zegarze"]}'
exit 0
'@

$nazwyAtrap = @{ baza = 'aplikacja przy zegarze'; wiedza = 'Wiedza o Tobie'; lore = 'Pamięć rozmów'; kierownik = 'Tryb kierownika'; skille = 'Polecane skille'; kopia = 'Kopia zapasowa' }
foreach ($kat in @($Atrapy, $AtrapyZle, $AtrapyBrak)) {
  foreach ($id in $nazwyAtrap.Keys) { Zapisz-Bom (Join-Path $kat "modul-$id.ps1") ($wzorModulu.Replace('__ID__', $id).Replace('__NAZWA__', $nazwyAtrap[$id])) }
  Zapisz-Bom (Join-Path $kat 'zaleznosci.ps1') $zaleznosci
  Zapisz-Bom (Join-Path $kat 'wpisz-zasady.ps1') $wpisz
}
Zapisz-Bom (Join-Path $AtrapyZle 'modul-baza.ps1') $bazaZla
Remove-Item -LiteralPath (Join-Path $AtrapyBrak 'modul-skille.ps1') -Force

# --- scenariusze -----------------------------------------------------------------
# Poczatek kazdego scenariusza - wczytywany kropka w okno.ps1 po zbudowaniu okna.
$wstep = @'
$script:TestRaport = '__RAPORT__'
$script:TestZrzuty = '__ZRZUTY__'
$script:TestPrzedrostek = '__PRZEDROSTEK__'
$script:TestIndeks = 0
$script:TestCzekamOd = $null
$script:TestSkonczony = $false
function Test-Pisz([string]$t) { [System.IO.File]::AppendAllText($script:TestRaport, ($t + "`r`n"), (New-Object System.Text.UTF8Encoding($false))) }
function Test-Zrzut([string]$nazwa) {
  [System.Windows.Forms.Application]::DoEvents()
  $script:Okno.Refresh()
  $b = $script:Okno.Bounds
  $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
  try {
    $script:Okno.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $b.Width, $b.Height)))
    $p = Join-Path $script:TestZrzuty ($script:TestPrzedrostek + '-' + $nazwa + '.png')
    $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
    Test-Pisz "ZRZUT $p"
  } finally { $bmp.Dispose() }
  if ($script:Tresc.VerticalScroll.Visible -and -not $script:Nakladka.Visible) {
    $script:Tresc.AutoScrollPosition = New-Object System.Drawing.Point(0, 100000)
    $script:Tresc.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
    try {
      $script:Okno.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $b.Width, $b.Height)))
      $p = Join-Path $script:TestZrzuty ($script:TestPrzedrostek + '-' + $nazwa + '-dol.png')
      $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
      Test-Pisz "ZRZUT $p"
    } finally { $bmp.Dispose() }
    $script:Tresc.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
  }
}
# Kontrolka wychodzaca poza prawa krawedz rodzica (nieprzewijanego) = tekst uciety po cichu.
function Test-Wystajace($c, [string]$sciezka) {
  $l = @()
  foreach ($d in $c.Controls) {
    if (-not $d.Visible) { continue }
    $przew = ($c -is [System.Windows.Forms.ScrollableControl]) -and $c.AutoScroll
    if ((-not $przew) -and ($d.Right -gt ($c.ClientSize.Width + 1))) {
      $t = ('' + $d.Text); if ($t.Length -gt 50) { $t = $t.Substring(0, 50) }
      $l += "$sciezka/$($d.GetType().Name) '$t' prawa=$($d.Right) > $($c.ClientSize.Width)"
    }
    $l += @(Test-Wystajace $d "$sciezka/$($d.GetType().Name)")
  }
  return $l
}
# Etykieta o stalym rozmiarze, w ktora tekst sie nie miesci.
function Test-Uciete($c, [string]$sciezka) {
  $l = @()
  foreach ($d in $c.Controls) {
    if (-not $d.Visible) { continue }
    if (($d -is [System.Windows.Forms.Label]) -and (-not $d.AutoSize) -and $d.Text) {
      $r = [System.Windows.Forms.TextRenderer]::MeasureText($d.Text, $d.Font, (New-Object System.Drawing.Size($d.Width, 10000)), [System.Windows.Forms.TextFormatFlags]::WordBreak)
      if (($r.Width -gt ($d.Width + 1)) -or ($r.Height -gt ($d.Height + 1))) { $l += "$sciezka/Label '$($d.Text)' potrzebuje $($r.Width)x$($r.Height), ma $($d.Width)x$($d.Height)" }
    }
    $l += @(Test-Uciete $d "$sciezka/$($d.GetType().Name)")
  }
  return $l
}
function Test-Uklad([string]$nazwa) {
  $obszar = $script:Tresc
  if ($script:Nakladka.Visible) { $obszar = $script:Nakladka }
  foreach ($c in @($obszar, $script:Pasek, $script:Naglowek)) {
    foreach ($w in @(Test-Wystajace $c $c.GetType().Name)) { Test-Pisz "WYSTAJE [$nazwa] $w" }
    foreach ($w in @(Test-Uciete $c $c.GetType().Name)) { Test-Pisz "UCIETE [$nazwa] $w" }
  }
}
function Test-Koniec {
  if ($script:TestSkonczony) { return }
  $script:TestSkonczony = $true
  $script:TestZegar.Stop()
  Test-Pisz ("WYWROTKI: " + (@($script:Wywrotki) -join ' || '))
  Test-Pisz 'KONIEC'
  $script:ZamykamMimoPlanu = $true
  if ($script:Okno -and -not $script:Okno.IsDisposed) { $script:Okno.Close() }
}
function Tak([bool]$w, [string]$opis) { if ($w) { return "TAK $opis" } return "NIE $opis" }
Test-Pisz "TRYB $($script:Tryb)"
$script:TestZegar = New-Object System.Windows.Forms.Timer
$script:TestZegar.Interval = 250
$script:TestWTrakcie = $false
$script:TestZegar.Add_Tick({
  # DoEvents (zrzut, klikniecie) potrafi wpuscic nastepne tykniecie, zanim to sie skonczy -
  # bez tej blokady jeden krok scenariusza wykonalby sie kilka razy.
  if ($script:TestSkonczony -or $script:TestWTrakcie) { return }
  $script:TestWTrakcie = $true
  $k = $null
  try {
    if ($script:TestIndeks -ge $script:TestKroki.Count) { Test-Koniec; return }
    $k = $script:TestKroki[$script:TestIndeks]
    if (-not $script:TestCzekamOd) { $script:TestCzekamOd = Get-Date }
    if ($k.Czekaj -and -not (& $k.Czekaj)) {
      $lim = 90; if ($k.Limit) { $lim = $k.Limit }
      if (((Get-Date) - $script:TestCzekamOd).TotalSeconds -gt $lim) { Test-Pisz "TIMEOUT $($k.N)"; Test-Zrzut ("BLAD-TESTU-" + $script:TestIndeks); Test-Koniec }
      return
    }
    if ($k.Zrob) { & $k.Zrob; [System.Windows.Forms.Application]::DoEvents() }
    if ($k.Zrzut) { Test-Zrzut $k.Zrzut; Test-Uklad $k.Zrzut }
    if ($k.Sprawdz) { Test-Pisz ("SPRAWDZ $($k.N): " + (& $k.Sprawdz)) }
    Test-Pisz "OK $($k.N)"
    $script:TestIndeks++
    $script:TestCzekamOd = $null
  } catch {
    $n = ''; if ($k) { $n = $k.N }
    Test-Pisz "WYJATEK $($n): $($_.Exception.Message) @ linia $($_.InvocationInfo.ScriptLineNumber)"
    Test-Koniec
  } finally { $script:TestWTrakcie = $false }
})
$script:TestZegar.Start()
'@

function Nowy-Dom([string]$nazwa) {
  $d = Join-Path $Robocze "dom-$nazwa"
  New-Item -ItemType Directory -Force -Path (Join-Path $d '.claude') | Out-Null
  return $d
}

function Zapisz-Scenariusz([string]$nazwa, [string]$kroki) {
  $raport = Join-Path $Robocze "raport-$nazwa.txt"
  if (Test-Path -LiteralPath $raport) { Remove-Item -LiteralPath $raport -Force }
  $plik = Join-Path $Robocze "scenariusz-$nazwa.ps1"
  Zapisz-Bom $plik ($wstep.Replace('__RAPORT__', $raport).Replace('__ZRZUTY__', $Zrzuty).Replace('__PRZEDROSTEK__', $Przedrostek) + "`r`n" + $kroki)
  return [pscustomobject]@{ Plik = $plik; Raport = $raport }
}

function Uruchom-Ps([string]$skrypt, [string[]]$argumenty, [int]$limit = 240) {
  $linia = (@(@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $skrypt) + $argumenty) | ForEach-Object { Cytuj "$_" }) -join ' '
  $bl = [System.IO.Path]::GetTempFileName(); $wy = [System.IO.Path]::GetTempFileName()
  $p = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $linia -NoNewWindow -PassThru -RedirectStandardOutput $wy -RedirectStandardError $bl
  $null = $p.Handle
  $kod = 'LIMIT'
  if ($p.WaitForExit($limit * 1000)) { $kod = $p.ExitCode } else { & taskkill.exe /PID $p.Id /T /F | Out-Null }
  $r = [pscustomobject]@{ Kod = $kod; Bledy = ("$(Get-Content -LiteralPath $bl -Raw -Encoding UTF8)").Trim(); Wyjscie = ("$(Get-Content -LiteralPath $wy -Raw -Encoding UTF8)").Trim() }
  Remove-Item -LiteralPath $bl, $wy -Force -ErrorAction SilentlyContinue
  return $r
}

function Ocen-Raport([string]$nazwa, $sc, $r) {
  if (-not (Test-Path -LiteralPath $sc.Raport)) { Wynik "$nazwa" $false "okno nie zostawilo raportu (kod $($r.Kod)): $($r.Bledy)"; return @() }
  $t = @(Get-Content -LiteralPath $sc.Raport -Encoding UTF8)
  $zle = @($t | Where-Object { $_ -match '^(TIMEOUT|WYJATEK|WYSTAJE|UCIETE)' })
  $wyw = @($t | Where-Object { ($_ -like 'WYWROTKI:*') -and ($_.Trim() -ne 'WYWROTKI:') })
  $spr = @($t | Where-Object { $_ -match '^SPRAWDZ ' })
  $nie = @($spr | Where-Object { $_ -match ': NIE ' })
  $koniec = @($t | Where-Object { $_ -eq 'KONIEC' }).Count -gt 0
  Wynik "$nazwa - przebieg" ($koniec -and $zle.Count -eq 0 -and $wyw.Count -eq 0 -and ($r.Kod -eq 0)) ("kod $($r.Kod), zrzutow $(@($t | Where-Object { $_ -like 'ZRZUT*' }).Count)" + $(if ($zle.Count) { '; ' + ($zle -join ' | ') } else { '' }) + $(if ($wyw.Count) { '; ' + ($wyw -join ' | ') } else { '' }) + $(if ($r.Bledy) { '; stderr: ' + $r.Bledy } else { '' }))
  foreach ($s in $spr) { Wynik "$nazwa - $(($s -replace '^SPRAWDZ ', '') -replace ': (TAK|NIE) .*$', '')" ($s -match ': TAK ') ($s -replace '^.*?: (TAK|NIE) ', '') }
  return $t
}

function Wywolania([string]$dom) {
  $p = Join-Path $Atrapy 'wywolania.log'
  $w = @()
  foreach ($kat in @($Atrapy, $AtrapyZle, $AtrapyBrak)) {
    $p = Join-Path $kat 'wywolania.log'
    if (Test-Path -LiteralPath $p) { $w += @(Get-Content -LiteralPath $p -Encoding UTF8) }
  }
  return @($w | Where-Object { ($_ -like "*Dom=$dom") -or (($_ -like '*|zaleznosci|*') -and ($script:OstatniDom -eq $dom)) })
}

function Czytaj-Rejestr([string]$dom) {
  $p = Join-Path $dom '.claude\mr\instalacja.json'
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  return ([System.IO.File]::ReadAllText($p, $Utf8) | ConvertFrom-Json)
}

function Argumenty-Okna([string]$dom, [string]$scen, [string]$atrapy, [switch]$Proba) {
  $a = @('-KatalogDomowy', $dom, '-KatalogSkryptow', $atrapy, '-PozaEkranem', '-Scenariusz', $scen)
  if ($Proba) { $a += '-Proba' }
  return ,$a
}

# Zaleznosci-atrapa nie zna katalogu domowego - rozdzielamy wywolania po czasie: czyscimy dziennik przed scenariuszem.
function Wyczysc-Wywolania { foreach ($kat in @($Atrapy, $AtrapyZle, $AtrapyBrak)) { Remove-Item -LiteralPath (Join-Path $kat 'wywolania.log') -Force -ErrorAction SilentlyContinue } }
function Wszystkie-Wywolania { $w = @(); foreach ($kat in @($Atrapy, $AtrapyZle, $AtrapyBrak)) { $p = Join-Path $kat 'wywolania.log'; if (Test-Path -LiteralPath $p) { $w += @(Get-Content -LiteralPath $p -Encoding UTF8) } }; return ,$w }
function Kolejnosc($wywolania) { return ((@($wywolania) | ForEach-Object { $c = $_ -split '\|'; ($c[1] + ':' + $c[2]) }) -join ' > ') }

# --- A. nowa instalacja ----------------------------------------------------------
if (Chce 'nowa') {
  $dom = Nowy-Dom 'nowa'
  [System.IO.File]::WriteAllText((Join-Path $dom 'atrapa-cisza.txt'), '1')
  $kopie = Join-Path $Robocze 'kopie-nowa'
  $sc = Zapisz-Scenariusz 'nowa' (@'
$script:SekundyCiszy = 2
$script:TestKroki = @(
  @{ N = 'powitanie'; Czekaj = { $script:Ekran -eq 'powitanie' }; Zrzut = '1-powitanie'; Sprawdz = { Tak ($script:Tryb -eq 'nowy') "tryb $($script:Tryb)" } },
  @{ N = 'dalej do wyboru'; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'wybor - stan z makiety'; Czekaj = { $script:Ekran -eq 'wybor' }; Zrzut = '2-wybor'; Sprawdz = { $m = $script:Wybor.Moduly; Tak ($m.wiedza -and $m.lore -and $m.kierownik -and $m.skille -and -not $m.kopia -and $script:Wybor.Zestaw -eq 'wlasny' -and -not $script:PanelKopii.Visible) "cztery zaznaczone, kopia nie, zestaw $($script:Wybor.Zestaw)" } },
  @{ N = 'zestaw Wszystko'; Zrob = { $script:BWszystko.PerformClick() }; Sprawdz = { $m = $script:Wybor.Moduly; Tak ($m.kopia -and $script:CheckboxyModulow.kopia.Checked -and $script:PanelKopii.Visible -and $script:Wybor.Zestaw -eq 'wszystko') "wszystko zaznaczone, panel kopii widoczny" } },
  @{ N = 'zestaw Wlasny przywraca'; Zrob = { $script:BWlasny.PerformClick() }; Sprawdz = { $m = $script:Wybor.Moduly; Tak ((-not $m.kopia) -and $m.wiedza -and (-not $script:CheckboxyModulow.kopia.Checked)) "wrocil wlasny wybor (kopia odznaczona)" } },
  @{ N = 'zaznacz kopie'; Zrob = { $script:CheckboxyModulow.kopia.Checked = $true } },
  @{ N = 'kopia - panel'; Czekaj = { $script:PanelKopii.Visible }; Zrzut = '2b-wybor-kopia'; Sprawdz = { Tak ($script:Wybor.Zestaw -eq 'wlasny' -and $script:BDalej.Enabled) "panel kopii, Dalej wlaczone, cel $($script:Wybor.KopiaCel)" } },
  @{ N = 'proba negatywna: nowa kopia bez ustawien biura'; Sprawdz = { Tak (($script:Wybor.KopiaWykluczenia.Count -eq 0) -and ($script:KopiaNaStart.Skad -ne 'dotychczasowe') -and ($script:Wybor.KopiaCel -like '*MegaRuchacz-kopia') -and $script:LBrakWykluczen.Visible) "skad $($script:KopiaNaStart.Skad), wykluczen $($script:Wybor.KopiaWykluczenia.Count)" } },
  @{ N = 'proba negatywna: kopia w kopiowanym folderze'; Zrob = { $script:PoleCelu.Text = (Join-Path $script:Dom '.claude\kopie') } },
  @{ N = 'kopia w srodku zrodla blokuje'; Czekaj = { -not $script:BDalej.Enabled }; Zrzut = '2c-kopia-zly-folder'; Sprawdz = { Tak (($script:LCelInfo.Text -like '*kopiowałaby samą siebie*') -and ($script:LStopka.Text -like '*kopii*')) "komunikat: $($script:LCelInfo.Text)" } },
  @{ N = 'dobry folder kopii'; Zrob = { $script:PoleCelu.Text = '__KOPIE__' }; Sprawdz = { Tak $script:BDalej.Enabled "Dalej znow wlaczone" } },
  @{ N = 'do podsumowania'; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'podsumowanie'; Czekaj = { ($script:Ekran -eq 'podsumowanie') -and $script:Sprawdzenie -and ($script:Sprawdzenie.Zadanie.Stan -ne 'trwa') }; Zrzut = '3-podsumowanie'; Sprawdz = { Tak (($script:LProgramy.Text -like 'Brakuje: uv, Python 3.12 - doinstaluję*') -and $script:BDalej.Enabled -and ($script:BDalej.Text -eq 'Zainstaluj')) "programy: $($script:LProgramy.Text)" } },
  @{ N = 'zainstaluj'; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'postep w trakcie'; Czekaj = { ($script:Ekran -eq 'postep') -and (@($script:Plan | Where-Object { ($_.Stan -eq 'trwa') -and ($_.Kroki.Count -gt 0) -and ($_.Id -like 'baza*') }).Count -gt 0) }; Zrzut = '4-postep' },
  @{ N = 'blad lore'; Czekaj = { $script:PlanStan -eq 'blad' }; Limit = 60; Zrzut = '4b-blad'; Sprawdz = { $z = $script:Plan[$script:PlanIndeks]; Tak (($z.Id -eq 'lore-Instaluj') -and ($script:LBleduTresc.Text -like '*huggingface*') -and $script:KartaBledu.Visible -and ($script:BAnuluj.Text -eq 'Zamknij')) "krok $($z.Id): $($script:LBleduTresc.Text)" } },
  @{ N = 'pokaz szczegoly'; Zrob = { $script:BSzczegoly.PerformClick() } },
  @{ N = 'szczegoly bledu'; Czekaj = { $script:PoleSzczegolow.Visible }; Zrzut = '4c-blad-szczegoly'; Sprawdz = { Tak (($script:PoleSzczegolow.Text -like '*huggingface.co: timeout*') -and ($script:PoleSzczegolow.Text -like '*Kod wyjścia: 1*')) "szczegoly maja wyjscie skryptu i kod" } },
  @{ N = 'sprobuj ponownie'; Zrob = { $script:BPonow.PerformClick() } },
  @{ N = 'cisza skille'; Czekaj = { $z = @($script:Plan | Where-Object { $_.Id -eq 'skille-Instaluj' })[0]; ($z.Stan -eq 'trwa') -and $z.OstatniZnak -and (((Get-Date) - $z.OstatniZnak).TotalSeconds -gt 3) }; Limit = 60; Zrzut = '4d-postep-cisza'; Sprawdz = { Tak ($script:WierszeZadan['skille-Instaluj'].Szczegol.Text -like '*nic nowego*') "uwaga o ciszy: $($script:WierszeZadan['skille-Instaluj'].Szczegol.Text)" } },
  @{ N = 'gotowe'; Czekaj = { $script:Ekran -eq 'gotowe' }; Limit = 90; Zrzut = '5-gotowe'; Sprawdz = {
      $kop = @($script:Plan | Where-Object { $_.Id -eq 'kopia-Instaluj' })[0]
      $ma = @($kop.Kroki | Where-Object { $_ -eq 'Zażółć gęślą jaźń (strona kodowa 852)' }).Count -gt 0
      $wh = @($kop.Kroki | Where-Object { $_ -like '*Write-Host*' }).Count -gt 0
      Tak ($ma -and $wh) "linia OEM 852 i Write-Host odczytane: $($kop.Kroki -join ' / ')" } },
  @{ N = 'uwagi na koncu'; Sprawdz = { $u = @($script:Plan | ForEach-Object { $_.Uwagi }); Tak (($u.Count -eq 1) -and ($u[0] -like 'Codex nie jest*')) "uwagi: $($u -join ' / ')" } }
)
'@).Replace('__KOPIE__', $kopie)
  Wyczysc-Wywolania
  $r = Uruchom-Ps $Okno (Argumenty-Okna $dom $sc.Plik $Atrapy) 300
  [void](Ocen-Raport 'nowa instalacja' $sc $r)
  $w = Wszystkie-Wywolania
  $kol = Kolejnosc $w
  $ocz = 'zaleznosci:Sprawdz > modul-baza:Instaluj > zaleznosci:Instaluj > modul-lore:Instaluj > modul-lore:Instaluj > modul-wiedza:Instaluj > modul-kierownik:Instaluj > modul-skille:Instaluj > modul-kopia:Instaluj > wpisz-zasady:Proba=False'
  Wynik 'nowa instalacja - kolejnosc skryptow' ($kol -eq $ocz) $kol
  $pot = @($w | Where-Object { $_ -like '*|zaleznosci|Instaluj|*' })
  Wynik 'nowa instalacja - lista programow jednym napisem' (($pot.Count -eq 1) -and ($pot[0] -like '*Potrzebne=git,node,uv,python|*')) "$($pot -join ' ')"
  $rej = Czytaj-Rejestr $dom
  $ok = $rej -and $rej.moduly.wiedza -and $rej.moduly.lore -and $rej.moduly.kierownik -and $rej.moduly.skille -and $rej.moduly.kopia -and ($rej.kopia.cel -eq $kopie) -and (@($rej.kopia.zrodla).Count -ge 1) -and ($null -ne $rej.narzedzia) -and ($null -ne $rej.kopia.PSObject.Properties['wykluczenia']) -and (@($rej.kopia.wykluczenia).Count -eq 0)
  Wynik 'nowa instalacja - rejestr' $ok ($(if ($rej) { $rej | ConvertTo-Json -Compress -Depth 5 } else { 'brak pliku' }))
}

# --- B. tryb zmiany --------------------------------------------------------------
if (Chce 'zmiana') {
  $dom = Nowy-Dom 'zmiana'
  New-Item -ItemType Directory -Force -Path (Join-Path $dom '.claude\mr') | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $dom '.claude\mr\instalacja.json'), '{"wersja":1,"moduly":{"wiedza":true,"lore":true,"kierownik":true,"skille":true,"kopia":false},"kopia":null,"narzedzia":{"claude":true,"codex":false,"opencode":false},"data":"2026-10-01 10:00:00"}', $Utf8)
  $kopie = Join-Path $Robocze 'kopie-zmiana'
  $sc = Zapisz-Scenariusz 'zmiana' (@'
$script:TestKroki = @(
  @{ N = 'wybor z obecnym stanem'; Czekaj = { $script:Ekran -eq 'wybor' }; Zrzut = '6-zmiana-wybor'; Sprawdz = { Tak (($script:Tryb -eq 'zmiana') -and (-not $script:BDalej.Enabled) -and ($script:LStopka.Text -eq 'Nic nie zmieniłeś.') -and ($script:BDalej.Text -eq 'Zastosuj zmiany') -and ($script:TagiModulow.lore.Text -eq 'jest') -and -not $script:Wybor.Moduly.kopia) "przycisk $($script:BDalej.Text) wylaczony: $($script:LStopka.Text)" } },
  @{ N = 'odznacz lore'; Zrob = { $script:CheckboxyModulow.lore.Checked = $false } },
  @{ N = 'pytanie o usuniecie'; Czekaj = { $script:Nakladka.Visible }; Zrzut = '7-zmiana-pytanie'; Sprawdz = { $t = $script:Nakladka.Controls[0].Controls[0].Text; Tak ((-not $script:PolePytania.Checked) -and (-not $script:BDalej.Enabled) -and ($t -eq ('Usunąć ' + [char]0x201E + 'Pamięć rozmów (Lore)' + [char]0x201D + '?'))) "tytul '$t', pole 'usun dane' domyslnie odznaczone, przyciski okna zablokowane" } },
  @{ N = 'usun z danymi'; Zrob = { $script:PolePytania.Checked = $true; $script:PrzyciskiPytania[0].PerformClick() }; Sprawdz = { Tak ((-not $script:Nakladka.Visible) -and ($script:TagiModulow.lore.Text -eq 'usunę z danymi') -and $script:Wybor.UsunDane.lore -and $script:BDalej.Enabled) "znaczek: $($script:TagiModulow.lore.Text)" } },
  @{ N = 'odznacz skille'; Zrob = { $script:CheckboxyModulow.skille.Checked = $false } },
  @{ N = 'zostaw skille'; Czekaj = { $script:Nakladka.Visible }; Zrob = { $script:PrzyciskiPytania[1].PerformClick() }; Sprawdz = { Tak ($script:CheckboxyModulow.skille.Checked -and $script:Wybor.Moduly.skille -and ($script:TagiModulow.skille.Text -eq 'jest')) "Zostaw przywrocil zaznaczenie" } },
  @{ N = 'dodaj kopie'; Zrob = { $script:CheckboxyModulow.kopia.Checked = $true; $script:PoleCelu.Text = '__KOPIE__' } },
  @{ N = 'wybor po zmianach'; Czekaj = { $script:PanelKopii.Visible }; Zrzut = '8-zmiana-wybor-po'; Sprawdz = { Tak (($script:TagiModulow.kopia.Text -eq 'dodam') -and $script:BDalej.Enabled) "kopia: $($script:TagiModulow.kopia.Text)" } },
  @{ N = 'zastosuj zmiany'; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'podsumowanie zmian'; Czekaj = { ($script:Ekran -eq 'podsumowanie') -and $script:Sprawdzenie -and ($script:Sprawdzenie.Zadanie.Stan -ne 'trwa') }; Zrzut = '9-zmiana-podsumowanie'; Sprawdz = { $ids = @($script:PlanDoWykonania | ForEach-Object { $_.Id }) -join ','; Tak ($ids -eq 'zapamietaj,lore-Usun,zaleznosci-Instaluj,kopia-Instaluj,zasady') "plan: $ids" } },
  @{ N = 'tak, zastosuj'; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'zmiany w toku'; Czekaj = { ($script:Ekran -eq 'postep') -and (@($script:Plan | Where-Object { ($_.Stan -eq 'trwa') -and ($_.Kroki.Count -gt 0) }).Count -gt 0) }; Zrzut = '9b-zmiana-postep' },
  @{ N = 'gotowe po zmianach'; Czekaj = { $script:Ekran -eq 'gotowe' }; Limit = 90; Zrzut = '10-zmiana-gotowe' }
)
'@).Replace('__KOPIE__', $kopie)
  Wyczysc-Wywolania
  $r = Uruchom-Ps $Okno (Argumenty-Okna $dom $sc.Plik $Atrapy) 240
  [void](Ocen-Raport 'tryb zmiany' $sc $r)
  $w = Wszystkie-Wywolania
  $kol = Kolejnosc $w
  $ocz = 'zaleznosci:Sprawdz > modul-lore:Usun > zaleznosci:Instaluj > modul-kopia:Instaluj > wpisz-zasady:Proba=False'
  Wynik 'tryb zmiany - kolejnosc skryptow' ($kol -eq $ocz) $kol
  $us = @($w | Where-Object { $_ -like '*|modul-lore|Usun|*' })
  Wynik 'tryb zmiany - usuniecie z danymi' (($us.Count -eq 1) -and ($us[0] -like '*UsunDane=True*')) "$($us -join ' ')"
  $rej = Czytaj-Rejestr $dom
  $ok = $rej -and $rej.moduly.wiedza -and (-not $rej.moduly.lore) -and $rej.moduly.kierownik -and $rej.moduly.skille -and $rej.moduly.kopia -and ($rej.kopia.cel -eq $kopie)
  Wynik 'tryb zmiany - rejestr' $ok ($(if ($rej) { $rej | ConvertTo-Json -Compress -Depth 5 } else { 'brak pliku' }))
}

# --- C. zmiana bez rejestru (instalacja sprzed rejestru) -----------------------------
# Komputer z kopia zapasowa sprzed rejestru (jak biuro): ustawienia kopii maja przyjsc z
# narzedzia\kopia-zapasowa-domyslne.json (cel, zrodla, 7 wykluczen) i trafic do rejestru bez zmian (P59d).
if (Chce 'bezrejestru') {
  $dom = Nowy-Dom 'bezrejestru'
  New-Item -ItemType Directory -Force -Path (Join-Path $dom '.claude\mr') | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $dom '.claude\.megaruchacz-global'), "zrodlo: $Repo`r`nwersja: 0.25.2`r`n", $Utf8)
  $backup = Join-Path $Robocze 'Backup'
  [System.IO.File]::WriteAllText((Join-Path $dom '.claude\mr\kopia-stan.txt'), "stan=OK`r`nostatnia=2026-10-02 08:54:06`r`ncel=$backup\zmiany\2026-10-02`r`n", $Utf8)
  $dom_json = [System.IO.File]::ReadAllText((Join-Path $Repo 'narzedzia\kopia-zapasowa-domyslne.json'), $Utf8) | ConvertFrom-Json
  $celJson = "$($dom_json.cel)".TrimEnd('\')
  $ileWykl = @($dom_json.wykluczenia).Count
  $sc = Zapisz-Scenariusz 'bezrejestru' (@'
$script:TestKroki = @(
  @{ N = 'wybor bez rejestru'; Czekaj = { $script:Ekran -eq 'wybor' }; Zrzut = '11-zmiana-bez-rejestru'; Sprawdz = { $m = $script:Wybor.Moduly; Tak (($script:Tryb -eq 'zmiana') -and $m.wiedza -and $m.lore -and $m.kierownik -and $m.skille -and $m.kopia -and $script:BDalej.Enabled) "wszystko zaznaczone, Zastosuj wlaczone" } },
  @{ N = 'kopia z dotychczasowych ustawien'; Sprawdz = { $w = @($script:Wybor.KopiaWykluczenia | Where-Object { $_.Zaznaczone }); Tak (($script:KopiaNaStart.Skad -eq 'dotychczasowe') -and ($script:Wybor.KopiaCel -eq '__CELJSON__') -and ($w.Count -eq __ILE__) -and ($script:ListaWykluczen.Controls.Count -eq __ILE__) -and (@($script:Wybor.KopiaZrodla | Where-Object { $_.Zaznaczone -and ($_.Sciezka -eq (Join-Path $script:Dom '.claude')) }).Count -eq 1)) "skad $($script:KopiaNaStart.Skad), cel $($script:Wybor.KopiaCel), wykluczen $($w.Count), ~ rozwiniete na dom testowy" } },
  @{ N = 'zastosuj'; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'podsumowanie bez zmian'; Czekaj = { $script:Ekran -eq 'podsumowanie' }; Zrzut = '12-bez-rejestru-podsumowanie'; Sprawdz = { $ids = @($script:PlanDoWykonania | ForEach-Object { $_.Id }) -join ','; Tak ($ids -eq 'zapamietaj') "plan: $ids" } },
  @{ N = 'tak, zastosuj'; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'gotowe'; Czekaj = { $script:Ekran -eq 'gotowe' }; Limit = 60 }
)
'@).Replace('__CELJSON__', $celJson).Replace('__ILE__', "$ileWykl")
  Wyczysc-Wywolania
  $r = Uruchom-Ps $Okno (Argumenty-Okna $dom $sc.Plik $Atrapy) 180
  [void](Ocen-Raport 'zmiana bez rejestru' $sc $r)
  $rej = Czytaj-Rejestr $dom
  $ok = $rej -and $rej.moduly.wiedza -and $rej.moduly.lore -and $rej.moduly.kierownik -and $rej.moduly.skille -and $rej.moduly.kopia
  Wynik 'zmiana bez rejestru - rejestr zapisany' $ok ($(if ($rej) { $rej.moduly | ConvertTo-Json -Compress } else { 'brak pliku' }))
  $wy = @(); if ($rej -and $rej.kopia) { $wy = @($rej.kopia.wykluczenia) }
  $ok = $rej -and ($rej.kopia.cel -eq $celJson) -and ($wy.Count -eq $ileWykl) -and (@($wy | Where-Object { $_.sciezka -and $_.powod -and ($_.katalog -eq $true) }).Count -eq $ileWykl) -and (@($rej.kopia.zrodla) -contains (Join-Path $dom '.claude')) -and (@($rej.kopia.zrodla) -contains 'C:\dev')
  Wynik 'zmiana bez rejestru - ustawienia kopii przeniesione z kopia-zapasowa-domyslne.json' $ok ($(if ($rej) { $rej.kopia | ConvertTo-Json -Compress -Depth 5 } else { 'brak pliku' }))
  $w = Wszystkie-Wywolania
  Wynik 'zmiana bez rejestru - zaden skrypt nie ruszony' ($w.Count -eq 0) "wywolan: $($w.Count) $(Kolejnosc $w)"
}

# --- D. uszkodzony rejestr (proba negatywna: nic nie usuwa) --------------------------
if (Chce 'uszkodzony') {
  $dom = Nowy-Dom 'uszkodzony'
  New-Item -ItemType Directory -Force -Path (Join-Path $dom '.claude\mr') | Out-Null
  [System.IO.File]::WriteAllBytes((Join-Path $dom '.claude\mr\instalacja.json'), (New-Object byte[] 64))
  $sc = Zapisz-Scenariusz 'uszkodzony' @'
$script:TestKroki = @(
  @{ N = 'karta bledu rejestru'; Czekaj = { $script:Ekran -eq 'wybor' }; Zrzut = '13-rejestr-uszkodzony'; Sprawdz = { Tak (($script:Tryb -eq 'zmiana') -and $script:Instalacja.blad -and (-not $script:BDalej.Enabled) -and ($script:LStopka.Text -like '*uszkodzony*')) "blad: $($script:Instalacja.blad)" } },
  @{ N = 'proba negatywna: odznaczenie zablokowane'; Zrob = { $script:CheckboxyModulow.wiedza.Checked = $false }; Sprawdz = { Tak ($script:CheckboxyModulow.wiedza.Checked -and $script:Wybor.Moduly.wiedza -and (-not $script:Nakladka.Visible) -and ($script:LBladRejestru.Text -like '*wstrzymane*')) "zostalo zaznaczone: $($script:LBladRejestru.Text)" } },
  @{ N = 'odloz zapis'; Zrob = { $script:BOdloz.PerformClick() } },
  @{ N = 'po odlozeniu'; Czekaj = { ($script:Ekran -eq 'wybor') -and -not $script:Instalacja.blad }; Zrzut = '14-rejestr-odlozony'; Sprawdz = { Tak ($script:BDalej.Enabled -and ($script:Instalacja.zrodlo -eq 'domyslne')) "zrodlo stanu: $($script:Instalacja.zrodlo)" } }
)
'@
  $r = Uruchom-Ps $Okno (Argumenty-Okna $dom $sc.Plik $Atrapy) 120
  [void](Ocen-Raport 'uszkodzony rejestr' $sc $r)
  $odl = @(Get-ChildItem -LiteralPath (Join-Path $dom '.claude\mr') -Filter 'instalacja.json.uszkodzony-*')
  Wynik 'uszkodzony rejestr - plik odlozony, nie skasowany' (($odl.Count -eq 1) -and ($odl[0].Length -eq 64) -and -not (Test-Path -LiteralPath (Join-Path $dom '.claude\mr\instalacja.json'))) "$($odl.Name)"
}

# --- E. proba (-Proba): nic nie zapisane ------------------------------------------
if (Chce 'proba') {
  $dom = Nowy-Dom 'proba'
  $sc = Zapisz-Scenariusz 'proba' @'
$script:TestKroki = @(
  @{ N = 'powitanie z karta proby'; Czekaj = { $script:Ekran -eq 'powitanie' }; Zrzut = '15-proba-powitanie' },
  @{ N = 'dalej'; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'dalej 2'; Czekaj = { $script:Ekran -eq 'wybor' }; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'zainstaluj'; Czekaj = { ($script:Ekran -eq 'podsumowanie') -and $script:Sprawdzenie -and ($script:Sprawdzenie.Zadanie.Stan -ne 'trwa') }; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'blad lore w probie'; Czekaj = { $script:PlanStan -eq 'blad' }; Limit = 60; Zrob = { $script:BPonow.PerformClick() } },
  @{ N = 'gotowe w probie'; Czekaj = { $script:Ekran -eq 'gotowe' }; Limit = 90; Zrzut = '16-proba-gotowe'; Sprawdz = { Tak ((@($script:Plan | Where-Object { $_.Id -eq 'zapamietaj' })[0].Stan -eq 'pominiety')) "zapis wyboru pominiety" } }
)
'@
  Wyczysc-Wywolania
  $r = Uruchom-Ps $Okno (Argumenty-Okna $dom $sc.Plik $Atrapy -Proba) 240
  [void](Ocen-Raport 'proba' $sc $r)
  $w = Wszystkie-Wywolania
  $bez = @($w | Where-Object { $_ -notlike '*Proba=True*' })
  Wynik 'proba - kazdy skrypt dostal -Proba' (($w.Count -gt 5) -and ($bez.Count -eq 0)) "wywolan $($w.Count), bez -Proba: $($bez -join ' ')"
  Wynik 'proba - rejestr nie zapisany' (-not (Test-Path -LiteralPath (Join-Path $dom '.claude\mr\instalacja.json'))) ''
  Wynik 'proba - dziennik poza katalogiem domowym' (-not (Test-Path -LiteralPath (Join-Path $dom 'AppData'))) ''
}

# --- F. zlamana umowa (proby negatywne odczytu WYNIK) --------------------------------
if (Chce 'umowa') {
  $dom = Nowy-Dom 'umowa'
  $sc = Zapisz-Scenariusz 'umowa' @'
$script:TestKroki = @(
  @{ N = 'dalej'; Czekaj = { $script:Ekran -eq 'powitanie' }; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'dalej 2'; Czekaj = { $script:Ekran -eq 'wybor' }; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'zainstaluj'; Czekaj = { ($script:Ekran -eq 'podsumowanie') -and $script:Sprawdzenie -and ($script:Sprawdzenie.Zadanie.Stan -ne 'trwa') }; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'brak WYNIK = blad'; Czekaj = { $script:PlanStan -eq 'blad' }; Limit = 60; Zrzut = '17-umowa-brak-wyniku'; Sprawdz = { Tak ($script:LBleduTresc.Text -like '*bez wyniku*koniec bez wyniku*') "$($script:LBleduTresc.Text)" } },
  @{ N = 'ponow 1'; Zrob = { $script:BPonow.PerformClick() } },
  @{ N = 'ok:true z kodem 1 = blad'; Czekaj = { ($script:PlanStan -eq 'blad') -and ($script:Plan[$script:PlanIndeks].Proby -eq 2) }; Limit = 60; Sprawdz = { Tak ($script:LBleduTresc.Text -like '*kodem 1*nie traktuję*') "$($script:LBleduTresc.Text)" } },
  @{ N = 'ponow 2'; Zrob = { $script:BPonow.PerformClick() } },
  @{ N = 'smieci zamiast JSON = blad'; Czekaj = { ($script:PlanStan -eq 'blad') -and ($script:Plan[$script:PlanIndeks].Proby -eq 3) }; Limit = 60; Sprawdz = { Tak ($script:LBleduTresc.Text -like '*nie umiem odczytać*') "$($script:LBleduTresc.Text)" } },
  @{ N = 'ponow 3'; Zrob = { $script:BPonow.PerformClick() } },
  @{ N = 'czwarte podejscie przechodzi'; Czekaj = { ($script:Plan[1].Stan -eq 'ok') }; Limit = 60; Sprawdz = { Tak ($script:Plan[1].Proby -eq 4) "podejsc: $($script:Plan[1].Proby)" } },
  @{ N = 'reszta do konca'; Czekaj = { ($script:PlanStan -eq 'blad') -or ($script:Ekran -eq 'gotowe') }; Limit = 90; Zrob = { if ($script:PlanStan -eq 'blad') { $script:BPonow.PerformClick() } } },
  @{ N = 'gotowe'; Czekaj = { $script:Ekran -eq 'gotowe' }; Limit = 90 }
)
'@
  Wyczysc-Wywolania
  $r = Uruchom-Ps $Okno (Argumenty-Okna $dom $sc.Plik $AtrapyZle) 300
  [void](Ocen-Raport 'zlamana umowa' $sc $r)
}

# --- G. brak skryptu modulu -------------------------------------------------------
if (Chce 'brak') {
  $dom = Nowy-Dom 'brak'
  $sc = Zapisz-Scenariusz 'brak' @'
$script:TestKroki = @(
  @{ N = 'dalej'; Czekaj = { $script:Ekran -eq 'powitanie' }; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'dalej 2'; Czekaj = { $script:Ekran -eq 'wybor' }; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'podsumowanie blokuje'; Czekaj = { $script:Ekran -eq 'podsumowanie' }; Zrzut = '18-brak-skryptu'; Sprawdz = { Tak ((-not $script:BDalej.Enabled) -and ($script:LStopka.Text -like '*Brakuje plików*')) "Zainstaluj wylaczone: $($script:LStopka.Text)" } }
)
'@
  $r = Uruchom-Ps $Okno (Argumenty-Okna $dom $sc.Plik $AtrapyBrak) 120
  [void](Ocen-Raport 'brak skryptu' $sc $r)
}

# --- H. przerwanie i zamkniecie w trakcie ------------------------------------------
if (Chce 'przerwij') {
  $dom = Nowy-Dom 'przerwij'
  [System.IO.File]::WriteAllText((Join-Path $dom 'atrapa-wolno.txt'), '1')
  [System.IO.File]::WriteAllText((Join-Path $dom 'atrapa-lore-raz.txt'), 'bez bledu lore')
  $sc = Zapisz-Scenariusz 'przerwij' @'
$script:TestKroki = @(
  @{ N = 'dalej'; Czekaj = { $script:Ekran -eq 'powitanie' }; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'dalej 2'; Czekaj = { $script:Ekran -eq 'wybor' }; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'zainstaluj'; Czekaj = { ($script:Ekran -eq 'podsumowanie') -and $script:Sprawdzenie -and ($script:Sprawdzenie.Zadanie.Stan -ne 'trwa') }; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'zamkniecie w trakcie pyta'; Czekaj = { (@($script:Plan | Where-Object { ($_.Id -eq 'wiedza-Instaluj') -and ($_.Stan -eq 'trwa') -and ($_.Kroki.Count -gt 0) }).Count -gt 0) }; Limit = 60; Zrob = { $script:Okno.Close() } },
  @{ N = 'pytanie przy zamykaniu'; Czekaj = { $script:Nakladka.Visible }; Zrzut = '19-zamkniecie-pytanie'; Sprawdz = { Tak (-not $script:Okno.IsDisposed) "okno nie zamknelo sie w trakcie" }; Zrob = { $script:PrzyciskiPytania[1].PerformClick() } },
  @{ N = 'przerwij'; Czekaj = { -not $script:Nakladka.Visible }; Zrob = { $script:BAnuluj.PerformClick() } },
  @{ N = 'potwierdz przerwanie'; Czekaj = { $script:Nakladka.Visible }; Zrob = { $script:PrzyciskiPytania[0].PerformClick() } },
  @{ N = 'przerwane'; Czekaj = { $script:PlanStan -eq 'przerwany' }; Limit = 30; Zrzut = '20-przerwane'; Sprawdz = { Tak (($script:LBleduTytul.Text -like 'Przerwane:*') -and ($script:Plan[$script:PlanIndeks].Stan -eq 'przerwany')) "$($script:LBleduTytul.Text)" } },
  @{ N = 'ponow po przerwaniu'; Zrob = { $script:BPonow.PerformClick() } },
  @{ N = 'gotowe'; Czekaj = { $script:Ekran -eq 'gotowe' }; Limit = 120 }
)
'@
  $r = Uruchom-Ps $Okno (Argumenty-Okna $dom $sc.Plik $Atrapy) 300
  [void](Ocen-Raport 'przerwanie' $sc $r)
  $sieroty = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*$Atrapy*modul-wiedza*" })
  Wynik 'przerwanie - zaden proces atrapy nie zostal' ($sieroty.Count -eq 0) "zostalo $($sieroty.Count)"
}

# --- P. czysty komputer: okno z folderu bez .git -------------------------------------
function Kopia-Bez-Gita([string]$cel) {
  $m = Join-Path $cel 'MegaRuchacz-main'
  New-Item -ItemType Directory -Force -Path (Join-Path $m 'narzedzia\instalacja'), (Join-Path $m 'instalator') | Out-Null
  Copy-Item -Path (Join-Path $Repo 'instalator\*.ps1') -Destination (Join-Path $m 'instalator')
  Copy-Item -LiteralPath (Join-Path $Repo 'narzedzia\instalacja\stan.ps1') -Destination (Join-Path $m 'narzedzia\instalacja')
  Copy-Item -LiteralPath (Join-Path $Repo 'logo.png') -Destination $m
  Copy-Item -LiteralPath (Join-Path $Repo 'instaluj.bat') -Destination $m
  return $m
}

if (Chce 'pobieranie') {
  # Zrodlo klonu z instalatorem: tymczasowe repo = klon tego repo + biezace pliki instalatora
  # w jednym commicie (prawdziwe repo zostaje nietkniete). GitHub dostanie je dopiero po push.
  if (-not $PSBoundParameters.ContainsKey('ZrodloKlonu')) {
    $ZrodloKlonu = Join-Path $Robocze 'repo-z-instalatorem'
    $poprz = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & git clone --quiet $Repo $ZrodloKlonu 2>&1 | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $ZrodloKlonu 'instalator') | Out-Null
    Copy-Item -Path (Join-Path $Repo 'instalator\*.ps1') -Destination (Join-Path $ZrodloKlonu 'instalator') -Force
    Copy-Item -LiteralPath (Join-Path $Repo 'instaluj.bat') -Destination $ZrodloKlonu -Force
    & git -C $ZrodloKlonu add -A 2>&1 | Out-Null
    & git -C $ZrodloKlonu -c user.name=test -c user.email=test@example.invalid commit --quiet -m 'test: instalator' 2>&1 | Out-Null
    $ErrorActionPreference = $poprz
  }
  foreach ($wariant in @('github', 'lokalny')) {
    $dom = Nowy-Dom "pobieranie-$wariant"
    $zip = Kopia-Bez-Gita (Join-Path $Robocze "zip-$wariant")
    $cel = Join-Path $Robocze "cel-$wariant\MegaRuchacz"
    $adres = 'https://github.com/Primo2966/MegaRuchacz.git'
    if ($wariant -eq 'lokalny') { $adres = $ZrodloKlonu }
    $sc2 = Zapisz-Scenariusz "z-klonu-$wariant" @'
$script:TestKroki = @(
  @{ N = 'okno z klonu'; Czekaj = { ($script:Ekran -eq 'powitanie') -or ($script:Ekran -eq 'wybor') }; Zrzut = '0d-z-klonu'; Sprawdz = { Tak (($script:Tryb -eq 'nowy') -and (Test-Path (Join-Path $script:Zrodlo '.git'))) "tryb $($script:Tryb), zrodlo $($script:Zrodlo)" } }
)
'@
    $zrzutPostepu = "0b-pobieranie-$wariant"
    $sc = Zapisz-Scenariusz "pobieranie-$wariant" (@'
$script:TestKroki = @(
  @{ N = 'folder'; Czekaj = { $script:Ekran -eq 'folder' }; Zrzut = '0-folder'; Sprawdz = { Tak (($script:Tryb -eq 'pobieranie') -and ($script:PoleFolderu.Text -eq (Join-Path $script:Dom 'MegaRuchacz'))) "domyslny folder: $($script:PoleFolderu.Text)" } },
  @{ N = 'proba negatywna: niepusty folder'; Zrob = { $script:PoleFolderu.Text = $script:Dom }; Sprawdz = { Tak ((-not $script:BDalej.Enabled) -and ($script:LFolderInfo.Text -like '*nie jest pusty*')) "$($script:LFolderInfo.Text)" } },
  @{ N = 'folder docelowy'; Zrob = { $script:PoleFolderu.Text = '__CEL__' }; Sprawdz = { Tak $script:BDalej.Enabled "$($script:LFolderInfo.Text)" } },
  @{ N = 'dalej'; Zrob = { $script:BDalej.PerformClick() } },
  @{ N = 'pobieranie trwa'; Czekaj = { ($script:Ekran -eq 'postep') -and ($script:Plan[0].Stan -ne 'czeka') }; Zrzut = '__ZRZUT__' },
  @{ N = 'koniec pobierania'; Czekaj = { @('gotowe', 'blad') -contains $script:PlanStan }; Limit = 180; Zrzut = '__ZRZUT__-koniec'; Sprawdz = { Tak $true "plan: $($script:PlanStan); $(@($script:Plan | ForEach-Object { $_.Id + '=' + $_.Stan + ' ' + $_.Komunikat }) -join ' | ')" } }
)
'@).Replace('__CEL__', $cel).Replace('__ZRZUT__', $zrzutPostepu)
    $a = @('-KatalogDomowy', $dom, '-KatalogSkryptow', $Atrapy, '-PozaEkranem', '-Proba', '-Scenariusz', $sc.Plik, '-ScenariuszDalej', $sc2.Plik, '-ZrodloKlonu', $adres)
    $r = Uruchom-Ps (Join-Path $zip 'instalator\okno.ps1') $a 300
    $t = Ocen-Raport "czysty komputer ($wariant)" $sc $r
    $klon = Test-Path -LiteralPath (Join-Path $cel '.git')
    Wynik "czysty komputer ($wariant) - klon w folderze tymczasowym" $klon $cel
    if ($wariant -eq 'github') {
      $kon = @($t | Where-Object { $_ -like 'SPRAWDZ koniec pobierania*' })
      $spodz = (Test-Path -LiteralPath (Join-Path $cel 'instalator\okno.ps1'))
      if (-not $spodz) { Wynik 'czysty komputer (github) - brak instalatora w klonie zgloszony' (($kon -join ' ') -like '*uruchom=blad W pobranym MegaRuchaczu nie ma instalatora*') ($kon -join ' ') }
    } else {
      $do = (Get-Date).AddSeconds(90)
      while (((Get-Date) -lt $do) -and -not ((Test-Path -LiteralPath $sc2.Raport) -and (@(Get-Content -LiteralPath $sc2.Raport -Encoding UTF8) -contains 'KONIEC'))) { Start-Sleep -Milliseconds 500 }
      Start-Sleep -Seconds 2
      [void](Ocen-Raport "czysty komputer (lokalny) - okno z klonu" $sc2 ([pscustomobject]@{ Kod = 0; Bledy = '' }))
    }
  }
  # Sam skrypt pobierania gita z -Proba (git jest na tym komputerze).
  $pg = Uruchom-Ps (Join-Path $Repo 'instalator\pobierz.ps1') @('-Co', 'git', '-Proba') 120
  Wynik 'pobierz.ps1 -Co git -Proba' (($pg.Kod -eq 0) -and ($pg.Wyjscie -match 'WYNIK: \{"ok":true')) (($pg.Wyjscie -split "`n" | Where-Object { $_ -match '^(KROK|WYNIK)' }) -join ' | ')
  # Droga bez gita: zaleznosci.ps1 (atrapa, ktora gita nie daje) -> MinGit z GitHuba - prawdziwe
  # zapytanie o najnowsze wydanie, bez pobierania (-Proba).
  $zr = Join-Path $Robocze 'zrodlo-bez-gita'
  New-Item -ItemType Directory -Force -Path (Join-Path $zr 'narzedzia\instalacja') | Out-Null
  Zapisz-Bom (Join-Path $zr 'narzedzia\instalacja\zaleznosci.ps1') "param([string]`$Akcja, [string[]]`$Potrzebne, [switch]`$Proba)`r`nWrite-Output 'KROK: winget nie odpowiada (atrapa)'`r`nWrite-Output 'WYNIK: {""ok"":false,""komunikat"":""winget nie zadzialal (atrapa)"",""kroki"":[]}'`r`nexit 1`r`n"
  $pg = Uruchom-Ps (Join-Path $Repo 'instalator\pobierz.ps1') @('-Co', 'git', '-Proba', '-UdawajBrakGita', '-Zrodlo', $zr) 120
  $linie = @($pg.Wyjscie -split "`n" | Where-Object { $_ -match '^(KROK|UWAGA|WYNIK)' })
  Wynik 'pobierz.ps1 bez gita: zaleznosci -> MinGit (proba)' (($pg.Kod -eq 0) -and ($pg.Wyjscie -match 'UWAGA: Narzędzie zależności nie dało gita') -and ($pg.Wyjscie -match 'WYNIK: \{"ok":true,"komunikat":"\(próba\) Gita nie ma - pobrałbym przenośnego MinGit-[0-9.]+(-[0-9]+)?-(64|32)-bit\.zip')) ($linie -join ' | ')
  $pg = Uruchom-Ps (Join-Path $Repo 'instalator\pobierz.ps1') @('-Co', 'git', '-UdawajBrakGita') 60
  Wynik 'pobierz.ps1 -UdawajBrakGita bez -Proba odmawia (proba negatywna)' (($pg.Kod -eq 1) -and ($pg.Wyjscie -match 'tylko z -Proba')) (($pg.Wyjscie -replace '\s+', ' ').Trim())
}

# --- instaluj.bat ------------------------------------------------------------------
# Obserwator: kazde WIDOCZNE okno nowych procesow konsoli (cmd, conhost, powershell, Windows
# Terminal) - okno instalatora poza ekranem jest jedynym dozwolonym.
$obserwatorKod = @'
param([string]$Plik, [string]$Stop, [string]$Od)
Add-Type -TypeDefinition @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class Okna {
  public delegate bool Wylicz(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(Wylicz f, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out R r);
  public struct R { public int L, T, P, D; }
  public static List<string> Widoczne() {
    var w = new List<string>();
    EnumWindows((h, l) => { if (IsWindowVisible(h)) { uint pid; GetWindowThreadProcessId(h, out pid); var t = new StringBuilder(256); GetWindowText(h, t, 256); var k = new StringBuilder(256); GetClassName(h, k, 256); R r; GetWindowRect(h, out r); w.Add(h.ToInt64() + "|" + pid + "|" + k + "|" + t + "|" + r.L + "," + r.T + "," + r.P + "," + r.D); } return true; }, IntPtr.Zero);
    return w;
  }
}
"@
$od = [datetime]::Parse($Od)
$widziane = @{}
$nazwy = @('cmd', 'conhost', 'powershell', 'OpenConsole', 'WindowsTerminal')
while (-not (Test-Path -LiteralPath $Stop)) {
  foreach ($x in [Okna]::Widoczne()) {
    $c = $x -split '\|'
    if ($widziane.ContainsKey($c[0])) { continue }
    $widziane[$c[0]] = $true
    $p = Get-Process -Id ([int]$c[1]) -ErrorAction SilentlyContinue
    if ($p -and ($nazwy -contains $p.ProcessName) -and ($p.StartTime -ge $od)) { Add-Content -LiteralPath $Plik -Value ("$($p.ProcessName)|$x") -Encoding UTF8 }
  }
  Start-Sleep -Milliseconds 20
}
'@
$obserwatorPlik = Join-Path $Robocze 'obserwator.ps1'
Zapisz-Bom $obserwatorPlik $obserwatorKod

function Z-Obserwatorem([string]$nazwa, [scriptblock]$co) {
  $okna = Join-Path $Robocze "okna-$nazwa.txt"; $stop = Join-Path $Robocze "stop-$nazwa.txt"
  Remove-Item -LiteralPath $okna, $stop -Force -ErrorAction SilentlyContinue
  $od = (Get-Date).AddSeconds(-1).ToString('o')
  $obs = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File ' + (Cytuj $obserwatorPlik) + ' -Plik ' + (Cytuj $okna) + ' -Stop ' + (Cytuj $stop) + ' -Od ' + (Cytuj $od)) -NoNewWindow -PassThru
  Start-Sleep -Seconds 2
  $wynik = & $co
  Start-Sleep -Seconds 1
  [System.IO.File]::WriteAllText($stop, 'stop')
  [void]$obs.WaitForExit(10000)
  $lista = @()
  if (Test-Path -LiteralPath $okna) { $lista = @(Get-Content -LiteralPath $okna -Encoding UTF8) }
  $obce = @($lista | Where-Object { -not (($_ -like '*|MegaRuchacz – instalacja|*') -and ($_ -match '\|-5\d\d\d,')) })
  return [pscustomobject]@{ Wynik = $wynik; Okna = $lista; Obce = $obce }
}

function Uruchom-Bat([string]$bat, [string[]]$argumenty, [hashtable]$srodowisko = @{}, [int]$limit = 120) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
  $psi.Arguments = '/d /c "' + (Cytuj $bat) + ' ' + (($argumenty | ForEach-Object { Cytuj $_ }) -join ' ') + ' < NUL"'
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  foreach ($k in $srodowisko.Keys) { $psi.EnvironmentVariables[$k] = $srodowisko[$k] }
  $start = Get-Date
  $p = [System.Diagnostics.Process]::Start($psi)
  $wyZ = $p.StandardOutput.ReadToEndAsync(); $blZ = $p.StandardError.ReadToEndAsync()
  $kod = 'LIMIT'
  if ($p.WaitForExit($limit * 1000)) { $kod = $p.ExitCode } else { & taskkill.exe /PID $p.Id /T /F | Out-Null }
  return [pscustomobject]@{ Kod = $kod; Wyjscie = ($wyZ.Result + $blZ.Result); Sekund = [math]::Round(((Get-Date) - $start).TotalSeconds, 1) }
}

function Czekaj-Na-Koniec([string]$raport, [int]$s = 90) {
  $do = (Get-Date).AddSeconds($s)
  while ((Get-Date) -lt $do) {
    if ((Test-Path -LiteralPath $raport) -and (@(Get-Content -LiteralPath $raport -Encoding UTF8) -contains 'KONIEC')) { Start-Sleep -Seconds 2; return $true }
    Start-Sleep -Milliseconds 500
  }
  return $false
}

if (Chce 'bat') {
  # 1. W repo: konsola .bat konczy sie, gdy okno stanie; nic poza oknem instalatora sie nie pokazuje.
  $dom = Nowy-Dom 'bat-repo'
  $sc = Zapisz-Scenariusz 'bat-repo' @'
$script:TestKroki = @(
  @{ N = 'okno z instaluj.bat'; Czekaj = { $script:Ekran -eq 'powitanie' }; Sprawdz = { Tak ($script:Znacznik -like '*okno-wstalo.txt') "znacznik: $($script:Znacznik)" } },
  @{ N = 'chwila'; Czekaj = { $script:Tyk -ge 0 } }
)
'@
  $o = Z-Obserwatorem 'bat-repo' { Uruchom-Bat (Join-Path $Repo 'instaluj.bat') (Argumenty-Okna $dom $sc.Plik $Atrapy) }
  $kon = Czekaj-Na-Koniec $sc.Raport 60
  Wynik 'instaluj.bat w repo - konsola konczy sie po starcie okna' (($o.Wynik.Kod -eq 0) -and ($o.Wynik.Sekund -lt 25) -and $kon) "kod $($o.Wynik.Kod), $($o.Wynik.Sekund) s, okno: $kon"
  [void](Ocen-Raport 'instaluj.bat w repo' $sc ([pscustomobject]@{ Kod = 0; Bledy = '' }))
  Wynik 'instaluj.bat w repo - nic nie mignelo' (($o.Obce.Count -eq 0) -and ($o.Okna.Count -ge 1)) "widoczne okna nowych procesow: $($o.Okna -join ' || ')"

  # 2. Poza repo: ZIP z pliku (MR_ZIP_URL) -> rozpakowanie -> okno w trybie pobieranie.
  $dom = Nowy-Dom 'bat-zip'
  $zrodloZip = Kopia-Bez-Gita (Join-Path $Robocze 'do-zipa')
  $zipPlik = Join-Path $Robocze 'MegaRuchacz-test.zip'
  if (Test-Path -LiteralPath $zipPlik) { Remove-Item -LiteralPath $zipPlik -Force }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::CreateFromDirectory((Split-Path -Parent $zrodloZip), $zipPlik)
  $sam = Join-Path $Robocze 'sam-bat'
  New-Item -ItemType Directory -Force -Path $sam | Out-Null
  Copy-Item -LiteralPath (Join-Path $Repo 'instaluj.bat') -Destination $sam -Force
  $sc = Zapisz-Scenariusz 'bat-zip' @'
$script:TestKroki = @(
  @{ N = 'okno z pobranego ZIP-a'; Czekaj = { $script:Ekran -eq 'folder' }; Zrzut = 'bat-zip-folder'; Sprawdz = { Tak (($script:Tryb -eq 'pobieranie') -and ($script:Zrodlo -like '*MegaRuchacz-instalator\rozpakowany\MegaRuchacz-main')) "tryb $($script:Tryb), zrodlo $($script:Zrodlo)" } }
)
'@
  $url = 'file:///' + ($zipPlik -replace '\\', '/')
  $o = Z-Obserwatorem 'bat-zip' { Uruchom-Bat (Join-Path $sam 'instaluj.bat') (Argumenty-Okna $dom $sc.Plik $Atrapy) @{ MR_ZIP_URL = $url } }
  $kon = Czekaj-Na-Koniec $sc.Raport 60
  Wynik 'instaluj.bat poza repo - pobranie ZIP-a i okno pobierania' (($o.Wynik.Kod -eq 0) -and $kon) "kod $($o.Wynik.Kod), $($o.Wynik.Sekund) s; $($o.Wynik.Wyjscie.Trim())"
  [void](Ocen-Raport 'instaluj.bat poza repo' $sc ([pscustomobject]@{ Kod = 0; Bledy = '' }))
  Wynik 'instaluj.bat poza repo - nic nie mignelo' ($o.Obce.Count -eq 0) "widoczne okna nowych procesow: $($o.Okna -join ' || ')"

  # 3. Prawdziwy ZIP z GitHuba: pobranie i rozpakowanie dzialaja, a brak instalatora w nim
  #    (wersja sprzed wypchniecia P59c) konczy sie glosnym komunikatem, nie cisza.
  # Argumenty testowe tez tutaj: gdyby GitHub mial juz instalator, okno ma stanac poza ekranem i samo sie zamknac.
  $dom = Nowy-Dom 'bat-github'
  $sc = Zapisz-Scenariusz 'bat-github' @'
$script:TestKroki = @( @{ N = 'okno z ZIP-a z GitHuba'; Czekaj = { $script:Ekran -eq 'folder' } } )
'@
  $o = Z-Obserwatorem 'bat-github' { Uruchom-Bat (Join-Path $sam 'instaluj.bat') (Argumenty-Okna $dom $sc.Plik $Atrapy) @{} 120 }
  $rozp = Join-Path ([System.IO.Path]::GetTempPath()) 'MegaRuchacz-instalator\rozpakowany\MegaRuchacz-main\narzedzia\straznik-zasad.ps1'
  $maInst = Test-Path -LiteralPath (Join-Path ([System.IO.Path]::GetTempPath()) 'MegaRuchacz-instalator\rozpakowany\MegaRuchacz-main\instalator\okno.ps1')
  if ($maInst) { Wynik 'instaluj.bat + ZIP z GitHuba' ($o.Wynik.Kod -eq 0) "GitHub ma juz instalator - okno startowalo (kod $($o.Wynik.Kod))" }
  else { Wynik 'instaluj.bat + ZIP z GitHuba (proba negatywna)' ((Test-Path -LiteralPath $rozp) -and ($o.Wynik.Wyjscie -like '*nie ma instalatora*')) "pobrany i rozpakowany: $(Test-Path -LiteralPath $rozp); konsola: $(($o.Wynik.Wyjscie -replace '\s+', ' ').Trim())" }
  Wynik 'instaluj.bat + ZIP z GitHuba - nic nie mignelo' ($o.Obce.Count -eq 0) "$($o.Okna -join ' || ')"

  # 4. Okno odmawia startu: konsola zostaje z powodem (znacznik ODMOWA).
  $zly = Join-Path $Robocze 'bat-odmowa'
  New-Item -ItemType Directory -Force -Path (Join-Path $zly 'instalator') | Out-Null
  Copy-Item -LiteralPath (Join-Path $Repo 'instaluj.bat') -Destination $zly -Force
  Zapisz-Bom (Join-Path $zly 'instalator\okno.ps1') "param([string]`$Znacznik = '')`r`n[System.IO.File]::WriteAllText(`$Znacznik, 'ODMOWA nie ma pliku narzedzia\instalacja\stan.ps1 (próba negatywna)', (New-Object System.Text.UTF8Encoding(`$false)))`r`nexit 3`r`n"
  $o = Z-Obserwatorem 'bat-odmowa' { Uruchom-Bat (Join-Path $zly 'instaluj.bat') @() @{} 60 }
  Wynik 'instaluj.bat - odmowa okna zostaje w konsoli' (($o.Wynik.Wyjscie -like '*nie wystartowal*') -and ($o.Wynik.Wyjscie -like '*negatywna)*') -and ($o.Wynik.Sekund -lt 20)) "$($o.Wynik.Sekund) s; $(($o.Wynik.Wyjscie -replace '\s+', ' ').Trim())"

  # 5. Okno nie wstaje wcale (bez znacznika): po 30 s konsola uruchamia je jeszcze raz na wierzchu, z bledem.
  $nic = Join-Path $Robocze 'bat-nie-wstaje'
  New-Item -ItemType Directory -Force -Path (Join-Path $nic 'instalator') | Out-Null
  Copy-Item -LiteralPath (Join-Path $Repo 'instaluj.bat') -Destination $nic -Force
  Zapisz-Bom (Join-Path $nic 'instalator\okno.ps1') "param([string]`$Znacznik = '')`r`n[Console]::Error.WriteLine('instalator: proba negatywna - okno nie wstaje')`r`nexit 3`r`n"
  $o = Z-Obserwatorem 'bat-nie-wstaje' { Uruchom-Bat (Join-Path $nic 'instaluj.bat') @() @{} 90 }
  Wynik 'instaluj.bat - okno, ktore nie wstaje, nie ginie po cichu' (($o.Wynik.Wyjscie -like '*nie pojawilo sie*') -and ($o.Wynik.Wyjscie -like '*okno nie wstaje*')) "$($o.Wynik.Sekund) s; $(($o.Wynik.Wyjscie -replace '\s+', ' ').Trim())"
  Wynik 'instaluj.bat - okno, ktore nie wstaje - nic nie mignelo' ($o.Obce.Count -eq 0) "$($o.Okna -join ' || ')"
}

# --- podsumowanie --------------------------------------------------------------
$zostaly = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { ($_.CommandLine -like '*instalator\okno.ps1*') -and ($_.CommandLine -like '*-PozaEkranem*') })
Wynik 'po tescie zadne okno testowe nie zostalo w procesach' ($zostaly.Count -eq 0) "$($zostaly.Count) procesow"
Write-Host ''
Write-Host "Wynik: $(@($script:Wyniki | Where-Object { $_.OK }).Count) z $($script:Wyniki.Count) TAK. Pliki robocze: $Robocze"
if (@($script:Wyniki | Where-Object { -not $_.OK }).Count -gt 0) { exit 1 }
exit 0
