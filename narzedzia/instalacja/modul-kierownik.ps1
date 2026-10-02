# narzedzia\instalacja\modul-kierownik.ps1 - modul "kierownik": tryb MegaRuchacza rozdajacego
# zadania workerom (zasady kierownika, role agentow, przypomnienie, rejestr START/KONIEC).
#
# Co zaklada - wszystko przez narzedzia\instaluj-globalnie.ps1 (jeden kod dla instalacji
# recznej i dla okna instalatora):
#   - blok <!-- MegaRuchacz:kierownik --> w ~\.claude\CLAUDE.md (wariant Claude Code albo
#     opencode/Codex) i w ~\.codex\AGENTS.md, kopie dla opencode
#   - role w ~\.claude\agents (piec, poznawane po znaczniku kierownik-template), w opencode i -
#     gdy w rejestrze jest narzedzia.codex = true albo MegaRuchacz juz je tam zalozyl - w Codeksie
#   - rejestr pracy: ~\.claude\megaruchacz-mr-log.js + hooki SubagentStart/Stop, ladunek
#     przypomnienia ~\.claude\mr\orchestrator-reminder.json, znacznik ~\.claude\.megaruchacz-global
# Potrzebuje Node.js - hooki przypomnienia i rejestru to skrypty node; bez niego rejestr po cichu
# nie dziala, dlatego tu jest wymagany.
# Usun: instaluj-globalnie.ps1 -Usun (blok, role Claude/opencode, rejestr, znacznik, hooki), a do
#   tego to, czego on nie zdejmuje: role i hooki rejestru Codeksa, ladunek przypomnienia. Potem
#   straznik uklada hooki od nowa wedlug rejestru (hook straznika modulu baza zostaje).
#   Klucz "worktree" w settings.json zostaje (mogl byc Twoj). Danych uzytkownika ten modul nie ma.
#
# Uzycie (umowa wyjscia - naglowek wspolne.ps1):
#   powershell -NoProfile -ExecutionPolicy Bypass -File narzedzia\instalacja\modul-kierownik.ps1
#     -Akcja Instaluj|Usun|Stan [-KatalogDomowy <kat>] [-Zrodlo <repo>] [-Proba] [-UsunDane]

[CmdletBinding()]
param(
  [string]$Akcja = "",
  [string]$KatalogDomowy = $HOME,
  [string]$Zrodlo = "",
  [switch]$Proba,
  [switch]$UsunDane
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "wspolne.ps1")
if (-not $Zrodlo) { $Zrodlo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$s0 = Start-Modul "kierownik" $Akcja ([bool]$Proba) $Zrodlo $KatalogDomowy
$Zrodlo = $s0.Zrodlo; $KatalogDomowy = $s0.KatalogDomowy

$Globalnie  = Join-Path $Zrodlo "narzedzia\instaluj-globalnie.ps1"
$DomClaude  = Join-Path $KatalogDomowy ".claude"
$DomCodex   = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $KatalogDomowy ".codex" }
$Ustawienia = Join-Path $DomClaude "settings.json"
$Ladunek    = Join-Path $DomClaude "mr\orchestrator-reminder.json"
$RejestrJs  = Join-Path $DomClaude "megaruchacz-mr-log.js"
$Znacznik   = Join-Path $DomClaude ".megaruchacz-global"
$Role       = @("implementer", "scout", "verifier", "zastepca", "projektant")
$Poczatek   = "<!-- MegaRuchacz:kierownik:start -->"

function Nasza-Rola([string]$p) {
  return ((Test-Path -LiteralPath $p) -and ([System.IO.File]::ReadAllText($p) -match "kierownik-template"))
}

function Bloki-Kierownika([string]$plik) {
  if (-not (Test-Path -LiteralPath $plik)) { return 0 }
  return ([regex]::Matches([System.IO.File]::ReadAllText($plik), [regex]::Escape($Poczatek))).Count
}

function Zbierz-Stan($rej, [hashtable]$prog) {
  $zainst = [bool]$rej.moduly.kierownik
  $role = @($Role | Where-Object { Nasza-Rola (Join-Path $DomClaude "agents\$_.md") })
  $bloki = Bloki-Kierownika (Join-Path $DomClaude "CLAUDE.md")
  $start = Policz-Hooki $Ustawienia "SubagentStart" 'mr-log\.js(?![A-Za-z0-9])'
  $stop = Policz-Hooki $Ustawienia "SubagentStop" 'mr-log\.js(?![A-Za-z0-9])'
  $przyp = Policz-Hooki $Ustawienia "UserPromptSubmit" 'przypomnienie\.js(?![A-Za-z0-9])'
  if ($zainst) {
    if ($bloki -ne 1) { Problem "blok zasad kierownika w ~\.claude\CLAUDE.md: jest $bloki (ma byc dokladnie jeden)" }
    if ($role.Count -ne $Role.Count) { Problem "role w ~\.claude\agents: $($role.Count) z $($Role.Count)" }
    if (-not (Test-Path -LiteralPath $RejestrJs)) { Problem "nie ma rejestru workerow $RejestrJs" }
    if (-not (Test-Path -LiteralPath $Ladunek)) { Problem "nie ma ladunku przypomnienia $Ladunek" }
    if ($start -ne 1 -or $stop -ne 1) { Problem "hooki rejestru START/KONIEC w settings.json: SubagentStart $start, SubagentStop $stop (ma byc po jednym)" }
    if ($przyp -ne 1) { Problem "hook przypomnienia (UserPromptSubmit) w settings.json: $przyp (ma byc jeden)" }
    if (-not $prog["node"]) { Problem "nie ma Node.js - hooki przypomnienia i rejestru nie zadzialaja" }
  }
  $dziala = $zainst -and ($script:MR.problemy.Count -eq 0)
  return [pscustomobject]@{ Zainstalowany = $zainst; Dziala = $dziala; Szczegoly = [ordered]@{
    blok_kierownika = $bloki; role = $role; rejestr_js = (Test-Path -LiteralPath $RejestrJs); ladunek = (Test-Path -LiteralPath $Ladunek)
    hook_start = $start; hook_stop = $stop; hook_przypomnienie = $przyp; znacznik = (Test-Path -LiteralPath $Znacznik) } }
}

# Role i hooki rejestru Codeksa - instaluj-globalnie.ps1 -Usun ich nie zdejmuje. Nasze poznajemy
# po znaczniku (role) i po mr-log-codex.js / statusMessage "MegaRuchacz" (hooki); cudze zostaja.
function Usun-Z-Codeksa {
  $ok = $true
  foreach ($r in @(Get-ChildItem -Path (Join-Path $DomCodex "agents\*.toml") -ErrorAction SilentlyContinue)) {
    if (-not (Nasza-Rola $r.FullName)) { continue }
    if ($Proba) { Plan "usunalbym role Codeksa $($r.FullName)"; continue }
    try { Remove-Item -LiteralPath $r.FullName -Force -ErrorAction Stop; Krok "usunieta rola Codeksa $($r.Name)" }
    catch { $ok = $false; Ostrzezenie "nie udalo sie usunac $($r.FullName): $($_.Exception.Message)" }
  }
  $plik = Join-Path $DomCodex "hooks.json"
  if (-not (Test-Path -LiteralPath $plik)) { return $ok }
  try { $s = [System.IO.File]::ReadAllText($plik).TrimStart([char]0xFEFF) | ConvertFrom-Json }
  catch { Ostrzezenie "$plik nie jest czystym JSON-em - hookow rejestru Codeksa nie zdejmuje"; return $false }
  if ($null -eq $s -or $null -eq $s.hooks) { return $ok }
  $zmiana = $false
  foreach ($z in @($s.hooks.PSObject.Properties.Name)) {
    $grupy = @()
    foreach ($g in @($s.hooks.$z)) {
      if ($null -eq $g -or -not ($g.PSObject.Properties.Name -contains "hooks")) { $grupy += ,$g; continue }
      $zostaja = @($g.hooks | Where-Object { $_ -and -not (((("" + $_.command + " " + $_.commandWindows) -match 'mr-log-codex\.js')) -or (("" + $_.statusMessage) -like "MegaRuchacz*")) })
      if ($zostaja.Count -ne @($g.hooks).Count) { $zmiana = $true }
      if ($zostaja.Count -gt 0) { $g.hooks = $zostaja; $grupy += ,$g }
    }
    if ($grupy.Count -eq 0) { [void]$s.hooks.PSObject.Properties.Remove($z) } else { $s.hooks.$z = $grupy }
  }
  if (-not $zmiana) { return $ok }
  if ($Proba) { Plan "zdjalbym hooki rejestru MegaRuchacza z $plik"; return $ok }
  $kopia = Lore-Kopia-Obok $plik
  [System.IO.File]::WriteAllText($plik, ($s | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
  Krok "zdjete hooki rejestru MegaRuchacza z $plik (kopia: $kopia; cudze zostaly)"
  return $ok
}

try {
  if ($Akcja -eq "Stan") {
    $prog = Sprawdz-Programy @("node") @("bash")
    $rej = Czytaj-Instalacje $KatalogDomowy
    if ($rej.blad) { Problem "rejestr modulow: $($rej.blad)" }
    $st = Zbierz-Stan $rej $prog
    $kom = if ($st.Dziala) { "kierownik dziala" } elseif ($st.Zainstalowany) { "kierownik wlaczony, ale: " + (@($script:MR.problemy) -join "; ") } else { "kierownik nie jest wlaczony" }
    Zakoncz (-not $rej.blad) $kom @{ zainstalowany = $st.Zainstalowany; dziala = $st.Dziala; szczegoly = $st.Szczegoly; rejestr = (Rejestr-Do-Wyniku $rej $KatalogDomowy) }
  }

  $rej = Rejestr-Do-Zmian $KatalogDomowy

  if ($Akcja -eq "Instaluj") {
    $prog = Sprawdz-Programy @("node") @("bash")
    Odmowa-Brak-Programow
    if (-not $prog["bash"]) { Ostrzezenie "nie widze Git Bash - hooki Claude Code chodza przez bash" }
    $a = @("-Zrodlo", $Zrodlo, "-KatalogDomowy", $KatalogDomowy, "-BezPytania")
    if ($rej.narzedzia -and $rej.narzedzia.codex) { $a += "-Codex"; Krok "rejestr mowi, ze uzywasz Codeksa - role i rejestr dostanie tez Codex" }
    if ($Proba) { $a += "-Proba" }
    # Rejestr PRZED instaluj-globalnie.ps1: ten wola straznika (-NaprawGlobalne), a straznik od P59a
    # kladzie hooki rejestru START/KONIEC i ladunek tylko przy kierowniku wlaczonym w rejestrze - bez
    # tego samosprawdzenie instaluj-globalnie widzialoby braki. Porazka = rejestr wraca do stanu sprzed.
    $bylWlaczony = [bool]$rej.moduly.kierownik
    Zapisz-Modul "kierownik" $true $KatalogDomowy
    $w = Uruchom-Skrypt $Globalnie $a 300
    if ($Proba) {
      # samosprawdzenie instaluj-globalnie.ps1 chodzi takze na probie i widzi wtedy braki tego, czego
      # proba celowo nie zalozyla - jego kod 1 nic tu nie znaczy
      Plan "zasady kierownika, role agentow, rejestr START/KONIEC i przypomnienie (instaluj-globalnie.ps1 -Proba)"
    } else {
      Przekaz-Uwagi $w.Tekst "instaluj-globalnie"
      if ($w.Kod -ne 0) {
        if (-not $bylWlaczony) {
          try { Zapisz-Modul "kierownik" $false $KatalogDomowy; [void](Po-Zmianie-Rejestru $Zrodlo $KatalogDomowy) }
          catch { Ostrzezenie "nie udalo sie cofnac wpisu w rejestrze: $($_.Exception.Message)" }
        }
        Zakoncz $false "tryb kierownika nie stanal: $(Sedno $w.Tekst)"
      }
      Krok "zasady kierownika, role agentow, rejestr START/KONIEC i przypomnienie na miejscu (instaluj-globalnie.ps1)"
    }
    $ok = Po-Zmianie-Rejestru $Zrodlo $KatalogDomowy
    if ($Proba) { Zakoncz $true "proba: kierownik dalby sie zainstalowac" }
    $rej2 = Czytaj-Instalacje $KatalogDomowy
    $st = Zbierz-Stan $rej2 $prog
    $kom = if (-not $ok) { "kierownik zainstalowany, ale hooki albo zasady nie zostaly uaktualnione wedlug rejestru" } elseif ($st.Dziala) { "kierownik zainstalowany - zamknij i otworz okna narzedzi" } else { "kierownik zainstalowany; do sprawdzenia: " + (@($script:MR.problemy) -join "; ") }
    Zakoncz $ok $kom @{ zainstalowany = $st.Zainstalowany; dziala = $st.Dziala; szczegoly = $st.Szczegoly; rejestr = (Rejestr-Do-Wyniku $rej2 $KatalogDomowy) }
  }

  # ---------------------------------------------------------------- Usun
  $a = @("-Zrodlo", $Zrodlo, "-KatalogDomowy", $KatalogDomowy, "-Usun")
  if ($Proba) { $a += "-Proba" }
  $w = Uruchom-Skrypt $Globalnie $a 300
  Przekaz-Uwagi $w.Tekst "instaluj-globalnie"
  if ($w.Kod -ne 0) { Zakoncz $false "nie udalo sie zdjac trybu kierownika: $(Sedno $w.Tekst)" }
  if ($Proba) { Plan "zasady kierownika, role, rejestr workerow i znacznik zdjete (instaluj-globalnie.ps1 -Usun)" }
  else { Krok "zdjete: zasady kierownika, role Claude Code i opencode, rejestr workerow, znacznik instalacji (instaluj-globalnie.ps1 -Usun)" }
  $ok = Usun-Z-Codeksa
  Krok "klucz 'worktree' w ~\.claude\settings.json zostaje - mogl byc ustawiony przez Ciebie"
  Zapisz-Modul "kierownik" $false $KatalogDomowy
  if (-not (Po-Zmianie-Rejestru $Zrodlo $KatalogDomowy)) { $ok = $false }
  # Pliki wolane przez hooki kierownika - PO ulozeniu hookow wedlug rejestru. Straznik ich juz nie
  # dogrywa, ale sam nie kasuje; bez nich zostajacy bez node'a "|| cat <ladunek>" w hooku przypomnienia
  # nie wypisze juz zasad kierownika (P59a).
  foreach ($p in @($Ladunek, $RejestrJs)) {
    if (-not (Test-Path -LiteralPath $p)) { continue }
    if ($Proba) { Plan "usunalbym $p"; continue }
    try { Remove-Item -LiteralPath $p -Force -ErrorAction Stop; Krok "usuniety plik kierownika $p" }
    catch { $ok = $false; Ostrzezenie "nie udalo sie usunac $p : $($_.Exception.Message)" }
  }
  if ($UsunDane) { Krok "modul kierownik nie trzyma Twoich danych w katalogu domowym (rejestr i mapa zostaja w projektach, w .megaruchacz\)" }
  if ($Proba) { Zakoncz $ok "proba: kierownik dalby sie usunac" }
  $kom = if ($ok) { "kierownik wylaczony - zamknij i otworz okna narzedzi" } else { "kierownik wylaczony, ale nie wszystko udalo sie zdjac - szczegoly w uwagach" }
  Zakoncz $ok $kom @{ zainstalowany = $false; dziala = $false; rejestr = (Rejestr-Do-Wyniku (Czytaj-Instalacje $KatalogDomowy) $KatalogDomowy) }
} catch {
  Zakoncz $false ("nieoczekiwany blad: " + $_.Exception.Message + " (" + $_.InvocationInfo.PositionMessage.Split("`n")[0].Trim() + ")")
}
