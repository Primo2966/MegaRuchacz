# instalator\wykonanie.ps1 - czesc okna instalatora (patrz BUDOWA w naglowku instalator\okno.ps1).
# Wykonanie krokow: kazdy skrypt (modul-*.ps1, zaleznosci.ps1, wpisz-zasady.ps1, pobierz.ps1)
# idzie w OSOBNYM, niewidocznym procesie powershell.exe; zegar okna co 150 ms doczytuje to,
# co proces dopisal do pliku wyjscia, i rozpoznaje linie umowy z P59b:
#   KROK: ...    kolejny krok (lista pod wierszem i pasek postepu)
#   UWAGA: ...   rzecz do sprawdzenia - krok sie udal, ale ma byc widac
#   WYNIK: {"ok":true/false,"komunikat":"...","kroki":[...]}   ostatnia linia, kod wyjscia 0/1
# Plan to lista takich krokow wykonywana po kolei; blad zatrzymuje plan, "Sprobuj ponownie"
# powtarza tylko krok, ktory sie nie udal.
#
# DLACZEGO PLIK, A NIE ZDARZENIA PROCESU: OutputDataReceived przychodzi w watku puli,
# a blok PowerShella w obcym watku wywraca proces; watki-runspace'y ze skladanym kodem
# wygladaly Defenderowi na omijanie zabezpieczen (nadzorca, P38). Plik + zegar okna = zero
# watkow, okno reaguje, a wyjscie widac na biezaco.
# POLSKIE ZNAKI: okno ustawia konsoli UTF-8 (okno.ps1), proces-dziecko dzieli z nim konsole
# (-NoNewWindow), wiec pisze w UTF-8. Gdyby ktorys skrypt przestawil sie na strone kodowa
# konsoli, linia, ktora nie jest poprawnym UTF-8, czytana jest w stronie kodowej OEM.
# Skad wolane: ekrany.ps1 (plan, sprawdzenie programow). Wczytuje go okno.ps1 kropka.

$script:Aktywne       = New-Object System.Collections.ArrayList
$script:ZegarZadan    = $null
$script:Tyk           = 0
$script:PoTyknieciu   = $null
$script:Utf8Scisly    = New-Object System.Text.UTF8Encoding($false, $true)
$script:KodowanieOem  = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
$script:PowerShellExe = Join-Path $PSHOME 'powershell.exe'
$script:Plan          = $null
$script:PlanIndeks    = 0
$script:PlanStan      = ''
$script:PoPlanie      = $null
$script:PoBledziePlanu = $null

function Nowe-Zadanie {
  param([string]$Id, [string]$Napis, [string]$Plik = '', [object[]]$Argumenty = @(), [bool]$Umowa = $true, [scriptblock]$Wewnetrzne = $null)
  return [pscustomobject]@{
    Id = $Id; Napis = $Napis; Plik = $Plik; Argumenty = $Argumenty; Umowa = $Umowa; Wewnetrzne = $Wewnetrzne
    PoSukcesie = $null; PoKoncu = $null
    Stan = 'czeka'; Od = $null; Koniec = $null; OstatniZnak = $null; Proby = 0
    Linie = (New-Object System.Collections.Generic.List[string])
    Kroki = (New-Object System.Collections.Generic.List[string])
    Uwagi = (New-Object System.Collections.Generic.List[string])
    Wynik = $null; WynikBlad = ''; Komunikat = ''; Kod = $null
    Proces = $null; PlikWy = $null; PlikBl = $null; Pozycja = [long]0
    Bufor = (New-Object System.Collections.Generic.List[byte])
  }
}

# Argument w wierszu polecen wg zasad CommandLineToArgvW: cudzyslow, gdy jest spacja,
# podwojone ukosniki przed cudzyslowem i na koncu (sciezka "C:\Users\X\" inaczej
# zjadlaby zamykajacy cudzyslow).
function Cytuj-Argument([string]$a) {
  if ($a -eq '') { return '""' }
  if ($a -notmatch '[\s"]') { return $a }
  $w = New-Object System.Text.StringBuilder
  [void]$w.Append('"')
  $ukosniki = 0
  foreach ($c in $a.ToCharArray()) {
    if ($c -eq [char]92) { $ukosniki++; continue }
    if ($c -eq [char]34) { [void]$w.Append([char]92, (2 * $ukosniki + 1)); [void]$w.Append([char]34); $ukosniki = 0; continue }
    if ($ukosniki -gt 0) { [void]$w.Append([char]92, $ukosniki); $ukosniki = 0 }
    [void]$w.Append($c)
  }
  if ($ukosniki -gt 0) { [void]$w.Append([char]92, (2 * $ukosniki)) }
  [void]$w.Append('"')
  return $w.ToString()
}

# PATH procesu okna zostaje z chwili startu, a zaleznosci.ps1 dopisuje nowe programy do PATH
# uzytkownika w rejestrze. Bez odswiezenia kolejne kroki (dzieci okna) nie widzialyby uv, gita
# ani Node'a zainstalowanych minute wczesniej.
function Odswiez-Path {
  try {
    $czesci = New-Object System.Collections.Generic.List[string]
    foreach ($zrodlo in @([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User'), $env:Path)) {
      foreach ($e in "$zrodlo".Split(';')) {
        $e = [Environment]::ExpandEnvironmentVariables($e.Trim())
        if ($e -and -not $czesci.Contains($e)) { $czesci.Add($e) }
      }
    }
    $env:Path = ($czesci -join ';')
  } catch { Zapisz-Dziennik "odswiezenie PATH nie wyszlo ($($_.Exception.Message)) - zostaje dotychczasowy" }
}

function Wlacz-Zegar-Zadan {
  if (-not $script:ZegarZadan) {
    $script:ZegarZadan = New-Object System.Windows.Forms.Timer
    $script:ZegarZadan.Interval = 150
    $script:ZegarZadan.Add_Tick({
      try { Tyknij-Zadania }
      catch { Zanotuj-Wywrotke "zegar krokow" $_ }
    })
  }
  if (-not $script:ZegarZadan.Enabled) { $script:ZegarZadan.Start() }
}

function Uruchom-Zadanie($z) {
  $z.Stan = 'trwa'; $z.Od = Get-Date; $z.OstatniZnak = $z.Od; $z.Koniec = $null; $z.Komunikat = ''
  $z.Linie.Clear(); $z.Kroki.Clear(); $z.Uwagi.Clear(); $z.Bufor.Clear()
  $z.Wynik = $null; $z.WynikBlad = ''; $z.Kod = $null; $z.Pozycja = [long]0
  $z.Proby++
  Zapisz-Dziennik "START $($z.Id) (podejscie $($z.Proby)): $($z.Napis)"
  [void]$script:Aktywne.Add($z)
  Wlacz-Zegar-Zadan
  if ($z.Wewnetrzne) { return }   # krok w samym oknie - liczony przy tyknieciu zegara
  if (-not (Test-Path -LiteralPath $z.Plik)) {
    Zakoncz-Zadanie $z 'blad' "Brakuje pliku $($z.Plik) - ta wersja MegaRuchacza jest niekompletna. Pobierz nowszą i uruchom instalator jeszcze raz."
    return
  }
  try {
    Odswiez-Path
    $z.PlikWy = [System.IO.Path]::GetTempFileName()
    $z.PlikBl = [System.IO.Path]::GetTempFileName()
    $lista = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $z.Plik) + @($z.Argumenty)
    $linia = (@($lista | ForEach-Object { Cytuj-Argument "$_" })) -join ' '
    Zapisz-Dziennik "  polecenie: powershell.exe $linia"
    # -NoNewWindow: dziecko dzieli niewidoczna konsole okna - zadnego mrugniecia.
    $p = Start-Process -FilePath $script:PowerShellExe -ArgumentList $linia -NoNewWindow -PassThru -RedirectStandardOutput $z.PlikWy -RedirectStandardError $z.PlikBl
    $null = $p.Handle   # bez dotkniecia uchwytu ExitCode zostaje pusty po zakonczeniu (jak w nadzorcy)
    $z.Proces = $p
  } catch {
    Sprzatnij-Proces $z
    Zakoncz-Zadanie $z 'blad' "Nie udało się uruchomić skryptu $($z.Plik): $($_.Exception.Message)"
  }
}

function Dekoduj-Linie([byte[]]$b) {
  $n = $b.Length
  if (($n -gt 0) -and ($b[$n - 1] -eq 13)) { $n-- }
  $t = ''
  try { $t = $script:Utf8Scisly.GetString($b, 0, $n) }
  catch { $t = $script:KodowanieOem.GetString($b, 0, $n) }
  return $t.TrimStart([char]0xFEFF)
}

function Przetworz-Linie($z, [string]$t) {
  $z.Linie.Add($t)
  $z.OstatniZnak = Get-Date
  Zapisz-Dziennik "  [$($z.Id)] $t"
  if ($t -match '^\s*KROK:\s*(.*)$') { $z.Kroki.Add($Matches[1].Trim()) }
  elseif ($t -match '^\s*UWAGA:\s*(.*)$') { $z.Uwagi.Add($Matches[1].Trim()) }
  elseif ($t -match '^\s*WYNIK:\s*(.*)$') {
    $json = $Matches[1].Trim()
    try { $z.Wynik = $json | ConvertFrom-Json; $z.WynikBlad = '' }
    catch { $z.Wynik = $null; $z.WynikBlad = "$($_.Exception.Message)" }
  }
}

# Doczytanie tego, co proces dopisal od ostatniego razu. Plik otwarty z FileShare.ReadWrite -
# proces dalej do niego pisze. Niepelna ostatnia linia czeka w buforze na swoj koniec.
function Czytaj-Przyrost($z) {
  if (-not $z.PlikWy -or -not (Test-Path -LiteralPath $z.PlikWy)) { return }
  $buf = $null; $czyt = 0
  $fs = [System.IO.File]::Open($z.PlikWy, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
  try {
    if ($fs.Length -le $z.Pozycja) { return }
    [void]$fs.Seek($z.Pozycja, [System.IO.SeekOrigin]::Begin)
    $buf = New-Object byte[] ([int]($fs.Length - $z.Pozycja))
    $czyt = $fs.Read($buf, 0, $buf.Length)
    $z.Pozycja += $czyt
  } finally { $fs.Dispose() }
  $start = 0
  while ($start -lt $czyt) {
    $nl = [Array]::IndexOf($buf, [byte]10, $start, $czyt - $start)
    if ($nl -lt 0) { break }
    $dl = $nl - $start
    $linia = New-Object byte[] ($z.Bufor.Count + $dl)
    $z.Bufor.CopyTo($linia, 0)
    [Array]::Copy($buf, $start, $linia, $z.Bufor.Count, $dl)
    $z.Bufor.Clear()
    Przetworz-Linie $z (Dekoduj-Linie $linia)
    $start = $nl + 1
  }
  if ($start -lt $czyt) {
    $reszta = New-Object byte[] ($czyt - $start)
    [Array]::Copy($buf, $start, $reszta, 0, $reszta.Length)
    $z.Bufor.AddRange($reszta)
  }
}

function Domknij-Bufor($z) {
  if ($z.Bufor.Count -eq 0) { return }
  $linia = $z.Bufor.ToArray()
  $z.Bufor.Clear()
  Przetworz-Linie $z (Dekoduj-Linie $linia)
}

function Czytaj-Bledy($z) {
  $w = @()
  if (-not $z.PlikBl -or -not (Test-Path -LiteralPath $z.PlikBl)) { return ,$w }
  $b = [System.IO.File]::ReadAllBytes($z.PlikBl)
  $start = 0
  for ($i = 0; $i -le $b.Length; $i++) {
    if (($i -eq $b.Length) -or ($b[$i] -eq 10)) {
      if ($i -gt $start) {
        $kaw = New-Object byte[] ($i - $start)
        [Array]::Copy($b, $start, $kaw, 0, $kaw.Length)
        $t = (Dekoduj-Linie $kaw).Trim()
        if ($t) { $w += $t }
      }
      $start = $i + 1
    }
  }
  return ,$w
}

function Sprzatnij-Proces($z) {
  if ($z.Proces) {
    try { $z.Proces.Dispose() } catch { Zapisz-Dziennik "nie zwolnilem procesu kroku $($z.Id): $($_.Exception.Message)" }
  }
  foreach ($p in @($z.PlikWy, $z.PlikBl)) {
    if ($p -and (Test-Path -LiteralPath $p)) {
      try { Remove-Item -LiteralPath $p -Force } catch { Zapisz-Dziennik "nie skasowalem pliku roboczego $p : $($_.Exception.Message)" }
    }
  }
  $z.Proces = $null; $z.PlikWy = $null; $z.PlikBl = $null
}

# Ostatnie zdanie procesu, ktore nie jest linia umowy - do komunikatu, gdy skrypt padl bez wyniku.
function Ostatnie-Slowa($z, $bledy) {
  $kand = @($bledy) + @($z.Linie | Where-Object { $_.Trim() -and ($_ -notmatch '^\s*(KROK|UWAGA|WYNIK):') })
  $kand = @($kand | Where-Object { $_ })
  if ($kand.Count -eq 0) { return 'Nic nie napisał.' }
  $t = "$($kand[$kand.Count - 1])".Trim()
  if (@($bledy).Count -gt 0) { $t = "$(@($bledy)[0])".Trim() }
  if ($t.Length -gt 300) { $t = $t.Substring(0, 300) + '...' }
  return "Ostatnie, co napisał: $t"
}

# Proces skonczyl: decyzja z WYNIK i kodu wyjscia. Niezgodnosc (ok:true i kod 1, brak WYNIK,
# nieczytelny WYNIK) to blad - instalator nie wierzy na slowo, bo krok udajacy sukces
# zostawilby czlowieka z polowa instalacji i zielonym ptaszkiem.
function Rozstrzygnij($z) {
  $kod = $null
  try { $kod = $z.Proces.ExitCode } catch { Zapisz-Dziennik "kod wyjscia kroku $($z.Id) nieznany: $($_.Exception.Message)" }
  $z.Kod = $kod
  $bledy = @()
  try { $bledy = Czytaj-Bledy $z } catch { Zapisz-Dziennik "nie odczytalem bledow kroku $($z.Id): $($_.Exception.Message)" }
  foreach ($l in $bledy) { $z.Linie.Add("[błąd] $l"); Zapisz-Dziennik "  [$($z.Id)] [blad] $l" }
  Sprzatnij-Proces $z
  if ($z.Umowa) {
    if ($z.WynikBlad) { Zakoncz-Zadanie $z 'blad' "Skrypt oddał wynik, którego nie umiem odczytać ($($z.WynikBlad))."; return }
    if (-not $z.Wynik) { Zakoncz-Zadanie $z 'blad' "Skrypt skończył pracę bez wyniku (kod wyjścia $kod). $(Ostatnie-Slowa $z $bledy)"; return }
    $kom = "$($z.Wynik.komunikat)".Trim()
    if (($z.Wynik.ok -eq $true) -and ($kod -eq 0)) {
      $st = 'ok'
      if ($z.Uwagi.Count -gt 0) { $st = 'uwaga' }
      Zakoncz-Zadanie $z $st $kom
      return
    }
    if ($z.Wynik.ok -eq $true) { Zakoncz-Zadanie $z 'blad' ("Skrypt napisał, że się udało, ale zakończył się kodem $kod - nie traktuję tego jako sukces. $kom").Trim(); return }
    if (-not $kom) { $kom = "Skrypt zgłosił błąd bez opisu (kod wyjścia $kod). $(Ostatnie-Slowa $z $bledy)" }
    Zakoncz-Zadanie $z 'blad' $kom
    return
  }
  if ($kod -eq 0) { Zakoncz-Zadanie $z 'ok' ''; return }
  $zle = @($z.Linie | Where-Object { $_ -match '^\s*(BLAD|BŁĄD|\[błąd\])' } | Select-Object -Last 3)
  if ($zle.Count -eq 0) { $zle = @($z.Linie | Where-Object { $_.Trim() } | Select-Object -Last 3) }
  Zakoncz-Zadanie $z 'blad' ("Skrypt zakończył się błędem (kod wyjścia $kod). " + (($zle | ForEach-Object { $_.Trim() }) -join ' ')).Trim()
}

function Zakoncz-Zadanie($z, [string]$stan, [string]$komunikat) {
  $script:Aktywne.Remove($z)
  $z.Koniec = Get-Date
  $z.Stan = $stan
  $z.Komunikat = $komunikat
  if ((($stan -eq 'ok') -or ($stan -eq 'uwaga')) -and $z.PoSukcesie) {
    try { & $z.PoSukcesie $z }
    catch {
      $z.Stan = 'blad'
      $z.Komunikat = "Ten krok się udał, ale nie zapisałem tego w zapisie instalacji: $($_.Exception.Message)"
      Zanotuj-Wywrotke "po kroku $($z.Id)" $_
    }
  }
  Zapisz-Dziennik "KONIEC $($z.Id): $($z.Stan) $($z.Komunikat)"
  if ($z.PoKoncu) {
    try { & $z.PoKoncu $z } catch { Zanotuj-Wywrotke "po zakonczeniu kroku $($z.Id)" $_ }
  }
}

# Przerwanie: caly drzewko procesow (skrypt moze wolac uv, gita, winget) - taskkill /T.
function Przerwij-Zadanie($z) {
  if ($z.Proces) {
    try {
      if (-not $z.Proces.HasExited) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = Join-Path $env:SystemRoot 'System32\taskkill.exe'
        $psi.Arguments = "/PID $($z.Proces.Id) /T /F"
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = $script:KodowanieOem
        $psi.StandardErrorEncoding = $script:KodowanieOem
        $tk = [System.Diagnostics.Process]::Start($psi)
        $odp = $tk.StandardOutput.ReadToEnd() + $tk.StandardError.ReadToEnd()
        [void]$tk.WaitForExit(15000)
        Zapisz-Dziennik "przerwanie kroku $($z.Id): $($odp.Trim())"
      }
    } catch { Zanotuj-Wywrotke "przerwanie kroku $($z.Id)" $_ }
    try { Czytaj-Przyrost $z; Domknij-Bufor $z } catch { Zapisz-Dziennik "po przerwaniu nie doczytalem wyjscia $($z.Id): $($_.Exception.Message)" }
  }
  Sprzatnij-Proces $z
  Zakoncz-Zadanie $z 'przerwany' 'Przerwane na Twoją prośbę.'
}

function Tyknij-Zadania {
  $script:Tyk++
  foreach ($z in @($script:Aktywne)) {
    try {
      if ($z.Wewnetrzne) {
        $w = & $z.Wewnetrzne $z
        if ($w -and $w.Stan -and ($w.Stan -ne 'trwa')) { Zakoncz-Zadanie $z "$($w.Stan)" "$($w.Komunikat)" }
        continue
      }
      if (-not $z.Proces) { continue }
      Czytaj-Przyrost $z
      if ($z.Proces.HasExited) {
        Czytaj-Przyrost $z
        Domknij-Bufor $z
        Rozstrzygnij $z
      }
    } catch {
      Zanotuj-Wywrotke "krok $($z.Id)" $_
      if ($script:Aktywne.Contains($z)) {
        Sprzatnij-Proces $z
        Zakoncz-Zadanie $z 'blad' "Okno instalatora potknęło się przy tym kroku: $($_.Exception.Message)"
      }
    }
  }
  if ($script:PoTyknieciu) {
    try { & $script:PoTyknieciu } catch { Zanotuj-Wywrotke "odmalowanie postepu" $_ }
  }
  if ($script:Aktywne.Count -eq 0) { $script:ZegarZadan.Stop() }
}

# --- plan --------------------------------------------------------------------

function Gotowy-Stan([string]$s) { return (@('ok', 'uwaga', 'pominiety') -contains $s) }

function Zacznij-Plan($plan) {
  $script:Plan = $plan
  $script:PlanIndeks = 0
  $script:PlanStan = 'trwa'
  foreach ($z in $plan) { $z.PoKoncu = { param($z) Po-Kroku-Planu $z } }
  Zapisz-Dziennik "PLAN: $((@($plan | ForEach-Object { $_.Id })) -join ', ')"
  Nastepny-Krok-Planu
}

function Nastepny-Krok-Planu {
  while ($script:PlanIndeks -lt $script:Plan.Count) {
    $z = $script:Plan[$script:PlanIndeks]
    if (Gotowy-Stan $z.Stan) { $script:PlanIndeks++; continue }
    Uruchom-Zadanie $z
    return
  }
  $script:PlanStan = 'gotowe'
  Zapisz-Dziennik "PLAN: gotowe"
  if ($script:PoPlanie) { & $script:PoPlanie }
}

function Po-Kroku-Planu($z) {
  if ($script:PlanStan -ne 'trwa') { return }
  if (Gotowy-Stan $z.Stan) { $script:PlanIndeks++; Nastepny-Krok-Planu; return }
  $script:PlanStan = 'blad'
  if ($z.Stan -eq 'przerwany') { $script:PlanStan = 'przerwany' }
  Zapisz-Dziennik "PLAN: zatrzymany na $($z.Id) ($($z.Stan))"
  if ($script:PoBledziePlanu) { & $script:PoBledziePlanu $z }
}

function Ponow-Plan {
  if (@('blad', 'przerwany') -notcontains $script:PlanStan) { return }
  $script:PlanStan = 'trwa'
  Nastepny-Krok-Planu
}

function Przerwij-Plan {
  if ($script:PlanStan -ne 'trwa') { return }
  foreach ($z in @($script:Aktywne)) { if ($script:Plan.Contains($z)) { Przerwij-Zadanie $z } }
}

# Postep: zrobione kroki w calosci, trwajacy - po kawalku z kazda linia KROK (najwyzej 90%:
# krok nie jest skonczony, dopoki nie odda wyniku).
function Postep-Planu {
  if (-not $script:Plan -or $script:Plan.Count -eq 0) { return 0.0 }
  $s = 0.0
  foreach ($z in $script:Plan) {
    if (Gotowy-Stan $z.Stan) { $s += 1.0 }
    elseif ($z.Stan -eq 'trwa') { $s += [math]::Min(0.9, 0.1 + 0.8 * (1.0 - [math]::Pow(0.7, $z.Kroki.Count))) }
  }
  return ($s / $script:Plan.Count)
}

# Znacznik dla okno.ps1: ten plik wczytal sie do konca.
$script:ModulyInstalatora["wykonanie"] = $true
