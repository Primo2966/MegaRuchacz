# narzedzia\instalacja\modul-kopia.ps1 - modul "kopia": codzienna kopia zapasowa na wskazany folder
# (narzedzia\kopia-zapasowa.ps1: pelna-RRRR-MM-DD, potem zmiany\RRRR-MM-DD, nic nie jest nadpisywane).
#
# Skad i dokad - z rejestru modulow (~\.claude\mr\instalacja.json, pole "kopia"), dokladnie tak,
# jak czyta je narzedzia\kopia-zapasowa.ps1 (Ustal-Ustawienia, P59d) przy KAZDYM przebiegu:
#     "kopia": { "cel": "D:\\Kopie", "zrodla": ["C:\\dev", "~\\orca"],
#                "wykluczenia": [{ "sciezka": "C:\\dev\\tools\\git", "powod": "...", "katalog": true }] }
#   "~" na poczatku sciezki = katalog domowy. Rejestr z celem, ale BEZ listy zrodel = kopia samych
#   plikow Claude'a i Codeksa (~\.claude, ~\.claude.json, ~\.codex, ~\.config\opencode, ~\.agents).
#   Rejestr bez celu = skrypt kopii konczy sie BLEDEM, wiec modul tez odmawia. Bez rejestru (instalacja
#   sprzed instalatora) skrypt kopii bierze pole "kopia" ustawien tego komputera ~\.claude\mr\lokalne.json,
#   a bez niego szablon narzedzia\kopia-zapasowa-domyslne.json (P67, umowa: stan.ps1 Kopia-Bez-Rejestru).
# Pole wpisuje okno instalatora (wybor folderu), zanim zawola ten skrypt.
#
# Co robi:
#   - sprawdza cel (dysk jest, folder istnieje albo da sie go zalozyc), zrodla (brak na dysku = UWAGA)
#     i wypisuje wykluczenia
#   - zaklada zadanie MegaRuchaczKopia (kopia-zapasowa.ps1 -ZalozZadanie: codziennie, niewidoczne,
#     po wylaczonym komputerze nadrabia) i sprawdza je w Harmonogramie
#   - wlacza modul w rejestrze
# Usun: zdejmuje zadanie. Kopie w folderze docelowym zostaja ZAWSZE, takze z -UsunDane - to Twoja
#   ostatnia deska ratunku i lezy poza katalogiem domowym. -UsunDane usuwa tylko stan kopii
#   w ~\.claude\mr (kopia-stan.txt, kopia-indeks.tsv - nastepna kopia bedzie wtedy pelna).
#
# Uzycie (umowa wyjscia - naglowek wspolne.ps1):
#   powershell -NoProfile -ExecutionPolicy Bypass -File narzedzia\instalacja\modul-kopia.ps1
#     -Akcja Instaluj|Usun|Stan [-KatalogDomowy <kat>] [-Zrodlo <repo>] [-Proba] [-UsunDane]

[CmdletBinding()]
param(
  [string]$Akcja = "",
  [string]$KatalogDomowy = $HOME,
  [string]$Zrodlo = "",
  [switch]$Proba,
  [switch]$UsunDane
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "wspolne.ps1")
if (-not $Zrodlo) { $Zrodlo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$s0 = Start-Modul "kopia" $Akcja ([bool]$Proba) $Zrodlo $KatalogDomowy
$Zrodlo = $s0.Zrodlo; $KatalogDomowy = $s0.KatalogDomowy

$Skrypt      = Join-Path $Zrodlo "narzedzia\kopia-zapasowa.ps1"
$PlikStanu   = Join-Path $KatalogDomowy ".claude\mr\kopia-stan.txt"
$PlikIndeksu = Join-Path $KatalogDomowy ".claude\mr\kopia-indeks.tsv"
# te same korzenie, co $KorzenieClaude w kopia-zapasowa.ps1 (kopia bez listy zrodel)
$KorzenieClaude = @("~\.claude", "~\.claude.json", "~\.codex", "~\.config\opencode", "~\.agents")

# "~" na poczatku = katalog domowy - jak Rozwin-Sciezke w kopia-zapasowa.ps1
function Rozwin([string]$p) {
  $p = "$p".Trim()
  if ($p -match '^~(\\|/|$)') { $p = $KatalogDomowy + $p.Substring(1) }
  return $p.TrimEnd('\')
}

# Ustawienia, jakie wezmie skrypt kopii: Skad, Cel, Zrodla (puste = pliki Claude'a i Codeksa),
# Wykluczenia, Brak (powod, dla ktorego kopia nie ruszy).
function Ustawienia-Kopii($rej) {
  $u = [pscustomobject]@{ Skad = ""; Cel = ""; Zrodla = @(); BezZrodel = $false; Wykluczenia = @(); Brak = "" }
  $k = $null
  if ($rej.zrodlo -eq "plik") {
    $u.Skad = "rejestr modulow ($(Sciezka-Instalacji $KatalogDomowy), pole kopia)"
    if (-not $rej.kopia) { $u.Brak = "w rejestrze nie ma ustawien kopii (pole kopia: cel i zrodla) - wybierz folder w oknie instalatora"; return $u }
    $k = $rej.kopia
  } else {
    try {
      $d = Kopia-Bez-Rejestru $Zrodlo $KatalogDomowy
      $k = $d.Kopia
      $u.Skad = "szablon narzedzia\kopia-zapasowa-domyslne.json (rejestru jeszcze nie ma, a w $(Sciezka-Lokalnych $KatalogDomowy) nie ma pola kopia)"
      if ($d.Lokalne) { $u.Skad = "ustawienia tego komputera $($d.Plik) (rejestru jeszcze nie ma - instalacja sprzed instalatora)" }
    } catch { $u.Skad = "ustawienia kopii bez rejestru"; $u.Brak = "nie umiem odczytac ustawien kopii bez rejestru: $($_.Exception.Message)"; return $u }
  }
  if ($k.cel) { $u.Cel = Rozwin $k.cel }
  $u.Zrodla = @(@($k.zrodla) | Where-Object { "$_".Trim() } | ForEach-Object { Rozwin $_ })
  foreach ($w in @($k.wykluczenia)) { if ($w -and "$($w.sciezka)".Trim()) { $u.Wykluczenia += (Rozwin $w.sciezka) } }
  if ($u.Zrodla.Count -eq 0 -and $rej.zrodlo -eq "plik") { $u.BezZrodel = $true; $u.Zrodla = @($KorzenieClaude | ForEach-Object { Rozwin $_ }) }
  if (-not $u.Cel) { $u.Brak = "w ustawieniach kopii ($($u.Skad)) nie ma celu (kopia.cel) - skrypt kopii skonczylby sie bledem; wybierz folder w oknie instalatora" }
  return $u
}

function Stan-Celu([string]$cel) {
  if (-not $cel) { return [pscustomobject]@{ Ok = $false; Opis = "nie ma celu kopii (pole kopia.cel) - wybierz folder w oknie instalatora" } }
  if (-not [System.IO.Path]::IsPathRooted($cel)) { return [pscustomobject]@{ Ok = $false; Opis = "cel kopii '$cel' nie jest pelna sciezka" } }
  $korzen = [System.IO.Path]::GetPathRoot($cel)
  if (-not (Test-Path -LiteralPath $korzen)) { return [pscustomobject]@{ Ok = $false; Opis = "nie widze dysku $korzen dla celu kopii $cel (odlaczony dysk albo Dysk Google nie chodzi?)" } }
  if (Test-Path -LiteralPath $cel -PathType Container) { return [pscustomobject]@{ Ok = $true; Opis = "cel kopii: $cel" } }
  if (Test-Path -LiteralPath $cel) { return [pscustomobject]@{ Ok = $false; Opis = "cel kopii $cel to plik, nie folder" } }
  return [pscustomobject]@{ Ok = $true; Opis = "cel kopii: $cel (folder jeszcze nie istnieje - zaloze go)"; Brak = $true }
}

function Czytaj-Stan-Kopii {
  $k = @{}
  if (-not (Test-Path -LiteralPath $PlikStanu)) { return $k }
  foreach ($l in [System.IO.File]::ReadAllLines($PlikStanu)) { $m = [regex]::Match($l, '^([a-z_]+)=(.*)$'); if ($m.Success) { $k[$m.Groups[1].Value] = $m.Groups[2].Value } }
  return $k
}

function Zbierz-Stan($rej) {
  $zainst = [bool]$rej.moduly.kopia
  $u = Ustawienia-Kopii $rej
  $cel = Stan-Celu $u.Cel
  $zad = Stan-Zadania $script:ZadanieKopii 'kopia-zapasowa'
  $sk = Czytaj-Stan-Kopii
  if ($zainst) {
    if (-not $zad.Ok) { Problem "zadanie kopii: $($zad.Opis)" }
    if ($u.Brak) { Problem $u.Brak } elseif (-not $cel.Ok) { Problem $cel.Opis }
    if (@("ALARM", "BLAD") -contains $sk["stan"]) { Problem "ostatnia kopia ($($sk['ostatnia'])): $($sk['stan'])$(if ($sk['blad']) { ' - ' + $sk['blad'] }) - szczegoly w $PlikStanu" }
  }
  $dziala = $zainst -and ($script:MR.problemy.Count -eq 0)
  $ostatnia = if ($sk.Count -gt 0) { [ordered]@{ stan = $sk["stan"]; kiedy = $sk["ostatnia"]; plikow = $sk["plikow"]; mb = $sk["mb"] } } else { $null }
  return [pscustomobject]@{ Zainstalowany = $zainst; Dziala = $dziala; Szczegoly = [ordered]@{
    ustawienia = $u.Skad; cel = $u.Cel; zrodla = $u.Zrodla; tylko_pliki_claude_codex = $u.BezZrodel; wykluczenia = $u.Wykluczenia
    zadanie = $zad.Opis; ostatnia_kopia = $ostatnia } }
}

try {
  if ($Akcja -eq "Stan") {
    [void](Sprawdz-Programy @() @("uv"))
    $rej = Czytaj-Instalacje $KatalogDomowy
    if ($rej.blad) { Problem "rejestr modulow: $($rej.blad)" }
    $st = Zbierz-Stan $rej
    $kom = if ($st.Dziala) { "kopia dziala" } elseif ($st.Zainstalowany) { "kopia wlaczona, ale: " + (@($script:MR.problemy) -join "; ") } else { "kopia nie jest wlaczona" }
    Zakoncz (-not $rej.blad) $kom @{ zainstalowany = $st.Zainstalowany; dziala = $st.Dziala; szczegoly = $st.Szczegoly; rejestr = (Rejestr-Do-Wyniku $rej $KatalogDomowy) }
  }

  $rej = Rejestr-Do-Zmian $KatalogDomowy

  if ($Akcja -eq "Instaluj") {
    $prog = Sprawdz-Programy @() @("uv")
    # Wlaczenie modulu zapisuje rejestr - a skrypt kopii z rejestrem bez pola "kopia" konczy sie
    # bledem. Dlatego bez ustawien w rejestrze nie wlaczamy (okno wpisuje je przed tym wywolaniem).
    if ($rej.zrodlo -ne "plik" -or -not $rej.kopia) {
      $dzis = if ($rej.zrodlo -ne "plik") { " Do tego czasu skrypt kopii chodzi na ustawieniach tego komputera ($(Sciezka-Lokalnych $KatalogDomowy), pole kopia), a bez nich na szablonie narzedzia\kopia-zapasowa-domyslne.json." } else { "" }
      Zakoncz $false ("w rejestrze modulow nie ma ustawien kopii (pole kopia: cel, zrodla, wykluczenia) - okno instalatora zapisuje je po wyborze folderu." + $dzis)
    }
    $u = Ustawienia-Kopii $rej
    if ($u.Brak) { Zakoncz $false $u.Brak }
    $cel = Stan-Celu $u.Cel
    if (-not $cel.Ok) { Zakoncz $false $cel.Opis }
    if ($cel.Brak) {
      if ($Proba) { Plan "zalozylbym folder kopii $($u.Cel)" }
      else {
        try { New-Item -ItemType Directory -Force -Path $u.Cel -ErrorAction Stop | Out-Null; Krok "zalozony folder kopii $($u.Cel)" }
        catch { Zakoncz $false "nie moge zalozyc folderu kopii $($u.Cel): $($_.Exception.Message)" }
      }
    } else { Krok $cel.Opis }
    if ($u.BezZrodel) {
      Ostrzezenie "w rejestrze nie ma listy zrodel kopii (kopia.zrodla) - kopia obejmie tylko pliki Claude'a i Codeksa: $($KorzenieClaude -join ', ')"
    }
    foreach ($z in $u.Zrodla) {
      if (Test-Path -LiteralPath $z) { Krok "zrodlo kopii: $z" }
      elseif (-not $u.BezZrodel) { Ostrzezenie "zrodla kopii $z nie ma na dysku - kopia je pominie" }
    }
    if ($u.Wykluczenia.Count -gt 0) { Krok "wykluczone z kopii ($($u.Wykluczenia.Count)): $($u.Wykluczenia -join ', ')" }
    if (-not $prog["uv"] -and -not (Test-Path (Join-Path $Zrodlo "lore\.venv\Scripts\python.exe"))) {
      Ostrzezenie "nie ma uv ani srodowiska Lore - bazy SQLite (np. lore.db) kopia przepuszcza przez Pythona; bez niego ich nie skopiuje"
    }
    if ($Proba) { Plan "zadanie $($script:ZadanieKopii): codzienna kopia, niewidoczna, po wylaczonym komputerze nadrabia; zrodla i cel czyta z rejestru przy kazdym przebiegu (kopia-zapasowa.ps1 -ZalozZadanie)" }
    else {
      $w = Uruchom-Skrypt $Skrypt @("-ZalozZadanie", "-KatalogDomowy", $KatalogDomowy) 120
      $zad = Stan-Zadania $script:ZadanieKopii 'kopia-zapasowa'
      if ($w.Kod -ne 0 -or -not $zad.Ok) { Zakoncz $false "nie udalo sie zalozyc zadania $($script:ZadanieKopii): $(Sedno $w.Tekst) $($zad.Opis)" }
      Krok "zadanie $($script:ZadanieKopii) jest w Harmonogramie ($($zad.Opis)) - $(Sedno $w.Tekst)"
    }
    Zapisz-Modul "kopia" $true $KatalogDomowy
    $ok = Po-Zmianie-Rejestru $Zrodlo $KatalogDomowy
    if ($Proba) { Zakoncz $true "proba: kopia dalaby sie zainstalowac" }
    $rej2 = Czytaj-Instalacje $KatalogDomowy
    $st = Zbierz-Stan $rej2
    $kom = if ($st.Dziala) { "kopia zainstalowana - pierwsza pojdzie o zaplanowanej godzinie" } else { "kopia zainstalowana; do sprawdzenia: " + (@($script:MR.problemy) -join "; ") }
    Zakoncz $ok $kom @{ zainstalowany = $st.Zainstalowany; dziala = $st.Dziala; szczegoly = $st.Szczegoly; rejestr = (Rejestr-Do-Wyniku $rej2 $KatalogDomowy) }
  }

  # ---------------------------------------------------------------- Usun
  $ok = $true
  if ($Proba) { Plan "zdjalbym zadanie $($script:ZadanieKopii)" }
  else {
    $w = Uruchom-Skrypt $Skrypt @("-UsunZadanie", "-KatalogDomowy", $KatalogDomowy) 120
    if ($w.Kod -ne 0 -or (Zadanie-Jest $script:ZadanieKopii)) { Zakoncz $false "nie udalo sie zdjac zadania $($script:ZadanieKopii), wiec kopia zostaje wlaczona: $(Sedno $w.Tekst)" }
    Krok "zadanie $($script:ZadanieKopii) zdjete - nowych kopii nie bedzie"
  }
  Zapisz-Modul "kopia" $false $KatalogDomowy
  if (-not (Po-Zmianie-Rejestru $Zrodlo $KatalogDomowy)) { $ok = $false }
  $u = Ustawienia-Kopii $rej
  if ($u.Cel) { Krok "zrobione kopie zostaja w $($u.Cel) - nie usuwam ich nigdy (takze z -UsunDane)" }
  Krok "ustawienia kopii w rejestrze (pole kopia) zostaja - przy ponownym wlaczeniu nie trzeba ich wybierac od nowa"
  if ($UsunDane) {
    foreach ($p in @($PlikStanu, $PlikIndeksu)) { if (-not (Usun-Katalog-Danych $p "stan kopii $(Split-Path -Leaf $p)")) { $ok = $false } }
  } else {
    Krok "stan kopii w ~\.claude\mr zostaje (wznowienie bez pelnej kopii) - usunie go -UsunDane"
  }
  if ($Proba) { Zakoncz $ok "proba: kopia dalaby sie usunac" }
  $kom = if ($ok) { "kopia wylaczona" } else { "kopia wylaczona, ale nie wszystko udalo sie zdjac - szczegoly w uwagach" }
  Zakoncz $ok $kom @{ zainstalowany = $false; dziala = $false; rejestr = (Rejestr-Do-Wyniku (Czytaj-Instalacje $KatalogDomowy) $KatalogDomowy) }
} catch {
  Zakoncz $false ("nieoczekiwany blad: " + $_.Exception.Message + " (" + $_.InvocationInfo.PositionMessage.Split("`n")[0].Trim() + ")")
}
