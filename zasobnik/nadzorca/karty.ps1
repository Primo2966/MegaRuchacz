# zasobnik\nadzorca\karty.ps1 - czesc zasobnik\nadzorca.ps1 (patrz BUDOWA
# w jego naglowku). Klocki, z ktorych sklada sie kazda zakladka: etykiety
# (Etykieta, Etykieta-Zawijana), odstepy, biala karta z ramka (Nowa-Karta,
# Obrysuj), przyciski i przelacznik zakladek (Nowy-Przycisk, Przycisk-Przelacznika,
# Styl-Przelacznika), kolor wagi, wiersz dwukolumnowy, tabela, karta sekcji
# Szczegolow (Karta-Sekcji) i karta komunikatu.
# Skad wolane: przeglad.ps1, szczegoly.ps1, warstwy.ps1, skille.ps1, w-tle.ps1,
# ladowanie.ps1, okno.ps1. Wczytuje go nadzorca.ps1 kropka po zamku jednej kopii -
# tu sa same definicje.

# --- klocki okna -------------------------------------------------------------

function Etykieta([string]$tekst, $czcionka, $kolor) {
  $l = New-Object System.Windows.Forms.Label
  $l.AutoSize = $true
  $l.Font = $czcionka
  $l.ForeColor = $kolor
  $l.BackColor = [System.Drawing.Color]::Transparent
  $l.Text = "$tekst"
  $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
  return $l
}

# Etykieta zawijana ma podana MAKSYMALNA szerokosc, a nie stala - dzieki temu
# dluga porada laduje w kilku wierszach zamiast wyjechac poza okno. Tekst, ktory
# wyjezdza poza okno, jest uciety po cichu, a tego w tym projekcie nie wolno.
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

# Biala karta z cienka szara ramka. Ramke rysujemy sami w Paint - BorderStyle
# daje czarna kreske, ktora wyglada jak okno z Windows 95.
function Nowa-Karta([int]$szerokosc) {
  $k = Pionowy $szerokosc
  $k.BackColor = $script:TloKarty
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

# Ramka karty, ktora jest dalszym ciagiem karty nad nia (wykres pod karta
# nauki): lewa, prawa i dolna kreska. Gorna tylko wtedy, gdy karty nad nia
# nie ma ($script:StatSama) - inaczej wisialaby bez ramki od gory.
function Obrysuj-Ciag-Dalszy($kontrolka, $e) {
  try {
    $w = $kontrolka.Width - 1; $h = $kontrolka.Height - 1
    $e.Graphics.DrawLine($script:PioroRamki, 0, 0, 0, $h)
    $e.Graphics.DrawLine($script:PioroRamki, $w, 0, $w, $h)
    $e.Graphics.DrawLine($script:PioroRamki, 0, $h, $w, $h)
    if ($script:StatSama) { $e.Graphics.DrawLine($script:PioroRamki, 0, 0, $w, 0) }
  } catch {
    if (-not $script:RamkaZawiodla) { $script:RamkaZawiodla = $true; Zanotuj-Wywrotke "rysowanie ramki wykresu" $_ }
  }
}

function Wyczysc-Panel($panel) {
  if (-not $panel) { return }
  while ($panel.Controls.Count -gt 0) {
    $c = $panel.Controls[0]
    $panel.Controls.RemoveAt(0)
    try { $c.Dispose() }
    catch { Notuj "nie udalo sie zwolnic kontrolki okna: $($_.Exception.Message)" }
  }
}

function Nowy-Przycisk([string]$napis) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $napis
  $b.Height = 34
  $b.Dock = [System.Windows.Forms.DockStyle]::Fill
  $b.Font = $script:CzZwykla
  $b.FlatStyle = [System.Windows.Forms.FlatStyle]::System
  $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 4)
  return $b
}

# Jeden z dwoch przyciskow przelacznika [Przeglad | Szczegoly]: plaski, bez
# ramki, wybrany jest bialy na szarym tle - jak przelacznik w ustawieniach Windows.
function Przycisk-Przelacznika([string]$napis, [int]$x, [int]$szer = 124) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $napis
  $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
  $b.FlatAppearance.BorderSize = 0
  $b.Size = New-Object System.Drawing.Size($szer, 32)
  $b.Location = New-Object System.Drawing.Point($x, 3)
  $b.Cursor = [System.Windows.Forms.Cursors]::Hand
  $b.TabStop = $false
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

# --- klocki szczegolow (25.09.2026) --------------------------------------------
# Z tych trzech klockow skladaja sie karty w zakladce Szczegoly: wiersz
# "etykieta | wartosc", tabela z liczbami wyrownanymi do prawej i sama karta
# sekcji z tytulem i jednym zdaniem "co to jest". Zawijanie zamiast ucinania -
# tekst, ktory wyjezdza poza karte, bylby ucieciem po cichu.

function Kolor-Wagi([string]$waga) {
  switch ($waga) {
    "pilne"  { return $script:KolPilne }
    "uwaga"  { return $script:KolUwaga }
    "szary"  { return $script:KolSzary }
    "dobrze" { return $script:KolDobrze }
  }
  return $script:KolTekst
}

function Wiersz-Dwukolumnowy([string]$etykieta, [string]$wartosc, $kolor, [int]$szer, [int]$szerEtykiety) {
  $w = Poziomy
  $w.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 5)
  $e = Etykieta-Zawijana $etykieta $script:CzZwykla $script:KolSzary ($szerEtykiety - 12)
  $e.MinimumSize = New-Object System.Drawing.Size($szerEtykiety, 0)
  $e.UseMnemonic = $false
  $w.Controls.Add($e)
  $v = Etykieta-Zawijana $wartosc $script:CzZwykla $kolor ($szer - $szerEtykiety)
  $v.UseMnemonic = $false
  $w.Controls.Add($v)
  return $w
}

# Tabela: TableLayoutPanel, kolumny o stalej szerokosci (ostatnia z zerem dostaje
# reszte), liczby do prawej, cienka kreska pod kazdym wierszem. Kolumna "Pasek"
# rysuje procent poziomym paskiem - udzial widac, zanim sie przeczyta liczbe.
function Tabela-Kontrolka($el, [int]$szer) {
  $t = New-Object System.Windows.Forms.TableLayoutPanel
  $t.AutoSize = $true
  $t.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
  $t.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 10)
  $t.Padding = New-Object System.Windows.Forms.Padding(0)
  $kol = @($el.Kolumny)
  $t.ColumnCount = $kol.Count
  $zajete = 0
  foreach ($k in $kol) { if ($k.S -gt 0) { $zajete += [int]$k.S } }
  $szerokosci = @()
  foreach ($k in $kol) {
    $s = [int]$k.S
    if ($s -le 0) { $s = [math]::Max(120, $szer - $zajete - 4) }
    $szerokosci += $s
    [void]$t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, $s)))
  }
  $t.RowCount = $el.Wiersze.Count + 1
  $t.Add_CellPaint({
    param($nadawca, $e)
    try {
      $y = $e.CellBounds.Bottom - 1
      $e.Graphics.DrawLine($script:PioroRamki, $e.CellBounds.Left, $y, $e.CellBounds.Right, $y)
    } catch { if (-not $script:RamkaZawiodla) { $script:RamkaZawiodla = $true; Zanotuj-Wywrotke "rysowanie kreski w tabeli" $_ } }
  })
  $wiersz = 0
  $wszystkie = @(,[string[]]@($kol | ForEach-Object { "$($_.N)" })) + @($el.Wiersze)
  foreach ($r in $wszystkie) {
    [void]$t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    for ($i = 0; $i -lt $kol.Count; $i++) {
      $k = $kol[$i]
      $v = ""
      if ($i -lt @($r).Count) { $v = "$($r[$i])" }
      if (($wiersz -gt 0) -and $k.Pasek) {
        $p = New-Object System.Windows.Forms.Panel
        $p.Size = New-Object System.Drawing.Size(($szerokosci[$i] - 16), 22)
        $p.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
        $p.BackColor = $script:TloKarty
        $proc = 0
        [void][int]::TryParse($v, [ref]$proc)
        $pas = New-Object System.Windows.Forms.Panel
        $pas.BackColor = $script:KolMr
        $pas.Location = New-Object System.Drawing.Point(0, 7)
        $pas.Size = New-Object System.Drawing.Size([math]::Max(2, [int](($szerokosci[$i] - 16) * [math]::Min(100, $proc) / 100.0)), 9)
        if ($proc -le 0) { $pas.BackColor = $script:KolOsi }
        $p.Controls.Add($pas)
        $t.Controls.Add($p, $i, $wiersz)
        continue
      }
      $cz = $script:CzZwykla; $kolor = $script:KolTekst
      if ($wiersz -eq 0) { $cz = $script:CzMalaGruba; $kolor = $script:KolSzary }
      $l = Etykieta-Zawijana $v $cz $kolor ($szerokosci[$i] - 12)
      $l.UseMnemonic = $false
      $l.Margin = New-Object System.Windows.Forms.Padding(0, 4, 12, 5)
      if ($k.P) {
        $l.Anchor = [System.Windows.Forms.AnchorStyles]::Right
        $l.TextAlign = [System.Drawing.ContentAlignment]::TopRight
      }
      $t.Controls.Add($l, $i, $wiersz)
    }
    $wiersz++
  }
  return $t
}

function Karta-Sekcji($s) {
  $k = Nowa-Karta $script:SzerKarty
  $k.Padding = New-Object System.Windows.Forms.Padding(22, 16, 22, 14)
  $k.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)
  $szer = $script:SzerKarty - 44
  $tyt = Etykieta-Zawijana $s.Tytul $script:CzSrednia $script:KolTekst $szer
  $tyt.UseMnemonic = $false
  $k.Controls.Add($tyt)
  if ($s.Opis) {
    $o = Etykieta-Zawijana $s.Opis $script:CzZwykla $script:KolSzary $szer
    $o.UseMnemonic = $false
    $o.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 12)
    $k.Controls.Add($o)
  }
  foreach ($e in $s.Elementy) {
    switch ($e.Rodzaj) {
      "wiersz" { $k.Controls.Add((Wiersz-Dwukolumnowy $e.Etykieta $e.Wartosc (Kolor-Wagi $e.Waga) $szer $script:SzerEtykiety)) }
      "tekst" {
        $l = Etykieta-Zawijana $e.Tekst $script:CzZwykla (Kolor-Wagi $e.Waga) $szer
        $l.UseMnemonic = $false
        $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 5)
        $k.Controls.Add($l)
      }
      "podtytul" {
        $l = Etykieta-Zawijana $e.Tekst $script:CzZwyklaGruba $script:KolTekst $szer
        $l.UseMnemonic = $false
        $l.Margin = New-Object System.Windows.Forms.Padding(0, 12, 0, 2)
        $k.Controls.Add($l)
      }
      "tabela" { $k.Controls.Add((Tabela-Kontrolka $e $szer)) }
    }
  }
  return $k
}

# Jedna karta z samym tekstem - "licze...", odpowiedz straznika, wywrotka.
function Karta-Komunikatu([string]$tytul, [string[]]$linie, $kolor) {
  $s = Nowa-Sekcja $tytul ""
  foreach ($x in @($linie)) { [void]$s.Elementy.Add([pscustomobject]@{ Rodzaj = "tekst"; Tekst = "$x"; Waga = "" }) }
  $k = Karta-Sekcji $s
  if ($kolor) { foreach ($c in $k.Controls) { if ($c -is [System.Windows.Forms.Label] -and ($c.Font -eq $script:CzZwykla)) { $c.ForeColor = $kolor } } }
  return $k
}

# Znacznik dla nadzorca.ps1: ten plik wczytal sie do konca.
$script:ModulyOkna["karty"] = $true
