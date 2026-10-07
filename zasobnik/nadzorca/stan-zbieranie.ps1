# zasobnik\nadzorca\stan-zbieranie.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Zbieranie danych: Zbierz-Wszystko sklada jeden obiekt
# (zainstalowane moduly, wersja, zmiany w pamieci, przeliczanie, kopia, cykl, rachunek,
# alarmy, informacje) dla okna i dozoru - czesci modulow, ktorych nie ma w instalacji,
# zostaja puste (P59d). Do tego alarm aktualizacji automatycznej (Alarm-Aktualizacji).
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
  # Aktualizacja automatyczna - slady jej zegara w nadzorcy (baza, bez modulu w rejestrze; blad,
  # urwany przebieg i dawne sprawdzenie pokazuje karta Stan - stan-wersja.ps1 Ocena-Aktualizacji).
  try {
    $aa = Alarm-Aktualizacji
    if ($aa) { $d.Alarmy = @($d.Alarmy) + @($aa) }
  } catch { Zanotuj-Wywrotke "alarm aktualizacji automatycznej" $_ }
  # Zolte informacje (np. nauka nadrabiala zaleglosc) - osobno od alarmow, bo
  # alarmy ida na dymek, a informacja nie ma prawa wyskakiwac jak ostrzezenie.
  if ($d.Rachunek) {
    try { $d.Informacje = Zbierz-Informacje $d.Rachunek $d.Instalacja }
    catch { Zanotuj-Wywrotke "skladanie informacji o koszcie nauki" $_ }
  }
  return $d
}

# ------------------------------------------- aktualizacja automatyczna (2026-10-07)
# Slady zegara aktualizacji w nadzorcy - "bylem tu" po STRONIE NADZORCY: dozor.ps1 zapisuje
# aktualizacja.zaplanowana (zegar wstal) i aktualizacja.zlecona (wystartowal skrypt) w pliku stanu
# nadzorcy. Ich nieswiezosc to alarm o przyczynie, ktorej sam plik postepu nie powie:
#  - zlecona, a skrypt nie zostawil sladu (konca w ~\.claude\mr\aktualizacja.json nowszego niz
#    zlecenie) po $MINUT_NA_SLAD min - start w tle nie wyszedl albo skrypt pada, zanim cokolwiek zapisze,
#  - zegar wstal, a od $GODZIN_CISZY_AKTUALIZACJI godzin nic nie zlecil, choc nadzorca chodzi - zegar
#    stanal (plik postepu bywa wtedy swiezy, bo aktualizacje klika sie recznie).
# Gdy plik postepu sam pokazuje klopot - nie ma go, jest nieczytelny, przebieg trwa albo urwal sie,
# skonczyl sie bledem albo ostatnie sprawdzenie jest starsze niz $GODZIN_CISZY_AKTUALIZACJI godziny -
# tu jest cisza z premedytacja: to wszystko pokazuje karta Stan na Przegladzie (stan-wersja.ps1
# Ocena-Aktualizacji, ten sam plik i ten sam prog 3 h). Druga karta o tym samym bylaby szumem.
# Bez sladow zegara (swiezy komputer, tryb -Proba, katalog testowy) - tez cisza.
# Start procesu i pierwszy zapis stanu to sekundy; kwadrans to jeden przebieg dozoru zapasu.
$MINUT_NA_SLAD = 15
# Zegar odpala co 60 min - trzy pominiete przebiegi to nie przypadek (jeden potrafi przespac
# uspienie komputera, a zegar okna odpala wtedy zaraz po wybudzeniu). Ten sam prog, co
# "nie sprawdzala serwera" w Ocena-Aktualizacji ($GODZIN_BEZ_SPRAWDZENIA_AKTUALIZACJI).
$GODZIN_CISZY_AKTUALIZACJI = 3
# Nadzorca chodzi = slad "byl" mlodszy niz tyle: dozor pisze go co 15 min, 40 to dwa pominiete.
# Bez tego warunku wydruk -Raport po zamknieciu ikony krzyczalby o zegarze, ktorego nie ma.
$MINUT_NADZORCA_ZYJE = 40

function Plik-Postepu-Aktualizacji { return (Join-Path $script:NadzDom ".claude\mr\aktualizacja.json") }

function Alarm-Aktualizacji([datetime]$teraz = [datetime]::Now) {
  $stan = Czytaj-Klucze $script:NadzPlikStanu
  $zaplanowana = Data-Lub-Nic $stan["aktualizacja.zaplanowana"]
  $zlecona = Data-Lub-Nic $stan["aktualizacja.zlecona"]
  if (-not $zaplanowana -and -not $zlecona) { return $null }

  # Plik postepu - tylko gdy sam nie pokazuje klopotu (patrz wyzej).
  $plik = Plik-Postepu-Aktualizacji
  if (-not (Test-Path -LiteralPath $plik)) { return $null }
  $a = $null
  try { $a = ("" + (Czytaj-Tekst $plik)).TrimStart([char]0xFEFF) | ConvertFrom-Json } catch { return $null }
  if (-not $a -or ("$($a.etap)" -ne "gotowe")) { return $null }
  $koniec = Data-Lub-Nic "$($a.koniec)"
  $ostatni = $koniec
  $sprawdzone = Data-Lub-Nic "$($a.sprawdzone)"
  if ($sprawdzone -and ((-not $ostatni) -or ($sprawdzone -gt $ostatni))) { $ostatni = $sprawdzone }
  if (-not $ostatni -or ((($teraz - $ostatni).TotalHours) -ge $GODZIN_CISZY_AKTUALIZACJI)) { return $null }

  $dziennik = Join-Path $script:NadzDom ".claude\mr\aktualizacja.log"
  if ($zlecona -and ((($teraz - $zlecona).TotalMinutes) -ge $MINUT_NA_SLAD) -and ((-not $koniec) -or ($koniec -lt $zlecona.AddMinutes(-1)))) {
    $kiedyKoniec = if ($koniec) { $koniec.ToString('yyyy-MM-dd HH:mm') } else { "nie wiadomo kiedy" }
    return (Alarm "aktualizacja" "MegaRuchacz: aktualizacja nie wystartowała" (
      "Nadzorca uruchomił aktualizację o $($zlecona.ToString('yyyy-MM-dd HH:mm')), a ona nie zostawiła śladu (ostatnio skończona: $kiedyKoniec). " +
      "Przyczyny szukaj w dzienniku aktualizacji ($dziennik) i nadzorcy ($($script:NadzPlikDziennika)).") "uwaga" (
      "Nadzorca próbował uruchomić aktualizację MegaRuchacza, ale ona nie ruszyła. Spróbuje znowu za godzinę - jeśli ten alarm wraca, przekaż jego opis."))
  }

  $byl = Data-Lub-Nic $stan["byl"]
  $zyje = $byl -and ((($teraz - $byl).TotalMinutes) -lt $MINUT_NADZORCA_ZYJE)
  if ($zaplanowana -and $zyje) {
    $ostatnio = $zlecona
    if (-not $ostatnio -or ($ostatnio -lt $zaplanowana)) { $ostatnio = $zaplanowana }
    if ((($teraz - $ostatnio).TotalHours) -ge $GODZIN_CISZY_AKTUALIZACJI) {
      $co = if ($zlecona -and ($zlecona -ge $zaplanowana)) { "ostatnio uruchomiona $($zlecona.ToString('yyyy-MM-dd HH:mm'))" } else { "od startu nadzorcy ($($zaplanowana.ToString('yyyy-MM-dd HH:mm'))) ani razu" }
      return (Alarm "aktualizacja" "MegaRuchacz: aktualizacja automatyczna nie rusza" (
        "Nadzorca chodzi, a od ponad $GODZIN_CISZY_AKTUALIZACJI godzin nie uruchomił aktualizacji sam ($co) - powinien co godzinę. " +
        "Dziennik nadzorcy: $($script:NadzPlikDziennika)") "uwaga" (
        "Aktualizacja MegaRuchacza przestała ruszać sama. Zamknij ikonę MegaRuchacza i uruchom go ponownie - jeśli alarm wraca, przekaż jego opis."))
    }
  }
  return $null
}

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["zbieranie"] = $true
