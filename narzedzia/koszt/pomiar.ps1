# narzedzia\koszt\pomiar.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz BUDOWA
# w jego naglowku). Pierwszy etap rachunku (Etap-Pomiar): co NAPRAWDE leci do modelu
# na tej maszynie - warstwy CLAUDE.md ($w), ktore narzedzie tu jest ($jestClaude,
# $jestCodex, $jestOpenCode i plik, ktory czyta OpenCode: $wOc, $plikOc), co czytaja hooki Claude Code, ladunki hookow obu narzedzi i lista
# sufitow ($sufity); od P71 takze lista narzedzi AI ($NARZEDZIA_AI -> $narzedzia: ktore
# uzywane, sekcja "## Co wiem" w pliku instrukcji kazdego). Skad wolane: koszt-pamieci.ps1 kropka (". Etap-Pomiar") zaraz
# po sciezkach; zmienne stad czyta caly dalszy przebieg. Funkcje nad etapem uzywa
# tez Etap-Kubelki (Klucz-Sciezki), tryb -Warstwy (Czy-Hook-Czyta) i tryb -Rozbicie
# oraz pelny raport (Powod-Pustej-Sesji).

# --- narzedzia AI tej maszyny ---------------------------------------------------
# JEDNA lista narzedzi, ktore MegaRuchacz zna. Nowe narzedzie (np. OpenCode) to
# jeden wpis tutaj - wykrywanie, szukanie sekcji "## Co wiem", warstwy i pomiar
# tokenow ida po tej liscie, bez kopiowania logiki. Pola (sciezki wzgledem domu):
#   Klucz, Nazwa    - klucz w danych dla okna i nazwa dla czlowieka,
#   Narz            - nazwa w -Narzedzie i w Rachunek-Narzedzia (alarmy.ps1),
#   Instrukcje      - plik instrukcji, ktory narzedzie wczytuje samo na starcie,
#   Rozmowy, Pliki  - katalog transkryptow i wzorzec nazwy pliku rozmowy,
#   Rekurencja      - $true: pliki w podkatalogach dowolnej glebokosci (Codex:
#                     RRRR\MM\DD); $false: jeden poziom (Claude Code: <projekt>\*.jsonl,
#                     glebiej leza workerzy - ich liczy osobno Pomiar-Otwarcia),
#   Historia        - plik dopisywany przy kazdej wiadomosci (najtanszy dowod uzywania),
#   Baza            - rozmowy w bazie SQLite zamiast plikow (OpenCode): ostatnia rozmowa
#                     i pomiar ida z bazy (opencode.ps1), Pliki i Rekurencja nie graja roli,
#   Format          - czytnik transkryptow w otwarcie.ps1 (Pomiar-Narzedzia); pusty =
#                     czytnika jeszcze nie ma i okno mowi to wprost, zamiast zgadywac.
# OpenCode (od 06.10.2026): ~\.config\opencode\AGENTS.md czyta sam na starcie, rozmowy
# trzyma w ~\.local\share\opencode\opencode.db, a ~\.local\state\opencode\prompt-history.jsonl
# dopisuje przy kazdej wiadomosci wpisanej w jego oknie.
$NARZEDZIA_AI = @(
  [pscustomobject]@{ Klucz = "claude"; Nazwa = "Claude Code"; Narz = "Claude"; Instrukcje = ".claude\CLAUDE.md"
                     Rozmowy = ".claude\projects"; Pliki = "*.jsonl"; Rekurencja = $false; Baza = ""
                     Historia = ".claude\history.jsonl"; Format = "claude" },
  [pscustomobject]@{ Klucz = "codex"; Nazwa = "Codex"; Narz = "Codex"; Instrukcje = ".codex\AGENTS.md"
                     Rozmowy = ".codex\sessions"; Pliki = "rollout-*.jsonl"; Rekurencja = $true; Baza = ""
                     Historia = ".codex\history.jsonl"; Format = "codex" },
  [pscustomobject]@{ Klucz = "opencode"; Nazwa = "OpenCode"; Narz = "OpenCode"; Instrukcje = ".config\opencode\AGENTS.md"
                     Rozmowy = ".local\share\opencode"; Pliki = ""; Rekurencja = $false; Baza = ".local\share\opencode\opencode.db"
                     Historia = ".local\state\opencode\prompt-history.jsonl"; Format = "opencode" }
)

# Narzedzie jest UZYWANE na tej maszynie, gdy w ostatnich tylu dniach byla w nim
# rozmowa. 14 = okno pomiaru otwarcia sesji (Pomiar-Otwarcia, otwarcie.ps1): narzedzie
# "uzywane" ma wtedy zawsze z czego zmierzyc, wiec brak pomiaru u uzywanego jest
# prawdziwa usterka, a nie falszywy alarm. Sam plik instrukcji niczego nie dowodzi -
# ~\.codex\AGENTS.md i ~\.claude\CLAUDE.md zaklada takze instalator MegaRuchacza.
$DniUzywania = 14

# Transkrypty narzedzia zmienione od $odKiedy, najnowsze pierwsze. Brak katalogu to
# pusta lista; nieczytelny podkatalog to wpis w $n.Bledy, nie cisza.
function Pliki-Rozmow($n, $odKiedy) {
  if (-not (Test-Path -LiteralPath $n.KatRozmow -PathType Container)) { return @() }
  $bl = @()
  if ($n.Rekurencja) {
    $pl = @(Get-ChildItem -LiteralPath $n.KatRozmow -Recurse -Filter $n.Pliki -File -ErrorAction SilentlyContinue -ErrorVariable +bl)
  } else {
    $pl = @(Get-ChildItem -LiteralPath $n.KatRozmow -Directory -ErrorAction SilentlyContinue -ErrorVariable +bl |
      ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter $n.Pliki -File -ErrorAction SilentlyContinue -ErrorVariable +bl })
  }
  foreach ($b in @($bl)) {
    $t = "nie przejrzalem czesci $($n.KatRozmow) ($b)"
    if (@($n.Bledy) -notcontains $t) { $n.Bledy += $t }
  }
  return @($pl | Where-Object { $_.LastWriteTime -ge $odKiedy } | Sort-Object LastWriteTime -Descending)
}

# Lista $NARZEDZIA_AI z tym, co o kazdym wiadomo na tej maszynie: czy jest plik
# instrukcji, kiedy byla ostatnia rozmowa i czy narzedzie jest uzywane.
function Narzedzia-Maszyny {
  $od = (Get-Date).AddDays(-$DniUzywania)
  $lista = @()
  foreach ($d in $NARZEDZIA_AI) {
    $n = [pscustomobject]@{
      Klucz = $d.Klucz; Nazwa = $d.Nazwa; Narz = $d.Narz; Format = "$($d.Format)"
      Instrukcje = (Join-Path $KatalogDomowy $d.Instrukcje); KatRozmow = (Join-Path $KatalogDomowy $d.Rozmowy)
      Pliki = $d.Pliki; Rekurencja = [bool]$d.Rekurencja; Baza = ""
      InstrukcjeJest = $false; Ostatnio = $null; Uzywane = $false; Bledy = @(); Warstwy = $null
    }
    if ($d.Baza) { $n.Baza = Join-Path $KatalogDomowy $d.Baza }
    $n.InstrukcjeJest = Test-Path -LiteralPath $n.Instrukcje -PathType Leaf
    if ($d.Historia) {
      $hist = Join-Path $KatalogDomowy $d.Historia
      if (Test-Path -LiteralPath $hist -PathType Leaf) {
        try { $n.Ostatnio = (Get-Item -LiteralPath $hist -Force -ErrorAction Stop).LastWriteTime }
        catch { $n.Bledy += "nie odczytalem daty $hist ($($_.Exception.Message))" }
      }
    }
    # Historia swieza wystarcza; inaczej najnowszy transkrypt (Codex bez history.jsonl)
    # albo najnowsza rozmowa w bazie (OpenCode). Data samego pliku bazy niczego nie
    # dowodzi - zmienia ja takze cykl wiedzy, ktory przez OpenCode wylawia fakty.
    if ((-not $n.Ostatnio) -or ($n.Ostatnio -lt $od)) {
      if ($n.Baza) {
        $naj = Ostatnia-Rozmowa-OpenCode $n
        if ($naj -and ((-not $n.Ostatnio) -or ($naj -gt $n.Ostatnio))) { $n.Ostatnio = $naj }
      } else {
        $naj = @(Pliki-Rozmow $n $od) | Select-Object -First 1
        if ($naj -and ((-not $n.Ostatnio) -or ($naj.LastWriteTime -gt $n.Ostatnio))) { $n.Ostatnio = $naj.LastWriteTime }
      }
    }
    $n.Uzywane = ($null -ne $n.Ostatnio) -and ($n.Ostatnio -ge $od)
    $lista += $n
  }
  return $lista
}

function Narzedzie-Po-Kluczu($klucz) {
  return (@($narzedzia | Where-Object { $_.Klucz -eq $klucz }) | Select-Object -First 1)
}

# "Claude Code", "Claude Code i Codex", "A, B i C" - nazwy uzywanych narzedzi.
function Nazwy-Narzedzi($lista) {
  $n = @($lista | ForEach-Object { $_.Nazwa })
  if ($n.Count -le 1) { return ($n -join "") }
  return (($n[0..($n.Count - 2)] -join ", ") + " i " + $n[-1])
}

function Powod-Pustej-Sesji($sciezkaClaude) {
  # dlaczego rachunek za start sesji wyszedl pusty - zdanie do wypisania zamiast
  # zera, bo zero czyta sie jak "za darmo", a to znaczy "nie bylo czego policzyc".
  # Sciezka idzie parametrem, zeby to samo zdanie dalo sie pokazac i pelna
  # sciezka (raport), i skrocona (rozbicie).
  if (-not $w.Jest) {
    if ($w.Blad) { return "plik $sciezkaClaude jest, ale nie da sie go odczytac" }
    return "nie ma pliku $sciezkaClaude"
  }
  if (-not $w.MaSekcje) { return "w $sciezkaClaude nie ma ani bloku zasad, ani sekcji '## Co wiem'" }
  return "w $sciezkaClaude nie ma nic do policzenia i zaden hook nie wstrzykuje zasad"
}

# Ten sam plik czytamy raz na zdarzenie - jego usterka ma trafic do Uwag raz.
function Dodaj-Uwage($tekst) {
  if (@($script:UwagiWarstw) -notcontains $tekst) { $script:UwagiWarstw += $tekst }
}

function Polecenia-Hookow($plik, $zdarzenie) {
  $wynik = @()
  if (-not (Test-Path -LiteralPath $plik -PathType Leaf)) { return $wynik }
  $tekst = $null
  try { $tekst = Czytaj $plik }
  catch {
    Dodaj-Uwage "nie da sie odczytac $plik ($($_.Exception.Message)) - nie wiem, co czytaja zapisane tam hooki"
    return $wynik
  }
  $j = $null
  try { $j = $tekst | ConvertFrom-Json }
  catch {
    Dodaj-Uwage "$plik nie jest poprawnym JSON-em ($($_.Exception.Message)) - nie wiem, co czytaja zapisane tam hooki"
    return $wynik
  }
  if (-not $j -or -not $j.hooks) { return $wynik }
  foreach ($grupa in @($j.hooks.$zdarzenie)) {
    if (-not $grupa) { continue }
    foreach ($h in @($grupa.hooks)) {
      if (-not $h) { continue }
      $wynik += ("" + $h.command + " " + $h.commandWindows)
    }
  }
  return $wynik
}

function Klucz-Sciezki($sciezka) { return ("$sciezka" -replace '/', '\').ToLowerInvariant() }

# Ile bajtow pliku instrukcji narzedzie wczytuje - z JEDNEJ listy narzedzi AI
# (narzedzia\kierownik-cele.ps1 Narzedzia-AI, pole Limit; 0 = bez limitu). Do 06.10
# sufit Codeksa szedl z $LIMIT_AGENTS w straznik-zasad.ps1 (32 768 B) - falszywy dla
# globalnego ~\.codex\AGENTS.md, ktory Codex czyta w calosci (dowod przy polu Limit),
# wiec plik ~36 KB dawal pilny alarm "UCINA PO CICHU" o czyms, czego nic nie ucina.
# Liste wczytujemy we wlasnym zasiegu (& { . plik }), zeby jej funkcje i zmienne nie
# mieszaly sie z rachunkiem. .Limit - liczba z listy albo $null; .Blad - dlaczego $null.
function Limit-Z-Listy-Narzedzi([string]$id) {
  $wynik = [pscustomobject]@{ Limit = $null; Blad = $null }
  $plik = Join-Path $Zrodlo "narzedzia\kierownik-cele.ps1"
  if (-not (Test-Path -LiteralPath $plik -PathType Leaf)) { $wynik.Blad = "nie ma pliku $plik"; return $wynik }
  $n = $null
  try { $n = & { param($p, $i) . $p; Narzedzie-AI $i } $plik $id }
  catch {
    $wynik.Blad = "nie wczytalem listy narzedzi z $plik ($($_.Exception.Message))"
    return $wynik
  }
  if (-not $n) { $wynik.Blad = "w $plik (Narzedzia-AI) nie ma narzedzia '$id'"; return $wynik }
  if (($n.PSObject.Properties.Name -notcontains "Limit") -or ($null -eq $n.Limit)) {
    $wynik.Blad = "w $plik (Narzedzia-AI) narzedzie '$id' nie ma pola Limit"
    return $wynik
  }
  $wynik.Limit = [long]$n.Limit
  return $wynik
}

# Czy ktorys hook naprawde wczytuje ten plik - po pelnej sciezce w poleceniu,
# z $CLAUDE_PROJECT_DIR podmienionym na katalog projektu.
function Czy-Hook-Czyta($polecenia, $sciezka, $katProj) {
  if (-not $sciezka) { return $false }
  $cel = Klucz-Sciezki $sciezka
  foreach ($pol in @($polecenia)) {
    $t = "$pol"
    if ($katProj) { $t = $t.Replace('$CLAUDE_PROJECT_DIR', $katProj) }
    if ((Klucz-Sciezki $t).Contains($cel)) { return $true }
  }
  return $false
}

# Etap-Pomiar - warstwy, narzedzia na maszynie, hooki, ladunki i sufity.
# Wola go koszt-pamieci.ps1 KROPKA (". Etap-Pomiar"), wiec biegnie w zasiegu skryptu
# glownego: zmienne i funkcje, ktore tu powstaja, widzi dalszy przebieg - tak samo,
# jak gdy ten kod stal w koszt-pamieci.ps1 wprost.
function Etap-Pomiar {
  $w = Zmierz-Warstwy $plikClaude

  # jednym zdaniem: dlaczego z CLAUDE.md nic nie policzylismy. Brak pliku i plik
  # nie do odczytania to dwa rozne powody i wszedzie nizej podajemy ten wlasciwy.
  $powodBrakuClaude = "nie ma pliku $plikClaude"
  if ($w.Blad) { $powodBrakuClaude = $w.Blad }

  # --- sufity: pomiary ---------------------------------------------------------

  $listaCx      = Limit-Z-Listy-Narzedzi "codex"
  $limitAgents  = $listaCx.Limit
  $limitZasad   = Limit-Hooka $plikHookow "zasady-sesja.json"
  $limitPrzyp   = Limit-Hooka $plikHookow "przypomnienie.json"
  $limitWejscia = Limit-Z-Pliku $plikFaktow  '(?m)^MAX_INPUT_CHARS\s*=\s*([\d_]+)'
  $limitKawalka = Limit-Z-Pliku $plikIndeksu '(?m)^CHUNK_SIZE\s*=\s*([\d_]+)'

  # AGENTS.md Codeksa - sufit (gdy jest) jest w BAJTACH, bo tyle czyta Codex
  $agentsTresc = Czytaj-Cicho $plikAgents
  $agentsBajty = $null
  if ($agentsTresc -ne $null) {
    try { $agentsBajty = [long](Get-Item -LiteralPath $plikAgents).Length } catch { $agentsBajty = $null }
  }

  # KTORE narzedzie naprawde siedzi na tej maszynie. Od tego zalezy, co wchodzi do
  # rachunkow nizej: liczymy to, co NAPRAWDE leci do modelu tutaj, a nie to, co
  # poleci u kogos innego. Codeksa poznajemy po jego pliku instrukcji, Claude Code
  # po plikach, ktore prowadzi sam - katalog ~\.claude zaklada takze MegaRuchacz,
  # wiec sam katalog nie dowodzi niczego (to samo rozroznienie robi
  # narzedzia\straznik-zasad.ps1 w Cisza-Claude-Linia).
  $jestCodex  = ($agentsTresc -ne $null)
  $jestClaude = ((Test-Path -LiteralPath (Join-Path $katKlaudii "history.jsonl")) -or
                 (Test-Path -LiteralPath (Join-Path $KatalogDomowy ".claude.json")))

  # Ktorego narzedzia NAPRAWDE uzywasz (rozmowa w ostatnich $DniUzywania dniach) i co
  # stoi w jego pliku instrukcji. "Jest" wyzej mowi, czyj rachunek liczyc; "uzywane"
  # mowi, czego brak jest usterka, a czego brak "nie dotyczy" - warstwy, pomiar tokenow
  # i sprawy w oknie pytaja o to drugie. Sekcje "## Co wiem" mierzymy w pliku instrukcji
  # KAZDEGO narzedzia: Codex ja ma w ~\.codex\AGENTS.md, Claude Code w ~\.claude\CLAUDE.md,
  # OpenCode w ~\.config\opencode\AGENTS.md.
  $narzedzia = @(Narzedzia-Maszyny)
  foreach ($n in $narzedzia) {
    if ((Klucz-Sciezki $n.Instrukcje) -eq (Klucz-Sciezki $plikClaude)) { $n.Warstwy = $w }
    else { $n.Warstwy = Zmierz-Warstwy $n.Instrukcje }
  }

  # OpenCode (rachunek od 06.10.2026). Jest na maszynie, gdy lezy jego plik instrukcji
  # albo baza rozmow, albo gdy go uzywasz. Czyta ~\.config\opencode\AGENTS.md, a gdy tego
  # pliku nie ma - ~\.claude\CLAUDE.md (zgodnosc z Claude Code; to samo zaklada wtyczka
  # szablony-opencode\plugins\mr-log.js). $wOc to warstwy pliku, ktory NAPRAWDE czyta,
  # $plikOc - jego sciezka, $ocZastepczy - czy to CLAUDE.md zamiast wlasnego AGENTS.md.
  $nOc = Narzedzie-Po-Kluczu "opencode"
  $jestOpenCode = [bool]($nOc -and ($nOc.InstrukcjeJest -or $nOc.Uzywane -or
                  ($nOc.Baza -and (Test-Path -LiteralPath $nOc.Baza -PathType Leaf))))
  $wOc = $null; $plikOc = $null; $ocZastepczy = $false
  if ($jestOpenCode) {
    if ($nOc.InstrukcjeJest) { $wOc = $nOc.Warstwy; $plikOc = $nOc.Instrukcje }
    elseif ($w.Jest -or $w.Blad) { $wOc = $w; $plikOc = $plikClaude; $ocZastepczy = $true }
  }
  # Wtyczka MegaRuchacza w projekcie (<projekt>\.opencode\plugins\mr-log.js) dokleja
  # <projekt>\.megaruchacz\zasady-kierownika.md jako plik instrukcji - ale tylko wtedy,
  # gdy zasad kierownika nie ma ani w AGENTS.md projektu, ani w globalnym pliku, ktory
  # OpenCode czyta (te same znaczniki, co w jej funkcji maZasady). Bez -Projekt nie wiemy,
  # w ktorym projekcie otworzy sie rozmowa, wiec tej pozycji wtedy nie ma. Do wiadomosci
  # wtyczka nie dokleja niczego - OpenCode nie ma odpowiednika hooka UserPromptSubmit.
  $zasadyOcTresc = $null; $zasadyOcSkad = $null
  if ($Projekt -and $jestOpenCode -and
      (Test-Path -LiteralPath (Join-Path $Projekt ".opencode\plugins\mr-log.js") -PathType Leaf)) {
    $maZasadyOc = {
      param($t)
      return ("$t".Contains("<!-- MegaRuchacz:start -->") -or "$t".Contains("<!-- MegaRuchacz:kierownik:start -->"))
    }
    $globalnyOc = $plikClaude
    if ($nOc.InstrukcjeJest) { $globalnyOc = $nOc.Instrukcje }
    if (-not ((& $maZasadyOc (Czytaj-Cicho (Join-Path $Projekt "AGENTS.md"))) -or (& $maZasadyOc (Czytaj-Cicho $globalnyOc)))) {
      $p = Join-Path $Projekt ".megaruchacz\zasady-kierownika.md"
      $t = Czytaj-Cicho $p
      if ($t) { $zasadyOcTresc = $t; $zasadyOcSkad = $p }
    }
  }

  # --- co naprawde czytaja hooki Claude Code -----------------------------------
  # Rachunek i tryb -Warstwy pytaja o to samo: ktory plik wczytuje hook. Do
  # 2026-09-25 wiedzial to tylko tryb -Warstwy, a rachunek zgadywal po sciezce -
  # i w trybie globalnym mierzyl kopie przypomnienia, ktorej zaden hook nie czyta.
  # Nieczytelny settings.json to nie cisza: idzie do Uwag (okno pokazuje je nad
  # lista, rachunek - przy pozycji, ktorej dotyczy).
  $script:UwagiWarstw = @()

  # Projekt, w ktorym ogladamy hooki. Bez -Projekt to katalog narzedzia -
  # tak samo wola ten skrypt nadzorca, ktory w zadnym projekcie nie siedzi.
  $katProjektu = $Projekt
  if (-not $katProjektu) { $katProjektu = $Zrodlo }
  $katProjektu = "$katProjektu".TrimEnd('\', '/')
  $trybGlobalny = Test-Path -LiteralPath (Join-Path $katKlaudii ".megaruchacz-global")

  $polStart = @()
  $polWiad  = @()
  foreach ($pu in @((Join-Path $katKlaudii "settings.json"), (Join-Path $katKlaudii "settings.local.json"),
                    (Join-Path $katProjektu ".claude\settings.json"), (Join-Path $katProjektu ".claude\settings.local.json"))) {
    $polStart += @(Polecenia-Hookow $pu "SessionStart")
    $polWiad  += @(Polecenia-Hookow $pu "UserPromptSubmit")
  }

  # Ktory ladunek przypomnienia NAPRAWDE leci: ten, ktory hook UserPromptSubmit
  # podaje narzedzia\przypomnienie.js. Pierwszy trafiony wygrywa (globalny
  # settings.json jest czytany pierwszy).
  $przypUzywany = $null
  foreach ($pol in $polWiad) {
    $m = [regex]::Match("$pol", 'przypomnienie\.js"?\s+(?:"(?<a>[^"]+)"|(?<a>\S+))')
    if ($m.Success) {
      $przypUzywany = ($m.Groups['a'].Value.Replace('$CLAUDE_PROJECT_DIR', $katProjektu) -replace '/', '\')
      break
    }
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
  # Zdanie do wypisania przy rachunku, gdy liczba NIE pochodzi z pliku wskazanego
  # przez hook albo gdy tego pliku nie da sie zmierzyc - $null, gdy wszystko gra.
  $przypCcUwaga = $null
  # Tryb globalny (~\.claude\.megaruchacz-global): przypomnienie czyta hook
  # z globalnego settings.json, np. ~\.claude\mr\orchestrator-reminder.json - i TEN
  # plik mierzymy, a nie kopie w projekcie. Do 2026-09-25 rachunek mierzyl kopie;
  # liczby zgadzaly sie tylko dlatego, ze obie mialy akurat po 725 znakow.
  # Gdy hook wskazuje plik bez ladunku, do modelu nie leci nic - kopia zastepcza
  # podalaby wtedy liczbe, ktorej nikt nie wysyla, wiec jej nie bierzemy.
  $przypZHooka = ($trybGlobalny -and $przypUzywany)
  if ($przypZHooka) {
    $t = Ladunek-Hooka $przypUzywany
    if ($t) {
      $przypCcTresc = $t; $przypCcSkad = $przypUzywany
    } elseif (-not (Test-Path -LiteralPath $przypUzywany -PathType Leaf)) {
      $przypCcUwaga = "hook UserPromptSubmit czyta $przypUzywany, a tego pliku nie ma - do wiadomosci nie dokleja sie nic"
    } else {
      $przypCcUwaga = "hook UserPromptSubmit czyta $przypUzywany, ale nie ma w nim pola hookSpecificOutput.additionalContext - do wiadomosci nie dokleja sie nic"
    }
  }
  if ((-not $przypZHooka) -and $Projekt) {
    $p = Join-Path $Projekt ".claude\orchestrator-reminder.json"
    $t = Ladunek-Hooka $p
    if ($t) { $przypCcTresc = $t; $przypCcSkad = $p }
  }
  # Kopia z katalogu narzedzia ratuje przebieg bez -Projekt (tak chodzi rachunek
  # pokazywany przy starcie sesji): wdrozenia roznia sie wtedy tylko sciezka.
  # Ale TYLKO na maszynie, na ktorej Claude Code w ogole jest. Bez tego warunku
  # wdrozenie z samym Codeksem dostawalo w rachunku ladunek Claude'a wziety
  # z katalogu narzedzia - liczbe, ktorej nikt nikomu nie wysyla - a pozycja
  # Codeksa nie pokazywala sie nigdy (sprawdzone 2026-09-17).
  if ((-not $przypZHooka) -and (-not $przypCcTresc) -and $jestClaude) {
    $p = Join-Path $Zrodlo ".claude\orchestrator-reminder.json"
    $t = Ladunek-Hooka $p
    if ($t) { $przypCcTresc = $t; $przypCcSkad = $p }
  }
  # Tryb globalny bez hooka, ktory wskazuje przypomnienie (settings.json nieczytelny
  # albo hook zdjety) - liczba z kopii to zgadywanie i ma to byc napisane.
  if ($trybGlobalny -and (-not $przypUzywany) -and $przypCcTresc) {
    $przypCcUwaga = "w trybie globalnym zaden hook UserPromptSubmit w settings.json nie wskazuje przypomnienia - liczona kopia zastepcza $przypCcSkad, moze nie trafiac do modelu wcale"
    if (@($script:UwagiWarstw).Count -gt 0) { $przypCcUwaga += " (" + (@($script:UwagiWarstw) -join "; ") + ")" }
  }
  # Modul kierownik wylaczony w rejestrze instalacji (P59a, koszt-pamieci.ps1): przypomnienie.js nie
  # dokleja ladunku z pliku ani w Claude Code, ani w Codeksie - liczba z pliku bylaby kosztem, ktorego
  # nikt nie placi. Linia cyklu i "Z ARCHIWUM" sa doklejane dalej, ale tych nie liczylismy nigdy.
  if ($script:KierownikWylaczony) {
    $przypCcTresc = $null; $przypCcSkad = $null
    $przypCcUwaga = "modul kierownik wylaczony w rejestrze instalacji - narzedzia\przypomnienie.js nie dokleja ladunku z pliku"
    $przypTresc = $null; $przypSkad = $null; $przypZnaki = $null
  }
  $przypCcZnaki = $null
  if ($przypCcTresc) { $przypCcZnaki = $przypCcTresc.Length }

  # Zasady kierownika wstrzykiwane hookiem startowym po stronie Claude Code.
  # Szablonu tu NIE mierzymy: szablon sam z siebie nikomu nic nie wysyla, wiec
  # doliczony do rachunku podawalby koszt, ktorego nikt nie placi.
  $zasadyCcTresc = $null
  $zasadyCcSkad  = $null
  # W trybie globalnym zasady kierownika ida blokiem w ~\.claude\CLAUDE.md (liczony
  # nizej), a straznik zdejmuje hook "cat ...megaruchacz-sesja.json" jako duplikat.
  # Ladunek, ktorego zaden hook SessionStart nie czyta, doliczylby te same zasady
  # drugi raz - wiec wtedy go pomijamy i mowimy o tym w raporcie.
  $zasadyCcPominiete = $null
  if ($Projekt) {
    $p = Join-Path $Projekt ".claude\megaruchacz-sesja.json"
    $t = Ladunek-Hooka $p
    if ($t) {
      if ($trybGlobalny -and -not (Czy-Hook-Czyta $polStart $p $katProjektu)) { $zasadyCcPominiete = $p }
      else { $zasadyCcTresc = $t; $zasadyCcSkad = $p }
    }
  }

  $sufity = @()

  $sufity += Sufit ([ordered]@{
    Nazwa      = "pamiec stala w CLAUDE.md (sekcja 'Co wiem')"
    Krotka     = "pamiec stala"
    Narzedzie  = "Claude"
    Teraz      = $(if ($w.Jest) { $w.Stala.Znaki } else { $null })
    Limit      = $ProgStalej
    Jednostka  = "znakow"
    Czyj       = "NASZ - sami go sobie ustawilismy"
    SkadLimitu = "narzedzia\koszt-pamieci.ps1 (`$ProgStalej)"
    Plik       = $plikClaude
    Skutek     = "nic sie nie ucina: to prog ostrzegawczy, sygnal zeby przeniesc rzadziej potrzebna wiedze do plikow w wiedza\"
    Ucina      = $false
    Uwaga      = (Powod-Braku $(if ($w.Jest) { $w.Stala.Znaki } else { $null }) $ProgStalej $powodBrakuClaude "tego skryptu")
  })

  # Limit Codeksa z listy narzedzi AI. 0 = Codex czyta plik w calosci - sufitu nie ma,
  # wiec nie ma tez wiersza (wiersz "nie zmierzone" czytalby sie jak usterka). Listy nie
  # da sie odczytac ($null) - wiersz zostaje, z powodem, zamiast cichego "nic nie ucina".
  $skadLimituCx = "narzedzia\kierownik-cele.ps1 (Narzedzia-AI, pole Limit Codeksa)"
  if (($null -eq $limitAgents) -or ($limitAgents -gt 0)) {
    $sufity += Sufit ([ordered]@{
      Nazwa      = "instrukcje dla Codeksa (~\.codex\AGENTS.md)"
      Krotka     = "instrukcje dla Codeksa"
      Narzedzie  = "Codex"
      Teraz      = $agentsBajty
      Limit      = $limitAgents
      Jednostka  = "bajtow"
      Czyj       = "NARZUCONY przez Codeksa - tego nie podniesiemy, trzeba sie zmiescic"
      SkadLimitu = $skadLimituCx
      Plik       = $plikAgents
      Skutek     = "UCINA PO CICHU: Codex czyta tylko poczatek pliku, koniec zasad nie dociera do niego wcale"
      Ucina      = $true
      Tresc      = $agentsTresc
      Uwaga      = (Powod-Braku $agentsBajty $limitAgents "nie ma pliku $plikAgents - Codeksa nie ma na tej maszynie, wiec ten sufit dzis nikogo nie dotyczy" `
                      $(if ($listaCx.Blad) { "$skadLimituCx - $($listaCx.Blad)" } else { $skadLimituCx }))
    })
  }

  $sufity += Sufit ([ordered]@{
    Nazwa      = "zasady kierownika wstrzykiwane Codeksowi przy starcie sesji"
    Krotka     = "zasady dla Codeksa"
    Narzedzie  = "Codex"
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
    Narzedzie  = "Codex"
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
      # Brak ladunku NIE kasuje tu calego wiersza: pominiety wiersz czyta sie jak
      # "tego sufitu nie ma", a jest wprost przeciwnie - jest, tylko nie wiemy,
      # ile pod nim siedzi. Idzie wiec jako pozycja bez pomiaru, z powodem.
      $plikCC = Join-Path $Projekt $paraCC.plik
      $trescCC = Ladunek-Hooka $plikCC
      $znakiCC = $null
      if ($trescCC) { $znakiCC = $trescCC.Length }
      $brakCC = "nie da sie odczytac ladunku z $plikCC"
      if (-not (Test-Path -LiteralPath $plikCC)) {
        $brakCC = "nie ma pliku $plikCC - tego hooka nie ma w tym projekcie (wgrywa go wdroz.ps1)"
      }
      $limitCC = Limit-Hooka $plikUstawien (Split-Path $paraCC.plik -Leaf)
      $sufity += Sufit ([ordered]@{
        Nazwa      = $paraCC.nazwa
        Krotka     = $paraCC.krotka
        Narzedzie  = "Claude"
        Teraz      = $znakiCC
        Limit      = $limitCC
        Jednostka  = "znakow"
        Czyj       = "NARZUCONY przez Claude Code, dopoki nie wpiszemy wlasnego additionalContextLimit do settings.json"
        SkadLimitu = "$plikUstawien (additionalContextLimit hooka $($paraCC.zdarzenie))"
        Plik       = $plikCC
        Skutek     = "UCINA PO CICHU: koniec ladunku przepada, gdy przekroczy sufit narzedzia"
        Ucina      = $true
        Tresc      = $trescCC
        Uwaga      = (Powod-Braku $znakiCC $limitCC $brakCC `
                      "$plikUstawien - nie ma tam additionalContextLimit, wiec sufitem jest wartosc domyslna Claude Code")
      })
    }
  }
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["pomiar"] = $true
