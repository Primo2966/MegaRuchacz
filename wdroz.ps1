# Wdraza tryb MegaRuchacza do istniejacego projektu - PRYWATNIE.
# Uzycie:  /MegaRuchacz   (w Claude Code, w dowolnym projekcie)
#     lub:  powershell -File C:\dev\claude-worker\wdroz.ps1   (bez argumentu = biezacy katalog)
#
# Wszystko ladunku w .claude/, ktory w wiekszosci repo jest w .gitignore.
# NIE dotyka zadnego sledzonego pliku - CLAUDE.md zostaje nietkniety.
# Zasady trafiaja do modelu przez hook SessionStart, nie przez CLAUDE.md.
#
# Parametry:
#   -BezPytania     pomija ekran zgody i zaklada zgode na wszystko (tryb nieinteraktywny)
#   -KatalogDomowy  podstawiony katalog domowy - do testow, zeby nie ruszac wlasnej konfiguracji
#   -WymusCodex     wdraza czesc dla Codeksa nawet wtedy, gdy nie widac go na maszynie

param(
  [string]$Projekt = (Get-Location).Path,
  [switch]$BezPytania,
  [string]$KatalogDomowy = $HOME,
  [switch]$WymusCodex
)

$Zrodlo  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Stempel = Get-Date -Format "yyyyMMdd-HHmmss"
$script:Kopie = @()
$script:Bledy = @()
$script:Niepelne = @()   # co samosprawdzenie potwierdza tylko czesciowo

function Kopia-Zapasowa($sciezka) {
  if (Test-Path $sciezka) {
    $bak = "$sciezka.bak-$Stempel"
    Copy-Item $sciezka $bak -Force
    $script:Kopie += $bak
  }
}

# Jeden punkt samosprawdzenia: wypisuje OK albo BLAD i zbiera bledy na podsumowanie.
function Sprawdz($opis, $ok, $czemu) {
  if ($ok) {
    Write-Host "  OK    $opis"
  } else {
    Write-Host "  BLAD  $opis - $czemu" -ForegroundColor Red
    $script:Bledy += $opis
  }
}

# Sprawdzenie, ktore potwierdza tylko zapis na dysku albo obecnosc wpisu, nie
# jest dowodem dzialania. Takie rzeczy ida tutaj i wracaja w podsumowaniu wprost,
# zeby nikt nie wzial "zapisane" za "dziala".
function Nie-Sprawdzono($tekst) {
  $script:Niepelne += $tekst
}

# Wyjmuje z settings.json konkretny hook - ten, ktorego polecenie zawiera znacznik.
function Polecenie-Hooka($ustawienia, $zdarzenie, $znacznik) {
  foreach ($grupa in @($ustawienia.hooks.$zdarzenie)) {
    foreach ($h in @($grupa.hooks)) {
      if ($h.command -and $h.command -like "*$znacznik*") { return $h }
    }
  }
  return $null
}

# Sciezka do bash.exe. Claude Code odnajduje basha SAM, niezaleznie od PATH,
# wiec szukanie wylacznie w PATH dawalo falszywy alarm tam, gdzie Git siedzi poza
# PATH-em, a hooki dzialaly bez zarzutu. Kolejnosc jak w Znajdz-Uv
# (narzedzia\instaluj-lore.ps1): najpierw PATH, potem znane miejsca instalacji Gita.
function Znajdz-Bash {
  $cmd = Get-Command bash -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return $cmd.Source }
  $kandydaci = @(
    "C:\dev\tools\git\bin\bash.exe",
    "$env:ProgramFiles\Git\bin\bash.exe",
    (Join-Path $env:LOCALAPPDATA "Programs\Git\bin\bash.exe"),
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
  )
  foreach ($k in $kandydaci) {
    if ($k -and (Test-Path $k)) { return (Resolve-Path $k).Path }
  }
  return $null
}

# Odpala polecenie hooka doslownie tak, jak zrobilby to Claude Code: przez bash,
# z CLAUDE_PROJECT_DIR wskazujacym projekt. Polecenie idzie do pliku, bo
# cudzyslowy w argumencie "bash -c" gina po drodze w PowerShell 5.1.
function Odpal-Przez-Bash($polecenie) {
  $tmp = Join-Path $env:TEMP ("mr-hook-proba-$Stempel-" + [guid]::NewGuid().ToString("N").Substring(0, 6) + ".sh")
  # LF, bez BOM - bash na Windowsie nie trawi ani CR, ani znacznika kodowania
  [System.IO.File]::WriteAllText($tmp, (($polecenie -replace "`r`n", "`n") + "`n"),
                                 (New-Object System.Text.UTF8Encoding($false)))
  $poprzedni = $env:CLAUDE_PROJECT_DIR
  $env:CLAUDE_PROJECT_DIR = $Projekt
  try {
    $global:LASTEXITCODE = 0
    $wyjscie = & $script:Bash ($tmp -replace "\\", "/") 2>&1 | Out-String
    return @{ kod = $LASTEXITCODE; tekst = $wyjscie }
  } catch {
    return @{ kod = -1; tekst = $_.Exception.Message }
  } finally {
    if ($null -eq $poprzedni) { Remove-Item Env:CLAUDE_PROJECT_DIR -ErrorAction SilentlyContinue }
    else { $env:CLAUDE_PROJECT_DIR = $poprzedni }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  }
}

# Odpala skrypt pomocniczy z repo. Brak pliku tez jest porazka - ale nigdy cicha,
# wynik zawsze laduje w samosprawdzeniu.
function Uruchom-Podskrypt($sciezka, $argumenty, $nazwa) {
  if (-not (Test-Path $sciezka)) {
    return @{ ok = $false; czemu = "nie ma pliku $sciezka" }
  }
  try {
    $global:LASTEXITCODE = 0
    & $sciezka @argumenty
    $kodPod = $LASTEXITCODE
    if ($kodPod -ne 0) { return @{ ok = $false; czemu = "$nazwa zakonczyl sie kodem $kodPod" } }
    return @{ ok = $true; czemu = "" }
  } catch {
    return @{ ok = $false; czemu = "$nazwa wywrocil sie: $($_.Exception.Message)" }
  }
}

# Czy plik jest sledzony przez gita w tym projekcie. Wdrozenie nie ma prawa
# ruszyc niczego, co uzytkownik trzyma w repozytorium - stad to pytanie przed
# dopisaniem czegokolwiek do AGENTS.md.
function Sledzony-W-Gicie($projekt, $plik) {
  try {
    $global:LASTEXITCODE = 0
    & git -C $projekt ls-files --error-unmatch $plik 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
  } catch { return $false }
}

# Numer wersji narzedzia - najwyzszy naglowek "## X.Y.Z" w ZMIANY.md.
# Wpisy w tym pliku nie zawsze ida po kolei, wiec liczy sie najwyzszy, nie pierwszy.
function Wersja-Narzedzia($plikZmian) {
  if (-not (Test-Path $plikZmian)) { return $null }
  $naj = $null
  foreach ($m in [regex]::Matches((Get-Content $plikZmian -Raw), '(?m)^##\s+(\d+)\.(\d+)\.(\d+)')) {
    $w = [version]("{0}.{1}.{2}" -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value)
    if ($null -eq $naj -or $w -gt $naj) { $naj = $w }
  }
  if ($null -eq $naj) { return $null }
  return $naj.ToString()
}

function Tak-Czy-Nie($pytanie) {
  $odp = Read-Host "$pytanie [t/N]"
  return ($odp -match '^(t|tak|y|yes)$')
}

if (-not (Test-Path $Projekt)) { Write-Error "Nie ma takiego katalogu: $Projekt"; exit 1 }
$Projekt = (Resolve-Path $Projekt).Path
if ($Projekt -eq (Resolve-Path $Zrodlo).Path) {
  Write-Error "To jest katalog szablonu - uruchom to w projekcie docelowym, nie tutaj."
  exit 1
}

# Co jest na TEJ maszynie. Tryb workerow stoi w calosci na mechanizmach Claude
# Code (hooki, subagenci, izolowane kopie repozytorium) - bez niego nie zadziala
# i nie wolno udawac, ze jest inaczej. Zasady globalne i odswiezanie narzedzia
# dzialaja niezaleznie od niego, wiec te wdrazamy tak czy owak.
$Claude = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$Node   = Get-Command node   -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$Bash   = Znajdz-Bash   # nie tylko PATH - Claude Code znajduje basha takze poza nim

# Codex ma wlasne hooki i wlasnych podagentow, wiec tryb workerow idzie takze
# tam - obok Claude Code, nie zamiast. Widzimy go po poleceniu w PATH albo po
# katalogu domowym ($CODEX_HOME, w razie braku ~\.codex).
$Codex = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$DomCodex = $env:CODEX_HOME
if (-not $DomCodex) { $DomCodex = Join-Path $KatalogDomowy ".codex" }
$JestCodex = ($null -ne $Codex) -or (Test-Path $DomCodex) -or $WymusCodex

# --------------------------------------------------------------- 0. ekran zgody
# Zanim cokolwiek ruszymy - co dokladnie sie stanie i gdzie. Nikt nie ma byc
# zaskoczony ani jednym plikiem, ani zadaniem w harmonogramie.
$plikDomowy = Join-Path $KatalogDomowy ".claude\CLAUDE.md"
$Straznik   = Join-Path $Zrodlo "narzedzia\straznik-zasad.ps1"

# Rejestr modulow mieszka w straznik-zasad.ps1 - jedno miejsce dla instalatora
# i dla straznika. Dolozenie modulu to dopisanie pozycji tam, nie tutaj.
$Moduly = @()
if (Test-Path $Straznik) {
  try {
    # UWAGA: w PowerShell 5.1 nawias @() wokol ConvertFrom-Json ZWIJA tablice
    # z powrotem w jeden element - petla po modulach dostawala wtedy obie
    # pozycje naraz jako jedna. Dlatego przypisanie wprost, bez @().
    $tekstJson = (& $Straznik -Moduly) -join [Environment]::NewLine
    $wczytane  = ConvertFrom-Json $tekstJson
    if ($wczytane -is [array]) { $Moduly = $wczytane } else { $Moduly = ,$wczytane }
  } catch { $Moduly = @() }
}
if ($Moduly.Count -eq 0) {
  Write-Host "UWAGA  nie moge odczytac rejestru modulow ze straznika - instaluje sam modul podstawowy" -ForegroundColor Yellow
  $Moduly = @([pscustomobject]@{ nazwa = "workerzy"; opis = "tryb kierownika rozdajacego zadania";
                                 koszt = "nic nie pobiera"; pytaj = $false; instalator = ""; aktualizacja = "pliki" })
}

Write-Host ""
Write-Host "=== MegaRuchacz - instalacja ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Projekt docelowy: $Projekt"
Write-Host ""
Write-Host "1) W projekcie, w katalogu .claude\ (w wiekszosci repo jest on w .gitignore):"
Write-Host "   agents\*.md                 definicje czterech rol workerow"
Write-Host "   worklog.md, mapa.md         pliki stanu: rejestr zadan i mapa projektu"
Write-Host "   megaruchacz-zasady.md       zasady pracy kierownika"
Write-Host "   megaruchacz-sesja.json      gotowy ladunek dla hooka startowego"
Write-Host "   orchestrator-reminder.json  krotkie przypomnienie przy kazdym poleceniu"
Write-Host "   mr-log.js                   dopisuje do rejestru start i koniec workera"
Write-Host "   megaruchacz-wersja.txt      wersja wdrozenia, zeby dalo sie je aktualizowac"
Write-Host "   settings.json               DOPISANE HOOKI - uruchamiane przy kazdej sesji"
Write-Host "                               i przy kazdym wyslanym poleceniu, plus worktree"
Write-Host "   Zaden sledzony plik repozytorium nie zostanie ruszony. Gdy cos nadpisujemy,"
Write-Host "   kopia zapasowa laduje obok, z data w nazwie."
Write-Host ""
if ($JestCodex) {
  Write-Host "1b) Widze Codeksa - tryb workerow wchodzi takze dla niego:"
  Write-Host "   .codex\agents\*.toml        definicje czterech rol podagentow"
  Write-Host "   .codex\hooks.json           DOPISANE HOOKI Codeksa: zasady na starcie sesji,"
  Write-Host "                               przypomnienie przy kazdym poleceniu, rejestr workerow"
  Write-Host "   AGENTS.md w korzeniu projektu   zasady kierownika miedzy znacznikami MegaRuchacz."
  Write-Host "                               Gdy tego pliku nie ma - powstanie nowy (niesledzony"
  Write-Host "                               przez gita). Gdy Twoj AGENTS.md jest sledzony w repo -"
  Write-Host "                               NIE ruszam go i powiem o tym wprost."
  Write-Host "   .megaruchacz\               rejestr pracy, mapa, zasady i ladunki hookow."
  Write-Host "                               Tam, a nie w .codex\, bo Codex trzyma .codex\"
  Write-Host "                               rekurencyjnie tylko do odczytu - hook nic by tam nie dopisal."
  Write-Host "   .megaruchacz\wersja.txt     wersja wdrozenia dla Codeksa, zeby dalo sie je aktualizowac"
  Write-Host "   Zaden sledzony plik repozytorium nie zostanie ruszony, ale .codex\, .megaruchacz\"
  Write-Host "   i AGENTS.md zwykle NIE SA w .gitignore - zobaczysz je w 'git status' jako nowe,"
  Write-Host "   niesledzone pliki. Gdy cos nadpisujemy, kopia zapasowa laduje obok, z data w nazwie."
  Write-Host "   UWAGA: hooki Codeksa NIE URUCHOMIA SIE, dopoki nie zatwierdzisz ich w CLI" -ForegroundColor Yellow
  Write-Host "   poleceniem /hooks. Zatwierdza sie je RAZ: Codex liczy skrot z samej DEFINICJI" -ForegroundColor Yellow
  Write-Host "   hooka (zdarzenie, matcher, polecenie, timeout, async), a nie z tresci skryptu," -ForegroundColor Yellow
  Write-Host "   ktory to polecenie uruchamia - nasze pozniejsze poprawki w skryptach zaufania" -ForegroundColor Yellow
  Write-Host "   nie uniewazniaja, aktualizacja samego Codeksa tez nie." -ForegroundColor Yellow
  Write-Host "   Bez tego kroku rejestr milczy i zasady nie wchodza z hooka - nie dlatego," -ForegroundColor Yellow
  Write-Host "   ze wdrozenie zawiodlo." -ForegroundColor Yellow
  Write-Host ""
} else {
  Write-Host "1b) Codeksa nie widze na tej maszynie - czesc dla niego (role, hooki, .megaruchacz\)"
  Write-Host "   zostanie pominieta. Wymusic mozna przelacznikiem -WymusCodex."
  Write-Host ""
}
Write-Host "2) Poza projektem - zasady globalne:"
Write-Host "   do $plikDomowy i do ~\.codex\AGENTS.md zostanie dopisany blok"
Write-Host "   miedzy znacznikami <!-- MegaRuchacz:start --> i <!-- MegaRuchacz:koniec -->."
Write-Host "   Twoje wlasne zapiski zostaja nietkniete, przed zmiana powstaje kopia zapasowa,"
Write-Host "   a caly blok da sie usunac: narzedzia\wpisz-zasady.ps1 -Usun"
Write-Host ""
Write-Host "3) Zadanie w Harmonogramie zadan Windows (MegaRuchaczOdswiez):"
Write-Host "   co godzine pobiera nowsza wersje narzedzia z gita i pilnuje plikow zasad."
Write-Host "   Na maszynie bez Claude Code to jedyna droga aktualizacji - hooka, ktory"
Write-Host "   robi to przy starcie sesji, ma wylacznie Claude Code."
Write-Host ""
Write-Host "4) Moduly - kazdy instaluje sie i aktualizuje osobno:" -ForegroundColor Yellow
foreach ($m in $Moduly) {
  $kiedy = if ($m.pytaj) { "zapytam osobno" } else { "wchodzi domyslnie" }
  Write-Host "   [$($m.nazwa)] - $kiedy"
  Write-Host "      daje:     $($m.opis)"
  Write-Host "      kosztuje: $($m.koszt)"
}
Write-Host ""

# Uczciwie i przed zgoda: czego na tej maszynie nie da sie wdrozyc.
if (-not $Claude -and -not $JestCodex) {
  Write-Host "UWAGA - nie widze na tej maszynie ani Claude Code, ani Codeksa:" -ForegroundColor Yellow
  Write-Host "   Tryb workerow (rozdawanie zadan, hooki, izolowane kopie repozytorium) stoi na" -ForegroundColor Yellow
  Write-Host "   mechanizmach tych dwoch narzedzi. Tutaj NIE zadziala i instalator nie bedzie" -ForegroundColor Yellow
  Write-Host "   udawal, ze jest inaczej." -ForegroundColor Yellow
  Write-Host "   Dziala za to: zasady globalne (Codex czyta ~\.codex\AGENTS.md sam, bez hooka)," -ForegroundColor Yellow
  Write-Host "   odswiezanie narzedzia z Harmonogramu i modul pamieci [pamiec]." -ForegroundColor Yellow
  Write-Host "   Pliki trybu workerow zapisze mimo to - zaczna dzialac, gdy narzedzie sie pojawi." -ForegroundColor Yellow
  Write-Host ""
} elseif (-not $Claude) {
  Write-Host "UWAGA - nie widze Claude Code, widze Codeksa:" -ForegroundColor Yellow
  Write-Host "   Tryb workerow wdroze w wersji dla Codeksa. Ma dwa ograniczenia, o ktorych" -ForegroundColor Yellow
  Write-Host "   trzeba wiedziec: nie ma pracy w tle (watek glowny czeka na wszystkich" -ForegroundColor Yellow
  Write-Host "   podagentow) i nie ma izolacji przez kopie repozytorium - rozlacznosc plikow" -ForegroundColor Yellow
  Write-Host "   pilnuje wylacznie tresc zlecenia i rejestr." -ForegroundColor Yellow
  Write-Host "   Pliki dla Claude Code zapisze mimo to - zaczna dzialac, gdy sie pojawi." -ForegroundColor Yellow
  Write-Host ""
}
if (-not $Node) {
  Write-Host "UWAGA  nie ma node w PATH - pliki hookow Claude Code (sesja i rejestr workerow)" -ForegroundColor Yellow
  Write-Host "       nie powstana; reszta wdrozenia idzie normalnie." -ForegroundColor Yellow
  Write-Host ""
}

$wybrane = @{}
if ($BezPytania) {
  Write-Host "Tryb -BezPytania: zgoda na calosc, razem z modulami opcjonalnymi."
  foreach ($m in $Moduly) { $wybrane[$m.nazwa] = $true }
} else {
  if (-not (Tak-Czy-Nie "Kontynuowac instalacje?")) {
    Write-Host "Przerwane - nic nie zostalo zmienione."
    exit 0
  }
  foreach ($m in $Moduly) {
    if (-not $m.pytaj) { $wybrane[$m.nazwa] = $true; continue }
    $wybrane[$m.nazwa] = Tak-Czy-Nie "Zainstalowac modul [$($m.nazwa)]?"
    if (-not $wybrane[$m.nazwa]) { Write-Host "Dobrze - pomijam [$($m.nazwa)]." }
  }
}
Write-Host ""

New-Item -ItemType Directory -Force -Path (Join-Path $Projekt ".claude\agents") | Out-Null

if (-not (Test-Path (Join-Path $Projekt ".git"))) {
  Write-Host "UWAGA  to nie jest repozytorium git - worktree (izolacja rownoleglych zadan) nie zadziala" -ForegroundColor Yellow
}

# 1. Workerzy
Get-ChildItem (Join-Path $Zrodlo ".claude\agents\*.md") | ForEach-Object {
  $cel = Join-Path $Projekt ".claude\agents\$($_.Name)"
  if (Test-Path $cel) {
    if (-not ((Get-Content $cel -Raw) -match "kierownik-template")) {
      Kopia-Zapasowa $cel
      Write-Host "UWAGA  masz wlasny agents\$($_.Name) - odlozylem kopie obok" -ForegroundColor Yellow
    }
  }
  Copy-Item $_.FullName $cel -Force
}
Write-Host "OK  workerzy -> .claude\agents\"

# 2. Pliki stanu - tylko gdy ich nie ma
foreach ($f in @("worklog.md","mapa.md")) {
  $celStanu = Join-Path $Projekt ".claude\$f"
  if (-not (Test-Path $celStanu)) {
    Copy-Item (Join-Path $Zrodlo ".claude\$f") $celStanu
    Write-Host "OK  .claude\$f (nowy)"
  } else {
    Write-Host "--  .claude\$f juz istnieje, zostawiam"
  }
}

# 3. Zasady + payloady dla hookow - wszystko w .claude, nic do repo
Copy-Item (Join-Path $Zrodlo "CLAUDE.md") (Join-Path $Projekt ".claude\megaruchacz-zasady.md") -Force
Copy-Item (Join-Path $Zrodlo ".claude\orchestrator-reminder.json") (Join-Path $Projekt ".claude") -Force
Copy-Item (Join-Path $Zrodlo ".claude\mr-log.js") (Join-Path $Projekt ".claude") -Force
Write-Host "OK  .claude\megaruchacz-zasady.md + przypomnienie dla hooka"

$budujSesje = @'
const fs = require("fs"), dir = process.argv[2];
const zasady = fs.readFileSync(dir + "/.claude/megaruchacz-zasady.md", "utf8");
fs.writeFileSync(dir + "/.claude/megaruchacz-sesja.json", JSON.stringify({
  suppressOutput: true,
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: "Zasady pracy w tym projekcie (tryb MegaRuchacz). Stosuj je przez cala sesje:\n\n" + zasady
  }
}));
console.log("OK  .claude/megaruchacz-sesja.json (zasady wstrzykiwane na starcie sesji)");
'@
# Ladunek dla hooka sesji sklada node. Bez node'a go nie bedzie - i nie ma to
# znaczenia tam, gdzie nie ma Claude Code, bo hooki naleza wylacznie do niego.
if ($Node) {
  $tmp1 = Join-Path $env:TEMP "mr-sesja-$Stempel.js"
  $budujSesje | Out-File -FilePath $tmp1 -Encoding utf8
  node $tmp1 $Projekt
  Remove-Item $tmp1 -Force
} else {
  Write-Host "--  .claude\megaruchacz-sesja.json pominiete - nie ma node w PATH"
}

# 4. settings.json - hooki + worktree
$js = @'
const fs = require("fs"), p = process.argv[2], repo = process.argv[3];
let s = {}, zmiana = false;
if (fs.existsSync(p)) {
  try {
    let raw = fs.readFileSync(p, "utf8");
    if (raw.charCodeAt(0) === 65279) raw = raw.slice(1);
    s = JSON.parse(raw);
  } catch (e) {
    console.log("POMINIETE  settings.json nie jest czystym JSON-em - nie ruszam go");
    process.exit(3);
  }
}
if (!s.worktree) {
  s.worktree = { baseRef: "fresh", bgIsolation: "worktree" };
  zmiana = true;
  console.log("OK  worktree (izolacja rownoleglych zadan)");
} else {
  console.log("--  worktree juz skonfigurowane, zostawiam");
}
s.hooks = s.hooks || {};
function dodajHook(event, plik, opis) {
  s.hooks[event] = s.hooks[event] || [];
  if (JSON.stringify(s.hooks[event]).includes(plik)) { console.log("--  hook " + event + " juz jest"); return; }
  s.hooks[event].push({ hooks: [{ type: "command", shell: "bash", timeout: 5,
    command: 'cat "$CLAUDE_PROJECT_DIR/.claude/' + plik + '" 2>/dev/null || cat .claude/' + plik }] });
  zmiana = true;
  console.log("OK  hook " + event + " - " + opis);
}
function dodajLogger(event, arg, opis) {
  s.hooks[event] = s.hooks[event] || [];
  if (JSON.stringify(s.hooks[event]).includes("mr-log.js")) { console.log("--  hook " + event + " juz jest"); return; }
  s.hooks[event].push({ hooks: [{ type: "command", shell: "bash", timeout: 5,
    command: 'node "$CLAUDE_PROJECT_DIR/.claude/mr-log.js"' + arg }] });
  zmiana = true;
  console.log("OK  hook " + event + " - " + opis);
}
// Straznik siedzi w repo szablonu, wiec sciezka musi byc bezwzgledna.
// Ukosniki w przod - mniej escapowania w JSON-ie i w bashu. "|| true", zeby
// brak powershella nigdzie indziej nie wywrocil startu sesji.
function dodajStraznika(opis) {
  const event = "SessionStart", plik = "straznik-zasad.ps1";
  s.hooks[event] = s.hooks[event] || [];
  if (JSON.stringify(s.hooks[event]).includes(plik)) { console.log("--  hook straznika juz jest"); return; }
  const r = repo.replace(/\\/g, "/");
  s.hooks[event].push({ hooks: [{ type: "command", shell: "bash", timeout: 15,
    command: 'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + r + '/narzedzia/' + plik +
             '" -Zrodlo "' + r + '" -Projekt "$CLAUDE_PROJECT_DIR" || true' }] });
  zmiana = true;
  console.log("OK  hook " + event + " - " + opis);
}
dodajLogger("SubagentStart", "", "wpis do rejestru przy starcie workera");
dodajLogger("SubagentStop", " stop", "wpis przy zakonczeniu workera");
dodajHook("SessionStart", "megaruchacz-sesja.json", "pelne zasady raz na sesje");
dodajStraznika("straznik zasad i wersji (cichy, gdy wszystko gra)");
dodajHook("UserPromptSubmit", "orchestrator-reminder.json", "przypomnienie przy kazdym enterze");
if (zmiana) { fs.writeFileSync(p, JSON.stringify(s, null, 2)); process.exit(0); }
process.exit(4);
'@
$celSettings = Join-Path $Projekt ".claude\settings.json"
$kod = 5   # 5 = w ogole nie probowalismy, bo nie ma czym
if ($Node) {
  $tmp2 = Join-Path $env:TEMP "mr-hook-$Stempel.js"
  $js | Out-File -FilePath $tmp2 -Encoding utf8
  Kopia-Zapasowa $celSettings
  node $tmp2 $celSettings $Zrodlo
  $kod = $LASTEXITCODE
  Remove-Item $tmp2 -Force
} else {
  Write-Host "--  .claude\settings.json pominiete - nie ma node w PATH"
}

if ($kod -ne 0) {
  $zbedne = @($script:Kopie | Where-Object { $_ -like "*settings.json.bak-*" })
  foreach ($z in $zbedne) { Remove-Item $z -Force }
  $script:Kopie = @($script:Kopie | Where-Object { $_ -notlike "*settings.json.bak-*" })
}
# 3 = cudzy settings.json nie jest JSON-em, 4 = wszystko juz bylo na miejscu
$hookiOk = ($kod -eq 0 -or $kod -eq 4)

# --------------------------------------------------------------- 4b. Codex CLI
# To samo wdrozenie, tylko w katalogach Codeksa: role w .codex\agents\, hooki
# w .codex\hooks.json, zasady w AGENTS.md (Codex czyta go sam, bez hooka), a
# rejestr, mapa i ladunki hookow w .megaruchacz\ - bo piaskownica Codeksa trzyma
# .codex\ rekurencyjnie tylko do odczytu i hook nic by tam nie dopisal.
$codexZasadyWAgents = $false
$codexHooki = 5      # jak $kod wyzej: 0 dopisane, 3 cudzy JSON, 4 juz byly, 5 nie probowalismy
$celCodex    = Join-Path $Projekt ".codex"
$celMega     = Join-Path $Projekt ".megaruchacz"
$celHookow   = Join-Path $celCodex "hooks.json"
$celAgentsMd = Join-Path $Projekt "AGENTS.md"

$budujSesjeCodex = @'
const fs = require("fs"), dir = process.argv[2], krotkie = process.argv[3] === "krotkie";
const zasady = fs.readFileSync(dir + "/.megaruchacz/zasady-kierownika.md", "utf8");
// Gdy pelne zasady sa juz w AGENTS.md, hook ma tylko przypomniec, ze obowiazuja -
// drugi raz tego samego nie wysylamy, bo additionalContext ma wlasny limit.
const tresc = krotkie
  ? "Tryb MegaRuchacz jest wlaczony w tym projekcie: jestes kierownikiem, ktory rozdaje robote podagentom. Pelne zasady masz w AGENTS.md w korzeniu projektu (kopia: .megaruchacz/zasady-kierownika.md) - stosuj je przez cala sesje. Stan pracy: .megaruchacz/worklog.md (rejestr) i .megaruchacz/mapa.md (co gdzie lezy)."
  : "Zasady pracy w tym projekcie (tryb MegaRuchacz). Stosuj je przez cala sesje:\n\n" + zasady;
fs.writeFileSync(dir + "/.megaruchacz/zasady-sesja.json", JSON.stringify({
  hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: tresc }
}));
console.log("OK  .megaruchacz\\zasady-sesja.json (zasady na starcie sesji Codeksa)");
'@

# Grupy hookow bierzemy z szablonu DOSLOWNIE - razem z jawnym "timeout" przy
# kazdym hooku. Ten timeout ma tam byc i ma zostac: Codex liczy skrot zaufania
# z definicji hooka juz po normalizacji, a wartosc domyslna moglaby sie zmienic
# w nowszym Codeksie i uniewaznic zatwierdzenie, ktore uzytkownik juz kliknal.
$jsCodex = @'
const fs = require("fs");
const cel = process.argv[2], szablonP = process.argv[3], projekt = process.argv[4], zrodlo = process.argv[5];
let surowy = fs.readFileSync(szablonP, "utf8");
if (surowy.charCodeAt(0) === 65279) surowy = surowy.slice(1);
surowy = surowy.split("{{PROJEKT}}").join(projekt.replace(/\\/g, "/"))
               .split("{{ZRODLO}}").join(zrodlo.replace(/\\/g, "/"));
const szablon = JSON.parse(surowy);
let s = {}, zmiana = false;
if (fs.existsSync(cel)) {
  try {
    let raw = fs.readFileSync(cel, "utf8");
    if (raw.charCodeAt(0) === 65279) raw = raw.slice(1);
    s = JSON.parse(raw);
  } catch (e) {
    console.log("POMINIETE  .codex/hooks.json nie jest czystym JSON-em - nie ruszam go");
    process.exit(3);
  }
}
s.hooks = s.hooks || {};
for (const zdarzenie of Object.keys(szablon.hooks)) {
  s.hooks[zdarzenie] = s.hooks[zdarzenie] || [];
  for (const grupa of szablon.hooks[zdarzenie]) {
    // Znacznik bez cudzyslowow: po JSON.stringify cudzyslowy sa zescapowane,
    // wiec porownywanie calego polecenia nigdy by nie trafilo.
    const znacznik = grupa.hooks[0].statusMessage || "MegaRuchacz";
    if (JSON.stringify(s.hooks[zdarzenie]).includes(znacznik)) {
      console.log("--  hook " + zdarzenie + " (Codex) juz jest");
      continue;
    }
    s.hooks[zdarzenie].push(grupa);
    zmiana = true;
    console.log("OK  hook " + zdarzenie + " (Codex)");
  }
}
if (zmiana) { fs.writeFileSync(cel, JSON.stringify(s, null, 2)); process.exit(0); }
process.exit(4);
'@

if ($JestCodex) {
  Write-Host ""
  Write-Host "--- Codex ---"
  $utf8Zapis  = New-Object System.Text.UTF8Encoding($false)
  $utf8Odczyt = New-Object System.Text.UTF8Encoding($false, $true)
  New-Item -ItemType Directory -Force -Path (Join-Path $celCodex "agents") | Out-Null
  New-Item -ItemType Directory -Force -Path $celMega | Out-Null

  # Role podagentow - tak samo jak w Claude Code: cudzy plik o tej samej nazwie
  # dostaje kopie zapasowa, swoje rozpoznajemy po znaczniku kierownik-template.
  Get-ChildItem (Join-Path $Zrodlo "szablony-codex\agents\*.toml") | ForEach-Object {
    $celRoli = Join-Path $celCodex "agents\$($_.Name)"
    if (Test-Path $celRoli) {
      if (-not ((Get-Content $celRoli -Raw) -match "kierownik-template")) {
        Kopia-Zapasowa $celRoli
        Write-Host "UWAGA  masz wlasny .codex\agents\$($_.Name) - odlozylem kopie obok" -ForegroundColor Yellow
      }
    }
    Copy-Item $_.FullName $celRoli -Force
  }
  Write-Host "OK  role podagentow -> .codex\agents\"

  # Pliki stanu - tylko gdy ich nie ma. Rejestr prowadzi hook, mape wypelnia
  # pierwszy scout; nadpisanie skasowaloby dorobek projektu.
  $celRejestru = Join-Path $celMega "worklog.md"
  if (-not (Test-Path $celRejestru)) {
    [System.IO.File]::WriteAllText($celRejestru, "# Rejestr pracy`r`n`r`n", $utf8Zapis)
    Write-Host "OK  .megaruchacz\worklog.md (nowy)"
  } else {
    Write-Host "--  .megaruchacz\worklog.md juz istnieje, zostawiam"
  }
  $celMapy = Join-Path $celMega "mapa.md"
  if (-not (Test-Path $celMapy)) {
    [System.IO.File]::WriteAllText($celMapy,
      "# Mapa projektu`r`n`r`n_(pusto - pierwszy scout ma tu dopisac, co gdzie lezy)_`r`n", $utf8Zapis)
    Write-Host "OK  .megaruchacz\mapa.md (nowa)"
  } else {
    Write-Host "--  .megaruchacz\mapa.md juz istnieje, zostawiam"
  }

  Copy-Item (Join-Path $Zrodlo "szablony-codex\zasady-kierownika.md") (Join-Path $celMega "zasady-kierownika.md") -Force
  Copy-Item (Join-Path $Zrodlo "szablony-codex\przypomnienie.json") (Join-Path $celMega "przypomnienie.json") -Force
  Write-Host "OK  .megaruchacz\zasady-kierownika.md + przypomnienie dla hooka"

  # AGENTS.md - jedyna droga zasad, ktora nie wymaga zatwierdzania hookow.
  # Tresc idzie miedzy znaczniki, wlasne zapiski uzytkownika zostaja nietkniete,
  # a pliku sledzonego w repozytorium nie ruszamy w ogole.
  $POCZATEK = "<!-- MegaRuchacz:start -->"
  $KONIEC   = "<!-- MegaRuchacz:koniec -->"
  $trescZasad = [System.IO.File]::ReadAllText((Join-Path $celMega "zasady-kierownika.md"), $utf8Odczyt)
  $blokZasad = $POCZATEK + "`r`n" + $trescZasad.Trim() + "`r`n" + $KONIEC + "`r`n"
  $stareAgents = $null
  if (-not (Test-Path $celAgentsMd)) {
    [System.IO.File]::WriteAllText($celAgentsMd, $blokZasad, $utf8Zapis)
    $codexZasadyWAgents = $true
    Write-Host "OK  AGENTS.md (nowy plik - zasady kierownika, Codex czyta go sam)"
  } else {
    # Cudzy plik czytamy ostroznie: gdy nie jest UTF-8, nie zgadujemy kodowania
    # i nie ruszamy go w ogole - lepiej zostawic zasady w .megaruchacz\.
    $stareAgents = $null
    try { $stareAgents = [System.IO.File]::ReadAllText($celAgentsMd, $utf8Odczyt) }
    catch { Write-Host "UWAGA  AGENTS.md nie daje sie odczytac jako UTF-8 - nie ruszam go" -ForegroundColor Yellow }
  }
  if ($null -ne $stareAgents) {
    $odKad = $stareAgents.IndexOf($POCZATEK, [System.StringComparison]::Ordinal)
    $doKad = $stareAgents.IndexOf($KONIEC, [System.StringComparison]::Ordinal)
    if ($odKad -ge 0 -and $doKad -gt $odKad) {
      Kopia-Zapasowa $celAgentsMd
      $noweAgents = $stareAgents.Substring(0, $odKad) + $blokZasad.TrimEnd() +
                    $stareAgents.Substring($doKad + $KONIEC.Length)
      [System.IO.File]::WriteAllText($celAgentsMd, $noweAgents, $utf8Zapis)
      $codexZasadyWAgents = $true
      Write-Host "OK  AGENTS.md - blok MegaRuchacza odswiezony, reszta pliku nietknieta"
    } elseif (Sledzony-W-Gicie $Projekt "AGENTS.md") {
      Write-Host "UWAGA  AGENTS.md jest sledzony w gicie - NIE ruszam go." -ForegroundColor Yellow
      Write-Host "       Zasady kierownika leza w .megaruchacz\zasady-kierownika.md. Zeby Codex" -ForegroundColor Yellow
      Write-Host "       czytal je sam, wklej ich tresc do AGENTS.md miedzy znaczniki" -ForegroundColor Yellow
      Write-Host "       $POCZATEK i $KONIEC" -ForegroundColor Yellow
      Write-Host "       Do tego czasu ida do modelu wylacznie hookiem SessionStart - czyli dopiero" -ForegroundColor Yellow
      Write-Host "       po zatwierdzeniu hookow poleceniem /hooks." -ForegroundColor Yellow
    } else {
      Kopia-Zapasowa $celAgentsMd
      [System.IO.File]::WriteAllText($celAgentsMd, $stareAgents.TrimEnd() + "`r`n`r`n" + $blokZasad, $utf8Zapis)
      $codexZasadyWAgents = $true
      Write-Host "OK  AGENTS.md - blok MegaRuchacza dopisany na koncu (plik nie jest sledzony w gicie)"
    }
  }

  # Ladunki hookow i wpisy w .codex\hooks.json sklada node - tak samo jak po
  # stronie Claude Code. Bez node'a nie ma ich i nie udajemy, ze sa.
  if ($Node) {
    $tmp3 = Join-Path $env:TEMP "mr-codex-sesja-$Stempel.js"
    $budujSesjeCodex | Out-File -FilePath $tmp3 -Encoding utf8
    $wariant = "pelne"
    if ($codexZasadyWAgents) { $wariant = "krotkie" }
    node $tmp3 $Projekt $wariant
    Remove-Item $tmp3 -Force

    $tmp4 = Join-Path $env:TEMP "mr-codex-hook-$Stempel.js"
    $jsCodex | Out-File -FilePath $tmp4 -Encoding utf8
    Kopia-Zapasowa $celHookow
    node $tmp4 $celHookow (Join-Path $Zrodlo "szablony-codex\hooks.json") $Projekt $Zrodlo
    $codexHooki = $LASTEXITCODE
    Remove-Item $tmp4 -Force
    if ($codexHooki -ne 0) {
      $zbedneC = @($script:Kopie | Where-Object { $_ -like "*hooks.json.bak-*" })
      foreach ($z in $zbedneC) { Remove-Item $z -Force }
      $script:Kopie = @($script:Kopie | Where-Object { $_ -notlike "*hooks.json.bak-*" })
    }
  } else {
    Write-Host "--  ladunki hookow Codeksa i .codex\hooks.json pominiete - nie ma node w PATH"
  }

  Write-Host "UWAGA  hooki Codeksa rusza dopiero po zatwierdzeniu poleceniem /hooks w CLI." -ForegroundColor Yellow
  Write-Host "       Zatwierdzasz raz - skrot liczy sie z definicji hooka, nie z tresci skryptu." -ForegroundColor Yellow
}

# ---------------------------------------------------------- 5. reszta instalacji
Write-Host ""
Write-Host "--- zasady globalne i moduly ---"

$wynikZasad = Uruchom-Podskrypt (Join-Path $Zrodlo "narzedzia\wpisz-zasady.ps1") `
  @{ Zrodlo = $Zrodlo; KatalogDomowy = $KatalogDomowy } "wpisz-zasady.ps1"
if (-not $wynikZasad.ok) { Write-Host "BLAD  zasady globalne: $($wynikZasad.czemu)" -ForegroundColor Red }

# Moduly z wlasnym instalatorem. Modul bez instalatora (podstawowy) to pliki
# skopiowane wyzej - nie ma tu nic do roboty.
$wyniki = @{}
foreach ($m in $Moduly) {
  if (-not $wybrane[$m.nazwa]) { Write-Host "--  modul [$($m.nazwa)] pominiety na zyczenie"; continue }
  if (-not $m.instalator) { $wyniki[$m.nazwa] = @{ ok = $true; czemu = "" }; continue }
  $wyniki[$m.nazwa] = Uruchom-Podskrypt (Join-Path $Zrodlo $m.instalator) `
    @{ Zrodlo = $Zrodlo; BezPytania = $true } $m.instalator
  if (-not $wyniki[$m.nazwa].ok) { Write-Host "BLAD  modul [$($m.nazwa)]: $($wyniki[$m.nazwa].czemu)" -ForegroundColor Red }
}

# Zadanie odswiezajace narzedzie ma stac niezaleznie od modulu pamieci - to
# jedyna droga aktualizacji tam, gdzie nie ma Claude Code, a [pamiec] wolno
# odrzucic. Gdy modul wszedl, zadanie zalozyl juz jego instalator; gdy nie -
# zakladamy je osobno, tym samym instalatorem w trybie -TylkoOdswiezanie.
$zadanieJuzJest = $false
foreach ($m in $Moduly) {
  if ($wybrane[$m.nazwa] -and $m.instalator -like "*instaluj-lore.ps1" -and $wyniki[$m.nazwa].ok) {
    $zadanieJuzJest = $true
  }
}
$wynikOdswiezania = $null
if (-not $zadanieJuzJest) {
  $wynikOdswiezania = Uruchom-Podskrypt (Join-Path $Zrodlo "narzedzia\instaluj-lore.ps1") `
    @{ Zrodlo = $Zrodlo; TylkoOdswiezanie = $true } "instaluj-lore.ps1 -TylkoOdswiezanie"
  if (-not $wynikOdswiezania.ok) {
    Write-Host "BLAD  zadanie odswiezajace narzedzie: $($wynikOdswiezania.czemu)" -ForegroundColor Red
  }
}

# 6. Znacznik wersji - z niego straznik wie, ktore moduly stoja we wdrozeniu,
# w jakiej wersji, ktorych uzytkownik nie chcial i gdzie stoi zrodlo.
# Format to proste "klucz: wartosc"; stan modulu siedzi pod "modul.<nazwa>.*",
# wiec trzeci modul to po prostu kolejne linie, bez zmiany formatu.
$wersja = Wersja-Narzedzia (Join-Path $Zrodlo "ZMIANY.md")
if (-not $wersja) { $wersja = "0.0.0" }
$commit = "nieznany"
try {
  $c = & git -C $Zrodlo rev-parse --short HEAD 2>$null
  if ($LASTEXITCODE -eq 0 -and $c) { $commit = ($c | Select-Object -First 1).ToString().Trim() }
} catch { }
$teraz = Get-Date -Format 'yyyy-MM-dd HH:mm'
$linieWersji = @("zrodlo: $Zrodlo", "commit: $commit", "data: $teraz")
foreach ($m in $Moduly) {
  $k = "modul." + $m.nazwa
  if ($wybrane[$m.nazwa] -and (-not $m.instalator -or $wyniki[$m.nazwa].ok)) {
    $linieWersji += "$k.wersja: $wersja"
  } elseif ($wybrane[$m.nazwa]) {
    $linieWersji += "$k.status: nieudany"      # probowalismy, nie wyszlo
  } else {
    $linieWersji += "$k.status: odrzucony"     # uzytkownik nie chcial - straznik nie wraca do tematu
  }
  $linieWersji += "$k.data: $teraz"
}
# Wdrozenie dla Codeksa ma wlasny stan - straznik go dzis nie aktualizuje, ale
# format jest ten sam ("klucz: wartosc"), wiec da sie po nim poznac, co i kiedy
# tam weszlo. Klucz zostaje takze w pliku wersji Claude Code, zeby jedno miejsce
# mowilo cala prawde o wdrozeniu.
if ($JestCodex) {
  $linieWersji += "codex.wersja: $wersja"
  $linieWersji += "codex.data: $teraz"
}
[System.IO.File]::WriteAllText((Join-Path $Projekt ".claude\megaruchacz-wersja.txt"),
  (($linieWersji -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "OK  .claude\megaruchacz-wersja.txt (wersja $wersja, commit $commit)"

if ($JestCodex) {
  $linieCodex = @("zrodlo: $Zrodlo", "commit: $commit", "data: $teraz",
                  "codex.wersja: $wersja", "codex.data: $teraz")
  if ($codexZasadyWAgents) { $linieCodex += "codex.zasady: AGENTS.md" }
  else { $linieCodex += "codex.zasady: tylko hook - AGENTS.md nietkniety" }
  [System.IO.File]::WriteAllText((Join-Path $celMega "wersja.txt"),
    (($linieCodex -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "OK  .megaruchacz\wersja.txt (wersja $wersja, commit $commit)"
}

# ------------------------------------------------------------ 7. samosprawdzenie
# Instalator sam po sobie sprawdza, co obiecal. Czesc sprawdzen dotyka tylko
# dysku - te sa dalej opisane wprost jako "zapisane", a nie "dziala".
Write-Host ""
Write-Host "--- samosprawdzenie ---"

$wymagane = @("megaruchacz-zasady.md","orchestrator-reminder.json",
              "mr-log.js","worklog.md","mapa.md","megaruchacz-wersja.txt")
# Pliki skladane node'em. Bez niego ich nie ma i nie udajemy, ze sa - ale to
# porazka tylko tam, gdzie w ogole moglyby do czegos sluzyc.
if ($Node) { $wymagane += @("megaruchacz-sesja.json","settings.json") }
foreach ($plik in $wymagane) {
  Sprawdz ".claude\$plik" (Test-Path (Join-Path $Projekt ".claude\$plik")) "plik nie powstal"
}
Get-ChildItem (Join-Path $Zrodlo ".claude\agents\*.md") | ForEach-Object {
  Sprawdz ".claude\agents\$($_.Name)" (Test-Path (Join-Path $Projekt ".claude\agents\$($_.Name)")) "plik nie powstal"
}
Nie-Sprawdzono "obecnosc plikow w .claude\ potwierdza tylko zapis na dysku - nie to, ze Claude Code je wczyta"

$plikZasad = Join-Path $Projekt ".claude\megaruchacz-zasady.md"
$zasadyOk = (Test-Path $plikZasad) -and ((Get-Item $plikZasad).Length -gt 0)
Sprawdz "zasady kierownika nie sa puste" $zasadyOk "plik zasad jest pusty albo go nie ma"

# settings.json - czysty JSON i komplet hookow. Hooki sa mechanizmem Claude
# Code; tam, gdzie go nie ma, ich brak nie jest bledem wdrozenia, tylko rzecza,
# ktorej na tej maszynie po prostu nie da sie wdrozyc.
if (-not $Claude) {
  Write-Host "  --    .claude\settings.json (hooki) - pominiete, nie ma Claude Code na tej maszynie"
  if ($JestCodex) {
    Nie-Sprawdzono "hookow Claude Code nie sprawdzano ani nie wymagano - tego narzedzia tu nie ma; tryb workerow stoi na czesci codeksowej"
  } else {
    Nie-Sprawdzono "hookow nie sprawdzano ani nie wymagano: naleza do Claude Code, a tego tu nie ma - tryb workerow na tej maszynie nie dziala"
  }
} else {
  $settingsOk = $false
  $czemuSettings = "nie ma pliku"
  if (Test-Path $celSettings) {
    $rawSet = Get-Content $celSettings -Raw
    try {
      $rawSet.TrimStart([char]0xFEFF) | ConvertFrom-Json | Out-Null
      $brakujace = @()
      foreach ($znacznik in @("megaruchacz-sesja.json","orchestrator-reminder.json","mr-log.js","straznik-zasad.ps1")) {
        if ($rawSet -notlike "*$znacznik*") { $brakujace += $znacznik }
      }
      if ($brakujace.Count -eq 0) { $settingsOk = $true } else { $czemuSettings = "brak hookow: " + ($brakujace -join ", ") }
    } catch {
      $czemuSettings = "to nie jest poprawny JSON"
    }
  }
  if ($settingsOk -and -not $hookiOk) { $settingsOk = $false; $czemuSettings = "hookow nie udalo sie dopisac (kod $kod)" }
  Sprawdz ".claude\settings.json - wpisy hookow sa w poprawnym JSON-ie" $settingsOk $czemuSettings
}

# --- czy te hooki w ogole da sie URUCHOMIC na tej maszynie ---
# Sam wpis w settings.json niczego nie dowodzi: audyt na obcej maszynie pokazal
# komplet wpisow i instalator meldujacy sukces, podczas gdy nic ich nie wykonalo.
# Dlatego kazde polecenie wyjmujemy z konfiguracji i probujemy odpalic.
$ustawienia = $null
if (Test-Path $celSettings) {
  try { $ustawienia = (Get-Content $celSettings -Raw).TrimStart([char]0xFEFF) | ConvertFrom-Json } catch { }
}
if (-not $Claude) {
  Write-Host "  --    hooki - pominiete, uruchamia je wylacznie Claude Code, a tego tu nie ma"
} elseif (-not $ustawienia) {
  Sprawdz "hooki daja sie uruchomic" $false "nie da sie odczytac settings.json, wiec nie mam czego probowac"
} elseif (-not $Bash) {
  # Kazdy hook Claude Code ma shell "bash", wiec bez basha nie mam czym ich
  # sprobowac. To OSTRZEZENIE, nie blad wdrozenia: pliki sa na miejscu, Claude
  # Code szuka basha po swojemu, a czesc codeksowa ma "commandWindows" i basha
  # nie potrzebuje w ogole. Blokowanie calej instalacji byloby tu falszywym alarmem.
  Write-Host "  UWAGA hooki Claude Code - nie znalazlem bash.exe ani w PATH, ani w typowych" -ForegroundColor Yellow
  Write-Host "        miejscach instalacji Gita, wiec nie mam czym ich sprobowac" -ForegroundColor Yellow
  Nie-Sprawdzono "hookow Claude Code nie probowalem uruchomic - nie widze bash.exe na tej maszynie; jesli hooki mimo to dzialaja, Claude Code ma wlasnego basha, a jesli nie - doinstaluj Git for Windows albo dopisz jego bin\ do PATH"
} else {
  # a) hooki podajace gotowy JSON - odpalamy naprawde i sprawdzamy, co wyszlo
  $ladunki = @(
    @{ zdarzenie = "SessionStart";     znacznik = "megaruchacz-sesja.json" },
    @{ zdarzenie = "UserPromptSubmit"; znacznik = "orchestrator-reminder.json" }
  )
  foreach ($para in $ladunki) {
    $zdarzenie = $para.zdarzenie
    $znacznik  = $para.znacznik
    $h = Polecenie-Hooka $ustawienia $zdarzenie $znacznik
    if (-not $h) {
      Sprawdz "hook $zdarzenie ($znacznik) wykonuje sie" $false "nie ma go w settings.json"
      continue
    }
    $w = Odpal-Przez-Bash $h.command
    $tresc = "$($w.tekst)".Trim()
    $ok = ($w.kod -eq 0 -and $tresc)
    if ($ok) { try { $tresc | ConvertFrom-Json | Out-Null } catch { $ok = $false } }
    Sprawdz "hook $zdarzenie ($znacznik) wykonuje sie" $ok "polecenie z settings.json nie wypisalo poprawnego JSON-a (kod $($w.kod))"
  }

  # b) hooki rejestru - samego mr-log.js NIE uruchamiamy, bo dopisalby do
  #    worklog.md zmyslony wpis o workerze, ktorego nie bylo. "node --check"
  #    mowi to, co tu potrzebne: czy interpreter jest i czy wczyta ten plik.
  $plikLog = Join-Path $Projekt ".claude\mr-log.js"
  foreach ($zdarzenie in @("SubagentStart", "SubagentStop")) {
    $h = Polecenie-Hooka $ustawienia $zdarzenie "mr-log.js"
    if (-not $h) {
      Sprawdz "hook $zdarzenie (mr-log.js) da sie uruchomic" $false "nie ma go w settings.json"
      continue
    }
    if (-not $Node) {
      Sprawdz "hook $zdarzenie (mr-log.js) da sie uruchomic" $false "nie ma node w PATH - polecenie tego hooka nie ma czym wystartowac"
      continue
    }
    $global:LASTEXITCODE = 0
    & node --check $plikLog 2>&1 | Out-Null
    Sprawdz "hook $zdarzenie (mr-log.js) da sie uruchomic" ($LASTEXITCODE -eq 0) "node nie wczytuje $plikLog"
  }
  Nie-Sprawdzono "hooki rejestru sprawdzono przez 'node --check' - nie uruchamialem mr-log.js, zeby nie dopisac do rejestru wpisu o nieistniejacym workerze"

  # c) straznik - jedyny hook, ktory startuje powershella z bashu. Zdejmujemy
  #    koncowe "|| true" (z nim nawet trup zwraca zero) i podmieniamy argumenty
  #    na -Moduly: to samo uruchomienie, tylko bez skutkow ubocznych.
  $h = Polecenie-Hooka $ustawienia "SessionStart" "straznik-zasad.ps1"
  if (-not $h) {
    Sprawdz "hook straznika da sie uruchomic" $false "nie ma go w settings.json"
  } else {
    $polecenie = $h.command -replace '\s*\|\|\s*true\s*$', ''
    $polecenie = $polecenie -replace '\s-Zrodlo\s.*$', ' -Moduly'
    $w = Odpal-Przez-Bash $polecenie
    $ok = ($w.kod -eq 0 -and "$($w.tekst)" -match '"nazwa"')
    Sprawdz "hook straznika da sie uruchomic" $ok "bash nie odpalil powershella ze straznikiem (kod $($w.kod))"
    Nie-Sprawdzono "straznika uruchomiono w wariancie -Moduly; pelne wywolanie z hooka konczy sie '|| true', wiec jego niepowodzenie i tak nigdy nie zatrzyma sesji"
  }
}
if ($Claude) {
  Nie-Sprawdzono "czy Claude Code faktycznie wykona te hooki w Twojej sesji - to widac dopiero po zamknieciu i otwarciu okna"
}

# --- czesc dla Codeksa ---
# Tu, gdzie sie da, sprawdzamy DZIALANIE, a nie sam zapis na dysku: rejestr
# uruchamiamy naprawde, hooks.json parsujemy i patrzymy, czy sciezki w nim
# prowadza do istniejacych plikow.
if ($JestCodex) {
  foreach ($p in @("zasady-kierownika.md","przypomnienie.json","worklog.md","mapa.md","wersja.txt")) {
    Sprawdz ".megaruchacz\$p" (Test-Path (Join-Path $celMega $p)) "plik nie powstal"
  }
  Get-ChildItem (Join-Path $Zrodlo "szablony-codex\agents\*.toml") | ForEach-Object {
    Sprawdz ".codex\agents\$($_.Name)" (Test-Path (Join-Path $celCodex "agents\$($_.Name)")) "plik nie powstal"
  }

  if ($codexZasadyWAgents) {
    $agentsOk = (Test-Path $celAgentsMd) -and ((Get-Content $celAgentsMd -Raw) -like "*<!-- MegaRuchacz:start -->*")
    Sprawdz "AGENTS.md - blok zasad kierownika" $agentsOk "nie ma znacznika MegaRuchacz:start"
  } else {
    Write-Host "  --    AGENTS.md - nie ruszany (sledzony w gicie albo nieczytelny jako UTF-8); zasady ida pelnym ladunkiem hooka"
    Nie-Sprawdzono "zasad kierownika NIE MA w AGENTS.md - Codex dostanie je wylacznie z hooka SessionStart, czyli dopiero po zatwierdzeniu hookow przez /hooks"
  }

  # Ladunki hookow musza byc poprawnym JSON-em - Codex czyta z nich additionalContext.
  foreach ($p in @("zasady-sesja.json","przypomnienie.json")) {
    $plikL = Join-Path $celMega $p
    $okL = $false
    $czemuL = "nie ma pliku"
    if (-not $Node -and -not (Test-Path $plikL)) { $czemuL = "nie ma node w PATH, wiec ladunek nie powstal" }
    if (Test-Path $plikL) {
      try {
        $ladunek = (Get-Content $plikL -Raw).TrimStart([char]0xFEFF) | ConvertFrom-Json
        if ($ladunek.hookSpecificOutput -and $ladunek.hookSpecificOutput.additionalContext) { $okL = $true }
        else { $czemuL = "brak hookSpecificOutput.additionalContext" }
      } catch { $czemuL = "to nie jest poprawny JSON" }
    }
    Sprawdz ".megaruchacz\$p - ladunek dla hooka" $okL $czemuL
  }

  $hookiCodexOk = $false
  $czemuH = "nie ma pliku"
  $rawH = ""
  if (Test-Path $celHookow) {
    $rawH = (Get-Content $celHookow -Raw).TrimStart([char]0xFEFF)
    try {
      $rawH | ConvertFrom-Json | Out-Null
      $brakH = @()
      foreach ($zn in @("zasady-sesja.json","przypomnienie.json","mr-log-codex.js")) {
        if ($rawH -notlike "*$zn*") { $brakH += $zn }
      }
      if ($brakH.Count -eq 0) { $hookiCodexOk = $true } else { $czemuH = "brak hookow: " + ($brakH -join ", ") }
    } catch { $czemuH = "to nie jest poprawny JSON" }
  } elseif (-not $Node) {
    $czemuH = "nie ma node w PATH, wiec hookow nie dopisywalismy"
  }
  if ($hookiCodexOk -and $codexHooki -eq 3) {
    $hookiCodexOk = $false
    $czemuH = "cudzy hooks.json nie jest JSON-em - nie ruszalem go"
  }
  Sprawdz ".codex\hooks.json - wpisy hookow sa w poprawnym JSON-ie" $hookiCodexOk $czemuH

  if ($hookiCodexOk) {
    $brakSciezek = @()
    $wSrodku = @([regex]::Matches($rawH, '[A-Za-z]:/[^"'']+?\.(?:json|js)') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    foreach ($s in $wSrodku) { if (-not (Test-Path $s)) { $brakSciezek += $s } }
    Sprawdz ".codex\hooks.json - sciezki w poleceniach wskazuja na istniejace pliki" `
      ($brakSciezek.Count -eq 0) ("nie ma: " + ($brakSciezek -join ", "))
  }

  # Rejestr - jedyna czesc, ktora da sie sprawdzic dzialaniem. Wolamy skrypt
  # przykladowym zdarzeniem w katalogu probnym w TEMP; do rejestru projektu nie
  # piszemy, bo byl to wpis o workerze, ktorego nigdy nie bylo.
  #
  # UWAGA: zdarzenie MUSI trafic na standardowe wejscie node'a - stamtad
  # mr-log-codex.js bierze rodzaj workera. Potok PowerShella ('$tekst | & node')
  # tego nie dowozil: node dostawal puste wejscie, dopisywal ogolne "worker",
  # a sprawdzenie szukajace "scout" meldowalo blad mimo dzialajacego skryptu.
  # Dlatego wejscie idzie z pliku, przez Start-Process -RedirectStandardInput.
  $skryptLog = Join-Path $Zrodlo "narzedzia\mr-log-codex.js"
  if (-not $Node) {
    Sprawdz "mr-log-codex.js dopisuje worker do rejestru" $false "nie ma node w PATH - hooki rejestru nie maja czym wystartowac"
  } elseif (-not (Test-Path $skryptLog)) {
    Sprawdz "mr-log-codex.js dopisuje worker do rejestru" $false "nie ma pliku $skryptLog"
  } else {
    $proba = Join-Path $env:TEMP "mr-proba-codex-$Stempel"
    New-Item -ItemType Directory -Force -Path $proba | Out-Null
    $plikZdarzenia = Join-Path $env:TEMP "mr-proba-zdarzenie-$Stempel.json"
    [System.IO.File]::WriteAllText($plikZdarzenia,
      '{"agent_id":"proba","agent_type":"scout","permission_mode":"read-only"}',
      (New-Object System.Text.UTF8Encoding($false)))
    $probaWyjscie = Join-Path $env:TEMP "mr-proba-wyjscie-$Stempel.txt"
    $probaBlad    = Join-Path $env:TEMP "mr-proba-blad-$Stempel.txt"
    $kodLog = -1
    try {
      $procLog = Start-Process -FilePath $Node.Source `
        -ArgumentList @("`"$skryptLog`"", "start", "`"$proba`"") `
        -RedirectStandardInput $plikZdarzenia -RedirectStandardOutput $probaWyjscie `
        -RedirectStandardError $probaBlad -NoNewWindow -Wait -PassThru
      $kodLog = $procLog.ExitCode
    } catch { }
    $probaPlik = Join-Path $proba ".megaruchacz\worklog.md"
    $trescProby = ""
    if (Test-Path $probaPlik) { $trescProby = Get-Content $probaPlik -Raw }
    # Sprawdzamy to, co ten hook ma robic: czy rejestr UROSL o wpis. Rodzaj
    # workera to juz tylko jakosc wpisu - gdy zdarzenie nie dojdzie na wejscie,
    # skrypt pisze ogolne "worker". To warte odnotowania, ale nie jest powodem,
    # zeby oblac cale wdrozenie.
    $dopisane = ($trescProby -match "START")
    Sprawdz "mr-log-codex.js dopisuje worker do rejestru (uruchomiony naprawde)" $dopisane `
      "skrypt nie dopisal linii o workerze w katalogu probnym (kod $kodLog)"
    if ($dopisane -and $trescProby -notmatch "START\s+scout") {
      Nie-Sprawdzono "rejestr dostal wpis, ale bez rodzaju workera - probne zdarzenie nie doszlo na standardowe wejscie skryptu; w realnej pracy podaje je hook Codeksa"
    }
    Remove-Item $proba -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $plikZdarzenia, $probaWyjscie, $probaBlad -Force -ErrorAction SilentlyContinue
  }

  Nie-Sprawdzono "hooki Codeksa sa ZAPISANE, ale nie wystartuja, dopoki nie zatwierdzisz ich poleceniem /hooks w CLI - bez czlowieka nie da sie tego ani zrobic, ani sprawdzic; zatwierdza sie raz, bo skrot liczy sie z definicji hooka (zdarzenie, matcher, polecenie, timeout, async), a nie z tresci skryptu"
  Nie-Sprawdzono "role z .codex\agents\ i zasady z AGENTS.md potwierdza tylko zapis na dysku - to, ze Codex je wczyta, widac dopiero w nowej sesji"
  Nie-Sprawdzono "straznik zasad nie odswieza czesci codeksowej - nowsza wersje tych plikow nanosi ponowne uruchomienie wdroz.ps1"
} else {
  Write-Host "  --    czesc dla Codeksa - pominieta, nie widze go na tej maszynie (wymusic mozna: -WymusCodex)"
}

Sprawdz "wpisanie zasad globalnych" $wynikZasad.ok $wynikZasad.czemu

# Zadanie odswiezajace zakladalismy tylko wtedy, gdy nie zrobil tego instalator
# modulu pamieci - inaczej sprawdzil je juz on sam.
if ($null -ne $wynikOdswiezania) {
  Sprawdz "zadanie odswiezajace narzedzie (MegaRuchaczOdswiez)" $wynikOdswiezania.ok $wynikOdswiezania.czemu
  Nie-Sprawdzono "zadanie odswiezajace jest w harmonogramie; czy naprawde cos podciagnie, widac dopiero w ~\.claude\.megaruchacz-tlo.log po pierwszym przebiegu"
}

$blokOk = $false
if (Test-Path $plikDomowy) { $blokOk = ((Get-Content $plikDomowy -Raw) -like "*<!-- MegaRuchacz:start -->*") }
Sprawdz "blok zasad globalnych zapisany w $plikDomowy" $blokOk "nie ma znacznika MegaRuchacz:start"
Nie-Sprawdzono "zasady globalne sa zapisane w pliku; czy Twoj klient je czyta, widac dopiero w nowej sesji"

foreach ($m in $Moduly) {
  if (-not $wybrane[$m.nazwa] -or -not $m.instalator) { continue }
  Sprawdz "instalacja modulu [$($m.nazwa)]" $wyniki[$m.nazwa].ok $wyniki[$m.nazwa].czemu
  $wynikSprawdz = Uruchom-Podskrypt (Join-Path $Zrodlo $m.instalator) `
    @{ Zrodlo = $Zrodlo; TylkoSprawdz = $true } "$($m.instalator) -TylkoSprawdz"
  Sprawdz "modul [$($m.nazwa)] odpowiada na sprawdzenie" $wynikSprawdz.ok $wynikSprawdz.czemu
}

if ($script:Kopie.Count -gt 0) {
  Write-Host ""
  Write-Host "Kopie zapasowe:"
  $script:Kopie | ForEach-Object { Write-Host "  $_" }
}

# Zielone "OK" bez tej listy czytaloby sie jak obietnica, ktorej samosprawdzenie
# nie jest w stanie zlozyc. Roznica miedzy "zapisane" a "dziala" ma byc widoczna.
if ($script:Niepelne.Count -gt 0) {
  Write-Host ""
  Write-Host "Czego to sprawdzenie NIE obejmuje:" -ForegroundColor DarkGray
  $script:Niepelne | ForEach-Object { Write-Host "  -  $_" -ForegroundColor DarkGray }
}

Write-Host ""
if ($script:Bledy.Count -eq 0) {
  Write-Host "Gotowe - wszystko na miejscu, zaden sledzony plik nie ruszony." -ForegroundColor Green
  if ($Claude) {
    Write-Host "Zamknij i otworz Claude Code na nowo, zeby zasady weszly w zycie."
  } elseif ($JestCodex) {
    Write-Host "Zamknij i otworz Codeksa na nowo, zeby zasady weszly w zycie."
  } else {
    Write-Host "Zamknij i otworz swoje narzedzie AI na nowo, zeby zasady weszly w zycie."
    Write-Host "Na tej maszynie NIE dziala tryb workerow - wymaga Claude Code albo Codeksa." -ForegroundColor Yellow
    Write-Host "Dziala: zasady globalne i odswiezanie narzedzia zadaniem MegaRuchaczOdswiez" -ForegroundColor Yellow
    Write-Host "z Harmonogramu." -ForegroundColor Yellow
  }
  if ($JestCodex) {
    Write-Host ""
    Write-Host "JESZCZE JEDEN KROK, BEZ NIEGO HOOKI CODEKSA NIE RUSZA:" -ForegroundColor Yellow
    Write-Host "  Wpisz w Codeksie /hooks i zatwierdz hooki MegaRuchacza. Dopoki tego nie" -ForegroundColor Yellow
    Write-Host "  zrobisz, rejestr .megaruchacz\worklog.md zostanie pusty, a zasady i" -ForegroundColor Yellow
    Write-Host "  przypomnienie nie wejda z hooka. To nie znaczy, ze wdrozenie zawiodlo." -ForegroundColor Yellow
    Write-Host "  Zatwierdzasz RAZ. Codex liczy skrot z samej definicji hooka (zdarzenie," -ForegroundColor Yellow
    Write-Host "  matcher, polecenie, timeout, async), a nie z tresci skryptu - ani nasze" -ForegroundColor Yellow
    Write-Host "  pozniejsze poprawki, ani aktualizacja Codeksa zaufania nie uniewazniaja." -ForegroundColor Yellow
  }
  exit 0
} else {
  Write-Host ("Instalacja NIEPELNA - do poprawy: " + ($script:Bledy -join "; ")) -ForegroundColor Red
  Write-Host "Popraw powyzsze i uruchom instalator ponownie, potem zamknij i otworz narzedzie AI na nowo."
  if ($JestCodex) {
    Write-Host "Pamietaj tez o /hooks w Codeksie - bez zatwierdzenia jego hooki nie ruszaja." -ForegroundColor Yellow
    Write-Host "Zatwierdzasz raz: skrot liczy sie z definicji hooka, nie z tresci skryptu." -ForegroundColor Yellow
  }
  exit 1
}
