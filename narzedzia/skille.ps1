# Polecane skille MegaRuchacza - wykrywanie, instalacja, aktualizacja, cofniecie.
#
# PO CO TO ISTNIEJE. Uzytkownik trzyma w ~\.claude\skills ponad sto skilli, prawie
# wszystkie wgrane recznie jako zwykle kopie - bez sladu, skad sa i z ktorej wersji.
# Chcial trzech rzeczy: listy polecanych skilli z opisem po ludzku (baza:
# skille\katalog.psd1), wykrycia, co juz ma, i codziennej aktualizacji tego, co ma
# pod opieka. Ten skrypt robi wszystko trzy; okno nadzorcy (zakladka "Skille") tylko
# go wola i pokazuje, co zapisal.
#
# ZASADY, KTORYCH TEN PLIK PILNUJE:
# 1. Skilla zmienionego recznie NIE nadpisuje nigdy sam. Zmieniony recznie = tresc
#    na dysku nie odpowiada ZADNEJ wersji z historii zrodla (porownanie z kazdym
#    stanem katalogu skilla w historii gita, takze sprzed przeniesien w repo).
#    Nadpisanie tylko na wyrazne zyczenie (-Wymus), zawsze z kopia.
# 2. Przed kazda podmiana - kopia starej wersji POZA ~\.claude\skills (inaczej Claude
#    wczytywalby ja jako drugi skill), w ~\.claude\mr\skille\kopie\<skill>\<stempel>\.
#    Cofniecie przywraca te kopie co do bajtu.
# 3. Pierwszy przebieg na maszynie niczego nie podmienia - tylko spisuje, co jest
#    ("przejecie pod opieke": zapis zrodla i commita, bez dotykania plikow).
#    Aktualizacje zaczynaja sie od nastepnego codziennego przebiegu.
# 4. Cisza jest zakazana: blad sieci, zly adres zrodla, blad gita - kazdy trafia do
#    stanu (pole blad przy zrodle i przy skillu), do dziennika i do znacznika
#    codziennego przebiegu, skad pokazuje go okno. Zadnego pustego catch.
# 5. Niewidocznie: git startuje z CreateNoWindow, bez pytan o haslo. Skrypt sam
#    nie otwiera okien; w tle odpala go nadzorca przez conhost --headless.
# 6. Siec ponawiamy, reszty nie (P20). Pobranie ze zrodla (clone, fetch, rozpakowanie
#    plikow z czesciowego klonu), ktore sie nie udalo, idzie jeszcze 5 razy z rosnaca
#    przerwa (-Przerwy, domyslnie 5, 15, 30, 60, 120 s); kazda proba trafia do dziennika,
#    blad dopiero po ostatniej. Bledy, ktore nie sa siecia (np. brak skilla w zrodle),
#    wychodza od razu - drugi raz wyszlyby tak samo.
# 7. Autor przeniosl skill w inne miejsce repo (ten sam katalog z SKILL.md gdzie
#    indziej) - skrypt sam go znajduje, zapisuje nowa sciezke w stanie ("przeniesiony")
#    i aktualizuje normalnie. Autor skill usunal - to NIE jest blad: stan "usuniety",
#    kopia u uzytkownika zostaje nietknieta; skasowac ja mozna tylko jawnie (-Tryb usun).
#
# GDZIE CZYTAJA SKILLE (rozpoznanie 2026-09-29, raport .megaruchacz\raporty\P18.md):
#   Claude Code - ~\.claude\skills\<nazwa>\SKILL.md            -> cel "claude" (zawsze)
#   Codex 0.157 - ~\.agents\skills\<nazwa>\SKILL.md (zakres USER; sprawdzone
#                 "codex debug prompt-input": korzen r0 = C:/Users/.../.agents/skills)
#                                                               -> cel "codex" (gdy jest Codex)
#   opencode    - czyta ~\.claude\skills i ~\.agents\skills sam (docs opencode.ai/docs/skills),
#                 wiec nie ma osobnego celu - dubel nazwy konczy sie u niego wpisem
#                 "duplicate skill name" w jego dzienniku, nie bledem.
#
# STAN (poza repo): ~\.claude\mr\skille\
#   stan.json        - co pod opieka, z jakiego zrodla i commita, kiedy sprawdzone
#   znacznik.txt     - codzienny przebieg: dzien, wynik, powod (czyta nadzorca co 15 min)
#   dziennik.log     - co sie zmienilo, z ktorego commita na ktory i kiedy
#   operacja.txt/.log- ostatnia operacja (klucze + pelny wydruk) dla okna
#   kopie\           - kopie zapasowe przed kazda podmiana
#   repo\<zrodlo>\   - wlasne kopie repozytoriow zrodel (czesciowy klon, tylko sciezki skilli)
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File narzedzia\skille.ps1 [-Tryb <tryb>] [opcje]
#     -Tryb stan         (domyslnie) stan z dysku, bez sieci i bez gita; -Json dla okna
#     -Tryb wykryj       pobiera zrodla, porownuje, przejmuje istniejace kopie pod opieke
#     -Tryb instaluj     -Skill <nazwa> albo -ZeZrodla <id>: wgrywa tam, gdzie brakuje
#     -Tryb aktualizuj   [-Skill <nazwa>] [-ZeZrodla <id>]: nowsze wersje skilli pod opieka
#     -Tryb cofnij       -Skill <nazwa>: przywraca kopie sprzed ostatniej aktualizacji
#     -Tryb usun         -Skill <nazwa>: kasuje u uzytkownika skill, ktory AUTOR usunal
#                        (z kopia zapasowa - "cofnij" go przywraca); innych nie kasuje
#     -Tryb codziennie   raz na dobe (znacznik): wykryj + aktualizuj; -Wymus pomija znacznik
#     -KatalogDomowy <k> podmiana katalogu domowego (testy na kopii)
#     -Katalog <plik>    podmiana bazy (proba negatywna: zly adres zrodla)
#     -BezSieci          bez pobierania - tylko to, co juz lezy w kopiach zrodel
#     -Przerwy "5,15"    przerwy w sekundach przed kolejnymi ponowieniami pobrania
#                        (ile liczb, tyle ponowien); do prob skraca sie je, np. "1,2,3,4,5"
#     -Wymus             instaluj/aktualizuj: nadpisz takze skill zmieniony recznie (z kopia);
#                        codziennie: pomin znacznik "juz dzis"
#
# Kod wyjscia: 0 wszystko sie udalo, 1 cos sie nie udalo (szczegoly w wydruku i w stanie),
# 2 zle wywolanie, 3 inny przebieg wlasnie pracuje.

param(
  [ValidateSet("stan", "wykryj", "instaluj", "aktualizuj", "cofnij", "codziennie", "usun")]
  [string]$Tryb = "stan",
  [string]$Skill = "",
  [string]$ZeZrodla = "",
  [string]$KatalogDomowy = $HOME,
  [string]$Katalog = "",
  [switch]$BezSieci,
  [string]$Przerwy = "5,15,30,60,120",
  [switch]$Wymus,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

if (-not $Katalog) { $Katalog = Join-Path (Split-Path -Parent $PSScriptRoot) "skille\katalog.psd1" }
$Dom        = $KatalogDomowy.TrimEnd('\')
$KatStanu   = Join-Path $Dom ".claude\mr\skille"
$PlikStanu  = Join-Path $KatStanu "stan.json"
$PlikZnacz  = Join-Path $KatStanu "znacznik.txt"
$PlikDzien  = Join-Path $KatStanu "dziennik.log"
$PlikOper   = Join-Path $KatStanu "operacja.txt"
$PlikOperLog = Join-Path $KatStanu "operacja.log"
$KatKopii   = Join-Path $KatStanu "kopie"
$KatRepo    = Join-Path $KatStanu "repo"
$KatTmp     = Join-Path $KatStanu "tmp"

# Limity czasu gita. Klon pierwszy raz bywa duzy (impeccable ma ~1900 commitow),
# ale to zawsze praca w tle - nikt przed ekranem nie czeka na jego koniec.
$CZAS_KLON   = 600
$CZAS_FETCH  = 180
$CZAS_GIT    = 120
# Ile kopii zapasowych jednego skilla trzymamy. Dziesiec to ~dwa tygodnie codziennych
# zmian w najczesciej zmienianym zrodle (impeccable) - starsze nie maja juz sensu.
$KOPII_NA_SKILL = 10
# Przerwy przed ponowieniami pobrania ze zrodla: piec ponowien z rosnaca przerwa,
# razem ~4 min. Chwilowa czkawka sieci albo GitHuba mija zwykle w sekundy-minuty,
# a skrypt chodzi w tle, wiec czekanie nikogo nie blokuje. Dluzej nie ma sensu -
# jutro jest nastepne codzienne sprawdzenie, a "Sprawdz teraz" dziala zawsze.
# (nie $PRZERWY: PowerShell nie rozroznia wielkosci liter, to bylby parametr -Przerwy, typu tekst)
$SEKUNDY_PRZERW = @()
# (przecinki albo spacje - "-Przerwy 2,4,6" podane przez -File dochodzi jako "2 4 6")
foreach ($t in @($Przerwy -split '[,;\s]+' | Where-Object { $_.Trim() })) {
  $n = 0
  if (-not [int]::TryParse($t.Trim(), [ref]$n) -or $n -lt 0) { Write-Output "BŁĄD: -Przerwy przyjmuje liczby sekund oddzielone przecinkami, a dostało: $Przerwy"; exit 2 }
  $SEKUNDY_PRZERW += $n
}
$LINII_DZIENNIKA = 3000
# Pliki, ktore Windows sam podrzuca do katalogow - nie sa czescia skilla.
$SMIECI = @("desktop.ini", "Thumbs.db", ".DS_Store")

$script:Wydruk = New-Object System.Collections.Generic.List[string]
$script:Bledy  = 0

# ------------------------------------------------------------------ pomocnicze

function Pisz([string]$t) {
  $script:Wydruk.Add($t)
  if (-not $Json) { [Console]::Out.WriteLine($t) }
}

function Bez-Bom { return (New-Object System.Text.UTF8Encoding($false)) }

function Zapisz-Tekst([string]$sciezka, [string]$tekst) {
  $kat = Split-Path -Parent $sciezka
  if ($kat -and -not (Test-Path -LiteralPath $kat)) { New-Item -ItemType Directory -Force -Path $kat | Out-Null }
  # Zapis przez plik tymczasowy i podmiane - okno czyta ten plik w dowolnej chwili
  # i nie moze trafic na polowe tresci.
  $tmp = "$sciezka.tmp"
  [System.IO.File]::WriteAllText($tmp, $tekst, (Bez-Bom))
  if (Test-Path -LiteralPath $sciezka) { [System.IO.File]::Replace($tmp, $sciezka, [NullString]::Value) }
  else { [System.IO.File]::Move($tmp, $sciezka) }
}

function Klucze-Z-Pliku([string]$sciezka) {
  $s = [ordered]@{}
  if (-not (Test-Path -LiteralPath $sciezka)) { return $s }
  foreach ($l in [System.IO.File]::ReadAllLines($sciezka, [System.Text.Encoding]::UTF8)) {
    $m = [regex]::Match($l, '^\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*:\s*(.*?)\s*$')
    if ($m.Success) { $s[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $s
}

function Zapisz-Klucze([string]$sciezka, $s) {
  $linie = @()
  foreach ($k in $s.Keys) { $linie += ("{0}: {1}" -f $k, (("$($s[$k])") -replace '[\r\n]+', ' ')) }
  Zapisz-Tekst $sciezka (($linie -join "`r`n") + "`r`n")
}

function Teraz { return (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }

function Dziennik([string]$co, [string]$skill, [string]$szczegoly) {
  try {
    if (-not (Test-Path -LiteralPath $KatStanu)) { New-Item -ItemType Directory -Force -Path $KatStanu | Out-Null }
    $linia = "{0} | {1} | {2} | {3}" -f (Teraz), $co, $skill, ($szczegoly -replace '[\r\n]+', ' ')
    [System.IO.File]::AppendAllText($PlikDzien, $linia + "`r`n", (Bez-Bom))
    $wszystkie = [System.IO.File]::ReadAllLines($PlikDzien, [System.Text.Encoding]::UTF8)
    if ($wszystkie.Count -gt $LINII_DZIENNIKA + 200) {
      [System.IO.File]::WriteAllLines($PlikDzien, [string[]]($wszystkie | Select-Object -Last $LINII_DZIENNIKA), (Bez-Bom))
    }
  } catch {
    # Ostatnie ogniwo: dziennika nie da sie zapisac - zostaje wydruk i strumien bledow.
    Pisz "UWAGA: nie moge pisac do dziennika $PlikDzien - $($_.Exception.Message)"
    Write-Error "skille: nie moge pisac do dziennika $PlikDzien - $($_.Exception.Message)" -ErrorAction Continue
  }
}

function Blad([string]$skill, [string]$tresc) {
  $script:Bledy++
  Pisz "BŁĄD: $tresc"
  Dziennik "blad" $skill $tresc
}

# Szybkie liczenie odciskow plikow (skrot gita dla obiektu "blob") i zamiana CRLF na LF.
# W C#, bo w samym PowerShellu petla po bajtach kilkumegabajtowego pliku trwa sekundy.
if (-not ('MegaRuchacz.SkilleOdcisk' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
namespace MegaRuchacz {
  public static class SkilleOdcisk {
    public static string Blob(byte[] b) {
      byte[] nag = Encoding.ASCII.GetBytes("blob " + b.Length + "\0");
      using (SHA1 s = SHA1.Create()) {
        s.TransformBlock(nag, 0, nag.Length, null, 0);
        s.TransformFinalBlock(b, 0, b.Length);
        return BitConverter.ToString(s.Hash).Replace("-", "").ToLowerInvariant();
      }
    }
    // null, gdy plik jest binarny (bajt zerowy w pierwszych 8000) albo nie ma CRLF -
    // wtedy zamiana nic by nie zmienila. Tak samo rozpoznaje tekst git (core.autocrlf).
    public static byte[] BezCrlf(byte[] b) {
      int n = Math.Min(b.Length, 8000);
      for (int i = 0; i < n; i++) if (b[i] == 0) return null;
      bool jest = false;
      for (int i = 0; i + 1 < b.Length; i++) if (b[i] == 13 && b[i + 1] == 10) { jest = true; break; }
      if (!jest) return null;
      MemoryStream m = new MemoryStream(b.Length);
      for (int i = 0; i < b.Length; i++) {
        if (b[i] == 13 && i + 1 < b.Length && b[i + 1] == 10) continue;
        m.WriteByte(b[i]);
      }
      return m.ToArray();
    }
  }
}
'@
}

# Odcisk katalogu skilla na dysku: sciezka wzgledna (z "/") -> dwa skroty: surowy
# i po zamianie CRLF na LF (kopie wgrane przez gita z core.autocrlf=true maja CRLF,
# a w repo leza z LF - to ta sama wersja). $null, gdy katalogu nie ma.
function Odcisk-Lokalny([string]$kat) {
  if (-not (Test-Path -LiteralPath $kat -PathType Container)) { return $null }
  $o = @{}
  $baza = (Resolve-Path -LiteralPath $kat).ProviderPath.TrimEnd('\')
  foreach ($f in @(Get-ChildItem -LiteralPath $baza -Recurse -File -Force)) {
    if ($SMIECI -contains $f.Name) { continue }
    $rel = $f.FullName.Substring($baza.Length + 1).Replace('\', '/')
    $b = [System.IO.File]::ReadAllBytes($f.FullName)
    $surowy = [MegaRuchacz.SkilleOdcisk]::Blob($b)
    $bez = [MegaRuchacz.SkilleOdcisk]::BezCrlf($b)
    $norm = $surowy
    if ($null -ne $bez) { $norm = [MegaRuchacz.SkilleOdcisk]::Blob($bez) }
    $o[$rel] = @($surowy, $norm)
  }
  return $o
}

# Czy pliki na dysku to dokladnie dana wersja (zestaw plikow i tresc kazdego).
function Zgodne($lok, $wersja) {
  if ($null -eq $lok -or $null -eq $wersja) { return $false }
  if ($lok.Count -ne $wersja.Count) { return $false }
  foreach ($rel in $wersja.Keys) {
    if (-not $lok.ContainsKey($rel)) { return $false }
    $s = "$($wersja[$rel])"
    if (($lok[$rel][0] -ne $s) -and ($lok[$rel][1] -ne $s)) { return $false }
  }
  return $true
}

# Roznica miedzy dyskiem a wersja - do opisu "zmieniony recznie" i do dziennika.
function Roznica($lok, $wersja) {
  $r = [pscustomobject]@{ Takie = 0; Zmienione = @(); Dodane = @(); Brakujace = @() }
  foreach ($rel in $wersja.Keys) {
    if (-not $lok.ContainsKey($rel)) { $r.Brakujace += $rel; continue }
    $s = "$($wersja[$rel])"
    if (($lok[$rel][0] -eq $s) -or ($lok[$rel][1] -eq $s)) { $r.Takie++ } else { $r.Zmienione += $rel }
  }
  foreach ($rel in $lok.Keys) { if (-not $wersja.ContainsKey($rel)) { $r.Dodane += $rel } }
  return $r
}

# Roznica miedzy dwiema wersjami ze zrodla (obie jako rel -> skrot).
function Roznica-Wersji($stara, $nowa) {
  $r = [pscustomobject]@{ Dodane = @(); Zmienione = @(); Usuniete = @() }
  foreach ($rel in $nowa.Keys) {
    if (-not $stara.ContainsKey($rel)) { $r.Dodane += $rel }
    elseif ("$($stara[$rel])" -ne "$($nowa[$rel])") { $r.Zmienione += $rel }
  }
  foreach ($rel in $stara.Keys) { if (-not $nowa.ContainsKey($rel)) { $r.Usuniete += $rel } }
  return $r
}

function Na-Slownik($o) {
  $h = @{}
  if ($null -eq $o) { return $h }
  if ($o -is [hashtable]) { return $o }
  foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = $p.Value }
  return $h
}

# Odcisk wersji do zapisania w stanie: dla wersji z dysku bierzemy skrot zgodny z repo.
function Odcisk-Do-Stanu($lok, $wersja) {
  $h = @{}
  foreach ($rel in $wersja.Keys) { $h[$rel] = "$($wersja[$rel])" }
  return $h
}

# --------------------------------------------------------------------- git

function Cytuj([string]$a) {
  if ($a -eq "") { return '""' }
  if ($a -notmatch '[\s"]') { return $a }
  $w = New-Object System.Text.StringBuilder
  [void]$w.Append('"')
  $ukosniki = 0
  foreach ($c in $a.ToCharArray()) {
    if ($c -eq '\') { $ukosniki++; continue }
    if ($c -eq '"') { [void]$w.Append('\' * ($ukosniki * 2 + 1)); [void]$w.Append('"'); $ukosniki = 0; continue }
    if ($ukosniki -gt 0) { [void]$w.Append('\' * $ukosniki); $ukosniki = 0 }
    [void]$w.Append($c)
  }
  if ($ukosniki -gt 0) { [void]$w.Append('\' * ($ukosniki * 2)) }
  [void]$w.Append('"')
  return $w.ToString()
}

# Git bez okna (CreateNoWindow), bez pytan o haslo i z limitem czasu. Oba strumienie
# czytane asynchronicznie - "git log" potrafi oddac kilka megabajtow i przy czytaniu
# po kolei proces stanalby na pelnym buforze.
function Wolaj-Git([string]$kat, [string[]]$argumenty, [int]$sekundy = $CZAS_GIT) {
  $w = [pscustomobject]@{ ok = $false; kod = $null; tekst = ""; powod = "" }
  $wszystkie = @("-c", "core.quotepath=false", "-c", "credential.interactive=never", "-c", "core.longpaths=true")
  if ($kat) { $wszystkie = @("-C", $kat) + $wszystkie }
  $wszystkie += $argumenty
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "git"
  $psi.Arguments = (($wszystkie | ForEach-Object { Cytuj $_ }) -join ' ')
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  $psi.EnvironmentVariables["GIT_TERMINAL_PROMPT"] = "0"
  $psi.EnvironmentVariables["GCM_INTERACTIVE"] = "never"
  $psi.EnvironmentVariables["GIT_ASKPASS"] = ""
  $psi.EnvironmentVariables["SSH_ASKPASS"] = ""
  $p = $null
  try { $p = [System.Diagnostics.Process]::Start($psi) }
  catch { $w.powod = "nie da się uruchomić gita ($($_.Exception.Message)) - czy git jest zainstalowany?"; return $w }
  $wy = $p.StandardOutput.ReadToEndAsync()
  $bl = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($sekundy * 1000)) {
    try { $p.Kill() } catch { Dziennik "uwaga" "" "git nie dal sie ubic po przekroczeniu czasu: $($psi.Arguments)" }
    $w.powod = "git nie skończył w $sekundy s (git $($argumenty[0]))"
    return $w
  }
  $p.WaitForExit()
  $w.kod = $p.ExitCode
  $w.tekst = $wy.Result
  $b = (("$($bl.Result)" -replace '[\r\n]+', ' ').Trim())
  if ($p.ExitCode -eq 0) { $w.ok = $true }
  else {
    $w.powod = $b
    if (-not $w.powod) { $w.powod = "git $($argumenty[0]) zwrócił kod $($p.ExitCode)" }
  }
  return $w
}

# ---------------------------------------------------------------- baza skilli

function Wczytaj-Katalog {
  if (-not (Test-Path -LiteralPath $Katalog)) { throw "nie ma bazy skilli: $Katalog" }
  $k = Import-PowerShellDataFile -LiteralPath $Katalog
  $zrodla = @()
  foreach ($z in @($k.Zrodla)) {
    if (-not $z.Id -or -not $z.Adres) { throw "wpis źródła w bazie bez Id albo Adres: $($z.Nazwa)" }
    $rodzaj = "skille"; if ($z.Rodzaj) { $rodzaj = "$($z.Rodzaj)" }
    $galaz = "main"; if ($z.Galaz) { $galaz = "$($z.Galaz)" }
    $sk = @()
    foreach ($s in @($z.Skille)) {
      $sc = "$($z.Sciezka)/$($s.Nazwa)".TrimStart('/'); if ($s.Sciezka) { $sc = "$($s.Sciezka)" }
      $fo = "$($s.Nazwa)"; if ($s.Folder) { $fo = "$($s.Folder)" }
      $sk += [pscustomobject]@{
        Nazwa = "$($s.Nazwa)"; Sciezka = $sc.Trim('/'); Folder = $fo; Opis = "$($s.Opis)"
        Robocza = [bool]$s.Robocza; Zrodlo = "$($z.Id)"
        NazwaWRepo = (($sc.Trim('/')) -split '/')[-1]
        # P20: sciezka z bazy (Sciezka moze zmienic Zastosuj-Przenosiny/Szukaj-Przenosin),
        # autor usunal skill, skill przeniesiony w kilka miejsc naraz (nie zgaduje ktore)
        SciezkaWBazie = $sc.Trim('/'); Usuniety = $false; Niepewny = $false
      }
    }
    $zrodla += [pscustomobject]@{
      Id = "$($z.Id)"; Nazwa = "$($z.Nazwa)"; Adres = "$($z.Adres)"; Galaz = $galaz
      Sciezka = "$($z.Sciezka)"; Opis = "$($z.Opis)"; Rodzaj = $rodzaj; Uwaga = "$($z.Uwaga)"; Skille = $sk
    }
  }
  return ,$zrodla
}

# Gdzie wgrywamy. Claude Code zawsze; Codex tylko gdy jest na maszynie (katalog
# ustawien Codeksa albo katalog Codeksa w Orce) - na komputerze bez Codeksa nie
# zakladamy ~\.agents\skills z niczego.
function Cele-Instalacji {
  $c = @([pscustomobject]@{ Id = "claude"; Nazwa = "Claude Code"; Katalog = (Join-Path $Dom ".claude\skills"); Jest = $true })
  $jestCodex = (Test-Path -LiteralPath (Join-Path $Dom ".codex")) -or
               (Test-Path -LiteralPath (Join-Path $Dom "AppData\Roaming\orca\codex-runtime-home"))
  $c += [pscustomobject]@{ Id = "codex"; Nazwa = "Codex"; Katalog = (Join-Path $Dom ".agents\skills"); Jest = $jestCodex }
  return ,$c
}

# -------------------------------------------------------------------- stan

function Nowy-Stan { return @{ wersja = 1; przejeto = ""; sprawdzono = ""; zrodla = @{}; skille = @{} } }

function Wczytaj-Stan {
  if (-not (Test-Path -LiteralPath $PlikStanu)) { return (Nowy-Stan) }
  $raw = [System.IO.File]::ReadAllText($PlikStanu, [System.Text.Encoding]::UTF8)
  $j = $raw | ConvertFrom-Json
  $s = Nowy-Stan
  $s.przejeto = "$($j.przejeto)"; $s.sprawdzono = "$($j.sprawdzono)"
  foreach ($p in @($j.zrodla.PSObject.Properties)) { $s.zrodla[$p.Name] = Na-Slownik $p.Value }
  foreach ($p in @($j.skille.PSObject.Properties)) {
    $sk = Na-Slownik $p.Value
    $cele = @{}
    foreach ($c in @((Na-Slownik $sk.cele).GetEnumerator())) {
      $cc = Na-Slownik $c.Value
      $cc.pliki = Na-Slownik $cc.pliki
      $cele[$c.Key] = $cc
    }
    $sk.cele = $cele
    if ($sk.najnowszy) { $n = Na-Slownik $sk.najnowszy; $n.pliki = Na-Slownik $n.pliki; $sk.najnowszy = $n }
    if ($sk.zmiana) { $sk.zmiana = Na-Slownik $sk.zmiana }
    if ($sk.przeniesiony) { $sk.przeniesiony = Na-Slownik $sk.przeniesiony }
    if ($sk.usuniety) { $sk.usuniety = Na-Slownik $sk.usuniety }
    $s.skille[$p.Name] = $sk
  }
  return $s
}

function Zapisz-Stan($s) {
  Zapisz-Tekst $PlikStanu ($s | ConvertTo-Json -Depth 12)
}

function Stan-Skilla($stan, $sk) {
  if (-not $stan.skille.ContainsKey($sk.Nazwa)) {
    $stan.skille[$sk.Nazwa] = @{ zrodlo = $sk.Zrodlo; sciezka = $sk.Sciezka; folder = $sk.Folder; cele = @{}; najnowszy = $null; zmiana = $null; blad = ""; sprawdzono = "" }
  }
  $x = $stan.skille[$sk.Nazwa]
  $x.zrodlo = $sk.Zrodlo; $x.sciezka = $sk.Sciezka; $x.folder = $sk.Folder
  return $x
}

# Przenosiny i usuniecia zapamietane w stanie (P20) - zeby tryb "stan" (bez gita) i
# operacje bez pobierania znaly aktualna sciezke skilla i wiedzialy, ze autor go usunal.
# Wpis o przenosinach dziala, dopoki baza wskazuje stara sciezke; gdy ktos poprawi baze,
# obowiazuje baza.
function Zastosuj-Przenosiny($stan, $zrodla) {
  foreach ($z in $zrodla) {
    foreach ($sk in $z.Skille) {
      $x = $stan.skille[$sk.Nazwa]
      if ($null -eq $x) { continue }
      if ($x.przeniesiony -and ("$($x.przeniesiony.z)" -eq $sk.SciezkaWBazie) -and "$($x.przeniesiony.na)") { $sk.Sciezka = "$($x.przeniesiony.na)" }
      if ($x.usuniety -and ("$($x.usuniety.sciezka)" -eq $sk.Sciezka)) { $sk.Usuniety = $true }
    }
  }
}

# ------------------------------------------------------------- kopie zrodel

function Katalog-Repo($z) { return (Join-Path $KatRepo $z.Id) }

# Sciezki, ktore naprawde potrzebujemy z repo - reszta (dema, strony, aplikacje)
# nie jest pobierana wcale: czesciowy klon bez tresci plikow + wybrane katalogi.
function Wzorce-Zrodla($z) {
  $w = @()
  foreach ($s in $z.Skille) { $w += "/" + $s.Sciezka + "/" }
  return ,@($w | Select-Object -Unique)
}

# ----------------------------------------------------- pobieranie i ponowienia (P20)

# Czy nieudane wywolanie gita to siec (warto ponowic), czy cos, co za kazdym razem
# wyjdzie tak samo. Clone i fetch rozmawiaja tylko z serwerem, wiec kazda ich porazka
# ($kazdyKod) liczy sie jako sieciowa - takze "Repository not found": po stronie
# GitHuba bywa chwilowa. Rozpakowanie jest lokalne i dociaga z sieci tylko brakujace
# pliki czesciowego klonu - tam o sieci mowi dopiero tresc bledu. Git, ktory sie
# w ogole nie uruchomil, siecia nie jest.
function Czy-Siec($r, [bool]$kazdyKod) {
  if ($r.ok) { return $false }
  if ("$($r.powod)" -match 'nie skończył w') { return $true }
  if ($null -eq $r.kod) { return $false }
  if ($kazdyKod) { return $true }
  return ("$($r.powod)" -match 'unable to access|Could not resolve|Failed to connect|timed out|promisor|remote|HTTP|SSL|TLS|Connection|fetch-pack|early EOF|RPC failed')
}

# Powod porazki pobrania po ludzku. Tresc gita zostaje obok w nawiasie - do diagnozy.
function Powod-Sieci-Po-Ludzku([string]$powod, [string]$adres) {
  $serwer = "serwera źródła"
  $m = [regex]::Match($adres, '^https?://([^/]+)')
  if ($m.Success) { $serwer = $m.Groups[1].Value }
  if ($powod -match 'Repository not found|not found|404') { return "pod adresem $adres nie ma repozytorium - autor mógł je usunąć, ukryć albo zmienić mu nazwę (albo adres w bazie jest błędny)" }
  if ($powod -match 'Could not resolve (host|proxy)|getaddrinfo') { return "brak internetu - komputer nie może odnaleźć serwera $serwer" }
  if ($powod -match 'nie skończył w|timed out|Timeout') { return "serwer $serwer nie odpowiada (za długo czekałem na odpowiedź)" }
  if ($powod -match 'Failed to connect|Connection refused|Could not connect|Connection reset|proxy') { return "nie da się połączyć z serwerem $serwer - brak internetu albo połączenie blokuje zapora lub serwer pośredniczący" }
  if ($powod -match 'SSL|certificate|schannel|TLS') { return "nie udało się nawiązać bezpiecznego połączenia z $serwer (kłopot z certyfikatem)" }
  if ($powod -match 'Authentication|could not read Username|terminal prompts disabled|401|403') { return "źródło wymaga logowania - repozytorium nie istnieje albo przestało być publiczne" }
  if ($powod -match 'error: 5\d\d|returned error: 5') { return "serwer $serwer ma chwilową awarię" }
  return "nie udało się pobrać danych z $serwer"
}

function Opis-Porazki-Pobrania($z, $w, [string]$co) {
  if (-not $w.siec) { return "$co się nie udało: $($w.powod)" }
  $proby = [int]$w.proby
  return "$(Powod-Sieci-Po-Ludzku $w.powod $z.Adres). Próbowałem $proby $(if ($proby -eq 1) { 'raz' } else { 'razy' }) ($co; git: $($w.powod))"
}

# Ponawianie krokow sieciowych. Zadanie = Kto (id zrodla), Co (opis do dziennika),
# Krok (nazwa funkcji wolanej ze zrodlem), Z (zrodlo). Zadania ida rundami: w pierwszej
# kazde raz, w nastepnych - po przerwie z $SEKUNDY_PRZERW - juz tylko nieudane. Dzieki temu
# przy braku sieci piec zrodel czeka ~4 minuty lacznie, a nie piec razy dluzej.
# Krok oddaje obiekt z polami ok, powod, siec; siec = $false konczy od razu, bez ponowien.
# Kazda nieudana proba idzie do dziennika z informacja, kiedy nastepna.
function Z-Ponowieniem($zadania) {
  $wyniki = @{}
  $czeka = @($zadania)
  $prob = $SEKUNDY_PRZERW.Count + 1
  $start = Get-Date
  for ($proba = 1; $czeka.Count -gt 0; $proba++) {
    $dalej = @()
    foreach ($zad in $czeka) {
      $w = $null
      try { $w = & $zad.Krok $zad.Z }
      catch { $w = [pscustomobject]@{ ok = $false; powod = "$($_.Exception.Message)"; siec = $false } }
      $w | Add-Member -NotePropertyName proby -NotePropertyValue $proba -Force
      if ($w.ok) {
        if ($proba -gt 1) { Dziennik "ponowienie" $zad.Kto "$($zad.Co): udalo sie za $proba. proba (po $([int]((Get-Date) - $start).TotalSeconds) s)" }
        $wyniki[$zad.Kto] = $w
        continue
      }
      if (-not $w.siec) { $wyniki[$zad.Kto] = $w; continue }
      if ($proba -ge $prob) {
        Dziennik "proba" $zad.Kto "$($zad.Co): proba $proba z $prob nieudana - $($w.powod); to byla ostatnia (razem $([int]((Get-Date) - $start).TotalSeconds) s)"
        $wyniki[$zad.Kto] = $w
        continue
      }
      $pauza = $SEKUNDY_PRZERW[$proba - 1]
      Dziennik "proba" $zad.Kto "$($zad.Co): proba $proba z $prob nieudana - $($w.powod); ponawiam za $pauza s"
      Pisz "  $($zad.Kto): $($zad.Co) - próba $proba z $prob nieudana, ponawiam za $pauza s."
      $dalej += $zad
    }
    $czeka = $dalej
    if ($czeka.Count -gt 0) { Start-Sleep -Seconds $SEKUNDY_PRZERW[$proba - 1] }
  }
  return $wyniki
}

# Krok sieciowy 1: pierwszy raz klon (czesciowy - bez tresci plikow, bez rozpakowania),
# potem fetch. Adres w bazie inny niz w kopii = klon od nowa. To NASZA kopia
# w ~\.claude\mr - nikt w niej nie pracuje, kasowanie jej jest bezpieczne.
function Krok-Pobrania($z) {
  $w = [pscustomobject]@{ ok = $false; powod = ""; siec = $false }
  $kat = Katalog-Repo $z
  $jest = Test-Path -LiteralPath (Join-Path $kat ".git")
  if ($jest) {
    $url = Wolaj-Git $kat @("config", "--get", "remote.origin.url")
    if ((-not $url.ok) -or ($url.tekst.Trim() -ne $z.Adres)) {
      Dziennik "zrodlo" $z.Id "adres w bazie inny niz w kopii ($($url.tekst.Trim()) -> $($z.Adres)) - klonuje od nowa"
      Remove-Item -LiteralPath $kat -Recurse -Force
      $jest = $false
    }
  }
  if ($jest) {
    $r = Wolaj-Git $kat @("fetch", "--quiet", "origin", $z.Galaz) $CZAS_FETCH
    if (-not $r.ok) { $w.powod = $r.powod; $w.siec = (Czy-Siec $r $true); return $w }
    $w.ok = $true
    return $w
  }
  if (-not (Test-Path -LiteralPath $KatRepo)) { New-Item -ItemType Directory -Force -Path $KatRepo | Out-Null }
  if (Test-Path -LiteralPath $kat) { Remove-Item -LiteralPath $kat -Recurse -Force }
  $r = Wolaj-Git "" @("clone", "--quiet", "--filter=blob:none", "--no-checkout", "--single-branch", "--branch", $z.Galaz,
                "-c", "core.autocrlf=false", "-c", "core.longpaths=true", $z.Adres, $kat) $CZAS_KLON
  if (-not $r.ok) {
    if (Test-Path -LiteralPath $kat) { Remove-Item -LiteralPath $kat -Recurse -Force -ErrorAction Continue }
    $w.powod = $r.powod; $w.siec = (Czy-Siec $r $true)
    return $w
  }
  $w.ok = $true
  return $w
}

# Krok sieciowy 2: ustawienie katalogow skilli w kopii i rozpakowanie najnowszej wersji.
# Czesciowy klon dociaga tu z sieci tresc plikow, ktorych jeszcze nie ma - dlatego tez
# jest ponawiany. Wzorce odswiezamy zawsze: ktos mogl dopisac skill do bazy, a autor
# mogl skill przeniesc.
function Krok-Rozpakowania($z) {
  $w = [pscustomobject]@{ ok = $false; powod = ""; siec = $false }
  $kat = Katalog-Repo $z
  $r = Wolaj-Git $kat (@("sparse-checkout", "set", "--no-cone") + (Wzorce-Zrodla $z)) $CZAS_FETCH
  if (-not $r.ok) { $w.powod = "ustawienie katalogów skilli w kopii: $($r.powod)"; $w.siec = (Czy-Siec $r $false); return $w }
  $r = Wolaj-Git $kat @("reset", "--quiet", "--hard", "origin/$($z.Galaz)") $CZAS_FETCH
  if (-not $r.ok) { $w.powod = "rozpakowanie najnowszej wersji: $($r.powod)"; $w.siec = (Czy-Siec $r $false); return $w }
  $w.ok = $true
  return $w
}

# Autor przeniosl albo usunal skill (P20; 2026-09-30 Matt przeniosl implement-spec, pr
# i retro z in-progress do engineering i usunal resolving-merge-conflicts). Jedno
# "git ls-tree" calego drzewa, bez tresci plikow: katalogi z SKILL.md. Skill, ktorego
# nie ma pod swoja sciezka:
#   - dokladnie jeden katalog o tej samej nazwie z SKILL.md -> przeniesiony: nowa sciezka
#     w $sk.Sciezka i w stanie (przeniesiony: z, na, kiedy, commit), wpis w dzienniku;
#   - zadnego -> usuniety u autora: stan neutralny, NIE blad, wpis w dzienniku raz;
#   - kilka -> nie zgaduje: blad przy skillu (nie sieciowy, wiec nie ponawiany).
# Kandydatow szukamy najpierw pod katalogiem skilli zrodla (Sciezka z bazy), dopiero
# potem w calym repo - impeccable ma ten sam skill w ~20 kopiach dla roznych narzedzi.
function Szukaj-Przenosin($z, [string]$kat, $stan, [string]$commit) {
  $r = Wolaj-Git $kat @("ls-tree", "-r", "--name-only", "--full-tree", "origin/$($z.Galaz)")
  if (-not $r.ok) { throw "git ls-tree w źródle $($z.Id): $($r.powod)" }
  $zSkillem = @{}; $poNazwie = @{}
  foreach ($l in ($r.tekst -split "`n")) {
    $l = $l.Trim()
    if (-not $l.EndsWith("/SKILL.md")) { continue }
    $d = $l.Substring(0, $l.Length - 9)
    $zSkillem[$d] = $true
    $n = ($d -split '/')[-1]
    if (-not $poNazwie.ContainsKey($n)) { $poNazwie[$n] = New-Object System.Collections.ArrayList }
    [void]$poNazwie[$n].Add($d)
  }
  $teraz = Teraz
  $krotko = $(if ($commit) { $commit.Substring(0, [math]::Min(7, $commit.Length)) } else { "?" })
  foreach ($sk in $z.Skille) {
    $x = Stan-Skilla $stan $sk
    $sk.Usuniety = $false; $sk.Niepewny = $false
    $bylUsuniety = [bool]$x.usuniety
    if ($zSkillem.ContainsKey($sk.SciezkaWBazie)) {
      # na miejscu wskazanym w bazie (takze: autor wrocil ze skillem na stare miejsce)
      # (zapis o przenosinach zostaje jako historia, gdy baza wskazuje juz nowe miejsce)
      if ($x.przeniesiony -and "$($x.przeniesiony.na)" -ne $sk.SciezkaWBazie) {
        Dziennik "przeniesiony" $sk.Nazwa "skill jest tam, gdzie wskazuje baza ($($sk.SciezkaWBazie)) - zapis o przenosinach zdjety"
        $x.przeniesiony = $null
      }
      $sk.Sciezka = $sk.SciezkaWBazie
    } elseif ($zSkillem.ContainsKey($sk.Sciezka)) {
      # juz wczesniej znaleziony w nowym miejscu (zapis w stanie) - nic nowego
    } else {
      $kand = @()
      if ($poNazwie.ContainsKey($sk.NazwaWRepo)) { $kand = @($poNazwie[$sk.NazwaWRepo]) }
      $pre = "$($z.Sciezka)".Trim('/')
      if ($pre -and $kand.Count -gt 1) {
        $podZrodlem = @($kand | Where-Object { $_.StartsWith($pre + "/") })
        if ($podZrodlem.Count -ge 1) { $kand = $podZrodlem }
      }
      if ($kand.Count -eq 1) {
        $stara = $sk.Sciezka
        $sk.Sciezka = $kand[0]
        $x.przeniesiony = @{ z = $sk.SciezkaWBazie; na = $kand[0]; kiedy = $teraz; commit = $commit }
        Dziennik "przeniesiony" $sk.Nazwa "autor przeniosl skill w swoim repo: $stara -> $($kand[0]) (commit $krotko) - biore go z nowego miejsca"
        Pisz "  $($sk.Folder): autor przeniósł go w swoim repo ($stara -> $($kand[0])) - biorę go z nowego miejsca."
      } elseif ($kand.Count -eq 0) {
        $sk.Usuniety = $true
        if (-not $x.usuniety -or "$($x.usuniety.sciezka)" -ne $sk.Sciezka) {
          $x.usuniety = @{ od = $teraz; sciezka = $sk.Sciezka; commit = $commit }
          Dziennik "usuniety" $sk.Nazwa "autor usunal ten skill ze zrodla (nie ma go pod $($sk.Sciezka) ani nigdzie indziej w repo, commit $krotko) - kopia u Ciebie zostaje nietknieta i dziala dalej"
          Pisz "  $($sk.Folder): autor usunął go ze swojego repo - Twoja kopia zostaje nietknięta."
        }
        continue
      } else {
        $sk.Niepewny = $true
        $x.blad = "autor przeniósł ten skill, a w źródle jest kilka katalogów o tej nazwie ($(($kand | Select-Object -First 4) -join ', ')) - nie zgaduję, który jest właściwy; trzeba wpisać Sciezka w bazie skilli"
        Blad $sk.Nazwa $x.blad
      }
    }
    if ($bylUsuniety -and -not $sk.Usuniety) {
      Dziennik "wrocil" $sk.Nazwa "skill znow jest w zrodle ($($sk.Sciezka)) - wraca do zwyklej opieki"
    }
    $x.usuniety = $null
  }
}

# Przygotowanie wlasnej kopii zrodla po kroku pobrania ($pobranie - wynik Krok-Pobrania
# po ponowieniach; $null przy -BezSieci): przenosiny i usuniecia u autora, rozpakowanie
# (z ponowieniami), najnowszy commit. Zwraca commit i date albo powod porazki.
function Przygotuj-Zrodlo($z, [bool]$zSieci, $pobranie, $stan) {
  $w = [pscustomobject]@{ ok = $false; katalog = (Katalog-Repo $z); commit = ""; data = ""; powod = ""; pobrano = $false }
  $kat = $w.katalog
  $jest = Test-Path -LiteralPath (Join-Path $kat ".git")
  if (-not $zSieci) {
    if (-not $jest) { $w.powod = "nie mam jeszcze kopii tego źródła, a sprawdzam bez sieci"; return $w }
    $url = Wolaj-Git $kat @("config", "--get", "remote.origin.url")
    if ((-not $url.ok) -or ($url.tekst.Trim() -ne $z.Adres)) { $w.powod = "adres źródła się zmienił, a bez sieci nie mogę pobrać nowego"; return $w }
  } elseif ($null -eq $pobranie -or -not $pobranie.ok) {
    $w.powod = $(if ($null -eq $pobranie) { "pobranie ze źródła nie ruszyło" } else { Opis-Porazki-Pobrania $z $pobranie "pobranie ze źródła" })
    # kopie z poprzedniego razu mamy - commit podajemy, ale ok = $false: to NIE jest swieze sprawdzenie
    if ($jest) {
      $c = Wolaj-Git $kat @("log", "-1", "--format=%H%x09%cI", "origin/$($z.Galaz)")
      if ($c.ok -and $c.tekst.Trim()) { $cz = $c.tekst.Trim() -split "`t"; $w.commit = $cz[0]; $w.data = $cz[1] }
    }
    return $w
  } else { $w.pobrano = $true }
  $c = Wolaj-Git $kat @("log", "-1", "--format=%H%x09%cI", "origin/$($z.Galaz)")
  if (-not $c.ok -or -not $c.tekst.Trim()) { $w.powod = "nie umiem odczytać najnowszego commita: $($c.powod)"; return $w }
  $cz = $c.tekst.Trim() -split "`t"
  try { Szukaj-Przenosin $z $kat $stan $cz[0] }
  catch { $w.powod = "nie udało się sprawdzić, czy autor coś przeniósł: $($_.Exception.Message)"; return $w }
  $roz = $null
  if ($zSieci) { $roz = (Z-Ponowieniem @([pscustomobject]@{ Kto = $z.Id; Co = "rozpakowanie plików skilli"; Krok = "Krok-Rozpakowania"; Z = $z }))[$z.Id] }
  else { $roz = Krok-Rozpakowania $z; $roz | Add-Member -NotePropertyName proby -NotePropertyValue 1 -Force }
  if (-not $roz.ok) { $w.powod = Opis-Porazki-Pobrania $z $roz "rozpakowanie plików skilli"; return $w }
  $w.commit = $cz[0]; $w.data = $cz[1]
  $w.ok = $true
  return $w
}

# Najnowsza wersja kazdego skilla ze zrodla: sciezka w repo -> (rel -> skrot).
# Jedno "git ls-tree" na zrodlo, bez tresci plikow.
function Najnowsze-Wersje($z, [string]$kat) {
  $wynik = @{}
  $r = Wolaj-Git $kat (@("ls-tree", "-r", "--full-tree", "origin/$($z.Galaz)", "--") + @($z.Skille | ForEach-Object { $_.Sciezka }))
  if (-not $r.ok) { throw "git ls-tree w źródle $($z.Id): $($r.powod)" }
  foreach ($l in ($r.tekst -split "`n")) {
    $m = [regex]::Match($l, '^\d+ blob ([0-9a-f]{40})\t(.+)$')
    if (-not $m.Success) { continue }
    $sciezka = $m.Groups[2].Value.Trim()
    foreach ($s in $z.Skille) {
      $pre = $s.Sciezka + "/"
      if ($sciezka.StartsWith($pre)) {
        if (-not $wynik.ContainsKey($s.Sciezka)) { $wynik[$s.Sciezka] = @{} }
        $wynik[$s.Sciezka][$sciezka.Substring($pre.Length)] = $m.Groups[1].Value
      }
    }
  }
  return $wynik
}

# CALA historia skilli ze zrodla - kazdy stan kazdego katalogu o nazwie skilla (z plikiem
# SKILL.md), takze sprzed przeniesien (np. u Matta skille wedrowaly z korzenia do
# skills/ i dalej do skills/engineering/). Jedno "git log --raw" na zrodlo, odtworzone
# commit po commicie wzdluz glownej linii (--first-parent -m: laczenie liczy sie wzgledem
# pierwszego rodzica). Wynik: nazwa w repo -> lista wersji od najnowszej.
function Historia-Zrodla($z, [string]$kat) {
  $nazwy = @{}
  foreach ($s in $z.Skille) { $nazwy[$s.NazwaWRepo] = $true }
  $wzorce = @($nazwy.Keys | ForEach-Object { ":(glob)**/$_/**" })
  $r = Wolaj-Git $kat (@("log", "--first-parent", "-m", "--root", "--reverse", "--raw", "--no-abbrev", "--no-renames",
                   "--format=C%x09%H%x09%cI", "origin/$($z.Galaz)", "--") + $wzorce) 300
  if (-not $r.ok) { throw "git log w źródle $($z.Id): $($r.powod)" }
  $katalogi = @{}      # sciezka katalogu -> (rel -> skrot)
  $wersje = @{}        # nazwa -> lista
  $widziane = @{}      # nazwa|odcisk -> $true
  $commit = ""; $data = ""
  $dotkniete = @{}
  $zamknij = {
    foreach ($d in @($dotkniete.Keys)) {
      $pl = $katalogi[$d]
      if ($null -eq $pl -or -not $pl.ContainsKey("SKILL.md")) { continue }
      $nazwa = ($d -split '/')[-1]
      $odc = (@($pl.Keys | Sort-Object | ForEach-Object { "$_=$($pl[$_])" }) -join "`n")
      $klucz = "$nazwa|$odc"
      if ($widziane.ContainsKey($klucz)) { continue }
      $widziane[$klucz] = $true
      if (-not $wersje.ContainsKey($nazwa)) { $wersje[$nazwa] = New-Object System.Collections.ArrayList }
      $kopia = @{}; foreach ($k in $pl.Keys) { $kopia[$k] = $pl[$k] }
      [void]$wersje[$nazwa].Add([pscustomobject]@{ Commit = $commit; Data = $data; Katalog = $d; Pliki = $kopia })
    }
    $dotkniete.Clear()
  }
  foreach ($l in ($r.tekst -split "`n")) {
    if ($l.StartsWith("C`t")) {
      & $zamknij
      $cz = $l.TrimEnd() -split "`t"
      $commit = $cz[1]; $data = $cz[2]
      continue
    }
    if (-not $l.StartsWith(":")) { continue }
    $tab = $l.IndexOf("`t")
    if ($tab -lt 0) { continue }
    $pola = $l.Substring(1, $tab - 1) -split ' '
    if ($pola.Count -lt 5) { continue }
    $nowy = $pola[3]; $status = $pola[4]
    $sciezka = $l.Substring($tab + 1).Trim()
    $seg = $sciezka -split '/'
    for ($i = 0; $i -lt $seg.Count - 1; $i++) {
      if (-not $nazwy.ContainsKey($seg[$i])) { continue }
      $d = ($seg[0..$i] -join '/')
      $rel = ($seg[($i + 1)..($seg.Count - 1)] -join '/')
      if (-not $katalogi.ContainsKey($d)) { $katalogi[$d] = @{} }
      if ($status.StartsWith("D")) { [void]$katalogi[$d].Remove($rel) }
      else { $katalogi[$d][$rel] = $nowy }
      $dotkniete[$d] = $true
    }
  }
  & $zamknij
  foreach ($n in @($wersje.Keys)) { $wersje[$n].Reverse() }
  return $wersje
}

# ------------------------------------------------------------------ ocena

# Jaki jest skill w jednym miejscu instalacji:
#   brak       - nie ma katalogu
#   zgodny     - dokladnie najnowsza wersja ze zrodla
#   starszy    - dokladnie ktoras wczesniejsza wersja ze zrodla (Commit mowi ktora)
#   zmieniony  - nie odpowiada zadnej wersji z historii = zmieniony recznie albo obcy
function Ocen-Cel($sk, $cel, $lok, $najnowsza, $zapis, $zrodloStan, [scriptblock]$historia) {
  $o = [pscustomobject]@{ Stan = "brak"; Commit = ""; Data = ""; Pliki = $null; Powod = ""; Najblizszy = "" }
  if ($null -eq $lok) { return $o }
  if ($null -ne $najnowsza -and (Zgodne $lok $najnowsza)) {
    $o.Stan = "zgodny"; $o.Commit = $zrodloStan.commit; $o.Data = $zrodloStan.data; $o.Pliki = $najnowsza
    if ($zapis -and $zapis.pliki -and (Zgodne $lok $zapis.pliki) -and $zapis.commit) { $o.Commit = $zapis.commit; $o.Data = $zapis.data }
    return $o
  }
  if ($zapis -and $zapis.pliki -and $zapis.pliki.Count -gt 0 -and (Zgodne $lok $zapis.pliki)) {
    $o.Stan = "starszy"; $o.Commit = $zapis.commit; $o.Data = $zapis.data; $o.Pliki = $zapis.pliki
    return $o
  }
  $hist = & $historia
  $najlepsza = $null; $najlepszyWynik = -1
  foreach ($v in @($hist)) {
    if (Zgodne $lok $v.Pliki) {
      $o.Stan = "starszy"; $o.Commit = $v.Commit; $o.Data = $v.Data; $o.Pliki = $v.Pliki
      return $o
    }
    $rz = Roznica $lok $v.Pliki
    $wynik = $rz.Takie - $rz.Zmienione.Count - $rz.Dodane.Count - $rz.Brakujace.Count
    if ($wynik -gt $najlepszyWynik) { $najlepszyWynik = $wynik; $najlepsza = @($v, $rz) }
  }
  $o.Stan = "zmieniony"
  $o.Powod = "treść na dysku nie odpowiada żadnej wersji z historii źródła"
  if ($najlepsza) {
    $v = $najlepsza[0]; $rz = $najlepsza[1]
    $opis = @()
    if ($rz.Zmienione.Count) { $opis += "inne pliki: " + (($rz.Zmienione | Select-Object -First 4) -join ", ") + $(if ($rz.Zmienione.Count -gt 4) { " i $($rz.Zmienione.Count - 4) więcej" }) }
    if ($rz.Dodane.Count) { $opis += "dodane u Ciebie: " + (($rz.Dodane | Select-Object -First 4) -join ", ") + $(if ($rz.Dodane.Count -gt 4) { " i $($rz.Dodane.Count - 4) więcej" }) }
    if ($rz.Brakujace.Count) { $opis += "brakuje: " + (($rz.Brakujace | Select-Object -First 4) -join ", ") + $(if ($rz.Brakujace.Count -gt 4) { " i $($rz.Brakujace.Count - 4) więcej" }) }
    $o.Najblizszy = "najbliżej wersji z $(([datetime]$v.Data).ToString('yyyy-MM-dd')) (oznaczenie $($v.Commit.Substring(0,7))): " + ($opis -join "; ")
  }
  return $o
}

# ---------------------------------------------------------- operacje na plikach

function Kopiuj-Katalog([string]$z, [string]$do) {
  if (-not (Test-Path -LiteralPath $z -PathType Container)) { throw "nie ma katalogu do skopiowania: $z" }
  $baza = (Resolve-Path -LiteralPath $z).ProviderPath.TrimEnd('\')
  New-Item -ItemType Directory -Force -Path $do | Out-Null
  foreach ($f in @(Get-ChildItem -LiteralPath $baza -Recurse -Force)) {
    $rel = $f.FullName.Substring($baza.Length + 1)
    $cel = Join-Path $do $rel
    if ($f.PSIsContainer) { New-Item -ItemType Directory -Force -Path $cel | Out-Null }
    else {
      $kc = Split-Path -Parent $cel
      if (-not (Test-Path -LiteralPath $kc)) { New-Item -ItemType Directory -Force -Path $kc | Out-Null }
      [System.IO.File]::Copy($f.FullName, $cel, $true)
    }
  }
}

function Usun-Katalog([string]$k) {
  if (Test-Path -LiteralPath $k) { Remove-Item -LiteralPath $k -Recurse -Force }
}

# Kopia zapasowa przed podmiana: kopie\<folder>\<stempel>\<cel>\ + kopia.txt z opisem.
function Zrob-Kopie($sk, [string]$rodzaj, $cele, [hashtable]$zapisy, [string]$naCommit) {
  $stempel = Get-Date -Format 'yyyyMMdd-HHmmss'
  $kat = Join-Path (Join-Path $KatKopii $sk.Folder) $stempel
  $i = 1
  while (Test-Path -LiteralPath $kat) { $kat = Join-Path (Join-Path $KatKopii $sk.Folder) "$stempel-$i"; $i++ }
  New-Item -ItemType Directory -Force -Path $kat | Out-Null
  $opis = [ordered]@{ rodzaj = $rodzaj; skill = $sk.Nazwa; zrodlo = $sk.Zrodlo; kiedy = (Teraz); na = $naCommit; cele = (@($cele | ForEach-Object { $_.Id }) -join ",") }
  foreach ($c in $cele) {
    $zrodlowy = Join-Path $c.Katalog $sk.Folder
    Kopiuj-Katalog $zrodlowy (Join-Path $kat $c.Id)
    $zp = $zapisy[$c.Id]
    $opis["$($c.Id).commit"] = "$($zp.commit)"
    $opis["$($c.Id).data"] = "$($zp.data)"
    $opis["$($c.Id).stan"] = "$($zp.stan)"
    # odcisk kopii - przy cofnieciu sprawdzamy, ze wraca dokladnie to, co zabralismy
    $lok = Odcisk-Lokalny (Join-Path $kat $c.Id)
    $spis = @($lok.Keys | Sort-Object | ForEach-Object { "$_=$($lok[$_][0])" })
    [System.IO.File]::WriteAllLines((Join-Path $kat "$($c.Id).spis"), [string[]]$spis, (Bez-Bom))
  }
  Zapisz-Klucze (Join-Path $kat "kopia.txt") $opis
  # porzadek: najstarsze kopie ponad limit ida precz
  $wszystkie = @(Get-ChildItem -LiteralPath (Join-Path $KatKopii $sk.Folder) -Directory | Sort-Object Name)
  if ($wszystkie.Count -gt $KOPII_NA_SKILL) {
    foreach ($d in ($wszystkie | Select-Object -First ($wszystkie.Count - $KOPII_NA_SKILL))) {
      try { Remove-Item -LiteralPath $d.FullName -Recurse -Force; Dziennik "kopia" $sk.Nazwa "usunieta najstarsza kopia $($d.Name) (limit $KOPII_NA_SKILL)" }
      catch { Dziennik "uwaga" $sk.Nazwa "nie udalo sie usunac starej kopii $($d.FullName): $($_.Exception.Message)" }
    }
  }
  return $kat
}

# Podmiana katalogu skilla na wersje z kopii zrodla. Najpierw nowa wersja do katalogu
# tymczasowego obok stanu (ten sam dysk), dopiero potem zamiana - skill nigdy nie
# stoi w polowie skopiowany. Po zamianie sprawdzamy odcisk z oczekiwanym.
function Wgraj-Wersje([string]$skad, [string]$dokad, $oczekiwane) {
  $tmp = Join-Path $KatTmp ([guid]::NewGuid().ToString("N").Substring(0, 12))
  Kopiuj-Katalog $skad $tmp
  $spr = Odcisk-Lokalny $tmp
  if (-not (Zgodne $spr $oczekiwane)) { Usun-Katalog $tmp; throw "kopia źródła nie zgadza się z wersją z gita (pliki w $skad)" }
  $rodzic = Split-Path -Parent $dokad
  if (-not (Test-Path -LiteralPath $rodzic)) { New-Item -ItemType Directory -Force -Path $rodzic | Out-Null }
  Usun-Katalog $dokad
  try { Move-Item -LiteralPath $tmp -Destination $dokad }
  catch { Kopiuj-Katalog $tmp $dokad; Usun-Katalog $tmp }
  $po = Odcisk-Lokalny $dokad
  if (-not (Zgodne $po $oczekiwane)) { throw "po wgraniu $dokad nie zgadza się z wersją ze źródła" }
}

function Opisy-Zmian($z, [string]$kat, [string]$od, [string]$do, [string[]]$sciezki) {
  if (-not $od -or -not $do -or $od -eq $do) { return ,@() }
  $r = Wolaj-Git $kat (@("log", "--format=%h %cs %s", "-n", "15", "$od..$do", "--") + @($sciezki | Where-Object { $_ }))
  if (-not $r.ok) { return ,@("(nie udało się odczytać opisów zmian: $($r.powod))") }
  return ,@(($r.tekst -split "`n") | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
}

# ------------------------------------------------------------ glowny przebieg

# Wykrywanie dla wszystkich zrodel: pobranie, porownanie kazdego skilla w kazdym
# miejscu instalacji, przejecie pod opieke tego, co jest wersja ze zrodla. Zwraca
# kontekst dla dalszych krokow (instalacja/aktualizacja): kopie zrodel i najnowsze wersje.
function Wykryj($stan, $zrodla, $cele, [bool]$zSieci) {
  $ctx = @{}
  $teraz = Teraz
  $pierwszy = (-not $stan.przejeto)
  # Najpierw siec dla wszystkich zrodel naraz (rundami, z ponowieniami), potem reszta.
  $pobrania = @{}
  if ($zSieci) {
    $zad = @($zrodla | Where-Object { $_.Rodzaj -eq "skille" } | ForEach-Object { [pscustomobject]@{ Kto = $_.Id; Co = "pobranie ze źródła"; Krok = "Krok-Pobrania"; Z = $_ } })
    if ($zad.Count -gt 0) { $pobrania = Z-Ponowieniem $zad }
  }
  foreach ($z in $zrodla) {
    if ($z.Rodzaj -ne "skille") {
      $stan.zrodla[$z.Id] = @{ rodzaj = $z.Rodzaj; blad = ""; sprawdzono = $teraz; commit = ""; data = "" }
      continue
    }
    if (-not $stan.zrodla.ContainsKey($z.Id)) { $stan.zrodla[$z.Id] = @{} }
    $zs = $stan.zrodla[$z.Id]
    $zs.rodzaj = $z.Rodzaj
    $p = $null
    try { $p = Przygotuj-Zrodlo $z $zSieci $pobrania[$z.Id] $stan }
    catch { $p = [pscustomobject]@{ ok = $false; katalog = (Katalog-Repo $z); commit = ""; data = ""; powod = "przygotowanie kopii źródła się wywróciło: $($_.Exception.Message)"; pobrano = $false } }
    $zs.sprawdzono = $teraz
    if (-not $p.ok) {
      $zs.blad = $p.powod
      $zs.bladOd = $(if ($zs.bladOd) { $zs.bladOd } else { $teraz })
      Blad $z.Id "źródło $($z.Nazwa): $($p.powod)"
      if (-not $p.commit) {
        foreach ($sk in $z.Skille) { $x = Stan-Skilla $stan $sk; $x.blad = "nie mogę sprawdzić: $($p.powod)"; $x.sprawdzono = $teraz }
        continue
      }
      Pisz "  Sprawdzam na podstawie kopii z poprzedniego razu (commit $($p.commit.Substring(0,7)))."
    } else {
      $zs.blad = ""; $zs.bladOd = ""
      $zs.pobrano = $teraz
    }
    $zs.commit = $p.commit; $zs.data = $p.data
    $najnowsze = $null
    try { $najnowsze = Najnowsze-Wersje $z $p.katalog }
    catch { Blad $z.Id "$($_.Exception.Message)"; foreach ($sk in $z.Skille) { (Stan-Skilla $stan $sk).blad = "$($_.Exception.Message)" }; continue }
    $hist = $null
    $historiaZrodla = { if ($null -eq $script:HistTmp) { $script:HistTmp = Historia-Zrodla $z $p.katalog }; return $script:HistTmp }
    $script:HistTmp = $null
    $ctx[$z.Id] = [pscustomobject]@{ Katalog = $p.katalog; Commit = $p.commit; Data = $p.data; Najnowsze = $najnowsze; Swieze = $p.ok }
    foreach ($sk in $z.Skille) {
      $x = Stan-Skilla $stan $sk
      $x.sprawdzono = $teraz
      # kilka kandydatow po przenosinach - blad juz zapisany w Szukaj-Przenosin
      if ($sk.Niepewny) { continue }
      if ($sk.Usuniety) {
        # Autor usunal skill: nie blad, nic do aktualizowania. Kopie u uzytkownika zostaja;
        # zapis zdejmujemy tylko tam, gdzie katalogu juz nie ma (ktos go skasowal).
        $x.blad = ""; $x.najnowszy = $null
        foreach ($c in $cele) {
          if ($x.cele.ContainsKey($c.Id) -and -not (Test-Path -LiteralPath (Join-Path $c.Katalog $sk.Folder))) {
            Dziennik "zniknal" $sk.Nazwa "$($c.Nazwa): katalogu $($sk.Folder) juz nie ma - zdejmuje z opieki"
            $x.cele.Remove($c.Id)
          }
        }
        continue
      }
      $x.blad = $(if ($p.ok) { "" } else { "dziś nie udało się sprawdzić nowej wersji: $($p.powod)" })
      $najn = $najnowsze[$sk.Sciezka]
      if ($null -eq $najn -or $najn.Count -eq 0) {
        # Stara "najnowsza wersja" nie moze zostac - 2026-09-30 aktualizacja retro poszla
        # wlasnie na niej, spod sciezki, ktorej w zrodle juz nie bylo.
        $x.najnowszy = $null
        $x.blad = "w źródle nie ma już tego skilla pod $($sk.Sciezka)"
        Blad $sk.Nazwa $x.blad
        continue
      }
      $x.najnowszy = @{ commit = $p.commit; data = $p.data; pliki = $najn }
      foreach ($c in $cele) {
        if (-not $c.Jest) { if ($x.cele.ContainsKey($c.Id)) { $x.cele.Remove($c.Id) }; continue }
        $zapis = $x.cele[$c.Id]
        $lok = Odcisk-Lokalny (Join-Path $c.Katalog $sk.Folder)
        $histSkilla = { $h = & $historiaZrodla; $l = $h[$sk.NazwaWRepo]; if ($null -eq $l) { return ,@() }; return ,@($l) }
        $o = $null
        try { $o = Ocen-Cel $sk $c $lok $najn $zapis $p $histSkilla }
        catch { Blad $sk.Nazwa "ocena w $($c.Nazwa): $($_.Exception.Message)"; continue }
        if ($o.Stan -eq "brak") {
          if ($zapis) {
            Dziennik "zniknal" $sk.Nazwa "$($c.Nazwa): katalogu $($sk.Folder) juz nie ma - zdejmuje z opieki"
            $x.cele.Remove($c.Id)
          }
          continue
        }
        if (-not $zapis) {
          $zapis = @{ opieka = $false; jak = ""; od = ""; commit = ""; data = ""; pliki = @{}; stan = ""; powod = ""; najblizszy = ""; wstrzymany = $false }
          $x.cele[$c.Id] = $zapis
        }
        $zapis.stan = $o.Stan; $zapis.powod = $o.Powod; $zapis.najblizszy = $o.Najblizszy
        if ($o.Stan -eq "zgodny" -or $o.Stan -eq "starszy") {
          if (-not $zapis.opieka) {
            $zapis.opieka = $true; $zapis.jak = "przejety"; $zapis.od = $teraz
            Dziennik "przejety" $sk.Nazwa "$($c.Nazwa): wersja ze zrodla $($z.Id), commit $($o.Commit.Substring(0,7)) z $($o.Data) ($($o.Stan))"
          } elseif ($zapis.commit -and $zapis.commit -ne $o.Commit -and -not (Zgodne $lok $zapis.pliki)) {
            Dziennik "rozpoznany" $sk.Nazwa "$($c.Nazwa): na dysku inna wersja ze zrodla niz zapisana ($($zapis.commit.Substring(0,7)) -> $($o.Commit.Substring(0,7)))"
          }
          $zapis.commit = $o.Commit; $zapis.data = $o.Data; $zapis.pliki = (Odcisk-Do-Stanu $lok $o.Pliki)
        } else {
          if ($zapis.opieka) {
            Dziennik "zmieniony" $sk.Nazwa "$($c.Nazwa): tresc rozni sie od kazdej wersji ze zrodla - NIE aktualizuje, dopoki nie zdecydujesz. $($o.Najblizszy)"
          } elseif (-not $zapis.od) {
            $zapis.od = $teraz
            Dziennik "zmieniony" $sk.Nazwa "$($c.Nazwa): przy pierwszym spisie - nie odpowiada zadnej wersji ze zrodla, nie biore pod opieke. $($o.Najblizszy)"
          }
          $zapis.opieka = $false
        }
      }
    }
  }
  $stan.sprawdzono = $teraz
  if ($pierwszy) { $stan.przejeto = $teraz }
  return $ctx
}

function Opis-Commita([string]$c, [string]$d) {
  if (-not $c) { return "?" }
  $k = $c.Substring(0, [math]::Min(7, $c.Length))
  if ($d) { try { return "$k z $(([datetime]$d).ToString('yyyy-MM-dd'))" } catch { return $k } }
  return $k
}

# Aktualizacja jednego skilla we wszystkich miejscach, w ktorych jest pod opieka i ma
# starsza wersje. $jawnie = klikniecie / -Skill (zdejmuje wstrzymanie po cofnieciu),
# $wymus = zgoda na nadpisanie zmienionego recznie.
function Aktualizuj-Skill($stan, $sk, $cele, $ctx, [bool]$jawnie, [bool]$wymus) {
  $x = $stan.skille[$sk.Nazwa]
  $k = $ctx[$sk.Zrodlo]
  if ($null -eq $x -or $null -eq $k -or $null -eq $x.najnowszy) { return 0 }
  if ($sk.Usuniety -or $sk.Niepewny) { return 0 }
  $najn = $x.najnowszy.pliki
  $doZrobienia = @()
  foreach ($c in $cele) {
    if (-not $c.Jest) { continue }
    $zp = $x.cele[$c.Id]
    if ($null -eq $zp) { continue }
    if ($zp.stan -eq "zgodny") { continue }
    if ($zp.stan -eq "zmieniony") {
      if ($wymus) { $doZrobienia += $c; continue }
      Pisz "  $($sk.Folder) ($($c.Nazwa)): zmieniony ręcznie - nie nadpisuję bez Twojej zgody."
      continue
    }
    if ($zp.stan -ne "starszy" -or -not $zp.opieka) { continue }
    if ($zp.wstrzymany -and -not $jawnie) {
      Pisz "  $($sk.Folder) ($($c.Nazwa)): po cofnięciu wstrzymany - nie aktualizuję sam."
      continue
    }
    $doZrobienia += $c
  }
  if ($doZrobienia.Count -eq 0) { return 0 }
  if (-not $k.Swieze) { Pisz "  $($sk.Folder): źródło nie zostało dziś sprawdzone - nie aktualizuję ze starej kopii."; return 0 }
  $skad = Join-Path $k.Katalog ($sk.Sciezka -replace '/', '\')
  # Zanim cokolwiek ruszymy: czy nowa wersja w ogole lezy w kopii zrodla. Bez tego
  # sprawdzenia 2026-09-30 retro poszlo do kopii i podmiany, ktora nie miala z czego wgrac.
  if (-not (Test-Path -LiteralPath (Join-Path $skad "SKILL.md"))) {
    Blad $sk.Nazwa "w kopii źródła nie ma nowej wersji ($skad) - nie ruszam Twojego skilla"
    return 0
  }

  $zapisy = @{}; foreach ($c in $doZrobienia) { $zapisy[$c.Id] = $x.cele[$c.Id] }
  $rodzaj = $(if ($wymus) { "nadpisanie" } else { "aktualizacja" })
  $kopia = $null
  try { $kopia = Zrob-Kopie $sk $rodzaj $doZrobienia $zapisy $k.Commit }
  catch { Blad $sk.Nazwa "nie udało się zrobić kopii zapasowej - NIE aktualizuję: $($_.Exception.Message)"; return 0 }

  $zrobione = 0
  foreach ($c in $doZrobienia) {
    $zp = $x.cele[$c.Id]
    $staryCommit = $zp.commit; $staraData = $zp.data
    $stareP = $zp.pliki
    try {
      Wgraj-Wersje $skad (Join-Path $c.Katalog $sk.Folder) $najn
    } catch {
      Blad $sk.Nazwa "$($c.Nazwa): podmiana się nie udała ($($_.Exception.Message)) - przywracam kopię"
      try {
        Usun-Katalog (Join-Path $c.Katalog $sk.Folder)
        Kopiuj-Katalog (Join-Path $kopia $c.Id) (Join-Path $c.Katalog $sk.Folder)
      } catch { Blad $sk.Nazwa "$($c.Nazwa): NIE UDAŁO SIĘ PRZYWRÓCIĆ KOPII z $kopia - przywróć ręcznie: $($_.Exception.Message)" }
      continue
    }
    $rz = Roznica-Wersji $stareP $najn
    $zp.commit = $k.Commit; $zp.data = $k.Data; $zp.pliki = $najn; $zp.stan = "zgodny"; $zp.powod = ""; $zp.najblizszy = ""
    $zp.opieka = $true; $zp.wstrzymany = $false
    if (-not $zp.jak) { $zp.jak = "zainstalowany" }
    # po przenosinach u autora zmiany sprzed przeprowadzki leza pod stara sciezka
    $opisy = Opisy-Zmian $null $k.Katalog $staryCommit $k.Commit @($sk.Sciezka, $(if ($x.przeniesiony) { "$($x.przeniesiony.z)" }))
    $x.zmiana = @{
      kiedy = (Teraz); rodzaj = $rodzaj; cel = $c.Id; z = $staryCommit; zData = $staraData; na = $k.Commit; naData = $k.Data
      dodane = @($rz.Dodane); zmienione = @($rz.Zmienione); usuniete = @($rz.Usuniete); kopia = $kopia; opisy = @($opisy)
    }
    $txt = "$($c.Nazwa): $(Opis-Commita $staryCommit $staraData) -> $(Opis-Commita $k.Commit $k.Data); pliki: +$($rz.Dodane.Count) ~$($rz.Zmienione.Count) -$($rz.Usuniete.Count); kopia: $kopia"
    Dziennik $rodzaj $sk.Nazwa $txt
    Pisz "  $($sk.Folder) - $txt"
    $zrobione++
  }
  return $zrobione
}

function Instaluj-Skill($stan, $sk, $cele, $ctx, [bool]$wymus) {
  $x = Stan-Skilla $stan $sk
  $k = $ctx[$sk.Zrodlo]
  if ($sk.Usuniety) { Pisz "  $($sk.Folder): autor usunął go ze swojego repo - nie ma czego instalować."; return 0 }
  if ($null -eq $k) { Blad $sk.Nazwa "nie mogę zainstalować - źródło $($sk.Zrodlo) nie jest dostępne"; return 0 }
  if ($null -eq $x.najnowszy) { Blad $sk.Nazwa "nie mogę zainstalować - brak wersji w źródle"; return 0 }
  $zrobione = 0
  foreach ($c in $cele) {
    if (-not $c.Jest) { continue }
    if ($x.cele.ContainsKey($c.Id)) { continue }
    if (Test-Path -LiteralPath (Join-Path $c.Katalog $sk.Folder)) {
      Pisz "  $($sk.Folder) ($($c.Nazwa)): katalog już jest, choć go nie znam - nie ruszam."
      continue
    }
    $skad = Join-Path $k.Katalog ($sk.Sciezka -replace '/', '\')
    try { Wgraj-Wersje $skad (Join-Path $c.Katalog $sk.Folder) $x.najnowszy.pliki }
    catch { Blad $sk.Nazwa "$($c.Nazwa): instalacja się nie udała: $($_.Exception.Message)"; continue }
    $x.cele[$c.Id] = @{ opieka = $true; jak = "zainstalowany"; od = (Teraz); commit = $k.Commit; data = $k.Data; pliki = $x.najnowszy.pliki; stan = "zgodny"; powod = ""; najblizszy = ""; wstrzymany = $false }
    Dziennik "instalacja" $sk.Nazwa "$($c.Nazwa): wersja $(Opis-Commita $k.Commit $k.Data) ze zrodla $($sk.Zrodlo)"
    Pisz "  $($sk.Folder) - zainstalowany dla $($c.Nazwa) (wersja $(Opis-Commita $k.Commit $k.Data))."
    $zrobione++
  }
  # Tam, gdzie juz byl w starszej wersji - "Zainstaluj" doprowadza go do najnowszej.
  $zrobione += Aktualizuj-Skill $stan $sk $cele $ctx $true $wymus
  return $zrobione
}

function Cofnij-Skill($stan, $sk, $cele) {
  $x = $stan.skille[$sk.Nazwa]
  $katS = Join-Path $KatKopii $sk.Folder
  if (-not (Test-Path -LiteralPath $katS)) { Blad $sk.Nazwa "nie ma żadnej kopii zapasowej tego skilla - nie ma czego cofać"; return 0 }
  $kopia = $null; $opis = $null
  foreach ($d in @(Get-ChildItem -LiteralPath $katS -Directory | Sort-Object Name -Descending)) {
    $o = Klucze-Z-Pliku (Join-Path $d.FullName "kopia.txt")
    if ($o["przywrocono"]) { continue }
    if ($o["rodzaj"] -eq "przed-cofnieciem") { continue }
    $kopia = $d.FullName; $opis = $o; break
  }
  if (-not $kopia) { Blad $sk.Nazwa "wszystkie kopie tego skilla zostały już przywrócone - nie ma czego cofać"; return 0 }
  $celeKopii = @("$($opis['cele'])" -split ',' | Where-Object { $_ })
  $doCofniecia = @($cele | Where-Object { $_.Jest -and ($celeKopii -contains $_.Id) })
  if ($doCofniecia.Count -eq 0) { Blad $sk.Nazwa "kopia $kopia nie dotyczy żadnego miejsca instalacji na tej maszynie"; return 0 }
  # To, co jest teraz, tez idzie do kopii - cofniecie ma sie dac cofnac.
  $zapisy = @{}; foreach ($c in $doCofniecia) { $zapisy[$c.Id] = $(if ($x) { $x.cele[$c.Id] } else { @{} }) }
  $obecne = @($doCofniecia | Where-Object { Test-Path -LiteralPath (Join-Path $_.Katalog $sk.Folder) })
  $kopiaObecnych = ""
  if ($obecne.Count -gt 0) {
    try { $kopiaObecnych = Zrob-Kopie $sk "przed-cofnieciem" $obecne $zapisy "" }
    catch { Blad $sk.Nazwa "nie udało się zabezpieczyć obecnej wersji - NIE cofam: $($_.Exception.Message)"; return 0 }
  }
  $zrobione = 0
  foreach ($c in $doCofniecia) {
    $zKopii = Join-Path $kopia $c.Id
    $docel = Join-Path $c.Katalog $sk.Folder
    try {
      Usun-Katalog $docel
      Kopiuj-Katalog $zKopii $docel
      # sprawdzenie co do bajtu wzgledem spisu zrobionego przy kopii
      $spis = @{}
      foreach ($l in [System.IO.File]::ReadAllLines((Join-Path $kopia "$($c.Id).spis"), [System.Text.Encoding]::UTF8)) {
        $i = $l.LastIndexOf('='); if ($i -gt 0) { $spis[$l.Substring(0, $i)] = $l.Substring($i + 1) }
      }
      $po = Odcisk-Lokalny $docel
      $zgodne = ($po.Count -eq $spis.Count)
      foreach ($rel in $spis.Keys) { if (-not $po.ContainsKey($rel) -or $po[$rel][0] -ne $spis[$rel]) { $zgodne = $false } }
      if (-not $zgodne) { throw "po przywróceniu pliki nie są identyczne z kopią" }
    } catch { Blad $sk.Nazwa "$($c.Nazwa): cofnięcie się nie udało: $($_.Exception.Message) (kopia: $kopia)"; continue }
    if ($x -and $x.cele.ContainsKey($c.Id)) {
      $zp = $x.cele[$c.Id]
      $zp.commit = "$($opis["$($c.Id).commit"])"; $zp.data = "$($opis["$($c.Id).data"])"
      $zp.stan = "$($opis["$($c.Id).stan"])"
      $zp.wstrzymany = $true
      $lok = Odcisk-Lokalny $docel
      $p = @{}; foreach ($rel in $lok.Keys) { $p[$rel] = $lok[$rel][1] }
      $zp.pliki = $p
    }
    Dziennik "cofniecie" $sk.Nazwa "$($c.Nazwa): przywrocona kopia $(Split-Path -Leaf $kopia) (wersja $(Opis-Commita "$($opis["$($c.Id).commit"])" "$($opis["$($c.Id).data"])")); dotychczasowa w $kopiaObecnych; codzienna aktualizacja wstrzymana dla tego skilla"
    if ($opis["rodzaj"] -eq "usuniecie") { Pisz "  $($sk.Folder) ($($c.Nazwa)): przywrócony z kopii zrobionej przed usunięciem ($($opis['kiedy']))." }
    else { Pisz "  $($sk.Folder) ($($c.Nazwa)): przywrócona wersja sprzed aktualizacji $($opis['kiedy'])." }
    $zrobione++
  }
  if ($zrobione -gt 0) {
    $opis["przywrocono"] = (Teraz)
    Zapisz-Klucze (Join-Path $kopia "kopia.txt") $opis
    if ($x) { $x.zmiana = @{ kiedy = (Teraz); rodzaj = "cofniecie"; kopia = $kopia; poprzednia = $kopiaObecnych; opisy = @() } }
  }
  return $zrobione
}

# Skasowanie u uzytkownika skilla, ktory AUTOR usunal ze zrodla (przycisk "Usun u mnie").
# Tylko takiego - innych skilli ten skrypt nie kasuje nigdy. Najpierw kopia zapasowa
# jak przed aktualizacja, wiec "cofnij" przywraca skill co do bajtu.
function Usun-Skill($stan, $sk, $cele) {
  if (-not $sk.Usuniety) { Blad $sk.Nazwa "kasuję tylko skille, które autor usunął ze swojego źródła - ten nadal u niego jest, więc go nie ruszam"; return 0 }
  $x = Stan-Skilla $stan $sk
  $obecne = @($cele | Where-Object { $_.Jest -and (Test-Path -LiteralPath (Join-Path $_.Katalog $sk.Folder)) })
  if ($obecne.Count -eq 0) { Pisz "  $($sk.Folder): nie masz go nigdzie - nie ma czego usuwać."; return 0 }
  $zapisy = @{}; foreach ($c in $obecne) { $zapisy[$c.Id] = $(if ($x.cele.ContainsKey($c.Id)) { $x.cele[$c.Id] } else { @{} }) }
  $kopia = $null
  try { $kopia = Zrob-Kopie $sk "usuniecie" $obecne $zapisy "" }
  catch { Blad $sk.Nazwa "nie udało się zrobić kopii zapasowej - NIE usuwam: $($_.Exception.Message)"; return 0 }
  $zrobione = 0
  foreach ($c in $obecne) {
    try { Usun-Katalog (Join-Path $c.Katalog $sk.Folder) }
    catch { Blad $sk.Nazwa "$($c.Nazwa): nie udało się usunąć: $($_.Exception.Message) (kopia: $kopia)"; continue }
    if ($x.cele.ContainsKey($c.Id)) { $x.cele.Remove($c.Id) }
    Dziennik "usuniecie" $sk.Nazwa "$($c.Nazwa): skasowany na Twoje zyczenie (autor usunal go ze zrodla); kopia: $kopia"
    Pisz "  $($sk.Folder) ($($c.Nazwa)): usunięty. Kopia: $kopia"
    $zrobione++
  }
  if ($zrobione -gt 0) { $x.zmiana = @{ kiedy = (Teraz); rodzaj = "usuniecie"; kopia = $kopia; opisy = @() } }
  return $zrobione
}

# ------------------------------------------------------------- stan dla okna

function Stan-Dla-Okna($stan, $zrodla, $cele) {
  $dzis = (Get-Date).ToString('yyyy-MM-dd')
  $wynikZ = @()
  $znane = @{}
  $licz = [ordered]@{ wBazie = 0; zgodne = 0; starsze = 0; zmienione = 0; brak = 0; usuniete = 0; bledy = 0; dzisZaktualizowane = 0 }
  foreach ($z in $zrodla) {
    $zs = Na-Slownik $stan.zrodla[$z.Id]
    $lista = @()
    foreach ($sk in $z.Skille) {
      $licz.wBazie++
      $znane[$sk.Folder] = $true
      $x = $stan.skille[$sk.Nazwa]
      $wc = @()
      $zbiorczy = "brak"
      foreach ($c in $cele) {
        if (-not $c.Jest) { continue }
        $zp = $null; if ($x) { $zp = $x.cele[$c.Id] }
        $lok = Odcisk-Lokalny (Join-Path $c.Katalog $sk.Folder)
        $st = "brak"
        if ($null -ne $lok) {
          if ($null -eq $zp -or -not $zp.stan) { $st = "nieznany" }
          elseif ($zp.pliki -and (Zgodne $lok $zp.pliki)) { $st = $zp.stan }
          elseif ($x.najnowszy -and (Zgodne $lok $x.najnowszy.pliki)) { $st = "zgodny" }
          elseif ($zp.stan -eq "zmieniony") { $st = "zmieniony" }
          else { $st = "zmieniony"; }
        }
        $wc += [pscustomobject]@{
          id = $c.Id; nazwa = $c.Nazwa; stan = $st
          commit = $(if ($zp) { "$($zp.commit)" } else { "" }); data = $(if ($zp) { "$($zp.data)" } else { "" })
          opieka = $(if ($zp) { [bool]$zp.opieka } else { $false }); wstrzymany = $(if ($zp) { [bool]$zp.wstrzymany } else { $false })
          jak = $(if ($zp) { "$($zp.jak)" } else { "" }); od = $(if ($zp) { "$($zp.od)" } else { "" })
          najblizszy = $(if ($zp) { "$($zp.najblizszy)" } else { "" })
          zmienionyOdSpisu = ($null -ne $lok -and $zp -and $zp.pliki -and $zp.pliki.Count -gt 0 -and -not (Zgodne $lok $zp.pliki) -and $st -eq "zmieniony" -and $zp.stan -ne "zmieniony")
        }
      }
      $stany = @($wc | ForEach-Object { $_.stan })
      # Blad sprawdzenia NIE przykrywa stanu - okno pokazuje oba: czerwone "nie udalo
      # sie sprawdzic" i to, co wiadomo z ostatniego udanego sprawdzenia.
      if ($stany -contains "zmieniony") { $zbiorczy = "zmieniony" }
      elseif ($stany -contains "starszy") { $zbiorczy = "starszy" }
      elseif ($stany -contains "nieznany") { $zbiorczy = "nieznany" }
      elseif ($stany -contains "zgodny") { $zbiorczy = "zgodny" }
      # Autor usunal skill - to wygrywa nad reszta: nie ma juz "najnowszej wersji",
      # wiec "aktualny" czy "starszy" nic by nie znaczyly. Kopia u uzytkownika dziala.
      $zainstalowany = (@($stany | Where-Object { $_ -ne "brak" }).Count -gt 0)
      if ($sk.Usuniety) { $zbiorczy = "usuniety" }
      $dzisAkt = $false
      if ($x -and $x.zmiana -and "$($x.zmiana.kiedy)".StartsWith($dzis) -and (@("cofniecie", "usuniecie") -notcontains $x.zmiana.rodzaj)) { $dzisAkt = $true }
      switch ($zbiorczy) { "zgodny" { $licz.zgodne++ } "starszy" { $licz.starsze++ } "zmieniony" { $licz.zmienione++ } "brak" { $licz.brak++ } "usuniety" { $licz.usuniete++ } default { } }
      if ($x -and $x.blad) { $licz.bledy++ }
      if ($dzisAkt) { $licz.dzisZaktualizowane++ }
      # Miejsca, w ktorych skilla brakuje, choc gdzie indziej jest (np. jest dla
      # Claude Code, nie ma dla Codeksa) - wtedy "Zainstaluj" ma sens mimo "aktualny".
      $brakujeW = @()
      if ($zbiorczy -ne "brak" -and -not $sk.Usuniety) { $brakujeW = @($wc | Where-Object { $_.stan -eq "brak" } | ForEach-Object { $_.nazwa }) }
      $lista += [pscustomobject]@{
        nazwa = $sk.Nazwa; folder = $sk.Folder; opis = $sk.Opis; robocza = $sk.Robocza; sciezka = $sk.Sciezka
        zainstalowany = $zainstalowany
        usuniety = $(if ($sk.Usuniety -and $x -and $x.usuniety) { [pscustomobject]$x.usuniety } elseif ($sk.Usuniety) { [pscustomobject]@{ od = ""; sciezka = $sk.Sciezka; commit = "" } } else { $null })
        przeniesiony = $(if ($x -and $x.przeniesiony -and "$($x.przeniesiony.na)" -eq $sk.Sciezka) { [pscustomobject]$x.przeniesiony } else { $null })
        stan = $zbiorczy; dzisZaktualizowany = $dzisAkt; blad = $(if ($x) { "$($x.blad)" } else { "" }); brakujeW = $brakujeW
        sprawdzono = $(if ($x) { "$($x.sprawdzono)" } else { "" })
        najnowszy = $(if ($x -and $x.najnowszy) { [pscustomobject]@{ commit = "$($x.najnowszy.commit)"; data = "$($x.najnowszy.data)" } } else { $null })
        cele = $wc
        zmiana = $(if ($x -and $x.zmiana) { [pscustomobject]$x.zmiana } else { $null })
      }
    }
    $wynikZ += [pscustomobject]@{
      id = $z.Id; nazwa = $z.Nazwa; opis = $z.Opis; rodzaj = $z.Rodzaj; uwaga = $z.Uwaga; adres = $z.Adres; galaz = $z.Galaz
      commit = "$($zs.commit)"; data = "$($zs.data)"; sprawdzono = "$($zs.sprawdzono)"; pobrano = "$($zs.pobrano)"
      blad = "$($zs.blad)"; bladOd = "$($zs.bladOd)"; skille = $lista
    }
  }
  $spoza = @()
  foreach ($c in $cele) {
    if (-not $c.Jest -or -not (Test-Path -LiteralPath $c.Katalog)) { continue }
    foreach ($d in @(Get-ChildItem -LiteralPath $c.Katalog -Directory -Force | Where-Object { -not $_.Name.StartsWith('.') })) {
      if (-not $znane.ContainsKey($d.Name)) { $spoza += [pscustomobject]@{ folder = $d.Name; cel = $c.Id } }
    }
  }
  return [pscustomobject]@{
    wygenerowano = (Teraz); dom = $Dom; katalog = $Katalog; stanPlik = $PlikStanu; dziennik = $PlikDzien; kopie = $KatKopii
    przejeto = "$($stan.przejeto)"; sprawdzono = "$($stan.sprawdzono)"
    cele = @($cele | ForEach-Object { [pscustomobject]@{ id = $_.Id; nazwa = $_.Nazwa; katalog = $_.Katalog; jest = $_.Jest } })
    znacznik = [pscustomobject](Klucze-Z-Pliku $PlikZnacz)
    operacja = [pscustomobject](Klucze-Z-Pliku $PlikOper)
    liczniki = [pscustomobject]$licz
    zrodla = $wynikZ; spozaBazy = $spoza
  }
}

# JSON bez polskich liter wprost (\uXXXX) - okno czyta wydruk z pliku przekierowania,
# a strona kodowa konsoli nie ma tu nic do gadania.
function Na-Json($o) {
  $t = $o | ConvertTo-Json -Depth 12 -Compress
  return [regex]::Replace($t, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
}

# ------------------------------------------------------------------- start

$zrodla = $null
try { $zrodla = Wczytaj-Katalog }
catch {
  if ($Json) { Write-Output (Na-Json ([pscustomobject]@{ powod = "nie udało się wczytać bazy skilli: $($_.Exception.Message)" })) }
  else { Write-Output "BŁĄD: nie udało się wczytać bazy skilli: $($_.Exception.Message)" }
  exit 1
}
$cele = Cele-Instalacji

if ($Tryb -eq "stan") {
  try {
    $stan = Wczytaj-Stan
    Zastosuj-Przenosiny $stan $zrodla
    $o = Stan-Dla-Okna $stan $zrodla $cele
    if ($Json) { Write-Output (Na-Json $o) }
    else {
      $l = $o.liczniki
      Write-Output "Skilli w bazie: $($l.wBazie); aktualne: $($l.zgodne); starsze: $($l.starsze); zmienione ręcznie: $($l.zmienione); niezainstalowane: $($l.brak); usunięte przez autora: $($l.usuniete); z błędem: $($l.bledy)"
      Write-Output "Ostatnie sprawdzenie: $($o.sprawdzono); przejęto pod opiekę: $($o.przejeto)"
      foreach ($z in $o.zrodla) {
        Write-Output ""
        Write-Output "== $($z.nazwa) [$($z.id)] $(if ($z.blad) { 'BŁĄD: ' + $z.blad })"
        foreach ($s in $z.skille) {
          $gdzie = (@($s.cele | Where-Object { $_.stan -ne 'brak' } | ForEach-Object { "$($_.id):$($_.stan)" }) -join ' ')
          Write-Output ("  {0,-32} {1,-10} {2}{3}" -f $s.folder, $s.stan, $gdzie, $(if ($s.blad) { "  [BŁĄD: " + $s.blad + "]" } else { "" }))
        }
      }
      if (@($o.spozaBazy).Count) { Write-Output ""; Write-Output ("Spoza bazy: " + ((@($o.spozaBazy) | ForEach-Object { "$($_.folder) ($($_.cel))" }) -join ", ")) }
    }
    exit 0
  } catch {
    if ($Json) { Write-Output (Na-Json ([pscustomobject]@{ powod = "odczyt stanu się wywrócił: $($_.Exception.Message)" })) }
    else { Write-Output "BŁĄD: odczyt stanu się wywrócił: $($_.Exception.Message)" }
    exit 1
  }
}

if ((@("instaluj", "cofnij", "usun") -contains $Tryb) -and -not $Skill -and -not ($Tryb -eq "instaluj" -and $ZeZrodla)) {
  Write-Output "BŁĄD: tryb $Tryb wymaga -Skill <nazwa>$(if ($Tryb -eq 'instaluj') { ' albo -ZeZrodla <id>' })"
  exit 2
}

# Wybor skilli, ktorych dotyczy polecenie (po nazwie z bazy albo po nazwie katalogu).
$wybrane = @()
foreach ($z in $zrodla) {
  foreach ($sk in $z.Skille) {
    if ($Skill -and ($sk.Nazwa -ne $Skill) -and ($sk.Folder -ne $Skill)) { continue }
    if ($ZeZrodla -and ($z.Id -ne $ZeZrodla)) { continue }
    $wybrane += $sk
  }
}
if (($Skill -or $ZeZrodla) -and $wybrane.Count -eq 0) {
  Write-Output "BŁĄD: nie ma w bazie skilla '$Skill'$(if ($ZeZrodla) { " w źródle '$ZeZrodla'" })"
  exit 2
}

# Jeden przebieg naraz na katalog domowy - przycisk w oknie i codzienny przebieg
# nie moga podmieniac tych samych plikow jednoczesnie.
$md5 = [System.Security.Cryptography.MD5]::Create()
$skrot = [BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Dom.ToLowerInvariant()))).Replace("-", "").Substring(0, 12)
$zamek = New-Object System.Threading.Mutex($false, "Local\MegaRuchacz-Skille-$skrot")
$moj = $false
try { $moj = $zamek.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $moj = $true }
if (-not $moj) {
  Write-Output "Inny przebieg skilli właśnie pracuje - spróbuj za chwilę."
  exit 3
}

$start = Teraz
$kod = 0
try {
  if (-not (Test-Path -LiteralPath $KatStanu)) { New-Item -ItemType Directory -Force -Path $KatStanu | Out-Null }
  $opisOperacji = "$Tryb$(if ($Skill) { ' ' + $Skill })$(if ($ZeZrodla) { ' zrodlo ' + $ZeZrodla })$(if ($Wymus) { ' (wymus)' })"
  Zapisz-Klucze $PlikOper ([ordered]@{ tryb = $Tryb; skill = $Skill; zrodlo = $ZeZrodla; start = $start; koniec = ""; wynik = "pracuje"; pid = $PID })

  $dzis = (Get-Date).ToString('yyyy-MM-dd')
  if ($Tryb -eq "codziennie") {
    $zn = Klucze-Z-Pliku $PlikZnacz
    if (($zn["dzien"] -eq $dzis) -and -not $Wymus) {
      Pisz "Skille sprawdzone już dziś ($($zn['start']), wynik: $($zn['wynik'])) - drugi raz tego samego dnia nie sprawdzam."
      Zapisz-Klucze $PlikOper ([ordered]@{ tryb = $Tryb; skill = ""; zrodlo = ""; start = $start; koniec = (Teraz); wynik = "pominiety"; pid = $PID })
      exit 0
    }
    # znacznik PRZED praca: wywrotka w polowie tez zostawia slad "dzis probowalem"
    Zapisz-Klucze $PlikZnacz ([ordered]@{ dzien = $dzis; start = $start; koniec = ""; wynik = "pracuje"; powod = ""; zaktualizowano = ""; pid = $PID })
  }

  $stan = Wczytaj-Stan
  Zastosuj-Przenosiny $stan $zrodla
  $pierwszy = (-not $stan.przejeto)
  $ctx = @{}
  # Usuniecie nie potrzebuje zrodel: to, ze autor skill usunal, wiadomo ze stanu.
  if ($Tryb -ne "usun") {
    Pisz "Sprawdzam źródła skilli$(if ($BezSieci) { ' (bez sieci)' })..."
    $ctx = Wykryj $stan $zrodla $cele (-not $BezSieci)
    Zapisz-Stan $stan
  }

  $zmian = 0
  switch ($Tryb) {
    "wykryj" { }
    "instaluj" {
      foreach ($sk in $wybrane) { $zmian += Instaluj-Skill $stan $sk $cele $ctx ([bool]$Wymus); Zapisz-Stan $stan }
    }
    "aktualizuj" {
      $jawnie = [bool]($Skill -or $ZeZrodla)
      foreach ($sk in $wybrane) { $zmian += Aktualizuj-Skill $stan $sk $cele $ctx $jawnie ([bool]$Wymus); Zapisz-Stan $stan }
    }
    "cofnij" {
      foreach ($sk in $wybrane) { $zmian += Cofnij-Skill $stan $sk $cele; Zapisz-Stan $stan }
    }
    "usun" {
      foreach ($sk in $wybrane) { $zmian += Usun-Skill $stan $sk $cele; Zapisz-Stan $stan }
    }
    "codziennie" {
      if ($pierwszy) {
        Pisz "Pierwszy przebieg na tym komputerze: tylko spisuję, co jest. Nowsze wersje pobiorę od następnego codziennego sprawdzenia."
        Dziennik "spis" "" "pierwszy przebieg - przejecie pod opieke bez zmian w plikach"
      } else {
        foreach ($sk in $wybrane) { $zmian += Aktualizuj-Skill $stan $sk $cele $ctx $false $false; Zapisz-Stan $stan }
      }
    }
  }
  Zapisz-Stan $stan

  $o = Stan-Dla-Okna $stan $zrodla $cele
  $l = $o.liczniki
  Pisz ""
  Pisz "Skilli w bazie: $($l.wBazie) - aktualne: $($l.zgodne), starsze wersje: $($l.starsze), zmienione ręcznie: $($l.zmienione), niezainstalowane: $($l.brak), usunięte przez autora: $($l.usuniete), z błędem: $($l.bledy). Zmienionych teraz: $zmian."
  if ($script:Bledy -gt 0) { $kod = 1 }
  $wynik = $(if ($script:Bledy -gt 0) { "blad" } else { "ok" })
  $powod = ""
  if ($script:Bledy -gt 0) { $powod = (@($script:Wydruk | Where-Object { $_.StartsWith("BŁĄD") } | Select-Object -First 3) -join " | ") }
  if ($Tryb -eq "codziennie") {
    Zapisz-Klucze $PlikZnacz ([ordered]@{ dzien = $dzis; start = $start; koniec = (Teraz); wynik = $wynik; powod = $powod; zaktualizowano = $zmian; pierwszy = $pierwszy; pid = $PID })
  }
  Zapisz-Klucze $PlikOper ([ordered]@{ tryb = $Tryb; skill = $Skill; zrodlo = $ZeZrodla; start = $start; koniec = (Teraz); wynik = $wynik; powod = $powod; zmian = $zmian; pid = $PID })
  Dziennik "przebieg" "" "$opisOperacji - wynik $wynik, zmian $zmian$(if ($powod) { ', ' + $powod })"
} catch {
  $kod = 1
  $t = "$($_.Exception.Message) (linia $($_.InvocationInfo.ScriptLineNumber))"
  Pisz "BŁĄD: przebieg się wywrócił: $t"
  Dziennik "wywrotka" "" "$Tryb - $t"
  try {
    if ($Tryb -eq "codziennie") { Zapisz-Klucze $PlikZnacz ([ordered]@{ dzien = (Get-Date).ToString('yyyy-MM-dd'); start = $start; koniec = (Teraz); wynik = "blad"; powod = "przebieg się wywrócił: $t"; zaktualizowano = ""; pid = $PID }) }
    Zapisz-Klucze $PlikOper ([ordered]@{ tryb = $Tryb; skill = $Skill; zrodlo = $ZeZrodla; start = $start; koniec = (Teraz); wynik = "blad"; powod = "przebieg się wywrócił: $t"; pid = $PID })
  } catch { Write-Error "skille: nie udalo sie zapisac znacznika po wywrotce: $($_.Exception.Message)" -ErrorAction Continue }
} finally {
  try { [System.IO.File]::WriteAllLines($PlikOperLog, [string[]]$script:Wydruk, (Bez-Bom)) }
  catch { Write-Error "skille: nie udalo sie zapisac wydruku operacji: $($_.Exception.Message)" -ErrorAction Continue }
  try { $zamek.ReleaseMutex() } catch { Write-Error "skille: zamek juz zwolniony: $($_.Exception.Message)" -ErrorAction Continue }
}
exit $kod
