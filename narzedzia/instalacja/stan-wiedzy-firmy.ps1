# narzedzia\instalacja\stan-wiedzy-firmy.ps1 - wspolna wiedza o module "Wiedza firmy" (wiedzafirmy:
# klient serwera jfwiedza na tym komputerze). Same definicje, przy wczytaniu niczego nie zmienia.
# Wczytuja go kropka: narzedzia\instalacja\modul-wiedzafirmy.ps1, okno instalatora (instalator\okno.ps1),
# cykl dzienny (narzedzia\cykl-dzienny.ps1 - alarm znacznikow), nadzorca (zasobnik\nadzorca\dozor.ps1 -
# pytanie po aktualizacji, stan-alarmy.ps1 - alarm) i okno pytania (zasobnik\nadzorca\pytanie-wiedza-firmy.ps1).
# Potrzebuje umowy rejestru (stan.ps1 obok) - wczytuje ja sam, gdy jej jeszcze nie ma.
# Stale sa funkcjami, nie zmiennymi $script: - ten plik bywa wczytywany wewnatrz funkcji (nadzorca),
# a zakres $script: jest dynamiczny (pulapka opisana w stan.ps1 przy Moduly-MegaRuchacza).
#
# PLIKI KLIENTA (umowa z narzedzia\wiedza-firmy-klient\klient.py, raport K3-Z6; projekt "Wiedza firmy, krok 3", sekcja 2):
#   ~\.claude\mr\wiedza-firmy\konfiguracja.json   OPCJONALNY. Klient ma domyslny adres JFTools w kodzie i sam bierze
#       adres serwera jfwiedza z JFTools (GET client-config). Plik zaklada modul-wiedzafirmy.ps1 TYLKO przy
#       nadpisaniu adresu (ADRESY nizej): { "serwer_url", "jftools_url" (nazwy pol z klient.py), "skad", "zrodlo",
#       "zapisano" }, UTF-8 bez BOM; pola, ktorych modul nie zna, zostaja przy zapisie.
#   ~\.claude\mr\wiedza-firmy\zainstalowano.txt   pisze modul przy Instaluj (czas instalacji) - od niego liczy sie
#       "klient milczy od instalacji", gdy nie ma jeszcze ani jednego znacznika
#   ~\.claude\mr\wiedza-firmy\stan.json           pisze klient; tu tylko odczyt (Stan modulu)
#   ~\.claude\mr\wiedza-firmy\klient.log          pisze klient (do 1 MB, potem zostaje druga polowa): kazdy znacznik
#       to tez linia "<czas ISO> [<krok>] ok: ..." albo "<czas ISO> [<krok>] BLAD: ..." - stad historia kroku
#       (ostatni sukces i bledy z rzedu), ktorej sam znacznik (zawsze tylko ostatni przebieg) nie ma
#   ~\.claude\mr\wiedza-firmy\znaczniki\<krok>.txt  pisze klient, jedna linia "czas|ok|opis" albo
#       "czas|blad|opis" (czas ISO 8601 albo "RRRR-MM-DD GG:MM:SS"). zgloszenie, token, przeglad i wysylka
#       odswiezane przy KAZDYM ticku (takze "czeka na zatwierdzenie" = ok), status tylko przy recznym
#       `klient.py status`, dzienny - poranny automat. Nieswiezosc znacznikow = tick nie chodzi.
#
# ADRESY - tylko NADPISANIE (domyslne zna sam klient, nic nie trzeba ustawiac). Kazdy adres osobno, pierwsze
# zrodlo, ktore go ma:
#   1. parametry -AdresSerwera / -AdresJFTools modulu,
#   2. zmienne srodowiskowe MR_WIEDZA_FIRMY_SERWER / MR_WIEDZA_FIRMY_JFTOOLS,
#   3. pole "wiedza_firmy": { "serwer": "...", "jftools": "..." } ustawien tego komputera
#      ~\.claude\mr\lokalne.json (stan.ps1 Czytaj-Lokalne - plik poza repo),
#   4. dotychczasowa konfiguracja.json (ponowna instalacja, aktualizacja).
# Adres, ktory nie jest http(s), jest pomijany z UWAGA (nie przemilczany).
#
# ALARM Z ZNACZNIKA "blad" (decyzja 2026-10-14; CLAUDE.md projektu: falszywy alarm jest gorszy niz brak
# alarmu). Pojedynczy blad - chwilowy brak sieci, laptop poza biurem (serwer wiedzy stoi w sieci biura) - NIE
# alarmuje: tick za 30 min ponawia sam, a ustalenia czekaja w kolejce. Alarm dopiero, gdy:
#   - blad jest TRWALY (Wf-Blad-Trwaly: komputer zablokowany, 403, odmowa przegladu) - ponowienie go nie naprawi;
#   - albo krok nie mial udanego przebiegu od Wf-Godzin-Bez-Sukcesu (26 h: doba + 2 h zapasu na pozne wlaczenie
#     komputera - ten sam rytm, co nieswiezosc) I od ostatniego sukcesu padl co najmniej Wf-Bledow-Z-Rzedu (4)
#     razy z rzedu (4 ticki co 30 min = 1,5-2 h awarii przy WLACZONYM komputerze). Sam czas nie wystarcza: po
#     weekendzie ostatni sukces ma 60 h, a pierwszy poniedzialkowy tick bez sieci to wciaz chwilowy blad.
# Historia kroku z klient.log; bez niego (albo nieczytelnego) czasu bez sukcesu nie da sie policzyc - wtedy
# tylko Uwaga w Stan, nie alarm.

if (-not (Get-Command Czytaj-Instalacje -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'stan.ps1') }

# Prog nieswiezosci znacznika: "tick" chodzi przy logowaniu (+5 min) i co 30 min, dzienny raz na dobe -
# doba plus 2 h zapasu na pozne wlaczenie komputera. Nizszy prog alarmowalby po kazdej nocy.
function Wf-Godzin-Nieswiezy { return 26 }
# Swiezo po starcie albo wybudzeniu Windows klient nie zdazyl sie jeszcze odezwac (5 min opoznienia przy
# logowaniu + 30 min odstepu + 5 min zapasu) - po weekendzie znacznik ma 60 h i to nie jest awaria.
function Wf-Minut-Po-Starcie { return 40 }
# Kroki, ktore powinny chodzic stale (reszta - zgloszenie, token, przeglad - jest jednorazowa i liczy
# sie tylko jej blad).
function Wf-Kroki-Cykliczne { return @('wysylka', 'dzienny') }
# Progi alarmu z bledu - uzasadnienie w naglowku (ALARM Z ZNACZNIKA "blad").
function Wf-Godzin-Bez-Sukcesu { return 26 }
function Wf-Bledow-Z-Rzedu { return 4 }
# Bledy, ktorych ponowienie nie naprawi (opisy z klient.py: "komputer zablokowany w JFTools", "serwer odmowil
# (zablokowany albo nieznany komputer)", "status 'blocked'", 403, "przeglad odmowil pracy").
function Wf-Blad-Trwaly([string]$opis) { return ("$opis" -match '(?i)zablokowan|blocked|odmowil|odmowa|\b403\b') }
# Nadzorca pyta o modul najwczesniej tyle minut po starcie Windows (ta sama decyzja uzytkownika
# z 2026-10-12, co przy przypomnieniach - stan-terminy.ps1 $MINUT_PO_STARCIE_WINDOWS).
function Wf-Minut-Przed-Pytaniem { return 5 }

function Katalog-Wiedzy-Firmy([string]$dom) { return (Join-Path $dom '.claude\mr\wiedza-firmy') }
function Plik-Konfiguracji-Wiedzy-Firmy([string]$dom) { return (Join-Path (Katalog-Wiedzy-Firmy $dom) 'konfiguracja.json') }
function Plik-Instalacji-Wiedzy-Firmy([string]$dom) { return (Join-Path (Katalog-Wiedzy-Firmy $dom) 'zainstalowano.txt') }
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

# Nadpisania adresow: Serwer, JFTools (pusto = domyslny klienta), Skad (opis zrodel), Nadpisanie ($true, gdy
# ktorys adres przyszedl z parametru, zmiennej albo lokalne.json - wtedy jest co zapisac w konfiguracja.json),
# Bledy (nieczytelne zrodla, zle adresy - meldowane, nie przemilczane).
function Adresy-Wiedzy-Firmy([string]$dom, [string]$serwer = '', [string]$jftools = '') {
  $w = [pscustomobject]@{ Serwer = ''; JFTools = ''; Skad = ''; Nadpisanie = $false; Bledy = @() }
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
  $zKonf = 'dotychczasowa konfiguracja*'
  $w.Nadpisanie = [bool](($skadS -and ($skadS -notlike $zKonf)) -or ($skadJ -and ($skadJ -notlike $zKonf)))
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

# Historia krokow z klient.log (format w naglowku): Jest (log jest), Od (najstarsza czytelna linia), Kroki:
# krok -> { OstatnieOk ([datetime] albo $null), BledowPo (bledy z rzedu po ostatnim sukcesie) }, Blad (nie dalo
# sie przeczytac). Czytane z FileShare.ReadWrite - klient moze akurat dopisywac.
function Historia-Klienta-Wiedzy-Firmy([string]$dom) {
  $w = [pscustomobject]@{ Jest = $false; Od = $null; Kroki = @{}; Blad = '' }
  $p = Join-Path (Katalog-Wiedzy-Firmy $dom) 'klient.log'
  if (-not (Test-Path -LiteralPath $p)) { return $w }
  $w.Jest = $true
  try {
    $fs = [System.IO.File]::Open($p, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    try { $czytnik = New-Object System.IO.StreamReader($fs, (New-Object System.Text.UTF8Encoding($false))); $tekst = $czytnik.ReadToEnd() } finally { $fs.Dispose() }
    foreach ($l in ($tekst -split "`r?`n")) {
      $m = [regex]::Match($l, '^(\d{4}-\d\d-\d\d[T ][\d:.]+)\s+\[([A-Za-z0-9_-]+)\]\s+(ok|BLAD):')
      if (-not $m.Success) { continue }
      $t = Wf-Data $m.Groups[1].Value
      if (-not $t) { continue }
      if (-not $w.Od) { $w.Od = $t }
      $k = $m.Groups[2].Value
      if (-not $w.Kroki.ContainsKey($k)) { $w.Kroki[$k] = [pscustomobject]@{ OstatnieOk = $null; BledowPo = 0 } }
      if ($m.Groups[3].Value -eq 'ok') { $w.Kroki[$k].OstatnieOk = $t; $w.Kroki[$k].BledowPo = 0 } else { $w.Kroki[$k].BledowPo++ }
    }
  } catch { $w.Blad = "nie umiem przeczytac $p : $($_.Exception.Message)" }
  return $w
}

# Kiedy modul zainstalowano: zainstalowano.txt, a ze starszej instalacji - pole zapisano konfiguracji. $null = nie wiem.
function Czas-Instalacji-Wiedzy-Firmy([string]$dom) {
  $p = Plik-Instalacji-Wiedzy-Firmy $dom
  if (Test-Path -LiteralPath $p) {
    try { $t = Wf-Data ([System.IO.File]::ReadAllText($p)); if ($t) { return $t } } catch { $null = $_ }   # zepsuty - probujemy konfiguracje
  }
  $pk = Plik-Konfiguracji-Wiedzy-Firmy $dom
  if (Test-Path -LiteralPath $pk) {
    try { $t = Wf-Data "$((Wf-Czytaj-Json $pk).zapisano)"; if ($t) { return $t } } catch { $null = $_ }
  }
  return $null
}

# Ocena znacznikow: Znaczniki (lista), Problemy (zdania - kazde to ALARM), Sprawdzone (czy liczono czas - swiezo
# po starcie Windows nie), Uwaga (co oceniono ostroznie i dlaczego). Progi i ich uzasadnienie - naglowek.
function Ocena-Znacznikow-Wiedzy-Firmy([string]$dom, [datetime]$teraz = [datetime]::Now, $startSystemu = $null) {
  $w = [pscustomobject]@{ Znaczniki = @(); Problemy = @(); Sprawdzone = $true; Uwaga = '' }
  $uwagi = @()
  $prog = Wf-Godzin-Nieswiezy
  try { $w.Znaczniki = Czytaj-Znaczniki-Wiedzy-Firmy $dom }
  catch { $w.Problemy += "nie umiem przeczytac znacznikow klienta Wiedzy firmy: $($_.Exception.Message)"; return $w }
  $bledne = @()
  foreach ($z in $w.Znaczniki) {
    if ($z.Blad) { $w.Problemy += "znacznik kroku '$($z.Krok)' jest nieczytelny ($($z.Plik)): $($z.Blad)"; continue }
    if (@('blad', 'error') -notcontains $z.Stan) { continue }
    if (Wf-Blad-Trwaly $z.Opis) { $w.Problemy += "krok '$($z.Krok)' ma blad trwaly (ponowienie go nie naprawi) $($z.Czas.ToString('yyyy-MM-dd HH:mm')): $($z.Opis)"; continue }
    $bledne += $z
  }
  $start = Wf-Rozwiaz-Start $startSystemu
  if ($start -and (($teraz - $start).TotalMinutes -lt (Wf-Minut-Po-Starcie))) {
    $w.Sprawdzone = $false
    $w.Uwaga = "czasu bez sukcesu i nieswiezosci znacznikow nie oceniam - Windows wstal $([int]($teraz - $start).TotalMinutes) min temu (klient odzywa sie do $(Wf-Minut-Po-Starcie) min po starcie)"
    return $w
  }
  $instalacja = Czas-Instalacji-Wiedzy-Firmy $dom
  if ($bledne.Count -gt 0) {
    $hist = Historia-Klienta-Wiedzy-Firmy $dom
    foreach ($z in $bledne) {
      if ((-not $hist.Jest) -or $hist.Blad) {
        $uwagi += "krok '$($z.Krok)': chwilowy blad ($($z.Opis)); $(if ($hist.Blad) { $hist.Blad } else { 'nie ma klient.log' }) - nie wiem, od kiedy pada, wiec nie alarmuje"
        continue
      }
      $h = $hist.Kroki[$z.Krok]
      $ile = if ($h) { [int]$h.BledowPo } else { 1 }
      $od = $null; $jak = ''
      if ($h -and $h.OstatnieOk) { $od = $h.OstatnieOk; $jak = "ostatni sukces $($od.ToString('yyyy-MM-dd HH:mm'))" }
      else {
        $od = @(@($hist.Od, $instalacja) | Where-Object { $_ } | Sort-Object | Select-Object -First 1)[0]
        if ($od) { $jak = "ani jednego sukcesu od $($od.ToString('yyyy-MM-dd HH:mm'))" }
      }
      if ($od -and ((Wf-Godziny $od $teraz) -ge (Wf-Godzin-Bez-Sukcesu)) -and ($ile -ge (Wf-Bledow-Z-Rzedu))) {
        $w.Problemy += "krok '$($z.Krok)' nie ma udanego przebiegu od $(Wf-Godziny $od $teraz) h ($jak, bledow z rzedu: $ile; ostatni: $($z.Opis))"
      } else {
        $uwagi += "krok '$($z.Krok)': chwilowy blad ($($z.Opis)) - bledow z rzedu $ile, $(if ($jak) { $jak } else { 'bez historii' }); alarm po $(Wf-Godzin-Bez-Sukcesu) h bez sukcesu i $(Wf-Bledow-Z-Rzedu) bledach z rzedu"
      }
    }
  }
  $w.Uwaga = ($uwagi -join '; ')
  $czytelne = @($w.Znaczniki | Where-Object { $_.Czas })
  if ($czytelne.Count -eq 0) {
    if ($instalacja -and ((Wf-Godziny $instalacja $teraz) -ge $prog)) {
      $w.Problemy += "klient Wiedzy firmy nie zostawil ani jednego znacznika od instalacji ($($instalacja.ToString('yyyy-MM-dd HH:mm')), $(Wf-Godziny $instalacja $teraz) h temu) - zadanie WiedzaFirmyKlient nie chodzi albo pada przed zapisem"
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
# niego instalacja i tak by padla), dzis jeszcze nie pytano i Windows nie wstal przed chwila. Adresow nie
# trzeba (domyslne zna klient).
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
