# Instalacja GLOBALNA MegaRuchacza - jedna, dla wszystkich projektow i wszystkich
# narzedzi naraz. Odpowiednik wdroz.ps1, ktory wdraza tryb do JEDNEGO projektu.
#
# Co robi (tylko dla narzedzi, ktore widzi na maszynie):
#   opencode    ~/.config/opencode/agents/*.md      cztery role + wtyczka rejestru
#               ~/.config/opencode/plugins/mr-log.js
#   Claude Code ~/.claude/agents/*.md               cztery role
#               ~/.claude/megaruchacz-mr-log.js     rejestr workerow
#               ~/.claude/mr/orchestrator-reminder.json  ladunek przypomnienia
#               ~/.claude/settings.json             JEDEN komplet hookow: straznik
#                                                   (SessionStart), przypomnienie.js
#                                                   (UserPromptSubmit), rejestr
#                                                   (SubagentStart/Stop). Uklada je
#                                                   straznik-zasad.ps1 -NaprawGlobalne;
#                                                   ponowne uruchomienie naprawia
#                                                   (duplikaty, stare "cat"), nie dubluje.
#   Codex       ~/.codex/AGENTS.md                  blok zasad kierownika
#               ~/.codex/hooks.json                 DOPISANE hooki rejestru
#   zasady      blok miedzy znacznikami MegaRuchacz:kierownik, w wariancie
#               wlasciwym dla narzedzia, ktore dany plik czyta:
#               ~/.claude/CLAUDE.md  <- szablony-global\claude\zasady-kierownika.md
#                                       (Claude Code: praca w tle, worktree);
#                                       na maszynie, na ktorej Claude Code nie
#                                       pracuje, wariant opencode/Codex - ten plik
#                                       czyta wtedy tylko opencode
#               ~/.codex/AGENTS.md   <- szablony-opencode\zasady-kierownika.md
#                                       (jak dotad, bez zmian)
#               opencode czyta pierwszy istniejacy z ~/.config/opencode/AGENTS.md
#               i ~/.claude/CLAUDE.md (sprawdzone w opencode 1.18.32) - na
#               maszynie z Claude Code i opencode dostaje wiec wariant Claude Code.
#               Wymuszenie wariantu: -WariantZasad claude|opencode.
#   znacznik    ~/.claude/.megaruchacz-global       fakt instalacji globalnej
#
# Stan pracy (rejestr i mapa) zostaje w PROJEKCIE, w .megaruchacz\ - zaklada go
# pierwszy worker, gdy zajdzie potrzeba. Dzieki temu nic nie zalega w projektach,
# w ktorych nie rozdajesz roboty.
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File narzedzia\instaluj-globalnie.ps1
#   -Usun        zdejmuje wszystko, co ta instalacja zalozyla
#   -Proba       pokazuje plan, nic nie zapisuje
#   -KatalogDomowy <kat>   do testow (podmienia baze ~\)
#   -WariantZasad auto|claude|opencode   wariant bloku w ~/.claude/CLAUDE.md;
#                auto (domyslnie) = claude, gdy Claude Code na tej maszynie pracuje
#                (sa jego wlasne pliki: ~/.claude/history.jsonl albo ~/.claude.json)
#
# UWAGA: instalacja globalna ZASTEPUJE per-projektowa czesc rejestru. Jesli masz
# gdzies wdroz.ps1, po instalacji globalnej uruchom go tam ponownie - wykryje
# instalacje globalna i nie dolozy drugiego wpisu do rejestru.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [string]$KatalogDomowy = $HOME,
  [switch]$BezPytania,
  [switch]$Usun,
  [switch]$Proba,
  [ValidateSet("auto", "claude", "opencode")]
  [string]$WariantZasad = "auto"
)

$Stempel = Get-Date -Format "yyyyMMdd-HHmmss"
$script:Kopie = @()
$script:Bledy = @()
$script:Niepelne = @()

$POCZATEK = "<!-- MegaRuchacz:kierownik:start -->"
$KONIEC   = "<!-- MegaRuchacz:kierownik:koniec -->"

$Utf8Zapis  = New-Object System.Text.UTF8Encoding($false)
$Utf8Odczyt = New-Object System.Text.UTF8Encoding($false, $true)

function Kopia-Zapasowa($sciezka) {
  if (Test-Path $sciezka) {
    $bak = "$sciezka.bak-$Stempel"
    Copy-Item $sciezka $bak -Force
    $script:Kopie += $bak
  }
}

function Sprawdz($opis, $ok, $czemu) {
  if ($ok) { Write-Host "  OK    $opis" }
  else { Write-Host "  BLAD  $opis - $czemu" -ForegroundColor Red; $script:Bledy += $opis }
}

function Nie-Sprawdzono($tekst) { $script:Niepelne += $tekst }

function Czytaj($sciezka) { return [System.IO.File]::ReadAllText($sciezka, $Utf8Odczyt) }
function Zapisz($sciezka, $tekst) { [System.IO.File]::WriteAllText($sciezka, $tekst, $Utf8Zapis) }

function Tak-Czy-Nie($pytanie) {
  $odp = Read-Host "$pytanie [t/N]"
  return ($odp -match '^(t|tak|y|yes)$')
}

# --- blok zasad kierownika w pliku instrukcji --------------------------------
# Ten sam mechanizm co wpisz-zasady.ps1: wstawiamy/podmieniamy blok miedzy
# znaczniki, reszta pliku (wlasne zapiski) zostaje nietknieta, przed zmiana kopia.
function Wstaw-Blok($plik, $nazwa, $tresc) {
  $istnieje = Test-Path $plik
  $stary = ""
  if ($istnieje) {
    try { $stary = Czytaj $plik }
    catch { Write-Host "BLAD  $nazwa - nie umiem odczytac $plik jako UTF-8, nie ruszam" -ForegroundColor Red; $script:Bledy += $nazwa; return }
  }
  $nl = if ($stary.Contains("`r`n")) { "`r`n" } else { "`n" }
  # Konce linii bloku jak w reszcie pliku - szablon w repo bywa CRLF (autocrlf),
  # a plik docelowy LF; bez tego blok mieszalby oba rodzaje w jednym pliku.
  $t = $tresc.Trim() -replace "`r`n", "`n"
  if ($nl -eq "`r`n") { $t = $t -replace "`n", "`r`n" }
  $blok = ($POCZATEK, $t, $KONIEC) -join $nl
  # Dwa bloki to dubel, ktorego podmiana pierwszego nie usunie - glosno, bez zapisu.
  $ile = ([regex]::Matches($stary, [regex]::Escape($POCZATEK))).Count
  if ($ile -gt 1) { Write-Host "BLAD  $nazwa - w $plik jest $ile blokow kierownika (dubel), nie ruszam - usun nadmiarowe recznie" -ForegroundColor Red; $script:Bledy += $nazwa; return }
  $i = $stary.IndexOf($POCZATEK, [System.StringComparison]::Ordinal)
  $j = $stary.IndexOf($KONIEC, [System.StringComparison]::Ordinal)
  if (($i -ge 0) -xor ($j -ge 0)) { Write-Host "BLAD  $nazwa - tylko jeden znacznik w $plik, nie ruszam" -ForegroundColor Red; $script:Bledy += $nazwa; return }
  if ($i -ge 0) {
    $nowy = $stary.Substring(0, $i) + $blok + $stary.Substring($j + $KONIEC.Length)
    $co = "podmieniam blok"
  } elseif ($stary.Trim().Length -eq 0) {
    $nowy = $blok + $nl; $co = "zakladam plik z blokiem"
  } else {
    $nowy = $stary.TrimEnd("`r", "`n") + $nl + $nl + $blok + $nl; $co = "dopisuje blok na koncu"
  }
  if ($nowy -ceq $stary) { Write-Host "--  $nazwa - blok juz aktualny"; return }
  if ($Proba) { Write-Host "PROBA  $nazwa - $co ($plik)"; return }
  if ($istnieje) { Kopia-Zapasowa $plik }
  else { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $plik) | Out-Null }
  Zapisz $plik $nowy
  Write-Host "OK  $nazwa - $co"
}

function Usun-Blok($plik, $nazwa) {
  if (-not (Test-Path $plik)) { return }
  try { $stary = Czytaj $plik } catch { return }
  $i = $stary.IndexOf($POCZATEK, [System.StringComparison]::Ordinal)
  $j = $stary.IndexOf($KONIEC, [System.StringComparison]::Ordinal)
  if ($i -lt 0 -or $j -lt $i) { return }
  if ($Proba) { Write-Host "PROBA  $nazwa - wycialbym blok z $plik"; return }
  Kopia-Zapasowa $plik
  $nl = if ($stary.Contains("`r`n")) { "`r`n" } else { "`n" }
  $przed = $stary.Substring(0, $i).TrimEnd("`r", "`n")
  $po    = $stary.Substring($j + $KONIEC.Length).TrimStart("`r", "`n")
  if ($przed.Length -eq 0) { $nowy = $po }
  elseif ($po.Length -eq 0) { $nowy = $przed + $nl }
  else { $nowy = $przed + $nl + $nl + $po }
  Zapisz $plik $nowy
  Write-Host "OK  $nazwa - blok wyciety"
}

# --- role (agenci) -----------------------------------------------------------
# Swoje pliki rozpoznajemy po znaczniku kierownik-template. Cudzy plik o tej
# samej nazwie dostaje kopie zapasowa, ale i tak go nadpisujemy - to instalacja
# naszych rol, nie scalanie z cudzymi.
function Wstaw-Agentow($zrodlo, $cel, $filtr, $co) {
  if (-not (Test-Path $zrodlo)) { Write-Host "UWAGA  brak szablonow: $zrodlo" -ForegroundColor Yellow; return }
  New-Item -ItemType Directory -Force -Path $cel | Out-Null
  Get-ChildItem (Join-Path $zrodlo $filtr) -ErrorAction SilentlyContinue | ForEach-Object {
    $dokad = Join-Path $cel $_.Name
    if ((Test-Path $dokad) -and -not ((Get-Content $dokad -Raw) -match "kierownik-template")) {
      Kopia-Zapasowa $dokad
      Write-Host "UWAGA  masz wlasny $co\$($_.Name) - odlozylem kopie obok" -ForegroundColor Yellow
    }
    if ($Proba) { Write-Host "PROBA  $co\$($_.Name)" } else { Copy-Item $_.FullName $dokad -Force }
  }
  if (-not $Proba) { Write-Host "OK  $co - role na miejscu" }
}

# --- hooki w settings.json (Claude Code) i hooks.json (Codex) -----------------
# Dokladamy grupe z wlasnym statusMessage, nie ruszamy cudzych. Swoje poznajemy
# po fragmentcie polecenia.
function Dopisz-Hook($plik, $jsonPole, $zdarzenie, $grupa, $znacznik) {
  $s = [pscustomobject]@{}
  if (Test-Path $plik) {
    try {
      $raw = Czytaj $plik
      if ($raw.Trim().Length -gt 0) { $s = $raw.TrimStart([char]0xFEFF) | ConvertFrom-Json }
    } catch {
      Write-Host "UWAGA  $plik nie jest czystym JSON-em - nie ruszam go" -ForegroundColor Yellow
      return $false
    }
  }
  $pole = $jsonPole
  if (-not ($s.PSObject.Properties.Name -contains $pole) -or $null -eq $s.$pole) {
    $s | Add-Member -NotePropertyName $pole -NotePropertyValue ([pscustomobject]@{}) -Force
  }
  $lista = @()
  if ($s.$pole.PSObject.Properties.Name -contains $zdarzenie) { $lista = @($s.$pole.$zdarzenie) }
  foreach ($g in $lista) { if ((($g | ConvertTo-Json -Depth 20 -Compress)) -like "*$znacznik*") { return $false } }
  $lista += $grupa
  if ($s.$pole.PSObject.Properties.Name -contains $zdarzenie) { $s.$pole.$zdarzenie = @($lista) }
  else { $s.$pole | Add-Member -NotePropertyName $zdarzenie -NotePropertyValue @($lista) -Force }
  if ($Proba) { Write-Host "PROBA  hook $zdarzenie -> $plik"; return $true }
  Kopia-Zapasowa $plik
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $plik) | Out-Null
  Zapisz $plik ($s | ConvertTo-Json -Depth 20)
  Write-Host "OK  hook $zdarzenie -> $plik"
  return $true
}

# Ustawia klucz najwyzszego poziomu w pliku JSON (np. worktree w settings.json),
# nie ruszajac pozostalych. Idempotentnie: jesli juz taki jest, nie zmienia.
function Ustaw-Klucz-Json($plik, $klucz, $wartosc) {
  $s = [pscustomobject]@{}
  if (Test-Path $plik) {
    try {
      $raw = Czytaj $plik
      if ($raw.Trim().Length -gt 0) { $s = $raw.TrimStart([char]0xFEFF) | ConvertFrom-Json }
    } catch { Write-Host "UWAGA  $plik nie jest czystym JSON-em - nie ruszam" -ForegroundColor Yellow; return }
  }
  if ($s.PSObject.Properties.Name -contains $klucz) { return }
  if ($Proba) { Write-Host "PROBA  $klucz w $plik"; return }
  $s | Add-Member -NotePropertyName $klucz -NotePropertyValue $wartosc -Force
  Kopia-Zapasowa $plik
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $plik) | Out-Null
  Zapisz $plik ($s | ConvertTo-Json -Depth 20)
  Write-Host "OK  $klucz ustawione w $plik"
}

# =============================================================== sprawdzenie ===
if (-not (Test-Path $Zrodlo)) { Write-Error "Nie ma katalogu zrodlowego: $Zrodlo"; exit 1 }
$Zrodlo = (Resolve-Path $Zrodlo).Path
if (-not (Test-Path $KatalogDomowy)) { Write-Error "Nie ma katalogu domowego: $KatalogDomowy"; exit 1 }
$KatalogDomowy = (Resolve-Path $KatalogDomowy).Path

$Claude   = Get-Command claude   -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$Codex    = Get-Command codex    -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$Opencode = Get-Command opencode -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$Node     = Get-Command node     -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1

$DomClaude   = Join-Path $KatalogDomowy ".claude"
$DomCodex    = Join-Path $KatalogDomowy ".codex"
$DomOpencode = Join-Path $KatalogDomowy ".config\opencode"
$JestClaude   = ($null -ne $Claude)   -or (Test-Path $DomClaude)
$JestCodex    = ($null -ne $Codex)    -or (Test-Path $DomCodex)
$JestOpencode = ($null -ne $Opencode) -or (Test-Path $DomOpencode)

# Zasady kierownika w dwoch wariantach - kazdy plik instrukcji dostaje ten, ktory
# pasuje do narzedzia, ktore go czyta. Do 0.21.0 oba pliki dostawaly wariant
# opencode/Codex, takze Claude Code (raport P5): "rozdaj naraz i czekaj", "nie ma
# worktree", "worker nie moze pytac" - wszystko nieprawda pod Claude Code.
$PlikZasadClaude   = Join-Path $Zrodlo "szablony-global\claude\zasady-kierownika.md"
$PlikZasadOpencode = Join-Path $Zrodlo "szablony-opencode\zasady-kierownika.md"
foreach ($p in @($PlikZasadClaude, $PlikZasadOpencode)) {
  if (-not (Test-Path $p)) { Write-Error "Brak szablonu zasad: $p"; exit 1 }
}
$TrescZasadClaude   = (Czytaj $PlikZasadClaude).Trim()
$TrescZasadOpencode = (Czytaj $PlikZasadOpencode).Trim()

# Czy Claude Code na tej maszynie PRACUJE. Po plikach, ktore prowadzi sam - katalog
# ~\.claude zaklada tez MegaRuchacz (Lore, wiedza), a na domowej maszynie claude.exe
# lezy w PATH, choc Claude Code nie jest tam uzywany. To samo rozroznienie robia
# straznik-zasad.ps1 (Cisza-Claude-Linia) i koszt-pamieci.ps1.
$PracujeClaude = (Test-Path (Join-Path $KatalogDomowy ".claude\history.jsonl")) -or
                 (Test-Path (Join-Path $KatalogDomowy ".claude.json"))
$Wariant = $WariantZasad
if ($Wariant -eq "auto") { $Wariant = if ($PracujeClaude) { "claude" } else { "opencode" } }
$TrescZasadDomowa = if ($Wariant -eq "claude") { $TrescZasadClaude } else { $TrescZasadOpencode }
$PlikZasadDomowy  = if ($Wariant -eq "claude") { $PlikZasadClaude } else { $PlikZasadOpencode }
# Hooki Claude Code uklada i naprawia straznik (tryb -NaprawGlobalne / -UsunGlobalne).
$Straznik = Join-Path $Zrodlo "narzedzia\straznik-zasad.ps1"
if (-not (Test-Path $Straznik)) { Write-Error "Brak straznika: $Straznik"; exit 1 }

# Ile hookow na danym zdarzeniu ma polecenie pasujace do wzorca. -1 = plik nie jest JSON-em.
function Policz-Hooki($plik, $zdarzenie, $wzor) {
  if (-not (Test-Path $plik)) { return 0 }
  try { $s = (Czytaj $plik).TrimStart([char]0xFEFF) | ConvertFrom-Json } catch { return -1 }
  if ($null -eq $s.hooks -or -not ($s.hooks.PSObject.Properties.Name -contains $zdarzenie)) { return 0 }
  $n = 0
  foreach ($g in @($s.hooks.$zdarzenie)) {
    foreach ($h in @($g.hooks)) { if ($h -and ("" + $h.command) -match $wzor) { $n++ } }
  }
  return $n
}

Write-Host ""
Write-Host "=== MegaRuchacz - instalacja GLOBALNA ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Katalog domowy: $KatalogDomowy"
Write-Host "Zrodlo:         $Zrodlo"
Write-Host ""
Write-Host "Zainstaluje tryb kierownika dla narzedzi, ktore widze:"
if ($JestClaude)   { Write-Host "  - Claude Code : role w ~/.claude/agents, rejestr + hooki w ~/.claude/settings.json, zasady w ~/.claude/CLAUDE.md (wariant: $Wariant)" }
if ($JestOpencode) { Write-Host "  - opencode    : role w ~/.config/opencode/agents, wtyczka rejestru w ~/.config/opencode/plugins, zasady przez ~/.claude/CLAUDE.md (wariant: $Wariant)" }
if ($JestCodex)    { Write-Host "  - Codex       : role w ~/.codex/agents, rejestr + hooki w ~/.codex/hooks.json, zasady w ~/.codex/AGENTS.md" }
if (-not ($JestClaude -or $JestOpencode -or $JestCodex)) { Write-Host "  (zadnego nie widze)" -ForegroundColor Yellow }
Write-Host ""
Write-Host "Stan pracy (rejestr, mapa) zostaje w KAZDYM projekcie w .megaruchacz\ -"
Write-Host "zaklada go pierwszy worker, gdy zajdzie potrzeba. Nic nie zalega bezczynnie."
Write-Host ""

if ($Usun) {
  Write-Host "TRYB USUWANIA - zdejmuje to, co zalozyla instalacja globalna." -ForegroundColor Yellow
} elseif (-not $BezPytania -and -not $Proba) {
  if (-not (Tak-Czy-Nie "Kontynuowac?")) { Write-Host "Przerwane - nic nie zmienione."; exit 0 }
}
Write-Host ""

$Marker = Join-Path $DomClaude ".megaruchacz-global"

# =============================================================== USUWANIE =====
if ($Usun) {
  Usun-Blok (Join-Path $DomClaude "CLAUDE.md") "zasady w ~/.claude/CLAUDE.md"
  Usun-Blok (Join-Path $DomCodex  "AGENTS.md") "zasady w ~/.codex/AGENTS.md"

  foreach ($r in @("implementer","scout","verifier","zastepca")) {
    foreach ($p in @((Join-Path $DomClaude "agents\$r.md"), (Join-Path $DomOpencode "agents\$r.md"))) {
      if ((Test-Path $p) -and ((Get-Content $p -Raw) -match "kierownik-template")) {
        if ($Proba) { Write-Host "PROBA  usunalbym $p" } else { Remove-Item $p -Force; Write-Host "OK  usuniete $p" }
      }
    }
  }
  foreach ($p in @((Join-Path $DomClaude "megaruchacz-mr-log.js"), (Join-Path $DomOpencode "plugins\mr-log.js"))) {
    if (Test-Path $p) { if ($Proba) { Write-Host "PROBA  usunalbym $p" } else { Remove-Item $p -Force; Write-Host "OK  usuniete $p" } }
  }
  if (Test-Path $Marker) { if ($Proba) { Write-Host "PROBA  usunalbym $Marker" } else { Remove-Item $Marker -Force; Write-Host "OK  usuniety znacznik instalacji globalnej" } }
  # Hooki MegaRuchacza w ~/.claude/settings.json - bez nich straznik chodzilby dalej
  # w kazdym projekcie. Cudze hooki (np. Orki) zostaja.
  $argiU = @{ UsunGlobalne = $true; Zrodlo = $Zrodlo; KatalogDomowy = $KatalogDomowy }
  if ($Proba) { $argiU.Proba = $true }
  $global:LASTEXITCODE = 0
  & $Straznik @argiU
  if ($LASTEXITCODE -ne 0) { Write-Host "BLAD  hookow MegaRuchacza w ~/.claude/settings.json nie udalo sie zdjac (powod wyzej)" -ForegroundColor Red }
  Write-Host ""
  Write-Host "Gotowe. Hooki rejestru Codeksa w ~/.codex/hooks.json zostaja - nastepne ich"
  Write-Host "uruchomienie nic nie dopisze. Wyczyscic je mozna recznie, jesli przeszkadzaja."
  exit 0
}

# =============================================================== ZASADY =======
Write-Host "--- zasady kierownika (globalnie) ---"
$skadWariant = if ($WariantZasad -ne "auto") { "wymuszony -WariantZasad" } elseif ($PracujeClaude) { "Claude Code tu pracuje" } else { "Claude Code tu nie pracuje" }
Write-Host "    ~/.claude/CLAUDE.md dostaje wariant: $Wariant ($skadWariant) - $PlikZasadDomowy"
Wstaw-Blok (Join-Path $DomClaude "CLAUDE.md") "zasady w ~/.claude/CLAUDE.md" $TrescZasadDomowa
if ($JestCodex) {
  Write-Host "    ~/.codex/AGENTS.md dostaje wariant: opencode/Codex - $PlikZasadOpencode"
  Wstaw-Blok (Join-Path $DomCodex "AGENTS.md") "zasady w ~/.codex/AGENTS.md" $TrescZasadOpencode
}
# opencode czyta ~/.claude/CLAUDE.md tylko wtedy, gdy nie ma ~/.config/opencode/AGENTS.md.
# Wlasnego pliku mu nie zakladamy: przestalby wtedy widziec "Co wiem" i blok Lore.
if ($JestOpencode -and $Wariant -eq "claude" -and -not (Test-Path (Join-Path $DomOpencode "AGENTS.md"))) {
  Write-Host "UWAGA  opencode na tej maszynie czyta ten sam ~/.claude/CLAUDE.md, wiec dostanie zasady" -ForegroundColor Yellow
  Write-Host "       w wariancie Claude Code. Osobny wariant dla opencode wymaga osobnego pliku" -ForegroundColor Yellow
  Write-Host "       (~/.config/opencode/AGENTS.md) razem z 'Co wiem' i blokiem Lore - do decyzji." -ForegroundColor Yellow
  Nie-Sprawdzono "opencode na tej maszynie dostaje zasady kierownika w wariancie Claude Code (czyta ten sam ~/.claude/CLAUDE.md)"
}
Write-Host ""

# =============================================================== ROLE ========
Write-Host "--- role ---"
if ($JestOpencode) { Wstaw-Agentow (Join-Path $Zrodlo "szablony-opencode\agents") (Join-Path $DomOpencode "agents") "*.md" "~/.config/opencode/agents" }
if ($JestClaude)   { Wstaw-Agentow (Join-Path $Zrodlo "szablony-global\claude\agents") (Join-Path $DomClaude "agents") "*.md" "~/.claude/agents" }
if ($JestCodex)    { Wstaw-Agentow (Join-Path $Zrodlo "szablony-codex\agents") (Join-Path $DomCodex "agents") "*.toml" "~/.codex/agents" }
Write-Host ""

# =============================================================== REJESTR =====
Write-Host "--- rejestr pracy ---"
$SciezkaWtyczki = (Join-Path $DomOpencode "plugins\mr-log.js") -replace '\\','/'
if ($JestOpencode) {
  $src = Join-Path $Zrodlo "szablony-opencode\plugins\mr-log.js"
  if ($Proba) { Write-Host "PROBA  wtyczka -> $SciezkaWtyczki" }
  else {
    New-Item -ItemType Directory -Force -Path (Join-Path $DomOpencode "plugins") | Out-Null
    Copy-Item $src (Join-Path $DomOpencode "plugins\mr-log.js") -Force
    Write-Host "OK  wtyczka opencode -> $SciezkaWtyczki"
  }
}

if ($JestClaude) {
  $srcLog = Join-Path $Zrodlo "szablony-global\claude\mr-log.js"
  $celLog = Join-Path $DomClaude "megaruchacz-mr-log.js"
  if ($Proba) { Write-Host "PROBA  rejestr Claude -> $celLog" }
  else { New-Item -ItemType Directory -Force -Path $DomClaude | Out-Null; Copy-Item $srcLog $celLog -Force; Write-Host "OK  rejestr Claude -> $celLog" }
  # Hooki Claude Code: JEDEN komplet - straznik na SessionStart, przypomnienie przez
  # narzedzia\przypomnienie.js (z "|| cat" na brak node'a), jeden rejestr na
  # SubagentStart/Stop. Robi to straznik, tym samym kodem, ktorym pilnuje ich potem
  # przy kazdym starcie sesji - dlatego ponowne uruchomienie instalatora naprawia
  # istniejaca instalacje (duplikaty, stare "cat") i niczego nie dubluje. Cudze
  # hooki (np. Orki) zostaja nietkniete co do znaku; przed zapisem kopia .bak-<data>.
  $argi = @{ NaprawGlobalne = $true; Zrodlo = $Zrodlo; KatalogDomowy = $KatalogDomowy }
  if ($Proba) { $argi.Proba = $true }
  $global:LASTEXITCODE = 0
  & $Straznik @argi
  if ($LASTEXITCODE -ne 0) {
    Write-Host "BLAD  hooki w ~/.claude/settings.json - straznik ich nie uporzadkowal (powod wyzej)" -ForegroundColor Red
    $script:Bledy += "hooki Claude Code w ~/.claude/settings.json"
  }
  # Worktree: izolacja rownoleglych zadan w Claude Code. To ustawienie jest
  # projektowe, ale globalne tez dziala - kazdy projekt je dostaje.
  Ustaw-Klucz-Json (Join-Path $DomClaude "settings.json") "worktree" ([pscustomobject]@{ baseRef = "fresh"; bgIsolation = "worktree" })
}

if ($JestCodex) {
  # Globalny hook Codeksa nie zna projektu z gory - mr-log-codex.js bierze go
  # z $CODEX_PROJECT_DIR albo z biezacego katalogu (process.cwd()).
  $absLog = (Join-Path $Zrodlo "narzedzia\mr-log-codex.js") -replace '\\','/'
  $gStart = [pscustomobject]@{ hooks = @([pscustomobject]@{ type = "command"; command = "node `"$absLog`" start"; timeout = 5; statusMessage = "MegaRuchacz: wpis do rejestru pracy" }) }
  $gStop  = [pscustomobject]@{ hooks = @([pscustomobject]@{ type = "command"; command = "node `"$absLog`" stop"; timeout = 5; statusMessage = "MegaRuchacz: wpis do rejestru pracy" }) }
  [void](Dopisz-Hook (Join-Path $DomCodex "hooks.json") "hooks" "SubagentStart" $gStart "mr-log-codex.js")
  [void](Dopisz-Hook (Join-Path $DomCodex "hooks.json") "hooks" "SubagentStop"  $gStop  "mr-log-codex.js")
}
Write-Host ""

# =============================================================== ZNACZNIK =====
if (-not $Proba) {
  New-Item -ItemType Directory -Force -Path $DomClaude | Out-Null
  $wersja = "0.0.0"
  $plikuZmian = Join-Path $Zrodlo "ZMIANY.md"
  if (Test-Path $plikuZmian) {
    $naj = $null
    foreach ($m in [regex]::Matches((Get-Content $plikuZmian -Raw), '(?m)^##\s+(\d+)\.(\d+)\.(\d+)')) {
      $w = [version]("{0}.{1}.{2}" -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value)
      if ($null -eq $naj -or $w -gt $naj) { $naj = $w }
    }
    if ($naj) { $wersja = $naj.ToString() }
  }
  Zapisz $Marker ("zrodlo: $Zrodlo`nwersja: $wersja`ndata: " + (Get-Date -Format 'yyyy-MM-dd HH:mm') + "`n")
  Write-Host "OK  znacznik instalacji globalnej: $Marker"
}

# =========================================================== SAMOSPRAWDZENIE ===
Write-Host ""
Write-Host "--- samosprawdzenie ---"
foreach ($r in @("implementer","scout","verifier","zastepca")) {
  if ($JestClaude)   { Sprawdz "~/.claude/agents/$r.md" (Test-Path (Join-Path $DomClaude "agents\$r.md")) "brak pliku" }
  if ($JestOpencode) { Sprawdz "~/.config/opencode/agents/$r.md" (Test-Path (Join-Path $DomOpencode "agents\$r.md")) "brak pliku" }
}
if ($JestClaude) {
  $blokClaude = ""
  if (Test-Path (Join-Path $DomClaude "CLAUDE.md")) { $blokClaude = Czytaj (Join-Path $DomClaude "CLAUDE.md") }
  $ileBlokow = ([regex]::Matches($blokClaude, [regex]::Escape($POCZATEK))).Count
  Sprawdz "blok zasad w ~/.claude/CLAUDE.md (dokladnie jeden)" ($ileBlokow -eq 1) "jest $ileBlokow"
  if (-not $Proba) {
    $pierwsza = ($TrescZasadDomowa -split "`r?`n")[0]
    Sprawdz "blok w ~/.claude/CLAUDE.md w wariancie $Wariant" ($blokClaude.Contains($pierwsza)) "w pliku nie ma naglowka '$pierwsza'"
  }
  Sprawdz "rejestr ~/.claude/megaruchacz-mr-log.js" (Test-Path (Join-Path $DomClaude "megaruchacz-mr-log.js")) "brak pliku"
  if (-not $Proba) {
    $ust = Join-Path $DomClaude "settings.json"
    Sprawdz "ladunek przypomnienia ~/.claude/mr/orchestrator-reminder.json" (Test-Path (Join-Path $DomClaude "mr\orchestrator-reminder.json")) "brak pliku"
    $n = Policz-Hooki $ust "SessionStart" 'straznik-zasad\.ps1'
    Sprawdz "straznik na SessionStart (dokladnie jeden)" ($n -eq 1) "jest $n"
    $n = Policz-Hooki $ust "UserPromptSubmit" 'orchestrator-reminder\.json'
    $np = Policz-Hooki $ust "UserPromptSubmit" 'przypomnienie\.js(?![A-Za-z0-9])'
    Sprawdz "przypomnienie przez przypomnienie.js (dokladnie jedno)" ($n -eq 1 -and $np -eq 1) "wpisow $n, przez skrypt $np"
    foreach ($z in @("SubagentStart", "SubagentStop")) {
      $n = Policz-Hooki $ust $z 'mr-log\.js(?![A-Za-z0-9])'
      Sprawdz "rejestr na $z (dokladnie jeden)" ($n -eq 1) "jest $n"
    }
  }
}
if ($JestCodex) {
  $blokCodex = ""
  if (Test-Path (Join-Path $DomCodex "AGENTS.md")) { $blokCodex = Czytaj (Join-Path $DomCodex "AGENTS.md") }
  Sprawdz "blok zasad w ~/.codex/AGENTS.md" ($blokCodex.Contains($POCZATEK)) "brak znacznika kierownika"
}
if ($JestOpencode) { Sprawdz "wtyczka ~/.config/opencode/plugins/mr-log.js" (Test-Path (Join-Path $DomOpencode "plugins\mr-log.js")) "brak pliku" }
Nie-Sprawdzono "czy narzedzia naprawde wczytaja role i hooki - to widac dopiero po zamknieciu i otwarciu okna"
Nie-Sprawdzono "rejestr pod Codeksem globalnie: hook nie zna projektu z gory, bierze go z CODEX_PROJECT_DIR albo biezacego katalogu - wymaga potwierdzenia na maszynie z Codeksem"

if ($script:Kopie.Count -gt 0) {
  Write-Host ""; Write-Host "Kopie zapasowe:"; $script:Kopie | ForEach-Object { Write-Host "  $_" }
}
if ($script:Niepelne.Count -gt 0) {
  Write-Host ""; Write-Host "Czego to sprawdzenie NIE obejmuje:" -ForegroundColor DarkGray
  $script:Niepelne | ForEach-Object { Write-Host "  -  $_" -ForegroundColor DarkGray }
}
Write-Host ""
if ($script:Bledy.Count -eq 0) {
  Write-Host "Gotowe - tryb kierownika dziala globalnie." -ForegroundColor Green
  Write-Host "Zamknij i otworz swoje narzedzia (Claude Code / opencode / Codeksa) na nowo."
  Write-Host "Jesli masz gdzies stare wdrozenie per projekt (wdroz.ps1), uruchom je tam"
  Write-Host "ponownie - wykryje instalacje globalna i nie doda drugiego wpisu do rejestru."
  exit 0
} else {
  Write-Host ("Instalacja NIEPELNA - do poprawy: " + ($script:Bledy -join "; ")) -ForegroundColor Red
  exit 1
}
