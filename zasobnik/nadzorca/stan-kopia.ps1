# zasobnik\nadzorca\stan-kopia.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Kopia zapasowa na Dysk Google (narzedzia\kopia-zapasowa.ps1):
# odczyt jej znacznika ~\.claude\mr\kopia-stan.txt (Stan-Kopii), ocena - jedna linia na
# Przeglad i ewentualny alarm (Ocena-Kopii, Alarm-Kopii) - i wiersze do Szczegolow
# (Opis-Kopii).
# Skad wolane: stan-zbieranie.ps1 (Zbierz-Wszystko -> $d.Kopia), stan-alarmy.ps1
# (Zbierz-Alarmy), przeglad.ps1 (Odmaluj-Stan), przeglad-tresc.ps1 (Zbuduj-Przod),
# szczegoly.ps1 (Sekcje-Szczegolow). Wczytuje go stan-nadzorcy.ps1 kropka - same definicje.
#
# Skad to sie wzielo (P62, 02.10.2026): kopia zapasowa chodzi w tle z Harmonogramu
# i pisze tylko swoj plik stanu. Pierwszego dnia pominela 59 wyzerowanych plikow z ALARMEM,
# ktorego nikt nie zobaczyl - bo nikt nie zaglada do pliku stanu. Brak wiadomosci nie moze
# znaczyc "wszystko gra": okno mowi wiec zawsze, kiedy byla ostatnia udana kopia.

# PROG: ostatnia UDANA kopia starsza niz 48 h = alarm. Kopia chodzi raz dziennie (12:30),
# a przegapiona, bo komputer byl wylaczony, rusza sama zaraz po wlaczeniu
# (StartWhenAvailable w zadaniu MegaRuchaczKopia) - jeden opuszczony dzien nie robi wiec
# dziury wiekszej niz ok. doba. Dwie doby bez udanej kopii to co najmniej dwa przebiegi
# z rzedu nieudane albo pominiete: usterka, nie przypadek. "2 dni" ze zlecenia uzytkownika.
$GODZIN_KOPIA_STARA = 48
# Przez pierwsza godzine po wlaczeniu komputera stara kopia nie jest jeszcze alarmem, tylko
# zolta linia: zalegly przebieg rusza sam po starcie, a Dysk Google musi najpierw wstac.
# Bez tego kazdy poniedzialek po weekendzie bez komputera dawalby falszywy alarm - a
# falszywy alarm uczy ignorowania prawdziwych.
$MINUT_PO_STARCIE_KOPII = 60
# "stan=TRWA" ze startem starszym niz tyle = przebieg przerwany (wylaczony komputer, zabity
# proces). Pierwsza, pelna kopia (02.10, 24 706 plikow, 4,9 GB) trwala 10 minut, przyrostowa
# 22 s - trzy godziny to zapas kilkunastokrotny, a przerwana kopia i tak wyjdzie najdalej
# po dwoch dobach jako stara.
$GODZIN_KOPIA_TRWA_NAJWYZEJ = 3

# Minuty od wlaczenia komputera. TickCount to int32 milisekund - po 24,9 dnia staje sie
# ujemny (dodajemy 2^32), po 49,7 dnia zawija sie do zera; wtedy przez godzine stara kopia
# bedzie zolta zamiast czerwonej - raz na siedem tygodni, do zniesienia.
function Minut-Od-Startu {
  $ms = [double][Environment]::TickCount
  if ($ms -lt 0) { $ms += 4294967296 }
  return ($ms / 60000)
}

function Plik-Stanu-Kopii { return (Join-Path $script:NadzDom ".claude\mr\kopia-stan.txt") }
function Plik-Indeksu-Kopii { return (Join-Path $script:NadzDom ".claude\mr\kopia-indeks.tsv") }

# Odczyt pliku stanu kopii i indeksu (indeks powstaje TYLKO po zakonczonym przebiegu, wiec
# jego data to ostatnia udana kopia - takze wtedy, gdy ostatni przebieg sie przerwal).
# Zwraca obiekt zawsze; Powod mowi, czego nie dalo sie odczytac.
function Stan-Kopii {
  $plik = Plik-Stanu-Kopii
  $indeks = Plik-Indeksu-Kopii
  $k = [pscustomobject]@{
    Jest = $false; Plik = $plik; Indeks = $indeks; Powod = ""; Stan = ""; Ostatnia = $null; Start = $null
    Rodzaj = ""; Cel = ""; Plikow = $null; Mb = ""; Alarmy = 0; Bledy = 0; WUzyciu = 0; Blad = ""
    Uszkodzone = @(); UszkodzoneTeraz = 0; InneAlarmy = @(); ListaBledow = @(); OstatniaUdana = $null; Dziennik = ""
  }
  if (Test-Path -LiteralPath $indeks -PathType Leaf) { $k.OstatniaUdana = (Get-Item -LiteralPath $indeks).LastWriteTime }
  if (-not (Test-Path -LiteralPath $plik -PathType Leaf)) { return $k }
  $k.Jest = $true
  $tekst = $null
  try { $tekst = [System.IO.File]::ReadAllText($plik, [System.Text.Encoding]::UTF8) }
  catch { $k.Powod = "nie da się odczytać pliku stanu kopii: $($_.Exception.Message)"; return $k }
  if ($tekst.IndexOf([char]0) -ge 0) { $k.Powod = "plik stanu kopii ma w środku zera (uszkodzony zapis, zwykle po zaniku prądu)"; return $k }
  $kl = @{}
  $usz = @(); $inne = @(); $bl = @()
  foreach ($l in ($tekst -split "\r?\n")) {
    if ($l -match '^ALARM WYZEROWANY PLIK[^:]*:\s*(.+)$') { $usz += $Matches[1].Trim(); continue }
    if ($l -match '^ALARM\s') { $inne += $l.Trim(); continue }
    if ($l -match '^BLAD\s+(.+)$') { $bl += $Matches[1].Trim(); continue }
    $m = [regex]::Match($l, '^([a-z_]+)=(.*)$')
    if ($m.Success) { $kl[$m.Groups[1].Value] = $m.Groups[2].Value.Trim() }
  }
  $data = {
    param($t)
    $d = [datetime]::MinValue
    if ($t -and [datetime]::TryParseExact($t, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { return $d }
    return $null
  }
  $k.Stan = "$($kl['stan'])".ToUpperInvariant()
  $k.Ostatnia = & $data $kl['ostatnia']
  $k.Start = & $data $kl['start']
  $k.Rodzaj = "$($kl['rodzaj'])"; $k.Cel = "$($kl['cel'])"; $k.Mb = "$($kl['mb'])"; $k.Blad = "$($kl['blad'])"
  $n = 0
  if ([int]::TryParse("$($kl['plikow'])", [ref]$n)) { $k.Plikow = $n }
  if ([int]::TryParse("$($kl['alarmy'])", [ref]$n)) { $k.Alarmy = $n }
  if ([int]::TryParse("$($kl['bledy'])", [ref]$n)) { $k.Bledy = $n }
  if ([int]::TryParse("$($kl['w_uzyciu'])", [ref]$n)) { $k.WUzyciu = $n }
  $k.Uszkodzone = $usz; $k.InneAlarmy = $inne; $k.ListaBledow = $bl
  $k.UszkodzoneTeraz = Ile-Nadal-Uszkodzonych $usz
  # Ostatni zakonczony przebieg jest swiezszy niz indeks tylko o sekundy - ale gdyby indeksu
  # nie bylo (usuniety recznie), data z pliku stanu tez dowodzi udanej kopii.
  if ($k.Ostatnia -and (@("OK", "ALARM") -contains $k.Stan -or ($k.Stan -eq "BLAD" -and $null -ne $k.Plikow))) {
    if (-not $k.OstatniaUdana -or $k.Ostatnia -gt $k.OstatniaUdana) { $k.OstatniaUdana = $k.Ostatnia }
  }
  # dziennik lezy w korzeniu kopii: <Backup>\zmiany\RRRR-MM-DD albo <Backup>\pelna-RRRR-MM-DD
  $cel = $k.Cel.TrimEnd('\')
  if ($cel -match '^(.*)\\zmiany\\[^\\]+$') { $k.Dziennik = "$($Matches[1])\dziennik.txt" }
  elseif ($cel -match '^(.*)\\pelna-[^\\]+$') { $k.Dziennik = "$($Matches[1])\dziennik.txt" }
  elseif ($cel) { $k.Dziennik = "$cel\dziennik.txt" }
  return $k
}

# Ile z plikow pominietych przez ostatnia kopie jako uszkodzone jest uszkodzonych NADAL.
# Pliki naprawione po kopii (np. skill wgrany od nowa) wejda do nastepnej kopii same -
# czerwony alarm o nich bylby do tego czasu falszywy. Rozpoznanie jak w kopia-zapasowa.ps1:
# ciag co najmniej 64 bajtow 0x00 albo caly plik z zer (tekst nie ma nigdy wiecej niz 3 zera
# pod rzad). Plik, ktorego juz nie ma, nie jest uszkodzony. Najwyzej 200 plikow - dalej
# liczymy wszystkie reszty jako uszkodzone (lepiej alarm niz cisza).
# (pliki binarne maja dlugie ciagi zer z natury - u nich tylko "caly plik z zer"; lista
# z kopia-zapasowa.ps1, $RozszBinarne)
$ROZSZERZENIA_BINARNE_KOPII = @(".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".bmp", ".pdf", ".zip", ".gz", ".7z", ".rar",
  ".exe", ".dll", ".bin", ".onnx", ".safetensors", ".pyc", ".woff", ".woff2", ".ttf", ".db", ".sqlite", ".sqlite3", ".mp4",
  ".webm", ".pma", ".node", ".xlsx", ".xls", ".docx", ".doc", ".pptx", ".ppt", ".odt", ".ods", ".jar", ".class", ".mp3", ".wav",
  ".mov", ".avi", ".tar", ".tgz", ".bz2", ".xz", ".wasm")
function Ile-Nadal-Uszkodzonych($wpisy) {
  $ile = 0; $nr = 0
  $zera64 = New-Object string ([char]0), 64
  foreach ($w in @($wpisy)) {
    $nr++
    if ($nr -gt 200) { $ile++; continue }
    $m = [regex]::Match("$w", '^(.+?) - (blok|caly plik)')
    if (-not $m.Success) { $ile++; continue }
    $p = $m.Groups[1].Value
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
    try {
      $t = [System.Text.Encoding]::GetEncoding(28591).GetString([System.IO.File]::ReadAllBytes($p))
      $binarny = $ROZSZERZENIA_BINARNE_KOPII -contains [System.IO.Path]::GetExtension($p).ToLowerInvariant()
      if (($t.Length -gt 0) -and ((-not $binarny -and $t.IndexOf($zera64, [System.StringComparison]::Ordinal) -ge 0) -or ($t.Trim([char]0).Length -eq 0))) { $ile++ }
    } catch { $ile++ }
  }
  return $ile
}

function Ile-Plikow([int]$n) { return "$(Liczba-Ludzka $n) $(Odmiana $n 'plik' 'pliki' 'plików')" }

# Linia na Przeglad, jej waga (""/"szary"/"uwaga"/"pilne") i - gdy jest o czym alarmowac -
# tytul, porada i pelna tresc alarmu. Kolejnosc spraw: uszkodzone pliki, stara kopia,
# inne alarmy kopii, przebieg przerwany, bledy; na wierzch idzie pierwsza, w tresci wszystkie.
function Ocena-Kopii($k) {
  $o = [pscustomobject]@{ Linia = ""; Waga = ""; Alarm = $false; AlarmWaga = ""; Tytul = ""; Porada = ""; Tresc = "" }
  if (-not $k) { $o.Linia = "Kopia zapasowa: nie wiem, nie udało się odczytać jej stanu."; $o.Waga = "uwaga"; return $o }
  if (-not $k.Jest -and -not $k.OstatniaUdana) {
    # Na komputerze bez kopii (np. domowym) to nie usterka - bez alarmu.
    $o.Linia = "Kopia zapasowa: nie jest ustawiona na tym komputerze."; $o.Waga = "szary"; return $o
  }
  $teraz = [datetime]::Now
  $udana = $(if ($k.OstatniaUdana) { "ostatnia udana $(Kiedy-Ludzko $k.OstatniaUdana)" } else { "ani jednej udanej kopii" })
  $trwa = ($k.Stan -eq "TRWA") -and $k.Start -and (($teraz - $k.Start).TotalHours -lt $GODZIN_KOPIA_TRWA_NAJWYZEJ)
  $stara = (-not $k.OstatniaUdana) -or (($teraz - $k.OstatniaUdana).TotalHours -gt $GODZIN_KOPIA_STARA)
  $polecenie = "powershell -ExecutionPolicy Bypass -File `"$($script:NadzZrodlo)\narzedzia\kopia-zapasowa.ps1`" -Proba"
  $gdzie = "Plik stanu: $($k.Plik)." + $(if ($k.Dziennik) { " Dziennik kopii: $($k.Dziennik)." } else { "" })

  if ($trwa) {
    $o.Linia = "Kopia zapasowa: właśnie trwa (od $($k.Start.ToString('HH:mm'))); $udana."
    return $o
  }
  $sprawy = @()   # @(waga, linia, tytul, porada, tresc)
  if ($k.Powod) {
    $sprawy += ,@("uwaga", "Kopia zapasowa: nie wiem, jak poszła - $($k.Powod); $udana.", "MegaRuchacz: nie umiem odczytać stanu kopii zapasowej",
      "Plik, w którym kopia zapisuje swój stan, jest nieczytelny. Następna kopia zapisze go od nowa; ścieżka jest w zakładce Szczegóły.",
      "Powod: $($k.Powod). $gdzie")
  }
  if ((@($k.Uszkodzone).Count -gt 0) -and ($k.UszkodzoneTeraz -eq 0)) {
    # wszystkie juz naprawione (albo usuniete) - wejda do nastepnej kopii; bez alarmu
    $n = @($k.Uszkodzone).Count
    $sprawy += ,@("uwaga", "Kopia zapasowa: $(Kiedy-Ludzko $k.Ostatnia), $(Ile-Plikow ([int]$k.Plikow)); $n $(Odmiana $n 'pominięty jako uszkodzony jest' 'pominięte jako uszkodzone są' 'pominiętych jako uszkodzone jest') już $(Odmiana $n 'naprawiony' 'naprawione' 'naprawionych') - $(Odmiana $n 'wejdzie' 'wejdą' 'wejdzie') do następnej kopii.", "", "", "")
  } elseif (@($k.Uszkodzone).Count -gt 0) {
    $n = [int]$k.UszkodzoneTeraz; $wszystkich = @($k.Uszkodzone).Count
    $kiedy = $(if ($k.Ostatnia) { " (kopia $(Kiedy-Ludzko $k.Ostatnia))" } else { "" })
    $linia = $(if ($n -eq $wszystkich) { "Kopia zapasowa: ALARM - $(Ile-Plikow $n) $(Odmiana $n 'pominięty' 'pominięte' 'pominiętych'), bo $(Odmiana $n 'uszkodzony' 'uszkodzone' 'uszkodzone')$kiedy." }
               else { "Kopia zapasowa: ALARM - $n z $wszystkich plików pominiętych jako uszkodzone $(Odmiana $n 'jest nadal uszkodzony' 'są nadal uszkodzone' 'jest nadal uszkodzonych')$kiedy." })
    $sprawy += ,@("pilne", $linia,
      "MegaRuchacz: kopia zapasowa pominęła $(Ile-Plikow $n) z samymi zerami",
      "Te pliki mają w środku same zera (uszkodzony zapis, zwykle po zaniku prądu), więc kopia ich nie wzięła - ich zdrowe wersje zostają w starszej kopii. Napraw albo przywróć te pliki; lista jest w zakładce Szczegóły. Następna kopia sprawdzi je od nowa.",
      ("Pominiete uszkodzone pliki ($wszystkich, nadal uszkodzonych $n): " + (@($k.Uszkodzone | Select-Object -First 10) -join "; ") + $(if ($wszystkich -gt 10) { "; i $($wszystkich - 10) wiecej" } else { "" }) + ". $gdzie"))
  }
  if ($stara -and -not $k.Powod) {
    $ile = $(if ($k.OstatniaUdana) { [int][math]::Floor(($teraz - $k.OstatniaUdana).TotalDays) } else { $null })
    $linia = $(if ($k.OstatniaUdana) { "Kopia zapasowa: ALARM - ostatnia udana kopia $(Kiedy-Ludzko $k.OstatniaUdana)." } else { "Kopia zapasowa: ALARM - nie było jeszcze ani jednej udanej kopii." })
    $porada = "$(if ($k.OstatniaUdana) { 'Kopia zapasowa na Dysk Google nie udała się od ponad dwóch dób.' } else { 'Nie było jeszcze ani jednej udanej kopii zapasowej na Dysk Google.' }) Sprawdź, czy działa Dysk Google (dysk G:) - powód ostatniej próby jest w zakładce Szczegóły."
    $tresc = "Ostatnia udana kopia: $(if ($k.OstatniaUdana) { $k.OstatniaUdana.ToString('yyyy-MM-dd HH:mm') } else { 'brak' }); prog $GODZIN_KOPIA_STARA h. Ostatni przebieg: stan $($k.Stan)$(if ($k.Blad) { ', ' + $k.Blad }). $gdzie Sprawdzenie bez kopiowania: $polecenie"
    if ((Minut-Od-Startu) -lt $MINUT_PO_STARCIE_KOPII) {
      # pierwsza godzina po wlaczeniu komputera: zalegla kopia zwykle wlasnie rusza
      $sprawy += ,@("uwaga", "Kopia zapasowa: zaległa ($udana) - powinna ruszyć sama zaraz po włączeniu komputera.", "", "", "")
    } else {
      $sprawy += ,@("pilne", $linia, "MegaRuchacz: kopia zapasowa nie idzie$(if ($null -ne $ile) { " od $ile $(Odmiana $ile 'dnia' 'dni' 'dni')" })", $porada, $tresc)
    }
  }
  if (@($k.InneAlarmy).Count -gt 0) {
    $sprawy += ,@("pilne", "Kopia zapasowa: ALARM - $(@($k.InneAlarmy)[0] -replace '^ALARM\s+', '')", "MegaRuchacz: kopia zapasowa zgłasza alarm",
      "Kopia zapasowa zgłosiła problem, który wymaga sprawdzenia - pełna treść jest w zakładce Szczegóły.",
      ((@($k.InneAlarmy) -join "; ") + ". $gdzie"))
  }
  if ($k.Stan -eq "TRWA") {
    $sprawy += ,@("uwaga", "Kopia zapasowa: przerwana w trakcie (ruszyła $(Kiedy-Ludzko $k.Start)); $udana.", "MegaRuchacz: kopia zapasowa urwała się w połowie",
      "Kopia ruszyła i nie skończyła (wyłączony komputer albo zatrzymany proces). Następna spróbuje sama o zwykłej porze.",
      "stan=TRWA od $(if ($k.Start) { $k.Start.ToString('yyyy-MM-dd HH:mm') } else { '?' }), prog $GODZIN_KOPIA_TRWA_NAJWYZEJ h. $gdzie")
  } elseif ($k.Stan -eq "BLAD" -and $k.Blad) {
    $sprawy += ,@("uwaga", "Kopia zapasowa: ostatnia próba przerwana $(Kiedy-Ludzko $k.Ostatnia) - powód w Szczegółach; $udana.", "MegaRuchacz: kopia zapasowa się nie udała",
      "Ostatnia kopia przerwała się z błędem (najczęściej: Dysk Google nie działał). Następna spróbuje sama o zwykłej porze; powód jest w zakładce Szczegóły.",
      "Blad: $($k.Blad). $gdzie Sprawdzenie bez kopiowania: $polecenie")
  } elseif ($k.Bledy -gt 0) {
    $sprawy += ,@("uwaga", "Kopia zapasowa: $(Kiedy-Ludzko $k.Ostatnia), $(Ile-Plikow ([int]$k.Plikow)), $(Liczba-Ludzka $k.Bledy) $(Odmiana $k.Bledy 'błąd' 'błędy' 'błędów') - lista w Szczegółach.", "MegaRuchacz: kopia zapasowa z błędami",
      "Kopia przeszła, ale części plików nie dało się skopiować - lista jest w zakładce Szczegóły.",
      ("Bledy ($($k.Bledy)): " + (@($k.ListaBledow | Select-Object -First 5) -join "; ") + ". $gdzie"))
  }
  if ($sprawy.Count -eq 0) {
    $mb = $(if ($k.Mb) { " ($($k.Mb) MB)" } else { "" })
    $o.Linia = "Kopia zapasowa: $(Kiedy-Ludzko $k.Ostatnia), $(Ile-Plikow ([int]$k.Plikow))$mb, bez błędów."
    return $o
  }
  # wybor po indeksach - tablice w potoku PowerShella nie zachowuja tozsamosci obiektu
  $iPierwsza = 0
  for ($i = $sprawy.Count - 1; $i -ge 0; $i--) { if ($sprawy[$i][0] -eq "pilne") { $iPierwsza = $i } }
  $o.Linia = $sprawy[$iPierwsza][1]; $o.Waga = $sprawy[$iPierwsza][0]
  $zAlarmem = @(); for ($i = 0; $i -lt $sprawy.Count; $i++) { if ($sprawy[$i][2]) { $zAlarmem += $i } }
  if ($zAlarmem.Count -gt 0) {
    $iGlowna = $zAlarmem[0]
    foreach ($i in $zAlarmem) { if ($sprawy[$i][0] -eq "pilne") { $iGlowna = $i; break } }
    $g = $sprawy[$iGlowna]
    $o.Alarm = $true; $o.AlarmWaga = $g[0]; $o.Tytul = $g[2]; $o.Porada = $g[3]
    $o.Tresc = (@($zAlarmem | ForEach-Object { $sprawy[$_][4] }) -join " ")
    $reszta = @($zAlarmem | Where-Object { $_ -ne $iGlowna } | ForEach-Object { ($sprawy[$_][1] -replace '^Kopia zapasowa:\s*', '') })
    if ($reszta.Count -gt 0) { $o.Porada += " (Kopia zgłasza też: " + ($reszta -join " ") + ")" }
  }
  return $o
}

# Alarm do Zbierz-Alarmy (temat "kopia" - jeden dymek na dobe) albo $null.
function Alarm-Kopii {
  $o = Ocena-Kopii (Stan-Kopii)
  if (-not $o.Alarm) { return $null }
  return (Alarm "kopia" $o.Tytul $o.Tresc $o.AlarmWaga $o.Porada)
}

# Wiersze do Szczegolow: wszystko, co wiadomo, z wagami.
function Opis-Kopii($k) {
  $w = @()
  $o = Ocena-Kopii $k
  $w += Wiersz "Stan" ($o.Linia -replace '^Kopia zapasowa:\s*', '') $o.Waga
  if (-not $k) { return ,$w }
  if ($k.Jest -or $k.OstatniaUdana) {
    $w += Wiersz "Ostatnia udana kopia" $(if ($k.OstatniaUdana) { "$($k.OstatniaUdana.ToString('yyyy-MM-dd HH:mm')) ($(Kiedy-Ludzko $k.OstatniaUdana))" } else { "nie było ani jednej" }) $(if ($o.Waga -eq "pilne" -and -not $k.OstatniaUdana) { "pilne" } else { "" })
  }
  if ($k.Jest -and -not $k.Powod) {
    $w += Wiersz "Ostatni przebieg" ("$(if ($k.Ostatnia) { $k.Ostatnia.ToString('yyyy-MM-dd HH:mm') } elseif ($k.Start) { 'ruszył ' + $k.Start.ToString('yyyy-MM-dd HH:mm') } else { '?' }) - stan $($k.Stan)$(if ($k.Rodzaj) { ', ' + $k.Rodzaj })")
    if ($null -ne $k.Plikow) { $w += Wiersz "Skopiowane" "$(Ile-Plikow $k.Plikow)$(if ($k.Mb) { ', ' + $k.Mb + ' MB' })" }
    if ($k.Blad) { $w += Wiersz "Powód przerwania" $k.Blad "uwaga" }
    $n = @($k.Uszkodzone).Count
    $w += Wiersz "Pominięte uszkodzone" $(if ($n -gt 0) { "$(Ile-Plikow $n) z samymi zerami - zdrowe wersje zostają w starszej kopii; nadal uszkodzonych teraz: $($k.UszkodzoneTeraz)" } else { "żadnych" }) $(if ($k.UszkodzoneTeraz -gt 0) { "pilne" } elseif ($n -gt 0) { "uwaga" } else { "" })
    foreach ($u in @($k.Uszkodzone | Select-Object -First 15)) { $w += Wiersz "" $u "szary" }
    if ($n -gt 15) { $w += Wiersz "" "i $($n - 15) więcej - pełna lista w pliku stanu (niżej)" "szary" }
    foreach ($a in @($k.InneAlarmy)) { $w += Wiersz "Alarm" $a "pilne" }
    $w += Wiersz "Błędy" $(if ($k.Bledy -gt 0) { "$($k.Bledy)" } else { "żadnych" }) $(if ($k.Bledy -gt 0) { "uwaga" } else { "" })
    foreach ($b in @($k.ListaBledow | Select-Object -First 5)) { $w += Wiersz "" $b "szary" }
    if ($k.WUzyciu -gt 0) { $w += Wiersz "W użyciu" "$(Ile-Plikow $k.WUzyciu) pominiętych, bo były otwarte - spróbuje jutro" "szary" }
  }
  if ($k.Cel) { $w += Wiersz "Gdzie leży kopia" $k.Cel "szary" }
  if ($k.Dziennik) { $w += Wiersz "Dziennik kopii" $k.Dziennik "szary" }
  $w += Wiersz "Plik stanu" $k.Plik "szary"
  $w += Wiersz "Kiedy alarm" "ostatnia udana kopia starsza niż $GODZIN_KOPIA_STARA h (kopia idzie raz dziennie, przegapiona rusza po włączeniu komputera - dwie doby to dwa nieudane przebiegi z rzędu) albo pominięte uszkodzone pliki" "szary"
  return ,$w
}

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["kopia"] = $true
