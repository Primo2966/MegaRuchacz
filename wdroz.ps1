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

param(
  [string]$Projekt = (Get-Location).Path,
  [switch]$BezPytania,
  [string]$KatalogDomowy = $HOME
)

$Zrodlo  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Stempel = Get-Date -Format "yyyyMMdd-HHmmss"
$script:Kopie = @()
$script:Bledy = @()

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
Write-Host "2) Poza projektem - zasady globalne:"
Write-Host "   do $plikDomowy i do ~\.codex\AGENTS.md zostanie dopisany blok"
Write-Host "   miedzy znacznikami <!-- MegaRuchacz:start --> i <!-- MegaRuchacz:koniec -->."
Write-Host "   Twoje wlasne zapiski zostaja nietkniete, przed zmiana powstaje kopia zapasowa,"
Write-Host "   a caly blok da sie usunac: narzedzia\wpisz-zasady.ps1 -Usun"
Write-Host ""
Write-Host "3) Moduly - kazdy instaluje sie i aktualizuje osobno:" -ForegroundColor Yellow
foreach ($m in $Moduly) {
  $kiedy = if ($m.pytaj) { "zapytam osobno" } else { "wchodzi domyslnie" }
  Write-Host "   [$($m.nazwa)] - $kiedy"
  Write-Host "      daje:     $($m.opis)"
  Write-Host "      kosztuje: $($m.koszt)"
}
Write-Host ""

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
$tmp1 = Join-Path $env:TEMP "mr-sesja-$Stempel.js"
$budujSesje | Out-File -FilePath $tmp1 -Encoding utf8
node $tmp1 $Projekt
Remove-Item $tmp1 -Force

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
$tmp2 = Join-Path $env:TEMP "mr-hook-$Stempel.js"
$js | Out-File -FilePath $tmp2 -Encoding utf8
$celSettings = Join-Path $Projekt ".claude\settings.json"
Kopia-Zapasowa $celSettings
node $tmp2 $celSettings $Zrodlo
$kod = $LASTEXITCODE
Remove-Item $tmp2 -Force

if ($kod -ne 0) {
  $zbedne = @($script:Kopie | Where-Object { $_ -like "*settings.json.bak-*" })
  foreach ($z in $zbedne) { Remove-Item $z -Force }
  $script:Kopie = @($script:Kopie | Where-Object { $_ -notlike "*settings.json.bak-*" })
}
# 3 = cudzy settings.json nie jest JSON-em, 4 = wszystko juz bylo na miejscu
$hookiOk = ($kod -eq 0 -or $kod -eq 4)

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
[System.IO.File]::WriteAllText((Join-Path $Projekt ".claude\megaruchacz-wersja.txt"),
  (($linieWersji -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "OK  .claude\megaruchacz-wersja.txt (wersja $wersja, commit $commit)"

# ------------------------------------------------------------ 7. samosprawdzenie
# Instalator sam po sobie sprawdza, czy to, co obiecal, naprawde lezy na dysku.
Write-Host ""
Write-Host "--- samosprawdzenie ---"

$wymagane = @("megaruchacz-zasady.md","megaruchacz-sesja.json","orchestrator-reminder.json",
              "mr-log.js","worklog.md","mapa.md","settings.json","megaruchacz-wersja.txt")
foreach ($plik in $wymagane) {
  Sprawdz ".claude\$plik" (Test-Path (Join-Path $Projekt ".claude\$plik")) "plik nie powstal"
}
Get-ChildItem (Join-Path $Zrodlo ".claude\agents\*.md") | ForEach-Object {
  Sprawdz ".claude\agents\$($_.Name)" (Test-Path (Join-Path $Projekt ".claude\agents\$($_.Name)")) "plik nie powstal"
}

$plikZasad = Join-Path $Projekt ".claude\megaruchacz-zasady.md"
$zasadyOk = (Test-Path $plikZasad) -and ((Get-Item $plikZasad).Length -gt 0)
Sprawdz "zasady kierownika nie sa puste" $zasadyOk "plik zasad jest pusty albo go nie ma"

# settings.json - czysty JSON i komplet hookow
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
Sprawdz ".claude\settings.json - poprawny JSON z hookami" $settingsOk $czemuSettings

Sprawdz "wpisanie zasad globalnych" $wynikZasad.ok $wynikZasad.czemu

$blokOk = $false
if (Test-Path $plikDomowy) { $blokOk = ((Get-Content $plikDomowy -Raw) -like "*<!-- MegaRuchacz:start -->*") }
Sprawdz "blok zasad globalnych w $plikDomowy" $blokOk "nie ma znacznika MegaRuchacz:start"

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

Write-Host ""
if ($script:Bledy.Count -eq 0) {
  Write-Host "Gotowe - wszystko na miejscu, zaden sledzony plik nie ruszony." -ForegroundColor Green
  Write-Host "Zamknij i otworz Claude Code na nowo, zeby zasady weszly w zycie."
  exit 0
} else {
  Write-Host ("Instalacja NIEPELNA - do poprawy: " + ($script:Bledy -join "; ")) -ForegroundColor Red
  Write-Host "Popraw powyzsze i uruchom instalator ponownie, potem zamknij i otworz Claude Code na nowo."
  exit 1
}
