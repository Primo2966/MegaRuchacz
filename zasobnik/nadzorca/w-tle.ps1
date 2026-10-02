# zasobnik\nadzorca\w-tle.ps1 - czesc zasobnik\nadzorca.ps1 (patrz BUDOWA
# w jego naglowku). Liczenie w tle (P21, przebudowane P38): kawalki danych
# ($KAWALKI, $WIDOK_KAWALKI), kazdy krok liczony w OSOBNYM procesie powershell.exe
# (skrypt licz-krok.ps1) z limitem (Rusz-Krok -> Obsluz-Kroki -> Przydziel-Proces
# -> Odbierz-Krok / Przerwij-Krok -> Zakoncz-Krok), odmalowanie po kroku (Po-Kroku,
# Wyrenderuj-Widok), wejscie do zakladki (Wejdz-Do-Widoku), przeliczenie z menu
# (Przelicz-W-Tle) i dociaganie dziennego zuzycia (Odswiez-Zuzycie). Dozor co
# kwadrans jest w dozor.ps1, ekran ladowania w ladowanie.ps1.
# Skad wolane: okno.ps1, dozor.ps1, skille.ps1, ladowanie.ps1, menu ikony
# w nadzorca.ps1. Wczytuje go nadzorca.ps1 kropka po zamku jednej kopii - stale
# krokow i stan kawalkow ustawiaja sie przy wczytaniu, jak dawniej w tym miejscu.

# --- liczenie w tle i ekran ladowania (P21, 30.09.2026) ----------------------
# Uzytkownik: "Czy mozna cos zrobic z sama apka, zeby tak dziwnie nie otwierala
# sie, gdy rano ja klikam? Nie moze byc jakies okno postepu wczytywanych danych,
# zeby nie zmieniala swojego rozmiaru w dziki sposob?"
#
# NAGRANIE PRZED ZMIANA (P21, zrzuty co 200 ms + zegar kontrolny watku okna)
# pokazalo trzy rzeczy naraz: okno wstawalo w wysokosci policzonej dla PUSTYCH
# kart (1089 px); 150 ms pozniej caly interfejs stawal na ~3,7 s, bo Odswiez-Dane
# wolalo koszt-pamieci.ps1 (-Dane, -Start) w watku okna; potem karty rosly,
# Dopasuj-Wysokosc podnosilo okno do 1347 px, a po kolejnych 3 s (dzienne
# zuzycie) karty przestawialy sie jeszcze raz. Zakladki stawaly na 1,2-2,2 s.
#
# TERAZ:
# - okno ma od pierwszej chwili stala wysokosc (Pokaz-Okno) i samo jej nie zmienia,
# - wszystko, co wola skrypty, liczy sie w osobnych PROCESACH powershell.exe (P38:
#   dawniej w watkach-runspace'ach, ale kod watku skladany ze stringa wygladal
#   Defenderowi na omijanie zabezpieczen - patrz licz-krok.ps1), ktore
#   wczytuja stan-nadzorcy.ps1; watek okna co 150 ms tylko zaglada, co gotowe,
# - zakladka bez kompletu danych z dzis ma nad soba ekran ladowania z lista krokow;
#   karty buduja sie RAZ, z kompletem, i dopiero wtedy ekran znika,
# - dane z dzis pokazuja sie od razu; starsze niz $MINUT_SWIEZOSCI min odswiezaja
#   sie po cichu i zakladka odmalowuje sie raz, gdy odswiezanie sie skonczy,
# - kazdy krok ma limit czasu wyprowadzony z limitow tego, co wola (nizej); po nim
#   krok jest przerywany, a ekran ladowania mowi przy nim, co sie stalo.

# Ile krokow naraz. Kazdy to osobny proces powershell.exe (~70 MB), a niektore
# wolaja jeszcze koszt-pamieci.ps1 w kolejnym procesie. Trzy wystarczaja, zeby
# trzy kroki Przegladu szly rownolegle; reszta zakladek dochodzi, gdy zwolni sie
# miejsce.
$KROKI_NARAZ = 3
# Dozor przelicza dane co $Minut min - liczby mlodsze niz to sa tak swieze, jak
# cokolwiek, co okno mogloby policzyc. Takie pokazujemy bez liczenia.
$MINUT_SWIEZOSCI = [math]::Max(1, $Minut)
# Po nieudanym kroku ekran ladowania stoi jeszcze tyle sekund z bledem na wierzchu
# (z przyciskiem "Pokaz od razu"): tyle trwa przeczytanie jednego zdania. Ten sam
# powod zostaje potem w karcie i w Szczegolach - nic nie znika.
$SEKUNDY_PO_BLEDZIE = 5
# Najwyzsza wysokosc okna. Przeglad z kompletem danych zmierzony 30.09.2026 =
# 1351 px okna; 1400 zostawia miejsce na karte problemu. Na nizszym ekranie okno
# ma obszar roboczy minus 40 px, a Przeglad sie przewija - jak dotad.
$WYS_OKNA_MAX = 1400
# LIMITY CZASU KROKOW - kazdy z limitu tego, co krok woła, nie "na oko":
#  - koszt-pamieci.ps1 i skille.ps1 ida przez Wolaj-Skrypt z wlasnym limitem
#    (120 s / 90 s) i same oddaja powod "nie skonczyl w N s". Limit kroku = tamten
#    + 30 s na start procesu (zmierzone ~0,3 s) i odczyt: zabicie procesu przez okno
#    to ostatnia deska ratunku, gdyby proces utknal gdzie indziej;
#  - "dane" wola jeszcze gita bez sieci (Stan-Wersji, Stan-Cyklu, po 10 s) -> 180 s;
#  - dozor pobiera dodatkowo z sieci (git fetch 25 s) -> 240 s;
#  - dzienne zuzycie czeka na osobny proces liczacy: P17 zmierzyl 6-7 s dla 337 MB
#    transkryptow, 30.09 bylo 2,7 s - 60 s to ~10 razy zapasu na zimny dysk. Potem
#    karta mowi "jeszcze sie liczy" i dociaga wynik sama (Odswiez-Zuzycie), a samo
#    liczenie ma swoj limit $MINUT_LICZENIA_ZUZYCIA w stan-nadzorcy.ps1.
$SEKUNDY_ZUZYCIA = 60
$LIMIT_DOZORU = 240
# Kawalki danych. Kazdy liczy licz-krok.ps1 po NAZWIE kawalka (dispatch switchem
# tam, bez kodu ze stringa). Zwykle = ile sekund zwykle trwa (do paska postepu,
# zanim krok zmierzy sie sam). PowodToBlad = zwrocony powod to porazka (nastepne
# wejscie liczy od nowa z ekranem ladowania); przy pozostalych powod to wynik
# ("nie zmierzono, bo..."), ktory karta pokazuje, a liczyc od nowa nie ma po co.
$KAWALKI = [ordered]@{
  dane     = @{ Napis = "Sprawdzam stan MegaRuchacza i liczę rachunek za pamięć"; Limit = 180; Zwykle = 3; PowodToBlad = $false }
  start    = @{ Napis = "Liczę koszt otwarcia okna rozmowy"; Limit = 150; Zwykle = 2; PowodToBlad = $false }
  # zuzycie: licz-krok.ps1 czeka na wynik najwyzej $SEKUNDY_ZUZYCIA s (reszte dociaga
  # okno przez Odswiez-Zuzycie) - dlatego limit kroku to tyle plus zapas na start.
  zuzycie  = @{ Napis = "Sprawdzam dzienne zużycie tokenów"; Limit = ($SEKUNDY_ZUZYCIA + 30); Zwykle = 4; PowodToBlad = $false }
  rozbicie = @{ Napis = "Liczę rozbicie rachunku pozycja po pozycji"; Limit = 150; Zwykle = 2; PowodToBlad = $true }
  warstwy  = @{ Napis = "Zbieram listę warstw pamięci"; Limit = 150; Zwykle = 2; PowodToBlad = $true }
  skille   = @{ Napis = "Sprawdzam skille"; Limit = 120; Zwykle = 2; PowodToBlad = $true }
  # P26: prawdziwy koszt dnia (Koszt-Dzis w stan-nadzorcy.ps1). 30.09.2026: 1,2 s dla
  # ~130 MB transkryptow z ostatniej doby na cieplym dysku; zimny dysk jak w P17
  # (6-7 s dla 337 MB) to ~3 s - 60 s to ponad 10 razy zapasu.
  koszt    = @{ Napis = "Liczę, ile tokenów zużyły dziś rozmowy i workerzy"; Limit = 60; Zwykle = 2; PowodToBlad = $false }
}
# Czego potrzebuje kazda zakladka, zeby pokazac karty w komplecie.
$WIDOK_KAWALKI = @{
  przeglad  = @("dane", "start", "zuzycie", "koszt")
  szczegoly = @("dane", "start", "rozbicie", "koszt", "zuzycie")
  warstwy   = @("warstwy")
  skille    = @("skille")
}
$NAZWY_WIDOKOW = @{ przeglad = "Przegląd"; szczegoly = "Szczegóły"; warstwy = "Warstwy pamięci"; skille = "Skille" }
foreach ($id in $KAWALKI.Keys) { $script:StanKawalkow[$id] = [pscustomobject]@{ Id = $id; Czas = $null; Nieudany = $false; Krok = $null; Ostatni = $null } }

# Skrypt liczacy jeden krok w osobnym procesie (P38). Lezy obok modulow okna;
# test-p7.ps1 kopiuje caly katalog nadzorca\, wiec kopia okna znajduje go tak samo.
# Osobny proces zamiast dawnego watku-runspace'a z $KOD_KROKU: tamten skladal kod
# ze stringa i uruchamial go w procesie okna, a Defender widzial w tym omijanie
# zabezpieczen PowerShella. Szczegoly i argumenty - w naglowku licz-krok.ps1.
$script:PlikKroku = Join-Path $script:KatalogModulowOkna "licz-krok.ps1"
if (-not (Test-Path -LiteralPath $script:PlikKroku)) { Notuj "UWAGA: nie ma $($script:PlikKroku) - liczenie w tle nie ruszy" }

function Czas-Kawalka([string]$id) {
  # dane przychodza takze z dozoru - ich czas to czas danych w oknie
  if ($id -eq "dane") { if ($script:Dane) { return $script:DaneCzas } else { return $null } }
  return $script:StanKawalkow[$id].Czas
}

# Brak = nie ma danych z dzis albo ostatnia proba sie nie udala. Wtedy zakladka
# czeka na nie za ekranem ladowania.
function Brakuje-Kawalka([string]$id) {
  $c = Czas-Kawalka $id
  if (-not $c) { return $true }
  if ($c.Date -ne [datetime]::Today) { return $true }
  if (($id -ne "dane") -and $script:StanKawalkow[$id].Nieudany) { return $true }
  return $false
}

function Nieswiezy-Kawalek([string]$id) {
  $c = Czas-Kawalka $id
  if (-not $c) { return $true }
  if ($id -eq "zuzycie") {
    # srednia dzienna nie zmienia sie w ciagu dnia - z dzis znaczy swieza
    if ($script:Zuzycie -and ($script:Zuzycie.Stan -eq "jest")) { return $false }
    if ($script:Zuzycie -and ($script:Zuzycie.Stan -eq "licze")) { return $true }
  }
  return ((([datetime]::Now - $c).TotalMinutes) -ge $MINUT_SWIEZOSCI)
}

function Krok-Trwa($k) { return ($k -and (@("czeka", "otwiera", "liczy") -contains $k.Stan)) }

function Nowy-Krok([string]$id, [string]$kawalek, [string]$napis, [string]$zadanie, [bool]$zSiecia, [int]$limit) {
  return [pscustomobject]@{
    Id = $id; Kawalek = $kawalek; Napis = $napis; Zadanie = $zadanie; ZSiecia = $zSiecia; Limit = $limit
    Stan = "czeka"; Od = $null; Koniec = $null; Powod = ""; Wynik = $null
    Proces = $null; PlikWyniku = $null; PlikBledu = $null; Po = $null
  }
}

# Start kroku dla kawalka danych. Trwajacy krok nie rusza drugi raz - oddajemy
# ten, ktory juz liczy. $zSiecia tylko dla "dane" (menu: dane razem z siecia).
function Rusz-Krok([string]$id, [bool]$zSiecia = $false) {
  $kaw = $script:StanKawalkow[$id]
  if (Krok-Trwa $kaw.Krok) { return $kaw.Krok }
  $def = $KAWALKI[$id]
  $k = Nowy-Krok $id $id $def.Napis $id $zSiecia $def.Limit
  $kaw.Krok = $k
  [void]$script:KolejkaKrokow.Add($k)
  if (@("dane", "start", "zuzycie") -contains $id) { $script:Licze = $true }
  Wlacz-Zegar-Krokow
  Obsluz-Kroki
  return $k
}

function Wlacz-Zegar-Krokow {
  if (-not $script:ZegarKrokow) {
    $script:ZegarKrokow = New-Object System.Windows.Forms.Timer
    $script:ZegarKrokow.Interval = 150
    $script:ZegarKrokow.Add_Tick({
      try { Obsluz-Kroki; $script:BladZegaraKrokow = "" }
      catch {
        # Nie przerywamy (kroki musza sie dokonczyc), ale kazda NOWA wywrotka idzie do
        # dziennika. "Nowa" = inne miejsce w kodzie, a nie inny tekst - tekst potrafi
        # nosic zmieniajaca sie liczbe i zasypalby dziennik co 150 ms (zlapane w probie P21).
        $klucz = "$($_.Exception.GetType().Name)@$($_.InvocationInfo.ScriptLineNumber)"
        if ($script:BladZegaraKrokow -ne $klucz) {
          $script:BladZegaraKrokow = $klucz
          Zanotuj-Wywrotke "zegar krokow w tle" $_
        }
      }
      try { Straznik-Ladowania }
      catch { if ($script:BladZegaraKrokow -ne "straznik") { $script:BladZegaraKrokow = "straznik"; Zanotuj-Wywrotke "straznik ekranu ladowania" $_ } }
    })
  }
  if (-not $script:ZegarKrokow.Enabled) { $script:ZegarKrokow.Start() }
}

# Serce: co 150 ms. Odbiera gotowe procesy, przerywa te po limicie, daje prace
# czekajacym, odmalowuje ekran ladowania.
function Obsluz-Kroki {
  $teraz = [datetime]::Now
  foreach ($k in @($script:KrokiAktywne)) {
    if ($k.Stan -ne "liczy") { continue }
    $minelo = 0
    if ($k.Od) { $minelo = ($teraz - $k.Od).TotalSeconds }
    if ($k.Proces -and $k.Proces.HasExited) { Odbierz-Krok $k }
    elseif ($minelo -gt $k.Limit) { Przerwij-Krok $k }
  }
  while ((-not $script:PrzydzialPoPokazaniu) -and ($script:KrokiAktywne.Count -lt $KROKI_NARAZ) -and ($script:KolejkaKrokow.Count -gt 0)) {
    $k = $script:KolejkaKrokow[0]
    $script:KolejkaKrokow.RemoveAt(0)
    Przydziel-Proces $k
  }
  $script:Licze = $false
  foreach ($id in @("dane", "start", "zuzycie")) { if (Krok-Trwa $script:StanKawalkow[$id].Krok) { $script:Licze = $true } }
  if ($script:Ladowanie) { Sprawdz-Ladowanie }
  $pusto = ($script:KrokiAktywne.Count -eq 0) -and ($script:KolejkaKrokow.Count -eq 0) -and (-not $script:Ladowanie)
  if ($pusto) {
    # Nic nie liczy - zegar staje. Nastepne otwarcie okna wystartuje nowe procesy.
    if ($script:ZegarKrokow) { $script:ZegarKrokow.Stop() }
  }
}

# Start kroku: osobny, niewidoczny proces powershell.exe -File licz-krok.ps1.
# -NoNewWindow (jak Wolaj-Skrypt) - proces-dziecko nadzorcy chodzacego bez okna
# nie mruga konsola. Wynik trafia do pliku tymczasowego, blad procesu do drugiego.
# Bool i godzine (NadzZuzycieOdpalone) przekazujemy jako tekst - -File tak je bierze.
function Przydziel-Proces($k) {
  $k.Od = [datetime]::Now
  [void]$script:KrokiAktywne.Add($k)
  try {
    $k.PlikWyniku = [System.IO.Path]::GetTempFileName()
    $k.PlikBledu  = [System.IO.Path]::GetTempFileName()
    $odpalone = ""
    if ($script:NadzZuzycieOdpalone -is [datetime]) {
      $odpalone = $script:NadzZuzycieOdpalone.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    $lista = @(
      "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
      "-File", ('"' + $script:PlikKroku + '"'),
      "-PlikStanu", ('"' + $script:NadzTenPlik + '"'),
      "-Zrodlo", ('"' + $script:NadzZrodlo + '"'),
      "-Dom", ('"' + $script:NadzDom + '"'),
      "-Proba", ([string][bool]$script:NadzProba),
      "-Kawalek", $k.Zadanie,
      "-ZSiecia", ([string][bool]$k.ZSiecia),
      "-Odpalone", ('"' + $odpalone + '"'),
      "-SekundyZuzycia", ([string]$SEKUNDY_ZUZYCIA),
      "-PlikWyniku", ('"' + $k.PlikWyniku + '"')
    )
    $p = Start-Process -FilePath "powershell.exe" -ArgumentList $lista -NoNewWindow -PassThru -RedirectStandardError $k.PlikBledu
    $null = $p.Handle   # bez dotkniecia uchwytu ExitCode zostaje null po zakonczeniu (jak w Wolaj-Skrypt)
    $k.Proces = $p
    $k.Stan = "liczy"
  } catch {
    Zakoncz-Krok $k "blad" "nie udało się uruchomić liczenia w tle: $($_.Exception.Message)"
  }
}

# Sprzatniecie po kroku: zwolnienie procesu i skasowanie plikow tymczasowych.
function Sprzatnij-Proces-Kroku($k) {
  if ($k.Proces) {
    try { $k.Proces.Dispose() } catch { Notuj "nie dalo sie zwolnic procesu kroku $($k.Id): $($_.Exception.Message)" }
  }
  foreach ($p in @($k.PlikWyniku, $k.PlikBledu)) {
    if ($p) {
      try { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
      catch { Notuj "nie dalo sie skasowac pliku roboczego kroku $($k.Id): $($_.Exception.Message)" }
    }
  }
  $k.Proces = $null; $k.PlikWyniku = $null; $k.PlikBledu = $null
}

# Proces skonczyl - czytamy wynik z pliku (Export-Clixml w licz-krok.ps1). Pole
# Blad w pliku = krok policzyl sie do konca, ale cos w srodku sie wywrocilo. Brak
# pliku albo smiec = proces padl, zanim zapisal (powod bierzemy z pliku bledu).
function Odbierz-Krok($k) {
  $opak = $null; $blad = ""; $kodWyjscia = $null
  try { if ($k.Proces) { $kodWyjscia = $k.Proces.ExitCode } } catch { $kodWyjscia = $null }
  try {
    if ($k.PlikWyniku -and (Test-Path -LiteralPath $k.PlikWyniku) -and ((Get-Item -LiteralPath $k.PlikWyniku).Length -gt 0)) {
      $opak = Import-Clixml -LiteralPath $k.PlikWyniku
    }
    if (-not $opak -or ($null -eq $opak.PSObject.Properties["Wynik"])) {
      $blad = "liczenie nie oddało wyniku"
      $bl = ""
      if ($k.PlikBledu) { $bl = "$(Get-Content -LiteralPath $k.PlikBledu -Raw -ErrorAction SilentlyContinue)".Trim() }
      if ($bl) { $blad += ": $(($bl -replace '[\r\n]+', ' ').Trim())" }
      elseif ($null -ne $kodWyjscia) { $blad += " (proces zakończył się kodem $kodWyjscia)" }
      $opak = $null
    } elseif ($opak.Blad) {
      $blad = "$($opak.Blad)"
    }
  } catch {
    $surowy = ""
    if ($k.PlikWyniku) { $surowy = "$(Get-Content -LiteralPath $k.PlikWyniku -Raw -ErrorAction SilentlyContinue)".Trim() }
    if ($surowy) { $blad = "nie odczytałem wyniku liczenia w tle: $(($surowy -replace '[\r\n]+', ' ').Trim())" }
    else { $blad = "nie odczytałem wyniku liczenia w tle: $($_.Exception.Message)" }
    $opak = $null
  }
  Sprzatnij-Proces-Kroku $k
  if ($blad) { Zakoncz-Krok $k "blad" $blad; return }
  foreach ($w in @($opak.Wywrotki)) { if ($w) { $script:NadzWywrotki += "$w" } }
  if ($k.Id -eq "zuzycie") { $script:NadzZuzycieOdpalone = $opak.Odpalone }
  $k.Wynik = $opak.Wynik
  Zakoncz-Krok $k "ok" ""
}

function Przerwij-Krok($k) {
  $pw = "nie skończyło się w $($k.Limit) s - przerwałem"
  if ($k.Proces) {
    try { if (-not $k.Proces.HasExited) { $k.Proces.Kill() } }
    catch { Notuj "przerwanie kroku $($k.Id): $($_.Exception.Message)" }
  }
  Sprzatnij-Proces-Kroku $k
  Zanotuj-Wywrotke "liczenie w tle: $($k.Napis)" $pw
  Zakoncz-Krok $k "czas" $pw
}

# Wynik kroku trafia do zmiennych okna. Porazka (wywrotka albo limit) zostawia
# po sobie powod w tych samych miejscach, w ktorych stawialy go stare "catch" -
# karta mowi "nie zmierzono, bo...", a nie pokazuje pustki.
function Zakoncz-Krok($k, [string]$stan, [string]$powod) {
  $script:KrokiAktywne.Remove($k)
  $k.Koniec = [datetime]::Now
  $k.Stan = $stan
  $k.Powod = $powod
  if ($k.Od) { $script:CzasyKrokow[$k.Id] = ($k.Koniec - $k.Od).TotalSeconds }
  $id = $k.Kawalek
  if ($id) {
    $porazka = ($stan -ne "ok")
    try {
      switch ($id) {
        "dane" {
          if ($porazka) { $script:DaneBlad = $powod }
          else {
            $script:Dane = $k.Wynik; $script:DaneCzas = $k.Koniec; $script:DaneBlad = $null
            # P59d: swiezy odczyt rejestru instalacji - zakladki i karty za nim
            if ($script:Dane) { Ustaw-Instalacje-Okna $script:Dane.Instalacja }
          }
        }
        "start" {
          if ($porazka) { $script:Start = [pscustomobject]@{ Powod = "pomiar się wywrócił: $powod"; MrSesja = $null } }
          else { $script:Start = $k.Wynik }
        }
        "zuzycie" {
          if ($porazka) { $script:Zuzycie = [pscustomobject]@{ Stan = "brak"; Powod = "odczyt się wywrócił: $powod" } }
          else {
            $script:Zuzycie = $k.Wynik
            # dalej liczy (dluzej niz $SEKUNDY_ZUZYCIA) - zegar co 3 s dociagnie wynik sam
            if ($script:Zuzycie.Stan -eq "licze") { Odswiez-Zuzycie }
          }
        }
        "rozbicie" {
          if ($porazka) { $script:Rozbicie = @("  NIE UDALO SIE POLICZYC ROZBICIA: $powod") }
          else { $script:Rozbicie = $k.Wynik }
        }
        "warstwy" {
          if ($porazka) { $script:DaneWarstw = [pscustomobject]@{ Warstwy = @(); Uwagi = @(); Powod = $powod; Wygenerowano = ""; TrybGlobalny = $null; Projekt = "" } }
          else { $script:DaneWarstw = $k.Wynik }
        }
        "skille" {
          if ($porazka) { $script:DaneSkilli = [pscustomobject]@{ Dane = $null; Powod = $powod } }
          else { $script:DaneSkilli = $k.Wynik }
        }
        "koszt" {
          if ($porazka) { $script:KosztDzis = [pscustomobject]@{ Powod = "liczenie się nie udało: $powod" } }
          else { $script:KosztDzis = $k.Wynik }
        }
      }
    } catch { Zanotuj-Wywrotke "przyjecie wyniku kroku $id" $_ }
    if ($porazka) {
      if ($stan -eq "blad") { Zanotuj-Wywrotke "liczenie w tle: $($k.Napis)" $powod }
    } else {
      # Krok przeszedl, ale oddal powod ("nie zmierzono, bo...") - to tez ma byc
      # widac przy kroku, nie tylko w karcie.
      $pw = ""
      try { $pw = Powod-Kawalka $id } catch { Zanotuj-Wywrotke "powod kroku $id" $_ }
      if ($pw) { $k.Stan = "uwaga"; $k.Powod = $pw }
    }
    $kaw = $script:StanKawalkow[$id]
    $kaw.Czas = $k.Koniec
    $kaw.Nieudany = $porazka -or (($k.Stan -eq "uwaga") -and $KAWALKI[$id].PowodToBlad)
    $kaw.Ostatni = $k
    if ($kaw.Krok -eq $k) { $kaw.Krok = $null }
  }
  if ($k.Po) {
    try { & $k.Po $k } catch { Zanotuj-Wywrotke "dokonczenie kroku $($k.Id)" $_ }
  }
  if ($id) { Po-Kroku $id }
}

# Powod, ktory zwrocil sam wynik - pusty, gdy wszystko jest.
function Powod-Kawalka([string]$id) {
  switch ($id) {
    "dane" {
      if (-not $script:Dane) { return "nic nie wróciło" }
      if (-not $script:Dane.Rachunek) { return "rachunek za pamięć się nie policzył - szczegóły w dzienniku nadzorcy" }
      if ($script:Dane.Rachunek.Powod) { return "rachunek za pamięć: $($script:Dane.Rachunek.Powod)" }
      # bez modulu Wiedza stanu nauki nie czytamy wcale (P59d) - to nie brak
      if ((-not $script:Dane.Cykl) -and (Modul-Jest $script:Dane.Instalacja "wiedza")) { return "nie odczytałem stanu nauki z rozmów - szczegóły w dzienniku nadzorcy" }
    }
    "start" { if ($script:Start -and $script:Start.Powod) { return "nie zmierzono, bo $($script:Start.Powod)" } }
    "zuzycie" {
      if ($script:Zuzycie -and ($script:Zuzycie.Stan -eq "licze")) { return "liczy się dłużej niż $SEKUNDY_ZUZYCIA s - pokażę resztę, a porównanie dojdzie samo, gdy będzie" }
      if ($script:Zuzycie -and ($script:Zuzycie.Stan -eq "brak")) { return "$($script:Zuzycie.Powod)" }
    }
    "rozbicie" {
      $l = @(@($script:Rozbicie) | Where-Object { "$_" -match 'NIE UDALO SIE|RACHUNEK PUSTY' } | Select-Object -First 1)
      if ($l.Count -gt 0) { return "$($l[0])".Trim() }
    }
    "warstwy" { if ($script:DaneWarstw -and $script:DaneWarstw.Powod) { return "$($script:DaneWarstw.Powod)" } }
    "skille" { if ($script:DaneSkilli -and $script:DaneSkilli.Powod) { return "$($script:DaneSkilli.Powod)" } }
    "koszt" { if ($script:KosztDzis -and $script:KosztDzis.Powod) { return "$($script:KosztDzis.Powod)" } }
  }
  return ""
}

# Po kazdym kroku: zakladki, ktore z niego korzystaja, sa do odmalowania. Ekran
# ladowania decyduje sam (Sprawdz-Ladowanie); bez niego biezaca zakladka
# odmalowuje sie RAZ, gdy zaden z jej krokow juz nie liczy.
function Po-Kroku([string]$id) {
  foreach ($w in @($WIDOK_KAWALKI.Keys)) { if (@($WIDOK_KAWALKI[$w]) -contains $id) { $script:DoOdmalowania[$w] = $true } }
  if (($id -eq "dane") -and $script:Ikona) {
    try { $script:Ikona.Text = Podpowiedz $script:Dane } catch { Zanotuj-Wywrotke "podpowiedz przy ikonie" $_ }
  }
  if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
  if ($script:Ladowanie) { return }
  Odswiez-Widoczne
}

function Odswiez-Widoczne {
  $w = $script:Widok
  if (-not $script:DoOdmalowania[$w]) { Odmaluj-Podtytul; return }
  foreach ($id in @($WIDOK_KAWALKI[$w])) { if (Krok-Trwa $script:StanKawalkow[$id].Krok) { Odmaluj-Podtytul; return } }
  Wyrenderuj-Widok $w
}

function Wyrenderuj-Widok([string]$w) {
  switch ($w) {
    "przeglad"  { Odmaluj-Okno }
    "szczegoly" {
      Odmaluj-Podtytul
      if (-not $script:SzczegolyZajete) {
        # Budowa kilkudziesieciu kart trwa ~1,3 s (zmierzone 30.09.2026) i musi isc
        # w watku okna. Za pierwszym razem najpierw jedno zdanie, zeby klikniecie
        # dalo znak od razu, a nie wygladalo na zawieszenie.
        if ($script:ListaSzczegolow -and ($script:ListaSzczegolow.Controls.Count -eq 0) -and $script:Okno.Visible) {
          Pokaz-Karty-Szczegolow @(Karta-Komunikatu "Układam zakładkę..." @("Kilkadziesiąt kart z liczbami - to trwa około sekundy.") $null)
          $script:Okno.Update()
        }
        Napelnij-Szczegoly
      }
    }
    "warstwy"   { Odmaluj-Podtytul; Napelnij-Warstwy }
    "skille" {
      Odmaluj-Podtytul
      # w trakcie operacji z przycisku lista stoi (zegar operacji ja odswiezy po koncu)
      $narysowana = $script:ListaSkilli -and ($script:ListaSkilli.Controls.Count -gt 0) -and ($script:ListaSkilli.Controls[0].Controls.Count -gt 0)
      if ($script:SkilleOperacjaOd -and $narysowana) { return }
      Napelnij-Skille
      if ($script:SkillePoOperacji -and $script:SkillePodglad -and -not $script:SkillePodglad.IsDisposed) {
        $script:SkillePodglad.Text = $script:SkillePoOperacji
        $script:SkillePodglad.SelectionStart = 0
        $script:SkillePodglad.ScrollToCaret()
      }
      $script:SkillePoOperacji = $null
    }
  }
}

# Wejscie do zakladki (takze przy otwarciu okna). Brak danych z dzis -> ekran
# ladowania; dane nieswieze -> zakladka od razu, odswiezenie po cichu. Przy
# otwarciu okna w tle rusza tez to, czego brakuje innym zakladkom - przelaczenie
# ma byc od razu.
function Wejdz-Do-Widoku([string]$widok, [bool]$otwarcie = $false) {
  if (-not $script:Okno -or $script:Okno.IsDisposed) { return }
  if (($widok -eq "szczegoly") -and $script:SzczegolyZajete) { Ukryj-Ladowanie; return }
  $ids = @($WIDOK_KAWALKI[$widok])
  $kroki = @{}
  $brak = $false
  foreach ($id in $ids) {
    $b = Brakuje-Kawalka $id
    if ($b) { $brak = $true }
    if ($b -or (Nieswiezy-Kawalek $id)) { $kroki[$id] = Rusz-Krok $id }
    elseif (Krok-Trwa $script:StanKawalkow[$id].Krok) { $kroki[$id] = $script:StanKawalkow[$id].Krok }
  }
  if ($otwarcie) {
    foreach ($w in @("przeglad", "szczegoly", "warstwy", "skille")) {
      # zakladki Skille bez jej modulu nie ma - jej danych nie liczymy (P59d)
      if (($w -eq "skille") -and -not (Modul-Jest $script:Instalacja "skille")) { continue }
      foreach ($id in @($WIDOK_KAWALKI[$w])) { if (Brakuje-Kawalka $id) { [void](Rusz-Krok $id) } }
    }
  }
  # Kroki ogladanej zakladki na poczatek kolejki - nie czekaja za tlem innych zakladek.
  foreach ($id in @($ids)[($ids.Count - 1)..0]) {
    $k = $script:StanKawalkow[$id].Krok
    if ($k -and ($k.Stan -eq "czeka") -and $script:KolejkaKrokow.Contains($k)) {
      $script:KolejkaKrokow.Remove($k)
      $script:KolejkaKrokow.Insert(0, $k)
    }
  }
  Obsluz-Kroki
  if ($brak) { Pokaz-Ladowanie $widok $ids $kroki; return }
  Ukryj-Ladowanie
  if ($script:DoOdmalowania[$widok]) { Wyrenderuj-Widok $widok } else { Odmaluj-Podtytul }
}

# Recznie zlecone przeliczenie (menu, po pobraniu nowszej wersji): Przeglad zostaje
# na ekranie, liczy sie w tle i odmalowuje raz na koncu.
function Przelicz-W-Tle([bool]$zSiecia = $false) {
  $k = Rusz-Krok "dane" $zSiecia
  [void](Rusz-Krok "start")
  [void](Rusz-Krok "zuzycie")
  [void](Rusz-Krok "koszt")
  return $k
}

# Dzienne zuzycie tokenow (P17): odczyt pliku podrecznego, a gdy wyniku z dzis
# nie ma - liczenie w osobnym procesie. Okno nie czeka: zegar co 3 s sprawdza,
# czy wynik juz jest, i wtedy odmalowuje okno. Zegar staje sam, gdy stan
# przestaje byc "licze" (wynik albo powod, czemu go nie ma - nigdy wieczne "licze":
# Zuzycie-Dzienne po $MINUT_LICZENIA_ZUZYCIA zamienia je na powod).
function Odswiez-Zuzycie {
  try { $script:Zuzycie = Zuzycie-Dzienne $false }
  catch {
    Zanotuj-Wywrotke "dzienne zuzycie tokenow" $_
    $script:Zuzycie = [pscustomobject]@{ Stan = "brak"; Powod = "odczyt się wywrócił: $($_.Exception.Message)" }
  }
  if (-not $script:Zuzycie -or ($script:Zuzycie.Stan -ne "licze")) {
    if ($script:ZegarZuzycia) { $script:ZegarZuzycia.Stop() }
    return
  }
  if (-not $script:ZegarZuzycia) {
    $script:ZegarZuzycia = New-Object System.Windows.Forms.Timer
    $script:ZegarZuzycia.Interval = 3000
    $script:ZegarZuzycia.Add_Tick({
      try {
        $przed = $script:Zuzycie.Stan
        Odswiez-Zuzycie
        if ($script:Zuzycie.Stan -ne $przed) { Odmaluj-Okno }
      } catch {
        $script:ZegarZuzycia.Stop()
        Zanotuj-Wywrotke "zegar dziennego zuzycia tokenow" $_
      }
    })
  }
  $script:ZegarZuzycia.Start()
}

# Znacznik dla nadzorca.ps1: ten plik wczytal sie do konca.
$script:ModulyOkna["w-tle"] = $true
