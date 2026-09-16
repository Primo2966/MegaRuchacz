# Wdraza tryb MegaRuchacza do istniejacego projektu - PRYWATNIE.
# Uzycie:  /MegaRuchacz   (w Claude Code, w dowolnym projekcie)
#     lub:  powershell -File C:\dev\claude-worker\wdroz.ps1   (bez argumentu = biezacy katalog)
#
# Wszystko ladunku w .claude/, ktory w wiekszosci repo jest w .gitignore.
# NIE dotyka zadnego sledzonego pliku - CLAUDE.md zostaje nietkniety.
# Zasady trafiaja do modelu przez hook SessionStart, nie przez CLAUDE.md.

param([string]$Projekt = (Get-Location).Path)

$Zrodlo  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Stempel = Get-Date -Format "yyyyMMdd-HHmmss"
$script:Kopie = @()

function Kopia-Zapasowa($sciezka) {
  if (Test-Path $sciezka) {
    $bak = "$sciezka.bak-$Stempel"
    Copy-Item $sciezka $bak -Force
    $script:Kopie += $bak
  }
}

if (-not (Test-Path $Projekt)) { Write-Error "Nie ma takiego katalogu: $Projekt"; exit 1 }
$Projekt = (Resolve-Path $Projekt).Path
if ($Projekt -eq (Resolve-Path $Zrodlo).Path) {
  Write-Error "To jest katalog szablonu - uruchom to w projekcie docelowym, nie tutaj."
  exit 1
}
Write-Host "Projekt docelowy: $Projekt"

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

# 4. settings.json - dwa hooki + worktree
$js = @'
const fs = require("fs"), p = process.argv[2];
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
dodajLogger("SubagentStart", "", "wpis do rejestru przy starcie workera");
dodajLogger("SubagentStop", " stop", "wpis przy zakonczeniu workera");
dodajHook("SessionStart", "megaruchacz-sesja.json", "pelne zasady raz na sesje");
dodajHook("UserPromptSubmit", "orchestrator-reminder.json", "przypomnienie przy kazdym enterze");
if (zmiana) { fs.writeFileSync(p, JSON.stringify(s, null, 2)); process.exit(0); }
process.exit(4);
'@
$tmp2 = Join-Path $env:TEMP "mr-hook-$Stempel.js"
$js | Out-File -FilePath $tmp2 -Encoding utf8
$celSettings = Join-Path $Projekt ".claude\settings.json"
Kopia-Zapasowa $celSettings
node $tmp2 $celSettings
$kod = $LASTEXITCODE
Remove-Item $tmp2 -Force

if ($kod -ne 0) {
  $zbedne = @($script:Kopie | Where-Object { $_ -like "*settings.json.bak-*" })
  foreach ($z in $zbedne) { Remove-Item $z -Force }
  $script:Kopie = @($script:Kopie | Where-Object { $_ -notlike "*settings.json.bak-*" })
}

if ($script:Kopie.Count -gt 0) {
  Write-Host ""
  Write-Host "Kopie zapasowe:"
  $script:Kopie | ForEach-Object { Write-Host "  $_" }
}

Write-Host ""
Write-Host "Gotowe - wszystko w .claude\, zaden sledzony plik nie ruszony."
Write-Host "Zamknij i otworz Claude Code na nowo."
