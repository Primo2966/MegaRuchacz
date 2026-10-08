# zasobnik\nadzorca\stan-cykl.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Cykl wiedzy: co o nim wiadomo (Stan-Cyklu - pliki
# w .claude\wiedza i kolejka z wyciagnij-fakty.ps1 -Kolejka), ile godzin stoi
# (Godzin-Od-Cyklu), wiersze dla okna (Opis-Cyklu), czy ma dzis ruszyc
# (Czy-Ruszac-Cykl), start w tle (Ruszaj-Cykl - na sucho przy -Proba) i wynik
# czytania recznego z okna (Stan-Recznego, Ocena-Klikniecia).
# Skad wolane: stan-zbieranie.ps1, dozor.ps1 (decyzja i start), okno.ps1
# (przycisk czytania rozmow), szczegoly.ps1. Wczytuje go stan-nadzorcy.ps1
# kropka - same definicje.

# ------------------------------------------------------------------ cykl wiedzy

# Wszystko, co wiadomo o cyklu: kiedy chodzil, ile czeka w kolejce, ile kosztowal.
# $zKolejka = $true doklada przebieg probny wylawiania (nie wola modelu, ~0,4 s) -
# w oknie tak, w dozorze tylko wtedy, gdy i tak zaraz startujemy cykl.
function Stan-Cyklu([bool]$zKolejka) {
  $c = [pscustomobject]@{
    Data       = $null     # kiedy ostatnio sie skonczyl (z cykl-ostatni.txt)
    Status     = $null
    Opis       = $null
    Zaleglosc  = $null     # ile przebiegow zostalo wg ostatniego podsumowania
    Kawalki    = $null     # ile kawalkow rozmow czeka NA ZYWO
    Przebiegi  = $null
    Pracuje    = $false
    Koszt      = $null     # tokeny ostatniego przebiegu
    KosztData  = $null
    KosztOpis  = $null
    KosztWywolan = $null   # ile wywolan modelu zlozylo sie na ten koszt - z tego
                           # i tylko z tego liczy sie szacunek przed przyciskiem
    Powody     = @()       # czego nie dalo sie odczytac i dlaczego
  }

  $plikOstatni = Join-Path $script:NadzWiedza "cykl-ostatni.txt"
  if (Test-Path $plikOstatni) {
    $k = Czytaj-Klucze $plikOstatni
    $c.Data      = Data-Lub-Nic $k["data"]
    $c.Status    = $k["status"]
    $c.Opis      = $k["opis"]
    if ($k["zaleglosc"] -match '^\d+$') { $c.Zaleglosc = [int]$k["zaleglosc"] }
    if (-not $c.Data) { $c.Powody += "w ${plikOstatni} nie ma czytelnej daty (klucz 'data')" }
  } else {
    $c.Powody += "nie ma ${plikOstatni} - cykl nie zakonczyl na tej maszynie ani jednego przebiegu"
  }

  $postep = Czytaj-Klucze (Join-Path $script:NadzWiedza ".cykl-postep")
  if ($postep["stan"] -eq "pracuje") {
    $kiedy = Data-Lub-Nic $postep["czas"]
    # Znacznik starszy niz trzy godziny to nie praca, tylko przebieg, ktory padl
    # w polowie - tak samo liczy to straznik przed startem cyklu.
    if ($kiedy -and (([datetime]::Now - $kiedy).TotalHours -lt 3)) { $c.Pracuje = $true }
  }

  $plikKosztu = Join-Path $script:NadzWiedza ".koszt-cyklu.txt"
  if (Test-Path $plikKosztu) {
    $k = Czytaj-Klucze $plikKosztu
    $c.KosztData = Data-Lub-Nic $k["data"]
    if ($k["tokeny"] -match '^\d+$') { $c.Koszt = [long]$k["tokeny"] }
    if ($k["wywolania"] -match '^\d+$') { $c.KosztWywolan = [int]$k["wywolania"] }
    $czesci = @()
    if ($k["wywolania"] -match '^\d+$') { $czesci += "$($k['wywolania']) wywolan $($k['narzedzie'])" }
    if ($k["fakty"] -match '^\d+$')     { $czesci += "$($k['fakty']) faktow" }
    if ($czesci.Count -gt 0) { $c.KosztOpis = ($czesci -join ", ") }
    if ($null -eq $c.Koszt) { $c.Powody += "w ${plikKosztu} nie ma liczby tokenow" }
  } else {
    $c.Powody += "nie ma ${plikKosztu} - cykl nigdy nie policzyl swojego kosztu"
  }

  if ($zKolejka) {
    $wyciagnij = Join-Path $script:NadzZrodlo "narzedzia\wyciagnij-fakty.ps1"
    $r = Wolaj-Skrypt $wyciagnij @("-Zrodlo", ('"' + $script:NadzZrodlo + '"'), "-Kolejka") 90
    if ($r.ok -and $r.kod -eq 0) {
      $k = Klucze-Z-Tekstu $r.tekst
      if ($k["kolejka.kawalki"]   -match '^\d+$') { $c.Kawalki   = [int]$k["kolejka.kawalki"] }
      if ($k["kolejka.przebiegi"] -match '^\d+$') { $c.Przebiegi = [int]$k["kolejka.przebiegi"] }
      if ($null -eq $c.Kawalki) { $c.Powody += "przebieg probny wylawiania nie oddal liczb kolejki" }
    } else {
      $powod = $r.powod
      if (-not $powod) { $powod = "kod wyjscia $($r.kod)" }
      $c.Powody += "nie dalo sie policzyc kolejki na zywo (${powod}) - zostaje liczba z ostatniego podsumowania"
    }
  }
  return $c
}

# Ile godzin cykl stoi. $null, gdy nie wiadomo - i wtedy TEZ jest problem,
# bo brak daty ostatniego przebiegu znaczy, ze cykl nie skonczyl nigdy.
function Godzin-Od-Cyklu($c) {
  if (-not $c.Data) { return $null }
  return [int]([datetime]::Now - $c.Data).TotalHours
}

function Opis-Cyklu($c, $o = $null) {
  $linie = @()
  if ($c.Data) {
    $godzin = Godzin-Od-Cyklu $c
    $kiedy = "$($c.Data.ToString('yyyy-MM-dd HH:mm'))"
    $waga = ""
    if ($godzin -lt 24) { $kiedy = "$kiedy (dziś, $godzin h temu)" }
    else { $kiedy = "$kiedy ($([int]($godzin / 24)) dni temu)"; $waga = "uwaga" }
    $linie += Wiersz "Ostatnia nauka" $kiedy $waga
    $st = $c.Status
    $wagaSt = ""
    if (-not $st) { $st = "nie wiadomo - w pliku stanu nie ma pola 'status'"; $wagaSt = "uwaga" }
    $linie += Wiersz "Jak poszła" $st $wagaSt
    if ($c.Opis) { $linie += Wiersz "" $c.Opis "szary" }
  } else {
    $linie += Wiersz "Ostatnia nauka" "nigdy albo nie da się tego odczytać" "pilne"
  }
  if ($c.Pracuje) { $linie += Wiersz "Teraz" "nauka właśnie pracuje" }

  if ($null -ne $c.Kawalki) {
    $ogon = ""
    if ($null -ne $c.Przebiegi) { $ogon = " ($($c.Przebiegi) $(Odmiana ([int]$c.Przebiegi) 'porcja' 'porcje' 'porcji') do modelu)" }
    $linie += Wiersz "Czeka na przeczytanie" "$(Liczba-Ludzka $c.Kawalki) $(Odmiana ([int]$c.Kawalki) 'fragment rozmów' 'fragmenty rozmów' 'fragmentów rozmów')${ogon}"
  } elseif ($null -ne $c.Zaleglosc) {
    $linie += Wiersz "Czeka na przeczytanie" "$($c.Zaleglosc) $(Odmiana ([int]$c.Zaleglosc) 'porcja' 'porcje' 'porcji') według ostatniego podsumowania (na żywo nie policzone)" "uwaga"
  } else {
    $linie += Wiersz "Czeka na przeczytanie" "nie wiadomo" "uwaga"
  }

  if ($null -ne $c.Koszt) {
    $kiedy = "nieznanego dnia"
    if ($c.KosztData) { $kiedy = $c.KosztData.ToString('yyyy-MM-dd') }
    $ogon = ""
    if ($c.KosztOpis) { $ogon = " - $($c.KosztOpis)" }
    # $o = Opis-Startu: procent jednego otwarcia sesji obok tokenow (P15)
    $js = Jak-Sesji $c.Koszt $o
    if ($js) { $js = " ($js)" }
    $linie += Wiersz "Ostatni koszt nauki" "~$(Liczba-Ludzka $c.Koszt) tokenów${js}, ${kiedy}${ogon}"
    $linie += Wiersz "" "to PRAWDZIWE wywołanie modelu, osobno od rachunku za pamięć" "szary"
  } else {
    $linie += Wiersz "Ostatni koszt nauki" "jeszcze ani razu nie policzony" "uwaga"
  }
  foreach ($p in $c.Powody) { $linie += Wiersz "Czego nie wiem" "$p" "uwaga" }
  return ,$linie
}

# Czy cykl ma dzis ruszyc. Warunek ten sam, co dzis w straznik-zasad.ps1:
# inna data w .cykl-stan niz dzisiejsza (albo przebieg odlozony, czyli taki,
# ktorego w ogole nie bylo), do tego zaden przebieg nie pracuje w tej chwili.
# Pusta kolejka jest jedynym powodem, zeby nie ruszac - kolejki, ktorej nie
# umiemy odczytac, nie udajemy i cykl idzie, bo sam powie, co mu przeszkadza.
# P59d: tylko z modulem Wiedza w rejestrze instalacji ($inst = Stan-Instalacji;
# nieczytelny rejestr = wszystko wlaczone, wiec cykl idzie jak dotad). Do tej pory
# jedynym warunkiem "modul jest" byl lore\pyproject.toml - plik w repo, po kazdym
# klonie obecny, wiec bez nauki w instalacji cykl ruszalby codziennie i padal.
function Czy-Ruszac-Cykl($inst = $null) {
  $w = [pscustomobject]@{ Ruszac = $false; Powod = "" }
  if (-not (Modul-Jest $inst "wiedza")) {
    $w.Powod = "modul Wiedza nie jest zainstalowany (rejestr instalacji) - nauka z rozmow nie chodzi"
    return $w
  }
  $skrypt = Join-Path $script:NadzZrodlo "narzedzia\cykl-dzienny.ps1"
  if (-not (Test-Path $skrypt)) {
    $w.Powod = "nie ma ${skrypt}"
    return $w
  }
  if (-not (Test-Path (Join-Path $script:NadzZrodlo "lore\pyproject.toml"))) {
    $w.Powod = "nie ma modulu pamieci (lore) - cykl nie mialby czego czytac"
    return $w
  }
  $dzis = Get-Date -Format 'yyyy-MM-dd'
  $stan = Czytaj-Klucze (Join-Path $script:NadzWiedza ".cykl-stan")
  if (($stan["data"] -eq $dzis) -and ($stan["status"] -ne "odlozony")) {
    $w.Powod = "cykl chodzil juz dzis ($dzis, status $($stan['status']))"
    return $w
  }
  $c = Stan-Cyklu $false
  if ($c.Pracuje) {
    $w.Powod = "cykl wlasnie pracuje"
    return $w
  }
  $w.Ruszac = $true
  $w.Powod = "ostatni przebieg: $($stan['data']), dzis jest $dzis"
  return $w
}

# $recznie = $true: przycisk w oknie po potwierdzeniu kosztu (cykl-dzienny.ps1 -Recznie -
# czyta takze po dzisiejszym przebiegu, wynik zostawia w .cykl-reczny). Dozor wola bez niego.
function Ruszaj-Cykl([bool]$recznie = $false) {
  $skrypt = Join-Path $script:NadzZrodlo "narzedzia\cykl-dzienny.ps1"
  $argumenty = '-Zrodlo "' + $script:NadzZrodlo + '" -KatalogDomowy "' + $script:NadzDom + '"'
  if ($recznie) { $argumenty += ' -Recznie' }
  if ($script:NadzProba) {
    Write-Host "[proba] NIE startuje cyklu: powershell -File ${skrypt} ${argumenty}"
    return $true
  }
  $poszlo = Odpal-W-Tle $skrypt $argumenty
  if ($poszlo) {
    Notuj "wystartowal cykl wiedzy$(if ($recznie) { ' (czytanie reczne z okna)' })"
    try { Dopisz-Klucze $script:NadzPlikStanu @{ "cykl.ruszony" = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') } }
    catch { Notuj "nie udalo sie zapisac znacznika startu cyklu" }
  }
  return $poszlo
}

# ------------------------------------------------- czytanie reczne z okna (08.10.2026)
# Przycisk "Przeczytaj teraz nowe rozmowy" odpalal do 08.10 zwykly cykl, a ten po dzisiejszym
# przebiegu konczyl sie od razu - uzytkownik potwierdzal koszt i nie dzialo sie nic, bez slowa.
# Teraz idzie cykl-dzienny.ps1 -Recznie, ktory KAZDE swoje zakonczenie (takze odmowe) zapisuje
# w ~\.claude\wiedza\.cykl-reczny, a tu ten zapis zamienia sie w zdanie dla czlowieka.

# Ile sekund od klikniecia okno czeka na pierwszy znak zycia (.cykl-reczny ze "stan: pracuje").
# Przebieg pisze go zaraz po zamku, przed jakakolwiek praca - zmierzone w test-cykl-reczny.ps1:
# 0,5 s od startu procesu do pierwszego zapisu. 60 s to ponad stokrotny zapas na zapchana maszyne;
# po nim cisza JEST juz wiadomoscia (przebieg nie wstal), a nie powodem do dalszego czekania.
$SEKUND_NA_START_RECZNEGO = 60
# "Pracuje" starsze niz tyle godzin nie jest praca - ten sam prog, co przy .cykl-postep
# (Stan-Cyklu, straznik-zasad.ps1): to przebieg, ktory padl w polowie.
$GODZIN_PRACY_RECZNEGO = 3

# Chwila po ludzku: dzisiejsza jako sama godzina ("08:04"), wczorajsza z "wczoraj", starsza z data.
function Chwila-Krotko($tekst) {
  $d = Data-Lub-Nic $tekst
  if (-not $d) { return $null }
  if ($d.Date -eq [datetime]::Today) { return $d.ToString("HH:mm") }
  if ($d.Date -eq [datetime]::Today.AddDays(-1)) { return "wczoraj " + $d.ToString("HH:mm") }
  return $d.ToString("dd.MM HH:mm")
}

# Czy proces z wpisu jeszcze zyje. Brak procesu to odpowiedz ("zniknal"), nie blad.
function Proces-Recznego-Zyje($pidTekst) {
  if ("$pidTekst" -notmatch '^\d+$') { return $false }
  $p = Get-Process -Id ([int]$pidTekst) -ErrorAction SilentlyContinue
  if (-not $p) { return $false }
  return ($p.ProcessName -match '^(powershell|pwsh)$')
}

# Ostatnie czytanie reczne: $null, gdy jeszcze ani razu go nie bylo. Krotki = zdanie pod
# przyciskiem, Pelny = okienko po zakonczeniu (z tym, co zrobic). Udane = czytalo naprawde.
function Stan-Recznego {
  $plik = Join-Path $script:NadzWiedza ".cykl-reczny"
  if (-not (Test-Path -LiteralPath $plik)) { return $null }
  $k = Czytaj-Klucze $plik
  $r = [pscustomobject]@{
    Start = Data-Lub-Nic $k["start"]; Czas = Data-Lub-Nic $k["czas"]; Stan = $k["stan"]
    Wynik = $k["wynik"]; Powod = $k["powod"]; Trwa = $false; Przerwane = $false
    Udane = $false; Dzis = $false; Krotki = ""; Pelny = ""
  }
  $kiedy = Chwila-Krotko $k["czas"]
  if (-not $kiedy) { $kiedy = "?" }
  $od = Chwila-Krotko $k["od"]
  $odTekst = $(if ($od) { "od $od" } else { "od początku" })
  $tokeny = $(if ($k["tokeny"] -match '^\d+$' -and [long]$k["tokeny"] -gt 0) { ", $(Tokeny-Okolo ([long]$k['tokeny'])) tokenów" } else { "" })
  $porcje = 0
  if ($k["porcje"] -match '^\d+$') { $porcje = [int]$k["porcje"] }
  $ile = "$porcje $(Odmiana $porcje 'porcja' 'porcje' 'porcji')"
  if ($k["przeczytane"] -match '^\d+$') {
    $ile = "$(Liczba-Ludzka ([long]$k['przeczytane'])) $(Odmiana ([int]$k['przeczytane']) 'fragment rozmów' 'fragmenty rozmów' 'fragmentów rozmów')"
  }
  $zostalo = 0
  if ($k["zostalo"] -match '^\d+$') { $zostalo = [int]$k["zostalo"] }
  $slad = "Ślad: $(Join-Path $script:NadzDom '.claude\.megaruchacz-zasobnik.log')."

  if ($r.Stan -eq "pracuje") {
    $start = Chwila-Krotko $k["start"]
    $swiezy = $r.Czas -and (([datetime]::Now - $r.Czas).TotalHours -lt $GODZIN_PRACY_RECZNEGO)
    if ($swiezy -and (Proces-Recznego-Zyje $k["pid"])) {
      $r.Trwa = $true
      $r.Krotki = "Czytanie uruchomione o $start trwa. Wynik pokażę tutaj, gdy skończy."
    } else {
      $r.Przerwane = $true
      $r.Wynik = "przerwane"
      $r.Krotki = "Czytanie z $start urwało się bez wyniku - proces zniknął w trakcie."
      $r.Pelny = "Czytanie rozmów uruchomione o $start urwało się w trakcie i nie zostawiło wyniku (proces zniknął, np. po restarcie komputera albo nadzorcy).`r`n`r`nTo, czego nie zdążyło przeczytać, czeka - możesz kliknąć jeszcze raz.`r`n$slad"
    }
  } else {
    switch ("$($r.Wynik)") {
      "ok" {
        $r.Udane = $true
        $r.Krotki = "Przeczytane o ${kiedy}: $ile $odTekst$tokeny. Nic więcej nie czeka."
      }
      { $_ -in @("dogania", "nie nadaza") } {
        $r.Udane = $true
        $r.Krotki = "Przeczytane o ${kiedy}: $ile $odTekst$tokeny. Czeka jeszcze $zostalo $(Odmiana $zostalo 'porcja' 'porcje' 'porcji')."
      }
      "nic" {
        $r.Krotki = "Nic nowego $odTekst - nie było czego czytać (sprawdzone o $kiedy, bez kosztu)."
        $r.Pelny = "Nic nowego $odTekst - nie było czego czytać.`r`n`r`nModel nie był wołany, nic to nie kosztowało."
      }
      "zajete" {
        $r.Krotki = "Nie ruszyło ($kiedy): czytanie rozmów już trwa. Liczby odświeżą się, gdy skończy."
        $r.Pelny = "Czytanie nie ruszyło drugi raz - rozmowy czyta właśnie inny przebieg (automat albo wcześniejsze kliknięcie).`r`n`r`nNic nie zostało wydane. Liczby odświeżą się, gdy tamten skończy."
      }
      "odlozony" {
        $powod = "$($r.Powod)"
        if ($porcje -gt 0) {
          $r.Krotki = "Przerwane o $kiedy (przeczytane: $ile $odTekst): $powod. Reszta czeka."
          $r.Pelny = "Czytanie rozmów przerwało się w połowie (przeczytane: $ile $odTekst$tokeny).`r`n`r`nPowód: $powod.`r`n`r`nReszta czeka nietknięta - możesz spróbować jeszcze raz, gdy przeszkoda minie."
        } else {
          $r.Krotki = "Nic nie przeczytane ($kiedy): $powod. Rozmowy czekają."
          $r.Pelny = "Czytanie rozmów nie przeczytało nic.`r`n`r`nPowód: $powod.`r`n`r`nRozmowy czekają nietknięte - możesz spróbować jeszcze raz, gdy przeszkoda minie."
        }
      }
      "wyzerowane" {
        $r.Krotki = "Nie ruszyło ($kiedy): pliki pamięci są wyzerowane - patrz Przegląd."
        $r.Pelny = "Czytanie rozmów nie ruszyło, bo pliki pamięci są wyzerowane - nic nie zostało przeczytane ani zapisane.`r`n`r`n$($r.Powod)"
      }
      "blad" {
        $r.Krotki = "Czytanie ($kiedy) wywróciło się: $($r.Powod)"
        $r.Pelny = "Czytanie rozmów wywróciło się w trakcie.`r`n`r`nBłąd: $($r.Powod)`r`n`r`n$slad"
      }
      default {
        $r.Krotki = "Czytanie ($kiedy) skończyło się wynikiem, którego nie znam: '$($r.Wynik)'."
        $r.Pelny = "$($r.Krotki)`r`n`r`n$slad"
      }
    }
  }
  $chwila = $(if ($r.Czas) { $r.Czas } else { $r.Start })
  $r.Dzis = [bool]($chwila -and ($chwila.Date -eq [datetime]::Today))
  if ($r.Udane -or -not $r.Pelny) { $r.Pelny = $r.Krotki }
  return $r
}

# Co z kliknieciem o $klik: "czekam" (wyniku jeszcze nie ma), "trwa", "koniec" albo "cisza"
# (przez $SEKUND_NA_START_RECZNEGO s ani sladu - przebieg nie wstal). Wynik jest "nasz",
# gdy przebieg ruszyl nie wczesniej niz klikniecie (5 s luzu na zaokraglenie do sekundy).
function Ocena-Klikniecia($r, $klik, [datetime]$teraz) {
  if (-not $klik) { return "koniec" }
  $nasz = $r -and $r.Start -and ($r.Start -ge ([datetime]$klik).AddSeconds(-5))
  if (-not $nasz) {
    if (($teraz - [datetime]$klik).TotalSeconds -ge $SEKUND_NA_START_RECZNEGO) { return "cisza" }
    return "czekam"
  }
  if ($r.Trwa) { return "trwa" }
  return "koniec"
}

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["cykl"] = $true
