# instalator\wyglad.ps1 - czesc okna instalatora (patrz BUDOWA w naglowku instalator\okno.ps1).
# Wyglad i klocki okna: kolory, kroje, wymiary liczone z ekranu, etykiety, karty,
# przyciski (zwykly, glowny, przelacznik zestawow) i pasek postepu.
# Wzor: okno nadzorcy (zasobnik\nadzorca\wyglad.ps1 i karty.ps1) - te same kolory, kroje
# i biale karty, zeby instalator i aplikacja przy zegarze wygladaly jak jedno narzedzie.
# Wartosci sa SKOPIOWANE, a nie wczytane z nadzorcy: tamte pliki przy wczytaniu ustawiaja
# caly stan okna nadzorcy, a instalator chodzi tez z pobranego ZIP-a, zanim nadzorca jest.
# Skad wolane: ekrany.ps1 i okno.ps1. Wczytuje go okno.ps1 kropka - poza kolorami, krojami
# i wymiarami same definicje.

# --- kolory ------------------------------------------------------------------
# KOLOR TYLKO TAM, GDZIE NIESIE ZNACZENIE (jak w nadzorcy): czerwien przy tym, co sie nie
# udalo albo co usuwa, zolty przy uwadze i trybie proby, zielen przy "gotowe", niebieski
# MegaRuchacza na glownym przycisku, biezacym kroku i pasku postepu. Cala reszta jest szara.
$script:KolTekst    = [System.Drawing.Color]::FromArgb(28, 28, 30)
$script:KolSzary    = [System.Drawing.Color]::FromArgb(106, 108, 112)
$script:KolPilne    = [System.Drawing.Color]::FromArgb(176, 32, 32)
$script:KolUwaga    = [System.Drawing.Color]::FromArgb(146, 98, 0)
$script:KolDobrze   = [System.Drawing.Color]::FromArgb(24, 104, 56)
$script:TloPilne    = [System.Drawing.Color]::FromArgb(253, 236, 236)
$script:TloUwaga    = [System.Drawing.Color]::FromArgb(255, 248, 227)
$script:TloPaska    = [System.Drawing.Color]::FromArgb(250, 250, 251)
$script:TloOkna     = [System.Drawing.Color]::FromArgb(243, 244, 246)
$script:TloKarty    = [System.Drawing.Color]::White
$script:TloPrzel    = [System.Drawing.Color]::FromArgb(228, 230, 234)
$script:KolRamki    = [System.Drawing.Color]::FromArgb(224, 226, 230)
$script:KolMr       = [System.Drawing.Color]::FromArgb(47, 95, 168)
$script:KolMrCiemny = [System.Drawing.Color]::FromArgb(36, 76, 140)
$script:KolCc       = [System.Drawing.Color]::FromArgb(214, 218, 224)
$script:KolJasny    = [System.Drawing.Color]::FromArgb(176, 182, 190)
$script:PioroRamki  = New-Object System.Drawing.Pen($script:KolRamki)

# Hierarchia krojem i wielkoscia, nie kolorem. Czcionki WSPOLNE dla wszystkich kontrolek -
# tworzone przy kazdym ekranie wyciekalyby uchwytami GDI (tak samo jak w nadzorcy).
$script:CzTytul       = New-Object System.Drawing.Font("Segoe UI Semibold", 15)
$script:CzGruba       = New-Object System.Drawing.Font("Segoe UI Semibold", 10.5)
$script:CzSrednia     = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
$script:CzZwykla      = New-Object System.Drawing.Font("Segoe UI", 9.75)
$script:CzZwyklaGruba = New-Object System.Drawing.Font("Segoe UI Semibold", 9.75)
$script:CzMala        = New-Object System.Drawing.Font("Segoe UI", 8.75)
$script:CzMalaGruba   = New-Object System.Drawing.Font("Segoe UI Semibold", 8.75)
$script:CzStala       = New-Object System.Drawing.Font("Consolas", 9)
$script:CzZnak        = New-Object System.Drawing.Font("Segoe UI Semibold", 11)

# Znaki krokow - te same co na ekranie ladowania nadzorcy.
$script:ZNAK_CZEKA  = [string][char]0x25CB
$script:ZNAKI_TRWA  = @([string][char]0x25D0, [string][char]0x25D3, [string][char]0x25D1, [string][char]0x25D2)
$script:ZNAK_OK     = [string][char]0x2713
$script:ZNAK_BLAD   = [string][char]0x2717
$script:ZNAK_POMIN  = [string][char]0x2013

# --- wymiary -----------------------------------------------------------------
# Okno na ekranie, na ktorym jest kursor (tam uzytkownik kliknal instaluj.bat). powershell.exe
# NIE jest swiadomy DPI (sprawdzone 02.10.2026: IsProcessDPIAware = False), wiec Windows sam
# skaluje okno, a obszar roboczy przychodzi w punktach logicznych - laptop 1366x768 przy
# 125% to ok. 1093x582. Dlatego szerokosc i wysokosc sa liczone z obszaru, a tresc sie
# przewija, gdy ekran jest za niski: nic nie znika pod krawedzia po cichu.
try { $script:ObszarEkranu = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea }
catch { $script:ObszarEkranu = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea }
$script:SzerOkna    = [int][math]::Max(760, [math]::Min(900, $script:ObszarEkranu.Width - 40))
$script:WysOkna     = [int][math]::Max(520, [math]::Min(720, $script:ObszarEkranu.Height - 60))
$script:Margines    = 28
# 20 px na pionowy suwak - suwak poziomy nie ma prawa sie pojawic.
$script:SzerTresc   = $script:SzerOkna - 2 * $script:Margines - 20
$script:SzerKarty   = $script:SzerTresc
$script:SzerWnetrza = $script:SzerKarty - 44

# --- klocki ------------------------------------------------------------------

function Etykieta([string]$tekst, $czcionka, $kolor) {
  $l = New-Object System.Windows.Forms.Label
  $l.AutoSize = $true
  $l.Font = $czcionka
  $l.ForeColor = $kolor
  $l.BackColor = [System.Drawing.Color]::Transparent
  # Sciezki z "&" (np. "C:\Users\Jan & Ania") maja sie pokazac w calosci.
  $l.UseMnemonic = $false
  # Tresc bez zmian; tylko twarda spacja w nazwie podpowiedzi, zeby nie rozpadla sie na dwa wiersze.
  $l.Text = "$tekst".Replace('„Z ARCHIWUM”', ('„Z' + [char]0x00A0 + 'ARCHIWUM”'))
  $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
  return $l
}

# Maksymalna, a nie stala szerokosc: dlugi tekst zawija sie w kilka wierszy zamiast
# wyjechac poza karte. Tekst wyjezdzajacy poza okno bylby ucieciem po cichu.
function Etykieta-Zawijana([string]$tekst, $czcionka, $kolor, [int]$szerokosc) {
  $l = Etykieta $tekst $czcionka $kolor
  $l.MaximumSize = New-Object System.Drawing.Size($szerokosc, 0)
  return $l
}

function Pionowy([int]$szerokosc) {
  $p = New-Object System.Windows.Forms.FlowLayoutPanel
  $p.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
  $p.WrapContents = $false
  $p.AutoSize = $true
  $p.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
  $p.Margin = New-Object System.Windows.Forms.Padding(0)
  $p.Padding = New-Object System.Windows.Forms.Padding(0)
  if ($szerokosc -gt 0) { $p.MinimumSize = New-Object System.Drawing.Size($szerokosc, 0) }
  return $p
}

function Poziomy {
  $p = New-Object System.Windows.Forms.FlowLayoutPanel
  $p.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
  $p.WrapContents = $false
  $p.AutoSize = $true
  $p.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
  $p.Margin = New-Object System.Windows.Forms.Padding(0)
  $p.Padding = New-Object System.Windows.Forms.Padding(0)
  return $p
}

# Biala karta z cienka szara ramka (ramka rysowana w Paint - BorderStyle daje czarna kreske
# jak z Windows 95). $tlo: TloPilne / TloUwaga dla kart z alarmem, inaczej biala.
function Nowa-Karta([int]$szerokosc, $tlo = $null) {
  $k = Pionowy $szerokosc
  $k.BackColor = $script:TloKarty
  if ($tlo) { $k.BackColor = $tlo }
  $k.Padding = New-Object System.Windows.Forms.Padding(22, 16, 22, 16)
  $k.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)
  $k.Add_Paint({ param($nadawca, $e) Obrysuj $nadawca $e })
  return $k
}

function Obrysuj($kontrolka, $e) {
  try {
    $e.Graphics.DrawRectangle($script:PioroRamki, 0, 0, $kontrolka.Width - 1, $kontrolka.Height - 1)
  } catch {
    if (-not $script:RamkaZawiodla) { $script:RamkaZawiodla = $true; Zanotuj-Wywrotke "rysowanie ramki karty" $_ }
  }
}

function Wyczysc-Panel($panel) {
  if (-not $panel) { return }
  while ($panel.Controls.Count -gt 0) {
    $c = $panel.Controls[0]
    $panel.Controls.RemoveAt(0)
    try { $c.Dispose() }
    catch { Zapisz-Dziennik "nie udalo sie zwolnic kontrolki okna: $($_.Exception.Message)" }
  }
}

# Zwykly przycisk - systemowy, jak w nadzorcy.
function Nowy-Przycisk([string]$napis, [int]$szerokosc = 120) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $napis
  $b.Font = $script:CzZwykla
  $b.FlatStyle = [System.Windows.Forms.FlatStyle]::System
  $b.Size = New-Object System.Drawing.Size($szerokosc, 34)
  $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
  $b.UseMnemonic = $false
  return $b
}

# Glowny przycisk ekranu (Dalej / Zainstaluj / Zastosuj zmiany): plaski, w niebieskim
# MegaRuchacza - jedyny kolorowy przycisk, zeby bylo widac, gdzie sie idzie dalej.
function Przycisk-Glowny([string]$napis, [int]$szerokosc = 170) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $napis
  $b.Font = $script:CzZwyklaGruba
  $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
  $b.FlatAppearance.BorderSize = 0
  $b.Size = New-Object System.Drawing.Size($szerokosc, 34)
  $b.Margin = New-Object System.Windows.Forms.Padding(0)
  $b.Cursor = [System.Windows.Forms.Cursors]::Hand
  $b.UseMnemonic = $false
  $b.Tag = "glowny"
  Ustaw-Wlaczony $b $true
  return $b
}

# Przycisk, ktory usuwa (np. "Usuń" w pytaniu o usuniecie czesci) - ten sam ksztalt co
# glowny, ale czerwony: czerwien w tym oknie znaczy "to cos zabierze".
function Przycisk-Grozny([string]$napis, [int]$szerokosc = 150) {
  $b = Przycisk-Glowny $napis $szerokosc
  $b.Tag = "grozny"
  Ustaw-Wlaczony $b $true
  return $b
}

# Wylaczony plaski przycisk WinForms rysuje szarym tekstem na swoim tle - na niebieskim
# byloby to nieczytelne, wiec wylaczony glowny dostaje jasnoszare tlo.
function Ustaw-Wlaczony($b, [bool]$wlaczony) {
  if (-not $b -or $b.IsDisposed) { return }
  $b.Enabled = $wlaczony
  if (($b.Tag -ne "glowny") -and ($b.Tag -ne "grozny")) { return }
  if ($wlaczony) {
    $tlo = $script:KolMr; $ciemne = $script:KolMrCiemny
    if ($b.Tag -eq "grozny") { $tlo = $script:KolPilne; $ciemne = [System.Drawing.Color]::FromArgb(140, 24, 24) }
    $b.BackColor = $tlo
    $b.ForeColor = [System.Drawing.Color]::White
    $b.FlatAppearance.MouseOverBackColor = $ciemne
    $b.FlatAppearance.MouseDownBackColor = $ciemne
  } else {
    $b.BackColor = $script:KolCc
    $b.ForeColor = $script:KolSzary
    $b.FlatAppearance.MouseOverBackColor = $script:KolCc
    $b.FlatAppearance.MouseDownBackColor = $script:KolCc
  }
}

# Jeden z przyciskow przelacznika zestawow [Wszystko | Wlasny wybor]: plaski, bez ramki,
# wybrany jest bialy na szarym tle - jak przelacznik widokow w oknie nadzorcy.
function Przycisk-Przelacznika([string]$napis, [int]$x, [int]$szer) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $napis
  $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
  $b.FlatAppearance.BorderSize = 0
  $b.Size = New-Object System.Drawing.Size($szer, 30)
  $b.Location = New-Object System.Drawing.Point($x, 3)
  $b.Cursor = [System.Windows.Forms.Cursors]::Hand
  $b.TabStop = $false
  $b.UseMnemonic = $false
  return $b
}

function Styl-Przelacznika($b, [bool]$wybrany) {
  if (-not $b -or $b.IsDisposed) { return }
  if ($wybrany) {
    $b.BackColor = [System.Drawing.Color]::White
    $b.ForeColor = $script:KolTekst
    $b.Font = $script:CzZwyklaGruba
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::White
  } else {
    $b.BackColor = $script:TloPrzel
    $b.ForeColor = $script:KolSzary
    $b.Font = $script:CzZwykla
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(236, 238, 241)
  }
}

# Pasek postepu rysowany sam (jak na ekranie ladowania nadzorcy): systemowy ProgressBar
# ma animacje i zielen Windows, ktora gryzie sie z reszta okna.
function Nowy-Pasek([int]$szerokosc) {
  $p = New-Object System.Windows.Forms.PictureBox
  $p.Size = New-Object System.Drawing.Size($szerokosc, 8)
  $p.Margin = New-Object System.Windows.Forms.Padding(0, 14, 0, 16)
  $p.Tag = 0.0
  $p.Add_Paint({
    param($nadawca, $e)
    try {
      $w = [int]$nadawca.ClientSize.Width; $h = [int]$nadawca.ClientSize.Height
      $tlo = New-Object System.Drawing.SolidBrush($script:KolCc)
      $pel = New-Object System.Drawing.SolidBrush($script:KolMr)
      try {
        $e.Graphics.FillRectangle($tlo, 0, 0, $w, $h)
        $e.Graphics.FillRectangle($pel, 0, 0, [int]($w * [math]::Min(1.0, [math]::Max(0.0, [double]$nadawca.Tag))), $h)
      } finally { $tlo.Dispose(); $pel.Dispose() }
    } catch {
      if (-not $script:RysowanieZawiodlo) { $script:RysowanieZawiodlo = $true; Zanotuj-Wywrotke "rysowanie paska postepu" $_ }
    }
  })
  return $p
}

# Cienka kreska oddzielajaca wiersze w karcie.
function Kreska([int]$szerokosc) {
  $k = New-Object System.Windows.Forms.Panel
  $k.Size = New-Object System.Drawing.Size($szerokosc, 1)
  $k.BackColor = $script:KolRamki
  $k.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 8)
  return $k
}

# Znacznik dla okno.ps1: ten plik wczytal sie do konca.
$script:ModulyInstalatora["wyglad"] = $true
