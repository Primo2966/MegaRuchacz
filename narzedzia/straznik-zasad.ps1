# Straznik - pilnuje trzech rzeczy przy kazdym otwarciu okna:
#   0. czy sam katalog zrodlowy narzedzia nie zostal w tyle za zdalnym repo,
#   1. czy blok zasad globalnych MegaRuchacza nadal siedzi w ~/.claude/CLAUDE.md,
#   2. czy wdrozenie w projekcie nie zostalo w tyle za katalogiem zrodlowym.
#
# Wolany przez hook SessionStart, wiec zasada nadrzedna brzmi: gdy wszystko sie
# zgadza, NIC nie wypisuje i nie robi nic drogiego. Porownania ida po skrocie
# tresci i po numerze wersji. Jedyne siegniecie do sieci to krotki "git fetch"
# w katalogu zrodlowym, najwyzej raz na godzine i z limitem czasu - bez niego
# punkt 2. porownywalby wdrozenie ze staroscia i zawsze wychodzilo mu, ze gra.
#
# Uzycie:
#   powershell -NoProfile -File narzedzia\straznik-zasad.ps1 [-Zrodlo <repo>] [-Projekt <katalog>]
#   powershell -NoProfile -File narzedzia\straznik-zasad.ps1 -Odrzuc <modul>
#       zapamietuje, ze modul (albo nowa funkcja w nim) ma zostac niewlaczony
#   powershell -NoProfile -File narzedzia\straznik-zasad.ps1 -Moduly
#       wypisuje rejestr modulow w JSON-ie; z tego korzysta wdroz.ps1
#   -KatalogDomowy  podstawiony katalog domowy - do testow

param(
  [string]$Zrodlo = "",
  [string]$Projekt = "",
  [string]$KatalogDomowy = $HOME,
  [string]$Odrzuc = "",
  [switch]$Moduly
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

$POCZATEK = "<!-- MegaRuchacz:start -->"
$KONIEC   = "<!-- MegaRuchacz:koniec -->"

$plikDomowy   = Join-Path $KatalogDomowy ".claude\CLAUDE.md"
$plikStanu    = Join-Path $KatalogDomowy ".claude\.megaruchacz-straznik.txt"
$plikWersji   = Join-Path $Projekt ".claude\megaruchacz-wersja.txt"
# Znacznik ostatniego zagladania do sieci. Lezy w katalogu domowym, a nie przy
# pliku wersji projektu, bo katalog zrodlowy jest jeden na maszyne: dziesiec
# otwartych okien ma go odpytac raz, nie dziesiec razy.
$plikPobrania = Join-Path $KatalogDomowy ".claude\.megaruchacz-pobranie.txt"
$MINUT_MIEDZY_POBRANIAMI = 60

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
function Czytaj-Klucze($sciezka) {
  $stan = [ordered]@{}
  $raw = Czytaj-Tekst $sciezka
  if (-not $raw) { return $stan }
  foreach ($l in ($raw -split '\r?\n')) {
    $m = [regex]::Match($l, '^\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*:\s*(.*?)\s*$')
    if ($m.Success) { $stan[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $stan
}

function Zapisz-Klucze($sciezka, $stan) {
  $linie = @()
  foreach ($k in $stan.Keys) { $linie += ("{0}: {1}" -f $k, $stan[$k]) }
  Zapisz-Tekst $sciezka (($linie -join "`r`n") + "`r`n")
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
    $doDodania += ,@("UserPromptSubmit", 'cat "$CLAUDE_PROJECT_DIR/.claude/orchestrator-reminder.json" 2>/dev/null || cat .claude/orchestrator-reminder.json', 5)
  }
  if ($raw -notlike "*mr-log.js*") {
    $doDodania += ,@("SubagentStart", 'node "$CLAUDE_PROJECT_DIR/.claude/mr-log.js"', 5)
    $doDodania += ,@("SubagentStop",  'node "$CLAUDE_PROJECT_DIR/.claude/mr-log.js" stop', 5)
  }
  if ($raw -notlike "*straznik-zasad.ps1*") {
    $doDodania += ,@("SessionStart", 'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
      $r + '/narzedzia/straznik-zasad.ps1" -Zrodlo "' + $r + '" -Projekt "$CLAUDE_PROJECT_DIR" || true', 15)
  }
  if ($doDodania.Count -eq 0) { return $false }

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

# Nanosi poprawki na pliki nalezace do narzedzia. NIE rusza plikow stanu
# (worklog.md, mapa.md) - to praca uzytkownika.
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
  # dla kazdego katalogu zrodlowego - stad skrot sciezki w kluczu.
  $klucz = "z" + (Skrot $Zrodlo.ToLower())
  $stanP = Czytaj-Klucze $plikPobrania
  $kiedy = [datetime]::MinValue
  if ($stanP[$klucz] -and [datetime]::TryParse($stanP[$klucz], [ref]$kiedy)) {
    if (([datetime]::Now - $kiedy).TotalMinutes -lt $MINUT_MIEDZY_POBRANIAMI) { return }
  }
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return }

  $cyt = '"' + $Zrodlo.TrimEnd('\') + '"'
  $repo = Wolaj-Gita "-C $cyt rev-parse --is-inside-work-tree" 5
  if (-not $repo.ok -or $repo.tekst -ne "true") { return }   # to nie repozytorium

  # Od tej chwili proba byla prawdziwa - znacznik idzie na dysk niezaleznie od
  # wyniku, zeby nieudane pobranie nie powtarzalo sie przy kazdym oknie.
  $stanP[$klucz] = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  Zapisz-Klucze $plikPobrania $stanP

  $brudne = Wolaj-Gita "-C $cyt status --porcelain" 5
  if (-not $brudne.ok) { return }
  if ($brudne.tekst) {
    Write-Host "MegaRuchacz: w $Zrodlo sa niezapisane zmiany - nie pobieram nowszej wersji narzedzia, pracuje na tej, ktora jest."
    return
  }

  # Galaz bez zdalnej (albo odpiety HEAD) - nie ma czego i skad pobierac.
  $zdalna = Wolaj-Gita "-C $cyt rev-parse --abbrev-ref --symbolic-full-name @{u}" 5
  if (-not $zdalna.ok -or -not $zdalna.tekst) { return }

  $plikZmian = Join-Path $Zrodlo "ZMIANY.md"
  $przedWersja = Wersja-Narzedzia $plikZmian

  # Zadnych pytan o haslo - okno sesji nie ma gdzie na nie odpowiedziec.
  # Limity czasu sa krotkie z premedytacja: caly hook ma 15 sekund, a start
  # okna nie moze na nas czekac. Gdy sie nie wyrobimy, wracamy po godzinie.
  $env:GIT_TERMINAL_PROMPT = "0"
  $pobrane = Wolaj-Gita "-C $cyt -c credential.interactive=never fetch --quiet" 6
  if (-not $pobrane.ok) { return }   # brak sieci to nie jest blad

  $licznik = Wolaj-Gita "-C $cyt rev-list --left-right --count HEAD...@{u}" 5
  if (-not $licznik.ok) { return }
  $czesci = $licznik.tekst -split '\s+'
  if ($czesci.Count -lt 2) { return }
  $nasze = [int]$czesci[0]   # commity lokalne, ktorych nie ma na zdalnej
  $zdalne = [int]$czesci[1]  # commity zdalne, ktorych nie mamy u siebie
  if ($zdalne -le 0) { return }   # nic nowego - cisza, tak jak reszta straznika

  if ($nasze -gt 0) {
    Write-Host "MegaRuchacz: historia w $Zrodlo rozjechala sie ze zdalna ($nasze lokalnych, $zdalne zdalnych) - nie scalam sam, zrob to recznie."
    return
  }

  # Tylko proste przewiniecie do przodu. Gdy git odmowi, zostajemy przy starym.
  $scalone = Wolaj-Gita "-C $cyt merge --ff-only @{u}" 6
  if (-not $scalone.ok) {
    Write-Host "MegaRuchacz: nie udalo sie przewinac $Zrodlo do nowszej wersji - pracuje na tej, ktora jest."
    return
  }

  # Cicha aktualizacja jest gorsza niz jej brak - zawsze jedna linia o tym,
  # co sie wlasnie zmienilo pod reka uzytkownika.
  $poWersja = Wersja-Narzedzia $plikZmian
  if ($przedWersja -and $poWersja -and $przedWersja -ne $poWersja) {
    Write-Host "MegaRuchacz: narzedzie podciagniete z gita - wersja ${przedWersja} -> ${poWersja} (co doszlo: $plikZmian)"
  } else {
    $slowo = if ($zdalne -eq 1) { "nowa zmiana" } else { "nowych zmian" }
    Write-Host "MegaRuchacz: narzedzie podciagniete z gita - $zdalne $slowo, numer wersji bez zmian (co doszlo: $plikZmian)"
  }
}

# --------------------------------------------------------- 1. zasady globalne
function Pilnuj-Zasad {
  $oczekiwane = Tresc-Zrodla (Join-Path $Zrodlo "zasady-globalne.md")
  if (-not $oczekiwane) { return }
  $blok = Tresc-Bloku $plikDomowy

  $skrotZrodla = Skrot (Znormalizuj $oczekiwane)
  $skrotBloku  = Skrot (Znormalizuj $blok)

  # Zgodne, gdy blok zawiera tresc ze zrodla, albo gdy oba skroty sa takie same
  # jak przy ostatnim udanym wpisie - to drugie ratuje nas, gdyby wpisz-zasady.ps1
  # skladalo blok inaczej, niz wyglada surowe zrodlo.
  $zgodne = $false
  if ($blok) {
    if ((Znormalizuj $blok).Contains((Znormalizuj $oczekiwane))) {
      $zgodne = $true
    } else {
      $stan = Czytaj-Klucze $plikStanu
      if ($stan["zrodlo"] -eq $skrotZrodla -and $stan["blok"] -eq $skrotBloku) { $zgodne = $true }
    }
  }

  if ($zgodne) {
    $stan = Czytaj-Klucze $plikStanu
    if ($stan["zrodlo"] -ne $skrotZrodla -or $stan["blok"] -ne $skrotBloku) {
      Zapisz-Klucze $plikStanu ([ordered]@{ zrodlo = $skrotZrodla; blok = $skrotBloku })
    }
    return
  }

  $powod = if ($blok) { "byly nieaktualne" } else { "zniknely" }
  $wpisz = Join-Path $Zrodlo "narzedzia\wpisz-zasady.ps1"
  if (-not (Test-Path $wpisz)) {
    Write-Host "MegaRuchacz: zasady globalne $powod w $plikDomowy, a nie ma $wpisz - wpisz je recznie."
    return
  }
  $kod = 1
  try {
    $global:LASTEXITCODE = 0
    & $wpisz -Zrodlo $Zrodlo -KatalogDomowy $KatalogDomowy *>&1 | Out-Null
    $kod = $LASTEXITCODE
  } catch { $kod = 1 }

  $poNaprawie = Tresc-Bloku $plikDomowy
  if ($kod -eq 0 -and $poNaprawie) {
    Zapisz-Klucze $plikStanu ([ordered]@{ zrodlo = $skrotZrodla; blok = (Skrot (Znormalizuj $poNaprawie)) })
    Write-Host "MegaRuchacz: zasady globalne $powod w $plikDomowy - wpisalem je z powrotem."
  } else {
    Write-Host "MegaRuchacz: zasady globalne $powod, a odtworzenie nie wyszlo (kod $kod) - uruchom $wpisz recznie."
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
      Write-Host "MegaRuchacz: jest modul [$($m.nazwa)] - $($m.opis). Kosztuje: $($m.koszt)."
      Write-Host "  Wlaczyc: powershell -File $Zrodlo\wdroz.ps1   Odrzucic: powershell -File $PSCommandPath -Odrzuc $($m.nazwa)"
      continue
    }

    try { $stara = [version]$wdrozona } catch { continue }
    if ($nowa -le $stara) { continue }

    # Pierwsza cyfra = przebudowa lamiaca zgodnosc. Nic nie nanosimy sami.
    if ($nowa.Major -gt $stara.Major) {
      if ($stan["$k.zapowiedziane"] -eq $wZrodla) { continue }
      $stan["$k.zapowiedziane"] = $wZrodla
      $zmiana = $true
      Write-Host "MegaRuchacz: modul [$($m.nazwa)] w wersji $wZrodla lamie zgodnosc z wdrozona $wdrozona - nic nie nanioslem sam, wdroz recznie: powershell -File $Zrodlo\wdroz.ps1 (opis: $plikZmian)"
      continue
    }

    # Modul, ktorego aktualizacja moze kosztowac (pobieranie, harmonogram) -
    # sami go nie ruszamy, podajemy komende.
    if ($m.aktualizacja -ne "pliki") {
      if ($stan["$k.zapowiedziane"] -eq $wZrodla) { continue }
      $stan["$k.zapowiedziane"] = $wZrodla
      $zmiana = $true
      Write-Host "MegaRuchacz: modul [$($m.nazwa)] ma nowsza wersje $wZrodla (wdrozona $wdrozona) - zastosuj: powershell -File $Zrodlo\$($m.instalator) -Zrodlo $Zrodlo"
      continue
    }

    Nanies-Poprawki $Zrodlo $Projekt
    $stan["$k.wersja"] = $wZrodla
    $stan["$k.data"] = (Get-Date -Format 'yyyy-MM-dd HH:mm')
    $zmiana = $true
    Write-Host "MegaRuchacz: modul [$($m.nazwa)] zaktualizowany $stara -> $wZrodla (co doszlo: $plikZmian)"

    # Druga cyfra = nowa funkcja. Poprawki weszly, ale funkcji nie wlaczamy sami -
    # potrafi kosztowac miejsce, pobieranie albo dostep do danych.
    if ($nowa.Minor -gt $stara.Minor -and $stan["$k.odrzucone"] -ne $wZrodla) {
      if ($stan["$k.zaproponowane"] -eq $wZrodla) {
        Write-Host "  Nowa funkcja z $wZrodla nadal niewlaczona - wlacz: powershell -File $Zrodlo\wdroz.ps1 ; odrzuc: powershell -File $PSCommandPath -Odrzuc $($m.nazwa)"
      } else {
        $stan["$k.zaproponowane"] = $wZrodla
        Write-Host "  Wersja $wZrodla przynosi nowa funkcje, ktorej NIE wlaczylem sam (za $plikZmian):"
        foreach ($l in (Wpis-Zmian $plikZmian $wZrodla | Select-Object -First 4)) { Write-Host "    $l" }
        Write-Host "  Wlaczyc: powershell -File $Zrodlo\wdroz.ps1   Odrzucic: powershell -File $PSCommandPath -Odrzuc $($m.nazwa)"
      }
    }
  }

  if ($zmiana) { Zapisz-Klucze $plikWersji $stan }
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
  # tak jak reszta straznika. Koszt pamieci doliczamy dopiero, gdy linia i tak idzie
  # na ekran: liczy go osobny skrypt i nie ma za co placic przy kazdym otwarciu okna.
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

    $koszt = ""
    $skrypt = Join-Path $Zrodlo "narzedzia\koszt-pamieci.ps1"
    if (Test-Path $skrypt) {
      try { $koszt = (& $skrypt -KatalogDomowy $KatalogDomowy -Zwiezle | Select-Object -First 1) } catch { $koszt = "" }
    }
    if ($koszt) { Write-Host "MegaRuchacz: $stan. $koszt" }
    else        { Write-Host "MegaRuchacz: $stan." }
  }

  # Osobne try, zeby potkniecie sie na jednym nie zabralo drugiego.
  # Pobranie idzie pierwsze - reszta porownuje sie z katalogiem zrodlowym,
  # wiec ma sens dopiero wtedy, gdy ten katalog jest swiezy.
  try { Odswiez-Zrodlo }   catch { }
  try { Pilnuj-Zasad }     catch { }
  try { Pilnuj-Wersji }    catch { }
  try { Zglos-Kandydatow } catch { }
  try { Zglos-Cykl }       catch { }
} catch { }
exit 0
