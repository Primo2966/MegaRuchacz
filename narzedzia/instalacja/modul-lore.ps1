# narzedzia\instalacja\modul-lore.ps1 - modul "lore": przeszukiwalna pamiec wszystkich rozmow
# (baza z wektorami, serwer MCP "lore" z lore_search, podpowiedzi "Z ARCHIWUM").
#
# Co zaklada:
#   - rdzen Lore (jak modul wiedza): srodowisko Pythona, baza lore.db, zadanie LoreIndex - tu
#     z wektorami (bez --text-only)
#   - model wektorow ~496 MB (sdadas/mmlw-retrieval-roberta-base; pobranie jednorazowe z huggingface.co)
#     i probny wektor - dowod, ze model naprawde liczy
#   - serwer MCP "lore" w kazdym narzedziu, ktore jest na maszynie: Claude Code (claude mcp add
#     --scope user), Codex (codex mcp add albo tabela w config.toml), opencode (opencode.json)
#   - wektory dla fragmentow zapisanych wczesniej bez nich (np. przez modul wiedza w trybie
#     "tylko tekst") - lore.migrate w tle; pusta baza dostaje pierwszy pelny przebieg indeksu w tle
#   - na koniec rozmowa z serwerem po MCP (initialize, tools/list, lore_stats)
# Usun: zdejmuje serwer MCP ze wszystkich narzedzi i model wektorow. Rdzen zostaje, gdy wlaczony
#   jest modul wiedza (zadanie LoreIndex przechodzi wtedy w tryb "tylko tekst"); inaczej zadanie
#   i srodowisko tez znikaja. Baza rozmow zostaje; -UsunDane usuwa ja (gdy wiedza wylaczona)
#   i stan podpowiedzi "Z ARCHIWUM".
#
# LORE JEST OBOWIAZKOWE (decyzja uzytkownika 2026-10-17): komputer bez niego dostaje je sam przy
# automatycznej aktualizacji (narzedzia\aktualizuj-megaruchacza.ps1 Doinstaluj-Lore, co godzine).
# Usun poza pelnym odinstalowaniem to konserwacja - aktualizacja przywroci Lore w ciagu godziny.
# BLOKADA: Instaluj i Usun (bez -Proba) ida jeden naraz na katalog zrodlowy (zamek Local\MegaRuchacz-
# lore-<16 znakow md5 sciezki zrodla malymi literami>, ta sama regula co blokada aktualizacji - kopia
# testowa nie zderza sie z prawdziwym repo). Zajety = od razu ok:false, zajete:true, nic nie zmienione:
# nowa instalacja startuje nadzorce przed krokiem Lore, a jego aktualizacja moglaby ruszyc drugi
# Instaluj na tym samym srodowisku i bazie.
#
# Uzycie (umowa wyjscia - naglowek wspolne.ps1):
#   powershell -NoProfile -ExecutionPolicy Bypass -File narzedzia\instalacja\modul-lore.ps1
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
$s0 = Start-Modul "lore" $Akcja ([bool]$Proba) $Zrodlo $KatalogDomowy
$Zrodlo = $s0.Zrodlo; $KatalogDomowy = $s0.KatalogDomowy
Lore-Przygotuj

$StanArchiwum = Join-Path $KatalogDomowy ".claude\wiedza\.archiwum-stan.json"

# Blokada Instaluj/Usun (patrz naglowek). Porzucona (poprzedni przebieg padl, trzymajac ja) jest juz
# nasza - wyjatek bywa owiniety w MethodInvocationException, wiec szukamy go w lancuchu.
$script:BlokadaLore = $null
function Wez-Blokade-Lore {
  $md5 = [System.Security.Cryptography.MD5]::Create()
  try { $skrot = ([System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Zrodlo.ToLower()))).Replace("-", "")).Substring(0, 16) }
  finally { $md5.Dispose() }
  $m = New-Object System.Threading.Mutex($false, ("Local\MegaRuchacz-lore-" + $skrot))
  $mam = $false
  try { $mam = $m.WaitOne(0) }
  catch {
    $wew = $_.Exception
    while ($wew -and -not ($wew -is [System.Threading.AbandonedMutexException])) { $wew = $wew.InnerException }
    if (-not $wew) { $m.Dispose(); throw }
    Ostrzezenie "poprzednia instalacja albo usuwanie Lore przerwaly sie w polowie - przejmuje ich blokade"
    $mam = $true
  }
  if (-not $mam) {
    $m.Dispose()
    Zakoncz $false "Pamiec rozmow (Lore) instaluje albo usuwa inny proces - wroc za kilka minut" @{ zajete = $true }
  }
  $script:BlokadaLore = $m
}
function Oddaj-Blokade-Lore {
  if (-not $script:BlokadaLore) { return }
  try { $script:BlokadaLore.ReleaseMutex() } catch { [Console]::Error.WriteLine("nie oddalem blokady Lore: $($_.Exception.Message)") }
  $script:BlokadaLore.Dispose()
  $script:BlokadaLore = $null
}

function Zbierz-Stan($rej) {
  $zainst = [bool]$rej.moduly.lore
  $sr = Lore-Srodowisko-Jest
  $ind = Lore-Stan-Indeksu
  $model = Lore-Stan-Modelu
  $mcp = @(Lore-Stan-Mcp)
  $wek = if ($sr) { Lore-Stan-Wektorow-Wprost } else { [pscustomobject]@{ Stan = $null; Ostrzezenie = "nie ma srodowiska"; Trwa = $false; Procent = "?" } }
  if ($zainst) {
    if (-not $sr) { Problem "nie ma srodowiska Pythona Lore ($($script:Lore)\.venv)" }
    if (-not $ind.Ok) { Problem "indeks rozmow: $($ind.Opis)" }
    elseif ($ind.TylkoTekst) { Problem "zadanie $($script:NazwaZadania) chodzi w trybie 'tylko tekst' - nowe rozmowy nie dostaja wektorow" }
    if (-not $model.Ok) { Problem "model wektorow: $($model.Opis)" }
    if ($mcp.Count -eq 0) { Problem "serwer MCP $($script:NazwaMcp) nie jest zarejestrowany w zadnym narzedziu" }
    if (-not (Test-Path $script:Baza)) { Problem "nie ma bazy rozmow $($script:Baza)" }
    elseif ($wek.Stan -eq "incomplete" -and -not $wek.Trwa) { Problem "czesc fragmentow nie ma wektorow, a liczenie nie idzie: $($wek.Ostrzezenie)" }
    elseif (@("unknown_model", "text_only") -contains $wek.Stan) { Problem "wektory: $($wek.Stan) - $($wek.Ostrzezenie)" }
    elseif ($wek.Stan -eq "migration_needed" -and -not $wek.Trwa) { Problem "archiwum trzeba przeliczyc na nowy model, a przeliczanie nie idzie: $(Polecenie-Przeliczania)" }
    elseif ($null -eq $wek.Stan -and $sr) { Problem "nie udalo sie odczytac stanu wektorow: $($wek.Ostrzezenie)" }
  }
  $dziala = $zainst -and ($script:MR.problemy.Count -eq 0)
  return [pscustomobject]@{ Zainstalowany = $zainst; Dziala = $dziala; Szczegoly = [ordered]@{
    srodowisko = $sr; indeks = $ind.Opis; indeks_tylko_tekst = $ind.TylkoTekst; model = $model.Opis; mcp = $mcp
    baza = $script:Baza; wektory = $wek.Stan; wektory_opis = $wek.Ostrzezenie; przeliczanie_trwa = $wek.Trwa } }
}

try {
  # Blokada PRZED wszystkim innym (takze przed wykrywaniem narzedzi, ktore wola programy) - zajety
  # przebieg konczy sie, niczego nie dotykajac. Stan i -Proba niczego nie zmieniaja, wiec bez blokady.
  if (($Akcja -ne "Stan") -and -not $Proba) { Wez-Blokade-Lore }
  Lore-Wykryj-Narzedzia

  if ($Akcja -eq "Stan") {
    [void](Sprawdz-Programy @("uv", "python") @("claude", "codex", "opencode", "node"))
    $rej = Czytaj-Instalacje $KatalogDomowy
    if ($rej.blad) { Problem "rejestr modulow: $($rej.blad)" }
    $st = Zbierz-Stan $rej
    # Lore obowiazkowe: przy braku komunikat mowi, ze to brak do uzupelnienia (zrobi to aktualizacja) -
    # poza odinstalowanym MegaRuchaczem ("baza": false), gdzie nic nie wraca samo.
    $kom = if ($st.Dziala) { "lore dziala" } elseif ($st.Zainstalowany) { "lore wlaczone, ale: " + (@($script:MR.problemy) -join "; ") }
           elseif ((-not $rej.blad) -and ($rej.baza -eq $false)) { "lore nie jest zainstalowane (MegaRuchacz jest odinstalowany na tym komputerze)" }
           else { "lore nie jest zainstalowane - to modul obowiazkowy, doinstaluje go aktualizacja" }
    Zakoncz (-not $rej.blad) $kom @{ zainstalowany = $st.Zainstalowany; dziala = $st.Dziala; szczegoly = $st.Szczegoly; rejestr = (Rejestr-Do-Wyniku $rej $KatalogDomowy) }
  }

  $rej = Rejestr-Do-Zmian $KatalogDomowy
  $wiedzaWlaczona = [bool]$rej.moduly.wiedza

  if ($Akcja -eq "Instaluj") {
    $prog = Sprawdz-Programy @("uv", "python") @("claude", "codex", "opencode", "node")
    Odmowa-Brak-Programow
    if (-not (Lore-Jakiekolwiek-Narzedzie)) {
      Zakoncz $false "nie ma narzedzia, w ktorym moglbym zarejestrowac serwer lore - ani Claude Code, ani Codeksa, ani opencode. Zainstaluj jedno z nich i uruchom instalacje jeszcze raz."
    }
    try {
      Lore-Zainstaluj-Srodowisko
      Lore-Zapisz-Tryb $false
      Lore-Zaloz-Zadanie-Indeksu $false
      Lore-Pobierz-Model
      $gdzie = @(Lore-Zarejestruj-Mcp)
    } catch { Zakoncz $false "lore nie stanelo: $($_.Exception.Message)" }
    Krok "od teraz agent AI ma dostep do tresci wszystkich Twoich rozmow z tej maszyny (wszystkie projekty i okna) - baza, model i wyszukiwanie zostaja lokalnie"

    # wektory: pusta baza -> pierwszy pelny przebieg; fragmenty bez wektora -> liczenie w tle
    if (-not $Proba) {
      $baza = Lore-Stan-Bazy
      if ($baza.Ok -and $baza.Fragmentow -eq 0) { Lore-Indeksuj-W-Tle $false }
      else { [void](Lore-Uruchom-Przeliczanie) }
      $probaMcp = Lore-Sprawdz-Mcp-Dziala
      if ($probaMcp.Ok) { Krok "serwer $($script:NazwaMcp) odpowiada na wywolanie MCP ($($probaMcp.Opis)) - otworz okna narzedzi na nowo, zeby go podpiely" }
      else { Zakoncz $false "serwer $($script:NazwaMcp) zarejestrowany, ale nie odpowiada: $($probaMcp.Opis)" }
    } else {
      Plan "wektory dla starszych fragmentow liczone w tle (lore.migrate), potem rozmowa z serwerem po MCP"
    }
    if (-not $prog["node"]) { Ostrzezenie "bez Node.js nie bedzie podpowiedzi 'Z ARCHIWUM' w rozmowie (hook przypomnienie.js)" }

    Zapisz-Modul "lore" $true $KatalogDomowy
    $zasadyOk = Po-Zmianie-Rejestru $Zrodlo $KatalogDomowy
    if ($Proba) { Zakoncz $true "proba: lore daloby sie zainstalowac" }
    $rej2 = Czytaj-Instalacje $KatalogDomowy
    $st = Zbierz-Stan $rej2
    $kom = if (-not $zasadyOk) { "lore zainstalowane, ale hooki albo zasady dla AI nie zostaly uaktualnione wedlug rejestru" } elseif ($st.Dziala) { "lore zainstalowane" } else { "lore zainstalowane; do sprawdzenia: " + (@($script:MR.problemy) -join "; ") }
    Zakoncz $zasadyOk $kom @{ zainstalowany = $st.Zainstalowany; dziala = $st.Dziala; szczegoly = $st.Szczegoly; mcp = $gdzie; rejestr = (Rejestr-Do-Wyniku $rej2 $KatalogDomowy) }
  }

  # ---------------------------------------------------------------- Usun
  # Serwer MCP najpierw i bez niego dalej nie idziemy: dopoki jest zarejestrowany, agent
  # dalej siega do rozmow - rejestr nie moze mowic "wylaczone".
  try { Lore-Wyrejestruj-Mcp } catch { Zakoncz $false "nie zdjalem serwera MCP, wiec lore zostaje wlaczone: $($_.Exception.Message)" }
  $ok = $true
  if (-not (Lore-Usun-Model)) { $ok = $false }
  if ($wiedzaWlaczona) {
    if (Lore-Srodowisko-Jest) {
      try {
        Lore-Zapisz-Tryb $true
        Lore-Zaloz-Zadanie-Indeksu $true
        Krok "rdzen Lore zostaje dla modulu wiedza - indeks przechodzi w tryb 'tylko tekst' (bez modelu)"
      } catch { Zakoncz $false "modul wiedza zostalby z indeksem, ktory pobierze model z powrotem: $($_.Exception.Message)" }
    } else {
      Ostrzezenie "modul wiedza jest wlaczony, a srodowiska Lore nie ma - uruchom: modul-wiedza.ps1 -Akcja Instaluj"
    }
  } else {
    try { Lore-Usun-Zadanie-Indeksu } catch { $ok = $false; Ostrzezenie $_.Exception.Message }
    if (-not (Lore-Usun-Srodowisko)) { $ok = $false }
  }
  Zapisz-Modul "lore" $false $KatalogDomowy
  if (-not (Po-Zmianie-Rejestru $Zrodlo $KatalogDomowy)) { $ok = $false }

  if ($UsunDane) {
    if (-not (Usun-Katalog-Danych $StanArchiwum "stan podpowiedzi 'Z ARCHIWUM'")) { $ok = $false }
    if ($wiedzaWlaczona) { Krok "baza rozmow zostaje - czyta ja cykl modulu wiedza" }
    elseif (-not (Lore-Usun-Dane)) { $ok = $false }
  } else {
    Krok "baza rozmow zostaje ($($script:Baza)) - usunie ja -UsunDane"
  }
  if ($Proba) { Zakoncz $ok "proba: lore daloby sie usunac" }
  $kom = if ($ok) { "lore wylaczone - agent nie siega juz do archiwum rozmow (otwarte okna maja serwer do zamkniecia)" } else { "lore wylaczone, ale nie wszystko udalo sie zdjac - szczegoly w uwagach" }
  Zakoncz $ok $kom @{ zainstalowany = $false; dziala = $false; rejestr = (Rejestr-Do-Wyniku (Czytaj-Instalacje $KatalogDomowy) $KatalogDomowy) }
} catch {
  Zakoncz $false ("nieoczekiwany blad: " + $_.Exception.Message + " (" + $_.InvocationInfo.PositionMessage.Split("`n")[0].Trim() + ")")
} finally {
  # Zakoncz konczy skrypt przez exit - PowerShell i tak przechodzi wtedy przez finally.
  Oddaj-Blokade-Lore
}
