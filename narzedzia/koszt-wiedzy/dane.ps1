# narzedzia\koszt-wiedzy\dane.ps1 - czesc narzedzia\koszt-wiedzy\koszt-wiedzy.ps1 (patrz BUDOWA
# w jego naglowku). Liczby do strony "Koszt tworzenia wiedzy z rozmow":
#   - tansza wersja: dziennik przebiegow porannej nauki (lore\lore\facts.py pisze
#     ~\.claude\wiedza\.koszt-historia.tsv, ten sam, ktory czyta narzedzia\koszt\nauka.ps1)
#     i stan ostatniego cyklu (cykl-ostatni.txt) - Czytaj-Tansza, Blad-Tanszej,
#   - pelna wersja: dziennik klienta wiedzy firmy (~\.claude\mr\wiedza-firmy\koszty.jsonl,
#     pisze go narzedzia\wiedza-firmy-klient\klient.py) plus proba z 14.10 - Czytaj-Pelna,
#     a rozbicie kazdego przebiegu na etapy z dziennikow koszt.tsv przegladu dnia - Dolacz-Etapy,
#   - cale zuzycie dnia: transkrypty Claude Code TYM SAMYM licznikiem, ktorym liczy okno
#     nadzorcy (C# z zasobnik\nadzorca\stan-zuzycie.ps1, wyjety stamtad bez uruchamiania
#     pliku), z plikiem podrecznym zakonczonych dni - Wczytaj-Licznik, Cale-Zuzycie,
#   - zlozenie w dni i sumy okresu - Zakres-Dni, Zloz-Dni, Dzien-Kart, Podsumuj-Okres.
# Same definicje; wczytuje go koszt-wiedzy.ps1 kropka (testy tez).
#
# KTORY DZIEN. Wiersz strony to DZIEN ROZMOW, ktore dana wersja przeczytala, a procent liczymy
# od calego zuzycia TEGO dnia. Poranny automat z 15.10 czyta rozmowy z 14.10, wiec jego koszt
# stoi przy 14.10 - obok tego, co tego dnia kosztowala cala praca z Claude. Tansza wersja: dzien
# z zakres_do (ostatnia przeczytana wiadomosc); przebieg bez zakresu (starsza nauka) - dzien
# przed przebiegiem. Pelna wersja: pole "dzien" z jej dziennika.

$script:Inv = [Globalization.CultureInfo]::InvariantCulture

# Kolumny dziennika przebiegow - te same co $KolumnyHistorii w narzedzia\koszt\nauka.ps1. Naglowek
# pliku ma pierwszenstwo; ta lista jest tylko dla pliku bez naglowka.
$KolumnyTanszej = @("kiedy", "narzedzie", "wywolania", "tokeny", "tokeny_zrodlo", "znaki_wyslane",
                    "znaki_odebrane", "wiadomosci", "zakres_od", "zakres_do", "fakty")

# Statusy cyklu, ktore NIE sa bledem przebiegu: przeszedl, albo przeczytal czesc i wraca po reszte
# (to ostrzega okno nadzorcy, nie ta strona). Reszta (odlozony, wyczerpane, wyzerowane, nieznany)
# znaczy, ze rozmowy z poprzedniego dnia nie zostaly przeczytane - wiersz idzie na czerwono.
$StatusyBezBledu = @("ok", "dogania", "nie nadaza")

# Proba pelnego czytania jednego dnia (14.10.2026, ta maszyna) - krokiem dziennym klienta wiedzy
# firmy PO optymalizacji wywolan (commit 060ce71), linia jego koszty.jsonl z katalogu probnego
# z 15.10.2026: 16 wywolan, wejscie 264 082, wyjscie 36 038, cache 0 = 300 120 tokenow, 63 fakty,
# 0,8886 $. Przed optymalizacja ten sam dzien (profil klient, raport proby WYNIK.md, tabela etapow):
# 22 wywolania, 650 250 tokenow, 65 faktow, 1,87 $ - stoi obok jako opis.
# Pokazywana TYLKO, gdy prawdziwy dziennik nie ma tego dnia - i zawsze z napisem "proba".
$PROBA_PELNEJ = [pscustomobject]@{
  Dzien = "2026-10-14"; Razem = [long]300120; CacheOdczyt = [long]0; Wywolan = [long]16
  Faktow = [long]63; Usd = 0.8886; Przebiegi = 1; Ok = $true; Blad = $null
  NieudaneWczesniej = 0; Proba = $true; ProbaOpis = "próba 14.10 (po optymalizacji)"; ListaPrzebiegow = @()
  ProbaPrzed = "przed optymalizacją ten sam dzień: 650 250 tokenów, 65 faktów, 22 wywołania, 1,87 $"
}

function Dzien-Z($tekst) {
  # 'RRRR-MM-DD' albo 'RRRR-MM-DD GG:MM' albo ISO -> sam dzien; $null przy braku i smieciu
  if ($null -eq $tekst) { return $null }
  $t = ("" + $tekst).Trim()
  if ($t.Length -lt 10) { return $null }
  $d = [datetime]::MinValue
  if ([datetime]::TryParseExact($t.Substring(0, 10), 'yyyy-MM-dd', $script:Inv,
      [Globalization.DateTimeStyles]::None, [ref]$d)) { return $d.Date }
  return $null
}

function Klucz-Dnia([datetime]$d) { return $d.ToString('yyyy-MM-dd', $script:Inv) }

function Liczba-Lub-Nic($v) {
  # $null zamiast zera przy braku i przy smieciu: zero znaczyloby "nic nie kosztowalo",
  # a to co innego niz "dziennik tego nie podal"
  if ($null -eq $v) { return $null }
  $t = ("" + $v).Trim()
  if ($t -notmatch '^\d+$') { return $null }
  return [long]$t
}

function Kwota-Lub-Nic($v) {
  if ($null -eq $v) { return $null }
  $d = 0.0
  if ([double]::TryParse(("" + $v).Trim(), [Globalization.NumberStyles]::Float, $script:Inv, [ref]$d)) { return $d }
  return $null
}

function Dodaj-Liczbe($stara, $nowa) {
  # suma, w ktorej "nie wiadomo" + "nie wiadomo" zostaje "nie wiadomo"
  if ($null -eq $nowa) { return $stara }
  if ($null -eq $stara) { return $nowa }
  return ($stara + $nowa)
}

function Klucze-Pliku($plik) {
  $k = @{}
  if (-not (Test-Path -LiteralPath $plik)) { return $k }
  foreach ($l in ([System.IO.File]::ReadAllText($plik) -split '\r?\n')) {
    $m = [regex]::Match($l, '^\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*:\s*(.*?)\s*$')
    if ($m.Success) { $k[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $k
}

# --- tansza wersja -------------------------------------------------------------

function Czytaj-Tansza($plik) {
  $w = [pscustomobject]@{ Plik = $plik; Jest = $false; Powod = ""; Pominiete = 0; Dni = @{} }
  if (-not (Test-Path -LiteralPath $plik)) {
    $w.Powod = "nie ma jeszcze dziennika przebiegów porannej nauki ($plik)"
    return $w
  }
  $tekst = $null
  try { $tekst = [System.IO.File]::ReadAllText($plik) }
  catch { $w.Powod = "dziennika przebiegów $plik nie da się odczytać: $($_.Exception.Message)"; return $w }
  $w.Jest = $true
  $linie = @(($tekst -split '\r?\n') | Where-Object { ("" + $_).Trim() })
  $kolumny = $KolumnyTanszej
  if (($linie.Count -gt 0) -and $linie[0].StartsWith("kiedy")) {
    $kolumny = @($linie[0] -split "`t")
    $linie = @($linie | Select-Object -Skip 1)
  }
  foreach ($l in $linie) {
    $pola = $l -split "`t"
    # Linia, ktora nie pasuje do kolumn, nie jest zgadywana - ale jest LICZONA i strona o niej mowi.
    if ($pola.Count -ne $kolumny.Count) { $w.Pominiete++; continue }
    $s = @{}
    for ($i = 0; $i -lt $pola.Count; $i++) { $s[$kolumny[$i]] = $pola[$i] }
    $kiedy = Dzien-Z $s["kiedy"]
    if ($null -eq $kiedy) { $w.Pominiete++; continue }
    $dzien = Dzien-Z $s["zakres_do"]
    if ($null -eq $dzien) { $dzien = $kiedy.AddDays(-1) }
    $k = Klucz-Dnia $dzien
    if (-not $w.Dni.ContainsKey($k)) {
      $w.Dni[$k] = [pscustomobject]@{ Dzien = $k; Tokeny = $null; Wywolania = $null; Fakty = $null
        Przebiegi = 0; ZakresOd = $null; ZakresDo = $null }
    }
    $d = $w.Dni[$k]
    $d.Tokeny    = Dodaj-Liczbe $d.Tokeny    (Liczba-Lub-Nic $s["tokeny"])
    $d.Wywolania = Dodaj-Liczbe $d.Wywolania (Liczba-Lub-Nic $s["wywolania"])
    $d.Fakty     = Dodaj-Liczbe $d.Fakty     (Liczba-Lub-Nic $s["fakty"])
    $d.Przebiegi++
    # 'RRRR-MM-DD GG:MM' porownuje sie poprawnie jako tekst
    $od = ("" + $s["zakres_od"]).Trim(); $do = ("" + $s["zakres_do"]).Trim()
    if ($od -and ((-not $d.ZakresOd) -or ($od -lt $d.ZakresOd))) { $d.ZakresOd = $od }
    if ($do -and ((-not $d.ZakresDo) -or ($do -gt $d.ZakresDo))) { $d.ZakresDo = $do }
  }
  if (($w.Dni.Count -eq 0) -and (-not $w.Powod)) { $w.Powod = "dziennik przebiegów porannej nauki jest pusty ($plik)" }
  return $w
}

function Blad-Tanszej($plik) {
  # Ostatni cykl, ktory NIE przeczytal rozmow: $null albo { Dzien (dzien rozmow, ktore mial
  # przeczytac - dzien przed przebiegiem), Opis }. Dziennik przebiegow zna tylko udane przebiegi,
  # wiec porazke widac wylacznie tutaj, i tylko ostatnia.
  $k = $null
  try { $k = Klucze-Pliku $plik } catch { return [pscustomobject]@{ Dzien = $null; Opis = "nie da się odczytać $plik ($($_.Exception.Message))" } }
  $status = ("" + $k["status"]).Trim()
  if ((-not $status) -or ($StatusyBezBledu -contains $status)) { return $null }
  $kiedy = Dzien-Z $k["data"]
  if ($null -eq $kiedy) { return $null }
  $opis = ("" + $k["opis"]).Trim()
  $powod = ("" + $k["powod"]).Trim()
  $data = ("" + $k["data"]).Trim()
  if (-not $opis) { $opis = "cykl zakończony stanem '$status' $powod".Trim() }
  return [pscustomobject]@{ Dzien = (Klucz-Dnia $kiedy.AddDays(-1)); Opis = "poranny automat $data" + ": " + $opis }
}

# --- pelna wersja --------------------------------------------------------------

function Czytaj-Pelna($plik) {
  $w = [pscustomobject]@{ Plik = $plik; Jest = $false; Powod = ""; Zle = 0; PrzykladZlej = ""; Dni = @{} }
  if (-not (Test-Path -LiteralPath $plik)) {
    $w.Powod = "dziennika pełnej wersji jeszcze nie ma ($plik)"
    return $w
  }
  $tekst = $null
  try { $tekst = [System.IO.File]::ReadAllText($plik) }
  catch { $w.Powod = "dziennika pełnej wersji $plik nie da się odczytać: $($_.Exception.Message)"; return $w }
  $w.Jest = $true
  $nr = 0
  foreach ($l in ($tekst -split '\r?\n')) {
    $nr++
    if (-not ("" + $l).Trim()) { continue }
    $o = $null
    try { $o = $l | ConvertFrom-Json -ErrorAction Stop } catch { $o = $null }
    $dzien = $null
    if ($o) { $dzien = Dzien-Z $o.dzien }
    if ($null -eq $dzien) {
      $w.Zle++
      if (-not $w.PrzykladZlej) { $w.PrzykladZlej = "linia $nr" }
      continue
    }
    $k = Klucz-Dnia $dzien
    if (-not $w.Dni.ContainsKey($k)) {
      $w.Dni[$k] = [pscustomobject]@{ Dzien = $k; Razem = $null; CacheOdczyt = $null; Wywolan = $null
        Faktow = $null; Usd = $null; Przebiegi = 0; Ok = $false; Blad = $null
        NieudaneWczesniej = 0; Proba = $false; ProbaOpis = ""; ProbaPrzed = ""; ListaPrzebiegow = @() }
    }
    $d = $w.Dni[$k]
    $razem = Liczba-Lub-Nic $o.razem
    if ($null -eq $razem) {
      foreach ($pole in @("wejscie", "cache_zapis", "cache_odczyt", "wyjscie")) { $razem = Dodaj-Liczbe $razem (Liczba-Lub-Nic $o.$pole) }
    }
    # Kazda proba osobno - do rozbicia na etapy (Dolacz-Etapy); blad bez przyczyny opisany jak nizej.
    $bladProby = $null
    if ($o.ok -ne $true) { $bladProby = ("" + $o.blad).Trim(); if (-not $bladProby) { $bladProby = "próba nieudana (dziennik nie podał przyczyny)" } }
    $d.ListaPrzebiegow += [pscustomobject]@{ Czas = ("" + $o.czas).Trim(); Ok = ($o.ok -eq $true); Blad = $bladProby
      Wywolan = (Liczba-Lub-Nic $o.wywolan); Razem = $razem; Usd = (Kwota-Lub-Nic $o.usd); Faktow = (Liczba-Lub-Nic $o.faktow)
      Etapy = $null; Paczek = $null; ZnakiCzytania = $null; EtapyBrak = ""; EtapyUwaga = "" }
    $d.Razem       = Dodaj-Liczbe $d.Razem       $razem
    $d.CacheOdczyt = Dodaj-Liczbe $d.CacheOdczyt (Liczba-Lub-Nic $o.cache_odczyt)
    $d.Wywolan     = Dodaj-Liczbe $d.Wywolan     (Liczba-Lub-Nic $o.wywolan)
    $d.Usd         = Dodaj-Liczbe $d.Usd         (Kwota-Lub-Nic $o.usd)
    # Jedna linia na kazda PROBE dnia (klient.py ponawia nieudany dzien). Tokeny, wywolania i $
    # sumujemy po wszystkich probach - kazda kosztowala. Fakty z OSTATNIEJ UDANEJ proby (nie
    # sumujemy: ponowienie czyta ten sam dzien). Dzien jest bledny, gdy zadna proba nie ma ok=true;
    # opis bledu z ostatniej nieudanej.
    $d.Przebiegi++
    if ($o.ok -eq $true) {
      $d.Ok = $true
      $d.Faktow = Liczba-Lub-Nic $o.faktow
    } else {
      $d.NieudaneWczesniej++
      $b = ("" + $o.blad).Trim()
      if (-not $b) { $b = "próba nieudana (dziennik nie podał przyczyny)" }
      $d.Blad = $b
    }
  }
  foreach ($d in $w.Dni.Values) {
    if ($d.Ok) { $d.Blad = $null }
    else {
      $d.NieudaneWczesniej = 0
      if ($d.Przebiegi -gt 1) { $d.Blad = "$($d.Przebiegi) prób, żadna nie przeszła; ostatni błąd: $($d.Blad)" }
    }
  }
  return $w
}

function Dolacz-Probe($pelna) {
  # Proba z 14.10 jako punkt odniesienia - tylko gdy prawdziwy dziennik nie ma tego dnia.
  if (-not $pelna.Dni.ContainsKey($PROBA_PELNEJ.Dzien)) { $pelna.Dni[$PROBA_PELNEJ.Dzien] = $PROBA_PELNEJ }
  return $pelna
}

# --- pelna wersja: rozbicie przebiegu na etapy ------------------------------------
# Linia koszty.jsonl ma tylko sumy przebiegu. Pojedyncze wywolania modelu leza w dziennikach
# koszt.tsv przegladu dnia (dzienny\<dzien>\przeglad\.stan\ - paczki i konsolidacja,
# ...\przeglad\tagi\.stan\ - tematy dodatkowe); klient.py liczy sume przebiegu z TYCH SAMYCH
# wierszy (wszystkie koszt.tsv pod katalogiem dnia, te same cztery pola tokenow). Dzienniki
# narastaja przez wszystkie proby dnia, wiec wiersz nalezy do przebiegu, gdy jego 'kiedy' jest po
# czasie poprzedniej linii tego dnia i najpozniej w czasie tej linii (oba ISO, czas lokalny,
# co do sekundy). Suma etapow ma sie zgadzac z linia koszty.jsonl - inaczej Etapy-Uwaga i strona
# mowi to wprost. Katalog dnia klient kasuje po 14 dniach (DZIENNY_TRZYMAJ_DNI) - wtedy rozbicia
# nie ma i strona tak pisze (to nie blad).

# etap z koszt.tsv -> nazwa dla wlasciciela; kolejnosc = kolejnosc na stronie
$NazwyEtapow = [ordered]@{ "paczka" = "czytanie rozmów"; "konsolidacja" = "łączenie powtórzeń"; "tagi" = "tematy i poufność" }
$PolaTokenow = @("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")

function Czytaj-Koszt-Dnia($katalog) {
  # Wszystkie wiersze wszystkich koszt.tsv pod katalogiem dnia: { Wiersze, Zle, Blad }
  $w = [pscustomobject]@{ Wiersze = @(); Zle = 0; Blad = "" }
  $pliki = @()
  try { $pliki = @(Get-ChildItem -LiteralPath $katalog -Recurse -Filter "koszt.tsv" -File -ErrorAction Stop) }
  catch { $w.Blad = "nie da się przejrzeć $katalog ($($_.Exception.Message))"; return $w }
  foreach ($p in $pliki) {
    $linie = $null
    try { $linie = @(([System.IO.File]::ReadAllText($p.FullName) -split '\r?\n') | Where-Object { ("" + $_).Trim() }) }
    catch { $w.Blad = "nie da się odczytać $($p.FullName) ($($_.Exception.Message))"; continue }
    if ($linie.Count -eq 0) { continue }
    $kol = @($linie[0] -split "`t")
    foreach ($l in @($linie | Select-Object -Skip 1)) {
      $pola = $l -split "`t"
      if ($pola.Count -ne $kol.Count) { $w.Zle++; continue }
      $s = @{}
      for ($i = 0; $i -lt $pola.Count; $i++) { $s[$kol[$i]] = $pola[$i] }
      $kiedy = ("" + $s["kiedy"]).Trim()
      if ($null -eq (Dzien-Z $kiedy)) { $w.Zle++; continue }
      # jak klient.py: brak liczby = 0 tokenow, wywolanie i tak sie liczy
      $tok = @{}
      foreach ($pole in $PolaTokenow) { $n = Liczba-Lub-Nic $s[$pole]; if ($null -eq $n) { $n = [long]0 }; $tok[$pole] = $n }
      $usd = Kwota-Lub-Nic $s["koszt_usd"]; if ($null -eq $usd) { $usd = 0.0 }
      $w.Wiersze += [pscustomobject]@{ Kiedy = $kiedy; Etap = ("" + $s["etap"]).Trim()
        Czytal = $tok["input_tokens"] + $tok["cache_creation_input_tokens"] + $tok["cache_read_input_tokens"]
        Napisal = $tok["output_tokens"]; Usd = $usd; Znaki = (Liczba-Lub-Nic $s["znaki_wyslane"]) }
    }
  }
  return $w
}

function Dolacz-Etapy($pelna, $katalogDzienny) {
  # Kazdemu przebiegowi pelnej wersji (ListaPrzebiegow) dopisuje Etapy (lista: Etap, Nazwa,
  # Wywolan, Czytal, Napisal, Razem, Usd), Paczek i ZnakiCzytania z etapu czytania - albo
  # EtapyBrak (czemu rozbicia nie ma) - oraz EtapyUwaga, gdy suma etapow nie zgadza sie z suma
  # przebiegu. Zwraca liste tekstow takich niezgodnosci (na gore strony).
  $uwagi = @()
  foreach ($d in @($pelna.Dni.Values)) {
    $lista = @($d.ListaPrzebiegow | Sort-Object Czas)
    if ($lista.Count -eq 0) { continue }
    $kat = Join-Path $katalogDzienny $d.Dzien
    $dziennik = $null
    if (Test-Path -LiteralPath $kat) { $dziennik = Czytaj-Koszt-Dnia $kat }
    $poprzedni = ""
    foreach ($pr in $lista) {
      $od = $poprzedni; $poprzedni = $pr.Czas
      $kosztowal = (($null -ne $pr.Wywolan) -and ($pr.Wywolan -gt 0)) -or (($null -ne $pr.Razem) -and ($pr.Razem -gt 0))
      if (-not $kosztowal) { continue }
      if ($null -eq $dziennik) { $pr.EtapyBrak = "rozbicia na etapy już nie ma - katalog roboczy tego dnia ($kat) klient kasuje po 14 dniach"; continue }
      if ($null -eq (Dzien-Z $pr.Czas)) { $pr.EtapyUwaga = "linia dziennika pełnej wersji nie ma czasu przebiegu - nie wiem, które wywołania do niej należą"; $uwagi += $pr.EtapyUwaga; continue }
      $wiersze = @($dziennik.Wiersze | Where-Object { ([string]::CompareOrdinal($_.Kiedy, $od) -gt 0) -and ([string]::CompareOrdinal($_.Kiedy, $pr.Czas) -le 0) })
      $etapy = [ordered]@{}
      foreach ($k in $NazwyEtapow.Keys) { $etapy[$k] = $null }
      $paczek = 0; $znaki = $null
      foreach ($r in $wiersze) {
        $k = $r.Etap; if (-not $k) { $k = "?" }
        if (-not $etapy[$k]) {
          $nazwa = $NazwyEtapow[$k]; if (-not $nazwa) { $nazwa = "inny etap ('$k')" }
          $etapy[$k] = [pscustomobject]@{ Etap = $k; Nazwa = $nazwa; Wywolan = 0; Czytal = [long]0; Napisal = [long]0; Razem = [long]0; Usd = 0.0 }
        }
        $e = $etapy[$k]
        $e.Wywolan++; $e.Czytal += $r.Czytal; $e.Napisal += $r.Napisal; $e.Razem += ($r.Czytal + $r.Napisal); $e.Usd += $r.Usd
        if ($k -eq "paczka") { $paczek++; $znaki = Dodaj-Liczbe $znaki $r.Znaki }
      }
      $pr.Etapy = @($etapy.Values | Where-Object { $_ })
      if ($paczek -gt 0) { $pr.Paczek = $paczek; $pr.ZnakiCzytania = $znaki }
      $sw = [long]0; $st = [long]0; $su = 0.0
      foreach ($e in $pr.Etapy) { $sw += $e.Wywolan; $st += $e.Razem; $su += $e.Usd }
      $rozne = @()
      if (($null -ne $pr.Wywolan) -and ($sw -ne $pr.Wywolan)) { $rozne += "uruchomień $sw zamiast $($pr.Wywolan)" }
      if (($null -ne $pr.Razem) -and ($st -ne $pr.Razem)) { $rozne += "tokenów $(([long]$st).ToString('N0', [Globalization.CultureInfo]::GetCultureInfo('pl-PL'))) zamiast $(([long]$pr.Razem).ToString('N0', [Globalization.CultureInfo]::GetCultureInfo('pl-PL')))" }
      # klient.py zaokragla sume $ do 4 miejsc
      if (($null -ne $pr.Usd) -and ([math]::Abs($su - $pr.Usd) -gt 0.0006)) { $rozne += "kosztu $($su.ToString('0.0000', $script:Inv)) $ zamiast $($pr.Usd.ToString('0.0000', $script:Inv)) $" }
      $ogon = ""
      if ($dziennik.Zle -gt 0) { $ogon += "; $($dziennik.Zle) nieczytelnych linii w dziennikach koszt.tsv" }
      if ($dziennik.Blad) { $ogon += "; $($dziennik.Blad)" }
      if ($rozne.Count -gt 0) {
        $pr.EtapyUwaga = "Pełna wersja, dzień $($d.Dzien) (przebieg $($pr.Czas)): suma etapów nie zgadza się z sumą przebiegu - wychodzi $($rozne -join ', ') (dzienniki koszt.tsv w $kat)$ogon"
        $uwagi += $pr.EtapyUwaga
      }
    }
  }
  return $uwagi
}

# --- cale zuzycie dnia ---------------------------------------------------------
# Metoda NIE jest tu wymyslona drugi raz: kod C# licznika i jego wersje bierzemy wprost z
# zasobnik\nadzorca\stan-zuzycie.ps1 (zmienne $KOD_LICZNIKA_ZUZYCIA i $WERSJA_ZUZYCIA), czytajac
# plik parserem PowerShella - bez uruchamiania go. Zmiana licznika tam = zmiana tutaj, a zmiana
# wersji liczy zapamietane dni od nowa.

function Wczytaj-Licznik($zrodlo) {
  $plik = Join-Path $zrodlo "zasobnik\nadzorca\stan-zuzycie.ps1"
  if (-not (Test-Path -LiteralPath $plik)) { throw "nie ma licznika tokenów okna nadzorcy ($plik)" }
  $bledy = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($plik, [ref]$null, [ref]$bledy)
  if (@($bledy).Count -gt 0) { throw "licznik tokenów $plik ma błąd składni: $($bledy[0].Message)" }
  $wart = @{}
  $przypisania = $ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.AssignmentStatementAst] }, $false)
  foreach ($a in $przypisania) {
    $lewa = $a.Left
    if (-not ($lewa -is [System.Management.Automation.Language.VariableExpressionAst])) { continue }
    $n = $lewa.VariablePath.UserPath
    if (($n -ne "KOD_LICZNIKA_ZUZYCIA") -and ($n -ne "WERSJA_ZUZYCIA")) { continue }
    $prawa = $a.Right
    if ($prawa -is [System.Management.Automation.Language.CommandExpressionAst]) { $prawa = $prawa.Expression }
    if ($prawa -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $wart[$n] = $prawa.Value }
  }
  if (-not $wart["KOD_LICZNIKA_ZUZYCIA"]) { throw "w $plik nie znalazłem kodu licznika (`$KOD_LICZNIKA_ZUZYCIA)" }
  if (-not $wart["WERSJA_ZUZYCIA"]) { throw "w $plik nie znalazłem wersji licznika (`$WERSJA_ZUZYCIA)" }
  if (-not ('MegaRuchacz.Tokeny.Licznik' -as [type])) {
    try { Add-Type -TypeDefinition $wart["KOD_LICZNIKA_ZUZYCIA"] -ErrorAction Stop }
    catch { if (-not ('MegaRuchacz.Tokeny.Licznik' -as [type])) { throw } }
  }
  return $wart["WERSJA_ZUZYCIA"]
}

$NaglowekPodrecznego = "dzien`twersja`twejscie`ttworzenie`todczyt`twyjscie`todpowiedzi`tpoliczono"

function Czytaj-Podreczny($plik, $wersja) {
  # dzien -> wynik; linie innej wersji licznika pomijamy (beda policzone od nowa), smieci liczymy
  $w = [pscustomobject]@{ Dni = @{}; Zle = 0 }
  if (-not (Test-Path -LiteralPath $plik)) { return $w }
  foreach ($l in ([System.IO.File]::ReadAllText($plik) -split '\r?\n')) {
    if ((-not ("" + $l).Trim()) -or $l.StartsWith("dzien")) { continue }
    $p = $l -split "`t"
    $dz = $null
    if ($p.Count -eq 8) { $dz = Dzien-Z $p[0] }
    $liczby = @()
    if ($null -ne $dz) { $liczby = @(2..6 | ForEach-Object { Liczba-Lub-Nic $p[$_] }) }
    if (($null -eq $dz) -or (@($liczby | Where-Object { $null -eq $_ }).Count -gt 0)) { $w.Zle++; continue }
    if ($p[1] -ne $wersja) { continue }
    $w.Dni[(Klucz-Dnia $dz)] = [pscustomobject]@{ Wejscie = $liczby[0]; Tworzenie = $liczby[1]; Odczyt = $liczby[2]
      Wyjscie = $liczby[3]; Odpowiedzi = $liczby[4]; Razem = ($liczby[0] + $liczby[1] + $liczby[2] + $liczby[3]); Policzono = $p[7] }
  }
  return $w
}

function Zapisz-Podreczny($plik, $dni, $wersja) {
  $kat = Split-Path -Parent $plik
  if (-not (Test-Path -LiteralPath $kat)) { New-Item -ItemType Directory -Force -Path $kat | Out-Null }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append($NaglowekPodrecznego + "`r`n")
  foreach ($k in @($dni.Keys | Sort-Object)) {
    $d = $dni[$k]
    [void]$sb.Append(("{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}`r`n" -f $k, $wersja, $d.Wejscie, $d.Tworzenie, $d.Odczyt, $d.Wyjscie, $d.Odpowiedzi, $d.Policzono))
  }
  $tmp = "$plik.tmp"
  [System.IO.File]::WriteAllText($tmp, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $tmp -Destination $plik -Force
}

function Cale-Zuzycie($dom, $zrodlo, [string[]]$klucze, $plikPodreczny) {
  # Cale zuzycie tokenow w rozmowach z Claude Code dla podanych dni (wszystkie zakonczone).
  # Dni z pliku podrecznego nie licza sie od nowa; reszta - jednym przejsciem licznika.
  $w = [pscustomobject]@{ Dni = @{}; Powod = ""; Ostrzezenia = @(); Policzone = 0; ZPliku = 0; Sekundy = 0.0 }
  if (@($klucze).Count -eq 0) { return $w }
  $wersja = $null
  try { $wersja = Wczytaj-Licznik $zrodlo }
  catch { $w.Powod = "$($_.Exception.Message)"; return $w }
  $pod = Czytaj-Podreczny $plikPodreczny $wersja
  if ($pod.Zle -gt 0) { $w.Ostrzezenia += "plik podręczny całego zużycia ($plikPodreczny): $($pod.Zle) nieczytelnych linii - te dni liczę od nowa" }
  $brak = @()
  foreach ($k in $klucze) {
    if ($pod.Dni.ContainsKey($k)) { $w.Dni[$k] = $pod.Dni[$k]; $w.ZPliku++ } else { $brak += $k }
  }
  if ($brak.Count -eq 0) { return $w }
  $katalog = Join-Path $dom ".claude\projects"
  if (-not (Test-Path -LiteralPath $katalog)) {
    $w.Powod = "nie ma katalogu z rozmowami Claude Code ($katalog)"
    return $w
  }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $od = Dzien-Z ($brak | Sort-Object | Select-Object -First 1)
  $doWyl = (Dzien-Z ($brak | Sort-Object | Select-Object -Last 1)).AddDays(1)
  $bledyListy = $null
  $pliki = @(Get-ChildItem -LiteralPath $katalog -Recurse -Filter *.jsonl -File -ErrorAction SilentlyContinue -ErrorVariable bledyListy |
             Where-Object { $_.LastWriteTime -ge $od } | ForEach-Object { $_.FullName })
  $wynik = [MegaRuchacz.Tokeny.Licznik]::Policz([string[]]$pliki, $od, $doWyl, $false)
  $w.Sekundy = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  # Dzien policzony z bledem odczytu ktoregos pliku albo listy katalogow nie trafia do pliku
  # podrecznego - zostalby zanizony na zawsze. Pokazujemy go z ostrzezeniem i liczymy znowu.
  $niepelne = ($wynik.Bledy.Count -gt 0) -or (@($bledyListy).Count -gt 0)
  if ($niepelne) {
    $przyklad = @($wynik.Bledy | Where-Object { $_ }) | Select-Object -First 1
    if (-not $przyklad -and @($bledyListy).Count -gt 0) { $przyklad = "$($bledyListy[0])" }
    $w.Ostrzezenia += "całe zużycie dni $($brak[0])…$($brak[-1]) może być zaniżone: nie dało się przeczytać $($wynik.Bledy.Count + @($bledyListy).Count) plików rozmów (np. $przyklad) - policzę je znowu przy następnym odświeżeniu"
  }
  $teraz = (Get-Date -Format 'yyyy-MM-dd HH:mm')
  foreach ($k in $brak) {
    $d = $null
    if ($wynik.Dni.ContainsKey($k)) { $d = $wynik.Dni[$k] }
    $x = [pscustomobject]@{ Wejscie = [long]0; Tworzenie = [long]0; Odczyt = [long]0; Wyjscie = [long]0; Odpowiedzi = [long]0; Razem = [long]0; Policzono = $teraz }
    if ($d) {
      $x.Wejscie = [long]$d.Wejscie; $x.Tworzenie = [long]$d.Tworzenie; $x.Odczyt = [long]$d.Odczyt
      $x.Wyjscie = [long]$d.Wyjscie; $x.Odpowiedzi = [long]$d.Odpowiedzi
      $x.Razem = $x.Wejscie + $x.Tworzenie + $x.Odczyt + $x.Wyjscie
    }
    $w.Dni[$k] = $x
    $w.Policzone++
    if (-not $niepelne) { $pod.Dni[$k] = $x }
  }
  if (-not $niepelne) {
    try { Zapisz-Podreczny $plikPodreczny $pod.Dni $wersja }
    catch { $w.Ostrzezenia += "nie zapisałem pliku podręcznego $plikPodreczny ($($_.Exception.Message)) - następne odświeżenie policzy te dni od nowa" }
  }
  return $w
}

# --- zlozenie w dni ------------------------------------------------------------

function Zakres-Dni([datetime]$dzis, $tansza, $bladTanszej, $pelna) {
  # Od pierwszego dnia z jakimikolwiek danymi do wczoraj (dzis jeszcze trwa - ani cale zuzycie,
  # ani czytanie dzisiejszych rozmow nie jest skonczone). Bez danych - sam wczorajszy dzien.
  $wczoraj = $dzis.Date.AddDays(-1)
  $wszystkie = @($tansza.Dni.Keys) + @($pelna.Dni.Keys)
  if ($bladTanszej -and $bladTanszej.Dzien) { $wszystkie += $bladTanszej.Dzien }
  $pierwszy = $wczoraj
  foreach ($k in $wszystkie) {
    $d = Dzien-Z $k
    if (($null -ne $d) -and ($d -lt $pierwszy)) { $pierwszy = $d }
  }
  $klucze = @()
  for ($d = $pierwszy; $d -le $wczoraj; $d = $d.AddDays(1)) { $klucze += (Klucz-Dnia $d) }
  return $klucze
}

function Procent($czesc, $calosc) {
  if (($null -eq $czesc) -or ($null -eq $calosc) -or ($calosc -le 0)) { return $null }
  return (100.0 * [double]$czesc / [double]$calosc)
}

function Zloz-Dni([string[]]$klucze, $tansza, $bladTanszej, $pelna, $cale) {
  # Wiersze od najnowszego dnia. Kazdy: Caly (albo $null, gdy nie policzony), Tansza, Pelna,
  # procenty z odczytem z cache i bez niego, iloraz, bledy przebiegu.
  $wiersze = @()
  foreach ($k in @($klucze | Sort-Object -Descending)) {
    $c = $null
    if ($cale -and $cale.Dni.ContainsKey($k)) { $c = $cale.Dni[$k] }
    $t = $null; if ($tansza.Dni.ContainsKey($k)) { $t = $tansza.Dni[$k] }
    $p = $null; if ($pelna.Dni.ContainsKey($k)) { $p = $pelna.Dni[$k] }
    $calosc = $null; $bezCache = $null
    if ($c -and ($c.Razem -gt 0)) { $calosc = $c.Razem; $bezCache = $c.Razem - $c.Odczyt }
    $r = [pscustomobject]@{
      Dzien = $k; Caly = $c; Tansza = $t; Pelna = $p
      ProcTansza = $null; ProcPelna = $null; ProcTanszaBezCache = $null; ProcPelnaBezCache = $null
      Iloraz = $null; Bledy = @()
    }
    if ($t) { $r.ProcTansza = Procent $t.Tokeny $calosc; $r.ProcTanszaBezCache = Procent $t.Tokeny $bezCache }
    if ($p) {
      $r.ProcPelna = Procent $p.Razem $calosc
      $pBez = $null
      if ($null -ne $p.Razem) { $pBez = $p.Razem; if ($null -ne $p.CacheOdczyt) { $pBez = $p.Razem - $p.CacheOdczyt } }
      $r.ProcPelnaBezCache = Procent $pBez $bezCache
      if (-not $p.Ok) { $r.Bledy += "Pełna wersja: $($p.Blad)" }
    }
    if ($t -and $p -and ($null -ne $t.Tokeny) -and ($t.Tokeny -gt 0) -and ($null -ne $p.Razem)) {
      $r.Iloraz = [double]$p.Razem / [double]$t.Tokeny
    }
    if ($bladTanszej -and ($bladTanszej.Dzien -eq $k)) { $r.Bledy += "Tańsza wersja: $($bladTanszej.Opis)" }
    $wiersze += $r
  }
  return $wiersze
}

function Ma-Dane($r) { return ($r.Tansza -or $r.Pelna -or (@($r.Bledy).Count -gt 0)) }

function Dzien-Kart($wiersze, [datetime]$dzis) {
  # Karty pokazuja wczoraj; gdy wczoraj nic nie czytano (np. niedziela bez rozmow), ostatni
  # dzien z danymi - a strona mowi wprost, ktory to dzien.
  $wczoraj = Klucz-Dnia $dzis.Date.AddDays(-1)
  $w = @($wiersze | Where-Object { $_.Dzien -eq $wczoraj }) | Select-Object -First 1
  if ($w -and (Ma-Dane $w)) { return $w }
  $inny = @($wiersze | Where-Object { Ma-Dane $_ }) | Select-Object -First 1
  if ($inny) { return $inny }
  return $w
}

function Podsumuj-Okres($wiersze) {
  # Sumy za caly okres. Procent kazdej wersji liczony od calego zuzycia TYCH dni, w ktorych
  # ta wersja ma dane (pelna ma dzis jeden dzien - procent od calego okresu udawalby, ze jest
  # tania). Ile to dni, stoi obok.
  $s = [pscustomobject]@{
    Od = $null; Do = $null; Dni = 0; Caly = [long]0; CalyOdczyt = [long]0; DniCalego = 0
    Tansza = [long]0; TanszaDni = 0; TanszaCaly = [long]0; TanszaCalyBez = [long]0
    Pelna = [long]0; PelnaBez = [long]0; PelnaDni = 0; PelnaCaly = [long]0; PelnaCalyBez = [long]0; PelnaProby = 0
    ProcTansza = $null; ProcPelna = $null; ProcTanszaBezCache = $null; ProcPelnaBezCache = $null; ProcCache = $null
  }
  $lista = @($wiersze)
  if ($lista.Count -eq 0) { return $s }
  $s.Do = $lista[0].Dzien
  $s.Od = $lista[-1].Dzien
  $s.Dni = $lista.Count
  foreach ($r in $lista) {
    $c = $r.Caly
    $jestCaly = ($c -and ($c.Razem -gt 0))
    if ($jestCaly) { $s.Caly += $c.Razem; $s.CalyOdczyt += $c.Odczyt; $s.DniCalego++ }
    if ($r.Tansza -and ($null -ne $r.Tansza.Tokeny) -and $jestCaly) {
      $s.Tansza += $r.Tansza.Tokeny; $s.TanszaDni++
      $s.TanszaCaly += $c.Razem; $s.TanszaCalyBez += ($c.Razem - $c.Odczyt)
    }
    if ($r.Pelna -and ($null -ne $r.Pelna.Razem) -and $jestCaly) {
      $s.Pelna += $r.Pelna.Razem; $s.PelnaDni++
      $bez = $r.Pelna.Razem; if ($null -ne $r.Pelna.CacheOdczyt) { $bez -= $r.Pelna.CacheOdczyt }
      $s.PelnaBez += $bez
      $s.PelnaCaly += $c.Razem; $s.PelnaCalyBez += ($c.Razem - $c.Odczyt)
      if ($r.Pelna.Proba) { $s.PelnaProby++ }
    }
  }
  $s.ProcTansza = Procent $s.Tansza $s.TanszaCaly
  $s.ProcTanszaBezCache = Procent $s.Tansza $s.TanszaCalyBez
  $s.ProcPelna = Procent $s.Pelna $s.PelnaCaly
  $s.ProcPelnaBezCache = Procent $s.PelnaBez $s.PelnaCalyBez
  $s.ProcCache = Procent $s.CalyOdczyt $s.Caly
  return $s
}

# Znacznik dla koszt-wiedzy.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztuWiedzy["dane"] = $true
