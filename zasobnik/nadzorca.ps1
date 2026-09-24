# Nadzorca MegaRuchacza - ikona w zasobniku Windows.
#
# PO CO TO ISTNIEJE. Do 0.17.0 rachunek za pamiec, start cyklu wiedzy i ALARM
# O CISZY wisialy w calosci na hookach SessionStart. Gdy hook nie odpalal,
# milknal razem z nim takze mechanizm, ktory mial wykryc, ze nic nie chodzi -
# i tak przez tydzien (17-24.09.2026) nikt nie zobaczyl ani jednej liczby.
# Wykrywacz ciszy, ktory milknie razem z tym, co wykrywa, jest bezuzyteczny.
# Dlatego nadzorca jest PROGRAMEM OSOBNYM: startuje przy zalogowaniu z zadania
# w Harmonogramie, nie wie nic o tym, czy uzytkownik otworzyl Claude Code,
# i to ON jest odtad glownym wyzwalaczem cyklu. Hooki zostaja jako droga zapasowa.
#
# DLACZEGO POWERSHELL, A NIE NODE ANI PYTHON. Warunek ze zlecenia brzmial:
# ikona w zasobniku BEZ instalowania czegokolwiek nowego u uzytkownika i bez
# mrugajacej konsoli. Node nie ma zasobnika we wbudowanych modulach (trzeba by
# dolozyc pakiet natywny), Python potrzebowalby pystray i pillow - w obu
# wypadkach to nowa zaleznosc. PowerShell 5.1 jest w Windows z definicji, a razem
# z nim System.Windows.Forms i System.Drawing, czyli NotifyIcon, menu i dymki.
# Zero instalacji. Okno konsoli nie mrugnie, bo zadanie startuje przez
# "conhost.exe --headless powershell.exe -WindowStyle Hidden" - ta sama sztuczka,
# ktorej uzywa juz narzedzia\straznik-zasad.ps1.
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File zasobnik\nadzorca.ps1
#     -Zrodlo <kat>         katalog glowny narzedzia (domyslnie: katalog nad zasobnik\)
#     -KatalogDomowy <kat>  podmiana katalogu domowego (testy, proba negatywna)
#     -Minut <n>            co ile minut dozor sprawdza stan (domyslnie 15)
#     -Pokaz                otwiera okno od razu po starcie
#     -Raz                  JEDEN przebieg dozoru bez petli i bez stalej ikony;
#                           wszystko wypisuje na ekran. Tego trybu uzywa sprawdzenie
#                           i proba negatywna - okna nie da sie sprawdzic bez pulpitu
#     -Raport               sam wydruk okna na ekran, bez dozoru i bez alarmow
#     -Proba                nie startuje cyklu i nic nie zapisuje (laczy sie z -Raz)
#     -Cicho                nie pokazuje dymkow, sam wydruk (tylko z -Raz)
#
# Kod wyjscia w trybie -Raz: 0 gdy nie bylo alarmow, 1 gdy byl choc jeden.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [string]$KatalogDomowy = $HOME,
  [int]$Minut = 15,
  [switch]$Pokaz,
  [switch]$Raz,
  [switch]$Raport,
  [switch]$Proba,
  [switch]$Cicho
)

. (Join-Path $PSScriptRoot "stan-nadzorcy.ps1")

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Ustaw-Nadzorce $Zrodlo $KatalogDomowy ([bool]$Proba)

# Bez katalogu zrodlowego nadzorca nie ma czego wolac i pokazywalby same
# "NIE WIADOMO" - a to wyglada jak usterka narzedzia, nie jak zla sciezka.
# Mowimy wprost i konczymy, zamiast udawac, ze cos nadzorujemy.
if (-not (Test-Path (Join-Path $Zrodlo "narzedzia\koszt-pamieci.ps1"))) {
  Write-Error "nadzorca: w '$Zrodlo' nie ma narzedzia\koszt-pamieci.ps1 - podaj wlasciwy -Zrodlo"
  exit 2
}

# Sufity Windows na dymek. Nie sa nasze - to twarde granice API powiadomien.
# Zgodnie z zasada "sufit nie ucina, sufit krzyczy" skrocony tekst dostaje
# ostrzezenie NA POCZATKU (poczatek przezywa uciecie zawsze), a cala tresc
# i tak idzie do okna oraz do dziennika, wiec nic nie ginie po cichu.
$MAX_TYTUL = 60
$MAX_TRESC = 240

function Skroc-Na-Dymek([string]$tekst, [int]$limit, [string]$ostrzezenie) {
  if (-not $tekst) { return "" }
  if ($tekst.Length -le $limit) { return $tekst }
  $zapas = $limit - $ostrzezenie.Length
  if ($zapas -lt 10) { return $ostrzezenie.Substring(0, [math]::Min($ostrzezenie.Length, $limit)) }
  return $ostrzezenie + $tekst.Substring(0, $zapas)
}

# Ikona. Bierzemy logo narzedzia z katalogu zrodlowego; gdy go nie ma albo nie
# da sie wczytac, zostaje ikona systemowa - program ma sie pokazac w zasobniku
# tak czy owak, bo bez ikony nie ma calego nadzorcy.
function Ikona-Nadzorcy {
  $plik = Join-Path $Zrodlo "logo.png"
  if (Test-Path $plik) {
    try {
      $obraz = [System.Drawing.Image]::FromFile($plik)
      $male = New-Object System.Drawing.Bitmap($obraz, 32, 32)
      $obraz.Dispose()
      return [System.Drawing.Icon]::FromHandle($male.GetHicon())
    } catch {
      Zanotuj-Wywrotke "wczytanie ikony z $plik" $_
    }
  }
  return [System.Drawing.SystemIcons]::Application
}

# ------------------------------------------------------------------ raport okna

# Cztery rzeczy ze zlecenia, w kolejnosci od najczesciej ogladanej: rachunek,
# cykl, wersja, alarmy - plus slad samego nadzorcy, bo on tez ma nie milczec
# o sobie. Zbierane raz, zeby dozor i okno nie liczyly tego samego dwa razy.
function Zbierz-Wszystko([bool]$zSieci, [bool]$zKolejka) {
  $d = [pscustomobject]@{ Wersja = $null; Cykl = $null; Rachunek = $null; Alarmy = @() }

  try { $d.Wersja = Stan-Wersji $zSieci }
  catch { Zanotuj-Wywrotke "odczyt wersji narzedzia" $_ }

  try { $d.Cykl = Stan-Cyklu $zKolejka }
  catch { Zanotuj-Wywrotke "odczyt stanu cyklu" $_ }

  try { $d.Rachunek = Linia-Rachunku }
  catch { Zanotuj-Wywrotke "rachunek za pamiec (linia)" $_ }

  if ($d.Cykl -and $d.Rachunek) {
    try { $d.Alarmy = Zbierz-Alarmy $d.Cykl $d.Rachunek }
    catch { Zanotuj-Wywrotke "skladanie alarmow" $_ }
  }
  return $d
}

function Zbuduj-Raport($d, [string[]]$wywrotkiNadzorcy) {
  $l = @()
  $l += "MegaRuchacz - nadzorca w zasobniku"
  $l += "zebrane $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  $l += "narzedzie      : $Zrodlo"
  $l += "katalog domowy : $KatalogDomowy"
  $l += ""

  $l += "== WERSJA NARZEDZIA =="
  if ($d.Wersja) { $l += Opis-Wersji $d.Wersja }
  else { $l += "  NIE UDALO SIE USTALIC - szczegoly w dzienniku nadzorcy" }
  $l += ""

  $l += "== RACHUNEK ZA PAMIEC =="
  $l += "   (liczy narzedzia\koszt-pamieci.ps1 -Rozbicie - to ten sam wydruk, nie druga kopia)"
  try { $l += Rachunek-Rozbicie }
  catch { Zanotuj-Wywrotke "rachunek za pamiec (rozbicie)" $_; $l += "  NIE UDALO SIE POLICZYC - szczegoly w dzienniku nadzorcy" }
  $l += ""

  $l += "== CYKL WIEDZY =="
  if ($d.Cykl) { $l += Opis-Cyklu $d.Cykl }
  else { $l += "  NIE UDALO SIE ODCZYTAC - szczegoly w dzienniku nadzorcy" }
  $l += ""

  $l += "== ALARMY =="
  if (@($d.Alarmy).Count -eq 0) {
    if ($d.Cykl -and $d.Rachunek) { $l += "  nic nie wymaga uwagi" }
    else { $l += "  NIE WIADOMO - brakuje danych, wiec alarmow nie policzylem" }
  } else {
    foreach ($a in $d.Alarmy) {
      $l += "  [$($a.Temat)] $($a.Tytul)"
      $l += "      $($a.Tresc)"
    }
  }
  $l += ""

  $l += "== NADZORCA =="
  $stan = Czytaj-Klucze (Join-Path $KatalogDomowy ".claude\.megaruchacz-zasobnik.txt")
  if ($stan["byl"]) { $l += "  ostatni dozor   : $($stan['byl']) (tryb $($stan['byl.tryb']))" }
  else { $l += "  ostatni dozor   : brak zapisu - to pierwszy przebieg albo nie moge pisac do pliku stanu" }
  if ($stan["cykl.ruszony"]) { $l += "  cykl startowany : $($stan['cykl.ruszony'])" }
  if (@($wywrotkiNadzorcy).Count -gt 0) {
    $l += "  WYWROTKI Z POPRZEDNICH PRZEBIEGOW:"
    foreach ($w in $wywrotkiNadzorcy) { $l += "      $w" }
  }
  $l += "  dziennik        : $(Join-Path $KatalogDomowy '.claude\.megaruchacz-zasobnik.log')"
  return $l
}

# Podpowiedz przy ikonie. NotifyIcon.Text ma twardy sufit 63 znakow, wiec tekst
# jest budowany tak, zeby sie zmiescil, a nie ciety po fakcie.
function Podpowiedz($d) {
  $w = "?"
  if ($d.Wersja -and $d.Wersja.Lokalna) { $w = $d.Wersja.Lokalna }
  $c = "cykl ?"
  if ($d.Cykl) {
    $g = Godzin-Od-Cyklu $d.Cykl
    if ($null -eq $g) { $c = "cykl NIGDY" }
    elseif ($g -lt 24) { $c = "cykl dzis" }
    else { $c = "cykl stoi $([int]($g / 24)) dni" }
  }
  $a = ""
  if (@($d.Alarmy).Count -gt 0) { $a = " ALARM x$(@($d.Alarmy).Count)" }
  $t = "MegaRuchacz ${w} - ${c}${a}"
  if ($t.Length -gt 63) { $t = $t.Substring(0, 63) }
  return $t
}

# -------------------------------------------------------------------- dozor

# Jeden przebieg dozoru: zebrac stan, ruszyc cykl jesli trzeba, wystrzelic
# alarmy, zostawic slad "bylem tu". Wolany z zegara co $Minut i raz przy starcie.
# $pokazDymek to skrypt-blok przyjmujacy tytul i tresc - dzieki temu ten sam
# dozor dziala z ikona w zasobniku i bez niej (tryb -Raz).
function Dozor($pokazDymek, [bool]$zKolejka) {
  $d = Zbierz-Wszystko $false $zKolejka

  # Cykl wiedzy - to jest teraz GLOWNY wyzwalacz, niezalezny od hookow.
  try {
    $czy = Czy-Ruszac-Cykl
    if ($czy.Ruszac) {
      Notuj "dozor: ruszam cykl wiedzy ($($czy.Powod))"
      $poszlo = Ruszaj-Cykl
      if (-not $poszlo) {
        & $pokazDymek "MegaRuchacz: nie udalo sie ruszyc cyklu" (
          "Proba startu narzedzia\cykl-dzienny.ps1 nie powiodla sie. " +
          "Uruchom recznie: powershell -ExecutionPolicy Bypass -File $Zrodlo\narzedzia\cykl-dzienny.ps1")
      }
    } else {
      Notuj "dozor: cyklu nie ruszam - $($czy.Powod)"
    }
  } catch { Zanotuj-Wywrotke "decyzja o starcie cyklu" $_ }

  # Alarmy - jeden na sprawe na dobe, zeby nie uczyly ignorowania.
  foreach ($a in @($d.Alarmy)) {
    if (Alarm-Juz-Byl $a.Temat) { Notuj "alarm [$($a.Temat)] juz dzis byl - nie powtarzam"; continue }
    & $pokazDymek $a.Tytul $a.Tresc
    Notuj "ALARM [$($a.Temat)] $($a.Tytul) :: $($a.Tresc)"
    Odnotuj-Alarm $a.Temat
  }

  Zapisz-Obecnosc "dozor"
  return $d
}

# --------------------------------------------------------------- tryby bez GUI

if ($Raz -or $Raport) {
  # Wywrotki z poprzedniego przebiegu meldujemy PRZED praca - inaczej nowy
  # przebieg nadpisalby slad po starym i nikt by sie o nim nie dowiedzial.
  $stare = @()
  try { $stare = Odbierz-Wywrotki } catch { Write-Warning "nie odczytalem wywrotek: $($_.Exception.Message)" }
  foreach ($w in $stare) { Write-Output "POPRZEDNIO SIE WYWROCILO: $w" }

  if ($Raport) {
    $d = Zbierz-Wszystko $true $true
    Zbuduj-Raport $d $stare | ForEach-Object { Write-Output $_ }
    Zapisz-Obecnosc "raport"
    exit 0
  }

  # Dymek takze w tym trybie - proba negatywna ma zobaczyc PRAWDZIWE
  # powiadomienie, a nie zapewnienie, ze by sie pokazalo.
  $dymek = {
    param($tytul, $tresc)
    # Pokazujemy CALA tresc i osobno to, co naprawde wchodzi na dymek - roznica
    # miedzy jednym a drugim jest tym, co sufit obcial, a to ma byc widac.
    $naDymekTytul = Skroc-Na-Dymek $tytul $MAX_TYTUL "[skrocone] "
    $naDymekTresc = Skroc-Na-Dymek $tresc $MAX_TRESC "[skrocone - calosc w oknie MegaRuchacza] "
    Write-Host ""
    Write-Host "POWIADOMIENIE"
    Write-Host "  tytul: $tytul"
    Write-Host "  tresc: $tresc"
    Write-Host "  na dymku, tytul ($($naDymekTytul.Length) zn.): $naDymekTytul"
    Write-Host "  na dymku, tresc ($($naDymekTresc.Length) zn.): $naDymekTresc"
    if ($Cicho) { Write-Host "  (-Cicho: dymka nie pokazuje)"; return }
    try {
      $n = New-Object System.Windows.Forms.NotifyIcon
      $n.Icon = Ikona-Nadzorcy
      $n.Visible = $true
      $n.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Warning
      $n.BalloonTipTitle = $naDymekTytul
      $n.BalloonTipText  = $naDymekTresc
      $n.ShowBalloonTip(15000)
      $do = [datetime]::Now.AddSeconds(6)
      while ([datetime]::Now -lt $do) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
      $n.Visible = $false
      $n.Dispose()
      Write-Host "  (dymek pokazany w zasobniku)"
    } catch {
      Write-Host "  (DYMKA NIE DALO SIE POKAZAC: $($_.Exception.Message))"
      Zanotuj-Wywrotke "pokazanie dymka" $_
    }
  }

  $d = Dozor $dymek $true
  Write-Output ""
  Zbuduj-Raport $d $stare | ForEach-Object { Write-Output $_ }
  if (@($d.Alarmy).Count -gt 0) { exit 1 }
  exit 0
}

# ------------------------------------------------------------------------ GUI
# Wszystko ponizej ma byc na poziomie skryptu, a nie w cudzych funkcjach:
# procedury obslugi zdarzen WinForms odpalaja sie po powrocie z funkcji,
# w ktorej je zapisano, wiec siegaja wylacznie po $script: i po funkcje skryptu.

[System.Windows.Forms.Application]::EnableVisualStyles()

# Jeden nadzorca na sesje. Drugi - wstawiony np. przez recznie odpalone zadanie -
# dublowalby alarmy i mogl ruszyc cykl dwa razy. Porzucony zamek (poprzedni
# przebieg padl w polowie) liczy sie jako wolny, inaczej jedna wywrotka
# blokowalaby start do konca sesji. Ta sama konstrukcja co w cykl-dzienny.ps1.
$script:Zamek = New-Object System.Threading.Mutex($false, "Local\MegaRuchacz-Nadzorca")
$mojZamek = $false
try { $mojZamek = $script:Zamek.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $mojZamek = $true }
if (-not $mojZamek) {
  Notuj "nadzorca juz chodzi w tej sesji - drugiego nie uruchamiam"
  exit 0
}

$script:Okno  = $null
$script:Pole  = $null
$script:Ikona = $null

# ZLAPANE 24.09.2026 NA PROBIE Z PRAWDZIWYM OKNEM, i to jest dokladnie ten rodzaj
# usterki, dla ktorego istnieje zasada "cisza jest zakazana": proces startowany
# z ukryta konsola (-WindowStyle Hidden, a tak wlasnie robi to zadanie
# w Harmonogramie) przekazuje SW_HIDE ze STARTUPINFO pierwszemu oknu, jakie
# stworzy. Form.Show() konczy sie wtedy bez bledu, okno POWSTAJE - i jest
# niewidzialne. Uzytkownik klikalby ikone i nie dzialoby sie NIC, bez sladu
# w dzienniku. Dlatego po kazdym Show() wymuszamy pokazanie wprost.
Add-Type -Namespace MegaRuchacz -Name Pulpit -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr uchwyt, int jak);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr uchwyt);
'@
$SW_POKAZ = 5   # SW_SHOW

function Wymus-Pokazanie($formularz) {
  try {
    [MegaRuchacz.Pulpit]::ShowWindow($formularz.Handle, $SW_POKAZ) | Out-Null
    [MegaRuchacz.Pulpit]::SetForegroundWindow($formularz.Handle) | Out-Null
  } catch { Zanotuj-Wywrotke "wymuszenie pokazania okna" $_ }
}

function Odswiez-Tresc([bool]$zSieci) {
  if (-not $script:Pole -or $script:Pole.IsDisposed) { return }
  $script:Pole.Text = "Zbieram dane - rachunek, stan cyklu, wersja..."
  $script:Okno.Refresh()
  try {
    $d = Zbierz-Wszystko $zSieci $true
    $script:Pole.Lines = [string[]](Zbuduj-Raport $d @())
    if ($script:Ikona) { $script:Ikona.Text = Podpowiedz $d }
  } catch {
    Zanotuj-Wywrotke "zlozenie okna" $_
    $script:Pole.Text = "NIE UDALO SIE ZLOZYC RAPORTU: $($_.Exception.Message)" + "`r`n`r`n" +
                        "Slad w $(Join-Path $KatalogDomowy '.claude\.megaruchacz-zasobnik.log')"
  }
  $script:Pole.SelectionStart = 0
  $script:Pole.ScrollToCaret()
}

function Nowy-Przycisk([string]$napis, [int]$szerokosc) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $napis
  $b.Width = $szerokosc
  $b.Height = 30
  return $b
}

function Pokaz-Okno {
  if ($script:Okno -and -not $script:Okno.IsDisposed) {
    $script:Okno.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $script:Okno.Show()
    Wymus-Pokazanie $script:Okno
    return
  }

  $f = New-Object System.Windows.Forms.Form
  $f.Text = "MegaRuchacz - nadzorca"
  $f.Size = New-Object System.Drawing.Size(880, 720)
  $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
  try { $f.Icon = Ikona-Nadzorcy } catch { Zanotuj-Wywrotke "ikona okna" $_ }

  $pole = New-Object System.Windows.Forms.TextBox
  $pole.Multiline = $true
  $pole.ReadOnly = $true
  $pole.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
  $pole.Font = New-Object System.Drawing.Font("Consolas", 9.5)
  $pole.Dock = [System.Windows.Forms.DockStyle]::Fill
  $pole.BackColor = [System.Drawing.Color]::White
  # Okno pokazuje sie NAJPIERW z ta linia, a dopiero potem sie wypelnia:
  # rachunek liczy osobny proces, wiec puste okno przez kilka sekund
  # wygladaloby jak zawieszone. Zawieszone i pracujace maja sie roznic.
  $pole.Text = "Zbieram dane - rachunek, stan cyklu, wersja..."

  $pasek = New-Object System.Windows.Forms.FlowLayoutPanel
  $pasek.Dock = [System.Windows.Forms.DockStyle]::Bottom
  $pasek.Height = 44
  $pasek.Padding = New-Object System.Windows.Forms.Padding(6)

  $bOdswiez    = Nowy-Przycisk "Odswiez" 90
  $bAktualizuj = Nowy-Przycisk "Aktualizuj" 110
  $bCykl       = Nowy-Przycisk "Uruchom cykl teraz" 150
  $bZamknij    = Nowy-Przycisk "Zamknij" 90
  $pasek.Controls.AddRange(@($bOdswiez, $bAktualizuj, $bCykl, $bZamknij))

  $bOdswiez.Add_Click({ Odswiez-Tresc $true })

  # Przycisk aktualizacji robi DOKLADNIE to, co hook Codeksa: wola
  # straznik-zasad.ps1 -Tlo (fetch + merge --ff-only, nigdy reset --hard).
  # Warunki odmowy - brudne drzewo, rozjechana historia, brak zdalnej -
  # naleza do straznika i to on je wypisuje; my pokazujemy, co powiedzial.
  $bAktualizuj.Add_Click({
    $script:Pole.Text = "Aktualizuje - straznik pobiera nowsza wersje i nanosi poprawki..."
    $script:Okno.Refresh()
    $wynik = @()
    try { $wynik = @(Aktualizuj) }
    catch { Zanotuj-Wywrotke "aktualizacja" $_; $wynik = @("NIE UDALO SIE: $($_.Exception.Message)") }
    $script:Pole.Lines = [string[]](@("== AKTUALIZACJA ==", "") + $wynik + @("", "Za chwile odswieze reszte okna."))
    $script:Okno.Refresh()
    Start-Sleep -Seconds 3
    Odswiez-Tresc $true
  })

  $bCykl.Add_Click({
    $script:Pole.Text = "Startuje cykl wiedzy..."
    $script:Okno.Refresh()
    $poszlo = $false
    try { $poszlo = Ruszaj-Cykl } catch { Zanotuj-Wywrotke "reczny start cyklu" $_ }
    if ($poszlo) {
      $script:Pole.Text = "Cykl wiedzy wystartowal w tle. Potrwa kilka minut." + "`r`n" +
                          "Koszt pojawi sie w tym oknie po zakonczeniu - kliknij wtedy [Odswiez]."
    } else {
      $script:Pole.Text = "NIE UDALO SIE WYSTARTOWAC CYKLU." + "`r`n" +
                          "Sprobuj recznie: powershell -ExecutionPolicy Bypass -File $Zrodlo\narzedzia\cykl-dzienny.ps1" + "`r`n" +
                          "Slad w $(Join-Path $KatalogDomowy '.claude\.megaruchacz-zasobnik.log')"
    }
  })

  $bZamknij.Add_Click({ $script:Okno.Close() })

  $f.Controls.Add($pole)
  $f.Controls.Add($pasek)
  $f.Add_FormClosed({ $script:Okno = $null; $script:Pole = $null })

  $script:Okno = $f
  $script:Pole = $pole
  $f.Show()
  Wymus-Pokazanie $f
  Odswiez-Tresc $true
}

# ----------------------------------------------------------------- ikona i menu

$script:Ikona = New-Object System.Windows.Forms.NotifyIcon
$script:Ikona.Icon = Ikona-Nadzorcy
$script:Ikona.Text = "MegaRuchacz - zbieram dane"
$script:Ikona.Visible = $true

function Pokaz-Dymek([string]$tytul, [string]$tresc) {
  try {
    $script:Ikona.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Warning
    $script:Ikona.BalloonTipTitle = Skroc-Na-Dymek $tytul $MAX_TYTUL "[skrocone] "
    $script:Ikona.BalloonTipText  = Skroc-Na-Dymek $tresc $MAX_TRESC "[skrocone - calosc w oknie MegaRuchacza] "
    $script:Ikona.ShowBalloonTip(20000)
  } catch { Zanotuj-Wywrotke "pokazanie dymka" $_ }
}
$script:Dymek = { param($tytul, $tresc) Pokaz-Dymek $tytul $tresc }

function Nowa-Pozycja([string]$napis, $akcja) {
  $p = New-Object System.Windows.Forms.ToolStripMenuItem
  $p.Text = $napis
  $p.Add_Click($akcja)
  return $p
}

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Items.Add((Nowa-Pozycja "Pokaz rachunek i stan" { Pokaz-Okno })) | Out-Null
$menu.Items.Add((Nowa-Pozycja "Sprawdz teraz" {
  try { Dozor $script:Dymek $true | Out-Null } catch { Zanotuj-Wywrotke "reczne sprawdzenie" $_ }
  Pokaz-Dymek "MegaRuchacz: sprawdzone" "Dozor przeszedl recznie. Szczegoly w oknie - kliknij ikone."
})) | Out-Null
$menu.Items.Add((Nowa-Pozycja "Uruchom cykl teraz" {
  $poszlo = $false
  try { $poszlo = Ruszaj-Cykl } catch { Zanotuj-Wywrotke "reczny start cyklu z menu" $_ }
  if ($poszlo) { Pokaz-Dymek "MegaRuchacz: cykl ruszyl" "Cykl wiedzy pracuje w tle. Koszt pokaze sie w oknie po zakonczeniu." }
  else { Pokaz-Dymek "MegaRuchacz: cykl NIE ruszyl" "Nie udalo sie wystartowac narzedzia\cykl-dzienny.ps1 - szczegoly w oknie." }
})) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$menu.Items.Add((Nowa-Pozycja "Zakoncz nadzorce" {
  Notuj "nadzorca zakonczony z menu - do najblizszego zalogowania nikt nie pilnuje cyklu"
  $script:Ikona.Visible = $false
  [System.Windows.Forms.Application]::Exit()
})) | Out-Null
$script:Ikona.ContextMenuStrip = $menu
$script:Ikona.Add_MouseClick({
  param($nadawca, $e)
  if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Pokaz-Okno }
})

# ------------------------------------------------------------------ zegar dozoru

# Pierwszy przebieg po 5 sekundach, a nie od razu: ikona ma sie pojawic
# natychmiast, a nie po kilkunastu sekundach liczenia rachunku.
$script:Pierwszy = $true
$script:Zegar = New-Object System.Windows.Forms.Timer
$script:Zegar.Interval = 5000
$script:Zegar.Add_Tick({
  if ($script:Pierwszy) {
    $script:Pierwszy = $false
    $script:Zegar.Interval = [math]::Max(1, $Minut) * 60 * 1000
  }
  try {
    $d = Dozor $script:Dymek $true
    $script:Ikona.Text = Podpowiedz $d
  } catch { Zanotuj-Wywrotke "przebieg dozoru" $_ }
})
$script:Zegar.Start()

# Wywrotki z poprzedniego uruchomienia - nadzorca, ktory sie wczoraj wywrocil,
# ma o tym powiedziec, a nie udawac, ze wstal czysty.
try {
  $stare = Odbierz-Wywrotki
  if ($stare.Count -gt 0) {
    $ogon = ""
    if ($stare.Count -gt 1) { $ogon = " (i jeszcze $($stare.Count - 1))" }
    Pokaz-Dymek "MegaRuchacz: nadzorca wywrocil sie poprzednio" (
      "$($stare[0])${ogon}. Kliknij ikone - w oknie jest komplet. " +
      "Dziennik: $(Join-Path $KatalogDomowy '.claude\.megaruchacz-zasobnik.log')")
  }
} catch { Zanotuj-Wywrotke "odczyt wywrotek przy starcie" $_ }

Notuj "nadzorca wystartowal (zrodlo $Zrodlo, dozor co $Minut min)"
Zapisz-Obecnosc "start"
if ($Pokaz) { Pokaz-Okno }

try {
  [System.Windows.Forms.Application]::Run()
} catch {
  # Wywrotka calego programu. Slad idzie na dysk, zeby nastepny start mogl
  # o niej zameldowac - nadzorca ginacy po cichu bylby dokladnie tym samym
  # problemem, dla ktorego rozwiazania powstal.
  Zanotuj-Wywrotke "petla glowna nadzorcy" $_
  Zapisz-Obecnosc "wywrotka"
} finally {
  try { $script:Ikona.Visible = $false; $script:Ikona.Dispose() }
  catch { Notuj "nie udalo sie sprzatnac ikony przy zamykaniu" }
}
