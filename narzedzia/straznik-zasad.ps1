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
#   powershell -NoProfile -File narzedzia\straznik-zasad.ps1 -Tlo
#       tryb bezobslugowy - z niego korzysta hook SessionStart Codeksa, bo Codex
#       nie wciaga wyjscia tego hooka do kontekstu modelu. Robi to samo co
#       przebieg zwykly (pobranie nowszej wersji narzedzia, pilnowanie plikow
#       zasad, nanoszenie poprawek na wdrozenie), tylko nic nie wypisuje na
#       ekran - slad zostaje w dzienniku, bo w tle nie ma kto czytac komunikatow.
#   -KatalogDomowy  podstawiony katalog domowy - do testow

param(
  [string]$Zrodlo = "",
  [string]$Projekt = "",
  [string]$KatalogDomowy = $HOME,
  [string]$Odrzuc = "",
  [switch]$Moduly,
  [switch]$Tlo
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
  try { Zapisz-Tekst $plikDziennika (($wszystkie -join "`r`n") + "`r`n") } catch { }
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

  $dodane = @()
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

  # Nowy hook nie ruszy sam z siebie - zatwierdza go czlowiek. Cicha podmiana
  # pliku znaczylaby, ze uzytkownik czeka na cos, co nigdy nie wystartuje.
  $dodane = Napraw-Hooki-Codex $celCodex $zrodlo $projekt $stempel
  if ($dodane.Count -gt 0) {
    Mow ("MegaRuchacz: doszedl hook Codeksa (" + (($dodane | Select-Object -Unique) -join ", ") +
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
  # nie ma: tam czestotliwosc ustawia harmonogram, a nie liczba otwartych okien.
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
    if ($rozne) { Zapisz-Klucze $plikStanu $skroty }
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
    Zapisz-Klucze $plikStanu $nowe
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

  # Tryb bezobslugowy - na maszynie z samym Codeksem to JEDYNA droga aktualizacji,
  # bo wola go hook SessionStart. Dlatego robimy tu wszystko, co nanosi zmiany:
  # pobranie nowszej wersji narzedzia, pliki zasad i poprawki na wdrozenie.
  # Komunikaty ida przez Mow, wiec propozycje i ostrzezenia nie gina - laduja
  # w dzienniku, bo tutaj nie ma ekranu, na ktory dalo by sie je wypisac.
  # Poczekalnia faktow i meldunek o cyklu zostaja poza tym trybem: to prosby
  # do czlowieka, a nie zmiany na dysku, wiec w dzienniku nikt ich nie przeczyta.
  if ($Tlo) {
    try { Odswiez-Zrodlo } catch { Mow "odswiezanie zrodla wywrocilo sie: $($_.Exception.Message)" }
    try { Pilnuj-Zasad }   catch { Mow "pilnowanie zasad wywrocilo sie: $($_.Exception.Message)" }
    try { Pilnuj-Wersji }  catch { Mow "pilnowanie wersji wdrozenia wywrocilo sie: $($_.Exception.Message)" }
    Dopisz-Dziennik
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
