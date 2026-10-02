# narzedzia\instalacja\modul-wiedza.ps1 - modul "wiedza": sekcja "Co wiem" w ~\.claude\CLAUDE.md,
# katalog ~\.claude\wiedza\ i codzienne czytanie rozmow (cykl wiedzy: wylawianie faktow + weryfikacja).
#
# Co zaklada:
#   - rdzen Lore: srodowisko Pythona (uv sync), baze rozmow lore.db i zadanie LoreIndex. Cykl czyta
#     tabele chunks, a wypelnia ja tylko indeks - bez niego nie ma z czego wylawiac. Gdy modul lore
#     jest WYLACZONY, indeks chodzi w trybie "tylko tekst" (lore.index --text-only): bez modelu
#     wektorow (~496 MB) i bez wyszukiwania po sensie - cykl wiedzy wektorow nie uzywa.
#   - szkielet sekcji "## Co wiem" (O uzytkowniku / O firmie / Nad czym pracuje / Jak pracuje /
#     Biezace / Dane referencyjne - puste), jesli jej nie ma. Bez niej weryfikacja niczego nie zapisze.
#     Stoi zawsze TUZ nad blokiem <!-- MegaRuchacz:start --> (granica sekcji w lore\lore\verify.py):
#     przed blokiem kierownika granicy nie ma i fakty moglyby trafic do jego srodka. Gdy bloku
#     MegaRuchacz:start jeszcze nie ma, szkielet dostaje pusty blok, ktory wpisz-zasady.ps1 wypelnia
#     w miejscu (dopisalby go inaczej na koncu pliku, za blokiem kierownika).
#   - katalog ~\.claude\wiedza\ i pierwsza kopie dzienna plikow pamieci (narzedzia\kopie-dzienne.ps1)
#   - sprawdza, czy jest zalogowane CLI "claude" albo "codex" - wylawianie faktow je wola (kazdy
#     przebieg to tokeny z planu uzytkownika). Brak = UWAGA, nie odmowa.
# Usun: wylacza modul w rejestrze; rdzen Lore (zadanie LoreIndex, srodowisko) zdejmuje tylko wtedy,
#   gdy modul lore tez jest wylaczony. Dane zostaja: wiedza\, "Co wiem", kopie dzienne, lore.db.
#   -UsunDane: wiedza\, kopie dzienne, sekcja "Co wiem" (kopia CLAUDE.md obok) i lore.db (gdy lore wylaczony).
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
if (-not $Zrodlo) { $Zrodlo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$s0 = Start-Modul "wiedza" $Akcja ([bool]$Proba) $Zrodlo $KatalogDomowy
$Zrodlo = $s0.Zrodlo; $KatalogDomowy = $s0.KatalogDomowy
Lore-Przygotuj

$Claude    = Join-Path $KatalogDomowy ".claude"
$PlikCm    = Join-Path $Claude "CLAUDE.md"
$Wiedza    = Join-Path $Claude "wiedza"
$KopieDz   = Join-Path $Claude "mr\kopie-dzienne"
$StanCyklu = Join-Path $Wiedza ".cykl-stan"
$Naglowek  = "## Co wiem"
$Granica   = "<!-- MegaRuchacz:start -->"
$GranicaK  = "<!-- MegaRuchacz:koniec -->"
$Utf8      = New-Object System.Text.UTF8Encoding($false)
$Utf8Scisly = New-Object System.Text.UTF8Encoding($false, $true)

# Podsekcje "Co wiem" - DOKLADNIE te same naglowki co w lore\lore\verify.py (STABLE_SUBSECTIONS,
# CURRENT_SUBSECTION, REFERENCE_SUBSECTION). Polskie litery skladane ze znakow - plik zostaje ASCII.
$zz = [char]0x017C; $aa = [char]0x0105
$Podsekcje = @("### O u${zz}ytkowniku", "### O firmie", "### Nad czym pracuje", "### Jak pracuje", "### Bie${zz}${aa}ce", "### Dane referencyjne")

function Koniec-Linii([string]$t) { if ($t.Contains("`r`n")) { return "`r`n" } elseif ($t.Contains("`n")) { return "`n" } else { return "`r`n" } }

function Ma-Co-Wiem([string]$tekst) {
  foreach ($l in ($tekst -split "`r?`n")) { if ($l.Trim().StartsWith($Naglowek)) { return $true } }
  return $false
}

# Tekst CLAUDE.md po dolozeniu szkieletu (albo $null, gdy sekcja juz jest).
function Z-Szkieletem([string]$stary) {
  if (Ma-Co-Wiem $stary) { return $null }
  $nl = Koniec-Linii $stary
  $szkielet = (@($Naglowek, "") + @($Podsekcje | ForEach-Object { $_, "" })) -join $nl
  $linie = [System.Collections.Generic.List[string]]@($stary -split "`r?`n")
  $iStart = -1; $iPierwszy = -1
  for ($i = 0; $i -lt $linie.Count; $i++) {
    $t = $linie[$i].Trim()
    if ($iStart -lt 0 -and $t -eq $Granica) { $iStart = $i }
    if ($iPierwszy -lt 0 -and $t.StartsWith("<!-- MegaRuchacz:")) { $iPierwszy = $i }
  }
  if ($iStart -ge 0) {
    # tuz nad blokiem zasad: verify.py konczy sekcje na tym znaczniku
    $przed = (@($linie | Select-Object -First $iStart) -join $nl).TrimEnd()
    $po = @($linie | Select-Object -Skip $iStart) -join $nl
    $sklejka = if ($przed) { $przed + $nl + $nl } else { "" }
    return ($sklejka + $szkielet + $po)
  }
  # bloku zasad jeszcze nie ma: szkielet + pusty blok (wpisz-zasady wypelni go w tym miejscu)
  $blok = $Granica + $nl + $GranicaK
  if ($iPierwszy -ge 0) {
    $przed = (@($linie | Select-Object -First $iPierwszy) -join $nl).TrimEnd()
    $po = @($linie | Select-Object -Skip $iPierwszy) -join $nl
    $sklejka = if ($przed) { $przed + $nl + $nl } else { "" }
    return ($sklejka + $szkielet + $blok + $nl + $nl + $po)
  }
  $cialo = $stary.TrimEnd()
  if (-not $cialo) { $cialo = "# Ustalenia globalne" }
  return ($cialo + $nl + $nl + $szkielet + $blok + $nl)
}

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

function Czytaj-Cm {
  if (-not (Test-Path -LiteralPath $PlikCm)) { return "" }
  return [System.IO.File]::ReadAllText($PlikCm, $Utf8Scisly)
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
  $cm = ""
  $cmBlad = $null
  try { $cm = Czytaj-Cm } catch { $cmBlad = $_.Exception.Message }
  $coWiem = (-not $cmBlad) -and (Ma-Co-Wiem $cm)
  $cli = @(Zalogowane-Cli $prog)
  $cykl = Stan-Cyklu
  if ($zainst) {
    if (-not $sr) { Problem "nie ma srodowiska Pythona Lore ($($script:Lore)\.venv) - cykl wiedzy nie ruszy" }
    if (-not $ind.Ok) { Problem "indeks rozmow: $($ind.Opis)" }
    elseif ((-not $lore) -and $ind.TylkoTekst -ne $true) { Problem "zadanie $($script:NazwaZadania) chodzi z wektorami, choc modul lore jest wylaczony - pobierze niepotrzebny model (~496 MB)" }
    if (-not $baza.Jest) { Problem "nie ma bazy rozmow $($script:Baza)" }
    if ($cmBlad) { Problem "nie umiem odczytac $PlikCm ($cmBlad)" }
    elseif (Ma-Zera $PlikCm) { Problem "$PlikCm ma bajty 0x00 (uszkodzony zapis) - przywroc: narzedzia\kopie-dzienne.ps1 -Przywroc" }
    elseif (-not $coWiem) { Problem "w $PlikCm nie ma sekcji '$Naglowek' - cykl nie ma gdzie zapisywac faktow" }
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
    $cm = $null
    try { $cm = Czytaj-Cm } catch { Zakoncz $false "nie umiem odczytac $PlikCm jako UTF-8 ($($_.Exception.Message)) - nie ruszam go" }

    # 1. rdzen Lore
    $tylkoTekst = -not $loreWlaczony
    try {
      Lore-Zainstaluj-Srodowisko
      Lore-Zapisz-Tryb $tylkoTekst
      Lore-Zaloz-Zadanie-Indeksu $tylkoTekst
    } catch { Zakoncz $false "rdzen Lore nie stanal: $($_.Exception.Message)" }
    if ($tylkoTekst) { Krok "modul lore jest wylaczony - indeks bez modelu wektorow (nie pobieram ~496 MB, wyszukiwania po sensie nie ma)" }
    Lore-Indeksuj-W-Tle $tylkoTekst

    # 2. szkielet "Co wiem"
    $nowy = Z-Szkieletem $cm
    if ($null -eq $nowy) { Krok "sekcja '$Naglowek' juz jest w $PlikCm - zostawiam jak jest" }
    elseif ($Proba) { Plan "dopisalbym pusty szkielet sekcji '$Naglowek' do $PlikCm (nad blokiem zasad MegaRuchacza)" }
    else {
      if (Test-Path -LiteralPath $PlikCm) {
        $kopia = "$PlikCm.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
        Kopiuj-Trwale $PlikCm $kopia
      }
      New-Item -ItemType Directory -Force -Path $Claude | Out-Null
      Zapisz-Trwale $PlikCm $nowy $Utf8
      if (-not (Ma-Co-Wiem (Czytaj-Cm))) { Zakoncz $false "zapisalem $PlikCm, ale sekcji '$Naglowek' w nim nie widze" }
      Krok "w $PlikCm jest pusty szkielet sekcji '$Naglowek' (O uzytkowniku, O firmie, Nad czym pracuje, Jak pracuje, Biezace, Dane referencyjne)"
    }

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
    $cm = $null
    try { $cm = Czytaj-Cm } catch { $ok = $false; Ostrzezenie "nie umiem odczytac $PlikCm ($($_.Exception.Message)) - sekcji '$Naglowek' nie ruszam" }
    if ($null -ne $cm) {
      $bez = Bez-Co-Wiem $cm
      if ($null -eq $bez) { Krok "sekcji '$Naglowek' w $PlikCm nie ma" }
      elseif (Ma-Zera $PlikCm) { $ok = $false; Ostrzezenie "$PlikCm ma bajty 0x00 - nie ruszam go" }
      elseif ($Proba) { Plan "wycialbym sekcje '$Naglowek' z $PlikCm (kopia obok)" }
      else {
        $kopia = "$PlikCm.bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
        Kopiuj-Trwale $PlikCm $kopia
        Zapisz-Trwale $PlikCm $bez $Utf8
        Krok "wycieta sekcja '$Naglowek' z $PlikCm (poprzednia wersja: $kopia)"
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
