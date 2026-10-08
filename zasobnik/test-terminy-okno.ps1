# Sprawdzenie okna przypomnien (zasobnik\terminy.ps1, 2026-10-08): napisy w oknie to pola
# tekstowe tylko do odczytu, ktore da sie zaznaczyc i skopiowac, przycisk "Kopiuj" przy kazdym
# przypomnieniu, dluga tresc bez uciecia, porazka schowka widoczna na przycisku i w dzienniku.
#   powershell -ExecutionPolicy Bypass -File zasobnik\test-terminy-okno.ps1 [-Zrodlo <repo>] [-Zrzuty <kat>]
# Wszystko na kopii terminy.ps1, sztucznym katalogu domowym i testowym pliku przypomnien (tylko
# tryb "przypomnij" - nic sie samo nie uruchamia). Kopia: okno poza ekranem (-5000, 0), bez paska
# zadan, bez aktywacji (nie zabiera klawiatury), bez TopMost, klawiatura wylaczona, wlasne zamki,
# zegar, ktory po pomiarach zamyka okno. Proces kopii bez okna konsoli, ubijany po 120 s.
# Sabotaze: kopie z Label zamiast pola, zepsutym "Kopiuj", stala wysokoscia pola, cichym bledem
# schowka i trzema zepsutymi Do-Schowka - kazdy MUSI zostac zlapany. Zawartosc schowka uzytkownika
# zachowana i przywrocona.
# Schowek czytaja po kazdej zmianie inne programy (zmierzone 2026-10-08: Remotly, historia schowka,
# Eksplorator - kazdy trzyma go do 70 ms), dlatego test przed kopiowaniem czeka, az ucichna, a odczyt
# ponawia do $MS_ODCZYTU_SCHOWKA (GetText przy zajetym schowku po cichu zwraca ""). Zajety schowek
# robi tez celowo osobny proces (trzymacz): krotko - Kopiuj ma poczekac i skopiowac, dlugo - porazka
# widoczna na przycisku i w dzienniku.
param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [string]$Zrzuty = ""
)
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { Write-Warning "konsola bez UTF-8: $($_.Exception.Message)" }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("test-terminy-okno-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
if (-not $Zrzuty) { $Zrzuty = Join-Path $tmp "zrzuty" }
New-Item -ItemType Directory -Force -Path $Zrzuty | Out-Null
$dom = Join-Path $tmp "dom"
$katMr = Join-Path $dom ".claude\mr"
New-Item -ItemType Directory -Force -Path $katMr | Out-Null
$plikP = Join-Path $katMr "przypomnienia.md"
$dziennik = Join-Path $katMr "przypomnienia.log"
$plikOkna = Join-Path $katMr "przypomnienia-okno.txt"
$oryginal = Join-Path $Zrodlo "zasobnik\terminy.ps1"
$BezBom = New-Object System.Text.UTF8Encoding($false)
$ZBom = New-Object System.Text.UTF8Encoding($true)

$script:wyniki = @()
function Wynik($nazwa, $ok, $opis) {
  $script:wyniki += [pscustomobject]@{ Test = $nazwa; OK = [bool]$ok; Opis = $opis }
  $z = "NIE"; if ($ok) { $z = "TAK" }
  Write-Host ("[{0}] {1} - {2}" -f $z, $nazwa, $opis)
}

# ---------------------------------------------------------------- dane testowe
$dzis = (Get-Date).ToString("yyyy-MM-dd")
$projekt = $tmp
$tresc1 = "Sprawdzić, czy oferty na Amazon PL mają ten sam SKU i ASIN co w FBA."
$spr1 = "Seller Central → Inventory, filtr po SKU"
$tresc2 = ("Długa treść przypomnienia do sprawdzenia zawijania: zestaw SET3-Citrus[020312] ma olejki 02, 03 i 12, " +
           "trzeba porównać ceny na DE, FR i UK, policzyć dopłaty FBA za EFN i Remote Fulfilment, " +
           "sprawdzić zdjęcie główne wariantu 40 g mentolu i 30 szt. kadzidełek backflow, " +
           "a potem przejrzeć tytuły pod frazy z zakupami z ostatnich 14 miesięcy (Search Query Performance), " +
           "bez powtórzeń i w naturalnym niemieckim, z wolnym miejscem na konkretny zapach ze składu zestawu. " +
           "Na koniec zapisać wyniki w pliku i dać znać, co się zmieniło, a czego nie dało się sprawdzić. " +
           "Zażółć gęślą jaźń - polskie znaki też muszą przejść przez schowek bez zmian.")
$spr2 = "porównanie cen w pliku dopłat, a tytuły w Search Query Performance"
$tresc3 = "Sprawa w toku od kilku dni - powinna mieć czerwoną uwagę pod treścią."
$linie = @(
  "# Przypomnienia - plik testowy test-terminy-okno.ps1",
  "",
  "- [ ] #1 $dzis | $projekt | $tresc1 | sprawdź: $spr1 | tryb: przypomnij | dodane $dzis",
  "- [ ] #2 $dzis | $projekt | $tresc2 | sprawdź: $spr2 | tryb: przypomnij | dodane $dzis",
  "- [~] #3 2026-10-01 | $projekt | $tresc3 | tryb: przypomnij | dodane 2026-09-30 | w toku 2026-10-01")
$trescPola = @{ 1 = "$tresc1`r`nJak sprawdzić: $spr1"; 2 = "$tresc2`r`nJak sprawdzić: $spr2"; 3 = $tresc3 }
$CZERWONY = [System.Drawing.Color]::FromArgb(170, 40, 20).ToArgb()
$CZARNY = [System.Drawing.SystemColors]::ControlText.ToArgb()

# Trzymacz: osobny proces, ktory otwiera schowek i trzyma go przez -Ms, jak program, ktory akurat
# z niego czyta. Krotko: dluzej niz czeka Clipboard.SetText (10 x 100 ms - stara wersja Do-Schowka
# tu pada), krocej niz czeka Do-Schowka ($PROB_SCHOWKA x $MS_MIEDZY_PROBAMI_SCHOWKA = 2,5 s).
# Dlugo: dluzej niz czeka Do-Schowka - ma byc widoczna porazka.
$MS_TRZYMANIA_KROTKO = 1800
$MS_TRZYMANIA_DLUGO = 4000
$trzymacz = Join-Path $tmp "trzymacz-schowka.ps1"
[System.IO.File]::WriteAllText($trzymacz, @'
param([int]$Ms, [string]$Znak)
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class TrzymaczSchowka {
  [DllImport("user32.dll")] public static extern bool OpenClipboard(IntPtr h);
  [DllImport("user32.dll")] public static extern bool CloseClipboard();
}
"@
# Wlasne okno (tylko do komunikatow, niewidoczne): schowek otwarty z NULL zamyka kazdy inny
# program, ktory tez otworzy go z NULL i zamknie (zmierzone - trzymanie znikalo po 0 ms).
Add-Type -AssemblyName System.Windows.Forms
$okno = New-Object System.Windows.Forms.NativeWindow
$cp = New-Object System.Windows.Forms.CreateParams
$cp.Parent = [IntPtr](-3)
$okno.CreateHandle($cp)
$t0 = [datetime]::Now
while (-not [TrzymaczSchowka]::OpenClipboard($okno.Handle)) {
  if (([datetime]::Now - $t0).TotalSeconds -gt 10) { [System.IO.File]::WriteAllText($Znak, "nie otworzylem schowka w 10 s"); exit 1 }
  Start-Sleep -Milliseconds 20
}
try { [System.IO.File]::WriteAllText($Znak, "trzymam"); Start-Sleep -Milliseconds $Ms } finally { [void][TrzymaczSchowka]::CloseClipboard() }
exit 0
'@, $BezBom)

# ---------------------------------------------------------------- kod wstrzykiwany do kopii
$klasaOkna = @'
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
public class OknoTestowePrzypomnien : System.Windows.Forms.Form {
  public static string Opis { get { return "okno testowe bez aktywacji"; } }
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override System.Windows.Forms.CreateParams CreateParams {
    get { System.Windows.Forms.CreateParams cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x00000080; return cp; }
  }
}
"@
  $f = New-Object OknoTestowePrzypomnien
'@
# Zamiast $f.Activate(): pomiary i kopiowanie z zegara, potem zamkniecie okna.
$hak = @'
$f.KeyPreview = $true
  $f.Add_KeyDown({ param($n, $e) $e.Handled = $true; $e.SuppressKeyPress = $true })
  function T-Wszystkie($c) { foreach ($d in $c.Controls) { $d; T-Wszystkie $d } }
  function T-Pompuj([int]$ms) { $do = [datetime]::Now.AddMilliseconds($ms); while ([datetime]::Now -lt $do) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 } }
  # Odczyt schowka ponawiany, az pokaze oczekiwany tekst albo minie $MS_ODCZYTU_SCHOWKA - wtedy
  # zwraca ostatni odczyt i ocenia go rodzic (ponawianie nie zmienia tresci, tylko omija chwile,
  # gdy schowek trzyma inny program).
  $MS_ODCZYTU_SCHOWKA = 2500
  function T-Schowek([string]$ocz) {
    $do = [datetime]::Now.AddMilliseconds($MS_ODCZYTU_SCHOWKA); $ost = ""
    do {
      T-Pompuj 40
      try { $ost = [System.Windows.Forms.Clipboard]::GetText() } catch { $ost = "BLAD ODCZYTU SCHOWKA: $($_.Exception.Message)" }
      if ($ost -ceq $ocz) { return $ost }
    } while ([datetime]::Now -lt $do)
    return $ost
  }
  # Zapis znacznika zamiast Clear (po nim widac, ze kopiowanie nic nie dalo) i odczekanie, az inne
  # programy skoncza czytac zmiane - kopiowanie przez pole (WM_COPY) przy zajetym schowku po cichu
  # nic nie robi, tak samo w kazdym programie Windows.
  function T-Czysc {
    $script:TestZnaczniki++
    for ($i = 0; $i -lt 30; $i++) {
      try { [System.Windows.Forms.Clipboard]::SetDataObject("TEST-SCHOWEK-PUSTY-$($script:TestZnaczniki)", $true, 0, 0); T-Pompuj 150; return } catch { T-Pompuj 100 }
    }
    $script:TestRaport.Uwagi += "nie zapisalem znacznika do schowka w 30 probach"
  }
  # Czy schowek jest teraz zajety: proba zapisu bez czekania (przy zajetym rzuca od razu).
  function T-Zajety { try { [System.Windows.Forms.Clipboard]::SetDataObject("TEST-SONDA", $true, 0, 0); return $false } catch { return $true } }
  # Osobny proces trzyma schowek otwarty przez $ms; zwraca go, gdy juz trzyma.
  function T-Trzymaj([int]$ms) {
    $znak = Join-Path '__TMP__' ("trzymacz-" + [guid]::NewGuid().ToString("N").Substring(0, 8) + ".txt")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"__TRZYMACZ__`" -Ms $ms -Znak `"$znak`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $do = [datetime]::Now.AddSeconds(20)
    $stan = ""
    while ((-not $stan) -and ([datetime]::Now -lt $do)) {
      if (Test-Path -LiteralPath $znak) { try { $stan = [System.IO.File]::ReadAllText($znak) } catch { $stan = "" } }
      elseif ($p.HasExited) { $stan = "proces skonczyl bez znaku, kod $($p.ExitCode)" }
      if (-not $stan) { T-Pompuj 20 }
    }
    if (-not $stan) { $stan = "brak znaku w 20 s" }
    if ($stan -ne "trzymam") { $script:TestRaport.Uwagi += "trzymacz schowka nie trzyma ($stan)"; try { $p.Kill() } catch { $script:TestRaport.Uwagi += "trzymacz: $($_.Exception.Message)" } }
    return $p
  }
  function T-Pusc($p) {
    $do = [datetime]::Now.AddSeconds(15)
    while ((-not $p.HasExited) -and ([datetime]::Now -lt $do)) { T-Pompuj 50 }
    if (-not $p.HasExited) { $script:TestRaport.Uwagi += "trzymacz nie skonczyl sam"; try { $p.Kill() } catch { $script:TestRaport.Uwagi += "trzymacz: $($_.Exception.Message)" } }
  }
  function T-Sprawdz {
    $r = $script:TestRaport
    foreach ($c in @(T-Wszystkie $script:Okno)) {
      $k = [ordered]@{ Typ = $c.GetType().Name; Tekst = "$($c.Text)"; Widoczny = $c.Visible; Wys = $c.Height; Szer = $c.Width; Prawa = $c.Right
                       SzerRodzica = $c.Parent.ClientSize.Width; Kolor = $c.ForeColor.ToArgb(); Tlo = $c.BackColor.ToArgb(); TloRodzica = $c.Parent.BackColor.ToArgb() }
      if ($c -is [System.Windows.Forms.TextBox]) {
        $k.ReadOnly = $c.ReadOnly; $k.Multiline = $c.Multiline; $k.Ramka = "$($c.BorderStyle)"; $k.Paski = "$($c.ScrollBars)"
        $k.TabStop = $c.TabStop; $k.Wlaczony = $c.Enabled; $k.WysWnetrza = $c.ClientSize.Height; $k.WysCzcionki = $c.Font.Height
        $ost = [Math]::Max(0, $c.TextLength - 1)
        $k.PierwszaY = $c.GetPositionFromCharIndex(0).Y; $k.OstatniaY = $c.GetPositionFromCharIndex($ost).Y; $k.Linii = $c.GetLineFromCharIndex($ost) + 1
      }
      $r.Kontrolki += [pscustomobject]$k
    }
    # zaznaczenie calego pola i Kopiuj (to samo, co zaznaczenie mysza + Ctrl+C / menu Kopiuj)
    $pola = @(T-Wszystkie $script:Okno | Where-Object { $_ -is [System.Windows.Forms.TextBox] })
    foreach ($c in $pola) {
      T-Czysc
      $c.Select(0, $c.TextLength); $c.Copy()
      $r.Zaznaczenia += [pscustomobject]@{ Tekst = $c.Text; Zaznaczone = $c.SelectedText; Schowek = (T-Schowek $c.Text) }
    }
    $dl = $pola | Sort-Object TextLength -Descending | Select-Object -First 1
    if ($dl -and $dl.TextLength -gt 60) {
      T-Czysc
      $dl.Select(10, 45); $dl.Copy()
      $r.Fragment = [pscustomobject]@{ Oczekiwany = $dl.Text.Substring(10, 45); Schowek = (T-Schowek $dl.Text.Substring(10, 45)) }
    }
    # przyciski Kopiuj
    $kop = @(T-Wszystkie $script:Okno | Where-Object { ($_ -is [System.Windows.Forms.Button]) -and ("$($_.AccessibleName)" -like "Kopiuj #*") })
    $wpisy = @()
    foreach ($b in $kop) {
      T-Czysc
      $b.PerformClick(); $po = $b.Text
      $wpisy += [pscustomobject]@{ Nazwa = $b.AccessibleName; Schowek = (T-Schowek $b.Tag.Tekst); NapisPo = $po; NapisPozniej = ""; Szer = $b.Width; Przycisk = $b }
    }
    T-Pompuj ($MS_NAPISU_SKOPIOWANO + 700)
    foreach ($w in $wpisy) { $w.NapisPozniej = $w.Przycisk.Text; $w.Szer = "$($w.Szer)/$($w.Przycisk.Width)"; $w.PSObject.Properties.Remove("Przycisk"); $r.Kopiuj += $w }
    # schowek zajety przez inny program (prawdziwy, trzymany przez osobny proces): krotko -
    # Kopiuj czeka i kopiuje; dlugo - "Nie skopiowano" zostaje i jest wpis w dzienniku
    if (($kop.Count -gt 0) -and __ZAJETY__) {
      $b = $kop[0]
      foreach ($sc in @(@{ Pole = "KopiujZajety"; Ms = __MS_KROTKO__ }, @{ Pole = "KopiujBlad"; Ms = __MS_DLUGO__ })) {
        T-Czysc
        $tr = T-Trzymaj $sc.Ms
        $zajPrzed = T-Zajety
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $b.PerformClick()
        $czas = $sw.ElapsedMilliseconds
        $po = $b.Text
        $zajPo = $null; $sch = $null
        if ($sc.Pole -eq "KopiujBlad") { $zajPo = T-Zajety } else { $sch = T-Schowek $b.Tag.Tekst }
        T-Pusc $tr
        T-Pompuj ($MS_NAPISU_SKOPIOWANO + 700)
        $r.($sc.Pole) = [pscustomobject]@{ Nazwa = $b.AccessibleName; TrzymanoMs = $sc.Ms; ZajetyPrzed = $zajPrzed; ZajetyPo = $zajPo
                                           CzasKlikniecia = $czas; NapisPo = $po; NapisPozniej = $b.Text; Schowek = $sch }
      }
    }
    $bmp = New-Object System.Drawing.Bitmap($script:Okno.Width, $script:Okno.Height)
    $script:Okno.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $script:Okno.Width, $script:Okno.Height)))
    $bmp.Save('__ZRZUT__'); $bmp.Dispose()
  }
  $script:TestRaport = [pscustomobject]@{ Kontrolki = @(); Zaznaczenia = @(); Fragment = $null; Kopiuj = @(); KopiujZajety = $null; KopiujBlad = $null
                                          Wywrotka = ""; Uwagi = @(); Watek = [System.Threading.Thread]::CurrentThread.ApartmentState.ToString()
                                          Okno = ""; Ekran = "" }
  $script:TestZegar = New-Object System.Windows.Forms.Timer
  $script:TestZegar.Interval = 300
  $script:TestZegar.Add_Tick({
    $script:TestZegar.Stop()
    try {
      $script:TestRaport.Okno = "$($script:Okno.Bounds)"; $script:TestRaport.Ekran = "$([System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea)"
      T-Sprawdz
    } catch { $script:TestRaport.Wywrotka = "$($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)" }
    [System.IO.File]::WriteAllText('__RAPORT__', ($script:TestRaport | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
    $script:Okno.Close()
  })
  $f.Add_Shown({ $script:TestZegar.Start() })
'@
# Zamiast ShowDialog (modalne okno aktywuje sie): Show bez aktywacji i petla komunikatow do
# zamkniecia, z bezpiecznikiem - okno, ktore samo sie nie zamknie, zamykamy po 90 s.
$petla = @'
$f.Show()
  $t0 = [datetime]::Now
  while ($f.Visible -and (([datetime]::Now - $t0).TotalSeconds -lt 90)) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 }
  if ($f.Visible) { [System.IO.File]::WriteAllText('__RAPORT__.zwis', "okno nie zamknelo sie samo w 90 s"); $f.Close() }
'@

$zrodloSkryptu = [System.IO.File]::ReadAllText($oryginal, [System.Text.Encoding]::UTF8)
function Ile([string]$w, [string]$co) { return ([regex]::Matches($w, [regex]::Escape($co))).Count }
# Kopia z podmianami; kazda kotwica musi wystapic dokladnie raz - inaczej porazka przygotowania,
# a nie test, ktory po cichu sprawdza nie to okno.
# -Zajety:$false pomija scenariusze z trzymanym schowkiem (ok. 12 s) w sabotazach, ktore ich nie oceniaja.
function Kopia([string]$wariant, [hashtable[]]$podmiany, [bool]$Zajety = $true) {
  $raport = Join-Path $tmp "raport-$wariant.json"
  $zrzut = Join-Path $Zrzuty "terminy-okno-$wariant.png"
  $wsp = @(
    @{ K = '$f = New-Object System.Windows.Forms.Form'; Z = $klasaOkna.TrimStart() },
    @{ K = '$f.TopMost = $true'; Z = '$f.TopMost = $false' },
    @{ K = '$f.ShowInTaskbar = $true'; Z = '$f.ShowInTaskbar = $false' },
    @{ K = '$f.StartPosition = "CenterScreen"'; Z = '$f.StartPosition = "Manual"; $f.Location = New-Object System.Drawing.Point(-5000, 0)' },
    @{ K = '$f.Add_Shown({ $f.Activate() })'; Z = $hak.Replace('__RAPORT__', $raport).Replace('__ZRZUT__', $zrzut).Replace('__TMP__', $tmp).Replace('__TRZYMACZ__', $trzymacz).Replace('__MS_KROTKO__', "$MS_TRZYMANIA_KROTKO").Replace('__MS_DLUGO__', "$MS_TRZYMANIA_DLUGO").Replace('__ZAJETY__', ('$' + "$Zajety")) },
    @{ K = '[void]$f.ShowDialog()'; Z = $petla.Replace('__RAPORT__', $raport) },
    @{ K = '"Local\MegaRuchacz-Terminy-Start"'; Z = '"Local\MegaRuchacz-Terminy-Start-TEST-OKNA"' },
    @{ K = '"Local\MegaRuchacz-Terminy-Okno"'; Z = '"Local\MegaRuchacz-Terminy-Okno-TEST-OKNA"' })
  $kod = $zrodloSkryptu
  foreach ($p in @($wsp) + @($podmiany)) {
    $n = Ile $kod $p.K
    if ($n -ne 1) { throw "kopia '$wariant': kotwica wystepuje $n razy (ma byc 1): $($p.K)" }
    $kod = $kod.Replace($p.K, $p.Z)
  }
  foreach ($zakaz in @('.Activate()', 'SetForegroundWindow', 'ShowDialog', '$f.TopMost = $true', '$f.ShowInTaskbar = $true')) {
    if ($kod.Contains($zakaz)) { throw "kopia '$wariant' nadal zawiera '$zakaz' - okno mogloby wyskoczyc na ekran" }
  }
  $plik = Join-Path $tmp "terminy-$wariant.ps1"
  [System.IO.File]::WriteAllText($plik, $kod, $ZBom)
  return [pscustomobject]@{ Plik = $plik; Raport = $raport; Zrzut = $zrzut }
}

# Kopia jako osobny proces: bez okna konsoli, wyjscie przechwycone, ubijana po 120 s.
function Uruchom($kopia) {
  [System.IO.File]::WriteAllLines($plikP, [string[]]$linie, $BezBom)
  foreach ($x in @($dziennik, $plikOkna, $kopia.Raport, "$($kopia.Raport).zwis")) { if (Test-Path -LiteralPath $x) { Remove-Item -LiteralPath $x -Force } }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$($kopia.Plik)`" -Zrodlo `"$Zrodlo`" -KatalogDomowy `"$dom`" -Plik `"$plikP`" -Dzis $dzis"
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  $p = [System.Diagnostics.Process]::Start($psi)
  $wy = $p.StandardOutput.ReadToEndAsync(); $bl = $p.StandardError.ReadToEndAsync()
  $zabity = $false
  if (-not $p.WaitForExit(120000)) { $p.Kill(); $p.WaitForExit(5000) | Out-Null; $zabity = $true }
  $r = [pscustomobject]@{ Kod = $p.ExitCode; Zabity = $zabity; Wyjscie = "$($wy.Result)$($bl.Result)".Trim(); Raport = $null; Dziennik = "" }
  if (Test-Path -LiteralPath $kopia.Raport) { $r.Raport = [System.IO.File]::ReadAllText($kopia.Raport, [System.Text.Encoding]::UTF8) | ConvertFrom-Json }
  if (Test-Path -LiteralPath $dziennik) { $r.Dziennik = [System.IO.File]::ReadAllText($dziennik, [System.Text.Encoding]::UTF8) }
  if (Test-Path -LiteralPath "$($kopia.Raport).zwis") { $r.Wyjscie += " | okno nie zamknelo sie samo (bezpiecznik 90 s)" }
  return $r
}

# Ocena jednego przebiegu - te same sprawdzenia dla wersji prawdziwej i sabotazy.
function Ocen($u) {
  $o = [ordered]@{}
  $r = $u.Raport
  $okPrzebieg = (-not $u.Zabity) -and ($u.Kod -eq 0) -and $r -and (-not $r.Wywrotka) -and ($u.Dziennik -notmatch 'WYWROTKA') -and
                ($u.Dziennik -notmatch 'samoczynne') -and ($u.Dziennik -match 'okno pokazane: (#[123](, )?){3}\r?\n') -and ($r.Watek -eq "STA") -and (@($r.Uwagi).Count -eq 0)
  $o["przebieg"] = @($okPrzebieg, "kod $($u.Kod), zabity=$($u.Zabity), watek $($r.Watek), wywrotka '$($r.Wywrotka)', uwagi '$(@($r.Uwagi) -join '; ')', wyjscie '$($u.Wyjscie)'")
  if (-not $r) { foreach ($n in @("pola", "wlasciwosci", "zaznaczenie", "kopiuj", "kopiuj-zajety", "kopiuj-blad", "uciecie")) { $o[$n] = @($false, "brak raportu z okna") }; return $o }
  $k = @($r.Kontrolki | Where-Object { $_.Widoczny })
  $pola = @($k | Where-Object { $_.Typ -eq "TextBox" })
  $etykiety = @($k | Where-Object { $_.Typ -eq "Label" })
  $glowy = @{}
  foreach ($id in 1..3) { $g = @($k | Where-Object { $_.Tekst -match "^#$id   \S+ \(.+\)   $([regex]::Escape($projekt))$" }); if ($g.Count -eq 1) { $glowy[$id] = $g[0] } }
  $szukane = @(
    @{ Co = "wstep"; Pole = @($k | Where-Object { $_.Tekst -like "Te sprawy mają termin dziś*krzyżykiem*" }) },
    @{ Co = "uwaga #3"; Pole = @($k | Where-Object { $_.Tekst -like "Uruchomione 2026-10-01, ale nie zostało dokończone*" }) })
  foreach ($id in 1..3) {
    $szukane += @{ Co = "naglowek #$id"; Pole = @($glowy[$id] | Where-Object { $_ }) }
    $szukane += @{ Co = "tresc #$id"; Pole = @($k | Where-Object { $_.Tekst -ceq $trescPola[$id] }) }
  }
  $zle = @($szukane | Where-Object { ($_.Pole.Count -ne 1) -or ($_.Pole[0].Typ -ne "TextBox") } | ForEach-Object { "$($_.Co): $(@($_.Pole | ForEach-Object { $_.Typ }) -join '+')" })
  $o["pola"] = @((($zle.Count -eq 0) -and ($etykiety.Count -eq 0)), "pol tekstowych $($pola.Count), Label $($etykiety.Count); nie w polu: $($zle -join '; ')")

  $zleW = @()
  foreach ($p in $pola) {
    $kol = $CZARNY; if ($p.Tekst -like "Uruchomione 2026-10-01*") { $kol = $CZERWONY }
    if (-not ($p.ReadOnly -and $p.Multiline -and ($p.Ramka -eq "None") -and ($p.Paski -eq "None") -and (-not $p.TabStop) -and $p.Wlaczony -and
              ($p.Tlo -eq $p.TloRodzica) -and ($p.Kolor -eq $kol))) {
      $zleW += "'$($p.Tekst.Substring(0, [Math]::Min(25, $p.Tekst.Length)))' ro=$($p.ReadOnly) ml=$($p.Multiline) ramka=$($p.Ramka) paski=$($p.Paski) tab=$($p.TabStop) wl=$($p.Wlaczony) tlo=$($p.Tlo)/$($p.TloRodzica) kolor=$($p.Kolor)/$kol"
    }
  }
  $o["wlasciwosci"] = @((($pola.Count -gt 0) -and ($zleW.Count -eq 0)), "tylko do odczytu, bez ramki i paskow, poza Tab, w kolorze tla: $(if ($pola.Count -eq 0) { 'nie ma ani jednego pola' } elseif ($zleW) { $zleW -join '; ' } else { 'wszystkie' })")

  $skop = @($r.Zaznaczenia | ForEach-Object { $_.Schowek })
  $zleZ = @($r.Zaznaczenia | Where-Object { $_.Schowek -cne $_.Tekst } | ForEach-Object { "'$($_.Tekst.Substring(0, [Math]::Min(25, $_.Tekst.Length)))' -> schowek '$("$($_.Schowek)".Substring(0, [Math]::Min(25, "$($_.Schowek)".Length)))'" })
  $brak = @(1..3 | Where-Object { $skop -cnotcontains $trescPola[$_] } | ForEach-Object { "#$_" })
  $frag = $r.Fragment -and ($r.Fragment.Schowek -ceq $r.Fragment.Oczekiwany)
  $o["zaznaczenie"] = @((($zleZ.Count -eq 0) -and ($brak.Count -eq 0) -and $frag), "zaznaczonych i skopiowanych $($skop.Count); zle: $($zleZ -join '; '); tresci nie skopiowane: $($brak -join ', '); fragment: $frag")

  $zleK = @()
  foreach ($id in 1..3) {
    $w = @($r.Kopiuj | Where-Object { $_.Nazwa -eq "Kopiuj #$id" })
    if ($w.Count -ne 1) { $zleK += "#${id}: przyciskow $($w.Count)"; continue }
    if (-not $glowy[$id]) { $zleK += "#${id}: nie ma naglowka"; continue }
    $ocz = $glowy[$id].Tekst + "`r`n" + $trescPola[$id]
    if ($w[0].Schowek -cne $ocz) { $zleK += "#${id}: schowek '$($w[0].Schowek)'" }
    if ($w[0].NapisPo -ne "Skopiowano") { $zleK += "#${id}: napis po kliknieciu '$($w[0].NapisPo)'" }
    if ($w[0].NapisPozniej -ne "Kopiuj") { $zleK += "#${id}: napis po chwili '$($w[0].NapisPozniej)'" }
  }
  $o["kopiuj"] = @(($zleK.Count -eq 0), "naglowek + tresc w schowku, 'Skopiowano' i powrot do 'Kopiuj': $(if ($zleK) { $zleK -join '; ' } else { 'trzy przyciski' })")

  $z = $r.KopiujZajety
  $oczZ = $null; if ($z -and ($z.Nazwa -match '^Kopiuj #(\d)$') -and $glowy[[int]$Matches[1]]) { $oczZ = $glowy[[int]$Matches[1]].Tekst + "`r`n" + $trescPola[[int]$Matches[1]] }
  $tekstZ = ($null -ne $oczZ) -and ($z.Schowek -ceq $oczZ)
  $o["kopiuj-zajety"] = @(($z -and $z.ZajetyPrzed -and ($z.NapisPo -eq "Skopiowano") -and ($z.NapisPozniej -eq "Kopiuj") -and $tekstZ),
                          "schowek trzymany $($z.TrzymanoMs) ms, zajety przy kliknieciu: $($z.ZajetyPrzed); klik $($z.CzasKlikniecia) ms, napis '$($z.NapisPo)', po chwili '$($z.NapisPozniej)', tekst w schowku: $tekstZ")

  $b = $r.KopiujBlad
  $wpis = $b -and ($u.Dziennik -match "przycisk $([regex]::Escape($b.Nazwa)) - NIE SKOPIOWALEM do schowka: schowek zajety przez inny program")
  $o["kopiuj-blad"] = @(($b -and $b.ZajetyPrzed -and $b.ZajetyPo -and ($b.NapisPo -eq "Nie skopiowano") -and ($b.NapisPozniej -eq "Nie skopiowano") -and $wpis),
                        "schowek trzymany $($b.TrzymanoMs) ms, zajety przed/po kliknieciu: $($b.ZajetyPrzed)/$($b.ZajetyPo); klik $($b.CzasKlikniecia) ms, napis '$($b.NapisPo)', po chwili '$($b.NapisPozniej)', wpis w dzienniku: $wpis")

  $zleU = @()
  foreach ($p in $pola) {
    if (($p.PierwszaY -ne 0) -or (($p.OstatniaY + $p.WysCzcionki) -gt $p.WysWnetrza) -or ($p.Prawa -gt $p.SzerRodzica)) {
      $zleU += "'$($p.Tekst.Substring(0, [Math]::Min(25, $p.Tekst.Length)))' linii $($p.Linii), ostatnia y=$($p.OstatniaY)+$($p.WysCzcionki) > wys $($p.WysWnetrza), pierwsza y=$($p.PierwszaY), prawa $($p.Prawa)/$($p.SzerRodzica)"
    }
  }
  $dluga = @($pola | Where-Object { $_.Tekst -ceq $trescPola[2] })
  $linii = 0; if ($dluga.Count -eq 1) { $linii = $dluga[0].Linii }
  $o["uciecie"] = @((($linii -ge 5) -and ($zleU.Count -eq 0) -and ($pola.Count -gt 0)), "dluga tresc #2: linii $linii, wys $(@($dluga | ForEach-Object { $_.WysWnetrza }) -join ''); uciete: $(if ($zleU) { $zleU -join '; ' } else { 'zadne' })")
  return $o
}

$OPISY = [ordered]@{
  "przebieg" = "kopia z oknem przeszla bez wywrotki, nic nie uruchomila sama"
  "pola" = "wstep, naglowki, tresci i uwaga sa w polach tekstowych, zadnego Label"
  "wlasciwosci" = "pola tylko do odczytu, bez ramki i paskow, w kolorze tla, kolory jak dawniej"
  "zaznaczenie" = "zaznaczenie i skopiowanie pola daje w schowku dokladnie tresc"
  "kopiuj" = "przycisk Kopiuj wklada do schowka naglowek i tresc"
  "kopiuj-zajety" = "schowek chwile zajety przez inny program: Kopiuj czeka i kopiuje"
  "kopiuj-blad" = "schowek dlugo zajety: 'Nie skopiowano' zostaje na przycisku i jest wpis w dzienniku"
  "uciecie" = "dluga tresc (kilka linii) miesci sie bez uciecia"
}

function Pompuj-Schowek([int]$ms) { $do = [datetime]::Now.AddMilliseconds($ms); while ([datetime]::Now -lt $do) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 } }
function Schowek-Stan {
  $s = [pscustomobject]@{ Tekst = $null; Formaty = [ordered]@{}; Nieodczytane = @() }
  if ([System.Windows.Forms.Clipboard]::ContainsText()) { $s.Tekst = [System.Windows.Forms.Clipboard]::GetText() }
  $dob = [System.Windows.Forms.Clipboard]::GetDataObject()
  if ($dob) { foreach ($fmt in $dob.GetFormats($false)) { try { $v = $dob.GetData($fmt); if ($null -ne $v) { $s.Formaty[$fmt] = $v } else { $s.Nieodczytane += $fmt } } catch { $s.Nieodczytane += $fmt } } }
  return $s
}

# ---------------------------------------------------------------- przebiegi
$schowek = $null; $stan = $null
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
  Wynik "watek STA (schowek)" $false "test musi chodzic w STA (powershell.exe 5.1 -File), inaczej nie zachowa schowka uzytkownika"
} else {
  # Zachowanie schowka uzytkownika: wszystkie formaty, ktore da sie odczytac; nieodczytane wymienione.
  # Odczyt przy zajetym schowku potrafi po cichu dac pusty tekst, dlatego dwa zgodne odczyty pod
  # rzad; bez nich test nie rusza schowka wcale (zamiast nadpisac go pustym przy przywracaniu).
  $poprz = $null
  for ($i = 0; ($i -lt 10) -and (-not $stan); $i++) {
    Pompuj-Schowek 200
    try { $teraz = Schowek-Stan } catch { $teraz = $null; Write-Host "odczyt schowka: $($_.Exception.Message)" }
    if ($teraz -and $poprz -and ("$($teraz.Tekst)" -ceq "$($poprz.Tekst)") -and (($null -eq $teraz.Tekst) -eq ($null -eq $poprz.Tekst)) -and
        ((@($teraz.Formaty.Keys) -join ',') -ceq (@($poprz.Formaty.Keys) -join ','))) { $stan = $teraz }
    $poprz = $teraz
  }
  if (-not $stan) { Wynik "schowek uzytkownika odczytany" $false "brak dwoch zgodnych odczytow w 10 probach - test nie rusza schowka" }
}
if ($stan) {
  $schowek = $stan.Formaty; $nieodczytane = $stan.Nieodczytane; $tekstPrzed = $stan.Tekst
  Write-Host "Schowek uzytkownika: zapamietane formaty $($schowek.Count) ($((@($schowek.Keys)) -join ', ')); nieodczytane: $($nieodczytane -join ', ')"

  try {
    $prawdziwa = Kopia "prawdziwa" @()
    $u = Uruchom $prawdziwa
    $oc = Ocen $u
    foreach ($n in $OPISY.Keys) { Wynik $OPISY[$n] $oc[$n][0] $oc[$n][1] }
    Write-Host "Zrzut okna: $($prawdziwa.Zrzut) (okno $($u.Raport.Okno), ekran $($u.Raport.Ekran))"

    $sabotaze = @(
      @{ Nazwa = "Label zamiast pola z trescia"; Sprawdzenie = "pola"
         K = '$tekst = Pole-Tekstowe $tresc 690 $f.Font $f.ForeColor $f.BackColor'
         Z = '$tekst = New-Object System.Windows.Forms.Label; $tekst.AutoSize = $true; $tekst.MaximumSize = New-Object System.Drawing.Size(690, 0); $tekst.Text = $tresc' },
      @{ Nazwa = "Kopiuj bez naglowka"; Sprawdzenie = "kopiuj"
         K = 'Tekst = $glowa.Text + "`r`n" + $tekst.Text'; Z = 'Tekst = $tekst.Text' },
      @{ Nazwa = "stala wysokosc pola zamiast MeasureText"; Sprawdzenie = "uciecie"
         K = '$t.Height = [System.Windows.Forms.TextRenderer]::MeasureText($tekst, $czcionka, $ile, $flagi).Height'; Z = '$t.Height = 20' },
      @{ Nazwa = "blad schowka po cichu (bez dziennika)"; Sprawdzenie = "kopiuj-blad"
         K = 'Dopisz-Dziennik "przycisk Kopiuj #$($tag.Poz.id) - NIE SKOPIOWALEM do schowka: $($_.Exception.Message)"'; Z = '# sabotaz: cisza' },
      @{ Nazwa = "Do-Schowka po staremu (Clipboard.SetText)"; Sprawdzenie = "kopiuj-zajety"
         K = 'function Do-Schowka([string]$tekst) {'; Z = "function Do-Schowka([string]`$tekst) { [System.Windows.Forms.Clipboard]::SetText(`$tekst) }`r`nfunction Do-Schowka-Nieuzywana([string]`$tekst) {" },
      @{ Nazwa = "Do-Schowka nic nie kopiuje"; Sprawdzenie = "kopiuj"
         K = 'function Do-Schowka([string]$tekst) {'; Z = "function Do-Schowka([string]`$tekst) { }`r`nfunction Do-Schowka-Nieuzywana([string]`$tekst) {" },
      @{ Nazwa = "Do-Schowka polyka porazke"; Sprawdzenie = "kopiuj-blad"
         K = 'throw "schowek zajety przez inny program'; Z = 'return; "schowek zajety przez inny program' })
    $nr = 0
    foreach ($s in $sabotaze) {
      $nr++
      try {
        $kop = Kopia "sabotaz$nr" @(@{ K = $s.K; Z = $s.Z }) -Zajety ($s.Sprawdzenie -like "kopiuj-*")
      } catch { Wynik "sabotaz '$($s.Nazwa)' wylapany" $false "przygotowanie: $($_.Exception.Message)"; continue }
      $os = Ocen (Uruchom $kop)
      Wynik "negatywna: sabotaz '$($s.Nazwa)' wylapany przez '$($s.Sprawdzenie)'" ((-not $os[$s.Sprawdzenie][0]) -and $os["przebieg"][0]) "z sabotazem: $($os[$s.Sprawdzenie][1])"
    }
  } catch {
    Wynik "WYWROTKA TESTU" $false "$($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
  } finally {
    # Przywrocenie schowka uzytkownika - z ponawianiem jak Do-Schowka (bez wlasnego czekania .NET,
    # ktore przy programie czytajacym schowek czeka na prozno) i sprawdzeniem dwoma odczytami.
    $nowy = New-Object System.Windows.Forms.DataObject
    foreach ($fmt in $schowek.Keys) { $nowy.SetData($fmt, $schowek[$fmt]) }
    $blad = "nie probowalem"
    for ($i = 0; $i -lt 30; $i++) {
      try {
        if ($schowek.Count -gt 0) { [System.Windows.Forms.Clipboard]::SetDataObject($nowy, $true, 0, 0) } else { [System.Windows.Forms.Clipboard]::SetDataObject((New-Object System.Windows.Forms.DataObject), $true, 0, 0) }
        $blad = ""; break
      } catch { $blad = $_.Exception.Message; Pompuj-Schowek 100 }
    }
    $po = $null; $zgodne = $false
    for ($i = 0; ($i -lt 10) -and (-not $zgodne); $i++) {
      Pompuj-Schowek 200
      try { $po = (Schowek-Stan).Tekst } catch { $po = "BLAD ODCZYTU: $($_.Exception.Message)" }
      $zgodne = ("$po" -ceq "$tekstPrzed") -and (($null -eq $po) -eq ($null -eq $tekstPrzed))
    }
    Wynik "schowek uzytkownika przywrocony" ((-not $blad) -and $zgodne) ("tekst przed: $(if ($null -eq $tekstPrzed) { 'brak' } else { "$($tekstPrzed.Length) zn." }), po: $(if ($null -eq $po) { 'brak' } else { "$($po.Length) zn." }); formatow $($schowek.Count)$(if ($blad) { "; zapis: $blad" })")
  }
}

# Po tescie zaden proces kopii nie moze zostac.
$zostale = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" | Where-Object { "$($_.CommandLine)" -like "*$tmp*" })
foreach ($z in $zostale) { try { Stop-Process -Id $z.ProcessId -Force } catch { Write-Warning "nie ubilem $($z.ProcessId): $($_.Exception.Message)" } }
Wynik "po tescie zaden proces kopii nie zostal" ($zostale.Count -eq 0) "pozostalych: $($zostale.Count)"

Write-Host ""
Write-Host "Zrzuty: $Zrzuty"
Write-Host "Wynik: $(@($script:wyniki | Where-Object { $_.OK }).Count) z $($script:wyniki.Count) TAK. Pliki robocze: $tmp"
if (@($script:wyniki | Where-Object { -not $_.OK }).Count -gt 0) { exit 1 }
exit 0
