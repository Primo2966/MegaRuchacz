# narzedzia\kopia-zapasowa.ps1 - dzienna kopia zapasowa C:\dev i plikow Claude'a
# na Dysk Google (domyslnie G:\Moj dysk\<folder>\Backup).
#
# UKLAD KOPII - nic nigdy nie jest nadpisywane ani kasowane:
#   Backup\pelna-RRRR-MM-DD\C\dev\...       pierwsza pelna kopia (sciezki jak na dysku C:)
#   Backup\zmiany\RRRR-MM-DD\C\...          kazdego dnia tylko pliki nowe i zmienione
#   Backup\dziennik.txt                     data, ile plikow, ile MB, alarmy, bledy, pominiete
#   ~\.claude\mr\kopia-stan.txt             znacznik "bylem tu" (stan=OK/ALARM/BLAD/TRWA)
#   ~\.claude\mr\kopia-indeks.tsv           co juz jest w kopii (sciezka, rozmiar, czas)
# Usuniecie pliku u zrodla NIE usuwa go z kopii. Drugi przebieg tego samego dnia
# idzie do zmiany\RRRR-MM-DD_GGMM - istniejacego pliku w kopii nie ruszamy nigdy.
# Odtwarzanie: najnowsza wersja pliku = jego kopia w najmlodszym katalogu zmiany\
# (albo w pelna-*, jesli od tamtej pory sie nie zmienial).
#
# Dlaczego tak: 2026-10-02 rano pliki pamieci (~\.claude\CLAUDE.md, wiedza\) zostaly
# wyzerowane. Kopia nadpisujaca skasowalaby zdrowa wersje. Dlatego (1) kazdy dzien
# trafia do osobnego katalogu, (2) przed skopiowaniem plik tekstowy jest sprawdzany
# na zera - wyzerowany NIE trafia do kopii, a w dzienniku i pliku stanu staje ALARM.
#
# Uzycie:
#   kopia-zapasowa.ps1                 przyrostowa (zadanie Harmonogramu; bez indeksu = pelna)
#   kopia-zapasowa.ps1 -Pierwsza       pelna kopia do pelna-RRRR-MM-DD
#   kopia-zapasowa.ps1 -Proba          tylko pokazuje, co by skopiowal (i ile MB) - nic nie pisze
#   kopia-zapasowa.ps1 -ZSekretami     dolacza .env, klucze SSH, ~\.claude\sekrety (domyslnie NIE)
#   kopia-zapasowa.ps1 -ZalozZadanie   zadanie MegaRuchaczKopia, codziennie o -Godzina (12:30)
#   kopia-zapasowa.ps1 -UsunZadanie
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
  [string]$Data = ""
)

$ErrorActionPreference = "Stop"
$NazwaZadania = "MegaRuchaczKopia"
$H = $env:USERPROFILE
# "Moj dysk" z o-kreskowanym budujemy ze znaku - plik zostaje czystym ASCII
if (-not $Cel) { $Cel = "G:\M" + [char]0x00F3 + "j dysk\<folder>\Backup" }
if (-not $PlikStanu) { $PlikStanu = "$H\.claude\mr\kopia-stan.txt" }
if (-not $PlikIndeksu) { $PlikIndeksu = "$H\.claude\mr\kopia-indeks.tsv" }
if (-not $Data) { $Data = Get-Date -Format "yyyy-MM-dd" }
$Cel = $Cel.TrimEnd('\')

# Kolejnosc ma znaczenie: najpierw pliki Claude'a (najwazniejsze), potem C:\dev.
# Lore (serwer MCP 'lore') chodzi z C:\dev\claude-worker\lore - jest w C:\dev.
# Projekt "projekt-d" lezy juz na Dysku Google - nie kopiujemy go drugi raz.
# ~\.agents: tam prowadzi dowiazanie ~\.claude\skills\orchestration.
if ($Zrodla.Count -eq 0) {
  $Zrodla = @("$H\.claude", "$H\.claude.json", "$H\.codex", "$H\.config\opencode",
              "$H\.agents", "$H\orca", "C:\dev")
}
$KorzenieClaude = @("$H\.claude", "$H\.claude.json", "$H\.codex", "$H\.config\opencode", "$H\.agents")

# Prog zer. Tekst w UTF-8/UTF-16/UTF-32 nigdy nie ma wiecej niz 3 bajty 0x00 pod
# rzad, a uszkodzenie z 2026-10-02 to bloki 3 332 - 31 986 bajtow zer albo caly plik
# z samych zer (najmniejszy mial 7 bajtow - dlatego osobno lapiemy "caly plik to zera").
# 64 daje duzy zapas w obie strony: zadnego falszywego alarmu na tekscie, a
# kazde widziane uszkodzenie jest 50x wieksze od progu.
$MinCiagZer = 64

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

      bool projekt = false, profil = false, pgPid = false, pgWer = false;
      foreach (var c in dzieci) {
        if ((c.Attr & 0x10) != 0) continue;
        string n = c.Name.ToLowerInvariant();
        if (n == "package.json" || n == "pyproject.toml" || n == "setup.py") projekt = true;
        else if (n == "local state") profil = true;
        else if (n == "postmaster.pid") pgPid = true;
        else if (n == "pg_version") pgWer = true;
      }
      if (profil) {
        pominiete.Add(new KopiaPominiety { Sciezka = kat, Powod = "profil przegladarki (plik 'Local State') - odtwarzalny, trzyma ciasteczka sesji", Katalog = true });
        continue;
      }
      if (pgPid && pgWer) {
        pominiete.Add(new KopiaPominiety { Sciezka = kat, Powod = "BLAD: Postgres dziala (postmaster.pid) - kopia plikow w biegu bylaby niespojna; zatrzymaj serwer albo zrob pg_dump", Katalog = true });
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
    if (hd.IsInvalid) { int e = Marshal.GetLastWin32Error(); tmp = null; return "BLAD:zalozenie pliku w kopii (blad Win32 " + e + ")"; }
    ws = new FileStream(hd, FileAccess.Write, 1 << 16);
    return null;
  }

  // Czyta zrodlo raz: sprawdza zera (jesli zera=true) i - gdy dst != null - pisze
  // do dst.kopia-tmp, a na koncu przemianowuje BEZ nadpisywania. dst == null:
  // samo sprawdzenie (tryb -Proba). Wynik: OK, ZERA:opis, W_UZYCIU, ISTNIEJE, BLAD:opis.
  public static string Kopiuj(string src, string dst, bool zera, int minCiag, long czas) {
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
        long ciag = 0, maxCiag = 0, gdzie = -1, poz = 0;
        bool same = true;
        int n;
        string blad;
        while ((n = rs.Read(buf, 0, buf.Length)) > 0) {
          if (zera) {
            for (int j = 0; j < n; j++) {
              if (buf[j] == 0) {
                ciag++;
                if (ciag > maxCiag) maxCiag = ciag;
                if (ciag == minCiag) gdzie = poz + j - minCiag + 1;
              } else { ciag = 0; same = false; }
            }
            if (maxCiag >= minCiag) break;
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
        if (zera && (maxCiag >= minCiag || (poz > 0 && same))) {
          string opis = (maxCiag >= minCiag)
            ? ("blok co najmniej " + maxCiag + " bajtow 0x00 od bajtu " + gdzie)
            : ("caly plik (" + poz + " B) to same bajty 0x00");
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
        return "OK";
      }
    } catch (IOException ex) {
      int e = Marshal.GetHRForException(ex) & 0xFFFF;
      if (e == 32 || e == 33) return "W_UZYCIU";
      return "BLAD:" + ex.Message;
    } catch (Exception ex) {
      return "BLAD:" + ex.Message;
    } finally {
      if (ws != null) ws.Dispose();
      if (tmp != null) DeleteFileW(L(tmp));
      if (!hs.IsClosed) hs.Dispose();
    }
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
Regula '^C:\\dev\\tools\\(git|pgsql|node|gh)$' "program przenosny (Git, PostgreSQL+pgAdmin, Node, gh) - odtwarzalny z instalatora" $true
Regula '\\node\\node\.exe$' "program przenosny (node.exe) - odtwarzalny" $false
Regula '\\minio\.exe$' "program przenosny (minio.exe) - odtwarzalny" $false
Regula '^C:\\dev\\projekt-e\\(bledy|nagrania)$' "nagrania diagnostyczne robota (ok. 680 MB zipow z bledow)" $true
Regula '^C:\\dev\\projekt-f\\_tools\\cache$' "pamiec podreczna narzedzia" $true

# ~\.claude i ~\.codex: katalogi techniczne. Zostaja: CLAUDE.md, wiedza, skills,
# agents, commands, mr, projects (transkrypty), file-history, settings, lore.db.
Regula "^$eH\\\.claude\\(shell-snapshots|statsig|todos|session-env|sessions|paste-cache|cache|ide|telemetry|debug|lore_models|backups)$" "katalog techniczny Claude Code (migawki powloki, sesje, pamiec podreczna, model Lore do pobrania, autokopie .claude.json)" $true
Regula "^$eH\\\.claude\\plugins\\(marketplaces|cache|\.trash)$" "wtyczki pobrane z marketplace - odtwarzalne" $true
Regula "^$eH\\\.claude\\lore\.db\.przed-[^\\]*$" "stara migawka lore.db sprzed migracji (184 MB) - aktualna lore.db jest w kopii" $false
Regula "^$eH\\\.claude\\mr\\kopia-indeks\.tsv(\.nowy)?$" "indeks samej kopii (zmienia sie co dzien)" $false
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
  $kand = "C:\dev\claude-worker\lore\.venv\Scripts\python.exe"
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
    return [KopiaIO]::Kopiuj($tmp, $dst, $false, $MinCiagZer, $czas)
  } catch {
    # blad jednej bazy nie przerywa calej kopii - idzie do listy bledow
    return "BLAD:kopia bazy SQLite: $($_.Exception.Message)"
  } finally {
    if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force }
  }
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

try {
  if (-not $Proba) {
    Zapisz-Stan ("stan=TRWA`r`nstart=" + $t0.ToString("yyyy-MM-dd HH:mm:ss") + "`r`ncel=$Cel`r`n" +
                 "# TRWA ze starym startem = kopia przerwana (wylaczony komputer, zabity proces)`r`n")
    $rodzic = Split-Path -Parent $Cel
    if (-not (Test-Path -LiteralPath $rodzic)) { throw "nie ma katalogu nad celem kopii: $rodzic (Dysk Google nie wystartowal?)" }
    if (-not (Test-Path -LiteralPath $Cel)) { New-Item -ItemType Directory -Force -Path $Cel | Out-Null }
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

  # kopiowanie (albo przy -Proba samo sprawdzenie zer)
  $skopiowane = 0; $bajty = [long]0; $wyzerowane = 0
  $ostatniMeldunek = Get-Date
  foreach ($k in $DoKopii) {
    $dst = if ($Proba) { $null } else { Do-Kopii $k.Sciezka $Przebieg }
    if ($Proba -and $k.Baza) { continue }
    if ($Proba -and -not $k.Zera) { continue }
    if ($k.Baza) { $wynik = Kopiuj-Sqlite $k.Sciezka $dst $k.Czas }
    else { $wynik = [KopiaIO]::Kopiuj($k.Sciezka, $dst, [bool]$k.Zera, $MinCiagZer, $k.Czas) }
    if ($wynik -eq "OK") {
      if (-not $Proba) {
        $skopiowane++; $bajty += $k.Rozmiar; $Indeks[$k.Sciezka] = $k.Klucz
        if ($k.Zera -and $k.Rozmiar -eq 0 -and $k.StaryRozmiar -gt 0) {
          $Uwagi.Add("plik skurczyl sie do 0 bajtow (poprzednio $($k.StaryRozmiar) B, ta wersja jest w kopii poprzedniego dnia): $($k.Sciezka)")
        }
      }
    } elseif ($wynik.StartsWith("ZERA:")) {
      $wyzerowane++
      $Alarmy.Add("ALARM WYZEROWANY PLIK - NIE skopiowany (zdrowa wersja zostaje w starszej kopii): $($k.Sciezka) - $($wynik.Substring(5))")
    } elseif ($wynik -eq "W_UZYCIU") {
      $WUzyciu.Add($k.Sciezka)
    } elseif ($wynik -eq "ZNIKNAL") {
      # np. agent sprzatnal swoj git worktree w trakcie kopii - to nie blad kopii
      $Uwagi.Add("zniknal w trakcie kopii (usuniety u zrodla): $($k.Sciezka)")
    } elseif ($wynik -eq "ISTNIEJE") {
      $Bledy.Add("w kopii juz jest $dst - nie nadpisuje")
    } else {
      $Bledy.Add("$($k.Sciezka) - $($wynik -replace '^BLAD:', '')")
    }
    if (-not $Proba -and ((Get-Date) - $ostatniMeldunek).TotalSeconds -ge 60) {
      $ostatniMeldunek = Get-Date
      Zapisz-Stan ("stan=TRWA`r`nstart=" + $t0.ToString("yyyy-MM-dd HH:mm:ss") + "`r`npostep=" + $skopiowane + " z " + $DoKopii.Count +
                   " plikow, " + (MB $bajty) + " z " + (MB $sumaDoKopii) + "`r`nmeldunek=" + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + "`r`ncel=$Przebieg`r`n")
    }
  }

  $czasTrwania = (Get-Date) - $t0
  $sekrety = @($Pominiete | Where-Object { $_.Sekret })

  if ($Proba) {
    Write-Output "PROBA - nic nie zostalo skopiowane ani zapisane"
    foreach ($a in $Alarmy) { Write-Output $a }
    foreach ($b in $Bledy) { Write-Output "BLAD  $b" }
    Write-Output ("rodzaj: $rodzaj  ->  $Cel\$nazwa")
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

  # dziennik - alarmy na POCZATKU wpisu
  $stan = if ($Alarmy.Count) { "ALARM" } elseif ($Bledy.Count) { "BLAD" } else { "OK" }
  $d = New-Object Text.StringBuilder
  [void]$d.AppendLine("=== " + $t0.ToString("yyyy-MM-dd HH:mm") + "  $rodzaj  stan=$stan  ->  $nazwa")
  foreach ($a in $Alarmy) { [void]$d.AppendLine($a) }
  [void]$d.AppendLine(("skopiowane: {0} plikow, {1}  (nowe {2}, zmienione {3}; bez zmian {4}); czas {5:hh\:mm\:ss}" -f $skopiowane, (MB $bajty), $nowe, $zmienione, $bezZmian, $czasTrwania))
  [void]$d.AppendLine(("pominiete: wyzerowane {0}, w uzyciu {1}, bledy {2}, sekrety {3}{4}, wykluczone katalogi/pliki {5}" -f $wyzerowane, $WUzyciu.Count, $Bledy.Count, $sekrety.Count, $(if ($ZSekretami) { " (z -ZSekretami)" } else { " (bez -ZSekretami)" }), ($Pominiete.Count - $sekrety.Count)))
  foreach ($b in $Bledy) { [void]$d.AppendLine("BLAD  $b") }
  foreach ($u in $WUzyciu) { [void]$d.AppendLine("W UZYCIU (pominiety, sprobuje jutro): $u") }
  foreach ($u in $Uwagi) { [void]$d.AppendLine("UWAGA $u") }
  [void]$d.AppendLine("")
  [IO.File]::AppendAllText("$Cel\dziennik.txt", $d.ToString(), (New-Object Text.UTF8Encoding($false)))

  $s = "stan=$stan`r`nostatnia=" + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + "`r`nrodzaj=$rodzaj`r`ncel=$Przebieg`r`n" +
       "plikow=$skopiowane`r`nmb=" + [Math]::Round($bajty / 1MB, 1) + "`r`nalarmy=$($Alarmy.Count)`r`nbledy=$($Bledy.Count)`r`nw_uzyciu=$($WUzyciu.Count)`r`n"
  # alarmy ida zawsze w calosci; lista bledow skrocona do 20 - ostrzezenie PRZED nia
  foreach ($a in $Alarmy) { $s += "$a`r`n" }
  if ($Bledy.Count -gt 20) { $s += "UWAGA lista bledow skrocona: ponizej 20 z $($Bledy.Count), pelna w $Cel\dziennik.txt`r`n" }
  foreach ($b in ($Bledy | Select-Object -First 20)) { $s += "BLAD  $b`r`n" }
  Zapisz-Stan $s

  Write-Output $d.ToString()
  if ($Alarmy.Count) { exit 2 }
  if ($Bledy.Count -or $script:BladStanu) { exit 1 }
  exit 0
} catch {
  $msg = $_.Exception.Message
  Write-Host "BLAD  kopia przerwana: $msg" -ForegroundColor Red
  if (-not $Proba) {
    Zapisz-Stan ("stan=BLAD`r`nostatnia=" + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") + "`r`nblad=$msg`r`n")
    try { [IO.File]::AppendAllText("$Cel\dziennik.txt", "=== " + $t0.ToString("yyyy-MM-dd HH:mm") + "  stan=BLAD  kopia przerwana: $msg`r`n`r`n") }
    catch { Write-Host "BLAD  nie da sie dopisac do dziennika: $($_.Exception.Message)" -ForegroundColor Red }
  }
  exit 1
} finally {
  $mutex.ReleaseMutex()
}
