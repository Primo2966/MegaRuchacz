# Audyt sufitow pamieci i zasad. Odpowiada na dwa pytania, ktore nie moga zostac
# bez odpowiedzi: CZY COS JEST UCINANE PO CICHU i CZY KOSZT ROSNIE NIEZAUWAZENIE.
# Poza tym rozdziela trzy rachunki, ktore latwo ze soba pomylic: ile tokenow
# dokleja sie do KAZDEJ wiadomosci (przypomnienie z hooka UserPromptSubmit),
# ile wchodzi RAZ, przy starcie sesji (blok zasad + warstwa stala i biezaca),
# a ile kosztuje RAZ NA DOBE cykl wiedzy - czyli jedyne miejsce w tym narzedziu,
# w ktorym naprawde wola sie model i wydaje tokeny uzytkownika. Dwa pierwsze to
# TEKST doklejany do rozmowy, trzeci to PRAWDZIWE WYWOLANIE - i wlasnie dlatego
# nie sumuja sie w jedna liczbe.
# Sam ten skrypt modelu nie wola: czysta arytmetyka na plikach.
#
# CALY RACHUNEK NA ZADANIE - jedna komenda do wklejenia w terminal:
#   powershell -ExecutionPolicy Bypass -File C:\dev\claude-worker\narzedzia\koszt-pamieci.ps1
# Wypisuje, ktora pamiec ile kosztuje przy kazdej wiadomosci i przy starcie
# sesji, pozycja po pozycji. Ta sama komenda jest na koncu kazdego raportu.
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File narzedzia\koszt-pamieci.ps1
#     -KatalogDomowy <kat>   podmiana bazy sciezek (domyslnie katalog domowy; testy)
#     -Zrodlo <kat>          katalog narzedzia (domyslnie katalog nad tym skryptem)
#     -Projekt <kat>         projekt z wdrozonym Codeksem: mierzymy wtedy ladunki
#                            hookow, ktore tam naprawde leza, a nie same szablony
#     -TylkoSufity           SAME sufity: kazda para (ladunek, limit) w jednej linii,
#                            kod 1 gdy cokolwiek wystaje - do odpalenia po kazdej
#                            zmianie zasad, bez czekania na reszte raportu
#     -Zwiezle               DOKLADNIE JEDNA linia do pokazania przy starcie sesji
#     -Zwykly                bez kolorow (do zapisu wydruku w pliku)
#     -ZalozZadanie          codzienny raport o 08:15 do <dom>\.claude\wiedza\koszt-ostatni.txt
#     -UsunZadanie           kasuje to zadanie
#
# Kod wyjscia: 0 gdy nic nie jest ucinane i zaden prog alarmowy nie jest
# przekroczony, 1 gdy cokolwiek z tego zachodzi - zeby dalo sie to podpiac jako
# sprawdzenie.
#
# WARTOSCI SUFITOW CZYTAMY Z PLIKOW, KTORE JE USTALAJA (straznik, hooks.json,
# facts.py, index.py). Wpisane tu na sztywno zaczelyby klamac przy pierwszej
# zmianie tamtych plikow - a audyt, ktory klamie, jest gorszy niz jego brak.
#
# Skrypt TYLKO CZYTA CLAUDE.md - nigdy do niego nie pisze. Brak pliku, brak sekcji,
# brak katalogu wiedzy czy bazy Lore to nie awaria, tylko mniej danych w raporcie.

param(
  [string]$KatalogDomowy = $HOME,
  [string]$Zrodlo = "",
  [string]$Projekt = "",
  [switch]$TylkoSufity,
  [switch]$Zwiezle,
  [switch]$Zwykly,
  [switch]$ZalozZadanie,
  [switch]$UsunZadanie
)

$ZnacznikStart  = "<!-- MegaRuchacz:start -->"
$ZnacznikKoniec = "<!-- MegaRuchacz:koniec -->"

$NazwaZadania   = "LoreKoszt"
$GodzinaZadania = "08:15"

# ~3 znaki na token to przyblizenie dla polszczyzny - patrz adnotacja w raporcie
$ZnakiNaToken   = 3
$DniWaznosci    = 14
# pomiar kosztu cyklu starszy niz tyle dni znaczy, ze cykl przestal chodzic -
# ta sama liczba, co w straznik-zasad.ps1 przy meldunku o cyklu
$DniCyklStary   = 2
$ProgStalej     = 8000
$ProgBiezacych  = 15
$ProgPoczekalni = 10
# powyzej tylu procent sufitu wiersz jest zolty - zapas konczy sie wczesniej,
# niz czlowiek zdazy zauwazyc
$ProgCiasno     = 80
# wzrost kosztu od poprzedniego pomiaru, ktory ma byc widoczny jako ostrzezenie
$ProgWzrostu    = 20

# --- progi alarmowe ----------------------------------------------------------
# TO SA NASZE LICZBY DO ZMIANY, NIE PRAWA NATURY. Zadna z nich nie pochodzi
# z dokumentacji Claude Code ani Codeksa - dobralismy je tak, zeby alarm odzywal
# sie rzadko i zawsze wtedy, gdy jest co zrobic. Kazda zmienia sie tutaj, jedna
# linijka, i nic poza tym plikiem o nich nie wie.
#
# $AlarmNaWiadomosc - przypomnienie doklejane do KAZDEJ wiadomosci. Dzisiejsze
#   ma okolo 200 tokenow, wiec prog to mniej wiecej poltora raza tyle: zmiesci
#   sie dopisane zdanie, nie zmiesci sie rozrost zasad. Ta pozycja mnozy sie
#   przez kazde zdanie uzytkownika, wiec ma najciasniejszy prog.
# $AlarmNaSesje - wszystko, co wchodzi RAZ, przy starcie sesji. Dzisiaj okolo
#   3 000 tokenow; 5 000 to zapas na rozrost wiedzy o uzytkowniku, ale juz nie
#   na drugie tyle zasad.
# $AlarmUdzialu - jedna pozycja zjadajaca wiecej niz tyle procent swojego
#   rachunku. Nie chodzi o sam rozmiar, tylko o to, ze skracanie czegokolwiek
#   innego nic nie da. Dzis najdrozsza pozycja (warstwa stala) ma 64%, wiec prog
#   stoi nad tym, a nie pod: alarm, ktory swieci sie od pierwszego dnia i tak
#   jak swiecil, przestaje byc alarmem.
# $MinPozycjiDoUdzialu - ponizej tylu pozycji w rachunku udzial nic nie mowi
#   (przy dwoch pozycjach jedna prawie zawsze ma ponad polowe), wiec alarm
#   o udziale w ogole sie nie odzywa.
# $AlarmCyklu - koszt cyklu wiedzy za JEDNA dobe. Tu skad wzielo sie 120 000,
#   bo prog wpisany bez uzasadnienia dwa razy juz po cichu psul dzialanie:
#     - jeden przebieg wylawiania bierze najwyzej MAX_INPUT_CHARS = 60 000 znakow
#       materialu (lore\lore\facts.py), czyli ~20 000 tokenow wejscia; z poleceniem
#       i odpowiedzia modelu liczymy z zapasem ~24 000 tokenow na przebieg,
#     - na JEDNO podejscie cykl bierze najwyzej $MaxNadrabiania = 5 przebiegow
#       (narzedzia\cykl-dzienny.ps1), czyli 5 * 24 000 = ~120 000 tokenow.
#   Tyle wolno kosztowac pelnemu podejsciu i zwyklemu, nawet gestemu dniu pracy.
#   Powyzej znaczy, ze cykl wracal po kolejne raty ($MaxProb = 5 podejsc na dobe,
#   gorna granica to ~600 000 tokenow) - czyli goni zaleglosc, ktorej nie dogania,
#   i to jest ten moment, w ktorym uzytkownik ma sie o tym dowiedziec.
#   Gdyby ktoras z tych trzech liczb sie zmienila, ten prog trzeba przeliczyc.
$AlarmNaWiadomosc    = 300
$AlarmNaSesje        = 5000
$AlarmUdzialu        = 70
$MinPozycjiDoUdzialu = 3
$AlarmCyklu          = 120000

# Przedrostek ladunku hooka startowego Codeksa - MUSI brzmiec tak samo jak
# w straznik-zasad.ps1 (Zbuduj-Sesje-Codex) i w wdroz.ps1, bo inaczej liczymy
# dlugosc czegos, czego nikt nie wysyla.
$PrzedrostekZasad = "Zasady pracy w tym projekcie (tryb MegaRuchacz). Stosuj je przez cala sesje:`n`n"

$script:Raport = @()

function Linia($tekst, $kolor = $null) {
  $script:Raport += [pscustomobject]@{ Tekst = $tekst; Kolor = $kolor }
}

# --- liczby i teksty ---------------------------------------------------------

function Liczba($n) {
  # separator tysiecy na sztywno spacja: N0 idzie za ustawieniami regionalnymi,
  # a te potrafia wstawic znak, ktory w konsoli wyglada jak smiec
  return ([long]$n).ToString("#,0", [Globalization.CultureInfo]::InvariantCulture).Replace(",", " ")
}

function Tokeny($znaki) {
  if ($znaki -eq $null) { return $null }
  return [int][math]::Ceiling([double]$znaki / $ZnakiNaToken)
}

function Rozmiar($bajty) {
  if ($bajty -lt 1024)    { return "$bajty B" }
  if ($bajty -lt 1048576) { return "$([math]::Round($bajty / 1024, 1)) KB" }
  return "$([math]::Round($bajty / 1048576, 1)) MB"
}

function Skroc($tekst, $ile) {
  if (-not $tekst) { return "" }
  if ($tekst.Length -le $ile) { return $tekst }
  return $tekst.Substring(0, $ile - 3) + "..."
}

# --- czytanie pliku ----------------------------------------------------------

function Czytaj($sciezka) {
  # UTF-8 bez rzucania bledem: zepsuty znak w cudzych zapiskach ma nie wywalic
  # raportu, bo to i tak konczy sie na policzeniu znakow
  return [System.IO.File]::ReadAllText($sciezka, (New-Object System.Text.UTF8Encoding($false)))
}

function Czytaj-Cicho($sciezka) {
  if (-not $sciezka) { return $null }
  if (-not (Test-Path -LiteralPath $sciezka)) { return $null }
  try { return Czytaj $sciezka } catch { return $null }
}

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

function Pozycja($nazwa, $znaki, $skad, $rada) {
  # Jedna skladowa rachunku: co to jest, ile wazy, skad pochodzi i co zrobic,
  # gdyby to ona okazala sie najdrozsza.
  return [pscustomobject]@{
    Nazwa   = $nazwa
    Znaki   = [int]$znaki
    Tokeny  = [int](Tokeny $znaki)
    Skad    = $skad
    Rada    = $rada
    Procent = 0
  }
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
    MaSekcje = $false
    Blok     = $pusta
    Stala    = $pusta
    Biezaca  = $pusta
    Wpisy    = @()
  }
  if (-not (Test-Path -LiteralPath $plik)) { return $wynik }

  try { $tekst = Czytaj $plik }
  catch { return $wynik }

  $wynik.Jest = $true
  $tekst = $tekst -replace "`r`n", "`n"

  # blok zasad wycinamy z tekstu od razu: ma wlasny rachunek, a gdyby zostal,
  # doliczylby sie drugi raz do sekcji, w ktorej akurat siedzi
  $i = $tekst.IndexOf($ZnacznikStart, [System.StringComparison]::Ordinal)
  $j = $tekst.IndexOf($ZnacznikKoniec, [System.StringComparison]::Ordinal)
  if ($i -ge 0 -and $j -gt $i) {
    $dlugosc = $j + $ZnacznikKoniec.Length - $i
    $wynik.Blok = Miara @($tekst.Substring($i, $dlugosc) -split "`n")
    $tekst = $tekst.Remove($i, $dlugosc)
  }

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
    return $wynik
  }

  $biezace = @(Linie-Zakresu $coWiem $gb[0] $gb[1])
  $stala = @(Linie-Zakresu $coWiem 0 $gb[0]) + @(Linie-Zakresu $coWiem $gb[1] $coWiem.Count)
  $wynik.Stala   = Miara $stala
  $wynik.Biezaca = Miara $biezace
  $wynik.Wpisy   = @(Czytaj-Wpisy $biezace)
  return $wynik
}

# --- sufity ------------------------------------------------------------------

function Limit-Z-Pliku($plik, $wzorzec) {
  # jedna liczba wyluskana ze zrodla, ktore ja naprawde ustala; $null, gdy pliku
  # nie ma albo wzorzec nie pasuje - wtedy raport mowi "nie znam sufitu" zamiast
  # podawac wartosc z pamieci
  $tekst = Czytaj-Cicho $plik
  if (-not $tekst) { return $null }
  $m = [regex]::Match($tekst, $wzorzec)
  if (-not $m.Success) { return $null }
  $cyfry = ($m.Groups[1].Value -replace '[^\d]', '')
  if (-not $cyfry) { return $null }
  return [int]$cyfry
}

function Limit-Hooka($plikHookow, $fragmentPolecenia) {
  # additionalContextLimit hooka rozpoznanego po tym, jaki plik wczytuje
  $tekst = Czytaj-Cicho $plikHookow
  if (-not $tekst) { return $null }
  try { $j = $tekst | ConvertFrom-Json } catch { return $null }
  if (-not $j.hooks) { return $null }
  foreach ($zdarzenie in $j.hooks.PSObject.Properties) {
    foreach ($grupa in @($zdarzenie.Value)) {
      foreach ($h in @($grupa.hooks)) {
        if (-not $h) { continue }
        if ($h.PSObject.Properties.Name -notcontains "additionalContextLimit") { continue }
        $polecenie = "" + $h.command + " " + $h.commandWindows
        if ($polecenie -like "*$fragmentPolecenia*") { return [int]$h.additionalContextLimit }
      }
    }
  }
  return $null
}

function Ladunek-Hooka($plikJson) {
  # tresc, ktora hook naprawde wysyla (additionalContext z gotowego ladunku)
  $tekst = Czytaj-Cicho $plikJson
  if (-not $tekst) { return $null }
  try { $j = $tekst | ConvertFrom-Json } catch { return $null }
  if (-not $j.hookSpecificOutput) { return $null }
  $tresc = [string]$j.hookSpecificOutput.additionalContext
  if (-not $tresc) { return $null }
  return $tresc
}

function Znaki-W-Bajtach($tresc, $bajty) {
  # ile ZNAKOW miesci sie w podanej liczbie bajtow UTF-8 - sufit AGENTS.md jest
  # w bajtach, a naglowka szukamy w tekscie
  $enc = New-Object System.Text.UTF8Encoding($false)
  if ($enc.GetByteCount($tresc) -le $bajty) { return $tresc.Length }
  $lo = 0
  $hi = $tresc.Length
  while ($lo -lt $hi) {
    $sr = [int][math]::Floor(($lo + $hi + 1) / 2)
    if ($enc.GetByteCount($tresc.Substring(0, $sr)) -le $bajty) { $lo = $sr } else { $hi = $sr - 1 }
  }
  return $lo
}

function Pierwszy-Utracony-Naglowek($tresc, $limit, $jednostka) {
  # od ktorego naglowka zaczyna sie czesc, ktora przepada - zeby bylo widac,
  # CO konkretnie ginie, a nie tylko ile znakow
  if (-not $tresc) { return $null }
  $ciecie = $limit
  if ($jednostka -eq "bajtow") { $ciecie = Znaki-W-Bajtach $tresc $limit }
  if ($ciecie -ge $tresc.Length) { return $null }
  $m = [regex]::Match($tresc.Substring($ciecie), '(?m)^#{1,6}\s+.+$')
  if (-not $m.Success) { return $null }
  return $m.Value.Trim()
}

function Sufit($pola) {
  # Pola obowiazkowe: Nazwa, Krotka, Teraz, Limit, Jednostka, Czyj, SkadLimitu,
  # Plik, Skutek, Ucina. Nieobowiazkowe: Tresc, Uwaga, Informacyjny.
  # Teraz albo Limit rowne $null znacza "nie zmierzone" - i tak to wypisujemy.
  $s = [pscustomobject]$pola
  foreach ($k in @("Nazwa","Krotka","Teraz","Limit","Jednostka","Czyj","SkadLimitu",
                   "Plik","Skutek","Ucina","Tresc","Uwaga","Informacyjny")) {
    if ($s.PSObject.Properties.Name -notcontains $k) {
      $s | Add-Member -NotePropertyName $k -NotePropertyValue $null
    }
  }
  $zmierzony = (($s.Teraz -ne $null) -and ($s.Limit -ne $null) -and ([int]$s.Limit -gt 0))
  $s | Add-Member -NotePropertyName "Zmierzony"    -NotePropertyValue $zmierzony
  $s | Add-Member -NotePropertyName "Procent"      -NotePropertyValue 0
  $s | Add-Member -NotePropertyName "Zapas"        -NotePropertyValue 0
  $s | Add-Member -NotePropertyName "Przekroczony" -NotePropertyValue $false
  $s | Add-Member -NotePropertyName "Strata"       -NotePropertyValue 0
  $s | Add-Member -NotePropertyName "Naglowek"     -NotePropertyValue $null
  if ($zmierzony) {
    $s.Procent = [int][math]::Round(100.0 * [double]$s.Teraz / [double]$s.Limit)
    $s.Zapas   = 100 - $s.Procent
    if ($s.Zapas -lt 0) { $s.Zapas = 0 }
    if ([long]$s.Teraz -gt [long]$s.Limit) {
      $s.Przekroczony = $true
      $s.Strata       = [long]$s.Teraz - [long]$s.Limit
      $s.Naglowek     = Pierwszy-Utracony-Naglowek $s.Tresc $s.Limit $s.Jednostka
    }
  }
  return $s
}

function Powod-Braku($teraz, $limit, $coMierzone, $skadLimitu) {
  $b = @()
  if ($teraz -eq $null) { $b += $coMierzone }
  if ($limit -eq $null) { $b += "nie umiem odczytac sufitu z $skadLimitu" }
  if ($b.Count -eq 0) { return $null }
  return ($b -join "; ")
}

function Sortuj-Sufity($lista) {
  # przekroczone i ciasne na GORZE - dolna czesc listy to ta, ktorej nikt nie czyta
  $klucze = @(
    @{ Expression = { if ($_.Informacyjny -or (-not $_.Zmierzony)) { 1 } else { 0 } } },
    @{ Expression = { if ($_.Zmierzony) { 0 - $_.Procent } else { 0 } } }
  )
  return @($lista | Sort-Object -Property $klucze)
}

# --- poprzedni pomiar --------------------------------------------------------

function Poprzedni-Pomiar($plik) {
  # dzienny raport zapisany przez zadanie z harmonogramu; najpierw szukamy linii
  # maszynowej, a dopiero potem - dla starszych plikow - linii RAZEM
  $tekst = Czytaj-Cicho $plik
  if (-not $tekst) { return $null }
  $m = [regex]::Match($tekst, '(?m)^\s*POMIAR\s+tokenow=(\d+)')
  if (-not $m.Success) {
    $m = [regex]::Match($tekst, '(?m)^\s*RAZEM.*?~\s*([\d ]+)\s*tokenow')
  }
  if (-not $m.Success) { return $null }
  $cyfry = ($m.Groups[1].Value -replace '[^\d]', '')
  if (-not $cyfry) { return $null }
  $data = $null
  try { $data = (Get-Item -LiteralPath $plik).LastWriteTime } catch { $data = $null }
  return [pscustomobject]@{ Tokeny = [int]$cyfry; Data = $data }
}

# --- koszt cyklu wiedzy ------------------------------------------------------
# Cykl dzienny (narzedzia\cykl-dzienny.ps1) wola model, zeby wylowic fakty
# z wczorajszych rozmow. To JEDYNE miejsce w calym narzedziu, w ktorym naprawde
# wydaja sie tokeny uzytkownika - reszta tego raportu to tekst doklejany do
# rozmowy, a nie wywolanie. Cykl zostawia po sobie plik "klucz: wartosc", w tym
# samym formacie co pozostale pliki stanu, z liczbami za dzis i za dzien
# poprzedni (klucze z przedrostkiem "poprzedni.").
#
# Braku pliku NIE traktujemy jak awarii: znaczy on tyle, ze cykl ani razu
# jeszcze nie policzyl kosztu - i tak wlasnie ma to byc napisane w raporcie.

function Klucze-Z-Tekstu($raw) {
  $stan = @{}
  if (-not $raw) { return $stan }
  foreach ($l in ($raw -split '\r?\n')) {
    $m = [regex]::Match($l, '^\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*:\s*(.*?)\s*$')
    if ($m.Success) { $stan[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $stan
}

function Klucz-Tekst($stan, $klucz) {
  if (-not $stan) { return $null }
  if (-not $stan.ContainsKey($klucz)) { return $null }
  $v = ("" + $stan[$klucz]).Trim()
  if (-not $v) { return $null }
  return $v
}

function Klucz-Liczba($stan, $klucz) {
  # $null zamiast zera przy braku i przy smieciu: zero znaczyloby "nic nie
  # kosztowalo", a to zupelnie co innego niz "cykl tego nie podal"
  $v = Klucz-Tekst $stan $klucz
  if ($null -eq $v) { return $null }
  $cyfry = ($v -replace '[^\d]', '')
  if (-not $cyfry) { return $null }
  return [long]$cyfry
}

function Lub-Nieznane($n) {
  if ($null -eq $n) { return "nie wiadomo" }
  return (Liczba $n)
}

function Kiedy-Cykl($wiek) {
  if ($null -eq $wiek) { return "" }
  if ($wiek -eq 0) { return "dzis" }
  if ($wiek -eq 1) { return "wczoraj" }
  return "$wiek dni temu"
}

function Opis-Zrodla($zrodlo) {
  if ($zrodlo -eq "pomiar")   { return "Tokeny to POMIAR - liczby pochodza od samego narzedzia AI." }
  if ($zrodlo -eq "szacunek") { return "Tokeny to SZACUNEK - przeliczone ze znakow, nie zmierzone." }
  if (-not $zrodlo)           { return "Cykl nie powiedzial, czy to pomiar, czy szacunek - traktuj te liczbe ostroznie." }
  return "Zrodlo liczby tokenow podane przez cykl: $zrodlo."
}

function Dzien-Cyklu($stan, $przedrostek) {
  # Jeden dzien pracy cyklu. $null, gdy pod tym przedrostkiem nie ma nic
  # sensownego - tak poznajemy, ze poprzedniego dnia po prostu jeszcze nie bylo.
  $data      = Klucz-Tekst  $stan "${przedrostek}data"
  $wywolania = Klucz-Liczba $stan "${przedrostek}wywolania"
  $tokeny    = Klucz-Liczba $stan "${przedrostek}tokeny"
  if (($null -eq $data) -and ($null -eq $wywolania) -and ($null -eq $tokeny)) { return $null }
  $wiek = $null
  if ($data) {
    try {
      $d = [datetime]::ParseExact($data, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
      $wiek = ([datetime]::Today - $d).Days
    } catch { $wiek = $null }
  }
  return [pscustomobject]@{
    Data          = $data
    Wiek          = $wiek
    Narzedzie     = (Klucz-Tekst  $stan "${przedrostek}narzedzie")
    Wywolania     = $wywolania
    ZnakiWyslane  = (Klucz-Liczba $stan "${przedrostek}znaki_wyslane")
    ZnakiOdebrane = (Klucz-Liczba $stan "${przedrostek}znaki_odebrane")
    Tokeny        = $tokeny
    Zrodlo        = (Klucz-Tekst  $stan "${przedrostek}tokeny_zrodlo")
    Fakty         = (Klucz-Liczba $stan "${przedrostek}fakty")
  }
}

function Koszt-Cyklu($plik) {
  $tekst = Czytaj-Cicho $plik
  if ($null -eq $tekst) { return $null }
  $stan = Klucze-Z-Tekstu $tekst
  $dzis = Dzien-Cyklu $stan ""
  if ($null -eq $dzis) { return $null }
  $dzis | Add-Member -NotePropertyName "Poprzedni" -NotePropertyValue (Dzien-Cyklu $stan "poprzedni.")
  return $dzis
}

# --- baza Lore ---------------------------------------------------------------

# Odczyt jednej liczby z lore.db bez zadnych zaleznosci: winsqlite3.dll siedzi
# w System32 kazdego Windowsa 10/11. Otwieramy do zapisu (ale bez CREATE), bo baza
# chodzi w trybie WAL, a polaczenie tylko do odczytu potrafi sie o to wylozyc.
$KodSqlite = @'
using System;
using System.Runtime.InteropServices;
public static class MalySqlite {
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_open_v2", CallingConvention=CallingConvention.Cdecl)]
  static extern int Open(byte[] plik, out IntPtr db, int flagi, IntPtr vfs);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_busy_timeout", CallingConvention=CallingConvention.Cdecl)]
  static extern int Busy(IntPtr db, int ms);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_prepare_v2", CallingConvention=CallingConvention.Cdecl)]
  static extern int Prepare(IntPtr db, byte[] sql, int n, out IntPtr st, IntPtr ogon);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_step", CallingConvention=CallingConvention.Cdecl)]
  static extern int Step(IntPtr st);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_column_int64", CallingConvention=CallingConvention.Cdecl)]
  static extern long Kolumna(IntPtr st, int i);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_finalize", CallingConvention=CallingConvention.Cdecl)]
  static extern int Koniec(IntPtr st);
  [DllImport("winsqlite3.dll", EntryPoint="sqlite3_close_v2", CallingConvention=CallingConvention.Cdecl)]
  static extern int Zamknij(IntPtr db);

  public static long Licz(string plik, string sql) {
    IntPtr db = IntPtr.Zero;
    IntPtr st = IntPtr.Zero;
    int rc = Open(System.Text.Encoding.UTF8.GetBytes(plik + "\0"), out db, 0x00000002, IntPtr.Zero);
    if (rc != 0) { if (db != IntPtr.Zero) { Zamknij(db); } throw new Exception("otwarcie bazy, kod " + rc); }
    try {
      Busy(db, 3000);
      rc = Prepare(db, System.Text.Encoding.UTF8.GetBytes(sql + "\0"), -1, out st, IntPtr.Zero);
      if (rc != 0) { throw new Exception("zapytanie, kod " + rc); }
      long wynik = 0;
      if (Step(st) == 100) { wynik = Kolumna(st, 0); }   // 100 = SQLITE_ROW
      return wynik;
    } finally {
      if (st != IntPtr.Zero) { Koniec(st); }
      if (db != IntPtr.Zero) { Zamknij(db); }
    }
  }
}
'@

function Pytanie-Do-Lore($baza, $sql) {
  if (-not (Test-Path -LiteralPath $baza)) {
    return [pscustomobject]@{ Ok = $false; Ile = 0; Powod = "nie ma bazy Lore: $baza" }
  }
  try {
    if (-not ("MalySqlite" -as [type])) { Add-Type -TypeDefinition $KodSqlite -ErrorAction Stop }
    $ile = [MalySqlite]::Licz($baza, $sql)
    return [pscustomobject]@{ Ok = $true; Ile = [long]$ile; Powod = $null }
  } catch {
    return [pscustomobject]@{ Ok = $false; Ile = 0; Powod = "nie umiem odczytac $baza ($($_.Exception.Message))" }
  }
}

function Kolejka-Lore($baza, $znacznik) {
  # ile znakow wypowiedzi uzytkownika czeka na wyciagniecie faktow - to jest
  # wartosc mierzona przeciw MAX_INPUT_CHARS
  $od = ""
  $t = Czytaj-Cicho $znacznik
  if ($t) { $od = $t.Trim() }
  if (-not $od) { $od = ([datetime]::UtcNow.AddHours(-24)).ToString("yyyy-MM-ddTHH:mm:ss") }
  $od = $od -replace "'", ""
  $sql = "SELECT coalesce(sum(length(text)), 0) FROM chunks WHERE ts > '$od'" +
         " AND (role = 'user' OR role LIKE '%:user')"
  return Pytanie-Do-Lore $baza $sql
}

function Najdluzszy-Kawalek($baza) {
  return Pytanie-Do-Lore $baza "SELECT coalesce(max(length(text)), 0) FROM chunks"
}

# --- zadanie w harmonogramie -------------------------------------------------

function Zaloz-Zadanie($skrypt, $dom, $plikRaportu) {
  # katalog musi istniec wczesniej - Set-Content nie zaklada brakujacych katalogow
  $katalog = Split-Path -Parent $plikRaportu
  if (-not (Test-Path -LiteralPath $katalog)) {
    New-Item -ItemType Directory -Force -Path $katalog | Out-Null
    Write-Host "  zalozony katalog $katalog"
  }

  $s = $skrypt      -replace "'", "''"
  $d = $dom         -replace "'", "''"
  $r = $plikRaportu -replace "'", "''"
  # -Zwykly obowiazkowo: kolorowe linie ida przez Write-Host, a tego Set-Content
  # nie lapie - raport w pliku byloby wtedy bez ostrzezen, czyli klamalby
  $polecenie = "& '$s' -KatalogDomowy '$d' -Zwykly | Set-Content -LiteralPath '$r' -Encoding UTF8"
  # conhost --headless: raport leci raz dziennie i nikt nie chce mrugniecia konsoli
  $argumenty = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ""$polecenie"""

  # UWAGA - tak samo jak w instaluj-lore.ps1: zakladanie zadania przez obiekty
  # (New-ScheduledTaskPrincipal + -Principal) konczy sie "Odmowa dostepu"
  # u zwyklego uzytkownika. Ten sam zapis podany jako XML przechodzi. Dlatego XML.
  try {
    $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $start = (Get-Date -Format "yyyy-MM-dd") + "T" + $GodzinaZadania + ":00"
    $argXml = [System.Security.SecurityElement]::Escape($argumenty)
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>MegaRuchacz - dzienny raport o koszcie pamieci agenta</Description>
    <URI>\$NazwaZadania</URI>
  </RegistrationInfo>
  <Principals>
    <Principal id="Author">
      <UserId>$sid</UserId>
      <LogonType>InteractiveToken</LogonType>
    </Principal>
  </Principals>
  <Settings>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>$start</StartBoundary>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
      <Enabled>true</Enabled>
    </CalendarTrigger>
  </Triggers>
  <Actions Context="Author">
    <Exec>
      <Command>conhost.exe</Command>
      <Arguments>$argXml</Arguments>
    </Exec>
  </Actions>
</Task>
"@
    Register-ScheduledTask -TaskName $NazwaZadania -Xml $xml -Force -ErrorAction Stop | Out-Null
  } catch {
    Write-Host "BLAD  nie udalo sie zalozyc zadania: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
  }
  Write-Host "OK  zadanie $NazwaZadania - codziennie o $GodzinaZadania, raport do $plikRaportu"
  Write-Host "    po wylaczonym komputerze nadrobi przy najblizszym wlaczeniu"
  exit 0
}

function Usun-Zadanie {
  $jest = Get-ScheduledTask -TaskName $NazwaZadania -ErrorAction SilentlyContinue
  if (-not $jest) {
    Write-Host "--  nie ma zadania $NazwaZadania, nie ma czego usuwac"
    exit 0
  }
  try { Unregister-ScheduledTask -TaskName $NazwaZadania -Confirm:$false -ErrorAction Stop }
  catch {
    Write-Host "BLAD  nie udalo sie usunac zadania: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
  }
  Write-Host "OK  zadanie $NazwaZadania usuniete"
  exit 0
}

# --- przebieg ----------------------------------------------------------------

if (-not (Test-Path -LiteralPath $KatalogDomowy)) {
  Write-Error "Nie ma takiego katalogu domowego: $KatalogDomowy"
  exit 1
}
$KatalogDomowy = (Resolve-Path -LiteralPath $KatalogDomowy).Path

if (-not $Zrodlo) {
  $katSkryptu = $PSScriptRoot
  if ((-not $katSkryptu) -and $PSCommandPath) { $katSkryptu = Split-Path -Parent $PSCommandPath }
  if ($katSkryptu) { $Zrodlo = Split-Path -Parent $katSkryptu }
}

$katKlaudii   = Join-Path $KatalogDomowy ".claude"
$plikClaude   = Join-Path $katKlaudii "CLAUDE.md"
$katWiedzy    = Join-Path $katKlaudii "wiedza"
$plikKandydat = Join-Path $katWiedzy "kandydaci.md"
$plikOstatni  = Join-Path $katWiedzy "koszt-ostatni.txt"
$plikZnacznik = Join-Path $katWiedzy ".ostatnie-wyciaganie"
# koszt cyklu wiedzy - pisze go sam cykl po wylowieniu faktow; tego pliku moze
# nie byc i to NIE jest awaria, tylko "cykl jeszcze nie liczyl kosztu"
$plikCyklKoszt   = Join-Path $katWiedzy ".koszt-cyklu.txt"
$plikCyklOstatni = Join-Path $katWiedzy "cykl-ostatni.txt"
$bazaLore     = Join-Path $katKlaudii "lore.db"
$plikAgents   = Join-Path $KatalogDomowy ".codex\AGENTS.md"

if ($UsunZadanie)  { Usun-Zadanie }
if ($ZalozZadanie) { Zaloz-Zadanie $PSCommandPath $KatalogDomowy $plikOstatni }

# zrodla sufitow - kazdy limit czytamy z pliku, ktory go naprawde ustala
$plikStraznika = Join-Path $Zrodlo "narzedzia\straznik-zasad.ps1"
# Sufit rzadzi ten, ktory NAPRAWDE lezy w projekcie - szablon w repo mowi tylko,
# co instalator by tam wpisal. Gdy projekt jest podany i ma wlasny .codex\hooks.json,
# limity czytamy stamtad; inaczej zostaje szablon.
$plikHookow    = Join-Path $Zrodlo "szablony-codex\hooks.json"
$skadHookow    = "szablony-codex\hooks.json"
if ($Projekt) {
  $hookiProjektu = Join-Path $Projekt ".codex\hooks.json"
  if (Test-Path -LiteralPath $hookiProjektu) {
    $plikHookow = $hookiProjektu
    $skadHookow = $hookiProjektu
  }
}
$plikZasadWzor = Join-Path $Zrodlo "szablony-codex\zasady-kierownika.md"
$plikPrzypWzor = Join-Path $Zrodlo "szablony-codex\przypomnienie.json"
$plikFaktow    = Join-Path $Zrodlo "lore\lore\facts.py"
$plikIndeksu   = Join-Path $Zrodlo "lore\lore\index.py"
$plikSzukania  = Join-Path $Zrodlo "lore\lore\search.py"
$plikKopania   = Join-Path $Zrodlo "lore\lore\mining.py"

$w = Zmierz-Warstwy $plikClaude

# tylko do linii maszynowej POMIAR - rachunek za start sesji sklada sie nizej
# z pozycji, bo wchodzi do niego takze to, co nie lezy w CLAUDE.md
$razemZnakow  = $w.Blok.Znaki + $w.Stala.Znaki + $w.Biezaca.Znaki

# --- sufity: pomiary ---------------------------------------------------------

$limitAgents  = Limit-Z-Pliku $plikStraznika '(?m)^\s*\$LIMIT_AGENTS\s*=\s*(\d+)'
$limitZasad   = Limit-Hooka $plikHookow "zasady-sesja.json"
$limitPrzyp   = Limit-Hooka $plikHookow "przypomnienie.json"
$limitWejscia = Limit-Z-Pliku $plikFaktow  '(?m)^MAX_INPUT_CHARS\s*=\s*([\d_]+)'
$limitKawalka = Limit-Z-Pliku $plikIndeksu '(?m)^CHUNK_SIZE\s*=\s*([\d_]+)'

# AGENTS.md Codeksa - sufit jest w BAJTACH, bo tyle czyta Codex
$agentsTresc = Czytaj-Cicho $plikAgents
$agentsBajty = $null
if ($agentsTresc -ne $null) {
  try { $agentsBajty = [long](Get-Item -LiteralPath $plikAgents).Length } catch { $agentsBajty = $null }
}

# Zasady wysylane Codeksowi na starcie sesji. Gdy podano projekt i lezy w nim
# gotowy ladunek - mierzymy JEGO, bo to jest to, co naprawde leci. Bez projektu
# mierzymy szablon zlozony tak samo jak sklada go straznik: to wariant pelny,
# czyli ten, ktory dostaje projekt bez zasad w AGENTS.md.
$zasadyTresc = $null
$zasadySkad  = $null
$zasadyWdrozone = $false
if ($Projekt) {
  $p = Join-Path $Projekt ".megaruchacz\zasady-sesja.json"
  $t = Ladunek-Hooka $p
  if ($t) { $zasadyTresc = $t; $zasadySkad = $p; $zasadyWdrozone = $true }
}
if (-not $zasadyTresc) {
  $t = Czytaj-Cicho $plikZasadWzor
  if ($t) {
    $zasadyTresc = $PrzedrostekZasad + $t
    $zasadySkad  = "$plikZasadWzor (wariant pelny - tyle leci do projektu, ktory nie ma zasad w AGENTS.md)"
  }
}
$zasadyZnaki = $null
if ($zasadyTresc) { $zasadyZnaki = $zasadyTresc.Length }

# Przypomnienie doklejane w Codeksie do KAZDEJ wiadomosci uzytkownika
$przypTresc = $null
$przypSkad  = $null
if ($Projekt) {
  $p = Join-Path $Projekt ".megaruchacz\przypomnienie.json"
  $t = Ladunek-Hooka $p
  if ($t) { $przypTresc = $t; $przypSkad = $p }
}
if (-not $przypTresc) {
  $t = Ladunek-Hooka $plikPrzypWzor
  if ($t) { $przypTresc = $t; $przypSkad = $plikPrzypWzor }
}
$przypZnaki = $null
if ($przypTresc) { $przypZnaki = $przypTresc.Length }

# To samo przypomnienie po stronie Claude Code - inny plik, ten sam ladunek
# hooka UserPromptSubmit. Sufitu tu nie ma (Claude Code nie przycina wyjscia
# hooka), wiec nie jest to sufit, tylko pozycja w rachunku za wiadomosc.
$przypCcTresc = $null
$przypCcSkad  = $null
if ($Projekt) {
  $p = Join-Path $Projekt ".claude\orchestrator-reminder.json"
  $t = Ladunek-Hooka $p
  if ($t) { $przypCcTresc = $t; $przypCcSkad = $p }
}
if (-not $przypCcTresc) {
  $p = Join-Path $Zrodlo ".claude\orchestrator-reminder.json"
  $t = Ladunek-Hooka $p
  if ($t) { $przypCcTresc = $t; $przypCcSkad = $p }
}
$przypCcZnaki = $null
if ($przypCcTresc) { $przypCcZnaki = $przypCcTresc.Length }

# Zasady kierownika wstrzykiwane hookiem startowym po stronie Claude Code.
# Szablonu tu NIE mierzymy: szablon sam z siebie nikomu nic nie wysyla, wiec
# doliczony do rachunku podawalby koszt, ktorego nikt nie placi.
$zasadyCcTresc = $null
$zasadyCcSkad  = $null
if ($Projekt) {
  $p = Join-Path $Projekt ".claude\megaruchacz-sesja.json"
  $t = Ladunek-Hooka $p
  if ($t) { $zasadyCcTresc = $t; $zasadyCcSkad = $p }
}

$sufity = @()

$sufity += Sufit ([ordered]@{
  Nazwa      = "pamiec stala w CLAUDE.md (sekcja 'Co wiem')"
  Krotka     = "pamiec stala"
  Teraz      = $(if ($w.Jest) { $w.Stala.Znaki } else { $null })
  Limit      = $ProgStalej
  Jednostka  = "znakow"
  Czyj       = "NASZ - sami go sobie ustawilismy"
  SkadLimitu = "narzedzia\koszt-pamieci.ps1 (`$ProgStalej)"
  Plik       = $plikClaude
  Skutek     = "nic sie nie ucina: to prog ostrzegawczy, sygnal zeby przeniesc rzadziej potrzebna wiedze do plikow w wiedza\"
  Ucina      = $false
  Uwaga      = (Powod-Braku $(if ($w.Jest) { $w.Stala.Znaki } else { $null }) $ProgStalej "nie ma pliku $plikClaude" "tego skryptu")
})

$sufity += Sufit ([ordered]@{
  Nazwa      = "instrukcje dla Codeksa (~\.codex\AGENTS.md)"
  Krotka     = "instrukcje dla Codeksa"
  Teraz      = $agentsBajty
  Limit      = $limitAgents
  Jednostka  = "bajtow"
  Czyj       = "NARZUCONY przez Codeksa - tego nie podniesiemy, trzeba sie zmiescic"
  SkadLimitu = "narzedzia\straznik-zasad.ps1 (`$LIMIT_AGENTS)"
  Plik       = $plikAgents
  Skutek     = "UCINA PO CICHU: Codex czyta tylko poczatek pliku, koniec zasad nie dociera do niego wcale"
  Ucina      = $true
  Tresc      = $agentsTresc
  Uwaga      = (Powod-Braku $agentsBajty $limitAgents "nie ma pliku $plikAgents - Codeksa nie ma na tej maszynie, wiec ten sufit dzis nikogo nie dotyczy" "narzedzia\straznik-zasad.ps1")
})

$sufity += Sufit ([ordered]@{
  Nazwa      = "zasady kierownika wstrzykiwane Codeksowi przy starcie sesji"
  Krotka     = "zasady dla Codeksa"
  Teraz      = $zasadyZnaki
  Limit      = $limitZasad
  Jednostka  = "znakow"
  Czyj       = "NASZ - liczba wpisana w $skadHookow, do podniesienia jedna linijka"
  SkadLimitu = "$skadHookow (additionalContextLimit hooka SessionStart)"
  Plik       = $zasadySkad
  Skutek     = "UCINA PO CICHU: Codex dostaje tylko poczatek zasad, konca nikt mu nie pokaze i nikt go nie ostrzeze"
  Ucina      = $true
  Tresc      = $zasadyTresc
  Uwaga      = (Powod-Braku $zasadyZnaki $limitZasad "nie ma czego mierzyc: brak $plikZasadWzor" $skadHookow)
})

$sufity += Sufit ([ordered]@{
  Nazwa      = "przypomnienie doklejane w Codeksie do kazdej wiadomosci"
  Krotka     = "przypomnienie dla Codeksa"
  Teraz      = $przypZnaki
  Limit      = $limitPrzyp
  Jednostka  = "znakow"
  Czyj       = "NASZ - liczba wpisana w $skadHookow, do podniesienia jedna linijka"
  SkadLimitu = "$skadHookow (additionalContextLimit hooka UserPromptSubmit)"
  Plik       = $przypSkad
  Skutek     = "UCINA PO CICHU: koniec przypomnienia przepada przy kazdej wiadomosci"
  Ucina      = $true
  Tresc      = $przypTresc
  Uwaga      = (Powod-Braku $przypZnaki $limitPrzyp "nie ma czego mierzyc: brak $plikPrzypWzor" $skadHookow)
})

# Ladunki hookow Claude Code - mierzymy je tylko wtedy, gdy podano projekt, bo
# poza nim nie ma czego mierzyc. Sufitu dla nich w settings.json DZIS NIE MA:
# obowiazuje wtedy wartosc domyslna Claude Code, ktorej nie znamy - i raport ma
# to powiedziec wprost, a nie przemilczec.
if ($Projekt) {
  $plikUstawien = Join-Path $Projekt ".claude\settings.json"
  foreach ($paraCC in @(
      @{ nazwa = "zasady kierownika wstrzykiwane na starcie sesji Claude Code"
         krotka = "zasady dla Claude Code"; plik = ".claude\megaruchacz-sesja.json"
         zdarzenie = "SessionStart" },
      @{ nazwa = "przypomnienie doklejane w Claude Code do kazdej wiadomosci"
         krotka = "przypomnienie dla Claude Code"; plik = ".claude\orchestrator-reminder.json"
         zdarzenie = "UserPromptSubmit" })) {
    $plikCC = Join-Path $Projekt $paraCC.plik
    if (-not (Test-Path -LiteralPath $plikCC)) { continue }
    $trescCC = Ladunek-Hooka $plikCC
    $znakiCC = $null
    if ($trescCC) { $znakiCC = $trescCC.Length }
    $limitCC = Limit-Hooka $plikUstawien (Split-Path $paraCC.plik -Leaf)
    $sufity += Sufit ([ordered]@{
      Nazwa      = $paraCC.nazwa
      Krotka     = $paraCC.krotka
      Teraz      = $znakiCC
      Limit      = $limitCC
      Jednostka  = "znakow"
      Czyj       = "NARZUCONY przez Claude Code, dopoki nie wpiszemy wlasnego additionalContextLimit do settings.json"
      SkadLimitu = "$plikUstawien (additionalContextLimit hooka $($paraCC.zdarzenie))"
      Plik       = $plikCC
      Skutek     = "UCINA PO CICHU: koniec ladunku przepada, gdy przekroczy sufit narzedzia"
      Ucina      = $true
      Tresc      = $trescCC
      Uwaga      = (Powod-Braku $znakiCC $limitCC "nie da sie odczytac ladunku z $plikCC" `
                    "$plikUstawien - nie ma tam additionalContextLimit, wiec sufitem jest wartosc domyslna Claude Code")
    })
  }
}

# --- dwa rachunki: za wiadomosc i za start sesji ------------------------------
# To sa rozne pieniadze i dlatego nie sumuja sie w jedna liczbe. Pierwszy placi
# sie przy kazdym zdaniu uzytkownika, drugi raz, przy otwarciu sesji.
# Do rachunku wchodzi tylko to, co na TEJ maszynie naprawde leci - szablon,
# ktorego nikt nie wysyla, jest wymieniony w raporcie, ale nie jest doliczany.

$jestCodex = ($agentsTresc -ne $null)

$kubWiadomosc = @()
if ($przypCcZnaki -ne $null) {
  $kubWiadomosc += Pozycja "przypomnienie zasad (Claude Code)" $przypCcZnaki $przypCcSkad `
    "skroc tresc 'additionalContext' w tym pliku - kazde zdanie stad placi sie przy kazdej wiadomosci"
} elseif (($przypZnaki -ne $null) -and $jestCodex) {
  $kubWiadomosc += Pozycja "przypomnienie zasad (Codex)" $przypZnaki $przypSkad `
    "skroc tresc 'additionalContext' w tym pliku - kazde zdanie stad placi sie przy kazdej wiadomosci"
}
$tokWiadomosc = Policz-Udzialy $kubWiadomosc

$kubSesja = @()
if ($w.Blok.Znaki -gt 0) {
  $kubSesja += Pozycja "blok zasad MegaRuchacza w CLAUDE.md" $w.Blok.Znaki $plikClaude `
    "ten blok nalezy do narzedzia - skracaj go w zrodle i wgraj przez wdroz.ps1, nie recznie"
}
if ($w.Stala.Znaki -gt 0) {
  $kubSesja += Pozycja "warstwa STALA (Co wiem)" $w.Stala.Znaki $plikClaude `
    "przenies najdluzsze zestawienie do pliku w $katWiedzy i zostaw tu jedna linie odsylacza - warstwa referencyjna nie kosztuje nic"
}
if ($w.Biezaca.Znaki -gt 0) {
  $kubSesja += Pozycja "warstwa BIEZACA" $w.Biezaca.Znaki $plikClaude `
    "skasuj wpisy starsze niz $DniWaznosci dni albo przenies te trwale do warstwy stalej"
}
if ($zasadyCcTresc) {
  $kubSesja += Pozycja "zasady kierownika z hooka (Claude Code)" $zasadyCcTresc.Length $zasadyCcSkad `
    "to zasady projektu wstrzykiwane hookiem - skracaj je w CLAUDE.md narzedzia i wgraj przez wdroz.ps1"
} elseif ($zasadyWdrozone -and $zasadyTresc) {
  $kubSesja += Pozycja "zasady kierownika z hooka (Codex)" $zasadyTresc.Length $zasadySkad `
    "to zasady projektu wstrzykiwane hookiem - skracaj je w szablony-codex\zasady-kierownika.md i wgraj przez wdroz.ps1"
}
$tokSesja = Policz-Udzialy $kubSesja

# Trzeci rachunek: cykl wiedzy raz na dobe. NIE doliczamy go do zadnego z dwoch
# powyzej - to inne pieniadze. Tamte to tekst doklejany do rozmowy, ten to
# prawdziwe wywolanie modelu, a zsumowana liczba mowilaby, ze tyle kosztuje
# kazda sesja. $null znaczy "cykl jeszcze nie liczyl kosztu".
$cykl = Koszt-Cyklu $plikCyklKoszt

# --- wypisanie: tryb zwiezly (DOKLADNIE JEDNA LINIA) -------------------------

$ucinane = @(Sortuj-Sufity @($sufity | Where-Object { $_.Ucina -and $_.Przekroczony }))
$cosUcinane = ($ucinane.Count -gt 0)

$poprz      = Poprzedni-Pomiar $plikOstatni
$zmiana     = 0
$zmianaProc = 0
$skokKosztu = $false
if ($poprz -and $poprz.Tokeny -gt 0) {
  $zmiana     = $tokSesja - $poprz.Tokeny
  $zmianaProc = [int][math]::Round(100.0 * $zmiana / $poprz.Tokeny)
  if ($zmianaProc -gt $ProgWzrostu) { $skokKosztu = $true }
}

# --- alarmy ------------------------------------------------------------------
# Alarm mowi, CO zrobic i z ktorym plikiem - sama liczba nad progiem nikomu
# jeszcze niczego nie zalatwila. Kazdy alarm podnosi kod wyjscia.

function Najdrozsza($pozycje) {
  $l = @($pozycje | Sort-Object -Property Tokeny -Descending)
  if ($l.Count -eq 0) { return $null }
  return $l[0]
}

function Alarm($krotko, $pelny) {
  return [pscustomobject]@{ Krotko = $krotko; Pelny = $pelny }
}

$alarmy = @()

if ($tokWiadomosc -gt $AlarmNaWiadomosc) {
  $n = Najdrozsza $kubWiadomosc
  $alarmy += Alarm "wiadomosc +$tokWiadomosc tokenow (prog $AlarmNaWiadomosc)" `
    ("Kazda Twoja wiadomosc kosztuje ~$(Liczba $tokWiadomosc) tokenow, prog to $(Liczba $AlarmNaWiadomosc). " +
     "Najdrozsza pozycja: $($n.Nazwa) - $($n.Rada). Plik: $($n.Skad).")
}

if ($tokSesja -gt $AlarmNaSesje) {
  $n = Najdrozsza $kubSesja
  $alarmy += Alarm "start sesji +$tokSesja tokenow (prog $AlarmNaSesje)" `
    ("Start sesji kosztuje ~$(Liczba $tokSesja) tokenow, prog to $(Liczba $AlarmNaSesje). " +
     "Najdrozsza pozycja: $($n.Nazwa) (~$(Liczba $n.Tokeny) tokenow) - $($n.Rada). Plik: $($n.Skad).")
}

foreach ($k in @(
  @{ Poz = $kubSesja;     Nazwa = "start sesji" },
  @{ Poz = $kubWiadomosc; Nazwa = "kazda wiadomosc" }
)) {
  if (@($k.Poz).Count -lt $MinPozycjiDoUdzialu) { continue }
  $n = Najdrozsza $k.Poz
  if ($n.Procent -le $AlarmUdzialu) { continue }
  $alarmy += Alarm "$($n.Nazwa) to $($n.Procent)% rachunku za $($k.Nazwa)" `
    ("Jedna pozycja zjada $($n.Procent)% rachunku za $($k.Nazwa): $($n.Nazwa), ~$(Liczba $n.Tokeny) tokenow. " +
     "Skracanie czegokolwiek innego nic nie da - $($n.Rada). Plik: $($n.Skad).")
}

if ($skokKosztu) {
  $alarmy += Alarm "+$zmianaProc% od poprzedniego pomiaru" `
    ("Start sesji urosl o $zmianaProc% od poprzedniego pomiaru ($(Liczba $poprz.Tokeny) -> $(Liczba $tokSesja) tokenow) - " +
     "sprawdz, co doszlo do $plikClaude.")
}

# Cykl wiedzy. Jedyny alarm w tym raporcie, ktory mowi o naprawde wydanych
# tokenach, a nie o doklejonym tekscie - dlatego liczba stoi tu osobno i nie
# jest z niczym sumowana.
if ($cykl -and ($null -ne $cykl.Tokeny) -and ([long]$cykl.Tokeny -gt $AlarmCyklu)) {
  $czymCykl = $cykl.Narzedzie
  if (-not $czymCykl) { $czymCykl = "nieznanym narzedziem" }
  $dzienCykl = $cykl.Data
  if (-not $dzienCykl) { $dzienCykl = "ostatniego dnia" }
  $alarmy += Alarm "cykl wiedzy $(Liczba $cykl.Tokeny) tokenow (prog $(Liczba $AlarmCyklu))" `
    ("Cykl wiedzy kosztowal $dzienCykl ~$(Liczba $cykl.Tokeny) tokenow w $(Lub-Nieznane $cykl.Wywolania) wywolaniach ($czymCykl), " +
     "prog to $(Liczba $AlarmCyklu). To jedyna pozycja w tym raporcie placona prawdziwym wywolaniem modelu. " +
     "Tyle wychodzi, gdy cykl nadrabia zaleglosc raty po racie - zajrzyj do $plikCyklOstatni. " +
     "Trwale zbijesz to, zmniejszajac `$MaxNadrabiania albo `$MaxProb w narzedzia\cykl-dzienny.ps1.")
}

if ($Zwiezle) {
  # Liczby bez separatora tysiecy: ta linia ma sie zmiescic w jednym wierszu
  # terminala i jest pokazywana przez straznika przy kazdym otwarciu sesji.
  # Obie liczby, bo sama sesyjna sugerowala, ze tyle placi sie za wiadomosc.
  if ($tokWiadomosc -gt 0) {
    $rachunek = "pamiec: wiadomosc +$tokWiadomosc tokenow, start sesji +$tokSesja tokenow"
  } else {
    $rachunek = "pamiec: start sesji +$tokSesja tokenow, przypomnienia nie umiem zmierzyc"
  }
  if ($cosUcinane) {
    $g = $ucinane[0]
    $opis = "UCINANE: $($g.Krotka) -$($g.Strata) $($g.Jednostka)"
    if ($g.Naglowek) { $opis = $opis + " (od ""$(Skroc $g.Naglowek 34)"")" }
    if ($ucinane.Count -gt 1) { $opis = $opis + " i jeszcze $($ucinane.Count - 1)" }
    $linia = "UWAGA $rachunek, $opis"
  } elseif ($alarmy.Count -gt 0) {
    $opis = "ALARM: $($alarmy[0].Krotko)"
    if ($alarmy.Count -gt 1) { $opis = $opis + " i jeszcze $($alarmy.Count - 1)" }
    $linia = "UWAGA $rachunek, $opis"
  } else {
    $linia = "$rachunek, nic nie jest ucinane"
  }
  Write-Output $linia
  if ($cosUcinane -or $alarmy.Count -gt 0) { exit 1 }
  exit 0
}

# --- wypisanie: same sufity (jedno polecenie do odpalenia po zmianie zasad) ---
# Przechodzi po WSZYSTKICH parach (ladunek, sufit), ktore juz sa policzone wyzej -
# drugi raz tego nie liczymy. Kod wyjscia 1 przy jakimkolwiek przekroczeniu, zeby
# dalo sie to wpiac jako bramke. Sufitow z Lore tu nie ma: niczego nie ucinaja
# przed modelem, a zapytania do bazy trwaja.
if ($TylkoSufity) {
  Write-Output "Sufity ladunkow - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
  foreach ($s in (Sortuj-Sufity $sufity)) {
    if (-not $s.Zmierzony) {
      Write-Output ("  ?     {0} - nie zmierzone: {1}" -f $s.Krotka, $s.Uwaga)
      continue
    }
    if ($s.Przekroczony -and $s.Ucina) {
      $opisU = "  UCINA {0} - {1} z {2} {3}, przepada {4}; sufit: {5}" -f `
               $s.Krotka, (Liczba $s.Teraz), (Liczba $s.Limit), $s.Jednostka, (Liczba $s.Strata), $s.SkadLimitu
      if ($s.Naglowek) { $opisU = $opisU + " (ginie od ""$(Skroc $s.Naglowek 40)"")" }
      Write-Output $opisU
    } elseif ($s.Przekroczony) {
      Write-Output ("  PROG  {0} - {1} z {2} {3}, ale ten sufit niczego nie ucina" -f `
                    $s.Krotka, (Liczba $s.Teraz), (Liczba $s.Limit), $s.Jednostka)
    } else {
      Write-Output ("  ok    {0} - {1} z {2} {3} ({4}% sufitu)" -f `
                    $s.Krotka, (Liczba $s.Teraz), (Liczba $s.Limit), $s.Jednostka, $s.Procent)
    }
  }
  if ($cosUcinane) {
    Write-Output "BLAD  cos jest ucinane po cichu - podnies limit we wskazanym pliku albo skroc tresc."
    exit 1
  }
  Write-Output "Nic nie jest ucinane."
  exit 0
}

# --- pomiary tylko do pelnego raportu ----------------------------------------
# (zapytania do bazy Lore potrafia chwile trwac, wiec w trybie zwiezlym ich nie ma)

$kolejka = Kolejka-Lore $bazaLore $plikZnacznik
$kawalek = Najdluzszy-Kawalek $bazaLore

$przebiegi = 0
if ($kolejka.Ok -and $limitWejscia -and $limitWejscia -gt 0) {
  $przebiegi = [int][math]::Ceiling([double]$kolejka.Ile / [double]$limitWejscia)
}

$sufity += Sufit ([ordered]@{
  Nazwa      = "jedna porcja rozmow wysylana do wyciagania faktow"
  Krotka     = "porcja dla Lore"
  Teraz      = $(if ($kolejka.Ok) { $kolejka.Ile } else { $null })
  Limit      = $limitWejscia
  Jednostka  = "znakow"
  Czyj       = "NASZ - stala w lore\lore\facts.py"
  SkadLimitu = "lore\lore\facts.py (MAX_INPUT_CHARS)"
  Plik       = $bazaLore
  Skutek     = "nic nie ginie: co sie nie zmiesci, czeka w kolejce na kolejny przebieg (teraz do nadrobienia przebiegow: $przebiegi)"
  Ucina      = $false
  Informacyjny = $true
  Uwaga      = (Powod-Braku $(if ($kolejka.Ok) { $kolejka.Ile } else { $null }) $limitWejscia "nie da sie policzyc kolejki: $($kolejka.Powod)" "lore\lore\facts.py")
})

$sufity += Sufit ([ordered]@{
  Nazwa      = "krojenie rozmowy na kawalki do wyszukiwania"
  Krotka     = "kawalek rozmowy"
  Teraz      = $(if ($kawalek.Ok) { $kawalek.Ile } else { $null })
  Limit      = $limitKawalka
  Jednostka  = "znakow"
  Czyj       = "NASZ - stala w lore\lore\index.py"
  SkadLimitu = "lore\lore\index.py (CHUNK_SIZE)"
  Plik       = $bazaLore
  Skutek     = "nic nie ginie, ale dluzsza wypowiedz jest krojona na kawalki - czasem w pol slowa; tak ma byc, to nie jest przekroczenie"
  Ucina      = $false
  Informacyjny = $true
  Uwaga      = (Powod-Braku $(if ($kawalek.Ok) { $kawalek.Ile } else { $null }) $limitKawalka "nie da sie zmierzyc kawalkow: $($kawalek.Powod)" "lore\lore\index.py")
})

# warstwa referencyjna: kandydaci i wlasny raport maja ponizej osobne linie,
# wiec tutaj ich nie liczymy drugi raz
$pliki = @()
if (Test-Path -LiteralPath $katWiedzy) {
  $pliki = @(Get-ChildItem -LiteralPath $katWiedzy -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -ne "kandydaci.md" -and $_.Name -ne "koszt-ostatni.txt" })
}
$bajtyWiedzy = 0
foreach ($p in $pliki) { $bajtyWiedzy += $p.Length }

$kandydaci = $null
if (Test-Path -LiteralPath $plikKandydat) {
  $kandydaci = 0
  try {
    foreach ($l in @((Czytaj $plikKandydat) -split "`r?`n")) {
      if ($l -match '^\s*-\s*\[\s\]') { $kandydaci++ }
    }
  } catch { $kandydaci = $null }
}

$stare = @($w.Wpisy | Where-Object { $_.Stary })

# --- ostrzezenia -------------------------------------------------------------

$ostrzezenia = @()
foreach ($s in $ucinane) {
  $ostrzezenia += "UCINANE PO CICHU: $($s.Nazwa) - ginie $(Liczba $s.Strata) $($s.Jednostka) z $(Liczba $s.Teraz). Sufit $($s.SkadLimitu)."
}
foreach ($a in $alarmy) {
  $ostrzezenia += $a.Pelny
}
foreach ($s in $sufity) {
  if ($s.Zmierzony -and (-not $s.Informacyjny) -and (-not $s.Przekroczony) -and ($s.Procent -ge $ProgCiasno)) {
    $ostrzezenia += "Blisko sufitu: $($s.Nazwa) - zajete $($s.Procent)% ($(Liczba $s.Teraz) z $(Liczba $s.Limit) $($s.Jednostka))."
  }
}
if ($w.Wpisy.Count -gt $ProgBiezacych) {
  $ostrzezenia += "Warstwa biezaca ma $($w.Wpisy.Count) wpisow (prog $ProgBiezacych) - przejrzyj je i skasuj to, co juz nieaktualne."
}
if ($stare.Count -gt 0) {
  $ostrzezenia += "Przeterminowanych wpisow: $($stare.Count) - agent bierze je za prawde, wiec albo odswiez date, albo skasuj."
}
if (($kandydaci -ne $null) -and ($kandydaci -gt $ProgPoczekalni)) {
  $ostrzezenia += "W poczekalni czeka $kandydaci faktow (prog $ProgPoczekalni) - zatwierdz je albo odrzuc, bo same sie nie zuzyja."
}
if ($cykl -and ($null -ne $cykl.Wiek) -and ($cykl.Wiek -gt $DniCyklStary)) {
  $ostrzezenia += "Koszt cyklu wiedzy jest z dnia $($cykl.Data), sprzed $($cykl.Wiek) dni - od tego czasu cykl nie wylowil ani jednego faktu, wiec wiedza nie przyrasta."
}

# --- wypisanie: pelny raport -------------------------------------------------

function Wypisz-Kubelek($pozycje, $razem, $czegoNieMa) {
  # Pozycje od najdrozszej, bo tylko gorna czesc listy ma znaczenie przy
  # skracaniu. Drobiazgi ponizej 1% ida w jedna linie "reszta" - wypisane
  # osobno tylko zaslanialyby to, co naprawde kosztuje.
  $l = @($pozycje)
  if ($l.Count -eq 0) {
    Linia "  $czegoNieMa"
    return
  }
  $reszta = 0
  $ileReszty = 0
  foreach ($p in ($l | Sort-Object -Property Tokeny -Descending)) {
    if ($p.Procent -lt 1) { $reszta += $p.Tokeny; $ileReszty++; continue }
    Linia ("  {0,-38} {1,8} znakow, ~{2,6} tokenow, {3,3}% tego rachunku" -f `
           (Skroc $p.Nazwa 38), (Liczba $p.Znaki), (Liczba $p.Tokeny), $p.Procent)
    Linia ("       z pliku: {0}" -f $p.Skad)
  }
  if ($ileReszty -gt 0) {
    Linia ("  {0,-38} {1,8}        ~{2,6} tokenow, ponizej 1%" -f `
           "reszta ($ileReszty poz.)", "", (Liczba $reszta))
  }
  Linia ("  {0,-38} {1,8}        ~{2,6} tokenow" -f "RAZEM", "", (Liczba $razem))
}

function Wiersz-Sufitu($s) {
  $znak  = "  "
  $kolor = $null
  if ($s.Zmierzony -and (-not $s.Informacyjny)) {
    if ($s.Przekroczony) { $znak = "!!"; $kolor = "Red" }
    elseif ($s.Procent -ge $ProgCiasno) { $znak = "! "; $kolor = "Yellow" }
  }
  Linia ("  {0} {1}" -f $znak, $s.Nazwa) $kolor
  if (-not $s.Zmierzony) {
    Linia ("       bez pomiaru: {0}" -f $s.Uwaga)
  } elseif ($s.Przekroczony) {
    Linia ("       {0} z {1} {2} - PRZEKROCZONE o {3} ({4}% sufitu)" -f `
           (Liczba $s.Teraz), (Liczba $s.Limit), $s.Jednostka, (Liczba $s.Strata), $s.Procent) $kolor
  } else {
    Linia ("       {0} z {1} {2} - zapasu {3}%" -f `
           (Liczba $s.Teraz), (Liczba $s.Limit), $s.Jednostka, $s.Zapas)
  }
  Linia ("       po przekroczeniu: {0}" -f $s.Skutek)
  Linia ("       sufit {0}; czytamy go z: {1}" -f $s.Czyj, $s.SkadLimitu)
  if ($s.Zmierzony -and $s.Plik) { Linia ("       mierzymy: {0}" -f $s.Plik) }
}

Linia ""
Linia "Audyt pamieci i sufitow - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Linia "Katalog: $katKlaudii"

Linia ""
Linia "0. CO WYMAGA UWAGI TERAZ"
if ((-not $cosUcinane) -and ($alarmy.Count -eq 0)) {
  Linia "  Nic nie jest ucinane, zaden prog nie jest przekroczony."
}
if ($alarmy.Count -gt 0) {
  foreach ($a in $alarmy) {
    Linia ("  ALARM: {0}" -f $a.Krotko) "Red"
    Linia ("    {0}" -f $a.Pelny) "Red"
  }
  Linia "  Progi sa nasze - siedza na gorze narzedzia\koszt-pamieci.ps1 i zmienia sie je jedna linijka."
}
if ((-not $cosUcinane) -and ($alarmy.Count -gt 0)) {
  Linia "  Nic za to nie jest ucinane - kazdy tekst miesci sie w swoim suficie."
}
if ($cosUcinane) {
  foreach ($s in $ucinane) {
    $procUtraty = 0
    if ([long]$s.Teraz -gt 0) { $procUtraty = [int][math]::Round(100.0 * $s.Strata / [double]$s.Teraz) }
    Linia ("  UCINANE: {0}" -f $s.Nazwa) "Red"
    Linia ("    ginie {0} {1} z {2} - {3}% tekstu, i to jego KONIEC" -f `
           (Liczba $s.Strata), $s.Jednostka, (Liczba $s.Teraz), $procUtraty) "Red"
    if ($s.Naglowek) {
      Linia ("    ucieta czesc zaczyna sie od naglowka: {0}" -f $s.Naglowek) "Red"
    } else {
      Linia "    w urwanej czesci nie ma naglowka, wiec nie umiem nazwac, co przepada" "Red"
    }
    Linia ("    tekst: {0}" -f $s.Plik)
    Linia ("    sufit: {0} {1} z {2}" -f (Liczba $s.Limit), $s.Jednostka, $s.SkadLimitu)
  }
}

Linia ""
Linia "1. Sufity - gdzie stoi kazdy i ile zostalo zapasu"
Linia "   (!! = przekroczony, ! = zajete ponad $ProgCiasno%; na gorze te najciasniejsze)"
foreach ($s in (Sortuj-Sufity $sufity)) { Wiersz-Sufitu $s }

Linia ""
Linia "2. PRZY KAZDEJ Twojej wiadomosci - z czego sie sklada"
Wypisz-Kubelek $kubWiadomosc $tokWiadomosc `
  "Nie znalazlem zadnego przypomnienia - przy wiadomosci nie dokleja sie nic."
if ($przypCcZnaki -ne $null -and $przypZnaki -ne $null) {
  $ogonCodex = ""
  if (-not $jestCodex) { $ogonCodex = " - tej maszyny to nie dotyczy, Codeksa tu nie ma" }
  Linia ("  Pod Codeksem zamiast tego leci ~{0} tokenow z {1}{2}." -f (Liczba (Tokeny $przypZnaki)), $przypSkad, $ogonCodex)
}
Linia "  Tylko to jest doklejane przy kazdym Twoim zdaniu. Reszta wchodzi raz, na starcie sesji."

Linia ""
Linia "3. RAZ, przy starcie sesji - z czego sie sklada"
if (-not $w.Jest) {
  Linia "  Nie ma pliku $plikClaude - czyli nic stad nie wchodzi do rozmowy."
}
Wypisz-Kubelek $kubSesja $tokSesja `
  "Nie ma czego mierzyc - ani pamieci w CLAUDE.md, ani zasad wstrzykiwanych hookiem."
if ($w.Jest -and (-not $w.MaSekcje)) {
  Linia "  (sekcji '## Co wiem' w tym pliku nie ma - warstwa stala i biezaca sa puste)"
}
if ($w.Jest -and ($w.Blok.Znaki -eq 0)) {
  Linia "  (bloku zasad MegaRuchacza w tym pliku nie ma)"
}
if (-not $zasadyCcTresc -and -not $zasadyWdrozone) {
  Linia "  (zasad wstrzykiwanych hookiem nie doliczam: bez -Projekt widze tylko szablon, a szablon sam z siebie nic nie wysyla)"
}
Linia "  To wchodzi do kontekstu raz i siedzi w nim do konca sesji - nie jest wysylane ponownie przy kazdej wiadomosci."
Linia "  Tokeny to SZACUNEK, nie pomiar: przyjete ~$ZnakiNaToken znaki na token dla polszczyzny."
# linia maszynowa - z niej czyta poprzedni pomiar nastepny przebieg
Linia ("  POMIAR tokenow={0} znakow={1}" -f $tokSesja, $razemZnakow)
if (-not $poprz) {
  Linia "  Poprzedniego pomiaru nie ma ($plikOstatni) - nie ma z czym porownac. Powstanie przy najblizszym dziennym raporcie."
} else {
  $dataPoprz = "data nieznana"
  if ($poprz.Data) { $dataPoprz = $poprz.Data.ToString("yyyy-MM-dd HH:mm") }
  $opisZmiany = "bez zmian"
  if ($zmiana -gt 0) { $opisZmiany = "+$(Liczba $zmiana), +$zmianaProc%" }
  elseif ($zmiana -lt 0) { $opisZmiany = "$(Liczba $zmiana), $zmianaProc%" }
  $kolorZmiany = $null
  if ($skokKosztu) { $kolorZmiany = "Yellow" }
  Linia ("  Poprzedni pomiar ({0}): {1} -> {2} tokenow na starcie sesji ({3})" -f `
         $dataPoprz, (Liczba $poprz.Tokeny), (Liczba $tokSesja), $opisZmiany) $kolorZmiany
}

Linia ""
Linia "4. RAZ NA DOBE - cykl wiedzy (jedyne prawdziwe wolanie modelu)"
Linia "  Dwa rachunki wyzej to TEKST doklejany do rozmowy. Ten jest innego rodzaju:"
Linia "  cykl dzienny wola model, zeby przeczytal wczorajsze rozmowy i wylowil z nich"
Linia "  fakty. Dlatego nie dodajemy go do tamtych - to osobne pieniadze, placone raz"
Linia "  na dobe, a zsumowane sugerowalyby, ze tyle kosztuje kazda sesja."
if (-not $cykl) {
  Linia "  Cykl jeszcze nie liczyl kosztu - nie ma pliku $plikCyklKoszt."
  Linia "  To normalny stan, nie awaria: liczba pojawi sie po pierwszym przebiegu cyklu,"
  Linia "  ktory wylowi fakty (narzedzia\cykl-dzienny.ps1)."
} else {
  $opisDnia = $cykl.Data
  if (-not $opisDnia) { $opisDnia = "dzien nieznany" }
  $kiedyCykl = Kiedy-Cykl $cykl.Wiek
  if ($kiedyCykl) { $opisDnia = "$opisDnia ($kiedyCykl)" }
  $czymCyklOpis = $cykl.Narzedzie
  if (-not $czymCyklOpis) { $czymCyklOpis = "nie wiadomo (cykl tego nie podal)" }
  Linia ("  Dzien: {0}, narzedzie: {1}" -f $opisDnia, $czymCyklOpis)
  Linia ("  {0,-38} {1,8}        ~{2,6} tokenow" -f "CYKL WIEDZY RAZEM", "", (Lub-Nieznane $cykl.Tokeny))
  Linia ("  Wywolan modelu: {0}, wylowionych faktow: {1}" -f `
         (Lub-Nieznane $cykl.Wywolania), (Lub-Nieznane $cykl.Fakty))
  Linia ("  Wyslane: {0} znakow, odebrane: {1} znakow" -f `
         (Lub-Nieznane $cykl.ZnakiWyslane), (Lub-Nieznane $cykl.ZnakiOdebrane))
  Linia ("  {0}" -f (Opis-Zrodla $cykl.Zrodlo))
  $poprzCykl = $cykl.Poprzedni
  if ((-not $poprzCykl) -or ($null -eq $poprzCykl.Tokeny) -or ($null -eq $cykl.Tokeny)) {
    Linia "  Poprzedniego dnia nie ma z czym porownac - cykl nie podal jego liczb."
  } else {
    $roznicaCykl = [long]$cykl.Tokeny - [long]$poprzCykl.Tokeny
    $procCykl = 0
    if ([long]$poprzCykl.Tokeny -gt 0) {
      $procCykl = [int][math]::Round(100.0 * $roznicaCykl / [double]$poprzCykl.Tokeny)
    }
    $opisRoznicy = "bez zmian"
    if ($roznicaCykl -gt 0)     { $opisRoznicy = "+$(Liczba $roznicaCykl), +$procCykl%" }
    elseif ($roznicaCykl -lt 0) { $opisRoznicy = "$(Liczba $roznicaCykl), $procCykl%" }
    $dzienPoprz = $poprzCykl.Data
    if (-not $dzienPoprz) { $dzienPoprz = "dzien nieznany" }
    Linia ("  Poprzedni dzien ({0}): {1} -> {2} tokenow ({3})" -f `
           $dzienPoprz, (Liczba $poprzCykl.Tokeny), (Liczba $cykl.Tokeny), $opisRoznicy)
  }
  if (($null -ne $cykl.Wiek) -and ($cykl.Wiek -gt $DniCyklStary)) {
    Linia ("  Ta liczba ma {0} dni - cykl od tego czasu nie liczyl kosztu, czyli najpewniej" -f $cykl.Wiek) "Yellow"
    Linia "  w ogole nie chodzi. Sprawdz: powershell -File narzedzia\cykl-dzienny.ps1 -Proba" "Yellow"
  }
  Linia "  Zapisal to sam cykl: $plikCyklKoszt"
}

Linia ""
Linia "5. Warstwa referencyjna ($katWiedzy)"
if (-not (Test-Path -LiteralPath $katWiedzy)) {
  Linia "  Nie ma tego katalogu - warstwy referencyjnej jeszcze nie ma."
} else {
  Linia "  Plikow: $($pliki.Count), lacznie $(Rozmiar $bajtyWiedzy)"
  Linia "  To NIE jest doklejane do rozmow. Nie kosztuje nic, dopoki agent po to nie siegnie -"
  Linia "  wiec ta warstwa moze byc duza, nie bedac droga. Tu przenosi sie to, co puchnie wyzej."
}

Linia ""
Linia "6. Poczekalnia ($plikKandydat)"
if ($kandydaci -eq $null) {
  Linia "  Nie ma pliku kandydatow - nic nie czeka na decyzje. To normalne."
} else {
  Linia "  Faktow czeka na zatwierdzenie: $kandydaci"
}

Linia ""
Linia "7. Higiena warstwy biezacej (wpis wazny przez $DniWaznosci dni)"
if ((-not $w.Jest) -or (-not $w.MaSekcje)) {
  Linia "  Brak danych - nie ma czego sprawdzac."
} elseif ($w.Wpisy.Count -eq 0) {
  Linia "  Nie ma ani jednego wpisu w formacie - [RRRR-MM-DD] tresc."
} else {
  Linia "  Wpisow: $($w.Wpisy.Count), w tym przeterminowanych: $($stare.Count)"
  foreach ($s in $stare) {
    Linia "    [$($s.Data)] ($($s.Wiek) dni) $(Skroc $s.Tresc 70)"
  }
}

Linia ""
Linia "8. Inne sufity znalezione w kodzie (stale, wiec nie ma tu czego mierzyc)"
$inne = @(
  @{ Plik = $plikIndeksu;  Wzor = '(?m)^MAX_TOOL_INPUT\s*=\s*([\d_]+)';     Opis = "opis wywolania narzedzia zapisywany w pamieci Lore jest przycinany do {0} znakow (lore\lore\index.py)" },
  @{ Plik = $plikIndeksu;  Wzor = '(?m)^MAX_TOOL_RESULT\s*=\s*([\d_]+)';    Opis = "wynik narzedzia zapisywany w pamieci Lore jest przycinany do {0} znakow (lore\lore\index.py)" },
  @{ Plik = $plikSzukania; Wzor = '(?m)^MAX_SNIPPET\s*=\s*([\d_]+)';        Opis = "fragment pokazywany w wynikach szukania jest przycinany do {0} znakow (lore\lore\search.py)" },
  @{ Plik = $plikKopania;  Wzor = '(?m)^MAX_SNIPPET\s*=\s*([\d_]+)';        Opis = "fragment podawany modelowi przy kopaniu w pamieci przycinany do {0} znakow (lore\lore\mining.py)" },
  @{ Plik = $plikKopania;  Wzor = '(?m)^MAX_PREVIEW_SNIPPET\s*=\s*([\d_]+)'; Opis = "zajawka w podgladzie znalezisk przycinana do {0} znakow (lore\lore\mining.py)" }
)
$bylo = $false
foreach ($i in $inne) {
  $v = Limit-Z-Pliku $i.Plik $i.Wzor
  if ($v -eq $null) { continue }
  $bylo = $true
  Linia ("  - " + ($i.Opis -f (Liczba $v)))
}
if (-not $bylo) {
  Linia "  Nie znalazlem zadnego - albo nie ma tu katalogu lore\."
} else {
  Linia "  Te sufity tna tresc, zanim trafi do pamieci albo do wyniku szukania. Nie dotycza"
  Linia "  tego, co dokleja sie do rozmowy, wiec nie licza sie do kosztu wyzej."
}

Linia ""
Linia "9. Ostrzezenia"
if ($ostrzezenia.Count -eq 0) {
  Linia "  Nic nie wymaga uwagi - nic nie jest ucinane, a pamiec trzyma sie w rozsadnych rozmiarach."
} else {
  foreach ($o in $ostrzezenia) { Linia "  UWAGA  $o" "Yellow" }
}

# Podsumowanie: dwie liczby i nic wiecej. Zadnych mnozen - uzytkownik powiedzial
# wprost, ze po przeliczeniu na dobe czy na sto wiadomosci i tak nic nie wie.
Linia ""
Linia "10. Podsumowanie"
if ($tokWiadomosc -gt 0) {
  Linia "  Kazda Twoja wiadomosc: +$(Liczba $tokWiadomosc) tokenow."
} else {
  Linia "  Kazda Twoja wiadomosc: nie umiem zmierzyc - nie znalazlem pliku z przypomnieniem."
}
Linia "  Start sesji: +$(Liczba $tokSesja) tokenow, raz."
# Trzecia liczba stoi osobno i celowo nie jest dodana do dwoch powyzej:
# tamte to doklejony tekst, ta to prawdziwie wydane tokeny.
if ($cykl -and ($null -ne $cykl.Tokeny)) {
  $ogonZrodla = ""
  if ($cykl.Zrodlo -eq "szacunek") { $ogonZrodla = " (szacunek)" }
  elseif ($cykl.Zrodlo -eq "pomiar") { $ogonZrodla = " (pomiar)" }
  Linia "  Cykl wiedzy: ~$(Liczba $cykl.Tokeny) tokenow$ogonZrodla raz na dobe - i to jedyne z tych trzech, co naprawde wola model."
} else {
  Linia "  Cykl wiedzy: kosztu jeszcze nie policzyl - liczba pojawi sie po pierwszym przebiegu cyklu."
}
$sciezkaSkryptu = $PSCommandPath
if (-not $sciezkaSkryptu) { $sciezkaSkryptu = Join-Path $Zrodlo "narzedzia\koszt-pamieci.ps1" }
Linia ""
Linia "Caly ten rachunek na zadanie - jedna komenda do wklejenia w terminal:"
Linia "  powershell -ExecutionPolicy Bypass -File $sciezkaSkryptu"
Linia ""

# Kolory ida przez Write-Host, a tego nie lapie ani przekierowanie, ani potok -
# wiec przy zapisie do pliku (-Zwykly albo wykryte przekierowanie) wypisujemy
# wszystko zwyklym wyjsciem, zeby zaden wiersz nie zginal po drodze.
$kolorowac = (-not $Zwykly)
if ($kolorowac) {
  try { if ([Console]::IsOutputRedirected) { $kolorowac = $false } } catch { $kolorowac = $false }
}
foreach ($l in $script:Raport) {
  if ($kolorowac -and $l.Kolor) { Write-Host $l.Tekst -ForegroundColor $l.Kolor }
  else { Write-Output $l.Tekst }
}

if ($cosUcinane -or $alarmy.Count -gt 0) { exit 1 }
exit 0
