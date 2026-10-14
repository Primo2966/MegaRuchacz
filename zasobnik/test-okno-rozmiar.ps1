# Sprawdzenie rozciagania okna nadzorcy (2026-10-14). Uzytkownik: okno ma sie dac rozciagac
# myszka i maksymalizowac, zeby wygodniej sie czytalo; rozmiar zapamietany miedzy otwarciami.
#   powershell -ExecutionPolicy Bypass -File zasobnik\test-okno-rozmiar.ps1 [-Zasobnik <kat zasobnik>] [-Zrodlo <repo>] [-Dom <kat domowy>] [-Limit <s>] [-BezSabotazy]
# Kopia CALEGO okna (wzor test-okno-mruganie.ps1 / test-p7.ps1): wlasny zamek, poza ekranem
# (-5000, 0), bez paska zadan, bez aktywacji (ShowWithoutActivation, WS_EX_NOACTIVATE, SW_SHOWNA,
# bez SetForegroundWindow), klawiatura wylaczona, bez ikony i dozoru, -Proba, bezpieczniki cyklu
# wiedzy / skilli / tla / aktualizacji w kopii stanu. Dane prawdziwe z -Dom (tylko odczyt).
# Plik z zapamietanym rozmiarem NIE jest prawdziwy: kopia dostaje wlasny w katalogu testu
# (podmieniona kotwica w Plik-Rozmiaru-Okna - w trybie probnym okno nic nie czyta i nie zapisuje).
# Okna NIE maksymalizujemy - zmaksymalizowane staneloby na ekranie uzytkownika. Maksymalizacja
# to ta sama droga co zmiana rozmiaru (Resize -> zegar -> Dopasuj-Do-Rozmiaru); tu sprawdzamy
# ramke, przycisk i zmiane rozmiaru.
#
# Przebiegi (rownolegle, kazdy w osobnym procesie, po wszystkim zaden nie zostaje w procesach):
#  A "pelny" - zepsuty plik rozmiaru -> rozmiar domyslny i wpis w dzienniku; potem po wczytaniu
#    danych pomiar wszystkich zakladek, okno +400 x +120 px, pomiar (karty, pola treści, listy
#    i kolumny urosly, przelacznik dalej przy prawej krawedzi, nic nie wystaje), proba zejscia
#    do 400 x 300 (zostaje MinimumSize, tresc wraca do szerokosci domyslnej), zamkniecie ->
#    zapisany rozmiar w pliku.
#  B "zapamietany" - poprawny plik -> okno w zapamietanym rozmiarze, tresc zlozona od razu
#    w tej szerokosci, wysokosc ponizej najmniejszej podniesiona do MinimumSize.
#  C "poza-ekranem" - polozenie poza wszystkimi ekranami -> rozmiar domyslny, wpis w dzienniku.
#  D "zle-pola" - JSON z polami nie-liczbami -> rozmiar domyslny, wpis w dzienniku, bez wyjatku.
# Proby negatywne (sabotaze na kopii, przebieg pelny): Dopasuj-Do-Rozmiaru wylaczone -> proba
# "rosnie" MUSI pasc; bez MinimumSize -> proba "minimum" MUSI pasc.
param(
  [string]$Zasobnik = $PSScriptRoot,
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [string]$Dom = $HOME,
  [int]$Limit = 360,
  [switch]$BezSabotazy
)
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { Write-Warning "konsola bez UTF-8: $($_.Exception.Message)" }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("test-okno-rozm-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$zrzuty = Join-Path $tmp "zrzuty"
New-Item -ItemType Directory -Force -Path $zrzuty | Out-Null
$utf8bom = New-Object System.Text.UTF8Encoding($true)
$utf8 = New-Object System.Text.UTF8Encoding($false)

$script:wyniki = @()
function Wynik($nazwa, $ok, $opis) {
  $script:wyniki += [pscustomobject]@{ Test = $nazwa; OK = [bool]$ok; Opis = $opis }
  $z = "NIE"; if ($ok) { $z = "TAK" }
  Write-Host ("[{0}] {1} - {2}" -f $z, $nazwa, $opis)
}

# Powiekszenie w przebiegu pelnym. Karty Przegladu i Szczegolow oraz pole Przegladu maja urosnac
# DOKLADNIE o tyle (szerokosc tresci = wnetrze okna minus stale marginesy); Warstwy i Skille dziela
# przyrost na dwie karty w procentach (48/52 i 56/44), wiec kazda z nich - o wiecej niz polowe
# z mniejszej czesci (150 px z 176 px), a nie o kilka pikseli.
$PLUS_SZER = 400
$PLUS_WYS = 120
$PROG_POLOWY = 150

# ---------------------------------------------------------------- scenariusz w kopii okna
$scenariusz = @'
# Scenariusz testu rozmiaru - wczytany kropka w miejsce 'if ($Pokaz) { Pokaz-Okno }' w kopii okna.
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System.Windows.Forms;
namespace RozmTest {
  public class OknoTestowe : Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams { get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x00000080; return cp; } }
  }
}
"@
$script:TWynik = $env:ROZM_WYNIK
$script:TTryb = $env:ROZM_TRYB
$script:TZrzuty = $env:ROZM_ZRZUTY
$script:TLog = New-Object System.Collections.Generic.List[string]
$script:TDziennik = New-Object System.Collections.Generic.List[string]
$script:TSw = [System.Diagnostics.Stopwatch]::StartNew()
function TNotuj($t) {
  $l = ("{0,7} ms  {1}" -f $script:TSw.ElapsedMilliseconds, $t)
  $script:TLog.Add($l)
  [System.IO.File]::AppendAllText($script:TWynik + ".log", $l + "`r`n")
}
# podsluch dziennika nadzorcy (wpisy o nieczytelnym pliku i polozeniu poza ekranem)
$script:TOrygNotuj = ${function:Notuj}
function Notuj([string]$tekst) { $script:TDziennik.Add("$tekst"); & $script:TOrygNotuj $tekst }

function TPompuj([int]$ms) { $k = [System.Diagnostics.Stopwatch]::StartNew(); while ($k.ElapsedMilliseconds -lt $ms) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 5 } }
function TSpokoj { return (-not $script:Ladowanie) -and ($script:KrokiAktywne.Count -eq 0) -and ($script:KolejkaKrokow.Count -eq 0) -and -not ($script:Zuzycie -and ($script:Zuzycie.Stan -eq "licze")) }
function TPrzycisk([string]$w) { switch ($w) { "przeglad" { $script:BPrzeglad } "szczegoly" { $script:BSzczegoly } "warstwy" { $script:BWarstwy } "skille" { $script:BSkille } } }
function TPanel([string]$w) { switch ($w) { "przeglad" { $script:WidokPrzeglad } "szczegoly" { $script:WidokSzczegoly } "warstwy" { $script:WidokWarstwy } "skille" { $script:WidokSkille } } }
function TWidoki { $w = @("przeglad", "szczegoly", "warstwy"); if (Modul-Jest $script:Instalacja "skille") { $w += "skille" }; return $w }

# Kontrolki wychodzace poza prawa krawedz swojego rodzica = tekst uciety po cichu (jak w test-p7.ps1).
function TWystajace($c, $sciezka) {
  $l = @()
  foreach ($d in $c.Controls) {
    if (-not $d.Visible) { continue }
    if (($d.Right -gt ($c.ClientSize.Width + 1)) -and -not ($c -is [System.Windows.Forms.ScrollableControl] -and $c.AutoScroll)) {
      $tx = "" + $d.Text
      $l += "$sciezka/$($d.GetType().Name) '$($tx.Substring(0, [math]::Min(30, $tx.Length)))' prawa=$($d.Right) > $($c.ClientSize.Width)"
    }
    $l += TWystajace $d "$sciezka/$($d.GetType().Name)"
  }
  return $l
}

function TOkno {
  $o = $script:Okno
  return [pscustomobject]@{
    W = $o.Width; H = $o.Height; KW = $o.ClientSize.Width; MinW = $o.MinimumSize.Width; MinH = $o.MinimumSize.Height
    Ramka = "$($o.FormBorderStyle)"; MaxPrzycisk = [bool]$o.MaximizeBox; Stan = "$($o.WindowState)"
    SzerOkna = $script:SzerOkna; SzerTresc = $script:SzerTresc; SzerDomyslna = $script:SzerOknaDomyslna
    Podtytul = $script:LPodtytul.MaximumSize.Width; RootMin = $script:Root.MinimumSize.Width
    OpisPaska = $script:LAktualizuj.MaximumSize.Width
    PrzelOdstep = ($script:Naglowek.ClientSize.Width - $script:Przelacznik.Right)
  }
}

# Zakladka: pokazanie, czekanie na dane, szerokosc karty i pola tresci, wystajace kontrolki.
function TZakladka([string]$w) {
  (TPrzycisk $w).PerformClick(); TPompuj 400
  $k = [System.Diagnostics.Stopwatch]::StartNew()
  while (-not (TSpokoj) -and ($k.ElapsedMilliseconds -lt 90000)) { TPompuj 100 }
  TPompuj 300
  $karta = 0; $pole = 0; $dodatek = 0
  switch ($w) {
    "przeglad"  { $karta = $script:KartaWerdykt.Width; $pole = $script:WidokPrzeglad.ClientSize.Width; $dodatek = $script:Root.Width }
    "szczegoly" { foreach ($c in $script:ListaSzczegolow.Controls) { $karta = [math]::Max($karta, $c.Width) }; $pole = $script:WidokSzczegoly.ClientSize.Width; $dodatek = $script:ListaSzczegolow.Controls.Count }
    "warstwy"   { $karta = $script:KartaListaWarstw.Width; $pole = $script:PodgladWarstwy.Width; $dodatek = $script:ListaWarstw.Columns[0].Width }
    "skille"    {
      $karta = $script:KartaListaSkilli.Width; $pole = $script:SkillePodglad.Width
      $wn = $script:ListaSkilli.Controls[0]; if ($wn -and $wn.Controls.Count -gt 0) { $dodatek = $wn.Controls[0].Width }
    }
  }
  $wy = @(TWystajace (TPanel $w) $w)
  return [pscustomobject]@{ Widok = $w; Karta = $karta; Pole = $pole; Dodatek = $dodatek; Wystaje = $wy.Count; WystajeOpis = (($wy | Select-Object -First 3) -join " ; ") }
}

function TObejdz { $l = @(); foreach ($w in (TWidoki)) { $l += TZakladka $w }; (TPrzycisk "przeglad").PerformClick(); TPompuj 300; return $l }

function TZrzut([string]$nazwa) {
  if (-not $script:TZrzuty) { return }
  try {
    $script:Okno.Refresh()
    $b = $script:Okno.Bounds
    $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
    $script:Okno.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $b.Width, $b.Height)))
    $bmp.Save((Join-Path $script:TZrzuty ($script:TTryb + "-" + $nazwa + ".png"))); $bmp.Dispose()
  } catch { TNotuj ("ZRZUT " + $nazwa + ": " + $_.Exception.Message) }
}

$script:TWyn = [ordered]@{ Tryb = $script:TTryb }
function TKoniec {
  $script:TZegar.Stop()
  $script:TWyn.Dziennik = $script:TDziennik.ToArray()
  $script:TWyn.Log = $script:TLog.ToArray()
  $script:TWyn.Wywrotki = [string[]]@($script:NadzWywrotki | ForEach-Object { "$_" })
  try { if ($script:Okno) { $script:Okno.Close() } } catch { TNotuj ("zamkniecie okna: " + $_.Exception.Message) }
  # po zamknieciu - zapis rozmiaru (FormClosing) mogl dolozyc wywrotke albo wpis
  $script:TWyn.WywrotkiPoZamknieciu = [string[]]@($script:NadzWywrotki | ForEach-Object { "$_" })
  $script:TWyn.DziennikPoZamknieciu = $script:TDziennik.ToArray()
  try { [System.IO.File]::WriteAllText($script:TWynik, ($script:TWyn | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false))) }
  catch { TNotuj ("ZAPIS WYNIKU: " + $_.Exception.Message) }
  $script:Ikona.Visible = $false
  [System.Windows.Forms.Application]::Exit()
}

Pokaz-Okno
$script:TWyn.Start = TOkno
$script:TWyn.WywrotkiStart = [string[]]@($script:NadzWywrotki | ForEach-Object { "$_" })
TNotuj ("okno {0}, aktywne: {1}" -f $script:Okno.Bounds, ([System.Windows.Forms.Form]::ActiveForm -eq $script:Okno))
$script:TFaza = "otwarcie"; $script:TSpokojOd = $null; $script:TRozgrzewka = $null
$script:TZegar = New-Object System.Windows.Forms.Timer
$script:TZegar.Interval = 200
$script:TZajety = $false
$script:TZegar.Add_Tick({
  if ($script:TZajety) { return }
  $script:TZajety = $true
  try {
    if ($script:TTryb -ne "pelny") { TPompuj 500; TKoniec; return }
    if ($script:TSw.ElapsedMilliseconds -gt 240000) { TNotuj "LIMIT czekania na dane"; TKoniec; return }
    switch ($script:TFaza) {
      "otwarcie" {
        # rozgrzewka: kazda zakladka raz z danymi (jak w test-okno-mruganie.ps1)
        if (-not (TSpokoj)) { $script:TSpokojOd = $null; return }
        $t = $script:TSw.ElapsedMilliseconds
        if ($null -eq $script:TSpokojOd) { $script:TSpokojOd = $t }
        if (($t - $script:TSpokojOd) -lt 1500) { return }
        $script:TSpokojOd = $null
        if ($null -eq $script:TRozgrzewka) { $script:TRozgrzewka = @(TWidoki | Select-Object -Skip 1) + @("przeglad") }
        $nast = $script:TRozgrzewka[0]
        $script:TRozgrzewka = @($script:TRozgrzewka | Select-Object -Skip 1)
        TNotuj "rozgrzewka: $nast"
        (TPrzycisk $nast).PerformClick()
        if ($script:TRozgrzewka.Count -eq 0) { $script:TFaza = "pomiar" }
      }
      "pomiar" {
        if (-not (TSpokoj)) { return }
        $script:TZegar.Stop()
        $script:TWyn.Przed = TObejdz
        $script:TWyn.OknoPrzed = TOkno
        TZrzut "przed"
        # wieksze okno - zegar rozmiaru (200 ms) i ulozenie widocznej zakladki
        $script:Okno.Size = New-Object System.Drawing.Size(($script:Okno.Width + [int]$env:ROZM_PLUS_SZER), ($script:Okno.Height + [int]$env:ROZM_PLUS_WYS))
        TPompuj 1200
        $script:TWyn.OknoPo = TOkno
        TZrzut "po"
        $script:TWyn.Po = TObejdz
        # proba zejscia ponizej najmniejszego rozmiaru
        $script:Okno.Size = New-Object System.Drawing.Size(400, 300)
        TPompuj 1200
        $script:TWyn.OknoMale = TOkno
        $script:TWyn.Male = TObejdz
        # rozmiar do zapamietania przy zamknieciu
        $script:Okno.Size = New-Object System.Drawing.Size(($script:Okno.MinimumSize.Width + 300), ($script:Okno.MinimumSize.Height + 10))
        TPompuj 800
        $script:TWyn.OknoKoniec = TOkno
        TKoniec
      }
    }
  } catch {
    TNotuj ("WYWROTKA SCENARIUSZA: " + $_.Exception.Message + " @ " + $_.InvocationInfo.PositionMessage)
    $script:TWyn.Wywrotka = $_.Exception.Message
    TKoniec
  } finally { $script:TZajety = $false }
})
$script:TZegar.Start()
'@
$plikScen = Join-Path $tmp "scenariusz.ps1"
[System.IO.File]::WriteAllText($plikScen, $scenariusz, $utf8bom)
$bledyScen = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($plikScen, [ref]$null, [ref]$bledyScen)
if (@($bledyScen).Count -gt 0) { Wynik "scenariusz testu sie parsuje" $false (($bledyScen | ForEach-Object { $_.ToString() }) -join " | "); exit 1 }

# ---------------------------------------------------------------- kopia okna
$BEZPIECZNIKI = @'

# ===== BEZPIECZNIKI TESTU ROZMIARU (kopia testowa, nie produkcja) =====
function Ruszaj-Cykl { Write-Host "[TEST] Ruszaj-Cykl ZABLOKOWANY"; return $false }
function Czy-Ruszac-Cykl { return [pscustomobject]@{ Ruszac = $false; Powod = "test rozmiaru" } }
function Odpal-W-Tle([string]$skrypt, [string]$argumenty) { Write-Host "[TEST] Odpal-W-Tle ZABLOKOWANY: $skrypt $argumenty"; return $false }
function Odpal-Skille([string]$argumenty) { Write-Host "[TEST] Odpal-Skille ZABLOKOWANY"; return $true }
function Ruszaj-Skille { return $true }
function Operacja-Na-Skillach { return "test rozmiaru - zablokowane" }
function Aktualizuj { return [pscustomobject]@{ Ok = $false; Proba = $true; Powod = "test rozmiaru - zablokowane"; Pid = $null } }
'@

# Kotwice wspolne dla kazdej kopii (kazda MUSI wystapic dokladnie raz w plikach okna).
function Zamiany-Kopii([string]$stanKopia, [string]$zamek, [string]$plikRozmiaru) {
  return [ordered]@{
    '. (Join-Path $PSScriptRoot "stan-nadzorcy.ps1")' = ". '$stanKopia'"
    '"Local\MegaRuchacz-Nadzorca"' = "`"Local\MegaRuchacz-Nadzorca-$zamek`""
    '$script:Zegar.Start()' = '# dozor wylaczony w tescie rozmiaru'
    '[MegaRuchacz.Pulpit]::SetForegroundWindow($formularz.Handle) | Out-Null' = '# bez kradziezy fokusu w tescie rozmiaru'
    '$SW_POKAZ = 5' = '$SW_POKAZ = 8   # test rozmiaru: SW_SHOWNA, bez aktywacji'
    '$script:Ikona.Visible = $true' = '$script:Ikona.Visible = $false   # test rozmiaru: bez ikony w zasobniku'
    '$f = New-Object System.Windows.Forms.Form' = '$f = New-Object RozmTest.OknoTestowe   # test rozmiaru: bez aktywacji, bez paska zadan'
    '$script:Okno = $f' = ('$f.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual; $f.Location = New-Object System.Drawing.Point(-5000, 0); $f.ShowInTaskbar = $false; $f.KeyPreview = $true; $f.Add_KeyDown({ param($s, $e) $e.SuppressKeyPress = $true; $e.Handled = $true })' + "`r`n  " + '$script:Okno = $f')
    # wlasny plik rozmiaru w katalogu testu zamiast "w trybie probnym nic" - prawdziwego nie dotykamy
    '  if ($script:NadzProba) { return $null }   # tryb probny nic nie zapisuje - i nie czyta rozmiaru prawdziwego okna' = "  return '$plikRozmiaru'   # test rozmiaru"
    'if ($Pokaz) { Pokaz-Okno }' = ". '$plikScen'"
  }
}

# Sklada kopie; $sabotaz = lista @{ Plik; Kotwica; Zamiana } albo $null. Zwraca katalog albo powod porazki.
function Przygotuj-Kopie([string]$nazwa, $sabotaz, [string]$trescPliku) {
  $kat = Join-Path $tmp $nazwa
  New-Item -ItemType Directory -Force -Path $kat | Out-Null
  Copy-Item -LiteralPath (Join-Path $Zasobnik "nadzorca.ps1") -Destination (Join-Path $kat "nadzorca-test.ps1")
  Copy-Item -LiteralPath (Join-Path $Zasobnik "stan-nadzorcy.ps1") -Destination (Join-Path $kat "stan-nadzorcy.ps1")
  Copy-Item -LiteralPath (Join-Path $Zasobnik "nadzorca") -Destination (Join-Path $kat "nadzorca") -Recurse
  $plikRozmiaru = Join-Path $kat "okno-nadzorcy.json"
  if ($null -ne $trescPliku) { [System.IO.File]::WriteAllText($plikRozmiaru, $trescPliku, $utf8) }
  $stanKopia = Join-Path $kat "stan-nadzorcy.ps1"
  [System.IO.File]::WriteAllText($stanKopia, ([System.IO.File]::ReadAllText($stanKopia) + $BEZPIECZNIKI), $utf8bom)
  $pliki = @((Join-Path $kat "nadzorca-test.ps1")) + @(Get-ChildItem -LiteralPath (Join-Path $kat "nadzorca") -Filter *.ps1 | Where-Object { $_.Name -notlike "stan-*" } | ForEach-Object { $_.FullName })
  $tresc = @{}; foreach ($p in $pliki) { $tresc[$p] = [System.IO.File]::ReadAllText($p) }
  $zamiany = Zamiany-Kopii $stanKopia ("TEST-ROZM-" + $nazwa) $plikRozmiaru
  foreach ($k in $zamiany.Keys) {
    $ile = 0; foreach ($p in $pliki) { $ile += ([regex]::Matches($tresc[$p], [regex]::Escape($k))).Count }
    if ($ile -ne 1) { return [pscustomobject]@{ Kat = $null; Powod = "kotwica kopii '$k' wystepuje $ile razy (ma byc 1)"; Plik = $plikRozmiaru } }
    foreach ($p in $pliki) { $tresc[$p] = $tresc[$p].Replace($k, $zamiany[$k]) }
  }
  foreach ($s in @($sabotaz)) {
    if (-not $s) { continue }
    $p = Join-Path $kat ("nadzorca\" + $s.Plik)
    $ile = ([regex]::Matches($tresc[$p], [regex]::Escape($s.Kotwica))).Count
    if ($ile -ne 1) { return [pscustomobject]@{ Kat = $null; Powod = "kotwica sabotazu w $($s.Plik) wystepuje $ile razy (ma byc 1): $($s.Kotwica)"; Plik = $plikRozmiaru } }
    $tresc[$p] = $tresc[$p].Replace($s.Kotwica, $s.Zamiana)
  }
  foreach ($p in $pliki) {
    if ($tresc[$p].Contains('SetForegroundWindow($formularz')) { return [pscustomobject]@{ Kat = $null; Powod = "SetForegroundWindow zostal w $p"; Plik = $plikRozmiaru } }
    [System.IO.File]::WriteAllText($p, $tresc[$p], $utf8bom)
  }
  if (-not ([System.IO.File]::ReadAllText($stanKopia)).Contains("BEZPIECZNIKI TESTU ROZMIARU")) { return [pscustomobject]@{ Kat = $null; Powod = "bezpieczniki nie trafily do kopii stanu"; Plik = $plikRozmiaru } }
  return [pscustomobject]@{ Kat = $kat; Powod = ""; Plik = $plikRozmiaru }
}

function Uruchom-Kopie([string]$kat, [string]$tryb) {
  $wynik = Join-Path $kat "wynik.json"
  $konsola = Join-Path $kat "konsola.txt"
  $pol = "`$env:ROZM_WYNIK = '$wynik'; `$env:ROZM_TRYB = '$tryb'; `$env:ROZM_ZRZUTY = '$zrzuty'; `$env:ROZM_PLUS_SZER = '$PLUS_SZER'; `$env:ROZM_PLUS_WYS = '$PLUS_WYS'; " +
         "& '$(Join-Path $kat 'nadzorca-test.ps1')' -Zrodlo '$Zrodlo' -KatalogDomowy '$Dom' -Pokaz -Proba *> '$konsola'; exit `$LASTEXITCODE"
  $psi = New-Object System.Diagnostics.ProcessStartInfo("powershell.exe", ('-NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($pol))))
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  return [pscustomobject]@{ Kat = $kat; Proces = $p; Pid = $p.Id; Wynik = $wynik; Konsola = $konsola; Start = [datetime]::Now }
}

function Zabij-Drzewo([int]$id) { & taskkill.exe /PID $id /T /F 2>&1 | Out-Null }

function Poczekaj($u) {
  $doKonca = [math]::Max(1, $Limit - ([datetime]::Now - $u.Start).TotalSeconds)
  if (-not $u.Proces.WaitForExit([int]($doKonca * 1000))) {
    Zabij-Drzewo $u.Pid
    return "kopia nie skonczyla w $Limit s - zabita"
  }
  return ""
}

function Wczytaj-Wynik($u) {
  if (-not (Test-Path -LiteralPath $u.Wynik)) {
    $kon = ""; try { $kon = ((Get-Content -LiteralPath $u.Konsola -Encoding Unicode -ErrorAction Stop | Select-Object -Last 8) -join " | ") } catch { $kon = "(brak konsoli: $($_.Exception.Message))" }
    $log = ""; try { $log = ((Get-Content -LiteralPath ($u.Wynik + ".log") -Encoding UTF8 -ErrorAction Stop | Select-Object -Last 5) -join " | ") } catch { $log = "(brak dziennika scenariusza)" }
    return [pscustomobject]@{ Ok = $false; Powod = "kopia nie zapisala wyniku; konsola: $kon; scenariusz: $log"; Dane = $null }
  }
  try { return [pscustomobject]@{ Ok = $true; Powod = ""; Dane = (Get-Content -LiteralPath $u.Wynik -Raw -Encoding UTF8 | ConvertFrom-Json) } }
  catch { return [pscustomobject]@{ Ok = $false; Powod = "wynik nieczytelny: $($_.Exception.Message)"; Dane = $null } }
}

function Bez-Wywrotek($d) {
  $wy = @($d.WywrotkiPoZamknieciu | Where-Object { $_ })
  $sc = @($d.Log | Where-Object { $_ -match 'WYWROTKA SCENARIUSZA|LIMIT|ZAPIS WYNIKU' })
  return [pscustomobject]@{ Ok = (($wy.Count -eq 0) -and ($sc.Count -eq 0) -and -not $d.Wywrotka); Opis = ((@($wy) + @($sc)) -join " || ") }
}
function Wpis($d, [string]$wzor) { return @($d.Dziennik | Where-Object { $_ -like $wzor }) }

# Ocena przebiegu pelnego: lista prob (Klucz, Nazwa, Ok, Opis) - ta sama dla kopii z sabotazem.
function Ocen-Pelny($d, [string]$plikRozmiaru) {
  $o = @()
  function P($klucz, $nazwa, $ok, $opis) { return [pscustomobject]@{ Klucz = $klucz; Nazwa = $nazwa; Ok = [bool]$ok; Opis = $opis } }
  $s = $d.Start
  $o += P "ramka" "okno rozciagalne (Sizable) z przyciskiem maksymalizacji" (($s.Ramka -eq "Sizable") -and $s.MaxPrzycisk) "ramka $($s.Ramka), maksymalizacja $($s.MaxPrzycisk)"
  $zp = Wpis $d "okno: zapamietany rozmiar okna nieczytelny*"
  $o += P "zepsuty-plik" "zepsuty plik rozmiaru: rozmiar domyslny (= MinimumSize), wpis w dzienniku, bez wyjatku" (($s.W -eq $s.MinW) -and ($s.H -eq $s.MinH) -and ($zp.Count -eq 1) -and (@($d.WywrotkiStart | Where-Object { $_ }).Count -eq 0)) "okno $($s.W) x $($s.H), minimum $($s.MinW) x $($s.MinH); dziennik: $($zp -join ' | ')"
  $przed = @($d.Przed); $po = @($d.Po); $male = @($d.Male)
  $zest = ($przed.Count -ge 3) -and ($po.Count -eq $przed.Count) -and ($male.Count -eq $przed.Count) -and $d.OknoKoniec
  $o += P "zestaw" "scenariusz doszedl do konca (pomiar przed, po powiekszeniu, po zmniejszeniu, zamkniecie)" $zest "zakladek: $($przed.Count)/$($po.Count)/$($male.Count)"
  if (-not $zest) { $o += P "wywrotki" "bez wywrotek" (Bez-Wywrotek $d).Ok (Bez-Wywrotek $d).Opis; return $o }
  $op = $d.OknoPrzed; $oo = $d.OknoPo
  $dk = $oo.KW - $op.KW
  $rosnie = @(); $opisy = @()
  for ($i = 0; $i -lt $przed.Count; $i++) {
    $a = $przed[$i]; $b = $po[$i]
    $dKarta = $b.Karta - $a.Karta; $dPole = $b.Pole - $a.Pole; $dDod = $b.Dodatek - $a.Dodatek
    switch ($a.Widok) {
      # pole tresci: co najmniej o tyle (wyzsze okno moze dodatkowo zdjac pionowy suwak)
      "przeglad"  { $ok = ($dKarta -eq $dk) -and ($dPole -ge $dk) -and ($dDod -ge $dk) }
      "szczegoly" { $ok = ($dKarta -eq $dk) -and ($dPole -ge $dk) -and ($b.Dodatek -eq $a.Dodatek) }
      "warstwy"   { $ok = ($dKarta -ge $PROG_POLOWY) -and ($dPole -ge $PROG_POLOWY) -and ($dDod -eq $dKarta) }
      "skille"    { $ok = ($dKarta -ge $PROG_POLOWY) -and ($dPole -ge $PROG_POLOWY) -and ($dDod -ge $PROG_POLOWY) }
    }
    if (-not $ok) { $rosnie += $a.Widok }
    $opisy += "$($a.Widok): karta $($a.Karta)->$($b.Karta), pole $($a.Pole)->$($b.Pole), dodatek $($a.Dodatek)->$($b.Dodatek)"
  }
  $o += P "okno-uroslo" "kontrola: wnetrze okna uroslo o $PLUS_SZER px" ($dk -eq $PLUS_SZER) "wnetrze $($op.KW) -> $($oo.KW)"
  $o += P "rosnie" "po powiekszeniu karty, pola tresci, listy i kolumny urosly we wszystkich zakladkach" (($rosnie.Count -eq 0) -and ($dk -eq $PLUS_SZER)) ((($opisy) -join "; ") + $(if ($rosnie.Count) { " || NIE UROSLO: " + ($rosnie -join ", ") }))
  $o += P "naglowek-pasek" "podtytul i opisy pod przyciskami szersze, przelacznik zakladek dalej przy prawej krawedzi" ((($oo.Podtytul - $op.Podtytul) -eq $dk) -and ($oo.OpisPaska -gt $op.OpisPaska) -and ($oo.PrzelOdstep -eq $op.PrzelOdstep)) "podtytul $($op.Podtytul)->$($oo.Podtytul), opis paska $($op.OpisPaska)->$($oo.OpisPaska), odstep przelacznika od prawej $($op.PrzelOdstep)->$($oo.PrzelOdstep)"
  $wys = @($po | Where-Object { $_.Wystaje -gt 0 }) + @($przed | Where-Object { $_.Wystaje -gt 0 })
  $o += P "nic-nie-wystaje" "przed i po powiekszeniu zadna kontrolka nie wystaje poza swoj panel (tekst uciety po cichu)" ($wys.Count -eq 0) ((($wys | ForEach-Object { "$($_.Widok): $($_.Wystaje) ($($_.WystajeOpis))" }) -join "; "))
  $om = $d.OknoMale
  $wrocilo = @(); for ($i = 0; $i -lt $przed.Count; $i++) { if (($male[$i].Karta -ne $przed[$i].Karta) -or ($male[$i].Pole -ne $przed[$i].Pole)) { $wrocilo += "$($przed[$i].Widok) $($przed[$i].Karta)/$($przed[$i].Pole) -> $($male[$i].Karta)/$($male[$i].Pole)" } }
  $o += P "minimum" "proba zejscia do 400 x 300: okno zostaje na MinimumSize, tresc wraca do szerokosci domyslnej" (($om.W -ge $om.MinW) -and ($om.H -ge $om.MinH) -and ($om.W -eq $op.W) -and ($om.H -eq $op.H) -and ($wrocilo.Count -eq 0)) "okno $($om.W) x $($om.H), minimum $($om.MinW) x $($om.MinH), przed powiekszeniem $($op.W) x $($op.H)$(if ($wrocilo.Count) { '; inne niz przed: ' + ($wrocilo -join ', ') })"
  # zapis przy zamknieciu
  $ok = $false; $opis = ""
  try {
    $j = [System.IO.File]::ReadAllText($plikRozmiaru) | ConvertFrom-Json
    $k = $d.OknoKoniec
    $ok = ([int]$j.szer -eq $k.W) -and ([int]$j.wys -eq $k.H) -and ($j.max -eq $false)
    $opis = "plik: $($j.szer) x $($j.wys), max $($j.max); okno przy zamknieciu $($k.W) x $($k.H)"
  } catch { $opis = "pliku nie da sie przeczytac: $($_.Exception.Message)" }
  $o += P "zapis" "zamkniecie zapisuje rozmiar i maksymalizacje do pliku" $ok $opis
  $bw = Bez-Wywrotek $d
  $o += P "wywrotki" "bez wywrotek nadzorcy i scenariusza (takze przy zapisie przy zamknieciu)" $bw.Ok $bw.Opis
  return $o
}

$uruchomione = @()
Add-Type -AssemblyName System.Windows.Forms
$obszar = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$ZAP_SZER = 1500

# ---------------------------------------------------------------- przebiegi rownolegle
$PRZEBIEGI = [ordered]@{
  "pelny"        = @{ Tryb = "pelny"; Plik = "{ to nie jest json"; Sabotaz = $null }
  "zapamietany"  = @{ Tryb = "szybki"; Plik = ('{"x":' + ($obszar.Left + 10) + ',"y":' + ($obszar.Top + 10) + ',"szer":' + $ZAP_SZER + ',"wys":300,"max":false,"zapisano":"2026-10-14T10:00:00"}'); Sabotaz = $null }
  "poza-ekranem" = @{ Tryb = "szybki"; Plik = '{"x":-20000,"y":-20000,"szer":1300,"wys":900,"max":false}'; Sabotaz = $null }
  "zle-pola"     = @{ Tryb = "szybki"; Plik = '{"x":"lewo","y":10,"szer":1300,"wys":900,"max":"tak"}'; Sabotaz = $null }
}
# Sabotaze (proby negatywne testu): kazdy MUSI zlamac swoja probe.
$SABOTAZE = @(
  @{ Nazwa = "tresc nie dopasowuje sie do rozmiaru (Dopasuj-Do-Rozmiaru wylaczone)"; Proba = "rosnie"
     Zmiany = @(@{ Plik = "okno.ps1"; Kotwica = 'try { Dopasuj-Do-Rozmiaru } catch'; Zamiana = 'try { <# SABOTAZ #> } catch' }) },
  @{ Nazwa = "okno bez MinimumSize"; Proba = "minimum"
     Zmiany = @(@{ Plik = "okno.ps1"; Kotwica = '$f.MinimumSize = $f.Size'; Zamiana = '<# SABOTAZ #>' }) }
)
if (-not $BezSabotazy) {
  $i = 0
  foreach ($s in $SABOTAZE) { $i++; $PRZEBIEGI["sabotaz$i"] = @{ Tryb = "pelny"; Plik = "{ to nie jest json"; Sabotaz = $s } }
}

Write-Host "Kopie okna ($($PRZEBIEGI.Count) rownolegle, dane z $Dom, limit $Limit s) - ok. 2-3 min..."
$biegi = [ordered]@{}
foreach ($n in $PRZEBIEGI.Keys) {
  $pr = $PRZEBIEGI[$n]
  $k = Przygotuj-Kopie $n $(if ($pr.Sabotaz) { $pr.Sabotaz.Zmiany } else { $null }) $pr.Plik
  if (-not $k.Kat) { Wynik "kopia okna '$n'" $false $k.Powod; continue }
  $u = Uruchom-Kopie $k.Kat $pr.Tryb
  $uruchomione += $u
  $biegi[$n] = [pscustomobject]@{ U = $u; Plik = $k.Plik; Pr = $pr }
}

foreach ($n in $biegi.Keys) {
  $b = $biegi[$n]
  $zw = Poczekaj $b.U
  $w = Wczytaj-Wynik $b.U
  if ($zw -or -not $w.Ok) { Wynik "kopia okna '$n' przeszla scenariusz" $false "$zw $($w.Powod)"; continue }
  $d = $w.Dane
  if ($b.Pr.Sabotaz) {
    $s = $b.Pr.Sabotaz
    $oc = @(Ocen-Pelny $d $b.Plik)
    $wl = @($oc | Where-Object { $_.Klucz -eq $s.Proba })
    $kontrola = @($oc | Where-Object { $_.Klucz -in @("zestaw") -and -not $_.Ok })
    $ok = ($wl.Count -eq 1) -and (-not $wl[0].Ok) -and ($kontrola.Count -eq 0)
    $opis = "z sabotazem: $(if ($wl.Count) { $wl[0].Opis } else { 'brak proby' })"
    if ($kontrola.Count) { $opis += " || przebieg niepelny: " + (($kontrola | ForEach-Object { $_.Opis }) -join "; ") }
    Wynik "sabotaz '$($s.Nazwa)' wylapany przez '$($s.Proba)'" $ok $opis
    continue
  }
  $s = $d.Start
  $bw = Bez-Wywrotek $d
  switch ($n) {
    "pelny" { foreach ($x in (Ocen-Pelny $d $b.Plik)) { Wynik $x.Nazwa $x.Ok $x.Opis } }
    "zapamietany" {
      $obce = @(Wpis $d "okno: zapamietan*")
      Wynik "zapamietany rozmiar: okno w nim staje, za niska wysokosc podniesiona do minimum" (($s.W -eq $ZAP_SZER) -and ($s.H -eq $s.MinH) -and ($s.Stan -eq "Normal") -and ($obce.Count -eq 0)) "okno $($s.W) x $($s.H) (zapisane $ZAP_SZER x 300, minimum $($s.MinW) x $($s.MinH)), stan $($s.Stan); dziennik: $($obce -join ' | ')"
      Wynik "zapamietany rozmiar: tresc zlozona od razu w jego szerokosci" (($s.SzerOkna -eq $s.KW) -and ($s.KW -gt $s.SzerDomyslna) -and ($s.Podtytul -eq ($s.SzerOkna - 56)) -and ($s.RootMin -eq $s.SzerTresc)) "wnetrze $($s.KW) (domyslne $($s.SzerDomyslna)), SzerOkna $($s.SzerOkna), podtytul $($s.Podtytul), karta Przegladu min $($s.RootMin) / SzerTresc $($s.SzerTresc)"
      Wynik "zapamietany rozmiar: bez wywrotek" $bw.Ok $bw.Opis
    }
    "poza-ekranem" {
      $wp = @(Wpis $d "okno: zapamietane polozenie okna*poza ekranami*")
      Wynik "proba negatywna: polozenie poza ekranami -> rozmiar domyslny i wpis w dzienniku" (($s.W -eq $s.MinW) -and ($s.H -eq $s.MinH) -and ($s.SzerOkna -eq $s.SzerDomyslna) -and ($wp.Count -eq 1) -and $bw.Ok) "okno $($s.W) x $($s.H), minimum $($s.MinW) x $($s.MinH); dziennik: $($wp -join ' | ')$(if (-not $bw.Ok) { '; WYWROTKI: ' + $bw.Opis })"
    }
    "zle-pola" {
      $wp = @(Wpis $d "okno: zapamietany rozmiar okna nieczytelny*nie jest liczba*")
      Wynik "proba negatywna: pola nie-liczby -> rozmiar domyslny, wpis w dzienniku, bez wyjatku" (($s.W -eq $s.MinW) -and ($s.H -eq $s.MinH) -and ($wp.Count -eq 1) -and $bw.Ok) "okno $($s.W) x $($s.H), minimum $($s.MinW) x $($s.MinH); dziennik: $($wp -join ' | ')$(if (-not $bw.Ok) { '; WYWROTKI: ' + $bw.Opis })"
    }
  }
}

# ---------------------------------------------------------------- sprzatanie
Start-Sleep -Milliseconds 500
$pidy = @($uruchomione | ForEach-Object { $_.Pid })
$zostaly = @(Get-CimInstance Win32_Process | Where-Object { ($pidy -contains $_.ProcessId) -or ($pidy -contains $_.ParentProcessId) -or ($_.CommandLine -and $_.CommandLine.Contains($tmp)) })
foreach ($z in $zostaly) { Zabij-Drzewo $z.ProcessId }
Wynik "po tescie zadna kopia okna nie zostala w procesach" ($zostaly.Count -eq 0) ("zostalo: " + (($zostaly | ForEach-Object { "$($_.ProcessId) $($_.Name)" }) -join ", "))

Write-Host ""
Write-Host "Zrzuty (DrawToBitmap, przed i po powiekszeniu): $zrzuty"
Write-Host "Wynik: $(@($script:wyniki | Where-Object { $_.OK }).Count) z $($script:wyniki.Count) TAK. Pliki robocze: $tmp"
if (@($script:wyniki | Where-Object { -not $_.OK }).Count -gt 0) { exit 1 }
exit 0
