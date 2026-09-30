# narzedzia\koszt\alarmy.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz BUDOWA
# w jego naglowku). Trzeci etap (Etap-Ocena): ocena kosztu nauki, rachunek kazdego
# narzedzia z jego progami i alarmami (Rachunek-Narzedzia -> $rCc, $rCx, $rDom),
# alarmy nauki z rozmow ($alarmy, $informacje) i jedna linia dla -Zwiezle / -Dane
# (Linia-Narzedzia -> $liniaZwiezla, $kodWyjscia). Progi ($AlarmUdzialuOtwarcia,
# $AlarmCyklu i reszta) stoja na gorze koszt-pamieci.ps1. Skad wolane:
# koszt-pamieci.ps1 kropka (". Etap-Ocena") przed trybami -Zwiezle, -Dane,
# -Rozbicie, -TylkoSufity i pelnym raportem.

# --- alarmy ------------------------------------------------------------------
# Alarm mowi, CO zrobic i z ktorym plikiem - sama liczba nad progiem nikomu
# jeszcze niczego nie zalatwila. Kazdy alarm podnosi kod wyjscia.

function Najdrozsza($pozycje) {
  $l = @($pozycje | Sort-Object -Property Tokeny -Descending)
  if ($l.Count -eq 0) { return $null }
  return $l[0]
}

function Alarm($krotko, $pelny, $temat = "", $waga = "pilne", $liczba = $null, $prog = $null, $okres = "") {
  # Waga: "pilne" (czerwone, podnosi kod wyjscia), "uwaga" (zolte - czegos nie
  # wiemy), "info" (zolte - co sie stalo i dlaczego; nic nie trzeba robic).
  # Okres mowi, ZA JAKI CZAS jest liczba: "stan na teraz" albo konkretne dni.
  # Liczba bez okresu i bez "za co" wyprodukowala 24.09.2026 alarm, ktory klamal.
  return [pscustomobject]@{ Krotko = $krotko; Pelny = $pelny; Temat = $temat; Waga = $waga
                            Liczba = $liczba; Prog = $prog; Okres = $okres }
}

# "4%" albo "mniej niz 1%" - zero procent czytaloby sie jak "nic", a to nie to
# samo. Ta sama zasada, co Procent-Ludzko w zasobnik\stan-nadzorcy.ps1.
function Procent-Tekst($proc) {
  if ($null -eq $proc) { return "?" }
  if (($proc -gt 0) -and ($proc -lt 1)) { return "mniej niz 1%" }
  return "$([int][math]::Round($proc))%"
}

# Dwa pierwsze rachunki to STAN PLIKOW NA TERAZ, a nie koszt jakiegos dnia -
# i tak ma byc napisane, bo "kosztuje X" bez "za co" czyta sie jak rachunek za dzis.
#
# Rachunek JEDNEGO narzedzia: jego kubelki, jego sufity, jego poprzedni pomiar
# i jego alarmy. Tematy alarmow Claude Code sa bez przedrostka (nadzorca zna je
# po nazwie: otwarcie, udzial, wzrost); Codex dostaje przedrostek "codex-". Krotki
# opis zaczyna sie od nazwy narzedzia - liczba bez tej nazwy klamie.
function Rachunek-Narzedzia($narz) {
  if ($narz -eq "Codex") {
    $r = [pscustomobject]@{ Narz = "Codex"; Klucz = "codex"; Nazwa = "Codex"; Temat = "codex-"
      Jest = [bool]$jestCodex; KubW = @($kubWiadomoscCx); TokW = $tokWiadomoscCx
      KubS = @($kubSesjaCx); TokS = $tokSesjaCx
      Brak = "brak Codeksa na tej maszynie (nie ma $plikAgents)" }
  } else {
    $r = [pscustomobject]@{ Narz = "Claude"; Klucz = "claude"; Nazwa = "Claude Code"; Temat = ""
      Jest = $true; KubW = @($kubWiadomosc); TokW = $tokWiadomosc
      KubS = @($kubSesja); TokS = $tokSesja; Brak = "" }
  }
  $r | Add-Member -NotePropertyName ZnakiS -NotePropertyValue 0
  foreach ($p in @($r.KubS)) { $r.ZnakiS += [int]$p.Znaki }
  $r | Add-Member -NotePropertyName Ucinane -NotePropertyValue @()
  $r | Add-Member -NotePropertyName Alarmy -NotePropertyValue @()
  $r | Add-Member -NotePropertyName Informacje -NotePropertyValue @()
  $r | Add-Member -NotePropertyName AlarmyUcinania -NotePropertyValue @()
  $r | Add-Member -NotePropertyName Poprz -NotePropertyValue $null
  $r | Add-Member -NotePropertyName Zmiana -NotePropertyValue 0
  $r | Add-Member -NotePropertyName ZmianaProc -NotePropertyValue 0
  $r | Add-Member -NotePropertyName Skok -NotePropertyValue $false
  # MegaRuchacz w otwarciu sesji: start + przypomnienie doklejone do pierwszej
  # wiadomosci (tak samo liczy okno nadzorcy, Opis-Startu). Calosc i Sesji z pomiaru.
  $r | Add-Member -NotePropertyName Mr -NotePropertyValue ([long]($r.TokS + $r.TokW))
  $r | Add-Member -NotePropertyName Calosc -NotePropertyValue $null
  $r | Add-Member -NotePropertyName Sesji -NotePropertyValue 0
  $r | Add-Member -NotePropertyName Udzial -NotePropertyValue $null
  $r | Add-Member -NotePropertyName PowodCalosci -NotePropertyValue ""
  $r | Add-Member -NotePropertyName NadProgiem -NotePropertyValue $false
  # Narzedzia, ktorego na maszynie nie ma, nie liczymy wcale: zero czytaloby
  # sie jak "za darmo", a to znaczy "nie ma czego liczyc" - mowi to pole Brak.
  if (-not $r.Jest) { return $r }

  if ($narz -eq "Codex") {
    $r.PowodCalosci = "calosci otwarcia sesji Codeksa nie mierze (pomiar z transkryptow jest tylko dla Claude Code)"
  } elseif ($bladOtwarcia) {
    $r.PowodCalosci = $bladOtwarcia
  } elseif (-not $otwarcie) {
    $r.PowodCalosci = "pomiaru calosci w tym trybie nie robie"
  } elseif ($otwarcie.Powod) {
    $r.PowodCalosci = $otwarcie.Powod
  } elseif ((-not $otwarcie.Sesje) -or ($null -eq $otwarcie.Sesje.Mediana) -or ($otwarcie.Sesje.Mediana -le 0)) {
    $r.PowodCalosci = "pomiar z transkryptow nie oddal mediany sesji"
  } else {
    $r.Calosc = [long]$otwarcie.Sesje.Mediana
    $r.Sesji  = [int]$otwarcie.Sesje.Liczba
    $r.Udzial = 100.0 * [double]$r.Mr / [double]$r.Calosc
    $r.NadProgiem = ($r.Udzial -gt $AlarmUdzialuOtwarcia)
  }

  $r.Ucinane = @(Sortuj-Sufity @($sufity | Where-Object {
    $_.Ucina -and $_.Przekroczony -and ((-not $_.Narzedzie) -or ($_.Narzedzie -eq $narz)) }))
  foreach ($s in $r.Ucinane) {
    $r.AlarmyUcinania += Alarm "$($r.Nazwa): UCINANE $($s.Krotka) -$($s.Strata) $($s.Jednostka)" `
      "UCINANE PO CICHU ($($r.Nazwa)): $($s.Nazwa) - ginie $(Liczba $s.Strata) $($s.Jednostka) z $(Liczba $s.Teraz). Sufit $($s.SkadLimitu). Tekst: $($s.Plik)." `
      "$($r.Temat)ucinane" "pilne" $s.Strata $s.Limit "stan na teraz"
  }

  # Porownanie z poprzednim pomiarem TEGO SAMEGO narzedzia (Poprzedni-Pomiar).
  # Pomiar nieporownywalny (stary format z jedna suma) nie daje zadnego skoku.
  $r.Poprz = Poprzedni-Pomiar $plikOstatni $r.Klucz $r.Nazwa
  if ($r.Poprz -and $r.Poprz.Porownywalny -and ($r.Poprz.Tokeny -gt 0)) {
    $r.Zmiana     = $r.TokS - $r.Poprz.Tokeny
    $r.ZmianaProc = [int][math]::Round(100.0 * $r.Zmiana / $r.Poprz.Tokeny)
    if ($r.ZmianaProc -gt $ProgWzrostu) { $r.Skok = $true }
  }

  if ($r.NadProgiem) {
    $n = Najdrozsza (@($r.KubS) + @($r.KubW))
    $r.Alarmy += Alarm "$($r.Nazwa): MegaRuchacz to $(Procent-Tekst $r.Udzial) otwarcia sesji (prog $AlarmUdzialuOtwarcia%)" `
      ("MegaRuchacz dokleja na otwarcie sesji $($r.Nazwa) ~$(Liczba $r.Mr) tokenow (start $(Liczba $r.TokS) + przypomnienie $(Liczba $r.TokW)), " +
       "czyli $(Procent-Tekst $r.Udzial) calego otwarcia (~$(Liczba $r.Calosc) tokenow, mediana z $($r.Sesji) ostatnich sesji w transkryptach). " +
       "Prog to $AlarmUdzialuOtwarcia%. To stan plikow na teraz, nie koszt jednego dnia. " +
       "Najdrozsza pozycja: $($n.Nazwa) (~$(Liczba $n.Tokeny) tokenow) - $($n.Rada). Plik: $($n.Skad).") `
      "$($r.Temat)otwarcie" "pilne" ([int][math]::Round($r.Udzial)) $AlarmUdzialuOtwarcia "stan na teraz, przy kazdym starcie sesji"

    # Co ciac - ma sens dopiero, gdy caly udzial jest nad progiem; wczesniej
    # "jedna pozycja to 49%" swiecila na czerwono, choc nic nie trzeba bylo robic.
    foreach ($k in @(
      @{ Poz = $r.KubS; Nazwa = "start sesji" },
      @{ Poz = $r.KubW; Nazwa = "kazda wiadomosc" }
    )) {
      if (@($k.Poz).Count -lt $MinPozycjiDoUdzialu) { continue }
      $n = Najdrozsza $k.Poz
      if ($n.Procent -le $AlarmUdzialu) { continue }
      $r.Alarmy += Alarm "$($r.Nazwa): $($n.Nazwa) to $($n.Procent)% rachunku za $($k.Nazwa)" `
        ("Jedna pozycja zjada $($n.Procent)% rachunku $($r.Nazwa) za $($k.Nazwa) (stan plikow na teraz): $($n.Nazwa), ~$(Liczba $n.Tokeny) tokenow. " +
         "Skracanie czegokolwiek innego nic nie da - $($n.Rada). Plik: $($n.Skad).") `
        "$($r.Temat)udzial" "pilne" $n.Procent $AlarmUdzialu "stan na teraz"
    }
  }

  if ($r.Skok) {
    # Wzrost "od poprzedniego pomiaru" bez daty tego pomiaru nie mowi, czy urosl
    # przez noc, czy przez miesiac - a to dwie rozne sprawy.
    $odKiedy = "poprzedniego pomiaru (data nieznana)"
    if ($r.Poprz.Data) { $odKiedy = "pomiaru z $($r.Poprz.Data.ToString('dd.MM HH:mm'))" }
    $poSkoku = "udzialu w calym otwarciu sesji nie znam ($($r.PowodCalosci))"
    if ($null -ne $r.Udzial) { $poSkoku = "po skoku MegaRuchacz to $(Procent-Tekst $r.Udzial) otwarcia sesji (prog $AlarmUdzialuOtwarcia%)" }
    $pelny = ("Start sesji $($r.Nazwa) urosl o $($r.ZmianaProc)% od $odKiedy ($(Liczba $r.Poprz.Tokeny) -> $(Liczba $r.TokS) tokenow na kazda sesje); " +
              "$poSkoku. Sprawdz, co doszlo do plikow tego narzedzia albo czy do rachunku nie doszla nowa pozycja (rozbicie wymienia wszystkie).")
    # Czerwony tylko wtedy, gdy po skoku udzial przekracza prog - sam skok przy
    # malym udziale to informacja: widac ja, ale nic sie nie pali.
    $waga = "info"
    if ($r.NadProgiem) { $waga = "pilne" }
    $a = Alarm "$($r.Nazwa): start sesji +$($r.ZmianaProc)% od $odKiedy" $pelny `
      "$($r.Temat)wzrost" $waga $r.ZmianaProc $ProgWzrostu $odKiedy
    if ($waga -eq "pilne") { $r.Alarmy += $a } else { $r.Informacje += $a }
  }
  return $r
}

# --- jedna linia: dla straznika (-Zwiezle) i dla nadzorcy (-Dane) --------------
# Liczby bez separatora tysiecy: ta linia ma sie zmiescic w jednym wierszu
# terminala i jest pokazywana przez straznika przy kazdym otwarciu sesji.
# Obie liczby, bo sama sesyjna sugerowala, ze tyle placi sie za wiadomosc.
# Zero tokenow za start sesji nie znaczy "za darmo", tylko "nie bylo czego
# policzyc" - i tak to ma byc napisane, tak samo jak przy przypomnieniu.
# Linia mowi o JEDNYM narzedziu i nazywa je z imienia ("pamiec Claude Code: ...").
# Jego alarmy i ucinanie podnosza kod; alarmy nauki z rozmow ($alarmy) sa wspolne,
# bo nauka placi sie raz, niezaleznie od narzedzia.
function Linia-Narzedzia($r) {
  # Najpierw PROCENT calego otwarcia sesji - to jest liczba, ktora cos mowi
  # czlowiekowi; tokeny stoja w nawiasie (i z nich czyta liczby nadzorca).
  # Bez zmierzonej calosci procentu nie ma i linia mowi dlaczego - szaro, bez
  # alarmu, bo brak pomiaru to nie przekroczenie.
  if (-not $r.Jest) {
    $rachunek = "pamiec $($r.Nazwa): $($r.Brak), nie ma czego liczyc"
  } else {
    $czSesja = "start sesji +$($r.TokS) tokenow"
    if ($r.TokS -le 0) { $czSesja = "startu sesji nie umiem zmierzyc" }
    if ($r.TokW -gt 0) { $czTokeny = "$czSesja, wiadomosc +$($r.TokW) tokenow" }
    else { $czTokeny = "$czSesja, przypomnienia nie umiem zmierzyc" }
    if ($null -ne $r.Udzial) {
      $rachunek = "pamiec $($r.Nazwa): MegaRuchacz to $(Procent-Tekst $r.Udzial) otwarcia sesji " +
                  "(~$($r.Mr) z ~$($r.Calosc) tokenow, reszta to sam $($r.Nazwa); $czTokeny)"
    } else {
      $rachunek = "pamiec $($r.Nazwa): $czTokeny - udzialu w calym otwarciu sesji nie porownuje, bo $($r.PowodCalosci)"
    }
  }
  $ucin = @($r.Ucinane)
  # Alarmy tego narzedzia maja w krotkim opisie jego nazwe - w jego wlasnej
  # linii nazwa stoi juz na poczatku, wiec drugi raz jej nie powtarzamy.
  $al = @(@($r.Alarmy) | ForEach-Object { $_.Krotko -replace ('^' + [regex]::Escape("$($r.Nazwa): ")), '' }) +
        @(@($alarmy) | ForEach-Object { $_.Krotko })
  if ($ucin.Count -gt 0) {
    $g = $ucin[0]
    $opis = "UCINANE: $($g.Krotka) -$($g.Strata) $($g.Jednostka)"
    if ($g.Naglowek) { $opis = $opis + " (od ""$(Skroc $g.Naglowek 34)"")" }
    if ($ucin.Count -gt 1) { $opis = $opis + " i jeszcze $($ucin.Count - 1)" }
    $linia = "UWAGA $rachunek, $opis"
  } elseif ($al.Count -gt 0) {
    $opis = "ALARM: $($al[0])"
    if ($al.Count -gt 1) { $opis = $opis + " i jeszcze $($al.Count - 1)" }
    $linia = "UWAGA $rachunek, $opis"
  } else {
    $linia = "$rachunek, nic nie jest ucinane"
    # Informacja idzie w te sama linie, ale BEZ slowa UWAGA i bez kodu 1 -
    # straznik pokazuje ja wtedy jako zwykly meldunek, a nie jako alarm.
    if ($informacje.Count -gt 0) {
      $slowo = "info"
      if ($informacje[0].Waga -eq "uwaga") { $slowo = "do sprawdzenia" }
      $linia = $linia + "; ${slowo}: $($informacje[0].Krotko)"
      if ($informacje.Count -gt 1) { $linia = $linia + " i jeszcze $($informacje.Count - 1)" }
    }
  }
  $kod = 0
  if (($ucin.Count -gt 0) -or ($al.Count -gt 0)) { $kod = 1 }
  return [pscustomobject]@{ Linia = $linia; Kod = $kod }
}

# Etap-Ocena - ocena nauki, rachunek kazdego narzedzia, alarmy i jedna linia.
# Wola go koszt-pamieci.ps1 KROPKA (". Etap-Ocena"), wiec biegnie w zasiegu skryptu
# glownego: zmienne i funkcje, ktore tu powstaja, widzi dalszy przebieg - tak samo,
# jak gdy ten kod stal w koszt-pamieci.ps1 wprost.
function Etap-Ocena {
  # Trzeci rachunek: cykl wiedzy raz na dobe. NIE doliczamy go do zadnego z dwoch
  # powyzej - to inne pieniadze. Tamte to tekst doklejany do rozmowy, ten to
  # prawdziwe wywolanie modelu, a zsumowana liczba mowilaby, ze tyle kosztuje
  # kazda sesja. $null znaczy "cykl jeszcze nie liczyl kosztu".
  $cykl = Koszt-Cyklu $plikCyklKoszt

  # Historia i ocena kosztu nauki: czy ostatni dzien byl zwykly, czy nadrabial
  # zaleglosc, ile kosztuje typowy dzien i czy koszt rosnie. Arytmetyka na plikach,
  # ktore zapisalo samo wylawianie - nic nie jest tu mierzone drugi raz.
  $historia    = Czytaj-Historie $plikHistoria
  $dniHistorii = @(Dni-Historii $historia.Wiersze)
  $ocena       = Ocena-Cyklu $cykl $dniHistorii
  $podsum      = Klucze-Z-Tekstu (Czytaj-Cicho $plikPodsum)
  $statystyka  = Statystyka-Nauki $historia $dniHistorii $cykl $podsum

  # --- wypisanie: tryb zwiezly (DOKLADNIE JEDNA LINIA) -------------------------

  # Wszystkie ucinane sufity, obu narzedzi - dla -TylkoSufity i pelnego raportu.
  # Linia jednego narzedzia bierze tylko swoje (patrz Rachunek-Narzedzia).
  $ucinane = @(Sortuj-Sufity @($sufity | Where-Object { $_.Ucina -and $_.Przekroczony }))
  $cosUcinane = ($ucinane.Count -gt 0)

  # Czerwone alarmy podnosza kod wyjscia. Informacje - nie: mowia, co sie stalo
  # i dlaczego, ale nic sie nie pali, a kod 1 za nie bylby falszywym alarmem
  # u kazdego, kto ten kod sprawdza (straznik, nadzorca).
  $alarmy = @()
  $informacje = @()

  # PROG TO PROCENT CALOSCI, NIE LICZBA TOKENOW. Calosc otwarcia sesji bierzemy
  # z pomiaru w transkryptach Claude Code (Pomiar-Otwarcia, same sesje - bez
  # workerow, bo nie o nich jest ten prog). Liczymy go tu RAZ, dla wszystkich
  # trybow, ktore pokazuja linie albo alarmy. Brak pomiaru to NIE zero i NIE alarm:
  # pole PowodCalosci mowi wtedy, dlaczego nie porownujemy.
  $otwarcie = $null
  $bladOtwarcia = ""
  if (-not $TylkoSufity) {
    try { $otwarcie = Pomiar-Otwarcia $false }
    catch { $bladOtwarcia = "pomiar otwarcia sesji sie wywrocil ($($_.Exception.Message))" }
  }

  $rCc = Rachunek-Narzedzia "Claude"
  $rCx = Rachunek-Narzedzia "Codex"
  if ($narzDomyslne -eq "Codex") { $rDom = $rCx; $rInny = $rCc } else { $rDom = $rCc; $rInny = $rCx }
  # Informacje (zolte, bez kodu 1) domyslnego narzedzia ida do wspolnej listy -
  # te same, ktore pokazuje linia i nadzorca. Drugie narzedzie dorzuca swoje nizej.
  $informacje += @($rDom.Informacje)

  # Nauka z rozmow (cykl wiedzy) - jedyny koszt w tym raporcie placony naprawde
  # wywolanym modelem. Alarm mowi ZA CO (ile wiadomosci), ZA JAKI OKRES (z ktorych
  # dni) i CZY TO SIE POWTARZA (zwykly dzien czy nadrabianie). Sama liczba nad
  # progiem dala 24.09.2026 czerwony alarm "pamiec kosztuje wiecej, niz powinna"
  # za jednorazowe nadrabianie rozmow sprzed tygodnia.
  # Pomiar starszy niz $DniCyklStary dni nie jest alarmem na dzis - o tym, ze cykl
  # stoi, mowi osobne ostrzezenie nizej.
  $cyklSwiezy = ($cykl -and ($null -ne $cykl.Tokeny) -and (($null -eq $cykl.Wiek) -or ($cykl.Wiek -le $DniCyklStary)))
  if ($cyklSwiezy) {
    $kiedyNauka = Kiedy-Cykl $cykl.Wiek
    if (-not $kiedyNauka) { $kiedyNauka = "ostatnio" }
    $okresNauki = Zakres-Krotko $ocena.ZakresOd $ocena.ZakresDo
    $ileWiad  = "nieznana liczba wiadomosci"
    $ileWiadB = "nieznana liczbe wiadomosci"
    if ($null -ne $ocena.Wiadomosci) {
      $ileWiad  = "$(Liczba $ocena.Wiadomosci) wiadomosci"
      $ileWiadB = $ileWiad
    }
    $zOkresu = ""
    if ($okresNauki) { $zOkresu = " z $okresNauki" }
    $typowy = Zdanie-Typowego-Dnia $ocena
    $zwyklyNadProgiem = (($null -ne $ocena.Zwykle) -and ($ocena.Zwykle -gt $AlarmCyklu))

    if ($zwyklyNadProgiem) {
      $alarmy += Alarm "nauka $kiedyNauka ~$(Liczba $ocena.Zwykle) tokenow za zwykly dzien (prog $(Liczba $AlarmCyklu))" `
        ("Nauka z rozmow kosztowala $kiedyNauka ($($cykl.Data)) ~$(Liczba $ocena.Zwykle) tokenow za material z jednego dnia " +
         "($ileWiad$zOkresu), a prog zwyklego dnia to $(Liczba $AlarmCyklu). To NIE jest nadrabianie zaleglosci - " +
         "cykl wracal po kolejne raty ze swiezymi rozmowami. $typowy " +
         "Zajrzyj do $plikCyklOstatni. Trwale zbijesz to, zmniejszajac `$MaxNadrabiania albo `$MaxProb w narzedzia\cykl-dzienny.ps1.") `
        "cykl-zwykly" "pilne" $ocena.Zwykle $AlarmCyklu $okresNauki
    }

    if ((-not $zwyklyNadProgiem) -and ($null -ne $ocena.Razem) -and ($ocena.Razem -gt $ProgInformacjiNauki) -and ($ocena.Nadrabianie -gt 0)) {
      $wTym = ""
      if ($ocena.Zwykle -gt 0) {
        $wTym = " W tym ~$(Liczba $ocena.Zwykle) tokenow za swieze rozmowy - ta czesc miesci sie w progu zwyklego dnia ($(Liczba $AlarmCyklu))."
      }
      $informacje += Alarm "nauka $kiedyNauka ~$(Liczba $ocena.Razem) tokenow - nadrabianie $ileWiad$zOkresu, jednorazowo" `
        ("Nauka z rozmow kosztowala $kiedyNauka ~$(Liczba $ocena.Razem) tokenow, bo NADRABIALA zaleglosc: przeczytala $ileWiadB$zOkresu.$wTym " +
         "To jednorazowe nadrabianie, nie nowy staly koszt - gdy zaleglosc sie skonczy, nauka czyta tylko rozmowy z poprzedniego dnia. $typowy") `
        "cykl-nadrabianie" "info" $ocena.Razem $ProgInformacjiNauki $okresNauki
    } elseif ((-not $zwyklyNadProgiem) -and ($ocena.Rodzaj -eq "nieznany") -and ($ocena.Razem -gt $AlarmCyklu)) {
      $informacje += Alarm "nauka $kiedyNauka ~$(Liczba $ocena.Razem) tokenow - nie wiadomo, za jaki okres" `
        ("Nauka z rozmow kosztowala $kiedyNauka ~$(Liczba $ocena.Razem) tokenow, ale nie zapisala, z jakiego okresu czytala rozmowy - " +
         "wiec nie da sie powiedziec, czy to jednorazowe nadrabianie zaleglosci, czy zwykly dzien (prog zwyklego dnia to $(Liczba $AlarmCyklu)). " +
         "Zakres zapisuje nowsza wersja modulu pamieci (lore) - po aktualizacji ta niewiadoma zniknie.") `
        "cykl-nieznany" "uwaga" $ocena.Razem $AlarmCyklu ""
    }

    if ($ocena.Wzrosty -ge $DniWzrostuCyklu) {
      $okresWzrostu = $ocena.WzrostOd.ToString('dd.MM') + "-" + $ocena.WzrostDo.ToString('dd.MM')
      $alarmy += Alarm "koszt nauki rosnie $($ocena.Wzrosty) dni z rzedu (${okresWzrostu}, ~$(Liczba $ocena.WzrostOdTokeny) -> ~$(Liczba $ocena.WzrostDoTokeny) tokenow na dzien)" `
        ("Koszt zwyklego dnia nauki (bez nadrabiania) rosl $($ocena.Wzrosty) dni z rzedu, za kazdym razem o co najmniej $ProcWzrostuCyklu procent - " +
         "od $($ocena.WzrostOd.ToString('yyyy-MM-dd')) (~$(Liczba $ocena.WzrostOdTokeny) tokenow) do $($ocena.WzrostDo.ToString('yyyy-MM-dd')) (~$(Liczba $ocena.WzrostDoTokeny) tokenow). " +
         "To trend, nie jednorazowy skok. Co nauka czytala - w $plikCyklOstatni.") `
        "cykl-rosnie" "pilne" $ocena.Wzrosty $DniWzrostuCyklu $okresWzrostu
    }
  }

  # Historia kosztow tez nie ma prawa zawiesc po cichu: podsumowanie samo zglasza,
  # gdy dziennik sie nie zapisuje (lore\lore\facts.py, _anomaly), a nieczytelne
  # linie dziennika to koszt, ktorego nie ma w zadnej sumie.
  $nieprawidlowosc = Klucz-Tekst $podsum "nieprawidlowosc"
  if ($nieprawidlowosc) {
    $zKiedy = Klucz-Tekst $podsum "zaktualizowano"
    if (-not $zKiedy) { $zKiedy = "data nieznana" }
    $informacje += Alarm "historia kosztow nauki sie nie zapisuje" `
      ("Podsumowanie kosztow nauki (stan z $zKiedy) zglasza: $nieprawidlowosc. " +
       "Dopoki to trwa, statystyka 7 i 30 dni jest niepelna. Plik: $plikPodsum.") `
      "historia" "uwaga" $null $null $zKiedy
  }
  if ($historia.Pominiete -gt 0) {
    $informacje += Alarm "dziennik kosztow nauki ma $($historia.Pominiete) nieczytelnych linii" `
      ("W dzienniku przebiegow nauki $($historia.Pominiete) linii nie pasuje do kolumn - ich koszt nie jest liczony ani w statystyce, ani w ocenie dnia. " +
       "Plik: $plikHistoria.") `
      "historia" "uwaga" $historia.Pominiete $null ""
  }

  $liniaDom     = Linia-Narzedzia $rDom
  $liniaZwiezla = $liniaDom.Linia
  $kodWyjscia   = $liniaDom.Kod
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["alarmy"] = $true
