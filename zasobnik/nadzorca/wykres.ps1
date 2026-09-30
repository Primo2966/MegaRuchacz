# zasobnik\nadzorca\wykres.ps1 - czesc zasobnik\nadzorca.ps1 (patrz BUDOWA
# w jego naglowku). Wykres nauki z 30 dni: skala i prog liczone raz
# (Ustaw-Miare-Wykresu, Skala-Wykresu, Prog-Widoczny), kontrolka Chart z .NET
# (Nowy-Chart) albo wlasne slupki w Paint (Rysuj-Slupki), gdy Chart zawiodl,
# wstawienie jednego z nich do karty (Wstaw-Wykres) i caly panel wykresu z liczbami
# obok, legenda i progiem (Panel-Wykresu, Liczba-Boczna, Znak-Legendy). Czy Chart
# sie zaladowal, ustala start nadzorca.ps1 ($script:JestChart, Opis-Rysownika).
# Skad wolane: Karta-Sekcji w karty.ps1 (element "wykres" karty "Koszt czytania
# rozmow" w Szczegolach - od P35; do tego dnia wykres stal na Przegladzie).
# Wczytuje go nadzorca.ps1 kropka po zamku jednej kopii - tu sa same definicje.

# --- wykres ------------------------------------------------------------------
# Te same dane rysuja dwie drogi: kontrolka Chart (gdy sie zaladowala) albo
# wlasne slupki w Paint. Skala i prog sa liczone RAZ, tutaj, zeby obie drogi
# pokazywaly dokladnie to samo.

# Gorna granica osi: najwyzszy slupek plus zapas, zaokraglona do "ladnej" liczby.
# Prog zwyklego dnia wchodzi do skali tylko wtedy, gdy jest najwyzej dwa razy
# wyzej niz najwyzszy slupek - inaczej zgniotlby wszystkie slupki do kresek,
# a legenda mowi wtedy wprost, ze prog jest daleko ponad nimi.
# MIARA OSI. $script:WykresDz to dzielnik "tokeny -> jednostka osi". Ustawia go
# Panel-Wykresu przed rysowaniem; skala zwracana jest juz w tej jednostce.
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

# --- panel wykresu z liczbami obok (P35, 30.09.2026) ---------------------------
# Do P35 to byla karta Przegladu - dalszy ciag karty nauki (Odmaluj-Statystyke).
# Przeglad przestal sie miescic bez przewijania (karta "Stan" byla pod spodem),
# wiec wykres razem z liczbami obok, legenda i progiem przeszedl do Szczegolow:
# wlasna karta sekcji "Koszt czytania rozmow - ostatnie 30 dni" (tytul daje karta,
# ten panel - reszte). Na Przegladzie zostala karta nauki z liczba tokenow.
# $st = Statystyka-Okna, $szer = szerokosc wnetrza karty sekcji.
function Liczba-Boczna($panel, [string]$podpis, [string]$wartosc) {
  $panel.Controls.Add((Etykieta $podpis $script:CzMala $script:KolSzary))
  $w = Etykieta $wartosc $script:CzSrednia $script:KolTekst
  $w.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
  $panel.Controls.Add($w)
}

function Znak-Legendy($panel, $kolor, [string]$napis) {
  $kw = New-Object System.Windows.Forms.Panel
  $kw.Size = New-Object System.Drawing.Size(10, 10)
  $kw.BackColor = $kolor
  $kw.Margin = New-Object System.Windows.Forms.Padding(0, 5, 6, 0)
  $panel.Controls.Add($kw)
  $t = Etykieta $napis $script:CzMala $script:KolSzary
  $t.Margin = New-Object System.Windows.Forms.Padding(0, 2, 14, 0)
  $panel.Controls.Add($t)
}

function Panel-Wykresu($st, [int]$szer) {
  $p = Pionowy $szer
  # Rysuj-Slupki (Paint) siega wylacznie po $script: - tu odkladamy dane wykresu.
  $script:StatWykresu = $st
  Ustaw-Miare-Wykresu
  if (-not $st) {
    $p.Controls.Add((Etykieta-Zawijana "Statystyki nie udało się złożyć - powód jest w dzienniku nadzorcy." $script:CzZwykla $script:KolUwaga $szer))
    return $p
  }

  $wiersz = Poziomy
  $wiersz.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
  $gospodarz = New-Object System.Windows.Forms.Panel
  # 130 px - jak na Przegladzie (P17), zeby wykres wygladal tak samo jak dotad.
  $gospodarz.Size = New-Object System.Drawing.Size(($szer - 340), 130)
  $gospodarz.Margin = New-Object System.Windows.Forms.Padding(0)
  $gospodarz.BackColor = [System.Drawing.Color]::White
  Wstaw-Wykres $gospodarz $st
  $wiersz.Controls.Add($gospodarz)

  # Liczby po prawej w tej samej mierze, co os: tokeny (P17). Dokladna liczba
  # drobno w podpisie, zaokraglona duzo.
  $boczne = Pionowy 300
  $boczne.Margin = New-Object System.Windows.Forms.Padding(40, 0, 0, 0)
  $boczna = {
    param([string]$podpis, $n, [string]$brak)
    if ($null -eq $n) { Liczba-Boczna $boczne $podpis $brak; return }
    Liczba-Boczna $boczne "$podpis · dokładnie $(Liczba-Ludzka $n)" "$(Tokeny-Okolo $n) tokenów"
  }
  # Trzy liczby, nie cztery (P15): srednia na dzien nauki powtarzala sume
  # podzielona przez dni i nie mowila laikowi nic nowego - stoi w wydruku -Raport.
  & $boczna "Ostatnie 7 dni" $st.Suma7 "brak danych"
  & $boczna "Ostatnie $($st.OknoDni) dni" $st.Suma30 "brak danych"
  if (($null -ne $st.Typowy) -and ($st.TypowychDni -gt 0)) {
    & $boczna "Zwykły dzień (z $($st.TypowychDni) $(Odmiana $st.TypowychDni 'dnia' 'dni' 'dni'))" $st.Typowy ""
  } else {
    Liczba-Boczna $boczne "Zwykły dzień" "jeszcze nie wiem"
  }
  $wiersz.Controls.Add($boczne)
  $p.Controls.Add($wiersz)

  if ($st.DniZDanymi -gt 0) {
    $leg = Poziomy
    $leg.Margin = New-Object System.Windows.Forms.Padding(54, 0, 0, 2)
    Znak-Legendy $leg $script:KolSlupek "zwykły dzień: rozmowy z poprzedniego dnia"
    Znak-Legendy $leg $script:KolNadrab "rozmowy z kilku dni naraz"
    if (@(@($st.Dni) | Where-Object { $_.Nieznane -gt 0 }).Count -gt 0) { Znak-Legendy $leg $script:KolNiezn "nie wiadomo, z których dni" }
  }
  # Prog "tu zaczyna sie drogo" pelnym zdaniem - w wierszu legendy, gdy sa
  # slupki (jedna linia mniej), inaczej osobno. Czerwony tylko wtedy, gdy
  # czerwona linia stoi na wykresie; gdy prog jest daleko ponad slupkami,
  # zdanie jest szare - to informacja, nie alarm.
  if ($null -ne $st.Prog) {
    $zp = Zdanie-Progu $st $script:Zuzycie
    $kolP = $script:KolSzary
    if ((Prog-Widoczny $st) -and ($st.DniZDanymi -gt 0)) { $zp = "- - czerwona linia: tu zaczyna się drogo. $zp"; $kolP = $script:KolPilne }
    elseif ($st.DniZDanymi -gt 0) { $zp = "$zp Słupki są daleko poniżej." }
    if ($st.DniZDanymi -gt 0) {
      $u = Etykieta-Zawijana $zp $script:CzMala $kolP ($szer - 54 - $leg.PreferredSize.Width - 10)
      $u.Margin = New-Object System.Windows.Forms.Padding(10, 2, 0, 0)
      $leg.Controls.Add($u)
    } else {
      $u = Etykieta-Zawijana $zp $script:CzMala $kolP $szer
      $u.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
      $p.Controls.Add($u)
    }
  }
  if ($st.DniZDanymi -gt 0) { $p.Controls.Add($leg) }
  # Uwaga o zbierajacej sie statystyce stoi pod wykresem ZAWSZE, gdy danych jest
  # malo - takze wtedy, gdy w samym wykresie jest juz jej tresc (bez danych).
  if ($st.Uwaga -and ($st.DniZDanymi -gt 0)) {
    $u = Etykieta-Zawijana $st.Uwaga $script:CzMala $script:KolSzary $szer
    $u.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    $p.Controls.Add($u)
  }
  return $p
}

# Znacznik dla nadzorca.ps1: ten plik wczytal sie do konca.
$script:ModulyOkna["wykres"] = $true
