# narzedzia\instalacja\zaleznosci.ps1 - programy, ktorych potrzebuja moduly MegaRuchacza.
#
#   uv      menedzer srodowisk Pythona (Lore, cykl wiedzy)    winget astral-sh.uv (wersja przenosna)
#                                                              albo zip z github.com/astral-sh/uv
#   python  Python 3.12 (Lore, cykl wiedzy)                   uv python install 3.12 (wymaga uv - dokladany sam)
#   git     aktualizacje MegaRuchacza, skille                 PELNY Git for Windows (z Git Bash): instalator
#   bash    Git Bash - Claude Code na Windows go wymaga,       z github.com/git-for-windows (suma SHA-256), po cichu
#           hooki MegaRuchacza chodza przez niego             i tylko dla uzytkownika (/VERYSILENT /CURRENTUSER ->
#                                                              %LOCALAPPDATA%\Programs\Git); gdy sie nie uda -
#                                                              winget Git.Git --scope user. git i bash = jedna paczka.
#   node    hooki przypomnienia i rejestru workerow           winget OpenJS.NodeJS.LTS --scope user (zip, bez MSI)
#                                                              albo zip z nodejs.org
# WSZYSTKO BEZ UPRAWNIEN ADMINISTRATORA: wersje przenosne w katalogu uzytkownika, katalog dopisany
# do PATH UZYTKOWNIKA (HKCU\Environment, z zachowaniem %ZMIENNYCH% w istniejacych wpisach).
# Paczki sa sprawdzane suma SHA-256 z tego samego wydania (uv: plik .sha256, Git for Windows: pole
# digest albo tabela w opisie wydania, Node: SHASUMS256.txt); zla suma = odmowa, plik usuniety.
# Git Bash jest dokladany sam, gdy potrzebny jest git albo node (baza i moduly z hookami): bez niego
# Claude Code na Windows nie dziala, a hooki chodza przez bash. Do 0.33 git byl przenosnym MinGit,
# ktory basha nie ma - na komputerze z takim gitem Git for Windows staje obok. Przenosnego PortableGit
# NIE uzywamy: jego samorozpakowujace sie archiwum pokazuje okno postepu nawet z -y (sprawdzone
# 2026-10-14), a instalator z /VERYSILENT nie pokazuje nic. Bash, ktorego Claude Code sam nie
# znajdzie (szuka w Program Files i obok pierwszego gita z PATH - Wskaz-Basha-Claude), dostaje
# zmienna uzytkownika CLAUDE_CODE_GIT_BASH_PATH (nazwa z komunikatu i kodu claude.exe 2.1.x).
# Juz otwarte okna (Claude Code, nadzorca) nowego PATH nie widza do ponownego uruchomienia -
# skrypty modulow szukaja programow takze w tych katalogach (wspolne.ps1, Kandydaci-Programu).
#
# Uzycie (ten sam format wyjscia co moduly - naglowek wspolne.ps1):
#   powershell -NoProfile -ExecutionPolicy Bypass -File narzedzia\instalacja\zaleznosci.ps1
#     -Akcja Sprawdz|Instaluj -Potrzebne uv,python,git,node [-Proba]
#     [-KatalogProgramow <kat>]  gdzie klasc wersje przenosne (domyslnie %LOCALAPPDATA%\MegaRuchacz)
#     [-BezWinget]               od razu paczka zip (winget bywa zepsuty albo go nie ma)
#     [-BezZmianyPath]           nie dopisuje katalogow do PATH uzytkownika ani nie ustawia zmiennej
#                                uzytkownika CLAUDE_CODE_GIT_BASH_PATH (testy)
#     [-InstalatorGita <plik>]   (TESTY) gotowy instalator Git for Windows zamiast pobierania z GitHuba,
#                                bez sumy SHA-256; dostaje te same przelaczniki co prawdziwy
#     [-Proxy <adres>]           serwer posredniczacy do pobierania (siec firmowa)
# Sprawdz: ok = wszystkie wymienione sa. Instaluj: ok = po instalacji wszystkie sa i sie uruchamiaja.

[CmdletBinding()]
param(
  [string]$Akcja = "",
  [string[]]$Potrzebne = @(),
  [switch]$Proba,
  [string]$KatalogProgramow = "",
  [switch]$BezWinget,
  [switch]$BezZmianyPath,
  [string]$Proxy = "",
  [string]$InstalatorGita = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # pasek postepu Invoke-WebRequest spowalnia pobieranie kilkukrotnie
. (Join-Path $PSScriptRoot "wspolne.ps1")
$Zrodlo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
[void](Start-Modul "zaleznosci" $Akcja ([bool]$Proba) $Zrodlo $HOME @("Sprawdz", "Instaluj"))
if (-not $KatalogProgramow) { $KatalogProgramow = Join-Path $env:LOCALAPPDATA "MegaRuchacz" }
if ($Proxy) { $env:HTTPS_PROXY = $Proxy; $env:HTTP_PROXY = $Proxy }   # dla uv (python install)
# Z -BezZmianyPath to zastepuje PATH z rejestru przy pytaniu "ktory git zobaczy Claude Code"
# (Wskaz-Basha-Claude): PATH ze startu + katalogi, ktore dopisalibysmy NA KONIEC PATH uzytkownika.
$script:PathStartowy = $env:PATH
$script:DopisaneDoPath = @()

$Znane = @("uv", "python", "git", "bash", "node")
# -File podaje "uv,python" jako JEDEN napis do [string[]] - dzielimy sami
$lista = @($Potrzebne | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ } | ForEach-Object { $_.ToLower() })
$nieznane = @($lista | Where-Object { $Znane -notcontains $_ })
if ($nieznane.Count -gt 0) { Zakoncz $false "nie znam programu: $($nieznane -join ', ') (znam: $($Znane -join ', '))" }
if ($lista.Count -eq 0) { Zakoncz $false "podaj -Potrzebne, np. -Potrzebne uv,python,git,node" }
if (($lista -contains "python") -and ($lista -notcontains "uv")) { $lista = @("uv") + $lista }
# git albo node = baza albo modul z hookami, a Claude Code na Windows bez Git Bash nie dziala wcale
if ((($lista -contains "git") -or ($lista -contains "node")) -and ($lista -notcontains "bash")) { $lista += "bash" }
$lista = @($Znane | Where-Object { $lista -contains $_ })   # kolejnosc: uv przed pythonem, git przed bashem

$Arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }

# ---------------------------------------------------------------- siec

function Powod-Sieci($blad, [string]$url) {
  $host_ = ([uri]$url).Host
  $e = $blad.Exception
  while ($e -and -not ($e -is [System.Net.WebException]) -and $e.InnerException) { $e = $e.InnerException }
  if ($e -is [System.Net.WebException]) {
    switch ($e.Status) {
      "NameResolutionFailure"      { return "brak internetu - nie znam adresu $host_ (sprawdz polaczenie)" }
      "ConnectFailure"             { return "brak internetu albo $host_ nie odpowiada (polaczenie odrzucone)" }
      "Timeout"                    { return "brak internetu albo $host_ nie odpowiada (minal czas)" }
      "ProxyNameResolutionFailure" { return "nie znam adresu serwera posredniczacego (-Proxy)" }
      "SecureChannelFailure"       { return "nie udalo sie zestawic bezpiecznego polaczenia z $host_ (TLS)" }
      "TrustFailure"               { return "certyfikat $host_ nie jest zaufany - cos przechwytuje polaczenie" }
      "ProtocolError" {
        $kod = try { [int]$e.Response.StatusCode } catch { 0 }
        if ($kod -eq 404) { return "na $host_ nie ma pliku $url (404)" }
        if ($kod -eq 403) { return "$host_ odmowil (403) - np. limit zapytan GitHuba bez logowania, sprobuj za godzine" }
        return "$host_ odpowiedzial bledem $kod"
      }
    }
  }
  return "pobranie z $host_ nie powiodlo sie: $($blad.Exception.Message)"
}

function Parametry-Sieci([string]$url) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  $p = @{ Uri = $url; UseBasicParsing = $true; TimeoutSec = 900; ErrorAction = "Stop" }
  if ($Proxy) { $p.Proxy = $Proxy }
  return $p
}

function Pobierz-Plik([string]$url, [string]$dokad) {
  $p = Parametry-Sieci $url
  try { Invoke-WebRequest @p -OutFile $dokad } catch { throw (Powod-Sieci $_ $url) }
}

function Pobierz-Tekst([string]$url) {
  $p = Parametry-Sieci $url
  try { $r = Invoke-WebRequest @p } catch { throw (Powod-Sieci $_ $url) }
  if ($r.Content -is [byte[]]) { return [System.Text.Encoding]::UTF8.GetString($r.Content) }
  return [string]$r.Content
}

function Sprawdz-Sume([string]$plik, [string]$oczekiwana, [string]$skad) {
  if (-not $oczekiwana) {
    Ostrzezenie "dla $(Split-Path -Leaf $plik) nie znalazlem sumy kontrolnej w $skad - instaluje bez niej (polaczenie HTTPS z serwerem wydania)"
    return
  }
  $jest = (Get-FileHash -LiteralPath $plik -Algorithm SHA256).Hash.ToLower()
  if ($jest -ne $oczekiwana.ToLower()) {
    Remove-Item -LiteralPath $plik -Force -ErrorAction SilentlyContinue
    throw "suma SHA-256 pobranego $(Split-Path -Leaf $plik) sie nie zgadza (jest $jest, ma byc $oczekiwana) - plik usuniety, nic nie zainstalowane"
  }
  Krok "suma SHA-256 $(Split-Path -Leaf $plik) zgodna z wydaniem"
}

# Rozpakowanie do katalogu obok i podmiana - przerwane rozpakowanie nie zostawia polowy programu.
# Wpis po wpisie (nie ExtractToDirectory): wpis wychodzacy poza katalog ("..") to odmowa, a wybor
# wpisow pozwala ominac to, czego nie potrzebujemy.
#   -JedenKatalog      paczka ma wszystko w jednym katalogu (np. node-v24.1.0-win-x64/) - bierzemy jego zawartosc
#   -BezPodkatalogow   tylko pliki z wierzchu. Node: hooki potrzebuja samego node.exe, a npm w paczce
#                      (node_modules\npm\...) ma sciezki, ktore pod dluzszym katalogiem przekraczaja
#                      260 znakow - zmierzone 2026-10-02: ExtractToDirectory padal na tym limicie.
function Rozpakuj-Do([string]$zip, [string]$cel, [switch]$JedenKatalog, [switch]$BezPodkatalogow) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cel) | Out-Null
  $tmp = "$cel.nowy-$PID"
  if (Test-Path -LiteralPath $tmp) { [void](Usun-Drzewo $tmp) }
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $tmpPelny = [System.IO.Path]::GetFullPath($tmp).TrimEnd('\') + '\'
  $arch = [System.IO.Compression.ZipFile]::OpenRead($zip)
  $udane = $false
  try {
    $wpisy = @($arch.Entries)
    $przedrostek = ""
    if ($JedenKatalog) {
      $wierzch = @($wpisy | ForEach-Object { ($_.FullName -split '/')[0] } | Sort-Object -Unique)
      if ($wierzch.Count -eq 1) { $przedrostek = $wierzch[0] + "/" }
    }
    foreach ($w in $wpisy) {
      $wzgl = $w.FullName
      if ($przedrostek) { if (-not $wzgl.StartsWith($przedrostek)) { continue }; $wzgl = $wzgl.Substring($przedrostek.Length) }
      if (-not $wzgl -or $wzgl.EndsWith("/")) { continue }
      if ($BezPodkatalogow -and $wzgl.Contains("/")) { continue }
      $dokad = [System.IO.Path]::GetFullPath((Join-Path $tmp ($wzgl -replace '/', '\')))
      if (-not $dokad.StartsWith($tmpPelny, [System.StringComparison]::OrdinalIgnoreCase)) { throw "paczka $(Split-Path -Leaf $zip) ma wpis poza swoim katalogiem ($($w.FullName)) - odmawiam rozpakowania" }
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dokad) | Out-Null
      [System.IO.Compression.ZipFileExtensions]::ExtractToFile($w, $dokad, $true)
    }
    $udane = $true
  } finally {
    $arch.Dispose()
    if (-not $udane) { $b = Usun-Drzewo $tmp; if ($b) { Ostrzezenie "niedokonczone rozpakowanie zostalo w $tmp ($b)" } }
  }
  if (Test-Path -LiteralPath $cel) {
    $stary = "$cel.stary-$PID"
    Rename-Item -LiteralPath $cel -NewName (Split-Path -Leaf $stary)
    $b = Usun-Drzewo $stary
    if ($b) { Ostrzezenie "stara wersja zostala w $stary ($b) - usun recznie" }
  }
  Rename-Item -LiteralPath $tmp -NewName (Split-Path -Leaf $cel)
}

function Plik-Tymczasowy([string]$nazwa) { return (Join-Path $env:TEMP ("mr-" + $PID + "-" + $nazwa)) }

# ---------------------------------------------------------------- PATH uzytkownika

function Rozglos-Zmiane-Srodowiska {
  if (-not ("MrSrodowisko" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MrSrodowisko {
  [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
  public static void Rozglos() {
    UIntPtr wynik;
    SendMessageTimeout(new IntPtr(0xffff), 0x001A, UIntPtr.Zero, "Environment", 0x0002, 5000, out wynik);
  }
}
'@
  }
  [MrSrodowisko]::Rozglos()
}

# Dopisuje katalog do PATH uzytkownika. Surowa wartosc z rejestru (bez rozwijania %ZMIENNYCH%) i zapis
# jako REG_EXPAND_SZ - [Environment]::SetEnvironmentVariable zapisalby REG_SZ i rozbil wpisy z %...%.
function Dopisz-Do-Path-Uzytkownika([string]$katalog) {
  Dodaj-Do-Path $katalog
  $script:DopisaneDoPath += $katalog
  if ($BezZmianyPath) { Krok "PATH uzytkownika bez zmian (-BezZmianyPath) - $katalog dopisany tylko dla tego procesu"; return }
  if ($Proba) { Plan "dopisalbym $katalog do PATH uzytkownika"; return }
  $klucz = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Environment", $true)
  try {
    $surowy = [string]$klucz.GetValue("Path", "", [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $czesci = @($surowy -split ';' | Where-Object { $_ })
    $rozwiniete = @($czesci | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') })
    if ($rozwiniete -contains $katalog.TrimEnd('\')) { Krok "$katalog juz jest w PATH uzytkownika"; return }
    $nowy = (@($czesci) + $katalog) -join ';'
    $klucz.SetValue("Path", $nowy, [Microsoft.Win32.RegistryValueKind]::ExpandString)
  } finally { $klucz.Close() }
  try { Rozglos-Zmiane-Srodowiska } catch { Ostrzezenie "PATH zapisany, ale nie udalo sie powiadomic Windows o zmianie ($($_.Exception.Message)) - zadziala po ponownym zalogowaniu" }
  Krok "dopisany do PATH uzytkownika: $katalog (otwarte okna widza go dopiero po ponownym uruchomieniu)"
}

# ---------------------------------------------------------------- sprawdzanie

function Wersja([string]$exe, [string[]]$argumenty = @("--version")) {
  $w = Uruchom-Program $exe $argumenty 60
  if ($w.Kod -ne 0) { return $null }
  return (($w.Tekst -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
}

function Znajdz([string]$n) {
  if ($n -eq "python") {
    $uv = Znajdz-Program "uv"
    $py = Znajdz-Pythona-Uv $uv
    if (-not $py) { return $null }
    return [pscustomobject]@{ Sciezka = $py; Wersja = (Wersja $py) }
  }
  $p = Znajdz-Program $n
  if (-not $p -and ($n -ne "bash")) {
    # wersja przenosna mogla trafic do innego katalogu programow (-KatalogProgramow); git tam to
    # MinGit z wersji sprzed 0.33 (bez basha)
    $tu = switch ($n) { "uv" { "uv\uv.exe" } "git" { "git\cmd\git.exe" } "node" { "node\node.exe" } }
    $k = Join-Path $KatalogProgramow $tu
    if (Test-Path -LiteralPath $k) { $p = $k; Dodaj-Do-Path (Split-Path -Parent $k) }
  }
  if (-not $p) { return $null }
  return [pscustomobject]@{ Sciezka = $p; Wersja = (Wersja $p) }
}

# ---------------------------------------------------------------- winget

function Winget { if ($BezWinget) { return $null }; return (Znajdz-Program "winget") }

# Zwraca $true, gdy po winget program jest. Kazda porazka winget to UWAGA i droga zapasowa ($potem).
function Przez-Winget([string]$n, [string]$id, [string[]]$dodatkowe, [string]$potem = "biore paczke zip") {
  $wg = Winget
  if (-not $wg) {
    $czemu = if ($BezWinget) { "pominiety (-BezWinget)" } else { "nie ma go na tym komputerze" }
    Krok "${n}: winget $czemu - $potem"
    return $false
  }
  if ($Proba) { Plan "${n}: winget install --id $id $($dodatkowe -join ' ') (bez administratora), a gdy sie nie uda - $potem"; return $true }
  Krok "${n}: instaluje przez winget ($id) - to moze potrwac kilka minut"
  $w = Uruchom-Program $wg (@("install", "--id", $id, "-e", "--source", "winget", "--silent", "--disable-interactivity",
        "--accept-package-agreements", "--accept-source-agreements") + $dodatkowe) 900
  if (Znajdz $n) { Krok "${n}: winget zainstalowal"; return $true }
  $powod = (($w.Tekst -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 1)
  if ($w.Tekst -match '(?i)(0x8a15000f|internet|network|connect|siec|sieci)') { $powod = "brak internetu albo zrodlo winget niedostepne ($powod)" }
  Ostrzezenie "${n}: winget nie zainstalowal (kod $($w.Kod): $powod) - $potem"
  return $false
}

# ---------------------------------------------------------------- instalacja poszczegolnych programow

function Instaluj-Uv {
  if (Przez-Winget "uv" "astral-sh.uv" @("--scope", "user")) { if (-not $Proba) { return } }
  $plik = switch ($Arch) { "ARM64" { "uv-aarch64-pc-windows-msvc.zip" } "x86" { "uv-i686-pc-windows-msvc.zip" } default { "uv-x86_64-pc-windows-msvc.zip" } }
  $url = "https://github.com/astral-sh/uv/releases/latest/download/$plik"
  $cel = Join-Path $KatalogProgramow "uv"
  if ($Proba) { Plan "uv: pobralbym $url (+ .sha256) i rozpakowal do $cel"; return }
  Krok "uv: pobieram $url"
  $zip = Plik-Tymczasowy $plik
  try {
    Pobierz-Plik $url $zip
    $suma = [regex]::Match((Pobierz-Tekst "$url.sha256"), '[0-9a-fA-F]{64}').Value
    Sprawdz-Sume $zip $suma "$url.sha256"
    Rozpakuj-Do $zip $cel
  } finally { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
  $exe = Get-ChildItem -LiteralPath $cel -Recurse -Filter "uv.exe" | Select-Object -First 1
  if (-not $exe) { throw "w paczce uv nie bylo uv.exe" }
  if ($exe.DirectoryName -ne $cel) { Get-ChildItem -LiteralPath $exe.DirectoryName -File | Move-Item -Destination $cel -Force }
  Dopisz-Do-Path-Uzytkownika $cel
}

function Instaluj-Pythona {
  $uv = Znajdz-Program "uv"
  if ($Proba -and -not $uv) { Plan "python: uv python install 3.12 (po zainstalowaniu uv; ~30 MB z github.com, python-build-standalone)"; return }
  if (-not $uv) { throw "Python instaluje sie przez uv, a uv nie ma" }
  if ($Proba) { Plan "python: $uv python install 3.12 (~30 MB z github.com, python-build-standalone)"; return }
  Krok "python: instaluje Pythona 3.12 przez uv (~30 MB)"
  $w = Uruchom-Program $uv @("python", "install", "3.12") 900
  if ($w.Kod -ne 0) {
    $powod = (($w.Tekst -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 1)
    if ($w.Tekst -match '(?i)(failed to (download|fetch)|dns|connect|timed out|network|tcp|error sending request)') {
      throw "uv nie pobral Pythona - brak internetu albo github.com niedostepny: $powod"
    }
    throw "uv python install 3.12 nie powiodl sie (kod $($w.Kod)): $powod"
  }
}

# Pelny Git for Windows - daje i gita, i Git Bash (MinGit, ktory byl tu do 0.33, basha nie ma).
# Najpierw instalator z najnowszego wydania na GitHubie (suma SHA-256 z pola digest albo z tabeli
# w opisie wydania), uruchomiony po cichu i tylko dla uzytkownika: /VERYSILENT nie pokazuje zadnego
# okna, /CURRENTUSER nie prosi o administratora i kladzie Gita do %LOCALAPPDATA%\Programs\Git (tam
# szukaja go wspolne.ps1 i Claude Code). Gdy sie nie uda - winget Git.Git --scope user (ten sam
# instalator). git i bash to ta sama paczka, wiec instalator idzie najwyzej RAZ na przebieg: po
# porazce albo po instalacji bez basha drugi program dostaje od razu ten sam powod, bez drugiego
# pobierania 60 MB.
$script:GitForWindows = $null   # $null = jeszcze nie bylo; "ok" = instalator przeszedl; inaczej powod porazki
$script:PowodBasha = ""

function Instaluj-Git-For-Windows([string]$n) {
  $docelowy = Join-Path $env:LOCALAPPDATA "Programs\Git"
  if ($script:GitForWindows -eq "ok") { throw "Git for Windows zainstalowal sie, ale nie ma w nim $n ($docelowy) - instalacja jest niepelna" }
  if ($script:GitForWindows) { throw "Git for Windows nie zainstalowal sie juz wyzej ($($script:GitForWindows))" }
  $wzor = switch ($Arch) { "ARM64" { '^Git-[\d.]+-arm64\.exe$' } "x86" { "" } default { '^Git-[\d.]+-64-bit\.exe$' } }
  $api = "https://api.github.com/repos/git-for-windows/git/releases/latest"
  $przelaczniki = @("/SP-", "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/NOCANCEL", "/CURRENTUSER")
  if ($Proba) {
    Plan "${n}: Git for Windows (pelny, z Git Bash) - instalator z najnowszego wydania github.com/git-for-windows (suma SHA-256), po cichu i tylko dla Ciebie ($($przelaczniki -join ' '), bez administratora) do $docelowy; gdy sie nie uda - winget Git.Git --scope user"
    return
  }
  $blad = $null
  $pobrany = $null
  try {
    if ($InstalatorGita) {
      if (-not (Test-Path -LiteralPath $InstalatorGita -PathType Leaf)) { throw "nie ma pliku instalatora $InstalatorGita (-InstalatorGita)" }
      $plik = $InstalatorGita
      Krok "${n}: instalator Git for Windows z pliku $plik (-InstalatorGita, test) - bez pobierania i bez sumy"
    } else {
      if (-not $wzor) { throw "Git for Windows z Git Bash nie wychodzi juz dla 32-bitowego Windows" }
      Krok "${n}: szukam najnowszego Git for Windows ($api)"
      $wyd = (Pobierz-Tekst $api) | ConvertFrom-Json
      $a = @($wyd.assets | Where-Object { $_.name -match $wzor }) | Select-Object -First 1
      if (-not $a) { throw "w wydaniu $($wyd.tag_name) nie ma instalatora Git for Windows dla $Arch" }
      $suma = ""
      if ($a.digest -and "$($a.digest)" -match 'sha256:([0-9a-fA-F]{64})') { $suma = $Matches[1] }
      elseif ($wyd.body) { $m = [regex]::Match([string]$wyd.body, [regex]::Escape($a.name) + '\s*\|\s*([0-9a-fA-F]{64})'); if ($m.Success) { $suma = $m.Groups[1].Value } }
      $pobrany = Plik-Tymczasowy $a.name
      Krok "${n}: pobieram $($a.name) ($([math]::Round($a.size / 1MB)) MB)"
      Pobierz-Plik $a.browser_download_url $pobrany
      Sprawdz-Sume $pobrany $suma "wydaniu $($wyd.tag_name)"
      $plik = $pobrany
    }
    $log = Plik-Tymczasowy "git-instalator.log"
    Krok "${n}: instaluje Git for Windows po cichu, tylko dla Ciebie (bez administratora) do $docelowy - to moze potrwac kilka minut"
    $w = Uruchom-Program $plik ($przelaczniki + @("/LOG=$log")) 900
    if ($w.Kod -ne 0) {
      $ogon = ""
      if (Test-Path -LiteralPath $log) { $ogon = (@(Get-Content -LiteralPath $log -Tail 3 -ErrorAction SilentlyContinue) -join " | ") }
      throw ("instalator Git for Windows skonczyl sie kodem $($w.Kod)" + $(if ($w.Tekst) { ": " + $w.Tekst } else { "" }) + $(if ($ogon) { " (koniec dziennika instalatora: $ogon)" } else { "" }))
    }
    Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    $script:GitForWindows = "ok"
    Krok "${n}: instalator Git for Windows skonczyl bez bledu"
    $cmd = Join-Path $docelowy "cmd"
    if (Test-Path -LiteralPath (Join-Path $cmd "git.exe")) { Dopisz-Do-Path-Uzytkownika $cmd }
    return
  } catch { $blad = $_.Exception.Message }
  finally { if ($pobrany) { Remove-Item -LiteralPath $pobrany -Force -ErrorAction SilentlyContinue } }
  Ostrzezenie "${n}: Git for Windows z GitHuba sie nie zainstalowal ($blad)"
  if (Przez-Winget $n "Git.Git" @("--scope", "user") "nie mam juz innej drogi") { $script:GitForWindows = "ok"; return }
  $script:GitForWindows = $blad
  throw "nie udalo sie zainstalowac Git for Windows: $blad"
}

# Claude Code szuka Git Bash sam tylko w C:\Program Files\Git i C:\Program Files (x86)\Git oraz obok
# PIERWSZEGO gita z PATH (..\..\bin\bash.exe) - a ten bywa MinGitem bez basha (u Eli MinGit stal
# w PATH przed Git for Windows). Gdy sam go nie znajdzie, bash dostaje zmienna uzytkownika
# CLAUDE_CODE_GIT_BASH_PATH. Gdy znajdzie - zmiennej nie zakladamy (nic, co juz dziala, nie jest
# ruszane). Zmienna wskazujaca istniejacy bash zostaje (mogles ja ustawic sam); wskazujaca plik,
# ktorego nie ma, jest poprawiana.

# Bash, ktory znajdzie NOWO uruchomiony Claude Code bez zmiennej, albo $null. PATH jak u nowego
# procesu: maszyny + uzytkownika z rejestru (-BezZmianyPath: PATH ze startu + dopisane na koncu).
function Bash-Ktorego-Claude-Uzyje {
  foreach ($b in @("C:\Program Files\Git\bin\bash.exe", "C:\Program Files (x86)\Git\bin\bash.exe")) { if (Test-Path -LiteralPath $b -PathType Leaf) { return $b } }
  $katalogi = if ($BezZmianyPath) { @($script:PathStartowy -split ';') + @($script:DopisaneDoPath) }
              else { @([Environment]::GetEnvironmentVariable("Path", "Machine") -split ';') + @([Environment]::GetEnvironmentVariable("Path", "User") -split ';') }
  foreach ($k in $katalogi) {
    $k = [Environment]::ExpandEnvironmentVariables("$k".Trim())
    if (-not $k) { continue }
    foreach ($e in @("git.com", "git.exe", "git.bat", "git.cmd")) {
      $g = Join-Path $k $e
      if (-not (Test-Path -LiteralPath $g -PathType Leaf)) { continue }
      # tylko PIERWSZY git sie liczy - tak robi Claude Code
      $b = Join-Path (Split-Path -Parent (Split-Path -Parent $g)) "bin\bash.exe"
      if (Test-Path -LiteralPath $b -PathType Leaf) { return $b }
      return $null
    }
  }
  return $null
}

function Wskaz-Basha-Claude([string]$bash) {
  $nazwa = $script:ZmiennaBasha
  $obecna = if ($BezZmianyPath) { [Environment]::GetEnvironmentVariable($nazwa) } else { [Environment]::GetEnvironmentVariable($nazwa, "User") }
  if ($obecna -and ($obecna.TrimEnd('\') -ieq $bash)) { Krok "bash: zmienna $nazwa juz wskazuje $bash"; return }
  if ($obecna -and ((Split-Path -Leaf $obecna) -match '^(bash|sh)(\.exe)?$') -and (Test-Path -LiteralPath $obecna -PathType Leaf)) { Krok "bash: zmienna $nazwa wskazuje inny istniejacy bash ($obecna) - zostawiam"; return }
  $sam = Bash-Ktorego-Claude-Uzyje
  if ($sam -and -not $obecna) { Krok "bash: Claude Code znajdzie Git Bash sam ($sam) - zmienna $nazwa niepotrzebna"; return }
  $czemu = if ($obecna) { "wskazywala $obecna, a tam basha nie ma" } else { "Claude Code sam szuka go tylko w Program Files i obok pierwszego gita z PATH, a tam go nie ma" }
  if ($Proba) { Plan "bash: ustawilbym zmienna uzytkownika $nazwa = $bash ($czemu)"; return }
  [Environment]::SetEnvironmentVariable($nazwa, $bash)   # ten proces i jego dzieci
  if ($BezZmianyPath) { Krok "bash: $nazwa = $bash tylko dla tego procesu (-BezZmianyPath) - $czemu"; return }
  try { [Environment]::SetEnvironmentVariable($nazwa, $bash, "User") }
  catch { Ostrzezenie "bash jest ($bash), ale nie ustawilem zmiennej uzytkownika $nazwa ($($_.Exception.Message)) - Claude Code moze go nie znalezc; ustaw ja recznie"; return }
  Krok "bash: ustawiona zmienna uzytkownika $nazwa = $bash ($czemu; otwarte okna Claude Code widza ja po ponownym uruchomieniu)"
}

function Instaluj-Node {
  if (Przez-Winget "node" "OpenJS.NodeJS.LTS" @("--scope", "user")) { if (-not $Proba) { return } }
  $plat = switch ($Arch) { "ARM64" { "win-arm64" } "x86" { "win-x86" } default { "win-x64" } }
  $cel = Join-Path $KatalogProgramow "node"
  if ($Proba) { Plan "node: pobralbym najnowsze LTS ($plat, zip z nodejs.org, + SHASUMS256.txt) i rozpakowal do $cel"; return }
  Krok "node: szukam najnowszego wydania LTS (nodejs.org/dist/index.json)"
  # PULAPKA PS 5.1: ConvertFrom-Json w potoku oddaje tablice JSON jako JEDEN obiekt - @(... | ConvertFrom-Json)
  # dawalo jedna "wersje" bedaca lista wszystkich, a adres paczki z niej - blad 400. Przypisanie rozwija tablice.
  $wyd = ConvertFrom-Json -InputObject (Pobierz-Tekst "https://nodejs.org/dist/index.json")
  $lts = $wyd | Where-Object { $_.lts -and $_.lts -ne $false -and (@($_.files) -contains "$plat-zip") } | Select-Object -First 1
  if (-not $lts -or $lts.version -notmatch '^v\d+\.\d+\.\d+$') { throw "nie umiem odczytac wydania LTS z nodejs.org/dist/index.json (wersja: '$($lts.version)')" }
  if (-not $lts) { throw "nie znalazlem wydania LTS Node.js z paczka $plat-zip" }
  $plik = "node-$($lts.version)-$plat.zip"
  $baza = "https://nodejs.org/dist/$($lts.version)"
  $zip = Plik-Tymczasowy $plik
  try {
    Krok "node: pobieram $plik (Node.js $($lts.version) LTS)"
    Pobierz-Plik "$baza/$plik" $zip
    $sumy = Pobierz-Tekst "$baza/SHASUMS256.txt"
    $suma = [regex]::Match($sumy, '([0-9a-fA-F]{64})\s+' + [regex]::Escape($plik)).Groups[1].Value
    Sprawdz-Sume $zip $suma "$baza/SHASUMS256.txt"
    Rozpakuj-Do $zip $cel -JedenKatalog -BezPodkatalogow
  } finally { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
  Krok "node: rozpakowany sam node.exe z plikami z wierzchu paczki (bez npm - hooki MegaRuchacza go nie potrzebuja)"
  Dopisz-Do-Path-Uzytkownika $cel
}

# ---------------------------------------------------------------- przebieg

try {
  $brak = @()
  $wynikProgramow = @{}
  foreach ($n in $lista) {
    $z = Znajdz $n
    $wynikProgramow[$n] = [ordered]@{ nazwa = $n; jest = [bool]$z; sciezka = $(if ($z) { $z.Sciezka }); wersja = $(if ($z) { $z.Wersja }); zainstalowany_teraz = $false; po_co = $script:OpisyProgramow[$n] }
    if ($z) { Krok "${n}: jest - $($z.Sciezka)$(if ($z.Wersja) { ' (' + $z.Wersja + ')' })" }
    else { Krok "${n}: brak"; $brak += $n }
  }

  if ($Akcja -eq "Instaluj") {
    foreach ($n in $brak) {
      $przyszedl = $false
      if (($n -eq "bash") -and ($brak -contains "git")) {
        # Git for Windows z kroku git wyzej przynosi tez basha
        if ($Proba) { Plan "bash: przyjdzie razem z Git for Windows (krok git wyzej)"; continue }
        $przyszedl = [bool](Znajdz "bash")
      }
      if (-not $przyszedl) {
        try {
          switch ($n) { "uv" { Instaluj-Uv } "python" { Instaluj-Pythona } "git" { Instaluj-Git-For-Windows "git" } "bash" { Instaluj-Git-For-Windows "bash" } "node" { Instaluj-Node } }
        } catch {
          if (@("git", "bash") -contains $n) { $script:PowodBasha = $_.Exception.Message }
          Ostrzezenie "${n}: $($_.Exception.Message)"
          continue
        }
      }
      if ($Proba) { continue }
      $z = Znajdz $n
      if ($z -and $z.Wersja) {
        Krok "${n}: zainstalowany - $($z.Sciezka) ($($z.Wersja))"
        $wynikProgramow[$n].jest = $true; $wynikProgramow[$n].sciezka = $z.Sciezka; $wynikProgramow[$n].wersja = $z.Wersja; $wynikProgramow[$n].zainstalowany_teraz = $true
      } elseif ($z) {
        Ostrzezenie "${n}: plik jest ($($z.Sciezka)), ale sie nie uruchamia"
        if ($n -eq "bash") { $script:PowodBasha = "$($z.Sciezka) jest, ale sie nie uruchamia" }
      } else {
        Ostrzezenie "${n}: po instalacji dalej go nie widze"
        if ($n -eq "bash") { $script:PowodBasha = "po instalacji Git for Windows nie widze bash.exe (szukalem m.in. w $(Join-Path $env:LOCALAPPDATA 'Programs\Git\bin'))" }
      }
    }
    if ($lista -contains "bash") {
      if ($wynikProgramow["bash"].jest) { Wskaz-Basha-Claude $wynikProgramow["bash"].sciezka }
      elseif ($Proba) { Plan "bash: po instalacji Git for Windows ustawilbym zmienna uzytkownika $($script:ZmiennaBasha), gdyby bash wyladowal poza miejscami, ktore Claude Code zna sam" }
    }
  }

  foreach ($n in $lista) {
    [void]$script:MR.programy.Add($wynikProgramow[$n])
    if (-not $wynikProgramow[$n].jest) { [void]$script:MR.brakuje.Add($n) }
  }
  $nadal = @($script:MR.brakuje)
  if ($Proba) {
    $kom = if ($brak.Count -eq 0) { "wszystko jest: $($lista -join ', ')" } else { "proba: brakuje $($brak -join ', ') - instalacja pojdzie jak wyzej" }
    Zakoncz $true $kom
  }
  if ($nadal.Count -eq 0) {
    $kom = if ($Akcja -eq "Instaluj" -and $brak.Count -gt 0) { "zainstalowane: $($brak -join ', '); reszta juz byla" } else { "wszystko jest: $($lista -join ', ')" }
    Zakoncz $true $kom
  }
  $kom = if ($Akcja -eq "Sprawdz") { "brakuje: $($nadal -join ', ') - zainstaluj: zaleznosci.ps1 -Akcja Instaluj -Potrzebne $($nadal -join ',')" } else { "nie udalo sie zainstalowac: $($nadal -join ', ') - powody w uwagach" }
  if (($Akcja -eq "Instaluj") -and ($nadal -contains "bash")) {
    # Glosno i na poczatku (okno pokazuje komunikat w karcie bledu): bez Git Bash nie ma po co isc dalej
    $kom = "Nie ma Git Bash (czesc Git for Windows), mimo proby instalacji - bez niego Claude Code na Windows i hooki MegaRuchacza nie dzialaja."
    if ($script:PowodBasha) { $kom += " Powod: $($script:PowodBasha)." }
    $kom += " Jesli blad wraca, zainstaluj Git for Windows ze strony https://git-scm.com/downloads/win (wystarczy 'Only for me', bez administratora) i uruchom instalator jeszcze raz."
    $inne = @($nadal | Where-Object { $_ -ne "bash" })
    if ($inne.Count -gt 0) { $kom += " Nie udalo sie tez zainstalowac: $($inne -join ', ') - powody w uwagach." }
  }
  Zakoncz $false $kom
} catch {
  Zakoncz $false ("nieoczekiwany blad: " + $_.Exception.Message + " (" + $_.InvocationInfo.PositionMessage.Split("`n")[0].Trim() + ")")
}
