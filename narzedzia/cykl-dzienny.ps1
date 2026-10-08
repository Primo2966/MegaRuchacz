# Cykl dzienny pamieci agenta - jedno uruchomienie spina cala robote:
# wylawianie faktow z zaleglych dni, weryfikacje i podsumowanie.
#
# Rzecz, dla ktorej to powstalo: zadanie o sztywnej godzinie przepada, gdy komputer byl
# wylaczony, siec padla, uzytkownik byl wylogowany albo skonczyl sie limit. Dlatego:
#   - cykl rusza przy PIERWSZEJ SESJI danego dnia (Claude Code, Codex albo OpenCode - startuje go
#     straznik-zasad.ps1 osobnym procesem), a nie o ustalonej porze ani przy zalogowaniu.
#     Komputer wlaczony o 13:00 i pierwsze okno o 15:00 znaczy cykl o 15:00, przy czym
#     sesja na nic nie czeka: hook ma kilkanascie sekund, a cykl trwa minuty,
#   - o tym, ze pracuje, mowi plik .cykl-postep - jedna linia stanu doklejana do kazdej
#     wiadomosci uzytkownika (narzedzia\przypomnienie.js), a na koniec meldunek o koszcie,
#   - warunki sprawdzane sa PRZED praca: brak sieci czy limitu to ODLOZENIE, nie porazka
#     (znacznik ostatniego przebiegu sie nie przesuwa, wiec material czeka nietkniety),
#   - nieudany przebieg wraca przy nastepnym otwarciu okna, najwyzej $MaxProb razy dziennie -
#     bez Start-Sleep, ktory ginie przy wylaczeniu maszyny, i bez zadania w harmonogramie,
#   - zaleglosc liczy sie w PRZEBIEGACH WYLAWIANIA, nie w dniach kalendarza. Jeden gesty
#     dzien pracy to kilka przebiegow, wiec "1 dzien zaleglosci" potrafilo znaczyc 133
#     czekajace kawalki rozmow - i tak wlasnie cykl 2026-09-17 zameldowal "ok" po zabraniu
#     jednej piatej materialu. Ile naprawde czeka, mowi samo wylawianie (przebieg probny,
#     bez modelu, 0,4 s) - arytmetyki na kalendarzu nie ma tu juz w ogole,
#   - na jedno podejscie idzie najwyzej $MaxNadrabiania przebiegow (ochrona limitu), a po
#     reszte cykl wraca w nastepnym dniu pracy - dzien bez wlaczonego komputera po prostu
#     nie istnieje, wiec liczy sie pierwsza sesja kolejnego dnia, a nie kolejna doba.
#
# Cykl NIE jest przywiazany do jednego narzedzia AI. Czytanie transkryptow, indeksowanie
# i weryfikacja to robota na plikach - modelu potrzebuje wylacznie wylawianie faktow.
# Rozmowy czyta wylawianie z bazy Lore, a ta obejmuje wszystkie trzy zrodla naraz:
# ~\.claude\projects, ~\.codex\sessions i baze OpenCode (lore\lore\index.py). Fakty trafiaja
# do pliku instrukcji kazdego narzedzia, ktore tu jest (lore\lore\verify.py INSTRUCTION_PATHS).
# Dlatego narzedzia (Claude Code, Codex, OpenCode) wykrywane sa na zywo, brak ktoregos to
# normalna maszyna, a brak wszystkich zatrzymuje SAMO wylawianie - weryfikacja idzie dalej.
# Kolejnosc jak w lore\lore\facts.py MODEL_CLIS: Claude Code, potem Codex, OpenCode na koncu.
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File narzedzia\cykl-dzienny.ps1
#   ... -Zrodlo <sciezka>         katalog glowny repozytorium (domyslnie: katalog nad narzedzia\)
#   ... -Proba                    pokazuje, co by zrobil; nie wola modelu i niczego nie zapisuje
#   ... -KatalogDomowy <sciezka>  podmiana katalogu domowego (do testow; ustawia LORE_HOME)
#   ... -UsunZadanie              zdejmuje z Harmonogramu stare zadania cyklu (sprzatanie)
#   ... -Recznie                  czytanie reczne z okna nadzorcy, po potwierdzeniu kosztu - czyta
#                                 od znacznika takze po dzisiejszym przebiegu (patrz "czytanie reczne")

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Proba,
  [string]$KatalogDomowy = $HOME,
  [switch]$UsunZadanie,
  [switch]$Recznie
)

# Zadania z Harmonogramu, ktore kiedys odpalaly ten cykl o sztywnej porze. Dzis
# rusza go pierwsza sesja dnia, wiec obie nazwy zostaja tu wylacznie po to, zeby
# je z maszyn ZDEJMOWAC (patrz Usun-Zadanie i narzedzia\instaluj-lore.ps1).
$NazwaZadania    = "LoreCykl"
$NazwaPonawiania = "LoreCyklPonow"
$MaxProb         = 5    # tyle podejsc na dobe (razem z doganianiem kolejki) - potem dzien
                        # odpuszczamy, material i tak czeka nietkniety
$MaxNadrabiania  = 5    # gorny limit przebiegow wylawiania na JEDNO podejscie (ochrona limitu);
                        # wieksza kolejke cykl bierze na raty, wracajac przy nastepnym oknie

$script:Dom       = $null
$script:Wiedza    = $null
$script:PlikStanu = $null
$script:Ostatni   = $null
$script:Znacznik  = $null
$script:Postep    = $null   # jedna linia stanu dla hooka przypomnienia (praca / meldunek koncowy)
$script:Koszt     = $null   # .koszt-cyklu.txt - pisze go samo wylawianie (lore\lore\facts.py)
$script:Wyciagnij = $null
$script:Aktualizuj = $null
$script:Zostalo   = $null   # ile przebiegow zaleglosci zostalo wg samego wylawiania
$script:Kawalki   = $null   # ile kawalkow materialu czeka (to samo zrodlo, jednostka po ludzku)
$script:Czeka     = $null   # ile czekalo PRZED ta praca - do porownania, czy kolejka rosnie
$script:Mozliwe   = $null   # ile przebiegow cykl zdazy jeszcze wziac do konca doby
$script:Pominiete = $null   # powod, dla ktorego wylawianie nie poszlo ($null = poszlo)
$script:Porcje    = 0       # ile porcji materialu poszlo do modelu w TYM przebiegu
$script:KosztStart = @{ tokeny = 0; fakty = 0; wywolania = 0 }  # licznik kosztu sprzed pracy
$script:ZnacznikPrzed = $null  # dokad siegal odczyt, zanim cykl przesunal znacznik
$script:PlikRecznego = $null   # .cykl-reczny - wynik czytania recznego z okna (-Recznie)
$script:RecznyStart  = $null   # kiedy ruszyl ten przebieg reczny - po tym okno poznaje "swoj" wynik
$script:StatusPrzed  = $null   # status dnia z .cykl-stan sprzed recznego przebiegu

# Zapis odporny na zanik pradu i rozpoznawanie wyzerowanych plikow (awaria 2026-10-02).
. (Join-Path $PSScriptRoot "zapis-trwaly.ps1")

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
  $script:Postep    = Join-Path $script:Wiedza ".cykl-postep"
  $script:Koszt     = Join-Path $script:Wiedza ".koszt-cyklu.txt"
  $script:PlikRecznego = Join-Path $script:Wiedza ".cykl-reczny"

  # wyciagnij-fakty.ps1 nie ma wlasnego przelacznika katalogu - lore czyta LORE_HOME,
  # wiec podmiana idzie przez zmienna srodowiskowa i obejmuje oba wolane skrypty
  if ($KatalogDomowy -ne $HOME) {
    $env:LORE_HOME = $script:Dom
    Ostrzezenie "katalog domowy podmieniony na $($script:Dom) - prawdziwa wiedza nie jest ruszana"
  }
}

function Bez-Bom { return (New-Object System.Text.UTF8Encoding($false)) }

# Plik tymczasowy + zapis przez bufor dysku + podmiana (narzedzia\zapis-trwaly.ps1) - .cykl-postep
# zapisany zwyklym WriteAllText byl 2026-10-02 jednym z wyzerowanych plikow.
function Zapisz-Tekst($sciezka, $tekst) {
  Zapisz-Trwale $sciezka $tekst (Bez-Bom)
}

# Pliki stanu trzymaja proste "klucz: wartosc" - tak samo jak reszta narzedzia,
# dzieki czemu straznik-zasad.ps1 czyta podsumowanie tym samym kodem.
function Klucze-Z-Tekstu($raw) {
  $stan = [ordered]@{}
  if (-not $raw) { return $stan }
  foreach ($l in ($raw -split '\r?\n')) {
    $m = [regex]::Match($l, '^\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*:\s*(.*?)\s*$')
    if ($m.Success) { $stan[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $stan
}

function Czytaj-Klucze($sciezka) {
  if (-not (Test-Path -LiteralPath $sciezka)) { return [ordered]@{} }
  $raw = $null
  try { $raw = [System.IO.File]::ReadAllText($sciezka) } catch { return [ordered]@{} }
  return Klucze-Z-Tekstu $raw
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

# ---------------------------------------------------------------- widoczny postep

# Cykl trwa minuty i chodzi w tle, wiec bez tego pliku uzytkownik nie ma ZADNEGO
# sladu, ze cokolwiek sie dzieje - a wlasnie o to prosil: "jakis napis i pasek
# postepu, ze cos robi". Linie sklada tutaj sam cykl, gotowa do wypisania: hook
# przypomnienia (narzedzia\przypomnienie.js) chodzi przy KAZDYM enterze i nie ma
# prawa niczego liczyc ani otwierac bazy.
#   stan: pracuje  - linia idzie przy kazdej wiadomosci, az do konca pracy
#   stan: koniec   - meldunek o koszcie; hook pokazuje go RAZ i kasuje plik
function Zapisz-Postep($stan, $linia) {
  if ($Proba) { return }
  $wpis = [ordered]@{
    stan  = $stan
    czas  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    linia = $linia
  }
  try { Zapisz-Klucze $script:Postep $wpis } catch { }   # meldunek nie ma prawa zabrac roboty
}

function Skasuj-Postep {
  if ($Proba) { return }
  if (Test-Path -LiteralPath $script:Postep) {
    try { Remove-Item -LiteralPath $script:Postep -Force } catch { }
  }
}

# Ile tokenow i faktow ma na koncie DZISIEJSZY dzien. facts.py sumuje przebiegi
# w obrebie doby, wiec koszt samego tego przebiegu to roznica: "po" minus "przed".
function Licznik-Kosztu {
  $k = Czytaj-Klucze $script:Koszt
  $w = @{ tokeny = 0; fakty = 0; wywolania = 0 }
  foreach ($klucz in @("tokeny", "fakty", "wywolania")) {
    if ($k[$klucz] -match '^\d+$') { $w[$klucz] = [long]$k[$klucz] }
  }
  return $w
}

function Liczba-Ludzka($n) {
  # separator tysiecy na sztywno spacja - tak samo jak w koszt-pamieci.ps1
  return ([long]$n).ToString("#,0", [Globalization.CultureInfo]::InvariantCulture).Replace(",", " ")
}

# Znacznik ostatniego odczytu (.ostatnie-wyciaganie) po ludzku - to JEDYNE, co wyznacza
# zakres materialu: lore bierze wszystko, co ma znacznik czasu pozniejszy (facts.py:
# since_marker + "ts > since"). Zaden kalendarz, zadne "wczoraj". Pusto = jeszcze nigdy
# nie czytane, wtedy lore siega 24 h wstecz.
function Czytaj-Znacznik {
  if (-not (Test-Path -LiteralPath $script:Znacznik)) { return $null }
  $tekst = ""
  try { $tekst = ([System.IO.File]::ReadAllText($script:Znacznik)).Trim() } catch { return $null }
  if (-not $tekst) { return $null }
  $data = [datetime]::MinValue
  $style = [Globalization.DateTimeStyles]::RoundtripKind
  if (-not [datetime]::TryParse($tekst, [Globalization.CultureInfo]::InvariantCulture, $style, [ref]$data)) {
    return $null
  }
  return $data.ToLocalTime()
}

function Opis-Znacznika($data) {
  if ($null -eq $data) { return "od poczatku (znacznika nie bylo)" }
  return $data.ToString("yyyy-MM-dd HH:mm")
}

# Podsumowanie czyta straznik przy starcie sesji - stad i klucze, i gotowy opis po ludzku.
# Zaleglosc przejsciowa i zaleglosc trwala wygladaja identycznie: "czeka X". Ta druga
# znaczy, ze limit na jeden przebieg jest za maly i system NIGDY nie nadgoni - a przez
# miesiace wyglada normalnie. Jedyne, co je odroznia, to kierunek: czy kolejka maleje,
# czy rosnie. Dlatego porownujemy z poprzednim przebiegiem i mowimy wprost, gdy nie nadazamy.
#
# UWAGA - dwa bledy, ktore to porownanie unieruchamialy do 2026-09-17:
#   - poprzednia wartosc czytana byla przez ConvertFrom-Json, a cykl-ostatni.txt to zapis
#     "klucz: wartosc"; wyjatek ladowal w pustym catch, wiec kierunku NIGDY nie bylo widac,
#   - zapisywana liczba raz znaczyla dni, raz przebiegi wylawiania - czyli porownanie
#     jablek z gruszkami. Teraz obie strony to przebiegi, i to pod wlasnym kluczem.
function Kierunek-Zaleglosci($zostalo) {
  $poprzednie = $null
  $stare = Czytaj-Klucze $script:Ostatni
  if ($stare["przebiegi"] -match '^\d+$') { $poprzednie = [int]$stare["przebiegi"] }
  if ($null -eq $poprzednie -or $zostalo -le 0) { return "" }
  if ($zostalo -gt $poprzednie) {
    return " UWAGA: kolejka ROSNIE ($poprzednie -> $zostalo przebiegow) - material przybywa szybciej, niz jest nadrabiany, i system nie nadgoni sam. Zwieksz MAX_INPUT_CHARS w lore\lore\facts.py albo uruchom recznie: narzedzia\wyciagnij-fakty.ps1 -Nadrabiaj $zostalo"
  }
  if ($zostalo -lt $poprzednie) { return " (maleje: $poprzednie -> $zostalo przebiegow, nadrabia sie)" }
  return " (stoi w miejscu od poprzedniego przebiegu - sprawdz, czy cos nie blokuje)"
}

# Jednostka, ktora cos znaczy dla czlowieka. "dni: 0" przy 133 czekajacych kawalkach
# rozmowy to komunikat usypiajacy - stad material zawsze w kawalkach, przebiegi obok.
function Opis-Kolejki($zostalo) {
  if ($zostalo -le 0) { return "zaleglosci nie ma - material jest przerobiony na biezaco" }
  $ogon = ""
  if ($null -ne $script:Kawalki -and $script:Kawalki -gt 0) { $ogon = " ($($script:Kawalki) kawalkow materialu)" }
  return "czeka jeszcze $zostalo przebiegow wylawiania$ogon"
}

function Zapisz-Podsumowanie($status, $powod, $nadrobione, $zaleglosc) {
  $kierunek = Kierunek-Zaleglosci $zaleglosc
  $czeka = Opis-Kolejki $zaleglosc
  $zdaze = $script:Mozliwe
  if ($null -eq $zdaze) { $zdaze = 0 }
  $opis = switch ($status) {
    "ok"          { "cykl przeszedl - nadrobione przebiegi: $nadrobione, $czeka$kierunek" }
    "dogania"     { "UWAGA: kolejka nie jest pusta - nadrobione przebiegi: $nadrobione, $czeka; wroce po reszte przy pierwszej sesji nastepnego dnia pracy$kierunek" }
    "nie nadaza"  { "UWAGA: cykl NIE NADAZA - nadrobione przebiegi: $nadrobione, $czeka, a do konca doby zdazy najwyzej $zdaze$kierunek" }
    "odlozony"    { "cykl odlozony ($powod) - $czeka$kierunek" }
    "wyczerpane"  { "cykl odpuszczony po $MaxProb probach ($powod) - $czeka$kierunek" }
    "wyzerowane"  { "$powod" }
    default       { "cykl zakonczony stanem '$status' - $czeka$kierunek" }
  }
  $podsumowanie = [ordered]@{
    data       = (Get-Date -Format "yyyy-MM-dd HH:mm")
    status     = $status
    powod      = $powod
    nadrobione = $nadrobione
    przebiegi  = $zaleglosc
    kawalki    = $(if ($null -ne $script:Kawalki) { $script:Kawalki } else { "" })
    # zaleglosc: ta sama liczba pod stara nazwa - straznik-zasad.ps1 czyta ten klucz
    # i po nim poznaje, czy ma sie odezwac przy starcie sesji
    zaleglosc  = $zaleglosc
    opis       = $opis
    uruchomienie = $(if ($Recznie) { "reczne z okna" } else { "automat" })
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
    @{ Nazwa = "Claude Code"; Polecenie = "claude";   Adres = "api.anthropic.com" },
    @{ Nazwa = "Codex";       Polecenie = "codex";    Adres = "chatgpt.com" },
    @{ Nazwa = "OpenCode";    Polecenie = "opencode"; Adres = (Adres-Opencode) }
  )) {
    if (Get-Command $n.Polecenie -CommandType Application -ErrorAction SilentlyContinue) { $lista += $n }
  }
  return ,$lista   # przecinek: jedno narzedzie tez ma wrocic jako lista, nie goly wpis
}

# OpenCode nie ma jednego dostawcy: rozmawia z tym, do ktorego uzytkownik sie zalogowal
# (u nas openrouter). Siec sprawdzamy wiec pod adresem tego dostawcy - z NAZW wpisow
# w auth.json (tresci, czyli kluczy, nie czytamy). Nieznany dostawca albo brak pliku:
# models.dev, skad OpenCode i tak pobiera liste modeli.
function Adres-Opencode {
  $znane = [ordered]@{
    openrouter = "openrouter.ai"; anthropic = "api.anthropic.com"; openai = "api.openai.com"
    google = "generativelanguage.googleapis.com"; deepseek = "api.deepseek.com"; opencode = "opencode.ai"
  }
  $plik = Join-Path $KatalogDomowy ".local\share\opencode\auth.json"
  if (Test-Path -LiteralPath $plik) {
    try {
      $wpisy = @((Get-Content -LiteralPath $plik -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties.Name)
      foreach ($k in $znane.Keys) { if ($wpisy -contains $k) { return $znane[$k] } }
    } catch {
      Ostrzezenie "nie umiem odczytac $plik ($($_.Exception.Message)) - siec dla OpenCode sprawdzam pod models.dev"
    }
  }
  return "models.dev"
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
  if ($narzedzie.Polecenie -eq "opencode") {
    # To samo podejscie: `opencode auth list` nie jest tu sprawdzone jako polecenie bez modelu.
    # Logowania OpenCode leza w ~\.local\share\opencode\auth.json - jest plik, jest logowanie;
    # bez pliku dostawca moze brac klucz ze srodowiska, czyli "nie wiadomo".
    if (Test-Path (Join-Path $KatalogDomowy ".local\share\opencode\auth.json")) { return $true }
    return $null
  }
  return $null
}

# Zwraca powod, dla ktorego nie da sie teraz WYLAWIAC faktow, albo $null.
# Weryfikacji to nie dotyczy - ona nie wola zadnego modelu i idzie tak czy owak.
function Znajdz-Przeszkode($narzedzia) {
  if ($narzedzia.Count -eq 0) {
    return "nie ma na tej maszynie narzedzia AI - ani claude, ani codex, ani opencode w PATH (Claude Code: npm install -g @anthropic-ai/claude-code)"
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
# odlozenie (material czeka), reszta to zwykly blad - obie wracaja przy nastepnym otwarciu okna.
function Rozpoznaj-Powod($tekst, $kod) {
  if ($tekst) {
    # lore odmowil pracy na wyzerowanych plikach (kod 3, lore\lore\safeio.py) - jego zdanie
    # mowi juz wszystko: ktory plik, gdzie zdrowa kopia i jak przywrocic
    $m = [regex]::Match($tekst, 'ALARM: wyzerowane pliki pamieci[^\r\n]*')
    if ($m.Success) { return $m.Value }
    # lore wola do wylawiania konkretne polecenie; gdy go tu nie ma, komunikat ma
    # mowic wprost, KTOREGO narzedzia brakuje, a nie "wylawianie nie powiodlo sie"
    # "no agent CLI in PATH - looked for `claude`, `codex`, `opencode`" (facts.py ModelMissing)
    # wymienia wszystkie trzy, wiec nie wolno z niego wyczytac jednego narzedzia
    if ($tekst -match '(?i)no agent CLI in PATH') {
      return "wylawianie wymaga narzedzia AI (claude, codex albo opencode), a nie ma zadnego w PATH"
    }
    if ($tekst -match '(?i)no .?(claude|codex|opencode).? in PATH|install Claude Code') {
      $czym = "modelu"
      if ($tekst -match '(?i)no .?claude.? in PATH|install Claude Code') { $czym = "polecenia claude (Claude Code)" }
      elseif ($tekst -match '(?i)no .?codex.? in PATH') { $czym = "polecenia codex" }
      elseif ($tekst -match '(?i)no .?opencode.? in PATH') { $czym = "polecenia opencode" }
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

# UWAGA - usuniete 2026-09-17: liczenie zaleglosci w DNIACH kalendarza (znacznik kontra
# dzisiaj). Material bierze sie wylacznie OD ZNACZNIKA ostatniego odczytu
# (~\.claude\wiedza\.ostatnie-wyciaganie; lore\lore\facts.py: since_marker + "ts > since"),
# a nie z wczorajszej doby - i jedyna uczciwa miara tego, ile czeka, jest sama kolejka
# (Stan-Kolejki). Arytmetyka na dniach mowila "1 dzien", gdy czekalo 133 kawalkow rozmow.

# Sam znacznik nie wystarczy do powiedzenia, ile JESZCZE czeka: po cichym weekendzie
# stoi on kilka dni wstecz, choc do przerobienia nie ma nic - a po gestym dniu wskazuje
# wczoraj, choc czeka piec przebiegow. Jedyne pewne zrodlo to samo wylawianie, i pytamy
# je wprost o liczby (wyciagnij-fakty.ps1 -Kolejka), zamiast wyczytywac je z tekstu.
#
# Przebieg probny modelu nie wola, znacznika nie przesuwa i - zmierzone 2026-09-17 na tej
# maszynie - trwa 0,4 s. Dlatego pytamy PRZED decyzja, ile wziac, a nie opieramy sie na
# liczbie sprzed doby. Zwraca @{ przebiegi; kawalki } albo $null, gdy odczyt sie nie udal.
function Stan-Kolejki {
  $global:LASTEXITCODE = 0
  $wyjscie = ""
  try { $wyjscie = (& $script:Wyciagnij -Zrodlo $script:Zrodlo -Kolejka *>&1 | Out-String) }
  catch { return $null }
  if ($LASTEXITCODE -ne 0) { return $null }
  $klucze = Klucze-Z-Tekstu $wyjscie
  if ($klucze["kolejka.przebiegi"] -notmatch '^\d+$') { return $null }
  $kawalki = 0
  if ($klucze["kolejka.kawalki"] -match '^\d+$') { $kawalki = [int]$klucze["kolejka.kawalki"] }
  return @{ przebiegi = [int]$klucze["kolejka.przebiegi"]; kawalki = $kawalki }
}

# Zapas na wypadek, gdyby odczyt kolejki nie wyszedl: wylawianie na koniec pisze po ludzku,
# ile przebiegow zostalo ("-Nadrabiaj N"). $null = nie wiadomo (wylawianie pominiete).
function Zostalo-Przebiegow($wyjscie) {
  if (-not $wyjscie) { return $null }
  # przy -Nadrabiaj N takich linii jest kilka, po jednej na przebieg - liczy sie OSTATNIA,
  # bo tylko ona mowi o kolejce po calej pracy; pierwsza znaczylaby stan sprzed niej
  $trafienia = [regex]::Matches($wyjscie, '(?i)-Nadrabiaj\s+(\d+)')
  if ($trafienia.Count -gt 0) { return [int]$trafienia[$trafienia.Count - 1].Groups[1].Value }
  return 0
}

# Ile czeka w tej chwili, najlepsza znana odpowiedz: po pracy liczba od wylawiania,
# przed praca stan kolejki z poczatku przebiegu. Gdy nie wiadomo nic - jeden przebieg,
# bo tyle bierze wylawianie w domysle; zgadywanie z kalendarza juz tu nie ma.
function Ile-Czeka {
  if ($null -ne $script:Zostalo) { return $script:Zostalo }
  if ($null -ne $script:Czeka)   { return $script:Czeka }
  return 1
}

# ---------------------------------------------------------------- sprzatanie po harmonogramie

# Cykl NIE MA juz zadnego zadania w Harmonogramie - rusza go pierwsza sesja dnia
# (straznik-zasad.ps1). Obie nazwy zostaja wylacznie po to, zeby je z maszyn ZDEJMOWAC:
# zadanie o sztywnej porze albo przy zalogowaniu robilo robote wtedy, gdy nikt na nia
# nie patrzyl, a przy komputerze wlaczanym po poludniu nie robilo jej wcale.
# Brak zadania to normalna sytuacja, nie blad.
function Usun-Zadanie {
  Naglowek "Usuwanie starych zadan cyklu ($NazwaZadania, $NazwaPonawiania)"
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
  if ($bylo) { Krok "usuniete - cykl rusza teraz przy pierwszej sesji dnia; wiedza i znacznik nietkniete" }
  else       { Krok "takich zadan nie ma - nie ma czego kasowac" }
  exit 0
}

# To samo sprzatanie, ale po cichu i w locie: gdy cykl chodzi na maszynie, na ktorej
# zostalo stare zadanie ponawiajace, zdejmujemy je przy okazji. Inaczej dwa mechanizmy
# odpalalyby te sama robote i liczyly podwojne proby.
function Zdejmij-Stare-Zadanie {
  if ($Proba) { return }
  $zadanie = Get-ScheduledTask -TaskName $NazwaPonawiania -ErrorAction SilentlyContinue
  if (-not $zadanie) { return }
  try { Unregister-ScheduledTask -TaskName $NazwaPonawiania -Confirm:$false -ErrorAction Stop } catch { }
}

# ---------------------------------------------------------------- czytanie reczne z okna (-Recznie)

# Do 2026-10-08 przycisk "Przeczytaj teraz nowe rozmowy" w oknie nadzorcy odpalal ten sam
# przebieg co dozor - a ten po dzisiejszym udanym cyklu konczyl sie od razu ("dzisiejszy cykl
# juz przeszedl - nie ma czego powtarzac"), choc od porannego odczytu przybyly nowe rozmowy.
# Okno liczylo koszt z kolejki (jest co czytac), cykl patrzyl na kalendarz (dzis juz bylo):
# uzytkownik potwierdzal koszt i nie dzialo sie nic, bez slowa. Dlatego -Recznie:
#   - czyta od znacznika ostatniego odczytu takze po dzisiejszym przebiegu, a wylawianie,
#     ktore dzis juz przeszlo, nie zamienia sie w sama weryfikacje,
#   - zabezpieczenia zostaja te same: zamek, kontrola zer, przeszkody dostawcy
#     i $MaxNadrabiania porcji na jedno podejscie,
#   - NIE wlicza sie do $MaxProb i nie jest przez nie blokowane. $MaxProb pilnuje automatu,
#     ktory wraca przy kazdym otwarciu okna i bez sufitu krecilby sie w kolko na zepsutym
#     dostawcy. Reczny przebieg to jedno klikniecie po zobaczeniu kosztu - petli nie ma,
#     a wliczony zabieralby automatowi jego dzisiejsze ponowienia (klikniecie w chwili
#     zerwanej sieci = o jedna szanse mniej dla automatu), zablokowany zas odmawialby
#     wyraznej decyzji czlowieka z powodu, ktory jej nie dotyczy,
#   - dzien zamkniety przez automat zostaje zamkniety: odlozenie recznego przebiegu nie
#     wpisuje do .cykl-stan statusu "odlozony", bo ten kaze dozorowi i straznikowi ruszac
#     cykl jeszcze dzis - automat ma chodzic dokladnie tak jak dotad, raz na dzien,
#   - KAZDE zakonczenie (takze odmowa: nic nowego, zamek zajety, przeszkoda, zera, blad)
#     zostawia wynik w .cykl-reczny, a okno nadzorcy mowi go zwyklymi slowami
#     (zasobnik\nadzorca\stan-cykl.ps1, Stan-Recznego). Sam dziennik to byla cisza.

# Znacznik do zapisu: ta sama postac, co w opisie znacznika; pusto = jeszcze nigdy nie czytane.
function Znacznik-Tekst($data) {
  if ($null -eq $data) { return "" }
  return $data.ToString("yyyy-MM-dd HH:mm")
}

# stan: pracuje (z pid procesu - okno po nim poznaje przebieg, ktory zniknal bez wyniku)
# albo koniec z wynikiem. Zapis nieudany NIE jest cisza: idzie na ekran przebiegu, a okno
# i tak powie, ze przebieg skonczyl sie bez wyniku.
function Zapisz-Reczny($stanPracy, $wynik = "", $powod = "", $dodatki = $null) {
  if (-not $Recznie) { return }
  if ($Proba) { Plan "wynik czytania recznego do $($script:PlikRecznego): $stanPracy $wynik $powod"; return }
  $wpis = [ordered]@{
    start = $script:RecznyStart
    pid   = $PID
    stan  = $stanPracy
    czas  = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  }
  if ($wynik) { $wpis["wynik"] = $wynik }
  if ($powod) { $wpis["powod"] = ("$powod" -replace '[\r\n]+', ' ').Trim() }
  if ($dodatki) { foreach ($k in $dodatki.Keys) { $wpis[$k] = $dodatki[$k] } }
  try { Zapisz-Klucze $script:PlikRecznego $wpis }
  catch { Blad "nie udalo sie zapisac wyniku czytania recznego do $($script:PlikRecznego): $($_.Exception.Message)" }
}

# Liczby do wyniku recznego: od kiedy czytal, dokad siega teraz znacznik, ile porcji i tokenow
# (roznica wzgledem stanu sprzed pracy, jak w Zamelduj-Koszt) i ile kawalkow ubylo z kolejki.
function Liczby-Recznego($zostalo, $kawalkiPrzed, $kawalkiPo) {
  $teraz = Licznik-Kosztu
  $tokeny = [long]$teraz["tokeny"] - [long]$script:KosztStart["tokeny"]
  if ($tokeny -lt 0) { $tokeny = 0 }
  $d = [ordered]@{
    od       = (Znacznik-Tekst $script:ZnacznikPrzed)
    znacznik = (Znacznik-Tekst (Czytaj-Znacznik))
    porcje   = $script:Porcje
    tokeny   = $tokeny
  }
  if ($null -ne $zostalo) { $d["zostalo"] = $zostalo }
  if (($null -ne $kawalkiPrzed) -and ($null -ne $kawalkiPo)) {
    $ubylo = [int]$kawalkiPrzed - [int]$kawalkiPo
    if ($ubylo -lt 0) { $ubylo = 0 }
    $d["przeczytane"] = $ubylo
  }
  return $d
}

# ---------------------------------------------------------------- kroki cyklu

# Odlozenie, nie porazka: kod 0, znacznik nietkniety, material czeka na nastepna probe.
# $ponawiaj = $false dla powodow, ktore same z siebie nie przejda (brak narzedzia AI) -
# wtedy nie ma po co wracac nawet przy nastepnym oknie.
function Odloz($stan, $powod, $ponawiaj = $true) {
  if ($Recznie -and $script:StatusPrzed -and ($script:StatusPrzed -ne "odlozony")) {
    # dzien zamkniety przez automat zostaje zamkniety (patrz "czytanie reczne") - zapisujemy
    # tylko kolejke; "odlozony" kazalby dozorowi ruszac cykl jeszcze dzis
    $stan["status"] = $script:StatusPrzed
  } else {
    $stan["status"] = "odlozony"
    $stan["powod"]  = $powod
    $stan["czas"]   = (Get-Date -Format "yyyy-MM-dd HH:mm")
  }
  Zapisz-Stan $stan
  # Odlozenie po czesciowej pracy tez ma swoj koszt - i uzytkownik ma go zobaczyc.
  # Dopiero gdy nie poszla ani jedna porcja, nie ma o czym meldowac i plik znika.
  if ($script:Porcje -gt 0) { Zamelduj-Koszt (Ile-Czeka) $null $null }
  else                      { Skasuj-Postep }
  $proby = [int]$stan["proby"]
  if ($Recznie) {
    # reczny przebieg nie liczy sie do $MaxProb, wiec "odpuszczony po N probach" byloby nieprawda
    Zapisz-Podsumowanie "odlozony" $powod 0 (Ile-Czeka)
    Zapisz-Reczny "koniec" "odlozony" $powod (Liczby-Recznego (Ile-Czeka) $null $null)
    Ostrzezenie "czytanie reczne nie przeszlo: $powod - material czeka nietkniety"
    exit 0
  }
  if (-not $ponawiaj) {
    Zapisz-Podsumowanie "odlozony" $powod 0 (Ile-Czeka)
    Ostrzezenie "$powod - material czeka nietkniety, cykl wroci przy nastepnym otwarciu okna"
    exit 0
  }
  if ($proby -ge $MaxProb) {
    Zapisz-Podsumowanie "wyczerpane" $powod 0 (Ile-Czeka)
    Ostrzezenie "$powod - to byla $proby. proba z $MaxProb, na dzis koniec; material czeka nietkniety"
  } else {
    Zapisz-Podsumowanie "odlozony" $powod 0 (Ile-Czeka)
    Krok "odlozone: $powod (proba $proby z $MaxProb) - wroce przy nastepnym otwarciu okna"
  }
  exit 0
}

# Gotowa linia dla hooka przypomnienia: ile porcji za nami i ile to dotad kosztowalo.
# Tokeny to ROZNICA wzgledem stanu sprzed tego przebiegu - facts.py sumuje w pliku
# cala dobe, a tutaj chodzi o te jedna prace, ktora uzytkownik ma wlasnie przed oczami.
function Linia-Postepu($zrobione, $ile) {
  $teraz = Licznik-Kosztu
  $tokeny = [long]$teraz["tokeny"] - [long]$script:KosztStart["tokeny"]
  $ogon = ""
  if ($tokeny -gt 0) { $ogon = ", ~$(Liczba-Ludzka $tokeny) tokenow" }
  return "cykl wiedzy: $zrobione z $ile porcji$ogon"
}

function Wylow-Fakty($stan, $nadrabiaj, $przeszkoda) {
  Naglowek "1/2  Wylawianie faktow od znacznika ostatniego odczytu"
  if (($stan["wylowione"] -eq "ok") -and -not $Recznie) {
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
    Plan "wyciagnij-fakty.ps1 -Zrodlo $($script:Zrodlo) -Nadrabiaj 1, i tak $nadrabiaj razy pod rzad"
    Plan "po kazdej porcji linia postepu do $($script:Postep)"
    return
  }

  # Porcja po porcji, zamiast jednego wolania z -Nadrabiaj $nadrabiaj. Model jest wolany
  # tyle samo razy i kosztuje tyle samo, ale po KAZDEJ porcji da sie powiedziec, ile juz
  # zrobione - bez tego cykl jest kwadransem ciszy, w ktorym nie widac nawet, czy zyje.
  for ($i = 1; $i -le $nadrabiaj; $i++) {
    Zapisz-Postep "pracuje" (Linia-Postepu ($i - 1) $nadrabiaj)
    Krok "porcja $i z $nadrabiaj"
    $argumenty = @{ Zrodlo = $script:Zrodlo; Nadrabiaj = 1 }
    $global:LASTEXITCODE = 0
    $wyjscie = (& $script:Wyciagnij @argumenty *>&1 | Out-String)
    $kod = $LASTEXITCODE
    Write-Host $wyjscie
    if ($kod -ne 0) {
      # znacznik sie nie przesunal, wiec reszta materialu czeka - odlozenie ustawiamy
      # dopiero po weryfikacji, zeby jej nie zabrac przez potkniecie na samym modelu.
      # Porcje juz wylowione zostaja w poczekalni: tego zadna powtorka nie cofnie.
      $script:Pominiete = Rozpoznaj-Powod $wyjscie $kod
      Ostrzezenie "wylawianie stanelo na porcji $i z ${nadrabiaj}: $($script:Pominiete) - weryfikacja idzie dalej"
      break
    }
    $script:Porcje  = $i
    $script:Zostalo = Zostalo-Przebiegow $wyjscie
    Zapisz-Postep "pracuje" (Linia-Postepu $i $nadrabiaj)
    # Kolejka pusta - dalsze porcje wolalyby model po nic
    if ($null -ne $script:Zostalo -and $script:Zostalo -le 0) { break }
  }

  # "wylowione: ok" znaczy CALE wylawianie tego podejscia, a nie pierwsza udana
  # porcja - inaczej potkniecie na trzeciej porcji zamykaloby krok 1/2 na caly dzien
  # i nastepne podejscie tylko weryfikowaloby wiedze, zostawiajac material w kolejce.
  if (-not $script:Pominiete) {
    $stan["wylowione"] = "ok"
    Zapisz-Stan $stan
  }
}

# Meldunek koncowy: jedna linia, ktora hook przypomnienia pokaze RAZ przy najblizszej
# wiadomosci uzytkownika i skasuje plik. Bez tego caly koszt cyklu byl niewidoczny az
# do nastepnego dnia. Mowi to, o co uzytkownik pytal wprost: ile przeczytane, z jakiego
# zakresu, iloma wolaniami, ile to kosztowalo (i czy to pomiar, czy szacunek), ile faktow
# z tego jest i gdzie stoi teraz znacznik. Liczby to ROZNICA wzgledem stanu sprzed pracy.
function Zamelduj-Koszt($zostalo, $kawalkiPrzed, $kawalkiPo) {
  if ($script:Porcje -le 0) { Skasuj-Postep; return }
  $teraz = Licznik-Kosztu
  $tokeny = [long]$teraz["tokeny"] - [long]$script:KosztStart["tokeny"]
  $fakty  = [long]$teraz["fakty"]  - [long]$script:KosztStart["fakty"]
  $wolania = [long]$teraz["wywolania"] - [long]$script:KosztStart["wywolania"]
  if ($tokeny -lt 0)  { $tokeny = 0 }
  if ($fakty  -lt 0)  { $fakty = 0 }
  if ($wolania -le 0) { $wolania = $script:Porcje }

  $zrodlo = (Czytaj-Klucze $script:Koszt)["tokeny_zrodlo"]
  if (-not $zrodlo) { $zrodlo = "szacunek" }
  $opisTok = "kosztu nie policzono"
  if ($tokeny -gt 0) { $opisTok = "~$(Liczba-Ludzka $tokeny) tokenow ($zrodlo)" }

  # Ile materialu naprawde ubylo z kolejki. Dwie liczby z tego samego zrodla
  # (wyciagnij-fakty.ps1 -Kolejka), wiec da sie je odjac uczciwie.
  $przeczytane = $null
  if (($null -ne $kawalkiPrzed) -and ($null -ne $kawalkiPo)) {
    $przeczytane = [int]$kawalkiPrzed - [int]$kawalkiPo
    if ($przeczytane -lt 0) { $przeczytane = 0 }   # w trakcie pracy doszedl nowy material
  }
  $coPrzeczytane = "$($script:Porcje) porcji"
  if ($null -ne $przeczytane) { $coPrzeczytane = "$przeczytane kawalkow rozmow w $($script:Porcje) porcjach" }

  $ogon = ""
  if ($zostalo -gt 0) { $ogon = "; w kolejce zostalo $zostalo przebiegow" }
  Zapisz-Postep "koniec" ("cykl wiedzy skonczony: przeczytane $coPrzeczytane od $(Opis-Znacznika $script:ZnacznikPrzed), " +
    "$(Ile-Wolan $wolania), $opisTok, $fakty nowych faktow w poczekalni; " +
    "znacznik stoi teraz na $(Opis-Znacznika (Czytaj-Znacznik))$ogon")
}

function Ile-Wolan($n) {
  $reszta = $n % 10
  $setka  = $n % 100
  if ($n -eq 1) { return "1 wolanie modelu" }
  if (($reszta -ge 2) -and ($reszta -le 4) -and (($setka -lt 12) -or ($setka -gt 14))) { return "$n wolania modelu" }
  return "$n wolan modelu"
}

# Kontrola zakresu. Znacznik to JEDNA data, wiec kawalek rozmowy dopisany do indeksu
# ze starsza data niz znacznik wypada z zakresu na zawsze i nikt sie o tym nie dowie.
# Uczciwie umiemy tu sprawdzic tylko jedno: czy kolejka zmalala tyle, ile porcji poszlo.
# Kolejka, ktora po przesunieciu znacznika nie zmalala wcale, znaczy material przepadly
# albo material, ktory przybyl w trakcie - i o tym mowimy wprost, zamiast milczec.
function Sprawdz-Zakres($kawalkiPrzed, $kawalkiPo) {
  if ($script:Porcje -le 0) { return }
  if (($null -eq $kawalkiPrzed) -or ($null -eq $kawalkiPo)) { return }
  if ([int]$kawalkiPrzed -le 0) { return }
  $ubylo = [int]$kawalkiPrzed - [int]$kawalkiPo
  if ($ubylo -gt 0) { return }
  Ostrzezenie ("kolejka nie zmalala po $($script:Porcje) porcjach (przed: $kawalkiPrzed, po: $kawalkiPo kawalkow) - " +
               "albo material przybywa szybciej, niz jest czytany, albo czesc kawalkow ma znacznik czasu starszy " +
               "niz $(Opis-Znacznika $script:ZnacznikPrzed) i wypadla z zakresu na stale")
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

# Rotacja kopii "wczoraj"/"przedwczoraj" (narzedzia\kopie-dzienne.ps1) - raz na dobe, przed cyklem,
# bo to cykl zapisuje pliki pamieci. Kod 2 = ktorys plik pamieci ma bajty 0x00: wtedy dzien
# zamykamy stanem "wyzerowane" (to nie jest "odlozony" - powtorka niczego nie naprawi, a dozor
# i straznik nie maja go ruszac w kolko) i konczymy, zanim cokolwiek dotknie plikow.
# Rotacja, ktora sie wywrocila z innego powodu, cyklu nie zatrzymuje - mowi o tym i idzie dalej.
function Pilnuj-Kopii-Dziennych($stan) {
  $skrypt = Join-Path $PSScriptRoot "kopie-dzienne.ps1"
  if (-not (Test-Path $skrypt)) { Ostrzezenie "nie ma $skrypt - kopii dziennych nie robie"; return }
  $global:LASTEXITCODE = 0
  $wy = @()
  try {
    if ($Proba) { $wy = @(& $skrypt -Rotuj -Proba -KatalogDomowy $KatalogDomowy -Zrodlo $Zrodlo 2>&1) }
    else        { $wy = @(& $skrypt -Rotuj -KatalogDomowy $KatalogDomowy -Zrodlo $Zrodlo 2>&1) }
    $kod = $LASTEXITCODE
  } catch {
    $wy = @("$($_.Exception.Message)")
    $kod = 1
  }
  $tekst = ($wy | ForEach-Object { "$_" }) -join " "
  if ($kod -eq 2) {
    $alarm = [regex]::Match($tekst, 'ALARM: wyzerowane pliki pamieci.*?(?= kopie dzienne:|$)').Value
    if (-not $alarm) { $alarm = $tekst }
    Blad $alarm
    Blad "cykl NIE rusza - nic nie zostalo przeczytane ani zapisane"
    if (-not $Proba) {
      $stan["status"] = "wyzerowane"
      $stan["powod"]  = $alarm
      $stan["czas"]   = (Get-Date -Format "yyyy-MM-dd HH:mm")
      Zapisz-Stan $stan
    }
    Zapisz-Podsumowanie "wyzerowane" $alarm 0 0
    Zapisz-Reczny "koniec" "wyzerowane" $alarm
    exit 1
  }
  if ($kod -ne 0) { Ostrzezenie "kopie dzienne sie nie udaly (kod $kod): $tekst - cykl idzie dalej"; return }
  foreach ($l in $wy) { Krok "$l" }
}

function Uruchom-Cykl {
  $dzis = (Get-Date -Format "yyyy-MM-dd")
  $stan = Czytaj-Klucze $script:PlikStanu
  if ($stan["data"] -ne $dzis) {
    # nowy dzien - licznik prob startuje od zera, stary powod juz nieaktualny.
    # Zapamietana kolejka przechodzi przez granice doby: material nie znika o polnocy,
    # a bez niej cykl zaczynalby dzien od arytmetyki na kalendarzu, czyli od "1 dnia".
    $zapamietane = $stan["zostalo"]
    $stan = [ordered]@{ data = $dzis; proby = "0" }
    if ($zapamietane) { $stan["zostalo"] = $zapamietane }
  }

  # status dnia sprzed tej pracy - reczny przebieg nie otwiera dnia zamknietego przez automat
  $script:StatusPrzed = $stan["status"]

  # Czytanie reczne (-Recznie) omija oba wyjscia ponizej - patrz "czytanie reczne z okna".
  if (($stan["status"] -eq "ok") -and -not $Recznie) {
    Zdejmij-Stare-Zadanie
    Krok "dzisiejszy cykl juz przeszedl ($($stan['czas'])) - nie ma czego powtarzac"
    exit 0
  }

  $proby = 0
  if ($stan["proby"] -match '^\d+$') { $proby = [int]$stan["proby"] }
  if (($proby -ge $MaxProb) -and -not $Recznie) {
    Zdejmij-Stare-Zadanie
    Krok "na dzis koniec prob ($proby z $MaxProb) - cykl wroci jutro, material czeka nietkniety"
    exit 0
  }

  # Kopie dzienne i kontrola zer - PRZED jakakolwiek praca. Z wyzerowanych plikow cykl
  # nie czyta, nie pisze do nich i nie robi z nich kopii (awaria 2026-10-02).
  Pilnuj-Kopii-Dziennych $stan

  if ($Recznie) {
    # reczny przebieg nie liczy sie do $MaxProb (patrz "czytanie reczne z okna")
    Naglowek "Czytanie reczne z okna ($dzis) - poza dziennymi probami automatu, status dnia: $(if ($script:StatusPrzed) { $script:StatusPrzed } else { 'jeszcze bez przebiegu' })"
  } else {
    # licznik podnosimy PRZED praca: przebieg, ktory sie wywroci, ma sie policzyc
    $proby++
    $stan["proby"] = "$proby"
    Zapisz-Stan $stan

    Naglowek "Cykl dzienny pamieci ($dzis, proba $proby z $MaxProb)"
  }
  $narzedzia = Znajdz-Narzedzia
  if ($narzedzia.Count -gt 0) {
    Krok ("narzedzia AI na tej maszynie: " + (($narzedzia | ForEach-Object { $_.Nazwa }) -join ", "))
  } else {
    Krok "narzedzi AI nie widac - ida tylko kroki, ktore czytaja pliki"
  }
  # przeszkoda dotyczy WYLAWIANIA, nie calego przebiegu - dlatego nie ma tu Odloz
  $przeszkoda = Znajdz-Przeszkode $narzedzia

  # Ile wziac, decyduje stan kolejki, a nie kalendarz. Kolejnosc zrodel od najpewniejszego:
  # odpowiedz wylawiania teraz -> liczba zapamietana z poprzedniego przebiegu -> dni.
  $kolejka = Stan-Kolejki
  $zKolejki = ($null -ne $kolejka)   # czy liczba "przed" jest w tej samej jednostce, co "po"
  if ($null -ne $kolejka) {
    $script:Czeka   = $kolejka["przebiegi"]
    $script:Kawalki = $kolejka["kawalki"]
    $skad = "$($script:Kawalki) kawalkow materialu czeka"
  } elseif ($stan["zostalo"] -match '^\d+$') {
    $script:Czeka = [int]$stan["zostalo"]
    $skad = "wg poprzedniego przebiegu - kolejki nie udalo sie odczytac teraz"
  } else {
    $script:Czeka = 1
    $skad = "kolejki nie udalo sie odczytac i nie ma czego pamietac - biore jedna porcje"
  }
  # Reczne czytanie przy pustej kolejce: modelu nie wolamy, stanu dnia nie ruszamy -
  # ale uzytkownik kliknal i ma uslyszec, ze nie bylo czego czytac i od kiedy.
  if ($Recznie -and ($null -ne $kolejka) -and ($kolejka["przebiegi"] -le 0)) {
    $od = Czytaj-Znacznik
    Krok "nic nowego od $(Opis-Znacznika $od) - nie bylo czego czytac; model nie wolany, stan dnia nietkniety"
    Zapisz-Reczny "koniec" "nic" "" ([ordered]@{ od = (Znacznik-Tekst $od); znacznik = (Znacznik-Tekst $od) })
    exit 0
  }
  # Punkt odniesienia dla meldunku koncowego: znacznik i licznik kosztu SPRZED pracy.
  # Bez tego nie da sie powiedziec, ile kosztowal ten przebieg (facts.py sumuje dobe)
  # ani od kiedy czytal (znacznik po pracy stoi juz gdzie indziej).
  $script:KosztStart    = Licznik-Kosztu
  $script:ZnacznikPrzed = Czytaj-Znacznik
  $kawalkiPrzed = $script:Kawalki
  $czeka = $script:Czeka
  $nadrabiaj = [math]::Max(1, [math]::Min($czeka, $MaxNadrabiania))
  # ile cykl zdazy wziac PO tym podejsciu, zanim skoncza sie proby na te dobe - stad
  # wiadomo, czy jest w ogole szansa nadgonic dzis, czy trzeba to powiedziec wprost
  $script:Mozliwe = ($MaxProb - $proby) * $MaxNadrabiania
  if ($czeka -gt $MaxNadrabiania) {
    Krok "do nadrobienia: $czeka przebiegow ($skad) - biore $nadrabiaj (wiecej na raz przepalaloby limit), po reszte wracam przy nastepnym otwarciu okna"
  } else {
    Krok "do nadrobienia: $czeka przebiegow ($skad) - biore $nadrabiaj"
  }

  Wylow-Fakty $stan $nadrabiaj $przeszkoda
  $kodWeryfikacji = Sprawdz-Wiedze

  # Po pracy pytamy kolejke jeszcze raz - to jedyna pewna odpowiedz, ile naprawde zostalo.
  # Liczba wyczytana z tekstu przebiegu ($script:Zostalo) sluzy juz tylko za zapas.
  $po = Stan-Kolejki
  if ($null -ne $po) {
    $script:Zostalo = $po["przebiegi"]
    $script:Kawalki = $po["kawalki"]
  }
  $poZostalo = $czeka
  if ($null -ne $script:Zostalo) { $poZostalo = $script:Zostalo }
  $nadrobione = $czeka - $poZostalo
  if ($nadrobione -lt 0) { $nadrobione = 0 }
  # stan kolejki zapamietujemy zawsze - nastepny przebieg ma od czego zaczac
  $stan["zostalo"] = "$poZostalo"
  if ($null -ne $script:Kawalki) { $stan["kawalki"] = "$($script:Kawalki)" }

  if ($kodWeryfikacji -ne 0) {
    # fakty sa juz wylowione i leza w poczekalni - tego zadna powtorka nie cofnie
    Odloz $stan "weryfikacja nie powiodla sie (kod $kodWeryfikacji)"
  }

  # weryfikacja przeszla, ale wylawianie nie poszlo - dzien nie jest zamkniety.
  # Brak narzedzia AI sam sie nie naprawi, wiec wtedy nie ma po co wracac nawet przy nastepnym oknie.
  if ($script:Pominiete) {
    Odloz $stan $script:Pominiete ($narzedzia.Count -gt 0)
  }

  # Dzien zamykamy dopiero z pusta kolejka. Zostalo cos - to NIE jest "ok": cykl wroci
  # po reszte w nastepnym dniu pracy, a gdy kolejka rosnie albo przerasta to, co zdazy
  # nadrobic, mowi o tym wprost zamiast meldowac sukces.
  if ($poZostalo -gt 0) {
    $status = "dogania"
    # "urosla" porownujemy tylko wtedy, gdy obie liczby pochodza z tego samego zrodla -
    # przebiegi kontra dni z kalendarza to znowu byloby porownanie jablek z gruszkami
    $urosla = ($zKolejki -and $null -ne $script:Zostalo -and $poZostalo -gt $czeka)
    if ($urosla -or $poZostalo -gt $script:Mozliwe) { $status = "nie nadaza" }
    $stan["status"] = $status
    $stan["czas"]   = (Get-Date -Format "yyyy-MM-dd HH:mm")
    $stan.Remove("powod")
    $stan.Remove("wylowione")    # nastepne podejscie ma znowu wylawiac, nie samo weryfikowac
    Zapisz-Stan $stan
    Zapisz-Podsumowanie $status "" $nadrobione $poZostalo
    Sprawdz-Zakres $kawalkiPrzed $script:Kawalki
    Zamelduj-Koszt $poZostalo $kawalkiPrzed $script:Kawalki
    Zapisz-Reczny "koniec" $status "" (Liczby-Recznego $poZostalo $kawalkiPrzed $script:Kawalki)

    Naglowek "Podsumowanie"
    Krok "nadrobione przebiegi: $nadrobione"
    Krok (Opis-Kolejki $poZostalo)
    Krok "reszta kolejki czeka na nastepny dzien pracy - cykl rusza przy pierwszej sesji nowego dnia"
    if ($status -eq "nie nadaza") {
      Ostrzezenie "material przybywa szybciej, niz cykl go bierze - zwieksz MAX_INPUT_CHARS w lore\lore\facts.py albo nadrob recznie: narzedzia\wyciagnij-fakty.ps1 -Nadrabiaj $poZostalo"
    }
    Krok "podsumowanie: $($script:Ostatni)"
    exit 0
  }

  $stan["status"] = "ok"
  $stan["proby"]  = "0"          # dzien zamkniety - licznik czysty
  $stan["czas"]   = (Get-Date -Format "yyyy-MM-dd HH:mm")
  $stan.Remove("powod")
  Zapisz-Stan $stan
  Zapisz-Podsumowanie "ok" "" $nadrobione $poZostalo
  Sprawdz-Zakres $kawalkiPrzed $script:Kawalki
  Zamelduj-Koszt 0 $kawalkiPrzed $script:Kawalki
  Zapisz-Reczny "koniec" "ok" "" (Liczby-Recznego $poZostalo $kawalkiPrzed $script:Kawalki)

  Naglowek "Podsumowanie"
  Krok "nadrobione przebiegi: $nadrobione"
  Krok (Opis-Kolejki $poZostalo)
  Krok "podsumowanie: $($script:Ostatni)"
  exit 0
}

# ---------------------------------------------------------------- przebieg

# Pierwsza rzecz: chwila startu recznego przebiegu - okno nadzorcy po niej poznaje, ze wynik
# w .cykl-reczny jest odpowiedzia na JEGO klikniecie, a nie zostalosc po poprzednim.
$script:RecznyStart = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")

Ustaw-Sciezki

if ($UsunZadanie)  { Usun-Zadanie }

# Cykl startuje z hooka sesji, a okien potrafi byc kilka naraz (Claude Code i Codex
# obok siebie) - bez zamka dwa przebiegi weszlyby sobie w droge i policzyly podwojna probe.
$zamek = New-Object System.Threading.Mutex($false, "Local\MegaRuchacz-LoreCykl")
$mojZamek = $false
# porzucony zamek (poprzedni przebieg padl w polowie) liczy sie jako wolny - inaczej
# jedna wywrotka blokowalaby cykl az do restartu maszyny
try { $mojZamek = $zamek.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $mojZamek = $true }
if (-not $mojZamek) {
  # Automat po cichu (inny przebieg i tak pracuje), klikniecie czlowieka - nigdy po cichu.
  if ($Recznie) {
    Ostrzezenie "czytanie rozmow juz trwa w innym procesie - drugi raz nie ruszam"
    Zapisz-Reczny "koniec" "zajete" "czytanie rozmow juz trwa (automat albo wczesniejsze klikniecie)"
  }
  exit 0
}

# "Pracuje" z pid procesu - od tej chwili okno wie, ze klikniecie ruszylo.
Zapisz-Reczny "pracuje"

try { Uruchom-Cykl }
catch {
  # Wywrotka w srodku: automat konczy sie jak dotad (blad idzie dalej), reczny zostawia slad.
  Zapisz-Reczny "koniec" "blad" "$($_.Exception.Message)"
  throw
}
