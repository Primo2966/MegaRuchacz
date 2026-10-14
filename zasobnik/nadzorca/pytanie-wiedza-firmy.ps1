# zasobnik\nadzorca\pytanie-wiedza-firmy.ps1 - jedno okienko "Dodać Wiedzę firmy? [Dodaj] [Nie teraz]"
# na STAREJ instalacji MegaRuchacza (rejestr bez klucza wiedzafirmy = "nie zaproponowano", trzeci stan
# w narzedzia\instalacja\stan.ps1). Osobny skrypt, nie modul nadzorcy: odpala go dozor w tle
# (zasobnik\nadzorca\dozor.ps1 Dozor-Wiedza-Firmy -> Odpal-W-Tle), wiec okno nadzorcy na nic nie czeka.
#
# Najwyzej raz dziennie: zanim okno sie pokaze, decyzja jest sprawdzana jeszcze raz
# (Czy-Pytac-O-Wiedze-Firmy w narzedzia\instalacja\stan-wiedzy-firmy.ps1) i zapisywane jest "pokazane"
# w ~\.claude\mr\wiedza-firmy-pytanie.txt. Drugie wywolanie tego samego dnia konczy sie bez okna.
#   [Dodaj]     -> narzedzia\instalacja\modul-wiedzafirmy.ps1 -Akcja Instaluj w ukrytym procesie; okno
#                  mowi, co sie dzieje, i na koncu "Gotowe" albo powod bledu (wtedy pyta znowu jutro)
#   [Nie teraz] -> odpowiedz "nie-teraz"; jutro znowu. Krzyzyk = to samo ("zamkniete").
# Okno rozciagalne i maksymalizowane jak inne okna MegaRuchacza (MinimumSize = rozmiar startowy).
# Dziennik: ~\.claude\mr\wiedza-firmy-pytanie.log.
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File zasobnik\nadzorca\pytanie-wiedza-firmy.ps1 [-Zrodlo <repo>] [-KatalogDomowy <kat>]
#   TESTY: -PozaEkranem (okno w -5000,0, bez paska zadan i aktywacji, wlasny zamek), -Scenariusz <plik>
#   (wczytany kropka po zbudowaniu okna - klika), -SkryptModulu <plik> (atrapa modulu).
# Kod wyjscia: 0 (takze "dzis nie pytam"), 1 = okno nie wstalo (powod w dzienniku i na strumieniu bledow).

param(
  [string]$Zrodlo = '',
  [string]$KatalogDomowy = '',
  [switch]$PozaEkranem,
  [string]$Scenariusz = '',
  [string]$SkryptModulu = ''
)

$ErrorActionPreference = 'Stop'
if (-not $Zrodlo) { $Zrodlo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
if (-not $KatalogDomowy) { $KatalogDomowy = $HOME }
$Zrodlo = $Zrodlo.TrimEnd('\')
$KatalogDomowy = $KatalogDomowy.TrimEnd('\')
if (-not $SkryptModulu) { $SkryptModulu = Join-Path $Zrodlo 'narzedzia\instalacja\modul-wiedzafirmy.ps1' }
$script:Dziennik = Join-Path $KatalogDomowy '.claude\mr\wiedza-firmy-pytanie.log'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)

function Dopisz-Dziennik([string]$t) {
  try {
    $kat = Split-Path -Parent $script:Dziennik
    if (-not (Test-Path -LiteralPath $kat)) { New-Item -ItemType Directory -Force -Path $kat | Out-Null }
    [System.IO.File]::AppendAllText($script:Dziennik, ("{0} [{1}] {2}`r`n" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PID, $t), $script:Utf8)
  } catch { [Console]::Error.WriteLine("pytanie o Wiedze firmy: nie zapisalem dziennika ($($_.Exception.Message)): $t") }
}

function Odmowa([string]$powod) {
  Dopisz-Dziennik "NIE WSTALEM: $powod"
  [Console]::Error.WriteLine("pytanie o Wiedze firmy: $powod")
  exit 1
}

$plikWf = Join-Path $Zrodlo 'narzedzia\instalacja\stan-wiedzy-firmy.ps1'
if (-not (Test-Path -LiteralPath $plikWf)) { Odmowa "nie ma $plikWf" }
try { . $plikWf } catch { Odmowa "nie da sie wczytac $plikWf ($($_.Exception.Message))" }

# Jedna kopia naraz (dwa dozory, klikniecie w trakcie). Test ma wlasny zamek.
$nazwaZamka = 'Local\MegaRuchacz-WiedzaFirmy-Pytanie'
if ($PozaEkranem) { $nazwaZamka += '-TEST' }
$script:Zamek = New-Object System.Threading.Mutex($false, $nazwaZamka)
$moj = $false
try { $moj = $script:Zamek.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $moj = $true }
if (-not $moj) { Dopisz-Dziennik 'okienko juz jest otwarte - koncze'; exit 0 }

$c = Czy-Pytac-O-Wiedze-Firmy $KatalogDomowy
if (-not $c.Pytac) { Dopisz-Dziennik "nie pytam - $($c.Powod)"; exit 0 }
try { Zapisz-Pytanie-Wiedzy-Firmy $KatalogDomowy @{ pokazane = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); odpowiedz = ''; kiedy = ''; powod = '' } }
catch { Odmowa "nie zapisalem, ze pytam ($($_.Exception.Message)) - bez tego pytalbym w kolko" }
Dopisz-Dziennik "pytam o Wiedze firmy ($($c.Powod))"

function Zapisz-Odpowiedz([string]$odp, [string]$powod = '') {
  try { Zapisz-Pytanie-Wiedzy-Firmy $KatalogDomowy @{ odpowiedz = $odp; kiedy = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); powod = $powod } }
  catch { Dopisz-Dziennik "NIE zapisalem odpowiedzi '$odp': $($_.Exception.Message)" }
  Dopisz-Dziennik "odpowiedz: $odp$(if ($powod) { " ($powod)" })"
}

try {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  Add-Type -Namespace MegaRuchacz -Name PytanieWF -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr uchwyt, int jak);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr uchwyt);
'@
  if ($PozaEkranem) {
    # Okno testowe nie odbiera fokusu ani klawiatury (WS_EX_NOACTIVATE, pokazanie bez aktywacji).
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
namespace MegaRuchacz {
  public class OknoTestowePytania : System.Windows.Forms.Form {
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override System.Windows.Forms.CreateParams CreateParams {
      get { System.Windows.Forms.CreateParams cp = base.CreateParams; cp.ExStyle |= 0x08000000; return cp; }
    }
  }
}
'@
  }
} catch { Odmowa "Windows nie dal okienek PowerShella (WinForms): $($_.Exception.Message)" }

# --- okno ------------------------------------------------------------------------
$script:StanOkna = 'pytanie'   # pytanie -> trwa -> gotowe | blad; po odpowiedzi bez instalacji: odpowiedziane
$script:Odpowiedziano = $false
$script:Proces = $null
$script:Wy = $null
$script:Bl = $null

$szer = 560; $wys = 300
if ($PozaEkranem) { $f = New-Object MegaRuchacz.OknoTestowePytania } else { $f = New-Object System.Windows.Forms.Form }
$script:Okno = $f
$f.Text = 'MegaRuchacz – Wiedza firmy'
$f.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$f.BackColor = [System.Drawing.Color]::White
$f.FormBorderStyle = 'Sizable'
$f.MaximizeBox = $true
$f.MinimizeBox = $true
$f.Size = New-Object System.Drawing.Size($szer, $wys)
$f.MinimumSize = $f.Size
if ($PozaEkranem) {
  $f.StartPosition = 'Manual'
  $f.Location = New-Object System.Drawing.Point(-5000, 0)
  $f.ShowInTaskbar = $false
} else {
  $f.StartPosition = 'CenterScreen'
  $f.TopMost = $true
  $ikona = Join-Path $Zrodlo 'logo.png'
  if (Test-Path -LiteralPath $ikona) {
    try { $obraz = [System.Drawing.Image]::FromFile($ikona); $f.Icon = [System.Drawing.Icon]::FromHandle((New-Object System.Drawing.Bitmap($obraz, 32, 32)).GetHicon()); $obraz.Dispose() }
    catch { Dopisz-Dziennik "ikona okna: $($_.Exception.Message)" }
  }
}

$t = New-Object System.Windows.Forms.TableLayoutPanel
$t.Dock = 'Fill'
$t.Padding = New-Object System.Windows.Forms.Padding(22, 18, 22, 14)
$t.ColumnCount = 1
$t.RowCount = 4
[void]$t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))

function Etykieta([string]$tekst, $czcionka, $kolor) {
  $l = New-Object System.Windows.Forms.Label
  $l.Text = $tekst
  $l.AutoSize = $true
  $l.UseMnemonic = $false
  if ($czcionka) { $l.Font = $czcionka }
  if ($kolor) { $l.ForeColor = $kolor }
  $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
  return $l
}
$script:LTytul = Etykieta 'Dodać Wiedzę firmy?' (New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)) ([System.Drawing.Color]::FromArgb(30, 30, 30))
$script:LTresc = Etykieta ("Claude zna to, co ustaliła cała firma, i korzysta z tego w rozmowach. " +
  "Ustalenia z Twoich rozmów z Claude’em trafiają do wspólnej bazy firmy. Niczego nie musisz ustawiać.") $null ([System.Drawing.Color]::FromArgb(50, 50, 50))
$script:LStatus = Etykieta '' $null ([System.Drawing.Color]::FromArgb(90, 90, 90))
$script:LStatus.Visible = $false

$p = New-Object System.Windows.Forms.FlowLayoutPanel
$p.FlowDirection = 'RightToLeft'
$p.AutoSize = $true
$p.Dock = 'Fill'
$p.WrapContents = $false
$p.Margin = New-Object System.Windows.Forms.Padding(0)
function Przycisk([string]$tekst) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $tekst
  $b.AutoSize = $true
  $b.MinimumSize = New-Object System.Drawing.Size(120, 36)
  $b.Margin = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
  $b.UseMnemonic = $false
  return $b
}
$script:BDodaj = Przycisk 'Dodaj'
$script:BNieTeraz = Przycisk 'Nie teraz'
$script:BZamknij = Przycisk 'Zamknij'
$script:BZamknij.Visible = $false
$p.Controls.Add($script:BDodaj); $p.Controls.Add($script:BNieTeraz); $p.Controls.Add($script:BZamknij)
$f.AcceptButton = $script:BDodaj

$t.Controls.Add($script:LTytul, 0, 0)
$t.Controls.Add($script:LTresc, 0, 1)
$t.Controls.Add($script:LStatus, 0, 2)
$t.Controls.Add($p, 0, 3)
$f.Controls.Add($t)

# Tekst zawija sie do szerokosci okna: przy kazdej zmianie rozmiaru etykiety dostaja nowa granice.
function Dopasuj-Teksty {
  $w = [Math]::Max(200, $t.ClientSize.Width - $t.Padding.Horizontal - 4)
  foreach ($l in @($script:LTytul, $script:LTresc, $script:LStatus)) { $l.MaximumSize = New-Object System.Drawing.Size($w, 0) }
}
$f.Add_Resize({ try { Dopasuj-Teksty } catch { Dopisz-Dziennik "zmiana rozmiaru: $($_.Exception.Message)" } })

function Pokaz-Status([string]$tekst, $kolor = $null) {
  $script:LStatus.Text = $tekst
  if ($kolor) { $script:LStatus.ForeColor = $kolor }
  $script:LStatus.Visible = $true
}

function Koniec-Instalacji {
  $wynik = $null; $tekst = ''
  try {
    $kod = $script:Proces.ExitCode
    $tekst = "$($script:Wy.Result)"
    $bl = ("$($script:Bl.Result)" -replace '[\r\n]+', ' ').Trim()
    if ($bl) { Dopisz-Dziennik "  bledy instalacji: $bl" }
    $ost = @($tekst -split "`r?`n" | Where-Object { $_ -like 'WYNIK: *' } | Select-Object -Last 1)
    if ($ost.Count) { $wynik = $ost[0].Substring(7) | ConvertFrom-Json }
  } catch { Dopisz-Dziennik "nie odczytalem wyniku instalacji: $($_.Exception.Message)" }
  foreach ($l in @($tekst -split "`r?`n" | Where-Object { $_ -match '^(KROK|UWAGA):' })) { Dopisz-Dziennik "  $l" }
  $script:BDodaj.Visible = $false
  $script:BNieTeraz.Visible = $false
  $script:BZamknij.Visible = $true
  $f.AcceptButton = $script:BZamknij
  if ($wynik -and ($wynik.ok -eq $true) -and ($kod -eq 0)) {
    $script:StanOkna = 'gotowe'
    Zapisz-Odpowiedz 'dodaj'
    $script:LTytul.Text = 'Wiedza firmy jest dodana'
    # w "..." - apostrof ’ PowerShell bierze za koniec napisu w apostrofach
    Pokaz-Status "Gotowe. Ten komputer sam zgłosi się do firmy, a wspólna wiedza pojawi się w rozmowach z Claude’em, gdy administrator go zatwierdzi." ([System.Drawing.Color]::FromArgb(20, 110, 50))
  } else {
    $script:StanOkna = 'blad'
    $kom = if ($wynik -and $wynik.komunikat) { "$($wynik.komunikat)" } elseif ($tekst.Trim()) { "skrypt skonczyl sie bez wyniku (kod $kod)" } else { "skrypt nic nie napisal (kod $kod)" }
    Zapisz-Odpowiedz 'dodaj-blad' $kom
    $script:LTytul.Text = 'Nie udało się dodać Wiedzy firmy'
    Pokaz-Status "Powód: $kom`r`nNic się nie zepsuło - zapytam znowu jutro. Jeśli to się powtarza, daj znać Przemkowi." ([System.Drawing.Color]::FromArgb(170, 30, 30))
  }
  Dopasuj-Teksty
}

$script:Zegar = New-Object System.Windows.Forms.Timer
$script:Zegar.Interval = 300
$script:Zegar.Add_Tick({
  try {
    if ($script:Proces -and $script:Proces.HasExited) { $script:Zegar.Stop(); $script:Proces.WaitForExit(); Koniec-Instalacji }
  } catch { $script:Zegar.Stop(); Dopisz-Dziennik "zegar instalacji: $($_.Exception.Message)" }
})

$script:BDodaj.Add_Click({
  try {
    $script:Odpowiedziano = $true
    $script:StanOkna = 'trwa'
    $script:BDodaj.Enabled = $false
    $script:BNieTeraz.Enabled = $false
    Pokaz-Status 'Dodaję Wiedzę firmy - to potrwa chwilę...'
    Dopasuj-Teksty
    # Osobny, ukryty proces z przechwyconym wyjsciem (jak Uruchom-Skrypt w wspolne.ps1) - umowa KROK/UWAGA/WYNIK.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $psi.Arguments = (@('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $SkryptModulu, '-Akcja', 'Instaluj',
                        '-KatalogDomowy', $KatalogDomowy, '-Zrodlo', $Zrodlo) | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $script:Utf8
    $psi.StandardErrorEncoding = $script:Utf8
    $script:Proces = [System.Diagnostics.Process]::Start($psi)
    $script:Wy = $script:Proces.StandardOutput.ReadToEndAsync()
    $script:Bl = $script:Proces.StandardError.ReadToEndAsync()
    Dopisz-Dziennik "Dodaj: instaluje modul (PID $($script:Proces.Id)): $SkryptModulu"
    $script:Zegar.Start()
  } catch {
    Dopisz-Dziennik "Dodaj: nie wystartowalem instalacji: $($_.Exception.Message)"
    $script:StanOkna = 'blad'
    Zapisz-Odpowiedz 'dodaj-blad' "nie wystartowala instalacja: $($_.Exception.Message)"
    Pokaz-Status "Nie udało się zacząć: $($_.Exception.Message). Zapytam znowu jutro." ([System.Drawing.Color]::FromArgb(170, 30, 30))
    $script:BZamknij.Visible = $true
  }
})
$script:BNieTeraz.Add_Click({
  $script:Odpowiedziano = $true
  $script:StanOkna = 'odpowiedziane'
  Zapisz-Odpowiedz 'nie-teraz'
  $f.Close()
})
$script:BZamknij.Add_Click({ $f.Close() })
$f.Add_FormClosing({
  if (-not $script:Odpowiedziano) { $script:Odpowiedziano = $true; Zapisz-Odpowiedz 'zamkniete' 'okno zamkniete bez odpowiedzi - jutro znowu' }
  elseif ($script:StanOkna -eq 'trwa') { Dopisz-Dziennik 'okno zamkniete w trakcie instalacji - instalacja idzie dalej w tle, wynik w rejestrze modulow' }
})
$f.Add_Shown({
  try {
    Dopasuj-Teksty
    if ($PozaEkranem) { [void][MegaRuchacz.PytanieWF]::ShowWindow($f.Handle, 4); return }   # SW_SHOWNOACTIVATE
    # Proces z ukryta konsola przekazuje SW_HIDE pierwszemu oknu (nadzorca 24.09.2026) - wymuszamy pokazanie.
    [void][MegaRuchacz.PytanieWF]::ShowWindow($f.Handle, 5)
    [void][MegaRuchacz.PytanieWF]::SetForegroundWindow($f.Handle)
  } catch { Dopisz-Dziennik "pokazanie okna: $($_.Exception.Message)" }
})

if ($Scenariusz) {
  try { . $Scenariusz } catch { Dopisz-Dziennik "scenariusz testu ${Scenariusz}: $($_.Exception.Message)" }
}

try {
  [System.Windows.Forms.Application]::EnableVisualStyles()
  [System.Windows.Forms.Application]::Run($f)
} catch {
  Dopisz-Dziennik "petla okna: $($_.Exception.Message)"
} finally {
  try { $script:Zamek.ReleaseMutex() } catch { Dopisz-Dziennik "zwolnienie zamka: $($_.Exception.Message)" }
  Dopisz-Dziennik "koniec okienka (stan: $($script:StanOkna))"
}
exit 0
