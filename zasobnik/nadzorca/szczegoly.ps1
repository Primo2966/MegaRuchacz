# zasobnik\nadzorca\szczegoly.ps1 - czesc zasobnik\nadzorca.ps1 (patrz BUDOWA
# w jego naglowku). Zakladka Szczegoly: lista sekcji (Sekcje-Szczegolow,
# Sekcja-Kosztu, Dodaj-Rozbicie i klocki Nowa-Sekcja / Dodaj-*, od P35 takze
# wykres kosztu nauki z 30 dni - Dodaj-Wykres), ta sama tresc
# jako tekst dla wydruku -Raport (Zbuduj-Szczegoly, Tabela-Na-Tekst), ogonki
# w tekstach z koszt-pamieci.ps1 (Po-Polsku, $SLOWA_Z_OGONKAMI) i wstawienie kart
# do zakladki (Napelnij-Szczegoly, Pokaz-Karty-Szczegolow). Same karty rysuje
# Karta-Sekcji w karty.ps1.
# Skad wolane: tryb -Raport w nadzorca.ps1 (Zbuduj-Szczegoly), w-tle.ps1
# (Napelnij-Szczegoly po kroku), okno.ps1, warstwy.ps1 (Po-Polsku). Wczytuje go
# nadzorca.ps1 kropka PRZED trybami bez GUI - poza stala $SLOWA_Z_OGONKAMI same
# definicje.

# SZCZEGOLY JAKO SEKCJE, NIE SCIANA TEKSTU (przebudowane 25.09.2026). Uzytkownik:
# "Szczegoly brzydko wygladaja". Do tej pory byl to jeden TextBox z liniami
# "== NAGLOWEK ==" i dwukropkami. Teraz Sekcje-Szczegolow sklada LISTE SEKCJI
# (tytul, jedno zdanie "co to jest", wiersze etykieta/wartosc, tabele) - okno
# rysuje z niej karty, a wydruk -Raport ten sam tekst. Jedna struktura dla obu,
# zeby wydruk nie mowil o czyms, czego w oknie nie ma.
# Kolejnosc: najpierw to, co wymaga uwagi, potem pieniadze, potem stan, na koncu
# gdzie co lezy. Informacje sa te same co wczesniej - nic nie wypadlo, tylko
# stoja w porzadku i po ludzku.

function Nowa-Sekcja([string]$tytul, [string]$opis) {
  return [pscustomobject]@{ Tytul = $tytul; Opis = $opis; Elementy = (New-Object System.Collections.ArrayList) }
}

function Dodaj-Wiersze($s, $wiersze) {
  foreach ($w in @($wiersze)) {
    if ($w) { [void]$s.Elementy.Add([pscustomobject]@{ Rodzaj = "wiersz"; Etykieta = "$($w.Etykieta)"; Wartosc = "$($w.Wartosc)"; Waga = "$($w.Waga)" }) }
  }
}

function Dodaj-Wiersz($s, [string]$etykieta, [string]$wartosc, [string]$waga = "") {
  Dodaj-Wiersze $s @(Wiersz $etykieta $wartosc $waga)
}

function Dodaj-Tekst($s, [string]$tekst, [string]$waga = "") {
  [void]$s.Elementy.Add([pscustomobject]@{ Rodzaj = "tekst"; Tekst = $tekst; Waga = $waga })
}

function Dodaj-Podtytul($s, [string]$tekst) {
  [void]$s.Elementy.Add([pscustomobject]@{ Rodzaj = "podtytul"; Tekst = $tekst })
}

# Kolumna: @{ N = naglowek; S = szerokosc w oknie (0 = reszta); P = do prawej;
# Pasek = wartosc to procent rysowany paskiem }. Wiersze: tablice napisow.
function Dodaj-Tabele($s, $kolumny, $wiersze) {
  $w = New-Object System.Collections.ArrayList
  foreach ($r in @($wiersze)) { [void]$w.Add([string[]]@($r)) }
  [void]$s.Elementy.Add([pscustomobject]@{ Rodzaj = "tabela"; Kolumny = @($kolumny); Wiersze = $w })
}

# Wykres kosztu nauki z liczbami obok (P35) - w oknie rysuje go Karta-Sekcji
# (Panel-Wykresu w wykres.ps1), wydruk -Raport daje w tym miejscu te same dni
# paskami ze znakow (Linie-Statystyki). $st = Statystyka-Okna.
function Dodaj-Wykres($s, $st) {
  [void]$s.Elementy.Add([pscustomobject]@{ Rodzaj = "wykres"; Statystyka = $st })
}

# koszt-pamieci.ps1 pisze samym ASCII (tak musi - patrz tamten plik). Do okna
# oddajemy te same slowa z ogonkami, zeby "wiadomosci" nie wygladalo na usterke.
# Tylko pelne slowa ze znanej listy - nieznane zostaja, jak byly.
# Pary, nie slownik: klucze slownika w PowerShellu nie roznia wielkosci liter,
# a "KAZDEJ" i "kazdej" to dwa rozne slowa w wydruku. Porownanie jest dokladne.
$SLOWA_Z_OGONKAMI = @(
  @("uczenie sie na wczesniejszych rozmowach", "nauka z wcześniejszych rozmów"),
  # P16: "sesja" nic uzytkownikowi nie mowi - jednostka jest otwarcie okna rozmowy.
  # Frazy przed pojedynczymi slowami; koszt-pamieci.ps1 zostaje, jak byl.
  @("przy starcie sesji", "przy otwarciu okna rozmowy"), @("na start sesji", "przy otwarciu okna rozmowy"),
  @("start sesji", "otwarcie okna rozmowy"), @("otwarcia sesji", "otwarcia okna rozmowy"),
  @("otwarciu sesji", "otwarciu okna rozmowy"), @("ostatnich sesji", "ostatnich rozmów"),
  @("KAZDEJ", "każdej"), @("kazdej", "każdej"), @("wiadomosci", "wiadomości"), @("wiadomosc", "wiadomość"),
  @("tokenow", "tokenów"), @("RAZ NA DOBE", "raz na dobę"), @("RAZ", "raz"), @("uczenie sie", "nauka"),
  @("wczesniejszych", "wcześniejszych"), @("stala", "stała"), @("biezaca", "bieżąca"), @("dzis", "dziś"),
  @("wywolan", "wywołań"), @("faktow", "faktów"), @("zwykly", "zwykły"), @("dzien", "dzień"),
  @("placona", "płacona"), @("wolaniem", "wołaniem"), @("wygasaja", "wygasają"), @("kosztuja", "kosztują"),
  @("dopoki", "dopóki"), @("wpisow", "wpisów"), @("pamiec", "pamięć"), @("sciezka", "ścieżka"),
  @("caly", "cały"), @("czesc", "część"), @("Biezace", "Bieżące"), @("rozmow", "rozmów"), @("zadan", "zadań"),
  @("czlowiek", "człowiek"), @("recznie", "ręcznie"), @("sie", "się"), @("kazdej", "każdej"),
  @("zaden", "żaden"), @("siega", "sięga"), @("narzedziami", "narzędziami"),
  @("niz", "niż"), @("prog", "próg"), @("calosc", "całość"), @("porownuje", "porównuje"), @("mierze", "mierzę"),
  @("Udzialu", "Udziału"), @("calym", "całym"), @("calosci", "całości"), @("transkryptow", "transkryptów"),
  @("zaleglosci", "zaległości")
)
function Po-Polsku([string]$t) {
  if (-not $t) { return "" }
  foreach ($p in $SLOWA_Z_OGONKAMI) {
    $t = [regex]::Replace($t, "(?<![\p{L}])" + [regex]::Escape($p[0]) + "(?![\p{L}])", $p[1])
  }
  return $t
}

# Rozbicie z koszt-pamieci.ps1 -Rozbicie jako tabele: wiersz pozycji ma postac
# "  nazwa  ####  1 234  54%  uwaga". Linia, ktora nie pasuje do wzorca, NIE
# ginie - idzie jako zwykly tekst pod tabela, w tej samej kolejnosci.
#
# P15: kolumna "% otwarcia sesji" - kazda liczba tokenow MegaRuchacza takze
# w mierze Przegladu ($o = Opis-Startu). Pozycje Codeksa jej nie dostaja: jego
# otwarcia sesji nikt nie mierzy, a procent od sesji Claude Code bylby falszywy.
function Dodaj-Rozbicie($s, $rozbicie, $o = $null) {
  $kol = @(@{ N = "Pozycja"; S = 250 }, @{ N = "Udział"; S = 170; Pasek = $true }, @{ N = "Tokeny"; S = 100; P = $true },
           @{ N = ""; S = 60; P = $true }, @{ N = "% otwarcia okna rozmowy"; S = 180; P = $true }, @{ N = "Uwaga"; S = 0 })
  $wiersze = @()
  $zrzuc = {
    if ($wiersze.Count -gt 0) { Dodaj-Tabele $s $kol $wiersze; Set-Variable -Name wiersze -Value @() -Scope 1 }
  }
  $pierwsza = $true
  $codex = $false
  foreach ($linia in @($rozbicie)) {
    $l = "$linia"
    if (-not $l.Trim()) { continue }
    if ($pierwsza -and ($l -match '^MegaRuchacz - ')) { $pierwsza = $false; continue }
    $pierwsza = $false
    $m = [regex]::Match($l, '^\s{2}(\S.*?)\s+([#|]+)\s+(\d[\d ]*\d|\d)(?:\s+(\d+)%)?(?:\s+(.*?))?\s*$')
    if ($m.Success) {
      $proc = ""
      if ($m.Groups[4].Success) { $proc = $m.Groups[4].Value }
      $pasek = $proc
      if (-not $pasek) { $pasek = "100"; if ($m.Groups[2].Value -eq "|") { $pasek = "0" } }
      $procTxt = ""
      if ($proc) { $procTxt = "$proc%" }
      $sesja = ""
      $tok = [long]($m.Groups[3].Value -replace ' ', '')
      if ((-not $codex) -and ($tok -gt 0)) { $sesja = Proc-Sesji $tok $o }
      elseif ($codex) { $sesja = "nie mierzę" }
      $wiersze += ,@((Po-Polsku $m.Groups[1].Value.Trim()), $pasek, $m.Groups[3].Value, $procTxt, $sesja, (Po-Polsku $m.Groups[5].Value.Trim()))
      continue
    }
    & $zrzuc
    if ($l -match '^\S') { $codex = ($l -match '^Codex') }
    if ($l -match '^\S') {
      Dodaj-Podtytul $s (Z-Wielkiej (Po-Polsku $l.Trim()))
    } else {
      Dodaj-Tekst $s (Po-Polsku $l.Trim()) "szary"
    }
  }
  & $zrzuc
}

# P26: prawdziwy koszt w calosci - to samo, co karta na Przegladzie, plus liczby
# odpowiedzi, pelne opisy, projekty i to, jak to policzone.
function Sekcja-Kosztu($koszt, $zuzycie) {
  $s = Nowa-Sekcja "Ile tokenów naprawdę zużywasz - Twoje rozmowy i workerzy" "Wszystkie tokeny z transkryptów Claude Code na tym komputerze, osobno Twoje rozmowy (okna) i workerzy."
  if (-not $koszt) { Dodaj-Tekst $s "Jeszcze nie policzone - liczy się w tle przy otwarciu okna." "szary"; return $s }
  if ($koszt.Powod) { Dodaj-Wiersz $s "Dziś" "nie wiem, bo $($koszt.Powod)" "uwaga" }
  else {
    $razem = [double]$koszt.Rozmowy + [double]$koszt.Workerzy
    $dz = "Twoje rozmowy $(Tokeny-Okolo $koszt.Rozmowy) ($(Liczba-Ludzka $koszt.OdpowiedziRozmow) odpowiedzi modelu), " +
          "workerzy $(Tokeny-Okolo $koszt.Workerzy) ($(Liczba-Ludzka $koszt.OdpowiedziWorkerow)), razem $(Tokeny-Okolo $razem)"
    if ($razem -gt 0) { $dz += " - workerzy to $(Procent-Udzialu ([double]$koszt.Workerzy) $razem)" }
    else { $dz = "jeszcze nie było rozmów z Claude" }
    Dodaj-Wiersz $s "Dziś do $($koszt.Wyliczono.ToString('HH:mm'))" $dz
  }
  if ($zuzycie -and ($zuzycie.Stan -eq "jest") -and ($null -ne $zuzycie.SredniaRozmowy)) {
    $okres = ""
    if ($zuzycie.Od -and $zuzycie.Do) { $okres = " ($($zuzycie.Od.ToString('dd'))–$($zuzycie.Do.ToString('dd.MM')), rozmowy w $($zuzycie.DniZRozmowami) z $($zuzycie.Dni) dni)" }
    $sr = [double]$zuzycie.SredniaRozmowy + [double]$zuzycie.SredniaWorkerow
    Dodaj-Wiersz $s "Średnio dziennie" ("Twoje rozmowy $(Tokeny-Okolo $zuzycie.SredniaRozmowy), workerzy $(Tokeny-Okolo $zuzycie.SredniaWorkerow), " +
      "razem $(Tokeny-Okolo $sr)$okres - workerzy to $(Procent-Udzialu ([double]$zuzycie.SredniaWorkerow) $sr)")
    if ($null -ne $zuzycie.Wyjscie) {
      Dodaj-Wiersz $s "Tekst pisany przez Claude'a" ("$(Tokeny-Okolo ([double]$zuzycie.Wyjscie / [double]$zuzycie.Dni)) tokenów dziennie ($(Liczba-Ludzka $zuzycie.Wyjscie) w $($zuzycie.Dni) dni) - " +
        "reszta to czytanie rozmowy (w tym z pamięci podręcznej).") "szary"
    }
  } elseif ($zuzycie -and ($zuzycie.Stan -eq "licze")) {
    Dodaj-Wiersz $s "Średnio dziennie" "jeszcze się liczy - za kilka sekund będzie" "szary"
  } else {
    $pw = "nie wiem dlaczego"
    if ($zuzycie -and $zuzycie.Powod) { $pw = $zuzycie.Powod }
    Dodaj-Wiersz $s "Średnio dziennie" "nie wiem, bo $pw" "uwaga"
  }
  if ((-not $koszt.Powod) -and (@($koszt.Najdrozsi).Count -gt 0)) {
    $ile = ""
    if ($koszt.WorkerowDzis -gt @($koszt.Najdrozsi).Count) { $ile = " (z $($koszt.WorkerowDzis) dzisiejszych)" }
    Dodaj-Podtytul $s "Najdroższe zadania workerów dziś$ile"
    $ws = @()
    foreach ($w in @($koszt.Najdrozsi)) {
      $opis = $w.Opis
      if (-not $opis) { $opis = "bez opisu zadania" }
      $ws += ,@($opis, "$($w.Rola)", "$($w.Projekt)", (Liczba-Ludzka $w.Wywolania), (Liczba-Ludzka $w.Tokeny))
    }
    Dodaj-Tabele $s @(@{ N = "Zadanie"; S = 0 }, @{ N = "Rola"; S = 130 }, @{ N = "Projekt"; S = 190 }, @{ N = "Wywołania"; S = 100; P = $true }, @{ N = "Tokeny"; S = 120; P = $true }) $ws
    foreach ($w in @($koszt.Najdrozsi)) { if ($w.Uwaga) { Dodaj-Tekst $s "$($w.Opis): $($w.Uwaga)" "uwaga" } }
  } elseif (-not $koszt.Powod) {
    Dodaj-Wiersz $s "Workerzy dziś" "żaden jeszcze nie pracował"
  }
  Dodaj-Wiersz $s "Jak to policzone" ("W każdej odpowiedzi modelu suma input_tokens, cache_creation_input_tokens, cache_read_input_tokens i output_tokens; " +
    "każda odpowiedź raz (message.id), z jej linii największe wartości. Worker = plik w katalogu subagents, opis zadania z pliku .meta.json obok.") "szary"
  if (-not $koszt.Powod) {
    $bl = ""
    if ($koszt.Bledy -gt 0) { $bl = "; nie dało się otworzyć $($koszt.Bledy), np. $($koszt.Blad)" }
    Dodaj-Wiersz $s "" "Pliki z ostatnich $($koszt.Godzin) h: $($koszt.Pliki), $($koszt.Mb) MB, liczone $("$($koszt.Sekundy)".Replace('.', ',')) s$bl." $(if ($koszt.Bledy -gt 0) { "uwaga" } else { "szary" })
  }
  return $s
}

function Sekcje-Szczegolow($d, $wywrotkiNadzorcy, $rozbicie, $start, $koszt = $null, $zuzycie = $null) {
  $lista = @()

  # 1. Co wymaga uwagi - pelna tresc, razem z komendami, ktorych nie ma na wierzchu.
  $s = Nowa-Sekcja "Co wymaga uwagi - pełna treść" "To samo, co karty na górze Przeglądu, ale w całości: z nazwami plików i komendami."
  $alarmy = @()
  if ($d) { $alarmy = @($d.Alarmy) + @($d.Informacje) }
  if ($alarmy.Count -eq 0) {
    if ($d -and $d.Cykl -and $d.Rachunek) { Dodaj-Tekst $s "Nic nie wymaga uwagi." "dobrze" }
    else { Dodaj-Tekst $s "Nie wiadomo - brakuje danych, więc alarmów nie policzyłem." "uwaga" }
  } else {
    foreach ($a in $alarmy) {
      $waga = Waga-Z-Alarmu $a
      $etyk = "Do sprawdzenia"; $kol = "uwaga"
      if ($waga -eq "pilne") { $etyk = "Wymaga działania"; $kol = "pilne" }
      elseif ($waga -eq "info") { $etyk = "Dla informacji"; $kol = "uwaga" }
      Dodaj-Wiersz $s $etyk (Bez-Przedrostka $a.Tytul) $kol
      Dodaj-Wiersz $s "" (Po-Polsku "$($a.Tresc)") "szary"
    }
  }
  if ($d -and $d.Rachunek -and $d.Rachunek.Linia) {
    Dodaj-Wiersz $s "Linia rachunku" (Po-Polsku "$($d.Rachunek.Linia)") "szary"
    Dodaj-Wiersz $s "" "te same liczby, które strażnik pokazuje przy otwarciu okna rozmowy" "szary"
  }
  $lista += $s

  # 1a. Prawdziwy koszt (P26) - najwieksze pieniadze, wiec zaraz po tym, co wymaga uwagi.
  try { $lista += (Sekcja-Kosztu $koszt $zuzycie) }
  catch {
    Zanotuj-Wywrotke "prawdziwy koszt do szczegolow" $_
    $s = Nowa-Sekcja "Ile tokenów naprawdę zużywasz - Twoje rozmowy i workerzy" ""
    Dodaj-Tekst $s "Nie udało się złożyć - powód jest w dzienniku nadzorcy." "uwaga"
    $lista += $s
  }

  # 2. Otwarcie okna rozmowy - skad liczby z karty na Przegladzie.
  $s = Nowa-Sekcja "Otwarcie okna rozmowy - skąd ta liczba" "Ile tokenów Claude wczytuje, gdy otwierasz nowe okno rozmowy (liczone przy pierwszej wiadomości), i jaka część z tego to MegaRuchacz."
  $o = $null
  try { $o = Opis-Startu $start } catch { Zanotuj-Wywrotke "opis otwarcia okna rozmowy do szczegolow" $_ }
  if (-not $start) {
    Dodaj-Tekst $s "Jeszcze nie zmierzone - pomiar rusza przy otwarciu okna." "szary"
  } elseif (-not $o -or -not $o.Zmierzone) {
    $pw = "nie wiadomo dlaczego"
    if ($o -and $o.Powod) { $pw = $o.Powod }
    Dodaj-Wiersz $s "Całość" "nie zmierzono, bo $pw" "uwaga"
    if ($o -and ($null -ne $o.Mr)) { Dodaj-Wiersz $s "MegaRuchacz (rachunek)" "~$(Liczba-Ludzka $o.Mr) tokenów - bez całości nie ma z czego policzyć procentu" }
  } else {
    Dodaj-Wiersz $s "Razem na otwarcie" "~$(Liczba-Ludzka $o.Razem) tokenów (mediana z $($o.Sesji) $(Odmiana $o.Sesji 'rozmowy' 'rozmów' 'rozmów'))"
    # Bez rozbicia na start + przypomnienie (P14): te dwie liczby stoja jako
    # naglowki w sekcji "Rachunek za pamiec" tuz nizej - drugi raz tu tylko mylil.
    Dodaj-Wiersz $s "MegaRuchacz" "~$(Liczba-Ludzka $o.Mr) tokenów ($($o.MrProc)) - to, co dokłada przy otwarciu okna rozmowy, i przypomnienie doklejone do pierwszej wiadomości; każdą pozycję pokazuje sekcja niżej"
    Dodaj-Wiersz $s "Claude Code sam" "~$(Liczba-Ludzka $o.Cc) tokenów ($($o.CcProc)) - jego instrukcje, opisy narzędzi (także z serwerów MCP), lista skilli"
    # "(22%)" to udzial w starcie WORKERA, nie w otwarciu sesji - dopisujemy to wprost (P15)
    if ($o.Worker) { Dodaj-Wiersz $s "Start workera" (($o.WorkerZdanie -replace '^Start jednego workera: ', '') -replace '\((\d+%)\)', '($1 startu workera)') }
    else { Dodaj-Wiersz $s "Start workera" ($o.WorkerZdanie -replace '^Start jednego workera: ', '') "uwaga" }
    Dodaj-Wiersz $s "Jak to zmierzone" ("W każdym transkrypcie Claude Code pierwsza odpowiedź modelu ma pole usage: suma input_tokens, " +
      "cache_creation_input_tokens i cache_read_input_tokens to cały kontekst w tej chwili. Od tego odejmuję Twoją pierwszą wiadomość " +
      "(jej znaki / 3) i biorę medianę z ostatnich rozmów.") "szary"
    Dodaj-Wiersz $s "" "Część MegaRuchacza to rachunek narzędzia (znaki / 3 - szacunek), całość to prawdziwe liczby z transkryptów." "szary"
    Dodaj-Wiersz $s "Transkrypty" "$($start.Katalog)" "szary"
    $ws = @()
    foreach ($x in @(@($start.Sesje.Lista) | Sort-Object { "$($_.Kiedy)" } -Descending)) {
      $kiedy = "$($x.Kiedy)"
      $dt = Data-Lub-Nic $kiedy
      if ($dt) { $kiedy = $dt.ToLocalTime().ToString('dd.MM HH:mm') }
      $proj = ("$($x.Plik)" -split '\\')[0]
      # katalog projektu w transkryptach to sciezka z myslnikami - bez litery dysku czyta sie lepiej
      $proj = $proj -replace '^[A-Za-z]--', ''
      $ws += ,@($kiedy, $proj, (Liczba-Ludzka $x.Kontekst), (Liczba-Ludzka $x.BezWiadomosci))
    }
    if ($ws.Count -gt 0) {
      Dodaj-Podtytul $s "Rozmowy, z których jest mediana"
      Dodaj-Tabele $s @(@{ N = "Kiedy"; S = 110 }, @{ N = "Projekt"; S = 0 }, @{ N = "Kontekst"; S = 110; P = $true }, @{ N = "Bez Twojej wiadomości"; S = 170; P = $true }) $ws
    }
    $ww = @()
    foreach ($x in @(@($start.Workerzy.Lista) | Sort-Object { "$($_.Kiedy)" } -Descending)) {
      $kiedy = "$($x.Kiedy)"
      $dt = Data-Lub-Nic $kiedy
      if ($dt) { $kiedy = $dt.ToLocalTime().ToString('dd.MM HH:mm') }
      $ww += ,@($kiedy, "$($x.Rola)", (Liczba-Ludzka $x.BezWiadomosci))
    }
    if ($ww.Count -gt 0) {
      Dodaj-Podtytul $s "Workerzy, z których jest mediana (bez treści zlecenia)"
      Dodaj-Tabele $s @(@{ N = "Kiedy"; S = 110 }, @{ N = "Rola"; S = 140 }, @{ N = "Start"; S = 110; P = $true }) $ww
    }
  }
  $lista += $s

  # 3. Rachunek pozycja po pozycji.
  $s = Nowa-Sekcja "Rachunek za pamięć, pozycja po pozycji" "Co MegaRuchacz dokleja do rozmowy i ile to waży. Liczy narzędzie koszt-pamieci (znaki podzielone przez 3 - szacunek)."
  if ($null -ne $rozbicie) { Dodaj-Rozbicie $s $rozbicie $o }
  else { Dodaj-Tekst $s "Jeszcze nie policzone." "szary" }
  $lista += $s

  # 4. Nauka z rozmow.
  $s = Nowa-Sekcja "Nauka z rozmów" "Raz dziennie MegaRuchacz czyta Twoje rozmowy i wyciąga z nich fakty do pamięci. To jedyne miejsce, gdzie naprawdę woła model."
  if ($d -and $d.Cykl) { Dodaj-Wiersze $s (Opis-Cyklu $d.Cykl $o) }
  else { Dodaj-Tekst $s "Nie udało się odczytać - szczegóły w dzienniku nadzorcy." "uwaga" }
  $lista += $s

  # 5. Wykres kosztu nauki z 30 dni z liczbami obok (P35, 30.09.2026: do tego dnia
  # stal na Przegladzie - ten przestal sie miescic bez przewijania). Karta nizej
  # ma te same dni w liczbach i to, skad sa.
  $rach = $null
  if ($d) { $rach = $d.Rachunek }
  $st = $null
  try { $st = Statystyka-Okna $rach }
  catch { Zanotuj-Wywrotke "statystyka nauki do szczegolow" $_ }
  $s = Nowa-Sekcja "Koszt czytania rozmów - ostatnie 30 dni" "Ile tokenów kosztowała nauka z Twoich rozmów każdego dnia. Te same dni w liczbach i to, skąd są - w karcie niżej."
  if ($st) { Dodaj-Wykres $s $st }
  else { Dodaj-Tekst $s "Nie udało się złożyć - szczegóły w dzienniku nadzorcy." "uwaga" }
  $lista += $s

  # 5a. Historia kosztu nauki - te same dni i sumy, co na wykresie, plus zrodlo.
  $s = Nowa-Sekcja "Koszt nauki dzień po dniu" "Liczby, z których rysuje się wykres wyżej."
  if ($st) {
    $skad = "nie wiadomo"; $wagaSkad = "uwaga"
    switch ($st.Zrodlo) {
      "historia"  { $skad = "dziennik przebiegów nauki (.koszt-historia.tsv)"; $wagaSkad = "" }
      "plik-dnia" { $skad = "tylko ostatni pomiar (.koszt-cyklu.txt) - dziennika przebiegów jeszcze nie ma"; $wagaSkad = "uwaga" }
      "brak"      { $skad = "nic - $($st.Powod)"; $wagaSkad = "uwaga" }
    }
    Dodaj-Wiersz $s "Dni wzięte z" $skad $wagaSkad
    $sumy = "nie ma czego sumować"
    if ($st.SumyZ -eq "podsumowanie") { $sumy = "podsumowanie liczone przez samą naukę (.koszt-podsumowanie.txt)" }
    elseif ($st.SumyZ -eq "dni") { $sumy = "zsumowane z dni poniżej (podsumowania nie ma)" }
    Dodaj-Wiersz $s "Sumy 7 i 30 dni" $sumy
    Dodaj-Wiersz $s "Wykres" (Opis-Rysownika)
    $pj = Jak-Sesji $st.Prog $o
    if ($pj) { $pj = " ($pj)" }
    Dodaj-Wiersz $s "Próg zwykłego dnia" "$(Tokeny-Albo-Brak $st.Prog)$pj - uzasadnienie na górze narzedzia\koszt-pamieci.ps1"
    $dni = @()
    foreach ($x in @(@($st.Dni) | Where-Object { $_.Jest })) {
      $dni += ,@($x.Dzien.ToString('yyyy-MM-dd'), (Liczba-Ludzka $x.Razem), (Proc-Sesji $x.Razem $o), (Liczba-Ludzka $x.Zwykle), (Liczba-Ludzka $x.Nadrabianie), (Liczba-Ludzka $x.Nieznane))
    }
    if ($dni.Count -gt 0) {
      Dodaj-Tabele $s @(@{ N = "Dzień"; S = 120 }, @{ N = "Razem"; S = 110; P = $true }, @{ N = "% otwarcia okna rozmowy"; S = 190; P = $true }, @{ N = "Zwykły dzień"; S = 120; P = $true },
                        @{ N = "Nadrabianie"; S = 120; P = $true }, @{ N = "Okres nieznany"; S = 130; P = $true }) $dni
    } else {
      Dodaj-Tekst $s "Jeszcze nie ma ani jednego dnia z kosztem." "szary"
    }
    if ($st.Uwaga) { Dodaj-Tekst $s "$($st.Uwaga)" "szary" }
  } else {
    Dodaj-Tekst $s "Nie udało się złożyć - szczegóły w dzienniku nadzorcy." "uwaga"
  }
  $lista += $s

  # 6. Zmiany w pamieci - razem z komenda cofania, ktora na wierzchu jest zdaniem.
  $s = Nowa-Sekcja "Zmiany w pamięci" "Co ostatnia nauka dopisała albo zmieniła w wiedzy o Tobie i o firmie."
  if ($d -and $d.Pamiec) {
    $pz = $d.Pamiec
    if ($pz.Dzien) { Dodaj-Wiersz $s "Dzień nauki" "$($pz.Dzien.ToString('yyyy-MM-dd'))" }
    if (-not $pz.Wiadomo) { Dodaj-Wiersz $s "Nie wiadomo" "$($pz.Powod)" "uwaga" }
    if ($pz.Naglowek) { Dodaj-Wiersz $s "Meldunek" "$($pz.Naglowek)" }
    foreach ($x in $pz.Zmiany) { Dodaj-Wiersz $s "" "$($x.Tresc)" }
    Dodaj-Wiersz $s "Jak cofnąć" "powiedz Claude'owi: cofnij zmianę <id> - albo ręcznie:" "szary"
    Dodaj-Wiersz $s "" "uv --directory $Zrodlo\lore run python -m lore.verify --cofnij <id>" "szary"
    Dodaj-Wiersz $s "Plik" "$($pz.Plik)" "szary"
  } else {
    Dodaj-Tekst $s "Nie udało się odczytać - szczegóły w dzienniku nadzorcy." "uwaga"
  }
  if ($d -and $d.Przeliczanie -and $d.Przeliczanie.Plik) {
    Dodaj-Wiersz $s "Przeliczanie archiwum" "jest plik $($d.Przeliczanie.Plik)"
    if ($d.Przeliczanie.Powod) { Dodaj-Wiersz $s "" "$($d.Przeliczanie.Powod)" "szary" }
  }
  $lista += $s

  # 6a. Kopia zapasowa na Dysk Google (P62) - na Przegladzie jedna linia, tu reszta.
  $s = Nowa-Sekcja "Kopia zapasowa na Dysk Google" "Codzienna kopia C:\dev i plików Claude'a (narzedzia\kopia-zapasowa.ps1, zadanie Harmonogramu MegaRuchaczKopia). Pliki z samymi zerami nie trafiają do kopii - ich zdrowe wersje zostają w starszej."
  try { Dodaj-Wiersze $s (Opis-Kopii $(if ($d) { $d.Kopia } else { $null })) }
  catch { Zanotuj-Wywrotke "kopia zapasowa do szczegolow" $_; Dodaj-Tekst $s "Nie udało się złożyć - szczegóły w dzienniku nadzorcy." "uwaga" }
  $lista += $s

  # 7. Wersja.
  $s = Nowa-Sekcja "Wersja MegaRuchacza" "Czy na serwerze czeka coś nowszego. Pobiera to przycisk na dole okna - za darmo."
  if ($d -and $d.Wersja) { Dodaj-Wiersze $s (Opis-Wersji $d.Wersja) }
  else { Dodaj-Tekst $s "Nie udało się ustalić - szczegóły w dzienniku nadzorcy." "uwaga" }
  $lista += $s

  # 8. Nadzorca i pliki.
  $s = Nowa-Sekcja "Nadzorca i gdzie co leży" "Ślad samego nadzorcy (tej ikony w zasobniku) i ścieżki, gdyby trzeba było zajrzeć ręcznie."
  $stan = Czytaj-Klucze (Join-Path $KatalogDomowy ".claude\.megaruchacz-zasobnik.txt")
  if ($stan["byl"]) { Dodaj-Wiersz $s "Ostatni dozór" "$($stan['byl']) (tryb $($stan['byl.tryb']))" }
  else { Dodaj-Wiersz $s "Ostatni dozór" "brak zapisu - to pierwszy przebieg albo nie mogę pisać do pliku stanu" "uwaga" }
  if ($stan["cykl.ruszony"]) { Dodaj-Wiersz $s "Naukę ruszył" "$($stan['cykl.ruszony'])" }
  if (@($wywrotkiNadzorcy).Count -gt 0) {
    foreach ($w in @($wywrotkiNadzorcy)) { Dodaj-Wiersz $s "Wywrotka" "$w" "pilne" }
  } else {
    Dodaj-Wiersz $s "Wywrotki" "żadnych od ostatniego startu"
  }
  Dodaj-Wiersz $s "Dziennik nadzorcy" "$(Join-Path $KatalogDomowy '.claude\.megaruchacz-zasobnik.log')" "szary"
  Dodaj-Wiersz $s "Narzędzie" "$Zrodlo" "szary"
  Dodaj-Wiersz $s "Katalog domowy" "$KatalogDomowy" "szary"
  Dodaj-Wiersz $s "Zebrane" "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "szary"
  $lista += $s

  return ,$lista
}

# Te same sekcje jako tekst - dla wydruku -Raport, jedynego sprawdzenia bez pulpitu.
function Tabela-Na-Tekst($el) {
  $l = @()
  $n = @($el.Kolumny).Count
  $szer = @()
  for ($i = 0; $i -lt $n; $i++) {
    $k = $el.Kolumny[$i]
    $m = "$($k.N)".Length
    foreach ($r in $el.Wiersze) {
      $v = "$($r[$i])"
      if ($k.Pasek) { $v = "#" * [int][math]::Round([double]("0" + $v) / 5) }
      if ($v.Length -gt $m) { $m = $v.Length }
    }
    $szer += [math]::Min($m, 60)
  }
  $fmt = {
    param($wartosci)
    $cz = @()
    for ($i = 0; $i -lt $n; $i++) {
      $v = "$($wartosci[$i])"
      if ($i -eq $n - 1) { $cz += $v; continue }
      if ($el.Kolumny[$i].P) { $cz += $v.PadLeft($szer[$i]) } else { $cz += $v.PadRight($szer[$i]) }
    }
    return ("    " + ($cz -join "  ")).TrimEnd()
  }
  $l += & $fmt @($el.Kolumny | ForEach-Object { "$($_.N)" })
  foreach ($r in $el.Wiersze) {
    $w = @()
    for ($i = 0; $i -lt $n; $i++) {
      $v = "$($r[$i])"
      if ($el.Kolumny[$i].Pasek) { $v = "#" * [int][math]::Round([double]("0" + $v) / 5) }
      $w += $v
    }
    $l += & $fmt $w
  }
  return ,$l
}

function Zbuduj-Szczegoly($d, $wywrotkiNadzorcy, $rozbicie, $start, $koszt = $null, $zuzycie = $null) {
  $l = @()
  $l += "SZCZEGÓŁY   (w oknie: zakładka Szczegóły - każda sekcja to osobna biała karta, najważniejsze na górze)"
  $l += ""
  foreach ($s in (Sekcje-Szczegolow $d $wywrotkiNadzorcy $rozbicie $start $koszt $zuzycie)) {
    $l += "== $($s.Tytul.ToUpper()) =="
    if ($s.Opis) { $l += "   $($s.Opis)" }
    foreach ($e in $s.Elementy) {
      switch ($e.Rodzaj) {
        "wiersz" {
          $zn = ""
          if ($e.Waga -eq "pilne") { $zn = "[!] " } elseif ($e.Waga -eq "uwaga") { $zn = "[?] " }
          if ($e.Etykieta) { $l += ("  {0,-24}: {1}{2}" -f $e.Etykieta, $zn, $e.Wartosc) }
          else { $l += ("  {0,-24}  {1}{2}" -f "", $zn, $e.Wartosc) }
        }
        "tekst"    { $l += "  $($e.Tekst)" }
        "podtytul" { $l += "  -- $($e.Tekst)" }
        "tabela"   { $l += Tabela-Na-Tekst $e }
        "wykres"   {
          $l += "  (w oknie: wykres słupkowy w tysiącach tokenów, obok trzy liczby - $(Opis-Rysownika); tutaj te same dni paskami)"
          $l += Linie-Statystyki $e.Statystyka $null $zuzycie
        }
      }
    }
    $l += ""
  }
  return ,$l
}

# --- dane dla okna -----------------------------------------------------------

function Pokaz-Karty-Szczegolow($karty) {
  $p = $script:ListaSzczegolow
  if (-not $p -or $p.IsDisposed) { return }
  $p.SuspendLayout()
  try {
    Wyczysc-Panel $p
    foreach ($k in @($karty)) { $p.Controls.Add($k) }
  } finally { $p.ResumeLayout($true) }
  try { $script:WidokSzczegoly.AutoScrollPosition = New-Object System.Drawing.Point(0, 0) }
  catch { Zanotuj-Wywrotke "przewiniecie szczegolow na gore" $_ }
}

# Samo rysowanie - rozbicie liczy krok w tle "rozbicie" (P21), a do czasu, az
# bedzie, nad zakladka stoi ekran ladowania.
function Napelnij-Szczegoly {
  if (-not $script:ListaSzczegolow -or $script:ListaSzczegolow.IsDisposed) { return }
  if ($null -eq $script:Rozbicie) { return }
  $script:DoOdmalowania["szczegoly"] = $false
  try {
    $karty = @()
    foreach ($s in (Sekcje-Szczegolow $script:Dane $script:Wywrotki $script:Rozbicie $script:Start $script:KosztDzis $script:Zuzycie)) { $karty += (Karta-Sekcji $s) }
    Pokaz-Karty-Szczegolow $karty
  } catch {
    Zanotuj-Wywrotke "zlozenie szczegolow" $_
    Pokaz-Karty-Szczegolow @(Karta-Komunikatu "Nie udało się złożyć szczegółów" @("$($_.Exception.Message)", "Pełny ślad jest w dzienniku nadzorcy.") $script:KolPilne)
  }
}

# Znacznik dla nadzorca.ps1: ten plik wczytal sie do konca.
$script:ModulyOkna["szczegoly"] = $true
