# Sprawdzenie pytania o Wiedze firmy na starej instalacji (Z3, 2026-10-14): okienko
# zasobnik\nadzorca\pytanie-wiedza-firmy.ps1 i jego wywolanie z dozoru nadzorcy, trzeci stan modulu
# w zasobnik\nadzorca\stan-instalacja.ps1 i alarm Wiedzy firmy (stan-alarmy.ps1 Alarm-Wiedzy-Firmy).
#   powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File zasobnik\test-wiedza-firmy-okno.ps1 [-Zrodlo <repo>] [-Zrzuty <kat>] [-Zostaw]
#
# NIEWIDOCZNY: okienko chodzi z -PozaEkranem (w -5000,0, bez paska zadan, bez aktywacji, wlasny zamek),
# klika je scenariusz wczytany w jego procesie; modul instalacji to atrapa (-SkryptModulu), katalog domowy
# sztuczny, BEZ zadnej konfiguracji adresow (klient zna domyslne; zmienne MR_WIEDZA_FIRMY_* zdjete z procesow
# testu - z nimi tylko jedna proba nadpisania). Dozor nadzorcy
# chodzi w osobnym procesie bez okna na kopii kodu zasobnik\ i atrapie okienka (Odpal-W-Tle: conhost
# --headless) - jak zasobnik\test-terminy-start.ps1. Zadnego zadania Harmonogramu, zadnej zmiany w ~.
# Decyzja "czy pytac" czyta prawdziwy start Windows: tuz po wlaczeniu komputera (< 5 min) okienko nie
# wstanie i proby W padna - wtedy uruchom test pozniej.
#
# Proby:
#   W1 okienko: tytul, przyciski, rozciaganie (ramka Sizable, MaximizeBox, MinimumSize), "Nie teraz"
#   W2 drugi raz tego samego dnia = bez okna (proba negatywna); jutro znowu pyta
#   W3 "Dodaj" z atrapa udana -> "Gotowe", odpowiedz dodaj, modul wolany z -Akcja Instaluj
#   W4 "Dodaj" z atrapa pada -> powod bledu na oknie, "zapytam znowu jutro", jutro znowu pyta (negatywna)
#   W5 krzyzyk bez odpowiedzi = jak "Nie teraz" (zamkniete)
#   W6 rejestr z decyzja (wiedzafirmy=false) = bez okna (negatywna); bez zadnej konfiguracji okno JEST
#   D1-D8 nadzorca: trzeci stan w Stan-Instalacji, dozor odpala okienko, nie odpala drugi raz ani po
#         decyzji, alarm przy bledzie trwalym klienta, bez alarmu przy jednym bledzie sieci, nieczytelny rejestr
# Sabotaze (kazdy MUSI zostac zlapany): S1 dozor nie wola Dozor-Wiedza-Firmy, S2 Stan-Instalacji bez trzeciego
#   stanu, S3 okienko nie zapisuje "pokazane" (pytaloby w kolko), S4 alarm bez ocen znacznikow.
param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [string]$Zrzuty = '',
  [switch]$Zostaw
)
$ErrorActionPreference = "Stop"
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("test-wf-okno-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
if (-not $Zrzuty) { $Zrzuty = Join-Path $tmp "zrzuty" }
New-Item -ItemType Directory -Force -Path $Zrzuty | Out-Null
$UTF8 = New-Object System.Text.UTF8Encoding($false)
$UTF8BOM = New-Object System.Text.UTF8Encoding($true)
$Okienko = Join-Path $Zrodlo "zasobnik\nadzorca\pytanie-wiedza-firmy.ps1"
$Adresy = @{ MR_WIEDZA_FIRMY_SERWER = "https://wiedza.test.invalid"; MR_WIEDZA_FIRMY_JFTOOLS = "https://jftools.test.invalid" }
$LIMIT_OKNA_S = 60

$script:wyniki = @()
function Wynik($nazwa, $ok, $opis) {
  $script:wyniki += [pscustomobject]@{ Test = $nazwa; OK = [bool]$ok; Opis = $opis }
  $z = "NIE"; if ($ok) { $z = "TAK" }
  Write-Host ("[{0}] {1} - {2}" -f $z, $nazwa, $opis)
}

function Procesy-Testu {
  return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($tmp) -and $_.ProcessId -ne $PID })
}
function Czekaj-Na-Procesy {
  $do = (Get-Date).AddSeconds(30)
  while (((Get-Date) -lt $do) -and (@(Procesy-Testu).Count -gt 0)) { Start-Sleep -Milliseconds 300 }
  foreach ($p in @(Procesy-Testu)) {
    try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; Write-Host "ubity zalegly proces $($p.ProcessId): $($p.CommandLine)" }
    catch { Write-Host "nie ubilem procesu $($p.ProcessId): $($_.Exception.Message)" }
  }
}

function Nowy-Dom([string]$nazwa, [string]$rejestr) {
  $d = Join-Path $tmp "dom-$nazwa"
  New-Item -ItemType Directory -Force -Path (Join-Path $d ".claude\mr"), (Join-Path $d "AppData\Local"), (Join-Path $d "AppData\Roaming") | Out-Null
  if ($rejestr) { [System.IO.File]::WriteAllText((Join-Path $d ".claude\mr\instalacja.json"), $rejestr, $UTF8) }
  return $d
}
$RejestrStary = '{"wersja":1,"moduly":{"wiedza":true,"lore":true,"kierownik":true,"skille":true,"kopia":false},"kopia":null,"narzedzia":null,"data":"2026-10-01 10:00:00"}'

function Klucze-Pytania([string]$dom) {
  $p = Join-Path $dom ".claude\mr\wiedza-firmy-pytanie.txt"
  $k = @{}
  if (Test-Path -LiteralPath $p) { foreach ($l in [System.IO.File]::ReadAllLines($p)) { if ($l -match '^([a-z_]+):\s*(.*)$') { $k[$Matches[1]] = $Matches[2] } } }
  return $k
}
function Dziennik-Okienka([string]$dom) {
  $p = Join-Path $dom ".claude\mr\wiedza-firmy-pytanie.log"
  if (Test-Path -LiteralPath $p) { return [System.IO.File]::ReadAllText($p) }
  return ""
}

# Decyzja "czy pytac" z umowy (narzedzia\instalacja\stan-wiedzy-firmy.ps1), z podanym czasem i startem Windows.
function Czy-Pytac-Test([string]$dom, [datetime]$teraz) {
  . (Join-Path $Zrodlo "narzedzia\instalacja\stan-wiedzy-firmy.ps1")
  return (Czy-Pytac-O-Wiedze-Firmy $dom $teraz $teraz.AddHours(-2))
}

# --- atrapy modulu instalacji (dla przycisku "Dodaj")
function Atrapa-Modulu([string]$nazwa, [bool]$pada) {
  $kat = Join-Path $tmp "atrapa-$nazwa"
  New-Item -ItemType Directory -Force -Path $kat | Out-Null
  $wynik = if ($pada) { '{"modul":"wiedzafirmy","akcja":"Instaluj","ok":false,"komunikat":"nie znam adresu serwera Wiedzy firmy (atrapa)"}' } else { '{"modul":"wiedzafirmy","akcja":"Instaluj","ok":true,"komunikat":"Wiedza firmy zainstalowana (atrapa)"}' }
  $kod = if ($pada) { 1 } else { 0 }
  [System.IO.File]::WriteAllText((Join-Path $kat "modul-wiedzafirmy.ps1"), @"
param([string]`$Akcja = '', [string]`$KatalogDomowy = '', [string]`$Zrodlo = '', [switch]`$Proba, [switch]`$UsunDane)
Add-Content -LiteralPath (Join-Path `$PSScriptRoot 'wywolania.log') -Value "`$Akcja|`$KatalogDomowy|`$Zrodlo"
Start-Sleep -Milliseconds 700
[Console]::Out.WriteLine('KROK: zapisuje konfiguracje (atrapa)')
[Console]::Out.WriteLine('WYNIK: $wynik')
exit $kod
"@, $UTF8BOM)
  return $kat
}

# --- scenariusz okienka (wczytany kropka w jego procesie, po zbudowaniu okna; klika zegarem)
$wstep = @'
$script:TRaport = '__RAPORT__'
$script:TZrzuty = '__ZRZUTY__'
$script:TIndeks = 0
$script:TOd = $null
function TP([string]$t) { [System.IO.File]::AppendAllText($script:TRaport, ($t + "`r`n"), (New-Object System.Text.UTF8Encoding($false))) }
function Tak([bool]$w, [string]$opis) { if ($w) { return "TAK $opis" } return "NIE $opis" }
function TZrzut([string]$n) {
  [System.Windows.Forms.Application]::DoEvents()
  $b = $script:Okno.Bounds
  $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
  try { $script:Okno.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $b.Width, $b.Height))); $bmp.Save((Join-Path $script:TZrzuty "wf-okno-$n.png"), [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bmp.Dispose() }
}
TP 'START'
$script:TZegar = New-Object System.Windows.Forms.Timer
$script:TZegar.Interval = 250
$script:TZegar.Add_Tick({
  if ($script:TWTrakcie) { return }
  $script:TWTrakcie = $true
  try {
    if ($script:TIndeks -ge $script:TKroki.Count) { $script:TZegar.Stop(); TP 'KONIEC'; if (-not $script:Okno.IsDisposed) { $script:Okno.Close() }; return }
    $k = $script:TKroki[$script:TIndeks]
    if (-not $script:TOd) { $script:TOd = Get-Date }
    if ($k.Czekaj -and -not (& $k.Czekaj)) {
      if (((Get-Date) - $script:TOd).TotalSeconds -gt 30) { TP "TIMEOUT $($k.N)"; $script:TZegar.Stop(); $script:Okno.Close() }
      return
    }
    if ($k.Zrob) { & $k.Zrob; [System.Windows.Forms.Application]::DoEvents() }
    if ($script:Okno.IsDisposed) { return }
    if ($k.Sprawdz) { TP ("SPRAWDZ $($k.N): " + (& $k.Sprawdz)) }
    if ($k.Zrzut) { TZrzut $k.Zrzut }
    $script:TIndeks++; $script:TOd = $null
  } catch { TP "WYJATEK $($_.Exception.Message)"; $script:TZegar.Stop(); try { $script:Okno.Close() } catch { TP "zamkniecie: $($_.Exception.Message)" } }
  finally { $script:TWTrakcie = $false }
})
$script:TZegar.Start()
'@

function Uruchom-Okienko([string]$nazwa, [string]$skrypt, [string]$dom, [string]$kroki, [string]$modul = "", [bool]$zAdresami = $false) {
  $raport = Join-Path $tmp "raport-$nazwa.txt"
  $sc = Join-Path $tmp "scenariusz-$nazwa.ps1"
  [System.IO.File]::WriteAllText($sc, ($wstep.Replace('__RAPORT__', $raport).Replace('__ZRZUTY__', $Zrzuty) + "`r`n" + $kroki), $UTF8BOM)
  if (-not $modul) { $modul = Join-Path (Atrapa-Modulu "nieuzywana" $false) "modul-wiedzafirmy.ps1" }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$skrypt`" -Zrodlo `"$Zrodlo`" -KatalogDomowy `"$dom`" -PozaEkranem -Scenariusz `"$sc`" -SkryptModulu `"$modul`""
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  foreach ($k in $Adresy.Keys) { if ($zAdresami) { $psi.EnvironmentVariables[$k] = $Adresy[$k] } elseif ($psi.EnvironmentVariables.ContainsKey($k)) { $psi.EnvironmentVariables.Remove($k) } }
  $t0 = Get-Date
  $pr = [System.Diagnostics.Process]::Start($psi)
  $wy = $pr.StandardOutput.ReadToEndAsync(); $bl = $pr.StandardError.ReadToEndAsync()
  $kod = "LIMIT"
  if ($pr.WaitForExit($LIMIT_OKNA_S * 1000)) { $kod = $pr.ExitCode } else { try { $pr.Kill() } catch { Write-Host "nie ubilem okienka ${nazwa}: $($_.Exception.Message)" } }
  $r = [pscustomobject]@{ Kod = $kod; Sekund = [int]((Get-Date) - $t0).TotalSeconds; Raport = @(); Bledy = ("$($bl.Result)").Trim() }
  if (Test-Path -LiteralPath $raport) { $r.Raport = @([System.IO.File]::ReadAllLines($raport)) }
  return $r
}
function Ocen-Okienko([string]$nazwa, $r) {
  $zle = @($r.Raport | Where-Object { $_ -match '^(TIMEOUT|WYJATEK)' })
  Wynik "$nazwa - przebieg" (($r.Kod -eq 0) -and ($r.Raport -contains 'KONIEC') -and ($zle.Count -eq 0)) "kod $($r.Kod), $($r.Sekund) s; $($zle -join ' | ') $($r.Bledy)"
  foreach ($s in @($r.Raport | Where-Object { $_ -like 'SPRAWDZ *' })) {
    Wynik "$nazwa - $(($s -replace '^SPRAWDZ ', '') -replace ': (TAK|NIE) .*$', '')" ($s -match ': TAK ') ($s -replace '^.*?: (TAK|NIE) ', '')
  }
}

$KrokiNieTeraz = @'
$script:TKroki = @(
  @{ N = 'okienko stoi'; Czekaj = { $script:Okno.Visible }; Zrzut = '1-pytanie'; Sprawdz = { Tak (($script:LTytul.Text -eq 'Dodać Wiedzę firmy?') -and ($script:BDodaj.Text -eq 'Dodaj') -and ($script:BNieTeraz.Text -eq 'Nie teraz') -and ($script:LTresc.Text -like '*trafiają do wspólnej bazy firmy*') -and ($script:Okno.FormBorderStyle -eq [System.Windows.Forms.FormBorderStyle]::Sizable) -and $script:Okno.MaximizeBox -and ($script:Okno.MinimumSize -eq $script:Okno.Size) -and ($script:StanOkna -eq 'pytanie')) "tytul '$($script:LTytul.Text)', ramka $($script:Okno.FormBorderStyle), minimum $($script:Okno.MinimumSize)" } },
  @{ N = 'szerzej'; Zrob = { $script:TSzer = $script:LTresc.Width; $script:TPrawa = $script:BDodaj.Right; $script:Okno.Size = New-Object System.Drawing.Size(($script:Okno.Width + 300), ($script:Okno.Height + 150)) } },
  @{ N = 'tresc rosnie z oknem, przyciski przy prawej krawedzi'; Czekaj = { $script:LTresc.Width -gt $script:TSzer }; Zrzut = '2-szeroko'; Sprawdz = { Tak (($script:LTresc.Width -gt $script:TSzer) -and ($script:BDodaj.Right -gt $script:TPrawa) -and ($script:BDodaj.Parent.Right -le $script:Okno.ClientSize.Width)) "tresc $($script:TSzer) -> $($script:LTresc.Width) px, Dodaj $($script:TPrawa) -> $($script:BDodaj.Right)" } },
  @{ N = 'nie mniej niz minimum'; Zrob = { $script:Okno.Size = New-Object System.Drawing.Size(200, 100) }; Sprawdz = { Tak (($script:Okno.Width -ge $script:Okno.MinimumSize.Width) -and ($script:Okno.Height -ge $script:Okno.MinimumSize.Height)) "okno $($script:Okno.Size)" } },
  @{ N = 'Nie teraz'; Zrob = { TP 'KONIEC'; $script:BNieTeraz.PerformClick() } }
)
'@
$KrokiZamknij = @'
$script:TKroki = @(
  @{ N = 'okienko stoi (nie powinno)'; Czekaj = { $script:Okno.Visible }; Zrob = { TP 'KONIEC'; $script:Okno.Close() } }
)
'@

# ------------------------------------------------------------------ przebieg dozoru (osobny proces)
$przebieg = @'
param([string]$Kod, [string]$ZrodloAtrapa, [string]$Dom, [string]$LogOkna)
$ErrorActionPreference = "Stop"
function P([string]$id, $ok, [string]$opis) { $z = "NIE"; if ($ok) { $z = "TAK" }; Write-Output ("WYNIK|{0}|{1}|{2}" -f $z, $id, (($opis -replace '[\r\n|]+', ' ').Trim())) }
function Dziennik { $p = Join-Path $Dom ".claude\.megaruchacz-zasobnik.log"; if (Test-Path -LiteralPath $p) { return [System.IO.File]::ReadAllText($p) }; return "" }
function Rejestr([string]$json) { [System.IO.File]::WriteAllText((Join-Path $Dom ".claude\mr\instalacja.json"), $json, (New-Object System.Text.UTF8Encoding($false))) }
function Wolan { if (Test-Path -LiteralPath $LogOkna) { return @([System.IO.File]::ReadAllLines($LogOkna)).Count }; return 0 }
try {
  Add-Type -AssemblyName System.Windows.Forms
  $script:ModulyOkna = @{}
  . (Join-Path $Kod "zasobnik\stan-nadzorcy.ps1")
  Ustaw-Nadzorce $ZrodloAtrapa $Dom $false
  . (Join-Path $Kod "zasobnik\nadzorca\dozor.ps1")
  # reszta decyzji dozoru jako atrapy - tu liczy sie tylko Wiedza firmy
  function Czy-Ruszac-Cykl($i) { return [pscustomobject]@{ Ruszac = $false; Powod = "atrapa testu" } }
  function Czy-Sprawdzac-Skille($i) { return [pscustomobject]@{ Ruszac = $false; Powod = "atrapa testu" } }
  function Dozor-Terminy($w) { }
  $stary = '{"wersja":1,"moduly":{"wiedza":true,"lore":true,"kierownik":true,"skille":true,"kopia":false},"kopia":null,"narzedzia":null}'

  Rejestr $stary
  $inst = Stan-Instalacji
  P "D1" (($inst.Moduly.wiedzafirmy -eq $false) -and (-not (Modul-Jest $inst "wiedzafirmy")) -and (Modul-Jest $inst "kierownik") -and ((Nazwy-Modulow $inst $false) -contains "Wiedza firmy")) "stara instalacja: wiedzafirmy=$($inst.Moduly.wiedzafirmy), niezainstalowane: $((Nazwy-Modulow $inst $false) -join ', ')"

  $d0 = (Dziennik).Length
  Dozor-Po-Danych ([pscustomobject]@{ Instalacja = $inst; Alarmy = @() }) { param($a, $b) }
  $do = [datetime]::Now.AddSeconds(20)
  while (([datetime]::Now -lt $do) -and ((Wolan) -lt 1)) { Start-Sleep -Milliseconds 200 }
  $wol = ""; if (Test-Path -LiteralPath $LogOkna) { $wol = [System.IO.File]::ReadAllText($LogOkna) }
  $dz = (Dziennik).Substring($d0)
  P "D2" (((Wolan) -eq 1) -and ($wol -match [regex]::Escape("-KatalogDomowy $Dom")) -and ($dz -match "pytam o Wiedze firmy") -and ($dz -match "wystartowalo okienko pytania o Wiedze firmy")) "dozor odpalil okienko: $($wol.Trim()); dziennik: $dz"

  [System.IO.File]::WriteAllText((Join-Path $Dom ".claude\mr\wiedza-firmy-pytanie.txt"), "pokazane: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`r`nodpowiedz: nie-teraz`r`n", (New-Object System.Text.UTF8Encoding($false)))
  $d0 = (Dziennik).Length
  Dozor-Po-Danych ([pscustomobject]@{ Instalacja = $inst; Alarmy = @() }) { param($a, $b) }
  Start-Sleep -Milliseconds 1500
  $dz = (Dziennik).Substring($d0)
  P "D3" (((Wolan) -eq 1) -and ($dz -match "nie pytam - dzis juz pytalem")) "drugi dozor tego samego dnia: wolan okienka $(Wolan); dziennik: $dz"

  Rejestr ($stary.Replace('"kopia":false}', '"kopia":false,"wiedzafirmy":true}'))
  $inst = Stan-Instalacji
  $d0 = (Dziennik).Length
  Dozor-Po-Danych ([pscustomobject]@{ Instalacja = $inst; Alarmy = @() }) { param($a, $b) }
  Start-Sleep -Milliseconds 1500
  $dz = (Dziennik).Substring($d0)
  P "D4" (($inst.Moduly.wiedzafirmy -eq $true) -and ((Wolan) -eq 1) -and ($dz -match "juz zdecydowano")) "po decyzji: wiedzafirmy=$($inst.Moduly.wiedzafirmy), wolan okienka $(Wolan); dziennik: $dz"

  $zn = Join-Path $Dom ".claude\mr\wiedza-firmy\znaczniki"
  New-Item -ItemType Directory -Force -Path $zn | Out-Null
  # jeden blad sieci po sukcesie godzine temu - bez alarmu (falszywy alarm gorszy niz brak)
  [System.IO.File]::WriteAllText((Join-Path $zn "wysylka.txt"), "$((Get-Date).ToString('s'))|blad|brak sieci - ponowie (atrapa)`n", (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText((Join-Path $Dom ".claude\mr\wiedza-firmy\klient.log"), "$((Get-Date).AddHours(-1).ToString('s')) [wysylka] ok: wyslano`n$((Get-Date).ToString('s')) [wysylka] BLAD: brak sieci - ponowie (atrapa)`n", (New-Object System.Text.UTF8Encoding($false)))
  $a0 = Alarm-Wiedzy-Firmy
  $wszystkie = Zbierz-Alarmy $null ([pscustomobject]@{ Kod = 0; Linia = "test"; Powod = "" }) $inst
  P "D5b" ((-not $a0) -and (@($wszystkie | Where-Object { $_.Temat -eq "wiedzafirmy" }).Count -eq 0)) "jeden blad sieci - bez alarmu: $(if ($a0) { $a0.Tresc } else { 'brak' })"
  # blad trwaly (komputer zablokowany, 403) - alarm od razu
  [System.IO.File]::WriteAllText((Join-Path $zn "wysylka.txt"), "$((Get-Date).ToString('s'))|blad|serwer odmowil (zablokowany albo nieznany komputer): 403 (atrapa)`n", (New-Object System.Text.UTF8Encoding($false)))
  $a = Alarm-Wiedzy-Firmy
  $wszystkie = Zbierz-Alarmy $null ([pscustomobject]@{ Kod = 0; Linia = "test"; Powod = "" }) $inst
  P "D5" ($a -and ($a.Temat -eq "wiedzafirmy") -and ($a.Tresc -match "krok 'wysylka' ma blad trwaly.*atrapa") -and (@($wszystkie | Where-Object { $_.Temat -eq "wiedzafirmy" }).Count -eq 1)) "alarm: $(if ($a) { $a.Tytul + ' :: ' + $a.Tresc }); w Zbierz-Alarmy: $(@($wszystkie | ForEach-Object { $_.Temat }) -join ',')"
  Rejestr $stary
  $inst = Stan-Instalacji
  $wszystkie = Zbierz-Alarmy $null ([pscustomobject]@{ Kod = 0; Linia = "test"; Powod = "" }) $inst
  P "D6" (@($wszystkie | Where-Object { $_.Temat -eq "wiedzafirmy" }).Count -eq 0) "bez modulu w rejestrze ten sam znacznik nie alarmuje: $(@($wszystkie | ForEach-Object { $_.Temat }) -join ',')"

  [System.IO.File]::WriteAllBytes((Join-Path $Dom ".claude\mr\instalacja.json"), [byte[]](0, 0, 0, 0))
  $i1 = Stan-Instalacji
  [System.IO.File]::WriteAllText((Join-Path $Dom ".claude\mr\wiedza-firmy\konfiguracja.json"), '{"wersja":1}', (New-Object System.Text.UTF8Encoding($false)))
  $i2 = Stan-Instalacji
  P "D7" ($i1.Blad -and ($i1.Moduly.wiedzafirmy -eq $false) -and ($i1.Moduly.kierownik -eq $true) -and ($i2.Moduly.wiedzafirmy -eq $true)) "nieczytelny rejestr: bez konfiguracji wiedzafirmy=$($i1.Moduly.wiedzafirmy), z konfiguracja=$($i2.Moduly.wiedzafirmy)"
  $wyw = @($script:NadzWywrotki)
  P "D8" ($wyw.Count -eq 0) "zadnej wywrotki w przebiegu: $($wyw -join ' || ')"
} catch {
  P "PRZEBIEG" $false "wywrotka przebiegu: $($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
}
'@
$plikPrzebiegu = Join-Path $tmp "przebieg.ps1"
[System.IO.File]::WriteAllText($plikPrzebiegu, $przebieg, $UTF8BOM)
$WSZYSTKIE_D = @("D1", "D2", "D3", "D4", "D5b", "D5", "D6", "D7", "D8")

function Kopia-Kodu([string]$nazwa) {
  $k = Join-Path $tmp "kod-$nazwa"
  New-Item -ItemType Directory -Force -Path (Join-Path $k "zasobnik") | Out-Null
  Copy-Item -LiteralPath (Join-Path $Zrodlo "zasobnik\stan-nadzorcy.ps1") -Destination (Join-Path $k "zasobnik")
  Copy-Item -LiteralPath (Join-Path $Zrodlo "zasobnik\nadzorca") -Destination (Join-Path $k "zasobnik") -Recurse
  return $k
}
function Sabotuj([string]$p, [string]$co, [string]$naCo) {
  $txt = [System.IO.File]::ReadAllText($p)
  $ile = ([regex]::Matches($txt, [regex]::Escape($co))).Count
  if ($ile -ne 1) { throw "sabotaz: kotwica w $p stoi $ile razy (ma raz): $co" }
  [System.IO.File]::WriteAllText($p, $txt.Replace($co, $naCo), $UTF8BOM)
}

function Przebieg-Dozoru([string]$nazwa, [string]$kod) {
  $baza = Join-Path $tmp "run-$nazwa"
  $dom = Join-Path $baza "dom"
  $zr = Join-Path $baza "zrodlo"
  New-Item -ItemType Directory -Force -Path (Join-Path $dom ".claude\mr"), (Join-Path $zr "zasobnik\nadzorca"), (Join-Path $zr "narzedzia\instalacja") | Out-Null
  foreach ($f in @("stan.ps1", "stan-wiedzy-firmy.ps1")) { Copy-Item -LiteralPath (Join-Path $Zrodlo "narzedzia\instalacja\$f") -Destination (Join-Path $zr "narzedzia\instalacja") }
  $log = Join-Path $baza "okienko-wolania.log"
  [System.IO.File]::WriteAllText((Join-Path $zr "zasobnik\nadzorca\pytanie-wiedza-firmy.ps1"), "Add-Content -LiteralPath '$log' -Value (`$args -join ' ')`r`n", $UTF8BOM)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$plikPrzebiegu`" -Kod `"$kod`" -ZrodloAtrapa `"$zr`" -Dom `"$dom`" -LogOkna `"$log`""
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  foreach ($k in $Adresy.Keys) { if ($psi.EnvironmentVariables.ContainsKey($k)) { $psi.EnvironmentVariables.Remove($k) } }   # bez zadnej konfiguracji
  $pr = [System.Diagnostics.Process]::Start($psi)
  $zadWy = $pr.StandardOutput.ReadToEndAsync(); $zadBl = $pr.StandardError.ReadToEndAsync()
  $r = @{}
  if (-not $pr.WaitForExit(120000)) { try { $pr.Kill() } catch { Write-Host "nie ubilem przebiegu ${nazwa}: $($_.Exception.Message)" }; $r["PRZEBIEG"] = [pscustomobject]@{ OK = $false; Opis = "przebieg $nazwa przekroczyl 120 s" } }
  $pr.WaitForExit()
  foreach ($l in @("$($zadWy.Result)" -split '\r?\n')) {
    if ($l -match '^WYNIK\|(TAK|NIE)\|([^|]+)\|(.*)$') { $r[$Matches[2]] = [pscustomobject]@{ OK = ($Matches[1] -eq "TAK"); Opis = $Matches[3] } }
  }
  if ("$($zadBl.Result)".Trim()) { $r["STDERR"] = [pscustomobject]@{ OK = $false; Opis = ("$($zadBl.Result)" -replace '\s+', ' ').Trim() } }
  Czekaj-Na-Procesy
  return $r
}

# W1-W2 na podanym skrypcie okienka; zwraca slownik id -> OK (do sabotazy).
function Proby-Nie-Teraz([string]$skrypt, [string]$przedrostek, [bool]$pisz) {
  $w = @{}
  $dom = Nowy-Dom "$przedrostek-nieteraz" $RejestrStary
  $r = Uruchom-Okienko "$przedrostek-W1" $skrypt $dom $KrokiNieTeraz
  $k = Klucze-Pytania $dom
  $w["W1"] = (($r.Kod -eq 0) -and ($r.Raport -contains 'KONIEC') -and ($k["odpowiedz"] -eq "nie-teraz") -and ($k["pokazane"] -like "$(Get-Date -Format 'yyyy-MM-dd') *"))
  if ($pisz) {
    Ocen-Okienko "W1 okienko i Nie teraz" $r
    Wynik "W1 Nie teraz zapisane (odpowiedz, pokazane dzis)" $w["W1"] "stan: $(($k.Keys | Sort-Object | ForEach-Object { "$_=$($k[$_])" }) -join '; ')"
  }
  $r2 = Uruchom-Okienko "$przedrostek-W2" $skrypt $dom $KrokiZamknij
  $dz = Dziennik-Okienka $dom
  $w["W2"] = (($r2.Kod -eq 0) -and ($r2.Raport.Count -eq 0) -and ($dz -match "nie pytam - dzis juz pytalem"))
  if ($pisz) {
    Wynik "W2 drugi raz tego samego dnia - bez okna (proba negatywna)" $w["W2"] "kod $($r2.Kod), $($r2.Sekund) s, raport scenariusza: $($r2.Raport -join ' | '); dziennik: $(($dz -split "`r?`n" | Select-Object -Last 3) -join ' / ')"
    $c = Czy-Pytac-Test $dom ([datetime]::Today.AddDays(1).AddHours(10))
    Wynik "W2 jutro znowu pyta" $c.Pytac $c.Powod
  }
  return $w
}

try {
  # ------------------------------------------------------------- okienko
  [void](Proby-Nie-Teraz $Okienko "ok" $true)

  $atrOk = Atrapa-Modulu "ok" $false
  $dom = Nowy-Dom "dodaj" $RejestrStary
  $r = Uruchom-Okienko "W3" $Okienko $dom @'
$script:TKroki = @(
  @{ N = 'okienko stoi'; Czekaj = { $script:Okno.Visible }; Zrob = { $script:BDodaj.PerformClick() } },
  @{ N = 'w trakcie'; Sprawdz = { Tak (($script:StanOkna -in @('trwa', 'gotowe')) -and (-not $script:BDodaj.Enabled) -and (-not $script:BNieTeraz.Enabled)) "stan $($script:StanOkna), przyciski zablokowane" } },
  @{ N = 'Dodaj - gotowe'; Czekaj = { $script:StanOkna -ne 'trwa' }; Zrzut = '3-dodane'; Sprawdz = { Tak (($script:StanOkna -eq 'gotowe') -and ($script:LTytul.Text -eq 'Wiedza firmy jest dodana') -and ($script:LStatus.Text -like 'Gotowe.*administrator*') -and $script:BZamknij.Visible) "stan $($script:StanOkna): $($script:LStatus.Text)" } },
  @{ N = 'Zamknij'; Zrob = { TP 'KONIEC'; $script:BZamknij.PerformClick() } }
)
'@ (Join-Path $atrOk "modul-wiedzafirmy.ps1")
  Ocen-Okienko "W3 Dodaj (atrapa udana)" $r
  $k = Klucze-Pytania $dom
  $wol = @(); $pl = Join-Path $atrOk "wywolania.log"; if (Test-Path $pl) { $wol = @(Get-Content $pl) }
  Wynik "W3 odpowiedz 'dodaj', modul wolany raz z -Akcja Instaluj i tym katalogiem domowym" (($k["odpowiedz"] -eq "dodaj") -and ($wol.Count -eq 1) -and ($wol[0] -eq "Instaluj|$dom|$Zrodlo")) "stan: odpowiedz=$($k['odpowiedz']); wywolania: $($wol -join ' || ')"

  $atrZle = Atrapa-Modulu "pada" $true
  $dom = Nowy-Dom "dodaj-blad" $RejestrStary
  $r = Uruchom-Okienko "W4" $Okienko $dom @'
$script:TKroki = @(
  @{ N = 'okienko stoi'; Czekaj = { $script:Okno.Visible }; Zrob = { $script:BDodaj.PerformClick() } },
  @{ N = 'Dodaj - blad z powodem'; Czekaj = { $script:StanOkna -eq 'blad' }; Zrzut = '4-blad'; Sprawdz = { Tak (($script:LTytul.Text -eq 'Nie udało się dodać Wiedzy firmy') -and ($script:LStatus.Text -like '*nie znam adresu serwera Wiedzy firmy (atrapa)*') -and ($script:LStatus.Text -like '*zapytam znowu jutro*') -and $script:BZamknij.Visible) "status: $($script:LStatus.Text)" } },
  @{ N = 'Zamknij'; Zrob = { TP 'KONIEC'; $script:BZamknij.PerformClick() } }
)
'@ (Join-Path $atrZle "modul-wiedzafirmy.ps1")
  Ocen-Okienko "W4 Dodaj z bledem (proba negatywna)" $r
  $k = Klucze-Pytania $dom
  $c = Czy-Pytac-Test $dom ([datetime]::Today.AddDays(1).AddHours(10))
  Wynik "W4 odpowiedz 'dodaj-blad' z powodem, jutro znowu pyta" (($k["odpowiedz"] -eq "dodaj-blad") -and ($k["powod"] -like "*atrapa*") -and $c.Pytac) "stan: odpowiedz=$($k['odpowiedz']), powod=$($k['powod']); jutro: $($c.Powod)"

  $dom = Nowy-Dom "krzyzyk" $RejestrStary
  $r = Uruchom-Okienko "W5" $Okienko $dom @'
$script:TKroki = @(
  @{ N = 'okienko stoi'; Czekaj = { $script:Okno.Visible }; Zrob = { TP 'KONIEC'; $script:Okno.Close() } }
)
'@
  $k = Klucze-Pytania $dom
  Wynik "W5 krzyzyk bez odpowiedzi = 'zamkniete' (jutro znowu)" (($r.Kod -eq 0) -and ($r.Raport -contains 'KONIEC') -and ($k["odpowiedz"] -eq "zamkniete")) "kod $($r.Kod); odpowiedz=$($k['odpowiedz'])"

  $dom = Nowy-Dom "zdecydowane" ($RejestrStary.Replace('"kopia":false}', '"kopia":false,"wiedzafirmy":false}'))
  $r = Uruchom-Okienko "W6" $Okienko $dom $KrokiZamknij
  $dz = Dziennik-Okienka $dom
  Wynik "W6 rejestr z decyzja (wiedzafirmy=false) - bez okna (proba negatywna)" (($r.Kod -eq 0) -and ($r.Raport.Count -eq 0) -and ($dz -match "juz zdecydowano")) "kod $($r.Kod); dziennik: $($dz.Trim())"
  $dom = Nowy-Dom "znadpisaniem" $RejestrStary
  $r = Uruchom-Okienko "W6b" $Okienko $dom $KrokiZamknij "" $true
  $dz = Dziennik-Okienka $dom
  Wynik "W6 z nadpisaniem adresow (MR_WIEDZA_FIRMY_*) okno tez wstaje - adresy nic nie zmieniaja w pytaniu" (($r.Kod -eq 0) -and ($r.Raport -contains 'KONIEC') -and ($dz -match "pytam o Wiedze firmy")) "kod $($r.Kod); dziennik: $($dz.Trim())"

  # ------------------------------------------------------------- dozor nadzorcy
  $rd = Przebieg-Dozoru "czysty" (Kopia-Kodu "czysty")
  foreach ($id in $WSZYSTKIE_D) { if ($rd.ContainsKey($id)) { Wynik $id $rd[$id].OK $rd[$id].Opis } else { Wynik $id $false "proba nie wykonala sie (przebieg urwany?)" } }
  foreach ($id in @("PRZEBIEG", "STDERR")) { if ($rd.ContainsKey($id)) { Wynik $id $false $rd[$id].Opis } }

  # ------------------------------------------------------------- sabotaze
  $s = @(
    @{ N = "S1 dozor nie wola Dozor-Wiedza-Firmy"; Plik = "zasobnik\nadzorca\dozor.ps1"; Co = "  Dozor-Wiedza-Firmy`r`n`r`n  # Alarmy"; NaCo = "  `$null = 0`r`n`r`n  # Alarmy"; Lapie = @("D2") },
    @{ N = "S2 Stan-Instalacji bez trzeciego stanu"; Plik = "zasobnik\nadzorca\stan-instalacja.ps1"; Co = '  $m["wiedzafirmy"] = $false   # trzeci stan'; NaCo = '  $null = 0   # trzeci stan'; Lapie = @("D1", "D7") },
    @{ N = "S4 alarm bez oceny znacznikow"; Plik = "zasobnik\nadzorca\stan-alarmy.ps1"; Co = 'if (@($o.Problemy).Count -eq 0) { return $null }'; NaCo = 'return $null'; Lapie = @("D5") }
  )
  $i = 0
  foreach ($x in $s) {
    $i++
    $kod = Kopia-Kodu "sabotaz$i"
    Sabotuj (Join-Path $kod $x.Plik) $x.Co $x.NaCo
    $rs = Przebieg-Dozoru "sabotaz$i" $kod
    $padly = @($x.Lapie | Where-Object { $rs.ContainsKey($_) -and (-not $rs[$_].OK) })
    Wynik "sabotaz: $($x.N)" ($padly.Count -gt 0) "padly proby: $(if ($padly) { $padly -join ', ' } else { 'ZADNA - sabotaz przeszedl niezauwazony' })"
  }
  $kopiaOkienka = Join-Path $tmp "okienko-sabotaz\zasobnik\nadzorca\pytanie-wiedza-firmy.ps1"
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $kopiaOkienka) | Out-Null
  Copy-Item -LiteralPath $Okienko -Destination $kopiaOkienka
  Sabotuj $kopiaOkienka "@{ pokazane = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); odpowiedz = ''" "@{ odpowiedz = ''"
  $ws = Proby-Nie-Teraz $kopiaOkienka "sabotaz" $false
  Wynik "sabotaz: S3 okienko nie zapisuje 'pokazane' (pytaloby w kolko)" (-not ($ws["W1"] -and $ws["W2"])) "W1=$($ws['W1']) W2=$($ws['W2'])"
} catch {
  Wynik "test bez wywrotki" $false "$($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
} finally {
  Czekaj-Na-Procesy
}
Wynik "sprzatanie: zadnego procesu z katalogu testu" (@(Procesy-Testu).Count -eq 0) ((@(Procesy-Testu) | ForEach-Object { "$($_.ProcessId) $($_.CommandLine)" }) -join ' || ')

$zle = @($script:wyniki | Where-Object { -not $_.OK })
if (-not $Zostaw -and $zle.Count -eq 0) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Host "katalog testu zostaje: $tmp" }
Write-Host ""
Write-Host "Wynik: $(@($script:wyniki).Count - $zle.Count) z $(@($script:wyniki).Count) OK"
if ($zle.Count -gt 0) { exit 1 }
exit 0
