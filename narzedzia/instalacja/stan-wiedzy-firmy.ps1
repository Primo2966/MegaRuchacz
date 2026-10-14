# narzedzia\instalacja\stan-wiedzy-firmy.ps1 - wspolna wiedza o module "Wiedza firmy" (wiedzafirmy:
# klient serwera jfwiedza na tym komputerze). Same definicje, przy wczytaniu niczego nie zmienia.
# Wczytuja go kropka: narzedzia\instalacja\modul-wiedzafirmy.ps1, okno instalatora (instalator\okno.ps1),
# cykl dzienny (narzedzia\cykl-dzienny.ps1 - alarm znacznikow), nadzorca (zasobnik\nadzorca\dozor.ps1 -
# pytanie po aktualizacji, stan-alarmy.ps1 - alarm) i okno pytania (zasobnik\nadzorca\pytanie-wiedza-firmy.ps1).
# Potrzebuje umowy rejestru (stan.ps1 obok) - wczytuje ja sam, gdy jej jeszcze nie ma.
# Stale sa funkcjami, nie zmiennymi $script: - ten plik bywa wczytywany wewnatrz funkcji (nadzorca),
# a zakres $script: jest dynamiczny (pulapka opisana w stan.ps1 przy Moduly-MegaRuchacza).
#
# PLIKI KLIENTA (umowa z narzedzia\wiedza-firmy-klient\klient.py; projekt "Wiedza firmy, krok 3", sekcja 2):
#   ~\.claude\mr\wiedza-firmy\konfiguracja.json   pisze modul-wiedzafirmy.ps1 (Instaluj), UTF-8 bez BOM:
#       { "wersja": 1, "serwer_url": "<adres serwera jfwiedza>", "jftools_url": "<adres JFTools>",
#         "skad": "<skad wziete adresy>", "zrodlo": "<folder MegaRuchacza>", "zapisano": "RRRR-MM-DD GG:MM:SS" }
#       (nazwy pol jak w klient.py Klient.konfiguracja; pola, ktorych modul nie zna, zostaja przy zapisie)
#   ~\.claude\mr\wiedza-firmy\stan.json           pisze klient; tu tylko odczyt (Stan modulu)
#   ~\.claude\mr\wiedza-firmy\znaczniki\<krok>.txt  pisze klient, jedna linia "czas|ok|opis" albo
#       "czas|blad|opis" (czas ISO 8601 albo "RRRR-MM-DD GG:MM:SS"); kroki: zgloszenie, token, status,
#       przeglad, wysylka (+ dzienny z porannego automatu). "tick" zostawia przy KAZDYM przebiegu
#       znacznik wysylka (takze "czeka na zatwierdzenie") - jego nieswiezosc to alarm.
#
# ADRESY serwera jfwiedza i JFTools NIE leza w repozytorium (jest publiczne). Skad, kazdy adres osobno,
# pierwsze zrodlo, ktore go ma:
#   1. parametry -AdresSerwera / -AdresJFTools modulu,
#   2. zmienne srodowiskowe MR_WIEDZA_FIRMY_SERWER / MR_WIEDZA_FIRMY_JFTOOLS,
#   3. pole "wiedza_firmy": { "serwer": "...", "jftools": "..." } ustawien tego komputera
#      ~\.claude\mr\lokalne.json (stan.ps1 Czytaj-Lokalne - plik poza repo),
#   4. dotychczasowa konfiguracja.json (ponowna instalacja, aktualizacja).
# Bez obu adresow modulu nie ma komu zaproponowac: okno instalatora go nie pokazuje, nadzorca nie
# pyta, a Instaluj konczy sie bledem z powodem - nigdy instalacja "na pusto".

if (-not (Get-Command Czytaj-Instalacje -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'stan.ps1') }

# Prog nieswiezosci znacznika: "tick" chodzi przy logowaniu (+5 min) i co 30 min, dzienny raz na dobe -
# doba plus 2 h zapasu na pozne wlaczenie komputera. Nizszy prog alarmowalby po kazdej nocy.
function Wf-Godzin-Nieswiezy { return 26 }
# Swiezo po starcie albo wybudzeniu Windows klient nie zdazyl sie jeszcze odezwac (5 min opoznienia przy
# logowaniu + 30 min odstepu + 5 min zapasu) - po weekendzie znacznik ma 60 h i to nie jest awaria.
function Wf-Minut-Po-Starcie { return 40 }
# Kroki, ktore powinny chodzic stale (reszta - zgloszenie, token, przeglad - jest jednorazowa i liczy
# sie tylko jej blad).
function Wf-Kroki-Cykliczne { return @('status', 'wysylka', 'dzienny') }
# Nadzorca pyta o modul najwczesniej tyle minut po starcie Windows (ta sama decyzja uzytkownika
# z 2026-10-12, co przy przypomnieniach - stan-terminy.ps1 $MINUT_PO_STARCIE_WINDOWS).
function Wf-Minut-Przed-Pytaniem { return 5 }

function Katalog-Wiedzy-Firmy([string]$dom) { return (Join-Path $dom '.claude\mr\wiedza-firmy') }
function Plik-Konfiguracji-Wiedzy-Firmy([string]$dom) { return (Join-Path (Katalog-Wiedzy-Firmy $dom) 'konfiguracja.json') }
# Poza katalogiem modulu: katalog powstaje dopiero przy instalacji, a pytanie jest wczesniej.
function Plik-Pytania-Wiedzy-Firmy([string]$dom) { return (Join-Path $dom '.claude\mr\wiedza-firmy-pytanie.txt') }

function Wf-Czytaj-Json([string]$p) {
  $bajty = [System.IO.File]::ReadAllBytes($p)
  if ($bajty.Length -eq 0) { throw 'plik jest pusty' }
  if ([Array]::IndexOf($bajty, [byte]0) -ge 0) { throw 'plik zawiera bajty 0x00 (uszkodzony, np. po zaniku zasilania)' }
  $j = (New-Object System.Text.UTF8Encoding($false)).GetString($bajty).TrimStart([char]0xFEFF) | ConvertFrom-Json
  if ($j -isnot [System.Management.Automation.PSCustomObject]) { throw 'to nie jest obiekt JSON' }
  return $j
}

# Zapis atomowy (plik tymczasowy obok, Flush, podmiana) - jak Zapisz-Instalacje w stan.ps1.
function Wf-Zapisz-Atomowo([string]$p, [string]$tekst) {
  $kat = Split-Path -Parent $p
  if (-not (Test-Path -LiteralPath $kat)) { New-Item -ItemType Directory -Force -Path $kat | Out-Null }
  $bajty = (New-Object System.Text.UTF8Encoding($false)).GetBytes($tekst)
  $tmp = "$p.tmp-$PID"
  $fs = [System.IO.File]::Open($tmp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
  try { $fs.Write($bajty, 0, $bajty.Length); $fs.Flush($true) } finally { $fs.Dispose() }
  try {
    if (Test-Path -LiteralPath $p) { [System.IO.File]::Replace($tmp, $p, [NullString]::Value) }
    else { [System.IO.File]::Move($tmp, $p) }
  } catch {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    throw "nie udalo sie zapisac $p : $($_.Exception.Message)"
  }
}

function Wf-Data([string]$t) {
  $t = "$t".Trim()
  if (-not $t) { return $null }
  $d = [datetime]::MinValue
  if ([datetime]::TryParse($t, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeLocal, [ref]$d)) { return $d }
  return $null
}

# ---------------------------------------------------------------- adresy

function Wf-Adres-Dobry([string]$a) { return ("$a".Trim() -match '^https?://[^\s/]+\S*$') }

# Serwer, JFTools (pusto = nie znam), Skad (opis zrodel), Jest (oba), Bledy (nieczytelne zrodla,
# zle adresy - meldowane, nie przemilczane).
function Adresy-Wiedzy-Firmy([string]$dom, [string]$serwer = '', [string]$jftools = '') {
  $w = [pscustomobject]@{ Serwer = ''; JFTools = ''; Skad = ''; Jest = $false; Bledy = @() }
  $kand = New-Object System.Collections.ArrayList
  if ("$serwer$jftools".Trim()) { [void]$kand.Add(@('parametr modulu', $serwer, $jftools)) }
  [void]$kand.Add(@('zmienne MR_WIEDZA_FIRMY_SERWER / MR_WIEDZA_FIRMY_JFTOOLS', $env:MR_WIEDZA_FIRMY_SERWER, $env:MR_WIEDZA_FIRMY_JFTOOLS))
  $l = Czytaj-Lokalne $dom
  if ($l.blad) { $w.Bledy += $l.blad }
  elseif ($l.dane -and $l.dane.PSObject.Properties['wiedza_firmy'] -and $l.dane.wiedza_firmy) {
    [void]$kand.Add(@("ustawienia tego komputera ($($l.plik), pole wiedza_firmy)", "$($l.dane.wiedza_firmy.serwer)", "$($l.dane.wiedza_firmy.jftools)"))
  }
  $pk = Plik-Konfiguracji-Wiedzy-Firmy $dom
  if (Test-Path -LiteralPath $pk) {
    try { $k = Wf-Czytaj-Json $pk; [void]$kand.Add(@("dotychczasowa konfiguracja ($pk)", "$($k.serwer_url)", "$($k.jftools_url)")) }
    catch { $w.Bledy += "nie umiem odczytac $pk : $($_.Exception.Message)" }
  }
  $skadS = ''; $skadJ = ''
  foreach ($k in $kand) {
    foreach ($i in 1, 2) {
      $v = "$($k[$i])".Trim()
      if (-not $v) { continue }
      $co = if ($i -eq 1) { 'serwera Wiedzy firmy' } else { 'JFTools' }
      if (-not (Wf-Adres-Dobry $v)) { $w.Bledy += "adres $co z: $($k[0]) nie jest adresem http(s) - pomijam go"; continue }
      if (($i -eq 1) -and -not $w.Serwer) { $w.Serwer = $v.TrimEnd('/'); $skadS = $k[0] }
      if (($i -eq 2) -and -not $w.JFTools) { $w.JFTools = $v.TrimEnd('/'); $skadJ = $k[0] }
    }
  }
  $w.Jest = [bool]($w.Serwer -and $w.JFTools)
  if ($skadS -and ($skadS -eq $skadJ)) { $w.Skad = $skadS }
  else { $w.Skad = (@(@($(if ($skadS) { "serwer: $skadS" }), $(if ($skadJ) { "JFTools: $skadJ" })) | Where-Object { $_ }) -join '; ') }
  return $w
}

# ---------------------------------------------------------------- start Windows

# Ostatni start albo wybudzenie Windows ([datetime] albo $null, gdy nie da sie odczytac). Ta sama
# kolejnosc zrodel, co Start-Systemu w zasobnik\nadzorca\stan-terminy.ps1 (dziennik System: Kernel-Boot 27,
# Power-Troubleshooter 1, Kernel-Power 507; zapas: LastBootUpTime) - kopia, bo cykl dzienny i modul
# nie wczytuja nadzorcy.
function Wf-Start-Systemu {
  $x = "*[System[(Provider[@Name='Microsoft-Windows-Kernel-Boot'] and EventID=27) or " +
    "(Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1) or " +
    "(Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=507)]]"
  try { return (@(Get-WinEvent -LogName System -FilterXPath $x -MaxEvents 1 -ErrorAction Stop)[0]).TimeCreated }
  catch { $null = $_ }   # brak zdarzen albo dziennika - rozstrzyga LastBootUpTime nizej
  try { return [datetime](Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime }
  catch { return $null }
}

# $startSystemu: [datetime] (testy wstrzykuja), 'brak' (nie wiadomo) albo $null (odczytaj teraz).
function Wf-Rozwiaz-Start($startSystemu) {
  if ($startSystemu -is [datetime]) { return $startSystemu }
  if ("$startSystemu" -eq 'brak') { return $null }
  return (Wf-Start-Systemu)
}

# ---------------------------------------------------------------- znaczniki klienta

function Czytaj-Znaczniki-Wiedzy-Firmy([string]$dom) {
  $kat = Join-Path (Katalog-Wiedzy-Firmy $dom) 'znaczniki'
  $w = @()
  if (-not (Test-Path -LiteralPath $kat)) { return ,$w }
  foreach ($f in @(Get-ChildItem -LiteralPath $kat -Filter '*.txt' -File -ErrorAction Stop | Sort-Object Name)) {
    $z = [pscustomobject]@{ Krok = $f.BaseName; Plik = $f.FullName; Czas = $null; Stan = ''; Opis = ''; Blad = '' }
    try {
      $bajty = [System.IO.File]::ReadAllBytes($f.FullName)
      if ([Array]::IndexOf($bajty, [byte]0) -ge 0) { throw 'plik zawiera bajty 0x00' }
      $linia = @((New-Object System.Text.UTF8Encoding($false)).GetString($bajty).TrimStart([char]0xFEFF) -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
      if ($linia.Count -eq 0) { throw 'plik jest pusty' }
      $cz = $linia[0] -split '\|', 3
      if ($cz.Count -lt 2) { throw "linia bez pol czas|stan|opis: '$($linia[0])'" }
      $z.Czas = Wf-Data $cz[0]
      if (-not $z.Czas) { throw "nieczytelny czas '$($cz[0])'" }
      $z.Stan = $cz[1].Trim().ToLowerInvariant()
      if ($cz.Count -ge 3) { $z.Opis = $cz[2].Trim() }
    } catch { $z.Blad = "$($_.Exception.Message)" }
    $w += $z
  }
  return ,$w
}

function Wf-Godziny([datetime]$od, [datetime]$teraz) { return [int][math]::Floor(($teraz - $od).TotalHours) }

# Ocena znacznikow: Znaczniki (lista), Problemy (zdania - kazde to ALARM), Sprawdzone (czy liczono
# nieswiezosc - swiezo po starcie Windows nie). Bledy kroku ida zawsze, nieswiezosc dopiero po
# Wf-Minut-Po-Starcie od startu/wybudzenia.
function Ocena-Znacznikow-Wiedzy-Firmy([string]$dom, [datetime]$teraz = [datetime]::Now, $startSystemu = $null) {
  $w = [pscustomobject]@{ Znaczniki = @(); Problemy = @(); Sprawdzone = $true; Uwaga = '' }
  $prog = Wf-Godzin-Nieswiezy
  try { $w.Znaczniki = Czytaj-Znaczniki-Wiedzy-Firmy $dom }
  catch { $w.Problemy += "nie umiem przeczytac znacznikow klienta Wiedzy firmy: $($_.Exception.Message)"; return $w }
  foreach ($z in $w.Znaczniki) {
    if ($z.Blad) { $w.Problemy += "znacznik kroku '$($z.Krok)' jest nieczytelny ($($z.Plik)): $($z.Blad)"; continue }
    if (@('blad', 'error') -contains $z.Stan) {
      $w.Problemy += "krok '$($z.Krok)' skonczyl sie bledem $($z.Czas.ToString('yyyy-MM-dd HH:mm')): $(if ($z.Opis) { $z.Opis } else { 'bez opisu' })"
    }
  }
  $start = Wf-Rozwiaz-Start $startSystemu
  if ($start -and (($teraz - $start).TotalMinutes -lt (Wf-Minut-Po-Starcie))) {
    $w.Sprawdzone = $false
    $w.Uwaga = "nieswiezosci znacznikow nie oceniam - Windows wstal $([int]($teraz - $start).TotalMinutes) min temu (klient odzywa sie do $(Wf-Minut-Po-Starcie) min po starcie)"
    return $w
  }
  $czytelne = @($w.Znaczniki | Where-Object { $_.Czas })
  if ($czytelne.Count -eq 0) {
    $pk = Plik-Konfiguracji-Wiedzy-Firmy $dom
    $od = $null
    if (Test-Path -LiteralPath $pk) {
      try { $od = Wf-Data "$((Wf-Czytaj-Json $pk).zapisano)" } catch { $od = $null }
      if (-not $od) { $od = (Get-Item -LiteralPath $pk).LastWriteTime }
    }
    if ($od -and ((Wf-Godziny $od $teraz) -ge $prog)) {
      $w.Problemy += "klient Wiedzy firmy nie zostawil ani jednego znacznika od instalacji ($($od.ToString('yyyy-MM-dd HH:mm')), $(Wf-Godziny $od $teraz) h temu) - zadanie WiedzaFirmyKlient nie chodzi albo pada przed zapisem"
    }
    return $w
  }
  $naj = $czytelne | Sort-Object Czas | Select-Object -Last 1
  if ((Wf-Godziny $naj.Czas $teraz) -ge $prog) {
    $w.Problemy += "klient Wiedzy firmy nie odezwal sie od $(Wf-Godziny $naj.Czas $teraz) h (ostatni znacznik: $($naj.Krok) $($naj.Czas.ToString('yyyy-MM-dd HH:mm'))) - zadanie WiedzaFirmyKlient nie chodzi"
    return $w
  }
  foreach ($z in $czytelne) {
    if ((Wf-Kroki-Cykliczne) -notcontains $z.Krok) { continue }
    $h = Wf-Godziny $z.Czas $teraz
    if ($h -ge $prog) { $w.Problemy += "krok '$($z.Krok)' nie chodzi od $h h (ostatnio $($z.Czas.ToString('yyyy-MM-dd HH:mm')), prog $prog h)" }
  }
  return $w
}

# ---------------------------------------------------------------- pytanie po aktualizacji

# Stan pytania (plik "klucz: wartosc"): pokazane (kiedy okno ostatnio wstalo), odpowiedz (dodaj /
# nie-teraz / zamkniete / dodaj-blad), kiedy, powod. Nieczytelny plik = pusty stan + Blad.
function Stan-Pytania-Wiedzy-Firmy([string]$dom) {
  $p = Plik-Pytania-Wiedzy-Firmy $dom
  $k = [ordered]@{}
  $blad = ''
  if (Test-Path -LiteralPath $p) {
    try {
      $bajty = [System.IO.File]::ReadAllBytes($p)
      if ([Array]::IndexOf($bajty, [byte]0) -ge 0) { throw 'plik zawiera bajty 0x00' }
      foreach ($l in ((New-Object System.Text.UTF8Encoding($false)).GetString($bajty) -split "`r?`n")) {
        $m = [regex]::Match($l, '^\s*([a-z_]+)\s*:\s*(.*?)\s*$')
        if ($m.Success) { $k[$m.Groups[1].Value] = $m.Groups[2].Value }
      }
    } catch { $blad = "nie umiem odczytac $p : $($_.Exception.Message)" }
  }
  return [pscustomobject]@{ Plik = $p; Klucze = $k; Blad = $blad }
}

function Zapisz-Pytanie-Wiedzy-Firmy([string]$dom, [hashtable]$zmiany) {
  $s = Stan-Pytania-Wiedzy-Firmy $dom
  $k = $s.Klucze
  foreach ($n in $zmiany.Keys) { $k[$n] = (("" + $zmiany[$n]) -replace '[\r\n]+', ' ').Trim() }
  $t = (@($k.Keys | ForEach-Object { "${_}: $($k[$_])" }) -join "`r`n") + "`r`n"
  Wf-Zapisz-Atomowo $s.Plik $t
}

# Czy nadzorca ma dzis zapytac "Dodac Wiedze firmy?". Pytac, Powod. Tylko gdy: rejestr czytelny,
# MegaRuchacz nie usuniety, modul "nie zaproponowano", jest rdzen Lore (Wiedza o Tobie albo Lore - bez
# niego instalacja i tak by padla), znane adresy, dzis jeszcze nie pytano i Windows nie wstal przed chwila.
function Czy-Pytac-O-Wiedze-Firmy([string]$dom, [datetime]$teraz = [datetime]::Now, $startSystemu = $null) {
  $w = [pscustomobject]@{ Pytac = $false; Powod = '' }
  $rej = Czytaj-Instalacje $dom
  if ($rej.blad) { $w.Powod = "rejestr instalacji nieczytelny ($($rej.blad))"; return $w }
  if ($rej.baza -eq $false) { $w.Powod = 'MegaRuchacz jest usuniety z tego komputera'; return $w }
  $v = $rej.moduly.wiedzafirmy
  if ($null -ne $v) { $w.Powod = "o Wiedze firmy juz zdecydowano (rejestr: $([bool]$v))"; return $w }
  $wiedza = $rej.moduly.wiedza; $lore = $rej.moduly.lore
  if (-not ((($null -eq $wiedza) -or [bool]$wiedza) -or (($null -eq $lore) -or [bool]$lore))) {
    $w.Powod = 'nie ma Wiedzy o Tobie ani Pamieci rozmow - Wiedza firmy potrzebuje jednej z nich'; return $w
  }
  $a = Adresy-Wiedzy-Firmy $dom
  if (-not $a.Jest) { $w.Powod = "nie znam adresow serwera firmy (MR_WIEDZA_FIRMY_*, lokalne.json pole wiedza_firmy)$(if ($a.Bledy.Count) { ': ' + ($a.Bledy -join '; ') })"; return $w }
  $p = Stan-Pytania-Wiedzy-Firmy $dom
  if ($p.Blad) { $w.Powod = "$($p.Blad) - nie pytam, zeby nie pytac w kolko"; return $w }
  $pok = Wf-Data $p.Klucze['pokazane']
  if ($pok -and ($pok.Date -eq $teraz.Date)) { $w.Powod = "dzis juz pytalem ($($pok.ToString('HH:mm')), odpowiedz: $(if ($p.Klucze['odpowiedz']) { $p.Klucze['odpowiedz'] } else { 'jeszcze brak' }))"; return $w }
  $start = Wf-Rozwiaz-Start $startSystemu
  if ($start -and (($teraz - $start).TotalMinutes -lt (Wf-Minut-Przed-Pytaniem))) {
    $w.Powod = "Windows wstal $([int][math]::Floor(($teraz - $start).TotalMinutes)) min temu - pytam najwczesniej $(Wf-Minut-Przed-Pytaniem) min po starcie"; return $w
  }
  $w.Pytac = $true
  $w.Powod = "Wiedza firmy nie byla jeszcze proponowana$(if ($pok) { ' (ostatnio pytalem ' + $pok.ToString('yyyy-MM-dd') + ', odpowiedz: ' + $p.Klucze['odpowiedz'] + ')' })"
  return $w
}
