# narzedzia\aktualizuj-megaruchacza.ps1 - aktualizacja SAMEGO MegaRuchacza, zawsze automatyczna:
# pobranie nowszej wersji z gita, naniesienie jej na ten komputer i restart nadzorcy.
#
# PO CO TO ISTNIEJE. Decyzja uzytkownika 2026-10-07: aktualizacja ma sie dziac sama, bez klikania -
# przy starcie nadzorcy i potem co godzine - i ma sie NANOSIC, a nie konczyc na "git pull". Do tej
# pory nadzorca tylko liczyl, ile zmian czeka (Stan-Wersji), hook straznika pobieral, ale nikt nie
# wolal instaluj-globalnie ani nie restartowal nadzorcy: nowy kod okna dzialal dopiero po recznym
# restarcie, a znacznik ~\.claude\.megaruchacz-global stal na starej wersji (w domu 0.21.3).
#
# JEDNO WEJSCIE dla automatu (nadzorca: zasobnik\nadzorca\dozor.ps1 Ruszaj-Aktualizacje - ~1 min
# po starcie i co 60 min) i dla przycisku w oknie (-Reczna). Zawsze w osobnym, ukrytym procesie.
# Jeden przebieg naraz na katalog zrodlowy (blokada): drugi, wywolany w trakcie, konczy sie od
# razu kodem 3 i NICZEGO nie zapisuje - stan pierwszego zostaje nietkniety.
#
# KROKI (pole "krok" w aktualizacja.json, "krokow" = 4):
#   1 sprawdzam - straznik-zasad.ps1 -TylkoPobierz: git fetch, a gdy jest nowsza wersja, git merge
#                 --ff-only. Warunki odmowy, kopie plikow roboczych i zdania o nich sa u straznika -
#                 tu nie ma drugiej implementacji pobierania i nie ma reset/stash/clean.
#   2 pobieram  - co przyszlo: wersja przed i po (najwyzszy "## X.Y.Z" w ZMIANY.md) i commit.
#   3 nanosze   - wedlug rejestru ~\.claude\mr\instalacja.json (tylko moduly wlaczone; rejestr
#                 nieczytelny = jak pelna instalacja, tak jak u straznika):
#                   kierownik przy instalacji globalnej - instaluj-globalnie.ps1 -BezPytania (zasady,
#                     role, hooki, znacznik .megaruchacz-global z nowym numerem wersji),
#                   zawsze - wpisz-zasady.ps1 i straznik-zasad.ps1 -Dopasuj (bloki zasad i hooki
#                     wedlug rejestru - to samo, co instalator po zmianie modulow),
#                   brakujaca Pamiec rozmow (Lore) - Doinstaluj-Lore: zaleznosci.ps1 (uv, Python,
#                     Node.js), potem modul-lore.ps1 Instaluj (ok. 770 MB, pierwsze czytanie rozmow
#                     w tle); porazka NIE zatrzymuje nowej wersji - skille, znacznik i restart ida
#                     dalej, a wynikiem przebiegu jest blad lore (pole lore_blad, Koniec-Naniesienia),
#                   skille - skille.ps1 -Tryb instaluj -Wbudowane (brakujace wbudowane skille;
#                     porazka to uwaga, nie blad: codzienne sprawdzenie skilli sprobuje znowu).
#   4 restart   - odlaczony pomocnik (ten skrypt z -Restart, proces POZA drzewem nadzorcy) zamyka
#                 stary proces nadzorcy TEGO repo, startuje zadanie Harmonogramu i sprawdza, ze
#                 nowy proces wstal; wynik dopisuje sam (etap "gotowe" albo "blad").
# "Czy nanosic" liczy sie wobec ostatniego UDANEGO naniesienia (~\.claude\mr\aktualizacja-naniesione.txt:
# commit naniesiony i commit, na ktorym wstal nadzorca), a nie wobec tego, czy pobieral TEN przebieg -
# wersje pobrana wczesniej przez hook straznika (otwarcie sesji Claude Code, Codex) tez trzeba naniesc.
# Nic nowego = etap "gotowe", wynik "aktualne", bez krokow 3 i 4.
#
# PAMIEC ROZMOW (LORE) JEST OBOWIAZKOWA (decyzja uzytkownika 2026-10-17: nowy uklad pamieci stoi na
# Lore - CLAUDE.md trzyma tylko staly rdzen, reszte Claude dostaje z Lore). Komputer, na ktorym jej
# brakuje (Lore-Brakuje: flaga lore w rejestrze nie true albo brak srodowiska lore\.venv), dostaje ja
# tutaj sam - liczone NIEZALEZNIE od znacznikow naniesienia, bo pierwsza aktualizacja niosaca ten kod
# wykona sie jeszcze starym skryptem i zostawi znaczniki rowne HEAD. Gdy brak Lore to jedyny powod:
# krok 2 "Brakuje Pamieci rozmow...", krok 3 samo Doinstaluj-Lore - bez instaluj-globalnie, bez
# restartu, znaczniki nietkniete - i koniec "zaktualizowano" z polem doinstalowano. Odroczenie (uwaga,
# nie blad): otwarte okno instalatora (ono samo instaluje Lore; gdy nic innego nie ma do zrobienia -
# przyczyna lore-zajete, w oknie szara linia) i $MINUT_PO_STARCIE_WINDOWS min po starcie albo
# wybudzeniu Windows. modul-lore.ps1 ma wlasna blokade - zajety tez konczy sie przyczyna lore-zajete.
# Przy nowej wersji porazka Lore nie przerywa naniesienia (decyzja 2026-10-17 wedlug reguly uzytkownika
# "przy aktualizacji nowsza wersja zawsze wygrywa"; wczesniej siec blokujaca pypi albo huggingface
# trzymala komputer na starym kodzie, a co godzine szla nowa proba do 90 min). Porazka czeka w stanie
# (lore_blad) do konca przebiegu i dopiero tam - takze u pomocnika restartu - zamienia sie w blad
# zamiast zielonego "zaktualizowano". Nastepny przebieg (pierwszy rusza nowy nadzorca ok. minuty po
# starcie, potem co godzine) ma znaczniki = HEAD, wiec probuje samo Lore.
#
# STAN dla okna i nadzorcy: ~\.claude\mr\aktualizacja.json (UTF-8 bez BOM, zapis atomowy przez
# zapis-trwaly.ps1: plik tymczasowy + podmiana), pisany na biezaco:
#   etap        sprawdzam | pobieram | nanosze | restart | gotowe | blad
#   krok        1..4, krokow 4
#   opis        krotkie zdanie po polsku pod pasek postepu
#   wynik       "" w trakcie; na koncu zaktualizowano | aktualne | blad
#   wersja_przed, wersja_po   "X.Y.Z"
#   start, koniec             czas ISO lokalny
#   sprawdzone  ostatni UDANY kontakt z serwerem (brak sieci zostawia poprzedni - stad wiadomo, od
#               kiedy nie da sie sprawdzic)
#   powod       przy bledzie: co sie stalo i co zrobic, po ludzku
#   reczna      true = przycisk w oknie
#   przyczyna   skad blad: wynik straznika (bez-sieci, zablokowane, rozjechane, ...) albo krok
#               (nanoszenie, restart, blokada-pomocnika, wywrotka, lore - doinstalowanie Pamieci
#               rozmow, lore-zajete - Lore instaluje inny proces: lagodna, jak zajete)
#   uwagi       rzeczy, ktore nie przerwaly aktualizacji, a maja byc widac (np. skille bez sieci)
#   doinstalowano  ["lore"], gdy ten przebieg doinstalowal Pamiec rozmow (Lore); inaczej []
#   lore_blad   null albo {przyczyna, powod}: Pamiec rozmow nie doinstalowala sie przy naniesieniu nowej
#               wersji - blad na koniec przebiegu (pomocnik restartu czyta go z tego pliku)
#   zrodlo, pid katalog repo i proces, ktory pisze (pomocnik restartu ma inny PID)
# Dziennik: ~\.claude\mr\aktualizacja.log - kazdy krok z PELNYM wyjsciem tego, co wolal.
#
# Uzycie (niewidocznie - wola go nadzorca przez conhost --headless):
#   powershell -NoProfile -ExecutionPolicy Bypass -File narzedzia\aktualizuj-megaruchacza.ps1
#     [-Zrodlo <repo>] [-KatalogDomowy <kat>] [-Reczna]
#     -ZadanieNadzorcy <nazwa>  zadanie Harmonogramu, ktore startuje nadzorce (testy: wlasne MRTEST-)
#     -Restart -Zdarzenie <nazwa> -Commit <sha>   wewnetrzne: pomocnik restartu
# Zmienne tylko dla testow (narzedzia\test-aktualizacji.ps1): MR_AKT_TETNO_S (tetno stanu w s),
# MR_AKT_UPTIME_MIN (minuty od startu Windows zamiast odczytu), MR_AKT_MUTEX_INSTALATORA (nazwa zamka
# okna instalatora zamiast Local\MegaRuchacz-Instalator).
# Kod wyjscia: 0 aktualne albo zaktualizowano (gdy jest restart - konczy go pomocnik, wynik w pliku
# stanu, takze blad lore z naniesienia), 1 blad (powod w pliku stanu), 3 inny przebieg wlasnie aktualizuje.

# [CmdletBinding()]: nieznana flaga konczy sie bledem zamiast isc po cichu do $args. PULAPKA PS 5.1:
# z [CmdletBinding()] i -File $PSScriptRoot w wartosci domyslnej parametru jest pusty - dlatego
# domyslne $Zrodlo liczymy pod param() (jak instaluj-globalnie.ps1).
[CmdletBinding()]
param(
  [string]$Zrodlo = "",
  [string]$KatalogDomowy = $HOME,
  [switch]$Reczna,
  [string]$ZadanieNadzorcy = "MegaRuchaczNadzorca",
  [switch]$Restart,
  [string]$Zdarzenie = "",
  [string]$Commit = ""
)

$ErrorActionPreference = "Stop"
if (-not $Zrodlo) { $Zrodlo = Split-Path -Parent $PSScriptRoot }
$Zrodlo = $Zrodlo.TrimEnd('\')
$KatalogDomowy = $KatalogDomowy.TrimEnd('\')

# ------------------------------------------------------------------ limity czasu
# Kazdy z uzasadnieniem - limit "na oko" albo ucina zdrowy przebieg, albo nie chroni przed zwisem.
# Straznik -TylkoPobierz: do 120 s czeka na blokade pobierania (inny przebieg straznika), potem
# fetch 60 s + merge 60 s (drugi raz przy plikach roboczych) + kilkanascie komend gita po 30 s.
# Typowo kilka sekund; 600 s pokrywa najgorszy przypadek tamtych limitow.
$SEKUNDY_STRAZNIKA = 600
# Te same limity, ktorymi wola te skrypty instalator (modul-kierownik.ps1: instaluj-globalnie 300 s;
# wspolne.ps1 Po-Zmianie-Rejestru: wpisz-zasady i -Dopasuj po 180 s).
$SEKUNDY_GLOBALNIE = 300
$SEKUNDY_ZASAD = 180
# Skille: pierwszy klon zrodla skilli bywa duzy (skille.ps1 CZAS_KLON = 600 s) plus dwie przerwy
# przed ponowieniem (5 i 15 s) - 900 s. Po nim kod -1 i uwaga; codzienne sprawdzenie sprobuje znowu.
$SEKUNDY_SKILLI = 900
$PRZERWY_SKILLI = "5,15"
# Lokalne komendy gita (rev-parse) - ulamek sekundy; 30 s jak w trybie -Tlo straznika.
$SEKUNDY_GITA = 30
# Pomocnik restartu: start powershella przez WMI to ~1-2 s - 30 s zapasu na zajety komputer.
$SEKUNDY_NA_POMOCNIKA = 30
# Pomocnik czeka na blokade, ktora ten przebieg oddaje zaraz po jego sygnale - 120 s to zapas
# na zapis stanu i dziennika na wolnym dysku.
$SEKUNDY_NA_BLOKADE_POMOCNIKA = 120
# Stop-Process konczy proces od razu; 30 s na obciazony komputer.
$SEKUNDY_NA_ZAMKNIECIE = 30
# zainstaluj-zasobnik.ps1 czeka na nadzorce 6 s; zaraz po zalogowaniu Harmonogram bywa wolniejszy.
$SEKUNDY_NA_WSTANIE = 60
# Nowy proces nadzorcy ma tyle przezyc: nadzorca z bledem w kodzie konczy sie (kod 3, Odmowa-Nadzorcy)
# po ~1-2 s, drugi egzemplarz przy zajetym zamku jeszcze szybciej.
$SEKUNDY_ZYCIA = 5
# Dziennik: przy jednym przebiegu na godzine bez zmian to ~15 linii na przebieg, czyli kilka dni
# historii; po aktualizacji pelne wyjscie instalatora (~100 linii) zostaje na pewno do nastepnej.
$LINII_DZIENNIKA = 3000
# Pamiec rozmow (Lore), Doinstaluj-Lore. Programy (zaleznosci.ps1: uv i Node.js z wingeta albo paczki
# zip, Python przez uv) - przy dobrej sieci kilka minut, a winget potrafi stac kilkanascie; 1800 s
# to zapas. modul-lore.ps1 Instaluj pobiera biblioteki i model, razem ok. 770 MB: przy 10 Mb/s to
# ok. 10 min, przy ~1 Mb/s ok. 100 min - 5400 s (90 min) to pulap dla bardzo wolnej sieci; po nim
# cale drzewo procesow ubite (taskkill /T /F) i blad z powodem, nastepna proba za godzine.
$SEKUNDY_ZALEZNOSCI_LORE = 1800
$SEKUNDY_LORE = 5400
# Tetno: w dlugim kroku stan zapisuje sie co 30 s takze bez nowych linii - okno uznaje trwajaca
# aktualizacje za martwa po 20 min bez zapisu (stan-wersja.ps1 MINUT_BEZ_RUCHU_AKTUALIZACJI), wiec
# 30 s to 40 zapisow zapasu, a dla dysku jeden maly plik na pol minuty. Test skraca je (MR_AKT_TETNO_S).
$SEKUNDY_TETNA = 30
# Wyjscie dlugiego kroku doczytywane co 2 s: krok widac pod paskiem najwyzej 2 s pozniej, a petla
# prawie nie zajmuje procesora.
$SEKUNDY_ODCZYTU = 2
# Duze pobieranie najwczesniej 5 min po starcie albo wybudzeniu Windows - regula uzytkownika z 13.10
# (najpierw siec i logowanie, potem reszta), ta sama co dla terminow (zasobnik\nadzorca\stan-terminy.ps1).
# Przebieg przy starcie nadzorcy (~1 min po zalogowaniu) odklada wtedy Lore do nastepnego (za 60 min).
$MINUT_PO_STARCIE_WINDOWS = 5

$KROKOW = 4
$DomClaude      = Join-Path $KatalogDomowy ".claude"
$PlikStanu      = Join-Path $DomClaude "mr\aktualizacja.json"
$PlikNaniesione = Join-Path $DomClaude "mr\aktualizacja-naniesione.txt"
$PlikDziennika  = Join-Path $DomClaude "mr\aktualizacja.log"
$PlikZmian      = Join-Path $Zrodlo "ZMIANY.md"
$SkryptNadzorcy = Join-Path $Zrodlo "zasobnik\nadzorca.ps1"
$Bez            = New-Object System.Text.UTF8Encoding($false)

# Zapis odporny na zanik pradu (plik tymczasowy w tym samym katalogu + podmiana) - ten sam kod,
# ktorym pisza straznik i cykl. Bez niego (starsza kopia narzedzia) - podmiana zrobiona tutaj.
$plikZapisu = Join-Path $PSScriptRoot "zapis-trwaly.ps1"
if (Test-Path -LiteralPath $plikZapisu) { . $plikZapisu }

function Skrot([string]$t) {
  $md5 = [System.Security.Cryptography.MD5]::Create()
  try { return ([System.BitConverter]::ToString($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($t))).Replace("-", "")).Substring(0, 16) }
  finally { $md5.Dispose() }
}
# Blokada na katalog zrodlowy: dwa repo na jednej maszynie (np. kopia testowa) nie czekaja na siebie.
# test-aktualizacji.ps1 sklada te sama nazwe (proba negatywna blokady) - zmiana tutaj = zmiana tam.
$NazwaBlokady = "Local\MegaRuchacz-aktualizacja-" + (Skrot $Zrodlo.ToLower())

# ------------------------------------------------------------------ dziennik i stan

function Teraz { return (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss") }

# Dziennik nie ma prawa przerwac aktualizacji, ale jego awaria nie jest cisza: idzie na strumien
# bledow (proces w tle - przeczyta go test) i do stanu jako uwaga.
function Loguj([string]$tekst) {
  try {
    $kat = Split-Path -Parent $PlikDziennika
    if (-not (Test-Path -LiteralPath $kat)) { New-Item -ItemType Directory -Force -Path $kat | Out-Null }
    $stempel = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $linie = @(("" + $tekst) -split '\r?\n' | ForEach-Object { "$stempel [$PID] $_" })
    [System.IO.File]::AppendAllText($PlikDziennika, (($linie -join "`r`n") + "`r`n"), $Bez)
  } catch {
    [Console]::Error.WriteLine("aktualizacja: nie zapisalem dziennika $PlikDziennika - $($_.Exception.Message)")
    if ($script:Stan -and -not $script:BladDziennika) {
      $script:BladDziennika = $true
      $script:Stan.uwagi = @($script:Stan.uwagi) + "Dziennik aktualizacji nie zapisuje sie ($($_.Exception.Message))."
    }
  }
}

function Przytnij-Dziennik {
  try {
    if (-not (Test-Path -LiteralPath $PlikDziennika)) { return }
    $linie = [System.IO.File]::ReadAllLines($PlikDziennika, $Bez)
    if ($linie.Count -le [int]($LINII_DZIENNIKA * 1.2)) { return }
    $zostaje = @($linie | Select-Object -Last $LINII_DZIENNIKA)
    Zapisz-Plik $PlikDziennika (($zostaje -join "`r`n") + "`r`n")
  } catch { Loguj "nie przycialem dziennika: $($_.Exception.Message)" }
}

function Zapisz-Plik([string]$sciezka, [string]$tekst) {
  if (Get-Command Zapisz-Trwale -ErrorAction SilentlyContinue) { Zapisz-Trwale $sciezka $tekst $Bez; return }
  $kat = Split-Path -Parent $sciezka
  if (-not (Test-Path -LiteralPath $kat)) { New-Item -ItemType Directory -Force -Path $kat | Out-Null }
  $tmp = Join-Path $kat (".{0}.tmp-{1}" -f (Split-Path -Leaf $sciezka), $PID)
  [System.IO.File]::WriteAllText($tmp, $tekst, $Bez)
  if (Test-Path -LiteralPath $sciezka) { [System.IO.File]::Replace($tmp, $sciezka, [NullString]::Value, $true) }
  else { [System.IO.File]::Move($tmp, $sciezka) }
}

function Nowy-Stan {
  return [ordered]@{
    etap = ""; krok = 0; krokow = $KROKOW; opis = ""; wynik = ""
    wersja_przed = ""; wersja_po = ""; start = ""; koniec = ""; sprawdzone = ""
    powod = ""; reczna = [bool]$Reczna; przyczyna = ""; uwagi = @(); doinstalowano = @(); lore_blad = $null; zrodlo = $Zrodlo; pid = $PID
  }
}

# Poprzedni stan z pliku - $null, gdy go nie ma albo jest nieczytelny (wtedy slad w dzienniku).
function Czytaj-Stan {
  if (-not (Test-Path -LiteralPath $PlikStanu)) { return $null }
  try {
    $j = ([System.IO.File]::ReadAllText($PlikStanu, $Bez)).TrimStart([char]0xFEFF) | ConvertFrom-Json
    $s = Nowy-Stan
    foreach ($p in $j.PSObject.Properties) { $s[$p.Name] = $p.Value }
    $s.uwagi = @($s.uwagi | Where-Object { $_ })
    $s.doinstalowano = @($s.doinstalowano | Where-Object { $_ })
    return $s
  } catch {
    Loguj "poprzedni stan $PlikStanu jest nieczytelny ($($_.Exception.Message)) - zaczynam od pustego"
    return $null
  }
}

function Zapisz-Stan {
  $script:Stan.pid = $PID
  try { Zapisz-Plik $PlikStanu (($script:Stan | ConvertTo-Json -Depth 4) + "`r`n") }
  catch {
    # Bez stanu okno i alarm nadzorcy nie wiedza, co sie dzieje - glosno w dzienniku i na strumieniu
    # bledow; alarm "aktualizacja nie rusza" (stan-zbieranie.ps1) odezwie sie po swoim progu.
    Loguj "NIE ZAPISALEM STANU $PlikStanu - $($_.Exception.Message)"
    [Console]::Error.WriteLine("aktualizacja: nie zapisalem stanu $PlikStanu - $($_.Exception.Message)")
  }
}

function Etap([string]$etap, [int]$krok, [string]$opis) {
  $script:Stan.etap = $etap
  $script:Stan.krok = $krok
  $script:Stan.opis = $opis
  $script:Stan.wynik = ""
  Zapisz-Stan
  Loguj "etap ${etap} (${krok}/${KROKOW}): $opis"
}

function Uwaga([string]$tekst) {
  $script:Stan.uwagi = @($script:Stan.uwagi) + $tekst
  Loguj "UWAGA $tekst"
}

function Koniec([string]$wynik, [string]$opis) {
  $script:Stan.etap = "gotowe"
  $script:Stan.wynik = $wynik
  $script:Stan.opis = $opis
  $script:Stan.powod = ""
  $script:Stan.przyczyna = ""
  $script:Stan.koniec = Teraz
  Zapisz-Stan
  Loguj "KONIEC: $wynik - $opis"
}

function Blad([string]$przyczyna, [string]$powod) {
  $script:Stan.etap = "blad"
  $script:Stan.wynik = "blad"
  $script:Stan.opis = "Aktualizacja się nie udała"
  $script:Stan.przyczyna = $przyczyna
  $script:Stan.powod = ($powod -replace '[\r\n]+', ' ').Trim()
  $script:Stan.koniec = Teraz
  Zapisz-Stan
  Loguj "BLAD [$przyczyna] $powod"
}

# ------------------------------------------------------------------ procesy

function Cytuj-Argument([string]$a) {
  if ($a -eq "") { return '""' }
  if ($a -notmatch '[\s"]') { return $a }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  $ukosniki = 0
  foreach ($c in $a.ToCharArray()) {
    if ($c -eq '\') { $ukosniki++; continue }
    if ($c -eq '"') { [void]$sb.Append(('\' * ($ukosniki * 2 + 1)) + '"'); $ukosniki = 0; continue }
    if ($ukosniki) { [void]$sb.Append('\' * $ukosniki); $ukosniki = 0 }
    [void]$sb.Append($c)
  }
  if ($ukosniki) { [void]$sb.Append('\' * ($ukosniki * 2)) }
  [void]$sb.Append('"')
  return $sb.ToString()
}

# Wyjscie powershella przekierowane do pliku/potoku idzie w stronie kodowej OEM (852 dla polskiego
# Windows) - tym kodowaniem je czytamy, inaczej polskie litery z wyjscia skryptow wyszlyby krzakami.
function Kodowanie-Konsoli {
  try {
    $cp = [int](Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -ErrorAction Stop).OEMCP
    return [System.Text.Encoding]::GetEncoding($cp)
  } catch { return [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) }
}

# Program bez okna (CreateNoWindow), z limitem czasu i przechwyconym wyjsciem. Po limicie - cale
# drzewo procesow ubite (taskkill /T), zeby po skrypcie nie zostal wiszacy git. Kod -1 = nie zdazyl
# albo nie wstal; Tekst mowi wtedy dlaczego.
function Uruchom-Proces([string]$program, [string[]]$argumenty, [int]$sekundy, $kodowanie) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $program
  $psi.Arguments = (@($argumenty | ForEach-Object { Cytuj-Argument $_ })) -join " "
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = $kodowanie
  $psi.StandardErrorEncoding = $kodowanie
  if (Test-Path -LiteralPath $KatalogDomowy) { $psi.WorkingDirectory = $KatalogDomowy }
  try { $p = [System.Diagnostics.Process]::Start($psi) }
  catch { return [pscustomobject]@{ Kod = -1; Tekst = "nie udalo sie uruchomic ${program}: $($_.Exception.Message)" } }
  $wy = $p.StandardOutput.ReadToEndAsync()
  $bl = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($sekundy * 1000)) {
    & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null
    return [pscustomobject]@{ Kod = -1; Tekst = "$(Split-Path -Leaf $program) $($argumenty | Select-Object -First 1) nie skonczyl w $sekundy s - przerwany" }
  }
  $p.WaitForExit()
  return [pscustomobject]@{ Kod = $p.ExitCode; Tekst = ($wy.Result + "`n" + $bl.Result).Trim() }
}

function Uruchom-Skrypt([string]$skrypt, [string[]]$argumenty, [int]$sekundy) {
  if (-not (Test-Path -LiteralPath $skrypt)) { return [pscustomobject]@{ Kod = -1; Tekst = "nie ma pliku $skrypt" } }
  $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
  return (Uruchom-Proces $ps (@("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $skrypt) + $argumenty) $sekundy (Kodowanie-Konsoli))
}

function Wolaj-I-Loguj([string]$co, [string]$skrypt, [string[]]$argumenty, [int]$sekundy) {
  Loguj "wolam ${co}: $skrypt $($argumenty -join ' ')"
  $w = Uruchom-Skrypt $skrypt $argumenty $sekundy
  Loguj ("${co} - kod $($w.Kod):`n" + $w.Tekst)
  return $w
}

# Sedno wyjscia skryptu do jednego zdania: linie BLAD/UWAGA, a bez nich ostatnia linia.
function Sedno([string]$tekst) {
  $l = @(("" + $tekst) -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $wazne = @($l | Where-Object { $_ -match '^(BLAD|BŁĄD|UWAGA|Write-Error|.*NIEPELNA)' -or $_ -match 'nie udalo|nie da sie' } | Select-Object -First 2)
  $s = if ($wazne.Count -gt 0) { $wazne -join " " } elseif ($l.Count -gt 0) { $l[-1] } else { "bez slowa wyjasnienia" }
  if ($s.Length -gt 300) { $s = $s.Substring(0, 300) + "..." }
  return $s
}

function Git-Tekst([string[]]$argumenty) {
  $w = Uruchom-Proces "git" (@("-C", $Zrodlo) + $argumenty) $SEKUNDY_GITA $Bez
  if ($w.Kod -ne 0) { Loguj "git $($argumenty -join ' ') - kod $($w.Kod): $($w.Tekst)"; return "" }
  return $w.Tekst.Trim()
}

# ------------------------------------------------------------------ wersje i znaczniki

# TA SAMA regula, co Wersja-Narzedzia w straznik-zasad.ps1 i stan-wersja.ps1 (najwyzszy "## X.Y.Z").
function Wersja-Narzedzia {
  if (-not (Test-Path -LiteralPath $PlikZmian)) { return "" }
  $naj = $null
  foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($PlikZmian), '(?m)^##\s+(\d+)\.(\d+)\.(\d+)')) {
    $w = [version]("{0}.{1}.{2}" -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value)
    if ($null -eq $naj -or $w -gt $naj) { $naj = $w }
  }
  if ($null -eq $naj) { return "" }
  return $naj.ToString()
}

function Czytaj-Klucze([string]$sciezka) {
  $stan = [ordered]@{}
  if (-not (Test-Path -LiteralPath $sciezka)) { return $stan }
  foreach ($l in [System.IO.File]::ReadAllLines($sciezka, $Bez)) {
    $m = [regex]::Match($l, '^\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*:\s*(.*?)\s*$')
    if ($m.Success) { $stan[$m.Groups[1].Value] = $m.Groups[2].Value }
  }
  return $stan
}

function Zapisz-Klucze([string]$sciezka, $stan) {
  $linie = @()
  foreach ($k in $stan.Keys) { $linie += ("{0}: {1}" -f $k, $stan[$k]) }
  Zapisz-Plik $sciezka (($linie -join "`r`n") + "`r`n")
}

# Znacznik naniesienia - tylko dla TEGO katalogu zrodlowego (inny katalog = jakby go nie bylo).
function Znacznik-Naniesienia {
  $z = Czytaj-Klucze $PlikNaniesione
  if ($z["zrodlo"] -and ($z["zrodlo"].TrimEnd('\') -ne $Zrodlo)) { return [ordered]@{} }
  return $z
}

function Odnotuj-Znacznik($nowe) {
  $z = Znacznik-Naniesienia
  $z["zrodlo"] = $Zrodlo
  foreach ($k in $nowe.Keys) { $z[$k] = $nowe[$k] }
  Zapisz-Klucze $PlikNaniesione $z
  Loguj ("znacznik naniesienia: " + (@($nowe.Keys | ForEach-Object { "$_ = $($nowe[$_])" }) -join "; "))
}

# Rejestr instalacji przez umowe narzedzia\instalacja\stan.ps1 (ta sama, co straznik i nadzorca).
# Starsza kopia bez umowy = wszystko wlaczone, jak u straznika.
function Rejestr {
  $plik = Join-Path $Zrodlo "narzedzia\instalacja\stan.ps1"
  if (-not (Test-Path -LiteralPath $plik)) {
    return [pscustomobject]@{ moduly = [pscustomobject]@{ wiedza = $true; lore = $true; kierownik = $true; skille = $true; kopia = $false }
                              narzedzia = $null; baza = $true; blad = $null }
  }
  . $plik
  return (Czytaj-Instalacje $KatalogDomowy)
}
function Modul-Wl($rej, [string]$nazwa) {
  $v = $rej.moduly.$nazwa
  return (($null -eq $v) -or [bool]$v)
}

# "Claude Code, Codeksa i OpenCode" - narzedzia AI, ktore tu sa (lista z kierownik-cele.ps1), do opisu.
function Nazwy-Narzedzi {
  $odmiana = @{ claude = "Claude Code"; codex = "Codeksa"; opencode = "OpenCode" }
  $ids = @()
  try {
    . (Join-Path $Zrodlo "narzedzia\kierownik-cele.ps1")
    $ids = @(Cele-Narzedzi $KatalogDomowy | ForEach-Object { $_.Id })
  } catch { Loguj "nie ustalilem listy narzedzi AI do opisu: $($_.Exception.Message)" }
  $n = @($ids | ForEach-Object { if ($odmiana.ContainsKey($_)) { $odmiana[$_] } else { $_ } })
  if ($n.Count -eq 0) { return "narzędzi AI" }
  if ($n.Count -eq 1) { return $n[0] }
  return ((@($n | Select-Object -First ($n.Count - 1)) -join ", ") + " i " + $n[-1])
}

# ------------------------------------------------------------------ krok 1-2: pobranie

# Wynik straznika po ludzku. Jego zdania sa juz konkretne (pliki, co zrobic) - dokladamy to, czego
# czlowiek potrzebuje na wierzchu: czy cos trzeba zrobic i kiedy bedzie nastepna proba.
function Powod-Ludzki([string]$wynik, [string]$powod) {
  $p = ($powod -replace '^\s*MegaRuchacz:\s*', '').Trim()
  switch ($wynik) {
    "bez-sieci"   { return "Nie udało się połączyć z serwerem z nowymi wersjami (brak internetu albo dostępu). Spróbuję znowu za godzinę - nic nie trzeba robić, chyba że trwa to ponad dobę. Szczegóły: $p" }
    "zajete"      { return "Inny przebieg właśnie pobierał nową wersję. Spróbuję znowu za godzinę - nic nie trzeba robić. Szczegóły: $p" }
    "zablokowane" { return "Nowej wersji nie pobrałem, bo nadpisałaby zmiany zrobione na tym komputerze w katalogu MegaRuchacza. Szczegóły: $p" }
    "rozjechane"  { return "Katalog MegaRuchacza na tym komputerze ma własne zmiany, których nie ma na serwerze - nie scalam ich sam. Szczegóły: $p" }
    "nieudane"    { return "Nie udało się pobrać nowej wersji. Spróbuję znowu za godzinę; jeśli to się powtarza, przekaż ten opis. Szczegóły: $p" }
    "kopia"       { return "Pobieranie nowych wersji wstrzymane do ręcznego porządku z kopią plików roboczych. Szczegóły: $p" }
    { @("bez-zdalnej", "nie-repo", "bez-gita") -contains $_ } { return "Ten katalog MegaRuchacza nie ma skąd pobierać nowych wersji, więc aktualizacje nie przyjdą same. Szczegóły: $p" }
  }
  return $p
}

# Wynik straznika z jego wyjscia (-TylkoPobierz), a gdy tam go nie ma - z jego pliku stanu, ale tylko
# z TEJ proby (aktualizacja.kiedy nie starsze niz start) - cudzy, stary wynik nie moze udawac naszego.
function Wynik-Straznika($r, [datetime]$od) {
  $w = [pscustomobject]@{ wynik = ""; powod = "" }
  foreach ($l in (("" + $r.Tekst) -split '\r?\n')) {
    if ($l -match '^aktualizacja\.wynik:\s*(.*)$') { $w.wynik = $Matches[1].Trim() }
    elseif ($l -match '^aktualizacja\.powod:\s*(.*)$') { $w.powod = $Matches[1].Trim() }
  }
  if ($w.wynik) { return $w }
  $s = Czytaj-Klucze (Join-Path $DomClaude ".megaruchacz-straznik.txt")
  $kiedy = [datetime]::MinValue
  if ($s["aktualizacja.wynik"] -and [datetime]::TryParse($s["aktualizacja.kiedy"], [ref]$kiedy) -and ($kiedy -ge $od.AddSeconds(-1))) {
    $w.wynik = $s["aktualizacja.wynik"]; $w.powod = $s["aktualizacja.powod"]
    Loguj "wynik straznika wziety z jego pliku stanu (na wyjsciu go nie bylo)"
  }
  return $w
}

# ------------------------------------------------------------------ krok 3: Pamiec rozmow (Lore)

# Czy na tym komputerze brakuje Pamieci rozmow (Lore) - obowiazkowej od 2026-10-17. TEN SAM predykat,
# co Powod-Braku-Lore w straznik-zasad.ps1 (zmiana tu = zmiana tam). $null = nie brakuje albo niczego
# nie twierdzimy: rejestr nieczytelny (ma wlasny alarm), MegaRuchacz odinstalowany ("baza": false -
# nic nie wraca samo), zrodlo bez lore\pyproject.toml (okrojona kopia - nie ma czego instalowac).
# Inaczej powod jednym zdaniem. Flaga lore w rejestrze znaczy "zainstalowane i dziala" - ustawia ja
# tylko udany modul-lore Instaluj.
function Lore-Brakuje($rej) {
  if ((-not $rej) -or $rej.blad -or ($rej.baza -eq $false)) { return $null }
  if (-not (Test-Path -LiteralPath (Join-Path $Zrodlo "lore\pyproject.toml"))) { return $null }
  if ($rej.moduly.lore -ne $true) { return "rejestr modułów nie ma jej jako zainstalowanej" }
  $py = Join-Path $Zrodlo "lore\.venv\Scripts\python.exe"
  if (-not (Test-Path -LiteralPath $py)) { return "nie ma jej środowiska Pythona ($py)" }
  return $null
}

# Ile minut temu wystartowal albo wybudzil sie Windows. TA SAMA regula, co Start-Systemu w
# zasobnik\nadzorca\stan-terminy.ps1 (zmiana tam = zmiana tu): najnowsze z dziennika zdarzen System -
# Kernel-Boot 27 (kazdy rozruch, takze "szybkie uruchamianie", ktore nie zmienia LastBootUpTime),
# Power-Troubleshooter 1 (wybudzenie ze snu i hibernacji), Kernel-Power 507 (wyjscie z nowoczesnego
# czuwania); bez nich LastBootUpTime. MR_AKT_UPTIME_MIN podstawia wynik w testach. Minut $null = nie wiadomo.
function Minut-Od-Startu-Windows {
  $w = [pscustomobject]@{ Minut = $null; Skad = "" }
  $test = "$env:MR_AKT_UPTIME_MIN".Trim()
  if ($test) {
    $n = 0.0
    if ([double]::TryParse($test, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)) {
      $w.Minut = $n; $w.Skad = "MR_AKT_UPTIME_MIN (test)"; return $w
    }
    Loguj "MR_AKT_UPTIME_MIN='$test' to nie liczba - licze start Windows naprawde"
  }
  $bledy = @()
  $x = "*[System[(Provider[@Name='Microsoft-Windows-Kernel-Boot'] and EventID=27) or " +
    "(Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1) or " +
    "(Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=507)]]"
  try {
    $e = @(Get-WinEvent -LogName System -FilterXPath $x -MaxEvents 1 -ErrorAction Stop)[0]
    $w.Minut = ((Get-Date) - $e.TimeCreated).TotalMinutes
    $w.Skad = "dziennik zdarzen: $($e.ProviderName) $($e.Id)"
  } catch {
    # Brak pasujacych zdarzen to nie usterka - wtedy rozstrzyga LastBootUpTime.
    if ("$($_.FullyQualifiedErrorId)" -notlike "NoMatchingEventsFound*") { $bledy += "dziennik zdarzen: $($_.Exception.Message)" }
  }
  if ($null -eq $w.Minut) {
    try {
      $b = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
      if (-not $b) { throw "pusty LastBootUpTime" }
      $w.Minut = ((Get-Date) - $b).TotalMinutes
      $w.Skad = "Win32_OperatingSystem.LastBootUpTime"
    } catch { $bledy += "LastBootUpTime: $($_.Exception.Message)" }
  }
  # Start "w przyszlosci" (przestawiony zegar) to tez "nie wiadomo" - inaczej odkladalby bez konca.
  if (($null -ne $w.Minut) -and ($w.Minut -lt 0)) { $bledy += "start Windows wypada w przyszlosci ($($w.Skad))"; $w.Minut = $null }
  if ($bledy.Count -gt 0) { $w.Skad = (@($w.Skad) + $bledy | Where-Object { $_ }) -join "; " }
  return $w
}

# Bramki odroczenia doinstalowania - nie bledy, tylko "jeszcze nie teraz" (uwaga w stanie i dziennik):
#  - otwarte okno instalatora (jego zamek jednej kopii, instalator\okno.ps1): ono samo instaluje Lore,
#    a nowa instalacja startuje nadzorce PRZED krokiem Lore, kiedy rejestr ma jeszcze lore=false - bez
#    tej bramki aktualizacja ruszylaby drugi modul-lore Instaluj na tym samym srodowisku i bazie;
#  - $MINUT_PO_STARCIE_WINDOWS min po starcie albo wybudzeniu Windows (regula uzytkownika).
# Zwraca $null albo obiekt: Przyczyna ("lore-zajete" przy oknie instalatora, "" po swiezym starcie), Powod.
function Odroczenie-Lore {
  $zamek = "Local\MegaRuchacz-Instalator"
  if ($env:MR_AKT_MUTEX_INSTALATORA) { $zamek = $env:MR_AKT_MUTEX_INSTALATORA }
  $otwarte = $false
  $m = $null
  try { $otwarte = [System.Threading.Mutex]::TryOpenExisting($zamek, [ref]$m) }
  catch {
    # Zamek jest, ale nie wolno go otworzyc (np. okno uruchomione jako administrator) - okno jest otwarte.
    Loguj "zamek okna instalatora $zamek jest, ale nie da sie go otworzyc ($($_.Exception.Message)) - uznaje okno za otwarte"
    $otwarte = $true
  } finally { if ($m) { $m.Dispose() } }
  if ($otwarte) {
    Loguj "otwarte okno instalatora ($zamek) - Lore instaluje ono, aktualizacja go nie rusza"
    return [pscustomobject]@{ Przyczyna = "lore-zajete"
      Powod = "Pamięć rozmów (Lore) instaluje właśnie inny proces (okno instalatora) - sprawdzę za godzinę." }
  }
  $s = Minut-Od-Startu-Windows
  if ($null -eq $s.Minut) { Loguj "nie wiem, kiedy wystartowal Windows ($($s.Skad)) - Lore nie odkladam"; return $null }
  $min = [int][math]::Floor($s.Minut)
  Loguj "start Windows: $min min temu ($($s.Skad))"
  if ($s.Minut -lt $MINUT_PO_STARCIE_WINDOWS) {
    return [pscustomobject]@{ Przyczyna = ""
      Powod = "Brakuje Pamięci rozmów (Lore) - doinstaluję ją przy następnej aktualizacji (za godzinę): Windows wystartował $min min temu, a duże pobieranie rusza najwcześniej $MINUT_PO_STARCIE_WINDOWS min po starcie." }
  }
  return $null
}

$script:Utf8Scisly = New-Object System.Text.UTF8Encoding($false, $true)

# Linia z wyjscia skryptu modulu: UTF-8 (wspolne.ps1 przestawia na nie wyjscie), a gdy to nie jest
# poprawny UTF-8 - strona kodowa konsoli (jak w instalator\wykonanie.ps1).
function Dekoduj-Linie([byte[]]$b) {
  if (($null -eq $b) -or ($b.Length -eq 0)) { return "" }
  $n = $b.Length
  if ($b[$n - 1] -eq 13) { $n-- }
  $t = ""
  try { $t = $script:Utf8Scisly.GetString($b, 0, $n) } catch { $t = (Kodowanie-Konsoli).GetString($b, 0, $n) }
  return $t.TrimStart([char]0xFEFF)
}

# Doczytanie tego, co proces dopisal do pliku wyjscia od ostatniego razu (plik otwarty z FileShare -
# proces dalej do niego pisze). Niepelna ostatnia linia czeka w buforze, a na koncu ($doKonca) idzie
# jak jest. Zwraca nowe pelne linie.
function Czytaj-Przyrost([string]$plik, $czytnik, [bool]$doKonca) {
  $linie = @()
  if (Test-Path -LiteralPath $plik) {
    $fs = $null
    try {
      $fs = [System.IO.File]::Open($plik, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
      if ($fs.Length -gt $czytnik.Pozycja) {
        [void]$fs.Seek($czytnik.Pozycja, [System.IO.SeekOrigin]::Begin)
        $buf = New-Object byte[] ([int]($fs.Length - $czytnik.Pozycja))
        $ile = $fs.Read($buf, 0, $buf.Length)
        $czytnik.Pozycja += $ile
        $od = 0
        while ($od -lt $ile) {
          $nl = [Array]::IndexOf($buf, [byte]10, $od, $ile - $od)
          if ($nl -lt 0) { break }
          for ($i = $od; $i -lt $nl; $i++) { $czytnik.Bufor.Add($buf[$i]) }
          $linie += Dekoduj-Linie $czytnik.Bufor.ToArray()
          $czytnik.Bufor.Clear()
          $od = $nl + 1
        }
        for ($i = $od; $i -lt $ile; $i++) { $czytnik.Bufor.Add($buf[$i]) }
      }
    } catch {
      if (-not $czytnik.BladOdczytu) { $czytnik.BladOdczytu = $true; Loguj "nie doczytalem wyjscia z ${plik}: $($_.Exception.Message)" }
    } finally { if ($fs) { $fs.Dispose() } }
  }
  if ($doKonca -and ($czytnik.Bufor.Count -gt 0)) { $linie += Dekoduj-Linie $czytnik.Bufor.ToArray(); $czytnik.Bufor.Clear() }
  foreach ($l in $linie) { [void]$czytnik.Linie.Add($l) }
  return ,$linie
}

# Calosc pliku, ktory moze trzymac jeszcze inny proces (wyjscie bledow dlugiego kroku).
function Czytaj-Caly([string]$plik) {
  if (-not (Test-Path -LiteralPath $plik)) { return "" }
  $fs = [System.IO.File]::Open($plik, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
  try {
    $buf = New-Object byte[] ([int]$fs.Length)
    $ile = $fs.Read($buf, 0, $buf.Length)
    $t = ""
    try { $t = $script:Utf8Scisly.GetString($buf, 0, $ile) } catch { $t = (Kodowanie-Konsoli).GetString($buf, 0, $ile) }
    return $t.TrimStart([char]0xFEFF).Trim()
  } finally { $fs.Dispose() }
}

# Opis pod paskiem w czasie doinstalowania: ostatnia linia KROK skryptu i ile to juz trwa (od poczatku
# Doinstaluj-Lore, zaokraglone w gore - "trwa 1 min" w pierwszej minucie). Bez linii KROK - opis kroku.
function Opis-Lore {
  if (-not $script:LoreKrok) { return $script:LoreOpisKroku }
  $min = [int][math]::Max(1, [math]::Ceiling(((Get-Date) - $script:LoreOd).TotalMinutes))
  return "Doinstalowuję Pamięć rozmów (Lore): $($script:LoreKrok) (trwa $min min)"
}

# Dlugi krok (doinstalowanie Lore): skrypt z umowa wyjscia (naglowek narzedzia\instalacja\wspolne.ps1:
# linie KROK/UWAGA, na koncu WYNIK {json}) w procesie bez okna, z wyjsciem do PLIKU, a nie do rur jak
# Uruchom-Proces. modul-lore puszcza w tle pierwsze czytanie rozmow (Lore-Indeksuj-W-Tle), a proces
# w tle dziedziczy uchwyty rodzica - przy rurach odczyt "do konca" czekalby na koniec indeksowania,
# a z plikiem czekamy tylko na sam skrypt (jak instalator\wykonanie.ps1). Pliki maja stale nazwy
# w ~\.claude\mr (aktualizacja-<co>.wyjscie.txt / .bledy.txt), nadpisywane co przebieg: skasowac ich
# sie nie da, dopoki trzyma je proces w tle, a stale nazwy nie zostawiaja smieci w TEMP.
# Co $SEKUNDY_ODCZYTU s doczytuje przyrost; kazda linia KROK idzie do opisu pod paskiem, a gdy nic nie
# przychodzi, stan i tak zapisuje sie co $SEKUNDY_TETNA (tetno - okno nie uzna aktualizacji za martwa).
# Po $sekundy - cale drzewo procesow ubite. Zwraca: Ok (kod 0 i ok:true w WYNIK - jak w instalatorze,
# sukces "na slowo" sie nie liczy), Kod, Wynik, Zajete, Uwagi, Sedno (zdanie do powodu bledu).
function Uruchom-Dlugi([string]$co, [string]$skrypt, [string[]]$argumenty, [int]$sekundy) {
  $w = [pscustomobject]@{ Ok = $false; Kod = -1; Wynik = $null; Zajete = $false; Uwagi = @(); Sedno = "" }
  $script:LoreKrok = ""
  $script:LoreOpisKroku = $script:Stan.opis
  if (-not (Test-Path -LiteralPath $skrypt)) { $w.Sedno = "nie ma pliku $skrypt"; Loguj "${co}: $($w.Sedno)"; return $w }
  $tetno = $SEKUNDY_TETNA
  $n = 0
  if ($env:MR_AKT_TETNO_S) {
    if ([int]::TryParse("$env:MR_AKT_TETNO_S", [ref]$n) -and ($n -gt 0)) { $tetno = $n; Loguj "tetno stanu co $tetno s (MR_AKT_TETNO_S - test)" }
    else { Loguj "MR_AKT_TETNO_S='$env:MR_AKT_TETNO_S' to nie liczba dodatnia - tetno co $tetno s" }
  }
  $plikWy = Join-Path $DomClaude "mr\aktualizacja-$co.wyjscie.txt"
  $plikBl = Join-Path $DomClaude "mr\aktualizacja-$co.bledy.txt"
  $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
  $linia = (@(@("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", $skrypt) + $argumenty) | ForEach-Object { Cytuj-Argument $_ }) -join " "
  Loguj "wolam ${co} (limit $sekundy s, wyjscie do $plikWy): $skrypt $($argumenty -join ' ')"
  $p = $null
  try {
    $kat = Split-Path -Parent $plikWy
    if (-not (Test-Path -LiteralPath $kat)) { New-Item -ItemType Directory -Force -Path $kat | Out-Null }
    $sp = @{ FilePath = $ps; ArgumentList = $linia; NoNewWindow = $true; PassThru = $true
             RedirectStandardOutput = $plikWy; RedirectStandardError = $plikBl; ErrorAction = "Stop" }
    if (Test-Path -LiteralPath $KatalogDomowy) { $sp.WorkingDirectory = $KatalogDomowy }
    # -NoNewWindow: dziecko dzieli niewidoczna konsole tego procesu (conhost --headless albo
    # CreateNoWindow) - zadnego okna.
    $p = Start-Process @sp
    $null = $p.Handle   # bez dotkniecia uchwytu ExitCode zostaje pusty po zakonczeniu (jak w instalatorze)
  } catch {
    $w.Sedno = "nie udało się uruchomić ${co}: $($_.Exception.Message)"
    Loguj $w.Sedno
    return $w
  }
  $czytnik = [pscustomobject]@{ Pozycja = [long]0; Bufor = New-Object System.Collections.Generic.List[byte]
                                Linie = New-Object System.Collections.ArrayList; BladOdczytu = $false }
  $t0 = Get-Date
  $ostatniZapis = $t0
  $przerwany = $false
  while ($true) {
    $skonczyl = $p.WaitForExit($SEKUNDY_ODCZYTU * 1000)
    $nowe = Czytaj-Przyrost $plikWy $czytnik $skonczyl
    $krok = $false
    foreach ($l in $nowe) { if ($l -match '^\s*KROK:\s*(.+)$') { $script:LoreKrok = $Matches[1].Trim(); $krok = $true } }
    if ($krok -or (((Get-Date) - $ostatniZapis).TotalSeconds -ge $tetno)) {
      $script:Stan.opis = Opis-Lore
      Zapisz-Stan
      $ostatniZapis = Get-Date
    }
    if ($skonczyl) { break }
    if (((Get-Date) - $t0).TotalSeconds -ge $sekundy) {
      Loguj "${co} nie skonczyl w $sekundy s - ubijam drzewo procesow (PID $($p.Id))"
      & taskkill.exe /T /F /PID $p.Id 2>&1 | Out-Null
      [void]$p.WaitForExit(15000)
      [void](Czytaj-Przyrost $plikWy $czytnik $true)
      $przerwany = $true
      break
    }
  }
  $bledy = ""
  try { $bledy = Czytaj-Caly $plikBl } catch { Loguj "nie odczytalem wyjscia bledow ${co}: $($_.Exception.Message)" }
  $kod = $null
  if (-not $przerwany) {
    try { $kod = $p.ExitCode } catch { Loguj "kod wyjscia ${co} nieznany: $($_.Exception.Message)" }
  }
  $p.Dispose()
  Loguj ("${co} - kod $(if ($przerwany) { 'przerwany' } else { $kod }):`n" + (@($czytnik.Linie) -join "`n") + $(if ($bledy) { "`n[bledy] $bledy" } else { "" }))
  if ($przerwany) {
    $w.Sedno = "przerwane po $([int][math]::Round($sekundy / 60)) min - nie skończyło w tym czasie$(if ($script:LoreKrok) { " (ostatni krok: $($script:LoreKrok))" })"
    return $w
  }
  if ($null -ne $kod) { $w.Kod = $kod }
  $wyn = $null
  $ost = @($czytnik.Linie | Where-Object { $_ -match '^\s*WYNIK:' } | Select-Object -Last 1)
  if ($ost.Count -gt 0) {
    try { $wyn = ($ost[0] -replace '^\s*WYNIK:\s*', '') | ConvertFrom-Json }
    catch { $w.Sedno = "oddał wynik, którego nie umiem odczytać ($($_.Exception.Message))"; return $w }
  }
  if (-not $wyn) {
    $w.Sedno = "skończył bez wyniku (kod $kod): $(Sedno ((@($czytnik.Linie) -join "`n") + "`n" + $bledy))"
    return $w
  }
  $w.Wynik = $wyn
  $w.Uwagi = @($wyn.uwagi | Where-Object { $_ })
  $w.Zajete = ($wyn.zajete -eq $true)
  $kom = "$($wyn.komunikat)".Trim()
  if (($wyn.ok -eq $true) -and ($kod -eq 0)) { $w.Ok = $true; $w.Sedno = $kom; return $w }
  if ($wyn.ok -eq $true) { $w.Sedno = "napisał, że się udało, ale zakończył się kodem $kod - nie traktuję tego jako sukces ($kom)"; return $w }
  if (-not $kom) { $kom = "bez opisu (kod $kod)" }
  $w.Sedno = $kom
  return $w
}

# Doinstalowanie Pamieci rozmow (Lore). Te same skrypty i ta sama kolejnosc, co w oknie instalatora:
# programy (zaleznosci.ps1 - JEDEN napis "uv,python,node": -File podaje go do [string[]] w calosci,
# a skrypt dzieli go sam), potem modul-lore.ps1 Instaluj (srodowisko, model, MCP w narzedziach AI,
# zadanie indeksu, hooki i zasady wedlug rejestru, pierwsze czytanie rozmow w tle). $poNowejWersji
# tylko do zdania o bledzie. Zwraca $null (doinstalowana) albo porazke: Przyczyna (lore albo
# lore-zajete) i Powod. Bledu nie pisze: samo doinstalowanie konczy nim przebieg od razu, a przy
# naniesieniu nowej wersji porazka czeka do konca przebiegu (Nanies, Koniec-Naniesienia).
# Ponowna proba po nowej wersji: pierwszy przebieg rusza nowy nadzorca ok. minuty po restarcie.
function Doinstaluj-Lore([bool]$poNowejWersji) {
  $script:LoreOd = Get-Date
  $zdanie = $(if ($poNowejWersji) { "Nowa wersja $($script:Stan.wersja_po) jest wgrana, ale nie udało się doinstalować Pamięci rozmów (Lore)" } else { "Nie udało się doinstalować Pamięci rozmów (Lore)" })
  $ponowie = $(if ($poNowejWersji) { "Jest obowiązkowa, więc spróbuję znowu za kilka minut, a potem co godzinę." } else { "Jest obowiązkowa, więc spróbuję znowu za godzinę." })
  Etap "nanosze" 3 "Doinstalowuję Pamięć rozmów (Lore) - sprawdzam programy (uv, Python, Node.js)"
  $w = Uruchom-Dlugi "zaleznosci-lore" (Join-Path $Zrodlo "narzedzia\instalacja\zaleznosci.ps1") @("-Akcja", "Instaluj", "-Potrzebne", "uv,python,node") $SEKUNDY_ZALEZNOSCI_LORE
  foreach ($u in $w.Uwagi) { Uwaga "Pamięć rozmów (Lore), programy: $u" }
  if (-not $w.Ok) {
    return [pscustomobject]@{ Przyczyna = "lore"
      Powod = "${zdanie}: nie stanęły programy, których potrzebuje (uv, Python, Node.js) - $($w.Sedno.TrimEnd('.', ' ')). $ponowie" }
  }
  Etap "nanosze" 3 "Doinstalowuję Pamięć rozmów (Lore) - pobieram biblioteki i model do wyszukiwania (ok. 770 MB); to potrwa kilkanaście minut, możesz normalnie pracować"
  $w = Uruchom-Dlugi "lore" (Join-Path $Zrodlo "narzedzia\instalacja\modul-lore.ps1") @("-Akcja", "Instaluj", "-KatalogDomowy", $KatalogDomowy, "-Zrodlo", $Zrodlo) $SEKUNDY_LORE
  foreach ($u in $w.Uwagi) { Uwaga "Pamięć rozmów (Lore): $u" }
  if ($w.Zajete) {
    return [pscustomobject]@{ Przyczyna = "lore-zajete"
      Powod = "Pamięć rozmów (Lore) instaluje właśnie inny proces - sprawdzę za godzinę. Szczegóły: $($w.Sedno)" }
  }
  if (-not $w.Ok) {
    return [pscustomobject]@{ Przyczyna = "lore"; Powod = "${zdanie}: $($w.Sedno.TrimEnd('.', ' ')). $ponowie" }
  }
  $script:Stan.doinstalowano = @("lore")
  Loguj "Pamiec rozmow (Lore) doinstalowana: $($w.Sedno)"
  return $null
}

# ------------------------------------------------------------------ krok 3: naniesienie

function Nanies($rej, [string]$narz, [bool]$doLore = $false) {
  if ($rej.blad) { Uwaga "Rejestr zainstalowanych modułów jest nieczytelny ($($rej.blad)) - nanoszę jak przy pełnej instalacji." }

  # Kierownik - tylko przy instalacji globalnej (znacznik .megaruchacz-global). Bez niego tryb
  # kierownika jest wdrozony per projekt (wdroz.ps1), a instaluj-globalnie przestawilby maszyne na
  # instalacje globalna - tego nikt nie wybral. Wdrozenia w projektach nanosi straznik przy starcie sesji.
  $znacznikGlobalny = Join-Path $DomClaude ".megaruchacz-global"
  if (Modul-Wl $rej "kierownik") {
    if (Test-Path -LiteralPath $znacznikGlobalny) {
      Etap "nanosze" 3 "Wgrywam zasady kierownika i role do $narz"
      $a = @("-Zrodlo", $Zrodlo, "-KatalogDomowy", $KatalogDomowy, "-BezPytania")
      if ($rej.narzedzia -and $rej.narzedzia.codex) { $a += "-Codex" }
      $w = Wolaj-I-Loguj "instaluj-globalnie" (Join-Path $Zrodlo "narzedzia\instaluj-globalnie.ps1") $a $SEKUNDY_GLOBALNIE
      if ($w.Kod -ne 0) {
        Blad "nanoszenie" ("Nowa wersja jest pobrana, ale nie udało się wgrać jej do $narz (instalacja globalna, kod $($w.Kod): $(Sedno $w.Tekst)). " +
                           "Spróbuję znowu za godzinę; jeśli to się powtarza, kliknij `„Zmień instalację`” na dole okna MegaRuchacza i zapisz wybór jeszcze raz.")
        return $false
      }
    } else {
      Loguj "kierownik bez instalacji globalnej (nie ma $znacznikGlobalny) - instaluj-globalnie pomijam; wdrozenia w projektach naniesie straznik przy starcie sesji"
    }
  }

  Etap "nanosze" 3 "Odświeżam zasady pamięci w $narz"
  $w = Wolaj-I-Loguj "wpisz-zasady" (Join-Path $Zrodlo "narzedzia\wpisz-zasady.ps1") @("-Zrodlo", $Zrodlo, "-KatalogDomowy", $KatalogDomowy) $SEKUNDY_ZASAD
  if ($w.Kod -ne 0) {
    Blad "nanoszenie" ("Nowa wersja jest pobrana, ale zasady pamięci w $narz nie zostały odświeżone (kod $($w.Kod): $(Sedno $w.Tekst)). " +
                       "Spróbuję znowu za godzinę; pliki zasad zostały takie, jakie były.")
    return $false
  }

  Etap "nanosze" 3 "Dopasowuję hooki i bloki zasad do wybranych modułów"
  $w = Wolaj-I-Loguj "straznik -Dopasuj" (Join-Path $Zrodlo "narzedzia\straznik-zasad.ps1") @("-Dopasuj", "-Zrodlo", $Zrodlo, "-KatalogDomowy", $KatalogDomowy) $SEKUNDY_ZASAD
  if ($w.Kod -ne 0) {
    Blad "nanoszenie" ("Nowa wersja jest pobrana, ale hooki albo bloki zasad nie zostały dopasowane (kod $($w.Kod): $(Sedno $w.Tekst)). " +
                       "Spróbuję znowu za godzinę; jeśli to się powtarza, kliknij `„Zmień instalację`” na dole okna MegaRuchacza.")
    return $false
  }

  # Brakujaca Pamiec rozmow (Lore) - PO dopasowaniu hookow i zasad do rejestru (modul-lore po udanej
  # instalacji sam uklada je jeszcze raz, juz z Lore), PRZED skillami. Porazka NIE przerywa naniesienia
  # (naglowek: nowsza wersja zawsze wygrywa) - skille, znacznik i restart ida dalej, a porazka czeka
  # w stanie (lore_blad) na koniec przebiegu: Koniec-Naniesienia robi z niej blad zamiast "zaktualizowano".
  if ($doLore) {
    $p = Doinstaluj-Lore $true
    if ($p) {
      $script:Stan.lore_blad = [ordered]@{ przyczyna = $p.Przyczyna; powod = $p.Powod }
      Loguj "BLAD [$($p.Przyczyna)] odlozony na koniec przebiegu - nowa wersja idzie dalej: $($p.Powod)"
    }
  }

  # Skille - porazka nie przerywa aktualizacji: zrodla skilli leza na GitHubie, a ich brak nie psuje
  # niczego w samym MegaRuchaczu. Codzienne sprawdzenie skilli w nadzorcy dogra je samo.
  if (Modul-Wl $rej "skille") {
    Etap "nanosze" 3 "Dogrywam wbudowane skille"
    $w = Wolaj-I-Loguj "skille -Wbudowane" (Join-Path $Zrodlo "narzedzia\skille.ps1") @("-Tryb", "instaluj", "-Wbudowane", "-KatalogDomowy", $KatalogDomowy, "-Przerwy", $PRZERWY_SKILLI) $SEKUNDY_SKILLI
    if ($w.Kod -eq 3) { Uwaga "Wbudowanych skilli nie dograłem - akurat pracowało inne sprawdzenie skilli; codzienne sprawdzenie dogra je samo." }
    elseif ($w.Kod -ne 0) { Uwaga "Wbudowanych skilli nie dograłem (kod $($w.Kod): $(Sedno $w.Tekst)) - codzienne sprawdzenie skilli spróbuje znowu." }
  }
  return $true
}

# ------------------------------------------------------------------ krok 4: restart

# Procesy nadzorcy TEGO repo: powershell.exe z "<zrodlo>\zasobnik\nadzorca.ps1" w wierszu polecen.
# Kopie testowe (test-p7: %TEMP%\test-p7-*\nadzorca-test.ps1) i kroki w tle (zasobnik\nadzorca\
# licz-krok.ps1) tej sciezki nie maja. $null = listy procesow nie da sie odczytac.
function Procesy-Nadzorcy {
  try {
    return ,@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop |
              Where-Object { $_.CommandLine -and ($_.CommandLine.IndexOf($SkryptNadzorcy, [StringComparison]::OrdinalIgnoreCase) -ge 0) })
  } catch {
    Loguj "nie moge zajrzec do listy procesow: $($_.Exception.Message)"
    return $null
  }
}

function Argumenty-Nadzorcy {
  # Te same, co w zadaniu Harmonogramu (zasobnik\zainstaluj-zasobnik.ps1 Argumenty-Nadzorcy).
  return ('--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' +
          $SkryptNadzorcy + '" -Zrodlo "' + $Zrodlo + '"')
}

# Pomocnik restartu startuje POZA drzewem procesow nadzorcy - przez WMI (Win32_Process.Create, jego
# rodzicem jest usluga WMI). Ten przebieg to wnuk nadzorcy (nadzorca -> conhost -> powershell) i siedzi
# w tym samym obiekcie zadania Harmonogramu: gdyby Harmonogram sprzatnal procesy starej instancji po
# jej zamknieciu, pomocnik z tego drzewa zginalby razem z nimi. Okno: ShowWindow = 0 i conhost --headless.
function Odpal-Pomocnika([string]$zdarzenie, [string]$commit) {
  $ogon = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '" -Restart' +
          ' -Zrodlo "' + $Zrodlo + '" -KatalogDomowy "' + $KatalogDomowy + '" -ZadanieNadzorcy "' + $ZadanieNadzorcy + '"' +
          ' -Zdarzenie "' + $zdarzenie + '" -Commit ' + $commit
  if ($Reczna) { $ogon += " -Reczna" }
  $cmd = "conhost.exe --headless powershell.exe " + $ogon
  try {
    $si = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
    $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd; ProcessStartupInformation = $si } -ErrorAction Stop
    if ($r.ReturnValue -eq 0) { Loguj "pomocnik restartu wystartowal poza drzewem nadzorcy (WMI, PID $($r.ProcessId))"; return $true }
    Loguj "WMI nie wystartowalo pomocnika (kod $($r.ReturnValue)) - probuje zwyklym startem"
  } catch { Loguj "WMI nie wystartowalo pomocnika ($($_.Exception.Message)) - probuje zwyklym startem" }
  try {
    Start-Process -FilePath "conhost.exe" -ArgumentList ("--headless powershell.exe " + $ogon) -WindowStyle Hidden -ErrorAction Stop | Out-Null
    Uwaga "Pomocnik restartu wystartował w drzewie procesów nadzorcy (WMI odmówiło) - jeśli Harmonogram zamknie go razem ze starym nadzorcą, restart nie dojdzie do końca."
    return $true
  } catch { Loguj "pomocnik restartu nie wystartowal: $($_.Exception.Message)"; return $false }
}

# Krok 4 po stronie tego przebiegu: stan "restart", pomocnik, a gdy da znak, ze czeka na blokade -
# oddanie jej (w finally wolajacego). Zwraca kod wyjscia.
function Zlec-Restart([string]$commit) {
  Etap "restart" 4 "Uruchamiam MegaRuchacza od nowa, żeby działał na nowej wersji"
  $procesy = Procesy-Nadzorcy
  $zadanie = Get-ScheduledTask -TaskName $ZadanieNadzorcy -ErrorAction SilentlyContinue
  if (-not $zadanie -and $null -ne $procesy -and $procesy.Count -eq 0) {
    Uwaga "Nadzorcy (ikony w zasobniku) nie ma na tym komputerze - nie było czego uruchamiać od nowa."
    Odnotuj-Znacznik ([ordered]@{ "nadzorca" = $commit; "nadzorca.data" = (Teraz) })
    return (Koniec-Naniesienia)
  }
  $nazwa = "Local\MegaRuchacz-akt-pomocnik-" + [guid]::NewGuid().ToString("N")
  $ev = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::ManualReset, $nazwa)
  try {
    if (-not (Odpal-Pomocnika $nazwa $commit)) {
      Blad "restart" ("Nowa wersja jest wgrana, ale nie udało się uruchomić MegaRuchacza od nowa - nadzorca działa jeszcze na starej wersji. " +
                      "Zadziała na nowej po następnym zalogowaniu; od razu: prawy klik na ikonie MegaRuchacza, `„Zamknij`”, a potem uruchom go ponownie.")
      return 1
    }
    if (-not $ev.WaitOne($SEKUNDY_NA_POMOCNIKA * 1000)) {
      Blad "restart" ("Nowa wersja jest wgrana, ale pomocnik ponownego uruchomienia nie zgłosił się w $SEKUNDY_NA_POMOCNIKA s - nadzorca działa jeszcze na starej wersji. " +
                      "Zadziała na nowej po następnym zalogowaniu. Dziennik: $PlikDziennika")
      return 1
    }
    Loguj "pomocnik restartu dal znak - oddaje mu blokade, dalej pisze on"
    return 0
  } finally { $ev.Dispose() }
}

function Opis-Zaktualizowano {
  $p = $script:Stan.wersja_przed; $n = $script:Stan.wersja_po
  if ($p -and $n -and ($p -ne $n)) { return "Zaktualizowano: $p → $n" }
  return "Zaktualizowano - wersja $n wgrana i działa"
}

# Koniec przebiegu, ktory nanosil nowa wersje (po restarcie albo bez nadzorcy do restartu):
# "zaktualizowano" - chyba ze w naniesieniu nie doinstalowala sie Pamiec rozmow (pole lore_blad,
# pomocnik restartu ma je z pliku stanu). Wtedy nowa wersja jest wgrana, a wynikiem jest blad z jej
# powodem: zielona linia nie moze zakryc porazki. Zwraca kod wyjscia.
function Koniec-Naniesienia {
  $lb = $script:Stan.lore_blad
  if ($lb -and "$($lb.przyczyna)") {
    $script:Stan.lore_blad = $null
    Blad "$($lb.przyczyna)" "$($lb.powod)"
    return 1
  }
  Koniec "zaktualizowano" (Opis-Zaktualizowano)
  return 0
}

# Nowy proces nadzorcy (spoza $stare), ktory przezyl $SEKUNDY_ZYCIA. $null = nie wstal w $sekundy.
function Czekaj-Na-Nadzorce($stare, [int]$sekundy) {
  $koniec = (Get-Date).AddSeconds($sekundy)
  $odrzucone = @{}
  while ((Get-Date) -lt $koniec) {
    $p = Procesy-Nadzorcy
    foreach ($x in @($p)) {
      if (-not $x -or (@($stare) -contains $x.ProcessId) -or $odrzucone.ContainsKey($x.ProcessId)) { continue }
      Start-Sleep -Seconds $SEKUNDY_ZYCIA
      if (Get-Process -Id $x.ProcessId -ErrorAction SilentlyContinue) { return $x.ProcessId }
      Loguj "nowy proces nadzorcy (PID $($x.ProcessId)) zakonczyl sie w ciagu $SEKUNDY_ZYCIA s"
      $odrzucone[$x.ProcessId] = $true
    }
    Start-Sleep -Seconds 1
  }
  return $null
}

function Wez-Blokade($m, [int]$ms) {
  try { return $m.WaitOne($ms) }
  catch {
    # Porzucona blokada (poprzedni przebieg padl, trzymajac ja) jest juz nasza - ten sam wzorzec, co
    # w straznik-zasad.ps1 Odswiez-Zrodlo (wyjatek bywa owiniety w MethodInvocationException).
    $wew = $_.Exception
    while ($wew -and -not ($wew -is [System.Threading.AbandonedMutexException])) { $wew = $wew.InnerException }
    if (-not $wew) { throw }
    Loguj "blokada po przebiegu, ktory padl w polowie - przejmuje ja"
    return $true
  }
}

# Pomocnik: przejmuje blokade od przebiegu, ktory go wystartowal, zamyka stary nadzorce, startuje
# zadanie i sprawdza, ze nowy wstal. Zwraca kod wyjscia.
function Pomocnik-Restartu {
  $poprzedni = Czytaj-Stan
  if ($poprzedni) { $script:Stan = $poprzedni }
  $script:Stan.pid = $PID
  Loguj "pomocnik restartu (zadanie $ZadanieNadzorcy, nadzorca $SkryptNadzorcy, commit $Commit)"
  $ev = $null
  if ($Zdarzenie) {
    try { $ev = [System.Threading.EventWaitHandle]::OpenExisting($Zdarzenie) }
    catch { Loguj "pomocnik: nie ma juz sygnalu $Zdarzenie (wolajacy sie poddal?) - restart robie mimo to" }
  }
  $blokada = New-Object System.Threading.Mutex($false, $NazwaBlokady)
  $mam = $false
  try {
    if ($ev) { [void]$ev.Set(); $ev.Dispose() }
    $mam = Wez-Blokade $blokada ($SEKUNDY_NA_BLOKADE_POMOCNIKA * 1000)
    if (-not $mam) {
      Blad "blokada-pomocnika" ("Nowa wersja jest wgrana, ale ponowne uruchomienie nie ruszyło - przez $SEKUNDY_NA_BLOKADE_POMOCNIKA s trzymał je inny przebieg aktualizacji. " +
                                "Nadzorca działa jeszcze na starej wersji; zadziała na nowej po następnym zalogowaniu.")
      return 1
    }
    $script:Stan.etap = "restart"; $script:Stan.krok = 4
    Zapisz-Stan

    $stare = Procesy-Nadzorcy
    if ($null -eq $stare) {
      Blad "restart" "Nowa wersja jest wgrana, ale nie mogę sprawdzić, czy nadzorca działa (lista procesów niedostępna). Zadziała na nowej wersji po następnym zalogowaniu."
      return 1
    }
    $starePid = @($stare | ForEach-Object { $_.ProcessId })
    foreach ($id in $starePid) {
      Loguj "zamykam stary proces nadzorcy PID $id"
      try { Stop-Process -Id $id -Force -ErrorAction Stop } catch { Loguj "Stop-Process $id - $($_.Exception.Message)" }
    }
    $koniec = (Get-Date).AddSeconds($SEKUNDY_NA_ZAMKNIECIE)
    while ((Get-Date) -lt $koniec -and @($starePid | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }).Count -gt 0) { Start-Sleep -Milliseconds 500 }
    $zywe = @($starePid | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
    if ($zywe.Count -gt 0) {
      Blad "restart" ("Nowa wersja jest wgrana, ale starego nadzorcy nie dało się zamknąć (PID $($zywe -join ', ')) - działa dalej na starej wersji. " +
                      "Zadziała na nowej po następnym zalogowaniu.")
      return 1
    }

    $nowy = $null
    try {
      Start-ScheduledTask -TaskName $ZadanieNadzorcy -ErrorAction Stop
      Loguj "wystartowane zadanie Harmonogramu $ZadanieNadzorcy"
      $nowy = Czekaj-Na-Nadzorce $starePid $SEKUNDY_NA_WSTANIE
      if (-not $nowy) { Loguj "zadanie $ZadanieNadzorcy wystartowane, a nadzorcy nie widac po $SEKUNDY_NA_WSTANIE s" }
    } catch { Loguj "zadanie Harmonogramu $ZadanieNadzorcy nie wystartowalo: $($_.Exception.Message)" }
    if (-not $nowy) {
      # Zapas: ten sam wiersz polecen co w zadaniu, wprost. Drugi egzemplarz (gdyby zadanie jednak
      # ruszylo) konczy sie sam na zamku jednej kopii w nadzorca.ps1.
      try {
        Start-Process -FilePath "conhost.exe" -ArgumentList (Argumenty-Nadzorcy) -WindowStyle Hidden -ErrorAction Stop | Out-Null
        Loguj "nadzorca wystartowany wprost (conhost --headless), bez Harmonogramu"
        $nowy = Czekaj-Na-Nadzorce $starePid $SEKUNDY_NA_WSTANIE
        if ($nowy) { Uwaga "Zadanie Harmonogramu $ZadanieNadzorcy nie uruchomiło nadzorcy - wystartowałem go wprost. Przy następnym logowaniu uruchomi go Harmonogram; jeśli ikona się wtedy nie pojawi, kliknij `„Zmień instalację`” i zapisz wybór jeszcze raz." }
      } catch { Loguj "nadzorca nie wystartowal wprost: $($_.Exception.Message)" }
    }
    if (-not $nowy) {
      Blad "restart" ("Nowa wersja jest wgrana, ale MegaRuchacz nie wstał po ponownym uruchomieniu (ikony w zasobniku nie ma). " +
                      "Wyloguj się i zaloguj ponownie; jeśli ikona dalej się nie pojawi, przyczyna jest w dzienniku nadzorcy: $(Join-Path $DomClaude '.megaruchacz-zasobnik.log')")
      return 1
    }
    Loguj "nowy nadzorca chodzi (PID $nowy)"
    Odnotuj-Znacznik ([ordered]@{ "nadzorca" = $Commit; "nadzorca.data" = (Teraz) })
    return (Koniec-Naniesienia)
  } finally {
    if ($mam) { try { $blokada.ReleaseMutex() } catch { Loguj "nie oddalem blokady: $($_.Exception.Message)" } }
    $blokada.Dispose()
  }
}

# ------------------------------------------------------------------ przebieg

function Aktualizuj {
  Przytnij-Dziennik
  $poprzedni = Czytaj-Stan
  if ($poprzedni -and $poprzedni.sprawdzone) { $script:Stan.sprawdzone = $poprzedni.sprawdzone }
  $od = Get-Date
  $script:Stan.start = Teraz
  $przed = Wersja-Narzedzia
  $script:Stan.wersja_przed = $przed
  $script:Stan.wersja_po = $przed
  Loguj "=== aktualizacja ($(if ($Reczna) { 'z przycisku' } else { 'automatyczna' })): zrodlo $Zrodlo, dom $KatalogDomowy, wersja $przed"
  Etap "sprawdzam" 1 "Sprawdzam, czy na serwerze jest nowsza wersja MegaRuchacza"

  if (-not (Test-Path -LiteralPath $Zrodlo)) {
    Blad "brak-zrodla" "Nie ma katalogu MegaRuchacza $Zrodlo - nie ma czego aktualizować. Jeśli katalog został przeniesiony, zainstaluj MegaRuchacza w nowym miejscu od nowa."
    return 1
  }
  $r = Wolaj-I-Loguj "straznik -TylkoPobierz" (Join-Path $Zrodlo "narzedzia\straznik-zasad.ps1") @("-TylkoPobierz", "-Zrodlo", $Zrodlo, "-KatalogDomowy", $KatalogDomowy) $SEKUNDY_STRAZNIKA
  $ws = Wynik-Straznika $r $od
  if (-not $ws.wynik) {
    Blad "straznik" ("Nie wiem, czy jest nowsza wersja - sprawdzanie nie oddało wyniku (kod $($r.Kod): $(Sedno $r.Tekst)). " +
                     "Spróbuję znowu za godzinę; jeśli to się powtarza, przyczyna jest w dzienniku: $PlikDziennika")
    return 1
  }
  if (@("pobrane", "aktualne", "zablokowane", "rozjechane") -contains $ws.wynik) { $script:Stan.sprawdzone = Teraz }
  if (@("pobrane", "aktualne") -notcontains $ws.wynik) {
    Blad $ws.wynik (Powod-Ludzki $ws.wynik $ws.powod)
    return 1
  }

  $head = Git-Tekst @("rev-parse", "HEAD")
  if (-not $head) {
    Blad "git" "Nie wiem, na jakiej wersji stoi katalog MegaRuchacza (git rev-parse się nie udał - szczegóły w dzienniku: $PlikDziennika). Spróbuję znowu za godzinę."
    return 1
  }
  $po = Wersja-Narzedzia
  $zn = Znacznik-Naniesienia
  if ($zn["naniesione.wersja"]) { $script:Stan.wersja_przed = $zn["naniesione.wersja"] }
  $script:Stan.wersja_po = $po
  $nowaWersja = ($zn["naniesione"] -ne $head)
  $restart = $nowaWersja -or ($zn["nadzorca"] -ne $head)

  # Rejestr juz tutaj, przed "nic nowego": brak Pamieci rozmow (Lore) liczy sie NIEZALEZNIE od
  # znacznikow naniesienia (patrz naglowek). Wyjatek z odczytu w tym miejscu nie jest nowym bledem -
  # slad w dzienniku, a blad "rejestr" zostaje tam, gdzie byl: przed wgrywaniem czegokolwiek.
  $rej = $null
  $bladRejestru = ""
  try { $rej = Rejestr }
  catch { $bladRejestru = $_.Exception.Message; Loguj "rejestru modulow nie odczytalem ($bladRejestru) - braku Lore nie licze" }
  $doLore = $false
  $odlozone = $null
  $brakLore = Lore-Brakuje $rej
  if ($brakLore) {
    Loguj "brakuje Pamieci rozmow (Lore): $brakLore"
    $odlozone = Odroczenie-Lore
    if (-not $odlozone) { $doLore = $true }
  }
  $nanies = $nowaWersja -or $doLore
  Loguj "commit $head; naniesione: $($zn['naniesione']); nadzorca na: $($zn['nadzorca']) -> nowa wersja: $nowaWersja, restart: $restart, doinstalowac Lore: $doLore$(if ($odlozone) { ' (odlozone)' })"
  if (-not $nanies -and -not $restart) {
    # Lore odlozone przez okno instalatora (albo zajete) i nic wiecej do zrobienia - lagodny blad,
    # w oknie szara linia "instaluje inny proces"; po swiezym starcie Windows - "aktualne" z uwaga.
    if ($odlozone -and $odlozone.Przyczyna) { Blad $odlozone.Przyczyna $odlozone.Powod; return 1 }
    if ($odlozone) { Uwaga $odlozone.Powod }
    Koniec "aktualne" "Masz najnowszą wersję MegaRuchacza ($po)"
    return 0
  }
  if ($odlozone) { Uwaga $odlozone.Powod }

  # Brak Lore to jedyny powod: tylko doinstalowanie - wersja jest juz wgrana i nadzorca na niej chodzi,
  # wiec bez instaluj-globalnie, bez restartu i bez ruszania znacznikow naniesienia.
  if ($doLore -and -not $restart) {
    Etap "pobieram" 2 "Brakuje Pamięci rozmów (Lore) - przygotowuję doinstalowanie"
    $p = Doinstaluj-Lore $false
    if ($p) { Blad $p.Przyczyna $p.Powod; return 1 }
    Koniec "zaktualizowano" (Opis-Zaktualizowano)
    return 0
  }

  if ($ws.wynik -eq "pobrane") {
    $opis = if ($przed -and $po -and ($przed -ne $po)) { "Pobrałem nową wersję: $przed → $po" } else { "Pobrałem nowe poprawki (wersja $po)" }
  } else {
    $opis = "Na dysku czeka wersja $po pobrana wcześniej - jeszcze niewgrana"
  }
  Etap "pobieram" 2 $opis

  if (-not $rej) {
    Blad "rejestr" "Nie odczytałem, które moduły są zainstalowane ($bladRejestru) - niczego nie wgrywam na ślepo. Spróbuję znowu za godzinę."
    return 1
  }
  if ($rej.baza -eq $false) {
    # Slad odinstalowania (umowa stan.ps1, P64): nic nie wraca samo.
    Uwaga "MegaRuchacz jest odinstalowany na tym komputerze - nowa wersja leży na dysku, ale niczego nie wgrywam."
    Koniec "zaktualizowano" "Pobrano wersję $po (bez wgrywania - MegaRuchacz odinstalowany)"
    return 0
  }

  if ($nanies) {
    $narz = Nazwy-Narzedzi
    if (-not (Nanies $rej $narz $doLore)) { return 1 }
    Odnotuj-Znacznik ([ordered]@{ "naniesione" = $head; "naniesione.wersja" = $po; "naniesione.data" = (Teraz) })
  }
  return (Zlec-Restart $head)
}

$script:Stan = Nowy-Stan
$script:BladDziennika = $false
# Doinstaluj-Lore / Uruchom-Dlugi: poczatek doinstalowania, ostatnia linia KROK, opis kroku bez niej.
$script:LoreOd = Get-Date
$script:LoreKrok = ""
$script:LoreOpisKroku = ""

if ($Restart) {
  $kod = 1
  try { $kod = Pomocnik-Restartu }
  catch {
    Loguj "pomocnik restartu sie wywrocil: $($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
    Blad "wywrotka" "Ponowne uruchomienie po aktualizacji wywróciło się ($($_.Exception.Message)). Nadzorca może działać jeszcze na starej wersji - zadziała na nowej po następnym zalogowaniu."
    $kod = 1
  }
  exit $kod
}

$blokada = New-Object System.Threading.Mutex($false, $NazwaBlokady)
$mam = $false
try { $mam = Wez-Blokade $blokada 0 }
catch { [Console]::Error.WriteLine("aktualizacja: blokada sie wywrocila - $($_.Exception.Message)"); $mam = $false }
if (-not $mam) {
  # Drugi przebieg w trakcie pierwszego: ani linii w pliku stanu - tamten wlasnie go pisze.
  Loguj "inny przebieg aktualizacji wlasnie pracuje - ten konczy od razu i niczego nie zapisuje"
  $blokada.Dispose()
  exit 3
}
$kod = 1
try { $kod = Aktualizuj }
catch {
  Loguj "aktualizacja sie wywrocila: $($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
  Blad "wywrotka" "Aktualizacja wywróciła się ($($_.Exception.Message)). Spróbuję znowu za godzinę; szczegóły w dzienniku: $PlikDziennika"
  $kod = 1
} finally {
  try { $blokada.ReleaseMutex() } catch { Loguj "nie oddalem blokady: $($_.Exception.Message)" }
  $blokada.Dispose()
}
exit $kod
