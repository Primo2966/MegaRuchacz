# narzedzia\instalacja\stan.ps1 - wspolny rejestr zainstalowanych modulow MegaRuchacza.
#
# To jest UMOWA miedzy instalatorem (instalator\), skryptami modulow
# (narzedzia\instalacja\modul-*.ps1), straznikiem, nadzorca i hookiem przypomnienia.
# Wczytuj kropka:  . (Join-Path $Zrodlo 'narzedzia\instalacja\stan.ps1')
#
# Plik stanu: <KatalogDomowy>\.claude\mr\instalacja.json  (UTF-8 bez BOM)
#   {
#     "wersja": 1,
#     "moduly": { "wiedza": true, "lore": true, "kierownik": true, "skille": true, "kopia": false,
#                 "wiedzafirmy": true },   (wiedzafirmy: brak klucza = nie zaproponowano - TRZECI STAN nizej)
#     "kopia": { "zrodla": ["C:\\dev"], "cel": "G:\\..." }   albo null,
#     "narzedzia": { "claude": true, "codex": false, "opencode": false }   albo null,
#     "baza": true,
#     "data": "RRRR-MM-DD GG:MM:SS"
#   }
# Baza (aplikacja przy zegarze + straznik/aktualizacje) jest zawsze - nie ma jej w "moduly".
# Pole "baza" (od P64) pisze tylko modul-baza.ps1: true po Instaluj, false po Usun (usuniecie calego
# MegaRuchacza). Brak pola = true. "baza": false to slad odinstalowania: straznik nie uznaje wtedy
# instalacji za globalna (nie doklada swojego hooka, gdy wywola go np. hook projektu z wdroz.ps1),
# a moduly sa wylaczone, wiec nic nie wraca samo. Bez pliku straznik wrocilby do zasad "sprzed
# rejestru" (wszystko wlaczone) - dlatego rejestr po odinstalowaniu zostaje.
#
# Zasady odczytu (te same w Node i Pythonie):
#   - brak pliku = instalacja sprzed rejestru: wiedza, lore, kierownik, skille wlaczone;
#     kopia wlaczona tylko, gdy istnieje .claude\mr\kopia-stan.txt;
#   - plik nieczytelny (pusty, wyzerowany, zly JSON) = wszystko wlaczone + pole "blad";
#     przy bledzie NIC nie wolno odinstalowac, tylko alarmowac (Cisza jest zakazana);
#   - brak klucza modulu w pliku = jak przy braku pliku.
#
# TRZECI STAN (moduly z Moduly-Z-Trzecim-Stanem, dzis "wiedzafirmy", 2026-10-14): true = jest,
# false = ktos go swiadomie nie chcial, brak klucza / null = "nie zaproponowano". Brak klucza NIE
# znaczy tu "wlaczony" - stara instalacja nie moze dostac takiego modulu po cichu; zamiast tego
# nadzorca raz dziennie pyta (zasobnik\nadzorca\pytanie-wiedza-firmy.ps1). Przy nieczytelnym pliku
# Modul-Wlaczony zwraca dla niego $true (nic nie wolno odinstalowac), ale nikt o niego nie pyta.
#
# LORE OBOWIAZKOWE (decyzja uzytkownika 17.10.2026): CLAUDE.md trzyma tylko staly rdzen wiedzy, reszte
# Claude dostaje z Lore ("Z ARCHIWUM", lore_search) - bez Lore ta wiedza jest niedostepna. Znaczenie
# flagi "lore" sie NIE zmienia: true = "zainstalowane i dziala" (ustawia ja tylko udany
# modul-lore.ps1 -Akcja Instaluj), false = stan przejsciowy do doinstalowania. Dlatego konsumenci flagi
# (bloki zasad, hooki Lore) dalej zdejmuja to, co bez Lore nie dziala - a obowiazek egzekwuja:
#   - instalator (instalator\dane.ps1, pole Zawsze): Lore nie da sie odznaczyc poza usunieciem calosci;
#   - aktualizacja (narzedzia\aktualizuj-megaruchacza.ps1, Doinstaluj-Lore): doinstalowuje sama;
#   - straznik (narzedzia\straznik-zasad.ps1, Zglos-Brak-Lore): linia przy kazdym starcie sesji;
#   - hook przypomnienia (narzedzia\przypomnienie.js, brak-lore): przy wlaczonym lore brak srodowiska
#     i bazy to awaria - linia UWAGA w rytmie alarmow.
# Wspolny predykat braku (straznik i aktualizacja): rejestr czytelny, "baza" nie false, (lore nie true
# albo brak <Zrodlo>\lore\.venv\Scripts\python.exe) i jest <Zrodlo>\lore\pyproject.toml.

# Lista modulow jako funkcja zwracajaca stala, NIE zmienna $script: - zakres $script: w PowerShellu
# jest dynamiczny (skrypt aktualnie wykonywany), wiec funkcja wolana z innego skryptu widziala
# pusta liste i wszystkie moduly wychodzily jako wylaczone (zlapal to test P59a).
function Moduly-MegaRuchacza { return @('wiedza', 'lore', 'kierownik', 'skille', 'kopia', 'wiedzafirmy') }

# Moduly, dla ktorych brak klucza = "nie zaproponowano" (patrz TRZECI STAN w naglowku).
function Moduly-Z-Trzecim-Stanem { return @('wiedzafirmy') }

# 'wlaczony' / 'wylaczony' / 'nie-zaproponowano' / 'nieczytelny' (rejestr z bledem).
function Stan-Modulu([string]$Nazwa, [string]$KatalogDomowy = $HOME) {
  if ((Moduly-MegaRuchacza) -notcontains $Nazwa) { throw "nieznany modul MegaRuchacza: $Nazwa" }
  $s = Czytaj-Instalacje $KatalogDomowy
  if ($s.blad) { return 'nieczytelny' }
  $v = $s.moduly.$Nazwa
  if ($null -eq $v) {
    if ((Moduly-Z-Trzecim-Stanem) -contains $Nazwa) { return 'nie-zaproponowano' }
    return 'wlaczony'
  }
  if ([bool]$v) { return 'wlaczony' }
  return 'wylaczony'
}

function Sciezka-Instalacji([string]$KatalogDomowy = $HOME) {
  return (Join-Path $KatalogDomowy '.claude\mr\instalacja.json')
}

function Domyslne-Moduly([string]$KatalogDomowy = $HOME) {
  $m = [ordered]@{}
  foreach ($n in (Moduly-MegaRuchacza)) { $m[$n] = $true }
  $m['kopia'] = Test-Path -LiteralPath (Join-Path $KatalogDomowy '.claude\mr\kopia-stan.txt')
  foreach ($n in (Moduly-Z-Trzecim-Stanem)) { $m[$n] = $null }
  return $m
}

function Czytaj-Instalacje([string]$KatalogDomowy = $HOME) {
  $p = Sciezka-Instalacji $KatalogDomowy
  $domyslne = Domyslne-Moduly $KatalogDomowy
  $wynik = [pscustomobject]@{
    wersja    = 1
    moduly    = [pscustomobject]$domyslne
    kopia     = $null
    narzedzia = $null
    baza      = $true
    data      = $null
    zrodlo    = 'domyslne'
    blad      = $null
  }
  if (-not (Test-Path -LiteralPath $p)) { return $wynik }
  try {
    $bajty = [System.IO.File]::ReadAllBytes($p)
    if ($bajty.Length -eq 0) { throw 'plik jest pusty' }
    if ([Array]::IndexOf($bajty, [byte]0) -ge 0) { throw 'plik zawiera bajty 0x00 (uszkodzony, np. po zaniku zasilania)' }
    $tekst = (New-Object System.Text.UTF8Encoding($false)).GetString($bajty).TrimStart([char]0xFEFF)
    $j = $tekst | ConvertFrom-Json
    if ($null -eq $j -or $null -eq $j.moduly) { throw 'brak pola "moduly"' }
    foreach ($n in (Moduly-MegaRuchacza)) {
      if ($null -eq $j.moduly.$n) {
        $j.moduly | Add-Member -NotePropertyName $n -NotePropertyValue $domyslne[$n] -Force
      }
    }
    foreach ($pole in @('wersja', 'kopia', 'narzedzia', 'data')) {
      if (-not ($j.PSObject.Properties.Name -contains $pole)) {
        $j | Add-Member -NotePropertyName $pole -NotePropertyValue $null -Force
      }
    }
    # Brak pola albo wartosc nie-logiczna = baza jest (jak przy braku klucza modulu).
    if (-not ($j.PSObject.Properties.Name -contains 'baza') -or ($j.baza -isnot [bool])) {
      $j | Add-Member -NotePropertyName baza -NotePropertyValue $true -Force
    }
    $j | Add-Member -NotePropertyName zrodlo -NotePropertyValue 'plik' -Force
    $j | Add-Member -NotePropertyName blad -NotePropertyValue $null -Force
    return $j
  } catch {
    $wynik.zrodlo = 'awaryjne'
    $wynik.blad = "nie umiem odczytac rejestru instalacji $p : $($_.Exception.Message)"
    return $wynik
  }
}

function Modul-Wlaczony([string]$Nazwa, [string]$KatalogDomowy = $HOME) {
  if ((Moduly-MegaRuchacza) -notcontains $Nazwa) { throw "nieznany modul MegaRuchacza: $Nazwa" }
  $s = Czytaj-Instalacje $KatalogDomowy
  $v = $s.moduly.$Nazwa
  # Brak wartosci = wlaczony: blad odczytu nigdy nie moze wylaczyc (i odinstalowac) modulu.
  # Wyjatek: modul z trzecim stanem przy czytelnym rejestrze - brak = "nie zaproponowano".
  if ($null -eq $v) { return (-not ((-not $s.blad) -and ((Moduly-Z-Trzecim-Stanem) -contains $Nazwa))) }
  return [bool]$v
}

# Zapis atomowy z wymuszeniem zapisu na dysk: plik tymczasowy w tym samym katalogu,
# Flush(true), potem podmiana. Zanik pradu zostawia albo stary, albo nowy plik - nigdy zera.
function Zapisz-Instalacje($Stan, [string]$KatalogDomowy = $HOME) {
  if ($Stan.blad) { throw "odmawiam zapisu rejestru instalacji: odczyt byl bledny ($($Stan.blad))" }
  $p = Sciezka-Instalacji $KatalogDomowy
  $katalog = Split-Path -Parent $p
  if (-not (Test-Path -LiteralPath $katalog)) { New-Item -ItemType Directory -Path $katalog -Force | Out-Null }
  $Stan | Add-Member -NotePropertyName data -NotePropertyValue ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -Force
  $json = $Stan | Select-Object -Property * -ExcludeProperty zrodlo, blad | ConvertTo-Json -Depth 6
  $bajty = (New-Object System.Text.UTF8Encoding($false)).GetBytes($json)
  $tmp = "$p.tmp-$PID"
  $fs = [System.IO.File]::Open($tmp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
  try {
    $fs.Write($bajty, 0, $bajty.Length)
    $fs.Flush($true)
  } finally {
    $fs.Dispose()
  }
  try {
    # [NullString]::Value - goly $null PowerShell podaje .NET jako pusty napis, a Replace go odrzuca.
    if (Test-Path -LiteralPath $p) {
      [System.IO.File]::Replace($tmp, $p, [NullString]::Value)
    } else {
      [System.IO.File]::Move($tmp, $p)
    }
  } catch {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    throw "nie udalo sie zapisac rejestru instalacji $p : $($_.Exception.Message)"
  }
}

function Ustaw-Baze([bool]$Jest, [string]$KatalogDomowy = $HOME) {
  $s = Czytaj-Instalacje $KatalogDomowy
  if ($s.blad) { throw $s.blad }
  $s | Add-Member -NotePropertyName baza -NotePropertyValue $Jest -Force
  Zapisz-Instalacje $s $KatalogDomowy
}

function Ustaw-Modul([string]$Nazwa, [bool]$Wlaczony, [string]$KatalogDomowy = $HOME) {
  if ((Moduly-MegaRuchacza) -notcontains $Nazwa) { throw "nieznany modul MegaRuchacza: $Nazwa" }
  $s = Czytaj-Instalacje $KatalogDomowy
  if ($s.blad) { throw $s.blad }
  $s.moduly | Add-Member -NotePropertyName $Nazwa -NotePropertyValue $Wlaczony -Force
  Zapisz-Instalacje $s $KatalogDomowy
}

# ---------------------------------------------------------------- ustawienia lokalne (P67)
# Plik: <KatalogDomowy>\.claude\mr\lokalne.json (UTF-8) - ustawienia TEGO komputera, ktorych nie ma
# w repozytorium, bo repo jest publiczne: sciezki, nazwy komputerow i projektow uzytkownika.
# Nikt go nie zaklada sam - piszesz go Ty (albo kierownik przy przenosinach). Pola:
#   "kopia":  { "zrodla": [...], "cel": "...", "wykluczenia": [...] }  - kopia BEZ rejestru instalacji
#             (format jak pole kopia rejestru i narzedzia\kopia-zapasowa-domyslne.json)
#   "lore":   { "inne_komputery": [...], "druga_maszyna": [...] }  - lore\lore\verify.py: nazwy innych
#             komputerow i slowa wskazujace druga maszyne (np. konto na niej) w sciezkach faktow
#   "skille": { "wlasne": [{ "folder": "...", "opis": "...", "skad": "..." }] }  - narzedzia\skille.ps1:
#             Twoje wlasne skille (jak lista Wlasne w skille\katalog.psd1)
# Brak pliku albo pola = zachowanie domyslne, bez niczego prywatnego. Plik nieczytelny = pole "blad";
# kto czyta, ten melduje (Cisza jest zakazana) i nie zgaduje w zamian.

function Sciezka-Lokalnych([string]$KatalogDomowy = $HOME) {
  return (Join-Path $KatalogDomowy '.claude\mr\lokalne.json')
}

function Czytaj-Lokalne([string]$KatalogDomowy = $HOME) {
  $p = Sciezka-Lokalnych $KatalogDomowy
  $wynik = [pscustomobject]@{ plik = $p; jest = $false; dane = $null; blad = $null }
  if (-not (Test-Path -LiteralPath $p)) { return $wynik }
  $wynik.jest = $true
  try {
    $bajty = [System.IO.File]::ReadAllBytes($p)
    if ($bajty.Length -eq 0) { throw 'plik jest pusty' }
    if ([Array]::IndexOf($bajty, [byte]0) -ge 0) { throw 'plik zawiera bajty 0x00 (uszkodzony, np. po zaniku zasilania)' }
    $j = (New-Object System.Text.UTF8Encoding($false)).GetString($bajty).TrimStart([char]0xFEFF) | ConvertFrom-Json
    if ($j -isnot [System.Management.Automation.PSCustomObject]) { throw 'to nie jest obiekt JSON' }
    $wynik.dane = $j
  } catch {
    $wynik.blad = "nie umiem odczytac ustawien lokalnych $p : $($_.Exception.Message)"
  }
  return $wynik
}

# Ustawienia kopii BEZ rejestru (instalacja sprzed instalatora): pole "kopia" z lokalne.json, a bez
# niego szablon z repo (narzedzia\kopia-zapasowa-domyslne.json - bez celu, wiec kopia nie ruszy, dopoki
# ktos go nie wybierze). Plik lokalny albo szablon nieczytelny = wyjatek: nie zgadujemy z drugiego.
# Zwraca Plik (skad), Kopia ({zrodla, cel, wykluczenia}) i Lokalne ($true = z lokalne.json).
function Kopia-Bez-Rejestru([string]$Zrodlo, [string]$KatalogDomowy = $HOME) {
  $l = Czytaj-Lokalne $KatalogDomowy
  if ($l.blad) { throw $l.blad }
  if ($l.dane -and $l.dane.kopia) { return [pscustomobject]@{ Plik = $l.plik; Kopia = $l.dane.kopia; Lokalne = $true } }
  $szablon = Join-Path $Zrodlo 'narzedzia\kopia-zapasowa-domyslne.json'
  if (-not (Test-Path -LiteralPath $szablon)) { throw "nie ma szablonu ustawien kopii $szablon (a w $($l.plik) nie ma pola kopia)" }
  try {
    $bajty = [System.IO.File]::ReadAllBytes($szablon)
    if ($bajty.Length -eq 0) { throw 'plik jest pusty' }
    if ([Array]::IndexOf($bajty, [byte]0) -ge 0) { throw 'plik zawiera bajty 0x00 (uszkodzony zapis)' }
    $k = (New-Object System.Text.UTF8Encoding($false)).GetString($bajty).TrimStart([char]0xFEFF) | ConvertFrom-Json
  } catch {
    throw "nie umiem odczytac szablonu ustawien kopii $szablon : $($_.Exception.Message)"
  }
  return [pscustomobject]@{ Plik = $szablon; Kopia = $k; Lokalne = $false }
}
