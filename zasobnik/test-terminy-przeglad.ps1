# Sprawdzenie wynikow przypomnien wykonanych w tle na Przegladzie (2026-10-08): "nic" - spokojna
# zielona linia w karcie Stan bez sprawy ("Wszystko gra" zostaje), "czlowiek" - zolta sprawa,
# "blad" - czerwona sprawa, nieczytelny plik - sprawa z nazwa pliku, wynik starszy niz doba
# i brak katalogu - nic. "Pokaż wynik" wskazuje <id>.md (Notatnik podmieniony - nic sie nie
# otwiera). Sabotaze na kopii stan-terminy.ps1: "blad" jako spokojna linia, nieczytelny plik
# polkniety po cichu - wlasciwa proba musi wtedy paść.
#   powershell -ExecutionPolicy Bypass -File zasobnik\test-terminy-przeglad.ps1 [-Zasobnik <kat zasobnik>] [-Zrodlo <repo>] [-Zrzuty <kat>] [-BezOkna]
# Wszystko na sztucznym katalogu domowym (atrapy ~\.claude\mr\przypomnienia-wyniki\<id>.json
# i <id>.md) - prawdziwego domu ani dzialajacego nadzorcy test nie dotyka.
# Czesc z oknem: formularz z karta Stan i sprawami, poza ekranem (-5000, 0), bez paska zadan,
# bez aktywacji (nie zabiera klawiatury), bez ikony i bez dozoru; zrzuty przez DrawToBitmap.
param(
  [string]$Zasobnik = $PSScriptRoot,
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [string]$Zrzuty = "",
  [switch]$BezOkna
)
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { Write-Warning "konsola bez UTF-8: $($_.Exception.Message)" }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("test-terminy-przeglad-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
if (-not $Zrzuty) { $Zrzuty = Join-Path $tmp "zrzuty" }
New-Item -ItemType Directory -Force -Path $Zrzuty | Out-Null
$dom = Join-Path $tmp "dom"
New-Item -ItemType Directory -Force -Path (Join-Path $dom ".claude\mr") | Out-Null
$katWynikow = Join-Path $dom ".claude\mr\przypomnienia-wyniki"

$script:wyniki = @()
function Wynik($nazwa, $ok, $opis) {
  $script:wyniki += [pscustomobject]@{ Test = $nazwa; OK = [bool]$ok; Opis = $opis }
  $z = "NIE"; if ($ok) { $z = "TAK" }
  Write-Host ("[{0}] {1} - {2}" -f $z, $nazwa, $opis)
}
function Iso($d) { return $d.ToString("yyyy-MM-ddTHH:mm:ss") }
# Jak narzedzia\terminy.js (new Date().toISOString()) - czas UTC z "Z" na koncu.
function IsoUtc($d) { return $d.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }
$UTF8 = New-Object System.Text.UTF8Encoding($false)

# Atrapa pliku wyniku - pola z umowy z mechanika wykonywania w tle; $md = $true kladzie obok <id>.md.
function Atrapa([int]$id, [hashtable]$pola, [bool]$md = $true) {
  New-Item -ItemType Directory -Force -Path $katWynikow | Out-Null
  $kon = (Get-Date).AddMinutes(-2)
  $o = [ordered]@{ id = $id; tresc = "Sprawdzić, czy nocne przeliczenie planera FBA poszło bez błędów i czy są nowe pozycje na żółto"
                   projekt = "Planer FBA"; start = (IsoUtc $kon.AddMinutes(-3)); koniec = (IsoUtc $kon); wynik = "nic"
                   co_zrobic = ""; powod = ""; raport = "Wszystko przeliczone, 0 bledow."; session_id = "abc-$id"; projekt_katalog = "C:\dev\planer" }
  foreach ($k in $pola.Keys) { $o[$k] = $pola[$k] }
  [System.IO.File]::WriteAllText((Join-Path $katWynikow "$id.json"), ($o | ConvertTo-Json), $UTF8)
  $pm = Join-Path $katWynikow "$id.md"
  if ($md) { [System.IO.File]::WriteAllText($pm, "# Wynik przypomnienia #$id`r`n", $UTF8) }
  elseif (Test-Path -LiteralPath $pm) { Remove-Item -LiteralPath $pm -Force }
}
function Wyczysc { if (Test-Path -LiteralPath $katWynikow) { Remove-Item -LiteralPath $katWynikow -Recurse -Force } }
function Postarz([string]$nazwa, $kiedy) { [System.IO.File]::SetLastWriteTime((Join-Path $katWynikow $nazwa), $kiedy) }

# ---------------------------------------------------------------- wczytanie modulow
. (Join-Path $Zasobnik "stan-nadzorcy.ps1")
Ustaw-Nadzorce $Zrodlo $dom $true
$script:ModulyOkna = @{}
. (Join-Path $Zasobnik "nadzorca\przeglad-tresc.ps1")

$inst = [pscustomobject]@{ Moduly = [pscustomobject]@{ wiedza = $false; lore = $false; skille = $false; kopia = $false; kierownik = $true } }
$k = [ordered]@{ narzedzia = "1"; "narz.1.klucz" = "claude"; "narz.1.nazwa" = "Claude Code"; "narz.1.uzywane" = "1"; "narz.1.zuzycie_w_oknie" = "1" }
$D = [pscustomobject]@{ Rachunek = [pscustomobject]@{ Klucze = $k; Linia = "x" }; Cykl = $null; Alarmy = @(); Informacje = @()
  Instalacja = $inst; Przeliczanie = $null; Kopia = $null; Pamiec = $null
  Wersja = [pscustomobject]@{ Lokalna = "0.29.1"; Nowsza = 0; Nasze = 0; Pobrano = (Get-Date); Powod = "" } }

function O { return (Ocena-Wynikow-Przypomnien (Wyniki-Przypomnien) (Get-Date)) }
$ZNAKOK = [string][char]0x2713
$WIELOKROPEK = [string][char]0x2026

# ---------------------------------------------------------------- A. tresc (bez okna)
# Kazda proba to funkcja - dwie z nich ida nizej na sabotowanej kopii stan-terminy.ps1.
function Proba-BrakKatalogu {
  Wyczysc
  $o = O
  return [pscustomobject]@{ Ok = ((@($o.Linie).Count -eq 0) -and (@($o.Problemy).Count -eq 0)); Opis = "linie=$(@($o.Linie).Count) sprawy=$(@($o.Problemy).Count)" }
}
function Proba-PustyKatalog {
  Wyczysc
  New-Item -ItemType Directory -Force -Path $katWynikow | Out-Null
  $o = O
  return [pscustomobject]@{ Ok = ((@($o.Linie).Count -eq 0) -and (@($o.Problemy).Count -eq 0)); Opis = "linie=$(@($o.Linie).Count) sprawy=$(@($o.Problemy).Count)" }
}
function Proba-Nic {
  Wyczysc
  Atrapa 7 @{}
  $o = O
  $kon = Data-Lub-Nic ((Get-Content -LiteralPath (Join-Path $katWynikow "7.json") -Raw -Encoding UTF8 | ConvertFrom-Json).koniec)
  $x = @($o.Linie)[0]
  $pocz = "Przypomnienie #7 zrobione samo - nic nie musisz robić ($(Kiedy-Krotko $kon)). Planer FBA: Sprawdzić, czy nocne"
  $ok = (@($o.Linie).Count -eq 1) -and (@($o.Problemy).Count -eq 0) -and $x.Tekst.StartsWith($pocz) -and $x.Tekst.EndsWith($WIELOKROPEK) -and
        ($x.Tekst -notmatch "[\s,.;:-]$WIELOKROPEK$") -and ($x.Podpowiedz -match 'czy są nowe pozycje na żółto') -and ($x.Podpowiedz -match 'Wszystko przeliczone') -and
        ($x.Plik -eq (Join-Path $katWynikow "7.md"))
  return [pscustomobject]@{ Ok = $ok; Opis = "'$($x.Tekst)' | plik=$($x.Plik) | sprawy=$(@($o.Problemy).Count)" }
}
function Proba-Czlowiek {
  Wyczysc
  Atrapa 8 @{ wynik = "czlowiek"; co_zrobic = "Kliknij w Seller Central 'Zatwierdź wysyłkę' dla FBA15K." }
  $o = O
  $p = @($o.Problemy)[0]
  $ok = (@($o.Problemy).Count -eq 1) -and (@($o.Linie).Count -eq 0) -and ($p.Waga -eq "uwaga") -and
        ($p.Tytul -eq "Przypomnienie #8 czeka na Ciebie: Kliknij w Seller Central 'Zatwierdź wysyłkę' dla FBA15K") -and
        ($p.Plik -eq (Join-Path $katWynikow "8.md")) -and ($p.Zrodlo -eq "przypomnienia")
  return [pscustomobject]@{ Ok = $ok; Opis = "[$($p.Waga)] $($p.Tytul) | $($p.Porada) | plik=$($p.Plik)" }
}
function Proba-Blad {
  Wyczysc
  Atrapa 9 @{ wynik = "blad"; powod = "Claude Code nie wystartował: brak pliku claude.exe." }
  $o = O
  $p = @($o.Problemy)[0]
  $ok = (@($o.Problemy).Count -eq 1) -and (@($o.Linie).Count -eq 0) -and ($p.Waga -eq "pilne") -and
        ($p.Tytul -eq "Przypomnienie #9 nie wykonało się: Claude Code nie wystartował: brak pliku claude.exe") -and ($p.Plik -eq (Join-Path $katWynikow "9.md"))
  return [pscustomobject]@{ Ok = $ok; Opis = "[$($p.Waga)] $($p.Tytul) | linie=$(@($o.Linie).Count)" }
}
function Proba-Nieczytelny {
  Wyczysc
  New-Item -ItemType Directory -Force -Path $katWynikow | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $katWynikow "12.json"), '{"id": 12, "wynik": "czl', $UTF8)
  Postarz "12.json" (Get-Date).AddMinutes(-1)
  $o = O
  $p = @($o.Problemy)[0]
  $ok = (@($o.Problemy).Count -eq 1) -and ($p.Waga -eq "uwaga") -and ($p.Tytul -match '12\.json') -and ($p.Pelne -match 'nie da się odczytać')
  return [pscustomobject]@{ Ok = $ok; Opis = "[$($p.Waga)] $($p.Tytul) | $($p.Pelne)" }
}
function Proba-Stary {
  Wyczysc
  Atrapa 10 @{ wynik = "blad"; powod = "x"; koniec = (IsoUtc (Get-Date).AddHours(-25)); start = (IsoUtc (Get-Date).AddHours(-25)) }
  Atrapa 11 @{ wynik = "czlowiek"; co_zrobic = "y"; koniec = (IsoUtc (Get-Date).AddHours(-30)) }
  [System.IO.File]::WriteAllText((Join-Path $katWynikow "13.json"), 'smieci', $UTF8)
  Postarz "13.json" (Get-Date).AddHours(-26)
  $o = O
  return [pscustomobject]@{ Ok = ((@($o.Linie).Count -eq 0) -and (@($o.Problemy).Count -eq 0)); Opis = "linie=$(@($o.Linie).Count) sprawy=$(@($o.Problemy).Count) $(@($o.Problemy | ForEach-Object { $_.Tytul }) -join ' | ')" }
}

$PROBY = [ordered]@{
  "brak katalogu wynikow -> nic (ani linii, ani sprawy)" = "Proba-BrakKatalogu"
  "pusty katalog wynikow -> nic" = "Proba-PustyKatalog"
  "nic -> jedna linia bez sprawy, tresc skrocona na granicy slowa z wielokropkiem, pelna w podpowiedzi, plik 7.md" = "Proba-Nic"
  "czlowiek -> zolta sprawa 'Przypomnienie #8 czeka na Ciebie: ...' z plikiem 8.md" = "Proba-Czlowiek"
  "negatywna: blad -> czerwona sprawa 'nie wykonało się: <powod>', bez spokojnej linii" = "Proba-Blad"
  "negatywna: nieczytelny JSON -> sprawa z nazwa pliku" = "Proba-Nieczytelny"
  "wyniki i nieczytelny plik starsze niz 24 h -> nic" = "Proba-Stary"
}
foreach ($nazwa in $PROBY.Keys) {
  $w = $null
  try { $w = & $PROBY[$nazwa] } catch { $w = [pscustomobject]@{ Ok = $false; Opis = "WYWROTKA: $($_.Exception.Message)" } }
  Wynik $nazwa $w.Ok $w.Opis
}

# reszta przypadkow brzegowych
Wyczysc
New-Item -ItemType Directory -Force -Path $katWynikow | Out-Null
[System.IO.File]::WriteAllText((Join-Path $katWynikow "14.json"), '{"id": 14, "wyn', $UTF8)
$o = O
Wynik "nieczytelny plik zapisany przed chwila (w trakcie zapisu) -> jeszcze bez sprawy" (@($o.Problemy).Count -eq 0) "sprawy=$(@($o.Problemy).Count)"
Postarz "14.json" (Get-Date).AddSeconds(-30)
$o = O
Wynik "negatywna: ten sam nieczytelny plik po 30 s -> sprawa" ((@($o.Problemy).Count -eq 1) -and (@($o.Problemy)[0].Tytul -match '14\.json')) "$(@($o.Problemy)[0].Tytul)"
Wyczysc
Atrapa 15 @{ wynik = "zrobione" }
$o = O
Wynik "negatywna: nieznany wynik 'zrobione' -> sprawa z nazwa pliku, nie cisza" ((@($o.Problemy).Count -eq 1) -and (@($o.Problemy)[0].Tytul -match '15\.json') -and (@($o.Problemy)[0].Pelne -match "nieznany wynik 'zrobione'") -and (@($o.Problemy)[0].Plik -eq (Join-Path $katWynikow "15.md"))) "$(@($o.Problemy)[0].Tytul) | $(@($o.Problemy)[0].Pelne)"
Wyczysc
Atrapa 16 @{ wynik = "blad"; powod = "" } $false
$o = O
$p = @($o.Problemy)[0]
Wynik "negatywna: blad bez powodu i bez .md -> mowi, ze powodu nie podano i ze raportu brak" (($p.Waga -eq "pilne") -and ($p.Tytul -match 'nie podało powodu') -and ($p.Porada -match 'brakuje pliku 16\.md') -and (-not $p.Plik)) "$($p.Tytul) | $($p.Porada)"
Wyczysc
Atrapa 17 @{ wynik = "czlowiek"; co_zrobic = "" }
$o = O
Wynik "negatywna: czlowiek bez co_zrobic -> sprawa mowi, ze nie zapisalo co zrobic" ((@($o.Problemy)[0].Tytul -match 'nie zapisało, co masz zrobić')) "$(@($o.Problemy)[0].Tytul)"
Wyczysc
Atrapa 18 @{ tresc = "Krótka treść" }
Atrapa 19 @{ wynik = "nic"; koniec = (IsoUtc (Get-Date).AddMinutes(-30)) }
$o = O
Wynik "krotka tresc bez wielokropka; dwa wyniki 'nic' od najnowszego" ((@($o.Linie).Count -eq 2) -and (@($o.Linie)[0].Tekst -match '#18 .*Planer FBA: Krótka treść$') -and (@($o.Linie)[1].Tekst -match '^Przypomnienie #19 ')) ((@($o.Linie) | ForEach-Object { $_.Tekst }) -join " || ")
$lw = (Linie-Wynikow-Przypomnien $o) -join "`n"
Wynik "wydruk tekstowy linii 'nic' z plikiem do 'Pokaż wynik'" (($lw -match "Przypomnienia w tle: $ZNAKOK Przypomnienie #18 zrobione samo") -and ($lw -match [regex]::Escape("[Pokaż wynik: $(Join-Path $katWynikow '18.md')]"))) $lw
Wyczysc
Atrapa 20 @{ koniec = ""; start = "" }
Postarz "20.json" (Get-Date).AddHours(-2)
$o = O
Wynik "wynik bez dat -> czas z zapisu pliku (2 h temu, wciaz pokazany)" ((@($o.Linie).Count -eq 1)) "$(@($o.Linie)[0].Tekst)"
Postarz "20.json" (Get-Date).AddHours(-25)
$o = O
Wynik "wynik bez dat, plik sprzed 25 h -> nic" ((@($o.Linie).Count -eq 0)) "linie=$(@($o.Linie).Count)"

# Sabotaz: kopia stan-terminy.ps1 z wylaczonym jednym warunkiem, wczytana w miejsce prawdziwej.
# Wlasciwa proba MUSI wtedy paść - inaczej nie pilnuje niczego. Kotwica sprawdzana przed podmiana
# (brak kotwicy = porazka testu, a nie sabotaz, ktory po cichu niczego nie zmienil).
$plikTerminow = Join-Path $Zasobnik "nadzorca\stan-terminy.ps1"
$oryginal = [System.IO.File]::ReadAllText($plikTerminow, [System.Text.Encoding]::UTF8)
$sabotaze = @(
  @{ Nazwa = "blad pokazany jako spokojna linia"; Proba = "Proba-Blad"
     Kotwica = 'switch ($r.Wynik) {'; Zamiana = 'switch ($(if ($r.Wynik -eq "blad") { "nic" } else { $r.Wynik })) {' },
  @{ Nazwa = "nieczytelny plik polkniety po cichu"; Proba = "Proba-Nieczytelny"
     Kotwica = 'if ($r.Blad) {'; Zamiana = 'if ($r.Blad) { continue' },
  @{ Nazwa = "doba wylaczona (stare wyniki wiecznie)"; Proba = "Proba-Stary"
     Kotwica = '(($teraz - $_.Kiedy).TotalHours -lt $GODZIN_WYNIKU_PRZYPOMNIENIA)'; Zamiana = '$true' })
$kopiaSabotazu = Join-Path $tmp "stan-terminy-sabotaz.ps1"
foreach ($s in $sabotaze) {
  if (-not $oryginal.Contains($s.Kotwica)) { Wynik "sabotaz '$($s.Nazwa)' wylapany" $false "kotwicy nie ma w ${plikTerminow}: $($s.Kotwica)"; continue }
  [System.IO.File]::WriteAllText($kopiaSabotazu, $oryginal.Replace($s.Kotwica, $s.Zamiana), (New-Object System.Text.UTF8Encoding($true)))
  . $kopiaSabotazu
  $pod = $null
  try { $pod = & $s.Proba } catch { $pod = [pscustomobject]@{ Ok = $false; Opis = "WYWROTKA: $($_.Exception.Message)" } }
  . $plikTerminow
  $po = & $s.Proba
  Wynik "sabotaz '$($s.Nazwa)' wylapany przez $($s.Proba)" ((-not $pod.Ok) -and $po.Ok) "z sabotazem: $($pod.Opis) || po przywroceniu: Ok=$($po.Ok)"
}
. $plikTerminow

# ---------------------------------------------------------------- B. okno poza ekranem
if (-not $BezOkna) {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
public class OknoTestowePrzypomnien : System.Windows.Forms.Form {
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override System.Windows.Forms.CreateParams CreateParams {
    get { System.Windows.Forms.CreateParams cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x00000080; return cp; }
  }
}
'@
  $script:NadzWywrotki = @()
  foreach ($m in @("wyglad", "karty", "przeglad", "okno")) { . (Join-Path $Zasobnik "nadzorca\$m.ps1") }
  # Notatnik podmieniony: zapisujemy, co mialby otworzyc, i nic sie nie otwiera.
  $script:OtwartoWNotatniku = @()
  function Otworz-W-Notatniku([string]$plik) { $script:OtwartoWNotatniku += $plik }

  $f = New-Object OknoTestowePrzypomnien
  $f.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
  $f.Location = New-Object System.Drawing.Point(-5000, 0)
  $f.ShowInTaskbar = $false
  $f.KeyPreview = $true
  $f.Add_KeyDown({ param($n, $e) $e.Handled = $true; $e.SuppressKeyPress = $true })
  $f.ClientSize = New-Object System.Drawing.Size($script:SzerOkna, 640)
  $f.BackColor = $script:TloOkna
  $f.Font = $script:CzZwykla
  $script:WidokPrzeglad = New-Object System.Windows.Forms.Panel
  $script:WidokPrzeglad.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:WidokPrzeglad.AutoScroll = $true
  $script:WidokPrzeglad.Padding = New-Object System.Windows.Forms.Padding($script:Margines, 8, $script:Margines, 8)
  $script:Root = Pionowy $script:SzerTresc
  $script:Root.Dock = [System.Windows.Forms.DockStyle]::Top
  $script:PanelProblemy = Pionowy $script:SzerTresc
  $script:PanelProblemy.Visible = $false
  $script:PanelStan = Nowa-Karta $script:SzerKarty
  $script:Root.Controls.Add($script:PanelProblemy)
  $script:Root.Controls.Add($script:PanelStan)
  $script:WidokPrzeglad.Controls.Add($script:Root)
  $f.Controls.Add($script:WidokPrzeglad)
  $script:Okno = $f
  $script:Dane = $D
  $script:Instalacja = $inst
  $script:Widok = "przeglad"
  $f.Show()
  [System.Windows.Forms.Application]::DoEvents()

  function Teksty($c) {
    $l = @()
    foreach ($d in $c.Controls) { if (-not $d.Visible) { continue }; if ("$($d.Text)") { $l += "$($d.Text)" }; $l += Teksty $d }
    return $l
  }
  function Linki($c) {
    $l = @()
    foreach ($d in $c.Controls) { if (-not $d.Visible) { continue }; if ($d -is [System.Windows.Forms.LinkLabel]) { $l += $d }; $l += Linki $d }
    return $l
  }
  function Etykiety($c) {
    $l = @()
    foreach ($d in $c.Controls) { if ($d -is [System.Windows.Forms.Label]) { $l += $d }; $l += Etykiety $d }
    return $l
  }
  function Zrzut([string]$nazwa) {
    $f.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    $b = New-Object System.Drawing.Bitmap($f.Width, $f.Height)
    $f.DrawToBitmap($b, (New-Object System.Drawing.Rectangle(0, 0, $f.Width, $f.Height)))
    $p = Join-Path $Zrzuty "przypomnienia-$nazwa.png"
    $b.Save($p); $b.Dispose()
    return $p
  }
  function Odmaluj { Odmaluj-Problemy; Odmaluj-Stan; [System.Windows.Forms.Application]::DoEvents() }
  # Klikniecie w link jak uzytkownik: LinkClicked przez chroniona OnLinkClicked.
  function Kliknij-Link($l) {
    $m = [System.Windows.Forms.LinkLabel].GetMethod("OnLinkClicked", [System.Reflection.BindingFlags]"NonPublic,Instance")
    $ea = [System.Windows.Forms.LinkLabelLinkClickedEventArgs]::new($l.Links[0])
    [void]$m.Invoke($l, [object[]]@($ea.PSObject.BaseObject))
    [System.Windows.Forms.Application]::DoEvents()
  }

  try {
    Wyczysc
    Odmaluj
    $t = (Teksty $script:PanelStan) -join " | "
    Wynik "okno: brak katalogu -> bez linii przypomnien, 'Wszystko gra'" (($t -notmatch 'Przypomnienia w tle') -and ($t -match 'Wszystko gra') -and (-not $script:PanelProblemy.Visible)) $t

    Atrapa 7 @{}
    Odmaluj
    $t = (Teksty $script:PanelStan) -join " | "
    $linia = @(Etykiety $script:PanelStan | Where-Object { "$($_.Text)" -like "$ZNAKOK Przypomnienie #7 zrobione samo*" }) | Select-Object -First 1
    $pp = Podpowiedz-Przypomnien
    $podp = ""; if ($linia) { $podp = $pp.GetToolTip($linia) }
    $ok = $linia -and ($linia.ForeColor.ToArgb() -eq $script:KolDobrze.ToArgb()) -and ($t -match 'Przypomnienia w tle') -and ($t -match 'Wszystko gra') -and
          (-not $script:PanelProblemy.Visible) -and ($podp -match 'czy są nowe pozycje na żółto') -and ("$($linia.Text)".EndsWith($WIELOKROPEK))
    Wynik "okno: nic -> zielona linia w karcie Stan, pelna tresc w podpowiedzi, 'Wszystko gra' zostaje" $ok "$t || podpowiedz: $podp"
    $l = @(Linki $script:PanelStan | Where-Object { $_.Text -eq "Pokaż wynik" })
    $script:OtwartoWNotatniku = @()
    if ($l.Count -eq 1) { Kliknij-Link $l[0] }
    Wynik "okno: 'Pokaż wynik' przy linii otwiera 7.md (Notatnik podmieniony)" (($l.Count -eq 1) -and ($l[0].Tag -eq (Join-Path $katWynikow "7.md")) -and (@($script:OtwartoWNotatniku).Count -eq 1) -and ($script:OtwartoWNotatniku[0] -eq (Join-Path $katWynikow "7.md"))) "linkow=$($l.Count) tag=$($l[0].Tag) otwarto=$($script:OtwartoWNotatniku -join ',')"
    [void](Zrzut "1-nic")

    # pliku .md juz nie ma w chwili klikniecia - link mowi to wprost, Notatnik sie nie otwiera
    Remove-Item -LiteralPath (Join-Path $katWynikow "7.md") -Force
    $script:OtwartoWNotatniku = @()
    $wPrzed = @($script:NadzWywrotki).Count
    Kliknij-Link $l[0]
    Wynik "negatywna okno: klik, a pliku .md nie ma -> 'Nie ma pliku z wynikiem' i wpis, Notatnik nie rusza" (($l[0].Text -eq "Nie ma pliku z wynikiem") -and (@($script:OtwartoWNotatniku).Count -eq 0) -and (@($script:NadzWywrotki).Count -eq ($wPrzed + 1))) "$($l[0].Text) | wywrotki: $(@($script:NadzWywrotki) -join ' || ')"
    $script:NadzWywrotki = @()

    Wyczysc
    Atrapa 8 @{ wynik = "czlowiek"; co_zrobic = "Kliknij w Seller Central 'Zatwierdź wysyłkę' dla FBA15K." }
    Odmaluj
    $t = (Teksty $script:PanelStan) -join " | "
    $tp = (Teksty $script:PanelProblemy) -join " | "
    $l = @(Linki $script:PanelProblemy | Where-Object { $_.Text -eq "Pokaż wynik" })
    $script:OtwartoWNotatniku = @()
    if ($l.Count -eq 1) { Kliknij-Link $l[0] }
    Wynik "okno: czlowiek -> zolta karta 'Do sprawdzenia' z 'Pokaż wynik' (8.md), bez 'Wszystko gra'" ($script:PanelProblemy.Visible -and ($tp -match 'DO SPRAWDZENIA') -and
      ($tp -match 'Przypomnienie #8 czeka na Ciebie: Kliknij w Seller Central') -and ($t -notmatch 'Wszystko gra') -and ($l.Count -eq 1) -and
      ($script:OtwartoWNotatniku[0] -eq (Join-Path $katWynikow "8.md")) -and ((Ile-Wymaga-Uwagi $script:Problemy) -eq 1)) "$tp || otwarto=$($script:OtwartoWNotatniku -join ',')"
    [void](Zrzut "2-czlowiek")

    Atrapa 9 @{ wynik = "blad"; powod = "Claude Code nie wystartował: brak pliku claude.exe." }
    Odmaluj
    $t = (Teksty $script:PanelStan) -join " | "
    $tp = (Teksty $script:PanelProblemy) -join " | "
    $pierwsza = $script:PanelProblemy.Controls[0]
    $czerw = $false
    foreach ($c in $pierwsza.Controls) { if (("$($c.Text)" -like "Przypomnienie #9 nie wykonało się*") -and ($c.ForeColor.ToArgb() -eq $script:KolPilne.ToArgb())) { $czerw = $true } }
    $l = @(Linki $pierwsza | Where-Object { $_.Text -eq "Pokaż wynik" })
    Wynik "negatywna okno: blad -> czerwona karta 'Wymaga działania' na samej gorze, przed zolta, z 'Pokaż wynik' (9.md)" ($czerw -and ($tp -match 'WYMAGA DZIAŁANIA') -and
      ($t -notmatch 'Wszystko gra') -and ($l.Count -eq 1) -and ($l[0].Tag -eq (Join-Path $katWynikow "9.md")) -and ((Ile-Wymaga-Uwagi $script:Problemy) -eq 2)) "$tp"
    [void](Zrzut "3-blad")

    Wyczysc
    New-Item -ItemType Directory -Force -Path $katWynikow | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $katWynikow "12.json"), '{"id": 12, "wynik": "czl', $UTF8)
    Postarz "12.json" (Get-Date).AddMinutes(-1)
    Odmaluj
    $t = (Teksty $script:PanelStan) -join " | "
    $tp = (Teksty $script:PanelProblemy) -join " | "
    Wynik "negatywna okno: nieczytelny plik -> karta z nazwa pliku, bez 'Wszystko gra'" ($script:PanelProblemy.Visible -and ($tp -match '12\.json') -and ($t -notmatch 'Wszystko gra')) $tp
    [void](Zrzut "4-nieczytelny")

    # gdy Zbierz-Problemy (przeglad-tresc.ps1) zacznie sama zbierac te sprawy - bez dubli
    Wyczysc
    Atrapa 9 @{ wynik = "blad"; powod = "x" }
    $zbierzOrg = ${function:Zbierz-Problemy}
    function Zbierz-Problemy($d, $w, $b, $c) { $l = @((Ocena-Wynikow-Przypomnien-Teraz).Problemy); return ,$l }
    Odmaluj
    $ile = @($script:Problemy).Count
    ${function:Zbierz-Problemy} = $zbierzOrg
    Wynik "sprawy przypomnien juz w Zbierz-Problemy -> okno nie dokłada ich drugi raz" ($ile -eq 1) "spraw: $ile"

    Wyczysc
    Atrapa 21 @{ wynik = "nic" }
    Atrapa 22 @{ wynik = "czlowiek"; co_zrobic = "Sprawdź etykiety." }
    Odmaluj
    $t = (Teksty $script:PanelStan) -join " | "
    $tp = (Teksty $script:PanelProblemy) -join " | "
    Wynik "okno: nic i czlowiek naraz -> linia w Stan i jedna sprawa, bez 'Wszystko gra'" (($t -match 'Przypomnienie #21 zrobione samo') -and ($tp -match 'Przypomnienie #22 czeka na Ciebie') -and ($t -notmatch 'Wszystko gra')) "$t || $tp"
    [void](Zrzut "5-nic-i-czlowiek")
  } catch {
    Wynik "okno: WYWROTKA TESTU" $false "$($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
  } finally {
    $f.Close(); $f.Dispose()
  }
  $wywr = @($script:NadzWywrotki)
  Wynik "okno: bez wywrotek nadzorcy" ($wywr.Count -eq 0) ($wywr -join " || ")
}

Write-Host ""
Write-Host "Zrzuty: $Zrzuty"
Write-Host "Wynik: $(@($script:wyniki | Where-Object { $_.OK }).Count) z $($script:wyniki.Count) TAK. Pliki robocze: $tmp"
if (@($script:wyniki | Where-Object { -not $_.OK }).Count -gt 0) { exit 1 }
exit 0
