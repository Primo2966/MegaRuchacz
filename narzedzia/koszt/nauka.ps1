# narzedzia\koszt\nauka.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz BUDOWA
# w jego naglowku). Trzeci rachunek - nauka z rozmow (cykl wiedzy), jedyne miejsce,
# w ktorym naprawde wola sie model: pliki "klucz: wartosc" (Klucze-Z-Tekstu,
# Klucz-Tekst, Klucz-Liczba), koszt cyklu za dzis i dzien poprzedni (Koszt-Cyklu),
# dziennik przebiegow i ocena dnia (Czytaj-Historie, Dni-Historii, Ocena-Cyklu,
# Statystyka-Nauki) oraz zdania o tym (Zdanie-Typowego-Dnia, Opis-Rodzaju).
# Skad wolane: etap Etap-Ocena (alarmy.ps1), tryby -Dane i -Rozbicie, pelny raport.
# Wczytuje go koszt-pamieci.ps1 kropka przy starcie - same definicje.

# --- koszt cyklu wiedzy ------------------------------------------------------
# Cykl dzienny (narzedzia\cykl-dzienny.ps1) wola model, zeby wylowic fakty
# z wczorajszych rozmow. To JEDYNE miejsce w calym narzedziu, w ktorym naprawde
# wydaja sie tokeny uzytkownika - reszta tego raportu to tekst doklejany do
# rozmowy, a nie wywolanie. Cykl zostawia po sobie plik "klucz: wartosc", w tym
# samym formacie co pozostale pliki stanu, z liczbami za dzis i za dzien
# poprzedni (klucze z przedrostkiem "poprzedni.").
#
# Braku pliku NIE traktujemy jak awarii: znaczy on tyle, ze cykl ani razu
# jeszcze nie policzyl kosztu - i tak wlasnie ma to byc napisane w raporcie.

function Klucze-Z-Tekstu($raw) {
  $stan = @{}
  if (-not $raw) { return $stan }
  foreach ($l in ($raw -split '\r?\n')) {
    $m = [regex]::Match($l, '^\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*:\s*(.*?)\s*$')
    if ($m.Success) { $stan[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $stan
}

function Klucz-Tekst($stan, $klucz) {
  if (-not $stan) { return $null }
  if (-not $stan.ContainsKey($klucz)) { return $null }
  $v = ("" + $stan[$klucz]).Trim()
  if (-not $v) { return $null }
  return $v
}

function Klucz-Liczba($stan, $klucz) {
  # $null zamiast zera przy braku i przy smieciu: zero znaczyloby "nic nie
  # kosztowalo", a to zupelnie co innego niz "cykl tego nie podal"
  $v = Klucz-Tekst $stan $klucz
  if ($null -eq $v) { return $null }
  $cyfry = ($v -replace '[^\d]', '')
  if (-not $cyfry) { return $null }
  return [long]$cyfry
}

function Lub-Nieznane($n) {
  if ($null -eq $n) { return "nie wiadomo" }
  return (Liczba $n)
}

function Kiedy-Cykl($wiek) {
  if ($null -eq $wiek) { return "" }
  if ($wiek -eq 0) { return "dzis" }
  if ($wiek -eq 1) { return "wczoraj" }
  return "$wiek dni temu"
}

function Opis-Zrodla($zrodlo) {
  if ($zrodlo -eq "pomiar")   { return "Tokeny to POMIAR - liczby pochodza od samego narzedzia AI." }
  if ($zrodlo -eq "szacunek") { return "Tokeny to SZACUNEK - przeliczone ze znakow, nie zmierzone." }
  if (-not $zrodlo)           { return "Cykl nie powiedzial, czy to pomiar, czy szacunek - traktuj te liczbe ostroznie." }
  return "Zrodlo liczby tokenow podane przez cykl: $zrodlo."
}

function Dzien-Cyklu($stan, $przedrostek) {
  # Jeden dzien pracy cyklu. $null, gdy pod tym przedrostkiem nie ma nic
  # sensownego - tak poznajemy, ze poprzedniego dnia po prostu jeszcze nie bylo.
  $data      = Klucz-Tekst  $stan "${przedrostek}data"
  $wywolania = Klucz-Liczba $stan "${przedrostek}wywolania"
  $tokeny    = Klucz-Liczba $stan "${przedrostek}tokeny"
  if (($null -eq $data) -and ($null -eq $wywolania) -and ($null -eq $tokeny)) { return $null }
  $wiek = $null
  if ($data) {
    try {
      $d = [datetime]::ParseExact($data, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
      $wiek = ([datetime]::Today - $d).Days
    } catch { $wiek = $null }
  }
  return [pscustomobject]@{
    Data          = $data
    Wiek          = $wiek
    Narzedzie     = (Klucz-Tekst  $stan "${przedrostek}narzedzie")
    Wywolania     = $wywolania
    ZnakiWyslane  = (Klucz-Liczba $stan "${przedrostek}znaki_wyslane")
    ZnakiOdebrane = (Klucz-Liczba $stan "${przedrostek}znaki_odebrane")
    Tokeny        = $tokeny
    Zrodlo        = (Klucz-Tekst  $stan "${przedrostek}tokeny_zrodlo")
    Fakty         = (Klucz-Liczba $stan "${przedrostek}fakty")
    # Za jaki okres: ile wiadomosci i z jakiego przedzialu czasu nauka czytala.
    # Bez tego drogi dzien nadrabiania wygladal jak nowa norma (24.09.2026).
    Wiadomosci    = (Klucz-Liczba $stan "${przedrostek}wiadomosci")
    ZakresOd      = (Klucz-Tekst  $stan "${przedrostek}zakres_od")
    ZakresDo      = (Klucz-Tekst  $stan "${przedrostek}zakres_do")
  }
}

function Koszt-Cyklu($plik) {
  $tekst = Czytaj-Cicho $plik
  if ($null -eq $tekst) { return $null }
  $stan = Klucze-Z-Tekstu $tekst
  $dzis = Dzien-Cyklu $stan ""
  if ($null -eq $dzis) { return $null }
  $dzis | Add-Member -NotePropertyName "Poprzedni" -NotePropertyValue (Dzien-Cyklu $stan "poprzedni.")
  return $dzis
}

# --- historia kosztu nauki ---------------------------------------------------
# Dziennik przebiegow (.koszt-historia.tsv, jedna linia na PRZEBIEG) i jego
# podsumowania 7/30 dni (.koszt-podsumowanie.txt) pisze samo wylawianie
# (lore\lore\facts.py, record_pass). Tu tylko czytamy i ukladamy po dniach.
#
# Po co: sama liczba "nauka kosztowala 312 609 tokenow" nie mowi, czy to nowa
# norma, czy jednorazowe nadrabianie zaleglosci sprzed tygodnia - a od tego
# zalezy, czy uzytkownik ma cos robic. Odpowiada na to zakres przeczytanych
# wiadomosci (zakres_od) zestawiony z dniem przebiegu.
#
# Funkcje oddajace liste oddaja ja ROZWINIETA ("return @(...)"), a wolajacy
# owija wywolanie w @() - jedna konwencja na caly ten blok.

$KolumnyHistorii = @("kiedy", "narzedzie", "wywolania", "tokeny", "tokeny_zrodlo", "znaki_wyslane",
                     "znaki_odebrane", "wiadomosci", "zakres_od", "zakres_do", "fakty")

function Dzien-Z-Tekstu($tekst) {
  # 'RRRR-MM-DD' albo 'RRRR-MM-DD GG:MM' -> sam dzien; $null przy braku i smieciu
  if (-not $tekst) { return $null }
  $t = ("" + $tekst).Trim()
  if ($t.Length -lt 10) { return $null }
  $d = [datetime]::MinValue
  if ([datetime]::TryParseExact($t.Substring(0, 10), 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture,
      [Globalization.DateTimeStyles]::None, [ref]$d)) { return $d.Date }
  return $null
}

function Czy-Nadrabianie($dzienPrzebiegu, $zakresOd) {
  # $true / $false, a $null gdy nie wiadomo - przebieg bez zakresu (starsza wersja
  # nauki go nie zapisywala). "Nie wiem" idzie dalej jako "nie wiem", nie jako zgadniete.
  $dp = Dzien-Z-Tekstu $dzienPrzebiegu
  $od = Dzien-Z-Tekstu $zakresOd
  if (($null -eq $dp) -or ($null -eq $od)) { return $null }
  return (($dp - $od).Days -gt $DniMaterialuZwyklego)
}

function Zakres-Krotko($od, $doo) {
  # "16.09", "16-17.09" albo "28.08-02.09" - okres, za ktory placono, jednym rzutem oka
  $a = Dzien-Z-Tekstu $od
  $b = Dzien-Z-Tekstu $doo
  if ($null -eq $a) { return "" }
  if (($null -eq $b) -or ($a -eq $b)) { return $a.ToString('dd.MM') }
  if (($a.Month -eq $b.Month) -and ($a.Year -eq $b.Year)) { return ($a.ToString('dd') + "-" + $b.ToString('dd.MM')) }
  return ($a.ToString('dd.MM') + "-" + $b.ToString('dd.MM'))
}

function Czytaj-Historie($plik) {
  $h = [pscustomobject]@{ Jest = $false; Wiersze = @(); Pominiete = 0; Powod = "" }
  if (-not (Test-Path -LiteralPath $plik)) {
    $h.Powod = "nie ma jeszcze dziennika przebiegow nauki ($plik)"
    return $h
  }
  $tekst = $null
  try { $tekst = Czytaj $plik }
  catch {
    $h.Powod = "dziennika przebiegow $plik nie da sie odczytac: $($_.Exception.Message)"
    return $h
  }
  $h.Jest = $true
  $linie = @(($tekst -split '\r?\n') | Where-Object { ("" + $_).Trim() })
  if (($linie.Count -gt 0) -and $linie[0].StartsWith("kiedy")) { $linie = @($linie | Select-Object -Skip 1) }
  $wiersze = @()
  foreach ($l in $linie) {
    $pola = $l -split "`t"
    # Linia, ktora nie pasuje do kolumn, nie jest zgadywana - ale jest LICZONA,
    # bo pominieta po cichu bylaby zgubionym kosztem.
    if ($pola.Count -ne $KolumnyHistorii.Count) { $h.Pominiete++; continue }
    $s = @{}
    for ($i = 0; $i -lt $pola.Count; $i++) { $s[$KolumnyHistorii[$i]] = $pola[$i] }
    $dzien = Dzien-Z-Tekstu $s["kiedy"]
    if ($null -eq $dzien) { $h.Pominiete++; continue }
    $wiersze += [pscustomobject]@{
      Dzien       = $dzien
      Tokeny      = (Klucz-Liczba $s "tokeny")
      Wywolania   = (Klucz-Liczba $s "wywolania")
      Wiadomosci  = (Klucz-Liczba $s "wiadomosci")
      ZakresOd    = (Klucz-Tekst  $s "zakres_od")
      ZakresDo    = (Klucz-Tekst  $s "zakres_do")
      Nadrabianie = (Czy-Nadrabianie $s["kiedy"] $s["zakres_od"])
    }
  }
  $h.Wiersze = $wiersze
  if (($wiersze.Count -eq 0) -and (-not $h.Powod)) { $h.Powod = "dziennik przebiegow nauki jest pusty ($plik)" }
  return $h
}

function Nowy-Dzien($dzien) {
  return [pscustomobject]@{
    Dzien = $dzien; Razem = [long]0; Zwykle = [long]0; Nadrabianie = [long]0; Nieznane = [long]0
    Przebiegi = 0; Wiadomosci = [long]0; ZakresOd = $null; ZakresDo = $null
  }
}

function Dni-Historii($wiersze) {
  # Przebiegi zsumowane po dniu, a tokeny rozdzielone na trzy: zwykly dzien,
  # nadrabianie i "nie wiadomo" (przebieg bez zakresu). Dopiero to rozdzielenie
  # mowi, czy drogi dzien byl nowa norma, czy jednorazowym nadrabianiem.
  $mapa = @{}
  foreach ($w in @($wiersze)) {
    if (-not $w) { continue }
    $k = $w.Dzien.ToString('yyyy-MM-dd')
    if (-not $mapa.ContainsKey($k)) { $mapa[$k] = Nowy-Dzien $w.Dzien }
    $d = $mapa[$k]
    $t = [long]0
    if ($null -ne $w.Tokeny) { $t = [long]$w.Tokeny }
    $d.Razem += $t
    if ($w.Nadrabianie -eq $true) { $d.Nadrabianie += $t }
    elseif ($w.Nadrabianie -eq $false) { $d.Zwykle += $t }
    else { $d.Nieznane += $t }
    $d.Przebiegi++
    if ($null -ne $w.Wiadomosci) { $d.Wiadomosci += [long]$w.Wiadomosci }
    # 'RRRR-MM-DD GG:MM' porownuje sie poprawnie jako tekst
    if ($w.ZakresOd -and ((-not $d.ZakresOd) -or ($w.ZakresOd -lt $d.ZakresOd))) { $d.ZakresOd = $w.ZakresOd }
    if ($w.ZakresDo -and ((-not $d.ZakresDo) -or ($w.ZakresDo -gt $d.ZakresDo))) { $d.ZakresDo = $w.ZakresDo }
  }
  return @($mapa.Values | Sort-Object -Property Dzien)
}

function Dni-Z-Pliku-Dnia($cykl) {
  # Gdy dziennika jeszcze nie ma, jedyne znane dni to te dwa z .koszt-cyklu.txt
  # (dzis i poprzedni). Pokazujemy je zamiast pustki - z tym samym podzialem.
  $wynik = @()
  if (-not $cykl) { return @() }
  foreach ($c in @($cykl, $cykl.Poprzedni)) {
    if ((-not $c) -or ($null -eq $c.Tokeny)) { continue }
    $dzien = Dzien-Z-Tekstu $c.Data
    if ($null -eq $dzien) { continue }
    $d = Nowy-Dzien $dzien
    $t = [long]$c.Tokeny
    $d.Razem = $t
    $n = Czy-Nadrabianie $c.Data $c.ZakresOd
    if ($n -eq $true) { $d.Nadrabianie = $t }
    elseif ($n -eq $false) { $d.Zwykle = $t }
    else { $d.Nieznane = $t }
    $d.Przebiegi = 1
    if ($null -ne $c.Wiadomosci) { $d.Wiadomosci = [long]$c.Wiadomosci }
    $d.ZakresOd = $c.ZakresOd
    $d.ZakresDo = $c.ZakresDo
    $wynik += $d
  }
  return @($wynik | Sort-Object -Property Dzien)
}

function Ocena-Cyklu($cykl, $dni) {
  # Rodzaj ostatniego dnia nauki: zwykly / nadrabianie / mieszany / nieznany,
  # a "" gdy nie ma czego oceniac. Do tego typowy zwykly dzien i biezacy wzrost.
  $o = [pscustomobject]@{
    Rodzaj = ""; Zrodlo = ""
    Razem = $null; Zwykle = $null; Nadrabianie = $null; Nieznane = $null
    Wiadomosci = $null; ZakresOd = $null; ZakresDo = $null
    TypowyDzien = $null; TypowychDni = 0
    Wzrosty = 0; WzrostOd = $null; WzrostOdTokeny = $null; WzrostDo = $null; WzrostDoTokeny = $null
  }
  $lista = @($dni)
  $granica = [datetime]::Today.AddDays(-($DniStatystyki - 1))

  # Typowy zwykly dzien = srodkowa wartosc (nie srednia) z dni BEZ nadrabiania:
  # jeden dzien nadrabiania nie ma prawa udawac, ze tyle kosztuje zwykla praca.
  $czyste = @($lista | Where-Object { ($_.Zwykle -gt 0) -and ($_.Nadrabianie -eq 0) -and ($_.Nieznane -eq 0) })
  $wartosci = @($czyste | Where-Object { $_.Dzien -ge $granica } | ForEach-Object { [long]$_.Zwykle } | Sort-Object)
  if ($wartosci.Count -gt 0) {
    $s = [int][math]::Floor($wartosci.Count / 2)
    if (($wartosci.Count % 2) -eq 1) { $o.TypowyDzien = [long]$wartosci[$s] }
    else { $o.TypowyDzien = [long][math]::Round(($wartosci[$s - 1] + $wartosci[$s]) / 2.0) }
    $o.TypowychDni = $wartosci.Count
  }

  # Wzrost: kolejne dni kalendarzowe, kazdy drozszy od poprzedniego o co najmniej
  # $ProcWzrostuCyklu procent. Liczone od najnowszego zwyklego dnia wstecz.
  if ($czyste.Count -ge 2) {
    $i = $czyste.Count - 1
    $n = 0
    while ($i -gt 0) {
      $teraz = $czyste[$i]
      $wczesniej = $czyste[$i - 1]
      if (($teraz.Dzien - $wczesniej.Dzien).Days -ne 1) { break }
      if ([double]$teraz.Zwykle -lt ([double]$wczesniej.Zwykle * (1 + $ProcWzrostuCyklu / 100.0))) { break }
      $n++
      $i--
    }
    $ostatni = $czyste[$czyste.Count - 1]
    # trend sprzed tygodnia nie jest alarmem na dzis
    if (($n -gt 0) -and (([datetime]::Today - $ostatni.Dzien).Days -le $DniCyklStary)) {
      $o.Wzrosty = $n
      $o.WzrostOd = $czyste[$i].Dzien
      $o.WzrostOdTokeny = $czyste[$i].Zwykle
      $o.WzrostDo = $ostatni.Dzien
      $o.WzrostDoTokeny = $ostatni.Zwykle
    }
  }

  if ((-not $cykl) -or ($null -eq $cykl.Tokeny)) { return $o }
  $o.Razem = [long]$cykl.Tokeny
  $o.Wiadomosci = $cykl.Wiadomosci
  $o.ZakresOd = $cykl.ZakresOd
  $o.ZakresDo = $cykl.ZakresDo
  $dzien = Dzien-Z-Tekstu $cykl.Data
  $zHistorii = $null
  if ($null -ne $dzien) { $zHistorii = @($lista | Where-Object { $_.Dzien -eq $dzien }) | Select-Object -First 1 }
  if ($zHistorii -and ($zHistorii.Razem -gt 0)) {
    # Ocena po przebiegach: dzien moze byc czesciowo zwykly, czesciowo nadrabianiem.
    $o.Zrodlo = "historia"
    $o.Zwykle = [long]$zHistorii.Zwykle
    $o.Nadrabianie = [long]$zHistorii.Nadrabianie
    $o.Nieznane = [long]$zHistorii.Nieznane
    # Plik dnia i dziennik moga sie rozjechac (dziennik ruszyl w polowie dnia).
    # Roznicy nie przypisujemy ani zwyklemu dniu, ani nadrabianiu - to "nie wiem".
    if ($o.Razem -gt $zHistorii.Razem) { $o.Nieznane += ($o.Razem - $zHistorii.Razem) }
    if (-not $o.ZakresOd) { $o.ZakresOd = $zHistorii.ZakresOd }
    if (-not $o.ZakresDo) { $o.ZakresDo = $zHistorii.ZakresDo }
    if ($null -eq $o.Wiadomosci) { $o.Wiadomosci = $zHistorii.Wiadomosci }
  } else {
    # Dziennika dla tego dnia nie ma - oceniamy caly dzien po zakresie z pliku dnia.
    $o.Zrodlo = "plik-dnia"
    $o.Zwykle = [long]0
    $o.Nadrabianie = [long]0
    $o.Nieznane = [long]0
    $n = Czy-Nadrabianie $cykl.Data $cykl.ZakresOd
    if ($n -eq $true) { $o.Nadrabianie = $o.Razem }
    elseif ($n -eq $false) { $o.Zwykle = $o.Razem }
    else { $o.Nieznane = $o.Razem }
  }
  if (($o.Nadrabianie -gt 0) -and ($o.Zwykle -gt 0)) { $o.Rodzaj = "mieszany" }
  elseif ($o.Nadrabianie -gt 0) { $o.Rodzaj = "nadrabianie" }
  elseif ($o.Zwykle -gt 0) { $o.Rodzaj = "zwykly" }
  elseif ($o.Nieznane -gt 0) { $o.Rodzaj = "nieznany" }
  else { $o.Rodzaj = "zwykly" }   # zero tokenow - nie bylo czego placic
  return $o
}

function Statystyka-Nauki($historia, $dni, $cykl, $podsum) {
  # Dni do wykresu i sumy 7/30 dni. Sumy bierzemy z podsumowania, ktore liczy
  # samo wylawianie; dopiero gdy go nie ma, dodajemy dni z dziennika - i mowimy,
  # skad jest liczba (SumyZ), bo ta sama nazwa z dwoch zrodel to przepis na rozjazd.
  $s = [pscustomobject]@{
    Zrodlo = ""; Powod = ""; Dni = @(); Pominiete = 0
    Suma7 = $null; Suma7Od = $null; Suma30 = $null; Suma30Od = $null; SumyZ = ""
    Srednia = $null; SredniaDni = 0; PodsumowanieZ = ""
  }
  $granica30 = [datetime]::Today.AddDays(-($DniStatystyki - 1))
  $granica7  = [datetime]::Today.AddDays(-6)
  if ($historia) { $s.Pominiete = $historia.Pominiete }
  if (@($dni).Count -gt 0) {
    $s.Zrodlo = "historia"
    $s.Dni = @(@($dni) | Where-Object { $_.Dzien -ge $granica30 })
  } else {
    $s.Zrodlo = "brak"
    if ($historia) { $s.Powod = $historia.Powod }
    $zPliku = @(Dni-Z-Pliku-Dnia $cykl | Where-Object { $_.Dzien -ge $granica30 })
    if ($zPliku.Count -gt 0) {
      $s.Zrodlo = "plik-dnia"
      $s.Dni = $zPliku
    }
  }

  $z7 = Klucz-Liczba $podsum "dni7.tokeny"
  $z30 = Klucz-Liczba $podsum "dni30.tokeny"
  if (($s.Zrodlo -eq "historia") -and ($null -ne $z7) -and ($null -ne $z30)) {
    $s.SumyZ = "podsumowanie"
    $s.Suma7 = $z7
    $s.Suma30 = $z30
    $s.Suma7Od = Klucz-Tekst $podsum "dni7.od"
    $s.Suma30Od = Klucz-Tekst $podsum "dni30.od"
    $s.PodsumowanieZ = Klucz-Tekst $podsum "zaktualizowano"
  } elseif (@($s.Dni).Count -gt 0) {
    $s.SumyZ = "dni"
    $s.Suma7 = [long]0
    $s.Suma30 = [long]0
    foreach ($d in $s.Dni) {
      $s.Suma30 += [long]$d.Razem
      if ($d.Dzien -ge $granica7) { $s.Suma7 += [long]$d.Razem }
    }
    $s.Suma7Od = $granica7.ToString('yyyy-MM-dd')
    $s.Suma30Od = $granica30.ToString('yyyy-MM-dd')
  }
  # Srednia NA DZIEN NAUKI, nie na dzien kalendarza: przy trzech dniach historii
  # dzielenie przez 30 udawaloby, ze nauka jest dziesiec razy tansza, niz jest.
  $zNauka = @(@($s.Dni) | Where-Object { $_.Razem -gt 0 })
  if (($zNauka.Count -gt 0) -and ($null -ne $s.Suma30)) {
    $s.SredniaDni = $zNauka.Count
    $s.Srednia = [long][math]::Round([double]$s.Suma30 / $zNauka.Count)
  }
  return $s
}

function Zdanie-Typowego-Dnia($o) {
  if (($null -ne $o.TypowyDzien) -and ($o.TypowychDni -gt 0)) {
    $zIlu = "z $($o.TypowychDni) dni"
    if ($o.TypowychDni -eq 1) { $zIlu = "z 1 dnia" }
    return "Zwykly dzien (bez nadrabiania) kosztuje ok. $(Liczba $o.TypowyDzien) tokenow - typowa wartosc $zIlu."
  }
  return "Ile kosztuje zwykly dzien - jeszcze nie wiadomo: historia kosztow dopiero sie zbiera i nie ma w niej ani jednego dnia bez nadrabiania."
}

function Opis-Rodzaju($o) {
  switch ($o.Rodzaj) {
    "zwykly"      { return "zwykly dzien - material z jednego dnia" }
    "nadrabianie" { return "NADRABIANIE zaleglosci - material sprzed wiecej niz $DniMaterialuZwyklego dnia; jednorazowy koszt, nie nowa norma" }
    "mieszany"    { return "czesciowo nadrabianie: ~$(Liczba $o.Nadrabianie) tokenow nadrabiania i ~$(Liczba $o.Zwykle) za swieze rozmowy" }
    "nieznany"    { return "nie wiadomo - nauka nie zapisala, z jakiego okresu czytala rozmowy (starsza wersja modulu pamieci)" }
  }
  return "nie ma czego oceniac"
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["nauka"] = $true
