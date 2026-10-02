# zasobnik\nadzorca\przeglad.ps1 - czesc zasobnik\nadzorca.ps1 (patrz BUDOWA
# w jego naglowku). Karty zakladki Przeglad: werdykt na gorze (Odmaluj-Werdykt),
# "Ile tokenow naprawde zuzywasz" (Odmaluj-Koszt), otwarcie okna rozmowy z paskiem
# (Odmaluj-Start), podtytul, karty problemow, nauka z rozmow (Odmaluj-Liczby),
# stan jednym rzutem oka ze zmianami w pamieci (Odmaluj-Stan), przyciski na dole
# (Odmaluj-Przyciski) i calosc (Odmaluj-Okno). Od P59d karty i linie modulow, ktorych
# nie ma w rejestrze instalacji ($script:Instalacja), sa niewidoczne albo nie
# powstaja - bez dziur w ukladzie. Tresc (co pokazac) jest
# w przeglad-tresc.ps1. Wykres kosztu nauki z 30 dni stal tu do P35 - teraz jest
# karta w Szczegolach (Panel-Wykresu w wykres.ps1).
# Skad wolane: w-tle.ps1 (Wyrenderuj-Widok, Odswiez-Zuzycie), ladowanie.ps1
# (Odmaluj-Podtytul), okno.ps1. Wczytuje go nadzorca.ps1 kropka po zamku jednej
# kopii - tu sa same definicje.

# --- werdykt na samej gorze Przegladu (P15, 28.09.2026) ------------------------
# Jedno zdanie duza czcionka, ktore czlowiek nieznajacy MegaRuchacza zrozumie
# w piec sekund: ile MegaRuchacz doklada i czy to malo (od P35 prog w tokenach,
# procent calosci tylko do pokazania).
# Stan i slowa sklada Werdykt-Kosztu (stan-nadzorcy.ps1) - tu tylko kolor:
# zielony = malo, czerwony = duzo, zolty = nie wiadomo (i wtedy tlo karty tez
# zolte, zeby "nie wiem" nie wygladalo jak "wszystko gra").
function Odmaluj-Werdykt {
  if (-not $script:KartaWerdykt -or $script:KartaWerdykt.IsDisposed) { return }
  Wyczysc-Panel $script:KartaWerdykt
  $szer = $script:SzerKarty - 44
  $r = $null; $c = $null
  if ($script:Dane) { $r = $script:Dane.Rachunek; $c = $script:Dane.Cykl }
  $w = $null
  try { $w = Werdykt-Kosztu $script:Start $r $c $script:Zuzycie $script:Instalacja } catch { Zanotuj-Wywrotke "werdykt kosztu" $_ }
  $script:KartaWerdykt.BackColor = $script:TloKarty
  if (-not $w) {
    $script:KartaWerdykt.BackColor = $script:TloUwaga
    $script:KartaWerdykt.Controls.Add((Etykieta-Zawijana "Nie udało się ocenić, ile kosztuje MegaRuchacz - powód jest w dzienniku nadzorcy." $script:CzGruba $script:KolUwaga $szer))
    return
  }
  $kol = $script:KolSzary
  switch ($w.Stan) {
    "malo"        { $kol = $script:KolDobrze }
    "duzo"        { $kol = $script:KolPilne; $script:KartaWerdykt.BackColor = $script:TloPilne }
    "nie wiadomo" { $kol = $script:KolUwaga; $script:KartaWerdykt.BackColor = $script:TloUwaga }
  }
  $z = Etykieta-Zawijana $w.Zdanie $script:CzTytul $kol $szer
  $z.UseMnemonic = $false
  $script:KartaWerdykt.Controls.Add($z)
  # Prog i nauka jednym akapitem pod zdaniem - okno ma sie miescic na ekranie
  # bez przewijania, a karta otwarcia sesji tuz nizej i tak mowi, co jest 100%.
  $reszta = (@($w.Wyjasnienie, $w.Nauka) | Where-Object { $_ }) -join " "
  if ($reszta) {
    $x = Etykieta-Zawijana $reszta $script:CzZwykla $script:KolTekst $szer
    $x.UseMnemonic = $false
    $x.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $script:KartaWerdykt.Controls.Add($x)
  }
}

# --- karta "Ile tokenow naprawde zuzywasz" na Przegladzie (P26, 30.09.2026) ----
# Werdykt wyzej mowi, ile doklada sam MegaRuchacz (kilka procent otwarcia okna).
# P22 pokazal, ze prawdziwe pieniadze sa gdzie indziej: workerzy (60% tokenow
# w 23-29.09). Ta karta mowi to wprost, w dwoch kolumnach obok siebie, zeby byla
# niska: dzis i srednia z 7 dni (rozmowy kontra workerzy) oraz najdrozsi workerzy
# dnia. Opis, ktory sie nie miesci, konczy sie wielokropkiem (widac, ze to nie
# calosc; calosc w dymku po najechaniu myszka i w Szczegolach). Teksty sklada
# Teksty-Kosztu (stan-nadzorcy.ps1) - te same co w wydruku -Raport.
# Trzecia kolumna - najdluzsze rozmowy z "!" ponad progiem - i stopka o dlugosci
# rozmowy usuniete 2026-10-01 (P43, decyzja uzytkownika); workerzy dostali jej
# miejsce i rola z projektem mieszcza sie teraz w linii.

# Etykieta o stalej szerokosci, w jednej linii, z wielokropkiem, gdy tekst sie nie
# miesci - kolumny stoja rowno, a nic nie wyjezdza poza karte po cichu.
function Etykieta-Stala([string]$tekst, $czcionka, $kolor, [int]$szer, [bool]$doPrawej = $false) {
  $l = Etykieta $tekst $czcionka $kolor
  $l.AutoSize = $false
  $l.AutoEllipsis = $true
  $l.UseMnemonic = $false
  $l.Size = New-Object System.Drawing.Size($szer, ($czcionka.Height + 1))
  $l.Margin = New-Object System.Windows.Forms.Padding(0)
  if ($doPrawej) { $l.TextAlign = [System.Drawing.ContentAlignment]::TopRight }
  return $l
}

function Odmaluj-Koszt {
  if (-not $script:KartaKoszt -or $script:KartaKoszt.IsDisposed) { return }
  Wyczysc-Panel $script:KartaKoszt
  $szer = $script:SzerKarty - 44
  $t = $null
  try { $t = Teksty-Kosztu $script:KosztDzis $script:Zuzycie }
  catch { Zanotuj-Wywrotke "karta prawdziwego kosztu" $_ }
  $gora = Poziomy
  $tytul = "Ile tokenów naprawdę zużywasz - Twoje rozmowy i workerzy"
  if ($t) { $tytul = $t.Tytul }
  $gora.Controls.Add((Etykieta $tytul $script:CzGruba $script:KolTekst))
  $script:KartaKoszt.Controls.Add($gora)
  if (-not $t) {
    $script:KartaKoszt.Controls.Add((Etykieta-Zawijana "Nie udało się złożyć tej karty - powód jest w dzienniku nadzorcy." $script:CzZwykla $script:KolUwaga $szer))
    return
  }
  if ($t.Powod) {
    # Jeszcze liczy - szare zdanie; nie udalo sie - zolte "nie wiem, bo ...". Nigdy zero.
    $kolP = $script:KolUwaga
    if (-not $script:KosztDzis) { $kolP = $script:KolSzary }
    $p = Etykieta-Zawijana $t.Powod $script:CzZwykla $kolP $szer
    $p.UseMnemonic = $false
    $p.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $script:KartaKoszt.Controls.Add($p)
    return
  }
  $odstep = 26
  $sz1 = 330
  $sz2 = $szer - $sz1 - $odstep
  # Kolumna "rola, projekt" po prawej - szara, stalej szerokosci, zeby opisy staly rowno.
  $szDop = 230
  $wiersz = Poziomy
  $wiersz.Margin = New-Object System.Windows.Forms.Padding(0, 5, 0, 0)

  # 1. Tabelka: co | dzis | srednio z 7 dni. "Razem" pogrubione.
  $k1 = Pionowy $sz1
  $sk = @(118, 96, ($sz1 - 118 - 96))
  $nr = 0
  foreach ($r in $t.Tabela) {
    $w = Poziomy
    $w.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 1)
    for ($i = 0; $i -lt 3; $i++) {
      $czc = $script:CzZwykla; $kol = $script:KolTekst
      if ($nr -eq 0) { $czc = $script:CzMala; $kol = $script:KolSzary }
      elseif ($i -eq 0) { $kol = $script:KolSzary }
      elseif ($nr -eq (@($t.Tabela).Count - 1)) { $czc = $script:CzZwyklaGruba }
      $w.Controls.Add((Etykieta-Stala "$($r[$i])" $czc $kol $sk[$i] ($i -gt 0)))
    }
    $k1.Controls.Add($w)
    $nr++
  }
  if ($t.Udzial) {
    $kolU = $script:KolSzary
    if ($t.UdzialUwaga) { $kolU = $script:KolUwaga }
    $u = Etykieta-Zawijana $t.Udzial $script:CzMala $kolU $sz1
    $u.UseMnemonic = $false
    $u.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    $k1.Controls.Add($u)
  }

  # 2. Najdrozsi workerzy dnia: tokeny | opis zadania | rola, projekt.
  $k2 = Pionowy $sz2
  $k2.Margin = New-Object System.Windows.Forms.Padding($odstep, 0, 0, 0)
  $k2.Controls.Add((Etykieta-Stala $t.NaglowekWorkerow $script:CzMalaGruba $script:KolSzary $sz2))
  foreach ($x in @($t.Workerzy)) {
    $w = Poziomy
    $w.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 1)
    $w.Controls.Add((Etykieta-Stala $x.Tokeny $script:CzZwykla $script:KolTekst 72 $true))
    $e = Etykieta-Stala $x.Opis $script:CzZwykla $script:KolTekst ($sz2 - 72 - 10 - 16 - $szDop)
    $e.Margin = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $w.Controls.Add($e)
    $d = Etykieta-Stala $x.Dopisek $script:CzZwykla $script:KolSzary $szDop
    $d.Margin = New-Object System.Windows.Forms.Padding(16, 0, 0, 0)
    $w.Controls.Add($d)
    $k2.Controls.Add($w)
  }
  if ($t.WorkerzyPusto) { $k2.Controls.Add((Etykieta-Zawijana $t.WorkerzyPusto $script:CzZwykla $script:KolSzary $sz2)) }

  $wiersz.Controls.Add($k1)
  $wiersz.Controls.Add($k2)
  $script:KartaKoszt.Controls.Add($wiersz)
}

# --- karta "Otwarcie sesji" na Przegladzie ------------------------------------
# Odpowiedz na pytanie uzytkownika "ile tokenow na otwarcie sesji i jaki to
# procent tego, co dokleja MegaRuchacz". Jedna duza liczba, pasek z dwoma
# kawalkami, dwa wiersze legendy z liczbami wyrownanymi do prawej i jedno
# zdanie, co to znaczy dla portfela. Gdy pomiaru nie ma - "nie zmierzono, bo...",
# bez paska i bez procentu: 0% czytaloby sie jak "MegaRuchacz nic nie kosztuje".
function Wiersz-Legendy-Startu($panel, $kolor, [string]$napis, [string]$liczba, [string]$proc) {
  $w = Poziomy
  $w.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
  $kw = New-Object System.Windows.Forms.Panel
  $kw.Size = New-Object System.Drawing.Size(12, 12)
  $kw.BackColor = $kolor
  $kw.Margin = New-Object System.Windows.Forms.Padding(0, 5, 10, 0)
  $w.Controls.Add($kw)
  $n = Etykieta $napis $script:CzZwykla $script:KolTekst
  $n.AutoSize = $false
  $n.Size = New-Object System.Drawing.Size(430, 22)
  $n.UseMnemonic = $false
  $w.Controls.Add($n)
  $l = Etykieta $liczba $script:CzZwyklaGruba $script:KolTekst
  $l.AutoSize = $false
  $l.Size = New-Object System.Drawing.Size(110, 22)
  $l.TextAlign = [System.Drawing.ContentAlignment]::TopRight
  $w.Controls.Add($l)
  $p = Etykieta $proc $script:CzZwykla $script:KolSzary
  $p.AutoSize = $false
  $p.Size = New-Object System.Drawing.Size(110, 22)
  $p.TextAlign = [System.Drawing.ContentAlignment]::TopRight
  $w.Controls.Add($p)
  $panel.Controls.Add($w)
}

# Wiersz skladnika pod wierszem MegaRuchacza: wciety pod kwadracik legendy,
# szary, te same kolumny liczby i procentu co wiersz nad nim.
function Wiersz-Skladnika-Startu($panel, $sk) {
  $w = Poziomy
  $w.Margin = New-Object System.Windows.Forms.Padding(22, 0, 0, 2)
  $n = Etykieta "$($sk.Napis)" $script:CzMala $script:KolSzary
  $n.AutoSize = $false
  $n.Size = New-Object System.Drawing.Size(430, 20)
  $n.UseMnemonic = $false
  $w.Controls.Add($n)
  $l = Etykieta "$($sk.Liczba)" $script:CzMala $script:KolSzary
  $l.AutoSize = $false
  $l.Size = New-Object System.Drawing.Size(110, 20)
  $l.TextAlign = [System.Drawing.ContentAlignment]::TopRight
  $w.Controls.Add($l)
  $p = Etykieta "$($sk.Proc)" $script:CzMala $script:KolSzary
  $p.AutoSize = $false
  $p.Size = New-Object System.Drawing.Size(110, 20)
  $p.TextAlign = [System.Drawing.ContentAlignment]::TopRight
  $w.Controls.Add($p)
  # P16: "+115 przy kazdej wiadomosci" po ludzku, w tym samym wierszu - bez nowej linii
  if ($sk.Uwaga) {
    $u = Etykieta "- $($sk.Uwaga)" $script:CzMala $script:KolSzary
    $u.Margin = New-Object System.Windows.Forms.Padding(16, 0, 0, 0)
    $w.Controls.Add($u)
  }
  $panel.Controls.Add($w)
}

function Rysuj-Pasek-Startu($g, $rozmiar) {
  try {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    $g.Clear($script:TloKarty)
    $w = [int]$rozmiar.Width; $h = [int]$rozmiar.Height
    $cc = New-Object System.Drawing.SolidBrush($script:KolCc)
    $mr = New-Object System.Drawing.SolidBrush($script:KolMr)
    try {
      $g.FillRectangle($cc, 0, 0, $w, $h)
      $szerMr = [int][math]::Round($w * [double]$script:UdzialStartu)
      if ($szerMr -lt 3) { $szerMr = 3 }   # kawalek ma byc widoczny, choc maly
      $g.FillRectangle($mr, 0, 0, $szerMr, $h)
    } finally { $cc.Dispose(); $mr.Dispose() }
  } catch {
    if (-not $script:RysowanieZawiodlo) { $script:RysowanieZawiodlo = $true; Zanotuj-Wywrotke "rysowanie paska otwarcia okna rozmowy" $_ }
  }
}

function Odmaluj-Start {
  if (-not $script:KartaStart -or $script:KartaStart.IsDisposed) { return }
  Wyczysc-Panel $script:KartaStart
  $szer = $script:SzerKarty - 44
  $tyt = Etykieta "Otwarcie okna rozmowy - nasza miara 100%" $script:CzGruba $script:KolTekst
  $script:KartaStart.Controls.Add($tyt)
  # P16 (28.09.2026): uzytkownik nie wie, co to "sesja" - dla niego to okno, w ktorym
  # pisze, a pisac mozna dwa slowa albo miliony tokenow. Jednostka jest wiec to, co
  # Claude wczytuje przy OTWARCIU nowego okna rozmowy, i tu, raz, stoi to wprost.
  $ileTxt = "swoje instrukcje"
  $o = $null
  if ($null -ne $script:Start) {
    try { $o = Opis-Startu $script:Start } catch { Zanotuj-Wywrotke "opis otwarcia okna rozmowy" $_ }
  }
  if ($o -and $o.Zmierzone) { $ileTxt = "~$(Okolo $o.Razem) tokenów swoich instrukcji" }
  $pod = Etykieta-Zawijana "Za każdym razem, gdy otwierasz nowe okno rozmowy z Claude, zanim napiszesz słowo, Claude wczytuje $ileTxt. To nasza miara 100%." $script:CzMala $script:KolSzary $szer
  $pod.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
  $script:KartaStart.Controls.Add($pod)

  if ($null -eq $script:Start) {
    $script:KartaStart.Controls.Add((Etykieta-Zawijana "Liczę, ile Claude wczytuje na starcie rozmowy - to potrwa kilka sekund..." $script:CzZwykla $script:KolSzary $szer))
    return
  }
  if (-not $o -or -not $o.Zmierzone) {
    $pw = "nie wiadomo dlaczego - to samo w sobie jest usterką"
    if ($o -and $o.Powod) { $pw = $o.Powod }
    $script:KartaStart.Controls.Add((Etykieta "nie zmierzono" $script:CzDuza $script:KolUwaga))
    $script:KartaStart.Controls.Add((Etykieta-Zawijana "Nie zmierzono, bo $pw." $script:CzZwykla $script:KolUwaga $szer))
    if ($o -and ($null -ne $o.Mr)) {
      $czescMr = "Sama część MegaRuchacza (z rachunku): ~$(Liczba-Ludzka $o.Mr) tokenów."
      if ($o.Mr -le 0) { $czescMr = "Rachunek MegaRuchacza też nie znalazł nic doklejanego przy otwarciu okna rozmowy - powód jest w zakładce Szczegóły." }
      $x = Etykieta-Zawijana ("$czescMr " +
        "Bez zmierzonej całości nie da się powiedzieć, jaki to procent - dlatego procentu tu nie ma.") $script:CzZwykla $script:KolSzary $szer
      $x.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
      $script:KartaStart.Controls.Add($x)
    }
    return
  }

  $script:UdzialStartu = $o.UdzialMr
  $wiersz = Poziomy
  $duza = Etykieta ("~" + (Okolo $o.Razem)) $script:CzDuza $script:KolTekst
  $duza.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
  $wiersz.Controls.Add($duza)
  $jed = Etykieta "tokenów przy każdym otwarciu okna rozmowy - to jest 100%" $script:CzZwykla $script:KolSzary
  $jed.Margin = New-Object System.Windows.Forms.Padding(0, 14, 0, 0)
  $wiersz.Controls.Add($jed)
  $script:KartaStart.Controls.Add($wiersz)

  $pasek = New-Object System.Windows.Forms.PictureBox
  $pasek.Size = New-Object System.Drawing.Size($szer, 14)
  $pasek.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 10)
  $pasek.Add_Paint({ param($nadawca, $e) Rysuj-Pasek-Startu $e.Graphics $nadawca.ClientSize })
  $script:KartaStart.Controls.Add($pasek)

  Wiersz-Legendy-Startu $script:KartaStart $script:KolMr "MegaRuchacz - razem, z tego:" "~$(Okolo $o.Mr)" $o.MrProc
  foreach ($sk in (Skladniki-Mr $script:Start $o)) { Wiersz-Skladnika-Startu $script:KartaStart $sk }
  Wiersz-Legendy-Startu $script:KartaStart $script:KolCc "Claude Code sam - jego własne instrukcje i podłączone dodatki" "~$(Okolo $o.Cc)" $o.CcProc

  $p = Etykieta-Zawijana $o.Portfel $script:CzZwykla $script:KolTekst $szer
  $p.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 6)
  $script:KartaStart.Controls.Add($p)
  # Start workera stoi w Szczegolach - na Przegladzie tylko to, co laik rozumie (P15).
  $pods = (@($o.Podstawa, $o.Zakres) | Where-Object { $_ }) -join " "
  $script:KartaStart.Controls.Add((Etykieta-Zawijana $pods $script:CzMala $script:KolSzary $szer))
}

# --- odmalowanie -------------------------------------------------------------

function Odmaluj-Podtytul {
  if (-not $script:LPodtytul -or $script:LPodtytul.IsDisposed) { return }
  if ($script:Ladowanie) {
    $script:LPodtytul.ForeColor = $script:KolSzary
    $script:LPodtytul.Text = "Wczytuję dane - postęp krok po kroku poniżej."
    return
  }
  if ($script:Licze) {
    $script:LPodtytul.ForeColor = $script:KolSzary
    if ($script:DaneCzas) {
      $script:LPodtytul.Text = "Przeliczam... na razie widzisz liczby sprzed $($script:DaneCzas.ToString('HH:mm'))."
    } else {
      $script:LPodtytul.Text = "Przeliczam, to potrwa kilka sekund..."
    }
    return
  }
  if ($script:DaneBlad) {
    $script:LPodtytul.ForeColor = $script:KolUwaga
    if ($script:DaneCzas) {
      $script:LPodtytul.Text = "Przeliczenie się nie udało - liczby są sprzed $($script:DaneCzas.ToString('HH:mm'))."
    } else {
      $script:LPodtytul.Text = "Przeliczenie się nie udało i nie mam żadnych liczb."
    }
    return
  }
  $script:LPodtytul.ForeColor = $script:KolSzary
  $kiedy = "przed chwilą"
  if ($script:DaneCzas) { $kiedy = Kiedy-Ludzko $script:DaneCzas }
  $script:LPodtytul.Text = "Sprawdzone $kiedy. Liczby odświeżają się same w tle co $Minut min."
}

function Karta-Problemu($p) {
  $k = Pionowy $script:SzerKarty
  $k.Padding = New-Object System.Windows.Forms.Padding(22, 14, 22, 14)
  $k.Margin  = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)
  $kolor = $script:KolUwaga
  $k.BackColor = $script:TloUwaga
  $podpis = "Do sprawdzenia"
  if ($p.Waga -eq "pilne") { $kolor = $script:KolPilne; $k.BackColor = $script:TloPilne; $podpis = "Wymaga działania" }
  elseif ($p.Waga -eq "info") { $podpis = "Dla informacji - nic nie trzeba robić" }
  $szer = $script:SzerKarty - 44
  $k.Controls.Add((Etykieta $podpis.ToUpper() $script:CzMalaGruba $kolor))
  $k.Controls.Add((Etykieta-Zawijana $p.Tytul $script:CzGruba $kolor $szer))
  if ($p.Porada) {
    $k.Controls.Add((Etykieta-Zawijana $p.Porada $script:CzZwykla $script:KolTekst $szer))
  }
  return $k
}

function Odmaluj-Problemy {
  if (-not $script:PanelProblemy -or $script:PanelProblemy.IsDisposed) { return }
  Wyczysc-Panel $script:PanelProblemy
  # Bez @() - patrz uwaga o "return ,$lista" w naglowku stan-nadzorcy.ps1.
  $script:Problemy = Zbierz-Problemy $script:Dane $script:Wywrotki $script:DaneBlad $script:DaneCzas
  if (@($script:Problemy).Count -eq 0) {
    # Niewidoczna kontrolka nie bierze udzialu w ukladaniu, wiec sekcja bez
    # problemow NIE ZOSTAWIA po sobie ani pustej ramki, ani odstepu.
    $script:PanelProblemy.Visible = $false
    return
  }
  foreach ($p in $script:Problemy) { $script:PanelProblemy.Controls.Add((Karta-Problemu $p)) }
  $script:PanelProblemy.Visible = $true
}

# Karta nauki z rozmow - na cala szerokosc, pod "Otwarcie sesji". Do 28.09.2026
# (P14) byla trzecim z trzech kafelkow; dwa pierwsze dublowaly karte otwarcia
# sesji i zniknely.
# P17 (28.09.2026): duza liczba to TOKENY dziennie. Uzytkownik: "te 20%, to nie
# wiem czego" - procent otwarcia okna rozmowy nie ma sensu przy koszcie
# dziennym. Pod liczba jedno zdanie porownania z calym dziennym zuzyciem
# tokenow w rozmowach z Claude ($zu = Zuzycie-Dzienne) albo, gdy go nie ma,
# "nie mam z czym porownac, bo ..." na zolto - nigdy zero.
function Kafelek-Liczby($t, $zu) {
  # Zwykly odstep pod karta (Nowa-Karta) - do P35 wykres kosztu nauki byl jej
  # dalszym ciagiem i stal tuz pod nia; teraz jest w Szczegolach.
  $k = Nowa-Karta $script:SzerKarty
  $szer = $script:SzerKarty - 44
  $k.Controls.Add((Etykieta-Zawijana $t.Naglowek $script:CzGruba $script:KolTekst $szer))
  if ($null -ne $t.Liczba) {
    $tn = Teksty-Nauki $t $zu
    $w = Poziomy
    $w.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $duza = Etykieta $tn.Duza $script:CzDuza $script:KolTekst
    $duza.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)
    $w.Controls.Add($duza)
    $jed = Etykieta $tn.Jednostka $script:CzZwykla $script:KolSzary
    $jed.Margin = New-Object System.Windows.Forms.Padding(0, 14, 0, 0)
    $w.Controls.Add($jed)
    $k.Controls.Add($w)
    # Dopisek "z jakich dni i czy zalegle" - kolor tylko wtedy, gdy niesie
    # znaczenie (czerwony: zwykly dzien nad progiem; zolty: zalegle rozmowy
    # albo dni nieznane); zwykly dzien dostaje neutralna szara plakietke.
    if ($t.Znacznik) {
      $kol = $script:KolSzary; $tlo = $script:TloZnacz
      if ($t.ZnacznikWaga -eq "pilne") { $kol = $script:KolPilne; $tlo = $script:TloPilne }
      elseif ($t.ZnacznikWaga) { $kol = $script:KolUwaga; $tlo = $script:TloUwaga }
      $z = Etykieta $t.Znacznik $script:CzMalaGruba $kol
      $z.UseMnemonic = $false
      $z.BackColor = $tlo
      $z.Padding = New-Object System.Windows.Forms.Padding(6, 2, 6, 3)
      $z.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 2)
      # P17: w wierszu duzej liczby, gdy sie miesci - karta dostala zdanie
      # porownania i drobny druk, a okno ma sie miescic bez przewijania.
      # Gdy sie nie miesci, osobna linia jak dotad (wiersz sie nie zawija).
      if (($w.PreferredSize.Width + 14 + $z.PreferredSize.Width) -le $szer) {
        $z.Margin = New-Object System.Windows.Forms.Padding(14, 12, 0, 0)
        $w.Controls.Add($z)
      } else {
        $k.Controls.Add($z)
      }
    }
    # Porownanie z calym dniem - zwykla czcionka, bo to odpowiedz na "duzo czy
    # malo?"; zolte, gdy porownania nie ma.
    $kolP = $script:KolTekst
    if (-not $tn.PorownanieJest) { $kolP = $script:KolUwaga }
    $por = Etykieta-Zawijana $tn.Porownanie $script:CzZwykla $kolP $szer
    $por.UseMnemonic = $false
    $por.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)
    $k.Controls.Add($por)
    if ($tn.Drobny) {
      $dd = Etykieta-Zawijana $tn.Drobny $script:CzMala $script:KolSzary $szer
      $dd.UseMnemonic = $false
      $dd.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
      $k.Controls.Add($dd)
    }
  } else {
    # Zero znaczyloby "nic nie kosztuje" - a my po prostu nie wiemy. Mowimy to
    # wprost i podajemy powod, zamiast pokazac liczbe, ktorej nie mamy.
    $k.Controls.Add((Etykieta "nie wiem" $script:CzDuza $script:KolUwaga))
    $k.Controls.Add((Etykieta-Zawijana $t.Powod $script:CzMala $script:KolUwaga $szer))
  }
  $opis = Etykieta-Zawijana $t.Opis $script:CzMala $script:KolSzary $szer
  $opis.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 0)
  $k.Controls.Add($opis)
  return $k
}

function Odmaluj-Liczby {
  if (-not $script:PanelLiczby -or $script:PanelLiczby.IsDisposed) { return }
  Wyczysc-Panel $script:PanelLiczby
  # P59d: bez modulu Wiedza karty nauki nie ma wcale - niewidoczny panel nie zostawia
  # w ukladzie ani dziury, ani odstepu (jak sekcja problemow bez problemow).
  $script:PanelLiczby.Visible = (Modul-Jest $script:Instalacja "wiedza")
  if (-not $script:PanelLiczby.Visible) { return }
  $r = $null; $c = $null
  if ($script:Dane) { $r = $script:Dane.Rachunek; $c = $script:Dane.Cykl }
  $t = $null
  try { $t = Liczba-Nauki $r $c }
  catch { Zanotuj-Wywrotke "zlozenie kosztu nauki" $_ }
  if (-not $t) {
    $bl = Etykieta-Zawijana "Kosztu nauki jeszcze nie ma - nie udało się go złożyć. Powód jest w zakładce Szczegóły." $script:CzZwykla $script:KolUwaga $script:SzerTresc
    # ten sam odstep od karty "Stan", co pod karta nauki
    $bl.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)
    $script:PanelLiczby.Controls.Add($bl)
    return
  }
  $script:PanelLiczby.Controls.Add((Kafelek-Liczby $t $script:Zuzycie))
}

# Wiersz karty stanu: "Nauka z rozmow: ostatnio dzis o 09:12" rozdzielone na
# dwie kolumny - co (szare) i jak (czarne). Linie przychodza gotowe z Linie-Stanu.
function Wiersz-Stanu([string]$linia, $kolorWartosci) {
  $w = Poziomy
  $w.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 5)
  $szer = $script:SzerKarty - 44
  $i = $linia.IndexOf(": ")
  if ($i -gt 0) {
    $e = Etykieta-Zawijana $linia.Substring(0, $i) $script:CzZwykla $script:KolSzary $script:SzerEtykiety
    $e.MinimumSize = New-Object System.Drawing.Size($script:SzerEtykiety, 0)
    $w.Controls.Add($e)
    $w.Controls.Add((Etykieta-Zawijana (Z-Wielkiej $linia.Substring($i + 2)) $script:CzZwykla $kolorWartosci ($szer - $script:SzerEtykiety)))
  } else {
    $w.Controls.Add((Etykieta-Zawijana $linia $script:CzZwykla $kolorWartosci $szer))
  }
  return $w
}

function Odmaluj-Stan {
  if (-not $script:PanelStan -or $script:PanelStan.IsDisposed) { return }
  Wyczysc-Panel $script:PanelStan
  $tyt = Etykieta "Stan" $script:CzGruba $script:KolTekst
  $tyt.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
  $script:PanelStan.Controls.Add($tyt)
  if ((Ile-Wymaga-Uwagi $script:Problemy) -eq 0) {
    $ok = Etykieta "Wszystko gra - nic nie wymaga Twojej uwagi." $script:CzZwyklaGruba $script:KolDobrze
    $ok.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
    $script:PanelStan.Controls.Add($ok)
  }
  $linie = @()
  if ($script:Dane) {
    try { $linie = Linie-Stanu $script:Dane.Wersja $script:Dane.Cykl $script:Dane.Przeliczanie $script:Instalacja }
    catch { Zanotuj-Wywrotke "zlozenie linii stanu" $_ }
  }
  foreach ($l in $linie) { $script:PanelStan.Controls.Add((Wiersz-Stanu $l $script:KolTekst)) }
  # Kopia zapasowa (P62): jedna linia, kolor z oceny (progi w stan-kopia.ps1). Tylko
  # z modulem Kopia (P59d).
  if ($script:Dane -and (Modul-Jest $script:Instalacja "kopia")) {
    try {
      $kop = Ocena-Kopii $script:Dane.Kopia $script:Instalacja
      $script:PanelStan.Controls.Add((Wiersz-Stanu $kop.Linia (Kolor-Wagi $kop.Waga)))
    } catch { Zanotuj-Wywrotke "linia kopii zapasowej" $_ }
  }
  # Zmiany w pamieci pisze nauka z rozmow - bez modulu Wiedza linii nie ma (P59d).
  if (Modul-Jest $script:Instalacja "wiedza") { Dodaj-Zmiany-Pamieci }
  else { $script:PanelZmian = $null; $script:LinkZmian = $null }
}

# "Pamiec dzis: 2 zmiany" jedna linia, a obok odnosnik [pokaz zmiany], ktory
# rozwija linie z identyfikatorami i zdanie, jak cofnac. Rozwijanie tylko
# przelacza widocznosc - nie przebudowuje panelu, bo kontrolka zwalniana we
# wlasnej procedurze klikniecia potrafi wywrocic WinForms.
function Dodaj-Zmiany-Pamieci {
  $script:PanelZmian = $null
  $script:LinkZmian = $null
  $szer = $script:SzerKarty - 44
  $pz = $null
  if ($script:Dane) { $pz = $script:Dane.Pamiec }
  $o = $null
  try { $o = Opis-Zmian-Pamieci $pz }
  catch { Zanotuj-Wywrotke "zlozenie zmian w pamieci" $_ }
  if (-not $o) {
    $script:PanelStan.Controls.Add((Wiersz-Stanu "Pamięć: nie udało się złożyć listy zmian - powód jest w dzienniku nadzorcy." $script:KolUwaga))
    return
  }
  $kolor = $script:KolTekst
  if ($o.Uwaga) { $kolor = $script:KolUwaga }
  if (@($o.Zmiany).Count -eq 0) {
    $script:PanelStan.Controls.Add((Wiersz-Stanu $o.Linia $kolor))
    return
  }

  $wiersz = Wiersz-Stanu $o.Linia $kolor
  $script:LinkZmian = New-Object System.Windows.Forms.LinkLabel
  $script:LinkZmian.AutoSize = $true
  $script:LinkZmian.Font = $script:CzZwykla
  $script:LinkZmian.Margin = New-Object System.Windows.Forms.Padding(6, 0, 0, 0)
  $wiersz.Controls.Add($script:LinkZmian)
  $script:PanelStan.Controls.Add($wiersz)

  $script:PanelZmian = Pionowy ($szer - $script:SzerEtykiety)
  $script:PanelZmian.Margin = New-Object System.Windows.Forms.Padding($script:SzerEtykiety, 0, 0, 4)
  foreach ($z in $o.Zmiany) {
    $script:PanelZmian.Controls.Add((Etykieta-Zawijana $z $script:CzMala $script:KolTekst ($szer - $script:SzerEtykiety)))
  }
  if ($o.Porada) {
    $p = Etykieta-Zawijana $o.Porada $script:CzZwykla $script:KolTekst ($szer - $script:SzerEtykiety)
    $p.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    $script:PanelZmian.Controls.Add($p)
  }
  $script:PanelStan.Controls.Add($script:PanelZmian)
  Ustaw-Rozwiniecie-Zmian

  $script:LinkZmian.Add_LinkClicked({
    $script:ZmianyRozwiniete = -not $script:ZmianyRozwiniete
    # Okno nie rosnie od rozwiniecia (P21) - Przeglad sie przewija.
    Ustaw-Rozwiniecie-Zmian
  })
}

function Ustaw-Rozwiniecie-Zmian {
  if (-not $script:PanelZmian -or $script:PanelZmian.IsDisposed) { return }
  $script:PanelZmian.Visible = $script:ZmianyRozwiniete
  if ($script:LinkZmian -and -not $script:LinkZmian.IsDisposed) {
    if ($script:ZmianyRozwiniete) { $script:LinkZmian.Text = "ukryj zmiany" }
    else { $script:LinkZmian.Text = "pokaż zmiany" }
  }
}

function Odmaluj-Przyciski {
  if (-not $script:BCykl -or $script:BCykl.IsDisposed) { return }
  $n = Napisy-Przyciskow $script:Dane $script:Zuzycie $script:Instalacja
  $script:BAktualizuj.Text = $n.Aktualizuj
  $script:LAktualizuj.Text = $n.AktualizujOpis
  $script:BCykl.Text       = $n.Cykl
  $script:LCykl.Text       = $n.CyklOpis
  $script:BCykl.Enabled    = $n.CyklWlaczony
  # P59d: czytanie rozmow tylko z modulem Wiedza (Uloz-Pasek w okno.ps1), obok
  # "Zmień instalację" - nieaktywny, gdy instalatora jeszcze nie ma albo juz jest otwarty.
  Uloz-Pasek $n.CyklJest
  if ($script:BInstalacja -and -not $script:BInstalacja.IsDisposed) {
    $otwarty = Instalator-Otwarty
    $script:BInstalacja.Text = $n.Instalacja
    $script:BInstalacja.Enabled = $n.InstalacjaWlaczona -and -not $otwarty
    if ($otwarty) { $script:LInstalacja.Text = "Instalator otwarty - zmiany pokażę po jego zamknięciu." }
    elseif ($script:NapisInstalacji) { $script:LInstalacja.Text = $script:NapisInstalacji }
    else { $script:LInstalacja.Text = $n.InstalacjaOpis }
  }
}

# DOPASUJ-WYSOKOSC USUNIETE (P21, 30.09.2026). Dobieralo wysokosc okna pod tresc
# Przegladu po KAZDYM odmalowaniu - a tresc rosla w miare dochodzenia danych, wiec
# okno wstawalo w 1089 px (puste karty) i po kilku sekundach skakalo do 1347 px,
# przesuwajac sie w gore. Teraz wysokosc liczy sie raz, przy budowie okna
# (Wysokosc-Okna), a Przeglad, gdy sie nie miesci, przewija sie w miejscu.

function Odmaluj-Okno {
  if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
  # Przewiniecie przezywa odmalowanie - ciche odswiezenie w tle nie ma prawa
  # wyrzucic czytajacego na gore.
  $przewiniecie = 0
  try { if ($script:WidokPrzeglad) { $przewiniecie = -$script:WidokPrzeglad.AutoScrollPosition.Y } }
  catch { Zanotuj-Wywrotke "odczyt przewiniecia przegladu" $_ }
  $script:DoOdmalowania["przeglad"] = $false
  $script:Okno.SuspendLayout()
  try {
    Odmaluj-Podtytul
    Odmaluj-Werdykt
    Odmaluj-Problemy
    Odmaluj-Koszt
    Odmaluj-Start
    Odmaluj-Liczby
    Odmaluj-Stan
    Odmaluj-Przyciski
  } catch {
    Zanotuj-Wywrotke "odmalowanie okna" $_
    if ($script:LPodtytul -and -not $script:LPodtytul.IsDisposed) {
      $script:LPodtytul.ForeColor = $script:KolPilne
      $script:LPodtytul.Text = "NIE UDAŁO SIĘ ZŁOŻYĆ OKNA: $($_.Exception.Message)"
    }
  } finally {
    $script:Okno.ResumeLayout($true)
  }
  if ($przewiniecie -gt 0) {
    try { $script:WidokPrzeglad.AutoScrollPosition = New-Object System.Drawing.Point(0, $przewiniecie) }
    catch { Zanotuj-Wywrotke "przywrocenie przewiniecia przegladu" $_ }
  }
}

# Znacznik dla nadzorca.ps1: ten plik wczytal sie do konca.
$script:ModulyOkna["przeglad"] = $true
