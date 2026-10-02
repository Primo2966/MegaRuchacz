# narzedzia\instalacja\wspolne.ps1 - wspolna czesc skryptow modulow (modul-*.ps1) i zaleznosci.ps1.
#
# Wczytywany kropka PO param() skryptu:  . (Join-Path $PSScriptRoot 'wspolne.ps1')
# Same definicje i pusty stan wyjscia; przy wczytaniu niczego nie zmienia. Wczytuje tez
# stan.ps1 (rejestr modulow) i lore-czesci.ps1 (czesci Lore) z tego samego katalogu.
#
# UMOWA WYJSCIA - czyta ja okno instalatora (instalator\), dlatego jest stala:
#   KROK: <tekst>    jeden krok po polsku dla laika; w trybie -Proba z przedrostkiem "[proba] "
#   UWAGA: <tekst>   cos nie gra, ale nie przerywa (brak opcjonalnego programu, resztki plikow)
#   WYNIK: {json}    ZAWSZE ostatnia linia: JSON w jednej linii, czysty ASCII (reszta jako \uXXXX).
#                    Pola: modul, akcja, ok, komunikat, proba, kroki[], uwagi[], programy[],
#                    brakuje[], zainstalowany, dziala, problemy[], rejestr (+ pola modulu)
# Kod wyjscia: 0 = ok, 1 = nie. Brak linii WYNIK (np. zly parametr, PowerShell nie wstal) = porazka.
# Teksty sa bez polskich znakow (dzialaja w kazdej stronie kodowej); stdout idzie w UTF-8,
# wiec sciezki z polskimi literami przechodza cale, jesli okno czyta wyjscie jako UTF-8.
# Linie ida przez [Console]::Out, nie przez potok: funkcja zwracajaca wartosc nie moze wciagnac
# linii KROK do swojego wyniku (wtedy znikalaby z ekranu i psula wynik).

$script:MR = [ordered]@{
  modul    = ""
  akcja    = ""
  proba    = $false
  kroki    = New-Object System.Collections.ArrayList
  uwagi    = New-Object System.Collections.ArrayList
  problemy = New-Object System.Collections.ArrayList
  programy = New-Object System.Collections.ArrayList
  brakuje  = New-Object System.Collections.ArrayList
}

. (Join-Path $PSScriptRoot "stan.ps1")
. (Join-Path $PSScriptRoot "lore-czesci.ps1")

# ---------------------------------------------------------------- wyjscie

function Jedna-Linia([string]$t) { return (($t -replace "[\r\n]+", " ").Trim()) }

function Pisz-Linie([string]$t) { [Console]::Out.WriteLine($t) }

function Krok([string]$t) { $t = Jedna-Linia $t; [void]$script:MR.kroki.Add($t); Pisz-Linie "KROK: $t" }
function Plan([string]$t) { Krok "[proba] $t" }
function Ostrzezenie([string]$t) { $t = Jedna-Linia $t; [void]$script:MR.uwagi.Add($t); Pisz-Linie "UWAGA: $t" }
# Powod, dla ktorego modul nie dziala (pole "problemy" w Stan) - bez osobnej linii na ekranie.
function Problem([string]$t) { [void]$script:MR.problemy.Add((Jedna-Linia $t)) }

function Json-Ascii([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  foreach ($c in $s.ToCharArray()) {
    if ([int]$c -gt 127) { [void]$sb.AppendFormat('\u{0:x4}', [int]$c) } else { [void]$sb.Append($c) }
  }
  return $sb.ToString()
}

# Ostatnia linia wyjscia i koniec skryptu. $dodatkowe - hashtable z polami modulu.
function Zakoncz([bool]$ok, [string]$komunikat, $dodatkowe = $null) {
  $w = [ordered]@{
    modul         = $script:MR.modul
    akcja         = $script:MR.akcja
    ok            = $ok
    komunikat     = (Jedna-Linia $komunikat)
    proba         = [bool]$script:MR.proba
    kroki         = [object[]]@($script:MR.kroki)
    uwagi         = [object[]]@($script:MR.uwagi)
    programy      = [object[]]@($script:MR.programy)
    brakuje       = [object[]]@($script:MR.brakuje)
    zainstalowany = $null
    dziala        = $null
    problemy      = [object[]]@($script:MR.problemy)
    rejestr       = $null
  }
  if ($dodatkowe) { foreach ($k in @($dodatkowe.Keys)) { $w[$k] = $dodatkowe[$k] } }
  $json = ConvertTo-Json -InputObject $w -Depth 8 -Compress
  Pisz-Linie ("WYNIK: " + (Json-Ascii $json))
  [Console]::Out.Flush()
  # strona kodowa konsoli wraca do poprzedniej - uruchomiony z okna PowerShella skrypt nie moze
  # zostawic go w UTF-8 (to ustawienie calej konsoli, nie procesu)
  if ($script:MR_StareKodowanie) {
    try { [Console]::OutputEncoding = $script:MR_StareKodowanie } catch { [Console]::Error.WriteLine("nie przywrocilem kodowania konsoli: $($_.Exception.Message)") }
  }
  if ($ok) { exit 0 }
  exit 1
}

# Poczatek kazdego skryptu modulu: nazwa, akcja, kodowanie wyjscia, sprawdzenie katalogow.
# Zwraca rozwiazane sciezki (Zrodlo, KatalogDomowy) - wolajacy przypisuje je sobie.
function Start-Modul([string]$nazwa, [string]$akcja, [bool]$proba, [string]$zrodlo, [string]$dom, [string[]]$akcje = @("Instaluj", "Usun", "Stan")) {
  $script:MR.modul = $nazwa
  $script:MR.akcja = $akcja
  $script:MR.proba = $proba
  $bladKodowania = $null
  try {
    $script:MR_StareKodowanie = [Console]::OutputEncoding
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
  } catch { $bladKodowania = $_.Exception.Message }
  if ($bladKodowania) { Ostrzezenie "nie udalo sie przestawic wyjscia na UTF-8 ($bladKodowania) - polskie litery w sciezkach moga wyjsc znieksztalcone" }
  if ($akcje -notcontains $akcja) { Zakoncz $false "nieznana akcja '$akcja' - dozwolone: $($akcje -join ', ') (parametr -Akcja)" }
  if (-not $zrodlo -or -not (Test-Path -LiteralPath (Join-Path $zrodlo "narzedzia\straznik-zasad.ps1"))) {
    Zakoncz $false "nie ma repozytorium MegaRuchacza w '$zrodlo' (brak narzedzia\straznik-zasad.ps1) - podaj -Zrodlo"
  }
  if (-not $dom -or -not (Test-Path -LiteralPath $dom)) { Zakoncz $false "nie ma katalogu domowego '$dom' (parametr -KatalogDomowy)" }
  $zrodlo = (Resolve-Path -LiteralPath $zrodlo).Path.TrimEnd('\')
  $dom = (Resolve-Path -LiteralPath $dom).Path.TrimEnd('\')
  if ($proba) { Krok "TRYB PROBY - nic nie zmieniam, tylko pokazuje kroki" }
  Ustaw-Katalog-Domowy $dom
  return [pscustomobject]@{ Zrodlo = $zrodlo; KatalogDomowy = $dom }
}

# Katalog domowy inny niz biezacego uzytkownika (testy na kopii domu): procesy potomne - Python
# Lore, claude, skrypty bez -KatalogDomowy - maja liczyc sciezki od TEGO katalogu, tak samo jak
# ten skrypt. Bez tego Python Lore czytalby prawdziwe ~\.claude, a kopia testowa - prawdziwe dane.
#
# Podstawiony dom musi miec AppData\Local i AppData\Roaming: Windows rozwija je z %USERPROFILE%,
# a [Environment]::GetFolderPath zwraca PUSTY napis, gdy katalogu nie ma - PowerShell zapisal wtedy
# swoja pamiec podreczna modulow (Microsoft\Windows\PowerShell\ModuleAnalysisCache) wzgledem
# katalogu roboczego, czyli do repo (zlapane w testach 2026-10-02).
function Ustaw-Katalog-Domowy([string]$dom) {
  if ($dom -ine ([Environment]::GetFolderPath("UserProfile")).TrimEnd('\')) {
    foreach ($k in @("AppData\Local", "AppData\Roaming")) {
      $p = Join-Path $dom $k
      if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
    }
  }
  if ($env:USERPROFILE -and ($env:USERPROFILE.TrimEnd('\') -ieq $dom)) { return }
  $env:USERPROFILE = $dom
  $env:HOME = $dom
  if ($dom -match '^[A-Za-z]:') { $env:HOMEDRIVE = $dom.Substring(0, 2); $env:HOMEPATH = $dom.Substring(2) }
  Krok "katalog domowy: $dom (inny niz biezacego uzytkownika - procesy potomne licza sciezki od niego)"
}

# ---------------------------------------------------------------- programy

function Dodaj-Do-Path([string]$katalog) {
  if (-not $katalog) { return }
  $czesci = @($env:PATH -split ';' | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') })
  if ($czesci -notcontains $katalog.TrimEnd('\')) { $env:PATH = $katalog + ';' + $env:PATH }
}

# Znane miejsca instalacji - takze te, pod ktore zaleznosci.ps1 kladzie wersje przenosne.
# Proces okna instalatora moze miec PATH sprzed instalacji programu, dlatego nie tylko PATH.
function Kandydaci-Programu([string]$n) {
  $la = $env:LOCALAPPDATA; $ad = $env:APPDATA; $up = $env:USERPROFILE; $pf = $env:ProgramFiles
  $mr = if ($la) { Join-Path $la "MegaRuchacz" } else { $null }
  $wg = if ($la) { Join-Path $la "Microsoft\WinGet" } else { $null }
  $k = switch ($n) {
    "git"      { @("$mr\git\cmd\git.exe", "$wg\Links\git.exe", "$wg\Packages\Git.MinGit_*\cmd\git.exe", "$la\Programs\Git\cmd\git.exe", "$pf\Git\cmd\git.exe") }
    "node"     { @("$mr\node\node.exe", "$wg\Links\node.exe", "$wg\Packages\OpenJS.NodeJS.LTS_*\node-v*\node.exe", "$pf\nodejs\node.exe") }
    "bash"     { @("$la\Programs\Git\bin\bash.exe", "$pf\Git\bin\bash.exe") }
    "claude"   { @("$up\.local\bin\claude.exe", "$ad\npm\claude.cmd") }
    "codex"    { @("$ad\npm\codex.cmd", "$la\Programs\OpenAI\Codex\bin\codex.exe") }
    "opencode" { @("$ad\npm\opencode.cmd", "$up\.opencode\bin\opencode.exe") }
    "winget"   { @("$la\Microsoft\WindowsApps\winget.exe") }
    default    { @() }
  }
  # kandydat z pustej zmiennej (np. "\Git\cmd\git.exe") wskazywalby korzen biezacego dysku
  return @($k | Where-Object { $_ -match '^([A-Za-z]:\\|\\\\)' })
}

# Pelna sciezka programu albo $null. Znaleziony poza PATH trafia na PATH TEGO procesu, zeby
# skrypty potomne (straznik, skille.ps1) znalazly go golym "git".
function Znajdz-Program([string]$nazwa) {
  if ($nazwa -eq "uv") {
    $u = Znajdz-Uv
    if ($u) { Dodaj-Do-Path (Split-Path -Parent $u) }
    return $u
  }
  $cmd = Get-Command $nazwa -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return $cmd.Source }
  foreach ($kand in (Kandydaci-Programu $nazwa)) {
    $traf = Get-ChildItem -Path $kand -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($traf) { Dodaj-Do-Path (Split-Path -Parent $traf.FullName); return $traf.FullName }
  }
  return $null
}

# Python >= 3.12 przez uv (uv zna swoje instalacje Pythona; "python" w PATH bywa tylko aliasem Sklepu).
function Znajdz-Pythona-Uv([string]$uv) {
  if (-not $uv) { return $null }
  $stare = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  try { $global:LASTEXITCODE = 0; $wy = & $uv python find ">=3.12" 2>&1; $kod = $LASTEXITCODE } finally { $ErrorActionPreference = $stare }
  if ($kod -ne 0) { return $null }
  return ((@($wy | ForEach-Object { "$_" }) | Where-Object { $_.Trim() } | Select-Object -Last 1))
}

$script:OpisyProgramow = @{
  uv       = "menedzer srodowisk Pythona (Lore i cykl wiedzy)"
  python   = "Python 3.12 (Lore i cykl wiedzy)"
  git      = "git (aktualizacje MegaRuchacza, skille)"
  node     = "Node.js (hooki: przypomnienie i rejestr workerow)"
  bash     = "Git Bash (powloka hookow Claude Code)"
  claude   = "Claude Code CLI (wylawianie faktow z rozmow)"
  codex    = "Codex CLI (wylawianie faktow z rozmow)"
  opencode = "opencode"
}

# Sprawdza programy z listy i zapisuje je do pola "programy" wyniku. Wymagany a brakujacy trafia
# do "brakuje" (okno instalatora podaje te liste do zaleznosci.ps1). Zwraca hashtable nazwa->sciezka.
function Sprawdz-Programy([string[]]$wymagane, [string[]]$opcjonalne = @()) {
  $znalezione = @{}
  foreach ($n in @($wymagane + $opcjonalne)) {
    if ($znalezione.ContainsKey($n)) { continue }
    $wym = $wymagane -contains $n
    if ($n -eq "python") {
      $uv = if ($znalezione["uv"]) { $znalezione["uv"] } else { Znajdz-Program "uv" }
      $sc = Znajdz-Pythona-Uv $uv
    } else {
      $sc = Znajdz-Program $n
    }
    $znalezione[$n] = $sc
    [void]$script:MR.programy.Add([ordered]@{ nazwa = $n; jest = [bool]$sc; wymagany = $wym; sciezka = $sc; po_co = $script:OpisyProgramow[$n] })
    if (-not $sc -and $wym) { [void]$script:MR.brakuje.Add($n) }
  }
  return $znalezione
}

function Odmowa-Brak-Programow {
  $lista = @($script:MR.brakuje)
  if ($lista.Count -eq 0) { return }
  $opis = ($lista | ForEach-Object { "$_ - $($script:OpisyProgramow[$_])" }) -join "; "
  Zakoncz $false ("brakuje programow: $opis. Zainstaluj je: narzedzia\instalacja\zaleznosci.ps1 -Akcja Instaluj -Potrzebne " + ($lista -join ","))
}

# ---------------------------------------------------------------- rejestr modulow

# Rejestr do zmian. Nieczytelny = odmowa wszystkiego (stan.ps1: przy bledzie NIC nie wolno
# odinstalowac, tylko alarmowac). Zwraca obiekt z Czytaj-Instalacje.
function Rejestr-Do-Zmian([string]$dom) {
  $s = Czytaj-Instalacje $dom
  if ($s.blad) {
    Zakoncz $false "nic nie zmieniam: $($s.blad). Przywroc ten plik albo go usun (wtedy MegaRuchacz uzna, ze wszystkie moduly sa wlaczone, i mozna wybrac od nowa)." @{ rejestr_blad = $s.blad }
  }
  return $s
}

function Rejestr-Do-Wyniku($s, [string]$dom) {
  if ($null -eq $s) { return $null }
  $m = [ordered]@{}
  foreach ($n in (Moduly-MegaRuchacza)) { $m[$n] = [bool]$s.moduly.$n }
  return [ordered]@{ moduly = $m; zrodlo = $s.zrodlo; blad = $s.blad; plik = (Sciezka-Instalacji $dom) }
}

# Zapis jak Ustaw-Modul (stan.ps1), z jednym dodatkiem. Gdy rejestru jeszcze nie ma (instalacja
# sprzed instalatora), pierwszy zapis go ZAKLADA - a narzedzia\kopia-zapasowa.ps1 z rejestrem bez
# pola "kopia" konczy sie bledem (P59d: bez rejestru bierze kopia-zapasowa-domyslne.json). Wlaczona
# dotad kopia stanelaby wiec przez instalacje zupelnie innego modulu. Dlatego przy zakladaniu
# rejestru z wlaczona kopia pole "kopia" dostaje te same ustawienia domyslne - kopia idzie jak szla.
function Zapisz-Modul([string]$nazwa, [bool]$wlaczony, [string]$dom) {
  $slowo = if ($wlaczony) { "wlaczony" } else { "wylaczony" }
  if ($script:MR.proba) { Plan "rejestr modulow: $nazwa = $slowo"; return }
  if ($script:MR_MODULY -notcontains $nazwa) { throw "nieznany modul MegaRuchacza: $nazwa" }
  $s = Czytaj-Instalacje $dom
  if ($s.blad) { throw $s.blad }
  $zakladam = ($s.zrodlo -eq "domyslne")
  $s.moduly | Add-Member -NotePropertyName $nazwa -NotePropertyValue $wlaczony -Force
  if ($zakladam -and [bool]$s.moduly.kopia -and -not $s.kopia) {
    $plikDom = Join-Path $Zrodlo "narzedzia\kopia-zapasowa-domyslne.json"
    try {
      $d = (New-Object System.Text.UTF8Encoding($false)).GetString([System.IO.File]::ReadAllBytes($plikDom)).TrimStart([char]0xFEFF) | ConvertFrom-Json
      $s | Add-Member -NotePropertyName kopia -NotePropertyValue ([pscustomobject]@{ zrodla = @($d.zrodla); cel = $d.cel; wykluczenia = @($d.wykluczenia) }) -Force
      Krok "zakladam rejestr modulow, a kopia zapasowa jest wlaczona - jej dotychczasowe ustawienia (kopia-zapasowa-domyslne.json: cel $($d.cel)) ida do pola kopia, kopia idzie dalej jak szla"
    } catch {
      Ostrzezenie "zakladam rejestr modulow bez ustawien kopii (nie odczytalem $plikDom : $($_.Exception.Message)) - kopia zapasowa zatrzyma sie z bledem, dopoki nie wybierzesz jej celu w oknie instalatora"
    }
  }
  Zapisz-Instalacje $s $dom
  Krok "rejestr modulow: $nazwa $slowo ($(Sciezka-Instalacji $dom))"
}

# ---------------------------------------------------------------- skrypty potomne

# Argument wiersza polecen wg regul CommandLineToArgvW (te stosuje powershell.exe -File).
function Cytuj-Argument([string]$a) {
  if ($a -eq "") { return '""' }
  if ($a -notmatch '[\s"]') { return $a }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  $ukosniki = 0
  foreach ($c in $a.ToCharArray()) {
    if ($c -eq '\') { $ukosniki++; continue }
    if ($c -eq '"') { [void]$sb.Append(('\' * ($ukosniki * 2 + 1)) + '"'); $ukosniki = 0; continue }
    if ($ukosniki) { [void]$sb.Append('\' * $ukosniki); $ukosniki = 0 }
    [void]$sb.Append($c)
  }
  if ($ukosniki) { [void]$sb.Append('\' * ($ukosniki * 2)) }
  [void]$sb.Append('"')
  return $sb.ToString()
}

# Strona kodowa, w ktorej pisze potomny PowerShell na przekierowane wyjscie: nowa (ukryta) konsola
# dostaje systemowa strone OEM - zmierzone 2026-10-02: 437 przy polskiej kulturze uzytkownika,
# wiec CultureInfo.OEMCodePage (852) dawalo krzaki. Polskie litery spoza tej strony konsola
# zamienia na najblizsze bez ogonkow - to strata po stronie potomka, nie odczytu.
function Kodowanie-Konsoli {
  try {
    $cp = [int](Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -ErrorAction Stop).OEMCP
    return [System.Text.Encoding]::GetEncoding($cp)
  } catch {
    return [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
  }
}

# Uruchamia skrypt PowerShella w osobnym procesie bez okna (CreateNoWindow), z przechwyconym
# wyjsciem. Osobny proces, bo te skrypty koncza sie przez exit, definiuja wlasne Krok/Blad
# i ustawiaja $ErrorActionPreference. Zwraca Kod (-1 = nie zdazyl albo nie wstal) i Tekst.
function Uruchom-Skrypt([string]$skrypt, [string[]]$argumenty, [int]$sekundy = 900) {
  if (-not (Test-Path -LiteralPath $skrypt)) { return [pscustomobject]@{ Kod = -1; Tekst = "nie ma pliku $skrypt" } }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
  $psi.Arguments = (@("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", (Cytuj-Argument $skrypt)) +
                    @($argumenty | ForEach-Object { Cytuj-Argument $_ })) -join " "
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $enc = Kodowanie-Konsoli
  $psi.StandardOutputEncoding = $enc
  $psi.StandardErrorEncoding = $enc
  try { $p = [System.Diagnostics.Process]::Start($psi) }
  catch { return [pscustomobject]@{ Kod = -1; Tekst = "nie udalo sie uruchomic PowerShella: $($_.Exception.Message)" } }
  $wy = $p.StandardOutput.ReadToEndAsync()
  $bl = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($sekundy * 1000)) {
    & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null
    return [pscustomobject]@{ Kod = -1; Tekst = "$skrypt nie skonczyl w $sekundy s - przerwany" }
  }
  $p.WaitForExit()
  $tekst = ($wy.Result + "`n" + $bl.Result).Trim()
  return [pscustomobject]@{ Kod = $p.ExitCode; Tekst = $tekst }
}

# Program (exe) bez okna, z limitem czasu i przechwyconym wyjsciem (winget potrafi zawisnac na
# pytaniu, ktorego w ukrytym oknie nikt nie zobaczy). Zwraca Kod (-1 = nie zdazyl / nie wstal) i Tekst.
function Uruchom-Program([string]$program, [string[]]$argumenty, [int]$sekundy = 600) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $program
  $psi.Arguments = (@($argumenty | ForEach-Object { Cytuj-Argument $_ })) -join " "
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
  $psi.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
  try { $p = [System.Diagnostics.Process]::Start($psi) }
  catch { return [pscustomobject]@{ Kod = -1; Tekst = "nie udalo sie uruchomic ${program}: $($_.Exception.Message)" } }
  $wy = $p.StandardOutput.ReadToEndAsync()
  $bl = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($sekundy * 1000)) {
    & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null
    return [pscustomobject]@{ Kod = -1; Tekst = "$program nie skonczyl w $sekundy s - przerwany" }
  }
  $p.WaitForExit()
  return [pscustomobject]@{ Kod = $p.ExitCode; Tekst = ($wy.Result + "`n" + $bl.Result).Trim() }
}

# Najbardziej mowiaca linia wyjscia skryptu potomnego: pierwsza z bledem, inaczej ostatnia niepusta.
function Sedno([string]$tekst) {
  $linie = @($tekst -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  # "BLAD" - takze ten z ogonkami ze skille.ps1: konsola potomka zamienia go na litery bez ogonkow
  $blad = $linie | Where-Object { $_ -match '^(BLAD|ERROR)|Exception|nie udalo|nie powiod' } | Select-Object -First 1
  if ($blad) { return $blad }
  return ($linie | Select-Object -Last 1)
}

# Zasady dla AI dogrywa/usuwa wpisz-zasady.ps1 wedlug rejestru (od zmian P59a; wczesniej wpisuje
# caly blok). Wolane po kazdej zmianie rejestru. Zwraca $true, gdy przeszlo.
function Wpisz-Zasady([string]$zrodlo, [string]$dom, [switch]$Usun) {
  $co = if ($Usun) { "zdjalby bloki zasad MegaRuchacza" } else { "dogralby bloki zasad dla AI wedlug rejestru" }
  if ($script:MR.proba) { Plan "narzedzia\wpisz-zasady.ps1 $co (~\.claude\CLAUDE.md, ~\.codex\AGENTS.md)"; return $true }
  $a = @("-Zrodlo", $zrodlo, "-KatalogDomowy", $dom)
  if ($Usun) { $a += "-Usun" }
  $w = Uruchom-Skrypt (Join-Path $zrodlo "narzedzia\wpisz-zasady.ps1") $a 180
  if ($w.Kod -ne 0) { Ostrzezenie "zasady dla AI nie zostaly uaktualnione - wpisz-zasady.ps1 zakonczyl sie kodem $($w.Kod): $(Sedno $w.Tekst)"; return $false }
  $slowo = if ($Usun) { "zdjete" } else { "uaktualnione wedlug rejestru" }
  Krok "zasady dla AI $slowo (~\.claude\CLAUDE.md, ~\.codex\AGENTS.md)"
  return $true
}

# Hooki globalne Claude Code (~\.claude\settings.json) uklada straznik - tym samym kodem, ktorym
# pilnuje ich przy kazdym starcie sesji, wiec ponowne wywolanie naprawia zamiast dublowac.
# Od zmian P59a komplet hookow zalezy od rejestru (straznik SessionStart zawsze - modul baza).
function Napraw-Hooki([string]$zrodlo, [string]$dom, [switch]$Usun) {
  $tryb = if ($Usun) { "-UsunGlobalne" } else { "-NaprawGlobalne" }
  if ($script:MR.proba) {
    $co = if ($Usun) { "zdjalby hooki MegaRuchacza" } else { "ulozylby hooki MegaRuchacza wedlug rejestru" }
    Plan "straznik-zasad.ps1 $tryb $co w ~\.claude\settings.json (cudze hooki zostaja)"
    return [pscustomobject]@{ Ok = $true; Tekst = "" }
  }
  $w = Uruchom-Skrypt (Join-Path $zrodlo "narzedzia\straznik-zasad.ps1") @($tryb, "-Zrodlo", $zrodlo, "-KatalogDomowy", $dom) 180
  if ($w.Kod -ne 0) { return [pscustomobject]@{ Ok = $false; Tekst = $w.Tekst } }
  return [pscustomobject]@{ Ok = $true; Tekst = $w.Tekst }
}

# Po zmianie rejestru: hooki i bloki zasad maja odpowiadac nowemu wyborowi (straznik i wpisz-zasady
# czytaja rejestr). Zwraca $true, gdy oba przeszly; porazka kazdego to UWAGA z powodem.
function Po-Zmianie-Rejestru([string]$zrodlo, [string]$dom) {
  $h = Napraw-Hooki $zrodlo $dom
  $ok = $true
  if (-not $h.Ok) { $ok = $false; Ostrzezenie "hooki w ~\.claude\settings.json nie zostaly ulozone wedlug rejestru: $(Sedno $h.Tekst)" }
  elseif (-not $script:MR.proba) { Krok "hooki MegaRuchacza ulozone wedlug rejestru (~\.claude\settings.json)" }
  if (-not (Wpisz-Zasady $zrodlo $dom)) { $ok = $false }
  return $ok
}

# Ile hookow na danym zdarzeniu ma polecenie pasujace do wzorca. -1 = plik nie jest JSON-em.
function Policz-Hooki([string]$plik, [string]$zdarzenie, [string]$wzor) {
  if (-not (Test-Path -LiteralPath $plik)) { return 0 }
  try {
    $raw = [System.IO.File]::ReadAllText($plik).TrimStart([char]0xFEFF)
    if (-not $raw.Trim()) { return 0 }
    $s = $raw | ConvertFrom-Json
  } catch { return -1 }
  if ($null -eq $s.hooks -or -not ($s.hooks.PSObject.Properties.Name -contains $zdarzenie)) { return 0 }
  $n = 0
  foreach ($g in @($s.hooks.$zdarzenie)) {
    foreach ($h in @($g.hooks)) { if ($h -and ("" + $h.command) -match $wzor) { $n++ } }
  }
  return $n
}

# ---------------------------------------------------------------- drobne

# Zadania Harmonogramu zakladane przez cudze skrypty (nazwy siedza tez tam - te musza sie zgadzac).
$script:ZadanieNadzorcy = "MegaRuchaczNadzorca"   # zasobnik\zainstaluj-zasobnik.ps1
$script:ZadanieKosztu   = "LoreKoszt"             # narzedzia\koszt-pamieci.ps1 (koszt\pomiar-dzienny.ps1)
$script:ZadanieKopii    = "MegaRuchaczKopia"      # narzedzia\kopia-zapasowa.ps1

# Linie "UWAGA ..." i "BLAD ..." z wyjscia skryptu potomnego ida dalej jako UWAGA - nie gina.
function Przekaz-Uwagi([string]$tekst, [string]$skad) {
  foreach ($l in @($tekst -split "`r?`n")) {
    $m = [regex]::Match($l, '^\s*(UWAGA|BLAD)\s*:?\s+(.+)$')
    if ($m.Success) { Ostrzezenie "${skad}: $($m.Groups[2].Value.Trim())" }
  }
}

# Procesy nadzorcy z TEGO repo (po pelnej sciezce nadzorca.ps1 w wierszu polecen). $null = nie
# mialem jak sprawdzic - to co innego niz "nie chodzi" (pusta lista).
function Procesy-Nadzorcy-Repo([string]$zrodlo) {
  $sc = Join-Path $zrodlo "zasobnik\nadzorca.ps1"
  try {
    return ,@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop |
              Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($sc, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
  } catch {
    Ostrzezenie "nie moge zajrzec do listy procesow: $($_.Exception.Message)"
    return $null
  }
}

function Zadanie-Jest([string]$nazwa) {
  if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return $null }
  return [bool](Get-ScheduledTask -TaskName $nazwa -ErrorAction SilentlyContinue)
}

# Usuwa katalog z danymi (tylko przy -UsunDane). Zwraca $true, gdy go juz nie ma.
function Usun-Katalog-Danych([string]$sciezka, [string]$opis) {
  if (-not (Test-Path -LiteralPath $sciezka)) { Krok "$opis - nie ma ($sciezka)"; return $true }
  if ($script:MR.proba) { Plan "usunalbym $opis ($sciezka)"; return $true }
  $blad = Usun-Drzewo $sciezka
  if ($blad) { Ostrzezenie "nie udalo sie usunac $opis ($sciezka): $blad"; return $false }
  Krok "usuniete: $opis ($sciezka)"
  return $true
}

# Czy repo jest klonem git z galezia sledzaca - bez tego straznik nie pobierze aktualizacji
# (zapisuje wtedy "nie-repo" albo "bez-zdalnej" i milczy). Zwraca Ok i Opis.
function Stan-Klonu([string]$git, [string]$zrodlo) {
  if (-not $git) { return [pscustomobject]@{ Ok = $false; Opis = "nie ma gita - aktualizacje MegaRuchacza nie beda przychodzic" } }
  if (-not (Test-Path -LiteralPath (Join-Path $zrodlo ".git"))) {
    return [pscustomobject]@{ Ok = $false; Opis = "$zrodlo nie jest klonem git (np. rozpakowany ZIP) - aktualizacje nie beda przychodzic; pobierz MegaRuchacza przez: git clone https://github.com/Primo2966/MegaRuchacz.git" }
  }
  $w = Lore-Wolaj $git @("-C", $zrodlo, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
  if ($w.Kod -ne 0) {
    return [pscustomobject]@{ Ok = $false; Opis = "galaz w $zrodlo nie sledzi zadnej zdalnej (git: $(Ostatnia-Linia $w.Tekst)) - aktualizacje nie beda przychodzic" }
  }
  return [pscustomobject]@{ Ok = $true; Opis = "klon git, galaz sledzi $(Ostatnia-Linia $w.Tekst)" }
}
