# Zapis plikow pamieci odporny na zanik zasilania i rozpoznawanie plikow wyzerowanych.
# Wczytywany kropka (same definicje) przez straznik-zasad.ps1, wpisz-zasady.ps1,
# cykl-dzienny.ps1 i kopie-dzienne.ps1. Strona Pythona to samo robi w lore\lore\safeio.py.
#
# Skad to sie wzielo: 2026-10-02 08:03 cykl wiedzy zapisal CLAUDE.md i jedenascie plikow
# w wiedza\, a ~30 s pozniej komputer padl bez zamkniecia (Kernel-Power 41). NTFS mial juz
# w dzienniku nowe rozmiary plikow, ale nie dane - po restarcie kazdy z nich mial pelna
# dlugosc i same bajty 0x00 w srodku. Straznik wzial wyzerowany CLAUDE.md za tekst
# uzytkownika, dokleil do niego bloki i zrobil "kopie zapasowa" zer.
#
# Stad dwie zasady:
#   - plik pamieci piszemy do pliku tymczasowego w TYM SAMYM katalogu, z zapisem przez
#     bufor dysku (WriteThrough + Flush(true)), i dopiero potem podmieniamy stary - zanik
#     pradu w dowolnej chwili zostawia stary albo nowy plik, nigdy wyzerowana hybryde,
#   - na pliku z choc jednym bajtem 0x00 niczego nie budujemy i nie robimy z niego kopii.
#     Zaden nasz plik tekstowy nie ma prawa miec zera w srodku, wiec jedno zero to dowod
#     zepsutego zapisu, a nie kwestia gustu.

# Podmiana pliku, ktory inny proces trzyma akurat otwarty (hook czytajacy CLAUDE.md,
# edytor), na Windowsie sie nie udaje. Kilka krotkich prob pokrywa taka chwile; ~2 s.
$script:ZapisProb   = 20
$script:ZapisPauzaMs = 100

# Ktore pliki w wiedza\ sa nasze i tekstowe - tylko te sprawdzamy na zera, zeby plik
# binarny wrzucony tam kiedys przez uzytkownika nie podnosil falszywego alarmu.
$script:RozszerzeniaPamieci = @(".md", ".txt", ".tsv", ".json", ".jsonl", "")

# Jedno polecenie, ktore przywraca wyzerowane pliki z najnowszej zdrowej kopii dziennej.
function Polecenie-Przywrocenia([string]$zrodlo) {
  if (-not $zrodlo) { $zrodlo = Split-Path -Parent $PSScriptRoot }
  return "powershell -ExecutionPolicy Bypass -File `"$zrodlo\narzedzia\kopie-dzienne.ps1`" -Przywroc"
}

# Pozycja pierwszego bajtu 0x00 w pliku: -1 = zdrowy, $null = pliku nie ma albo nie da sie go
# przeczytac. IndexOf jest natywny - liczymy zera dopiero, gdy jakies sa (rzadko).
function Pierwsze-Zero([string]$sciezka) {
  if (-not (Test-Path -LiteralPath $sciezka -PathType Leaf)) { return $null }
  try { $b = [System.IO.File]::ReadAllBytes($sciezka) } catch { return $null }
  return [Array]::IndexOf($b, [byte]0)
}

function Ma-Zera([string]$sciezka) {
  $i = Pierwsze-Zero $sciezka
  return (($null -ne $i) -and ($i -ge 0))
}

# Zapis bajtow: plik tymczasowy obok, WriteThrough + Flush(true), potem podmiana.
function Zapisz-Bajty-Trwale([string]$sciezka, [byte[]]$bajty) {
  if ([Array]::IndexOf($bajty, [byte]0) -ge 0) { throw "odmawiam zapisu bajtow 0x00 do $sciezka" }
  $katalog = Split-Path -Parent $sciezka
  if ($katalog -and -not (Test-Path -LiteralPath $katalog)) { New-Item -ItemType Directory -Force -Path $katalog | Out-Null }
  $tmp = Join-Path $katalog (".{0}.tmp-{1}" -f (Split-Path -Leaf $sciezka), $PID)
  $fs = New-Object System.IO.FileStream($tmp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write,
          [System.IO.FileShare]::None, 4096, [System.IO.FileOptions]::WriteThrough)
  try { $fs.Write($bajty, 0, $bajty.Length); $fs.Flush($true) } finally { $fs.Dispose() }
  $blad = $null
  for ($i = 0; $i -lt $script:ZapisProb; $i++) {
    try {
      if (Test-Path -LiteralPath $sciezka) { [System.IO.File]::Replace($tmp, $sciezka, [NullString]::Value, $true) }
      else { [System.IO.File]::Move($tmp, $sciezka) }
      $blad = $null
      break
    } catch {
      $blad = $_
      Start-Sleep -Milliseconds $script:ZapisPauzaMs
    }
  }
  if ($blad) {
    try { Remove-Item -LiteralPath $tmp -Force -ErrorAction Stop } catch { Write-Warning "zostal plik tymczasowy ${tmp}: $($_.Exception.Message)" }
    throw "nie udalo sie podmienic ${sciezka}: $($blad.Exception.Message)"
  }
}

# Zapis tekstu - zamiennik [IO.File]::WriteAllText (z ta sama obsluga BOM-u kodowania).
function Zapisz-Trwale([string]$sciezka, [string]$tekst, $kodowanie = $null) {
  if ($null -eq $kodowanie) { $kodowanie = New-Object System.Text.UTF8Encoding($false) }
  if ($tekst.IndexOf([char]0) -ge 0) { throw "odmawiam zapisu bajtow 0x00 do $sciezka" }
  $bajty = [byte[]]($kodowanie.GetPreamble() + $kodowanie.GetBytes($tekst))
  Zapisz-Bajty-Trwale $sciezka $bajty
}

# Kopia zapasowa, ktora naprawde jest na dysku - i nigdy kopia zer. Wyzerowany plik zrodlowy
# to wyjatek: kopia zer nadpisalaby moze ostatnia zdrowa kopie o tej samej nazwie.
function Kopiuj-Trwale([string]$skad, [string]$dokad) {
  $b = [System.IO.File]::ReadAllBytes($skad)
  if ([Array]::IndexOf($b, [byte]0) -ge 0) { throw "$skad ma bajty 0x00 (wyzerowany zapis) - nie robie z niego kopii" }
  Zapisz-Bajty-Trwale $dokad $b
  try { (Get-Item -LiteralPath $dokad).LastWriteTime = (Get-Item -LiteralPath $skad).LastWriteTime } catch { }   # data w nazwie mowi kiedy; mtime to grzecznosc
}

# Pliki pamieci jednej maszyny: instrukcje narzedzi AI i pliki tekstowe z wiedza\
# (tylko z wierzchu - kopie\ to juz kopie). Sciezki, ktorych nie ma, pomijamy.
function Pliki-Pamieci([string]$dom) {
  $lista = @()
  foreach ($w in @(".claude\CLAUDE.md", ".codex\AGENTS.md", ".config\opencode\AGENTS.md")) {
    $p = Join-Path $dom $w
    if (Test-Path -LiteralPath $p -PathType Leaf) { $lista += $p }
  }
  $wiedza = Join-Path $dom ".claude\wiedza"
  if (Test-Path -LiteralPath $wiedza) {
    foreach ($f in @(Get-ChildItem -LiteralPath $wiedza -File -Force | Sort-Object Name)) {
      if ($f.Name -like "*.tmp-*") { continue }
      if (($script:RozszerzeniaPamieci -contains $f.Extension.ToLower()) -or $f.Name.StartsWith(".")) { $lista += $f.FullName }
    }
  }
  return ,$lista
}

# Wszystkie wyzerowane pliki pamieci: Sciezka, Zera, Rozmiar.
function Wyzerowane-Pliki([string]$dom) {
  $wynik = @()
  foreach ($p in (Pliki-Pamieci $dom)) {
    if (-not (Ma-Zera $p)) { continue }
    $b = [System.IO.File]::ReadAllBytes($p)
    $zer = 0
    foreach ($x in $b) { if ($x -eq 0) { $zer++ } }
    $wynik += [pscustomobject]@{ Sciezka = $p; Zera = $zer; Rozmiar = $b.Length }
  }
  return ,$wynik
}

function Sciezka-Wzgledna([string]$dom, [string]$sciezka) {
  $d = (Resolve-Path -LiteralPath $dom).Path.TrimEnd('\')
  if ($sciezka.StartsWith($d + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return $sciezka.Substring($d.Length + 1) }
  return $null
}

# Najnowsza kopia pliku bez ani jednego zera: najpierw kopie dzienne, potem kopie .bak-*
# i .przed-* obok pliku oraz wiedza\kopie\<nazwa>-*. $null, gdy zdrowej nie ma.
function Zdrowa-Kopia([string]$plik, [string]$dom) {
  $kandydaci = @()
  $wzgl = Sciezka-Wzgledna $dom $plik
  if ($wzgl) {
    foreach ($slot in @("wczoraj", "przedwczoraj")) { $kandydaci += (Join-Path $dom ".claude\mr\kopie-dzienne\$slot\$wzgl") }
  }
  $katalog = Split-Path -Parent $plik
  $nazwa = Split-Path -Leaf $plik
  $obok = @(Get-ChildItem -LiteralPath $katalog -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "$nazwa.bak-*" -or $_.Name -like "$nazwa.przed-*" })
  $kopie = Join-Path $dom ".claude\wiedza\kopie"
  if (Test-Path -LiteralPath $kopie) {
    $rdzen = [System.IO.Path]::GetFileNameWithoutExtension($nazwa)
    $obok += @(Get-ChildItem -LiteralPath $kopie -File -Filter "$rdzen-*" -ErrorAction SilentlyContinue)
  }
  $kandydaci += @($obok | Sort-Object LastWriteTime -Descending | ForEach-Object { $_.FullName })
  foreach ($k in $kandydaci) {
    $i = Pierwsze-Zero $k
    if (($null -ne $i) -and ($i -lt 0) -and ((Get-Item -LiteralPath $k).Length -gt 0)) { return $k }
  }
  return $null
}

# Jedno zdanie alarmu: co jest wyzerowane, skad przywrocic i jakim poleceniem.
function Opis-Wyzerowanych($lista, [string]$dom, [string]$zrodlo) {
  $czesci = @()
  foreach ($w in $lista) {
    $kopia = Zdrowa-Kopia $w.Sciezka $dom
    $gdzie = if ($kopia) { "ostatnia zdrowa kopia: $kopia" } else { "zdrowej kopii nie znalazlem" }
    $czesci += "$($w.Sciezka) ($($w.Zera) z $($w.Rozmiar) bajtow to zera; $gdzie)"
  }
  return ("ALARM: wyzerowane pliki pamieci - " + ($czesci -join "; ") +
          ". Nic na nich nie buduje i nie robie z nich kopii. Przywrocenie: " + (Polecenie-Przywrocenia $zrodlo))
}
