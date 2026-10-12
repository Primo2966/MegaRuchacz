# zasobnik\terminy.ps1 - przypomnienia z terminem na pulpicie (decyzja uzytkownika 2026-10-05).
# Wola go nadzorca (zasobnik\nadzorca\stan-terminy.ps1) przy starcie i co godzine 8-20; mozna
# tez recznie. Plik przypomnien i cala jego logike ma narzedzia\terminy.js - tutaj tylko:
#
#   1. tryb "sam", termin dzis albo wczesniej, jeszcze nieuruchomione -> NAJPIERW status "w toku"
#      (terminy.js w-toku), POTEM osobny proces bez okna (ten skrypt z -Wykonaj <id>), ktory
#      puszcza "claude -p" w katalogu projektu (2026-10-08: okno z dlugim raportem przy kazdym
#      zadaniu bylo zbedne, a wynik ginal przy jego zamknieciu). W tej kolejnosci, bo wywrotka
#      po starcie nie moze skonczyc sie drugim uruchomieniem - najwyzej jedno samoczynne na
#      przypomnienie. Kilka naraz: kazde w osobnym procesie, ale Claude PO KOLEI - proces czeka
#      w kolejce (zamek $NAZWA_KOLEJKI_CLAUDE), az poprzedni skonczy razem z ponowieniami
#      (2026-10-12: trzy rownolegle starty zderzyly sie przy odswiezaniu logowania i padly).
#      Proces w tle: odpowiedz Claude zaczyna sie znacznikiem "WYNIK: NIC_NIE_MUSISZ" albo
#      "WYNIK: POTRZEBUJE_CIEBIE: <co>"; wynik ZAWSZE na trwale w ~\.claude\mr\przypomnienia-wyniki\
#      <id>.json (umowa z karta Przeglad nadzorcy) i <id>.md (raport do Notatnika).
#        "nic"      -> odhaczone, zadnego okna,
#        "czlowiek" -> okno terminala z "claude --resume <sesja>" i naglowkiem "MUSISZ: ...",
#                      zostaje "w toku",
#        "blad"     -> brak znacznika, kod wyjscia, limit czasu, nieczytelny JSON, odmowa uprawnien
#                      (permission_denials - blad naszych ustawien, nie sprawa dla czlowieka) - nigdy nie
#                      uchodza za "nic". Blad przejsciowy (logowanie, limit zapytan, przeciazenie,
#                      siec) ponawiany do $PROB_W_TLE razy co $SEKUND_MIEDZY_PROBAMI. Potem zadanie
#                      SAMO przechodzi na jutro (terminy.js przesun <id> jutro) i jutro rusza znowu,
#                      bez limitu dni, a czlowiek dostaje male okno "Nie udalo sie ... Przeniesione
#                      na jutro" z przyciskami "Sprobuj teraz" / "Odloz na jutro" - nigdy terminal
#                      z surowa rozmowa Claude (decyzja uzytkownika 2026-10-12).
#   2. okno z przyciskami "Zrob teraz / Jutro / Zrobione" dla: trybu "przypomnij", spraw "w toku"
#      od wczoraj albo dawniej (automat nie dokonczyl) i uruchomien, ktore sie nie udaly. Okno
#      stoi na wierzchu i na pasku zadan, dopoki ktos nie kliknie. Krzyzyk przy nieobsluzonych
#      = wroci za 2 godziny (odlozone_do w przypomnienia-okno.txt). Tekst w oknie da sie
#      zaznaczyc mysza, a przycisk "Kopiuj" daje do schowka naglowek i tresc przypomnienia.
#      "Zrob teraz" startuje Claude dopiero, gdy kolejka jest wolna (okno pisze, ze czeka).
#
# Slad "bylem tu", kazde uruchomienie i kazda wywrotka: ~\.claude\mr\przypomnienia.log.
#
# Uzycie:
#   powershell -NoProfile -ExecutionPolicy Bypass -File zasobnik\terminy.ps1 [-Zrodlo <repo>]
#     [-KatalogDomowy <kat>] [-Plik <plik przypomnien>] [-Dzis RRRR-MM-DD] [-Proba] [-BezOkna]
#     [-Wykonaj <id>] [-LimitSekund <s>] [-PauzaSekund <s>]
#   -Proba    nic nie uruchamia, nie zmienia i nie pokazuje - wypisuje, co by zrobil
#   -BezOkna  tylko samoczynne uruchomienia (punkt 1)
#   -Wykonaj  proces w tle dla jednego przypomnienia "w toku" (startuje go punkt 1, nie czlowiek)
#   -LimitSekund  limit claude -p zamiast $SEKUND_LIMITU_W_TLE (testy)
#   -PauzaSekund  przerwa miedzy probami zamiast $SEKUND_MIEDZY_PROBAMI (testy)
# Kod wyjscia: 0 ok (takze "nic do zrobienia"), 1 blad (opis w dzienniku i na stderr).
#
# Kod i komentarze bez polskich znakow; teksty w oknie i polecenie dla Claude z polskimi -
# dlatego plik MUSI miec BOM (PowerShell 5.1 czyta plik bez BOM jako ANSI).

param(
  [string]$Zrodlo = "",
  [string]$KatalogDomowy = "",
  [string]$Plik = "",
  [string]$Dzis = "",
  [switch]$Proba,
  [switch]$BezOkna,
  [int]$Wykonaj = 0,
  [int]$LimitSekund = 0,
  [int]$PauzaSekund = 0
)

$ErrorActionPreference = "Stop"
# Domyslne sciezki pod param(), nie w nim - patrz pulapka PS 5.1 w mapie (instaluj-globalnie).
if (-not $Zrodlo) { $Zrodlo = Split-Path -Parent $PSScriptRoot }
if (-not $KatalogDomowy) { $KatalogDomowy = $HOME }
$Zrodlo = $Zrodlo.TrimEnd('\', '/')
$SkryptTerminow = Join-Path $Zrodlo "narzedzia\terminy.js"
if ($Plik) { $env:MR_PRZYPOMNIENIA = $Plik } else { $Plik = Join-Path $KatalogDomowy ".claude\mr\przypomnienia.md" }
if ($Dzis) { $env:MR_DZIS = $Dzis }
$KatStanu = Split-Path -Parent $Plik
$PlikOkna = Join-Path $KatStanu "przypomnienia-okno.txt"
$Dziennik = Join-Path $KatStanu "przypomnienia.log"
$KatUruchomien = Join-Path $KatStanu "terminy"

# Krzyzyk = wroc za tyle minut (decyzja uzytkownika: 2 godziny, "nie gubimy sprawy").
$MINUT_ODLOZENIA = 120
# Kolejka Claude (decyzja uzytkownika 2026-10-12, po awarii z 08:03): w danej chwili najwyzej
# jeden Claude uruchomiony przez przypomnienia. Starty co 3 s nie wystarczyly - trzy procesy
# zderzyly sie przy odswiezaniu logowania ("another Claude Code process is refreshing it")
# i padly wszystkie. Zamek trzyma proces w tle przez wszystkie proby; "Zrob teraz" na niego czeka.
$NAZWA_KOLEJKI_CLAUDE = "Local\MegaRuchacz-Terminy-Claude"
# Limit jednego przebiegu w tle (claude -p). Zadania z przypomnien to "sprawdz, porownaj,
# przygotuj propozycje" - kilka do kilkunastu minut. 30 min to zapas na wolne API i kilka
# narzedzi; proces, ktory chodzi dluzej, prawie na pewno utknal (np. na zerwanym MCP). Po
# limicie proces jest ubijany razem z dziecmi, a wynik to "blad" (na jutro, okno dla czlowieka).
$SEKUND_LIMITU_W_TLE = 1800
if ($LimitSekund -gt 0) { $SEKUND_LIMITU_W_TLE = $LimitSekund }
# Ponowienie bledu przejsciowego (decyzja uzytkownika 2026-10-12): 3 proby co 60 s. Claude Code
# przy bledzie logowania sam pisze "retry in a minute"; limit zapytan i przeciazenie API tez
# mijaja zwykle w ciagu minut. Wiecej prob tylko dluzej trzyma kolejke - nastepna szansa jutro.
$PROB_W_TLE = 3
$SEKUND_MIEDZY_PROBAMI = 60
if ($PauzaSekund -gt 0) { $SEKUND_MIEDZY_PROBAMI = $PauzaSekund }
# Najdluzsze czekanie w kolejce. Jedno zadanie trzyma ja najwyzej $PROB_W_TLE x $SEKUND_LIMITU_W_TLE
# + pauzy = ok. 92 min; 12 h to zapas na ok. 8 takich zadan przed nami. Dluzej = cos utknelo -
# zadanie konczy sie bledem (na jutro, z oknem), a nie czeka w ciszy.
$MINUT_CZEKANIA_W_KOLEJCE = 720
# Bledy, ktore mijaja same - wzor szukany w stderr i odpowiedzi Claude (pole result) przebiegu,
# ktory sie nie udal (kod != 0, is_error, nie JSON; zwykly raport moze cytowac te slowa i nie
# jest bledem). Opis to powod dla czlowieka; surowa tresc bledu idzie za nim w nawiasie.
$BLEDY_PRZEJSCIOWE = @(
  @{ Wzor = 'OAuth|refresh(ing)? (the )?(access )?token|another Claude Code process'
     Opis = "Claude nie mógł się zalogować, bo kilka okien naraz odnawiało logowanie" },
  @{ Wzor = 'usage limit'; Opis = "wyczerpał się limit użycia konta Claude" },
  @{ Wzor = 'rate.?limit|too many requests|\b429\b'; Opis = "Claude chwilowo odmówił, bo przekroczono limit zapytań" },
  @{ Wzor = 'overloaded|(API Error|status|HTTP)\W{0,3}5\d\d\b|internal server error|bad gateway|service unavailable|gateway time-?out'
     Opis = "serwery Claude były przeciążone albo miały awarię" },
  @{ Wzor = 'ECONNRESET|ETIMEDOUT|ECONNREFUSED|ENOTFOUND|EAI_AGAIN|socket hang up|fetch failed|network|connection (error|refused|reset)'
     Opis = "nie było połączenia z serwerami Claude (sieć)" })
# Okno niepowodzenia: tyle znakow tresci przypomnienia w zdaniu "Nie udalo sie wykonac #N (...)".
$ZNAKOW_SKROTU_TRESCI = 80
# Tryb uprawnien claude -p: "auto", jak u uzytkownika na co dzien (pasek "auto mode on").
# Do 2026-10-12 byl "dontAsk" = odmowa wszystkiego spoza listy dozwolonych, a uzytkownik
# listy nie ma - tego dnia wszystkie trzy przypomnienia skonczyly sie POTRZEBUJE_CIEBIE, bo
# Read poza katalogiem, Bash i MCP (lore, ecommerce-helper) byly odrzucane. Sprawdzone na
# zywo 2026-10-12 (claude 2.1.296, -p, polecenie na stdin, Claude-W-Tle): w "auto" przeszly
# Bash, PowerShell, Read poza katalogiem, mcp__lore__lore_stats i mcp__ecommerce-helper__
# credentials_status (serwery MCP z ~\.claude.json wstaja w -p same, bez --mcp-config); w
# "dontAsk" te same Read i oba MCP poszly do permission_denials. (Bash jest tylko, gdy Git
# jest w PATH procesu - nadzorca go ma, z PATH uzytkownika.) "auto" przepuszcza
# odczyt, a ryzykowne kroki ocenia klasyfikator; zakaz zmian na produkcji stoi w poleceniu.
# Nigdy bypassPermissions (test-terminy-tlo.ps1 tego pilnuje).
$TRYB_UPRAWNIEN_W_TLE = "auto"
# Znaczniki sesji nadrzednej, ktore Claude Code ustawia swoim dzieciom (lista z claude.exe
# 2.1.296 + zmienne widziane 2026-10-12 w srodowisku sesji). Odziedziczone przez Claude
# uruchomionego przez ten skrypt robia z niego "dziecko" cudzej sesji: okno interaktywne
# wylacza zapis rozmowy ("Transcript saving is off - inherited CLAUDE_CODE_CHILD_SESSION
# marker", 2026-10-12, gdy terminy.ps1 odpalil kierownik z wnetrza Claude Code), a z niego
# korzysta Lore i --resume. Usuwane przy kazdym starcie claude: w tle (Claude-W-Tle) i w oknie
# (skrypt startowy, Linie-Bez-Znacznikow-Sesji). Tylko te nazwy - reszta srodowiska zostaje.
$ZNACZNIKI_SESJI_NADRZEDNEJ = @("CLAUDECODE", "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_SESSION_ID",
  "CLAUDE_CODE_SESSION_ATTENDED", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_EXECPATH", "CLAUDE_PID",
  "CLAUDE_CODE_MESSAGING_SOCKET", "CLAUDE_CODE_MESSAGING_TOKEN", "CLAUDE_CODE_INVOKED_SKILLS",
  "CLAUDE_EFFORT", "AI_AGENT")
# Ile znakow wyjscia procesu (stdout/stderr) trafia do raportu, gdy Claude nie dal odpowiedzi.
$MAX_WYJSCIA_W_RAPORCIE = 4000
$KatWynikow = Join-Path $KatalogDomowy ".claude\mr\przypomnienia-wyniki"
# Dziennik rosnie o kilka linii na godzine; powyzej tego rozmiaru zostaje jego koncowka.
$MAX_DZIENNIKA = 512KB
# Jak dlugo przycisk mowi "Skopiowano", zanim wroci do "Kopiuj".
$MS_NAPISU_SKOPIOWANO = 2000
# Przycisk Kopiuj przy zajetym schowku: ile prob i co ile (lacznie ok. 2,5 s). Inne programy
# trzymaja schowek po kazdej zmianie najwyzej 70 ms (zmierzone 2026-10-08), wiec 2,5 s to duzy zapas.
$PROB_SCHOWKA = 25
$MS_MIEDZY_PROBAMI_SCHOWKA = 100
# Pole tekstowe ma wewnetrzne marginesy (zmierzone 3+3 px zwykla, 4+4 pogrubiona Segoe UI 10);
# wysokosc mierzymy przy szerokosci mniejszej o ten zapas - wezsze zawijanie daje najwyzej
# o linie za duzo, nigdy za malo (za malo = tekst uciety).
$ZAPAS_SZEROKOSCI_POLA = 10

function Bez-Bom { return (New-Object System.Text.UTF8Encoding($false)) }

function Dopisz-Dziennik([string]$tekst) {
  $linia = (Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "  " + $tekst
  if ($Proba) { Write-Host "[proba] $linia"; return }
  try {
    if (-not (Test-Path -LiteralPath $KatStanu)) { New-Item -ItemType Directory -Force -Path $KatStanu | Out-Null }
    if ((Test-Path -LiteralPath $Dziennik) -and ((Get-Item -LiteralPath $Dziennik).Length -gt $MAX_DZIENNIKA)) {
      $ogon = @([System.IO.File]::ReadAllLines($Dziennik, [System.Text.Encoding]::UTF8) | Select-Object -Last 400)
      [System.IO.File]::WriteAllLines($Dziennik, [string[]]$ogon, (Bez-Bom))
    }
    # Proces w tle (-Wykonaj) i glowny przebieg moga dopisywac w tej samej chwili - kilka
    # krotkich prob, zanim to bedzie blad.
    for ($i = 1; ; $i++) {
      try { [System.IO.File]::AppendAllText($Dziennik, $linia + "`r`n", (Bez-Bom)); break }
      catch [System.IO.IOException] { if ($i -ge 10) { throw }; Start-Sleep -Milliseconds 50 }
    }
  } catch {
    # Dziennik jest jedynym sladem - gdy i on padl, zostaje stderr (nadzorca go nie czyta, ale
    # reczne uruchomienie zobaczy) i kod wyjscia.
    [Console]::Error.WriteLine("terminy.ps1: nie zapisalem dziennika ${Dziennik}: $($_.Exception.Message) | $tekst")
    $script:BladDziennika = $true
  }
}

function Czytaj-Klucze-Okna {
  $k = @{}
  if (-not (Test-Path -LiteralPath $PlikOkna)) { return $k }
  foreach ($l in [System.IO.File]::ReadAllLines($PlikOkna, [System.Text.Encoding]::UTF8)) {
    if ($l -match '^\s*([A-Za-z_.]+)\s*:\s*(.*?)\s*$') { $k[$matches[1]] = $matches[2] }
  }
  return $k
}

function Zapisz-Klucz-Okna([string]$klucz, [string]$wartosc) {
  if ($Proba) { Write-Host "[proba] przypomnienia-okno.txt: $klucz = $wartosc"; return }
  $k = Czytaj-Klucze-Okna
  $k[$klucz] = $wartosc
  $tekst = (@($k.Keys | Sort-Object | ForEach-Object { "${_}: $($k[$_])" }) -join "`r`n") + "`r`n"
  [System.IO.File]::WriteAllText($PlikOkna, $tekst, (Bez-Bom))
}

# terminy.js osobnym procesem, bez okna konsoli, z wyjsciem odczytanym jako UTF-8 (strona
# kodowa konsoli psulaby polskie litery w komunikatach bledow).
function Wolaj-Terminy([string[]]$argumenty) {
  $w = [pscustomobject]@{ Kod = -1; Tekst = ""; Blad = "" }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $script:Node
  $psi.Arguments = (@($SkryptTerminow) + $argumenty | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join " "
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  $p = [System.Diagnostics.Process]::Start($psi)
  $bl = $p.StandardError.ReadToEndAsync()
  $w.Tekst = $p.StandardOutput.ReadToEnd()
  $p.WaitForExit()
  $w.Blad = $bl.Result.Trim()
  $w.Kod = $p.ExitCode
  return $w
}

function Zmien-Status([string]$polecenie, [string[]]$reszta, [string]$opis) {
  if ($Proba) { Write-Host "[proba] node terminy.js $polecenie $($reszta -join ' ')"; return $true }
  $r = Wolaj-Terminy (@($polecenie) + $reszta)
  if ($r.Kod -eq 0) { Dopisz-Dziennik "$opis - ok"; return $true }
  Dopisz-Dziennik "$opis - NIE WYSZLO (kod $($r.Kod)): $($r.Blad) $($r.Tekst.Trim())"
  $script:OstatniBladStatusu = "$($r.Blad) $($r.Tekst.Trim())".Trim()
  return $false
}

# --------------------------------------------------------------- Claude Code w terminalu

# Wprost claude.exe, gdy da sie go znalezc: shim npm "claude.cmd" przepuszcza argument przez
# cmd.exe, ktory rozwija %ZMIENNE% i potyka sie na znakach specjalnych w tresci zadania.
function Sciezka-Claude {
  $c = Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $c) { return $null }
  $s = $c.Source
  if ($s -match '\.(cmd|bat|ps1)$' -or -not [System.IO.Path]::GetExtension($s)) {
    $exe = Join-Path (Split-Path -Parent $s) "node_modules\@anthropic-ai\claude-code\bin\claude.exe"
    if (Test-Path -LiteralPath $exe) { return $exe }
  }
  return $s
}

# Napis w pojedynczych cudzyslowach PowerShella. Za cudzyslow pojedynczy PS bierze tez
# ‘ ’ ‚ ‛ - zamieniamy je na zwykly apostrof i dopiero wtedy podwajamy.
function Napis-PS([string]$t) {
  $t = $t -replace "[‘’‚‛]", "'"
  return "'" + ($t -replace "'", "''") + "'"
}

# Sciezka do porownania: "/" -> "\", bez koncowego ukosnika i "\." po literze dysku, bez wielkosci
# liter. 2026-10-12 "C:/dev/ecommerce-helper" z przypomnienia nie zgadzalo sie z "C:\dev\ecommerce-
# helper" po GetFullPath i Claude dostal falszywa uwage, ze katalogu nie ma na tym komputerze.
function Sciezka-Do-Porownania([string]$s) {
  $s = "$s".Trim() -replace '/', '\'
  if ($s -match '^[A-Za-z]:\\\.$') { $s = $s.Substring(0, 2) }
  return $s.TrimEnd('\').ToLowerInvariant()
}

# $wTle: przebieg "claude -p" bez czlowieka - polecenie dostaje umowe o znaczniku WYNIK
# (czyta go Ocen-Przebieg) i zakaz odhaczania (odhacza ten skrypt, tylko przy "nic").
function Polecenie-Dla-Claude($p, [string]$katalog, [bool]$wTle = $false) {
  $skrypt = $SkryptTerminow.Replace('\', '/')
  $tresc = ($p.tresc -replace '"', "'").TrimEnd('.', ' ')   # kropke dostawia zdanie nizej
  if ($p.sprawdz) { $tresc += " (jak sprawdzić: " + ($p.sprawdz -replace '"', "'") + ")" }
  $gdzie = ""
  if ((Sciezka-Do-Porownania $katalog) -ne (Sciezka-Do-Porownania $p.projekt)) { $gdzie = " Uwaga: katalogu projektu '" + $p.projekt + "' nie ma na tym komputerze - okno otwarte w katalogu domowym; ustal najpierw, gdzie leży projekt." }
  $wstep = ("Zadanie z przypomnienia $($p.id) zaplanowane na $($p.termin): $tresc. Wykonaj je.$gdzie " +
            "Niczego nie zmieniaj na produkcji ani w sklepach bez wyraźnego polecenia użytkownika — przygotuj propozycję. ")
  if (-not $wTle) { return ($wstep + "Na koniec krótki raport po polsku i odhacz przypomnienie: node '$skrypt' zrobione $($p.id)") }
  return ($wstep +
          "Robisz to w tle, bez użytkownika przy komputerze: wykonaj zadanie sam, w tej jednej odpowiedzi — nie rozdawaj go workerom w tle, nie zadawaj pytań i nie kończ przed wynikiem. " +
          "Nie odhaczaj teraz przypomnienia — przy wyniku NIC_NIE_MUSISZ MegaRuchacz zrobi to sam. " +
          "Twoja ostatnia odpowiedź MUSI zaczynać się dokładnie jedną z dwóch linii, bez niczego przed nią (także gdy inne komunikaty każą zacząć od czegoś innego): " +
          "'WYNIK: NIC_NIE_MUSISZ' — zadanie załatwione, użytkownik nie musi nic robić; " +
          "'WYNIK: POTRZEBUJE_CIEBIE: <jednym zdaniem, co użytkownik ma zrobić>' — potrzebna jego decyzja, zgoda na zmianę albo kliknięcie, albo czegoś nie dało się zrobić. " +
          "Gdy Claude Code odmówi ci narzędzia z braku uprawnień, nie każ użytkownikowi uruchamiać zadania gdzie indziej — to błąd ustawień MegaRuchacza, który sam go zgłosi; napisz w raporcie wprost 'ODMOWA UPRAWNIEŃ: <narzędzie> — <po co było potrzebne>'. " +
          "Pod tą linią krótki raport po polsku: co sprawdziłeś, co wyszło, czego nie sprawdzono. " +
          "Gdy później dokończycie sprawę z użytkownikiem w tej rozmowie, odhacz: node '$skrypt' zrobione $($p.id)")
}

# Katalog projektu z przypomnienia; gdy go nie ma na tym komputerze - katalog domowy
# (polecenie dla Claude mowi wtedy, ze projektu trzeba poszukac).
function Katalog-Projektu($p) {
  $kat = "$($p.projekt)"
  if (-not $kat -or -not (Test-Path -LiteralPath $kat -PathType Container)) { $kat = $KatalogDomowy }
  $kat = [System.IO.Path]::GetFullPath($kat).TrimEnd('\')
  if ($kat -match '^[A-Za-z]:$') { $kat += '\.' }
  return $kat
}

# Otwiera WIDOCZNE okno: Windows Terminal (karta w nowym oknie), a gdy go nie ma - zwykla
# konsola PowerShella, z gotowym skryptem startowym. Zwraca opis albo rzuca wyjatek.
function Otworz-Terminal([string]$kat, [string]$id, [string]$start) {
  $ps = @("-NoExit", "-ExecutionPolicy", "Bypass", "-File", ('"' + $start + '"'))
  $wt = Get-Command wt.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($wt) {
    $arg = @("-w", "new", "new-tab", "-d", ('"' + $kat + '"'), "--title", ('"MegaRuchacz #' + $id + '"'), "powershell.exe") + $ps
    Start-Process -FilePath $wt.Source -ArgumentList $arg | Out-Null
    return "Windows Terminal, katalog $kat, skrypt startowy $start"
  }
  Start-Process -FilePath "powershell.exe" -WorkingDirectory $kat -ArgumentList $ps | Out-Null
  return "konsola PowerShell (brak Windows Terminal), katalog $kat, skrypt startowy $start"
}

# Skrypt startowy w ~\.claude\mr\terminy\ (zostaje jako slad, co dokladnie uruchomiono),
# bo wiersz polecen wt.exe rozcina tekst na ";". Z BOM - ma polskie litery.
function Zapisz-Skrypt-Startowy([string]$start, [string[]]$linie) {
  if (-not (Test-Path -LiteralPath $KatUruchomien)) { New-Item -ItemType Directory -Force -Path $KatUruchomien | Out-Null }
  [System.IO.File]::WriteAllText($start, ($linie -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding($true)))
}

# Linie skryptu startowego okna: zanim ruszy Claude, poczekaj, az zadanie z przypomnienia
# w tle zwolni kolejke (decyzja uzytkownika 2026-10-12: zaden drugi Claude rownolegle).
# Zamek tylko na chwile - rozmowa z czlowiekiem trwa godzinami i nie moze wstrzymac automatu.
# Zamek po procesie, ktory padl (AbandonedMutexException), jest juz nasz - zwalniamy go tak samo.
function Linie-Czekania-Na-Kolejke {
  return @(
    ('$kolejka = New-Object System.Threading.Mutex($false, ' + (Napis-PS $NAZWA_KOLEJKI_CLAUDE) + ')'),
    ('try { if (-not $kolejka.WaitOne(0)) { Write-Host ' + (Napis-PS "Czekam, aż skończy się zadanie z przypomnienia, które Claude robi w tle (dwa naraz psują logowanie)...") +
     ' -ForegroundColor Yellow; [void]$kolejka.WaitOne() } } catch [System.Threading.AbandonedMutexException] { }'),
    '$kolejka.ReleaseMutex(); $kolejka.Dispose()')
}

# Linie skryptu startowego okna: bez znacznikow sesji nadrzednej ($ZNACZNIKI_SESJI_NADRZEDNEJ).
# W skrypcie, nie w tym procesie - okno moze otworzyc juz dzialajacy Windows Terminal ze swoim
# srodowiskiem, a skrypt startowy zawsze biegnie tuz przed claude.
function Linie-Bez-Znacznikow-Sesji {
  $nazwy = ($ZNACZNIKI_SESJI_NADRZEDNEJ | ForEach-Object { Napis-PS $_ }) -join ", "
  return @(
    '# Bez znacznikow sesji nadrzednej Claude Code - inaczej okno wylacza zapis rozmowy (Lore, --resume)',
    ('foreach ($n in @(' + $nazwy + ')) { if (Test-Path -LiteralPath "Env:\$n") { Remove-Item -LiteralPath "Env:\$n" } }'))
}

# Interaktywny Claude Code w widocznym oknie (przycisk "Zrob teraz"). Zwraca opis albo
# rzuca wyjatek z powodem.
function Uruchom-Claude($p, [string]$jak) {
  $kat = Katalog-Projektu $p
  $claude = Sciezka-Claude
  if (-not $claude) { throw "nie ma polecenia claude w PATH - Claude Code nie jest zainstalowany albo PATH tego procesu go nie widzi" }
  $polecenie = Polecenie-Dla-Claude $p $kat
  $start = Join-Path $KatUruchomien "zrob-$($p.id).ps1"
  $tresc = @(
    "# MegaRuchacz: przypomnienie #$($p.id) - $jak $(Get-Date -Format 'yyyy-MM-dd HH:mm') (zasobnik\terminy.ps1)",
    ('$Host.UI.RawUI.WindowTitle = ' + (Napis-PS "MegaRuchacz - przypomnienie #$($p.id)")),
    ('Set-Location -LiteralPath ' + (Napis-PS $kat)),
    ('$polecenie = ' + (Napis-PS $polecenie))
  ) + (Linie-Bez-Znacznikow-Sesji) + (Linie-Czekania-Na-Kolejke) + @(
    ('& ' + (Napis-PS $claude) + ' $polecenie')
  )
  if ($Proba) {
    Write-Host "[proba] otworzylbym Claude Code w $kat ($jak):"
    Write-Host "        $polecenie"
    return "proba"
  }
  Zapisz-Skrypt-Startowy $start $tresc
  return (Otworz-Terminal $kat "$($p.id)" $start)
}

# ------------------------------------------------------ tryb "sam": Claude Code w tle

# Osobny proces bez okna (ten skrypt z -Wykonaj <id>) - glowny przebieg nie czeka na Claude,
# wiec zamek startu trwa sekundy; Claude po kolei pilnuje kolejka w procesie. Zwraca opis albo rzuca.
function Odpal-W-Tle($p) {
  $arg = @("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
           "-File", ('"' + $PSCommandPath + '"'), "-Wykonaj", "$($p.id)",
           "-Zrodlo", ('"' + $Zrodlo + '"'), "-KatalogDomowy", ('"' + $KatalogDomowy.TrimEnd('\') + '"'), "-Plik", ('"' + $Plik + '"'))
  if ($Dzis) { $arg += @("-Dzis", $Dzis) }
  if ($LimitSekund -gt 0) { $arg += @("-LimitSekund", "$LimitSekund") }
  if ($PauzaSekund -gt 0) { $arg += @("-PauzaSekund", "$PauzaSekund") }
  if ($Proba) {
    Write-Host "[proba] uruchomilbym w tle: powershell $($arg -join ' ')"
    return "proba"
  }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $psi.Arguments = $arg -join " "
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $proc = [System.Diagnostics.Process]::Start($psi)
  return "w tle, bez okna (proces $($proc.Id), limit $SEKUND_LIMITU_W_TLE s)"
}

# Ubija proces razem z dziecmi - claude.exe odpala bash, node i serwery MCP, samo Kill()
# zostawiloby je w tle. taskkill bez okna konsoli. Zwraca opis porazki albo "".
function Ubij-Drzewo([int]$procId) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = Join-Path $env:SystemRoot "System32\taskkill.exe"
  $psi.Arguments = "/T /F /PID $procId"
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $t = [System.Diagnostics.Process]::Start($psi)
  $wy = $t.StandardOutput.ReadToEndAsync(); $bl = $t.StandardError.ReadToEndAsync()
  if (-not $t.WaitForExit(15000)) { return "taskkill nie skonczyl w 15 s" }
  $t.WaitForExit()
  if ($t.ExitCode -ne 0) { return "taskkill kod $($t.ExitCode): $($bl.Result.Trim()) $($wy.Result.Trim())" }
  return ""
}

# claude -p bez okna, w katalogu projektu, polecenie na stdin (bez cytowania w wierszu
# polecen; bajty UTF-8 wprost do strumienia, bo .NET Framework nie ma kodowania stdin).
# MR_PRZYPOMNIENIE_W_TLE wycisza hook "terminy.js start" - inne zalegle przypomnienia nie
# maja odciagac Claude od znacznika WYNIK w pierwszej linii.
function Claude-W-Tle([string]$claude, [string]$kat, [string]$polecenie, [int]$id) {
  $r = [pscustomobject]@{ Kod = $null; Wyjscie = ""; Bledy = ""; Limit = $false; Uwagi = @() }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $claude
  $psi.Arguments = "-p --output-format json --permission-mode $TRYB_UPRAWNIEN_W_TLE"
  $psi.WorkingDirectory = $kat
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
  $psi.EnvironmentVariables["MR_PRZYPOMNIENIE_W_TLE"] = "$id"
  foreach ($n in $ZNACZNIKI_SESJI_NADRZEDNEJ) { $psi.EnvironmentVariables.Remove($n) }   # brak klucza = nic
  $proc = [System.Diagnostics.Process]::Start($psi)
  $wy = $proc.StandardOutput.ReadToEndAsync(); $bl = $proc.StandardError.ReadToEndAsync()
  try {
    $b = (New-Object System.Text.UTF8Encoding($false)).GetBytes($polecenie)
    $proc.StandardInput.BaseStream.Write($b, 0, $b.Length)
    $proc.StandardInput.BaseStream.Flush()
    $proc.StandardInput.Close()
  } catch { $r.Uwagi += "polecenie nie weszlo na stdin: $($_.Exception.Message)" }
  if ($proc.WaitForExit($SEKUND_LIMITU_W_TLE * 1000)) {
    $proc.WaitForExit()
    $r.Kod = $proc.ExitCode
  } else {
    $r.Limit = $true
    $u = Ubij-Drzewo $proc.Id
    if ($u) { $r.Uwagi += "ubijanie po limicie: $u" }
    if (-not $proc.WaitForExit(10000)) { $r.Uwagi += "proces $($proc.Id) zyje mimo ubijania" }
  }
  # Dziecko, ktore odziedziczylo wyjscie i zyje dalej, trzymaloby strumien bez konca.
  if ($wy.Wait(30000)) { $r.Wyjscie = $wy.Result } else { $r.Uwagi += "stdout nie domkniety w 30 s" }
  if ($bl.Wait(5000)) { $r.Bledy = $bl.Result } else { $r.Uwagi += "stderr nie domkniety w 5 s" }
  return $r
}

function Ogon([string]$t, [int]$ile) {
  $t = "$t".Trim()
  if ($t.Length -le $ile) { return $t }
  return "(...poczatek pominiety...) " + $t.Substring($t.Length - $ile)
}

# Powod bledu: co sie stalo + surowa tresc bledu; gdy tresc (stderr albo odpowiedz Claude)
# pasuje do bledu przejsciowego - na poczatku zdanie dla czlowieka i Przejsciowy = ponowic.
function Powod-Bledu($w, [string]$co, [string]$tresc, [string]$doOceny) {
  $szczegoly = $co
  if ("$tresc".Trim()) { $szczegoly += ": " + (Ogon ($tresc -replace '\s+', ' ') 300) }
  foreach ($b in $BLEDY_PRZEJSCIOWE) {
    if ($doOceny -match $b.Wzor) { $w.Przejsciowy = $true; $w.Powod = "$($b.Opis) ($szczegoly)"; return }
  }
  $w.Powod = $szczegoly
}

# Wynik przebiegu. Domyslnie "blad" - "nic" tylko przy czystym przebiegu ze znacznikiem
# NIC_NIE_MUSISZ w pierwszej linii odpowiedzi. Kazda inna sytuacja konczy sie oknem.
# Przejsciowy = blad, ktory mija sam (Wykonaj-W-Tle ponawia); brak znacznika, nieznany
# znacznik i limit czasu nigdy nie sa przejsciowe.
function Ocen-Przebieg($r) {
  $w = [pscustomobject]@{ Wynik = "blad"; CoZrobic = ""; Powod = ""; Raport = ""; Sesja = ""; Przejsciowy = $false }
  $j = $null
  $bladJson = ""
  $tekst = "$($r.Wyjscie)".Trim()
  if ($tekst) {
    try { $j = $tekst | ConvertFrom-Json } catch { $bladJson = $_.Exception.Message }
    # Ostrzezenie wypisane przed JSON-em nie moze zgubic odpowiedzi - wtedy ostatnia linia "{...".
    $ost = @($tekst -split "\r?\n" | Where-Object { $_.TrimStart().StartsWith("{") } | Select-Object -Last 1)
    if (-not $j -and $ost.Count -gt 0 -and $ost[0].Trim() -ne $tekst) {
      try { $j = $ost[0] | ConvertFrom-Json; $bladJson = "" } catch { $bladJson += "; ostatnia linia: $($_.Exception.Message)" }
    }
    if ($j -and -not ($j.PSObject.Properties.Name -contains "result")) { $bladJson = "brak pola result"; $j = $null }
  } else { $bladJson = "puste wyjscie" }
  if ($j) { $w.Sesja = "$($j.session_id)"; $w.Raport = "$($j.result)" }
  if (-not $w.Raport) {
    $w.Raport = "Brak odpowiedzi Claude.`r`n`r`nWyjście procesu:`r`n" + (Ogon $tekst $MAX_WYJSCIA_W_RAPORCIE) +
                "`r`n`r`nBłędy procesu:`r`n" + (Ogon $r.Bledy $MAX_WYJSCIA_W_RAPORCIE)
  }
  # Tresc bledu: stderr, a gdy pusty - odpowiedz Claude (pole result) albo samo wyjscie.
  # 2026-10-12 blad logowania byl tylko w result, a powod brzmial "...kodem 1: " bez tresci.
  $trescBledu = "$($r.Bledy)".Trim()
  if (-not $trescBledu) { if ($j -and "$($j.result)".Trim()) { $trescBledu = "$($j.result)".Trim() } else { $trescBledu = $tekst } }
  $doOceny = "$($r.Bledy)`n$($w.Raport)"
  if ($r.Limit) { $w.Powod = "przekroczony limit czasu ($([int]($SEKUND_LIMITU_W_TLE / 60)) min, $SEKUND_LIMITU_W_TLE s) - proces ubity"; return $w }
  if ($r.Kod -ne 0) { Powod-Bledu $w "Claude Code zakończył się kodem $($r.Kod)" $trescBledu $doOceny; return $w }
  if (-not $j) { Powod-Bledu $w "nieczytelna odpowiedź Claude Code (nie JSON: $bladJson)" $trescBledu $doOceny; return $w }
  if ($j.is_error) { Powod-Bledu $w "Claude Code zgłosił błąd ($($j.subtype))" $trescBledu $doOceny; return $w }
  $pierwsza = @("$($j.result)" -split "\r?\n" | Where-Object { $_.Trim() } | Select-Object -First 1)
  $linia = ""
  if ($pierwsza.Count -gt 0) { $linia = $pierwsza[0].Trim().Trim('*', '`', '#', '>', '_', ' ') }
  # Odmowa uprawnien = blad naszej konfiguracji (tryb $TRYB_UPRAWNIEN_W_TLE), nie zadanie dla
  # czlowieka: zamiast terminala z prosba "uruchom gdzie indziej" - na jutro i okno niepowodzenia.
  # Rozpoznanie tylko z pola permission_denials (lista {tool_name, tool_use_id, tool_input}), nie
  # ze slow w odpowiedzi. Przy NIC_NIE_MUSISZ zadanie zrobione mimo odmowy - Odmowy idzie do dziennika.
  $odmowy = @(@($j.permission_denials) | Where-Object { $_ } | ForEach-Object { "$($_.tool_name)".Trim() } | Where-Object { $_ } | Select-Object -Unique)
  $w | Add-Member -NotePropertyName Odmowy -NotePropertyValue $odmowy -Force
  if ($linia -match '^WYNIK:\s*NIC_NIE_MUSISZ$') { $w.Wynik = "nic"; return $w }
  if ($odmowy.Count -gt 0) { $w.Powod = "brak uprawnień w tle: Claude Code odrzucił narzędzia $($odmowy -join ', ') (tryb uprawnień $TRYB_UPRAWNIEN_W_TLE) - błąd ustawień MegaRuchacza, nie zadanie dla ciebie"; return $w }
  if ($linia -match '^WYNIK:\s*POTRZEBUJE_CIEBIE:\s*(\S.*)$') { $w.Wynik = "czlowiek"; $w.CoZrobic = $matches[1].Trim(); return $w }
  if ($linia -match '^WYNIK:') { $w.Powod = "nieznany znacznik w pierwszej linii odpowiedzi: $linia"; return $w }
  $w.Powod = "brak znacznika WYNIK w pierwszej linii odpowiedzi"
  return $w
}

# Wynik na trwale: <id>.json (umowa z karta Przeglad nadzorcy - nazwy pol sa jej czescia)
# i <id>.md do Notatnika. Kolejny przebieg tego samego id nadpisuje oba. Zwraca sciezke json.
function Zapisz-Wynik($p, [string]$kat, [datetime]$start, [datetime]$koniec, $w) {
  $raport = "$($w.Raport)".Replace([string][char]0, "")
  $dane = [ordered]@{
    id = [int]$p.id; tresc = "$($p.tresc)"; projekt = "$($p.projekt)"
    start = $start.ToString("yyyy-MM-ddTHH:mm:sszzz"); koniec = $koniec.ToString("yyyy-MM-ddTHH:mm:sszzz")
    wynik = $w.Wynik; co_zrobic = $w.CoZrobic; powod = $w.Powod; raport = $raport
    session_id = $w.Sesja; projekt_katalog = $kat
  }
  $json = Join-Path $KatWynikow "$($p.id).json"
  $md = Join-Path $KatWynikow "$($p.id).md"
  $naglowek = switch ($w.Wynik) {
    "nic"      { "Nic nie musisz robić." }
    "czlowiek" { "MUSISZ: $($w.CoZrobic)" }
    default    { "NIE UDAŁO SIĘ: $($w.Powod)" }
  }
  $tekstMd = (@("# Przypomnienie #$($p.id): $($p.tresc)", "", $naglowek, "",
                "Projekt: $($p.projekt)", "Start: $($dane.start)", "Koniec: $($dane.koniec)", "Sesja Claude: $($w.Sesja)", "",
                "## Raport", "", $raport) -join "`n") -replace "\r?\n", "`r`n"
  Zapisz-Trwale $json (($dane | ConvertTo-Json -Depth 3) + "`r`n")
  Zapisz-Trwale $md ($tekstMd + "`r`n") (New-Object System.Text.UTF8Encoding($true))
  return $json
}

# Okno dla czlowieka po przebiegu w tle: naglowek "MUSISZ: ..." albo "NIE UDALO SIE: ...",
# pod nim ta sama rozmowa (claude --resume), a bez sesji - nowa z tym samym zadaniem.
# Od 2026-10-12 wolane tylko przy "czlowiek" - "blad" dostaje Okno-Niepowodzenia (bez terminala).
function Okno-Po-Przebiegu($p, [string]$kat, [string]$claude, $w, [string]$sciezkaMd) {
  if ($w.Wynik -eq "czlowiek") { $glowa = "MUSISZ: $($w.CoZrobic)"; $kolor = "Yellow" }
  else { $glowa = "NIE UDAŁO SIĘ: $($w.Powod)"; $kolor = "Red" }
  $start = Join-Path $KatUruchomien "zrob-$($p.id).ps1"
  $linie = @(
    "# MegaRuchacz: przypomnienie #$($p.id) - po przebiegu w tle $(Get-Date -Format 'yyyy-MM-dd HH:mm'), wynik $($w.Wynik) (zasobnik\terminy.ps1)",
    ('$Host.UI.RawUI.WindowTitle = ' + (Napis-PS "MegaRuchacz - przypomnienie #$($p.id): $glowa")),
    ('$ramka = "=" * [Math]::Max(40, [Math]::Min(100, $Host.UI.RawUI.WindowSize.Width - 1))'),
    'Write-Host ""',
    ('Write-Host $ramka -ForegroundColor ' + $kolor),
    ('Write-Host ' + (Napis-PS "  $glowa  ") + ' -ForegroundColor Black -BackgroundColor ' + $kolor),
    ('Write-Host $ramka -ForegroundColor ' + $kolor),
    ('Write-Host ' + (Napis-PS "Przypomnienie #$($p.id): $($p.tresc)")),
    ('Write-Host ' + (Napis-PS "Pełny raport: $sciezkaMd")),
    'Write-Host ""',
    ('Set-Location -LiteralPath ' + (Napis-PS $kat)))
  $linie += @(Linie-Bez-Znacznikow-Sesji)
  if ($w.Sesja) {
    $linie += ('Write-Host ' + (Napis-PS "Niżej rozmowa, w której Claude robił to zadanie - możesz pisać w niej dalej.") + ' -ForegroundColor Gray')
    $linie += ('& ' + (Napis-PS $claude) + ' --resume ' + (Napis-PS $w.Sesja))
  } else {
    $linie += ('Write-Host ' + (Napis-PS "Rozmowy z przebiegu w tle nie da się wznowić - zaczynam nową z tym samym zadaniem.") + ' -ForegroundColor Gray')
    $linie += ('$polecenie = ' + (Napis-PS (Polecenie-Dla-Claude $p $kat)))
    $linie += ('& ' + (Napis-PS $claude) + ' $polecenie')
  }
  Zapisz-Skrypt-Startowy $start $linie
  return (Otworz-Terminal $kat "$($p.id)" $start)
}

# Kolejka Claude: czeka, az zaden inny proces przypomnien nie trzyma zamka, i go bierze. Zwraca
# zamek (oddaje go Zwolnij-Kolejke) albo rzuca po $MINUT_CZEKANIA_W_KOLEJCE. Zamek po procesie,
# ktory padl, nie blokuje: AbandonedMutexException = zamek juz nasz.
function Zajmij-Kolejke([string]$kto) {
  $z = New-Object System.Threading.Mutex($false, $NAZWA_KOLEJKI_CLAUDE)
  try {
    if ($z.WaitOne(0)) { return $z }
    Dopisz-Dziennik "${kto}: czeka w kolejce - Claude z innego przypomnienia jeszcze pracuje"
    $t0 = Get-Date
    if (-not $z.WaitOne($MINUT_CZEKANIA_W_KOLEJCE * 60000)) {
      $z.Dispose()
      throw "kolejka Claude zajęta dłużej niż $MINUT_CZEKANIA_W_KOLEJCE min - inne przypomnienie w tle utknęło"
    }
    Dopisz-Dziennik "${kto}: kolejka wolna po $([int]((Get-Date) - $t0).TotalSeconds) s"
    return $z
  } catch [System.Threading.AbandonedMutexException] {
    Dopisz-Dziennik "${kto}: przejal kolejke po procesie, ktory padl"
    return $z
  }
}

function Zwolnij-Kolejke($z) {
  if (-not $z) { return }
  try { $z.ReleaseMutex() } catch { Dopisz-Dziennik "kolejka Claude - nie zwolnilem zamka: $($_.Exception.Message)" }
  $z.Dispose()
}

# "Sprobuj teraz" z okna niepowodzenia: z powrotem na dzis, "w toku" i przebieg w tle - w kolejce,
# jak samoczynny (przesuniete na jutro nie jest zalegle, a -Wykonaj bierze tylko zalegle).
function Sprobuj-Teraz($p) {
  if (-not (Zmien-Status "przesun" @("$($p.id)", "dzis") "przycisk Sprobuj teraz #$($p.id): z powrotem na dzis")) { return $false }
  if (-not (Zmien-Status "w-toku" @("$($p.id)") "przycisk Sprobuj teraz #$($p.id): status w toku")) { return $false }
  $jak = Odpal-W-Tle $p
  Dopisz-Dziennik "przycisk Sprobuj teraz #$($p.id): $jak (Claude ruszy, gdy kolejka bedzie wolna)"
  return $true
}

# Okno po bledzie przebiegu w tle (decyzja uzytkownika 2026-10-12): zamiast terminala z surowa
# rozmowa Claude - okno przypomnien z jedna karta, zdaniem "Nie udalo sie ... bo: ... Przeniesione
# na jutro" i przyciskami "Sprobuj teraz" / "Odloz na jutro". Czeka na czlowieka (okno modalne).
function Okno-Niepowodzenia($p, $w, [bool]$przeniesione, [string]$bladPrzesuniecia, [string]$sciezkaMd, [string]$jutro) {
  $skrot = "$($p.tresc)".Trim().TrimEnd('.', ' ')
  if ($skrot.Length -gt $ZNAKOW_SKROTU_TRESCI) { $skrot = $skrot.Substring(0, $ZNAKOW_SKROTU_TRESCI).TrimEnd() + "…" }
  $uwaga = "Nie udało się wykonać przypomnienia #$($p.id) ($skrot), bo: $("$($w.Powod)".Trim().TrimEnd('.')). "
  if ($przeniesione) { $uwaga += "Przeniesione na jutro." }
  else { $uwaga += "Nie udało się też przenieść go na jutro ($bladPrzesuniecia) - zostaje w toku i jutro wróci w oknie przypomnień." }
  if ($sciezkaMd) { $uwaga += "`r`nPełny raport: $sciezkaMd" }
  $poz = $p | Select-Object *
  $poz | Add-Member -NotePropertyName uwaga -NotePropertyValue $uwaga -Force
  $poz | Add-Member -NotePropertyName przeniesione -NotePropertyValue $przeniesione -Force
  if ($przeniesione -and $jutro) { $poz.termin = $jutro; $poz.opis = "jutro" }
  Okno-Przypomnien @($poz) "niepowodzenie"
}

# Proces w tle (-Wykonaj): jedno przypomnienie "w toku" od poczatku do konca. Claude tylko po
# zajeciu kolejki, blad przejsciowy ponawiany. Wynik zapisany zawsze, status i okno zgodne
# z wynikiem, jedna linia podsumowania w dzienniku (przed oknem niepowodzenia, ktore czeka).
function Wykonaj-W-Tle([int]$id) {
  $plikZapisu = Join-Path $Zrodlo "narzedzia\zapis-trwaly.ps1"
  if (-not (Test-Path -LiteralPath $plikZapisu)) { throw "nie ma $plikZapisu - wyniku nie da sie zapisac trwale" }
  . $plikZapisu
  $r = Wolaj-Terminy @("zalegle", "--json")
  if ($r.Kod -ne 0) { throw "terminy.js zalegle --json: kod $($r.Kod) $($r.Blad)" }
  $dane = $r.Tekst | ConvertFrom-Json
  $p = @($dane.zalegle | Where-Object { $_ -and ([int]$_.id -eq $id) }) | Select-Object -First 1
  if (-not $p) { throw "nie ma zaleglego przypomnienia #$id" }
  if ($p.status -ne "w toku") { throw "przypomnienie #$id ma status '$($p.status)', a nie 'w toku' - nie uruchamiam" }
  $jutro = ""
  try { $jutro = [datetime]::ParseExact("$($dane.dzis)", "yyyy-MM-dd", $null).AddDays(1).ToString("yyyy-MM-dd") }
  catch { Dopisz-Dziennik "w tle #${id}: nieczytelne 'dzis' z terminy.js: '$($dane.dzis)'" }
  $kat = Katalog-Projektu $p
  $claude = Sciezka-Claude
  $start = Get-Date
  $uwagi = @()
  $nrProby = 0
  $w = $null
  $kolejka = $null
  try { $kolejka = Zajmij-Kolejke "w tle #$id" }
  catch { $w = [pscustomobject]@{ Wynik = "blad"; CoZrobic = ""; Raport = ""; Sesja = ""; Przejsciowy = $false; Powod = "$($_.Exception.Message)" } }
  try {
    if ($w) { }
    elseif (-not $claude) {
      $w = [pscustomobject]@{ Wynik = "blad"; CoZrobic = ""; Raport = ""; Sesja = ""; Przejsciowy = $false
                              Powod = "nie ma polecenia claude w PATH - Claude Code nie jest zainstalowany albo PATH tego procesu go nie widzi" }
      $claude = "claude"
    } else {
      while ($true) {
        $nrProby++
        try {
          $przebieg = Claude-W-Tle $claude $kat (Polecenie-Dla-Claude $p $kat $true) $id
          $uwagi += @($przebieg.Uwagi | ForEach-Object { "proba ${nrProby}: $_" })
          $w = Ocen-Przebieg $przebieg
        } catch {
          $w = [pscustomobject]@{ Wynik = "blad"; CoZrobic = ""; Raport = ""; Sesja = ""; Przejsciowy = $false; Powod = "Claude Code nie wystartował: $($_.Exception.Message)" }
        }
        if (-not (($w.Wynik -eq "blad") -and $w.Przejsciowy -and ($nrProby -lt $PROB_W_TLE))) { break }
        Dopisz-Dziennik ("w tle #${id}: proba $nrProby z $PROB_W_TLE nieudana, blad przejsciowy ($($w.Powod)) - ponawiam za $SEKUND_MIEDZY_PROBAMI s" -replace "\r?\n", " ")
        Start-Sleep -Seconds $SEKUND_MIEDZY_PROBAMI
      }
    }
  } finally { Zwolnij-Kolejke $kolejka }
  if (($w.Wynik -eq "nic") -and @($w.Odmowy).Count -gt 0) { $uwagi += "zrobione, ale Claude Code odrzucil narzedzia $(@($w.Odmowy) -join ', ') (tryb $TRYB_UPRAWNIEN_W_TLE) - sprawdz ustawienia uprawnien w tle" }
  if (($w.Wynik -eq "blad") -and ($nrProby -gt 0)) {
    if ($w.Przejsciowy) { $w.Powod += "; prób: $nrProby z $PROB_W_TLE" }
    else { $w.Powod += "; prób: $nrProby (ten błąd nie mija sam - bez ponawiania)" }
  }
  $koniec = Get-Date
  $sciezka = ""
  try {
    $sciezka = Zapisz-Wynik $p $kat $start $koniec $w
  } catch {
    $uwagi += "NIE ZAPISALEM wyniku: $($_.Exception.Message)"
    if ($w.Wynik -eq "nic") { $w.Wynik = "blad"; $w.Powod = "zadanie zrobione, ale nie zapisałem wyniku ($($_.Exception.Message))" }
    $script:BladZapisuWyniku = $true
  }
  $status = "zostaje w toku"
  $przeniesione = $false
  $bladPrzesuniecia = ""
  if ($w.Wynik -eq "nic") {
    if (Zmien-Status "zrobione" @("$id") "w tle #${id}: odhaczenie") { $status = "odhaczone" }
    else { $status = "NIE ODHACZONE ($($script:OstatniBladStatusu)) - wroci jutro w oknie jako niedokonczone" }
  } elseif ($w.Wynik -eq "blad") {
    # Blad = samo na jutro (decyzja uzytkownika 2026-10-12); jutro automat probuje znowu.
    $script:OstatniBladStatusu = ""
    if (Zmien-Status "przesun" @("$id", "jutro") "w tle #${id}: blad - przesuniecie na jutro") { $status = "przeniesione na jutro"; $przeniesione = $true }
    else { $bladPrzesuniecia = $script:OstatniBladStatusu; $status = "NIE PRZENIESIONE NA JUTRO ($bladPrzesuniecia) - zostaje w toku, jutro wroci w oknie jako niedokonczone" }
  }
  $okno = "bez okna"
  $pokazNiepowodzenie = $false
  if ($w.Wynik -ne "nic") {
    if ($w.Wynik -eq "czlowiek") {
      try { $okno = "okno: " + (Okno-Po-Przebiegu $p $kat $claude $w (Join-Path $KatWynikow "$id.md")) }
      catch { $okno = "NIE OTWORZYLEM okna: $($_.Exception.Message)"; $script:BladOkna = $true }
    } else { $okno = "okno niepowodzenia (Sprobuj teraz / Odloz na jutro)"; $pokazNiepowodzenie = $true }
  }
  $opis = $w.Wynik
  if ($w.Wynik -eq "czlowiek") { $opis += " (co: $($w.CoZrobic))" }
  if ($w.Wynik -eq "blad") { $opis += " (powod: $($w.Powod))" }
  $czas = [int]($koniec - $start).TotalSeconds
  $dopisek = ""; if ($uwagi.Count -gt 0) { $dopisek = "; UWAGI: " + ($uwagi -join "; ") }
  Dopisz-Dziennik ("w tle #${id}: wynik $opis; ${czas} s, sesja '$($w.Sesja)'; $status; wynik w '$sciezka'; $okno$dopisek" -replace "\r?\n", " ")
  if ($pokazNiepowodzenie) {
    $md = ""; if ($sciezka) { $md = Join-Path $KatWynikow "$id.md" }
    try { Okno-Niepowodzenia $p $w $przeniesione $bladPrzesuniecia $md $jutro }
    catch { Dopisz-Dziennik "w tle #${id}: NIE POKAZALEM okna niepowodzenia: $($_.Exception.Message)"; $script:BladOkna = $true }
  }
}

# -------------------------------------------------------------------- okno z przyciskami

# Napisy w oknie to pola tylko do odczytu, nie Label - Label nie daje sie zaznaczyc ani
# skopiowac (zgloszenie uzytkownika 2026-10-08). Bez ramki i w kolorze tla wyglada jak napis.
# TextBox nie ma AutoSize, wiec wysokosc z TextRenderer.MeasureText (zapas wyzej).
function Pole-Tekstowe([string]$tekst, [int]$szerokosc, $czcionka, $kolor, $tlo) {
  $t = New-Object System.Windows.Forms.TextBox
  $t.ReadOnly = $true
  $t.Multiline = $true
  $t.WordWrap = $true
  $t.ScrollBars = "None"
  $t.BorderStyle = "None"
  $t.TabStop = $false
  $t.BackColor = $tlo
  $t.ForeColor = $kolor
  $t.Font = $czcionka
  $t.Margin = New-Object System.Windows.Forms.Padding(3, 0, 3, 0)   # jak domyslny Label
  $t.Width = $szerokosc
  $t.Text = $tekst
  $flagi = [System.Windows.Forms.TextFormatFlags]"WordBreak, TextBoxControl, NoPrefix"
  $ile = New-Object System.Drawing.Size(($szerokosc - $ZAPAS_SZEROKOSCI_POLA), [int]::MaxValue)
  $t.Height = [System.Windows.Forms.TextRenderer]::MeasureText($tekst, $czcionka, $ile, $flagi).Height
  return $t
}

# Schowek z ponawianiem i obsluga komunikatow miedzy probami. Clipboard.SetText ponawia sam
# (10 x 100 ms), ale nie obsluguje w tym czasie komunikatow, a programy czytajace kazda zmiane
# schowka (zmierzone 2026-10-08: Remotly, historia schowka, Eksplorator) prosza nas o dane
# i trzymaja schowek, az je dostana - czekamy na siebie nawzajem. Zmierzone: 5 na 120 klikniec
# "Nie skopiowano" po 1,1 s, choc tekst trafil do schowka; z kodem ponizej - 0 na 120.
# Porazka po wszystkich probach to wyjatek - Kopiuj-Przypomnienie pokazuje ja i zapisuje.
function Do-Schowka([string]$tekst) {
  $blad = ""
  for ($i = 1; $i -le $PROB_SCHOWKA; $i++) {
    if ($i -gt 1) {
      $do = [datetime]::Now.AddMilliseconds($MS_MIEDZY_PROBAMI_SCHOWKA)
      while ([datetime]::Now -lt $do) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 10 }
    }
    try {
      $dane = New-Object System.Windows.Forms.DataObject
      $dane.SetData([System.Windows.Forms.DataFormats]::UnicodeText, $false, $tekst)
      [System.Windows.Forms.Clipboard]::SetDataObject($dane, $true, 0, 0)   # bez wlasnego czekania .NET
      return
    } catch { $blad = $_.Exception.Message }
  }
  throw "schowek zajety przez inny program - $PROB_SCHOWKA prob co $MS_MIEDZY_PROBAMI_SCHOWKA ms, ostatni blad: $blad"
}

# Przycisk "Kopiuj": naglowek i tresc przypomnienia do schowka. Porazka zostaje na przycisku
# ("Nie skopiowano") i w dzienniku - nie znika po chwili jak "Skopiowano".
function Kopiuj-Przypomnienie($btn) {
  $tag = $btn.Tag
  if ($tag.Zegar) { $tag.Zegar.Stop(); $tag.Zegar.Dispose(); $tag.Zegar = $null }
  try {
    Do-Schowka $tag.Tekst
  } catch {
    $btn.Text = "Nie skopiowano"
    Dopisz-Dziennik "przycisk Kopiuj #$($tag.Poz.id) - NIE SKOPIOWALEM do schowka: $($_.Exception.Message)"
    return
  }
  $btn.Text = "Skopiowano"
  $z = New-Object System.Windows.Forms.Timer
  $z.Interval = $MS_NAPISU_SKOPIOWANO
  $z.Tag = $btn
  $z.Add_Tick({ $this.Stop(); if (-not $this.Tag.IsDisposed) { $this.Tag.Text = "Kopiuj" } })
  $tag.Zegar = $z
  $z.Start()
}

# $rodzaj "niepowodzenie" (Okno-Niepowodzenia): ten sam wyglad, inny wstep, przyciski "Sprobuj
# teraz" / "Odloz na jutro", a krzyzyk nic nie odklada - sprawa juz jest na jutro.
function Okno-Przypomnien($pozycje, [string]$rodzaj = "") {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  [System.Windows.Forms.Application]::EnableVisualStyles()
  $script:Obsluzone = @{}
  $script:Pozostalo = @($pozycje).Count
  $script:Niepowodzenie = ($rodzaj -eq "niepowodzenie")
  $niepowodzenie = $script:Niepowodzenie

  $f = New-Object System.Windows.Forms.Form
  $f.Text = "MegaRuchacz - przypomnienia ($(@($pozycje).Count))"
  if ($niepowodzenie) { $f.Text = "MegaRuchacz - nie udało się wykonać przypomnienia" }
  $f.TopMost = $true
  $f.ShowInTaskbar = $true
  $f.StartPosition = "CenterScreen"
  $f.Font = New-Object System.Drawing.Font("Segoe UI", 10)
  $f.BackColor = [System.Drawing.Color]::White
  $f.Width = 780
  $f.Height = [Math]::Min(760, 170 + 150 * @($pozycje).Count)
  $f.MinimizeBox = $true
  $f.MaximizeBox = $false
  $ikona = Join-Path $Zrodlo "logo.png"
  if (Test-Path -LiteralPath $ikona) {
    try {
      $obraz = [System.Drawing.Image]::FromFile($ikona)
      $f.Icon = [System.Drawing.Icon]::FromHandle((New-Object System.Drawing.Bitmap($obraz, 32, 32)).GetHicon())
      $obraz.Dispose()
    } catch { Dopisz-Dziennik "ikona okna: $($_.Exception.Message)" }
  }

  $lista = New-Object System.Windows.Forms.FlowLayoutPanel
  $lista.Dock = "Fill"
  $lista.FlowDirection = "TopDown"
  $lista.WrapContents = $false
  $lista.AutoScroll = $true
  $lista.Padding = New-Object System.Windows.Forms.Padding(14, 10, 14, 10)
  $f.Controls.Add($lista)

  $czerwony = [System.Drawing.Color]::FromArgb(170, 40, 20)
  $tekstWstepu = ("Te sprawy mają termin dziś albo już minął. Wybierz, co z każdą zrobić. " +
                  "Zamknięcie okna krzyżykiem = przypomnę ponownie za 2 godziny.")
  if ($niepowodzenie) {
    $tekstWstepu = ("Automat nie zdołał wykonać tego przypomnienia w tle. Jutro spróbuje znowu sam - nic nie musisz robić. " +
                    "Zamknięcie okna krzyżykiem = zostaje na jutro.")
  }
  $wstep = Pole-Tekstowe $tekstWstepu 720 $f.Font $f.ForeColor $f.BackColor
  $wstep.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
  $lista.Controls.Add($wstep)

  foreach ($p in @($pozycje)) {
    $karta = New-Object System.Windows.Forms.FlowLayoutPanel
    $karta.FlowDirection = "TopDown"
    $karta.WrapContents = $false
    $karta.AutoSize = $true
    $karta.BorderStyle = "FixedSingle"
    $karta.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)
    $karta.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $karta.MinimumSize = New-Object System.Drawing.Size(720, 0)

    $gruba = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $glowa = Pole-Tekstowe "#$($p.id)   $($p.termin) ($($p.opis))   $($p.projekt)" 690 $gruba $f.ForeColor $f.BackColor
    $karta.Controls.Add($glowa)

    $tresc = $p.tresc
    if ($p.sprawdz) { $tresc += "`r`nJak sprawdzić: $($p.sprawdz)" }
    $tekst = Pole-Tekstowe $tresc 690 $f.Font $f.ForeColor $f.BackColor
    $karta.Controls.Add($tekst)

    if ($p.uwaga) {
      $uw = Pole-Tekstowe $p.uwaga 690 $f.Font $czerwony $f.BackColor
      $karta.Controls.Add($uw)
    }

    $przyciski = New-Object System.Windows.Forms.FlowLayoutPanel
    $przyciski.AutoSize = $true
    $przyciski.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $akcje = @(@("Zrób teraz", "teraz"), @("Jutro", "jutro"), @("Zrobione", "zrobione"))
    if ($niepowodzenie) { $akcje = @(@("Spróbuj teraz", "sprobuj"), @("Odłóż na jutro", "odloz")) }
    foreach ($b in $akcje) {
      $btn = New-Object System.Windows.Forms.Button
      $btn.Text = $b[0]
      $btn.AccessibleName = "$($b[0]) #$($p.id)"
      $btn.AutoSize = $true
      $btn.Padding = New-Object System.Windows.Forms.Padding(8, 2, 8, 2)
      $btn.Tag = @{ Akcja = $b[1]; Poz = $p; Karta = $karta }
      $btn.Add_Click({ Klik $this.Tag })
      $przyciski.Controls.Add($btn)
    }
    $kop = New-Object System.Windows.Forms.Button
    $kop.AutoSize = $true
    $kop.Padding = New-Object System.Windows.Forms.Padding(8, 2, 8, 2)
    $kop.Text = "Nie skopiowano"   # najdluzszy napis - przycisk nie skacze przy zmianie
    $kop.MinimumSize = New-Object System.Drawing.Size($kop.PreferredSize.Width, 0)
    $kop.Text = "Kopiuj"
    $kop.AccessibleName = "Kopiuj #$($p.id)"
    $kop.Tag = @{ Poz = $p; Tekst = $glowa.Text + "`r`n" + $tekst.Text; Zegar = $null }
    $kop.Add_Click({ Kopiuj-Przypomnienie $this })
    $przyciski.Controls.Add($kop)
    $karta.Controls.Add($przyciski)
    $lista.Controls.Add($karta)
  }

  $f.Add_FormClosing({
    param($s, $e)
    if ($script:Niepowodzenie) {
      if ($script:Pozostalo -gt 0) { Dopisz-Dziennik "okno niepowodzenia zamkniete krzyzykiem - zostaje na jutro" }
      else { Dopisz-Dziennik "okno niepowodzenia zamkniete - obsluzone" }
    } elseif ($script:Pozostalo -gt 0) {
      $do = (Get-Date).AddMinutes($MINUT_ODLOZENIA)
      try { Zapisz-Klucz-Okna "odlozone_do" $do.ToString("yyyy-MM-dd HH:mm:ss") }
      catch { Dopisz-Dziennik "zapis odlozenia sie nie udal: $($_.Exception.Message)" }
      Dopisz-Dziennik "okno zamkniete bez obslugi $($script:Pozostalo) spraw - wroce o $($do.ToString('HH:mm'))"
    } else {
      Dopisz-Dziennik "okno zamkniete - wszystko obsluzone"
    }
  })
  $script:Okno = $f
  $f.Add_Shown({ $f.Activate() })
  if ($niepowodzenie) {
    Dopisz-Dziennik ("okno niepowodzenia pokazane: " + ((@($pozycje) | ForEach-Object { "#$($_.id)" }) -join ", "))
  } else {
    Dopisz-Dziennik ("okno pokazane: " + ((@($pozycje) | ForEach-Object { "#$($_.id)" }) -join ", "))
    Zapisz-Klucz-Okna "pokazane" (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  }
  [void]$f.ShowDialog()
  $f.Dispose()
}

function Klik($tag) {
  $p = $tag.Poz
  $ok = $false
  $script:OstatniBladStatusu = ""
  try {
    switch ($tag.Akcja) {
      "teraz" {
        $arg = @("$($p.id)")
        if ($p.status -eq "w toku") { $arg += "--ponownie" }
        if (Zmien-Status "w-toku" $arg "przycisk Zrob teraz #$($p.id): status w toku") {
          $jak = Uruchom-Claude $p "uruchomione przyciskiem"
          Dopisz-Dziennik "przycisk Zrob teraz #$($p.id): $jak"
          $ok = $true
        }
      }
      "jutro"    { $ok = Zmien-Status "przesun" @("$($p.id)", "jutro") "przycisk Jutro #$($p.id)" }
      "zrobione" { $ok = Zmien-Status "zrobione" @("$($p.id)") "przycisk Zrobione #$($p.id)" }
      "sprobuj"  { $ok = Sprobuj-Teraz $p }
      "odloz" {
        if ($p.przeniesione) { Dopisz-Dziennik "przycisk Odloz na jutro #$($p.id): zostaje na jutro"; $ok = $true }
        else { $ok = Zmien-Status "przesun" @("$($p.id)", "jutro") "przycisk Odloz na jutro #$($p.id)" }
      }
    }
  } catch {
    $script:OstatniBladStatusu = $_.Exception.Message
    Dopisz-Dziennik "przycisk $($tag.Akcja) #$($p.id) - WYWROTKA: $($_.Exception.Message)"
  }
  if (-not $ok) {
    [void][System.Windows.Forms.MessageBox]::Show($script:Okno,
      "Nie udało się ($($tag.Akcja), przypomnienie #$($p.id)): $($script:OstatniBladStatusu)`r`n`r`nSzczegóły: $Dziennik",
      "MegaRuchacz", "OK", "Warning")
    return
  }
  $tag.Karta.Visible = $false
  $script:Pozostalo--
  if ($script:Pozostalo -le 0) { $script:Okno.Close() }
}

# ------------------------------------------------------------------------- przebieg

$kod = 0
$zamekStartu = $null
try {
  $nodeCmd = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $nodeCmd) { throw "nie ma node w PATH - przypomnien nie da sie przeczytac" }
  $script:Node = $nodeCmd.Source
  if (-not (Test-Path -LiteralPath $SkryptTerminow)) { throw "nie ma $SkryptTerminow" }

  if ($Wykonaj -gt 0) {
    if ($Proba) { throw "-Wykonaj nie dziala z -Proba (uruchamia Claude naprawde)" }
    Wykonaj-W-Tle $Wykonaj
    if ($script:BladZapisuWyniku -or $script:BladOkna) { $kod = 1 }
    if ($script:BladDziennika) { $kod = 1 }
    exit $kod
  }

  # Jedna kopia czesci uruchamiajacej naraz - dwie odpalone jednoczesnie otworzylyby to samo
  # zadanie dwa razy, zanim pierwsza zdazy zapisac "w toku".
  $zamekStartu = New-Object System.Threading.Mutex($false, "Local\MegaRuchacz-Terminy-Start")
  if (-not $zamekStartu.WaitOne(0)) {
    Dopisz-Dziennik "inna kopia wlasnie uruchamia przypomnienia - ta konczy"
    $zamekStartu.Dispose(); $zamekStartu = $null
    exit 0
  }

  $r = Wolaj-Terminy @("zalegle", "--json")
  if ($r.Kod -ne 0) { throw "terminy.js zalegle --json: kod $($r.Kod) $($r.Blad)" }
  $dane = $r.Tekst | ConvertFrom-Json
  foreach ($n in @($dane.nieczytelne)) { if ($n) { Dopisz-Dziennik "UWAGA plik przypomnien, $n" } }
  $zalegle = @($dane.zalegle | Where-Object { $_ })
  $dzis = $dane.dzis

  $doOkna = @()
  $uruchomione = 0
  foreach ($p in $zalegle) {
    $p | Add-Member -NotePropertyName uwaga -NotePropertyValue "" -Force
    if ($p.status -eq "otwarte" -and $p.tryb -eq "sam") {
      # Procesy w tle ruszaja od razu wszystkie, ale Claude po kolei - czekaja w kolejce (Zajmij-Kolejke).
      if (-not (Zmien-Status "w-toku" @("$($p.id)") "samoczynne #$($p.id): status w toku")) {
        $p.uwaga = "Automat nie zdołał oznaczyć sprawy jako »w toku« i jej nie uruchomił: $($script:OstatniBladStatusu)"
        $doOkna += $p
        continue
      }
      try {
        $jak = Odpal-W-Tle $p
        Dopisz-Dziennik "samoczynne #$($p.id) ($($p.termin), $($p.projekt)): $jak"
        $uruchomione++
      } catch {
        Dopisz-Dziennik "samoczynne #$($p.id) - NIE URUCHOMILEM zadania w tle: $($_.Exception.Message)"
        $p.status = "w toku"
        $p.uwaga = "Automat nie zdołał uruchomić zadania w tle: $($_.Exception.Message)"
        $doOkna += $p
      }
      continue
    }
    if ($p.status -eq "otwarte") { $doOkna += $p; continue }   # tryb "przypomnij"
    # "w toku": od dzis = jeszcze chodzi, nie przeszkadzamy; od wczoraj albo dawniej = nie dokonczone
    $od = "$($p.wTokuOd)"
    if ($od.Length -ge 10 -and $od.Substring(0, 10) -lt $dzis) {
      if ($p.tryb -eq "sam") {
        $p.uwaga = "Automat uruchomił to zadanie $od, ale nie zostało dokończone (nie odhaczone)."
        $md = Join-Path $KatWynikow "$($p.id).md"
        if (Test-Path -LiteralPath $md) { $p.uwaga += " Raport z przebiegu: $md" }
      }
      else { $p.uwaga = "Uruchomione $od, ale nie zostało dokończone (nie odhaczone)." }
      $doOkna += $p
    }
  }
  $zamekStartu.ReleaseMutex(); $zamekStartu.Dispose(); $zamekStartu = $null

  $dopisek = ""
  if ($doOkna.Count -gt 0) { $dopisek = ", do okna: " + (($doOkna | ForEach-Object { "#$($_.id)" }) -join ", ") }
  Dopisz-Dziennik "sprawdzenie: zaleglych $($zalegle.Count), uruchomionych samoczynnie $uruchomione$dopisek"

  if ($doOkna.Count -gt 0 -and -not $BezOkna) {
    # Niepowodzenia z tego przebiegu ida od razu, mimo odlozenia - nie moga czekac w ciszy.
    $pilne = @($doOkna | Where-Object { $_.uwaga -like "Automat nie zdo*" })
    $odlozone = $null
    $k = Czytaj-Klucze-Okna
    if ($k["odlozone_do"]) { try { $odlozone = [datetime]::ParseExact($k["odlozone_do"], "yyyy-MM-dd HH:mm:ss", $null) } catch { Dopisz-Dziennik "nieczytelne odlozone_do: $($k['odlozone_do'])" } }
    if ($odlozone -and (Get-Date) -lt $odlozone -and $pilne.Count -eq 0) {
      Dopisz-Dziennik "okno odlozone krzyzykiem do $($odlozone.ToString('HH:mm')) - nie pokazuje"
    } elseif ($Proba) {
      Write-Host "[proba] pokazalbym okno z: $(($doOkna | ForEach-Object { "#$($_.id) $($_.tresc) $($_.uwaga)" }) -join ' || ')"
    } else {
      $zamekOkna = New-Object System.Threading.Mutex($false, "Local\MegaRuchacz-Terminy-Okno")
      if ($zamekOkna.WaitOne(0)) {
        try { Okno-Przypomnien $doOkna } finally { $zamekOkna.ReleaseMutex(); $zamekOkna.Dispose() }
      } else {
        $zamekOkna.Dispose()
        Dopisz-Dziennik "okno przypomnien juz stoi na ekranie - drugiego nie otwieram"
      }
    }
  }
} catch {
  $kod = 1
  Dopisz-Dziennik "WYWROTKA: $($_.Exception.Message)"
  [Console]::Error.WriteLine("terminy.ps1: $($_.Exception.Message)")
} finally {
  if ($zamekStartu) { try { $zamekStartu.ReleaseMutex() } catch { Dopisz-Dziennik "zamek startu: $($_.Exception.Message)" }; $zamekStartu.Dispose() }
}
if ($script:BladDziennika) { $kod = 1 }
exit $kod
