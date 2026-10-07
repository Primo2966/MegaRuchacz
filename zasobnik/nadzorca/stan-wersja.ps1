# zasobnik\nadzorca\stan-wersja.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Wersja narzedzia: numer z ZMIANY.md (Wersja-Narzedzia),
# porownanie z serwerem przez gita (Stan-Wersji), wiersze dla okna (Wiersz,
# Opis-Wersji), stan aktualizacji z ~\.claude\mr\aktualizacja.json (Stan-Aktualizacji,
# Ocena-Aktualizacji) i przycisk (Aktualizuj -> narzedzia\aktualizuj-megaruchacza.ps1 w tle).
# Wiersz to klocek wierszy Szczegolow uzywany we wszystkich modulach.
# Skad wolane: stan-zbieranie.ps1 (Stan-Wersji), szczegoly.ps1 (Opis-Wersji),
# okno.ps1 (Aktualizuj, Stan-Aktualizacji), przeglad.ps1 i przeglad-tresc.ps1
# (Ocena-Aktualizacji-Teraz). Wczytuje go stan-nadzorcy.ps1 kropka - same definicje.

# ----------------------------------------------------------------- numer wersji

# TA SAMA logika, co Wersja-Narzedzia w wdroz.ps1 (najwyzszy naglowek "## X.Y.Z"
# w ZMIANY.md). Przepisana, a nie dot-sourcowana, bo wdroz.ps1 to skrypt, ktory
# przy wczytaniu wykonalby sie w calosci. Gdy tamta funkcja sie zmieni, ta ma
# pojsc za nia - stad ten komentarz.
function Wersja-Narzedzia($plikZmian) {
  if (-not (Test-Path $plikZmian)) { return $null }
  $naj = $null
  $raw = Czytaj-Tekst $plikZmian
  if (-not $raw) { return $null }
  foreach ($m in [regex]::Matches($raw, '(?m)^##\s+(\d+)\.(\d+)\.(\d+)')) {
    $w = [version]("{0}.{1}.{2}" -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value)
    if ($null -eq $naj -or $w -gt $naj) { $naj = $w }
  }
  if ($null -eq $naj) { return $null }
  return $naj.ToString()
}

# Numer wersji plus odpowiedz na pytanie, czy na gicie lezy cos nowszego.
# $zSieci = $false znaczy "nie ruszaj sieci, powiedz co wiesz z ostatniego pobrania" -
# tak liczymy przy kazdym otwarciu okna, zeby nie czekalo na fetch.
# Zwraca zawsze komplet pol; gdy czegos nie da sie ustalic, w Powod stoi DLACZEGO.
function Stan-Wersji([bool]$zSieci) {
  $w = [pscustomobject]@{
    Lokalna   = $null
    Nowsza    = $null      # ile commitow zdalna ma ponad nami ($null = nie wiadomo)
    Nasze     = $null      # ile mamy lokalnych, ktorych nie ma na zdalnej
    Pobrano   = $null      # kiedy ostatnio zagladalismy do sieci
    Powod     = ""         # dlaczego nie wiadomo
  }
  $plikZmian = Join-Path $script:NadzZrodlo "ZMIANY.md"
  $w.Lokalna = Wersja-Narzedzia $plikZmian
  if (-not $w.Lokalna) { $w.Powod = "nie umiem odczytac numeru wersji z ${plikZmian}" }

  $cyt = '"' + $script:NadzZrodlo + '"'
  $repo = Wolaj-Gita "-C $cyt rev-parse --is-inside-work-tree" $CZAS_GIT
  if (-not $repo.ok -or $repo.tekst -ne "true") {
    $w.Powod = "$($script:NadzZrodlo) to nie repozytorium git - nie ma z czym porownywac"
    return $w
  }

  $stan = Czytaj-Klucze $script:NadzPlikStanu
  $w.Pobrano = Data-Lub-Nic $stan["pobranie"]
  if ($zSieci) {
    $swieze = $false
    if ($w.Pobrano -and (([datetime]::Now - $w.Pobrano).TotalMinutes -lt $MINUT_MIEDZY_POBRANIAMI)) { $swieze = $true }
    if (-not $swieze) {
      $env:GIT_TERMINAL_PROMPT = "0"
      $pobrane = Wolaj-Gita "-C $cyt -c credential.interactive=never fetch --quiet" $CZAS_GIT_FETCH
      if ($pobrane.ok) {
        $w.Pobrano = [datetime]::Now
        if (-not $script:NadzProba) {
          try { Dopisz-Klucze $script:NadzPlikStanu @{ pobranie = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') } }
          catch { Notuj "nie udalo sie zapisac znacznika pobrania" }
        }
      } else {
        $w.Powod = "nie udalo sie zajrzec do sieci ($($pobrane.powod)) - porownuje z tym, co bylo pobrane wczesniej"
      }
    }
  }

  $licznik = Wolaj-Gita "-C $cyt rev-list --left-right --count HEAD...@{u}" $CZAS_GIT
  if (-not $licznik.ok) {
    if (-not $w.Powod) { $w.Powod = "git nie policzyl roznicy wobec zdalnej ($($licznik.powod))" }
    return $w
  }
  $czesci = $licznik.tekst -split '\s+'
  if ($czesci.Count -lt 2) {
    if (-not $w.Powod) { $w.Powod = "git oddal nieczytelna odpowiedz o roznicy: $($licznik.tekst)" }
    return $w
  }
  $w.Nasze  = [int]$czesci[0]
  $w.Nowsza = [int]$czesci[1]
  return $w
}

# Jeden wiersz szczegolow: etykieta po ludzku, wartosc i waga ("" / "uwaga" /
# "pilne" / "szary"). Okno rysuje z tego dwie kolumny, wydruk -Raport - linie
# "etykieta : wartosc". Jedna struktura dla obu, zeby sie nie rozjechaly.
function Wiersz([string]$etykieta, [string]$wartosc, [string]$waga = "") {
  return [pscustomobject]@{ Etykieta = $etykieta; Wartosc = $wartosc; Waga = $waga }
}

# Wersja narzedzia jako wiersze. Do 2026-09-25 byly to linie tekstu z zargonem
# ("na gicie", "commitow") - teraz etykiety mowia po ludzku, a waga koloruje
# tylko to, co naprawde czegos wymaga.
function Opis-Wersji($w) {
  $lok = $w.Lokalna
  $wagaLok = ""
  if (-not $lok) { $lok = "nie wiadomo"; $wagaLok = "uwaga" }
  $linie = @(Wiersz "Wersja na tym komputerze" $lok $wagaLok)
  if ($null -eq $w.Nowsza) {
    $powod = $w.Powod
    if (-not $powod) { $powod = "nie ustaliłem powodu - to samo w sobie jest usterką" }
    $linie += Wiersz "Nowsza na serwerze" "nie wiadomo - $powod" "uwaga"
  } elseif ($w.Nowsza -le 0) {
    $linie += Wiersz "Nowsza na serwerze" "nie ma, masz najnowszą"
  } else {
    $linie += Wiersz "Nowsza na serwerze" "czeka $($w.Nowsza) $(Odmiana ([int]$w.Nowsza) 'zmiana' 'zmiany' 'zmian') - pobierze je przycisk na dole okna" "uwaga"
  }
  if ($w.Nasze -gt 0) {
    $linie += Wiersz "Uwaga" "na tym komputerze jest $($w.Nasze) $(Odmiana ([int]$w.Nasze) 'własna zmiana' 'własne zmiany' 'własnych zmian'), których nie ma na serwerze - aktualizacja odmówi scalenia" "uwaga"
  }
  if ($w.Pobrano) {
    $linie += Wiersz "Ostatnio sprawdzone" "$($w.Pobrano.ToString('yyyy-MM-dd HH:mm'))"
  } else {
    $linie += Wiersz "Ostatnio sprawdzone" "jeszcze ani razu w tej instalacji" "szary"
  }
  return ,$linie
}

# ------------------------------------------------------------------ aktualizacja

# Od 2026-10-07 aktualizacja chodzi SAMA: narzedzia\aktualizuj-megaruchacza.ps1 przy
# starcie nadzorcy i co 60 min (rusza ja dozor), a na koniec restartuje nadzorce.
# Swoj postep zapisuje w ~\.claude\mr\aktualizacja.json (UTF-8):
#   etap          sprawdzam | pobieram | nanosze | restart | gotowe | blad
#   krok, krokow  1..4 z 4;  opis - zdanie pod paskiem
#   wynik         "" | zaktualizowano | aktualne | blad;  powod - przy bledzie, po ludzku
#   wersja_przed, wersja_po, start, koniec, sprawdzone (ISO, czas lokalny), reczna
#   sprawdzone    ostatni UDANY kontakt z serwerem - brak sieci zostawia poprzedni
#   przyczyna     przy bledzie: wynik straznika (bez-sieci, zajete, zablokowane, rozjechane,
#                 nieudane, kopia, bez-zdalnej, nie-repo, bez-gita) albo krok (brak-zrodla,
#                 straznik, git, rejestr, nanoszenie, restart, blokada-pomocnika, wywrotka)
# Tu jest tylko odczyt tego pliku (Stan-Aktualizacji) i jego ocena po ludzku
# (Ocena-Aktualizacji) - wspolna dla okna (pasek i karta Stan), listy spraw na
# Przegladzie i wydruku -Raport. Przycisk (Aktualizuj) tylko uruchamia skrypt w tle
# i NIE czeka - do 0.28.0 wolal straznika synchronicznie do 180 s i okno zamarzalo.

$ETAPY_AKTUALIZACJI = @("sprawdzam", "pobieram", "nanosze", "restart")
$KROKI_AKTUALIZACJI = @("Sprawdzam, czy jest coś nowego", "Pobieram", "Wgrywam do Claude Code / Codeksa / OpenCode", "Uruchamiam ponownie")
$OPISY_ETAPOW = @{ sprawdzam = "Sprawdzam, czy jest coś nowego..."; pobieram = "Pobieram nową wersję..."
                   nanosze = "Wgrywam nową wersję..."; restart = "Uruchamiam MegaRuchacza ponownie..." }
# PROGI Z UZASADNIENIEM:
# - 3 h bez sprawdzenia: aktualizacja ma chodzic co 60 min, wiec 3 h to co najmniej dwa
#   przebiegi z rzedu, ktore przepadly. Jeden przepadly przebieg (uspiony komputer) to
#   jeszcze nie usterka - a nieudany konczy sie bledem w pliku, nie cisza.
# - 15 min po starcie nadzorcy: pierwszy przebieg idzie przy starcie, wiec stary wynik
#   z wczoraj (komputer byl wylaczony) w pierwszym kwadransie to nie alarm, tylko czekanie.
# - 20 min bez zapisu w trakcie: najdluzsze kroki (pobranie przy wolnej sieci, wgranie
#   do narzedzi AI) trwaja minuty; 20 min bez zadnego zapisu = proces nie zyje albo wisi.
# - 30 s po kliknieciu: skrypt zapisuje "sprawdzam" w pierwszej sekundzie; 30 s bez sladu
#   = nie ruszyl (np. zly PowerShell, blokada) i trzeba to powiedziec, a nie krecic paskiem.
# - 24 h od ostatniego UDANEGO sprawdzenia przy przyczynie chwilowej (brak sieci, pobieranie
#   zajete przez inny przebieg): nadzorca probuje co godzine, wiec doba to 24 nieudane proby
#   z rzedu - juz nie chwilowa przerwa (laptop w pociagu), tylko cos, co trzeba naprawic.
#   Wczesniej taki wynik to szara linia bez sprawy: czerwona karta co godzine na laptopie bez
#   sieci bylaby falszywym alarmem, a ten uczy ignorowac prawdziwe. Prog 3 h liczy sie wtedy
#   od ostatniej PROBY (koniec), nie od udanego sprawdzenia - lapie martwy zegar, nie brak sieci.
$GODZIN_BEZ_SPRAWDZENIA_AKTUALIZACJI = 3
$GODZIN_BEZ_UDANEGO_SPRAWDZENIA = 24
$PRZYCZYNY_CHWILOWE = @("bez-sieci", "zajete")
$MINUT_PO_STARCIE_NADZORCY = 15
$MINUT_BEZ_RUCHU_AKTUALIZACJI = 20
$SEKUND_NA_START_AKTUALIZACJI = 30

function Plik-Aktualizacji { return (Join-Path $script:NadzDom ".claude\mr\aktualizacja.json") }

function Data-Aktualizacji($v) {
  if ($v -is [datetime]) { return $v }
  return (Data-Lub-Nic "$v")
}

# Odczyt pliku stanu. Zawsze komplet pol; nieczytelny plik = Blad z powodem, brak = Jest $false.
function Stan-Aktualizacji {
  $plik = Plik-Aktualizacji
  $a = [pscustomobject]@{ Plik = $plik; Jest = $false; Blad = ""; Zapis = $null; Etap = ""; Krok = 0; Krokow = 4
    Opis = ""; Wynik = ""; WersjaPrzed = ""; WersjaPo = ""; Start = $null; Koniec = $null; Sprawdzone = $null
    Powod = ""; Reczna = $false; Przyczyna = ""; Utworzony = $null }
  $fi = New-Object System.IO.FileInfo($plik)
  if (-not $fi.Exists) { return $a }
  $a.Jest = $true
  $a.Zapis = $fi.LastWriteTime
  # Pierwszy zapis pliku = pierwsza proba w ogole: skrypt podmienia plik przez File.Replace,
  # a ta zachowuje date utworzenia. Liczy od niej dobe, gdy udanego sprawdzenia nie bylo nigdy.
  $a.Utworzony = $fi.CreationTime
  $j = $null
  try {
    $txt = [System.IO.File]::ReadAllText($plik, [System.Text.Encoding]::UTF8)
    if (-not "$txt".Trim()) { throw "plik jest pusty" }
    $j = $txt | ConvertFrom-Json
    if ($null -eq $j) { throw "w pliku nie ma żadnych danych" }
  } catch {
    $a.Blad = "nie da się odczytać ${plik}: $($_.Exception.Message)"
    return $a
  }
  $a.Etap = "$($j.etap)".Trim().ToLower()
  if (($ETAPY_AKTUALIZACJI + @("gotowe", "blad")) -notcontains $a.Etap) {
    $a.Blad = "w ${plik} stoi nieznany etap '$($a.Etap)'"
    return $a
  }
  $n = 0
  if ([int]::TryParse("$($j.krok)", [ref]$n)) { $a.Krok = $n }
  if ([int]::TryParse("$($j.krokow)", [ref]$n) -and ($n -gt 0)) { $a.Krokow = $n }
  $a.Opis = "$($j.opis)".Trim()
  $a.Wynik = "$($j.wynik)".Trim().ToLower()
  $a.WersjaPrzed = "$($j.wersja_przed)".Trim()
  $a.WersjaPo = "$($j.wersja_po)".Trim()
  $a.Start = Data-Aktualizacji $j.start
  $a.Koniec = Data-Aktualizacji $j.koniec
  $a.Sprawdzone = Data-Aktualizacji $j.sprawdzone
  $a.Powod = "$($j.powod)".Trim()
  $a.Przyczyna = "$($j.przyczyna)".Trim().ToLower()
  $a.Reczna = (("$($j.reczna)" -eq "True") -or ("$($j.reczna)" -eq "1"))
  return $a
}

# "dziś 08:12", "wczoraj 08:12", "05.10 08:12" - tak jak w uzgodnionym wygladzie.
function Kiedy-Krotko($data) {
  if (-not $data) { return "nie wiem kiedy" }
  $dzis = [datetime]::Now.Date
  if ($data.Date -eq $dzis) { return "dziś $($data.ToString('HH:mm'))" }
  if ($data.Date -eq $dzis.AddDays(-1)) { return "wczoraj $($data.ToString('HH:mm'))" }
  return $data.ToString('dd.MM HH:mm')
}

# Ocena po ludzku. $a = Stan-Aktualizacji; $nadzorcaOd = start dzialajacego nadzorcy
# ($null = nie wiadomo, np. wydruk -Raport: wtedy brak pliku nie jest sprawa, bo nie wiemy,
# czy nadzorca w ogole chodzi); $klik / $klikPowod = klikniecie przycisku w tym oknie
# i ewentualny powod, dla ktorego skrypt nie ruszyl. Zwraca:
#   Trwa, Postep (0..1), Naglowek ("Pobieram nową wersję... (2 z 4)"), Kroki (Napis, Stan:
#   zrobione/trwa/czeka), Znak, Linia, Waga (dobrze/pilne/uwaga/szary), Dopisek,
#   ZPliku ($false = nic nie wiadomo, okno zostawia stara linie "Wersja MegaRuchacza"),
#   Problem ($null albo Waga/Tytul/Porada/Pelne), Przycisk (wlaczony), PrzyciskOpis.
function Ocena-Aktualizacji($a, $teraz, $nadzorcaOd = $null, $klik = $null, [string]$klikPowod = "", [string]$lokalna = "") {
  $przyc = "`„Sprawdź i pobierz nowszą wersję MegaRuchacza`”"
  $o = [pscustomobject]@{ Etykieta = "Aktualizacja MegaRuchacza"; Trwa = $false; Postep = 0.0; Naglowek = ""; Kroki = @()
    Znak = ""; Linia = ""; Waga = "szary"; Dopisek = ""; ZPliku = $true; Problem = $null; Przycisk = $true; PrzyciskOpis = "" }
  $poStarcie = ($null -ne $nadzorcaOd) -and (($teraz - $nadzorcaOd).TotalMinutes -ge $MINUT_PO_STARCIE_NADZORCY)
  $zle = {
    param([string]$linia, [string]$tytul, [string]$porada, [string]$pelne)
    $o.Znak = [string][char]0x2717; $o.Linia = $linia; $o.Waga = "pilne"
    $o.Problem = [pscustomobject]@{ Waga = "pilne"; Tytul = $tytul; Porada = $porada; Pelne = $pelne }
  }
  $wTrakcie = $a -and $a.Jest -and (-not $a.Blad) -and ($ETAPY_AKTUALIZACJI -contains $a.Etap)
  $ruch = $null
  if ($wTrakcie) { $ruch = $a.Zapis; if ($a.Start -and ((-not $ruch) -or ($a.Start -gt $ruch))) { $ruch = $a.Start } }
  $zyje = $wTrakcie -and $ruch -and (($teraz - $ruch).TotalMinutes -lt $MINUT_BEZ_RUCHU_AKTUALIZACJI)
  # klikniecie, na ktore plik jeszcze nie odpowiedzial (start w pliku sprzed klikniecia)
  $czekaNaKlik = $klik -and -not ($a -and $a.Jest -and (-not $a.Blad) -and $a.Start -and ($a.Start -ge $klik.AddSeconds(-2)))

  if ($zyje -or ($czekaNaKlik -and (-not $klikPowod) -and (($teraz - $klik).TotalSeconds -lt $SEKUND_NA_START_AKTUALIZACJI))) {
    $krok = 1; $krokow = 4; $opis = ""
    if ($zyje) {
      $krok = $a.Krok
      if ($krok -lt 1) { $krok = [array]::IndexOf($ETAPY_AKTUALIZACJI, $a.Etap) + 1 }
      $krokow = [math]::Max($a.Krokow, $krok)
      $opis = $a.Opis
      if (-not $opis) { $opis = $OPISY_ETAPOW[$a.Etap] }
    } else { $opis = $OPISY_ETAPOW["sprawdzam"] }
    $o.Trwa = $true
    $o.Postep = [math]::Min(1.0, [math]::Max(0.0, ($krok - 0.5) / $krokow))
    $o.Naglowek = "$opis ($krok z $krokow)"
    for ($i = 1; $i -le [math]::Max($krokow, $KROKI_AKTUALIZACJI.Count); $i++) {
      $napis = $(if ($i -le $KROKI_AKTUALIZACJI.Count) { $KROKI_AKTUALIZACJI[$i - 1] } else { "Krok $i" })
      $st = $(if ($i -lt $krok) { "zrobione" } elseif ($i -eq $krok) { "trwa" } else { "czeka" })
      $o.Kroki += [pscustomobject]@{ Napis = $napis; Stan = $st }
    }
    $o.Waga = ""
    $o.Przycisk = $false
    $o.PrzyciskOpis = "Aktualizacja trwa - postęp widać w karcie Stan na Przeglądzie."
    return $o
  }

  if ($czekaNaKlik) {
    $pw = $klikPowod
    if (-not $pw) { $pw = "przez $SEKUND_NA_START_AKTUALIZACJI s po kliknięciu nie zapisała ani śladu postępu" }
    & $zle "Nie udało się uruchomić aktualizacji: $pw." "Nie udało się uruchomić aktualizacji MegaRuchacza" (
      "Kliknięcie o $($klik.ToString('HH:mm')) nie uruchomiło aktualizacji: $pw. Spróbuj kliknąć $przyc jeszcze raz; jeśli to się powtórzy, ślad jest w dzienniku nadzorcy.") "plik: $(Plik-Aktualizacji)"
    return $o
  }

  if (-not $a -or -not $a.Jest) {
    $o.ZPliku = $false
    if ($poStarcie) {
      $o.Problem = [pscustomobject]@{ Waga = "uwaga"; Tytul = "Aktualizacja MegaRuchacza jeszcze ani razu nie ruszyła sama"
        Porada = "Powinna sprawdzać serwer sama przy starcie i co godzinę, a od uruchomienia ikony przy zegarze ($(Kiedy-Krotko $nadzorcaOd)) nie zostawiła śladu. Kliknij $przyc na dole okna."
        Pelne = "brak pliku $(Plik-Aktualizacji)" }
    }
    return $o
  }

  if ($a.Blad) {
    $o.Znak = "!"; $o.Waga = "uwaga"
    $o.Linia = "Nie umiem odczytać, jak poszła ostatnia aktualizacja - plik z jej postępem jest uszkodzony."
    $o.Problem = [pscustomobject]@{ Waga = "uwaga"; Tytul = "Nie umiem odczytać, jak poszła aktualizacja MegaRuchacza"
      Porada = "Plik, w którym aktualizacja zapisuje swój postęp, jest uszkodzony. Kliknij $przyc na dole okna - aktualizacja zapisze go od nowa."
      Pelne = $a.Blad }
    return $o
  }

  if ($wTrakcie) {
    $nr = $a.Krok; if ($nr -lt 1) { $nr = [array]::IndexOf($ETAPY_AKTUALIZACJI, $a.Etap) + 1 }
    $nap = $(if (($nr -ge 1) -and ($nr -le $KROKI_AKTUALIZACJI.Count)) { $KROKI_AKTUALIZACJI[$nr - 1] } else { $a.Etap })
    $pw = "aktualizacja stanęła na kroku $nr z $([math]::Max($a.Krokow, $nr)) (`„$nap`”) i od $(Kiedy-Krotko $ruch) nic nie zapisała. Kliknij $przyc, żeby spróbować jeszcze raz"
    & $zle "Nie udało się zaktualizować: $pw." "Nie udało się zaktualizować MegaRuchacza" "$(Z-Wielkiej $pw)." "plik: $($a.Plik); start: $($a.Start); ostatni zapis: $($a.Zapis)"
    return $o
  }

  $wersja = $a.WersjaPo
  if (-not $wersja) { $wersja = $a.WersjaPrzed }
  if (-not $wersja) { $wersja = $lokalna }
  if (-not $wersja) { $wersja = "(numer nieznany)" }
  $grace = ($null -ne $nadzorcaOd) -and (-not $poStarcie)
  $bladAkt = ($a.Etap -eq "blad") -or ($a.Wynik -eq "blad")
  if ($bladAkt -and ($PRZYCZYNY_CHWILOWE -contains $a.Przyczyna)) {
    # Brak sieci albo pobieranie zajete przez inny przebieg - szara linia bez sprawy, dopoki
    # od ostatniego UDANEGO sprawdzenia nie minela doba (prog z uzasadnieniem wyzej).
    $bezSieci = ($a.Przyczyna -eq "bez-sieci")
    $udane = $a.Sprawdzone
    $odKiedy = $udane
    if (-not $odKiedy) { $odKiedy = $a.Utworzony }
    $ostatnio = $(if ($udane) { Kiedy-Krotko $udane } else { "jeszcze nigdy" })
    $proba = $a.Koniec
    if (-not $proba) { $proba = $a.Zapis }
    $pelne = "przyczyna: $($a.Przyczyna); ostatnia próba: $(if ($proba) { $proba } else { 'nie wiadomo' }); ostatnie udane sprawdzenie: $(if ($udane) { $udane } else { 'nigdy' }); plik: $($a.Plik)$(if ($a.Powod) { '; ' + $a.Powod })"
    if ($odKiedy -and (($teraz - $odKiedy).TotalHours -ge $GODZIN_BEZ_UDANEGO_SPRAWDZENIA) -and (-not $grace)) {
      if ($bezSieci) {
        & $zle "Od ponad doby nie mogę sprawdzić aktualizacji - brak połączenia z GitHubem (ostatnio sprawdzone: $ostatnio)." "Od ponad doby nie mogę sprawdzić aktualizacji MegaRuchacza" (
          "Brak połączenia z GitHubem - ostatnie udane sprawdzenie: $ostatnio. Sprawdź internet; aktualizacja próbuje sama co godzinę.") $pelne
      } else {
        & $zle "Od ponad doby nie mogę sprawdzić aktualizacji - pobieranie ciągle zajmuje inny proces (ostatnio sprawdzone: $ostatnio)." "Od ponad doby nie mogę sprawdzić aktualizacji MegaRuchacza" (
          "Pobieranie nowej wersji od doby blokuje inny proces - ostatnie udane sprawdzenie: $ostatnio. Uruchom komputer ponownie; jeśli to wraca, przekaż ten opis.") $pelne
      }
      return $o
    }
    $o.Znak = ""; $o.Waga = "szary"
    if ($bezSieci) {
      $o.Linia = "Nie sprawdziłem aktualizacji - brak internetu. Spróbuję sam za godzinę. Ostatnio sprawdzone: $ostatnio."
    } else {
      $o.Linia = "Aktualizację właśnie pobiera inny proces - sprawdzę za godzinę."
    }
    # Martwy zegar: nawet nieudanej proby nie bylo od 3 h (prog liczony od proby, nie od udanego).
    if ($proba -and (($teraz - $proba).TotalHours -ge $GODZIN_BEZ_SPRAWDZENIA_AKTUALIZACJI) -and (-not $grace)) {
      $o.Znak = "!"; $o.Waga = "uwaga"
      $o.Dopisek = "Od ponad $GODZIN_BEZ_SPRAWDZENIA_AKTUALIZACJI godzin nie próbowałem sprawdzić, czy jest coś nowszego - powinienem co godzinę."
      $o.Problem = [pscustomobject]@{ Waga = "uwaga"; Tytul = "Aktualizacja MegaRuchacza nie próbowała sprawdzać serwera od $(Kiedy-Krotko $proba)"
        Porada = "Sprawdzanie ma iść samo co godzinę, a ostatnia próba była $(Kiedy-Krotko $proba). Kliknij $przyc na dole okna, żeby sprawdzić teraz."
        Pelne = $pelne }
    }
    return $o
  }
  if ($bladAkt) {
    $pw = $a.Powod
    if (-not $pw) { $pw = "aktualizacja nie podała powodu - to samo w sobie jest usterką. Kliknij $przyc, żeby spróbować jeszcze raz" }
    $pw = $pw.TrimEnd('.', ' ')
    & $zle "Nie udało się zaktualizować: $pw." "Nie udało się zaktualizować MegaRuchacza" "$(Z-Wielkiej $pw)." "$(Kiedy-Krotko $(if ($a.Koniec) { $a.Koniec } else { $a.Zapis })); plik: $($a.Plik)"
    return $o
  }

  $kiedy = $null
  if ($a.Wynik -eq "zaktualizowano") {
    $kiedy = $a.Koniec; if (-not $kiedy) { $kiedy = $a.Sprawdzone }
    $o.Znak = [string][char]0x2713; $o.Waga = "dobrze"
    $o.Linia = "Zaktualizowano do najnowszej wersji $wersja ($(Kiedy-Krotko $kiedy))"
    if ($a.Sprawdzone -and ((-not $kiedy) -or ($a.Sprawdzone -gt $kiedy))) { $kiedy = $a.Sprawdzone }
  } elseif ($a.Wynik -eq "aktualne") {
    $kiedy = $a.Sprawdzone; if (-not $kiedy) { $kiedy = $a.Koniec }
    $o.Znak = [string][char]0x2713; $o.Waga = "dobrze"
    $o.Linia = "Masz najnowszą wersję $wersja (sprawdzone $(Kiedy-Krotko $kiedy))"
  } else {
    $o.Znak = "!"; $o.Waga = "uwaga"
    $o.Linia = "Aktualizacja skończyła się, ale nie zapisała, czy coś pobrała."
    $o.Problem = [pscustomobject]@{ Waga = "uwaga"; Tytul = "Aktualizacja MegaRuchacza nie zapisała wyniku"
      Porada = "Ostatnia aktualizacja doszła do końca, ale nie zapisała, czy coś pobrała. Kliknij $przyc na dole okna, żeby sprawdzić jeszcze raz."
      Pelne = "wynik '$($a.Wynik)' w $($a.Plik)" }
    return $o
  }
  if (-not $kiedy) { $kiedy = $a.Zapis }
  if ($kiedy -and (($teraz - $kiedy).TotalHours -ge $GODZIN_BEZ_SPRAWDZENIA_AKTUALIZACJI) -and (-not $grace)) {
    $o.Znak = "!"; $o.Waga = "uwaga"
    $o.Dopisek = "Od ponad $GODZIN_BEZ_SPRAWDZENIA_AKTUALIZACJI godzin nie sprawdziłem, czy jest coś nowszego - powinienem co godzinę."
    $o.Problem = [pscustomobject]@{ Waga = "uwaga"; Tytul = "Aktualizacja MegaRuchacza nie sprawdzała serwera od $(Kiedy-Krotko $kiedy)"
      Porada = "Sprawdzanie ma iść samo co godzinę, a ostatnie było $(Kiedy-Krotko $kiedy). Kliknij $przyc na dole okna, żeby sprawdzić teraz."
      Pelne = "ostatnie sprawdzenie: $kiedy; plik: $($a.Plik)" }
  }
  return $o
}

# Ocena na teraz: stan z okna ($script:Aktualizacja, odswiezany zegarem w okno.ps1) albo
# - w wydruku -Raport, gdzie okna nie ma - prosto z pliku.
function Ocena-Aktualizacji-Teraz([string]$lokalna = "") {
  $a = $script:Aktualizacja
  if (-not $a) { $a = Stan-Aktualizacji }
  return (Ocena-Aktualizacji $a ([datetime]::Now) $script:NadzorcaOd $script:AktualizacjaKlik "$($script:AktualizacjaKlikPowod)" $lokalna)
}

# Przycisk: skrypt aktualizacji w osobnym, ukrytym procesie z -Reczna - i powrot od razu.
# Postep pokazuje zegar okna z pliku stanu. Nie ma tu drugiej implementacji pobierania ani
# warunkow odmowy (brudne drzewo, rozjechana historia) - ma je skrypt aktualizacji.
# Zwraca Ok / Powod / Pid; tryb probny niczego nie uruchamia (Proba = $true).
function Aktualizuj {
  $w = [pscustomobject]@{ Ok = $false; Proba = $false; Powod = ""; Pid = $null }
  $skrypt = Join-Path $script:NadzZrodlo "narzedzia\aktualizuj-megaruchacza.ps1"
  if (-not (Test-Path -LiteralPath $skrypt -PathType Leaf)) {
    $w.Powod = "brakuje pliku $skrypt"
    Zanotuj-Wywrotke "aktualizacja z okna" $w.Powod
    return $w
  }
  if ($script:NadzProba) { $w.Proba = $true; $w.Powod = "tryb próbny - aktualizacji nie uruchamiam"; return $w }
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $skrypt + '" -Zrodlo "' + $script:NadzZrodlo.TrimEnd('\') + '" -Reczna'
    $psi.WorkingDirectory = $script:NadzZrodlo
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $w.Pid = $p.Id
    $w.Ok = $true
    $p.Dispose()
    Notuj "aktualizacja: uruchomiona z okna w tle (pid $($w.Pid))"
  } catch {
    $w.Powod = "Windows nie uruchomił skryptu aktualizacji ($($_.Exception.Message))"
    Zanotuj-Wywrotke "aktualizacja z okna" $_
  }
  return $w
}

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["wersja"] = $true
