# zasobnik\nadzorca\skille.ps1 - czesc zasobnik\nadzorca.ps1 (patrz BUDOWA
# w jego naglowku). Zakladka Skille: lista w grupach zwijanych (Napelnij-Skille,
# Naglowek-Grupy, Wiersz-Skilla, Przelacz-Grupe), prawa strona (Pokaz-Przeglad-Skilli,
# Pokaz-Info-Skilla, Podglad-Skilla, Ustaw-Przyciski-Skilla) i operacje z przyciskow
# (Rusz-Operacje-Skilli, Sprawdz-Operacje-Skilli - zegar na operacja.txt).
# Skille spoza bazy (P49, Skille-Spoza): grupy "Twoje wlasne" (przyciski paczki),
# "poza opieka" i "zrodlo nieznane" - wiersze z nazwa "__spoza:<folder>".
# Od 2026-10-06 lista ma dwie czesci (Naglowek-Czesci): WBUDOWANE (zrodla z flaga Wbudowane,
# same sie aktualizuja; przycisk "Zainstaluj" przy niezainstalowanych) i INNE WYKRYTE (reszta
# zrodel z bazy z przyciskiem "Sprawdz aktualizacje" + skille spoza bazy). Adresy zrodel to
# klikalne linki (Link-Zrodla); operacje na calym zrodle - Operacja-Na-Zrodle (-ZeZrodla).
# Dane daje Stan-Skilli (stan-nadzorcy.ps1 -> narzedzia\skille.ps1).
# Skad wolane: w-tle.ps1 (Wyrenderuj-Widok -> Napelnij-Skille) i okno.ps1
# (przyciski). Wczytuje go nadzorca.ps1 kropka po zamku jednej kopii - poza stala
# $ZDANIE_BEZPIECZENSTWA same definicje.

# ------------------------------------------------------------ zakladka Skille (P18)
# Dane liczy narzedzia\skille.ps1 -Tryb stan -Json (Stan-Skilli w stan-nadzorcy.ps1) -
# tutaj jest tylko wyglad i przyciski. Przyciski NIE czekaja na koniec operacji: skrypt
# idzie w tle bez okna, a zegar co 2 s zaglada do operacja.txt i odmalowuje zakladke.

$ZDANIE_BEZPIECZENSTWA = "Skille to instrukcje od zewnętrznych autorów. Same, raz dziennie, aktualizują się wyłącznie skille wbudowane w MegaRuchacza (zaufane źródła z górnej części listy); inne wykryte aktualizujesz ręcznie. Każda zmiana jest zapisana i da się ją cofnąć."

# ------------------------------------------------- wbudowane i inne, linki (2026-10-06)
# Uzytkownik: wbudowane w MegaRuchacza = szesc zrodel z flaga Wbudowane w bazie; tylko one
# aktualizuja sie same. Wszystko inne wykryte - z KLIKALNYM linkiem do zrodla (albo
# "zrodlo nieznane") i aktualizacja wylacznie z przycisku.

# Skill z bazy ze zrodla spoza wbudowanych. Brak pola (stary JSON) = jak dotad, wbudowany.
function Czy-Inny($s) { return ($null -ne $s.wbudowane) -and (-not [bool]$s.wbudowane) }

function Adres-Krotko([string]$a) {
  $t = $a.Trim() -replace '^https?://', '' -replace '\.git$', ''
  return $t.TrimEnd('/')
}

# Link otwiera przegladarke uzytkownika - tylko https (adres z bazy, ale baze mozna podmienic).
function Otworz-Adres([string]$a) {
  if ($a -notmatch '^https://[^\s"]+$') { Notuj "skille: link '$a' to nie adres https - nie otwieram"; return }
  Start-Process $a
}

function Link-Zrodla([string]$adres, $czcionka, [int]$szer) {
  $l = New-Object System.Windows.Forms.LinkLabel
  $l.AutoSize = $true
  $l.Font = $czcionka
  $l.BackColor = [System.Drawing.Color]::Transparent
  $l.UseMnemonic = $false
  $l.Text = Adres-Krotko $adres
  $l.Tag = $adres
  if ($szer -gt 0) { $l.MaximumSize = New-Object System.Drawing.Size($szer, 0) }
  $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
  $l.Add_LinkClicked({ param($nadawca, $e) try { Otworz-Adres "$($nadawca.Tag)" } catch { Zanotuj-Wywrotke "link do zrodla skilli" $_ } })
  return $l
}

# Wiersz "Zrodlo" po prawej: etykieta jak w Wiersz-Dwukolumnowy, wartosc - link albo tekst.
function Wiersz-Zrodla([string]$etykieta, [string]$adres, [string]$tekst, [int]$szer, [int]$szerEtykiety) {
  if (-not $adres) { return (Wiersz-Dwukolumnowy $etykieta $tekst $script:KolSzary $szer $szerEtykiety) }
  $w = Poziomy
  $w.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 5)
  $e = Etykieta-Zawijana $etykieta $script:CzZwykla $script:KolSzary ($szerEtykiety - 12)
  $e.MinimumSize = New-Object System.Drawing.Size($szerEtykiety, 0)
  $e.UseMnemonic = $false
  $w.Controls.Add($e)
  $p = Pionowy 0
  if ($tekst) { $t = Etykieta-Zawijana $tekst $script:CzZwykla $script:KolSzary ($szer - $szerEtykiety); $t.UseMnemonic = $false; $p.Controls.Add($t) }
  $p.Controls.Add((Link-Zrodla $adres $script:CzZwykla ($szer - $szerEtykiety)))
  $w.Controls.Add($p)
  return $w
}

# Przycisk w naglowku zrodla: instalacja brakujacych (wbudowane) albo reczna aktualizacja
# (inne). Operacja dotyczy calego zrodla - skille.ps1 -ZeZrodla <id>.
function Operacja-Na-Zrodle([string]$tryb, [string]$zrodlo) {
  if ($script:NadzProba) { return "tryb próbny - przyciski skilli niczego nie uruchamiają" }
  if ($zrodlo -notmatch '^[\w-]+$') { return "nieprawidłowy identyfikator źródła: $zrodlo" }
  $a = "-Tryb $tryb -ZeZrodla $zrodlo"
  if (Odpal-Skille $a) {
    Notuj "skille: z okna ruszyla operacja $a"
    return ""
  }
  return "nie udało się uruchomić narzedzia\skille.ps1 w tle - szczegóły w dzienniku nadzorcy"
}

function Data-Krotko([string]$t) {
  $d = Data-Lub-Nic $t
  if (-not $d) { return "" }
  return $d.ToString('yyyy-MM-dd')
}

function Wersja-Krotko([string]$commit, [string]$data) {
  if (-not $commit) { return "nieznana" }
  $k = $commit.Substring(0, [math]::Min(7, $commit.Length))
  $d = Data-Krotko $data
  if ($d) { return "z $d (oznaczenie $k)" }
  return "oznaczenie $k"
}

# Stan skilla po ludzku: krotki napis na liste i kolor. Blad sprawdzenia wygrywa na
# liscie (czerwony), ale szczegoly mowia tez, co wiadomo z ostatniego udanego razu.
function Napis-Skilla($s) {
  # Spoza bazy (P49): Twoj wlasny (niebieski), znane zrodlo poza opieka (szary),
  # zrodlo nieznane (bursztyn - nie wiadomo, kto go napisal).
  if ($s.spoza) {
    switch ("$($s.rodzaj)") {
      "wlasny" { return @("Twój własny", $script:KolMr) }
      "inne"   { return @("poza opieką MegaRuchacza", $script:KolSzary) }
    }
    return @("źródło nieznane", $script:KolUwaga)
  }
  $wstrzymany = @($s.cele | Where-Object { $_.wstrzymany }).Count -gt 0
  # Wyzerowany po zaniku pradu (P62) - przed bledem sprawdzenia, bo mowi, co zrobic.
  if ($s.wyzerowany) { return @("uszkodzony (same zera) - do naprawy", $script:KolPilne) }
  if ($s.blad) { return @("nie udało się sprawdzić", $script:KolPilne) }
  if ($s.dzisZaktualizowany -and $s.stan -eq "zgodny") { return @("nowa wersja pobrana dziś", $script:KolDobrze) }
  # Autor usunal skill - neutralnie (szaro): to nie usterka, kopia u Ciebie dziala.
  if ($s.stan -eq "usuniety") {
    if ($s.zainstalowany) { return @("autor go usunął - Twoja kopia działa", $script:KolSzary) }
    return @("autor go usunął", $script:KolSzary)
  }
  switch ("$($s.stan)") {
    "zgodny"    { return @("aktualny", $script:KolDobrze) }
    "starszy"   {
      if ($wstrzymany) { return @("cofnięty - nie aktualizuję sam", $script:KolSzary) }
      if (Czy-Inny $s) { return @("nowsza wersja - zaktualizuj ręcznie", $script:KolUwaga) }
      return @("czeka nowsza wersja", $script:KolUwaga) }
    "zmieniony" { return @("zmieniony ręcznie - nie ruszam", $script:KolUwaga) }
    "brak"      { return @("nie zainstalowany", $script:KolSzary) }
    "nieznany"  { return @("jeszcze nie sprawdzony", $script:KolSzary) }
  }
  return @("$($s.stan)", $script:KolSzary)
}

function Zdanie-Stanu-Skilla($s) {
  $wstrzymany = @($s.cele | Where-Object { $_.wstrzymany }).Count -gt 0
  switch ("$($s.stan)") {
    "zgodny"    { return "Masz najnowszą wersję od autora." }
    "starszy"   {
      if ($wstrzymany) { return "Masz starszą wersję, bo cofnąłeś ostatnią aktualizację. Sam jej nie ponowię - kliknij `„Aktualizuj teraz`”, gdy zechcesz." }
      if (Czy-Inny $s) { return "Masz starszą wersję od autora. To źródło nie jest częścią MegaRuchacza, więc sam jej nie podmienię - kliknij `„Aktualizuj teraz`” (z kopią starej wersji)." }
      return "Masz starszą wersję od autora. Nowsza podmieni się sama przy najbliższym codziennym sprawdzeniu (z kopią starej) - albo kliknij `„Aktualizuj teraz`”." }
    "zmieniony" { return "Ktoś zmienił ten skill ręcznie - jego treść nie pasuje do żadnej wersji autora. Nie nadpisuję go sam. `„Aktualizuj teraz`” zapyta o zgodę, a Twoja wersja trafi do kopii." }
    "brak"      { return "Nie masz go zainstalowanego." }
    "nieznany"  { return "Jest na dysku, ale jeszcze go nie sprawdzałem - kliknij `„Sprawdź teraz`”." }
    "usuniety"  {
      $kiedy = Data-Krotko "$($s.usuniety.od)"
      $t = "Autor usunął ten skill ze swojego źródła$(if ($kiedy) { " (zauważone $kiedy)" }) - nowych wersji już nie będzie. To nie jest błąd."
      if ($s.zainstalowany) { return "$t Twoja kopia zostaje nietknięta i działa jak dotąd. Jeśli go nie potrzebujesz, kliknij `„Usuń u mnie`” - zrobię kopię zapasową, więc da się go przywrócić." }
      return "$t Nie masz go, a zainstalować się go już nie da."
    }
  }
  return "$($s.stan)"
}

function Opis-Celu($c) {
  switch ("$($c.stan)") {
    "brak"      { return "nie zainstalowany" }
    "zgodny"    { return "aktualny, wersja $(Wersja-Krotko $c.commit $c.data)" }
    "starszy"   { return "starsza wersja $(Wersja-Krotko $c.commit $c.data)$(if ($c.wstrzymany) { ' - cofnięty, wstrzymany' })" }
    "zmieniony" { return "zmieniony ręcznie" }
    "nieznany"  { return "jeszcze nie sprawdzony" }
  }
  return "$($c.stan)"
}

# Wiersz listy: nazwa i stan w pierwszej linii, opis zawiniety pod spodem. Caly
# wiersz jest klikalny (Tag = nazwa skilla); wybrany ma szare tlo. Wciety wzgledem
# naglowka grupy (P20) - widac, do ktorej grupy nalezy.
function Wiersz-Skilla($s, [int]$szer) {
  $t = New-Object System.Windows.Forms.TableLayoutPanel
  $t.ColumnCount = 2
  $t.RowCount = 2
  $t.AutoSize = $true
  $t.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
  $t.MinimumSize = New-Object System.Drawing.Size($szer, 0)
  $t.MaximumSize = New-Object System.Drawing.Size($szer, 0)
  $t.Padding = New-Object System.Windows.Forms.Padding(34, 7, 12, 7)
  $t.Margin = New-Object System.Windows.Forms.Padding(0)
  $t.BackColor = $script:TloKarty
  $t.Cursor = [System.Windows.Forms.Cursors]::Hand
  $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
  $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null
  $nazwa = "$($s.folder)"
  if ($s.robocza) { $nazwa += "  · wersja robocza autora" }
  $ln = Etykieta $nazwa $script:CzZwyklaGruba $script:KolTekst
  $ln.UseMnemonic = $false
  $ns = Napis-Skilla $s
  $ls = Etykieta $ns[0] $script:CzMalaGruba $ns[1]
  $ls.UseMnemonic = $false
  $ls.Anchor = [System.Windows.Forms.AnchorStyles]::Right
  $lo = Etykieta-Zawijana "$($s.opis)" $script:CzMala $script:KolSzary ($szer - 50)
  $lo.UseMnemonic = $false
  $t.Controls.Add($ln, 0, 0)
  $t.Controls.Add($ls, 1, 0)
  $t.Controls.Add($lo, 0, 1)
  $t.SetColumnSpan($lo, 2)
  foreach ($c in @($t, $ln, $ls, $lo)) {
    $c.Tag = "$($s.nazwa)"
    $c.Add_Click({ param($nadawca, $e) try { Wybierz-Skill "$($nadawca.Tag)" } catch { Zanotuj-Wywrotke "wybor skilla" $_ } })
  }
  # Spoza bazy ze znanym adresem zrodla - klikalny link pod opisem (klik w link nie wybiera wiersza)
  if ($s.spoza -and $s.adres) {
    $t.RowCount = 3
    $lk = Link-Zrodla "$($s.adres)" $script:CzMala ($szer - 50)
    $t.Controls.Add($lk, 0, 2)
    $t.SetColumnSpan($lk, 2)
  }
  # cienka kreska pod wierszem
  $t.Add_Paint({ param($nadawca, $e) try { $e.Graphics.DrawLine($script:PioroRamki, 32, $nadawca.Height - 1, $nadawca.Width - 12, $nadawca.Height - 1) } catch { if (-not $script:RamkaZawiodla) { $script:RamkaZawiodla = $true; Zanotuj-Wywrotke "kreska pod skillem" $_ } } })
  return $t
}

# GRUPY ZWIJANE (P20). Uzytkownik: "skille w apce powinny byc w grupach z mozliwoscia
# rozwiniecia, a nie od razu widoczny kazdy skill". Na starcie lista pokazuje same
# naglowki grup (zrodel); klikniecie naglowka rozwija grupe. Co jest rozwiniete, okno
# pamieta do zamkniecia ($script:GrupySkilli: id -> $true). Grupa z problemem ma
# czerwony pasek z lewej, grupa z nowsza wersja do pobrania - bursztynowy; reszta
# bez paska. Tak samo jak na liscie: kolor tylko tam, gdzie cos wymaga uwagi.

# Liczby grupy: ile skilli, ile masz, ile czeka nowsza wersja, ile ma problem (nie udalo
# sie sprawdzic albo pobrac), ile zmienionych recznie i ile autor usunal.
function Liczby-Grupy($z) {
  $sk = @($z.skille)
  return [pscustomobject]@{
    Ile = $sk.Count
    Masz = @($sk | Where-Object { ($_.stan -ne "brak") -and (($_.stan -ne "usuniety") -or $_.zainstalowany) }).Count
    Starsze = @($sk | Where-Object { $_.stan -eq "starszy" }).Count
    Problem = @($sk | Where-Object { $_.blad }).Count
    Zmienione = @($sk | Where-Object { $_.stan -eq "zmieniony" }).Count
    Usuniete = @($sk | Where-Object { $_.stan -eq "usuniety" }).Count
  }
}

# Opis grupy do naglowka - z danych zrodla ($z) albo recznie (grupa "spoza bazy").
function Grupa-Zrodla($z) {
  $g = [pscustomobject]@{
    Id = "$($z.id)"; Tytul = "$($z.nazwa)"; Opis = "$($z.opis)"; Liczby = ""; Napis = ""; KolorNapisu = $script:KolSzary
    Znacznik = $null; Blad = ""; Uwaga = ""; Rozwijalny = $true
    Adres = "$($z.adres)"; Pominiete = ""; Przycisk = $null
  }
  $wbud = -not ((Czy-Inny $z))
  if ($z.rodzaj -ne "skille") {
    $g.Rozwijalny = $false; $g.Uwaga = "$($z.uwaga)"; $g.Napis = "nic do instalowania"
    return $g
  }
  $g.Uwaga = "$($z.uwaga)"
  $l = Liczby-Grupy $z
  # do zainstalowania: skille, ktorych nie masz (bez usunietych przez autora - tych sie nie da)
  $brak = @(@($z.skille) | Where-Object { $_.stan -eq "brak" }).Count
  if ($wbud) {
    $cz = @($(if ($l.Masz -eq 0) { "NIE ZAINSTALOWANE ($($l.Ile) $(Odmiana $l.Ile 'skill' 'skille' 'skilli'))" } else { "zainstalowane $($l.Masz) z $($l.Ile)" }), "nowsza wersja: $($l.Starsze)", "problem: $($l.Problem)")
    if ($brak -gt 0) {
      $g.Przycisk = [pscustomobject]@{ Tryb = "instaluj"; Zrodlo = $g.Id
        Tekst = $(if ($l.Masz -eq 0) { "Zainstaluj" } else { "Zainstaluj brakujące ($brak)" })
        Opis = "Instaluję $(if ($l.Masz -eq 0) { 'wszystkie skille' } else { "brakujące skille ($brak)" }) ze źródła $($g.Tytul)" }
    }
  } else {
    $cz = @("$($l.Ile) $(Odmiana $l.Ile 'skill' 'skille' 'skilli')", "masz $($l.Masz)", "nowsza wersja: $($l.Starsze)", "problem: $($l.Problem)")
    $g.Przycisk = [pscustomobject]@{ Tryb = "aktualizuj"; Zrodlo = $g.Id; Tekst = "Sprawdź aktualizacje"
      Opis = "Sprawdzam źródło $($g.Tytul) i pobieram nowsze wersje skilli, które masz (ręczna aktualizacja)" }
  }
  if ($l.Zmienione -gt 0) { $cz += "zmienione ręcznie: $($l.Zmienione)" }
  if ($l.Usuniete -gt 0) { $cz += "autor usunął: $($l.Usuniete)" }
  $g.Liczby = $cz -join "   ·   "
  # Zrodlo, z ktorego bierzemy tylko czesc (open-design): ile pominieto i dlaczego
  if ($z.pominiete) {
    $ile = [int]$z.pominiete.ile
    $g.Pominiete = $(if ($ile -ge 0) { "pominięte: $ile - $($z.pominiete.opis)" } else { "pominięte: policzę przy pierwszym sprawdzeniu źródła - $($z.pominiete.opis)" })
  }
  if ($z.blad) {
    $g.Blad = "Nie udało się pobrać ($(Data-Krotko $z.sprawdzono)): $($z.blad)"
    $g.Napis = "błąd pobrania"; $g.KolorNapisu = $script:KolPilne; $g.Znacznik = $script:KolPilne
  } elseif ($l.Problem -gt 0) {
    $g.Napis = "problem: $($l.Problem)"; $g.KolorNapisu = $script:KolPilne; $g.Znacznik = $script:KolPilne
  } elseif ($l.Starsze -gt 0) {
    $g.Napis = $(if ($wbud) { "nowsza wersja: $($l.Starsze)" } else { "nowsza wersja: $($l.Starsze) - ręcznie" })
    $g.KolorNapisu = $script:KolUwaga; $g.Znacznik = $script:KolUwaga
  } elseif ($wbud -and $l.Masz -eq 0) {
    $g.Napis = "NIE ZAINSTALOWANE"; $g.KolorNapisu = $script:KolTekst
  } else {
    $g.Napis = "w porządku"
  }
  return $g
}

function Naglowek-Grupy($g, [int]$szer) {
  $rozw = $g.Rozwijalny -and [bool]$script:GrupySkilli[$g.Id]
  $script:ZnacznikiGrup[$g.Id] = $g.Znacznik
  $t = New-Object System.Windows.Forms.TableLayoutPanel
  $t.ColumnCount = 2
  $t.RowCount = 4
  $t.AutoSize = $true
  $t.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
  $t.MinimumSize = New-Object System.Drawing.Size($szer, 0)
  $t.MaximumSize = New-Object System.Drawing.Size($szer, 0)
  $t.Padding = New-Object System.Windows.Forms.Padding(16, 10, 12, 10)
  $t.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 1)
  $t.BackColor = $script:TloZnacz
  if ($g.Rozwijalny) { $t.Cursor = [System.Windows.Forms.Cursors]::Hand }
  $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
  $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null
  $ln = Etykieta-Zawijana (Tytul-Naglowka $g.Tytul $g.Rozwijalny $rozw) $script:CzGruba $script:KolTekst ($szer - 190)
  $ln.UseMnemonic = $false
  $ls = Etykieta $g.Napis $script:CzMalaGruba $g.KolorNapisu
  $ls.UseMnemonic = $false
  $ls.Anchor = [System.Windows.Forms.AnchorStyles]::Right
  $t.Controls.Add($ln, 0, 0)
  $t.Controls.Add($ls, 1, 0)
  $wiersz = 1
  $wciecie = $(if ($g.Rozwijalny) { 20 } else { 0 })
  # pod tytulem: klikalny adres zrodla, potem opis, liczby, pominiete, blad, uwaga, przycisk
  $wiersze = New-Object System.Collections.Generic.List[object]
  if ($g.Adres) { $wiersze.Add((Link-Zrodla "$($g.Adres)" $script:CzMala ($szer - 50))) }
  foreach ($para in @(@($g.Opis, $script:KolSzary), @($g.Liczby, $script:KolTekst), @($g.Pominiete, $script:KolSzary), @($g.Blad, $script:KolPilne), @($g.Uwaga, $script:KolUwaga))) {
    if (-not $para[0]) { continue }
    $l = Etykieta-Zawijana $para[0] $script:CzMala $para[1] ($szer - 50)
    $l.UseMnemonic = $false
    $wiersze.Add($l)
  }
  if ($g.Przycisk) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = "$($g.Przycisk.Tekst)"
    $b.Font = $script:CzMala
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::System
    $b.AutoSize = $true
    $b.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $b.UseMnemonic = $false
    $b.Tag = $g.Przycisk
    $b.Enabled = -not [bool]$script:SkilleOperacjaOd
    $b.Add_Click({ param($nadawca, $e)
      try { $p = $nadawca.Tag; Rusz-Operacje-Skilli "$($p.Tryb)" "" $false "$($p.Opis)" "$($p.Zrodlo)" }
      catch { Zanotuj-Wywrotke "przycisk zrodla skilli" $_ } })
    $script:PrzyciskiZrodel += $b
    $wiersze.Add($b)
  }
  foreach ($l in $wiersze) {
    $l.Margin = New-Object System.Windows.Forms.Padding($wciecie, $(if ($l -is [System.Windows.Forms.Button]) { 6 } else { 2 }), 0, 0)
    if ($wiersz -ge $t.RowCount) { $t.RowCount = $wiersz + 1 }
    $t.Controls.Add($l, 0, $wiersz)
    $t.SetColumnSpan($l, 2)
    $wiersz++
  }
  if ($g.Rozwijalny) {
    # link i przycisk maja wlasne dzialanie - ich klikniecie nie zwija grupy
    foreach ($c in @($t) + @($t.Controls | Where-Object { -not ($_ -is [System.Windows.Forms.LinkLabel]) -and -not ($_ -is [System.Windows.Forms.ButtonBase]) })) {
      $c.Tag = $g.Id
      $c.Add_Click({ param($nadawca, $e) try { Przelacz-Grupe "$($nadawca.Tag)" } catch { Zanotuj-Wywrotke "rozwiniecie grupy skilli" $_ } })
    }
  } else { $t.Tag = $g.Id }
  # pasek z lewej (kolor stanu grupy) i kreska pod naglowkiem
  $t.Add_Paint({ param($nadawca, $e)
    try {
      $kol = $script:ZnacznikiGrup["$($nadawca.Tag)"]
      if ($null -ne $kol) {
        $pedzel = New-Object System.Drawing.SolidBrush($kol)
        try { $e.Graphics.FillRectangle($pedzel, 0, 0, 5, $nadawca.Height) } finally { $pedzel.Dispose() }
      }
      $e.Graphics.DrawLine($script:PioroRamki, 0, $nadawca.Height - 1, $nadawca.Width, $nadawca.Height - 1)
    } catch { if (-not $script:RamkaZawiodla) { $script:RamkaZawiodla = $true; Zanotuj-Wywrotke "pasek grupy skilli" $_ } }
  })
  $script:NaglowkiGrup[$g.Id] = $t
  # Rejestr grupy (P50): Przelacz-Grupe chowa/pokazuje jej wiersze zamiast budowac liste od nowa.
  $script:GrupyListy[$g.Id] = [pscustomobject]@{
    Naglowek = $t; Strzalka = $ln; Tytul = $g.Tytul; Rozwijalny = $g.Rozwijalny; Szer = $szer
    Zrodlo = $null; Skille = @(); Wiersze = (New-Object System.Collections.Generic.List[object]); Zbudowane = $false
  }
  return $t
}

# Naglowek czesci listy (wbudowane / inne wykryte) - sam napis, nie grupa: nie zwija sie.
function Naglowek-Czesci([string]$tytul, [string]$dopisek, [int]$szer) {
  $p = Pionowy $szer
  $p.MaximumSize = New-Object System.Drawing.Size($szer, 0)
  $p.Padding = New-Object System.Windows.Forms.Padding(6, 14, 12, 6)
  $p.BackColor = $script:TloKarty
  $l = Etykieta-Zawijana "$tytul - $dopisek" $script:CzMalaGruba $script:KolSzary ($szer - 30)
  $l.UseMnemonic = $false
  $p.Controls.Add($l)
  return $p
}

# strzalka: rozwinieta w dol, zwinieta w prawo (znaki z Unicode, zeby nie zalezaly od kodowania pliku)
function Tytul-Naglowka([string]$tytul, [bool]$rozwijalny, [bool]$rozw) {
  if (-not $rozwijalny) { return $tytul }
  return $(if ($rozw) { [string][char]0x25BC } else { [string][char]0x25B6 }) + "  " + $tytul
}

# Wiersze grupy (wiersz sprawdzenia zrodla i skille) - budowane przy pierwszym rozwinieciu
# i zapamietane w $gr.Wiersze; kolejne klikniecia tylko je chowaja i pokazuja.
function Wiersze-Grupy($gr) {
  $wynik = New-Object System.Collections.Generic.List[object]
  $sk = $gr.Skille
  if ($gr.Zrodlo) { $wynik.Add((Wiersz-Sprawdzenia $gr.Zrodlo $gr.Szer)); $sk = @($gr.Zrodlo.skille) }
  foreach ($s in @($sk)) {
    $w = Wiersz-Skilla $s $gr.Szer
    $script:WierszeSkilli["$($s.nazwa)"] = $w
    $script:GrupaWiersza["$($s.nazwa)"] = "$($gr.Naglowek.Tag)"
    if ("$($s.nazwa)" -eq $script:SkillWybrany) { $w.BackColor = $script:TloPrzel }
    $wynik.Add($w)
  }
  foreach ($w in $wynik) { $gr.Wiersze.Add($w) }
  $gr.Zbudowane = $true
  return ,$wynik
}

# Wiersz pod naglowkiem rozwinietej grupy: kiedy sprawdzone i jaka jest najnowsza wersja.
function Wiersz-Sprawdzenia($z, [int]$szer) {
  $p = Pionowy $szer
  $p.Padding = New-Object System.Windows.Forms.Padding(34, 6, 12, 4)
  $p.BackColor = $script:TloKarty
  $t = $(if ($z.sprawdzono) { "Sprawdzone $($z.sprawdzono). Najnowsza wersja autora: $(Wersja-Krotko $z.commit $z.data)." } else { "Jeszcze nie sprawdzane." })
  $l = Etykieta-Zawijana $t $script:CzMala $script:KolSzary ($szer - 50)
  $l.UseMnemonic = $false
  $p.Controls.Add($l)
  return $p
}

# P50 - "dziwnie miga": wczesniej kazde klikniecie budowalo CALA liste od nowa (45-333
# kontrolek zwalnianych i tworzonych, 0,7-4 s, lista znikala kawalkami). Teraz: wiersze
# grupy powstaja raz, potem tylko Visible; rysowanie wstrzymane do konca zmiany,
# przewijanie zostaje tam, gdzie bylo.
function Przelacz-Grupe([string]$id) {
  if (-not $id) { return }
  $lista = $script:ListaSkilli
  $gr = $script:GrupyListy[$id]
  $rozw = -not [bool]$script:GrupySkilli[$id]
  $script:GrupySkilli[$id] = $rozw
  if (-not $gr -or $gr.Naglowek.IsDisposed -or -not $lista -or $lista.IsDisposed) {
    # rejestru nie ma (nie powinno sie zdarzyc) - stara droga, przebudowa listy
    Notuj "rozwiniecie grupy skilli '$id' bez rejestru grupy - przebudowa calej listy"
    Napelnij-Skille $true
    $n = $script:NaglowkiGrup[$id]
    if ($n -and -not $n.IsDisposed) { $script:ListaSkilli.ScrollControlIntoView($n) }
    return
  }
  $wnetrze = $lista.Controls[0]
  $poz = $lista.AutoScrollPosition
  $wstrzymane = Wstrzymaj-Rysowanie $lista.Parent
  $lista.SuspendLayout()
  $wnetrze.SuspendLayout()
  try {
    if ($rozw -and -not $gr.Zbudowane) {
      $i = $wnetrze.Controls.GetChildIndex($gr.Naglowek)
      foreach ($w in (Wiersze-Grupy $gr)) { $wnetrze.Controls.Add($w); $i++; $wnetrze.Controls.SetChildIndex($w, $i) }
    } else {
      foreach ($w in $gr.Wiersze) { if (-not $w.IsDisposed) { $w.Visible = $rozw } }
    }
    $gr.Strzalka.Text = Tytul-Naglowka $gr.Tytul $true $rozw
  } finally {
    $wnetrze.ResumeLayout($true)
    $lista.ResumeLayout($true)
    # AutoScrollPosition czyta sie ujemnie, a ustawia dodatnio
    $lista.AutoScrollPosition = New-Object System.Drawing.Point((-$poz.X), (-$poz.Y))
    if ($wstrzymane) { Wznow-Rysowanie $lista.Parent }
  }
  $lista.ScrollControlIntoView($gr.Naglowek)
}

function Znajdz-Skill([string]$nazwa) {
  if (-not $script:DaneSkilli -or -not $script:DaneSkilli.Dane) { return $null }
  if ($nazwa.StartsWith("__spoza:")) {
    foreach ($s in @(Skille-Spoza $script:DaneSkilli.Dane)) { if ($s.nazwa -eq $nazwa) { return @($s, $null) } }
    return $null
  }
  foreach ($z in @($script:DaneSkilli.Dane.zrodla)) {
    foreach ($s in @($z.skille)) { if ($s.nazwa -eq $nazwa) { return @($s, $z) } }
  }
  return $null
}

# Skille spoza bazy jako wiersze listy (P49): jeden na katalog, choc moze lezec w kilku
# miejscach (np. orchestration u Claude Code i Codeksa). Nazwa z przedrostkiem __spoza:,
# zeby nie zderzyla sie z nazwa skilla z bazy.
function Skille-Spoza($d) {
  $wynik = [ordered]@{}
  foreach ($x in @($d.spozaBazy)) {
    if ($null -eq $x) { continue }
    $k = "$($x.folder)"
    if (-not $wynik.Contains($k)) {
      $rodzaj = "$($x.rodzaj)"; if (-not $rodzaj) { $rodzaj = "nieznane" }
      $opis = "$($x.opis)"
      if (-not $opis) { $opis = $(if ($x.opisAutora) { "Opis autora (po angielsku): $($x.opisAutora)" } else { "Brak opisu - w katalogu nie ma pliku SKILL.md z opisem." }) }
      $wynik[$k] = [pscustomobject]@{
        spoza = $true; nazwa = "__spoza:$k"; folder = $k; rodzaj = $rodzaj; opis = $opis; skad = "$($x.skad)"; uwaga = "$($x.uwaga)"; adres = "$($x.adres)"
        robocza = $false; cele = @(); miejsca = @(); dowiazanie = $false
      }
    }
    $w = $wynik[$k]
    # nazwaCelu niesie kazdy katalog (takze ~\.config\opencode\skills, ktory nie jest celem);
    # stary JSON bez tego pola - nazwa z listy celow
    $nazwaCelu = "$($x.nazwaCelu)"
    if (-not $nazwaCelu) {
      $nazwaCelu = "$($x.cel)"
      foreach ($c in @($d.cele)) { if ($c.id -eq $x.cel) { $nazwaCelu = "$($c.nazwa)" } }
    }
    $w.miejsca += "$nazwaCelu - $($x.sciezka)$(if ($x.dowiazanie) { ' (dowiązanie)' })"
    if ($x.dowiazanie) { $w.dowiazanie = $true }
  }
  return @($wynik.Values)
}

function Zdanie-Skilli($d) {
  $l = $d.liczniki
  $t = ""
  if ($null -ne $l.wbudSkilli) {
    # osobno wbudowane (same sie aktualizuja) i inne wykryte (tylko recznie)
    $wbudBrak = [int]$l.wbudSkilli - [int]$l.wbudZainstalowane
    $t += "Wbudowane w MegaRuchacza (same się aktualizują): zainstalowane $($l.wbudZainstalowane) z $($l.wbudSkilli) $(Odmiana $l.wbudSkilli 'skilla' 'skilli' 'skilli') ($($l.wbudZrodel) $(Odmiana $l.wbudZrodel 'źródło' 'źródła' 'źródeł'))"
    if ($wbudBrak -gt 0) { $t += ", niezainstalowane: $wbudBrak" }
    if ($l.wbudStarsze -gt 0) { $t += ", czeka nowsza wersja: $($l.wbudStarsze)" }
    $t += "."
    $sp = @(Skille-Spoza $d)
    $czInne = @()
    if ($l.inneZrodel -gt 0) { $czInne += "$($l.inneZainstalowane) $(Odmiana $l.inneZainstalowane 'skill' 'skille' 'skilli') z $($l.inneZrodel) $(Odmiana $l.inneZrodel 'źródła' 'źródeł' 'źródeł') z bazy" }
    $ileInne = @($sp | Where-Object { $_.rodzaj -eq "inne" }).Count
    if ($ileInne -gt 0) { $czInne += "poza opieką: $ileInne" }
    if ($l.wlasne -gt 0) { $czInne += "Twoje własne: $($l.wlasne)" }
    if ($l.nieznane -gt 0) { $czInne += "o nieznanym źródle: $($l.nieznane)" }
    if ($czInne.Count -gt 0) {
      $t += " Inne wykryte (aktualizujesz ręcznie): " + ($czInne -join ", ")
      if ($l.inneStarsze -gt 0) { $t += "; nowsza wersja czeka w $($l.inneStarsze)" }
      $t += "."
    }
    if ($l.zmienione -gt 0) { $t += " Zmienione ręcznie: $($l.zmienione)." }
  } else {
    $t += "W bazie $($l.wBazie) $(Odmiana $l.wBazie 'skill' 'skille' 'skilli') - aktualne: $($l.zgodne), czeka nowsza wersja: $($l.starsze), zmienione ręcznie: $($l.zmienione), niezainstalowane: $($l.brak)."
    if ($l.wlasne -gt 0) { $t += " Twoje własne: $($l.wlasne)." }
    if ($l.nieznane -gt 0) { $t += " O nieznanym źródle: $($l.nieznane)." }
  }
  if ($l.usuniete -gt 0) { $t += " Autor usunął: $($l.usuniete)." }
  if ($l.dzisZaktualizowane -gt 0) { $t += " Dziś pobrano nowe wersje: $($l.dzisZaktualizowane)." }
  if ($l.bledy -gt 0) { $t += " Nie udało się sprawdzić: $($l.bledy)." }
  $zn = $d.znacznik
  if ($zn -and $zn.dzien) {
    $t += " Codzienne sprawdzenie: $($zn.start)"
    if ($zn.wynik -eq "blad") { $t += " - BŁĄD." } elseif ($zn.wynik -eq "pracuje") { $t += " - trwa." } else { $t += " - w porządku." }
  } else { $t += " Codziennego sprawdzenia jeszcze nie było." }
  return $t
}

# $tylkoLista - rozwiniecie/zwiniecie grupy: przebudowa samej listy z danych, ktore juz
# sa, bez ruszania prawej strony (wynik operacji ani wybrany skill nie znikaja).
# Samo rysowanie - stan skilli liczy krok w tle "skille" (P21).
function Napelnij-Skille([bool]$tylkoLista = $false) {
  if (-not $script:ListaSkilli -or $script:ListaSkilli.IsDisposed) { return }
  if ($null -eq $script:DaneSkilli) { return }
  if (-not $tylkoLista) { $script:DoOdmalowania["skille"] = $false }
  $ds = $script:DaneSkilli
  $lista = $script:ListaSkilli
  $wnetrze = $lista.Controls[0]
  # P50: rysowanie wstrzymane, a uklad wnetrza zawieszony JUZ przed czyszczeniem - wczesniej
  # zwalnianie wierszy liczylo uklad 98-166 razy i wymazywalo tlo na oczach uzytkownika.
  # Wstrzymana jest KARTA wokol listy, nie sama lista: lista ze wstrzymanym rysowaniem jest dla
  # Windows niewidoczna, wiec gdy pojawia sie albo znika pasek przewijania, karta zamalowywala
  # cala liste na bialo (zmierzone - jedno wymazanie karty przy kazdym takim kliknieciu).
  $wstrzymane = Wstrzymaj-Rysowanie $lista.Parent
  $lista.SuspendLayout()
  $wnetrze.SuspendLayout()
  try {
    $script:WierszeSkilli = @{}
    $script:GrupaWiersza = @{}
    $script:NaglowkiGrup = @{}
    $script:ZnacznikiGrup = @{}
    $script:GrupyListy = @{}
    $script:PrzyciskiZrodel = @()
    Wyczysc-Panel $wnetrze
    if ($ds.Powod -or -not $ds.Dane) {
      $script:LSkille.ForeColor = $script:KolPilne
      $script:LSkille.Text = "NIE UDAŁO SIĘ ZEBRAĆ LISTY SKILLI: $($ds.Powod)"
      Pokaz-Info-Skilla $null
      $script:SkillePodglad.Text = ("Lista jest pusta, bo jej zebranie się nie udało - to nie znaczy, że nie masz skilli." + "`r`n`r`n" +
        "Powód: $($ds.Powod)" + "`r`n`r`n" + "Spróbuj ręcznie:" + "`r`n" +
        "powershell -ExecutionPolicy Bypass -File $(Skrypt-Skilli)")
      return
    }
    $d = $ds.Dane
    # wiersze dokladane jeden po drugim - uklad liczony raz, na koncu (rozwiniecie grupy ~2x szybciej)
    $szer = [math]::Max(300, $lista.ClientSize.Width - [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth - 2)
    # Dwie czesci listy (2026-10-06): na gorze zrodla wbudowane w MegaRuchacza, pod nimi
    # wszystko inne wykryte - zrodla z bazy bez flagi Wbudowane i skille spoza bazy.
    $wbudZ = @(@($d.zrodla) | Where-Object { -not (Czy-Inny $_) })
    $inneZ = @(@($d.zrodla) | Where-Object { Czy-Inny $_ })
    $spoza = @(Skille-Spoza $d)
    if ($wbudZ.Count -gt 0) { $wnetrze.Controls.Add((Naglowek-Czesci "WBUDOWANE W MEGARUCHACZA" "aktualizują się same raz dziennie" $szer)) }
    $czescInne = $false
    foreach ($z in @($wbudZ + $inneZ)) {
      if ((Czy-Inny $z) -and -not $czescInne) {
        $wnetrze.Controls.Add((Naglowek-Czesci "INNE WYKRYTE" "nie są częścią MegaRuchacza - aktualizujesz je ręcznie" $szer))
        $czescInne = $true
      }
      $g = Grupa-Zrodla $z
      $wnetrze.Controls.Add((Naglowek-Grupy $g $szer))
      $script:GrupyListy[$g.Id].Zrodlo = $z
      if (-not ($g.Rozwijalny -and $script:GrupySkilli[$g.Id])) { continue }
      foreach ($w in (Wiersze-Grupy $script:GrupyListy[$g.Id])) { $wnetrze.Controls.Add($w) }
    }
    if (($spoza.Count -gt 0) -and -not $czescInne) {
      $wnetrze.Controls.Add((Naglowek-Czesci "INNE WYKRYTE" "nie są częścią MegaRuchacza - aktualizujesz je ręcznie" $szer))
    }
    # Spoza bazy (P49): trzy grupy - Twoje wlasne (z przyciskiem paczki), znane zrodla
    # poza opieka i zrodlo nieznane. Kazdy skill to klikalny wiersz jak w zrodlach.
    $grupySpoza = @(
      @{ Id = "__wlasne"; Rodzaj = "wlasny"; Tytul = "Twoje własne skille"; Opis = "Powstały w Twoich rozmowach. MegaRuchacz ich nie zmienia - możesz je spakować i przekazać innym (kliknij skill)." }
      @{ Id = "__inne"; Rodzaj = "inne"; Tytul = "Z innych źródeł, poza opieką MegaRuchacza"; Opis = "Wiadomo, skąd są (link przy skillu), ale aktualizuje je inne narzędzie - MegaRuchacz ich nie rusza." }
      @{ Id = "__nieznane"; Rodzaj = "nieznane"; Tytul = "Źródło nieznane"; Opis = "Nie pasują do żadnego znanego źródła ani do Twoich rozmów. MegaRuchacz ich nie sprawdza i nie rusza." }
    )
    foreach ($gs in $grupySpoza) {
      $te = @($spoza | Where-Object { $_.rodzaj -eq $gs.Rodzaj })
      if ($te.Count -eq 0) { continue }
      $g = [pscustomobject]@{
        Id = $gs.Id; Tytul = $gs.Tytul; Opis = $gs.Opis
        Liczby = "$($te.Count) $(Odmiana $te.Count 'skill' 'skille' 'skilli')"; Napis = ""; KolorNapisu = $script:KolSzary
        Znacznik = $null; Blad = ""; Uwaga = ""; Rozwijalny = $true
      }
      $wnetrze.Controls.Add((Naglowek-Grupy $g $szer))
      $script:GrupyListy[$gs.Id].Skille = $te
      if (-not $script:GrupySkilli[$gs.Id]) { continue }
      foreach ($w in (Wiersze-Grupy $script:GrupyListy[$gs.Id])) { $wnetrze.Controls.Add($w) }
    }
    if ($tylkoLista) {
      # sam wybrany wiersz podswietlony (jesli jego grupa jest rozwinieta), prawa strona bez zmian
      $w = $script:WierszeSkilli[$script:SkillWybrany]
      if ($w) { $w.BackColor = $script:TloPrzel }
      return
    }
    $script:LSkille.ForeColor = $script:KolTekst
    if ($d.liczniki.bledy -gt 0 -or ($d.znacznik -and $d.znacznik.wynik -eq "blad")) { $script:LSkille.ForeColor = $script:KolPilne }
    $script:LSkille.Text = Zdanie-Skilli $d
    if ($script:SkillWybrany -and (Znajdz-Skill $script:SkillWybrany)) { Wybierz-Skill $script:SkillWybrany }
    else { $script:SkillWybrany = ""; Pokaz-Info-Skilla $null; Pokaz-Przeglad-Skilli }
  } finally {
    $wnetrze.ResumeLayout($true)
    $lista.ResumeLayout($true)
    if ($wstrzymane) { Wznow-Rysowanie $lista.Parent }
    # etykieta sama dopasowuje wysokosc (AutoSize z MaximumSize)
  }
}

# Prawa strona, gdy nic nie jest wybrane: czym jest ta zakladka, ostatnie codzienne
# sprawdzenie i ostatnia operacja - zeby wynik klikniecia nie znikal po odswiezeniu.
function Pokaz-Przeglad-Skilli {
  if (-not $script:SkillePodglad -or $script:SkillePodglad.IsDisposed) { return }
  $d = $script:DaneSkilli.Dane
  $l = New-Object System.Collections.Generic.List[string]
  $l.Add("Kliknij grupę po lewej, żeby ją rozwinąć, a potem skill - zobaczysz, co robi, jaką masz wersję i co się zmieniło przy ostatniej aktualizacji. Grupa z czerwonym paskiem ma problem, z bursztynowym - nowszą wersję do pobrania.")
  $l.Add("")
  $l.Add("Jak to działa:")
  $l.Add("- Raz dziennie MegaRuchacz sam pobiera nowsze wersje skilli WBUDOWANYCH (górna część listy), które masz pod opieką. Gdy któregoś źródła nie masz wcale, przy jego nazwie jest przycisk `„Zainstaluj`”.")
  $l.Add("- Skille z innych wykrytych źródeł (dolna część listy) nie są częścią MegaRuchacza - sam ich nie aktualizuje. Robisz to ręcznie: `„Sprawdź aktualizacje`” przy źródle albo `„Aktualizuj teraz`” przy skillu. Link przy źródle prowadzi do jego repozytorium.")
  $l.Add("- Gdy pobranie się nie uda, próbuje jeszcze 5 razy (po 5 s, 15 s, 30 s, 1 min i 2 min). Błąd pokazuje dopiero wtedy, gdy wszystkie próby zawiodą.")
  $l.Add("- Gdy autor przeniesie skill w swoim repozytorium, MegaRuchacz sam go znajdzie. Gdy autor skill usunie, Twoja kopia zostaje i działa dalej.")
  $l.Add("- Przed każdą podmianą robi kopię starej wersji. `„Cofnij ostatnią aktualizację`” przywraca ją co do bajtu.")
  $l.Add("- Skilla zmienionego ręcznie nie nadpisuje nigdy sam.")
  $gdzieJest = @($d.cele | Where-Object { $_.jest })
  if ($gdzieJest.Count -eq 0) {
    $l.Add("- Gdzie instaluje: nigdzie - nie widzę na tym komputerze Claude Code, Codeksa ani OpenCode. Skille wbudowane wgram, gdy któreś się pojawi.")
  } else {
    $l.Add("- Gdzie instaluje: " + ((@($gdzieJest) | ForEach-Object { "$($_.nazwa) ($($_.katalog))" }) -join "; ") + ".")
  }
  if (@($d.narzedzia | Where-Object { $_.id -eq "opencode" -and $_.jest }).Count -gt 0) {
    $l.Add("- OpenCode nie dostaje osobnej kopii: sam czyta katalogi Claude Code i Codeksa (oraz swój ~\.config\opencode\skills). Gdy masz i Claude Code, i Codeksa, widzi ten sam skill dwa razy i zapisuje to w swoim dzienniku jako ostrzeżenie - obie kopie są te same i aktualizują się razem.")
  }
  foreach ($u in @($d.uwagi)) { if ($u) { $l.Add("- $u") } }
  $zn = $d.znacznik
  $l.Add("")
  if ($zn -and $zn.dzien) {
    $l.Add("Ostatnie codzienne sprawdzenie: $($zn.start) - $($zn.koniec), wynik: $(if ($zn.wynik -eq 'ok') { 'w porządku' } else { $zn.wynik }), pobranych nowych wersji: $($zn.zaktualizowano).")
    if ($zn.pierwszy -eq "True") { $l.Add("To był pierwszy przebieg na tym komputerze - tylko spisał, co masz. Nowsze wersje pobiera od następnego.") }
    if ($zn.powod) { $l.Add("Powód błędu: $($zn.powod)") }
  } else { $l.Add("Codziennego sprawdzenia jeszcze nie było - ruszy samo w ciągu kwadransa.") }
  $op = $d.operacja
  if ($op -and $op.tryb -and $op.tryb -ne "codziennie") {
    $l.Add("Ostatnia operacja z przycisku: $($op.tryb) $($op.skill)$(if ($op.zrodlo) { 'źródło ' + $op.zrodlo }) - $($op.start), wynik: $($op.wynik).")
    if ($op.powod) { $l.Add("Powód: $($op.powod)") }
  }
  $l.Add("")
  $l.Add("Dziennik zmian: $($d.dziennik)")
  $l.Add("Kopie zapasowe: $($d.kopie)")
  $script:SkillePodglad.Text = ($l -join "`r`n")
}

function Pokaz-Info-Skilla($para) {
  $info = $script:SkilleInfo
  if (-not $info -or $info.IsDisposed) { return }
  $info.SuspendLayout()
  try {
    Wyczysc-Panel $info
    $szer = [math]::Max(300, $info.Parent.ClientSize.Width - $info.Parent.Padding.Horizontal - 12)
    if (-not $para) {
      $t = Etykieta-Zawijana "Polecane skille" $script:CzSrednia $script:KolTekst $szer
      $info.Controls.Add($t)
      Ustaw-Przyciski-Skilla $null
      return
    }
    $s = $para[0]; $z = $para[1]
    $tyt = "$($s.folder)"
    $t = Etykieta-Zawijana $tyt $script:CzSrednia $script:KolTekst $szer
    $t.UseMnemonic = $false
    $t.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $info.Controls.Add($t)
    $e = 130
    if ($s.spoza) {
      $ns = Napis-Skilla $s
      $info.Controls.Add((Wiersz-Dwukolumnowy "Do czego jest" "$($s.opis)" $script:KolTekst $szer $e))
      $info.Controls.Add((Wiersz-Dwukolumnowy "Rodzaj" $ns[0] $ns[1] $szer $e))
      $skad = $(if ($s.skad) { "$($s.skad)" } elseif ($s.rodzaj -eq "nieznane") { "Nie wiadomo - nie pasuje do żadnego źródła z bazy ani do Twoich rozmów, w których powstawały skille." } else { "" })
      if ($skad) { $info.Controls.Add((Wiersz-Dwukolumnowy "Skąd jest" $skad $script:KolTekst $szer $e)) }
      if ($s.adres) { $info.Controls.Add((Wiersz-Zrodla "Źródło" "$($s.adres)" "" $szer $e)) }
      elseif ($s.rodzaj -eq "nieznane") { $info.Controls.Add((Wiersz-Dwukolumnowy "Źródło" "źródło nieznane" $script:KolUwaga $szer $e)) }
      if ($s.uwaga) { $info.Controls.Add((Wiersz-Dwukolumnowy "Uwaga" "$($s.uwaga)" $script:KolUwaga $szer $e)) }
      $info.Controls.Add((Wiersz-Dwukolumnowy "Gdzie leży" (@($s.miejsca) -join "`r`n") $script:KolSzary $szer $e))
      Ustaw-Przyciski-Skilla $s
      return
    }
    $info.Controls.Add((Wiersz-Dwukolumnowy "Do czego jest" "$($s.opis)" $script:KolTekst $szer $e))
    $ns = Napis-Skilla $s
    $info.Controls.Add((Wiersz-Dwukolumnowy "Stan" (Zdanie-Stanu-Skilla $s) $ns[1] $szer $e))
    if ($s.blad) { $info.Controls.Add((Wiersz-Dwukolumnowy "Błąd" "$($s.blad)" $script:KolPilne $szer $e)) }
    if ($s.przeniesiony) {
      $info.Controls.Add((Wiersz-Dwukolumnowy "Przeniesiony" "Autor przeniósł go w swoim repo z $($s.przeniesiony.z) do $($s.przeniesiony.na) (zauważone $(Data-Krotko "$($s.przeniesiony.kiedy)")). MegaRuchacz sam bierze go z nowego miejsca." $script:KolSzary $szer $e))
    }
    foreach ($c in @($s.cele)) {
      $oc = Opis-Celu $c
      # przy skillu usunietym przez autora "aktualny" nic nie znaczy - jest po prostu Twoja kopia
      if ($s.stan -eq "usuniety" -and $c.stan -ne "brak") { $oc = "masz kopię$(if ($c.commit) { ' - ostatnia wersja od autora ' + (Wersja-Krotko $c.commit $c.data) })" }
      $info.Controls.Add((Wiersz-Dwukolumnowy "$($c.nazwa)" $oc $script:KolTekst $szer $e))
    }
    if ($s.najnowszy) { $info.Controls.Add((Wiersz-Dwukolumnowy "Najnowsza" (Wersja-Krotko $s.najnowszy.commit $s.najnowszy.data) $script:KolTekst $szer $e)) }
    if ($s.sprawdzono) { $info.Controls.Add((Wiersz-Dwukolumnowy "Sprawdzone" "$($s.sprawdzono)" $script:KolTekst $szer $e)) }
    $info.Controls.Add((Wiersz-Zrodla "Źródło" "$($z.adres)" "$($z.nazwa)" $szer $e))
    $akt = $(if (Czy-Inny $s) { "Tylko ręcznie (`„Aktualizuj teraz`” albo `„Sprawdź aktualizacje`” przy źródle) - to źródło nie jest częścią MegaRuchacza." } else { "Sama, raz dziennie - źródło wbudowane w MegaRuchacza." })
    $info.Controls.Add((Wiersz-Dwukolumnowy "Aktualizacja" $akt $script:KolSzary $szer $e))
    Ustaw-Przyciski-Skilla $s
  } finally { $info.ResumeLayout($true) }
}

function Ustaw-Przyciski-Skilla($s) {
  $pracuje = [bool]$script:SkilleOperacjaOd
  $script:BSkilleTeraz.Enabled = -not $pracuje
  foreach ($b in @($script:PrzyciskiZrodel)) { if ($b -and -not $b.IsDisposed) { $b.Enabled = -not $pracuje } }
  $script:SkillePrzyciski.Visible = [bool]$s
  if (-not $s) { return }
  # Spoza bazy (P49): zadnych operacji ze zrodla; Twoj wlasny ma dwa przyciski paczki.
  $wlasny = [bool]$s.spoza -and ($s.rodzaj -eq "wlasny")
  foreach ($b in @($script:BSkillSpakuj, $script:BSkillSpakujWszystkie)) { $b.Visible = $wlasny; $b.Enabled = $wlasny -and -not $pracuje }
  foreach ($b in @($script:BSkillInstaluj, $script:BSkillAktualizuj, $script:BSkillUsun, $script:BSkillCofnij)) { $b.Visible = -not $s.spoza }
  if ($s.spoza) { $script:SkillePrzyciski.Visible = $wlasny; return }
  $usun = ($s.stan -eq "usuniety")
  $inst = (($s.stan -eq "brak") -or (@($s.brakujeW).Count -gt 0)) -and -not $usun
  $akt = ($s.stan -eq "starszy") -or ($s.stan -eq "zmieniony")
  $cof = ($null -ne $s.zmiana) -and (@("aktualizacja", "nadpisanie", "usuniecie") -contains "$($s.zmiana.rodzaj)")
  $script:BSkillInstaluj.Enabled = $inst -and -not $pracuje
  # Zainstalowany u jednego narzedzia, brak u drugiego - przycisk mowi wprost, gdzie doda.
  $script:BSkillInstaluj.Text = $(if (($s.stan -ne "brak") -and (@($s.brakujeW).Count -gt 0)) { "Dodaj dla: " + (@($s.brakujeW) -join ", ") } else { "Zainstaluj" })
  $script:BSkillAktualizuj.Visible = -not $usun
  $script:BSkillAktualizuj.Enabled = $akt -and -not $pracuje
  $script:BSkillUsun.Visible = $usun
  $script:BSkillUsun.Enabled = $usun -and [bool]$s.zainstalowany -and -not $pracuje
  $script:BSkillCofnij.Text = $(if ($cof -and "$($s.zmiana.rodzaj)" -eq "usuniecie") { "Przywróć usunięty" } else { "Cofnij ostatnią aktualizację" })
  $script:BSkillCofnij.Enabled = $cof -and -not $pracuje
}

# Podglad: co sie zmienilo przy ostatniej aktualizacji (pliki, opisy zmian od autora),
# a dla zmienionego recznie - czym rozni sie od najblizszej wersji autora.
function Podglad-Skilla($s) {
  $l = New-Object System.Collections.Generic.List[string]
  if ($s.spoza) {
    switch ("$($s.rodzaj)") {
      "wlasny" {
        $l.Add("Ten skill powstał u Ciebie - nie ma go w żadnym zewnętrznym źródle, więc MegaRuchacz go nie aktualizuje i nie zmienia.")
        $l.Add("")
        $l.Add("Przekazanie innej osobie:")
        $l.Add("- `„Spakuj do przekazania`” robi plik ZIP z tym skillem i instrukcją po polsku (JAK-ZAINSTALOWAC.txt). `„Spakuj wszystkie własne`” - jeden ZIP ze wszystkimi Twoimi skillami.")
        $l.Add("- Paczka trafia na Pulpit (gdy go nie ma - do Pobranych). Ścieżkę zobaczysz tutaj po zakończeniu.")
        $l.Add("- Przed spakowaniem sprawdzam, czy w skillu nie ma haseł, kluczy, tokenów, adresów IP, loginów ani maili. Jeśli są - NIE pakuję i pokazuję plik i linię, które trzeba poprawić.")
      }
      "inne" {
        $l.Add("Wiadomo, skąd jest ten skill, ale aktualizuje go inne narzędzie - MegaRuchacz go nie sprawdza i nie rusza, żeby nie wejść mu w drogę.")
      }
      default {
        $l.Add("Nie wiem, skąd jest ten skill: nie pasuje do żadnego źródła z bazy, a w Twoich rozmowach nie ma śladu, że tam powstał.")
        $l.Add("MegaRuchacz go nie sprawdza i nie rusza. Jeśli znasz jego źródło, dopisz je do bazy (skille\katalog.psd1) - wtedy będzie się aktualizował sam.")
      }
    }
    return ($l -join "`r`n")
  }
  foreach ($c in @($s.cele)) {
    if ($c.najblizszy) { $l.Add("$($c.nazwa): czym Twoja wersja różni się od autora - $($c.najblizszy)"); $l.Add("") }
  }
  $zm = $s.zmiana
  if ($zm -and ($zm.rodzaj -eq "usuniecie")) {
    $l.Add("Usunięty u Ciebie na Twoje życzenie: $($zm.kiedy) (autor wcześniej usunął go ze swojego źródła).")
    $l.Add("Kopia zapasowa: $($zm.kopia)")
    $l.Add("`„Przywróć usunięty`” wgra go z tej kopii co do bajtu.")
    return ($l -join "`r`n")
  }
  if ($s.stan -eq "usuniety") {
    $l.Add("Autor usunął ten skill ze swojego źródła (nie ma go już pod $($s.usuniety.sciezka) ani nigdzie indziej w jego repozytorium).")
    $l.Add("")
    if ($s.zainstalowany) {
      $l.Add("Twoja kopia zostaje nietknięta i działa dalej - MegaRuchacz jej nie skasuje sam. Nie dostanie już tylko nowych wersji.")
      $l.Add("Jeśli go nie potrzebujesz: `„Usuń u mnie`” skasuje go z Twojego komputera, a wcześniej zrobi kopię zapasową.")
    } else {
      $l.Add("Nie masz go zainstalowanego, a zainstalować go się już nie da.")
    }
    return ($l -join "`r`n")
  }
  if ((-not $zm) -and ($s.stan -eq "brak")) {
    $gdzie = (@($script:DaneSkilli.Dane.cele | Where-Object { $_.jest }) | ForEach-Object { "$($_.nazwa)" }) -join " i "
    $l.Add("Nie masz go jeszcze. `„Zainstaluj`” wgra najnowszą wersję od autora dla: $gdzie. $(if (Czy-Inny $s) { 'To źródło nie jest częścią MegaRuchacza - nowsze wersje pobierzesz ręcznie.' } else { 'Od tej chwili będzie się sam aktualizował raz dziennie.' })")
  } elseif ((-not $zm) -and ($s.stan -eq "zmieniony")) {
    $l.Add("Nie aktualizuję go sam, bo Twoja wersja różni się od każdej wersji autora - aktualizacja skasowałaby Twoje zmiany.")
  } elseif (-not $zm) {
    $l.Add("Od kiedy jest pod opieką MegaRuchacza, ten skill nie był jeszcze aktualizowany.")
  } elseif ($zm.rodzaj -eq "cofniecie") {
    $l.Add("Ostatnio: cofnięcie aktualizacji, $($zm.kiedy).")
    $l.Add("Przywrócona kopia: $($zm.kopia)")
    if ($zm.poprzednia) { $l.Add("Wersja sprzed cofnięcia leży w: $($zm.poprzednia)") }
  } else {
    $l.Add("Ostatnia aktualizacja: $($zm.kiedy)$(if ($zm.rodzaj -eq 'nadpisanie') { ' (nadpisanie wersji zmienionej ręcznie, za Twoją zgodą)' }).")
    $l.Add("Wersja: $(Wersja-Krotko $zm.z $zm.zData)  ->  $(Wersja-Krotko $zm.na $zm.naData)")
    $l.Add("Pliki: nowe $(@($zm.dodane).Count), zmienione $(@($zm.zmienione).Count), usunięte $(@($zm.usuniete).Count).")
    foreach ($p in @($zm.dodane)) { $l.Add("  + $p") }
    foreach ($p in @($zm.zmienione)) { $l.Add("  ~ $p") }
    foreach ($p in @($zm.usuniete)) { $l.Add("  - $p") }
    if (@($zm.opisy).Count -gt 0) {
      $l.Add("")
      $l.Add("Opisy zmian od autora (po angielsku, najnowsze na górze):")
      foreach ($o in @($zm.opisy)) { $l.Add("  $o") }
    }
    $l.Add("")
    $l.Add("Kopia poprzedniej wersji: $($zm.kopia)")
  }
  return ($l -join "`r`n")
}

function Wybierz-Skill([string]$nazwa) {
  $para = Znajdz-Skill $nazwa
  if (-not $para) { return }
  foreach ($k in @($script:WierszeSkilli.Keys)) {
    $w = $script:WierszeSkilli[$k]
    if ($w -and -not $w.IsDisposed) {
      $w.BackColor = $(if ($k -eq $nazwa) { $script:TloPrzel } else { $script:TloKarty })
    }
  }
  $script:SkillWybrany = $nazwa
  $wiersz = $script:WierszeSkilli[$nazwa]
  # wiersz zwinietej grupy zostaje (ukryty, P50) - przewijamy tylko do wiersza rozwinietej
  if ($wiersz -and -not $wiersz.IsDisposed -and $script:GrupySkilli[$script:GrupaWiersza[$nazwa]]) { $script:ListaSkilli.ScrollControlIntoView($wiersz) }
  Pokaz-Info-Skilla $para
  $script:SkillePodglad.Text = Podglad-Skilla $para[0]
  $script:SkillePodglad.SelectionStart = 0
  $script:SkillePodglad.ScrollToCaret()
}

# Klikniecie przycisku: start w tle, zegar co 2 s. Koniec rozpoznajemy po operacja.txt
# z poczatkiem nie wczesniejszym niz klikniecie i wynikiem innym niz "pracuje".
# $zrodlo - operacja na calym zrodle (-ZeZrodla, przycisk w naglowku grupy).
function Rusz-Operacje-Skilli([string]$tryb, [string]$skill, [bool]$wymus, [string]$opis, [string]$zrodlo = "") {
  $powod = $(if ($zrodlo) { Operacja-Na-Zrodle $tryb $zrodlo } else { Operacja-Na-Skillach $tryb $skill $wymus })
  if ($powod) {
    $script:SkillePodglad.Text = "NIE UDAŁO SIĘ URUCHOMIĆ: $powod"
    return
  }
  $script:SkilleOperacjaOd = [datetime]::Now.AddSeconds(-1)
  $script:SkilleOperacjaOpis = $opis
  $script:SkillePodglad.Text = "$opis`r`n`r`nPracuję w tle - to potrwa od kilku sekund do kilku minut (pierwsze pobranie źródeł jest najdłuższe). Okno odświeży się samo."
  # paczka podaje folder (albo "*"), nie nazwe wiersza - przyciski ustawia wybrany wiersz
  $para = $null
  if ($skill) { $para = Znajdz-Skill $skill }
  if (-not $para -and $script:SkillWybrany) { $para = Znajdz-Skill $script:SkillWybrany }
  Ustaw-Przyciski-Skilla $(if ($para) { $para[0] } else { $null })
  if (-not $script:ZegarSkilli) {
    $script:ZegarSkilli = New-Object System.Windows.Forms.Timer
    $script:ZegarSkilli.Interval = 2000
    $script:ZegarSkilli.Add_Tick({
      try { Sprawdz-Operacje-Skilli }
      catch { $script:ZegarSkilli.Stop(); $script:SkilleOperacjaOd = $null; Zanotuj-Wywrotke "zegar operacji na skillach" $_ }
    })
  }
  $script:ZegarSkilli.Start()
}

function Sprawdz-Operacje-Skilli {
  if (-not $script:SkilleOperacjaOd) { $script:ZegarSkilli.Stop(); return }
  $op = Operacja-Skilli
  $start = Data-Lub-Nic $op["start"]
  $minelo = ([datetime]::Now - $script:SkilleOperacjaOd).TotalSeconds
  $koniec = $false; $tekst = ""
  if ($start -and ($start -ge $script:SkilleOperacjaOd) -and ($op["wynik"] -ne "pracuje")) {
    $koniec = $true
    $log = @()
    try { $log = [System.IO.File]::ReadAllLines((Join-Path (Katalog-Stanu-Skilli) "operacja.log"), [System.Text.Encoding]::UTF8) }
    catch { $log = @("(nie udało się odczytać wydruku operacji: $($_.Exception.Message))") }
    $tekst = "$($script:SkilleOperacjaOpis) - $(if ($op['wynik'] -eq 'ok') { 'GOTOWE' } else { 'SKOŃCZONE Z BŁĘDEM' }) ($($op['koniec']))`r`n`r`n" + ($log -join "`r`n")
  } elseif (($op["wynik"] -eq "pracuje") -and $start -and ($start -lt $script:SkilleOperacjaOd) -and ($minelo -gt 10)) {
    $koniec = $true
    $tekst = "Nie ruszyłem, bo właśnie trwa inna operacja na skillach ($($op['tryb']) od $($op['start'])). Spróbuj za chwilę."
  } elseif ($minelo -gt 900) {
    $koniec = $true
    $tekst = "Po 15 minutach operacja wciąż nie zapisała wyniku. Sprawdź dziennik: $(Join-Path (Katalog-Stanu-Skilli) 'dziennik.log')"
    Zanotuj-Wywrotke "operacja na skillach" "brak wyniku po 15 min ($($script:SkilleOperacjaOpis))"
  }
  if (-not $koniec) { return }
  $script:ZegarSkilli.Stop()
  $script:SkilleOperacjaOd = $null
  if ($script:WidokSkille -and -not $script:WidokSkille.IsDisposed) {
    $script:SkillePodglad.Text = $tekst
    $script:SkillePodglad.SelectionStart = 0
    $script:SkillePodglad.ScrollToCaret()
    # Lista po operacji liczy sie w tle (P21); wynik operacji wraca na prawa
    # strone po przebudowie listy (Wyrenderuj-Widok).
    $script:SkillePoOperacji = $tekst
    [void](Rusz-Krok "skille")
  }
}

# Znacznik dla nadzorca.ps1: ten plik wczytal sie do konca.
$script:ModulyOkna["skille"] = $true
