# instalator\dane.ps1 - czesc okna instalatora (patrz BUDOWA w naglowku instalator\okno.ps1).
# Co instalator wie i liczy, zanim cokolwiek pokaze: tabela czesci MegaRuchacza (nazwy
# i opisy z makiety uzgodnionej z uzytkownikiem), wykrywanie narzedzi AI, obecnej instalacji,
# Dysku Google i ustawien kopii, roznica "jest - ma byc" i z niej plan krokow, zapis rejestru.
# Skad wolane: ekrany.ps1 (ekrany wyboru i podsumowania) i okno.ps1 (start). Wczytuje go
# okno.ps1 kropka - poza tabelami same definicje.

# --- czesci MegaRuchacza -------------------------------------------------------
# Nazwy i opisy: makieta uzgodniona z uzytkownikiem 02.10.2026 (zlecenie P59c) - nie zmieniac
# bez niego. Programy: czego czesc potrzebuje (P63, sekcja B: Wiedza i Lore chodza przez uv
# i Pythona, przypomnienie w oknie rozmowy to hook w Node.js, skille pobiera git, kopia baz
# idzie przez Pythona). To jest zalozenie instalatora - zaleznosci.ps1 (P59b) dostaje te
# liste i sam sprawdza, czego brakuje.
# Przestanie / Dane: zdania do pytania o usuniecie - Dane opisuje to, co modul kasuje z -UsunDane
# (wg naglowkow modul-*.ps1 P59b; kierownik danych w domu nie trzyma - pytanie bez pola).
# Opis-Danych dokleja zaleznosc wiedza <-> lore (baze rozmow kasuje tylko ostatni z nich).
$script:MODULY = [ordered]@{
  wiedza = [pscustomobject]@{
    Id = 'wiedza'; Nazwa = 'Wiedza o Tobie'
    Opis = 'pliki z wiedzą + codzienne czytanie rozmów i poprawianie tych plików (ok. 40 tys. tokenów dziennie)'
    Programy = @('uv', 'python', 'node')
    Przestanie = 'uczyć się o Tobie z rozmów i poprawiać pliki z wiedzą'
    Dane = 'pliki z wiedzą o Tobie (folder wiedza, sekcję „Co wiem” i kopie dzienne)'
  }
  lore = [pscustomobject]@{
    Id = 'lore'; Nazwa = 'Pamięć rozmów (Lore)'
    Opis = 'wyszukiwanie we wszystkich dawnych rozmowach + podpowiedzi „Z ARCHIWUM”'
    Programy = @('uv', 'python', 'node')
    Przestanie = 'przeszukiwać dawne rozmowy i podpowiadać „Z ARCHIWUM”'
    Dane = 'bazę do przeszukiwania dawnych rozmów i stan podpowiedzi „Z ARCHIWUM” (same rozmowy zostają)'
  }
  kierownik = [pscustomobject]@{
    Id = 'kierownik'; Nazwa = 'Tryb kierownika'
    Opis = 'zasady MegaRuchacza, pomocnicy (workerzy), rejestr i mapa'
    Programy = @('node')
    Przestanie = 'pracować w trybie kierownika z pomocnikami'
    Dane = ''
  }
  skille = [pscustomobject]@{
    Id = 'skille'; Nazwa = 'Polecane skille'
    Opis = 'gotowe umiejętności, same się aktualizują'
    Programy = @('git')
    Przestanie = 'instalować i aktualizować polecane skille'
    Dane = 'zapis opieki nad skillami (kopie źródeł, kopie zapasowe, dziennik) - same skille zostają w Twoim folderze'
  }
  kopia = [pscustomobject]@{
    Id = 'kopia'; Nazwa = 'Kopia zapasowa'
    Opis = 'codzienna kopia do wybranego folderu'
    Programy = @('uv', 'python')
    Przestanie = 'robić codzienną kopię zapasową'
    Dane = 'zapis postępu kopii (same kopie w wybranym folderze zostają nietknięte)'
  }
}
$script:ZAWSZE = 'aplikacja przy zegarze + automatyczne aktualizacje'
# Lore przed Wiedza: Wiedza bez Lore dogrywa sobie ukryty rdzen sama, ale gdy Lore tez jest
# wybrane, rdzen powstaje raz, z Lore. Usuwanie w odwrotnej kolejnosci.
$script:KOLEJNOSC_INSTALACJI = @('lore', 'wiedza', 'kierownik', 'skille', 'kopia')
$script:KOLEJNOSC_USUWANIA   = @('kopia', 'skille', 'kierownik', 'wiedza', 'lore')
$script:PROGRAMY = [ordered]@{
  git    = 'Git'
  node   = 'Node.js'
  uv     = 'uv'
  python = 'Python 3.12'
}
# Baza (aplikacja przy zegarze + aktualizacje) pobiera aktualizacje gitem.
$script:PROGRAMY_BAZY = @('git')
# Ile pobiera z internetu (P63, sekcja D, zmierzone na biurowej): srodowisko Pythona
# z bibliotekami 196 MB + sam Python 70 MB, model do wyszukiwania 496 MB (tylko Lore),
# repozytoria polecanych skilli ok. 44 MB.
$script:MB_PYTHON = 270
$script:MB_MODEL  = 496
$script:MB_SKILLE = 50

function Nazwa-Modulu([string]$id) {
  if ($id -eq 'baza') { return 'Aplikacja przy zegarze i automatyczne aktualizacje' }
  return $script:MODULY[$id].Nazwa
}

# Co kasuje "usun tez moje dane" - z tabeli, plus zaleznosc wiedza <-> lore: baze rozmow kasuje
# modul, ktory odchodzi jako ostatni z dwoch (modul-wiedza.ps1 i modul-lore.ps1, P59b).
function Opis-Danych([string]$id) {
  $d = $script:MODULY[$id].Dane
  if (($id -eq 'lore') -and $script:Wybor.Moduly['wiedza']) { $d += ' - sama baza zostanie, dopóki jest Wiedza o Tobie, bo Wiedza z niej czyta' }
  if (($id -eq 'wiedza') -and -not $script:Wybor.Moduly['lore']) { $d += ' oraz bazę dawnych rozmów' }
  return $d
}

function Po-Kolei($ids, $kolejnosc) {
  $w = @()
  foreach ($k in $kolejnosc) { if (@($ids) -contains $k) { $w += $k } }
  return ,$w
}

# --- wykrywanie --------------------------------------------------------------

# Narzedzia AI - po poleceniu w PATH i po katalogu w domu (tak jak w zleceniu P59c).
# Wolane RAZ przy starcie, zanim instalator cokolwiek zapisze: dziennik nie lezy w .claude,
# wiec nie tworzy folderu, ktory potem udawalby zainstalowane Claude Code.
function Wykryj-Narzedzia {
  $wynik = @()
  foreach ($n in @(
      @{ Id = 'claude';   Nazwa = 'Claude Code'; Polecenie = 'claude';   Katalog = '.claude' },
      @{ Id = 'codex';    Nazwa = 'Codex';       Polecenie = 'codex';    Katalog = '.codex' },
      @{ Id = 'opencode'; Nazwa = 'opencode';    Polecenie = 'opencode'; Katalog = '.config\opencode' })) {
    $pol = $null
    try { $pol = Get-Command $n.Polecenie -ErrorAction SilentlyContinue | Select-Object -First 1 }
    catch { Zapisz-Dziennik "wykrywanie polecenia $($n.Polecenie): $($_.Exception.Message)" }
    $jestKat = Test-Path -LiteralPath (Join-Path $script:Dom $n.Katalog)
    $slady = @()
    if ($pol) { $slady += "polecenie $($n.Polecenie)" }
    if ($jestKat) { $slady += "folder $($n.Katalog)" }
    $wynik += [pscustomobject]@{ Id = $n.Id; Nazwa = $n.Nazwa; Jest = [bool]($pol -or $jestKat); Slady = ($slady -join ', ') }
  }
  return $wynik
}

# Czy MegaRuchacz juz jest: rejestr instalacji, a bez niego slady starej instalacji
# (znacznik trybu globalnego albo blok zasad MegaRuchacza w pliku instrukcji).
function Wykryj-Instalacje {
  if (Test-Path -LiteralPath (Sciezka-Instalacji $script:Dom)) { return 'rejestr' }
  if (Test-Path -LiteralPath (Join-Path $script:Dom '.claude\.megaruchacz-global')) { return 'bez-rejestru' }
  foreach ($plik in @('.claude\CLAUDE.md', '.codex\AGENTS.md')) {
    $p = Join-Path $script:Dom $plik
    if (-not (Test-Path -LiteralPath $p)) { continue }
    try {
      if ([System.IO.File]::ReadAllText($p) -match '<!-- MegaRuchacz:') { return 'bez-rejestru' }
    } catch { Zapisz-Dziennik "wykrywanie instalacji: nie odczytalem $p ($($_.Exception.Message))" }
  }
  return ''
}

# Dysk Google na komputerze: litera z folderem "Mój dysk" (albo "My Drive" po angielsku).
# Dyski sieciowe pomijamy - niepodlaczony potrafi wieszac odczyt na kilka sekund.
function Znajdz-Dysk-Google {
  foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
    try {
      if (@('Network', 'CDRom', 'NoRootDirectory') -contains "$($d.DriveType)") { continue }
      if (-not $d.IsReady) { continue }
      foreach ($n in @('Mój dysk', 'My Drive')) {
        $p = Join-Path $d.RootDirectory.FullName $n
        if (Test-Path -LiteralPath $p) { return $p }
      }
    } catch { Zapisz-Dziennik "szukanie Dysku Google na $($d.Name): $($_.Exception.Message)" }
  }
  return $null
}

# Folder ostatniej kopii z ~\.claude\mr\kopia-stan.txt (kopia sprzed rejestru): "cel=" to
# katalog dnia (...\Backup\zmiany\2026-10-02 albo ...\Backup\pelna-2026-10-01) - folder kopii
# jest nad nim.
function Cel-Z-Ostatniej-Kopii {
  $p = Join-Path $script:Dom '.claude\mr\kopia-stan.txt'
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  try {
    foreach ($l in [System.IO.File]::ReadAllLines($p, (New-Object System.Text.UTF8Encoding($false)))) {
      if ($l -match '^cel=(.+)$') {
        return (($Matches[1].Trim()) -replace '\\(zmiany\\[^\\]+|pelna-[^\\]+)$', '')
      }
    }
  } catch { Zapisz-Dziennik "nie odczytalem $p ($($_.Exception.Message))" }
  return $null
}

# Co kopiowac domyslnie: to samo, co kopia-zapasowa.ps1 bez -Zrodla, ale tylko to, co na tym
# komputerze istnieje.
function Znane-Zrodla-Kopii {
  $h = $script:Dom
  return @(
    [pscustomobject]@{ Sciezka = "$h\.claude";          Nazwa = 'Claude Code i MegaRuchacz (ustawienia, wiedza, rozmowy)' },
    [pscustomobject]@{ Sciezka = "$h\.claude.json";     Nazwa = 'Ustawienia Claude Code (plik .claude.json)' },
    [pscustomobject]@{ Sciezka = "$h\.codex";           Nazwa = 'Codex' },
    [pscustomobject]@{ Sciezka = "$h\.config\opencode"; Nazwa = 'opencode' },
    [pscustomobject]@{ Sciezka = "$h\.agents";          Nazwa = 'Skille Codexa (folder .agents)' },
    [pscustomobject]@{ Sciezka = "$h\orca";             Nazwa = 'Orca' },
    [pscustomobject]@{ Sciezka = 'C:\dev';              Nazwa = 'Projekty (C:\dev)' })
}

function Nazwa-Zrodla([string]$sciezka) {
  foreach ($z in (Znane-Zrodla-Kopii)) { if ($z.Sciezka -ieq $sciezka.TrimEnd('\')) { return $z.Nazwa } }
  $lisc = Split-Path -Leaf $sciezka.TrimEnd('\')
  if (-not $lisc) { return $sciezka }
  return $lisc
}

function Domyslne-Zrodla-Kopii {
  $w = New-Object System.Collections.ArrayList
  foreach ($z in (Znane-Zrodla-Kopii)) {
    if (Test-Path -LiteralPath $z.Sciezka) { [void]$w.Add([pscustomobject]@{ Sciezka = $z.Sciezka; Nazwa = $z.Nazwa; Zaznaczone = $true }) }
  }
  return ,$w
}

# "~" na poczatku sciezki = katalog domowy (umowa pola kopia z kopia-zapasowa.ps1, P59d).
function Rozwin-Tylde([string]$p) {
  $p = "$p".Trim()
  if ($p -match '^~(\\|/|$)') { $p = $script:Dom + $p.Substring(1) }
  return $p.TrimEnd('\')
}

# Ustawienia kopii na start - skad, w tej kolejnosci:
#  1. pole kopia rejestru ({zrodla, cel, wykluczenia});
#  2. kopia chodzi bez rejestru (jest ~\.claude\mr\kopia-stan.txt): narzedzia\kopia-zapasowa-domyslne.json,
#     czyli DOKLADNIE to, co dzis kopiuje kopia-zapasowa.ps1 bez rejestru - razem z wykluczeniami
#     (wymog P59d: pierwszy zapis rejestru na takim komputerze niczego nie zmienia po cichu);
#     bez tego pliku - folder ostatniej kopii z kopia-stan.txt;
#  3. nowa kopia: Dysk Google, a bez niego Dokumenty; zrodla = znane foldery, ktore istnieja.
# Plik domyslnych NIE jest brany dla nowej kopii - ma sciezki komputera biurowego.
function Poczatkowa-Kopia {
  $cel = $null; $skad = ''
  $zrodla = New-Object System.Collections.ArrayList
  $wykl = New-Object System.Collections.ArrayList
  $zestaw = $null
  $rej = $script:Instalacja.kopia
  if ($rej -and ($rej.cel -or @($rej.zrodla).Count)) { $zestaw = $rej; $skad = 'rejestr' }
  elseif (Test-Path -LiteralPath (Join-Path $script:Dom '.claude\mr\kopia-stan.txt')) {
    $plik = Join-Path $script:Zrodlo 'narzedzia\kopia-zapasowa-domyslne.json'
    if (Test-Path -LiteralPath $plik) {
      try {
        $zestaw = ([System.IO.File]::ReadAllText($plik, (New-Object System.Text.UTF8Encoding($false))).TrimStart([char]0xFEFF) | ConvertFrom-Json)
        $skad = 'dotychczasowe'
      } catch { Zanotuj-Wywrotke "odczyt dotychczasowych ustawien kopii $plik" $_ }
    }
    if (-not $zestaw) {
      $ost = Cel-Z-Ostatniej-Kopii
      if ($ost) { $cel = $ost; $skad = 'ostatnia' }
    }
  }
  if ($zestaw) {
    if ($zestaw.cel) { $cel = Rozwin-Tylde $zestaw.cel }
    foreach ($s in @($zestaw.zrodla)) { if ("$s".Trim()) { $p = Rozwin-Tylde $s; [void]$zrodla.Add([pscustomobject]@{ Sciezka = $p; Nazwa = (Nazwa-Zrodla $p); Zaznaczone = $true }) } }
    foreach ($w in @($zestaw.wykluczenia)) {
      if (-not $w -or -not "$($w.sciezka)".Trim()) { continue }
      $kat = $null
      if ($w.PSObject.Properties['katalog'] -and ($null -ne $w.katalog)) { $kat = [bool]$w.katalog }
      [void]$wykl.Add([pscustomobject]@{ Sciezka = (Rozwin-Tylde $w.sciezka); Powod = "$($w.powod)"; Katalog = $kat; Zaznaczone = $true })
    }
  }
  $script:DyskGoogle = Znajdz-Dysk-Google
  if (-not $cel) {
    if ($script:DyskGoogle) { $cel = Join-Path $script:DyskGoogle 'MegaRuchacz-kopia'; $skad = 'google' }
    else { $cel = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'MegaRuchacz-kopia'; $skad = 'dokumenty' }
  }
  if ($zrodla.Count -eq 0) { $zrodla = Domyslne-Zrodla-Kopii }
  # Znane foldery, ktorych nie ma na liscie, dochodza jako odznaczone - da sie je dodac jednym kliknieciem.
  foreach ($z in (Znane-Zrodla-Kopii)) {
    if (-not (Test-Path -LiteralPath $z.Sciezka)) { continue }
    $jest = $false
    foreach ($x in $zrodla) { if ($x.Sciezka -ieq $z.Sciezka) { $jest = $true } }
    if (-not $jest) { [void]$zrodla.Add([pscustomobject]@{ Sciezka = $z.Sciezka; Nazwa = $z.Nazwa; Zaznaczone = $false }) }
  }
  return [pscustomobject]@{ Cel = $cel; Zrodla = $zrodla; Wykluczenia = $wykl; Skad = $skad }
}

function Zaznaczone-Zrodla {
  $w = @()
  foreach ($z in $script:Wybor.KopiaZrodla) { if ($z.Zaznaczone) { $w += $z.Sciezka } }
  return ,$w
}

function Zaznaczone-Wykluczenia {
  $w = @()
  foreach ($x in $script:Wybor.KopiaWykluczenia) { if ($x.Zaznaczone) { $w += $x } }
  return ,$w
}

function Klucz-Kopii([string]$cel, $zrodla, $wykluczenia) {
  $z = (@($zrodla) | ForEach-Object { "$_".TrimEnd('\').ToLowerInvariant() } | Sort-Object) -join ';'
  $w = (@($wykluczenia) | ForEach-Object { "$($_.Sciezka)".TrimEnd('\').ToLowerInvariant() + '=' + "$($_.Katalog)" } | Sort-Object) -join ';'
  return ($cel.TrimEnd('\').ToLowerInvariant() + '|' + $z + '|' + $w)
}

function Kopia-Zmieniona {
  if (-not $script:KopiaNaStart) { return $true }
  return ((Klucz-Kopii $script:Wybor.KopiaCel (Zaznaczone-Zrodla) (Zaznaczone-Wykluczenia)) -ne (Klucz-Kopii $script:KopiaNaStart.Cel $script:KopiaNaStart.Zrodla $script:KopiaNaStart.Wykluczenia))
}

# Sprawdzenie ustawien kopii - zwraca zdanie bledu albo "" (wtedy da sie isc dalej).
# Kopia w srodku kopiowanego folderu kopiowalaby sama siebie w kolko.
function Blad-Kopii {
  $cel = "$($script:Wybor.KopiaCel)".Trim()
  if (-not $cel) { return 'Wybierz folder na kopie.' }
  if (-not [System.IO.Path]::IsPathRooted($cel) -or $cel -notmatch '^[A-Za-z]:\\|^\\\\') { return 'Podaj pełną ścieżkę folderu, np. D:\Kopie.' }
  try { $cel = [System.IO.Path]::GetFullPath($cel) } catch { return "Tej ścieżki nie da się użyć: $($_.Exception.Message)" }
  $kor = [System.IO.Path]::GetPathRoot($cel)
  if (-not (Test-Path -LiteralPath $kor)) { return "Nie ma dysku $kor na tym komputerze." }
  $zaz = Zaznaczone-Zrodla
  if ($zaz.Count -eq 0) { return 'Zaznacz przynajmniej jeden folder do kopiowania.' }
  $c = $cel.TrimEnd('\') + '\'
  foreach ($s in $zaz) {
    $z = "$s".TrimEnd('\') + '\'
    if ($c.StartsWith($z, [System.StringComparison]::OrdinalIgnoreCase)) { return "Folder na kopie leży w kopiowanym folderze ($s) - kopia kopiowałaby samą siebie. Wybierz inny folder." }
    if ($z.StartsWith($c, [System.StringComparison]::OrdinalIgnoreCase)) { return "Kopiowany folder $s leży w folderze na kopie. Wybierz inny folder na kopie." }
  }
  return ''
}

# --- roznica i plan ------------------------------------------------------------

# Co sie zmieni: Dodaj / Usun / Zostaje / Nie (nie ma i nie bedzie), KopiaZmieniona (kopia zostaje,
# ale z innymi ustawieniami - modul-kopia jeszcze raz).
function Policz-Zmiany {
  $dodaj = @(); $usun = @(); $zostaje = @(); $nie = @()
  foreach ($id in $script:MODULY.Keys) {
    $teraz = [bool]$script:Obecne[$id]; $chce = [bool]$script:Wybor.Moduly[$id]
    if ($chce -and -not $teraz) { $dodaj += $id }
    elseif ((-not $chce) -and $teraz) { $usun += $id }
    elseif ($chce) { $zostaje += $id }
    else { $nie += $id }
  }
  # Lore usuwane przy zostajacej Wiedzy samo zostawia rdzen, z ktorego Wiedza czyta (modul-lore.ps1,
  # P59b), a usuniecia ida przed instalacjami - zadnego dodatkowego kroku dla Wiedzy.
  $kopiaZm = [bool](($zostaje -contains 'kopia') -and (Kopia-Zmieniona))
  $cos = [bool](($dodaj.Count + $usun.Count) -gt 0 -or $kopiaZm)
  return [pscustomobject]@{ Dodaj = $dodaj; Usun = $usun; Zostaje = $zostaje; Nie = $nie; KopiaZmieniona = $kopiaZm; Cokolwiek = $cos }
}

function Do-Instalacji($zm) {
  $ids = @($zm.Dodaj)
  if ($zm.KopiaZmieniona) { $ids += 'kopia' }
  # Przecinek: pusta lista zostaje pusta lista, a nie $null (return rozwija tablice).
  $w = Po-Kolei $ids $script:KOLEJNOSC_INSTALACJI
  return ,$w
}

function Programy-Dla($ids, [bool]$zBaza) {
  $w = @()
  if ($zBaza) { $w += $script:PROGRAMY_BAZY }
  foreach ($id in @($ids)) { if ($id) { $w += $script:MODULY["$id"].Programy } }
  $u = @()
  foreach ($p in $script:PROGRAMY.Keys) { if ($w -contains $p) { $u += $p } }
  return ,$u
}

function Nazwy-Programow($programy) {
  return ((@($programy) | ForEach-Object { $script:PROGRAMY[$_] }) -join ', ')
}

# Python z bibliotekami tylko wtedy, gdy nie ma go jeszcze z Wiedzy albo Lore (tryb zmiany).
function Mb-Do-Pobrania($ids) {
  $mb = 0
  $jestPython = [bool]($script:Obecne['wiedza'] -or $script:Obecne['lore'])
  $chcePython = (@($ids) -contains 'lore') -or (@($ids) -contains 'wiedza') -or (@($ids) -contains 'kopia')
  if ($chcePython -and -not $jestPython) { $mb += $script:MB_PYTHON }
  if (@($ids) -contains 'lore') { $mb += $script:MB_MODEL }
  if (@($ids) -contains 'skille') { $mb += $script:MB_SKILLE }
  return $mb
}

function Sciezka-Skryptu([string]$nazwa) {
  if ($script:KatalogSkryptow) { return (Join-Path $script:KatalogSkryptow $nazwa) }
  if ($nazwa -eq 'wpisz-zasady.ps1') { return (Join-Path $script:Zrodlo 'narzedzia\wpisz-zasady.ps1') }
  return (Join-Path $script:Zrodlo "narzedzia\instalacja\$nazwa")
}

function Argumenty-Wspolne {
  $a = @('-KatalogDomowy', $script:Dom, '-Zrodlo', $script:Zrodlo)
  if ($script:Proba) { $a += '-Proba' }
  return ,$a
}

function Zadanie-Modulu([string]$id, [string]$akcja, [bool]$usunDane, [string]$napis) {
  $a = @('-Akcja', $akcja) + (Argumenty-Wspolne)
  if ($usunDane) { $a += '-UsunDane' }
  $z = Nowe-Zadanie -Id "$id-$akcja" -Napis $napis -Plik (Sciezka-Skryptu "modul-$id.ps1") -Argumenty $a -Umowa $true
  $z | Add-Member -NotePropertyName Modul -NotePropertyValue $id
  $z | Add-Member -NotePropertyName Akcja -NotePropertyValue $akcja
  $z | Add-Member -NotePropertyName UsunDane -NotePropertyValue $usunDane
  if ($id -ne 'baza') {
    $z.PoSukcesie = {
      param($z)
      $wl = ($z.Akcja -eq 'Instaluj')
      Ustaw-Flage-Modulu $z.Modul $wl ([bool](($z.Modul -eq 'kopia') -and (-not $wl) -and $z.UsunDane))
    }
  }
  return $z
}

function Zadanie-Zaleznosci([string]$akcja, $programy) {
  # Lista idzie JEDNYM napisem "uv,python,git,node": przez -File PowerShell nie rozbija
  # tablicy po przecinkach - zaleznosci.ps1 musi to zrobic sam.
  $a = @('-Akcja', $akcja, '-Potrzebne', (@($programy) -join ','))
  if ($script:Proba) { $a += '-Proba' }
  return (Nowe-Zadanie -Id "zaleznosci-$akcja" -Napis "Programy potrzebne do działania: $(Nazwy-Programow $programy)" -Plik (Sciezka-Skryptu 'zaleznosci.ps1') -Argumenty $a -Umowa $true)
}

function Zbuduj-Plan {
  $zm = Policz-Zmiany
  $script:ZmianyPlanu = $zm
  $plan = New-Object System.Collections.ArrayList
  [void]$plan.Add((Nowe-Zadanie -Id 'zapamietaj' -Napis 'Zapamiętuję Twój wybór' -Wewnetrzne { param($z) Zapamietaj-Wybor }))
  $nowa = ($script:Tryb -eq 'nowy')
  if ($nowa) { [void]$plan.Add((Zadanie-Modulu 'baza' 'Instaluj' $false (Nazwa-Modulu 'baza'))) }
  foreach ($id in (Po-Kolei $zm.Usun $script:KOLEJNOSC_USUWANIA)) {
    $dane = [bool]$script:Wybor.UsunDane[$id]
    $n = "Usuwam: $(Nazwa-Modulu $id)"
    if ($dane) { $n += ' (razem z danymi)' }
    [void]$plan.Add((Zadanie-Modulu $id 'Usun' $dane $n))
  }
  $inst = Do-Instalacji $zm
  $prog = Programy-Dla $inst $nowa
  if ($prog.Count -gt 0) { [void]$plan.Add((Zadanie-Zaleznosci 'Instaluj' $prog)) }
  foreach ($id in $inst) {
    $n = Nazwa-Modulu $id
    if (($id -eq 'kopia') -and $zm.KopiaZmieniona) { $n = 'Kopia zapasowa: nowe ustawienia' }
    elseif (-not $nowa) { $n = "Dodaję: $n" }
    [void]$plan.Add((Zadanie-Modulu $id 'Instaluj' $false $n))
  }
  if ($nowa -or $zm.Cokolwiek) {
    $z = Nowe-Zadanie -Id 'zasady' -Napis 'Zasady MegaRuchacza dla Twoich narzędzi AI' -Plik (Sciezka-Skryptu 'wpisz-zasady.ps1') -Argumenty (@('-Zrodlo', $script:Zrodlo, '-KatalogDomowy', $script:Dom) + $(if ($script:Proba) { @('-Proba') } else { @() })) -Umowa $false
    [void]$plan.Add($z)
  }
  return ,$plan
}

# Pliki, bez ktorych planu nie da sie wykonac - lepiej powiedziec to przed startem niz
# w polowie instalacji.
function Brakujace-Skrypty($plan) {
  $w = @()
  foreach ($z in $plan) { if ($z.Plik -and -not (Test-Path -LiteralPath $z.Plik)) { $w += $z.Plik } }
  return ,$w
}

# --- rejestr instalacji (narzedzia\instalacja\stan.ps1) --------------------------

# Pierwszy krok planu: obecny stan modulow wprost (bez domyslnych zgadywanych przy braku
# pliku), ustawienia kopii i wykryte narzedzia. Moduly zmieniaja sie dopiero po udanym
# kroku (Ustaw-Flage-Modulu) - rejestr nigdy nie twierdzi, ze cos jest, zanim to jest.
function Zapamietaj-Wybor {
  if ($script:Proba) { return @{ Stan = 'pominiety'; Komunikat = 'próba - nic nie zapisuję' } }
  $s = Czytaj-Instalacje $script:Dom
  if ($s.blad) { return @{ Stan = 'blad'; Komunikat = "Nie umiem odczytać zapisu instalacji: $($s.blad)" } }
  foreach ($id in $script:MODULY.Keys) { $s.moduly | Add-Member -NotePropertyName $id -NotePropertyValue ([bool]$script:Obecne[$id]) -Force }
  if ($script:Wybor.Moduly['kopia']) {
    $kopia = New-Object PSObject
    $kopia | Add-Member -NotePropertyName zrodla -NotePropertyValue ([string[]](Zaznaczone-Zrodla))
    $kopia | Add-Member -NotePropertyName cel -NotePropertyValue ([System.IO.Path]::GetFullPath("$($script:Wybor.KopiaCel)".Trim()).TrimEnd('\'))
    # Wykluczenia w formacie kopia-zapasowa.ps1 (P59d): {sciezka, powod, katalog}; bez "katalog" = katalog i plik.
    $wy = @()
    foreach ($x in (Zaznaczone-Wykluczenia)) {
      $o = [ordered]@{ sciezka = $x.Sciezka; powod = $x.Powod }
      if ($null -ne $x.Katalog) { $o['katalog'] = [bool]$x.Katalog }
      $wy += [pscustomobject]$o
    }
    $kopia | Add-Member -NotePropertyName wykluczenia -NotePropertyValue ([object[]]$wy)
    $s | Add-Member -NotePropertyName kopia -NotePropertyValue $kopia -Force
  }
  $n = New-Object PSObject
  foreach ($x in $script:Narzedzia) { $n | Add-Member -NotePropertyName $x.Id -NotePropertyValue ([bool]$x.Jest) }
  $s | Add-Member -NotePropertyName narzedzia -NotePropertyValue $n -Force
  Zapisz-Instalacje $s $script:Dom
  Zapisz-Dziennik "rejestr: zapisany stan poczatkowy ($(Sciezka-Instalacji $script:Dom))"
  return @{ Stan = 'ok'; Komunikat = '' }
}

function Ustaw-Flage-Modulu([string]$id, [bool]$wartosc, [bool]$bezUstawienKopii) {
  $script:Obecne[$id] = $wartosc
  if ($script:Proba) { return }
  $s = Czytaj-Instalacje $script:Dom
  if ($s.blad) { throw "nie zapisalem w rejestrze, ze $id = $wartosc - odczyt rejestru byl bledny: $($s.blad)" }
  $s.moduly | Add-Member -NotePropertyName $id -NotePropertyValue $wartosc -Force
  if ($bezUstawienKopii) { $s | Add-Member -NotePropertyName kopia -NotePropertyValue $null -Force }
  Zapisz-Instalacje $s $script:Dom
  Zapisz-Dziennik "rejestr: $id = $wartosc"
}

# Uszkodzony rejestr: plik zostaje (przemianowany), nic nie jest kasowane. Po odlozeniu
# odczyt wraca do zasad "bez pliku" - instalacja sprzed rejestru, wszystko wlaczone.
function Odloz-Uszkodzony-Rejestr {
  $p = Sciezka-Instalacji $script:Dom
  $nowa = "$p.uszkodzony-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
  Move-Item -LiteralPath $p -Destination $nowa
  Zapisz-Dziennik "rejestr: uszkodzony plik odlozony jako $nowa"
  return $nowa
}

# Znacznik dla okno.ps1: ten plik wczytal sie do konca.
$script:ModulyInstalatora["dane"] = $true
