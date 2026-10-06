# Wspolne dla instaluj-globalnie.ps1, straznik-zasad.ps1, wpisz-zasady.ps1, modul-wiedza.ps1
# i instalatora (instalator\dane.ps1) - dolaczane kropka: JEDNA lista narzedzi AI, do ktorych
# MegaRuchacz wpisuje zasady, i to, jak sie je wykrywa, zaklada i pilnuje.
#
#   ~/.claude/CLAUDE.md           Claude Code - wariant zasad kierownika "claude"
#   ~/.codex/AGENTS.md            Codex       - wariant opencode/Codex, Codex czyta go w calosci
#   ~/.config/opencode/AGENTS.md  OpenCode    - wariant opencode/Codex
#
# Kazdy plik jest SAMODZIELNY: bloki zasad (lore, wiedza, kierownik) i wlasna sekcja "## Co wiem",
# do ktorej cykl wiedzy (lore\lore\verify.py INSTRUCTION_PATHS) dopisuje fakty - ta sama wiedza
# w kazdym pliku (pusta sekcja zasiewana z najbogatszej: Zrodlo-Co-Wiem; zmiany jednego pliku ida do
# pozostalych: Synchronizuj-Co-Wiem). Do 0.27 plik
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
#   Limit      ile bajtow pliku narzedzie wczytuje; 0 = bez limitu albo limitu nie znamy. Ponad limit
#              zapis jest odmawiany (Ponad-Limit), bo nasze bloki stoja na koncu pliku.
#              Codex: 0. Do 06.10 stalo tu 32768 (project_doc_max_bytes z docs) - FALSZYWE dla
#              globalnego pliku. Dowod (Codex 0.157.0, 2026-10-06): w sztucznym CODEX_HOME
#              "codex debug prompt-input ping" (tekst, ktory dostaje model, bez wywolania modelu)
#              ma ~/.codex/AGENTS.md 40 033 B i 200 KB w calosci, ze znacznikiem z konca pliku, takze
#              bez project_doc_max_bytes w config.toml. Ten limit (domyslnie 32 KiB) przycina tylko
#              AGENTS.md w katalogach projektu (40 KB w repo: uciety po linii 495 z 605, z
#              project_doc_max_bytes = 65536 caly). Nowa wersja Codeksa moze to zmienic - wtedy
#              ta sama proba i wpis tutaj.
#              OpenCode: w docs (opencode.ai/docs/rules) limitu brak - niepotwierdzone.
#   Skille     katalogi skilli, ktore narzedzie czyta (wzgledem domu), w KOLEJNOSCI WCZYTYWANIA: przy
#              dublu nazwy wygrywa katalog pozniejszy (OpenCode 1.18.33 - narzedzia\skille.ps1, naglowek).
#              Pusta lista = nie wiemy - skille.ps1 nic mu nie wgrywa i mowi o tym UWAGA.
#   Zapas      Id narzedzia, ktorego plik to narzedzie czyta, gdy wlasnego nie ma. OpenCode czyta
#              ~/.claude/CLAUDE.md, dopoki nie ma ~/.config/opencode/AGENTS.md, a gdy ten jest -
#              TYLKO jego (docs: rules). Wlasny plik zakladamy wiec z trescia tamtego (bez bloku
#              kierownika, ktory dostaje wlasny wariant) - nic, co opencode dotad widzial, nie ginie,
#              i nic nie wchodzi dwa razy.
function Narzedzia-AI {
  return @(
    [pscustomobject]@{ Id = "claude";   Nazwa = "Claude Code"; Plik = ".claude\CLAUDE.md";          Polecenie = "claude";   Slady = @(".claude.json", ".claude\history.jsonl");                       Wariant = "claude";   Limit = 0;     Zapas = $null
                       Skille = @(".claude\skills") },
    [pscustomobject]@{ Id = "codex";    Nazwa = "Codex";       Plik = ".codex\AGENTS.md";           Polecenie = "codex";    Slady = @(".codex", "AppData\Roaming\orca\codex-runtime-home\home"); Wariant = "opencode"; Limit = 0;     Zapas = $null
                       Skille = @(".agents\skills") },
    [pscustomobject]@{ Id = "opencode"; Nazwa = "OpenCode";    Plik = ".config\opencode\AGENTS.md"; Polecenie = "opencode"; Slady = @(".config\opencode");                                       Wariant = "opencode"; Limit = 0;     Zapas = "claude"
                       Skille = @(".claude\skills", ".agents\skills", ".config\opencode\skills") }
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

# Narzedzia zaznaczone w rejestrze instalacji (~\.claude\mr\instalacja.json, pole narzedzia.<id> = true -
# wybor w instalatorze; uklad pliku: narzedzia\instalacja\stan.ps1). .Narzedzia - obiekt z pola albo
# $null (brak pliku, pole null); .Blad - plik jest, a nie da sie go odczytac (wolajacy mowi o tym).
function Narzedzia-Z-Rejestru([string]$dom) {
  $w = [pscustomobject]@{ Narzedzia = $null; Blad = $null }
  $p = Join-Path $dom ".claude\mr\instalacja.json"
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $w }
  try {
    $t = (Czytaj-Utf8 $p).TrimStart([char]0xFEFF)
    if ($t.IndexOf([char]0) -ge 0) { throw "ma bajty 0x00 (uszkodzony zapis)" }
    $j = $t | ConvertFrom-Json
    if ($null -eq $j) { throw "plik jest pusty" }
    if ($j.narzedzia) { $w.Narzedzia = $j.narzedzia }
  } catch { $w.Blad = "rejestr instalacji ($p) nieczytelny: $($_.Exception.Message)" }
  return $w
}

# Kazde narzedzie z listy z polami Sciezka (pelna sciezka pliku), Jest i Dowod (czym sie zdradzilo,
# do meldunkow), Skille (katalogi skilli z listy) i RejestrBlad (rejestr instalacji nieczytelny albo
# $null - ten sam w kazdym wpisie). Obecne = zaznaczone w rejestrze instalacji albo polecenie w PATH
# albo slad w domu albo nasze bloki w jego pliku. Rejestr to zdjecie z dnia instalacji - narzedzie
# zainstalowane pozniej widac po sladach, wiec rejestr doklada, a niczego nie odbiera.
function Wykryj-Narzedzia-AI([string]$dom) {
  $wynik = @()
  $rej = Narzedzia-Z-Rejestru $dom
  foreach ($n in (Narzedzia-AI)) {
    $dowody = @()
    if ($rej.Narzedzia -and ($rej.Narzedzia.PSObject.Properties.Name -contains $n.Id) -and ($rej.Narzedzia.($n.Id) -eq $true)) { $dowody += "rejestr instalacji" }
    $pol = Get-Command $n.Polecenie -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pol) { $dowody += "polecenie $($n.Polecenie)" }
    foreach ($s in $n.Slady) { if (Test-Path -LiteralPath (Join-Path $dom $s)) { $dowody += $s } }
    $sciezka = Join-Path $dom $n.Plik
    if (Ma-Nasze-Bloki $sciezka) { $dowody += "zasady MegaRuchacza w $($n.Plik)" }
    $w = [pscustomobject]@{ Id = $n.Id; Nazwa = $n.Nazwa; Plik = $n.Plik; Sciezka = $sciezka; Wariant = $n.Wariant
                            Limit = $n.Limit; Zapas = $n.Zapas; Skille = @($n.Skille); Jest = ($dowody.Count -gt 0); Dowod = ($dowody -join ", ")
                            RejestrBlad = $rej.Blad }
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
#   - sekcji z wpisami zasiew nie nadpisuje nigdy. Rozne sekcje w roznych plikach (np. reczny dopis tylko
#     do CLAUDE.md) wyrownuje synchronizacja (Synchronizuj-Co-Wiem, nizej) - takze przy instalacji
#     modulu wiedza (do 06.10 byl tam meldunek o roznicach, Rozjazd-Co-Wiem).
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
# z bajtami 0x00 - nie jest ani zrodlem, ani wzorem; synchronizacja melduje go w .Uwagi).
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
  $cialo = @($zrodlo.Cialo)
  $a = 0; $b = $cialo.Count - 1
  while (($a -le $b) -and -not $cialo[$a].Trim()) { $a++ }
  while (($b -ge $a) -and -not $cialo[$b].Trim()) { $b-- }
  if ($a -gt $b) { return $null }
  return (Z-Cialem-Co-Wiem $stary @($cialo[$a..$b]))
}

# Tekst z cialem sekcji "Co wiem" zastapionym liniami $cialo (bez pustych linii na brzegach); $null, gdy
# sekcji nie ma. Linia "## Co wiem" i reszta pliku zostaja co do bajtu; konce linii jak w pliku.
function Z-Cialem-Co-Wiem([string]$stary, [string[]]$cialo) {
  $nl = if ($stary.Contains("`r`n")) { "`r`n" } elseif ($stary.Contains("`n")) { "`n" } else { "`r`n" }
  $linie = @($stary -split "`r?`n")
  $g = Granice-Co-Wiem $linie
  if ($null -eq $g) { return $null }
  $nowe = @($linie | Select-Object -First ($g[0] + 1)) + @("") + @($cialo) + @("")
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

function Skrot-Linii([string]$l) {
  if ($l.Length -le 60) { return $l }
  return $l.Substring(0, 57) + "..."
}

# ------------------------------------------------------------ synchronizacja "Co wiem"
# Kazde CLI edytuje "Co wiem" we WLASNYM pliku (agent w rozmowie: poprawka, zapis na prosbe
# uzytkownika), a cykl wiedzy pisze do wszystkich naraz - roznica miedzy plikami jest wiec
# codziennoscia, nie awaria. Meldowanie jej przy kazdym starcie okna bylo falszywym alarmem, ktory
# uczy ignorowac ostrzezenia - zamiast tego synchronizujemy (Synchronizuj-Co-Wiem; wola ja straznik
# w Pilnuj-Zasad przy kazdym starcie okna kazdego CLI i wpisz-zasady.ps1):
#   - stan po ostatniej synchronizacji: ~\.claude\mr\co-wiem-sync.json - tresc sekcji (baza) i skrot
#     sekcji kazdego pliku; plik, ktorego sekcja zostala inna niz baza (zapis odmowiony), ma tam
#     tez wlasna tresc - jego zmiany liczymy wzgledem niej, a nie bazy;
#   - zmienil sie jeden plik (albo kilka tak samo - cykl wiedzy) - jego sekcja idzie do pozostalych;
#   - kilka roznie - zmiany laczymy linia po linii wzgledem bazy: rozne dopisane linie wchodza
#     wszystkie, kazda na swoim miejscu (w swojej podsekcji). Ta sama linia zmieniona inaczej (albo
#     zmieniona w jednym pliku, a skasowana w drugim) - NOWSZY WYGRYWA (decyzja uzytkownika 06.10:
#     synchronizacja w pelni automatyczna, zadnych meldunkow o konflikcie). Nowszy = plik z pozniejszym
#     czasem zapisu (LastWriteTimeUtc), remis - kolejnosc listy narzedzi. Czas pliku, a nie wlasny
#     znacznik, bo innego rzetelnego nie ma: cykl wiedzy i agenci pisza wprost do pliku, a reszte pliku
#     (bloki) przepisujemy dopiero PO synchronizacji, wiec zmiana "Co wiem" jest zawsze ostatnim
#     zapisem, jaki widzimy. Wersja przegrana nie ginie bez sladu: w stanie (pole nadpisane, ostatnie
#     $ILE_NADPISANYCH) i w .Nadpisane wyniku (straznik - do dziennika), a caly plik w kopii .bak;
#     Opis i wydruk o tym nie krzycza - to codziennosc, nie problem uzytkownika;
#   - plik bez wpisu w stanie (pierwsza synchronizacja, nowe CLI) wnosi tylko DOPISANE linie: bez
#     bazy nie da sie odroznic linii skasowanej od niedopisanej, a kasowac wiedzy na zgadywanie nie
#     wolno. Baza pierwszej synchronizacji = najbogatsza sekcja (jak przy zasiewie);
#   - zapis ponad limit narzedzia (pole Limit listy) - odmowa z powodem, pozostale pliki i tak dostaja
#     swoje; przed kazdym zapisem kopia .bak-<stempel>, a tuz przed nim plik czytamy jeszcze raz -
#     zmieniony w miedzyczasie (cykl wiedzy) zostaje do nastepnego przebiegu.
# Puste sekcje i pliki bez sekcji nie biora udzialu - te zaklada i zasiewa Plan-Pliku-Narzedzia.
$PLIK_SYNC_CO_WIEM = ".claude\mr\co-wiem-sync.json"
$ILE_NADPISANYCH = 50

# Sekcja jako linie do porownan i zapisu: bez koncowych spacji, bez pustych linii na brzegach.
# Jedna tablica (przecinek) - bierz przypisaniem.
function Linie-Co-Wiem($cialo) {
  $l = @(@($cialo) | ForEach-Object { "$_".TrimEnd() })
  $a = 0; $b = $l.Count - 1
  while (($a -le $b) -and -not $l[$a]) { $a++ }
  while (($b -ge $a) -and -not $l[$b]) { $b-- }
  if ($a -gt $b) { return ,([string[]]@()) }
  return ,([string[]]@($l[$a..$b]))
}

function Odcisk-Co-Wiem([string[]]$linie) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $h = $sha.ComputeHash((New-Object System.Text.UTF8Encoding($false)).GetBytes((@($linie) -join "`n"))) } finally { $sha.Dispose() }
  return [System.BitConverter]::ToString($h).Replace("-", "")
}

function Rowne-Linie([string[]]$a, [string[]]$b) { return ((@($a) -join "`n") -ceq (@($b) -join "`n")) }

# Dopasowanie linii $a do $b - najdluzszy wspolny podciag (rowny poczatek i koniec zdjete z gory, bo
# zmiana to zwykle kilka linii w srodku): tablica dlugosci $a z indeksem linii w $b albo -1.
function Dopasowanie-Linii([string[]]$a, [string[]]$b) {
  $n = @($a).Count; $m = @($b).Count
  $mapa = New-Object 'int[]' $n
  for ($i = 0; $i -lt $n; $i++) { $mapa[$i] = -1 }
  $p = 0
  while (($p -lt $n) -and ($p -lt $m) -and ($a[$p] -ceq $b[$p])) { $mapa[$p] = $p; $p++ }
  $k = 0
  while (($k -lt ($n - $p)) -and ($k -lt ($m - $p)) -and ($a[$n - 1 - $k] -ceq $b[$m - 1 - $k])) { $mapa[$n - 1 - $k] = $m - 1 - $k; $k++ }
  $n2 = $n - $p - $k; $m2 = $m - $p - $k
  if (($n2 -le 0) -or ($m2 -le 0)) { return ,$mapa }
  $w = $m2 + 1
  $L = New-Object 'int[]' (($n2 + 1) * $w)
  for ($i = $n2 - 1; $i -ge 0; $i--) {
    $ai = $a[$p + $i]
    for ($j = $m2 - 1; $j -ge 0; $j--) {
      if ($ai -ceq $b[$p + $j]) { $L[$i * $w + $j] = $L[($i + 1) * $w + $j + 1] + 1 }
      else { $L[$i * $w + $j] = [Math]::Max($L[($i + 1) * $w + $j], $L[$i * $w + $j + 1]) }
    }
  }
  $i = 0; $j = 0
  while (($i -lt $n2) -and ($j -lt $m2)) {
    if ($a[$p + $i] -ceq $b[$p + $j]) { $mapa[$p + $i] = $p + $j; $i++; $j++ }
    elseif ($L[($i + 1) * $w + $j] -ge $L[$i * $w + $j + 1]) { $i++ }
    else { $j++ }
  }
  return ,$mapa
}

# Zmiany $b wzgledem $a (z dopasowania $mapa): Od, Do - zakres linii $a do zastapienia (Od = Do:
# wstawka przed linia Od), Nowe - linie z $b.
function Zmiany-Linii([string[]]$a, [string[]]$b, $mapa) {
  $wynik = @()
  $n = @($a).Count
  $pa = -1; $pb = -1
  for ($i = 0; $i -le $n; $i++) {
    if ($i -lt $n) { if ($mapa[$i] -lt 0) { continue }; $ca = $i; $cb = $mapa[$i] }
    else { $ca = $n; $cb = @($b).Count }
    if (($ca -gt $pa + 1) -or ($cb -gt $pb + 1)) {
      $nowe = [string[]]@()
      if ($cb -gt $pb + 1) { $nowe = [string[]]@($b[($pb + 1)..($cb - 1)]) }
      $wynik += [pscustomobject]@{ Od = $pa + 1; Do = $ca; Nowe = $nowe }
    }
    $pa = $ca; $pb = $cb
  }
  return ,$wynik
}

# Zmiany liczone wzgledem wlasnej tresci pliku ($a - inna niz baza, gdy jego zapis byl odmowiony,
# albo same linie pliku obecne w bazie, gdy pliku nie ma w stanie) przeniesione na baze przez
# dopasowanie $mapa ($a -> baza). Wstawka idzie za najblizsza wczesniejsza linia, ktora w bazie jest.
# Zmiana linii, ktorych w bazie nie ma (albo nie leza obok siebie), rozpada sie na skasowanie tych
# z nich, ktore w bazie sa (kazda osobno), i wstawke nowych linii w miejscu pierwszej z nich (bez
# takiej - za najblizsza wczesniejsza linia z bazy): nic nie przepada i nic nie staje.
function Na-Baze($zmiany, $mapa) {
  $wynik = @()
  foreach ($z in $zmiany) {
    $poz = 0
    for ($k = $z.Od - 1; $k -ge 0; $k--) { if ($mapa[$k] -ge 0) { $poz = $mapa[$k] + 1; break } }
    if ($z.Od -lt $z.Do) {
      $ok = $true
      for ($k = $z.Od; $k -lt $z.Do; $k++) {
        if (($mapa[$k] -lt 0) -or (($k -gt $z.Od) -and ($mapa[$k] -ne $mapa[$k - 1] + 1))) { $ok = $false; break }
      }
      if ($ok) { $wynik += [pscustomobject]@{ Od = $mapa[$z.Od]; Do = $mapa[$z.Do - 1] + 1; Nowe = $z.Nowe }; continue }
      $pierwsza = -1
      for ($k = $z.Od; $k -lt $z.Do; $k++) {
        if ($mapa[$k] -lt 0) { continue }
        if ($pierwsza -lt 0) { $pierwsza = $mapa[$k] }
        $wynik += [pscustomobject]@{ Od = $mapa[$k]; Do = $mapa[$k] + 1; Nowe = [string[]]@() }
      }
      if ($pierwsza -ge 0) { $poz = $pierwsza }
      if (@($z.Nowe).Count -gt 0) { $wynik += [pscustomobject]@{ Od = $poz; Do = $poz; Nowe = $z.Nowe } }
      continue
    }
    $wynik += [pscustomobject]@{ Od = $poz; Do = $poz; Nowe = $z.Nowe }
  }
  return ,$wynik
}

function Czy-Podciag([string[]]$maly, [string[]]$duzy) {
  $j = 0
  foreach ($x in @($duzy)) { if (($j -lt @($maly).Count) -and ($x -ceq $maly[$j])) { $j++ } }
  return ($j -eq @($maly).Count)
}

# Zamiana linii bazy rowna liczba linii na rowna - linia po linii (wersje roznych plikow tej samej
# linii spotykaja sie wtedy pojedynczo, a nie calymi blokami: poprawka linii 3 w jednym pliku nie
# zabiera poprawki linii 4 z drugiego). Pary bez zmiany odpadaja.
function Rozbij-Zamiany([string[]]$baza, $zmiany) {
  $wynik = @()
  foreach ($z in $zmiany) {
    $ile = $z.Do - $z.Od
    if (($ile -lt 1) -or ($ile -ne @($z.Nowe).Count)) { $wynik += $z; continue }
    for ($k = 0; $k -lt $ile; $k++) {
      if ($baza[$z.Od + $k] -ceq $z.Nowe[$k]) { continue }
      $wynik += [pscustomobject]@{ Od = $z.Od + $k; Do = $z.Od + $k + 1; Nowe = [string[]]@($z.Nowe[$k]) }
    }
  }
  return ,$wynik
}

function Wersja-Linii($h) {
  if (@($h.Nowe).Count -gt 0) { return "'" + (Skrot-Linii (@($h.Nowe) -join ' / ')) + "'" }
  return "(skasowana)"
}

# Laczy zmiany kilku plikow na bazie. $zestawy - lista @{ Plik (~/...); Czas (czas zapisu pliku, UTC);
# Zmiany (Od, Do, Nowe na bazie) } w kolejnosci listy narzedzi. Wynik: .Linie (tresc po polaczeniu)
# i .Nadpisane (opisy wersji, ktore przegraly - do dziennika). Konfliktow nie ma:
#   - te same zmiany z kilku plikow licza sie raz;
#   - wstawki (dopisy) wchodza wszystkie - w tym samym miejscu w kolejnosci listy narzedzi; linia
#     niepusta, ktora w wyniku juz jest, drugi raz nie wchodzi; dopis w srodku linii zamienionych
#     przez inny plik staje zaraz za nimi;
#   - zamiany (poprawka, skasowanie) tych samych linii: jedna wersja zawierajaca druga (ta sama
#     poprawka plus dopis) wygrywa zawsze - dopis nie przepada; inaczej NOWSZY plik (Czas, remis -
#     wczesniejszy na liscie). Skasowanie nie "zawiera sie" w niczym: skasowanie w nowszym pliku
#     wygrywa z poprawka w starszym, a poprawka w nowszym - ze skasowaniem w starszym.
function Polacz-Zmiany-Co-Wiem([string[]]$baza, $zestawy) {
  $baza = [string[]]@($baza)
  $wszystkie = @()
  $nr = 0
  foreach ($zs in $zestawy) {
    $czas = [datetime]::MinValue
    if ($zs.PSObject.Properties["Czas"] -and $zs.Czas) { $czas = [datetime]$zs.Czas }
    foreach ($z in (Rozbij-Zamiany $baza $zs.Zmiany)) {
      $klucz = "$($z.Od)|$($z.Do)|" + (@($z.Nowe) -join "`n")
      $byl = @($wszystkie | Where-Object { $_.Klucz -ceq $klucz })
      if ($byl.Count -gt 0) {
        $byl[0].Pliki += $zs.Plik
        if ($czas -gt $byl[0].Czas) { $byl[0].Czas = $czas }
        continue
      }
      $wszystkie += [pscustomobject]@{ Od = $z.Od; Do = $z.Do; Nowe = [string[]]@($z.Nowe); Klucz = $klucz; Pliki = @($zs.Plik); Czas = $czas; Nr = $nr }
    }
    $nr++
  }
  $nadpisane = @()
  # zamiany od najnowszej; kazda kolejna wchodzi, jesli nie zachodzi na zadna juz przyjeta
  $kolejka = @($wszystkie | Where-Object { $_.Od -lt $_.Do } | Sort-Object -Property @{ Expression = { $_.Czas }; Descending = $true }, @{ Expression = { $_.Nr }; Descending = $false })
  $zamiany = New-Object 'System.Collections.Generic.List[object]'
  foreach ($h in $kolejka) {
    $a = $null
    foreach ($x in $zamiany) { if (($h.Od -lt $x.Do) -and ($x.Od -lt $h.Do)) { $a = $x; break } }
    if ($null -eq $a) { $zamiany.Add($h); continue }
    if (($h.Od -eq $a.Od) -and ($h.Do -eq $a.Do) -and (@($h.Nowe).Count -gt 0) -and (@($a.Nowe).Count -gt 0)) {
      if (Czy-Podciag $h.Nowe $a.Nowe) { continue }                          # ta sama poprawka, w nowszym z dopisem
      if (Czy-Podciag $a.Nowe $h.Nowe) { $zamiany[$zamiany.IndexOf($a)] = $h; continue }   # starszy = to samo + dopis
    }
    $nadpisane += ("linia '$(Skrot-Linii $baza[[Math]::Max($h.Od, $a.Od)])': wygral nowszy $(@($a.Pliki) -join ' i ') -> " +
                   "$(Wersja-Linii $a), nadpisana wersja z $(@($h.Pliki) -join ' i ') -> $(Wersja-Linii $h)")
  }
  # wstawki: w srodku przyjetej zamiany - zaraz za nia
  $wstawki = @()
  foreach ($s in @($wszystkie | Where-Object { $_.Od -eq $_.Do })) {
    $poz = $s.Od
    foreach ($h in $zamiany) { if (($h.Od -lt $poz) -and ($poz -lt $h.Do)) { $poz = $h.Do } }
    $wstawki += [pscustomobject]@{ Od = $poz; Do = $poz; Nowe = $s.Nowe; Nr = $s.Nr; Idx = $wstawki.Count }
  }
  $wstawki = @($wstawki | Sort-Object -Property Nr, Idx)   # PS 5.1 nie ma -Stable

  # linie niepuste, ktore w wyniku zostana - wstawka ich nie dubluje
  $obecne = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  for ($i = 0; $i -lt $baza.Count; $i++) {
    if (@($zamiany | Where-Object { ($_.Od -le $i) -and ($i -lt $_.Do) }).Count -eq 0) { if ($baza[$i]) { [void]$obecne.Add($baza[$i]) } }
  }
  foreach ($h in $zamiany) { foreach ($l in $h.Nowe) { if ($l) { [void]$obecne.Add($l) } } }
  $wynik = New-Object 'System.Collections.Generic.List[string]'
  $i = 0
  while ($true) {
    foreach ($s in @($wstawki | Where-Object { $_.Od -eq $i })) {
      $dodaj = @($s.Nowe | Where-Object { (-not $_) -or -not $obecne.Contains($_) })
      if (@($dodaj | Where-Object { $_ }).Count -eq 0) { continue }
      foreach ($l in $dodaj) { $wynik.Add($l); if ($l) { [void]$obecne.Add($l) } }
    }
    if ($i -ge $baza.Count) { break }
    $h = @($zamiany | Where-Object { $_.Od -eq $i }) | Select-Object -First 1
    if ($h) { foreach ($l in $h.Nowe) { $wynik.Add($l) }; $i = $h.Do; continue }
    $wynik.Add($baza[$i]); $i++
  }
  return [pscustomobject]@{ Linie = (Linie-Co-Wiem $wynik.ToArray()); Nadpisane = $nadpisane }
}

# Stan ostatniej synchronizacji albo $null (pierwsza). Plik nieczytelny = wyjatek (wolajacy liczy to
# jak pierwsza synchronizacje - same dopisy, nic nie ginie - i mowi o tym).
function Czytaj-Stan-Co-Wiem([string]$dom) {
  $p = Join-Path $dom $PLIK_SYNC_CO_WIEM
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $null }
  $j = (Czytaj-Utf8 $p) | ConvertFrom-Json
  if ((-not $j) -or ($null -eq $j.baza) -or ($null -eq $j.pliki)) { throw "brak pol baza/pliki" }
  $s = [pscustomobject]@{ Baza = [string[]]@($j.baza | ForEach-Object { "$_" }); Pliki = @{}; Nadpisane = @(); Tekst = "" }
  if ($null -ne $j.nadpisane) { $s.Nadpisane = @($j.nadpisane | ForEach-Object { "$_" }) }
  foreach ($w in $j.pliki.PSObject.Properties) {
    $linie = $null
    if ($null -ne $w.Value.linie) { $linie = [string[]]@($w.Value.linie | ForEach-Object { "$_" }) }
    $s.Pliki[$w.Name] = [pscustomobject]@{ Skrot = "$($w.Value.skrot)"; Linie = $linie }
  }
  return $s
}

# $nadpisane - slad "nowszy wygral" (najnowsze na koncu, najwyzej $ILE_NADPISANYCH): dziennik, nie meldunek.
function Zapisz-Stan-Co-Wiem([string]$dom, [string[]]$baza, $pliki, [string[]]$nadpisane, [string]$poprzedni) {
  $o = [ordered]@{ wersja = 1; baza = [string[]]@($baza); pliki = [ordered]@{}; nadpisane = [string[]]@($nadpisane | Select-Object -Last $ILE_NADPISANYCH) }
  foreach ($id in $pliki.Keys) {
    $w = [ordered]@{ skrot = $pliki[$id].Skrot }
    if ($null -ne $pliki[$id].Linie) { $w.linie = [string[]]@($pliki[$id].Linie) }
    $o.pliki[$id] = $w
  }
  $tekst = $o | ConvertTo-Json -Depth 6
  if ($tekst -ceq $poprzedni) { return }   # nic nowego - bez zapisu przy kazdym starcie okna
  $p = Join-Path $dom $PLIK_SYNC_CO_WIEM
  Zapisz-Trwale $p $tekst (New-Object System.Text.UTF8Encoding($false))
}

# Synchronizacja "Co wiem" miedzy plikami obecnych narzedzi AI (regula wyzej). $wzor - Id narzedzia,
# ktorego sekcja idzie do wszystkich bez laczenia (wpisz-zasady.ps1 -WzorCoWiem: narzedzie reczne -
# "ta wersja i koniec" albo synchronizacja od czysta). $proba - sam plan: bez zapisu plikow i stanu.
# Zapis wymaga zapis-trwaly.ps1 (Zapisz-Trwale, Kopiuj-Trwale). Wynik:
#   .Opis       jedno zdanie o tym, co zrobiono, albo $null (nic do zrobienia)
#   .Odmowy     "ODMOWA ZAPISU (<narzedzie>): ..." - sufit; wolajacy stawia je na poczatku meldunku
#   .Nadpisane  wersje linii, ktore przegraly z nowszym plikiem - do dziennika, nie do meldunku
#   .Uwagi      rzeczy do dziennika (stan nieczytelny, plik zmieniony w trakcie, plik pominiety)
#   .Zapisane   pliki zapisane (albo, z $proba, do zapisu)
function Synchronizuj-Co-Wiem([string]$dom, [string]$wzor = "", [bool]$proba = $false) {
  $w = [pscustomobject]@{ Opis = $null; Odmowy = @(); Nadpisane = @(); Uwagi = @(); Zapisane = @() }
  if (-not $proba -and -not (Get-Command Zapisz-Trwale -ErrorAction SilentlyContinue)) { throw "nie ma zapis-trwaly.ps1 (Zapisz-Trwale) - nie synchronizuje 'Co wiem'" }
  $obecne = @(Cele-Narzedzi $dom | ForEach-Object { $_.Id })
  $udzial = @()
  foreach ($s in (Sekcje-Co-Wiem $dom)) {
    if ($obecne -notcontains $s.Id) { continue }
    if ($s.Blad) { $w.Uwagi += "$($s.Plik) pominiety w synchronizacji 'Co wiem' ($($s.Blad))"; continue }
    if (($null -eq $s.Cialo) -or ($s.Wpisy.Count -eq 0)) { continue }
    $l = Linie-Co-Wiem $s.Cialo
    $czas = [System.IO.File]::GetLastWriteTimeUtc($s.Sciezka)
    $udzial += [pscustomobject]@{ S = $s; N = (Narzedzie-AI $s.Id); Linie = $l; Odcisk = (Odcisk-Co-Wiem $l); Czas = $czas }
  }
  $stan = $null; $poprzedni = $null
  try {
    $stan = Czytaj-Stan-Co-Wiem $dom
    if ($stan) { $poprzedni = Czytaj-Utf8 (Join-Path $dom $PLIK_SYNC_CO_WIEM) }
  } catch {
    $w.Uwagi += "stan synchronizacji 'Co wiem' ($PLIK_SYNC_CO_WIEM) nieczytelny ($($_.Exception.Message)) - licze jak pierwsza synchronizacje: same dopisy, nic nie kasuje"
    $stan = $null
  }
  if ($udzial.Count -eq 0) { return $w }

  # --- tresc docelowa
  $baza = $null; $cel = $null; $zrodla = @(); $pierwsza = $false
  if ($wzor) {
    $wz = @($udzial | Where-Object { $_.S.Id -eq $wzor })
    if ($wz.Count -eq 0) { throw "w pliku narzedzia '$wzor' nie ma sekcji 'Co wiem' z wpisami (albo narzedzia tu nie ma) - nie moze byc wzorem" }
    $cel = $wz[0].Linie; $zrodla = @($wz[0].S.Plik)
  } else {
    if ($stan) { $baza = $stan.Baza }
    else {
      $pierwsza = $true
      $naj = $udzial[0]
      foreach ($u in $udzial) { if ($u.S.Znakow -gt $naj.S.Znakow) { $naj = $u } }
      $baza = $naj.Linie
    }
    $wBazie = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($l in $baza) { [void]$wBazie.Add($l) }
    $zestawy = @()
    foreach ($u in $udzial) {
      $wpis = $null
      if ($stan -and $stan.Pliki.ContainsKey($u.S.Id)) { $wpis = $stan.Pliki[$u.S.Id] }
      if ($wpis -and ($wpis.Skrot -eq $u.Odcisk)) { continue }          # bez zmian od ostatniej synchronizacji
      $wlasna = $null
      if ($wpis) { $wlasna = if ($null -ne $wpis.Linie) { $wpis.Linie } else { $baza } }
      else { $wlasna = [string[]]@($u.Linie | Where-Object { $wBazie.Contains($_) }) }   # bez stanu: same dopisy
      if (Rowne-Linie $wlasna $u.Linie) { continue }
      $zm = Zmiany-Linii $wlasna $u.Linie (Dopasowanie-Linii $wlasna $u.Linie)
      if (-not (Rowne-Linie $wlasna $baza)) { $zm = Na-Baze $zm (Dopasowanie-Linii $wlasna $baza) }
      if ($zm.Count -gt 0) { $zestawy += [pscustomobject]@{ Plik = $u.S.Plik; Czas = $u.Czas; Zmiany = $zm } }
    }
    if ($zestawy.Count -eq 0) { $cel = $baza }
    else {
      $zrodla = @($zestawy | ForEach-Object { $_.Plik })
      $pol = Polacz-Zmiany-Co-Wiem $baza $zestawy
      $cel = $pol.Linie
      $w.Nadpisane = @($pol.Nadpisane)
    }
  }

  # --- zapis do plikow, ktore maja inna tresc
  $stempel = Get-Date -Format "yyyyMMdd-HHmmss"
  $koncowe = @{}
  $kopie = @()
  foreach ($u in $udzial) {
    $koncowe[$u.S.Id] = $u.Linie
    if (Rowne-Linie $u.Linie $cel) { continue }
    try {
      $tekst = Czytaj-Utf8 $u.S.Sciezka
      if (-not (Rowne-Linie (Linie-Co-Wiem (Cialo-Co-Wiem $tekst)) $u.Linie)) {
        $w.Uwagi += "$($u.S.Plik) zmienil sie w trakcie synchronizacji 'Co wiem' - zostawiam go do nastepnego przebiegu"
        continue
      }
      $nowy = Z-Cialem-Co-Wiem $tekst $cel
      $sufit = Ponad-Limit $u.N $tekst $nowy
      if ($sufit) {
        $ile = (New-Object System.Text.UTF8Encoding($false)).GetByteCount($nowy)
        $w.Odmowy += ("ODMOWA ZAPISU ($($u.N.Nazwa)): synchronizacja sekcji 'Co wiem' dalaby $($u.S.Plik) $ile B, a " +
                      "$($u.N.Nazwa) czyta najwyzej $($u.N.Limit) B - NIE zapisalem, $($u.N.Nazwa) nie ma najnowszej wiedzy " +
                      "(pozostale pliki zsynchronizowane). Skroc 'Co wiem' (np. zestawienia do wiedza\) albo reszte $($u.S.Plik).")
        continue
      }
      if ($proba) { $w.Zapisane += $u.S.Plik; continue }
      $bak = "$($u.S.Sciezka).bak-$stempel"
      Kopiuj-Trwale $u.S.Sciezka $bak
      Zapisz-Trwale $u.S.Sciezka $nowy (New-Object System.Text.UTF8Encoding($false))
      $po = Linie-Co-Wiem (Cialo-Co-Wiem (Czytaj-Utf8 $u.S.Sciezka))
      if (-not (Rowne-Linie $po $cel)) { throw "po zapisie sekcja w pliku nie zgadza sie z tym, co mialo wejsc" }
      $koncowe[$u.S.Id] = $cel
      $w.Zapisane += $u.S.Plik
      $kopie += $bak
    } catch {
      $w.Odmowy += "ODMOWA ZAPISU ($($u.N.Nazwa)): synchronizacja sekcji 'Co wiem' do $($u.S.Plik) nie wyszla - $($_.Exception.Message)"
    }
  }
  if ($w.Zapisane.Count -gt 0) {
    $skad = if ($zrodla.Count -gt 0) { " (zmiany z " + ($zrodla -join ", ") + ")" } else { "" }
    $co = if ($proba) { "zapisalbym" } else { "zapisana" }
    $jak = if ($pierwsza) { "pierwsza synchronizacja sekcji 'Co wiem' - same dopisy, nic nie skasowane" } elseif ($wzor) { "sekcja 'Co wiem' wedlug wzoru" } else { "sekcja 'Co wiem' zsynchronizowana" }
    $w.Opis = "$jak$skad, $co w: " + ($w.Zapisane -join ", ")
    if ($kopie.Count -gt 0) { $w.Opis += " (kopie .bak-$stempel obok)" }
  }
  if (-not $proba) {
    $pl = [ordered]@{}
    foreach ($u in $udzial) {
      $k = $koncowe[$u.S.Id]
      $pl[$u.S.Id] = [pscustomobject]@{ Skrot = (Odcisk-Co-Wiem $k); Linie = $(if (Rowne-Linie $k $cel) { $null } else { $k }) }
    }
    $slad = @()
    if ($stan) { $slad = @($stan.Nadpisane) }
    $kiedy = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    foreach ($x in $w.Nadpisane) { $slad += "$kiedy $x" }
    Zapisz-Stan-Co-Wiem $dom $cel $pl $slad $poprzedni
  }
  return $w
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
