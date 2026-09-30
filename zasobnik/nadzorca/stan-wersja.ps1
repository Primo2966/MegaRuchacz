# zasobnik\nadzorca\stan-wersja.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Wersja narzedzia: numer z ZMIANY.md (Wersja-Narzedzia),
# porownanie z serwerem przez gita (Stan-Wersji), wiersze dla okna (Wiersz,
# Opis-Wersji) i przycisk aktualizacji (Aktualizuj -> straznik-zasad.ps1 -Tlo).
# Wiersz to klocek wierszy Szczegolow uzywany we wszystkich modulach.
# Skad wolane: stan-zbieranie.ps1 (Stan-Wersji), szczegoly.ps1 (Opis-Wersji),
# okno.ps1 (Aktualizuj). Wczytuje go stan-nadzorcy.ps1 kropka - same definicje.

# ----------------------------------------------------------------- numer wersji

# TA SAMA logika, co Wersja-Narzedzia w wdroz.ps1 (najwyzszy naglowek "## X.Y.Z"
# w ZMIANY.md). Przepisana, a nie dot-sourcowana, bo wdroz.ps1 to skrypt, ktory
# przy wczytaniu wykonalby sie w calosci. Gdy tamta funkcja sie zmieni, ta ma
# pojsc za nia - stad ten komentarz.
function Wersja-Narzedzia($plikZmian) {
  if (-not (Test-Path $plikZmian)) { return $null }
  $naj = $null
  $raw = Czytaj-Tekst $plikZmian
  if (-not $raw) { return $null }
  foreach ($m in [regex]::Matches($raw, '(?m)^##\s+(\d+)\.(\d+)\.(\d+)')) {
    $w = [version]("{0}.{1}.{2}" -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value)
    if ($null -eq $naj -or $w -gt $naj) { $naj = $w }
  }
  if ($null -eq $naj) { return $null }
  return $naj.ToString()
}

# Numer wersji plus odpowiedz na pytanie, czy na gicie lezy cos nowszego.
# $zSieci = $false znaczy "nie ruszaj sieci, powiedz co wiesz z ostatniego pobrania" -
# tak liczymy przy kazdym otwarciu okna, zeby nie czekalo na fetch.
# Zwraca zawsze komplet pol; gdy czegos nie da sie ustalic, w Powod stoi DLACZEGO.
function Stan-Wersji([bool]$zSieci) {
  $w = [pscustomobject]@{
    Lokalna   = $null
    Nowsza    = $null      # ile commitow zdalna ma ponad nami ($null = nie wiadomo)
    Nasze     = $null      # ile mamy lokalnych, ktorych nie ma na zdalnej
    Pobrano   = $null      # kiedy ostatnio zagladalismy do sieci
    Powod     = ""         # dlaczego nie wiadomo
  }
  $plikZmian = Join-Path $script:NadzZrodlo "ZMIANY.md"
  $w.Lokalna = Wersja-Narzedzia $plikZmian
  if (-not $w.Lokalna) { $w.Powod = "nie umiem odczytac numeru wersji z ${plikZmian}" }

  $cyt = '"' + $script:NadzZrodlo + '"'
  $repo = Wolaj-Gita "-C $cyt rev-parse --is-inside-work-tree" $CZAS_GIT
  if (-not $repo.ok -or $repo.tekst -ne "true") {
    $w.Powod = "$($script:NadzZrodlo) to nie repozytorium git - nie ma z czym porownywac"
    return $w
  }

  $stan = Czytaj-Klucze $script:NadzPlikStanu
  $w.Pobrano = Data-Lub-Nic $stan["pobranie"]
  if ($zSieci) {
    $swieze = $false
    if ($w.Pobrano -and (([datetime]::Now - $w.Pobrano).TotalMinutes -lt $MINUT_MIEDZY_POBRANIAMI)) { $swieze = $true }
    if (-not $swieze) {
      $env:GIT_TERMINAL_PROMPT = "0"
      $pobrane = Wolaj-Gita "-C $cyt -c credential.interactive=never fetch --quiet" $CZAS_GIT_FETCH
      if ($pobrane.ok) {
        $w.Pobrano = [datetime]::Now
        if (-not $script:NadzProba) {
          try { Dopisz-Klucze $script:NadzPlikStanu @{ pobranie = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') } }
          catch { Notuj "nie udalo sie zapisac znacznika pobrania" }
        }
      } else {
        $w.Powod = "nie udalo sie zajrzec do sieci ($($pobrane.powod)) - porownuje z tym, co bylo pobrane wczesniej"
      }
    }
  }

  $licznik = Wolaj-Gita "-C $cyt rev-list --left-right --count HEAD...@{u}" $CZAS_GIT
  if (-not $licznik.ok) {
    if (-not $w.Powod) { $w.Powod = "git nie policzyl roznicy wobec zdalnej ($($licznik.powod))" }
    return $w
  }
  $czesci = $licznik.tekst -split '\s+'
  if ($czesci.Count -lt 2) {
    if (-not $w.Powod) { $w.Powod = "git oddal nieczytelna odpowiedz o roznicy: $($licznik.tekst)" }
    return $w
  }
  $w.Nasze  = [int]$czesci[0]
  $w.Nowsza = [int]$czesci[1]
  return $w
}

# Jeden wiersz szczegolow: etykieta po ludzku, wartosc i waga ("" / "uwaga" /
# "pilne" / "szary"). Okno rysuje z tego dwie kolumny, wydruk -Raport - linie
# "etykieta : wartosc". Jedna struktura dla obu, zeby sie nie rozjechaly.
function Wiersz([string]$etykieta, [string]$wartosc, [string]$waga = "") {
  return [pscustomobject]@{ Etykieta = $etykieta; Wartosc = $wartosc; Waga = $waga }
}

# Wersja narzedzia jako wiersze. Do 2026-09-25 byly to linie tekstu z zargonem
# ("na gicie", "commitow") - teraz etykiety mowia po ludzku, a waga koloruje
# tylko to, co naprawde czegos wymaga.
function Opis-Wersji($w) {
  $lok = $w.Lokalna
  $wagaLok = ""
  if (-not $lok) { $lok = "nie wiadomo"; $wagaLok = "uwaga" }
  $linie = @(Wiersz "Wersja na tym komputerze" $lok $wagaLok)
  if ($null -eq $w.Nowsza) {
    $powod = $w.Powod
    if (-not $powod) { $powod = "nie ustaliłem powodu - to samo w sobie jest usterką" }
    $linie += Wiersz "Nowsza na serwerze" "nie wiadomo - $powod" "uwaga"
  } elseif ($w.Nowsza -le 0) {
    $linie += Wiersz "Nowsza na serwerze" "nie ma, masz najnowszą"
  } else {
    $linie += Wiersz "Nowsza na serwerze" "czeka $($w.Nowsza) $(Odmiana ([int]$w.Nowsza) 'zmiana' 'zmiany' 'zmian') - pobierze je przycisk na dole okna" "uwaga"
  }
  if ($w.Nasze -gt 0) {
    $linie += Wiersz "Uwaga" "na tym komputerze jest $($w.Nasze) $(Odmiana ([int]$w.Nasze) 'własna zmiana' 'własne zmiany' 'własnych zmian'), których nie ma na serwerze - aktualizacja odmówi scalenia" "uwaga"
  }
  if ($w.Pobrano) {
    $linie += Wiersz "Ostatnio sprawdzone" "$($w.Pobrano.ToString('yyyy-MM-dd HH:mm'))"
  } else {
    $linie += Wiersz "Ostatnio sprawdzone" "jeszcze ani razu w tej instalacji" "szary"
  }
  return ,$linie
}

# ------------------------------------------------------------------ aktualizacja

# Przycisk [Aktualizuj] robi DOKLADNIE to, co dzis robi hook Codeksa: wola
# narzedzia\straznik-zasad.ps1 -Tlo. Nie ma tu drugiej implementacji pobierania
# (fetch + merge --ff-only, nigdy reset --hard) ani drugiego kompletu warunkow
# odmowy - straznik ma je u siebie i to on jest jedynym zrodlem prawdy.
# Straznik w tym trybie milczy na ekran i pisze do ~\.claude\.megaruchacz-tlo.log,
# wiec bierzemy stad roznice: to, co dopisal, jest odpowiedzia dla czlowieka.
function Aktualizuj {
  $skrypt = Join-Path $script:NadzZrodlo "narzedzia\straznik-zasad.ps1"
  $plikLogu = Join-Path $script:NadzDom ".claude\.megaruchacz-tlo.log"
  $przed = @()
  $raw = Czytaj-Tekst $plikLogu
  if ($raw) { $przed = @(($raw -split '\r?\n') | Where-Object { $_.Trim() }) }

  if ($script:NadzProba) { return ,@("[proba] NIE wolam straznika: ${skrypt} -Tlo") }

  $r = Wolaj-Skrypt $skrypt @("-Tlo", "-Zrodlo", ('"' + $script:NadzZrodlo + '"'), "-KatalogDomowy", ('"' + $script:NadzDom + '"')) 180
  if (-not $r.ok) {
    Zanotuj-Wywrotke "aktualizacja przez straznika" $r.powod
    return ,@("NIE UDALO SIE: $($r.powod)",
             "sprobuj recznie: powershell -ExecutionPolicy Bypass -File ${skrypt} -Tlo")
  }

  $po = @()
  $raw = Czytaj-Tekst $plikLogu
  if ($raw) { $po = @(($raw -split '\r?\n') | Where-Object { $_.Trim() }) }

  # Dziennik jest obcinany z gory do stalej liczby linii, wiec porownujemy
  # tresc, a nie indeksy - inaczej po obcieciu "nowe" wyszlyby stare linie.
  $nowe = @()
  if ($po.Count -gt 0) {
    $zbior = @{}
    foreach ($l in $przed) { $zbior[$l] = $true }
    foreach ($l in $po) { if (-not $zbior.ContainsKey($l)) { $nowe += $l } }
  }
  if ($nowe.Count -eq 0) {
    # Cisza po straznikU nie znaczy "wszystko gra" - znaczy, ze nie wiemy.
    return ,@("Straznik przeszedl (kod $($r.kod)), ale nie dopisal ani jednej linii do dziennika.",
             "To NIE jest potwierdzenie, ze cos pobral - to brak odpowiedzi.",
             "Dziennik: ${plikLogu}")
  }
  Notuj "aktualizacja: $($nowe.Count) nowych linii w dzienniku straznika"
  return ,$nowe
}

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["wersja"] = $true
