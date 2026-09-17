# Straznik - pilnuje czterech rzeczy przy kazdym otwarciu okna:
#   0. czy sam katalog zrodlowy narzedzia nie zostal w tyle za zdalnym repo,
#   1. czy blok zasad globalnych MegaRuchacza nadal siedzi w ~/.claude/CLAUDE.md,
#   2. czy wdrozenie w projekcie nie zostalo w tyle za katalogiem zrodlowym,
#   3. ile kosztuje pamiec agenta i czy cokolwiek jest UCINANE.
#
# Wolany przez hook SessionStart, wiec zasada nadrzedna brzmi: gdy wszystko sie
# zgadza, NIC nie wypisuje i nie robi nic drogiego - z jednym wyjatkiem, punktem
# 3., ktory odzywa sie ZAWSZE, bo uzytkownik poprosil o to wprost. Porownania ida po skrocie
# tresci i po numerze wersji. Jedyne siegniecie do sieci to krotki "git fetch"
# w katalogu zrodlowym, z limitem czasu i - w przebiegu zwyklym - najwyzej raz
# na godzine (w trybie -Tlo przy kazdym starcie sesji, patrz Odswiez-Zrodlo);
# bez niego punkt 2. porownywalby wdrozenie ze staroscia i zawsze wychodzilo mu, ze gra.
#
# Przy KAZDYM przebiegu, w kazdym trybie, straznik odklada w pliku stanu slad
# "bylem tu" (data, godzina, tryb) i to, co mu sie po drodze wywrocilo. Z tego
# bierze sie jedyna odpowiedz na pytanie "czy to w ogole chodzi": brak
# wiadomosci ma byc odroznialny od "wszystko gra". Cisze po drugiej stronie
# (niezatwierdzone hooki Codeksa) meldujemy pod Claude Code i na odwrot - hook,
# ktory nie chodzi, sam o sobie nie powie nigdy.
#
# Uzycie:
#   powershell -NoProfile -File narzedzia\straznik-zasad.ps1 [-Zrodlo <repo>] [-Projekt <katalog>]
#   powershell -NoProfile -File narzedzia\straznik-zasad.ps1 -Odrzuc <modul>
#       zapamietuje, ze modul (albo nowa funkcja w nim) ma zostac niewlaczony
#   powershell -NoProfile -File narzedzia\straznik-zasad.ps1 -Moduly
#       wypisuje rejestr modulow w JSON-ie; z tego korzysta wdroz.ps1
#   powershell -NoProfile -File narzedzia\straznik-zasad.ps1 -Tlo
#       tryb bezobslugowy - z niego korzysta hook SessionStart Codeksa, bo Codex
#       nie wciaga wyjscia tego hooka do kontekstu modelu. Robi to samo co
#       przebieg zwykly (pobranie nowszej wersji narzedzia, pilnowanie plikow
#       zasad, nanoszenie poprawek na wdrozenie), tylko nic nie wypisuje na
#       ekran - slad zostaje w dzienniku, bo w tle nie ma kto czytac komunikatow.
#   powershell -NoProfile -File narzedzia\straznik-zasad.ps1 -PoliczKoszt
#       przelicza rachunek za pamiec agenta i zapisuje gotowa linie do pliku
#       podrecznego; nic nie wypisuje. Straznik startuje to sam, osobnym
#       procesem, zeby otwarcie okna nie czekalo na liczenie.
#   powershell -NoProfile -File narzedzia\straznik-zasad.ps1 -KosztCodex
#       wypisuje sam rachunek za pamiec, w formacie ladunku "additionalContext"
#       Codeksa. Osobny hook SessionStart, bo ten od aktualizacji chodzi w tle
#       i jego wyjscia Codex do rozmowy nie wciaga. Nic nie liczy - czyta
#       gotowa linie z pliku podrecznego, wiec start sesji na nic nie czeka.
#   -KatalogDomowy  podstawiony katalog domowy - do testow

param(
  [string]$Zrodlo = "",
  [string]$Projekt = "",
  [string]$KatalogDomowy = $HOME,
  [string]$Odrzuc = "",
  [switch]$Moduly,
  [switch]$Tlo,
  [switch]$PoliczKoszt,
  [switch]$KosztCodex
)

$ErrorActionPreference = "Stop"
if (-not $Zrodlo)  { $Zrodlo  = Split-Path -Parent $PSScriptRoot }
if (-not $Projekt) { $Projekt = (Get-Location).Path }

# Rejestr modulow - JEDNO miejsce, w ktorym opisane sa czesci narzedzia.
# Kazdy modul instaluje sie, pomija i aktualizuje osobno. Dolozenie trzeciego
# to dopisanie tu jednej pozycji: instalator czyta te liste przez -Moduly,
# a plik wersji trzyma stan pod kluczami "modul.<nazwa>.*", wiec format
# niczego nie zaklada co do liczby modulow.
#   pytaj        - czy pytac o zgode (modul podstawowy wchodzi domyslnie)
#   instalator   - skrypt w repo; puste = robi to wprost wdroz.ps1
#   aktualizacja - "pliki" (straznik nanosi sam) albo "instalator"
#                  (straznik tylko mowi, jaka komenda to zrobi - moze kosztowac)
function Rejestr-Modulow {
  return @(
    [ordered]@{
      nazwa        = "workerzy"
      opis         = "tryb kierownika rozdajacego zadania - zasady, role workerow, hooki, rejestr i mapa projektu"
      koszt        = "nic nie pobiera i dziala od razu; pliki leza w .claude\ tego projektu"
      pytaj        = $false
      instalator   = ""
      aktualizacja = "pliki"
    },
    [ordered]@{
      nazwa        = "pamiec"
      opis         = "Lore - przeszukiwalna pamiec wszystkich rozmow odbytych na tej maszynie"
      koszt        = "okolo 465 MB pobrania i Python, lokalna baza z trescia rozmow, dostep agenta do tych tresci, zadanie w harmonogramie co 10 minut"
      pytaj        = $true
      instalator   = "narzedzia\instaluj-lore.ps1"
      aktualizacja = "instalator"
    }
  )
}

if ($Moduly) {
  Write-Output ((Rejestr-Modulow) | ConvertTo-Json -Depth 4 -Compress)
  exit 0
}

# Pomiar ladunku hooka, ostrzezenie o ucieciu i czytanie sufitu - ten sam kod,
# ktorego uzywa wdroz.ps1 (Pilnuj-Sufitu, Limit-Ladunku, Ostrzezenie-O-Ucieciu).
# Wczytujemy go DOPIERO tu, zeby -Moduly zostalo czystym JSON-em. Gdy pliku nie
# ma (starsza kopia narzedzia), straznik leci dalej bez pilnowania sufitu - start
# sesji jest wazniejszy niz to sprawdzenie.
$plikSufitu = Join-Path $PSScriptRoot "sufit-ladunku.ps1"
if (Test-Path $plikSufitu) { . $plikSufitu }

$POCZATEK = "<!-- MegaRuchacz:start -->"
$KONIEC   = "<!-- MegaRuchacz:koniec -->"

$plikDomowy   = Join-Path $KatalogDomowy ".claude\CLAUDE.md"
# Plik instrukcji Codeksa. Bez $env:CODEX_HOME z premedytacja: zasady wpisuje
# wpisz-zasady.ps1, ktory liczy go tak samo - z $KatalogDomowy. Gdybysmy tu
# patrzyli gdzie indziej, straznik pilnowalby innego pliku, niz naprawia.
$plikCodex    = Join-Path $KatalogDomowy ".codex\AGENTS.md"
$plikStanu    = Join-Path $KatalogDomowy ".claude\.megaruchacz-straznik.txt"
$plikWersji   = Join-Path $Projekt ".claude\megaruchacz-wersja.txt"
# Znacznik ostatniego zagladania do sieci. Lezy w katalogu domowym, a nie przy
# pliku wersji projektu, bo katalog zrodlowy jest jeden na maszyne: dziesiec
# otwartych okien ma go odpytac raz, nie dziesiec razy.
$plikPobrania = Join-Path $KatalogDomowy ".claude\.megaruchacz-pobranie.txt"
$MINUT_MIEDZY_POBRANIAMI = 60

# Slad po trybie bezobslugowym. Lezy przy pozostalych plikach stanu straznika,
# zeby wszystko jego bylo w jednym miejscu.
$plikDziennika = Join-Path $KatalogDomowy ".claude\.megaruchacz-tlo.log"
$LINII_DZIENNIKA = 200

# Podreczna liczba za pamiec agenta: gotowa linia, kod (0 = nic nie jest ucinane),
# data policzenia i znacznik dnia, w ktorym poszedl pelniejszy meldunek. Osobny
# plik, bo plik stanu zasad jest przepisywany w calosci przy kazdej zmianie skrotow.
$plikKosztu = Join-Path $KatalogDomowy ".claude\.megaruchacz-koszt.txt"
# Rozbicie rachunku na pozycje - kilkanascie linii, wiec osobny plik, a nie klucz
# w pliku podrecznym (tamten trzyma "klucz: wartosc", po jednej linii na wartosc).
# Liczy je koszt-pamieci.ps1 -Rozbicie w tle, pokazujemy raz dziennie.
$plikRozbicia = Join-Path $KatalogDomowy ".claude\.megaruchacz-rozbicie.txt"
# Liczba starsza niz tyle godzin idzie do przeliczenia w tle (ale pokazujemy ja
# dalej - stara liczba jest lepsza niz cisza).
$GODZIN_MIEDZY_KOSZTAMI = 6
# Powyzej tego nie udajemy, ze to dzisiejszy rachunek - mowimy, z kiedy jest.
$GODZIN_KOSZT_STARY = 30
# Dlawik na samo startowanie procesu liczacego: dziesiec okien otwartych naraz
# ma go odpalic raz, a nieudane liczenie nie ma prawa wracac przy kazdym oknie.
$MINUT_MIEDZY_PROBAMI = 15
# Koszt cyklu wiedzy starszy niz tyle dni znaczy, ze cykl przestal chodzic -
# ta sama liczba, co przy meldunku o samym cyklu (Zglos-Cykl).
$DNI_KOSZT_CYKLU_STARY = 2
# Codex czyta AGENTS.md do 32 KiB - dluzszy plik przycina, wiec koniec zasad
# po prostu przepada. Za ten limit nie odpowiadamy, ale mamy o nim powiedziec.
$LIMIT_AGENTS = 32768

# W tle nikt nie czeka na otwarcie okna, wiec git dostaje wiecej czasu niz
# w hooku, gdzie caly przebieg ma sie zmiescic w kilkunastu sekundach.
if ($Tlo) { $CZAS_GIT = 30; $CZAS_GIT_FETCH = 60 } else { $CZAS_GIT = 5; $CZAS_GIT_FETCH = 6 }

# Jedyne wyjscie straznika. W hooku idzie na ekran (Claude Code wciaga to do
# kontekstu sesji), w tle - do dziennika, bo Write-Host nie trafia tam do nikogo.
$script:Dziennik = @()
function Mow([string]$tekst) {
  if ($Tlo) { $script:Dziennik += $tekst } else { Write-Host $tekst }
}

# To, o czym hook milczy celowo (brak sieci, nic nowego), a co w dzienniku jest
# jedyna odpowiedzia na pytanie "czy to zadanie w ogole chodzi".
function Notuj([string]$tekst) {
  if ($Tlo) { $script:Dziennik += $tekst }
}

function Bez-Bom { return (New-Object System.Text.UTF8Encoding($false)) }

function Zapisz-Tekst($sciezka, $tekst) {
  $katalog = Split-Path -Parent $sciezka
  if ($katalog -and -not (Test-Path $katalog)) { New-Item -ItemType Directory -Force -Path $katalog | Out-Null }
  [System.IO.File]::WriteAllText($sciezka, $tekst, (Bez-Bom))
}

function Czytaj-Tekst($sciezka) {
  if (-not (Test-Path $sciezka)) { return $null }
  try { return [System.IO.File]::ReadAllText($sciezka) } catch { return $null }
}

function Skrot([string]$tekst) {
  if (-not $tekst) { return "" }
  $md5 = [System.Security.Cryptography.MD5]::Create()
  return [System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($tekst))).Replace("-","")
}

function Znormalizuj([string]$tekst) {
  if (-not $tekst) { return "" }
  return ($tekst -replace "`r`n", "`n").Trim()
}

# Tresc bloku MegaRuchacza z pliku instrukcji - albo $null, gdy bloku nie ma.
function Tresc-Bloku($sciezka) {
  $raw = Czytaj-Tekst $sciezka
  if (-not $raw) { return $null }
  $i = $raw.IndexOf($POCZATEK)
  $j = $raw.IndexOf($KONIEC)
  if ($i -lt 0 -or $j -lt $i) { return $null }
  return $raw.Substring($i + $POCZATEK.Length, $j - $i - $POCZATEK.Length)
}

# Tresc do wstrzykniecia ze zrodla - wszystko ponizej linii-znacznika.
# Znacznik dopasowany bez polskich znakow, zeby nie zalezec od kodowania pliku.
function Tresc-Zrodla($sciezka) {
  $raw = Czytaj-Tekst $sciezka
  if (-not $raw) { return $null }
  $m = [regex]::Match($raw, '(?m)^<!--[^>]*WSTRZYKNI[^>]*-->[ \t]*\r?\n')
  if ($m.Success) { return $raw.Substring($m.Index + $m.Length) }
  return $raw
}

# Najwyzszy naglowek "## X.Y.Z" w ZMIANY.md. Wpisy nie zawsze ida po kolei,
# wiec liczy sie najwyzszy numer, nie pierwszy z brzegu.
function Wersja-Narzedzia($plikZmian) {
  $raw = Czytaj-Tekst $plikZmian
  if (-not $raw) { return $null }
  $naj = $null
  foreach ($m in [regex]::Matches($raw, '(?m)^##\s+(\d+)\.(\d+)\.(\d+)')) {
    $w = [version]("{0}.{1}.{2}" -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value)
    if ($null -eq $naj -or $w -gt $naj) { $naj = $w }
  }
  if ($null -eq $naj) { return $null }
  return $naj.ToString()
}

# Wpis z ZMIANY.md dla podanej wersji - zrodlo opisu nowej funkcji.
function Wpis-Zmian($plikZmian, $wersja) {
  $raw = Czytaj-Tekst $plikZmian
  if (-not $raw) { return @() }
  $m = [regex]::Match($raw, '(?ms)^##\s+' + [regex]::Escape($wersja) + '(?!\d).*?(?=^##\s|\z)')
  if (-not $m.Success) { return @() }
  $linie = @()
  foreach ($l in ($m.Value -split '\r?\n')) {
    $t = $l.Trim()
    if ($t -and $t -notmatch '^##\s') { $linie += $t }
  }
  return $linie
}

# Plik wersji wdrozenia: proste "klucz: wartosc" w kolejnosci zapisu.
# Ten sam format maja pliki stanu cyklu i wyjscie "wyciagnij-fakty.ps1 -Kolejka",
# dlatego samo parsowanie jest osobno - czasem czytamy tekst, ktory nie jest plikiem.
function Klucze-Z-Tekstu($raw) {
  $stan = [ordered]@{}
  if (-not $raw) { return $stan }
  foreach ($l in ($raw -split '\r?\n')) {
    $m = [regex]::Match($l, '^\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*:\s*(.*?)\s*$')
    if ($m.Success) { $stan[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $stan
}

function Czytaj-Klucze($sciezka) {
  return (Klucze-Z-Tekstu (Czytaj-Tekst $sciezka))
}

function Zapisz-Klucze($sciezka, $stan) {
  $linie = @()
  foreach ($k in $stan.Keys) { $linie += ("{0}: {1}" -f $k, $stan[$k]) }
  Zapisz-Tekst $sciezka (($linie -join "`r`n") + "`r`n")
}

# Plik stanu straznika trzyma nie tylko skroty zasad, ale takze slad obecnosci
# i wywrotki z przebiegow, ktorych nikt nie ogladal. Dlatego zapisujemy do niego
# WYLACZNIE przez scalenie - przepisanie go w calosci (tak robil Pilnuj-Zasad do
# 0.15.1) kasowaloby wszystko, co skrotem zasad nie jest.
function Dopisz-Klucze($sciezka, $nowe) {
  $stan = Czytaj-Klucze $sciezka
  foreach ($k in $nowe.Keys) { $stan[$k] = $nowe[$k] }
  Zapisz-Klucze $sciezka $stan
}

# ------------------------------- znacznik obecnosci, wywrotki i cisza hookow
# Najdrozsza usterka tego narzedzia nie wyglada jak usterka, tylko jak spokoj:
# hook niezatwierdzony w Codeksie (/hooks), piaskownica, ktora nie przepuszcza
# powershella, albo zadanie wywrocone w pustym "catch" - we wszystkich trzech
# wypadkach widac dokladnie to samo co przy narzedziu sprawnym, czyli nic.
# Brak wiadomosci ma byc odroznialny od "wszystko gra", stad dwa slady w pliku
# stanu straznika (tym samym, w ktorym siedza skroty zasad - osobnego pliku nie
# zakladamy, zeby caly jego stan lezal w jednym miejscu):
#   byl.<tryb> - kiedy straznik ostatnio chodzil i w ktorym trybie,
#   blad.<n>   - co sie wywrocilo przy przebiegu, ktorego nikt nie ogladal.
# Tryby sa rozdzielone z premedytacja: pod Claude Code wszystko moze chodzic
# wzorowo, a hook Codeksa nie ruszyc ani razu - i na odwrot.
$GODZIN_CISZY = 24
$WYWROTEK_NAJWYZEJ = 5
$script:Wywrotki = @()

# Tryb, w ktorym straznik akurat chodzi - to samo slowo jest koncowka klucza
# "byl.<tryb>". CLAUDE_PROJECT_DIR ustawia samo Claude Code, wolajac hooka; bez
# niej to uruchomienie z reki, ktore o zdrowiu hookow nie mowi nic.
function Nazwa-Trybu {
  if ($Tlo)        { return "tlo" }      # hook SessionStart Codeksa, bezobslugowy
  if ($KosztCodex) { return "codex" }    # hook Codeksa od rachunku za pamiec
  if ($env:CLAUDE_PROJECT_DIR) { return "claude" }
  return "recznie"
}

# Wywrotka zadania NIE przerywa przebiegu (start sesji jest wazniejszy), ale ma
# zostawic slad: w dzienniku od razu, a w pliku stanu do zameldowania czlowiekowi
# przy najblizszym przebiegu, ktory ma komu mowic.
function Zanotuj-Wywrotke([string]$zadanie, $blad) {
  $tresc = "$blad"
  if ($blad -and $blad.Exception) { $tresc = $blad.Exception.Message }
  $tresc = ($tresc -replace '[\r\n\t]+', ' ').Trim()
  if (-not $tresc) { $tresc = "wyjatek bez tresci" }
  if ($tresc.Length -gt 300) { $tresc = $tresc.Substring(0, 300) }
  $script:Wywrotki += ("{0} | {1}" -f $zadanie, $tresc)
  Notuj "wywrocilo sie: ${zadanie} - ${tresc}"
}

# Jeden zapis na koniec przebiegu: "bylem tu" plus wywrotki, ktore sie zebraly.
function Zapisz-Obecnosc([string]$tryb) {
  try {
    $stan = Czytaj-Klucze $plikStanu
    $stan["byl.$tryb"] = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    $naj = 0
    foreach ($k in @($stan.Keys)) {
      $m = [regex]::Match($k, '^blad\.(\d+)$')
      if ($m.Success -and ([int]$m.Groups[1].Value) -gt $naj) { $naj = [int]$m.Groups[1].Value }
    }
    foreach ($w in $script:Wywrotki) {
      # Piata wywrotka niczego juz nie tlumaczy, a plik stanu ma zostac czytelny.
      if ($naj -ge $WYWROTEK_NAJWYZEJ) { break }
      $naj++
      $stan["blad.$naj"] = ("{0} | {1} | {2}" -f $tryb, (Get-Date -Format 'yyyy-MM-dd HH:mm'), $w)
    }
    Zapisz-Klucze $plikStanu $stan
  } catch {
    # Ostatnie ogniwo lancucha: gdy nie da sie zapisac nawet tego, zostaje
    # dziennik trybu bezobslugowego. Wyjatek stad nie ma prawa wyjsc.
    Notuj "zapis znacznika obecnosci nie wyszedl: $($_.Exception.Message)"
  }
}

# Wywrotki z poprzednich przebiegow - zwraca gotowe linie i CZYSCI je z pliku
# stanu. Raz zameldowany blad ma nie wracac do konca swiata; gdy rzecz sie
# powtorzy, wpis pojawi sie na nowo przy nastepnej wywrotce.
function Odbierz-Wywrotki {
  $stan = Czytaj-Klucze $plikStanu
  $klucze = @($stan.Keys | Where-Object { $_ -match '^blad\.\d+$' })
  if ($klucze.Count -eq 0) { return @() }
  $linie = @()
  foreach ($k in $klucze) {
    $cz = "$($stan[$k])" -split '\s*\|\s*', 4
    if ($cz.Count -eq 4) { $linie += "$($cz[2]) - $($cz[3]) (tryb $($cz[0]), $($cz[1]))" }
    else { $linie += "$($stan[$k])" }
    $stan.Remove($k)
  }
  try { Zapisz-Klucze $plikStanu $stan } catch { }   # nie wyczyscilo sie - wroca raz jeszcze, trudno
  return $linie
}

# Kiedy dany program chodzil na tej maszynie ostatni raz - po swiezosci plikow,
# ktore prowadzi sam w swoim katalogu domowym. To jedyny dowod przychodzacy
# SPOZA naszych hookow, wiec tylko on pozwala odroznic "hook nie wystartowal"
# od "uzytkownik po prostu nie odpalal tego programu". Pliki pisane przez nas
# samych sie nie licza (stad wzorce do pominiecia), a w podkatalogi nie
# schodzimy - caly przebieg ma sie zmiescic w kilkunastu sekundach.
function Kiedy-Chodzil($katalog, $nieNasze) {
  if (-not $katalog -or -not (Test-Path $katalog)) { return $null }
  $naj = $null
  foreach ($p in @(Get-ChildItem -Path $katalog -File -ErrorAction SilentlyContinue)) {
    $pomin = $false
    foreach ($wzor in $nieNasze) { if ($p.Name -like $wzor) { $pomin = $true } }
    if ($pomin) { continue }
    if ($null -eq $naj -or $p.LastWriteTime -gt $naj) { $naj = $p.LastWriteTime }
  }
  return $naj
}

# Czy w tym projekcie stoi wdrozenie dla Codeksa i czy Codex w ogole jest na tej
# maszynie. Brak przebiegow pod Codeksem tam, gdzie Codeksa nie ma, to nie
# usterka, tylko normalny stan komputera - a falszywy alarm jest gorszy niz brak
# alarmu, bo uczy ignorowac alarmy.
function Jest-Wdrozenie-Codex {
  if (-not (Test-Path (Split-Path -Parent $plikCodex))) { return $false }
  if (-not $Projekt) { return $false }
  if (Test-Path (Join-Path $Projekt ".codex")) { return $true }
  foreach ($p in @($plikWersji, (Join-Path $Projekt ".megaruchacz\wersja.txt"))) {
    if (Test-Path $p) {
      $w = Czytaj-Klucze $p
      if ($w["codex.wersja"]) { return $true }
    }
  }
  return $false
}

# Wspolny rdzen obu meldunkow o ciszy: porownuje slady naszego hooka (klucze
# "byl.*") ze sladami, ktore zostawil sam program. Dwa stopnie pewnosci:
#   1. program chodzil, a hook nie zostawil sladu - dowod twardy,
#   2. wdrozenie stoi od doby, a hook nie odnotowal ANI JEDNEGO przebiegu -
#      dokladnie tak wyglada niezatwierdzony /hooks.
# Zwykla przerwa w pracy (weekend, tydzien bez Codeksa) nie jest ani jednym,
# ani drugim i alarmu nie wywola. Zostaje jedna dziura, ktorej nie zalatamy:
# kto uzywa programu WYLACZNIE w projektach bez MegaRuchacza, ten ma swieze
# slady mimo sprawnych hookow - dlatego meldunek podaje obie daty zamiast
# wyrokowac i odzywa sie raz na dobe, a nie przy kazdym oknie.
# Zwraca powod jako kawalek zdania albo pusty tekst, gdy nie ma o czym mowic.
function Powod-Ciszy($kluczeSladu, $kiedyChodzil, $kluczZauwazenia) {
  $stan = Czytaj-Klucze $plikStanu
  $teraz = [datetime]::Now

  # Pierwsze zauwazenie wdrozenia zaczyna okres ochronny - bez niego swieze
  # wdrozenie krzyczaloby "hook nie chodzil" w minucie, w ktorej powstalo.
  $zauwazony = [datetime]::MinValue
  if (-not [datetime]::TryParse($stan[$kluczZauwazenia], [ref]$zauwazony)) {
    try { Dopisz-Klucze $plikStanu ([ordered]@{ $kluczZauwazenia = $teraz.ToString('yyyy-MM-dd HH:mm:ss') }) } catch { }
    return ""
  }

  $ostatni = [datetime]::MinValue
  foreach ($k in $kluczeSladu) {
    $d = [datetime]::MinValue
    if ([datetime]::TryParse($stan[$k], [ref]$d) -and $d -gt $ostatni) { $ostatni = $d }
  }

  if ($ostatni -eq [datetime]::MinValue) {
    $godzin = [int]($teraz - $zauwazony).TotalHours
    if ($godzin -le $GODZIN_CISZY) { return "" }
    return "nie odnotowal ani jednego przebiegu od wdrozenia (${godzin} godzin temu)"
  }
  if ($kiedyChodzil -and ($kiedyChodzil - $ostatni).TotalHours -gt $GODZIN_CISZY) {
    return ("nie zostawil sladu od " + $ostatni.ToString('yyyy-MM-dd HH:mm') +
            ", a sam program chodzil " + $kiedyChodzil.ToString('yyyy-MM-dd HH:mm'))
  }
  return ""
}

# Meldunek o ciszy pod Claude Code dotyczy hookow CODEKSA - i odwrotnie: o hooku
# Claude Code mowi ladunek pod Codeksem (patrz Wypisz-Koszt-Codex). Ten podzial
# jest sednem sprawy, bo hook, ktory nie chodzi, sam o sobie nie powie NIGDY,
# wiec wykrycie musi przyjsc z drugiej strony.
function Zglos-Cisze {
  if (-not (Jest-Wdrozenie-Codex)) { return }
  $chodzil = Kiedy-Chodzil (Split-Path -Parent $plikCodex) @("AGENTS.md", "AGENTS.md.bak-*")
  $powod = Powod-Ciszy @("byl.tlo", "byl.codex") $chodzil "codex.zauwazony"
  if (-not $powod) { return }
  $stan = Czytaj-Klucze $plikStanu
  $dzis = (Get-Date -Format 'yyyy-MM-dd')
  if ($stan["cisza.codex"] -eq $dzis) { return }   # raz na dobe wystarczy
  try { Dopisz-Klucze $plikStanu ([ordered]@{ "cisza.codex" = $dzis }) } catch { }
  Write-Host "MegaRuchacz: hook Codeksa ${powod}."
  Write-Host "    Sprawdz w Codeksie polecenie /hooks - najpewniej hooki nie sa zatwierdzone. Jesli sa zatwierdzone, to piaskownica Codeksa nie przepuszcza powershella i tez nic nie chodzi."
}

# To samo w druga strone, jedna linia do ladunku hooka Codeksa. Krotko, bo ten
# ladunek ma sufit 1000 znakow i jest ucinany od konca.
function Cisza-Claude-Linia {
  if (-not $Projekt -or -not (Test-Path $plikWersji)) { return "" }
  $dom = Split-Path -Parent $plikDomowy
  # Claude Code poznajemy po plikach, ktore prowadzi sam - katalog ~\.claude
  # zaklada tez MegaRuchacz, wiec sam katalog niczego nie dowodzi.
  if (-not (Test-Path (Join-Path $dom "history.jsonl")) -and
      -not (Test-Path (Join-Path $KatalogDomowy ".claude.json"))) { return "" }
  $chodzil = Kiedy-Chodzil $dom @("CLAUDE.md", "CLAUDE.md.bak*", ".megaruchacz-*")
  $powod = Powod-Ciszy @("byl.claude") $chodzil "claude.zauwazony"
  if (-not $powod) { return "" }
  $stan = Czytaj-Klucze $plikStanu
  $dzis = (Get-Date -Format 'yyyy-MM-dd')
  if ($stan["cisza.claude"] -eq $dzis) { return "" }
  try { Dopisz-Klucze $plikStanu ([ordered]@{ "cisza.claude" = $dzis }) } catch { }
  return "UWAGA: hook MegaRuchacza pod Claude Code ${powod} - sprawdz hooki w .claude\settings.json tego projektu."
}

# Wywrotki z przebiegow, ktorych nikt nie ogladal (tlo, hooki Codeksa) - tu jest
# pierwsze miejsce, w ktorym maja szanse dotrzec do czlowieka.
function Zglos-Wywrotki {
  $linie = @(Odbierz-Wywrotki)
  if ($linie.Count -eq 0) { return }
  Write-Host "MegaRuchacz: przy poprzednim przebiegu straznika cos sie wywrocilo (sesji to nie zatrzymalo, ale samo sie nie naprawi):"
  foreach ($l in $linie) { Write-Host "    $l" }
}

# Zamyka przebieg w tle: zbierane komunikaty ida na koniec dziennika, a z gory
# leci wszystko powyzej $LINII_DZIENNIKA - plik ma byc dowodem, ze zadanie
# chodzi, a nie archiwum rosnacym bez konca.
function Dopisz-Dziennik {
  if (-not $Tlo) { return }
  $stempel = Get-Date -Format 'yyyy-MM-dd HH:mm'
  $swieze = @()
  if ($script:Dziennik.Count -eq 0) {
    $swieze += "$stempel | nic nie wymagalo uwagi"
  } else {
    foreach ($l in $script:Dziennik) { $swieze += "$stempel | $l" }
  }
  $stare = @()
  $raw = Czytaj-Tekst $plikDziennika
  if ($raw) { $stare = @(($raw -split '\r?\n') | Where-Object { $_.Trim() }) }
  $wszystkie = @($stare + $swieze)
  if ($wszystkie.Count -gt $LINII_DZIENNIKA) {
    $wszystkie = @($wszystkie | Select-Object -Last $LINII_DZIENNIKA)
  }
  # Dziennik jest jedynym wyjsciem trybu bezobslugowego - gdy i on nie dziala,
  # slad musi zostac w pliku stanu, inaczej caly przebieg znika bez ladu.
  try { Zapisz-Tekst $plikDziennika (($wszystkie -join "`r`n") + "`r`n") }
  catch { Zanotuj-Wywrotke "zapis dziennika" $_ }
}

function Kopia-Zapasowa($sciezka, $stempel) {
  if (Test-Path $sciezka) { Copy-Item $sciezka "$sciezka.bak-$stempel" -Force }
}

# Nadpisuje plik nalezacy do narzedzia, ale tylko gdy faktycznie sie rozni.
# Przed nadpisaniem kopia zapasowa - tak samo jak robi to wdroz.ps1.
function Odswiez($zrodlowy, $docelowy, $stempel) {
  if (-not (Test-Path $zrodlowy)) { return $false }
  if (Test-Path $docelowy) {
    if ((Czytaj-Tekst $docelowy) -eq (Czytaj-Tekst $zrodlowy)) { return $false }
    Kopia-Zapasowa $docelowy $stempel
  }
  Copy-Item $zrodlowy $docelowy -Force
  return $true
}

# Ladunek dla hooka startowego - skladany tu, zeby nie wolac node'a.
function Zbuduj-Sesje($cel) {
  $plikZasad = Join-Path $cel "megaruchacz-zasady.md"
  if (-not (Test-Path $plikZasad)) { return }
  $naglowek = "Zasady pracy w tym projekcie (tryb MegaRuchacz). Stosuj je przez cala sesje:`n`n"
  $ladunek = [ordered]@{
    suppressOutput = $true
    hookSpecificOutput = [ordered]@{
      hookEventName = "SessionStart"
      additionalContext = $naglowek + (Czytaj-Tekst $plikZasad)
    }
  }
  Zapisz-Tekst (Join-Path $cel "megaruchacz-sesja.json") ($ladunek | ConvertTo-Json -Depth 5 -Compress)
}

# Polecenie hooka przypomnienia. Nie samo "cat" pliku, tylko krotki skrypt, ktory
# ten plik wypisze i dolozy jedna linie o cyklu wiedzy, gdy ten akurat pracuje.
# Nazwa ladunku ZOSTAJE w poleceniu: po niej rozpoznaja ten hook koszt-pamieci.ps1
# i sufit-ladunku.ps1, szukajac przy nim additionalContextLimit.
# "|| cat": gdy na maszynie nie ma node'a, przypomnienie ma i tak dojsc - bez linii
# postepu, ale w calosci. Cisza bylaby tu gorsza niz brak jednego dopisku.
function Polecenie-Przypomnienia($zrodloUkosniki) {
  return 'node "' + $zrodloUkosniki + '/narzedzia/przypomnienie.js" "$CLAUDE_PROJECT_DIR/.claude/orchestrator-reminder.json" || cat "$CLAUDE_PROJECT_DIR/.claude/orchestrator-reminder.json"'
}

# settings.json jest w polowie wlasnoscia uzytkownika - dopisujemy wylacznie
# brakujace hooki, nigdy nie przepisujemy calego pliku.
function Napraw-Hooki($cel, $zrodlo, $stempel) {
  $plik = Join-Path $cel "settings.json"
  $raw = Czytaj-Tekst $plik
  if (-not $raw) { return $false }
  try { $s = $raw.TrimStart([char]0xFEFF) | ConvertFrom-Json } catch { return $false }

  $r = $zrodlo.Replace("\","/")
  $doDodania = @()
  if ($raw -notlike "*megaruchacz-sesja.json*") {
    $doDodania += ,@("SessionStart", 'cat "$CLAUDE_PROJECT_DIR/.claude/megaruchacz-sesja.json" 2>/dev/null || cat .claude/megaruchacz-sesja.json', 5)
  }
  if ($raw -notlike "*orchestrator-reminder.json*") {
    $doDodania += ,@("UserPromptSubmit", (Polecenie-Przypomnienia $r), 5)
  }
  if ($raw -notlike "*mr-log.js*") {
    $doDodania += ,@("SubagentStart", 'node "$CLAUDE_PROJECT_DIR/.claude/mr-log.js"', 5)
    $doDodania += ,@("SubagentStop",  'node "$CLAUDE_PROJECT_DIR/.claude/mr-log.js" stop', 5)
  }
  if ($raw -notlike "*straznik-zasad.ps1*") {
    $doDodania += ,@("SessionStart", 'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
      $r + '/narzedzia/straznik-zasad.ps1" -Zrodlo "' + $r + '" -Projekt "$CLAUDE_PROJECT_DIR" || true', 15)
  }
  # Podmiana STAREGO hooka przypomnienia (samo "cat" pliku) na wywolanie skryptu.
  # To jedyne miejsce, w ktorym nadpisujemy polecenie juz istniejacego hooka - bez
  # tego wdrozenia sprzed 2026-09-17 nigdy nie pokazalyby postepu cyklu, bo hook
  # dopisuje sie wylacznie wtedy, gdy go w ogole nie ma. Ruszamy tylko wpisy, ktore
  # niosa NASZ plik i nie wolaja jeszcze naszego skryptu.
  $podmienione = $false
  if ($s.hooks -and ($s.hooks.PSObject.Properties.Name -contains "UserPromptSubmit")) {
    foreach ($grupa in @($s.hooks.UserPromptSubmit)) {
      foreach ($h in @($grupa.hooks)) {
        if (-not $h) { continue }
        if ("$($h.command)" -notlike "*orchestrator-reminder.json*") { continue }
        if ("$($h.command)" -like "*przypomnienie.js*") { continue }
        $h.command = Polecenie-Przypomnienia $r
        $podmienione = $true
      }
    }
  }

  if ($doDodania.Count -eq 0 -and -not $podmienione) { return $false }

  if (-not ($s.PSObject.Properties.Name -contains "hooks") -or $null -eq $s.hooks) {
    $s | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force
  }
  foreach ($w in $doDodania) {
    $wpis = [pscustomobject]@{ hooks = @([pscustomobject]@{ type = "command"; shell = "bash"; timeout = $w[2]; command = $w[1] }) }
    if ($s.hooks.PSObject.Properties.Name -contains $w[0]) {
      $s.hooks.($w[0]) = @($s.hooks.($w[0])) + $wpis
    } else {
      $s.hooks | Add-Member -NotePropertyName $w[0] -NotePropertyValue @($wpis) -Force
    }
  }
  Kopia-Zapasowa $plik $stempel
  Zapisz-Tekst $plik ($s | ConvertTo-Json -Depth 20)
  return $true
}

# Blok zasad w AGENTS.md - Codex czyta ten plik sam, bez zadnego hooka, wiec
# nieodswiezony blok znaczy po prostu stare zasady. Ruszamy WYLACZNIE to, co
# stoi miedzy znacznikami; gdy znacznikow nie ma, nie dopisujemy nic - tak samo
# ostroznie jak wdroz.ps1, bo to w polowie cudzy plik.
# Zwraca $true, gdy zasady w AGENTS.md sa - od tego zalezy, czy ladunek hooka
# ma niesc pelna tresc, czy samo przypomnienie.
function Odswiez-Agents($projekt, $plikZasad, $stempel) {
  $plik = Join-Path $projekt "AGENTS.md"
  $stare = Czytaj-Tekst $plik
  if (-not $stare) { return $false }
  $i = $stare.IndexOf($POCZATEK, [System.StringComparison]::Ordinal)
  $j = $stare.IndexOf($KONIEC, [System.StringComparison]::Ordinal)
  if ($i -lt 0 -or $j -le $i) { return $false }
  $tresc = Czytaj-Tekst $plikZasad
  if (-not $tresc) { return $false }
  $nowe = $stare.Substring(0, $i) + $POCZATEK + "`r`n" + $tresc.Trim() + "`r`n" + $KONIEC +
          $stare.Substring($j + $KONIEC.Length)
  if ($nowe -eq $stare) { return $true }
  Kopia-Zapasowa $plik $stempel
  Zapisz-Tekst $plik $nowe
  return $true
}

# Ladunek hooka startowego Codeksa - odpowiednik Zbuduj-Sesje, tylko w
# .megaruchacz\. Pelne zasady leca tylko wtedy, gdy NIE MA ich w AGENTS.md;
# inaczej samo przypomnienie, bo additionalContext ma wlasny limit i drugi raz
# tego samego nie wysylamy. Obie tresci musza brzmiec tak samo jak w wdroz.ps1
# (czesc "4b. Codex CLI") - to jeden komunikat, tylko skladany w dwoch miejscach.
function Zbuduj-Sesje-Codex($celMega, $krotkie) {
  $plikZasad = Join-Path $celMega "zasady-kierownika.md"
  if (-not (Test-Path $plikZasad)) { return }
  if ($krotkie) {
    $tresc = "Tryb MegaRuchacz jest wlaczony w tym projekcie: jestes kierownikiem, ktory rozdaje robote podagentom. Pelne zasady masz w AGENTS.md w korzeniu projektu (kopia: .megaruchacz/zasady-kierownika.md) - stosuj je przez cala sesje. Stan pracy: .megaruchacz/worklog.md (rejestr) i .megaruchacz/mapa.md (co gdzie lezy)."
  } else {
    $tresc = "Zasady pracy w tym projekcie (tryb MegaRuchacz). Stosuj je przez cala sesje:`n`n" + (Czytaj-Tekst $plikZasad)
  }
  $ladunek = [ordered]@{
    hookSpecificOutput = [ordered]@{
      hookEventName = "SessionStart"
      additionalContext = $tresc
    }
  }
  Zapisz-Tekst (Join-Path $celMega "zasady-sesja.json") ($ladunek | ConvertTo-Json -Depth 5 -Compress)
}

# Ten ladunek idzie prosto do modelu, a wszystko ponad additionalContextLimit
# jest ucinane OD KONCA i bez slowa. Instalator ma prawo odmowic wdrozenia, bo
# stoi przy nim czlowiek - tutaj chodzi hook startowy, wiec przerwanie zepsuloby
# start pracy. Zamiast tego robimy to, co wdroz.ps1: wstawiamy identyczne
# ostrzezenie na POCZATEK tresci (jedyne miejsce, ktore przezyje uciecie)
# i mowimy o tym jedna linia - w tle znaczy: do dziennika, bo nie ma komu krzyczec.
# Sprawdzamy przy KAZDYM przebiegu, nie tylko po przebudowie ladunku: sufit moze
# zjechac w dol sam, gdy ktos poprawi .codex\hooks.json, a zasady zostana te same.
function Pilnuj-Sufitu-Sesji-Codex($celMega, $celCodex) {
  $plikLadunku = Join-Path $celMega "zasady-sesja.json"
  if (-not (Test-Path $plikLadunku)) { return }
  if (-not (Get-Command Pilnuj-Sufitu -ErrorAction SilentlyContinue)) { return }
  # $true = poprawiaj plik na dysku; pomiar leci po tresci BEZ ostrzezenia
  # z poprzedniego przebiegu, wiec liczba nie rosnie przy kazdej aktualizacji.
  $w = Pilnuj-Sufitu $plikLadunku (Join-Path $celCodex "hooks.json") "zasady-sesja.json" `
                     ".codex\hooks.json" "zasady kierownika dla Codeksa" $true
  if (-not $w.Przekroczony) { return }
  $strata = [int]$w.Znaki - [int]$w.Limit
  Mow ("MegaRuchacz: zasady dla Codeksa nie mieszcza sie w suficie hooka - maja " +
       "$($w.Znaki) znakow, a zmiesci sie $($w.Limit), wiec koniec (${strata} znakow) zostanie uciety. " +
       "Ladunek $plikLadunku ma juz ostrzezenie w pierwszej linii; podnies additionalContextLimit " +
       "przy hooku od zasady-sesja.json w .codex\hooks.json albo skroc zasady.")
}

# .codex\hooks.json - tu chodzimy na palcach. Zmiana DEFINICJI hooka (polecenie,
# timeout, matcher, async) uniewaznia zatwierdzenie z /hooks i zmusza uzytkownika
# do powtarzania go, wiec grup, ktore juz tam sa, NIE RUSZAMY w ogole - dopisujemy
# wylacznie brakujace. Swoje poznajemy po "statusMessage", tak samo jak wdroz.ps1.
# Zwraca liste zdarzen, ktorych grupy doszly - o kazdej trzeba powiedziec wprost.
function Napraw-Hooki-Codex($celCodex, $zrodlo, $projekt, $stempel) {
  $surowy = Czytaj-Tekst (Join-Path $zrodlo "szablony-codex\hooks.json")
  if (-not $surowy) { return @() }
  $surowy = $surowy.TrimStart([char]0xFEFF).Replace("{{PROJEKT}}", $projekt.Replace("\","/")).Replace("{{ZRODLO}}", $zrodlo.Replace("\","/"))
  try { $szablon = $surowy | ConvertFrom-Json } catch { return @() }
  if (-not $szablon.hooks) { return @() }

  $plik = Join-Path $celCodex "hooks.json"
  $s = [pscustomobject]@{}
  $raw = Czytaj-Tekst $plik
  # Cudzy plik, ktory nie jest czystym JSON-em, zostaje nietkniety - tak samo
  # jak w instalatorze. Lepiej nie dopisac hooka niz zepsuc komus ustawienia.
  if ($raw) {
    try { $s = $raw.TrimStart([char]0xFEFF) | ConvertFrom-Json } catch { return @() }
  }
  if (-not ($s.PSObject.Properties.Name -contains "hooks") -or $null -eq $s.hooks) {
    $s | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force
  }

  # Jedyny wyjatek od zasady "istniejacych grup nie ruszamy": stare przypomnienie,
  # ktore samo wypisywalo plik ("cat" / Get-Content). Dzis to samo robi skrypt, ktory
  # dokleja linie o pracujacym cyklu - i bez tej jednej podmiany zadne wdrozenie
  # sprzed 2026-09-17 by jej nie zobaczylo. Podmieniamy RAZ: polecenie wskazuje juz
  # na skrypt, wiec kazda kolejna poprawka dzieje sie w srodku skryptu i nie wymaga
  # ponownego zatwierdzania hookow.
  $podmienione = $false
  $wzorPrzyp = $null
  foreach ($g in @($szablon.hooks.UserPromptSubmit)) {
    foreach ($hw in @($g.hooks)) {
      if ("$($hw.command)" -like "*przypomnienie.js*") { $wzorPrzyp = $hw }
    }
  }
  if ($wzorPrzyp -and ($s.hooks.PSObject.Properties.Name -contains "UserPromptSubmit")) {
    foreach ($grupa in @($s.hooks.UserPromptSubmit)) {
      foreach ($h in @($grupa.hooks)) {
        if (-not $h) { continue }
        $pol = "" + $h.command + " " + $h.commandWindows
        if ($pol -notlike "*przypomnienie.json*") { continue }
        if ($pol -like "*przypomnienie.js*") { continue }
        $h.command = $wzorPrzyp.command
        if ($h.PSObject.Properties.Name -contains "commandWindows") { $h.commandWindows = $wzorPrzyp.commandWindows }
        else { $h | Add-Member -NotePropertyName commandWindows -NotePropertyValue $wzorPrzyp.commandWindows -Force }
        $podmienione = $true
      }
    }
  }

  $dodane = @()
  if ($podmienione) { $dodane += "UserPromptSubmit" }
  foreach ($zdarzenie in $szablon.hooks.PSObject.Properties.Name) {
    $obecne = @()
    if ($s.hooks.PSObject.Properties.Name -contains $zdarzenie) { $obecne = @($s.hooks.$zdarzenie) }
    foreach ($grupa in @($szablon.hooks.$zdarzenie)) {
      $znacznik = $grupa.hooks[0].statusMessage
      if (-not $znacznik) { $znacznik = "MegaRuchacz" }
      if ($obecne.Count -gt 0 -and (($obecne | ConvertTo-Json -Depth 20 -Compress) -like "*$znacznik*")) { continue }
      $obecne += $grupa
      $dodane += $zdarzenie
    }
    if ($obecne.Count -eq 0) { continue }
    if ($s.hooks.PSObject.Properties.Name -contains $zdarzenie) { $s.hooks.$zdarzenie = @($obecne) }
    else { $s.hooks | Add-Member -NotePropertyName $zdarzenie -NotePropertyValue @($obecne) -Force }
  }
  if ($dodane.Count -eq 0) { return @() }
  Kopia-Zapasowa $plik $stempel
  Zapisz-Tekst $plik ($s | ConvertTo-Json -Depth 20)
  return $dodane
}

# Czesc codeksowa wdrozenia: role w .codex\agents\, zasady i ladunki hookow
# w .megaruchacz\, blok zasad w AGENTS.md. Nanosimy ja na tych samych zasadach
# co czesc dla Claude Code - z jednym wyjatkiem, ktory siedzi w Napraw-Hooki-Codex.
function Nanies-Poprawki-Codex($zrodlo, $projekt, $stempel) {
  $celCodex = Join-Path $projekt ".codex"
  $celMega  = Join-Path $projekt ".megaruchacz"
  # Bez .megaruchacz\ to nie jest wdrozenie dla Codeksa - nie zakladamy go sami.
  if (-not (Test-Path $celMega)) { return }
  $szablony = Join-Path $zrodlo "szablony-codex"
  if (-not (Test-Path $szablony)) { return }

  New-Item -ItemType Directory -Force -Path (Join-Path $celCodex "agents") | Out-Null
  foreach ($p in @(Get-ChildItem (Join-Path $szablony "agents\*.toml") -ErrorAction SilentlyContinue)) {
    [void](Odswiez $p.FullName (Join-Path $celCodex "agents\$($p.Name)") $stempel)
  }
  $zasadyZmienione = Odswiez (Join-Path $szablony "zasady-kierownika.md") (Join-Path $celMega "zasady-kierownika.md") $stempel
  [void](Odswiez (Join-Path $szablony "przypomnienie.json") (Join-Path $celMega "przypomnienie.json") $stempel)

  $wAgents = Odswiez-Agents $projekt (Join-Path $celMega "zasady-kierownika.md") $stempel
  if ($zasadyZmienione -or -not (Test-Path (Join-Path $celMega "zasady-sesja.json"))) {
    Zbuduj-Sesje-Codex $celMega $wAgents
  }
  Pilnuj-Sufitu-Sesji-Codex $celMega $celCodex

  # Nowy hook nie ruszy sam z siebie - zatwierdza go czlowiek. Cicha podmiana
  # pliku znaczylaby, ze uzytkownik czeka na cos, co nigdy nie wystartuje.
  $dodane = Napraw-Hooki-Codex $celCodex $zrodlo $projekt $stempel
  if ($dodane.Count -gt 0) {
    Mow ("MegaRuchacz: doszedl albo zmienil sie hook Codeksa (" + (($dodane | Select-Object -Unique) -join ", ") +
         ") w .codex\hooks.json - zatwierdz go w Codeksie poleceniem /hooks, inaczej nie wystartuje.")
  }

  # Slad w pliku wersji wdrozenia Codeksa - ten sam format "klucz: wartosc".
  $plikW = Join-Path $celMega "wersja.txt"
  if (Test-Path $plikW) {
    $w = Wersja-Narzedzia (Join-Path $zrodlo "ZMIANY.md")
    if ($w) {
      $stanC = Czytaj-Klucze $plikW
      $stanC["codex.wersja"] = $w
      $stanC["codex.data"] = (Get-Date -Format 'yyyy-MM-dd HH:mm')
      Zapisz-Klucze $plikW $stanC
    }
  }
}

# Nanosi poprawki na pliki nalezace do narzedzia. NIE rusza plikow stanu
# (worklog.md, mapa.md) - to praca uzytkownika.

# Sufit ladunku trzeba sprawdzac przy KAZDYM przebiegu, nie tylko po podbiciu
# wersji. Sprawdzone 2026-09-17: gdy wersja wdrozenia rowna sie zrodlowej,
# Pilnuj-Wersji przerywa petle i Nanies-Poprawki wcale nie leci - a sufit da sie
# zlamac bez zadnej aktualizacji, choćby recznym obnizeniem limitu w hooks.json.
function Pilnuj-Sufitu-Zawsze {
  if (-not $Projekt) { return }
  $celMega  = Join-Path $Projekt '.megaruchacz'
  $celCodex = Join-Path $Projekt '.codex'
  if (-not (Test-Path $celMega)) { return }
  Pilnuj-Sufitu-Sesji-Codex $celMega $celCodex
}

function Nanies-Poprawki($zrodlo, $projekt) {
  $stempel = Get-Date -Format "yyyyMMdd-HHmmss"
  $cel = Join-Path $projekt ".claude"
  New-Item -ItemType Directory -Force -Path (Join-Path $cel "agents") | Out-Null
  foreach ($p in @(Get-ChildItem (Join-Path $zrodlo ".claude\agents\*.md") -ErrorAction SilentlyContinue)) {
    [void](Odswiez $p.FullName (Join-Path $cel "agents\$($p.Name)") $stempel)
  }
  $zasadyZmienione = Odswiez (Join-Path $zrodlo "CLAUDE.md") (Join-Path $cel "megaruchacz-zasady.md") $stempel
  [void](Odswiez (Join-Path $zrodlo ".claude\mr-log.js") (Join-Path $cel "mr-log.js") $stempel)
  [void](Odswiez (Join-Path $zrodlo ".claude\orchestrator-reminder.json") (Join-Path $cel "orchestrator-reminder.json") $stempel)
  if ($zasadyZmienione -or -not (Test-Path (Join-Path $cel "megaruchacz-sesja.json"))) { Zbuduj-Sesje $cel }
  [void](Napraw-Hooki $cel $zrodlo $stempel)

  # Wdrozenie dla Codeksa idzie z tym samym modulem, wiec odswieza sie razem
  # z reszta. Osobne try: potkniecie na czesci codeksowej nie ma prawa zabrac
  # poprawek, ktore juz weszly po stronie Claude Code.
  try { Nanies-Poprawki-Codex $zrodlo $projekt $stempel }
  catch { Mow "MegaRuchacz: czesci codeksowej wdrozenia nie udalo sie odswiezyc ($($_.Exception.Message)) - zrobi to ponowne uruchomienie wdroz.ps1." }
}

# ------------------------------------------------- 0. swiezosc kopii narzedzia
# Wola gita w osobnym procesie, zeby dalo sie nalozyc limit czasu - straznik
# chodzi przy KAZDYM otwarciu okna i nie ma prawa czekac na gluche polaczenie.
# Zwraca .ok (kod wyjscia 0 i zdazyl) oraz .tekst (wyjscie bez bialych znakow).
function Wolaj-Gita([string]$argumenty, [int]$sekundy) {
  $wynik = [ordered]@{ ok = $false; tekst = "" }
  $wy = [System.IO.Path]::GetTempFileName()
  $bl = [System.IO.Path]::GetTempFileName()
  try {
    $p = Start-Process -FilePath "git" -ArgumentList $argumenty -NoNewWindow -PassThru `
           -RedirectStandardOutput $wy -RedirectStandardError $bl
    # Dotkniecie uchwytu MUSI byc przed czekaniem: bez tego Start-Process -PassThru
    # oddaje obiekt, w ktorym ExitCode zostaje $null nawet po zakonczeniu procesu,
    # wiec kazde wolanie wygladalo na nieudane i pobieranie nigdy nie ruszalo.
    # Sprawdzone 2026-09-16: bez tej linii ExitCode = $null, z nia = 0.
    $null = $p.Handle
    if (-not $p.WaitForExit($sekundy * 1000)) {
      try { $p.Kill() } catch { }
      return $wynik
    }
    $p.WaitForExit()
    if ($p.ExitCode -eq 0) {
      $wynik.ok = $true
      $t = [System.IO.File]::ReadAllText($wy)
      if ($t) { $wynik.tekst = $t.Trim() }
    }
  } catch { }
  finally { Remove-Item $wy, $bl -Force -ErrorAction SilentlyContinue }
  return $wynik
}

# Przewija katalog zrodlowy narzedzia do nowszej wersji, zanim ktokolwiek
# zacznie porownywac numery. To jest katalog roboczy uzytkownika, wiec pobranie
# jest tchorzliwe z zalozenia: przy niezapisanych zmianach albo rozjechanej
# historii NIE robi nic poza powiedzeniem o tym. Zadnego reset --hard, checkout
# -f, clean ani autostash - cudza praca jest wazniejsza niz swiezosc narzedzia.
# Brak gita, brak zdalnej i brak sieci to normalne sytuacje: cisza i jedziemy
# dalej z tym, co lezy na dysku.
function Odswiez-Zrodlo {
  # Do sieci zagladamy nie czesciej niz raz na $MINUT_MIEDZY_POBRANIAMI, osobno
  # dla kazdego katalogu zrodlowego - stad skrot sciezki w kluczu. W tle dlawika
  # nie ma z decyzji uzytkownika: jedynym wolajacym -Tlo jest hook SessionStart
  # Codeksa, a pobranie ma sie dziac przy KAZDYM starcie sesji, nie raz na godzine.
  $klucz = "z" + (Skrot $Zrodlo.ToLower())
  $stanP = Czytaj-Klucze $plikPobrania
  $kiedy = [datetime]::MinValue
  if (-not $Tlo -and $stanP[$klucz] -and [datetime]::TryParse($stanP[$klucz], [ref]$kiedy)) {
    if (([datetime]::Now - $kiedy).TotalMinutes -lt $MINUT_MIEDZY_POBRANIAMI) { return }
  }
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Notuj "zrodlo: nie ma gita na tej maszynie - pomijam pobranie"; return }

  $cyt = '"' + $Zrodlo.TrimEnd('\') + '"'
  $repo = Wolaj-Gita "-C $cyt rev-parse --is-inside-work-tree" $CZAS_GIT
  if (-not $repo.ok -or $repo.tekst -ne "true") {
    Notuj "zrodlo: $Zrodlo to nie repozytorium git - nie ma skad pobierac"
    return
  }

  # Od tej chwili proba byla prawdziwa - znacznik idzie na dysk niezaleznie od
  # wyniku, zeby nieudane pobranie nie powtarzalo sie przy kazdym oknie.
  $stanP[$klucz] = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  Zapisz-Klucze $plikPobrania $stanP

  $brudne = Wolaj-Gita "-C $cyt status --porcelain" $CZAS_GIT
  if (-not $brudne.ok) { Notuj "zrodlo: git nie odpowiedzial na pytanie o niezapisane zmiany"; return }
  if ($brudne.tekst) {
    Mow "MegaRuchacz: w $Zrodlo sa niezapisane zmiany - nie pobieram nowszej wersji narzedzia, pracuje na tej, ktora jest."
    return
  }

  # Galaz bez zdalnej (albo odpiety HEAD) - nie ma czego i skad pobierac.
  $zdalna = Wolaj-Gita "-C $cyt rev-parse --abbrev-ref --symbolic-full-name @{u}" $CZAS_GIT
  if (-not $zdalna.ok -or -not $zdalna.tekst) {
    Notuj "zrodlo: galaz w $Zrodlo nie ma zdalnej - nie ma skad pobierac"
    return
  }

  $plikZmian = Join-Path $Zrodlo "ZMIANY.md"
  $przedWersja = Wersja-Narzedzia $plikZmian

  # Zadnych pytan o haslo - okno sesji nie ma gdzie na nie odpowiedziec.
  # Limity czasu sa krotkie z premedytacja: caly hook ma 15 sekund, a start
  # okna nie moze na nas czekac. Gdy sie nie wyrobimy, wracamy po godzinie.
  $env:GIT_TERMINAL_PROMPT = "0"
  $pobrane = Wolaj-Gita "-C $cyt -c credential.interactive=never fetch --quiet" $CZAS_GIT_FETCH
  if (-not $pobrane.ok) { Notuj "zrodlo: fetch nie wyszedl (brak sieci albo dostepu) - zostaje przy tym, co na dysku"; return }

  $licznik = Wolaj-Gita "-C $cyt rev-list --left-right --count HEAD...@{u}" $CZAS_GIT
  if (-not $licznik.ok) { Notuj "zrodlo: git nie policzyl roznicy wobec zdalnej"; return }
  $czesci = $licznik.tekst -split '\s+'
  if ($czesci.Count -lt 2) { return }
  $nasze = [int]$czesci[0]   # commity lokalne, ktorych nie ma na zdalnej
  $zdalne = [int]$czesci[1]  # commity zdalne, ktorych nie mamy u siebie
  if ($zdalne -le 0) { Notuj "zrodlo: bez zmian, zdalna nie ma nic nowego"; return }

  if ($nasze -gt 0) {
    Mow "MegaRuchacz: historia w $Zrodlo rozjechala sie ze zdalna ($nasze lokalnych, $zdalne zdalnych) - nie scalam sam, zrob to recznie."
    return
  }

  # Tylko proste przewiniecie do przodu. Gdy git odmowi, zostajemy przy starym.
  $scalone = Wolaj-Gita "-C $cyt merge --ff-only @{u}" $CZAS_GIT_FETCH
  if (-not $scalone.ok) {
    Mow "MegaRuchacz: nie udalo sie przewinac $Zrodlo do nowszej wersji - pracuje na tej, ktora jest."
    return
  }

  # Cicha aktualizacja jest gorsza niz jej brak - zawsze jedna linia o tym,
  # co sie wlasnie zmienilo pod reka uzytkownika.
  $poWersja = Wersja-Narzedzia $plikZmian
  if ($przedWersja -and $poWersja -and $przedWersja -ne $poWersja) {
    Mow "MegaRuchacz: narzedzie podciagniete z gita - wersja ${przedWersja} -> ${poWersja} (co doszlo: $plikZmian)"
  } else {
    $slowo = if ($zdalne -eq 1) { "nowa zmiana" } else { "nowych zmian" }
    Mow "MegaRuchacz: narzedzie podciagniete z gita - $zdalne $slowo, numer wersji bez zmian (co doszlo: $plikZmian)"
  }
}

# --------------------------------------------------------- 1. zasady globalne
# Pliki instrukcji do pilnowania. Claude Code czyta ~\.claude\CLAUDE.md, Codex
# ~\.codex\AGENTS.md - i to jest jedyna droga zasad na maszynie bez Claude Code,
# bo Codex wczytuje AGENTS.md sam, bez zadnego hooka. Zapisuje wpisz-zasady.ps1
# (oba pliki naraz), tu tylko sprawdzamy, czy blok nadal tam siedzi i jest swiezy.
# Klucz to nazwa pola w pliku stanu - "blok" zostaje przy CLAUDE.md, zeby stare
# pliki stanu dalej sie zgadzaly.
function Cele-Zasad {
  $cele = @(
    [ordered]@{ nazwa = "Claude Code"; plik = $plikDomowy; klucz = "blok"; limit = 0 }
  )
  # Codeksa uznajemy za obecnego po jego katalogu domowym - tak samo jak robia
  # to wpisz-zasady.ps1 i instaluj-lore.ps1.
  if (Test-Path (Split-Path -Parent $plikCodex)) {
    $cele += [ordered]@{ nazwa = "Codex"; plik = $plikCodex; klucz = "blok.codex"; limit = $LIMIT_AGENTS }
  }
  # przecinek z premedytacja: bez niego lista jednoelementowa wraca jako goly
  # slownik, a nie tablica - ta sama pulapka, ktora zlapala rejestr modulow
  return ,$cele
}

function Pilnuj-Zasad {
  $oczekiwane = Tresc-Zrodla (Join-Path $Zrodlo "zasady-globalne.md")
  if (-not $oczekiwane) { return }
  $skrotZrodla = Skrot (Znormalizuj $oczekiwane)
  $stan = Czytaj-Klucze $plikStanu
  $cele = Cele-Zasad

  # Zgodne, gdy blok zawiera tresc ze zrodla, albo gdy oba skroty sa takie same
  # jak przy ostatnim udanym wpisie - to drugie ratuje nas, gdyby wpisz-zasady.ps1
  # skladalo blok inaczej, niz wyglada surowe zrodlo.
  $skroty = [ordered]@{ zrodlo = $skrotZrodla }
  $doNaprawy = @()
  foreach ($c in $cele) {
    $blok = Tresc-Bloku $c.plik
    $skrotBloku = Skrot (Znormalizuj $blok)
    $skroty[$c.klucz] = $skrotBloku
    $zgodne = $false
    if ($blok) {
      if ((Znormalizuj $blok).Contains((Znormalizuj $oczekiwane))) {
        $zgodne = $true
      } elseif ($stan["zrodlo"] -eq $skrotZrodla -and $stan[$c.klucz] -eq $skrotBloku) {
        $zgodne = $true
      }
    }
    if (-not $zgodne) {
      $powod = if ($blok) { "nieaktualne" } else { "zniknely" }
      $doNaprawy += [ordered]@{ nazwa = $c.nazwa; plik = $c.plik; powod = $powod }
    }
  }

  if ($doNaprawy.Count -eq 0) {
    $rozne = $false
    foreach ($k in $skroty.Keys) { if ($stan[$k] -ne $skroty[$k]) { $rozne = $true } }
    if ($rozne) { Dopisz-Klucze $plikStanu $skroty }
    Notuj ("zasady: aktualne (" + (($cele | ForEach-Object { $_.nazwa }) -join ", ") + ")")
    Pilnuj-Limitu $cele
    return
  }

  $opis = ($doNaprawy | ForEach-Object { "$($_.nazwa): $($_.powod)" }) -join ", "
  $wpisz = Join-Path $Zrodlo "narzedzia\wpisz-zasady.ps1"
  if (-not (Test-Path $wpisz)) {
    Mow "MegaRuchacz: zasady globalne wymagaja poprawki ($opis), a nie ma $wpisz - wpisz je recznie."
    return
  }
  $kod = 1
  try {
    $global:LASTEXITCODE = 0
    & $wpisz -Zrodlo $Zrodlo -KatalogDomowy $KatalogDomowy *>&1 | Out-Null
    $kod = $LASTEXITCODE
  } catch { $kod = 1 }

  # Po naprawie liczymy wszystko jeszcze raz z dysku - to, co wpisz-zasady.ps1
  # wypisalo o sobie, nie jest dowodem.
  $nowe = [ordered]@{ zrodlo = $skrotZrodla }
  $nadal = @()
  foreach ($c in $cele) {
    $blok = Tresc-Bloku $c.plik
    $nowe[$c.klucz] = Skrot (Znormalizuj $blok)
    if (-not $blok) { $nadal += $c.nazwa }
  }
  if ($kod -eq 0 -and $nadal.Count -eq 0) {
    Dopisz-Klucze $plikStanu $nowe
    Mow "MegaRuchacz: zasady globalne wymagaly poprawki ($opis) - wpisalem je z powrotem."
    Pilnuj-Limitu $cele
  } else {
    $ogon = ""
    if ($nadal.Count -gt 0) { $ogon = ", nadal bez bloku: " + ($nadal -join ", ") }
    Mow "MegaRuchacz: zasady globalne ($opis), a odtworzenie nie wyszlo (kod ${kod}${ogon}) - uruchom $wpisz recznie."
  }
}

# Plik ponad limitem czyta sie tylko do limitu - reszta zasad przepada po cichu.
# To nie jest nasza wina i nie mamy tego czym naprawic, ale mamy o tym powiedziec.
function Pilnuj-Limitu($cele) {
  foreach ($c in $cele) {
    if ($c.limit -le 0) { continue }
    if (-not (Test-Path $c.plik)) { continue }
    $ile = (Get-Item $c.plik).Length
    if ($ile -le $c.limit) { continue }
    Mow "MegaRuchacz: $($c.plik) ma $([int]($ile / 1024)) KiB, a $($c.nazwa) czyta najwyzej $([int]($c.limit / 1024)) KiB - koniec pliku sie nie wczyta, skroc go."
  }
}

# --------------------------------------------- 2. wersje modulow we wdrozeniu
# Kazdy modul ma wlasny stan pod "modul.<nazwa>.*" i jest aktualizowany osobno.
# Modul, ktorego uzytkownik nie chcial, przestaje nas obchodzic - nie wracamy
# do niego przy kazdym otwarciu okna.
function Pilnuj-Wersji {
  if (-not (Test-Path $plikWersji)) { return }   # to nie jest wdrozenie MegaRuchacza
  $stan = Czytaj-Klucze $plikWersji
  $plikZmian = Join-Path $Zrodlo "ZMIANY.md"
  $wZrodla = Wersja-Narzedzia $plikZmian
  if (-not $wZrodla) { return }
  try { $nowa = [version]$wZrodla } catch { return }
  $zmiana = $false

  foreach ($m in (Rejestr-Modulow)) {
    $k = "modul." + $m.nazwa
    $wdrozona = $stan["$k.wersja"]

    # Modul jeszcze niezainstalowany - proponujemy raz, z kosztem, i tyle.
    if (-not $wdrozona) {
      if ($stan["$k.status"] -eq "odrzucony") { continue }
      if ($stan["$k.zaproponowany"] -eq $wZrodla) { continue }
      $stan["$k.zaproponowany"] = $wZrodla
      $zmiana = $true
      Mow "MegaRuchacz: jest modul [$($m.nazwa)] - $($m.opis). Kosztuje: $($m.koszt)."
      Mow "  Wlaczyc: powershell -File $Zrodlo\wdroz.ps1   Odrzucic: powershell -File $PSCommandPath -Odrzuc $($m.nazwa)"
      continue
    }

    try { $stara = [version]$wdrozona } catch { continue }
    if ($nowa -le $stara) { continue }

    # Pierwsza cyfra = przebudowa lamiaca zgodnosc. Nic nie nanosimy sami.
    if ($nowa.Major -gt $stara.Major) {
      if ($stan["$k.zapowiedziane"] -eq $wZrodla) { continue }
      $stan["$k.zapowiedziane"] = $wZrodla
      $zmiana = $true
      Mow "MegaRuchacz: modul [$($m.nazwa)] w wersji $wZrodla lamie zgodnosc z wdrozona $wdrozona - nic nie nanioslem sam, wdroz recznie: powershell -File $Zrodlo\wdroz.ps1 (opis: $plikZmian)"
      continue
    }

    # Modul, ktorego aktualizacja moze kosztowac (pobieranie, harmonogram) -
    # sami go nie ruszamy, podajemy komende.
    if ($m.aktualizacja -ne "pliki") {
      if ($stan["$k.zapowiedziane"] -eq $wZrodla) { continue }
      $stan["$k.zapowiedziane"] = $wZrodla
      $zmiana = $true
      Mow "MegaRuchacz: modul [$($m.nazwa)] ma nowsza wersje $wZrodla (wdrozona $wdrozona) - zastosuj: powershell -File $Zrodlo\$($m.instalator) -Zrodlo $Zrodlo"
      continue
    }

    Nanies-Poprawki $Zrodlo $Projekt
    $stan["$k.wersja"] = $wZrodla
    $stan["$k.data"] = (Get-Date -Format 'yyyy-MM-dd HH:mm')
    # Czesc codeksowa jedzie razem z modulem, wiec jej stan tez sie przesuwa -
    # ale tylko tam, gdzie w ogole jest (klucz zaklada wdroz.ps1).
    if ($stan["codex.wersja"]) {
      $stan["codex.wersja"] = $wZrodla
      $stan["codex.data"] = $stan["$k.data"]
    }
    $zmiana = $true
    Mow "MegaRuchacz: modul [$($m.nazwa)] zaktualizowany $stara -> $wZrodla (co doszlo: $plikZmian)"

    # Druga cyfra = nowa funkcja. Poprawki weszly, ale funkcji nie wlaczamy sami -
    # potrafi kosztowac miejsce, pobieranie albo dostep do danych.
    if ($nowa.Minor -gt $stara.Minor -and $stan["$k.odrzucone"] -ne $wZrodla) {
      if ($stan["$k.zaproponowane"] -eq $wZrodla) {
        Mow "  Nowa funkcja z $wZrodla nadal niewlaczona - wlacz: powershell -File $Zrodlo\wdroz.ps1 ; odrzuc: powershell -File $PSCommandPath -Odrzuc $($m.nazwa)"
      } else {
        $stan["$k.zaproponowane"] = $wZrodla
        Mow "  Wersja $wZrodla przynosi nowa funkcje, ktorej NIE wlaczylem sam (za $plikZmian):"
        foreach ($l in (Wpis-Zmian $plikZmian $wZrodla | Select-Object -First 4)) { Mow "    $l" }
        Mow "  Wlaczyc: powershell -File $Zrodlo\wdroz.ps1   Odrzucic: powershell -File $PSCommandPath -Odrzuc $($m.nazwa)"
      }
    }
  }

  if ($zmiana) { Zapisz-Klucze $plikWersji $stan }
}

# ------------------------------------------------ 3. koszt pamieci i ucinanie
# Warunek postawiony wprost przez uzytkownika: przy KAZDYM otwarciu okna ma
# widziec, ile kosztuje pamiec agenta, i nic nie ma prawa uciac sie po cichu.
# Dlatego ta czesc jest jedyna, ktora odzywa sie takze wtedy, gdy wszystko gra.
#
# Rachunek liczy osobny skrypt (koszt-pamieci.ps1): siega do bazy Lore i kompiluje
# sobie typ pomocniczy, wiec trwa zauwazalnie dluzej niz caly reszta straznika,
# a caly hook ma kilkanascie sekund. Stad podzial: przy starcie okna CZYTAMY
# gotowa linie z pliku podrecznego, a przeliczenie idzie osobnym procesem, na
# ktory nikt nie czeka. Liczba sprzed kilku godzin w zupelnosci wystarcza.
#
# Umowa ze skryptem: "-Zwiezle" zwraca JEDNA linie, kod wyjscia 0 gdy nic nie
# jest ucinane, 1 gdy cokolwiek jest. Starsza wersja skryptu potrafi zwrocic co
# innego - bierzemy wtedy pierwsza niepusta linie i kod, jaki dostaniemy. Nic
# z tego nie ma prawa wywrocic otwarcia sesji.
function Policz-Koszt {
  $skrypt = Join-Path $Zrodlo "narzedzia\koszt-pamieci.ps1"
  if (-not (Test-Path $skrypt)) { return $null }
  $kod = 0
  $wy = @()
  try {
    $global:LASTEXITCODE = 0
    $wy = @(& $skrypt -KatalogDomowy $KatalogDomowy -Zwiezle 2>$null)
    $kod = $LASTEXITCODE
  } catch { Zanotuj-Wywrotke "liczenie rachunku za pamiec" $_; return $null }
  $linia = ""
  foreach ($l in $wy) {
    $t = "$l".Trim()
    if ($t) { $linia = $t; break }
  }
  if (-not $linia) { return $null }
  if ($null -eq $kod) { $kod = 0 }
  return [ordered]@{ linia = $linia; kod = [int]$kod }
}

# Rozbicie na pozycje - to samo liczenie, tylko dluzsze wyjscie. Idzie z -Projekt,
# bo bez niego nie da sie zmierzyc ladunku hooka Claude Code, czyli calego kubelka
# "przy kazdej wiadomosci". Blok jest wspolny dla maszyny (jak reszta pliku
# podrecznego): sciezki w nim sa wzgledne, a ladunki w projektach i tak sa te same.
function Policz-Rozbicie {
  $skrypt = Join-Path $Zrodlo "narzedzia\koszt-pamieci.ps1"
  if (-not (Test-Path $skrypt)) { return $null }
  try {
    $wy = @(& $skrypt -KatalogDomowy $KatalogDomowy -Projekt $Projekt -Rozbicie 2>$null)
  } catch { Zanotuj-Wywrotke "liczenie rozbicia rachunku" $_; return $null }
  $linie = @($wy | ForEach-Object { "$_".TrimEnd() } | Where-Object { $_ -ne "" })
  if ($linie.Count -lt 2) { return $null }
  return ($linie -join "`r`n")
}

function Zapisz-Rozbicie($blok) {
  if (-not $blok) { return }
  try { Zapisz-Tekst $plikRozbicia $blok } catch { Zanotuj-Wywrotke "zapis rozbicia rachunku" $_ }
}

# Zapis do pliku podrecznego. Znacznik dziennego meldunku przezywa przeliczenie -
# inaczej pelniejszy raport wracalby po kazdym odswiezeniu liczby.
function Zapisz-Koszt($wynik) {
  $stare = Czytaj-Klucze $plikKosztu
  $stan = [ordered]@{
    data  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    kod   = $wynik.kod
    linia = $wynik.linia
  }
  if ($stare["pelny"]) { $stan["pelny"] = $stare["pelny"] }
  if ($stare["proba"]) { $stan["proba"] = $stare["proba"] }
  try { Zapisz-Klucze $plikKosztu $stan } catch { Zanotuj-Wywrotke "zapis podrecznego rachunku" $_ }
}

# Odpala liczenie osobnym procesem i NIE czeka na wynik - to jest cala sztuczka,
# dzieki ktorej start okna kosztuje tyle co odczyt jednego pliku. conhost
# --headless, zeby nikomu nie mrugnela konsola; gdyby go nie bylo, zwykly
# powershell w ukrytym oknie.
function Odswiez-Koszt-W-Tle {
  $skrypt = Join-Path $Zrodlo "narzedzia\koszt-pamieci.ps1"
  if (-not (Test-Path $skrypt)) { return }

  # Znacznik proby idzie na dysk PRZED startem - takze wtedy, gdy start sie nie
  # uda. Liczenie, ktore sie wywraca, ma wracac co kwadrans, a nie co okno.
  $stan = Czytaj-Klucze $plikKosztu
  $stan["proba"] = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  try { Zapisz-Klucze $plikKosztu $stan } catch { Zanotuj-Wywrotke "zapis znacznika proby liczenia" $_ }

  $ogon = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $PSCommandPath +
          '" -PoliczKoszt -Zrodlo "' + $Zrodlo + '" -KatalogDomowy "' + $KatalogDomowy + '"'
  try {
    Start-Process -FilePath "conhost.exe" -ArgumentList ("--headless powershell.exe " + $ogon) `
      -WindowStyle Hidden -ErrorAction Stop | Out-Null
    return
  } catch { }   # conhost sie nie udal - zaraz probujemy zwyklym powershellem
  try { Start-Process -FilePath "powershell.exe" -ArgumentList $ogon -WindowStyle Hidden | Out-Null }
  catch { Zanotuj-Wywrotke "start liczenia rachunku w tle" $_ }
}

# Jedna linia o koszcie pamieci - zawsze, niezaleznie od tego, czy cokolwiek
# innego wymaga uwagi. Gdy cos jest ucinane (kod 1), linia idzie jako wyrozniony
# alarm, a nie dopisek w cudzym meldunku: po cichu ucinac sie nie ma prawa.
function Zglos-Koszt {
  if ($Tlo) {
    # W tle nikt nie czeka na otwarcie okna, wiec liczymy na miejscu - i przy
    # okazji odswiezamy liczbe oraz rozbicie, z ktorych skorzystaja nastepne okna.
    $swieze = Policz-Koszt
    if ($swieze) { Zapisz-Koszt $swieze }
    Zapisz-Rozbicie (Policz-Rozbicie)
  }

  $stan = Czytaj-Klucze $plikKosztu
  $linia = $stan["linia"]
  $kod = 0
  if ($stan["kod"] -match '^\d+$') { $kod = [int]$stan["kod"] }

  $kiedy = [datetime]::MinValue
  $godzin = [double]::MaxValue
  if ([datetime]::TryParse($stan["data"], [ref]$kiedy)) {
    $godzin = ([datetime]::Now - $kiedy).TotalHours
  }

  # Kiedy ostatnio w ogole PROBOWALISMY policzyc - stad wiadomo, czy wypada
  # startowac kolejny proces, czy poprzedni dopiero co poszedl.
  $probowano = [datetime]::MinValue
  $odProby = [double]::MaxValue
  if ([datetime]::TryParse($stan["proba"], [ref]$probowano)) {
    $odProby = ([datetime]::Now - $probowano).TotalMinutes
  }

  $trzeba = ($godzin -gt $GODZIN_MIEDZY_KOSZTAMI)
  if (-not $Tlo -and $trzeba -and $odProby -gt $MINUT_MIEDZY_PROBAMI) { Odswiez-Koszt-W-Tle }

  if (-not $linia) {
    # Pierwsze uruchomienie: nie ma jeszcze czego pokazac, ale cisza wygladalaby
    # jak "nic sie nie dzieje", wiec mowimy wprost, ze liczba dopiero powstaje.
    if ($Tlo) { Notuj "koszt pamieci: nie ma jeszcze policzonej liczby" }
    else       { Write-Host "MegaRuchacz: rachunek za pamiec agenta licze wlasnie w tle - liczba bedzie przy nastepnym otwarciu okna." }
    return
  }

  $ogon = ""
  if ($godzin -gt $GODZIN_KOSZT_STARY) {
    $ogon = " (liczba z $(Get-Date $kiedy -Format 'yyyy-MM-dd HH:mm'), swiezsza bedzie za chwile)"
  }

  # Kod 1 znaczy "cos jest nie tak", ale nie zawsze "cos jest ucinane" - moze to
  # byc sam przekroczony prog (np. koszt cyklu wiedzy). Naglowek o ucinanych
  # zasadach przy zwyklym progu bylby po prostu nieprawda, wiec rozdzielamy to
  # po tresci linii: ucinanie koszt-pamieci.ps1 nazywa slowem UCINANE.
  if ($kod -ne 0 -and $linia -like "*UCINANE:*") {
    Mow "!!! MegaRuchacz: CZESC ZASAD NIE DOCIERA DO AGENTA !!!"
    Mow "    ${linia}${ogon}"
    Mow "    Dopoki tego nie skrocisz, agent pracuje bez ucietego kawalka - pelny rachunek: powershell -File $Zrodlo\narzedzia\koszt-pamieci.ps1"
  } elseif ($kod -ne 0) {
    Mow "MegaRuchacz: ${linia}${ogon}"
    Mow "    Nic nie jest ucinane - to przekroczony prog. Pelny rachunek: powershell -File $Zrodlo\narzedzia\koszt-pamieci.ps1"
  } else {
    Mow "MegaRuchacz: ${linia}${ogon}"
  }
}

# To samo pod Codeksem. Codex nie wciaga wyjscia hooka do rozmowy tak jak Claude
# Code - chce ladunku "hookSpecificOutput.additionalContext", wiec ta sama liczba
# musi wyjsc JSON-em, z osobnego hooka SessionStart. Osobnego, bo ten od
# samoaktualizacji chodzi w tle i celowo nie mowi do modelu ani slowa.
#
# Tu NIC sie nie liczy: czytamy gotowa linie z pliku podrecznego (liczenie trwa
# sekundy i opoznialoby start sesji), a odswieza ja hook bezobslugowy - w trybie
# -Tlo Zglos-Koszt przelicza rachunek przy kazdym przebiegu. Gdy liczby jeszcze
# nie ma albo jest stara, mowimy to wprost: cisza wygladalaby jak "nic nie kosztuje".
#
# Ucinanie (kod inny niz 0) idzie na POCZATEK linii, slowem UWAGA - alarm
# schowany w srodku zdania jest alarmem, ktorego nikt nie zauwaza.
function Wypisz-Koszt-Codex {
  $stan = Czytaj-Klucze $plikKosztu
  $linia = $stan["linia"]
  $kod = 0
  if ($stan["kod"] -match '^\d+$') { $kod = [int]$stan["kod"] }

  if (-not $linia) {
    $tresc = "MegaRuchacz: rachunek za pamiec agenta nie jest jeszcze policzony - liczba bedzie przy nastepnym otwarciu sesji."
  } else {
    $kiedy = [datetime]::MinValue
    $godzin = [double]::MaxValue
    if ([datetime]::TryParse($stan["data"], [ref]$kiedy)) {
      $godzin = ([datetime]::Now - $kiedy).TotalHours
    }
    $ogon = ""
    if ($godzin -gt $GODZIN_KOSZT_STARY -and $kiedy -gt [datetime]::MinValue) {
      $ogon = " (liczba z $(Get-Date $kiedy -Format 'yyyy-MM-dd HH:mm'), swiezsza bedzie za chwile)"
    }
    # tak samo jak w Zglos-Koszt: kod 1 bez slowa UCINANE to przekroczony prog,
    # a nie uciete zasady - nazywanie tego ucinaniem byloby klamstwem
    if ($kod -ne 0 -and $linia -like "*UCINANE:*") { $tresc = "UWAGA: czesc zasad NIE DOCIERA do agenta - ${linia}${ogon}" }
    elseif ($kod -ne 0) { $tresc = "UWAGA: ${linia}${ogon}" }
    else                { $tresc = "MegaRuchacz: ${linia}${ogon}" }
  }

  # Alarmy ida PRZED rachunkiem: ten ladunek ma wlasny sufit (additionalContextLimit
  # w .codex\hooks.json) i jest ucinany od konca, wiec to, co najwazniejsze, musi
  # stac na poczatku. Tutaj tez odbieramy wywrotki z trybu -Tlo: na maszynie
  # z samym Codeksem nie ma innego miejsca, w ktorym ktokolwiek by je przeczytal.
  $przed = @()
  try {
    $wywrotki = @(Odbierz-Wywrotki)
    if ($wywrotki.Count -gt 0) {
      # Sufit ladunku to 1000 znakow, wiec do modelu ida najwyzej dwie wywrotki,
      # i to przyciete - komplet lezy w dzienniku trybu bezobslugowego.
      $krotkie = @()
      foreach ($w in @($wywrotki | Select-Object -First 2)) {
        if ("$w".Length -gt 120) { $krotkie += "$w".Substring(0, 120) + "..." } else { $krotkie += "$w" }
      }
      $ogonek = ""
      if ($wywrotki.Count -gt 2) { $ogonek = " (oraz $($wywrotki.Count - 2) innych - komplet w ${plikDziennika})" }
      $przed += ("UWAGA: przy poprzednim przebiegu straznika wywrocilo sie: " + ($krotkie -join "; ") + "${ogonek}.")
    }
    $ciszaClaude = Cisza-Claude-Linia
    if ($ciszaClaude) { $przed += $ciszaClaude }
  } catch { }   # alarm, ktory sam sie wywraca, nie ma prawa zabrac rachunku
  if ($przed.Count -gt 0) { $tresc = ($przed -join " ") + " " + $tresc }

  # ConvertTo-Json, a nie sklejanie tekstu - linia potrafi miec cudzyslow albo
  # ukosnik i recznie zescapowany ladunek przestalby byc JSON-em.
  $ladunek = [ordered]@{
    hookSpecificOutput = [ordered]@{
      hookEventName     = "SessionStart"
      additionalContext = $tresc
    }
  }
  Write-Output ($ladunek | ConvertTo-Json -Depth 4 -Compress)
}

function Liczba-Ludzka($n) {
  # separator tysiecy na sztywno spacja - tak samo jak w koszt-pamieci.ps1
  return ([long]$n).ToString("#,0", [Globalization.CultureInfo]::InvariantCulture).Replace(",", " ")
}

function Ile-Wywolan($n) {
  $reszta = $n % 10
  $setka  = $n % 100
  if ($n -eq 1) { return "1 wywolanie" }
  if (($reszta -ge 2) -and ($reszta -le 4) -and (($setka -lt 12) -or ($setka -gt 14))) { return "$n wywolania" }
  return "$n wywolan"
}

# Koszt cyklu wiedzy - JEDNA linia, raz na dobe, w dziennym meldunku. To inny
# rodzaj kosztu niz rachunek za pamiec wyzej: tamten to tekst doklejany do
# rozmowy, ten to prawdziwe wywolanie modelu, ktore cykl dzienny placi za
# przeczytanie wczorajszych rozmow. Dlatego liczby nie sa sumowane.
#
# Plik pisze sam cykl (<dom>\.claude\wiedza\.koszt-cyklu.txt, format
# "klucz: wartosc"). Brak pliku albo pomiar sprzed kilku dni mowimy WPROST:
# cisza w tym miejscu znaczylaby "cykl chodzi i nic nie kosztuje", a prawda
# bylaby wtedy odwrotna - cykl w ogole nie chodzi i wiedza nie przyrasta.
function Zglos-Koszt-Cyklu {
  $plik = Join-Path $KatalogDomowy ".claude\wiedza\.koszt-cyklu.txt"
  if (-not (Test-Path $plik)) {
    Write-Host "    cykl wiedzy: kosztu jeszcze nie policzyl - jesli cykl chodzi, liczba bedzie po jego najblizszym przebiegu"
    return
  }
  $k = Czytaj-Klucze $plik

  # Wiek liczymy z klucza "data" (dzien, ktorego dotycza liczby), a dopiero
  # w ostatecznosci z daty pliku - plik moze byc przepisany bez nowej pracy.
  $data = [datetime]::MinValue
  $wiek = $null
  if ([datetime]::TryParse($k["data"], [ref]$data)) {
    $wiek = [int]([datetime]::Today - $data.Date).TotalDays
  } else {
    try { $wiek = [int]([datetime]::Now - (Get-Item $plik).LastWriteTime).TotalDays } catch { $wiek = $null }
  }

  if (($null -ne $wiek) -and ($wiek -gt $DNI_KOSZT_CYKLU_STARY)) {
    $kiedy = $k["data"]
    if (-not $kiedy) { $kiedy = "dawno" }
    Write-Host "    cykl wiedzy: ostatni koszt z ${kiedy} (${wiek} dni temu) - cykl od tego czasu nie wylawial faktow, wiec nie chodzi"
    return
  }

  $kiedy = "ostatnio"
  if ($wiek -eq 0)    { $kiedy = "dzis" }
  elseif ($wiek -eq 1) { $kiedy = "wczoraj" }
  elseif ($k["data"]) { $kiedy = "z dnia $($k['data'])" }

  $tokeny = "nie wiadomo ile"
  if ($k["tokeny"] -match '^\d+$') { $tokeny = "~$(Liczba-Ludzka ([long]$k['tokeny']))" }
  $zrodlo = ""
  if ($k["tokeny_zrodlo"]) { $zrodlo = " ($($k['tokeny_zrodlo']))" }

  $czesci = @()
  if ($k["wywolania"] -match '^\d+$') {
    $opisW = Ile-Wywolan ([int]$k["wywolania"])
    if ($k["narzedzie"]) { $opisW = "$opisW $($k['narzedzie'])" }
    $czesci += $opisW
  }
  if ($k["fakty"] -match '^\d+$') { $czesci += "$($k['fakty']) faktow" }
  if ($k["poprzedni.tokeny"] -match '^\d+$') {
    $czesci += "poprzednio ~$(Liczba-Ludzka ([long]$k['poprzedni.tokeny']))"
  }
  $ogon = ""
  if ($czesci.Count -gt 0) { $ogon = " (" + ($czesci -join ", ") + ")" }

  Write-Host "    cykl wiedzy ${kiedy}: ${tokeny} tokenow${zrodlo}${ogon} - to prawdziwe wywolanie modelu, osobno od liczb wyzej"
}

# Raz na dobe, przy pierwszym otwarciu okna tego dnia, pelniejszy meldunek -
# uzytkownik chcial byc informowany CODZIENNIE, a nie tylko wtedy, gdy sam
# zajrzy do pliku. Zrodlem jest raport zadania LoreKoszt z Harmonogramu
# (<dom>\.claude\wiedza\koszt-ostatni.txt). Gdy tego zadania nie ma albo nie
# chodzi, mowimy i o tym: cisza wygladalaby jak "wszystko policzone".
function Zglos-Koszt-Dzienny {
  $stan = Czytaj-Klucze $plikKosztu
  $dzis = (Get-Date -Format 'yyyy-MM-dd')
  if ($stan["pelny"] -eq $dzis) { return }
  # Znacznik idzie na dysk PRZED wypisaniem - potkniecie ma znaczyc jeden
  # pominiety meldunek, a nie meldunek przy kazdym oknie do konca dnia.
  $stan["pelny"] = $dzis
  try { Zapisz-Klucze $plikKosztu $stan } catch { Zanotuj-Wywrotke "znacznik dziennego rachunku" $_ }

  # Rozbicie na pozycje - to jest ten meldunek, o ktory uzytkownik poprosil: przy
  # kazdej pozycji ma stac, GDZIE ona siedzi i DO CZEGO jest doklejana, bo sama suma
  # nie mowi, co skrocic. Gotowy blok lezy w pliku podrecznym (liczy go w tle
  # koszt-pamieci.ps1 -Rozbicie), wiec otwarcie sesji na nic nie czeka.
  if (Pokaz-Rozbicie) { return }

  # Rozbicia jeszcze nie ma (pierwsze uruchomienie) - zostaje to, co bylo:
  # wyciag z dziennego raportu zadania LoreKoszt i osobna linia o koszcie cyklu.
  $plik = Join-Path $KatalogDomowy ".claude\wiedza\koszt-ostatni.txt"
  $skrypt = Join-Path $Zrodlo "narzedzia\koszt-pamieci.ps1"
  if (-not (Test-Path $plik)) {
    Write-Host "MegaRuchacz: rozbicie rachunku za pamiec licze wlasnie w tle - bedzie przy nastepnym otwarciu okna."
    # koszt cyklu to osobny plik i osobny rodzaj kosztu - brak jednego rachunku
    # nie ma prawa zabrac drugiego
    try { Zglos-Koszt-Cyklu } catch { Zanotuj-Wywrotke "koszt cyklu wiedzy" $_ }
    return
  }

  $dni = [int]([datetime]::Now - (Get-Item $plik).LastWriteTime).TotalDays
  Write-Host "MegaRuchacz - dzienny rachunek za pamiec (z $((Get-Item $plik).LastWriteTime.ToString('yyyy-MM-dd HH:mm'))):"

  # Z pelnego raportu bierzemy tylko to, co jest liczba albo ostrzezeniem -
  # reszta to objasnienia, ktore uzytkownik przeczyta w pliku, jesli zechce.
  $wybrane = @()
  $raport = Czytaj-Tekst $plik
  if ($raport) {
    foreach ($l in (($raport -replace "`r`n", "`n") -split "`n")) {
      $t = $l.Trim()
      if (-not $t) { continue }
      if ($t -like "Kazda Twoja wiadomosc:*" -or $t -like "Start sesji:*" -or $t -like "UWAGA *") {
        $wybrane += $t
      }
    }
  }
  if ($wybrane.Count -eq 0) { $wybrane += "nic nie wymagalo uwagi" }
  foreach ($t in ($wybrane | Select-Object -First 6)) { Write-Host "    $t" }
  try { Zglos-Koszt-Cyklu } catch { Zanotuj-Wywrotke "koszt cyklu wiedzy" $_ }
  if ($dni -gt 2) {
    Write-Host "    Ten raport ma $dni dni - zadanie LoreKoszt nie chodzi. Zaloz je od nowa: powershell -File $skrypt -ZalozZadanie"
  }
  Write-Host "    Caly rachunek: $plik"
}

# Gotowy blok rozbicia z pliku podrecznego. Wypisujemy go slowo w slowo i prosimy
# model, zeby przepisal go uzytkownikowi: wyjscie hooka trafia do KONTEKSTU MODELU,
# a nie na ekran, wiec bez tej prosby uzytkownik nie zobaczy z tego ani linii.
# $false = nie ma czego pokazac (pierwsze uruchomienie albo liczenie sie wywrocilo).
function Pokaz-Rozbicie {
  $blok = Czytaj-Tekst $plikRozbicia
  if (-not $blok) { return $false }
  $wiek = [double]::MaxValue
  try { $wiek = ([datetime]::Now - (Get-Item $plikRozbicia).LastWriteTime).TotalDays } catch { }
  Write-Host "MegaRuchacz: przepisz uzytkownikowi ponizszy blok w pierwszej odpowiedzi, bez zmian i bez komentarza."
  foreach ($l in (($blok -replace "`r`n", "`n") -split "`n")) { Write-Host $l }
  if ($wiek -gt 7) {
    Write-Host "    (liczby z $((Get-Item $plikRozbicia).LastWriteTime.ToString('yyyy-MM-dd')) - swiezsze beda po przeliczeniu w tle)"
  }
  return $true
}

# ------------------------------------------------- 4. cykl wiedzy przy pierwszej sesji
# Cykl wiedzy rusza TUTAJ - przy pierwszej sesji danego dnia, a nie o sztywnej
# godzinie z Harmonogramu (do 2026-09-17 bylo to zadanie LoreCykl). Warunek jest
# doslownie taki: data ostatniego przebiegu jest inna niz dzisiejsza. Dni, w ktorych
# komputer byl wylaczony, po prostu nie istnieja: praca we wtorek, dwa dni wolnego,
# piatek 15:00 - i cykl bierze wtedy wszystko od wtorku. Drugie i trzecie okno tego
# samego dnia juz go nie odpala.
#
# Sesja NA NIC TU NIE CZEKA: hook ma kilkanascie sekund, a cykl trwa minuty, wiec
# idzie osobnym, odczepionym procesem (ten sam wzorzec, co Odswiez-Koszt-W-Tle).
# Jedyny koszt po tej stronie to odczyt stanu kolejki - liczby, bez wolania modelu,
# zmierzone 0,4 s - i robimy go najwyzej raz na dobe.
function Ruszaj-Cykl {
  $skrypt = Join-Path $Zrodlo "narzedzia\cykl-dzienny.ps1"
  if (-not (Test-Path $skrypt)) { return }
  # bez modulu pamieci nie ma czego czytac - i nie ma po co budzic procesu
  if (-not (Test-Path (Join-Path $Zrodlo "lore\pyproject.toml"))) { return }

  $katWiedzy = Join-Path $KatalogDomowy ".claude\wiedza"
  $dzis = Get-Date -Format 'yyyy-MM-dd'
  $stanCyklu = Czytaj-Klucze (Join-Path $katWiedzy ".cykl-stan")
  # "odlozony" znaczy, ze przebiegu w ogole nie bylo (brak sieci, wylogowanie) -
  # to nie jest dzisiejsza praca, wiec wolno sprobowac jeszcze raz.
  if (($stanCyklu["data"] -eq $dzis) -and ($stanCyklu["status"] -ne "odlozony")) { return }

  # Drugie okno otwarte minute po pierwszym - cykl juz pracuje, nie dubluj meldunku.
  # (Przed samym podwojnym przebiegiem broni zamek w cykl-dzienny.ps1.)
  $postep = Czytaj-Klucze (Join-Path $katWiedzy ".cykl-postep")
  if ($postep["stan"] -eq "pracuje") {
    $kiedyPostep = [datetime]::MinValue
    if ([datetime]::TryParse($postep["czas"], [ref]$kiedyPostep) -and
        (([datetime]::Now - $kiedyPostep).TotalHours -lt 3)) { return }
  }

  # Czy jest w ogole co robic. Przebieg probny wylawiania modelu nie wola,
  # znacznika nie przesuwa i oddaje same liczby.
  $kawalki = $null
  $przebiegi = $null
  $wyciagnij = Join-Path $Zrodlo "narzedzia\wyciagnij-fakty.ps1"
  if (Test-Path $wyciagnij) {
    try {
      $global:LASTEXITCODE = 0
      # *>&1: wylawianie pisze przez Write-Host, a to w tym samym procesie wyladowaloby
      # w wyjsciu hooka, czyli w kontekscie modelu. Zbieramy wszystko i czytamy liczby.
      $wy = (& $wyciagnij -Zrodlo $Zrodlo -Kolejka *>&1 | Out-String)
      if ($LASTEXITCODE -eq 0) {
        $k = Klucze-Z-Tekstu $wy
        if ($k["kolejka.kawalki"]   -match '^\d+$') { $kawalki   = [int]$k["kolejka.kawalki"] }
        if ($k["kolejka.przebiegi"] -match '^\d+$') { $przebiegi = [int]$k["kolejka.przebiegi"] }
      }
    } catch { }   # nie udalo sie zapytac - decyzje podejmuje wtedy sam cykl
  }
  # Pusta kolejka to jedyny powod, zeby nie ruszac. Kolejki, ktorej nie umiemy
  # odczytac, nie udajemy: wtedy cykl idzie i sam powie, co mu przeszkadza.
  if (($null -ne $kawalki) -and ($kawalki -le 0)) { return }

  $ogon = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $skrypt +
          '" -Zrodlo "' + $Zrodlo + '" -KatalogDomowy "' + $KatalogDomowy + '"'
  $poszlo = $false
  try {
    Start-Process -FilePath "conhost.exe" -ArgumentList ("--headless powershell.exe " + $ogon) `
      -WindowStyle Hidden -ErrorAction Stop | Out-Null
    $poszlo = $true
  } catch { }
  if (-not $poszlo) {
    try {
      Start-Process -FilePath "powershell.exe" -ArgumentList $ogon -WindowStyle Hidden | Out-Null
      $poszlo = $true
    } catch { Zanotuj-Wywrotke "start cyklu wiedzy" $_ }
  }
  if (-not $poszlo) { return }

  # Jedna linia o tym, co sie wlasnie zaczelo. Ile to kosztowalo, powie meldunek
  # koncowy przy najblizszej wiadomosci (narzedzia\przypomnienie.js).
  $skad = "od ostatniego odczytu"
  $znacznik = Join-Path $katWiedzy ".ostatnie-wyciaganie"
  if (Test-Path $znacznik) {
    $tekst = (Czytaj-Tekst $znacznik)
    $data = [datetime]::MinValue
    if ($tekst -and [datetime]::TryParse($tekst.Trim(), [Globalization.CultureInfo]::InvariantCulture,
          [Globalization.DateTimeStyles]::RoundtripKind, [ref]$data)) {
      $skad = "od $($data.ToLocalTime().ToString('yyyy-MM-dd HH:mm'))"
    }
  }
  $ile = @()
  if ($null -ne $kawalki)   { $ile += "$kawalki kawalkow rozmow" }
  if ($null -ne $przebiegi) { $ile += "$przebiegi porcji" }
  $opisIle = ""
  if ($ile.Count -gt 0) { $opisIle = " - " + ($ile -join ", ") }
  Mow "MegaRuchacz: czytam rozmowy ${skad}${opisIle}. Potrwa kilka minut, koszt podam po zakonczeniu."
}

# ------------------------------------------------------------------ przebieg
# Cokolwiek by sie tu nie stalo, start sesji ma sie udac - stad kod 0 na koncu.
try {
  if (-not (Test-Path $Zrodlo)) { exit 0 }   # zrodlo przeniesione albo skasowane - milczymy

  # Odmowa jest zapamietywana per modul - o to samo nie pytamy drugi raz.
  # Wrocic do tego mozna instalatorem, kiedy uzytkownik sam zechce.
  if ($Odrzuc) {
    if (-not (Test-Path $plikWersji)) { Write-Host "MegaRuchacz: nie ma $plikWersji - to nie jest wdrozony projekt."; exit 0 }
    $nazwy = @(Rejestr-Modulow | ForEach-Object { $_.nazwa })
    if (-not ($nazwy -contains $Odrzuc)) {
      Write-Host ("MegaRuchacz: nie znam modulu [$Odrzuc]. Sa: " + ($nazwy -join ", "))
      exit 0
    }
    $stan = Czytaj-Klucze $plikWersji
    $k = "modul.$Odrzuc"
    if ($stan["$k.wersja"]) {
      # modul jest wdrozony - odmowa dotyczy nowej funkcji w nim
      $co = $stan["$k.zaproponowane"]
      if (-not $co) { $co = Wersja-Narzedzia (Join-Path $Zrodlo "ZMIANY.md") }
      $stan["$k.odrzucone"] = $co
      $stan.Remove("$k.zaproponowane")
      Write-Host "MegaRuchacz: zapamietane - nowa funkcja z $co w module [$Odrzuc] zostaje niewlaczona."
    } else {
      $stan["$k.status"] = "odrzucony"
      $stan["$k.data"] = (Get-Date -Format 'yyyy-MM-dd HH:mm')
      $stan.Remove("$k.zaproponowany")
      Write-Host "MegaRuchacz: zapamietane - modul [$Odrzuc] zostaje niezainstalowany."
    }
    Zapisz-Klucze $plikWersji $stan
    Write-Host "  Wrocic mozna instalatorem: powershell -File $Zrodlo\wdroz.ps1"
    exit 0
  }

  # Tryb pomocniczy - policz rachunek za pamiec i odloz gotowa linie do pliku
  # podrecznego. Startuje go straznik sam, osobnym procesem, wiec nikt tu nie
  # czeka i nikt nie czyta: zadnego wypisywania, zadnych innych sprawdzen.
  if ($PoliczKoszt) {
    $w = Policz-Koszt
    if ($w) { Zapisz-Koszt $w }
    # Rozbicie na pozycje liczy sie przy tej samej okazji: to ten sam skrypt,
    # a blok ma byc gotowy do wypisania, gdy nastanie nowy dzien.
    Zapisz-Rozbicie (Policz-Rozbicie)
    exit 0
  }

  # Ladunek dla Codeksa - sama linia o koszcie pamieci i nic wiecej. Zadnego
  # pobierania, pilnowania zasad ani liczenia: ten hook ma oddac jedna linie
  # od razu, a cala reszta roboty siedzi w hooku bezobslugowym (-Tlo).
  if ($KosztCodex) {
    # Slad "bylem tu" idzie PRZED ladunkiem: to jedyny dowod, ze hooki Codeksa
    # w ogole chodza, i nie ma prawa zalezec od tego, co bedzie dalej.
    Zapisz-Obecnosc "codex"
    Wypisz-Koszt-Codex
    exit 0
  }

  # Tryb bezobslugowy - na maszynie z samym Codeksem to JEDYNA droga aktualizacji,
  # bo wola go hook SessionStart. Dlatego robimy tu wszystko, co nanosi zmiany:
  # pobranie nowszej wersji narzedzia, pliki zasad i poprawki na wdrozenie.
  # Komunikaty ida przez Mow, wiec propozycje i ostrzezenia nie gina - laduja
  # w dzienniku, bo tutaj nie ma ekranu, na ktory dalo by sie je wypisac.
  # Poczekalnia faktow i meldunek o cyklu zostaja poza tym trybem: to prosby
  # do czlowieka, a nie zmiany na dysku, wiec w dzienniku nikt ich nie przeczyta.
  # Rachunek za pamiec jest tu wyjatkiem i idzie do dziennika z premedytacja:
  # jedna linia z data przy kazdym przebiegu to jedyny zapis tego, jak ten koszt
  # rosnie w czasie - z niego widac trend, ktorego pojedyncze okno nie pokaze.
  if ($Tlo) {
    try { Odswiez-Zrodlo } catch { Zanotuj-Wywrotke "odswiezanie zrodla" $_ }
    try { Pilnuj-Zasad }   catch { Zanotuj-Wywrotke "pilnowanie zasad" $_ }
    try { Pilnuj-Sufitu-Zawsze } catch { Zanotuj-Wywrotke "pilnowanie sufitu ladunku" $_ }
    try { Pilnuj-Wersji }  catch { Zanotuj-Wywrotke "pilnowanie wersji wdrozenia" $_ }
    try { Zglos-Koszt }    catch { Zanotuj-Wywrotke "rachunek za pamiec" $_ }
    # Cykl wiedzy takze tutaj: na maszynie z samym Codeksem ten hook jest jedynym,
    # ktory w ogole chodzi przy starcie sesji. Ze jest w robocie, uzytkownik zobaczy
    # przy pierwszej wiadomosci - z linii stanu doklejanej przez przypomnienie.js.
    try { Ruszaj-Cykl }    catch { Zanotuj-Wywrotke "start cyklu wiedzy" $_ }
    # Najpierw dziennik (zbiera tez wywrotki), potem znacznik obecnosci wraz
    # z nimi - w tej kolejnosci, bo potkniecie samego dziennika tez ma sie zapisac.
    Dopisz-Dziennik
    Zapisz-Obecnosc "tlo"
    exit 0
  }

  # Fakty wylowione z rozmow czekaja w poczekalni na decyzje uzytkownika.
  # Bez tego powiadomienia nikt tam nie zaglada i cala robota idzie do kosza.
  function Zglos-Kandydatow {
    $plik = Join-Path $KatalogDomowy ".claude\wiedza\kandydaci.md"
    if (-not (Test-Path $plik)) { return }
    $ile = @(Select-String -Path $plik -Pattern '^\s*-\s*\[\s*\]' -AllMatches).Count
    if ($ile -lt 1) { return }
    $slowo = if ($ile -eq 1) { "fakt czeka" } else { "faktow czeka" }
    Write-Host "MegaRuchacz: $ile $slowo na Twoja decyzje - powiedz 'pokaz fakty', zeby je przejrzec."
  }

  # Jedna linia o dziennym cyklu pamieci (cykl-dzienny.ps1) - i tylko wtedy, gdy cos
  # wymaga uwagi: cykl sie nie udal albo zostala zaleglosc. Przy czystym stanie cisza,
  # tak jak reszta straznika. O koszcie pamieci nie ma tu ani slowa: to osobna linia,
  # pokazywana ZAWSZE (patrz Zglos-Koszt), a nie dopisek doklejany do cudzego meldunku
  # wtedy, gdy akurat cos innego nie gra.
  function Zglos-Cykl {
    $plik = Join-Path $KatalogDomowy ".claude\wiedza\cykl-ostatni.txt"
    if (-not (Test-Path $plik)) { return }        # cyklu na tej maszynie nie ma
    $c = Czytaj-Klucze $plik
    if (-not $c["status"]) { return }
    $zaleglosc = 0
    if ($c["zaleglosc"] -match '^\d+$') { $zaleglosc = [int]$c["zaleglosc"] }

    # podsumowanie sprzed kilku dni znaczy, ze cykl w ogole nie chodzi
    $stare = $false
    $data = [datetime]::MinValue
    if ([datetime]::TryParse($c["data"], [ref]$data)) {
      $stare = (([datetime]::Now - $data).TotalDays -gt 2)
    }
    if ($c["status"] -eq "ok" -and $zaleglosc -le 0 -and -not $stare) { return }

    $stan = $c["opis"]
    if (-not $stan) { $stan = "stan cyklu: $($c['status'])" }
    if ($stare) { $stan = "cykl nie chodzil od $([int]([datetime]::Now - $data).TotalDays) dni - $stan" }

    Write-Host "MegaRuchacz: $stan."
  }

  # Osobne try, zeby potkniecie sie na jednym nie zabralo drugiego.
  # Pobranie idzie pierwsze - reszta porownuje sie z katalogiem zrodlowym,
  # wiec ma sens dopiero wtedy, gdy ten katalog jest swiezy.
  try { Odswiez-Zrodlo }   catch { Zanotuj-Wywrotke "odswiezanie zrodla" $_ }
  try { Pilnuj-Zasad }     catch { Zanotuj-Wywrotke "pilnowanie zasad" $_ }
  try { Pilnuj-Sufitu-Zawsze } catch { Zanotuj-Wywrotke "pilnowanie sufitu ladunku" $_ }
  try { Pilnuj-Wersji }    catch { Zanotuj-Wywrotke "pilnowanie wersji wdrozenia" $_ }
  try { Zglos-Kandydatow } catch { Zanotuj-Wywrotke "poczekalnia faktow" $_ }
  try { Zglos-Cykl }       catch { Zanotuj-Wywrotke "meldunek o cyklu" $_ }
  # Wywrotki z przebiegow bez widowni i cisza po stronie Codeksa - tu jest
  # jedyne miejsce, w ktorym maja szanse dotrzec do czlowieka.
  try { Zglos-Wywrotki }   catch { Zanotuj-Wywrotke "meldunek o wywrotkach" $_ }
  try { Zglos-Cisze }      catch { Zanotuj-Wywrotke "wykrywanie ciszy" $_ }
  # Rachunek za pamiec na koncu, zeby zostal pod reka uzytkownika - a pelniejszy
  # meldunek raz na dobe zaraz za nim, bo objasnia te sama liczbe.
  try { Zglos-Koszt }        catch { Zanotuj-Wywrotke "rachunek za pamiec" $_ }
  try { Zglos-Koszt-Dzienny } catch { Zanotuj-Wywrotke "dzienny rachunek za pamiec" $_ }
  # Na samym koncu: cykl wiedzy przy pierwszej sesji dnia. Linia o tym, co sie
  # zaczelo, ma stac pod rachunkiem, bo to ciag dalszy tej samej sprawy.
  try { Ruszaj-Cykl }        catch { Zanotuj-Wywrotke "start cyklu wiedzy" $_ }
  Zapisz-Obecnosc (Nazwa-Trybu)
} catch {
  # Ostatnia siatka. Przebieg i tak konczy sie kodem 0, bo start sesji jest
  # wazniejszy - ale nie konczy sie juz po cichu: slad idzie do pliku stanu
  # i zostanie zameldowany przy nastepnym otwarciu okna.
  try { Zanotuj-Wywrotke "przebieg straznika" $_; Zapisz-Obecnosc (Nazwa-Trybu) } catch { }
}
exit 0
