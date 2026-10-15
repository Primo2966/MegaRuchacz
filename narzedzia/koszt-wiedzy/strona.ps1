# narzedzia\koszt-wiedzy\strona.ps1 - czesc narzedzia\koszt-wiedzy\koszt-wiedzy.ps1 (patrz BUDOWA
# w jego naglowku). Sklada strone HTML z liczb z dane.ps1: liczby i procenty po polsku
# (Liczba-Pl, Mln-Pl, Proc-Pl, Odmiana), karty za wczoraj (Karta-Wersji), wykres SVG z 30 dni
# (Wykres-Svg), tabela dni, suma okresu i stopka (Zbuduj-Strone), strona bledu (Strona-Bledu).
# Jeden plik HTML bez niczego z sieci: style w <style>, wykres w SVG, jasny i ciemny motyw
# z prefers-color-scheme. Same definicje; wczytuje go koszt-wiedzy.ps1 kropka (testy tez).

$script:Pl = [Globalization.CultureInfo]::GetCultureInfo("pl-PL")
$DniWykresu = 30
$DniTygodnia = @("nd", "pn", "wt", "śr", "cz", "pt", "sb")

# Tylko & < > " ' - WebUtility.HtmlEncode w .NET Framework zamienia tez znaki 160-255 (ó, twarda spacja)
# na &#NNN;, co psuje szukanie w tekscie strony.
function Html($t) { return ("" + $t).Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("`"", "&quot;").Replace("'", "&#39;") }

function Liczba-Pl($n) {
  if ($null -eq $n) { return "?" }
  return ([long]$n).ToString("N0", $script:Pl)
}

function Mln-Pl($n) {
  if ($null -eq $n) { return "?" }
  return ([double]$n / 1e6).ToString("N1", $script:Pl)
}

# Procent z tyloma miejscami po przecinku, ile trzeba, zeby nie wyszlo zero - ta sama zasada co
# Procent-Udzialu w zasobnik\nadzorca\stan-zuzycie.ps1 (12%, 3,4%, 0,21%, 0,021%).
function Proc-Pl($p) {
  if ($null -eq $p) { return "?" }
  $p = [double]$p
  if ($p -ge 10) { return "$([int][math]::Round($p))%" }
  if ($p -ge 1) { return ($p.ToString("0.#", $script:Pl) + "%") }
  if ($p -ge 0.1) { return ($p.ToString("0.0#", $script:Pl) + "%") }
  if ($p -ge 0.01) { return ($p.ToString("0.0##", $script:Pl) + "%") }
  if ($p -ge 0.001) { return ($p.ToString("0.000", $script:Pl) + "%") }
  if ($p -gt 0) { return "mniej niż 0,001%" }
  return "0%"
}

function Iloraz-Pl($x) {
  if ($null -eq $x) { return "—" }
  if ($x -ge 10) { return "$([long][math]::Round($x))×" }
  return ($x.ToString("0.#", $script:Pl) + "×")
}

function Usd-Pl($x) {
  if ($null -eq $x) { return "" }
  return ([double]$x).ToString("0.00", $script:Pl) + " $"
}

function Odmiana($n, $jeden, $kilka, $wiele) {
  if ($null -eq $n) { return $wiele }
  $n = [long]$n
  if ($n -eq 1) { return $jeden }
  $j = $n % 10; $d = $n % 100
  if (($j -ge 2) -and ($j -le 4) -and (($d -lt 12) -or ($d -gt 14))) { return $kilka }
  return $wiele
}

function Data-Pl($klucz, [switch]$ZDniem) {
  $d = Dzien-Z $klucz
  if ($null -eq $d) { return "" }
  $t = $d.ToString("dd.MM.yyyy", $script:Inv)
  if ($ZDniem) { $t += " " + $DniTygodnia[[int]$d.DayOfWeek] }
  return $t
}

function Zakres-Krotko($od, $do) {
  # "12–13.10" albo "28.09–02.10" - z jakich dni byly przeczytane rozmowy
  $a = Dzien-Z $od; $b = Dzien-Z $do
  if ($null -eq $a) { return "" }
  if (($null -eq $b) -or ($a -eq $b)) { return $a.ToString("dd.MM", $script:Inv) }
  if ($a.Month -eq $b.Month) { return $a.ToString("dd", $script:Inv) + "–" + $b.ToString("dd.MM", $script:Inv) }
  return $a.ToString("dd.MM", $script:Inv) + "–" + $b.ToString("dd.MM", $script:Inv)
}

function Tokeny-Osi($n) {
  if ($n -ge 1e6) { return ([double]$n / 1e6).ToString("0.#", $script:Pl) + " mln" }
  if ($n -ge 1e3) { return ([double]$n / 1e3).ToString("0.#", $script:Pl) + " tys." }
  return ([long]$n).ToString("N0", $script:Pl)
}

function Okragla-Gora($x) {
  # 1, 2, 2,5, 5 razy potega dziesieciu - gora osi wykresu
  if ($x -le 0) { return 1 }
  $pot = [math]::Pow(10, [math]::Floor([math]::Log10($x)))
  foreach ($m in @(1, 2, 2.5, 5, 10)) { if (($m * $pot) -ge $x) { return $m * $pot } }
  return 10 * $pot
}

$STYL = @'
:root{--tlo:#f5f6f8;--karta:#fff;--tekst:#1b2330;--slaby:#5d6775;--linia:#e2e5ea;--tansza:#2f6fd6;--pelna:#d9731f;
--blad-tlo:#fdeceb;--blad:#b3261e;--uwaga-tlo:#fff5d9;--uwaga:#7a5400;--pusty:#9aa2ad}
@media (prefers-color-scheme:dark){:root{--tlo:#13161b;--karta:#1c2128;--tekst:#e5e8ec;--slaby:#9ba4af;--linia:#2d343d;
--tansza:#6ea4ff;--pelna:#f29a52;--blad-tlo:#3b1f1e;--blad:#ff8f87;--uwaga-tlo:#3a3117;--uwaga:#f1cb72;--pusty:#5e6670}}
*{box-sizing:border-box}
body{margin:0;background:var(--tlo);color:var(--tekst);font:15px/1.5 "Segoe UI",system-ui,-apple-system,sans-serif}
main{max-width:1120px;margin:0 auto;padding:28px 22px 56px}
h1{font-size:26px;margin:0;letter-spacing:-.01em}
h2{font-size:17px;margin:34px 0 10px}
.odswiezono{color:var(--slaby);margin:2px 0 22px}
.dzien-kart{margin:0 0 10px;color:var(--slaby)}
.dzien-kart b{color:var(--tekst)}
.karty{display:grid;grid-template-columns:1fr auto 1fr;gap:16px;align-items:stretch}
.karta{background:var(--karta);border:1px solid var(--linia);border-top:4px solid var(--kolor);border-radius:10px;padding:16px 20px}
.karta.t{--kolor:var(--tansza)}.karta.p{--kolor:var(--pelna)}
.karta h3{margin:0 0 6px;font-size:15px;font-weight:600}
.duza{font-size:32px;font-weight:700;font-variant-numeric:tabular-nums;line-height:1.2}
.duza small{font-size:15px;font-weight:400;color:var(--slaby)}
.proc{font-size:17px;margin:2px 0 6px}
.drobne{color:var(--slaby);font-size:13.5px}
.brak{font-size:22px;color:var(--slaby);margin:6px 0}
.mnoznik{align-self:center;text-align:center;padding:0 6px}
.mnoznik b{display:block;font-size:24px}
.mnoznik span{color:var(--slaby);font-size:13px}
.znacznik{display:inline-block;font-size:11.5px;font-weight:600;padding:1px 7px;border-radius:9px;border:1px solid var(--pelna);color:var(--pelna);vertical-align:2px;margin-left:4px}
.czerwony{color:var(--blad)}
.uwagi{background:var(--uwaga-tlo);color:var(--uwaga);border-radius:8px;padding:10px 16px;margin:0 0 18px}
.uwagi ul{margin:4px 0 0;padding-left:20px}
.panel{background:var(--karta);border:1px solid var(--linia);border-radius:10px;padding:14px 16px}
.legenda{display:flex;gap:18px;color:var(--slaby);font-size:13.5px;margin:0 0 6px}
.legenda i{display:inline-block;width:11px;height:11px;border-radius:2px;margin-right:6px;vertical-align:-1px}
svg{width:100%;height:auto;display:block}
svg text{fill:var(--slaby);font-size:11px;font-family:inherit}
svg .siatka{stroke:var(--linia);stroke-width:1}
svg .t{fill:var(--tansza)}svg .p{fill:var(--pelna)}svg .p.proba{fill-opacity:.45;stroke:var(--pelna);stroke-dasharray:3 2}
svg .b{fill:var(--blad)}
.tabela{overflow-x:auto}
table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums;font-size:14px}
th,td{padding:6px 9px;border-bottom:1px solid var(--linia);text-align:right;white-space:nowrap}
th{font-weight:600;color:var(--slaby);font-size:13px;vertical-align:bottom}
th.grupa{text-align:center;border-bottom:2px solid var(--kolor)}
th.grupa.t{--kolor:var(--tansza)}th.grupa.p{--kolor:var(--pelna)}
td:first-child,th:first-child{text-align:left}
tr.pusty td{color:var(--pusty)}
tr.zbledem td{background:var(--blad-tlo)}
tr.opis-bledu td{background:var(--blad-tlo);color:var(--blad);text-align:left;white-space:normal;padding-top:0;font-size:13.5px}
.suma p{margin:4px 0}
.stopka{margin-top:30px;color:var(--slaby);font-size:13.5px}
.stopka p{margin:4px 0}
.rozbicie p{margin:4px 0}
.rozbicie table{width:auto;margin:6px 0 12px}
.rozbicie th{text-align:right}.rozbicie th:first-child{text-align:left}
tr.szczegoly>td{text-align:left;white-space:normal;padding:0 9px 6px}
tr.szczegoly summary{cursor:pointer;color:var(--slaby);font-size:13.5px}
tr.szczegoly summary.czerwony{color:var(--blad)}
tr.szczegoly .rozbicie{padding:4px 0 0 18px}
.wyszarzony{color:var(--slaby)}
details.tech{margin:0 0 8px;font-size:12.5px;color:var(--slaby)}
details.tech summary{cursor:pointer}
details.tech div{white-space:pre-wrap;word-break:break-all;margin:4px 0 0 14px}
@media (max-width:760px){.karty{grid-template-columns:1fr}.mnoznik{padding:4px 0}}
'@

function Karta-Wersji($klasa, $tytul, $tokeny, $proc, $fakty, $wywolania, $proba, $dodatki, $brak, $blad) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("<section class=`"karta $klasa`"><h3>$(Html $tytul)")
  if ($proba) { [void]$sb.Append("<span class=`"znacznik`">próba</span>") }
  [void]$sb.Append("</h3>")
  if ($null -eq $tokeny) {
    [void]$sb.Append("<div class=`"brak`">brak danych</div>")
    if ($brak) { [void]$sb.Append("<div class=`"drobne`">$(Html $brak)</div>") }
  } else {
    [void]$sb.Append("<div class=`"duza`">$(Liczba-Pl $tokeny) <small>tokenów</small></div>")
    [void]$sb.Append("<div class=`"proc`">$(Html (Proc-Pl $proc)) całego dnia</div>")
    $fakt = "? faktów"; if ($null -ne $fakty) { $fakt = "$(Liczba-Pl $fakty) $(Odmiana $fakty 'fakt' 'fakty' 'faktów')" }
    $wyw = "? wywołań"; if ($null -ne $wywolania) { $wyw = "$(Liczba-Pl $wywolania) $(Odmiana $wywolania 'wywołanie' 'wywołania' 'wywołań')" }
    [void]$sb.Append("<div class=`"drobne`">$fakt · $wyw</div>")
    foreach ($d in @($dodatki)) { if ($d) { [void]$sb.Append("<div class=`"drobne`">$(Html $d)</div>") } }
  }
  if ($blad) { [void]$sb.Append("<div class=`"drobne czerwony`">$(Html $blad)</div>") }
  [void]$sb.Append("</section>")
  return $sb.ToString()
}

function Usd-Dol($x) {
  # "$0,93" - zapis z makiety rozbicia na etapy
  if ($null -eq $x) { return "?" }
  return "$" + ([double]$x).ToString("0.00", $script:Pl)
}

function Czas-Przebiegu($czas) {
  # ISO z koszty.jsonl -> "15.10, 9:14"
  $d = [datetime]::MinValue
  if ([datetime]::TryParse(("" + $czas), $script:Inv, [Globalization.DateTimeStyles]::None, [ref]$d)) { return $d.ToString("dd.MM, H:mm", $script:Inv) }
  return ("" + $czas)
}

function Godzina-Udanego($czas, $czasBledu) {
  # " o 9:14" (ten sam dzien co nieudany przebieg) albo " 16.10 o 9:14"; bez czytelnego czasu - nic
  $d = [datetime]::MinValue
  if (-not [datetime]::TryParse(("" + $czas), $script:Inv, [Globalization.DateTimeStyles]::None, [ref]$d)) { return "" }
  $b = [datetime]::MinValue
  if ([datetime]::TryParse(("" + $czasBledu), $script:Inv, [Globalization.DateTimeStyles]::None, [ref]$b) -and ($b.Date -eq $d.Date)) {
    return " o $($d.ToString('H:mm', $script:Inv))"
  }
  return " $($d.ToString('dd.MM', $script:Inv)) o $($d.ToString('H:mm', $script:Inv))"
}

function Rozbicie-Przebiegow($p) {
  # Kazdy przebieg pelnej wersji tego dnia: naglowek z suma, tabela etapow (Dolacz-Etapy w dane.ps1)
  # albo powod, czemu jej nie ma; niezgodnosc sum i odrzucone przebiegi na czerwono.
  $sb = New-Object System.Text.StringBuilder
  $dzien = (Dzien-Z $p.Dzien).ToString("dd.MM", $script:Inv)
  $lista = @($p.ListaPrzebiegow | Sort-Object Czas)
  foreach ($pr in $lista) {
    $kiedy = "Pełne czytanie dnia $dzien (przebieg $(Czas-Przebiegu $pr.Czas))"
    $kosztowal = (($null -ne $pr.Wywolan) -and ($pr.Wywolan -gt 0)) -or (($null -ne $pr.Razem) -and ($pr.Razem -gt 0))
    if (-not $pr.Ok) {
      # Najpierw zdanie po ludzku, surowy tekst zwiniety. Czerwony tylko, gdy dzien nie ma zadnego
      # udanego przebiegu - gdy pozniejsza proba przeszla, porazka jest wyszarzona z jej godzina.
      $ludzki = Blad-Po-Ludzku $pr.Blad $pr.Razem
      $udany = @($lista | Where-Object { $_.Ok -and ([string]::CompareOrdinal($_.Czas, $pr.Czas) -gt 0) }) | Select-Object -First 1
      $klasa = "czerwony"
      if ($udany) { $klasa = "wyszarzony"; $ludzki += " Udało się w kolejnym podejściu$(Godzina-Udanego $udany.Czas $pr.Czas)." }
      elseif ($p.Ok) { $klasa = "wyszarzony"; $ludzki += " Ten dzień udał się w innym podejściu." }
      $tech = "<details class=`"tech`"><summary>szczegóły techniczne</summary><div>$(Html $pr.Blad)</div></details>"
    }
    if (-not $kosztowal) {
      if ($pr.Ok) { [void]$sb.Append("<p class=`"drobne`">$(Html $kiedy): bez uruchomień modelu - $(Html $pr.Blad)</p>") }
      else { [void]$sb.Append("<div class=`"$klasa`"><p>$(Html $kiedy): $(Html $ludzki)</p>$tech</div>") }
      continue
    }
    $ile = "razem $(Html (Tokeny-Osi $pr.Razem)) tokenów · $(Html (Usd-Dol $pr.Usd))"
    if ($pr.Ok -and ($null -ne $pr.Faktow)) { $ile += " · $(Liczba-Pl $pr.Faktow) $(Odmiana $pr.Faktow 'fakt' 'fakty' 'faktów')" }
    [void]$sb.Append("<p><b>$(Html $kiedy):</b> $ile</p>")
    if (-not $pr.Ok) { [void]$sb.Append("<div class=`"$klasa`"><p>Ten przebieg się nie udał (jego koszt jest wliczony). $(Html $ludzki)</p>$tech</div>") }
    if ($pr.EtapyUwaga) { [void]$sb.Append("<p class=`"czerwony`"><b>Uwaga:</b> $(Html $pr.EtapyUwaga)</p>") }
    if (@($pr.Etapy).Count -gt 0) {
      [void]$sb.Append("<table><thead><tr><th>etap</th><th>uruchomień</th><th>czytał (tokeny)</th><th>napisał (tokeny)</th><th>razem</th><th>$</th></tr></thead><tbody>")
      foreach ($e in @($pr.Etapy)) {
        [void]$sb.Append("<tr><td>$(Html $e.Nazwa)</td><td>$(Liczba-Pl $e.Wywolan)</td><td>$(Liczba-Pl $e.Czytal)</td><td>$(Liczba-Pl $e.Napisal)</td><td>$(Liczba-Pl $e.Razem)</td><td>$(Html (Usd-Dol $e.Usd))</td></tr>")
      }
      [void]$sb.Append("</tbody></table>")
      if ($pr.Paczek) {
        $zn = ""; if ($null -ne $pr.ZnakiCzytania) { $zn = ": $(Liczba-Pl $pr.ZnakiCzytania) znaków (razem z instrukcją dla modelu)" }
        [void]$sb.Append("<p class=`"drobne`">Rozmowy tego dnia poszły do czytania w $($pr.Paczek) $(Odmiana $pr.Paczek 'paczce' 'paczkach' 'paczkach')$zn.</p>")
      }
    } elseif ($pr.EtapyBrak) { [void]$sb.Append("<p class=`"drobne`">$(Html $pr.EtapyBrak)</p>") }
  }
  return $sb.ToString()
}

function Wykres-Svg($wiersze) {
  # Ostatnie $DniWykresu dni od najstarszego: dwa slupki na dzien w JEDNEJ skali - roznica
  # wysokosci to prawdziwa roznica kosztu. Niezerowy slupek ma co najmniej 2 px, zeby bylo go widac.
  $dni = @(@($wiersze) | Select-Object -First $DniWykresu)
  [array]::Reverse($dni)
  $max = [double]0
  foreach ($r in $dni) {
    if ($r.Tansza -and ($null -ne $r.Tansza.Tokeny) -and ($r.Tansza.Tokeny -gt $max)) { $max = [double]$r.Tansza.Tokeny }
    if ($r.Pelna -and ($null -ne $r.Pelna.Razem) -and ($r.Pelna.Razem -gt $max)) { $max = [double]$r.Pelna.Razem }
  }
  if (($dni.Count -eq 0) -or ($max -le 0)) { return "<p class=`"drobne`">Brak danych do wykresu.</p>" }
  $gora = Okragla-Gora $max
  $W = 1000; $H = 250; $ml = 64; $mr = 8; $mt = 10; $mb = 30
  $wys = $H - $mt - $mb
  $slot = ($W - $ml - $mr) / $dni.Count
  $bw = [math]::Min(16, $slot * 0.36)
  $f = { param($x) ([double]$x).ToString("0.#", $script:Inv) }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("<svg viewBox=`"0 0 $W $H`" role=`"img`" aria-label=`"Koszt tworzenia wiedzy z ostatnich $($dni.Count) dni`">")
  for ($i = 0; $i -le 4; $i++) {
    $v = $gora * $i / 4
    $y = $mt + $wys - ($wys * $i / 4)
    [void]$sb.Append("<line class=`"siatka`" x1=`"$ml`" x2=`"$($W - $mr)`" y1=`"$(& $f $y)`" y2=`"$(& $f $y)`"/>")
    [void]$sb.Append("<text x=`"$($ml - 6)`" y=`"$(& $f ($y + 4))`" text-anchor=`"end`">$(Html (Tokeny-Osi $v))</text>")
  }
  $co = [math]::Max(1, [math]::Ceiling($dni.Count / 10))
  for ($i = 0; $i -lt $dni.Count; $i++) {
    $r = $dni[$i]
    $x0 = $ml + $slot * $i + ($slot - 2 * $bw - 2) / 2
    $etykieta = Data-Pl $r.Dzien
    foreach ($s in @(@{ K = "t"; V = $(if ($r.Tansza) { $r.Tansza.Tokeny } else { $null }); N = "tańsza"; X = $x0 },
                     @{ K = "p"; V = $(if ($r.Pelna) { $r.Pelna.Razem } else { $null }); N = "pełna"; X = $x0 + $bw + 2 })) {
      if (($null -eq $s.V) -or ($s.V -le 0)) { continue }
      # nie $h: PowerShell nie rozroznia wielkosci liter, $h nadpisaloby wysokosc wykresu $H
      $wysSlupka = [math]::Max(2, $wys * [double]$s.V / $gora)
      $klasa = $s.K
      $opis = "$etykieta · $($s.N): $(Liczba-Pl $s.V) tokenów"
      if (($s.K -eq "p") -and $r.Pelna.Proba) { $klasa = "p proba"; $opis += " ($($r.Pelna.ProbaOpis))" }
      [void]$sb.Append("<rect class=`"$klasa`" x=`"$(& $f $s.X)`" y=`"$(& $f ($mt + $wys - $wysSlupka))`" width=`"$(& $f $bw)`" height=`"$(& $f $wysSlupka)`"><title>$(Html $opis)</title></rect>")
    }
    if (@($r.Bledy).Count -gt 0) {
      [void]$sb.Append("<rect class=`"b`" x=`"$(& $f ($ml + $slot * $i + 2))`" y=`"$(& $f ($mt + $wys + 2))`" width=`"$(& $f ($slot - 4))`" height=`"4`"><title>$(Html ($etykieta + ' · ' + ($r.Bledy -join ' · ')))</title></rect>")
    }
    if ((($dni.Count - 1 - $i) % $co) -eq 0) {
      $etk = (Dzien-Z $r.Dzien).ToString("dd.MM", $script:Inv)
      [void]$sb.Append("<text x=`"$(& $f ($ml + $slot * $i + $slot / 2))`" y=`"$($H - 8)`" text-anchor=`"middle`">$etk</text>")
    }
  }
  [void]$sb.Append("</svg>")
  return $sb.ToString()
}

function Zbuduj-Strone($m) {
  # $m: Odswiezono, Wiersze, Karty (wiersz albo $null), Suma, Uwagi, Tansza, Pelna, Cale, Dzis, Zrodla
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append("<!doctype html>`n<html lang=`"pl`"><head><meta charset=`"utf-8`"><meta name=`"viewport`" content=`"width=device-width,initial-scale=1`">")
  [void]$sb.Append("<meta name=`"color-scheme`" content=`"light dark`"><title>Koszt tworzenia wiedzy z rozmów</title><style>$STYL</style></head><body><main>`n")
  [void]$sb.Append("<h1>Koszt tworzenia wiedzy z rozmów</h1>")
  [void]$sb.Append("<p class=`"odswiezono`">Odświeżono $(Html $m.Odswiezono)</p>`n")

  if (@($m.Uwagi).Count -gt 0) {
    [void]$sb.Append("<div class=`"uwagi`"><b>Uwaga - nie wszystko udało się policzyć:</b><ul>")
    foreach ($u in $m.Uwagi) { [void]$sb.Append("<li>$(Html $u)</li>") }
    [void]$sb.Append("</ul></div>`n")
  }

  # --- karty
  $k = $m.Karty
  $wczoraj = Klucz-Dnia $m.Dzis.AddDays(-1)
  if ($k) {
    $kiedy = "Wczoraj, $(Data-Pl $k.Dzien)"
    if ($k.Dzien -ne $wczoraj) { $kiedy = "$(Data-Pl $k.Dzien) - ostatni dzień z danymi (za wczoraj jeszcze nic nie przeczytano)" }
    $caly = "całe zużycie tego dnia nie jest policzone"
    if ($k.Caly -and ($k.Caly.Razem -gt 0)) { $caly = "cały dzień Claude: $(Mln-Pl $k.Caly.Razem) mln tokenów" }
    elseif ($k.Caly) { $caly = "tego dnia nie ma w zapisie żadnej rozmowy z Claude" }
    [void]$sb.Append("<p class=`"dzien-kart`"><b>$(Html $kiedy)</b> · $(Html $caly)</p>")
  }
  [void]$sb.Append("<div class=`"karty`">")
  $t = $null; $p = $null
  if ($k) { $t = $k.Tansza; $p = $k.Pelna }
  $bladT = $null; $bladP = $null
  if ($k) {
    $bladT = @($k.Bledy | Where-Object { $_ -like "Tańsza*" }) | Select-Object -First 1
    $bladP = @($k.Bledy | Where-Object { $_ -like "Pełna*" }) | Select-Object -First 1
  }
  $dodT = @()
  if ($t -and $t.ZakresOd -and ((Dzien-Z $t.ZakresOd) -ne (Dzien-Z $t.Dzien))) { $dodT += "czytała rozmowy z $(Zakres-Krotko $t.ZakresOd $t.ZakresDo) (nadrabianie)" }
  if ($t -and ($t.Przebiegi -gt 1)) { $dodT += "$($t.Przebiegi) przebiegi tego dnia, zsumowane" }
  $brakT = "tego dnia poranny automat nic nie czytał"
  if (-not $m.Tansza.Jest) { $brakT = $m.Tansza.Powod }
  [void]$sb.Append((Karta-Wersji "t" "Tańsza wersja (pamięć osobista)" $(if ($t) { $t.Tokeny } else { $null }) $(if ($k) { $k.ProcTansza } else { $null }) `
    $(if ($t) { $t.Fakty } else { $null }) $(if ($t) { $t.Wywolania } else { $null }) $false $dodT $brakT $bladT))
  $mn = "—"; if ($k) { $mn = Iloraz-Pl $k.Iloraz }
  [void]$sb.Append("<div class=`"mnoznik`"><span>pełna =</span><b>$(Html $mn)</b><span>tańsza</span></div>")
  $dodP = @()
  if ($p -and ($null -ne $p.Usd)) {
    $u = "koszt: $(Usd-Pl $p.Usd)"
    $dodP += $u
  }
  if ($p -and $p.Proba) { $dodP += "$($p.ProbaOpis) - jednorazowa próba, nie codzienny przebieg"; if ($p.ProbaPrzed) { $dodP += $p.ProbaPrzed } }
  if ($p -and ($p.NieudaneWczesniej -gt 0)) { $dodP += "nieudane próby tego dnia: $($p.NieudaneWczesniej) (ich koszt jest wliczony)" }
  $brakP = "tego dnia pełna wersja nic nie czytała"
  if (-not $m.Pelna.Jest) { $brakP = $m.Pelna.Powod }
  [void]$sb.Append((Karta-Wersji "p" "Pełne czytanie dnia (wiedza firmy)" $(if ($p) { $p.Razem } else { $null }) $(if ($k) { $k.ProcPelna } else { $null }) `
    $(if ($p) { $p.Faktow } else { $null }) $(if ($p) { $p.Wywolan } else { $null }) $(if ($p) { [bool]$p.Proba } else { $false }) $dodP $brakP $bladP))
  [void]$sb.Append("</div>`n")
  if ($p -and (@($p.ListaPrzebiegow).Count -gt 0)) {
    [void]$sb.Append("<h2>Pełne czytanie dnia - na co poszły tokeny</h2><div class=`"panel rozbicie`">$(Rozbicie-Przebiegow $p)</div>`n")
  }

  # --- wykres
  [void]$sb.Append("<h2>Ostatnie $DniWykresu dni</h2><div class=`"panel`">")
  [void]$sb.Append("<div class=`"legenda`"><span><i style=`"background:var(--tansza)`"></i>tańsza (pamięć osobista)</span><span><i style=`"background:var(--pelna)`"></i>pełna (wiedza firmy)</span><span><i style=`"background:var(--blad)`"></i>błąd przebiegu</span></div>")
  [void]$sb.Append((Wykres-Svg $m.Wiersze))
  [void]$sb.Append("</div>`n")

  # --- tabela
  [void]$sb.Append("<h2>Wszystkie dni</h2><div class=`"panel tabela`"><table><thead>")
  [void]$sb.Append("<tr><th rowspan=`"2`" title=`"dzień rozmów, które dana wersja przeczytała`">dzień</th><th rowspan=`"2`">cały dzień Claude<br>(mln tokenów)</th>")
  [void]$sb.Append("<th class=`"grupa t`" colspan=`"3`">tańsza</th><th class=`"grupa p`" colspan=`"3`">pełna</th><th rowspan=`"2`">pełna ÷ tańsza</th></tr>")
  [void]$sb.Append("<tr><th>tokeny</th><th>%</th><th>fakty</th><th>tokeny</th><th>%</th><th>fakty</th></tr></thead><tbody>")
  foreach ($r in @($m.Wiersze)) {
    $klasa = ""
    if (@($r.Bledy).Count -gt 0) { $klasa = "zbledem" } elseif (-not (Ma-Dane $r)) { $klasa = "pusty" }
    $caly = "?"
    if ($r.Caly) { $caly = $(if ($r.Caly.Razem -gt 0) { Mln-Pl $r.Caly.Razem } else { "0" }) }
    $tc = @("—", "—", "—")
    if ($r.Tansza) { $tc = @((Liczba-Pl $r.Tansza.Tokeny), (Proc-Pl $r.ProcTansza), (Liczba-Pl $r.Tansza.Fakty)) }
    $pc = @("—", "—", "—")
    if ($r.Pelna) {
      $tok = Liczba-Pl $r.Pelna.Razem
      if ($r.Pelna.Proba) { $tok = "<span class=`"znacznik`">próba</span> " + $tok }
      $pc = @($tok, (Html (Proc-Pl $r.ProcPelna)), (Liczba-Pl $r.Pelna.Faktow))
    }
    [void]$sb.Append("<tr class=`"$klasa`"><td>$(Data-Pl $r.Dzien -ZDniem)</td><td>$caly</td>")
    [void]$sb.Append("<td>$($tc[0])</td><td>$(Html $tc[1])</td><td>$($tc[2])</td><td>$($pc[0])</td><td>$($pc[1])</td><td>$($pc[2])</td><td>$(Html (Iloraz-Pl $r.Iloraz))</td></tr>")
    if (@($r.Bledy).Count -gt 0) {
      $tech = ""
      if (@($r.BledyTech).Count -gt 0) { $tech = "<details class=`"tech`"><summary>szczegóły techniczne</summary><div>$(Html ($r.BledyTech -join ' · '))</div></details>" }
      [void]$sb.Append("<tr class=`"opis-bledu`"><td colspan=`"9`">$(Html ($r.Bledy -join ' · '))$tech</td></tr>")
    }
    if ($r.Pelna -and (@($r.Pelna.ListaPrzebiegow).Count -gt 0)) {
      $lp = @($r.Pelna.ListaPrzebiegow)
      $sum = "pełna wersja: na co poszły tokeny"
      if ($lp.Count -gt 1) { $sum += " ($($lp.Count) $(Odmiana $lp.Count 'przebieg' 'przebiegi' 'przebiegów'))" }
      $klSum = ""
      if (@($lp | Where-Object { $_.EtapyUwaga }).Count -gt 0) { $sum += " - suma etapów się nie zgadza"; $klSum = " class=`"czerwony`"" }
      [void]$sb.Append("<tr class=`"szczegoly`"><td colspan=`"9`"><details><summary$klSum>$(Html $sum)</summary><div class=`"rozbicie`">$(Rozbicie-Przebiegow $r.Pelna)</div></details></td></tr>")
    }
  }
  [void]$sb.Append("</tbody></table></div>`n")

  # --- suma
  $s = $m.Suma
  [void]$sb.Append("<h2>Suma za okres</h2><div class=`"panel suma`">")
  if ($s.Dni -gt 0) {
    [void]$sb.Append("<p><b>$(Data-Pl $s.Od) – $(Data-Pl $s.Do)</b> ($($s.Dni) $(Odmiana $s.Dni 'dzień' 'dni' 'dni')) · cały Claude: $(Mln-Pl $s.Caly) mln tokenów")
    if ($s.DniCalego -lt $s.Dni) { [void]$sb.Append(" (policzone dni: $($s.DniCalego))") }
    [void]$sb.Append("</p>")
    if ($s.TanszaDni -gt 0) {
      [void]$sb.Append("<p><b>Tańsza:</b> $(Liczba-Pl $s.Tansza) tokenów w $($s.TanszaDni) $(Odmiana $s.TanszaDni 'dniu' 'dniach' 'dniach') = $(Html (Proc-Pl $s.ProcTansza)) całego zużycia tych dni</p>")
    } else { [void]$sb.Append("<p><b>Tańsza:</b> brak danych</p>") }
    if ($s.PelnaDni -gt 0) {
      $ogon = ""; if ($s.PelnaProby -gt 0) { $ogon = " (w tym próba 14.10 po optymalizacji)" }
      [void]$sb.Append("<p><b>Pełna:</b> $(Liczba-Pl $s.Pelna) tokenów w $($s.PelnaDni) $(Odmiana $s.PelnaDni 'dniu' 'dniach' 'dniach') = $(Html (Proc-Pl $s.ProcPelna)) całego zużycia tych dni$ogon</p>")
    } else { [void]$sb.Append("<p><b>Pełna:</b> brak danych</p>") }
  } else { [void]$sb.Append("<p>Brak danych.</p>") }
  [void]$sb.Append("</div>`n")

  # --- stopka
  $cache = "ok. 97% dnia"
  if ($null -ne $s.ProcCache) { $cache = "w tym okresie $(Proc-Pl $s.ProcCache) wszystkich tokenów" }
  [void]$sb.Append("<div class=`"stopka`"><p>% liczony od wszystkich tokenów dnia, razem z odczytem z cache ($(Html $cache)).</p>")
  $bezT = "?"; $bezP = "?"
  if ($null -ne $s.ProcTanszaBezCache) { $bezT = "najwyżej " + (Proc-Pl $s.ProcTanszaBezCache) }
  if ($null -ne $s.ProcPelnaBezCache) { $bezP = Proc-Pl $s.ProcPelnaBezCache }
  [void]$sb.Append("<p>Bez odczytu z cache (suma za okres): tańsza $(Html $bezT), pełna $(Html $bezP) całego zużycia. Tańsza &bdquo;najwyżej&rdquo;, bo jej dziennik nie rozbija tokenów na odczyt z cache - liczę je wszystkie.</p>")
  [void]$sb.Append("<p>Źródła: $(Html ($m.Zrodla -join ' · '))</p></div>")
  [void]$sb.Append("`n</main></body></html>`n")
  return $sb.ToString()
}

function Strona-Bledu($odswiezono, $powod) {
  return ("<!doctype html>`n<html lang=`"pl`"><head><meta charset=`"utf-8`"><meta name=`"color-scheme`" content=`"light dark`">" +
    "<title>Koszt tworzenia wiedzy z rozmów</title><style>$STYL</style></head><body><main>" +
    "<h1>Koszt tworzenia wiedzy z rozmów</h1><p class=`"odswiezono`">Próba odświeżenia $(Html $odswiezono)</p>" +
    "<div class=`"uwagi`"><b>Strony nie udało się zbudować.</b><ul><li>$(Html $powod)</li></ul></div>" +
    "</main></body></html>`n")
}

# Znacznik dla koszt-wiedzy.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztuWiedzy["strona"] = $true
