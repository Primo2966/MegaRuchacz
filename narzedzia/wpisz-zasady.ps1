# Wpisuje zasady globalne MegaRuchacza do plikow instrukcji narzedzi AI uzytkownika.
# Zrodlo tresci: zasady-globalne.md (tylko to, co jest pod linia-znacznikiem).
#
# Uzycie:
#   powershell -File C:\dev\claude-worker\narzedzia\wpisz-zasady.ps1
#     -Proba                  wypisuje, co by zrobil, ale nic nie zapisuje
#     -Usun                   wycina blok razem ze znacznikami
#     -Zrodlo <katalog>       katalog glowny repo (domyslnie katalog nad narzedzia\)
#     -KatalogDomowy <kat>    wewnetrzne: podmiana bazy sciezek docelowych (testy)
#
# Tresc laduje miedzy znacznikami MegaRuchacz:start / :koniec. Reszta pliku -
# czyli wlasne zapiski uzytkownika - zostaje nietknieta. Przed kazda zmiana kopia.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [string]$KatalogDomowy = $HOME,
  [switch]$Usun,
  [switch]$Proba
)

$ZnacznikStart  = "<!-- MegaRuchacz:start -->"
$ZnacznikKoniec = "<!-- MegaRuchacz:koniec -->"
$Stempel = Get-Date -Format "yyyyMMdd-HHmmss"

# UTF-8 bez BOM przy zapisie, UTF-8 rzucajacy bledem przy odczycie -
# zepsute polskie znaki maja wywalic skrypt, a nie przejsc po cichu.
$Utf8Zapis  = New-Object System.Text.UTF8Encoding($false)
$Utf8Odczyt = New-Object System.Text.UTF8Encoding($false, $true)

$script:Bledy = 0
$script:Raport = @()

function Czytaj($sciezka) {
  return [System.IO.File]::ReadAllText($sciezka, $Utf8Odczyt)
}

function Zapisz($sciezka, $tekst) {
  [System.IO.File]::WriteAllText($sciezka, $tekst, $Utf8Zapis)
}

function Koniec-Linii($tekst) {
  if ($tekst.Contains("`r`n")) { return "`r`n" }
  if ($tekst.Contains("`n"))   { return "`n" }
  return "`r`n"
}

function Kopia-Zapasowa($sciezka) {
  $bak = "$sciezka.bak-$Stempel"
  Copy-Item $sciezka $bak -Force
  return $bak
}

# Odczyt kontrolny po zapisie - najczestsza cicha wpadka na Windowsie to
# rozsypane polskie znaki, wiec porownujemy to, co wyszlo, z tym, co mialo wejsc.
function Sprawdz-Zapis($plik, $nazwa, $blok, $maByc) {
  try { $sprawdzony = Czytaj $plik }
  catch {
    Write-Host "BLAD  $nazwa - po zapisie $plik nie daje sie odczytac jako UTF-8" -ForegroundColor Red
    $script:Bledy++
    return $false
  }
  if ($sprawdzony.IndexOf([char]0xFFFD) -ge 0) {
    Write-Host "BLAD  $nazwa - w $plik siedza rozsypane znaki po zapisie" -ForegroundColor Red
    $script:Bledy++
    return $false
  }
  if ($maByc -and $sprawdzony.IndexOf($blok, [System.StringComparison]::Ordinal) -lt 0) {
    Write-Host "BLAD  $nazwa - blok w $plik nie zgadza sie z tym, co mialo byc zapisane" -ForegroundColor Red
    $script:Bledy++
    return $false
  }
  if ((-not $maByc) -and ($sprawdzony.Contains($ZnacznikStart) -or $sprawdzony.Contains($ZnacznikKoniec))) {
    Write-Host "BLAD  $nazwa - w $plik dalej siedza znaczniki MegaRuchacza" -ForegroundColor Red
    $script:Bledy++
    return $false
  }
  return $true
}

# --- tresc do wstrzykniecia --------------------------------------------------

function Pobierz-Tresc($plikZrodlowy) {
  $linie = (Czytaj $plikZrodlowy) -split "\r?\n"
  $start = -1
  for ($i = 0; $i -lt $linie.Count; $i++) {
    if ($linie[$i] -match '^<!--.*WSTRZYKNI.*-->\s*$') { $start = $i; break }
  }
  if ($start -lt 0) {
    Write-Error "W $plikZrodlowy nie ma linii-znacznika 'TRESC DO WSTRZYKNIECIA PONIZEJ TEJ LINII'."
    exit 1
  }
  $ogon = @()
  if ($start -lt ($linie.Count - 1)) { $ogon = @($linie[($start + 1)..($linie.Count - 1)]) }
  # obcinamy puste linie z gory i z dolu na indeksach, nie zakresami -
  # zakres 0..-1 w PowerShellu zawija sie na koniec tablicy i robi petle bez konca
  $od = 0
  $doo = $ogon.Count - 1
  while ($od -le $doo -and $ogon[$od].Trim() -eq "")  { $od++ }
  while ($doo -ge $od -and $ogon[$doo].Trim() -eq "") { $doo-- }
  if ($od -gt $doo) {
    Write-Error "W $plikZrodlowy pod linia-znacznikiem nie ma zadnej tresci."
    exit 1
  }
  return @($ogon[$od..$doo])
}

# --- operacje na pliku docelowym ---------------------------------------------

function Wstaw-Blok($plik, $nazwa, $tresc) {
  $istnieje = Test-Path $plik
  $stary = ""
  if ($istnieje) {
    try { $stary = Czytaj $plik }
    catch {
      Write-Host "BLAD  $nazwa - nie umiem odczytac $plik jako UTF-8, nie ruszam go" -ForegroundColor Red
      $script:Bledy++
      return
    }
  }

  $nl = Koniec-Linii $stary
  $blok = ($ZnacznikStart, ($tresc -join $nl), $ZnacznikKoniec) -join $nl
  $linijek = ($blok -split "\r?\n").Count

  $i = $stary.IndexOf($ZnacznikStart, [System.StringComparison]::Ordinal)
  $j = $stary.IndexOf($ZnacznikKoniec, [System.StringComparison]::Ordinal)

  if (($i -ge 0) -xor ($j -ge 0)) {
    Write-Host "BLAD  $nazwa - w $plik jest tylko jeden znacznik MegaRuchacza, nie ruszam go" -ForegroundColor Red
    $script:Bledy++
    return
  }
  if ($i -ge 0 -and $j -lt $i) {
    Write-Host "BLAD  $nazwa - znaczniki MegaRuchacza w $plik sa w zlej kolejnosci, nie ruszam go" -ForegroundColor Red
    $script:Bledy++
    return
  }

  if ($i -ge 0) {
    $co = "podmieniam blok"
    $nowy = $stary.Substring(0, $i) + $blok + $stary.Substring($j + $ZnacznikKoniec.Length)
  } elseif ($stary.Trim().Length -eq 0) {
    if ($istnieje) { $co = "wpisuje blok do pustego pliku" } else { $co = "zakladam plik z blokiem" }
    $nowy = $blok + $nl
  } else {
    $co = "dopisuje blok na koncu"
    $nowy = $stary.TrimEnd("`r", "`n") + $nl + $nl + $blok + $nl
  }

  if ($nowy -ceq $stary) {
    Write-Host "--  $nazwa - blok juz jest aktualny: $plik"
    $script:Raport += "$nazwa : bez zmian (blok aktualny)"
    return
  }

  if ($Proba) {
    Write-Host "PROBA  $nazwa - $co ($linijek linii) w $plik"
    if ($istnieje) { Write-Host "PROBA  $nazwa - kopia trafilaby do $plik.bak-$Stempel" }
    $script:Raport += "$nazwa : PROBA, $co, $linijek linii"
    return
  }

  $bak = $null
  if ($istnieje) { $bak = Kopia-Zapasowa $plik }
  Zapisz $plik $nowy

  if (-not (Sprawdz-Zapis $plik $nazwa $blok $true)) { return }

  Write-Host "OK  $nazwa - $co ($linijek linii): $plik"
  $wpis = "$nazwa : $co, $linijek linii"
  if ($bak) {
    Write-Host "    kopia: $bak"
    $wpis = "$wpis, kopia $bak"
  }
  $script:Raport += $wpis
}

function Usun-Blok($plik, $nazwa) {
  if (-not (Test-Path $plik)) {
    Write-Host "--  $nazwa - nie ma pliku $plik, nie ma czego usuwac"
    $script:Raport += "$nazwa : brak pliku"
    return
  }
  try { $stary = Czytaj $plik }
  catch {
    Write-Host "BLAD  $nazwa - nie umiem odczytac $plik jako UTF-8, nie ruszam go" -ForegroundColor Red
    $script:Bledy++
    return
  }

  $i = $stary.IndexOf($ZnacznikStart, [System.StringComparison]::Ordinal)
  $j = $stary.IndexOf($ZnacznikKoniec, [System.StringComparison]::Ordinal)
  if ($i -lt 0 -or $j -lt $i) {
    Write-Host "--  $nazwa - w $plik nie ma bloku MegaRuchacza, zostawiam"
    $script:Raport += "$nazwa : bez zmian (brak bloku)"
    return
  }

  $nl = Koniec-Linii $stary
  $wyciete = ($stary.Substring($i, $j + $ZnacznikKoniec.Length - $i) -split "\r?\n").Count
  $przed = $stary.Substring(0, $i).TrimEnd("`r", "`n")
  $po    = $stary.Substring($j + $ZnacznikKoniec.Length).TrimStart("`r", "`n")

  # sklejamy tak, zeby po wycieciu nie zostala podwojna pusta linia
  if ($przed.Length -eq 0)  { $nowy = $po }
  elseif ($po.Length -eq 0) { $nowy = $przed + $nl }
  else                      { $nowy = $przed + $nl + $nl + $po }

  if ($Proba) {
    Write-Host "PROBA  $nazwa - wycialbym blok ($wyciete linii) z $plik"
    Write-Host "PROBA  $nazwa - kopia trafilaby do $plik.bak-$Stempel"
    $script:Raport += "$nazwa : PROBA, wyciecie bloku, $wyciete linii"
    return
  }

  $bak = Kopia-Zapasowa $plik
  Zapisz $plik $nowy

  if (-not (Sprawdz-Zapis $plik $nazwa $null $false)) { return }

  Write-Host "OK  $nazwa - blok wyciety ($wyciete linii): $plik"
  Write-Host "    kopia: $bak"
  $script:Raport += "$nazwa : blok wyciety, $wyciete linii, kopia $bak"
}

# --- przebieg ----------------------------------------------------------------

if (-not (Test-Path $KatalogDomowy)) {
  Write-Error "Nie ma takiego katalogu domowego: $KatalogDomowy"
  exit 1
}
$KatalogDomowy = (Resolve-Path $KatalogDomowy).Path

$tresc = $null
if (-not $Usun) {
  if (-not (Test-Path $Zrodlo)) { Write-Error "Nie ma takiego katalogu zrodlowego: $Zrodlo"; exit 1 }
  $Zrodlo = (Resolve-Path $Zrodlo).Path
  $plikZrodlowy = Join-Path $Zrodlo "zasady-globalne.md"
  if (-not (Test-Path $plikZrodlowy)) {
    Write-Error "Nie ma pliku ze zrodlem zasad: $plikZrodlowy"
    exit 1
  }
  $tresc = Pobierz-Tresc $plikZrodlowy
  Write-Host "Zrodlo: $plikZrodlowy ($($tresc.Count) linii tresci)"
}

if ($Proba) { Write-Host "TRYB PROBY - nic nie zostanie zapisane" -ForegroundColor Yellow }

$Cele = @(
  @{ Nazwa = "Claude Code"; Katalog = (Join-Path $KatalogDomowy ".claude"); Plik = "CLAUDE.md"; Zakladaj = $true  },
  @{ Nazwa = "Codex";       Katalog = (Join-Path $KatalogDomowy ".codex");  Plik = "AGENTS.md"; Zakladaj = $false }
)

foreach ($cel in $Cele) {
  $plik = Join-Path $cel.Katalog $cel.Plik

  if (-not (Test-Path $cel.Katalog)) {
    if (-not $cel.Zakladaj) {
      Write-Host "--  $($cel.Nazwa) - nie ma $($cel.Katalog), czyli nie ma tego narzedzia na tej maszynie: pomijam"
      $script:Raport += "$($cel.Nazwa) : pominiete (brak narzedzia)"
      continue
    }
    if ($Proba) {
      Write-Host "PROBA  $($cel.Nazwa) - zalozylbym katalog $($cel.Katalog)"
    } else {
      New-Item -ItemType Directory -Force -Path $cel.Katalog | Out-Null
    }
  }

  if ($Usun) { Usun-Blok $plik $cel.Nazwa }
  else       { Wstaw-Blok $plik $cel.Nazwa $tresc }
}

Write-Host ""
Write-Host "Podsumowanie:"
foreach ($linia in $script:Raport) { Write-Host "  $linia" }

if ($script:Bledy -gt 0) {
  Write-Host ""
  Write-Host "Zakonczone bledem - $($script:Bledy) plik(ow) nie przeszlo." -ForegroundColor Red
  exit 1
}

Write-Host ""
if ($Proba)    { Write-Host "Proba zakonczona - zaden plik nie ruszony." }
elseif ($Usun) { Write-Host "Gotowe - blok MegaRuchacza usuniety, reszta plikow bez zmian." }
else           { Write-Host "Gotowe - zasady wpisane. Zamknij i otworz narzedzie na nowo." }
exit 0
