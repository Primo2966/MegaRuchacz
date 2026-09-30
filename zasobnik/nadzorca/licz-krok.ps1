# zasobnik\nadzorca\licz-krok.ps1 - liczenie JEDNEGO kroku danych okna nadzorcy
# w osobnym procesie. To NIE jest modul: nie wczytuje sie kropka i nie ma znacznika
# ModulyOkna. Okno uruchamia go zwyklym powershell.exe -NoProfile -File (P38).
#
# DLACZEGO OSOBNY PROCES (P38, 30.09.2026). Do P28a kazdy krok liczyl sie w watku
# (runspace) okna, a kod watku ($KOD_KROKU w w-tle.ps1) byl skladany ze stringa
# i uruchamiany wewnatrz procesu okna. Microsoft Defender widzial w tej konstrukcji
# narzedzie do omijania zabezpieczen PowerShella (falszywy alarm na naszym wlasnym
# kodzie) i wywracal liczenie w tle (dozor co kwadrans i ekran ladowania okna
# uzywaja tego samego kodu). Teraz kazdy krok to zwykly, osobny proces: wczytuje
# stan-nadzorcy.ps1, liczy wskazany kawalek przez NAZWANE funkcje (bez budowania
# kodu ze stringow, bez siegania do wnetrza silnika PowerShella) i oddaje wynik
# przez Export-Clixml do -PlikWyniku, ktory czyta okno. Blad tez trafia do tego
# pliku (pole Blad), a nie ginie po cichu.
#
# Wolane z: Przydziel-Proces w zasobnik\nadzorca\w-tle.ps1. Argumenty w tej samej
# roli, co dawne argumenty $KOD_KROKU:
#   -PlikStanu   sciezka stan-nadzorcy.ps1 ($script:NadzTenPlik) - wczytujemy go
#   -Zrodlo -Dom -Proba   to samo, co Ustaw-Nadzorce
#   -Kawalek     ktore dane liczyc (dane / start / zuzycie / rozbicie / warstwy /
#                skille / koszt) - dispatch switchem po NAZWIE, bez kodu ze stringa
#   -ZSiecia     tylko dla "dane": czy Zbierz-Wszystko zaglada po nowsza wersje
#   -Odpalone    dlawik liczenia zuzycia (NadzZuzycieOdpalone) - godzina jako tekst
#                ISO (format "o") albo pusto ($null); wraca w wyniku
#   -SekundyZuzycia  ile najwyzej czekac, az zuzycie sie policzy (reszte dociaga okno)
#   -PlikWyniku  gdzie zapisac wynik (Export-Clixml); tam trafia tez ewentualny blad
# Bool i godzine przez -File PowerShell przekazuje jako TEKST - dlatego parametry
# sa [string] i zamieniamy je tu wprost, bez zgadywania.
param(
  [string]$PlikStanu,
  [string]$Zrodlo,
  [string]$Dom,
  [string]$Proba = "False",
  [string]$Kawalek,
  [string]$ZSiecia = "False",
  [string]$Odpalone = "",
  [int]$SekundyZuzycia = 60,
  [string]$PlikWyniku
)
$ErrorActionPreference = "Stop"
$bProba   = ($Proba -eq "True")
$bZSiecia = ($ZSiecia -eq "True")
$dtOdpalone = $null
if ($Odpalone) {
  try { $dtOdpalone = [datetime]::Parse($Odpalone, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind) }
  catch { $dtOdpalone = $null }
}

$wywrotki = @()
$odpalone = $dtOdpalone
try {
  . $PlikStanu
  Ustaw-Nadzorce $Zrodlo $Dom $bProba
  $script:NadzZuzycieOdpalone = $dtOdpalone
  $wynik = switch ($Kawalek) {
    "dane"     { Zbierz-Wszystko $bZSiecia $true }
    "start"    { Pomiar-Startu }
    "zuzycie"  {
      # Zuzycie potrafi liczyc sie dluzej - czekamy najwyzej -SekundyZuzycia,
      # dokladnie tak, jak robil to dawny $KOD_KROKU. Reszte dociaga samo okno
      # (Odswiez-Zuzycie), a samo liczenie ma swoj limit w stan-zuzycie.ps1.
      $z = Zuzycie-Dzienne $false
      $do = [datetime]::Now.AddSeconds($SekundyZuzycia)
      while (($z.Stan -eq "licze") -and ([datetime]::Now -lt $do)) {
        Start-Sleep -Milliseconds 400
        $z = Zuzycie-Dzienne $false
      }
      $z
    }
    "rozbicie" { Rachunek-Rozbicie }
    "warstwy"  { Warstwy-Pamieci }
    "skille"   { Stan-Skilli }
    "koszt"    { Koszt-Dzis }
    default    { throw "nieznany kawalek '$Kawalek'" }
  }
  $wywrotki = @($script:NadzWywrotki)
  $odpalone = $script:NadzZuzycieOdpalone
  $opak = [pscustomobject]@{ Wynik = $wynik; Blad = $null; Wywrotki = $wywrotki; Odpalone = $odpalone }
} catch {
  if ($script:NadzWywrotki) { $wywrotki = @($script:NadzWywrotki) }
  $opak = [pscustomobject]@{ Wynik = $null; Blad = "$($_.Exception.Message)"; Wywrotki = $wywrotki; Odpalone = $odpalone }
}
try {
  $opak | Export-Clixml -Path $PlikWyniku -Depth 12
} catch {
  # Ostatnia deska ratunku - okno nie moze zostac z pustym plikiem bez slowa
  # (Odbierz-Krok przeczyta ten tekst i pokaze go jako powod bledu kroku).
  try { Set-Content -LiteralPath $PlikWyniku -Value ("BLAD ZAPISU WYNIKU KROKU: " + $_.Exception.Message) -Encoding UTF8 }
  catch { Write-Error "nie zapisalem wyniku kroku do $PlikWyniku - $($_.Exception.Message)" }
}
