# zasobnik\nadzorca\stan-zbieranie.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Zbieranie danych: Zbierz-Wszystko sklada jeden obiekt
# (wersja, zmiany w pamieci, przeliczanie, cykl, rachunek, alarmy, informacje) dla
# okna i dozoru.
# Skad wolane: krok "dane" i dozor w tle (w-tle.ps1, dozor.ps1 - w watku, ktory
# wczytuje stan-nadzorcy.ps1), tryby -Raz i -Raport w nadzorca.ps1. Wczytuje go
# stan-nadzorcy.ps1 kropka jako ostatni - same definicje.

# ------------------------------------------------------- zbieranie danych (P21)
# Przeniesione z nadzorca.ps1 w 0.22.4: okno liczy dane w watku w tle (runspace),
# ktory wczytuje tylko ten plik - dlatego Zbierz-Wszystko musi byc tutaj. Tresc bez zmian.
#
# Cztery rzeczy ze zlecenia, w kolejnosci od najczesciej ogladanej: rachunek,
# cykl, wersja, alarmy - plus slad samego nadzorcy, bo on tez ma nie milczec
# o sobie. Zbierane raz, zeby dozor i okno nie liczyly tego samego dwa razy.
function Zbierz-Wszystko([bool]$zSieci, [bool]$zKolejka) {
  $d = [pscustomobject]@{ Wersja = $null; Cykl = $null; Rachunek = $null; Alarmy = @(); Informacje = @(); Pamiec = $null; Przeliczanie = $null }

  try { $d.Wersja = Stan-Wersji $zSieci }
  catch { Zanotuj-Wywrotke "odczyt wersji narzedzia" $_ }

  # Oba odczyty to same pliki na dysku, bez wolania skryptow - ulamek sekundy.
  try { $d.Pamiec = Stan-Zmian-Pamieci }
  catch { Zanotuj-Wywrotke "odczyt zmian w pamieci" $_ }

  try { $d.Przeliczanie = Postep-Przeliczania }
  catch { Zanotuj-Wywrotke "odczyt postepu przeliczania archiwum" $_ }

  try { $d.Cykl = Stan-Cyklu $zKolejka }
  catch { Zanotuj-Wywrotke "odczyt stanu cyklu" $_ }

  try { $d.Rachunek = Linia-Rachunku }
  catch { Zanotuj-Wywrotke "rachunek za pamiec (linia)" $_ }

  if ($d.Cykl -and $d.Rachunek) {
    try { $d.Alarmy = Zbierz-Alarmy $d.Cykl $d.Rachunek }
    catch { Zanotuj-Wywrotke "skladanie alarmow" $_ }
  }
  # Zolte informacje (np. nauka nadrabiala zaleglosc) - osobno od alarmow, bo
  # alarmy ida na dymek, a informacja nie ma prawa wyskakiwac jak ostrzezenie.
  if ($d.Rachunek) {
    try { $d.Informacje = Zbierz-Informacje $d.Rachunek }
    catch { Zanotuj-Wywrotke "skladanie informacji o koszcie nauki" $_ }
  }
  return $d
}

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["zbieranie"] = $true
