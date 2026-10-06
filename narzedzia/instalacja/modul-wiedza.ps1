# narzedzia\instalacja\modul-wiedza.ps1 - modul "wiedza": sekcja "Co wiem" w pliku instrukcji kazdego
# narzedzia AI, ktore tu jest (lista: narzedzia\kierownik-cele.ps1 Narzedzia-AI - ~\.claude\CLAUDE.md,
# ~\.codex\AGENTS.md, ~\.config\opencode\AGENTS.md), katalog ~\.claude\wiedza\ i codzienne czytanie
# rozmow (cykl wiedzy: wylawianie faktow + weryfikacja).
#
# Co zaklada:
#   - rdzen Lore: srodowisko Pythona (uv sync), baze rozmow lore.db i zadanie LoreIndex. Cykl czyta
#     tabele chunks, a wypelnia ja tylko indeks - bez niego nie ma z czego wylawiac. Gdy modul lore
#     jest WYLACZONY, indeks chodzi w trybie "tylko tekst" (lore.index --text-only): bez modelu
#     wektorow (~496 MB) i bez wyszukiwania po sensie - cykl wiedzy wektorow nie uzywa.
#   - szkielet sekcji "## Co wiem" (O uzytkowniku / O firmie / Nad czym pracuje / Jak pracuje /
#     Biezace / Dane referencyjne - puste) w pliku KAZDEGO obecnego narzedzia, ktory jej nie ma; istniejacej
#     nie rusza. Bez niej weryfikacja niczego do tego pliku nie zapisze (verify.py pisze do kazdego pliku
#     z ta sekcja). Sekcja pusta (zakladana albo zastana) dostaje tresc najbogatszej sekcji z plikow
#     narzedzi (kierownik-cele.ps1 Zrodlo-Co-Wiem) - ta sama wiedza w kazdym CLI; sekcji z wpisami nie
#     nadpisuje, rozne sekcje = UWAGA (bez scalania). Plik, ktorego narzedzie jeszcze nie ma, zaczyna sie od Tekst-Startowy (OpenCode - od
#     tresci CLAUDE.md, ktory czytal dotad). Zapis ponad limit narzedzia (Codex 32 KiB) = odmowa z UWAGA.
#     Zadnego narzedzia AI = UWAGA (fakty czekaja w wiedza\kandydaci.md), nie odmowa.
#     Stoi nad PIERWSZYM znacznikiem <!-- MegaRuchacz: (bloki lore, wiedza, kierownik): lore\lore\verify.py
#     (section_bounds, GUARD_PREFIX od P59a) konczy sekcje na "## " albo na kazdym takim znaczniku, wiec
#     fakty nie trafia do srodka zadnego bloku. Bez znacznikow - na koncu pliku (bloki dopisza sie pod nim).
#   - katalog ~\.claude\wiedza\ i pierwsza kopie dzienna plikow pamieci (narzedzia\kopie-dzienne.ps1)
#   - sprawdza, czy jest zalogowane CLI "claude" albo "codex" - wylawianie faktow je wola (kazdy
#     przebieg to tokeny z planu uzytkownika). Brak = UWAGA, nie odmowa.
# Usun: wylacza modul w rejestrze; rdzen Lore (zadanie LoreIndex, srodowisko) zdejmuje tylko wtedy,
#   gdy modul lore tez jest wylaczony. Dane zostaja: wiedza\, "Co wiem", kopie dzienne, lore.db.
#   -UsunDane: wiedza\, kopie dzienne, sekcja "Co wiem" z pliku kazdego narzedzia (kopia obok) i lore.db
#   (gdy lore wylaczony).
#
# Uzycie (umowa wyjscia - naglowek wspolne.ps1):
#   powershell -NoProfile -ExecutionPolicy Bypass -File narzedzia\instalacja\modul-wiedza.ps1
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
. (Join-Path (Split-Path -Parent $PSScriptRoot) "zapis-trwaly.ps1")
# Lista narzedzi AI, szkielet "Co wiem", poczatek pliku i limit - wspolne z wpisz-zasady.ps1 i straznikiem.
. (Join-Path (Split-Path -Parent $PSScriptRoot) "kierownik-cele.ps1")
if (-not $Zrodlo) { $Zrodlo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$s0 = Start-Modul "wiedza" $Akcja ([bool]$Proba) $Zrodlo $KatalogDomowy
$Zrodlo = $s0.Zrodlo; $KatalogDomowy = $s0.KatalogDomowy
Lore-Przygotuj

$Claude    = Join-Path $KatalogDomowy ".claude"
$Wiedza    = Join-Path $Claude "wiedza"
$KopieDz   = Join-Path $Claude "mr\kopie-dzienne"
$StanCyklu = Join-Path $Wiedza ".cykl-stan"
$Naglowek  = "## Co wiem"
$Utf8      = New-Object System.Text.UTF8Encoding($false)
$Utf8Scisly = New-Object System.Text.UTF8Encoding($false, $true)

# Szkielet "Co wiem" (Ma-Co-Wiem, Z-Szkieletem-Co-Wiem - podsekcje DOKLADNIE jak w lore\lore\verify.py)
# lezy w kierownik-cele.ps1: ta sama regula sklada go w wpisz-zasady.ps1 i sprawdza straznik.
function Koniec-Linii([string]$t) { if ($t.Contains("`r`n")) { return "`r`n" } elseif ($t.Contains("`n")) { return "`n" } else { return "`r`n" } }

# Tekst bez sekcji "Co wiem" (do -UsunDane): od naglowka do nastepnego "## " albo znacznika
# MegaRuchacza - nigdy w glab bloku.
function Bez-Co-Wiem([string]$stary) {
  $nl = Koniec-Linii $stary
  $linie = @($stary -split "`r?`n")
  $od = -1; $do = $linie.Count
  for ($i = 0; $i -lt $linie.Count; $i++) {
    $t = $linie[$i].Trim()
    if ($od -lt 0) { if ($t.StartsWith($Naglowek)) { $od = $i }; continue }
    if ($t.StartsWith("## ") -or $t.StartsWith("<!-- MegaRuchacz:")) { $do = $i; break }
  }
  if ($od -lt 0) { return $null }
  $przed = @($linie | Select-Object -First $od)
  $po = @($linie | Select-Object -Skip $do)
  return ((@($przed) + @($po)) -join $nl)
}

function Czytaj-Plik([string]$sciezka) {
  if (-not (Test-Path -LiteralPath $sciezka)) { return "" }
  return [System.IO.File]::ReadAllText($sciezka, $Utf8Scisly)
}

# Stan sekcji "Co wiem" w plikach narzedzi, ktore tu sa: .Brak (pliki bez sekcji), .Bledy (opisy),
# .Cele (lista z Cele-Narzedzi).
function Stan-Co-Wiem {
  $w = [pscustomobject]@{ Cele = @(Cele-Narzedzi $KatalogDomowy); Brak = @(); Bledy = @() }
  foreach ($n in $w.Cele) {
    $tx = $null
    try { $tx = Czytaj-Plik $n.Sciezka } catch { $w.Bledy += "nie umiem odczytac $($n.Sciezka) ($($_.Exception.Message))"; continue }
    if ((Test-Path -LiteralPath $n.Sciezka) -and (Ma-Zera $n.Sciezka)) { $w.Bledy += "$($n.Sciezka) ma bajty 0x00 (uszkodzony zapis) - przywroc: narzedzia\kopie-dzienne.ps1 -Przywroc"; continue }
    if (-not (Ma-Co-Wiem $tx)) { $w.Brak += $n.Sciezka }
  }
  return $w
}

# Zalogowanie poznajemy po plikach, ktore CLI zostawia po logowaniu, i po kluczach w srodowisku -
# bez wolania modelu (to kosztuje tokeny) i bez interaktywnych pytan.
function Zalogowane-Cli([hashtable]$prog) {
  $wynik = @()
  if ($prog["claude"]) {
    $znaki = @()
    if (Test-Path -LiteralPath (Join-Path $Claude ".credentials.json")) { $znaki += ".credentials.json" }
    if ($env:ANTHROPIC_API_KEY -or $env:ANTHROPIC_AUTH_TOKEN) { $znaki += "klucz w srodowisku" }
    $ust = Join-Path $Claude "settings.json"
    if ((Test-Path -LiteralPath $ust) -and ([System.IO.File]::ReadAllText($ust) -match 'ANTHROPIC_(API_KEY|AUTH_TOKEN)')) { $znaki += "klucz w settings.json" }
    $cj = Join-Path $KatalogDomowy ".claude.json"
    if ((Test-Path -LiteralPath $cj) -and ([System.IO.File]::ReadAllText($cj) -match '"oauthAccount"')) { $znaki += "konto w .claude.json" }
    if ($znaki.Count -gt 0) { $wynik += "claude" }
  }
  if ($prog["codex"]) {
    $dc = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $KatalogDomowy ".codex" }
    if ((Test-Path -LiteralPath (Join-Path $dc "auth.json")) -or $env:OPENAI_API_KEY) { $wynik += "codex" }
  }
  return $wynik
}

function Stan-Cyklu {
  if (-not (Test-Path -LiteralPath $StanCyklu)) { return [pscustomobject]@{ Data = $null; Status = $null; Powod = $null } }
  $k = @{}
  foreach ($l in [System.IO.File]::ReadAllLines($StanCyklu)) { $m = [regex]::Match($l, '^\s*([^:]+):\s*(.*)$'); if ($m.Success) { $k[$m.Groups[1].Value.Trim()] = $m.Groups[2].Value.Trim() } }
  return [pscustomobject]@{ Data = $k["data"]; Status = $k["status"]; Powod = $k["powod"] }
}

function Zbierz-Stan($rej, [hashtable]$prog) {
  $zainst = [bool]$rej.moduly.wiedza
  $lore = [bool]$rej.moduly.lore
  $sr = Lore-Srodowisko-Jest
  $ind = Lore-Stan-Indeksu
  $baza = if ($sr) { Lore-Stan-Bazy } else { [pscustomobject]@{ Ok = $false; Jest = (Test-Path $script:Baza); Tryb = $null; Fragmentow = 0; Wektorow = 0; Opis = "" } }
  $scw = Stan-Co-Wiem
  $coWiem = ($scw.Cele.Count -gt 0) -and ($scw.Brak.Count -eq 0) -and ($scw.Bledy.Count -eq 0)
  $cli = @(Zalogowane-Cli $prog)
  $cykl = Stan-Cyklu
  if ($zainst) {
    if (-not $sr) { Problem "nie ma srodowiska Pythona Lore ($($script:Lore)\.venv) - cykl wiedzy nie ruszy" }
    if (-not $ind.Ok) { Problem "indeks rozmow: $($ind.Opis)" }
    elseif ((-not $lore) -and $ind.TylkoTekst -ne $true) { Problem "zadanie $($script:NazwaZadania) chodzi z wektorami, choc modul lore jest wylaczony - pobierze niepotrzebny model (~496 MB)" }
    if (-not $baza.Jest) { Problem "nie ma bazy rozmow $($script:Baza)" }
    foreach ($b in $scw.Bledy) { Problem $b }
    foreach ($b in $scw.Brak) { Problem "w $b nie ma sekcji '$Naglowek' - cykl nie zapisze tam faktow" }
    if ($scw.Cele.Count -eq 0) { Problem "nie widze zadnego narzedzia AI (Claude Code, Codex, OpenCode) - sekcji '$Naglowek' nie ma gdzie trzymac, fakty czekaja w wiedza\kandydaci.md" }
    if (-not (Test-Path -LiteralPath $Wiedza)) { Problem "nie ma katalogu $Wiedza" }
    if ($cli.Count -eq 0) { Problem "nie widze zalogowanego Claude Code ani Codeksa - wylawianie faktow nie ma czym czytac rozmow" }
    if (@("odlozony", "wyzerowane", "nie nadaza") -contains $cykl.Status) { Problem "ostatni cykl wiedzy ($($cykl.Data)): $($cykl.Status)$(if ($cykl.Powod) { ' - ' + $cykl.Powod })" }
  }
  $dziala = $zainst -and ($script:MR.problemy.Count -eq 0)
  return [pscustomobject]@{ Zainstalowany = $zainst; Dziala = $dziala; Szczegoly = [ordered]@{
    srodowisko = $sr; indeks = $ind.Opis; indeks_tylko_tekst = $ind.TylkoTekst; baza = $script:Baza; baza_tryb = $baza.Tryb
    fragmentow = $baza.Fragmentow; wektorow = $baza.Wektorow; co_wiem = $coWiem; wiedza_katalog = (Test-Path -LiteralPath $Wiedza)
    zalogowane_cli = $cli; ostatni_cykl = [ordered]@{ data = $cykl.Data; status = $cykl.Status; powod = $cykl.Powod }
    kopie_dzienne = (Test-Path -LiteralPath (Join-Path $KopieDz "wczoraj")) } }
}

try {
  if ($Akcja -eq "Stan") {
    $prog = Sprawdz-Programy @("uv", "python") @("claude", "codex", "node")
    $rej = Czytaj-Instalacje $KatalogDomowy
    if ($rej.blad) { Problem "rejestr modulow: $($rej.blad)" }
    $st = Zbierz-Stan $rej $prog
    $kom = if ($st.Dziala) { "wiedza dziala" } elseif ($st.Zainstalowany) { "wiedza wlaczona, ale: " + (@($script:MR.problemy) -join "; ") } else { "wiedza nie jest wlaczona" }
    Zakoncz (-not $rej.blad) $kom @{ zainstalowany = $st.Zainstalowany; dziala = $st.Dziala; szczegoly = $st.Szczegoly; rejestr = (Rejestr-Do-Wyniku $rej $KatalogDomowy) }
  }

  $rej = Rejestr-Do-Zmian $KatalogDomowy
  $loreWlaczony = [bool]$rej.moduly.lore

  if ($Akcja -eq "Instaluj") {
    $prog = Sprawdz-Programy @("uv", "python") @("claude", "codex", "node")
    Odmowa-Brak-Programow
    $wyzerowane = Wyzerowane-Pliki $KatalogDomowy
    if ($wyzerowane.Count -gt 0) {
      Zakoncz $false ("nic nie zmieniam: " + (Opis-Wyzerowanych $wyzerowane $KatalogDomowy $Zrodlo))
    }
    # Poczatek pliku kazdego narzedzia - przed czymkolwiek, co kosztuje: plik nie po UTF-8 = odmowa.
    $plany = @()
    foreach ($n in (Cele-Narzedzi $KatalogDomowy)) {
      try { $plany += [pscustomobject]@{ N = $n; Start = (Tekst-Startowy $n $KatalogDomowy); NaDysku = (Czytaj-Plik $n.Sciezka) } }
      catch { Zakoncz $false "nie umiem odczytac $($n.Sciezka) albo pliku, od ktorego sie zaczyna ($($_.Exception.Message)) - nie ruszam go" }
    }

    # 1. rdzen Lore
    $tylkoTekst = -not $loreWlaczony
    try {
      Lore-Zainstaluj-Srodowisko
      Lore-Zapisz-Tryb $tylkoTekst
      Lore-Zaloz-Zadanie-Indeksu $tylkoTekst
    } catch { Zakoncz $false "rdzen Lore nie stanal: $($_.Exception.Message)" }
    if ($tylkoTekst) { Krok "modul lore jest wylaczony - indeks bez modelu wektorow (nie pobieram ~496 MB, wyszukiwania po sensie nie ma)" }
    Lore-Indeksuj-W-Tle $tylkoTekst

    # 2. szkielet "Co wiem" - w pliku kazdego narzedzia AI, ktore tu jest
    if ($plany.Count -eq 0) { Ostrzezenie "nie widze zadnego narzedzia AI (Claude Code, Codex, OpenCode) - sekcji '$Naglowek' nie ma gdzie zalozyc; fakty poczekaja w wiedza\kandydaci.md, a szkielet dolozy straznik, gdy narzedzie sie pojawi" }
    # Pusta sekcja (zakladana albo zastana) - z trescia najbogatszej sekcji z plikow narzedzi.
    $zrodloCw = Zrodlo-Co-Wiem $KatalogDomowy
    foreach ($pl in $plany) {
      $plik = $pl.N.Sciezka
      $nowy = Z-Szkieletem-Co-Wiem $pl.Start.Tekst
      $baza = if ($null -ne $nowy) { $nowy } else { $pl.Start.Tekst }
      $zs = Zasiej-Co-Wiem $pl.N $pl.NaDysku $baza $zrodloCw
      if ($zs.Odmowa) { Ostrzezenie "ODMOWA ZAPISU ($($pl.N.Nazwa)): $($zs.Odmowa)" }
      if ($zs.Zasiew) { $nowy = $zs.Tekst }
      if ($null -eq $nowy) {
        if ($pl.Start.Tekst -ceq $pl.NaDysku) { Krok "sekcja '$Naglowek' juz jest w $plik - zostawiam jak jest" }
        else { Krok "sekcja '$Naglowek' w $plik przyjdzie z poczatkiem pliku ($($pl.Start.Opis)) - zapisze go krok zasad" }
        continue
      }
      $sufit = Ponad-Limit $pl.N $pl.NaDysku $nowy
      if ($sufit) { Ostrzezenie "ODMOWA ZAPISU szkieletu '$Naglowek' ($($pl.N.Nazwa)): $sufit"; continue }
      if ($Proba) {
        if ($zs.Zasiew) { Plan "w ${plik}: $($zs.Zasiew)" } else { Plan "dopisalbym pusty szkielet sekcji '$Naglowek' do $plik (nad blokiem zasad MegaRuchacza)" }
        continue
      }
      if (Test-Path -LiteralPath $plik) {
        $kopia = "$plik.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
        Kopiuj-Trwale $plik $kopia
      }
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $plik) | Out-Null
      Zapisz-Trwale $plik $nowy $Utf8
      if (-not (Ma-Co-Wiem (Czytaj-Plik $plik))) { Zakoncz $false "zapisalem $plik, ale sekcji '$Naglowek' w nim nie widze" }
      if ($zs.Zasiew) {
        if (Pusta-Co-Wiem (Czytaj-Plik $plik)) { Zakoncz $false "zapisalem $plik, ale sekcja '$Naglowek' jest w nim nadal pusta (zasiew nie wszedl)" }
        Krok "w $plik ($($pl.N.Nazwa)): $($zs.Zasiew)"
      }
      else { Krok "w $plik ($($pl.N.Nazwa)) jest pusty szkielet sekcji '$Naglowek' (O uzytkowniku, O firmie, Nad czym pracuje, Jak pracuje, Biezace, Dane referencyjne)" }
    }
    $rozjazd = Rozjazd-Co-Wiem $KatalogDomowy
    if ($rozjazd) { Ostrzezenie $rozjazd }

    # 3. katalog wiedzy i kopie dzienne
    if (Test-Path -LiteralPath $Wiedza) { Krok "katalog wiedzy jest: $Wiedza" }
    elseif ($Proba) { Plan "zalozylbym katalog wiedzy $Wiedza" }
    else { New-Item -ItemType Directory -Force -Path $Wiedza | Out-Null; Krok "zalozony katalog wiedzy: $Wiedza" }
    $a = @("-Rotuj", "-KatalogDomowy", $KatalogDomowy, "-Zrodlo", $Zrodlo)
    if ($Proba) { $a += "-Proba" }
    $w = Uruchom-Skrypt (Join-Path $Zrodlo "narzedzia\kopie-dzienne.ps1") $a 300
    if ($w.Kod -eq 2) { Zakoncz $false "kopie dzienne odmowily - pliki pamieci maja bajty 0x00: $(Sedno $w.Tekst)" }
    if ($w.Kod -ne 0) { Ostrzezenie "kopia dzienna plikow pamieci sie nie udala: $(Sedno $w.Tekst) - cykl sprobuje sam przed pierwszym przebiegiem" }
    else { Krok "kopie dzienne plikow pamieci ($KopieDz): $(Sedno $w.Tekst)" }

    # 4. kto bedzie czytal rozmowy
    $cli = @(Zalogowane-Cli $prog)
    if ($cli.Count -gt 0) { Krok "wylawianie faktow uzyje: $($cli -join ' albo ') (jedno wywolanie modelu na dzienny przebieg - tokeny z Twojego planu)" }
    elseif ($prog["claude"] -or $prog["codex"]) { Ostrzezenie "jest CLI $((@('claude','codex') | Where-Object { $prog[$_] }) -join '/'), ale nie widze zalogowania - zaloguj sie (claude: /login, codex: codex login), inaczej cykl wiedzy bedzie odkladany" }
    else { Ostrzezenie "nie ma ani Claude Code (claude), ani Codeksa (codex) - wylawianie faktow nie ma czym czytac rozmow; cykl bedzie odkladany do czasu instalacji jednego z nich" }
    if (-not $prog["node"]) { Ostrzezenie "bez Node.js nie zobaczysz w rozmowie linii o postepie cyklu (hook przypomnienie.js)" }
    if ((Policz-Hooki (Join-Path $Claude "settings.json") "SessionStart" 'straznik-zasad\.ps1') -le 0) {
      Ostrzezenie "nie widze modulu baza (hooka straznika) - cykl wiedzy rusza przy pierwszej sesji dnia i z nadzorcy; zainstaluj najpierw baze"
    }

    # 5. rejestr i zasady dla AI
    Zapisz-Modul "wiedza" $true $KatalogDomowy
    $zasadyOk = Po-Zmianie-Rejestru $Zrodlo $KatalogDomowy
    if ($Proba) { Zakoncz $true "proba: wiedza dalaby sie zainstalowac" }
    $rej2 = Czytaj-Instalacje $KatalogDomowy
    $st = Zbierz-Stan $rej2 $prog
    $kom = if (-not $zasadyOk) { "wiedza zainstalowana, ale hooki albo zasady dla AI nie zostaly uaktualnione wedlug rejestru" } elseif ($st.Dziala) { "wiedza zainstalowana" } else { "wiedza zainstalowana; do sprawdzenia: " + (@($script:MR.problemy) -join "; ") }
    Zakoncz $zasadyOk $kom @{ zainstalowany = $st.Zainstalowany; dziala = $st.Dziala; szczegoly = $st.Szczegoly; rejestr = (Rejestr-Do-Wyniku $rej2 $KatalogDomowy) }
  }

  # ---------------------------------------------------------------- Usun
  $ok = $true
  if ($loreWlaczony) {
    Krok "rdzen Lore (srodowisko, baza, zadanie $($script:NazwaZadania)) zostaje - uzywa go modul lore"
  } else {
    try { Lore-Usun-Zadanie-Indeksu } catch { $ok = $false; Ostrzezenie $_.Exception.Message }
    if (-not (Lore-Usun-Srodowisko)) { $ok = $false }
  }
  Zapisz-Modul "wiedza" $false $KatalogDomowy
  if (-not (Po-Zmianie-Rejestru $Zrodlo $KatalogDomowy)) { $ok = $false }

  if ($UsunDane) {
    if (-not (Usun-Katalog-Danych $Wiedza "katalog wiedzy")) { $ok = $false }
    if (-not (Usun-Katalog-Danych $KopieDz "kopie dzienne plikow pamieci")) { $ok = $false }
    foreach ($nz in (Narzedzia-AI)) {
      $plikN = Join-Path $KatalogDomowy $nz.Plik
      if (-not (Test-Path -LiteralPath $plikN)) { continue }
      $cm = $null
      try { $cm = Czytaj-Plik $plikN } catch { $ok = $false; Ostrzezenie "nie umiem odczytac $plikN ($($_.Exception.Message)) - sekcji '$Naglowek' nie ruszam" }
      if ($null -eq $cm) { continue }
      $bez = Bez-Co-Wiem $cm
      if ($null -eq $bez) { Krok "sekcji '$Naglowek' w $plikN nie ma" }
      elseif (Ma-Zera $plikN) { $ok = $false; Ostrzezenie "$plikN ma bajty 0x00 - nie ruszam go" }
      elseif ($Proba) { Plan "wycialbym sekcje '$Naglowek' z $plikN (kopia obok)" }
      else {
        $kopia = "$plikN.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
        Kopiuj-Trwale $plikN $kopia
        Zapisz-Trwale $plikN $bez $Utf8
        Krok "wycieta sekcja '$Naglowek' z $plikN (poprzednia wersja: $kopia)"
      }
    }
    if ($loreWlaczony) { Krok "baza rozmow zostaje - uzywa jej modul lore" }
    elseif (-not (Lore-Usun-Dane)) { $ok = $false }
  } else {
    Krok "zostaja Twoje dane: $Wiedza, sekcja '$Naglowek', kopie dzienne i baza rozmow (usunie je -UsunDane)"
  }
  if ($Proba) { Zakoncz $ok "proba: wiedza dalaby sie usunac" }
  $kom = if ($ok) { "wiedza wylaczona" } else { "wiedza wylaczona, ale nie wszystko udalo sie zdjac - szczegoly w uwagach" }
  Zakoncz $ok $kom @{ zainstalowany = $false; dziala = $false; rejestr = (Rejestr-Do-Wyniku (Czytaj-Instalacje $KatalogDomowy) $KatalogDomowy) }
} catch {
  Zakoncz $false ("nieoczekiwany blad: " + $_.Exception.Message + " (" + $_.InvocationInfo.PositionMessage.Split("`n")[0].Trim() + ")")
}
