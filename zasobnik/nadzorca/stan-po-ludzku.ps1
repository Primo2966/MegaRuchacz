# zasobnik\nadzorca\stan-po-ludzku.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Jezyk, ktorym mowi czlowiek - sama prezentacja:
# odmiana i daty (Odmiana, Kiedy-Ludzko, Dzien-Ludzko), koszt nauki (Liczba-Nauki,
# Alarm-Z-Rachunku, Zbierz-Informacje, Statystyka-Okna), zmiany w pamieci
# (Stan-Zmian-Pamieci, Opis-Zmian-Pamieci), przeliczanie archiwum
# (Postep-Przeliczania), stan jednym rzutem oka (Linie-Stanu), waga i porada
# alarmu (Waga-Alarmu, Porada-Ludzka) i szacunek kosztu cyklu przed przyciskiem
# (Max-Nadrabiania, Szacunek-Cyklu).
# Skad wolane: stan-zbieranie.ps1, stan-alarmy.ps1, karty i sekcje okna,
# przeglad-tresc.ps1. Wczytuje go stan-nadzorcy.ps1 kropka - poza stala
# $WZORCE_PRZELICZANIA same definicje.

# ====================================================== jezyk, ktorym mowi czlowiek
#
# Wszystko ponizej sluzy WYLACZNIE prezentacji. Bierze liczby, ktore juz sa
# policzone wyzej, i ubiera je w zdania, ktorych uzywa uzytkownik. Ani jedna
# z tych funkcji nie liczy kosztu drugi raz: rachunek liczy
# narzedzia\koszt-pamieci.ps1, kolejke narzedzia\wyciagnij-fakty.ps1 -Kolejka,
# koszt cyklu zapisuje samo wylawianie. Jedyna arytmetyka, ktora powstaje tutaj,
# to SZACUNEK przed przyciskiem (Szacunek-Cyklu) - i on mnozy wylacznie liczby
# ZMIERZONE, zadnej stalej z powietrza.
#
# Teksty w tej sekcji maja polskie znaki i tak ma byc: ida do okna, nie do kodu.
# Plik jest zapisany w UTF-8 ZE ZNACZNIKIEM BOM - bez niego PowerShell 5.1 czyta
# go jako ANSI i zamiast "koszt rozmow" wychodza krzaki. To bylo juz dwa razy.

# Odmiana przez liczbe. Bez niej okno pisze "1 fragmentow" i od razu wyglada
# na zrobione byle jak - a ma byc tym, czemu uzytkownik ufa.
function Odmiana([int]$n, [string]$jeden, [string]$kilka, [string]$wiele) {
  if ($n -eq 1) { return $jeden }
  $ost = $n % 10
  $dwie = $n % 100
  if (($ost -ge 2) -and ($ost -le 4) -and (($dwie -lt 12) -or ($dwie -gt 14))) { return $kilka }
  return $wiele
}

# "dzis o 09:42" zamiast "2026-09-24 09:42". Data w formacie maszynowym zmusza
# czlowieka do liczenia w glowie, a okno ma odpowiadac w trzy sekundy.
function Kiedy-Ludzko($data) {
  if (-not $data) { return $null }
  $dzis = [datetime]::Now.Date
  if ($data.Date -eq $dzis)             { return "dziś o $($data.ToString('HH:mm'))" }
  if ($data.Date -eq $dzis.AddDays(-1)) { return "wczoraj o $($data.ToString('HH:mm'))" }
  $dni = [int]($dzis - $data.Date).TotalDays
  return "$($data.ToString('dd.MM')), $dni $(Odmiana $dni 'dzień' 'dni' 'dni') temu"
}

# To samo, ale SAM DZIEN. Osobna funkcja, bo .koszt-cyklu.txt zapisuje sama date
# bez godziny - "dzis o 00:00" brzmialoby jak pomiar z polnocy, czyli jak liczba,
# ktorej nikt nie zmierzyl.
function Dzien-Ludzko($data) {
  if (-not $data) { return $null }
  $dzis = [datetime]::Now.Date
  if ($data.Date -eq $dzis)             { return "dziś" }
  if ($data.Date -eq $dzis.AddDays(-1)) { return "wczoraj" }
  return $data.ToString('dd.MM')
}

# KOSZT NAUKI Z ROZMOW NA WIERZCHU OKNA.
#
# Do 28.09.2026 (P14) byly tu TRZY liczby: na wiadomosc, na otwarcie sesji
# i nauka. Dwie pierwsze powtarzaly to, co stoi w karcie "Otwarcie sesji" -
# uzytkownik: "u gory jest otwarcie sesji, srodkowy kafelek tez ma napisane,
# ile doklada do kazdej sesji. Czym to sie rozni?". Zostaly wiec tylko w tej
# karcie (rozpisane na "raz na start sesji" i "przy kazdej wiadomosci"), a tu
# sama nauka - to inny koszt: jedyne prawdziwe wywolanie modelu. Liczba to
# koszt ostatniego przebiegu, czyli to, co samo wylawianie zapisalo
# w .koszt-cyklu.txt. Nic tu nie jest liczone na nowo.
#
# Gdy liczby nie da sie ustalic, pole Liczba zostaje puste, a w Powod stoi
# DLACZEGO. Okno pokazuje wtedy "nie wiem" i powod, nigdy zera: zero znaczy
# "nic nie kosztuje" i byloby najdrozszym rodzajem ciszy w calym narzedziu.
function Liczba-Nauki($rachunek, $cykl) {
  # Slowa bez zargonu (P14, uzytkownik: "trzecia belka jest niezrozumiala"):
  # zadnego "wywolania modelu", "doklejonego tekstu" ani "nadrabiania".
  $naDobe = [pscustomobject]@{
    Naglowek = "Raz dziennie: MegaRuchacz czyta Twoje rozmowy i wyciąga z nich fakty"
    Liczba   = $null
    # P35: wykres z 30 dni przeszedl z Przegladu do Szczegolow - mowimy, gdzie jest.
    Opis     = "Tylko tu MegaRuchacz sam zleca pracę Claude'owi i za nią płacisz. Wszystko inne to tekst dopisany do Twoich rozmów - karta wyżej. Wykres z 30 dni - w zakładce Szczegóły."
    Ogon     = ""
    Powod    = ""
    # Za jaki okres i czy to nadrabianie - bez tego drogi dzien nadrabiania
    # wygladal na karcie jak nowa norma. Waga koloruje tylko ten jeden napis.
    Znacznik     = ""
    ZnacznikWaga = ""
  }

  if ($cykl -and ($null -ne $cykl.Koszt)) {
    $naDobe.Liczba = [long]$cykl.Koszt
    $kiedy = Dzien-Ludzko $cykl.KosztData
    if ($kiedy) { $naDobe.Ogon = "ostatnio $kiedy" } else { $naDobe.Ogon = "przy ostatnim przebiegu" }
    $o = Ocena-Nauki $rachunek
    $okres = Okres-Ludzko $o.ZakresOd $o.ZakresDo
    # P15: bez slowa "zalegle" - laik nie wie, co zalega. Mowimy, co sie stalo:
    # przeczytal rozmowy, ktore czekaly dluzej niz jeden dzien.
    switch ($o.Rodzaj) {
      "nadrabianie" { $naDobe.Znacznik = "tym razem czytał rozmowy, które czekały dłużej niż dzień";            $naDobe.ZnacznikWaga = "info" }
      "mieszany"    { $naDobe.Znacznik = "tym razem czytał nowe rozmowy i część tych, które czekały dłużej"; $naDobe.ZnacznikWaga = "info" }
      "zwykly"      { $naDobe.Znacznik = "zwykły dzień - czytał rozmowy z poprzedniego dnia";                 $naDobe.ZnacznikWaga = "" }
      "nieznany"    { $naDobe.Znacznik = "nie wiem, z których dni były czytane rozmowy";                      $naDobe.ZnacznikWaga = "uwaga" }
    }
    if ($okres -and $naDobe.Znacznik -and ($o.Rodzaj -ne "nieznany")) { $naDobe.Znacznik = "$($naDobe.Znacznik) (z $okres)" }
    elseif ($okres -and $naDobe.Znacznik) { $naDobe.Znacznik = "$($naDobe.Znacznik) (zakres: $okres)" }
    foreach ($a in (Alarmy-Rachunku $rachunek)) {
      if (($a.Temat -eq "cykl-zwykly") -or ($a.Temat -eq "cykl-rosnie")) { $naDobe.ZnacznikWaga = "pilne" }
    }
  } else {
    $naDobe.Powod = "nauka z rozmów nie policzyła jeszcze ani razu swojego kosztu"
    if ($cykl) {
      foreach ($p in $cykl.Powody) { if ("$p" -match 'koszt') { $naDobe.Powod = $p } }
    }
  }

  return $naDobe
}

# ---------------------------------------------------- koszt nauki po ludzku

# "~312 600" - liczba zaokraglona do setek, do tytulow. Tylda mowi, ze to
# przyblizenie; pelna liczba stoi na karcie i w szczegolach.
function Okolo($n) {
  if ($null -eq $n) { return "?" }
  return (Liczba-Ludzka ([long]([math]::Round([double]$n / 100.0) * 100)))
}

# "16-17.09" albo "28.08-02.09" (w oknie z polpauza) - okres, za ktory
# zaplacono, jednym rzutem oka.
function Okres-Ludzko([string]$od, [string]$doo) {
  $a = Data-Lub-Nic $od
  $b = Data-Lub-Nic $doo
  if (-not $a) { return "" }
  if ((-not $b) -or ($a.Date -eq $b.Date)) { return $a.ToString('dd.MM') }
  if (($a.Month -eq $b.Month) -and ($a.Year -eq $b.Year)) { return ($a.ToString('dd') + "–" + $b.ToString('dd.MM')) }
  return ($a.ToString('dd.MM') + "–" + $b.ToString('dd.MM'))
}

# Ile kosztuje zwykly dzien. Liczba pochodzi z koszt-pamieci.ps1 (typowa wartosc
# z dni bez nadrabiania); gdy jej nie ma, mowimy to wprost - nie zgadujemy.
function Zdanie-Zwyklego-Dnia($o) {
  if ($o -and ($null -ne $o.Typowy) -and ($o.TypowychDni -gt 0)) {
    $z = "z $($o.TypowychDni) dni"
    if ($o.TypowychDni -eq 1) { $z = "z 1 dnia" }
    return "zwykły dzień kosztuje ok. $(Okolo $o.Typowy) tokenów (typowa wartość $z bez nadrabiania)"
  }
  return "ile kosztuje zwykły dzień - jeszcze nie wiem, statystyka dopiero się zbiera"
}

function Z-Wielkiej([string]$t) {
  if (-not $t) { return "" }
  return $t.Substring(0, 1).ToUpper() + $t.Substring(1)
}

# Alarm z rachunku ubrany w zdania uzytkownika. KAZDY mowi trzy rzeczy: ZA CO
# jest liczba (kazda wiadomosc, kazda sesja, nauka z rozmow), ZA JAKI OKRES
# (stan na teraz albo konkretne dni) i CZY TO SIE POWTARZA. Pelna, surowa tresc
# z koszt-pamieci.ps1 zostaje w szczegolach - nic nie ginie.
function Alarm-Z-Rachunku($a, $o) {
  $pelne = "Rachunek mowi: $($a.Krotko). $($a.Pelny) Progi i ich uzasadnienie sa w $($script:NadzZrodlo)\narzedzia\koszt-pamieci.ps1"
  $waga = $a.Waga
  if ($waga -eq "pilne") { $waga = "pilne" } elseif ($waga -eq "info") { $waga = "info" } else { $waga = "uwaga" }
  $kiedy = "ostatnio"
  if ($o -and $o.Data) { $kiedy = Dzien-Ludzko $o.Data }
  $okres = ""
  if ($o) { $okres = Okres-Ludzko $o.ZakresOd $o.ZakresDo }
  $wiad = "nieznaną liczbę wiadomości"
  if ($o -and ($null -ne $o.Wiadomosci)) {
    $wiad = "$(Liczba-Ludzka $o.Wiadomosci) $(Odmiana ([int]$o.Wiadomosci) 'wiadomość' 'wiadomości' 'wiadomości')"
  }
  $zOkresu = ""
  if ($okres) { $zOkresu = " z $okres" }
  $tytul = ""
  $porada = ""

  switch ($a.Temat) {
    "wiadomosc" {
      $tytul = "MegaRuchacz: każda wiadomość dokleja ~$(Liczba-Ludzka $a.Liczba) tokenów"
      $porada = ("To stan plików na teraz, nie koszt jednego dnia: tyle tekstu idzie do modelu z każdym Twoim zdaniem " +
                 "(próg $(Liczba-Ludzka $a.Prog)). Która pozycja urosła - w zakładce Szczegóły.")
    }
    "sesja" {
      $tytul = "MegaRuchacz: każde otwarcie okna rozmowy to ~$(Liczba-Ludzka $a.Liczba) jego tokenów"
      $porada = ("To stan plików na teraz, nie koszt jednego dnia: tyle tekstu wchodzi przy każdym otwarciu okna rozmowy " +
                 "(próg $(Liczba-Ludzka $a.Prog)). Najczęściej pomaga skrócenie sekcji 'Co wiem' w pliku z wiedzą. Co urosło - w zakładce Szczegóły.")
    }
    "otwarcie" {
      # Od 30.09.2026 (P35) prog jest znow liczba tokenow czesci MegaRuchacza, a nie
      # procentem calego otwarcia - procent zalezy od wagi dodatkow, ktora ustawia
      # administrator proxy. Liczba i prog przychodza z rachunku w tokenach.
      $tytul = "MegaRuchacz dokłada już ~$(Okolo $a.Liczba) tokenów do każdego otwarcia okna rozmowy (próg ~$(Okolo $a.Prog))"
      $porada = ("Tyle tekstu wchodzi od samego MegaRuchacza przy każdym otwarciu okna rozmowy - resztę dokłada sam Claude Code. " +
                 "To stan plików na teraz, nie koszt jednego dnia. Najczęściej pomaga skrócenie sekcji 'Co wiem'. Co urosło - w zakładce Szczegóły.")
    }
    "udzial" {
      $tytul = "MegaRuchacz: jedna pozycja to $($a.Liczba)% rachunku"
      $porada = "Stan plików na teraz. Skracanie czegokolwiek innego nic nie da. Która to pozycja - w zakładce Szczegóły."
    }
    "wzrost" {
      $m = [regex]::Match($a.Okres, '(\d\d\.\d\d)')
      $od = "poprzedniego pomiaru"
      if ($m.Success) { $od = $m.Groups[1].Value }
      $tytul = "MegaRuchacz: jego część otwarcia okna rozmowy urosła o $($a.Liczba)% od $od"
      $porada = "Tyle więcej tekstu wchodzi teraz przy każdym otwarciu okna rozmowy niż przy pomiarze z $od. Co doszło - w zakładce Szczegóły."
      # Skok, po ktorym czesc MegaRuchacza jest wciaz ponizej progu, przychodzi jako
      # informacja (waga "info"): widac go, ale nic sie nie pali.
      if ($a.Waga -eq "info") {
        $porada = "Część MegaRuchacza nadal jest poniżej progu, od którego robi się drogo, więc to tylko informacja. Co doszło - w zakładce Szczegóły."
      }
    }
    "cykl-zwykly" {
      $tytul = "MegaRuchacz: nauka $kiedy ~$(Okolo $a.Liczba) tokenów za zwykły dzień"
      $porada = ("Przeczytała $wiad$zOkresu - rozmowy z jednego dnia, a nie nadrabianie zaległości - " +
                 "i przekroczyła próg zwykłego dnia ($(Liczba-Ludzka $a.Prog)). Dla porównania: $(Zdanie-Zwyklego-Dnia $o). " +
                 "Jak to zmniejszyć - w zakładce Szczegóły.")
    }
    "cykl-rosnie" {
      $tytul = "MegaRuchacz: koszt nauki rośnie $($a.Liczba) dni z rzędu"
      $zakres = ""
      if ($o -and $o.WzrostOd -and $o.WzrostDo) {
        $zakres = " Od $($o.WzrostOd.ToString('dd.MM')) do $($o.WzrostDo.ToString('dd.MM')): z ~$(Okolo $o.WzrostOdTokeny) do ~$(Okolo $o.WzrostDoTokeny) tokenów dziennie."
      }
      $ileProc = "wyraźnie"
      if ($o -and ($null -ne $o.ProcWzrostu)) { $ileProc = "o co najmniej $($o.ProcWzrostu)%" }
      $porada = "Zwykły dzień nauki (bez nadrabiania) drożeje dzień po dniu, za każdym razem $ileProc.$zakres To trend, nie jednorazowy skok."
    }
    "cykl-nadrabianie" {
      # Brzmienie ze zlecenia uzytkownika: co konkretnie, za jaki okres i czy
      # to sie powtarza - w tej kolejnosci.
      $tytul = "MegaRuchacz: nauka z rozmów kosztowała $kiedy ~$(Okolo $a.Liczba) tokenów — bo nadrabiała zaległość"
      $wTym = ""
      if ($o -and ($o.Zwykle -gt 0)) { $wTym = " W tym ~$(Okolo $o.Zwykle) tokenów za świeże rozmowy." }
      $porada = "Przeczytała $wiad$zOkresu.$wTym Jednorazowe nadrabianie, nie nowy stały koszt; $(Zdanie-Zwyklego-Dnia $o)."
    }
    "cykl-nieznany" {
      $tytul = "MegaRuchacz: nauka $kiedy ~$(Okolo $a.Liczba) tokenów, okres nieznany"
      $porada = ("Nauka nie zapisała, z których dni czytała rozmowy, więc nie umiem powiedzieć, czy to jednorazowe nadrabianie, " +
                 "czy zwykły dzień (próg zwykłego dnia: $(Liczba-Ludzka $a.Prog)). Zakres zapisuje nowsza wersja modułu pamięci.")
    }
    "historia" {
      if ($null -ne $a.Liczba) {
        $tytul = "MegaRuchacz: dziennik kosztów nauki ma nieczytelne linie"
        $porada = "$(Liczba-Ludzka $a.Liczba) $(Odmiana ([int]$a.Liczba) 'linia jest nieczytelna' 'linie są nieczytelne' 'linii jest nieczytelnych') - ich koszt nie wchodzi do statystyki. Szczegóły - w zakładce Szczegóły."
      } else {
        $tytul = "MegaRuchacz: historia kosztów nauki się nie zapisuje"
        $porada = "Nauka sama to zgłasza, więc statystyka 7 i 30 dni jest niepełna. Co dokładnie - w zakładce Szczegóły."
      }
    }
    default {
      $tytul = "MegaRuchacz: $($a.Krotko)"
      $porada = Porada-Ludzka $a.Pelny
    }
  }
  return Alarm "koszt-$($a.Temat)" $tytul $pelne $waga $porada
}

# Zolte INFORMACJE z rachunku (dzis: nadrabianie zaleglosci). Osobno od alarmow,
# bo alarmy ida takze na dymek - a informacja "to bylo jednorazowe" wyskakujaca
# w zasobniku jak ostrzezenie bylaby dokladnie tym, na co uzytkownik sie
# skarzyl 24.09.2026. W oknie stoja razem z alarmami, na zoltym tle.
function Zbierz-Informacje($rachunek) {
  $lista = @()
  if (-not $rachunek) { return ,$lista }
  $ocena = Ocena-Nauki $rachunek
  foreach ($a in (Alarmy-Rachunku $rachunek)) {
    if ($a.Waga -ne "info") { continue }
    $lista += Alarm-Z-Rachunku $a $ocena
  }
  return ,$lista
}

# STATYSTYKA NAUKI DO OKNA: 30 dni, jeden element na dzien kalendarza (takze
# dni bez nauki - wykres ma pokazac przerwe, a nie ja zwinac). Liczby i sumy
# pochodza z koszt-pamieci.ps1 -Dane, ktory czyta dziennik przebiegow
# (.koszt-historia.tsv) i podsumowanie (.koszt-podsumowanie.txt). Tu tylko
# rozkladamy je na dni i ubieramy w zdania.
#
# Malo danych to NIE jest pusty wykres bez slowa: Uwaga mowi wprost, ze
# statystyka dopiero sie zbiera i skad sa liczby.
function Statystyka-Okna($rachunek) {
  $s = [pscustomobject]@{
    Dni = @(); DniZDanymi = 0; OknoDni = 30; Zrodlo = ""; Powod = ""
    Suma7 = $null; Suma30 = $null; SumyZ = ""; Srednia = $null; SredniaDni = 0
    Typowy = $null; TypowychDni = 0; Prog = $null; Uwaga = ""
  }
  if ((-not $rachunek) -or (-not $rachunek.Klucze) -or ($rachunek.Klucze.Count -eq 0)) {
    $s.Powod = "nie udało się policzyć rachunku"
    if ($rachunek -and $rachunek.Powod) { $s.Powod = $rachunek.Powod }
    $s.Uwaga = "Statystyki nie ma, bo nie udało się policzyć rachunku. Powód jest w zakładce Szczegóły."
    return $s
  }
  $k = $rachunek.Klucze
  $okno = Liczba-Z-Klucza $k "stat.okno_dni"
  if (($null -ne $okno) -and ($okno -gt 0)) { $s.OknoDni = [int]$okno }
  $s.Zrodlo      = Tekst-Z-Klucza  $k "stat.zrodlo"
  $s.Powod       = Tekst-Z-Klucza  $k "stat.powod"
  $s.Suma7       = Liczba-Z-Klucza $k "stat.suma7"
  $s.Suma30      = Liczba-Z-Klucza $k "stat.suma30"
  $s.SumyZ       = Tekst-Z-Klucza  $k "stat.sumy_z"
  $s.Srednia     = Liczba-Z-Klucza $k "stat.srednia"
  $sd            = Liczba-Z-Klucza $k "stat.srednia_dni"
  if ($null -ne $sd) { $s.SredniaDni = [int]$sd }
  $s.Typowy      = Liczba-Z-Klucza $k "cykl.typowy_dzien"
  $td            = Liczba-Z-Klucza $k "cykl.typowych_dni"
  if ($null -ne $td) { $s.TypowychDni = [int]$td }
  $s.Prog        = Liczba-Z-Klucza $k "cykl.prog"

  $mapa = @{}
  $ile = Liczba-Z-Klucza $k "stat.dni"
  if ($null -eq $ile) { $ile = 0 }
  for ($i = 1; $i -le $ile; $i++) {
    $cz = @((Tekst-Z-Klucza $k "stat.dzien.$i") -split '\|')
    if ($cz.Count -lt 5) { continue }
    $mapa[$cz[0]] = $cz
  }
  $dzis = [datetime]::Today
  $dni = @()
  for ($i = $s.OknoDni - 1; $i -ge 0; $i--) {
    $d = $dzis.AddDays(-$i)
    $x = [pscustomobject]@{ Dzien = $d; Razem = [long]0; Zwykle = [long]0; Nadrabianie = [long]0; Nieznane = [long]0; Jest = $false }
    $klucz = $d.ToString('yyyy-MM-dd')
    if ($mapa.ContainsKey($klucz)) {
      $cz = $mapa[$klucz]
      $x.Razem       = Na-Liczbe $cz[1]
      $x.Zwykle      = Na-Liczbe $cz[2]
      $x.Nadrabianie = Na-Liczbe $cz[3]
      $x.Nieznane    = Na-Liczbe $cz[4]
      $x.Jest = $true
      $s.DniZDanymi++
    }
    $dni += $x
  }
  $s.Dni = $dni

  if ($s.DniZDanymi -eq 0) {
    if ($s.Zrodlo -eq "historia") {
      $s.Uwaga = "W ostatnich $($s.OknoDni) dniach nauka nie kosztowała nic - nie ma czego pokazać na wykresie."
    } else {
      $s.Uwaga = "Statystyka dopiero się zbiera: nie ma jeszcze historii kosztów nauki. Pierwszy słupek pojawi się po najbliższej nauce z rozmów."
    }
  } elseif ($s.Zrodlo -eq "plik-dnia") {
    $s.Uwaga = ("Historii przebiegów jeszcze nie ma - pokazuję tylko ostatni pomiar ($($s.DniZDanymi) " +
                "$(Odmiana $s.DniZDanymi 'dzień' 'dni' 'dni')). Statystyka rośnie z każdym dniem nauki.")
  } elseif ($s.DniZDanymi -lt 7) {
    $s.Uwaga = ("Statystyka dopiero się zbiera: $($s.DniZDanymi) $(Odmiana $s.DniZDanymi 'dzień' 'dni' 'dni') z danymi. " +
                "Rośnie z każdym dniem nauki.")
  }
  return $s
}

function Na-Liczbe($t) {
  $v = "$t".Trim()
  if ($v -match '^\d+$') { return [long]$v }
  return [long]0
}

# ZMIANY W PAMIECI Z OSTATNIEJ NAUKI. Pisze je modul pamieci (lore\lore\verify.py,
# report_lines) do ~\.claude\wiedza\.wiedza-stan.txt:
#   data: RRRR-MM-DD                     dzien przebiegu
#   meldunek: bez zmian                  gdy nic sie nie zmienilo - JEDNA linia
#   meldunek: zmienilem 1, uspilem 0, obudzilem 0, awansowalem 1 - cofniecie: ...
#   meldunek: UWAGA: 12 zmian, pokazuje 10 - ...; zmienilem ...   (lista przycieta)
#   meldunek_1: Z-260924-1 zmienilem: „stare” -> „nowe”
#   meldunek_2: A-260924-2 awansowalem: „fakt”
# Tu tylko czytamy - licznik bierzemy z naglowka, bo lista bywa przycieta.
#
# Trzy stany i kazdy mowi co innego, bo "nie wiem" to nie "zero":
#   Wiadomo = $false  -> nie ma pliku albo nie ma w nim meldunku; Powod mowi dlaczego
#   Ile = 0           -> modul pamieci sam napisal "bez zmian"
#   Ile > 0           -> Zmiany z identyfikatorami, po ktorych sie cofa
function Stan-Zmian-Pamieci {
  $z = [pscustomobject]@{
    Wiadomo  = $false
    Dzien    = $null       # dzien przebiegu nauki, z klucza "data"
    Ile      = $null
    Zmiany   = @()         # pscustomobject: Id, Tresc (surowa linia meldunku)
    Naglowek = ""          # surowy naglowek meldunku - do szczegolow, z komenda cofania
    Powod    = ""
    Plik     = (Join-Path $script:NadzWiedza ".wiedza-stan.txt")
  }
  if (-not (Test-Path $z.Plik)) {
    $z.Powod = "nauka nie zapisała jeszcze podsumowania na tym komputerze"
    return $z
  }
  $k = Czytaj-Klucze $z.Plik
  $z.Dzien = Data-Lub-Nic $k["data"]
  if (-not $k.Contains("meldunek")) {
    $z.Powod = "ostatnie podsumowanie nauki nie ma listy zmian (zapisała je starsza wersja)"
    return $z
  }
  $z.Naglowek = "$($k['meldunek'])"
  if ($z.Naglowek -match '^\s*bez zmian\s*$') {
    $z.Wiadomo = $true
    $z.Ile = 0
    return $z
  }

  # Linie meldunek_N po numerze, nie po kolejnosci w pliku - "meldunek_10"
  # alfabetycznie stoi przed "meldunek_2".
  $numery = @()
  foreach ($klucz in @($k.Keys)) {
    $m = [regex]::Match($klucz, '^meldunek_(\d+)$')
    if ($m.Success) { $numery += [int]$m.Groups[1].Value }
  }
  foreach ($n in @($numery | Sort-Object)) {
    $tresc = "$($k["meldunek_$n"])"
    $id = ""
    $m = [regex]::Match($tresc, '^\s*([A-Z]-\d{6}-\d+)\b')
    if ($m.Success) { $id = $m.Groups[1].Value }
    $z.Zmiany += [pscustomobject]@{ Id = $id; Tresc = $tresc.Trim() }
  }

  $m = [regex]::Match($z.Naglowek, '^\s*UWAGA:\s*(\d+)\s+zmian')
  $s = [regex]::Match($z.Naglowek, 'zmienilem\s+(\d+),\s*uspilem\s+(\d+),\s*obudzilem\s+(\d+),\s*awansowalem\s+(\d+)')
  if ($m.Success) {
    $z.Ile = [int]$m.Groups[1].Value
  } elseif ($s.Success) {
    $z.Ile = [int]$s.Groups[1].Value + [int]$s.Groups[2].Value + [int]$s.Groups[3].Value + [int]$s.Groups[4].Value
  } elseif ($z.Zmiany.Count -gt 0) {
    $z.Ile = $z.Zmiany.Count
  } else {
    $z.Powod = "meldunek nauki jest nieczytelny: $($z.Naglowek)"
    return $z
  }
  $z.Wiadomo = $true
  return $z
}

# Linia meldunku po ludzku: slowa z ogonkami i strzalka zamiast "->".
# Modul pamieci pisze bez ogonkow, bo to samo idzie do dziennika i do konsoli.
function Zmiana-Ludzko([string]$tresc) {
  $t = $tresc
  $t = $t -replace '^(\s*[A-Z]-\d{6}-\d+\s+)zmienilem:',   '$1zmieniłem:'
  $t = $t -replace '^(\s*[A-Z]-\d{6}-\d+\s+)uspilem:',     '$1uśpiłem:'
  $t = $t -replace '^(\s*[A-Z]-\d{6}-\d+\s+)obudzilem:',   '$1obudziłem:'
  $t = $t -replace '^(\s*[A-Z]-\d{6}-\d+\s+)awansowalem:', '$1przeniosłem do stałej pamięci:'
  $t = $t -replace '\s->\s', ' → '
  return $t
}

# To, co widac w sekcji stanu: jedna linia na wierzchu, pod nia (w oknie
# schowane pod "pokaz") linie zmian i JEDNO zdanie, jak cofnac - dla czlowieka,
# nie dla programisty. Cofanie idzie przez rozmowe z Claude'em (lore.verify
# --cofnij), przycisku "Cofnij" w oknie nie ma i nie ma byc: zmiana pamieci
# jednym kliknieciem bez potwierdzenia to ryzyko.
function Opis-Zmian-Pamieci($z) {
  $o = [pscustomobject]@{ Linia = ""; Zmiany = @(); Porada = ""; Uwaga = $false }
  if (-not $z) {
    $o.Linia = "Pamięć o Tobie i firmie: nie wiem, co się w niej zmieniło - nie udało się tego odczytać."
    $o.Uwaga = $true
    return $o
  }
  $kiedy = "dziś"
  if ($z.Dzien -and ($z.Dzien.Date -ne [datetime]::Now.Date)) {
    $kiedy = "przy ostatniej nauce ($(Dzien-Ludzko $z.Dzien))"
  }
  if (-not $z.Wiadomo) {
    $o.Linia = "Pamięć o Tobie i firmie ${kiedy}: nie wiem, co się zmieniło - $($z.Powod)."
    $o.Uwaga = $true
    return $o
  }
  if ($z.Ile -le 0) {
    $o.Linia = "Pamięć o Tobie i firmie ${kiedy}: bez zmian."
    return $o
  }
  $o.Linia = "Pamięć o Tobie i firmie ${kiedy}: $($z.Ile) $(Odmiana ([int]$z.Ile) 'zmiana' 'zmiany' 'zmian')."
  foreach ($x in $z.Zmiany) { $o.Zmiany += (Zmiana-Ludzko $x.Tresc) }
  if ($z.Zmiany.Count -lt $z.Ile) {
    $o.Zmiany += "... i jeszcze $($z.Ile - $z.Zmiany.Count) - pełna lista jest w historii zmian pamięci."
  }
  $przyklad = $null
  foreach ($x in $z.Zmiany) { if ($x.Id) { $przyklad = $x.Id; break } }
  if ($przyklad) {
    $o.Porada = "Coś się nie zgadza? Powiedz Claude'owi: cofnij zmianę $przyklad"
  } else {
    $o.Porada = "Coś się nie zgadza? Powiedz Claude'owi: cofnij dzisiejsze zmiany w pamięci"
  }
  return $o
}

# PRZELICZANIE ARCHIWUM (wymiana modelu wyszukiwania, ~2 h). Format pliku postepu
# NIE JEST JESZCZE USTALONY - pisze go inny kawalek narzedzia. Dlatego:
#   - szukamy pliku po wzorcu nazwy w ~\.claude i ~\.lore (bez rekurencji
#     w glab projects\, bo tam lezy ponad gigabajt transkryptow),
#   - gdy go nie ma: Plik = $null i okno NIC nie pokazuje,
#   - gdy jest: Plik ustawiony, ale Zrobione/Wszystkie zostaja puste, dopoki ktos
#     nie podepnie odczytu formatu TUTAJ. Zgadniety format pokazalby liczby,
#     ktorych nikt nie zmierzyl. Sciezka idzie do szczegolow, zeby nie byla cisza.
$WZORCE_PRZELICZANIA = @("*przelicz*", "*migracj*", "*reindex*")

function Postep-Przeliczania {
  $p = [pscustomobject]@{ Plik = $null; Zrobione = $null; Wszystkie = $null; Powod = "" }
  $katalogi = @(
    (Join-Path $script:NadzDom ".claude"),
    (Join-Path $script:NadzDom ".claude\wiedza"),
    (Join-Path $script:NadzDom ".lore")
  )
  # Plik postepu przeliczania archiwum na nowy model (lore\lore\migrate.py):
  # ~\.claude\lore.migration.json - pola state, done, total, eta_min.
  # Pokazujemy tylko gdy przeliczanie trwa; po skonczeniu linia znika sama.
  $mig = Join-Path $script:NadzDom ".claude\lore.migration.json"
  if (Test-Path $mig) {
    $p.Plik = $mig
    try {
      $j = [System.IO.File]::ReadAllText($mig, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
      if ($j.state -eq "running" -and $null -ne $j.done -and $null -ne $j.total) {
        $p.Zrobione = [int]$j.done
        $p.Wszystkie = [int]$j.total
        if ($null -ne $j.eta_min) { $p.Powod = "zostalo ok. $([int]$j.eta_min) min" }
      } else {
        $p.Powod = "przeliczanie nie trwa (stan: $($j.state))"
      }
    } catch {
      $p.Powod = "nie umiem odczytac pliku postepu: $($_.Exception.Message)"
    }
    return $p
  }
  foreach ($kat in $katalogi) {
    if (-not (Test-Path $kat)) { continue }
    foreach ($wz in $WZORCE_PRZELICZANIA) {
      $pliki = @(Get-ChildItem -Path $kat -Filter $wz -File -Force -ErrorAction SilentlyContinue |
                 Sort-Object LastWriteTime -Descending)
      if ($pliki.Count -gt 0) {
        $p.Plik = $pliki[0].FullName
        # TU PODPIAC odczyt formatu, gdy bedzie znany: ustawic $p.Zrobione i $p.Wszystkie.
        $p.Powod = "format pliku postępu nie jest jeszcze podpięty do okna"
        return $p
      }
    }
  }
  return $p
}

# STAN JEDNYM RZUTEM OKA - kilka krotkich zdan zamiast akapitow. Zadnych nazw
# plikow i zadnych sciezek: te sa pod [Szczegoly] i tam jest ich miejsce.
function Linie-Stanu($wersja, $cykl, $przeliczanie) {
  $linie = @()

  # Jedna linia i tylko wtedy, gdy postep naprawde odczytalismy - patrz
  # Postep-Przeliczania. Bez pliku albo bez podpietego formatu: nic.
  if ($przeliczanie -and ($null -ne $przeliczanie.Zrobione) -and ($null -ne $przeliczanie.Wszystkie)) {
    $linie += "Przeliczam archiwum: $(Liczba-Ludzka $przeliczanie.Zrobione) z $(Liczba-Ludzka $przeliczanie.Wszystkie)."
  }

  if ($cykl) {
    if ($cykl.Pracuje) {
      $linie += "Czytanie rozmów: właśnie trwa."
    } elseif ($cykl.Data) {
      $linie += "Ostatnie czytanie rozmów: $(Kiedy-Ludzko $cykl.Data)."
    } else {
      $linie += "Czytanie rozmów: jeszcze ani razu na tym komputerze."
    }

    if ($null -ne $cykl.Kawalki) {
      if ($cykl.Kawalki -le 0) {
        $linie += "Czeka na przeczytanie: nic - wszystkie rozmowy są już przeczytane."
      } else {
        $linie += "Czeka na przeczytanie: $(Liczba-Ludzka $cykl.Kawalki) $(Odmiana ([int]$cykl.Kawalki) 'kawałek' 'kawałki' 'kawałków') Twoich nowszych rozmów. Przeczyta je sam przy kolejnym codziennym czytaniu - nic nie musisz robić."
      }
    } elseif ($null -ne $cykl.Zaleglosc) {
      $linie += "Czeka na przeczytanie: teraz nie sprawdziłem; ostatnio zostawało $(Liczba-Ludzka $cykl.Zaleglosc) $(Odmiana ([int]$cykl.Zaleglosc) 'porcja' 'porcje' 'porcji') rozmów."
    } else {
      $linie += "Czeka na przeczytanie: nie wiem, nie dało się sprawdzić."
    }
  } else {
    $linie += "Czytanie rozmów: nie wiem, nie udało się odczytać jego stanu."
  }

  if ($wersja) {
    $w = "nieznana"
    if ($wersja.Lokalna) { $w = $wersja.Lokalna }
    if ($null -eq $wersja.Nowsza) {
      $powod = $wersja.Powod
      if (-not $powod) { $powod = "nie ustaliłem powodu - to samo w sobie jest usterką" }
      $linie += "Wersja MegaRuchacza: $w. Czy jest coś nowszego - nie wiem ($powod)."
    } elseif ($wersja.Nowsza -le 0) {
      $linie += "Wersja MegaRuchacza: $w, nic nowszego nie czeka."
    } else {
      $linie += "Wersja MegaRuchacza: $w. Czeka $($wersja.Nowsza) $(Odmiana ([int]$wersja.Nowsza) 'nowsza zmiana' 'nowsze zmiany' 'nowszych zmian') - pobierze je przycisk na dole."
    }
  } else {
    $linie += "Wersja MegaRuchacza: nie wiem, nie udało się jej odczytać."
  }

  return ,$linie
}

# Czerwony czy zolty. PROG Z UZASADNIENIEM, nie kolor z powietrza:
#   CZERWONY - cos jest zepsute albo kosztuje i jest konkretna rzecz do zrobienia
#              (nauka stoi, tekst jest ucinany, rachunek nad progiem, straznik sie wywrocil);
#   ZOLTY    - czegos NIE WIEMY i trzeba to sprawdzic, ale nic sie jeszcze nie pali;
#   ZOLTY "info" - wiemy, co sie stalo, i nic nie trzeba robic (np. nauka nadrabiala
#              zaleglosc). Waga niesiona przez sam alarm wygrywa z tym tematem.
# Wszystko inne zostaje neutralne. Tecza uczy ignorowania kolorow.
function Waga-Alarmu([string]$temat) {
  if ($temat -eq "rachunek") { return "uwaga" }
  return "pilne"
}

# Porada bez zargonu: zdania z komendami i sciezkami zostaja w [Szczegoly],
# na wierzchu stoi to, co uzytkownik moze zrobic sam. NIC NIE GINIE - pelna tresc
# alarmu jest zawsze w szczegolach, a gdyby po odsianiu nie zostalo ani jedno
# zdanie, oddajemy oryginal. Lepiej zargon niz pusta ramka.
function Porada-Ludzka([string]$tresc) {
  if (-not $tresc) { return "" }
  $ludzkie = @()
  $odsiane = 0
  foreach ($z in [regex]::Split($tresc, '(?<=\.)\s+')) {
    $t = "$z".Trim()
    if (-not $t) { continue }
    if ($t -match 'powershell\s+-ExecutionPolicy') { $odsiane++; continue }
    if ($t -match '\.ps1|\.log|\.db|\.txt|\.json|\\\.claude\\|\\narzedzia\\') { $odsiane++; continue }
    $ludzkie += $t
  }
  if ($ludzkie.Count -eq 0) { return $tresc }
  # Odsianie ma byc WIDOCZNE. Inaczej uzytkownik nie wie, ze jest ciag dalszy,
  # i nigdy go nie otworzy - a to jest dokladnie cicha strata tresci.
  if ($odsiane -gt 0) { $ludzkie += "Dokładna ścieżka i komenda są w szczegółach." }
  return ($ludzkie -join " ")
}

# Gorny limit porcji na JEDNO podejscie czytamy z pliku, ktory go USTALA.
# Wpisany tutaj na sztywno zaczalby klamac przy pierwszej zmianie cyklu - ta sama
# zasada, co przy sufitach w narzedzia\koszt-pamieci.ps1. $null znaczy
# "nie odczytalem" i wolajacy MA to powiedziec, a nie zgadnac.
function Max-Nadrabiania {
  $raw = Czytaj-Tekst (Join-Path $script:NadzZrodlo "narzedzia\cykl-dzienny.ps1")
  if (-not $raw) { return $null }
  $m = [regex]::Match($raw, '(?m)^\$MaxNadrabiania\s*=\s*(\d+)')
  if (-not $m.Success) { return $null }
  return [int]$m.Groups[1].Value
}

# SZACUNEK KOSZTU PRZED KLIKNIECIEM. Powstal dlatego, ze przycisk "Uruchom cykl"
# wydal 24.09.2026 jednym kliknieciem 312 609 tokenow, nie uprzedzajac o niczym.
#
# Skad ta liczba: (ile porcji pojdzie w tym podejsciu) x (ile kosztowalo jedno
# wyslanie przy POPRZEDNIM przebiegu). Oba czynniki sa ZMIERZONE - pierwszy liczy
# narzedzia\wyciagnij-fakty.ps1 -Kolejka (przebieg probny, bez wolania modelu,
# ~0,4 s), drugi stoi w .koszt-cyklu.txt, zapisany przez samo wylawianie. Zadnej
# stalej "tyle to mniej wiecej kosztuje" tu nie ma i nie ma byc.
#
# Gdy ktoregos czynnika brakuje, Tokeny zostaja puste, a w Powod stoi dlaczego.
# Okno mowi wtedy wprost "NIE WIEM, ile to bedzie kosztowac" i dalej pyta o zgode
# z podswietlonym "Nie" - koszt zgadniety bylby gorszy niz zaden.
function Szacunek-Cyklu($cykl) {
  $s = [pscustomobject]@{
    Tokeny   = $null      # szacunek calego podejscia
    NaPorcje = $null      # ile kosztowalo jedno wyslanie ostatnim razem
    Porcje   = $null      # ile porcji pojdzie TERAZ
    WKolejce = $null      # ile porcji czeka w sumie
    Kawalki  = $null
    Podstawa = @()        # zdania mowiace, z czego ta liczba wyszla
    Powod    = ""         # dlaczego nie umiem podac liczby
  }
  if (-not $cykl) {
    $s.Powod = "nie mam danych o kolejce ani o poprzednim przebiegu"
    return $s
  }
  $s.Kawalki  = $cykl.Kawalki
  $s.WKolejce = $cykl.Przebiegi

  if ($null -eq $cykl.Przebiegi) {
    $s.Powod = "nie dało się sprawdzić, ile rozmów czeka w kolejce"
  } elseif ($cykl.Przebiegi -le 0) {
    $s.Porcje = 0
    $s.Tokeny = 0
    $s.Podstawa += "Kolejka jest pusta - nie ma zaległych rozmów do przeczytania."
    return $s
  } else {
    $max = Max-Nadrabiania
    $s.Porcje = $cykl.Przebiegi
    $ile = "nieznaną liczbę fragmentów"
    if ($null -ne $cykl.Kawalki) {
      $ile = "$(Liczba-Ludzka $cykl.Kawalki) $(Odmiana ([int]$cykl.Kawalki) 'fragment' 'fragmenty' 'fragmentów')"
    }
    $s.Podstawa += "Czeka $ile rozmów, czyli $($cykl.Przebiegi) $(Odmiana ([int]$cykl.Przebiegi) 'porcja' 'porcje' 'porcji') do wysłania."
    if ($null -eq $max) {
      $s.Podstawa += "Nie odczytałem, ile porcji bierze jedno podejście - liczę tak, jakby poszły wszystkie naraz."
    } elseif ($cykl.Przebiegi -gt $max) {
      $s.Porcje = $max
      $s.Podstawa += "Jedno podejście bierze najwyżej $max $(Odmiana ([int]$max) 'porcję' 'porcje' 'porcji') - reszta poczeka do następnego razu."
    }
  }

  if (($null -ne $cykl.Koszt) -and ($null -ne $cykl.KosztWywolan) -and ($cykl.KosztWywolan -gt 0)) {
    $s.NaPorcje = [long][math]::Round([double]$cykl.Koszt / [double]$cykl.KosztWywolan)
    $kiedy = "ostatnim razem"
    if ($cykl.KosztData) { $kiedy = $cykl.KosztData.ToString('dd.MM') }
    $s.Podstawa += ("Jedno wysłanie kosztowało ostatnio ~$(Liczba-Ludzka $s.NaPorcje) tokenów " +
                    "(${kiedy}: $(Liczba-Ludzka $cykl.Koszt) tokenów na $($cykl.KosztWywolan) $(Odmiana ([int]$cykl.KosztWywolan) 'wywołanie' 'wywołania' 'wywołań')).")
  } elseif (-not $s.Powod) {
    $s.Powod = "nie ma pomiaru poprzedniego przebiegu, więc nie mam po czym szacować"
  }

  if (($null -ne $s.Porcje) -and ($null -ne $s.NaPorcje)) {
    $s.Tokeny = [long]($s.Porcje * $s.NaPorcje)
  }
  return $s
}

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["po-ludzku"] = $true
