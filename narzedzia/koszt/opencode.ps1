# narzedzia\koszt\opencode.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz BUDOWA
# w jego naglowku). Rozmowy OpenCode z jego bazy SQLite (<dom>\.local\share\opencode\
# opencode.db), TYLKO DO ODCZYTU: kiedy byla ostatnia rozmowa (Ostatnia-Rozmowa-OpenCode -
# wola ja Narzedzia-Maszyny w pomiar.ps1), otwarcie okna rozmowy (Pomiar-Otwarcia-OpenCode)
# i zuzycie dzienne (Zuzycie-OpenCode) - te dwie wola Pomiar-Narzedzia (otwarcie.ps1),
# wynik ma ten sam ksztalt co u Codeksa. Wczytuje go koszt-pamieci.ps1 kropka przy
# starcie - same definicje (typ C# kompiluje sie dopiero przy pierwszym pytaniu).
#
# Baze czytamy przez winsqlite3.dll - siedzi w System32 kazdego Windowsa 10/11, tak samo
# jak w baza-lore.ps1: bez Pythona i bez zadnych zaleznosci. Otwarcie z flaga
# SQLITE_OPEN_READONLY i adresem "file:...?mode=ro" - nic w bazie nie zmieniamy, takze
# wtedy, gdy OpenCode akurat w nia pisze (tryb WAL).
#
# CO LEZY W BAZIE (sprawdzone na prawdziwej bazie 06.10.2026, OpenCode 1.18):
#   session - id, parent_id (podagent: rozmowa odpalona przez inna rozmowe), title,
#             directory, time_created / time_updated (ms od 1970). Kolumny tokens_* to
#             suma wiadomosci rozmowy RAZEM z kopiami: rozmowa rozwidlona (fork) dostaje
#             kopie wiadomosci rozmowy, z ktorej wyszla, i liczylaby je drugi raz - dlatego
#             ich nie bierzemy, tylko liczymy z wiadomosci.
#   message - data (JSON): role, time.created (ms), parentID (u odpowiedzi modelu: Twoja
#             wiadomosc, na ktora odpowiada), modelID i tokens {input, output, reasoning,
#             cache {read, write}}, w nowszych wersjach takze total. input NIE zawiera
#             odczytu z pamieci podrecznej (inaczej niz u Codeksa), wiec caly kontekst
#             wywolania = input + cache.read + cache.write.
#   part    - kawalki wiadomosci; Twoj tekst to part type "text" (synthetic albo ignored =
#             dokleil go sam OpenCode, nie Ty).
# Kopia w rozmowie rozwidlonej ma time.created sprzed powstania tej rozmowy - po tym ja
# poznajemy (w bazie biurowej 96 ze 175 odpowiedzi jednej rozmowy).
# Rozmowa zatytulowana "lore-fakty" to cykl wiedzy MegaRuchacza (lore\lore\facts.py,
# OPENCODE_ARGS) - ani Twoja rozmowa, ani Twoje zuzycie (koszt nauki liczy nauka.ps1).
# Cykl kasuje ja zaraz po przebiegu; gdyby zostala, pomijamy ja wszedzie.

$TytulCykluOpenCode = "lore-fakty"

$KodSqliteOdczyt = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class SqliteDoOdczytu {
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_open_v2", CallingConvention=CallingConvention.Cdecl)]
  static extern int Open(byte[] plik, out IntPtr db, int flagi, IntPtr vfs);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_busy_timeout", CallingConvention=CallingConvention.Cdecl)]
  static extern int Busy(IntPtr db, int ms);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_prepare_v2", CallingConvention=CallingConvention.Cdecl)]
  static extern int Prepare(IntPtr db, byte[] sql, int n, out IntPtr st, IntPtr ogon);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_step", CallingConvention=CallingConvention.Cdecl)]
  static extern int Step(IntPtr st);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_column_count", CallingConvention=CallingConvention.Cdecl)]
  static extern int Kolumny(IntPtr st);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_column_type", CallingConvention=CallingConvention.Cdecl)]
  static extern int Typ(IntPtr st, int i);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_column_text", CallingConvention=CallingConvention.Cdecl)]
  static extern IntPtr Tekst(IntPtr st, int i);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_column_bytes", CallingConvention=CallingConvention.Cdecl)]
  static extern int Bajty(IntPtr st, int i);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_errmsg", CallingConvention=CallingConvention.Cdecl)]
  static extern IntPtr Blad(IntPtr db);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_finalize", CallingConvention=CallingConvention.Cdecl)]
  static extern int Koniec(IntPtr st);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_close_v2", CallingConvention=CallingConvention.Cdecl)]
  static extern int Zamknij(IntPtr db);

  static string Komunikat(IntPtr db) {
    if (db == IntPtr.Zero) { return ""; }
    return Marshal.PtrToStringAnsi(Blad(db));
  }

  // Wszystkie wiersze zapytania jako napisy (NULL = null). 0x01 = SQLITE_OPEN_READONLY,
  // 0x40 = SQLITE_OPEN_URI (adres "file:...?mode=ro").
  public static List<string[]> Wiersze(string adres, string sql) {
    IntPtr db = IntPtr.Zero;
    IntPtr st = IntPtr.Zero;
    int rc = Open(System.Text.Encoding.UTF8.GetBytes(adres + "\0"), out db, 0x01 | 0x40, IntPtr.Zero);
    if (rc != 0) { string m = Komunikat(db); if (db != IntPtr.Zero) { Zamknij(db); } throw new Exception("otwarcie bazy, kod " + rc + " " + m); }
    try {
      Busy(db, 3000);
      rc = Prepare(db, System.Text.Encoding.UTF8.GetBytes(sql + "\0"), -1, out st, IntPtr.Zero);
      if (rc != 0) { throw new Exception("zapytanie, kod " + rc + " " + Komunikat(db)); }
      List<string[]> wynik = new List<string[]>();
      int n = Kolumny(st);
      while (true) {
        rc = Step(st);
        if (rc == 101) { break; }                         // 101 = SQLITE_DONE
        if (rc != 100) { throw new Exception("odczyt wiersza, kod " + rc + " " + Komunikat(db)); }
        string[] w = new string[n];
        for (int i = 0; i < n; i++) {
          if (Typ(st, i) == 5) { w[i] = null; continue; }   // 5 = SQLITE_NULL
          IntPtr p = Tekst(st, i);
          int b = Bajty(st, i);
          byte[] bufor = new byte[b];
          if (b > 0) { Marshal.Copy(p, bufor, 0, b); }
          w[i] = System.Text.Encoding.UTF8.GetString(bufor);
        }
        wynik.Add(w);
      }
      return wynik;
    } finally {
      if (st != IntPtr.Zero) { Koniec(st); }
      if (db != IntPtr.Zero) { Zamknij(db); }
    }
  }
}
'@

# Jedno zapytanie do bazy OpenCode. Ok = $false niesie Powod - wolajacy mowi go zamiast
# liczby, nigdy zero.
function Pytanie-OpenCode($baza, $sql) {
  if (-not (Test-Path -LiteralPath $baza -PathType Leaf)) {
    return [pscustomobject]@{ Ok = $false; Wiersze = @(); Powod = "nie ma bazy rozmow OpenCode ($baza)" }
  }
  try {
    if (-not ("SqliteDoOdczytu" -as [type])) { Add-Type -TypeDefinition $KodSqliteOdczyt -ErrorAction Stop }
    $adres = ([Uri]$baza).AbsoluteUri + "?mode=ro"
    $w = [SqliteDoOdczytu]::Wiersze($adres, $sql)
    return [pscustomobject]@{ Ok = $true; Wiersze = @($w); Powod = "" }
  } catch {
    $m = $_.Exception.Message
    if ($_.Exception.InnerException) { $m = $_.Exception.InnerException.Message }
    return [pscustomobject]@{ Ok = $false; Wiersze = @(); Powod = "nie umiem odczytac bazy rozmow OpenCode $baza ($m)" }
  }
}

function Czas-Z-Ms($ms) {
  return [DateTimeOffset]::FromUnixTimeMilliseconds([long]$ms).LocalDateTime
}

function Ms-Z-Czasu([datetime]$czas) {
  return ([DateTimeOffset]$czas).ToUnixTimeMilliseconds()
}

# Liczba z pola slownika JSON; brak pola albo smiec = 0.
function Pole-Liczba($d, $klucz) {
  if (-not ($d -is [System.Collections.IDictionary]) -or -not $d.ContainsKey($klucz) -or ($null -eq $d[$klucz])) { return [long]0 }
  try { return [long]$d[$klucz] } catch { return [long]0 }
}

# Kiedy byla Twoja ostatnia rozmowa w OpenCode (bez rozmow cyklu wiedzy). $null = baza
# pusta albo jej nie ma; nieczytelna baza to dodatkowo wpis w $n.Bledy.
function Ostatnia-Rozmowa-OpenCode($n) {
  if (-not $n.Baza -or -not (Test-Path -LiteralPath $n.Baza -PathType Leaf)) { return $null }
  $r = Pytanie-OpenCode $n.Baza "SELECT max(time_updated) FROM session WHERE title <> '$TytulCykluOpenCode'"
  if (-not $r.Ok) {
    if (@($n.Bledy) -notcontains $r.Powod) { $n.Bledy += $r.Powod }
    return $null
  }
  $v = $null
  if (@($r.Wiersze).Count -gt 0) { $v = $r.Wiersze[0][0] }
  if (-not ("$v" -match '^\d+$')) { return $null }
  return (Czas-Z-Ms $v)
}

# Rozmowy OpenCode zmienione w ostatnich $DniUzywania dniach z ich wiadomosciami - jeden
# odczyt dla otwarcia i zuzycia (Pomiar-Narzedzia wola obie). Wynik: Ok, Powod, Sesje
# (najnowsze pierwsze; kazda z odpowiedziami modelu), Bledy (wiadomosci,
# ktorych JSON-u nie dalo sie odczytac - liczymy dalej, ale nie po cichu).
function Rozmowy-OpenCode($n, $serializer) {
  $w = [pscustomobject]@{ Ok = $false; Powod = ""; Sesje = @(); Bledy = @() }
  $odMs = Ms-Z-Czasu ((Get-Date).AddDays(-$DniUzywania))
  $rs = Pytanie-OpenCode $n.Baza ("SELECT id, parent_id, title = '$TytulCykluOpenCode', directory, time_created, time_updated " +
                                  "FROM session WHERE time_updated >= $odMs ORDER BY time_updated DESC")
  if (-not $rs.Ok) { $w.Powod = $rs.Powod; return $w }
  $sesje = [ordered]@{}
  foreach ($r in @($rs.Wiersze)) {
    $sesje[$r[0]] = [pscustomobject]@{
      Id = $r[0]; Podagent = [bool]$r[1]; Cykl = ($r[2] -eq "1")
      Projekt = $(if ($r[3]) { [System.IO.Path]::GetFileName(("" + $r[3]).TrimEnd('\', '/')) } else { "" })
      Utworzona = [long]$r[4]; Zmieniona = [long]$r[5]; Kopie = 0
      Odpowiedzi = @()
    }
  }
  $w.Ok = $true
  if ($sesje.Count -eq 0) { return $w }
  $rm = Pytanie-OpenCode $n.Baza ("SELECT m.session_id, m.id, m.data FROM message m JOIN session s ON s.id = m.session_id " +
                                  "WHERE s.time_updated >= $odMs")
  if (-not $rm.Ok) { $w.Ok = $false; $w.Powod = $rm.Powod; return $w }
  foreach ($r in @($rm.Wiersze)) {
    $s = $sesje[$r[0]]
    if (-not $s) { continue }
    $o = $null
    try { $o = $serializer.DeserializeObject($r[2]) } catch { $o = $null }
    if (-not ($o -is [System.Collections.IDictionary])) {
      if ($w.Bledy.Count -lt 3) { $w.Bledy += "wiadomosc $($r[1]) nie jest poprawnym JSON-em" }
      continue
    }
    $kiedy = Pole-Liczba $o["time"] "created"
    # kopia z rozmowy, z ktorej ta wyszla (fork) - nie jej wlasna wiadomosc
    if (($kiedy -gt 0) -and ($kiedy -lt $s.Utworzona)) { $s.Kopie++; continue }
    $rola = "" + $o["role"]
    if ($rola -ne "assistant") { continue }
    $t = $o["tokens"]
    $s.Odpowiedzi += [pscustomobject]@{
      Kiedy = $kiedy; Rodzic = ("" + $o["parentID"]); Model = ("" + $o["modelID"])
      MaTokeny = ($t -is [System.Collections.IDictionary]); Tokeny = $t
    }
  }
  foreach ($s in $sesje.Values) { $s.Odpowiedzi = @($s.Odpowiedzi | Sort-Object Kiedy) }
  $w.Sesje = @($sesje.Values)
  return $w
}

# Caly kontekst wywolania i wszystkie tokeny jednej odpowiedzi modelu.
function Kontekst-OpenCode($t) {
  $c = $t["cache"]
  return ((Pole-Liczba $t "input") + (Pole-Liczba $c "read") + (Pole-Liczba $c "write"))
}
function Razem-OpenCode($t) {
  $razem = Pole-Liczba $t "total"
  if ($razem -gt 0) { return $razem }
  return ((Kontekst-OpenCode $t) + (Pole-Liczba $t "output") + (Pole-Liczba $t "reasoning"))
}

# Otwarcie okna rozmowy OpenCode - mediana z ostatnich rozmow, ten sam ksztalt co Sesje
# w Pomiar-Otwarcia. Pierwsza odpowiedz modelu z liczbami, minus Twoja wiadomosc, na
# ktora odpowiada (znaki / $ZnakiNaToken). Podagent, rozmowa rozwidlona (zaczyna sie od
# cudzego kontekstu) i rozmowa cyklu wiedzy nie sa otwarciem Twojego okna - pomijamy je
# i mowimy ile, gdy z tego powodu nie zostalo nic.
function Pomiar-Otwarcia-OpenCode($n, $rozmowy, $serializer) {
  $w = [pscustomobject]@{ Liczba = 0; Mediana = $null; Min = $null; Max = $null; Powod = ""; Pominiete = 0; Bledy = @(); Lista = @(); Narzedzie = $n.Nazwa }
  if (-not $rozmowy.Ok) { $w.Powod = $rozmowy.Powod; return $w }
  $w.Bledy = @($rozmowy.Bledy)
  $inne = 0
  $kandydaci = @()
  foreach ($s in @($rozmowy.Sesje)) {
    if ($s.Podagent -or $s.Cykl -or ($s.Kopie -gt 0)) { $inne++; continue }
    $p = @($s.Odpowiedzi | Where-Object { $_.MaTokeny -and ((Kontekst-OpenCode $_.Tokeny) -gt 0) }) | Select-Object -First 1
    if (-not $p) { $w.Pominiete++; continue }
    $kandydaci += [pscustomobject]@{ Sesja = $s; Odp = $p }
    if ($kandydaci.Count -ge $OtwarcieSesji) { break }
  }
  # Twoje wiadomosci, na ktore odpowiadaja te pierwsze odpowiedzi - jednym zapytaniem.
  # Id z bazy idzie do SQL-a tylko, gdy ma same litery, cyfry i podkreslenia.
  $znaki = @{}
  $idy = @($kandydaci | ForEach-Object { $_.Odp.Rodzic } | Where-Object { $_ -match '^[A-Za-z0-9_]+$' } | Select-Object -Unique)
  if ($idy.Count -gt 0) {
    $rp = Pytanie-OpenCode $n.Baza ("SELECT message_id, data FROM part WHERE message_id IN ('" + ($idy -join "','") + "')")
    if (-not $rp.Ok) { $w.Powod = $rp.Powod; return $w }
    foreach ($r in @($rp.Wiersze)) {
      $o = $null
      try { $o = $serializer.DeserializeObject($r[1]) } catch { continue }
      if (-not ($o -is [System.Collections.IDictionary]) -or (("" + $o["type"]) -ne "text")) { continue }
      if ($o["synthetic"] -eq $true -or $o["ignored"] -eq $true) { continue }
      if (-not $znaki.ContainsKey($r[0])) { $znaki[$r[0]] = 0 }
      $znaki[$r[0]] += ("" + $o["text"]).Length
    }
  }
  $lista = @()
  foreach ($k in $kandydaci) {
    $kontekst = Kontekst-OpenCode $k.Odp.Tokeny
    $zn = 0
    if ($znaki.ContainsKey($k.Odp.Rodzic)) { $zn = [int]$znaki[$k.Odp.Rodzic] }
    $bezW = $kontekst - [long](Tokeny $zn)
    $plik = $k.Sesja.Id
    if ($k.Sesja.Projekt) { $plik = "$($k.Sesja.Projekt)\$($k.Sesja.Id)" }
    $lista += [pscustomobject]@{
      Plik = $plik; Rola = ""
      Kiedy = (Czas-Z-Ms $k.Odp.Kiedy).ToString("yyyy-MM-ddTHH:mm:ss"); Model = $k.Odp.Model; Kontekst = $kontekst
      ZnakiWiadomosci = $zn; BezWiadomosci = [long][math]::Max(0, $bezW)
    }
  }
  Podsumuj-Otwarcia $w $lista
  if ($w.Liczba -eq 0) {
    $ile = @($rozmowy.Sesje).Count
    $w.Powod = "w bazie $($n.Baza) nie ma ani jednej Twojej rozmowy z ostatnich $DniUzywania dni z liczba tokenow ($ile $(if ($ile -eq 1) { 'rozmowa przejrzana' } else { 'rozmow przejrzanych' }))"
    if ($inne -gt 0) { $w.Powod += "; $inne to podagenci, rozmowy rozwidlone albo cykl wiedzy - tych nie licze do otwarcia" }
  }
  return $w
}

# Zuzycie tokenow w rozmowach z OpenCode: dzis i srednio dziennie z $DniZuzyciaCodeksa
# PELNYCH dni (ta sama miara, co u Codeksa i Claude Code w oknie). Kazda odpowiedz modelu
# raz: tokens.total (albo suma input + cache + output + reasoning, gdy total brak), dzien
# wedlug lokalnej daty time.created. Kopie w rozmowach rozwidlonych i rozmowy cyklu wiedzy
# pomijamy; podagentow liczymy - to Twoje tokeny. Bufor = cache.read.
function Zuzycie-OpenCode($n, $rozmowy) {
  $dzis = [datetime]::Today
  $od = $dzis.AddDays(-$DniZuzyciaCodeksa)
  $z = [pscustomobject]@{
    Dzis = $null; Srednia = $null; Dni = $DniZuzyciaCodeksa; DniZRozmowami = 0
    Od = $od.ToString("yyyy-MM-dd"); Do = $dzis.AddDays(-1).ToString("yyyy-MM-dd")
    Pliki = 0; Zdarzenia = 0; Bufor = $null; Powod = ""; Bledy = @()
  }
  if (-not $rozmowy.Ok) { $z.Powod = $rozmowy.Powod; return $z }
  $z.Bledy = @($rozmowy.Bledy)
  $odMs = Ms-Z-Czasu $od
  $sesje = @($rozmowy.Sesje | Where-Object { (-not $_.Cykl) -and ($_.Zmieniona -ge $odMs) })
  $z.Pliki = $sesje.Count
  # Brak rozmow z tych dni = naprawde nic (baza przejrzana), nie "nie wiem".
  $z.Dzis = [long]0; $z.Srednia = [long]0
  if ($sesje.Count -eq 0) { return $z }
  $dni = @{}; $suma = [long]0; $bufor = [long]0; $odpowiedzi = 0
  foreach ($s in $sesje) {
    foreach ($o in @($s.Odpowiedzi)) {
      $odpowiedzi++
      if (-not $o.MaTokeny) { continue }
      if ($o.Kiedy -lt $odMs) { continue }
      $z.Zdarzenia++
      $dzien = (Czas-Z-Ms $o.Kiedy).Date
      $k = $dzien.ToString("yyyy-MM-dd")
      $ile = Razem-OpenCode $o.Tokeny
      if (-not $dni.ContainsKey($k)) { $dni[$k] = [long]0 }
      $dni[$k] += $ile
      if ($dzien -lt $dzis) { $suma += $ile; $bufor += (Pole-Liczba $o.Tokeny["cache"] "read") }
    }
  }
  # Odpowiedzi modelu sa, a zadna nie niesie liczb - OpenCode zmienil zapis i tego nie
  # wolno przemilczec jako "nic".
  if (($odpowiedzi -gt 0) -and (@($sesje | ForEach-Object { $_.Odpowiedzi } | Where-Object { $_.MaTokeny }).Count -eq 0)) {
    $z.Dzis = $null; $z.Srednia = $null
    $z.Powod = "w $($sesje.Count) rozmowach OpenCode z ostatnich $DniZuzyciaCodeksa dni zadna odpowiedz modelu nie ma pola tokens - nie umiem policzyc zuzycia"
    return $z
  }
  $kDzis = $dzis.ToString("yyyy-MM-dd")
  if ($dni.ContainsKey($kDzis)) { $z.Dzis = [long]$dni[$kDzis] }
  $z.DniZRozmowami = @($dni.Keys | Where-Object { ($_ -ne $kDzis) -and ($dni[$_] -gt 0) }).Count
  $z.Srednia = [long][math]::Round($suma / [double]$DniZuzyciaCodeksa)
  $z.Bufor = [long][math]::Round($bufor / [double]$DniZuzyciaCodeksa)
  return $z
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["opencode"] = $true
