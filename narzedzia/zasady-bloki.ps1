# narzedzia\zasady-bloki.ps1 - bloki zasad pamieci MegaRuchacza w plikach instrukcji narzedzi AI
# (~\.claude\CLAUDE.md, ~\.codex\AGENTS.md). Wczytywany kropka (same definicje) przez
# wpisz-zasady.ps1 (zapis), straznik-zasad.ps1 (Pilnuj-Zasad: czy zapis jest potrzebny) i wdroz.ps1
# (sprawdzenie po instalacji). Jedno miejsce na znaczniki i regule skladania pliku: dwie kopie tej
# reguly rozjechalyby sie przy pierwszej poprawce, a wtedy straznik przepisywalby zasady przy
# kazdym otwarciu okna.
#
# Od P59a dwa bloki, kazdy z wlasnego zrodla i dla wlasnego modulu instalatora:
#   lore    <!-- MegaRuchacz:lore:start -->   ... <!-- MegaRuchacz:lore:koniec -->     zasady-lore.md
#   wiedza  <!-- MegaRuchacz:wiedza:start --> ... <!-- MegaRuchacz:wiedza:koniec -->   zasady-wiedza.md
# Do P59a stal jeden wspolny blok <!-- MegaRuchacz:start --> ... <!-- MegaRuchacz:koniec -->
# (zasady-globalne.md). Stary blok jest zamieniany na nowe NA SWOIM MIEJSCU - wszystko przed nim
# (sekcja "Co wiem") i za nim zostaje co do bajtu. Ten sam stary znacznik ma w projektowym
# AGENTS.md (wdroz.ps1) inne znaczenie - zasady kierownika; tu chodzi wylacznie o pliki globalne.
#
# Ktore bloki maja stac, mowi rejestr instalacji (narzedzia\instalacja\stan.ps1, moduly "lore"
# i "wiedza"): brak rejestru = oba (instalacja sprzed rejestru); rejestr nieczytelny = oba i NIC
# nie zdejmujemy - alarm, nie odinstalowanie (Chciane-Bloki-Zasad).

# stan.ps1 wczytujemy ZAWSZE, takze gdy Czytaj-Instalacje juz widac: jego funkcje trzymaja liste
# modulow w $script:MR_MODULY, a ten zakres to skrypt, ktory WOLA funkcje - wpisz-zasady.ps1 wolany
# "&" ze straznika widzial funkcje straznika z pusta lista modulow (zlapane testem: wszystkie moduly
# "wylaczone"). Z tego samego powodu ten plik nie trzyma niczego w $script: - same funkcje.
$plikStanuInstalacji = Join-Path $PSScriptRoot "instalacja\stan.ps1"
if (Test-Path -LiteralPath $plikStanuInstalacji) { . $plikStanuInstalacji }

# kolejnosc = kolejnosc blokow w pliku
function Bloki-Zasad { return @("lore", "wiedza") }
function Start-Kierownika-Zasad { return "<!-- MegaRuchacz:kierownik:start -->" }

# @(start, koniec); "stary" = wspolny blok sprzed P59a.
function Znaczniki-Zasad([string]$nazwa) {
  if ($nazwa -eq "stary") { return @("<!-- MegaRuchacz:start -->", "<!-- MegaRuchacz:koniec -->") }
  return @("<!-- MegaRuchacz:${nazwa}:start -->", "<!-- MegaRuchacz:${nazwa}:koniec -->")
}

# Katalog repo w postaci, ktora trafia do tresci bloku za {{ZRODLO}}. Zawsze ta sama dla tego samego
# katalogu: hook podaje straznikowi "C:/dev/x", reka idzie "C:\dev\x\" - bez tego kazda droga
# uznawalaby blok wpisany przez druga za nieaktualny.
function Zrodlo-Zasad([string]$Zrodlo) {
  return ([System.IO.Path]::GetFullPath($Zrodlo)).TrimEnd('\', '/')
}

# Linie tresci bloku: wszystko pod linia-znacznikiem "TRESC DO WSTRZYKNIECIA" (dopasowanym bez
# polskich znakow), bez pustych linii z gory i z dolu, z {{ZRODLO}} zamienionym na katalog repo.
# Brak pliku, znacznika albo tresci = wyjatek - lepiej nie wpisac nic niz pusty blok.
function Tresc-Zrodla-Zasad([string]$Zrodlo, [string]$nazwa) {
  $plik = Join-Path $Zrodlo "zasady-$nazwa.md"
  if (-not (Test-Path -LiteralPath $plik)) { throw "nie ma pliku ze zrodlem zasad: $plik" }
  $tekst = [System.IO.File]::ReadAllText($plik, (New-Object System.Text.UTF8Encoding($false, $true)))
  $linie = @($tekst.TrimStart([char]0xFEFF) -split "\r?\n")
  $start = -1
  for ($i = 0; $i -lt $linie.Count; $i++) {
    if ($linie[$i] -match '^<!--.*WSTRZYKNI.*-->\s*$') { $start = $i; break }
  }
  if ($start -lt 0) { throw "w $plik nie ma linii-znacznika 'TRESC DO WSTRZYKNIECIA PONIZEJ TEJ LINII'" }
  # obcinamy puste linie na indeksach, nie zakresami - zakres 0..-1 w PowerShellu zawija sie na koniec
  $od = $start + 1
  $doo = $linie.Count - 1
  while ($od -le $doo -and $linie[$od].Trim() -eq "")  { $od++ }
  while ($doo -ge $od -and $linie[$doo].Trim() -eq "") { $doo-- }
  if ($od -gt $doo) { throw "w $plik pod linia-znacznikiem nie ma zadnej tresci" }
  $z = Zrodlo-Zasad $Zrodlo
  return ,@($linie[$od..$doo] | ForEach-Object { $_.Replace('{{ZRODLO}}', $z) })
}

function Tekst-Bloku-Zasad([string]$nazwa, $linie, [string]$nl) {
  $z = Znaczniki-Zasad $nazwa
  return (($z[0], (@($linie) -join $nl), $z[1]) -join $nl)
}

# Gdzie stoja nasze bloki zasad. Zwraca .Bloki (nazwa -> @{ Od; Do }, Do wylacznie - za znacznikiem
# konca; "stary" = blok sprzed P59a) i .Blad (powod, dla ktorego pliku nie wolno ruszac, albo $null).
# Kazdy blok najwyzej raz, oba jego znaczniki albo zaden, start przed koncem, bloki rozlaczne -
# inaczej nie zgadujemy, co jest czyje.
function Znajdz-Bloki-Zasad([string]$tekst) {
  $w = [pscustomobject]@{ Bloki = [ordered]@{}; Blad = $null }
  if ($null -eq $tekst) { $tekst = "" }
  $zakresy = @()
  foreach ($n in (@("stary") + @(Bloki-Zasad))) {
    $z = Znaczniki-Zasad $n
    $ileS = ([regex]::Matches($tekst, [regex]::Escape($z[0]))).Count
    $ileK = ([regex]::Matches($tekst, [regex]::Escape($z[1]))).Count
    if ($ileS -eq 0 -and $ileK -eq 0) { continue }
    $opis = if ($n -eq "stary") { "stary blok MegaRuchacz:start" } else { "blok MegaRuchacz:$n" }
    if ($ileS -ne 1 -or $ileK -ne 1) { $w.Blad = "$opis ma $ileS znacznik(ow) startu i $ileK konca"; return $w }
    $i = $tekst.IndexOf($z[0], [System.StringComparison]::Ordinal)
    $j = $tekst.IndexOf($z[1], [System.StringComparison]::Ordinal)
    if ($j -lt $i) { $w.Blad = "$opis ma znaczniki w zlej kolejnosci"; return $w }
    $w.Bloki[$n] = [pscustomobject]@{ Od = $i; Do = $j + $z[1].Length }
    $zakresy += $w.Bloki[$n]
  }
  $po = @($zakresy | Sort-Object Od)
  for ($k = 1; $k -lt $po.Count; $k++) {
    if ($po[$k].Od -lt $po[$k - 1].Do) { $w.Blad = "bloki zasad MegaRuchacza nachodza na siebie"; return $w }
  }
  return $w
}

# Nazwy blokow, ktore w tekscie juz SA - stary blok liczy sie za oba (niesie obie tresci).
function Obecne-Bloki-Zasad([string]$tekst) {
  $f = Znajdz-Bloki-Zasad $tekst
  if ($f.Blad) { return @() }
  if ($f.Bloki.Contains("stary")) { return @(Bloki-Zasad) }
  return @(Bloki-Zasad | Where-Object { $f.Bloki.Contains($_) })
}

# Ktore bloki maja stac wedlug rejestru instalacji. .Nazwy - lista; .Zdejmuj - czy wolno zdjac
# pozostale (NIE przy rejestrze nieczytelnym: wtedy wszystko jest "wlaczone" i nic nie znika);
# .Blad - tresc bledu odczytu rejestru albo $null; .Zrodlo - plik / domyslne / awaryjne / brak-umowy.
function Chciane-Bloki-Zasad([string]$KatalogDomowy) {
  $w = [pscustomobject]@{ Nazwy = @(Bloki-Zasad); Zdejmuj = $true; Blad = $null; Zrodlo = "brak-umowy" }
  # starsza kopia narzedzia bez narzedzia\instalacja\stan.ps1 - jak przed rejestrem: oba bloki
  if (-not (Get-Command Czytaj-Instalacje -ErrorAction SilentlyContinue)) { return $w }
  $s = Czytaj-Instalacje $KatalogDomowy
  $w.Zrodlo = $s.zrodlo
  if ($s.blad) { $w.Blad = $s.blad; $w.Zdejmuj = $false; return $w }
  # brak klucza = wlaczony (umowa stan.ps1) - tak samo, gdy lista modulow umowy okazala sie pusta
  $w.Nazwy = @(Bloki-Zasad | Where-Object { ($null -eq $s.moduly.$_) -or [bool]$s.moduly.$_ })
  return $w
}

# Wycina zakres [od, do) razem z pustymi liniami wokol, tak zeby nie zostala podwojna pusta linia.
function Wytnij-Zakres-Zasad([string]$tekst, [int]$od, [int]$do, [string]$nl) {
  $przed = $tekst.Substring(0, $od).TrimEnd("`r", "`n")
  $po    = $tekst.Substring($do).TrimStart("`r", "`n")
  if ($przed.Length -eq 0) { return $po }
  if ($po.Length -eq 0)    { return $przed + $nl }
  return $przed + $nl + $nl + $po
}

# Tekst pliku po wpisaniu blokow zasad. $tresci: [ordered] nazwa -> linie tresci (bloki, ktore maja
# stac); $zdejmij: nazwy blokow do zdjecia. Blok spoza obu list zostaje, jaki jest. Regula:
#   - stary blok -> NA JEGO MIEJSCU bloki z $tresci, ktorych nie ma nigdzie indziej (kolejnosc lore,
#     wiedza); gdy takich nie ma - stary blok znika. Tekst przed nim i za nim zostaje co do bajtu;
#   - blok, ktory stoi i ma stac - tresc podmieniona na miejscu;
#   - blok, ktory stoi, a ma zniknac - wyciety bez podwojnej pustej linii;
#   - blok, ktorego nie ma - obok bloku-brata (lore przed wiedza), inaczej przed blokiem
#     kierownika, inaczej na koncu pliku.
# Konce linii bloku jak w reszcie pliku. Zle znaczniki = wyjatek (nie zgadujemy, co jest czyje).
function Zloz-Plik-Zasad([string]$stary, $tresci, [string[]]$zdejmij = @()) {
  if ($null -eq $stary) { $stary = "" }
  if ($null -eq $tresci) { $tresci = [ordered]@{} }
  $nl = "`r`n"
  if (-not $stary.Contains("`r`n") -and $stary.Contains("`n")) { $nl = "`n" }
  $tekst = $stary
  $f = Znajdz-Bloki-Zasad $tekst
  if ($f.Blad) { throw $f.Blad }

  if ($f.Bloki.Contains("stary")) {
    $z = $f.Bloki["stary"]
    $nowe = @()
    foreach ($n in (Bloki-Zasad)) {
      if ($tresci.Contains($n) -and -not $f.Bloki.Contains($n)) { $nowe += (Tekst-Bloku-Zasad $n $tresci[$n] $nl) }
    }
    if ($nowe.Count -gt 0) { $tekst = $tekst.Substring(0, $z.Od) + ($nowe -join ($nl + $nl)) + $tekst.Substring($z.Do) }
    else { $tekst = Wytnij-Zakres-Zasad $tekst $z.Od $z.Do $nl }
    $f = Znajdz-Bloki-Zasad $tekst
  }

  foreach ($n in (Bloki-Zasad)) {
    if (-not $f.Bloki.Contains($n)) { continue }
    $z = $f.Bloki[$n]
    if ($tresci.Contains($n)) {
      $tekst = $tekst.Substring(0, $z.Od) + (Tekst-Bloku-Zasad $n $tresci[$n] $nl) + $tekst.Substring($z.Do)
    } elseif ($zdejmij -contains $n) {
      $tekst = Wytnij-Zakres-Zasad $tekst $z.Od $z.Do $nl
    }
    $f = Znajdz-Bloki-Zasad $tekst
  }

  $nazwy = @(Bloki-Zasad)
  for ($k = 0; $k -lt $nazwy.Count; $k++) {
    $n = $nazwy[$k]
    if (-not $tresci.Contains($n) -or $f.Bloki.Contains($n)) { continue }
    $blok = Tekst-Bloku-Zasad $n $tresci[$n] $nl
    $nastepny = $null
    foreach ($m in @($nazwy | Select-Object -Skip ($k + 1))) { if ($f.Bloki.Contains($m)) { $nastepny = $f.Bloki[$m]; break } }
    $poprzedni = $null
    foreach ($m in @($nazwy | Select-Object -First $k)) { if ($f.Bloki.Contains($m)) { $poprzedni = $f.Bloki[$m] } }
    $kier = $tekst.IndexOf((Start-Kierownika-Zasad), [System.StringComparison]::Ordinal)
    if ($nastepny) {
      $tekst = $tekst.Substring(0, $nastepny.Od) + $blok + $nl + $nl + $tekst.Substring($nastepny.Od)
    } elseif ($poprzedni) {
      $tekst = $tekst.Substring(0, $poprzedni.Do) + $nl + $nl + $blok + $tekst.Substring($poprzedni.Do)
    } elseif ($kier -ge 0) {
      $tekst = $tekst.Substring(0, $kier) + $blok + $nl + $nl + $tekst.Substring($kier)
    } elseif ($tekst.Trim().Length -eq 0) {
      $tekst = $blok + $nl
    } else {
      $tekst = $tekst.TrimEnd("`r", "`n") + $nl + $nl + $blok + $nl
    }
    $f = Znajdz-Bloki-Zasad $tekst
  }
  return $tekst
}

# Co Zloz-Plik-Zasad zmieni w tym tekscie - krotkie opisy do meldunku (pusta lista = nic).
function Roznice-Zasad([string]$stary, $tresci, [string[]]$zdejmij = @()) {
  if ($null -eq $stary) { $stary = "" }
  if ($null -eq $tresci) { $tresci = [ordered]@{} }
  $nl = "`r`n"
  if (-not $stary.Contains("`r`n") -and $stary.Contains("`n")) { $nl = "`n" }
  $f = Znajdz-Bloki-Zasad $stary
  if ($f.Blad) { return @("zle znaczniki: $($f.Blad)") }
  $opisy = @()
  if ($f.Bloki.Contains("stary")) {
    $na = @(Bloki-Zasad | Where-Object { $tresci.Contains($_) -and -not $f.Bloki.Contains($_) })
    if ($na.Count -gt 0) { $opisy += "stary wspolny blok zamieniony na: " + ($na -join " + ") }
    else { $opisy += "stary wspolny blok zdjety (moduly lore i wiedza wylaczone)" }
  }
  foreach ($n in (Bloki-Zasad)) {
    $jest = $f.Bloki.Contains($n)
    if ($tresci.Contains($n)) {
      if (-not $jest) {
        if (-not $f.Bloki.Contains("stary")) { $opisy += "brakowalo bloku $n" }
      } else {
        $z = $f.Bloki[$n]
        if ($stary.Substring($z.Od, $z.Do - $z.Od) -cne (Tekst-Bloku-Zasad $n $tresci[$n] $nl)) { $opisy += "nieaktualny blok $n" }
      }
    } elseif ($jest -and ($zdejmij -contains $n)) {
      $opisy += "zdjety blok $n"
    }
  }
  return $opisy
}
