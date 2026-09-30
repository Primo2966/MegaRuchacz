# narzedzia\koszt\baza-lore.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz BUDOWA
# w jego naglowku). Odczyt jednej liczby z bazy Lore (lore.db) przez winsqlite3.dll:
# kolejka wypowiedzi czekajacych na wylowienie faktow (Kolejka-Lore) i najdluzszy
# kawalek rozmowy (Najdluzszy-Kawalek). Skad wolane: tylko pelny raport
# (raport-pelny.ps1) - zapytania trwaja, wiec tryby zwiezle ich nie robia.
# Wczytuje go koszt-pamieci.ps1 kropka przy starcie - same definicje (typ C#
# kompiluje sie dopiero przy pierwszym pytaniu).

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

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["baza-lore"] = $true
