# Okno instalatora MegaRuchacza (PowerShell 5.1 + WinForms, nic do instalowania).
#
# Uruchamia je instaluj.bat (dwuklik, konsola znika, gdy okno stanie) albo aplikacja przy
# zegarze (przycisk zmiany instalacji):
#   powershell -ExecutionPolicy Bypass -File instalator\okno.ps1 [-Tryb zmiana]
#
# TRYB wybiera samo okno, po tym, co jest na dysku (-Tryb tylko podpowiada):
#   pobieranie - okno chodzi z folderu bez .git (ZIP z GitHuba rozpakowany przez instaluj.bat
#                albo przez uzytkownika): pyta o folder, zdobywa gita, klonuje repo i otwiera
#                instalator z klonu. Klon jest konieczny - aktualizacje to git fetch + merge,
#                folder z ZIP-a nigdy by sie nie odswiezyl (straznik zapisalby "nie-repo" po cichu).
#   nowy       - MegaRuchacza nie ma: powitanie -> wybor -> podsumowanie -> instalacja -> gotowe.
#   zmiana     - jest rejestr ~\.claude\mr\instalacja.json albo slady starej instalacji: wybor
#                z obecnym stanem -> podsumowanie -> zmiany -> gotowe. Odznaczenie zainstalowanej
#                czesci pyta w oknie, z polem "usun tez moje dane" (domyslnie odznaczonym).
#
# KOLEJNOSC (umowa P59c z P59b, od P64): usuniecia -> zaleznosci.ps1 -> baza (nowa instalacja albo tryb
#   zmiany bez bazy) -> wybrane moduly -> wpisz-zasady.ps1. "Usuń MegaRuchacza…": Usun kazdego modulu -> baza Usun.
#   narzedzia\instalacja\modul-<baza|wiedza|lore|kierownik|skille|kopia>.ps1 -Akcja Instaluj|Usun
#     -KatalogDomowy <kat> -Zrodlo <repo> [-Proba] [-UsunDane]
#   narzedzia\instalacja\zaleznosci.ps1 -Akcja Sprawdz|Instaluj -Potrzebne "uv,python,git,node" [-Proba]
#   Wyjscie: linie KROK: / UWAGA: / WYNIK: {"ok":..,"komunikat":..,"kroki":[..]}, kod 0/1 (wykonanie.ps1).
#   Rejestr: narzedzia\instalacja\stan.ps1 (moduly, kopia = {zrodla, cel}, narzedzia).
#
# Parametry:
#   -Tryb nowy|zmiana        podpowiedz (decyduje stan dysku)
#   -Zrodlo <kat>            folder MegaRuchacza (domyslnie katalog nad instalator\)
#   -KatalogDomowy <kat>     podmiana katalogu domowego (testy)
#   -Proba                   skrypty dostaja -Proba, rejestr nie jest zapisywany; w trybie pobieranie
#                            klon idzie NAPRAWDE (do wskazanego folderu), programy tylko na probe
#   -KatalogSkryptow <kat>   skad brac modul-*.ps1, zaleznosci.ps1 i wpisz-zasady.ps1 (testy na atrapach)
#   -ZrodloKlonu <adres>     skad klonowac w trybie pobieranie (domyslnie GitHub)
#   -Znacznik <plik>         plik zapisywany, gdy okno stanie (instaluj.bat czeka na niego)
#   -PozaEkranem             TESTY: okno w (-5000, 0), bez paska zadan i bez aktywacji
#   -Scenariusz <plik>       TESTY: skrypt wczytany kropka po zbudowaniu okna (klika, robi zrzuty)
#   -ScenariuszDalej <plik>  TESTY: scenariusz dla okna uruchomionego z klonu
# Kod wyjscia: 0, 3 = okno nie wstalo (powod w dzienniku, na strumieniu bledow i w okienku).
#
# BUDOWA: ten plik - parametry, dziennik, zamek jednej kopii, wczytanie modulow, tryb, stan
# poczatkowy, petla okna. Reszta lezy obok (kazdy plik ma naglowek, co w nim jest):
#   wyglad.ps1     kolory, kroje, wymiary, klocki okna (wzor: okno nadzorcy)
#   dane.ps1       czesci MegaRuchacza, wykrywanie, roznica i plan, zapis rejestru
#   wykonanie.ps1  kroki w osobnych procesach, odczyt KROK/UWAGA/WYNIK, plan
#   ekrany.ps1     okno, ekrany, pytanie w oknie
#   pobierz.ps1    osobny proces trybu pobieranie: zdobycie gita i klon
#   test-instalatora.ps1  niewidoczna proba na atrapach + zrzuty ekranow
# Modul bez znacznika na koncu (pusty, uciety) = odmowa startu, a nie okno z dziura.
# Pliki z polskimi tekstami: UTF-8 ZE ZNACZNIKIEM BOM i CRLF (bez BOM PowerShell 5.1 czyta ANSI).

param(
  [string]$Tryb = '',
  [string]$Zrodlo = '',
  [string]$KatalogDomowy = '',
  [string]$KatalogSkryptow = '',
  [string]$ZrodloKlonu = 'https://github.com/Primo2966/MegaRuchacz.git',
  [string]$Znacznik = '',
  [switch]$Proba,
  [switch]$PozaEkranem,
  [string]$Scenariusz = '',
  [string]$ScenariuszDalej = ''
)

$ErrorActionPreference = 'Stop'
# Kopia parametru: na poziomie skryptu $Tryb i $script:Tryb to TA SAMA zmienna (PowerShell
# nie rozroznia tez wielkosci liter), a $script:Tryb dostaje nizej tryb ustalony z dysku.
$trybZParametru = $Tryb
# Domyslne sciezki pod param(), nie w nim: $PSScriptRoot w wartosciach domyslnych bywa pusty
# (pulapka PS 5.1 opisana w mapie przy instaluj-globalnie.ps1).
$script:KatalogInstalatora = $PSScriptRoot
if (-not $Zrodlo) { $Zrodlo = Split-Path -Parent $PSScriptRoot }
if (-not $KatalogDomowy) { $KatalogDomowy = $HOME }
$script:Zrodlo          = $Zrodlo.TrimEnd('\')
$script:Dom             = $KatalogDomowy.TrimEnd('\')
$script:KatalogSkryptow = $KatalogSkryptow
$script:ZrodloKlonu     = $ZrodloKlonu
$script:Znacznik        = $Znacznik
$script:Proba           = [bool]$Proba
$script:PozaEkranem     = [bool]$PozaEkranem
$script:ScenariuszDalej = $ScenariuszDalej
$script:Wywrotki        = @()
$script:Utf8BezBom      = New-Object System.Text.UTF8Encoding($false)

# --- dziennik ------------------------------------------------------------------
# Poza .claude: dziennik zalozony w ~\.claude udawalby potem zainstalowane Claude Code
# (wykrywanie narzedzi patrzy na ten folder). Proba pisze do folderu tymczasowego.
$script:DziennikZawiodl = ''
try {
  if ($script:Proba) { $katDz = [System.IO.Path]::GetTempPath(); $nazwaDz = 'MegaRuchacz-instalator-proba.log' }
  else {
    if ($script:Dom -eq $HOME.TrimEnd('\')) { $katDz = Join-Path $env:LOCALAPPDATA 'MegaRuchacz' }
    else { $katDz = Join-Path $script:Dom 'AppData\Local\MegaRuchacz' }
    $nazwaDz = 'instalator.log'
  }
  if (-not (Test-Path -LiteralPath $katDz)) { New-Item -ItemType Directory -Path $katDz -Force | Out-Null }
  $script:Dziennik = Join-Path $katDz $nazwaDz
  if ((Test-Path -LiteralPath $script:Dziennik) -and ((Get-Item -LiteralPath $script:Dziennik).Length -gt 2MB)) {
    Move-Item -LiteralPath $script:Dziennik -Destination "$($script:Dziennik).1" -Force
  }
} catch {
  $script:Dziennik = Join-Path ([System.IO.Path]::GetTempPath()) 'MegaRuchacz-instalator.log'
  $script:DziennikZawiodl = "dziennik w zwyklym miejscu nie wyszedl ($($_.Exception.Message)) - pisze do $($script:Dziennik)"
}

function Zapisz-Dziennik([string]$tekst) {
  try { [System.IO.File]::AppendAllText($script:Dziennik, ("{0} [{1}] {2}`r`n" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PID, $tekst), $script:Utf8BezBom) }
  catch {
    # Nie przerywamy pracy okna, ale nie milczymy: pierwszy taki blad idzie na czerwony pasek okna.
    if (-not $script:DziennikZawiodl) { $script:DziennikZawiodl = "nie zapisuje do dziennika $($script:Dziennik): $($_.Exception.Message)"; $script:Wywrotki += $script:DziennikZawiodl }
  }
}

# Wywrotka samego okna: do dziennika i na czerwony pasek pod naglowkiem (ekrany.ps1).
function Zanotuj-Wywrotke([string]$kontekst, $blad) {
  $opis = "$blad"
  if ($blad -is [System.Management.Automation.ErrorRecord]) {
    $gdzie = ''
    if ($blad.InvocationInfo -and $blad.InvocationInfo.ScriptName) { $gdzie = " ($(Split-Path -Leaf $blad.InvocationInfo.ScriptName), linia $($blad.InvocationInfo.ScriptLineNumber))" }
    $opis = "$($blad.Exception.Message)$gdzie"
  }
  $script:Wywrotki += "${kontekst}: $opis"
  Zapisz-Dziennik "WYWROTKA ${kontekst}: $opis"
  if (Get-Command Odswiez-Pasek-Wywrotek -ErrorAction SilentlyContinue) {
    try { Odswiez-Pasek-Wywrotek } catch { Zapisz-Dziennik "nie pokazalem wywrotki w oknie: $($_.Exception.Message)" }
  }
}

# Okno nie wstanie: powod do dziennika, na strumien bledow, do znacznika (instaluj.bat go
# wypisze) i w okienku - poza testem, bo test nie ma prawa niczego pokazac na ekranie.
function Odmowa-Startu([string]$powod) {
  Zapisz-Dziennik "NIE WSTALEM: $powod"
  if ($script:Znacznik) {
    try { [System.IO.File]::WriteAllText($script:Znacznik, "ODMOWA $powod", $script:Utf8BezBom) } catch { Zapisz-Dziennik "znacznik odmowy nie zapisany: $($_.Exception.Message)" }
  }
  if (-not $script:PozaEkranem) {
    try {
      Add-Type -AssemblyName System.Windows.Forms
      [void][System.Windows.Forms.MessageBox]::Show("Instalator MegaRuchacza nie może wystartować:`r`n`r`n$powod`r`n`r`nPełny zapis: $($script:Dziennik)", 'MegaRuchacz – instalacja', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    } catch { Zapisz-Dziennik "okienko z powodem odmowy sie nie pokazalo: $($_.Exception.Message)" }
  }
  [Console]::Error.WriteLine("instalator: $powod")
  exit 3
}

Zapisz-Dziennik "start okna instalatora: zrodlo $($script:Zrodlo), dom $($script:Dom), proba $($script:Proba), poza ekranem $($script:PozaEkranem)"
if ($script:DziennikZawiodl) { $script:Wywrotki += $script:DziennikZawiodl }
if (@('', 'nowy', 'zmiana') -notcontains $trybZParametru) { Odmowa-Startu "nieznany tryb '$trybZParametru' (dozwolone: nowy, zmiana)" }

try {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  # ShowWindow: proces startowany z ukryta konsola przekazuje SW_HIDE pierwszemu oknu - Form.Show
  # konczy sie bez bledu, a okno jest niewidzialne (zlapane w nadzorcy 24.09.2026). FindWindow:
  # druga kopia instalatora pokazuje pierwsza zamiast otwierac nowa.
  Add-Type -Namespace MegaRuchacz -Name Instalator -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr uchwyt, int jak);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr uchwyt);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string klasa, string tytul);
'@
  if ($script:PozaEkranem) {
    # Okno testowe nie odbiera fokusu i klawiatury uzytkownikowi (WS_EX_NOACTIVATE, pokazanie bez aktywacji).
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
namespace MegaRuchacz {
  public class OknoTestowe : System.Windows.Forms.Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override System.Windows.Forms.CreateParams CreateParams {
      get { System.Windows.Forms.CreateParams cp = base.CreateParams; cp.ExStyle |= 0x08000000; return cp; }
    }
  }
}
'@
  }
} catch { Odmowa-Startu "Windows nie dał okienek PowerShella (WinForms): $($_.Exception.Message)" }

function Wymus-Pokazanie($formularz) {
  try {
    if ($script:PozaEkranem) { [void][MegaRuchacz.Instalator]::ShowWindow($formularz.Handle, 4); return }   # SW_SHOWNOACTIVATE
    [void][MegaRuchacz.Instalator]::ShowWindow($formularz.Handle, 5)   # SW_SHOW
    [void][MegaRuchacz.Instalator]::SetForegroundWindow($formularz.Handle)
  } catch { Zanotuj-Wywrotke "wymuszenie pokazania okna" $_ }
}

# --- moduly okna ---------------------------------------------------------------
$script:ModulyInstalatora = @{}
foreach ($modul in @('wyglad', 'dane', 'wykonanie', 'ekrany')) {
  $plikModulu = Join-Path $PSScriptRoot "$modul.ps1"
  try { . $plikModulu }
  catch { Odmowa-Startu "nie da się wczytać pliku $plikModulu ($($_.Exception.Message))" }
  if (-not $script:ModulyInstalatora[$modul]) { Odmowa-Startu "plik $plikModulu nie wczytał się do końca (jest pusty albo ucięty)" }
}

# Rejestr instalacji - wspolna umowa z modulami, straznikiem i nadzorca.
$plikStanu = Join-Path $script:Zrodlo 'narzedzia\instalacja\stan.ps1'
if (-not (Test-Path -LiteralPath $plikStanu)) { Odmowa-Startu "nie ma pliku $plikStanu - ten folder MegaRuchacza jest za stary albo niekompletny" }
try { . $plikStanu } catch { Odmowa-Startu "nie da się wczytać $plikStanu ($($_.Exception.Message))" }

# --- jedna kopia -----------------------------------------------------------------
# Drugi instalator (dwuklik w trakcie, przycisk w aplikacji przy zegarze) pokazuje pierwszy.
# Test ma wlasny zamek - nie zderza sie ani z prawdziwym oknem, ani z innym testem.
$nazwaZamka = 'Local\MegaRuchacz-Instalator'
if ($script:PozaEkranem) { $nazwaZamka += "-TEST-$PID" }
$script:Zamek = New-Object System.Threading.Mutex($false, $nazwaZamka)
$mojZamek = $false
try { $mojZamek = $script:Zamek.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $mojZamek = $true }
if (-not $mojZamek) {
  Zapisz-Dziennik "instalator juz jest otwarty - pokazuje tamto okno i koncze"
  try {
    $h = [MegaRuchacz.Instalator]::FindWindow($null, $script:TYTUL_OKNA)
    if ($h -ne [IntPtr]::Zero) { [void][MegaRuchacz.Instalator]::ShowWindow($h, 9); [void][MegaRuchacz.Instalator]::SetForegroundWindow($h) }
    if ($script:Znacznik) { [System.IO.File]::WriteAllText($script:Znacznik, "JUZ-OTWARTY $PID", $script:Utf8BezBom) }
  } catch { Zapisz-Dziennik "nie pokazalem otwartego instalatora: $($_.Exception.Message)" }
  exit 0
}

# Przed uruchomieniem instalatora z klonu (tryb pobieranie) - nowe okno musi dostac zamek.
function Zwolnij-Zamek {
  if (-not $script:Zamek) { return }
  try { $script:Zamek.ReleaseMutex() } catch { Zapisz-Dziennik "zwolnienie zamka: $($_.Exception.Message)" }
  $script:Zamek.Dispose()
  $script:Zamek = $null
}

# --- tryb i stan poczatkowy --------------------------------------------------------

# Wolane przy starcie i po odlozeniu uszkodzonego rejestru.
function Ustal-Stan-Poczatkowy {
  $script:Instalacja = Czytaj-Instalacje $script:Dom
  if ($script:Instalacja.blad) { Zapisz-Dziennik "rejestr nieczytelny: $($script:Instalacja.blad)" }
  $script:Obecne = @{}
  foreach ($id in $script:MODULY.Keys) {
    $script:Obecne[$id] = $false
    if ($script:Tryb -eq 'zmiana') { $script:Obecne[$id] = [bool]$script:Instalacja.moduly.$id }
  }
  $kp = Poczatkowa-Kopia
  $script:KopiaNaStart = [pscustomobject]@{ Cel = $kp.Cel; Zrodla = @($kp.Zrodla | Where-Object { $_.Zaznaczone } | ForEach-Object { $_.Sciezka }); Wykluczenia = @($kp.Wykluczenia | Where-Object { $_.Zaznaczone }); Skad = $kp.Skad }
  $mod = @{}
  if ($script:Tryb -eq 'zmiana') { foreach ($id in $script:MODULY.Keys) { $mod[$id] = [bool]$script:Obecne[$id] } }
  else {
    # Makieta uzgodniona z uzytkownikiem: cztery czesci zaznaczone, kopia zapasowa nie.
    foreach ($id in $script:MODULY.Keys) { $mod[$id] = $true }
    $mod['kopia'] = $false
  }
  $zestaw = 'wlasny'
  if (@($mod.Values | Where-Object { -not $_ }).Count -eq 0) { $zestaw = 'wszystko' }
  # UsunWszystko: przycisk "Usuń MegaRuchacza" w trybie zmiany (P64) - razem z baza; zapis instalacji
  # zostaje z "baza": false. BazaJest: hook straznika albo zadanie nadzorcy (dane.ps1 Baza-Jest).
  $script:Wybor = [pscustomobject]@{ Moduly = $mod; UsunDane = @{}; KopiaCel = $kp.Cel; KopiaZrodla = $kp.Zrodla; KopiaWykluczenia = $kp.Wykluczenia; Zestaw = $zestaw; Wlasny = $null
    UsunWszystko = $false; UsunDaneWszystko = $false }
  $script:BazaJest = Baza-Jest
  Zapisz-Dziennik "stan poczatkowy: tryb $($script:Tryb), rejestr $($script:Instalacja.zrodlo), baza $($script:BazaJest), obecne $((@($script:Obecne.Keys | Sort-Object | ForEach-Object { "$_=$($script:Obecne[$_])" })) -join ' '), kopia -> $($kp.Cel) ($($kp.Skad), wykluczen $(@($kp.Wykluczenia).Count))"
}

# Narzedzia wykrywane PRZED czymkolwiek, co pisze w katalogu domowym.
$script:Narzedzia = Wykryj-Narzedzia
$script:FolderDocelowy = Join-Path $script:Dom 'MegaRuchacz'
if (-not (Test-Path -LiteralPath (Join-Path $script:Zrodlo '.git'))) {
  $script:Tryb = 'pobieranie'
} else {
  $slad = Wykryj-Instalacje
  if ($slad) { $script:Tryb = 'zmiana' } else { $script:Tryb = 'nowy' }
  if (($trybZParametru -eq 'zmiana') -and -not $slad) { Zapisz-Dziennik "-Tryb zmiana, ale MegaRuchacza tu nie ma - pokazuje nowa instalacje" }
  if (($trybZParametru -eq 'nowy') -and $slad) { Zapisz-Dziennik "-Tryb nowy, ale MegaRuchacz juz jest ($slad) - pokazuje zmiane instalacji" }
}
try { Ustal-Stan-Poczatkowy } catch { Odmowa-Startu "nie ustaliłem, co jest zainstalowane: $($_.Exception.Message)" }

# Polskie znaki ze skryptow-dzieci: dzieci dziela z oknem (niewidoczna) konsole, wiec biora
# jej strone kodowa - UTF-8 ustawione tutaj (wykonanie.ps1). Stara strona wraca przy wyjsciu.
$script:StareKodowanie = $null
try {
  $script:StareKodowanie = [Console]::OutputEncoding
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch { Zapisz-Dziennik "konsola bez UTF-8 ($($_.Exception.Message)) - polskie znaki skryptow czytam awaryjnie w stronie kodowej OEM" }

# --- okno ----------------------------------------------------------------------
try {
  [System.Windows.Forms.Application]::EnableVisualStyles()
  Zbuduj-Okno
  $script:PoTyknieciu = { Odmaluj-Biezacy }
  switch ($script:Tryb) {
    'pobieranie' { Pokaz-Ekran 'folder' }
    'zmiana'     { Pokaz-Ekran 'wybor' }
    default      { Pokaz-Ekran 'powitanie' }
  }
} catch { Odmowa-Startu "okno się nie zbudowało: $($_.Exception.Message) (linia $($_.InvocationInfo.ScriptLineNumber) w $($_.InvocationInfo.ScriptName))" }

if ($Scenariusz) {
  try { . $Scenariusz } catch { Zanotuj-Wywrotke "scenariusz testu $Scenariusz" $_ }
}

try {
  [System.Windows.Forms.Application]::Run($script:Okno)
} catch {
  Zanotuj-Wywrotke "petla okna" $_
} finally {
  Zwolnij-Zamek
  if ($script:StareKodowanie) {
    try { [Console]::OutputEncoding = $script:StareKodowanie } catch { Zapisz-Dziennik "nie przywrocilem kodowania konsoli: $($_.Exception.Message)" }
  }
  Zapisz-Dziennik "koniec okna instalatora"
}
exit 0
