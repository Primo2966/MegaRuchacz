# Audyt sufitow pamieci i zasad. Odpowiada na dwa pytania, ktore nie moga zostac
# bez odpowiedzi: CZY COS JEST UCINANE PO CICHU i CZY KOSZT ROSNIE NIEZAUWAZENIE.
# Poza tym liczy, ile znakow dokleja sie do KAZDEJ wiadomosci z warstwy stalej
# i biezacej, ile to daje przez dobe, i porownuje to z poprzednim pomiarem.
# Czysta arytmetyka na plikach - zaden model nie jest wolany.
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File narzedzia\koszt-pamieci.ps1
#     -KatalogDomowy <kat>   podmiana bazy sciezek (domyslnie katalog domowy; testy)
#     -Zrodlo <kat>          katalog narzedzia (domyslnie katalog nad tym skryptem)
#     -Projekt <kat>         projekt z wdrozonym Codeksem: mierzymy wtedy ladunki
#                            hookow, ktore tam naprawde leza, a nie same szablony
#     -TylkoSufity           SAME sufity: kazda para (ladunek, limit) w jednej linii,
#                            kod 1 gdy cokolwiek wystaje - do odpalenia po kazdej
#                            zmianie zasad, bez czekania na reszte raportu
#     -Zwiezle               DOKLADNIE JEDNA linia do pokazania przy starcie sesji
#     -Zwykly                bez kolorow (do zapisu wydruku w pliku)
#     -ZalozZadanie          codzienny raport o 08:15 do <dom>\.claude\wiedza\koszt-ostatni.txt
#     -UsunZadanie           kasuje to zadanie
#
# Kod wyjscia: 0 gdy nic nie jest ucinane, 1 gdy cokolwiek jest - zeby dalo sie
# to podpiac jako sprawdzenie.
#
# WARTOSCI SUFITOW CZYTAMY Z PLIKOW, KTORE JE USTALAJA (straznik, hooks.json,
# facts.py, index.py). Wpisane tu na sztywno zaczelyby klamac przy pierwszej
# zmianie tamtych plikow - a audyt, ktory klamie, jest gorszy niz jego brak.
#
# Skrypt TYLKO CZYTA CLAUDE.md - nigdy do niego nie pisze. Brak pliku, brak sekcji,
# brak katalogu wiedzy czy bazy Lore to nie awaria, tylko mniej danych w raporcie.

param(
  [string]$KatalogDomowy = $HOME,
  [string]$Zrodlo = "",
  [string]$Projekt = "",
  [switch]$TylkoSufity,
  [switch]$Zwiezle,
  [switch]$Zwykly,
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
# powyzej tylu procent sufitu wiersz jest zolty - zapas konczy sie wczesniej,
# niz czlowiek zdazy zauwazyc
$ProgCiasno     = 80
# wzrost kosztu od poprzedniego pomiaru, ktory ma byc widoczny jako ostrzezenie
$ProgWzrostu    = 20

# Przedrostek ladunku hooka startowego Codeksa - MUSI brzmiec tak samo jak
# w straznik-zasad.ps1 (Zbuduj-Sesje-Codex) i w wdroz.ps1, bo inaczej liczymy
# dlugosc czegos, czego nikt nie wysyla.
$PrzedrostekZasad = "Zasady pracy w tym projekcie (tryb MegaRuchacz). Stosuj je przez cala sesje:`n`n"

$script:Raport = @()

function Linia($tekst, $kolor = $null) {
  $script:Raport += [pscustomobject]@{ Tekst = $tekst; Kolor = $kolor }
}

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
  if (-not $tekst) { return "" }
  if ($tekst.Length -le $ile) { return $tekst }
  return $tekst.Substring(0, $ile - 3) + "..."
}

# --- czytanie pliku ----------------------------------------------------------

function Czytaj($sciezka) {
  # UTF-8 bez rzucania bledem: zepsuty znak w cudzych zapiskach ma nie wywalic
  # raportu, bo to i tak konczy sie na policzeniu znakow
  return [System.IO.File]::ReadAllText($sciezka, (New-Object System.Text.UTF8Encoding($false)))
}

function Czytaj-Cicho($sciezka) {
  if (-not $sciezka) { return $null }
  if (-not (Test-Path -LiteralPath $sciezka)) { return $null }
  try { return Czytaj $sciezka } catch { return $null }
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

# --- sufity ------------------------------------------------------------------

function Limit-Z-Pliku($plik, $wzorzec) {
  # jedna liczba wyluskana ze zrodla, ktore ja naprawde ustala; $null, gdy pliku
  # nie ma albo wzorzec nie pasuje - wtedy raport mowi "nie znam sufitu" zamiast
  # podawac wartosc z pamieci
  $tekst = Czytaj-Cicho $plik
  if (-not $tekst) { return $null }
  $m = [regex]::Match($tekst, $wzorzec)
  if (-not $m.Success) { return $null }
  $cyfry = ($m.Groups[1].Value -replace '[^\d]', '')
  if (-not $cyfry) { return $null }
  return [int]$cyfry
}

function Limit-Hooka($plikHookow, $fragmentPolecenia) {
  # additionalContextLimit hooka rozpoznanego po tym, jaki plik wczytuje
  $tekst = Czytaj-Cicho $plikHookow
  if (-not $tekst) { return $null }
  try { $j = $tekst | ConvertFrom-Json } catch { return $null }
  if (-not $j.hooks) { return $null }
  foreach ($zdarzenie in $j.hooks.PSObject.Properties) {
    foreach ($grupa in @($zdarzenie.Value)) {
      foreach ($h in @($grupa.hooks)) {
        if (-not $h) { continue }
        if ($h.PSObject.Properties.Name -notcontains "additionalContextLimit") { continue }
        $polecenie = "" + $h.command + " " + $h.commandWindows
        if ($polecenie -like "*$fragmentPolecenia*") { return [int]$h.additionalContextLimit }
      }
    }
  }
  return $null
}

function Ladunek-Hooka($plikJson) {
  # tresc, ktora hook naprawde wysyla (additionalContext z gotowego ladunku)
  $tekst = Czytaj-Cicho $plikJson
  if (-not $tekst) { return $null }
  try { $j = $tekst | ConvertFrom-Json } catch { return $null }
  if (-not $j.hookSpecificOutput) { return $null }
  $tresc = [string]$j.hookSpecificOutput.additionalContext
  if (-not $tresc) { return $null }
  return $tresc
}

function Znaki-W-Bajtach($tresc, $bajty) {
  # ile ZNAKOW miesci sie w podanej liczbie bajtow UTF-8 - sufit AGENTS.md jest
  # w bajtach, a naglowka szukamy w tekscie
  $enc = New-Object System.Text.UTF8Encoding($false)
  if ($enc.GetByteCount($tresc) -le $bajty) { return $tresc.Length }
  $lo = 0
  $hi = $tresc.Length
  while ($lo -lt $hi) {
    $sr = [int][math]::Floor(($lo + $hi + 1) / 2)
    if ($enc.GetByteCount($tresc.Substring(0, $sr)) -le $bajty) { $lo = $sr } else { $hi = $sr - 1 }
  }
  return $lo
}

function Pierwszy-Utracony-Naglowek($tresc, $limit, $jednostka) {
  # od ktorego naglowka zaczyna sie czesc, ktora przepada - zeby bylo widac,
  # CO konkretnie ginie, a nie tylko ile znakow
  if (-not $tresc) { return $null }
  $ciecie = $limit
  if ($jednostka -eq "bajtow") { $ciecie = Znaki-W-Bajtach $tresc $limit }
  if ($ciecie -ge $tresc.Length) { return $null }
  $m = [regex]::Match($tresc.Substring($ciecie), '(?m)^#{1,6}\s+.+$')
  if (-not $m.Success) { return $null }
  return $m.Value.Trim()
}

function Sufit($pola) {
  # Pola obowiazkowe: Nazwa, Krotka, Teraz, Limit, Jednostka, Czyj, SkadLimitu,
  # Plik, Skutek, Ucina. Nieobowiazkowe: Tresc, Uwaga, Informacyjny.
  # Teraz albo Limit rowne $null znacza "nie zmierzone" - i tak to wypisujemy.
  $s = [pscustomobject]$pola
  foreach ($k in @("Nazwa","Krotka","Teraz","Limit","Jednostka","Czyj","SkadLimitu",
                   "Plik","Skutek","Ucina","Tresc","Uwaga","Informacyjny")) {
    if ($s.PSObject.Properties.Name -notcontains $k) {
      $s | Add-Member -NotePropertyName $k -NotePropertyValue $null
    }
  }
  $zmierzony = (($s.Teraz -ne $null) -and ($s.Limit -ne $null) -and ([int]$s.Limit -gt 0))
  $s | Add-Member -NotePropertyName "Zmierzony"    -NotePropertyValue $zmierzony
  $s | Add-Member -NotePropertyName "Procent"      -NotePropertyValue 0
  $s | Add-Member -NotePropertyName "Zapas"        -NotePropertyValue 0
  $s | Add-Member -NotePropertyName "Przekroczony" -NotePropertyValue $false
  $s | Add-Member -NotePropertyName "Strata"       -NotePropertyValue 0
  $s | Add-Member -NotePropertyName "Naglowek"     -NotePropertyValue $null
  if ($zmierzony) {
    $s.Procent = [int][math]::Round(100.0 * [double]$s.Teraz / [double]$s.Limit)
    $s.Zapas   = 100 - $s.Procent
    if ($s.Zapas -lt 0) { $s.Zapas = 0 }
    if ([long]$s.Teraz -gt [long]$s.Limit) {
      $s.Przekroczony = $true
      $s.Strata       = [long]$s.Teraz - [long]$s.Limit
      $s.Naglowek     = Pierwszy-Utracony-Naglowek $s.Tresc $s.Limit $s.Jednostka
    }
  }
  return $s
}

function Powod-Braku($teraz, $limit, $coMierzone, $skadLimitu) {
  $b = @()
  if ($teraz -eq $null) { $b += $coMierzone }
  if ($limit -eq $null) { $b += "nie umiem odczytac sufitu z $skadLimitu" }
  if ($b.Count -eq 0) { return $null }
  return ($b -join "; ")
}

function Sortuj-Sufity($lista) {
  # przekroczone i ciasne na GORZE - dolna czesc listy to ta, ktorej nikt nie czyta
  $klucze = @(
    @{ Expression = { if ($_.Informacyjny -or (-not $_.Zmierzony)) { 1 } else { 0 } } },
    @{ Expression = { if ($_.Zmierzony) { 0 - $_.Procent } else { 0 } } }
  )
  return @($lista | Sort-Object -Property $klucze)
}

# --- poprzedni pomiar --------------------------------------------------------

function Poprzedni-Pomiar($plik) {
  # dzienny raport zapisany przez zadanie z harmonogramu; najpierw szukamy linii
  # maszynowej, a dopiero potem - dla starszych plikow - linii RAZEM
  $tekst = Czytaj-Cicho $plik
  if (-not $tekst) { return $null }
  $m = [regex]::Match($tekst, '(?m)^\s*POMIAR\s+tokenow=(\d+)')
  if (-not $m.Success) {
    $m = [regex]::Match($tekst, '(?m)^\s*RAZEM.*?~\s*([\d ]+)\s*tokenow')
  }
  if (-not $m.Success) { return $null }
  $cyfry = ($m.Groups[1].Value -replace '[^\d]', '')
  if (-not $cyfry) { return $null }
  $data = $null
  try { $data = (Get-Item -LiteralPath $plik).LastWriteTime } catch { $data = $null }
  return [pscustomobject]@{ Tokeny = [int]$cyfry; Data = $data }
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

function Pytanie-Do-Lore($baza, $sql) {
  if (-not (Test-Path -LiteralPath $baza)) {
    return [pscustomobject]@{ Ok = $false; Ile = 0; Powod = "nie ma bazy Lore: $baza" }
  }
  try {
    if (-not ("MalySqlite" -as [type])) { Add-Type -TypeDefinition $KodSqlite -ErrorAction Stop }
    $ile = [MalySqlite]::Licz($baza, $sql)
    return [pscustomobject]@{ Ok = $true; Ile = [long]$ile; Powod = $null }
  } catch {
    return [pscustomobject]@{ Ok = $false; Ile = 0; Powod = "nie umiem odczytac $baza ($($_.Exception.Message))" }
  }
}

function Policz-Sesje($baza) {
  # ile roznych sesji zostawilo slad w ostatniej dobie
  # ts w tabeli chunks to ISO UTC ("2026-09-11T06:27:15.470Z"), wiec zwykle
  # porownanie tekstowe z obcieta granica daje poprawny wynik
  $granica = ([datetime]::UtcNow.AddDays(-1)).ToString("yyyy-MM-ddTHH:mm:ss")
  return Pytanie-Do-Lore $baza "SELECT count(DISTINCT session) FROM chunks WHERE ts >= '$granica'"
}

function Kolejka-Lore($baza, $znacznik) {
  # ile znakow wypowiedzi uzytkownika czeka na wyciagniecie faktow - to jest
  # wartosc mierzona przeciw MAX_INPUT_CHARS
  $od = ""
  $t = Czytaj-Cicho $znacznik
  if ($t) { $od = $t.Trim() }
  if (-not $od) { $od = ([datetime]::UtcNow.AddHours(-24)).ToString("yyyy-MM-ddTHH:mm:ss") }
  $od = $od -replace "'", ""
  $sql = "SELECT coalesce(sum(length(text)), 0) FROM chunks WHERE ts > '$od'" +
         " AND (role = 'user' OR role LIKE '%:user')"
  return Pytanie-Do-Lore $baza $sql
}

function Najdluzszy-Kawalek($baza) {
  return Pytanie-Do-Lore $baza "SELECT coalesce(max(length(text)), 0) FROM chunks"
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
  # -Zwykly obowiazkowo: kolorowe linie ida przez Write-Host, a tego Set-Content
  # nie lapie - raport w pliku byloby wtedy bez ostrzezen, czyli klamalby
  $polecenie = "& '$s' -KatalogDomowy '$d' -Zwykly | Set-Content -LiteralPath '$r' -Encoding UTF8"
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

if (-not $Zrodlo) {
  $katSkryptu = $PSScriptRoot
  if ((-not $katSkryptu) -and $PSCommandPath) { $katSkryptu = Split-Path -Parent $PSCommandPath }
  if ($katSkryptu) { $Zrodlo = Split-Path -Parent $katSkryptu }
}

$katKlaudii   = Join-Path $KatalogDomowy ".claude"
$plikClaude   = Join-Path $katKlaudii "CLAUDE.md"
$katWiedzy    = Join-Path $katKlaudii "wiedza"
$plikKandydat = Join-Path $katWiedzy "kandydaci.md"
$plikOstatni  = Join-Path $katWiedzy "koszt-ostatni.txt"
$plikZnacznik = Join-Path $katWiedzy ".ostatnie-wyciaganie"
$bazaLore     = Join-Path $katKlaudii "lore.db"
$plikAgents   = Join-Path $KatalogDomowy ".codex\AGENTS.md"

if ($UsunZadanie)  { Usun-Zadanie }
if ($ZalozZadanie) { Zaloz-Zadanie $PSCommandPath $KatalogDomowy $plikOstatni }

# zrodla sufitow - kazdy limit czytamy z pliku, ktory go naprawde ustala
$plikStraznika = Join-Path $Zrodlo "narzedzia\straznik-zasad.ps1"
# Sufit rzadzi ten, ktory NAPRAWDE lezy w projekcie - szablon w repo mowi tylko,
# co instalator by tam wpisal. Gdy projekt jest podany i ma wlasny .codex\hooks.json,
# limity czytamy stamtad; inaczej zostaje szablon.
$plikHookow    = Join-Path $Zrodlo "szablony-codex\hooks.json"
$skadHookow    = "szablony-codex\hooks.json"
if ($Projekt) {
  $hookiProjektu = Join-Path $Projekt ".codex\hooks.json"
  if (Test-Path -LiteralPath $hookiProjektu) {
    $plikHookow = $hookiProjektu
    $skadHookow = $hookiProjektu
  }
}
$plikZasadWzor = Join-Path $Zrodlo "szablony-codex\zasady-kierownika.md"
$plikPrzypWzor = Join-Path $Zrodlo "szablony-codex\przypomnienie.json"
$plikFaktow    = Join-Path $Zrodlo "lore\lore\facts.py"
$plikIndeksu   = Join-Path $Zrodlo "lore\lore\index.py"
$plikSzukania  = Join-Path $Zrodlo "lore\lore\search.py"
$plikKopania   = Join-Path $Zrodlo "lore\lore\mining.py"

$w = Zmierz-Warstwy $plikClaude

$razemZnakow  = $w.Blok.Znaki + $w.Stala.Znaki + $w.Biezaca.Znaki
$razemLinii   = $w.Blok.Linie + $w.Stala.Linie + $w.Biezaca.Linie
$razemTokenow = [int][math]::Ceiling($razemZnakow / $ZnakiNaToken)

# --- sufity: pomiary ---------------------------------------------------------

$limitAgents  = Limit-Z-Pliku $plikStraznika '(?m)^\s*\$LIMIT_AGENTS\s*=\s*(\d+)'
$limitZasad   = Limit-Hooka $plikHookow "zasady-sesja.json"
$limitPrzyp   = Limit-Hooka $plikHookow "przypomnienie.json"
$limitWejscia = Limit-Z-Pliku $plikFaktow  '(?m)^MAX_INPUT_CHARS\s*=\s*([\d_]+)'
$limitKawalka = Limit-Z-Pliku $plikIndeksu '(?m)^CHUNK_SIZE\s*=\s*([\d_]+)'

# AGENTS.md Codeksa - sufit jest w BAJTACH, bo tyle czyta Codex
$agentsTresc = Czytaj-Cicho $plikAgents
$agentsBajty = $null
if ($agentsTresc -ne $null) {
  try { $agentsBajty = [long](Get-Item -LiteralPath $plikAgents).Length } catch { $agentsBajty = $null }
}

# Zasady wysylane Codeksowi na starcie sesji. Gdy podano projekt i lezy w nim
# gotowy ladunek - mierzymy JEGO, bo to jest to, co naprawde leci. Bez projektu
# mierzymy szablon zlozony tak samo jak sklada go straznik: to wariant pelny,
# czyli ten, ktory dostaje projekt bez zasad w AGENTS.md.
$zasadyTresc = $null
$zasadySkad  = $null
if ($Projekt) {
  $p = Join-Path $Projekt ".megaruchacz\zasady-sesja.json"
  $t = Ladunek-Hooka $p
  if ($t) { $zasadyTresc = $t; $zasadySkad = $p }
}
if (-not $zasadyTresc) {
  $t = Czytaj-Cicho $plikZasadWzor
  if ($t) {
    $zasadyTresc = $PrzedrostekZasad + $t
    $zasadySkad  = "$plikZasadWzor (wariant pelny - tyle leci do projektu, ktory nie ma zasad w AGENTS.md)"
  }
}
$zasadyZnaki = $null
if ($zasadyTresc) { $zasadyZnaki = $zasadyTresc.Length }

# Przypomnienie doklejane w Codeksie do KAZDEJ wiadomosci uzytkownika
$przypTresc = $null
$przypSkad  = $null
if ($Projekt) {
  $p = Join-Path $Projekt ".megaruchacz\przypomnienie.json"
  $t = Ladunek-Hooka $p
  if ($t) { $przypTresc = $t; $przypSkad = $p }
}
if (-not $przypTresc) {
  $t = Ladunek-Hooka $plikPrzypWzor
  if ($t) { $przypTresc = $t; $przypSkad = $plikPrzypWzor }
}
$przypZnaki = $null
if ($przypTresc) { $przypZnaki = $przypTresc.Length }

$sufity = @()

$sufity += Sufit ([ordered]@{
  Nazwa      = "pamiec stala w CLAUDE.md (sekcja 'Co wiem')"
  Krotka     = "pamiec stala"
  Teraz      = $(if ($w.Jest) { $w.Stala.Znaki } else { $null })
  Limit      = $ProgStalej
  Jednostka  = "znakow"
  Czyj       = "NASZ - sami go sobie ustawilismy"
  SkadLimitu = "narzedzia\koszt-pamieci.ps1 (`$ProgStalej)"
  Plik       = $plikClaude
  Skutek     = "nic sie nie ucina: to prog ostrzegawczy, sygnal zeby przeniesc rzadziej potrzebna wiedze do plikow w wiedza\"
  Ucina      = $false
  Uwaga      = (Powod-Braku $(if ($w.Jest) { $w.Stala.Znaki } else { $null }) $ProgStalej "nie ma pliku $plikClaude" "tego skryptu")
})

$sufity += Sufit ([ordered]@{
  Nazwa      = "instrukcje dla Codeksa (~\.codex\AGENTS.md)"
  Krotka     = "instrukcje dla Codeksa"
  Teraz      = $agentsBajty
  Limit      = $limitAgents
  Jednostka  = "bajtow"
  Czyj       = "NARZUCONY przez Codeksa - tego nie podniesiemy, trzeba sie zmiescic"
  SkadLimitu = "narzedzia\straznik-zasad.ps1 (`$LIMIT_AGENTS)"
  Plik       = $plikAgents
  Skutek     = "UCINA PO CICHU: Codex czyta tylko poczatek pliku, koniec zasad nie dociera do niego wcale"
  Ucina      = $true
  Tresc      = $agentsTresc
  Uwaga      = (Powod-Braku $agentsBajty $limitAgents "nie ma pliku $plikAgents - Codeksa nie ma na tej maszynie, wiec ten sufit dzis nikogo nie dotyczy" "narzedzia\straznik-zasad.ps1")
})

$sufity += Sufit ([ordered]@{
  Nazwa      = "zasady kierownika wstrzykiwane Codeksowi przy starcie sesji"
  Krotka     = "zasady dla Codeksa"
  Teraz      = $zasadyZnaki
  Limit      = $limitZasad
  Jednostka  = "znakow"
  Czyj       = "NASZ - liczba wpisana w $skadHookow, do podniesienia jedna linijka"
  SkadLimitu = "$skadHookow (additionalContextLimit hooka SessionStart)"
  Plik       = $zasadySkad
  Skutek     = "UCINA PO CICHU: Codex dostaje tylko poczatek zasad, konca nikt mu nie pokaze i nikt go nie ostrzeze"
  Ucina      = $true
  Tresc      = $zasadyTresc
  Uwaga      = (Powod-Braku $zasadyZnaki $limitZasad "nie ma czego mierzyc: brak $plikZasadWzor" $skadHookow)
})

$sufity += Sufit ([ordered]@{
  Nazwa      = "przypomnienie doklejane w Codeksie do kazdej wiadomosci"
  Krotka     = "przypomnienie dla Codeksa"
  Teraz      = $przypZnaki
  Limit      = $limitPrzyp
  Jednostka  = "znakow"
  Czyj       = "NASZ - liczba wpisana w $skadHookow, do podniesienia jedna linijka"
  SkadLimitu = "$skadHookow (additionalContextLimit hooka UserPromptSubmit)"
  Plik       = $przypSkad
  Skutek     = "UCINA PO CICHU: koniec przypomnienia przepada przy kazdej wiadomosci"
  Ucina      = $true
  Tresc      = $przypTresc
  Uwaga      = (Powod-Braku $przypZnaki $limitPrzyp "nie ma czego mierzyc: brak $plikPrzypWzor" $skadHookow)
})

# Ladunki hookow Claude Code - mierzymy je tylko wtedy, gdy podano projekt, bo
# poza nim nie ma czego mierzyc. Sufitu dla nich w settings.json DZIS NIE MA:
# obowiazuje wtedy wartosc domyslna Claude Code, ktorej nie znamy - i raport ma
# to powiedziec wprost, a nie przemilczec.
if ($Projekt) {
  $plikUstawien = Join-Path $Projekt ".claude\settings.json"
  foreach ($paraCC in @(
      @{ nazwa = "zasady kierownika wstrzykiwane na starcie sesji Claude Code"
         krotka = "zasady dla Claude Code"; plik = ".claude\megaruchacz-sesja.json"
         zdarzenie = "SessionStart" },
      @{ nazwa = "przypomnienie doklejane w Claude Code do kazdej wiadomosci"
         krotka = "przypomnienie dla Claude Code"; plik = ".claude\orchestrator-reminder.json"
         zdarzenie = "UserPromptSubmit" })) {
    $plikCC = Join-Path $Projekt $paraCC.plik
    if (-not (Test-Path -LiteralPath $plikCC)) { continue }
    $trescCC = Ladunek-Hooka $plikCC
    $znakiCC = $null
    if ($trescCC) { $znakiCC = $trescCC.Length }
    $limitCC = Limit-Hooka $plikUstawien (Split-Path $paraCC.plik -Leaf)
    $sufity += Sufit ([ordered]@{
      Nazwa      = $paraCC.nazwa
      Krotka     = $paraCC.krotka
      Teraz      = $znakiCC
      Limit      = $limitCC
      Jednostka  = "znakow"
      Czyj       = "NARZUCONY przez Claude Code, dopoki nie wpiszemy wlasnego additionalContextLimit do settings.json"
      SkadLimitu = "$plikUstawien (additionalContextLimit hooka $($paraCC.zdarzenie))"
      Plik       = $plikCC
      Skutek     = "UCINA PO CICHU: koniec ladunku przepada, gdy przekroczy sufit narzedzia"
      Ucina      = $true
      Tresc      = $trescCC
      Uwaga      = (Powod-Braku $znakiCC $limitCC "nie da sie odczytac ladunku z $plikCC" `
                    "$plikUstawien - nie ma tam additionalContextLimit, wiec sufitem jest wartosc domyslna Claude Code")
    })
  }
}

# --- wypisanie: tryb zwiezly (DOKLADNIE JEDNA LINIA) -------------------------

$ucinane = @(Sortuj-Sufity @($sufity | Where-Object { $_.Ucina -and $_.Przekroczony }))
$cosUcinane = ($ucinane.Count -gt 0)

$poprz      = Poprzedni-Pomiar $plikOstatni
$zmiana     = 0
$zmianaProc = 0
$skokKosztu = $false
if ($poprz -and $poprz.Tokeny -gt 0) {
  $zmiana     = $razemTokenow - $poprz.Tokeny
  $zmianaProc = [int][math]::Round(100.0 * $zmiana / $poprz.Tokeny)
  if ($zmianaProc -gt $ProgWzrostu) { $skokKosztu = $true }
}

if ($Zwiezle) {
  # Liczby bez separatora tysiecy: ta linia ma sie zmiescic w jednym wierszu
  # terminala i jest pokazywana przez straznika przy kazdym otwarciu sesji.
  if ($cosUcinane) {
    $g = $ucinane[0]
    $opis = "UCINANE: $($g.Krotka) -$($g.Strata) $($g.Jednostka)"
    if ($g.Naglowek) { $opis = $opis + " (od ""$(Skroc $g.Naglowek 34)"")" }
    if ($ucinane.Count -gt 1) { $opis = $opis + " i jeszcze $($ucinane.Count - 1)" }
    $linia = "UWAGA pamiec: ~$razemTokenow tokenow na wiadomosc, $opis"
  } else {
    $linia = "pamiec: ~$razemTokenow tokenow na wiadomosc, nic nie jest ucinane"
  }
  if ($skokKosztu) { $linia = $linia + " (+$zmianaProc% od wczoraj)" }
  Write-Output $linia
  if ($cosUcinane) { exit 1 }
  exit 0
}

# --- wypisanie: same sufity (jedno polecenie do odpalenia po zmianie zasad) ---
# Przechodzi po WSZYSTKICH parach (ladunek, sufit), ktore juz sa policzone wyzej -
# drugi raz tego nie liczymy. Kod wyjscia 1 przy jakimkolwiek przekroczeniu, zeby
# dalo sie to wpiac jako bramke. Sufitow z Lore tu nie ma: niczego nie ucinaja
# przed modelem, a zapytania do bazy trwaja.
if ($TylkoSufity) {
  Write-Output "Sufity ladunkow - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
  foreach ($s in (Sortuj-Sufity $sufity)) {
    if (-not $s.Zmierzony) {
      Write-Output ("  ?     {0} - nie zmierzone: {1}" -f $s.Krotka, $s.Uwaga)
      continue
    }
    if ($s.Przekroczony -and $s.Ucina) {
      $opisU = "  UCINA {0} - {1} z {2} {3}, przepada {4}; sufit: {5}" -f `
               $s.Krotka, (Liczba $s.Teraz), (Liczba $s.Limit), $s.Jednostka, (Liczba $s.Strata), $s.SkadLimitu
      if ($s.Naglowek) { $opisU = $opisU + " (ginie od ""$(Skroc $s.Naglowek 40)"")" }
      Write-Output $opisU
    } elseif ($s.Przekroczony) {
      Write-Output ("  PROG  {0} - {1} z {2} {3}, ale ten sufit niczego nie ucina" -f `
                    $s.Krotka, (Liczba $s.Teraz), (Liczba $s.Limit), $s.Jednostka)
    } else {
      Write-Output ("  ok    {0} - {1} z {2} {3} ({4}% sufitu)" -f `
                    $s.Krotka, (Liczba $s.Teraz), (Liczba $s.Limit), $s.Jednostka, $s.Procent)
    }
  }
  if ($cosUcinane) {
    Write-Output "BLAD  cos jest ucinane po cichu - podnies limit we wskazanym pliku albo skroc tresc."
    exit 1
  }
  Write-Output "Nic nie jest ucinane."
  exit 0
}

# --- pomiary tylko do pelnego raportu ----------------------------------------
# (zapytania do bazy Lore potrafia chwile trwac, wiec w trybie zwiezlym ich nie ma)

$sesje   = Policz-Sesje $bazaLore
$kolejka = Kolejka-Lore $bazaLore $plikZnacznik
$kawalek = Najdluzszy-Kawalek $bazaLore

$przebiegi = 0
if ($kolejka.Ok -and $limitWejscia -and $limitWejscia -gt 0) {
  $przebiegi = [int][math]::Ceiling([double]$kolejka.Ile / [double]$limitWejscia)
}

$sufity += Sufit ([ordered]@{
  Nazwa      = "jedna porcja rozmow wysylana do wyciagania faktow"
  Krotka     = "porcja dla Lore"
  Teraz      = $(if ($kolejka.Ok) { $kolejka.Ile } else { $null })
  Limit      = $limitWejscia
  Jednostka  = "znakow"
  Czyj       = "NASZ - stala w lore\lore\facts.py"
  SkadLimitu = "lore\lore\facts.py (MAX_INPUT_CHARS)"
  Plik       = $bazaLore
  Skutek     = "nic nie ginie: co sie nie zmiesci, czeka w kolejce na kolejny przebieg (teraz do nadrobienia przebiegow: $przebiegi)"
  Ucina      = $false
  Informacyjny = $true
  Uwaga      = (Powod-Braku $(if ($kolejka.Ok) { $kolejka.Ile } else { $null }) $limitWejscia "nie da sie policzyc kolejki: $($kolejka.Powod)" "lore\lore\facts.py")
})

$sufity += Sufit ([ordered]@{
  Nazwa      = "krojenie rozmowy na kawalki do wyszukiwania"
  Krotka     = "kawalek rozmowy"
  Teraz      = $(if ($kawalek.Ok) { $kawalek.Ile } else { $null })
  Limit      = $limitKawalka
  Jednostka  = "znakow"
  Czyj       = "NASZ - stala w lore\lore\index.py"
  SkadLimitu = "lore\lore\index.py (CHUNK_SIZE)"
  Plik       = $bazaLore
  Skutek     = "nic nie ginie, ale dluzsza wypowiedz jest krojona na kawalki - czasem w pol slowa; tak ma byc, to nie jest przekroczenie"
  Ucina      = $false
  Informacyjny = $true
  Uwaga      = (Powod-Braku $(if ($kawalek.Ok) { $kawalek.Ile } else { $null }) $limitKawalka "nie da sie zmierzyc kawalkow: $($kawalek.Powod)" "lore\lore\index.py")
})

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
foreach ($s in $ucinane) {
  $ostrzezenia += "UCINANE PO CICHU: $($s.Nazwa) - ginie $(Liczba $s.Strata) $($s.Jednostka) z $(Liczba $s.Teraz). Sufit $($s.SkadLimitu)."
}
if ($skokKosztu) {
  $ostrzezenia += "Koszt jednej wiadomosci urosl o $zmianaProc% od poprzedniego pomiaru ($(Liczba $poprz.Tokeny) -> $(Liczba $razemTokenow) tokenow) - sprawdz, co doszlo do CLAUDE.md."
}
foreach ($s in $sufity) {
  if ($s.Zmierzony -and (-not $s.Informacyjny) -and (-not $s.Przekroczony) -and ($s.Procent -ge $ProgCiasno)) {
    $ostrzezenia += "Blisko sufitu: $($s.Nazwa) - zajete $($s.Procent)% ($(Liczba $s.Teraz) z $(Liczba $s.Limit) $($s.Jednostka))."
  }
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

# --- wypisanie: pelny raport -------------------------------------------------

function Wiersz($nazwa, $m) {
  Linia ("  {0,-26} {1,5} linii, {2,9} znakow, ~{3,7} tokenow" -f $nazwa, (Liczba $m.Linie), (Liczba $m.Znaki), (Liczba $m.Tokeny))
}

function Wiersz-Sufitu($s) {
  $znak  = "  "
  $kolor = $null
  if ($s.Zmierzony -and (-not $s.Informacyjny)) {
    if ($s.Przekroczony) { $znak = "!!"; $kolor = "Red" }
    elseif ($s.Procent -ge $ProgCiasno) { $znak = "! "; $kolor = "Yellow" }
  }
  Linia ("  {0} {1}" -f $znak, $s.Nazwa) $kolor
  if (-not $s.Zmierzony) {
    Linia ("       bez pomiaru: {0}" -f $s.Uwaga)
  } elseif ($s.Przekroczony) {
    Linia ("       {0} z {1} {2} - PRZEKROCZONE o {3} ({4}% sufitu)" -f `
           (Liczba $s.Teraz), (Liczba $s.Limit), $s.Jednostka, (Liczba $s.Strata), $s.Procent) $kolor
  } else {
    Linia ("       {0} z {1} {2} - zapasu {3}%" -f `
           (Liczba $s.Teraz), (Liczba $s.Limit), $s.Jednostka, $s.Zapas)
  }
  Linia ("       po przekroczeniu: {0}" -f $s.Skutek)
  Linia ("       sufit {0}; czytamy go z: {1}" -f $s.Czyj, $s.SkadLimitu)
  if ($s.Zmierzony -and $s.Plik) { Linia ("       mierzymy: {0}" -f $s.Plik) }
}

Linia ""
Linia "Audyt pamieci i sufitow - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Linia "Katalog: $katKlaudii"

Linia ""
Linia "0. CO JEST UCINANE W TEJ CHWILI"
if (-not $cosUcinane) {
  Linia "  Nic nie jest ucinane - kazdy tekst miesci sie w swoim suficie."
} else {
  foreach ($s in $ucinane) {
    $procUtraty = 0
    if ([long]$s.Teraz -gt 0) { $procUtraty = [int][math]::Round(100.0 * $s.Strata / [double]$s.Teraz) }
    Linia ("  UCINANE: {0}" -f $s.Nazwa) "Red"
    Linia ("    ginie {0} {1} z {2} - {3}% tekstu, i to jego KONIEC" -f `
           (Liczba $s.Strata), $s.Jednostka, (Liczba $s.Teraz), $procUtraty) "Red"
    if ($s.Naglowek) {
      Linia ("    ucieta czesc zaczyna sie od naglowka: {0}" -f $s.Naglowek) "Red"
    } else {
      Linia "    w urwanej czesci nie ma naglowka, wiec nie umiem nazwac, co przepada" "Red"
    }
    Linia ("    tekst: {0}" -f $s.Plik)
    Linia ("    sufit: {0} {1} z {2}" -f (Liczba $s.Limit), $s.Jednostka, $s.SkadLimitu)
  }
}

Linia ""
Linia "1. Sufity - gdzie stoi kazdy i ile zostalo zapasu"
Linia "   (!! = przekroczony, ! = zajete ponad $ProgCiasno%; na gorze te najciasniejsze)"
foreach ($s in (Sortuj-Sufity $sufity)) { Wiersz-Sufitu $s }

Linia ""
Linia "2. Doklejane do KAZDEJ wiadomosci"
if (-not $w.Jest) {
  Linia "  Nie ma pliku $plikClaude - czyli nic stad nie dokleja sie do rozmow."
} else {
  Wiersz "blok zasad instalatora" $w.Blok
  Wiersz "warstwa STALA (Co wiem)" $w.Stala
  Wiersz "warstwa BIEZACA" $w.Biezaca
  Linia ("  {0,-26} {1,5} linii, {2,9} znakow, ~{3,7} tokenow" -f "RAZEM na jedna wiadomosc", (Liczba $razemLinii), (Liczba $razemZnakow), (Liczba $razemTokenow))
  if ($w.Blok.Znaki -eq 0) { Linia "  (bloku zasad MegaRuchacza w tym pliku nie ma)" }
  if (-not $w.MaSekcje)    { Linia "  (sekcji '## Co wiem' w tym pliku nie ma - warstwa stala i biezaca sa puste)" }
  Linia "  Tokeny to SZACUNEK, nie pomiar: przyjete ~$ZnakiNaToken znaki na token dla polszczyzny."
}
# linia maszynowa - z niej czyta poprzedni pomiar nastepny przebieg
Linia ("  POMIAR tokenow={0} znakow={1}" -f $razemTokenow, $razemZnakow)
if (-not $poprz) {
  Linia "  Poprzedniego pomiaru nie ma ($plikOstatni) - nie ma z czym porownac. Powstanie przy najblizszym dziennym raporcie."
} else {
  $dataPoprz = "data nieznana"
  if ($poprz.Data) { $dataPoprz = $poprz.Data.ToString("yyyy-MM-dd HH:mm") }
  $opisZmiany = "bez zmian"
  if ($zmiana -gt 0) { $opisZmiany = "+$(Liczba $zmiana), +$zmianaProc%" }
  elseif ($zmiana -lt 0) { $opisZmiany = "$(Liczba $zmiana), $zmianaProc%" }
  $kolorZmiany = $null
  if ($skokKosztu) { $kolorZmiany = "Yellow" }
  Linia ("  Poprzedni pomiar ({0}): {1} -> {2} tokenow na wiadomosc ({3})" -f `
         $dataPoprz, (Liczba $poprz.Tokeny), (Liczba $razemTokenow), $opisZmiany) $kolorZmiany
  if ($skokKosztu) {
    Linia "  UWAGA  to wiecej niz $ProgWzrostu% wzrostu - pamiec puchnie i kazda wiadomosc placi za to osobno." "Yellow"
  }
}

Linia ""
Linia "3. Ile to daje przez dobe"
if (-not $w.Jest) {
  Linia "  Koszt jednostkowy jest zerowy, wiec nie ma czego mnozyc przez liczbe sesji."
} elseif (-not $sesje.Ok) {
  Linia "  Nie da sie policzyc: $($sesje.Powod)."
  Linia "  Zostaje sam koszt jednostkowy: ~$(Liczba $razemTokenow) tokenow za kazda wiadomosc."
} elseif ($sesje.Ile -eq 0) {
  Linia "  W ostatniej dobie nie bylo ani jednej sesji - dzis ta pamiec nic nie kosztowala."
  Linia "  Koszt jednostkowy: ~$(Liczba $razemTokenow) tokenow za kazda wiadomosc."
} else {
  Linia "  Sesji w ostatniej dobie: $($sesje.Ile)"
  Linia "  $(Liczba $razemTokenow) tokenow x $($sesje.Ile) sesji = ~$(Liczba ($razemTokenow * $sesje.Ile)) tokenow doklejonych przez dobe."
}

Linia ""
Linia "4. Warstwa referencyjna ($katWiedzy)"
if (-not (Test-Path -LiteralPath $katWiedzy)) {
  Linia "  Nie ma tego katalogu - warstwy referencyjnej jeszcze nie ma."
} else {
  Linia "  Plikow: $($pliki.Count), lacznie $(Rozmiar $bajtyWiedzy)"
  Linia "  To NIE jest doklejane do rozmow. Nie kosztuje nic, dopoki agent po to nie siegnie -"
  Linia "  wiec ta warstwa moze byc duza, nie bedac droga. Tu przenosi sie to, co puchnie wyzej."
}

Linia ""
Linia "5. Poczekalnia ($plikKandydat)"
if ($kandydaci -eq $null) {
  Linia "  Nie ma pliku kandydatow - nic nie czeka na decyzje. To normalne."
} else {
  Linia "  Faktow czeka na zatwierdzenie: $kandydaci"
}

Linia ""
Linia "6. Higiena warstwy biezacej (wpis wazny przez $DniWaznosci dni)"
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
Linia "7. Inne sufity znalezione w kodzie (stale, wiec nie ma tu czego mierzyc)"
$inne = @(
  @{ Plik = $plikIndeksu;  Wzor = '(?m)^MAX_TOOL_INPUT\s*=\s*([\d_]+)';     Opis = "opis wywolania narzedzia zapisywany w pamieci Lore jest przycinany do {0} znakow (lore\lore\index.py)" },
  @{ Plik = $plikIndeksu;  Wzor = '(?m)^MAX_TOOL_RESULT\s*=\s*([\d_]+)';    Opis = "wynik narzedzia zapisywany w pamieci Lore jest przycinany do {0} znakow (lore\lore\index.py)" },
  @{ Plik = $plikSzukania; Wzor = '(?m)^MAX_SNIPPET\s*=\s*([\d_]+)';        Opis = "fragment pokazywany w wynikach szukania jest przycinany do {0} znakow (lore\lore\search.py)" },
  @{ Plik = $plikKopania;  Wzor = '(?m)^MAX_SNIPPET\s*=\s*([\d_]+)';        Opis = "fragment podawany modelowi przy kopaniu w pamieci przycinany do {0} znakow (lore\lore\mining.py)" },
  @{ Plik = $plikKopania;  Wzor = '(?m)^MAX_PREVIEW_SNIPPET\s*=\s*([\d_]+)'; Opis = "zajawka w podgladzie znalezisk przycinana do {0} znakow (lore\lore\mining.py)" }
)
$bylo = $false
foreach ($i in $inne) {
  $v = Limit-Z-Pliku $i.Plik $i.Wzor
  if ($v -eq $null) { continue }
  $bylo = $true
  Linia ("  - " + ($i.Opis -f (Liczba $v)))
}
if (-not $bylo) {
  Linia "  Nie znalazlem zadnego - albo nie ma tu katalogu lore\."
} else {
  Linia "  Te sufity tna tresc, zanim trafi do pamieci albo do wyniku szukania. Nie dotycza"
  Linia "  tego, co dokleja sie do rozmowy, wiec nie licza sie do kosztu wyzej."
}

Linia ""
Linia "8. Ostrzezenia"
if ($ostrzezenia.Count -eq 0) {
  Linia "  Nic nie wymaga uwagi - nic nie jest ucinane, a pamiec trzyma sie w rozsadnych rozmiarach."
} else {
  foreach ($o in $ostrzezenia) { Linia "  UWAGA  $o" "Yellow" }
}
Linia ""

# Kolory ida przez Write-Host, a tego nie lapie ani przekierowanie, ani potok -
# wiec przy zapisie do pliku (-Zwykly albo wykryte przekierowanie) wypisujemy
# wszystko zwyklym wyjsciem, zeby zaden wiersz nie zginal po drodze.
$kolorowac = (-not $Zwykly)
if ($kolorowac) {
  try { if ([Console]::IsOutputRedirected) { $kolorowac = $false } } catch { $kolorowac = $false }
}
foreach ($l in $script:Raport) {
  if ($kolorowac -and $l.Kolor) { Write-Host $l.Tekst -ForegroundColor $l.Kolor }
  else { Write-Output $l.Tekst }
}

if ($cosUcinane) { exit 1 }
exit 0
