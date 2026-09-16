# Liczy, ile kosztuje pamiec agenta: ile znakow dokleja sie do KAZDEJ rozmowy
# z warstwy stalej i biezacej, ile to daje przez dobe, i czy ktoras warstwa nie
# zaczyna puchnac. Czysta arytmetyka na plikach - zaden model nie jest wolany.
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File narzedzia\koszt-pamieci.ps1
#     -KatalogDomowy <kat>   podmiana bazy sciezek (domyslnie katalog domowy; testy)
#     -Zwiezle               jedna linia podsumowania zamiast pelnego raportu
#     -ZalozZadanie          codzienny raport o 08:15 do <dom>\.claude\wiedza\koszt-ostatni.txt
#     -UsunZadanie           kasuje to zadanie
#
# Skrypt TYLKO CZYTA CLAUDE.md - nigdy do niego nie pisze. Brak pliku, brak sekcji,
# brak katalogu wiedzy czy bazy Lore to nie awaria, tylko mniej danych w raporcie.

param(
  [string]$KatalogDomowy = $HOME,
  [switch]$Zwiezle,
  [switch]$ZalozZadanie,
  [switch]$UsunZadanie
)

$ZnacznikStart  = "<!-- MegaRuchacz:start -->"
$ZnacznikKoniec = "<!-- MegaRuchacz:koniec -->"

$NazwaZadania   = "LoreKoszt"
$GodzinaZadania = "08:15"

# ~3 znaki na token to przyblizenie dla polszczyzny - patrz adnotacja w raporcie
$ZnakiNaToken   = 3
$DniWaznosci    = 14
$ProgStalej     = 8000
$ProgBiezacych  = 15
$ProgPoczekalni = 10

$script:Raport = @()

function Linia($tekst) { $script:Raport += $tekst }

# --- liczby i teksty ---------------------------------------------------------

function Liczba($n) {
  # separator tysiecy na sztywno spacja: N0 idzie za ustawieniami regionalnymi,
  # a te potrafia wstawic znak, ktory w konsoli wyglada jak smiec
  return ([long]$n).ToString("#,0", [Globalization.CultureInfo]::InvariantCulture).Replace(",", " ")
}

function Rozmiar($bajty) {
  if ($bajty -lt 1024)    { return "$bajty B" }
  if ($bajty -lt 1048576) { return "$([math]::Round($bajty / 1024, 1)) KB" }
  return "$([math]::Round($bajty / 1048576, 1)) MB"
}

function Skroc($tekst, $ile) {
  if ($tekst.Length -le $ile) { return $tekst }
  return $tekst.Substring(0, $ile - 3) + "..."
}

# --- czytanie pliku ----------------------------------------------------------

function Czytaj($sciezka) {
  # UTF-8 bez rzucania bledem: zepsuty znak w cudzych zapiskach ma nie wywalic
  # raportu, bo to i tak konczy sie na policzeniu znakow
  return [System.IO.File]::ReadAllText($sciezka, (New-Object System.Text.UTF8Encoding($false)))
}

# --- warstwy -----------------------------------------------------------------

function Granice-Sekcji($linie, $start, $koniec) {
  # zwraca @(poczatek, koniec) - koniec wylacznie; @(-1, -1) gdy naglowka nie ma
  $i = -1
  for ($k = 0; $k -lt $linie.Count; $k++) {
    if ($linie[$k] -match $start) { $i = $k; break }
  }
  if ($i -lt 0) { return @(-1, -1) }
  $j = $linie.Count
  for ($k = $i + 1; $k -lt $linie.Count; $k++) {
    if ($linie[$k] -match $koniec) { $j = $k; break }
  }
  return @($i, $j)
}

function Linie-Zakresu($linie, $od, $doo) {
  if ($od -lt 0 -or $doo -le $od) { return @() }
  return @($linie[$od..($doo - 1)])
}

function Miara($linie) {
  $l = @($linie)
  $znaki = ($l -join "`n").Length
  return [pscustomobject]@{
    Linie  = $l.Count
    Znaki  = $znaki
    Tokeny = [int][math]::Ceiling($znaki / $ZnakiNaToken)
  }
}

function Czytaj-Wpisy($linie) {
  $dzis = [datetime]::Today
  $wpisy = @()
  foreach ($l in @($linie)) {
    $m = [regex]::Match($l, '^\s*-\s*\[(\d{4}-\d{2}-\d{2})\]\s*(.*)$')
    if (-not $m.Success) { continue }
    $data = $null
    try {
      $data = [datetime]::ParseExact($m.Groups[1].Value, 'yyyy-MM-dd',
                                     [Globalization.CultureInfo]::InvariantCulture)
    } catch { $data = $null }
    $wiek = 0
    if ($data) { $wiek = ($dzis - $data).Days }
    $wpisy += [pscustomobject]@{
      Data  = $m.Groups[1].Value
      Tresc = $m.Groups[2].Value.Trim()
      Wiek  = $wiek
      Stary = (($data -ne $null) -and ($wiek -gt $DniWaznosci))
    }
  }
  return $wpisy
}

function Zmierz-Warstwy($plik) {
  $pusta = Miara @()
  $wynik = [pscustomobject]@{
    Jest     = $false
    MaSekcje = $false
    Blok     = $pusta
    Stala    = $pusta
    Biezaca  = $pusta
    Wpisy    = @()
  }
  if (-not (Test-Path -LiteralPath $plik)) { return $wynik }

  try { $tekst = Czytaj $plik }
  catch { return $wynik }

  $wynik.Jest = $true
  $tekst = $tekst -replace "`r`n", "`n"

  # blok zasad wycinamy z tekstu od razu: ma wlasny rachunek, a gdyby zostal,
  # doliczylby sie drugi raz do sekcji, w ktorej akurat siedzi
  $i = $tekst.IndexOf($ZnacznikStart, [System.StringComparison]::Ordinal)
  $j = $tekst.IndexOf($ZnacznikKoniec, [System.StringComparison]::Ordinal)
  if ($i -ge 0 -and $j -gt $i) {
    $dlugosc = $j + $ZnacznikKoniec.Length - $i
    $wynik.Blok = Miara @($tekst.Substring($i, $dlugosc) -split "`n")
    $tekst = $tekst.Remove($i, $dlugosc)
  }

  $linie = @($tekst -split "`n")

  # "## Co wiem" konczy sie na najblizszym naglowku pierwszego lub drugiego poziomu;
  # "###" do wzorca nie pasuje, bo po dwoch krzyzykach musi stac bialy znak
  $g = @(Granice-Sekcji $linie '^##\s+Co\s+wiem' '^#{1,2}\s')
  if ($g[0] -lt 0) { return $wynik }
  $wynik.MaSekcje = $true
  $coWiem = @(Linie-Zakresu $linie $g[0] $g[1])

  # "Bie" zamiast pelnego slowa: ten plik jest bez polskich znakow, a naglowek
  # w CLAUDE.md bywa pisany i z ogonkami, i bez
  $gb = @(Granice-Sekcji $coWiem '^###\s+Bie' '^#{1,3}\s')
  if ($gb[0] -lt 0) {
    $wynik.Stala = Miara $coWiem
    return $wynik
  }

  $biezace = @(Linie-Zakresu $coWiem $gb[0] $gb[1])
  $stala = @(Linie-Zakresu $coWiem 0 $gb[0]) + @(Linie-Zakresu $coWiem $gb[1] $coWiem.Count)
  $wynik.Stala   = Miara $stala
  $wynik.Biezaca = Miara $biezace
  $wynik.Wpisy   = @(Czytaj-Wpisy $biezace)
  return $wynik
}

# --- baza Lore ---------------------------------------------------------------

# Odczyt jednej liczby z lore.db bez zadnych zaleznosci: winsqlite3.dll siedzi
# w System32 kazdego Windowsa 10/11. Otwieramy do zapisu (ale bez CREATE), bo baza
# chodzi w trybie WAL, a polaczenie tylko do odczytu potrafi sie o to wylozyc.
$KodSqlite = @'
using System;
using System.Runtime.InteropServices;
public static class MalySqlite {
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_open_v2", CallingConvention=CallingConvention.Cdecl)]
  static extern int Open(byte[] plik, out IntPtr db, int flagi, IntPtr vfs);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_busy_timeout", CallingConvention=CallingConvention.Cdecl)]
  static extern int Busy(IntPtr db, int ms);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_prepare_v2", CallingConvention=CallingConvention.Cdecl)]
  static extern int Prepare(IntPtr db, byte[] sql, int n, out IntPtr st, IntPtr ogon);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_step", CallingConvention=CallingConvention.Cdecl)]
  static extern int Step(IntPtr st);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_column_int64", CallingConvention=CallingConvention.Cdecl)]
  static extern long Kolumna(IntPtr st, int i);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_finalize", CallingConvention=CallingConvention.Cdecl)]
  static extern int Koniec(IntPtr st);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_close_v2", CallingConvention=CallingConvention.Cdecl)]
  static extern int Zamknij(IntPtr db);

  public static long Licz(string plik, string sql) {
    IntPtr db = IntPtr.Zero;
    IntPtr st = IntPtr.Zero;
    int rc = Open(System.Text.Encoding.UTF8.GetBytes(plik + "\0"), out db, 0x00000002, IntPtr.Zero);
    if (rc != 0) { if (db != IntPtr.Zero) { Zamknij(db); } throw new Exception("otwarcie bazy, kod " + rc); }
    try {
      Busy(db, 3000);
      rc = Prepare(db, System.Text.Encoding.UTF8.GetBytes(sql + "\0"), -1, out st, IntPtr.Zero);
      if (rc != 0) { throw new Exception("zapytanie, kod " + rc); }
      long wynik = 0;
      if (Step(st) == 100) { wynik = Kolumna(st, 0); }   // 100 = SQLITE_ROW
      return wynik;
    } finally {
      if (st != IntPtr.Zero) { Koniec(st); }
      if (db != IntPtr.Zero) { Zamknij(db); }
    }
  }
}
'@

function Policz-Sesje($baza) {
  # ile roznych sesji zostawilo slad w ostatniej dobie
  if (-not (Test-Path -LiteralPath $baza)) {
    return [pscustomobject]@{ Ok = $false; Ile = 0; Powod = "nie ma bazy Lore: $baza" }
  }
  try {
    if (-not ("MalySqlite" -as [type])) { Add-Type -TypeDefinition $KodSqlite -ErrorAction Stop }
    # ts w tabeli chunks to ISO UTC ("2026-09-11T06:27:15.470Z"), wiec zwykle
    # porownanie tekstowe z obcieta granica daje poprawny wynik
    $granica = ([datetime]::UtcNow.AddDays(-1)).ToString("yyyy-MM-ddTHH:mm:ss")
    $sql = "SELECT count(DISTINCT session) FROM chunks WHERE ts >= '$granica'"
    $ile = [MalySqlite]::Licz($baza, $sql)
    return [pscustomobject]@{ Ok = $true; Ile = [long]$ile; Powod = $null }
  } catch {
    return [pscustomobject]@{ Ok = $false; Ile = 0; Powod = "nie umiem odczytac $baza ($($_.Exception.Message))" }
  }
}

# --- zadanie w harmonogramie -------------------------------------------------

function Zaloz-Zadanie($skrypt, $dom, $plikRaportu) {
  # katalog musi istniec wczesniej - Set-Content nie zaklada brakujacych katalogow
  $katalog = Split-Path -Parent $plikRaportu
  if (-not (Test-Path -LiteralPath $katalog)) {
    New-Item -ItemType Directory -Force -Path $katalog | Out-Null
    Write-Host "  zalozony katalog $katalog"
  }

  $s = $skrypt      -replace "'", "''"
  $d = $dom         -replace "'", "''"
  $r = $plikRaportu -replace "'", "''"
  $polecenie = "& '$s' -KatalogDomowy '$d' | Set-Content -LiteralPath '$r' -Encoding UTF8"
  # conhost --headless: raport leci raz dziennie i nikt nie chce mrugniecia konsoli
  $argumenty = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ""$polecenie"""

  # UWAGA - tak samo jak w instaluj-lore.ps1: zakladanie zadania przez obiekty
  # (New-ScheduledTaskPrincipal + -Principal) konczy sie "Odmowa dostepu"
  # u zwyklego uzytkownika. Ten sam zapis podany jako XML przechodzi. Dlatego XML.
  try {
    $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $start = (Get-Date -Format "yyyy-MM-dd") + "T" + $GodzinaZadania + ":00"
    $argXml = [System.Security.SecurityElement]::Escape($argumenty)
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>MegaRuchacz - dzienny raport o koszcie pamieci agenta</Description>
    <URI>\$NazwaZadania</URI>
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
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>$start</StartBoundary>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
      <Enabled>true</Enabled>
    </CalendarTrigger>
  </Triggers>
  <Actions Context="Author">
    <Exec>
      <Command>conhost.exe</Command>
      <Arguments>$argXml</Arguments>
    </Exec>
  </Actions>
</Task>
"@
    Register-ScheduledTask -TaskName $NazwaZadania -Xml $xml -Force -ErrorAction Stop | Out-Null
  } catch {
    Write-Host "BLAD  nie udalo sie zalozyc zadania: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
  }
  Write-Host "OK  zadanie $NazwaZadania - codziennie o $GodzinaZadania, raport do $plikRaportu"
  Write-Host "    po wylaczonym komputerze nadrobi przy najblizszym wlaczeniu"
  exit 0
}

function Usun-Zadanie {
  $jest = Get-ScheduledTask -TaskName $NazwaZadania -ErrorAction SilentlyContinue
  if (-not $jest) {
    Write-Host "--  nie ma zadania $NazwaZadania, nie ma czego usuwac"
    exit 0
  }
  try { Unregister-ScheduledTask -TaskName $NazwaZadania -Confirm:$false -ErrorAction Stop }
  catch {
    Write-Host "BLAD  nie udalo sie usunac zadania: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
  }
  Write-Host "OK  zadanie $NazwaZadania usuniete"
  exit 0
}

# --- przebieg ----------------------------------------------------------------

if (-not (Test-Path -LiteralPath $KatalogDomowy)) {
  Write-Error "Nie ma takiego katalogu domowego: $KatalogDomowy"
  exit 1
}
$KatalogDomowy = (Resolve-Path -LiteralPath $KatalogDomowy).Path

$katKlaudii   = Join-Path $KatalogDomowy ".claude"
$plikClaude   = Join-Path $katKlaudii "CLAUDE.md"
$katWiedzy    = Join-Path $katKlaudii "wiedza"
$plikKandydat = Join-Path $katWiedzy "kandydaci.md"
$plikOstatni  = Join-Path $katWiedzy "koszt-ostatni.txt"
$bazaLore     = Join-Path $katKlaudii "lore.db"

if ($UsunZadanie)  { Usun-Zadanie }
if ($ZalozZadanie) { Zaloz-Zadanie $PSCommandPath $KatalogDomowy $plikOstatni }

$w = Zmierz-Warstwy $plikClaude

$razemZnakow  = $w.Blok.Znaki + $w.Stala.Znaki + $w.Biezaca.Znaki
$razemLinii   = $w.Blok.Linie + $w.Stala.Linie + $w.Biezaca.Linie
$razemTokenow = [int][math]::Ceiling($razemZnakow / $ZnakiNaToken)

$sesje = Policz-Sesje $bazaLore

# warstwa referencyjna: kandydaci i wlasny raport maja ponizej osobne linie,
# wiec tutaj ich nie liczymy drugi raz
$pliki = @()
if (Test-Path -LiteralPath $katWiedzy) {
  $pliki = @(Get-ChildItem -LiteralPath $katWiedzy -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -ne "kandydaci.md" -and $_.Name -ne "koszt-ostatni.txt" })
}
$bajtyWiedzy = 0
foreach ($p in $pliki) { $bajtyWiedzy += $p.Length }

$kandydaci = $null
if (Test-Path -LiteralPath $plikKandydat) {
  $kandydaci = 0
  try {
    foreach ($l in @((Czytaj $plikKandydat) -split "`r?`n")) {
      if ($l -match '^\s*-\s*\[\s\]') { $kandydaci++ }
    }
  } catch { $kandydaci = $null }
}

$stare = @($w.Wpisy | Where-Object { $_.Stary })

# --- ostrzezenia -------------------------------------------------------------

$ostrzezenia = @()
if ($w.Stala.Znaki -gt $ProgStalej) {
  $ostrzezenia += "Warstwa stala ma $(Liczba $w.Stala.Znaki) znakow (prog $(Liczba $ProgStalej)) - przenies rzadziej potrzebne rzeczy do $katWiedzy, stamtad nie doklejaja sie do kazdej rozmowy."
}
if ($w.Wpisy.Count -gt $ProgBiezacych) {
  $ostrzezenia += "Warstwa biezaca ma $($w.Wpisy.Count) wpisow (prog $ProgBiezacych) - przejrzyj je i skasuj to, co juz nieaktualne."
}
if ($stare.Count -gt 0) {
  $ostrzezenia += "Przeterminowanych wpisow: $($stare.Count) - agent bierze je za prawde, wiec albo odswiez date, albo skasuj."
}
if (($kandydaci -ne $null) -and ($kandydaci -gt $ProgPoczekalni)) {
  $ostrzezenia += "W poczekalni czeka $kandydaci faktow (prog $ProgPoczekalni) - zatwierdz je albo odrzuc, bo same sie nie zuzyja."
}

# --- wypisanie ---------------------------------------------------------------

if ($Zwiezle) {
  if (-not $w.Jest) {
    Write-Output "Pamiec agenta: nie ma pliku $plikClaude - nic nie dokleja sie do rozmow."
    exit 0
  }
  $dziennie = "dziennie: brak danych o sesjach"
  if ($sesje.Ok) { $dziennie = "~$(Liczba ($razemTokenow * $sesje.Ile)) dziennie przy $($sesje.Ile) sesjach" }
  $pocz = "poczekalnia pusta"
  if ($kandydaci -ne $null) { $pocz = "poczekalnia $kandydaci" }
  Write-Output "Pamiec agenta: ~$(Liczba $razemTokenow) tokenow na rozmowe, $dziennie; biezace $($w.Wpisy.Count) wpisow ($($stare.Count) przeterminowanych), $pocz; ostrzezen: $($ostrzezenia.Count)"
  exit 0
}

function Wiersz($nazwa, $m) {
  Linia ("  {0,-26} {1,5} linii, {2,9} znakow, ~{3,7} tokenow" -f $nazwa, (Liczba $m.Linie), (Liczba $m.Znaki), (Liczba $m.Tokeny))
}

Linia ""
Linia "Koszt pamieci agenta - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Linia "Katalog: $katKlaudii"

Linia ""
Linia "1. Doklejane do KAZDEJ rozmowy"
if (-not $w.Jest) {
  Linia "  Nie ma pliku $plikClaude - czyli nic stad nie dokleja sie do rozmow."
} else {
  Wiersz "blok zasad instalatora" $w.Blok
  Wiersz "warstwa STALA (Co wiem)" $w.Stala
  Wiersz "warstwa BIEZACA" $w.Biezaca
  Linia ("  {0,-26} {1,5} linii, {2,9} znakow, ~{3,7} tokenow" -f "RAZEM za jedna rozmowe", (Liczba $razemLinii), (Liczba $razemZnakow), (Liczba $razemTokenow))
  if ($w.Blok.Znaki -eq 0) { Linia "  (bloku zasad MegaRuchacza w tym pliku nie ma)" }
  if (-not $w.MaSekcje)    { Linia "  (sekcji '## Co wiem' w tym pliku nie ma - warstwa stala i biezaca sa puste)" }
  Linia "  Tokeny to SZACUNEK, nie pomiar: przyjete ~$ZnakiNaToken znaki na token dla polszczyzny."
}

Linia ""
Linia "2. Ile to daje przez dobe"
if (-not $w.Jest) {
  Linia "  Koszt jednostkowy jest zerowy, wiec nie ma czego mnozyc przez liczbe sesji."
} elseif (-not $sesje.Ok) {
  Linia "  Nie da sie policzyc: $($sesje.Powod)."
  Linia "  Zostaje sam koszt jednostkowy: ~$(Liczba $razemTokenow) tokenow za kazda rozmowe."
} elseif ($sesje.Ile -eq 0) {
  Linia "  W ostatniej dobie nie bylo ani jednej sesji - dzis ta pamiec nic nie kosztowala."
  Linia "  Koszt jednostkowy: ~$(Liczba $razemTokenow) tokenow za kazda rozmowe."
} else {
  Linia "  Sesji w ostatniej dobie: $($sesje.Ile)"
  Linia "  $(Liczba $razemTokenow) tokenow x $($sesje.Ile) sesji = ~$(Liczba ($razemTokenow * $sesje.Ile)) tokenow doklejonych przez dobe."
}

Linia ""
Linia "3. Warstwa referencyjna ($katWiedzy)"
if (-not (Test-Path -LiteralPath $katWiedzy)) {
  Linia "  Nie ma tego katalogu - warstwy referencyjnej jeszcze nie ma."
} else {
  Linia "  Plikow: $($pliki.Count), lacznie $(Rozmiar $bajtyWiedzy)"
  Linia "  To NIE jest doklejane do rozmow. Nie kosztuje nic, dopoki agent po to nie siegnie -"
  Linia "  wiec ta warstwa moze byc duza, nie bedac droga. Tu przenosi sie to, co puchnie wyzej."
}

Linia ""
Linia "4. Poczekalnia ($plikKandydat)"
if ($kandydaci -eq $null) {
  Linia "  Nie ma pliku kandydatow - nic nie czeka na decyzje. To normalne."
} else {
  Linia "  Faktow czeka na zatwierdzenie: $kandydaci"
}

Linia ""
Linia "5. Higiena warstwy biezacej (wpis wazny przez $DniWaznosci dni)"
if ((-not $w.Jest) -or (-not $w.MaSekcje)) {
  Linia "  Brak danych - nie ma czego sprawdzac."
} elseif ($w.Wpisy.Count -eq 0) {
  Linia "  Nie ma ani jednego wpisu w formacie - [RRRR-MM-DD] tresc."
} else {
  Linia "  Wpisow: $($w.Wpisy.Count), w tym przeterminowanych: $($stare.Count)"
  foreach ($s in $stare) {
    Linia "    [$($s.Data)] ($($s.Wiek) dni) $(Skroc $s.Tresc 70)"
  }
}

Linia ""
Linia "6. Ostrzezenia"
if ($ostrzezenia.Count -eq 0) {
  Linia "  Nic nie wymaga uwagi - pamiec trzyma sie w rozsadnych rozmiarach."
} else {
  foreach ($o in $ostrzezenia) { Linia "  UWAGA  $o" }
}
Linia ""

foreach ($l in $script:Raport) { Write-Output $l }
exit 0
