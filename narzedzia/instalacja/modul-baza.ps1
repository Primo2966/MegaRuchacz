# narzedzia\instalacja\modul-baza.ps1 - modul "baza" MegaRuchacza. Jest ZAWSZE; reszta modulow na nim stoi.
#
# Co zaklada:
#   - hook straznika (SessionStart) w ~\.claude\settings.json - aktualizacje MegaRuchacza i pilnowanie
#     zasad przy kazdym otwarciu sesji; uklada go straznik-zasad.ps1 -NaprawGlobalne (ten sam kod,
#     ktorym potem pilnuje hookow - od zmian P59a komplet hookow idzie wedlug rejestru)
#   - nadzorce w zasobniku: zadanie MegaRuchaczNadzorca (zasobnik\zainstaluj-zasobnik.ps1)
#   - zadanie LoreKoszt - dzienny raport kosztu pamieci, punkt odniesienia alarmu "koszt urosl"
#     (narzedzia\koszt-pamieci.ps1 -ZalozZadanie)
#   - sprawdza, ze repo jest klonem git z galezia sledzaca - inaczej aktualizacje nie przyjda
#   - rejestr modulow ~\.claude\mr\instalacja.json: na SWIEZEJ maszynie zaklada go ze wszystkimi
#     modulami wylaczonymi (okno wlacza potem wybrane); na maszynie sprzed rejestru go nie rusza
#     (brak pliku znaczy tam "wszystko wlaczone" - tak jak bylo)
#   - zdejmuje stare zadania (MegaRuchaczOdswiez, LoreCykl i spolka)
# Usun: tylko gdy zaden modul nie jest juz wlaczony - inaczej zostalyby bez straznika i nadzorcy.
#   Zdejmuje hooki MegaRuchacza (cudze zostaja), nadzorce, LoreKoszt i bloki zasad MegaRuchacza.
#   -UsunDane dodatkowo pliki stanu straznika w ~\.claude (.megaruchacz-*). Rejestr zostaje
#   z "baza": false (P64) - slad, dzieki ktoremu straznik niczego nie doklada z powrotem.
#
# Uzycie (umowa wyjscia - naglowek wspolne.ps1):
#   powershell -NoProfile -ExecutionPolicy Bypass -File narzedzia\instalacja\modul-baza.ps1
#     -Akcja Instaluj|Usun|Stan [-KatalogDomowy <kat>] [-Zrodlo <repo>] [-Proba] [-UsunDane]
#     [-BezStartu]   zaklada nadzorce, ale go nie uruchamia (wstanie przy nastepnym zalogowaniu)

[CmdletBinding()]
param(
  [string]$Akcja = "",
  [string]$KatalogDomowy = $HOME,
  [string]$Zrodlo = "",
  [switch]$Proba,
  [switch]$UsunDane,
  [switch]$BezStartu
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "wspolne.ps1")
# PULAPKA PS 5.1: w skrypcie z [CmdletBinding()] uruchomionym przez -File $PSScriptRoot w wartosci
# domyslnej parametru jest pusty - dlatego domyslne zrodlo liczymy dopiero tutaj.
if (-not $Zrodlo) { $Zrodlo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$s0 = Start-Modul "baza" $Akcja ([bool]$Proba) $Zrodlo $KatalogDomowy
$Zrodlo = $s0.Zrodlo; $KatalogDomowy = $s0.KatalogDomowy
Lore-Przygotuj

$Ustawienia = Join-Path $KatalogDomowy ".claude\settings.json"
$Zasobnik   = Join-Path $Zrodlo "zasobnik\zainstaluj-zasobnik.ps1"
$Koszt      = Join-Path $Zrodlo "narzedzia\koszt-pamieci.ps1"
$ZrodloSlash = $Zrodlo.Replace("\", "/")

# Slady instalacji sprzed rejestru: wtedy brak pliku rejestru znaczy "wszystko wlaczone"
# i baza nie ma prawa go zalozyc z modulami wylaczonymi.
function Slady-Starej-Instalacji {
  $slady = @()
  $kl = Join-Path $KatalogDomowy ".claude"
  foreach ($p in @(".megaruchacz-global", ".megaruchacz-straznik.txt", "lore.db", "mr\kopia-stan.txt", "mr\skille\stan.json")) {
    if (Test-Path -LiteralPath (Join-Path $kl $p)) { $slady += "~\.claude\$p" }
  }
  if (Test-Path -LiteralPath (Join-Path $KatalogDomowy ".lore\lore.db")) { $slady += "~\.lore\lore.db" }
  if ((Policz-Hooki $Ustawienia "SessionStart" 'straznik-zasad\.ps1') -gt 0) { $slady += "hook straznika w ~\.claude\settings.json" }
  if (Zadanie-Jest $script:NazwaZadania) { $slady += "zadanie $($script:NazwaZadania)" }
  return $slady
}

function Stan-Hooka {
  $n = Policz-Hooki $Ustawienia "SessionStart" 'straznik-zasad\.ps1'
  if ($n -lt 0) { return [pscustomobject]@{ Ok = $false; Ile = $n; Opis = "$Ustawienia nie jest czystym JSON-em" } }
  if ($n -eq 0) { return [pscustomobject]@{ Ok = $false; Ile = 0; Opis = "nie ma hooka straznika (SessionStart) w $Ustawienia" } }
  if ($n -gt 1) { return [pscustomobject]@{ Ok = $false; Ile = $n; Opis = "hook straznika jest $n razy w $Ustawienia (dubel)" } }
  $tekst = [System.IO.File]::ReadAllText($Ustawienia)
  if ($tekst.IndexOf($ZrodloSlash, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
    return [pscustomobject]@{ Ok = $false; Ile = 1; Opis = "hook straznika wskazuje inne repo niz $Zrodlo" }
  }
  return [pscustomobject]@{ Ok = $true; Ile = 1; Opis = "hook straznika (SessionStart) jest w $Ustawienia" }
}

function Zbierz-Stan([hashtable]$prog) {
  $hook = Stan-Hooka
  $zad = Stan-Zadania $script:ZadanieNadzorcy 'nadzorca\.ps1'
  $proc = Procesy-Nadzorcy-Repo $Zrodlo
  $koszt = Stan-Zadania $script:ZadanieKosztu 'koszt-pamieci'
  $klon = Stan-Klonu $prog["git"] $Zrodlo
  if (-not $hook.Ok) { Problem $hook.Opis }
  if (-not $zad.Ok) { Problem "nadzorca: $($zad.Opis)" }
  elseif ($zad.Argumenty.IndexOf($Zrodlo, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { Problem "zadanie $($script:ZadanieNadzorcy) uruchamia nadzorce z innego repo niz $Zrodlo" }
  if ($null -eq $proc) { Problem "nie wiem, czy nadzorca chodzi (nie moglem sprawdzic procesow)" }
  elseif ($proc.Count -eq 0) { Problem "nadzorca nie chodzi - ikony przy zegarze nie ma (wstanie przy zalogowaniu albo po Start-ScheduledTask $($script:ZadanieNadzorcy))" }
  if (-not $koszt.Ok) { Problem "raport kosztu: $($koszt.Opis)" }
  if (-not $klon.Ok) { Problem $klon.Opis }
  $zainst = $hook.Ok -and [bool]$zad.Jest
  $dziala = $zainst -and $zad.Ok -and ($proc -and $proc.Count -gt 0) -and $koszt.Ok -and $klon.Ok
  return [pscustomobject]@{ Zainstalowany = $zainst; Dziala = $dziala
    Szczegoly = [ordered]@{ hook = $hook.Opis; nadzorca_zadanie = $zad.Opis; nadzorca_chodzi = $(if ($null -eq $proc) { $null } else { $proc.Count -gt 0 })
                            koszt_zadanie = $koszt.Opis; aktualizacje = $klon.Opis } }
}

try {
  if ($Akcja -eq "Stan") {
    $prog = Sprawdz-Programy @("git") @("bash")
    $rej = Czytaj-Instalacje $KatalogDomowy
    if ($rej.blad) { Problem "rejestr modulow: $($rej.blad)" }
    $st = Zbierz-Stan $prog
    $kom = if ($st.Dziala) { "baza dziala" } elseif ($st.Zainstalowany) { "baza zainstalowana, ale: " + (@($script:MR.problemy) -join "; ") } else { "baza nie jest zainstalowana" }
    Zakoncz (-not $rej.blad) $kom @{ zainstalowany = $st.Zainstalowany; dziala = $st.Dziala; szczegoly = $st.Szczegoly; rejestr = (Rejestr-Do-Wyniku $rej $KatalogDomowy) }
  }

  if ($Akcja -eq "Instaluj") {
    $prog = Sprawdz-Programy @("git") @("bash")
    Odmowa-Brak-Programow
    if (-not $prog["bash"]) { Ostrzezenie "nie widze Git Bash - hooki Claude Code chodza przez bash; Claude Code na Windows i tak go wymaga, zainstaluj Git for Windows" }
    $rej = Rejestr-Do-Zmian $KatalogDomowy

    # 1. rejestr modulow na swiezej maszynie
    if ($rej.zrodlo -eq "domyslne") {
      $slady = @(Slady-Starej-Instalacji)
      if ($slady.Count -gt 0) {
        Krok "rejestru modulow jeszcze nie ma, ale to starsza instalacja ($($slady[0])) - do czasu wyboru w oknie wszystkie moduly licza sie jako wlaczone"
      } elseif ($Proba) {
        Plan "zalozylbym rejestr modulow $(Sciezka-Instalacji $KatalogDomowy) - wszystkie moduly wylaczone, do wlaczenia w oknie"
      } else {
        foreach ($n in (Moduly-MegaRuchacza)) { $rej.moduly | Add-Member -NotePropertyName $n -NotePropertyValue $false -Force }
        $rej | Add-Member -NotePropertyName baza -NotePropertyValue $true -Force
        Zapisz-Instalacje $rej $KatalogDomowy
        Krok "zalozony rejestr modulow $(Sciezka-Instalacji $KatalogDomowy) - zaden modul jeszcze nie jest wlaczony"
      }
    } elseif ($rej.baza -ne $true) {
      # Slad po usunieciu calego MegaRuchacza (baza = false, P64) - baza wraca, a z nia straznik.
      if ($Proba) { Plan "zapisalbym w rejestrze modulow: baza znowu jest" }
      else { Ustaw-Baze $true $KatalogDomowy; Krok "rejestr modulow: baza znowu jest (MegaRuchacz byl wczesniej usuniety z tego komputera)" }
    }

    # 2. hook straznika
    $h = Napraw-Hooki $Zrodlo $KatalogDomowy
    if (-not $h.Ok) { Zakoncz $false "nie udalo sie ulozyc hookow w $Ustawienia - $(Sedno $h.Tekst)" }
    if (-not $Proba) {
      $sh = Stan-Hooka
      if (-not $sh.Ok) { Zakoncz $false "straznik skonczyl bez bledu, ale: $($sh.Opis)" }
      Krok "hook straznika na starcie sesji: aktualizacje MegaRuchacza i pilnowanie zasad ($Ustawienia)"
    }

    # 3. nadzorca w zasobniku
    $arg = @("-Zrodlo", $Zrodlo)
    if ($BezStartu) { $arg += "-BezStartu" }
    if ($Proba) { $arg += "-Proba" }
    $w = Uruchom-Skrypt $Zasobnik $arg 180
    Przekaz-Uwagi $w.Tekst "nadzorca"
    if ($w.Kod -ne 0) { Zakoncz $false "nadzorca w zasobniku nie stanal: $(Sedno $w.Tekst) (sprobuj: powershell -ExecutionPolicy Bypass -File $Zasobnik)" }
    if ($Proba) { Plan "zadanie $($script:ZadanieNadzorcy): nadzorca przy zegarze, wstaje przy kazdym zalogowaniu" }
    else {
      $zad = Stan-Zadania $script:ZadanieNadzorcy 'nadzorca\.ps1'
      if (-not $zad.Ok) { Zakoncz $false "zainstaluj-zasobnik.ps1 skonczyl bez bledu, ale zadania nie ma: $($zad.Opis)" }
      $jak = if ($BezStartu) { "wstanie przy nastepnym zalogowaniu" } else { "ikona jest przy zegarze" }
      Krok "nadzorca w zasobniku: zadanie $($script:ZadanieNadzorcy) ($($zad.Opis)), $jak"
    }

    # 4. dzienny raport kosztu pamieci
    if ($Proba) { Plan "zadanie $($script:ZadanieKosztu): codzienny raport kosztu pamieci (koszt-pamieci.ps1 -ZalozZadanie)" }
    else {
      $w = Uruchom-Skrypt $Koszt @("-ZalozZadanie", "-KatalogDomowy", $KatalogDomowy, "-Zrodlo", $Zrodlo) 120
      $zk = Stan-Zadania $script:ZadanieKosztu 'koszt-pamieci'
      if ($w.Kod -ne 0 -or -not $zk.Ok) { Zakoncz $false "nie udalo sie zalozyc zadania $($script:ZadanieKosztu): $(Sedno $w.Tekst) $($zk.Opis)" }
      Krok "zadanie $($script:ZadanieKosztu): codzienny raport kosztu pamieci ($($zk.Opis))"
    }

    # 5. aktualizacje = klon git
    $klon = Stan-Klonu $prog["git"] $Zrodlo
    if ($klon.Ok) { Krok "aktualizacje: $($klon.Opis) - straznik pobiera nowe wersje przy starcie sesji" }
    else { Ostrzezenie $klon.Opis }

    # 6. stare zadania
    [void](Lore-Usun-Stare-Zadania)

    if ($Proba) { Zakoncz $true "proba: baza dalaby sie zainstalowac" @{ zainstalowany = $null; dziala = $null } }
    $st = Zbierz-Stan $prog
    $rej2 = Czytaj-Instalacje $KatalogDomowy
    $kom = if ($st.Dziala) { "baza zainstalowana i dziala" } else { "baza zainstalowana; do sprawdzenia: " + (@($script:MR.problemy) -join "; ") }
    Zakoncz $true $kom @{ zainstalowany = $st.Zainstalowany; dziala = $st.Dziala; szczegoly = $st.Szczegoly; rejestr = (Rejestr-Do-Wyniku $rej2 $KatalogDomowy) }
  }

  # ---------------------------------------------------------------- Usun
  $rej = Rejestr-Do-Zmian $KatalogDomowy
  $wlaczone = @((Moduly-MegaRuchacza) | Where-Object { [bool]$rej.moduly.$_ })
  if ($wlaczone.Count -gt 0) {
    $skad = if ($rej.zrodlo -eq "domyslne") { " (rejestru nie ma - instalacja sprzed rejestru liczy sie jako komplet)" } else { "" }
    Zakoncz $false ("baza zostaje, bo wlaczone sa moduly: " + ($wlaczone -join ", ") + "$skad - najpierw je usun (modul-<nazwa>.ps1 -Akcja Usun)") @{ rejestr = (Rejestr-Do-Wyniku $rej $KatalogDomowy) }
  }
  $ok = $true
  # Slad odinstalowania w rejestrze (stan.ps1, P64): straznik wywolany potem z jakiegos projektu nie
  # uzna tego za instalacje globalna i nie dolozy swojego hooka. Przed zdejmowaniem - gdyby cos
  # dalej sie nie udalo, slad i tak stoi. Bez pliku rejestru (instalacja sprzed niego) nie ma gdzie.
  if ($rej.zrodlo -eq "plik") {
    if ($Proba) { Plan "zapisalbym w rejestrze modulow: baza usunieta (zeby nic nie wrocilo samo)" }
    else { Ustaw-Baze $false $KatalogDomowy; Krok "rejestr modulow: baza usunieta - plik rejestru zostaje jako slad, zeby straznik niczego nie dokladal z powrotem" }
  }
  $h = Napraw-Hooki $Zrodlo $KatalogDomowy -Usun
  if (-not $h.Ok) { $ok = $false; Ostrzezenie "hooki MegaRuchacza w $Ustawienia nie zostaly zdjete: $(Sedno $h.Tekst)" }
  elseif (-not $Proba) { Krok "zdjete hooki MegaRuchacza z $Ustawienia (cudze zostaly)" }

  $arg = @("-Zrodlo", $Zrodlo, "-Usun")
  if ($Proba) { $arg += "-Proba" }
  $w = Uruchom-Skrypt $Zasobnik $arg 120
  # "nikt nie pilnuje cyklu wiedzy" z zainstaluj-zasobnik -Usun: baza znika tylko przy wylaczonej wiedzy,
  # wiec cyklu nie ma - w "Do sprawdzenia" okna bylby to falszywy alarm (proba calosci P64).
  Przekaz-Uwagi (@($w.Tekst -split "`r?`n" | Where-Object { $_ -notmatch 'nikt nie pilnuje cyklu wiedzy' }) -join "`n") "nadzorca"
  if ($w.Kod -ne 0) { $ok = $false; Ostrzezenie "nadzorca nie zostal zdjety: $(Sedno $w.Tekst)" }
  elseif ($Proba) { Plan "zamknalbym nadzorce i zdjal zadanie $($script:ZadanieNadzorcy)" }
  else { Krok "nadzorca zamkniety, zadanie $($script:ZadanieNadzorcy) zdjete" }

  if ($Proba) { Plan "zdjalbym zadanie $($script:ZadanieKosztu)" }
  else {
    $w = Uruchom-Skrypt $Koszt @("-UsunZadanie", "-KatalogDomowy", $KatalogDomowy, "-Zrodlo", $Zrodlo) 120
    if ($w.Kod -ne 0 -or (Zadanie-Jest $script:ZadanieKosztu)) { $ok = $false; Ostrzezenie "zadanie $($script:ZadanieKosztu) nie zostalo zdjete: $(Sedno $w.Tekst)" }
    else { Krok "zadanie $($script:ZadanieKosztu) zdjete" }
  }
  [void](Lore-Usun-Stare-Zadania)
  if (-not (Wpisz-Zasady $Zrodlo $KatalogDomowy -Usun)) { $ok = $false }

  if ($UsunDane) {
    $kl = Join-Path $KatalogDomowy ".claude"
    foreach ($p in @(Get-ChildItem -LiteralPath $kl -Force -Filter ".megaruchacz-*" -ErrorAction SilentlyContinue)) {
      if ($p.Name -eq ".megaruchacz-global") { continue }   # znacznik kierownika - zdejmuje go modul kierownik
      if (-not (Usun-Katalog-Danych $p.FullName "plik stanu straznika $($p.Name)")) { $ok = $false }
    }
  } else {
    Krok "pliki stanu straznika w ~\.claude zostaja (usunie je -UsunDane)"
  }
  if ($Proba) { Zakoncz $ok "proba: baza dalaby sie usunac" }
  $kom = if ($ok) { "baza usunieta - MegaRuchacz nie pilnuje juz niczego na tym komputerze" } else { "baza usunieta tylko czesciowo - szczegoly w uwagach" }
  Zakoncz $ok $kom @{ zainstalowany = $false; dziala = $false; rejestr = (Rejestr-Do-Wyniku (Czytaj-Instalacje $KatalogDomowy) $KatalogDomowy) }
} catch {
  Zakoncz $false ("nieoczekiwany blad: " + $_.Exception.Message + " (" + $_.InvocationInfo.PositionMessage.Split("`n")[0].Trim() + ")")
}
