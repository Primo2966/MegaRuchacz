# narzedzia\instalacja\stan.ps1 - wspolny rejestr zainstalowanych modulow MegaRuchacza.
#
# To jest UMOWA miedzy instalatorem (instalator\), skryptami modulow
# (narzedzia\instalacja\modul-*.ps1), straznikiem, nadzorca i hookiem przypomnienia.
# Wczytuj kropka:  . (Join-Path $Zrodlo 'narzedzia\instalacja\stan.ps1')
#
# Plik stanu: <KatalogDomowy>\.claude\mr\instalacja.json  (UTF-8 bez BOM)
#   {
#     "wersja": 1,
#     "moduly": { "wiedza": true, "lore": true, "kierownik": true, "skille": true, "kopia": false },
#     "kopia": { "zrodla": ["C:\\dev"], "cel": "G:\\..." }   albo null,
#     "narzedzia": { "claude": true, "codex": false, "opencode": false }   albo null,
#     "data": "RRRR-MM-DD GG:MM:SS"
#   }
# Baza (aplikacja przy zegarze + straznik/aktualizacje) jest zawsze - nie ma jej w "moduly".
#
# Zasady odczytu (te same w Node i Pythonie):
#   - brak pliku = instalacja sprzed rejestru: wiedza, lore, kierownik, skille wlaczone;
#     kopia wlaczona tylko, gdy istnieje .claude\mr\kopia-stan.txt;
#   - plik nieczytelny (pusty, wyzerowany, zly JSON) = wszystko wlaczone + pole "blad";
#     przy bledzie NIC nie wolno odinstalowac, tylko alarmowac (Cisza jest zakazana);
#   - brak klucza modulu w pliku = jak przy braku pliku.

$script:MR_MODULY = @('wiedza', 'lore', 'kierownik', 'skille', 'kopia')

function Moduly-MegaRuchacza { return $script:MR_MODULY }

function Sciezka-Instalacji([string]$KatalogDomowy = $HOME) {
  return (Join-Path $KatalogDomowy '.claude\mr\instalacja.json')
}

function Domyslne-Moduly([string]$KatalogDomowy = $HOME) {
  $m = [ordered]@{}
  foreach ($n in $script:MR_MODULY) { $m[$n] = $true }
  $m['kopia'] = Test-Path -LiteralPath (Join-Path $KatalogDomowy '.claude\mr\kopia-stan.txt')
  return $m
}

function Czytaj-Instalacje([string]$KatalogDomowy = $HOME) {
  $p = Sciezka-Instalacji $KatalogDomowy
  $domyslne = Domyslne-Moduly $KatalogDomowy
  $wynik = [pscustomobject]@{
    wersja    = 1
    moduly    = [pscustomobject]$domyslne
    kopia     = $null
    narzedzia = $null
    data      = $null
    zrodlo    = 'domyslne'
    blad      = $null
  }
  if (-not (Test-Path -LiteralPath $p)) { return $wynik }
  try {
    $bajty = [System.IO.File]::ReadAllBytes($p)
    if ($bajty.Length -eq 0) { throw 'plik jest pusty' }
    if ([Array]::IndexOf($bajty, [byte]0) -ge 0) { throw 'plik zawiera bajty 0x00 (uszkodzony, np. po zaniku zasilania)' }
    $tekst = (New-Object System.Text.UTF8Encoding($false)).GetString($bajty).TrimStart([char]0xFEFF)
    $j = $tekst | ConvertFrom-Json
    if ($null -eq $j -or $null -eq $j.moduly) { throw 'brak pola "moduly"' }
    foreach ($n in $script:MR_MODULY) {
      if ($null -eq $j.moduly.$n) {
        $j.moduly | Add-Member -NotePropertyName $n -NotePropertyValue $domyslne[$n] -Force
      }
    }
    foreach ($pole in @('wersja', 'kopia', 'narzedzia', 'data')) {
      if (-not ($j.PSObject.Properties.Name -contains $pole)) {
        $j | Add-Member -NotePropertyName $pole -NotePropertyValue $null -Force
      }
    }
    $j | Add-Member -NotePropertyName zrodlo -NotePropertyValue 'plik' -Force
    $j | Add-Member -NotePropertyName blad -NotePropertyValue $null -Force
    return $j
  } catch {
    $wynik.zrodlo = 'awaryjne'
    $wynik.blad = "nie umiem odczytac rejestru instalacji $p : $($_.Exception.Message)"
    return $wynik
  }
}

function Modul-Wlaczony([string]$Nazwa, [string]$KatalogDomowy = $HOME) {
  if ($script:MR_MODULY -notcontains $Nazwa) { throw "nieznany modul MegaRuchacza: $Nazwa" }
  $s = Czytaj-Instalacje $KatalogDomowy
  return [bool]$s.moduly.$Nazwa
}

# Zapis atomowy z wymuszeniem zapisu na dysk: plik tymczasowy w tym samym katalogu,
# Flush(true), potem podmiana. Zanik pradu zostawia albo stary, albo nowy plik - nigdy zera.
function Zapisz-Instalacje($Stan, [string]$KatalogDomowy = $HOME) {
  if ($Stan.blad) { throw "odmawiam zapisu rejestru instalacji: odczyt byl bledny ($($Stan.blad))" }
  $p = Sciezka-Instalacji $KatalogDomowy
  $katalog = Split-Path -Parent $p
  if (-not (Test-Path -LiteralPath $katalog)) { New-Item -ItemType Directory -Path $katalog -Force | Out-Null }
  $Stan | Add-Member -NotePropertyName data -NotePropertyValue ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -Force
  $json = $Stan | Select-Object -Property * -ExcludeProperty zrodlo, blad | ConvertTo-Json -Depth 6
  $bajty = (New-Object System.Text.UTF8Encoding($false)).GetBytes($json)
  $tmp = "$p.tmp-$PID"
  $fs = [System.IO.File]::Open($tmp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
  try {
    $fs.Write($bajty, 0, $bajty.Length)
    $fs.Flush($true)
  } finally {
    $fs.Dispose()
  }
  if (Test-Path -LiteralPath $p) {
    [System.IO.File]::Replace($tmp, $p, $null)
  } else {
    [System.IO.File]::Move($tmp, $p)
  }
}

function Ustaw-Modul([string]$Nazwa, [bool]$Wlaczony, [string]$KatalogDomowy = $HOME) {
  if ($script:MR_MODULY -notcontains $Nazwa) { throw "nieznany modul MegaRuchacza: $Nazwa" }
  $s = Czytaj-Instalacje $KatalogDomowy
  if ($s.blad) { throw $s.blad }
  $s.moduly | Add-Member -NotePropertyName $Nazwa -NotePropertyValue $Wlaczony -Force
  Zapisz-Instalacje $s $KatalogDomowy
}
