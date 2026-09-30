# zasobnik\nadzorca\ladowanie.ps1 - czesc zasobnik\nadzorca.ps1 (patrz BUDOWA
# w jego naglowku). Ekran ladowania na miejscu zakladki bez kompletu danych z dzis:
# budowa (Zbuduj-Ladowanie, Wiersz-Kroku, pasek postepu), pokazanie i zdjecie
# (Pokaz-Ladowanie, Ukryj-Ladowanie), odmalowanie krokow co 150 ms (Odmaluj-Kroki),
# koniec po bledzie (Sprawdz-Ladowanie) i straznik z limitem (Straznik-Ladowania),
# plus obszar ekranu pod oknem (Obszar-Okna).
# Skad wolane: w-tle.ps1 (Wejdz-Do-Widoku, Obsluz-Kroki, zegar krokow) i okno.ps1.
# Wczytuje go nadzorca.ps1 kropka po zamku jednej kopii - poza znakami krokow
# ($ZNAK_*) same definicje.

# --- ekran ladowania -----------------------------------------------------------
# Biala karta na miejscu zakladki: tytul, jedno zdanie, pasek postepu i lista
# krokow - kazdy z kolkiem (czeka), obracajacym sie znakiem (liczy), ptaszkiem
# (gotowe), wykrzyknikiem (gotowe z powodem) albo krzyzykiem (nie udalo sie / po
# limicie), z czasem po prawej i powodem po ludzku pod spodem. Wiersze maja stale
# wymiary - zmienia sie tylko tekst, wiec nic nie skacze.
$ZNAK_CZEKA = [string][char]0x25CB
$ZNAKI_LICZY = @([string][char]0x25D0, [string][char]0x25D3, [string][char]0x25D1, [string][char]0x25D2)
$ZNAK_OK = [string][char]0x2713
$ZNAK_BLAD = [string][char]0x2717

function Zbuduj-Ladowanie {
  $p = New-Object System.Windows.Forms.Panel
  $p.Dock = [System.Windows.Forms.DockStyle]::Fill
  $p.AutoScroll = $true
  $p.BackColor = $script:TloOkna
  $p.Padding = New-Object System.Windows.Forms.Padding($script:Margines, 4, $script:Margines, 8)
  $p.Visible = $false
  $root = Pionowy $script:SzerTresc
  $root.Dock = [System.Windows.Forms.DockStyle]::Top
  $karta = Nowa-Karta $script:SzerKarty
  $karta.Padding = New-Object System.Windows.Forms.Padding(28, 22, 28, 22)
  $szer = $script:SzerKarty - 56
  $script:LLadowanieTytul = Etykieta "Wczytuję dane" $script:CzTytul $script:KolTekst
  $script:LLadowanieOpis = Etykieta-Zawijana "" $script:CzZwykla $script:KolSzary $szer
  $script:LLadowanieOpis.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
  $script:PasekLadowania = New-Object System.Windows.Forms.PictureBox
  $script:PasekLadowania.Size = New-Object System.Drawing.Size($szer, 8)
  $script:PasekLadowania.Margin = New-Object System.Windows.Forms.Padding(0, 16, 0, 18)
  $script:PasekLadowania.Add_Paint({ param($nadawca, $e) Rysuj-Pasek-Ladowania $e.Graphics $nadawca.ClientSize })
  $script:ListaKrokow = Pionowy $szer
  $script:LLadowanieStopka = Etykieta-Zawijana "" $script:CzMala $script:KolSzary $szer
  $script:LLadowanieStopka.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
  $script:BPokazTeraz = New-Object System.Windows.Forms.Button
  $script:BPokazTeraz.Text = "Pokaż od razu"
  $script:BPokazTeraz.Font = $script:CzZwykla
  $script:BPokazTeraz.FlatStyle = [System.Windows.Forms.FlatStyle]::System
  $script:BPokazTeraz.Size = New-Object System.Drawing.Size(160, 32)
  $script:BPokazTeraz.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
  $script:BPokazTeraz.Visible = $false
  $script:BPokazTeraz.Add_Click({
    try { if ($script:Ladowanie) { $script:Ladowanie.Od_Razu = $true; Sprawdz-Ladowanie } }
    catch { Zanotuj-Wywrotke "przycisk Pokaz od razu" $_ }
  })
  foreach ($c in @($script:LLadowanieTytul, $script:LLadowanieOpis, $script:PasekLadowania, $script:ListaKrokow, $script:LLadowanieStopka, $script:BPokazTeraz)) { $karta.Controls.Add($c) }
  $root.Controls.Add($karta)
  $p.Controls.Add($root)
  return $p
}

function Rysuj-Pasek-Ladowania($g, $rozmiar) {
  try {
    $w = [int]$rozmiar.Width; $h = [int]$rozmiar.Height
    $tlo = New-Object System.Drawing.SolidBrush($script:KolCc)
    $pel = New-Object System.Drawing.SolidBrush($script:KolMr)
    try {
      $g.FillRectangle($tlo, 0, 0, $w, $h)
      $g.FillRectangle($pel, 0, 0, [int]($w * [math]::Min(1.0, [math]::Max(0.0, $script:PostepLadowania))), $h)
    } finally { $tlo.Dispose(); $pel.Dispose() }
  } catch {
    if (-not $script:RysowanieZawiodlo) { $script:RysowanieZawiodlo = $true; Zanotuj-Wywrotke "rysowanie paska postepu" $_ }
  }
}

function Wiersz-Kroku([string]$id, [int]$szer) {
  $kol = Pionowy $szer
  $w = Poziomy
  $z = Etykieta $ZNAK_CZEKA $script:CzGruba $script:KolSzary
  $z.AutoSize = $false; $z.Size = New-Object System.Drawing.Size(28, 26); $z.Margin = New-Object System.Windows.Forms.Padding(0)
  $n = Etykieta $KAWALKI[$id].Napis $script:CzZwykla $script:KolTekst
  $n.AutoSize = $false; $n.Size = New-Object System.Drawing.Size(($szer - 28 - 250), 26); $n.Margin = New-Object System.Windows.Forms.Padding(0)
  $n.UseMnemonic = $false
  $s = Etykieta "" $script:CzZwykla $script:KolSzary
  $s.AutoSize = $false; $s.Size = New-Object System.Drawing.Size(250, 26); $s.Margin = New-Object System.Windows.Forms.Padding(0)
  $s.TextAlign = [System.Drawing.ContentAlignment]::TopRight
  $w.Controls.Add($z); $w.Controls.Add($n); $w.Controls.Add($s)
  $d = Etykieta-Zawijana "" $script:CzMala $script:KolPilne ($szer - 28)
  $d.Margin = New-Object System.Windows.Forms.Padding(28, 0, 0, 8)
  $d.UseMnemonic = $false
  $d.Visible = $false
  $kol.Controls.Add($w); $kol.Controls.Add($d)
  $script:WierszeKrokow[$id] = @{ Znak = $z; Napis = $n; Stan = $s; Szczegol = $d }
  return $kol
}

function Pokaz-Ladowanie([string]$widok, $ids, $kroki) {
  if (-not $script:WidokLadowania -or $script:WidokLadowania.IsDisposed) { return }
  $script:Ladowanie = [pscustomobject]@{ Widok = $widok; Kawalki = @($ids); Kroki = $kroki; Od = [datetime]::Now; BladOd = $null; Od_Razu = $false }
  $szer = $script:SzerKarty - 56
  $script:WidokLadowania.SuspendLayout()
  try {
    Wyczysc-Panel $script:ListaKrokow
    $script:WierszeKrokow = @{}
    foreach ($id in $ids) { $script:ListaKrokow.Controls.Add((Wiersz-Kroku $id $szer)) }
    if ($widok -eq "przeglad") {
      if ((-not $script:DaneCzas) -or ($script:DaneCzas.Date -ne [datetime]::Today) -or (-not $script:Start)) { $o = "Pierwsze otwarcie dziś - liczę wszystko od nowa. Zwykle trwa to kilka sekund." }
      else { $o = "Części liczb nie ma jeszcze z dzisiaj - liczę je teraz. Zwykle trwa to kilka sekund." }
    } else {
      $o = "Zakładka `„$($NAZWY_WIDOKOW[$widok])`” potrzebuje danych, których jeszcze nie ma - zbieram je."
    }
    $script:LLadowanieOpis.Text = "$o Okno możesz w tym czasie przesuwać i przełączać zakładki - liczenie idzie w tle."
    $script:BPokazTeraz.Visible = $false
    Odmaluj-Kroki
    $script:WidokLadowania.Visible = $true
  } finally { $script:WidokLadowania.ResumeLayout($true) }
  Odmaluj-Podtytul
}

function Ukryj-Ladowanie {
  $script:Ladowanie = $null
  if ($script:WidokLadowania -and -not $script:WidokLadowania.IsDisposed) { $script:WidokLadowania.Visible = $false }
}

function Ustaw-Tekst($kontrolka, [string]$tekst, $kolor) {
  if ($kontrolka.Text -ne $tekst) { $kontrolka.Text = $tekst }
  if ($kolor -and ($kontrolka.ForeColor -ne $kolor)) { $kontrolka.ForeColor = $kolor }
}

function Sekundy-Ludzko([double]$s) {
  $pl = [System.Globalization.CultureInfo]::GetCultureInfo("pl-PL")
  if ($s -lt 10) { return ($s.ToString("0.0", $pl) + " s") }
  return ([int][math]::Round($s)).ToString() + " s"
}

# Odmalowanie wierszy - tylko teksty i kolory, bez przebudowy (wolane co 150 ms).
function Odmaluj-Kroki {
  $l = $script:Ladowanie
  if (-not $l) { return }
  $script:TykKrokow++
  $teraz = [datetime]::Now
  $suma = 0.0
  foreach ($id in $l.Kawalki) {
    $r = $script:WierszeKrokow[$id]
    if (-not $r) { continue }
    $k = $l.Kroki[$id]
    $szczegol = ""
    if (-not $k) {
      $c = Czas-Kawalka $id
      Ustaw-Tekst $r.Znak $ZNAK_OK $script:KolDobrze
      Ustaw-Tekst $r.Stan $(if ($c) { "gotowe wcześniej (z $($c.ToString('HH:mm')))" } else { "gotowe" }) $script:KolSzary
      $suma += 1.0
    } else {
      switch ($k.Stan) {
        "czeka" { Ustaw-Tekst $r.Znak $ZNAK_CZEKA $script:KolSzary; Ustaw-Tekst $r.Stan "czeka na swoją kolej" $script:KolSzary }
        { ($_ -eq "otwiera") -or ($_ -eq "liczy") } {
          $s = 0.0; if ($k.Od) { $s = ($teraz - $k.Od).TotalSeconds }
          Ustaw-Tekst $r.Znak $ZNAKI_LICZY[[int]([math]::Floor($script:TykKrokow / 2)) % 4] $script:KolMr
          Ustaw-Tekst $r.Stan "liczę... $(Sekundy-Ludzko $s)" $script:KolTekst
          $zw = [double]$KAWALKI[$id].Zwykle
          if ($script:CzasyKrokow.ContainsKey($id)) { $zw = [math]::Max(0.5, [double]$script:CzasyKrokow[$id]) }
          $suma += [math]::Min(0.9, $s / (1.5 * $zw))
        }
        "ok" { Ustaw-Tekst $r.Znak $ZNAK_OK $script:KolDobrze; Ustaw-Tekst $r.Stan "gotowe ($(Sekundy-Ludzko (($k.Koniec - $k.Od).TotalSeconds)))" $script:KolSzary; $suma += 1.0 }
        "uwaga" {
          Ustaw-Tekst $r.Znak "!" $script:KolUwaga; Ustaw-Tekst $r.Stan "gotowe, ale z uwagą" $script:KolUwaga; $suma += 1.0
          $szczegol = $k.Powod
        }
        "blad" { Ustaw-Tekst $r.Znak $ZNAK_BLAD $script:KolPilne; Ustaw-Tekst $r.Stan "nie udało się" $script:KolPilne; $suma += 1.0; $szczegol = $k.Powod }
        "czas" { Ustaw-Tekst $r.Znak $ZNAK_BLAD $script:KolPilne; Ustaw-Tekst $r.Stan "przerwane po $($k.Limit) s" $script:KolPilne; $suma += 1.0; $szczegol = $k.Powod }
      }
    }
    if ($szczegol) {
      $kolS = $script:KolPilne; if ($k.Stan -eq "uwaga") { $kolS = $script:KolUwaga }
      Ustaw-Tekst $r.Szczegol ((Z-Wielkiej $szczegol).TrimEnd('.') + ".") $kolS
      if (-not $r.Szczegol.Visible) { $r.Szczegol.Visible = $true }
    } elseif ($r.Szczegol.Visible) { $r.Szczegol.Visible = $false }
  }
  $n = [math]::Max(1, @($l.Kawalki).Count)
  $p = $suma / $n
  if ([math]::Abs($p - $script:PostepLadowania) -gt 0.001) { $script:PostepLadowania = $p; $script:PasekLadowania.Invalidate() }
  if ($l.BladOd) {
    $zostalo = [int][math]::Max(0.0, [math]::Ceiling([double]$SEKUNDY_PO_BLEDZIE - ($teraz - $l.BladOd).TotalSeconds))
    Ustaw-Tekst $script:LLadowanieStopka "Nie wszystko się udało - powód stoi przy kroku wyżej. Resztę pokażę za $([math]::Max(0, $zostalo)) s; ten sam powód zostanie w karcie i w zakładce Szczegóły." $script:KolUwaga
  } else {
    $lim = ($l.Kawalki | ForEach-Object { $KAWALKI[$_].Limit } | Measure-Object -Maximum).Maximum
    Ustaw-Tekst $script:LLadowanieStopka "Żaden krok nie liczy się bez końca: najdłużej po $lim s przerywam go i piszę tu, dlaczego." $script:KolSzary
  }
}

# Czy ekran ladowania moze zejsc: wszystkie kroki tej zakladki skonczone. Gdy ktorys
# sie nie udal, ekran stoi jeszcze $SEKUNDY_PO_BLEDZIE s (albo do "Pokaz od razu").
# Karty buduja sie POD ekranem ladowania i dopiero potem on znika - jedno odmalowanie.
function Sprawdz-Ladowanie {
  $l = $script:Ladowanie
  if (-not $l) { return }
  Odmaluj-Kroki
  $zle = $false
  foreach ($id in $l.Kawalki) {
    $k = $l.Kroki[$id]
    if (-not $k) { continue }
    if (Krok-Trwa $k) { return }
    if ($k.Stan -ne "ok") { $zle = $true }
  }
  if ($zle) {
    if (-not $l.BladOd) {
      $l.BladOd = [datetime]::Now
      $script:BPokazTeraz.Visible = $true
      Odmaluj-Kroki
      return
    }
    if ((-not $l.Od_Razu) -and ((([datetime]::Now) - $l.BladOd).TotalSeconds -lt $SEKUNDY_PO_BLEDZIE)) { return }
  }
  $w = $l.Widok
  if ($w -eq $script:Widok) { Wyrenderuj-Widok $w }
  Ukryj-Ladowanie
  Odmaluj-Podtytul
}

# Ostatnia deska ratunku: ekran ladowania, ktory stoi dluzej niz najdluzszy limit
# jego krokow + czas na przeczytanie bledu + 15 s zapasu, zdejmujemy sila - cos
# poszlo nie tak w samym oknie (np. wywrotka w Obsluz-Kroki przy kazdym tyknieciu).
# Nie po cichu: wywrotka do dziennika i zolta karta "nie udalo sie przeliczyc".
function Straznik-Ladowania {
  $l = $script:Ladowanie
  if (-not $l) { return }
  $lim = ($l.Kawalki | ForEach-Object { $KAWALKI[$_].Limit } | Measure-Object -Maximum).Maximum + $SEKUNDY_PO_BLEDZIE + 15
  $minelo = ([datetime]::Now - $l.Od).TotalSeconds
  if ($minelo -le $lim) { return }
  $pw = "ekran ładowania stał ponad $lim s, więc zdjąłem go awaryjnie - część liczb może być niepełna (szczegóły w dzienniku nadzorcy)"
  Zanotuj-Wywrotke "ekran ladowania" $pw
  $script:DaneBlad = $pw
  Ukryj-Ladowanie
  try { Wyrenderuj-Widok $script:Widok } catch { Zanotuj-Wywrotke "odmalowanie po zdjeciu ekranu ladowania" $_ }
}

# Ekran pod kursorem - tam jest ikona, ktora wlasnie kliknieto.
function Obszar-Okna {
  try { return [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea }
  catch { Zanotuj-Wywrotke "ekran pod kursorem" $_; return [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea }
}

# Znacznik dla nadzorca.ps1: ten plik wczytal sie do konca.
$script:ModulyOkna["ladowanie"] = $true
