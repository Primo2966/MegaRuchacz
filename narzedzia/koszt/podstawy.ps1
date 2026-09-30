# narzedzia\koszt\podstawy.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz BUDOWA
# w jego naglowku). Podstawy, z ktorych korzystaja wszystkie inne moduly: linie
# raportu (Linia -> $script:Raport, wypisywane na koncu pelnego raportu), liczby
# i teksty (Liczba, Tokeny, Rozmiar, Skroc) i czytanie plikow (Czytaj, Czytaj-Cicho).
# Skad wolane: z kazdego etapu i trybu. Wczytuje go koszt-pamieci.ps1 kropka przy
# starcie - tu sa same definicje, nic sie nie liczy.

$script:Raport = @()

function Linia($tekst, $kolor = $null) {
  $script:Raport += [pscustomobject]@{ Tekst = $tekst; Kolor = $kolor }
}

# --- liczby i teksty ---------------------------------------------------------

function Liczba($n) {
  # separator tysiecy na sztywno spacja: N0 idzie za ustawieniami regionalnymi,
  # a te potrafia wstawic znak, ktory w konsoli wyglada jak smiec
  return ([long]$n).ToString("#,0", [Globalization.CultureInfo]::InvariantCulture).Replace(",", " ")
}

function Tokeny($znaki) {
  if ($znaki -eq $null) { return $null }
  return [int][math]::Ceiling([double]$znaki / $ZnakiNaToken)
}

function Rozmiar($bajty) {
  if ($bajty -lt 1024)    { return "$bajty B" }
  if ($bajty -lt 1048576) { return "$([math]::Round($bajty / 1024, 1)) KB" }
  return "$([math]::Round($bajty / 1048576, 1)) MB"
}

function Skroc($tekst, $ile) {
  if (-not $tekst) { return "" }
  if ($tekst.Length -le $ile) { return $tekst }
  return $tekst.Substring(0, $ile - 3) + "..."
}

# --- czytanie pliku ----------------------------------------------------------

function Czytaj($sciezka) {
  # UTF-8 bez rzucania bledem: zepsuty znak w cudzych zapiskach ma nie wywalic
  # raportu, bo to i tak konczy sie na policzeniu znakow
  return [System.IO.File]::ReadAllText($sciezka, (New-Object System.Text.UTF8Encoding($false)))
}

function Czytaj-Cicho($sciezka) {
  if (-not $sciezka) { return $null }
  if (-not (Test-Path -LiteralPath $sciezka)) { return $null }
  try { return Czytaj $sciezka } catch { return $null }
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["podstawy"] = $true
