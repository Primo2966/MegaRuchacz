# narzedzia\instalacja\modul-wiedzafirmy.ps1 - modul "Wiedza firmy": ten komputer podlacza sie do
# wspolnej bazy wiedzy firmy (serwer jfwiedza). Ustalenia z rozmow trafiaja na serwer, a Claude dostaje
# serwer MCP "jfwiedza" z wiedza calej firmy. Pracownik niczego nie ustawia - zgloszenie komputera,
# token i podlaczenie MCP robi sam klient (narzedzia\wiedza-firmy-klient\klient.py), dostep daje admin
# zatwierdzeniem komputera w panelu JFTools.
#
# Pliki, adresy i znaczniki - umowa w narzedzia\instalacja\stan-wiedzy-firmy.ps1 (naglowek). W skrocie:
# ADRESY serwera i JFTools nie leza w publicznym repo - parametry -AdresSerwera/-AdresJFTools, zmienne
# MR_WIEDZA_FIRMY_SERWER/MR_WIEDZA_FIRMY_JFTOOLS, pole wiedza_firmy w ~\.claude\mr\lokalne.json albo
# dotychczasowa konfiguracja.json. Bez nich Instaluj konczy sie bledem z powodem.
#
# Co robi Instaluj:
#   - sprawdza rdzen Lore (srodowisko Pythona lore\.venv - stawia go modul Wiedza albo Lore; klient
#     chodzi w nim przez uv) i program klienta
#   - zapisuje ~\.claude\mr\wiedza-firmy\konfiguracja.json (adresy; inne pola zostawia)
#   - zaklada zadanie WiedzaFirmyKlient: przy zalogowaniu (+5 min) i co 30 min "klient.py tick",
#     przez conhost --headless (bez okna), XML bez uprawnien administratora jak LoreIndex
#   - wlacza modul w rejestrze i od razu odpala jeden "tick" w tle (zgloszenie komputera)
# Usun: zdejmuje zadanie i serwer MCP jfwiedza z Claude Code (claude mcp remove jfwiedza -s user);
#   dane w ~\.claude\mr\wiedza-firmy zostaja (klucz komputera - po ponownym wlaczeniu ten sam wpis
#   w panelu), z -UsunDane znikaja. To, co juz poszlo na serwer firmy, zostaje na serwerze.
# Stan: rejestr (trzy stany: wlaczony / wylaczony / nie zaproponowano), konfiguracja, zadanie,
#   stan.json klienta i znaczniki (blad kroku albo znacznik nieswiezy = problem).
#
# Uzycie (umowa wyjscia - naglowek wspolne.ps1):
#   powershell -NoProfile -ExecutionPolicy Bypass -File narzedzia\instalacja\modul-wiedzafirmy.ps1
#     -Akcja Instaluj|Usun|Stan [-KatalogDomowy <kat>] [-Zrodlo <repo>] [-Proba] [-UsunDane]
#     [-AdresSerwera <https://...>] [-AdresJFTools <https://...>]

[CmdletBinding()]
param(
  [string]$Akcja = "",
  [string]$KatalogDomowy = $HOME,
  [string]$Zrodlo = "",
  [switch]$Proba,
  [switch]$UsunDane,
  [string]$AdresSerwera = "",
  [string]$AdresJFTools = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "wspolne.ps1")
. (Join-Path $PSScriptRoot "stan-wiedzy-firmy.ps1")
if (-not $Zrodlo) { $Zrodlo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$s0 = Start-Modul "wiedzafirmy" $Akcja ([bool]$Proba) $Zrodlo $KatalogDomowy
$Zrodlo = $s0.Zrodlo; $KatalogDomowy = $s0.KatalogDomowy

$Katalog     = Katalog-Wiedzy-Firmy $KatalogDomowy
$PlikKonfig  = Plik-Konfiguracji-Wiedzy-Firmy $KatalogDomowy
$PlikKlienta = Join-Path $Katalog "stan.json"
$Klient      = Join-Path $Zrodlo "narzedzia\wiedza-firmy-klient\klient.py"
$KatalogLore = Join-Path $Zrodlo "lore"
$PythonLore  = Join-Path $KatalogLore ".venv\Scripts\python.exe"
$NazwaMcp    = "jfwiedza"
$WzorAkcji   = 'klient\.py"?\s+tick'
# Limit jednego przebiegu: "tick" bywa dlugi przy pierwszym przegladzie historii (klient wznawia go
# przy nastepnym przebiegu), a IgnoreNew i tak nie wpusci drugiego naraz.
$LimitPrzebiegu = "PT4H"

# Akcja zadania: conhost --headless (zadne okno konsoli co pol godziny), uv w srodowisku Lore -
# ta sama droga co zadanie LoreIndex (lore-czesci.ps1 Argumenty-Indeksu).
function Argumenty-Klienta([string]$uv) {
  return "--headless `"$uv`" --directory `"$KatalogLore`" run python `"$Klient`" tick"
}

# XML zamiast obiektow - obiekty (New-ScheduledTaskPrincipal) daja "Odmowa dostepu" bez administratora
# (lore-czesci.ps1 Zarejestruj-Zadanie). Dwa wyzwalacze: przy zalogowaniu z opoznieniem 5 min (siec
# i logowanie Claude gotowe, decyzja uzytkownika 2026-10-12) i co 30 min od pol godziny po instalacji
# (pierwszy przebieg idzie od razu w tle). StartWhenAvailable: po uspieniu przebieg nadrabia sie zaraz.
function Zarejestruj-Zadanie-Klienta([string]$argumenty) {
  $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
  $start = (Get-Date).AddMinutes(30).ToString("yyyy-MM-ddTHH:mm:ss")
  $przyLogowaniu = "true"
  $argXml = [System.Security.SecurityElement]::Escape($argumenty)
  $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>MegaRuchacz - Wiedza firmy: zgloszenie komputera i wysylka ustalen do wspolnej bazy firmy (klient.py tick)</Description>
    <URI>\$($script:ZadanieWiedzyFirmy)</URI>
  </RegistrationInfo>
  <Principals>
    <Principal id="Author">
      <UserId>$sid</UserId>
      <LogonType>InteractiveToken</LogonType>
    </Principal>
  </Principals>
  <Settings>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>$LimitPrzebiegu</ExecutionTimeLimit>
    <Hidden>true</Hidden>
    <Enabled>true</Enabled>
  </Settings>
  <Triggers>
    <LogonTrigger>
      <Enabled>$przyLogowaniu</Enabled>
      <UserId>$sid</UserId>
      <Delay>PT5M</Delay>
    </LogonTrigger>
    <TimeTrigger>
      <StartBoundary>$start</StartBoundary>
      <Repetition>
        <Interval>PT30M</Interval>
      </Repetition>
      <Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Actions Context="Author">
    <Exec>
      <Command>conhost.exe</Command>
      <Arguments>$argXml</Arguments>
    </Exec>
  </Actions>
</Task>
"@
  Register-ScheduledTask -TaskName $script:ZadanieWiedzyFirmy -Xml $xml -Force -ErrorAction Stop | Out-Null
}

# Konfiguracja: nasze pola nadpisane, cudze (dopisane przez klienta albo nowsza wersje) zostaja.
function Zapisz-Konfiguracje($a) {
  $k = [ordered]@{}
  if (Test-Path -LiteralPath $PlikKonfig) {
    try { foreach ($p in (Wf-Czytaj-Json $PlikKonfig).PSObject.Properties) { $k[$p.Name] = $p.Value } }
    catch { Ostrzezenie "dotychczasowa konfiguracja $PlikKonfig byla nieczytelna ($($_.Exception.Message)) - zapisuje ja od nowa" }
  }
  $k["wersja"] = 1
  $k["serwer_url"] = $a.Serwer
  $k["jftools_url"] = $a.JFTools
  $k["skad"] = $a.Skad
  $k["zrodlo"] = $Zrodlo
  $k["zapisano"] = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  Wf-Zapisz-Atomowo $PlikKonfig ((ConvertTo-Json -InputObject $k -Depth 6) + "`r`n")
}

# Pierwszy "tick" od razu, w tle i bez okna - nie czekamy pol godziny na zadanie. Osobny proces,
# nie Start-ScheduledTask: dziedziczy katalog domowy wolajacego (zadanie chodzi zawsze na prawdziwym).
function Tick-W-Tle([string]$uv) {
  $log = Join-Path $Katalog "tick-instalacja.log"
  $logBl = Join-Path $Katalog "tick-instalacja.err.log"
  try {
    $p = Start-Process -FilePath $uv -ArgumentList @("--directory", "`"$KatalogLore`"", "run", "python", "`"$Klient`"", "tick") `
      -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError $logBl -ErrorAction Stop
    Krok "pierwszy przebieg klienta ruszyl w tle (PID $($p.Id)) - komputer zglosi sie do serwera firmy; dziennik: $log"
  } catch {
    Ostrzezenie "nie udalo sie uruchomic pierwszego przebiegu klienta ($($_.Exception.Message)) - zrobi to zadanie $($script:ZadanieWiedzyFirmy) w ciagu 30 min"
  }
}

function Stan-Konfiguracji {
  $w = [pscustomobject]@{ Ok = $false; Opis = ""; Serwer = ""; JFTools = ""; Zapisano = "" }
  if (-not (Test-Path -LiteralPath $PlikKonfig)) { $w.Opis = "nie ma $PlikKonfig"; return $w }
  try { $k = Wf-Czytaj-Json $PlikKonfig } catch { $w.Opis = "konfiguracja $PlikKonfig nieczytelna: $($_.Exception.Message)"; return $w }
  $w.Serwer = "$($k.serwer_url)"; $w.JFTools = "$($k.jftools_url)"; $w.Zapisano = "$($k.zapisano)"
  $brak = @()
  if (-not (Wf-Adres-Dobry $w.Serwer)) { $brak += "serwer_url" }
  if (-not (Wf-Adres-Dobry $w.JFTools)) { $brak += "jftools_url" }
  if ($brak.Count) { $w.Opis = "w konfiguracji $PlikKonfig brakuje dobrego adresu: $($brak -join ', ')"; return $w }
  $w.Ok = $true; $w.Opis = "konfiguracja: $PlikKonfig"
  return $w
}

function Stan-Klienta {
  if (-not (Test-Path -LiteralPath $PlikKlienta)) { return [pscustomobject]@{ Ok = $true; Opis = "klient jeszcze nie zapisal stanu ($PlikKlienta)"; Status = "" } }
  try {
    $s = Wf-Czytaj-Json $PlikKlienta
    $st = "$($s.status)"
    return [pscustomobject]@{ Ok = $true; Opis = "stan klienta: $(if ($st) { $st } else { 'bez pola status' })"; Status = $st }
  } catch { return [pscustomobject]@{ Ok = $false; Opis = "stan klienta $PlikKlienta nieczytelny: $($_.Exception.Message)"; Status = "" } }
}

function Zbierz-Stan($rej) {
  $v = $rej.moduly.wiedzafirmy
  $stanMod = if ($rej.blad) { "nieczytelny" } elseif ($null -eq $v) { "nie-zaproponowano" } elseif ([bool]$v) { "wlaczony" } else { "wylaczony" }
  $zainst = ($stanMod -eq "wlaczony")
  $konf = Stan-Konfiguracji
  $zad = Stan-Zadania $script:ZadanieWiedzyFirmy $WzorAkcji
  $kl = Stan-Klienta
  $oc = Ocena-Znacznikow-Wiedzy-Firmy $KatalogDomowy
  if ($zainst) {
    if (-not $konf.Ok) { Problem $konf.Opis }
    if (-not $zad.Ok) { Problem "zadanie $($script:ZadanieWiedzyFirmy): $($zad.Opis)" }
    if (-not (Test-Path -LiteralPath $Klient)) { Problem "nie ma programu klienta $Klient" }
    if (-not $kl.Ok) { Problem $kl.Opis }
    foreach ($p in $oc.Problemy) { Problem $p }
  }
  $znaczniki = @($oc.Znaczniki | ForEach-Object { [ordered]@{ krok = $_.Krok; czas = $(if ($_.Czas) { $_.Czas.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }); stan = $_.Stan; opis = $_.Opis; blad = $_.Blad } })
  return [pscustomobject]@{ Zainstalowany = $zainst; Dziala = ($zainst -and ($script:MR.problemy.Count -eq 0)); StanModulu = $stanMod; Szczegoly = [ordered]@{
    stan_modulu = $stanMod; konfiguracja = $konf.Opis; serwer = $konf.Serwer; jftools = $konf.JFTools; zadanie = $zad.Opis
    stan_klienta = $kl.Opis; status_klienta = $kl.Status; znaczniki = [object[]]$znaczniki; nieswiezosc = $(if ($oc.Sprawdzone) { "sprawdzona" } else { $oc.Uwaga }) } }
}

try {
  if ($Akcja -eq "Stan") {
    [void](Sprawdz-Programy @() @("uv", "claude"))
    $rej = Czytaj-Instalacje $KatalogDomowy
    if ($rej.blad) { Problem "rejestr modulow: $($rej.blad)" }
    $st = Zbierz-Stan $rej
    $kom = switch ($st.StanModulu) {
      "wlaczony"          { if ($st.Dziala) { "Wiedza firmy dziala" } else { "Wiedza firmy wlaczona, ale: " + (@($script:MR.problemy) -join "; ") } }
      "nie-zaproponowano" { "Wiedza firmy nie byla jeszcze proponowana na tym komputerze" }
      "wylaczony"         { "Wiedza firmy nie jest wlaczona" }
      default             { "nie wiem, czy Wiedza firmy jest - rejestr nieczytelny" }
    }
    Zakoncz (-not $rej.blad) $kom @{ zainstalowany = $st.Zainstalowany; dziala = $st.Dziala; zaproponowany = ($st.StanModulu -ne "nie-zaproponowano"); szczegoly = $st.Szczegoly; rejestr = (Rejestr-Do-Wyniku $rej $KatalogDomowy) }
  }

  $rej = Rejestr-Do-Zmian $KatalogDomowy

  if ($Akcja -eq "Instaluj") {
    $prog = Sprawdz-Programy @("uv") @("claude")
    Odmowa-Brak-Programow
    $a = Adresy-Wiedzy-Firmy $KatalogDomowy $AdresSerwera $AdresJFTools
    foreach ($b in $a.Bledy) { Ostrzezenie $b }
    if (-not $a.Jest) {
      $brak = @(@($(if (-not $a.Serwer) { "serwera Wiedzy firmy" }), $(if (-not $a.JFTools) { "JFTools" })) | Where-Object { $_ })
      Zakoncz $false ("nie znam adresu: $($brak -join ' ani ') - adresy firmy nie leza w publicznym repozytorium. Podaj je parametrami -AdresSerwera i -AdresJFTools, " +
        "zmiennymi MR_WIEDZA_FIRMY_SERWER i MR_WIEDZA_FIRMY_JFTOOLS albo w polu wiedza_firmy pliku $(Sciezka-Lokalnych $KatalogDomowy)") @{ brak_adresu = $true }
    }
    Krok "adresy serwera firmy: $($a.Skad)"
    $rdzen = (Modul-Wlaczony "wiedza" $KatalogDomowy) -or (Modul-Wlaczony "lore" $KatalogDomowy)
    if (-not (Test-Path -LiteralPath $PythonLore)) {
      $t = "nie ma srodowiska Pythona Lore ($PythonLore) - Wiedza firmy chodzi w nim, a stawia je Wiedza o Tobie albo Pamiec rozmow (Lore); zainstaluj najpierw jedna z nich"
      if ($Proba) { Ostrzezenie $t } else { Zakoncz $false $t }
    } elseif (-not $rdzen) {
      Ostrzezenie "w rejestrze nie ma ani Wiedzy o Tobie, ani Pamieci rozmow - srodowisko Lore jest, ale gdy zniknie, Wiedza firmy stanie"
    } else { Krok "srodowisko Lore jest ($PythonLore)" }
    if (-not (Test-Path -LiteralPath $Klient)) {
      $t = "nie ma programu klienta $Klient - ta wersja MegaRuchacza jest niekompletna; pobierz nowsza"
      if ($Proba) { Ostrzezenie $t } else { Zakoncz $false $t }
    }
    if (-not $prog["claude"]) { Ostrzezenie "nie ma Claude Code - klient zglosi komputer, ale serwera jfwiedza nie bedzie gdzie podlaczyc, dopoki Claude Code nie stanie" }

    if ($Proba) {
      Plan "zapisalbym $PlikKonfig (serwer i JFTools z: $($a.Skad))"
      Plan "zadanie $($script:ZadanieWiedzyFirmy): przy zalogowaniu (+5 min) i co 30 min, bez okna - conhost.exe $(Argumenty-Klienta $prog['uv'])"
      Plan "pierwszy przebieg klienta (tick) w tle"
    } else {
      New-Item -ItemType Directory -Force -Path $Katalog | Out-Null
      Zapisz-Konfiguracje $a
      Krok "konfiguracja zapisana: $PlikKonfig"
      try { Zarejestruj-Zadanie-Klienta (Argumenty-Klienta $prog["uv"]) }
      catch { Zakoncz $false "nie udalo sie zalozyc zadania $($script:ZadanieWiedzyFirmy): $($_.Exception.Message) (jesli to 'Odmowa dostepu' - zasady tej maszyny moga wymagac uprawnien administratora)" }
      $zad = Stan-Zadania $script:ZadanieWiedzyFirmy $WzorAkcji
      if (-not $zad.Ok) { Zakoncz $false "zadanie $($script:ZadanieWiedzyFirmy) nie powstalo jak trzeba: $($zad.Opis) - harmonogram przyjal polecenie, ale zadania nie ma albo ma inna akcje" }
      Krok "zadanie $($script:ZadanieWiedzyFirmy) jest w Harmonogramie ($($zad.Opis)) - przy zalogowaniu (+5 min) i co 30 min, bez okna"
    }
    Zapisz-Modul "wiedzafirmy" $true $KatalogDomowy
    if ($Proba) { Zakoncz $true "proba: Wiedza firmy dalaby sie zainstalowac" }
    Tick-W-Tle $prog["uv"]
    $st = Zbierz-Stan (Czytaj-Instalacje $KatalogDomowy)
    $kom = "Wiedza firmy zainstalowana - komputer zglasza sie do serwera firmy w tle; dostep pojawi sie po zatwierdzeniu w panelu JFTools"
    Zakoncz $true $kom @{ zainstalowany = $st.Zainstalowany; dziala = $st.Dziala; zaproponowany = $true; szczegoly = $st.Szczegoly; rejestr = (Rejestr-Do-Wyniku (Czytaj-Instalacje $KatalogDomowy) $KatalogDomowy) }
  }

  # ---------------------------------------------------------------- Usun
  $ok = $true
  $zad = Stan-Zadania $script:ZadanieWiedzyFirmy $WzorAkcji
  if ($zad.Jest -eq $false) { Krok "zadania $($script:ZadanieWiedzyFirmy) nie ma w Harmonogramie - nie ma czego zdejmowac" }
  elseif ($Proba) { Plan "zdjalbym zadanie $($script:ZadanieWiedzyFirmy)" }
  else {
    try { Unregister-ScheduledTask -TaskName $script:ZadanieWiedzyFirmy -Confirm:$false -ErrorAction Stop }
    catch { Zakoncz $false "nie udalo sie zdjac zadania $($script:ZadanieWiedzyFirmy), wiec Wiedza firmy zostaje wlaczona: $($_.Exception.Message)" }
    if (Zadanie-Jest $script:ZadanieWiedzyFirmy) { Zakoncz $false "zadanie $($script:ZadanieWiedzyFirmy) nadal jest w Harmonogramie - Wiedza firmy zostaje wlaczona; zdejmij je recznie" }
    Krok "zadanie $($script:ZadanieWiedzyFirmy) zdjete - nic juz nie idzie na serwer firmy"
  }
  $claude = Znajdz-Program "claude"
  if (-not $claude) { Krok "nie ma Claude Code - serwera $NazwaMcp nie ma skad zdejmowac" }
  elseif ((Lore-Wolaj $claude @("mcp", "get", $NazwaMcp)).Kod -ne 0) { Krok "Claude Code: serwera $NazwaMcp tam nie ma" }
  elseif ($Proba) { Plan "Claude Code: claude mcp remove $NazwaMcp -s user" }
  else {
    $w = Lore-Wolaj $claude @("mcp", "remove", $NazwaMcp, "-s", "user")
    if (($w.Kod -ne 0) -or ((Lore-Wolaj $claude @("mcp", "get", $NazwaMcp)).Kod -eq 0)) {
      $ok = $false
      Ostrzezenie "nie udalo sie zdjac serwera $NazwaMcp z Claude Code (kod $($w.Kod)): $(Ostatnia-Linia $w.Tekst) - zdejmij go recznie: claude mcp remove $NazwaMcp -s user"
    } else { Krok "Claude Code: serwer $NazwaMcp zdjety (otwarte okna maja go do zamkniecia)" }
  }
  # "nie zaproponowano" zostaje "nie zaproponowano" - Usun na niezainstalowanym (np. sprzatanie resztek)
  # nie moze udawac, ze ktos o module zdecydowal.
  if ($null -ne $rej.moduly.wiedzafirmy) { Zapisz-Modul "wiedzafirmy" $false $KatalogDomowy }
  else { Krok "rejestr modulow: Wiedza firmy nie byla proponowana - zostawiam bez zmian" }
  if ($UsunDane) {
    if (-not (Usun-Katalog-Danych $Katalog "dane Wiedzy firmy na tym komputerze (klucz komputera, kolejka, wyslane, znaczniki)")) { $ok = $false }
    $pp = Plik-Pytania-Wiedzy-Firmy $KatalogDomowy
    if (Test-Path -LiteralPath $pp) { if (-not (Usun-Katalog-Danych $pp "zapis pytania o Wiedze firmy")) { $ok = $false } }
  } elseif (Test-Path -LiteralPath $Katalog) {
    Krok "dane Wiedzy firmy zostaja w $Katalog (klucz komputera - po ponownym wlaczeniu ten sam wpis w panelu) - usunie je -UsunDane"
  }
  Krok "to, co juz poszlo do bazy firmy, zostaje na serwerze firmy"
  if ($Proba) { Zakoncz $ok "proba: Wiedza firmy dalaby sie usunac" }
  $kom = if ($ok) { "Wiedza firmy wylaczona" } else { "Wiedza firmy wylaczona, ale nie wszystko udalo sie zdjac - szczegoly w uwagach" }
  Zakoncz $ok $kom @{ zainstalowany = $false; dziala = $false; rejestr = (Rejestr-Do-Wyniku (Czytaj-Instalacje $KatalogDomowy) $KatalogDomowy) }
} catch {
  Zakoncz $false ("nieoczekiwany blad: " + $_.Exception.Message + " (" + $_.InvocationInfo.PositionMessage.Split("`n")[0].Trim() + ")")
}
