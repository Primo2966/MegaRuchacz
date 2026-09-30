# zasobnik\nadzorca\przeglad-tresc.ps1 - czesc zasobnik\nadzorca.ps1 (patrz BUDOWA
# w jego naglowku). Tresc zakladki Przeglad wspolna dla okna i dla wydrukow -Raz
# i -Raport: jedna lista spraw wymagajacych uwagi (Zbierz-Problemy, Problem,
# Waga-Z-Alarmu, Porada-Z-Alarmu, Ile-Wymaga-Uwagi), napisy przyciskow z szacunkiem
# kosztu (Napisy-Przyciskow) i Przeglad jako tekst (Zbuduj-Przod, Skladniki-Mr,
# Linie-Statystyki, Tokeny-Albo-Brak, Koszt-Po-Ludzku, Zdanie-Progu).
# Skad wolane: tryby -Raz i -Raport w nadzorca.ps1, karty w przeglad.ps1 (Odmaluj-*),
# przyciski w okno.ps1, sekcje w szczegoly.ps1. Wczytuje go nadzorca.ps1 kropka
# PRZED trybami bez GUI - tu sa same definicje, nic sie nie liczy.

# ------------------------------------------------------- co wymaga uwagi TERAZ

function Problem([string]$waga, [string]$tytul, [string]$porada, [string]$pelne) {
  return [pscustomobject]@{ Waga = $waga; Tytul = $tytul; Porada = $porada; Pelne = $pelne }
}

# Tytuly alarmow zaczynaja sie od "MegaRuchacz: ", bo ida takze na dymek, gdzie
# trzeba powiedziec, kto wola. W oknie MegaRuchacza ten przedrostek jest szumem.
function Bez-Przedrostka([string]$tytul) {
  if (-not $tytul) { return "" }
  return ($tytul -replace '^\s*MegaRuchacz\s*:\s*', '')
}

# JEDNA lista spraw wymagajacych uwagi - ta sama dla okna i dla wydruku -Raport,
# zeby nie dalo sie ich rozjechac. Pusta lista znaczy "nic sie nie pali" i wtedy
# w oknie ta sekcja W OGOLE NIE ISTNIEJE, a nie stoi pusta.
#
# Cisza jest zakazana, wiec na liscie sa nie tylko alarmy, ale tez KAZDY powod,
# dla ktorego liczby moga byc niepelne: nieudane odswiezenie, brak rachunku albo
# stanu cyklu, wywrotka z poprzedniego przebiegu. Stare liczby pokazane jako
# biezace byly przez tydzien najdrozszym bledem tego narzedzia.
function Zbierz-Problemy($d, $wywrotki, [string]$blad, $czasDanych) {
  $lista = @()

  if ($blad) {
    $ogon = "Nie mam żadnych świeżych liczb do pokazania."
    if ($czasDanych) { $ogon = "Liczby niżej są sprzed $($czasDanych.ToString('HH:mm')) i mogą być nieaktualne." }
    $lista += Problem "uwaga" "Nie udało się przeliczyć liczb" $ogon $blad
  }

  if ($d) {
    foreach ($a in @($d.Alarmy)) {
      $lista += Problem (Waga-Z-Alarmu $a) (Bez-Przedrostka $a.Tytul) (Porada-Z-Alarmu $a) $a.Tresc
    }
    # Informacje (np. "nauka nadrabiala zaleglosc") stoja w oknie razem z alarmami,
    # na zoltym tle, ale z dopiskiem, ze nic nie trzeba robic - i nie ida na dymek.
    foreach ($a in @($d.Informacje)) {
      $lista += Problem "info" (Bez-Przedrostka $a.Tytul) (Porada-Z-Alarmu $a) $a.Tresc
    }
    if ((-not $d.Rachunek) -or (-not $d.Cykl)) {
      $lista += Problem "uwaga" "Nie wszystko udało się odczytać" (
        "Część liczb w tym oknie może być niepełna, a alarmów w ogóle nie policzyłem. " +
        "Otwórz zakładkę Szczegóły - tam stoi, czego zabrakło.") ""
    }
  } else {
    $lista += Problem "uwaga" "Nie mam jeszcze żadnych liczb" (
      "Nic się nie policzyło. Otwórz zakładkę Szczegóły albo zajrzyj do dziennika nadzorcy.") ""
  }

  if (@($wywrotki).Count -gt 0) {
    $lista += Problem "uwaga" "Przy poprzednim przebiegu coś się nie udało" (
      "MegaRuchacz potknął się w tle. Pełna treść jest w zakładce Szczegóły.") ((@($wywrotki)) -join " | ")
  }

  # Skille (P18): nieudane albo dawno niewykonane codzienne sprawdzenie - sam plik
  # znacznika, bez wolania skryptu.
  try {
    foreach ($p in (Problemy-Skilli)) { $lista += Problem $p.Waga $p.Tytul $p.Porada $p.Pelne }
  } catch { Zanotuj-Wywrotke "odczyt znacznika skilli" $_ }

  # Czerwone przed zoltymi, zolte przed informacjami: pierwsza rzecz na ekranie
  # ma byc ta, ktora naprawde czegos wymaga, a nie ta, ktorej akurat nie wiemy.
  $lista = @($lista | Sort-Object -Property @{ Expression = { Kolejnosc-Wagi $_.Waga } })
  return ,$lista
}

function Kolejnosc-Wagi([string]$waga) {
  if ($waga -eq "pilne") { return 0 }
  if ($waga -eq "info") { return 2 }
  return 1
}

# Waga niesiona przez sam alarm wygrywa; bez niej - wedlug tematu, jak dotad.
function Waga-Z-Alarmu($a) {
  if ($a.Waga) { return $a.Waga }
  return (Waga-Alarmu $a.Temat)
}

# Porada gotowa (alarmy kosztu mowia same, za co i za jaki okres) albo odsiana
# z tresci bez sciezek i komend, jak dotad.
function Porada-Z-Alarmu($a) {
  if ($a.Porada) { return $a.Porada }
  return (Porada-Ludzka $a.Tresc)
}

# Ile spraw naprawde wymaga uwagi - informacje sie nie licza. Od tego zalezy,
# czy w oknie stoi "Wszystko gra".
function Ile-Wymaga-Uwagi($problemy) {
  return @(@($problemy) | Where-Object { $_ -and ($_.Waga -ne "info") }).Count
}

# ------------------------------------------------------------- napisy przyciskow

# Napisy powstaja TUTAJ, w jednym miejscu, i ten sam tekst widzi uzytkownik
# w oknie oraz w wydruku -Raport. Gdyby powstawaly osobno, wydruk mowilby
# o przycisku, ktorego w oknie nie ma - a tak wlasnie zaczyna sie nieufnosc
# do narzedzia.
#
# Etykieta przycisku, ktory wydaje tokeny, NIESIE SZACUNEK KOSZTU. Uzytkownik ma
# zobaczyc liczbe zanim kliknie, a nie dowiedziec sie o niej z rachunku nazajutrz.
#
# P17 (28.09.2026): koszt na przycisku w TOKENACH. Procent otwarcia okna
# rozmowy (P15) nic uzytkownikowi nie mowil przy koszcie dziennym; porownanie
# z calym dziennym zuzyciem ($zuzycie = Zuzycie-Dzienne) stoi w pytaniu o zgode.
# Bez slowa "zalegle": czytanie i tak idzie samo raz dziennie, przycisk robi to
# tylko wczesniej - i opis mowi to wprost.
function Napisy-Przyciskow($d, $zuzycie = $null) {
  $n = [pscustomobject]@{
    Aktualizuj     = "Sprawdź i pobierz nowszą wersję MegaRuchacza"
    AktualizujOpis = "Nie kosztuje nic. Zagląda na serwer po poprawki i nanosi je."
    Cykl           = "Przeczytaj teraz nowe rozmowy"
    CyklOpis       = "Nie musisz - MegaRuchacz robi to sam raz dziennie. Zapyta o zgodę."
    CyklWlaczony   = $true
    Szacunek       = $null
  }

  if ($d -and $d.Wersja -and ($null -ne $d.Wersja.Nowsza) -and ($d.Wersja.Nowsza -gt 0)) {
    $n.Aktualizuj = "Pobierz nowszą wersję MegaRuchacza ($($d.Wersja.Nowsza) do pobrania)"
  }

  $s = $null
  if ($d) {
    try { $s = Szacunek-Cyklu $d.Cykl }
    catch { Zanotuj-Wywrotke "szacunek kosztu czytania rozmow" $_ }
  }
  $n.Szacunek = $s

  if ($d -and $d.Cykl -and $d.Cykl.Pracuje) {
    # Drugi przebieg w tej samej chwili nic nie da, a kosztowalby drugi raz.
    $n.CyklWlaczony = $false
    $n.CyklOpis = "Wyłączone: czytanie rozmów właśnie trwa. Liczby odświeżą się same, gdy skończy."
  } elseif (-not $s) {
    $n.Cykl = "Przeczytaj teraz nowe rozmowy (koszt: nie wiem)"
    $n.CyklOpis = "Nie musisz - robi to sam raz dziennie. Nie mam danych, żeby oszacować koszt; przed startem zapyta o zgodę."
  } elseif (($null -ne $s.Porcje) -and ($s.Porcje -le 0)) {
    $n.CyklWlaczony = $false
    $n.CyklOpis = "Wyłączone: nic nie czeka, wszystkie rozmowy są już przeczytane."
  } elseif ($null -ne $s.Tokeny) {
    $n.Cykl = "Przeczytaj teraz nowe rozmowy ($(Tokeny-Okolo $s.Tokeny) tokenów)"
    $n.CyklOpis = "Nie musisz - robi to sam raz dziennie. Zapyta o zgodę i pokaże, skąd ta liczba."
  } else {
    $n.Cykl = "Przeczytaj teraz nowe rozmowy (koszt: nie wiem)"
    $n.CyklOpis = "Nie umiem oszacować kosztu: $($s.Powod). Przed startem zapyta o zgodę."
  }
  return $n
}

# ----------------------------------------------------------- wydruk tego, co widac

# Czesc MegaRuchacza rozpisana na dwa kawalki, ktore laik rozroznia (P14,
# 28.09.2026). Do tej pory te same liczby staly drugi raz w dwoch kafelkach pod
# karta ("dokleja do kazdej wiadomosci", "doklada na otwarcie sesji") i
# uzytkownik pytal, czym to sie rozni. Teraz stoja TYLKO tu, w tej samej mierze
# co reszta Przegladu: procent jednego otwarcia sesji. Liczby z pomiaru -Start,
# niczego nie przeliczamy; brak liczby to "nie wiem", nigdy zero.
function Skladniki-Mr($start, $o) {
  $lista = @()
  if (-not $start -or -not $o -or -not $o.Zmierzone) { return ,$lista }
  foreach ($x in @(
      @("raz na start rozmowy: zasady i wiedza o Tobie i firmie", $start.MrStart, "", ""),
      @("przy każdej Twojej wiadomości: przypomnienie zasad", $start.MrWiadomosc, "+", "stała dopłata - tyle samo, czy piszesz dwa słowa, czy długi tekst"))) {
    $liczba = "nie wiem"; $proc = ""
    if ($null -ne $x[1]) {
      $liczba = "$($x[2])$(Liczba-Ludzka ([long]$x[1]))"
      $proc = Procent-Drobny ([double]$x[1]) ([double]$o.Razem)
    }
    $uw = ""
    if ($null -ne $x[1]) { $uw = $x[3] }
    $lista += [pscustomobject]@{ Napis = $x[0]; Liczba = $liczba; Proc = $proc; Uwaga = $uw }
  }
  return ,$lista
}

# Przod okna jako tekst: dokladnie te sekcje i w tej samej kolejnosci, co
# w oknie. Ten wydruk jest jedynym sposobem sprawdzenia ukladu bez pulpitu.
function Zbuduj-Przod($d, $problemy, $czas, $start, $zuzycie = $null, $koszt = $null) {
  $l = @()
  $l += "MegaRuchacz - nadzorca                      [ Przegląd | Szczegóły | Warstwy pamięci ]   <- przełącznik widoków u góry okna"
  $stempel = "przed chwilą"
  if ($czas) { $stempel = $czas.ToString('yyyy-MM-dd HH:mm:ss') }
  $l += "liczby sprawdzone: $stempel  (okno odświeża je samo w tle co $Minut min; starsze niż dzisiejsze liczy od nowa przy otwarciu)"
  $l += ""

  $l += "WERDYKT   (w oknie: pierwsza karta, duże zdanie - zielone: mało, czerwone: dużo, żółte: nie wiadomo)"
  $wd = $null
  try { $wd = Werdykt-Kosztu $start $(if ($d) { $d.Rachunek } else { $null }) $(if ($d) { $d.Cykl } else { $null }) $zuzycie }
  catch { Zanotuj-Wywrotke "werdykt do wydruku" $_ }
  if (-not $wd) {
    $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy"
  } else {
    $l += "  [$($wd.Stan)] $($wd.Zdanie)"
    if ($wd.Wyjasnienie) { $l += "  $($wd.Wyjasnienie)" }
    if ($wd.Nauka) { $l += "  $($wd.Nauka)" }
  }
  $l += ""

  $wazne =@(@($problemy) | Where-Object { $_.Waga -ne "info" })
  $info  = @(@($problemy) | Where-Object { $_.Waga -eq "info" })
  if (($wazne.Count -eq 0) -and ($info.Count -eq 0)) {
    $l += "CO WYMAGA UWAGI"
    $l += "  nic - w oknie tej sekcji wtedy w ogóle nie ma i nie zajmuje miejsca"
    $l += ""
  }
  if ($wazne.Count -gt 0) {
    $l += "CO WYMAGA UWAGI   (w oknie: karty na samej górze, czerwone [!] albo żółte [?])"
    foreach ($p in $wazne) {
      $znak = "[?]"
      if ($p.Waga -eq "pilne") { $znak = "[!]" }
      $l += "  $znak $($p.Tytul)"
      if ($p.Porada) { $l += "      $($p.Porada)" }
    }
    $l += ""
  }
  if ($info.Count -gt 0) {
    $l += "WARTO WIEDZIEĆ   (w oknie: żółta karta z dopiskiem 'dla informacji - nic nie trzeba robić', bez dymka)"
    foreach ($p in $info) {
      $l += "  [i] $($p.Tytul)"
      if ($p.Porada) { $l += "      $($p.Porada)" }
    }
    $l += ""
  }

  $l += "ILE TOKENÓW NAPRAWDĘ ZUŻYWASZ   (w oknie: karta pod werdyktem - trzy kolumny obok siebie)"
  $tk = $null
  try { $tk = Teksty-Kosztu $koszt $zuzycie } catch { Zanotuj-Wywrotke "prawdziwy koszt do wydruku" $_ }
  if (-not $tk) {
    $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy"
  } elseif ($tk.Powod) {
    $l += "  $($tk.Powod)  (żółty napis)"
  } else {
    foreach ($r in $tk.Tabela) { $l += ("  {0,-16} {1,-18} {2}" -f $r[0], $r[1], $r[2]) }
    if ($tk.Udzial) { $l += "  $($tk.Udzial)$(if ($tk.UdzialUwaga) { '  (żółty napis)' })" }
    $l += "  | $($tk.NaglowekWorkerow)"
    foreach ($x in $tk.Workerzy) { $l += ("  |   {0,9}  {1}  ({2})" -f $x.Tokeny, $x.Opis, $x.Dopisek) }
    if ($tk.WorkerzyPusto) { $l += "  |   $($tk.WorkerzyPusto)" }
    $l += "  | $($tk.NaglowekRozmow)"
    foreach ($x in $tk.Rozmowy) { $l += ("  |   {0}{1,9}  {2}  ({3})" -f $(if ($x.Dluga) { "! " } else { "  " }), $x.Rozmiar, $x.Tytul, $x.Dopisek) }
    if ($tk.RozmowyPusto) { $l += "  |   $($tk.RozmowyPusto)" }
    $l += "  $($tk.Stopka)   (drobnym drukiem)"
  }
  $l += ""

  $l += "OTWARCIE OKNA ROZMOWY   (w oknie: karta z dużą liczbą i paskiem - MegaRuchacz kontra sam Claude Code)"
  $os = $null
  try { $os = Opis-Startu $start } catch { Zanotuj-Wywrotke "otwarcie okna rozmowy do wydruku" $_ }
  if (-not $os) {
    $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy"
  } elseif (-not $os.Zmierzone) {
    $l += "  nie zmierzono, bo $($os.Powod)."
    if ($null -ne $os.Mr) { $l += "  sama część MegaRuchacza (z rachunku): ~$(Liczba-Ludzka $os.Mr) tokenów - procentu nie ma, bo nie ma całości" }
  } else {
    $l += "  Otwarcie okna rozmowy: ~$(Okolo $os.Razem) tokenów. Z tego MegaRuchacz: $(Okolo $os.Mr) ($($os.MrProc)) · Claude Code sam: $(Okolo $os.Cc) ($($os.CcProc))"
    foreach ($sk in (Skladniki-Mr $start $os)) { $l += "      $($sk.Napis): $($sk.Liczba)   ($($sk.Proc))" }
    $zw = Zdanie-Wiadomosci $start
    if ($zw) { $l += "      $zw" }
    $l += "  $($os.Portfel)"
    $l += "  $($os.Podstawa) $($os.Zakres)   (drobnym drukiem)"
  }
  $l += ""

  $l += "NAUKA Z ROZMÓW   (w oknie: karta na całą szerokość pod otwarciem okna rozmowy)"
  $r = $null; $c = $null
  if ($d) { $r = $d.Rachunek; $c = $d.Cykl }
  $trzy = @()
  try { $trzy = @(Liczba-Nauki $r $c) }
  catch { Zanotuj-Wywrotke "koszt nauki do wydruku" $_; $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy" }
  foreach ($t in $trzy) {
    $l += "  | $($t.Naglowek)"
    if ($null -ne $t.Liczba) {
      $tn = Teksty-Nauki $t $zuzycie
      $l += "  |   $($tn.Duza)  (duża liczba w oknie)  $($tn.Jednostka)"
      if ($t.Znacznik) {
        $zn = "[$($t.Znacznik)]"
        if ($t.ZnacznikWaga -eq "pilne") { $zn = "$zn  (czerwony napis)" }
        elseif ($t.ZnacznikWaga) { $zn = "$zn  (żółty napis)" }
        $l += "  |   $zn"
      }
      $l += "  |   $($tn.Porownanie)$(if (-not $tn.PorownanieJest) { '  (żółty napis)' })"
      if ($tn.Drobny) { $l += "  |   $($tn.Drobny)   (drobnym drukiem)" }
    } else {
      $l += "  |   nie wiem - $($t.Powod)"
    }
    $l += "  |   $($t.Opis)"
  }
  $l += ""

  $st = $null
  try { $st = Statystyka-Okna $r }
  catch { Zanotuj-Wywrotke "statystyka nauki do wydruku" $_ }
  $l += "KOSZT CZYTANIA ROZMÓW - OSTATNIE 30 DNI   (w oknie: dalszy ciąg karty nauki, wykres słupkowy w tysiącach tokenów - $(Opis-Rysownika))"
  if (-not $st) {
    $l += "  NIE UDALO SIE ZLOZYC STATYSTYKI - szczegoly w dzienniku nadzorcy"
  } else {
    $l += Linie-Statystyki $st $r $zuzycie
  }
  $l += ""

  $l += "STAN   (w oknie: karta z dwiema kolumnami - co i jak)"
  if ((Ile-Wymaga-Uwagi $problemy) -eq 0) { $l += "  Wszystko gra - nic nie wymaga Twojej uwagi." }
  $linie = @()
  if ($d) {
    try { $linie = Linie-Stanu $d.Wersja $d.Cykl $d.Przeliczanie }
    catch { Zanotuj-Wywrotke "linie stanu do wydruku" $_; $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy" }
  }
  foreach ($x in $linie) { $l += "  $x" }
  $pm = $null
  try { $pm = Opis-Zmian-Pamieci $(if ($d) { $d.Pamiec } else { $null }) }
  catch { Zanotuj-Wywrotke "zmiany w pamieci do wydruku" $_; $l += "  NIE UDALO SIE ZLOZYC ZMIAN W PAMIECI - szczegoly w dzienniku nadzorcy" }
  if ($pm) {
    $l += "  $($pm.Linia)"
    if (@($pm.Zmiany).Count -gt 0) {
      $l += "      (w oknie schowane pod [pokaż zmiany])"
      foreach ($x in $pm.Zmiany) { $l += "      $x" }
    }
    if ($pm.Porada) { $l += "      $($pm.Porada)" }
  }
  $l += ""

  $l += "PRZYCISKI W OKNIE - co się stanie po kliknięciu"
  $n = Napisy-Przyciskow $d $zuzycie
  $l += "  [$($n.Aktualizuj)]"
  $l += "      $($n.AktualizujOpis)"
  $wl = ""
  if (-not $n.CyklWlaczony) { $wl = "  (przycisk nieaktywny)" }
  $l += "  [$($n.Cykl)]$wl"
  $l += "      $($n.CyklOpis)"
  if ($n.Szacunek) { foreach ($z in $n.Szacunek.Podstawa) { $l += "      $z" } }
  $l += "  [Przegląd] / [Szczegóły] / [Warstwy pamięci]  (przełącznik u góry)"
  $l += "      Szczegóły i warstwy - z czego to się składa i gdzie to leży - zajmują miejsce przeglądu. Nic nie uruchamiają i nic nie kosztują."
  $l += "  [Zamknij okno]"
  $l += "      Okno znika, ikona w zasobniku zostaje i pilnuje dalej."
  return ,$l
}

# Statystyka jako tekst: to samo, co wykres w oknie, tylko paskami ze znakow.
# Sluzy wydrukowi -Raport, czyli sprawdzeniu bez pulpitu.
function Linie-Statystyki($st, $rachunek, $zuzycie = $null) {
  $l = @()
  $zDanymi = @(@($st.Dni) | Where-Object { $_.Jest })
  if ($zDanymi.Count -gt 0) {
    $max = [long]1
    foreach ($x in $zDanymi) { if ($x.Razem -gt $max) { $max = $x.Razem } }
    foreach ($x in $zDanymi) {
      $dl = [int][math]::Round(30.0 * $x.Razem / $max)
      $pasek = ("#" * [math]::Max(0, $dl))
      if (($x.Razem -gt 0) -and ($dl -lt 1)) { $pasek = "|" }
      $rodzaj = @()
      if ($x.Zwykle -gt 0)      { $rodzaj += "zwykły dzień" }
      if ($x.Nadrabianie -gt 0) { $rodzaj += "rozmowy z kilku dni" }
      if ($x.Nieznane -gt 0)    { $rodzaj += "nie wiadomo, z których dni" }
      $l += ("  {0}  {1,-30}  {2,9}  {3}" -f $x.Dzien.ToString('dd.MM'), $pasek, (Liczba-Ludzka $x.Razem), ($rodzaj -join " + "))
    }
  } else {
    $l += "  (wykres bez słupków - w oknie w jego miejscu stoi zdanie niżej)"
  }
  $l += ("  Ostatnie 7 dni: {0}   |   ostatnie {1} dni: {2}" -f (Koszt-Po-Ludzku $st.Suma7), $st.OknoDni, (Koszt-Po-Ludzku $st.Suma30))
  if ($null -ne $st.Srednia) {
    $l += ("  Średnio na dzień nauki: {0} (z {1} {2})" -f (Koszt-Po-Ludzku $st.Srednia), $st.SredniaDni, (Odmiana $st.SredniaDni 'dnia' 'dni' 'dni'))
  } else {
    $l += "  Średnio na dzień nauki: jeszcze nie wiem"
  }
  if (($null -ne $st.Typowy) -and ($st.TypowychDni -gt 0)) {
    $l += ("  Zwykły dzień (rozmowy z poprzedniego dnia): {0} - typowa wartość z {1} {2}" -f (Koszt-Po-Ludzku $st.Typowy), $st.TypowychDni, (Odmiana $st.TypowychDni 'dnia' 'dni' 'dni'))
  } else {
    $l += "  Zwykły dzień (rozmowy z poprzedniego dnia): jeszcze nie wiem - w historii nie ma ani jednego takiego dnia"
  }
  if ($null -ne $st.Prog) {
    $l += "  $(Zdanie-Progu $st $zuzycie)  (w oknie przerywana czerwona linia, gdy mieści się w skali)"
  }
  if ($st.Uwaga) { $l += "  $($st.Uwaga)" }
  return ,$l
}

function Tokeny-Albo-Brak($n) {
  if ($null -eq $n) { return "brak danych" }
  return "~$(Liczba-Ludzka $n) tokenów"
}

# "~40 000 tokenów (40 477)" - od P17 koszt nauki wszedzie w tokenach; procent
# otwarcia okna rozmowy przy koszcie dziennym nic nie mowil.
function Koszt-Po-Ludzku($n) {
  if ($null -eq $n) { return "brak danych" }
  return "$(Tokeny-Okolo $n) tokenów ($(Liczba-Ludzka $n))"
}

# Prog zwyklego dnia (z koszt-pamieci.ps1, cykl.prog) po ludzku: "tu zaczyna
# sie drogo" w tokenach i - gdy jest z czym porownac - jako udzial w calym
# dziennym zuzyciu. Liczba progu idzie z rachunku, tu tylko ja ubieramy w slowa.
function Zdanie-Progu($st, $zuzycie = $null) {
  if (-not $st -or ($null -eq $st.Prog)) { return "" }
  $t = "Drogo dopiero od $(Tokeny-Okolo $st.Prog) tokenów za zwykły dzień"
  if ($zuzycie -and ($zuzycie.Stan -eq "jest")) { $t += " ($(Procent-Udzialu ([double]$st.Prog) ([double]$zuzycie.Srednia)) dziennego zużycia)" }
  return "$t."
}

# Znacznik dla nadzorca.ps1: ten plik wczytal sie do konca.
$script:ModulyOkna["przeglad-tresc"] = $true
