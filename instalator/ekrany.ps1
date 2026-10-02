# instalator\ekrany.ps1 - czesc okna instalatora (patrz BUDOWA w naglowku instalator\okno.ps1).
# Okno i jego ekrany: Zbuduj-Okno (naglowek z krokami, pasek z wywrotkami, tresc, pasek
# przyciskow, nakladka z pytaniem), Pokaz-Ekran i ekrany po kolei - folder (czysty komputer),
# powitanie, wybor, podsumowanie, postep, gotowe - oraz pytanie w samym oknie (Pokaz-Pytanie)
# zamiast MessageBox: odznaczenie czesci, przerwanie instalacji.
# Skad wolane: okno.ps1 (Zbuduj-Okno, pierwszy ekran) i zdarzenia kontrolek okna. Wczytuje go
# okno.ps1 kropka - poza stanem ekranow same definicje.

$script:TYTUL_OKNA       = 'MegaRuchacz – instalacja'
$script:Ekran            = ''
$script:AkcjaAnuluj      = $null
$script:AkcjaWstecz      = $null
$script:AkcjaDalej       = $null
$script:CheckboxyModulow = @{}
$script:TagiModulow      = @{}
$script:BezZdarzen       = $false
$script:Sprawdzenie      = $null
$script:ZamykamMimoPlanu = $false
$script:PytaniePoTak     = $null
$script:PytaniePoNie     = $null
$script:PytanieModul     = ''
$script:PolePytania      = $null
$script:StanPrzyciskow   = $null
$script:CoPoChwili       = $null
$script:KomunikatOdlozenia = ''
# Po tylu sekundach bez nowej linii krok dostaje zolta uwage "od ... nic nowego" - pobranie
# modelu (496 MB) potrafi milczec minute; 90 s to dosc, zeby nie straszyc przy zwyklym kroku.
$script:SekundyCiszy     = 90

# --- okno --------------------------------------------------------------------

function Zbuduj-Okno {
  if ($script:PozaEkranem) { $f = New-Object MegaRuchacz.OknoTestowe } else { $f = New-Object System.Windows.Forms.Form }
  $f.Text = $script:TYTUL_OKNA
  $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
  $f.MaximizeBox = $false
  $f.ClientSize = New-Object System.Drawing.Size($script:SzerOkna, $script:WysOkna)
  $f.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
  $f.BackColor = $script:TloOkna
  $f.Font = $script:CzZwykla
  if ($script:PozaEkranem) {
    # Test: poza wszystkimi ekranami, bez paska zadan i bez aktywacji (OknoTestowe w okno.ps1).
    $f.Location = New-Object System.Drawing.Point(-5000, 0)
    $f.ShowInTaskbar = $false
  } else {
    $o = $script:ObszarEkranu
    $f.Location = New-Object System.Drawing.Point(($o.Left + [int](($o.Width - $f.Width) / 2)), ($o.Top + [int](($o.Height - $f.Height) / 2)))
  }
  $logo = Join-Path $script:Zrodlo 'logo.png'
  if (Test-Path -LiteralPath $logo) {
    try {
      $obraz = [System.Drawing.Image]::FromFile($logo)
      $male = New-Object System.Drawing.Bitmap($obraz, 32, 32)
      $obraz.Dispose()
      $f.Icon = [System.Drawing.Icon]::FromHandle($male.GetHicon())
    } catch { Zanotuj-Wywrotke "ikona okna z $logo" $_ }
  }

  # Naglowek: tytul z makiety, kroki instalacji, jedno zdanie o biezacym ekranie.
  $script:Naglowek = New-Object System.Windows.Forms.Panel
  $script:Naglowek.Dock = [System.Windows.Forms.DockStyle]::Top
  $script:Naglowek.Height = 104
  $script:Naglowek.BackColor = $script:TloOkna
  $script:LTytul = Etykieta $script:TYTUL_OKNA $script:CzTytul $script:KolTekst
  $script:LTytul.Location = New-Object System.Drawing.Point(($script:Margines - 3), 12)
  $script:PanelKrokow = Poziomy
  $script:PanelKrokow.Location = New-Object System.Drawing.Point($script:Margines, 52)
  $script:LPodtytul = Etykieta-Zawijana '' $script:CzZwykla $script:KolSzary ($script:SzerOkna - 2 * $script:Margines)
  $script:LPodtytul.Location = New-Object System.Drawing.Point($script:Margines, 78)
  # Wysokosc naglowka idzie za podtytulem - dwulinijkowy nie ma prawa wejsc pod tresc.
  $script:LPodtytul.Add_SizeChanged({
    param($nadawca, $e)
    try { $script:Naglowek.Height = [math]::Max(100, $nadawca.Bottom + 12) } catch { Zanotuj-Wywrotke "wysokosc naglowka" $_ }
  })
  $script:Naglowek.Controls.Add($script:LTytul)
  $script:Naglowek.Controls.Add($script:PanelKrokow)
  $script:Naglowek.Controls.Add($script:LPodtytul)

  # Czerwony pasek pod naglowkiem - tylko gdy samo okno sie potknelo (Zanotuj-Wywrotke).
  # Wywrotka okna nie znika w dzienniku: ma byc widac, ze cos poszlo nie tak.
  $script:PasekWywrotek = New-Object System.Windows.Forms.Panel
  $script:PasekWywrotek.Dock = [System.Windows.Forms.DockStyle]::Top
  $script:PasekWywrotek.BackColor = $script:TloPilne
  $script:PasekWywrotek.Padding = New-Object System.Windows.Forms.Padding($script:Margines, 8, $script:Margines, 8)
  $script:PasekWywrotek.Visible = $false
  $script:LWywrotki = Etykieta-Zawijana '' $script:CzMala $script:KolPilne ($script:SzerOkna - 2 * $script:Margines)
  $script:LWywrotki.Location = New-Object System.Drawing.Point($script:Margines, 8)
  $script:LWywrotki.Add_SizeChanged({
    param($nadawca, $e)
    try { $script:PasekWywrotek.Height = $nadawca.Bottom + 8 } catch { Zapisz-Dziennik "wysokosc paska wywrotek: $($_.Exception.Message)" }
  })
  $script:PasekWywrotek.Controls.Add($script:LWywrotki)

  # Pasek przyciskow na dole: Anuluj po lewej, Wstecz i glowny po prawej, miedzy nimi
  # jedno zdanie, dlaczego glowny jest wylaczony.
  $script:Pasek = New-Object System.Windows.Forms.Panel
  $script:Pasek.Dock = [System.Windows.Forms.DockStyle]::Bottom
  $script:Pasek.Height = 64
  $script:Pasek.BackColor = $script:TloPaska
  $script:Pasek.Add_Paint({
    param($nadawca, $e)
    try { $e.Graphics.DrawLine($script:PioroRamki, 0, 0, $nadawca.Width, 0) }
    catch { if (-not $script:RamkaZawiodla) { $script:RamkaZawiodla = $true; Zanotuj-Wywrotke "kreska nad przyciskami" $_ } }
  })
  $script:BAnuluj = Nowy-Przycisk 'Anuluj' 120
  $script:BAnuluj.Location = New-Object System.Drawing.Point($script:Margines, 15)
  $script:BDalej = Przycisk-Glowny 'Dalej' 190
  $script:BDalej.Location = New-Object System.Drawing.Point(($script:SzerOkna - $script:Margines - 190), 15)
  $script:BWstecz = Nowy-Przycisk 'Wstecz' 120
  $script:BWstecz.Location = New-Object System.Drawing.Point(($script:BDalej.Left - 12 - 120), 15)
  $xStopki = $script:Margines + 120 + 16
  $script:LStopka = Etykieta-Zawijana '' $script:CzMala $script:KolSzary ($script:BWstecz.Left - $xStopki - 12)
  $script:LStopka.Location = New-Object System.Drawing.Point($xStopki, 16)
  foreach ($c in @($script:BAnuluj, $script:BWstecz, $script:BDalej, $script:LStopka)) { $script:Pasek.Controls.Add($c) }
  # Enter = glowny przycisk ekranu, Esc = lewy (Anuluj / Przerwij / Zamknij). Schowany albo
  # wylaczony przycisk nie reaguje, wiec Enter nie przeskoczy wylaczonego "Zastosuj zmiany".
  $f.AcceptButton = $script:BDalej
  $f.CancelButton = $script:BAnuluj
  $script:BAnuluj.Add_Click({ try { if ($script:AkcjaAnuluj) { & $script:AkcjaAnuluj } } catch { Zanotuj-Wywrotke "przycisk $($script:BAnuluj.Text)" $_ } })
  $script:BWstecz.Add_Click({ try { if ($script:AkcjaWstecz) { & $script:AkcjaWstecz } } catch { Zanotuj-Wywrotke "przycisk Wstecz" $_ } })
  $script:BDalej.Add_Click({ try { if ($script:AkcjaDalej) { & $script:AkcjaDalej } } catch { Zanotuj-Wywrotke "przycisk $($script:BDalej.Text)" $_ } })

  # Tresc ekranu - przewijana tylko wtedy, gdy ekran jest za niski.
  $script:Tresc = New-Object System.Windows.Forms.Panel
  $script:Tresc.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:Tresc.AutoScroll = $true
  $script:Tresc.BackColor = $script:TloOkna
  $script:Tresc.Padding = New-Object System.Windows.Forms.Padding($script:Margines, 6, $script:Margines, 12)

  # Nakladka z pytaniem - ten sam obszar co tresc, na wierzchu (pytanie w oknie, bez MessageBox).
  $script:Nakladka = New-Object System.Windows.Forms.Panel
  $script:Nakladka.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:Nakladka.BackColor = $script:TloOkna
  $script:Nakladka.AutoScroll = $true
  $script:Nakladka.Visible = $false
  $script:Nakladka.Add_Resize({ try { Wysrodkuj-Pytanie } catch { Zanotuj-Wywrotke "wysrodkowanie pytania" $_ } })

  # WinForms dokuje od ostatnio dodanej kontrolki: wypelniajace ida PIERWSZE (nakladka na
  # samej gorze kolejnosci rysowania), potem pasek wywrotek, naglowek i przyciski.
  $f.Controls.Add($script:Nakladka)
  $f.Controls.Add($script:Tresc)
  $f.Controls.Add($script:PasekWywrotek)
  $f.Controls.Add($script:Naglowek)
  $f.Controls.Add($script:Pasek)

  $f.Add_FormClosing({
    param($nadawca, $e)
    try {
      if (($script:PlanStan -eq 'trwa') -and (-not $script:ZamykamMimoPlanu)) {
        $e.Cancel = $true
        Pytanie-O-Przerwanie $true
      }
    } catch { Zanotuj-Wywrotke "zamykanie okna" $_ }
  })
  $f.Add_FormClosed({
    try { foreach ($z in @($script:Aktywne)) { if (-not $z.Wewnetrzne) { Przerwij-Zadanie $z } } }
    catch { Zapisz-Dziennik "sprzatanie krokow przy zamknieciu: $($_.Exception.Message)" }
    Zapisz-Dziennik "okno zamkniete"
  })
  $f.Add_Shown({
    try {
      Wymus-Pokazanie $script:Okno
      if ($script:Znacznik) { [System.IO.File]::WriteAllText($script:Znacznik, "$PID $(Get-Date -Format o)") }
    } catch { Zanotuj-Wywrotke "pokazanie okna" $_ }
  })
  $script:Okno = $f
  Odswiez-Pasek-Wywrotek
}

function Odswiez-Pasek-Wywrotek {
  if (-not $script:PasekWywrotek -or $script:PasekWywrotek.IsDisposed) { return }
  if (@($script:Wywrotki).Count -eq 0) { $script:PasekWywrotek.Visible = $false; return }
  $ile = @($script:Wywrotki).Count
  $t = "Okno instalatora potknęło się: $($script:Wywrotki[$ile - 1])"
  if ($ile -gt 1) { $t += " (i jeszcze $($ile - 1) wcześniej)" }
  $t += ". Pełny zapis: $($script:Dziennik)"
  $script:LWywrotki.Text = $t
  $script:PasekWywrotek.Visible = $true
}

# Jednorazowe "zrob to za chwile" - np. przejscie do ekranu Gotowe, gdy ostatni ptaszek
# zdazy sie pokazac.
function Po-Chwili([int]$ms, [scriptblock]$co) {
  $script:CoPoChwili = $co
  $t = New-Object System.Windows.Forms.Timer
  $t.Interval = $ms
  $t.Add_Tick({
    param($nadawca, $e)
    $nadawca.Stop()
    $nadawca.Dispose()
    try { $c = $script:CoPoChwili; $script:CoPoChwili = $null; if ($c) { & $c } }
    catch { Zanotuj-Wywrotke "opoznione przejscie" $_ }
  })
  $t.Start()
}

# --- naglowek, przyciski, wspolne kawalki ---------------------------------------

function Kroki-Trybu {
  switch ($script:Tryb) {
    'pobieranie' { return @('Folder', 'Pobieranie') }
    'zmiana' { return @('Wybór', 'Podsumowanie', 'Zmiany', 'Gotowe') }
  }
  return @('Powitanie', 'Wybór', 'Podsumowanie', 'Instalacja', 'Gotowe')
}

function Indeks-Ekranu([string]$ekran) {
  $mapa = @{ powitanie = 0; wybor = 1; podsumowanie = 2; postep = 3; gotowe = 4 }
  if ($script:Tryb -eq 'pobieranie') { $mapa = @{ folder = 0; postep = 1 } }
  elseif ($script:Tryb -eq 'zmiana') { $mapa = @{ wybor = 0; podsumowanie = 1; postep = 2; gotowe = 3 } }
  return $mapa[$ekran]
}

function Ustaw-Kroki([string]$ekran) {
  Wyczysc-Panel $script:PanelKrokow
  $lista = @(Kroki-Trybu)
  $biez = Indeks-Ekranu $ekran
  for ($i = 0; $i -lt $lista.Count; $i++) {
    if ($i -gt 0) {
      $s = Etykieta '›' $script:CzZwykla $script:KolJasny
      $s.Margin = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
      $script:PanelKrokow.Controls.Add($s)
    }
    $cz = $script:CzZwykla; $kol = $script:KolJasny
    if ($i -eq $biez) { $cz = $script:CzZwyklaGruba; $kol = $script:KolMr }
    elseif ($i -lt $biez) { $kol = $script:KolSzary }
    $l = Etykieta ("{0}. {1}" -f ($i + 1), $lista[$i]) $cz $kol
    $l.Margin = New-Object System.Windows.Forms.Padding(0)
    $script:PanelKrokow.Controls.Add($l)
  }
}

function Ustaw-Podtytul([string]$t) { $script:LPodtytul.Text = $t }

# Napis = $null albo '' chowa przycisk. Akcje to bloki wolane po kliknieciu.
function Ustaw-Przyciski {
  param([string]$Anuluj = '', [string]$Wstecz = '', [string]$Dalej = '', [scriptblock]$PoAnuluj = $null, [scriptblock]$PoWstecz = $null, [scriptblock]$PoDalej = $null)
  foreach ($para in @(@($script:BAnuluj, $Anuluj), @($script:BWstecz, $Wstecz), @($script:BDalej, $Dalej))) {
    $b = $para[0]; $t = $para[1]
    $b.Visible = [bool]$t
    if ($t) { $b.Text = $t; Ustaw-Wlaczony $b $true }
  }
  $script:AkcjaAnuluj = $PoAnuluj; $script:AkcjaWstecz = $PoWstecz; $script:AkcjaDalej = $PoDalej
  $script:LStopka.Text = ''
}

function Zamknij-Okno { $script:Okno.Close() }

function Ustaw-Tekst($kontrolka, [string]$tekst, $kolor) {
  if (-not $kontrolka -or $kontrolka.IsDisposed) { return }
  if ($kontrolka.Text -ne $tekst) { $kontrolka.Text = $tekst }
  if ($kolor -and ($kontrolka.ForeColor -ne $kolor)) { $kontrolka.ForeColor = $kolor }
}

function Czas-Ludzko([double]$s) {
  if ($s -lt 60) { return "$([int][math]::Floor($s)) s" }
  return ("{0} min {1:00} s" -f [int][math]::Floor($s / 60), [int]([math]::Floor($s) % 60))
}

function Punkt([string]$tekst, $kolor = $null, [int]$szer = 0, $czcionka = $null) {
  if (-not $kolor) { $kolor = $script:KolTekst }
  if ($szer -le 0) { $szer = $script:SzerWnetrza }
  if (-not $czcionka) { $czcionka = $script:CzZwykla }
  $w = Poziomy
  $w.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 3)
  $k = Etykieta '•' $czcionka $script:KolSzary
  $k.AutoSize = $false
  $k.Size = New-Object System.Drawing.Size(16, 20)
  $k.Margin = New-Object System.Windows.Forms.Padding(0)
  $w.Controls.Add($k)
  $l = Etykieta-Zawijana $tekst $czcionka $kolor ($szer - 16)
  $l.Margin = New-Object System.Windows.Forms.Padding(0)
  $w.Controls.Add($l)
  return $w
}

function Punkt-Numer([int]$nr, [string]$gruby, [string]$tekst) {
  $szw = $script:SzerWnetrza
  $w = Poziomy
  $w.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 4)
  $n = Etykieta "$nr." $script:CzGruba $script:KolMr
  $n.AutoSize = $false
  $n.Size = New-Object System.Drawing.Size(28, 24)
  $n.Margin = New-Object System.Windows.Forms.Padding(0)
  $w.Controls.Add($n)
  $p = Pionowy ($szw - 28)
  $g = Etykieta-Zawijana $gruby $script:CzGruba $script:KolTekst ($szw - 28)
  $p.Controls.Add($g)
  if ($tekst) {
    $t = Etykieta-Zawijana $tekst $script:CzZwykla $script:KolSzary ($szw - 28)
    $p.Controls.Add($t)
  }
  $w.Controls.Add($p)
  return $w
}

function Tytul-Karty([string]$t) {
  $l = Etykieta-Zawijana $t $script:CzGruba $script:KolTekst $script:SzerWnetrza
  $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
  return $l
}

function Akapit([string]$t, $kolor = $null, $czcionka = $null) {
  if (-not $kolor) { $kolor = $script:KolSzary }
  if (-not $czcionka) { $czcionka = $script:CzZwykla }
  $l = Etykieta-Zawijana $t $czcionka $kolor $script:SzerWnetrza
  $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
  return $l
}

function Karta-Proby {
  $k = Nowa-Karta $script:SzerKarty $script:TloUwaga
  $k.Padding = New-Object System.Windows.Forms.Padding(22, 12, 22, 12)
  $t = 'Tryb próby: niczego nie zainstaluję ani nie zapiszę - skrypty pokażą tylko, co by zrobiły.'
  if ($script:Tryb -eq 'pobieranie') { $t = 'Tryb próby: programów nie zainstaluję, ale MegaRuchacza pobiorę naprawdę do wskazanego folderu - żeby dało się sprawdzić dalszą część.' }
  $l = Etykieta-Zawijana $t $script:CzZwyklaGruba $script:KolUwaga $script:SzerWnetrza
  $l.Margin = New-Object System.Windows.Forms.Padding(0)
  $k.Controls.Add($l)
  return $k
}

function Pokaz-Ekran([string]$nazwa) {
  $script:Ekran = $nazwa
  Ukryj-Pytanie
  $script:Tresc.SuspendLayout()
  try {
    Wyczysc-Panel $script:Tresc
    $script:Tresc.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
    $root = Pionowy $script:SzerTresc
    $root.Dock = [System.Windows.Forms.DockStyle]::Top
    if ($script:Proba) { $root.Controls.Add((Karta-Proby)) }
    switch ($nazwa) {
      'folder'       { Ekran-Folder $root }
      'powitanie'    { Ekran-Powitanie $root }
      'wybor'        { Ekran-Wybor $root }
      'podsumowanie' { Ekran-Podsumowanie $root }
      'postep'       { Ekran-Postep $root }
      'gotowe'       { Ekran-Gotowe $root }
    }
    $script:Tresc.Controls.Add($root)
  } finally { $script:Tresc.ResumeLayout($true) }
  Ustaw-Kroki $nazwa
  Zapisz-Dziennik "ekran: $nazwa"
}

# --- pytanie w oknie (zamiast MessageBox) ----------------------------------------

function Pokaz-Pytanie {
  param([string]$Tytul, [string[]]$Linie = @(), [string]$Pole = '', [string]$OpisPola = '', [string]$Tak = 'Tak', [string]$Nie = 'Nie',
        [scriptblock]$PoTak = $null, [scriptblock]$PoNie = $null, [bool]$TakGrozne = $false)
  $script:PytaniePoTak = $PoTak; $script:PytaniePoNie = $PoNie; $script:PolePytania = $null
  Wyczysc-Panel $script:Nakladka
  $szer = [math]::Min(640, $script:SzerTresc)
  $szw = $szer - 56
  $k = Nowa-Karta $szer
  $k.Padding = New-Object System.Windows.Forms.Padding(28, 22, 28, 22)
  $t = Etykieta-Zawijana $Tytul $script:CzSrednia $script:KolTekst $szw
  $t.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
  $k.Controls.Add($t)
  foreach ($l in @($Linie)) {
    $e = Etykieta-Zawijana $l $script:CzZwykla $script:KolTekst $szw
    $e.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
    $k.Controls.Add($e)
  }
  if ($Pole) {
    $w = Poziomy
    $w.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.AutoSize = $true
    $cb.Text = ''
    $cb.Checked = $false
    $cb.Margin = New-Object System.Windows.Forms.Padding(0, 2, 2, 0)
    $lp = Etykieta-Zawijana $Pole $script:CzZwyklaGruba $script:KolTekst ($szw - 24)
    $lp.Tag = $cb
    $lp.Cursor = [System.Windows.Forms.Cursors]::Hand
    $lp.Add_Click({ param($nadawca, $e) try { $nadawca.Tag.Checked = -not $nadawca.Tag.Checked } catch { Zanotuj-Wywrotke "pole w pytaniu" $_ } })
    $w.Controls.Add($cb)
    $w.Controls.Add($lp)
    $k.Controls.Add($w)
    $script:PolePytania = $cb
    if ($OpisPola) {
      $op = Etykieta-Zawijana $OpisPola $script:CzMala $script:KolSzary ($szw - 24)
      $op.Margin = New-Object System.Windows.Forms.Padding(22, 2, 0, 0)
      $k.Controls.Add($op)
    }
  }
  $r = Poziomy
  $r.Margin = New-Object System.Windows.Forms.Padding(0, 18, 0, 0)
  if ($TakGrozne) { $bt = Przycisk-Grozny $Tak 180 } else { $bt = Przycisk-Glowny $Tak 180 }
  $bt.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
  $bn = Nowy-Przycisk $Nie 170
  $bt.Add_Click({
    try {
      $zaz = $false
      if ($script:PolePytania) { $zaz = [bool]$script:PolePytania.Checked }
      $po = $script:PytaniePoTak
      Ukryj-Pytanie
      if ($po) { & $po $zaz }
    } catch { Zanotuj-Wywrotke "odpowiedz na pytanie (tak)" $_ }
  })
  $bn.Add_Click({
    try { $po = $script:PytaniePoNie; Ukryj-Pytanie; if ($po) { & $po } }
    catch { Zanotuj-Wywrotke "odpowiedz na pytanie (nie)" $_ }
  })
  $r.Controls.Add($bt)
  $r.Controls.Add($bn)
  $k.Controls.Add($r)
  $script:PrzyciskiPytania = @($bt, $bn)
  $script:Nakladka.Controls.Add($k)
  if (-not $script:Nakladka.Visible) {
    $script:StanPrzyciskow = @{ A = $script:BAnuluj.Enabled; W = $script:BWstecz.Enabled; D = $script:BDalej.Enabled }
  }
  foreach ($b in @($script:BAnuluj, $script:BWstecz, $script:BDalej)) { Ustaw-Wlaczony $b $false }
  # Tresc pod pytaniem schowana: Tab nie wejdzie w kontrolki pod spodem, a zrzut (DrawToBitmap
  # rysuje rodzenstwo w odwrotnej kolejnosci) pokazuje to, co widzi uzytkownik.
  if ($script:Tresc.Visible) {
    $script:PozycjaTresci = $script:Tresc.AutoScrollPosition
    $script:Tresc.Visible = $false
  }
  $script:Nakladka.Visible = $true
  $script:Nakladka.BringToFront()
  Wysrodkuj-Pytanie
  # Fokus na bezpiecznym "Nie" - przypadkowy Enter niczego nie usuwa (jak Button2 w pytaniach nadzorcy).
  [void]$bn.Select()
}

function Wysrodkuj-Pytanie {
  if (-not $script:Nakladka.Visible -or $script:Nakladka.Controls.Count -eq 0) { return }
  $k = $script:Nakladka.Controls[0]
  $x = [math]::Max($script:Margines, [int](($script:Nakladka.ClientSize.Width - $k.Width) / 2))
  $y = [math]::Max(16, [int](($script:Nakladka.ClientSize.Height - $k.Height) / 3))
  $k.Location = New-Object System.Drawing.Point($x, $y)
}

function Ukryj-Pytanie {
  if (-not $script:Nakladka -or -not $script:Nakladka.Visible) { return }
  $script:Nakladka.Visible = $false
  Wyczysc-Panel $script:Nakladka
  $script:PrzyciskiPytania = $null
  $script:Tresc.Visible = $true
  if ($script:PozycjaTresci) {
    $script:Tresc.AutoScrollPosition = New-Object System.Drawing.Point((-$script:PozycjaTresci.X), (-$script:PozycjaTresci.Y))
    $script:PozycjaTresci = $null
  }
  if ($script:StanPrzyciskow) {
    Ustaw-Wlaczony $script:BAnuluj $script:StanPrzyciskow.A
    Ustaw-Wlaczony $script:BWstecz $script:StanPrzyciskow.W
    Ustaw-Wlaczony $script:BDalej $script:StanPrzyciskow.D
    $script:StanPrzyciskow = $null
  }
}

function Pytanie-O-Przerwanie([bool]$zamknij) {
  $tak = 'Przerwij'
  if ($zamknij) { $tak = 'Przerwij i zamknij' }
  $script:PrzerwijIZamknij = $zamknij
  Pokaz-Pytanie -Tytul 'Przerwać instalację?' -Linie @(
      'Bieżący krok zostanie przerwany w połowie, a dalsze się nie wykonają.',
      'Nic się nie zepsuje - instalator możesz uruchomić później jeszcze raz i dokończyć.') `
    -Tak $tak -Nie 'Wróć do instalacji' -TakGrozne $true -PoTak {
      param($zaz)
      if ($script:PrzerwijIZamknij) { $script:ZamykamMimoPlanu = $true }
      Przerwij-Plan
      if ($script:PrzerwijIZamknij) { Zamknij-Okno }
    }
}

# --- ekran: folder (czysty komputer) ------------------------------------------

# Zwraca zdanie bledu (Blad) albo pusty blad i zdanie informacji (Info).
function Ocen-Folder([string]$f) {
  $f = "$f".Trim()
  if (-not $f) { return @{ Blad = 'Podaj folder.'; Info = '' } }
  if ($f -notmatch '^[A-Za-z]:\\') { return @{ Blad = 'Podaj pełną ścieżkę folderu na dysku, np. C:\Users\Ty\MegaRuchacz.'; Info = '' } }
  try { $f = [System.IO.Path]::GetFullPath($f) } catch { return @{ Blad = "Tej ścieżki nie da się użyć: $($_.Exception.Message)"; Info = '' } }
  if ($f.Length -gt 150) { return @{ Blad = 'Ta ścieżka jest za długa - wybierz krótszą (najwyżej 150 znaków), bo niektóre pliki MegaRuchacza mają długie nazwy.'; Info = '' } }
  $kor = [System.IO.Path]::GetPathRoot($f)
  if (-not (Test-Path -LiteralPath $kor)) { return @{ Blad = "Nie ma dysku $kor na tym komputerze."; Info = '' } }
  if (Test-Path -LiteralPath $f -PathType Leaf) { return @{ Blad = 'Pod tą ścieżką jest plik, a nie folder.'; Info = '' } }
  if (Test-Path -LiteralPath $f) {
    if ((Test-Path -LiteralPath (Join-Path $f '.git')) -and (Test-Path -LiteralPath (Join-Path $f 'narzedzia\straznik-zasad.ps1'))) {
      return @{ Blad = ''; Info = 'W tym folderze już jest MegaRuchacz - użyję go i nie będę pobierał drugi raz.' }
    }
    $cos = @(Get-ChildItem -LiteralPath $f -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($cos.Count -gt 0) { return @{ Blad = 'Ten folder nie jest pusty. Wybierz pusty albo nowy folder (np. dopisz na końcu \MegaRuchacz).'; Info = '' } }
    return @{ Blad = ''; Info = 'Folder jest pusty - MegaRuchacz trafi właśnie tam.' }
  }
  return @{ Blad = ''; Info = 'Folder zostanie utworzony.' }
}

function Sprawdz-Folder {
  if (-not $script:PoleFolderu -or $script:PoleFolderu.IsDisposed) { return }
  $o = Ocen-Folder $script:PoleFolderu.Text
  if ($o.Blad) { Ustaw-Tekst $script:LFolderInfo $o.Blad $script:KolPilne }
  else { Ustaw-Tekst $script:LFolderInfo $o.Info $script:KolSzary }
  Ustaw-Wlaczony $script:BDalej (-not $o.Blad)
}

function Ekran-Folder($root) {
  Ustaw-Podtytul 'MegaRuchacz potrzebuje własnego folderu - stamtąd będzie się sam aktualizował.'
  $szw = $script:SzerWnetrza
  $k = Nowa-Karta $script:SzerKarty
  $t = Etykieta-Zawijana 'Gdzie zainstalować MegaRuchacza?' $script:CzSrednia $script:KolTekst $szw
  $t.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
  $k.Controls.Add($t)
  $k.Controls.Add((Akapit 'Wybierz folder, w którym MegaRuchacz zamieszka na stałe. Pobiorę go tam z GitHuba (ok. 9 MB) i stamtąd będzie pobierał poprawki. Nie przenoś go potem w inne miejsce - Twoje narzędzia AI będą go szukać właśnie tam.'))
  $w = Poziomy
  $w.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
  $script:PoleFolderu = New-Object System.Windows.Forms.TextBox
  $script:PoleFolderu.Font = $script:CzZwykla
  $script:PoleFolderu.Width = $szw - 130
  $script:PoleFolderu.Margin = New-Object System.Windows.Forms.Padding(0, 4, 10, 0)
  $script:PoleFolderu.Text = $script:FolderDocelowy
  $script:PoleFolderu.Add_TextChanged({ try { Sprawdz-Folder } catch { Zanotuj-Wywrotke "sprawdzenie folderu" $_ } })
  $bz = Nowy-Przycisk 'Zmień…' 120
  $bz.Margin = New-Object System.Windows.Forms.Padding(0)
  $bz.Add_Click({
    try {
      $d = New-Object System.Windows.Forms.FolderBrowserDialog
      $d.Description = 'Wybierz folder, w którym ma zamieszkać MegaRuchacz (pusty albo nowy).'
      $d.ShowNewFolderButton = $true
      $nad = Split-Path -Parent $script:PoleFolderu.Text
      if ($nad -and (Test-Path -LiteralPath $nad)) { $d.SelectedPath = $nad }
      if ($d.ShowDialog($script:Okno) -eq [System.Windows.Forms.DialogResult]::OK) {
        $wyb = $d.SelectedPath
        # Wybrany niepusty folder (np. Dokumenty) dostaje podfolder MegaRuchacz - tego zwykle chodzilo.
        if ((Ocen-Folder $wyb).Blad -and -not (Ocen-Folder (Join-Path $wyb 'MegaRuchacz')).Blad) { $wyb = Join-Path $wyb 'MegaRuchacz' }
        $script:PoleFolderu.Text = $wyb
      }
      $d.Dispose()
    } catch { Zanotuj-Wywrotke "wybor folderu" $_ }
  })
  $w.Controls.Add($script:PoleFolderu)
  $w.Controls.Add($bz)
  $k.Controls.Add($w)
  $script:LFolderInfo = Etykieta-Zawijana '' $script:CzMala $script:KolSzary $szw
  $script:LFolderInfo.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
  $k.Controls.Add($script:LFolderInfo)
  $root.Controls.Add($k)

  $k2 = Nowa-Karta $script:SzerKarty
  $k2.Controls.Add((Tytul-Karty 'Co się stanie po kliknięciu „Dalej”'))
  $k2.Controls.Add((Punkt-Numer 1 'Sprawdzę, czy jest program git.' 'Git pobiera poprawki MegaRuchacza. Jeśli go nie ma, pobiorę go sam.'))
  $k2.Controls.Add((Punkt-Numer 2 'Pobiorę MegaRuchacza do wybranego folderu.' ''))
  $k2.Controls.Add((Punkt-Numer 3 'Otworzę instalator z nowego folderu.' 'Tam wybierzesz, co chcesz mieć - do tego czasu nic poza pobraniem się nie stanie.'))
  $root.Controls.Add($k2)
  Ustaw-Przyciski -Anuluj 'Anuluj' -Dalej 'Dalej' -PoAnuluj { Zamknij-Okno } -PoDalej {
    $o = Ocen-Folder $script:PoleFolderu.Text
    if ($o.Blad) { Sprawdz-Folder; return }
    $script:FolderDocelowy = [System.IO.Path]::GetFullPath($script:PoleFolderu.Text.Trim()).TrimEnd('\')
    Uruchom-Plan (Plan-Pobierania)
  }
  Sprawdz-Folder
}

function Plan-Pobierania {
  $skrypt = Join-Path $script:KatalogInstalatora 'pobierz.ps1'
  $plan = New-Object System.Collections.ArrayList
  $a = @('-Co', 'git', '-Zrodlo', $script:Zrodlo)
  if ($script:Proba) { $a += '-Proba' }
  [void]$plan.Add((Nowe-Zadanie -Id 'git' -Napis 'Program git (pobiera poprawki MegaRuchacza)' -Plik $skrypt -Argumenty $a -Umowa $true))
  $a2 = @('-Co', 'klon', '-Folder', $script:FolderDocelowy, '-Adres', $script:ZrodloKlonu)
  [void]$plan.Add((Nowe-Zadanie -Id 'klon' -Napis "MegaRuchacz do folderu $($script:FolderDocelowy)" -Plik $skrypt -Argumenty $a2 -Umowa $true))
  [void]$plan.Add((Nowe-Zadanie -Id 'uruchom' -Napis 'Instalator z nowego folderu' -Wewnetrzne { param($z) Uruchom-Z-Klonu $z }))
  return ,$plan
}

# Ostatni krok pobierania: instalator z klonu w osobnym procesie. Udany, gdy nowe okno
# zostawi znacznik "stoje" - samo uruchomienie procesu nic nie mowi o tym, czy okno wstalo.
function Uruchom-Z-Klonu($z) {
  if ((-not $z.PSObject.Properties['Dziecko']) -or ($z.PodejscieDziecka -ne $z.Proby)) {
    $okno = Join-Path $script:FolderDocelowy 'instalator\okno.ps1'
    if (-not (Test-Path -LiteralPath $okno)) {
      return @{ Stan = 'blad'; Komunikat = "W pobranym MegaRuchaczu nie ma instalatora ($okno). Wersja na GitHubie jest starsza niż ten instalator - spróbuj później albo daj znać autorowi." }
    }
    $zn = Join-Path ([System.IO.Path]::GetTempPath()) ("MegaRuchacz-okno-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $okno, '-Znacznik', $zn)
    if ($script:Dom -ne $HOME) { $a += @('-KatalogDomowy', $script:Dom) }
    if ($script:Proba) { $a += '-Proba' }
    if ($script:KatalogSkryptow) { $a += @('-KatalogSkryptow', $script:KatalogSkryptow) }
    if ($script:PozaEkranem) { $a += '-PozaEkranem' }
    if ($script:ScenariuszDalej) { $a += @('-Scenariusz', $script:ScenariuszDalej) }
    $bl = [System.IO.Path]::GetTempFileName()
    Zwolnij-Zamek
    $linia = (@($a | ForEach-Object { Cytuj-Argument "$_" })) -join ' '
    Zapisz-Dziennik "uruchamiam instalator z klonu: powershell.exe $linia"
    $p = Start-Process -FilePath $script:PowerShellExe -ArgumentList $linia -NoNewWindow -PassThru -RedirectStandardError $bl
    $null = $p.Handle
    $z | Add-Member -NotePropertyName Dziecko -NotePropertyValue $p -Force
    $z | Add-Member -NotePropertyName PodejscieDziecka -NotePropertyValue $z.Proby -Force
    $z | Add-Member -NotePropertyName ZnacznikDziecka -NotePropertyValue $zn -Force
    $z | Add-Member -NotePropertyName BledyDziecka -NotePropertyValue $bl -Force
    $z.Kroki.Add('Nowe okno startuje...')
    return @{ Stan = 'trwa' }
  }
  if (Test-Path -LiteralPath $z.ZnacznikDziecka) {
    Remove-Item -LiteralPath $z.ZnacznikDziecka -Force -ErrorAction SilentlyContinue
    return @{ Stan = 'ok'; Komunikat = '' }
  }
  if ($z.Dziecko.HasExited) {
    $t = ''
    try { $t = ("$(Get-Content -LiteralPath $z.BledyDziecka -Raw -ErrorAction Stop)" -replace '\s+', ' ').Trim() } catch { $t = "(nie odczytałem jego błędów: $($_.Exception.Message))" }
    return @{ Stan = 'blad'; Komunikat = "Nowe okno instalatora zamknęło się od razu (kod $($z.Dziecko.ExitCode)). $t".Trim() }
  }
  if (((Get-Date) - $z.Od).TotalSeconds -gt 60) { return @{ Stan = 'blad'; Komunikat = 'Nowe okno instalatora nie pokazało się w ciągu minuty.' } }
  return @{ Stan = 'trwa' }
}

# --- ekran: powitanie --------------------------------------------------------

function Ekran-Powitanie($root) {
  Ustaw-Podtytul 'Zanim cokolwiek zmienię, pokażę podsumowanie.'
  $szw = $script:SzerWnetrza
  $k = Nowa-Karta $script:SzerKarty
  $t = Etykieta-Zawijana 'Cześć! Zainstaluję MegaRuchacza.' $script:CzSrednia $script:KolTekst $szw
  $t.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
  $k.Controls.Add($t)
  $k.Controls.Add((Akapit 'MegaRuchacz to dodatek do Twojego narzędzia AI. Pamięta, czego się o Tobie dowiedział, umie przeszukać Twoje dawne rozmowy, przy większych zadaniach rozdziela pracę między pomocników i sam dba o swoje aktualizacje.' $script:KolTekst))
  $k.Controls.Add((Akapit 'Na następnym ekranie wybierzesz, co chcesz mieć. Przed startem pokażę podsumowanie - do tego czasu nic się nie zmieni.'))
  $root.Controls.Add($k)

  $k2 = Nowa-Karta $script:SzerKarty
  $k2.Controls.Add((Tytul-Karty 'Twoje narzędzia AI'))
  $jakies = $false
  foreach ($n in $script:Narzedzia) {
    $w = Poziomy
    $w.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
    if ($n.Jest) { $jakies = $true; $zn = Etykieta $script:ZNAK_OK $script:CzZnak $script:KolDobrze }
    else { $zn = Etykieta $script:ZNAK_POMIN $script:CzZnak $script:KolJasny }
    $zn.AutoSize = $false
    $zn.Size = New-Object System.Drawing.Size(26, 24)
    $zn.Margin = New-Object System.Windows.Forms.Padding(0)
    $nz = Etykieta $n.Nazwa $script:CzZwyklaGruba $script:KolTekst
    $nz.AutoSize = $false
    $nz.Size = New-Object System.Drawing.Size(130, 24)
    $nz.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
    if ($n.Jest) { $opis = "znalezione ($($n.Slady))"; $kol = $script:KolTekst } else { $opis = 'nie znalezione'; $kol = $script:KolSzary }
    $op = Etykieta-Zawijana $opis $script:CzZwykla $kol ($szw - 156)
    $op.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
    $w.Controls.Add($zn); $w.Controls.Add($nz); $w.Controls.Add($op)
    $k2.Controls.Add($w)
  }
  $odstep = New-Object System.Windows.Forms.Panel
  $odstep.Size = New-Object System.Drawing.Size(1, 6)
  $odstep.Margin = New-Object System.Windows.Forms.Padding(0)
  $k2.Controls.Add($odstep)
  if ($jakies) { $k2.Controls.Add((Akapit 'MegaRuchacz podłączy się do każdego znalezionego narzędzia.')) }
  else { $k2.Controls.Add((Akapit 'Nie znalazłem żadnego z tych narzędzi. MegaRuchacz działa tylko razem z jednym z nich - najlepiej najpierw zainstaluj Claude Code, a potem uruchom ten instalator jeszcze raz. Możesz też iść dalej i zainstalować MegaRuchacza już teraz.' $script:KolUwaga $script:CzZwyklaGruba)) }
  $l = Etykieta-Zawijana "MegaRuchacz leży w folderze $($script:Zrodlo)." $script:CzMala $script:KolSzary $szw
  $l.Margin = New-Object System.Windows.Forms.Padding(0)
  $k2.Controls.Add($l)
  $root.Controls.Add($k2)
  Ustaw-Przyciski -Anuluj 'Anuluj' -Dalej 'Dalej' -PoAnuluj { Zamknij-Okno } -PoDalej { Pokaz-Ekran 'wybor' }
}

# --- ekran: wybor ------------------------------------------------------------

function Ekran-Wybor($root) {
  $zmiana = ($script:Tryb -eq 'zmiana')
  if ($zmiana) { Ustaw-Podtytul 'Zaznaczone jest to, co masz teraz. Odznacz, żeby usunąć - zaznacz, żeby dodać.' }
  else { Ustaw-Podtytul 'Zaznacz, co chcesz mieć. Później możesz to zmienić - wystarczy uruchomić instalator jeszcze raz.' }
  if ($script:Instalacja.blad) { $root.Controls.Add((Karta-Bledu-Rejestru)) }
  elseif ($zmiana -and ($script:Instalacja.zrodlo -eq 'domyslne')) { $root.Controls.Add((Karta-Bez-Rejestru)) }
  $szw = $script:SzerWnetrza
  $k = Nowa-Karta $script:SzerKarty
  $k.Padding = New-Object System.Windows.Forms.Padding(22, 14, 22, 8)
  # Gora karty: tytul po lewej, przelacznik zestawow po prawej.
  $g = New-Object System.Windows.Forms.Panel
  $g.Size = New-Object System.Drawing.Size($szw, 44)
  $g.Margin = New-Object System.Windows.Forms.Padding(0)
  $g.BackColor = $script:TloKarty
  $tt = 'Co zainstalować'
  if ($zmiana) { $tt = 'Co ma być zainstalowane' }
  $lt = Etykieta $tt $script:CzGruba $script:KolTekst
  $lt.Location = New-Object System.Drawing.Point(0, 8)
  $prz = New-Object System.Windows.Forms.Panel
  $prz.Size = New-Object System.Drawing.Size(282, 36)
  $prz.Location = New-Object System.Drawing.Point(($szw - 282), 0)
  $prz.BackColor = $script:TloPrzel
  $script:BWszystko = Przycisk-Przelacznika 'Wszystko' 3 136
  $script:BWlasny = Przycisk-Przelacznika 'Własny wybór' 143 136
  $script:BWszystko.Add_Click({ try { Wybierz-Zestaw 'wszystko' } catch { Zanotuj-Wywrotke "zestaw Wszystko" $_ } })
  $script:BWlasny.Add_Click({ try { Wybierz-Zestaw 'wlasny' } catch { Zanotuj-Wywrotke "zestaw Wlasny wybor" $_ } })
  $prz.Controls.Add($script:BWszystko)
  $prz.Controls.Add($script:BWlasny)
  $g.Controls.Add($lt)
  $g.Controls.Add($prz)
  $k.Controls.Add($g)
  $k.Controls.Add((Wiersz-Zawsze))
  $script:CheckboxyModulow = @{}; $script:TagiModulow = @{}; $script:PanelKopii = $null
  foreach ($id in $script:MODULY.Keys) {
    $k.Controls.Add((Wiersz-Modulu $id))
    if ($id -eq 'kopia') {
      $script:PanelKopii = Panel-Kopii
      $k.Controls.Add($script:PanelKopii)
    }
  }
  $root.Controls.Add($k)
  if ($zmiana) {
    Ustaw-Przyciski -Anuluj 'Anuluj' -Dalej 'Zastosuj zmiany' -PoAnuluj { Zamknij-Okno } -PoDalej { Pokaz-Ekran 'podsumowanie' }
  } else {
    Ustaw-Przyciski -Anuluj 'Anuluj' -Wstecz 'Wstecz' -Dalej 'Dalej' -PoAnuluj { Zamknij-Okno } -PoWstecz { Pokaz-Ekran 'powitanie' } -PoDalej { Pokaz-Ekran 'podsumowanie' }
  }
  Odswiez-Wybor
}

function Karta-Bledu-Rejestru {
  $szw = $script:SzerWnetrza
  $k = Nowa-Karta $script:SzerKarty $script:TloPilne
  $t = Etykieta-Zawijana 'Nie umiem odczytać zapisu instalacji' $script:CzZwyklaGruba $script:KolPilne $szw
  $k.Controls.Add($t)
  $k.Controls.Add((Akapit "$($script:Instalacja.blad)" $script:KolTekst))
  $k.Controls.Add((Akapit 'Dopóki ten plik jest uszkodzony, niczego nie usunę ani nie zapiszę - tak jest bezpieczniej. Mogę go odłożyć na bok (zmienię mu tylko nazwę, niczego nie kasuję) i odczytać stan od nowa.'))
  $b = Nowy-Przycisk 'Odłóż uszkodzony zapis' 220
  $script:BOdloz = $b
  $b.Add_Click({
    try {
      $nowa = Odloz-Uszkodzony-Rejestr
      Ustal-Stan-Poczatkowy
      $script:KomunikatOdlozenia = "Uszkodzony zapis odłożony jako $nowa."
      Pokaz-Ekran 'wybor'
    } catch {
      Zanotuj-Wywrotke "odlozenie uszkodzonego rejestru" $_
      Ustaw-Tekst $script:LBladRejestru "Nie udało się odłożyć pliku: $($_.Exception.Message)" $script:KolPilne
    }
  })
  $k.Controls.Add($b)
  $script:LBladRejestru = Etykieta-Zawijana '' $script:CzMala $script:KolPilne $szw
  $script:LBladRejestru.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
  $k.Controls.Add($script:LBladRejestru)
  return $k
}

function Karta-Bez-Rejestru {
  $szw = $script:SzerWnetrza
  $k = Nowa-Karta $script:SzerKarty $script:TloUwaga
  $k.Padding = New-Object System.Windows.Forms.Padding(22, 12, 22, 12)
  $k.Controls.Add((Etykieta-Zawijana 'Nie ma jeszcze zapisu, co jest zainstalowane' $script:CzZwyklaGruba $script:KolUwaga $szw))
  $t = 'Zaznaczyłem więc to, co MegaRuchacz instalował dotąd zawsze'
  if ($script:Obecne['kopia']) {
    $t += ' - razem z kopią zapasową, bo widzę ślad jej pracy.'
    if ($script:KopiaNaStart -and ($script:KopiaNaStart.Skad -eq 'dotychczasowe')) { $t += ' Jej ustawienia (dokąd, co kopiować i czego nie) wziąłem z dotychczasowego pliku ustawień - są niżej, przy kopii.' }
  } else { $t += '.' }
  $t += ' Sprawdź, czy się zgadza; po kliknięciu „Zastosuj zmiany” zapamiętam stan.'
  $l = Etykieta-Zawijana $t $script:CzZwykla $script:KolTekst $szw
  $l.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
  $k.Controls.Add($l)
  if ($script:KomunikatOdlozenia) {
    $o = Etykieta-Zawijana $script:KomunikatOdlozenia $script:CzMala $script:KolSzary $szw
    $o.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    $k.Controls.Add($o)
  }
  return $k
}

# Wiersz tabeli wyboru: [pole z nazwa | opis z makiety | znaczek stanu]. Kolumna znaczka
# ("jest", "dodam", "usunę z danymi") tylko w trybie zmiany - przy nowej instalacji opis
# dostaje cala szerokosc i nie lamie sie bez potrzeby.
function Kolumny-Wyboru {
  $znaczek = 0
  if ($script:Tryb -eq 'zmiana') { $znaczek = 112 }
  return @(200, ($script:SzerWnetrza - 200 - $znaczek), $znaczek)
}

function Nowy-Wiersz-Wyboru {
  $kol = Kolumny-Wyboru
  $t = New-Object System.Windows.Forms.TableLayoutPanel
  $t.AutoSize = $true
  $t.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
  $t.ColumnCount = 3
  $t.RowCount = 1
  $t.Margin = New-Object System.Windows.Forms.Padding(0)
  $t.Padding = New-Object System.Windows.Forms.Padding(0, 10, 0, 10)
  $t.BackColor = $script:TloKarty
  foreach ($s in $kol) { [void]$t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, $s))) }
  [void]$t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
  $t.Add_Paint({
    param($nadawca, $e)
    try { $e.Graphics.DrawLine($script:PioroRamki, 0, 0, $nadawca.Width, 0) }
    catch { if (-not $script:RamkaZawiodla) { $script:RamkaZawiodla = $true; Zanotuj-Wywrotke "kreska miedzy wierszami" $_ } }
  })
  return $t
}

function Znaczek-Stanu {
  $l = Etykieta '' $script:CzMalaGruba $script:KolSzary
  $l.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
  $l.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)
  return $l
}

function Wiersz-Zawsze {
  $kol = Kolumny-Wyboru
  $t = Nowy-Wiersz-Wyboru
  $n = Etykieta 'Zawsze:' $script:CzZwyklaGruba $script:KolTekst
  $n.Margin = New-Object System.Windows.Forms.Padding(18, 2, 0, 0)
  $d = Etykieta-Zawijana $script:ZAWSZE $script:CzZwykla $script:KolSzary ($kol[1] - 10)
  $d.Margin = New-Object System.Windows.Forms.Padding(0, 2, 10, 0)
  $s = Znaczek-Stanu
  if ($script:Tryb -eq 'zmiana') { $s.Text = 'jest' }
  $t.Controls.Add($n, 0, 0); $t.Controls.Add($d, 1, 0); $t.Controls.Add($s, 2, 0)
  return $t
}

function Wiersz-Modulu([string]$id) {
  $m = $script:MODULY[$id]
  $kol = Kolumny-Wyboru
  $t = Nowy-Wiersz-Wyboru
  $cb = New-Object System.Windows.Forms.CheckBox
  $cb.Text = $m.Nazwa
  $cb.Font = $script:CzZwyklaGruba
  $cb.ForeColor = $script:KolTekst
  $cb.AutoSize = $true
  $cb.UseMnemonic = $false
  $cb.Tag = $id
  $cb.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
  $cb.Checked = [bool]$script:Wybor.Moduly[$id]
  $cb.Add_CheckedChanged({ param($nadawca, $e) try { Po-Zmianie-Modulu $nadawca } catch { Zanotuj-Wywrotke "zaznaczenie $($nadawca.Tag)" $_ } })
  $d = Etykieta-Zawijana $m.Opis $script:CzZwykla $script:KolSzary ($kol[1] - 10)
  $d.Margin = New-Object System.Windows.Forms.Padding(0, 2, 10, 0)
  $d.Tag = $cb
  $d.Cursor = [System.Windows.Forms.Cursors]::Hand
  $d.Add_Click({ param($nadawca, $e) try { $nadawca.Tag.Checked = -not $nadawca.Tag.Checked } catch { Zanotuj-Wywrotke "klikniecie opisu" $_ } })
  $s = Znaczek-Stanu
  $t.Controls.Add($cb, 0, 0); $t.Controls.Add($d, 1, 0); $t.Controls.Add($s, 2, 0)
  $script:CheckboxyModulow[$id] = $cb
  $script:TagiModulow[$id] = $s
  return $t
}

function Panel-Kopii {
  $ws = $script:SzerWnetrza - 30
  $p = Pionowy $ws
  $p.Margin = New-Object System.Windows.Forms.Padding(30, 0, 0, 12)
  $p.BackColor = $script:TloKarty
  $p.Controls.Add((Etykieta 'Folder na kopie' $script:CzZwyklaGruba $script:KolTekst))
  $w = Poziomy
  $script:PoleCelu = New-Object System.Windows.Forms.TextBox
  $script:PoleCelu.Font = $script:CzZwykla
  $script:PoleCelu.Width = $ws - 130
  $script:PoleCelu.Margin = New-Object System.Windows.Forms.Padding(0, 4, 10, 0)
  $script:PoleCelu.Text = $script:Wybor.KopiaCel
  $script:PoleCelu.Add_TextChanged({ try { $script:Wybor.KopiaCel = $script:PoleCelu.Text; Odswiez-Kopie } catch { Zanotuj-Wywrotke "folder na kopie" $_ } })
  $bz = Nowy-Przycisk 'Zmień…' 120
  $bz.Margin = New-Object System.Windows.Forms.Padding(0)
  $bz.Add_Click({
    try {
      $d = New-Object System.Windows.Forms.FolderBrowserDialog
      $d.Description = 'Wybierz folder na kopie zapasowe (najlepiej na innym dysku albo w chmurze, np. na Dysku Google).'
      $d.ShowNewFolderButton = $true
      if (Test-Path -LiteralPath $script:PoleCelu.Text) { $d.SelectedPath = $script:PoleCelu.Text }
      if ($d.ShowDialog($script:Okno) -eq [System.Windows.Forms.DialogResult]::OK) { $script:PoleCelu.Text = $d.SelectedPath }
      $d.Dispose()
    } catch { Zanotuj-Wywrotke "wybor folderu na kopie" $_ }
  })
  $w.Controls.Add($script:PoleCelu)
  $w.Controls.Add($bz)
  $p.Controls.Add($w)
  $script:LCelInfo = Etykieta-Zawijana '' $script:CzMala $script:KolSzary $ws
  $script:LCelInfo.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
  $p.Controls.Add($script:LCelInfo)
  $l = Etykieta 'Co kopiować' $script:CzZwyklaGruba $script:KolTekst
  $l.Margin = New-Object System.Windows.Forms.Padding(0, 12, 0, 2)
  $p.Controls.Add($l)
  $script:ListaZrodel = Pionowy $ws
  foreach ($z in $script:Wybor.KopiaZrodla) { $script:ListaZrodel.Controls.Add((Wiersz-Zrodla $z $ws)) }
  $p.Controls.Add($script:ListaZrodel)
  $lk = New-Object System.Windows.Forms.LinkLabel
  $lk.Text = '+ Dodaj folder…'
  $lk.Font = $script:CzZwykla
  $lk.AutoSize = $true
  $lk.LinkColor = $script:KolMr
  $lk.ActiveLinkColor = $script:KolMrCiemny
  $lk.LinkBehavior = [System.Windows.Forms.LinkBehavior]::HoverUnderline
  $lk.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
  $lk.Add_LinkClicked({
    try {
      $d = New-Object System.Windows.Forms.FolderBrowserDialog
      $d.Description = 'Wybierz folder, który ma trafiać do kopii zapasowej.'
      if ($d.ShowDialog($script:Okno) -eq [System.Windows.Forms.DialogResult]::OK) { Dodaj-Zrodlo $d.SelectedPath }
      $d.Dispose()
    } catch { Zanotuj-Wywrotke "dodanie folderu do kopii" $_ }
  })
  $p.Controls.Add($lk)
  # Wyjatki (P59d): na komputerze z kopia sprzed rejestru przychodza z dotychczasowych ustawien
  # i maja byc widoczne - odznaczony wyjatek trafi do kopii.
  $l2 = Etykieta 'Czego nie kopiować' $script:CzZwyklaGruba $script:KolTekst
  $l2.Margin = New-Object System.Windows.Forms.Padding(0, 12, 0, 2)
  $p.Controls.Add($l2)
  $script:ListaWykluczen = Pionowy $ws
  foreach ($x in $script:Wybor.KopiaWykluczenia) { $script:ListaWykluczen.Controls.Add((Wiersz-Wykluczenia $x $ws)) }
  $script:LBrakWykluczen = Etykieta-Zawijana 'Nic nie pomijam poza tym, co kopia pomija zawsze sama: pamięć podręczną programów i pliki z hasłami.' $script:CzMala $script:KolSzary $ws
  $script:LBrakWykluczen.Visible = ($script:Wybor.KopiaWykluczenia.Count -eq 0)
  $p.Controls.Add($script:LBrakWykluczen)
  $p.Controls.Add($script:ListaWykluczen)
  $lw = New-Object System.Windows.Forms.LinkLabel
  $lw.Text = '+ Pomiń folder…'
  $lw.Font = $script:CzZwykla
  $lw.AutoSize = $true
  $lw.LinkColor = $script:KolMr
  $lw.ActiveLinkColor = $script:KolMrCiemny
  $lw.LinkBehavior = [System.Windows.Forms.LinkBehavior]::HoverUnderline
  $lw.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
  $lw.Add_LinkClicked({
    try {
      $d = New-Object System.Windows.Forms.FolderBrowserDialog
      $d.Description = 'Wybierz folder, którego kopia ma NIE obejmować.'
      if ($d.ShowDialog($script:Okno) -eq [System.Windows.Forms.DialogResult]::OK) { Dodaj-Wykluczenie $d.SelectedPath }
      $d.Dispose()
    } catch { Zanotuj-Wywrotke "dodanie wyjatku kopii" $_ }
  })
  $p.Controls.Add($lw)
  return $p
}

# Wiersz listy kopii: pole z nazwa, pod nim szarym drobnym druczkiem szczegol (sciezka albo
# powod wyjatku), wciety pod tekst pola - rowna kolumna zamiast poszarpanych linii.
function Wiersz-Z-Polem([string]$napis, [string]$pod, $obiekt, [int]$ws, [string]$co) {
  $p = Pionowy $ws
  $p.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
  $cb = New-Object System.Windows.Forms.CheckBox
  $cb.Text = $napis
  $cb.Font = $script:CzZwykla
  $cb.ForeColor = $script:KolTekst
  $cb.AutoSize = $true
  $cb.UseMnemonic = $false
  $cb.Checked = [bool]$obiekt.Zaznaczone
  $cb.Tag = $obiekt
  $cb.Margin = New-Object System.Windows.Forms.Padding(0)
  $cb.Add_CheckedChanged({ param($nadawca, $e) try { $nadawca.Tag.Zaznaczone = $nadawca.Checked; Odswiez-Kopie } catch { Zanotuj-Wywrotke "pole kopii zapasowej" $_ } })
  $p.Controls.Add($cb)
  if ($pod) {
    $l = Etykieta-Zawijana $pod $script:CzMala $script:KolSzary ($ws - 20)
    $l.Margin = New-Object System.Windows.Forms.Padding(20, 0, 0, 0)
    $p.Controls.Add($l)
  }
  return $p
}

function Wiersz-Wykluczenia($x, [int]$ws) {
  return (Wiersz-Z-Polem $x.Sciezka $x.Powod $x $ws 'wyjatek')
}

function Dodaj-Wykluczenie([string]$sciezka) {
  $s = "$sciezka".TrimEnd('\')
  if (-not $s) { return }
  foreach ($x in $script:Wybor.KopiaWykluczenia) { if ($x.Sciezka -ieq $s) { $x.Zaznaczone = $true; Pokaz-Ekran 'wybor'; return } }
  [void]$script:Wybor.KopiaWykluczenia.Add([pscustomobject]@{ Sciezka = $s; Powod = 'pominięte na Twoje życzenie'; Katalog = $true; Zaznaczone = $true })
  $script:ListaWykluczen.Controls.Add((Wiersz-Wykluczenia $script:Wybor.KopiaWykluczenia[$script:Wybor.KopiaWykluczenia.Count - 1] ($script:SzerWnetrza - 30)))
  $script:LBrakWykluczen.Visible = $false
  Odswiez-Kopie
}

function Wiersz-Zrodla($z, [int]$ws) {
  $pod = $z.Sciezka
  if ($z.Nazwa.Contains($z.Sciezka)) { $pod = '' }
  return (Wiersz-Z-Polem $z.Nazwa $pod $z $ws 'zrodlo')
}

function Dodaj-Zrodlo([string]$sciezka) {
  $s = "$sciezka".TrimEnd('\')
  if (-not $s) { return }
  foreach ($x in $script:Wybor.KopiaZrodla) { if ($x.Sciezka -ieq $s) { $x.Zaznaczone = $true; Pokaz-Ekran 'wybor'; return } }
  [void]$script:Wybor.KopiaZrodla.Add([pscustomobject]@{ Sciezka = $s; Nazwa = (Nazwa-Zrodla $s); Zaznaczone = $true })
  $script:ListaZrodel.Controls.Add((Wiersz-Zrodla $script:Wybor.KopiaZrodla[$script:Wybor.KopiaZrodla.Count - 1] ($script:SzerWnetrza - 30)))
  Odswiez-Kopie
}

function Odswiez-Kopie {
  if ($script:LCelInfo -and -not $script:LCelInfo.IsDisposed) {
    $b = Blad-Kopii
    if ($b) { Ustaw-Tekst $script:LCelInfo $b $script:KolPilne }
    else {
      $i = @()
      $cel = "$($script:Wybor.KopiaCel)".Trim()
      if ($script:DyskGoogle -and $cel.StartsWith($script:DyskGoogle, [System.StringComparison]::OrdinalIgnoreCase)) { $i += 'To folder na Dysku Google - kopie trafią do chmury.' }
      elseif ($script:KopiaNaStart -and ($script:KopiaNaStart.Skad -eq 'ostatnia') -and ($cel -ieq $script:KopiaNaStart.Cel)) { $i += 'Ten sam folder, do którego szła ostatnia kopia.' }
      if ($script:KopiaNaStart -and ($script:KopiaNaStart.Skad -eq 'dotychczasowe') -and -not (Kopia-Zmieniona)) { $i += 'To dotychczasowe ustawienia kopii - przeniosę je do zapisu instalacji bez zmian.' }
      if (-not (Test-Path -LiteralPath $cel)) { $i += 'Folder zostanie utworzony.' }
      Ustaw-Tekst $script:LCelInfo ($i -join ' ') $script:KolSzary
    }
  }
  Odswiez-Przycisk-Wyboru
}

function Odswiez-Przycisk-Wyboru {
  if ($script:Ekran -ne 'wybor') { return }
  $pow = ''
  if ($script:Instalacja.blad) { $pow = 'Najpierw odłóż uszkodzony zapis instalacji (czerwona karta wyżej).' }
  elseif ($script:Wybor.Moduly['kopia'] -and (Blad-Kopii)) { $pow = 'Popraw ustawienia kopii zapasowej.' }
  elseif (($script:Tryb -eq 'zmiana') -and ($script:Instalacja.zrodlo -eq 'plik') -and -not (Policz-Zmiany).Cokolwiek) { $pow = 'Nic nie zmieniłeś.' }
  Ustaw-Wlaczony $script:BDalej (-not $pow)
  $script:LStopka.Text = $pow
}

function Odswiez-Wybor {
  $script:BezZdarzen = $true
  try {
    foreach ($id in $script:MODULY.Keys) {
      $cb = $script:CheckboxyModulow[$id]
      if ($cb -and ($cb.Checked -ne [bool]$script:Wybor.Moduly[$id])) { $cb.Checked = [bool]$script:Wybor.Moduly[$id] }
    }
  } finally { $script:BezZdarzen = $false }
  if ($script:Tryb -eq 'zmiana') {
    foreach ($id in $script:MODULY.Keys) {
      $teraz = [bool]$script:Obecne[$id]; $chce = [bool]$script:Wybor.Moduly[$id]
      $t = ''; $kol = $script:KolSzary
      if ($teraz -and $chce) { $t = 'jest' }
      elseif ($chce) { $t = 'dodam'; $kol = $script:KolMr }
      elseif ($teraz) {
        $t = 'usunę'; $kol = $script:KolPilne
        if ($script:Wybor.UsunDane[$id]) { $t = 'usunę z danymi' }
      }
      Ustaw-Tekst $script:TagiModulow[$id] $t $kol
    }
  }
  Styl-Przelacznika $script:BWszystko ($script:Wybor.Zestaw -eq 'wszystko')
  Styl-Przelacznika $script:BWlasny ($script:Wybor.Zestaw -ne 'wszystko')
  if ($script:PanelKopii) { $script:PanelKopii.Visible = [bool]$script:Wybor.Moduly['kopia'] }
  Odswiez-Kopie
}

# [Wszystko] zaznacza wszystko i zapamietuje dotychczasowy wlasny wybor; [Wlasny wybor]
# go przywraca (razem z odpowiedziami na pytania o usuniecie - byly juz potwierdzone).
function Wybierz-Zestaw([string]$zestaw) {
  if ($zestaw -eq 'wszystko') {
    if ($script:Wybor.Zestaw -ne 'wszystko') { $script:Wybor.Wlasny = @{ Moduly = $script:Wybor.Moduly.Clone(); UsunDane = $script:Wybor.UsunDane.Clone() } }
    $script:Wybor.Zestaw = 'wszystko'
    foreach ($id in @($script:MODULY.Keys)) { $script:Wybor.Moduly[$id] = $true }
    $script:Wybor.UsunDane = @{}
  } else {
    if (($script:Wybor.Zestaw -eq 'wszystko') -and $script:Wybor.Wlasny) {
      $script:Wybor.Moduly = $script:Wybor.Wlasny.Moduly.Clone()
      $script:Wybor.UsunDane = $script:Wybor.Wlasny.UsunDane.Clone()
    }
    $script:Wybor.Zestaw = 'wlasny'
  }
  Odswiez-Wybor
}

# Odznaczenie czesci, ktora JEST zainstalowana, pyta w oknie - z polem "usun tez moje dane",
# domyslnie odznaczonym. "Zostaw" przywraca zaznaczenie.
function Po-Zmianie-Modulu($cb) {
  if ($script:BezZdarzen) { return }
  $id = "$($cb.Tag)"
  if (($script:Tryb -eq 'zmiana') -and (-not $cb.Checked) -and $script:Obecne[$id]) {
    if ($script:Instalacja.blad) {
      $script:BezZdarzen = $true
      try { $cb.Checked = $true } finally { $script:BezZdarzen = $false }
      Ustaw-Tekst $script:LBladRejestru 'Usuwanie jest wstrzymane, dopóki zapis instalacji jest uszkodzony - najpierw kliknij „Odłóż uszkodzony zapis”.' $script:KolPilne
      return
    }
    $m = $script:MODULY[$id]
    $script:PytanieModul = $id
    # Cudzyslowy „ ” w napisie w "..." trzeba poprzedzic `: PowerShell uznaje je za koniec napisu.
    $linie = @("MegaRuchacz przestanie $($m.Przestanie).", 'Usunę to dopiero po kliknięciu „Zastosuj zmiany” - do tego czasu możesz to cofnąć.')
    $dane = Opis-Danych $id
    $pole = ''; $opisPola = ''
    if ($dane) { $pole = "Usuń też moje dane: $dane"; $opisPola = 'Bez zaznaczenia dane zostają na dysku i wrócą, gdy włączysz to z powrotem.' }
    else { $linie += 'Ta część nie trzyma Twoich danych na tym komputerze - rejestr pracy i mapy zostają w folderach projektów.' }
    Pokaz-Pytanie -Tytul "Usunąć `„$($m.Nazwa)`”?" -Linie $linie -Pole $pole -OpisPola $opisPola `
      -Tak 'Usuń' -Nie 'Zostaw' -TakGrozne $true -PoTak {
        param($zaz)
        $script:Wybor.Moduly[$script:PytanieModul] = $false
        $script:Wybor.UsunDane[$script:PytanieModul] = [bool]$zaz
        $script:Wybor.Zestaw = 'wlasny'; $script:Wybor.Wlasny = $null
        Odswiez-Wybor
      } -PoNie {
        $script:Wybor.Moduly[$script:PytanieModul] = $true
        $script:Wybor.UsunDane.Remove($script:PytanieModul)
        Odswiez-Wybor
      }
    return
  }
  $script:Wybor.Moduly[$id] = [bool]$cb.Checked
  if ($cb.Checked) { $script:Wybor.UsunDane.Remove($id) }
  $script:Wybor.Zestaw = 'wlasny'; $script:Wybor.Wlasny = $null
  Odswiez-Wybor
}

# --- ekran: podsumowanie -------------------------------------------------------

function Opis-Kopii {
  $nazwy = @()
  foreach ($z in $script:Wybor.KopiaZrodla) { if ($z.Zaznaczone) { $nazwy += $z.Nazwa } }
  $t = "codziennie do $("$($script:Wybor.KopiaCel)".Trim()) (kopiuję: $($nazwy -join '; ')"
  # Bez @(): Zaznaczone-Wykluczenia oddaje tablice przecinkiem, a @() opakowaloby ja drugi raz
  # (pusta lista liczylaby sie jako 1).
  $wyk = Zaznaczone-Wykluczenia
  $ile = $wyk.Count
  if ($ile -eq 1) { $t += "; pomijam 1 miejsce" }
  elseif ($ile -gt 1) { $t += "; pomijam $ile miejsc" }
  return "$t)"
}

function Opis-W-Podsumowaniu([string]$id) {
  $n = Nazwa-Modulu $id
  if ($id -eq 'wiedza') { return "$n - codziennie ok. 40 tys. tokenów z Twojego planu na czytanie rozmów" }
  if ($id -eq 'kopia') { return "$n - $(Opis-Kopii)" }
  return $n
}

function Ekran-Podsumowanie($root) {
  Ustaw-Podtytul 'Sprawdź, co się stanie. Do kliknięcia przycisku na dole nic się nie zmieni.'
  $szw = $script:SzerWnetrza
  $zm = Policz-Zmiany
  $script:PlanDoWykonania = Zbuduj-Plan
  $brak = Brakujace-Skrypty $script:PlanDoWykonania
  $nowa = ($script:Tryb -eq 'nowy')

  # Braki na samej gorze - glowny przycisk jest przez nie wylaczony, wiec powod ma byc widac od razu.
  if ($brak.Count -gt 0) {
    $k3 = Nowa-Karta $script:SzerKarty $script:TloPilne
    $k3.Controls.Add((Etykieta-Zawijana 'Nie mogę zacząć - brakuje plików instalatora' $script:CzZwyklaGruba $script:KolPilne $szw))
    foreach ($b in $brak) { $k3.Controls.Add((Punkt $b $script:KolTekst)) }
    $k3.Controls.Add((Akapit 'Ta wersja MegaRuchacza jest niekompletna albo za stara. Pobierz nowszą i uruchom instalator jeszcze raz.' $script:KolTekst))
    $root.Controls.Add($k3)
  }

  $k = Nowa-Karta $script:SzerKarty
  $k.Controls.Add((Tytul-Karty 'Co zrobię'))
  if ($nowa) {
    $k.Controls.Add((Etykieta 'Zainstaluję' $script:CzZwyklaGruba $script:KolTekst))
    $k.Controls.Add((Punkt 'Aplikację przy zegarze i automatyczne aktualizacje (zawsze)'))
    foreach ($id in $script:MODULY.Keys) { if ($script:Wybor.Moduly[$id]) { $k.Controls.Add((Punkt (Opis-W-Podsumowaniu $id))) } }
    if (@($zm.Nie).Count -gt 0) {
      $l = Etykieta 'Nie instaluję' $script:CzZwyklaGruba $script:KolTekst
      $l.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 2)
      $k.Controls.Add($l)
      $k.Controls.Add((Punkt ((@($zm.Nie) | ForEach-Object { Nazwa-Modulu $_ }) -join ', ') $script:KolSzary))
    }
  } else {
    $grupy = @()
    if (@($zm.Dodaj).Count) { $grupy += ,@('Dodam', @($zm.Dodaj | ForEach-Object { Opis-W-Podsumowaniu $_ }), $script:KolTekst) }
    if (@($zm.Usun).Count) {
      $u = @()
      foreach ($id in $zm.Usun) {
        $dane = Opis-Danych $id
        if ($script:Wybor.UsunDane[$id] -and $dane) { $u += "$(Nazwa-Modulu $id) - razem z danymi: $dane" }
        elseif (-not $dane) { $u += (Nazwa-Modulu $id) }
        else { $u += "$(Nazwa-Modulu $id) - dane zostają na dysku" }
      }
      $grupy += ,@('Usunę', $u, $script:KolPilne)
    }
    $inne = @()
    if ($zm.KopiaZmieniona) { $inne += "Kopia zapasowa - nowe ustawienia: $(Opis-Kopii)" }
    if ($inne.Count) { $grupy += ,@('Zmienię', $inne, $script:KolTekst) }
    $bez = @($zm.Zostaje | Where-Object { -not (($_ -eq 'kopia') -and $zm.KopiaZmieniona) } | ForEach-Object { Nazwa-Modulu $_ })
    $bez = @('Aplikacja przy zegarze i automatyczne aktualizacje') + $bez
    $grupy += ,@('Bez zmian', @($bez -join ', '), $script:KolSzary)
    $pierwsza = $true
    foreach ($g in $grupy) {
      $l = Etykieta $g[0] $script:CzZwyklaGruba $script:KolTekst
      if (-not $pierwsza) { $l.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 2) }
      $pierwsza = $false
      $k.Controls.Add($l)
      foreach ($x in @($g[1])) { $k.Controls.Add((Punkt $x $g[2])) }
    }
    if (-not $zm.Cokolwiek) {
      $k.Controls.Add((Akapit 'Niczego nie instaluję ani nie usuwam - zapiszę tylko, co jest zainstalowane, żeby strażnik i aplikacja przy zegarze wiedziały, czego pilnować.' $script:KolTekst))
    }
    # Pierwszy zapis rejestru na komputerze z kopia sprzed rejestru: ustawienia kopii przechodza
    # do rejestru - ma byc napisane jakie, zeby nic nie zmienilo sie bez wiedzy uzytkownika (P59d).
    if (($script:Instalacja.zrodlo -ne 'plik') -and $script:Obecne['kopia'] -and $script:Wybor.Moduly['kopia'] -and -not $zm.KopiaZmieniona) {
      $k.Controls.Add((Akapit "Kopię zapasową zapiszę z dzisiejszymi ustawieniami: $(Opis-Kopii)." $script:KolTekst))
    }
  }
  $root.Controls.Add($k)

  $inst = Do-Instalacji $zm
  $prog = Programy-Dla $inst $nowa
  $k2 = Nowa-Karta $script:SzerKarty
  $k2.Controls.Add((Tytul-Karty 'Programy'))
  $script:LProgramy = $null; $script:ListaProgramow = $null
  if ($prog.Count -gt 0) {
    $k2.Controls.Add((Akapit "Do działania potrzebne są: $(Nazwy-Programow $prog). Tych, których brakuje, doinstaluję sam - bez uprawnień administratora." $script:KolTekst))
    $script:LProgramy = Etykieta-Zawijana "$($script:ZNAKI_TRWA[0]) Sprawdzam, które z nich już są..." $script:CzZwykla $script:KolSzary $szw
    $script:LProgramy.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
    $k2.Controls.Add($script:LProgramy)
    $script:ListaProgramow = Pionowy $szw
    $k2.Controls.Add($script:ListaProgramow)
  } else {
    $k2.Controls.Add((Akapit 'Nie trzeba doinstalowywać żadnych programów.' $script:KolTekst))
  }
  $mb = Mb-Do-Pobrania $inst
  if ($mb -gt 0) {
    $co = 'Python i biblioteki'
    if (@($inst) -contains 'lore') { $co = 'Python, biblioteki i model do wyszukiwania rozmów' }
    $l = Etykieta-Zawijana "Z internetu pobiorę do ok. $mb MB ($co) - przy wolnym łączu to potrwa." $script:CzMala $script:KolSzary $szw
    $l.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $k2.Controls.Add($l)
  }
  $root.Controls.Add($k2)


  $glowny = 'Zainstaluj'
  if (-not $nowa) { $glowny = 'Tak, zastosuj' }
  Ustaw-Przyciski -Anuluj 'Anuluj' -Wstecz 'Wstecz' -Dalej $glowny -PoAnuluj { Zamknij-Okno } -PoWstecz { Pokaz-Ekran 'wybor' } -PoDalej { Uruchom-Plan $script:PlanDoWykonania }
  if ($brak.Count -gt 0) {
    Ustaw-Wlaczony $script:BDalej $false
    $script:LStopka.Text = 'Brakuje plików instalatora - szczegóły w czerwonej karcie.'
  }
  if ($prog.Count -gt 0) { Zacznij-Sprawdzanie-Programow $prog }
}

# zaleznosci.ps1 -Akcja Sprawdz w tle - podsumowanie stoi od razu, wynik dochodzi.
function Zacznij-Sprawdzanie-Programow($programy) {
  $klucz = (@($programy) -join ',')
  if ($script:Sprawdzenie -and ($script:Sprawdzenie.Klucz -eq $klucz)) {
    if ($script:Sprawdzenie.Zadanie.Stan -ne 'trwa') { Pokaz-Wynik-Sprawdzenia }
    return
  }
  $z = Zadanie-Zaleznosci 'Sprawdz' $programy
  $script:Sprawdzenie = [pscustomobject]@{ Klucz = $klucz; Zadanie = $z }
  $z.PoKoncu = {
    param($z)
    if ($script:Sprawdzenie -and [object]::ReferenceEquals($script:Sprawdzenie.Zadanie, $z)) { Pokaz-Wynik-Sprawdzenia }
  }
  Uruchom-Zadanie $z
}

# Wynik zaleznosci.ps1 -Akcja Sprawdz. U P59b "ok" znaczy "wszystkie sa" - braki to ok:false
# z polem "brakuje", a nie awaria. Dlatego najpierw pole "brakuje" (jest = skrypt sprawdzil),
# dopiero bez niego ok/blad. Komunikat skryptu bywa techniczny ("zainstaluj: zaleznosci.ps1
# -Akcja ..."), wiec przy polu "brakuje" zdanie dla czlowieka sklada okno.
function Pokaz-Wynik-Sprawdzenia {
  if (($script:Ekran -ne 'podsumowanie') -or -not $script:LProgramy -or $script:LProgramy.IsDisposed) { return }
  $z = $script:Sprawdzenie.Zadanie
  if ($z.Stan -eq 'trwa') { return }
  Wyczysc-Panel $script:ListaProgramow
  $szw = $script:SzerWnetrza
  $script:LProgramy.Font = $script:CzZwyklaGruba
  $nazwa = { param($p) if ($script:PROGRAMY.Contains("$p")) { $script:PROGRAMY["$p"] } else { "$p" } }
  if ($z.Wynik -and $z.Wynik.PSObject.Properties['brakuje']) {
    $brak = @($z.Wynik.brakuje | Where-Object { $_ } | ForEach-Object { "$_".Trim().ToLowerInvariant() })
    $sa = @($script:Sprawdzenie.Klucz -split ',' | Where-Object { $_ -and ($brak -notcontains $_) })
    if ($brak.Count -gt 0) {
      Ustaw-Tekst $script:LProgramy "Brakuje: $((@($brak | ForEach-Object { & $nazwa $_ })) -join ', ') - doinstaluję w trakcie instalacji." $script:KolTekst
      if ($sa.Count -gt 0) { $script:ListaProgramow.Controls.Add((Punkt "Już są: $((@($sa | ForEach-Object { & $nazwa $_ })) -join ', ')" $script:KolSzary $szw)) }
    } else {
      Ustaw-Tekst $script:LProgramy 'Wszystkie potrzebne programy już są - niczego nie doinstaluję.' $script:KolTekst
    }
  } elseif (Gotowy-Stan $z.Stan) {
    $kom = "$($z.Komunikat)"
    if (-not $kom) { $kom = 'Sprawdzone.' }
    Ustaw-Tekst $script:LProgramy $kom $script:KolTekst
    $kroki = @()
    if ($z.Wynik -and $z.Wynik.PSObject.Properties['kroki']) { $kroki = @($z.Wynik.kroki | Where-Object { $_ }) }
    if ($kroki.Count -eq 0) { $kroki = @($z.Kroki) }
    foreach ($x in $kroki) { $script:ListaProgramow.Controls.Add((Punkt "$x" $script:KolSzary $szw)) }
  } else {
    Ustaw-Tekst $script:LProgramy "Nie udało się sprawdzić programów: $($z.Komunikat)" $script:KolUwaga
    $script:ListaProgramow.Controls.Add((Punkt 'Instalacja i tak spróbuje doinstalować to, czego brakuje - a jeśli się nie uda, powie dlaczego.' $script:KolSzary $szw))
  }
  foreach ($u in $z.Uwagi) { $script:ListaProgramow.Controls.Add((Punkt "$u" $script:KolUwaga $szw)) }
}

# --- ekran: postep -----------------------------------------------------------

function Uruchom-Plan($plan) {
  $script:Plan = $plan
  $script:PoPlanie = { Po-Udanym-Planie }
  $script:PoBledziePlanu = { param($z) Pokaz-Blad-Planu $z }
  foreach ($z in $plan) { $z.Stan = 'czeka' }
  Pokaz-Ekran 'postep'
  Zacznij-Plan $plan
  Odmaluj-Postep
}

function Ekran-Postep($root) {
  $szw = $script:SzerWnetrza
  $tyt = 'Instaluję MegaRuchacza'
  if ($script:Tryb -eq 'zmiana') { $tyt = 'Wprowadzam zmiany' }
  elseif ($script:Tryb -eq 'pobieranie') { $tyt = 'Pobieram MegaRuchacza' }
  Ustaw-Podtytul 'Okno możesz w tym czasie przesuwać - praca idzie w tle.'
  $k = Nowa-Karta $script:SzerKarty
  $k.Padding = New-Object System.Windows.Forms.Padding(22, 18, 22, 14)
  $script:LPostepTytul = Etykieta $tyt $script:CzSrednia $script:KolTekst
  $k.Controls.Add($script:LPostepTytul)
  $script:LPostepOpis = Etykieta-Zawijana 'Zwykle trwa to kilka minut. Każdy krok pokaże tu, co właśnie robi.' $script:CzZwykla $script:KolSzary $szw
  $script:LPostepOpis.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
  $k.Controls.Add($script:LPostepOpis)
  $script:PasekPostepu = Nowy-Pasek $szw
  $k.Controls.Add($script:PasekPostepu)
  $script:WierszeZadan = @{}
  foreach ($z in $script:Plan) { $k.Controls.Add((Wiersz-Zadania $z $szw)) }
  $root.Controls.Add($k)

  $script:KartaBledu = Nowa-Karta $script:SzerKarty $script:TloPilne
  $script:KartaBledu.Visible = $false
  $script:LBleduTytul = Etykieta-Zawijana '' $script:CzGruba $script:KolPilne $szw
  $script:LBleduTresc = Etykieta-Zawijana '' $script:CzZwykla $script:KolTekst $szw
  $script:LBleduTresc.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 6)
  $script:LBleduRada = Etykieta-Zawijana 'Kliknij „Spróbuj ponownie” - kroki, które już się udały, nie powtórzą się. Jeśli błąd wraca, zamknij okno: nic się nie zepsuje, a instalator możesz uruchomić później jeszcze raz.' $script:CzMala $script:KolSzary $szw
  $script:LBleduRada.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
  $r = Poziomy
  $script:BPonow = Przycisk-Glowny 'Spróbuj ponownie' 180
  $script:BPonow.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
  $script:BSzczegoly = Nowy-Przycisk 'Pokaż szczegóły' 160
  $script:BPonow.Add_Click({
    try {
      $script:KartaBledu.Visible = $false
      Ustaw-Przyciski -Anuluj 'Przerwij' -PoAnuluj { Pytanie-O-Przerwanie $false }
      Ponow-Plan
      Odmaluj-Postep
    } catch { Zanotuj-Wywrotke "przycisk Sprobuj ponownie" $_ }
  })
  $script:BSzczegoly.Add_Click({
    try {
      $script:PoleSzczegolow.Visible = -not $script:PoleSzczegolow.Visible
      if ($script:PoleSzczegolow.Visible) { $script:BSzczegoly.Text = 'Ukryj szczegóły' } else { $script:BSzczegoly.Text = 'Pokaż szczegóły' }
    } catch { Zanotuj-Wywrotke "przycisk Pokaz szczegoly" $_ }
  })
  $r.Controls.Add($script:BPonow)
  $r.Controls.Add($script:BSzczegoly)
  $script:PoleSzczegolow = New-Object System.Windows.Forms.TextBox
  $script:PoleSzczegolow.Multiline = $true
  $script:PoleSzczegolow.ReadOnly = $true
  $script:PoleSzczegolow.MaxLength = [int]::MaxValue
  $script:PoleSzczegolow.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
  $script:PoleSzczegolow.WordWrap = $true
  $script:PoleSzczegolow.Font = $script:CzStala
  $script:PoleSzczegolow.BackColor = $script:TloKarty
  $script:PoleSzczegolow.Size = New-Object System.Drawing.Size($szw, 180)
  $script:PoleSzczegolow.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
  $script:PoleSzczegolow.Visible = $false
  foreach ($c in @($script:LBleduTytul, $script:LBleduTresc, $script:LBleduRada, $r, $script:PoleSzczegolow)) { $script:KartaBledu.Controls.Add($c) }
  $root.Controls.Add($script:KartaBledu)

  $ld = Etykieta-Zawijana "Pełny zapis instalacji: $($script:Dziennik)" $script:CzMala $script:KolSzary $script:SzerTresc
  $ld.Margin = New-Object System.Windows.Forms.Padding(2, 0, 0, 0)
  $root.Controls.Add($ld)
  Ustaw-Przyciski -Anuluj 'Przerwij' -PoAnuluj { Pytanie-O-Przerwanie $false }
}

function Wiersz-Zadania($z, [int]$szw) {
  $kol = Pionowy $szw
  $kol.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
  $w = Poziomy
  $zn = Etykieta $script:ZNAK_CZEKA $script:CzZnak $script:KolJasny
  $zn.AutoSize = $false
  $zn.Size = New-Object System.Drawing.Size(28, 24)
  $zn.Margin = New-Object System.Windows.Forms.Padding(0)
  $n = Etykieta-Zawijana $z.Napis $script:CzZwykla $script:KolTekst ($szw - 28 - 190)
  $n.MinimumSize = New-Object System.Drawing.Size(($szw - 28 - 190), 24)
  $n.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
  $s = Etykieta '' $script:CzZwykla $script:KolSzary
  $s.AutoSize = $false
  $s.Size = New-Object System.Drawing.Size(190, 24)
  $s.TextAlign = [System.Drawing.ContentAlignment]::TopRight
  $s.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
  $w.Controls.Add($zn); $w.Controls.Add($n); $w.Controls.Add($s)
  $d = Etykieta-Zawijana '' $script:CzMala $script:KolSzary ($szw - 28)
  $d.Margin = New-Object System.Windows.Forms.Padding(28, 0, 0, 6)
  $d.Visible = $false
  $kol.Controls.Add($w)
  $kol.Controls.Add($d)
  $script:WierszeZadan[$z.Id] = @{ Znak = $zn; Napis = $n; Stan = $s; Szczegol = $d }
  return $kol
}

# Odmalowanie wierszy - tylko teksty i kolory, bez przebudowy (co 150 ms, gdy cos trwa).
function Odmaluj-Postep {
  if (($script:Ekran -ne 'postep') -or -not $script:Plan) { return }
  $teraz = Get-Date
  $kartaBledu = [bool]($script:KartaBledu -and -not $script:KartaBledu.IsDisposed -and $script:KartaBledu.Visible)
  foreach ($z in $script:Plan) {
    $r = $script:WierszeZadan[$z.Id]
    if (-not $r) { continue }
    $szcz = ''; $kolSz = $script:KolSzary
    switch ($z.Stan) {
      'czeka' { Ustaw-Tekst $r.Znak $script:ZNAK_CZEKA $script:KolJasny; Ustaw-Tekst $r.Stan 'czeka' $script:KolJasny }
      'trwa' {
        Ustaw-Tekst $r.Znak $script:ZNAKI_TRWA[[int]([math]::Floor($script:Tyk / 2)) % 4] $script:KolMr
        $s = 0.0; if ($z.Od) { $s = ($teraz - $z.Od).TotalSeconds }
        Ustaw-Tekst $r.Stan "trwa... $(Czas-Ludzko $s)" $script:KolTekst
        $szcz = 'zaczynam...'
        if ($z.Kroki.Count -gt 0) { $szcz = $z.Kroki[$z.Kroki.Count - 1] }
        $cisza = 0.0; if ($z.OstatniZnak) { $cisza = ($teraz - $z.OstatniZnak).TotalSeconds }
        if ($cisza -gt $script:SekundyCiszy) {
          $szcz = "$szcz - od $(Czas-Ludzko $cisza) nic nowego. To może być pobieranie dużego pliku; możesz poczekać albo przerwać."
          $kolSz = $script:KolUwaga
        }
      }
      'ok' {
        Ustaw-Tekst $r.Znak $script:ZNAK_OK $script:KolDobrze
        $s = 0.0; if ($z.Od -and $z.Koniec) { $s = ($z.Koniec - $z.Od).TotalSeconds }
        Ustaw-Tekst $r.Stan "gotowe ($(Czas-Ludzko $s))" $script:KolSzary
      }
      'uwaga' {
        Ustaw-Tekst $r.Znak $script:ZNAK_OK $script:KolUwaga
        Ustaw-Tekst $r.Stan 'gotowe, z uwagą' $script:KolUwaga
        $szcz = (@($z.Uwagi) -join ' · '); $kolSz = $script:KolUwaga
      }
      'pominiety' { Ustaw-Tekst $r.Znak $script:ZNAK_POMIN $script:KolSzary; Ustaw-Tekst $r.Stan 'pominięte' $script:KolSzary; $szcz = $z.Komunikat }
      # Powod bledu stoi w czerwonej karcie pod lista - w wierszu tylko wtedy, gdy karty nie ma.
      'blad' { Ustaw-Tekst $r.Znak $script:ZNAK_BLAD $script:KolPilne; Ustaw-Tekst $r.Stan 'nie udało się' $script:KolPilne; if (-not $kartaBledu) { $szcz = $z.Komunikat }; $kolSz = $script:KolPilne }
      'przerwany' { Ustaw-Tekst $r.Znak $script:ZNAK_BLAD $script:KolPilne; Ustaw-Tekst $r.Stan 'przerwane' $script:KolPilne; if (-not $kartaBledu) { $szcz = $z.Komunikat }; $kolSz = $script:KolPilne }
    }
    if ($szcz) {
      Ustaw-Tekst $r.Szczegol $szcz $kolSz
      if (-not $r.Szczegol.Visible) { $r.Szczegol.Visible = $true }
    } elseif ($r.Szczegol.Visible) { $r.Szczegol.Visible = $false }
  }
  if ($script:PasekPostepu -and -not $script:PasekPostepu.IsDisposed) {
    $p = Postep-Planu
    if ([math]::Abs($p - [double]$script:PasekPostepu.Tag) -gt 0.001) { $script:PasekPostepu.Tag = $p; $script:PasekPostepu.Invalidate() }
  }
}

function Odmaluj-Biezacy {
  if ($script:Ekran -eq 'postep') { Odmaluj-Postep; return }
  if (($script:Ekran -eq 'podsumowanie') -and $script:Sprawdzenie -and ($script:Sprawdzenie.Zadanie.Stan -eq 'trwa') -and $script:LProgramy -and -not $script:LProgramy.IsDisposed) {
    Ustaw-Tekst $script:LProgramy "$($script:ZNAKI_TRWA[[int]([math]::Floor($script:Tyk / 2)) % 4]) Sprawdzam, które z nich już są..." $script:KolSzary
  }
}

function Szczegoly-Zadania($z) {
  $l = New-Object System.Collections.Generic.List[string]
  $l.Add("Krok: $($z.Napis)")
  if ($z.Plik) { $l.Add("Skrypt: $($z.Plik) $((@($z.Argumenty) | ForEach-Object { Cytuj-Argument "$_" }) -join ' ')") }
  if ($null -ne $z.Kod) { $l.Add("Kod wyjścia: $($z.Kod)") }
  $l.Add("Podejście: $($z.Proby)")
  $l.Add('--- co napisał ---')
  $linie = @($z.Linie)
  if ($linie.Count -gt 300) { $l.Add("(pokazuję ostatnie 300 z $($linie.Count) linii)"); $linie = $linie[($linie.Count - 300)..($linie.Count - 1)] }
  foreach ($x in $linie) { $l.Add("$x") }
  if ($linie.Count -eq 0) { $l.Add('(nic)') }
  $l.Add('---')
  $l.Add("Pełny zapis instalacji: $($script:Dziennik)")
  return ($l -join "`r`n")
}

function Pokaz-Blad-Planu($z) {
  if ($script:Ekran -ne 'postep') { return }
  if ($z.Stan -eq 'przerwany') { $script:LBleduTytul.Text = "Przerwane: $($z.Napis)" }
  else { $script:LBleduTytul.Text = "Nie udało się: $($z.Napis)" }
  $kom = "$($z.Komunikat)"
  if (-not $kom) { $kom = 'Krok nie powiedział, dlaczego.' }
  $script:LBleduTresc.Text = $kom
  $script:PoleSzczegolow.Text = Szczegoly-Zadania $z
  $script:PoleSzczegolow.Visible = $false
  $script:BSzczegoly.Text = 'Pokaż szczegóły'
  $script:KartaBledu.Visible = $true
  Odmaluj-Postep
  Ustaw-Przyciski -Anuluj 'Zamknij' -PoAnuluj { Zamknij-Okno }
  try { $script:Tresc.ScrollControlIntoView($script:KartaBledu) } catch { Zapisz-Dziennik "przewiniecie do bledu: $($_.Exception.Message)" }
}

function Po-Udanym-Planie {
  Odmaluj-Postep
  Ustaw-Przyciski
  if ($script:Tryb -eq 'pobieranie') {
    Ustaw-Tekst $script:LPostepOpis 'Gotowe - instalator otworzył się z nowego folderu. To okno zaraz zniknie.' $script:KolDobrze
    Po-Chwili 1500 { Zamknij-Okno }
    return
  }
  Po-Chwili 900 { Pokaz-Ekran 'gotowe' }
}

# --- ekran: gotowe -----------------------------------------------------------

function Nazwy-Narzedzi {
  $n = @($script:Narzedzia | Where-Object { $_.Jest } | ForEach-Object { $_.Nazwa })
  if ($n.Count -eq 0) { return 'Claude Code' }
  if ($n.Count -eq 1) { return $n[0] }
  return (($n[0..($n.Count - 2)] -join ', ') + ' albo ' + $n[$n.Count - 1])
}

function Ekran-Gotowe($root) {
  $szw = $script:SzerWnetrza
  $zmiana = ($script:Tryb -eq 'zmiana')
  Ustaw-Podtytul ''
  $k = Nowa-Karta $script:SzerKarty
  $k.Padding = New-Object System.Windows.Forms.Padding(22, 18, 22, 14)
  $g = Poziomy
  $zn = Etykieta $script:ZNAK_OK $script:CzTytul $script:KolDobrze
  $zn.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
  $tyt = 'Gotowe! MegaRuchacz jest zainstalowany.'
  if ($zmiana) { $tyt = 'Gotowe! Zmiany są wprowadzone.' }
  if ($script:Proba) { $tyt = 'Próba zakończona - nic nie zostało zainstalowane ani zapisane.' }
  $t = Etykieta-Zawijana $tyt $script:CzSrednia $script:KolDobrze ($szw - 40)
  $t.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
  $g.Controls.Add($zn); $g.Controls.Add($t)
  $k.Controls.Add($g)
  $co = Etykieta 'Co teraz' $script:CzZwyklaGruba $script:KolSzary
  $co.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 0)
  $k.Controls.Add($co)
  $nr = 1
  $narz = Nazwy-Narzedzi
  if ($script:Proba) {
    $k.Controls.Add((Punkt-Numer $nr 'Nic się nie zmieniło.' "Skrypty pokazały tylko, co by zrobiły - wszystko jest w zapisie: $($script:Dziennik).")); $nr++
    $k.Controls.Add((Punkt-Numer $nr 'Żeby zainstalować naprawdę' 'uruchom instalator bez -Proba - zwykłym dwuklikiem na instaluj.bat.')); $nr++
  } else {
    $k.Controls.Add((Punkt-Numer $nr "Otwórz nowe okno $narz." 'Dopiero nowe okno rozmowy wczyta MegaRuchacza. Okna otwarte wcześniej działają po staremu, dopóki ich nie zamkniesz.')); $nr++
    if (-not $zmiana) {
      $k.Controls.Add((Punkt-Numer $nr 'Przy zegarze jest teraz ikona MegaRuchacza.' 'Kliknij ją (prawy dolny róg ekranu, czasem pod strzałką ^), żeby zobaczyć, co MegaRuchacz robi i ile kosztuje.')); $nr++
    }
    $k.Controls.Add((Punkt-Numer $nr 'Chcesz coś dodać albo usunąć?' "Uruchom instalator jeszcze raz - plik instaluj.bat w folderze $($script:Zrodlo).")); $nr++
  }
  $root.Controls.Add($k)

  $uwagi = @()
  foreach ($z in @($script:Plan)) { foreach ($u in $z.Uwagi) { $uwagi += "$($z.Napis): $u" } }
  if ($uwagi.Count -gt 0) {
    $k2 = Nowa-Karta $script:SzerKarty $script:TloUwaga
    $k2.Controls.Add((Etykieta-Zawijana 'Do sprawdzenia' $script:CzZwyklaGruba $script:KolUwaga $szw))
    foreach ($u in $uwagi) { $k2.Controls.Add((Punkt $u $script:KolTekst)) }
    $root.Controls.Add($k2)
  }
  Ustaw-Przyciski -Dalej 'Zamknij' -PoDalej { Zamknij-Okno }
}

# Znacznik dla okno.ps1: ten plik wczytal sie do konca.
$script:ModulyInstalatora["ekrany"] = $true
