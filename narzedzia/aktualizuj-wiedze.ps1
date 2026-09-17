# Aktualizacja trwalej wiedzy o uzytkowniku - caly cykl w jednym poleceniu.
#
# 1. wylawianie nowych faktow z rozmow (uruchamia narzedzia\wyciagnij-fakty.ps1)
# 2. weryfikacja: co da sie sprawdzic maszynowo (na razie: sciezki w systemie plikow)
# 3. fakty wchodza do obowiazujacej wiedzy SAME - kazdy do swojej warstwy
#    (%USERPROFILE%\.claude\CLAUDE.md, wylacznie sekcja "## Co wiem"). Poczekalnia nie
#    jest juz kolejka do klikania: rano bylo w niej 90 pozycji i nikt ich nie czytal.
#    W poczekalni zostaje tylko to, czego automat nie ma prawa rozstrzygnac:
#      [!] odrzucone - podana sciezka nie istnieje albo wpis nie miesci sie w progu
#          warstwy stalej (8000 znakow; prog stoi w narzedzia\koszt-pamieci.ps1),
#      [?] sporne - fakt przeczy temu, co juz jest zapisane. Automat musialby zgadnac,
#          ktora wersja jest prawdziwa - a to jest dokladnie ten rodzaj cichej pomylki,
#          ktora zyje potem miesiacami. Decyduje uzytkownik.
# 4. fakty JUZ obowiazujace tez sa sprawdzane - te, ktore przestaly sie potwierdzac,
#    dostaja dopisek "niepotwierdzone" i trafiaja do podsumowania. Nic nie jest kasowane:
#    nieobecna sciezka moze byc odpietym dyskiem sieciowym, a nie nieprawda.
# 5. przed kazda zmiana powstaje kopia pliku z data w nazwie (wiedza\kopie) - fakty
#    wchodza bez pytania, wiec musi byc prosta droga powrotu.
#
# Skad sie wzial ktorykolwiek fakt: wiedza\zrodla.md (data + rozmowy, z ktorych pochodzi).
# Podsumowanie przebiegu w formacie "klucz: wartosc": wiedza\.wiedza-stan.txt
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File narzedzia\aktualizuj-wiedze.ps1
#   ... -Zrodlo <sciezka>         katalog glowny repozytorium (domyslnie: katalog nad narzedzia\)
#   ... -Proba                    pokazuje, co by zrobil, i NIE zapisuje niczego
#   ... -BezWylawiania            sama weryfikacja, bez wolania modelu - czyli za darmo
#   ... -KatalogDomowy <sciezka>  inny katalog zamiast ~\.claude (do testow; ustawia LORE_HOME)
#   ... -ZalozZadanie             zaklada zadanie "LoreWiedza" (w poniedzialki o 08:25)
#   ... -UsunZadanie              kasuje to zadanie

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Proba,
  [switch]$BezWylawiania,
  [string]$KatalogDomowy,
  [switch]$ZalozZadanie,
  [switch]$UsunZadanie
)

$NazwaZadania = "LoreWiedza"
$Godzina      = "08:25"
$DzienTygodnia = "Monday"

$script:Uv   = $null
$script:Lore = $null
$script:Dom  = $null

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

# ---------------------------------------------------------------- warunki wstepne

function Znajdz-Uv {
  # najpierw PATH, a jak nie ma - sciezki, pod ktore uv laduje z WinGeta
  $cmd = Get-Command uv -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return $cmd.Source }
  $link = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\uv.exe"
  if (Test-Path $link) { return (Resolve-Path $link).Path }
  $wzorzec = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\astral-sh.uv_*\uv.exe"
  $trafienie = Get-ChildItem $wzorzec -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($trafienie) { return $trafienie.FullName }
  return $null
}

function Sprawdz-Warunki {
  $sciezka = Resolve-Path $Zrodlo -ErrorAction SilentlyContinue
  if (-not $sciezka) {
    Blad "nie ma takiego katalogu: $Zrodlo"
    exit 1
  }
  $script:Lore = Join-Path $sciezka.Path "lore"
  if (-not (Test-Path (Join-Path $script:Lore "pyproject.toml"))) {
    Blad "nie widze $($script:Lore)\pyproject.toml - wskaz repozytorium przez  -Zrodlo <sciezka>"
    exit 1
  }
  $script:Uv = Znajdz-Uv
  if (-not $script:Uv) {
    Blad "nie znalazlem uv (menedzer srodowisk Pythona). Zainstaluj:  winget install --id astral-sh.uv"
    exit 1
  }
  $script:Dom = Join-Path $env:USERPROFILE ".claude"
  if ($KatalogDomowy) {
    # LORE_HOME podmienia caly katalog .claude - na tym stoi izolacja testow od prawdziwej wiedzy
    New-Item -ItemType Directory -Path $KatalogDomowy -Force | Out-Null
    $script:Dom = (Resolve-Path $KatalogDomowy).Path
    $env:LORE_HOME = $script:Dom
    Ostrzezenie "katalog domowy podmieniony na $($script:Dom) - prawdziwa wiedza nie jest ruszana"
  }
}

# ---------------------------------------------------------------- zadanie w harmonogramie

function Argumenty-Zadania {
  # conhost --headless: zadanie chodzi samo rano i nikt nie chce ogladac mrugajacego okna konsoli.
  # Sama weryfikacja, bez wylawiania: fakty wylawia codzienne zadanie LoreFacts (08:05), a to tutaj
  # tylko sprawdza, co sie potwierdza - nie wola modelu, wiec nic nie kosztuje.
  return "--headless `"$($script:Uv)`" --directory `"$($script:Lore)`" run python -m lore.verify"
}

function Zaloz-Zadanie {
  Naglowek "Zadanie w harmonogramie ($NazwaZadania)"
  $argumenty = Argumenty-Zadania
  if ($Proba) {
    Plan "Register-ScheduledTask -TaskName $NazwaZadania -Force   (nadpisuje istniejace, nie doklada drugiego)"
    Plan "  akcja     : conhost.exe $argumenty"
    Plan "  wyzwalacz : co tydzien w poniedzialek o $Godzina, z nadrobieniem po wlaczeniu komputera"
    exit 0
  }
  # UWAGA - sprawdzone 2026-09-16: zakladanie zadania przez obiekty
  # (New-ScheduledTaskPrincipal + Register-ScheduledTask -Principal) konczy sie
  # "Odmowa dostepu" u zwyklego, niepodniesionego uzytkownika. Ta sama operacja
  # podana jako XML przechodzi bez uprawnien administratora. Dlatego XML.
  try {
    $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $czesci = $Godzina -split ":"
    $poczatek = Get-Date -Hour ([int]$czesci[0]) -Minute ([int]$czesci[1]) -Second 0
    # StartBoundary wyzwalacza tygodniowego musi wypadac w tym dniu tygodnia - bierzemy najblizszy
    $doDnia = ([int][System.DayOfWeek]$DzienTygodnia - [int]$poczatek.DayOfWeek + 7) % 7
    $start = $poczatek.AddDays($doDnia).ToString("yyyy-MM-ddTHH:mm:ss")
    $argXml = [System.Security.SecurityElement]::Escape($argumenty)
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Lore - cotygodniowe sprawdzanie wiedzy o uzytkowniku (potwierdzanie faktow)</Description>
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
    <ExecutionTimeLimit>PT1H</ExecutionTimeLimit>
    <StartWhenAvailable>true</StartWhenAvailable>
    <Enabled>true</Enabled>
  </Settings>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>$start</StartBoundary>
      <ScheduleByWeek>
        <DaysOfWeek>
          <$DzienTygodnia />
        </DaysOfWeek>
        <WeeksInterval>1</WeeksInterval>
      </ScheduleByWeek>
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
    Blad "nie udalo sie zalozyc zadania: $($_.Exception.Message)"
    Krok "jesli to 'Odmowa dostepu' - zasady tej maszyny moga wymagac uprawnien administratora"
    exit 1
  }
  # StartWhenAvailable: gdy komputer byl w poniedzialek o $Godzina wylaczony, zadanie ruszy pozniej
  Krok "wiedza sprawdzana co tydzien w poniedzialek o $Godzina (z nadrobieniem po wlaczeniu komputera)"
  Krok "obowiazujaca wiedza: $(Join-Path $script:Dom 'CLAUDE.md') (sekcja '## Co wiem')"
  exit 0
}

function Usun-Zadanie {
  Naglowek "Usuwanie zadania ($NazwaZadania)"
  if ($Proba) {
    Plan "Unregister-ScheduledTask -TaskName $NazwaZadania -Confirm:`$false"
    exit 0
  }
  $zadanie = Get-ScheduledTask -TaskName $NazwaZadania -ErrorAction SilentlyContinue
  if (-not $zadanie) {
    Krok "takiego zadania nie ma - nie ma czego kasowac"
    exit 0
  }
  try {
    Unregister-ScheduledTask -TaskName $NazwaZadania -Confirm:$false -ErrorAction Stop
  } catch {
    Blad "nie udalo sie usunac zadania: $($_.Exception.Message)"
    exit 1
  }
  Krok "usuniete - poczekalnia i dotychczasowa wiedza zostaja nietkniete"
  exit 0
}

# ---------------------------------------------------------------- caly cykl

function Wylow-Fakty {
  Naglowek "1/2  Wylawianie nowych faktow z rozmow"
  if ($BezWylawiania) {
    Krok "pominiete (-BezWylawiania) - model nie jest wolany, ten przebieg nic nie kosztuje"
    return
  }
  $skrypt = Join-Path $PSScriptRoot "wyciagnij-fakty.ps1"
  if (-not (Test-Path $skrypt)) {
    Ostrzezenie "nie widze $skrypt - pomijam wylawianie, sama weryfikacja idzie dalej"
    return
  }
  if ($Proba) {
    & $skrypt -Zrodlo $Zrodlo -Proba
  } else {
    & $skrypt -Zrodlo $Zrodlo
  }
  # porazka wylawiania nie przerywa cyklu: weryfikacja tego, co juz lezy w plikach, ma sens zawsze
  if ($LASTEXITCODE -ne 0) {
    Ostrzezenie "wylawianie faktow nie powiodlo sie (kod $LASTEXITCODE) - weryfikacja idzie dalej"
  }
}

function Sprawdz-Wiedze {
  Naglowek "2/2  Sprawdzanie faktow"
  if ($Proba) { Ostrzezenie "TRYB PROBNY - tylko pokazuje, co by zrobil, niczego nie zapisuje" }
  $argumenty = @("--directory", $script:Lore, "run", "python", "-m", "lore.verify")
  if ($Proba) { $argumenty += "--proba" }
  & $script:Uv @argumenty
  $kod = $LASTEXITCODE
  if ($kod -ne 0) {
    Blad "sprawdzanie faktow nie powiodlo sie (kod $kod) - szczegoly w liniach powyzej"
    exit $kod
  }
  Naglowek "Gdzie to teraz jest"
  Krok "obowiazujaca wiedza : $(Join-Path $script:Dom 'CLAUDE.md') (sekcja '## Co wiem')"
  Krok "poczekalnia         : $(Join-Path $script:Dom 'wiedza\kandydaci.md')  - juz tylko [!] i [?]"
  Krok "skad sie wzialy     : $(Join-Path $script:Dom 'wiedza\zrodla.md')"
  Krok "kopie przed zmiana  : $(Join-Path $script:Dom 'wiedza\kopie')"
  Pokaz-Podsumowanie
  exit 0
}

function Pokaz-Podsumowanie {
  # Cisza jest zakazana: przebieg, ktory nic nie dopisal, ma powiedziec dlaczego, a nie
  # wygladac jak brak przebiegu. Dlatego czytamy plik stanu zamiast milczec, gdy go nie ma.
  $plik = Join-Path $script:Dom "wiedza\.wiedza-stan.txt"
  Naglowek "Podsumowanie przebiegu"
  if ($Proba) {
    Krok "tryb probny - podsumowanie nie jest zapisywane (liczby powyzej sa prawdziwe)"
    return
  }
  if (-not (Test-Path -LiteralPath $plik)) {
    Ostrzezenie "nie ma $plik - weryfikacja nie zapisala podsumowania, czyli cos poszlo nie tak"
    return
  }
  $stan = @{}
  foreach ($linia in (Get-Content -LiteralPath $plik -Encoding UTF8)) {
    $czesci = $linia -split ":", 2
    if ($czesci.Count -eq 2) { $stan[$czesci[0].Trim()] = $czesci[1].Trim() }
  }
  Krok "dopisane : $($stan['dopisane'])  (stala $($stan['stala']) / biezaca $($stan['biezaca']) / referencyjna $($stan['referencyjna']))"
  Krok "zostaje  : $($stan['odrzucone']) odrzuconych, $($stan['sporne']) spornych, $($stan['wstrzymane_progiem']) wstrzymanych progiem"
  Krok "warstwa stala: $($stan['prog_stalej']) znakow"
  Krok "powod    : $($stan['powod'])"
  # bez "??" - ten skrypt chodzi takze na Windows PowerShell 5.1, gdzie to jest blad skladni
  $sporne = 0
  if ($stan.ContainsKey("sporne")) { [void][int]::TryParse($stan["sporne"], [ref]$sporne) }
  if ($sporne -gt 0) {
    Ostrzezenie "sporne fakty czekaja na Twoja decyzje w $(Join-Path $script:Dom 'wiedza\kandydaci.md') - szukaj [?]"
  }
}

# ---------------------------------------------------------------- przebieg

Sprawdz-Warunki

if ($UsunZadanie)  { Usun-Zadanie }
if ($ZalozZadanie) { Zaloz-Zadanie }

Wylow-Fakty
Sprawdz-Wiedze
