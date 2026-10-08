# Sprawdzenie migania okna nadzorcy przy przelaczaniu zakladek (2026-10-08). Uzytkownik: okno
# "dziwnie mruga przy kazdym przelaczaniu zakladek, nawet gdy dane sa juz wczytane".
#   powershell -ExecutionPolicy Bypass -File zasobnik\test-okno-mruganie.ps1 [-Zasobnik <kat zasobnik>] [-Zrodlo <repo>] [-Dom <kat domowy>] [-Limit <s>] [-BezSabotazy]
# Kopia CALEGO okna (nadzorca.ps1 + stan-nadzorcy.ps1 + nadzorca\) w katalogu tymczasowym: wlasny
# zamek, poza ekranem (-5000, 0), bez paska zadan, bez aktywacji (ShowWithoutActivation,
# WS_EX_NOACTIVATE, SW_SHOWNA, bez SetForegroundWindow), klawiatura wylaczona, bez ikony i bez
# dozoru, -Proba, bezpieczniki cyklu wiedzy / skilli / tla / aktualizacji w kopii stanu. Dane
# prawdziwe z -Dom (tylko odczyt, jak test-p7.ps1) - bez nich zakladki maja za malo kontrolek,
# zeby usterka sie pokazala. Proces kopii bez konsoli (CreateNoWindow), po limicie zabijany
# z dziecmi; na koncu test sprawdza, ze zadna kopia nie zostala w procesach.
#
# Co mierzy (scenariusz w kopii, po wczytaniu danych i jednym obejsciu wszystkich zakladek):
#  - przelaczenie tam i z powrotem przy swiezych danych: czas klikniecia, nowe / zwolnione
#    kontrolki, przebudowy zakladki, nowe kroki liczenia, zmiana polozenia kontrolek;
#  - RYSOWANIE W TRAKCIE: komunikaty rysowania wyslane SYNCHRONICZNIE (WM_ERASEBKGND, WM_PAINT,
#    WM_NCPAINT) do widocznych okien, gdy kod jeszcze zmienia zakladke - to trafia na ekran przed
#    koncem zmiany (hak WH_CALLWNDPROC, metoda z P50); liczone w kliknieciu i w kazdej przebudowie,
#    w progu tylko okna TRESCI zakladek (dlaczego - w TZmiana);
#  - ODMALOWANIA PO: ile WM_PAINT z kolejki przyszlo po zmianie (osobne odmalowanie = zakladka
#    dorysowuje sie kawalkami);
#  - przebudowe widocznego Przegladu po cichym odswiezeniu (te same dane z dozoru), wejscie do
#    Szczegolow po nim i wejscia do zakladek z danymi starszymi niz -Minut (ciche odswiezenie);
#  - rozwiniecie i zwiniecie grupy skilli (P50), bezczynnosc (zadnego malowania w kolko)
#    i przewijanie Szczegolow kolkiem myszy.
# PULAPKA pomiaru: okno poza ekranem ma pusty obszar przyciecia (GetClipBox), wiec windows czesc
# wymazan pomija - liczby sa tu NIZSZE niz na ekranie (Warstwy: 19 tu, 37 na ukrytym pulpicie
# w (0, 0)). Prog dotyczy wiec liczby rysowan, a nie pikseli; usterka i tak wychodzi wyraznie.
# Proby negatywne: ten sam scenariusz na kopiach z sabotazem przywracajacym stare zachowanie -
# wlasciwa proba MUSI pasc (kotwica sprawdzana przed podmiana; brak kotwicy = porazka testu).
# Stary kod (sprzed poprawki) da sie sprawdzic tak samo: -Zasobnik <kopia starego zasobnik> -BezSabotazy.
param(
  [string]$Zasobnik = $PSScriptRoot,
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [string]$Dom = $HOME,
  [int]$Limit = 360,
  [switch]$BezSabotazy
)
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { Write-Warning "konsola bez UTF-8: $($_.Exception.Message)" }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("test-okno-mrug-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$utf8bom = New-Object System.Text.UTF8Encoding($true)

$script:wyniki = @()
function Wynik($nazwa, $ok, $opis) {
  $script:wyniki += [pscustomobject]@{ Test = $nazwa; OK = [bool]$ok; Opis = $opis }
  $z = "NIE"; if ($ok) { $z = "TAK" }
  Write-Host ("[{0}] {1} - {2}" -f $z, $nazwa, $opis)
}

# --- PROGI (z uzasadnieniem; liczby z pomiaru 08.10.2026 na prawdziwych danych, okno 1256 x 1352) ---
# Czas klikniecia przelaczajacego zakladke bez przebudowy: przed poprawka Przeglad -> Szczegoly
# 10,7-11,4 s, Skille -> Przeglad 0,4-0,5 s; po 0,16-0,2 s. 1 s = piec razy zmierzony czas po
# poprawce (zapas na wolniejszy komputer) i ponad dziesiec razy mniej niz usterka.
$PROG_KLIK_MS = 1000
# Rysowanie TRESCI ZAKLADKI w trakcie zmiany (synchroniczne, na widocznych oknach wewnatrz paneli
# zakladek): przed poprawka 19 przy wejsciu do Warstw, 32 do Szczegolow, 404-2243 przy przebudowie
# widocznego Przegladu; po 0 (zostaje przycisk przelacznika i zasloniete tlo formularza - patrz
# TZmiana w scenariuszu). 2 = pojedyncze wymazanie (np. paska przewijania) nie jest miganiem;
# najmniejsza zmierzona usterka jest prawie dziesiec razy wieksza.
$PROG_RYSOWANIE_W_TRAKCIE = 2
# Osobne odmalowania po zmianie (WM_PAINT z kolejki): przed poprawka 35-116 (karta po karcie),
# po 5 (panel z buforem, naglowek, przyciski). 10 = dwa razy zmierzone, trzy razy mniej niz usterka.
$PROG_ODMALOWAN_PO = 10
# Przewiniecie Szczegolow o jeden zabek kolka (z odmalowaniem): po poprawce 36-42 ms. Panel z buforem
# maluje przy przewijaniu cala widoczna czesc - 300 ms to granica, za ktora przewijanie zaczyna sie
# ciac (ponizej czterech klatek na sekunde), siedem razy zmierzony czas.
$PROG_PRZEWINIECIE_MS = 300

# ---------------------------------------------------------------- scenariusz w kopii okna
$scenariusz = @'
# Scenariusz testu migania - wczytany kropka w miejsce 'if ($Pokaz) { Pokaz-Okno }' w kopii okna.
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows.Forms;
namespace MrugTest {
  public class OknoTestowe : Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams { get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x00000080; return cp; } }
  }
  public static class Api { [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l); }
  // WM_PAINT z kolejki (odmalowania po zmianie)
  public class Licznik : IMessageFilter {
    public int Paint; public HashSet<IntPtr> Okna = new HashSet<IntPtr>();
    public bool PreFilterMessage(ref Message m) { if (m.Msg == 0x000F) { Paint++; Okna.Add(m.HWnd); } return false; }
    public void Zeruj() { Paint = 0; Okna.Clear(); }
  }
  // Rysowanie WYSLANE (synchroniczne) do widocznych okien, gdy W = true
  public class Hak {
    delegate IntPtr Proc(int code, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, Proc p, IntPtr mod, uint thr);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int code, IntPtr w, IntPtr l);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] struct CWP { public IntPtr lParam, wParam; public uint message; public IntPtr hwnd; }
    IntPtr h; Proc p;
    public bool W; public int Rysowan; public HashSet<IntPtr> Okna = new HashSet<IntPtr>(); public Dictionary<IntPtr, string> Typy = new Dictionary<IntPtr, string>();
    public Hak() { p = new Proc(Obsluz); h = SetWindowsHookEx(4, p, IntPtr.Zero, GetCurrentThreadId()); }
    public void Zeruj() { Rysowan = 0; Okna.Clear(); Typy.Clear(); }
    public void Zdejmij() { UnhookWindowsHookEx(h); }
    IntPtr Obsluz(int code, IntPtr w, IntPtr l) {
      if (code >= 0 && W) {
        var c = (CWP)Marshal.PtrToStructure(l, typeof(CWP));
        if ((c.message == 0x0F || c.message == 0x14 || c.message == 0x85) && IsWindowVisible(c.hwnd)) { Rysowan++; Okna.Add(c.hwnd); string z = c.message == 0x0F ? "P" : (c.message == 0x14 ? "E" : "N"); string b; Typy[c.hwnd] = (Typy.TryGetValue(c.hwnd, out b) ? b : "") + z; }
      }
      return CallNextHookEx(h, code, w, l);
    }
  }
}
"@
$script:TWynik = $env:MRUG_WYNIK
$script:TLog = New-Object System.Collections.Generic.List[string]
$script:TSw = [System.Diagnostics.Stopwatch]::StartNew()
function TNotuj($t) {
  $l = ("{0,7} ms  {1}" -f $script:TSw.ElapsedMilliseconds, $t)
  $script:TLog.Add($l)
  [System.IO.File]::AppendAllText($script:TWynik + ".log", $l + "`r`n")
}
$script:TLicz = New-Object MrugTest.Licznik
[System.Windows.Forms.Application]::AddMessageFilter($script:TLicz)
$script:THak = New-Object MrugTest.Hak
# podsluch: przebudowy zakladek (z rysowaniem w trakcie) i nowe kroki liczenia
$script:TRender = @{}; $script:TKroki = 0
$script:TOrygRender = ${function:Wyrenderuj-Widok}
function Wyrenderuj-Widok([string]$w) {
  $script:TRender[$w] = 1 + [int]$script:TRender[$w]
  $bylo = $script:THak.W; $script:THak.W = $true
  try { & $script:TOrygRender $w } finally { $script:THak.W = $bylo }
}
$script:TOrygNowy = ${function:Nowy-Krok}
function Nowy-Krok([string]$id, [string]$kawalek, [string]$napis, [string]$zadanie, [bool]$zSiecia, [int]$limit) {
  $script:TKroki++; TNotuj "krok $id"
  return (& $script:TOrygNowy $id $kawalek $napis $zadanie $zSiecia $limit)
}
function TPotomki($c) { $l = New-Object System.Collections.Generic.List[object]; foreach ($d in $c.Controls) { $l.Add($d); foreach ($x in (TPotomki $d)) { $l.Add($x) } }; return ,$l }
function TPompuj([int]$ms) { $k = [System.Diagnostics.Stopwatch]::StartNew(); while ($k.ElapsedMilliseconds -lt $ms) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 5 } }
function TSpokoj { return (-not $script:Ladowanie) -and ($script:KrokiAktywne.Count -eq 0) -and ($script:KolejkaKrokow.Count -eq 0) -and -not ($script:Zuzycie -and ($script:Zuzycie.Stan -eq "licze")) }
function TPrzycisk([string]$w) { switch ($w) { "przeglad" { $script:BPrzeglad } "szczegoly" { $script:BSzczegoly } "warstwy" { $script:BWarstwy } "skille" { $script:BSkille } } }
function TPanel([string]$w) { switch ($w) { "przeglad" { $script:WidokPrzeglad } "szczegoly" { $script:WidokSzczegoly } "warstwy" { $script:WidokWarstwy } "skille" { $script:WidokSkille } } }
$script:TPomiary = New-Object System.Collections.Generic.List[object]
$script:TInne = New-Object System.Collections.Generic.List[object]

# Jedna zmiana (klikniecie przelacznika albo $akcja) i wszystko, co po niej widac.
function TZmiana([string]$etap, [string]$cel, [scriptblock]$akcja = $null, [int]$poMs = 700, [bool]$doSpokoju = $false) {
  TPompuj 200
  $przed = New-Object 'System.Collections.Generic.HashSet[object]'
  foreach ($c in (TPotomki $script:Okno)) { [void]$przed.Add($c) }
  $granice = @{}; foreach ($c in (TPotomki (TPanel $cel))) { $granice[$c] = $c.Bounds }
  $z = $script:Widok
  $script:TRender = @{}; $script:TKroki = 0
  $script:THak.Zeruj(); $script:TLicz.Zeruj()
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $script:THak.W = $true
  try { if ($akcja) { & $akcja } else { (TPrzycisk $cel).PerformClick() } } finally { $script:THak.W = $false }
  $tKlik = $sw.ElapsedMilliseconds
  # Rysowanie TRESCI ZAKLADEK w trakcie: okna wewnatrz paneli zakladek (z nimi samymi). Poza
  # nimi zostaje wcisniety przycisk przelacznika (zmienia kolor - ma sie odmalowac) i tlo
  # formularza: w calosci zasloniete naglowkiem, zakladka i paskiem - zmierzone 08.10.2026 na
  # ukrytym pulpicie w (0, 0): kazde takie wymazanie mialo pusty obszar przyciecia, 0 pikseli.
  $zakl = 0
  foreach ($h in @($script:THak.Okna)) {
    $c = [System.Windows.Forms.Control]::FromHandle($h)
    $q = $c; $wZakl = $false
    while ($q) { if (@($script:WidokPrzeglad, $script:WidokSzczegoly, $script:WidokWarstwy, $script:WidokSkille) -contains $q) { $wZakl = $true; break }; $q = $q.Parent }
    if ($wZakl -or -not $c) { $zakl += ("" + $script:THak.Typy[$h]).Length }
  }
  # ktore okna rysowaly sie w trakcie (rodzaje: P = WM_PAINT, E = wymazanie tla, N = ramka;
  # typ<rodzic 'tekst') - do opisu, gdy proba padnie
  $opisOkien = ((@($script:THak.Okna) | Select-Object -First 12 | ForEach-Object {
    $c = [System.Windows.Forms.Control]::FromHandle($_)
    if ($c) { $tx = "" + $c.Text; "$($script:THak.Typy[$_]) $($c.GetType().Name)<$(if ($c.Parent) { $c.Parent.GetType().Name })'$($tx.Substring(0, [math]::Min(18, $tx.Length)))'" } else { "$($script:THak.Typy[$_]) obce okno" }
  }) -join "; ")
  $script:TLicz.Zeruj()
  TPompuj $poMs
  if ($doSpokoju) { $k = [System.Diagnostics.Stopwatch]::StartNew(); while (-not (TSpokoj) -and ($k.ElapsedMilliseconds -lt 150000)) { TPompuj 100 }; TPompuj 800 }
  $po = TPotomki $script:Okno; $nowe = 0; foreach ($c in $po) { if (-not $przed.Contains($c)) { $nowe++ } }
  $zwol = 0; foreach ($c in $przed) { if ($c.IsDisposed) { $zwol++ } }
  $zmGr = 0; foreach ($c in @($granice.Keys)) { if (-not $c.IsDisposed -and ($c.Bounds -ne $granice[$c])) { $zmGr++ } }
  $m = [pscustomobject]@{ Etap = $etap; Z = $z; Do = $cel; Widok = $script:Widok; KlikMs = $tKlik
    RysowanieWTrakcie = $script:THak.Rysowan; RysowanieZakladki = $zakl; OkienRysowanychWTrakcie = $script:THak.Okna.Count
    OdmalowanPo = $script:TLicz.Paint; OkienOdmalowanych = $script:TLicz.Okna.Count
    Nowych = $nowe; Zwolnionych = $zwol; ZmienioneGranice = $zmGr; Kontrolek = $po.Count
    Przebudowy = [int](($script:TRender.Values | Measure-Object -Sum).Sum); PrzebudowyOpis = (($script:TRender.Keys | ForEach-Object { "$_=$($script:TRender[$_])" }) -join ",")
    NowychKrokow = $script:TKroki; OknaWTrakcie = $opisOkien; Widoczny = [bool](TPanel $cel).Visible }
  $script:TPomiary.Add($m)
  TNotuj ("POMIAR " + ($m | ConvertTo-Json -Compress))
}

function TBezczynnosc([string]$w) {
  (TPrzycisk $w).PerformClick(); TPompuj 1000
  $script:TLicz.Zeruj(); TPompuj 2000
  $m = [pscustomobject]@{ Rodzaj = "bezczynnosc"; Widok = $w; OdmalowanPo = $script:TLicz.Paint }
  $script:TInne.Add($m); TNotuj ("BEZCZYNNOSC " + ($m | ConvertTo-Json -Compress))
}

function TPrzewin([string]$w, [int]$ile = 6) {
  (TPrzycisk $w).PerformClick(); TPompuj 1000
  $panel = TPanel $w
  $panel.AutoScrollPosition = New-Object System.Drawing.Point(0, 0); TPompuj 300
  $s = $panel.PointToScreen((New-Object System.Drawing.Point(([int]($panel.ClientSize.Width / 2)), ([int]($panel.ClientSize.Height / 2)))))
  $l = [IntPtr](($s.Y -shl 16) -bor ($s.X -band 0xFFFF))
  $czasy = @()
  for ($i = 0; $i -lt $ile; $i++) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    [void][MrugTest.Api]::SendMessage($panel.Handle, 0x020A, [IntPtr]([int](-120 -shl 16)), $l)
    $panel.Update()
    TPompuj 0
    $czasy += $sw.ElapsedMilliseconds
  }
  $m = [pscustomobject]@{ Rodzaj = "przewijanie"; Widok = $w; Czasy = ($czasy -join ","); Max = [int](($czasy | Measure-Object -Maximum).Maximum); Pozycja = (-$panel.AutoScrollPosition.Y) }
  $script:TInne.Add($m); TNotuj ("PRZEWIJANIE " + ($m | ConvertTo-Json -Compress))
  $panel.AutoScrollPosition = New-Object System.Drawing.Point(0, 0); TPompuj 300
}

function TPostarz([int]$minut) {
  foreach ($id in @($script:StanKawalkow.Keys)) { $k = $script:StanKawalkow[$id]; if ($k.Czas) { $k.Czas = $k.Czas.AddMinutes(-$minut) } }
  if ($script:DaneCzas) { $script:DaneCzas = $script:DaneCzas.AddMinutes(-$minut) }
}

function TKoniec {
  $script:TZegar.Stop()
  try {
    $o = [pscustomobject]@{ Pomiary = $script:TPomiary.ToArray(); Inne = $script:TInne.ToArray(); Log = $script:TLog.ToArray()
      Wywrotki = [string[]]@($script:NadzWywrotki | ForEach-Object { "$_" }) }
    [System.IO.File]::WriteAllText($script:TWynik, ($o | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
  } catch { TNotuj ("ZAPIS WYNIKU: " + $_.Exception.Message) }
  try { $script:THak.Zdejmij() } catch { TNotuj ("zdjecie haka: " + $_.Exception.Message) }
  try { if ($script:Okno) { $script:Okno.Close() } } catch { TNotuj ("zamkniecie okna: " + $_.Exception.Message) }
  $script:Ikona.Visible = $false
  [System.Windows.Forms.Application]::Exit()
}

$script:TFaza = "otwarcie"; $script:TFazaOd = 0; $script:TSpokojOd = $null; $script:TRozgrzewka = $null
Pokaz-Okno
TNotuj ("okno {0}, aktywne: {1}" -f $script:Okno.Bounds, ([System.Windows.Forms.Form]::ActiveForm -eq $script:Okno))
$script:TZegar = New-Object System.Windows.Forms.Timer
$script:TZegar.Interval = 200
$script:TZajety = $false
$script:TZegar.Add_Tick({
  if ($script:TZajety) { return }
  $script:TZajety = $true
  try {
    $t = $script:TSw.ElapsedMilliseconds
    if (($t - $script:TFazaOd) -gt 200000) { TNotuj "LIMIT fazy $($script:TFaza)"; TKoniec; return }
    $widoki = @("przeglad", "szczegoly", "warstwy"); if ($script:BSkille.Visible) { $widoki += "skille" }
    $kolejka = @($widoki | Select-Object -Skip 1) + @("przeglad")
    switch ($script:TFaza) {
      "otwarcie" {
        if (-not (TSpokoj)) { $script:TSpokojOd = $null; return }
        if ($null -eq $script:TSpokojOd) { $script:TSpokojOd = $t }
        if (($t - $script:TSpokojOd) -lt 1500) { return }
        $script:TSpokojOd = $null
        if ($null -eq $script:TRozgrzewka) { $script:TRozgrzewka = $kolejka }
        $nast = $script:TRozgrzewka[0]
        $script:TRozgrzewka = @($script:TRozgrzewka | Select-Object -Skip 1)
        TNotuj "rozgrzewka: $nast"
        (TPrzycisk $nast).PerformClick()
        if ($script:TRozgrzewka.Count -eq 0) { $script:TFaza = "pomiar"; $script:TFazaOd = $t }
      }
      "pomiar" {
        if (-not (TSpokoj)) { return }
        $script:TZegar.Stop()
        foreach ($r in 1..2) { foreach ($w in $kolejka) { TZmiana "swieze-$r" $w } }
        foreach ($w in @("przeglad", "szczegoly", "warstwy")) { TBezczynnosc $w }
        TPrzewin "szczegoly"
        # rozwiniecie i zwiniecie grupy skilli (P50) w zakladce z podwojnym buforem
        if ($script:BSkille.Visible) {
          (TPrzycisk "skille").PerformClick(); TPompuj 500
          # najwieksze zrodlo skilli (jak w pomiarze P50), a bez danych - pierwsza grupa z listy
          $gid = $null
          try { $gid = (@($script:DaneSkilli.Dane.zrodla | Where-Object { $script:GrupyListy.ContainsKey($_.id) }) | Sort-Object { @($_.skille).Count } -Descending | Select-Object -First 1).id } catch { TNotuj "wybor grupy skilli: $($_.Exception.Message)" }
          if (-not $gid) { $gid = @($script:GrupyListy.Keys)[0] }
          if ($gid -and $script:GrupySkilli[$gid]) { Przelacz-Grupe $gid; TPompuj 300 }
          foreach ($krok in @("rozwin", "zwin")) {
            TZmiana "grupa-skilli-$krok" "skille" { Przelacz-Grupe $gid }
            # (liczone petla: @() na liscie wierszy w literale obiektu wywraca PS 5.1 - "Niezgodne typy argumentow")
            $wid = 0; $wsz = 0
            foreach ($wr in $script:GrupyListy[$gid].Wiersze) { $wsz++; if (-not $wr.IsDisposed -and $wr.Visible) { $wid++ } }
            $mg = [pscustomobject]@{ Rodzaj = "grupa-skilli"; Krok = $krok; Grupa = "$gid"; Widocznych = $wid; Wierszy = $wsz }
            $script:TInne.Add($mg)
            TNotuj "GRUPA $gid $krok - widocznych wierszy $wid"
          }
        }
        (TPrzycisk "przeglad").PerformClick(); TPompuj 500
        # dozor przynosi dane, gdy patrzysz na Przeglad (Po-Kroku "dane" jak w Dozor-Po-Danych)
        TZmiana "odswiezenie-na-oczach" "przeglad" { Po-Kroku "dane" }
        # Szczegoly sa po tym do przebudowy - wejscie do nich
        TZmiana "wejscie-po-odswiezeniu" "szczegoly"
        TZmiana "wejscie-po-odswiezeniu" "przeglad"
        # dane starsze niz -Minut: wejscie w zakladke = ciche odswiezenie i przebudowa
        TPostarz 16
        foreach ($w in $kolejka) { TZmiana "postarzone" $w $null 700 $true }
        TKoniec
      }
    }
  } catch {
    TNotuj ("WYWROTKA SCENARIUSZA: " + $_.Exception.Message + " @ " + $_.InvocationInfo.PositionMessage)
    TKoniec
  } finally { $script:TZajety = $false }
})
$script:TZegar.Start()
'@
$plikScen = Join-Path $tmp "scenariusz.ps1"
[System.IO.File]::WriteAllText($plikScen, $scenariusz, $utf8bom)
$bledyScen = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($plikScen, [ref]$null, [ref]$bledyScen)
if (@($bledyScen).Count -gt 0) { Wynik "scenariusz testu sie parsuje" $false (($bledyScen | ForEach-Object { $_.ToString() }) -join " | "); exit 1 }

# ---------------------------------------------------------------- kopia okna
$BEZPIECZNIKI = @'

# ===== BEZPIECZNIKI TESTU MIGANIA (kopia testowa, nie produkcja) =====
function Ruszaj-Cykl { Write-Host "[TEST] Ruszaj-Cykl ZABLOKOWANY"; return $false }
function Czy-Ruszac-Cykl { return [pscustomobject]@{ Ruszac = $false; Powod = "test migania" } }
function Odpal-W-Tle([string]$skrypt, [string]$argumenty) { Write-Host "[TEST] Odpal-W-Tle ZABLOKOWANY: $skrypt $argumenty"; return $false }
function Odpal-Skille([string]$argumenty) { Write-Host "[TEST] Odpal-Skille ZABLOKOWANY"; return $true }
function Ruszaj-Skille { return $true }
function Operacja-Na-Skillach { return "test migania - zablokowane" }
function Aktualizuj { return [pscustomobject]@{ Ok = $false; Proba = $true; Powod = "test migania - zablokowane"; Pid = $null } }
'@

# Kotwice wspolne dla kazdej kopii (kazda MUSI wystapic dokladnie raz w plikach okna).
function Zamiany-Kopii([string]$stanKopia, [string]$zamek) {
  return [ordered]@{
    '. (Join-Path $PSScriptRoot "stan-nadzorcy.ps1")' = ". '$stanKopia'"
    '"Local\MegaRuchacz-Nadzorca"' = "`"Local\MegaRuchacz-Nadzorca-$zamek`""
    '$script:Zegar.Start()' = '# dozor wylaczony w tescie migania'
    '[MegaRuchacz.Pulpit]::SetForegroundWindow($formularz.Handle) | Out-Null' = '# bez kradziezy fokusu w tescie migania'
    '$SW_POKAZ = 5' = '$SW_POKAZ = 8   # test migania: SW_SHOWNA, bez aktywacji'
    '$script:Ikona.Visible = $true' = '$script:Ikona.Visible = $false   # test migania: bez ikony w zasobniku'
    '$f = New-Object System.Windows.Forms.Form' = '$f = New-Object MrugTest.OknoTestowe   # test migania: bez aktywacji, bez paska zadan'
    '$script:Okno = $f' = ('$f.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual; $f.Location = New-Object System.Drawing.Point(-5000, 0); $f.ShowInTaskbar = $false; $f.KeyPreview = $true; $f.Add_KeyDown({ param($s, $e) $e.SuppressKeyPress = $true; $e.Handled = $true })' + "`r`n  " + '$script:Okno = $f')
    'if ($Pokaz) { Pokaz-Okno }' = ". '$plikScen'"
  }
}

# Sklada kopie; $sabotaz = lista @{ Plik; Kotwica; Zamiana } albo $null. Zwraca sciezke albo powod porazki.
function Przygotuj-Kopie([string]$nazwa, $sabotaz) {
  $kat = Join-Path $tmp $nazwa
  New-Item -ItemType Directory -Force -Path $kat | Out-Null
  Copy-Item -LiteralPath (Join-Path $Zasobnik "nadzorca.ps1") -Destination (Join-Path $kat "nadzorca-test.ps1")
  Copy-Item -LiteralPath (Join-Path $Zasobnik "stan-nadzorcy.ps1") -Destination (Join-Path $kat "stan-nadzorcy.ps1")
  Copy-Item -LiteralPath (Join-Path $Zasobnik "nadzorca") -Destination (Join-Path $kat "nadzorca") -Recurse
  $stanKopia = Join-Path $kat "stan-nadzorcy.ps1"
  [System.IO.File]::WriteAllText($stanKopia, ([System.IO.File]::ReadAllText($stanKopia) + $BEZPIECZNIKI), $utf8bom)
  $pliki = @((Join-Path $kat "nadzorca-test.ps1")) + @(Get-ChildItem -LiteralPath (Join-Path $kat "nadzorca") -Filter *.ps1 | Where-Object { $_.Name -notlike "stan-*" } | ForEach-Object { $_.FullName })
  $tresc = @{}; foreach ($p in $pliki) { $tresc[$p] = [System.IO.File]::ReadAllText($p) }
  $zamiany = Zamiany-Kopii $stanKopia ("TEST-MRUG-" + $nazwa)
  foreach ($k in $zamiany.Keys) {
    $ile = 0; foreach ($p in $pliki) { $ile += ([regex]::Matches($tresc[$p], [regex]::Escape($k))).Count }
    if ($ile -ne 1) { return [pscustomobject]@{ Kat = $null; Powod = "kotwica kopii '$k' wystepuje $ile razy (ma byc 1)" } }
    foreach ($p in $pliki) { $tresc[$p] = $tresc[$p].Replace($k, $zamiany[$k]) }
  }
  foreach ($s in @($sabotaz)) {
    if (-not $s) { continue }
    $p = Join-Path $kat ("nadzorca\" + $s.Plik)
    $ile = ([regex]::Matches($tresc[$p], [regex]::Escape($s.Kotwica))).Count
    if ($ile -ne 1) { return [pscustomobject]@{ Kat = $null; Powod = "kotwica sabotazu w $($s.Plik) wystepuje $ile razy (ma byc 1): $($s.Kotwica)" } }
    $tresc[$p] = $tresc[$p].Replace($s.Kotwica, $s.Zamiana)
  }
  foreach ($p in $pliki) {
    if ($tresc[$p].Contains('SetForegroundWindow($formularz')) { return [pscustomobject]@{ Kat = $null; Powod = "SetForegroundWindow zostal w $p" } }
    [System.IO.File]::WriteAllText($p, $tresc[$p], $utf8bom)
  }
  if (-not ([System.IO.File]::ReadAllText($stanKopia)).Contains("BEZPIECZNIKI TESTU MIGANIA")) { return [pscustomobject]@{ Kat = $null; Powod = "bezpieczniki nie trafily do kopii stanu" } }
  return [pscustomobject]@{ Kat = $kat; Powod = "" }
}

function Uruchom-Kopie([string]$kat) {
  $wynik = Join-Path $kat "wynik.json"
  $konsola = Join-Path $kat "konsola.txt"
  $pol = "`$env:MRUG_WYNIK = '$wynik'; & '$(Join-Path $kat 'nadzorca-test.ps1')' -Zrodlo '$Zrodlo' -KatalogDomowy '$Dom' -Pokaz -Proba *> '$konsola'; exit `$LASTEXITCODE"
  $psi = New-Object System.Diagnostics.ProcessStartInfo("powershell.exe", ('-NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($pol))))
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  return [pscustomobject]@{ Kat = $kat; Proces = $p; Pid = $p.Id; Wynik = $wynik; Konsola = $konsola; Start = [datetime]::Now }
}

function Zabij-Drzewo([int]$id) { & taskkill.exe /PID $id /T /F 2>&1 | Out-Null }

function Poczekaj($u) {
  $doKonca = [math]::Max(1, $Limit - ([datetime]::Now - $u.Start).TotalSeconds)
  if (-not $u.Proces.WaitForExit([int]($doKonca * 1000))) {
    Zabij-Drzewo $u.Pid
    return "kopia nie skonczyla w $Limit s - zabita"
  }
  return ""
}

function Wczytaj-Wynik($u) {
  if (-not (Test-Path -LiteralPath $u.Wynik)) {
    $kon = ""; try { $kon = ((Get-Content -LiteralPath $u.Konsola -Encoding Unicode -ErrorAction Stop | Select-Object -Last 8) -join " | ") } catch { $kon = "(brak konsoli: $($_.Exception.Message))" }
    $log = ""; try { $log = ((Get-Content -LiteralPath ($u.Wynik + ".log") -Encoding UTF8 -ErrorAction Stop | Select-Object -Last 5) -join " | ") } catch { $log = "(brak dziennika scenariusza)" }
    return [pscustomobject]@{ Ok = $false; Powod = "kopia nie zapisala wyniku; konsola: $kon; scenariusz: $log"; Dane = $null }
  }
  try { return [pscustomobject]@{ Ok = $true; Powod = ""; Dane = (Get-Content -LiteralPath $u.Wynik -Raw -Encoding UTF8 | ConvertFrom-Json) } }
  catch { return [pscustomobject]@{ Ok = $false; Powod = "wynik nieczytelny: $($_.Exception.Message)"; Dane = $null } }
}

# Ocena jednego przebiegu: lista prob (Klucz, Nazwa, Ok, Opis). Ta sama dla kopii z poprawka
# i dla kopii z sabotazem - sabotaz ma zlamac swoja probe.
function Ocen($d) {
  $p = @($d.Pomiary)
  $o = @()
  function P($klucz, $nazwa, $ok, $opis) { return [pscustomobject]@{ Klucz = $klucz; Nazwa = $nazwa; Ok = [bool]$ok; Opis = $opis } }
  function Lista($zb, $pole) { return (($zb | ForEach-Object { "$($_.Z)->$($_.Do)=$($_.$pole)" }) -join ", ") }
  # przy porazce: ktore okna tresci rysowaly sie w trakcie (pierwszy pomiar ponad progiem)
  function Okna-Opisu($zb) {
    $zly = @($zb | Where-Object { $_.RysowanieZakladki -gt $PROG_RYSOWANIE_W_TRAKCIE }) | Select-Object -First 1
    if ($zly) { return " [np. $($zly.Z)->$($zly.Do): $($zly.OknaWTrakcie)]" } else { return "" }
  }
  $sw = @($p | Where-Object { $_.Etap -like "swieze-*" })
  $o += P "zestaw" "scenariusz doszedl do konca (przelaczenia, odswiezenie, postarzone dane)" (($sw.Count -ge 6) -and @($p | Where-Object { $_.Etap -eq "postarzone" }).Count -ge 3 -and @($p | Where-Object { $_.Etap -eq "odswiezenie-na-oczach" }).Count -eq 1) "pomiarow: $($p.Count), w tym swiezych $($sw.Count)"
  $o += P "widok" "kazde klikniecie konczy na wybranej, widocznej zakladce" (@($p | Where-Object { ($_.Widok -ne $_.Do) -or -not $_.Widoczny }).Count -eq 0) (Lista $p "Widok")
  $o += P "bez-przebudowy" "swieze dane: przelaczenie tam i z powrotem bez przebudowy, nowych kontrolek i liczenia" (@($sw | Where-Object { ($_.Przebudowy -ne 0) -or ($_.Nowych -ne 0) -or ($_.Zwolnionych -ne 0) -or ($_.NowychKrokow -ne 0) }).Count -eq 0) ("przebudowy " + (Lista $sw "Przebudowy") + "; nowe " + (Lista $sw "Nowych") + "; kroki " + (Lista $sw "NowychKrokow"))
  $o += P "granice" "swieze dane: kazda kontrolka zakladki w tym samym miejscu co przed schowaniem" (@($sw | Where-Object { $_.ZmienioneGranice -ne 0 }).Count -eq 0) (Lista $sw "ZmienioneGranice")
  $o += P "czas" "przelaczenie bez przebudowy krocej niz $PROG_KLIK_MS ms" (@($sw | Where-Object { $_.KlikMs -ge $PROG_KLIK_MS }).Count -eq 0) ("ms: " + (Lista $sw "KlikMs"))
  $o += P "w-trakcie" "przelaczenie: najwyzej $PROG_RYSOWANIE_W_TRAKCIE rysowan tresci zakladki na ekranie w trakcie zmiany" (@($sw | Where-Object { $_.RysowanieZakladki -gt $PROG_RYSOWANIE_W_TRAKCIE }).Count -eq 0) ((Lista $sw "RysowanieZakladki") + (Okna-Opisu $sw))
  $o += P "po" "przelaczenie: najwyzej $PROG_ODMALOWAN_PO osobnych odmalowan po zmianie (zakladka naraz, nie kawalkami)" (@($sw | Where-Object { $_.OdmalowanPo -gt $PROG_ODMALOWAN_PO }).Count -eq 0) (Lista $sw "OdmalowanPo")
  $od = @($p | Where-Object { $_.Etap -eq "odswiezenie-na-oczach" })
  $o += P "odswiezenie-bylo" "kontrola: dane z dozoru przebudowaly widoczny Przeglad (inaczej nastepne dwie proby nic nie mierza)" (@($od | Where-Object { $_.Przebudowy -ge 1 -and $_.Nowych -gt 0 }).Count -eq 1) ("przebudowy " + (Lista $od "Przebudowy") + ", nowych " + (Lista $od "Nowych"))
  $o += P "odswiezenie-w-trakcie" "przebudowa widocznego Przegladu: najwyzej $PROG_RYSOWANIE_W_TRAKCIE rysowan tresci zakladki na ekranie w trakcie" (@($od | Where-Object { $_.RysowanieZakladki -gt $PROG_RYSOWANIE_W_TRAKCIE }).Count -eq 0) ((Lista $od "RysowanieZakladki") + (Okna-Opisu $od))
  $o += P "odswiezenie-po" "przebudowa widocznego Przegladu: najwyzej $PROG_ODMALOWAN_PO osobnych odmalowan" (@($od | Where-Object { $_.OdmalowanPo -gt $PROG_ODMALOWAN_PO }).Count -eq 0) (Lista $od "OdmalowanPo")
  $we = @($p | Where-Object { ($_.Etap -eq "wejscie-po-odswiezeniu") -or ($_.Etap -eq "postarzone") })
  $o += P "wejscie-bylo" "kontrola: wejscie do Szczegolow po odswiezeniu przebudowalo zakladke" (@($p | Where-Object { ($_.Etap -eq "wejscie-po-odswiezeniu") -and ($_.Do -eq "szczegoly") -and ($_.Przebudowy -ge 1) }).Count -eq 1) ("przebudowy " + (Lista @($p | Where-Object { $_.Etap -eq "wejscie-po-odswiezeniu" }) "PrzebudowyOpis"))
  $o += P "wejscie-w-trakcie" "wejscie do zakladki z nowymi danymi: najwyzej $PROG_RYSOWANIE_W_TRAKCIE rysowan tresci zakladki na ekranie w trakcie" (@($we | Where-Object { $_.RysowanieZakladki -gt $PROG_RYSOWANIE_W_TRAKCIE }).Count -eq 0) ((Lista $we "RysowanieZakladki") + (Okna-Opisu $we))
  $o += P "wejscie-po" "wejscie do zakladki z nowymi danymi: najwyzej $PROG_ODMALOWAN_PO osobnych odmalowan" (@($we | Where-Object { $_.OdmalowanPo -gt $PROG_ODMALOWAN_PO }).Count -eq 0) (Lista $we "OdmalowanPo")
  $gr = @($p | Where-Object { $_.Etap -like "grupa-skilli-*" })
  $grI = @($d.Inne | Where-Object { $_.Rodzaj -eq "grupa-skilli" })
  if ($grI.Count -gt 0) {
    $roz = @($grI | Where-Object { $_.Krok -eq "rozwin" }); $zw = @($grI | Where-Object { $_.Krok -eq "zwin" })
    $o += P "grupa-dziala" "grupa skilli rozwija sie i zwija (wiersze widac i znikaja)" (($roz.Count -eq 1) -and ($zw.Count -eq 1) -and ($roz[0].Widocznych -gt 0) -and ($roz[0].Widocznych -eq $roz[0].Wierszy) -and ($zw[0].Widocznych -eq 0)) ("grupa $($roz[0].Grupa): po rozwinieciu $($roz[0].Widocznych) z $($roz[0].Wierszy), po zwinieciu $($zw[0].Widocznych)")
    $o += P "grupa-w-trakcie" "grupa skilli: najwyzej $PROG_RYSOWANIE_W_TRAKCIE rysowan tresci zakladki w trakcie, najwyzej $PROG_ODMALOWAN_PO odmalowan po" (@($gr | Where-Object { ($_.RysowanieZakladki -gt $PROG_RYSOWANIE_W_TRAKCIE) -or ($_.OdmalowanPo -gt $PROG_ODMALOWAN_PO) }).Count -eq 0) ("w trakcie " + (Lista $gr "RysowanieZakladki") + "; po " + (Lista $gr "OdmalowanPo") + (Okna-Opisu $gr))
  }
  $bez = @($d.Inne | Where-Object { $_.Rodzaj -eq "bezczynnosc" })
  $o += P "bezczynnosc" "bezczynne okno nie maluje sie w kolko (2 s na Przegladzie, Szczegolach i Warstwach)" (($bez.Count -eq 3) -and @($bez | Where-Object { $_.OdmalowanPo -ne 0 }).Count -eq 0) ((($bez | ForEach-Object { "$($_.Widok)=$($_.OdmalowanPo)" }) -join ", "))
  $prz = @($d.Inne | Where-Object { $_.Rodzaj -eq "przewijanie" })
  $o += P "przewijanie" "kolko myszy przewija Szczegoly, kazdy zabek ponizej $PROG_PRZEWINIECIE_MS ms" (($prz.Count -eq 1) -and ($prz[0].Pozycja -gt 0) -and ($prz[0].Max -lt $PROG_PRZEWINIECIE_MS)) ("ms: $($prz[0].Czasy), pozycja po $($prz[0].Pozycja) px")
  $wy = @($d.Wywrotki | Where-Object { $_ })
  $sc = @($d.Log | Where-Object { $_ -match 'WYWROTKA SCENARIUSZA|LIMIT fazy|ZAPIS WYNIKU' })
  $o += P "wywrotki" "bez wywrotek nadzorcy i scenariusza" (($wy.Count -eq 0) -and ($sc.Count -eq 0)) ((@($wy) + @($sc)) -join " || ")
  return $o
}

function Tabela($d) {
  return (@($d.Pomiary) | Format-Table Etap, Z, Do, KlikMs, RysowanieZakladki, RysowanieWTrakcie, OdmalowanPo, Nowych, Zwolnionych, ZmienioneGranice, PrzebudowyOpis, NowychKrokow -AutoSize | Out-String -Width 220)
}

$uruchomione = @()

# ---------------------------------------------------------------- A. kopia okna z biezacym kodem
Write-Host "Kopia okna (dane z $Dom, limit $Limit s) - ok. 1,5 min..."
$k = Przygotuj-Kopie "okno" $null
if (-not $k.Kat) { Wynik "kopia okna" $false $k.Powod; exit 1 }
$u = Uruchom-Kopie $k.Kat
$uruchomione += $u
$zw = Poczekaj $u
$w = Wczytaj-Wynik $u
if ($zw -or -not $w.Ok) {
  Wynik "kopia okna przeszla scenariusz" $false "$zw $($w.Powod)"
} else {
  Write-Host (Tabela $w.Dane)
  foreach ($x in (Ocen $w.Dane)) { Wynik $x.Nazwa $x.Ok $x.Opis }
}

# ---------------------------------------------------------------- B. sabotaze (proby negatywne)
# Kazdy przywraca jedna czesc starego zachowania; jego proba MUSI pasc. Ida rownolegle - sprawdzaja
# liczby (rysowania, odmalowania, przebudowy) i przekroczenie progu czasu w gore, a rownolegly
# przebieg moze czas tylko wydluzyc.
$SABOTAZE = @(
  @{ Nazwa = "uklad liczony po kazdej kontrolce (bez wstrzymania ukladu przy pokazaniu)"; Proba = "czas"
     Zmiany = @(@{ Plik = "okno.ps1"; Kotwica = 'foreach ($c in $kontenery) { $c.SuspendLayout() }'; Zamiana = '$kontenery.Clear()   # SABOTAZ' }) },
  @{ Nazwa = "Przeglad i Szczegoly bez podwojnego bufora - pokazywanie kawalkami"; Proba = "po"
     Zmiany = @(@{ Plik = "okno.ps1"; Kotwica = '$script:WidokPrzeglad = New-Object MegaRuchacz.ListaBezMigania'; Zamiana = '$script:WidokPrzeglad = New-Object System.Windows.Forms.Panel   # SABOTAZ' },
                @{ Plik = "okno.ps1"; Kotwica = '$script:WidokSzczegoly = New-Object MegaRuchacz.ListaBezMigania'; Zamiana = '$script:WidokSzczegoly = New-Object System.Windows.Forms.Panel   # SABOTAZ' }) },
  @{ Nazwa = "Przeglad bez podwojnego bufora - przebudowa po odswiezeniu na oczach"; Proba = "odswiezenie-w-trakcie"
     Zmiany = @(@{ Plik = "okno.ps1"; Kotwica = '$script:WidokPrzeglad = New-Object MegaRuchacz.ListaBezMigania'; Zamiana = '$script:WidokPrzeglad = New-Object System.Windows.Forms.Panel   # SABOTAZ' }) },
  @{ Nazwa = "Warstwy i Skille bez podwojnego bufora - tlo i karty wymazywane przy wejsciu"; Proba = "w-trakcie"
     Zmiany = @(@{ Plik = "okno.ps1"; Kotwica = '$script:WidokWarstwy = New-Object MegaRuchacz.ListaBezMigania'; Zamiana = '$script:WidokWarstwy = New-Object System.Windows.Forms.Panel   # SABOTAZ' },
                @{ Plik = "okno.ps1"; Kotwica = '$script:WidokSkille = New-Object MegaRuchacz.ListaBezMigania'; Zamiana = '$script:WidokSkille = New-Object System.Windows.Forms.Panel   # SABOTAZ' }) },
  @{ Nazwa = "zakladka przebudowywana przy kazdym wejsciu"; Proba = "bez-przebudowy"
     Zmiany = @(@{ Plik = "w-tle.ps1"; Kotwica = 'if ($script:DoOdmalowania[$widok]) { Wyrenderuj-Widok $widok } else { Odmaluj-Podtytul }'; Zamiana = 'Wyrenderuj-Widok $widok   # SABOTAZ' }) }
)
if (-not $BezSabotazy) {
  Write-Host "Sabotaze ($($SABOTAZE.Count) kopii rownolegle) - ok. 2-3 min..."
  $sab = @()
  $i = 0
  foreach ($s in $SABOTAZE) {
    $i++
    $k = Przygotuj-Kopie "sabotaz$i" $s.Zmiany
    if (-not $k.Kat) { Wynik "sabotaz '$($s.Nazwa)' wylapany" $false $k.Powod; continue }
    $u = Uruchom-Kopie $k.Kat
    $uruchomione += $u
    $sab += [pscustomobject]@{ S = $s; U = $u }
  }
  foreach ($x in $sab) {
    $zw = Poczekaj $x.U
    $w = Wczytaj-Wynik $x.U
    if ($zw -or -not $w.Ok) { Wynik "sabotaz '$($x.S.Nazwa)' wylapany przez '$($x.S.Proba)'" $false "przebieg sie nie udal: $zw $($w.Powod)"; continue }
    $oc = @(Ocen $w.Dane)
    $wl = @($oc | Where-Object { $_.Klucz -eq $x.S.Proba })
    $kontrola = @($oc | Where-Object { $_.Klucz -in @("zestaw", "wywrotki") -and -not $_.Ok })
    $ok = ($wl.Count -eq 1) -and (-not $wl[0].Ok) -and ($kontrola.Count -eq 0)
    $opis = "z sabotazem: $(if ($wl.Count) { $wl[0].Opis } else { 'brak proby' })"
    if ($kontrola.Count) { $opis += " || przebieg niepelny: " + (($kontrola | ForEach-Object { $_.Opis }) -join "; ") }
    Wynik "sabotaz '$($x.S.Nazwa)' wylapany przez '$($x.S.Proba)'" $ok $opis
  }
}

# ---------------------------------------------------------------- C. sprzatanie
Start-Sleep -Milliseconds 500
$pidy = @($uruchomione | ForEach-Object { $_.Pid })
$zostaly = @(Get-CimInstance Win32_Process | Where-Object { ($pidy -contains $_.ProcessId) -or ($pidy -contains $_.ParentProcessId) -or ($_.CommandLine -and $_.CommandLine.Contains($tmp)) })
foreach ($z in $zostaly) { Zabij-Drzewo $z.ProcessId }
Wynik "po tescie zadna kopia okna nie zostala w procesach" ($zostaly.Count -eq 0) ("zostalo: " + (($zostaly | ForEach-Object { "$($_.ProcessId) $($_.Name)" }) -join ", "))

Write-Host ""
Write-Host "Wynik: $(@($script:wyniki | Where-Object { $_.OK }).Count) z $($script:wyniki.Count) TAK. Pliki robocze: $tmp"
if (@($script:wyniki | Where-Object { -not $_.OK }).Count -gt 0) { exit 1 }
exit 0
