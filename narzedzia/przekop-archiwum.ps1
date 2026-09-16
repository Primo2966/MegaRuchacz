# Jednorazowe przekopanie CALEGO archiwum rozmow - wiedza wylowiona z powtorzen.
#
# Codzienne wylawianie (narzedzia\wyciagnij-fakty.ps1) widzi tylko wczoraj. Wszystko, co
# uzytkownik tlumaczyl przez wczesniejsze miesiace, lezy w archiwum nieprzeczytane, a
# przepuszczenie kilkudziesieciu tysiecy fragmentow przez model kosztowaloby dziesiatki dolarow.
#
# Dlatego powtorzenia znajduje sama baza wektorowa, bez modelu: fragmenty znaczace to samo leza
# blisko siebie, nawet gdy padly inne slowa i inny jezyk. Skupisko takich fragmentow pochodzacych
# z WIELU ROZNYCH SESJI znaczy dokladnie jedno - uzytkownik tlumaczyl to samo w oknie po oknie.
# Model czyta wtedy po jednym przedstawicielu ze skupiska, czyli kilkadziesiat urywkow zamiast
# calego archiwum.
#
# Fakty laduja w POCZEKALNI: %USERPROFILE%\.claude\wiedza\kandydaci.md
# Do obowiazujacej wiedzy (~\.claude\CLAUDE.md) nie trafia nic samo - czlowiek zatwierdza recznie.
# Baza jest otwierana tylko do odczytu.
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File narzedzia\przekop-archiwum.ps1 -Proba
#   ... -Zrodlo <sciezka>         katalog glowny repozytorium (domyslnie: katalog nad narzedzia\)
#   ... -Proba                    DARMOWY podglad: pokazuje znalezione skupiska i ich sile,
#                                 NIE wola modelu i niczego nie zapisuje
#   ... -Ile <N>                  ile najsilniejszych skupisk dostaje model (domyslnie 60)
#   ... -PrzesunZnacznik          po udanym przebiegu przesuwa znacznik codziennego wylawiania
#                                 na koniec archiwum - patrz ostrzezenie nizej. Domyslnie WYLACZONE.
#   ... -KatalogDomowy <sciezka>  inny katalog zamiast ~\.claude (do testow; ustawia LORE_HOME)

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Proba,
  [int]$Ile = 60,
  [switch]$PrzesunZnacznik,
  [string]$KatalogDomowy
)

$script:Uv   = $null
$script:Lore = $null
$script:Dom  = $null

# ---------------------------------------------------------------- wypisywanie

function Naglowek($tekst) {
  Write-Host ""
  Write-Host $tekst -ForegroundColor Cyan
  Write-Host ("-" * $tekst.Length) -ForegroundColor DarkGray
}

function Krok($tekst)        { Write-Host "  $tekst" }
function Plan($tekst)        { Write-Host "  [PROBA] $tekst" -ForegroundColor DarkGray }
function Ostrzezenie($tekst) { Write-Host "UWAGA  $tekst" -ForegroundColor Yellow }
function Blad($tekst)        { Write-Host "BLAD  $tekst" -ForegroundColor Red }

# ---------------------------------------------------------------- warunki wstepne

function Znajdz-Uv {
  # najpierw PATH, a jak nie ma - sciezki, pod ktore uv laduje z WinGeta
  $cmd = Get-Command uv -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return $cmd.Source }
  $link = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\uv.exe"
  if (Test-Path $link) { return (Resolve-Path $link).Path }
  $wzorzec = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\astral-sh.uv_*\uv.exe"
  $trafienie = Get-ChildItem $wzorzec -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($trafienie) { return $trafienie.FullName }
  return $null
}

function Sprawdz-Warunki {
  $sciezka = Resolve-Path $Zrodlo -ErrorAction SilentlyContinue
  if (-not $sciezka) {
    Blad "nie ma takiego katalogu: $Zrodlo"
    exit 1
  }
  $script:Lore = Join-Path $sciezka.Path "lore"
  if (-not (Test-Path (Join-Path $script:Lore "pyproject.toml"))) {
    Blad "nie widze $($script:Lore)\pyproject.toml - wskaz repozytorium przez  -Zrodlo <sciezka>"
    exit 1
  }
  $script:Uv = Znajdz-Uv
  if (-not $script:Uv) {
    Blad "nie znalazlem uv (menedzer srodowisk Pythona). Zainstaluj:  winget install --id astral-sh.uv"
    exit 1
  }
  $script:Dom = Join-Path $env:USERPROFILE ".claude"
  if ($KatalogDomowy) {
    # LORE_HOME podmienia caly katalog .claude - na tym stoi izolacja testow od prawdziwej wiedzy
    New-Item -ItemType Directory -Path $KatalogDomowy -Force | Out-Null
    $script:Dom = (Resolve-Path $KatalogDomowy).Path
    $env:LORE_HOME = $script:Dom
    Ostrzezenie "katalog domowy podmieniony na $($script:Dom) - prawdziwa wiedza nie jest ruszana"
  }
  $baza = Join-Path $script:Dom "lore.db"
  if (-not (Test-Path $baza)) {
    Blad "nie ma bazy $baza - najpierw zaindeksuj rozmowy (narzedzia\instaluj-lore.ps1)"
    exit 1
  }
}

# ---------------------------------------------------------------- znacznik

function Powiedz-O-Znaczniku {
  # Przesuniecie znacznika to decyzja o POMINIECIU materialu, a nie szczegol techniczny.
  # Dlatego jest osobnym przelacznikiem i dlatego zawsze pada tu zdanie, co to znaczy.
  $znacznik = Join-Path $script:Dom "wiedza\.ostatnie-wyciaganie"
  if ($PrzesunZnacznik) {
    Ostrzezenie "-PrzesunZnacznik JEST WLACZONY"
    Krok "po udanym przebiegu znacznik ($znacznik) przeskoczy na koniec archiwum,"
    Krok "czyli codzienne wylawianie NIGDY juz nie przeczyta niczego sprzed tej chwili."
    Krok "Zostanie tylko to, co ten przebieg wylowil ze skupisk - reszta materialu przepada."
  } else {
    Krok "znacznik codziennego wylawiania zostaje nietkniety (tak jest domyslnie):"
    Krok "ten sam material przejdzie jeszcze raz przez codzienne zadanie. Zeby to pominac,"
    Krok "uruchom ponownie z  -PrzesunZnacznik"
  }
}

# ---------------------------------------------------------------- przekop

function Przekop {
  Naglowek "Przekopywanie archiwum rozmow"
  if ($Proba) {
    Ostrzezenie "TRYB PROBNY - tylko szuka skupisk; model nie jest wolany, wiec nic nie kosztuje"
  } else {
    Krok "model dostanie najwyzej $Ile urywkow - po jednym z kazdego najsilniejszego skupiska"
  }
  Powiedz-O-Znaczniku
  Write-Host ""

  $argumenty = @("--directory", $script:Lore, "run", "python", "-m", "lore.mining", "--ile", "$Ile")
  if ($Proba)           { $argumenty += "--proba" }
  if ($PrzesunZnacznik) { $argumenty += "--przesun-znacznik" }
  & $script:Uv @argumenty
  $kod = $LASTEXITCODE
  if ($kod -ne 0) {
    Blad "przekopywanie archiwum nie powiodlo sie (kod $kod) - szczegoly w liniach powyzej"
    exit $kod
  }
  if (-not $Proba) {
    Write-Host ""
    Krok "propozycje czekaja w: $(Join-Path $script:Dom 'wiedza\kandydaci.md')"
    Krok "nic nie weszlo do obowiazujacej wiedzy - to robi czlowiek albo narzedzia\aktualizuj-wiedze.ps1"
  }
  exit 0
}

# ---------------------------------------------------------------- przebieg

if ($Ile -lt 1) { $Ile = 1 }

Sprawdz-Warunki
Przekop
