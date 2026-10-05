# zasobnik\terminy.ps1 - przypomnienia z terminem na pulpicie (decyzja uzytkownika 2026-10-05).
# Wola go nadzorca (zasobnik\nadzorca\stan-terminy.ps1) przy starcie i co godzine 8-20; mozna
# tez recznie. Plik przypomnien i cala jego logike ma narzedzia\terminy.js - tutaj tylko:
#
#   1. tryb "sam", termin dzis albo wczesniej, jeszcze nieuruchomione -> NAJPIERW status "w toku"
#      (terminy.js w-toku), POTEM widoczne okno terminala z Claude Code w katalogu projektu
#      i zadaniem jako pierwszym poleceniem. W tej kolejnosci, bo wywrotka po otwarciu okna
#      nie moze skonczyc sie drugim uruchomieniem - najwyzej jedno samoczynne na przypomnienie.
#      Kilka naraz: po kolei, kazde w osobnym oknie.
#   2. okno z przyciskami "Zrob teraz / Jutro / Zrobione" dla: trybu "przypomnij", spraw "w toku"
#      od wczoraj albo dawniej (automat nie dokonczyl) i uruchomien, ktore sie nie udaly. Okno
#      stoi na wierzchu i na pasku zadan, dopoki ktos nie kliknie. Krzyzyk przy nieobsluzonych
#      = wroci za 2 godziny (odlozone_do w przypomnienia-okno.txt).
#
# Slad "bylem tu", kazde uruchomienie i kazda wywrotka: ~\.claude\mr\przypomnienia.log.
#
# Uzycie:
#   powershell -NoProfile -ExecutionPolicy Bypass -File zasobnik\terminy.ps1 [-Zrodlo <repo>]
#     [-KatalogDomowy <kat>] [-Plik <plik przypomnien>] [-Dzis RRRR-MM-DD] [-Proba] [-BezOkna]
#   -Proba    nic nie uruchamia, nie zmienia i nie pokazuje - wypisuje, co by zrobil
#   -BezOkna  tylko samoczynne uruchomienia (punkt 1)
# Kod wyjscia: 0 ok (takze "nic do zrobienia"), 1 blad (opis w dzienniku i na stderr).
#
# Kod i komentarze bez polskich znakow; teksty w oknie i polecenie dla Claude z polskimi -
# dlatego plik MUSI miec BOM (PowerShell 5.1 czyta plik bez BOM jako ANSI).

param(
  [string]$Zrodlo = "",
  [string]$KatalogDomowy = "",
  [string]$Plik = "",
  [string]$Dzis = "",
  [switch]$Proba,
  [switch]$BezOkna
)

$ErrorActionPreference = "Stop"
# Domyslne sciezki pod param(), nie w nim - patrz pulapka PS 5.1 w mapie (instaluj-globalnie).
if (-not $Zrodlo) { $Zrodlo = Split-Path -Parent $PSScriptRoot }
if (-not $KatalogDomowy) { $KatalogDomowy = $HOME }
$Zrodlo = $Zrodlo.TrimEnd('\', '/')
$SkryptTerminow = Join-Path $Zrodlo "narzedzia\terminy.js"
if ($Plik) { $env:MR_PRZYPOMNIENIA = $Plik } else { $Plik = Join-Path $KatalogDomowy ".claude\mr\przypomnienia.md" }
if ($Dzis) { $env:MR_DZIS = $Dzis }
$KatStanu = Split-Path -Parent $Plik
$PlikOkna = Join-Path $KatStanu "przypomnienia-okno.txt"
$Dziennik = Join-Path $KatStanu "przypomnienia.log"
$KatUruchomien = Join-Path $KatStanu "terminy"

# Krzyzyk = wroc za tyle minut (decyzja uzytkownika: 2 godziny, "nie gubimy sprawy").
$MINUT_ODLOZENIA = 120
# Odstep miedzy kolejnymi samoczynnymi oknami - zeby kilka terminali nie wstawalo w jednej
# chwili jeden na drugim (Windows Terminal potrafi wtedy zgubic kolejnosc kart).
$SEKUND_MIEDZY_URUCHOMIENIAMI = 3
# Dziennik rosnie o kilka linii na godzine; powyzej tego rozmiaru zostaje jego koncowka.
$MAX_DZIENNIKA = 512KB

function Bez-Bom { return (New-Object System.Text.UTF8Encoding($false)) }

function Dopisz-Dziennik([string]$tekst) {
  $linia = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "  " + $tekst
  if ($Proba) { Write-Host "[proba] $linia"; return }
  try {
    if (-not (Test-Path -LiteralPath $KatStanu)) { New-Item -ItemType Directory -Force -Path $KatStanu | Out-Null }
    if ((Test-Path -LiteralPath $Dziennik) -and ((Get-Item -LiteralPath $Dziennik).Length -gt $MAX_DZIENNIKA)) {
      $ogon = @([System.IO.File]::ReadAllLines($Dziennik, [System.Text.Encoding]::UTF8) | Select-Object -Last 400)
      [System.IO.File]::WriteAllLines($Dziennik, [string[]]$ogon, (Bez-Bom))
    }
    [System.IO.File]::AppendAllText($Dziennik, $linia + "`r`n", (Bez-Bom))
  } catch {
    # Dziennik jest jedynym sladem - gdy i on padl, zostaje stderr (nadzorca go nie czyta, ale
    # reczne uruchomienie zobaczy) i kod wyjscia.
    [Console]::Error.WriteLine("terminy.ps1: nie zapisalem dziennika ${Dziennik}: $($_.Exception.Message) | $tekst")
    $script:BladDziennika = $true
  }
}

function Czytaj-Klucze-Okna {
  $k = @{}
  if (-not (Test-Path -LiteralPath $PlikOkna)) { return $k }
  foreach ($l in [System.IO.File]::ReadAllLines($PlikOkna, [System.Text.Encoding]::UTF8)) {
    if ($l -match '^\s*([A-Za-z_.]+)\s*:\s*(.*?)\s*$') { $k[$matches[1]] = $matches[2] }
  }
  return $k
}

function Zapisz-Klucz-Okna([string]$klucz, [string]$wartosc) {
  if ($Proba) { Write-Host "[proba] przypomnienia-okno.txt: $klucz = $wartosc"; return }
  $k = Czytaj-Klucze-Okna
  $k[$klucz] = $wartosc
  $tekst = (@($k.Keys | Sort-Object | ForEach-Object { "${_}: $($k[$_])" }) -join "`r`n") + "`r`n"
  [System.IO.File]::WriteAllText($PlikOkna, $tekst, (Bez-Bom))
}

# terminy.js osobnym procesem, bez okna konsoli, z wyjsciem odczytanym jako UTF-8 (strona
# kodowa konsoli psulaby polskie litery w komunikatach bledow).
function Wolaj-Terminy([string[]]$argumenty) {
  $w = [pscustomobject]@{ Kod = -1; Tekst = ""; Blad = "" }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $script:Node
  $psi.Arguments = (@($SkryptTerminow) + $argumenty | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join " "
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  $p = [System.Diagnostics.Process]::Start($psi)
  $bl = $p.StandardError.ReadToEndAsync()
  $w.Tekst = $p.StandardOutput.ReadToEnd()
  $p.WaitForExit()
  $w.Blad = $bl.Result.Trim()
  $w.Kod = $p.ExitCode
  return $w
}

function Zmien-Status([string]$polecenie, [string[]]$reszta, [string]$opis) {
  if ($Proba) { Write-Host "[proba] node terminy.js $polecenie $($reszta -join ' ')"; return $true }
  $r = Wolaj-Terminy (@($polecenie) + $reszta)
  if ($r.Kod -eq 0) { Dopisz-Dziennik "$opis - ok"; return $true }
  Dopisz-Dziennik "$opis - NIE WYSZLO (kod $($r.Kod)): $($r.Blad) $($r.Tekst.Trim())"
  $script:OstatniBladStatusu = "$($r.Blad) $($r.Tekst.Trim())".Trim()
  return $false
}

# --------------------------------------------------------------- Claude Code w terminalu

# Wprost claude.exe, gdy da sie go znalezc: shim npm "claude.cmd" przepuszcza argument przez
# cmd.exe, ktory rozwija %ZMIENNE% i potyka sie na znakach specjalnych w tresci zadania.
function Sciezka-Claude {
  $c = Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $c) { return $null }
  $s = $c.Source
  if ($s -match '\.(cmd|bat|ps1)$' -or -not [System.IO.Path]::GetExtension($s)) {
    $exe = Join-Path (Split-Path -Parent $s) "node_modules\@anthropic-ai\claude-code\bin\claude.exe"
    if (Test-Path -LiteralPath $exe) { return $exe }
  }
  return $s
}

# Napis w pojedynczych cudzyslowach PowerShella. Za cudzyslow pojedynczy PS bierze tez
# ‘ ’ ‚ ‛ - zamieniamy je na zwykly apostrof i dopiero wtedy podwajamy.
function Napis-PS([string]$t) {
  $t = $t -replace "[‘’‚‛]", "'"
  return "'" + ($t -replace "'", "''") + "'"
}

function Polecenie-Dla-Claude($p, [string]$katalog) {
  $skrypt = $SkryptTerminow.Replace('\', '/')
  $tresc = ($p.tresc -replace '"', "'").TrimEnd('.', ' ')   # kropke dostawia zdanie nizej
  if ($p.sprawdz) { $tresc += " (jak sprawdzić: " + ($p.sprawdz -replace '"', "'") + ")" }
  $gdzie = ""
  if ($katalog -ne $p.projekt) { $gdzie = " Uwaga: katalogu projektu '" + $p.projekt + "' nie ma na tym komputerze - okno otwarte w katalogu domowym; ustal najpierw, gdzie leży projekt." }
  return ("Zadanie z przypomnienia $($p.id) zaplanowane na $($p.termin): $tresc. Wykonaj je.$gdzie " +
          "Niczego nie zmieniaj na produkcji ani w sklepach bez wyraźnego polecenia użytkownika — przygotuj propozycję. " +
          "Na koniec krótki raport po polsku i odhacz przypomnienie: node '$skrypt' zrobione $($p.id)")
}

# Otwiera WIDOCZNE okno: Windows Terminal (karta w nowym oknie), a gdy go nie ma - zwykla
# konsola PowerShella. Polecenie idzie przez maly skrypt startowy w ~\.claude\mr\terminy\
# (zostaje jako slad, co dokladnie uruchomiono), bo wiersz polecen wt.exe rozcina tekst na ";".
# Zwraca opis albo rzuca wyjatek z powodem.
function Uruchom-Claude($p, [string]$jak) {
  $kat = "$($p.projekt)"
  if (-not $kat -or -not (Test-Path -LiteralPath $kat -PathType Container)) { $kat = $KatalogDomowy }
  $kat = [System.IO.Path]::GetFullPath($kat).TrimEnd('\')
  if ($kat -match '^[A-Za-z]:$') { $kat += '\.' }
  $claude = Sciezka-Claude
  if (-not $claude) { throw "nie ma polecenia claude w PATH - Claude Code nie jest zainstalowany albo PATH tego procesu go nie widzi" }
  $polecenie = Polecenie-Dla-Claude $p $kat
  $start = Join-Path $KatUruchomien "zrob-$($p.id).ps1"
  $tresc = @(
    "# MegaRuchacz: przypomnienie #$($p.id) - $jak $(Get-Date -Format 'yyyy-MM-dd HH:mm') (zasobnik\terminy.ps1)",
    ('$Host.UI.RawUI.WindowTitle = ' + (Napis-PS "MegaRuchacz - przypomnienie #$($p.id)")),
    ('Set-Location -LiteralPath ' + (Napis-PS $kat)),
    ('$polecenie = ' + (Napis-PS $polecenie)),
    ('& ' + (Napis-PS $claude) + ' $polecenie')
  ) -join "`r`n"
  if ($Proba) {
    Write-Host "[proba] otworzylbym Claude Code w $kat ($jak):"
    Write-Host "        $polecenie"
    return "proba"
  }
  if (-not (Test-Path -LiteralPath $KatUruchomien)) { New-Item -ItemType Directory -Force -Path $KatUruchomien | Out-Null }
  [System.IO.File]::WriteAllText($start, $tresc + "`r`n", (New-Object System.Text.UTF8Encoding($true)))
  $ps = @("-NoExit", "-ExecutionPolicy", "Bypass", "-File", ('"' + $start + '"'))
  $wt = Get-Command wt.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($wt) {
    $arg = @("-w", "new", "new-tab", "-d", ('"' + $kat + '"'), "--title", ('"MegaRuchacz #' + $p.id + '"'), "powershell.exe") + $ps
    Start-Process -FilePath $wt.Source -ArgumentList $arg | Out-Null
    return "Windows Terminal, katalog $kat, skrypt startowy $start"
  }
  Start-Process -FilePath "powershell.exe" -WorkingDirectory $kat -ArgumentList $ps | Out-Null
  return "konsola PowerShell (brak Windows Terminal), katalog $kat, skrypt startowy $start"
}

# -------------------------------------------------------------------- okno z przyciskami

function Okno-Przypomnien($pozycje) {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  [System.Windows.Forms.Application]::EnableVisualStyles()
  $script:Obsluzone = @{}
  $script:Pozostalo = @($pozycje).Count

  $f = New-Object System.Windows.Forms.Form
  $f.Text = "MegaRuchacz - przypomnienia ($(@($pozycje).Count))"
  $f.TopMost = $true
  $f.ShowInTaskbar = $true
  $f.StartPosition = "CenterScreen"
  $f.Font = New-Object System.Drawing.Font("Segoe UI", 10)
  $f.BackColor = [System.Drawing.Color]::White
  $f.Width = 780
  $f.Height = [Math]::Min(760, 170 + 150 * @($pozycje).Count)
  $f.MinimizeBox = $true
  $f.MaximizeBox = $false
  $ikona = Join-Path $Zrodlo "logo.png"
  if (Test-Path -LiteralPath $ikona) {
    try {
      $obraz = [System.Drawing.Image]::FromFile($ikona)
      $f.Icon = [System.Drawing.Icon]::FromHandle((New-Object System.Drawing.Bitmap($obraz, 32, 32)).GetHicon())
      $obraz.Dispose()
    } catch { Dopisz-Dziennik "ikona okna: $($_.Exception.Message)" }
  }

  $lista = New-Object System.Windows.Forms.FlowLayoutPanel
  $lista.Dock = "Fill"
  $lista.FlowDirection = "TopDown"
  $lista.WrapContents = $false
  $lista.AutoScroll = $true
  $lista.Padding = New-Object System.Windows.Forms.Padding(14, 10, 14, 10)
  $f.Controls.Add($lista)

  $wstep = New-Object System.Windows.Forms.Label
  $wstep.AutoSize = $true
  $wstep.MaximumSize = New-Object System.Drawing.Size(720, 0)
  $wstep.Text = "Te sprawy mają termin dziś albo już minął. Wybierz, co z każdą zrobić. " +
                "Zamknięcie okna krzyżykiem = przypomnę ponownie za 2 godziny."
  $wstep.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
  $lista.Controls.Add($wstep)

  foreach ($p in @($pozycje)) {
    $karta = New-Object System.Windows.Forms.FlowLayoutPanel
    $karta.FlowDirection = "TopDown"
    $karta.WrapContents = $false
    $karta.AutoSize = $true
    $karta.BorderStyle = "FixedSingle"
    $karta.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)
    $karta.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $karta.MinimumSize = New-Object System.Drawing.Size(720, 0)

    $glowa = New-Object System.Windows.Forms.Label
    $glowa.AutoSize = $true
    $glowa.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $glowa.Text = "#$($p.id)   $($p.termin) ($($p.opis))   $($p.projekt)"
    $karta.Controls.Add($glowa)

    $tekst = New-Object System.Windows.Forms.Label
    $tekst.AutoSize = $true
    $tekst.MaximumSize = New-Object System.Drawing.Size(690, 0)
    $tekst.Text = $p.tresc
    if ($p.sprawdz) { $tekst.Text += "`r`nJak sprawdzić: $($p.sprawdz)" }
    $karta.Controls.Add($tekst)

    if ($p.uwaga) {
      $uw = New-Object System.Windows.Forms.Label
      $uw.AutoSize = $true
      $uw.MaximumSize = New-Object System.Drawing.Size(690, 0)
      $uw.ForeColor = [System.Drawing.Color]::FromArgb(170, 40, 20)
      $uw.Text = $p.uwaga
      $karta.Controls.Add($uw)
    }

    $przyciski = New-Object System.Windows.Forms.FlowLayoutPanel
    $przyciski.AutoSize = $true
    $przyciski.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    foreach ($b in @(@("Zrób teraz", "teraz"), @("Jutro", "jutro"), @("Zrobione", "zrobione"))) {
      $btn = New-Object System.Windows.Forms.Button
      $btn.Text = $b[0]
      $btn.AccessibleName = "$($b[0]) #$($p.id)"
      $btn.AutoSize = $true
      $btn.Padding = New-Object System.Windows.Forms.Padding(8, 2, 8, 2)
      $btn.Tag = @{ Akcja = $b[1]; Poz = $p; Karta = $karta }
      $btn.Add_Click({ Klik $this.Tag })
      $przyciski.Controls.Add($btn)
    }
    $karta.Controls.Add($przyciski)
    $lista.Controls.Add($karta)
  }

  $f.Add_FormClosing({
    param($s, $e)
    if ($script:Pozostalo -gt 0) {
      $do = (Get-Date).AddMinutes($MINUT_ODLOZENIA)
      try { Zapisz-Klucz-Okna "odlozone_do" $do.ToString("yyyy-MM-dd HH:mm:ss") }
      catch { Dopisz-Dziennik "zapis odlozenia sie nie udal: $($_.Exception.Message)" }
      Dopisz-Dziennik "okno zamkniete bez obslugi $($script:Pozostalo) spraw - wroce o $($do.ToString('HH:mm'))"
    } else {
      Dopisz-Dziennik "okno zamkniete - wszystko obsluzone"
    }
  })
  $script:Okno = $f
  $f.Add_Shown({ $f.Activate() })
  Dopisz-Dziennik ("okno pokazane: " + ((@($pozycje) | ForEach-Object { "#$($_.id)" }) -join ", "))
  Zapisz-Klucz-Okna "pokazane" (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  [void]$f.ShowDialog()
  $f.Dispose()
}

function Klik($tag) {
  $p = $tag.Poz
  $ok = $false
  $script:OstatniBladStatusu = ""
  try {
    switch ($tag.Akcja) {
      "teraz" {
        $arg = @("$($p.id)")
        if ($p.status -eq "w toku") { $arg += "--ponownie" }
        if (Zmien-Status "w-toku" $arg "przycisk Zrob teraz #$($p.id): status w toku") {
          $jak = Uruchom-Claude $p "uruchomione przyciskiem"
          Dopisz-Dziennik "przycisk Zrob teraz #$($p.id): $jak"
          $ok = $true
        }
      }
      "jutro"    { $ok = Zmien-Status "przesun" @("$($p.id)", "jutro") "przycisk Jutro #$($p.id)" }
      "zrobione" { $ok = Zmien-Status "zrobione" @("$($p.id)") "przycisk Zrobione #$($p.id)" }
    }
  } catch {
    $script:OstatniBladStatusu = $_.Exception.Message
    Dopisz-Dziennik "przycisk $($tag.Akcja) #$($p.id) - WYWROTKA: $($_.Exception.Message)"
  }
  if (-not $ok) {
    [void][System.Windows.Forms.MessageBox]::Show($script:Okno,
      "Nie udało się ($($tag.Akcja), przypomnienie #$($p.id)): $($script:OstatniBladStatusu)`r`n`r`nSzczegóły: $Dziennik",
      "MegaRuchacz", "OK", "Warning")
    return
  }
  $tag.Karta.Visible = $false
  $script:Pozostalo--
  if ($script:Pozostalo -le 0) { $script:Okno.Close() }
}

# ------------------------------------------------------------------------- przebieg

$kod = 0
$zamekStartu = $null
try {
  $nodeCmd = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $nodeCmd) { throw "nie ma node w PATH - przypomnien nie da sie przeczytac" }
  $script:Node = $nodeCmd.Source
  if (-not (Test-Path -LiteralPath $SkryptTerminow)) { throw "nie ma $SkryptTerminow" }

  # Jedna kopia czesci uruchamiajacej naraz - dwie odpalone jednoczesnie otworzylyby to samo
  # zadanie dwa razy, zanim pierwsza zdazy zapisac "w toku".
  $zamekStartu = New-Object System.Threading.Mutex($false, "Local\MegaRuchacz-Terminy-Start")
  if (-not $zamekStartu.WaitOne(0)) {
    Dopisz-Dziennik "inna kopia wlasnie uruchamia przypomnienia - ta konczy"
    $zamekStartu.Dispose(); $zamekStartu = $null
    exit 0
  }

  $r = Wolaj-Terminy @("zalegle", "--json")
  if ($r.Kod -ne 0) { throw "terminy.js zalegle --json: kod $($r.Kod) $($r.Blad)" }
  $dane = $r.Tekst | ConvertFrom-Json
  foreach ($n in @($dane.nieczytelne)) { if ($n) { Dopisz-Dziennik "UWAGA plik przypomnien, $n" } }
  $zalegle = @($dane.zalegle | Where-Object { $_ })
  $dzis = $dane.dzis

  $doOkna = @()
  $uruchomione = 0
  foreach ($p in $zalegle) {
    $p | Add-Member -NotePropertyName uwaga -NotePropertyValue "" -Force
    if ($p.status -eq "otwarte" -and $p.tryb -eq "sam") {
      if ($uruchomione -gt 0 -and -not $Proba) { Start-Sleep -Seconds $SEKUND_MIEDZY_URUCHOMIENIAMI }
      if (-not (Zmien-Status "w-toku" @("$($p.id)") "samoczynne #$($p.id): status w toku")) {
        $p.uwaga = "Automat nie zdołał oznaczyć sprawy jako »w toku« i jej nie uruchomił: $($script:OstatniBladStatusu)"
        $doOkna += $p
        continue
      }
      try {
        $jak = Uruchom-Claude $p "uruchomione samoczynnie"
        Dopisz-Dziennik "samoczynne #$($p.id) ($($p.termin), $($p.projekt)): $jak"
        $uruchomione++
      } catch {
        Dopisz-Dziennik "samoczynne #$($p.id) - NIE OTWORZYLEM Claude Code: $($_.Exception.Message)"
        $p.status = "w toku"
        $p.uwaga = "Automat nie zdołał otworzyć Claude Code: $($_.Exception.Message)"
        $doOkna += $p
      }
      continue
    }
    if ($p.status -eq "otwarte") { $doOkna += $p; continue }   # tryb "przypomnij"
    # "w toku": od dzis = jeszcze chodzi, nie przeszkadzamy; od wczoraj albo dawniej = nie dokonczone
    $od = "$($p.wTokuOd)"
    if ($od.Length -ge 10 -and $od.Substring(0, 10) -lt $dzis) {
      if ($p.tryb -eq "sam") { $p.uwaga = "Automat uruchomił to zadanie $od, ale nie zostało dokończone (nie odhaczone)." }
      else { $p.uwaga = "Uruchomione $od, ale nie zostało dokończone (nie odhaczone)." }
      $doOkna += $p
    }
  }
  $zamekStartu.ReleaseMutex(); $zamekStartu.Dispose(); $zamekStartu = $null

  $dopisek = ""
  if ($doOkna.Count -gt 0) { $dopisek = ", do okna: " + (($doOkna | ForEach-Object { "#$($_.id)" }) -join ", ") }
  Dopisz-Dziennik "sprawdzenie: zaleglych $($zalegle.Count), uruchomionych samoczynnie $uruchomione$dopisek"

  if ($doOkna.Count -gt 0 -and -not $BezOkna) {
    # Niepowodzenia z tego przebiegu ida od razu, mimo odlozenia - nie moga czekac w ciszy.
    $pilne = @($doOkna | Where-Object { $_.uwaga -like "Automat nie zdo*" })
    $odlozone = $null
    $k = Czytaj-Klucze-Okna
    if ($k["odlozone_do"]) { try { $odlozone = [datetime]::ParseExact($k["odlozone_do"], "yyyy-MM-dd HH:mm:ss", $null) } catch { Dopisz-Dziennik "nieczytelne odlozone_do: $($k['odlozone_do'])" } }
    if ($odlozone -and (Get-Date) -lt $odlozone -and $pilne.Count -eq 0) {
      Dopisz-Dziennik "okno odlozone krzyzykiem do $($odlozone.ToString('HH:mm')) - nie pokazuje"
    } elseif ($Proba) {
      Write-Host "[proba] pokazalbym okno z: $(($doOkna | ForEach-Object { "#$($_.id) $($_.tresc) $($_.uwaga)" }) -join ' || ')"
    } else {
      $zamekOkna = New-Object System.Threading.Mutex($false, "Local\MegaRuchacz-Terminy-Okno")
      if ($zamekOkna.WaitOne(0)) {
        try { Okno-Przypomnien $doOkna } finally { $zamekOkna.ReleaseMutex(); $zamekOkna.Dispose() }
      } else {
        $zamekOkna.Dispose()
        Dopisz-Dziennik "okno przypomnien juz stoi na ekranie - drugiego nie otwieram"
      }
    }
  }
} catch {
  $kod = 1
  Dopisz-Dziennik "WYWROTKA: $($_.Exception.Message)"
  [Console]::Error.WriteLine("terminy.ps1: $($_.Exception.Message)")
} finally {
  if ($zamekStartu) { try { $zamekStartu.ReleaseMutex() } catch { Dopisz-Dziennik "zamek startu: $($_.Exception.Message)" }; $zamekStartu.Dispose() }
}
if ($script:BladDziennika) { $kod = 1 }
exit $kod
