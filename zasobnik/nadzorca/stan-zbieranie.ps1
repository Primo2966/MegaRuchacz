# zasobnik\nadzorca\stan-zbieranie.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Zbieranie danych: Zbierz-Wszystko sklada jeden obiekt
# (zainstalowane moduly, wersja, zmiany w pamieci, przeliczanie, kopia, cykl, rachunek,
# alarmy, informacje) dla okna i dozoru - czesci modulow, ktorych nie ma w instalacji,
# zostaja puste (P59d).
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
  $d = [pscustomobject]@{ Wersja = $null; Cykl = $null; Rachunek = $null; Alarmy = @(); Informacje = @(); Pamiec = $null; Przeliczanie = $null; Kopia = $null; Instalacja = $null }

  # Ktore moduly sa zainstalowane (P59d) - najpierw, bo od tego zalezy, co liczyc dalej.
  # Wywrotka = $null, czyli "wszystko jest" (Modul-Jest) - jak przy nieczytelnym rejestrze.
  try { $d.Instalacja = Stan-Instalacji }
  catch { Zanotuj-Wywrotke "odczyt rejestru instalacji" $_ }
  $wiedza = Modul-Jest $d.Instalacja "wiedza"

  try { $d.Wersja = Stan-Wersji $zSieci }
  catch { Zanotuj-Wywrotke "odczyt wersji narzedzia" $_ }

  # Oba odczyty to same pliki na dysku, bez wolania skryptow - ulamek sekundy.
  # Zmiany w pamieci pisze nauka z rozmow (Wiedza), przeliczanie archiwum - Lore.
  if ($wiedza) {
    try { $d.Pamiec = Stan-Zmian-Pamieci }
    catch { Zanotuj-Wywrotke "odczyt zmian w pamieci" $_ }
  }

  if (Modul-Jest $d.Instalacja "lore") {
    try { $d.Przeliczanie = Postep-Przeliczania }
    catch { Zanotuj-Wywrotke "odczyt postepu przeliczania archiwum" $_ }
  }

  # Kopia zapasowa (P62) - jeden maly plik stanu i data indeksu.
  if (Modul-Jest $d.Instalacja "kopia") {
    try { $d.Kopia = Stan-Kopii }
    catch { Zanotuj-Wywrotke "odczyt stanu kopii zapasowej" $_ }
  }

  # Bez modulu Wiedza nauka nie chodzi: stanu cyklu nie czytamy wcale (stare pliki
  # na dysku pokazalyby nauke, ktorej nie ma), a kolejki tym bardziej nie liczymy.
  if ($wiedza) {
    try { $d.Cykl = Stan-Cyklu $zKolejka }
    catch { Zanotuj-Wywrotke "odczyt stanu cyklu" $_ }
  }

  try { $d.Rachunek = Linia-Rachunku }
  catch { Zanotuj-Wywrotke "rachunek za pamiec (linia)" $_ }

  if ($d.Rachunek -and ($d.Cykl -or -not $wiedza)) {
    try { $d.Alarmy = Zbierz-Alarmy $d.Cykl $d.Rachunek $d.Instalacja }
    catch { Zanotuj-Wywrotke "skladanie alarmow" $_ }
  }
  # Nieczytelny rejestr instalacji - pilny alarm zawsze, takze gdy reszty alarmow nie
  # dalo sie policzyc (bez niego nikt by nie wiedzial, czemu okno pokazuje wszystko).
  try {
    $ai = Alarm-Instalacji $d.Instalacja
    if ($ai) { $d.Alarmy = @($d.Alarmy) + @($ai) }
  } catch { Zanotuj-Wywrotke "alarm rejestru instalacji" $_ }
  # Zolte informacje (np. nauka nadrabiala zaleglosc) - osobno od alarmow, bo
  # alarmy ida na dymek, a informacja nie ma prawa wyskakiwac jak ostrzezenie.
  if ($d.Rachunek) {
    try { $d.Informacje = Zbierz-Informacje $d.Rachunek $d.Instalacja }
    catch { Zanotuj-Wywrotke "skladanie informacji o koszcie nauki" $_ }
  }
  return $d
}

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["zbieranie"] = $true
