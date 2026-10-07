# zasobnik\nadzorca\okno.ps1 - czesc zasobnik\nadzorca.ps1 (patrz BUDOWA
# w jego naglowku). Budowa okna: Pokaz-Okno sklada formularz (naglowek
# z przelacznikiem, panele czterech zakladek, ekran ladowania, przyciski z pytaniem
# o zgode, zdarzenia) i pokazuje go; Pokaz-Widok przelacza zakladki. Od P59d takze
# zakladki i pasek wedlug rejestru instalacji (Uloz-Przelacznik, Uloz-Pasek,
# Ustaw-Instalacje-Okna) i przycisk "Zmień instalację" (Zmien-Instalacje,
# Po-Instalatorze, Instalator-Otwarty). Od 2026-10-07 postep aktualizacji MegaRuchacza
# z pliku stanu (Rusz-Zegar-Aktualizacji, Sprawdz-Aktualizacje, Kliknij-Aktualizuj).
# Skad wolane: menu i klikniecie ikony w nadzorca.ps1 (Pokaz-Okno), przelacznik
# zakladek (Pokaz-Widok), dozor.ps1 i w-tle.ps1 (Ustaw-Instalacje-Okna po danych),
# przeglad.ps1 (Uloz-Pasek, Instalator-Otwarty). Wczytuje go nadzorca.ps1 kropka po
# zamku jednej kopii, jako OSTATNI modul okna - tu sa same definicje.

# Przelaczenie widoku. Szczegoly napelniaja sie przy wejsciu - chyba ze stoi
# w nich odpowiedz na klikniecie (SzczegolyZajete), ktorej nie wolno podmienic.
# Od P21 dane kazdej zakladki licza sie w tle (Wejdz-Do-Widoku): brak danych z dzis
# = ekran ladowania, dane nieswieze = widok od razu i ciche odswiezenie. Nieudana
# proba liczy sie od nowa przy nastepnym wejsciu, zamiast zostawiac stary blad.
function Pokaz-Widok([string]$nazwa) {
  if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
  # bez modulu Skille nie ma tej zakladki (P59d) - wejscie do niej konczy sie na Przegladzie
  if (($nazwa -eq "skille") -and -not (Modul-Jest $script:Instalacja "skille")) { $nazwa = "przeglad" }
  $script:Widok = $nazwa
  $szcz = ($nazwa -eq "szczegoly")
  $warst = ($nazwa -eq "warstwy")
  $skil = ($nazwa -eq "skille")
  $przeg = (-not ($szcz -or $warst -or $skil))
  $script:WidokSzczegoly.Visible = $szcz
  $script:WidokWarstwy.Visible = $warst
  $script:WidokSkille.Visible = $skil
  $script:WidokPrzeglad.Visible = $przeg
  Styl-Przelacznika $script:BPrzeglad $przeg
  Styl-Przelacznika $script:BSzczegoly $szcz
  Styl-Przelacznika $script:BWarstwy $warst
  Styl-Przelacznika $script:BSkille $skil
  Wejdz-Do-Widoku $nazwa
}

# --- instalacja: zakladki wedlug rejestru i przycisk "Zmień instalację" (P59d) -------
# Ktore zakladki i karty sa w oknie, mowi rejestr instalacji ($script:Instalacja,
# Stan-Instalacji w stan-instalacja.ps1). Odczyt jest tani (jeden maly plik), wiec okno
# czyta go samo przy budowie, a potem bierze swiezy z kazdym krokiem "dane" (i z dozoru)
# - po zmianie instalacji okno ustawia sie samo, bez restartu nadzorcy.

# Przelacznik zakladek: bez modulu Skille panel jest wezszy o jej przycisk i dalej
# przylega do prawej krawedzi - zadnej pustej dziury po zakladce, ktorej nie ma.
function Uloz-Przelacznik {
  $p = $script:Przelacznik
  if (-not $p -or $p.IsDisposed) { return }
  $skil = Modul-Jest $script:Instalacja "skille"
  $szer = $(if ($skil) { 530 } else { 426 })
  $script:BSkille.Visible = $skil
  $p.Size = New-Object System.Drawing.Size($szer, 38)
  $p.Location = New-Object System.Drawing.Point(($script:SzerOkna - $script:Margines - $szer), 10)
}

# Pasek przyciskow: cztery kolumny (aktualizacja, czytanie rozmow, zmiana instalacji,
# zamkniecie). Bez modulu Wiedza kolumna czytania rozmow ma 0% i jest niewidoczna -
# reszta rozsuwa sie na cala szerokosc. Szerokosc opisow pod przyciskami idzie za
# kolumna, inaczej opis wyjechalby poza swoja kolumne albo zawijal sie bez potrzeby.
# Procenty: przy 1240 px okna kolumny maja 403/403/189/189 px - opisy mieszcza sie
# w dwoch liniach (zmierzone TextRenderer), czyli pasek nie jest wyzszy niz dotad.
function Uloz-Pasek([bool]$zCyklem) {
  $p = $script:Pasek
  if (-not $p -or $p.IsDisposed -or ($p.ColumnStyles.Count -lt 4)) { return }
  $proc = $(if ($zCyklem) { @(34, 34, 16, 16) } else { @(50, 0, 25, 25) })
  # (po procentach, nie po Visible - Visible przycisku w niepokazanym jeszcze oknie to $false)
  if (($p.ColumnStyles[0].Width -eq $proc[0]) -and ($p.ColumnStyles[1].Width -eq $proc[1])) { return }
  $p.SuspendLayout()
  try {
    $wnetrze = $script:SzerOkna - 2 * $script:Margines
    $opisy = @($script:LAktualizuj, $script:LCykl, $script:LInstalacja, $script:LZamknij)
    for ($i = 0; $i -lt 4; $i++) {
      $p.ColumnStyles[$i].Width = $proc[$i]
      if ($opisy[$i] -and ($proc[$i] -gt 0)) { $opisy[$i].MaximumSize = New-Object System.Drawing.Size(([int]($wnetrze * $proc[$i] / 100) - 24), 0) }
    }
    $script:BCykl.Visible = $zCyklem
    $script:LCykl.Visible = $zCyklem
  } finally { $p.ResumeLayout($true) }
}

function Instalator-Otwarty {
  $pr = $script:ProcesInstalatora
  if (-not $pr) { return $false }
  try { return (-not $pr.HasExited) } catch { return $false }
}

# Nowy odczyt rejestru (z kroku "dane", z dozoru albo po zamknieciu instalatora).
# Starszy niz ten, ktory okno juz ma (dozor policzony przed zmiana), nie wygrywa.
# Gdy zestaw modulow sie zmienil: przelacznik, pasek i wszystkie zakladki od nowa.
function Ustaw-Instalacje-Okna($inst) {
  if (-not $inst) { return }
  $stara = $script:Instalacja
  if ($stara -and $stara.Czas -and $inst.Czas -and ($inst.Czas -lt $stara.Czas)) { return }
  $script:Instalacja = $inst
  if ($stara -and (Moduly-Rowne $stara $inst)) { return }
  Notuj "okno: zainstalowane moduly - $((Nazwy-Modulow $inst $true) -join ', ')$(if ($inst.Blad) { ' (rejestr nieczytelny: ' + $inst.Blad + ')' })"
  foreach ($w in @($script:DoOdmalowania.Keys)) { $script:DoOdmalowania[$w] = $true }
  if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
  Uloz-Przelacznik
  if (($script:Widok -eq "skille") -and -not (Modul-Jest $inst "skille")) { Pokaz-Widok "przeglad" }
}

# "Zmień instalację": instalator w trybie zmiany - instalator\okno.ps1 -Tryb zmiana (to
# samo, co instaluj.bat w tym trybie, bez okna konsoli po drodze). Osobny proces bez
# konsoli (CreateNoWindow, bez -WindowStyle Hidden: ukryte okno startowe przeszloby na
# pierwsze okno instalatora - patrz Wymus-Pokazanie w wyglad.ps1). Nic nie kosztuje,
# wiec bez pytania; drugi instalator naraz nie rusza. Tryb probny niczego nie uruchamia.
function Zmien-Instalacje {
  $plik = Join-Path $script:NadzZrodlo "instalator\okno.ps1"
  if (-not (Test-Path -LiteralPath $plik -PathType Leaf)) {
    $script:NapisInstalacji = "Nieaktywny - instalator w przygotowaniu."
    Odmaluj-Przyciski
    return
  }
  if (Instalator-Otwarty) { Odmaluj-Przyciski; return }
  if ($script:NadzProba) {
    $script:NapisInstalacji = "Tryb próbny - instalatora nie uruchamiam."
    Odmaluj-Przyciski
    return
  }
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    # -Zrodlo i -KatalogDomowy jak u nadzorcy: instalator zmienia te instalacje, ktora to okno
    # pokazuje (w tescie z podstawionym domem - podstawiony dom, nie prawdziwy)
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $plik + '" -Tryb zmiana -Zrodlo "' + $script:NadzZrodlo + '" -KatalogDomowy "' + $script:NadzDom + '"'
    $psi.WorkingDirectory = $script:NadzZrodlo
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $script:ProcesInstalatora = [System.Diagnostics.Process]::Start($psi)
    $script:NapisInstalacji = ""
    Notuj "okno: uruchomiony instalator w trybie zmiany (pid $($script:ProcesInstalatora.Id))"
  } catch {
    Zanotuj-Wywrotke "uruchomienie instalatora" $_
    $script:ProcesInstalatora = $null
    $script:NapisInstalacji = "Nie udało się uruchomić instalatora: $($_.Exception.Message)"
  }
  Odmaluj-Przyciski
  if (-not $script:ProcesInstalatora) { return }
  if (-not $script:ZegarInstalatora) {
    $script:ZegarInstalatora = New-Object System.Windows.Forms.Timer
    $script:ZegarInstalatora.Interval = 2000
    $script:ZegarInstalatora.Add_Tick({ try { Po-Instalatorze } catch { $script:ZegarInstalatora.Stop(); Zanotuj-Wywrotke "zegar instalatora" $_ } })
  }
  $script:ZegarInstalatora.Start()
}

# Co 2 s, dopoki instalator jest otwarty. Po zamknieciu: rejestr od nowa (zakladki od
# razu), potem liczby w tle - zmienione moduly zmieniaja tez to, co sie liczy.
function Po-Instalatorze {
  if (Instalator-Otwarty) { return }
  $script:ZegarInstalatora.Stop()
  $kod = $null
  try { $kod = $script:ProcesInstalatora.ExitCode } catch { $kod = $null }
  Notuj "okno: instalator zamkniety (kod $kod) - czytam rejestr instalacji od nowa"
  try { $script:ProcesInstalatora.Dispose() } catch { Notuj "nie dalo sie zwolnic procesu instalatora: $($_.Exception.Message)" }
  $script:ProcesInstalatora = $null
  # kod inny niz 0 (3 = okno instalatora nie wstalo) - pod przyciskiem, nie tylko w dzienniku
  if (($null -ne $kod) -and ($kod -ne 0)) { $script:NapisInstalacji = "Instalator zakończył się błędem (kod $kod) - powód podaje on sam w swoim okienku i dzienniku." }
  try { Ustaw-Instalacje-Okna (Stan-Instalacji) } catch { Zanotuj-Wywrotke "rejestr instalacji po instalatorze" $_ }
  if ($script:Okno -and -not $script:Okno.IsDisposed) {
    Odmaluj-Przyciski
    [void](Przelicz-W-Tle)
  }
}

# --- aktualizacja MegaRuchacza (2026-10-07) ------------------------------------
# Aktualizacja chodzi sama w tle (przy starcie nadzorcy i co 60 min) albo po kliknieciu
# przycisku - zawsze w osobnym procesie, ktory zapisuje postep w ~\.claude\mr\aktualizacja.json.
# Okno co 1,5 s zaglada do tego pliku (wzorzec Rusz-Operacje-Skilli: zegar, plik, zero
# czekania), czyta go tylko po zmianie, a karty odmalowuje tylko wtedy, gdy zmienilo sie to,
# co widac. Tresc - Ocena-Aktualizacji (stan-wersja.ps1), wyglad - Wiersz-Aktualizacji.
function Rusz-Zegar-Aktualizacji {
  if (-not $script:ZegarAktualizacji) {
    $script:ZegarAktualizacji = New-Object System.Windows.Forms.Timer
    $script:ZegarAktualizacji.Interval = 1500
    $script:ZegarAktualizacji.Add_Tick({
      try { Sprawdz-Aktualizacje }
      catch { $script:ZegarAktualizacji.Stop(); Zanotuj-Wywrotke "zegar aktualizacji" $_ }
    })
  }
  $script:ZegarAktualizacji.Start()
}

function Sprawdz-Aktualizacje([bool]$wymus = $false) {
  $fi = New-Object System.IO.FileInfo((Plik-Aktualizacji))
  $sygn = "brak"
  if ($fi.Exists) { $sygn = "$($fi.LastWriteTimeUtc.Ticks)/$($fi.Length)" }
  if ($wymus -or ($sygn -ne $script:AktualizacjaSygnatura)) {
    $a = Stan-Aktualizacji
    if ($a.Blad -and $script:Aktualizacja -and -not $script:Aktualizacja.Blad) {
      # Plik moze byc wlasnie w trakcie zapisu - stary odczyt zostaje jeszcze 10 s
      # (sygnatury nie zapamietujemy, wiec nastepny tyk czyta od nowa); dluzej = naprawde zepsuty.
      if (-not $script:AktualizacjaBladOd) { $script:AktualizacjaBladOd = [datetime]::Now }
      if (([datetime]::Now - $script:AktualizacjaBladOd).TotalSeconds -ge 10) { $script:Aktualizacja = $a; $script:AktualizacjaSygnatura = $sygn }
    } else {
      $script:AktualizacjaBladOd = $null
      $script:Aktualizacja = $a
      $script:AktualizacjaSygnatura = $sygn
    }
  }
  $a = $script:Aktualizacja
  # Klikniecie obsluzone, gdy plik zaczal nowy przebieg (start nie wczesniej niz klikniecie).
  if ($script:AktualizacjaKlik -and $a -and $a.Start -and ($a.Start -ge $script:AktualizacjaKlik.AddSeconds(-2))) {
    $script:AktualizacjaKlik = $null; $script:AktualizacjaKlikPowod = ""
  }
  $lok = $(if ($script:Dane -and $script:Dane.Wersja) { "$($script:Dane.Wersja.Lokalna)" } else { "" })
  $oa = Ocena-Aktualizacji-Teraz $lok
  $widok = "$($oa.Trwa)|$($oa.Naglowek)|$($oa.Znak)|$($oa.Linia)|$($oa.Waga)|$($oa.Dopisek)|$($oa.ZPliku)|" +
    "$((@($oa.Kroki) | ForEach-Object { $_.Stan }) -join ',')|$(if ($oa.Problem) { $oa.Problem.Tytul })|$($oa.Przycisk)"
  if ((-not $wymus) -and ($widok -eq $script:AktualizacjaWidok)) { return }
  $script:AktualizacjaWidok = $widok
  if ($script:AktualizacjaTrwala -and -not $oa.Trwa) {
    Notuj "okno: aktualizacja skonczona - $($oa.Linia)"
    # Po nowej wersji bez restartu (np. restart sie nie udal) liczby licza sie od nowa w tle;
    # rozbicie i warstwy moga byc juz z innego kodu - przy wejsciu w zakladke od nowa.
    if ($a -and ($a.Wynik -eq "zaktualizowano")) {
      if ($script:StanKawalkow["rozbicie"]) { $script:StanKawalkow["rozbicie"].Czas = $null }
      if ($script:StanKawalkow["warstwy"]) { $script:StanKawalkow["warstwy"].Czas = $null }
      if ($script:Okno -and -not $script:Okno.IsDisposed) { [void](Przelicz-W-Tle) }
    }
  }
  $script:AktualizacjaTrwala = $oa.Trwa
  if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
  # Bez danych Przeglad stoi pod ekranem ladowania - karty i tak zlozy pierwsze odmalowanie
  # (Odmaluj-Okno), a tu tylko przycisk. Z danymi: sprawy, karta Stan i przyciski, z tym
  # samym przewinieciem co przed odmalowaniem (jak w Odmaluj-Okno).
  if (-not $script:Dane) { Odmaluj-Przyciski; return }
  $przewiniecie = 0
  try { if ($script:WidokPrzeglad) { $przewiniecie = -$script:WidokPrzeglad.AutoScrollPosition.Y } }
  catch { Zanotuj-Wywrotke "odczyt przewiniecia przegladu (aktualizacja)" $_ }
  $script:Okno.SuspendLayout()
  try {
    Odmaluj-Problemy
    Odmaluj-Stan
    Odmaluj-Przyciski
  } finally { $script:Okno.ResumeLayout($true) }
  if ($przewiniecie -gt 0) {
    try { $script:WidokPrzeglad.AutoScrollPosition = New-Object System.Drawing.Point(0, $przewiniecie) }
    catch { Zanotuj-Wywrotke "przywrocenie przewiniecia przegladu (aktualizacja)" $_ }
  }
}

# Klikniecie: skrypt w tle (Aktualizuj w stan-wersja.ps1), od razu pasek na "Sprawdzam"
# i widok Przegladu z karta Stan - tam stoi postep. Gdy skrypt nie ruszyl, karta mowi
# dlaczego (Ocena-Aktualizacji), a nie kreci paskiem w nieskonczonosc.
function Kliknij-Aktualizuj {
  $r = Aktualizuj
  if ($r.Proba) {
    $script:NapisAktualizacji = "Tryb próbny - aktualizacji nie uruchamiam."
    Odmaluj-Przyciski
    return
  }
  $script:NapisAktualizacji = ""
  $script:AktualizacjaKlik = [datetime]::Now
  $script:AktualizacjaKlikPowod = $(if ($r.Ok) { "" } else { $r.Powod })
  if ($script:Widok -ne "przeglad") { $script:SzczegolyZajete = $false; Pokaz-Widok "przeglad" }
  Sprawdz-Aktualizacje $true
  Rusz-Zegar-Aktualizacji
  try {
    if ($script:PanelStan -and -not $script:PanelStan.IsDisposed -and $script:WidokPrzeglad) { $script:WidokPrzeglad.ScrollControlIntoView($script:PanelStan) }
  } catch { Zanotuj-Wywrotke "przewiniecie do karty Stan po kliknieciu aktualizacji" $_ }
}

# --- budowa okna -------------------------------------------------------------

function Pokaz-Okno {
  if ($script:Okno -and -not $script:Okno.IsDisposed) {
    $script:Okno.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $script:Okno.Show()
    Wymus-Pokazanie $script:Okno
    Wejdz-Do-Widoku $script:Widok
    Rusz-Zegar-Aktualizacji
    return
  }

  # P59d: rejestr instalacji przed budowa - od niego zalezy przelacznik i pasek.
  try { Ustaw-Instalacje-Okna (Stan-Instalacji) } catch { Zanotuj-Wywrotke "odczyt rejestru instalacji przy budowie okna" $_ }

  $f = New-Object System.Windows.Forms.Form
  $f.Text = "MegaRuchacz"
  $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
  $f.MaximizeBox = $false
  # STALY ROZMIAR OD PIERWSZEJ CHWILI (P21): wysokosc z ekranu, raz - okno nie
  # rosnie ani nie skacze w miare dochodzenia danych. Polozenie: tam, gdzie
  # uzytkownik zostawil okno ostatnio (gdy nadal miesci sie na ktoryms ekranie),
  # inaczej srodek ekranu pod kursorem.
  $obszar = Obszar-Okna
  $f.ClientSize = New-Object System.Drawing.Size($script:SzerOkna, 720)
  $f.Height = [int][math]::Min($WYS_OKNA_MAX, $obszar.Height - 40)
  $f.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
  $poz = New-Object System.Drawing.Point(($obszar.Left + [int](($obszar.Width - $f.Width) / 2)), ($obszar.Top + [int](($obszar.Height - $f.Height) / 2)))
  if ($script:PolozenieOkna) {
    $prost = New-Object System.Drawing.Rectangle($script:PolozenieOkna, $f.Size)
    foreach ($ekran in [System.Windows.Forms.Screen]::AllScreens) {
      if ($ekran.WorkingArea.Contains($prost)) { $poz = $script:PolozenieOkna; break }
    }
  }
  $f.Location = $poz
  $f.BackColor = $script:TloOkna
  $f.Font = $script:CzZwykla
  try { $f.Icon = Ikona-Nadzorcy } catch { Zanotuj-Wywrotke "ikona okna" $_ }

  # Pasek przyciskow siedzi na formularzu, a nie w przewijanej tresci - ma byc
  # pod reka zawsze, w obu widokach.
  $script:Pasek = New-Object System.Windows.Forms.TableLayoutPanel
  $script:Pasek.Dock = [System.Windows.Forms.DockStyle]::Bottom
  $script:Pasek.AutoSize = $true
  $script:Pasek.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
  # P59d: czwarta kolumna "Zmień instalację"; procenty i szerokosci opisow ustawia
  # Uloz-Pasek (wyzej) - takze bez modulu Wiedza, gdy kolumna czytania rozmow znika.
  $script:Pasek.ColumnCount = 4
  $script:Pasek.RowCount = 2
  $script:Pasek.Padding = New-Object System.Windows.Forms.Padding($script:Margines, 14, $script:Margines, 14)
  $script:Pasek.BackColor = $script:TloPaska
  foreach ($proc in @(34, 34, 16, 16)) {
    $script:Pasek.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, $proc))) | Out-Null
  }
  $script:Pasek.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 38))) | Out-Null
  $script:Pasek.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null
  # cienka kreska nad paskiem - oddziela przyciski od tresci bez ciezkiej ramki
  $script:Pasek.Add_Paint({ param($nadawca, $e) try { $e.Graphics.DrawLine($script:PioroRamki, 0, 0, $nadawca.Width, 0) } catch { if (-not $script:RamkaZawiodla) { $script:RamkaZawiodla = $true; Zanotuj-Wywrotke "rysowanie kreski nad przyciskami" $_ } } })

  $script:BAktualizuj = Nowy-Przycisk "Sprawdź i pobierz nowszą wersję MegaRuchacza"
  $script:BCykl       = Nowy-Przycisk "Przeczytaj teraz nowe rozmowy"
  $script:BInstalacja = Nowy-Przycisk "Zmień instalację"
  $bZamknij           = Nowy-Przycisk "Zamknij okno"
  $wnetrzePaska = $script:SzerOkna - 2 * $script:Margines
  $script:LAktualizuj = Etykieta-Zawijana "" $script:CzMala $script:KolSzary ([int]($wnetrzePaska * 0.34) - 24)
  $script:LCykl       = Etykieta-Zawijana "" $script:CzMala $script:KolSzary ([int]($wnetrzePaska * 0.34) - 24)
  $script:LInstalacja = Etykieta-Zawijana "" $script:CzMala $script:KolSzary ([int]($wnetrzePaska * 0.16) - 24)
  $script:LZamknij    = Etykieta-Zawijana "Ikona w zasobniku zostaje i pilnuje dalej." $script:CzMala $script:KolSzary ([int]($wnetrzePaska * 0.16) - 24)
  $script:LInstalacja.UseMnemonic = $false

  $script:Pasek.Controls.Add($script:BAktualizuj, 0, 0)
  $script:Pasek.Controls.Add($script:BCykl, 1, 0)
  $script:Pasek.Controls.Add($script:BInstalacja, 2, 0)
  $script:Pasek.Controls.Add($bZamknij, 3, 0)
  $script:Pasek.Controls.Add($script:LAktualizuj, 0, 1)
  $script:Pasek.Controls.Add($script:LCykl, 1, 1)
  $script:Pasek.Controls.Add($script:LInstalacja, 2, 1)
  $script:Pasek.Controls.Add($script:LZamknij, 3, 1)

  # Naglowek: tytul i podtytul po lewej, przelacznik widokow po prawej.
  $script:Naglowek = New-Object System.Windows.Forms.Panel
  $script:Naglowek.Dock = [System.Windows.Forms.DockStyle]::Top
  $script:Naglowek.Height = 88
  $script:Naglowek.BackColor = $script:TloOkna
  $lTytul = Etykieta "MegaRuchacz" $script:CzTytul $script:KolTekst
  $lTytul.Location = New-Object System.Drawing.Point(($script:Margines - 3), 14)
  $script:LPodtytul = Etykieta-Zawijana "Przeliczam, to potrwa kilka sekund..." $script:CzZwykla $script:KolSzary ($script:SzerOkna - 2 * $script:Margines)
  $script:LPodtytul.Location = New-Object System.Drawing.Point($script:Margines, 54)
  # Przelacznik trzech widokow na linii tytulu, po prawej; podtytul biegnie pod
  # nim na cala szerokosc.
  # P18: czwarty przycisk "Skille" - panel szerszy o 104 px (100 px przycisku + 4 odstepu).
  # P59d: bez modulu Skille panel wezszy o te 104 px (Uloz-Przelacznik).
  $przel = New-Object System.Windows.Forms.Panel
  $przel.Size = New-Object System.Drawing.Size(530, 38)
  $przel.Location = New-Object System.Drawing.Point(($script:SzerOkna - $script:Margines - 530), 10)
  $przel.BackColor = $script:TloPrzel
  $script:Przelacznik = $przel
  $script:BPrzeglad  = Przycisk-Przelacznika "Przegląd" 3 124
  $script:BSzczegoly = Przycisk-Przelacznika "Szczegóły" 131 124
  $script:BWarstwy   = Przycisk-Przelacznika "Warstwy pamięci" 259 164
  $script:BSkille    = Przycisk-Przelacznika "Skille" 427 100
  $przel.Controls.Add($script:BPrzeglad)
  $przel.Controls.Add($script:BSzczegoly)
  $przel.Controls.Add($script:BWarstwy)
  $przel.Controls.Add($script:BSkille)
  Uloz-Przelacznik
  $script:Naglowek.Controls.Add($lTytul)
  $script:Naglowek.Controls.Add($script:LPodtytul)
  $script:Naglowek.Controls.Add($przel)

  # Widok przegladu: karty jedna pod druga. Przewija sie wylacznie wtedy, gdy
  # ekran jest nizszy niz tresc - wtedy nic nie znika pod krawedzia.
  $script:WidokPrzeglad = New-Object System.Windows.Forms.Panel
  $script:WidokPrzeglad.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:WidokPrzeglad.AutoScroll = $true
  $script:WidokPrzeglad.BackColor = $script:TloOkna
  $script:WidokPrzeglad.Padding = New-Object System.Windows.Forms.Padding($script:Margines, 4, $script:Margines, 8)

  $script:Root = Pionowy $script:SzerTresc
  $script:Root.Dock = [System.Windows.Forms.DockStyle]::Top

  $script:PanelProblemy = Pionowy $script:SzerTresc
  $script:PanelProblemy.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
  $script:PanelProblemy.Visible = $false

  $script:KartaWerdykt = Nowa-Karta $script:SzerKarty
  $script:KartaStart = Nowa-Karta $script:SzerKarty
  # P26: prawdziwy koszt - zaraz pod werdyktem (i ewentualnymi problemami): werdykt mowi,
  # ile doklada sam MegaRuchacz, ta karta - ile naprawde idzie.
  $script:KartaKoszt = Nowa-Karta $script:SzerKarty
  $script:KartaKoszt.Padding = New-Object System.Windows.Forms.Padding(22, 12, 22, 10)

  $script:PanelLiczby = Poziomy
  $script:PanelLiczby.Margin = New-Object System.Windows.Forms.Padding(0)

  # Wykres kosztu nauki z 30 dni stal tu pod karta nauki do P35 (30.09.2026) -
  # Przeglad przestal sie miescic bez przewijania, wiec wykres jest teraz karta
  # w Szczegolach (Sekcje-Szczegolow, Panel-Wykresu).
  $script:PanelStan = Nowa-Karta $script:SzerKarty
  $script:PanelStan.Margin = New-Object System.Windows.Forms.Padding(0)

  $script:Root.Controls.Add($script:KartaWerdykt)
  $script:Root.Controls.Add($script:PanelProblemy)
  $script:Root.Controls.Add($script:KartaKoszt)
  $script:Root.Controls.Add($script:KartaStart)
  $script:Root.Controls.Add($script:PanelLiczby)
  $script:Root.Controls.Add($script:PanelStan)
  $script:WidokPrzeglad.Controls.Add($script:Root)

  # Widok szczegolow: ten sam obszar, karty sekcji jedna pod druga, przewijane
  # w miejscu - okno nie rosnie od tego ani o piksel.
  $script:WidokSzczegoly = New-Object System.Windows.Forms.Panel
  $script:WidokSzczegoly.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:WidokSzczegoly.AutoScroll = $true
  $script:WidokSzczegoly.BackColor = $script:TloOkna
  $script:WidokSzczegoly.Padding = New-Object System.Windows.Forms.Padding($script:Margines, 4, $script:Margines, 12)
  $script:WidokSzczegoly.Visible = $false
  $script:ListaSzczegolow = Pionowy $script:SzerTresc
  $script:ListaSzczegolow.Dock = [System.Windows.Forms.DockStyle]::Top
  $script:WidokSzczegoly.Controls.Add($script:ListaSzczegolow)

  # Widok warstw pamieci: zdanie podsumowania u gory, pod nim dwie biale karty -
  # lista warstw pogrupowana wedlug tego, kiedy sie wczytuja, i podglad tylko
  # do odczytu. Ten sam obszar co pozostale widoki, okno nie rosnie.
  $script:WidokWarstwy = New-Object System.Windows.Forms.Panel
  $script:WidokWarstwy.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:WidokWarstwy.BackColor = $script:TloOkna
  $script:WidokWarstwy.Padding = New-Object System.Windows.Forms.Padding($script:Margines, 4, $script:Margines, 14)
  $script:WidokWarstwy.Visible = $false

  $script:LWarstwy = New-Object System.Windows.Forms.Label
  $script:LWarstwy.AutoSize = $false
  $script:LWarstwy.UseMnemonic = $false
  $script:LWarstwy.Dock = [System.Windows.Forms.DockStyle]::Top
  $script:LWarstwy.Height = 44
  $script:LWarstwy.Font = $script:CzZwyklaGruba
  $script:LWarstwy.ForeColor = $script:KolTekst
  $script:LWarstwy.BackColor = [System.Drawing.Color]::Transparent
  $script:LWarstwy.Text = "Zbieram listę warstw pamięci..."

  $cialoW = New-Object System.Windows.Forms.Panel
  $cialoW.Dock = [System.Windows.Forms.DockStyle]::Fill
  $cialoW.BackColor = $script:TloOkna

  $kartaLista = New-Object System.Windows.Forms.Panel
  $kartaLista.Dock = [System.Windows.Forms.DockStyle]::Left
  $kartaLista.Width = [int]($script:SzerTresc * 0.48)
  $kartaLista.BackColor = $script:TloKarty
  $kartaLista.Padding = New-Object System.Windows.Forms.Padding(1)
  $kartaLista.Add_Paint({ param($nadawca, $e) Obrysuj $nadawca $e })
  $script:ListaWarstw = New-Object System.Windows.Forms.ListView
  $script:ListaWarstw.View = [System.Windows.Forms.View]::Details
  $script:ListaWarstw.FullRowSelect = $true
  $script:ListaWarstw.HideSelection = $false
  $script:ListaWarstw.MultiSelect = $false
  $script:ListaWarstw.ShowGroups = $true
  $script:ListaWarstw.ShowItemToolTips = $true
  $script:ListaWarstw.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
  $script:ListaWarstw.BorderStyle = [System.Windows.Forms.BorderStyle]::None
  $script:ListaWarstw.Font = $script:CzZwykla
  $script:ListaWarstw.BackColor = $script:TloKarty
  $script:ListaWarstw.ForeColor = $script:KolTekst
  $script:ListaWarstw.Dock = [System.Windows.Forms.DockStyle]::Fill
  # Wyzsze wiersze: WinForms nie ma na to wlasciwosci, ale wysokosc wiersza
  # idzie za wysokoscia obrazka z SmallImageList - pusty obrazek 1 x 26 px
  # daje liste, ktora sie czyta, a nie mruzy oczy.
  $wierszWys = New-Object System.Windows.Forms.ImageList
  $wierszWys.ImageSize = New-Object System.Drawing.Size(1, 26)
  $script:ListaWarstw.SmallImageList = $wierszWys
  [void]$script:ListaWarstw.Columns.Add("Warstwa", ($kartaLista.Width - 100 - 116 - 26))
  [void]$script:ListaWarstw.Columns.Add("Trwałość", 100)
  [void]$script:ListaWarstw.Columns.Add("Rozmiar", 116)
  $kartaLista.Controls.Add($script:ListaWarstw)

  $odstepW = New-Object System.Windows.Forms.Panel
  $odstepW.Dock = [System.Windows.Forms.DockStyle]::Left
  $odstepW.Width = 14
  $odstepW.BackColor = $script:TloOkna

  $kartaPodglad = New-Object System.Windows.Forms.Panel
  $kartaPodglad.Dock = [System.Windows.Forms.DockStyle]::Fill
  $kartaPodglad.BackColor = $script:TloKarty
  $kartaPodglad.Padding = New-Object System.Windows.Forms.Padding(18, 14, 6, 6)
  $kartaPodglad.Add_Paint({ param($nadawca, $e) Obrysuj $nadawca $e })
  $script:PodgladWarstwy = New-Object System.Windows.Forms.TextBox
  $script:PodgladWarstwy.Multiline = $true
  $script:PodgladWarstwy.ReadOnly = $true
  # CLAUDE.md i mapa potrafia miec po kilkadziesiat tysiecy znakow - domyslny
  # sufit pola (32 767) nie ma prawa uciac konca pliku po cichu
  $script:PodgladWarstwy.MaxLength = [int]::MaxValue
  $script:PodgladWarstwy.WordWrap = $true
  $script:PodgladWarstwy.BorderStyle = [System.Windows.Forms.BorderStyle]::None
  $script:PodgladWarstwy.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
  # Consolas 9, a nie 9.5: pliki maja twarde lamanie ~80 znakow i przy 9.5 kazda
  # dluzsza linia zostawiala sierote w nastepnym wierszu
  $script:PodgladWarstwy.Font = $script:CzStalaMala
  $script:PodgladWarstwy.BackColor = $script:TloKarty
  $script:PodgladWarstwy.ForeColor = $script:KolTekst
  $script:PodgladWarstwy.Dock = [System.Windows.Forms.DockStyle]::Fill
  $kartaPodglad.Controls.Add($script:PodgladWarstwy)
  $script:PodgladInfo = Pionowy 0
  $script:PodgladInfo.Dock = [System.Windows.Forms.DockStyle]::Top
  $script:PodgladInfo.BackColor = $script:TloKarty
  $kartaPodglad.Controls.Add($script:PodgladInfo)

  # Dokowanie od ostatnio dodanej: wypelniajacy podglad pierwszy, potem odstep,
  # na koncu lista - ona dokuje sie pierwsza, czyli najbardziej z lewej.
  $cialoW.Controls.Add($kartaPodglad)
  $cialoW.Controls.Add($odstepW)
  $cialoW.Controls.Add($kartaLista)
  $script:WidokWarstwy.Controls.Add($cialoW)
  $script:WidokWarstwy.Controls.Add($script:LWarstwy)

  # Widok skilli (P18): u gory zdanie o bezpieczenstwie z podsumowaniem i przycisk
  # "Sprawdz teraz", pod nimi lista (wiersze z zawinietym opisem, pogrupowane wedlug
  # zrodla) i karta szczegolow z przyciskami. Ten sam obszar, okno nie rosnie.
  $script:WidokSkille = New-Object System.Windows.Forms.Panel
  $script:WidokSkille.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:WidokSkille.BackColor = $script:TloOkna
  $script:WidokSkille.Padding = New-Object System.Windows.Forms.Padding($script:Margines, 4, $script:Margines, 14)
  $script:WidokSkille.Visible = $false

  # Gora: po lewej zdanie o bezpieczenstwie (szare, stale) i pod nim podsumowanie
  # (kolor wedlug stanu), po prawej przycisk. Zdanie o bezpieczenstwie nie czerwienieje
  # przy bledzie - czerwone jest tylko to, co naprawde sie nie udalo.
  $goraS = New-Object System.Windows.Forms.Panel
  $goraS.Dock = [System.Windows.Forms.DockStyle]::Top
  $goraS.Height = 64
  $goraS.BackColor = $script:TloOkna
  $prawaS = New-Object System.Windows.Forms.Panel
  $prawaS.Dock = [System.Windows.Forms.DockStyle]::Right
  $prawaS.Width = 164
  $prawaS.Padding = New-Object System.Windows.Forms.Padding(14, 2, 0, 0)
  $script:BSkilleTeraz = New-Object System.Windows.Forms.Button
  $script:BSkilleTeraz.Text = "Sprawdź teraz"
  $script:BSkilleTeraz.Font = $script:CzZwykla
  $script:BSkilleTeraz.FlatStyle = [System.Windows.Forms.FlatStyle]::System
  $script:BSkilleTeraz.Height = 34
  $script:BSkilleTeraz.Dock = [System.Windows.Forms.DockStyle]::Top
  $prawaS.Controls.Add($script:BSkilleTeraz)
  $lewaS = Pionowy 0
  $lewaS.Dock = [System.Windows.Forms.DockStyle]::Fill
  $lewaS.AutoSize = $false
  $szerZdania = $script:SzerTresc - 164 - 4
  $lBezp = Etykieta-Zawijana $ZDANIE_BEZPIECZENSTWA $script:CzMala $script:KolSzary $szerZdania
  $lBezp.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
  $script:LSkille = Etykieta-Zawijana "Zbieram listę skilli..." $script:CzZwyklaGruba $script:KolTekst $szerZdania
  $script:LSkille.UseMnemonic = $false
  $lewaS.Controls.Add($lBezp)
  $lewaS.Controls.Add($script:LSkille)
  $goraS.Controls.Add($lewaS)
  $goraS.Controls.Add($prawaS)
  # Wysokosc gory idzie za tekstem - podsumowanie nie ma prawa uciac sie pod lista.
  $script:LSkille.Add_SizeChanged({ param($nadawca, $e) try { $nadawca.Parent.Parent.Height = [math]::Max(48, $nadawca.Bottom + 12) } catch { Zanotuj-Wywrotke "wysokosc podsumowania skilli" $_ } })

  $cialoS = New-Object System.Windows.Forms.Panel
  $cialoS.Dock = [System.Windows.Forms.DockStyle]::Fill
  $cialoS.BackColor = $script:TloOkna

  $kartaListaS = New-Object System.Windows.Forms.Panel
  $kartaListaS.Dock = [System.Windows.Forms.DockStyle]::Left
  $kartaListaS.Width = [int]($script:SzerTresc * 0.56)
  $kartaListaS.BackColor = $script:TloKarty
  $kartaListaS.Padding = New-Object System.Windows.Forms.Padding(1)
  $kartaListaS.Add_Paint({ param($nadawca, $e) Obrysuj $nadawca $e })
  # panel bez migania (wyglad.ps1, P50): podwojne buforowanie calej listy
  $script:ListaSkilli = New-Object MegaRuchacz.ListaBezMigania
  $script:ListaSkilli.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:ListaSkilli.AutoScroll = $true
  $script:ListaSkilli.BackColor = $script:TloKarty
  $wnetrzeS = Pionowy 0
  $wnetrzeS.Location = New-Object System.Drawing.Point(0, 0)
  $script:ListaSkilli.Controls.Add($wnetrzeS)
  $kartaListaS.Controls.Add($script:ListaSkilli)

  $odstepS = New-Object System.Windows.Forms.Panel
  $odstepS.Dock = [System.Windows.Forms.DockStyle]::Left
  $odstepS.Width = 14
  $odstepS.BackColor = $script:TloOkna

  $kartaInfoS = New-Object System.Windows.Forms.Panel
  $kartaInfoS.Dock = [System.Windows.Forms.DockStyle]::Fill
  $kartaInfoS.BackColor = $script:TloKarty
  $kartaInfoS.Padding = New-Object System.Windows.Forms.Padding(18, 14, 6, 6)
  $kartaInfoS.Add_Paint({ param($nadawca, $e) Obrysuj $nadawca $e })
  $script:SkillePodglad = New-Object System.Windows.Forms.TextBox
  $script:SkillePodglad.Multiline = $true
  $script:SkillePodglad.ReadOnly = $true
  $script:SkillePodglad.MaxLength = [int]::MaxValue
  $script:SkillePodglad.WordWrap = $true
  $script:SkillePodglad.BorderStyle = [System.Windows.Forms.BorderStyle]::None
  $script:SkillePodglad.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
  $script:SkillePodglad.Font = $script:CzMala
  $script:SkillePodglad.BackColor = $script:TloKarty
  $script:SkillePodglad.ForeColor = $script:KolTekst
  $script:SkillePodglad.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:SkillePrzyciski = Poziomy
  $script:SkillePrzyciski.Dock = [System.Windows.Forms.DockStyle]::Top
  $script:SkillePrzyciski.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 10)
  $script:BSkillInstaluj = New-Object System.Windows.Forms.Button
  $script:BSkillAktualizuj = New-Object System.Windows.Forms.Button
  $script:BSkillCofnij = New-Object System.Windows.Forms.Button
  $script:BSkillUsun = New-Object System.Windows.Forms.Button
  # P49: paczka do przekazania - tylko przy skillu "Twoj wlasny" (wtedy cztery powyzsze sa ukryte).
  $script:BSkillSpakuj = New-Object System.Windows.Forms.Button
  $script:BSkillSpakujWszystkie = New-Object System.Windows.Forms.Button
  # "Usun u mnie" stoi w miejscu "Aktualizuj teraz" (widac zawsze jeden z nich) -
  # rzad przyciskow nie robi sie szerszy niz karta.
  foreach ($para in @(@($script:BSkillInstaluj, "Zainstaluj", 140), @($script:BSkillAktualizuj, "Aktualizuj teraz", 130), @($script:BSkillUsun, "Usuń u mnie", 130), @($script:BSkillCofnij, "Cofnij ostatnią aktualizację", 200), @($script:BSkillSpakuj, "Spakuj do przekazania", 180), @($script:BSkillSpakujWszystkie, "Spakuj wszystkie własne", 190))) {
    $para[0].Text = $para[1]
    $para[0].Font = $script:CzZwykla
    $para[0].FlatStyle = [System.Windows.Forms.FlatStyle]::System
    $para[0].Size = New-Object System.Drawing.Size($para[2], 32)
    $para[0].Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    $script:SkillePrzyciski.Controls.Add($para[0])
  }
  $script:SkilleInfo = Pionowy 0
  $script:SkilleInfo.Dock = [System.Windows.Forms.DockStyle]::Top
  $script:SkilleInfo.BackColor = $script:TloKarty
  $kartaInfoS.Controls.Add($script:SkillePodglad)
  $kartaInfoS.Controls.Add($script:SkillePrzyciski)
  $kartaInfoS.Controls.Add($script:SkilleInfo)

  $cialoS.Controls.Add($kartaInfoS)
  $cialoS.Controls.Add($odstepS)
  $cialoS.Controls.Add($kartaListaS)
  $script:WidokSkille.Controls.Add($cialoS)
  $script:WidokSkille.Controls.Add($goraS)

  # Ekran ladowania (P21) - ten sam obszar co zakladki, dodany PIERWSZY, wiec lezy
  # na wierzchu wszystkich widokow i zaslania je, dopoki zakladka nie ma kompletu.
  $script:WidokLadowania = Zbuduj-Ladowanie

  # Kolejnosc dodawania ma znaczenie: WinForms dokuje od ostatnio dodanej
  # kontrolki, wiec wypelniajace widoki ida PIERWSZE, a naglowek i pasek po nich.
  $f.Controls.Add($script:WidokLadowania)
  $f.Controls.Add($script:WidokSkille)
  $f.Controls.Add($script:WidokWarstwy)
  $f.Controls.Add($script:WidokSzczegoly)
  $f.Controls.Add($script:WidokPrzeglad)
  $f.Controls.Add($script:Naglowek)
  $f.Controls.Add($script:Pasek)
  # Polozenie zapamietane do nastepnego otwarcia - okno staje tam, gdzie je zostawiono.
  $f.Add_FormClosing({
    try { if ($script:Okno.WindowState -eq [System.Windows.Forms.FormWindowState]::Normal) { $script:PolozenieOkna = $script:Okno.Location } }
    catch { Zanotuj-Wywrotke "zapamietanie polozenia okna" $_ }
  })
  $f.Add_FormClosed({
    # Dane (DaneWarstw, DaneSkilli, Rozbicie...) zostaja - to nie kontrolki. Drugie
    # otwarcie tego samego dnia pokazuje je od razu (P21); swiezosc pilnuja kawalki.
    $script:Ladowanie = $null; $script:WidokLadowania = $null; $script:ListaKrokow = $null; $script:WierszeKrokow = @{}
    $script:PasekLadowania = $null; $script:LLadowanieTytul = $null; $script:LLadowanieOpis = $null
    $script:LLadowanieStopka = $null; $script:BPokazTeraz = $null
    foreach ($w in @($script:DoOdmalowania.Keys)) { $script:DoOdmalowania[$w] = $true }
    $script:Okno = $null; $script:Root = $null; $script:Naglowek = $null
    $script:WidokPrzeglad = $null; $script:WidokSzczegoly = $null
    $script:LPodtytul = $null; $script:PanelProblemy = $null; $script:PanelLiczby = $null
    $script:PanelStan = $null
    $script:BPrzeglad = $null; $script:BSzczegoly = $null; $script:ListaSzczegolow = $null
    $script:KartaStart = $null; $script:KartaWerdykt = $null; $script:PodgladInfo = $null; $script:KartaKoszt = $null
    $script:Pasek = $null; $script:BAktualizuj = $null; $script:LAktualizuj = $null
    $script:BCykl = $null; $script:LCykl = $null
    # instalator moze dalej byc otwarty - jego proces i zegar zostaja (Po-Instalatorze
    # przeczyta rejestr takze bez okna); znika tylko odpowiedz na klikniecie
    $script:BInstalacja = $null; $script:LInstalacja = $null; $script:LZamknij = $null; $script:Przelacznik = $null
    $script:NapisInstalacji = ""
    $script:PanelZmian = $null; $script:LinkZmian = $null
    $script:BWarstwy = $null; $script:WidokWarstwy = $null; $script:LWarstwy = $null
    $script:ListaWarstw = $null; $script:PodgladWarstwy = $null
    if ($script:ZegarSkilli) { $script:ZegarSkilli.Stop() }
    # aktualizacja chodzi dalej w tle - bez okna nie ma czego odmalowywac; po otwarciu od nowa
    if ($script:ZegarAktualizacji) { $script:ZegarAktualizacji.Stop() }
    $script:AktualizacjaWidok = ""; $script:NapisAktualizacji = ""
    $script:BSkille = $null; $script:WidokSkille = $null; $script:LSkille = $null; $script:BSkilleTeraz = $null
    $script:ListaSkilli = $null; $script:SkilleInfo = $null; $script:SkillePrzyciski = $null; $script:SkillePodglad = $null
    $script:BSkillInstaluj = $null; $script:BSkillAktualizuj = $null; $script:BSkillCofnij = $null; $script:BSkillUsun = $null
    $script:BSkillSpakuj = $null; $script:BSkillSpakujWszystkie = $null
    $script:WierszeSkilli = @{}; $script:SkilleOperacjaOd = $null; $script:SkillePoOperacji = $null
    $script:GrupySkilli = @{}; $script:NaglowkiGrup = @{}; $script:ZnacznikiGrup = @{}; $script:GrupyListy = @{}; $script:GrupaWiersza = @{}
    $script:Widok = "przeglad"
    $script:SzczegolyZajete = $false
  })

  # --- co robia przyciski ---

  $script:BPrzeglad.Add_Click({
    $script:SzczegolyZajete = $false
    Pokaz-Widok "przeglad"
  })
  $script:BSzczegoly.Add_Click({
    if ($script:Widok -eq "szczegoly") { return }
    $script:SzczegolyZajete = $false
    Pokaz-Widok "szczegoly"
  })
  $script:BWarstwy.Add_Click({
    if ($script:Widok -eq "warstwy") { return }
    $script:SzczegolyZajete = $false
    Pokaz-Widok "warstwy"
  })
  $script:BSkille.Add_Click({
    if ($script:Widok -eq "skille") { return }
    $script:SzczegolyZajete = $false
    Pokaz-Widok "skille"
  })
  # Przyciski skilli nie wydaja tokenow - pytaja tylko wtedy, gdy maja nadpisac
  # skill zmieniony recznie (domyslnie podswietlone "Nie").
  $script:BSkilleTeraz.Add_Click({
    try { Rusz-Operacje-Skilli "aktualizuj" "" $false "Sprawdzam wszystkie źródła i pobieram nowsze wersje skilli pod opieką" }
    catch { Zanotuj-Wywrotke "przycisk Sprawdz teraz (skille)" $_ }
  })
  $script:BSkillInstaluj.Add_Click({
    try {
      $n = $script:SkillWybrany
      if ($n) { Rusz-Operacje-Skilli "instaluj" $n $false "Instaluję $n" }
    } catch { Zanotuj-Wywrotke "przycisk Zainstaluj (skille)" $_ }
  })
  $script:BSkillAktualizuj.Add_Click({
    try {
      $n = $script:SkillWybrany
      $para = Znajdz-Skill $n
      if (-not $para) { return }
      $wymus = $false
      if ($para[0].wyzerowany) {
        # P62: wyzerowany to nie zmiana reczna - kopii z zer skrypt nie zrobi, wiec mowimy to wprost
        $odp = [System.Windows.Forms.MessageBox]::Show($script:Okno,
          ("Skill `„$($para[0].folder)`” jest uszkodzony: jego pliki to same zera (zanik prądu)." + "`r`n`r`n" +
           "Czy wgrać w to miejsce najnowszą wersję od autora? Kopii zapasowej z zer nie robię - nie ma w nich nic do ocalenia." + "`r`n`r`n" +
           "Po kliknięciu Nie nie stanie się nic."),
          "Naprawić uszkodzony skill?", [System.Windows.Forms.MessageBoxButtons]::YesNo,
          [System.Windows.Forms.MessageBoxIcon]::Warning, [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($odp -ne [System.Windows.Forms.DialogResult]::Yes) { Notuj "skille: naprawa wyzerowanego $n - uzytkownik nie potwierdzil"; return }
        $wymus = $true
      } elseif ($para[0].stan -eq "zmieniony") {
        $odp = [System.Windows.Forms.MessageBox]::Show($script:Okno,
          ("Skill `„$($para[0].folder)`” był zmieniony ręcznie - jego treść nie pasuje do żadnej wersji autora." + "`r`n`r`n" +
           "Czy zastąpić go najnowszą wersją od autora? Twoja wersja trafi do kopii zapasowej i przycisk `„Cofnij ostatnią aktualizację`” ją przywróci." + "`r`n`r`n" +
           "Po kliknięciu Nie nie stanie się nic."),
          "Zastąpić skill zmieniony ręcznie?", [System.Windows.Forms.MessageBoxButtons]::YesNo,
          [System.Windows.Forms.MessageBoxIcon]::Question, [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($odp -ne [System.Windows.Forms.DialogResult]::Yes) { Notuj "skille: nadpisanie $n - uzytkownik nie potwierdzil"; return }
        $wymus = $true
      }
      Rusz-Operacje-Skilli "aktualizuj" $n $wymus "Aktualizuję $n"
    } catch { Zanotuj-Wywrotke "przycisk Aktualizuj teraz (skille)" $_ }
  })
  $script:BSkillCofnij.Add_Click({
    try {
      $n = $script:SkillWybrany
      if ($n) { Rusz-Operacje-Skilli "cofnij" $n $false "Cofam ostatnią zmianę $n" }
    } catch { Zanotuj-Wywrotke "przycisk Cofnij (skille)" $_ }
  })
  # Usun u mnie (P20): tylko skill usuniety przez autora, zawsze z pytaniem (domyslnie "Nie").
  $script:BSkillUsun.Add_Click({
    try {
      $n = $script:SkillWybrany
      $para = Znajdz-Skill $n
      if (-not $para -or $para[0].stan -ne "usuniety") { return }
      $odp = [System.Windows.Forms.MessageBox]::Show($script:Okno,
        ("Autor usunął skill `„$($para[0].folder)`” ze swojego źródła. Twoja kopia nadal działa." + "`r`n`r`n" +
         "Czy usunąć go z Twojego komputera? Najpierw zrobię kopię zapasową - przycisk `„Przywróć usunięty`” wgra go z powrotem." + "`r`n`r`n" +
         "Po kliknięciu Nie nie stanie się nic."),
        "Usunąć skill?", [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question, [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
      if ($odp -ne [System.Windows.Forms.DialogResult]::Yes) { Notuj "skille: usuniecie $n - uzytkownik nie potwierdzil"; return }
      Rusz-Operacje-Skilli "usun" $n $false "Usuwam $n"
    } catch { Zanotuj-Wywrotke "przycisk Usun u mnie (skille)" $_ }
  })
  # Paczka do przekazania (P49): nic nie zmienia u Ciebie, wiec bez pytania. Odmowe
  # (dane wrazliwe w skillu) i sciezke gotowej paczki pokazuje wynik operacji po prawej.
  $script:BSkillSpakuj.Add_Click({
    try {
      $para = Znajdz-Skill $script:SkillWybrany
      if (-not $para -or -not $para[0].spoza -or $para[0].rodzaj -ne "wlasny") { return }
      Rusz-Operacje-Skilli "spakuj" "$($para[0].folder)" $false "Pakuję $($para[0].folder) do przekazania"
    } catch { Zanotuj-Wywrotke "przycisk Spakuj do przekazania (skille)" $_ }
  })
  $script:BSkillSpakujWszystkie.Add_Click({
    try { Rusz-Operacje-Skilli "spakuj" "*" $false "Pakuję wszystkie Twoje własne skille do przekazania" }
    catch { Zanotuj-Wywrotke "przycisk Spakuj wszystkie wlasne (skille)" $_ }
  })

  # Klikniecie warstwy pokazuje jej tresc po prawej. Wywrotka podgladu idzie
  # do dziennika i na ekran - nie zostawia starego podgladu udajacego nowy.
  $script:ListaWarstw.Add_SelectedIndexChanged({
    try {
      if ($script:ListaWarstw.SelectedItems.Count -gt 0) { Pokaz-Podglad $script:ListaWarstw.SelectedItems[0].Tag }
    } catch {
      Zanotuj-Wywrotke "podglad warstwy pamieci" $_
      if ($script:PodgladWarstwy -and -not $script:PodgladWarstwy.IsDisposed) {
        $script:PodgladWarstwy.Text = "NIE UDAŁO SIĘ POKAZAĆ TEJ WARSTWY: $($_.Exception.Message)"
      }
    }
  })

  # Przycisk bezpieczny - NIE pyta o zgode, bo nie wydaje ani jednego tokena.
  # Od 2026-10-07 tylko uruchamia aktualizacje w tle i NIE czeka (Kliknij-Aktualizuj);
  # do 0.28.0 wolal straznika synchronicznie do 180 s i okno zamarzalo bez wyniku.
  $script:BAktualizuj.Add_Click({
    try { Kliknij-Aktualizuj } catch { Zanotuj-Wywrotke "przycisk aktualizacji" $_ }
  })

  # JEDYNY przycisk w tym oknie, ktory wydaje tokeny - i dlatego jedyny, ktory
  # pyta. 24.09.2026 jego poprzednik ("Uruchom cykl teraz") wydal jednym
  # kliknieciem 312 609 tokenow, nie mowiac o tym ani slowa wczesniej.
  # Domyslnie podswietlone jest "Nie": przypadkowy Enter ma nic nie kosztowac.
  $script:BCykl.Add_Click({
    $n = Napisy-Przyciskow $script:Dane $script:Zuzycie
    $s = $n.Szacunek
    $t = @()
    # P17: tokeny i udzial w calym dziennym zuzyciu - bez procentu otwarcia okna rozmowy.
    $porownaj = {
      param($tokeny)
      $ud = ""
      try { $ud = Udzial-W-Dniu $tokeny $script:Zuzycie } catch { Zanotuj-Wywrotke "udzial w dziennym zuzyciu w pytaniu o zgode" $_ }
      if ($ud) { return "To $ud." }
      $bp = "Nie mam z czym porównać."
      try { $bp = (Z-Wielkiej (Bez-Porownania $script:Zuzycie)) + "." } catch { Zanotuj-Wywrotke "brak porownania w pytaniu o zgode" $_ }
      return $bp
    }
    if ($s -and ($null -ne $s.Tokeny)) {
      $t += "Przeczytanie nowych rozmów będzie kosztować około $(Liczba-Ludzka $s.Tokeny) tokenów."
      $t += (& $porownaj $s.Tokeny)
      $t += "Nie musisz tego robić - MegaRuchacz czyta rozmowy sam raz dziennie. Ten przycisk robi to tylko wcześniej."
    } else {
      $t += "NIE WIEM, ile to będzie kosztować."
      if ($s -and $s.Powod) { $t += "Powód: $($s.Powod)." }
      if ($script:Dane -and $script:Dane.Cykl -and ($null -ne $script:Dane.Cykl.Koszt)) {
        $t += "Poprzednie czytanie kosztowało ~$(Liczba-Ludzka $script:Dane.Cykl.Koszt) tokenów - takiego rzędu liczby się spodziewaj."
        $t += (& $porownaj $script:Dane.Cykl.Koszt)
      }
    }
    $t += ""
    if ($s) { foreach ($z in $s.Podstawa) { $t += $z } }
    $t += ""
    $t += "To jedyny przycisk w tym oknie, który naprawdę wydaje tokeny."
    $t += "Kliknij Tak, żeby uruchomić. Po kliknięciu Nie nie stanie się nic."
    $odp = [System.Windows.Forms.MessageBox]::Show(
      $script:Okno, ($t -join "`r`n"), "Przeczytać teraz nowe rozmowy?",
      [System.Windows.Forms.MessageBoxButtons]::YesNo,
      [System.Windows.Forms.MessageBoxIcon]::Warning,
      [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
    if ($odp -ne [System.Windows.Forms.DialogResult]::Yes) {
      Notuj "czytanie zaleglych rozmow: uzytkownik nie potwierdzil - nic nie ruszylo"
      return
    }

    $poszlo = $false
    try { $poszlo = Ruszaj-Cykl } catch { Zanotuj-Wywrotke "reczny start czytania rozmow" $_ }
    if ($poszlo) {
      $script:BCykl.Enabled = $false
      $script:LCykl.Text = "Czytanie ruszyło w tle. Potrwa kilka minut, liczby odświeżą się same."
      Notuj "czytanie zaleglych rozmow ruszylo z okna po potwierdzeniu kosztu"
    } else {
      $script:LCykl.Text = "NIE UDAŁO SIĘ uruchomić - szczegóły w oknie obok."
      [System.Windows.Forms.MessageBox]::Show(
        $script:Okno,
        ("Nie udało się uruchomić czytania rozmów." + "`r`n`r`n" +
         "Spróbuj ręcznie:" + "`r`n" +
         "powershell -ExecutionPolicy Bypass -File $Zrodlo\narzedzia\cykl-dzienny.ps1" + "`r`n`r`n" +
         "Ślad w $(Join-Path $KatalogDomowy '.claude\.megaruchacz-zasobnik.log')"),
        "Nie udało się", [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
  })

  # P59d: instalator w trybie zmiany - nic nie kosztuje, wiec bez pytania (Zmien-Instalacje).
  $script:BInstalacja.Add_Click({
    try { Zmien-Instalacje } catch { Zanotuj-Wywrotke "przycisk Zmien instalacje" $_ }
  })

  $bZamknij.Add_Click({ $script:Okno.Close() })

  $script:Okno = $f
  # Tresc (karty albo ekran ladowania) sklada sie PRZED pokazaniem okna - pierwsze
  # odmalowanie jest od razu docelowe, bez pustych kart (P21).
  $script:Widok = "przeglad"
  Styl-Przelacznika $script:BPrzeglad $true
  Styl-Przelacznika $script:BSzczegoly $false
  Styl-Przelacznika $script:BWarstwy $false
  Styl-Przelacznika $script:BSkille $false
  # stan aktualizacji przed pierwszym odmalowaniem - nowe okno po restarcie pokazuje wynik od razu
  try { Sprawdz-Aktualizacje $true } catch { Zanotuj-Wywrotke "stan aktualizacji przy budowie okna" $_ }
  Odmaluj-Przyciski
  # Watki do liczenia otwieraja sie dopiero PO pokazaniu okna - okno ma stanac
  # na ekranie jak najszybciej, a kroki i tak juz stoja na liscie jako "czeka".
  $script:PrzydzialPoPokazaniu = $true
  try { Wejdz-Do-Widoku "przeglad" $true } finally { $script:PrzydzialPoPokazaniu = $false }
  $f.Show()
  Wymus-Pokazanie $f
  Obsluz-Kroki
  Rusz-Zegar-Aktualizacji
}

# Znacznik dla nadzorca.ps1: ten plik wczytal sie do konca.
$script:ModulyOkna["okno"] = $true
