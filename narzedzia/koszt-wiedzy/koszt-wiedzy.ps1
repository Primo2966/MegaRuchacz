# Strona "Koszt tworzenia wiedzy z rozmow" - ile tokenow kosztuje codzienne wylawianie wiedzy
# z rozmow, dzien po dniu, w dwoch wersjach obok siebie:
#   - tansza (pamiec osobista): poranny automat lore\lore\facts.py, czyta tylko poprawki,
#     powtorzenia i "zapamietaj",
#   - pelna (wiedza firmy, jfwiedza): dzienny krok narzedzia\wiedza-firmy-klient\klient.py,
#     czyta caly dzien rozmow; do czasu pierwszych przebiegow - proba z 14.10,
# kazda w tokenach i w procentach CALEGO dziennego zuzycia Claude Code na tym komputerze.
# Wynik: jeden plik HTML bez niczego z sieci, <dom>\.claude\mr\koszt-wiedzy.html.
#
# Uzycie:
#   powershell -NoProfile -ExecutionPolicy Bypass -File narzedzia\koszt-wiedzy\koszt-wiedzy.ps1 [-Otworz]
#     -Otworz               po zapisie otwiera strone w domyslnej przegladarce (pozycja
#                           "Koszt tworzenia wiedzy" w menu zasobnika)
#     -KatalogDomowy <kat>  podmiana katalogu domowego (testy)
#     -Zrodlo <kat>         katalog repozytorium (domyslnie dwa poziomy nad tym skryptem)
#     -Wyjscie <plik>       inna sciezka strony (testy)
#     -Dzis <RRRR-MM-DD>    inny "dzis" (testy)
# Kto wola: narzedzia\cykl-dzienny.ps1 po porannym czytaniu, menu zasobnika (zasobnik\nadzorca.ps1).
#
# Kod wyjscia: 0 = strona zapisana i wszystko policzone, 2 = strona zapisana, ale czegos nie
# udalo sie policzyc (to stoi na gorze strony i w wydruku, linie "UWAGA"), 1 = strony nie dalo
# sie zbudowac (zapisana strona bledu z powodem, o ile w ogole dalo sie pisac).
#
# Cale zuzycie dnia liczy sie z transkryptow (setki MB), wiec dni zakonczone ida do pliku
# podrecznego <dom>\.claude\mr\koszt-wiedzy-dni.tsv i nie licza sie drugi raz.
#
# BUDOWA. Ten plik: parametry, sciezki, przebieg i exit. Reszta obok, kazdy z naglowkiem:
#   dane.ps1    zrodla liczb (dzienniki obu wersji, rozbicie pelnej na etapy, cale zuzycie dnia), dni, sumy
#   strona.ps1  HTML: karty, wykres SVG, tabela, suma, stopka, strona bledu
# Test: narzedzia\koszt-wiedzy\test-koszt-wiedzy.ps1.

param(
  [string]$KatalogDomowy = $HOME,
  [string]$Zrodlo = "",
  [string]$Wyjscie = "",
  [string]$Dzis = "",
  [switch]$Otworz
)

$ErrorActionPreference = "Stop"
if (-not $Zrodlo) { $Zrodlo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$Mr = Join-Path $KatalogDomowy ".claude\mr"
if (-not $Wyjscie) { $Wyjscie = Join-Path $Mr "koszt-wiedzy.html" }
$Odswiezono = Get-Date -Format "dd.MM.yyyy HH:mm"

function Zapisz-Html($plik, $tekst) {
  # najpierw plik obok, potem podmiana - przegladarka nie zobaczy polowy strony
  $kat = Split-Path -Parent $plik
  if (-not (Test-Path -LiteralPath $kat)) { New-Item -ItemType Directory -Force -Path $kat | Out-Null }
  $tmp = "$plik.tmp"
  [System.IO.File]::WriteAllText($tmp, $tekst, (New-Object System.Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $tmp -Destination $plik -Force
}

function Otworz-Strone {
  if (-not $Otworz) { return }
  if (-not (Test-Path -LiteralPath $Wyjscie)) { return }
  try { Start-Process -FilePath $Wyjscie }
  catch { Write-Output "UWAGA nie otworzylem strony w przegladarce: $($_.Exception.Message)" }
}

function Porazka($powod) {
  Write-Output "BLAD $powod"
  try { Zapisz-Html $Wyjscie (Strona-Bledu $Odswiezono $powod) }
  catch { Write-Output "BLAD nie zapisalem nawet strony bledu ($Wyjscie): $($_.Exception.Message)" }
  Otworz-Strone
  exit 1
}

$script:ModulyKosztuWiedzy = @{}
foreach ($modul in @("dane", "strona")) {
  $plikModulu = Join-Path $PSScriptRoot "$modul.ps1"
  try { . $plikModulu }
  catch {
    $script:ModulyKosztuWiedzy = @{}
    Write-Output "BLAD nie da sie wczytac $plikModulu ($($_.Exception.Message))"
    exit 1
  }
  if (-not $script:ModulyKosztuWiedzy[$modul]) {
    Write-Output "BLAD $plikModulu nie wczytal sie do konca (brak znacznika na koncu - plik pusty albo uciety)"
    exit 1
  }
}

try {
  $dzisData = [datetime]::Today
  if ($Dzis) {
    $dzisData = Dzien-Z $Dzis
    if ($null -eq $dzisData) { Porazka "zly parametr -Dzis '$Dzis' (ma byc RRRR-MM-DD)" }
  }
  $wiedza = Join-Path $KatalogDomowy ".claude\wiedza"
  $plikTanszej = Join-Path $wiedza ".koszt-historia.tsv"
  $plikCyklu = Join-Path $wiedza "cykl-ostatni.txt"
  $plikPelnej = Join-Path $Mr "wiedza-firmy\koszty.jsonl"
  $plikPodreczny = Join-Path $Mr "koszt-wiedzy-dni.tsv"

  $uwagi = @()
  $tansza = Czytaj-Tansza $plikTanszej
  if ($tansza.Jest -and ($tansza.Dni.Count -eq 0)) { $uwagi += "Tańsza wersja: $($tansza.Powod)" }
  elseif (-not $tansza.Jest) { $uwagi += "Tańsza wersja: $($tansza.Powod)" }
  if ($tansza.Pominiete -gt 0) { $uwagi += "Tańsza wersja: $($tansza.Pominiete) linii dziennika $plikTanszej nie da się odczytać - pominięte" }
  $bladTanszej = Blad-Tanszej $plikCyklu
  if ($bladTanszej -and (-not $bladTanszej.Dzien)) { $uwagi += "Tańsza wersja: $($bladTanszej.Opis)"; $bladTanszej = $null }

  $pelna = Dolacz-Probe (Czytaj-Pelna $plikPelnej)
  # Brak dziennika pelnej wersji to NIE awaria - ten krok jeszcze nie ruszyl; karta mowi "brak danych".
  if ($pelna.Jest -eq $false -and (Test-Path -LiteralPath $plikPelnej)) { $uwagi += "Pełna wersja: $($pelna.Powod)" }
  # Rozbicie przebiegow na etapy; suma etapow, ktora nie zgadza sie z suma przebiegu, idzie na gore.
  foreach ($u in @(Dolacz-Etapy $pelna (Join-Path $Mr "wiedza-firmy\dzienny"))) { $uwagi += $u }
  if ($pelna.Zle -gt 0) { $uwagi += "Pełna wersja: $($pelna.Zle) linii dziennika $plikPelnej nie da się odczytać (np. $($pelna.PrzykladZlej)) - pominięte" }

  $klucze = Zakres-Dni $dzisData $tansza $bladTanszej $pelna
  $cale = Cale-Zuzycie $KatalogDomowy $Zrodlo $klucze $plikPodreczny
  if ($cale.Powod) { $uwagi += "Całe zużycie dnia nie jest policzone, więc procentów nie ma: $($cale.Powod)" }
  foreach ($u in @($cale.Ostrzezenia)) { $uwagi += "Całe zużycie dnia: $u" }

  $wiersze = @(Zloz-Dni $klucze $tansza $bladTanszej $pelna $cale)
  $model = [pscustomobject]@{
    Odswiezono = $Odswiezono; Dzis = $dzisData; Wiersze = $wiersze
    Karty = (Dzien-Kart $wiersze $dzisData); Suma = (Podsumuj-Okres $wiersze); Uwagi = $uwagi
    Tansza = $tansza; Pelna = $pelna; Cale = $cale
    Zrodla = @($plikTanszej, $plikPelnej, "$(Join-Path $KatalogDomowy '.claude\projects') (licznik okna nadzorcy)")
  }
  $html = Zbuduj-Strone $model
} catch {
  Porazka "budowa strony sie wywrocila: $(($_.Exception.Message -replace '[\r\n]+', ' ').Trim()) (linia $($_.InvocationInfo.ScriptLineNumber) w $($_.InvocationInfo.ScriptName))"
}

try { Zapisz-Html $Wyjscie $html }
catch {
  Write-Output "BLAD nie zapisalem strony $Wyjscie : $($_.Exception.Message)"
  exit 1
}

Write-Output "strona: $Wyjscie"
Write-Output ("dni: {0}, cale zuzycie: {1} z pliku podrecznego, {2} policzone teraz ({3} s)" -f $wiersze.Count, $cale.ZPliku, $cale.Policzone, $cale.Sekundy)
foreach ($u in $uwagi) { Write-Output "UWAGA $u" }
Otworz-Strone
if ($uwagi.Count -gt 0) { exit 2 }
exit 0
