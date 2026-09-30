# zasobnik\nadzorca\wykres.ps1 - czesc zasobnik\nadzorca.ps1 (patrz BUDOWA
# w jego naglowku). Wykres nauki z 30 dni: skala i prog liczone raz
# (Ustaw-Miare-Wykresu, Skala-Wykresu, Prog-Widoczny), kontrolka Chart z .NET
# (Nowy-Chart) albo wlasne slupki w Paint (Rysuj-Slupki), gdy Chart zawiodl, i
# wstawienie jednego z nich do karty (Wstaw-Wykres). Czy Chart sie zaladowal,
# ustala start nadzorca.ps1 ($script:JestChart, Opis-Rysownika).
# Skad wolane: Odmaluj-Statystyke w przeglad.ps1. Wczytuje go nadzorca.ps1 kropka
# po zamku jednej kopii - tu sa same definicje.

# --- wykres ------------------------------------------------------------------
# Te same dane rysuja dwie drogi: kontrolka Chart (gdy sie zaladowala) albo
# wlasne slupki w Paint. Skala i prog sa liczone RAZ, tutaj, zeby obie drogi
# pokazywaly dokladnie to samo.

# Gorna granica osi: najwyzszy slupek plus zapas, zaokraglona do "ladnej" liczby.
# Prog zwyklego dnia wchodzi do skali tylko wtedy, gdy jest najwyzej dwa razy
# wyzej niz najwyzszy slupek - inaczej zgniotlby wszystkie slupki do kresek,
# a legenda mowi wtedy wprost, ze prog jest daleko ponad nimi.
# MIARA OSI. $script:WykresDz to dzielnik "tokeny -> jednostka osi". Ustawia go
# Odmaluj-Statystyke przed rysowaniem; skala zwracana jest juz w tej jednostce.
# P15 dal tu procent jednego otwarcia sesji.
# P17 (28.09.2026): os ZAWSZE w tysiacach tokenow. Procent otwarcia okna
# rozmowy przy koszcie dziennym nic uzytkownikowi nie mowil. Przelacznik
# $script:WykresProc zostaje (rysowanie go obsluguje), ale nie jest wlaczany.
function Ustaw-Miare-Wykresu {
  $script:WykresDz = 1000.0
  $script:WykresProc = $false
}

function Etykieta-Osi([double]$v) {
  if ($v -le 0) { return "0" }
  $pl = [System.Globalization.CultureInfo]::GetCultureInfo("pl-PL")
  if ($script:WykresProc) { return ($v.ToString("0.#", $pl) + "%") }
  return ($v.ToString("0.#", $pl) + " tys.")
}

function Skala-Wykresu($st) {
  $max = [double]0
  foreach ($d in @($st.Dni)) { if ($d.Razem -gt $max) { $max = [double]$d.Razem } }
  if ($max -le 0) { $max = 1000 }
  $gora = $max
  if (Prog-Widoczny $st) { $gora = [math]::Max($gora, [double]$st.Prog) }
  $gora = $gora * 1.1 / $script:WykresDz
  $potega = [math]::Pow(10, [math]::Floor([math]::Log10($gora)))
  foreach ($m in @(1, 2, 2.5, 4, 5, 10)) {
    if (($m * $potega) -ge $gora) { return [double]($m * $potega) }
  }
  return [double](10 * $potega)
}

function Prog-Widoczny($st) {
  if ((-not $st) -or ($null -eq $st.Prog) -or ($st.Prog -le 0)) { return $false }
  $max = [double]0
  foreach ($d in @($st.Dni)) { if ($d.Razem -gt $max) { $max = [double]$d.Razem } }
  return ([double]$st.Prog -le (2 * $max))
}

function Opis-Dnia-Wykresu($d) {
  $cz = @()
  if ($d.Zwykle -gt 0)      { $cz += "zwykły dzień" }
  if ($d.Nadrabianie -gt 0) { $cz += "rozmowy z kilku dni naraz" }
  if ($d.Nieznane -gt 0)    { $cz += "nie wiadomo, z których dni" }
  return "$($d.Dzien.ToString('dd.MM')): $(Liczba-Ludzka $d.Razem) tokenów ($($cz -join ' + '))"
}

# Droga pierwsza: wbudowana kontrolka Chart. Wyjatek z tej funkcji przelacza
# okno na droge druga (wlasne slupki) - patrz Wstaw-Wykres.
function Nowy-Chart($st) {
  $ch = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
  $ch.BackColor = [System.Drawing.Color]::White
  $ch.AntiAliasing = [System.Windows.Forms.DataVisualization.Charting.AntiAliasingStyles]::All
  $ch.TextAntiAliasingQuality = [System.Windows.Forms.DataVisualization.Charting.TextAntiAliasingQuality]::High

  $ob = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea("obszar")
  $ob.BackColor = [System.Drawing.Color]::White
  foreach ($os in @($ob.AxisX, $ob.AxisY)) {
    $os.LineColor = $script:KolOsi
    $os.MajorTickMark.Enabled = $false
    $os.LabelStyle.Font = $script:CzMala
    $os.LabelStyle.ForeColor = $script:KolSzary
  }
  $ob.AxisX.MajorGrid.Enabled = $false
  $ob.AxisX.IsLabelAutoFit = $false
  $ob.AxisY.MajorGrid.LineColor = $script:KolSiatki
  $skala = Skala-Wykresu $st
  $ob.AxisY.Minimum = 0
  $ob.AxisY.Maximum = $skala
  $ob.AxisY.Interval = $skala / 2.0
  if ($script:WykresProc) {
    $ob.AxisY.LabelStyle.Format = "0.#'%'"
    $ob.AxisY.Title = "% otwarcia`nokna rozmowy"
  } else {
    $ob.AxisY.LabelStyle.Format = "0"
    $ob.AxisY.Title = "tys. tokenów"
  }
  $ob.AxisY.TitleFont = $script:CzMala
  $ob.AxisY.TitleForeColor = $script:KolSzary
  if (Prog-Widoczny $st) {
    $linia = New-Object System.Windows.Forms.DataVisualization.Charting.StripLine
    $linia.IntervalOffset = [double]$st.Prog / $script:WykresDz
    $linia.StripWidth = 0
    $linia.BorderColor = $script:KolPilne
    $linia.BorderDashStyle = [System.Windows.Forms.DataVisualization.Charting.ChartDashStyle]::Dash
    $linia.BorderWidth = 1
    $linia.Text = "tu zaczyna się drogo"
    $linia.TextAlignment = [System.Drawing.StringAlignment]::Far
    $linia.TextLineAlignment = [System.Drawing.StringAlignment]::Far
    $linia.ForeColor = $script:KolPilne
    $linia.Font = $script:CzMala
    $ob.AxisY.StripLines.Add($linia) | Out-Null
  }
  $ch.ChartAreas.Add($ob) | Out-Null

  $serie = @(
    @{ Nazwa = "zwykle";      Kolor = $script:KolSlupek; Pole = "Zwykle" },
    @{ Nazwa = "nieznane";    Kolor = $script:KolNiezn;  Pole = "Nieznane" },
    @{ Nazwa = "nadrabianie"; Kolor = $script:KolNadrab; Pole = "Nadrabianie" }
  )
  foreach ($opis in $serie) {
    $s = New-Object System.Windows.Forms.DataVisualization.Charting.Series($opis.Nazwa)
    $s.ChartArea = "obszar"
    $s.ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::StackedColumn
    $s.Color = $opis.Kolor
    $s["PointWidth"] = "0.62"
    foreach ($d in @($st.Dni)) {
      $i = $s.Points.AddY([double]$d.($opis.Pole) / $script:WykresDz)
      if ($d.Jest) { $s.Points[$i].ToolTip = (Opis-Dnia-Wykresu $d) }
    }
    $ch.Series.Add($s) | Out-Null
  }
  # Podpisy dni co tydzien, liczac od dzis wstecz - tak, zeby dzisiejszy dzien
  # mial podpis zawsze. Punkty sa numerowane od 1.
  $n = @($st.Dni).Count
  for ($i = $n; $i -ge 1; $i -= 7) {
    # szeroki zakres podpisu (tydzien), inaczej Chart lamie "28.08" na dwie linie
    $ob.AxisX.CustomLabels.Add([double]($i - 3), [double]($i + 3), $st.Dni[$i - 1].Dzien.ToString('dd.MM')) | Out-Null
  }
  return $ch
}

# Droga druga: wlasne slupki. Uzywana, gdy kontrolki Chart nie ma albo sie
# wywrocila, i ZAWSZE wtedy, gdy nie ma czego rysowac - wtedy w miejscu wykresu
# stoi zdanie, ze statystyka dopiero sie zbiera, a nie puste pole.
function Rysuj-Slupki($g, $rozmiar, $st) {
  $pedzle = @()
  $piora = @()
  try {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.Clear([System.Drawing.Color]::White)
    $szer = [float]$rozmiar.Width
    $wys = [float]$rozmiar.Height
    $szary = New-Object System.Drawing.SolidBrush($script:KolSzary); $pedzle += $szary
    $wSrodku = New-Object System.Drawing.StringFormat
    $wSrodku.Alignment = [System.Drawing.StringAlignment]::Center
    $wSrodku.LineAlignment = [System.Drawing.StringAlignment]::Center

    if ((-not $st) -or ($st.DniZDanymi -eq 0)) {
      $tekst = "Brak danych do wykresu."
      if ($st -and $st.Uwaga) { $tekst = $st.Uwaga }
      $g.DrawString($tekst, $script:CzZwykla, $szary, (New-Object System.Drawing.RectangleF(24, 0, ($szer - 48), $wys)), $wSrodku)
      return
    }

    $lewy = [float]54; $prawy = [float]6; $gora = [float]10; $dol = [float]22
    $w = $szer - $lewy - $prawy
    $h = $wys - $gora - $dol
    $skala = Skala-Wykresu $st
    $siatka = New-Object System.Drawing.Pen($script:KolSiatki); $piora += $siatka
    $os = New-Object System.Drawing.Pen($script:KolOsi); $piora += $os
    $doPrawej = New-Object System.Drawing.StringFormat
    $doPrawej.Alignment = [System.Drawing.StringAlignment]::Far
    $doPrawej.LineAlignment = [System.Drawing.StringAlignment]::Center
    foreach ($f in @(0.5, 1.0)) {
      $y = $gora + $h - [float]($h * $f)
      $g.DrawLine($siatka, [float]$lewy, [float]$y, [float]($lewy + $w), [float]$y)
      $g.DrawString((Etykieta-Osi ($skala * $f)), $script:CzMala, $szary, (New-Object System.Drawing.RectangleF(0, ($y - 9), ($lewy - 6), 18)), $doPrawej)
    }
    $g.DrawString("0", $script:CzMala, $szary, (New-Object System.Drawing.RectangleF(0, ($gora + $h - 9), ($lewy - 6), 18)), $doPrawej)

    $kolory = @{ Zwykle = $script:KolSlupek; Nieznane = $script:KolNiezn; Nadrabianie = $script:KolNadrab }
    $pedzelDla = @{}
    foreach ($klucz in @($kolory.Keys)) {
      $p = New-Object System.Drawing.SolidBrush($kolory[$klucz]); $pedzle += $p; $pedzelDla[$klucz] = $p
    }
    $dni = @($st.Dni)
    $n = $dni.Count
    $slot = $w / $n
    $bw = [float][math]::Max(3, $slot * 0.62)
    for ($i = 0; $i -lt $n; $i++) {
      $d = $dni[$i]
      $x = [float]($lewy + $i * $slot + ($slot - $bw) / 2)
      $podstawa = $gora + $h
      foreach ($pole in @("Zwykle", "Nieznane", "Nadrabianie")) {
        $ile = [double]$d.$pole / $script:WykresDz
        if ($ile -le 0) { continue }
        $hh = [float]($h * $ile / $skala)
        if ($hh -lt 1) { $hh = [float]1 }   # dzien z kosztem ma byc widoczny, choc maly
        $g.FillRectangle($pedzelDla[$pole], $x, [float]($podstawa - $hh), $bw, $hh)
        $podstawa = $podstawa - $hh
      }
      if ((($n - 1 - $i) % 7) -eq 0) {
        $g.DrawString($d.Dzien.ToString('dd.MM'), $script:CzMala, $szary,
          (New-Object System.Drawing.RectangleF(($x + $bw / 2 - 24), ($gora + $h + 3), 48, 16)), $wSrodku)
      }
    }
    $g.DrawLine($os, [float]$lewy, [float]($gora + $h), [float]($lewy + $w), [float]($gora + $h))

    if (Prog-Widoczny $st) {
      $y = $gora + $h - [float]($h * [double]$st.Prog / $script:WykresDz / $skala)
      $prog = New-Object System.Drawing.Pen($script:KolPilne); $piora += $prog
      $prog.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
      $g.DrawLine($prog, [float]$lewy, [float]$y, [float]($lewy + $w), [float]$y)
      $czerwony = New-Object System.Drawing.SolidBrush($script:KolPilne); $pedzle += $czerwony
      $nad = New-Object System.Drawing.StringFormat
      $nad.Alignment = [System.Drawing.StringAlignment]::Far
      $g.DrawString("tu zaczyna się drogo", $script:CzMala, $czerwony, (New-Object System.Drawing.RectangleF($lewy, ($y - 16), $w, 16)), $nad)
    }
  } catch {
    if (-not $script:RysowanieZawiodlo) { $script:RysowanieZawiodlo = $true; Zanotuj-Wywrotke "rysowanie wykresu" $_ }
  } finally {
    foreach ($p in $pedzle) { try { $p.Dispose() } catch { Notuj "nie zwolnilem pedzla wykresu" } }
    foreach ($p in $piora) { try { $p.Dispose() } catch { Notuj "nie zwolnilem piora wykresu" } }
  }
}

function Wstaw-Wykres($gospodarz, $st) {
  if ($st -and ($st.DniZDanymi -gt 0) -and $script:JestChart -and (-not $script:ChartZawiodl)) {
    try {
      $ch = Nowy-Chart $st
      $ch.Dock = [System.Windows.Forms.DockStyle]::Fill
      $gospodarz.Controls.Add($ch)
      return
    } catch {
      # Cisza jest zakazana: wywrotka kontrolki nie znika - idzie do dziennika
      # i do szczegolow (Opis-Rysownika), a okno rysuje slupki samo.
      $script:ChartZawiodl = $true
      $script:PowodBezChart = "kontrolka Chart się wywróciła: $($_.Exception.Message)"
      Zanotuj-Wywrotke "wykres przez kontrolke Chart - dalej rysuje slupki sam" $_
    }
  }
  $pb = New-Object System.Windows.Forms.PictureBox
  $pb.Dock = [System.Windows.Forms.DockStyle]::Fill
  $pb.BackColor = [System.Drawing.Color]::White
  $pb.Add_Paint({ param($nadawca, $e) Rysuj-Slupki $e.Graphics $nadawca.ClientSize $script:StatWykresu })
  $pb.Add_Resize({ param($nadawca, $e) $nadawca.Invalidate() })
  $gospodarz.Controls.Add($pb)
}

# Znacznik dla nadzorca.ps1: ten plik wczytal sie do konca.
$script:ModulyOkna["wykres"] = $true
