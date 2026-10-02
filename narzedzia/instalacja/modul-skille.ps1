# narzedzia\instalacja\modul-skille.ps1 - modul "skille": polecane skille z opieka (codzienne
# sprawdzenie nowych wersji, kopie przed podmiana, cofanie). Silnik to narzedzia\skille.ps1.
#
# Co robi:
#   - sprawdza gita (skille.ps1 pobiera zrodla czesciowym klonem) i baze polecanych skilli
#     (skille\katalog.psd1)
#   - przejecie pod opieke: skille.ps1 -Tryb wykryj - pobiera zrodla, porownuje i spisuje skille,
#     ktore juz masz (pierwszy przebieg niczego nie podmienia). Nieudane pobranie to UWAGA, nie
#     odmowa: codzienne sprawdzenie w nadzorcy sprobuje jeszcze raz
#   - wlacza modul w rejestrze - z niego nadzorca wie, ze ma codziennie sprawdzac skille
# Pojedyncze skille instaluje sie z zakladki "Skille" w oknie nadzorcy (skille.ps1 -Tryb instaluj).
# Usun: wylacza modul (koniec codziennych sprawdzen). Skille w ~\.claude\skills zostaja ZAWSZE -
#   to Twoje pliki, takze z -UsunDane. -UsunDane usuwa stan opieki ~\.claude\mr\skille\ (kopie
#   zrodel, kopie zapasowe skilli, dziennik) i wypisuje skille wgrane przez MegaRuchacza.
#
# Uzycie (umowa wyjscia - naglowek wspolne.ps1):
#   powershell -NoProfile -ExecutionPolicy Bypass -File narzedzia\instalacja\modul-skille.ps1
#     -Akcja Instaluj|Usun|Stan [-KatalogDomowy <kat>] [-Zrodlo <repo>] [-Proba] [-UsunDane]
#     [-KatalogSkilli <plik.psd1>]   inna baza polecanych skilli (testy, proba negatywna)

[CmdletBinding()]
param(
  [string]$Akcja = "",
  [string]$KatalogDomowy = $HOME,
  [string]$Zrodlo = "",
  [switch]$Proba,
  [switch]$UsunDane,
  [string]$KatalogSkilli = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "wspolne.ps1")
if (-not $Zrodlo) { $Zrodlo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$s0 = Start-Modul "skille" $Akcja ([bool]$Proba) $Zrodlo $KatalogDomowy
$Zrodlo = $s0.Zrodlo; $KatalogDomowy = $s0.KatalogDomowy

$Silnik    = Join-Path $Zrodlo "narzedzia\skille.ps1"
if (-not $KatalogSkilli) { $KatalogSkilli = Join-Path $Zrodlo "skille\katalog.psd1" }
$KatStanu  = Join-Path $KatalogDomowy ".claude\mr\skille"
$PlikStanu = Join-Path $KatStanu "stan.json"
$Znacznik  = Join-Path $KatStanu "znacznik.txt"
$Skille    = Join-Path $KatalogDomowy ".claude\skills"

function Stan-Katalogu {
  if (-not (Test-Path -LiteralPath $KatalogSkilli)) { return [pscustomobject]@{ Ok = $false; Zrodel = 0; Opis = "nie ma bazy polecanych skilli $KatalogSkilli" } }
  try {
    $k = Import-PowerShellDataFile -LiteralPath $KatalogSkilli
    $n = @($k.Zrodla).Count
    if ($n -eq 0) { return [pscustomobject]@{ Ok = $false; Zrodel = 0; Opis = "baza $KatalogSkilli nie ma zadnego zrodla" } }
    return [pscustomobject]@{ Ok = $true; Zrodel = $n; Opis = "baza polecanych skilli: $n zrodel" }
  } catch {
    return [pscustomobject]@{ Ok = $false; Zrodel = 0; Opis = "nie umiem odczytac bazy $KatalogSkilli : $($_.Exception.Message)" }
  }
}

function Czytaj-Klucze([string]$plik) {
  $k = @{}
  if (-not (Test-Path -LiteralPath $plik)) { return $k }
  foreach ($l in [System.IO.File]::ReadAllLines($plik)) { $m = [regex]::Match($l, '^\s*([^:]+):\s*(.*)$'); if ($m.Success) { $k[$m.Groups[1].Value.Trim()] = $m.Groups[2].Value.Trim() } }
  return $k
}

# Skille, ktore wgral MegaRuchacz (jak = "zainstalowany"), w odroznieniu od przejetych kopii uzytkownika.
function Wgrane-Przez-Nas {
  if (-not (Test-Path -LiteralPath $PlikStanu)) { return @() }
  try { $s = [System.IO.File]::ReadAllText($PlikStanu).TrimStart([char]0xFEFF) | ConvertFrom-Json }
  catch { Ostrzezenie "nie umiem odczytac $PlikStanu ($($_.Exception.Message)) - nie wiem, ktore skille wgral MegaRuchacz"; return @() }
  $lista = @()
  foreach ($p in @($s.skille.PSObject.Properties)) {
    foreach ($c in @($p.Value.cele.PSObject.Properties)) { if ($c.Value.jak -eq "zainstalowany") { $lista += "$($p.Name) ($($c.Name))" } }
  }
  return $lista
}

function Zbierz-Stan($rej, [hashtable]$prog) {
  $zainst = [bool]$rej.moduly.skille
  $kat = Stan-Katalogu
  $z = Czytaj-Klucze $Znacznik
  if ($zainst) {
    if (-not $prog["git"]) { Problem "nie ma gita - skille nie pobiora nowych wersji" }
    if (-not $kat.Ok) { Problem $kat.Opis }
    if ($z["wynik"] -eq "blad") { Problem "ostatnie sprawdzenie skilli ($($z['dzien'])) skonczylo sie bledem: $($z['powod'])" }
  }
  $dziala = $zainst -and ($script:MR.problemy.Count -eq 0)
  return [pscustomobject]@{ Zainstalowany = $zainst; Dziala = $dziala; Szczegoly = [ordered]@{
    baza = $kat.Opis; stan_opieki = (Test-Path -LiteralPath $PlikStanu)
    ostatnie_sprawdzenie = [ordered]@{ dzien = $z["dzien"]; wynik = $z["wynik"]; powod = $z["powod"] } } }
}

try {
  if ($Akcja -eq "Stan") {
    $prog = Sprawdz-Programy @("git")
    $rej = Czytaj-Instalacje $KatalogDomowy
    if ($rej.blad) { Problem "rejestr modulow: $($rej.blad)" }
    $st = Zbierz-Stan $rej $prog
    $kom = if ($st.Dziala) { "skille dzialaja" } elseif ($st.Zainstalowany) { "skille wlaczone, ale: " + (@($script:MR.problemy) -join "; ") } else { "skille nie sa wlaczone" }
    Zakoncz (-not $rej.blad) $kom @{ zainstalowany = $st.Zainstalowany; dziala = $st.Dziala; szczegoly = $st.Szczegoly; rejestr = (Rejestr-Do-Wyniku $rej $KatalogDomowy) }
  }

  $rej = Rejestr-Do-Zmian $KatalogDomowy

  if ($Akcja -eq "Instaluj") {
    $prog = Sprawdz-Programy @("git")
    Odmowa-Brak-Programow
    $kat = Stan-Katalogu
    if (-not $kat.Ok) { Zakoncz $false $kat.Opis }
    Krok $kat.Opis
    if (-not (Test-Path -LiteralPath $Skille)) {
      if ($Proba) { Plan "zalozylbym katalog skilli $Skille" }
      else { New-Item -ItemType Directory -Force -Path $Skille | Out-Null; Krok "zalozony katalog skilli $Skille" }
    }
    if ($Proba) {
      Plan "przejecie pod opieke: skille.ps1 -Tryb wykryj (pobiera zrodla z GitHuba, spisuje skille, ktore juz masz; niczego nie podmienia)"
    } else {
      Krok "przejmuje skille pod opieke - pobieram zrodla polecanych skilli (pierwszy raz to kilka minut)"
      $w = Uruchom-Skrypt $Silnik @("-Tryb", "wykryj", "-KatalogDomowy", $KatalogDomowy, "-Katalog", $KatalogSkilli, "-Przerwy", "3,10") 1800
      if ($w.Kod -eq 2) { Zakoncz $false "skille.ps1 odrzucil wywolanie: $(Sedno $w.Tekst)" }
      elseif ($w.Kod -eq 3) { Ostrzezenie "inne sprawdzenie skilli wlasnie pracuje - przejecie dokonczy ono albo codzienne sprawdzenie w nadzorcy" }
      elseif ($w.Kod -ne 0) { Ostrzezenie "przejecie pod opieke nie udalo sie w calosci: $(Sedno $w.Tekst) - codzienne sprawdzenie sprobuje jeszcze raz" }
      else { Krok "skille przejete pod opieke - stan: $PlikStanu" }
    }
    Zapisz-Modul "skille" $true $KatalogDomowy
    $ok = Po-Zmianie-Rejestru $Zrodlo $KatalogDomowy
    Krok "codzienne sprawdzenie nowych wersji robi nadzorca przy zegarze; pojedyncze skille instalujesz z jego zakladki 'Skille'"
    if ($Proba) { Zakoncz $true "proba: skille dalyby sie zainstalowac" }
    $rej2 = Czytaj-Instalacje $KatalogDomowy
    $st = Zbierz-Stan $rej2 $prog
    $kom = if ($st.Dziala) { "skille zainstalowane" } else { "skille zainstalowane; do sprawdzenia: " + (@($script:MR.problemy) -join "; ") }
    Zakoncz $ok $kom @{ zainstalowany = $st.Zainstalowany; dziala = $st.Dziala; szczegoly = $st.Szczegoly; rejestr = (Rejestr-Do-Wyniku $rej2 $KatalogDomowy) }
  }

  # ---------------------------------------------------------------- Usun
  $wgrane = @(Wgrane-Przez-Nas)
  Zapisz-Modul "skille" $false $KatalogDomowy
  $ok = Po-Zmianie-Rejestru $Zrodlo $KatalogDomowy
  Krok "skille w $Skille zostaja - to Twoje pliki (codzienne sprawdzenie nowych wersji wylaczone)"
  if ($wgrane.Count -gt 0) { Krok "wgrane przez MegaRuchacza (usuniesz je recznie, jesli niepotrzebne): $($wgrane -join ', ')" }
  if ($UsunDane) {
    if (-not (Usun-Katalog-Danych $KatStanu "stan opieki nad skillami (kopie zrodel, kopie zapasowe skilli, dziennik)")) { $ok = $false }
  } else {
    Krok "stan opieki i kopie zapasowe skilli zostaja ($KatStanu) - usunie je -UsunDane"
  }
  if ($Proba) { Zakoncz $ok "proba: skille dalyby sie usunac" }
  $kom = if ($ok) { "skille wylaczone" } else { "skille wylaczone, ale nie wszystko udalo sie zdjac - szczegoly w uwagach" }
  Zakoncz $ok $kom @{ zainstalowany = $false; dziala = $false; rejestr = (Rejestr-Do-Wyniku (Czytaj-Instalacje $KatalogDomowy) $KatalogDomowy) }
} catch {
  Zakoncz $false ("nieoczekiwany blad: " + $_.Exception.Message + " (" + $_.InvocationInfo.PositionMessage.Split("`n")[0].Trim() + ")")
}
