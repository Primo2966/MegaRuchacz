<#
Stan serwera "Wiedza firmy" na Pakowanie2 - do odczytu przez SSH. Kod wyjscia 1 = ALARM.

Progi (kazdy z uzasadnieniem - falszywy alarm uczy ignorowac alarmy):
  - straznik.json starszy niz 5 x jego interwal (min. 5 min): straznik pisze go co
    interwal takze w trakcie aktualizacji i kopii, wiec 5 opuszczonych zapisow
    to nie czkawka, tylko martwy straznik,
  - serwer dziala dluzej niz 3 min, a port nie slucha: start z modelem trwa
    kilkadziesiat sekund, 3 min to wyraznie za dlugo,
  - znacznik zycia samego serwera (<dane>\serwer-zyje.json, pisany co 60 s) starszy
    niz 5 min, model w stanie BLAD (wyszukiwanie tylko pelnotekstowe) albo problem
    z plikiem osob,
  - aktualizacja: brak sukcesu przez 24 h (sprawdzanie co godzine - doba bez
    jednego sukcesu to nie chwilowa przerwa GitHuba); pojedynczy blad = UWAGA,
  - kopia: ostatni wynik blad/czesciowo albo brak sukcesu przez 26 h (raz na dobe
    o 3:00, ponowienia co godzine - 2 h zapasu).

  powershell -NoProfile -ExecutionPolicy Bypass -File stan-serwera-wiedzy.ps1 [-Kat C:\dev\wiedza-firmy]
#>
param(
  [string]$Kat = 'C:\dev\wiedza-firmy',
  [datetime]$Teraz = (Get-Date)   # testy
)
$Stan = Join-Path $Kat 'stan'
$alarmy = 0
function Linia([string]$poziom, [string]$t) {
  if ($poziom -eq 'ALARM') { $script:alarmy++ }
  Write-Host ("[{0}] {1}" -f $poziom, $t)
}
$Dane = Join-Path $env:APPDATA 'wiedza-firmy'
$plikKonf = Join-Path $Kat 'serwer-wiedzy.json'
if (Test-Path -LiteralPath $plikKonf) {
  try { $k0 = Get-Content -LiteralPath $plikKonf -Raw -Encoding UTF8 | ConvertFrom-Json; if ($k0.dane) { $Dane = [string]$k0.dane } }
  catch { Linia 'ALARM' "nieczytelny $plikKonf : $($_.Exception.Message)" }
}
function Czytaj([string]$nazwa) {
  $p = Join-Path $Stan $nazwa
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  try { return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) }
  catch { Linia 'ALARM' "$nazwa nieczytelny: $($_.Exception.Message)"; return $null }
}
function Wiek([object]$czas) {
  if (-not $czas) { return $null }
  try { return ($Teraz - [datetimeoffset]::Parse("$czas").LocalDateTime) } catch { return $null }
}
function Godz($ts) { if ($null -eq $ts) { 'nigdy' } else { '{0:N1} h temu' -f $ts.TotalHours } }

$s = Czytaj 'straznik.json'
if (-not $s) { Linia 'ALARM' "brak $Stan\straznik.json - straznik nigdy nie ruszyl" }
else {
  $w = Wiek $s.czas
  $prog = [Math]::Max(300, 5 * [int]$s.co_ile_s)
  if ($null -eq $w -or $w.TotalSeconds -gt $prog) { Linia 'ALARM' "straznik milczy: ostatni znacznik $($s.czas) (prog $prog s)" }
  elseif ($s.faza -like 'koniec*') { Linia 'ALARM' "straznik zakonczyl petle: $($s.faza)" }
  else { Linia 'OK' "straznik zyje ($($s.faza), znacznik $([int]$w.TotalSeconds) s temu, startow serwera: $($s.startow))" }
  $od = Wiek $s.serwer_od
  if ($s.faza -eq 'serwer dziala' -and -not $s.port_slucha -and $od -and $od.TotalMinutes -gt 3) {
    Linia 'ALARM' "serwer dziala od $($s.serwer_od), a port $($s.port) nie slucha - zobacz $Stan\serwer.log"
  } elseif ($s.port_slucha) { Linia 'OK' "port $($s.port) slucha" }
}

$zp = Join-Path $Dane 'serwer-zyje.json'
$z = $null
if (Test-Path -LiteralPath $zp) {
  try { $z = Get-Content -LiteralPath $zp -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Linia 'ALARM' "nieczytelny $zp" }
}
if (-not $z) { Linia 'ALARM' "brak znacznika zycia serwera $zp" }
else {
  $wz = Wiek $z.czas
  if ($null -eq $wz -or $wz.TotalMinutes -gt 5) { Linia 'ALARM' "serwer nie daje znaku zycia od $($z.czas) (pid $($z.pid))" }
  else { Linia 'OK' "serwer zyje (pid $($z.pid), wersja $($z.wersja), $([int]$wz.TotalSeconds) s temu)" }
  if ("$($z.model)" -like 'BLAD*') { Linia 'ALARM' "model: $($z.model) - wyszukiwanie tylko pelnotekstowe" }
  elseif ($z.model) { Linia 'OK' "model: $($z.model)" }
  if ($z.problem_osob) { Linia 'ALARM' "osoby: $($z.problem_osob)" }
}

$a = Czytaj 'aktualizacja.json'
if (-not $a) { Linia 'ALARM' 'aktualizacja nigdy nie przebiegla' }
else {
  $ws = Wiek $a.ostatni_sukces
  if ($null -eq $ws -or $ws.TotalHours -gt 24) { Linia 'ALARM' "aktualizacja bez sukcesu od $(Godz $ws); ostatnio: $($a.status): $($a.przyczyna)" }
  elseif ($a.status -eq 'blad') { Linia 'UWAGA' "ostatnia aktualizacja: blad: $($a.przyczyna) (sukces $(Godz $ws))" }
  else { Linia 'OK' "aktualizacja: $($a.status), sha $($a.sha), sukces $(Godz $ws)" }
}

$k = Czytaj 'kopia.json'
if (-not $k) { Linia 'ALARM' 'kopia zapasowa nigdy nie przebiegla' }
else {
  $wk = Wiek $k.ostatni_sukces
  if ($k.status -ne 'ok') { Linia 'ALARM' "kopia zapasowa: $($k.status): $($k.przyczyna)" }
  if ($null -eq $wk -or $wk.TotalHours -gt 26) { Linia 'ALARM' "kopia zapasowa bez sukcesu od $(Godz $wk)" }
  elseif ($k.status -eq 'ok') { Linia 'OK' "kopia zapasowa: $($k.katalog) ($(Godz $wk))" }
}

$log = Join-Path $Stan 'straznik.log'
if (Test-Path -LiteralPath $log) { Write-Host '--- straznik.log (koniec)'; Get-Content -LiteralPath $log -Tail 8 -Encoding UTF8 | ForEach-Object { "  $_" } }
if ($alarmy) { exit 1 } else { exit 0 }
