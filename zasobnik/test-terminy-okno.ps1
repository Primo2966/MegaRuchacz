# Sprawdzenie okna przypomnien (zasobnik\terminy.ps1, 2026-10-08): napisy w oknie to pola
# tekstowe tylko do odczytu, ktore da sie zaznaczyc i skopiowac, przycisk "Kopiuj" przy kazdym
# przypomnieniu, dluga tresc bez uciecia, porazka schowka widoczna na przycisku i w dzienniku.
#   powershell -ExecutionPolicy Bypass -File zasobnik\test-terminy-okno.ps1 [-Zrodlo <repo>] [-Zrzuty <kat>]
# Wszystko na kopii terminy.ps1, sztucznym katalogu domowym i testowym pliku przypomnien (tylko
# tryb "przypomnij"; kopia kieruje go do okna zamiast w tle). Kopia: okno poza ekranem (-5000, 0), bez paska
# zadan, bez aktywacji (nie zabiera klawiatury), bez TopMost, klawiatura wylaczona, wlasne zamki,
# zegar, ktory po pomiarach zamyka okno. Proces kopii bez okna konsoli, ubijany po 120 s.
# Sabotaze: kopie z Label zamiast pola, zepsutym "Kopiuj", stala wysokoscia pola, cichym bledem
# schowka i trzema zepsutymi Do-Schowka - kazdy MUSI zostac zlapany. Zawartosc schowka uzytkownika
# zachowana i przywrocona.
# Okno niepowodzenia (2026-10-12, Okno-Niepowodzenia: blad przebiegu w tle, sprawa juz na jutro):
# kopia, ktora zamiast zwyklego okna pokazuje je dla #1 - zdanie "Nie udalo sie ... Przeniesione
# na jutro" na czerwono, przyciski "Sprobuj teraz" / "Odloz na jutro" (+ Kopiuj), krzyzyk niczego
# nie odklada. Sabotaze: zwykle przyciski w oknie niepowodzenia, krzyzyk odkladajacy o 2 godziny.
# Okno decyzji (2026-10-12, Okno-Decyzji: wynik POTRZEBUJE_CIEBIE zamiast terminala): kopia pokazuje
# je dla #1 - tytul "Przypomnienie #1 – potrzebna Twoja decyzja", zdanie duza czcionka, odpowiedzi
# (PYTANIE) albo "Zrobione" (ZROB), "Odloz na jutro", "Otworz rozmowe", zwiniete "Szczegoly". Hak
# klika przycisk przed pomiarem (-Przed) albo po nim (-Klik). Otworz-Terminal, Odpal-W-Tle i
# Pokaz-Blad w KAZDEJ kopii to atrapy, ktore tylko zapisuja - zaden terminal, proces w tle ani
# MessageBox nie powstaje. Sabotaze: szczegoly rozwiniete od razu, stala wysokosc przycisku
# odpowiedzi, krzyzyk bez przeniesienia na jutro, odpowiedz otwierajaca terminal.
# Rozciaganie (2026-10-14): zwykle okno, okno niepowodzenia i okna decyzji (-Rozciagnij) - ramka Sizable,
# maksymalizacja, MinimumSize = rozmiar z kodu, pola i przyciski po +300 px szersze i bez uciecia, proba
# zejscia ponizej minimum, powrot do dawnych szerokosci, zapis rozmiaru przy zamknieciu. Zapamietany
# rozmiar (przypomnienia-okno-rozmiar.txt przed startem): przywracany, ponizej minimum, zepsuty plik,
# polozenie poza ekranem, katalog zamiast pliku - zawsze okno i wpis w dzienniku, nigdy wyjatek. Atrapa
# Przywroc-Rozmiar-Okna bierze tylko rozmiar (polozenie z pliku i maksymalizacja = okno na ekranie).
# Sabotaze: bez maksymalizacji, bez rozkladu, bez minimum, zla baza, bez zapisu, przycisk GrowOnly,
# odczyt z wyjatkiem, bez przywracania, polozenie poza ekranem przyjete, cichy blad zapisu.
# Schowek czytaja po kazdej zmianie inne programy (zmierzone 2026-10-08: Remotly, historia schowka,
# Eksplorator - kazdy trzyma go do 70 ms), dlatego test przed kopiowaniem czeka, az ucichna, a odczyt
# ponawia do $MS_ODCZYTU_SCHOWKA (GetText przy zajetym schowku po cichu zwraca ""). Zajety schowek
# robi tez celowo osobny proces (trzymacz): krotko - Kopiuj ma poczekac i skopiowac, dlugo - porazka
# widoczna na przycisku i w dzienniku.
# SCHOWEK TYLKO Z -Schowek (2026-10-12: przebieg nadpisal schowek uzytkownika w trakcie jego pracy -
# wklejal "TEST-SCHOWEK-PUSTY-4"). Bez przelacznika test ani razu nie dotyka schowka: bez zaznaczania
# i kopiowania pol, przyciskow Kopiuj, trzymacza, zapamietania i przywracania - i mowi o tym jedna linia.
# Proby schowka uruchamiac tylko, gdy nikt nie pracuje przy komputerze.
param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [string]$Zrzuty = "",
  [switch]$Schowek
)
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { Write-Warning "konsola bez UTF-8: $($_.Exception.Message)" }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("test-terminy-okno-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
if (-not $Zrzuty) { $Zrzuty = Join-Path $tmp "zrzuty" }
New-Item -ItemType Directory -Force -Path $Zrzuty | Out-Null
$dom = Join-Path $tmp "dom"
$katMr = Join-Path $dom ".claude\mr"
New-Item -ItemType Directory -Force -Path $katMr | Out-Null
$plikP = Join-Path $katMr "przypomnienia.md"
$dziennik = Join-Path $katMr "przypomnienia.log"
$plikOkna = Join-Path $katMr "przypomnienia-okno.txt"
$plikRozmiaru = Join-Path $katMr "przypomnienia-okno-rozmiar.txt"
$logTerminala = Join-Path $tmp "atrapa-terminal.jsonl"
$logOdpal = Join-Path $tmp "atrapa-odpal.jsonl"
$logBledow = Join-Path $tmp "atrapa-pokaz-blad.txt"
$oryginal = Join-Path $Zrodlo "zasobnik\terminy.ps1"
$BezBom = New-Object System.Text.UTF8Encoding($false)
$ZBom = New-Object System.Text.UTF8Encoding($true)

$script:wyniki = @()
function Wynik($nazwa, $ok, $opis) {
  $script:wyniki += [pscustomobject]@{ Test = $nazwa; OK = [bool]$ok; Opis = $opis }
  $z = "NIE"; if ($ok) { $z = "TAK" }
  Write-Host ("[{0}] {1} - {2}" -f $z, $nazwa, $opis)
}

# ---------------------------------------------------------------- dane testowe
$dzis = (Get-Date).ToString("yyyy-MM-dd")
$projekt = $tmp
$tresc1 = "Sprawdzić, czy oferty na Amazon PL mają ten sam SKU i ASIN co w FBA."
$spr1 = "Seller Central → Inventory, filtr po SKU"
$tresc2 = ("Długa treść przypomnienia do sprawdzenia zawijania: zestaw SET3-Citrus[020312] ma olejki 02, 03 i 12, " +
           "trzeba porównać ceny na DE, FR i UK, policzyć dopłaty FBA za EFN i Remote Fulfilment, " +
           "sprawdzić zdjęcie główne wariantu 40 g mentolu i 30 szt. kadzidełek backflow, " +
           "a potem przejrzeć tytuły pod frazy z zakupami z ostatnich 14 miesięcy (Search Query Performance), " +
           "bez powtórzeń i w naturalnym niemieckim, z wolnym miejscem na konkretny zapach ze składu zestawu. " +
           "Na koniec zapisać wyniki w pliku i dać znać, co się zmieniło, a czego nie dało się sprawdzić. " +
           "Zażółć gęślą jaźń - polskie znaki też muszą przejść przez schowek bez zmian.")
$spr2 = "porównanie cen w pliku dopłat, a tytuły w Search Query Performance"
$tresc3 = "Sprawa w toku od kilku dni - powinna mieć czerwoną uwagę pod treścią."
$linie = @(
  "# Przypomnienia - plik testowy test-terminy-okno.ps1",
  "",
  "- [ ] #1 $dzis | $projekt | $tresc1 | sprawdź: $spr1 | tryb: przypomnij | dodane $dzis",
  "- [ ] #2 $dzis | $projekt | $tresc2 | sprawdź: $spr2 | tryb: przypomnij | dodane $dzis",
  "- [~] #3 2026-10-01 | $projekt | $tresc3 | tryb: przypomnij | dodane 2026-09-30 | w toku 2026-10-01")
$trescPola = @{ 1 = "$tresc1`r`nJak sprawdzić: $spr1"; 2 = "$tresc2`r`nJak sprawdzić: $spr2"; 3 = $tresc3 }
$CZERWONY = [System.Drawing.Color]::FromArgb(170, 40, 20).ToArgb()
$CZARNY = [System.Drawing.SystemColors]::ControlText.ToArgb()

# Trzymacz: osobny proces, ktory otwiera schowek i trzyma go przez -Ms, jak program, ktory akurat
# z niego czyta. Krotko: dluzej niz czeka Clipboard.SetText (10 x 100 ms - stara wersja Do-Schowka
# tu pada), krocej niz czeka Do-Schowka ($PROB_SCHOWKA x $MS_MIEDZY_PROBAMI_SCHOWKA = 2,5 s).
# Dlugo: dluzej niz czeka Do-Schowka - ma byc widoczna porazka.
$MS_TRZYMANIA_KROTKO = 1800
$MS_TRZYMANIA_DLUGO = 4000
$trzymacz = Join-Path $tmp "trzymacz-schowka.ps1"
[System.IO.File]::WriteAllText($trzymacz, @'
param([int]$Ms, [string]$Znak)
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class TrzymaczSchowka {
  [DllImport("user32.dll")] public static extern bool OpenClipboard(IntPtr h);
  [DllImport("user32.dll")] public static extern bool CloseClipboard();
}
"@
# Wlasne okno (tylko do komunikatow, niewidoczne): schowek otwarty z NULL zamyka kazdy inny
# program, ktory tez otworzy go z NULL i zamknie (zmierzone - trzymanie znikalo po 0 ms).
Add-Type -AssemblyName System.Windows.Forms
$okno = New-Object System.Windows.Forms.NativeWindow
$cp = New-Object System.Windows.Forms.CreateParams
$cp.Parent = [IntPtr](-3)
$okno.CreateHandle($cp)
$t0 = [datetime]::Now
while (-not [TrzymaczSchowka]::OpenClipboard($okno.Handle)) {
  if (([datetime]::Now - $t0).TotalSeconds -gt 10) { [System.IO.File]::WriteAllText($Znak, "nie otworzylem schowka w 10 s"); exit 1 }
  Start-Sleep -Milliseconds 20
}
try { [System.IO.File]::WriteAllText($Znak, "trzymam"); Start-Sleep -Milliseconds $Ms } finally { [void][TrzymaczSchowka]::CloseClipboard() }
exit 0
'@, $BezBom)

# ---------------------------------------------------------------- kod wstrzykiwany do kopii
$klasaOkna = @'
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
public class OknoTestowePrzypomnien : System.Windows.Forms.Form {
  public static string Opis { get { return "okno testowe bez aktywacji"; } }
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override System.Windows.Forms.CreateParams CreateParams {
    get { System.Windows.Forms.CreateParams cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x00000080; return cp; }
  }
}
"@
  $f = New-Object OknoTestowePrzypomnien
'@
# Zamiast $f.Activate(): pomiary i kopiowanie z zegara, potem zamkniecie okna.
$hak = @'
$f.KeyPreview = $true
  $f.Add_KeyDown({ param($n, $e) $e.Handled = $true; $e.SuppressKeyPress = $true })
  function T-Wszystkie($c) { foreach ($d in $c.Controls) { $d; T-Wszystkie $d } }
  function T-Pompuj([int]$ms) { $do = [datetime]::Now.AddMilliseconds($ms); while ([datetime]::Now -lt $do) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 } }
  # Odczyt schowka ponawiany, az pokaze oczekiwany tekst albo minie $MS_ODCZYTU_SCHOWKA - wtedy
  # zwraca ostatni odczyt i ocenia go rodzic (ponawianie nie zmienia tresci, tylko omija chwile,
  # gdy schowek trzyma inny program).
  $MS_ODCZYTU_SCHOWKA = 2500
  function T-Schowek([string]$ocz) {
    $do = [datetime]::Now.AddMilliseconds($MS_ODCZYTU_SCHOWKA); $ost = ""
    do {
      T-Pompuj 40
      try { $ost = [System.Windows.Forms.Clipboard]::GetText() } catch { $ost = "BLAD ODCZYTU SCHOWKA: $($_.Exception.Message)" }
      if ($ost -ceq $ocz) { return $ost }
    } while ([datetime]::Now -lt $do)
    return $ost
  }
  # Zapis znacznika zamiast Clear (po nim widac, ze kopiowanie nic nie dalo) i odczekanie, az inne
  # programy skoncza czytac zmiane - kopiowanie przez pole (WM_COPY) przy zajetym schowku po cichu
  # nic nie robi, tak samo w kazdym programie Windows.
  function T-Czysc {
    $script:TestZnaczniki++
    for ($i = 0; $i -lt 30; $i++) {
      try { [System.Windows.Forms.Clipboard]::SetDataObject("TEST-SCHOWEK-PUSTY-$($script:TestZnaczniki)", $true, 0, 0); T-Pompuj 150; return } catch { T-Pompuj 100 }
    }
    $script:TestRaport.Uwagi += "nie zapisalem znacznika do schowka w 30 probach"
  }
  # Czy schowek jest teraz zajety: proba zapisu bez czekania (przy zajetym rzuca od razu).
  function T-Zajety { try { [System.Windows.Forms.Clipboard]::SetDataObject("TEST-SONDA", $true, 0, 0); return $false } catch { return $true } }
  # Osobny proces trzyma schowek otwarty przez $ms; zwraca go, gdy juz trzyma.
  function T-Trzymaj([int]$ms) {
    $znak = Join-Path '__TMP__' ("trzymacz-" + [guid]::NewGuid().ToString("N").Substring(0, 8) + ".txt")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"__TRZYMACZ__`" -Ms $ms -Znak `"$znak`""
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $do = [datetime]::Now.AddSeconds(20)
    $stan = ""
    while ((-not $stan) -and ([datetime]::Now -lt $do)) {
      if (Test-Path -LiteralPath $znak) { try { $stan = [System.IO.File]::ReadAllText($znak) } catch { $stan = "" } }
      elseif ($p.HasExited) { $stan = "proces skonczyl bez znaku, kod $($p.ExitCode)" }
      if (-not $stan) { T-Pompuj 20 }
    }
    if (-not $stan) { $stan = "brak znaku w 20 s" }
    if ($stan -ne "trzymam") { $script:TestRaport.Uwagi += "trzymacz schowka nie trzyma ($stan)"; try { $p.Kill() } catch { $script:TestRaport.Uwagi += "trzymacz: $($_.Exception.Message)" } }
    return $p
  }
  function T-Pusc($p) {
    $do = [datetime]::Now.AddSeconds(15)
    while ((-not $p.HasExited) -and ([datetime]::Now -lt $do)) { T-Pompuj 50 }
    if (-not $p.HasExited) { $script:TestRaport.Uwagi += "trzymacz nie skonczyl sam"; try { $p.Kill() } catch { $script:TestRaport.Uwagi += "trzymacz: $($_.Exception.Message)" } }
  }
  # Migawka kontrolek (typ, tekst, rozmiar, polozenie, uciecie) - przy rozmiarze z kodu i po rozciagnieciu.
  function T-Kontrolki {
    $lst = $script:Okno.Controls[0]
    foreach ($c in @(T-Wszystkie $script:Okno)) {
      $k = [ordered]@{ Typ = $c.GetType().Name; Tekst = "$($c.Text)"; Widoczny = $c.Visible; Wys = $c.Height; Szer = $c.Width; Prawa = $c.Right
                       SzerRodzica = $c.Parent.ClientSize.Width; Kolor = $c.ForeColor.ToArgb(); Tlo = $c.BackColor.ToArgb(); TloRodzica = $c.Parent.BackColor.ToArgb() }
      $k.Akcja = ""; if (($c -is [System.Windows.Forms.Button]) -and ($c.Tag -is [hashtable])) { $k.Akcja = "$($c.Tag.Akcja)" }
      # Polozenie w obszarze okna (ucina je okno, nie tylko rodzic) i wielkosc czcionki.
      $k.Pkt = [Math]::Round($c.Font.SizeInPoints, 1)
      if ($c.Visible) { $pt = $script:Okno.PointToClient($c.PointToScreen([System.Drawing.Point]::Empty)); $k.WOknieDol = $pt.Y + $c.Height; $k.WOkniePrawa = $pt.X + $c.Width }
      # Przycisk: wysokosc potrzebna na tekst zawiniety przy jego szerokosci. Ramka = naturalny rozmiar
      # blizniaka z AutoSize (jeden wiersz; PreferredSize przycisku bez AutoSize oddaje jego obecna
      # wysokosc) minus sam tekst; plaski "Szczegoly" ma ja mniejsza niz zwykly.
      if ($c -is [System.Windows.Forms.Button]) {
        $flagi = [System.Windows.Forms.TextFormatFlags]"WordBreak, NoPrefix"
        $jeden = [System.Windows.Forms.TextRenderer]::MeasureText($c.Text, $c.Font, [System.Drawing.Size]::Empty, [System.Windows.Forms.TextFormatFlags]"NoPrefix")
        $bl = New-Object System.Windows.Forms.Button
        $bl.Font = $c.Font; $bl.UseMnemonic = $c.UseMnemonic; $bl.Padding = $c.Padding; $bl.FlatStyle = $c.FlatStyle; $bl.FlatAppearance.BorderSize = $c.FlatAppearance.BorderSize
        $bl.Text = $c.Text; $bl.AutoSize = $true
        $nat = $bl.PreferredSize; $bl.Dispose()
        $ile = New-Object System.Drawing.Size([Math]::Max(1, $c.Width - ($nat.Width - $jeden.Width)), [int]::MaxValue)
        $k.Potrzebna = [System.Windows.Forms.TextRenderer]::MeasureText($c.Text, $c.Font, $ile, $flagi).Height + ($nat.Height - $jeden.Height)
      }
      if ($c -is [System.Windows.Forms.TextBox]) {
        $k.ReadOnly = $c.ReadOnly; $k.Multiline = $c.Multiline; $k.Ramka = "$($c.BorderStyle)"; $k.Paski = "$($c.ScrollBars)"
        $k.TabStop = $c.TabStop; $k.Wlaczony = $c.Enabled; $k.WysWnetrza = $c.ClientSize.Height; $k.WysCzcionki = $c.Font.Height
        $ost = [Math]::Max(0, $c.TextLength - 1)
        $k.PierwszaY = $c.GetPositionFromCharIndex(0).Y; $k.OstatniaY = $c.GetPositionFromCharIndex($ost).Y; $k.Linii = $c.GetLineFromCharIndex($ost) + 1
      }
      # Prawa krawedz w obszarze listy (bez paska przewijania) - po rozciagnieciu nic nie moze za nia wyjsc.
      if ($c.Visible -and ($c -ne $lst)) { $k.WLisciePrawa = $lst.PointToClient($c.PointToScreen([System.Drawing.Point]::Empty)).X + $c.Width; $k.ListaSzer = $lst.ClientSize.Width }
      [pscustomobject]$k
    }
  }
  function T-Sprawdz {
    $r = $script:TestRaport
    $r.Kontrolki = @(T-Kontrolki)
    # Wszystko do zamykajacej klamry "koniec prob schowka" dotyka schowka - tylko z -Schowek.
    if (__SCHOWEK__) {
    # zaznaczenie calego pola i Kopiuj (to samo, co zaznaczenie mysza + Ctrl+C / menu Kopiuj)
    $pola = @(T-Wszystkie $script:Okno | Where-Object { $_ -is [System.Windows.Forms.TextBox] })
    foreach ($c in $pola) {
      T-Czysc
      $c.Select(0, $c.TextLength); $c.Copy()
      $r.Zaznaczenia += [pscustomobject]@{ Tekst = $c.Text; Zaznaczone = $c.SelectedText; Schowek = (T-Schowek $c.Text) }
    }
    $dl = $pola | Sort-Object TextLength -Descending | Select-Object -First 1
    if ($dl -and $dl.TextLength -gt 60) {
      T-Czysc
      $dl.Select(10, 45); $dl.Copy()
      $r.Fragment = [pscustomobject]@{ Oczekiwany = $dl.Text.Substring(10, 45); Schowek = (T-Schowek $dl.Text.Substring(10, 45)) }
    }
    # przyciski Kopiuj
    $kop = @(T-Wszystkie $script:Okno | Where-Object { ($_ -is [System.Windows.Forms.Button]) -and ("$($_.AccessibleName)" -like "Kopiuj #*") })
    $wpisy = @()
    foreach ($b in $kop) {
      T-Czysc
      $b.PerformClick(); $po = $b.Text
      $wpisy += [pscustomobject]@{ Nazwa = $b.AccessibleName; Schowek = (T-Schowek $b.Tag.Tekst); NapisPo = $po; NapisPozniej = ""; Szer = $b.Width; Przycisk = $b }
    }
    T-Pompuj ($MS_NAPISU_SKOPIOWANO + 700)
    foreach ($w in $wpisy) { $w.NapisPozniej = $w.Przycisk.Text; $w.Szer = "$($w.Szer)/$($w.Przycisk.Width)"; $w.PSObject.Properties.Remove("Przycisk"); $r.Kopiuj += $w }
    # schowek zajety przez inny program (prawdziwy, trzymany przez osobny proces): krotko -
    # Kopiuj czeka i kopiuje; dlugo - "Nie skopiowano" zostaje i jest wpis w dzienniku
    if (($kop.Count -gt 0) -and __ZAJETY__) {
      $b = $kop[0]
      foreach ($sc in @(@{ Pole = "KopiujZajety"; Ms = __MS_KROTKO__ }, @{ Pole = "KopiujBlad"; Ms = __MS_DLUGO__ })) {
        T-Czysc
        $tr = T-Trzymaj $sc.Ms
        $zajPrzed = T-Zajety
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $b.PerformClick()
        $czas = $sw.ElapsedMilliseconds
        $po = $b.Text
        $zajPo = $null; $sch = $null
        if ($sc.Pole -eq "KopiujBlad") { $zajPo = T-Zajety } else { $sch = T-Schowek $b.Tag.Tekst }
        T-Pusc $tr
        T-Pompuj ($MS_NAPISU_SKOPIOWANO + 700)
        $r.($sc.Pole) = [pscustomobject]@{ Nazwa = $b.AccessibleName; TrzymanoMs = $sc.Ms; ZajetyPrzed = $zajPrzed; ZajetyPo = $zajPo
                                           CzasKlikniecia = $czas; NapisPo = $po; NapisPozniej = $b.Text; Schowek = $sch }
      }
    }
    }   # koniec prob schowka (__SCHOWEK__)
    $bmp = New-Object System.Drawing.Bitmap($script:Okno.Width, $script:Okno.Height)
    $script:Okno.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $script:Okno.Width, $script:Okno.Height)))
    $bmp.Save('__ZRZUT__'); $bmp.Dispose()
  }
  $script:TestRaport = [pscustomobject]@{ Kontrolki = @(); Zaznaczenia = @(); Fragment = $null; Kopiuj = @(); KopiujZajety = $null; KopiujBlad = $null
                                          Wywrotka = ""; Uwagi = @(); Watek = [System.Threading.Thread]::CurrentThread.ApartmentState.ToString()
                                          Okno = ""; Ekran = ""; Tytul = ""; KlientSzer = 0; KlientWys = 0; Klik = $null
                                          Ramka = ""; MaksBox = $null; Szer = 0; Wys = 0; MinSzer = 0; MinWys = 0; Przywrocone = "$($script:TestPrzywrocone)"
                                          Rozciagniete = $null; Sciesnione = $null; Wrocone = @(); Koniec = "" }
  # Rozciagniecie (z -Rozciagnij): +300 x +200 px - pola rosna, tekst sie zawija od nowa; proba
  # zejscia do 200 x 120 (ma zostac MinimumSize) i powrot do rozmiaru z kodu. Okno caly czas poza ekranem.
  function T-Rozciagnij {
    $r = $script:TestRaport
    $przed = $script:Okno.Size
    $script:Okno.Size = New-Object System.Drawing.Size(($przed.Width + 300), ($przed.Height + 200)); T-Pompuj 300
    $lst = $script:Okno.Controls[0]
    $r.Rozciagniete = [pscustomobject]@{ Szer = $script:Okno.Width; Wys = $script:Okno.Height; ListaSzer = $lst.ClientSize.Width; Kontrolki = @(T-Kontrolki) }
    $bmp = New-Object System.Drawing.Bitmap($script:Okno.Width, $script:Okno.Height)
    $script:Okno.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $script:Okno.Width, $script:Okno.Height)))
    $bmp.Save('__ZRZUT_ROZC__'); $bmp.Dispose()
    $script:Okno.Size = New-Object System.Drawing.Size(200, 120); T-Pompuj 300
    $r.Sciesnione = [pscustomobject]@{ Szer = $script:Okno.Width; Wys = $script:Okno.Height }
    $script:Okno.Size = $przed; T-Pompuj 300
    $r.Wrocone = @(T-Kontrolki)
  }
  # Przycisk po napisie (okno decyzji: -Przed klika przed pomiarem, -Klik po nim).
  function T-Kliknij([string]$napis) {
    $b = @(T-Wszystkie $script:Okno | Where-Object { ($_ -is [System.Windows.Forms.Button]) -and $_.Visible -and ($_.Text -ceq $napis) })
    if ($b.Count -ne 1) { $script:TestRaport.Uwagi += "przyciskow '$napis': $($b.Count)"; return $null }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $b[0].PerformClick()
    return [pscustomobject]@{ Napis = $napis; Ms = $sw.ElapsedMilliseconds; Zamkniete = ($script:Okno.IsDisposed -or -not $script:Okno.Visible) }
  }
  $script:TestZegar = New-Object System.Windows.Forms.Timer
  $script:TestZegar.Interval = 300
  $script:TestZegar.Add_Tick({
    $script:TestZegar.Stop()
    try {
      $script:TestRaport.Ramka = "$($script:Okno.FormBorderStyle)"; $script:TestRaport.MaksBox = $script:Okno.MaximizeBox
      $script:TestRaport.Szer = $script:Okno.Width; $script:TestRaport.Wys = $script:Okno.Height
      $script:TestRaport.MinSzer = $script:Okno.MinimumSize.Width; $script:TestRaport.MinWys = $script:Okno.MinimumSize.Height
      if ('__PRZED__') { [void](T-Kliknij '__PRZED__'); T-Pompuj 300 }
      $script:TestRaport.Okno = "$($script:Okno.Bounds)"; $script:TestRaport.Ekran = "$([System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea)"
      $script:TestRaport.Tytul = $script:Okno.Text; $script:TestRaport.KlientSzer = $script:Okno.ClientSize.Width; $script:TestRaport.KlientWys = $script:Okno.ClientSize.Height
      T-Sprawdz
      if (__ROZCIAGNIJ__) { T-Rozciagnij }
      if (-not $script:Okno.IsDisposed) { $script:TestRaport.Koniec = "$($script:Okno.Left),$($script:Okno.Top),$($script:Okno.Width),$($script:Okno.Height)" }
      if ('__KLIK__') { $script:TestRaport.Klik = T-Kliknij '__KLIK__' }
    } catch { $script:TestRaport.Wywrotka = "$($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)" }
    [System.IO.File]::WriteAllText('__RAPORT__', ($script:TestRaport | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
    if ((-not $script:Okno.IsDisposed) -and $script:Okno.Visible) { $script:Okno.Close() }
  })
  $f.Add_Shown({ $script:TestZegar.Start() })
'@
# Zamiast ShowDialog (modalne okno aktywuje sie): Show bez aktywacji i petla komunikatow do
# zamkniecia, z bezpiecznikiem - okno, ktore samo sie nie zamknie, zamykamy po 90 s.
$petla = @'
$f.Show()
  $t0 = [datetime]::Now
  while ($f.Visible -and (([datetime]::Now - $t0).TotalSeconds -lt 90)) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 }
  if ($f.Visible) { [System.IO.File]::WriteAllText('__RAPORT__.zwis', "okno nie zamknelo sie samo w 90 s"); $f.Close() }
'@

$zrodloSkryptu = [System.IO.File]::ReadAllText($oryginal, [System.Text.Encoding]::UTF8)
function Ile([string]$w, [string]$co) { return ([regex]::Matches($w, [regex]::Escape($co))).Count }
# Atrapy w kazdej kopii: nowa definicja zamiast naglowka prawdziwej, ktora dostaje inna nazwe
# (nikt jej nie wola). Zapisuja, z czym je wolano - zaden terminal, proces w tle ani MessageBox.
$atrapaTerminala = @'
function Otworz-Terminal([string]$kat, [string]$id, [string]$start) {
  $z = [ordered]@{ kat = $kat; id = $id; start = $start; skrypt = [System.IO.File]::ReadAllText($start, [System.Text.Encoding]::UTF8) }
  [System.IO.File]::AppendAllText('__LOG__', (($z | ConvertTo-Json -Compress) + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
  return "ATRAPA terminala"
}
function Otworz-Terminal-Nieuzywana([string]$kat, [string]$id, [string]$start) {
'@
$atrapaOdpal = @'
function Odpal-W-Tle($p, [string]$wznow = "") {
  $plikWz = ""; if ($wznow -and (Test-Path -LiteralPath $wznow)) { $plikWz = [System.IO.File]::ReadAllText($wznow, [System.Text.Encoding]::UTF8) }
  $z = [ordered]@{ id = "$($p.id)"; wznow = $wznow; plik = $plikWz }
  [System.IO.File]::AppendAllText('__LOG__', (($z | ConvertTo-Json -Compress) + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
  return "ATRAPA procesu w tle"
}
function Odpal-W-Tle-Nieuzywana($p, [string]$wznow = "") {
'@
$atrapaBledu = @'
function Pokaz-Blad([string]$tekst) { [System.IO.File]::AppendAllText('__LOG__', $tekst + "`r`n", (New-Object System.Text.UTF8Encoding($false))) }
function Pokaz-Blad-Nieuzywana([string]$tekst) {
'@
# Zapamietany rozmiar: atrapa bierze tylko rozmiar i zapisuje, co by przywrocila - polozenie z pliku
# (prawdziwy ekran) i maksymalizacja wyciagnelyby okno testu na ekran uzytkownika.
$atrapaPrzywroc = @'
function Przywroc-Rozmiar-Okna($f, $z) {
  $f.Size = $z.Prostokat.Size
  $script:TestPrzywrocone = "$($z.Prostokat.X),$($z.Prostokat.Y),$($z.Prostokat.Width),$($z.Prostokat.Height),$($z.Maks)"
}
function Przywroc-Rozmiar-Okna-Nieuzywana($f, $z) {
'@
# Kopia z podmianami; kazda kotwica musi wystapic dokladnie raz - inaczej porazka przygotowania,
# a nie test, ktory po cichu sprawdza nie to okno.
# -Zajety:$false pomija scenariusze z trzymanym schowkiem (ok. 12 s) w sabotazach, ktore ich nie oceniaja.
# -Przed / -Klik: napis przycisku, ktory hak kliknie przed pomiarem / po nim.
# -Rozciagnij: po pomiarze rozciagniecie, proba zejscia ponizej minimum i powrot (T-Rozciagnij).
function Kopia([string]$wariant, [hashtable[]]$podmiany, [bool]$Zajety = $true, [string]$Przed = "", [string]$Klik = "", [bool]$Rozciagnij = $false) {
  $raport = Join-Path $tmp "raport-$wariant.json"
  $zrzut = Join-Path $Zrzuty "terminy-okno-$wariant.png"
  $zrzutR = Join-Path $Zrzuty "terminy-okno-$wariant-rozciagniete.png"
  $wsp = @(
    @{ K = '$f = New-Object System.Windows.Forms.Form'; Z = $klasaOkna.TrimStart() },
    @{ K = '$f.TopMost = $true'; Z = '$f.TopMost = $false' },
    @{ K = '$f.ShowInTaskbar = $true'; Z = '$f.ShowInTaskbar = $false' },
    @{ K = '$f.StartPosition = "CenterScreen"'; Z = '$f.StartPosition = "Manual"; $f.Location = New-Object System.Drawing.Point(-5000, 0)' },
    @{ K = '$f.Add_Shown({ $f.Activate() })'; Z = $hak.Replace('__RAPORT__', $raport).Replace('__ZRZUT__', $zrzut).Replace('__TMP__', $tmp).Replace('__TRZYMACZ__', $trzymacz).Replace('__MS_KROTKO__', "$MS_TRZYMANIA_KROTKO").Replace('__MS_DLUGO__', "$MS_TRZYMANIA_DLUGO").Replace('__ZAJETY__', ('$' + "$($Zajety -and $Schowek)")).Replace('__SCHOWEK__', ('$' + "$([bool]$Schowek)")).Replace('__PRZED__', $Przed.Replace("'", "''")).Replace('__KLIK__', $Klik.Replace("'", "''")).Replace('__ROZCIAGNIJ__', ('$' + "$Rozciagnij")).Replace('__ZRZUT_ROZC__', $zrzutR) },
    @{ K = 'function Otworz-Terminal([string]$kat, [string]$id, [string]$start) {'; Z = $atrapaTerminala.Replace('__LOG__', $logTerminala).TrimEnd() },
    @{ K = 'function Odpal-W-Tle($p, [string]$wznow = "") {'; Z = $atrapaOdpal.Replace('__LOG__', $logOdpal).TrimEnd() },
    @{ K = 'function Pokaz-Blad([string]$tekst) {'; Z = $atrapaBledu.Replace('__LOG__', $logBledow).TrimEnd() },
    @{ K = 'function Przywroc-Rozmiar-Okna($f, $z) {'; Z = $atrapaPrzywroc.TrimEnd() },
    @{ K = '[void]$f.ShowDialog()'; Z = $petla.Replace('__RAPORT__', $raport) },
    @{ K = '"Local\MegaRuchacz-Terminy-Start"'; Z = '"Local\MegaRuchacz-Terminy-Start-TEST-OKNA"' },
    @{ K = '"Local\MegaRuchacz-Terminy-Okno"'; Z = '"Local\MegaRuchacz-Terminy-Okno-TEST-OKNA"' },
    # od cd43606 "przypomnij" idzie w tle; test sprawdza rysowanie okna, wiec kopia wymusza stara droge do okna
    @{ K = 'if ($p.status -eq "otwarte") {   # oba tryby'; Z = 'if ($p.status -eq "otwarte" -and $p.tryb -ne "sam") { $doOkna += $p; continue }; if ($p.status -eq "otwarte") {' })
  $kod = $zrodloSkryptu
  foreach ($p in @($wsp) + @($podmiany)) {
    $n = Ile $kod $p.K
    if ($n -ne 1) { throw "kopia '$wariant': kotwica wystepuje $n razy (ma byc 1): $($p.K)" }
    $kod = $kod.Replace($p.K, $p.Z)
  }
  # Bez -Schowek proby schowka w haku musza byc wylaczone - inaczej porazka przygotowania, nie
  # cichy zapis do schowka uzytkownika.
  if ((-not $Schowek) -and (-not $kod.Contains("if (`$False) {`r`n    # zaznaczenie calego pola"))) { throw "kopia '$wariant': proby schowka w haku nie sa wylaczone, a test idzie bez -Schowek" }
  foreach ($zakaz in @('.Activate()', 'SetForegroundWindow', 'ShowDialog', '$f.TopMost = $true', '$f.ShowInTaskbar = $true')) {
    if ($kod.Contains($zakaz)) { throw "kopia '$wariant' nadal zawiera '$zakaz' - okno mogloby wyskoczyc na ekran" }
  }
  $plik = Join-Path $tmp "terminy-$wariant.ps1"
  [System.IO.File]::WriteAllText($plik, $kod, $ZBom)
  return [pscustomobject]@{ Plik = $plik; Raport = $raport; Zrzut = $zrzut }
}

function Linie-Json([string]$f) {
  if (-not (Test-Path -LiteralPath $f)) { return @() }
  return @([System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8) -split "\r?\n" | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
}

# Kopia jako osobny proces: bez okna konsoli, wyjscie przechwycone, ubijana po 120 s.
# -Rozmiar: tresc pliku z rozmiarem okna przed startem (bez - pliku nie ma); -RozmiarKatalog: w jego
# miejscu katalog (odczyt i zapis rzucaja wyjatkiem).
function Uruchom($kopia, [string]$Rozmiar = "", [switch]$RozmiarKatalog) {
  [System.IO.File]::WriteAllLines($plikP, [string[]]$linie, $BezBom)
  foreach ($x in @($dziennik, $plikOkna, $plikRozmiaru, $kopia.Raport, "$($kopia.Raport).zwis", $logTerminala, $logOdpal, $logBledow)) { if (Test-Path -LiteralPath $x) { Remove-Item -LiteralPath $x -Force -Recurse } }
  if ($Rozmiar) { [System.IO.File]::WriteAllText($plikRozmiaru, $Rozmiar, $BezBom) }
  if ($RozmiarKatalog) { New-Item -ItemType Directory -Force -Path $plikRozmiaru | Out-Null }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$($kopia.Plik)`" -Zrodlo `"$Zrodlo`" -KatalogDomowy `"$dom`" -Plik `"$plikP`" -Dzis $dzis"
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  $p = [System.Diagnostics.Process]::Start($psi)
  $wy = $p.StandardOutput.ReadToEndAsync(); $bl = $p.StandardError.ReadToEndAsync()
  $zabity = $false
  if (-not $p.WaitForExit(120000)) { $p.Kill(); $p.WaitForExit(5000) | Out-Null; $zabity = $true }
  $r = [pscustomobject]@{ Kod = $p.ExitCode; Zabity = $zabity; Wyjscie = "$($wy.Result)$($bl.Result)".Trim(); Raport = $null; Dziennik = ""
                          Przypomnienia = [System.IO.File]::ReadAllText($plikP, [System.Text.Encoding]::UTF8)
                          Terminal = @(Linie-Json $logTerminala); Odpal = @(Linie-Json $logOdpal); Bledy = ""; Rozmiar = $null }
  if (Test-Path -LiteralPath $plikRozmiaru -PathType Leaf) { $r.Rozmiar = [System.IO.File]::ReadAllText($plikRozmiaru, [System.Text.Encoding]::UTF8) }
  if (Test-Path -LiteralPath $logBledow) { $r.Bledy = [System.IO.File]::ReadAllText($logBledow, [System.Text.Encoding]::UTF8).Trim() }
  if (Test-Path -LiteralPath $kopia.Raport) { $r.Raport = [System.IO.File]::ReadAllText($kopia.Raport, [System.Text.Encoding]::UTF8) | ConvertFrom-Json }
  if (Test-Path -LiteralPath $dziennik) { $r.Dziennik = [System.IO.File]::ReadAllText($dziennik, [System.Text.Encoding]::UTF8) }
  if (Test-Path -LiteralPath "$($kopia.Raport).zwis") { $r.Wyjscie += " | okno nie zamknelo sie samo (bezpiecznik 90 s)" }
  return $r
}

# Ocena jednego przebiegu - te same sprawdzenia dla wersji prawdziwej i sabotazy.
function Ocen($u) {
  $o = [ordered]@{}
  $r = $u.Raport
  $okPrzebieg = (-not $u.Zabity) -and ($u.Kod -eq 0) -and $r -and (-not $r.Wywrotka) -and ($u.Dziennik -notmatch 'WYWROTKA') -and
                ($u.Dziennik -notmatch 'samoczynne') -and ($u.Dziennik -match 'okno pokazane: (#[123](, )?){3}\r?\n') -and ($r.Watek -eq "STA") -and (@($r.Uwagi).Count -eq 0)
  $o["przebieg"] = @($okPrzebieg, "kod $($u.Kod), zabity=$($u.Zabity), watek $($r.Watek), wywrotka '$($r.Wywrotka)', uwagi '$(@($r.Uwagi) -join '; ')', wyjscie '$($u.Wyjscie)'")
  if (-not $r) { foreach ($n in @("pola", "wlasciwosci", "zaznaczenie", "kopiuj", "kopiuj-zajety", "kopiuj-blad", "uciecie")) { $o[$n] = @($false, "brak raportu z okna") }; return $o }
  $k = @($r.Kontrolki | Where-Object { $_.Widoczny })
  $pola = @($k | Where-Object { $_.Typ -eq "TextBox" })
  $etykiety = @($k | Where-Object { $_.Typ -eq "Label" })
  $glowy = @{}
  foreach ($id in 1..3) { $g = @($k | Where-Object { $_.Tekst -match "^#$id   \S+ \(.+\)   $([regex]::Escape($projekt))$" }); if ($g.Count -eq 1) { $glowy[$id] = $g[0] } }
  $szukane = @(
    @{ Co = "wstep"; Pole = @($k | Where-Object { $_.Tekst -like "Te sprawy mają termin dziś*krzyżykiem*" }) },
    @{ Co = "uwaga #3"; Pole = @($k | Where-Object { $_.Tekst -like "Uruchomione 2026-10-01, ale nie zostało dokończone*" }) })
  foreach ($id in 1..3) {
    $szukane += @{ Co = "naglowek #$id"; Pole = @($glowy[$id] | Where-Object { $_ }) }
    $szukane += @{ Co = "tresc #$id"; Pole = @($k | Where-Object { $_.Tekst -ceq $trescPola[$id] }) }
  }
  $zle = @($szukane | Where-Object { ($_.Pole.Count -ne 1) -or ($_.Pole[0].Typ -ne "TextBox") } | ForEach-Object { "$($_.Co): $(@($_.Pole | ForEach-Object { $_.Typ }) -join '+')" })
  $o["pola"] = @((($zle.Count -eq 0) -and ($etykiety.Count -eq 0)), "pol tekstowych $($pola.Count), Label $($etykiety.Count); nie w polu: $($zle -join '; ')")

  $zleW = @()
  foreach ($p in $pola) {
    $kol = $CZARNY; if ($p.Tekst -like "Uruchomione 2026-10-01*") { $kol = $CZERWONY }
    if (-not ($p.ReadOnly -and $p.Multiline -and ($p.Ramka -eq "None") -and ($p.Paski -eq "None") -and (-not $p.TabStop) -and $p.Wlaczony -and
              ($p.Tlo -eq $p.TloRodzica) -and ($p.Kolor -eq $kol))) {
      $zleW += "'$($p.Tekst.Substring(0, [Math]::Min(25, $p.Tekst.Length)))' ro=$($p.ReadOnly) ml=$($p.Multiline) ramka=$($p.Ramka) paski=$($p.Paski) tab=$($p.TabStop) wl=$($p.Wlaczony) tlo=$($p.Tlo)/$($p.TloRodzica) kolor=$($p.Kolor)/$kol"
    }
  }
  $o["wlasciwosci"] = @((($pola.Count -gt 0) -and ($zleW.Count -eq 0)), "tylko do odczytu, bez ramki i paskow, poza Tab, w kolorze tla: $(if ($pola.Count -eq 0) { 'nie ma ani jednego pola' } elseif ($zleW) { $zleW -join '; ' } else { 'wszystkie' })")

  $skop = @($r.Zaznaczenia | ForEach-Object { $_.Schowek })
  $zleZ = @($r.Zaznaczenia | Where-Object { $_.Schowek -cne $_.Tekst } | ForEach-Object { "'$($_.Tekst.Substring(0, [Math]::Min(25, $_.Tekst.Length)))' -> schowek '$("$($_.Schowek)".Substring(0, [Math]::Min(25, "$($_.Schowek)".Length)))'" })
  $brak = @(1..3 | Where-Object { $skop -cnotcontains $trescPola[$_] } | ForEach-Object { "#$_" })
  $frag = $r.Fragment -and ($r.Fragment.Schowek -ceq $r.Fragment.Oczekiwany)
  $o["zaznaczenie"] = @((($zleZ.Count -eq 0) -and ($brak.Count -eq 0) -and $frag), "zaznaczonych i skopiowanych $($skop.Count); zle: $($zleZ -join '; '); tresci nie skopiowane: $($brak -join ', '); fragment: $frag")

  $zleK = @()
  foreach ($id in 1..3) {
    $w = @($r.Kopiuj | Where-Object { $_.Nazwa -eq "Kopiuj #$id" })
    if ($w.Count -ne 1) { $zleK += "#${id}: przyciskow $($w.Count)"; continue }
    if (-not $glowy[$id]) { $zleK += "#${id}: nie ma naglowka"; continue }
    $ocz = $glowy[$id].Tekst + "`r`n" + $trescPola[$id]
    if ($w[0].Schowek -cne $ocz) { $zleK += "#${id}: schowek '$($w[0].Schowek)'" }
    if ($w[0].NapisPo -ne "Skopiowano") { $zleK += "#${id}: napis po kliknieciu '$($w[0].NapisPo)'" }
    if ($w[0].NapisPozniej -ne "Kopiuj") { $zleK += "#${id}: napis po chwili '$($w[0].NapisPozniej)'" }
  }
  $o["kopiuj"] = @(($zleK.Count -eq 0), "naglowek + tresc w schowku, 'Skopiowano' i powrot do 'Kopiuj': $(if ($zleK) { $zleK -join '; ' } else { 'trzy przyciski' })")

  $z = $r.KopiujZajety
  $oczZ = $null; if ($z -and ($z.Nazwa -match '^Kopiuj #(\d)$') -and $glowy[[int]$Matches[1]]) { $oczZ = $glowy[[int]$Matches[1]].Tekst + "`r`n" + $trescPola[[int]$Matches[1]] }
  $tekstZ = ($null -ne $oczZ) -and ($z.Schowek -ceq $oczZ)
  $o["kopiuj-zajety"] = @(($z -and $z.ZajetyPrzed -and ($z.NapisPo -eq "Skopiowano") -and ($z.NapisPozniej -eq "Kopiuj") -and $tekstZ),
                          "schowek trzymany $($z.TrzymanoMs) ms, zajety przy kliknieciu: $($z.ZajetyPrzed); klik $($z.CzasKlikniecia) ms, napis '$($z.NapisPo)', po chwili '$($z.NapisPozniej)', tekst w schowku: $tekstZ")

  $b = $r.KopiujBlad
  $wpis = $b -and ($u.Dziennik -match "przycisk $([regex]::Escape($b.Nazwa)) - NIE SKOPIOWALEM do schowka: schowek zajety przez inny program")
  $o["kopiuj-blad"] = @(($b -and $b.ZajetyPrzed -and $b.ZajetyPo -and ($b.NapisPo -eq "Nie skopiowano") -and ($b.NapisPozniej -eq "Nie skopiowano") -and $wpis),
                        "schowek trzymany $($b.TrzymanoMs) ms, zajety przed/po kliknieciu: $($b.ZajetyPrzed)/$($b.ZajetyPo); klik $($b.CzasKlikniecia) ms, napis '$($b.NapisPo)', po chwili '$($b.NapisPozniej)', wpis w dzienniku: $wpis")

  $zleU = @()
  foreach ($p in $pola) {
    if (($p.PierwszaY -ne 0) -or (($p.OstatniaY + $p.WysCzcionki) -gt $p.WysWnetrza) -or ($p.Prawa -gt $p.SzerRodzica)) {
      $zleU += "'$($p.Tekst.Substring(0, [Math]::Min(25, $p.Tekst.Length)))' linii $($p.Linii), ostatnia y=$($p.OstatniaY)+$($p.WysCzcionki) > wys $($p.WysWnetrza), pierwsza y=$($p.PierwszaY), prawa $($p.Prawa)/$($p.SzerRodzica)"
    }
  }
  $dluga = @($pola | Where-Object { $_.Tekst -ceq $trescPola[2] })
  $linii = 0; if ($dluga.Count -eq 1) { $linii = $dluga[0].Linii }
  $o["uciecie"] = @((($linii -ge 5) -and ($zleU.Count -eq 0) -and ($pola.Count -gt 0)), "dluga tresc #2: linii $linii, wys $(@($dluga | ForEach-Object { $_.WysWnetrza }) -join ''); uciete: $(if ($zleU) { $zleU -join '; ' } else { 'zadne' })")
  return $o
}

$OPISY = [ordered]@{
  "przebieg" = "kopia z oknem przeszla bez wywrotki, nic nie uruchomila sama"
  "pola" = "wstep, naglowki, tresci i uwaga sa w polach tekstowych, zadnego Label"
  "wlasciwosci" = "pola tylko do odczytu, bez ramki i paskow, w kolorze tla, kolory jak dawniej"
  "zaznaczenie" = "zaznaczenie i skopiowanie pola daje w schowku dokladnie tresc"
  "kopiuj" = "przycisk Kopiuj wklada do schowka naglowek i tresc"
  "kopiuj-zajety" = "schowek chwile zajety przez inny program: Kopiuj czeka i kopiuje"
  "kopiuj-blad" = "schowek dlugo zajety: 'Nie skopiowano' zostaje na przycisku i jest wpis w dzienniku"
  "uciecie" = "dluga tresc (kilka linii) miesci sie bez uciecia"
}

# ---------------------------------------------------------------- okno niepowodzenia
$jutro = (Get-Date).AddDays(1).ToString("yyyy-MM-dd")
$POWOD_NIEP = "Claude nie mógł się zalogować, bo kilka okien naraz odnawiało logowanie (Claude Code zakończył się kodem 1: Failed to refresh OAuth token); prób: 3 z 3"
$MD_NIEP = Join-Path $katMr "przypomnienia-wyniki\1.md"
# Kopia pokazuje okno niepowodzenia dla #1 zamiast zwyklego okna (te same atrapy okna i zegar).
$NIEPOWODZENIE = @{ K = 'try { Okno-Przypomnien $doOkna } finally {'
                    Z = "try { Okno-Niepowodzenia @(`$doOkna | Where-Object { `$_.id -eq 1 })[0] ([pscustomobject]@{ Powod = '$POWOD_NIEP' }) `$true '' '$MD_NIEP' '$jutro' } finally {" }

function Ocen-Niepowodzenia($u) {
  $o = [ordered]@{}
  $r = $u.Raport
  $ok = (-not $u.Zabity) -and ($u.Kod -eq 0) -and $r -and (-not $r.Wywrotka) -and ($u.Dziennik -notmatch 'WYWROTKA') -and
        ($u.Dziennik -match 'okno niepowodzenia pokazane: #1\r?\n') -and ($r.Watek -eq "STA") -and (@($r.Uwagi).Count -eq 0)
  $o["przebieg"] = @($ok, "kod $($u.Kod), zabity=$($u.Zabity), wywrotka '$($r.Wywrotka)', uwagi '$(@($r.Uwagi) -join '; ')', wyjscie '$($u.Wyjscie)'")
  if (-not $r) { foreach ($n in @("teksty", "przyciski", "krzyzyk", "uciecie")) { $o[$n] = @($false, "brak raportu z okna") }; return $o }
  $k = @($r.Kontrolki | Where-Object { $_.Widoczny })
  $pola = @($k | Where-Object { $_.Typ -eq "TextBox" })
  $uwaga = "Nie udało się wykonać przypomnienia #1 ($($tresc1.TrimEnd('.'))), bo: $POWOD_NIEP. Przeniesione na jutro.`r`nPełny raport: $MD_NIEP"
  $szukane = @(
    @{ Co = "wstep"; Kolor = $CZARNY; Pole = @($pola | Where-Object { $_.Tekst -like "Automat nie zdołał wykonać tego przypomnienia*krzyżykiem = zostaje na jutro." }) },
    @{ Co = "naglowek z terminem jutro"; Kolor = $CZARNY; Pole = @($pola | Where-Object { $_.Tekst -ceq "#1   $jutro (jutro)   $projekt" }) },
    @{ Co = "tresc"; Kolor = $CZARNY; Pole = @($pola | Where-Object { $_.Tekst -ceq $trescPola[1] }) },
    @{ Co = "zdanie o niepowodzeniu"; Kolor = $CZERWONY; Pole = @($pola | Where-Object { $_.Tekst -ceq $uwaga }) })
  $zle = @($szukane | Where-Object { ($_.Pole.Count -ne 1) -or ($_.Pole[0].Kolor -ne $_.Kolor) } | ForEach-Object { "$($_.Co): pol $($_.Pole.Count)" })
  $etykiety = @($k | Where-Object { $_.Typ -eq "Label" })
  $o["teksty"] = @((($zle.Count -eq 0) -and ($etykiety.Count -eq 0) -and ($pola.Count -eq 4)), "pol $($pola.Count), Label $($etykiety.Count); zle: $($zle -join '; '); pola: $(@($pola | ForEach-Object { "'$($_.Tekst.Substring(0, [Math]::Min(40, $_.Tekst.Length)))'" }) -join ', ')")
  $przyc = @($k | Where-Object { $_.Typ -eq "Button" } | ForEach-Object { "$($_.Tekst)=$($_.Akcja)" })
  $o["przyciski"] = @((($przyc -join ", ") -ceq "Spróbuj teraz=sprobuj, Odłóż na jutro=odloz, Kopiuj="), "przyciski: $($przyc -join ', ')")
  $odl = (Test-Path -LiteralPath $plikOkna) -and ((Czytaj-Okno) -match 'odlozone_do')
  $o["krzyzyk"] = @((($u.Dziennik -match 'okno niepowodzenia zamkniete krzyzykiem - zostaje na jutro') -and (-not $odl) -and ($u.Dziennik -notmatch 'wroce o')),
                    "wpis 'zostaje na jutro': $($u.Dziennik -match 'zostaje na jutro'); odlozone_do w przypomnienia-okno.txt: $odl")
  $zleU = @($pola | Where-Object { ($_.PierwszaY -ne 0) -or (($_.OstatniaY + $_.WysCzcionki) -gt $_.WysWnetrza) -or ($_.Prawa -gt $_.SzerRodzica) } | ForEach-Object { "'$($_.Tekst.Substring(0, [Math]::Min(25, $_.Tekst.Length)))'" })
  $o["uciecie"] = @((($pola.Count -gt 0) -and ($zleU.Count -eq 0)), "uciete: $(if ($zleU) { $zleU -join '; ' } else { 'zadne' })")
  return $o
}
function Czytaj-Okno { return [System.IO.File]::ReadAllText($plikOkna, [System.Text.Encoding]::UTF8) }
$OPISY_NIEP = [ordered]@{
  "przebieg" = "okno niepowodzenia: kopia przeszla bez wywrotki, wpis 'okno niepowodzenia pokazane'"
  "teksty" = "okno niepowodzenia: wstep, naglowek z terminem jutro, tresc i czerwone zdanie 'Nie udalo sie ... Przeniesione na jutro' w polach"
  "przyciski" = "okno niepowodzenia: przyciski Sprobuj teraz / Odloz na jutro / Kopiuj, bez Zrob teraz / Jutro / Zrobione"
  "krzyzyk" = "okno niepowodzenia: krzyzyk = zostaje na jutro, nic nie odklada o 2 godziny"
  "uciecie" = "okno niepowodzenia: dlugi powod miesci sie bez uciecia"
}

# ---------------------------------------------------------------- okno decyzji
$MD_DEC = Join-Path $katMr "przypomnienia-wyniki\1.md"
$SESJA_DEC = "sesja-okno-decyzji"
$TYTUL_DEC = "Przypomnienie #1 – potrzebna Twoja decyzja"
$PYT = "Grafiki PT02: od czego zacząć poprawę niemieckich tekstów?"
$OPCJE = @("Jeden zapach na próbę", "Od razu wszystkie")
$PYT_DL = ("Grafiki PT02 dla wszystkich zapachów: w opisach po niemiecku są literówki i zdania przetłumaczone słowo w słowo, " +
           "a część napisów na zdjęciach nie mieści się w ramkach. Od czego zacząć poprawę, żeby jak najszybciej było widać efekt w sprzedaży?")
# Ok. 730 px przy 11 pkt (zmierzone): dwa wiersze przy 600 px, jeden po rozciagnieciu o 300 px.
$OPCJA_SR = "Najpierw zapachy z największą sprzedażą na Amazon DE w ostatnich 14 miesiącach, potem reszta"
$OPCJE_DL = @("Lawenda na próbę", "Od razu wszystkie zapachy",
              "Najpierw tylko te zapachy, które w ostatnich 14 miesiącach miały najwięcej zakupów z wyszukiwania na Amazon DE, a resztę zostaw na później, gdy zobaczymy wynik",
              "Wstrzymaj & wróć za tydzień")
$ZROB = 'Kliknij w Seller Central „Zatwierdź wysyłkę” dla wysyłki FBA15K do magazynu w Niemczech.'   # „” to dla PS cudzyslow - tylko w '...'
$RAPORT_DEC = "WYNIK: POTRZEBUJE_CIEBIE: ...`r`n`r`nSprawdziłem grafiki PT02 w 12 zapachach.`r`nZażółć gęślą jaźń - polskie litery w raporcie."
$RAPORT_DL = $RAPORT_DEC + (@(1..30 | ForEach-Object { "`r`nLinia $_ raportu: co sprawdziłem i co wyszło w zapachu numer $_." }) -join "")
function Napis-PS([string]$t) { return "'" + $t.Replace("'", "''") + "'" }
# Kopia pokazuje okno decyzji dla #1 zamiast zwyklego okna; $w jak z Ocen-Przebieg.
function Wstaw-Decyzje([string]$rodzaj, [string]$zdanie, [string[]]$opcje, [string]$raport) {
  $op = (@($opcje) | ForEach-Object { Napis-PS $_ }) -join ", "
  $w = "([pscustomobject]@{ Wynik = 'czlowiek'; Rodzaj = $(Napis-PS $rodzaj); CoZrobic = $(Napis-PS $zdanie); Opcje = @($op); Sesja = $(Napis-PS $SESJA_DEC); Raport = $(Napis-PS $raport) })"
  return @{ K = 'try { Okno-Przypomnien $doOkna } finally {'
            Z = "try { Okno-Decyzji (@(`$doOkna | Where-Object { `$_.id -eq 1 })[0]) $w $(Napis-PS $projekt) 'C:\atrapa\claude.exe' $(Napis-PS $MD_DEC) } finally {" }
}

# $o: Przyciski - widoczne "napis=akcja" po kolei; Szczegoly - rozwiniete?; Raport - tekst w nich;
# Data - termin #1 po przebiegu; Dziennik - wzory, ktore musza stac; Terminal / Odpal - ile wywolan
# atrap; Klik - czy klik zamknal okno od razu; Wielowierszowy - napis przycisku, ktory musi sie zawinac.
function Ocen-Decyzji($u, [string]$zdanie, [hashtable]$o) {
  $wy = [ordered]@{}
  $r = $u.Raport
  $ok = (-not $u.Zabity) -and ($u.Kod -eq 0) -and $r -and (-not $r.Wywrotka) -and ($u.Dziennik -notmatch 'WYWROTKA') -and ($u.Dziennik -notmatch 'samoczynne') -and
        ($u.Dziennik -match 'okno decyzji pokazane: #1 \((pytanie|czynnosc)\)') -and ($r.Watek -eq "STA") -and (@($r.Uwagi).Count -eq 0) -and (-not $u.Bledy)
  $wy["przebieg"] = @($ok, "kod $($u.Kod), zabity=$($u.Zabity), wywrotka '$($r.Wywrotka)', uwagi '$(@($r.Uwagi) -join '; ')', ostrzezenia '$($u.Bledy)', wyjscie '$($u.Wyjscie)'")
  if (-not $r) { foreach ($n in @("teksty", "przyciski", "szczegoly", "uciecie", "po")) { $wy[$n] = @($false, "brak raportu z okna") }; return $wy }
  $k = @($r.Kontrolki | Where-Object { $_.Widoczny })
  $pola = @($k | Where-Object { $_.Typ -eq "TextBox" })
  $zd = @($pola | Where-Object { $_.Tekst -ceq $zdanie })
  $inne = @($k | Where-Object { ($_.Typ -ne "FlowLayoutPanel") -and ($_.Tekst -cne $zdanie) } | ForEach-Object { $_.Pkt } | Measure-Object -Maximum).Maximum
  $etykiety = @($k | Where-Object { $_.Typ -eq "Label" })
  $wy["teksty"] = @((($r.Tytul -ceq $TYTUL_DEC) -and ($zd.Count -eq 1) -and ($zd[0].Pkt -gt $inne) -and ($etykiety.Count -eq 0)),
                    "tytul '$($r.Tytul)', zdanie w polu: $($zd.Count) (czcionka $(@($zd | ForEach-Object { $_.Pkt }) -join '') pkt, reszta najwyzej $inne pkt), Label $($etykiety.Count)")
  $przyc = @($k | Where-Object { $_.Typ -eq "Button" } | ForEach-Object { "$($_.Tekst)=$($_.Akcja)" }) -join ", "
  $wy["przyciski"] = @(($przyc -ceq $o.Przyciski), "przyciski: $przyc")
  $rap = @($pola | Where-Object { $_.Tekst -cne $zdanie })
  $kop = @($r.Kopiuj | Where-Object { $_.NapisPo -eq "Skopiowano" })
  if ($o.Szczegoly) {
    $tekstSz = "Przypomnienie #1: $tresc1`r`nPełny raport: $MD_DEC`r`n`r`n$($o.Raport)"
    # Bez -Schowek tylko obecnosc przycisku Kopiuj (z -Schowek tez to, co wklada do schowka).
    $widacKopiuj = @($k | Where-Object { ($_.Typ -eq "Button") -and ($_.Tekst -eq "Kopiuj") }).Count -eq 1
    $okKop = $widacKopiuj -and ((-not $Schowek) -or (($kop.Count -eq 1) -and ($kop[0].Schowek -ceq $tekstSz)))
    $okSz = ($rap.Count -eq 1) -and ($rap[0].Tekst -ceq $tekstSz) -and $okKop
    $wy["szczegoly"] = @($okSz, "rozwiniete: pol z raportem $($rap.Count), tekst zgodny: $(($rap.Count -eq 1) -and ($rap[0].Tekst -ceq $tekstSz)), widac Kopiuj: $widacKopiuj, Kopiuj do schowka: $(if ($Schowek) { @($kop | ForEach-Object { $_.Schowek -ceq $tekstSz }) -join '' } else { 'nie sprawdzane (bez -Schowek)' })")
  } else {
    $wy["szczegoly"] = @((($rap.Count -eq 0) -and (@($k | Where-Object { $_.Tekst -eq "Kopiuj" }).Count -eq 0)), "zwiniete: widocznych pol poza zdaniem $($rap.Count), widoczny Kopiuj: $(@($k | Where-Object { $_.Tekst -eq 'Kopiuj' }).Count)")
  }
  $zleU = @()
  foreach ($c in $k | Where-Object { $_.Typ -ne "FlowLayoutPanel" }) {
    $nazwa = "'$($c.Tekst.Substring(0, [Math]::Min(25, $c.Tekst.Length)))'"
    if (($c.WOknieDol -gt $r.KlientWys) -or ($c.WOkniePrawa -gt $r.KlientSzer) -or ($c.Prawa -gt $c.SzerRodzica)) { $zleU += "$nazwa poza oknem (dol $($c.WOknieDol)/$($r.KlientWys), prawa $($c.WOkniePrawa)/$($r.KlientSzer))" }
    if (($c.Typ -eq "TextBox") -and ($c.Paski -eq "None") -and (($c.PierwszaY -ne 0) -or (($c.OstatniaY + $c.WysCzcionki) -gt $c.WysWnetrza))) { $zleU += "$nazwa uciete: linii $($c.Linii), ostatnia y=$($c.OstatniaY)+$($c.WysCzcionki) > $($c.WysWnetrza)" }
    if (($c.Typ -eq "Button") -and ($c.Potrzebna -gt $c.Wys)) { $zleU += "$nazwa przycisk za niski: $($c.Wys) < $($c.Potrzebna)" }
  }
  if ($o.Wielowierszowy) {
    $b = @($k | Where-Object { ($_.Typ -eq "Button") -and ($_.Tekst -ceq $o.Wielowierszowy) })
    $jeden = @($k | Where-Object { ($_.Typ -eq "Button") -and ($_.Akcja -eq "opcja") -and ($_.Tekst -cne $o.Wielowierszowy) } | ForEach-Object { $_.Wys } | Measure-Object -Maximum).Maximum
    if (($b.Count -ne 1) -or ($b[0].Wys -le $jeden)) { $zleU += "dluga odpowiedz nie zawinieta: wys $(@($b | ForEach-Object { $_.Wys }) -join '') przy jednowierszowych $jeden" }
  }
  $wy["uciecie"] = @((($zleU.Count -eq 0) -and ($pola.Count -gt 0)), "okno $($r.KlientSzer)x$($r.KlientWys); $(if ($zleU) { $zleU -join '; ' } else { 'nic nie uciete' })")
  $zleP = @()
  $data = [regex]::Match($u.Przypomnienia, "(?m)^- \[.\] #1 (\d{4}-\d{2}-\d{2}) ").Groups[1].Value
  if ($data -ne $o.Data) { $zleP += "termin #1 '$data' zamiast '$($o.Data)'" }
  foreach ($wz in @($o.Dziennik)) { if ($u.Dziennik -notmatch $wz) { $zleP += "w dzienniku brak '$wz'" } }
  if ($u.Terminal.Count -ne $o.Terminal) { $zleP += "terminali $($u.Terminal.Count) zamiast $($o.Terminal)" }
  if ($u.Odpal.Count -ne $o.Odpal) { $zleP += "procesow w tle $($u.Odpal.Count) zamiast $($o.Odpal)" }
  if ($o.Klik -and -not ($r.Klik -and $r.Klik.Zamkniete -and ($r.Klik.Ms -lt 3000))) { $zleP += "klik nie zamknal okna od razu: $($r.Klik | ConvertTo-Json -Compress)" }
  if ($o.Po) { $zleP += @(& $o.Po $u) }
  $wy["po"] = @(($zleP.Count -eq 0), "$(if ($zleP) { $zleP -join '; ' } else { "termin #1 $data, terminali $($u.Terminal.Count), procesow w tle $($u.Odpal.Count)" })")
  return $wy
}
$OPISY_DEC = [ordered]@{
  "przebieg" = "przeszla bez wywrotki i bez ostrzezen, wpis 'okno decyzji pokazane'"
  "teksty" = "tytul 'Przypomnienie #1 – potrzebna Twoja decyzja', zdanie w polu i wieksza czcionka niz reszta, zadnego Label"
  "przyciski" = "wlasciwe przyciski po kolei"
  "szczegoly" = "szczegoly (raport Claude + Kopiuj) zwiniete albo po rozwinieciu kompletne i kopiowalne"
  "uciecie" = "nic nie wystaje poza okno, tekst pol i przyciskow bez uciecia"
  "po" = "po zamknieciu / kliknieciu: termin, dziennik, terminal i proces w tle jak trzeba"
}
$PRZYC_PYT = "Jeden zapach na próbę=opcja, Od razu wszystkie=opcja, Odłóż na jutro=odloz, Otwórz rozmowę=rozmowa, Szczegóły ▸=szczegoly"
$WIADOMOSC_OPCJI = "Użytkownik wybrał: Od razu wszystkie. Kontynuuj zadanie."
$PRZYPADKI_DEC = [ordered]@{
  "decyzja" = @{ Opis = "okno decyzji (PYTANIE, makieta), krzyzyk"; Wstaw = (Wstaw-Decyzje "pytanie" $PYT $OPCJE $RAPORT_DEC); Zdanie = $PYT
    O = @{ Przyciski = $PRZYC_PYT; Data = $jutro; Terminal = 0; Odpal = 0; Dziennik = @('okno decyzji #1 zamkniete krzyzykiem - na jutro - ok') } }
  "decyzja-dluga" = @{ Opis = "okno decyzji: dlugie pytanie i 4 odpowiedzi, jedna dluzsza niz okno"; Wstaw = (Wstaw-Decyzje "pytanie" $PYT_DL $OPCJE_DL $RAPORT_DEC); Zdanie = $PYT_DL; Rozciagnij = $OPCJE_DL[2]; Szerszy = $true
    O = @{ Przyciski = ((@($OPCJE_DL | ForEach-Object { "$_=opcja" }) + @("Odłóż na jutro=odloz", "Otwórz rozmowę=rozmowa", "Szczegóły ▸=szczegoly")) -join ", ")
           Data = $jutro; Terminal = 0; Odpal = 0; Dziennik = @('zamkniete krzyzykiem - na jutro - ok'); Wielowierszowy = $OPCJE_DL[2] } }
  "decyzja-srednia" = @{ Opis = "okno decyzji: odpowiedz zawinieta przy 600 px, w jednym wierszu po rozciagnieciu"; Wstaw = (Wstaw-Decyzje "pytanie" $PYT @($OPCJE[0], $OPCJA_SR) $RAPORT_DEC); Zdanie = $PYT; Rozciagnij = $OPCJA_SR
    O = @{ Przyciski = "$($OPCJE[0])=opcja, $OPCJA_SR=opcja, Odłóż na jutro=odloz, Otwórz rozmowę=rozmowa, Szczegóły ▸=szczegoly"
           Data = $jutro; Terminal = 0; Odpal = 0; Dziennik = @('zamkniete krzyzykiem - na jutro - ok'); Wielowierszowy = $OPCJA_SR } }
  "decyzja-czynnosc" = @{ Opis ="okno decyzji (ZROB) z rozwinietymi szczegolami (dlugi raport)"; Wstaw = (Wstaw-Decyzje "czynnosc" $ZROB @() $RAPORT_DL); Zdanie = $ZROB; Przed = "Szczegóły ▸"; Rozciagnij = $ZROB
    O = @{ Przyciski = "Zrobione=zrobilem, Odłóż na jutro=odloz, Otwórz rozmowę=rozmowa, Szczegóły ▾=szczegoly, Kopiuj="; Szczegoly = $true; Raport = $RAPORT_DL
           Data = $jutro; Terminal = 0; Odpal = 0; Dziennik = @('przycisk Szczegoly #1: rozwiniete', 'zamkniete krzyzykiem - na jutro - ok') } }
  "decyzja-opcja" = @{ Opis = "klik odpowiedzi: wznowienie tej rozmowy w tle, okno od razu zamkniete, bez terminala"; Wstaw = (Wstaw-Decyzje "pytanie" $PYT $OPCJE $RAPORT_DEC); Zdanie = $PYT; Klik = "Od razu wszystkie"
    O = @{ Przyciski = $PRZYC_PYT; Data = $dzis; Terminal = 0; Odpal = 1; Klik = $true; Dziennik = @("przycisk 'Od razu wszystkie' #1: wznawiam rozmowe '$SESJA_DEC' w tle", 'okno decyzji zamkniete - obsluzone')
           Po = { param($u)
             $z = @()
             if ($u.Odpal.Count -eq 1) {
               $wz = $null; try { $wz = $u.Odpal[0].plik | ConvertFrom-Json } catch { $z += "plik wznowienia nieczytelny: '$($u.Odpal[0].plik)'" }
               if ("$($u.Odpal[0].id)" -ne "1" -or -not $wz -or $wz.sesja -ne $SESJA_DEC -or $wz.wiadomosc -cne $WIADOMOSC_OPCJI) { $z += "wznowienie: id '$($u.Odpal[0].id)', plik '$($u.Odpal[0].plik)'" }
             }
             $z } } }
  "decyzja-odloz" = @{ Opis = "klik 'Odloz na jutro': na jutro, okno zamkniete, nic w tle"; Wstaw = (Wstaw-Decyzje "pytanie" $PYT $OPCJE $RAPORT_DEC); Zdanie = $PYT; Klik = "Odłóż na jutro"
    O = @{ Przyciski = $PRZYC_PYT; Data = $jutro; Terminal = 0; Odpal = 0; Klik = $true; Dziennik = @('przycisk Odloz na jutro #1 - ok', 'okno decyzji zamkniete - obsluzone') } }
  "decyzja-rozmowa" = @{ Opis = "klik 'Otworz rozmowe': terminal z claude --resume tej rozmowy, zostaje na dzis"; Wstaw = (Wstaw-Decyzje "pytanie" $PYT $OPCJE $RAPORT_DEC); Zdanie = $PYT; Klik = "Otwórz rozmowę"
    O = @{ Przyciski = $PRZYC_PYT; Data = $dzis; Terminal = 1; Odpal = 0; Klik = $true; Dziennik = @('przycisk Otworz rozmowe #1: ATRAPA terminala \(zostaje w toku\)')
           Po = { param($u) if (($u.Terminal.Count -eq 1) -and -not "$($u.Terminal[0].skrypt)".Contains("--resume '$SESJA_DEC'")) { "terminal bez --resume '$SESJA_DEC'" } } } }
}

# ---------------------------------------------------------------- rozciaganie i zapamietany rozmiar
# Okna da sie rozciagac i maksymalizowac (2026-10-14): ramka Sizable, MaximizeBox, MinimumSize = rozmiar
# z kodu; pola i przyciski rosna z szerokoscia okna (T-Rozciagnij: +300 px), rozmiar zapisany przy
# zamknieciu w przypomnienia-okno-rozmiar.txt i przywracany przy otwarciu (atrapa Przywroc-Rozmiar-Okna).
# Domyslny rozmiar zwyklego okna z 3 sprawami: terminy.ps1, 780 x min(760, 170 + 150 * 3).
$SZER_DOM = 780; $WYS_DOM = 620
$ROZC_SZER = 300
$SZEROKOSC_DECYZJI = 600   # jak w terminy.ps1
$PASEK = [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth
function Skrot([string]$t) { return $t.Substring(0, [Math]::Min(25, $t.Length)) }

# $baza - szerokosc najszerszego pola przy rozmiarze z kodu (wyglad jak dotad); $mniej - napis pola
# albo przycisku, ktory po rozciagnieciu musi byc nizszy (mniej linii) albo - z -Szerszy - o tyle
# szerszy, o ile okno, i nie wyzszy (przycisk, ktory i przy +300 px ma dwa wiersze).
function Ocen-Rozmiar($u, [string]$rodzaj, [int]$baza, [string]$mniej, [switch]$Szerszy) {
  $o = [ordered]@{}
  $r = $u.Raport
  $ok = (-not $u.Zabity) -and ($u.Kod -eq 0) -and $r -and (-not $r.Wywrotka) -and ($u.Dziennik -notmatch 'WYWROTKA') -and (@($r.Uwagi).Count -eq 0) -and
        ($u.Dziennik -notmatch 'nie dopasowala sie|rozmiar okna przypomnien')
  $o["przebieg"] = @($ok, "kod $($u.Kod), zabity=$($u.Zabity), wywrotka '$($r.Wywrotka)', uwagi '$(@($r.Uwagi) -join '; ')', wyjscie '$($u.Wyjscie)'")
  if ((-not $r) -or (-not $r.Rozciagniete)) { foreach ($n in @("ramka", "domyslny", "rosnie", "minimum", "powrot", "zapis")) { $o[$n] = @($false, "brak raportu z rozciagniecia") }; return $o }
  $o["ramka"] = @((($r.Ramka -eq "Sizable") -and ($r.MaksBox -eq $true) -and ($r.MinSzer -eq $r.Szer) -and ($r.MinWys -eq $r.Wys)),
                  "ramka $($r.Ramka), maksymalizacja $($r.MaksBox), okno $($r.Szer)x$($r.Wys), MinimumSize $($r.MinSzer)x$($r.MinWys)")
  $pola0 = @($r.Kontrolki | Where-Object { $_.Widoczny -and ($_.Typ -eq "TextBox") })
  $szer0 = ($pola0 | Measure-Object Szer -Maximum).Maximum
  $o["domyslny"] = @(($szer0 -eq $baza), "przy rozmiarze z kodu najszersze pole $szer0 px (ma byc $baza - wyglad jak dotad)")
  $k1 = @($r.Rozciagniete.Kontrolki | Where-Object { $_.Widoczny })
  $zle = @()
  foreach ($p in $pola0) {
    $po = @($k1 | Where-Object { ($_.Typ -eq "TextBox") -and ($_.Tekst -ceq $p.Tekst) })
    if ($po.Count -ne 1) { $zle += "'$(Skrot $p.Tekst)': po rozciagnieciu pol $($po.Count)"; continue }
    $przyr = $po[0].Szer - $p.Szer
    if (($przyr -lt ($ROZC_SZER - $PASEK)) -or ($przyr -gt $ROZC_SZER)) { $zle += "'$(Skrot $p.Tekst)' uroslo o $przyr px" }
    if ($po[0].Linii -gt $p.Linii) { $zle += "'$(Skrot $p.Tekst)' linii $($p.Linii) -> $($po[0].Linii)" }
  }
  foreach ($c in @($k1 | Where-Object { $_.Typ -ne "FlowLayoutPanel" })) {
    if ($c.WLisciePrawa -gt $c.ListaSzer) { $zle += "'$(Skrot $c.Tekst)' wystaje w prawo ($($c.WLisciePrawa) > $($c.ListaSzer))" }
    if (($c.Typ -eq "TextBox") -and ($c.Paski -eq "None") -and (($c.PierwszaY -ne 0) -or (($c.OstatniaY + $c.WysCzcionki) -gt $c.WysWnetrza))) { $zle += "'$(Skrot $c.Tekst)' uciete" }
    if (($c.Typ -eq "Button") -and ($c.Potrzebna -gt $c.Wys)) { $zle += "'$(Skrot $c.Tekst)' przycisk za niski: $($c.Wys) < $($c.Potrzebna)" }
  }
  if ($mniej) {
    $a = @($r.Kontrolki | Where-Object { $_.Widoczny -and ($_.Tekst -ceq $mniej) }); $b = @($k1 | Where-Object { $_.Tekst -ceq $mniej })
    $okM = ($a.Count -eq 1) -and ($b.Count -eq 1)
    if ($okM -and $Szerszy) { $okM = (($b[0].Szer - $a[0].Szer) -ge ($ROZC_SZER - $PASEK)) -and (($b[0].Szer - $a[0].Szer) -le $ROZC_SZER) -and ($b[0].Wys -le $a[0].Wys) }
    elseif ($okM) { $okM = $b[0].Wys -lt $a[0].Wys }
    if (-not $okM) { $zle += "'$(Skrot $mniej)' nie $(if ($Szerszy) { 'poszerzony' } else { 'nizszy' }): $(@($a | ForEach-Object { "$($_.Szer)x$($_.Wys)" }) -join '') -> $(@($b | ForEach-Object { "$($_.Szer)x$($_.Wys)" }) -join '')" }
  }
  $o["rosnie"] = @((($zle.Count -eq 0) -and ($pola0.Count -gt 0)), "okno $($r.Rozciagniete.Szer)x$($r.Rozciagniete.Wys): $(if ($zle) { $zle -join '; ' } else { "pola szersze o ok. $ROZC_SZER px, tekst zawiniety od nowa, nic nie uciete ani nie wystaje" })")
  $o["minimum"] = @((($r.Sciesnione.Szer -ge $r.Szer) -and ($r.Sciesnione.Wys -ge $r.Wys) -and ($r.Sciesnione.Szer -eq $r.MinSzer) -and ($r.Sciesnione.Wys -eq $r.MinWys)),
                    "proba 200x120: okno $($r.Sciesnione.Szer)x$($r.Sciesnione.Wys), rozmiar z kodu $($r.Szer)x$($r.Wys), MinimumSize $($r.MinSzer)x$($r.MinWys)")
  $szer2 = (@($r.Wrocone | Where-Object { $_.Widoczny -and ($_.Typ -eq "TextBox") }) | Measure-Object Szer -Maximum).Maximum
  $o["powrot"] = @(($szer2 -eq $baza), "po powrocie do rozmiaru z kodu najszersze pole $szer2 px (ma byc $baza)")
  $ocz = "${rodzaj}: $($r.Koniec),normalne"
  $o["zapis"] = @(("$($u.Rozmiar)".Trim() -ceq $ocz), "przypomnienia-okno-rozmiar.txt po zamknieciu: '$("$($u.Rozmiar)".Trim())' (ma byc '$ocz')")
  return $o
}
$OPISY_ROZ = [ordered]@{
  "przebieg" = "bez wywrotki i bez wpisow o rozmiarze w dzienniku"
  "ramka" = "ramka do rozciagania, maksymalizacja wlaczona, MinimumSize = rozmiar z kodu"
  "domyslny" = "przy rozmiarze z kodu pola maja dawna szerokosc"
  "rosnie" = "po rozciagnieciu pola i przyciski rosna, tekst sie zawija, nic nie uciete"
  "minimum" = "okno nie schodzi ponizej MinimumSize"
  "powrot" = "po powrocie do rozmiaru z kodu pola wracaja do dawnej szerokosci"
  "zapis" = "przy zamknieciu rozmiar i polozenie zapisane w przypomnienia-okno-rozmiar.txt"
}

# Zapamietany rozmiar zwyklego okna: Plik - zawartosc pliku przed startem; Przywrocone - co atrapa
# dostala ("" = nic); Szer/Wys - okno przy pomiarze; Baza - najszersze pole (pasek przewijania
# moze zabrac do $PASEK px); Wpis - wzory, ktore musza byc w dzienniku (bez - zadnego wpisu
# o rozmiarze); PlikPo - wzory pliku po zamknieciu.
$WA = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$XN = $WA.X + 40; $YN = $WA.Y + 40
$PRZYPADKI_PAMIECI = [ordered]@{
  "pamiec" = @{ Opis = "zapamietany rozmiar 1000x700 na ekranie wraca przy otwarciu, tresc szersza"
    Plik = "zwykle: $XN,$YN,1000,700,normalne`r`n"; Przywrocone = "$XN,$YN,1000,700,False"; Szer = 1000; Wys = 700; Baza = (720 + 1000 - $SZER_DOM)
    PlikPo = @('^zwykle: -5000,0,1000,700,normalne\r?\n$') }
  "pamiec-maks" = @{ Opis = "zapamietane okno zmaksymalizowane: rozmiar sprzed maksymalizacji + maks, linia innego okna zostaje w pliku"
    Plik = "niepowodzenie: 1,2,900,650,normalne`r`nzwykle: $XN,$YN,1000,700,maks`r`n"; Przywrocone = "$XN,$YN,1000,700,True"; Szer = 1000; Wys = 700; Baza = (720 + 1000 - $SZER_DOM)
    PlikPo = @('(?m)^niepowodzenie: 1,2,900,650,normalne\r?$', '(?m)^zwykle: -5000,0,1000,700,normalne\r?$') }
  "pamiec-mala" = @{ Opis = "zapamietany rozmiar mniejszy niz minimum: okno ma rozmiar z kodu"
    Plik = "zwykle: $XN,$YN,300,200,normalne"; Przywrocone = "$XN,$YN,300,200,False"; Szer = $SZER_DOM; Wys = $WYS_DOM; Baza = 720 }
  "pamiec-zepsuta" = @{ Opis = "negatywna: zepsuty plik rozmiaru - rozmiar domyslny i wpis w dzienniku, nie wyjatek"
    Plik = "zwykle: 12,abc`r`n`0`0śmieci ►"; Przywrocone = ""; Szer = $SZER_DOM; Wys = $WYS_DOM; Baza = 720
    Wpis = @('rozmiar okna przypomnien \(zwykle\) z .*nieczytelny zapis .* - rozmiar i polozenie domyslne'); PlikPo = @("^zwykle: -5000,0,$SZER_DOM,$WYS_DOM,normalne\r?\n$") }
  "pamiec-poza" = @{ Opis = "negatywna: zapamietane polozenie poza ekranem - rozmiar domyslny i wpis w dzienniku"
    Plik = "zwykle: -5000,0,1000,700,normalne"; Przywrocone = ""; Szer = $SZER_DOM; Wys = $WYS_DOM; Baza = 720
    Wpis = @('rozmiar okna przypomnien \(zwykle\): zapamietane polozenie -5000,0 1000x700 jest poza ekranem - rozmiar i polozenie domyslne') }
  "pamiec-katalog" = @{ Opis = "negatywna: plik rozmiaru nie do odczytu ani zapisu (katalog) - rozmiar domyslny, okno dziala, oba bledy w dzienniku"
    Katalog = $true; Przywrocone = ""; Szer = $SZER_DOM; Wys = $WYS_DOM; Baza = 720
    Wpis = @('rozmiar okna przypomnien \(zwykle\) z .* - rozmiar i polozenie domyslne', 'rozmiar okna przypomnien \(zwykle\): nie zapisalem do ') }
}
function Ocen-Pamieci($u, [hashtable]$c) {
  $o = [ordered]@{}
  $r = $u.Raport
  $ok = (-not $u.Zabity) -and ($u.Kod -eq 0) -and $r -and (-not $r.Wywrotka) -and ($u.Dziennik -notmatch 'WYWROTKA') -and (@($r.Uwagi).Count -eq 0) -and
        ($u.Dziennik -match 'okno pokazane: ')
  $o["przebieg"] = @($ok, "kod $($u.Kod), zabity=$($u.Zabity), wywrotka '$($r.Wywrotka)', wyjscie '$($u.Wyjscie)'$(if (-not $ok) { ", dziennik '$($u.Dziennik.Trim() -replace '\r?\n', ' | ')'" })")
  if (-not $r) { $o["pamiec"] = @($false, "brak raportu z okna"); return $o }
  $zle = @()
  if ("$($r.Przywrocone)" -cne $c.Przywrocone) { $zle += "przywrocone '$($r.Przywrocone)' zamiast '$($c.Przywrocone)'" }
  if (($r.Szer -ne $c.Szer) -or ($r.Wys -ne $c.Wys)) { $zle += "okno $($r.Szer)x$($r.Wys) zamiast $($c.Szer)x$($c.Wys)" }
  if (($r.MinSzer -ne $SZER_DOM) -or ($r.MinWys -ne $WYS_DOM)) { $zle += "MinimumSize $($r.MinSzer)x$($r.MinWys) zamiast ${SZER_DOM}x$WYS_DOM" }
  $szer = (@($r.Kontrolki | Where-Object { $_.Widoczny -and ($_.Typ -eq "TextBox") }) | Measure-Object Szer -Maximum).Maximum
  if (($szer -gt $c.Baza) -or ($szer -lt ($c.Baza - $PASEK))) { $zle += "najszersze pole $szer px zamiast $($c.Baza)" }
  foreach ($wz in @($c.Wpis | Where-Object { $_ })) { if ($u.Dziennik -notmatch $wz) { $zle += "w dzienniku brak '$wz'" } }
  if ((-not $c.Wpis) -and ($u.Dziennik -match 'rozmiar okna przypomnien')) { $zle += "niepotrzebny wpis o rozmiarze w dzienniku" }
  foreach ($wz in @($c.PlikPo | Where-Object { $_ })) { if ("$($u.Rozmiar)" -notmatch $wz) { $zle += "plik po zamknieciu '$("$($u.Rozmiar)" -replace '\r?\n', ' | ')' nie pasuje do '$wz'" } }
  $o["pamiec"] = @(($zle.Count -eq 0), "okno $($r.Szer)x$($r.Wys), przywrocone '$($r.Przywrocone)', najszersze pole $szer px$(if ($zle) { '; ' + ($zle -join '; ') })")
  return $o
}

function Pompuj-Schowek([int]$ms) { $do = [datetime]::Now.AddMilliseconds($ms); while ([datetime]::Now -lt $do) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 } }
function Schowek-Stan {
  $s = [pscustomobject]@{ Tekst = $null; Formaty = [ordered]@{}; Nieodczytane = @() }
  if ([System.Windows.Forms.Clipboard]::ContainsText()) { $s.Tekst = [System.Windows.Forms.Clipboard]::GetText() }
  $dob = [System.Windows.Forms.Clipboard]::GetDataObject()
  if ($dob) { foreach ($fmt in $dob.GetFormats($false)) { try { $v = $dob.GetData($fmt); if ($null -ne $v) { $s.Formaty[$fmt] = $v } else { $s.Nieodczytane += $fmt } } catch { $s.Nieodczytane += $fmt } } }
  return $s
}

# ---------------------------------------------------------------- przebiegi
$schowek = $null; $stan = $null
# Oceny i sabotaze, ktore wymagaja schowka - bez -Schowek nie sa ani uruchamiane, ani liczone.
$PROBY_SCHOWKA = @("zaznaczenie", "kopiuj", "kopiuj-zajety", "kopiuj-blad")
if (-not $Schowek) {
  Write-Host "próby schowka pominięte (użyj -Schowek)"
} elseif ([System.Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
  Wynik "watek STA (schowek)" $false "test musi chodzic w STA (powershell.exe 5.1 -File), inaczej nie zachowa schowka uzytkownika"
} else {
  # Zachowanie schowka uzytkownika: wszystkie formaty, ktore da sie odczytac; nieodczytane wymienione.
  # Odczyt przy zajetym schowku potrafi po cichu dac pusty tekst, dlatego dwa zgodne odczyty pod
  # rzad; bez nich test nie rusza schowka wcale (zamiast nadpisac go pustym przy przywracaniu).
  $poprz = $null
  for ($i = 0; ($i -lt 10) -and (-not $stan); $i++) {
    Pompuj-Schowek 200
    try { $teraz = Schowek-Stan } catch { $teraz = $null; Write-Host "odczyt schowka: $($_.Exception.Message)" }
    if ($teraz -and $poprz -and ("$($teraz.Tekst)" -ceq "$($poprz.Tekst)") -and (($null -eq $teraz.Tekst) -eq ($null -eq $poprz.Tekst)) -and
        ((@($teraz.Formaty.Keys) -join ',') -ceq (@($poprz.Formaty.Keys) -join ','))) { $stan = $teraz }
    $poprz = $teraz
  }
  if (-not $stan) { Wynik "schowek uzytkownika odczytany" $false "brak dwoch zgodnych odczytow w 10 probach - test nie rusza schowka" }
}
if ($stan -or -not $Schowek) {
  if ($stan) {
    $schowek = $stan.Formaty; $nieodczytane = $stan.Nieodczytane; $tekstPrzed = $stan.Tekst
    Write-Host "Schowek uzytkownika: zapamietane formaty $($schowek.Count) ($((@($schowek.Keys)) -join ', ')); nieodczytane: $($nieodczytane -join ', ')"
  }

  try {
    $prawdziwa = Kopia "prawdziwa" @() -Rozciagnij $true
    $u = Uruchom $prawdziwa
    $oc = Ocen $u
    foreach ($n in $OPISY.Keys) { if ($Schowek -or ($PROBY_SCHOWKA -notcontains $n)) { Wynik $OPISY[$n] $oc[$n][0] $oc[$n][1] } }
    Write-Host "Zrzut okna: $($prawdziwa.Zrzut) (okno $($u.Raport.Okno), ekran $($u.Raport.Ekran))"
    $or = Ocen-Rozmiar $u "zwykle" 720 $trescPola[2]
    foreach ($n in $OPISY_ROZ.Keys) { Wynik "okno przypomnien: $($OPISY_ROZ[$n])" $or[$n][0] $or[$n][1] }

    $sabotaze = @(
      @{ Nazwa = "Label zamiast pola z trescia"; Sprawdzenie = "pola"
         K = '$tekst = Pole-Tekstowe $tresc 690 $f.Font $f.ForeColor $f.BackColor'
         Z = '$tekst = New-Object System.Windows.Forms.Label; $tekst.AutoSize = $true; $tekst.MaximumSize = New-Object System.Drawing.Size(690, 0); $tekst.Text = $tresc' },
      @{ Nazwa = "Kopiuj bez naglowka"; Sprawdzenie = "kopiuj"
         K = 'Tekst = $glowa.Text + "`r`n" + $tekst.Text'; Z = 'Tekst = $tekst.Text' },
      @{ Nazwa = "stala wysokosc pola zamiast MeasureText"; Sprawdzenie = "uciecie"
         K = '$t.Height = [System.Windows.Forms.TextRenderer]::MeasureText($tekst, $czcionka, $ile, $flagi).Height'; Z = '$t.Height = 20' },
      @{ Nazwa = "blad schowka po cichu (bez dziennika)"; Sprawdzenie = "kopiuj-blad"
         K = 'Dopisz-Dziennik "przycisk Kopiuj #$($tag.Poz.id) - NIE SKOPIOWALEM do schowka: $($_.Exception.Message)"'; Z = '# sabotaz: cisza' },
      @{ Nazwa = "Do-Schowka po staremu (Clipboard.SetText)"; Sprawdzenie = "kopiuj-zajety"
         K = 'function Do-Schowka([string]$tekst) {'; Z = "function Do-Schowka([string]`$tekst) { [System.Windows.Forms.Clipboard]::SetText(`$tekst) }`r`nfunction Do-Schowka-Nieuzywana([string]`$tekst) {" },
      @{ Nazwa = "Do-Schowka nic nie kopiuje"; Sprawdzenie = "kopiuj"
         K = 'function Do-Schowka([string]$tekst) {'; Z = "function Do-Schowka([string]`$tekst) { }`r`nfunction Do-Schowka-Nieuzywana([string]`$tekst) {" },
      @{ Nazwa = "Do-Schowka polyka porazke"; Sprawdzenie = "kopiuj-blad"
         K = 'throw "schowek zajety przez inny program'; Z = 'return; "schowek zajety przez inny program' })
    $nr = 0
    foreach ($s in $sabotaze) {
      $nr++
      if ((-not $Schowek) -and ($PROBY_SCHOWKA -contains $s.Sprawdzenie)) { continue }
      try {
        $kop = Kopia "sabotaz$nr" @(@{ K = $s.K; Z = $s.Z }) -Zajety ($s.Sprawdzenie -like "kopiuj-*")
      } catch { Wynik "sabotaz '$($s.Nazwa)' wylapany" $false "przygotowanie: $($_.Exception.Message)"; continue }
      $os = Ocen (Uruchom $kop)
      Wynik "negatywna: sabotaz '$($s.Nazwa)' wylapany przez '$($s.Sprawdzenie)'" ((-not $os[$s.Sprawdzenie][0]) -and $os["przebieg"][0]) "z sabotazem: $($os[$s.Sprawdzenie][1])"
    }

    # Okno niepowodzenia (bez prob z trzymanym schowkiem - te sprawdza zwykle okno, kod ten sam).
    $kn = Kopia "niepowodzenie" @($NIEPOWODZENIE) -Zajety $false -Rozciagnij $true
    $un = Uruchom $kn
    $on = Ocen-Niepowodzenia $un
    foreach ($n in $OPISY_NIEP.Keys) { Wynik $OPISY_NIEP[$n] $on[$n][0] $on[$n][1] }
    Write-Host "Zrzut okna niepowodzenia: $($kn.Zrzut)"
    $or = Ocen-Rozmiar $un "niepowodzenie" 720 "Nie udało się wykonać przypomnienia #1 ($($tresc1.TrimEnd('.'))), bo: $POWOD_NIEP. Przeniesione na jutro.`r`nPełny raport: $MD_NIEP"
    foreach ($n in $OPISY_ROZ.Keys) { Wynik "okno niepowodzenia: $($OPISY_ROZ[$n])" $or[$n][0] $or[$n][1] }
    $sabotazeN = @(
      @{ Nazwa = "zwykle przyciski w oknie niepowodzenia"; Sprawdzenie = "przyciski"
         K = 'if ($niepowodzenie) { $akcje = @(@("Spróbuj teraz", "sprobuj"), @("Odłóż na jutro", "odloz")) }'; Z = '# sabotaz: zwykle przyciski' },
      @{ Nazwa = "krzyzyk w oknie niepowodzenia odklada o 2 godziny"; Sprawdzenie = "krzyzyk"
         K = 'if ($script:Niepowodzenie) {'; Z = 'if ($false) {' })
    foreach ($s in $sabotazeN) {
      $nr++
      try { $kop = Kopia "sabotaz$nr" @($NIEPOWODZENIE, @{ K = $s.K; Z = $s.Z }) -Zajety $false }
      catch { Wynik "sabotaz '$($s.Nazwa)' wylapany" $false "przygotowanie: $($_.Exception.Message)"; continue }
      $os = Ocen-Niepowodzenia (Uruchom $kop)
      Wynik "negatywna: sabotaz '$($s.Nazwa)' wylapany przez '$($s.Sprawdzenie)'" ((-not $os[$s.Sprawdzenie][0]) -and $os["przebieg"][0]) "z sabotazem: $($os[$s.Sprawdzenie][1])"
    }

    # Okno decyzji (bez prob z trzymanym schowkiem).
    foreach ($nazwa in $PRZYPADKI_DEC.Keys) {
      $c = $PRZYPADKI_DEC[$nazwa]
      $kd = Kopia $nazwa @($c.Wstaw) -Zajety $false -Przed "$($c.Przed)" -Klik "$($c.Klik)" -Rozciagnij ([bool]$c.Rozciagnij)
      $ud = Uruchom $kd
      $od = Ocen-Decyzji $ud $c.Zdanie $c.O
      foreach ($n in $OPISY_DEC.Keys) { Wynik "$($c.Opis): $($OPISY_DEC[$n])" $od[$n][0] $od[$n][1] }
      Write-Host "Zrzut okna decyzji ($nazwa): $($kd.Zrzut)"
      if ($c.Rozciagnij) {
        $or = Ocen-Rozmiar $ud "decyzja" $SZEROKOSC_DECYZJI $c.Rozciagnij -Szerszy:([bool]$c.Szerszy)
        foreach ($n in $OPISY_ROZ.Keys) { Wynik "$($c.Opis): $($OPISY_ROZ[$n])" $or[$n][0] $or[$n][1] }
      }
    }
    $sabotazeD = @(
      @{ Nazwa = "szczegoly rozwiniete od razu"; Przypadek = "decyzja"; Sprawdzenie = "szczegoly"
         K = '$panel.Visible = $false'; Z = '$panel.Visible = $true' },
      @{ Nazwa = "stala wysokosc przycisku odpowiedzi"; Przypadek = "decyzja-dluga"; Sprawdzenie = "uciecie"
         K = '+ $nat.Height - $jeden.Height))'; Z = '* 0 + 34))' },
      @{ Nazwa = "krzyzyk w oknie decyzji bez przeniesienia na jutro"; Przypadek = "decyzja"; Sprawdzenie = "po"
         K = 'if ($script:Pozostalo -gt 0) { Zamknij-Decyzje-Krzyzykiem }'; Z = 'if ($false) { }' },
      @{ Nazwa = "odpowiedz otwiera terminal zamiast wznowic rozmowe w tle"; Przypadek = "decyzja-opcja"; Sprawdzenie = "po"
         K = '"opcja"    { return (Wznow-W-Tle'; Z = '"opcja" { $null = Okno-Po-Przebiegu $p $p.katalog $p.claude $p.wynikPrzebiegu $p.md; return $true }; "opcja-sabotaz" { return (Wznow-W-Tle' })
    foreach ($s in $sabotazeD) {
      $nr++
      $c = $PRZYPADKI_DEC[$s.Przypadek]
      try { $kop = Kopia "sabotaz$nr" @($c.Wstaw, @{ K = $s.K; Z = $s.Z }) -Zajety $false -Przed "$($c.Przed)" -Klik "$($c.Klik)" }
      catch { Wynik "sabotaz '$($s.Nazwa)' wylapany" $false "przygotowanie: $($_.Exception.Message)"; continue }
      $os = Ocen-Decyzji (Uruchom $kop) $c.Zdanie $c.O
      Wynik "negatywna: sabotaz '$($s.Nazwa)' wylapany przez '$($s.Sprawdzenie)'" ((-not $os[$s.Sprawdzenie][0]) -and $os["teksty"][0]) "z sabotazem: $($os[$s.Sprawdzenie][1])"
    }

    # Rozciaganie zwyklego okna - sabotaze (bez prob z trzymanym schowkiem).
    $sabotazeR = @(
      @{ Nazwa = "maksymalizacja wylaczona"; Sprawdzenie = "ramka"; K = '$f.MaximizeBox = $true'; Z = '$f.MaximizeBox = $false' },
      @{ Nazwa = "tresc nie rosnie z oknem"; Sprawdzenie = "rosnie"
         K = '$lista.Add_ClientSizeChanged({ param($s, $e) Rozloz-Okno $s.Parent $s })'; Z = '# sabotaz: bez rozkladu' },
      @{ Nazwa = "bez MinimumSize"; Sprawdzenie = "minimum"; K = '$f.MinimumSize = $f.Size'; Z = '# sabotaz: bez minimum' },
      @{ Nazwa = "szerokosc bazowa zle policzona (tresc szersza niz dotad)"; Sprawdzenie = "domyslny"
         K = '$script:BazaKlienta = $f.ClientSize.Width - $script:DodatekPaska'; Z = '$script:BazaKlienta = $f.ClientSize.Width - $script:DodatekPaska - 40' },
      @{ Nazwa = "rozmiar nie zapisywany przy zamknieciu"; Sprawdzenie = "zapis"
         K = '$f.Add_FormClosing({ param($s, $e) Zapisz-Rozmiar-Okna $s })'; Z = '# sabotaz: bez zapisu' },
      @{ Nazwa = 'przycisk odpowiedzi po rozciagnieciu zostaje na pelnej szerokosci (GrowOnly)'; Sprawdzenie = 'rosnie'; Przypadek = 'decyzja-srednia'
         K = '$b.Size = $nat   # AutoSize'; Z = '# sabotaz: bez powrotu do naturalnego rozmiaru # AutoSize' })
    foreach ($s in $sabotazeR) {
      $nr++
      $pod = @(@{ K = $s.K; Z = $s.Z }); if ($s.Przypadek) { $pod = @($PRZYPADKI_DEC[$s.Przypadek].Wstaw) + $pod }
      try { $kop = Kopia "sabotaz$nr" $pod -Zajety $false -Rozciagnij $true }
      catch { Wynik "sabotaz '$($s.Nazwa)' wylapany" $false "przygotowanie: $($_.Exception.Message)"; continue }
      if ($s.Przypadek) { $os = Ocen-Rozmiar (Uruchom $kop) "decyzja" $SZEROKOSC_DECYZJI $PRZYPADKI_DEC[$s.Przypadek].Rozciagnij }
      else { $os = Ocen-Rozmiar (Uruchom $kop) "zwykle" 720 $trescPola[2] }
      Wynik "negatywna: sabotaz '$($s.Nazwa)' wylapany przez '$($s.Sprawdzenie)'" ((-not $os[$s.Sprawdzenie][0]) -and $os["przebieg"][0]) "z sabotazem: $($os[$s.Sprawdzenie][1])"
    }

    # Zapamietany rozmiar zwyklego okna (plik przed startem) i sabotaze.
    foreach ($nazwa in $PRZYPADKI_PAMIECI.Keys) {
      $c = $PRZYPADKI_PAMIECI[$nazwa]
      $kp = Kopia $nazwa @() -Zajety $false
      $op = Ocen-Pamieci (Uruchom $kp -Rozmiar "$($c.Plik)" -RozmiarKatalog:([bool]$c.Katalog)) $c
      Wynik "$($c.Opis) (przebieg)" $op["przebieg"][0] $op["przebieg"][1]
      Wynik $c.Opis $op["pamiec"][0] $op["pamiec"][1]
    }
    $sabotazeP = @(
      @{ Nazwa = "odczyt rozmiaru bez obslugi bledu (wyjatek zamiast domyslnego)"; Przypadek = "pamiec-zepsuta"
         K = 'function Czytaj-Rozmiar-Okna([string]$rodzaj) {'
         Z = "function Czytaj-Rozmiar-Okna([string]`$rodzaj) {`r`n  if (-not (Test-Path -LiteralPath `$PlikRozmiaru)) { return `$null }`r`n  `$c = ([System.IO.File]::ReadAllText(`$PlikRozmiaru) -split ':')[1] -split ','`r`n  return [pscustomobject]@{ Prostokat = New-Object System.Drawing.Rectangle([int]`$c[0], [int]`$c[1], [int]`$c[2], [int]`$c[3]); Maks = `$false }`r`n}`r`nfunction Czytaj-Rozmiar-Okna-Nieuzywana([string]`$rodzaj) {" },
      @{ Nazwa = "zapamietany rozmiar nie przywracany"; Przypadek = "pamiec"; K = 'if ($z) { Przywroc-Rozmiar-Okna $f $z }'; Z = '# sabotaz: bez przywracania' },
      @{ Nazwa = "polozenie poza ekranem przyjete"; Przypadek = "pamiec-poza"; K = 'if ($widac.Count -eq 0) {'; Z = 'if ($false) {' },
      @{ Nazwa = "nieudany zapis rozmiaru po cichu"; Przypadek = "pamiec-katalog"
         K = 'catch { Dopisz-Dziennik "rozmiar okna przypomnien ($($script:RodzajOkna)): nie zapisalem'; Z = 'catch { $null = "rozmiar okna przypomnien ($($script:RodzajOkna)): nie zapisalem' })
    foreach ($s in $sabotazeP) {
      $nr++
      $c = $PRZYPADKI_PAMIECI[$s.Przypadek]
      try { $kop = Kopia "sabotaz$nr" @(@{ K = $s.K; Z = $s.Z }) -Zajety $false }
      catch { Wynik "sabotaz '$($s.Nazwa)' wylapany" $false "przygotowanie: $($_.Exception.Message)"; continue }
      $os = Ocen-Pamieci (Uruchom $kop -Rozmiar "$($c.Plik)" -RozmiarKatalog:([bool]$c.Katalog)) $c
      Wynik "negatywna: sabotaz '$($s.Nazwa)' wylapany" (-not ($os["przebieg"][0] -and $os["pamiec"][0])) "z sabotazem: $($os['pamiec'][1]) | $($os['przebieg'][1])"
    }
  } catch {
    Wynik "WYWROTKA TESTU" $false "$($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
  } finally {
    # Przywrocenie schowka uzytkownika (tylko z -Schowek - bez niego test schowka nie ruszal) - z
    # ponawianiem jak Do-Schowka (bez wlasnego czekania .NET, ktore przy programie czytajacym schowek
    # czeka na prozno) i sprawdzeniem dwoma odczytami.
    if ($stan) {
      $nowy = New-Object System.Windows.Forms.DataObject
      foreach ($fmt in $schowek.Keys) { $nowy.SetData($fmt, $schowek[$fmt]) }
      $blad = "nie probowalem"
      for ($i = 0; $i -lt 30; $i++) {
        try {
          if ($schowek.Count -gt 0) { [System.Windows.Forms.Clipboard]::SetDataObject($nowy, $true, 0, 0) } else { [System.Windows.Forms.Clipboard]::SetDataObject((New-Object System.Windows.Forms.DataObject), $true, 0, 0) }
          $blad = ""; break
        } catch { $blad = $_.Exception.Message; Pompuj-Schowek 100 }
      }
      $po = $null; $zgodne = $false
      for ($i = 0; ($i -lt 10) -and (-not $zgodne); $i++) {
        Pompuj-Schowek 200
        try { $po = (Schowek-Stan).Tekst } catch { $po = "BLAD ODCZYTU: $($_.Exception.Message)" }
        $zgodne = ("$po" -ceq "$tekstPrzed") -and (($null -eq $po) -eq ($null -eq $tekstPrzed))
      }
      Wynik "schowek uzytkownika przywrocony" ((-not $blad) -and $zgodne) ("tekst przed: $(if ($null -eq $tekstPrzed) { 'brak' } else { "$($tekstPrzed.Length) zn." }), po: $(if ($null -eq $po) { 'brak' } else { "$($po.Length) zn." }); formatow $($schowek.Count)$(if ($blad) { "; zapis: $blad" })")
    }
  }
}

# Po tescie zaden proces kopii nie moze zostac.
$zostale = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" | Where-Object { "$($_.CommandLine)" -like "*$tmp*" })
foreach ($z in $zostale) { try { Stop-Process -Id $z.ProcessId -Force } catch { Write-Warning "nie ubilem $($z.ProcessId): $($_.Exception.Message)" } }
Wynik "po tescie zaden proces kopii nie zostal" ($zostale.Count -eq 0) "pozostalych: $($zostale.Count)"

Write-Host ""
Write-Host "Zrzuty: $Zrzuty"
Write-Host "Wynik: $(@($script:wyniki | Where-Object { $_.OK }).Count) z $($script:wyniki.Count) TAK. Pliki robocze: $tmp"
if (@($script:wyniki | Where-Object { -not $_.OK }).Count -gt 0) { exit 1 }
exit 0
