# Sprawdzenie P71: okno MegaRuchacza na komputerze z samym Codeksem (bez Claude Code).
# Sztuczne katalogi domowe w %TEMP% - prawdziwy dom nie jest ruszany, nadzorca idzie
# z -Proba (nic nie zapisuje) i bez okna (-Raport = tresc okna tekstem).
#   powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File zasobnik\test-codex.ps1 [-Zrodlo <repo>] [-Zostaw]
# Kod wyjscia: 0 = wszystkie proby przeszly, 1 = ktoras nie.
#
# Domy:
#   codex      - ~\.codex\AGENTS.md z sekcja "## Co wiem" i "### Biezace", dwie rozmowy
#                Codeksa (dzis i 3 dni temu) ze zdarzeniami token_count; ani sladu ~\.claude.
#   codex-bez  - to samo, ale AGENTS.md BEZ sekcji "Co wiem" - proba negatywna: sekcji nie ma
#                nigdzie, wiec Przeglad nie moze mowic "Wszystko gra".
#   codex-zle  - rozmowy Codeksa bez liczb tokenow - proba negatywna: pomiar niemozliwy dla
#                UZYWANEGO narzedzia ma trafic do spraw wymagajacych uwagi.
#   codex-prawdziwy - zanonimizowana probka w PRAWDZIWYM zapisie Codeksa (DomPrawdziwy nizej,
#                z podagentem niosacym kopie rozmowy-rodzica) - od 06.10.2026.
# Do tego werdykt i Pomiar-Startu okna: liczby Codeksa nazwane Codeksem, nie Claude'em.
# Liczby w rozmowach sa dobrane tak, zeby wynik dalo sie policzyc na kartce: dzis przyrosty
# 20 500 + 0 (zdarzenie powtorzone) + 25 400 = 45 900; 3 dni temu 30 000, czyli srednio
# 30 000 / 7 = 4 286 dziennie; otwarcie dzis 20 000 - 11 znakow wiadomosci / 3 (4) = 19 996,
# 3 dni temu 29 000 - 1 = 28 999, mediana z dwoch rozmow (19 996 + 28 999) / 2 = 24 498.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Zostaw
)

$ErrorActionPreference = "Stop"
# Wydruk -Raport ma polskie znaki (nadzorca przestawia sie na UTF-8) - bez tej linii
# PowerShell odczytalby go w stronie kodowej konsoli i porownania tekstow by padly.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 }
catch { Write-Host "UWAGA: konsola nie przestawila sie na UTF-8 ($($_.Exception.Message)) - porownania z ogonkami moga pasc" }
$T = Join-Path $env:TEMP ("mr-test-codex-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
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

# Zapis rozmowy Codeksa: jedna linia JSON na zapis, tak jak pisze go Codex.
function Zapis($kiedy, [string]$typ, $payload) {
  return (@{ timestamp = $kiedy.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"); type = $typ; payload = $payload } | ConvertTo-Json -Compress -Depth 8)
}
function Tokeny-Zapis($kiedy, $calosc, $ostatnie) {
  $u = { param($we, $buf, $wy) @{ input_tokens = $we; cached_input_tokens = $buf; output_tokens = $wy; reasoning_output_tokens = 0; total_tokens = ($we + $wy) } }
  return (Zapis $kiedy "event_msg" @{ type = "token_count"; rate_limits = @{}
    info = @{ total_token_usage = (& $u $calosc[0] $calosc[1] $calosc[2]); last_token_usage = (& $u $ostatnie[0] $ostatnie[1] $ostatnie[2]); model_context_window = 272000 } })
}
function Rozmowa($dom, $kiedy, [string[]]$linie) {
  $kat = Join-Path $dom (".codex\sessions\" + $kiedy.ToString("yyyy\\MM\\dd"))
  New-Item -ItemType Directory -Force -Path $kat | Out-Null
  $plik = Join-Path $kat ("rollout-" + $kiedy.ToString("yyyy-MM-ddTHH-mm-ss") + "-" + [guid]::NewGuid().ToString() + ".jsonl")
  [System.IO.File]::WriteAllText($plik, (($linie -join "`n") + "`n"), $bezBom)
  (Get-Item -LiteralPath $plik).LastWriteTime = $kiedy
}
function Wiadomosc($kiedy, [string]$tekst) {
  return (Zapis $kiedy "response_item" @{ type = "message"; role = "user"; content = @(@{ type = "input_text"; text = $tekst }) })
}

# --- probka w PRAWDZIWYM zapisie Codeksa (zanonimizowana) ---------------------
# Ksztalt przepisany 06.10.2026 z prawdziwych rozmow z komputera domowego (Codex
# codex-tui, 3 pliki z 30.09-04.10, plus przeglad wszystkich 129): te same typy zapisow
# i pola, tresci i identyfikatory zmyslone. Rzeczy, ktorych pierwsza probka nie miala:
# pole ordinal w kazdym zapisie, world_state, token_usage_record (te same liczby co
# token_count - nie wolno ich liczyc drugi raz), cache_write_input_tokens, obrazek
# w wiadomosci (bloki <image>, input_image, </image>) i PODAGENT: pierwszy session_meta
# z source.subagent, zaraz za nim session_meta rodzica i KOPIA jego rozmowy razem z jego
# token_count (na domu 14 z 43 podagentow, sumy 18-143 mln) - wlasna historia od zapisu
# subagent_history_start_ordinal.
# Liczby: dzis - rozmowa 57 400 (dwa zdarzenia, przyrost 28 200 + 29 200) + podagent
# 30 100 (kopia rodzica z 5 000 000 nie liczy sie) = 87 500; 2 dni temu rozmowa
# "codex exec" 32 145 -> srednio 32 145 / 7 = 4 592. Otwarcie: 28 000 - 10 znakow / 3 (4) =
# 27 996 i 32 000 - 12 / 3 (4) = 31 996 -> mediana 29 996; podagent nie jest otwarciem okna.
function ZapisO($kiedy, [int]$nr, [string]$typ, $payload) {
  return ([ordered]@{ timestamp = $kiedy.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"); ordinal = $nr; type = $typ; payload = $payload } | ConvertTo-Json -Compress -Depth 10)
}
function UzycieO($we, $buf, $wy, $roz) {
  return [ordered]@{ input_tokens = $we; cached_input_tokens = $buf; cache_write_input_tokens = 0; output_tokens = $wy; reasoning_output_tokens = $roz; total_tokens = ($we + $wy) }
}
function TokenyO($kiedy, [int]$nr, $calosc, $ostatnie) {
  return (ZapisO $kiedy $nr "event_msg" ([ordered]@{ type = "token_count"
    info = [ordered]@{ total_token_usage = $calosc; last_token_usage = $ostatnie; model_context_window = 258400 }
    rate_limits = [ordered]@{ limit_id = "codex"; primary = [ordered]@{ used_percent = 1.0; window_minutes = 300 } } }))
}
function RekordO($kiedy, [int]$nr, $uzycie) {
  return (ZapisO $kiedy $nr "token_usage_record" ([ordered]@{ thread_id = "watek"; turn_id = "tura"; session_id = "sesja"; root_turn_id = "tura"
    response_id = "resp_test"; usage = $uzycie; turn_token_usage = $uzycie; thread_token_usage = $uzycie }))
}
function MetaO($kiedy, [int]$nr, [string]$id, $zrodlo, [string]$watek, $start) {
  $p = [ordered]@{ session_id = $id; id = $id; timestamp = $kiedy.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ"); cwd = "C:\projekt"
    originator = "codex-tui"; cli_version = "0.200.0"; source = $zrodlo; thread_source = $watek; model_provider = "openai"; history_mode = "paginated"
    base_instructions = [ordered]@{ text = "Instrukcje bazowe (zmyslone)." } }
  if ($null -ne $start) { $p.subagent_history_start_ordinal = $start; $p.forked_from_id = "rodzic"; $p.parent_thread_id = "rodzic" }
  return (ZapisO $kiedy $nr "session_meta" $p)
}
function WiadO($kiedy, [int]$nr, [string]$rola, $bloki) {
  return (ZapisO $kiedy $nr "response_item" ([ordered]@{ type = "message"; role = $rola; content = @($bloki) }))
}
function TekstO([string]$t) { return [ordered]@{ type = "input_text"; text = $t } }
function KontekstO($kiedy, [int]$nr) {
  return (ZapisO $kiedy $nr "turn_context" ([ordered]@{ turn_id = "tura"; cwd = "C:\projekt"; approval_policy = "on-request"; model = "gpt-test"; effort = "high"; summary = "auto" }))
}
function DomPrawdziwy([string]$nazwa) {
  $dom = Join-Path $T $nazwa
  New-Item -ItemType Directory -Force -Path (Join-Path $dom ".codex") | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $dom ".codex\AGENTS.md"), "## Co wiem`n`n- Fakt testowy.`n", $bezBom)
  $dzis = (Get-Date).AddMinutes(-5)
  if ($dzis.Date -ne (Get-Date).Date) { $dzis = (Get-Date) }
  $agentsMd = TekstO "# AGENTS.md instructions for C:\projekt`n`n<INSTRUCTIONS>`nZmyslone instrukcje.`n</INSTRUCTIONS>"
  $srodowisko = TekstO "<environment_context>`n  <cwd>C:\projekt</cwd>`n  <shell>powershell</shell>`n</environment_context>"
  # zwykla rozmowa z obrazkiem w pierwszej wiadomosci, dwa wywolania modelu
  $l = @(
    (MetaO $dzis 0 "rozmowa-1" "cli" "user" $null),
    (ZapisO $dzis 1 "event_msg" ([ordered]@{ type = "task_started"; turn_id = "tura" })),
    (WiadO $dzis 2 "developer" @([ordered]@{ type = "input_text"; text = "<permissions instructions>zmyslone</permissions instructions>" })),
    (WiadO $dzis 3 "user" @($agentsMd, $srodowisko)),
    (ZapisO $dzis 4 "world_state" ([ordered]@{ full = $true; state = [ordered]@{ model = "gpt-test" } })),
    (KontekstO $dzis 5),
    (WiadO $dzis 6 "user" @((TekstO "<image name=[Image #1]>"), [ordered]@{ type = "input_image"; image_url = "data:image/png;base64,AAAA" }, (TekstO "</image>"), (TekstO "Policz to."))),
    (ZapisO $dzis 7 "event_msg" ([ordered]@{ type = "item_completed"; item = [ordered]@{ type = "reasoning" } })),
    (ZapisO $dzis 8 "response_item" ([ordered]@{ type = "reasoning"; summary = @() })),
    (RekordO $dzis 9 (UzycieO 28000 11000 200 50)),
    (TokenyO $dzis 10 (UzycieO 28000 11000 200 50) (UzycieO 28000 11000 200 50)),
    (RekordO $dzis 11 (UzycieO 29000 28000 200 0)),
    (TokenyO $dzis 12 (UzycieO 57000 39000 400 50) (UzycieO 29000 28000 200 0)),
    (ZapisO $dzis 13 "event_msg" ([ordered]@{ type = "task_complete"; turn_id = "tura" })))
  Rozmowa $dom $dzis $l
  # podagent: kopia rodzica (z jego token_count na 5 mln) do zapisu nr 5, wlasna historia od 6
  $pod = $dzis.AddSeconds(30)
  $zrodloPod = [ordered]@{ subagent = [ordered]@{ thread_spawn = [ordered]@{ parent_thread_id = "rodzic"; depth = 1; agent_path = "/root/implementer"; agent_nickname = "Test" } } }
  $l = @(
    (MetaO $pod 0 "podagent-1" $zrodloPod "subagent" 6),
    (MetaO $pod 1 "rodzic" "cli" "user" $null),
    (WiadO $pod 2 "user" @($agentsMd, $srodowisko)),
    (WiadO $pod 3 "user" @((TekstO "Wiadomosc rodzica."))),
    (TokenyO $pod 4 (UzycieO 4990000 4900000 10000 0) (UzycieO 70000 69000 100 0)),
    (KontekstO $pod 5),
    (WiadO $pod 6 "user" @((TekstO "Zadanie dla podagenta."))),
    (KontekstO $pod 7),
    (RekordO $pod 8 (UzycieO 30000 29000 100 0)),
    (TokenyO $pod 9 (UzycieO 30000 29000 100 0) (UzycieO 30000 29000 100 0)))
  Rozmowa $dom $pod $l
  # rozmowa "codex exec" sprzed 2 dni
  $wcz = (Get-Date).Date.AddDays(-2).AddHours(6)
  $l = @(
    (MetaO $wcz 0 "exec-1" "exec" "user" $null),
    (WiadO $wcz 1 "user" @($agentsMd, $srodowisko)),
    (KontekstO $wcz 2),
    (WiadO $wcz 3 "user" @((TekstO "Na wejsciu x"))),
    (RekordO $wcz 4 (UzycieO 32000 0 145 129)),
    (TokenyO $wcz 5 (UzycieO 32000 0 145 129) (UzycieO 32000 0 145 129)))
  Rozmowa $dom $wcz $l
  return $dom
}

function Dom([string]$nazwa, [bool]$zCoWiem, [bool]$zTokenami) {
  $dom = Join-Path $T $nazwa
  New-Item -ItemType Directory -Force -Path (Join-Path $dom ".codex") | Out-Null
  $agents = "# Instrukcje`n`nPisz po polsku.`n"
  if ($zCoWiem) {
    $agents = "## Co wiem`n`n### O użytkowniku`n`n- Sprzedaje olejki zapachowe.`n`n### Bieżące`n`n- [$((Get-Date).ToString('yyyy-MM-dd'))] Fakt testowy.`n`n## Zasady`n`nPisz po polsku.`n"
  }
  [System.IO.File]::WriteAllText((Join-Path $dom ".codex\AGENTS.md"), $agents, $bezBom)
  # dzis - kilka minut temu (zeby "dzis" nie wypadlo na wczoraj tuz po polnocy)
  $dzis = (Get-Date).AddMinutes(-5)
  if ($dzis.Date -ne (Get-Date).Date) { $dzis = (Get-Date) }
  $l = @(
    (Zapis $dzis "session_meta" @{ id = "sesja-dzis"; cwd = "C:\projekt"; originator = "codex_cli_rs" }),
    (Wiadomosc $dzis "<environment_context>`n  <cwd>C:\projekt</cwd>`n</environment_context>"),
    (Zapis $dzis "turn_context" @{ model = "gpt-5-codex"; cwd = "C:\projekt" }),
    (Wiadomosc $dzis "Napisz test"))
  if ($zTokenami) {
    $l += (Zapis $dzis "event_msg" @{ type = "token_count"; info = $null; rate_limits = @{} })
    $l += (Tokeny-Zapis $dzis @(20000, 0, 500) @(20000, 0, 500))
    $l += (Tokeny-Zapis $dzis @(20000, 0, 500) @(20000, 0, 500))
    $l += (Tokeny-Zapis $dzis @(45000, 18000, 900) @(25000, 18000, 400))
  } else {
    $l += (Zapis $dzis "event_msg" @{ type = "agent_message"; message = "brak liczb" })
  }
  Rozmowa $dom $dzis $l
  $wczesniej = (Get-Date).Date.AddDays(-3).AddHours(10)
  $l = @((Zapis $wczesniej "session_meta" @{ id = "sesja-wczesniej"; cwd = "C:\projekt" }), (Wiadomosc $wczesniej "Hej"))
  if ($zTokenami) { $l += (Tokeny-Zapis $wczesniej @(29000, 10000, 1000) @(29000, 10000, 1000)) }
  Rozmowa $dom $wczesniej $l
  return $dom
}

try {
  New-Item -ItemType Directory -Force -Path $T | Out-Null
  $koszt = Join-Path $Zrodlo "narzedzia\koszt-pamieci.ps1"
  $nadz = Join-Path $Zrodlo "zasobnik\nadzorca.ps1"
  $dCx = Dom "codex" $true $true
  $dBez = Dom "codex-bez" $false $true
  $dZle = Dom "codex-zle" $true $false
  $agentsCx = Join-Path $dCx ".codex\AGENTS.md"

  # ------------------------------------------------------------- -Warstwy
  $r = Odpal $koszt @("-KatalogDomowy", $dCx, "-Zrodlo", $Zrodlo, "-Warstwy")
  $j = $null
  try { $j = $r.Tekst | ConvertFrom-Json } catch { }
  Sprawdz "-Warstwy: JSON" ($null -ne $j) $r.Tekst
  if ($j) {
    $w = @{}; foreach ($x in @($j.Warstwy)) { $w["$($x.Id)"] = $x }
    Sprawdz "-Warstwy: sekcja 'Co wiem' znaleziona w AGENTS.md (czesc stala)" (($w["codex-globalny-stala"].Stan -eq "jest") -and ($w["codex-globalny-stala"].Sciezka -eq $agentsCx)) ($w["codex-globalny-stala"] | ConvertTo-Json -Compress)
    Sprawdz "-Warstwy: 'Biezace' znalezione w AGENTS.md" ($w["codex-globalny-biezace"].Stan -eq "jest") ($w["codex-globalny-biezace"] | ConvertTo-Json -Compress)
    Sprawdz "-Warstwy: 'Co wiem' w CLAUDE.md = nie dotyczy (Claude Code tu nieuzywany)" ($w["claude-globalny-stala"].Stan -eq "nie-dotyczy") "$($w['claude-globalny-stala'].Stan): $($w['claude-globalny-stala'].Brak)"
    Sprawdz "-Warstwy: natywna pamiec Claude Code = nie dotyczy" ($w["pamiec-natywna"].Stan -eq "nie-dotyczy") "$($w['pamiec-natywna'].Stan)"
    $czerwoneCc = @($j.Warstwy | Where-Object { ($_.Narzedzie -eq "claude") -and (@("brak", "blad") -contains $_.Stan) })
    Sprawdz "-Warstwy: zadna warstwa Claude Code nie swieci na czerwono" ($czerwoneCc.Count -eq 0) (@($czerwoneCc | ForEach-Object { $_.Id }) -join ", ")
    $nCx = @($j.Narzedzia | Where-Object { $_.Klucz -eq "codex" })[0]
    Sprawdz "-Warstwy: Codex uzywany, Claude Code nie" ($nCx.Uzywane -and -not (@($j.Narzedzia | Where-Object { $_.Klucz -eq "claude" })[0].Uzywane)) ($j.Narzedzia | ConvertTo-Json -Compress)
  }
  # proba negatywna: bez sekcji w AGENTS.md (a Codeksa uzywasz) - wiersz czerwony, z powodem
  $r = Odpal $koszt @("-KatalogDomowy", $dBez, "-Zrodlo", $Zrodlo, "-Warstwy")
  $jb = $null
  try { $jb = $r.Tekst | ConvertFrom-Json } catch { }
  $sb = @($jb.Warstwy | Where-Object { $_.Id -eq "codex-globalny-stala" })[0]
  Sprawdz "negatywna -Warstwy: brak 'Co wiem' w AGENTS.md uzywanego Codeksa = brak (czerwony)" (($sb.Stan -eq "brak") -and ($sb.Brak -match "nie ma jej w zadnym innym pliku")) "$($sb.Stan): $($sb.Brak)"

  # ------------------------------------------------------------- -Dane
  $r = Odpal $koszt @("-KatalogDomowy", $dCx, "-Zrodlo", $Zrodlo, "-Dane", "-Zwykly")
  $k = Klucze $r.Tekst
  $ix = $null
  for ($i = 1; $i -le 5; $i++) { if ($k["narz.$i.klucz"] -eq "codex") { $ix = $i } }
  Sprawdz "-Dane: lista narzedzi z Codeksem" ($null -ne $ix) $r.Tekst
  if ($ix) {
    Sprawdz "-Dane: Codex uzywany, jedyny" (($k["narz.$ix.uzywane"] -eq "1") -and ($k["narzedzia.uzywane"] -eq "Codex")) "uzywane=$($k["narz.$ix.uzywane"]) narzedzia.uzywane=$($k['narzedzia.uzywane'])"
    Sprawdz "-Dane: tokeny Codeksa dzis = 45 900 (zdarzenie powtorzone liczone raz)" ($k["narz.$ix.dzis"] -eq "45900") "dzis=$($k["narz.$ix.dzis"]) powod=$($k["narz.$ix.zuzycie_powod"])"
    Sprawdz "-Dane: tokeny Codeksa srednio dziennie = 30 000 / 7 = 4 286" ($k["narz.$ix.srednia"] -eq "4286") "srednia=$($k["narz.$ix.srednia"])"
    Sprawdz "-Dane: otwarcie okna rozmowy Codeksa = 24 498 (mediana z 2 rozmow)" (($k["narz.$ix.otwarcie"] -eq "24498") -and ($k["narz.$ix.otwarcie_sesji"] -eq "2") -and -not $k["narz.$ix.otwarcie_powod"]) "otwarcie=$($k["narz.$ix.otwarcie"]) powod=$($k["narz.$ix.otwarcie_powod"])"
    Sprawdz "-Dane: 'Co wiem' znaleziona w AGENTS.md" ($k["cowiem.gdzie"] -eq $agentsCx) "cowiem.gdzie=$($k['cowiem.gdzie'])"
    Sprawdz "-Dane: rachunek domyslny = Codex, z procentem otwarcia" (($k["narzedzie"] -eq "Codex") -and ($k["udzial.calosc"] -eq "24498")) "narzedzie=$($k['narzedzie']) calosc=$($k['udzial.calosc']) powod=$($k['udzial.powod'])"
  }

  # ------------------------------------------------------------- -Start
  $r = Odpal $koszt @("-KatalogDomowy", $dCx, "-Zrodlo", $Zrodlo, "-Start")
  $js = $null
  try { $js = $r.Tekst | ConvertFrom-Json } catch { }
  Sprawdz "-Start: JSON w samym ASCII" (($null -ne $js) -and ($r.Tekst -notmatch '[^\x00-\x7F]')) $r.Tekst
  if ($js) {
    Sprawdz "-Start: glowne narzedzie Codex, mediana 24 498 z 2 rozmow" (($js.Narzedzie -eq "Codex") -and ($js.Sesje.Narzedzie -eq "Codex") -and ($js.Sesje.Mediana -eq 24498) -and ($js.Sesje.Liczba -eq 2)) ($js | ConvertTo-Json -Depth 3 -Compress)
    Sprawdz "-Start: czesc MegaRuchacza Codeksa = start + wiadomosc" (($null -ne $js.MegaRuchaczSesja) -and ($js.MegaRuchaczSesja -eq ($js.MegaRuchaczStart + $js.MegaRuchaczWiadomosc)) -and -not $js.Powod) "sesja $($js.MegaRuchaczSesja), powod '$($js.Powod)'"
  }

  # ------------------------------------------------------------- okno (-Raport)
  $r = Odpal $nadz @("-Zrodlo", $Zrodlo, "-KatalogDomowy", $dCx, "-Raport", "-Proba", "-Cicho")
  $tx = $r.Tekst
  $przod = ($tx -csplit "SZCZEGÓŁY")[0]
  $uwaga = ""
  $mu = [regex]::Match($przod, '(?s)CO WYMAGA UWAGI.*?\n\n')
  if ($mu.Success) { $uwaga = $mu.Value }
  Sprawdz "okno: zdanie 'Na tym komputerze: Codex.'" ($przod -match 'Na tym komputerze: Codex\.') $przod.Substring(0, [Math]::Min(800, $przod.Length))
  Sprawdz "okno: karta zuzycia z wierszem Codeksa (dzis ~46 000, srednio ~4 300)" (($przod -match '(?m)^\s+Codex\s+~46 000\s+~4 300') -and ($przod -notmatch 'Nie wiem, ile tokenów zużywasz')) (([regex]::Match($przod, '(?s)ILE TOKEN.*?OTWARCIE')).Value)
  Sprawdz "okno: otwarcie okna rozmowy zmierzone dla Codeksa" ($przod -match 'Otwarcie okna rozmowy \(Codex\): ~') (([regex]::Match($przod, '(?s)OTWARCIE OKNA.*?\n\n')).Value)
  # Werdykt i karta otwarcia na komputerze z samym Codeksem - ani slowa o Claude (06.10.2026:
  # liczba zawsze z nazwa narzedzia, takze "przy otwarciu okna w Codeksie").
  $werdyktCx = ([regex]::Match($przod, '(?s)WERDYKT .*?\n\n')).Value
  $otwCx = ([regex]::Match($przod, '(?s)OTWARCIE OKNA ROZMOWY .*?\n\n')).Value
  Sprawdz "okno: werdykt i karta otwarcia o Codeksie, bez słowa 'Claude'" (($werdyktCx -match 'co Codex wczytuje') -and ($werdyktCx -match 'w Codeksie') -and
    ($werdyktCx -cnotmatch 'Claude') -and ($otwCx -cnotmatch 'Claude')) "$werdyktCx$otwCx"
  Sprawdz "okno: brak sprawy 'Wiedza ... nie trafia' przy sekcji w AGENTS.md" ($przod -notmatch 'nie trafia do żadnego narzędzia') $uwaga
  Sprawdz "okno: zadnej sprawy o nieuzywanym Claude Code (falszywy alarm)" ($uwaga -notmatch 'Claude') $uwaga

  # proba negatywna 1: sekcji "Co wiem" nie ma nigdzie
  $r = Odpal $nadz @("-Zrodlo", $Zrodlo, "-KatalogDomowy", $dBez, "-Raport", "-Proba", "-Cicho")
  $przodB = ($r.Tekst -csplit "SZCZEGÓŁY")[0]
  Sprawdz "negatywna okno: sprawa 'Wiedza o Tobie i firmie nie trafia do żadnego narzędzia'" ($przodB -match '\[!\] Wiedza o Tobie i firmie nie trafia do żadnego narzędzia') (([regex]::Match($przodB, '(?s)CO WYMAGA UWAGI.*?\n\n')).Value)
  Sprawdz "negatywna okno: Stan bez 'Wszystko gra'" ($przodB -notmatch 'Wszystko gra') (([regex]::Match($przodB, '(?s)STAN .*?\n\n')).Value)

  # Ta sama sprawa na samej liscie spraw (Zbierz-Problemy -> Ile-Wymaga-Uwagi, od ktorej
  # zalezy "Wszystko gra") - bez innych braków sztucznego domu, ktore i tak zdejmuja
  # "Wszystko gra". Para: sekcja jest -> 0 spraw; sekcji nie ma nigdzie -> 1 sprawa;
  # nieuzywany Claude Code z brakami pomiaru -> 0 (bez falszywego alarmu); uzywany Codex
  # bez pomiaru -> 1.
  $kodSpraw = @'
param($zr, $dom)
$ErrorActionPreference = "Stop"
. (Join-Path $zr "zasobnik\stan-nadzorcy.ps1")
Ustaw-Nadzorce $zr $dom $true
$script:ModulyOkna = @{}
. (Join-Path $zr "zasobnik\nadzorca\przeglad-tresc.ps1")
$inst = [pscustomobject]@{ Moduly = [pscustomobject]@{ wiedza = $true; skille = $false } }
function D($klucze) {
  $k = [ordered]@{ narzedzia = "2"
    "narz.1.klucz" = "claude"; "narz.1.nazwa" = "Claude Code"; "narz.1.uzywane" = "0"; "narz.1.zuzycie_w_oknie" = "1"
    "narz.1.otwarcie_powod" = "nie ma katalogu z transkryptami Claude Code"
    "narz.2.klucz" = "codex"; "narz.2.nazwa" = "Codex"; "narz.2.uzywane" = "1"; "narz.2.zuzycie_w_oknie" = "0"
    "narz.2.otwarcie" = "24498"; "narz.2.dzis" = "45900"; "narz.2.srednia" = "4286"
    "cowiem.gdzie" = "C:\dom\.codex\AGENTS.md"; "cowiem.sprawdzone" = "C:\dom\.claude\CLAUDE.md; C:\dom\.codex\AGENTS.md"; "cowiem.wiedza_wylaczona" = "0" }
  foreach ($x in $klucze.Keys) { $k[$x] = $klucze[$x] }
  return [pscustomobject]@{ Rachunek = [pscustomobject]@{ Klucze = $k; Linia = "x" }; Cykl = [pscustomobject]@{ Pracuje = $false }
    Alarmy = @(); Informacje = @(); Instalacja = $inst }
}
$wynik = [ordered]@{}
$wynik.jest      = Ile-Wymaga-Uwagi (Zbierz-Problemy (D @{}) @() "" (Get-Date))
$wynik.nigdzie   = Ile-Wymaga-Uwagi (Zbierz-Problemy (D @{ "cowiem.gdzie" = "" }) @() "" (Get-Date))
$wynik.wylaczona = Ile-Wymaga-Uwagi (Zbierz-Problemy (D @{ "cowiem.gdzie" = ""; "cowiem.wiedza_wylaczona" = "1" }) @() "" (Get-Date))
$wynik.codexbez  = Ile-Wymaga-Uwagi (Zbierz-Problemy (D @{ "narz.2.otwarcie_powod" = "brak liczb"; "narz.2.zuzycie_powod" = "brak liczb" }) @() "" (Get-Date))
$wynik.zdanie    = Zdanie-Narzedzi (D @{})
$wynik.oba       = Zdanie-Narzedzi (D @{ "narz.1.uzywane" = "1" })
# oba narzedzia naraz: wiersze Claude Code nazwane z imienia, wiersz Codeksa i "Razem" ze wszystkich
$ko = [pscustomobject]@{ Powod = ""; Wyliczono = (Get-Date); Rozmowy = 1000000; Workerzy = 2000000; Najdrozsi = @(); WorkerowDzis = 0
  OdpowiedziRozmow = 1; OdpowiedziWorkerow = 1 }
$zu = [pscustomobject]@{ Stan = "jest"; Dni = 7; SredniaRozmowy = 3000000; SredniaWorkerow = 4000000; Powod = "" }
$tk = Teksty-Kosztu-Narzedzi $ko $zu (D @{ "narz.1.uzywane" = "1" })
$wynik.tabela    = (@($tk.Tabela | ForEach-Object { $_ -join "|" }) -join " / ")
$lo = Linie-Otwarcia-Innych (D @{ "narz.1.uzywane" = "1"; "narz.2.otwarcie_sesji" = "2"; "narz.2.mr" = "242" }) ([pscustomobject]@{ Sesje = [pscustomobject]@{ Narzedzie = "Claude Code" } })
$wynik.otwarcie  = ($lo -join " / ")
foreach ($x in $wynik.Keys) { Write-Output "${x}: $($wynik[$x])" }
'@
  $plikSpraw = Join-Path $T "sprawy.ps1"
  [System.IO.File]::WriteAllText($plikSpraw, $kodSpraw, (New-Object System.Text.UTF8Encoding($true)))
  $r = Odpal $plikSpraw @($Zrodlo, $dCx)
  $ks = Klucze $r.Tekst
  Sprawdz "sprawy: sekcja 'Co wiem' jest -> 0 spraw (czyli 'Wszystko gra')" ($ks["jest"] -eq "0") $r.Tekst
  Sprawdz "negatywna sprawy: sekcji nie ma nigdzie -> 1 sprawa (bez 'Wszystko gra')" ($ks["nigdzie"] -eq "1") $r.Tekst
  Sprawdz "sprawy: modul Wiedza wylaczony -> brak sekcji to nie sprawa" ($ks["wylaczona"] -eq "0") $r.Tekst
  Sprawdz "negatywna sprawy: uzywany Codex bez pomiaru -> 1 sprawa" ($ks["codexbez"] -eq "1") $r.Tekst
  Sprawdz "zdanie: 'Na tym komputerze: Codex.' / 'Claude Code i Codex.'" (($ks["zdanie"] -eq "Na tym komputerze: Codex.") -and ($ks["oba"] -eq "Na tym komputerze: Claude Code i Codex.")) $r.Tekst
  Sprawdz "oba narzedzia: karta zuzycia osobno i razem (Claude 1+2 mln, Codex ~46 000 -> razem ~3 mln dzis, ~7 mln srednio)" (
    $ks["tabela"] -match '^\|dziś do \d\d:\d\d\|średnio z 7 dni / Claude: rozmowy\|~1 mln\|~3 mln / Claude: workerzy\|~2 mln\|~4 mln / Codex\|~46 000\|~4 300 / Razem\|~3 mln\|~7 mln$') $ks["tabela"]
  Sprawdz "oba narzedzia: linia otwarcia Codeksa pod karta Claude Code" ($ks["otwarcie"] -match '^Codex: otwarcie okna rozmowy ~24 500 tokenów \(typowa wartość z 2 rozmów\), z tego MegaRuchacz ~200 \(mniej niż 1%\)\.$') $ks["otwarcie"]

  # Zakladka Warstwy pamieci bez okna: te same funkcje, ktore rysuja liste (Zdanie-Warstw,
  # Rozmiar-Warstwy, Narzedzie-Nieuzywane), na liscie warstw sztucznego domu z samym Codeksem.
  $kodWarstw = @'
param($zr, $dom, $plikJson, $plikDanych)
$ErrorActionPreference = "Stop"
. (Join-Path $zr "zasobnik\stan-nadzorcy.ps1")
Ustaw-Nadzorce $zr $dom $true
$script:ModulyOkna = @{}
. (Join-Path $zr "zasobnik\nadzorca\przeglad-tresc.ps1")
. (Join-Path $zr "zasobnik\nadzorca\szczegoly.ps1")
. (Join-Path $zr "zasobnik\nadzorca\warstwy.ps1")
$k = [ordered]@{}
foreach ($l in [System.IO.File]::ReadAllLines($plikDanych)) { $m = [regex]::Match($l, '^\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*:\s*(.*?)\s*$'); if ($m.Success) { $k[$m.Groups[1].Value] = $m.Groups[2].Value } }
$script:Dane = [pscustomobject]@{ Rachunek = [pscustomobject]@{ Klucze = $k } }
$script:Start = [pscustomobject]@{ Sesje = [pscustomobject]@{ Narzedzie = "Codex"; Mediana = 24498; Liczba = 2 }; MrSesja = 242; Powod = ""; DniWstecz = 14 }
$dw = [System.IO.File]::ReadAllText($plikJson) | ConvertFrom-Json
$w = @{}; foreach ($x in @($dw.Warstwy)) { $w["$($x.Id)"] = $x }
Write-Output ("zdanie: " + (Zdanie-Warstw $dw))
Write-Output ("rozmiar_claude_stala: " + (Rozmiar-Warstwy $w["claude-globalny-stala"]))
Write-Output ("stan_claude_stala: " + (Stan-Po-Ludzku "$($w['claude-globalny-stala'].Stan)"))
Write-Output ("szary_claude_stala: " + (Narzedzie-Nieuzywane $w["claude-globalny-stala"]))
Write-Output ("szary_codex_stala: " + (Narzedzie-Nieuzywane $w["codex-globalny-stala"]))
Write-Output ("procent_codex: " + (Rozmiar-Opisowy $w["codex-globalny"]))
Write-Output ("modul_codex_stala: " + ((Moduly-Warstwy $w["codex-globalny-stala"]) -join ","))
'@
  $plikW = Join-Path $T "warstwy-okna.ps1"
  [System.IO.File]::WriteAllText($plikW, $kodWarstw, (New-Object System.Text.UTF8Encoding($true)))
  $plikJson = Join-Path $T "warstwy.json"
  [System.IO.File]::WriteAllText($plikJson, (Odpal $koszt @("-KatalogDomowy", $dCx, "-Zrodlo", $Zrodlo, "-Warstwy")).Tekst, $bezBom)
  $plikDanych = Join-Path $T "dane.txt"
  [System.IO.File]::WriteAllText($plikDanych, (Odpal $koszt @("-KatalogDomowy", $dCx, "-Zrodlo", $Zrodlo, "-Dane", "-Zwykly")).Tekst, $bezBom)
  $r = Odpal $plikW @($Zrodlo, $dCx, $plikJson, $plikDanych)
  $kw = Klucze $r.Tekst
  Sprawdz "zakladka Warstwy: zdanie mowi, gdzie jest 'Co wiem' i co nie dotyczy" (($kw["zdanie"] -match 'Sekcja „Co wiem” jest w: AGENTS\.md \(Codex\)') -and ($kw["zdanie"] -match '\d+ warstw\w* nie dotycz\w* tego komputera - należą do narzędzi, których tu nie używasz \(Claude Code i OpenCode\)')) $r.Tekst
  Sprawdz "zakladka Warstwy: 'Co wiem' w CLAUDE.md = 'nie dotyczy', szare" (($kw["rozmiar_claude_stala"] -eq "nie dotyczy") -and ($kw["szary_claude_stala"] -eq "True") -and ($kw["szary_codex_stala"] -eq "False")) $r.Tekst
  Sprawdz "zakladka Warstwy: AGENTS.md z procentem otwarcia Codeksa, 'Co wiem' w module Wiedza" (($kw["procent_codex"] -match 'jak .*% otwarcia okna rozmowy') -and ($kw["modul_codex_stala"] -eq "wiedza")) $r.Tekst

  # proba negatywna 2: Codeksa uzywasz, a liczb tokenow w rozmowach nie ma
  $r = Odpal $nadz @("-Zrodlo", $Zrodlo, "-KatalogDomowy", $dZle, "-Raport", "-Proba", "-Cicho")
  $przodZ = ($r.Tekst -csplit "SZCZEGÓŁY")[0]
  Sprawdz "negatywna okno: sprawa 'Nie umiem zmierzyć, ile tokenów zużywasz w Codeksie'" ($przodZ -match 'Nie umiem zmierzyć, ile tokenów zużywasz w Codeksie') (([regex]::Match($przodZ, '(?s)CO WYMAGA UWAGI.*?\n\n')).Value)
  Sprawdz "negatywna okno: Stan bez 'Wszystko gra'" ($przodZ -notmatch 'Wszystko gra') (([regex]::Match($przodZ, '(?s)STAN .*?\n\n')).Value)

  # ------------------------------------------------------------- prawdziwy zapis Codeksa
  # Proba negatywna wbudowana w liczby: gdyby kopia rodzica w pliku podagenta sie liczyla,
  # dzis wyszloby ~5 mln zamiast 87 500, a otwarcie mialoby trzy rozmowy zamiast dwoch.
  $dPr = DomPrawdziwy "codex-prawdziwy"
  $r = Odpal $koszt @("-KatalogDomowy", $dPr, "-Zrodlo", $Zrodlo, "-Dane", "-Zwykly")
  $kp = Klucze $r.Tekst
  $ip = $null
  for ($i = 1; $i -le 6; $i++) { if ($kp["narz.$i.klucz"] -eq "codex") { $ip = $i } }
  Sprawdz "prawdziwy zapis: Codex uzywany" ($ip -and ($kp["narz.$ip.uzywane"] -eq "1")) $r.Tekst
  if ($ip) {
    Sprawdz "prawdziwy zapis: dzis = 87 500 (token_usage_record i kopia rodzica u podagenta nie liczone)" ($kp["narz.$ip.dzis"] -eq "87500") "dzis=$($kp["narz.$ip.dzis"]) powod=$($kp["narz.$ip.zuzycie_powod"])"
    Sprawdz "prawdziwy zapis: srednio = 32 145 / 7 = 4 592 (rozmowa codex exec)" ($kp["narz.$ip.srednia"] -eq "4592") "srednia=$($kp["narz.$ip.srednia"])"
    Sprawdz "prawdziwy zapis: otwarcie = 29 996 z 2 rozmow (podagent pominiety, obrazek nie liczy sie do wiadomosci)" (($kp["narz.$ip.otwarcie"] -eq "29996") -and ($kp["narz.$ip.otwarcie_sesji"] -eq "2")) "otwarcie=$($kp["narz.$ip.otwarcie"]) z $($kp["narz.$ip.otwarcie_sesji"]) powod=$($kp["narz.$ip.otwarcie_powod"])"
  }
  $r = Odpal $koszt @("-KatalogDomowy", $dPr, "-Zrodlo", $Zrodlo, "-Warstwy")
  $jp = $null
  try { $jp = $r.Tekst | ConvertFrom-Json } catch { }
  $wo = @($jp.Warstwy | Where-Object { $_.Id -eq "opencode-globalny" })[0]
  Sprawdz "prawdziwy zapis: AGENTS.md OpenCode bez OpenCode = 'nie dotyczy' (bez falszywego alarmu)" ($wo -and ($wo.Stan -eq "nie-dotyczy")) "$($wo.Stan): $($wo.Brak)"

  # Werdykt i pomiar otwarcia w oknie mowia o Codeksie, nie o Claude (P71, poprawka 06.10):
  # Kto-Wczytuje na danych z -Start, Pomiar-Startu oddaje pola Narzedzie i Narzedzia.
  $kodStartu = @'
param($zr, $dom)
$ErrorActionPreference = "Stop"
. (Join-Path $zr "zasobnik\stan-nadzorcy.ps1")
Ustaw-Nadzorce $zr $dom $true
$s = Pomiar-Startu
Write-Output ("narzedzie: " + $s.Narzedzie)
Write-Output ("narzedzia: " + ((@($s.Narzedzia) | ForEach-Object { $_.Klucz }) -join ","))
Write-Output ("sesje: " + $s.Sesje.Narzedzie)
Write-Output ("kto: " + (Kto-Wczytuje $s $null))
Write-Output ("kto_bez_pomiaru: " + (Kto-Wczytuje $null @{ narzedzie = "Codex" }))
Write-Output ("kto_claude: " + (Kto-Wczytuje $null @{ narzedzie = "Claude Code" }))
$k = [ordered]@{ "udzial.prog_tokeny" = "15000"; "udzial.mr" = "206"; "udzial.start" = "8"; "narzedzie" = "Codex" }
$w = Werdykt-Kosztu $s ([pscustomobject]@{ Klucze = $k; Linia = "x" }) $null
Write-Output ("werdykt: " + $w.Zdanie)
'@
  $plikStartu = Join-Path $T "start.ps1"
  [System.IO.File]::WriteAllText($plikStartu, $kodStartu, (New-Object System.Text.UTF8Encoding($true)))
  $r = Odpal $plikStartu @($Zrodlo, $dCx)
  $kst = Klucze $r.Tekst
  Sprawdz "Pomiar-Startu: pola Narzedzie i Narzedzia z -Start nie gina" (($kst["narzedzie"] -eq "Codex") -and ($kst["narzedzia"] -eq "claude,codex,opencode") -and ($kst["sesje"] -eq "Codex")) $r.Tekst
  Sprawdz "werdykt: 'co Codex wczytuje' na komputerze z samym Codeksem" (($kst["kto"] -eq "Codex") -and ($kst["werdykt"] -match 'co Codex wczytuje') -and ($kst["werdykt"] -notmatch 'Claude')) $r.Tekst
  Sprawdz "werdykt: bez pomiaru nazwa z rachunku, Claude Code krotko 'Claude'" (($kst["kto_bez_pomiaru"] -eq "Codex") -and ($kst["kto_claude"] -eq "Claude")) $r.Tekst
} finally {
  if ($Zostaw) { Write-Host "Zostawione: $T" }
  else { Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
if ($script:Zle -gt 0) { Write-Host "NIE PRZESZLO: $($script:Zle)"; exit 1 }
Write-Host "PRZESZLO WSZYSTKO"
exit 0
