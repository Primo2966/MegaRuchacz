# narzedzia\koszt\warstwy.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz BUDOWA
# w jego naglowku). Pomiar warstw pamieci w CLAUDE.md: blok zasad, bloki nazwane,
# czesc stala i biezaca sekcji "## Co wiem" (Zmierz-Warstwy), wpisy z datami
# (Czytaj-Wpisy) i pozycje rachunku (Pozycja, Policz-Udzialy, Ile-Wpisow).
# Skad wolane: Zmierz-Warstwy - etap Etap-Pomiar (pomiar.ps1); pozycje - etap
# Etap-Kubelki (kubelki.ps1) i tryb -Rozbicie. Wczytuje go koszt-pamieci.ps1 kropka
# przy starcie - same definicje.

# --- warstwy -----------------------------------------------------------------

function Granice-Sekcji($linie, $start, $koniec) {
  # zwraca @(poczatek, koniec) - koniec wylacznie; @(-1, -1) gdy naglowka nie ma
  $i = -1
  for ($k = 0; $k -lt $linie.Count; $k++) {
    if ($linie[$k] -match $start) { $i = $k; break }
  }
  if ($i -lt 0) { return @(-1, -1) }
  $j = $linie.Count
  for ($k = $i + 1; $k -lt $linie.Count; $k++) {
    if ($linie[$k] -match $koniec) { $j = $k; break }
  }
  return @($i, $j)
}

function Linie-Zakresu($linie, $od, $doo) {
  if ($od -lt 0 -or $doo -le $od) { return @() }
  return @($linie[$od..($doo - 1)])
}

function Miara($linie) {
  $l = @($linie)
  $znaki = ($l -join "`n").Length
  return [pscustomobject]@{
    Linie  = $l.Count
    Znaki  = $znaki
    Tokeny = [int][math]::Ceiling($znaki / $ZnakiNaToken)
  }
}

# --- pozycje rachunku --------------------------------------------------------

function Pozycja($nazwa, $znaki, $skad, $rada, $krotka = "", $uwaga = "") {
  # Jedna skladowa rachunku: co to jest, ile wazy, skad pochodzi i co zrobic,
  # gdyby to ona okazala sie najdrozsza. $krotka to ta sama pozycja nazwana
  # w dwoch slowach - do rozbicia pokazywanego raz dziennie przy starcie sesji,
  # gdzie kazdy znak leci do kontekstu modelu i placi sie za niego.
  # $uwaga to ogon tego samego wiersza w rozbiciu: czy ta pozycja wygasa. Bez
  # tego nie widac, ktora warstwa pamieci jest tymczasowa, a ktora rosnie na
  # zawsze - a to jest pierwsza rzecz, ktora trzeba wiedziec przy skracaniu.
  if (-not $krotka) { $krotka = $nazwa }
  return [pscustomobject]@{
    Nazwa   = $nazwa
    Krotka  = $krotka
    Znaki   = [int]$znaki
    Tokeny  = [int](Tokeny $znaki)
    Skad    = $skad
    Rada    = $rada
    Uwaga   = $uwaga
    Procent = 0
  }
}

function Ile-Wpisow($n) {
  # polska odmiana - "2 wpisy", ale "5 wpisow"; ten sam wzorzec, co Ile-Wywolan
  # w narzedzia\straznik-zasad.ps1
  $reszta = $n % 10
  $setka  = $n % 100
  if ($n -eq 1) { return "1 wpis" }
  if (($reszta -ge 2) -and ($reszta -le 4) -and (($setka -lt 12) -or ($setka -gt 14))) { return "$n wpisy" }
  return "$n wpisow"
}

function Policz-Udzialy($pozycje) {
  $razem = 0
  foreach ($p in @($pozycje)) { $razem += $p.Tokeny }
  foreach ($p in @($pozycje)) {
    if ($razem -gt 0) { $p.Procent = [int][math]::Round(100.0 * $p.Tokeny / $razem) }
  }
  return $razem
}

function Czytaj-Wpisy($linie) {
  $dzis = [datetime]::Today
  $wpisy = @()
  foreach ($l in @($linie)) {
    $m = [regex]::Match($l, '^\s*-\s*\[(\d{4}-\d{2}-\d{2})\]\s*(.*)$')
    if (-not $m.Success) { continue }
    $data = $null
    try {
      $data = [datetime]::ParseExact($m.Groups[1].Value, 'yyyy-MM-dd',
                                     [Globalization.CultureInfo]::InvariantCulture)
    } catch { $data = $null }
    $wiek = 0
    if ($data) { $wiek = ($dzis - $data).Days }
    $wpisy += [pscustomobject]@{
      Data  = $m.Groups[1].Value
      Tresc = $m.Groups[2].Value.Trim()
      Wiek  = $wiek
      Stary = (($data -ne $null) -and ($wiek -gt $DniWaznosci))
    }
  }
  return $wpisy
}

function Zmierz-Warstwy($plik) {
  $pusta = Miara @()
  $wynik = [pscustomobject]@{
    Jest     = $false
    Blad     = $null
    MaSekcje = $false
    Blok     = $pusta
    Stala    = $pusta
    Biezaca  = $pusta
    Wpisy    = @()
    # Same teksty podwarstw - czyta je wylacznie tryb -Warstwy (podglad w oknie
    # nadzorcy), zeby okno nie wycinalo sekcji drugi raz, po swojemu.
    BlokTekst    = ""
    StalaTekst   = ""
    BiezacaTekst = ""
    # Bloki nazwane <!-- MegaRuchacz:<nazwa>:start/koniec --> poza blokiem
    # glownym (np. zasady kierownika z instaluj-globalnie.ps1). Kazdy to osobna
    # pozycja rachunku za start sesji - wchodzi do modelu razem z calym plikiem.
    Bloki    = @()
    # Nazwy blokow ze znacznikiem startu bez znacznika konca - takiego bloku nie
    # umiemy odciac, wiec rachunek mowi o nim wprost zamiast go przemilczec
    BlokiBezKonca = @()
  }
  if (-not (Test-Path -LiteralPath $plik)) { return $wynik }

  try { $tekst = Czytaj $plik }
  catch {
    # plik JEST, tylko nie da sie go przeczytac - to co innego niz jego brak,
    # a raport, ktory powie "nie ma pliku", po prostu sklamie
    $wynik.Blad = "plik $plik jest, ale nie da sie go odczytac ($($_.Exception.Message))"
    return $wynik
  }

  $wynik.Jest = $true
  $tekst = $tekst -replace "`r`n", "`n"

  # blok zasad wycinamy z tekstu od razu: ma wlasny rachunek, a gdyby zostal,
  # doliczylby sie drugi raz do sekcji, w ktorej akurat siedzi
  $i = $tekst.IndexOf($ZnacznikStart, [System.StringComparison]::Ordinal)
  $j = $tekst.IndexOf($ZnacznikKoniec, [System.StringComparison]::Ordinal)
  if ($i -ge 0 -and $j -gt $i) {
    $dlugosc = $j + $ZnacznikKoniec.Length - $i
    $wynik.BlokTekst = $tekst.Substring($i, $dlugosc)
    $wynik.Blok = Miara @($wynik.BlokTekst -split "`n")
    $tekst = $tekst.Remove($i, $dlugosc)
  }

  # Bloki nazwane - z tego samego powodu wycinane PRZED podzialem na sekcje:
  # blok kierownika stoi zaraz za "Co wiem" i jego znacznik startu doliczal sie
  # dotad do warstwy stalej. Szukamy ich dopiero po wycieciu bloku glownego, wiec
  # blok zagniezdzony w glownym nie policzy sie drugi raz.
  $bloki = @()
  $trafienia = @([regex]::Matches($tekst, '(?s)<!-- MegaRuchacz:(?<n>[A-Za-z0-9_-]+):start -->.*?<!-- MegaRuchacz:\k<n>:koniec -->'))
  foreach ($m in $trafienia) {
    $bloki += [pscustomobject]@{
      Nazwa = $m.Groups['n'].Value
      Znaki = $m.Value.Length
      Tekst = $m.Value
    }
  }
  # od konca, zeby wczesniejsze pozycje w tekscie sie nie przesunely
  for ($k = $trafienia.Count - 1; $k -ge 0; $k--) {
    $tekst = $tekst.Remove($trafienia[$k].Index, $trafienia[$k].Length)
  }
  $wynik.Bloki = $bloki
  $wynik.BlokiBezKonca = @([regex]::Matches($tekst, '<!-- MegaRuchacz:(?<n>[A-Za-z0-9_-]+):start -->') |
                           ForEach-Object { $_.Groups['n'].Value })

  $linie = @($tekst -split "`n")

  # "## Co wiem" konczy sie na najblizszym naglowku pierwszego lub drugiego poziomu;
  # "###" do wzorca nie pasuje, bo po dwoch krzyzykach musi stac bialy znak
  $g = @(Granice-Sekcji $linie '^##\s+Co\s+wiem' '^#{1,2}\s')
  if ($g[0] -lt 0) { return $wynik }
  $wynik.MaSekcje = $true
  $coWiem = @(Linie-Zakresu $linie $g[0] $g[1])

  # "Bie" zamiast pelnego slowa: ten plik jest bez polskich znakow, a naglowek
  # w CLAUDE.md bywa pisany i z ogonkami, i bez
  $gb = @(Granice-Sekcji $coWiem '^###\s+Bie' '^#{1,3}\s')
  if ($gb[0] -lt 0) {
    $wynik.Stala = Miara $coWiem
    $wynik.StalaTekst = ($coWiem -join "`n")
    return $wynik
  }

  $biezace = @(Linie-Zakresu $coWiem $gb[0] $gb[1])
  $stala = @(Linie-Zakresu $coWiem 0 $gb[0]) + @(Linie-Zakresu $coWiem $gb[1] $coWiem.Count)
  $wynik.Stala   = Miara $stala
  $wynik.Biezaca = Miara $biezace
  $wynik.StalaTekst   = ($stala -join "`n")
  $wynik.BiezacaTekst = ($biezace -join "`n")
  $wynik.Wpisy   = @(Czytaj-Wpisy $biezace)
  return $wynik
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["warstwy"] = $true
