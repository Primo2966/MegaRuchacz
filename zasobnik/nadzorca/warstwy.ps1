# zasobnik\nadzorca\warstwy.ps1 - czesc zasobnik\nadzorca.ps1 (patrz BUDOWA
# w jego naglowku). Zakladka Warstwy pamieci: lista warstw z Warstwy-Pamieci
# (Napelnij-Warstwy, Zdanie-Warstw, $KOLEJNOSC_KIEDY) - od P59d tylko warstwy
# zainstalowanych modulow (Moduly-Warstwy), opisy po ludzku (kiedy,
# trwalosc, stan, rozmiar) i prawa strona: dwie kolumny o warstwie
# (Pokaz-Info-Warstwy) i podglad tresci (Pokaz-Podglad).
# Skad wolane: w-tle.ps1 (Wyrenderuj-Widok -> Napelnij-Warstwy) i okno.ps1
# (wybor na liscie -> Pokaz-Podglad). Wczytuje go nadzorca.ps1 kropka po zamku
# jednej kopii - poza stala $KOLEJNOSC_KIEDY same definicje.

# --- warstwy pamieci -----------------------------------------------------------
# Wszystko o warstwach pochodzi z Warstwy-Pamieci (narzedzia\koszt-pamieci.ps1
# -Warstwy) - okno nie zna zadnej sciezki samo z siebie. Samo tylko CZYTA plik
# wybranej warstwy do podgladu i niczego nie zapisuje.

$KOLEJNOSC_KIEDY = @("start", "wiadomosc", "zadanie", "nieuzywane")

function Kiedy-Po-Ludzku([string]$k) {
  switch ($k) {
    "start"      { return "Raz, przy otwarciu okna rozmowy" }
    "wiadomosc"  { return "Przy każdej wiadomości" }
    "zadanie"    { return "Tylko na żądanie" }
    "nieuzywane" { return "Nieużywane - nikt ich nie wczytuje" }
  }
  return "Inne ($k)"
}

function Trwalosc-Po-Ludzku([string]$t) {
  switch ($t) {
    "stala"      { return "stała" }
    "tymczasowa" { return "tymczasowa" }
    "mieszana"   { return "stała + tymcz." }
  }
  return "$t"
}

function Stan-Po-Ludzku([string]$s) {
  switch ($s) {
    "jest"       { return "jest" }
    "pusty"      { return "pusta" }
    "brak"       { return "BRAK" }
    "blad"       { return "BŁĄD ODCZYTU" }
    "nieaktywna" { return "teraz nieaktywna" }
  }
  return "$s"
}

function Rozmiar-Ludzki($bajty) {
  if ($null -eq $bajty) { return "rozmiar nieznany" }
  if ($bajty -lt 1024)    { return "$bajty B" }
  if ($bajty -lt 1048576) { return "$([math]::Round($bajty / 1024, 1)) KB" }
  return "$([math]::Round($bajty / 1048576, 1)) MB"
}

# Kolumna "Rozmiar": liczba znakow, a gdy jej nie ma - krotko, dlaczego nie ma.
# Brak pliku ma byc widoczny w samej liscie, nie dopiero po kliknieciu.
function Rozmiar-Warstwy($wa) {
  switch ("$($wa.Stan)") {
    "brak" {
      if ($wa.Rodzaj -eq "katalog") { return "BRAK KATALOGU" }
      if (($wa.Rodzaj -eq "podwarstwa") -and $wa.Istnieje) { return "BRAK SEKCJI" }
      return "BRAK PLIKU"
    }
    "blad"       { return "BŁĄD ODCZYTU" }
    "pusty"      { return "pusta" }
    "nieaktywna" { return "teraz nic" }
  }
  if ($wa.Rodzaj -eq "katalog") { return "$(@($wa.Pliki).Count) plików" }
  if ($wa.Rodzaj -eq "baza")    { return (Rozmiar-Ludzki $wa.Bajty) }
  if ($null -ne $wa.Znaki)      { return "$(Liczba-Ludzka $wa.Znaki) zn." }
  if ($null -ne $wa.Limit)      { return "do $(Liczba-Ludzka $wa.Limit) zn." }
  return "nieznany"
}

# Ten sam rozmiar pelnym zdaniem, z jednostka - do podgladu.
function Rozmiar-Opisowy($wa) {
  if ($wa.Rodzaj -eq "baza") { return (Rozmiar-Ludzki $wa.Bajty) + " (bazy nie liczy się w znakach)" }
  if ($wa.Rodzaj -eq "katalog") { return "$(@($wa.Pliki).Count) plików" }
  if ($null -ne $wa.Znaki) {
    $t = "$(Liczba-Ludzka $wa.Znaki) znaków"
    if ($null -ne $wa.Tokeny) {
      # P15: tokeny takze jako procent jednego otwarcia sesji Claude Code.
      # Warstwy Codeksa bez procentu - jego otwarcia sesji nikt nie mierzy.
      $js = ""
      if ("$($wa.Nazwa)" -notmatch 'tylko Codex') {
        $o = $null
        try { if ($script:Start) { $o = Opis-Startu $script:Start } } catch { Zanotuj-Wywrotke "opis otwarcia okna rozmowy do warstwy" $_ }
        $js = Jak-Sesji $wa.Tokeny $o
      }
      if ($js) { $t += " (~$(Liczba-Ludzka $wa.Tokeny) tokenów, $js)" }
      else { $t += " (~$(Liczba-Ludzka $wa.Tokeny) tokenów)" }
    }
    return $t
  }
  if ($null -ne $wa.Limit) { return "do $(Liczba-Ludzka $wa.Limit) znaków, za każdym razem inna treść" }
  return "nieznany"
}

# Jedno zdanie po ludzku nad lista. KAZDA liczba w nim odnosi sie do tej samej
# podstawy - warstw glownych (bez podwarstw i pojedynczych plikow wiedzy) - i kazdy
# podzial sumuje sie do ich liczby. Do 2026-09-25 "kiedy" liczylo sie od warstw
# glownych, a "stala/tymczasowa" od podwarstw: 12 warstw, a stalych i tymczasowych
# razem 18 - dla czlowieka sprzecznosc. Warstwa, ktorej podwarstwy sa roznej
# trwalosci (globalny CLAUDE.md, katalog wiedzy), liczy sie jako mieszana i zdanie
# mowi wprost, co w niej jest tymczasowe.
function Zdanie-Warstw($dw) {
  $wszystkie = @($dw.Warstwy)
  $glowne = @($wszystkie | Where-Object { -not $_.Rodzic })
  $ile = $glowne.Count
  $czesci = @()
  foreach ($k in $KOLEJNOSC_KIEDY) {
    $n = @($glowne | Where-Object { $_.Kiedy -eq $k }).Count
    switch ($k) {
      "start"      { $czesci += "$n przy otwarciu okna rozmowy" }
      "wiadomosc"  { $czesci += "$n przy każdej wiadomości" }
      "zadanie"    { $czesci += "$n tylko na żądanie" }
      "nieuzywane" { if ($n -gt 0) { $czesci += "$n $(Odmiana $n 'nieużywana' 'nieużywane' 'nieużywanych')" } }
    }
  }
  # "kiedy" spoza znanych czterech tez musi sie pokazac - inaczej suma sie nie zgodzi
  $inne = @($glowne | Where-Object { $KOLEJNOSC_KIEDY -notcontains "$($_.Kiedy)" }).Count
  if ($inne -gt 0) { $czesci += "$inne $(Odmiana $inne 'inna' 'inne' 'innych')" }
  $z = "$ile $(Odmiana $ile 'warstwa' 'warstwy' 'warstw') pamięci: " + ($czesci -join ", ") + "."

  # Trwalosc warstwy glownej: jej wlasna, a gdy ma podwarstwy roznej trwalosci - mieszana.
  $st = 0; $tm = 0; $nz = 0
  $mieszane = @()
  foreach ($g in $glowne) {
    $dzieci = @($wszystkie | Where-Object { "$($_.Rodzic)" -eq "$($g.Id)" })
    $rodzaje = @($dzieci | ForEach-Object { "$($_.Trwalosc)" } | Select-Object -Unique)
    $tr = "$($g.Trwalosc)"
    if ($rodzaje.Count -gt 1) { $tr = "mieszana" }
    switch ($tr) {
      "stala"      { $st++ }
      "tymczasowa" { $tm++ }
      "mieszana" {
        $tymcz = @($dzieci | Where-Object { $_.Trwalosc -eq "tymczasowa" } | ForEach-Object { "$($_.Nazwa)" })
        if ($tymcz.Count -gt 0) { $mieszane += "$($g.Nazwa) - tymczasowe w niej tylko: $($tymcz -join ', ')" }
        else { $mieszane += "$($g.Nazwa)" }
      }
      default { $nz++ }
    }
  }
  $trw = @()
  $trw += "$st $(Odmiana $st 'stała' 'stałe' 'stałych')"
  $trw += "$tm $(Odmiana $tm 'tymczasowa' 'tymczasowe' 'tymczasowych')"
  if ($mieszane.Count -gt 0) { $trw += "$($mieszane.Count) $(Odmiana $mieszane.Count 'mieszana' 'mieszane' 'mieszanych')" }
  if ($nz -gt 0) { $trw += "$nz o nieznanej trwałości" }
  $z += " Z tych $ile" + ": " + ($trw -join ", ")
  if ($mieszane.Count -gt 0) { $z += " (" + ($mieszane -join "; ") + ")" }
  $z += "."

  # Braki tez na tej samej podstawie: warstwa glowna liczy sie raz, gdy brakuje
  # jej samej albo ktorejkolwiek z jej podwarstw.
  $zle = 0
  foreach ($g in $glowne) {
    $rodzina = @($g) + @($wszystkie | Where-Object { "$($_.Rodzic)" -eq "$($g.Id)" })
    if (@($rodzina | Where-Object { ($_.Stan -eq "brak") -or ($_.Stan -eq "blad") }).Count -gt 0) { $zle++ }
  }
  if ($zle -gt 0) { $z += " Brak pliku albo błąd odczytu w $zle z $ile - zaznaczone na czerwono." }
  return $z
}

# Do ktorego modulu nalezy warstwa (P59d) - pusta lista = warstwa zawsze (Claude Code
# sam, CLAUDE.md, pliki projektu). Liste warstw sklada koszt-pamieci.ps1 -Warstwy
# (narzedzia\koszt\tryb-warstwy.ps1); tu tylko przypisanie po Id, a dla ladunkow hooka
# po pliku - ladunki zasad kierownika (megaruchacz-sesja.json, orchestrator-reminder.json)
# leza pod roznymi Id. Blok "MegaRuchacz:start" niesie dzis zasady Lore i Wiedzy naraz,
# wiec jest, gdy jest ktorykolwiek z nich; blok o nazwie modulu (np. "kierownik") nalezy
# do tego modulu. Nieznana warstwa jest zawsze - schowanie czegos, czego nie znamy,
# byloby cisza.
function Moduly-Warstwy($wa) {
  $id = "$($wa.Id)"
  if ($id -eq "claude-globalny-blok") { return ,@("wiedza", "lore") }
  if ($id -match '^claude-globalny-blok-(.+)$') {
    if ($NADZ_MODULY -contains $Matches[1]) { return ,@($Matches[1]) }
    return ,@()
  }
  if (@("claude-globalny-stala", "claude-globalny-biezace", "doklejka-cykl", "wiedza") -contains $id) { return ,@("wiedza") }
  if ("$($wa.Rodzic)" -eq "wiedza") { return ,@("wiedza") }
  if (@("doklejka-archiwum", "lore") -contains $id) { return ,@("lore") }
  if ((@("przypomnienie", "przypomnienie-codex", "mapa", "worklog") -contains $id) -or ($id -match '^ladunek-\d+$')) { return ,@("kierownik") }
  if (($id -match '^sesja-\d+$') -and ("$($wa.Sciezka)" -match '(megaruchacz-sesja|orchestrator-reminder)\.json$')) { return ,@("kierownik") }
  return ,@()
}

# Etykieta podsumowania rosnie razem z tekstem - uciety koniec zdania bylby
# ucieciem po cichu, a tego w tym projekcie nie wolno.
function Dopasuj-Etykiete($l) {
  if (-not $l -or $l.IsDisposed) { return }
  try {
    $szer = [math]::Max(200, $l.ClientSize.Width)
    $roz = [System.Windows.Forms.TextRenderer]::MeasureText($l.Text, $l.Font,
             (New-Object System.Drawing.Size($szer, 0)), [System.Windows.Forms.TextFormatFlags]::WordBreak)
    $l.Height = $roz.Height + 10
  } catch { Zanotuj-Wywrotke "dopasowanie wysokosci podsumowania warstw" $_ }
}

# Samo rysowanie - liste liczy krok w tle "warstwy" (P21).
function Napelnij-Warstwy {
  if (-not $script:ListaWarstw -or $script:ListaWarstw.IsDisposed) { return }
  if ($null -eq $script:DaneWarstw) { return }
  $script:DoOdmalowania["warstwy"] = $false
  $dw = $script:DaneWarstw
  $lv = $script:ListaWarstw
  $lv.BeginUpdate()
  try {
    $lv.Items.Clear()
    $lv.Groups.Clear()
    if ($dw.Powod) {
      $script:LWarstwy.ForeColor = $script:KolPilne
      $script:LWarstwy.Text = "NIE UDAŁO SIĘ ZEBRAĆ LISTY WARSTW: $($dw.Powod)"
      $script:PodgladWarstwy.Text = ("Lista warstw jest pusta, bo jej zebranie się nie udało - to nie znaczy, że warstw nie ma." + "`r`n`r`n" +
        "Powód: $($dw.Powod)" + "`r`n`r`n" + "Spróbuj ręcznie:" + "`r`n" +
        "powershell -ExecutionPolicy Bypass -File $(Join-Path $script:NadzZrodlo 'narzedzia\koszt-pamieci.ps1') -Warstwy")
      return
    }
    $grupy = @{}
    foreach ($k in $KOLEJNOSC_KIEDY) {
      $g = New-Object System.Windows.Forms.ListViewGroup -ArgumentList @((Kiedy-Po-Ludzku $k), [System.Windows.Forms.HorizontalAlignment]::Left)
      [void]$lv.Groups.Add($g)
      $grupy[$k] = $g
    }
    # P59d: na liscie tylko warstwy zainstalowanych modulow (Moduly-Warstwy). Schowane
    # nie znikaja po cichu: zdanie nad lista mowi, ile ich jest i z jakich modulow, a te,
    # ktore mimo to trafiaja do kazdej rozmowy (np. sekcja "Co wiem" zostala w CLAUDE.md po
    # odinstalowaniu Wiedzy), wymienia z nazwy na zolto - kosztuja tokeny.
    $pokazane = @(); $schowane = @(); $wczytywane = @(); $modulySchowanych = @()
    foreach ($wa in @($dw.Warstwy)) {
      $mod = Moduly-Warstwy $wa   # bez @() - zwraca ",$lista" (zasada w stan-nadzorcy.ps1)
      if (($mod.Count -eq 0) -or (@($mod | Where-Object { Modul-Jest $script:Instalacja $_ }).Count -gt 0)) { $pokazane += $wa; continue }
      $schowane += $wa
      foreach ($m in $mod) { if ($modulySchowanych -notcontains $NAZWY_MODULOW[$m]) { $modulySchowanych += $NAZWY_MODULOW[$m] } }
      if (("$($wa.Stan)" -eq "jest") -and (@("start", "wiadomosc") -contains "$($wa.Kiedy)")) { $wczytywane += $wa }
    }
    foreach ($wa in $pokazane) {
      $klucz = "$($wa.Kiedy)"
      if (-not $grupy.ContainsKey($klucz)) {
        # nieznany rodzaj "kiedy" nie znika - dostaje wlasna grupe
        $g = New-Object System.Windows.Forms.ListViewGroup -ArgumentList @((Kiedy-Po-Ludzku $klucz), [System.Windows.Forms.HorizontalAlignment]::Left)
        [void]$lv.Groups.Add($g)
        $grupy[$klucz] = $g
      }
      $nazwa = Po-Polsku "$($wa.Nazwa)"
      if ($wa.Rodzic) { $nazwa = "      › " + $nazwa }
      $it = New-Object System.Windows.Forms.ListViewItem -ArgumentList @(,[string]$nazwa)
      [void]$it.SubItems.Add([string](Trwalosc-Po-Ludzku $wa.Trwalosc))
      [void]$it.SubItems.Add([string](Rozmiar-Warstwy $wa))
      $it.Group = $grupy[$klucz]
      $it.Tag = $wa
      $it.ToolTipText = "$($wa.Nazwa) - $($wa.Sciezka)"
      if (($wa.Stan -eq "brak") -or ($wa.Stan -eq "blad")) { $it.ForeColor = $script:KolPilne }
      elseif (($wa.Kiedy -eq "nieuzywane") -or ($wa.Stan -eq "nieaktywna") -or ($wa.Stan -eq "pusty")) { $it.ForeColor = $script:KolSzary }
      [void]$lv.Items.Add($it)
    }
    $zd = Zdanie-Warstw ([pscustomobject]@{ Warstwy = $pokazane })
    $script:LWarstwy.ForeColor = $script:KolTekst
    if ($schowane.Count -gt 0) {
      $zd += " Bez warstw modułów spoza instalacji ($($modulySchowanych -join ', ')): $($schowane.Count)."
    }
    if ($wczytywane.Count -gt 0) {
      $zd += " UWAGA: $($wczytywane.Count) $(Odmiana $wczytywane.Count 'warstwa modułu spoza instalacji nadal trafia' 'warstwy modułów spoza instalacji nadal trafiają' 'warstw modułów spoza instalacji nadal trafia') do rozmów: " +
        (@($wczytywane | ForEach-Object { Po-Polsku "$($_.Nazwa)" }) -join ", ") + " - kosztują tokeny, choć modułu nie ma."
      $script:LWarstwy.ForeColor = $script:KolUwaga
    }
    if (@($dw.Uwagi).Count -gt 0) {
      $zd += " UWAGA: " + (@($dw.Uwagi) -join "; ")
      $script:LWarstwy.ForeColor = $script:KolUwaga
    }
    $script:LWarstwy.Text = Po-Polsku $zd
    Pokaz-Info-Warstwy $null
    $pocz = @("Kliknij warstwę po lewej, żeby zobaczyć, co w niej jest.", "",
              "Lista zebrana: $($dw.Wygenerowano). Projekt: $($dw.Projekt).")
    if (@($dw.Uwagi).Count -gt 0) { $pocz += @("", "UWAGI:") + @($dw.Uwagi | ForEach-Object { "  - $_" }) }
    $script:PodgladWarstwy.Lines = [string[]]$pocz
  } finally {
    $lv.EndUpdate()
    Dopasuj-Etykiete $script:LWarstwy
  }
}

# Podglad tylko do odczytu. Nad trescia - dwie kolumny z tym, co o warstwie
# wiadomo (kiedy sie wczytuje, stan, rozmiar, kto pisze, sciezka); pod nimi sama
# tresc. Podwarstwa i ladunek hooka pokazuja tekst z koszt-pamieci.ps1 (kawalek
# pliku albo to, co hook naprawde wysyla), zwykly plik czytamy tutaj, katalog to
# lista plikow, bazy nie wczytujemy wcale.
function Pokaz-Info-Warstwy($wa) {
  $info = $script:PodgladInfo
  if (-not $info -or $info.IsDisposed) { return }
  $info.SuspendLayout()
  try {
    Wyczysc-Panel $info
    if (-not $wa) { return }
    $szer = [math]::Max(300, $info.Parent.ClientSize.Width - $info.Parent.Padding.Horizontal - 12)
    $t = Etykieta-Zawijana (Po-Polsku "$($wa.Nazwa)") $script:CzSrednia $script:KolTekst $szer
    $t.UseMnemonic = $false
    $t.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $info.Controls.Add($t)
    $st = "$($wa.Stan)"
    $kolSt = $script:KolDobrze
    if (($st -eq "brak") -or ($st -eq "blad")) { $kolSt = $script:KolPilne }
    elseif (($st -eq "nieaktywna") -or ($st -eq "pusty")) { $kolSt = $script:KolSzary }
    $e = 130
    $info.Controls.Add((Wiersz-Dwukolumnowy "Wczytuje się" (Kiedy-Po-Ludzku "$($wa.Kiedy)") $script:KolTekst $szer $e))
    $info.Controls.Add((Wiersz-Dwukolumnowy "Stan" (Stan-Po-Ludzku $st) $kolSt $szer $e))
    $info.Controls.Add((Wiersz-Dwukolumnowy "Rozmiar" (Rozmiar-Opisowy $wa) $script:KolTekst $szer $e))
    $info.Controls.Add((Wiersz-Dwukolumnowy "Trwałość" (Trwalosc-Po-Ludzku "$($wa.Trwalosc)") $script:KolTekst $szer $e))
    if ($wa.Zmieniony) { $info.Controls.Add((Wiersz-Dwukolumnowy "Zmieniony" "$($wa.Zmieniony)" $script:KolTekst $szer $e)) }
    $info.Controls.Add((Wiersz-Dwukolumnowy "Kto pisze" (Po-Polsku "$($wa.KtoPisze)") $script:KolTekst $szer $e))
    if ($wa.Opis) { $info.Controls.Add((Wiersz-Dwukolumnowy "Co to jest" (Po-Polsku "$($wa.Opis)") $script:KolTekst $szer $e)) }
    $info.Controls.Add((Wiersz-Dwukolumnowy "Ścieżka" "$($wa.Sciezka)" $script:KolSzary $szer $e))
    $kreska = New-Object System.Windows.Forms.Panel
    $kreska.Size = New-Object System.Drawing.Size($szer, 1)
    $kreska.BackColor = $script:KolRamki
    $kreska.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 8)
    $info.Controls.Add($kreska)
  } finally { $info.ResumeLayout($true) }
}

function Pokaz-Podglad($wa) {
  if (-not $script:PodgladWarstwy -or $script:PodgladWarstwy.IsDisposed -or -not $wa) { return }
  Pokaz-Info-Warstwy $wa
  $l = New-Object System.Collections.Generic.List[string]
  $st = "$($wa.Stan)"
  if (($st -eq "brak") -or ($st -eq "blad")) {
    $l.Add("NIE MA CZEGO POKAZAĆ: $($wa.Brak)")
  } elseif ($st -eq "nieaktywna") {
    $l.Add("Teraz nic się nie dokleja: $($wa.Brak)")
  } elseif ($st -eq "pusty") {
    $l.Add("Warstwa jest pusta: $($wa.Brak)")
  } elseif ($wa.Rodzaj -eq "baza") {
    $l.Add("Bazy nie wczytuję do podglądu - to $(Rozmiar-Ludzki $wa.Bajty) danych. Model sięga do niej narzędziami lore_search i lore_context.")
  } elseif ($wa.Rodzaj -eq "katalog") {
    $l.Add("Pliki w katalogu ($(@($wa.Pliki).Count)):")
    $l.Add("")
    foreach ($pl in @($wa.Pliki)) { $l.Add(("{0,-30} {1,10}  {2}" -f "$($pl.Nazwa)", (Rozmiar-Ludzki $pl.Bajty), "$($pl.Zmieniony)")) }
    $l.Add("")
    $l.Add("Pliki .md z tego katalogu są na liście po lewej - kliknij, żeby zobaczyć treść.")
  } elseif ("$($wa.Tresc)" -ne "") {
    if ($wa.Rodzaj -eq "ladunek") {
      $l.Add("Poniżej tekst, który hook naprawdę wysyła do modelu (pole additionalContext), a nie surowy JSON:")
      $l.Add("")
    }
    $l.Add(("$($wa.Tresc)" -replace '\r?\n', "`r`n"))
  } else {
    if ($wa.Rodzaj -eq "doklejka") {
      $l.Add("Samej doklejki nikt nie zapisuje - poniżej plik stanu, z którego korzysta:")
      $l.Add("")
    } elseif ($wa.Rodzaj -eq "ladunek") {
      $l.Add("Nie udało się wyciągnąć tekstu, który hook wysyła - poniżej surowy plik:")
      $l.Add("")
    }
    try {
      $l.Add(([System.IO.File]::ReadAllText("$($wa.Sciezka)", [System.Text.Encoding]::UTF8) -replace '\r?\n', "`r`n"))
    } catch {
      Zanotuj-Wywrotke "podglad warstwy $($wa.Sciezka)" $_
      $l.Add("NIE UDAŁO SIĘ ODCZYTAĆ PLIKU: $($_.Exception.Message)")
    }
  }
  $script:PodgladWarstwy.Text = ($l -join "`r`n")
  $script:PodgladWarstwy.SelectionStart = 0
  $script:PodgladWarstwy.ScrollToCaret()
}

# Znacznik dla nadzorca.ps1: ten plik wczytal sie do konca.
$script:ModulyOkna["warstwy"] = $true
