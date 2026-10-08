# zasobnik\nadzorca\stan-terminy.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Przypomnienia z terminem (2026-10-05): kiedy dozor ma
# zawolac zasobnik\terminy.ps1 (Czy-Sprawdzac-Terminy) i start w tle (Ruszaj-Terminy).
# Cala reszta - samoczynne otwarcie Claude Code, okno z przyciskami, odlozenie krzyzykiem
# o 2 godziny, jedno uruchomienie na przypomnienie - siedzi w terminy.ps1 i narzedzia\terminy.js.
# Od 2026-10-08 takze wyniki przypomnien wykonanych w tle: odczyt i ocena po ludzku
# (Wyniki-Przypomnien, Ocena-Wynikow-Przypomnien) - rysuje je karta Przeglad.
# Nalezy do bazy (bez modulu w rejestrze instalacji): nadzorca jest zawsze, wiec i to.
# Skad wolane: dozor.ps1 (Dozor-Po-Danych), przeglad.ps1 (Odmaluj-Problemy, Odmaluj-Stan).
# Wczytuje go stan-nadzorcy.ps1 kropka -
# poza stalymi same definicje.

# ------------------------------------------------------------ przypomnienia z terminem

# Rytm ustalony z uzytkownikiem: przy starcie nadzorca (= zalogowanie, start komputera)
# zawsze, potem najwyzej raz na godzine i tylko 8:00-20:00 - poza tymi godzinami nikt nie
# siedzi przy komputerze, a okno Claude Code otwarte w nocy czekaloby do rana na nic.
$MINUT_MIEDZY_TERMINAMI = 60
$GODZINA_TERMINOW_OD = 8
$GODZINA_TERMINOW_DO = 20
# Kiedy dozor ostatnio wolal terminy.ps1 w TYM procesie. $null = jeszcze ani razu od
# startu nadzorcy, czyli pierwszy przebieg po zalogowaniu - ten idzie zawsze.
$script:NadzTerminyOstatnio = $null

function Skrypt-Terminow { return (Join-Path $script:NadzZrodlo "zasobnik\terminy.ps1") }

function Czy-Sprawdzac-Terminy([datetime]$teraz = [datetime]::Now) {
  $w = [pscustomobject]@{ Ruszac = $false; Powod = "" }
  $skrypt = Skrypt-Terminow
  if (-not (Test-Path -LiteralPath $skrypt)) { $w.Powod = "nie ma $skrypt"; return $w }
  if ($null -eq $script:NadzTerminyOstatnio) {
    $w.Ruszac = $true
    $w.Powod = "pierwszy przebieg od startu nadzorcy"
    return $w
  }
  if ($teraz.Hour -lt $GODZINA_TERMINOW_OD -or $teraz.Hour -ge $GODZINA_TERMINOW_DO) {
    $w.Powod = "poza godzinami $GODZINA_TERMINOW_OD-$GODZINA_TERMINOW_DO"
    return $w
  }
  $minut = ($teraz - $script:NadzTerminyOstatnio).TotalMinutes
  if ($minut -lt $MINUT_MIEDZY_TERMINAMI) {
    $w.Powod = "sprawdzone o $($script:NadzTerminyOstatnio.ToString('HH:mm')), nastepne po $MINUT_MIEDZY_TERMINAMI min"
    return $w
  }
  $w.Ruszac = $true
  $w.Powod = "ostatnio o $($script:NadzTerminyOstatnio.ToString('HH:mm'))"
  return $w
}

# Start w tle przez conhost --headless (Odpal-W-Tle) - konsoli nie widac, a okna, ktore
# terminy.ps1 otwiera (Claude Code w Windows Terminal, okno z przyciskami), sa zwyklymi
# oknami pulpitu. Slad i bledy pisze terminy.ps1 do ~\.claude\mr\przypomnienia.log.
function Ruszaj-Terminy {
  $script:NadzTerminyOstatnio = [datetime]::Now
  $skrypt = Skrypt-Terminow
  $arg = '-Zrodlo "' + $script:NadzZrodlo + '" -KatalogDomowy "' + $script:NadzDom + '"'
  if ($script:NadzProba) {
    Write-Host "[proba] NIE startuje przypomnien: powershell -File ${skrypt} ${arg}"
    return $true
  }
  $poszlo = Odpal-W-Tle $skrypt $arg
  if ($poszlo) { Notuj "wystartowalo sprawdzenie przypomnien z terminem" }
  return $poszlo
}

# ------------------------------------------------- wyniki przypomnien wykonanych w tle
# (2026-10-08) Zadania z przypomnien, ktore MegaRuchacz wykonuje sam, ida w tle, bez okna.
# Kazde zostawia ~\.claude\mr\przypomnienia-wyniki\<id>.json (pisze go terminy.ps1 /
# narzedzia\terminy.js) i obok <id>.md z pelnym raportem; kolejny przebieg tego samego id
# nadpisuje oba. Pola: id, tresc, projekt, start, koniec (ISO), wynik nic | czlowiek | blad,
# co_zrobic, powod, raport, session_id, projekt_katalog.
# Tu jest tylko odczyt (Wyniki-Przypomnien) i ocena po ludzku (Ocena-Wynikow-Przypomnien,
# czysta funkcja bez okna): "nic" to spokojna zielona linia w karcie Stan, "czlowiek" -
# zolta sprawa, "blad" - czerwona sprawa, nieczytelny plik - sprawa z nazwa pliku. Brak
# katalogu albo plikow to normalny stan (zadne przypomnienie jeszcze nie szlo w tle) - nic.
# Rysuje przeglad.ps1 (Odmaluj-Problemy, Wiersz-Przypomnien, Karta-Problemu z "Pokaż wynik").
#
# PROGI Z UZASADNIENIEM:
# - 24 h: przypomnienia ida najwyzej raz na godzine w godzinach 8-20, wiec doba obejmuje
#   caly wczorajszy dzien pracy i dzisiejszy poranek - wynik z wczoraj wieczorem widac
#   jeszcze rano po wlaczeniu komputera, a tydzien starych wynikow nie zasmieca Przegladu.
#   Ta sama doba dotyczy pliku nieczytelnego (liczona od jego zapisu na dysku).
# - 10 s: plik wyniku zapisany przed chwila moze byc wlasnie w trakcie zapisu; nieczytelny
#   mlodszy niz 10 s to jeszcze nie usterka (to samo okno co przy pliku aktualizacji
#   w okno.ps1 Sprawdz-Aktualizacje). Starszy - sprawa.
# - 60 znakow tresci w linii "nic": w oknie szerokim na 1240 px prawa kolumna karty Stan
#   miesci ok. 120 znakow, a poczatek linii ("Przypomnienie #7 zrobione samo - nic nie
#   musisz robić (dziś 08:04). ") zajmuje ok. 65 - linia zostaje jedna. Calosc w podpowiedzi.
$GODZIN_WYNIKU_PRZYPOMNIENIA = 24
$SEKUND_ZAPISU_WYNIKU_PRZYPOMNIENIA = 10
$ZNAKOW_TRESCI_PRZYPOMNIENIA = 60
$WYNIKI_PRZYPOMNIEN = @("nic", "czlowiek", "blad")

function Katalog-Wynikow-Przypomnien { return (Join-Path $script:NadzDom ".claude\mr\przypomnienia-wyniki") }

function Data-Wyniku-Przypomnienia($v) {
  if ($v -is [datetime]) { return $v }
  return (Data-Lub-Nic "$v")
}

# Odczyt katalogu. Zawsze obiekt: Katalog, Blad (katalogu nie da sie przejrzec), Wyniki -
# po jednym na plik .json: Plik, PlikMd, Nazwa, Id, Tresc, Projekt, ProjektKatalog, Start,
# Koniec, Kiedy (koniec, start albo zapis pliku), Zapis, Wynik, CoZrobic, Powod, Raport,
# Blad (nieczytelny plik albo nieznany wynik - z powodem), Nieczytelny (JSON sie nie odczytal).
function Wyniki-Przypomnien {
  $kat = Katalog-Wynikow-Przypomnien
  $w = [pscustomobject]@{ Katalog = $kat; Blad = ""; Wyniki = @() }
  if (-not (Test-Path -LiteralPath $kat -PathType Container)) { return $w }
  $pliki = @()
  try { $pliki = @(Get-ChildItem -LiteralPath $kat -Filter "*.json" -File -ErrorAction Stop) }
  catch { $w.Blad = "nie da się przejrzeć katalogu ${kat}: $($_.Exception.Message)"; return $w }
  foreach ($fi in $pliki) {
    $baza = [System.IO.Path]::GetFileNameWithoutExtension($fi.Name)
    $r = [pscustomobject]@{ Plik = $fi.FullName; PlikMd = (Join-Path $kat "$baza.md"); Nazwa = $fi.Name; Id = $baza
      Tresc = ""; Projekt = ""; ProjektKatalog = ""; Start = $null; Koniec = $null; Kiedy = $fi.LastWriteTime
      Zapis = $fi.LastWriteTime; Wynik = ""; CoZrobic = ""; Powod = ""; Raport = ""; Blad = ""; Nieczytelny = $false }
    $j = $null
    try {
      $txt = [System.IO.File]::ReadAllText($fi.FullName, [System.Text.Encoding]::UTF8)
      if (-not "$txt".Trim()) { throw "plik jest pusty" }
      $j = $txt | ConvertFrom-Json
      if ($null -eq $j) { throw "w pliku nie ma żadnych danych" }
    } catch {
      $r.Blad = "nie da się odczytać $($fi.FullName): $($_.Exception.Message)"
      $r.Nieczytelny = $true
      $w.Wyniki += $r
      continue
    }
    $n = 0
    if ([int]::TryParse("$($j.id)", [ref]$n)) { $r.Id = "$n" }
    $r.Tresc = ("$($j.tresc)" -replace '\s+', ' ').Trim()
    $r.Projekt = "$($j.projekt)".Trim()
    $r.ProjektKatalog = "$($j.projekt_katalog)".Trim()
    $r.Start = Data-Wyniku-Przypomnienia $j.start
    $r.Koniec = Data-Wyniku-Przypomnienia $j.koniec
    if ($r.Koniec) { $r.Kiedy = $r.Koniec } elseif ($r.Start) { $r.Kiedy = $r.Start }
    $r.Wynik = "$($j.wynik)".Trim().ToLower()
    $r.CoZrobic = ("$($j.co_zrobic)" -replace '\s+', ' ').Trim()
    $r.Powod = ("$($j.powod)" -replace '\s+', ' ').Trim()
    $r.Raport = "$($j.raport)".Trim()
    if ($WYNIKI_PRZYPOMNIEN -notcontains $r.Wynik) { $r.Blad = "w $($fi.FullName) stoi nieznany wynik '$($r.Wynik)'" }
    $w.Wyniki += $r
  }
  return $w
}

# Tresc przypomnienia skrocona naturalnie: na granicy slowa, z wielokropkiem - nigdy
# w polowie wyrazu. Krotsza niz limit zostaje cala.
function Skroc-Tresc-Przypomnienia([string]$t, [int]$max) {
  $t = ($t -replace '\s+', ' ').Trim()
  if ($t.Length -le $max) { return $t }
  $c = $t.Substring(0, $max)
  $i = $c.LastIndexOf(' ')
  if ($i -ge [int]($max / 2)) { $c = $c.Substring(0, $i) }
  return ($c.TrimEnd(' ', ',', ';', ':', '-', '.') + [string][char]0x2026)
}

# Ocena po ludzku. $wp = Wyniki-Przypomnien, $teraz - chwila oceny. Zwraca:
#   Linie - spokojne linie wynikow "nic" (Tekst, Podpowiedz, Plik = <id>.md, Kiedy), od najnowszej;
#   Problemy - sprawy na Przeglad (Waga, Tytul, Porada, Pelne, Plik = <id>.md albo "",
#     Zrodlo = "przypomnienia"), od najnowszej.
function Ocena-Wynikow-Przypomnien($wp, $teraz) {
  $o = [pscustomobject]@{ Etykieta = "Przypomnienia w tle"; Linie = @(); Problemy = @() }
  if (-not $wp) { return $o }
  $pokaz = "Pełny raport otwiera `„Pokaż wynik`”."
  if ($wp.Blad) {
    $o.Problemy += [pscustomobject]@{ Waga = "uwaga"; Tytul = "Nie umiem przejrzeć wyników przypomnień wykonanych w tle"
      Porada = "Katalogu, w którym przypomnienia zostawiają swoje wyniki, nie da się odczytać - nie wiem, czy któreś czeka na Ciebie."
      Pelne = $wp.Blad; Plik = ""; Zrodlo = "przypomnienia" }
  }
  $swieze = @(@($wp.Wyniki) | Where-Object { $_ -and $_.Kiedy -and (($teraz - $_.Kiedy).TotalHours -lt $GODZIN_WYNIKU_PRZYPOMNIENIA) } |
    Sort-Object -Property Kiedy -Descending)
  foreach ($r in $swieze) {
    $kiedy = Kiedy-Krotko $r.Kiedy
    $md = ""
    if (Test-Path -LiteralPath $r.PlikMd -PathType Leaf) { $md = $r.PlikMd }
    $co = $r.Tresc
    if ($r.Projekt -and $co) { $co = "$($r.Projekt): $co" } elseif ($r.Projekt) { $co = $r.Projekt }
    $opis = "$(if ($co) { $co } else { '(przypomnienie bez treści)' })"
    if ($r.Blad) {
      if ($r.Nieczytelny -and (($teraz - $r.Zapis).TotalSeconds -lt $SEKUND_ZAPISU_WYNIKU_PRZYPOMNIENIA)) { continue }
      $o.Problemy += [pscustomobject]@{ Waga = "uwaga"; Tytul = "Nie umiem odczytać wyniku przypomnienia z pliku $($r.Nazwa)"
        Porada = ("Przypomnienie wykonane w tle ($kiedy) zostawiło wynik, którego nie da się odczytać, więc nie wiem, czy coś czeka na Ciebie. " +
          $(if ($md) { $pokaz } else { "Pełnego raportu obok też nie ma." }))
        Pelne = $r.Blad; Plik = $md; Zrodlo = "przypomnienia" }
      continue
    }
    switch ($r.Wynik) {
      "nic" {
        $o.Linie += [pscustomobject]@{
          Tekst = "Przypomnienie #$($r.Id) zrobione samo - nic nie musisz robić ($kiedy). $(Skroc-Tresc-Przypomnienia $opis $ZNAKOW_TRESCI_PRZYPOMNIENIA)"
          Podpowiedz = (@("Przypomnienie #$($r.Id) ($kiedy)", $opis, $(if ($r.Raport) { "Wynik: $($r.Raport)" }),
            $(if (-not $md) { "Pełnego raportu nie ma - brakuje pliku $([System.IO.Path]::GetFileName($r.PlikMd))." })) | Where-Object { $_ }) -join "`r`n"
          Plik = $md; Kiedy = $r.Kiedy }
      }
      "czlowiek" {
        $cz = $r.CoZrobic
        if (-not $cz) { $cz = "nie zapisało, co masz zrobić - zajrzyj do pełnego raportu" }
        $o.Problemy += [pscustomobject]@{ Waga = "uwaga"; Tytul = "Przypomnienie #$($r.Id) czeka na Ciebie: $($cz.TrimEnd('.', ' '))"
          Porada = "Przypomnienie ($kiedy): $opis. $(if ($md) { $pokaz } else { 'Pełnego raportu nie ma - brakuje pliku ' + [System.IO.Path]::GetFileName($r.PlikMd) + '.' })"
          Pelne = "plik: $($r.Plik)$(if ($r.Raport) { '; ' + $r.Raport })"; Plik = $md; Zrodlo = "przypomnienia" }
      }
      "blad" {
        $pw = $r.Powod
        if (-not $pw) { $pw = "nie podało powodu - to samo w sobie jest usterką" }
        $o.Problemy += [pscustomobject]@{ Waga = "pilne"; Tytul = "Przypomnienie #$($r.Id) nie wykonało się: $($pw.TrimEnd('.', ' '))"
          Porada = "Przypomnienie ($kiedy): $opis. $(if ($md) { $pokaz } else { 'Pełnego raportu nie ma - brakuje pliku ' + [System.IO.Path]::GetFileName($r.PlikMd) + '.' })"
          Pelne = "plik: $($r.Plik)$(if ($r.Raport) { '; ' + $r.Raport })"; Plik = $md; Zrodlo = "przypomnienia" }
      }
    }
  }
  return $o
}

function Ocena-Wynikow-Przypomnien-Teraz { return (Ocena-Wynikow-Przypomnien (Wyniki-Przypomnien) ([datetime]::Now)) }

# Te same linie "nic" jako tekst do wydruku -Raport (i do testow bez pulpitu).
function Linie-Wynikow-Przypomnien($o) {
  $l = @()
  if (-not $o) { return ,$l }
  foreach ($x in @($o.Linie)) {
    $l += "  $($o.Etykieta): $([string][char]0x2713) $($x.Tekst)  (zielony napis)  [Pokaż wynik: $(if ($x.Plik) { $x.Plik } else { 'brak pliku z raportem' })]"
  }
  return ,$l
}

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["terminy"] = $true
