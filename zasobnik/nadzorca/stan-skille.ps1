# zasobnik\nadzorca\stan-skille.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Polecane skille (P18) - wszystko przez
# narzedzia\skille.ps1: codzienne sprawdzenie w tle (Czy-Sprawdzac-Skille,
# Ruszaj-Skille, Odpal-Skille), operacje z przyciskow (Operacja-Na-Skillach), stan
# dla zakladki (Stan-Skilli) i sprawy dla Przegladu z pliku znacznika
# (Problemy-Skilli).
# Skad wolane: dozor.ps1, krok "skille" w w-tle.ps1, skille.ps1 (zakladka),
# przeglad-tresc.ps1 (Problemy-Skilli). Wczytuje go stan-nadzorcy.ps1 kropka -
# poza stalymi same definicje.

# ------------------------------------------------------------ polecane skille (P18)

# Skille ma narzedzia\skille.ps1 - baza (skille\katalog.psd1), wykrywanie, instalacja,
# aktualizacja i cofniecie siedza TAM. Tutaj sa tylko: decyzja dozoru "czy dzis juz
# sprawdzone" (sam plik znacznika, bez wolania skryptu - dozor chodzi co 15 minut),
# start w tle bez okna i odczyt stanu dla zakladki "Skille".

# Najczesciej, jak dozor probuje ruszyc sprawdzenie, gdy znacznika z dzis wciaz nie ma
# (np. skrypt padl, zanim go zapisal). Dwie godziny: dosc, zeby nie odpalac procesu
# co kwadrans na zepsutym skrypcie, i dosc malo, zeby chwilowy brak sieci rano nie
# przepadl na caly dzien, gdy skrypt w ogole nie wystartowal.
$MINUT_MIEDZY_STARTAMI_SKILLI = 120
# Po ilu dniach bez udanego sprawdzenia skille staja sie sprawa na Przegladzie. Dwa,
# bo rytm to raz na dobe: jeden opuszczony dzien (komputer wylaczony) to jeszcze nie
# usterka, drugi z rzedu przy dzialajacym nadzorcy - juz tak.
$DNI_BEZ_SPRAWDZENIA_SKILLI = 2
$script:NadzSkilleOdpalone = $null

function Skrypt-Skilli { return (Join-Path $script:NadzZrodlo "narzedzia\skille.ps1") }
function Katalog-Stanu-Skilli { return (Join-Path $script:NadzDom ".claude\mr\skille") }
function Znacznik-Skilli { return (Czytaj-Klucze (Join-Path (Katalog-Stanu-Skilli) "znacznik.txt")) }
function Operacja-Skilli { return (Czytaj-Klucze (Join-Path (Katalog-Stanu-Skilli) "operacja.txt")) }

function Proces-Zyje($pidTekst) {
  $n = 0
  if (-not [int]::TryParse("$pidTekst", [ref]$n)) { return $false }
  return [bool](Get-Process -Id $n -ErrorAction SilentlyContinue)
}

function Czy-Sprawdzac-Skille {
  $w = [pscustomobject]@{ Ruszac = $false; Powod = "" }
  $skrypt = Skrypt-Skilli
  if (-not (Test-Path -LiteralPath $skrypt)) { $w.Powod = "nie ma $skrypt"; return $w }
  $dzis = Get-Date -Format 'yyyy-MM-dd'
  $zn = Znacznik-Skilli
  if ($zn["dzien"] -eq $dzis) {
    $w.Powod = "sprawdzone juz dzis ($($zn['start']), wynik $($zn['wynik']))"
    return $w
  }
  $op = Operacja-Skilli
  if (($op["wynik"] -eq "pracuje") -and (Proces-Zyje $op["pid"])) {
    $w.Powod = "wlasnie trwa inna operacja na skillach ($($op['tryb']) od $($op['start']))"
    return $w
  }
  if ($script:NadzSkilleOdpalone -and (([datetime]::Now - $script:NadzSkilleOdpalone).TotalMinutes -lt $MINUT_MIEDZY_STARTAMI_SKILLI)) {
    $w.Powod = "odpalone o $($script:NadzSkilleOdpalone.ToString('HH:mm')), a znacznika z dzis wciaz nie ma - nastepna proba po $MINUT_MIEDZY_STARTAMI_SKILLI min"
    return $w
  }
  $w.Ruszac = $true
  $w.Powod = "ostatnie sprawdzenie: $(if ($zn['dzien']) { $zn['dzien'] } else { 'nigdy' }), dzis jest $dzis"
  return $w
}

# Start w tle przez conhost --headless (Odpal-W-Tle) - ta sama droga, co cykl wiedzy,
# sprawdzona rejestratorem okien (P10: zero okien).
function Odpal-Skille([string]$argumenty) {
  $skrypt = Skrypt-Skilli
  $calosc = $argumenty + ' -KatalogDomowy "' + $script:NadzDom + '"'
  if ($script:NadzProba) {
    Write-Host "[proba] NIE startuje skilli: powershell -File ${skrypt} ${calosc}"
    return $true
  }
  return (Odpal-W-Tle $skrypt $calosc)
}

function Ruszaj-Skille {
  $script:NadzSkilleOdpalone = [datetime]::Now
  $poszlo = Odpal-Skille "-Tryb codziennie"
  if ($poszlo) { Notuj "wystartowalo codzienne sprawdzenie skilli" }
  return $poszlo
}

# Operacja z przycisku w zakladce: instaluj / aktualizuj / cofnij, jeden skill albo
# wszystkie. Oddaje od razu - wynik okno odczytuje z operacja.txt zegarem.
function Operacja-Na-Skillach([string]$tryb, [string]$skill, [bool]$wymus) {
  if ($script:NadzProba) { return "tryb próbny - przyciski skilli niczego nie uruchamiają" }
  $a = "-Tryb $tryb"
  if ($skill) { $a += ' -Skill "' + $skill + '"' }
  if ($wymus) { $a += " -Wymus" }
  if (Odpal-Skille $a) {
    Notuj "skille: z okna ruszyla operacja $a"
    return ""
  }
  return "nie udało się uruchomić narzedzia\skille.ps1 w tle - szczegóły w dzienniku nadzorcy"
}

# Pelny stan dla zakladki: skille.ps1 -Tryb stan -Json (bez sieci, sekunda-dwie).
# Nieudane wywolanie albo smiec zamiast JSON-u to Powod, ktory okno pokazuje
# zamiast pustej listy - pusta lista udawalaby "nic nie masz".
function Stan-Skilli {
  $w = [pscustomobject]@{ Dane = $null; Powod = "" }
  $skrypt = Skrypt-Skilli
  $r = Wolaj-Skrypt $skrypt @("-Tryb", "stan", "-Json", "-KatalogDomowy", ('"' + $script:NadzDom + '"')) 90
  if (-not $r.ok) { $w.Powod = $r.powod; return $w }
  $t = "$($r.tekst)".Trim()
  if (-not $t) {
    $w.Powod = "skille.ps1 nic nie wypisał (kod $($r.kod))$(if ($r.powod) { ' - ' + $r.powod })"
    return $w
  }
  $j = $null
  try { $j = $t | ConvertFrom-Json }
  catch {
    Zanotuj-Wywrotke "odczyt stanu skilli" $_
    $w.Powod = "skille.ps1 oddał coś, co nie jest JSON-em: $($_.Exception.Message)"
    return $w
  }
  if ($j.powod) { $w.Powod = "$($j.powod)"; return $w }
  if ($null -eq $j.zrodla) { $w.Powod = "w odpowiedzi skille.ps1 nie ma listy źródeł (kod $($r.kod))"; return $w }
  $w.Dane = $j
  return $w
}

# Sprawy dla Przegladu - TYLKO z pliku znacznika (dozor i okno czytaja to czesto).
# Zwraca liste obiektow Waga/Tytul/Porada/Pelne; pusta = nic sie nie pali.
function Problemy-Skilli {
  $lista = @()
  $kat = Katalog-Stanu-Skilli
  if (-not (Test-Path -LiteralPath (Join-Path $kat "stan.json"))) { return ,$lista }
  $zn = Znacznik-Skilli
  $wynik = "$($zn['wynik'])"
  if ($wynik -eq "blad") {
    $lista += [pscustomobject]@{ Waga = "uwaga"; Tytul = "Skille: nie udało się sprawdzić nowych wersji"
      Porada = "Codzienne sprawdzenie ($($zn['dzien'])) trafiło na błąd. Pobranie ze źródła jest ponawiane 5 razy, więc chwilowa czkawka sieci tu nie trafia - to raczej dłuższy brak internetu albo niedostępne źródło. Grupa z czerwonym paskiem w zakładce Skille pokazuje szczegóły. Skille, które masz, działają dalej."
      Pelne = "$($zn['powod'])" }
  } elseif ($wynik -eq "pracuje") {
    $od = Data-Lub-Nic $zn["start"]
    if ($od -and (([datetime]::Now - $od).TotalMinutes -gt 60) -and -not (Proces-Zyje $zn["pid"])) {
      $lista += [pscustomobject]@{ Waga = "uwaga"; Tytul = "Skille: sprawdzenie urwało się w połowie"
        Porada = "Sprawdzenie ruszyło $($zn['start']) i nie zapisało wyniku. Kliknij w zakładce Skille `„Sprawdź teraz`”, żeby spróbować jeszcze raz."
        Pelne = "znacznik: $($zn['start']), proces $($zn['pid']) już nie żyje" }
    }
  }
  $dzien = Data-Lub-Nic $zn["dzien"]
  if ($null -eq $dzien) {
    # Stan jest (ktos sprawdzal recznie), a codziennego przebiegu nie bylo ani razu.
    # Alarm dopiero po dobie od powstania stanu - w pierwszym kwadransie po starcie
    # dozor wlasnie go odpala i alarm bylby falszywy.
    $powstal = (Get-Item -LiteralPath (Join-Path $kat "stan.json")).CreationTime
    if (([datetime]::Now - $powstal).TotalHours -ge 24) {
      $lista += [pscustomobject]@{ Waga = "uwaga"; Tytul = "Skille jeszcze ani razu nie były sprawdzane same"
        Porada = "Codzienne sprawdzenie nowych wersji skilli nie ruszyło od $($powstal.ToString('yyyy-MM-dd')). Otwórz zakładkę Skille i kliknij `„Sprawdź teraz`”."
        Pelne = "brak pliku $(Join-Path $kat 'znacznik.txt')" }
    }
  } elseif (([datetime]::Today - $dzien.Date).TotalDays -ge $DNI_BEZ_SPRAWDZENIA_SKILLI) {
    $kiedy = $dzien.ToString('yyyy-MM-dd')
    $lista += [pscustomobject]@{ Waga = "uwaga"; Tytul = "Skille nie były sprawdzane od $kiedy"
      Porada = "Sprawdzenie nowych wersji skilli ma iść samo raz dziennie, a nie szło co najmniej $DNI_BEZ_SPRAWDZENIA_SKILLI dni. Otwórz zakładkę Skille i kliknij `„Sprawdź teraz`”."
      Pelne = "znacznik: $(Join-Path $kat 'znacznik.txt')" }
  }
  return ,$lista
}

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["skille"] = $true
