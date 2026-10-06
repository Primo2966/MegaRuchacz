# zasobnik\nadzorca\stan-koszt.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Prawdziwy koszt dnia (P26): Twoje rozmowy kontra
# workerzy, najdrozsi workerzy (Koszt-Dzis, Opis-Workera, Teksty-Kosztu),
# werdykt na gorze Przegladu (Werdykt-Kosztu,
# Zdanie-Wiadomosci) i odczyt rachunku z koszt-pamieci.ps1 -Dane (Liczba-Z-Klucza,
# Tekst-Z-Klucza, Alarmy-Rachunku, Ocena-Nauki).
# Skad wolane: krok "koszt" w w-tle.ps1, tryb -Raport w nadzorca.ps1, karty
# Przegladu, stan-alarmy.ps1 i stan-po-ludzku.ps1. Wczytuje go stan-nadzorcy.ps1
# kropka - poza stalymi same definicje.

# ---------------------------------- prawdziwy koszt: Twoje rozmowy i workerzy (P26)
#
# P22 (analiza 30.09.2026): workerzy to 78% wywolan modelu i 60% odczytu z bufora,
# a rozmowa kierownika urosla do ~580 tys. tokenow - kazde jej wywolanie czyta ja
# cala. Okno pokazywalo dotad tylko to, co doklada sam MegaRuchacz (kilka procent
# otwarcia okna rozmowy), wiec najwieksze pozycje byly niewidoczne. Tu liczymy to,
# co naprawde idzie: dzis Twoje rozmowy kontra workerzy i najdrozsi workerzy dnia.
# Srednia z 7 dni (tez rozdzielona) daje Zuzycie-Dzienne wyzej.
# Lista najdluzszych rozmow z "!" ponad progiem (tez P26) usunieta 2026-10-01 (P43)
# decyzja uzytkownika - razem z ostrzezeniem o dlugiej rozmowie w przypomnieniu
# i w strazniku: dlugosci rozmow nie liczymy i nie pokazujemy.
#
# SKAD LICZBY. Ten sam licznik co dzienne zuzycie (te same cztery pola usage, kazde
# message.id raz, najwieksze wartosci z jego linii), tylko na plikach zmienionych
# w ostatnich $GODZIN_KOSZTU h (30.09.2026: 36 plikow, ~130 MB). Worker = transkrypt
# ...\<rozmowa>\subagents\agent-*.jsonl; opis zadania z agent-*.meta.json obok (pole
# description - tak Claude Code zapisuje opis podany przy wywolaniu workera).
#
# KIEDY. Krok "koszt" w nadzorca.ps1, w watku w tle: przy otwarciu okna, gdy wynik
# jest starszy niz kwadrans, i po dozorze, gdy okno jest otwarte. Liczby "dzis"
# rosna w ciagu dnia, wiec - inaczej niz srednia - nie sa swieze przez caly dzien.
#
# CISZA. Brak katalogu i wywrotka zostawiaja Powod (okno pisze "nie wiem, bo..."),
# nieczytelny opis workera - "bez opisu" z powodem w Szczegolach. Dzien bez rozmow
# to prawdziwe zero i okno mowi to zdaniem, nie cyfra.
$GODZIN_KOSZTU = 24
$NAJDROZSZYCH_WORKEROW = 5

# Nazwa projektu dla czlowieka: ostatni czlon katalogu, w ktorym szla rozmowa
# ("C:\dev\claude-worker" -> "claude-worker"). Gdy go nie ma - katalog projektu
# w transkryptach bez litery dysku, tak jak w Szczegolach otwarcia okna.
function Projekt-Rozmowy([string]$cwd, [string]$sciezka) {
  if ($cwd) {
    $n = [System.IO.Path]::GetFileName($cwd.TrimEnd('\', '/'))
    if ($n) { return $n }
  }
  $kat = Join-Path $script:NadzDom ".claude\projects"
  $rel = "$sciezka"
  if ($rel.StartsWith($kat, [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($kat.Length).TrimStart('\') }
  return ((($rel -split '\\')[0]) -replace '^[A-Za-z]--', '')
}

function Opis-Workera($p) {
  $x = [pscustomobject]@{
    Opis = ""; Rola = ""; Uwaga = ""; Projekt = (Projekt-Rozmowy $p.Cwd $p.Sciezka)
    Tokeny = $p.Tokeny; Wywolania = $p.Wywolania; Ostatnio = $null; Plik = $p.Sciezka
  }
  if ($p.Ostatnio -gt [datetime]::MinValue) { $x.Ostatnio = $p.Ostatnio.ToLocalTime() }
  $meta = [System.IO.Path]::ChangeExtension($p.Sciezka, ".meta.json")
  if (Test-Path -LiteralPath $meta) {
    try {
      $j = [System.IO.File]::ReadAllText($meta, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
      $x.Opis = "$($j.description)".Trim()
      $x.Rola = "$($j.agentType)".Trim()
    } catch { $x.Uwaga = "nie odczytałem opisu zadania: $(($_.Exception.Message -replace '[\r\n]+', ' ').Trim())" }
  } else {
    $x.Uwaga = "Claude Code nie zostawił opisu zadania (brak $([System.IO.Path]::GetFileName($meta)))"
  }
  return $x
}

# Liczenie - w watku w tle okna albo wprost w wydruku -Raport. Zawsze oddaje obiekt:
# z liczbami albo z Powodem.
function Koszt-Dzis {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $teraz = [datetime]::Now
  $k = [pscustomobject]@{
    Powod = ""; Wyliczono = $teraz; Sekundy = ""; Pliki = 0; Mb = 0; Bledy = 0; Blad = ""
    Rozmowy = $null; Workerzy = $null; OdpowiedziRozmow = $null; OdpowiedziWorkerow = $null
    WorkerowDzis = 0; Najdrozsi = @(); Godzin = $GODZIN_KOSZTU
  }
  try {
    $katalog = Join-Path $script:NadzDom ".claude\projects"
    if (-not (Test-Path -LiteralPath $katalog)) {
      $k.Powod = "nie ma katalogu z Twoimi rozmowami z Claude Code ($katalog)"
    } else {
      $odCzasu = $teraz.AddHours(-$GODZIN_KOSZTU)
      $pliki = @(Get-ChildItem -LiteralPath $katalog -Recurse -Filter *.jsonl -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.LastWriteTime -ge $odCzasu } | ForEach-Object { $_.FullName })
      $k.Pliki = $pliki.Count
      # Brak plikow z ostatniej doby = dzis naprawde nic (katalog przejrzany), nie "nie wiem".
      $k.Rozmowy = [long]0; $k.Workerzy = [long]0; $k.OdpowiedziRozmow = [long]0; $k.OdpowiedziWorkerow = [long]0
      if ($pliki.Count -gt 0) {
        Wczytaj-Licznik-Tokenow
        $dzis = $teraz.Date
        $w = [MegaRuchacz.Tokeny.Licznik]::Policz([string[]]$pliki, $dzis, $dzis.AddDays(1), $true)
        $k.Mb = [long][math]::Round($w.Bajty / 1MB)
        if ($w.Bledy.Count -gt 0) {
          $k.Bledy = $w.Bledy.Count
          $k.Blad = (($w.Bledy | Where-Object { $_ } | Select-Object -First 1) -replace '[\r\n]+', ' ')
        }
        $klucz = $dzis.ToString('yyyy-MM-dd')
        if ($w.Dni.ContainsKey($klucz)) {
          $d = $w.Dni[$klucz]
          $k.Rozmowy = $d.Rozmowy; $k.Workerzy = $d.Workerzy
          $k.OdpowiedziRozmow = $d.OdpowiedziRozmow; $k.OdpowiedziWorkerow = $d.OdpowiedziWorkerow
        }
        $wor = @($w.PlikiZOdpowiedziami | Where-Object { $_.Worker -and ($_.Tokeny -gt 0) } | Sort-Object -Property Tokeny -Descending)
        $k.WorkerowDzis = $wor.Count
        $k.Najdrozsi = @($wor | Select-Object -First $NAJDROZSZYCH_WORKEROW | ForEach-Object { Opis-Workera $_ })
        if ((($k.Rozmowy + $k.Workerzy) -le 0) -and ($w.Bledy.Count -gt 0)) {
          $k.Powod = "nie dało się otworzyć $($w.Bledy.Count) z $($pliki.Count) plików rozmów, np. $($k.Blad)"
        }
      }
    }
  } catch {
    Zanotuj-Wywrotke "prawdziwy koszt dnia" $_
    $k.Powod = "liczenie się wywróciło: $(($_.Exception.Message -replace '[\r\n]+', ' ').Trim())"
  }
  $k.Sekundy = [math]::Round($sw.Elapsed.TotalSeconds, 1).ToString([System.Globalization.CultureInfo]::InvariantCulture)
  Notuj "prawdziwy koszt dnia policzony w $($k.Sekundy) s: $(if ($k.Powod) { 'BEZ WYNIKU - ' + $k.Powod } else { "rozmowy $($k.Rozmowy), workerzy $($k.Workerzy), $($k.Pliki) plikow" })"
  return $k
}

# Teksty karty (P26) - jedne dla okna i dla wydruku -Raport. $k = Koszt-Dzis,
# $z = Zuzycie-Dzienne (srednia z 7 dni). Gdy czegos nie ma, tekst mowi dlaczego.
function Teksty-Kosztu($k, $z) {
  $x = [pscustomobject]@{
    Tytul = "Ile tokenów naprawdę zużywasz - Twoje rozmowy i workerzy"
    Powod = ""; Tabela = @(); Udzial = ""; UdzialUwaga = $false
    NaglowekWorkerow = "Najdroższe zadania workerów dziś"; Workerzy = @(); WorkerzyPusto = ""
  }
  if (-not $k) { $x.Powod = "Liczę, ile tokenów zużyły dziś rozmowy i workerzy - to potrwa kilka sekund..."; return $x }
  if ($k.Powod) { $x.Powod = "Nie wiem, ile tokenów zużywasz dziś, bo $("$($k.Powod)".TrimEnd('.', ' '))."; return $x }
  $dzisR = [double]$k.Rozmowy; $dzisW = [double]$k.Workerzy
  $sr = "średnio z $($z.Dni) dni"
  if (-not $z) { $sr = "średnio dziennie" }
  $x.Tabela = @(,@("", "dziś do $($k.Wyliczono.ToString('HH:mm'))", $sr))
  $jestSr = $z -and ($z.Stan -eq "jest") -and ($null -ne $z.SredniaRozmowy) -and ($null -ne $z.SredniaWorkerow)
  $brakSr = "liczę..."
  if ($z -and ($z.Stan -eq "brak")) { $brakSr = "nie wiem" }
  $wiersz = {
    param([string]$napis, $dzis, $srednio)
    $d = "nic"
    if ($dzis -gt 0) { $d = Tokeny-Okolo $dzis }
    $s = $brakSr
    if ($jestSr) { $s = Tokeny-Okolo $srednio }
    return ,@($napis, $d, $s)
  }
  $x.Tabela += ,(& $wiersz "Twoje rozmowy" $dzisR $(if ($jestSr) { $z.SredniaRozmowy } else { $null }))
  $x.Tabela += ,(& $wiersz "Workerzy" $dzisW $(if ($jestSr) { $z.SredniaWorkerow } else { $null }))
  $x.Tabela += ,(& $wiersz "Razem" ($dzisR + $dzisW) $(if ($jestSr) { [double]$z.SredniaRozmowy + [double]$z.SredniaWorkerow } else { $null }))
  if (($dzisR + $dzisW) -gt 0) {
    $x.Udzial = "Workerzy to $(Procent-Udzialu $dzisW ($dzisR + $dzisW)) dzisiejszych tokenów"
    if ($jestSr -and (([double]$z.SredniaRozmowy + [double]$z.SredniaWorkerow) -gt 0)) {
      $x.Udzial += ", średnio $(Procent-Udzialu ([double]$z.SredniaWorkerow) ([double]$z.SredniaRozmowy + [double]$z.SredniaWorkerow))"
    }
    $x.Udzial += "."
  } else {
    $x.Udzial = "Dziś jeszcze nie było rozmów z Claude."
  }
  if ((-not $jestSr) -and $z -and ($z.Stan -eq "brak")) { $x.Udzial += " Średniej nie ma: $($z.Powod)."; $x.UdzialUwaga = $true }
  foreach ($w in @($k.Najdrozsi)) {
    $opis = $w.Opis
    if (-not $opis) { $opis = "bez opisu zadania" }
    $dop = @()
    if ($w.Rola) { $dop += $w.Rola }
    if ($w.Projekt) { $dop += $w.Projekt }
    $x.Workerzy += [pscustomobject]@{ Tokeny = (Tokeny-Okolo $w.Tokeny); Opis = $opis; Dopisek = ($dop -join ", ") }
  }
  if (@($k.Najdrozsi).Count -eq 0) { $x.WorkerzyPusto = "Dziś jeszcze żaden worker nie pracował." }
  return $x
}

# P16 (28.09.2026): "+115 przy kazdej wiadomosci" po ludzku - to stala doplata,
# nie zalezy od dlugosci wiadomosci (przypomnienie zasad ma zawsze te sama tresc).
# Bez pomiaru przypomnienia zdania nie ma - zadnego "0" zamiast "nie wiem".
# Zero (OpenCode nie ma hooka wiadomosci, modul kierownik wylaczony) - tez bez zdania:
# "+0 to stala doplata" brzmialoby jak koszt.
function Zdanie-Wiadomosci($start) {
  if (-not $start -or ($null -eq $start.MrWiadomosc) -or ([long]$start.MrWiadomosc -le 0)) { return "" }
  return "Te +$(Liczba-Ludzka ([long]$start.MrWiadomosc)) to stała dopłata MegaRuchacza do każdej Twojej wiadomości - tyle samo, czy piszesz dwa słowa, czy długi tekst."
}

# WERDYKT NA SAMEJ GORZE PRZEGLADU (P15). Uzytkownik: "ma byc jasno jak dla
# laika, ktory nie wie do konca, co to MegaRuchacz, ale wie, ze tokeny kosztuja".
# Trzy stany i zaden czwarty:
#   malo        - czesc MegaRuchacza w otwarciu sesji (start + przypomnienie,
#                 w tokenach) NIE przekracza progu,
#   duzo        - przekracza (to samo porownanie, co alarm "otwarcie"
#                 w koszt-pamieci.ps1: udzial.mr > $AlarmCzesciOtwarcia),
#   nie wiadomo - czesci MegaRuchacza nie da sie zmierzyc albo nie ma progu;
#                 mowimy wtedy wprost, czego brakuje. "Malo" bez pomiaru byloby
#                 klamstwem.
# P35 (30.09.2026, decyzja uzytkownika): prog jest w TOKENACH, nie w procencie
# calego otwarcia okna rozmowy. Procent zalezy od wagi dodatkow, ktora ustawia
# administrator proxy - otwarcie ~191 tys. -> ~75 tys. zrobiloby z tych samych
# ~9 100 tokenow ~12% i czerwony werdykt. Procent zostaje w zdaniu do POKAZANIA
# (ten sam, co na karcie otwarcia tuz nizej); bez zmierzonej calosci zdanie mowi
# same tokeny i dlaczego procentu nie ma - werdykt i tak zapada.
# Czesc MegaRuchacza i prog NIE sa tu liczone ani wpisane - przychodza z jednego
# przebiegu koszt-pamieci.ps1 -Dane (udzial.mr, udzial.start, udzial.prog_tokeny),
# wiec werdykt i alarm nie moga sie rozjechac. Stan "licze" to tylko chwila przed
# pierwszym pomiarem po otwarciu okna, nie werdykt.
# P59d ($inst = Stan-Instalacji): bez modulow, ktore dopisuja tekst do rozmow (Wiedza,
# Lore, Kierownik), zero w rachunku nie jest "nie wiem", tylko odpowiedzia - zolte
# "nie wiadomo" przy samej bazie byloby falszywym alarmem.
# 06.10.2026: kazde uzywane narzedzie ma wlasny rachunek (Claude Code, Codex, OpenCode) -
# glowne idzie w udzial.*, pozostale w narz.N.mr; werdykt mowi o kazdym (Inne-Narzedzia-Werdyktu).
function Werdykt-Kosztu($start, $rachunek, $cykl, $zuzycie = $null, $inst = $null) {
  $w = [pscustomobject]@{ Stan = "licze"; Zdanie = ""; Wyjasnienie = ""; Nauka = ""; Prog = $null; Proc = "" }
  if ($null -eq $start) {
    $w.Zdanie = "Liczę, ile kosztuje MegaRuchacz - to potrwa kilka sekund..."
    return $w
  }
  $k = $null
  if ($rachunek) { $k = $rachunek.Klucze }
  $w.Prog = Liczba-Z-Klucza $k "udzial.prog_tokeny"
  $mr  = Liczba-Z-Klucza $k "udzial.mr"
  $mrS = Liczba-Z-Klucza $k "udzial.start"
  $o = Opis-Startu $start
  # P17: nauka w tokenach i jako udzial w calym dziennym zuzyciu - procent
  # otwarcia okna rozmowy nic nie mowil przy koszcie dziennym.
  # Krotko, zeby werdykt zostal jednym akapitem, a okno miescilo sie bez
  # przewijania; pelne zdanie z srednia stoi w karcie nauki.
  if ($cykl -and ($null -ne $cykl.Koszt)) {
    $w.Nauka = "Osobno, raz dziennie, czyta Twoje rozmowy, żeby się uczyć: ostatnio $(Tokeny-Okolo $cykl.Koszt) tokenów"
    if ($zuzycie -and ($zuzycie.Stan -eq "jest")) {
      $w.Nauka += ", ok. $(Procent-Udzialu ([double]$cykl.Koszt) ([double]$zuzycie.Srednia)) Twojego dziennego zużycia tokenów."
    } else { $w.Nauka += " ($(Bez-Porownania $zuzycie))." }
  }
  if ($o.Zmierzone) { $w.Proc = $o.MrProc }
  if ($null -eq $w.Prog) {
    $pw = "rachunek MegaRuchacza go nie podał"
    if ($rachunek -and $rachunek.Powod) { $pw = "rachunek MegaRuchacza się nie policzył: $($rachunek.Powod)" }
    elseif (-not $rachunek) { $pw = "rachunek MegaRuchacza się nie policzył" }
    $w.Stan = "nie wiadomo"
    $w.Zdanie = "Nie wiadomo, czy MegaRuchacz kosztuje dużo, czy mało."
    $w.Wyjasnienie = "Nie znam progu, od którego jest drogo ($pw)."
    # Liczba bez rachunku - z pomiaru otwarcia okna (-Start liczy te same pliki).
    if (($null -ne $o.Mr) -and ($o.Mr -gt 0)) {
      $ile = "~$(Okolo $o.Mr) tokenów"
      if ($w.Proc) { $ile += " ($($w.Proc) otwarcia okna rozmowy)" }
      $w.Wyjasnienie = "Sam MegaRuchacz dokłada $ile przy każdym otwarciu okna rozmowy, ale nie znam progu, od którego jest drogo ($pw)."
    }
    return $w
  }
  # Zero za start to nie "za darmo", tylko "nie bylo czego policzyc" (brak CLAUDE.md,
  # plik sie nie czyta, nie ma w nim niczego od MegaRuchacza) - tak mowi sam rachunek.
  if (($null -eq $mr) -or ($null -eq $mrS) -or ($mrS -le 0)) {
    $doklejaja = @(@("wiedza", "lore", "kierownik") | Where-Object { Modul-Jest $inst $_ })
    if ($inst -and -not $inst.Blad -and ($doklejaja.Count -eq 0) -and (($null -eq $mr) -or ($mr -le 0))) {
      $w.Stan = "malo"
      $w.Zdanie = "MegaRuchacz nic nie dokłada do otwarcia okna rozmowy."
      $w.Wyjasnienie = "Nie masz zainstalowanych modułów, które dopisują tekst do rozmów (Wiedza, Lore, Kierownik) - pracują tylko aplikacja przy zegarze i aktualizacje$(if (Modul-Jest $inst 'skille') { ', opieka nad skillami' })$(if (Modul-Jest $inst 'kopia') { ', kopia zapasowa' })."
      return $w
    }
    $w.Stan = "nie wiadomo"
    $w.Zdanie = "Nie wiadomo, czy MegaRuchacz kosztuje dużo, czy mało."
    $w.Wyjasnienie = ("Rachunek nie zmierzył, ile MegaRuchacz dokłada przy otwarciu okna rozmowy - nie znalazł ani jego zasad, ani wiedzy wczytywanej na starcie " +
                      "(co dokładnie, pokazuje zakładka Szczegóły). Nie ma czego porównać z progiem.")
    # pozostale uzywane narzedzia i tak maja swoje liczby - nie wolno ich przemilczec
    $glN = Kto-Wczytuje $start $k
    if ($glN -eq "Claude") { $glN = "Claude Code" }
    foreach ($n in (Inne-Narzedzia-Werdyktu $k $glN)) { $w.Wyjasnienie += " " + (Zdanie-Narzedzia-Werdyktu $n.Nazwa $n.Mr $n.Otwarcie) }
    return $w
  }
  # Bez zmierzonej calosci procentu nie ma - werdykt zapada i tak (prog jest w tokenach),
  # a zdanie mowi, czemu procentu brak. Nigdy 0% i nigdy zgadniety procent.
  # P71: liczby moga byc Codeksa albo OpenCode (komputer bez Claude Code) - zdanie nazywa
  # narzedzie, ktorego otwarcie mierzono, a nie zawsze Claude'a.
  $kto = Kto-Wczytuje $start $k
  # Gdzie liczono: bez procentu zdanie nie nazywaloby narzedzia wcale - "w OpenCode",
  # "w Codeksie"; u Claude Code zdania zostaja jak dotad (pusty dopisek).
  $gdzie = ""
  if ($kto -ne "Claude") { $gdzie = " $(Miejsce-Narzedzia $kto)" }
  $bezProcentu = ""
  if (-not $w.Proc) { $bezProcentu = " Jaką to część wszystkiego, co $kto wczytuje przy otwarciu okna, nie wiem, bo $("$($o.Powod)".TrimEnd('.', ' '))." }
  $ile = "~$(Okolo $mr) tokenów"
  if ($mr -gt $w.Prog) {
    $w.Stan = "duzo"
    if ($w.Proc) {
      $w.Zdanie = "MegaRuchacz kosztuje dużo: dokłada $($w.Proc) do tego, co $kto wczytuje przy każdym otwarciu nowego okna rozmowy."
      $w.Wyjasnienie = "To $ile przy każdym otwarciu okna$gdzie, a drogo robi się już od ~$(Okolo $w.Prog) tokenów - warto odchudzić jego zasady albo wiedzę (co ile waży, pokazuje zakładka Szczegóły)."
    } else {
      $w.Zdanie = "MegaRuchacz kosztuje dużo: dokłada $ile przy każdym otwarciu nowego okna rozmowy$gdzie."
      $w.Wyjasnienie = "Drogo robi się już od ~$(Okolo $w.Prog) tokenów - warto odchudzić jego zasady albo wiedzę (co ile waży, pokazuje zakładka Szczegóły).$bezProcentu"
    }
  } else {
    $w.Stan = "malo"
    if ($w.Proc) {
      $w.Zdanie = "MegaRuchacz kosztuje mało: dokłada $($w.Proc) do tego, co $kto wczytuje przy każdym otwarciu nowego okna rozmowy."
      $w.Wyjasnienie = "Drogo byłoby, gdyby MegaRuchacz urósł o $(Wzrost-Do-Progu $mr $w.Prog) (dziś $ile przy otwarciu okna$gdzie)."
    } else {
      $w.Zdanie = "MegaRuchacz kosztuje mało: dokłada $ile przy każdym otwarciu nowego okna rozmowy$gdzie."
      $w.Wyjasnienie = "Drogo byłoby, gdyby MegaRuchacz urósł o $(Wzrost-Do-Progu $mr $w.Prog).$bezProcentu"
    }
  }
  # Kilka narzedzi naraz: werdykt mowi o kazdym, ktorego uzywasz - glowne wyzej, pozostale
  # zdaniem na narzedzie. Drogie inne narzedzie przy tanim glownym zmienia werdykt na
  # "dużo" i to ono staje w zdaniu (ten sam prog w tokenach, kazde liczone osobno).
  $glowne = $kto
  if ($glowne -eq "Claude") { $glowne = "Claude Code" }
  $inne = Inne-Narzedzia-Werdyktu $k $glowne
  if ($inne.Count -gt 0) {
    $drogie = @($inne | Where-Object { $_.Mr -gt $w.Prog })
    if (($drogie.Count -gt 0) -and ($w.Stan -ne "duzo")) {
      $d0 = $drogie[0]
      $w.Stan = "duzo"
      $w.Zdanie = "MegaRuchacz kosztuje dużo $(Miejsce-Narzedzia $d0.Nazwa): dokłada ~$(Okolo $d0.Mr) tokenów przy każdym otwarciu nowego okna rozmowy."
      $w.Wyjasnienie = ("Drogo robi się już od ~$(Okolo $w.Prog) tokenów - warto odchudzić jego zasady albo wiedzę (co ile waży, pokazuje zakładka Szczegóły). " +
                        (Zdanie-Narzedzia-Werdyktu $glowne $mr $(if ($w.Proc) { $o.Razem } else { $null })))
      $inne = @($inne | Where-Object { $_.Nazwa -ne $d0.Nazwa })
    }
    foreach ($n in $inne) { $w.Wyjasnienie = ("$($w.Wyjasnienie) " + (Zdanie-Narzedzia-Werdyktu $n.Nazwa $n.Mr $n.Otwarcie)).Trim() }
  }
  return $w
}

# "w Claude Code", "w Codeksie", "w OpenCode" - gdzie MegaRuchacz doklada (werdykt).
function Miejsce-Narzedzia([string]$nazwa) {
  switch ($nazwa) {
    "Claude"      { return "w Claude Code" }
    "Claude Code" { return "w Claude Code" }
    "Codex"       { return "w Codeksie" }
  }
  return "w $nazwa"
}

# Pozostale narzedzia do werdyktu (klucze narz.N.* z koszt-pamieci.ps1 -Dane): tylko te,
# ktorych UZYWASZ (rozmowa w 14 dniach), inne niz glowne, z czescia MegaRuchacza z ich
# rachunku (narz.N.mr). Stary rachunek bez tych kluczy = pusta lista, werdykt jak dotad.
function Inne-Narzedzia-Werdyktu($k, [string]$glowne) {
  $l = @()
  $ile = Liczba-Z-Klucza $k "narzedzia"
  if (-not $ile) { return ,$l }
  for ($i = 1; $i -le $ile; $i++) {
    $nazwa = Tekst-Z-Klucza $k "narz.$i.nazwa"
    if ((-not $nazwa) -or ($nazwa -eq $glowne) -or ((Tekst-Z-Klucza $k "narz.$i.uzywane") -ne "1")) { continue }
    $mr = Liczba-Z-Klucza $k "narz.$i.mr"
    if ($null -eq $mr) { continue }
    $l += [pscustomobject]@{ Nazwa = $nazwa; Mr = $mr; Otwarcie = (Liczba-Z-Klucza $k "narz.$i.otwarcie") }
  }
  return ,$l
}

# Jedno zdanie o jednym narzedziu, zawsze z jednostka: "W OpenCode MegaRuchacz dokłada
# ~2 000 tokenów przy każdym otwarciu okna rozmowy (9% tego, co OpenCode wczytuje)."
# Bez zmierzonego otwarcia - bez procentu; zero = rachunek nic nie znalazl, nie "za darmo".
function Zdanie-Narzedzia-Werdyktu([string]$nazwa, $mr, $calosc) {
  $miejsce = Miejsce-Narzedzia $nazwa
  $miejsce = $miejsce.Substring(0, 1).ToUpper() + $miejsce.Substring(1)
  if (($null -eq $mr) -or ($mr -le 0)) {
    return "$miejsce rachunek nie znalazł niczego od MegaRuchacza w tym, co $nazwa wczytuje przy otwarciu okna rozmowy."
  }
  $z = "$miejsce MegaRuchacz dokłada ~$(Okolo $mr) tokenów przy każdym otwarciu okna rozmowy"
  if (($null -ne $calosc) -and ($calosc -gt 0)) { $z += " ($(Procent-Ludzko ([double]$mr) ([double]$calosc)) tego, co $nazwa wczytuje)" }
  return "$z."
}

# Kto wczytuje otwarcie okna rozmowy, o ktorym mowi werdykt (P71): glowne narzedzie tej
# maszyny - to, ktorego otwarcie zmierzyl -Start (Sesje.Narzedzie, Narzedzie), a bez
# pomiaru to, ktorego rachunek idzie w udzial.* (klucz "narzedzie" z -Dane). Claude Code
# mowi o sobie krotko "Claude"; bez zadnej z tych liczb - jak dotad "Claude".
function Kto-Wczytuje($start, $k) {
  $n = ""
  if ($start -and $start.Sesje -and $start.Sesje.Narzedzie) { $n = "$($start.Sesje.Narzedzie)" }
  elseif ($start -and $start.PSObject.Properties["Narzedzie"] -and $start.Narzedzie) { $n = "$($start.Narzedzie)" }
  if (-not $n) { $n = Tekst-Z-Klucza $k "narzedzie" }
  if ((-not $n) -or ($n -eq "Claude Code")) { return "Claude" }
  return $n
}

# "ok. 65%" - o ile czesc MegaRuchacza musialaby urosnac, zeby przekroczyc prog.
# Od 10% w gore co 5 (to zapas na oko, nie pomiar co do procenta), ponizej -
# dokladnie, ponizej 1% - "mniej niż 1%" (zero czytaloby sie jak "juz drogo").
function Wzrost-Do-Progu($mr, $prog) {
  $p = 100.0 * ([double]$prog - [double]$mr) / [math]::Max(1.0, [double]$mr)
  if ($p -ge 10) { return "ok. $([int]([math]::Round($p / 5.0) * 5))%" }
  if ($p -ge 1) { return "ok. $([int][math]::Round($p))%" }
  return "mniej niż 1%"
}

# Odczyt pojedynczych kluczy z odpowiedzi -Dane. Brak klucza i smiec to $null /
# pusty tekst - "nie wiem", nigdy zero.
function Liczba-Z-Klucza($k, [string]$klucz) {
  if (-not $k) { return $null }
  $v = "$($k[$klucz])".Trim()
  if ($v -match '^-?\d+$') { return [long]$v }
  return $null
}

function Tekst-Z-Klucza($k, [string]$klucz) {
  if (-not $k) { return "" }
  return "$($k[$klucz])".Trim()
}

# Alarmy policzone w koszt-pamieci.ps1 - surowe, bez ogonkow. Po polsku ubiera
# je Alarm-Z-Rachunku nizej; tu tylko je wyjmujemy.
function Alarmy-Rachunku($rachunek) {
  $lista = @()
  if ((-not $rachunek) -or (-not $rachunek.Klucze)) { return ,$lista }
  $k = $rachunek.Klucze
  $ile = Liczba-Z-Klucza $k "alarmy"
  if ($null -eq $ile) { return ,$lista }
  for ($i = 1; $i -le $ile; $i++) {
    $lista += [pscustomobject]@{
      Temat  = (Tekst-Z-Klucza $k "alarm.$i.temat")
      Waga   = (Tekst-Z-Klucza $k "alarm.$i.waga")
      Liczba = (Liczba-Z-Klucza $k "alarm.$i.liczba")
      Prog   = (Liczba-Z-Klucza $k "alarm.$i.prog")
      Okres  = (Tekst-Z-Klucza $k "alarm.$i.okres")
      Krotko = (Tekst-Z-Klucza $k "alarm.$i.krotko")
      Pelny  = (Tekst-Z-Klucza $k "alarm.$i.pelny")
    }
  }
  return ,$lista
}

# Ocena ostatniego dnia nauki: zwykly dzien, nadrabianie, mieszany, nieznany -
# policzona w koszt-pamieci.ps1 (Ocena-Cyklu), tu tylko odczytana.
function Ocena-Nauki($rachunek) {
  $k = $null
  if ($rachunek) { $k = $rachunek.Klucze }
  return [pscustomobject]@{
    Rodzaj         = (Tekst-Z-Klucza  $k "cykl.rodzaj")
    Data           = (Data-Lub-Nic (Tekst-Z-Klucza $k "cykl.data"))
    Tokeny         = (Liczba-Z-Klucza $k "cykl.tokeny")
    Wiadomosci     = (Liczba-Z-Klucza $k "cykl.wiadomosci")
    ZakresOd       = (Tekst-Z-Klucza  $k "cykl.zakres_od")
    ZakresDo       = (Tekst-Z-Klucza  $k "cykl.zakres_do")
    Zwykle         = (Liczba-Z-Klucza $k "cykl.zwykle")
    Nadrabianie    = (Liczba-Z-Klucza $k "cykl.nadrabianie")
    Typowy         = (Liczba-Z-Klucza $k "cykl.typowy_dzien")
    TypowychDni    = (Liczba-Z-Klucza $k "cykl.typowych_dni")
    Prog           = (Liczba-Z-Klucza $k "cykl.prog")
    Wzrosty        = (Liczba-Z-Klucza $k "cykl.wzrosty")
    WzrostOd       = (Data-Lub-Nic (Tekst-Z-Klucza $k "cykl.wzrost_od"))
    WzrostOdTokeny = (Liczba-Z-Klucza $k "cykl.wzrost_od_tokeny")
    WzrostDo       = (Data-Lub-Nic (Tekst-Z-Klucza $k "cykl.wzrost_do"))
    WzrostDoTokeny = (Liczba-Z-Klucza $k "cykl.wzrost_do_tokeny")
    ProcWzrostu    = (Liczba-Z-Klucza $k "cykl.proc_wzrostu")
  }
}

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["koszt"] = $true
