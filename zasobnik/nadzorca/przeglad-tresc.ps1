# zasobnik\nadzorca\przeglad-tresc.ps1 - czesc zasobnik\nadzorca.ps1 (patrz BUDOWA
# w jego naglowku). Tresc zakladki Przeglad wspolna dla okna i dla wydrukow -Raz
# i -Raport: jedna lista spraw wymagajacych uwagi (Zbierz-Problemy, Problem,
# Waga-Z-Alarmu, Porada-Z-Alarmu, Ile-Wymaga-Uwagi), napisy przyciskow z szacunkiem
# kosztu (Napisy-Przyciskow) i Przeglad jako tekst (Zbuduj-Przod, Skladniki-Mr,
# Tokeny-Albo-Brak, Koszt-Po-Ludzku, Zdanie-Progu) oraz wykres kosztu nauki jako
# tekst (Linie-Statystyki - od P35 wykres stoi w Szczegolach, tam go wola wydruk).
# Od P59d sprawy, karty i przyciski modulow spoza rejestru instalacji ($d.Instalacja)
# nie powstaja - w oknie i w wydruku tak samo. Od P71 narzedzia AI tej maszyny (Claude
# Code, Codex - klucze narz.N.* z -Dane): Narzedzia-Z-Rachunku, Zdanie-Narzedzi,
# Problemy-Narzedzi, Teksty-Kosztu-Narzedzi, Opis-Startu-Narzedzia, Linie-Otwarcia-Innych.
# Od 2026-10-07 aktualizacja MegaRuchacza: sprawa przy nieudanej / urwanej / dawno
# niesprawdzonej (w Zbierz-Problemy), przycisk wyszarzony w trakcie (Napisy-Przyciskow),
# w wydruku pasek z krokami albo linia wyniku zamiast wiersza wersji (Linie-Aktualizacji).
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
    # Bez modulu Wiedza stanu nauki nie czytamy wcale (P59d) - jego brak to nie dziura.
    if ((-not $d.Rachunek) -or ((-not $d.Cykl) -and (Modul-Jest $d.Instalacja "wiedza"))) {
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

  # Narzedzia AI tej maszyny (koszt-pamieci.ps1 -Dane, klucze narz.N.* i cowiem.*):
  # prawdziwe braki ida na liste, braki narzedzia, ktorego tu nie uzywasz - NIE (falszywy
  # alarm jest gorszy niz brak alarmu). Stary rachunek bez tych kluczy = nic nie dodajemy.
  if ($d) {
    try { foreach ($p in (Problemy-Narzedzi $d)) { $lista += $p } }
    catch { Zanotuj-Wywrotke "sprawy narzedzi AI" $_ }
  }

  # Skille (P18): nieudane albo dawno niewykonane codzienne sprawdzenie - sam plik
  # znacznika, bez wolania skryptu. Tylko z modulem Skille (P59d).
  if (Modul-Jest $(if ($d) { $d.Instalacja } else { $null }) "skille") {
    try {
      foreach ($p in (Problemy-Skilli)) { $lista += Problem $p.Waga $p.Tytul $p.Porada $p.Pelne }
    } catch { Zanotuj-Wywrotke "odczyt znacznika skilli" $_ }
  }

  # Aktualizacja MegaRuchacza (od 2026-10-07 chodzi sama): nieudana, urwana w polowie,
  # nieczytelna albo dawno niesprawdzana - sama ocena pliku stanu (Ocena-Aktualizacji
  # w stan-wersja.ps1). Nieudana aktualizacja nie ma prawa stac obok "Wszystko gra".
  try {
    $oa = Ocena-Aktualizacji-Teraz $(if ($d -and $d.Wersja) { "$($d.Wersja.Lokalna)" } else { "" })
    if ($oa.Problem) { $lista += Problem $oa.Problem.Waga $oa.Problem.Tytul $oa.Problem.Porada $oa.Problem.Pelne }
  } catch { Zanotuj-Wywrotke "sprawa aktualizacji MegaRuchacza" $_ }
  # Przypomnienia wykonane w tle (2026-10-08, stan-terminy.ps1): "czlowiek", "blad" i nieczytelny wynik.
  try { foreach ($p in (Ocena-Wynikow-Przypomnien-Teraz).Problemy) { $lista += $p } } catch { Zanotuj-Wywrotke "sprawy przypomnien w tle" $_ }

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

# ------------------------------------------- narzedzia AI na tym komputerze (P71)
#
# Okno pokazywalo dotad tylko Claude Code. Na komputerze z samym Codeksem klamalo:
# "BRAK SEKCJI" przy wiedzy, ktora stoi w ~\.codex\AGENTS.md, "nie zmierzono" przy
# tokenach i "Wszystko gra" pod czerwonymi wierszami. Lista narzedzi i ich liczby
# przychodza z koszt-pamieci.ps1 -Dane (klucze narz.N.*, lista $NARZEDZIA_AI
# w narzedzia\koszt\pomiar.ps1) - okno niczego nie wykrywa i nie liczy samo.
# Uzywane = rozmowa w tym narzedziu w ostatnich 14 dniach.

function Narzedzia-Z-Rachunku($d) {
  $lista = @()
  if (-not $d -or -not $d.Rachunek -or -not $d.Rachunek.Klucze) { return ,$lista }
  $k = $d.Rachunek.Klucze
  $ile = Liczba-Z-Klucza $k "narzedzia"
  if (-not $ile) { return ,$lista }
  for ($i = 1; $i -le $ile; $i++) {
    $p = "narz.$i."
    $lista += [pscustomobject]@{
      Klucz = Tekst-Z-Klucza $k "${p}klucz"; Nazwa = Tekst-Z-Klucza $k "${p}nazwa"
      Uzywane = ((Tekst-Z-Klucza $k "${p}uzywane") -eq "1"); Ostatnio = Tekst-Z-Klucza $k "${p}ostatnio"
      Instrukcje = Tekst-Z-Klucza $k "${p}instrukcje"; InstrukcjeJest = ((Tekst-Z-Klucza $k "${p}instrukcje_jest") -eq "1")
      CoWiem = ((Tekst-Z-Klucza $k "${p}cowiem") -eq "1"); Mr = Liczba-Z-Klucza $k "${p}mr"
      Otwarcie = Liczba-Z-Klucza $k "${p}otwarcie"; OtwarcieSesji = Liczba-Z-Klucza $k "${p}otwarcie_sesji"
      OtwarciePowod = Tekst-Z-Klucza $k "${p}otwarcie_powod"
      ZuzycieWOknie = ((Tekst-Z-Klucza $k "${p}zuzycie_w_oknie") -eq "1")
      Dzis = Liczba-Z-Klucza $k "${p}dzis"; Srednia = Liczba-Z-Klucza $k "${p}srednia"
      ZuzycieDni = Liczba-Z-Klucza $k "${p}zuzycie_dni"; DniZRozmowami = Liczba-Z-Klucza $k "${p}zuzycie_dni_z_rozmowami"
      Bufor = Liczba-Z-Klucza $k "${p}zuzycie_bufor"; ZuzyciePowod = Tekst-Z-Klucza $k "${p}zuzycie_powod"
    }
  }
  return ,$lista
}

# "Claude Code", "Claude Code i Codex", "A, B i C".
function Lista-Nazw($nazwy) {
  $n = @($nazwy | Where-Object { $_ })
  if ($n.Count -le 1) { return ($n -join "") }
  return (($n[0..($n.Count - 2)] -join ", ") + " i " + $n[-1])
}

# "z Claude", "z Codeksem" - do zdan "rozmowy z ...". Nieznane narzedzie: "w <nazwa>".
function Z-Narzedziem([string]$nazwa) {
  switch ($nazwa) {
    "Claude Code" { return "z Claude" }
    "Codex"       { return "z Codeksem" }
  }
  return "w $nazwa"
}

# "w Claude Code", "w Codeksie" - do zdan "zuzywasz w ...".
function W-Narzedziu([string]$nazwa) {
  if ($nazwa -eq "Codex") { return "w Codeksie" }
  return "w $nazwa"
}

# Jedno zdanie na gorze Przegladu (P71). Pusty tekst = rachunek bez listy narzedzi
# (stara wersja albo nieudany) - wtedy o brakach mowi juz lista spraw.
function Zdanie-Narzedzi($d) {
  $narz = Narzedzia-Z-Rachunku $d
  if ($narz.Count -eq 0) { return "" }
  $uz = @($narz | Where-Object { $_.Uzywane })
  if ($uz.Count -eq 0) {
    return "Na tym komputerze: w ostatnich 14 dniach nie było rozmowy w żadnym narzędziu ($(Lista-Nazw @($narz | ForEach-Object { $_.Nazwa })))."
  }
  return "Na tym komputerze: $(Lista-Nazw @($uz | ForEach-Object { $_.Nazwa }))."
}

# Prawdziwe braki narzedzi: sekcja "Co wiem" nie stoi w ZADNYM pliku instrukcji (przy
# module Wiedza) i pomiar tokenow niemozliwy dla narzedzia, ktorego UZYWASZ. Narzedzie
# nieuzywane nie daje tu nic - jego braki pokazuje szaro zakladka Warstwy pamieci.
function Problemy-Narzedzi($d) {
  $lista = @()
  $k = $null
  if ($d -and $d.Rachunek) { $k = $d.Rachunek.Klucze }
  if (-not $k) { return ,$lista }
  $narz = Narzedzia-Z-Rachunku $d
  if ($k.Contains("cowiem.gdzie") -and (Modul-Jest $d.Instalacja "wiedza") -and ((Tekst-Z-Klucza $k "cowiem.wiedza_wylaczona") -ne "1") -and
      (-not (Tekst-Z-Klucza $k "cowiem.gdzie"))) {
    $spr = Tekst-Z-Klucza $k "cowiem.sprawdzone"
    $lista += Problem "pilne" "Wiedza o Tobie i firmie nie trafia do żadnego narzędzia" (
      "W żadnym pliku instrukcji nie ma sekcji `„Co wiem`” - sprawdziłem $(@($narz).Count) $(Odmiana @($narz).Count 'plik' 'pliki' 'plików'). " +
      "Bez niej żadne narzędzie AI ($(Lista-Nazw @($narz | ForEach-Object { $_.Nazwa }))) nie wie nic z tego, czego MegaRuchacz się o Tobie nauczył. " +
      "Kliknij `„Zmień instalację`” i zainstaluj ponownie moduł Wiedza - założy tę sekcję.") "Sprawdzone pliki: $spr"
  }
  foreach ($n in $narz) {
    if (-not $n.Uzywane) { continue }
    $pow = @()
    if ($n.OtwarciePowod) { $pow += "otwarcie okna rozmowy: $($n.OtwarciePowod)" }
    if ((-not $n.ZuzycieWOknie) -and $n.ZuzyciePowod) { $pow += "zużycie dzienne: $($n.ZuzyciePowod)" }
    if ($pow.Count -eq 0) { continue }
    $lista += Problem "uwaga" "Nie umiem zmierzyć, ile tokenów zużywasz $(W-Narzedziu $n.Nazwa)" (
      "Używasz go na tym komputerze (ostatnia rozmowa: $(if ($n.Ostatnio) { $n.Ostatnio } else { 'niedawno' })), ale liczby tokenów nie da się odczytać z jego rozmów. " +
      "Szczegóły są w zakładce Szczegóły.") ($pow -join " | ")
  }
  return ,$lista
}

# Karta "Ile tokenow naprawde zuzywasz" dla KAZDEGO narzedzia (P71). Teksty Claude Code
# sklada Teksty-Kosztu (stan-koszt.ps1) jak dotad; tu dochodza narzedzia, ktorych
# zuzycie liczy koszt-pamieci.ps1 (Codex), osobno i razem, kazda liczba z jednostka.
# Gdy Claude Code nie jest tu uzywany, karta mowi o pozostalych narzedziach, a o nim
# jednym zdaniem - spokojnie, bez "nie wiem" na zolto.
function Teksty-Kosztu-Narzedzi($k, $z, $d) {
  $t = Teksty-Kosztu $k $z
  $narz = Narzedzia-Z-Rachunku $d
  if ($narz.Count -eq 0) { return $t }
  $cc = @($narz | Where-Object { $_.ZuzycieWOknie }) | Select-Object -First 1
  $inne = @($narz | Where-Object { (-not $_.ZuzycieWOknie) -and $_.Uzywane })
  $ccUz = (-not $cc) -or $cc.Uzywane
  if ($ccUz -and ($inne.Count -eq 0)) { return $t }

  $wiersz = {
    param($n)
    $dz = "nie wiem"; $sr = "nie wiem"
    if (-not $n.ZuzyciePowod) {
      $dz = "nic"; if ($n.Dzis -gt 0) { $dz = Tokeny-Okolo $n.Dzis }
      $sr = "nic"; if ($n.Srednia -gt 0) { $sr = Tokeny-Okolo $n.Srednia }
    }
    return ,@($n.Nazwa, $dz, $sr)
  }
  $znane = @($inne | Where-Object { -not $_.ZuzyciePowod })
  $bezLiczb = @($inne | Where-Object { $_.ZuzyciePowod })

  if (-not $ccUz) {
    $x = [pscustomobject]@{
      Tytul = "Ile tokenów naprawdę zużywasz - $(Lista-Nazw @($inne | ForEach-Object { $_.Nazwa }))"
      Powod = ""; PowodSzary = $false; Tabela = @(); Udzial = ""; UdzialUwaga = $false
      NaglowekWorkerow = "Workerzy MegaRuchacza"; Workerzy = @()
      WorkerzyPusto = "Workerzy MegaRuchacza pracują w Claude Code - tu go nie używasz, więc ich nie ma."
    }
    if ($inne.Count -eq 0) {
      $x.Tytul = "Ile tokenów naprawdę zużywasz"
      $x.PowodSzary = $true
      $x.Powod = "Nie ma czego liczyć: w ostatnich 14 dniach nie było tu rozmowy w żadnym narzędziu ($(Lista-Nazw @($narz | ForEach-Object { $_.Nazwa })))."
      return $x
    }
    if ($znane.Count -eq 0) {
      $x.Powod = "Nie wiem, ile tokenów zużywasz $(W-Narzedziu $inne[0].Nazwa), bo $("$($inne[0].ZuzyciePowod)".TrimEnd('.', ' '))."
      return $x
    }
    $x.Tabela = @(,@("", "dziś (tokenów)", "średnio dziennie"))
    foreach ($n in $inne) { $x.Tabela += ,(& $wiersz $n) }
    if ($znane.Count -gt 1) {
      $sd = [double]0; $ss = [double]0
      foreach ($n in $znane) { $sd += [double]$n.Dzis; $ss += [double]$n.Srednia }
      $x.Tabela += ,@("Razem", $(if ($sd -gt 0) { Tokeny-Okolo $sd } else { "nic" }), $(if ($ss -gt 0) { Tokeny-Okolo $ss } else { "nic" }))
    }
    $dni = $znane[0].ZuzycieDni
    $x.Udzial = "Średnio dziennie = z $dni pełnych dni, liczę wszystkie tokeny rozmów (także czytane ponownie z pamięci podręcznej). Claude Code: nie używasz go na tym komputerze."
    if ($bezLiczb.Count -gt 0) {
      $x.Udzial += " $($bezLiczb[0].Nazwa): nie wiem, bo $("$($bezLiczb[0].ZuzyciePowod)".TrimEnd('.', ' '))."
      $x.UdzialUwaga = $true
    }
    return $x
  }

  # Claude Code i inne narzedzie naraz: wiersze Claude Code nazwane z imienia, wiersz
  # kazdego innego narzedzia i "Razem" ze wszystkich - gdy wszystkie liczby sa znane.
  $opisInnych = @($inne | ForEach-Object {
    if ($_.ZuzyciePowod) { "$($_.Nazwa): nie wiem, bo $("$($_.ZuzyciePowod)".TrimEnd('.', ' '))" }
    else { "$($_.Nazwa): dziś $(if ($_.Dzis -gt 0) { Tokeny-Okolo $_.Dzis } else { 'nic' }), średnio $(if ($_.Srednia -gt 0) { Tokeny-Okolo $_.Srednia } else { 'nic' }) tokenów dziennie" }
  })
  $t.Tytul = "Ile tokenów naprawdę zużywasz - Claude Code (rozmowy i workerzy) i $(Lista-Nazw @($inne | ForEach-Object { $_.Nazwa }))"
  if ($t.Powod -or (@($t.Tabela).Count -lt 4)) {
    if ($t.Powod) { $t.Powod = "$($t.Powod) $($opisInnych -join '; ')." }
    return $t
  }
  $tab = @($t.Tabela)
  $razem = $tab[-1]
  $nowa = @(,$tab[0])
  $nowa += ,@("Claude: rozmowy", $tab[1][1], $tab[1][2])
  $nowa += ,@("Claude: workerzy", $tab[2][1], $tab[2][2])
  foreach ($n in $inne) { $nowa += ,(& $wiersz $n) }
  if ($bezLiczb.Count -eq 0) {
    $dz = [double]$k.Rozmowy + [double]$k.Workerzy
    $sr = $null
    if ($z -and ($z.Stan -eq "jest") -and ($null -ne $z.SredniaRozmowy) -and ($null -ne $z.SredniaWorkerow)) { $sr = [double]$z.SredniaRozmowy + [double]$z.SredniaWorkerow }
    foreach ($n in $inne) { $dz += [double]$n.Dzis; if ($null -ne $sr) { $sr += [double]$n.Srednia } }
    $nowa += ,@("Razem", $(if ($dz -gt 0) { Tokeny-Okolo $dz } else { "nic" }), $(if ($null -ne $sr) { Tokeny-Okolo $sr } else { $razem[2] }))
  } else {
    $nowa += ,@("Razem Claude", $razem[1], $razem[2])
    $t.Udzial = "$($t.Udzial) $($opisInnych -join '; ')."
    $t.UdzialUwaga = $true
  }
  $t.Tabela = $nowa
  return $t
}

# Otwarcie okna rozmowy: nazwa narzedzia, ktorego dotyczy pomiar (-Start, Sesje.Narzedzie;
# stary pomiar bez tego pola = Claude Code) i opis z poprawionym "z Claude".
function Narzedzie-Startu($start) {
  if ($start -and $start.Sesje -and $start.Sesje.Narzedzie) { return "$($start.Sesje.Narzedzie)" }
  return "Claude Code"
}

function Opis-Startu-Narzedzia($start) {
  $o = Opis-Startu $start
  $nazwa = Narzedzie-Startu $start
  if ($o -and ($nazwa -ne "Claude Code") -and $o.Podstawa) { $o.Podstawa = $o.Podstawa -replace 'z Claude \(', "$(Z-Narzedziem $nazwa) (" }
  return $o
}

# Otwarcie okna rozmowy POZOSTALYCH uzywanych narzedzi - jedna linia na narzedzie, pod
# karta glownego. Liczby z -Dane (narz.N.otwarcie, narz.N.mr); brak to "nie zmierzono, bo".
function Linie-Otwarcia-Innych($d, $start) {
  $l = @()
  $glowne = Narzedzie-Startu $start
  foreach ($n in (Narzedzia-Z-Rachunku $d)) {
    if ((-not $n.Uzywane) -or ($n.Nazwa -eq $glowne)) { continue }
    if ($null -ne $n.Otwarcie) {
      $x = "$($n.Nazwa): otwarcie okna rozmowy ~$(Okolo $n.Otwarcie) tokenów (typowa wartość z $($n.OtwarcieSesji) $(Odmiana ([int]$n.OtwarcieSesji) 'rozmowy' 'rozmów' 'rozmów'))"
      if ($null -ne $n.Mr) { $x += ", z tego MegaRuchacz ~$(Okolo $n.Mr) ($(Procent-Ludzko $n.Mr $n.Otwarcie))" }
      $l += "$x."
    } else {
      $l += "$($n.Nazwa): otwarcia okna rozmowy nie zmierzono, bo $("$($n.OtwarciePowod)".TrimEnd('.', ' '))."
    }
  }
  return ,$l
}

# Ile spraw naprawde wymaga uwagi - informacje sie nie licza. Od tego zalezy,
# czy w oknie stoi "Wszystko gra".
function Ile-Wymaga-Uwagi($problemy) {
  return @(@($problemy) | Where-Object { $_ -and ($_.Waga -ne "info") }).Count
}

# ------------------------------------------- aktualizacja MegaRuchacza (2026-10-07)
# Karta Stan: w miejscu wiersza "Wersja MegaRuchacza" (Linie-Stanu) staje aktualizacja -
# w trakcie pasek z czterema krokami, w spoczynku sama linia wyniku. Gdy pliku stanu
# aktualizacji jeszcze nie ma (ZPliku $false), zostaje stary wiersz wersji.
function Wiersz-Wersji([string]$linia) { return $linia.StartsWith("Wersja MegaRuchacza:") }

# Ta sama tresc co w oknie, jako tekst do wydruku -Raport (i do testow bez pulpitu).
function Linie-Aktualizacji($oa) {
  $l = @()
  if ($oa.Trwa) {
    $pel = [int][math]::Round(20 * $oa.Postep)
    $l += "  $($oa.Etykieta): [$('#' * $pel)$('-' * (20 - $pel))]  $($oa.Naglowek)   (pasek tylko w trakcie)"
    $nr = 1
    foreach ($k in $oa.Kroki) {
      $zn = $(if ($k.Stan -eq "zrobione") { "  " + [string][char]0x2713 } elseif ($k.Stan -eq "trwa") { "  ..." } else { "" })
      $l += "      $nr. $($k.Napis)$zn"
      $nr++
    }
    return ,$l
  }
  $kol = $(switch ($oa.Waga) { "dobrze" { "  (zielony napis)" } "pilne" { "  (czerwony napis)" } "uwaga" { "  (żółty napis)" } default { "" } })
  $l += "  $($oa.Etykieta): $(@($oa.Znak, $oa.Linia | Where-Object { $_ }) -join ' ')$kol"
  if ($oa.Dopisek) { $l += "      $($oa.Dopisek)  (żółty napis)" }
  return ,$l
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
#
# P59d: przycisk czytania rozmow jest tylko z modulem Wiedza (CyklJest), a obok stoi
# "Zmień instalację" - otwiera instalator w trybie zmiany (instalator\okno.ps1), a gdy
# instalatora jeszcze nie ma w repo, jest nieaktywny i mowi dlaczego. $inst = Stan-Instalacji
# (pusty = wedlug $d.Instalacja).
#
# Od 2026-10-07 aktualizacja chodzi sama i trwa w tle - w trakcie przycisk jest wyszarzony
# z opisem "Aktualizacja trwa" ($akt = Ocena-Aktualizacji; pusty = odczyt na teraz).
function Napisy-Przyciskow($d, $zuzycie = $null, $inst = $null, $akt = $null) {
  $n = [pscustomobject]@{
    Aktualizuj     = "Sprawdź i pobierz nowszą wersję MegaRuchacza"
    AktualizujOpis = "Nie kosztuje nic. Zagląda na serwer po poprawki i nanosi je."
    AktualizujWlaczony = $true
    Cykl           = "Przeczytaj teraz nowe rozmowy"
    CyklOpis       = "Nie musisz - MegaRuchacz robi to sam raz dziennie. Zapyta o zgodę."
    CyklWlaczony   = $true
    CyklJest       = $true
    Szacunek       = $null
    Instalacja         = "Zmień instalację"
    InstalacjaOpis     = "Dodaj albo odłącz moduły. Nic nie kosztuje."
    InstalacjaWlaczona = $true
  }
  if ((-not $inst) -and $d) { $inst = $d.Instalacja }
  $n.CyklJest = Modul-Jest $inst "wiedza"
  if (-not (Test-Path -LiteralPath (Join-Path $script:NadzZrodlo "instalator\okno.ps1") -PathType Leaf)) {
    $n.InstalacjaWlaczona = $false
    $n.InstalacjaOpis = "Nieaktywny - instalator w przygotowaniu."
  }

  if ($d -and $d.Wersja -and ($null -ne $d.Wersja.Nowsza) -and ($d.Wersja.Nowsza -gt 0)) {
    $n.Aktualizuj = "Pobierz nowszą wersję MegaRuchacza ($($d.Wersja.Nowsza) do pobrania)"
  }
  if (-not $akt) {
    try { $akt = Ocena-Aktualizacji-Teraz $(if ($d -and $d.Wersja) { "$($d.Wersja.Lokalna)" } else { "" }) }
    catch { Zanotuj-Wywrotke "stan aktualizacji pod przyciskiem" $_ }
  }
  if ($akt -and -not $akt.Przycisk) {
    $n.AktualizujWlaczony = $false
    $n.AktualizujOpis = $akt.PrzyciskOpis
  }

  $s = $null
  if ($d) {
    try { $s = Szacunek-Cyklu $d.Cykl }
    catch { Zanotuj-Wywrotke "szacunek kosztu czytania rozmow" $_ }
  }
  $n.Szacunek = $s

  # Czytanie reczne z okna (08.10.2026): wynik ostatniego klikniecia z .cykl-reczny
  # (Stan-Recznego) i klikniecie, na ktore okno jeszcze czeka ($script:CyklKlik, okno.ps1).
  $r = $null
  try { $r = Stan-Recznego } catch { Zanotuj-Wywrotke "wynik recznego czytania rozmow" $_ }
  $ocena = "koniec"
  if ($script:CyklKlik) {
    try { $ocena = Ocena-Klikniecia $r $script:CyklKlik ([datetime]::Now) }
    catch { Zanotuj-Wywrotke "ocena klikniecia czytania rozmow" $_ }
  }

  if ($d -and $d.Cykl -and $d.Cykl.Pracuje) {
    # Drugi przebieg w tej samej chwili nic nie da, a kosztowalby drugi raz.
    $n.CyklWlaczony = $false
    $n.CyklOpis = "Wyłączone: czytanie rozmów właśnie trwa. Liczby odświeżą się same, gdy skończy."
  } elseif ($ocena -eq "czekam") {
    $n.CyklWlaczony = $false
    $n.CyklOpis = "Uruchamiam czytanie w tle..."
  } elseif ($r -and $r.Trwa) {
    $n.CyklWlaczony = $false
    $n.CyklOpis = $r.Krotki
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
  # Po kliknieciu opis pod przyciskiem mowi, jak poszlo - takze odmowe ("nic nowego od 08:04"),
  # do konca dnia. Klikniecie bez sladu przebiegu ($script:NapisCyklu z okna) wygrywa
  # ze starszym wynikiem.
  $trwa = ($d -and $d.Cykl -and $d.Cykl.Pracuje) -or ($ocena -eq "czekam") -or ($r -and $r.Trwa)
  if (-not $trwa) {
    $napis = $script:NapisCyklu
    if ($napis -and -not ($r -and $r.Start -and ($r.Start -ge ([datetime]$napis.Czas).AddSeconds(-5)))) { $n.CyklOpis = $napis.Tekst }
    elseif ($r -and $r.Dzis -and $r.Krotki) { $n.CyklOpis = $r.Krotki }
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
    # Zero przy wiadomosci to "nic sie nie dokleja" (OpenCode nie ma hooka wiadomosci,
    # modul kierownik wylaczony) - nie "+0", ktore czyta sie jak doplata.
    if (($x[2] -eq "+") -and ($null -ne $x[1]) -and ([long]$x[1] -le 0)) {
      $liczba = "nic"; $uw = "MegaRuchacz nie dokleja niczego do Twoich wiadomości"
    }
    $lista += [pscustomobject]@{ Napis = $x[0]; Liczba = $liczba; Proc = $proc; Uwaga = $uw }
  }
  return ,$lista
}

# Przod okna jako tekst: dokladnie te sekcje i w tej samej kolejnosci, co
# w oknie. Ten wydruk jest jedynym sposobem sprawdzenia ukladu bez pulpitu.
function Zbuduj-Przod($d, $problemy, $czas, $start, $zuzycie = $null, $koszt = $null) {
  $l = @()
  # P59d: zakladki, karty i linie modulow, ktorych nie ma w instalacji, nie istnieja -
  # tak samo w oknie i tutaj.
  $inst = $null
  if ($d) { $inst = $d.Instalacja }
  $zakladki = "Przegląd | Szczegóły | Warstwy pamięci$(if (Modul-Jest $inst 'skille') { ' | Skille' })"
  $l += "MegaRuchacz - nadzorca                      [ $zakladki ]   <- przełącznik widoków u góry okna"
  $stempel = "przed chwilą"
  if ($czas) { $stempel = $czas.ToString('yyyy-MM-dd HH:mm:ss') }
  $l += "liczby sprawdzone: $stempel  (okno odświeża je samo w tle co $Minut min; starsze niż dzisiejsze liczy od nowa przy otwarciu)"
  $jest = Nazwy-Modulow $inst $true
  $l += "zainstalowane moduły: $(if ($jest.Count -gt 0) { $jest -join ', ' } else { 'żaden (sama aplikacja przy zegarze z aktualizacjami)' })$(if ($inst -and $inst.Blad) { '  (REJESTR NIECZYTELNY - pokazuję wszystko)' })"
  # P71: na jakich narzedziach pracujesz na tym komputerze - w oknie pierwsza linia karty werdyktu.
  $zn = ""
  try { $zn = Zdanie-Narzedzi $d } catch { Zanotuj-Wywrotke "zdanie o narzedziach do wydruku" $_ }
  if ($zn) { $l += "$zn   (w oknie: szara linia na samej górze Przeglądu)" }
  $l += ""

  $l += "WERDYKT   (w oknie: pierwsza karta, duże zdanie - zielone: mało, czerwone: dużo, żółte: nie wiadomo)"
  $wd = $null
  try { $wd = Werdykt-Kosztu $start $(if ($d) { $d.Rachunek } else { $null }) $(if ($d) { $d.Cykl } else { $null }) $zuzycie $inst }
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

  $l += "ILE TOKENÓW NAPRAWDĘ ZUŻYWASZ   (w oknie: karta pod werdyktem - dwie kolumny obok siebie)"
  $tk = $null
  try { $tk = Teksty-Kosztu-Narzedzi $koszt $zuzycie $d } catch { Zanotuj-Wywrotke "prawdziwy koszt do wydruku" $_ }
  if (-not $tk) {
    $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy"
  } elseif ($tk.Powod) {
    $l += "  $($tk.Powod)  ($(if ($tk.PowodSzary) { 'szary' } else { 'żółty' }) napis)"
  } else {
    if ($tk.Tytul) { $l += "  $($tk.Tytul)" }
    foreach ($r in $tk.Tabela) { $l += ("  {0,-16} {1,-18} {2}" -f $r[0], $r[1], $r[2]) }
    if ($tk.Udzial) { $l += "  $($tk.Udzial)$(if ($tk.UdzialUwaga) { '  (żółty napis)' })" }
    $l += "  | $($tk.NaglowekWorkerow)"
    foreach ($x in $tk.Workerzy) { $l += ("  |   {0,9}  {1}  ({2})" -f $x.Tokeny, $x.Opis, $x.Dopisek) }
    if ($tk.WorkerzyPusto) { $l += "  |   $($tk.WorkerzyPusto)" }
  }
  $l += ""

  $nazwaStartu = Narzedzie-Startu $start
  $l += "OTWARCIE OKNA ROZMOWY   (w oknie: karta z dużą liczbą i paskiem - MegaRuchacz kontra sam $nazwaStartu)"
  $os = $null
  try { $os = Opis-Startu-Narzedzia $start } catch { Zanotuj-Wywrotke "otwarcie okna rozmowy do wydruku" $_ }
  if (-not $os) {
    $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy"
  } elseif (-not $os.Zmierzone) {
    $l += "  nie zmierzono, bo $($os.Powod)."
    if ($null -ne $os.Mr) { $l += "  sama część MegaRuchacza (z rachunku): ~$(Liczba-Ludzka $os.Mr) tokenów - procentu nie ma, bo nie ma całości" }
  } else {
    $l += "  Otwarcie okna rozmowy ($nazwaStartu): ~$(Okolo $os.Razem) tokenów na otwarcie okna. Z tego MegaRuchacz: $(Okolo $os.Mr) ($($os.MrProc)) · $nazwaStartu sam: $(Okolo $os.Cc) ($($os.CcProc))"
    foreach ($sk in (Skladniki-Mr $start $os)) { $l += "      $($sk.Napis): $($sk.Liczba)   ($($sk.Proc))" }
    $zw = Zdanie-Wiadomosci $start
    if ($zw) { $l += "      $zw" }
    $l += "  $($os.Portfel)"
    $l += "  $($os.Podstawa) $($os.Zakres)   (drobnym drukiem)"
  }
  $inneO = @()
  try { $inneO = Linie-Otwarcia-Innych $d $start } catch { Zanotuj-Wywrotke "otwarcie okna innych narzedzi do wydruku" $_ }
  foreach ($x in $inneO) { $l += "  $x   (drobnym drukiem)" }
  $l += ""

  $r = $null; $c = $null
  if ($d) { $r = $d.Rachunek; $c = $d.Cykl }
  $trzy = @()
  # karta nauki tylko z modulem Wiedza (P59d) - bez niego nie ma jej w oknie wcale
  if (Modul-Jest $inst "wiedza") {
    $l += "NAUKA Z ROZMÓW   (w oknie: karta na całą szerokość pod otwarciem okna rozmowy)"
    try { $trzy = @(Liczba-Nauki $r $c) }
    catch { Zanotuj-Wywrotke "koszt nauki do wydruku" $_; $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy" }
  }
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
  if (Modul-Jest $inst "wiedza") { $l += "" }
  # Wykres kosztu nauki z 30 dni stoi od P35 w Szczegolach (karta "Koszt czytania
  # rozmow - ostatnie 30 dni") - w wydruku razem z nimi, w Zbuduj-Szczegoly.

  $l += "STAN   (w oknie: karta z dwiema kolumnami - co i jak)"
  if ((Ile-Wymaga-Uwagi $problemy) -eq 0) { $l += "  Wszystko gra - nic nie wymaga Twojej uwagi." }
  $linie = @()
  if ($d) {
    try { $linie = Linie-Stanu $d.Wersja $d.Cykl $d.Przeliczanie $inst }
    catch { Zanotuj-Wywrotke "linie stanu do wydruku" $_; $l += "  NIE UDALO SIE ZLOZYC - szczegoly w dzienniku nadzorcy" }
  }
  # Aktualizacja w miejscu wiersza "Wersja MegaRuchacza" - tak samo jak w oknie (przeglad.ps1).
  $oa = $null
  try { $oa = Ocena-Aktualizacji-Teraz $(if ($d -and $d.Wersja) { "$($d.Wersja.Lokalna)" } else { "" }) }
  catch { Zanotuj-Wywrotke "aktualizacja do wydruku" $_; $l += "  NIE UDALO SIE ZLOZYC STANU AKTUALIZACJI - szczegoly w dzienniku nadzorcy" }
  $wstawiona = $false
  foreach ($x in $linie) {
    if ($oa -and $oa.ZPliku -and (Wiersz-Wersji $x)) { $l += Linie-Aktualizacji $oa; $wstawiona = $true; continue }
    $l += "  $x"
  }
  if ($oa -and $oa.ZPliku -and -not $wstawiona) { $l += Linie-Aktualizacji $oa }
  if ($d -and (Modul-Jest $inst "kopia")) {
    try { $kop = Ocena-Kopii $d.Kopia $inst; $l += "  $($kop.Linia)$(if ($kop.Waga -eq 'pilne') { '  (czerwony napis)' } elseif ($kop.Waga -eq 'uwaga') { '  (żółty napis)' })" }
    catch { Zanotuj-Wywrotke "linia kopii zapasowej do wydruku" $_; $l += "  NIE UDALO SIE ZLOZYC LINII KOPII ZAPASOWEJ - szczegoly w dzienniku nadzorcy" }
  }
  try { $l += Linie-Wynikow-Przypomnien (Ocena-Wynikow-Przypomnien-Teraz) } catch { Zanotuj-Wywrotke "przypomnienia w tle do wydruku" $_; $l += "  NIE UDALO SIE ZLOZYC LINII PRZYPOMNIEN - szczegoly w dzienniku nadzorcy" }
  $pm = $null
  # zmiany w pamieci pisze nauka z rozmow - bez modulu Wiedza linii nie ma (P59d)
  if (Modul-Jest $inst "wiedza") {
    try { $pm = Opis-Zmian-Pamieci $(if ($d) { $d.Pamiec } else { $null }) }
    catch { Zanotuj-Wywrotke "zmiany w pamieci do wydruku" $_; $l += "  NIE UDALO SIE ZLOZYC ZMIAN W PAMIECI - szczegoly w dzienniku nadzorcy" }
  }
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
  $n = Napisy-Przyciskow $d $zuzycie $inst $oa
  $l += "  [$($n.Aktualizuj)]$(if (-not $n.AktualizujWlaczony) { '  (przycisk nieaktywny)' })"
  $l += "      $($n.AktualizujOpis)"
  if ($n.CyklJest) {
    $wl = ""
    if (-not $n.CyklWlaczony) { $wl = "  (przycisk nieaktywny)" }
    $l += "  [$($n.Cykl)]$wl"
    $l += "      $($n.CyklOpis)"
    if ($n.Szacunek) { foreach ($z in $n.Szacunek.Podstawa) { $l += "      $z" } }
  }
  $l += "  [$($n.Instalacja)]$(if (-not $n.InstalacjaWlaczona) { '  (przycisk nieaktywny)' })"
  $l += "      $($n.InstalacjaOpis)"
  $l += "  [$($zakladki -replace ' \| ', '] / [')]  (przełącznik u góry)"
  $l += "      Szczegóły i warstwy - z czego to się składa i gdzie to leży - zajmują miejsce przeglądu. Nic nie uruchamiają i nic nie kosztują."
  $l += "  [Zamknij okno]"
  $l += "      Okno znika, ikona w zasobniku zostaje i pilnuje dalej."
  return ,$l
}

# Statystyka jako tekst: to samo, co wykres w oknie, tylko paskami ze znakow.
# Sluzy wydrukowi -Raport, czyli sprawdzeniu bez pulpitu (od P35 w czesci
# SZCZEGOLY - Zbuduj-Szczegoly, element "wykres").
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
