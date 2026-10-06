# narzedzia\koszt\raport-pelny.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz
# BUDOWA w jego naglowku). Pelny raport - tryb bez przelacznika, ten sam, ktory raz
# na dobe zapisuje zadanie LoreKoszt (pomiar-dzienny.ps1): pomiary tylko do niego
# (kolejka Lore, pliki wiedzy, poczekalnia), ostrzezenia, sekcje 0-10 z liniami
# POMIAR i wypisanie $script:Raport (kolorem albo zwyklym wyjsciem).
# Skad wolane: koszt-pamieci.ps1 kropka (". Raport-Pelny") na samym koncu; kod
# wyjscia (1 przy ucinaniu albo alarmie) i $sciezkaSkryptu daje tamten plik.

# --- wypisanie: pelny raport -------------------------------------------------

function Wypisz-Kubelek($pozycje, $razem, $czegoNieMa) {
  # Pozycje od najdrozszej, bo tylko gorna czesc listy ma znaczenie przy
  # skracaniu. Drobiazgi ponizej 1% ida w jedna linie "reszta" - wypisane
  # osobno tylko zaslanialyby to, co naprawde kosztuje.
  $l = @($pozycje)
  if ($l.Count -eq 0) {
    Linia "  $czegoNieMa"
    return
  }
  $reszta = 0
  $ileReszty = 0
  foreach ($p in ($l | Sort-Object -Property Tokeny -Descending)) {
    if ($p.Procent -lt 1) { $reszta += $p.Tokeny; $ileReszty++; continue }
    Linia ("  {0,-38} {1,8} znakow, ~{2,6} tokenow, {3,3}% tego rachunku" -f `
           (Skroc $p.Nazwa 38), (Liczba $p.Znaki), (Liczba $p.Tokeny), $p.Procent)
    Linia ("       z pliku: {0}" -f $p.Skad)
  }
  if ($ileReszty -gt 0) {
    Linia ("  {0,-38} {1,8}        ~{2,6} tokenow, ponizej 1%" -f `
           "reszta ($ileReszty poz.)", "", (Liczba $reszta))
  }
  Linia ("  {0,-38} {1,8}        ~{2,6} tokenow" -f "RAZEM", "", (Liczba $razem))
}

function Wiersz-Sufitu($s) {
  $znak  = "  "
  $kolor = $null
  if ($s.Zmierzony -and (-not $s.Informacyjny)) {
    if ($s.Przekroczony) { $znak = "!!"; $kolor = "Red" }
    elseif ($s.Procent -ge $ProgCiasno) { $znak = "! "; $kolor = "Yellow" }
  }
  Linia ("  {0} {1}" -f $znak, $s.Nazwa) $kolor
  if (-not $s.Zmierzony) {
    Linia ("       bez pomiaru: {0}" -f $s.Uwaga)
  } elseif ($s.Przekroczony) {
    Linia ("       {0} z {1} {2} - PRZEKROCZONE o {3} ({4}% sufitu)" -f `
           (Liczba $s.Teraz), (Liczba $s.Limit), $s.Jednostka, (Liczba $s.Strata), $s.Procent) $kolor
  } else {
    Linia ("       {0} z {1} {2} - zapasu {3}%" -f `
           (Liczba $s.Teraz), (Liczba $s.Limit), $s.Jednostka, $s.Zapas)
  }
  Linia ("       po przekroczeniu: {0}" -f $s.Skutek)
  Linia ("       sufit {0}; czytamy go z: {1}" -f $s.Czyj, $s.SkadLimitu)
  if ($s.Zmierzony -and $s.Plik) { Linia ("       mierzymy: {0}" -f $s.Plik) }
}

# Porownanie z poprzednim pomiarem - osobno dla kazdego narzedzia, bo kazde
# ma wlasna linie POMIAR (patrz Poprzedni-Pomiar).
function Wypisz-Porownanie($r) {
  if (-not $r.Poprz) {
    if (Test-Path -LiteralPath $plikOstatni) {
      # plik jest, ale bez linii POMIAR - "nie ma poprzedniego pomiaru" bylby tu
      # polprawda, a przyczyna (stary albo uciety raport) zniknelaby bez sladu
      Linia "  Plik $plikOstatni jest, ale nie ma w nim linii POMIAR ani RAZEM - poprzedniej liczby nie umiem odczytac."
    } else {
      Linia "  Poprzedniego pomiaru nie ma ($plikOstatni) - nie ma z czym porownac. Powstanie przy najblizszym dziennym raporcie."
    }
    return
  }
  $dataPoprz = "data nieznana"
  if ($r.Poprz.Data) { $dataPoprz = $r.Poprz.Data.ToString("yyyy-MM-dd HH:mm") }
  if (-not $r.Poprz.Porownywalny) {
    Linia "  Poprzedni pomiar ($dataPoprz): nie porownuje - $($r.Poprz.Powod). Porownanie wroci po najblizszym dziennym raporcie ($plikOstatni)."
    return
  }
  $opisZmiany = "bez zmian"
  if ($r.Zmiana -gt 0) { $opisZmiany = "+$(Liczba $r.Zmiana), +$($r.ZmianaProc)%" }
  elseif ($r.Zmiana -lt 0) { $opisZmiany = "$(Liczba $r.Zmiana), $($r.ZmianaProc)%" }
  $kolorZmiany = $null
  if ($r.Skok) { $kolorZmiany = "Yellow" }
  Linia ("  Poprzedni pomiar ({0}): {1} -> {2} tokenow na starcie sesji {3} ({4})" -f `
         $dataPoprz, (Liczba $r.Poprz.Tokeny), (Liczba $r.TokS), $r.Nazwa, $opisZmiany) $kolorZmiany
}

# Raport-Pelny - pomiary do pelnego raportu, ostrzezenia i wydruk.
# Wola go koszt-pamieci.ps1 KROPKA (". Raport-Pelny"), wiec biegnie w zasiegu skryptu
# glownego: zmienne i funkcje, ktore tu powstaja, widzi dalszy przebieg - tak samo,
# jak gdy ten kod stal w koszt-pamieci.ps1 wprost.
function Raport-Pelny {
  # --- pomiary tylko do pelnego raportu ----------------------------------------
  # (zapytania do bazy Lore potrafia chwile trwac, wiec w trybie zwiezlym ich nie ma)

  $kolejka = Kolejka-Lore $bazaLore $plikZnacznik
  $kawalek = Najdluzszy-Kawalek $bazaLore

  $przebiegi = 0
  if ($kolejka.Ok -and $limitWejscia -and $limitWejscia -gt 0) {
    $przebiegi = [int][math]::Ceiling([double]$kolejka.Ile / [double]$limitWejscia)
  }

  $sufity += Sufit ([ordered]@{
    Nazwa      = "jedna porcja rozmow wysylana do wyciagania faktow"
    Krotka     = "porcja dla Lore"
    Teraz      = $(if ($kolejka.Ok) { $kolejka.Ile } else { $null })
    Limit      = $limitWejscia
    Jednostka  = "znakow"
    Czyj       = "NASZ - stala w lore\lore\facts.py"
    SkadLimitu = "lore\lore\facts.py (MAX_INPUT_CHARS)"
    Plik       = $bazaLore
    Skutek     = "nic nie ginie: co sie nie zmiesci, czeka w kolejce na kolejny przebieg (teraz do nadrobienia przebiegow: $przebiegi)"
    Ucina      = $false
    Informacyjny = $true
    Uwaga      = (Powod-Braku $(if ($kolejka.Ok) { $kolejka.Ile } else { $null }) $limitWejscia "nie da sie policzyc kolejki: $($kolejka.Powod)" "lore\lore\facts.py")
  })

  $sufity += Sufit ([ordered]@{
    Nazwa      = "krojenie rozmowy na kawalki do wyszukiwania"
    Krotka     = "kawalek rozmowy"
    Teraz      = $(if ($kawalek.Ok) { $kawalek.Ile } else { $null })
    Limit      = $limitKawalka
    Jednostka  = "znakow"
    Czyj       = "NASZ - stala w lore\lore\index.py"
    SkadLimitu = "lore\lore\index.py (CHUNK_SIZE)"
    Plik       = $bazaLore
    Skutek     = "nic nie ginie, ale dluzsza wypowiedz jest krojona na kawalki - czasem w pol slowa; tak ma byc, to nie jest przekroczenie"
    Ucina      = $false
    Informacyjny = $true
    Uwaga      = (Powod-Braku $(if ($kawalek.Ok) { $kawalek.Ile } else { $null }) $limitKawalka "nie da sie zmierzyc kawalkow: $($kawalek.Powod)" "lore\lore\index.py")
  })

  # warstwa referencyjna: kandydaci i wlasny raport maja ponizej osobne linie,
  # wiec tutaj ich nie liczymy drugi raz
  $pliki = @()
  if (Test-Path -LiteralPath $katWiedzy) {
    $pliki = @(Get-ChildItem -LiteralPath $katWiedzy -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -ne "kandydaci.md" -and $_.Name -ne "koszt-ostatni.txt" })
  }
  $bajtyWiedzy = 0
  foreach ($p in $pliki) { $bajtyWiedzy += $p.Length }

  $kandydaci = $null
  $bladKandydatow = $null
  if (Test-Path -LiteralPath $plikKandydat) {
    $kandydaci = 0
    try {
      foreach ($l in @((Czytaj $plikKandydat) -split "`r?`n")) {
        if ($l -match '^\s*-\s*\[\s\]') { $kandydaci++ }
      }
    } catch {
      # plik jest, ale sie nie czyta - inaczej raport powiedzialby "nie ma pliku"
      $kandydaci = $null
      $bladKandydatow = "plik $plikKandydat jest, ale nie da sie go odczytac ($($_.Exception.Message))"
    }
  }

  $stare = @($w.Wpisy | Where-Object { $_.Stary })

  # --- ostrzezenia -------------------------------------------------------------

  # Pelny raport to audyt calej maszyny: alarmy OBU narzedzi (kazdy z nazwa
  # narzedzia w tresci, kazdy liczony na jego wlasnej sumie) plus wspolne alarmy
  # nauki z rozmow. Kod wyjscia pelnego raportu podnosi ktorykolwiek z nich.
  $alarmyNauki = @($alarmy)
  $alarmy = @($rDom.Alarmy)
  foreach ($ri in @($rInne)) { if ($ri.Jest) { $alarmy += @($ri.Alarmy) } }
  $alarmy += $alarmyNauki
  foreach ($ri in @($rInne)) { if ($ri.Jest) { $informacje += @($ri.Informacje) } }

  $ostrzezenia = @()
  foreach ($s in $ucinane) {
    $ostrzezenia += "UCINANE PO CICHU: $($s.Nazwa) - ginie $(Liczba $s.Strata) $($s.Jednostka) z $(Liczba $s.Teraz). Sufit $($s.SkadLimitu)."
  }
  foreach ($a in $alarmy) {
    $ostrzezenia += $a.Pelny
  }
  foreach ($s in $sufity) {
    if ($s.Zmierzony -and (-not $s.Informacyjny) -and (-not $s.Przekroczony) -and ($s.Procent -ge $ProgCiasno)) {
      $ostrzezenia += "Blisko sufitu: $($s.Nazwa) - zajete $($s.Procent)% ($(Liczba $s.Teraz) z $(Liczba $s.Limit) $($s.Jednostka))."
    }
  }
  if ($w.Wpisy.Count -gt $ProgBiezacych) {
    $ostrzezenia += "Warstwa biezaca ma $($w.Wpisy.Count) wpisow (prog $ProgBiezacych) - przejrzyj je i skasuj to, co juz nieaktualne."
  }
  if ($stare.Count -gt 0) {
    $ostrzezenia += "Przeterminowanych wpisow: $($stare.Count) - agent bierze je za prawde, wiec albo odswiez date, albo skasuj."
  }
  if (($kandydaci -ne $null) -and ($kandydaci -gt $ProgPoczekalni)) {
    $ostrzezenia += "W poczekalni czeka $kandydaci faktow (prog $ProgPoczekalni) - zatwierdz je albo odrzuc, bo same sie nie zuzyja."
  }
  if ($cykl -and ($null -ne $cykl.Wiek) -and ($cykl.Wiek -gt $DniCyklStary)) {
    $ostrzezenia += "Koszt cyklu wiedzy jest z dnia $($cykl.Data), sprzed $($cykl.Wiek) dni - od tego czasu cykl nie wylowil ani jednego faktu, wiec wiedza nie przyrasta."
  }

  # --- wypisanie: sekcje raportu (Wypisz-Kubelek, Wiersz-Sufitu i Wypisz-Porownanie - nad etapem)
  Linia ""
  Linia "Audyt pamieci i sufitow - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
  Linia "Katalog: $katKlaudii"

  Linia ""
  Linia "0. CO WYMAGA UWAGI TERAZ"
  if ((-not $cosUcinane) -and ($alarmy.Count -eq 0)) {
    Linia "  Nic nie jest ucinane, zaden prog nie jest przekroczony."
  }
  # Udzial w calym otwarciu sesji - zawsze jedna linia: procent albo zdanie,
  # dlaczego go nie ma. Brak pomiaru nie jest alarmem, wiec bez koloru.
  foreach ($rr in (@($rDom) + @($rInne))) {
    if (-not $rr.Jest) { continue }
    if ($null -ne $rr.Udzial) {
      Linia "  $($rr.Nazwa): MegaRuchacz to $(Procent-Tekst $rr.Udzial) otwarcia sesji (~$(Liczba $rr.Mr) z ~$(Liczba $rr.Calosc) tokenow, prog $(Liczba $AlarmCzesciOtwarcia) tokenow)."
    } else {
      Linia "  $($rr.Nazwa): udzialu w calym otwarciu sesji nie porownuje, bo $($rr.PowodCalosci)."
    }
  }
  if ($alarmy.Count -gt 0) {
    foreach ($a in $alarmy) {
      Linia ("  ALARM: {0}" -f $a.Krotko) "Red"
      Linia ("    {0}" -f $a.Pelny) "Red"
    }
    Linia "  Progi sa nasze - siedza na gorze narzedzia\koszt-pamieci.ps1 i zmienia sie je jedna linijka."
  }
  # Informacje sa zolte i nie podnosza kodu wyjscia: mowia, co sie stalo i za jaki
  # okres, ale niczego nie trzeba naprawiac.
  foreach ($a in $informacje) {
    $slowo = "INFO"
    if ($a.Waga -eq "uwaga") { $slowo = "DO SPRAWDZENIA" }
    Linia ("  {0}: {1}" -f $slowo, $a.Krotko) "Yellow"
    Linia ("    {0}" -f $a.Pelny) "Yellow"
  }
  if ((-not $cosUcinane) -and ($alarmy.Count -gt 0)) {
    Linia "  Nic za to nie jest ucinane - kazdy tekst miesci sie w swoim suficie."
  }
  if ($cosUcinane) {
    foreach ($s in $ucinane) {
      $procUtraty = 0
      if ([long]$s.Teraz -gt 0) { $procUtraty = [int][math]::Round(100.0 * $s.Strata / [double]$s.Teraz) }
      Linia ("  UCINANE: {0}" -f $s.Nazwa) "Red"
      Linia ("    ginie {0} {1} z {2} - {3}% tekstu, i to jego KONIEC" -f `
             (Liczba $s.Strata), $s.Jednostka, (Liczba $s.Teraz), $procUtraty) "Red"
      if ($s.Naglowek) {
        Linia ("    ucieta czesc zaczyna sie od naglowka: {0}" -f $s.Naglowek) "Red"
      } else {
        Linia "    w urwanej czesci nie ma naglowka, wiec nie umiem nazwac, co przepada" "Red"
      }
      Linia ("    tekst: {0}" -f $s.Plik)
      Linia ("    sufit: {0} {1} z {2}" -f (Liczba $s.Limit), $s.Jednostka, $s.SkadLimitu)
    }
  }

  Linia ""
  Linia "1. Sufity - gdzie stoi kazdy i ile zostalo zapasu"
  Linia "   (!! = przekroczony, ! = zajete ponad $ProgCiasno%; na gorze te najciasniejsze)"
  foreach ($s in (Sortuj-Sufity $sufity)) { Wiersz-Sufitu $s }

  Linia ""
  Linia "2. PRZY KAZDEJ Twojej wiadomosci - z czego sie sklada (kazde narzedzie osobno)"
  Linia "  Claude Code:"
  $brakPrzyp = "Nie znalazlem przypomnienia Claude Code - przy wiadomosci nie dokleja sie nic."
  if ($przypCcUwaga -and (@($kubWiadomosc).Count -eq 0)) { $brakPrzyp = "Przy wiadomosci nie dokleja sie nic: $przypCcUwaga." }
  Wypisz-Kubelek $kubWiadomosc $tokWiadomosc $brakPrzyp
  if ($przypCcUwaga -and (@($kubWiadomosc).Count -gt 0)) { Linia "  UWAGA: $przypCcUwaga." "Yellow" }
  if ($przypZHooka -and $przypCcTresc) {
    Linia "  Plik przypomnienia wziety z hooka UserPromptSubmit w settings.json (tryb globalny) - to ten, ktory naprawde leci."
  }
  Linia "  Codex (osobny rachunek - Claude Code tego nie dostaje):"
  if (-not $jestCodex) {
    $ogonCx = ""
    if ($przypZnaki -ne $null) { $ogonCx = " Gdyby byl, lecialoby ~$(Liczba (Tokeny $przypZnaki)) tokenow z $przypSkad." }
    Linia "  $($rCx.Brak) - nie ma czego liczyc.$ogonCx"
  } else {
    Wypisz-Kubelek $kubWiadomoscCx $tokWiadomoscCx "Nie znalazlem przypomnienia Codeksa - przy wiadomosci nie dokleja sie nic."
  }
  if ($jestOpenCode) {
    Linia "  OpenCode: nic - nie ma hooka wiadomosci, a wtyczka MegaRuchacza (mr-log.js) niczego do wiadomosci nie dokleja."
  }
  Linia "  Tylko to jest doklejane przy kazdym Twoim zdaniu, kazdemu narzedziu jego wlasne. Reszta wchodzi raz, na starcie sesji."

  Linia ""
  Linia "3. RAZ, przy starcie sesji - z czego sie sklada (kazde narzedzie osobno)"
  Linia "  Claude Code:"
  if (-not $w.Jest) {
    if ($w.Blad) { Linia "  $($w.Blad) - nie wiem, co stad wchodzi do rozmowy." "Yellow" }
    else         { Linia "  Nie ma pliku $plikClaude - czyli nic stad nie wchodzi do rozmowy." }
  }
  Wypisz-Kubelek $kubSesja $tokSesja `
    "Nie ma czego mierzyc - ani pamieci w CLAUDE.md, ani zasad wstrzykiwanych hookiem."
  if ($w.Jest -and (-not $w.MaSekcje)) {
    Linia "  (sekcji '## Co wiem' w tym pliku nie ma - warstwa stala i biezaca sa puste)"
  }
  # od P59a zasady pamieci to bloki nazwane lore i wiedza; stary wspolny blok to $w.Blok
  if ($w.Jest -and ($w.Blok.Znaki -eq 0) -and (@($w.Bloki | Where-Object { $_.Nazwa -in @("lore", "wiedza") }).Count -eq 0)) {
    Linia "  (blokow zasad pamieci MegaRuchacza - lore, wiedza - w tym pliku nie ma)"
  }
  foreach ($nb in @($w.BlokiBezKonca)) {
    Linia "  UWAGA: blok '$nb' w $plikClaude ma znacznik startu bez znacznika konca - nie umiem go odciac ani policzyc." "Yellow"
  }
  if ($zasadyCcPominiete) {
    Linia "  (nie doliczam $zasadyCcPominiete - w trybie globalnym zaden hook SessionStart go nie wczytuje, a zasady kierownika ida blokiem w CLAUDE.md, policzonym wyzej)"
  } elseif (-not $zasadyCcTresc -and -not $zasadyWdrozone) {
    Linia "  (zasad wstrzykiwanych hookiem nie doliczam: bez -Projekt widze tylko szablon, a szablon sam z siebie nic nie wysyla)"
  }
  # linie maszynowe - z nich czyta poprzedni pomiar nastepny przebieg, kazde
  # narzedzie swoja (Poprzedni-Pomiar)
  Linia ("  POMIAR narzedzie=claude tokenow={0} znakow={1}" -f $rCc.TokS, $rCc.ZnakiS)
  Wypisz-Porownanie $rCc
  Linia "  Codex (osobny rachunek - Claude Code tych plikow nie czyta):"
  if (-not $jestCodex) {
    Linia "  $($rCx.Brak) - nie ma czego liczyc."
  } else {
    Wypisz-Kubelek $kubSesjaCx $tokSesjaCx "Nie ma czego mierzyc."
    Linia ("  POMIAR narzedzie=codex tokenow={0} znakow={1}" -f $rCx.TokS, $rCx.ZnakiS)
    Wypisz-Porownanie $rCx
  }
  # OpenCode (od 06.10.2026) - bloki MegaRuchacza i "Co wiem" z pliku, ktory czyta (kubelki.ps1).
  if ($jestOpenCode) {
    Linia "  OpenCode (osobny rachunek - z $plikOc$(if ($ocZastepczy) { ', bo nie ma ~\.config\opencode\AGENTS.md' })):"
    Wypisz-Kubelek $kubSesjaOc $tokSesjaOc "Nie ma czego mierzyc - ani blokow zasad MegaRuchacza, ani sekcji '## Co wiem'."
    Linia ("  POMIAR narzedzie=opencode tokenow={0} znakow={1}" -f $rOc.TokS, $rOc.ZnakiS)
    Wypisz-Porownanie $rOc
  }
  Linia "  To wchodzi do kontekstu raz i siedzi w nim do konca sesji - nie jest wysylane ponownie przy kazdej wiadomosci."
  Linia "  Tokeny to SZACUNEK, nie pomiar: przyjete ~$ZnakiNaToken znaki na token dla polszczyzny."

  Linia ""
  Linia "4. RAZ NA DOBE - cykl wiedzy (jedyne prawdziwe wolanie modelu)"
  Linia "  Dwa rachunki wyzej to TEKST doklejany do rozmowy. Ten jest innego rodzaju:"
  Linia "  cykl dzienny wola model, zeby przeczytal wczorajsze rozmowy i wylowil z nich"
  Linia "  fakty. Dlatego nie dodajemy go do tamtych - to osobne pieniadze, placone raz"
  Linia "  na dobe, a zsumowane sugerowalyby, ze tyle kosztuje kazda sesja."
  if ($script:WiedzaWylaczona) {
    # P64: modul wiedza odznaczony w instalatorze - nauki nie ma z wyboru, a nie z braku przebiegu
    Linia "  Modul Wiedza nie jest zainstalowany (rejestr instalacji) - cykl wiedzy nie chodzi i nic nie kosztuje."
  } elseif (-not $cykl) {
    Linia "  Cykl jeszcze nie liczyl kosztu - nie ma pliku $plikCyklKoszt."
    Linia "  To normalny stan, nie awaria: liczba pojawi sie po pierwszym przebiegu cyklu,"
    Linia "  ktory wylowi fakty (narzedzia\cykl-dzienny.ps1)."
  } else {
    $opisDnia = $cykl.Data
    if (-not $opisDnia) { $opisDnia = "dzien nieznany" }
    $kiedyCykl = Kiedy-Cykl $cykl.Wiek
    if ($kiedyCykl) { $opisDnia = "$opisDnia ($kiedyCykl)" }
    $czymCyklOpis = $cykl.Narzedzie
    if (-not $czymCyklOpis) { $czymCyklOpis = "nie wiadomo (cykl tego nie podal)" }
    Linia ("  Dzien: {0}, narzedzie: {1}" -f $opisDnia, $czymCyklOpis)
    Linia ("  {0,-38} {1,8}        ~{2,6} tokenow" -f "CYKL WIEDZY RAZEM", "", (Lub-Nieznane $cykl.Tokeny))
    Linia ("  Wywolan modelu: {0}, wylowionych faktow: {1}" -f `
           (Lub-Nieznane $cykl.Wywolania), (Lub-Nieznane $cykl.Fakty))
    Linia ("  Wyslane: {0} znakow, odebrane: {1} znakow" -f `
           (Lub-Nieznane $cykl.ZnakiWyslane), (Lub-Nieznane $cykl.ZnakiOdebrane))
    Linia ("  {0}" -f (Opis-Zrodla $cykl.Zrodlo))
    $okresPelny = "nie zapisany (starsza wersja modulu pamieci)"
    if ($ocena.ZakresOd) { $okresPelny = "$($ocena.ZakresOd) - $($ocena.ZakresDo)" }
    Linia ("  Za jaki okres: {0} wiadomosci z {1}" -f (Lub-Nieznane $ocena.Wiadomosci), $okresPelny)
    $kolorRodzaju = $null
    if (@("nadrabianie", "mieszany", "nieznany") -contains $ocena.Rodzaj) { $kolorRodzaju = "Yellow" }
    $skadOceny = "z dziennika przebiegow"
    if ($ocena.Zrodlo -eq "plik-dnia") { $skadOceny = "z pliku dnia - dziennika przebiegow dla tego dnia nie ma" }
    Linia ("  Rodzaj: {0} (ocena {1})" -f (Opis-Rodzaju $ocena), $skadOceny) $kolorRodzaju
    Linia ("  {0}" -f (Zdanie-Typowego-Dnia $ocena))
    $poprzCykl = $cykl.Poprzedni
    if ((-not $poprzCykl) -or ($null -eq $poprzCykl.Tokeny) -or ($null -eq $cykl.Tokeny)) {
      Linia "  Poprzedniego dnia nie ma z czym porownac - cykl nie podal jego liczb."
    } else {
      $roznicaCykl = [long]$cykl.Tokeny - [long]$poprzCykl.Tokeny
      $procCykl = 0
      if ([long]$poprzCykl.Tokeny -gt 0) {
        $procCykl = [int][math]::Round(100.0 * $roznicaCykl / [double]$poprzCykl.Tokeny)
      }
      $opisRoznicy = "bez zmian"
      if ($roznicaCykl -gt 0)     { $opisRoznicy = "+$(Liczba $roznicaCykl), +$procCykl%" }
      elseif ($roznicaCykl -lt 0) { $opisRoznicy = "$(Liczba $roznicaCykl), $procCykl%" }
      $dzienPoprz = $poprzCykl.Data
      if (-not $dzienPoprz) { $dzienPoprz = "dzien nieznany" }
      Linia ("  Poprzedni dzien ({0}): {1} -> {2} tokenow ({3})" -f `
             $dzienPoprz, (Liczba $poprzCykl.Tokeny), (Liczba $cykl.Tokeny), $opisRoznicy)
    }
    if (($null -ne $cykl.Wiek) -and ($cykl.Wiek -gt $DniCyklStary)) {
      Linia ("  Ta liczba ma {0} dni - cykl od tego czasu nie liczyl kosztu, czyli najpewniej" -f $cykl.Wiek) "Yellow"
      Linia "  w ogole nie chodzi. Sprawdz: powershell -File narzedzia\cykl-dzienny.ps1 -Proba" "Yellow"
    }
    Linia "  Zapisal to sam cykl: $plikCyklKoszt"
  }

  # Historia dni: to samo, co wykres w oknie nadzorcy, tylko w liniach.
  if (@($statystyka.Dni).Count -gt 0) {
    $skadSum = "z podsumowania $plikPodsum"
    if ($statystyka.SumyZ -eq "dni") { $skadSum = "zsumowane z dni ponizej" }
    Linia ("  Historia: 7 dni ~{0}, {1} dni ~{2} tokenow ({3}); dni z nauka: {4}" -f `
           (Lub-Nieznane $statystyka.Suma7), $DniStatystyki, (Lub-Nieznane $statystyka.Suma30), $skadSum, $statystyka.SredniaDni)
    foreach ($d in @($statystyka.Dni)) {
      $podzial = @()
      if ($d.Zwykle -gt 0)      { $podzial += "zwykly dzien ~$(Liczba $d.Zwykle)" }
      if ($d.Nadrabianie -gt 0) { $podzial += "nadrabianie ~$(Liczba $d.Nadrabianie)" }
      if ($d.Nieznane -gt 0)    { $podzial += "okres nieznany ~$(Liczba $d.Nieznane)" }
      Linia ("    {0}  ~{1,9} tokenow  {2}" -f $d.Dzien.ToString('yyyy-MM-dd'), (Liczba $d.Razem), ($podzial -join ", "))
    }
    if ($statystyka.Zrodlo -eq "plik-dnia") {
      Linia "  Dziennika przebiegow ($plikHistoria) jeszcze nie ma - to jedyne znane dni, z $plikCyklKoszt. Statystyka rosnie z kazdym dniem nauki."
    }
  } else {
    $powodHist = $statystyka.Powod
    if (-not $powodHist) { $powodHist = "brak dni z nauka w ostatnich $DniStatystyki dniach" }
    Linia "  Historia: $powodHist - statystyka dopiero sie zbiera."
  }

  Linia ""
  Linia "5. Warstwa referencyjna ($katWiedzy)"
  if (-not (Test-Path -LiteralPath $katWiedzy)) {
    Linia "  Nie ma tego katalogu - warstwy referencyjnej jeszcze nie ma."
  } else {
    Linia "  Plikow: $($pliki.Count), lacznie $(Rozmiar $bajtyWiedzy)"
    Linia "  To NIE jest doklejane do rozmow. Nie kosztuje nic, dopoki agent po to nie siegnie -"
    Linia "  wiec ta warstwa moze byc duza, nie bedac droga. Tu przenosi sie to, co puchnie wyzej."
  }

  Linia ""
  Linia "6. Poczekalnia ($plikKandydat)"
  if ($bladKandydatow) {
    Linia "  $bladKandydatow - nie wiem, ile faktow czeka na decyzje." "Yellow"
  } elseif ($kandydaci -eq $null) {
    Linia "  Nie ma pliku kandydatow - nic nie czeka na decyzje. To normalne."
  } else {
    Linia "  Faktow czeka na zatwierdzenie: $kandydaci"
  }

  Linia ""
  Linia "7. Higiena warstwy biezacej (wpis wazny przez $DniWaznosci dni)"
  if ((-not $w.Jest) -or (-not $w.MaSekcje)) {
    Linia "  Brak danych - nie ma czego sprawdzac."
  } elseif ($w.Wpisy.Count -eq 0) {
    Linia "  Nie ma ani jednego wpisu w formacie - [RRRR-MM-DD] tresc."
  } else {
    Linia "  Wpisow: $($w.Wpisy.Count), w tym przeterminowanych: $($stare.Count)"
    foreach ($s in $stare) {
      Linia "    [$($s.Data)] ($($s.Wiek) dni) $(Skroc $s.Tresc 70)"
    }
  }

  Linia ""
  Linia "8. Inne sufity znalezione w kodzie (stale, wiec nie ma tu czego mierzyc)"
  $inne = @(
    @{ Plik = $plikIndeksu;  Wzor = '(?m)^MAX_TOOL_INPUT\s*=\s*([\d_]+)';     Opis = "opis wywolania narzedzia zapisywany w pamieci Lore jest przycinany do {0} znakow (lore\lore\index.py)" },
    @{ Plik = $plikIndeksu;  Wzor = '(?m)^MAX_TOOL_RESULT\s*=\s*([\d_]+)';    Opis = "wynik narzedzia zapisywany w pamieci Lore jest przycinany do {0} znakow (lore\lore\index.py)" },
    @{ Plik = $plikSzukania; Wzor = '(?m)^MAX_SNIPPET\s*=\s*([\d_]+)';        Opis = "fragment pokazywany w wynikach szukania jest przycinany do {0} znakow (lore\lore\search.py)" },
    @{ Plik = $plikKopania;  Wzor = '(?m)^MAX_SNIPPET\s*=\s*([\d_]+)';        Opis = "fragment podawany modelowi przy kopaniu w pamieci przycinany do {0} znakow (lore\lore\mining.py)" },
    @{ Plik = $plikKopania;  Wzor = '(?m)^MAX_PREVIEW_SNIPPET\s*=\s*([\d_]+)'; Opis = "zajawka w podgladzie znalezisk przycinana do {0} znakow (lore\lore\mining.py)" }
  )
  $bylo = $false
  # sufity, ktorych nie udalo sie odczytac, ida osobna linia - pominiete po cichu
  # wygladalyby tak, jakby ich w kodzie w ogole nie bylo
  $nieodczytane = @()
  foreach ($i in $inne) {
    $v = Limit-Z-Pliku $i.Plik $i.Wzor
    if ($v -eq $null) {
      $powodI = "nie ma tego pliku"
      if (Test-Path -LiteralPath $i.Plik) { $powodI = "plik jest, ale nie ma w nim tej stalej" }
      $nieodczytane += (($i.Opis -f "?") + " - $powodI")
      continue
    }
    $bylo = $true
    Linia ("  - " + ($i.Opis -f (Liczba $v)))
  }
  foreach ($n in $nieodczytane) {
    Linia ("  ? nie zmierzone: " + $n)
  }
  if (-not $bylo) {
    Linia "  Nie znalazlem ani jednej liczby - albo nie ma tu katalogu lore\."
  } else {
    Linia "  Te sufity tna tresc, zanim trafi do pamieci albo do wyniku szukania. Nie dotycza"
    Linia "  tego, co dokleja sie do rozmowy, wiec nie licza sie do kosztu wyzej."
  }

  Linia ""
  Linia "9. Ostrzezenia"
  if ($ostrzezenia.Count -eq 0) {
    Linia "  Nic nie wymaga uwagi - nic nie jest ucinane, a pamiec trzyma sie w rozsadnych rozmiarach."
  } else {
    foreach ($o in $ostrzezenia) { Linia "  UWAGA  $o" "Yellow" }
  }

  # Podsumowanie: dwie liczby i nic wiecej. Zadnych mnozen - uzytkownik powiedzial
  # wprost, ze po przeliczeniu na dobe czy na sto wiadomosci i tak nic nie wie.
  Linia ""
  Linia "10. Podsumowanie"
  if ($tokWiadomosc -gt 0) {
    Linia "  Claude Code, kazda Twoja wiadomosc: +$(Liczba $tokWiadomosc) tokenow."
  } else {
    Linia "  Claude Code, kazda Twoja wiadomosc: nie umiem zmierzyc - nie znalazlem pliku z przypomnieniem."
  }
  if ($tokSesja -gt 0) {
    $procS = ""
    if ($null -ne $rCc.Calosc) { $procS = " = $(Procent-Tekst (100.0 * $tokSesja / $rCc.Calosc)) otwarcia sesji (reszta to sam Claude Code)" }
    Linia "  Claude Code, start sesji: +$(Liczba $tokSesja) tokenow, raz$procS."
  } else {
    Linia "  Claude Code, start sesji: nie umiem zmierzyc - $(Powod-Pustej-Sesji $plikClaude)."
  }
  # Codex osobno - jego liczby NIE dodaja sie do tych wyzej, placi je inne okno.
  if (-not $jestCodex) {
    Linia "  Codex: $($rCx.Brak) - nie ma czego liczyc."
  } else {
    if ($tokWiadomoscCx -gt 0) { Linia "  Codex, kazda wiadomosc: +$(Liczba $tokWiadomoscCx) tokenow." }
    else { Linia "  Codex, kazda wiadomosc: nie umiem zmierzyc - nie znalazlem przypomnienia Codeksa." }
    Linia "  Codex, start sesji: +$(Liczba $tokSesjaCx) tokenow, raz."
  }
  if ($jestOpenCode) {
    Linia "  OpenCode, kazda wiadomosc: nic (nie ma hooka wiadomosci)."
    Linia "  OpenCode, start sesji: +$(Liczba $tokSesjaOc) tokenow, raz."
  }
  # Trzecia liczba stoi osobno i celowo nie jest dodana do dwoch powyzej:
  # tamte to doklejony tekst, ta to prawdziwie wydane tokeny.
  if ($cykl -and ($null -ne $cykl.Tokeny)) {
    $ogonZrodla = ""
    if ($cykl.Zrodlo -eq "szacunek") { $ogonZrodla = " (szacunek)" }
    elseif ($cykl.Zrodlo -eq "pomiar") { $ogonZrodla = " (pomiar)" }
    $ogonRodzaju = ""
    $okres10 = Zakres-Krotko $ocena.ZakresOd $ocena.ZakresDo
    if (@("nadrabianie", "mieszany") -contains $ocena.Rodzaj) { $ogonRodzaju = ", nadrabianie zaleglosci z $okres10 (jednorazowo)" }
    elseif ($okres10) { $ogonRodzaju = ", rozmowy z $okres10" }
    Linia "  Nauka z rozmow (cykl wiedzy): ~$(Liczba $cykl.Tokeny) tokenow$ogonZrodla przy ostatnim przebiegu$ogonRodzaju - i to jedyne z tych trzech, co naprawde wola model."
  } else {
    Linia "  Cykl wiedzy: kosztu jeszcze nie policzyl - liczba pojawi sie po pierwszym przebiegu cyklu."
  }
  # $sciezkaSkryptu (komenda nizej) liczy koszt-pamieci.ps1 przed tym etapem -
  # tu $PSCommandPath wskazywalby ten modul, a nie skrypt.
  Linia ""
  Linia "Caly ten rachunek na zadanie - jedna komenda do wklejenia w terminal:"
  Linia "  powershell -ExecutionPolicy Bypass -File $sciezkaSkryptu"
  Linia ""

  # Kolory ida przez Write-Host, a tego nie lapie ani przekierowanie, ani potok -
  # wiec przy zapisie do pliku (-Zwykly albo wykryte przekierowanie) wypisujemy
  # wszystko zwyklym wyjsciem, zeby zaden wiersz nie zginal po drodze.
  $kolorowac = (-not $Zwykly)
  if ($kolorowac) {
    try { if ([Console]::IsOutputRedirected) { $kolorowac = $false } } catch { $kolorowac = $false }
  }
  foreach ($l in $script:Raport) {
    if ($kolorowac -and $l.Kolor) { Write-Host $l.Tekst -ForegroundColor $l.Kolor }
    else { Write-Output $l.Tekst }
  }
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["raport-pelny"] = $true
