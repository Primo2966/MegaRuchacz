# Wspolne dla instaluj-globalnie.ps1, straznik-zasad.ps1, wpisz-zasady.ps1, modul-wiedza.ps1
# i instalatora (instalator\dane.ps1) - dolaczane kropka: JEDNA lista narzedzi AI, do ktorych
# MegaRuchacz wpisuje zasady, i to, jak sie je wykrywa, zaklada i pilnuje.
#
#   ~/.claude/CLAUDE.md           Claude Code - wariant zasad kierownika "claude"
#   ~/.codex/AGENTS.md            Codex       - wariant opencode/Codex, Codex czyta do 32 KiB
#   ~/.config/opencode/AGENTS.md  OpenCode    - wariant opencode/Codex
#
# Kazdy plik jest SAMODZIELNY: bloki zasad (lore, wiedza, kierownik) i wlasna sekcja "## Co wiem",
# do ktorej cykl wiedzy (lore\lore\verify.py INSTRUCTION_PATHS) dopisuje fakty - ta sama wiedza
# w kazdym pliku (pusta sekcja zasiewana z najbogatszej, rozjazd meldowany: Zrodlo-Co-Wiem). Do 0.27 plik
# opencode byl kopia CLAUDE.md odswiezana przez straznika (pierwsza linia
# <!-- MegaRuchacz:kopia-dla-opencode ...); taka kopie zamieniamy na samodzielny plik, zdejmujac
# sama linie naglowka - tresc (z "Co wiem") zostaje (Tekst-Startowy).
#
# Orka (orca) uruchamia Codeksa z wlasnym CODEX_HOME
# (%APPDATA%\orca\codex-runtime-home\home). Przy KAZDYM starcie Codeksa w Orce
# sama przenosi tam z ~/.codex: AGENTS.md, skills, hooks (katalog), plugins,
# plugin-state, profile-v2, themes, prompts - dowiazaniem albo kopia, ktora
# odswieza, gdy sie rozni (kod Orki 1.4.210: out/main/chunks/codex-home-paths-*.js,
# funkcja wolana z prepareForCodexLaunch). Dlatego do katalogu Orki NIC nie
# piszemy: wystarczy ~/.codex/AGENTS.md. Wlasny plik w katalogu Orki
# zablokowalby to kopiowanie na zawsze (Orka nie nadpisuje pliku, ktorego sama
# nie zalozyla). hooks.json Orka NIE przenosi - hooki rejestru z ~/.codex pod
# Orka nie chodza.

$KIEROWNIK_POCZATEK = "<!-- MegaRuchacz:kierownik:start -->"
$KIEROWNIK_KONIEC   = "<!-- MegaRuchacz:kierownik:koniec -->"
$KOPIA_OPENCODE_ZNACZNIK = "<!-- MegaRuchacz:kopia-dla-opencode"
$ZNACZNIK_MEGARUCHACZA = "<!-- MegaRuchacz:"   # = GUARD_PREFIX w lore\lore\verify.py

# ------------------------------------------------------------ lista narzedzi AI
# Czwarte CLI = jeden wpis tutaj; reszta (wpisz-zasady, straznik, instalator globalny, modul
# wiedza, okno instalatora) bierze wszystko z tej listy.
#   Id, Nazwa
#   Plik       plik instrukcji, ktory narzedzie wczytuje samo (wzgledem katalogu domowego)
#   Polecenie  polecenie w PATH - jeden ze sladow obecnosci
#   Slady      pliki i katalogi w domu, ktore zaklada SAMO narzedzie. Dla Claude Code to
#              .claude.json i historia, a nie katalog .claude - ten zaklada tez MegaRuchacz
#              (Lore, wiedza, rejestr instalacji), wiec nic nie dowodzi.
#   Wariant    wariant bloku zasad kierownika: claude (szablony-global\claude) albo opencode
#              (szablony-opencode - Codex i OpenCode: praca bez tla i bez worktree)
#   Limit      ile bajtow pliku narzedzie wczytuje; 0 = limitu nie znamy. Codex przycina
#              AGENTS.md na 32 KiB (project_doc_max_bytes), a nasze bloki stoja na koncu pliku.
#              OpenCode: w docs (opencode.ai/docs/rules) limitu brak - niepotwierdzone.
#   Zapas      Id narzedzia, ktorego plik to narzedzie czyta, gdy wlasnego nie ma. OpenCode czyta
#              ~/.claude/CLAUDE.md, dopoki nie ma ~/.config/opencode/AGENTS.md, a gdy ten jest -
#              TYLKO jego (docs: rules). Wlasny plik zakladamy wiec z trescia tamtego (bez bloku
#              kierownika, ktory dostaje wlasny wariant) - nic, co opencode dotad widzial, nie ginie,
#              i nic nie wchodzi dwa razy.
function Narzedzia-AI {
  return @(
    [pscustomobject]@{ Id = "claude";   Nazwa = "Claude Code"; Plik = ".claude\CLAUDE.md";          Polecenie = "claude";   Slady = @(".claude.json", ".claude\history.jsonl");                       Wariant = "claude";   Limit = 0;     Zapas = $null },
    [pscustomobject]@{ Id = "codex";    Nazwa = "Codex";       Plik = ".codex\AGENTS.md";           Polecenie = "codex";    Slady = @(".codex", "AppData\Roaming\orca\codex-runtime-home\home"); Wariant = "opencode"; Limit = 32768; Zapas = $null },
    [pscustomobject]@{ Id = "opencode"; Nazwa = "OpenCode";    Plik = ".config\opencode\AGENTS.md"; Polecenie = "opencode"; Slady = @(".config\opencode");                                       Wariant = "opencode"; Limit = 0;     Zapas = "claude" }
  )
}

function Narzedzie-AI([string]$id) {
  return (Narzedzia-AI | Where-Object { $_.Id -eq $id } | Select-Object -First 1)
}

function Czytaj-Utf8($sciezka) {
  return [System.IO.File]::ReadAllText($sciezka, (New-Object System.Text.UTF8Encoding($false, $true)))
}

# Czy w pliku stoi juz cos naszego (znacznik bloku). Taki plik pilnujemy dalej, nawet gdy samego
# narzedzia juz nie widac - inaczej zostalyby w nim nieaktualne bloki, ktorych nikt nie zdejmie.
function Ma-Nasze-Bloki([string]$sciezka) {
  if (-not (Test-Path -LiteralPath $sciezka -PathType Leaf)) { return $false }
  try { return ([System.IO.File]::ReadAllText($sciezka)).Contains($ZNACZNIK_MEGARUCHACZA) } catch { return $false }
}

# Kazde narzedzie z listy z polami Sciezka (pelna sciezka pliku), Jest i Dowod (czym sie zdradzilo,
# do meldunkow). Obecne = polecenie w PATH albo slad w domu albo nasze bloki w jego pliku.
function Wykryj-Narzedzia-AI([string]$dom) {
  $wynik = @()
  foreach ($n in (Narzedzia-AI)) {
    $dowody = @()
    $pol = Get-Command $n.Polecenie -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pol) { $dowody += "polecenie $($n.Polecenie)" }
    foreach ($s in $n.Slady) { if (Test-Path -LiteralPath (Join-Path $dom $s)) { $dowody += $s } }
    $sciezka = Join-Path $dom $n.Plik
    if (Ma-Nasze-Bloki $sciezka) { $dowody += "zasady MegaRuchacza w $($n.Plik)" }
    $w = [pscustomobject]@{ Id = $n.Id; Nazwa = $n.Nazwa; Plik = $n.Plik; Sciezka = $sciezka; Wariant = $n.Wariant
                            Limit = $n.Limit; Zapas = $n.Zapas; Jest = ($dowody.Count -gt 0); Dowod = ($dowody -join ", ") }
    $wynik += $w
  }
  return ,$wynik
}

# Same obecne - pliki instrukcji, do ktorych wpisujemy zasady. Pusta lista = zadnego narzedzia AI.
# Wynik rozwiniety (bez przecinka): wolajacy bierze go w @(), inaczej jeden wpis wraca bez tablicy.
function Cele-Narzedzi([string]$dom) {
  return @((Wykryj-Narzedzia-AI $dom) | Where-Object { $_.Jest })
}

# ------------------------------------------------------------ poczatek pliku narzedzia
# Stara kopia CLAUDE.md dla opencode (do 0.27) - po pierwszej linii.
function Jest-Kopia-Opencode($sciezka) {
  if (-not (Test-Path $sciezka)) { return $false }
  try { return (Czytaj-Utf8 $sciezka).StartsWith($KOPIA_OPENCODE_ZNACZNIK) } catch { return $false }
}

# Tekst bez linii naglowka starej kopii (i pustej linii pod nia); reszta co do bajtu.
function Bez-Naglowka-Kopii([string]$tekst) {
  if (-not $tekst -or -not $tekst.StartsWith($KOPIA_OPENCODE_ZNACZNIK)) { return $tekst }
  $m = [regex]::Match($tekst, "^[^\n]*\n(\r?\n)?")
  return $tekst.Substring($m.Length)
}

# Tekst, od ktorego zaczyna sie skladanie pliku narzedzia $n (wpis z Wykryj-Narzedzia-AI):
#   - plik jest: jego tresc (stara kopia dla opencode - bez linii naglowka);
#   - pliku nie ma, a narzedzie czyta wtedy plik zapasowy (Zapas): tresc tamtego bez bloku kierownika;
#   - inaczej: pusty.
# .Istnieje - czy plik jest na dysku; .Opis - skad poczatek (do meldunku) albo $null.
# Plik nie po UTF-8, bajty 0x00 w pliku zapasowym albo dubel bloku kierownika = wyjatek.
function Tekst-Startowy($n, [string]$dom) {
  $w = [pscustomobject]@{ Tekst = ""; Istnieje = (Test-Path -LiteralPath $n.Sciezka -PathType Leaf); Opis = $null }
  if ($w.Istnieje) {
    $t = Czytaj-Utf8 $n.Sciezka
    $w.Tekst = Bez-Naglowka-Kopii $t
    if ($w.Tekst -cne $t) { $w.Opis = "stara kopia ~/.claude/CLAUDE.md - od teraz samodzielny plik (naglowek kopii zdjety, tresc zostaje)" }
    return $w
  }
  if (-not $n.Zapas) { return $w }
  $zap = Narzedzie-AI $n.Zapas
  $sz = Join-Path $dom $zap.Plik
  if (-not (Test-Path -LiteralPath $sz -PathType Leaf)) { return $w }
  if ([Array]::IndexOf([System.IO.File]::ReadAllBytes($sz), [byte]0) -ge 0) { throw "$($zap.Plik) ma bajty 0x00 - nie zakladam z niego $($n.Plik)" }
  $t = Bez-Bloku-Kierownika (Czytaj-Utf8 $sz)
  if ($t.Trim().Length -gt 0) {
    $w.Tekst = $t
    $w.Opis = "zalozony z trescia $($zap.Plik) (dotad $($n.Nazwa) czytal tamten plik) - bez jego bloku kierownika"
  }
  return $w
}

# ------------------------------------------------------------ szkielet "## Co wiem"
# Podsekcje - DOKLADNIE te same naglowki co w lore\lore\verify.py (STABLE_SUBSECTIONS,
# CURRENT_SUBSECTION, REFERENCE_SUBSECTION). Polskie litery skladane ze znakow - plik zostaje ASCII.
$NAGLOWEK_CO_WIEM = "## Co wiem"
function Podsekcje-Co-Wiem {
  $zz = [char]0x017C; $aa = [char]0x0105
  return @("### O u${zz}ytkowniku", "### O firmie", "### Nad czym pracuje", "### Jak pracuje", "### Bie${zz}${aa}ce", "### Dane referencyjne")
}

function Ma-Co-Wiem([string]$tekst) {
  foreach ($l in ("$tekst" -split "`r?`n")) { if ($l.Trim().StartsWith($NAGLOWEK_CO_WIEM)) { return $true } }
  return $false
}

# Tekst po dolozeniu pustego szkieletu (albo $null, gdy sekcja juz jest - istniejacej nie ruszamy):
# nad pierwszym znacznikiem MegaRuchacza (verify.py konczy na nim sekcje, wiec fakty nie trafia do
# srodka zadnego bloku), a bez znacznikow - na koncu pliku.
function Z-Szkieletem-Co-Wiem([string]$stary) {
  if (Ma-Co-Wiem $stary) { return $null }
  if ($null -eq $stary) { $stary = "" }
  $nl = if ($stary.Contains("`r`n")) { "`r`n" } elseif ($stary.Contains("`n")) { "`n" } else { "`r`n" }
  $szkielet = (@($NAGLOWEK_CO_WIEM, "") + @(Podsekcje-Co-Wiem | ForEach-Object { $_, "" })) -join $nl
  $linie = @($stary -split "`r?`n")
  $iPierwszy = -1
  for ($i = 0; $i -lt $linie.Count; $i++) { if ($linie[$i].Trim().StartsWith($ZNACZNIK_MEGARUCHACZA)) { $iPierwszy = $i; break } }
  if ($iPierwszy -ge 0) {
    $przed = (@($linie | Select-Object -First $iPierwszy) -join $nl).TrimEnd()
    $po = @($linie | Select-Object -Skip $iPierwszy) -join $nl
    $sklejka = if ($przed) { $przed + $nl + $nl } else { "" }
    return ($sklejka + $szkielet + $po)
  }
  $cialo = $stary.TrimEnd()
  if (-not $cialo) { $cialo = "# Ustalenia globalne" }
  return ($cialo + $nl + $nl + $szkielet.TrimEnd() + $nl)
}

# ------------------------------------------------------------ ta sama wiedza w kazdym CLI
# "Co wiem" ma byc ta sama we wszystkich narzedziach AI na maszynie. Biurowa 06.10: AGENTS.md
# Codeksa dostal pusty szkielet obok ~8000 znakow wiedzy w CLAUDE.md - Codex nie wiedzial nic.
# Regula:
#   - sekcja pusta (same naglowki, zero wpisow) - zasiewamy ja trescia sekcji z NAJBOGATSZEGO pliku
#     z listy (Zrodlo-Co-Wiem, Zasiej-Co-Wiem); zasiew ponad limit narzedzia - odmowa (sam zasiew,
#     reszta pliku idzie), powod w pierwszej linii;
#   - sekcji z wpisami nie nadpisujemy nigdy. Rozne sekcje w roznych plikach (np. reczny dopis tylko
#     do CLAUDE.md) - meldunek (Rozjazd-Co-Wiem), bez scalania: co jest czyje, rozstrzyga czlowiek.
# Granice sekcji jak lore\lore\verify.py section_bounds: od "## Co wiem" do nastepnego "## " albo
# znacznika MegaRuchacza.

# @(indeks naglowka, indeks pierwszej linii za sekcja) albo $null, gdy sekcji nie ma.
function Granice-Co-Wiem([string[]]$linie) {
  $od = -1
  for ($i = 0; $i -lt $linie.Count; $i++) { if ($linie[$i].Trim().StartsWith($NAGLOWEK_CO_WIEM)) { $od = $i; break } }
  if ($od -lt 0) { return $null }
  for ($j = $od + 1; $j -lt $linie.Count; $j++) {
    $t = $linie[$j].Trim()
    if ($t.StartsWith("## ") -or $t.StartsWith($ZNACZNIK_MEGARUCHACZA)) { return @($od, $j) }
  }
  return @($od, $linie.Count)
}

# Linie tresci sekcji (bez linii "## Co wiem"); $null, gdy sekcji nie ma. Wynik to JEDNA tablica
# (przecinek): bierz go przypisaniem, nie w @() - inaczej tablica w tablicy (to samo w Wpisy-Co-Wiem).
function Cialo-Co-Wiem([string]$tekst) {
  $linie = @("$tekst" -split "`r?`n")
  $g = Granice-Co-Wiem $linie
  if ($null -eq $g) { return $null }
  if ($g[1] - $g[0] -le 1) { return ,@() }
  return ,@($linie[($g[0] + 1)..($g[1] - 1)])
}

# Wpisy sekcji: niepuste linie, ktore nie sa naglowkami podsekcji.
function Wpisy-Co-Wiem([string]$tekst) {
  $c = Cialo-Co-Wiem $tekst
  if ($null -eq $c) { return ,@() }
  return ,@($c | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith("#") })
}

# Sekcja jest, a nie ma w niej ani jednego wpisu (same naglowki podsekcji i puste linie).
function Pusta-Co-Wiem([string]$tekst) {
  if (-not (Ma-Co-Wiem $tekst)) { return $false }
  $wp = Wpisy-Co-Wiem $tekst
  return ($wp.Count -eq 0)
}

# Sekcja "Co wiem" kazdego pliku z listy, ktory lezy na dysku: Id, Nazwa, Plik (~/...), Sciezka,
# Cialo ($null = sekcji nie ma), Wpisy, Znakow (suma dlugosci wpisow), Blad (plik nieczytelny albo
# z bajtami 0x00 - nie jest ani zrodlem, ani wzorem; Rozjazd-Co-Wiem go melduje).
function Sekcje-Co-Wiem([string]$dom) {
  $wynik = @()
  foreach ($n in (Narzedzia-AI)) {
    $p = Join-Path $dom $n.Plik
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
    $w = [pscustomobject]@{ Id = $n.Id; Nazwa = $n.Nazwa; Plik = "~/" + ($n.Plik -replace '\\', '/'); Sciezka = $p
                            Cialo = $null; Wpisy = @(); Znakow = 0; Blad = $null }
    try {
      $t = Czytaj-Utf8 $p
      if ($t.IndexOf([char]0) -ge 0) { throw "ma bajty 0x00 (uszkodzony zapis)" }
      $c = Cialo-Co-Wiem $t
      if ($null -ne $c) {
        $w.Cialo = @($c)
        $w.Wpisy = Wpisy-Co-Wiem $t
        foreach ($x in $w.Wpisy) { $w.Znakow += $x.Length }
      }
    } catch { $w.Blad = $_.Exception.Message }
    $wynik += $w
  }
  return ,$wynik
}

# Najbogatsza sekcja z wpisami (najwiecej znakow we wpisach; remis - kolejnosc listy) - wpis
# z Sekcje-Co-Wiem albo $null, gdy nigdzie nie ma sekcji z wpisami.
function Zrodlo-Co-Wiem([string]$dom) {
  $naj = $null
  foreach ($s in (Sekcje-Co-Wiem $dom)) {
    if ($s.Blad -or $s.Wpisy.Count -eq 0) { continue }
    if (($null -eq $naj) -or ($s.Znakow -gt $naj.Znakow)) { $naj = $s }
  }
  return $naj
}

# Tekst z pusta sekcja "Co wiem" zastapiona trescia sekcji $zrodlo (wpis z Zrodlo-Co-Wiem); $null,
# gdy nie ma czego siac (sekcji nie ma, ma wpisy, brak zrodla). Linia "## Co wiem" i reszta pliku
# zostaja co do bajtu; konce linii jak w pliku docelowym.
function Z-Zasiewem-Co-Wiem([string]$stary, $zrodlo) {
  if (($null -eq $zrodlo) -or ($null -eq $zrodlo.Cialo) -or -not (Pusta-Co-Wiem $stary)) { return $null }
  $nl = if ($stary.Contains("`r`n")) { "`r`n" } elseif ($stary.Contains("`n")) { "`n" } else { "`r`n" }
  $linie = @($stary -split "`r?`n")
  $g = Granice-Co-Wiem $linie
  $cialo = @($zrodlo.Cialo)
  $a = 0; $b = $cialo.Count - 1
  while (($a -le $b) -and -not $cialo[$a].Trim()) { $a++ }
  while (($b -ge $a) -and -not $cialo[$b].Trim()) { $b-- }
  if ($a -gt $b) { return $null }
  $nowe = @($linie | Select-Object -First ($g[0] + 1)) + @("") + @($cialo[$a..$b]) + @("")
  $po = @($linie | Select-Object -Skip $g[1])
  # sekcja na koncu pliku konczy go jednym koncem linii; inaczej pusta linia przed tym, co za nia
  if ($po.Count -gt 0) { $nowe += $po }
  return ($nowe -join $nl)
}

# Zasiew na gotowym tekscie pliku narzedzia $n, z sufitem ($stary = plik na dysku, do Ponad-Limit):
#   .Tekst   tekst z zasiewem albo $tekst bez zmian
#   .Zasiew  opis zasiewu do meldunku albo $null
#   .Odmowa  powod, dla ktorego zasiewu NIE ma - przekroczylby limit narzedzia - albo $null.
#            Tylko sam zasiew odpada: reszta pliku (bloki zasad) miesci sie i idzie.
function Zasiej-Co-Wiem($n, [string]$stary, [string]$tekst, $zrodlo) {
  $w = [pscustomobject]@{ Tekst = $tekst; Zasiew = $null; Odmowa = $null }
  if (($null -eq $zrodlo) -or -not $tekst) { return $w }
  $z = Z-Zasiewem-Co-Wiem $tekst $zrodlo
  if ($null -eq $z) { return $w }
  if (-not (Ponad-Limit $n $stary $z)) {
    $w.Tekst = $z
    $w.Zasiew = "pusta sekcja 'Co wiem' zasiana trescia z $($zrodlo.Plik) ($($zrodlo.Wpisy.Count) wpisow)"
  } elseif (-not (Ponad-Limit $n $stary $tekst)) {
    # gdy i bez zasiewu jest za duzo, caly zapis odmawia Ponad-Limit - drugi powod bylby szumem
    $ile = (New-Object System.Text.UTF8Encoding($false)).GetByteCount($z)
    $w.Odmowa = ("zasiew sekcji 'Co wiem' trescia z $($zrodlo.Plik) dalby $($n.Plik) $ile B, a $($n.Nazwa) czyta najwyzej " +
                 "$($n.Limit) B - NIE zasialem, sekcja zostaje pusta (reszta pliku zapisana). Skroc 'Co wiem' w " +
                 "$($zrodlo.Plik) (np. zestawienia do wiedza\) i uruchom ponownie.")
  }
  return $w
}

# Meldunek, gdy sekcje z wpisami w roznych plikach sie roznia, albo $null (jedna wiedza wszedzie).
# Linie porownujemy jako zbiory (wpisy i naglowki podsekcji; kolejnosc i puste linie sie nie licza)
# z najbogatsza sekcja. Pustych i brakujacych sekcji nie porownujemy - te zaklada i zasiewa
# wpisz-zasady.ps1. Plik nieczytelny tez jest w meldunku: cisza znaczylaby "zgodne".
function Rozjazd-Co-Wiem([string]$dom) {
  $sekcje = Sekcje-Co-Wiem $dom
  $czesci = @($sekcje | Where-Object { $_.Blad } | ForEach-Object { "$($_.Plik) nie porownalem ($($_.Blad))" })
  $pelne = @($sekcje | Where-Object { (-not $_.Blad) -and $_.Wpisy.Count -gt 0 })
  if ($pelne.Count -ge 2) {
    $wzor = $pelne[0]
    foreach ($s in $pelne) { if ($s.Znakow -gt $wzor.Znakow) { $wzor = $s } }
    $lw = @($wzor.Cialo | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($s in $pelne) {
      if ($s.Sciezka -eq $wzor.Sciezka) { continue }
      $ls = @($s.Cialo | ForEach-Object { $_.Trim() } | Where-Object { $_ })
      $brak = @($lw | Where-Object { $ls -cnotcontains $_ })
      $nadmiar = @($ls | Where-Object { $lw -cnotcontains $_ })
      if (($brak.Count + $nadmiar.Count) -eq 0) { continue }
      $o = @()
      if ($brak.Count -gt 0) { $o += "brakuje $($brak.Count) linii z $($wzor.Plik) (np. '$(Skrot-Linii $brak[0])')" }
      if ($nadmiar.Count -gt 0) { $o += "jest $($nadmiar.Count) linii, ktorych w $($wzor.Plik) nie ma (np. '$(Skrot-Linii $nadmiar[0])')" }
      $czesci += "w $($s.Plik) " + ($o -join ", a ")
    }
  }
  if ($czesci.Count -eq 0) { return $null }
  return ("sekcja 'Co wiem' nie jest ta sama we wszystkich narzedziach AI: " + ($czesci -join "; ") +
          ". Nie scalam sam - przenies brakujace wpisy recznie, tak zeby kazde CLI wiedzialo to samo.")
}

function Skrot-Linii([string]$l) {
  if ($l.Length -le 60) { return $l }
  return $l.Substring(0, 57) + "..."
}

# ------------------------------------------------------------ sufit pliku
# Sufit nie ucina - sufit krzyczy: zapis, po ktorym plik urosnie ponad to, co narzedzie wczyta,
# jest odmawiany (koniec pliku - nasze bloki - i tak by przepadl). Zwraca powod odmowy albo $null.
# Plik, ktory ponad limitem byl juz wczesniej, wolno zmniejszac (np. zdjecie bloku).
function Ponad-Limit($n, [string]$stary, [string]$nowy) {
  if (-not $n.Limit -or $n.Limit -le 0) { return $null }
  $u = New-Object System.Text.UTF8Encoding($false)
  $ileNowy = $u.GetByteCount("$nowy")
  $ileStary = $u.GetByteCount("$stary")
  if ($ileNowy -le $n.Limit -or $ileNowy -le $ileStary) { return $null }
  return ("$($n.Plik) mialby po zapisie $ileNowy B, a $($n.Nazwa) czyta najwyzej $($n.Limit) B - koniec pliku " +
          "(zasady MegaRuchacza) by sie nie wczytal. NIE zapisalem; skroc plik (np. sekcje 'Co wiem') i uruchom ponownie.")
}

# Tekst pliku narzedzia po wpisaniu blokow zasad pamieci (Zloz-Plik-Zasad z zasady-bloki.ps1)
# i - z $szkielet - szkieletu "Co wiem", gdy go nie ma. Plik, ktorego nie ma i do ktorego nie ma
# czego wpisac, zostaje niezalozony (wynik "").
function Zloz-Plik-Narzedzia($start, $tresci, [string[]]$zdejmij = @(), [bool]$szkielet = $false) {
  if ((-not $start.Istnieje) -and (($null -eq $tresci) -or $tresci.Count -eq 0)) { return "" }
  $t = Zloz-Plik-Zasad $start.Tekst $tresci $zdejmij
  if ($szkielet) {
    $s = Z-Szkieletem-Co-Wiem $t
    if ($null -ne $s) { $t = $s }
  }
  return $t
}

# Plik narzedzia do zapisu - wspolne dla wpisz-zasady.ps1 i straznika (ten sam wynik: straznik nie
# widzi roznicy tam, gdzie wpisz-zasady nic by nie zrobil): Zloz-Plik-Narzedzia, z $szkielet zasiew
# pustej sekcji "Co wiem" z $zrodlo (Zrodlo-Co-Wiem) i sufit. $stary = plik na dysku.
#   .Nowy  tekst do zapisu     .Zasiew  opis zasiewu albo $null
#   .OdmowaZasiewu  powod odmowy samego zasiewu (Zasiej-Co-Wiem) albo $null
#   .Limit          powod odmowy CALEGO zapisu (Ponad-Limit) albo $null
function Plan-Pliku-Narzedzia($n, $start, [string]$stary, $tresci, [string[]]$zdejmij = @(), [bool]$szkielet = $false, $zrodlo = $null) {
  $t = Zloz-Plik-Narzedzia $start $tresci $zdejmij $szkielet
  $w = [pscustomobject]@{ Nowy = $t; Zasiew = $null; OdmowaZasiewu = $null; Limit = $null }
  if ($szkielet) {
    $z = Zasiej-Co-Wiem $n $stary $t $zrodlo
    $w.Nowy = $z.Tekst; $w.Zasiew = $z.Zasiew; $w.OdmowaZasiewu = $z.Odmowa
  }
  $w.Limit = Ponad-Limit $n $stary $w.Nowy
  return $w
}

# ------------------------------------------------------------ blok zasad kierownika
function Katalog-Codex-Orki($dom) {
  $p = Join-Path $dom "AppData\Roaming\orca\codex-runtime-home\home"
  if (Test-Path $p) { return $p }
  return $null
}

# Claude Code poznajemy po plikach, ktore prowadzi sam - katalog ~\.claude zaklada
# tez MegaRuchacz (Lore, wiedza). To samo rozroznienie co w instalatorze.
function Pracuje-Claude($dom) {
  return (Test-Path (Join-Path $dom ".claude\history.jsonl")) -or (Test-Path (Join-Path $dom ".claude.json"))
}

function Ile-Blokow-Kierownika([string]$tekst) {
  if (-not $tekst) { return 0 }
  return ([regex]::Matches($tekst, [regex]::Escape($KIEROWNIK_POCZATEK))).Count
}

# Tresc bloku kierownika (bez znacznikow) albo $null.
function Blok-Kierownika([string]$tekst) {
  if (-not $tekst) { return $null }
  $i = $tekst.IndexOf($KIEROWNIK_POCZATEK, [System.StringComparison]::Ordinal)
  $j = $tekst.IndexOf($KIEROWNIK_KONIEC, [System.StringComparison]::Ordinal)
  if ($i -lt 0 -or $j -lt $i) { return $null }
  return $tekst.Substring($i + $KIEROWNIK_POCZATEK.Length, $j - $i - $KIEROWNIK_POCZATEK.Length)
}

# Tekst pliku z blokiem kierownika o podanej tresci: podmiana jedynego bloku albo
# dopisanie na koncu. Konce linii bloku jak w reszcie pliku. Dubel albo samotny
# znacznik = wyjatek - tego nie naprawiamy po cichu.
function Z-Blokiem-Kierownika([string]$stary, [string]$tresc) {
  if ($null -eq $stary) { $stary = "" }
  $nl = if ($stary.Contains("`r`n")) { "`r`n" } else { "`n" }
  $t = $tresc.Trim() -replace "`r`n", "`n"
  if ($nl -eq "`r`n") { $t = $t -replace "`n", "`r`n" }
  $blok = ($KIEROWNIK_POCZATEK, $t, $KIEROWNIK_KONIEC) -join $nl
  $ile = Ile-Blokow-Kierownika $stary
  if ($ile -gt 1) { throw "jest $ile blokow kierownika (dubel)" }
  $i = $stary.IndexOf($KIEROWNIK_POCZATEK, [System.StringComparison]::Ordinal)
  $j = $stary.IndexOf($KIEROWNIK_KONIEC, [System.StringComparison]::Ordinal)
  if (($i -ge 0) -xor ($j -ge 0)) { throw "jest tylko jeden znacznik bloku kierownika" }
  if ($i -ge 0) { return $stary.Substring(0, $i) + $blok + $stary.Substring($j + $KIEROWNIK_KONIEC.Length) }
  if ($stary.Trim().Length -eq 0) { return $blok + $nl }
  return $stary.TrimEnd("`r", "`n") + $nl + $nl + $blok + $nl
}

# Tekst pliku bez bloku kierownika (modul kierownik wylaczony w rejestrze instalacji): blok
# wyciety razem ze znacznikami, bez podwojnej pustej linii po nim. Brak bloku = tekst bez zmian;
# dubel albo samotny znacznik = wyjatek - tego nie naprawiamy po cichu.
function Bez-Bloku-Kierownika([string]$stary) {
  if ($null -eq $stary) { return "" }
  $ile = Ile-Blokow-Kierownika $stary
  if ($ile -gt 1) { throw "jest $ile blokow kierownika (dubel)" }
  $i = $stary.IndexOf($KIEROWNIK_POCZATEK, [System.StringComparison]::Ordinal)
  $j = $stary.IndexOf($KIEROWNIK_KONIEC, [System.StringComparison]::Ordinal)
  if (($i -ge 0) -xor ($j -ge 0)) { throw "jest tylko jeden znacznik bloku kierownika" }
  if ($i -lt 0) { return $stary }
  if ($j -lt $i) { throw "znaczniki bloku kierownika stoja w zlej kolejnosci" }
  $nl = if ($stary.Contains("`r`n")) { "`r`n" } else { "`n" }
  $przed = $stary.Substring(0, $i).TrimEnd("`r", "`n")
  $po = $stary.Substring($j + $KIEROWNIK_KONIEC.Length).TrimStart("`r", "`n")
  if ($przed.Length -eq 0) { return $po }
  if ($po.Length -eq 0) { return $przed + $nl }
  return $przed + $nl + $nl + $po
}
