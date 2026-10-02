# Instalator modulu pamieci rozmow "Lore" - stawia calosc jednym poleceniem:
# srodowisko Pythona (uv), rejestracja serwera MCP, zadanie w harmonogramie,
# a na koniec test, czy to naprawde dziala.
#
# Od podzialu na czesci (P59b) to okno konsoli do recznej instalacji i do starych wywolan
# (wdroz.ps1, straznik). Same czesci - kazda do zalozenia i do zdjecia osobno - siedza w
# narzedzia\instalacja\lore-czesci.ps1; instalator z wyborem modulow wola je przez
# narzedzia\instalacja\modul-wiedza.ps1 i modul-lore.ps1 (te prowadza tez rejestr modulow).
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File narzedzia\instaluj-lore.ps1
#   ... -Zrodlo <sciezka>   katalog glowny repozytorium (domyslnie: katalog nad narzedzia\)
#   ... -BezPytania         pomija ekran zgody (dla instalatora nadrzednego, ktory juz ja zebral)
#   ... -Proba              wypisuje, co by zrobil, i NIE robi nic
#   ... -TylkoSprawdz       sam test juz zainstalowanego modulu
#   ... -UsunOdswiezanie    samo sprzatanie: zdejmuje z Harmonogramu stare zadanie
#                           odswiezajace narzedzie oraz zadania cyklu wiedzy
#                           (LoreCykl i spolka) i konczy - nic nie zaklada
#   ... -Czesci <lista>     tylko wybrane czesci: Srodowisko, Indeks, Model, Mcp, Nadzorca, Sprzatanie
#                           (domyslnie wszystkie - tak jak przed podzialem)
#   ... -TylkoTekst         indeks bez modelu wektorow (lore.index --text-only); czesc Model odpada
#   ... -Usun               zdejmuje wybrane czesci (domyslnie: Mcp, Model, Indeks, Srodowisko -
#                           nadzorce tylko jawnie: -Czesci Nadzorca); dane zostaja
#   ... -UsunDane           z -Usun: takze baza rozmow lore.db
#   ... -KatalogDomowy <k>  podmiana katalogu domowego (testy na kopii)
# Rejestru modulow (~\.claude\mr\instalacja.json) ten skrypt nie zmienia.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [string]$KatalogDomowy = $HOME,
  [switch]$BezPytania,
  [switch]$Proba,
  [switch]$TylkoSprawdz,
  [switch]$UsunOdswiezanie,
  # Stara nazwa tego samego trybu - dawniej zakladala zadanie odswiezania.
  # Zostaje, zeby starsze wdroz.ps1 nie wywalilo sie na nieznanym parametrze;
  # dzis robi dokladnie to samo co -UsunOdswiezanie, czyli sprzatanie.
  [switch]$TylkoOdswiezanie,
  [string[]]$Czesci = @(),
  [switch]$TylkoTekst,
  [switch]$Usun,
  [switch]$UsunDane
)

# Czesci instalacji (stale, Znajdz-Uv, srodowisko, indeks, model, MCP, sprzatanie, proba MCP).
$plikCzesci = Join-Path $PSScriptRoot "instalacja\lore-czesci.ps1"
if (-not (Test-Path $plikCzesci)) { Write-Host "BLAD  nie ma $plikCzesci - bez niego nie zainstaluje Lore" -ForegroundColor Red; exit 1 }
. $plikCzesci

$script:Kroki  = @()   # wyniki sprawdzen do koncowego podsumowania
$script:PrzeliczanieRuszylo = $false
$script:Niepelne = @() # rzeczy, ktorych sprawdzenie NIE obejmuje - do podsumowania

# ---------------------------------------------------------------- wypisywanie

function Naglowek($tekst) {
  Write-Host ""
  Write-Host $tekst -ForegroundColor Cyan
  Write-Host ("-" * $tekst.Length) -ForegroundColor DarkGray
}

function Krok($tekst)        { Write-Host "  $tekst" }
function Plan($tekst)        { Write-Host "  [PROBA] $tekst" -ForegroundColor DarkGray }
function Ostrzezenie($tekst) { Write-Host "UWAGA  $tekst" -ForegroundColor Yellow }
function Blad($tekst)        { Write-Host "BLAD  $tekst" -ForegroundColor Red }

function Zapisz-Wynik($nazwa, $ok, $opis) {
  $script:Kroki += [pscustomobject]@{ Nazwa = $nazwa; Ok = [bool]$ok; Opis = $opis }
  $etykieta = if ($ok) { "OK  " } else { "BLAD" }
  $kolor    = if ($ok) { "Green" } else { "Red" }
  $linia    = "  $etykieta  $nazwa"
  if ($opis) { $linia += " - $opis" }
  Write-Host $linia -ForegroundColor $kolor
}

# Sprawdzenie, ktore potwierdza tylko zapis na dysku albo obecnosc wpisu, nie
# nazywa sie "dziala". Takie rzeczy ida tutaj i wracaja w podsumowaniu wprost.
function Nie-Sprawdzono($tekst) {
  $script:Niepelne += $tekst
}

# Czy dana czesc jest w tym przebiegu wybrana.
function Czesc([string]$nazwa) { return ($script:Wybrane -contains $nazwa) }

# ---------------------------------------------------------------- warunki wstepne

function Sprawdz-Warunki {
  Naglowek "Warunki wstepne"
  $braki = @()

  if ($script:Uv) {
    Krok "uv      : $($script:Uv)"
  } else {
    $braki += "uv (menedzer srodowisk Pythona). Zainstaluj:  winget install --id astral-sh.uv  (albo: narzedzia\instalacja\zaleznosci.ps1 -Akcja Instaluj -Potrzebne uv,python)"
  }

  if ($script:Uv) {
    # uv zna swoje wlasne instalacje Pythona, wiec pytamy jego, a nie PATH-a
    $py = Lore-Znajdz-Pythona
    if ($py) {
      Krok "Python  : $py"
    } else {
      $braki += "Python 3.12 lub nowszy. Zainstaluj:  uv python install 3.12"
    }
  }

  # Serwer MCP rejestrujemy w KAZDYM narzedziu, ktore zastaniemy na tej maszynie.
  # Brak jednego z nich to normalna sytuacja - dopiero brak wszystkich konczy instalacje MCP.
  Lore-Wykryj-Narzedzia
  if ($script:Claude) { Krok "claude  : $($script:Claude)" }
  else { Krok "claude  : nie widze Claude Code na tej maszynie - pomijam" }
  if ($script:Codex) {
    if ($script:CodexMa) { Krok "codex   : $($script:Codex) (rejestracja przez 'codex mcp add')" }
    else { Krok "codex   : $($script:Codex) (nie zna 'codex mcp add' - wpis pojdzie do $($script:CodexCfg))" }
  } elseif ($script:CodexJest) {
    Krok "codex   : nie ma binarki w PATH, ale jest $($script:CodexDom) - wpis pojdzie do $($script:CodexCfg)"
  } else {
    Krok "codex   : nie widze Codeksa na tej maszynie - pomijam"
  }
  if ($script:OpencodeJest) { Krok "opencode: wpis mcp.$NazwaMcp pojdzie do $($script:OpencodeCfg)" }
  else { Krok "opencode: nie widze go na tej maszynie - pomijam" }

  if ((Czesc "Mcp") -and -not (Lore-Jakiekolwiek-Narzedzie)) {
    $braki += "narzedzie, w ktorym dalo by sie zarejestrowac serwer MCP - nie ma ani Claude Code, ani Codeksa, ani opencode. Zainstaluj jedno z nich:  npm install -g @anthropic-ai/claude-code  /  @openai/codex  /  opencode-ai"
  }

  if (Test-Path (Join-Path $script:Lore "pyproject.toml")) {
    Krok "modul   : $($script:Lore)"
  } else {
    $braki += "katalog modulu: nie widze $($script:Lore)\pyproject.toml - wskaz repozytorium przez  -Zrodlo <sciezka>"
  }

  if ($braki.Count -gt 0) {
    Write-Host ""
    Blad "brakuje tego, bez czego instalacja nie ma sensu:"
    foreach ($b in $braki) { Write-Host "  - $b" -ForegroundColor Yellow }
    Write-Host ""
    Write-Host "Nic nie zostalo zmienione."
    exit 1
  }
}

# Jedno miejsce na warunek "co tu w ogole jest": dostaje opis Claude Code i opis
# Codeksa, oddaje tylko te, ktore Sprawdz-Warunki naprawde znalazlo. Inaczej ten
# sam warunek siedzi w kilku ekranach naraz i rozjezdza sie przy pierwszej zmianie.
function Wykryte-Narzedzia($opisClaude, $opisCodex, $opisOpencode) {
  $lista = @()
  if ($script:Claude)       { $lista += $opisClaude }
  if ($script:CodexJest)    { $lista += $opisCodex }
  if ($script:OpencodeJest -and $opisOpencode) { $lista += $opisOpencode }
  return $lista
}

# ---------------------------------------------------------------- zgoda uzytkownika

function Ekran-Zgody {
  # Kazdy tekst tego ekranu ma mowic prawde o TEJ maszynie - wymieniamy tylko te
  # narzedzia, ktore Sprawdz-Warunki (wolane wczesniej) naprawde na niej znalazlo.
  $zKim  = @(Wykryte-Narzedzia "Claude Code" "Codeksem" "opencode")
  $czyje = if ($zKim.Count -gt 1) {
             (($zKim[0..($zKim.Count - 2)] -join ", ") + " i " + $zKim[-1])
           } elseif ($zKim.Count -eq 1) { $zKim[0] }
           else { "Twoim narzedziem AI" }

  $opisCodex = if ($script:CodexMa) { "Codex CLI - przez 'codex mcp add'" } else { "Codex CLI - wpisem w $($script:CodexCfg) (stary plik zostanie skopiowany obok)" }
  $gdzie = @(Wykryte-Narzedzia "Claude Code - przez 'claude mcp add', w zasiegu Twojego uzytkownika" $opisCodex `
                                "opencode - wpisem mcp.$NazwaMcp w $($script:OpencodeCfg) (stary plik zostanie skopiowany obok)")
  $lista = ($gdzie | ForEach-Object { "        - $_" }) -join "`n"

  Naglowek "Co zaraz stanie sie na tym komputerze"
  $nr = 0
  $tekst = "  Lore to lokalna, przeszukiwalna pamiec Twoich rozmow z $($czyje).`n"
  if ((Czesc "Srodowisko") -or (Czesc "Indeks")) {
    $nr++
    $jak = if ($TylkoTekst) { "wyszukiwaniem pelnotekstowym (bez modelu wektorow - tryb 'tylko tekst')" } else { "wyszukiwaniem pelnotekstowym i semantycznym`n     (znajduje po sensie zdania, nie tylko po doslownym slowie)" }
    $tekst += "`n  $nr. Powstanie LOKALNA baza SQLite z $jak.`n        baza  : $($script:Baza)"
  }
  if (Czesc "Model") {
    $nr++
    $tekst += "`n  $nr. Pobierze sie z internetu model jezykowy, $RozmiarModelu (sdadas/mmlw-retrieval-roberta-base).`n        model : $($script:Modele)"
    if (Test-Path $script:Baza) {
      $tekst += "`n        Baza juz tu jest: jesli archiwum policzono starszym modelem albo czesc fragmentow`n        nie ma wektorow, zostana POLICZONE W TLE ($CzasPrzeliczania przy duzym archiwum, obnizony`n        priorytet procesu; wyszukiwanie dziala przez caly czas)."
    }
  }
  if (Czesc "Mcp") {
    $nr++
    $tekst += "`n  $nr. Serwer MCP o nazwie `"$NazwaMcp`" zostanie zarejestrowany wszedzie tam, gdzie`n     widze narzedzie, ktore go przyjmie:`n$lista`n     UWAGA: od tej chwili agent AI ma dostep do TRESCI wszystkich Twoich rozmow`n     zebranych na tej maszynie - ze wszystkich projektow i wszystkich okien."
  }
  if (Czesc "Indeks") {
    $nr++
    $tekst += "`n  $nr. Powstanie zadanie w Harmonogramie zadan Windows:`n        `"$NazwaZadania`" - odswieza indeks rozmow co $InterwalMin minut"
  }
  if (Czesc "Nadzorca") {
    $nr++
    $tekst += "`n  $nr. Powstanie zadanie w Harmonogramie, przy zalogowaniu (30 s pozniej):`n        `"MegaRuchaczNadzorca`" - nadzorca z ikona w zasobniku obok zegara. Pilnuje`n        rachunku za pamiec, cyklu wiedzy i alarmow takze wtedy, gdy nie otwierasz`n        zadnego okna. Wystartuje od razu; zdjac: zasobnik\zainstaluj-zasobnik.ps1 -Usun"
  }
  # O usuwaniu mowimy tylko tam, gdzie naprawde jest co usuwac.
  if ((Czesc "Sprzatanie") -and (Jest-Stare-Odswiezanie)) {
    $nr++
    $tekst += "`n  $nr. Zadanie `"$NazwaZadaniaOdswiez`" ze starszej instalacji zostanie USUNIETE`n     - narzedzie aktualizuje sie dzis przy starcie sesji, nie z Harmonogramu."
  }
  $tekst += "`n`n  Nic nie wychodzi poza ta maszyne: baza, model i samo wyszukiwanie dzialaja lokalnie,`n  bez zewnetrznych API. Jedynym ruchem w sieci jest jednorazowe pobranie modelu."
  Write-Host $tekst
}

function Zapytaj-O-Zgode {
  Ekran-Zgody
  if ($Proba) {
    Write-Host ""
    Plan "tutaj instalator poprosilby o potwierdzenie"
    return
  }
  if ($BezPytania) {
    Write-Host ""
    Krok "zgoda zebrana wczesniej (-BezPytania) - nie pytam"
    return
  }
  Write-Host ""
  $odp = Read-Host "  Instalowac? wpisz 'tak', zeby kontynuowac"
  if ($odp -notmatch '^\s*(t|tak|y|yes)\s*$') {
    Write-Host ""
    Write-Host "Przerwane na zyczenie - nic nie zostalo zmienione."
    exit 0
  }
}

# ---------------------------------------------------------------- instalacja (czesci z lore-czesci.ps1)

# Wspolny ksztalt: naglowek, czesc z biblioteki, a jej wyjatek = BLAD i koniec, zeby nie
# zostawic polowicznej instalacji bez slowa.
function Wykonaj([string]$naglowek, [scriptblock]$co) {
  Naglowek $naglowek
  try { & $co }
  catch {
    Blad "$($_.Exception.Message) - przerywam."
    exit 1
  }
}

# Autostart nadzorcy w zasobniku. Cykl wiedzy musi miec wyzwalacz NIEZALEZNY
# od hookow: hook nie chodzi, gdy nikt nie otworzyl okna, a wtedy milknie takze
# wykrywanie tego, ze nic nie chodzi (17-24.09.2026 cykl stal tydzien i nikt
# sie o tym nie dowiedzial). Sama rejestracja siedzi w zasobnik\, tu jest tylko
# jej wywolanie. Brak tego katalogu to starsza kopia narzedzia, nie awaria pamieci.
function Zaloz-Nadzorce([switch]$Zdejmij) {
  $skrypt = Join-Path $Zrodlo "zasobnik\zainstaluj-zasobnik.ps1"
  if (-not (Test-Path $skrypt)) {
    Ostrzezenie "nie ma ${skrypt} - nadzorcy w zasobniku nie ruszam (starsza kopia narzedzia?)"
    return
  }
  # Splatowanie TABLICA a nie tablica: przy @("-Zrodlo", $Zrodlo) PowerShell
  # przekazal "-Zrodlo" jako WARTOSC pierwszego parametru pozycyjnego i instalator
  # szukal nadzorcy w katalogu o nazwie "-Zrodlo". Zlapane 24.09.2026.
  $argumenty = @{ Zrodlo = $Zrodlo }
  if ($Proba) { $argumenty["Proba"] = $true }
  if ($Zdejmij) { $argumenty["Usun"] = $true }
  try {
    $global:LASTEXITCODE = 0
    & $skrypt @argumenty
    if ($LASTEXITCODE -ne 0) {
      Ostrzezenie "nadzorca w zasobniku: zainstaluj-zasobnik.ps1 zakonczyl sie kodem ${LASTEXITCODE} - reszta jest w porzadku"
      Krok "sprobuj osobno: powershell -ExecutionPolicy Bypass -File $skrypt"
    }
  } catch {
    Ostrzezenie "nie udalo sie ruszyc nadzorcy w zasobniku: $($_.Exception.Message)"
    Krok "sprobuj osobno: powershell -ExecutionPolicy Bypass -File $skrypt"
  }
}

# Sprzatanie po starszych instalacjach (MegaRuchaczOdswiez, LoreCykl i spolka). Brak zadania
# to normalna sytuacja - na swiezej maszynie nikt o tym nie musi slyszec.
function Usun-Stare-Zadania {
  if (-not (Jest-Stare-Odswiezanie) -and @(Stare-Zadania-Cyklu).Count -eq 0) {
    if ($Proba) {
      Naglowek "Stare zadania w harmonogramie"
      Plan "zadnego z zadan $NazwaZadaniaOdswiez, $($ZadaniaCyklu -join ', ') nie ma w Harmonogramie - nic do sprzatania"
    }
    return
  }
  Naglowek "Stare zadania w harmonogramie"
  [void](Lore-Usun-Stare-Zadania)
}

# ---------------------------------------------------------------- sprawdzenie instalacji

function Sprawdz-Testy {
  $w = Uruchom-Uv @("pytest", "-q")
  $ile = [regex]::Match($w.Tekst, '(\d+) passed').Groups[1].Value
  if ($w.Kod -eq 0) {
    Zapisz-Wynik "testy modulu" $true "przeszlo: $ile"
  } else {
    Zapisz-Wynik "testy modulu" $false "pytest zwrocil kod $($w.Kod): $(Ostatnia-Linia $w.Tekst)"
  }
}

function Sprawdz-Import {
  $w = Uruchom-Uv @("python", "-c", "from lore import server")
  if ($w.Kod -eq 0) {
    Zapisz-Wynik "import serwera MCP" $true $null
  } else {
    Zapisz-Wynik "import serwera MCP" $false "$(Ostatnia-Linia $w.Tekst)"
  }
}

function Sprawdz-Indeksowanie {
  $dalej = @("python", "-m", "lore.index")
  if ($TylkoTekst) { $dalej += "--text-only"; Krok "indeksuje rozmowy (tylko tekst, bez modelu)..." }
  else { Krok "indeksuje rozmowy (pierwszy raz trwa - pobiera sie model)..." }
  $w = Uruchom-Uv $dalej
  if ($w.Kod -eq 0) {
    Zapisz-Wynik "indeksowanie rozmow" $true $null
  } else {
    Zapisz-Wynik "indeksowanie rozmow" $false "kod $($w.Kod): $(Ostatnia-Linia $w.Tekst)"
  }
}

function Sprawdz-Zadanie {
  $stan = Lore-Stan-Indeksu
  if ($stan.Ok -and $stan.TylkoTekst -ne [bool]$TylkoTekst) {
    $jest = if ($stan.TylkoTekst) { "tylko tekst" } else { "z wektorami" }
    Zapisz-Wynik "zadanie w harmonogramie ($NazwaZadania)" $false "chodzi w trybie '$jest', a ten przebieg chcial innego"
    return
  }
  Zapisz-Wynik "zadanie w harmonogramie ($NazwaZadania)" $stan.Ok $stan.Opis
}

function Sprawdz-Model {
  # Model sciaga sie leniwie - dlatego liczymy wektor NAPRAWDE (to wymusza pobranie
  # i od razu pokazuje, czy model dziala).
  try {
    Lore-Pobierz-Model
    $m = Lore-Stan-Modelu
    Zapisz-Wynik "model semantyczny" $true $m.Opis
  } catch {
    Zapisz-Wynik "model semantyczny" $false $_.Exception.Message
  }
}

# ok = OK. migration_needed / migrating / incomplete w trakcie liczenia = ostrzezenie, nie blad:
# przeliczanie trwa godzinami, a wyszukiwanie dziala przez ten czas - czerwone "instalacja NIE
# jest kompletna" byloby falszywym alarmem. text_only = OK tylko przy -TylkoTekst.
# Kazdy inny stan (unknown_model, nieczytelny) = blad z trescia z db.py.
function Sprawdz-Wektory {
  $s = Stan-Wektorow
  if (-not $s.Stan) {
    Zapisz-Wynik "wektory w bazie" $false "nie udalo sie odczytac stanu: $(Ostatnia-Linia $s.Tekst)"
    return
  }
  if ($TylkoTekst) {
    # Wiedza bez lore: wektory nie sa uzywane, wiec ich brak (incomplete), stary albo nieznany model
    # (migration_needed, unknown_model) to stan prawidlowy - BLAD bylby falszywym alarmem (P59a).
    if ($s.Stan -eq "text_only") { Zapisz-Wynik "tryb indeksu" $true "tylko tekst - wyszukiwanie pelnotekstowe, bez wektorow (tak ma byc)" }
    elseif (@("ok", "incomplete", "unknown_model", "migration_needed", "migrating") -contains $s.Stan) {
      Zapisz-Wynik "tryb indeksu" $true "tylko tekst - wektory nie sa tu uzywane (stan bazy: $($s.Stan); tryb zapisze pierwszy przebieg indeksu)"
    }
    else { Zapisz-Wynik "tryb indeksu" $false "nieznany stan bazy '$($s.Stan)': $($s.Ostrzezenie)" }
    return
  }
  switch ($s.Stan) {
    "ok" { Zapisz-Wynik "wektory w bazie" $true "policzone modelem, na ktory Lore jest ustawione" }
    { @("migration_needed", "migrating", "incomplete") -contains $_ } {
      if ($s.Stan -eq "incomplete" -and -not $s.Trwa -and -not $script:PrzeliczanieRuszylo) {
        Zapisz-Wynik "wektory w bazie" $false "stan incomplete: $($s.Ostrzezenie)"
        return
      }
      if ($script:PrzeliczanieRuszylo -and -not $s.Trwa) {
        Ostrzezenie "wektory w bazie: $($s.Stan) - liczenie ruszylo przed chwila w tle; do konca wyszukiwanie po sensie nie obejmuje wszystkiego"
      } elseif ($s.Trwa) {
        Ostrzezenie "wektory w bazie: $($s.Stan) - liczenie trwa ($($s.Procent)%); do konca wyszukiwanie po sensie nie obejmuje wszystkiego"
      } else {
        Ostrzezenie "wektory w bazie: $($s.Stan) - archiwum trzeba przeliczyc, a przeliczanie TERAZ NIE IDZIE"
      }
      Krok "polecenie (wznawia od miejsca, w ktorym stanelo): $(Polecenie-Przeliczania)"
      Nie-Sprawdzono "liczenie wektorow nie jest skonczone (stan: $($s.Stan)) - wyszukiwanie po sensie obejmie cale archiwum dopiero po jego koncu"
    }
    default { Zapisz-Wynik "wektory w bazie" $false "stan $($s.Stan): $($s.Ostrzezenie)" }
  }
}

# Nadzorca w zasobniku - sam instalator nadzorcy wie najlepiej, jak go sprawdzic
# (zadanie w Harmonogramie + proces). Kod 0 = jest i chodzi.
function Sprawdz-Nadzorce {
  $skrypt = Join-Path $Zrodlo "zasobnik\zainstaluj-zasobnik.ps1"
  if (-not (Test-Path $skrypt)) {
    Zapisz-Wynik "nadzorca w zasobniku" $false "nie ma ${skrypt}"
    return
  }
  try {
    $global:LASTEXITCODE = 0
    & $skrypt -Zrodlo $Zrodlo -TylkoSprawdz
    $kodN = $LASTEXITCODE
  } catch {
    Zapisz-Wynik "nadzorca w zasobniku" $false "sprawdzenie wywrocilo sie: $($_.Exception.Message)"
    return
  }
  if ($kodN -eq 0) {
    Zapisz-Wynik "nadzorca w zasobniku" $true "zadanie MegaRuchaczNadzorca jest w Harmonogramie, proces chodzi"
  } else {
    Zapisz-Wynik "nadzorca w zasobniku" $false "zadanie albo proces nie stoi (szczegoly wyzej) - uruchom: powershell -ExecutionPolicy Bypass -File $skrypt"
  }
}

function Sprawdz-Baze {
  # liczby prosto z bazy - connect() zaklada schemat i jest idempotentne
  # UWAGA: cudzyslowy podwojne wewnatrz argumentu gina przy przekazywaniu do
  # zewnetrznego programu w PowerShell 5.1 - dlatego w kodzie Pythona sa pojedyncze.
  #
  # Zero plikow i zero kawalkow samo w sobie nie znaczy nic: tak samo wyglada
  # swieza maszyna i calkiem zepsuty indekser. Rozroznia je dopiero liczba
  # transkryptow, ktore indekser POWINIEN widziec - stad find_files().
  $kodPy = "from lore.db import connect; from lore.index import find_files; c = connect(); " +
           "print('BAZA', c.execute('SELECT count(*) FROM files').fetchone()[0], " +
           "c.execute('SELECT count(*) FROM chunks').fetchone()[0], len(find_files()))"
  $w = Uruchom-Uv @("python", "-c", $kodPy)
  $m = [regex]::Match($w.Tekst, 'BAZA (\d+) (\d+) (\d+)')
  if ($w.Kod -ne 0 -or -not $m.Success) {
    Zapisz-Wynik "zawartosc bazy" $false "nie udalo sie odczytac statystyk z $($script:Baza): $(Ostatnia-Linia $w.Tekst)"
    return
  }
  $plikow   = [int]$m.Groups[1].Value
  $kawalkow = [int]$m.Groups[2].Value
  $zrodel   = [int]$m.Groups[3].Value
  if ($zrodel -eq 0 -and $plikow -eq 0) {
    Zapisz-Wynik "zawartosc bazy" $true "na tej maszynie nie ma jeszcze czego indeksowac - zero transkryptow, zero wpisow"
  } elseif ($plikow -eq 0) {
    Zapisz-Wynik "zawartosc bazy" $false "indekser widzi $zrodel transkryptow, a baza jest pusta - indeksowanie nie zadzialalo"
  } elseif ($kawalkow -eq 0) {
    Zapisz-Wynik "zawartosc bazy" $false "zaindeksowano $plikow plikow, ale zero fragmentow - nie ma czego szukac"
  } else {
    Zapisz-Wynik "zawartosc bazy" $true "plikow: $plikow z $zrodel widocznych, kawalkow: $kawalkow"
  }
}

function Sprawdz-Mcp-Wpis {
  # To jest sprawdzenie REJESTRACJI, nie dzialania - lista wpisow pokaze serwer
  # takze na maszynie, na ktorej on nie wstaje. Od dzialania jest handshake nizej.
  # Narzedzia, ktorego tu nie ma, NIE zaliczamy na zielono - mowimy, ze pominiete.
  $jest = @(Lore-Stan-Mcp)
  if ($script:Claude) {
    Zapisz-Wynik "serwer MCP w Claude Code" ($jest -contains "claude") "wpis $NazwaMcp $(if ($jest -contains 'claude') { 'jest w konfiguracji uzytkownika' } else { 'nie jest widoczny w claude mcp get' })"
    Nie-Sprawdzono "czy Twoj klient Claude Code podepnie serwer $NazwaMcp przy starcie - to widac dopiero w nowym oknie"
  } else {
    Write-Host "  --    serwer MCP w Claude Code - pominiete, nie ma Claude Code na tej maszynie" -ForegroundColor DarkGray
  }
  if ($script:OpencodeJest) {
    Zapisz-Wynik "serwer MCP w opencode" ($jest -contains "opencode") "wpis mcp.$NazwaMcp $(if ($jest -contains 'opencode') { 'jest' } else { 'nie siedzi' }) w $($script:OpencodeCfg)"
    Nie-Sprawdzono "czy opencode podepnie serwer $NazwaMcp przy starcie - wpis jest, ale podpiecie widac dopiero w nowej sesji opencode"
  } else {
    Write-Host "  --    serwer MCP w opencode - pominiete, nie ma opencode na tej maszynie" -ForegroundColor DarkGray
  }
  if ($script:CodexJest) {
    Zapisz-Wynik "serwer MCP w Codeksie" ($jest -contains "codex") "wpis $NazwaMcp $(if ($jest -contains 'codex') { 'jest' } else { 'nie jest widoczny' })"
    Nie-Sprawdzono "czy Codex wstanie z serwerem $NazwaMcp - wpis jest, ale podpiecie widac dopiero w nowej sesji Codeksa"
  } else {
    Write-Host "  --    serwer MCP w Codeksie - pominiete, nie ma Codeksa na tej maszynie" -ForegroundColor DarkGray
  }
}

function Sprawdz-Mcp-Dziala {
  $w = Lore-Sprawdz-Mcp-Dziala
  Zapisz-Wynik "serwer MCP odpowiada na wywolanie" $w.Ok $w.Opis
}

function Sprawdz-Instalacje {
  Naglowek "Sprawdzenie, czy to naprawde dziala"
  if ($Proba) {
    if (Czesc "Srodowisko") { Plan "uv --directory $($script:Lore) run pytest -q" }
    if (Czesc "Mcp") { Plan "uv --directory $($script:Lore) run python -c ""from lore import server""" }
    if (Czesc "Indeks") {
      Plan "Get-ScheduledTask $NazwaZadania - czy zadanie istnieje, nie jest wylaczone i chodzi we wlasciwym trybie"
      Plan "uv --directory $($script:Lore) run python -m lore.index$(if ($TylkoTekst) { ' --text-only' })   (jeden przebieg indeksowania)"
    }
    if (Czesc "Model") { Plan "policzenie wektora modelem i rozmiar katalogu $($script:Modele) (min. $MinModelMB MB)" }
    Plan "stan wektorow: vector_status(connect())  (ok / liczenie trwa / tylko tekst / blad)"
    Plan "odczyt z bazy: ile plikow i kawalkow wobec liczby widocznych transkryptow ($($script:Baza))"
    if (Czesc "Mcp") {
      Plan "wpis serwera $NazwaMcp w wykrytych narzedziach (claude mcp get / codex mcp get / config.toml / opencode.json)"
      Plan "handshake JSON-RPC z serwerem ${NazwaMcp}: initialize + tools/list + lore_stats"
    }
    if (Czesc "Nadzorca") { Plan "zasobnik\zainstaluj-zasobnik.ps1 -TylkoSprawdz - czy zadanie MegaRuchaczNadzorca jest i czy nadzorca chodzi" }
    return
  }
  if (Czesc "Srodowisko") { Sprawdz-Testy }
  if (Czesc "Mcp") { Sprawdz-Import }
  if (Czesc "Indeks") { Sprawdz-Zadanie; Sprawdz-Indeksowanie }
  if (Czesc "Model") { Sprawdz-Model }
  if ((Czesc "Model") -or $TylkoTekst) { Sprawdz-Wektory }
  Sprawdz-Baze
  if (Czesc "Mcp") { Sprawdz-Mcp-Wpis; Sprawdz-Mcp-Dziala }
  if (Czesc "Nadzorca") { Sprawdz-Nadzorce }
}

function Podsumowanie {
  Naglowek "Podsumowanie"
  foreach ($k in $script:Kroki) {
    $etykieta = if ($k.Ok) { "OK  " } else { "BLAD" }
    $kolor    = if ($k.Ok) { "Green" } else { "Red" }
    $linia    = "  $etykieta  $($k.Nazwa)"
    if ($k.Opis) { $linia += " - $($k.Opis)" }
    Write-Host $linia -ForegroundColor $kolor
  }
  if ($script:Niepelne.Count -gt 0) {
    Write-Host ""
    Write-Host "  Czego to sprawdzenie NIE obejmuje:" -ForegroundColor DarkGray
    foreach ($n in $script:Niepelne) { Write-Host "  -  $n" -ForegroundColor DarkGray }
  }
  $zle = @($script:Kroki | Where-Object { -not $_.Ok })
  Write-Host ""
  if ($zle.Count -gt 0) {
    Blad "instalacja NIE jest kompletna: $($zle.Count) z $($script:Kroki.Count) sprawdzen nie przeszlo."
    exit 1
  }
  if (Czesc "Mcp") {
    $gdzie = @(Wykryte-Narzedzia "okna Claude Code" "sesje Codeksa")
    $co = if ($gdzie.Count -gt 0) { $gdzie -join " i " } else { "okna narzedzia AI" }
    Write-Host "Gotowe. Zamknij i otworz $co - serwer $NazwaMcp podepnie sie przy starcie." -ForegroundColor Green
  } else {
    Write-Host "Gotowe - wybrane czesci Lore stoja: $($script:Wybrane -join ', ')." -ForegroundColor Green
  }
  exit 0
}

# ---------------------------------------------------------------- przebieg

$WszystkieCzesci = @("Srodowisko", "Indeks", "Model", "Mcp", "Nadzorca", "Sprzatanie")
# -File podaje "Mcp,Model" jako JEDEN napis do [string[]] - dzielimy sami
$podane = @($Czesci | ForEach-Object { $_ -split '[,;\s]+' } | Where-Object { $_ })
$nieznane = @($podane | Where-Object { $WszystkieCzesci -notcontains $_ })
if ($nieznane.Count -gt 0) { Blad "nie znam czesci: $($nieznane -join ', ') (znam: $($WszystkieCzesci -join ', '))"; exit 1 }
if ($podane.Count -gt 0) { $script:Wybrane = @($WszystkieCzesci | Where-Object { $podane -contains $_ }) }
elseif ($Usun) { $script:Wybrane = @("Mcp", "Model", "Indeks", "Srodowisko") }
else { $script:Wybrane = $WszystkieCzesci }
if ($TylkoTekst) { $script:Wybrane = @($script:Wybrane | Where-Object { $_ -ne "Model" }) }

Write-Host ""
Write-Host "Instalator modulu pamieci rozmow Lore"
if ($Proba)            { Ostrzezenie "TRYB PROBNY - tylko pokazuje plan, niczego nie zmienia" }
if ($TylkoSprawdz)     { Ostrzezenie "TRYB SPRAWDZANIA - tylko test juz zainstalowanego modulu" }
if ($TylkoTekst)       { Ostrzezenie "TRYB 'TYLKO TEKST' - indeks bez modelu wektorow, bez wyszukiwania po sensie" }
if ($Usun)             { Ostrzezenie "TRYB USUWANIA - zdejmuje czesci: $($script:Wybrane -join ', ')$(if ($UsunDane) { ' + baza rozmow' })" }
$Sprzatanie = $UsunOdswiezanie -or $TylkoOdswiezanie
if ($Sprzatanie)       { Ostrzezenie "TRYB SPRZATANIA - zdejmuje stare zadania z Harmonogramu (odswiezanie narzedzia i cykl wiedzy), pamieci rozmow nie ruszam" }

$sciezka = Resolve-Path $Zrodlo -ErrorAction SilentlyContinue
if (-not $sciezka) {
  Blad "nie ma takiego katalogu: $Zrodlo"
  exit 1
}
$Zrodlo = $sciezka.Path
Lore-Przygotuj

# Sprzatanie nie ma nic wspolnego z pamiecia rozmow - nie potrzebuje ani Pythona,
# ani uv, ani serwera MCP. Osobne wyjscie, zeby dalo sie zdjac stare zadanie
# z maszyny, na ktorej modulu pamieci nikt nie chcial - i bez reinstalacji.
if ($Sprzatanie) {
  Usun-Stare-Zadania
  if ($Proba) {
    Write-Host ""
    Write-Host "TRYB PROBNY - nic nie zostalo zmienione."
    exit 0
  }
  Write-Host ""
  if (Jest-Stare-Odswiezanie) {
    Blad "zadanie $NazwaZadaniaOdswiez nadal jest w Harmonogramie - zdejmij je recznie."
    exit 1
  }
  $zostalyCykle = @(Stare-Zadania-Cyklu)
  if ($zostalyCykle.Count -gt 0) {
    Blad "zadania $($zostalyCykle -join ', ') nadal sa w Harmonogramie - zdejmij je recznie."
    exit 1
  }
  Write-Host "Gotowe - narzedzie aktualizuje sie przy starcie sesji, a cykl wiedzy rusza przy pierwszej sesji dnia." -ForegroundColor Green
  exit 0
}

# Usuwanie czesci - odwrotnosc instalacji, w odwrotnej kolejnosci. Rejestru modulow nie
# ruszamy: modul wylaczaja narzedzia\instalacja\modul-*.ps1.
if ($Usun) {
  Lore-Wykryj-Narzedzia
  $zle = 0
  if (Czesc "Mcp") { Naglowek "Serwer MCP ($NazwaMcp) - zdejmowanie"; try { Lore-Wyrejestruj-Mcp } catch { Blad $_.Exception.Message; $zle++ } }
  if (Czesc "Model") { Naglowek "Model wektorow - usuwanie"; if (-not (Lore-Usun-Model)) { $zle++ } }
  if (Czesc "Indeks") { Naglowek "Zadanie w harmonogramie ($NazwaZadania) - zdejmowanie"; try { Lore-Usun-Zadanie-Indeksu } catch { Blad $_.Exception.Message; $zle++ } }
  if (Czesc "Srodowisko") { Naglowek "Srodowisko Pythona - usuwanie"; if (-not (Lore-Usun-Srodowisko)) { $zle++ } }
  if (Czesc "Nadzorca") { Naglowek "Nadzorca w zasobniku - usuwanie"; Zaloz-Nadzorce -Zdejmij }
  if ($UsunDane) { Naglowek "Baza rozmow - usuwanie"; if (-not (Lore-Usun-Dane)) { $zle++ } }
  else { Krok "baza rozmow zostaje ($($script:Baza)) - usunie ja -UsunDane" }
  Write-Host ""
  Ostrzezenie "rejestr modulow bez zmian - modul wylaczasz przez narzedzia\instalacja\modul-lore.ps1 / modul-wiedza.ps1 -Akcja Usun"
  if ($Proba) { Write-Host "TRYB PROBNY - nic nie zostalo zmienione."; exit 0 }
  if ($zle -gt 0) { Blad "usuwanie NIE jest kompletne - $zle czesci zostalo (powody wyzej)."; exit 1 }
  Write-Host "Gotowe - wybrane czesci Lore zdjete." -ForegroundColor Green
  exit 0
}

Sprawdz-Warunki

if (-not $TylkoSprawdz) {
  Zapytaj-O-Zgode
  if (Czesc "Srodowisko") { Wykonaj "Srodowisko Pythona" { Lore-Zainstaluj-Srodowisko } }
  if (Czesc "Mcp") { Wykonaj "Serwer MCP ($NazwaMcp)" { [void](Lore-Zarejestruj-Mcp) } }
  if (Czesc "Indeks") {
    Wykonaj "Zadanie w harmonogramie ($NazwaZadania)" {
      if (-not $Proba) { Lore-Zapisz-Tryb ([bool]$TylkoTekst) }
      Lore-Zaloz-Zadanie-Indeksu ([bool]$TylkoTekst)
    }
  }
  if (Czesc "Nadzorca") { Zaloz-Nadzorce }
  if (Czesc "Model") {
    Naglowek "Wektory archiwum"
    $script:PrzeliczanieRuszylo = Lore-Uruchom-Przeliczanie
  }
  if (Czesc "Sprzatanie") { Usun-Stare-Zadania }
}

Sprawdz-Instalacje

if ($Proba) {
  Write-Host ""
  Write-Host "TRYB PROBNY - nic nie zostalo zmienione. Uruchom bez -Proba, zeby zainstalowac."
  exit 0
}

Podsumowanie
