# Sprawdzenie okna przypomnien (zasobnik\terminy.ps1, 2026-10-08): napisy w oknie to pola
# tekstowe tylko do odczytu, ktore da sie zaznaczyc i skopiowac, przycisk "Kopiuj" przy kazdym
# przypomnieniu, dluga tresc bez uciecia, porazka schowka widoczna na przycisku i w dzienniku.
#   powershell -ExecutionPolicy Bypass -File zasobnik\test-terminy-okno.ps1 [-Zrodlo <repo>] [-Zrzuty <kat>]
# Wszystko na kopii terminy.ps1, sztucznym katalogu domowym i testowym pliku przypomnien (tylko
# tryb "przypomnij" - nic sie samo nie uruchamia). Kopia: okno poza ekranem (-5000, 0), bez paska
# zadan, bez aktywacji (nie zabiera klawiatury), bez TopMost, klawiatura wylaczona, wlasne zamki,
# zegar, ktory po pomiarach zamyka okno. Proces kopii bez okna konsoli, ubijany po 120 s.
# Sabotaze: kopie z Label zamiast pola, zepsutym "Kopiuj", stala wysokoscia pola i cichym bledem
# schowka - kazdy MUSI zostac zlapany. Zawartosc schowka uzytkownika zachowana i przywrocona.
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
  function T-Schowek { try { return [System.Windows.Forms.Clipboard]::GetText() } catch { return "BLAD ODCZYTU SCHOWKA: $($_.Exception.Message)" } }
  function T-Czysc { try { [System.Windows.Forms.Clipboard]::Clear() } catch { $script:TestRaport.Uwagi += "Clear: $($_.Exception.Message)" } }
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
      $c.Select(0, $c.TextLength); $c.Copy(); T-Pompuj 30
      $r.Zaznaczenia += [pscustomobject]@{ Tekst = $c.Text; Zaznaczone = $c.SelectedText; Schowek = (T-Schowek) }
    }
    $dl = $pola | Sort-Object TextLength -Descending | Select-Object -First 1
    if ($dl -and $dl.TextLength -gt 60) {
      T-Czysc
      $dl.Select(10, 45); $dl.Copy(); T-Pompuj 30
      $r.Fragment = [pscustomobject]@{ Oczekiwany = $dl.Text.Substring(10, 45); Schowek = (T-Schowek) }
    }
    # przyciski Kopiuj
    $kop = @(T-Wszystkie $script:Okno | Where-Object { ($_ -is [System.Windows.Forms.Button]) -and ("$($_.AccessibleName)" -like "Kopiuj #*") })
    $wpisy = @()
    foreach ($b in $kop) {
      T-Czysc
      $b.PerformClick(); T-Pompuj 30
      $wpisy += [pscustomobject]@{ Nazwa = $b.AccessibleName; Schowek = (T-Schowek); NapisPo = $b.Text; NapisPozniej = ""; Szer = $b.Width; Przycisk = $b }
    }
    T-Pompuj ($MS_NAPISU_SKOPIOWANO + 700)
    foreach ($w in $wpisy) { $w.NapisPozniej = $w.Przycisk.Text; $w.Szer = "$($w.Szer)/$($w.Przycisk.Width)"; $w.PSObject.Properties.Remove("Przycisk"); $r.Kopiuj += $w }
    # schowek zablokowany: Do-Schowka rzuca jak Clipboard.SetText przy zajetym schowku
    if ($kop.Count -gt 0) {
      $stara = ${function:script:Do-Schowka}
      ${function:script:Do-Schowka} = { param([string]$tekst) throw "TEST: schowek zajety przez inny program" }
      $b = $kop[0]
      $b.PerformClick(); T-Pompuj 30
      $po = $b.Text
      T-Pompuj ($MS_NAPISU_SKOPIOWANO + 700)
      $r.KopiujBlad = [pscustomobject]@{ Nazwa = $b.AccessibleName; NapisPo = $po; NapisPozniej = $b.Text }
      ${function:script:Do-Schowka} = $stara
    }
    $bmp = New-Object System.Drawing.Bitmap($script:Okno.Width, $script:Okno.Height)
    $script:Okno.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $script:Okno.Width, $script:Okno.Height)))
    $bmp.Save('__ZRZUT__'); $bmp.Dispose()
  }
  $script:TestRaport = [pscustomobject]@{ Kontrolki = @(); Zaznaczenia = @(); Fragment = $null; Kopiuj = @(); KopiujBlad = $null
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
function Kopia([string]$wariant, [hashtable[]]$podmiany) {
  $raport = Join-Path $tmp "raport-$wariant.json"
  $zrzut = Join-Path $Zrzuty "terminy-okno-$wariant.png"
  $wsp = @(
    @{ K = '$f = New-Object System.Windows.Forms.Form'; Z = $klasaOkna.TrimStart() },
    @{ K = '$f.TopMost = $true'; Z = '$f.TopMost = $false' },
    @{ K = '$f.ShowInTaskbar = $true'; Z = '$f.ShowInTaskbar = $false' },
    @{ K = '$f.StartPosition = "CenterScreen"'; Z = '$f.StartPosition = "Manual"; $f.Location = New-Object System.Drawing.Point(-5000, 0)' },
    @{ K = '$f.Add_Shown({ $f.Activate() })'; Z = $hak.Replace('__RAPORT__', $raport).Replace('__ZRZUT__', $zrzut) },
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
                ($u.Dziennik -notmatch 'samoczynne') -and ($u.Dziennik -match 'okno pokazane: (#[123](, )?){3}\r?\n') -and ($r.Watek -eq "STA")
  $o["przebieg"] = @($okPrzebieg, "kod $($u.Kod), zabity=$($u.Zabity), watek $($r.Watek), wywrotka '$($r.Wywrotka)', wyjscie '$($u.Wyjscie)'")
  if (-not $r) { foreach ($n in @("pola", "wlasciwosci", "zaznaczenie", "kopiuj", "kopiuj-blad", "uciecie")) { $o[$n] = @($false, "brak raportu z okna") }; return $o }
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

  $b = $r.KopiujBlad
  $wpis = $b -and ($u.Dziennik -match "przycisk $([regex]::Escape($b.Nazwa)) - NIE SKOPIOWALEM do schowka: TEST: schowek zajety")
  $o["kopiuj-blad"] = @(($b -and ($b.NapisPo -eq "Nie skopiowano") -and ($b.NapisPozniej -eq "Nie skopiowano") -and $wpis),
                        "napis '$($b.NapisPo)', po chwili '$($b.NapisPozniej)', wpis w dzienniku: $wpis")

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
  "kopiuj-blad" = "zajety schowek: 'Nie skopiowano' zostaje na przycisku i jest wpis w dzienniku"
  "uciecie" = "dluga tresc (kilka linii) miesci sie bez uciecia"
}

# ---------------------------------------------------------------- przebiegi
$schowek = $null
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
  Wynik "watek STA (schowek)" $false "test musi chodzic w STA (powershell.exe 5.1 -File), inaczej nie zachowa schowka uzytkownika"
} else {
  # Zachowanie schowka uzytkownika: wszystkie formaty, ktore da sie odczytac; nieodczytane wymienione.
  $schowek = [ordered]@{}
  $nieodczytane = @()
  $tekstPrzed = $null
  try {
    if ([System.Windows.Forms.Clipboard]::ContainsText()) { $tekstPrzed = [System.Windows.Forms.Clipboard]::GetText() }
    $dob = [System.Windows.Forms.Clipboard]::GetDataObject()
    if ($dob) { foreach ($fmt in $dob.GetFormats($false)) { try { $v = $dob.GetData($fmt); if ($null -ne $v) { $schowek[$fmt] = $v } else { $nieodczytane += $fmt } } catch { $nieodczytane += $fmt } } }
  } catch { Wynik "schowek uzytkownika odczytany" $false $_.Exception.Message }
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
         K = 'Dopisz-Dziennik "przycisk Kopiuj #$($tag.Poz.id) - NIE SKOPIOWALEM do schowka: $($_.Exception.Message)"'; Z = '# sabotaz: cisza' })
    $nr = 0
    foreach ($s in $sabotaze) {
      $nr++
      try {
        $kop = Kopia "sabotaz$nr" @(@{ K = $s.K; Z = $s.Z })
      } catch { Wynik "sabotaz '$($s.Nazwa)' wylapany" $false "przygotowanie: $($_.Exception.Message)"; continue }
      $os = Ocen (Uruchom $kop)
      Wynik "negatywna: sabotaz '$($s.Nazwa)' wylapany przez '$($s.Sprawdzenie)'" ((-not $os[$s.Sprawdzenie][0]) -and $os["przebieg"][0]) "z sabotazem: $($os[$s.Sprawdzenie][1])"
    }
  } catch {
    Wynik "WYWROTKA TESTU" $false "$($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
  } finally {
    # Przywrocenie schowka uzytkownika.
    try {
      if ($schowek.Count -gt 0) {
        $nowy = New-Object System.Windows.Forms.DataObject
        foreach ($fmt in $schowek.Keys) { $nowy.SetData($fmt, $schowek[$fmt]) }
        [System.Windows.Forms.Clipboard]::SetDataObject($nowy, $true)
      } else {
        [System.Windows.Forms.Clipboard]::Clear()
      }
      $po = $null; if ([System.Windows.Forms.Clipboard]::ContainsText()) { $po = [System.Windows.Forms.Clipboard]::GetText() }
      Wynik "schowek uzytkownika przywrocony" ("$po" -ceq "$tekstPrzed") ("tekst przed: $(if ($null -eq $tekstPrzed) { 'brak' } else { "$($tekstPrzed.Length) zn." }), po: $(if ($null -eq $po) { 'brak' } else { "$($po.Length) zn." }); formatow $($schowek.Count)")
    } catch {
      if ($null -ne $tekstPrzed) { try { [System.Windows.Forms.Clipboard]::SetText($tekstPrzed) } catch { Write-Warning "schowek: nie przywrocilem nawet tekstu: $($_.Exception.Message)" } }
      Wynik "schowek uzytkownika przywrocony" $false "pelne przywrocenie nie wyszlo ($($_.Exception.Message)), przywrocony sam tekst"
    }
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
