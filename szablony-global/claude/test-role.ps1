# Test rol workerow (szablony-global\claude\agents) i zdania o nich w zasadach kierownika.
# Role maja omitClaudeMd: true - worker nie dostaje zadnego CLAUDE.md (proba 17.10 na
# Claude Code 2.1.302: start workera bez pliku instrukcji), wiec rdzen zasad musi stac
# w samej roli. Brak ktoregos punktu = worker nie zna zasady, a nikt tego nie zauwazy.
#   -Katalog  katalog z kopia agents\ i zasady-kierownika.md (proba negatywna na kopii)
param([string]$Katalog = $PSScriptRoot)

$ErrorActionPreference = "Stop"
$bledy = @()
function Blad($t) { $script:bledy += $t; Write-Host "BLAD  $t" -ForegroundColor Red }

$role = @("implementer", "projektant", "scout", "verifier", "zastepca")
# Kotwice rdzenia zasad - kazda musi byc w kazdej roli.
$rdzen = [ordered]@{
  "CLAUDE.md projektu na starcie" = '`CLAUDE.md` w katalogu'
  "Co wiem przy sprawach firmy"   = 'Co wiem'
  "sciezka globalnego pliku"      = '~/.claude/CLAUDE.md'
  "Amazon/eBay tylko odczyt"      = 'execute_proposal'
  "nic na produkcji"              = 'na produkcji z'
  "commit bez Co-Authored-By"     = 'bez linii `Co-Authored-By`'
  "git add tylko wlasnych"        = 'nigdy `-A`'
  "lore_search na starcie"        = 'wyszukanie `lore_search`'
  "znalezisko to trop"            = 'trop, nie dow'
}

$znalezione = @(Get-ChildItem (Join-Path $Katalog "agents\*.md") | ForEach-Object { $_.BaseName })
foreach ($r in $role) { if ($znalezione -notcontains $r) { Blad "brak roli $r" } }

foreach ($r in $role) {
  $plik = Join-Path $Katalog "agents\$r.md"
  if (-not (Test-Path $plik)) { continue }
  $t = [IO.File]::ReadAllText($plik, [Text.Encoding]::UTF8) -replace "`r`n", "`n"
  if ($t -notmatch '(?s)^---\n(.*?)\n---\n(.*)$') { Blad "$r - brak frontmattera"; continue }
  $fm = $Matches[1]; $tresc = $Matches[2]
  if ($fm -notmatch '(?m)^omitClaudeMd: true$') { Blad "$r - frontmatter bez 'omitClaudeMd: true'" }
  # Rola z lista tools dostaje TYLKO wymienione narzedzia - bez lore_search punkt rdzenia bylby martwy.
  if ($fm -notmatch '(?m)^tools: .*\bmcp__lore__lore_search\b') { Blad "$r - tools bez mcp__lore__lore_search (punkt o lore_search martwy)" }
  foreach ($k in $rdzen.Keys) {
    if (-not $tresc.Contains($rdzen[$k])) { Blad "$r - brak w rdzeniu: $k" }
  }
  if (-not $tresc.Contains("kierownik-template")) { Blad "$r - brak znacznika kierownik-template" }
}

$zasady = Join-Path $Katalog "zasady-kierownika.md"
$z = [IO.File]::ReadAllText($zasady, [Text.Encoding]::UTF8)
if (-not $z.Contains("omitClaudeMd")) { Blad "zasady-kierownika - nie mowia, ze worker nie dostaje CLAUDE.md" }
if ($z.Contains("dostaje sam")) { Blad "zasady-kierownika - nadal twierdza, ze worker dostaje CLAUDE.md projektu sam" }

if ($bledy.Count -gt 0) { Write-Host "NIE PRZESZLO: $($bledy.Count) bledow"; exit 1 }
Write-Host "OK  role: $($role.Count), rdzen: $($rdzen.Count) punktow w kazdej, zasady kierownika zgodne"
exit 0
