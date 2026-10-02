# instalator\pobierz.ps1 - tryb pobieranie instalatora (czysty komputer), osobny proces
# uruchamiany przez okno (instalator\ekrany.ps1, Plan-Pobierania).
#   -Co git   zdobywa program git: jest w systemie -> nic nie robi; nie ma -> narzedzia\instalacja\
#             zaleznosci.ps1 z pobranego ZIP-a (-Akcja Instaluj -Potrzebne git); nadal nie ma ->
#             przenosny MinGit z git-for-windows (GitHub) do %LOCALAPPDATA%\MegaRuchacz\git (tam,
#             gdzie kladzie go zaleznosci.ps1 - skrypty modulow szukaja go tez tam) i jego cmd\ do
#             PATH uzytkownika (bez administratora).
#   -Co klon  git clone repozytorium MegaRuchacza do -Folder (pusty albo nowy; folder z gotowym
#             klonem MegaRuchacza = uzyj go). Klon, nie ZIP: aktualizacje to git fetch + merge.
# Wyjscie jak modul-*.ps1 (umowa z P59b): linie KROK: / UWAGA: i ostatnia
#   WYNIK: {"ok":true/false,"komunikat":"...","kroki":[...], ...}, kod wyjscia 0/1.
#   Dodatkowe pola: git (sciezka git.exe), folder.
# -Proba: zadnego programu nie instaluje (pokazuje, co by pobral); klon idzie NAPRAWDE - test
#   czystego komputera ma sprawdzic pobranie, a folder wskazuje sie tymczasowy.
# Recznie (proba negatywna / test): powershell -ExecutionPolicy Bypass -File instalator\pobierz.ps1 -Co git -Proba
# -UdawajBrakGita (TESTY, tylko z -Proba): zachowuje sie, jakby gita nie bylo - sprawdza droge
#   zaleznosci.ps1 i MinGit na komputerze, ktory gita ma.
param(
  [ValidateSet('git', 'klon')][string]$Co = 'git',
  [string]$Folder = '',
  [string]$Adres = 'https://github.com/Primo2966/MegaRuchacz.git',
  [string]$Zrodlo = '',
  [switch]$Proba,
  [switch]$UdawajBrakGita
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# UTF-8 na czas pracy; stara strona kodowa wraca przy wyjsciu (Wynik) - uruchomiony recznie z konsoli
# nie zostawia jej przestawionej. Pod oknem instalatora stara = UTF-8 okna, wiec nic sie nie zmienia.
$script:StareKodowanie = $null
try { $script:StareKodowanie = [Console]::OutputEncoding; [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) }
catch { Write-Output "UWAGA: konsola bez UTF-8 - polskie litery mogą wyjść krzywo ($($_.Exception.Message))" }

$script:Kroki = New-Object System.Collections.Generic.List[string]
function Krok([string]$t) { $script:Kroki.Add($t); Write-Output "KROK: $t" }
# Bez -Proba udawanie braku gita pobraloby i dopisalo do PATH drugiego gita - odmowa.
if ($UdawajBrakGita -and -not $Proba) {
  Write-Output ('WYNIK: ' + (ConvertTo-Json -InputObject ([ordered]@{ ok = $false; komunikat = '-UdawajBrakGita dziala tylko z -Proba'; kroki = @() }) -Compress))
  exit 1
}
function Uwaga([string]$t) { Write-Output "UWAGA: $t" }
function Wynik([bool]$ok, [string]$komunikat, $dodatki = @{}) {
  $o = [ordered]@{ ok = $ok; komunikat = $komunikat; kroki = [string[]]@($script:Kroki) }
  foreach ($k in $dodatki.Keys) { $o[$k] = $dodatki[$k] }
  Write-Output ('WYNIK: ' + (ConvertTo-Json -InputObject $o -Compress -Depth 4))
  if ($script:StareKodowanie) {
    try { [Console]::Out.Flush(); [Console]::OutputEncoding = $script:StareKodowanie } catch { Write-Error "nie przywrocilem kodowania konsoli: $($_.Exception.Message)" }
  }
  if ($ok) { exit 0 }
  exit 1
}

# PATH tego procesu jest z chwili startu okna - git zainstalowany przed chwila jest tylko
# w rejestrze (PATH uzytkownika / maszyny). Najpierw PATH procesu, potem brakujace z rejestru -
# tak samo jak Odswiez-Path w wykonanie.ps1 (P64: to, co dal wolajacy, wygrywa).
function Odswiez-Path {
  $czesci = New-Object System.Collections.Generic.List[string]
  foreach ($z in @($env:Path, [Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User'))) {
    foreach ($e in "$z".Split(';')) {
      $e = [Environment]::ExpandEnvironmentVariables($e.Trim())
      if ($e -and -not $czesci.Contains($e)) { $czesci.Add($e) }
    }
  }
  $env:Path = ($czesci -join ';')
}

function Znajdz-Gita {
  if ($UdawajBrakGita) { return $null }
  Odswiez-Path
  $g = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($g) { return $g.Source }
  foreach ($p in @("$env:LOCALAPPDATA\MegaRuchacz\git\cmd\git.exe", "$env:ProgramFiles\Git\cmd\git.exe",
                   "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe", "$env:LOCALAPPDATA\Microsoft\WinGet\Links\git.exe")) {
    if ($p -and (Test-Path -LiteralPath $p)) { return $p }
  }
  return $null
}

function Wersja-Gita([string]$git) {
  $poprz = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { return ("$(& $git --version 2>&1)").Trim() }
  catch { Uwaga "nie odczytałem wersji gita ($($_.Exception.Message))"; return '?' }
  finally { $ErrorActionPreference = $poprz }
}

# Dopisanie do PATH uzytkownika z zachowaniem typu wpisu (REG_EXPAND_SZ - inaczej wpisy
# z %USERPROFILE% przestalyby dzialac) i z powiadomieniem Windows o zmianie (SetEnvironmentVariable
# rozsyla WM_SETTINGCHANGE - programy uruchamiane potem z Eksploratora widza nowy PATH).
function Dopisz-Do-Path([string]$katalog) {
  $klucz = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
  try {
    $stara = "$($klucz.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames))"
    if (@($stara.Split(';') | ForEach-Object { $_.Trim().TrimEnd('\') }) -contains $katalog.TrimEnd('\')) { return $false }
    $nowa = (($stara.TrimEnd(';') + ';' + $katalog).TrimStart(';'))
    $klucz.SetValue('Path', $nowa, [Microsoft.Win32.RegistryValueKind]::ExpandString)
  } finally { $klucz.Dispose() }
  [Environment]::SetEnvironmentVariable('MegaRuchaczPowiadomienie', '1', 'User')
  [Environment]::SetEnvironmentVariable('MegaRuchaczPowiadomienie', $null, 'User')
  return $true
}

function Architektura {
  $a = "$env:PROCESSOR_ARCHITEW6432"
  if (-not $a) { $a = "$env:PROCESSOR_ARCHITECTURE" }
  if ($a -eq 'ARM64') { return 'arm64' }
  if ([Environment]::Is64BitOperatingSystem) { return '64-bit' }
  return '32-bit'
}

# --- git -----------------------------------------------------------------------
if ($Co -eq 'git') {
  Krok 'Sprawdzam, czy na komputerze jest program git'
  $git = Znajdz-Gita
  if ($git) {
    Krok "Git jest: $(Wersja-Gita $git)"
    Wynik $true "Git już jest na komputerze ($git)." @{ git = $git }
  }

  $zal = ''
  if ($Zrodlo) { $zal = Join-Path $Zrodlo 'narzedzia\instalacja\zaleznosci.ps1' }
  if ($zal -and (Test-Path -LiteralPath $zal)) {
    Krok 'Gita nie ma - instaluję go narzędziem zależności MegaRuchacza'
    $a = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $zal, '-Akcja', 'Instaluj', '-Potrzebne', 'git')
    if ($Proba) { $a += '-Proba' }
    $wynikZal = $null
    $poprz = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      & (Join-Path $PSHOME 'powershell.exe') @a 2>&1 | ForEach-Object {
        $t = "$_"
        if ($t -match '^\s*KROK:\s*(.*)$') { Krok "git: $($Matches[1].Trim())" }
        elseif ($t -match '^\s*UWAGA:\s*(.*)$') { Uwaga $Matches[1].Trim() }
        elseif ($t -match '^\s*WYNIK:\s*(.*)$') {
          try { $wynikZal = $Matches[1] | ConvertFrom-Json } catch { Uwaga "nieczytelny wynik zaleznosci.ps1: $($_.Exception.Message)" }
        }
        elseif ($t.Trim()) { Write-Output "  zaleznosci: $t" }
      }
      $kod = $LASTEXITCODE
    } finally { $ErrorActionPreference = $poprz }
    $kom = ''
    if ($wynikZal) { $kom = "$($wynikZal.komunikat)" }
    # W probie narzedzie zaleznosci tez tylko udaje - jego "ok" znaczy "zainstalowalbym".
    if ($Proba -and $wynikZal -and ($wynikZal.ok -eq $true) -and ($kod -eq 0)) { Wynik $true "(próba) Gita nie ma - zainstalowałoby go narzędzie zależności. $kom".Trim() @{ git = '' } }
    $git = Znajdz-Gita
    if ($git) {
      Krok "Git jest: $(Wersja-Gita $git)"
      Wynik $true "Zainstalowałem gita ($git)." @{ git = $git }
    }
    Uwaga "Narzędzie zależności nie dało gita (kod $kod$(if ($kom) { ': ' + $kom })) - pobieram wersję przenośną."
  }

  Krok 'Szukam najnowszej przenośnej wersji gita (MinGit z git-for-windows na GitHubie)'
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' -UseBasicParsing -TimeoutSec 30 -Headers @{ 'User-Agent' = 'MegaRuchacz-instalator' }
  } catch { Wynik $false "Nie mogę połączyć się z GitHubem, żeby pobrać gita: $($_.Exception.Message). Sprawdź internet i spróbuj ponownie." }
  $arch = Architektura
  $zasob = @($rel.assets | Where-Object { $_.name -match "^MinGit-[0-9][0-9.]*(-[0-9]+)?-$([regex]::Escape($arch))\.zip$" }) | Select-Object -First 1
  if (-not $zasob) { Wynik $false "W najnowszym wydaniu gita ($($rel.tag_name)) nie ma przenośnej wersji dla tego komputera ($arch)." }
  $mb = [math]::Max(1, [math]::Round($zasob.size / 1MB))
  $cel = Join-Path $env:LOCALAPPDATA 'MegaRuchacz\git'
  if ($Proba) {
    Krok "(próba) Pobrałbym $($zasob.name) ($mb MB) do $cel i dopisał $cel\cmd do PATH"
    Wynik $true "(próba) Gita nie ma - pobrałbym przenośnego $($zasob.name) ($mb MB)." @{ git = ''; adres = $zasob.browser_download_url }
  }
  Krok "Pobieram $($zasob.name) ($mb MB)"
  $zip = Join-Path ([System.IO.Path]::GetTempPath()) $zasob.name
  try { Invoke-WebRequest -Uri $zasob.browser_download_url -OutFile $zip -UseBasicParsing -TimeoutSec 900 }
  catch { Wynik $false "Nie udało się pobrać gita: $($_.Exception.Message). Sprawdź internet i spróbuj ponownie." }
  Krok "Rozpakowuję do $cel"
  try {
    if (Test-Path -LiteralPath $cel) { Remove-Item -LiteralPath $cel -Recurse -Force }
    Expand-Archive -LiteralPath $zip -DestinationPath $cel -Force
    Remove-Item -LiteralPath $zip -Force
  } catch { Wynik $false "Nie udało się rozpakować gita do $($cel): $($_.Exception.Message)" }
  $exe = Join-Path $cel 'cmd\git.exe'
  if (-not (Test-Path -LiteralPath $exe)) { Wynik $false "Po rozpakowaniu nie ma $exe - pobrany plik jest niepełny." }
  Krok 'Dopisuję gita do PATH (tylko dla Ciebie, bez administratora)'
  try { [void](Dopisz-Do-Path (Join-Path $cel 'cmd')) }
  catch { Wynik $false "Git jest w $cel, ale nie dopisałem go do PATH: $($_.Exception.Message)" @{ git = $exe } }
  Krok "Git jest: $(Wersja-Gita $exe)"
  Wynik $true "Pobrałem przenośnego gita ($($zasob.name))." @{ git = $exe }
}

# --- klon ----------------------------------------------------------------------
if (-not $Folder) { Wynik $false 'Nie podano folderu, do którego pobrać MegaRuchacza.' }
try { $Folder = [System.IO.Path]::GetFullPath($Folder).TrimEnd('\') } catch { Wynik $false "Tej ścieżki nie da się użyć: $Folder ($($_.Exception.Message))" }
Krok "Sprawdzam folder $Folder"
if (Test-Path -LiteralPath $Folder) {
  if ((Test-Path -LiteralPath (Join-Path $Folder '.git')) -and (Test-Path -LiteralPath (Join-Path $Folder 'narzedzia\straznik-zasad.ps1'))) {
    Krok 'W tym folderze już jest MegaRuchacz - używam go'
    Wynik $true "MegaRuchacz już był w $Folder." @{ folder = $Folder }
  }
  if (@(Get-ChildItem -LiteralPath $Folder -Force | Select-Object -First 1).Count -gt 0) { Wynik $false "Folder $Folder nie jest pusty - wybierz pusty albo nowy." }
}
$git = Znajdz-Gita
if (-not $git) {
  if ($Proba) { Wynik $true '(próba) Gita nie ma, więc nie pobiorę MegaRuchacza - w prawdziwej instalacji git byłby już zainstalowany krok wcześniej.' @{ folder = $Folder } }
  Wynik $false 'Nie ma programu git - bez niego nie pobiorę MegaRuchacza. Kliknij „Spróbuj ponownie” albo zainstaluj gita i uruchom instalator jeszcze raz.'
}
Krok "Pobieram MegaRuchacza z $Adres"
$env:GIT_TERMINAL_PROMPT = '0'
$linie = New-Object System.Collections.Generic.List[string]
$poprz = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  & $git -c credential.interactive=never clone --progress $Adres $Folder 2>&1 | ForEach-Object {
    # git pisze postep z \r - zostaje ostatni stan kazdej linii.
    $t = ("$_" -split "`r")[-1].Trim()
    if ($t) { $linie.Add($t); Write-Output "  git: $t" }
  }
  $kod = $LASTEXITCODE
} finally { $ErrorActionPreference = $poprz }
if ($kod -ne 0) {
  $calosc = ($linie -join ' ')
  $pow = "git clone nie wyszedł (kod $kod): $(if ($linie.Count) { $linie[$linie.Count - 1] } else { 'bez opisu' })"
  if ($calosc -match 'Could not resolve host|unable to access|Failed to connect|timed out') { $pow = 'Nie mogę połączyć się z GitHubem - sprawdź internet i kliknij „Spróbuj ponownie”.' }
  elseif ($calosc -match 'already exists and is not an empty') { $pow = "Folder $Folder nie jest pusty - wybierz pusty albo nowy." }
  elseif ($calosc -match 'Permission denied|Access is denied|Odmowa dost') { $pow = "Nie mogę pisać w folderze $Folder - wybierz inny (np. w swoim folderze użytkownika)." }
  elseif ($calosc -match 'not found|does not exist|Repository not found') { $pow = "Nie znalazłem repozytorium MegaRuchacza pod adresem $Adres." }
  Wynik $false $pow
}
Krok 'Sprawdzam pobrane pliki'
if (-not (Test-Path -LiteralPath (Join-Path $Folder 'narzedzia\instalacja\stan.ps1'))) { Uwaga 'W pobranym MegaRuchaczu brakuje narzedzia\instalacja\stan.ps1 - wersja na GitHubie jest starsza niż ten instalator.' }
Wynik $true "MegaRuchacz pobrany do $Folder." @{ folder = $Folder; git = $git }
