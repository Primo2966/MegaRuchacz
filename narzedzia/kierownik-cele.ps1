# Wspolne dla instaluj-globalnie.ps1 i straznik-zasad.ps1 (dolaczane kropka):
# ktore pliki instrukcji dostaja blok zasad kierownika i w jakim wariancie.
#
#   ~/.claude/CLAUDE.md           wariant Claude Code, gdy Claude Code na maszynie
#                                 pracuje; inaczej wariant opencode/Codex
#   ~/.codex/AGENTS.md            wariant opencode/Codex
#   ~/.config/opencode/AGENTS.md  KOPIA ~/.claude/CLAUDE.md z blokiem w wariancie
#                                 opencode/Codex (patrz Kopia-Dla-Opencode)
#
# Orka (orca) uruchamia Codeksa z wlasnym CODEX_HOME
# (%APPDATA%\orca\codex-runtime-home\home). Przy KAZDYM starcie Codeksa w Orce
# sama przenosi tam z ~/.codex: AGENTS.md, skills, hooks (katalog), plugins,
# plugin-state, profile-v2, themes, prompts - dowiazaniem albo kopia, ktora
# odswieza, gdy sie rozni (kod Orki 1.4.210: out/main/chunks/codex-home-paths-*.js,
# funkcja wolana z prepareForCodexLaunch). Dlatego do katalogu Orki NIC nie
# piszemy: wystarczy ~/.codex/AGENTS.md. Wlasny plik w katalogu Orki
# zablokowalby to kopiowanie na zawsze (Orka nie nadpisuje pliku, ktorego sama
# nie zalozyla). hooks.json Orka NIE przenosi - hooki rejestru z ~/.codex pod
# Orka nie chodza.

$KIEROWNIK_POCZATEK = "<!-- MegaRuchacz:kierownik:start -->"
$KIEROWNIK_KONIEC   = "<!-- MegaRuchacz:kierownik:koniec -->"
$KOPIA_OPENCODE_ZNACZNIK = "<!-- MegaRuchacz:kopia-dla-opencode"

function Katalog-Codex-Orki($dom) {
  $p = Join-Path $dom "AppData\Roaming\orca\codex-runtime-home\home"
  if (Test-Path $p) { return $p }
  return $null
}

# Claude Code poznajemy po plikach, ktore prowadzi sam - katalog ~\.claude zaklada
# tez MegaRuchacz (Lore, wiedza). To samo rozroznienie co w instalatorze.
function Pracuje-Claude($dom) {
  return (Test-Path (Join-Path $dom ".claude\history.jsonl")) -or (Test-Path (Join-Path $dom ".claude.json"))
}

function Czytaj-Utf8($sciezka) {
  return [System.IO.File]::ReadAllText($sciezka, (New-Object System.Text.UTF8Encoding($false, $true)))
}

function Ile-Blokow-Kierownika([string]$tekst) {
  if (-not $tekst) { return 0 }
  return ([regex]::Matches($tekst, [regex]::Escape($KIEROWNIK_POCZATEK))).Count
}

# Tresc bloku kierownika (bez znacznikow) albo $null.
function Blok-Kierownika([string]$tekst) {
  if (-not $tekst) { return $null }
  $i = $tekst.IndexOf($KIEROWNIK_POCZATEK, [System.StringComparison]::Ordinal)
  $j = $tekst.IndexOf($KIEROWNIK_KONIEC, [System.StringComparison]::Ordinal)
  if ($i -lt 0 -or $j -lt $i) { return $null }
  return $tekst.Substring($i + $KIEROWNIK_POCZATEK.Length, $j - $i - $KIEROWNIK_POCZATEK.Length)
}

# Tekst pliku z blokiem kierownika o podanej tresci: podmiana jedynego bloku albo
# dopisanie na koncu. Konce linii bloku jak w reszcie pliku. Dubel albo samotny
# znacznik = wyjatek - tego nie naprawiamy po cichu.
function Z-Blokiem-Kierownika([string]$stary, [string]$tresc) {
  if ($null -eq $stary) { $stary = "" }
  $nl = if ($stary.Contains("`r`n")) { "`r`n" } else { "`n" }
  $t = $tresc.Trim() -replace "`r`n", "`n"
  if ($nl -eq "`r`n") { $t = $t -replace "`n", "`r`n" }
  $blok = ($KIEROWNIK_POCZATEK, $t, $KIEROWNIK_KONIEC) -join $nl
  $ile = Ile-Blokow-Kierownika $stary
  if ($ile -gt 1) { throw "jest $ile blokow kierownika (dubel)" }
  $i = $stary.IndexOf($KIEROWNIK_POCZATEK, [System.StringComparison]::Ordinal)
  $j = $stary.IndexOf($KIEROWNIK_KONIEC, [System.StringComparison]::Ordinal)
  if (($i -ge 0) -xor ($j -ge 0)) { throw "jest tylko jeden znacznik bloku kierownika" }
  if ($i -ge 0) { return $stary.Substring(0, $i) + $blok + $stary.Substring($j + $KIEROWNIK_KONIEC.Length) }
  if ($stary.Trim().Length -eq 0) { return $blok + $nl }
  return $stary.TrimEnd("`r", "`n") + $nl + $nl + $blok + $nl
}

# Tekst pliku bez bloku kierownika (modul kierownik wylaczony w rejestrze instalacji): blok
# wyciety razem ze znacznikami, bez podwojnej pustej linii po nim. Brak bloku = tekst bez zmian;
# dubel albo samotny znacznik = wyjatek - tego nie naprawiamy po cichu.
function Bez-Bloku-Kierownika([string]$stary) {
  if ($null -eq $stary) { return "" }
  $ile = Ile-Blokow-Kierownika $stary
  if ($ile -gt 1) { throw "jest $ile blokow kierownika (dubel)" }
  $i = $stary.IndexOf($KIEROWNIK_POCZATEK, [System.StringComparison]::Ordinal)
  $j = $stary.IndexOf($KIEROWNIK_KONIEC, [System.StringComparison]::Ordinal)
  if (($i -ge 0) -xor ($j -ge 0)) { throw "jest tylko jeden znacznik bloku kierownika" }
  if ($i -lt 0) { return $stary }
  if ($j -lt $i) { throw "znaczniki bloku kierownika stoja w zlej kolejnosci" }
  $nl = if ($stary.Contains("`r`n")) { "`r`n" } else { "`n" }
  $przed = $stary.Substring(0, $i).TrimEnd("`r", "`n")
  $po = $stary.Substring($j + $KIEROWNIK_KONIEC.Length).TrimStart("`r", "`n")
  if ($przed.Length -eq 0) { return $po }
  if ($po.Length -eq 0) { return $przed + $nl }
  return $przed + $nl + $nl + $po
}

# opencode czyta globalnie PIERWSZY istniejacy z ~/.config/opencode/AGENTS.md
# i ~/.claude/CLAUDE.md (docs: opencode.ai/docs/rules). Pole "instructions" tylko
# DOKLADA pliki, a dolozenie CLAUDE.md wnioslo by wariant Claude Code. Jedyna droga
# do "Co wiem" + bloku Lore + wlasciwego wariantu naraz: wlasny AGENTS.md opencode
# bedacy kopia CLAUDE.md z podmienionym blokiem kierownika. Kopie odswieza straznik
# przy kazdym starcie sesji (Claude Code - hook SessionStart, opencode - wtyczka
# mr-log.js), bo "Co wiem" zmienia sie codziennie.
function Kopia-Dla-Opencode([string]$claudeTekst, [string]$trescOpencode) {
  $nl = if ($claudeTekst.Contains("`r`n")) { "`r`n" } else { "`n" }
  $naglowek = "$KOPIA_OPENCODE_ZNACZNIK - plik zaklada i odswieza MegaRuchacz (narzedzia\straznik-zasad.ps1): kopia ~/.claude/CLAUDE.md z zasadami kierownika w wariancie dla opencode. Nie edytuj - zmieniaj ~/.claude/CLAUDE.md. -->"
  return $naglowek + $nl + $nl + (Z-Blokiem-Kierownika $claudeTekst $trescOpencode)
}

function Jest-Kopia-Opencode($sciezka) {
  if (-not (Test-Path $sciezka)) { return $false }
  try { return (Czytaj-Utf8 $sciezka).StartsWith($KOPIA_OPENCODE_ZNACZNIK) } catch { return $false }
}
