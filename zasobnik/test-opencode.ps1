# Sprawdzenie pomiaru OpenCode w oknie MegaRuchacza: rozmowy z bazy SQLite
# (~\.local\share\opencode\opencode.db, narzedzia\koszt\opencode.ps1) i AGENTS.md OpenCode
# jako warstwa pamieci. Sztuczne katalogi domowe w %TEMP% - prawdziwy dom nie jest ruszany,
# nadzorca idzie z -Proba (nic nie zapisuje) i bez okna (-Raport = tresc okna tekstem).
#   powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File zasobnik\test-opencode.ps1 [-Zrodlo <repo>] [-Zostaw]
# Kod wyjscia: 0 = wszystkie proby przeszly, 1 = ktoras nie.
#
# Domy (bazy zakladane tu, przez winsqlite3.dll - ten sam silnik, ktorym czyta je pomiar;
# kolumny jak w prawdziwej bazie OpenCode 1.18, tresci zmyslone):
#   oc         - AGENTS.md z "## Co wiem"; w bazie: rozmowa dzis (Twoja wiadomosc 30 znakow
#                + 1000 znakow doklejonych przez OpenCode, dwie odpowiedzi), rozmowa sprzed
#                3 dni (odpowiedz z bledem i zerami, potem odpowiedz w starym zapisie bez
#                total), rozmowa rozwidlona (kopie wiadomosci z rozmowy dzisiejszej + jedna
#                wlasna), podagent, rozmowa cyklu wiedzy "lore-fakty" i rozmowa sprzed 20 dni.
#   oc-zla     - proba negatywna: "baza" to plik tekstowy, a OpenCode jest uzywany
#                (swieza prompt-history.jsonl); AGENTS.md bez sekcji "Co wiem".
#   oc-bez     - proba negatywna: baza poprawna, ale odpowiedzi modelu bez pola tokens
#                (OpenCode zmienil zapis) - zuzycie nie moze wyjsc "nic".
#   oc-duzy    - (kopia oc) proba negatywna rachunku: blok kierownika ponad prog - alarm
#                "opencode-otwarcie" i czerwony werdykt o OpenCode, nie o Claude Code.
#   oc-claudemd - (kopia oc) bez ~\.config\opencode\AGENTS.md: OpenCode czyta ~\.claude\CLAUDE.md
#                i rachunek liczy stamtad.
# Rachunek MegaRuchacza w OpenCode (od 06.10.2026): bloki MegaRuchacza i "Co wiem" z AGENTS.md
# OpenCode, bez Twoich wlasnych instrukcji; werdykt, karta otwarcia i rachunek pozycja po
# pozycji mowia o OpenCode (bez slowa "Claude"), a przy kilku narzedziach - o kazdym.
# Liczby do policzenia na kartce:
#   dzis: 20 500 + 21 400 (rozmowa dzisiejsza) + 30 600 (wlasna odpowiedz rozmowy
#   rozwidlonej, kopie sie nie licza) + 15 100 (podagent) = 87 600; cykl wiedzy (50 000)
#   i rozmowa sprzed 20 dni (99 999) - nie.
#   srednio: 26 000 (sprzed 3 dni, total = 25 000 + 1 000) / 7 = 3 714.
#   otwarcie: dzis 20 000 - 30 znakow / 3 (10) = 19 990, sprzed 3 dni 25 000 - 12 / 3 (4) =
#   24 996; mediana (19 990 + 24 996) / 2 = 22 493. Rozwidlona, podagent i cykl - pominiete.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Zostaw
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 }
catch { Write-Host "UWAGA: konsola nie przestawila sie na UTF-8 ($($_.Exception.Message)) - porownania z ogonkami moga pasc" }
$T = Join-Path $env:TEMP ("mr-test-opencode-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
$script:Zle = 0
$bezBom = New-Object System.Text.UTF8Encoding($false)

function Sprawdz([string]$co, [bool]$ok, [string]$szczegol = "") {
  $linia = $(if ($ok) { "OK    " } else { "BLAD  " }) + $co
  if ($szczegol -and -not $ok) { $linia += " -- $szczegol" }
  Write-Host $linia
  if (-not $ok) { $script:Zle++ }
}

function Odpal([string]$skrypt, [string[]]$argumenty) {
  $ErrorActionPreference = "Continue"
  $wy = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File $skrypt @argumenty 2>&1
  return [pscustomobject]@{ Kod = $LASTEXITCODE; Tekst = (($wy | ForEach-Object { "$_" }) -join "`n") }
}

function Klucze([string]$tekst) {
  $k = @{}
  foreach ($l in ($tekst -split "`n")) {
    $m = [regex]::Match($l, '^\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*:\s*(.*?)\s*$')
    if ($m.Success) { $k[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $k
}

# Zapis do bazy testowej - sqlite3_exec przez winsqlite3.dll (jak czytnik, bez zaleznosci).
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SqliteTestZapis {
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_open_v2", CallingConvention=CallingConvention.Cdecl)]
  static extern int Open(byte[] plik, out IntPtr db, int flagi, IntPtr vfs);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_exec", CallingConvention=CallingConvention.Cdecl)]
  static extern int Exec(IntPtr db, byte[] sql, IntPtr cb, IntPtr arg, out IntPtr blad);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_close_v2", CallingConvention=CallingConvention.Cdecl)]
  static extern int Zamknij(IntPtr db);
  public static void Wykonaj(string plik, string sql) {
    IntPtr db;
    int rc = Open(System.Text.Encoding.UTF8.GetBytes(plik + "\0"), out db, 0x02 | 0x04, IntPtr.Zero);
    if (rc != 0) { throw new Exception("otwarcie " + rc); }
    try {
      IntPtr b;
      rc = Exec(db, System.Text.Encoding.UTF8.GetBytes(sql + "\0"), IntPtr.Zero, IntPtr.Zero, out b);
      if (rc != 0) { throw new Exception("exec " + rc + " " + Marshal.PtrToStringAnsi(b)); }
    } finally { Zamknij(db); }
  }
}
'@

function Ms($czas) { return ([DateTimeOffset]$czas).ToUnixTimeMilliseconds() }
function Sql([string]$t) { return "'" + $t.Replace("'", "''") + "'" }
function Json($o) { return ($o | ConvertTo-Json -Compress -Depth 8) }

$schemat = @"
CREATE TABLE session (id text PRIMARY KEY, project_id text NOT NULL, workspace_id text, parent_id text, slug text NOT NULL,
  directory text NOT NULL, path text, title text NOT NULL, version text NOT NULL, cost real DEFAULT 0 NOT NULL,
  tokens_input integer DEFAULT 0, tokens_output integer DEFAULT 0, tokens_reasoning integer DEFAULT 0,
  tokens_cache_read integer DEFAULT 0, tokens_cache_write integer DEFAULT 0, agent text, model text,
  time_created integer NOT NULL, time_updated integer NOT NULL);
CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL);
CREATE TABLE part (id text PRIMARY KEY, message_id text NOT NULL, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL);
"@

function Sesja($id, $utw, $zm, [string]$rodzic = "", [string]$tytul = "Rozmowa testowa") {
  $r = "NULL"; if ($rodzic) { $r = Sql $rodzic }
  return "INSERT INTO session (id, project_id, parent_id, slug, directory, title, version, time_created, time_updated) VALUES " +
         "($(Sql $id), 'global', $r, 'slug', 'C:\projekt', $(Sql $tytul), '1.18.32', $(Ms $utw), $(Ms $zm));`n"
}
function Wiad($id, $sesja, $kiedy, $data) {
  return "INSERT INTO message (id, session_id, time_created, time_updated, data) VALUES ($(Sql $id), $(Sql $sesja), $(Ms $kiedy), $(Ms $kiedy), $(Sql (Json $data)));`n"
}
function Kawalek($id, $wiad, $sesja, $kiedy, $data) {
  return "INSERT INTO part (id, message_id, session_id, time_created, time_updated, data) VALUES ($(Sql $id), $(Sql $wiad), $(Sql $sesja), $(Ms $kiedy), $(Ms $kiedy), $(Sql (Json $data)));`n"
}
function Uzytk($kiedy) { return @{ role = "user"; time = @{ created = (Ms $kiedy) }; agent = "build"; model = @{ providerID = "test"; modelID = "model-test" } } }
function Odp($kiedy, $rodzic, $tokeny) {
  $d = @{ role = "assistant"; parentID = $rodzic; mode = "build"; agent = "build"; modelID = "model-test"; providerID = "test"
          time = @{ created = (Ms $kiedy); completed = (Ms $kiedy.AddSeconds(2)) }; path = @{ cwd = "C:\projekt"; root = "C:\projekt" } }
  if ($null -ne $tokeny) { $d.tokens = $tokeny }
  return $d
}
function Tok($we, $wy, $roz, $odc, $zap, [bool]$zTotal = $true) {
  $t = [ordered]@{ input = $we; output = $wy; reasoning = $roz; cache = [ordered]@{ read = $odc; write = $zap } }
  if ($zTotal) { $t.total = $we + $wy + $roz + $odc + $zap }
  return $t
}

# Rachunek MegaRuchacza w OpenCode (od 06.10.2026): blok kierownika w AGENTS.md OpenCode
# (6 000 znakow tresci) i Twoje wlasne instrukcje obok (10 000 znakow - poza rachunkiem).
# Start = ceil(dlugosc bloku / 3) + 21 (Co wiem, stala) + 14 (Biezace) - na kartce.
$BlokK = "<!-- MegaRuchacz:kierownik:start -->`n# MegaRuchacz - kierownik projektu (opencode / Codex CLI)`n`n" +
         ("Rozdaj zadania workerom. " * 240) + "`n<!-- MegaRuchacz:kierownik:koniec -->"
$Wlasne = "## Moje instrukcje`n`n" + ("Pisz krotko i po polsku. " * 400) + "`n"
$StartOc = [int][math]::Ceiling($BlokK.Length / 3.0) + 21 + 14
# Ponad prog ($AlarmCzesciOtwarcia = 15 000 tokenow): blok 50 000 znakow, ~16 700 tokenow.
$BlokDuzy = "<!-- MegaRuchacz:kierownik:start -->`n# MegaRuchacz - kierownik projektu (opencode / Codex CLI)`n`n" +
            ("Rozdaj zadania workerom. " * 2000) + "`n<!-- MegaRuchacz:kierownik:koniec -->"

function Dom([string]$nazwa, [string]$wariant) {
  $dom = Join-Path $T $nazwa
  $katOc = Join-Path $dom ".config\opencode"
  $katBazy = Join-Path $dom ".local\share\opencode"
  New-Item -ItemType Directory -Force -Path $katOc, $katBazy | Out-Null
  $agents = "# Instrukcje`n`nPisz po polsku.`n"
  if ($wariant -ne "zla") {
    # "Co wiem" (stala 21 + biezaca 14 tokenow), blok kierownika MegaRuchacza ($BlokK) i Twoje
    # wlasne instrukcje (~3 300 tokenow) - tych ostatnich rachunek MegaRuchacza liczyc nie moze.
    $agents = "## Co wiem`n`n### O użytkowniku`n`n- Sprzedaje olejki zapachowe.`n`n### Bieżące`n`n- [$((Get-Date).ToString('yyyy-MM-dd'))] Fakt testowy.`n`n## Zasady`n`nPisz po polsku.`n`n" +
              $BlokK + "`n`n" + $Wlasne
  }
  [System.IO.File]::WriteAllText((Join-Path $katOc "AGENTS.md"), $agents, $bezBom)
  $baza = Join-Path $katBazy "opencode.db"
  if ($wariant -eq "zla") {
    [System.IO.File]::WriteAllText($baza, "to nie jest baza SQLite", $bezBom)
    $katStanu = Join-Path $dom ".local\state\opencode"
    New-Item -ItemType Directory -Force -Path $katStanu | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $katStanu "prompt-history.jsonl"), "{`"input`":`"x`"}`n", $bezBom)
    return $dom
  }
  # dzis - kilka minut temu (zeby "dzis" nie wypadlo na wczoraj tuz po polnocy)
  $dzis = (Get-Date).AddMinutes(-10)
  if ($dzis.Date -ne (Get-Date).Date) { $dzis = (Get-Date).AddSeconds(-90) }
  $wcz = (Get-Date).Date.AddDays(-3).AddHours(10)
  $sql = $schemat
  if ($wariant -eq "bez") {
    $sql += Sesja "ses_bez" $dzis $dzis.AddSeconds(30)
    $sql += Wiad "msg_u" "ses_bez" $dzis.AddSeconds(1) (Uzytk $dzis.AddSeconds(1))
    $sql += Wiad "msg_a" "ses_bez" $dzis.AddSeconds(5) (Odp $dzis.AddSeconds(5) "msg_u" $null)
    [SqliteTestZapis]::Wykonaj($baza, $sql)
    return $dom
  }
  # rozmowa dzisiejsza
  $sql += Sesja "ses_dzis" $dzis $dzis.AddSeconds(60)
  $sql += Wiad "msg_u1" "ses_dzis" $dzis.AddSeconds(1) (Uzytk $dzis.AddSeconds(1))
  $sql += Kawalek "prt_u1a" "msg_u1" "ses_dzis" $dzis.AddSeconds(1) @{ type = "text"; text = ("a" * 30) }
  $sql += Kawalek "prt_u1b" "msg_u1" "ses_dzis" $dzis.AddSeconds(1) @{ type = "text"; text = ("b" * 1000); synthetic = $true }
  $sql += Wiad "msg_a1" "ses_dzis" $dzis.AddSeconds(2) (Odp $dzis.AddSeconds(2) "msg_u1" (Tok 20000 300 200 0 0))
  $sql += Wiad "msg_a2" "ses_dzis" $dzis.AddSeconds(4) (Odp $dzis.AddSeconds(4) "msg_u1" (Tok 1000 400 0 20000 0))
  # rozmowa sprzed 3 dni: najpierw odpowiedz z bledem (same zera), potem stary zapis bez total
  $sql += Sesja "ses_wcz" $wcz $wcz.AddMinutes(5)
  $sql += Wiad "msg_u2" "ses_wcz" $wcz.AddSeconds(1) (Uzytk $wcz.AddSeconds(1))
  $sql += Kawalek "prt_u2" "msg_u2" "ses_wcz" $wcz.AddSeconds(1) @{ type = "text"; text = "Hej, policz." }
  $sql += Wiad "msg_a0" "ses_wcz" $wcz.AddSeconds(2) (Odp $wcz.AddSeconds(2) "msg_u2" (Tok 0 0 0 0 0 $false))
  $sql += Wiad "msg_a3" "ses_wcz" $wcz.AddSeconds(9) (Odp $wcz.AddSeconds(9) "msg_u2" (Tok 25000 1000 0 0 0 $false))
  # rozmowa rozwidlona z dzisiejszej: kopie (czas sprzed jej powstania) + jedna wlasna
  $fork = $dzis.AddSeconds(20)
  $sql += Sesja "ses_fork" $fork $fork.AddSeconds(30)
  $sql += Wiad "msg_k1" "ses_fork" $fork (Uzytk $dzis.AddSeconds(1))
  $sql += Wiad "msg_k2" "ses_fork" $fork (Odp $dzis.AddSeconds(2) "msg_k1" (Tok 20000 300 200 0 0))
  $sql += Wiad "msg_k3" "ses_fork" $fork (Odp $dzis.AddSeconds(4) "msg_k1" (Tok 1000 400 0 20000 0))
  $sql += Wiad "msg_u4" "ses_fork" $fork.AddSeconds(1) (Uzytk $fork.AddSeconds(1))
  $sql += Wiad "msg_a4" "ses_fork" $fork.AddSeconds(3) (Odp $fork.AddSeconds(3) "msg_u4" (Tok 500 100 0 30000 0))
  # podagent dzisiejszej rozmowy
  $pod = $dzis.AddSeconds(25)
  $sql += Sesja "ses_pod" $pod $pod.AddSeconds(20) "ses_dzis"
  $sql += Wiad "msg_u5" "ses_pod" $pod.AddSeconds(1) (Uzytk $pod.AddSeconds(1))
  $sql += Wiad "msg_a5" "ses_pod" $pod.AddSeconds(3) (Odp $pod.AddSeconds(3) "msg_u5" (Tok 15000 100 0 0 0))
  # cykl wiedzy MegaRuchacza - najnowszy, ale nie Twoj
  $cyk = $dzis.AddSeconds(200)
  $sql += Sesja "ses_cykl" $cyk $cyk.AddSeconds(30) "" "lore-fakty"
  $sql += Wiad "msg_u6" "ses_cykl" $cyk.AddSeconds(1) (Uzytk $cyk.AddSeconds(1))
  $sql += Wiad "msg_a6" "ses_cykl" $cyk.AddSeconds(3) (Odp $cyk.AddSeconds(3) "msg_u6" (Tok 50000 0 0 0 0))
  # rozmowa sprzed 20 dni - poza kazdym oknem
  $st = (Get-Date).Date.AddDays(-20).AddHours(9)
  $sql += Sesja "ses_stara" $st $st.AddMinutes(1)
  $sql += Wiad "msg_u7" "ses_stara" $st.AddSeconds(1) (Uzytk $st.AddSeconds(1))
  $sql += Wiad "msg_a7" "ses_stara" $st.AddSeconds(3) (Odp $st.AddSeconds(3) "msg_u7" (Tok 99999 0 0 0 0 $false))
  [SqliteTestZapis]::Wykonaj($baza, $sql)
  return $dom
}

try {
  New-Item -ItemType Directory -Force -Path $T | Out-Null
  $koszt = Join-Path $Zrodlo "narzedzia\koszt-pamieci.ps1"
  $nadz = Join-Path $Zrodlo "zasobnik\nadzorca.ps1"
  $dOc = Dom "oc" "dobra"
  $dZla = Dom "oc-zla" "zla"
  $dBez = Dom "oc-bez" "bez"
  $bazaOc = Join-Path $dOc ".local\share\opencode\opencode.db"
  $skrotPrzed = (Get-FileHash -LiteralPath $bazaOc -Algorithm SHA256).Hash
  $czasPrzed = (Get-Item -LiteralPath $bazaOc).LastWriteTimeUtc

  # ------------------------------------------------------------- -Dane
  $r = Odpal $koszt @("-KatalogDomowy", $dOc, "-Zrodlo", $Zrodlo, "-Dane", "-Zwykly")
  $k = Klucze $r.Tekst
  $ix = $null
  for ($i = 1; $i -le 6; $i++) { if ($k["narz.$i.klucz"] -eq "opencode") { $ix = $i } }
  Sprawdz "-Dane: lista narzedzi z OpenCode" ($null -ne $ix) $r.Tekst
  if ($ix) {
    Sprawdz "-Dane: OpenCode uzywany (ostatnia rozmowa z bazy, bez cyklu wiedzy), jedyny" (($k["narz.$ix.uzywane"] -eq "1") -and ($k["narzedzia.uzywane"] -eq "OpenCode")) "uzywane=$($k["narz.$ix.uzywane"]) narzedzia.uzywane=$($k['narzedzia.uzywane']) ostatnio=$($k["narz.$ix.ostatnio"])"
    Sprawdz "-Dane: tokeny OpenCode dzis = 87 600 (kopie w rozwidlonej, cykl i stara rozmowa poza)" ($k["narz.$ix.dzis"] -eq "87600") "dzis=$($k["narz.$ix.dzis"]) powod=$($k["narz.$ix.zuzycie_powod"])"
    Sprawdz "-Dane: tokeny OpenCode srednio dziennie = 26 000 / 7 = 3 714 (stary zapis bez total)" ($k["narz.$ix.srednia"] -eq "3714") "srednia=$($k["narz.$ix.srednia"])"
    Sprawdz "-Dane: otwarcie okna rozmowy OpenCode = 22 493 (mediana z 2 rozmow, bez podagenta, rozwidlonej i cyklu)" (($k["narz.$ix.otwarcie"] -eq "22493") -and ($k["narz.$ix.otwarcie_sesji"] -eq "2") -and -not $k["narz.$ix.otwarcie_powod"]) "otwarcie=$($k["narz.$ix.otwarcie"]) z $($k["narz.$ix.otwarcie_sesji"]) powod=$($k["narz.$ix.otwarcie_powod"])"
    Sprawdz "-Dane: 'Co wiem' znaleziona w AGENTS.md OpenCode" (($k["narz.$ix.cowiem"] -eq "1") -and ($k["cowiem.gdzie"] -eq (Join-Path $dOc ".config\opencode\AGENTS.md"))) "cowiem.gdzie=$($k['cowiem.gdzie'])"
    Sprawdz "-Dane: czesc MegaRuchacza w OpenCode z jego rachunku (narz.mr = udzial.mr = $StartOc)" (($k["narz.$ix.mr"] -eq "$StartOc") -and ($k["narz.$ix.mr_start"] -eq "$StartOc") -and ($k["narz.$ix.mr_wiadomosc"] -eq "0")) "mr=$($k["narz.$ix.mr"]) start=$($k["narz.$ix.mr_start"]) wiadomosc=$($k["narz.$ix.mr_wiadomosc"])"
  }
  # Rachunek OpenCode: domyslne narzedzie na komputerze z samym OpenCode, start = blok
  # kierownika + "Co wiem" (na kartce $StartOc), procent od zmierzonego otwarcia OpenCode.
  Sprawdz "-Dane: rachunek domyslny = OpenCode, start $StartOc, wiadomosc 0, calosc 22 493" (($k["narzedzie"] -eq "OpenCode") -and ($k["udzial.start"] -eq "$StartOc") -and
    ($k["udzial.wiadomosc"] -eq "0") -and ($k["udzial.mr"] -eq "$StartOc") -and ($k["udzial.calosc"] -eq "22493") -and -not $k["udzial.powod"]) "narzedzie=$($k['narzedzie']) start=$($k['udzial.start']) wiadomosc=$($k['udzial.wiadomosc']) calosc=$($k['udzial.calosc']) powod=$($k['udzial.powod'])"
  Sprawdz "negatywna -Dane: Twoje wlasne instrukcje w AGENTS.md (~3 300 tokenow) nie licza sie jako MegaRuchacz" ([int]$k["udzial.start"] -lt ($StartOc + 100)) "start=$($k['udzial.start']) (gdyby liczyl caly plik: ~$([int](($BlokK.Length + $Wlasne.Length) / 3)))"
  Sprawdz "-Dane: linia rachunku mowi o OpenCode i 'do wiadomosci nic nie dokleja', bez Claude Code" (($k["linia"] -match '^pamiec OpenCode: ') -and ($k["linia"] -match 'do wiadomosci nic nie dokleja') -and ($k["linia"] -notmatch 'Claude')) $k["linia"]
  # tylko odczyt: baza bajt w bajt ta sama, zadnych plikow obok
  $skrotPo = (Get-FileHash -LiteralPath $bazaOc -Algorithm SHA256).Hash
  $obok = @(Get-ChildItem -LiteralPath (Split-Path $bazaOc) -File | Where-Object { $_.Name -ne "opencode.db" } | ForEach-Object { $_.Name })
  Sprawdz "tylko odczyt: baza OpenCode niezmieniona, bez plikow -journal/-wal/-shm" (($skrotPo -eq $skrotPrzed) -and ((Get-Item -LiteralPath $bazaOc).LastWriteTimeUtc -eq $czasPrzed) -and ($obok.Count -eq 0)) "skrot $skrotPrzed -> $skrotPo, obok: $($obok -join ', ')"

  # ------------------------------------------------------------- -Start
  $r = Odpal $koszt @("-KatalogDomowy", $dOc, "-Zrodlo", $Zrodlo, "-Start")
  $js = $null
  try { $js = $r.Tekst | ConvertFrom-Json } catch { }
  Sprawdz "-Start: JSON w samym ASCII" (($null -ne $js) -and ($r.Tekst -notmatch '[^\x00-\x7F]')) $r.Tekst
  if ($js) {
    $po = @($js.Narzedzia | Where-Object { $_.Klucz -eq "opencode" })[0]
    Sprawdz "-Start: OpenCode w Narzedzia z mediana 22 493 i czescia MegaRuchacza $StartOc" (($po.Otwarcie.Mediana -eq 22493) -and ($po.MegaRuchacz -eq $StartOc) -and $po.Uzywane) ($po | ConvertTo-Json -Depth 4 -Compress)
    Sprawdz "-Start: glowne narzedzie OpenCode - na wierzchu jego mediana i jego czesc MegaRuchacza" (($js.Narzedzie -eq "OpenCode") -and ($js.Sesje.Narzedzie -eq "OpenCode") -and ($js.Sesje.Mediana -eq 22493) -and
      ($js.MegaRuchaczSesja -eq $StartOc) -and ($js.MegaRuchaczStart -eq $StartOc) -and ($js.MegaRuchaczWiadomosc -eq 0) -and -not $js.Powod) "narzedzie=$($js.Narzedzie) sesja=$($js.MegaRuchaczSesja) powod=$($js.Powod)"
  }

  # ------------------------------------------------------------- -Rozbicie
  $r = Odpal $koszt @("-KatalogDomowy", $dOc, "-Zrodlo", $Zrodlo, "-Rozbicie", "-Zwykly")
  $naglowki = @(($r.Tekst -split "`n") | Where-Object { $_ -match '^\S' -and $_ -notmatch '^MegaRuchacz - ' })
  Sprawdz "-Rozbicie: najpierw OpenCode (wiadomosc: nic, start z blokiem kierownika), bez kubelkow Claude Code" (($naglowki.Count -ge 2) -and ($naglowki[0] -match '^OpenCode - przy KAZDEJ wiadomosci - nic') -and
    ($naglowki[1] -match "^OpenCode - RAZ, przy starcie sesji .* - ~$(([long]$StartOc).ToString("#,0", [Globalization.CultureInfo]::InvariantCulture).Replace(',', ' ')) tokenow") -and ($r.Tekst -match 'zasady kierownika') -and ($r.Tekst -cnotmatch 'Claude Code -')) $r.Tekst

  # ------------------------------------------------------------- -Warstwy
  $r = Odpal $koszt @("-KatalogDomowy", $dOc, "-Zrodlo", $Zrodlo, "-Warstwy")
  $j = $null
  try { $j = $r.Tekst | ConvertFrom-Json } catch { }
  Sprawdz "-Warstwy: JSON" ($null -ne $j) $r.Tekst
  if ($j) {
    $w = @{}; foreach ($x in @($j.Warstwy)) { $w["$($x.Id)"] = $x }
    $agOc = Join-Path $dOc ".config\opencode\AGENTS.md"
    Sprawdz "-Warstwy: AGENTS.md OpenCode jako warstwa startu OpenCode" (($w["opencode-globalny"].Stan -eq "jest") -and ($w["opencode-globalny"].Narzedzie -eq "opencode") -and ($w["opencode-globalny"].Kiedy -eq "start") -and ($w["opencode-globalny"].Sciezka -eq $agOc)) ($w["opencode-globalny"] | ConvertTo-Json -Compress)
    Sprawdz "-Warstwy: 'Co wiem' (stala i Biezace) w AGENTS.md OpenCode" (($w["opencode-globalny-stala"].Stan -eq "jest") -and ($w["opencode-globalny-biezace"].Stan -eq "jest") -and ($w["opencode-globalny-stala"].Rodzic -eq "opencode-globalny")) "$($w['opencode-globalny-stala'].Stan) / $($w['opencode-globalny-biezace'].Stan)"
    Sprawdz "-Warstwy: zadna warstwa nie jest tablica (podwarstwy rozpakowane)" (@($j.Warstwy | Where-Object { $_ -is [array] }).Count -eq 0) ""
  }
  # proba negatywna: OpenCode uzywany, a w AGENTS.md nie ma "Co wiem" - czerwony wiersz z powodem
  $r = Odpal $koszt @("-KatalogDomowy", $dZla, "-Zrodlo", $Zrodlo, "-Warstwy")
  $jz = $null
  try { $jz = $r.Tekst | ConvertFrom-Json } catch { }
  $sz = @($jz.Warstwy | Where-Object { $_.Id -eq "opencode-globalny-stala" })[0]
  Sprawdz "negatywna -Warstwy: brak 'Co wiem' w AGENTS.md uzywanego OpenCode = brak (czerwony)" (($sz.Stan -eq "brak") -and ($sz.Brak -match "nie ma jej w zadnym innym pliku")) "$($sz.Stan): $($sz.Brak)"

  # ------------------------------------------------------------- proby negatywne -Dane
  $r = Odpal $koszt @("-KatalogDomowy", $dZla, "-Zrodlo", $Zrodlo, "-Dane", "-Zwykly")
  $kz = Klucze $r.Tekst
  $iz = $null
  for ($i = 1; $i -le 6; $i++) { if ($kz["narz.$i.klucz"] -eq "opencode") { $iz = $i } }
  Sprawdz "negatywna -Dane: baza nieczytelna -> powod zamiast liczb (nigdy zero)" ($iz -and ($kz["narz.$iz.uzywane"] -eq "1") -and ($kz["narz.$iz.otwarcie_powod"] -match "nie umiem odczytac bazy rozmow OpenCode") -and
    ($kz["narz.$iz.zuzycie_powod"] -match "nie umiem odczytac") -and ($kz["narz.$iz.dzis"] -eq "") -and ($kz["narz.$iz.otwarcie"] -eq "")) "otwarcie_powod=$($kz["narz.$iz.otwarcie_powod"]) dzis='$($kz["narz.$iz.dzis"])'"
  $r = Odpal $koszt @("-KatalogDomowy", $dBez, "-Zrodlo", $Zrodlo, "-Dane", "-Zwykly")
  $kb = Klucze $r.Tekst
  $ib = $null
  for ($i = 1; $i -le 6; $i++) { if ($kb["narz.$i.klucz"] -eq "opencode") { $ib = $i } }
  Sprawdz "negatywna -Dane: odpowiedzi bez pola tokens -> powod, nie 'nic'" ($ib -and ($kb["narz.$ib.zuzycie_powod"] -match "pola tokens") -and ($kb["narz.$ib.dzis"] -eq "") -and ($kb["narz.$ib.otwarcie_powod"] -match "liczba tokenow")) "zuzycie_powod=$($kb["narz.$ib.zuzycie_powod"]) dzis='$($kb["narz.$ib.dzis"])' otwarcie_powod=$($kb["narz.$ib.otwarcie_powod"])"

  # ------------------------------------------------------------- okno (-Raport)
  $r = Odpal $nadz @("-Zrodlo", $Zrodlo, "-KatalogDomowy", $dOc, "-Raport", "-Proba", "-Cicho")
  $przod = ($r.Tekst -csplit "SZCZEGÓŁY")[0]
  $uwaga = ""
  $mu = [regex]::Match($przod, '(?s)CO WYMAGA UWAGI.*?\n\n')
  if ($mu.Success) { $uwaga = $mu.Value }
  Sprawdz "okno: zdanie 'Na tym komputerze: OpenCode.'" ($przod -match 'Na tym komputerze: OpenCode\.') $przod.Substring(0, [Math]::Min(800, $przod.Length))
  Sprawdz "okno: karta zuzycia z wierszem OpenCode (dzis ~88 000, srednio ~3 700)" ($przod -match '(?m)^\s+OpenCode\s+~88 000\s+~3 700') (([regex]::Match($przod, '(?s)ILE TOKEN.*?OTWARCIE')).Value)
  Sprawdz "okno: brak sprawy 'Nie umiem zmierzyć ... w OpenCode' przy dobrej bazie" ($uwaga -notmatch 'OpenCode') $uwaga
  Sprawdz "okno: brak sprawy 'Wiedza ... nie trafia' przy sekcji w AGENTS.md OpenCode" ($przod -notmatch 'nie trafia do żadnego narzędzia') $uwaga
  # Werdykt, karta otwarcia i rachunek pozycja po pozycji mowia o OpenCode - do 06.10.2026
  # mowily o Claude Code, ktorego na tym komputerze nie ma (rachunek byl tylko dla niego).
  $werdykt = ([regex]::Match($przod, '(?s)WERDYKT .*?\n\n')).Value
  $otw = ([regex]::Match($przod, '(?s)OTWARCIE OKNA ROZMOWY .*?\n\n')).Value
  $rach = ([regex]::Match($r.Tekst, '(?s)== RACHUNEK ZA PAMI.*?== NAUKA')).Value
  Sprawdz "okno: werdykt o OpenCode ('mało', 'co OpenCode wczytuje'), bez słowa 'Claude'" (($werdykt -match '\[malo\]') -and ($werdykt -match 'co OpenCode wczytuje') -and ($werdykt -match 'otwarciu okna w OpenCode') -and ($werdykt -cnotmatch 'Claude')) $werdykt
  Sprawdz "okno: karta otwarcia - OpenCode z częścią MegaRuchacza, przy wiadomości 'nic', bez 'Claude'" (($otw -match 'Otwarcie okna rozmowy \(OpenCode\): ~22 500') -and ($otw -match 'Z tego MegaRuchacz: 2 100 \(9%\)') -and
    ($otw -match 'przy każdej Twojej wiadomości: przypomnienie zasad: nic') -and ($otw -cnotmatch 'Claude')) $otw
  Sprawdz "okno Szczegóły: rachunek pozycja po pozycji - OpenCode, bez kubełków Claude Code" (($rach -match 'OpenCode - raz') -and ($rach -match 'zasady kierownika') -and ($rach -cnotmatch 'Claude Code')) $rach

  # proba negatywna: czesc MegaRuchacza w OpenCode ponad prog (blok 50 000 znakow) - alarm
  # "opencode-otwarcie" (kod 1) i czerwony werdykt o OpenCode, nie o Claude Code
  $dDuzy = Join-Path $T "oc-duzy"
  Copy-Item -LiteralPath $dOc -Destination $dDuzy -Recurse
  $agDuzy = "## Co wiem`n`n- Fakt testowy.`n`n" + $BlokDuzy + "`n"
  [System.IO.File]::WriteAllText((Join-Path $dDuzy ".config\opencode\AGENTS.md"), $agDuzy, $bezBom)
  $r = Odpal $koszt @("-KatalogDomowy", $dDuzy, "-Zrodlo", $Zrodlo, "-Dane", "-Zwykly")
  $kd = Klucze $r.Tekst
  $alOc = @(1..([int]("0" + $kd["alarmy"])) | Where-Object { $kd["alarm.$_.temat"] -eq "opencode-otwarcie" })
  Sprawdz "negatywna -Dane: OpenCode ponad próg -> alarm 'opencode-otwarcie' z nazwą OpenCode, kod 1" (($alOc.Count -eq 1) -and ($kd["alarm.$($alOc[0]).krotko"] -match '^OpenCode: MegaRuchacz to ~') -and ($kd["kod"] -eq "1") -and ($kd["linia"] -match '^UWAGA pamiec OpenCode')) "alarmy=$($kd['alarmy']) kod=$($kd['kod']) linia=$($kd['linia'])"
  $r = Odpal $nadz @("-Zrodlo", $Zrodlo, "-KatalogDomowy", $dDuzy, "-Raport", "-Proba", "-Cicho")
  $werdyktD = ([regex]::Match((($r.Tekst -csplit "SZCZEGÓŁY")[0]), '(?s)WERDYKT .*?\n\n')).Value
  Sprawdz "negatywna okno: werdykt 'dużo' o OpenCode, bez słowa 'Claude'" (($werdyktD -match '\[duzo\]') -and ($werdyktD -match 'OpenCode') -and ($werdyktD -cnotmatch 'Claude')) $werdyktD

  # Bez ~\.config\opencode\AGENTS.md OpenCode czyta ~\.claude\CLAUDE.md - rachunek liczy stamtad
  # i mowi to wprost (a nie "nic nie doklada")
  $dCm = Join-Path $T "oc-claudemd"
  Copy-Item -LiteralPath $dOc -Destination $dCm -Recurse
  Remove-Item -LiteralPath (Join-Path $dCm ".config\opencode\AGENTS.md")
  New-Item -ItemType Directory -Force -Path (Join-Path $dCm ".claude") | Out-Null
  [System.IO.File]::Copy((Join-Path $dOc ".config\opencode\AGENTS.md"), (Join-Path $dCm ".claude\CLAUDE.md"))
  $r = Odpal $koszt @("-KatalogDomowy", $dCm, "-Zrodlo", $Zrodlo, "-Dane", "-Zwykly")
  $kc = Klucze $r.Tekst
  $r2 = Odpal $koszt @("-KatalogDomowy", $dCm, "-Zrodlo", $Zrodlo, "-Rozbicie", "-Zwykly")
  Sprawdz "bez AGENTS.md OpenCode: rachunek z ~\.claude\CLAUDE.md (start $StartOc) i zdanie o tym w rozbiciu" (($kc["narzedzie"] -eq "OpenCode") -and ($kc["udzial.start"] -eq "$StartOc") -and
    ($r2.Tekst -match 'Nie ma ~\\\.config\\opencode\\AGENTS\.md, wiec OpenCode czyta ~\\\.claude\\CLAUDE\.md')) "narzedzie=$($kc['narzedzie']) start=$($kc['udzial.start']) | $($r2.Tekst)"

  # Kilka narzedzi naraz: werdykt mowi o kazdym uzywanym (glowne Claude Code + Codex + OpenCode,
  # kazde z czescia MegaRuchacza z wlasnego rachunku). Drogie OpenCode przy tanim Claude Code
  # = "dużo w OpenCode"; nieuzywane narzedzie - ani slowa (falszywy alarm).
  $kodWerdyktu = @'
param($zr, $dom)
$ErrorActionPreference = "Stop"
. (Join-Path $zr "zasobnik\stan-nadzorcy.ps1")
Ustaw-Nadzorce $zr $dom $true
$start = [pscustomobject]@{ Powod = ""; Sesje = [pscustomobject]@{ Narzedzie = "Claude Code"; Mediana = 180000; Liczba = 5; Min = 170000; Max = 190000 }
  Workerzy = $null; DniWstecz = 14; MrSesja = 9000; MrStart = 8900; MrWiadomosc = 100; MrWorker = 8900; Narzedzie = "Claude Code" }
function K($ocUz, $ocMr) {
  return [pscustomobject]@{ Linia = "x"; Klucze = [ordered]@{ "udzial.prog_tokeny" = "15000"; "udzial.mr" = "9000"; "udzial.start" = "8900"; "narzedzie" = "Claude Code"
    narzedzia = "3"; "narz.1.nazwa" = "Claude Code"; "narz.1.uzywane" = "1"; "narz.1.mr" = "9000"
    "narz.2.nazwa" = "Codex"; "narz.2.uzywane" = "1"; "narz.2.mr" = "5000"; "narz.2.otwarcie" = "24500"
    "narz.3.nazwa" = "OpenCode"; "narz.3.uzywane" = $ocUz; "narz.3.mr" = $ocMr; "narz.3.otwarcie" = "40000" } }
}
$a = Werdykt-Kosztu $start (K "1" "16000") $null
$b = Werdykt-Kosztu $start (K "0" "16000") $null
$c = Werdykt-Kosztu $start (K "1" "2000") $null
Write-Output ("drogi_stan: " + $a.Stan); Write-Output ("drogi: " + $a.Zdanie + " | " + $a.Wyjasnienie)
Write-Output ("nieuzywany_stan: " + $b.Stan); Write-Output ("nieuzywany: " + $b.Zdanie + " | " + $b.Wyjasnienie)
Write-Output ("tani_stan: " + $c.Stan); Write-Output ("tani: " + $c.Zdanie + " | " + $c.Wyjasnienie)
'@
  $plikWd = Join-Path $T "werdykt.ps1"
  [System.IO.File]::WriteAllText($plikWd, $kodWerdyktu, (New-Object System.Text.UTF8Encoding($true)))
  $r = Odpal $plikWd @($Zrodlo, $dOc)
  $kv = Klucze $r.Tekst
  Sprawdz "werdykt kilku narzędzi: tanie wszystkie -> 'mało' i zdanie o Codeksie i OpenCode, każde z jednostką" (($kv["tani_stan"] -eq "malo") -and
    ($kv["tani"] -match 'W Codeksie MegaRuchacz dokłada ~5 000 tokenów przy każdym otwarciu okna rozmowy \(20% tego, co Codex wczytuje\)\.') -and
    ($kv["tani"] -match 'W OpenCode MegaRuchacz dokłada ~2 000 tokenów przy każdym otwarciu okna rozmowy \(5% tego, co OpenCode wczytuje\)\.')) $r.Tekst
  Sprawdz "negatywna werdykt kilku narzędzi: drogie OpenCode przy tanim Claude Code -> 'dużo w OpenCode'" (($kv["drogi_stan"] -eq "duzo") -and
    ($kv["drogi"] -match '^MegaRuchacz kosztuje dużo w OpenCode: dokłada ~16 000 tokenów') -and ($kv["drogi"] -match 'W Claude Code MegaRuchacz dokłada ~9 000 tokenów') -and ($kv["drogi"] -match 'W Codeksie')) $r.Tekst
  Sprawdz "werdykt kilku narzędzi: nieużywany OpenCode nie zmienia werdyktu i nie pada w nim" (($kv["nieuzywany_stan"] -eq "malo") -and ($kv["nieuzywany"] -notmatch 'OpenCode')) $r.Tekst

  # proba negatywna: OpenCode uzywany, baza nieczytelna - sprawa wymagajaca uwagi
  $r = Odpal $nadz @("-Zrodlo", $Zrodlo, "-KatalogDomowy", $dZla, "-Raport", "-Proba", "-Cicho")
  $przodZ = ($r.Tekst -csplit "SZCZEGÓŁY")[0]
  Sprawdz "negatywna okno: sprawa 'Nie umiem zmierzyć, ile tokenów zużywasz w OpenCode'" ($przodZ -match 'Nie umiem zmierzyć, ile tokenów zużywasz w OpenCode') (([regex]::Match($przodZ, '(?s)CO WYMAGA UWAGI.*?\n\n')).Value)
  Sprawdz "negatywna okno: Stan bez 'Wszystko gra'" ($przodZ -notmatch 'Wszystko gra') (([regex]::Match($przodZ, '(?s)STAN .*?\n\n')).Value)

  # Zakladka Warstwy pamieci: 'Co wiem' w AGENTS.md OpenCode nalezy do modulu Wiedza,
  # a zdanie nad lista mowi, gdzie ta sekcja jest.
  $kodWarstw = @'
param($zr, $dom, $plikJson)
$ErrorActionPreference = "Stop"
. (Join-Path $zr "zasobnik\stan-nadzorcy.ps1")
Ustaw-Nadzorce $zr $dom $true
$script:ModulyOkna = @{}
. (Join-Path $zr "zasobnik\nadzorca\przeglad-tresc.ps1")
. (Join-Path $zr "zasobnik\nadzorca\szczegoly.ps1")
. (Join-Path $zr "zasobnik\nadzorca\warstwy.ps1")
$dw = [System.IO.File]::ReadAllText($plikJson) | ConvertFrom-Json
$w = @{}; foreach ($x in @($dw.Warstwy)) { $w["$($x.Id)"] = $x }
Write-Output ("zdanie: " + (Zdanie-Warstw $dw))
Write-Output ("modul_oc_stala: " + ((Moduly-Warstwy $w["opencode-globalny-stala"]) -join ","))
Write-Output ("modul_oc_biezace: " + ((Moduly-Warstwy $w["opencode-globalny-biezace"]) -join ","))
Write-Output ("szary_oc: " + (Narzedzie-Nieuzywane $w["opencode-globalny"]))
'@
  $plikW = Join-Path $T "warstwy-okna.ps1"
  [System.IO.File]::WriteAllText($plikW, $kodWarstw, (New-Object System.Text.UTF8Encoding($true)))
  $plikJson = Join-Path $T "warstwy.json"
  [System.IO.File]::WriteAllText($plikJson, (Odpal $koszt @("-KatalogDomowy", $dOc, "-Zrodlo", $Zrodlo, "-Warstwy")).Tekst, $bezBom)
  $r = Odpal $plikW @($Zrodlo, $dOc, $plikJson)
  $kw = Klucze $r.Tekst
  Sprawdz "zakladka Warstwy: 'Co wiem' jest w AGENTS.md (OpenCode)" ($kw["zdanie"] -match 'Sekcja „Co wiem” jest w: AGENTS\.md \(OpenCode\)') $r.Tekst
  Sprawdz "zakladka Warstwy: 'Co wiem' OpenCode w module Wiedza, warstwa nie szara" (($kw["modul_oc_stala"] -eq "wiedza") -and ($kw["modul_oc_biezace"] -eq "wiedza") -and ($kw["szary_oc"] -eq "False")) $r.Tekst
} finally {
  if ($Zostaw) { Write-Host "Zostawione: $T" }
  else { Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
if ($script:Zle -gt 0) { Write-Host "NIE PRZESZLO: $($script:Zle)"; exit 1 }
Write-Host "PRZESZLO WSZYSTKO"
exit 0
