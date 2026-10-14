# zasobnik\nadzorca\okno.ps1 - czesc zasobnik\nadzorca.ps1 (patrz BUDOWA
# w jego naglowku). Budowa okna: Pokaz-Okno sklada formularz (naglowek
# z przelacznikiem, panele czterech zakladek, ekran ladowania, przyciski z pytaniem
# o zgode, zdarzenia) i pokazuje go; Pokaz-Widok przelacza zakladki. Od P59d takze
# zakladki i pasek wedlug rejestru instalacji (Uloz-Przelacznik, Uloz-Pasek,
# Ustaw-Instalacje-Okna) i przycisk "Zmień instalację" (Zmien-Instalacje,
# Po-Instalatorze, Instalator-Otwarty). Od 2026-10-07 postep aktualizacji MegaRuchacza
# z pliku stanu (Rusz-Zegar-Aktualizacji, Sprawdz-Aktualizacje, Kliknij-Aktualizuj). Od 2026-10-08
# przelaczanie zakladek bez migania (Pokaz-Panel, Ustaw-Panele-Widoku - wolane takze z w-tle.ps1,
# Panel-Widoku, Kontenery-Od-Dolu) i zakladki jako panele z podwojnym buforem.
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
  Styl-Przelacznika $script:BPrzeglad $przeg
  Styl-Przelacznika $script:BSzczegoly $szcz
  Styl-Przelacznika $script:BWarstwy $warst
  Styl-Przelacznika $script:BSkille $skil
  # 2026-10-08: najpierw tresc - przebudowa (gdy dane sie zmienily) idzie pod spodem, w jeszcze
  # schowanej zakladce - a dopiero potem jedno przelaczenie widocznosci (Ustaw-Panele-Widoku).
  Wejdz-Do-Widoku $nazwa
  Ustaw-Panele-Widoku $nazwa
}

# --- przelaczanie i odmalowanie bez migania (2026-10-08) ----------------------
# Uzytkownik: okno "dziwnie mruga przy kazdym przelaczaniu zakladek, nawet gdy dane sa juz
# wczytane". Zmierzone 08.10.2026 na kopii okna z prawdziwymi danymi (test-okno-mruganie.ps1):
# - Visible = $true na schowanej zakladce liczylo uklad od nowa po KAZDEJ z jej kontrolek
#   z osobna (kazda zgloszona widocznosc = pelny uklad rodzicow): Przeglad -> Szczegoly
#   11-12 s zamrozonego okna, Skille -> Przeglad 0,4-0,7 s. Pokaz-Panel wstrzymuje uklad calego
#   poddrzewa na czas zmiany i liczy go raz, od dolu: ok. 0,2 s i 0,02 s, polozenie wszystkich
#   kontrolek identyczne jak przed schowaniem.
# - Zakladka pokazywala sie kawalkami (Szczegoly 35-97 osobnych odmalowan, Warstwy i Skille
#   wymazanie calego tla, potem bialych kart, potem tresc), a przebudowa widocznego Przegladu
#   po cichym odswiezeniu wymazywala na oczach 400-2200 razy. Wszystkie cztery zakladki sa
#   panelami z podwojnym buforem (ListaBezMigania z wyglad.ps1): calosc malowana naraz, jednym
#   odmalowaniem - takze przy przebudowie widocznej zakladki. Wyglad bez zmian (zrzuty przed
#   i po identyczne), bezczynne okno nie maluje sie wcale, przewijanie Szczegolow ~40 ms na zabek.
# - Przebudowa przy wejsciu do zakladki (nowe dane) idzie pod spodem, w jeszcze schowanej
#   zakladce (Pokaz-Widok: najpierw Wejdz-Do-Widoku, potem Ustaw-Panele-Widoku).

function Panel-Widoku([string]$nazwa) {
  switch ($nazwa) {
    "szczegoly" { return $script:WidokSzczegoly }
    "warstwy"   { return $script:WidokWarstwy }
    "skille"    { return $script:WidokSkille }
    default     { return $script:WidokPrzeglad }
  }
}

# Kontenery poddrzewa od dolu: dzieci przed rodzicem - wznowione w tej kolejnosci licza
# swoj uklad raz, z gotowymi juz rozmiarami dzieci.
function Kontenery-Od-Dolu($c, $lista) {
  foreach ($d in $c.Controls) { if ($d.Controls.Count -gt 0) { Kontenery-Od-Dolu $d $lista } }
  [void]$lista.Add($c)
}

function Pokaz-Panel($panel) {
  if (-not $panel -or $panel.IsDisposed -or $panel.Visible) { return }
  $kontenery = New-Object System.Collections.Generic.List[object]
  Kontenery-Od-Dolu $panel $kontenery
  foreach ($c in $kontenery) { $c.SuspendLayout() }
  try { $panel.Visible = $true }
  finally { foreach ($c in $kontenery) { $c.ResumeLayout($true) } }
}

# Wybrana zakladka pokazuje sie PRZED schowaniem poprzedniej - miedzy nimi nie przeswituje
# puste tlo okna.
function Ustaw-Panele-Widoku([string]$nazwa) {
  $cel = Panel-Widoku $nazwa
  Pokaz-Panel $cel
  foreach ($p in @($script:WidokPrzeglad, $script:WidokSzczegoly, $script:WidokWarstwy, $script:WidokSkille)) {
    if ($p -and -not $p.IsDisposed -and -not [object]::ReferenceEquals($p, $cel)) { $p.Visible = $false }
  }
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
  # przy prawej krawedzi naglowka - takze w trakcie ciagniecia okna (Resize naglowka)
  $szerN = $script:SzerOkna
  if ($script:Naglowek -and -not $script:Naglowek.IsDisposed -and $script:Naglowek.Parent) { $szerN = [math]::Max($script:SzerOknaDomyslna, $script:Naglowek.ClientSize.Width) }
  $p.Location = New-Object System.Drawing.Point(($szerN - $script:Margines - $szer), 10)
}

# Pasek przyciskow: cztery kolumny (aktualizacja, czytanie rozmow, zmiana instalacji,
# zamkniecie). Bez modulu Wiedza kolumna czytania rozmow ma 0% i jest niewidoczna -
# reszta rozsuwa sie na cala szerokosc. Szerokosc opisow pod przyciskami idzie za
# kolumna, inaczej opis wyjechalby poza swoja kolumne albo zawijal sie bez potrzeby.
# Procenty: przy 1240 px okna kolumny maja 403/403/189/189 px - opisy mieszcza sie
# w dwoch liniach (zmierzone TextRenderer), czyli pasek nie jest wyzszy niz dotad.
# $wymus - po zmianie rozmiaru okna: te same procenty, nowe szerokosci opisow.
function Uloz-Pasek([bool]$zCyklem, [bool]$wymus = $false) {
  $p = $script:Pasek
  if (-not $p -or $p.IsDisposed -or ($p.ColumnStyles.Count -lt 4)) { return }
  $proc = $(if ($zCyklem) { @(34, 34, 16, 16) } else { @(50, 0, 25, 25) })
  # (po procentach, nie po Visible - Visible przycisku w niepokazanym jeszcze oknie to $false)
  if ((-not $wymus) -and ($p.ColumnStyles[0].Width -eq $proc[0]) -and ($p.ColumnStyles[1].Width -eq $proc[1])) { return }
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

# --- czytanie rozmow z przycisku (2026-10-08) -----------------------------------
# Po kliknieciu "Przeczytaj teraz" co 2 s zagladamy do wyniku czytania recznego
# (Stan-Recznego, stan-cykl.ps1) - ten sam wzorzec co aktualizacja: zegar, plik, zero
# czekania. Opis pod przyciskiem sklada Napisy-Przyciskow; tutaj tylko odmalowanie po
# zmianie, a na koniec okienko z odmowa albo bledem, zeby nie przeszlo bez slowa.
function Rusz-Zegar-Czytania {
  if (-not $script:ZegarCzytania) {
    $script:ZegarCzytania = New-Object System.Windows.Forms.Timer
    $script:ZegarCzytania.Interval = 2000
    $script:ZegarCzytania.Add_Tick({
      try { Pilnuj-Czytania }
      catch { $script:ZegarCzytania.Stop(); $script:CyklKlik = $null; Zanotuj-Wywrotke "zegar czytania rozmow" $_ }
    })
  }
  $script:ZegarCzytania.Start()
}

function Pilnuj-Czytania {
  if (-not $script:CyklKlik) { $script:ZegarCzytania.Stop(); return }
  $r = Stan-Recznego
  $ocena = Ocena-Klikniecia $r $script:CyklKlik ([datetime]::Now)
  $okno = ($script:Okno -and -not $script:Okno.IsDisposed)
  $widok = "$ocena|$(if ($r) { $r.Krotki })"
  if ($okno -and ($widok -ne $script:CzytanieWidok)) { $script:CzytanieWidok = $widok; Odmaluj-Przyciski }
  if (($ocena -eq "czekam") -or ($ocena -eq "trwa")) { return }

  $script:ZegarCzytania.Stop()
  $klik = $script:CyklKlik
  $script:CyklKlik = $null
  $tytul = "Czytanie rozmów"
  $ikona = [System.Windows.Forms.MessageBoxIcon]::Warning
  if ($ocena -eq "cisza") {
    $tekst = "Czytanie rozmów nie dało znaku życia przez $SEKUND_NA_START_RECZNEGO s od kliknięcia - nie wiem, czy w ogóle ruszyło."
    $script:NapisCyklu = [pscustomobject]@{ Czas = $klik; Tekst = $tekst }
    $tekst += "`r`n`r`nSpróbuj ręcznie:`r`npowershell -ExecutionPolicy Bypass -File $Zrodlo\narzedzia\cykl-dzienny.ps1 -Recznie" +
              "`r`n`r`nŚlad w $(Join-Path $KatalogDomowy '.claude\.megaruchacz-zasobnik.log')"
    Notuj "czytanie zaleglych rozmow z okna: przez $SEKUND_NA_START_RECZNEGO s ani sladu wyniku w .cykl-reczny"
  } else {
    Notuj "czytanie zaleglych rozmow z okna skonczone: $($r.Wynik) - $($r.Krotki)"
    if ($r.Udane) { $tekst = $null }
    else {
      $tekst = $r.Pelny
      if ($r.Wynik -eq "nic") { $ikona = [System.Windows.Forms.MessageBoxIcon]::Information }
    }
  }
  if (-not $okno) { return }   # okno zamkniete - wynik i tak stoi pod przyciskiem przy nastepnym otwarciu
  Odmaluj-Przyciski
  # liczby (kolejka, koszt, ostatnia nauka) od nowa - takze po odmowie, bo stan mogl sie zmienic
  try { [void](Przelicz-W-Tle) } catch { Zanotuj-Wywrotke "przeliczenie po czytaniu rozmow" $_ }
  if ($tekst) {
    [System.Windows.Forms.MessageBox]::Show($script:Okno, $tekst, $tytul,
      [System.Windows.Forms.MessageBoxButtons]::OK, $ikona) | Out-Null
  }
}

# --- rozmiar okna (2026-10-14) -------------------------------------------------
# Uzytkownik: okno ma sie dac rozciagac i maksymalizowac, zeby wygodniej sie czytalo.
# Zakladki, lista warstw, pola podgladu i pasek przyciskow rosna same (Dock), a karty
# Przegladu, Szczegolow i ekranu ladowania sa skladane na szerokosc SzerKarty - po zmianie
# rozmiaru Dopasuj-Do-Rozmiaru ustawia nowe szerokosci i uklada widoczna zakladke od nowa
# (schowane - przy wejsciu do nich). Rozmiar zapamietany per uzytkownik w
# ~\.claude\mr\okno-nadzorcy.json, obok innych plikow stanu (instalacja.json, aktualizacja.json).

function Plik-Rozmiaru-Okna {
  if ($script:NadzProba) { return $null }   # tryb probny nic nie zapisuje - i nie czyta rozmiaru prawdziwego okna
  return (Join-Path $script:NadzDom ".claude\mr\okno-nadzorcy.json")
}

# Zapamietany rozmiar albo $null (brak pliku, tryb probny, plik nieczytelny, okno poza
# ekranami). Nieczytelny plik i polozenie poza ekranem ida do dziennika - okno staje wtedy
# w rozmiarze domyslnym, a nie wywraca sie ani nie laduje tam, gdzie go nie widac.
function Wczytaj-Rozmiar-Okna($min) {
  $plik = Plik-Rozmiaru-Okna
  if (-not $plik -or -not (Test-Path -LiteralPath $plik -PathType Leaf)) { return $null }
  $l = @{}
  try {
    $j = [System.IO.File]::ReadAllText($plik) | ConvertFrom-Json
    if (-not $j) { throw "plik jest pusty" }
    foreach ($k in @("x", "y", "szer", "wys")) {
      $v = 0
      if (-not [int]::TryParse("$($j.$k)", [ref]$v)) { throw "pole '$k' nie jest liczba calkowita: '$($j.$k)'" }
      $l[$k] = $v
    }
    if ($j.max -isnot [bool]) { throw "pole 'max' nie jest prawda/falszem: '$($j.max)'" }
    if (($l.szer -le 0) -or ($l.wys -le 0) -or ($l.szer -gt 30000) -or ($l.wys -gt 30000)) { throw "rozmiar bez sensu: $($l.szer) x $($l.wys)" }
  } catch {
    Notuj "okno: zapamietany rozmiar okna nieczytelny ($plik): $($_.Exception.Message) - okno w rozmiarze domyslnym"
    return $null
  }
  # mniejszego niz domyslny nie bedzie (MinimumSize) - nie ma czego pilnowac
  $g = New-Object System.Drawing.Rectangle($l.x, $l.y, [math]::Max($l.szer, $min.Width), [math]::Max($l.wys, $min.Height))
  # Na ekranie = pasek tytulu (gorne 32 px) widac na ktoryms ekranie na co najmniej 200 px
  # szerokosci i 24 px wysokosci - za niego okno da sie zlapac. Okno przyklejone do krawedzi
  # wystaje poza nia o niewidzialna ramke (~7 px), dlatego nie wymagamy calego okna w ekranie.
  $tytul = New-Object System.Drawing.Rectangle($g.X, $g.Y, $g.Width, 32)
  $widac = $false
  foreach ($ekran in [System.Windows.Forms.Screen]::AllScreens) {
    $cz = [System.Drawing.Rectangle]::Intersect($ekran.WorkingArea, $tytul)
    if (($cz.Width -ge [math]::Min(200, $g.Width)) -and ($cz.Height -ge 24)) { $widac = $true; break }
  }
  if (-not $widac) {
    Notuj "okno: zapamietane polozenie okna ($($g.X), $($g.Y), $($g.Width) x $($g.Height)) jest poza ekranami (np. odlaczony monitor) - okno w rozmiarze domyslnym na srodku ekranu"
    return $null
  }
  return [pscustomobject]@{ Granice = $g; Max = [bool]$j.max }
}

# Przy zamykaniu okna. Zmaksymalizowane zapisuje rozmiar sprzed maksymalizacji
# (RestoreBounds) i znacznik max - po otwarciu jest znow zmaksymalizowane, a przywrocone
# wraca do swojego rozmiaru. Blad zapisu leci do wolajacego (Zanotuj-Wywrotke).
function Zapisz-Rozmiar-Okna($f) {
  $plik = Plik-Rozmiaru-Okna
  if (-not $plik) { Notuj "okno: tryb probny - rozmiaru okna nie zapisuje"; return }
  $stan = $f.WindowState
  $g = $(if ($stan -eq [System.Windows.Forms.FormWindowState]::Normal) { $f.Bounds } else { $f.RestoreBounds })
  $max = $(if ($stan -eq [System.Windows.Forms.FormWindowState]::Minimized) { [bool]$script:OknoMax } else { $stan -eq [System.Windows.Forms.FormWindowState]::Maximized })
  $kat = Split-Path -Parent $plik
  if (-not (Test-Path -LiteralPath $kat -PathType Container)) { New-Item -ItemType Directory -Force -Path $kat | Out-Null }
  $json = '{"x":' + $g.X + ',"y":' + $g.Y + ',"szer":' + $g.Width + ',"wys":' + $g.Height + ',"max":' + $(if ($max) { 'true' } else { 'false' }) +
          ',"zapisano":"' + (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss") + '"}'
  [System.IO.File]::WriteAllText($plik, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# Po zmianie rozmiaru (zegar z Resize) i w tescie. Gdy szerokosc wnetrza sie nie zmienila,
# nie robi nic - zmiana samej wysokosci zalatwia Dock (zakladki przewijaja sie w miejscu).
function Dopasuj-Do-Rozmiaru([bool]$wymus = $false) {
  $f = $script:Okno
  if (-not $f -or $f.IsDisposed) { return }
  if ($f.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { return }
  $stara = $script:SzerOkna
  Ustaw-Szerokosci $f.ClientSize.Width
  if ((-not $wymus) -and ($script:SzerOkna -eq $stara)) { return }
  $f.SuspendLayout()
  try {
    if ($script:LPodtytul) { $script:LPodtytul.MaximumSize = New-Object System.Drawing.Size(($script:SzerOkna - 2 * $script:Margines), 0) }
    Uloz-Przelacznik
    if ($script:Pasek -and ($script:Pasek.ColumnStyles.Count -ge 4)) { Uloz-Pasek ($script:Pasek.ColumnStyles[1].Width -gt 0) $true }
    $szerT = New-Object System.Drawing.Size($script:SzerTresc, 0)
    $szerK = New-Object System.Drawing.Size($script:SzerKarty, 0)
    foreach ($c in @($script:Root, $script:PanelProblemy, $script:ListaSzczegolow, $script:LadowanieRoot)) { if ($c -and -not $c.IsDisposed) { $c.MinimumSize = $szerT } }
    foreach ($c in @($script:KartaWerdykt, $script:KartaStart, $script:KartaKoszt, $script:PanelStan, $script:LadowanieKarta)) { if ($c -and -not $c.IsDisposed) { $c.MinimumSize = $szerK } }
    # ekran ladowania: karta ma wnetrze o 56 px wezsze (Zbuduj-Ladowanie)
    $szerL = $script:SzerKarty - 56
    if ($script:LLadowanieOpis) { $script:LLadowanieOpis.MaximumSize = New-Object System.Drawing.Size($szerL, 0) }
    if ($script:LLadowanieStopka) { $script:LLadowanieStopka.MaximumSize = New-Object System.Drawing.Size($szerL, 0) }
    if ($script:PasekLadowania) { $script:PasekLadowania.Width = $szerL }
    if ($script:ListaKrokow) { $script:ListaKrokow.MinimumSize = New-Object System.Drawing.Size($szerL, 0) }
    # Warstwy i Skille: lewa karta w tych samych procentach tresci co przy budowie
    if ($script:KartaListaWarstw) {
      $script:KartaListaWarstw.Width = [int]($script:SzerTresc * 0.48)
      if ($script:ListaWarstw -and ($script:ListaWarstw.Columns.Count -ge 3)) { $script:ListaWarstw.Columns[0].Width = $script:KartaListaWarstw.Width - 100 - 116 - 26 }
    }
    if ($script:KartaListaSkilli) { $script:KartaListaSkilli.Width = [int]($script:SzerTresc * 0.56) }
    $szerZdania = New-Object System.Drawing.Size(($script:SzerTresc - 164 - 4), 0)
    if ($script:LBezpSkilli) { $script:LBezpSkilli.MaximumSize = $szerZdania }
    if ($script:LSkille) { $script:LSkille.MaximumSize = $szerZdania }
  } finally { $f.ResumeLayout($true) }

  # Schowane zakladki nie biora udzialu w ukladzie okna (Visible = $false) i zostalyby
  # w starym rozmiarze - a Warstwy i Skille mierza swoje wnetrze przy budowie. Dostaja
  # granice widocznej zakladki, jak po pokazaniu.
  $wzor = $null
  foreach ($p in @($script:WidokLadowania, (Panel-Widoku $script:Widok))) { if ($p -and -not $p.IsDisposed -and $p.Visible) { $wzor = $p; break } }
  if ($wzor) {
    foreach ($p in @($script:WidokPrzeglad, $script:WidokSzczegoly, $script:WidokWarstwy, $script:WidokSkille, $script:WidokLadowania)) {
      if ($p -and -not $p.IsDisposed -and -not $p.Visible -and ($p.Bounds -ne $wzor.Bounds)) { $p.Bounds = $wzor.Bounds }
    }
  }
  if ($script:LSkille -and $script:LSkille.Parent -and $script:LSkille.Parent.Parent) {
    $script:LSkille.Parent.Parent.Height = [math]::Max(48, $script:LSkille.Bottom + 12)
  }

  if ($script:Ladowanie) { Uloz-Wiersze-Krokow; Odmaluj-Kroki }
  if ($script:LWarstwy -and -not $script:LWarstwy.IsDisposed) { Dopasuj-Etykiete $script:LWarstwy }
  if ($script:ListaWarstw -and ($script:ListaWarstw.SelectedItems.Count -gt 0)) { Pokaz-Info-Warstwy $script:ListaWarstw.SelectedItems[0].Tag }
  # lista skilli (wiersze na szerokosc listy) - sama lista, wybrany skill i wynik operacji zostaja
  $narysowana = $script:ListaSkilli -and ($script:ListaSkilli.Controls.Count -gt 0) -and ($script:ListaSkilli.Controls[0].Controls.Count -gt 0)
  if ($narysowana -and -not $script:SkilleOperacjaOd) {
    Napelnij-Skille $true
    if ($script:SkillWybrany) { $para = Znajdz-Skill $script:SkillWybrany; if ($para) { Pokaz-Info-Skilla $para } }
  }
  # Przeglad i Szczegoly - karty od nowa: widoczna zakladka teraz, schowana przy wejsciu.
  $script:DoOdmalowania["przeglad"] = $true
  $script:DoOdmalowania["szczegoly"] = $true
  if ($script:Ladowanie) { return }   # karty zlozy Sprawdz-Ladowanie, gdy liczenie sie skonczy
  if ($script:Widok -eq "przeglad") { Wyrenderuj-Widok "przeglad" }
  elseif (($script:Widok -eq "szczegoly") -and -not $script:SzczegolyZajete) {
    $przew = 0
    try { $przew = -$script:WidokSzczegoly.AutoScrollPosition.Y } catch { Zanotuj-Wywrotke "odczyt przewiniecia szczegolow (rozmiar)" $_ }
    Wyrenderuj-Widok "szczegoly"
    if ($przew -gt 0) {
      try { $script:WidokSzczegoly.AutoScrollPosition = New-Object System.Drawing.Point(0, $przew) }
      catch { Zanotuj-Wywrotke "przywrocenie przewiniecia szczegolow (rozmiar)" $_ }
    }
  }
}

# --- budowa okna -------------------------------------------------------------

function Pokaz-Okno {
  if ($script:Okno -and -not $script:Okno.IsDisposed) {
    # zminimalizowane wraca do tego, jakie bylo (zmaksymalizowane zostaje zmaksymalizowane)
    if ($script:Okno.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
      $script:Okno.WindowState = $(if ($script:OknoMax) { [System.Windows.Forms.FormWindowState]::Maximized } else { [System.Windows.Forms.FormWindowState]::Normal })
    }
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
  # 2026-10-14: okno rozciaga sie myszka i maksymalizuje (uzytkownik: wygodniej sie czyta).
  $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
  $f.MaximizeBox = $true
  # ROZMIAR OD PIERWSZEJ CHWILI (P21): wysokosc z ekranu, raz - okno nie rosnie ani
  # nie skacze w miare dochodzenia danych. Ten domyslny rozmiar jest zarazem
  # najmniejszym (MinimumSize) - mniej niz tyle i karty musialyby sie sciskac.
  # Rozmiar, polozenie i maksymalizacja z poprzedniego zamkniecia - gdy plik jest
  # czytelny, a okno nadal miesci sie na ktoryms ekranie (Wczytaj-Rozmiar-Okna);
  # inaczej rozmiar domyslny na srodku ekranu pod kursorem.
  $obszar = Obszar-Okna
  Ustaw-Szerokosci $script:SzerOknaDomyslna
  $f.ClientSize = New-Object System.Drawing.Size($script:SzerOkna, 720)
  $f.Height = [int][math]::Min($WYS_OKNA_MAX, $obszar.Height - 40)
  $f.MinimumSize = $f.Size
  $f.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
  $f.Location = New-Object System.Drawing.Point(($obszar.Left + [int](($obszar.Width - $f.Width) / 2)), ($obszar.Top + [int](($obszar.Height - $f.Height) / 2)))
  $zap = $null
  try { $zap = Wczytaj-Rozmiar-Okna $f.MinimumSize } catch { Zanotuj-Wywrotke "odczyt zapamietanego rozmiaru okna" $_ }
  $script:OknoMax = $false
  if ($zap) {
    $f.Bounds = $zap.Granice
    if ($zap.Max) {
      $script:OknoMax = $true
      $f.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
      # zmaksymalizowane okno ma wnetrze na cala szerokosc obszaru roboczego - tresc od razu
      # w tej szerokosci, bez przebudowy zaraz po pokazaniu
      Ustaw-Szerokosci ([System.Windows.Forms.Screen]::FromRectangle($zap.Granice).WorkingArea.Width)
    } else {
      Ustaw-Szerokosci $f.ClientSize.Width
    }
  }
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
  # Panel z podwojnym buforem (ListaBezMigania, wyglad.ps1) - cala zakladka malowana naraz,
  # nie karta po karcie (2026-10-08, patrz Pokaz-Panel). Tak samo trzy pozostale zakladki.
  $script:WidokPrzeglad = New-Object MegaRuchacz.ListaBezMigania
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
  $script:WidokSzczegoly = New-Object MegaRuchacz.ListaBezMigania
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
  $script:WidokWarstwy = New-Object MegaRuchacz.ListaBezMigania
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
  $script:KartaListaWarstw = $kartaLista
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
  $script:WidokSkille = New-Object MegaRuchacz.ListaBezMigania
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
  $script:LBezpSkilli = $lBezp
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
  $script:KartaListaSkilli = $kartaListaS
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
  # Rozmiar, polozenie i maksymalizacja zapamietane do nastepnego otwarcia (takze po
  # restarcie nadzorcy) - okno staje tak, jak je zostawiono.
  $f.Add_FormClosing({
    try { Zapisz-Rozmiar-Okna $script:Okno } catch { Zanotuj-Wywrotke "zapamietanie rozmiaru okna" $_ }
  })
  # Zmiana rozmiaru: zakladki, listy i pola rosna same (Dock), a karty skladane na
  # szerokosc (SzerKarty) ukladaja sie od nowa - raz, gdy mysz stanie (zegar), a nie
  # przy kazdym pikselu ciagniecia. Maksymalizacja i przywrocenie ida ta sama droga.
  $f.Add_Resize({
    try {
      if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
      if ($script:Okno.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { return }
      $script:OknoMax = ($script:Okno.WindowState -eq [System.Windows.Forms.FormWindowState]::Maximized)
      if (-not $script:ZegarRozmiaru) {
        $script:ZegarRozmiaru = New-Object System.Windows.Forms.Timer
        $script:ZegarRozmiaru.Interval = 200
        $script:ZegarRozmiaru.Add_Tick({
          $script:ZegarRozmiaru.Stop()
          try { Dopasuj-Do-Rozmiaru } catch { Zanotuj-Wywrotke "dopasowanie okna do rozmiaru" $_ }
        })
      }
      $script:ZegarRozmiaru.Stop()
      $script:ZegarRozmiaru.Start()
    } catch { Zanotuj-Wywrotke "zmiana rozmiaru okna" $_ }
  })
  $script:Naglowek.Add_Resize({ try { Uloz-Przelacznik } catch { Zanotuj-Wywrotke "przelacznik zakladek po zmianie rozmiaru" $_ } })
  $f.Add_FormClosed({
    # Dane (DaneWarstw, DaneSkilli, Rozbicie...) zostaja - to nie kontrolki. Drugie
    # otwarcie tego samego dnia pokazuje je od razu (P21); swiezosc pilnuja kawalki.
    $script:Ladowanie = $null; $script:WidokLadowania = $null; $script:ListaKrokow = $null; $script:WierszeKrokow = @{}
    if ($script:ZegarRozmiaru) { $script:ZegarRozmiaru.Stop() }
    $script:LadowanieRoot = $null; $script:LadowanieKarta = $null
    $script:KartaListaWarstw = $null; $script:KartaListaSkilli = $null; $script:LBezpSkilli = $null
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

    # -Recznie: czyta takze po dzisiejszym przebiegu automatu, a kazde zakonczenie (takze
    # odmowe) zostawia w .cykl-reczny - zegar nizej pokazuje je pod przyciskiem (08.10.2026:
    # do tej pory po dzisiejszym cyklu klikniecie konczylo sie niczym, bez slowa).
    $script:NapisCyklu = $null
    $script:CyklKlik = [datetime]::Now
    $poszlo = $false
    try { $poszlo = Ruszaj-Cykl $true } catch { Zanotuj-Wywrotke "reczny start czytania rozmow" $_ }
    if ($poszlo -and $script:NadzProba) {
      $script:CyklKlik = $null
      $script:LCykl.Text = "Tryb próbny - czytania nie uruchamiam."
    } elseif ($poszlo) {
      $script:BCykl.Enabled = $false
      $script:LCykl.Text = "Uruchamiam czytanie w tle..."
      Notuj "czytanie zaleglych rozmow ruszylo z okna po potwierdzeniu kosztu"
      $script:CzytanieWidok = ""
      Rusz-Zegar-Czytania
    } else {
      $script:CyklKlik = $null
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
