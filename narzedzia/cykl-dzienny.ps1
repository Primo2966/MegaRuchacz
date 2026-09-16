# Cykl dzienny pamieci agenta - jedno uruchomienie spina cala robote:
# wylawianie faktow z zaleglych dni, weryfikacje i podsumowanie.
#
# Rzecz, dla ktorej to powstalo: zadanie o sztywnej godzinie przepada, gdy komputer byl
# wylaczony, siec padla, uzytkownik byl wylogowany albo skonczyl sie limit. Dlatego:
#   - cykl chodzi PRZY STARCIE SYSTEMU i przy zalogowaniu, a nie o ustalonej porze,
#   - warunki sprawdzane sa PRZED praca: brak sieci czy limitu to ODLOZENIE, nie porazka
#     (znacznik ostatniego przebiegu sie nie przesuwa, wiec material czeka nietkniety),
#   - nieudany przebieg wraca po $OdstepMin min osobnym zadaniem w harmonogramie,
#     najwyzej $MaxProb razy dziennie - bez Start-Sleep, ktory ginie przy wylaczeniu maszyny,
#   - zaleglosc liczona jest w dniach i nadrabiana po $MaxNadrabiania dni na przebieg,
#     zeby po urlopie nie przepalic calego limitu w piec minut.
#
# Cykl NIE jest przywiazany do jednego narzedzia AI. Czytanie transkryptow, indeksowanie
# i weryfikacja to robota na plikach - modelu potrzebuje wylacznie wylawianie faktow.
# Dlatego narzedzia (Claude Code, Codex) wykrywane sa na zywo, brak jednego z nich to
# normalna maszyna, a brak obu zatrzymuje SAMO wylawianie - weryfikacja idzie dalej.
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File narzedzia\cykl-dzienny.ps1
#   ... -Zrodlo <sciezka>         katalog glowny repozytorium (domyslnie: katalog nad narzedzia\)
#   ... -Proba                    pokazuje, co by zrobil; nie wola modelu i niczego nie zapisuje
#   ... -KatalogDomowy <sciezka>  podmiana katalogu domowego (do testow; ustawia LORE_HOME)
#   ... -ZalozZadanie             zaklada zadanie "LoreCykl" (przy starcie systemu i zalogowaniu)
#   ... -UsunZadanie              kasuje to zadanie razem z ponawiajacym

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Proba,
  [string]$KatalogDomowy = $HOME,
  [switch]$ZalozZadanie,
  [switch]$UsunZadanie
)

$NazwaZadania    = "LoreCykl"
$NazwaPonawiania = "LoreCyklPonow"
$MaxProb         = 5    # tyle podejsc na dobe - potem dzien odpuszczamy, material i tak czeka
$OdstepMin       = 10   # co tyle minut wraca zadanie ponawiajace
$MaxNadrabiania  = 5    # gorny limit dni na jeden przebieg (ochrona limitu po dluzszej przerwie)

$script:Dom       = $null
$script:Wiedza    = $null
$script:PlikStanu = $null
$script:Ostatni   = $null
$script:Znacznik  = $null
$script:Wyciagnij = $null
$script:Aktualizuj = $null
$script:Zostalo   = $null   # ile przebiegow zaleglosci zostalo wg samego wylawiania
$script:Pominiete = $null   # powod, dla ktorego wylawianie nie poszlo ($null = poszlo)

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

# ---------------------------------------------------------------- sciezki i pliki stanu

function Ustaw-Sciezki {
  $sciezka = Resolve-Path $Zrodlo -ErrorAction SilentlyContinue
  if (-not $sciezka) {
    Blad "nie ma takiego katalogu: $Zrodlo"
    exit 1
  }
  $script:Zrodlo     = $sciezka.Path
  $script:Wyciagnij  = Join-Path $PSScriptRoot "wyciagnij-fakty.ps1"
  $script:Aktualizuj = Join-Path $PSScriptRoot "aktualizuj-wiedze.ps1"

  # -KatalogDomowy to katalog DOMOWY (jak w straznik-zasad.ps1 i koszt-pamieci.ps1),
  # a nie sam .claude - stad doklejenie ".claude" tutaj. aktualizuj-wiedze.ps1 rozumie
  # ten parametr inaczej (podaje sie mu wprost katalog .claude), wiec nizej dostaje $Dom.
  $script:Dom       = Join-Path $KatalogDomowy ".claude"
  $script:Wiedza    = Join-Path $script:Dom "wiedza"
  $script:PlikStanu = Join-Path $script:Wiedza ".cykl-stan"
  $script:Ostatni   = Join-Path $script:Wiedza "cykl-ostatni.txt"
  $script:Znacznik  = Join-Path $script:Wiedza ".ostatnie-wyciaganie"

  # wyciagnij-fakty.ps1 nie ma wlasnego przelacznika katalogu - lore czyta LORE_HOME,
  # wiec podmiana idzie przez zmienna srodowiskowa i obejmuje oba wolane skrypty
  if ($KatalogDomowy -ne $HOME) {
    $env:LORE_HOME = $script:Dom
    Ostrzezenie "katalog domowy podmieniony na $($script:Dom) - prawdziwa wiedza nie jest ruszana"
  }
}

function Bez-Bom { return (New-Object System.Text.UTF8Encoding($false)) }

function Zapisz-Tekst($sciezka, $tekst) {
  $katalog = Split-Path -Parent $sciezka
  if ($katalog -and -not (Test-Path $katalog)) { New-Item -ItemType Directory -Force -Path $katalog | Out-Null }
  [System.IO.File]::WriteAllText($sciezka, $tekst, (Bez-Bom))
}

# Pliki stanu trzymaja proste "klucz: wartosc" - tak samo jak reszta narzedzia,
# dzieki czemu straznik-zasad.ps1 czyta podsumowanie tym samym kodem.
function Czytaj-Klucze($sciezka) {
  $stan = [ordered]@{}
  if (-not (Test-Path -LiteralPath $sciezka)) { return $stan }
  $raw = $null
  try { $raw = [System.IO.File]::ReadAllText($sciezka) } catch { return $stan }
  if (-not $raw) { return $stan }
  foreach ($l in ($raw -split '\r?\n')) {
    $m = [regex]::Match($l, '^\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*:\s*(.*?)\s*$')
    if ($m.Success) { $stan[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $stan
}

function Zapisz-Klucze($sciezka, $stan) {
  $linie = @()
  foreach ($k in $stan.Keys) { $linie += ("{0}: {1}" -f $k, $stan[$k]) }
  Zapisz-Tekst $sciezka (($linie -join "`r`n") + "`r`n")
}

function Zapisz-Stan($stan) {
  if ($Proba) { return }
  Zapisz-Klucze $script:PlikStanu $stan
}

# Podsumowanie czyta straznik przy starcie sesji - stad i klucze, i gotowy opis po ludzku.
# Zaleglosc przejsciowa i zaleglosc trwala wygladaja identycznie: "czeka X dni".
# Ta druga znaczy, ze limit na jeden przebieg jest za maly i system NIGDY nie
# nadgoni - a przez miesiace wyglada normalnie. Jedyne, co je odroznia, to
# kierunek: czy zaleglosc maleje, czy rosnie. Dlatego porownujemy z poprzednim
# przebiegiem i mowimy wprost, gdy nie nadazamy.
function Kierunek-Zaleglosci($zaleglosc) {
  $poprzednia = $null
  if (Test-Path $script:Ostatni) {
    try {
      $stare = Get-Content $script:Ostatni -Raw | ConvertFrom-Json
      if ($stare.zaleglosc -match '^\d+$') { $poprzednia = [int]$stare.zaleglosc }
    } catch { }
  }
  if ($null -eq $poprzednia -or $zaleglosc -le 0) { return "" }
  if ($zaleglosc -gt $poprzednia) {
    return " UWAGA: zaleglosc ROSNIE ($poprzednia -> $zaleglosc) - limit na jeden przebieg jest za maly, system nie nadazy sam. Zwieksz MAX_INPUT_CHARS w lore\lore\facts.py albo uruchom z -Nadrabiaj."
  }
  if ($zaleglosc -lt $poprzednia) { return " (maleje: $poprzednia -> $zaleglosc, nadrabia sie)" }
  return " (stoi w miejscu od poprzedniego przebiegu - sprawdz, czy cos nie blokuje)"
}

function Zapisz-Podsumowanie($status, $powod, $nadrobione, $zaleglosc) {
  $kierunek = Kierunek-Zaleglosci $zaleglosc
  $opis = switch ($status) {
    "ok"         { "cykl przeszedl - nadrobione dni: $nadrobione, czeka jeszcze: $zaleglosc$kierunek" }
    "odlozony"   { "cykl odlozony ($powod) - czeka jeszcze dni: $zaleglosc$kierunek" }
    "wyczerpane" { "cykl odpuszczony po $MaxProb probach ($powod) - czeka jeszcze dni: $zaleglosc$kierunek" }
    default      { "cykl zakonczony stanem '$status' - czeka jeszcze dni: $zaleglosc$kierunek" }
  }
  $podsumowanie = [ordered]@{
    data       = (Get-Date -Format "yyyy-MM-dd HH:mm")
    status     = $status
    powod      = $powod
    nadrobione = $nadrobione
    zaleglosc  = $zaleglosc
    opis       = $opis
  }
  if ($Proba) {
    Plan "podsumowanie do $($script:Ostatni): $opis"
    return
  }
  Zapisz-Klucze $script:Ostatni $podsumowanie
}

# ---------------------------------------------------------------- narzedzia AI i warunki przed praca

# Ktore narzedzie AI stoi na maszynie, sprawdzamy na zywo - zaden krok nie zaklada
# z gory Claude Code. Brak jednego z nich to normalna maszyna, nie blad.
function Znajdz-Narzedzia {
  $lista = @()
  foreach ($n in @(
    @{ Nazwa = "Claude Code"; Polecenie = "claude"; Adres = "api.anthropic.com" },
    @{ Nazwa = "Codex";       Polecenie = "codex";  Adres = "chatgpt.com" }
  )) {
    if (Get-Command $n.Polecenie -CommandType Application -ErrorAction SilentlyContinue) { $lista += $n }
  }
  return ,$lista   # przecinek: jedno narzedzie tez ma wrocic jako lista, nie goly wpis
}

function Jest-Siec($adres) {
  # samo polaczenie TCP, zadnego odpytywania modelu - ma byc tanio i szybko.
  # Adres bierze sie z wykrytego narzedzia: na maszynie bez Claude Code
  # niedostepny api.anthropic.com nie jest zadna przeszkoda.
  if (-not [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()) { return $false }
  try {
    $klient = New-Object System.Net.Sockets.TcpClient
    $operacja = $klient.BeginConnect($adres, 443, $null, $null)
    $ok = $operacja.AsyncWaitHandle.WaitOne(3000, $false)
    if ($ok) {
      try { $klient.EndConnect($operacja) } catch { $ok = $false }
    }
    $klient.Close()
    return $ok
  } catch {
    return $false
  }
}

# $true / $false / $null, gdzie $null znaczy "nie wiadomo" - a to NIE jest powod,
# zeby cokolwiek zatrzymywac. Wolimy sprobowac i rozpoznac blad z tresci przebiegu,
# niz odlozyc material przez sprawdzenie, ktorego nie umiemy zrobic uczciwie.
function Jest-Zalogowany($narzedzie) {
  if ($narzedzie.Polecenie -eq "claude") {
    # `claude auth status --json` czyta wylacznie lokalne poswiadczenia: nie wola modelu
    # i nie zuzywa limitu. Wyczerpanego limitu stad nie widac - to poznajemy po tresci
    # bledu z samego przebiegu (patrz Rozpoznaj-Powod).
    $wyjscie = ""
    try { $wyjscie = (& claude auth status --json 2>&1 | Out-String) } catch { return $false }
    $i = $wyjscie.IndexOf("{")
    $j = $wyjscie.LastIndexOf("}")
    if ($i -lt 0 -or $j -le $i) { return $false }
    try {
      $stan = $wyjscie.Substring($i, $j - $i + 1) | ConvertFrom-Json
      return ($stan.loggedIn -eq $true)
    } catch {
      return $false
    }
  }
  if ($narzedzie.Polecenie -eq "codex") {
    # Codeksa nie odpytujemy: nie ma tu sprawdzonego polecenia, ktore czyta same
    # poswiadczenia, nie wolajac modelu. Widoczny plik z poswiadczeniami albo klucz
    # w srodowisku to "zalogowany", wszystko inne to "nie wiadomo".
    if (Test-Path (Join-Path $KatalogDomowy ".codex\auth.json")) { return $true }
    if ($env:OPENAI_API_KEY) { return $true }
    return $null
  }
  return $null
}

# Zwraca powod, dla ktorego nie da sie teraz WYLAWIAC faktow, albo $null.
# Weryfikacji to nie dotyczy - ona nie wola zadnego modelu i idzie tak czy owak.
function Znajdz-Przeszkode($narzedzia) {
  if ($narzedzia.Count -eq 0) {
    return "nie ma na tej maszynie narzedzia AI - ani claude, ani codex w PATH (Claude Code: npm install -g @anthropic-ai/claude-code)"
  }
  $zSiecia = @($narzedzia | Where-Object { Jest-Siec $_.Adres })
  if ($zSiecia.Count -eq 0) {
    return "brak sieci do: " + (($narzedzia | ForEach-Object { $_.Adres }) -join ", ")
  }
  # dosc jednego narzedzia, w ktorym nie widac wylogowania
  $gotowe = @($zSiecia | Where-Object { (Jest-Zalogowany $_) -ne $false })
  if ($gotowe.Count -eq 0) {
    return "uzytkownik wylogowany w: " + (($zSiecia | ForEach-Object { $_.Nazwa }) -join ", ")
  }
  return $null
}

# Po nieudanym przebiegu: z czego to bylo. Wyczerpany limit i zerwana siec to
# odlozenie (material czeka), reszta to zwykly blad - ale tez wraca za $OdstepMin min.
function Rozpoznaj-Powod($tekst, $kod) {
  if ($tekst) {
    # lore wola do wylawiania konkretne polecenie; gdy go tu nie ma, komunikat ma
    # mowic wprost, KTOREGO narzedzia brakuje, a nie "wylawianie nie powiodlo sie"
    if ($tekst -match '(?i)no .?(claude|codex).? in PATH|install Claude Code') {
      $czym = "modelu"
      if ($tekst -match '(?i)claude') { $czym = "polecenia claude (Claude Code)" }
      elseif ($tekst -match '(?i)codex') { $czym = "polecenia codex" }
      return "wylawianie wymaga ${czym}, a nie ma go w PATH"
    }
    if ($tekst -match '(?i)usage limit|rate.?limit|limit reached|quota|out of credit|too many requests|\b429\b') {
      return "wyczerpany limit"
    }
    if ($tekst -match '(?i)not logged in|unauthorized|authentication|invalid api key|\b401\b|claude (auth )?login') {
      return "uzytkownik wylogowany"
    }
    if ($tekst -match '(?i)ENOTFOUND|ECONNRESET|ETIMEDOUT|ECONNREFUSED|getaddrinfo|network error|offline') {
      return "brak sieci"
    }
  }
  return "wylawianie nie powiodlo sie (kod $kod)"
}

# ---------------------------------------------------------------- zaleglosc

# Ile dni materialu czeka: roznica miedzy znacznikiem ostatniego przebiegu a dzisiaj.
# Brak albo nieczytelny znacznik = jeden dzien, bo tyle bierze lore w domysle.
function Zaleglosc-Dni {
  if (-not (Test-Path -LiteralPath $script:Znacznik)) { return 1 }
  $tekst = ""
  try { $tekst = ([System.IO.File]::ReadAllText($script:Znacznik)).Trim() } catch { return 1 }
  if (-not $tekst) { return 1 }
  $data = [datetime]::MinValue
  $style = [Globalization.DateTimeStyles]::RoundtripKind
  if (-not [datetime]::TryParse($tekst, [Globalization.CultureInfo]::InvariantCulture, $style, [ref]$data)) {
    return 1
  }
  $dni = ([datetime]::Today - $data.ToLocalTime().Date).Days
  if ($dni -lt 0) { return 0 }
  return $dni
}

# Sam znacznik nie wystarczy do powiedzenia, ile JESZCZE czeka: po cichym weekendzie
# stoi on kilka dni wstecz, choc do przerobienia nie ma nic. Wylawianie samo pisze,
# ile przebiegow zostalo ("-Nadrabiaj N"), i to jest jedyna pewna odpowiedz.
# $null = nie wiadomo (wylawianie w tej probie pominiete) - wtedy liczy sie znacznik.
function Zostalo-Przebiegow($wyjscie) {
  if (-not $wyjscie) { return $null }
  $m = [regex]::Match($wyjscie, '(?i)-Nadrabiaj\s+(\d+)')
  if ($m.Success) { return [int]$m.Groups[1].Value }
  return 0
}

# ---------------------------------------------------------------- zadania w harmonogramie

function Xml-Zadania($opis, $wyzwalacze, $argumenty, $limitCzasu) {
  $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
  $argXml = [System.Security.SecurityElement]::Escape($argumenty)
  return @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>$opis</Description>
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
    <ExecutionTimeLimit>$limitCzasu</ExecutionTimeLimit>
    <StartWhenAvailable>true</StartWhenAvailable>
    <Enabled>true</Enabled>
  </Settings>
  <Triggers>
$wyzwalacze
  </Triggers>
  <Actions Context="Author">
    <Exec>
      <Command>conhost.exe</Command>
      <Arguments>$argXml</Arguments>
    </Exec>
  </Actions>
</Task>
"@
}

# Polecenie, ktore zadanie ma odpalic. conhost --headless: cykl chodzi sam przy starcie
# maszyny i nikt nie chce ogladac mrugajacego okna konsoli.
function Argumenty-Cyklu {
  $s = $PSCommandPath
  $z = $script:Zrodlo
  $arg = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$s`" -Zrodlo `"$z`""
  if ($KatalogDomowy -ne $HOME) { $arg += " -KatalogDomowy `"$KatalogDomowy`"" }
  return $arg
}

function Zaloz-Zadanie {
  Naglowek "Zadanie w harmonogramie ($NazwaZadania)"
  $argumenty = Argumenty-Cyklu
  if ($Proba) {
    Plan "Register-ScheduledTask -TaskName $NazwaZadania -Force   (nadpisuje istniejace, nie doklada drugiego)"
    Plan "  akcja     : conhost.exe $argumenty"
    Plan "  wyzwalacz : przy starcie systemu i przy zalogowaniu, z nadrobieniem (StartWhenAvailable)"
    Plan "  ponawianie: osobne zadanie $NazwaPonawiania co $OdstepMin min, najwyzej $MaxProb prob na dobe"
    exit 0
  }
  # UWAGA - sprawdzone 2026-09-16: zakladanie zadania przez obiekty
  # (New-ScheduledTaskPrincipal + Register-ScheduledTask -Principal) konczy sie
  # "Odmowa dostepu" u zwyklego, niepodniesionego uzytkownika. Ta sama operacja
  # podana jako XML przechodzi bez uprawnien administratora. Dlatego XML.
  try {
    $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    # opoznienia: przy starcie siec wstaje pozniej niz zadania, a brak sieci
    # kosztowalby jedna z pieciu prob za nic
    # UWAGA - sprawdzone 2026-09-16: <BootTrigger> odpala zadanie PRZED
    # zalogowaniem uzytkownika, wiec Windows zada do jego zalozenia uprawnien
    # administratora i konczy "Odmowa dostepu" u zwyklego uzytkownika. Samo
    # logowanie wystarcza: przed zalogowaniem i tak nie ma czego analizowac.
    $wyzwalacze = @"
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>$sid</UserId>
      <Delay>PT1M</Delay>
    </LogonTrigger>
"@
    $xml = Xml-Zadania "Lore - dzienny cykl pamieci agenta (wylawianie + weryfikacja)" $wyzwalacze $argumenty "PT2H"
    Register-ScheduledTask -TaskName $NazwaZadania -Xml $xml -Force -ErrorAction Stop | Out-Null
  } catch {
    Blad "nie udalo sie zalozyc zadania: $($_.Exception.Message)"
    Krok "jesli to 'Odmowa dostepu' - zasady tej maszyny moga wymagac uprawnien administratora"
    exit 1
  }
  Krok "cykl rusza przy starcie systemu i przy zalogowaniu - nie o sztywnej godzinie"
  Krok "nieudany przebieg wraca sam co $OdstepMin min, najwyzej $MaxProb razy na dobe"
  Krok "podsumowanie ostatniego przebiegu: $($script:Ostatni)"
  exit 0
}

function Usun-Zadanie {
  Naglowek "Usuwanie zadania ($NazwaZadania)"
  if ($Proba) {
    Plan "Unregister-ScheduledTask -TaskName $NazwaZadania -Confirm:`$false"
    Plan "Unregister-ScheduledTask -TaskName $NazwaPonawiania -Confirm:`$false"
    exit 0
  }
  $bylo = $false
  foreach ($nazwa in @($NazwaZadania, $NazwaPonawiania)) {
    $zadanie = Get-ScheduledTask -TaskName $nazwa -ErrorAction SilentlyContinue
    if (-not $zadanie) { continue }
    try {
      Unregister-ScheduledTask -TaskName $nazwa -Confirm:$false -ErrorAction Stop
      $bylo = $true
    } catch {
      Blad "nie udalo sie usunac zadania $nazwa : $($_.Exception.Message)"
      exit 1
    }
  }
  if ($bylo) { Krok "usuniete - wiedza, poczekalnia i znacznik zostaja nietkniete" }
  else       { Krok "takich zadan nie ma - nie ma czego kasowac" }
  exit 0
}

# Zadanie ponawiajace istnieje tylko miedzy nieudana proba a powodzeniem. Zamiast
# Start-Sleep, ktory blokuje i ginie razem z wylaczonym komputerem.
function Wlacz-Ponawianie {
  if ($Proba) { Plan "zalozenie zadania $NazwaPonawiania - powrot co $OdstepMin min"; return }
  try {
    $start = (Get-Date).AddMinutes($OdstepMin).ToString("yyyy-MM-ddTHH:mm:ss")
    $wyzwalacze = @"
    <TimeTrigger>
      <StartBoundary>$start</StartBoundary>
      <Repetition>
        <Interval>PT${OdstepMin}M</Interval>
        <Duration>PT2H</Duration>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <Enabled>true</Enabled>
    </TimeTrigger>
"@
    $xml = Xml-Zadania "Lore - ponowienie dziennego cyklu pamieci po nieudanej probie" $wyzwalacze (Argumenty-Cyklu) "PT1H"
    Register-ScheduledTask -TaskName $NazwaPonawiania -Xml $xml -Force -ErrorAction Stop | Out-Null
    Krok "powrot za $OdstepMin min (zadanie $NazwaPonawiania)"
  } catch {
    Ostrzezenie "nie udalo sie zalozyc ponawiania: $($_.Exception.Message) - cykl wroci przy nastepnym starcie"
  }
}

function Wylacz-Ponawianie {
  if ($Proba) { return }
  $zadanie = Get-ScheduledTask -TaskName $NazwaPonawiania -ErrorAction SilentlyContinue
  if (-not $zadanie) { return }
  try { Unregister-ScheduledTask -TaskName $NazwaPonawiania -Confirm:$false -ErrorAction Stop } catch { }
}

# ---------------------------------------------------------------- kroki cyklu

# Odlozenie, nie porazka: kod 0, znacznik nietkniety, material czeka na nastepna probe.
# $ponawiaj = $false dla powodow, ktore same z siebie nie przejda (brak narzedzia AI) -
# wracanie co $OdstepMin min przepalaloby tylko proby.
function Odloz($stan, $powod, $ponawiaj = $true) {
  $stan["status"] = "odlozony"
  $stan["powod"]  = $powod
  $stan["czas"]   = (Get-Date -Format "yyyy-MM-dd HH:mm")
  Zapisz-Stan $stan
  $proby = [int]$stan["proby"]
  if (-not $ponawiaj) {
    Wylacz-Ponawianie
    Zapisz-Podsumowanie "odlozony" $powod 0 (Zaleglosc-Dni)
    Ostrzezenie "$powod - material czeka nietkniety, cykl wroci przy nastepnym zalogowaniu"
    exit 0
  }
  if ($proby -ge $MaxProb) {
    Wylacz-Ponawianie
    Zapisz-Podsumowanie "wyczerpane" $powod 0 (Zaleglosc-Dni)
    Ostrzezenie "$powod - to byla $proby. proba z $MaxProb, na dzis koniec; material czeka nietkniety"
  } else {
    Zapisz-Podsumowanie "odlozony" $powod 0 (Zaleglosc-Dni)
    Krok "odlozone: $powod (proba $proby z $MaxProb)"
    Wlacz-Ponawianie
  }
  exit 0
}

function Wylow-Fakty($stan, $nadrabiaj, $przeszkoda) {
  Naglowek "1/2  Wylawianie faktow z zaleglych dni"
  if ($stan["wylowione"] -eq "ok") {
    # krok 2 juz sie dzis udal - powtorka jest tylko po to, zeby dokonczyc krok 3.
    # Modelu drugi raz nie wolamy: potkniecie na weryfikacji nie ma kosztowac limitu.
    Krok "dzis juz przeszlo - w tej probie tylko weryfikacja"
    return
  }
  # To jedyny krok, ktory potrzebuje modelu. Przeszkoda zatrzymuje wiec jego, a nie
  # caly przebieg: weryfikacja czyta pliki i idzie dalej niezaleznie od dostawcy.
  if ($przeszkoda) {
    $script:Pominiete = $przeszkoda
    if ($Proba) { Plan "wylawianie pominiete: $przeszkoda" }
    else        { Krok "pominiete (wymaga modelu): $przeszkoda" }
    Krok "weryfikacja idzie dalej - ona modelu nie wola"
    return
  }
  if ($Proba) {
    Plan "wyciagnij-fakty.ps1 -Zrodlo $($script:Zrodlo) -Nadrabiaj $nadrabiaj"
    return
  }
  $argumenty = @{ Zrodlo = $script:Zrodlo; Nadrabiaj = $nadrabiaj }
  $global:LASTEXITCODE = 0
  $wyjscie = (& $script:Wyciagnij @argumenty *>&1 | Out-String)
  $kod = $LASTEXITCODE
  Write-Host $wyjscie
  if ($kod -ne 0) {
    # znacznik sie nie przesunal, wiec material czeka - odlozenie ustawiamy dopiero
    # po weryfikacji, zeby jej nie zabrac przez potkniecie na samym modelu
    $script:Pominiete = Rozpoznaj-Powod $wyjscie $kod
    Ostrzezenie "wylawianie stanelo: $($script:Pominiete) - weryfikacja idzie dalej"
    return
  }
  $script:Zostalo = Zostalo-Przebiegow $wyjscie
  $stan["wylowione"] = "ok"
  Zapisz-Stan $stan
}

# Weryfikacja nie wola modelu (-BezWylawiania), wiec nic nie kosztuje. Gdy sie potknie,
# wylowione fakty i tak zostaja w poczekalni - stad zwracany kod zamiast przerwania.
function Sprawdz-Wiedze {
  Naglowek "2/2  Weryfikacja i zatwierdzenie potwierdzonych"
  if ($Proba) {
    Plan "aktualizuj-wiedze.ps1 -Zrodlo $($script:Zrodlo) -BezWylawiania"
    return 0
  }
  $argumenty = @{ Zrodlo = $script:Zrodlo; BezWylawiania = $true }
  # aktualizuj-wiedze.ps1 chce wprost katalogu .claude, nie katalogu domowego
  if ($KatalogDomowy -ne $HOME) { $argumenty["KatalogDomowy"] = $script:Dom }
  $global:LASTEXITCODE = 0
  # Out-Host, a nie samo wywolanie: uv pisze na wyjscie standardowe, a to wpadloby
  # do wartosci zwracanej przez ta funkcje i zmieszalo sie z kodem wyjscia
  & $script:Aktualizuj @argumenty | Out-Host
  return $LASTEXITCODE
}

function Uruchom-Cykl {
  $dzis = (Get-Date -Format "yyyy-MM-dd")
  $stan = Czytaj-Klucze $script:PlikStanu
  if ($stan["data"] -ne $dzis) {
    # nowy dzien - licznik prob startuje od zera, stary powod juz nieaktualny
    $stan = [ordered]@{ data = $dzis; proby = "0" }
  }

  if ($stan["status"] -eq "ok") {
    Wylacz-Ponawianie
    Krok "dzisiejszy cykl juz przeszedl ($($stan['czas'])) - nie ma czego powtarzac"
    exit 0
  }

  $proby = 0
  if ($stan["proby"] -match '^\d+$') { $proby = [int]$stan["proby"] }
  if ($proby -ge $MaxProb) {
    Wylacz-Ponawianie
    Krok "na dzis koniec prob ($proby z $MaxProb) - cykl wroci jutro, material czeka nietkniety"
    exit 0
  }

  # licznik podnosimy PRZED praca: przebieg, ktory sie wywroci, ma sie policzyc
  $proby++
  $stan["proby"] = "$proby"
  Zapisz-Stan $stan

  Naglowek "Cykl dzienny pamieci ($dzis, proba $proby z $MaxProb)"
  $narzedzia = Znajdz-Narzedzia
  if ($narzedzia.Count -gt 0) {
    Krok ("narzedzia AI na tej maszynie: " + (($narzedzia | ForEach-Object { $_.Nazwa }) -join ", "))
  } else {
    Krok "narzedzi AI nie widac - ida tylko kroki, ktore czytaja pliki"
  }
  # przeszkoda dotyczy WYLAWIANIA, nie calego przebiegu - dlatego nie ma tu Odloz
  $przeszkoda = Znajdz-Przeszkode $narzedzia

  $zaleglosc = Zaleglosc-Dni
  $nadrabiaj = [math]::Max(1, [math]::Min($zaleglosc, $MaxNadrabiania))
  if ($zaleglosc -gt $MaxNadrabiania) {
    Krok "zaleglosc: $zaleglosc dni - biore $nadrabiaj (wiecej na raz przepalaloby limit), reszta jutro"
  } else {
    Krok "zaleglosc: $zaleglosc dni - biore $nadrabiaj"
  }

  Wylow-Fakty $stan $nadrabiaj $przeszkoda
  $kodWeryfikacji = Sprawdz-Wiedze

  # nadrobione = o ile przesunal sie znacznik; zostalo = co wylawianie samo zglosilo
  $nadrobione = $zaleglosc - (Zaleglosc-Dni)
  if ($nadrobione -lt 0) { $nadrobione = 0 }
  $poZaleglosc = Zaleglosc-Dni
  if ($null -ne $script:Zostalo) {
    $poZaleglosc = $script:Zostalo
  }

  if ($kodWeryfikacji -ne 0) {
    # fakty sa juz wylowione i leza w poczekalni - tego zadna powtorka nie cofnie
    Odloz $stan "weryfikacja nie powiodla sie (kod $kodWeryfikacji)"
  }

  # weryfikacja przeszla, ale wylawianie nie poszlo - dzien nie jest zamkniety.
  # Brak narzedzia AI sam sie nie naprawi, wiec wtedy bez ponawiania co $OdstepMin min.
  if ($script:Pominiete) {
    Odloz $stan $script:Pominiete ($narzedzia.Count -gt 0)
  }

  $stan["status"] = "ok"
  $stan["proby"]  = "0"          # dzien zamkniety - licznik czysty
  $stan["czas"]   = (Get-Date -Format "yyyy-MM-dd HH:mm")
  $stan.Remove("powod")
  Zapisz-Stan $stan
  Wylacz-Ponawianie
  Zapisz-Podsumowanie "ok" "" $nadrobione $poZaleglosc

  Naglowek "Podsumowanie"
  Krok "nadrobione dni: $nadrobione"
  if ($poZaleglosc -gt 0) { Krok "czeka jeszcze: $poZaleglosc dni - nadrobi sie przy kolejnych przebiegach" }
  else                    { Krok "zaleglosci nie ma - material jest przerobiony na biezaco" }
  Krok "podsumowanie: $($script:Ostatni)"
  exit 0
}

# ---------------------------------------------------------------- przebieg

Ustaw-Sciezki

if ($UsunZadanie)  { Usun-Zadanie }
if ($ZalozZadanie) { Zaloz-Zadanie }

# Zadanie glowne chodzi przy starcie I przy zalogowaniu, a ponawiajace co $OdstepMin min -
# bez zamka dwa przebiegi potrafilyby wejsc sobie w droge i policzyc podwojna probe.
$zamek = New-Object System.Threading.Mutex($false, "Local\MegaRuchacz-LoreCykl")
$mojZamek = $false
# porzucony zamek (poprzedni przebieg padl w polowie) liczy sie jako wolny - inaczej
# jedna wywrotka blokowalaby cykl az do restartu maszyny
try { $mojZamek = $zamek.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $mojZamek = $true }
if (-not $mojZamek) { exit 0 }

Uruchom-Cykl
