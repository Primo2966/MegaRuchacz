# Straznik - pilnuje czterech rzeczy przy kazdym otwarciu okna:
#   0. czy sam katalog zrodlowy narzedzia nie zostal w tyle za zdalnym repo,
#   1. czy bloki zasad pamieci MegaRuchacza (lore, wiedza) nadal siedza w ~/.claude/CLAUDE.md,
#   2. czy wdrozenie w projekcie nie zostalo w tyle za katalogiem zrodlowym,
#   3. ile kosztuje pamiec agenta i czy cokolwiek jest UCINANE.
# Przy instalacji globalnej (~\.claude\.megaruchacz-global) dodatkowo trzyma jeden
# komplet hookow MegaRuchacza w ~\.claude\settings.json i zdejmuje zdublowane hooki
# projektowe (patrz Pilnuj-Hookow-Globalnych). W tym trybie wola go globalny hook
# SessionStart z -Projekt "$CLAUDE_PROJECT_DIR", czyli w KAZDYM projekcie.
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
# Od P59a samonaprawa slucha rejestru instalacji (~\.claude\mr\instalacja.json, umowa:
# narzedzia\instalacja\stan.ps1): dogrywa TYLKO to, co nalezy do wlaczonych modulow, i zdejmuje
# NASZE bloki i hooki modulow wylaczonych - bloki zasad lore/wiedza (Pilnuj-Zasad), blok
# kierownika (Pilnuj-Kierownika), hooki globalne (Pilnuj-Hookow-Globalnych),
# cykl wiedzy (Ruszaj-Cykl). Brak rejestru = jak przed nim (wszystko poza kopia wlaczone).
# Rejestr nieczytelny = wszystko wlaczone, jedna linia alarmu i ZADNEGO zdejmowania.
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
#   powershell -NoProfile -File narzedzia\straznik-zasad.ps1 -NaprawGlobalne [-Proba]
#       naprawia SAME hooki instalacji globalnej w ~\.claude\settings.json (jeden
#       komplet, bez duplikatow, przypomnienie przez skrypt, straznik na starcie)
#       i nic poza tym. Wola go instaluj-globalnie.ps1; -Proba = tylko plan.
#       Z jawnym -Projekt <katalog> zdejmuje tez zdublowane hooki z tego projektu.
#   powershell -NoProfile -File narzedzia\straznik-zasad.ps1 -UsunGlobalne [-Proba]
#       zdejmuje hooki MegaRuchacza z ~\.claude\settings.json (cudze zostaja).
#   powershell -NoProfile -File narzedzia\straznik-zasad.ps1 -Dopasuj
#       dopasowuje pliki do rejestru instalacji od razu, bez czekania na nastepna sesje:
#       bloki zasad, blok kierownika, szkielet "Co wiem", hooki globalne. Bez sieci, cyklu
#       i rachunku. Dla instalatora po zmianie modulow. Kod 1 = cos sie nie udalo.
#   -KatalogDomowy  podstawiony katalog domowy - do testow

param(
  [string]$Zrodlo = "",
  [string]$Projekt = "",
  [string]$KatalogDomowy = $HOME,
  [string]$Odrzuc = "",
  [switch]$Moduly,
  [switch]$Tlo,
  [switch]$PoliczKoszt,
  [switch]$KosztCodex,
  [switch]$NaprawGlobalne,
  [switch]$UsunGlobalne,
  [switch]$Dopasuj,
  [switch]$Proba
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
      koszt        = "okolo 496 MB pobrania i Python, lokalna baza z trescia rozmow, dostep agenta do tych tresci, zadanie w harmonogramie co 10 minut i nadzorca w zasobniku (drugie zadanie, przy logowaniu); na istniejacej bazie - przeliczenie archiwum na nowy model w tle, ~2-4 h z obnizonym priorytetem"
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
# Lista narzedzi AI i cele zasad (warianty, Codex w Orce, plik OpenCode, szkielet "Co wiem", limit) -
# ten sam kod co w instaluj-globalnie.ps1 i wpisz-zasady.ps1. Brak pliku melduje Pilnuj-Kierownika.
$plikCeliKierownika = Join-Path $PSScriptRoot "kierownik-cele.ps1"
if (Test-Path $plikCeliKierownika) { . $plikCeliKierownika }
# Zapis odporny na zanik pradu i rozpoznawanie wyzerowanych plikow pamieci (awaria
# 2026-10-02, patrz naglowek tego pliku). Brak pliku melduje Sprawdz-Zera - glosno.
$plikZapisu = Join-Path $PSScriptRoot "zapis-trwaly.ps1"
if (Test-Path $plikZapisu) { . $plikZapisu }
# Rejestr instalacji (ktore moduly sa wlaczone) - wspolna umowa z instalatorem, nadzorca
# i hookiem przypomnienia. Starsza kopia narzedzia bez niego = wszystko wlaczone, jak dotad.
$plikRejestru = Join-Path $PSScriptRoot "instalacja\stan.ps1"
if (Test-Path $plikRejestru) { . $plikRejestru }
# Znaczniki i regula skladania blokow zasad pamieci (lore, wiedza) - ten sam kod, ktorym pisze
# wpisz-zasady.ps1. Brak pliku melduje Pilnuj-Zasad.
$plikBlokowZasad = Join-Path $PSScriptRoot "zasady-bloki.ps1"
if (Test-Path $plikBlokowZasad) { . $plikBlokowZasad }

# Znaczniki bloku zasad kierownika w PROJEKTOWYM AGENTS.md (wdroz.ps1, Odswiez-Agents). Do P59a
# ten sam znacznik nosil w plikach globalnych wspolny blok Lore+Wiedza - dzis to dwa bloki
# lore/wiedza (zasady-bloki.ps1), a stary blok zamienia na nie Pilnuj-Zasad.
$POCZATEK = "<!-- MegaRuchacz:start -->"
$KONIEC   = "<!-- MegaRuchacz:koniec -->"

$plikDomowy   = Join-Path $KatalogDomowy ".claude\CLAUDE.md"
# Plik instrukcji Codeksa. Bez $env:CODEX_HOME z premedytacja: zasady wpisuje
# wpisz-zasady.ps1, ktory liczy go tak samo - z $KatalogDomowy. Gdybysmy tu
# patrzyli gdzie indziej, straznik pilnowalby innego pliku, niz naprawia.
$plikCodex    = Join-Path $KatalogDomowy ".codex\AGENTS.md"

# Czy narzedzia bez Claude Code sa na tej maszynie. Poprawki nanosimy tylko na
# czesc narzedzia, ktore tu stoi: katalog .megaruchacz\ jest wspolny dla Codeksa
# i opencode, wiec jego obecnosc nie dowodzi, ze stoi tu oba. Detekcja ta sama
# co w wdroz.ps1 - polecenie w PATH albo katalog konfiguracji narzedzia.
$JestCodex    = [bool](Get-Command codex    -CommandType Application -ErrorAction SilentlyContinue) -or (Test-Path (Split-Path -Parent $plikCodex))
$JestOpencode = [bool](Get-Command opencode -CommandType Application -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $KatalogDomowy ".config\opencode"))

# Rejestr instalacji czytamy RAZ na przebieg - wszystkie decyzje przebiegu (co dograc, co zdjac)
# wynikaja z jednego odczytu. Wywrotka odczytu liczy sie jak rejestr nieczytelny: wszystko
# wlaczone i nic nie zdejmujemy.
$script:Instalacja = $null
if (Get-Command Czytaj-Instalacje -ErrorAction SilentlyContinue) {
  try { $script:Instalacja = Czytaj-Instalacje $KatalogDomowy }
  catch {
    $script:Instalacja = [pscustomobject]@{
      moduly = [pscustomobject]@{ wiedza = $true; lore = $true; kierownik = $true; skille = $true; kopia = $true }
      zrodlo = "awaryjne"; blad = "odczyt rejestru instalacji sie wywrocil: $($_.Exception.Message)" }
  }
}
if (-not $script:Instalacja) {
  $script:Instalacja = [pscustomobject]@{
    moduly = [pscustomobject]@{ wiedza = $true; lore = $true; kierownik = $true; skille = $true; kopia = $false }
    zrodlo = "brak-umowy"; blad = $null }
}
# Czy modul jest wlaczony - przy braku rejestru i przy rejestrze nieczytelnym zawsze tak; brak
# klucza tez znaczy "tak" (umowa stan.ps1) - nawet gdy lista modulow umowy wyszla pusta.
function Modul-Wl([string]$nazwa) {
  $v = $script:Instalacja.moduly.$nazwa
  return (($null -eq $v) -or [bool]$v)
}
# Czy wolno zdjac cos modulu wylaczonego - nigdy przy rejestrze nieczytelnym.
function Modul-Wylaczony([string]$nazwa) { return ((-not $script:Instalacja.blad) -and -not (Modul-Wl $nazwa)) }

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
# To samo dla Codeksa - OSOBNY plik, bo od 0.21.3 kazde narzedzie ma wlasny
# rachunek (koszt-pamieci.ps1 -Narzedzie). Do 0.21.2 Codex dostawal linie
# Claude Code, czyli liczbe, ktorej jego model w ogole nie placi.
$plikKosztuCodex = Join-Path $KatalogDomowy ".claude\.megaruchacz-koszt-codex.txt"
# Liczenie obu rachunkow trwa kilka sekund (zmierzone 28.09: ~1 s na narzedzie).
# Proba sprzed wiecej niz tylu minut, po ktorej w pliku nie ma swiezej linii,
# to przeliczenie, ktore sie wywrocilo - wtedy "przeliczam" byloby klamstwem.
$MINUT_NA_PRZELICZENIE = 5
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

# Plik tymczasowy + zapis przez bufor dysku + podmiana (zapis-trwaly.ps1): CLAUDE.md i kopia
# dla opencode zapisane zwyklym WriteAllText byly 2026-10-02 wsrod wyzerowanych plikow.
function Zapisz-Tekst($sciezka, $tekst) {
  $katalog = Split-Path -Parent $sciezka
  if ($katalog -and -not (Test-Path $katalog)) { New-Item -ItemType Directory -Force -Path $katalog | Out-Null }
  if (Get-Command Zapisz-Trwale -ErrorAction SilentlyContinue) { Zapisz-Trwale $sciezka $tekst (Bez-Bom); return }
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

# To samo scalenie, tylko w druga strone - zdejmuje wymienione klucze, reszte zostawia.
# Zapis tylko wtedy, gdy ktorys z nich w ogole byl.
function Usun-Klucze($sciezka, [string[]]$nazwy) {
  $stan = Czytaj-Klucze $sciezka
  $byly = @($nazwy | Where-Object { $stan.Contains($_) })
  if ($byly.Count -eq 0) { return }
  foreach ($k in $byly) { $stan.Remove($k) }
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
# Ile napraw sie nie udalo (zasady, blok kierownika) - z tego bierze sie
# kod wyjscia trybu -Dopasuj; hook startowy konczy sie zerem zawsze.
$script:Niepowodzenia = 0

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

# Zdanie do czlowieka z przebiegu, ktory nie ma widowni. W trybie -Tlo (jedyny
# hook Codeksa, ktory cokolwiek nanosi) "Mow" znaczy "do dziennika", a dziennik
# jest dowodem, ze zadanie chodzi - nie skrzynka na prosby. Prosba, na ktora
# uzytkownik ma odpowiedziec (np. zatwierdzic hooki przez /hooks), czeka wiec
# w pliku stanu na najblizszy przebieg, ktory ma komu mowic - tak samo jak wywrotki.
$WIADOMOSCI_NAJWYZEJ = 3
function Odloz-Wiadomosc([string]$tekst) {
  if (-not $tekst) { return }
  try {
    $stan = Czytaj-Klucze $plikStanu
    $naj = 0
    $ile = 0
    foreach ($k in @($stan.Keys)) {
      $m = [regex]::Match($k, '^mow\.(\d+)$')
      if (-not $m.Success) { continue }
      if ("$($stan[$k])" -eq $tekst) { return }   # juz czeka, nie dubluj
      $ile++
      if (([int]$m.Groups[1].Value) -gt $naj) { $naj = [int]$m.Groups[1].Value }
    }
    if ($ile -ge $WIADOMOSCI_NAJWYZEJ) { return }
    $nowy = [ordered]@{}
    $nowy["mow." + ($naj + 1)] = $tekst
    Dopisz-Klucze $plikStanu $nowy
  } catch { Notuj "odlozenie wiadomosci nie wyszlo: $($_.Exception.Message)" }
}

# Odlozone zdania - zwraca je i CZYSCI, bo maja dojsc raz. Gdy sprawa wroci,
# odlozy je na nowo ten sam przebieg, ktory ja zauwazy.
function Odbierz-Wiadomosci {
  $stan = Czytaj-Klucze $plikStanu
  $klucze = @($stan.Keys | Where-Object { $_ -match '^mow\.\d+$' })
  if ($klucze.Count -eq 0) { return @() }
  $linie = @()
  foreach ($k in $klucze) {
    $linie += "$($stan[$k])"
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

# Prosby odlozone przez przebiegi bez widowni - to samo miejsce w lancuchu,
# co wywrotki. Pod Codeksem odbiera je Wypisz-Koszt-Codex; kto pierwszy, ten
# je pokaze, bo po obu stronach ekranu siedzi ten sam czlowiek.
function Zglos-Odlozone {
  foreach ($l in @(Odbierz-Wiadomosci)) { Write-Host $l }
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

# Kopia z wyzerowanego pliku to nie kopia - 2026-10-02 taka "kopia" zer wygladala potem jak
# najnowsza zdrowa. Kopiuj-Trwale rzuca wyjatkiem, a wolajacy melduje go jako wywrotke.
function Kopia-Zapasowa($sciezka, $stempel) {
  if (-not (Test-Path $sciezka)) { return }
  if (Get-Command Kopiuj-Trwale -ErrorAction SilentlyContinue) { Kopiuj-Trwale $sciezka "$sciezka.bak-$stempel"; return }
  Copy-Item $sciezka "$sciezka.bak-$stempel" -Force
}

# ------------------------------------------------- 0a. wyzerowane pliki pamieci
# Pierwsza rzecz kazdego przebiegu: czy CLAUDE.md, AGENTS.md i pliki wiedza\ nie maja w srodku
# bajtow 0x00 (zanik pradu tuz po zapisie zostawia pelna dlugosc i same zera). Gdy maja:
# alarm jako PIERWSZA linia wyjscia hooka, a potem zadnego wpisywania zasad, kopii dla
# opencode ani cyklu wiedzy - 2026-10-02 straznik dokleil bloki do zer i zrobil ich "kopie".
$script:Wyzerowane = @()
function Sprawdz-Zera {
  if (-not (Get-Command Wyzerowane-Pliki -ErrorAction SilentlyContinue)) {
    Mow "MegaRuchacz: nie ma $plikZapisu - nie sprawdzam, czy pliki pamieci nie sa wyzerowane, i zapisuje je po staremu."
    return
  }
  # bez @(): funkcja oddaje tablice jednym obiektem, a @() zrobiloby z pustej tablicy jeden element
  $script:Wyzerowane = Wyzerowane-Pliki $KatalogDomowy
  if ($script:Wyzerowane.Count -eq 0) { return }
  Mow ("MegaRuchacz: " + (Opis-Wyzerowanych $script:Wyzerowane $KatalogDomowy $Zrodlo) +
       " Do czasu przywrocenia nie wpisuje zasad i nie ruszam cyklu wiedzy.")
}

# Rejestr instalacji nieczytelny (pusty, wyzerowany po zaniku pradu, zly JSON) - jedna linia
# alarmu przy kazdym przebiegu, zaraz po alarmie o zerach. Do czasu naprawy pilnujemy wszystkiego
# jak przed rejestrem i niczego nie zdejmujemy: rejestr, ktorego nie umiemy przeczytac, nie ma
# prawa odinstalowac modulu.
function Zglos-Rejestr {
  if (-not $script:Instalacja.blad) { return }
  Mow ("MegaRuchacz: ALARM - $($script:Instalacja.blad). Do czasu naprawy pilnuje wszystkich modulow jak dotad " +
       "i niczego nie zdejmuje; rejestr zapisze od nowa ponowne uruchomienie instalatora (instaluj.bat).")
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

# Podmiana STAREGO hooka przypomnienia (samo "cat" pliku) na wywolanie skryptu.
# To jedyne miejsce, w ktorym nadpisujemy polecenie juz istniejacego hooka - bez
# tego wdrozenia sprzed 2026-09-17 nigdy nie pokazalyby postepu cyklu ani (od
# 2026-09-24) podpowiedzi z archiwum, bo hook dopisuje sie wylacznie wtedy, gdy go
# w ogole nie ma. Ruszamy tylko wpisy, ktore niosa NASZ plik i nie wolaja jeszcze
# naszego skryptu. Zmienia $s w miejscu; zwraca $true, gdy cos podmienila.
# Wolana z Napraw-Hooki (po podbiciu wersji) i z Pilnuj-Przypomnienia-Zawsze
# (przy kazdym przebiegu) - stare wdrozenie nie ma czekac na nastepna wersje.
function Podmien-Przypomnienie-Claude($s, $r) {
  $podmienione = $false
  if ($s.hooks -and ($s.hooks.PSObject.Properties.Name -contains "UserPromptSubmit")) {
    foreach ($grupa in @($s.hooks.UserPromptSubmit)) {
      foreach ($h in @($grupa.hooks)) {
        if (-not $h) { continue }
        if ("$($h.command)" -notlike "*orchestrator-reminder.json*") { continue }
        if (Wola-Przypomnienie "$($h.command)") { continue }
        $h.command = Polecenie-Przypomnienia $r
        $podmienione = $true
      }
    }
  }
  return $podmienione
}

# settings.json jest w polowie wlasnoscia uzytkownika - dopisujemy wylacznie
# brakujace hooki, nigdy nie przepisujemy calego pliku.
function Napraw-Hooki($cel, $zrodlo, $stempel) {
  # Przy instalacji globalnej hooki projektowe sa duplikatem - Usun-Hooki-Projektowe
  # je zdejmuje, wiec dopisanie ich tu z powrotem kreciloby sie w kolko.
  if (Projekt-Bez-Hookow (Split-Path -Parent $cel)) { return $false }
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
  $podmienione = Podmien-Przypomnienie-Claude $s $r

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

# Czy to polecenie WOLA skrypt przypomnienia, czy tylko wypisuje plik ladunku.
# Zwykle "-like *przypomnienie.js*" tego NIE odroznia: nazwa ladunku
# (przypomnienie.json) zawiera nazwe skryptu (przypomnienie.js) jako podciag,
# wiec warunek trafial ZAWSZE i podmiana starego hooka nie zaszla ani razu -
# sprawdzone 2026-09-17. Granica po ".js" jest odporna na cudzyslowy, ukosniki
# i na to, czy polecenie idzie przez bash, czy przez powershella (w wariancie
# windowsowym sciezka stoi w apostrofach, wiec dopasowanie do 'przypomnienie.js"'
# tez by sie przewrocilo).
function Wola-Przypomnienie([string]$polecenie) {
  return ($polecenie -match 'przypomnienie\.js(?![A-Za-z0-9])')
}

# Ustawia pole obiektu z JSON-a niezaleznie od tego, czy ono tam juz jest.
function Ustaw-Pole($obiekt, $nazwa, $wartosc) {
  if ($obiekt.PSObject.Properties.Name -contains $nazwa) { $obiekt.$nazwa = $wartosc }
  else { $obiekt | Add-Member -NotePropertyName $nazwa -NotePropertyValue $wartosc -Force }
}

# Istniejaca grupa hookow zostaje w spokoju - z dwoma wyjatkami, bo inaczej
# usterka naprawiona w szablonie zyje we wdrozeniu do konca swiata:
#   1. POLECENIE inne niz szablonowe (np. bez zabezpieczenia na brak node'a).
#      To zmiana definicji hooka, wiec uniewaznia zatwierdzenie z /hooks i musi
#      byc zameldowana czlowiekowi.
#   2. additionalContextLimit NIZSZY niz szablonowy - podnosimy do szablonowego,
#      nigdy nie obnizamy. Wlasny, wyzszy sufit uzytkownika rzadzi (tak samo
#      czyta go narzedzia\sufit-ladunku.ps1), a zanizony ucinalby ladunek po cichu.
#      Sam limit nie jest czescia definicji hooka, wiec /hooks tego nie dotyczy.
function Zsynchronizuj-Grupe($grupa, $wzor) {
  $wynik = [ordered]@{ Polecenie = $false; Limit = $false }
  $mam = @($grupa.hooks)
  $ich = @($wzor.hooks)
  for ($i = 0; $i -lt $ich.Count; $i++) {
    if ($i -ge $mam.Count) { break }
    $h = $mam[$i]
    $w = $ich[$i]
    if ($null -eq $h -or $null -eq $w) { continue }
    foreach ($pole in @("command", "commandWindows")) {
      if ($w.PSObject.Properties.Name -notcontains $pole) { continue }
      if ("$($h.$pole)" -eq "$($w.$pole)") { continue }
      Ustaw-Pole $h $pole $w.$pole
      $wynik.Polecenie = $true
    }
    if ($w.PSObject.Properties.Name -contains "additionalContextLimit") {
      $limitWzoru = [int]$w.additionalContextLimit
      $limitMoj = 0
      if ($h.PSObject.Properties.Name -contains "additionalContextLimit") { $limitMoj = [int]$h.additionalContextLimit }
      if ($limitMoj -lt $limitWzoru) {
        Ustaw-Pole $h "additionalContextLimit" $limitWzoru
        $wynik.Limit = $true
      }
    }
  }
  return $wynik
}

# Co Napraw-Hooki-Codex zrobil z plikiem. Trzy listy zdarzen, bo trzy rozne
# rzeczy do powiedzenia: dopisana grupa i zmienione polecenie wymagaja ponownego
# /hooks, samo podniesienie sufitu ladunku - nie.
function Wynik-Hookow {
  return [ordered]@{ Dodane = @(); Poprawione = @(); Limity = @() }
}

# Szablon hookow Codeksa z podstawionymi sciezkami - albo $null, gdy go nie ma
# albo nie jest JSON-em.
function Szablon-Hookow-Codex($zrodlo, $projekt) {
  $surowy = Czytaj-Tekst (Join-Path $zrodlo "szablony-codex\hooks.json")
  if (-not $surowy) { return $null }
  $surowy = $surowy.TrimStart([char]0xFEFF).Replace("{{PROJEKT}}", $projekt.Replace("\","/")).Replace("{{ZRODLO}}", $zrodlo.Replace("\","/"))
  try { $szablon = $surowy | ConvertFrom-Json } catch { return $null }
  if (-not $szablon.hooks) { return $null }
  return $szablon
}

# Jedyny wyjatek od zasady "istniejacych grup nie ruszamy": stare przypomnienie,
# ktore samo wypisywalo plik ("cat" / Get-Content). Dzis to samo robi skrypt, ktory
# dokleja linie o pracujacym cyklu i podpowiedz z archiwum - i bez tej jednej
# podmiany zadne wdrozenie sprzed 2026-09-17 by ich nie zobaczylo. Podmieniamy RAZ:
# polecenie wskazuje juz na skrypt, wiec kazda kolejna poprawka dzieje sie w srodku
# skryptu i nie wymaga ponownego zatwierdzania hookow. Zmienia $s w miejscu;
# zwraca $true, gdy cos podmienila. Wolana z Napraw-Hooki-Codex i z
# Pilnuj-Przypomnienia-Zawsze.
function Podmien-Przypomnienie-Codex($s, $szablon) {
  $podmienione = $false
  $wzorPrzyp = $null
  foreach ($g in @($szablon.hooks.UserPromptSubmit)) {
    foreach ($hw in @($g.hooks)) {
      if (Wola-Przypomnienie ("" + $hw.command + " " + $hw.commandWindows)) { $wzorPrzyp = $hw }
    }
  }
  if ($wzorPrzyp -and $s.hooks -and ($s.hooks.PSObject.Properties.Name -contains "UserPromptSubmit")) {
    foreach ($grupa in @($s.hooks.UserPromptSubmit)) {
      foreach ($h in @($grupa.hooks)) {
        if (-not $h) { continue }
        $pol = "" + $h.command + " " + $h.commandWindows
        if ($pol -notlike "*przypomnienie.json*") { continue }
        if (Wola-Przypomnienie $pol) { continue }
        $h.command = $wzorPrzyp.command
        if ($h.PSObject.Properties.Name -contains "commandWindows") { $h.commandWindows = $wzorPrzyp.commandWindows }
        else { $h | Add-Member -NotePropertyName commandWindows -NotePropertyValue $wzorPrzyp.commandWindows -Force }
        $podmienione = $true
      }
    }
  }
  return $podmienione
}

# .codex\hooks.json - tu chodzimy na palcach. Zmiana DEFINICJI hooka (polecenie,
# timeout, matcher, async) uniewaznia zatwierdzenie z /hooks i zmusza uzytkownika
# do powtarzania go, wiec grupy, ktore juz tam sa, ruszamy WYLACZNIE tak, jak
# opisuje Zsynchronizuj-Grupe (rozjechane polecenie, zanizony sufit) - poza tym
# dopisujemy tylko brakujace. Swoje poznajemy po "statusMessage", tak samo jak
# wdroz.ps1. Zwraca Wynik-Hookow - o kazdej pozycji trzeba powiedziec wprost.
function Napraw-Hooki-Codex($celCodex, $zrodlo, $projekt, $stempel) {
  $szablon = Szablon-Hookow-Codex $zrodlo $projekt
  if (-not $szablon) { return (Wynik-Hookow) }

  $plik = Join-Path $celCodex "hooks.json"
  $s = [pscustomobject]@{}
  $raw = Czytaj-Tekst $plik
  # Cudzy plik, ktory nie jest czystym JSON-em, zostaje nietkniety - tak samo
  # jak w instalatorze. Lepiej nie dopisac hooka niz zepsuc komus ustawienia.
  if ($raw) {
    try { $s = $raw.TrimStart([char]0xFEFF) | ConvertFrom-Json } catch { return (Wynik-Hookow) }
  }
  if (-not ($s.PSObject.Properties.Name -contains "hooks") -or $null -eq $s.hooks) {
    $s | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force
  }

  $podmienione = Podmien-Przypomnienie-Codex $s $szablon

  $wynik = Wynik-Hookow
  if ($podmienione) { $wynik.Poprawione += "UserPromptSubmit" }
  foreach ($zdarzenie in $szablon.hooks.PSObject.Properties.Name) {
    $obecne = @()
    if ($s.hooks.PSObject.Properties.Name -contains $zdarzenie) { $obecne = @($s.hooks.$zdarzenie) }
    foreach ($grupa in @($szablon.hooks.$zdarzenie)) {
      $znacznik = $grupa.hooks[0].statusMessage
      if (-not $znacznik) { $znacznik = "MegaRuchacz" }
      # Nasza grupa, jesli juz tam jest - poznajemy ja po tym samym znaczniku,
      # ktorym rozpoznaje swoje wdroz.ps1.
      $nasza = $null
      foreach ($g in $obecne) {
        if ((($g | ConvertTo-Json -Depth 20 -Compress) -like "*$znacznik*")) { $nasza = $g; break }
      }
      if (-not $nasza) {
        $obecne += $grupa
        $wynik.Dodane += $zdarzenie
        continue
      }
      $co = Zsynchronizuj-Grupe $nasza $grupa
      if ($co.Polecenie) { $wynik.Poprawione += $zdarzenie }
      if ($co.Limit)     { $wynik.Limity += $zdarzenie }
    }
    if ($obecne.Count -eq 0) { continue }
    if ($s.hooks.PSObject.Properties.Name -contains $zdarzenie) { $s.hooks.$zdarzenie = @($obecne) }
    else { $s.hooks | Add-Member -NotePropertyName $zdarzenie -NotePropertyValue @($obecne) -Force }
  }
  if ($wynik.Dodane.Count -eq 0 -and $wynik.Poprawione.Count -eq 0 -and $wynik.Limity.Count -eq 0) { return $wynik }
  Kopia-Zapasowa $plik $stempel
  Zapisz-Tekst $plik ($s | ConvertTo-Json -Depth 20)
  return $wynik
}

# Czy Codex w tym projekcie jest sprawa MegaRuchacza. Tak, gdy MegaRuchacz juz go tu
# postawil - jego hooki w <projekt>\.codex\hooks.json (statusMessage "MegaRuchacz..."
# albo polecenie z mr-log-codex.js) albo jego role w <projekt>\.codex\agents (znacznik
# kierownik-template); te same slady, po ktorych instalator globalny poznaje ~/.codex
# (Codex-Od-MegaRuchacza w instaluj-globalnie.ps1) - albo gdy projekt ma to jawnie
# wlaczone: "codex: tak" w .claude\megaruchacz-wersja.txt (odpowiednik flagi -Codex
# instalatora). Zwraca powod (pusty = nie) i uwage, gdy hooks.json nie da sie odczytac.
function Codex-W-Projekcie($projekt) {
  $w = [ordered]@{ powod = ""; uwaga = "" }
  $stanW = Czytaj-Klucze (Join-Path $projekt ".claude\megaruchacz-wersja.txt")
  if ("$($stanW['codex'])" -match '^(t|tak|y|yes)$') { $w.powod = "codex: tak w .claude\megaruchacz-wersja.txt"; return $w }
  $celCodex = Join-Path $projekt ".codex"
  $raw = Czytaj-Tekst (Join-Path $celCodex "hooks.json")
  if ($raw) {
    $s = $null
    try { $s = $raw.TrimStart([char]0xFEFF) | ConvertFrom-Json }
    catch { $w.uwaga = ".codex\hooks.json nie jest czystym JSON-em, wiec nie widze w nim hookow MegaRuchacza" }
    if ($s -and $s.hooks) {
      foreach ($z in $s.hooks.PSObject.Properties.Name) {
        foreach ($g in @($s.hooks.$z)) {
          foreach ($h in @($g.hooks)) {
            if (-not $h) { continue }
            if ((("" + $h.command + " " + $h.commandWindows) -match 'mr-log-codex\.js') -or (("" + $h.statusMessage) -like "MegaRuchacz*")) {
              $w.powod = "sa juz hooki MegaRuchacza w .codex\hooks.json"; return $w
            }
          }
        }
      }
    }
  }
  foreach ($r in @(Get-ChildItem (Join-Path $celCodex "agents\*.toml") -ErrorAction SilentlyContinue)) {
    if ((Czytaj-Tekst $r.FullName) -match "kierownik-template") { $w.powod = "sa juz role MegaRuchacza w .codex\agents"; return $w }
  }
  return $w
}

# Czesc codeksowa wdrozenia: role w .codex\agents\, zasady i ladunki hookow
# w .megaruchacz\, blok zasad w AGENTS.md. Nanosimy ja na tych samych zasadach
# co czesc dla Claude Code - z jednym wyjatkiem, ktory siedzi w Napraw-Hooki-Codex.
function Nanies-Poprawki-Codex($zrodlo, $projekt, $stempel) {
  $celCodex = Join-Path $projekt ".codex"
  $celMega  = Join-Path $projekt ".megaruchacz"
  # Bez .megaruchacz\ to nie jest wdrozenie dla narzedzia - nie zakladamy go sami.
  if (-not (Test-Path $celMega)) { return }
  $szablony = Join-Path $zrodlo "szablony-codex"
  if (-not (Test-Path $szablony)) { return }
  # Czesc codeksowa zakladamy i utrzymujemy tylko tam, gdzie jest sprawa MegaRuchacza
  # (Codex-W-Projekcie). Do 2026-09-30 wystarczalo, ze Codeksa widac na maszynie - i kazda
  # aktualizacja zakladala .codex\agents i .codex\hooks.json w projektach, w ktorych nikt
  # o to nie prosil (raport P31). Gdy Codeksa nie ma ani tu, ani na maszynie, nie ma
  # o czym mowic; w pozostalych przypadkach jedna linia zamiast cichego pominiecia.
  $codexTu = Codex-W-Projekcie $projekt
  if (-not $codexTu.powod) {
    if (-not (Test-Path $celCodex) -and -not $JestCodex) { return }
    $dlaczego = ""
    if ($codexTu.uwaga) { $dlaczego = "$($codexTu.uwaga); " }
    Mow ("MegaRuchacz: Codex w tym projekcie: role i hooki pominiete (${dlaczego}wlaczysz linia 'codex: tak' w " +
         "$(Join-Path $projekt '.claude\megaruchacz-wersja.txt') - wejda przy nastepnej aktualizacji wdrozenia).")
    return
  }
  Notuj "codex w projekcie: $($codexTu.powod)"

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
  $wynikH = Napraw-Hooki-Codex $celCodex $zrodlo $projekt $stempel
  $doZatwierdzenia = @(@($wynikH.Dodane) + @($wynikH.Poprawione) | Select-Object -Unique)
  if ($doZatwierdzenia.Count -gt 0) {
    $prosba = "MegaRuchacz: doszedl albo zmienil sie hook Codeksa (" + ($doZatwierdzenia -join ", ") +
              ") w .codex\hooks.json - zatwierdz go w Codeksie poleceniem /hooks, inaczej nie wystartuje."
    Mow $prosba
    # Pod Codeksem straznik chodzi w trybie -Tlo, a tam "Mow" znaczy "do dziennika",
    # ktorego nikt nie czyta - czyli prosba skierowana do uzytkownika Codeksa
    # trafialaby dokladnie tam, gdzie jej nie zobaczy. Odkladamy ja wiec do pliku
    # stanu i doklejamy do ladunku hooka od rachunku (Wypisz-Koszt-Codex).
    if ($Tlo) { Odloz-Wiadomosc $prosba }
  }
  if (@($wynikH.Limity).Count -gt 0) {
    Mow ("MegaRuchacz: podniesiony sufit ladunku hooka Codeksa (" +
         ((@($wynikH.Limity) | Select-Object -Unique) -join ", ") +
         ") w .codex\hooks.json do wartosci z szablonu - sufit nie jest czescia definicji hooka, wiec /hooks zatwierdzac nie trzeba.")
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

# Czesc opencode wdrozenia: role w .opencode\agents\ i wtyczka rejestru.
# Odswiezamy na tych samych zasadach co .codex\ - z jednym wyjatkiem: opencode
# nie ma hooks.json ani zatwierdzania, wiec nie ma tu czego oglaszac czlowiekowi.
# Gdy Codex jest na maszynie, Nanies-Poprawki-Codex tez odswiezy zasady i AGENTS.md
# (wariantem codeksowym); to wezwanie idzie po nim, wiec wygrywa wariant opencode -
# ten sam, ktory wybiera wdroz.ps1, gdy sa oba narzedzia.
function Nanies-Poprawki-Opencode($zrodlo, $projekt, $stempel) {
  $celMega = Join-Path $projekt ".megaruchacz"
  # Bez .megaruchacz\ to nie jest wdrozenie trybu workerow - nie zakladamy go sami.
  # Bez opencode na maszynie nie ma czego odswiezac.
  if (-not (Test-Path $celMega)) { return }
  if (-not $JestOpencode) { return }
  $szablony = Join-Path $zrodlo "szablony-opencode"
  if (-not (Test-Path $szablony)) { return }

  New-Item -ItemType Directory -Force -Path (Join-Path $projekt ".opencode\agents")  | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $projekt ".opencode\plugins") | Out-Null
  foreach ($p in @(Get-ChildItem (Join-Path $szablony "agents\*.md") -ErrorAction SilentlyContinue)) {
    [void](Odswiez $p.FullName (Join-Path $projekt ".opencode\agents\$($p.Name)") $stempel)
  }
  [void](Odswiez (Join-Path $szablony "plugins\mr-log.js") (Join-Path $projekt ".opencode\plugins\mr-log.js") $stempel)

  # Zasady i AGENTS.md - tym samym kodem co czesc codeksowa, zeby znaczniki,
  # kopie zapasowe i warunek "sledzony w gicie" byly w jednym miejscu.
  $plikZasad = Join-Path $szablony "zasady-kierownika.md"
  [void](Odswiez $plikZasad (Join-Path $celMega "zasady-kierownika.md") $stempel)
  [void](Odswiez-Agents $projekt $plikZasad $stempel)

  # Slad w pliku wersji wdrozenia - ten sam format "klucz: wartosc".
  $plikW = Join-Path $celMega "wersja.txt"
  if (Test-Path $plikW) {
    $w = Wersja-Narzedzia (Join-Path $zrodlo "ZMIANY.md")
    if ($w) {
      $stanO = Czytaj-Klucze $plikW
      $stanO["opencode.wersja"] = $w
      $stanO["opencode.data"] = (Get-Date -Format 'yyyy-MM-dd HH:mm')
      Zapisz-Klucze $plikW $stanO
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

# Stary hook przypomnienia ("cat" pliku) podmieniamy przy KAZDYM przebiegu, nie
# tylko po podbiciu wersji - z tego samego powodu co sufit wyzej: gdy wersja
# wdrozenia rowna sie zrodlowej, Nanies-Poprawki nie leci wcale, a wdrozenie, ktore
# przespalo podmiane (do 2026-09-17 nie zachodzila nigdzie przez blad z podciagiem
# nazwy), zostaloby z "cat" na zawsze - bez podpowiedzi z archiwum i bez linii
# postepu cyklu. Samo sprawdzenie to odczyt dwoch malych plikow; zapis tylko wtedy,
# gdy jest co podmienic, i wtedy zawsze z jedna linia dla czlowieka.
function Pilnuj-Przypomnienia-Zawsze {
  if (-not $Projekt) { return }
  $stempel = Get-Date -Format "yyyyMMdd-HHmmss"
  $r = $Zrodlo.Replace("\","/")

  # Claude Code - tylko we wdrozeniu MegaRuchacza (jest plik wersji).
  $plik = Join-Path $Projekt ".claude\settings.json"
  if ((Test-Path $plikWersji) -and (Test-Path $plik)) {
    $raw = Czytaj-Tekst $plik
    $s = $null
    if ($raw) {
      try { $s = $raw.TrimStart([char]0xFEFF) | ConvertFrom-Json }
      catch { Notuj "settings.json nie jest czystym JSON-em - hooka przypomnienia nie sprawdzam: $($_.Exception.Message)" }
    }
    if ($s -and (Podmien-Przypomnienie-Claude $s $r)) {
      Kopia-Zapasowa $plik $stempel
      Zapisz-Tekst $plik ($s | ConvertTo-Json -Depth 20)
      Mow "MegaRuchacz: stary hook przypomnienia (samo 'cat') w .claude\settings.json podmieniony na skrypt z podpowiedzia z archiwum - zadziala od nastepnej sesji; bez node'a przypomnienie idzie jak dotad (kopia: settings.json.bak-${stempel})."
    }
  }

  # Codex - zmiana polecenia uniewaznia zatwierdzenie z /hooks, wiec prosba idzie
  # do czlowieka zawsze, a w trybie -Tlo takze do pliku stanu (patrz Nanies-Poprawki-Codex).
  $plikC = Join-Path $Projekt ".codex\hooks.json"
  if ((Test-Path (Join-Path $Projekt ".megaruchacz")) -and (Test-Path $plikC)) {
    $szablon = Szablon-Hookow-Codex $Zrodlo $Projekt
    $rawC = Czytaj-Tekst $plikC
    $sC = $null
    if ($szablon -and $rawC) {
      try { $sC = $rawC.TrimStart([char]0xFEFF) | ConvertFrom-Json }
      catch { Notuj ".codex\hooks.json nie jest czystym JSON-em - hooka przypomnienia nie sprawdzam: $($_.Exception.Message)" }
    }
    if ($sC -and (Podmien-Przypomnienie-Codex $sC $szablon)) {
      Kopia-Zapasowa $plikC $stempel
      Zapisz-Tekst $plikC ($sC | ConvertTo-Json -Depth 20)
      $prosba = "MegaRuchacz: stary hook przypomnienia Codeksa (samo wypisanie pliku) w .codex\hooks.json podmieniony na skrypt z podpowiedzia z archiwum - zatwierdz go w Codeksie poleceniem /hooks, inaczej przypomnienie nie wystartuje wcale."
      Mow $prosba
      if ($Tlo) { Odloz-Wiadomosc $prosba }
    }
  }
}

function Nanies-Poprawki($zrodlo, $projekt) {
  $stempel = Get-Date -Format "yyyyMMdd-HHmmss"
  $cel = Join-Path $projekt ".claude"
  New-Item -ItemType Directory -Force -Path (Join-Path $cel "agents") | Out-Null
  # Role i zasady z tych samych szablonow co instalacja globalna - jedno zrodlo.
  # (Do 0.21.0 zasady szly z CLAUDE.md repo, ktory dzis ma juz tylko reguly repo.)
  foreach ($p in @(Get-ChildItem (Join-Path $zrodlo "szablony-global\claude\agents\*.md") -ErrorAction SilentlyContinue)) {
    [void](Odswiez $p.FullName (Join-Path $cel "agents\$($p.Name)") $stempel)
  }
  $zasadyZmienione = Odswiez (Join-Path $zrodlo "szablony-global\claude\zasady-kierownika.md") (Join-Path $cel "megaruchacz-zasady.md") $stempel
  [void](Odswiez (Join-Path $zrodlo ".claude\mr-log.js") (Join-Path $cel "mr-log.js") $stempel)
  [void](Odswiez (Join-Path $zrodlo ".claude\orchestrator-reminder.json") (Join-Path $cel "orchestrator-reminder.json") $stempel)
  if ($zasadyZmienione -or -not (Test-Path (Join-Path $cel "megaruchacz-sesja.json"))) { Zbuduj-Sesje $cel }
  [void](Napraw-Hooki $cel $zrodlo $stempel)

  # Wdrozenie dla Codeksa idzie z tym samym modulem, wiec odswieza sie razem
  # z reszta. Osobne try: potkniecie na czesci codeksowej nie ma prawa zabrac
  # poprawek, ktore juz weszly po stronie Claude Code.
  try { Nanies-Poprawki-Codex $zrodlo $projekt $stempel }
  catch { Mow "MegaRuchacz: czesci codeksowej wdrozenia nie udalo sie odswiezyc ($($_.Exception.Message)) - zrobi to ponowne uruchomienie wdroz.ps1." }

  # Czesc opencode idzie zaraz po codeksowej i swiadomie ja przykrywa: gdy oba
  # narzedzia sa na maszynie, wariant opencode (opisujacy oba) ma byc tym, ktory
  # trafia do AGENTS.md i .megaruchacz\. Osobny try, zeby potkniecie na jednej
  # czesci nie zabralo drugiej.
  try { Nanies-Poprawki-Opencode $zrodlo $projekt $stempel }
  catch { Mow "MegaRuchacz: czesci opencode wdrozenia nie udalo sie odswiezyc ($($_.Exception.Message)) - zrobi to ponowne uruchomienie wdroz.ps1." }
}

# ------------------------------------------ hooki instalacji GLOBALNEJ (Claude Code)
# Instalacja globalna (narzedzia\instaluj-globalnie.ps1) trzyma hooki MegaRuchacza
# w ~\.claude\settings.json. Ten plik jest wspolny z innymi programami (Orka dopisuje
# tam swoje hooki na kilkunastu zdarzeniach), wiec zasada jest twarda: ruszamy
# WYLACZNIE wpisy rozpoznane jako nasze po sciezce w poleceniu, a cala reszta pliku
# ma wyjsc z zapisu identyczna co do znaku. Stad wlasny zapis JSON-a (Do-Json) zamiast
# ConvertTo-Json: tamten w PowerShellu 5.1 przeformatowuje caly plik, a Claude Code
# pisze go w ukladzie JSON.stringify(s, null, 2) - i ten sam uklad dajemy tutaj.
#
# Po co: 2026-09-24 w C:\dev\claude-worker chodzily naraz hooki globalne i stare
# projektowe - przypomnienie szlo do modelu DWA razy przy kazdej wiadomosci, a rejestr
# dostawal wpisy podwojnie (w globalnych staly dwa rozne mr-log.js).

$PlikZnacznikaGlobalnego = Join-Path $KatalogDomowy ".claude\.megaruchacz-global"
# Instalacja globalna: znacznik instaluj-globalnie.ps1 albo (od P59a) rejestr instalatora
# z wyborem modulow - straznik (baza) jest w nim zawsze, wiec rejestr tez znaczy "globalnie".
# Wyjatek (P64): rejestr z "baza": false to slad po usunieciu calego MegaRuchacza - wtedy NIE
# globalnie, bo inaczej straznik wywolany z jakiegos projektu dolozylby z powrotem swoj hook.
function Jest-Globalna {
  if (Test-Path $PlikZnacznikaGlobalnego) { return $true }
  if (Baza-Usunieta) { return $false }
  return ($script:Instalacja.zrodlo -in @("plik", "awaryjne"))
}

# Projekt, w ktorym hookow MegaRuchacza ma NIE byc, bo robia to globalne. Wyjatek:
# wdroz.ps1 -WymusProjektowo zostawia w pliku wersji "projektowo: wymuszone" -
# wyrazne zyczenie uzytkownika, wiec wtedy nic nie zdejmujemy.
function Projekt-Bez-Hookow($projekt) {
  if (-not $projekt) { return $false }
  if (-not (Jest-Globalna)) { return $false }
  $plikW = Join-Path $projekt ".claude\megaruchacz-wersja.txt"
  if ((Test-Path $plikW) -and ((Czytaj-Klucze $plikW)["projektowo"] -eq "wymuszone")) { return $false }
  return $true
}

# Czyj to hook. $null = cudzy (Orka i wszystko inne) - takiego nie ruszamy nigdy.
# Orke odcinamy jawnie i PIERWSZA, zeby zadne przyszle dopasowanie do naszych nazw
# nie moglo trafic w jej wpis.
function Rodzaj-Hooka($h) {
  if ($null -eq $h) { return $null }
  $p = "" + $h.command + " " + $h.commandWindows
  if ($p -match '[\\/]\.orca[\\/]') { return $null }
  if ($p -like "*straznik-zasad.ps1*")         { return "straznik" }
  if ($p -like "*megaruchacz-sesja.json*")     { return "zasady" }
  if ($p -like "*orchestrator-reminder.json*") { return "przypomnienie" }
  if ($p -match 'narzedzia[\\/]terminy\.js') { return "terminy" }     # przypomnienia z terminem (2026-10-05)
  if ($p -match 'mr-log\.js(?![A-Za-z0-9])')  { return "rejestr" }   # mr-log.js i megaruchacz-mr-log.js
  return $null
}

# Napis w JSON-ie, z ucieczkami jak w JSON.stringify: cudzyslow, ukosnik wsteczny
# i znaki sterujace; polskie litery i reszta ida wprost.
function Json-Tekst([string]$t) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  foreach ($c in $t.ToCharArray()) {
    $k = [int]$c
    if ($k -eq 34)     { [void]$sb.Append('\"') }
    elseif ($k -eq 92) { [void]$sb.Append('\\') }
    elseif ($k -eq 10) { [void]$sb.Append('\n') }
    elseif ($k -eq 13) { [void]$sb.Append('\r') }
    elseif ($k -eq 9)  { [void]$sb.Append('\t') }
    elseif ($k -eq 8)  { [void]$sb.Append('\b') }
    elseif ($k -eq 12) { [void]$sb.Append('\f') }
    elseif ($k -lt 32) { [void]$sb.Append(('\u{0:x4}' -f $k)) }
    else               { [void]$sb.Append($c) }
  }
  [void]$sb.Append('"')
  return $sb.ToString()
}

# Wartosc z ConvertFrom-Json z powrotem w JSON, w ukladzie JSON.stringify(x, null, 2).
function Do-Json($w, [string]$wciecie) {
  if ($null -eq $w) { return 'null' }
  if ($w -is [string]) { return (Json-Tekst $w) }
  if ($w -is [bool]) { if ($w) { return 'true' } else { return 'false' } }
  if ($w -is [int] -or $w -is [long] -or $w -is [decimal] -or $w -is [double] -or
      $w -is [single] -or $w -is [int16] -or $w -is [byte]) {
    return [System.Convert]::ToString($w, [System.Globalization.CultureInfo]::InvariantCulture)
  }
  $dalej = $wciecie + '  '
  if ($w -is [System.Collections.IDictionary]) {
    if ($w.Count -eq 0) { return '{}' }
    $czesci = @()
    foreach ($n in @($w.Keys)) { $czesci += ($dalej + (Json-Tekst "$n") + ': ' + (Do-Json $w[$n] $dalej)) }
    return "{`n" + ($czesci -join ",`n") + "`n" + $wciecie + "}"
  }
  if ($w -is [System.Collections.IList]) {
    if ($w.Count -eq 0) { return '[]' }
    $czesci = @()
    foreach ($e in $w) { $czesci += ($dalej + (Do-Json $e $dalej)) }
    return "[`n" + ($czesci -join ",`n") + "`n" + $wciecie + "]"
  }
  if ($w -is [System.Management.Automation.PSCustomObject]) {
    $nazwy = @($w.PSObject.Properties | ForEach-Object { $_.Name })
    if ($nazwy.Count -eq 0) { return '{}' }
    $czesci = @()
    foreach ($n in $nazwy) { $czesci += ($dalej + (Json-Tekst $n) + ': ' + (Do-Json $w.$n $dalej)) }
    return "{`n" + ($czesci -join ",`n") + "`n" + $wciecie + "}"
  }
  return (Json-Tekst ("" + $w))
}

# Plik ustawien razem z tym, co trzeba, zeby zapisac go w tym samym ukladzie: BOM
# (jest albo nie), konce linii, koncowy znak nowej linii. Nie-JSON rzuca wyjatek -
# wolajacy mowi o tym czlowiekowi i pliku nie rusza.
function Czytaj-Ustawienia($plik) {
  $u = [ordered]@{ s = [pscustomobject]@{}; bom = $false; nl = "`n"; koniec = "`n" }
  if (-not (Test-Path $plik)) { return $u }
  $bajty = [System.IO.File]::ReadAllBytes($plik)
  $u.bom = ($bajty.Length -ge 3 -and $bajty[0] -eq 0xEF -and $bajty[1] -eq 0xBB -and $bajty[2] -eq 0xBF)
  $raw = [System.IO.File]::ReadAllText($plik, [System.Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
  if ($raw.Contains("`r`n")) { $u.nl = "`r`n" }
  if ($raw.EndsWith("`n")) { $u.koniec = $u.nl } else { $u.koniec = "" }
  if ($raw.Trim().Length -gt 0) {
    $s = $raw | ConvertFrom-Json
    if (-not ($s -is [System.Management.Automation.PSCustomObject])) { throw "w pliku nie ma obiektu JSON" }
    $u.s = $s
  }
  return $u
}

function Zapisz-Ustawienia($plik, $u, $stempel) {
  $tekst = Do-Json $u.s ""
  if ($u.nl -ne "`n") { $tekst = $tekst.Replace("`n", $u.nl) }   # w napisach JSON-a nowych linii nie ma - sa \n
  $tekst += $u.koniec
  Kopia-Zapasowa $plik $stempel
  $katalog = Split-Path -Parent $plik
  if ($katalog -and -not (Test-Path $katalog)) { New-Item -ItemType Directory -Force -Path $katalog | Out-Null }
  [System.IO.File]::WriteAllText($plik, $tekst, (New-Object System.Text.UTF8Encoding($u.bom)))
}

# Dwa przebiegi straznika potrafia ruszyc naraz (hook globalny i projektowy na tym
# samym starcie sesji, dwa okna otwarte jednoczesnie). Bez blokady oba przeczytalyby
# plik, oba zapisaly - a kopia zapasowa drugiego bylaby juz kopia po zmianie.
function Pod-Blokada([scriptblock]$robota) {
  $m = New-Object System.Threading.Mutex($false, "Local\MegaRuchacz-hooki")
  $mam = $false
  try {
    try { $mam = $m.WaitOne(8000) }
    catch {
      # Porzucona blokada (poprzedni przebieg padl, trzymajac ja) jest juz nasza.
      $wew = $_.Exception
      while ($wew -and -not ($wew -is [System.Threading.AbandonedMutexException])) { $wew = $wew.InnerException }
      if (-not $wew) { throw }
      $mam = $true
    }
    if (-not $mam) { throw "inny przebieg straznika trzyma hooki od 8 s - tym razem nie ruszam" }
    return (& $robota)
  } finally {
    if ($mam) { $m.ReleaseMutex() }
    $m.Dispose()
  }
}

# Jeden komplet hookow MegaRuchacza w instalacji globalnej. "zasady" (stary wpis
# "cat ...megaruchacz-sesja.json") nie ma wzoru: zasady ida blokiem w ~\.claude\CLAUDE.md,
# wiec nowej instalacji go nie dokladamy - istniejacy zostaje, zdejmujemy tylko duplikaty.
# Od P59a komplet zalezy od rejestru instalacji: straznik (baza) zawsze; przypomnienie, gdy
# wlaczony ktorykolwiek z modulow, ktorych tresc dokleja (kierownik - ladunek, wiedza - linia
# cyklu, lore - "Z ARCHIWUM"); rejestr pracy workerow tylko przy kierowniku.
function Wzory-Hookow-Globalnych($zrodlo, $domClaude) {
  $r = $zrodlo.Replace("\","/").TrimEnd("/")
  $d = $domClaude.Replace("\","/").TrimEnd("/")
  $przyp = $d + "/mr/orchestrator-reminder.json"
  $log = $d + "/megaruchacz-mr-log.js"
  $straznik = 'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $r +
              '/narzedzia/straznik-zasad.ps1" -Zrodlo "' + $r + '" -Projekt "$CLAUDE_PROJECT_DIR" || true'
  $przypomnienie = 'node "' + $r + '/narzedzia/przypomnienie.js" "' + $przyp + '" || cat "' + $przyp + '"'
  $terminy = 'node "' + $r + '/narzedzia/terminy.js" start || true'
  $wzory = @()
  if ((Rodzaje-Hookow-Wylaczone) -notcontains "straznik") {
    $wzory += [pscustomobject]@{ zdarzenie = "SessionStart"; rodzaj = "straznik"
      hook = [pscustomobject]@{ type = "command"; command = $straznik; shell = "bash"; timeout = 15; statusMessage = "MegaRuchacz: straznik zasad" } }
  }
  # Przypomnienia z terminem (narzedzia\terminy.js start) - baza, jak straznik: zalegle sprawy
  # do kontekstu na starcie okna, bez zaleglych pusto. Osobny hook node'a, a nie linia straznika,
  # bo tresc przypomnien ma polskie litery, a wyjscie PowerShella 5.1 idzie w stronie kodowej konsoli.
  if ((Rodzaje-Hookow-Wylaczone) -notcontains "terminy") {
    $wzory += [pscustomobject]@{ zdarzenie = "SessionStart"; rodzaj = "terminy"
      hook = [pscustomobject]@{ type = "command"; command = $terminy; shell = "bash"; timeout = 5; statusMessage = "MegaRuchacz: przypomnienia z terminem" } }
  }
  if ((Rodzaje-Hookow-Wylaczone) -notcontains "przypomnienie") {
    $wzory += [pscustomobject]@{ zdarzenie = "UserPromptSubmit"; rodzaj = "przypomnienie"
      hook = [pscustomobject]@{ type = "command"; command = $przypomnienie; shell = "bash"; timeout = 5 } }
  }
  if ((Rodzaje-Hookow-Wylaczone) -notcontains "rejestr") {
    $wzory += [pscustomobject]@{ zdarzenie = "SubagentStart"; rodzaj = "rejestr"
      hook = [pscustomobject]@{ type = "command"; command = ('node "' + $log + '"'); timeout = 5; statusMessage = "MegaRuchacz: wpis do rejestru pracy" } }
    $wzory += [pscustomobject]@{ zdarzenie = "SubagentStop"; rodzaj = "rejestr"
      hook = [pscustomobject]@{ type = "command"; command = ('node "' + $log + '" stop'); timeout = 5; statusMessage = "MegaRuchacz: wpis do rejestru pracy" } }
  }
  return $wzory
}

# Rodzaje NASZYCH hookow globalnych, ktore maja zniknac, bo ich moduly sa wylaczone w rejestrze
# (Rodzaj-Hooka). Rejestr nieczytelny albo go brak = pusta lista - wtedy nic nie znika.
# Hook straznika nalezy do bazy: znika tylko przy "baza": false (usuniety caly MegaRuchacz, P64) -
# inaczej skrypty modulow wolane przy sprzataniu po odinstalowaniu (-NaprawGlobalne) kladlyby go z powrotem.
function Rodzaje-Hookow-Wylaczone {
  $w = @()
  if ((Modul-Wylaczony "kierownik") -and (Modul-Wylaczony "wiedza") -and (Modul-Wylaczony "lore")) { $w += "przypomnienie" }
  if (Modul-Wylaczony "kierownik") { $w += "rejestr" }
  if (Baza-Usunieta) { $w += @("straznik", "terminy") }
  return $w
}

# Rejestr czytelny i z "baza": false - slad po usunieciu calego MegaRuchacza (stan.ps1, P64).
function Baza-Usunieta {
  return ((-not $script:Instalacja.blad) -and ($script:Instalacja.zrodlo -eq "plik") -and ($script:Instalacja.baza -eq $false))
}

function Wzor-Dla($wzory, $zdarzenie, $rodzaj) {
  foreach ($w in @($wzory)) {
    if ($null -ne $w -and $w.zdarzenie -eq $zdarzenie -and $w.rodzaj -eq $rodzaj) { return $w }
  }
  return $null
}

# Porzadkuje NASZE hooki w obiekcie ustawien (zmienia $s w miejscu):
#   - z kazdego rodzaju na danym zdarzeniu zostaje JEDEN wpis - najchetniej ten,
#     ktory juz jest identyczny ze wzorem, inaczej pierwszy, i ten dostaje postac wzoru,
#   - pozostale nasze tego rodzaju znikaja; grupa, ktora zostala pusta, znika cala,
#   - brakujace wzgledem wzoru dokladamy na koncu zdarzenia,
#   - $usun = zdejmij wszystkie nasze, niczego nie dokladaj,
#   - $doZdjecia = rodzaje zdejmowane mimo braku $usun (moduly wylaczone w rejestrze instalacji).
# Cudzych wpisow (Rodzaj-Hooka = $null) i cudzych grup nie dotykamy wcale - zostaja
# tymi samymi obiektami, wiec Do-Json wypisze je dokladnie tak, jak byly.
function Uporzadkuj-Hooki($s, $wzory, [bool]$usun, [string[]]$doZdjecia = @()) {
  $wynik = [ordered]@{ Usuniete = @(); Dodane = @(); Poprawione = @() }
  $maHooki = ($s.PSObject.Properties.Name -contains "hooks") -and ($null -ne $s.hooks)
  if (-not $maHooki) {
    if ($usun -or @($wzory).Count -eq 0) { return $wynik }
    $s | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) -Force
  }
  $zdarzenia = @($s.hooks.PSObject.Properties | ForEach-Object { $_.Name })

  # Przebieg 1 - ktory wpis kazdego rodzaju zostaje. Pozycja zamiast referencji:
  # porownywanie obiektow PSObject po referencji w PowerShellu bywa zdradliwe.
  $wybrane = @{}
  foreach ($z in $zdarzenia) {
    $grupy = @($s.hooks.$z)
    for ($gi = 0; $gi -lt $grupy.Count; $gi++) {
      $g = $grupy[$gi]
      if ($null -eq $g -or -not ($g.PSObject.Properties.Name -contains "hooks")) { continue }
      $hs = @($g.hooks)
      for ($hi = 0; $hi -lt $hs.Count; $hi++) {
        $rodzaj = Rodzaj-Hooka $hs[$hi]
        if (-not $rodzaj) { continue }
        $klucz = "$z|$rodzaj"
        $wzor = Wzor-Dla $wzory $z $rodzaj
        $zgodny = ($null -ne $wzor) -and ((Do-Json $hs[$hi] "") -ceq (Do-Json $wzor.hook ""))
        if (-not $wybrane.ContainsKey($klucz) -or ($zgodny -and -not $wybrane[$klucz].zgodny)) {
          $wybrane[$klucz] = @{ poz = "$gi|$hi"; zgodny = $zgodny }
        }
      }
    }
  }

  # Przebieg 2 - zdejmowanie duplikatow i podmiana wybranego na wzor.
  foreach ($z in $zdarzenia) {
    $grupy = @($s.hooks.$z)
    $noweGrupy = @()
    $zmianaZdarzenia = $false
    for ($gi = 0; $gi -lt $grupy.Count; $gi++) {
      $g = $grupy[$gi]
      if ($null -eq $g -or -not ($g.PSObject.Properties.Name -contains "hooks")) { $noweGrupy += ,$g; continue }
      $hs = @($g.hooks)
      $noweHooki = @()
      $zmianaGrupy = $false
      for ($hi = 0; $hi -lt $hs.Count; $hi++) {
        $h = $hs[$hi]
        $rodzaj = Rodzaj-Hooka $h
        if (-not $rodzaj) { $noweHooki += ,$h; continue }
        $klucz = "$z|$rodzaj"
        # "zasady" (cat ...megaruchacz-sesja.json) w trybie globalnym zdejmujemy:
        # zasady kierownika ida blokiem w ~\.claude\CLAUDE.md. Od 0.21.0 ten blok
        # to wersja dla Claude Code (szablony-global\claude\zasady-kierownika.md),
        # wiec hook bylby prawdziwym duplikatem. UWAGA na historie: od 2026-09-24
        # do 0.21.0 blok mial wersje opencode/Codex i ten hook NIE byl duplikatem,
        # tylko jedyna wersja dla Claude Code - patrz raport P5.
        if ($usun -or $rodzaj -eq "zasady" -or ($doZdjecia -contains $rodzaj) -or $wybrane[$klucz].poz -ne "$gi|$hi") {
          $wynik.Usuniete += "$z/$rodzaj"
          $zmianaGrupy = $true
          continue
        }
        $wzor = Wzor-Dla $wzory $z $rodzaj
        if ($null -ne $wzor -and -not $wybrane[$klucz].zgodny) {
          $noweHooki += ,$wzor.hook
          $wynik.Poprawione += "$z/$rodzaj"
          $zmianaGrupy = $true
          continue
        }
        $noweHooki += ,$h
      }
      if (-not $zmianaGrupy) { $noweGrupy += ,$g; continue }
      $zmianaZdarzenia = $true
      if ($noweHooki.Count -eq 0) { continue }
      $g.hooks = @($noweHooki)
      $noweGrupy += ,$g
    }
    if (-not $zmianaZdarzenia) { continue }
    if ($noweGrupy.Count -eq 0) { [void]$s.hooks.PSObject.Properties.Remove($z) }
    else { $s.hooks.$z = @($noweGrupy) }
  }

  # Przebieg 3 - brakujace.
  if (-not $usun) {
    foreach ($w in @($wzory)) {
      if ($null -eq $w) { continue }
      if ($wybrane.ContainsKey("$($w.zdarzenie)|$($w.rodzaj)")) { continue }
      $grupa = [pscustomobject]@{ hooks = @($w.hook) }
      if ($s.hooks.PSObject.Properties.Name -contains $w.zdarzenie) {
        $s.hooks.($w.zdarzenie) = @($s.hooks.($w.zdarzenie)) + ,$grupa
      } else {
        $s.hooks | Add-Member -NotePropertyName $w.zdarzenie -NotePropertyValue @($grupa) -Force
      }
      $wynik.Dodane += "$($w.zdarzenie)/$($w.rodzaj)"
    }
  }
  return $wynik
}

function Opis-Zmian-Hookow($wynik, [string]$slowoUsuniete) {
  $czesci = @()
  if (@($wynik.Usuniete).Count -gt 0)   { $czesci += ($slowoUsuniete + ": " + (@($wynik.Usuniete) -join ", ")) }
  if (@($wynik.Poprawione).Count -gt 0) { $czesci += ("podmienione na aktualne: " + (@($wynik.Poprawione) -join ", ")) }
  if (@($wynik.Dodane).Count -gt 0)     { $czesci += ("dolozone: " + (@($wynik.Dodane) -join ", ")) }
  return ($czesci -join "; ")
}

# Pliki, ktore wolaja hooki globalne: rejestr i ladunek przypomnienia. Hook wskazujacy
# na nieistniejacy plik sypalby bledem przy kazdym workerze albo kazdej wiadomosci,
# wiec dokladamy je (i odswiezamy z kopia zapasowa) razem z hookami. Oba naleza do modulu
# kierownik - przy wylaczonym ich nie dokladamy (przypomnienie.js ladunku wtedy nie czyta,
# a zdjecie samych plikow to robota odinstalowania modulu, nie straznika).
function Odswiez-Pliki-Globalne($domClaude, $stempel) {
  if (Modul-Wylaczony "kierownik") { return @() }
  $pary = @(
    @((Join-Path $Zrodlo "szablony-global\claude\mr-log.js"), (Join-Path $domClaude "megaruchacz-mr-log.js")),
    @((Join-Path $Zrodlo ".claude\orchestrator-reminder.json"), (Join-Path $domClaude "mr\orchestrator-reminder.json"))
  )
  $zmienione = @()
  foreach ($p in $pary) {
    if (-not (Test-Path $p[0])) { Mow "MegaRuchacz: brak szablonu $($p[0]) - hook globalny wola plik, ktorego nie mam skad wziac."; continue }
    $rozne = (-not (Test-Path $p[1])) -or ((Czytaj-Tekst $p[1]) -cne (Czytaj-Tekst $p[0]))
    if (-not $rozne) { continue }
    $zmienione += (Split-Path -Leaf $p[1])
    if ($Proba) { continue }
    $kat = Split-Path -Parent $p[1]
    if (-not (Test-Path $kat)) { New-Item -ItemType Directory -Force -Path $kat | Out-Null }
    Kopia-Zapasowa $p[1] $stempel
    Copy-Item $p[0] $p[1] -Force
  }
  return $zmienione
}

# Naprawa (albo z $usun - zdjecie) hookow MegaRuchacza w ~\.claude\settings.json.
# Zwraca $true, gdy hooki globalne sa w porzadku; $false, gdy pliku nie dalo sie
# ruszyc - wtedy NIE wolno zdejmowac hookow projektowych, bo projekt zostalby bez zadnych.
function Napraw-Hooki-Globalne([bool]$usun) {
  $domClaude = Join-Path $KatalogDomowy ".claude"
  $plik = Join-Path $domClaude "settings.json"
  $stempel = Get-Date -Format "yyyyMMdd-HHmmss"
  $pliki = @()
  if (-not $usun) { $pliki = @(Odswiez-Pliki-Globalne $domClaude $stempel) }
  if ($pliki.Count -gt 0) {
    if ($Proba) { Mow ("PROBA  odswiezylbym w ~\.claude: " + ($pliki -join ", ")) }
    else { Mow ("MegaRuchacz: odswiezone pliki instalacji globalnej w ~\.claude: " + ($pliki -join ", ") + " (kopie .bak-${stempel} obok).") }
  }
  return (Pod-Blokada {
    try { $u = Czytaj-Ustawienia $plik }
    catch {
      Mow "MegaRuchacz: $plik nie jest czystym JSON-em - hookow globalnych nie ruszam ($($_.Exception.Message))."
      return $false
    }
    $wzory = @()
    $wylaczone = @()
    if (-not $usun) {
      $wzory = @(Wzory-Hookow-Globalnych $Zrodlo $domClaude)
      $wylaczone = @(Rodzaje-Hookow-Wylaczone)
    }
    $wynik = Uporzadkuj-Hooki $u.s $wzory $usun $wylaczone
    $slowo = if ($usun) { "zdjete" } elseif ($wylaczone.Count -gt 0) { "zdjete duplikaty i hooki modulow wylaczonych w rejestrze instalacji" } else { "usuniete duplikaty" }
    $opis = Opis-Zmian-Hookow $wynik $slowo
    if (-not $opis) { Notuj "hooki globalne: bez zmian"; return $true }
    if ($Proba) { Mow "PROBA  $plik - $opis"; return $true }
    Zapisz-Ustawienia $plik $u $stempel
    Mow "MegaRuchacz: hooki MegaRuchacza w $plik uporzadkowane ($opis) - zadziala od nastepnej sesji; cudze wpisy nietkniete, kopia: settings.json.bak-${stempel}."
    return $true
  })
}

# Przy instalacji globalnej hooki MegaRuchacza w projekcie sa duplikatem: to one
# sprawialy, ze przypomnienie szlo dwa razy. Zdejmujemy tylko NASZE (Rodzaj-Hooka),
# z kopia zapasowa i jedna linia dla czlowieka; cudze hooki i reszta pliku zostaja.
function Usun-Hooki-Projektowe {
  if (-not (Projekt-Bez-Hookow $Projekt)) { return }
  $plik = Join-Path $Projekt ".claude\settings.json"
  if (-not (Test-Path $plik)) { return }
  # Sesja otwarta w katalogu domowym: projektowy .claude\settings.json to wtedy TEN
  # SAM plik co globalny - zdjelibysmy dokladnie te hooki, ktore maja zostac.
  $globalny = Join-Path $KatalogDomowy ".claude\settings.json"
  if ([System.IO.Path]::GetFullPath($plik) -ieq [System.IO.Path]::GetFullPath($globalny)) { return }
  $stempel = Get-Date -Format "yyyyMMdd-HHmmss"
  [void](Pod-Blokada {
    try { $u = Czytaj-Ustawienia $plik }
    catch {
      Mow "MegaRuchacz: $plik nie jest czystym JSON-em - zdublowanych hookow projektowych nie zdejmuje ($($_.Exception.Message))."
      return $false
    }
    $wynik = Uporzadkuj-Hooki $u.s @() $true
    $ile = @($wynik.Usuniete).Count
    if ($ile -eq 0) { return $true }
    if ($Proba) { Mow ("PROBA  $plik - zdjalbym $ile hookow MegaRuchacza: " + (@($wynik.Usuniete) -join ", ")); return $true }
    Zapisz-Ustawienia $plik $u $stempel
    Mow ("MegaRuchacz: dziala instalacja globalna, wiec z .claude\settings.json tego projektu zdjalem " +
         "$ile hookow MegaRuchacza, ktore ja dublowaly (" + (@($wynik.Usuniete) -join ", ") +
         ") - kopia: settings.json.bak-${stempel}. Z powrotem: wdroz.ps1 -WymusProjektowo.")
    return $true
  })
}

# Przy KAZDYM przebiegu, gdy stoi instalacja globalna: najpierw hooki globalne, potem
# - tylko jesli te sa w porzadku - zdjecie duplikatow z projektu.
function Pilnuj-Hookow-Globalnych {
  if (-not (Jest-Globalna)) { return }
  if (-not (Napraw-Hooki-Globalne $false)) { return }
  Usun-Hooki-Projektowe
}

# ------------------------------------------------- 0. swiezosc kopii narzedzia
# Wola gita w osobnym procesie, zeby dalo sie nalozyc limit czasu - straznik
# chodzi przy KAZDYM otwarciu okna i nie ma prawa czekac na gluche polaczenie.
# Zwraca .ok (kod wyjscia 0 i zdazyl) oraz .tekst (wyjscie bez bialych znakow).
# Od P36 takze .surowy (wyjscie co do znaku - listy z -z, w ktorych nic nie wolno
# przycinac), .blad (stderr gita - z niego bierze sie powod odmowy) i .kod
# (kod wyjscia; $null = git nie zdazyl albo nie ruszyl).
function Wolaj-Gita([string]$argumenty, [int]$sekundy) {
  $wynik = [ordered]@{ ok = $false; tekst = ""; surowy = ""; blad = ""; kod = $null }
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
      $wynik.blad = "git nie zdazyl w $sekundy s"
      try { $p.Kill() } catch { $wynik.blad += " i nie dal sie zatrzymac ($($_.Exception.Message))" }
      return $wynik
    }
    $p.WaitForExit()
    $wynik.kod = $p.ExitCode
    $e = [System.IO.File]::ReadAllText($bl)
    if ($e) { $wynik.blad = $e.Trim() }
    if ($p.ExitCode -eq 0) {
      $wynik.ok = $true
      $t = [System.IO.File]::ReadAllText($wy)
      if ($t) { $wynik.surowy = $t; $wynik.tekst = $t.Trim() }
    }
  } catch { $wynik.blad = "nie udalo sie zawolac gita: $($_.Exception.Message)" }
  finally { Remove-Item $wy, $bl -Force -ErrorAction SilentlyContinue }
  return $wynik
}

# Pliki robocze narzedzia w jego WLASNYM repo. Pisze je praca, a nie autor narzedzia:
# rejestr (hooki START/KONIEC i kierownik - kazda maszyna swoj), raporty workerow
# i to, co wdroz.ps1 i straznik zakladaja w projekcie, gdy projektem jest samo repo
# narzedzia. Do P36 kazdy z nich trzymal repo w stanie "niezapisane zmiany", a straznik
# odmawial wtedy pobrania - na zawsze, bo rejestr dopisuje sie przy kazdym workerze.
# Teraz przewiniecie odklada je do kopii i oddaje dokladnie takie, jakie byly, takze
# gdy nowa wersja przestaje je sledzic (git skasowalby je wtedy z dysku).
# Wzory dla -like, sciezki wzgledem korzenia repo, ukosnik "/".
# Mapy (.megaruchacz/mapa.md) tu NIE ma z premedytacja: to wspolna, sledzona wiedza
# o projekcie - jej lokalna zmiana jest czyjas praca i blokuje tak samo jak kod.
$WZORY_PLIKOW_ROBOCZYCH = @(
  ".megaruchacz/worklog.md",
  ".megaruchacz/raporty/*",
  ".megaruchacz/wersja.txt",
  ".megaruchacz/zasady-kierownika.md",
  ".megaruchacz/zasady-sesja.json",
  ".megaruchacz/przypomnienie.json",
  ".claude/megaruchacz-wersja.txt",
  ".claude/megaruchacz-zasady.md",
  ".claude/megaruchacz-sesja.json",
  ".codex/*",
  ".opencode/*"
)
# Ile nazw plikow miesci jedno zdanie o odmowie. Zdanie idzie do okna rozmowy i do
# dziennika, a lista potrafi miec dziesiatki pozycji - reszta dostaje licznik, a komplet
# lezy w pliku stanu (klucz aktualizacja.pliki), wiec nic nie znika bez slowa.
$PLIKOW_W_ZDANIU = 8
# Koncowka nazwy, pod ktora plik roboczy przeczekuje (w tym samym katalogu, wiec
# przemianowanie jest niepodzielne) chwile miedzy zdjeciem z dysku a skopiowaniem.
$KONCOWKA_ZDJETEGO = ".megaruchacz-zdjety"

function Jest-Plikiem-Roboczym([string]$sciezka) {
  foreach ($w in $WZORY_PLIKOW_ROBOCZYCH) { if ($sciezka -like $w) { return $true } }
  return $false
}

# Wpisy z wyjscia gita z -z (NUL miedzy wpisami) - sciezki co do znaku, bez
# cudzyslowow i kodow \ooo, ktorymi git zastepuje polskie litery w zwyklym wyjsciu.
function Wpisy-Z-Gita([string]$surowy) {
  if (-not $surowy) { return @() }
  return @($surowy.Split([char]0) | Where-Object { $_ -ne "" })
}

function Sciezka-W-Zrodle([string]$wzgledna) {
  return (Join-Path $Zrodlo ($wzgledna -replace '/', '\'))
}

function Sciezka-W-Kopii([string]$kat, [string]$wzgledna) {
  return (Join-Path $kat ("pliki\" + ($wzgledna -replace '/', '\')))
}

# Skrot tresci pliku ("" = pliku nie ma). Czytamy, pozwalajac innym pisac: hook
# potrafi akurat dopisywac linie do rejestru, a blokada wywrocilaby cale pobranie.
function Skrot-Pliku([string]$sciezka) {
  if (-not (Test-Path -LiteralPath $sciezka -PathType Leaf)) { return "" }
  $md5 = [System.Security.Cryptography.MD5]::Create()
  $s = [System.IO.File]::Open($sciezka, 'Open', 'Read', 'ReadWrite')
  try { return [System.BitConverter]::ToString($md5.ComputeHash($s)).Replace("-","") }
  finally { $s.Dispose(); $md5.Dispose() }
}

# Kopia bajt w bajt, potwierdzona skrotem - dopiero taka upowaznia do ruszenia
# oryginalu. Rzuca, gdy sie nie zgadza: wtedy nikt niczego nie rusza.
function Kopiuj-Na-Pewno([string]$skad, [string]$dokad) {
  [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($dokad))
  [System.IO.File]::Copy($skad, $dokad, $true)
  if ((Skrot-Pliku $skad) -ne (Skrot-Pliku $dokad)) { throw "kopia $dokad nie zgadza sie z $skad" }
}

# Czy plik lezy dokladnie tak, jak zna go git (sledzony, bez zmian wobec HEAD).
# Tylko taki wolno nadpisac kopia - jego tresc i tak zostaje w historii.
function Czysty-W-Gicie($cyt, [string]$sciezka) {
  $s = Wolaj-Gita "-C $cyt --literal-pathspecs ls-files -z -- `"$sciezka`"" $CZAS_GIT
  if (-not $s.ok -or -not (Wpisy-Z-Gita $s.surowy)) { return $false }
  $z = Wolaj-Gita "-C $cyt --literal-pathspecs diff --name-only -z HEAD -- `"$sciezka`"" $CZAS_GIT
  return ($z.ok -and -not (Wpisy-Z-Gita $z.surowy))
}

function Lista-Do-Zdania($pliki) {
  $l = @($pliki)
  if ($l.Count -le $PLIKOW_W_ZDANIU) { return ($l -join ", ") }
  return ((@($l | Select-Object -First $PLIKOW_W_ZDANIU) -join ", ") +
          " i jeszcze $($l.Count - $PLIKOW_W_ZDANIU) (komplet: $plikStanu, klucz aktualizacja.pliki)")
}

# Zdanie o pobraniu, na ktore czlowiek ma zareagowac. Pod Claude Code idzie od razu na
# ekran i zdejmuje taka sama prosbe odlozona wczesniej przez tryb -Tlo (np. po kliknieciu
# w oknie nadzorcy) - inaczej przy tym samym otwarciu okna padlaby dwa razy. W -Tlo
# czeka w pliku stanu na przebieg, ktory ma komu mowic (pod Codeksem: ladunek -KosztCodex).
function Powiedz-Wazne([string]$zdanie) {
  Mow $zdanie
  if ($Tlo) { Odloz-Wiadomosc $zdanie; return }
  try {
    $stan = Czytaj-Klucze $plikStanu
    $zdjete = $false
    foreach ($k in @($stan.Keys)) {
      if ($k -match '^mow\.\d+$' -and "$($stan[$k])" -eq $zdanie) { $stan.Remove($k); $zdjete = $true }
    }
    if ($zdjete) { Zapisz-Klucze $plikStanu $stan }
  } catch { Zanotuj-Wywrotke "zdjecie odlozonej prosby o pobraniu" $_ }
}

# Wynik ostatniej prawdziwej proby pobrania - w pliku stanu straznika, zeby okno
# nadzorcy (przycisk pobierania) moglo powiedziec DLACZEGO, zamiast zgadywac z dziennika.
# Klucze aktualizacja.* zawsze z jednej proby: pliki i kopia z poprzedniej nie maja
# prawa wisiec przy nowym wyniku.
#   kiedy, zrodlo - kiedy i ktory katalog zrodlowy
#   wynik  - pobrane | aktualne | zablokowane | rozjechane | nieudane | kopia
#            | bez-sieci | bez-zdalnej | nie-repo | bez-gita
#   powod  - to samo zdanie, ktore poszlo do czlowieka albo do dziennika
#   pliki  - pelna lista plikow, przez ktore git odmowil (zablokowane, nieudane)
#   kopia  - katalog z kopia plikow roboczych, ktorej nie dalo sie oddac
function Zapisz-Wynik-Pobrania([string]$wynik, [string]$powod, $pliki = @(), [string]$kopia = "") {
  try {
    $stan = Czytaj-Klucze $plikStanu
    foreach ($k in @($stan.Keys)) { if ($k -like "aktualizacja.*") { $stan.Remove($k) } }
    $stan["aktualizacja.kiedy"]  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    $stan["aktualizacja.zrodlo"] = $Zrodlo
    $stan["aktualizacja.wynik"]  = $wynik
    $stan["aktualizacja.powod"]  = ($powod -replace '[\r\n]+', ' ')
    if (@($pliki).Count -gt 0) { $stan["aktualizacja.pliki"] = (@($pliki) -join ", ") }
    if ($kopia) { $stan["aktualizacja.kopia"] = $kopia }
    Zapisz-Klucze $plikStanu $stan
  } catch { Zanotuj-Wywrotke "zapis wyniku pobrania do pliku stanu" $_ }
}

# Co przewiniecie zrobi z plikami na dysku - z tych samych danych, ktore sprawdza
# git merge --ff-only, zanim odmowi: ktore sciezki zmienia nowa wersja (HEAD..@{u})
# i ktore maja u nas zmiany. Tu nic sie nie rozstrzyga - odmawia git; plan mowi, co
# odlozyc do kopii i jak po ludzku nazwac to, przez co git odmowil.
#   robocze   - pliki robocze na drodze nowej wersji: "wlasny" (tresc tej maszyny,
#               ktorej w gicie nie ma - wraca zawsze) albo "kasowany" (czysty, ale
#               nowa wersja go usuwa - wraca, gdy go zabraknie),
#   zmienione - Twoje zmiany w plikach, ktore zmienia tez nowa wersja,
#   obce      - pliki spoza gita tam, gdzie nowa wersja kladzie swoje,
#   dodane    - zmiany przygotowane do zapisu (git add) w tych plikach.
function Plan-Przewiniecia($cyt) {
  $plan = [ordered]@{ ok = $false; powod = ""; robocze = @(); zmienione = @(); obce = @(); dodane = @() }
  $przych = Wolaj-Gita "-C $cyt diff --name-status -z --no-renames HEAD @{u}" $CZAS_GIT
  $lokal  = Wolaj-Gita "-C $cyt diff --name-only -z HEAD" $CZAS_GIT
  $indeks = Wolaj-Gita "-C $cyt diff --name-only -z --cached" $CZAS_GIT
  $sledz  = Wolaj-Gita "-C $cyt ls-files -z" $CZAS_GIT
  foreach ($w in @($przych, $lokal, $indeks, $sledz)) {
    if (-not $w.ok) { $plan.powod = "git nie powiedzial, co zmienia nowa wersja ($($w.blad))"; return $plan }
  }
  $zmienioneU = @{}; foreach ($s in (Wpisy-Z-Gita $lokal.surowy))  { $zmienioneU[$s] = $true }
  $wIndeksie  = @{}; foreach ($s in (Wpisy-Z-Gita $indeks.surowy)) { $wIndeksie[$s] = $true }
  $sledzone   = @{}; foreach ($s in (Wpisy-Z-Gita $sledz.surowy))  { $sledzone[$s] = $true }
  $wpisy = @(Wpisy-Z-Gita $przych.surowy)
  for ($i = 0; $i + 1 -lt $wpisy.Count; $i += 2) {
    $stan = $wpisy[$i]
    $p = $wpisy[$i + 1]
    if ($wIndeksie.ContainsKey($p)) { $plan.dodane += $p; continue }
    $pelna = Sciezka-W-Zrodle $p
    if (-not (Test-Path -LiteralPath $pelna)) { continue }   # nie ma na dysku - nie ma czego stracic
    $sledzony = $sledzone.ContainsKey($p)
    $zmieniony = $zmienioneU.ContainsKey($p)
    if ((Jest-Plikiem-Roboczym $p) -and (Test-Path -LiteralPath $pelna -PathType Leaf)) {
      if ((-not $sledzony) -or $zmieniony) { $plan.robocze += [pscustomobject]@{ tryb = "wlasny"; sciezka = $p } }
      elseif ($stan -eq "D") { $plan.robocze += [pscustomobject]@{ tryb = "kasowany"; sciezka = $p } }
      continue
    }
    if (-not $sledzony) { $plan.obce += $p }
    elseif ($zmieniony) { $plan.zmienione += $p }
  }
  $plan.ok = $true
  return $plan
}

# Kopie plikow roboczych - poza repo (przewiniecie ich nie dosiegnie), osobno dla
# kazdego katalogu zrodlowego (ten sam skrot, co w znaczniku pobrania), kazda proba
# we wlasnym podkatalogu ze spisem: "wlasny|sciezka", "kasowany|sciezka", a przed
# zdjeciem pliku z dysku dopisane "zdjety|sciezka". Ze spisu oddajemy pliki takze po
# przebiegu, ktory padl w polowie (hook ubity po 15 s, wylaczony komputer).
function Katalog-Kopii-Zrodla {
  return (Join-Path $KatalogDomowy (".claude\.megaruchacz-kopia-zrodla\z" + (Skrot $Zrodlo.ToLower())))
}

function Odloz-Robocze($robocze) {
  $kat = Join-Path (Katalog-Kopii-Zrodla) (Get-Date -Format "yyyyMMdd-HHmmss-fff")
  try {
    $spis = @("zrodlo|$Zrodlo")
    foreach ($r in $robocze) {
      Kopiuj-Na-Pewno (Sciezka-W-Zrodle $r.sciezka) (Sciezka-W-Kopii $kat $r.sciezka)
      $spis += ($r.tryb + "|" + $r.sciezka)
    }
    # Spis na samym koncu: katalog bez spisu to kopia niedokonczona - oryginaly sa
    # wtedy nietkniete, wiec Dokoncz-Przerwane moze ja po prostu usunac.
    Zapisz-Tekst (Join-Path $kat "spis.txt") (($spis -join "`r`n") + "`r`n")
  } catch {
    if (Test-Path -LiteralPath $kat) { Remove-Item -LiteralPath $kat -Recurse -Force -ErrorAction SilentlyContinue }
    throw
  }
  return $kat
}

function Czytaj-Spis([string]$kat) {
  $spis = [ordered]@{ wpisy = @(); zdjete = @{} }
  $raw = Czytaj-Tekst (Join-Path $kat "spis.txt")
  foreach ($l in (("" + $raw) -split '\r?\n')) {
    $cz = $l -split '\|', 2
    if ($cz.Count -ne 2 -or -not $cz[1]) { continue }
    if ($cz[0] -eq "wlasny" -or $cz[0] -eq "kasowany") { $spis.wpisy += [pscustomobject]@{ tryb = $cz[0]; sciezka = $cz[1] } }
    elseif ($cz[0] -eq "zdjety") { $spis.zdjete[$cz[1]] = $true }
  }
  return $spis
}

# Zdejmuje z drogi wlasne pliki robocze, przez ktore git odmowil: skasowany plik
# sledzony nie blokuje przewiniecia (git uznaje, ze nie ma czego stracic), a plik
# spoza gita przestaje zawadzac. "zdjety" trafia do spisu PRZED ruszeniem pliku, a sam
# plik najpierw zmienia nazwe (niepodzielnie) i dopiero potem idzie do kopii - linia,
# ktora hook dopisalby w tej chwili, wyladuje w nowym pliku, a nie w nicosci.
function Zdejmij-Robocze($kat, $robocze) {
  $spis = Join-Path $kat "spis.txt"
  foreach ($r in $robocze) {
    if ($r.tryb -ne "wlasny") { continue }
    $pelna = Sciezka-W-Zrodle $r.sciezka
    $obok = $pelna + $KONCOWKA_ZDJETEGO
    [System.IO.File]::AppendAllText($spis, ("zdjety|" + $r.sciezka + "`r`n"), (Bez-Bom))
    [System.IO.File]::Move($pelna, $obok)
    Kopiuj-Na-Pewno $obok (Sciezka-W-Kopii $kat $r.sciezka)
    [System.IO.File]::Delete($obok)
  }
}

# Oddaje pliki robocze z kopii - po przewinieciu, po odmowie i po przebiegu, ktory padl
# w polowie; zawsze ta sama regula, zeby zadna droga nie mogla niczego zgubic:
#   - pliku nie ma -> wraca z kopii (git go skasowal albo sami go zdjelismy),
#   - lezy taki sam jak w kopii -> nic do roboty,
#   - zdjelismy go, a teraz lezy wersja znana gitowi (przewiniecie wpisalo swoja) ->
#     wraca tresc tej maszyny, a tamta zostaje w historii,
#   - zdjelismy go, a lezy cos innego (np. hook zalozyl rejestr od nowa) -> NIE
#     nadpisujemy, kopia zostaje na dysku i straznik mowi, gdzie jej szukac,
#   - nie ruszalismy go, a jest inny niz w kopii -> to zywy plik; kopia jest zbedna.
# Kopia znika dopiero, gdy wszystko lezy na miejscu. Zwraca to, czego nie oddal.
function Oddaj-Robocze($cyt, [string]$kat) {
  $spis = Czytaj-Spis $kat
  $nieOddane = @()
  foreach ($w in $spis.wpisy) {
    $pelna = Sciezka-W-Zrodle $w.sciezka
    $kopia = Sciezka-W-Kopii $kat $w.sciezka
    $zdjety = $spis.zdjete.ContainsKey($w.sciezka)
    try {
      # Przebieg padl miedzy zmiana nazwy a skopiowaniem - najswiezsza tresc lezy obok.
      $obok = $pelna + $KONCOWKA_ZDJETEGO
      if ($zdjety -and (Test-Path -LiteralPath $obok -PathType Leaf)) {
        Kopiuj-Na-Pewno $obok $kopia
        [System.IO.File]::Delete($obok)
      }
      if (-not (Test-Path -LiteralPath $kopia -PathType Leaf)) { $nieOddane += "$($w.sciezka) (w kopii go nie ma)"; continue }
      if (-not (Test-Path -LiteralPath $pelna)) { Kopiuj-Na-Pewno $kopia $pelna; continue }
      if ((Skrot-Pliku $pelna) -eq (Skrot-Pliku $kopia)) { continue }
      if ($zdjety -and $w.tryb -eq "wlasny") {
        if (Czysty-W-Gicie $cyt $w.sciezka) { Kopiuj-Na-Pewno $kopia $pelna }
        else { $nieOddane += $w.sciezka }
      }
    } catch { $nieOddane += "$($w.sciezka) ($($_.Exception.Message))" }
  }
  if ($nieOddane.Count -eq 0) {
    try {
      Remove-Item -LiteralPath $kat -Recurse -Force
      # Puste katalogi nad kopia tez znikaja - po udanym pobraniu nie zostaje sladu.
      $baza = Split-Path -Parent $kat
      foreach ($k in @($baza, (Split-Path -Parent $baza))) {
        if (-not @(Get-ChildItem -LiteralPath $k -Force)) { Remove-Item -LiteralPath $k -Force }
      }
    } catch { Zanotuj-Wywrotke "sprzatanie kopii plikow roboczych" $_ }
  }
  return $nieOddane
}

# Kopie po przebiegu, ktory padl w polowie. Katalog bez spisu to kopia niedokonczona
# (oryginaly byly wtedy nietkniete) - do kosza. Ze spisem - oddajemy jak po przewinieciu.
# Zwraca kopie, ktorych nie dalo sie oddac bez nadpisania innej tresci.
function Dokoncz-Przerwane($cyt) {
  $baza = Katalog-Kopii-Zrodla
  if (-not (Test-Path -LiteralPath $baza)) { return @() }
  $zostalo = @()
  foreach ($kat in @(Get-ChildItem -LiteralPath $baza -Directory)) {
    if (-not (Test-Path -LiteralPath (Join-Path $kat.FullName "spis.txt"))) {
      Remove-Item -LiteralPath $kat.FullName -Recurse -Force
      continue
    }
    Notuj "zrodlo: oddaje pliki robocze z kopii po przerwanym pobraniu ($($kat.FullName))"
    $nie = @(Oddaj-Robocze $cyt $kat.FullName)
    if ($nie.Count -gt 0) { $zostalo += [pscustomobject]@{ kat = $kat.FullName; pliki = $nie } }
  }
  return $zostalo
}

# Przewija katalog zrodlowy narzedzia do nowszej wersji, zanim ktokolwiek zacznie
# porownywac numery. To jest katalog roboczy uzytkownika, wiec pobranie jest tchorzliwe
# z zalozenia - ale od P36 samo "sa niezapisane zmiany" nie jest juz powodem odmowy:
# repo narzedzia bylo w tym stanie zawsze, bo rejestr pracy dopisuja hooki. Odmawia
# git - merge --ff-only nie nadpisze lokalnej zmiany ani pliku spoza gita, a z
# --no-overwrite-ignore takze pliku ignorowanego (bez tego git nadpisuje go po cichu).
# My nazywamy po ludzku, przez co odmowil, i chronimy pliki robocze narzedzia (kopia
# przed przewinieciem, oddanie po nim). Rozjechana historia (lokalne commity) - odmowa
# jak dotad. Zadnego reset, stash, clean ani checkout -f - cudza praca jest wazniejsza
# niz swiezosc narzedzia. Brak gita, brak zdalnej i brak sieci to normalne sytuacje:
# cisza i jedziemy dalej z tym, co lezy na dysku. Wynik kazdej prawdziwej proby lezy
# w pliku stanu (klucze aktualizacja.*, patrz Zapisz-Wynik-Pobrania).
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
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Notuj "zrodlo: nie ma gita na tej maszynie - pomijam pobranie"
    Zapisz-Wynik-Pobrania "bez-gita" "nie ma gita na tej maszynie - nie ma czym pobrac nowszej wersji"
    return
  }

  $cyt = '"' + $Zrodlo.TrimEnd('\') + '"'
  $repo = Wolaj-Gita "-C $cyt rev-parse --is-inside-work-tree" $CZAS_GIT
  if (-not $repo.ok -or $repo.tekst -ne "true") {
    Notuj "zrodlo: $Zrodlo to nie repozytorium git - nie ma skad pobierac"
    Zapisz-Wynik-Pobrania "nie-repo" "$Zrodlo to nie repozytorium git - nie ma skad pobierac"
    return
  }

  # Od tej chwili proba byla prawdziwa - znacznik idzie na dysk niezaleznie od
  # wyniku, zeby nieudane pobranie nie powtarzalo sie przy kazdym oknie.
  $stanP[$klucz] = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  Zapisz-Klucze $plikPobrania $stanP

  # Jeden przebieg naraz: dwa okna otwarte jednoczesnie nie moga odkladac tych samych
  # plikow ani scalac na wyscigi. Drugi odpuszcza - pierwszy i tak pobiera.
  $m = New-Object System.Threading.Mutex($false, "Local\MegaRuchacz-zrodlo")
  $mam = $false
  try {
    try { $mam = $m.WaitOne(2000) }
    catch {
      # Porzucona blokada (poprzedni przebieg padl, trzymajac ja) jest juz nasza -
      # to, co po sobie zostawil, oddaje Dokoncz-Przerwane.
      $wew = $_.Exception
      while ($wew -and -not ($wew -is [System.Threading.AbandonedMutexException])) { $wew = $wew.InnerException }
      if (-not $wew) { throw }
      $mam = $true
    }
    if (-not $mam) { Notuj "zrodlo: inny przebieg straznika wlasnie pobiera nowsza wersje - tym razem odpuszczam"; return }
    Przewin-Zrodlo $cyt
  } finally {
    if ($mam) { $m.ReleaseMutex() }
    $m.Dispose()
  }
}

function Przewin-Zrodlo($cyt) {
  # Najpierw to, co zostawil przebieg, ktory padl w polowie: zanim cokolwiek
  # pobierzemy, pliki robocze maja lezec tam, gdzie lezaly.
  $wiszace = @(Dokoncz-Przerwane $cyt)
  if ($wiszace.Count -gt 0) {
    $opis = (@($wiszace | ForEach-Object { "$($_.kat) (" + ($_.pliki -join ", ") + ")" }) -join "; ")
    $zdanie = "MegaRuchacz: UWAGA - kopia plikow roboczych z przerwanego pobrania nowszej wersji czeka w $opis. " +
              "Na dysku lezy juz inna tresc tych plikow, wiec jej nie nadpisuje: porownaj i przenies recznie, a potem usun ten katalog. " +
              "Do tego czasu nie pobieram nowszej wersji narzedzia."
    Powiedz-Wazne $zdanie
    Zapisz-Wynik-Pobrania "kopia" $zdanie @() (@($wiszace | ForEach-Object { $_.kat }) -join ", ")
    return
  }

  # Galaz bez zdalnej (albo odpiety HEAD) - nie ma czego i skad pobierac.
  $zdalna = Wolaj-Gita "-C $cyt rev-parse --abbrev-ref --symbolic-full-name @{u}" $CZAS_GIT
  if (-not $zdalna.ok -or -not $zdalna.tekst) {
    Notuj "zrodlo: galaz w $Zrodlo nie ma zdalnej - nie ma skad pobierac"
    Zapisz-Wynik-Pobrania "bez-zdalnej" "galaz w $Zrodlo nie ma zdalnej - nie ma skad pobierac"
    return
  }

  $plikZmian = Join-Path $Zrodlo "ZMIANY.md"
  $przedWersja = Wersja-Narzedzia $plikZmian

  # Zadnych pytan o haslo - okno sesji nie ma gdzie na nie odpowiedziec.
  # Limity czasu sa krotkie z premedytacja: caly hook ma 15 sekund, a start
  # okna nie moze na nas czekac. Gdy sie nie wyrobimy, wracamy po godzinie.
  $env:GIT_TERMINAL_PROMPT = "0"
  $pobrane = Wolaj-Gita "-C $cyt -c credential.interactive=never fetch --quiet" $CZAS_GIT_FETCH
  if (-not $pobrane.ok) {
    Notuj "zrodlo: fetch nie wyszedl (brak sieci albo dostepu) - zostaje przy tym, co na dysku"
    $bladFetch = @(("" + $pobrane.blad) -split '\r?\n' | Where-Object { $_.Trim() } | Select-Object -First 1) -join ""
    Zapisz-Wynik-Pobrania "bez-sieci" ("nie udalo sie zajrzec na serwer (brak sieci albo dostepu)" + $(if ($bladFetch) { ": $bladFetch" } else { "" }))
    return
  }

  $licznik = Wolaj-Gita "-C $cyt rev-list --left-right --count HEAD...@{u}" $CZAS_GIT
  if (-not $licznik.ok) {
    Notuj "zrodlo: git nie policzyl roznicy wobec zdalnej"
    Zapisz-Wynik-Pobrania "nieudane" "git nie policzyl roznicy wobec zdalnej ($($licznik.blad))"
    return
  }
  $czesci = $licznik.tekst -split '\s+'
  if ($czesci.Count -lt 2) {
    Zapisz-Wynik-Pobrania "nieudane" "git oddal nieczytelna odpowiedz o roznicy wobec zdalnej: $($licznik.tekst)"
    return
  }
  $nasze = [int]$czesci[0]   # commity lokalne, ktorych nie ma na zdalnej
  $zdalne = [int]$czesci[1]  # commity zdalne, ktorych nie mamy u siebie
  if ($zdalne -le 0) {
    Notuj "zrodlo: bez zmian, zdalna nie ma nic nowego"
    Zapisz-Wynik-Pobrania "aktualne" "na serwerze nie ma nic nowszego - masz najnowsza wersje"
    return
  }

  if ($nasze -gt 0) {
    $zdanie = "MegaRuchacz: historia w $Zrodlo rozjechala sie ze zdalna ($nasze lokalnych, $zdalne zdalnych) - nie scalam sam, zrob to recznie."
    Powiedz-Wazne $zdanie
    Zapisz-Wynik-Pobrania "rozjechane" $zdanie
    return
  }

  $plan = Plan-Przewiniecia $cyt
  if (-not $plan.ok) {
    $zdanie = "MegaRuchacz: nie pobieram nowszej wersji narzedzia - $($plan.powod). Nic nie ruszylem; sprobuje przy nastepnym otwarciu okna."
    Powiedz-Wazne $zdanie
    Zapisz-Wynik-Pobrania "nieudane" $zdanie
    return
  }

  # Kopia plikow roboczych, ktore nowa wersja zmienia albo kasuje - PRZED pierwsza
  # proba, bo udane przewiniecie kasuje z dysku plik, ktory przestaje byc sledzony.
  $kat = ""
  if ($plan.robocze.Count -gt 0) {
    try { $kat = Odloz-Robocze $plan.robocze }
    catch {
      $zdanie = "MegaRuchacz: nie pobieram nowszej wersji narzedzia - nie udalo sie odlozyc plikow roboczych do kopii ($($_.Exception.Message)). Nic nie ruszylem."
      Powiedz-Wazne $zdanie
      Zapisz-Wynik-Pobrania "nieudane" $zdanie
      return
    }
  }

  # Tylko proste przewiniecie do przodu - o tym, czy wolno, rozstrzyga git.
  $scal = "-C $cyt merge --ff-only --no-overwrite-ignore @{u}"
  $r = Wolaj-Gita $scal $CZAS_GIT_FETCH
  $blokuja = @($plan.zmienione) + @($plan.obce) + @($plan.dodane)
  $wlasne = @($plan.robocze | Where-Object { $_.tryb -eq "wlasny" })
  $bladZdjecia = ""
  if (-not $r.ok -and $blokuja.Count -eq 0 -and $wlasne.Count -gt 0) {
    # Git odmowil wylacznie przez pliki robocze tej maszyny - kopia juz lezy, wiec
    # zdejmujemy je z drogi i probujemy drugi raz. Wracaja w Oddaj-Robocze.
    try {
      Zdejmij-Robocze $kat $wlasne
      $r = Wolaj-Gita $scal $CZAS_GIT_FETCH
    } catch { $bladZdjecia = "nie udalo sie zdjac plikow roboczych z drogi: $($_.Exception.Message)" }
  }
  $nieOddane = @()
  if ($kat) { $nieOddane = @(Oddaj-Robocze $cyt $kat) }
  $kopia = ""
  if ($nieOddane.Count -gt 0) {
    $kopia = $kat
    $zdanieKopii = "MegaRuchacz: UWAGA - nie oddalem z kopii plikow roboczych: " + ($nieOddane -join ", ") +
                   ". Na dysku lezy juz inna tresc, wiec jej nie nadpisuje - kopia czeka w ${kat}: porownaj i przenies recznie, a potem usun ten katalog."
    Powiedz-Wazne $zdanieKopii
  }

  if ($r.ok) {
    if ($kat -and $nieOddane.Count -eq 0) {
      Notuj ("zrodlo: pliki robocze tej maszyny odlozone na czas pobrania i oddane bez zmian: " + (@($plan.robocze | ForEach-Object { $_.sciezka }) -join ", "))
    }
    # Cicha aktualizacja jest gorsza niz jej brak - zawsze jedna linia o tym,
    # co sie wlasnie zmienilo pod reka uzytkownika.
    $poWersja = Wersja-Narzedzia $plikZmian
    if ($przedWersja -and $poWersja -and $przedWersja -ne $poWersja) {
      $zdanie = "MegaRuchacz: narzedzie podciagniete z gita - wersja ${przedWersja} -> ${poWersja} (co doszlo: $plikZmian)"
    } else {
      $slowo = if ($zdalne -eq 1) { "nowa zmiana" } else { "nowych zmian" }
      $zdanie = "MegaRuchacz: narzedzie podciagniete z gita - $zdalne $slowo, numer wersji bez zmian (co doszlo: $plikZmian)"
    }
    Mow $zdanie
    Zapisz-Wynik-Pobrania "pobrane" $zdanie @() $kopia
    return
  }

  # Odmowa przez pliki git zglasza, zanim cokolwiek zapisze - wtedy "nic nie ruszylem"
  # jest prawda. Przy innej odmowie (np. plik trzymany przez inny program) git mogl juz
  # cos zapisac, wiec mowimy tylko to, za co reczymy sami: pliki robocze.
  $naMiejscu = if ($nieOddane.Count -eq 0) { " Nic nie ruszylem." } else { "" }
  $oRoboczych = if ($kat -and $nieOddane.Count -eq 0) { " Pliki robocze tej maszyny zostaly na miejscu." } else { "" }
  if ($blokuja.Count -gt 0) {
    $czesciZdania = @()
    if ($plan.zmienione.Count -gt 0) { $czesciZdania += "zmiany w plikach, ktore zmienia tez nowa wersja: " + (Lista-Do-Zdania $plan.zmienione) }
    if ($plan.obce.Count -gt 0)      { $czesciZdania += "pliki spoza gita tam, gdzie nowa wersja kladzie swoje: " + (Lista-Do-Zdania $plan.obce) }
    if ($plan.dodane.Count -gt 0)    { $czesciZdania += "zmiany przygotowane do zapisu (git add) w plikach, ktore zmienia nowa wersja: " + (Lista-Do-Zdania $plan.dodane) }
    $zdanie = "MegaRuchacz: nie pobieram nowszej wersji narzedzia - git odmowil, bo nadpisalby Twoja prace w ${Zrodlo}: " +
              ($czesciZdania -join "; ") + ".$naMiejscu Zachowaj je recznie (commit i scalenie) albo przenies w bezpieczne " +
              "miejsce - potem pobiore sam przy nastepnym otwarciu okna."
    Powiedz-Wazne $zdanie
    Zapisz-Wynik-Pobrania "zablokowane" $zdanie $blokuja $kopia
    return
  }

  # Odmowa z innego powodu (zablokowany indeks, plik trzymany przez inny program,
  # brak miejsca) albo git nie zdazyl. Powod slowami gita - lepsze to niz zgadywanie.
  $powodGita = (@(("" + $r.blad) -split '\r?\n' | Where-Object { $_.Trim() -and ($_ -notmatch '^\s*(warning|hint):') } | Select-Object -First 1) -join "").Trim().TrimEnd('.')
  if (-not $powodGita) { $powodGita = "bez slowa wyjasnienia (kod $($r.kod))" }
  $powod = if ($bladZdjecia) { $bladZdjecia } else { "git: $powodGita" }
  $plikiGita = @(("" + $r.blad) -split '\r?\n' | Where-Object { $_ -match '^\t' } | ForEach-Object { $_.Trim() })
  $zdanie = "MegaRuchacz: nie udalo sie przewinac $Zrodlo do nowszej wersji - $powod"
  if ($plikiGita.Count -gt 0) { $zdanie += " (pliki: " + (Lista-Do-Zdania $plikiGita) + ")" }
  $zdanie += ". Pracuje na tej, ktora jest.$oRoboczych"
  Powiedz-Wazne $zdanie
  Zapisz-Wynik-Pobrania "nieudane" $zdanie $plikiGita $kopia
}

# --------------------------------------------------------- 1. zasady globalne
# Pliki instrukcji do pilnowania - KAZDEGO narzedzia AI z listy (kierownik-cele.ps1 Narzedzia-AI:
# Claude Code ~\.claude\CLAUDE.md, Codex ~\.codex\AGENTS.md, OpenCode ~\.config\opencode\AGENTS.md),
# ktore tu jest. Codex i OpenCode wczytuja swoj plik sami, bez zadnego hooka - to jedyna droga zasad
# na maszynie bez Claude Code. Zapisuje wpisz-zasady.ps1 (wszystkie pliki naraz), tu tylko
# sprawdzamy, czy bloki (i przy module wiedza szkielet "Co wiem") nadal tam siedza i sa swieze.
function Cele-Zasad {
  $cele = @()
  if (-not (Get-Command Cele-Narzedzi -ErrorAction SilentlyContinue)) {
    # starsza kopia kierownik-cele.ps1 - jak do 0.27: sam CLAUDE.md i AGENTS.md Codeksa
    $cele += [ordered]@{ nazwa = "Claude Code"; plik = $plikDomowy; limit = 0; n = $null }
    if (Test-Path (Split-Path -Parent $plikCodex)) { $cele += [ordered]@{ nazwa = "Codex"; plik = $plikCodex; limit = $LIMIT_AGENTS; n = $null } }
    return ,$cele
  }
  foreach ($n in (Cele-Narzedzi $KatalogDomowy)) {
    $cele += [ordered]@{ nazwa = $n.Nazwa; plik = $n.Sciezka; limit = $n.Limit; n = $n }
  }
  # przecinek z premedytacja: bez niego lista jednoelementowa wraca jako goly
  # slownik, a nie tablica - ta sama pulapka, ktora zlapala rejestr modulow
  return ,$cele
}

# Od P59a dwa bloki zasad pamieci - lore i wiedza, kazdy przy swoim module z rejestru instalacji
# (zasady-bloki.ps1). Plik jest "zgodny", gdy zlozenie go od nowa (Zloz-Plik-Zasad - ta sama
# regula, ktora pisze wpisz-zasady.ps1) nie zmienia w nim ani znaku. Inaczej wolamy
# wpisz-zasady.ps1 i sprawdzamy wynik z dysku. Przy okazji migracja: stary wspolny blok
# MegaRuchacz:start zamienia sie na nowe na swoim miejscu, "Co wiem" nad nim zostaje co do bajtu.
# Do P59a w pliku stanu lezaly skroty bloku (zrodlo, blok, blok.codex) - dzis zbedne, sprzatamy je.
function Pilnuj-Zasad {
  if (-not (Get-Command Zloz-Plik-Zasad -ErrorAction SilentlyContinue)) {
    Mow "MegaRuchacz: nie ma $plikBlokowZasad - nie pilnuje blokow zasad pamieci (Lore, wiedza) w plikach instrukcji."
    return
  }
  $chciane = Chciane-Bloki-Zasad $KatalogDomowy
  $tresci = [ordered]@{}
  try {
    foreach ($n in (Bloki-Zasad)) { if ($chciane.Nazwy -contains $n) { $tresci[$n] = Tresc-Zrodla-Zasad $Zrodlo $n } }
  } catch {
    Mow "MegaRuchacz: zasady pamieci - $($_.Exception.Message); bloki zostaja, jakie sa, dopoki zrodlo nie wroci."
    return
  }
  $zdejmij = @()
  if ($chciane.Zdejmuj) { $zdejmij = @(Bloki-Zasad | Where-Object { $chciane.Nazwy -notcontains $_ }) }
  # Szkielet "Co wiem" w kazdym pliku przy wlaczonym module wiedza - ta sama regula co w wpisz-zasady.ps1.
  $szkielet = ($chciane.Nazwy -contains "wiedza") -and [bool](Get-Command Zloz-Plik-Narzedzia -ErrorAction SilentlyContinue)
  $cele = Cele-Zasad
  if ($cele.Count -eq 0) {
    Notuj "zasady pamieci: nie widze zadnego narzedzia AI (Claude Code, Codex, OpenCode) - nie ma gdzie ich pilnowac"
    return
  }

  $doNaprawy = @()
  foreach ($c in $cele) {
    $tekst = ""
    if (Test-Path -LiteralPath $c.plik) {
      try { $tekst = [System.IO.File]::ReadAllText($c.plik, (New-Object System.Text.UTF8Encoding($false, $true))) }
      catch { Mow "MegaRuchacz: $($c.plik) nie czyta sie jako UTF-8 - nie pilnuje w nim zasad pamieci."; $script:Niepowodzenia++; continue }
    }
    $oczekiwany = $null
    $start = [pscustomobject]@{ Tekst = $tekst; Istnieje = (Test-Path -LiteralPath $c.plik); Opis = $null }
    try {
      # Plik narzedzia zaczyna sie tak samo jak w wpisz-zasady.ps1 (Tekst-Startowy): OpenCode bez
      # wlasnego pliku - od tresci CLAUDE.md, stara kopia dla opencode - bez linii naglowka.
      if ($c.n) { $start = Tekst-Startowy $c.n $KatalogDomowy; $oczekiwany = Zloz-Plik-Narzedzia $start $tresci $zdejmij $szkielet }
      else { $oczekiwany = Zloz-Plik-Zasad $tekst $tresci $zdejmij }
    }
    catch { Mow "MegaRuchacz: zasady pamieci w $($c.plik): $($_.Exception.Message) - nie ruszam, popraw znaczniki recznie."; $script:Niepowodzenia++; continue }
    if ($oczekiwany -ceq $tekst) { continue }
    $opisy = @(Roznice-Zasad $start.Tekst $tresci $zdejmij)
    if ($szkielet -and -not (Ma-Co-Wiem $start.Tekst)) { $opisy += "brakowalo szkieletu 'Co wiem'" }
    if ($start.Opis) { $opisy = @($start.Opis) + $opisy }
    $doNaprawy += [ordered]@{ nazwa = $c.nazwa; plik = $c.plik; opis = ($opisy -join ", "); n = $c.n }
  }

  if ($doNaprawy.Count -eq 0) {
    Usun-Klucze $plikStanu @("zrodlo", "blok", "blok.codex")
    Notuj ("zasady pamieci: aktualne (" + (($cele | ForEach-Object { $_.nazwa }) -join ", ") + ")")
    Pilnuj-Limitu $cele
    return
  }

  $opis = ($doNaprawy | ForEach-Object { "$($_.nazwa): $($_.opis)" }) -join "; "
  $wpisz = Join-Path $Zrodlo "narzedzia\wpisz-zasady.ps1"
  if (-not (Test-Path $wpisz)) {
    Mow "MegaRuchacz: zasady pamieci wymagaja poprawki ($opis), a nie ma $wpisz - wpisz je recznie."
    return
  }
  $kod = 1
  $wyjscie = @()
  try {
    $global:LASTEXITCODE = 0
    $wyjscie = @(& $wpisz -Zrodlo $Zrodlo -KatalogDomowy $KatalogDomowy *>&1 | ForEach-Object { "$_" })
    $kod = $LASTEXITCODE
  } catch { $kod = 1; $wyjscie += "$($_.Exception.Message)" }
  # Odmowa zapisu z sufitu (plik przekroczylby limit narzedzia) - na POCZATKU meldunku: to jedyny
  # powod, dla ktorego naprawa nie wyszla, a ktory naprawia czlowiek, nie straznik.
  $odmowy = @($wyjscie | Where-Object { $_ -match '^BLAD\s+ODMOWA ZAPISU' } | ForEach-Object { ($_ -replace '^BLAD\s+', '').Trim() })
  foreach ($o in $odmowy) { Mow "MegaRuchacz: UWAGA - $o" }
  $pierwszyBlad = @($wyjscie | Where-Object { $_ -match '^BLAD\s' -and $_ -notmatch 'ODMOWA ZAPISU' } | Select-Object -First 1)

  # Po naprawie skladamy wszystko jeszcze raz z dysku - to, co wpisz-zasady.ps1
  # wypisalo o sobie, nie jest dowodem.
  $nadal = @()
  foreach ($c in $doNaprawy) {
    $tekst = ""
    try { if (Test-Path -LiteralPath $c.plik) { $tekst = [System.IO.File]::ReadAllText($c.plik, (New-Object System.Text.UTF8Encoding($false, $true))) } }
    catch { $nadal += $c.nazwa; continue }
    try {
      $ocz = if ($c.n) { Zloz-Plik-Narzedzia (Tekst-Startowy $c.n $KatalogDomowy) $tresci $zdejmij $szkielet } else { Zloz-Plik-Zasad $tekst $tresci $zdejmij }
      if ($ocz -cne $tekst) { $nadal += $c.nazwa }
    }
    catch { $nadal += $c.nazwa }
  }
  if ($kod -eq 0 -and $nadal.Count -eq 0) {
    Usun-Klucze $plikStanu @("zrodlo", "blok", "blok.codex")
    Mow "MegaRuchacz: zasady pamieci wymagaly poprawki ($opis) - poprawione, reszta plikow bez zmian."
    Pilnuj-Limitu $cele
  } else {
    $ogon = ""
    if ($nadal.Count -gt 0) { $ogon = ", nadal niezgodne: " + ($nadal -join ", ") }
    if ($pierwszyBlad.Count -gt 0) { $ogon += "; " + ($pierwszyBlad[0] -replace '^BLAD\s+', '').Trim() }
    if ($odmowy.Count -gt 0) { $ogon += "; odmowa zapisu ponad limit - powod wyzej" }
    Mow "MegaRuchacz: zasady pamieci ($opis), a poprawka nie wyszla (kod ${kod}${ogon}) - uruchom $wpisz recznie."
    $script:Niepowodzenia++
  }
}

# ------------------------------------------------ 1b. blok zasad kierownika
# Blok MegaRuchacz:kierownik wpisuje instalator globalny. Do 0.21.0 nikt go potem
# nie pilnowal (P8): gdy znikal, straznik przywracal sam blok Lore i milczal.
# Teraz: brak bloku = przywracamy go we wlasciwym wariancie dla pliku, dubel albo
# brak szablonu = jedna linia do czlowieka. ISTNIEJACEGO bloku nie podmieniamy -
# aktualizacja tresci to robota instalatora (tu nie wiemy, czy wariant nie byl
# wymuszony). Tylko przy instalacji globalnej - wdrozenie per projekt tego bloku
# w plikach globalnych nie ma i miec nie ma.
# Pliki: kazde narzedzie AI z listy (kierownik-cele.ps1 Narzedzia-AI), ktore tu jest, w wariancie
# z listy - CLAUDE.md w wariancie zapisanym przez instalator (moze byc wymuszony -WariantZasad).
# Do 0.27 opencode dostawal kopie CLAUDE.md (Pilnuj-Kopii-Opencode) - dzis ma samodzielny plik jak
# Codex, a stara kopie zamienia na samodzielny plik Pilnuj-Zasad (Tekst-Startowy).
# Od P59a modul kierownik wylaczony w rejestrze instalacji = blok zdejmujemy (Zdejmij-Kierownika).
function Powiedz-Kierownik([string]$tekst) {
  Mow $tekst
  # W tle nikt nie czyta ekranu - zdanie czeka na najblizszy przebieg z widownia.
  if ($Tlo) { Odloz-Wiadomosc $tekst }
}

# Pliki instrukcji wszystkich narzedzi z listy (takze tych, ktorych juz nie widac - zdejmowanie jest
# bezpieczne), a przy starszej kopii kierownik-cele.ps1 - CLAUDE.md i AGENTS.md Codeksa jak dotad.
function Pliki-Wszystkich-Narzedzi {
  if (Get-Command Narzedzia-AI -ErrorAction SilentlyContinue) {
    return ,@(Narzedzia-AI | ForEach-Object { [ordered]@{ nazwa = "~/" + ($_.Plik -replace '\\', '/'); plik = (Join-Path $KatalogDomowy $_.Plik) } })
  }
  return ,@([ordered]@{ nazwa = "~/.claude/CLAUDE.md"; plik = $plikDomowy }, [ordered]@{ nazwa = "~/.codex/AGENTS.md"; plik = $plikCodex })
}

# Wycina NASZ blok kierownika (po znacznikach) z pliku instrukcji kazdego narzedzia AI. Dubel
# albo samotny znacznik - jedna linia do czlowieka, plik zostaje (nie zgadujemy, co jest czyje).
function Zdejmij-Kierownika {
  if (-not (Get-Command Bez-Bloku-Kierownika -ErrorAction SilentlyContinue)) {
    Powiedz-Kierownik "MegaRuchacz: modul kierownik wylaczony w rejestrze instalacji, a $plikCeliKierownika nie umie zdjac bloku (starsza kopia) - blok zostaje."
    return
  }
  $stempel = Get-Date -Format "yyyyMMdd-HHmmss"
  foreach ($c in (Pliki-Wszystkich-Narzedzi)) {
    if (-not (Test-Path -LiteralPath $c.plik)) { continue }
    try { $tekst = Czytaj-Utf8 $c.plik }
    catch { Powiedz-Kierownik "MegaRuchacz: $($c.nazwa) nie czyta sie jako UTF-8 - nie zdejmuje z niego bloku zasad kierownika."; $script:Niepowodzenia++; continue }
    if ((Ile-Blokow-Kierownika $tekst) -eq 0) { continue }
    try {
      $nowy = Bez-Bloku-Kierownika $tekst
      Kopia-Zapasowa $c.plik $stempel
      Zapisz-Tekst $c.plik $nowy
      if ((Ile-Blokow-Kierownika (Czytaj-Utf8 $c.plik)) -ne 0) { throw "po zapisie blok nadal jest w pliku" }
      Powiedz-Kierownik "MegaRuchacz: modul kierownik wylaczony w rejestrze instalacji - zdjalem blok zasad kierownika z $($c.nazwa) (kopia .bak-$stempel obok)."
    } catch {
      Powiedz-Kierownik "MegaRuchacz: modul kierownik wylaczony, a bloku zasad kierownika w $($c.nazwa) nie udalo sie zdjac ($($_.Exception.Message))."
      $script:Niepowodzenia++
    }
  }
}

function Pilnuj-Kierownika {
  if (-not (Jest-Globalna)) { return }
  if (-not (Get-Command Z-Blokiem-Kierownika -ErrorAction SilentlyContinue)) {
    Powiedz-Kierownik "MegaRuchacz: nie ma $plikCeliKierownika - nie pilnuje bloku zasad kierownika (uruchom narzedzia\instaluj-globalnie.ps1)."
    return
  }
  if (Modul-Wylaczony "kierownik") {
    Zdejmij-Kierownika
    return
  }
  if (-not (Get-Command Cele-Narzedzi -ErrorAction SilentlyContinue)) {
    Powiedz-Kierownik "MegaRuchacz: $plikCeliKierownika nie ma listy narzedzi AI (starsza kopia) - nie pilnuje bloku zasad kierownika; uruchom narzedzia\instaluj-globalnie.ps1."
    return
  }
  $szablony = [ordered]@{
    claude   = Join-Path $Zrodlo "szablony-global\claude\zasady-kierownika.md"
    opencode = Join-Path $Zrodlo "szablony-opencode\zasady-kierownika.md"
  }
  # Wariant dla ~/.claude/CLAUDE.md: taki, jaki zapisal instalator (moze byc wymuszony); gdy go
  # nie zapisal (instalacje sprzed 0.21.1) - wariant z listy narzedzi.
  $wariantDomowy = (Czytaj-Klucze $PlikZnacznikaGlobalnego)["wariant"]
  $stempel = Get-Date -Format "yyyyMMdd-HHmmss"
  foreach ($n in (Cele-Narzedzi $KatalogDomowy)) {
    $wariant = $n.Wariant
    if (($n.Id -eq "claude") -and ($wariantDomowy -in @("claude", "opencode"))) { $wariant = $wariantDomowy }
    $nazwa = "~/" + ($n.Plik -replace '\\', '/')
    $tekst = ""
    if (Test-Path -LiteralPath $n.Sciezka) {
      try { $tekst = Czytaj-Utf8 $n.Sciezka }
      catch { Powiedz-Kierownik "MegaRuchacz: $nazwa nie czyta sie jako UTF-8 - nie sprawdzam w nim bloku zasad kierownika."; continue }
    }
    $ile = Ile-Blokow-Kierownika $tekst
    if ($ile -eq 1) { continue }
    if ($ile -gt 1) {
      Powiedz-Kierownik "MegaRuchacz: w $nazwa jest $ile blokow zasad kierownika (dubel) - nie ruszam, usun nadmiarowe."
      continue
    }
    $szablon = $szablony[$wariant]
    if (-not (Test-Path $szablon)) {
      Powiedz-Kierownik "MegaRuchacz: w $nazwa brakuje bloku zasad kierownika, a nie umiem go wpisac - brak szablonu $szablon. Uruchom narzedzia\instaluj-globalnie.ps1."
      continue
    }
    try {
      $tresc = Czytaj-Utf8 $szablon
      # Plik, ktorego jeszcze nie ma, zaczyna sie tak samo jak w wpisz-zasady.ps1 (Tekst-Startowy).
      $start = Tekst-Startowy $n $KatalogDomowy
      $nowy = Z-Blokiem-Kierownika $start.Tekst $tresc
      $sufit = Ponad-Limit $n $tekst $nowy
      if ($sufit) {
        Powiedz-Kierownik "MegaRuchacz: UWAGA - w $nazwa brakuje bloku zasad kierownika i NIE wpisalem go: $sufit"
        $script:Niepowodzenia++
        continue
      }
      Kopia-Zapasowa $n.Sciezka $stempel
      Zapisz-Tekst $n.Sciezka $nowy
      # Dowodem jest dysk, nie to, ze zapis nie rzucil wyjatkiem.
      $po = Czytaj-Utf8 $n.Sciezka
      $naglowek = ($tresc.Trim() -split "`r?`n")[0]
      if ((Ile-Blokow-Kierownika $po) -ne 1 -or -not $po.Contains($naglowek)) { throw "po zapisie w pliku nie ma dokladnie jednego bloku w wariancie $wariant" }
      $skad = if ($start.Opis) { "; $($start.Opis)" } else { "" }
      Powiedz-Kierownik "MegaRuchacz: w $nazwa brakowalo bloku zasad kierownika - wpisalem go (wariant $wariant$skad)."
    } catch {
      Powiedz-Kierownik "MegaRuchacz: w $nazwa brakuje bloku zasad kierownika, a wpisanie nie wyszlo ($($_.Exception.Message)). Uruchom narzedzia\instaluj-globalnie.ps1."
      $script:Niepowodzenia++
    }
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
    # Lore odznaczone w instalatorze (rejestr instalacji) - nie proponujemy go i nie zapowiadamy
    # jego aktualizacji przy kazdej nowej wersji; wroci, gdy uzytkownik zaznaczy je sam.
    if (($m.nazwa -eq "pamiec") -and (Modul-Wylaczony "lore")) { continue }

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
    # To samo dla czesci opencode - Nanies-Poprawki tez ja odswieza i przesuwa
    # znacznik w .megaruchacz\wersja.txt, ale klucz w pliku wdrozenia Claude Code
    # musi pojsc razem z nim, zeby "jedno miejsce" mowilo prawde.
    if ($stan["opencode.wersja"]) {
      $stan["opencode.wersja"] = $wZrodla
      $stan["opencode.data"] = $stan["$k.data"]
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
#
# $narzedzie: "Claude" albo "Codex" - kazde narzedzie ma wlasny rachunek i wlasny
# plik podreczny. Starsza wersja skryptu bez -Narzedzie wywroci sie na nieznanym
# parametrze - to trafia do wywrotek, a nie w cisze.
function Policz-Koszt([string]$narzedzie = "Claude") {
  $skrypt = Join-Path $Zrodlo "narzedzia\koszt-pamieci.ps1"
  if (-not (Test-Path $skrypt)) { return $null }
  $odcisk = Odcisk-Rachunku
  $kod = 0
  $wy = @()
  try {
    $global:LASTEXITCODE = 0
    $wy = @(& $skrypt -KatalogDomowy $KatalogDomowy -Zwiezle -Narzedzie $narzedzie 2>$null)
    $kod = $LASTEXITCODE
  } catch { Zanotuj-Wywrotke "liczenie rachunku za pamiec ($narzedzie)" $_; return $null }
  $linia = ""
  foreach ($l in $wy) {
    $t = "$l".Trim()
    if ($t) { $linia = $t; break }
  }
  if (-not $linia) { return $null }
  if ($null -eq $kod) { $kod = 0 }
  return [ordered]@{ linia = $linia; kod = [int]$kod; skrypt = $odcisk }
}

# Odcisk skryptu liczacego. Linia w pliku podrecznym jest wazna TYLKO z tym samym
# odciskiem: 28.09.2026 po zmianie rachunku (911d5a0) okno pokazywalo przez dwie
# godziny linie policzona stara wersja ("ALARM: ... prog 300"), bo data miescila
# sie w $GODZIN_MIEDZY_KOSZTAMI. Stara liczba z innego rachunku to nie liczba
# "troche nieswieza", tylko inna liczba - nie pokazujemy jej wcale.
# Od P27 rachunek to plik wejsciowy plus moduly narzedzia\koszt\*.ps1, wiec odcisk
# idzie z CALOSCI: nazwa i SHA256 kazdego pliku (kolejnosc porzadkowa, niezalezna od
# ustawien jezyka). Z samego pliku wejsciowego zmiana w module zostawialaby w oknie
# linie policzona stara wersja az do $GODZIN_KOSZT_STARY. Starsza kopia narzedzia bez
# katalogu koszt\ - sam plik. Skroty liczymy wprost, bez Get-FileHash: jego pierwsze
# wywolanie w procesie kosztuje ~150 ms (zmierzone 30.09.2026), a to hook startowy.
# "" = nie da sie policzyc odcisku (wtedy zadna linia nie jest wazna).
function Odcisk-Rachunku {
  $skrypt = Join-Path $Zrodlo "narzedzia\koszt-pamieci.ps1"
  if (-not (Test-Path $skrypt)) { return "" }
  $sha = $null
  try {
    $pliki = @($skrypt)
    $moduly = Join-Path $Zrodlo "narzedzia\koszt"
    if (Test-Path -LiteralPath $moduly -PathType Container) {
      $nazwy = [string[]]@(Get-ChildItem -LiteralPath $moduly -Filter *.ps1 -File -ErrorAction Stop | ForEach-Object { $_.Name })
      [Array]::Sort($nazwy, [StringComparer]::OrdinalIgnoreCase)
      $pliki += @($nazwy | ForEach-Object { Join-Path $moduly $_ })
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $sklad = @($pliki | ForEach-Object {
      (Split-Path -Leaf $_) + "=" + [System.BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($_))).Replace("-", "")
    }) -join "`n"
    return [System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sklad))).Replace("-", "").Substring(0, 16)
  } catch { Zanotuj-Wywrotke "odcisk skryptu rachunku" $_; return "" }
  finally { if ($sha) { $sha.Dispose() } }
}

# Odczyt linii z pliku podrecznego razem z ocena, czy wolno ja pokazac.
# Zwraca linie = $null i powod, gdy jej nie ma, gdy policzyl ja inny rachunek
# (inny odcisk skryptu) albo gdy jest starsza niz $GODZIN_KOSZT_STARY - liczba
# sprzed ponad doby opisuje juz inna konfiguracje. Miedzy $GODZIN_MIEDZY_KOSZTAMI
# a $GODZIN_KOSZT_STARY linia idzie dalej, ale z godzina (Ogon-Wieku).
function Czytaj-Rachunek($plik) {
  $stan = Czytaj-Klucze $plik
  $w = [ordered]@{ linia = $null; kod = 0; kiedy = [datetime]::MinValue; swieza = $false; powod = "" }
  if ($stan["kod"] -match '^\d+$') { $w.kod = [int]$stan["kod"] }
  $kiedy = [datetime]::MinValue
  $jestData = [datetime]::TryParse($stan["data"], [ref]$kiedy)
  $w.kiedy = $kiedy
  $odcisk = Odcisk-Rachunku
  if (-not $stan["linia"]) {
    $w.powod = "nie ma jeszcze policzonej liczby"
  } elseif ((-not $odcisk) -or ($stan["skrypt"] -ne $odcisk)) {
    $w.powod = "zapisana liczba jest z poprzedniej wersji rachunku, wiec jej nie pokazuje"
  } elseif (-not $jestData) {
    $w.powod = "zapisana liczba nie ma daty, wiec jej nie pokazuje"
  } elseif (([datetime]::Now - $kiedy).TotalHours -gt $GODZIN_KOSZT_STARY) {
    $w.powod = "zapisana liczba jest z $($kiedy.ToString('yyyy-MM-dd HH:mm')), sprzed ponad doby, wiec jej nie pokazuje"
  } else {
    $w.linia = $stan["linia"]
    $w.swieza = (([datetime]::Now - $kiedy).TotalHours -le $GODZIN_MIEDZY_KOSZTAMI)
  }
  return $w
}

# Zdanie zamiast linii, gdy linii nie wolno pokazac. Gdy ostatnie zamowione
# przeliczenie (znacznik "proba") jest starsze niz $MINUT_NA_PRZELICZENIE i nie
# zostawilo waznej linii, mowimy wprost, ze sie nie udalo - "przeliczam" przy
# liczeniu, ktore sie wywraca, byloby ta sama cisza, tylko ladniej ubrana.
function Zdanie-Przeliczania($rach, [string]$kiedyBedzie) {
  $tekst = "MegaRuchacz: rachunek za pamiec agenta sie przelicza ($($rach.powod)) - liczba bedzie $kiedyBedzie."
  $stan = Czytaj-Klucze $plikKosztu
  $probowano = [datetime]::MinValue
  if ([datetime]::TryParse($stan["proba"], [ref]$probowano) -and
      $probowano -gt $rach.kiedy -and ([datetime]::Now - $probowano).TotalMinutes -gt $MINUT_NA_PRZELICZENIE) {
    $tekst += (" UWAGA: przeliczenie zamowione $($probowano.ToString('yyyy-MM-dd HH:mm')) nie zapisalo nowej liczby - " +
               "pelny rachunek recznie: powershell -File $Zrodlo\narzedzia\koszt-pamieci.ps1")
  }
  return $tekst
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
function Zapisz-Koszt($wynik, $plik = $plikKosztu) {
  $stare = Czytaj-Klucze $plik
  $stan = [ordered]@{
    data   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    kod    = $wynik.kod
    linia  = $wynik.linia
    skrypt = $wynik.skrypt
  }
  # "pelny" i "pelny.codex" - znaczniki dziennego meldunku, osobne dla kazdego
  # narzedzia, bo uzytkownik Codeksa ma zobaczyc rozbicie takze wtedy, gdy tego
  # samego dnia otworzyl wczesniej okno Claude Code.
  foreach ($k in @($stare.Keys)) {
    if ($k -like "pelny*") { $stan[$k] = $stare[$k] }
  }
  if ($stare["proba"]) { $stan["proba"] = $stare["proba"] }
  try { Zapisz-Klucze $plik $stan } catch { Zanotuj-Wywrotke "zapis podrecznego rachunku" $_ }
}

# Oba rachunki naraz - Claude Code i Codex, kazdy do swojego pliku. Liczymy oba
# niezaleznie od tego, ktore okno zamowilo przeliczenie: to sekundy w procesie,
# na ktory nikt nie czeka, a drugie narzedzie dostaje swieza liczbe za darmo.
function Policz-I-Zapisz-Koszty {
  $claude = Policz-Koszt "Claude"
  if ($claude) { Zapisz-Koszt $claude $plikKosztu }
  $codex = Policz-Koszt "Codex"
  if ($codex) { Zapisz-Koszt $codex $plikKosztuCodex }
  # do dziennika trybu -Tlo: trend rachunku Codeksa ma tam tak samo lezec
  if ($codex) { Notuj "koszt pamieci Codeksa: $($codex.linia)" }
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

# To samo, ale z dlawikiem na probe - ten sam warunek, ktorego pilnuje Zglos-Koszt.
# Dziesiec okien otwartych naraz ma odpalic liczenie raz, a liczenie, ktore sie
# wywraca, ma wracac co kwadrans, a nie przy kazdym oknie. W trybie -Tlo nic nie
# startujemy: tam liczymy na miejscu i drugi proces byloby marnotrawstwem.
function Zamow-Przeliczenie {
  if ($Tlo) { return }
  $stan = Czytaj-Klucze $plikKosztu
  $probowano = [datetime]::MinValue
  $odProby = [double]::MaxValue
  if ([datetime]::TryParse($stan["proba"], [ref]$probowano)) {
    $odProby = ([datetime]::Now - $probowano).TotalMinutes
  }
  if ($odProby -le $MINUT_MIEDZY_PROBAMI) { return }
  Odswiez-Koszt-W-Tle
}

# Czy gotowe rozbicie w pliku podrecznym jest jeszcze swieze. Osobno od liczby
# z $plikKosztu, bo to osobny plik i potrafi zostac w tyle za nia.
function Rozbicie-Swieze {
  if (-not (Test-Path $plikRozbicia)) { return $false }
  try {
    return (([datetime]::Now - (Get-Item $plikRozbicia).LastWriteTime).TotalHours -le $GODZIN_MIEDZY_KOSZTAMI)
  } catch {
    Zanotuj-Wywrotke "odczyt wieku rozbicia rachunku" $_
    return $false
  }
}

# Ogon przy JEDNOLINIJKOWYM rachunku: z kiedy jest pokazywana liczba. Do
# 2026-09-17 stal dopiero po $GODZIN_KOSZT_STARY, wiec liczba sprzed siedmiu
# godzin szla jako biezaca - to jest dokladnie to klamstwo, ktorego zakazuje
# "Cisza jest zakazana": dane maja byc swieze albo jawnie opisane wiekiem.
function Ogon-Wieku($kiedy) {
  if ((-not $kiedy) -or ($kiedy -eq [datetime]::MinValue)) {
    return " (nie wiadomo, z kiedy jest ta liczba - bufor bez daty)"
  }
  $godzin = ([datetime]::Now - $kiedy).TotalHours
  # "po przeliczeniu w tle", a nie "przeliczam teraz": przeliczenie ma wlasny
  # dlawik i moze akurat nie ruszyc. Obiecywanie czegos, co sie nie dzieje, uczy
  # ignorowac te dopiski.
  if ($godzin -gt $GODZIN_KOSZT_STARY) {
    return " (liczba z $(Get-Date $kiedy -Format 'yyyy-MM-dd HH:mm'), sprzed $([int]$godzin) godzin - NIESWIEZA, swiezsza po przeliczeniu w tle)"
  }
  if ($godzin -gt $GODZIN_MIEDZY_KOSZTAMI) {
    return " (liczba z $(Get-Date $kiedy -Format 'yyyy-MM-dd HH:mm'), swiezsza po przeliczeniu w tle)"
  }
  return ""
}

# To samo dla BLOKU rozbicia - osobna linia, bo blok ma wiecej niz jeden wiersz.
# Godzina stoi przy nim zawsze: blok idzie z bufora, wiec nigdy nie jest "z tej
# chwili", a liczby podane bez godziny kazdy czyta jako stan na teraz.
function Znacznik-Wieku($kiedy, [string]$co) {
  if ((-not $kiedy) -or ($kiedy -eq [datetime]::MinValue)) {
    return "    (nie wiadomo, z kiedy sa te ${co} - nie da sie odczytac daty bufora)"
  }
  $godzin = ([datetime]::Now - $kiedy).TotalHours
  $stempel = $kiedy.ToString('yyyy-MM-dd HH:mm')
  if ($godzin -gt $GODZIN_MIEDZY_KOSZTAMI) {
    return ("    (UWAGA: ${co} sprzed $([int]$godzin) godzin, z bufora z ${stempel} - to NIE jest stan na teraz; " +
            "swiezsze beda po przeliczeniu w tle, przy nastepnym otwarciu)")
  }
  return "    (${co} z bufora z ${stempel})"
}

# Jedna linia o koszcie pamieci - zawsze, niezaleznie od tego, czy cokolwiek
# innego wymaga uwagi. Gdy cos jest ucinane (kod 1), linia idzie jako wyrozniony
# alarm, a nie dopisek w cudzym meldunku: po cichu ucinac sie nie ma prawa.
function Zglos-Koszt {
  if ($Tlo) {
    # W tle nikt nie czeka na otwarcie okna, wiec liczymy na miejscu - i przy
    # okazji odswiezamy liczbe oraz rozbicie, z ktorych skorzystaja nastepne okna.
    Policz-I-Zapisz-Koszty
    Zapisz-Rozbicie (Policz-Rozbicie)
  }

  # Rachunek Claude Code - to okno jest oknem Claude Code (hook SessionStart
  # z ~\.claude\settings.json), a w -Tlo linia idzie do dziennika jako trend.
  $rach = Czytaj-Rachunek $plikKosztu
  $linia = $rach.linia
  $kod = $rach.kod
  $kiedy = $rach.kiedy

  # Zdanie o przeliczaniu skladamy PRZED zamowieniem: zamowienie przestawia
  # znacznik proby, a zdanie ma powiedziec, czy POPRZEDNIA proba sie udala.
  $zdanie = $null
  if (-not $linia) { $zdanie = Zdanie-Przeliczania $rach "przy nastepnym otwarciu okna" }

  # Linia niewazna albo nieswieza - przeliczenie w tle. Dlawik na probe siedzi
  # w Zamow-Przeliczenie (w -Tlo nic nie startuje, bo liczy na miejscu).
  if ((-not $linia) -or (-not $rach.swieza)) { Zamow-Przeliczenie }

  if (-not $linia) {
    # Nie ma czego pokazac (pierwsze uruchomienie, liczba z innej wersji rachunku
    # albo sprzed doby) - cisza wygladalaby jak "nic sie nie dzieje", a stara
    # liczba jak stan na teraz, wiec mowimy wprost, ze rachunek sie przelicza.
    if ($Tlo) { Notuj "koszt pamieci: $($rach.powod)" }
    else       { Mow $zdanie }
    return
  }

  $ogon = Ogon-Wieku $kiedy

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

# Sufit ladunku TEGO hooka, czytany z .codex\hooks.json lezacego w projekcie -
# tak samo jak robi to narzedzia\sufit-ladunku.ps1 przy ladunkach z pliku.
# Hooka poznajemy po przelaczniku "-KosztCodex" w poleceniu. $null = nie wiadomo,
# gdzie stoi sufit (brak pliku, cudzy hooks.json, starsza kopia narzedzia).
#
# Gdy w projekcie tego pliku nie ma (hooki siedza w konfiguracji domowej Codeksa
# albo wdrozenie jest starsze), bierzemy sufit z szablonu w katalogu zrodlowym -
# to ten sam plik, ktory wdrozenie tam kopiuje. Lepszy sufit wzorcowy niz zaden:
# bez zadnej liczby nie wiedzielibysmy, ze ladunek jest ucinany.
function Sufit-Kosztu-Codex {
  if (-not (Get-Command Limit-Ladunku -ErrorAction SilentlyContinue)) { return $null }
  if ($Projekt) {
    try {
      $z = Limit-Ladunku (Join-Path $Projekt ".codex\hooks.json") "-KosztCodex"
      if ($z) { return $z }
    } catch { Zanotuj-Wywrotke "odczyt sufitu hooka Codeksa z projektu" $_ }
  }
  try { return (Limit-Ladunku (Join-Path $Zrodlo "szablony-codex\hooks.json") "-KosztCodex") }
  catch { Zanotuj-Wywrotke "odczyt sufitu hooka Codeksa z szablonu" $_; return $null }
}

# Dziennemu rozbiciu daleko do jednej linii, a ladunek hooka ma sufit i jest
# ucinany OD KONCA bez slowa. Dlatego: albo rozbicie miesci sie w calosci, albo
# nie idzie wcale i zostaje jedno zdanie o tym, czego brakuje i jak to naprawic.
# Znacznik dnia odkladamy DOPIERO po udanym doklejeniu - meldunek, ktory sie nie
# zmiescil, ma wrocic przy nastepnym otwarciu, a nie przepasc na caly dzien.
function Dolacz-Rozbicie-Codex([string]$tresc) {
  $stan = Czytaj-Klucze $plikKosztu
  $dzis = (Get-Date -Format 'yyyy-MM-dd')
  if ($stan["pelny.codex"] -eq $dzis) { return $tresc }

  $linie = @(Linie-Kosztu-Dziennego)
  if ($linie.Count -eq 0) { return $tresc }
  $blok = ($linie -join "`n")

  $limit = Sufit-Kosztu-Codex
  if (($null -ne $limit) -and ($limit -gt 0) -and (($tresc.Length + 1 + $blok.Length) -gt $limit)) {
    return ($tresc + "`n" + "MegaRuchacz: dzienne rozbicie rachunku ($($blok.Length) znakow) nie miesci sie w suficie hooka " +
            "($limit znakow), wiec go tu nie wklejam - podnies additionalContextLimit przy hooku od -KosztCodex " +
            "w .codex\hooks.json. Cale rozbicie lezy w ${plikRozbicia}.")
  }

  $stan["pelny.codex"] = $dzis
  try { Zapisz-Klucze $plikKosztu $stan } catch { Zanotuj-Wywrotke "znacznik dziennego rachunku (Codex)" $_ }
  return ($tresc + "`n" + $blok)
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
#
# Od 0.21.3 czytamy WLASNY rachunek Codeksa ($plikKosztuCodex, koszt-pamieci.ps1
# -Narzedzie Codex) - do 0.21.2 szla tu linia Claude Code.
function Wypisz-Koszt-Codex {
  $rach = Czytaj-Rachunek $plikKosztuCodex
  $linia = $rach.linia
  $kod = $rach.kod

  if (-not $linia) {
    $tresc = Zdanie-Przeliczania $rach "przy nastepnym otwarciu sesji"
  } else {
    $ogon = Ogon-Wieku $rach.kiedy
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
      # Do modelu ida najwyzej dwie wywrotki, i to przyciete - komplet lezy
      # w dzienniku trybu bezobslugowego. Sufit ladunku musi starczyc przede
      # wszystkim na rozbicie, a nie na liste tego, co sie potknelo.
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
    # Prosby odlozone przez tryb -Tlo (np. "zatwierdz hooki przez /hooks"). Pod
    # Codeksem to jedyne miejsce, w ktorym maja szanse dotrzec do czlowieka -
    # tam, skad je odlozono, jest tylko dziennik.
    foreach ($odlozone in @(Odbierz-Wiadomosci)) { $przed += $odlozone }
    # Bez node'a nie chodzi ani przypomnienie o zasadach (zostaje samo wypisanie
    # ladunku, bez linii o cyklu), ani rejestr pracy workerow. Oba maja wtedy
    # awaryjne wyjscie i milcza - a cisza w tym miejscu wygladalaby jak sprawnosc.
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
      $przed += "UWAGA: nie ma node w PATH - przypomnienie o zasadach idzie bez linii o cyklu wiedzy, a wpisy o workerach do .megaruchacz\worklog.md nie powstaja wcale."
    }
  } catch { }   # alarm, ktory sam sie wywraca, nie ma prawa zabrac rachunku
  if ($przed.Count -gt 0) { $tresc = ($przed -join " ") + " " + $tresc }

  # Rozbicie rachunku na pozycje - raz dziennie, dokladnie to samo, co widzi
  # uzytkownik Claude Code (Zglos-Koszt-Dzienny). Do 2026-09-17 nie szlo tu nic:
  # rozbicie liczyl tryb -Tlo, zapisywal je do pliku i na tym sie konczylo, bo
  # pokazywala je wylacznie galaz interaktywna. Znacznik jest osobny ("pelny.codex"),
  # zeby wczesniejsze okno Claude Code nie zabralo meldunku Codeksowi.
  try { $tresc = Dolacz-Rozbicie-Codex $tresc } catch { Zanotuj-Wywrotke "dolaczanie rozbicia rachunku (Codex)" $_ }

  # Przeliczenie zamawiamy DOPIERO TERAZ, gdy ladunek jest juz zlozony: proces
  # liczacy przepisuje bufor, a my mamy oddac to, co wlasnie opisalismy godzina.
  # Zamawiamy takze wtedy, gdy rozbicie dzis juz poszlo - inaczej pod Codeksem
  # odswiezal rachunek wylacznie hook -Tlo i kazde okno czytalo stan sprzed sesji.
  try {
    if ((-not $rach.swieza) -or (-not (Rozbicie-Swieze))) { Zamow-Przeliczenie }
  } catch { Zanotuj-Wywrotke "start przeliczenia rachunku (Codex)" $_ }

  # Ostatnia bramka: nawet sam rachunek z alarmami moze nie zmiescic sie w suficie
  # (ktos obnizyl limit recznie). Ucinane jest to, co na koncu, wiec ostrzezenie
  # idzie na POCZATEK - jedyne miejsce, ktore uciecie przezyje zawsze. Ten sam
  # komunikat, co w narzedzia\sufit-ladunku.ps1, zeby obie drogi brzmialy tak samo.
  try {
    $limitH = Sufit-Kosztu-Codex
    if (($null -ne $limitH) -and ($limitH -gt 0) -and ($tresc.Length -gt $limitH) -and
        (Get-Command Ostrzezenie-O-Ucieciu -ErrorAction SilentlyContinue)) {
      $tresc = (Ostrzezenie-O-Ucieciu $tresc.Length $limitH) + $tresc
    }
  } catch { Zanotuj-Wywrotke "pilnowanie sufitu ladunku (Codex)" $_ }

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
#
# Zwraca LINIE, a nie wypisuje: ten sam tekst idzie na ekran pod Claude Code
# i do ladunku hooka pod Codeksem (Wypisz-Koszt-Codex). Dwie kopie tego samego
# meldunku rozjechalyby sie przy pierwszej poprawce.
function Linie-Kosztu-Cyklu {
  # Modul wiedza wylaczony w rejestrze instalacji: cyklu nie ma z wyboru, a stary plik kosztu
  # krzyczalby "cykl nie chodzi" - falszywy alarm.
  if (Modul-Wylaczony "wiedza") { return @() }
  $plik = Join-Path $KatalogDomowy ".claude\wiedza\.koszt-cyklu.txt"
  if (-not (Test-Path $plik)) {
    return @("    cykl wiedzy: kosztu jeszcze nie policzyl - jesli cykl chodzi, liczba bedzie po jego najblizszym przebiegu")
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
    return @("    cykl wiedzy: ostatni koszt z ${kiedy} (${wiek} dni temu) - cykl od tego czasu nie wylawial faktow, wiec nie chodzi")
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

  return @("    cykl wiedzy ${kiedy}: ${tokeny} tokenow${zrodlo}${ogon} - to prawdziwe wywolanie modelu, osobno od liczb wyzej")
}

# Raz na dobe, przy pierwszym otwarciu okna tego dnia, pelniejszy meldunek -
# uzytkownik chcial byc informowany CODZIENNIE, a nie tylko wtedy, gdy sam
# zajrzy do pliku. Zrodlem jest raport zadania LoreKoszt z Harmonogramu
# (<dom>\.claude\wiedza\koszt-ostatni.txt). Gdy tego zadania nie ma albo nie
# chodzi, mowimy i o tym: cisza wygladalaby jak "wszystko policzone".
#
# Tu powstaja same LINIE - bez wypisywania i bez odkladania znacznika "raz
# dziennie". Znacznik odklada ten, kto te linie POKAZE, bo pod Codeksem pokazanie
# moze sie nie udac (sufit ladunku) i wtedy meldunek ma wrocic, a nie przepasc.
function Linie-Kosztu-Dziennego {
  # Rozbicie na pozycje - to jest ten meldunek, o ktory uzytkownik poprosil: przy
  # kazdej pozycji ma stac, GDZIE ona siedzi i DO CZEGO jest doklejana, bo sama suma
  # nie mowi, co skrocic. Gotowy blok lezy w pliku podrecznym (liczy go w tle
  # koszt-pamieci.ps1 -Rozbicie), wiec otwarcie sesji na nic nie czeka.
  $linie = @(Linie-Rozbicia)
  # Bufor pusty albo starszy niz $GODZIN_MIEDZY_KOSZTAMI - przeliczenie idzie
  # w tle, nikt na nie nie czeka, a to, co pokazujemy teraz, niesie swoja godzine.
  if (-not (Rozbicie-Swieze)) { try { Zamow-Przeliczenie } catch { Zanotuj-Wywrotke "start przeliczenia rozbicia" $_ } }
  if ($linie.Count -gt 0) { return $linie }

  # Rozbicia jeszcze nie ma (pierwsze uruchomienie) - zostaje to, co bylo:
  # wyciag z dziennego raportu zadania LoreKoszt i osobna linia o koszcie cyklu.
  $plik = Join-Path $KatalogDomowy ".claude\wiedza\koszt-ostatni.txt"
  $skrypt = Join-Path $Zrodlo "narzedzia\koszt-pamieci.ps1"
  if (-not (Test-Path $plik)) {
    $linie += "MegaRuchacz: rozbicie rachunku za pamiec licze wlasnie w tle - bedzie przy nastepnym otwarciu okna."
    # koszt cyklu to osobny plik i osobny rodzaj kosztu - brak jednego rachunku
    # nie ma prawa zabrac drugiego
    try { $linie += @(Linie-Kosztu-Cyklu) } catch { Zanotuj-Wywrotke "koszt cyklu wiedzy" $_ }
    return $linie
  }

  $kiedyRaport = (Get-Item $plik).LastWriteTime
  $dni = [int]([datetime]::Now - $kiedyRaport).TotalDays
  $godzinRaportu = ([datetime]::Now - $kiedyRaport).TotalHours
  # Ten raport pisze zadanie LoreKoszt raz na dobe, wiec bywa sprzed godzin, a
  # niesie rzeczy, ktore zdazyly sie zmienic (ile faktow czeka w poczekalni,
  # ktore progi byly przekroczone). Sama data w nawiasie okazala sie za cicha:
  # 2026-09-17 poszlo stad "W poczekalni czeka 90 faktow", gdy byla juz pusta.
  # Dlatego przy nieswiezym raporcie mowimy to pierwsza linia, wprost.
  if ($godzinRaportu -gt $GODZIN_MIEDZY_KOSZTAMI) {
    $linie += ("MegaRuchacz - UWAGA: ponizszy rachunek za pamiec jest sprzed $([int]$godzinRaportu) godzin " +
               "(z $($kiedyRaport.ToString('yyyy-MM-dd HH:mm'))) i NIE opisuje stanu na teraz - liczby i ostrzezenia " +
               "z niego mogly sie od tego czasu zdezaktualizowac. Rozbicie na pozycje bedzie po przeliczeniu w tle.")
  } else {
    $linie += "MegaRuchacz - dzienny rachunek za pamiec (z $($kiedyRaport.ToString('yyyy-MM-dd HH:mm'))):"
  }

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
  foreach ($t in ($wybrane | Select-Object -First 6)) { $linie += "    $t" }
  try { $linie += @(Linie-Kosztu-Cyklu) } catch { Zanotuj-Wywrotke "koszt cyklu wiedzy" $_ }
  if ($dni -gt 2) {
    $linie += "    Ten raport ma $dni dni - zadanie LoreKoszt nie chodzi. Zaloz je od nowa: powershell -File $skrypt -ZalozZadanie"
  }
  $linie += "    Caly rachunek: $plik"
  return $linie
}

function Zglos-Koszt-Dzienny {
  $stan = Czytaj-Klucze $plikKosztu
  $dzis = (Get-Date -Format 'yyyy-MM-dd')
  if ($stan["pelny"] -eq $dzis) { return }
  # Znacznik idzie na dysk PRZED wypisaniem - potkniecie ma znaczyc jeden
  # pominiety meldunek, a nie meldunek przy kazdym oknie do konca dnia.
  $stan["pelny"] = $dzis
  try { Zapisz-Klucze $plikKosztu $stan } catch { Zanotuj-Wywrotke "znacznik dziennego rachunku" $_ }
  foreach ($l in @(Linie-Kosztu-Dziennego)) { Write-Host $l }
}

# Gotowy blok rozbicia z pliku podrecznego. Oddajemy go slowo w slowo i prosimy
# model, zeby przepisal go uzytkownikowi: wyjscie hooka trafia do KONTEKSTU MODELU,
# a nie na ekran, wiec bez tej prosby uzytkownik nie zobaczy z tego ani linii.
# Pusta lista = nie ma czego pokazac (pierwsze uruchomienie albo liczenie sie wywrocilo).
function Linie-Rozbicia {
  $blok = Czytaj-Tekst $plikRozbicia
  if (-not $blok) { return @() }
  # Godzina bufora idzie ZAWSZE, nie dopiero po tygodniu: blok jest czytany
  # z pliku, wiec zawsze opisuje przeszlosc, a bez stempla czyta sie go jak stan
  # na teraz. 2026-09-17 poszly tak do Codeksa liczby sprzed siedmiu godzin.
  $kiedy = $null
  try { $kiedy = (Get-Item $plikRozbicia).LastWriteTime } catch { Zanotuj-Wywrotke "odczyt daty rozbicia rachunku" $_ }
  $linie = @("MegaRuchacz: przepisz uzytkownikowi ponizszy blok w pierwszej odpowiedzi, bez zmian i bez komentarza.")
  foreach ($l in (($blok -replace "`r`n", "`n") -split "`n")) { $linie += $l }
  $linie += (Znacznik-Wieku $kiedy "liczby")
  return $linie
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
  # Cykl to modul wiedza. Odznaczony w instalatorze (rejestr instalacji) = cyklu nie ma z wyboru
  # uzytkownika, a nie z awarii - dlatego bez slowa na ekranie, tylko slad w dzienniku.
  if (Modul-Wylaczony "wiedza") { Notuj "cykl wiedzy: modul wiedza wylaczony w rejestrze instalacji - nie ruszam"; return }

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

  # Tryb dla instaluj-globalnie.ps1 - wylacznie hooki globalne (i pliki, ktore wolaja),
  # nic poza tym: zadnego pobierania, cyklu ani rachunku. Znacznika instalacji
  # nie sprawdzamy, bo instalator stawia go dopiero na koncu. Kod wyjscia 1 = nie wyszlo.
  # Z jawnym -Projekt dodatkowo zdejmuje zdublowane hooki z tego projektu (to samo,
  # co robi przebieg przy starcie sesji) - bez pobierania z gita i bez cyklu wiedzy.
  if ($NaprawGlobalne -or $UsunGlobalne) {
    $ok = $false
    try { $ok = Napraw-Hooki-Globalne ([bool]$UsunGlobalne) }
    catch { Write-Host "MegaRuchacz: porzadkowanie hookow globalnych sie wywrocilo - $($_.Exception.Message)" }
    if ($ok -and $NaprawGlobalne -and $PSBoundParameters.ContainsKey("Projekt")) {
      try { Usun-Hooki-Projektowe }
      catch { Write-Host "MegaRuchacz: zdejmowanie hookow projektowych sie wywrocilo - $($_.Exception.Message)"; $ok = $false }
    }
    if ($ok) { exit 0 } else { exit 1 }
  }

  # Tryb dla instalatora po zmianie modulow - pliki dopasowane do rejestru instalacji od razu,
  # a nie przy nastepnym otwarciu okna: bloki zasad pamieci (z szkieletem "Co wiem"), blok kierownika
  # i hooki globalne. Bez pobierania z gita, cyklu wiedzy i rachunku. Wyzerowane pliki pamieci
  # blokuja zapis tak samo jak przy starcie sesji. Kod 1 = cos sie nie udalo (opis na ekranie).
  if ($Dopasuj) {
    try { Sprawdz-Zera } catch { Zanotuj-Wywrotke "sprawdzanie zer w plikach pamieci" $_ }
    try { Zglos-Rejestr } catch { Zanotuj-Wywrotke "odczyt rejestru instalacji" $_ }
    $hookiOk = $true
    if ($script:Wyzerowane.Count -eq 0) {
      try { Pilnuj-Zasad } catch { Zanotuj-Wywrotke "pilnowanie zasad" $_ }
      try { Pilnuj-Kierownika } catch { Zanotuj-Wywrotke "pilnowanie bloku kierownika" $_ }
    } else { $script:Niepowodzenia++ }
    try { if (Jest-Globalna) { $hookiOk = Napraw-Hooki-Globalne $false } } catch { Zanotuj-Wywrotke "hooki instalacji globalnej" $_ }
    foreach ($w in $script:Wywrotki) { Write-Host "MegaRuchacz: wywrocilo sie: $w" }
    Zapisz-Obecnosc "dopasuj"
    if ($script:Niepowodzenia -gt 0 -or $script:Wywrotki.Count -gt 0 -or -not $hookiOk) { exit 1 }
    exit 0
  }

  # Tryb pomocniczy - policz rachunek za pamiec i odloz gotowa linie do pliku
  # podrecznego. Startuje go straznik sam, osobnym procesem, wiec nikt tu nie
  # czeka i nikt nie czyta: zadnego wypisywania, zadnych innych sprawdzen.
  if ($PoliczKoszt) {
    Policz-I-Zapisz-Koszty
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
    # To, co zebralo sie do tej pory, jest juz na dysku i za chwile zostanie
    # odebrane do ladunku - zerujemy licznik, zeby nie poszlo drugi raz.
    $script:Wywrotki = @()
    Wypisz-Koszt-Codex
    # Drugi zapis, bo wywrotka przy SKLADANIU ladunku wydarza sie PO pierwszym
    # i bez tego nie zostawilaby po sobie ani sladu - a cisza w tym miejscu
    # wygladalaby jak sprawnie zlozony rachunek.
    if ($script:Wywrotki.Count -gt 0) { Zapisz-Obecnosc "codex" }
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
    try { Sprawdz-Zera }   catch { Zanotuj-Wywrotke "sprawdzanie zer w plikach pamieci" $_ }
    try { Zglos-Rejestr }  catch { Zanotuj-Wywrotke "odczyt rejestru instalacji" $_ }
    try { Odswiez-Zrodlo } catch { Zanotuj-Wywrotke "odswiezanie zrodla" $_ }
    if ($script:Wyzerowane.Count -eq 0) {
      try { Pilnuj-Zasad }   catch { Zanotuj-Wywrotke "pilnowanie zasad" $_ }
      try { Pilnuj-Kierownika } catch { Zanotuj-Wywrotke "pilnowanie bloku kierownika" $_ }
    }
    try { Pilnuj-Hookow-Globalnych } catch { Zanotuj-Wywrotke "hooki instalacji globalnej" $_ }
    try { Pilnuj-Sufitu-Zawsze } catch { Zanotuj-Wywrotke "pilnowanie sufitu ladunku" $_ }
    try { Pilnuj-Przypomnienia-Zawsze } catch { Zanotuj-Wywrotke "podmiana starego hooka przypomnienia" $_ }
    try { Pilnuj-Wersji }  catch { Zanotuj-Wywrotke "pilnowanie wersji wdrozenia" $_ }
    try { Zglos-Koszt }    catch { Zanotuj-Wywrotke "rachunek za pamiec" $_ }
    # Cykl wiedzy takze tutaj: na maszynie z samym Codeksem ten hook jest jedynym,
    # ktory w ogole chodzi przy starcie sesji. Ze jest w robocie, uzytkownik zobaczy
    # przy pierwszej wiadomosci - z linii stanu doklejanej przez przypomnienie.js.
    if ($script:Wyzerowane.Count -eq 0) {
      try { Ruszaj-Cykl }    catch { Zanotuj-Wywrotke "start cyklu wiedzy" $_ }
    }
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

  # Kazdy plik z wiedza w ~\.claude\wiedza ma miec odsylacz w "### Dane referencyjne" - inaczej
  # agent nie wie, ze plik istnieje (decyzja uzytkownika 2026-09-30). Dopisuje go sam cykl Lore
  # (lore.verify.ensure_pointers); tu tylko mowimy glosno, gdy ktoregos brakuje, bo cykl chodzi
  # raz na dobe, a plik mogl przybyc recznie. Cisza = wszystkie maja odsylacz. Pliki techniczne
  # (bez odsylacza z zalozenia) - ta sama lista co TECHNICAL_FILES w lore\lore\facts.py.
  function Zglos-Odsylacze {
    $katalog = Join-Path $KatalogDomowy ".claude\wiedza"
    $zasady  = Join-Path $KatalogDomowy ".claude\CLAUDE.md"
    if (-not (Test-Path $katalog) -or -not (Test-Path $zasady)) { return }
    $techniczne = @("kandydaci.md", "zrodla.md", "historia-zmian.md", "uspione.md", "README.md")
    $tekst = Czytaj-Tekst $zasady
    if ($null -eq $tekst) { throw "nie da sie przeczytac $zasady" }
    $m = [regex]::Match($tekst, '(?ms)^###\s+Dane referencyjne[^\r\n]*$(.*?)(?=^#|^<!-- MegaRuchacz:|\z)')
    $sekcja = if ($m.Success) { $m.Groups[1].Value } else { "" }
    $brak = @()
    foreach ($plik in @(Get-ChildItem -LiteralPath $katalog -Filter "*.md" -File)) {
      if ($plik.Extension -ne ".md" -or $plik.Name.StartsWith(".") -or $techniczne -contains $plik.Name) { continue }
      if ($sekcja -notmatch ('`wiedza[/\\]' + [regex]::Escape($plik.Name) + '`')) { $brak += $plik.Name }
    }
    if ($brak.Count -eq 0) { return }
    Write-Host ("MegaRuchacz: pliki wiedzy bez odsylacza w 'Dane referencyjne': " + ($brak -join ", ") +
      " - agent o nich nie wie. Najblizszy cykl Lore dopisze odsylacz sam, a jesli nie da rady, powie dlaczego.")
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
  # Zera najpierw: alarm o nich ma byc pierwsza linia, a reszta ma wiedziec, czego nie ruszac.
  try { Sprawdz-Zera }     catch { Zanotuj-Wywrotke "sprawdzanie zer w plikach pamieci" $_ }
  try { Zglos-Rejestr }    catch { Zanotuj-Wywrotke "odczyt rejestru instalacji" $_ }
  try { Odswiez-Zrodlo }   catch { Zanotuj-Wywrotke "odswiezanie zrodla" $_ }
  if ($script:Wyzerowane.Count -eq 0) {
    try { Pilnuj-Zasad }     catch { Zanotuj-Wywrotke "pilnowanie zasad" $_ }
    try { Pilnuj-Kierownika } catch { Zanotuj-Wywrotke "pilnowanie bloku kierownika" $_ }
  }
  try { Pilnuj-Hookow-Globalnych } catch { Zanotuj-Wywrotke "hooki instalacji globalnej" $_ }
  try { Pilnuj-Sufitu-Zawsze } catch { Zanotuj-Wywrotke "pilnowanie sufitu ladunku" $_ }
  try { Pilnuj-Przypomnienia-Zawsze } catch { Zanotuj-Wywrotke "podmiana starego hooka przypomnienia" $_ }
  try { Pilnuj-Wersji }    catch { Zanotuj-Wywrotke "pilnowanie wersji wdrozenia" $_ }
  # Poczekalnia, odsylacze i meldunek o cyklu to modul wiedza - odznaczony w instalatorze nie ma
  # o czym meldowac, a stary stan cyklu krzyczalby "cykl nie chodzi" (falszywy alarm).
  if (-not (Modul-Wylaczony "wiedza")) {
    try { Zglos-Kandydatow } catch { Zanotuj-Wywrotke "poczekalnia faktow" $_ }
    try { Zglos-Odsylacze }  catch { Zanotuj-Wywrotke "odsylacze plikow wiedzy" $_ }
    try { Zglos-Cykl }       catch { Zanotuj-Wywrotke "meldunek o cyklu" $_ }
  }
  # Wywrotki z przebiegow bez widowni i cisza po stronie Codeksa - tu jest
  # jedyne miejsce, w ktorym maja szanse dotrzec do czlowieka.
  try { Zglos-Wywrotki }   catch { Zanotuj-Wywrotke "meldunek o wywrotkach" $_ }
  try { Zglos-Odlozone }   catch { Zanotuj-Wywrotke "odlozone prosby" $_ }
  try { Zglos-Cisze }      catch { Zanotuj-Wywrotke "wykrywanie ciszy" $_ }
  # Rachunek za pamiec na koncu, zeby zostal pod reka uzytkownika - a pelniejszy
  # meldunek raz na dobe zaraz za nim, bo objasnia te sama liczbe.
  try { Zglos-Koszt }        catch { Zanotuj-Wywrotke "rachunek za pamiec" $_ }
  try { Zglos-Koszt-Dzienny } catch { Zanotuj-Wywrotke "dzienny rachunek za pamiec" $_ }
  # Na samym koncu: cykl wiedzy przy pierwszej sesji dnia. Linia o tym, co sie
  # zaczelo, ma stac pod rachunkiem, bo to ciag dalszy tej samej sprawy.
  if ($script:Wyzerowane.Count -eq 0) {
    try { Ruszaj-Cykl }        catch { Zanotuj-Wywrotke "start cyklu wiedzy" $_ }
  }
  Zapisz-Obecnosc (Nazwa-Trybu)
} catch {
  # Ostatnia siatka. Przebieg i tak konczy sie kodem 0, bo start sesji jest
  # wazniejszy - ale nie konczy sie juz po cichu: slad idzie do pliku stanu
  # i zostanie zameldowany przy nastepnym otwarciu okna.
  try { Zanotuj-Wywrotke "przebieg straznika" $_; Zapisz-Obecnosc (Nazwa-Trybu) } catch { }
}
exit 0
