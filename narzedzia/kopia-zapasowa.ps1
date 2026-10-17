# narzedzia\kopia-zapasowa.ps1 - dzienna kopia zapasowa wybranych folderow i plikow
# Claude'a (na komputerze biurowym: C:\dev i pliki Claude'a na Dysk Google).
#
# CO I DOKAD (P59d) - nic z tego nie jest zaszyte w kodzie:
#   - z rejestru instalacji ~\.claude\mr\instalacja.json, pole "kopia"
#     {zrodla:[...], cel:"...", wykluczenia:[{sciezka, powod, katalog}]} - wybor
#     uzytkownika z instalatora (umowa: narzedzia\instalacja\stan.ps1);
#   - BEZ rejestru (instalacja sprzed instalatora) - z pola "kopia" ustawien tego
#     komputera ~\.claude\mr\lokalne.json (P67: zrodla, cel i wykluczenia projektow
#     leza poza publicznym repo; umowa: narzedzia\instalacja\stan.ps1), a bez niego
#     z szablonu obok, kopia-zapasowa-domyslne.json - bez celu, wiec BLAD z powodem;
#   - -Zrodla i -Cel podane wprost wygrywaja z jednym i drugim.
# Rejestr jest, ale bez celu kopii = BLAD z powodem (nie zgadujemy celu cudzego
# komputera z ustawien domyslnych); z celem, ale bez listy zrodel = pliki Claude'a
# i Codeksa i UWAGA w dzienniku; rejestr nieczytelny = ustawienia jak bez rejestru i ALARM
# w dzienniku i pliku stanu (kopia ma isc, a ktos ma sie dowiedziec).
#
# UKLAD KOPII:
#   Backup\pelna-RRRR-MM-DD\C\dev\...       pelna kopia (sciezki jak na dysku C:) = stan sprzed
#                                           -Trzymaj dni kopii (data w nazwie = dzien jej zalozenia)
#   Backup\zmiany\RRRR-MM-DD\C\...          kazdego dnia tylko pliki nowe i zmienione
#   Backup\dziennik.txt                     data, ile plikow, ile MB, alarmy, bledy, pominiete
#   ~\.claude\mr\kopia-stan.txt             znacznik "bylem tu" (stan=OK/ALARM/BLAD/TRWA, przyczyna=)
#   ~\.claude\mr\kopia-indeks.tsv           co juz jest w kopii (sciezka, rozmiar, czas)
#   ~\.claude\mr\kopia-w-uzyciu.tsv         od kiedy ktory plik jest zablokowany (W UZYCIU)
# W dniu kopii istniejacego pliku w kopii nie ruszamy: drugi przebieg tego samego dnia
# idzie do zmiany\RRRR-MM-DD_GGMMSS. Usuniecie pliku u zrodla NIE usuwa go z kopii.
# Odtwarzanie: najnowsza wersja pliku = jego kopia w najmlodszym katalogu zmiany\
# (albo w pelna-*, jesli od tamtej pory sie nie zmienial).
#
# ROTACJA (od 17.10.2026; do tego dnia nic nie bylo kasowane i kopia urosla do ~36 GB
# w 16 dni): po udanym przebiegu zostaja katalogi zmiany\ z -Trzymaj ostatnich DNI, w ktorych
# byla kopia (domyslnie 7). Starszy dzien jest WLEWANY do najnowszej pelna-* (jego pliki
# zastepuja tam starsze wersje - kazdy byl sprawdzony na zera, zanim trafil do kopii) i znika.
# Dzien sprzed najnowszej pelna-* (np. po -Pierwsza) jest kasowany bez wlewania, a starsza
# pelna-* - gdy najnowsza wypadnie z okna -Trzymaj dni. Rotacja dotyka WYLACZNIE katalogow
# pelna-RRRR-MM-DD* i zmiany\RRRR-MM-DD* w celu - nic innego w folderze kopii.
# Uwaga: Dysk Google przenosi usuniete i zastapione pliki do kosza, ktory liczy sie do
# limitu konta jeszcze 30 dni - miejsce wraca po oproznieniu kosza albo po 30 dniach.
#
# BLEDY - trzy rodzaje, zeby jeden zablokowany plik nie zaslanial co dzien prawdziwej awarii:
#   - kopia nie poszla (brak celu / dysku, brak miejsca, ustawienia): stan=BLAD, blad=<powod>,
#     przyczyna=BRAK_CELU|BRAK_MIEJSCA|USTAWIENIA|PRZERWANA; brak miejsca dodatkowo linia ALARM;
#   - kopia poszla, ale czesci plikow nie dalo sie skopiowac: stan=BLAD bez blad=, przyczyna=PLIKI,
#     linie BLAD z nazwami;
#   - plik zablokowany przez inny program (W UZYCIU): ostrzezenie z nazwa w dzienniku i stanie,
#     stan zostaje OK - plik pojdzie w nastepnym przebiegu. Dopiero zablokowany od -Trzymaj dni
#     (zadnej swiezej kopii w calym oknie rotacji) staje sie linia BLAD.
# Katalogi danych baz (Postgres, MySQL, MongoDB) sa ZAWSZE pomijane, z wpisem BAZA w dzienniku
# i stanie (informacja, nie blad) - patrz KopiaIO.Przejdz.
#
# Dlaczego tak: 2026-10-02 rano pliki pamieci (~\.claude\CLAUDE.md, wiedza\) zostaly
# wyzerowane. Kopia nadpisujaca skasowalaby zdrowa wersje. Dlatego (1) kazdy dzien
# trafia do osobnego katalogu, (2) przed skopiowaniem plik tekstowy jest sprawdzany
# na zera - wyzerowany NIE trafia do kopii, a w dzienniku i pliku stanu staje ALARM
# z miejscem ostatniej wersji w kopii (albo zdaniem, ze jej nie ma). Wyjatek od 08.10:
# plik z mala dziura (bloki zer <= 10%, zdrowy koniec - $ProgDziur) idzie do kopii
# z wpisem DZIURA zamiast alarmu.
#
# Uzycie:
#   kopia-zapasowa.ps1                 przyrostowa (zadanie Harmonogramu; bez indeksu = pelna)
#   kopia-zapasowa.ps1 -Pierwsza       pelna kopia do pelna-RRRR-MM-DD
#   kopia-zapasowa.ps1 -Proba          tylko pokazuje, co by skopiowal (i ile MB) - nic nie pisze
#   kopia-zapasowa.ps1 -ZSekretami     dolacza .env, klucze SSH, ~\.claude\sekrety (domyslnie NIE)
#   kopia-zapasowa.ps1 -ZalozZadanie   zadanie MegaRuchaczKopia, codziennie o -Godzina (12:30)
#   kopia-zapasowa.ps1 -UsunZadanie
#   -Trzymaj <N>                       ile ostatnich dni kopii trzymac osobno (domyslnie 7)
#   -WolneBajty <B>                    tylko testy: udaje wolne miejsce na dysku celu
#   -KatalogDomowy <kat>               podmiana katalogu domowego (testy): rejestr, lokalne.json,
#                                      "~" w ustawieniach, plik stanu i indeks liczone od niego
# Pliku logowania Claude'a (.credentials.json) i auth.json Codeksa NIE kopiujemy nigdy -
# do odtworzenia pracy nie sa potrzebne, a daja dostep do konta.
#
# Dlugie sciezki: PowerShell 5.1 (.NET w trybie zgodnosci) nie przyjmuje sciezek
# \\?\..., a kopia na G:\ potrafi przekroczyc 260 znakow. Dlatego listowanie
# i kopiowanie idzie przez Win32 (FindFirstFileExW, CreateFileW) w klasie KopiaIO.
# Bazy SQLite (lore.db, bazy Codeksa) kopiujemy przez sqlite3.backup w Pythonie -
# zwykla kopia otwartej bazy w trybie WAL bywa niespojna.

param(
  [switch]$Pierwsza,
  [switch]$Proba,
  [switch]$ZSekretami,
  [switch]$Szczegoly,
  [switch]$ZalozZadanie,
  [switch]$UsunZadanie,
  [string]$Godzina = "12:30",
  [string]$Cel = "",
  [string[]]$Zrodla = @(),
  [string]$PlikStanu = "",
  [string]$PlikIndeksu = "",
  [string]$Data = "",
  # 7 dni: zerowanie plikow z 02.10.2026 wyszlo na jaw tego samego dnia, a alarm kopii widac
  # w oknie nadzorcy najpozniej po dwoch dobach (prog "kopia nie idzie") - tydzien daje
  # zapas na weekend i kilka dni nieobecnosci. Wersje starsze niz tydzien nie znikaja do zera:
  # zostaje stan sprzed 7 dni w pelna-* (a pamiec ma jeszcze kopie-dzienne.ps1 lokalnie).
  # Wiecej dni = wiecej miejsca: dzien to dzis 0,5-2 GB (glownie grafiki z C:\dev i lore.db).
  [int]$Trzymaj = 7,
  [long]$WolneBajty = -1,
  [string]$KatalogDomowy = $env:USERPROFILE
)

$ErrorActionPreference = "Stop"
$NazwaZadania = "MegaRuchaczKopia"
$H = $KatalogDomowy.TrimEnd('\')
if (-not $PlikStanu) { $PlikStanu = "$H\.claude\mr\kopia-stan.txt" }
if (-not $PlikIndeksu) { $PlikIndeksu = "$H\.claude\mr\kopia-indeks.tsv" }
$PlikWUzyciu = Join-Path (Split-Path -Parent $PlikStanu) "kopia-w-uzyciu.tsv"
if ($Trzymaj -lt 1) { Write-Host "BLAD  -Trzymaj musi byc co najmniej 1 (podano $Trzymaj)" -ForegroundColor Red; exit 1 }
# rodzaj bledu przerywajacego kopie (patrz naglowek, BLEDY) - ustawiany tuz przed throw
$script:Przyczyna = "PRZERWANA"
if (-not $Data) { $Data = Get-Date -Format "yyyy-MM-dd" }

# Zrodla, cel i wykluczenia projektow - z rejestru instalacji albo z pliku obok
# (Ustal-Ustawienia nizej, przed startem). Pliki Claude'a i Codeksa (to MegaRuchacz wie
# sam, gdzie leza) sa sprawdzane na zera inaczej niz reszta - patrz Do-Sprawdzenia.
$KorzenieClaude = @("$H\.claude", "$H\.claude.json", "$H\.codex", "$H\.config\opencode", "$H\.agents")

# Prog zer. Tekst w UTF-8/UTF-16/UTF-32 nigdy nie ma wiecej niz 3 bajty 0x00 pod
# rzad, a uszkodzenie z 2026-10-02 to bloki 3 332 - 31 986 bajtow zer albo caly plik
# z samych zer (najmniejszy mial 7 bajtow - dlatego osobno lapiemy "caly plik to zera").
# 64 daje duzy zapas w obie strony: zadnego falszywego alarmu na tekscie, a
# kazde widziane uszkodzenie jest 50x wieksze od progu.
$MinCiagZer = 64

# Prog dziury (od 2026-10-08). Plik, w ktorym bloki zer to RAZEM najwyzej 10% dlugosci,
# a koniec NIE jest blokiem zer, idzie do kopii mimo zer - z wpisem DZIURA w dzienniku
# i pliku stanu, bez ALARMU. To slad zaniku pradu w dzienniku dopisywanym: kawalek
# przepadl, a po nim program pisal dalej (zdrowy koniec dowodzi, ze plik zyje). Pominiecie
# takiego pliku w calosci gubilo wszystkie NOWSZE wpisy, a dziury i tak nie da sie
# zalatac. Liczby z 08.10.2026: ~\.claude\history.jsonl - 847 B zer na 582 066 B (0,15%),
# ~\.claude\mr\przypomnienia.log - 311 B na 5 411 B (5,75%); obydwa rosna, wiec udzial
# zer z czasem tylko spada. Plik z ponad 10% zer albo z zerami na koncu (swieze
# uszkodzenie, nic po nim nie dopisano) - jak dawniej: NIE do kopii, ALARM. Poprzednia
# wersja z kopii nie ginie: kazdy dzien to osobny katalog, nic nie jest nadpisywane, a wpis
# DZIURA podaje, gdzie lezy. Nasze pliki pamieci (CLAUDE.md, wiedza) ma dodatkowo
# straznik w zasobniku (jedno zero = alarm) - dziura w nich nie przejdzie po cichu.
$ProgDziur = 0.10

# --- zadanie w harmonogramie (wzor: narzedzia\koszt\pomiar-dzienny.ps1) -------

function Zaloz-Zadanie {
  $skrypt = $PSCommandPath
  # conhost --headless: kopia leci raz dziennie i nikt nie chce mrugniecia konsoli
  $argumenty = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$skrypt"""
  # UWAGA - jak w instaluj-lore.ps1: zadanie przez obiekty (New-ScheduledTaskPrincipal)
  # konczy sie "Odmowa dostepu" u zwyklego uzytkownika; ten sam zapis jako XML przechodzi.
  try {
    $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $start = (Get-Date -Format "yyyy-MM-dd") + "T" + $Godzina + ":00"
    $argXml = [System.Security.SecurityElement]::Escape($argumenty)
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>MegaRuchacz - dzienna kopia zapasowa C:\dev i plikow Claude'a na Dysk Google (narzedzia\kopia-zapasowa.ps1)</Description>
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
    <ExecutionTimeLimit>PT6H</ExecutionTimeLimit>
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
  # Register-ScheduledTask bez wyjatku niczego nie dowodzi - pytamy harmonogram
  $jest = Get-ScheduledTask -TaskName $NazwaZadania -ErrorAction SilentlyContinue
  if (-not $jest) { Write-Host "BLAD  harmonogram nie zna zadania $NazwaZadania po zalozeniu" -ForegroundColor Red; exit 1 }
  Write-Host "OK  zadanie $NazwaZadania - codziennie o $Godzina, niewidoczne (conhost --headless)"
  Write-Host "    po wylaczonym komputerze nadrobi przy najblizszym wlaczeniu"
  exit 0
}

function Usun-Zadanie {
  $jest = Get-ScheduledTask -TaskName $NazwaZadania -ErrorAction SilentlyContinue
  if (-not $jest) { Write-Host "--  nie ma zadania $NazwaZadania, nie ma czego usuwac"; exit 0 }
  try { Unregister-ScheduledTask -TaskName $NazwaZadania -Confirm:$false -ErrorAction Stop }
  catch { Write-Host "BLAD  nie udalo sie usunac zadania: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }
  Write-Host "OK  zadanie $NazwaZadania usuniete"
  exit 0
}

if ($ZalozZadanie) { Zaloz-Zadanie }
if ($UsunZadanie) { Usun-Zadanie }

# --- Win32: listowanie i kopiowanie z dlugimi sciezkami -----------------------

if (-not ("KopiaIO" -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public class KopiaWpis { public string Sciezka; public long Rozmiar; public long Czas; }
public class KopiaPominiety { public string Sciezka; public string Powod; public bool Katalog; public bool Sekret; }
public class KopiaRegula { public Regex Wzor; public string Powod; public bool Katalog; public bool Sekret; }

public static class KopiaIO {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  struct FIND {
    public uint Attr; public uint CLo, CHi, ALo, AHi, WLo, WHi; public uint SizeHi, SizeLo, R0, R1;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Name;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string Alt;
  }
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern IntPtr FindFirstFileExW(string n, int lvl, out FIND d, int op, IntPtr f, int fl);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern bool FindNextFileW(IntPtr h, out FIND d);
  [DllImport("kernel32.dll")]
  static extern bool FindClose(IntPtr h);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern SafeFileHandle CreateFileW(string n, uint acc, uint share, IntPtr sec, uint disp, uint fl, IntPtr t);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern bool CreateDirectoryW(string n, IntPtr sec);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern bool MoveFileExW(string a, string b, uint fl);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern bool DeleteFileW(string n);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern bool RemoveDirectoryW(string n);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern uint GetFileAttributesW(string n);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool SetFileTime(SafeFileHandle h, IntPtr c, IntPtr a, ref long w);

  static readonly IntPtr ZLY = new IntPtr(-1);
  static HashSet<string> zalozone = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

  public static string L(string p) {
    if (p.StartsWith(@"\\?\")) return p;
    if (p.StartsWith(@"\\")) return @"\\?\UNC\" + p.Substring(2);
    return @"\\?\" + p;
  }

  public static bool Istnieje(string p) { return GetFileAttributesW(L(p)) != 0xFFFFFFFF; }

  // pojedynczy plik (np. ~\.claude.json); null = nie ma albo to katalog
  public static KopiaWpis Stat(string p) {
    FIND d; IntPtr h = FindFirstFileExW(L(p), 1, out d, 0, IntPtr.Zero, 0);
    if (h == ZLY) return null;
    FindClose(h);
    if ((d.Attr & 0x10) != 0) return null;
    return new KopiaWpis { Sciezka = p, Rozmiar = ((long)d.SizeHi << 32) | d.SizeLo, Czas = ((long)d.WHi << 32) | d.WLo };
  }

  // Przechodzi drzewo bez schodzenia do wykluczonych katalogow (node_modules to
  // setki tysiecy plikow - filtrowanie po fakcie trwaloby minuty).
  public static void Przejdz(string korzen, List<KopiaRegula> reguly, List<KopiaWpis> pliki, List<KopiaPominiety> pominiete) {
    var stos = new Stack<string>();
    stos.Push(korzen.TrimEnd('\\'));
    while (stos.Count > 0) {
      string kat = stos.Pop();
      var dzieci = new List<FIND>();
      FIND d;
      IntPtr h = FindFirstFileExW(L(kat) + @"\*", 1, out d, 0, IntPtr.Zero, 2);
      if (h == ZLY) {
        int e = Marshal.GetLastWin32Error();
        if (e != 2 && e != 18)
          pominiete.Add(new KopiaPominiety { Sciezka = kat, Powod = "BLAD: nie da sie wylistowac katalogu (blad Win32 " + e + ")", Katalog = true });
        continue;
      }
      do { if (d.Name != "." && d.Name != "..") dzieci.Add(d); } while (FindNextFileW(h, out d));
      FindClose(h);

      bool projekt = false, profil = false, pgWer = false, pgKonf = false, mysql = false, mongo = false;
      foreach (var c in dzieci) {
        if ((c.Attr & 0x10) != 0) continue;
        string n = c.Name.ToLowerInvariant();
        if (n == "package.json" || n == "pyproject.toml" || n == "setup.py") projekt = true;
        else if (n == "local state") profil = true;
        else if (n == "pg_version") pgWer = true;
        else if (n == "postmaster.pid" || n == "postgresql.conf" || n == "pg_hba.conf") pgKonf = true;
        else if (n == "ibdata1" || n == "aria_log_control") mysql = true;
        else if (n == "wiredtiger" || n == "mongod.lock") mongo = true;
      }
      if (profil) {
        pominiete.Add(new KopiaPominiety { Sciezka = kat, Powod = "profil przegladarki (plik 'Local State') - odtwarzalny, trzyma ciasteczka sesji", Katalog = true });
        continue;
      }
      // Katalog danych bazy - ZAWSZE poza kopia (od 17.10.2026). Dzialajacy serwer trzyma pliki
      // otwarte i zmienia je w trakcie, wiec kopia plik po pliku jest niespojna; do 17.10 dzialajacy
      // Postgres (C:\dev\tools\pgdata) dawal BLAD w kazdym przebiegu od 05.10, ktory zaslanial
      // wszystko inne. Kopia bazy to jej zrzut (pg_dump, mysqldump, mongodump) - osobna sprawa.
      // Wpis "BAZA:" idzie do dziennika i stanu jako informacja, nie blad.
      string baza = (pgWer && pgKonf) ? "Postgres" : mysql ? "MySQL/MariaDB" : mongo ? "MongoDB" : null;
      if (baza != null) {
        pominiete.Add(new KopiaPominiety { Sciezka = kat, Powod = "BAZA: katalog danych bazy " + baza + " - pliki dzialajacej bazy sa niespojne, kopia bazy to jej zrzut (np. pg_dump)", Katalog = true });
        continue;
      }
      foreach (var c in dzieci) {
        string p = kat + "\\" + c.Name;
        bool jestKat = (c.Attr & 0x10) != 0;
        if ((c.Attr & 0x400) != 0) {
          pominiete.Add(new KopiaPominiety { Sciezka = p, Powod = "dowiazanie (junction/symlink) - nie idziemy za nim; cel kopiuj jako osobne zrodlo", Katalog = jestKat });
          continue;
        }
        KopiaRegula traf = null;
        foreach (var r in reguly) { if (r.Katalog == jestKat && r.Wzor.IsMatch(p)) { traf = r; break; } }
        if (traf != null) {
          pominiete.Add(new KopiaPominiety { Sciezka = p, Powod = traf.Powod, Katalog = jestKat, Sekret = traf.Sekret });
          continue;
        }
        if (jestKat) {
          string n = c.Name.ToLowerInvariant();
          if (projekt && (n == "dist" || n == "build" || n == "out")) {
            pominiete.Add(new KopiaPominiety { Sciezka = p, Powod = "wynik budowania (obok package.json/pyproject.toml)", Katalog = true });
            continue;
          }
          stos.Push(p);
        } else {
          pliki.Add(new KopiaWpis { Sciezka = p, Rozmiar = ((long)c.SizeHi << 32) | c.SizeLo, Czas = ((long)c.WHi << 32) | c.WLo });
        }
      }
    }
  }

  public static byte[] Naglowek(string p, int n) {
    var h = CreateFileW(L(p), 0x80000000, 7, IntPtr.Zero, 3, 0, IntPtr.Zero);
    if (h.IsInvalid) return null;
    using (var fs = new FileStream(h, FileAccess.Read)) {
      var b = new byte[n];
      int r = fs.Read(b, 0, n);
      return r < n ? null : b;
    }
  }

  public static void ZalozKatalog(string kat) {
    if (zalozone.Contains(kat)) return;
    var doZalozenia = new Stack<string>();
    string k = kat;
    while (!zalozone.Contains(k) && GetFileAttributesW(L(k)) == 0xFFFFFFFF) {
      doZalozenia.Push(k);
      int i = k.LastIndexOf('\\');
      if (i <= 2) break;
      k = k.Substring(0, i);
    }
    while (doZalozenia.Count > 0) {
      string z = doZalozenia.Pop();
      if (!CreateDirectoryW(L(z), IntPtr.Zero)) {
        int e = Marshal.GetLastWin32Error();
        if (e != 183) throw new IOException("nie da sie zalozyc katalogu " + z + " (blad Win32 " + e + ")");
      }
      zalozone.Add(z);
    }
    zalozone.Add(kat);
  }

  static string OtworzCel(string dst, out string tmp, out SafeFileHandle hd, out FileStream ws) {
    ws = null;
    ZalozKatalog(dst.Substring(0, dst.LastIndexOf('\\')));
    tmp = dst + ".kopia-tmp";
    DeleteFileW(L(tmp));
    hd = CreateFileW(L(tmp), 0x40000000, 0, IntPtr.Zero, 1, 0, IntPtr.Zero);
    if (hd.IsInvalid) {
      int e = Marshal.GetLastWin32Error(); tmp = null;
      if (e == 112 || e == 39) return "PELNY:zalozenie pliku w kopii (blad Win32 " + e + " - brak miejsca)";
      return "BLAD:zalozenie pliku w kopii (blad Win32 " + e + ")";
    }
    ws = new FileStream(hd, FileAccess.Write, 1 << 16);
    return null;
  }

  // Czyta zrodlo raz: sprawdza zera (jesli zera=true) i - gdy dst != null - pisze
  // do dst.kopia-tmp, a na koncu przemianowuje BEZ nadpisywania. dst == null:
  // samo sprawdzenie (tryb -Proba). Wynik: OK, ZERA:opis (NIE skopiowany),
  // DZIURY:opis (skopiowany mimo blokow zer - patrz $ProgDziur), W_UZYCIU, ISTNIEJE, BLAD:opis.
  // Blok = ciag co najmniej minCiag bajtow 0x00. Plik idzie do kopii z dziurami tylko,
  // gdy bloki razem to najwyzej progDziur jego dlugosci I plik nie konczy sie blokiem.
  public static string Kopiuj(string src, string dst, bool zera, int minCiag, double progDziur, long czas) {
    if (dst == "") dst = null;   // PowerShell podaje $null jako pusty napis
    SafeFileHandle hs = CreateFileW(L(src), 0x80000000, 7, IntPtr.Zero, 3, 0x08000000, IntPtr.Zero);
    if (hs.IsInvalid) {
      int e = Marshal.GetLastWin32Error();
      if (e == 32 || e == 33) return "W_UZYCIU";
      if (e == 2 || e == 3) return "ZNIKNAL";   // usuniety miedzy listowaniem a kopia
      return "BLAD:otwarcie zrodla (blad Win32 " + e + ")";
    }
    string tmp = null; SafeFileHandle hd = null; FileStream ws = null;
    try {
      using (var rs = new FileStream(hs, FileAccess.Read, 1 << 16)) {
        if (dst != null && Istnieje(dst)) return "ISTNIEJE";
        // Plik w kopii zakladamy dopiero po sprawdzeniu pierwszego bloku (1 MB) -
        // wyzerowany plik tekstowy nie zostawia wtedy w kopii nawet pustego katalogu.
        byte[] buf = new byte[1 << 20];
        byte[] wstrzym = null; int wstrzymN = 0;
        long ciag = 0, poczCiagu = 0, maxCiag = 0, gdzie = -1, poz = 0, przeczytane = 0;
        // dziury: suma blokow, ich liczba i opis pierwszych pieciu (od bajtu, dlugosc)
        long dlugosc = rs.Length, sumaBlokow = 0, limit = (long)Math.Floor(rs.Length * progDziur);
        int ileBlokow = 0;
        var opisBlokow = new System.Text.StringBuilder();
        bool same = true, zaDuzo = false, zerowyKoniec = false;
        int n;
        string blad;
        while ((n = rs.Read(buf, 0, buf.Length)) > 0) {
          przeczytane += n;
          if (zera) {
            for (int j = 0; j < n; j++) {
              if (buf[j] == 0) {
                if (ciag == 0) poczCiagu = poz + j;
                ciag++;
                if (ciag > maxCiag) { maxCiag = ciag; if (ciag >= minCiag) gdzie = poczCiagu; }
              } else {
                if (ciag >= minCiag) {
                  sumaBlokow += ciag; ileBlokow++;
                  if (ileBlokow <= 5) opisBlokow.Append((ileBlokow > 1 ? "; " : "") + "od bajtu " + poczCiagu + " dl. " + ciag + " B");
                }
                ciag = 0; same = false;
              }
            }
            // za duzo zer jak na dziure - dalej nie czytamy, plik i tak nie idzie do kopii
            if (sumaBlokow + (ciag >= minCiag ? ciag : 0) > limit) { zaDuzo = true; break; }
          }
          if (dst != null) {
            if (ws == null && wstrzym == null) { wstrzym = (byte[])buf.Clone(); wstrzymN = n; }
            else {
              if (ws == null) {
                blad = OtworzCel(dst, out tmp, out hd, out ws);
                if (blad != null) return blad;
                ws.Write(wstrzym, 0, wstrzymN);
              }
              ws.Write(buf, 0, n);
            }
          }
          poz += n;
        }
        if (zera && !zaDuzo && ciag >= minCiag) {
          // blok zer na samym koncu: swieze uszkodzenie (po nim nikt nic nie dopisal)
          zerowyKoniec = true; sumaBlokow += ciag; ileBlokow++;
        }
        bool caly = same && przeczytane > 0 && przeczytane >= dlugosc;
        if (zera && (zaDuzo || zerowyKoniec || caly)) {
          string opis = caly
            ? ("caly plik (" + przeczytane + " B) to same bajty 0x00")
            : ("blok co najmniej " + maxCiag + " bajtow 0x00 od bajtu " + gdzie +
               (zerowyKoniec && !zaDuzo ? " (na koncu pliku)" : ""));
          if (ws != null) {
            // plik > 1 MB zdazyl juz zalozyc katalogi - zdejmujemy te, ktore zostaly puste
            ws.Dispose(); ws = null; DeleteFileW(L(tmp)); tmp = null;
            string k = dst.Substring(0, dst.LastIndexOf('\\'));
            while (k.LastIndexOf('\\') > 2 && RemoveDirectoryW(L(k))) { zalozone.Remove(k); k = k.Substring(0, k.LastIndexOf('\\')); }
          }
          return "ZERA:" + opis;
        }
        if (dst != null && ws == null) {
          blad = OtworzCel(dst, out tmp, out hd, out ws);
          if (blad != null) return blad;
          if (wstrzym != null) ws.Write(wstrzym, 0, wstrzymN);
        }
        if (ws != null) {
          ws.Flush(true);
          long w = czas;
          SetFileTime(hd, IntPtr.Zero, IntPtr.Zero, ref w);
          ws.Dispose(); ws = null;
          if (!MoveFileExW(L(tmp), L(dst), 8)) {
            int e = Marshal.GetLastWin32Error();
            return (e == 183 || e == 80) ? "ISTNIEJE" : ("BLAD:przemianowanie kopii (blad Win32 " + e + ")");
          }
          tmp = null;
        }
        if (zera && ileBlokow > 0) {
          double proc = przeczytane > 0 ? (100.0 * sumaBlokow / przeczytane) : 0;
          string bl = ileBlokow == 1 ? " blok" : ((ileBlokow % 10 >= 2 && ileBlokow % 10 <= 4 && (ileBlokow % 100 < 12 || ileBlokow % 100 > 14)) ? " bloki" : " blokow");
          return "DZIURY:" + ileBlokow + bl + " zer, razem " + sumaBlokow + " B z " + przeczytane + " B (" +
                 proc.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture) + "% pliku): " + opisBlokow.ToString() +
                 (ileBlokow > 5 ? "; i " + (ileBlokow - 5) + " wiecej" : "");
        }
        return "OK";
      }
    } catch (IOException ex) {
      int e = Marshal.GetHRForException(ex) & 0xFFFF;
      if (e == 32 || e == 33) return "W_UZYCIU";
      if (e == 112 || e == 39) return "PELNY:" + ex.Message;
      return "BLAD:" + ex.Message;
    } catch (Exception ex) {
      return "BLAD:" + ex.Message;
    } finally {
      if (ws != null) ws.Dispose();
      if (tmp != null) DeleteFileW(L(tmp));
      if (!hs.IsClosed) hs.Dispose();
    }
  }

  // --- rotacja (od 17.10.2026) ---
  // Pliki katalogu kopii (dlugie sciezki), bez schodzenia za dowiazania.
  static void Drzewo(string korzen, List<string> pliki, List<string> katalogi) {
    var stos = new Stack<string>();
    stos.Push(korzen.TrimEnd('\\'));
    while (stos.Count > 0) {
      string kat = stos.Pop();
      katalogi.Add(kat);
      FIND d;
      IntPtr h = FindFirstFileExW(L(kat) + @"\*", 1, out d, 0, IntPtr.Zero, 2);
      if (h == ZLY) continue;
      do {
        if (d.Name == "." || d.Name == "..") continue;
        string p = kat + "\\" + d.Name;
        if ((d.Attr & 0x10) != 0 && (d.Attr & 0x400) == 0) stos.Push(p); else pliki.Add(p);
      } while (FindNextFileW(h, out d));
      FindClose(h);
    }
  }

  // Usuwa katalog z cala zawartoscia. Wynik: lista bledow (pusta = usuniety).
  public static List<string> UsunDrzewo(string korzen) {
    var bledy = new List<string>();
    var pliki = new List<string>(); var katalogi = new List<string>();
    Drzewo(korzen, pliki, katalogi);
    foreach (var p in pliki) {
      if (!DeleteFileW(L(p)) && !RemoveDirectoryW(L(p))) bledy.Add(p + " (blad Win32 " + Marshal.GetLastWin32Error() + ")");
    }
    for (int i = katalogi.Count - 1; i >= 0; i--) {
      if (!RemoveDirectoryW(L(katalogi[i])) && bledy.Count == 0) bledy.Add(katalogi[i] + " (blad Win32 " + Marshal.GetLastWin32Error() + ")");
    }
    zalozone.Clear();
    return bledy;
  }

  // Wlewa katalog dnia (zmiany\RRRR-MM-DD) do pelnej kopii: kazdy plik przechodzi na swoje
  // miejsce w pelnej, zastepujac starsza wersje; resztki *.kopia-tmp (przerwany zapis) sa
  // kasowane. Wynik: liczba przeniesionych plikow; bledy dopisuje do listy.
  public static int Wlej(string dzien, string pelna, List<string> bledy) {
    var pliki = new List<string>(); var katalogi = new List<string>();
    dzien = dzien.TrimEnd('\\'); pelna = pelna.TrimEnd('\\');
    Drzewo(dzien, pliki, katalogi);
    int n = 0;
    foreach (var p in pliki) {
      if (p.EndsWith(".kopia-tmp", StringComparison.OrdinalIgnoreCase)) { DeleteFileW(L(p)); continue; }
      string dst = pelna + p.Substring(dzien.Length);
      try { ZalozKatalog(dst.Substring(0, dst.LastIndexOf('\\'))); }
      catch (Exception ex) { bledy.Add(p + " - " + ex.Message); continue; }
      // 1 = MOVEFILE_REPLACE_EXISTING (ten sam dysk - przemianowanie, bez kopiowania danych)
      if (MoveFileExW(L(p), L(dst), 1)) n++;
      else bledy.Add(p + " -> " + dst + " (blad Win32 " + Marshal.GetLastWin32Error() + ")");
    }
    return n;
  }
}
'@
}

# --- reguly wykluczen --------------------------------------------------------

$Reguly = New-Object 'System.Collections.Generic.List[KopiaRegula]'
function Regula([string]$wzor, [string]$powod, [bool]$katalog, [bool]$sekret = $false) {
  $r = New-Object KopiaRegula
  $r.Wzor = New-Object System.Text.RegularExpressions.Regex($wzor, 'IgnoreCase, CultureInvariant')
  $r.Powod = $powod; $r.Katalog = $katalog; $r.Sekret = $sekret
  $Reguly.Add($r)
}
function E([string]$s) { [regex]::Escape($s) }
$eH = E $H

# Zawsze, takze z -ZSekretami: logowanie do kont. Odtwarza sie je zalogowaniem.
Regula "^$eH\\\.claude\\\.credentials\.json$" "plik logowania Claude'a (token konta) - nie kopiujemy nigdy" $false
Regula "^$eH\\\.codex\\auth\.json$" "plik logowania Codeksa (token konta) - nie kopiujemy nigdy" $false
Regula "^$eH\\\.codex\\\.sandbox-secrets$" "sekrety piaskownicy Codeksa - nie kopiujemy nigdy" $true

# Odtwarzalne: zaleznosci, wyniki budowania, pamieci podreczne, pliki tymczasowe.
Regula '\\(node_modules|\.next|\.nuxt|\.turbo|\.svelte-kit|\.parcel-cache|\.pnpm-store)$' "zaleznosci/wynik budowania JS - odtwarzalne (npm install, build)" $true
Regula '\\(\.venv|venv|__pycache__|\.pytest_cache|\.mypy_cache|\.ruff_cache)$' "srodowisko/pamiec podreczna Pythona - odtwarzalne" $true
Regula '\\(\.cache|\.tmp|tmp|temp)$' "pamiec podreczna / pliki tymczasowe" $true
Regula '\\ms-playwright$' "przegladarki Playwrighta - odtwarzalne (npx playwright install)" $true
Regula '\\\.claude\\worktrees$' "kopie robocze agentow (git worktree) - tymczasowe, tresc jest w git" $true
Regula '\.(tmp|temp|kopia-tmp)$' "plik tymczasowy" $false
Regula '\\(~\$[^\\]*|Thumbs\.db)$' "plik techniczny Windows/Office" $false
Regula '\\node\\node\.exe$' "program przenosny (node.exe) - odtwarzalny" $false
Regula '\\minio\.exe$' "program przenosny (minio.exe) - odtwarzalny" $false
# Wykluczenia konkretnych folderow uzytkownika (np. programy przenosne w C:\dev\tools,
# nagrania robota w jednym z projektow) NIE sa tu - przychodza z ustawien (rejestr albo
# ~\.claude\mr\lokalne.json) i dochodza do tej listy w Ustal-Ustawienia nizej.

# ~\.claude i ~\.codex: katalogi techniczne. Zostaja: CLAUDE.md, wiedza, skills,
# agents, commands, mr, projects (transkrypty), file-history, settings, lore.db.
Regula "^$eH\\\.claude\\(shell-snapshots|statsig|todos|session-env|sessions|paste-cache|cache|ide|telemetry|debug|lore_models|backups)$" "katalog techniczny Claude Code (migawki powloki, sesje, pamiec podreczna, model Lore do pobrania, autokopie .claude.json)" $true
Regula "^$eH\\\.claude\\plugins\\(marketplaces|cache|\.trash)$" "wtyczki pobrane z marketplace - odtwarzalne" $true
# Kosz po usunietych skillach - zaklada go sama aplikacja Claude, nikt z niego nie czyta.
# 08.10.2026 dal 18 z 21 alarmow "wyzerowany plik" (pliki w calosci zerowe, bez zdrowej
# wersji w zadnej kopii) - falszywy alarm o czyms, czego nikt nie potrzebuje.
Regula "^$eH\\\.claude\\skills\\\.trash$" "kosz po usunietych skillach (zaklada go aplikacja Claude) - nieuzywany" $true
# Jednorazowe skrypty startowe przypomnien (zasobnik\terminy.ps1 Zapisz-Skrypt-Startowy):
# zapisywane od nowa przy kazdym otwarciu przypomnienia, po nim zbedne. Tresc przypomnienia
# jest w ~\.claude\mr\przypomnienia.md - ten idzie do kopii. 08.10.2026: zrob-1.ps1
# wyzerowany po zaniku pradu = 1 z 21 alarmow.
Regula "^$eH\\\.claude\\mr\\terminy\\zrob-[^\\]*\.ps1$" "skrypt startowy przypomnienia (zasobnik\terminy.ps1) - jednorazowy, zapisywany od nowa" $false
# Pliki blokady z wierzchu ~\.claude (np. lore-podpowiedz.lock) - bez tresci, trzymane otwarte
# przez dzialajacy proces; 17.10.2026 jedyny plik W UZYCIU w pelnej kopii. Trwale trzymany
# po -Trzymaj dniach dawalby codzienny BLAD o niczym. Tylko ~\.claude - yarn.lock, uv.lock
# itp. w projektach to tresc i ida do kopii.
Regula "^$eH\\\.claude\\[^\\]*\.lock$" "plik blokady w ~\.claude (bez tresci, trzymany przez dzialajacy proces)" $false
Regula "^$eH\\\.claude\\lore\.db\.przed-[^\\]*$" "stara migawka lore.db sprzed migracji (184 MB) - aktualna lore.db jest w kopii" $false
Regula "^$eH\\\.claude\\mr\\kopia-(indeks|w-uzyciu)\.tsv(\.nowy)?$" "indeks samej kopii (zmienia sie co dzien)" $false
Regula "^$eH\\\.codex\\(\.sandbox|\.sandbox-bin|\.tmp|tmp|cache|packages|thread-writer-locks)$" "katalog techniczny Codeksa (programy, piaskownica, pamiec podreczna)" $true
Regula "^$eH\\\.codex\\plugins\\cache$" "wtyczki Codeksa pobrane z sieci - odtwarzalne" $true
Regula "^$eH\\\.codex\\models_cache\.json$" "pamiec podreczna Codeksa" $false

# Sekrety - domyslnie NIE (decyzja uzytkownika), wlacza je -ZSekretami.
if (-not $ZSekretami) {
  Regula '\\\.ssh$' "klucze SSH - wlacz -ZSekretami" $true $true
  Regula "^$eH\\\.claude\\sekrety$" "sekrety MegaRuchacza - wlacz -ZSekretami" $true $true
  Regula '\\\.env$' "plik .env (hasla, klucze API) - wlacz -ZSekretami" $false $true
  Regula '\\\.env\.(?![^\\]*(example|sample|template))[^\\]+$' "plik .env.* (hasla, klucze API) - wlacz -ZSekretami" $false $true
  Regula '\.(pem|key|ppk|pfx|p12)$' "klucz/certyfikat - wlacz -ZSekretami" $false $true
  Regula '\.secret\.[^\\]*$' "plik oznaczony .SECRET. - wlacz -ZSekretami" $false $true
}

$RozszBinarne = @{}
'.png .jpg .jpeg .gif .webp .ico .bmp .pdf .zip .gz .7z .rar .exe .dll .bin .onnx .safetensors .pyc .woff .woff2 .ttf .db .sqlite .sqlite3 .mp4 .webm .pma .node .xlsx .xls .docx .doc .pptx .ppt .odt .ods .jar .class .mp3 .wav .mov .avi .tar .tgz .bz2 .xz .wasm'.Split(' ') | ForEach-Object { $RozszBinarne[$_] = 1 }
$RozszTekst = @{}
'.md .txt .json .jsonl .ps1 .psm1 .psd1 .js .mjs .cjs .ts .tsx .jsx .py .toml .yaml .yml .ini .cfg .csv .html .htm .css .sql .sh .bat .cmd .xml .vbs'.Split(' ') | ForEach-Object { $RozszTekst[$_] = 1 }

function W-KorzeniuClaude([string]$p) {
  foreach ($k in $KorzenieClaude) { if ($p -eq $k -or $p.StartsWith($k + '\', 'OrdinalIgnoreCase')) { return $true } }
  return $false
}

# Ktory plik sprawdzamy na zera: wszystko z plikow Claude'a poza binarnymi (wiedza
# ma pliki bez rozszerzenia, np. .ostatnie-wyciaganie-id), a w projektach - tekst.
# Logi spoza plikow Claude'a nie: po awarii zasilania maja bloki zer i alarm co
# dzien bylby falszywy w sensie "nic waznego".
function Do-Sprawdzenia([string]$p) {
  if ($p -match '\\\.git\\') { return $false }
  # dowody awarii (~\.claude\awaria-*) sa wyzerowane celowo - kopiujemy je bez alarmu
  if ($p -match '\\\.claude\\awaria-[^\\]*\\') { return $false }
  $i = $p.LastIndexOf('.'); $j = $p.LastIndexOf('\')
  $roz = if ($i -gt $j) { $p.Substring($i).ToLowerInvariant() } else { "" }
  if (W-KorzeniuClaude $p) { return -not $RozszBinarne.ContainsKey($roz) }
  return $RozszTekst.ContainsKey($roz)
}

# --- pomocnicze ---------------------------------------------------------------

function MB([long]$b) { "{0:N1} MB" -f ($b / 1MB) }

function Do-Kopii([string]$zrodlo, [string]$katalogPrzebiegu) {
  # C:\dev\x -> <przebieg>\C\dev\x ; \\serwer\x -> <przebieg>\UNC\serwer\x
  if ($zrodlo.StartsWith('\\')) { return $katalogPrzebiegu + '\UNC\' + $zrodlo.Substring(2) }
  return $katalogPrzebiegu + '\' + $zrodlo.Substring(0, 1) + $zrodlo.Substring(2)
}

# Gdzie w kopii lezy ostatnia wersja pliku sprzed tego przebiegu - do wpisow ALARM
# WYZEROWANY PLIK i DZIURA (zeby czlowiek wiedzial, skad ja wziac, albo ze jej nie ma).
# Przeszukuje katalogi zmiany\* (od najmlodszego) i pelna-*, bez biezacego przebiegu.
# Lista katalogow czytana raz na przebieg; pytamy tylko o pliki z zerami (kilka sztuk).
$script:KatalogiWersji = $null
function Ostatnia-Wersja([string]$zrodlo) {
  if ($null -eq $script:KatalogiWersji) {
    $kat = @()
    if (Test-Path -LiteralPath "$Cel\zmiany") {
      $kat += @(Get-ChildItem -LiteralPath "$Cel\zmiany" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending |
               ForEach-Object { [pscustomobject]@{ Kat = $_.FullName; Data = $_.Name.Substring(0, [Math]::Min(10, $_.Name.Length)) } })
    }
    $kat += @(Get-ChildItem -LiteralPath $Cel -Directory -Filter "pelna-*" -ErrorAction SilentlyContinue | Sort-Object Name -Descending |
             ForEach-Object { [pscustomobject]@{ Kat = $_.FullName; Data = $_.Name.Substring(6, [Math]::Min(10, $_.Name.Length - 6)) } })
    $script:KatalogiWersji = @($kat | Where-Object { $_.Kat.TrimEnd('\') -ne $Przebieg })
  }
  foreach ($k in $script:KatalogiWersji) {
    $p = Do-Kopii $zrodlo $k.Kat
    if ([KopiaIO]::Istnieje($p)) { return "ostatnia wersja w kopii: $p (z $($k.Data))" }
  }
  return "w kopii nie ma zadnej wersji tego pliku"
}

function Zapisz-Stan([string]$tresc) {
  try {
    $kat = Split-Path -Parent $PlikStanu
    if (-not (Test-Path -LiteralPath $kat)) { New-Item -ItemType Directory -Force -Path $kat | Out-Null }
    [IO.File]::WriteAllText($PlikStanu, $tresc, (New-Object Text.UTF8Encoding($false)))
  } catch {
    # pliku stanu nie da sie zapisac - zostaje tylko kod wyjscia i konsola
    Write-Host "BLAD  nie da sie zapisac pliku stanu $PlikStanu : $($_.Exception.Message)" -ForegroundColor Red
    $script:BladStanu = $true
  }
}

$Python = $null
function Znajdz-Pythona {
  # srodowisko Lore w repo, w ktorym lezy ten skrypt (narzedzia\..\lore\.venv)
  $kand = Join-Path (Split-Path -Parent $PSScriptRoot) "lore\.venv\Scripts\python.exe"
  if (Test-Path -LiteralPath $kand) { return @($kand) }
  $uv = Get-Command uv.exe -ErrorAction SilentlyContinue
  if ($uv) { return @($uv.Source, "run", "--no-project", "python") }
  return $null
}

$KodSqlite = @'
import sqlite3, sys, pathlib
src, dst = sys.argv[1], sys.argv[2]
s = sqlite3.connect(pathlib.Path(src).as_uri() + "?mode=ro", uri=True, timeout=60)
d = sqlite3.connect(dst)
s.backup(d)
r = d.execute("pragma quick_check").fetchone()[0]
d.close(); s.close()
print(r)
sys.exit(0 if r == "ok" else 3)
'@

function Kopiuj-Sqlite([string]$zrodlo, [string]$dst, [long]$czas) {
  # @(...) obowiazkowo: jednoelementowa tablica z funkcji rozwija sie do napisu
  if (-not $script:Python) { $script:Python = @(Znajdz-Pythona) }
  if ($script:Python.Count -eq 0 -or -not $script:Python[0]) { return "BLAD:brak Pythona (lore\.venv ani uv) - bazy SQLite nie da sie bezpiecznie skopiowac" }
  $tmp = $null
  try {
    $tmpKat = Join-Path $env:TEMP "mr-kopia-sqlite"
    New-Item -ItemType Directory -Force -Path $tmpKat | Out-Null
    $py = Join-Path $tmpKat "backup.py"
    [IO.File]::WriteAllText($py, $KodSqlite)
    $tmp = Join-Path $tmpKat ([guid]::NewGuid().ToString() + ".db")
    $exe = $script:Python[0]; $resz = @($script:Python | Select-Object -Skip 1)
    $wynik = & $exe @resz $py $zrodlo $tmp 2>&1
    if ($LASTEXITCODE -ne 0) { return "BLAD:sqlite3.backup nie przeszedl (kod $LASTEXITCODE): $(($wynik | Out-String).Trim())" }
    return [KopiaIO]::Kopiuj($tmp, $dst, $false, $MinCiagZer, $ProgDziur, $czas)
  } catch {
    # blad jednej bazy nie przerywa calej kopii - idzie do listy bledow
    return "BLAD:kopia bazy SQLite: $($_.Exception.Message)"
  } finally {
    if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force }
  }
}

# --- ustawienia: co kopiowac, dokad, czego nie (P59d) --------------------------
# Skad - patrz naglowek. Umowa rejestru (narzedzia\instalacja\stan.ps1) wczytywana
# kropka wewnatrz funkcji: rejestr i ustawienia lokalne czyta sie tym samym kodem, co
# u instalatora, straznika i nadzorcy. "~" na poczatku sciezki = katalog domowy ($H).

function Rozwin-Sciezke([string]$p) {
  $p = "$p".Trim()
  if ($p -match '^~(\\|/|$)') { $p = $H + $p.Substring(1) }
  return $p.TrimEnd('\')
}

# Zwraca Skad (opis po ludzku), Zrodla, Cel, Wykluczenia, Alarm (rejestr nieczytelny),
# Uwaga i Brak (rejestr bez ustawien kopii - wtedy Zrodla i Cel zostaja puste).
# Rejestr z celem, ale bez listy zrodel: pliki Claude'a i Codeksa ($KorzenieClaude - to
# MegaRuchacz wie sam, gdzie leza) i UWAGA w dzienniku; bez celu - Brak (nie zgadujemy).
function Ustal-Ustawienia {
  $u = [pscustomobject]@{ Skad = ""; Zrodla = @(); Cel = ""; Wykluczenia = @(); Alarm = ""; Uwaga = ""; Brak = "" }
  $umowa = Join-Path $PSScriptRoot "instalacja\stan.ps1"
  if (-not (Test-Path -LiteralPath $umowa)) { throw "nie ma umowy rejestru instalacji $umowa" }
  . $umowa
  $s = Czytaj-Instalacje $H
  $rejestr = Sciezka-Instalacji $H
  $k = $null
  if ($s.zrodlo -eq "plik") {
    $u.Skad = "rejestr instalacji $rejestr"
    if (-not $s.kopia) { $u.Brak = "rejestr instalacji $rejestr nie ma ustawien kopii (pole kopia: zrodla i cel) - wybierz je w instalatorze"; return $u }
    $k = $s.kopia
  } else {
    # rejestru nie ma albo jest nieczytelny: ustawienia tego komputera (lokalne.json), a bez nich
    # szablon z repo; lokalne.json nieczytelny = wyjatek, czyli BLAD z powodem (Bez-Ustawien)
    $d = Kopia-Bez-Rejestru (Split-Path -Parent $PSScriptRoot) $H
    $k = $d.Kopia
    $opis = if ($d.Lokalne) { "ustawienia tego komputera $($d.Plik)" } else { "szablon $($d.Plik) (w $(Sciezka-Lokalnych $H) nie ma pola kopia)" }
    if ($s.blad) {
      $u.Skad = "$opis (REJESTR INSTALACJI NIECZYTELNY)"
      $u.Alarm = "ALARM rejestr instalacji nieczytelny ($($s.blad)) - zrodla, cel i wykluczenia kopii wziete z: $opis"
    } else {
      $u.Skad = "$opis (nie ma rejestru instalacji $rejestr - instalacja sprzed instalatora)"
    }
  }
  $u.Zrodla = @(@($k.zrodla) | Where-Object { "$_".Trim() } | ForEach-Object { Rozwin-Sciezke $_ })
  if ($k.cel) { $u.Cel = Rozwin-Sciezke $k.cel }
  if (($u.Zrodla.Count -eq 0) -and ($s.zrodlo -eq "plik")) {
    $u.Zrodla = @($KorzenieClaude)
    $u.Uwaga = "w rejestrze instalacji nie ma listy zrodel kopii (kopia.zrodla) - kopiuje pliki Claude'a i Codeksa: $($KorzenieClaude -join ', ')"
  }
  foreach ($w in @($k.wykluczenia)) {
    if (-not $w -or -not "$($w.sciezka)".Trim()) { continue }
    $powod = "$($w.powod)"
    if (-not $powod) { $powod = "wykluczone w ustawieniach kopii" }
    $u.Wykluczenia += [pscustomobject]@{ Sciezka = (Rozwin-Sciezke $w.sciezka); Powod = $powod; Katalog = $w.katalog }
  }
  if ($u.Zrodla.Count -eq 0) { $u.Brak = "w ustawieniach ($($u.Skad)) nie ma zrodel kopii" }
  elseif (-not $u.Cel) { $u.Brak = "w ustawieniach ($($u.Skad)) nie ma celu kopii" }
  return $u
}

# Bez ustawien nie ma kopii - ale nie po cichu: stan=BLAD z powodem (nadzorca go pokaze).
function Bez-Ustawien([string]$powod) {
  Write-Host "BLAD  kopia nie ruszyla: $powod" -ForegroundColor Red
  if (-not $Proba) { Zapisz-Stan ("stan=BLAD`r`nostatnia=" + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + "`r`nprzyczyna=USTAWIENIA`r`nblad=$powod`r`n") }
  exit 1
}

$Ustawienia = $null
$bladUstawien = ""
try { $Ustawienia = Ustal-Ustawienia } catch { $bladUstawien = $_.Exception.Message }
$wprost = ($Zrodla.Count -gt 0) -and $Cel
if (-not $Ustawienia) {
  if (-not $wprost) { Bez-Ustawien "nie odczytalem ustawien kopii: $bladUstawien" }
  $Ustawienia = [pscustomobject]@{ Skad = "-Zrodla i -Cel z wywolania (ustawien nie odczytalem: $bladUstawien)"; Zrodla = @(); Cel = ""; Wykluczenia = @(); Alarm = ""; Uwaga = ""; Brak = "" }
}
if ($Zrodla.Count -gt 0) { $Ustawienia.Skad = "-Zrodla z wywolania; reszta: " + $Ustawienia.Skad } else { $Zrodla = @($Ustawienia.Zrodla) }
if ($Cel) { $Ustawienia.Skad = "-Cel z wywolania; " + $Ustawienia.Skad } else { $Cel = $Ustawienia.Cel }
if (($Zrodla.Count -eq 0) -or (-not $Cel)) {
  $pw = $Ustawienia.Brak
  if (-not $pw) { $pw = "brak $(if ($Zrodla.Count -eq 0) { 'zrodel' } else { 'celu' }) kopii ($($Ustawienia.Skad))" }
  Bez-Ustawien $pw
}
$Cel = $Cel.TrimEnd('\')
# wykluczenia z ustawien - dokladnie te sciezki (bez wzorcow); bez "katalog" = katalog i plik
foreach ($w in $Ustawienia.Wykluczenia) {
  $wz = "^" + (E $w.Sciezka) + "$"
  if ($null -eq $w.Katalog) { Regula $wz $w.Powod $true; Regula $wz $w.Powod $false }
  else { Regula $wz $w.Powod ([bool]$w.Katalog) }
}

# --- rotacja (naglowek: ROTACJA) ----------------------------------------------
# Wola ja tylko udany przebieg (indeks zapisany). Wynik: opis do dziennika; bledy -> $Bledy
# (plik, ktorego nie dalo sie przeniesc/usunac, zostaje w katalogu dnia - nastepny przebieg
# sprobuje znowu, nic nie ginie).
function Data-Katalogu([string]$nazwa) {
  $m = [regex]::Match($nazwa, '^(?:pelna-)?(\d{4}-\d{2}-\d{2})(?:_[0-9-]+)?$')
  if ($m.Success) { return $m.Groups[1].Value }
  return $null
}

function Rotacja {
  $opis = New-Object 'System.Collections.Generic.List[string]'
  $pelne = @(Get-ChildItem -LiteralPath $Cel -Directory -Filter "pelna-*" -ErrorAction Stop |
             Where-Object { Data-Katalogu $_.Name } | Sort-Object Name -Descending)
  if ($pelne.Count -eq 0) { return "rotacja: brak pelnej kopii - nic do wlania" }
  $baza = $pelne[0].FullName; $dataBazy = Data-Katalogu $pelne[0].Name
  $dni = @()
  if (Test-Path -LiteralPath "$Cel\zmiany") {
    $dni = @(Get-ChildItem -LiteralPath "$Cel\zmiany" -Directory -ErrorAction Stop |
             Where-Object { Data-Katalogu $_.Name } | Sort-Object Name)
  }
  # dni kopii = daty katalogow zmiany\ i data najnowszej pelnej; zostaje $Trzymaj najmlodszych
  $daty = @(@($dni | ForEach-Object { Data-Katalogu $_.Name }) + @($dataBazy) | Sort-Object -Unique -Descending)
  $zostaja = @($daty | Select-Object -First $Trzymaj)
  $wlane = 0; $plikow = 0; $usuniete = 0
  foreach ($d in $dni) {
    $data = Data-Katalogu $d.Name
    if ($zostaja -contains $data) { continue }
    if ($d.FullName.TrimEnd('\') -eq $Przebieg) { continue }   # dzisiejszego nie ruszamy nigdy
    $bl = New-Object 'System.Collections.Generic.List[string]'
    if ($data -ge $dataBazy) {
      $plikow += [KopiaIO]::Wlej($d.FullName, $baza, $bl)
      foreach ($b in $bl) { $Bledy.Add("rotacja: nie przenioslem do pelnej kopii: $b") }
      if ($bl.Count -gt 0) { continue }   # zostaje do nastepnego przebiegu
      $wlane++
    } else { $usuniete++ }
    foreach ($b in [KopiaIO]::UsunDrzewo($d.FullName)) { $Bledy.Add("rotacja: nie usunalem $b") }
  }
  if ($wlane) { $opis.Add("wlane do $($pelne[0].Name): $wlane $(if ($wlane -eq 1) { 'dzien' } else { 'dni' }) ($plikow plikow)") }
  if ($usuniete) { $opis.Add("usuniete dni sprzed $($pelne[0].Name): $usuniete") }
  if (-not ($zostaja -contains $dataBazy)) {
    foreach ($p in @($pelne | Select-Object -Skip 1)) {
      foreach ($b in [KopiaIO]::UsunDrzewo($p.FullName)) { $Bledy.Add("rotacja: nie usunalem $b") }
      $opis.Add("usunieta starsza pelna kopia $($p.Name)")
    }
  }
  $txt = "rotacja (trzymam $Trzymaj ostatnich dni kopii): "
  if ($opis.Count) { return $txt + ($opis -join "; ") }
  return $txt + "nic do zrobienia"
}

# Pliki W UZYCIU: od kiedy kazdy jest zablokowany (sciezka TAB data). Zwraca slownik.
function Czytaj-WUzyciu {
  $s = @{}
  if (-not (Test-Path -LiteralPath $PlikWUzyciu)) { return $s }
  try {
    foreach ($l in [IO.File]::ReadAllLines($PlikWUzyciu)) {
      $c = $l.Split("`t"); if ($c.Count -eq 2 -and (Data-Katalogu $c[1])) { $s[$c[0]] = $c[1] }
    }
  } catch { $Uwagi.Add("nie odczytalem $PlikWUzyciu ($($_.Exception.Message)) - liczenie dni blokady od nowa") }
  return $s
}

# --- start --------------------------------------------------------------------

$t0 = Get-Date
$mutex = New-Object Threading.Mutex($false, "MegaRuchaczKopiaZapasowa")
if (-not $mutex.WaitOne(0)) {
  Write-Host "BLAD  inna kopia zapasowa juz trwa - ta konczy bez pracy" -ForegroundColor Red
  exit 1
}

$Alarmy = New-Object 'System.Collections.Generic.List[string]'
$Bledy = New-Object 'System.Collections.Generic.List[string]'
$Uwagi = New-Object 'System.Collections.Generic.List[string]'
$WUzyciu = New-Object 'System.Collections.Generic.List[string]'
$Dziury = New-Object 'System.Collections.Generic.List[string]'
if ($Ustawienia.Alarm) { $Alarmy.Add($Ustawienia.Alarm) }
if ($Ustawienia.Uwaga -and ($Zrodla.Count -gt 0) -and -not ($Ustawienia.Skad -like "-Zrodla z wywolania*")) { $Uwagi.Add($Ustawienia.Uwaga) }

try {
  if (-not $Proba) {
    Zapisz-Stan ("stan=TRWA`r`nstart=" + $t0.ToString("yyyy-MM-dd HH:mm:ss") + "`r`ncel=$Cel`r`n" +
                 "# TRWA ze starym startem = kopia przerwana (wylaczony komputer, zabity proces)`r`n")
    $rodzic = Split-Path -Parent $Cel
    $script:Przyczyna = "BRAK_CELU"
    if (-not (Test-Path -LiteralPath $rodzic)) { throw "nie ma katalogu nad celem kopii: $rodzic (Dysk Google nie wystartowal?)" }
    if (-not (Test-Path -LiteralPath $Cel)) { New-Item -ItemType Directory -Force -Path $Cel | Out-Null }
    $script:Przyczyna = "PRZERWANA"
  }

  # indeks: co juz jest w kopii
  $Indeks = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
  $indeksJest = $false
  if (Test-Path -LiteralPath $PlikIndeksu) {
    $txt = [IO.File]::ReadAllText($PlikIndeksu)
    if ($txt.Contains([char]0)) {
      $Alarmy.Add("ALARM indeks kopii $PlikIndeksu ma bajty 0x00 (uszkodzony) - kopiuje wszystko jak za pierwszym razem, nic nie nadpisujac")
    } else {
      foreach ($linia in $txt.Split("`n")) {
        $c = $linia.TrimEnd("`r").Split("`t")
        if ($c.Count -eq 3) { $Indeks[$c[0]] = $c[1] + "`t" + $c[2] }
      }
      $indeksJest = $Indeks.Count -gt 0
    }
  }
  $pelne = @()
  if (Test-Path -LiteralPath $Cel) { $pelne = @(Get-ChildItem -LiteralPath $Cel -Directory -Filter "pelna-*" -ErrorAction SilentlyContinue) }
  $Pelna = [bool]$Pierwsza
  if (-not $Pelna -and $indeksJest -and $pelne.Count -eq 0) {
    # Indeks jest, a pelnej kopii w celu nie ma (folder kopii usuniety albo nowy cel): przyrost
    # wzialby same zmiany od wczoraj i kopia bylaby dziurawa bez slowa - robimy pelna.
    $Pelna = $true
    $Uwagi.Add("w celu $Cel nie ma pelnej kopii (pelna-*), choc indeks jest - robie pelna od nowa")
  }
  if (-not $Pelna -and -not $indeksJest) {
    if ($pelne.Count -eq 0) {
      $Pelna = $true
      $Uwagi.Add("brak indeksu i brak pelnej kopii - robie pelna (pierwszy przebieg)")
    } elseif ($Alarmy.Count -eq 0) {
      $Alarmy.Add("ALARM brak indeksu $PlikIndeksu mimo istniejacej pelnej kopii - kopiuje wszystko do zmiany\, nic nie nadpisujac")
    }
  }
  $rodzaj = if ($Pelna) { "pelna" } else { "przyrostowa" }
  $nazwa = if ($Pelna) { "pelna-$Data" } else { "zmiany\$Data" }
  $Przebieg = "$Cel\$nazwa"
  if ((-not $Proba) -and (Test-Path -LiteralPath $Przebieg)) {
    # drugi przebieg tego dnia - nowy katalog, istniejacego nie ruszamy
    $baza = $nazwa + "_" + (Get-Date -Format "HHmmss")
    $nazwa = $baza; $nr = 2
    while (Test-Path -LiteralPath "$Cel\$nazwa") { $nazwa = "$baza-$nr"; $nr++ }
    $Przebieg = "$Cel\$nazwa"
  }

  # listowanie
  $Pliki = New-Object 'System.Collections.Generic.List[KopiaWpis]'
  $Pominiete = New-Object 'System.Collections.Generic.List[KopiaPominiety]'
  foreach ($z in $Zrodla) {
    $z = $z.TrimEnd('\')
    $w = [KopiaIO]::Stat($z)
    if ($w) { $Pliki.Add($w); continue }
    if (-not [KopiaIO]::Istnieje($z)) { $Uwagi.Add("zrodlo nie istnieje: $z"); continue }
    [KopiaIO]::Przejdz($z, $Reguly, $Pliki, $Pominiete)
  }
  foreach ($p in $Pominiete) { if ($p.Powod.StartsWith("BLAD:")) { $Bledy.Add("$($p.Sciezka) - $($p.Powod.Substring(5).Trim())") } }

  # bazy SQLite i ich pliki towarzyszace
  $Sqlite = @{}
  $czasy = @{}
  foreach ($f in $Pliki) { $czasy[$f.Sciezka] = $f }
  foreach ($f in $Pliki) {
    if ($f.Sciezka -match '\.(db|sqlite|sqlite3|db3)$' -and $f.Rozmiar -ge 100) {
      $nag = [KopiaIO]::Naglowek($f.Sciezka, 16)
      if ($nag -and [Text.Encoding]::ASCII.GetString($nag, 0, 15) -eq "SQLite format 3") { $Sqlite[$f.Sciezka] = $true }
    }
  }

  # decyzja o kazdym pliku
  $DoKopii = New-Object 'System.Collections.Generic.List[object]'
  $bezZmian = 0; $nowe = 0; $zmienione = 0; $towarzyszace = 0
  foreach ($f in $Pliki) {
    $p = $f.Sciezka
    $m = [regex]::Match($p, '^(.*)-(wal|shm|journal)$')
    if ($m.Success -and $Sqlite.ContainsKey($m.Groups[1].Value)) { $towarzyszace++; continue }
    $rozmiar = $f.Rozmiar; $czas = $f.Czas
    $baza = $Sqlite.ContainsKey($p)
    if ($baza -and $czasy.ContainsKey("$p-wal") -and $czasy["$p-wal"].Rozmiar -gt 0) {
      # zmiana w bazie WAL czesto dotyka tylko pliku -wal. Pusty -wal pomijamy:
      # sam odczyt bazy (takze nasz sqlite3.backup) zaklada go na nowo ze swiezym czasem.
      $wal = $czasy["$p-wal"]; $rozmiar += $wal.Rozmiar; if ($wal.Czas -gt $czas) { $czas = $wal.Czas }
    }
    $klucz = "$rozmiar`t$czas"
    $stary = $null
    $byl = $Indeks.TryGetValue($p, [ref]$stary)
    if (-not $Pelna -and $byl -and $stary -eq $klucz) { $bezZmian++; continue }
    if ($byl) { $zmienione++ } else { $nowe++ }
    $DoKopii.Add([pscustomobject]@{ Sciezka = $p; Rozmiar = $f.Rozmiar; Czas = $f.Czas; Klucz = $klucz; Baza = $baza
                                    Zera = (-not $baza) -and (Do-Sprawdzenia $p); StaryRozmiar = $(if ($byl) { [long]$stary.Split("`t")[0] } else { -1 }) })
  }
  $sumaDoKopii = ($DoKopii | Measure-Object Rozmiar -Sum).Sum
  if (-not $sumaDoKopii) { $sumaDoKopii = 0 }

  # Wolne miejsce na dysku celu PRZED kopiowaniem. Potrzeba: rozmiar kopii + 10% (pliki rosna
  # miedzy listowaniem a kopiowaniem - transkrypty, lore.db; w 2,5 min przebiegu o megabajty,
  # nigdy o 10%) + 512 MB (system i pamiec podreczna Dysku Google nie moga zostac z zerem).
  # Dysk Google pokazuje jako wolne miejsce to, co zglasza jego klient (zwykle miejsce na
  # dysku z jego pamiecia podreczna, nie limit konta) - pelne konto wyjdzie dopiero przy
  # wysylce w chmurze, poza zasiegiem tego skryptu.
  $wolne = [long]-1
  if ($WolneBajty -ge 0) { $wolne = $WolneBajty }
  else {
    try { $wolne = (New-Object IO.DriveInfo([IO.Path]::GetPathRoot($Cel))).AvailableFreeSpace }
    catch { $Uwagi.Add("nie sprawdzilem wolnego miejsca na $Cel ($($_.Exception.Message))") }
  }
  $potrzeba = [long]($sumaDoKopii * 1.1) + 512MB
  if ($wolne -ge 0 -and $wolne -lt $potrzeba) {
    $script:Przyczyna = "BRAK_MIEJSCA"
    $msg = "brak miejsca na dysku celu ($Cel): wolne $(MB $wolne), potrzeba $(MB $potrzeba) (kopia $(MB $sumaDoKopii) + zapas)"
    if ($Proba) { $Alarmy.Add("ALARM BRAK MIEJSCA - $msg") } else { throw $msg }
  }

  # kopiowanie (albo przy -Proba samo sprawdzenie zer)
  $skopiowane = 0; $bajty = [long]0; $wyzerowane = 0
  $ostatniMeldunek = Get-Date
  foreach ($k in $DoKopii) {
    $dst = if ($Proba) { $null } else { Do-Kopii $k.Sciezka $Przebieg }
    if ($Proba -and $k.Baza) { continue }
    if ($Proba -and -not $k.Zera) { continue }
    if ($k.Baza) { $wynik = Kopiuj-Sqlite $k.Sciezka $dst $k.Czas }
    else { $wynik = [KopiaIO]::Kopiuj($k.Sciezka, $dst, [bool]$k.Zera, $MinCiagZer, $ProgDziur, $k.Czas) }
    if ($wynik.StartsWith("DZIURY:")) {
      # skopiowany mimo dziury (patrz $ProgDziur) - slad zamiast alarmu
      $Dziury.Add("DZIURA W PLIKU - skopiowany mimo zer: $($k.Sciezka) - $($wynik.Substring(7)); " + (Ostatnia-Wersja $k.Sciezka))
      $wynik = "OK"
    }
    if ($wynik -eq "OK") {
      if (-not $Proba) {
        $skopiowane++; $bajty += $k.Rozmiar; $Indeks[$k.Sciezka] = $k.Klucz
        if ($k.Zera -and $k.Rozmiar -eq 0 -and $k.StaryRozmiar -gt 0) {
          $Uwagi.Add("plik skurczyl sie do 0 bajtow (poprzednio $($k.StaryRozmiar) B, ta wersja jest w kopii poprzedniego dnia): $($k.Sciezka)")
        }
      }
    } elseif ($wynik.StartsWith("ZERA:")) {
      $wyzerowane++
      $Alarmy.Add("ALARM WYZEROWANY PLIK - NIE skopiowany: $($k.Sciezka) - $($wynik.Substring(5)); " + (Ostatnia-Wersja $k.Sciezka))
    } elseif ($wynik -eq "W_UZYCIU") {
      $WUzyciu.Add($k.Sciezka)
    } elseif ($wynik -eq "ZNIKNAL") {
      # np. agent sprzatnal swoj git worktree w trakcie kopii - to nie blad kopii
      $Uwagi.Add("zniknal w trakcie kopii (usuniety u zrodla): $($k.Sciezka)")
    } elseif ($wynik -eq "ISTNIEJE") {
      $Bledy.Add("w kopii juz jest $dst - nie nadpisuje")
    } elseif ($wynik.StartsWith("PELNY:")) {
      # dysk celu pelny - kazdy nastepny plik i tak padnie; przerywamy cala kopie
      $script:Przyczyna = "BRAK_MIEJSCA"
      throw "brak miejsca na dysku celu ($Cel) przy kopiowaniu $($k.Sciezka): $($wynik.Substring(6)); skopiowane do tej chwili: $skopiowane z $($DoKopii.Count) plikow"
    } else {
      $Bledy.Add("$($k.Sciezka) - $($wynik -replace '^BLAD:', '')")
    }
    if (-not $Proba -and ((Get-Date) - $ostatniMeldunek).TotalSeconds -ge 60) {
      $ostatniMeldunek = Get-Date
      Zapisz-Stan ("stan=TRWA`r`nstart=" + $t0.ToString("yyyy-MM-dd HH:mm:ss") + "`r`npostep=" + $skopiowane + " z " + $DoKopii.Count +
                   " plikow, " + (MB $bajty) + " z " + (MB $sumaDoKopii) + "`r`nmeldunek=" + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + "`r`ncel=$Przebieg`r`n")
    }
  }

  $sekrety = @($Pominiete | Where-Object { $_.Sekret })
  $Bazy = @($Pominiete | Where-Object { $_.Powod.StartsWith("BAZA:") } | ForEach-Object { "BAZA DANYCH pominieta (kopia bazy to jej zrzut, np. pg_dump): $($_.Sciezka) - $($_.Powod.Substring(5).Trim())" })

  if ($Proba) {
    $czasTrwania = (Get-Date) - $t0
    Write-Output "PROBA - nic nie zostalo skopiowane ani zapisane"
    Write-Output ("ustawienia: " + $Ustawienia.Skad)
    Write-Output ("zrodla: " + ($Zrodla -join "; "))
    Write-Output ("cel: $Cel")
    Write-Output ("wykluczenia z ustawien: " + $(if (@($Ustawienia.Wykluczenia).Count) { (@($Ustawienia.Wykluczenia | ForEach-Object { $_.Sciezka }) -join "; ") } else { "zadnych" }))
    foreach ($a in $Alarmy) { Write-Output $a }
    foreach ($b in $Bledy) { Write-Output "BLAD  $b" }
    foreach ($z in $Dziury) { Write-Output $z }
    foreach ($z in $Bazy) { Write-Output $z }
    Write-Output ("rodzaj: $rodzaj  ->  $Cel\$nazwa  (rotacja: trzymam $Trzymaj ostatnich dni kopii)")
    Write-Output ("do skopiowania: {0} plikow, {1}  (nowe {2}, zmienione {3}, bez zmian {4}, pliki -wal/-shm w kopii bazy {5})" -f $DoKopii.Count, (MB $sumaDoKopii), $nowe, $zmienione, $bezZmian, $towarzyszace)
    Write-Output ""
    Write-Output "wedlug zrodla (C:\dev - wedlug projektu):"
    $grupy = @{}
    foreach ($k in $DoKopii) {
      $p = $k.Sciezka; $g = $p
      foreach ($z in $Zrodla) {
        $z = $z.TrimEnd('\')
        if ($p.StartsWith($z + '\', 'OrdinalIgnoreCase')) {
          $reszta = $p.Substring($z.Length + 1); $seg = $reszta.Split('\')
          $g = if ($seg.Count -gt 1) { "$z\$($seg[0])" } else { "$z\(pliki luzem)" }
          break
        }
      }
      if (-not $grupy.ContainsKey($g)) { $grupy[$g] = @(0, [long]0) }
      $grupy[$g][0]++; $grupy[$g][1] += $k.Rozmiar
    }
    $grupy.GetEnumerator() | Sort-Object { $_.Value[1] } -Descending | ForEach-Object {
      Write-Output ("  {0,10}  {1,7} pl.  {2}" -f (MB $_.Value[1]), $_.Value[0], $_.Key)
    }
    Write-Output ""
    Write-Output ("bazy SQLite (kopia przez sqlite3.backup): " + (($Sqlite.Keys | Sort-Object) -join ", "))
    Write-Output ""
    Write-Output ("SEKRETY pominiete ({0}){1}:" -f $sekrety.Count, $(if ($ZSekretami) { "" } else { " - wlacza je -ZSekretami" }))
    foreach ($s in $sekrety) { Write-Output "  $($s.Sciezka)" }
    Write-Output ""
    Write-Output "wykluczone (wedlug powodu):"
    $Pominiete | Where-Object { -not $_.Sekret } | Group-Object Powod | Sort-Object Count -Descending | ForEach-Object {
      Write-Output ("  [{0}] {1}" -f $_.Count, $_.Name)
      $lista = @($_.Group | ForEach-Object { $_.Sciezka })
      $ile = if ($Szczegoly) { $lista.Count } else { [Math]::Min(6, $lista.Count) }
      for ($i = 0; $i -lt $ile; $i++) { Write-Output "      $($lista[$i])" }
      if ($ile -lt $lista.Count) { Write-Output "      (+$($lista.Count - $ile) wiecej - pelna lista: -Szczegoly)" }
    }
    if ($Szczegoly) {
      Write-Output ""
      Write-Output "pliki do skopiowania:"
      foreach ($k in $DoKopii) { Write-Output ("  {0,12:N0}  {1}" -f $k.Rozmiar, $k.Sciezka) }
    }
    foreach ($u in $Uwagi) { Write-Output "UWAGA $u" }
    Write-Output ("czas: {0:mm\:ss}" -f $czasTrwania)
    if ($Alarmy.Count) { exit 2 }
    exit 0
  }

  # indeks - zapis przez plik obok i podmiane, zeby przerwany zapis nie zostawil kadlubka
  $sb = New-Object Text.StringBuilder
  foreach ($kv in $Indeks.GetEnumerator()) { [void]$sb.Append($kv.Key).Append("`t").Append($kv.Value).Append("`r`n") }
  $nowy = "$PlikIndeksu.nowy"
  [IO.File]::WriteAllText($nowy, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $nowy -Destination $PlikIndeksu -Force

  # Pliki W UZYCIU: od kiedy zablokowany. Pojedyncza blokada to ostrzezenie (plik pojdzie jutro);
  # blokada od $Trzymaj dni = w calym oknie rotacji nie ma jego swiezej kopii -> linia BLAD.
  $stareBlokady = Czytaj-WUzyciu
  $noweBlokady = @{}
  $LinieWUzyciu = New-Object 'System.Collections.Generic.List[string]'
  foreach ($u in $WUzyciu) {
    $od = if ($stareBlokady.ContainsKey($u)) { $stareBlokady[$u] } else { $Data }
    $noweBlokady[$u] = $od
    $dniBlokady = 0
    try { $dniBlokady = [int]([datetime]::ParseExact($Data, "yyyy-MM-dd", $null) - [datetime]::ParseExact($od, "yyyy-MM-dd", $null)).TotalDays }
    catch { $Uwagi.Add("zla data blokady '$od' dla $u - licze od dzis") }
    if ($dniBlokady -ge $Trzymaj) {
      $Bledy.Add("plik zablokowany przez inny program od $od ($dniBlokady dni) - w kopii z ostatnich $Trzymaj dni nie ma jego swiezej wersji; zamknij program, ktory go trzyma, albo wyklucz plik w ustawieniach kopii: $u")
    } else {
      $LinieWUzyciu.Add("W UZYCIU (pominiety, zablokowany przez inny program$(if ($od -ne $Data) { " od $od" }); sprobuje w nastepnym przebiegu): $u")
    }
  }
  try {
    $sbU = New-Object Text.StringBuilder
    foreach ($kv in $noweBlokady.GetEnumerator()) { [void]$sbU.Append($kv.Key).Append("`t").Append($kv.Value).Append("`r`n") }
    if ($noweBlokady.Count) { [IO.File]::WriteAllText($PlikWUzyciu, $sbU.ToString(), (New-Object Text.UTF8Encoding($false))) }
    elseif (Test-Path -LiteralPath $PlikWUzyciu) { Remove-Item -LiteralPath $PlikWUzyciu -Force }
  } catch { $Uwagi.Add("nie zapisalem $PlikWUzyciu ($($_.Exception.Message)) - dni blokady plikow beda liczone od nowa") }

  # rotacja - tylko po udanym przebiegu; jej bledy ida do $Bledy, nie przerywaja wpisu
  $opisRotacji = ""
  try { $opisRotacji = Rotacja }
  catch { $Bledy.Add("rotacja przerwana: $($_.Exception.Message) - stare kopie zostaja, nastepny przebieg sprobuje znowu") }
  $czasTrwania = (Get-Date) - $t0

  # dziennik - alarmy na POCZATKU wpisu
  $stan = if ($Alarmy.Count) { "ALARM" } elseif ($Bledy.Count) { "BLAD" } else { "OK" }
  $przyczyna = if ($Bledy.Count) { "PLIKI" } else { "" }
  $d = New-Object Text.StringBuilder
  [void]$d.AppendLine("=== " + $t0.ToString("yyyy-MM-dd HH:mm") + "  $rodzaj  stan=$stan  ->  $nazwa")
  foreach ($a in $Alarmy) { [void]$d.AppendLine($a) }
  [void]$d.AppendLine(("skopiowane: {0} plikow, {1}  (nowe {2}, zmienione {3}; bez zmian {4}); czas {5:hh\:mm\:ss}" -f $skopiowane, (MB $bajty), $nowe, $zmienione, $bezZmian, $czasTrwania))
  [void]$d.AppendLine(("pominiete: wyzerowane {0}, w uzyciu {1}, bledy {2}, sekrety {3}{4}, bazy danych {5}, wykluczone katalogi/pliki {6}; skopiowane mimo dziury {7}" -f $wyzerowane, $WUzyciu.Count, $Bledy.Count, $sekrety.Count, $(if ($ZSekretami) { " (z -ZSekretami)" } else { " (bez -ZSekretami)" }), $Bazy.Count, ($Pominiete.Count - $sekrety.Count - $Bazy.Count), $Dziury.Count))
  if ($opisRotacji) { [void]$d.AppendLine($opisRotacji) }
  foreach ($b in $Bledy) { [void]$d.AppendLine("BLAD  $b") }
  foreach ($z in $Dziury) { [void]$d.AppendLine($z) }
  foreach ($u in $LinieWUzyciu) { [void]$d.AppendLine($u) }
  foreach ($z in $Bazy) { [void]$d.AppendLine($z) }
  foreach ($u in $Uwagi) { [void]$d.AppendLine("UWAGA $u") }
  [void]$d.AppendLine("")
  [IO.File]::AppendAllText("$Cel\dziennik.txt", $d.ToString(), (New-Object Text.UTF8Encoding($false)))

  $s = "stan=$stan`r`nostatnia=" + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + "`r`nrodzaj=$rodzaj`r`ncel=$Przebieg`r`n" +
       "plikow=$skopiowane`r`nmb=" + [Math]::Round($bajty / 1MB, 1) + "`r`nalarmy=$($Alarmy.Count)`r`nbledy=$($Bledy.Count)`r`nw_uzyciu=$($WUzyciu.Count)`r`n" +
       "dziury=$($Dziury.Count)`r`nprzyczyna=$przyczyna`r`ntrzymam_dni=$Trzymaj`r`nustawienia=$($Ustawienia.Skad)`r`n"
  if ($opisRotacji) { $s += "rotacja=$opisRotacji`r`n" }
  # alarmy i dziury ida zawsze w calosci; lista bledow skrocona do 20 - ostrzezenie PRZED nia
  foreach ($a in $Alarmy) { $s += "$a`r`n" }
  foreach ($z in $Dziury) { $s += "$z`r`n" }
  if ($Bledy.Count -gt 20) { $s += "UWAGA lista bledow skrocona: ponizej 20 z $($Bledy.Count), pelna w $Cel\dziennik.txt`r`n" }
  foreach ($b in ($Bledy | Select-Object -First 20)) { $s += "BLAD  $b`r`n" }
  if ($LinieWUzyciu.Count -gt 20) { $s += "UWAGA lista plikow W UZYCIU skrocona: ponizej 20 z $($LinieWUzyciu.Count), pelna w $Cel\dziennik.txt`r`n" }
  foreach ($u in ($LinieWUzyciu | Select-Object -First 20)) { $s += "$u`r`n" }
  foreach ($z in $Bazy) { $s += "$z`r`n" }
  Zapisz-Stan $s

  Write-Output $d.ToString()
  if ($Alarmy.Count) { exit 2 }
  if ($Bledy.Count -or $script:BladStanu) { exit 1 }
  exit 0
} catch {
  $msg = $_.Exception.Message
  Write-Host "BLAD  kopia przerwana: $msg" -ForegroundColor Red
  if (-not $Proba) {
    # brak miejsca to awaria, ktora sama nie minie - linia ALARM (okno nadzorcy: od razu pilne)
    $al = if ($script:Przyczyna -eq "BRAK_MIEJSCA") { "ALARM BRAK MIEJSCA - kopia nie poszla: $msg`r`n" } else { "" }
    Zapisz-Stan ("stan=BLAD`r`nostatnia=" + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + "`r`nprzyczyna=$($script:Przyczyna)`r`nblad=$msg`r`n" + $al)
    try { [IO.File]::AppendAllText("$Cel\dziennik.txt", "=== " + $t0.ToString("yyyy-MM-dd HH:mm") + "  stan=BLAD  przyczyna=$($script:Przyczyna)  kopia przerwana: $msg`r`n`r`n") }
    catch { Write-Host "BLAD  nie da sie dopisac do dziennika: $($_.Exception.Message)" -ForegroundColor Red }
  }
  exit 1
} finally {
  $mutex.ReleaseMutex()
}
