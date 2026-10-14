# Test wdrozenia serwera "Wiedza firmy" (narzedzia\serwer-wiedzy). Niewidoczny: wszystko na
# katalogu tymczasowym, atrapy zamiast Harmonogramu i zapory, archiwa kodu robione lokalnie
# (bez sieci), procesy w tle bez okien.
#   powershell -NoProfile -ExecutionPolicy Bypass -File narzedzia\serwer-wiedzy\test-serwer-wiedzy.ps1 [-Python <python.exe>] [-BezNegatywnych]
#
# Przypadki: aktualizacja (uszkodzone archiwum, kod sie nie importuje, awaria po podmianie,
# dane nietkniete, sciezka ".." w archiwum, dane w obszarze podmiany, zamek, brak pyproject),
# kopia (baza w trakcie zapisu, uszkodzona baza zrodlowa, retencja, drugi cel, brak bazy),
# instalator (-Proba, instalacja, drugie uruchomienie, brak pyproject, port 8765),
# odinstalowanie, straznik (znacznik, restart, stary python na porcie, kopia), stan.
# Proby negatywne: kazde zabezpieczenie psute na kopii skryptu (jedna podmiana kotwicy) -
# przypadek, ktory go pilnuje, MUSI wtedy pasc.
param(
  [string]$Python = '',
  [switch]$BezNegatywnych
)
$ErrorActionPreference = 'Stop'
$Tu = $PSScriptRoot
$Repo = Split-Path -Parent (Split-Path -Parent $Tu)
if (-not $Python) {
  $kand = @((Join-Path $Repo 'lore\.venv\Scripts\python.exe')) +
          @(Get-ChildItem "$env:APPDATA\uv\python\cpython-3.1[2-9]*\python.exe" -ErrorAction SilentlyContinue | ForEach-Object FullName)
  $Python = $kand | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $Python) { throw 'Brak Pythona 3.12+ (parametr -Python)' }
$Tmp = Join-Path ([IO.Path]::GetTempPath()) ('test-serwer-wiedzy-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
$Pomoc = Join-Path $Tmp '_pomoc'   # skrypty testu - osobno od danych testowych
New-Item -ItemType Directory -Force -Path $Pomoc | Out-Null
$wyniki = New-Object System.Collections.ArrayList
function Wynik($nazwa, $ok, $opis) {
  [void]$wyniki.Add([pscustomobject]@{ Test = $nazwa; OK = [bool]$ok; Opis = $opis })
  $z = if ($ok) { 'TAK' } else { 'NIE' }
  Write-Host ("[{0}] {1} - {2}" -f $z, $nazwa, $opis)
}
function Ocena($nazwa, [string[]]$usterki, [string]$opisOk) {
  $u = @($usterki | Where-Object { $_ })
  Wynik $nazwa ($u.Count -eq 0) $(if ($u.Count) { $u -join ' | ' } else { $opisOk })
}

# --- narzedzia pomocnicze -----------------------------------------------------
function Py([string[]]$a, [hashtable]$zmienne = @{}) {
  $stare = @{}
  foreach ($k in $zmienne.Keys) { $stare[$k] = [Environment]::GetEnvironmentVariable($k, 'Process'); [Environment]::SetEnvironmentVariable($k, $zmienne[$k], 'Process') }
  $e = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $wy = @(& $Python @a 2>&1 | ForEach-Object { "$_" }); $kod = $LASTEXITCODE }
  finally {
    $ErrorActionPreference = $e
    foreach ($k in $zmienne.Keys) { [Environment]::SetEnvironmentVariable($k, $stare[$k], 'Process') }
  }
  return [pscustomobject]@{ Kod = $kod; Tekst = ($wy -join "`n") }
}
function Wolaj-Ps([string]$skrypt, [string[]]$a) {
  $e = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $wy = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $skrypt @a 2>&1 | ForEach-Object { "$_" }); $kod = $LASTEXITCODE }
  finally { $ErrorActionPreference = $e }
  return [pscustomobject]@{ Kod = $kod; Tekst = ($wy -join "`n") }
}
function Czytaj-Json([string]$p) { if (Test-Path -LiteralPath $p) { Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json } }
# Odcisk drzewa: sciezka wzgledna + SHA-256 + czas zapisu kazdego pliku.
function Odcisk([string]$kat) {
  if (-not (Test-Path -LiteralPath $kat)) { return '(brak)' }
  $baza = (Resolve-Path -LiteralPath $kat).Path
  (Get-ChildItem -LiteralPath $kat -Recurse -File -Force | Where-Object { $_.FullName -notmatch '\\__pycache__\\' } | Sort-Object FullName | ForEach-Object {
    "{0}|{1}|{2}" -f $_.FullName.Substring($baza.Length), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash, $_.LastWriteTimeUtc.Ticks
  }) -join "`n"
}
function Wersja-Kodu([string]$kat) {
  $p = Join-Path $kat 'kod\wiedza_firmy\wiedza_firmy\__init__.py'
  if (Test-Path -LiteralPath $p) { ((Get-Content -LiteralPath $p -Raw) -replace '[^v0-9]', '') } else { '(brak)' }
}
function Nowy-Kat([string]$nazwa) { $k = Join-Path $Tmp $nazwa; New-Item -ItemType Directory -Force -Path $k | Out-Null; return $k }

# Kopia skryptow (caly katalog) z jedna podmiana kotwicy - do prob negatywnych.
$script:nrSab = 0
function Sabotaz([string]$plik, [string]$kotwica, [string]$zamiana) {
  $script:nrSab++
  $kat = Join-Path $Tmp ("sab{0}\narzedzia" -f $script:nrSab)
  New-Item -ItemType Directory -Force -Path $kat | Out-Null
  Get-ChildItem -LiteralPath $Tu -File | Where-Object { $_.Name -ne 'test-serwer-wiedzy.ps1' } | Copy-Item -Destination $kat
  $p = Join-Path $kat $plik
  $t = [IO.File]::ReadAllText($p)
  $ile = ([regex]::Matches($t, [regex]::Escape($kotwica))).Count
  if ($ile -ne 1) { throw "kotwica sabotazu w $plik wystepuje $ile razy: $kotwica" }
  [IO.File]::WriteAllText($p, $t.Replace($kotwica, $zamiana), (New-Object Text.UTF8Encoding($false)))
  return $kat
}
function Negatywna([string]$nazwa, [string]$plik, [string]$kotwica, [string]$zamiana, [scriptblock]$przypadek) {
  if ($BezNegatywnych) { return }
  try { $kat = Sabotaz $plik $kotwica $zamiana }
  catch { Wynik "negatywna: $nazwa" $false "przygotowanie: $($_.Exception.Message)"; return }
  $u = @()
  try { $u = @(& $przypadek $kat | Where-Object { $_ }) } catch { $u = @("wyjatek: $($_.Exception.Message)") }
  Wynik "negatywna: $nazwa" ($u.Count -gt 0) $(if ($u.Count) { "zlapany: $($u[0])" } else { 'NIE ZLAPANY - przypadek przeszedl z zepsutym zabezpieczeniem' })
}

# --- archiwa kodu (jak zipball GitHuba: jeden katalog glowny) -----------------------
$zipPy = Join-Path $Pomoc 'zrob_zip.py'
[IO.File]::WriteAllText($zipPy, @'
import json, sys, zipfile
spec = json.load(open(sys.argv[1], encoding="utf-8"))
with zipfile.ZipFile(spec["zip"], "w", zipfile.ZIP_DEFLATED) as zf:
    for nazwa, tresc in spec["pliki"].items():
        zf.writestr(spec["root"] + "/" + nazwa, tresc)
    for nazwa, tresc in spec.get("surowe", []):
        zf.writestr(nazwa, tresc)
'@, (New-Object Text.UTF8Encoding($false)))
$Archiwa = Join-Path $Tmp '_archiwa'
New-Item -ItemType Directory -Force -Path $Archiwa | Out-Null
function Zip([string]$nazwa, [string]$wersja, [hashtable]$zmiany = @{}, [object[]]$surowe = @()) {
  $root = "Primo2966-MegaRuchacz-$wersja" + 'abc1234'
  $pliki = [ordered]@{
    'README.md' = 'repo'
    'narzedzia/inne.ps1' = 'nie dla serwera'
    'wiedza_firmy/pyproject.toml' = "[project]`nname = `"wiedza-firmy`"`nversion = `"0`"`ndependencies = []`n"
    'wiedza_firmy/wiedza_firmy/__init__.py' = "WERSJA = `"$wersja`"`n"
    'wiedza_firmy/wiedza_firmy/serwer.py' = "print('serwer')`n"
    'lore/pyproject.toml' = "[project]`nname = `"lore`"`nversion = `"0`"`ndependencies = []`n"
    'lore/lore/__init__.py' = ''
    'lore/lore/db.py' = "X = 1`n"
    'lore/tests/test_x.py' = 'nie dla serwera'
  }
  foreach ($k in $zmiany.Keys) { if ($null -eq $zmiany[$k]) { $pliki.Remove($k) } else { $pliki[$k] = $zmiany[$k] } }
  $cel = Join-Path $Archiwa "$nazwa.zip"
  $spec = Join-Path $Pomoc "$nazwa.json"
  [IO.File]::WriteAllText($spec, (@{ zip = $cel; root = $root; pliki = $pliki; surowe = @($surowe) } | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
  $r = Py @($zipPy, $spec)
  if ($r.Kod -ne 0) { throw "zip ${nazwa}: $($r.Tekst)" }
  return $cel
}
$zipV1 = Zip 'v1' 'v1'
$zipV2 = Zip 'v2' 'v2'
$zipV3 = Zip 'v3-zepsuty-import' 'v3' @{ 'wiedza_firmy/wiedza_firmy/__init__.py' = "raise RuntimeError('zepsuty kod')`n" }
$zipBezPyproject = Zip 'bez-pyproject' 'v2' @{ 'wiedza_firmy/pyproject.toml' = $null }
$zipPrzejscie = Zip 'przejscie' 'v2' @{} @(, @('Primo2966-MegaRuchacz-v2abc1234/wiedza_firmy/../../../dane/osoby.json', '{"przejete": true}'))
# uszkodzone: uciete (brak katalogu centralnego) i z podmienionymi bajtami danych (zla suma CRC)
$zipUciety = Join-Path $Archiwa 'uciety.zip'
$b = [IO.File]::ReadAllBytes($zipV2); [IO.File]::WriteAllBytes($zipUciety, $b[0..([int]($b.Length * 0.6))])
$zipCrc = Join-Path $Archiwa 'zla-crc.zip'
$b = [IO.File]::ReadAllBytes($zipV2); for ($i = 60; $i -lt 400; $i++) { $b[$i] = $b[$i] -bxor 0x5A }; [IO.File]::WriteAllBytes($zipCrc, $b)

function Dane-Testowe([string]$kat) {
  New-Item -ItemType Directory -Force -Path $kat | Out-Null
  $r = Py @('-c', "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('create table if not exists wpisy(id integer primary key, tresc text)'); c.execute('insert into wpisy(tresc) values (?)', ('ustalenie',)); c.commit()", (Join-Path $kat 'wiedza.db'))
  if ($r.Kod -ne 0) { throw "dane testowe: $($r.Tekst)" }
  [IO.File]::WriteAllText((Join-Path $kat 'tematy.json'), '[{"id": "grafiki", "nazwa": "Grafiki"}]')
  [IO.File]::WriteAllText((Join-Path $kat 'osoby.json'), '{"ela": {"token_sha256": "x", "admin": false}}')
}

# ============================================================================
# AKTUALIZACJA
# ============================================================================
function Akt([string]$skrypty, [string]$kat, [string]$dane, [string]$zip, [hashtable]$zmienne = @{}) {
  return (Py @((Join-Path $skrypty 'aktualizacja.py'), '--kat', $kat, '--dane', $dane, '--zip', $zip) $zmienne)
}
# Instalacja v1 i sprawdzenie, ze sie udala (przygotowanie przypadkow).
function Akt-Start([string]$skrypty, [string]$nazwa) {
  $kat = Nowy-Kat $nazwa
  $dane = Join-Path $Tmp "$nazwa-dane"
  $r = Akt $skrypty $kat $dane $zipV1
  if ($r.Kod -ne 10 -or (Wersja-Kodu $kat) -ne 'v1') { throw "przygotowanie $nazwa`: kod $($r.Kod), wersja $(Wersja-Kodu $kat): $($r.Tekst)" }
  return @{ Kat = $kat; Dane = $dane }
}
function Wspolne-Bledu($kat, $odciskPrzed, $r, [string]$wzor) {
  $s = Czytaj-Json (Join-Path $kat 'stan\aktualizacja.json')
  $log = Get-Content -LiteralPath (Join-Path $kat 'stan\aktualizacja.log') -Tail 1 -ErrorAction SilentlyContinue
  if ($r.Kod -ne 1) { "kod wyjscia $($r.Kod) zamiast 1" }
  if ((Odcisk (Join-Path $kat 'kod')) -ne $odciskPrzed) { "kod serwera ZMIENIONY (wersja $(Wersja-Kodu $kat))" }
  if (-not $s -or $s.status -ne 'blad') { "stan nie mowi o bledzie: $($s.status)" }
  elseif ($s.przyczyna -notmatch $wzor) { "przyczyna bez '$wzor': $($s.przyczyna)" }
  if ($s -and -not $s.ostatni_sukces) { 'zgubiony ostatni sukces' }
  if ("$log" -notmatch '^\S+ BLAD: ') { "dziennik bez linii BLAD: $log" }
  $resztki = @(Get-ChildItem -LiteralPath $kat -Force | Where-Object { $_.Name -like '.kod-*' -or $_.Name -like '.aktualizacja*' })
  if ($resztki.Count) { "resztki: $($resztki.Name -join ', ')" }
}

# (a) uszkodzone archiwum: stary kod zostaje, blad widoczny w stanie i dzienniku
$przypadekUszkodzony = {
  param($skrypty)
  $u = Akt-Start $skrypty ("a-uszk-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  $przed = Odcisk (Join-Path $u.Kat 'kod')
  Wspolne-Bledu $u.Kat $przed (Akt $skrypty $u.Kat $u.Dane $zipUciety) 'uszkodzone archiwum'
  Wspolne-Bledu $u.Kat $przed (Akt $skrypty $u.Kat $u.Dane $zipCrc) 'uszkodzone archiwum'
}
Ocena '(a) uszkodzone archiwum (uciete i zla CRC): stary kod + widoczny blad' (& $przypadekUszkodzony $Tu) 'kod v1 nietkniety, stan blad, linia BLAD w dzienniku, bez resztek'

$przypadekImport = {
  param($skrypty)
  $u = Akt-Start $skrypty ("a-imp-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  Wspolne-Bledu $u.Kat (Odcisk (Join-Path $u.Kat 'kod')) (Akt $skrypty $u.Kat $u.Dane $zipV3) 'nie importuje'
  # odrzucony PRZED podmiana - nie dopiero cofniety po niej (serwer nie mial okna na zly kod)
  $s = Czytaj-Json (Join-Path $u.Kat 'stan\aktualizacja.json')
  if ($s.przyczyna -match 'przywrocono') { "zly kod wszedl na miejsce i dopiero zostal cofniety: $($s.przyczyna)" }
}
Ocena '(a) nowy kod sie nie importuje: odrzucony przed podmiana' (& $przypadekImport $Tu) 'kod v1 nietkniety, stan blad'

$przypadekCofanie = {
  param($skrypty)
  $u = Akt-Start $skrypty ("a-cof-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  Wspolne-Bledu $u.Kat (Odcisk (Join-Path $u.Kat 'kod')) (Akt $skrypty $u.Kat $u.Dane $zipV2 @{ SERWER_WIEDZY_AWARIA = 'po_podmianie' }) 'przywrocono poprzedni kod'
}
Ocena '(a) awaria po podmianie: powrot do starego kodu' (& $przypadekCofanie $Tu) 'kod v1 wrocil, stan blad'

# (b) aktualizacja nie rusza danych: udana podmiana v1->v2, archiwum z "..", dane w obszarze podmiany
$przypadekDane = {
  param($skrypty)
  $u = Akt-Start $skrypty ("b-dane-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  Dane-Testowe $u.Dane
  $przed = Odcisk $u.Dane
  $r = Akt $skrypty $u.Kat $u.Dane $zipV2
  if ($r.Kod -ne 10 -or (Wersja-Kodu $u.Kat) -ne 'v2') { "v1->v2: kod $($r.Kod), wersja $(Wersja-Kodu $u.Kat): $($r.Tekst)" }
  $obce = @('README.md', 'narzedzia', 'lore\tests') | Where-Object { Test-Path -LiteralPath (Join-Path $u.Kat "kod\$_") }
  if ($obce) { "w kod\ trafilo spoza zakresu: $($obce -join ', ')" }
  if (-not (Test-Path -LiteralPath (Join-Path $u.Kat 'kod\lore\pyproject.toml'))) { 'brak kod\lore\pyproject.toml' }
  # archiwum z wpisem wychodzacym poza katalog (celuje w osoby.json danych)
  $przedKod = Odcisk (Join-Path $u.Kat 'kod')
  $r2 = Akt $skrypty $u.Kat $u.Dane $zipPrzejscie
  if ($r2.Kod -ne 1) { "archiwum z '..' przyjete (kod $($r2.Kod))" }
  if ((Odcisk (Join-Path $u.Kat 'kod')) -ne $przedKod) { "archiwum z '..' zmienilo kod" }
  if ((Odcisk $u.Dane) -ne $przed) { 'DANE ZMIENIONE' }
  # ponowne v2 = "aktualna": dane dalej nietkniete
  $r3 = Akt $skrypty $u.Kat $u.Dane $zipV2
  if ($r3.Kod -ne 0) { "ponowne v2: kod $($r3.Kod) zamiast 0 (aktualna)" }
  if ((Odcisk $u.Dane) -ne $przed) { 'DANE ZMIENIONE po "aktualna"' }
}
Ocena '(b) aktualizacja nie rusza danych (podmiana, archiwum z "..", aktualna)' (& $przypadekDane $Tu) 'odcisk danych (sumy + czasy) identyczny; w kod\ tylko wiedza_firmy\ i lore\lore\'

$przypadekDaneWKodzie = {
  param($skrypty)
  $u = Akt-Start $skrypty ("b-wk-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  $daneWKodzie = Join-Path $u.Kat 'kod\wiedza_firmy\dane'
  Dane-Testowe $daneWKodzie
  $przed = Odcisk $daneWKodzie
  $r = Akt $skrypty $u.Kat $daneWKodzie $zipV2
  if ($r.Kod -ne 1) { "kod wyjscia $($r.Kod) zamiast 1 (odmowa)" }
  if ((Odcisk $daneWKodzie) -ne $przed) { "DANE ZNISZCZONE (odcisk: $((Odcisk $daneWKodzie).Length) zn.)" }
  $s = Czytaj-Json (Join-Path $u.Kat 'stan\aktualizacja.json')
  if ($s.przyczyna -notmatch 'obszarze podmiany') { "brak widocznej odmowy: $($s.przyczyna)" }
}
Ocena '(b) dane w obszarze podmiany: odmowa' (& $przypadekDaneWKodzie $Tu) 'aktualizacja odmawia, dane zostaja'

$przypadekZamek = {
  param($skrypty)
  $u = Akt-Start $skrypty ("zamek-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  $z = Join-Path $u.Kat '.aktualizacja.lock'
  Set-Content -LiteralPath $z -Value 'inny przebieg'
  $r = Akt $skrypty $u.Kat $u.Dane $zipV2
  if ($r.Kod -ne 3) { "swiezy zamek: kod $($r.Kod) zamiast 3" }
  if ((Wersja-Kodu $u.Kat) -ne 'v1') { 'kod podmieniony mimo zamka' }
  if (-not (Test-Path -LiteralPath $z)) { 'cudzy zamek usuniety'; return }
  if ((Get-Content -LiteralPath (Join-Path $u.Kat 'stan\aktualizacja.log') -Tail 1) -notmatch 'ZAMEK_ZAJETY') { 'zamek bez wpisu w dzienniku' }
  (Get-Item -LiteralPath $z).LastWriteTime = (Get-Date).AddHours(-1)
  $r = Akt $skrypty $u.Kat $u.Dane $zipV2
  if ($r.Kod -ne 10 -or (Wersja-Kodu $u.Kat) -ne 'v2') { "porzucony zamek nie przejety: kod $($r.Kod)" }
}
Ocena 'zamek: swiezy blokuje, porzucony przejety' (& $przypadekZamek $Tu) 'kod 3 i v1 zostaje; po godzinie przejety, v2'

$przypadekPyproject = {
  param($skrypty)
  $kat = Nowy-Kat ("pp-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  $r = Akt $skrypty $kat (Join-Path $kat '..\pp-dane') $zipBezPyproject
  if ($r.Kod -ne 1) { "kod wyjscia $($r.Kod) zamiast 1" }
  if (Test-Path -LiteralPath (Join-Path $kat 'kod')) { 'kod bez pyproject zainstalowany' }
  if ($r.Tekst -notmatch 'wiedza_firmy/pyproject.toml') { "komunikat bez nazwy pliku: $($r.Tekst)" }
}
Ocena 'archiwum bez wiedza_firmy\pyproject.toml: czytelny blad' (& $przypadekPyproject $Tu) 'odmowa z nazwa brakujacego pliku'

if (-not $BezNegatywnych) {
  Negatywna 'blad bez zapisu w stanie i dzienniku' 'aktualizacja.py' `
    '    except BladAktualizacji as exc:
        odnotuj(kat, "blad", str(exc), kod_zmieniony=False)' `
    '    except BladAktualizacji as exc:
        pass' $przypadekUszkodzony
  Negatywna 'podmiana bez sprawdzenia importu' 'aktualizacja.py' '        sprawdz_kod(kat, nowy, modul)' '        pass' $przypadekImport
  Negatywna 'brak cofania po nieudanej podmianie' 'aktualizacja.py' '            cofnij(kod, stary, nowy, byl)' '            pass' $przypadekCofanie
  Negatywna 'brak kontroli sciezek ".." w archiwum' 'aktualizacja.py' `
    'if n.startswith(("/", "\\")) or ":" in n or ".." in czesci:' 'if False:' $przypadekDane
  Negatywna 'brak odmowy dla danych w obszarze podmiany' 'aktualizacja.py' `
    'if wewnatrz(dane, kod) or wewnatrz(kod, dane) or wewnatrz(kat, dane):' 'if False:' $przypadekDaneWKodzie
  Negatywna 'zamek ignorowany' 'aktualizacja.py' '    if not zamek(kat):' '    if not (zamek(kat) or True):' $przypadekZamek
  Negatywna 'brak kontroli wymaganych plikow' 'aktualizacja.py' '    if brak:
        raise' '    if False:
        raise' $przypadekPyproject
}

# ============================================================================
# KOPIA ZAPASOWA
# ============================================================================
$pisarzPy = Join-Path $Pomoc 'pisarz.py'
[IO.File]::WriteAllText($pisarzPy, @'
# Pisarz udajacy serwer: duze transakcje z malym cache (strony trafiaja do pliku bazy PRZED
# zatwierdzeniem), kazda trzyma blokade ~1,5 s. Niezmiennik: licznik.suma == count(wpisy).
import os, sqlite3, sys, time
db, flaga, sek = sys.argv[1], sys.argv[2], float(sys.argv[3])
con = sqlite3.connect(db, timeout=120, isolation_level=None)
con.execute("PRAGMA cache_size=20")
con.execute("CREATE TABLE IF NOT EXISTS wpisy(id INTEGER PRIMARY KEY, partia INT, tresc BLOB)")
con.execute("CREATE TABLE IF NOT EXISTS licznik(id INTEGER PRIMARY KEY, suma INT)")
con.execute("INSERT OR IGNORE INTO licznik VALUES(1, 0)")
koniec = time.time() + sek
partia = 0
while time.time() < koniec:
    partia += 1
    con.execute("BEGIN IMMEDIATE")
    con.execute("DELETE FROM wpisy WHERE partia < ?", (partia - 1,))
    con.executemany("INSERT INTO wpisy(partia, tresc) VALUES(?, ?)", [(partia, os.urandom(6000)) for _ in range(800)])
    con.execute("UPDATE licznik SET suma=(SELECT count(*) FROM wpisy) WHERE id=1")
    with open(flaga, "w") as f:
        f.write(str(partia))
    time.sleep(1.5)
    con.execute("COMMIT")
    time.sleep(0.1)
'@, (New-Object Text.UTF8Encoding($false)))
$sprawdzBazePy = Join-Path $Pomoc 'sprawdz_baze.py'
[IO.File]::WriteAllText($sprawdzBazePy, @'
import sqlite3, sys
try:
    c = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
    ic = [r[0] for r in c.execute("PRAGMA integrity_check")]
    n = c.execute("SELECT count(*) FROM wpisy").fetchone()[0]
    s = c.execute("SELECT suma FROM licznik").fetchone()[0]
    print(f"integrity={ic[0][:80]} wpisy={n} licznik={s}")
    sys.exit(0 if ic == ["ok"] and n == s and n > 0 else 1)
except Exception as e:
    print(f"nie otwiera sie: {e}")
    sys.exit(1)
'@, (New-Object Text.UTF8Encoding($false)))

function Kopia([string]$skrypty, [string]$kat, [string]$dane, [string[]]$dodatkowe = @()) {
  return (Py (@((Join-Path $skrypty 'kopia.py'), '--kat', $kat, '--dane', $dane) + $dodatkowe))
}

# (c) kopia bazy w trakcie zapisu daje plik, ktory sie otwiera i jest spojny
$przypadekWTrakcie = {
  param($skrypty)
  $kat = Nowy-Kat ("c-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  $dane = Join-Path $kat 'dane'; New-Item -ItemType Directory -Force -Path $dane | Out-Null
  [IO.File]::WriteAllText((Join-Path $dane 'tematy.json'), '[{"id": "grafiki"}]')
  [IO.File]::WriteAllText((Join-Path $dane 'osoby.json'), '{"ela": {}}')
  $flaga = Join-Path $kat 'flaga'
  $pis = Start-Process -FilePath $Python -ArgumentList @("`"$pisarzPy`"", "`"$(Join-Path $dane 'wiedza.db')`"", "`"$flaga`"", '9') -WindowStyle Hidden -PassThru
  try {
    # czekamy, az za nami beda >= 2 zatwierdzone partie i trwa kolejna transakcja
    $do = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $do -and -not ((Test-Path -LiteralPath $flaga) -and ([int]("0" + (Get-Content -LiteralPath $flaga -Raw -ErrorAction SilentlyContinue)) -ge 3))) { Start-Sleep -Milliseconds 50 }
    if ((Get-Date) -ge $do) { return 'pisarz nie ruszyl' }
    Start-Sleep -Milliseconds 200
    $r = Kopia $skrypty $kat $dane
  } finally { if (-not $pis.HasExited) { Stop-Process -Id $pis.Id -Force -ErrorAction SilentlyContinue } }
  $s = Czytaj-Json (Join-Path $kat 'stan\kopia.json')
  if ($r.Kod -ne 0 -or $s.status -ne 'ok') { "kopia: kod $($r.Kod), status $($s.status): $($s.przyczyna)" ; return }
  $kb = Join-Path $s.katalog 'wiedza.db'
  $sb = Py @($sprawdzBazePy, $kb)
  if ($sb.Kod -ne 0) { "kopia bazy niespojna: $($sb.Tekst)" }
  foreach ($j in 'tematy.json', 'osoby.json') {
    if ((Get-FileHash (Join-Path $dane $j)).Hash -ne (Get-FileHash (Join-Path $s.katalog $j) -ErrorAction SilentlyContinue).Hash) { "$j nie skopiowany wiernie" }
  }
  if (-not (Test-Path -LiteralPath (Join-Path $s.katalog 'kopia.json'))) { 'brak kopia.json (sumy)' }
  $script:opisC = $sb.Tekst
}
$u = @(& $przypadekWTrakcie $Tu)
Ocena '(c) kopia bazy w trakcie zapisu: plik sie otwiera i jest spojny' $u "integrity_check ok, niezmiennik trzyma: $script:opisC; JSON-y wierne"

$przypadekZepsutaBaza = {
  param($skrypty)
  $kat = Nowy-Kat ("cz-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  $dane = Join-Path $kat 'dane'; New-Item -ItemType Directory -Force -Path $dane | Out-Null
  $db = Join-Path $dane 'wiedza.db'
  $r = Py @('-c', "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]); c.execute('create table wpisy(id integer primary key, tresc text)'); c.executemany('insert into wpisy(tresc) values(?)', [('x'*300,) for _ in range(200)]); c.commit()", $db)
  $b = [IO.File]::ReadAllBytes($db); for ($i = 4096 * 3 + 50; $i -lt 4096 * 3 + 1500; $i++) { $b[$i] = 0xFF }; [IO.File]::WriteAllBytes($db, $b)
  $r = Kopia $skrypty $kat $dane
  $s = Czytaj-Json (Join-Path $kat 'stan\kopia.json')
  if ($r.Kod -ne 1 -or $s.status -ne 'blad') { "uszkodzona baza zrodlowa przyjeta: kod $($r.Kod), status $($s.status)" }
  elseif ($s.przyczyna -notmatch 'integrity_check|nie otwiera') { "przyczyna nieczytelna: $($s.przyczyna)" }
  if (@(Get-ChildItem -LiteralPath (Join-Path $kat 'kopie') -Directory -Force -ErrorAction SilentlyContinue).Count) { 'zla kopia zostawiona jak gotowa' }
}
Ocena 'kopia: uszkodzona baza zrodlowa = blad, nie "ok"' (& $przypadekZepsutaBaza $Tu) 'integrity_check kopii lapie uszkodzenie, katalog roboczy usuniety'

$przypadekRetencja = {
  param($skrypty)
  $kat = Nowy-Kat ("cr-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  $dane = Join-Path $kat 'dane'; Dane-Testowe $dane
  $kopie = Join-Path $kat 'kopie'
  $stara = Join-Path $kopie '2020-01-01_030000'
  $swieza = Join-Path $kopie ((Get-Date).AddDays(-2).ToString('yyyy-MM-dd') + '_030000')
  $graniczna = Join-Path $kopie ((Get-Date).AddDays(-13).ToString('yyyy-MM-dd') + '_030000')
  $obca = Join-Path $kopie 'notatki-2020'
  foreach ($k in $stara, $swieza, $graniczna, $obca) { New-Item -ItemType Directory -Force -Path $k | Out-Null; Set-Content -LiteralPath (Join-Path $k 'x.txt') -Value 'x' }
  Set-Content -LiteralPath (Join-Path $kopie '2020-01-01_030000.txt') -Value 'plik, nie kopia'
  $r = Kopia $skrypty $kat $dane
  if ($r.Kod -ne 0) { "kopia: kod $($r.Kod): $($r.Tekst)" }
  if (Test-Path -LiteralPath $stara) { 'kopia sprzed 14 dni nie usunieta' }
  foreach ($k in $swieza, $graniczna, $obca, (Join-Path $kopie '2020-01-01_030000.txt')) { if (-not (Test-Path -LiteralPath $k)) { "usuniete, a mialo zostac: $(Split-Path -Leaf $k)" } }
}
Ocena 'kopia: 14 dni, rusza tylko katalogi kopii' (& $przypadekRetencja $Tu) 'stara usunieta; 2 i 13 dni, obcy katalog i plik zostaja'

$przypadekDrugiCel = {
  param($skrypty)
  $kat = Nowy-Kat ("cd-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  $dane = Join-Path $kat 'dane'; Dane-Testowe $dane
  $r = Kopia $skrypty $kat $dane @('--drugi-cel', (Join-Path $kat 'G-nie-ma\Moj dysk'))
  $s = Czytaj-Json (Join-Path $kat 'stan\kopia.json')
  if ($r.Kod -ne 2 -or $s.status -ne 'czesciowo' -or $s.przyczyna -notmatch 'drugi cel') { "brak drugiego celu niewidoczny: kod $($r.Kod), $($s.status): $($s.przyczyna)" }
  if (-not (Test-Path -LiteralPath (Join-Path $s.katalog 'wiedza.db'))) { 'lokalna kopia nie powstala' }
  $drugi = Join-Path $kat 'G\kopie'; New-Item -ItemType Directory -Force -Path $drugi | Out-Null
  Start-Sleep -Seconds 1   # inna nazwa katalogu (sekundy w nazwie)
  $r = Kopia $skrypty $kat $dane @('--drugi-cel', $drugi)
  $s = Czytaj-Json (Join-Path $kat 'stan\kopia.json')
  if ($r.Kod -ne 0 -or $s.drugi_cel -ne 'ok' -or -not (Test-Path -LiteralPath (Join-Path $drugi ((Split-Path -Leaf $s.katalog) + '\wiedza.db')))) { "drugi cel nie dostal kopii: kod $($r.Kod), $($s.status)" }
}
Ocena 'kopia: drugi cel (Dysk Google) - brak = "czesciowo", jest = kopia tam' (& $przypadekDrugiCel $Tu) 'niedostepny drugi cel widoczny, dostepny dostaje kopie'

$przypadekBrakBazy = {
  param($skrypty)
  $kat = Nowy-Kat ("cb-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  $dane = Join-Path $kat 'dane'; New-Item -ItemType Directory -Force -Path $dane | Out-Null
  [IO.File]::WriteAllText((Join-Path $dane 'tematy.json'), '[]')
  $r = Kopia $skrypty $kat $dane
  $s = Czytaj-Json (Join-Path $kat 'stan\kopia.json')
  if ($r.Kod -ne 1 -or $s.status -ne 'blad') { "brak bazy przemilczany: kod $($r.Kod), $($s.status)" }
  if ((Get-Content -LiteralPath (Join-Path $kat 'stan\kopia.log') -Tail 1 -ErrorAction SilentlyContinue) -notmatch ' BLAD: ') { 'brak linii BLAD w kopia.log' }
}
Ocena 'kopia: brak bazy = widoczny blad' (& $przypadekBrakBazy $Tu) 'stan blad + linia BLAD'

if (-not $BezNegatywnych) {
  Negatywna 'kopiowanie pliku w locie zamiast API kopii SQLite' 'kopia.py' '            src.backup(dst, pages=-1, sleep=0.1)' '            shutil.copyfile(zrodlo, cel)' $przypadekWTrakcie
  Negatywna 'kopia bez integrity_check' 'kopia.py' '    if wynik != ["ok"]:' '    if False:' $przypadekZepsutaBaza
  Negatywna 'retencja bez patrzenia na date' 'kopia.py' '        if m.group(1) < granica:' '        if True:' $przypadekRetencja
  Negatywna 'blad drugiego celu przemilczany' 'kopia.py' '        raise BladKopii(f"drugi cel {drugi} niedostepny (brak dysku/katalogu)")' '        return []' $przypadekDrugiCel
  Negatywna 'blad kopii bez zapisu stanu' 'kopia.py' '    zapisz_stan(kat, stan)
    print(' '    print(' $przypadekBrakBazy
}

# ============================================================================
# INSTALATOR I ODINSTALOWANIE (atrapy zamiast systemu)
# ============================================================================
$atrapy = Join-Path $Pomoc 'atrapy.ps1'
[IO.File]::WriteAllText($atrapy, @'
function Zapisz-Wywolanie([string]$t) { Add-Content -LiteralPath $env:ATRAPY_LOG -Value $t }
function Czy-Admin { $true }
function Kto { 'TEST\uzytkownik' }
function Utworz-Venv { Zapisz-Wywolanie 'venv'; return (Python-Uruchom $PythonBazowy @('-m', 'venv', '--without-pip', (Join-Path $Kat 'venv'))) }
function Instaluj-Zaleznosci { Zapisz-Wywolanie 'zaleznosci'; return [pscustomobject]@{ Kod = 0; Tekst = @('atrapa pip') } }
function Pobierz-Model { Zapisz-Wywolanie 'model'; return [pscustomobject]@{ Kod = 0; Tekst = @('atrapa modelu') } }
function Zaloz-Zapore { Zapisz-Wywolanie "zapora $NazwaReguly $Port $($AdresyZdalne -join ',')" }
function Zaloz-Zadanie([string]$u) { Zapisz-Wywolanie "zadanie $NazwaZadania $u" }
function Stan-Zadania { '' }
function Zatrzymaj-Zadanie { Zapisz-Wywolanie 'stop' }
function Uruchom-Zadanie { Zapisz-Wywolanie 'start' }
function Jest-Zadanie { $true }
function Usun-Zadanie { Zapisz-Wywolanie 'usun-zadanie' }
function Jest-Regula { $true }
function Usun-Regule { Zapisz-Wywolanie 'usun-regule' }
function Procesy-Serwera { @(4242) }
function Zabij([int]$id) { Zapisz-Wywolanie "zabij $id" }
'@, (New-Object Text.UTF8Encoding($false)))

function Instaluj([string]$skrypty, [string]$kat, [string]$dane, [string]$zip, [string[]]$dodatkowe = @()) {
  $env:ATRAPY_LOG = Join-Path (Split-Path -Parent $kat) ((Split-Path -Leaf $kat) + '-atrapy.log')
  return (Wolaj-Ps (Join-Path $skrypty 'instaluj-serwer-wiedzy.ps1') (@('-Kat', $kat, '-Dane', $dane, '-ZrodloKodu', $zip, '-PythonBazowy', $Python, '-Atrapy', $atrapy) + $dodatkowe))
}
function Wywolania([string]$kat) { $p = Join-Path (Split-Path -Parent $kat) ((Split-Path -Leaf $kat) + '-atrapy.log'); if (Test-Path -LiteralPath $p) { @(Get-Content -LiteralPath $p) } else { @() } }

# (d) -Proba niczego nie zmienia: ani na czystym komputerze, ani na gotowej instalacji
$przypadekProba = {
  param($skrypty)
  $baza = Nowy-Kat ("d-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  $kat = Join-Path $baza 'wiedza-firmy'; $dane = Join-Path $baza 'dane'
  $r = Instaluj $skrypty $kat $dane $zipV1 @('-Proba')
  if ($r.Kod -ne 0) { "proba na czysto: kod $($r.Kod): $($r.Tekst)" }
  if (Test-Path -LiteralPath $kat) { "proba na czysto utworzyla $kat" }
  if (Test-Path -LiteralPath $dane) { 'proba utworzyla katalog danych' }
  $w = Wywolania $kat
  if ($w.Count) { "proba na czysto ruszyla system: $($w -join ', ')" }
  if ($r.Tekst -notmatch '\[proba\] zalozylbym zadanie' -or $r.Tekst -notmatch '\[proba\] zalozylbym / odswiezylbym regule') { 'plan bez zadania albo zapory' }
  # gotowa instalacja (prawdziwy przebieg), potem proba - odcisk calego drzewa bez zmian
  $r = Instaluj $Tu $kat $dane $zipV1
  if ($r.Kod -ne 0) { "przygotowanie instalacji: kod $($r.Kod): $($r.Tekst)"; return }
  Remove-Item -LiteralPath (Join-Path $baza 'wiedza-firmy-atrapy.log') -Force
  $przed = Odcisk $kat
  $r = Instaluj $skrypty $kat $dane $zipV2 @('-Proba')
  if ($r.Kod -ne 0) { "proba na instalacji: kod $($r.Kod): $($r.Tekst)" }
  if ((Odcisk $kat) -ne $przed) { 'proba na instalacji ZMIENILA pliki' }
  $w = Wywolania $kat
  if ($w.Count) { "proba na instalacji ruszyla system: $($w -join ', ')" }
}
Ocena '(d) -Proba niczego nie zmienia (czysto i na gotowej instalacji)' (& $przypadekProba $Tu) 'zero plikow, zero wywolan systemowych, plan wypisany'

$przypadekInstalacja = {
  param($skrypty)
  $baza = Nowy-Kat ("i-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  $kat = Join-Path $baza 'wiedza-firmy'; $dane = Join-Path $baza 'dane'
  Dane-Testowe $dane
  $odDane = Odcisk $dane
  $r = Instaluj $skrypty $kat $dane $zipV1
  if ($r.Kod -ne 0) { "instalacja: kod $($r.Kod): $($r.Tekst)"; return }
  $w = Wywolania $kat
  $oczek = @('venv', 'zaleznosci', 'model', 'zapora WiedzaFirmyHttp-TCP 8766 192.168.0.0/24,100.64.0.0/10,127.0.0.1', 'zadanie WiedzaFirmyHttp TEST\uzytkownik', 'start')
  if (($w -join ';') -ne ($oczek -join ';')) { "wywolania: $($w -join ';')" }
  foreach ($p in 'straznik.ps1', 'aktualizacja.py', 'kopia.py', 'uruchom.py', 'stan-serwera-wiedzy.ps1', 'odinstaluj-serwer-wiedzy.ps1', 'instaluj-serwer-wiedzy.ps1', 'CZYTAJ.md') {
    if (-not (Test-Path -LiteralPath (Join-Path $kat "narzedzia\$p"))) { "brak narzedzia\$p" }
  }
  $k = Czytaj-Json (Join-Path $kat 'serwer-wiedzy.json')
  if ($k.port -ne 8766 -or $k.modul -ne 'wiedza_firmy.serwer' -or $k.dane -ne $dane) { "konfiguracja: $($k | ConvertTo-Json -Compress)" }
  if ((Wersja-Kodu $kat) -ne 'v1') { "kod: $(Wersja-Kodu $kat)" }
  foreach ($d in 'stan', 'kopie', 'lore-dane', 'venv\Scripts\python.exe') { if (-not (Test-Path -LiteralPath (Join-Path $kat $d))) { "brak $d" } }
  if ($r.Tekst -match 'Nikt nie ma jeszcze dostepu') { 'osoby.json jest, a instalator mowi, ze nie ma' }
  # drugie uruchomienie: nic nie psuje, venv nie od nowa, kod i konfiguracja te same
  $przed = Odcisk $kat
  $venvCzas = (Get-Item -LiteralPath (Join-Path $kat 'venv\Scripts\python.exe')).LastWriteTimeUtc
  $r = Instaluj $skrypty $kat $dane $zipV1
  if ($r.Kod -ne 0) { "drugie uruchomienie: kod $($r.Kod): $($r.Tekst)" }
  $w2 = @(Wywolania $kat | Select-Object -Skip $w.Count)
  if ($w2 -contains 'venv') { 'drugie uruchomienie zalozylo venv od nowa' }
  if ((Get-Item -LiteralPath (Join-Path $kat 'venv\Scripts\python.exe')).LastWriteTimeUtc -ne $venvCzas) { 'venv ruszony' }
  $roznice = Compare-Object @($przed -split "`n" | Where-Object { $_ -notmatch '^\\stan\\' }) @((Odcisk $kat) -split "`n" | Where-Object { $_ -notmatch '^\\stan\\' })
  $roznice = @($roznice | Where-Object { $_.InputObject -notmatch '^\\(narzedzia\\|serwer-wiedzy\.json)' })
  if ($roznice.Count) { "drugie uruchomienie zmienilo: $(($roznice | Select-Object -First 3 | ForEach-Object InputObject) -join ', ')" }
  $s = Czytaj-Json (Join-Path $kat 'stan\aktualizacja.json')
  if ($s.status -ne 'aktualna') { "drugie uruchomienie: aktualizacja $($s.status)" }
  foreach ($p in 'serwer-wiedzy.json', 'narzedzia\straznik.ps1') {
    $a1 = ($przed -split "`n" | Where-Object { $_ -like "\$p|*" }) -replace '\|\d+$', ''
    $a2 = ((Odcisk $kat) -split "`n" | Where-Object { $_ -like "\$p|*" }) -replace '\|\d+$', ''
    if ($a1 -ne $a2) { "tresc $p zmieniona przy drugim uruchomieniu" }
  }
  if ((Odcisk $dane) -ne $odDane) { 'instalator ZMIENIL dane' }
}
Ocena 'instalacja + drugie uruchomienie (idempotentna)' (& $przypadekInstalacja $Tu) 'kolejnosc wywolan, pliki, konfiguracja; drugi raz: venv i kod bez zmian, dane nietkniete'

$przypadekInstBezPyproject = {
  param($skrypty)
  $baza = Nowy-Kat ("ip-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  $kat = Join-Path $baza 'wiedza-firmy'
  $r = Instaluj $skrypty $kat (Join-Path $baza 'dane') $zipBezPyproject
  if ($r.Kod -ne 1) { "kod $($r.Kod) zamiast 1" }
  if ($r.Tekst -notmatch 'pyproject') { 'komunikat bez slowa pyproject' }
  $w = Wywolania $kat
  if ($w -match '^(zapora|zadanie|start)') { "mimo bledu ruszyl system: $($w -join ', ')" }
  $r = Instaluj $skrypty (Join-Path $baza 'p') (Join-Path $baza 'dane') $zipV1 @('-Port', '8765')
  if ($r.Kod -ne 1 -or $r.Tekst -notmatch '8765') { "port 8765 przyjety: kod $($r.Kod)" }
}
Ocena 'instalator: brak pyproject i port 8765 = czytelny blad' (& $przypadekInstBezPyproject $Tu) 'odmowa przed zapora i zadaniem'

$przypadekOdinstaluj = {
  param($skrypty)
  $baza = Nowy-Kat ("o-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  $kat = Join-Path $baza 'wiedza-firmy'; $dane = Join-Path $baza 'dane'
  Dane-Testowe $dane
  $r = Instaluj $Tu $kat $dane $zipV1
  if ($r.Kod -ne 0) { "przygotowanie: $($r.Tekst)"; return }
  New-Item -ItemType Directory -Force -Path (Join-Path $kat 'kopie\2026-10-14_030000') | Out-Null
  $przedKat = Odcisk $kat; $przedDane = Odcisk $dane
  $env:ATRAPY_LOG = Join-Path $baza 'odinst.log'
  $r = Wolaj-Ps (Join-Path $skrypty 'odinstaluj-serwer-wiedzy.ps1') @('-Kat', $kat, '-Proba', '-Atrapy', $atrapy)
  if ($r.Kod -ne 0 -or (Test-Path -LiteralPath $env:ATRAPY_LOG)) { "-Proba odinstalowania cos zrobila: kod $($r.Kod)" }
  $r = Wolaj-Ps (Join-Path $skrypty 'odinstaluj-serwer-wiedzy.ps1') @('-Kat', $kat, '-Atrapy', $atrapy)
  $w = @(Get-Content -LiteralPath $env:ATRAPY_LOG -ErrorAction SilentlyContinue)
  if ($r.Kod -ne 0 -or (($w -join ';') -ne 'usun-zadanie;zabij 4242;usun-regule')) { "odinstalowanie: kod $($r.Kod), wywolania $($w -join ';')" }
  if ((Odcisk $dane) -ne $przedDane) { 'DANE ZMIENIONE' }
  if ((Odcisk $kat) -ne $przedKat) { 'program albo kopie zmienione' }
}
Ocena 'odinstalowanie: zadanie, proces, zapora - dane i kopie zostaja' (& $przypadekOdinstaluj $Tu) 'trzy wywolania, dane i katalog programu nietkniete'

if (-not $BezNegatywnych) {
  Negatywna '-Proba zakladajaca zapore' 'instaluj-serwer-wiedzy.ps1' 'if ($Proba) { Plan "zalozylbym / odswiezylbym regule $NazwaReguly" }' 'if ($false) { }' $przypadekProba
  Negatywna '-Proba zakladajaca zadanie' 'instaluj-serwer-wiedzy.ps1' 'if ($Proba) { Plan "zalozylbym zadanie:' 'if ($false) { Plan "zalozylbym zadanie:' $przypadekProba
  Negatywna '-Proba tworzaca katalogi i konfiguracje' 'instaluj-serwer-wiedzy.ps1' 'if ($Proba) {
  foreach ($k in $katalogi)' 'if ($false) {
  foreach ($k in $katalogi)' $przypadekProba
  Negatywna '-Proba kopiujaca skrypty' 'instaluj-serwer-wiedzy.ps1' 'elseif ($Proba) { Plan "skopiowalbym:' 'elseif ($false) { Plan "skopiowalbym:' $przypadekProba
  Negatywna 'venv zakladany przy kazdym uruchomieniu' 'instaluj-serwer-wiedzy.ps1' "if (Test-Path -LiteralPath `$PyVenv) { Ok 'venv juz jest - zostawiam' }" "if (`$false) { }" $przypadekInstalacja
  Negatywna 'brak kontroli pyproject (instalator + 2 warstwy aktualizacji)' 'instaluj-serwer-wiedzy.ps1' '  if (-not (Test-Path -LiteralPath $pyproject)) {
    Blad' '  if ($false) {
    Blad' {
      param($skrypty)
      # Zabezpieczenie warstwowe: kontrola w instalatorze (zepsuta kotwica wyzej) i dwie
      # w aktualizacji (wymagane pliki, odczyt zaleznosci). Psujemy wszystkie trzy.
      $p = Join-Path $skrypty 'aktualizacja.py'
      $t = [IO.File]::ReadAllText($p)
      foreach ($para in @(@('WYMAGANE = ("wiedza_firmy/pyproject.toml", "lore/lore/db.py")', 'WYMAGANE = ("lore/lore/db.py",)'),
                          @('        raise BladAktualizacji(f"brak {pp} - nie wiem, jakie zaleznosci instalowac")', '        return []'))) {
        if (([regex]::Matches($t, [regex]::Escape($para[0]))).Count -ne 1) { throw "kotwica: $($para[0])" }
        $t = $t.Replace($para[0], $para[1])
      }
      [IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($false)))
      & $przypadekInstBezPyproject $skrypty
    }
}

# ============================================================================
# STRAZNIK
# ============================================================================
$serwerPy = Join-Path $Pomoc 'atrapa_serwera.py'
[IO.File]::WriteAllText($serwerPy, @'
# Atrapa serwera: slucha na porcie z WIEDZA_FIRMY_PORT, po ~2,5 s czyta znacznik straznika
# (dowod, ze straznik pisze "bylem tu" w trakcie pracy serwera), po 4 s konczy sie kodem 7.
import json, os, socket, sys, time
port = int(os.environ["WIEDZA_FIRMY_PORT"])
s = socket.socket()
try:
    s.bind(("127.0.0.1", port))
except OSError as e:
    print(f"ATRAPA: port {port} zajety: {e}", flush=True)
    sys.exit(5)
s.listen()
print(f"ATRAPA: slucham na {port}", flush=True)
time.sleep(2.5)
try:
    z = json.load(open(os.path.join(os.environ["ZNACZNIK_KAT"], "straznik.json"), encoding="utf-8"))
    print(f"ATRAPA: znacznik faza={z['faza']} port_slucha={z['port_slucha']}", flush=True)
except Exception as e:
    print(f"ATRAPA: brak znacznika: {e}", flush=True)
time.sleep(1.5)
sys.exit(7)
'@, (New-Object Text.UTF8Encoding($false)))
$blokerPy = Join-Path $Pomoc 'stary_serwer.py'
[IO.File]::WriteAllText($blokerPy, @'
import socket, sys, time
s = socket.socket(); s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen()
time.sleep(120)
'@, (New-Object Text.UTF8Encoding($false)))
function Wolny-Port { $l = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0); $l.Start(); $p = $l.LocalEndpoint.Port; $l.Stop(); return $p }

$przypadekStraznik = {
  param($skrypty)
  $kat = Nowy-Kat ("s-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  $nar = Join-Path $kat 'narzedzia'; New-Item -ItemType Directory -Force -Path $nar | Out-Null
  Get-ChildItem -LiteralPath $skrypty -File | Copy-Item -Destination $nar
  $dane = Join-Path $kat 'dane'; Dane-Testowe $dane
  $port = Wolny-Port
  $stary = Start-Process -FilePath $Python -ArgumentList @("`"$blokerPy`"", "$port") -WindowStyle Hidden -PassThru
  Start-Sleep -Milliseconds 800
  $env:ZNACZNIK_KAT = Join-Path $kat 'stan'
  $st = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $nar 'straznik.ps1')`"", '-Kat', "`"$kat`"", '-Port', "$port",
    '-Python', "`"$Python`"", '-Dane', "`"$dane`"", '-CoIleSprawdzacS', '1', '-MaksStartow', '2', '-BezAktualizacji',
    '-GodzinaKopii', '0', '-SerwerArgumenty', "`"$serwerPy`"")
  if (-not $st.WaitForExit(90000)) { & taskkill.exe /pid $st.Id /t /f 2>&1 | Out-Null; 'straznik nie skonczyl w 90 s' }
  $staryZyje = -not $stary.HasExited
  if ($staryZyje) { Stop-Process -Id $stary.Id -Force -ErrorAction SilentlyContinue }
  $log = Get-Content -LiteralPath (Join-Path $kat 'stan\straznik.log') -Raw -ErrorAction SilentlyContinue
  $slog = Get-Content -LiteralPath (Join-Path $kat 'stan\serwer.log') -Raw -ErrorAction SilentlyContinue
  if ($staryZyje -or $log -notmatch "port $port zajety przez stary python") { "stary python na porcie nie zamkniety (zyje: $staryZyje)" }
  if (([regex]::Matches("$log", 'start serwera, pid')).Count -ne 2) { "startow serwera: $(([regex]::Matches("$log", 'start serwera, pid')).Count) zamiast 2" }
  if (([regex]::Matches("$log", 'serwer zakonczony, kod 7')).Count -ne 2) { 'brak wpisow o zakonczeniu z kodem 7' }
  if (([regex]::Matches("$slog", 'ATRAPA: slucham')).Count -ne 2) { "serwer nie wstal 2 razy: $slog" }
  if (([regex]::Matches("$slog", 'ATRAPA: znacznik faza=serwer dziala port_slucha=True')).Count -ne 2) { "znacznik w trakcie pracy serwera nieswiezy/zly: $(([regex]::Matches("$slog", 'ATRAPA: znacznik[^\r\n]*') | ForEach-Object Value) -join ' / ')" }
  $z = Czytaj-Json (Join-Path $kat 'stan\straznik.json')
  if (-not $z -or $z.faza -ne 'koniec (limit startow)' -or $z.startow -ne 2) { "koncowy znacznik: $($z | ConvertTo-Json -Compress)" }
  $k = Czytaj-Json (Join-Path $kat 'stan\kopia.json')
  if (-not $k -or $k.status -ne 'ok' -or "$log" -notmatch 'kopia zapasowa: ok') { "kopia dzienna nie zrobiona przez straznika: $($k.status) $($k.przyczyna)" }
  if (([regex]::Matches("$log", 'kopia zapasowa:')).Count -ne 1) { 'kopia zrobiona wiecej niz raz w ciagu dnia' }
}
Ocena 'straznik: stary python z portu, znacznik "bylem tu", restart, kopia raz dziennie' (& $przypadekStraznik $Tu) 'zamknal stary python, 2 starty, znacznik swiezy w trakcie pracy, kopia ok raz'

if (-not $BezNegatywnych) {
  Negatywna 'straznik bez znacznika w trakcie pracy serwera' 'straznik.ps1' "      Zapisz-Znacznik 'serwer dziala'
      if (Kopia-Potrzebna)" '      if (Kopia-Potrzebna)' $przypadekStraznik
  Negatywna 'straznik bez restartu' 'straznik.ps1' "  Zapisz-Znacznik 'przerwa przed restartem'" "  Zapisz-Znacznik 'koniec (limit startow)'; break" $przypadekStraznik
  Negatywna 'straznik nie zamyka starego pythona' 'straznik.ps1' '    Sprzataj-Port
    Rotuj $LogSerwera' '    Rotuj $LogSerwera' $przypadekStraznik
}

# ============================================================================
# STAN (progi alarmow)
# ============================================================================
$przypadekStan = {
  param($skrypty)
  $kat = Nowy-Kat ("st-" + [guid]::NewGuid().ToString('N').Substring(0, 4))
  $stan = Join-Path $kat 'stan'; New-Item -ItemType Directory -Force -Path $stan | Out-Null
  $t = Get-Date '2026-10-14T12:00:00'
  function Zapisz-Stan($s, $a, $k) {
    foreach ($p in @(@('straznik.json', $s), @('aktualizacja.json', $a), @('kopia.json', $k))) {
      [IO.File]::WriteAllText((Join-Path $stan $p[0]), ($p[1] | ConvertTo-Json))
    }
  }
  $iso = { param($m) $t.AddMinutes(-$m).ToString('yyyy-MM-ddTHH:mm:sszzz') }
  $sOk = @{ czas = (& $iso 0.5); faza = 'serwer dziala'; co_ile_s = 60; startow = 1; port = 8766; port_slucha = $true; serwer_od = (& $iso 600) }
  $aOk = @{ status = 'aktualna'; przyczyna = 'bez zmian'; sha = 'x'; ostatni_sukces = (& $iso 30) }
  $kOk = @{ status = 'ok'; katalog = 'k'; ostatni_sukces = (& $iso 600) }
  $dane = Join-Path $kat 'dane'; New-Item -ItemType Directory -Force -Path $dane | Out-Null
  [IO.File]::WriteAllText((Join-Path $kat 'serwer-wiedzy.json'), (@{ dane = $dane; port = 8766 } | ConvertTo-Json))
  $zyje = Join-Path $dane 'serwer-zyje.json'
  function Zyje($minut, $model, $osoby) {
    [IO.File]::WriteAllText($zyje, (@{ czas = $t.AddMinutes(-$minut).ToString('yyyy-MM-ddTHH:mm:ss'); pid = 1; wersja = '0.1.0'; model = $model; problem_osob = $osoby } | ConvertTo-Json))
  }
  Zyje 1 'gotowy (20 s)' $null
  $skr = Join-Path $skrypty 'stan-serwera-wiedzy.ps1'
  $teraz = $t.ToString('o')
  Zapisz-Stan $sOk $aOk $kOk
  $r = Wolaj-Ps $skr @('-Kat', $kat, '-Teraz', $teraz); if ($r.Kod -ne 0) { "wszystko ok, a kod $($r.Kod): $($r.Tekst)" }
  $s2 = $sOk.Clone(); $s2.czas = (& $iso 6); Zapisz-Stan $s2 $aOk $kOk
  $r = Wolaj-Ps $skr @('-Kat', $kat, '-Teraz', $teraz); if ($r.Kod -ne 1 -or $r.Tekst -notmatch 'straznik milczy') { 'znacznik sprzed 6 min bez alarmu' }
  $s2 = $sOk.Clone(); $s2.czas = (& $iso 4); Zapisz-Stan $s2 $aOk $kOk
  $r = Wolaj-Ps $skr @('-Kat', $kat, '-Teraz', $teraz); if ($r.Kod -ne 0) { 'znacznik sprzed 4 min = falszywy alarm' }
  $a2 = $aOk.Clone(); $a2.status = 'blad'; $a2.przyczyna = 'brak polaczenia'; Zapisz-Stan $sOk $a2 $kOk
  $r = Wolaj-Ps $skr @('-Kat', $kat, '-Teraz', $teraz); if ($r.Kod -ne 0 -or $r.Tekst -notmatch '\[UWAGA\]') { 'pojedynczy blad aktualizacji: zly poziom' }
  $a2.ostatni_sukces = (& $iso (25 * 60)); Zapisz-Stan $sOk $a2 $kOk
  $r = Wolaj-Ps $skr @('-Kat', $kat, '-Teraz', $teraz); if ($r.Kod -ne 1) { 'doba bez udanej aktualizacji bez alarmu' }
  $k2 = $kOk.Clone(); $k2.status = 'blad'; $k2.przyczyna = 'integrity'; Zapisz-Stan $sOk $aOk $k2
  $r = Wolaj-Ps $skr @('-Kat', $kat, '-Teraz', $teraz); if ($r.Kod -ne 1) { 'blad kopii bez alarmu' }
  $k2 = $kOk.Clone(); $k2.ostatni_sukces = (& $iso (27 * 60)); Zapisz-Stan $sOk $aOk $k2
  $r = Wolaj-Ps $skr @('-Kat', $kat, '-Teraz', $teraz); if ($r.Kod -ne 1) { 'kopia sprzed 27 h bez alarmu' }
  $s2 = $sOk.Clone(); $s2.port_slucha = $false; Zapisz-Stan $s2 $aOk $kOk
  $r = Wolaj-Ps $skr @('-Kat', $kat, '-Teraz', $teraz); if ($r.Kod -ne 1) { 'port nie slucha od 10 min bez alarmu' }
  Zapisz-Stan $sOk $aOk $kOk
  Zyje 6 'gotowy (20 s)' $null
  $r = Wolaj-Ps $skr @('-Kat', $kat, '-Teraz', $teraz); if ($r.Kod -ne 1 -or $r.Tekst -notmatch 'znaku zycia') { 'serwer bez znaku zycia od 6 min bez alarmu' }
  Zyje 1 'BLAD: brak sieci' $null
  $r = Wolaj-Ps $skr @('-Kat', $kat, '-Teraz', $teraz); if ($r.Kod -ne 1) { 'model w stanie BLAD bez alarmu' }
  Zyje 1 'laduje' 'osoby.json: zly JSON'
  $r = Wolaj-Ps $skr @('-Kat', $kat, '-Teraz', $teraz); if ($r.Kod -ne 1) { 'problem z osobami bez alarmu' }
  Zyje 1 'laduje' $null
  $r = Wolaj-Ps $skr @('-Kat', $kat, '-Teraz', $teraz); if ($r.Kod -ne 0) { "model w trakcie ladowania = falszywy alarm: $($r.Tekst)" }
}
Ocena 'stan: progi alarmow (bez falszywych)' (& $przypadekStan $Tu) 'cisza straznika 6 min / doba bez aktualizacji / blad kopii / 27 h bez kopii / gluchy port / serwer bez znaku zycia / model BLAD / osoby = ALARM; 4 min, pojedynczy blad, model laduje - nie'
if (-not $BezNegatywnych) {
  Negatywna 'stan bez progu ciszy straznika' 'stan-serwera-wiedzy.ps1' '$w.TotalSeconds -gt $prog' '$false' $przypadekStan
  Negatywna 'stan bez progu zycia serwera' 'stan-serwera-wiedzy.ps1' '$wz.TotalMinutes -gt 5' '$false' $przypadekStan
}

# ----------------------------------------------------------------------------
$zle = @($wyniki | Where-Object { -not $_.OK })
$poz = @($wyniki | Where-Object { $_.Test -notlike 'negatywna:*' })
$neg = @($wyniki | Where-Object { $_.Test -like 'negatywna:*' })
Write-Host ''
Write-Host ("WYNIK: {0}/{1} zaliczonych (przypadki {2}/{3}, negatywne {4}/{5})" -f ($wyniki.Count - $zle.Count), $wyniki.Count,
  @($poz | Where-Object OK).Count, $poz.Count, @($neg | Where-Object OK).Count, $neg.Count)
$zostale = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($Tmp) })
if ($zostale.Count) {
  Write-Host "UWAGA: procesy testu wciaz zyja - zamykam: $($zostale.ProcessId -join ', ')"
  foreach ($p in $zostale) { & taskkill.exe /pid $p.ProcessId /t /f 2>&1 | Out-Null }
}
if (-not $zle.Count) { Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Host "Katalog testu zostaje: $Tmp" }
if ($zle.Count) { exit 1 } else { exit 0 }
