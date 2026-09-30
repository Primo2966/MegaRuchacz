# Nadzorca MegaRuchacza - ikona w zasobniku Windows.
#
# PO CO TO ISTNIEJE. Do 0.17.0 rachunek za pamiec, start cyklu wiedzy i ALARM
# O CISZY wisialy w calosci na hookach SessionStart. Gdy hook nie odpalal,
# milknal razem z nim takze mechanizm, ktory mial wykryc, ze nic nie chodzi -
# i tak przez tydzien (17-24.09.2026) nikt nie zobaczyl ani jednej liczby.
# Wykrywacz ciszy, ktory milknie razem z tym, co wykrywa, jest bezuzyteczny.
# Dlatego nadzorca jest PROGRAMEM OSOBNYM: startuje przy zalogowaniu z zadania
# w Harmonogramie, nie wie nic o tym, czy uzytkownik otworzyl Claude Code,
# i to ON jest odtad glownym wyzwalaczem cyklu. Hooki zostaja jako droga zapasowa.
#
# DLACZEGO POWERSHELL, A NIE NODE ANI PYTHON. Warunek ze zlecenia brzmial:
# ikona w zasobniku BEZ instalowania czegokolwiek nowego u uzytkownika i bez
# mrugajacej konsoli. Node nie ma zasobnika we wbudowanych modulach (trzeba by
# dolozyc pakiet natywny), Python potrzebowalby pystray i pillow - w obu
# wypadkach to nowa zaleznosc. PowerShell 5.1 jest w Windows z definicji, a razem
# z nim System.Windows.Forms i System.Drawing, czyli NotifyIcon, menu i dymki.
# Zero instalacji. Okno konsoli nie mrugnie, bo zadanie startuje przez
# "conhost.exe --headless powershell.exe -WindowStyle Hidden" - ta sama sztuczka,
# ktorej uzywa juz narzedzia\straznik-zasad.ps1.
#
# --------------------------------------------------------------------------
# UKLAD OKNA - przepisany 24.09.2026 dwa razy. Najpierw, bo poprzedni sypal
# wszystkim naraz; potem, bo byl sciana tekstu bez statystyk.
#
# Uzytkownik nie jest programista i powiedzial wprost: "pelno informacji w ryj
# mam rzuconych, nie wiem na co patrzec", a potem: "przerob okienko, aby bylo
# ladniejsze, miescilo wszystko w sobie. Moze jakies statystyki". Stad decyzje:
#
# 1. KARTY, NIE TEKST. Jasnoszare tlo, na nim biale karty z cienka ramka, kroj
#    Segoe UI. Kolor tylko tam, gdzie niesie znaczenie: czerwien przy sprawie do
#    zrobienia, zolty przy "czegos nie wiem" i przy informacji, zielen przy
#    "wszystko gra", bursztyn na slupku dnia nadrabiania. Reszta szara.
# 2. TRZY LICZBY KOSZTOW jako trzy karty obok siebie: duza liczba, pod nia
#    jedno zdanie CZYM JEST. Karta nauki z rozmow ma dopisek, za jaki okres
#    i czy to bylo nadrabianie - bez niego drogi dzien wygladal jak nowa norma.
# 3. STATYSTYKA NAUKI: wykres slupkowy z 30 dni (jeden slupek na dzien, dzien
#    nadrabiania innym kolorem, prog zwyklego dnia przerywana linia), obok sumy
#    7 i 30 dni, srednia na dzien nauki i typowy zwykly dzien. Malo danych nie
#    daje pustego wykresu bez slowa - okno mowi, ze statystyka dopiero sie zbiera.
# 4. DWA WIDOKI W JEDNYM OKNIE: [Przeglad] i [Szczegoly], przelacznik u gory.
#    Szczegoly (rozbicie, sciezki, pelne tresci alarmow) nie wydluzaja juz okna -
#    zajmuja miejsce przegladu, wiec okno ma stala szerokosc i wysokosc dobrana
#    pod przeglad, bez przewijania na zwyklym ekranie.
# 5. SEKCJA PROBLEMOW ZNIKA, gdy problemow nie ma - nie zostawia pustej ramki.
#    Gdy jest problem, stoi jako pierwsza, na kolorowym tle, z porada bez zargonu
#    i dopiskiem, czy trzeba cos zrobic ("dla informacji - nic nie trzeba robic").
# 6. KAZDY PRZYCISK MOWI, CO ZROBI, a ten jeden, ktory wydaje tokeny, ma szacunek
#    kosztu w samej etykiecie i pyta o zgode. 24.09.2026 jedno kliknieciem
#    "Uruchom cykl teraz" poszlo 312 609 tokenow bez slowa ostrzezenia.
#
# 7. 25.09.2026 (P7): okno szersze (liczone z ekranu), karta "Otwarcie sesji"
#    na Przegladzie (zmierzona calosc z transkryptow i udzial MegaRuchacza),
#    Szczegoly jako karty sekcji zamiast jednego pola tekstu, podglad warstwy
#    z dwiema kolumnami nad trescia.
# 8. 28.09.2026 (P14): dwa kafelki "dokleja do kazdej wiadomosci" i "doklada
#    na otwarcie sesji" usuniete - dublowaly liczby z karty "Otwarcie sesji".
#    Te liczby stoja teraz tylko tam, rozpisane pod paskiem. Kafelek nauki
#    z rozmow na cala szerokosc, z duza liczba jako procent jednego otwarcia
#    sesji: na Przegladzie kazda liczba MegaRuchacza jest w tej samej mierze.
# 9. 28.09.2026 (P17): koszt nauki z powrotem w TOKENACH - karta, wykres (os
#    w tys. tokenow), przycisk, pytanie o zgode i werdykt. Uzytkownik: "te 20%,
#    to nie wiem czego". Jedyne porownanie: udzial w calym dziennym zuzyciu
#    tokenow w rozmowach z Claude (Zuzycie-Dzienne w stan-nadzorcy.ps1).
#    Procent otwarcia okna rozmowy zostal tylko w karcie "Otwarcie okna rozmowy".
# 10. 29.09.2026 (P18): czwarta zakladka "Skille" - polecane skille z bazy
#    skille\katalog.psd1, stan, przyciski Zainstaluj / Aktualizuj teraz / Cofnij.
#    Dozor raz na dobe odpala w tle narzedzia\skille.ps1 -Tryb codziennie.
# 11. 30.09.2026 (P20): lista skilli w grupach zwijanych (na starcie same naglowki
#    z liczbami, pasek z lewej przy grupie z problemem albo nowsza wersja), stan
#    "autor usunal" (szary) i przycisk "Usun u mnie" z kopia zapasowa.
# 12. 30.09.2026 (P21): uzytkownik: "zeby tak dziwnie nie otwierala sie, gdy rano
#    ja klikam ... zeby nie zmieniala swojego rozmiaru w dziki sposob". Okno ma od
#    pierwszej chwili stala wysokosc, wszystko, co wola skrypty, liczy sie w watkach
#    w tle (sekcja "liczenie w tle i ekran ladowania"), a zakladka bez kompletu
#    danych z dzis ma nad soba ekran ladowania z lista krokow.
# 13. 30.09.2026 (P26): karta "Ile tokenow naprawde zuzywasz" pod werdyktem - dzis
#    i srednio z 7 dni Twoje rozmowy kontra workerzy, najdrozsi workerzy dnia,
#    najdluzsze rozmowy z ostatniej doby (krok w tle "koszt", Koszt-Dzis); ta sama
#    rzecz w pelni jako sekcja w Szczegolach.
#
# PRZYCISKU [ODSWIEZ] NIE MA I NIE MA GO BYC. Istnial tylko dlatego, ze okno
# nie odswiezalo sie samo - byl obejsciem braku, nie funkcja. Dzis okno liczy
# od nowa przy otwarciu to, czego nie ma z dzis, starsze niz kwadrans odswieza
# po cichu, a dozor przelicza wszystko co kwadrans; recznemu sprawdzeniu
# zostala pozycja w menu ikony, dla tego, kto wlasnie cos poprawil i chce
# zobaczyc skutek natychmiast.
#
# POLSKIE ZNAKI. Kod i komentarze sa bez ogonkow, ale teksty widoczne w oknie
# maja je miec. Dlatego ten plik ORAZ stan-nadzorcy.ps1 sa zapisane w UTF-8
# ZE ZNACZNIKIEM BOM: bez BOM-u PowerShell 5.1 czyta plik jako ANSI i w oknie
# wychodza krzaki. To sie w tym projekcie zdarzylo juz dwa razy.
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File zasobnik\nadzorca.ps1
#     -Zrodlo <kat>         katalog glowny narzedzia (domyslnie: katalog nad zasobnik\)
#     -KatalogDomowy <kat>  podmiana katalogu domowego (testy, proba negatywna)
#     -Minut <n>            co ile minut dozor sprawdza stan (domyslnie 15)
#     -Pokaz                otwiera okno od razu po starcie
#     -Raz                  JEDEN przebieg dozoru bez petli i bez stalej ikony;
#                           wszystko wypisuje na ekran. Tego trybu uzywa sprawdzenie
#                           i proba negatywna - okna nie da sie sprawdzic bez pulpitu
#     -Raport               sam wydruk okna na ekran, bez dozoru i bez alarmow
#     -Proba                nie startuje cyklu i nic nie zapisuje
#     -Cicho                nie pokazuje dymkow, sam wydruk (tylko z -Raz)
#
# Do OGLADANIA okna bez ryzyka wydania choc jednego tokena:
#   powershell -ExecutionPolicy Bypass -File zasobnik\nadzorca.ps1 -Pokaz -Proba
# "-Proba" zatrzymuje Ruszaj-Cykl na sucho, wiec ani dozor, ani przycisk nie
# uruchomia prawdziwego czytania rozmow.
#
# Proba negatywna sekcji problemow - podstawiamy pusty katalog domowy, w ktorym
# nic nigdy nie chodzilo, wiec alarmy musza sie odezwac:
#   powershell -ExecutionPolicy Bypass -File zasobnik\nadzorca.ps1 -Raport -Proba -KatalogDomowy C:\Temp\pusty
#
# Proba negatywna listy zmian w pamieci - w podstawionym katalogu domowym
# kladziemy wlasny .claude\wiedza\.wiedza-stan.txt (NIGDY prawdziwy): z dwiema
# liniami meldunek_N ma pokazac obie z identyfikatorami, z "meldunek: bez zmian"
# jedna linie, a bez pliku - "nie wiem", nigdy zero.
#
# Proba negatywna kosztu nauki i statystyki - w podstawionym katalogu domowym
# kladziemy wlasne .claude\wiedza\.koszt-cyklu.txt i .koszt-historia.tsv (NIGDY
# prawdziwe) i ogladamy wydruk -Raport -Proba:
#   - zwykly, jednodniowy przebieg nad progiem   -> [!] czerwony alarm "za zwykly dzien",
#   - nadrabianie rozmow sprzed wielu dni       -> [i] zolta informacja "nadrabiala zaleglosc",
#   - brak historii                             -> "statystyka dopiero sie zbiera", zadnego zera.
# Informacja [i] nie idzie na dymek i nie podnosi kodu wyjscia -Raz.
#
# Kod wyjscia w trybie -Raz: 0 gdy nie bylo alarmow, 1 gdy byl choc jeden.
# Kod 3 (kazdy tryb): nadzorca nie wstal, bo ktoregos z jego plikow nie dalo sie
# wczytac w calosci (patrz BUDOWA) - powod na strumieniu bledow i w dzienniku nadzorcy.
#
# BUDOWA (P28a, 30.09.2026). Ten plik trzyma parametry, start (wczytanie stanu,
# sprawdzenie zrodla), tryby bez GUI (-Raz, -Raport), zamek jednej kopii, ikone
# z menu, zegar dozoru i petle okna - czyli przebieg i wszystkie exit. Reszta
# lezy w zasobnik\nadzorca\, jeden plik na temat, zeby do zmiany wystarczylo
# przeczytac jeden kawalek (kazdy ma naglowek: co w nim jest i skad jest wolany):
#   przeglad-tresc.ps1  tresc Przegladu: sprawy do uwagi, napisy przyciskow, wydruk
#   szczegoly.ps1       zakladka Szczegoly: sekcje dla okna i dla wydruku -Raport
#   dozor.ps1           dozor: przebieg, decyzje, co kwadrans w tle, podpowiedz ikony
#   wyglad.ps1          stan okna ($script:...), kolory, czcionki, szerokosci
#   karty.ps1           klocki okna: etykiety, karty, przyciski, wiersze, tabele
#   przeglad.ps1        karty Przegladu: werdykt, koszt, otwarcie, nauka, stan
#   wykres.ps1          wykres nauki z 30 dni (kontrolka Chart albo wlasne slupki)
#   warstwy.ps1         zakladka Warstwy pamieci: lista i podglad
#   skille.ps1          zakladka Skille: grupy, szczegoly skilla, przyciski
#   w-tle.ps1           liczenie w tle: kawalki danych, kroki w watkach, limity
#   ladowanie.ps1       ekran ladowania z lista krokow
#   okno.ps1            budowa okna (Pokaz-Okno) i przelaczanie zakladek
# Trzy pierwsze wczytuja sie PRZED trybami bez GUI (potrzebuje ich -Raz i
# -Raport), reszta dopiero po zamku jednej kopii - tam, gdzie ten kod stal, zanim
# plik podzielono, wiec wszystko, co sie wykonuje, idzie w tej samej kolejnosci.
# Stan i wywolania skryptow sa w stan-nadzorcy.ps1 (i w jego stan-*.ps1 obok).
# W modulach nie ma exit ani $PSScriptRoot / $PSCommandPath: exit w pliku
# wczytanym kropka konczy tylko ten plik, a sciezki wskazywalyby modul. Nowy
# modul: nazwa na liscie przy wczytywaniu i ostatnia linia
# $script:ModulyOkna["nazwa"] = $true; brak, blad skladni albo plik uciety =
# odmowa startu (Odmowa-Nadzorcy, kod 3). Moduly zapisane jak ten plik: UTF-8
# ZE ZNACZNIKIEM BOM i konce linii CRLF (teksty okna maja polskie znaki).

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [string]$KatalogDomowy = $HOME,
  [int]$Minut = 15,
  [switch]$Pokaz,
  [switch]$Raz,
  [switch]$Raport,
  [switch]$Proba,
  [switch]$Cicho
)

# Odmowa startu (P28a). Nadzorca bez ktoregos ze swoich plikow (stan-nadzorcy.ps1
# i moduly w zasobnik\nadzorca\) nie wie, co robi: wstalby z dziura, ktora
# wywroci sie dopiero przy kliknieciu, albo pokazalby okno bez polowy liczb.
# Zamiast tego mowi, czego brakuje, i konczy kodem 3. Powod idzie na strumien
# bledow i do dziennika nadzorcy - z Harmonogramu strumien bledow nikomu sie nie
# pokaze, a ikona po prostu by nie wstala. -Proba niczego nie zapisuje, wiec wtedy
# zostaje sam strumien bledow.
function Odmowa-Nadzorcy([string]$powod) {
  Write-Error "nadzorca: $powod - nie startuje"
  if (-not $Proba) {
    try {
      $dziennik = Join-Path $KatalogDomowy ".claude\.megaruchacz-zasobnik.log"
      [System.IO.File]::AppendAllText($dziennik, ("{0} | NIE WSTALEM: {1}`r`n" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $powod), (New-Object System.Text.UTF8Encoding($false)))
    } catch { Write-Error "nadzorca: tego powodu nie dalo sie tez zapisac do dziennika ($($_.Exception.Message))" }
  }
  exit 3
}
if (-not $PSScriptRoot) { Odmowa-Nadzorcy "nie wiem, gdzie leza moje pliki (skrypt nie jest uruchomiony z pliku)" }
$script:KatalogModulowOkna = Join-Path $PSScriptRoot "nadzorca"

try { . (Join-Path $PSScriptRoot "stan-nadzorcy.ps1") }
catch { Odmowa-Nadzorcy "$($_.Exception.Message)" }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Ustaw-Nadzorce $Zrodlo $KatalogDomowy ([bool]$Proba)

# WYKRES. .NET Framework 4.x ma wbudowana kontrolke wykresow
# (System.Windows.Forms.DataVisualization) - nic do instalowania. Na maszynie
# uzytkownika lezy w GAC (sprawdzone 24.09.2026: C:\Windows\Microsoft.NET\assembly\
# GAC_MSIL\System.Windows.Forms.DataVisualization\v4.0_4.0.0.0__31bf3856ad364e35).
# Gdyby sie nie zaladowala albo wywrocila przy rysowaniu, slupki rysuje sam
# nadzorca (Graphics w zdarzeniu Paint) - wykres ma byc tak czy owak, a powod
# idzie do dziennika i do szczegolow. Proba ladowania jest takze w trybie
# -Raport, zeby wydruk mowil, czym okno naprawde rysuje.
$script:JestChart     = $false
$script:ChartZawiodl  = $false
$script:PowodBezChart = ""
try {
  Add-Type -AssemblyName System.Windows.Forms.DataVisualization -ErrorAction Stop
  $script:JestChart = $true
} catch {
  try {
    Add-Type -AssemblyName "System.Windows.Forms.DataVisualization, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35" -ErrorAction Stop
    $script:JestChart = $true
  } catch {
    $script:PowodBezChart = $_.Exception.Message
    Notuj "wykres: kontrolka Chart sie nie zaladowala ($($script:PowodBezChart)) - slupki rysuje sam nadzorca"
  }
}

function Opis-Rysownika {
  if ($script:JestChart -and (-not $script:ChartZawiodl)) {
    return "rysuje go wbudowana w Windows kontrolka Chart (.NET Framework, nic do instalowania)"
  }
  return "słupki rysuje sam nadzorca, bo kontrolka Chart nie jest dostępna: $($script:PowodBezChart)"
}

# Bez katalogu zrodlowego nadzorca nie ma czego wolac i pokazywalby same
# "NIE WIADOMO" - a to wyglada jak usterka narzedzia, nie jak zla sciezka.
# Mowimy wprost i konczymy, zamiast udawac, ze cos nadzorujemy.
if (-not (Test-Path (Join-Path $Zrodlo "narzedzia\koszt-pamieci.ps1"))) {
  Write-Error "nadzorca: w '$Zrodlo' nie ma narzedzia\koszt-pamieci.ps1 - podaj wlasciwy -Zrodlo"
  exit 2
}

# Sufity Windows na dymek. Nie sa nasze - to twarde granice API powiadomien.
# Zgodnie z zasada "sufit nie ucina, sufit krzyczy" skrocony tekst dostaje
# ostrzezenie NA POCZATKU (poczatek przezywa uciecie zawsze), a cala tresc
# i tak idzie do okna oraz do dziennika, wiec nic nie ginie po cichu.
$MAX_TYTUL = 60
$MAX_TRESC = 240

function Skroc-Na-Dymek([string]$tekst, [int]$limit, [string]$ostrzezenie) {
  if (-not $tekst) { return "" }
  if ($tekst.Length -le $limit) { return $tekst }
  $zapas = $limit - $ostrzezenie.Length
  if ($zapas -lt 10) { return $ostrzezenie.Substring(0, [math]::Min($ostrzezenie.Length, $limit)) }
  return $ostrzezenie + $tekst.Substring(0, $zapas)
}

# Ikona. Bierzemy logo narzedzia z katalogu zrodlowego; gdy go nie ma albo nie
# da sie wczytac, zostaje ikona systemowa - program ma sie pokazac w zasobniku
# tak czy owak, bo bez ikony nie ma calego nadzorcy.
function Ikona-Nadzorcy {
  $plik = Join-Path $Zrodlo "logo.png"
  if (Test-Path $plik) {
    try {
      $obraz = [System.Drawing.Image]::FromFile($plik)
      $male = New-Object System.Drawing.Bitmap($obraz, 32, 32)
      $obraz.Dispose()
      return [System.Drawing.Icon]::FromHandle($male.GetHicon())
    } catch {
      Zanotuj-Wywrotke "wczytanie ikony z $plik" $_
    }
  }
  return [System.Drawing.SystemIcons]::Application
}

# ------------------------------------------------------------- zbieranie danych

# Zbierz-Wszystko mieszka od 0.22.4 (P21) w stan-nadzorcy.ps1: okno liczy dane
# w watku w tle, ktory wczytuje sam stan-nadzorcy.ps1 - funkcja musi byc tam.

# --- moduly okna: czesc wspolna ------------------------------------------------
# Tresc Przegladu, Szczegoly i dozor potrzebne sa takze trybom bez GUI (nizej),
# wiec wczytujemy je tutaj - tam, gdzie te funkcje staly, zanim plik podzielono.
# Brak modulu, blad skladni albo plik bez znacznika na koncu (pusty albo uciety)
# = odmowa startu, a nie nadzorca z dziura.
$script:ModulyOkna = @{}
foreach ($modulOkna in @("przeglad-tresc", "szczegoly", "dozor")) {
  $plikModuluOkna = Join-Path $script:KatalogModulowOkna "$modulOkna.ps1"
  try { . $plikModuluOkna }
  catch { Odmowa-Nadzorcy "nie da sie wczytac modulu $plikModuluOkna ($($_.Exception.Message))" }
  if (-not $script:ModulyOkna[$modulOkna]) {
    Odmowa-Nadzorcy "modul $plikModuluOkna nie wczytal sie do konca (nie ma znacznika na jego koncu - plik pusty albo uciety)"
  }
}

# --------------------------------------------------------------- tryby bez GUI

if ($Raz -or $Raport) {
  # Teksty okna maja polskie znaki, a konsola Windows startuje na stronie
  # kodowej, ktora ich nie zna. Bez tej linii wydruk sprawdzenia wyglada jak
  # usterka kodowania, choc w samym oknie wszystko jest w porzadku.
  try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 }
  catch { Write-Warning "nie przestawilem konsoli na UTF-8, polskie znaki moga wyjsc jako krzaki: $($_.Exception.Message)" }

  # Wywrotki z poprzedniego przebiegu meldujemy PRZED praca - inaczej nowy
  # przebieg nadpisalby slad po starym i nikt by sie o nim nie dowiedzial.
  $stare = @()
  try { $stare = Odbierz-Wywrotki } catch { Write-Warning "nie odczytalem wywrotek: $($_.Exception.Message)" }
  foreach ($w in $stare) { Write-Output "POPRZEDNIO SIE WYWROCILO: $w" }

  if ($Raport) {
    $d = Zbierz-Wszystko $true $true
    $probl = Zbierz-Problemy $d $stare "" ([datetime]::Now)
    $start = $null
    try { $start = Pomiar-Startu } catch { Zanotuj-Wywrotke "pomiar otwarcia okna rozmowy" $_ }
    $zu = $null
    try { $zu = Zuzycie-Dzienne $true } catch { Zanotuj-Wywrotke "dzienne zuzycie tokenow" $_ }
    $ko = $null
    try { $ko = Koszt-Dzis } catch { Zanotuj-Wywrotke "prawdziwy koszt dnia" $_ }
    $roz = @()
    try { $roz = Rachunek-Rozbicie }
    catch { Zanotuj-Wywrotke "rachunek za pamiec (rozbicie)" $_; $roz = @("  NIE UDALO SIE POLICZYC - szczegoly w dzienniku nadzorcy") }
    Zbuduj-Przod $d $probl ([datetime]::Now) $start $zu $ko | ForEach-Object { Write-Output $_ }
    Write-Output ""
    Zbuduj-Szczegoly $d $stare $roz $start $ko $zu | ForEach-Object { Write-Output $_ }
    Zapisz-Obecnosc "raport"
    exit 0
  }

  # Dymek takze w tym trybie - proba negatywna ma zobaczyc PRAWDZIWE
  # powiadomienie, a nie zapewnienie, ze by sie pokazalo.
  $dymek = {
    param($tytul, $tresc)
    # Pokazujemy CALA tresc i osobno to, co naprawde wchodzi na dymek - roznica
    # miedzy jednym a drugim jest tym, co sufit obcial, a to ma byc widac.
    $naDymekTytul = Skroc-Na-Dymek $tytul $MAX_TYTUL "[skrocone] "
    $naDymekTresc = Skroc-Na-Dymek $tresc $MAX_TRESC "[skrocone - calosc w oknie MegaRuchacza] "
    Write-Host ""
    Write-Host "POWIADOMIENIE"
    Write-Host "  tytul: $tytul"
    Write-Host "  tresc: $tresc"
    Write-Host "  na dymku, tytul ($($naDymekTytul.Length) zn.): $naDymekTytul"
    Write-Host "  na dymku, tresc ($($naDymekTresc.Length) zn.): $naDymekTresc"
    if ($Cicho) { Write-Host "  (-Cicho: dymka nie pokazuje)"; return }
    try {
      $n = New-Object System.Windows.Forms.NotifyIcon
      $n.Icon = Ikona-Nadzorcy
      $n.Visible = $true
      $n.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Warning
      $n.BalloonTipTitle = $naDymekTytul
      $n.BalloonTipText  = $naDymekTresc
      $n.ShowBalloonTip(15000)
      $do = [datetime]::Now.AddSeconds(6)
      while ([datetime]::Now -lt $do) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
      $n.Visible = $false
      $n.Dispose()
      Write-Host "  (dymek pokazany w zasobniku)"
    } catch {
      Write-Host "  (DYMKA NIE DALO SIE POKAZAC: $($_.Exception.Message))"
      Zanotuj-Wywrotke "pokazanie dymka" $_
    }
  }

  $d = Dozor $dymek $true $false
  Write-Output ""
  $probl = Zbierz-Problemy $d $stare "" ([datetime]::Now)
  $start = $null
  try { $start = Pomiar-Startu } catch { Zanotuj-Wywrotke "pomiar otwarcia okna rozmowy" $_ }
  $zu = $null
  try { $zu = Zuzycie-Dzienne $true } catch { Zanotuj-Wywrotke "dzienne zuzycie tokenow" $_ }
  $ko = $null
  try { $ko = Koszt-Dzis } catch { Zanotuj-Wywrotke "prawdziwy koszt dnia" $_ }
  $roz = @()
  try { $roz = Rachunek-Rozbicie }
  catch { Zanotuj-Wywrotke "rachunek za pamiec (rozbicie)" $_; $roz = @("  NIE UDALO SIE POLICZYC - szczegoly w dzienniku nadzorcy") }
  Zbuduj-Przod $d $probl ([datetime]::Now) $start $zu $ko | ForEach-Object { Write-Output $_ }
  Write-Output ""
  Zbuduj-Szczegoly $d $stare $roz $start $ko $zu | ForEach-Object { Write-Output $_ }
  if (@($d.Alarmy).Count -gt 0) { exit 1 }
  exit 0
}

# ------------------------------------------------------------------------ GUI
# Wszystko ponizej ma byc na poziomie skryptu, a nie w cudzych funkcjach:
# procedury obslugi zdarzen WinForms odpalaja sie po powrocie z funkcji,
# w ktorej je zapisano, wiec siegaja wylacznie po $script: i po funkcje skryptu.

[System.Windows.Forms.Application]::EnableVisualStyles()

# Jeden nadzorca na sesje. Drugi - wstawiony np. przez recznie odpalone zadanie -
# dublowalby alarmy i mogl ruszyc cykl dwa razy. Porzucony zamek (poprzedni
# przebieg padl w polowie) liczy sie jako wolny, inaczej jedna wywrotka
# blokowalaby start do konca sesji. Ta sama konstrukcja co w cykl-dzienny.ps1.
$script:Zamek = New-Object System.Threading.Mutex($false, "Local\MegaRuchacz-Nadzorca")
$mojZamek = $false
try { $mojZamek = $script:Zamek.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $mojZamek = $true }
if (-not $mojZamek) {
  Notuj "nadzorca juz chodzi w tej sesji - drugiego nie uruchamiam"
  exit 0
}

# --- moduly okna: reszta ------------------------------------------------------
# Stan okna, klocki, zakladki, liczenie w tle i budowa okna - dopiero tutaj, po
# zamku jednej kopii, tam, gdzie ten kod stal, zanim plik podzielono: stan okna,
# kolory, czcionki i stale krokow powstaja w tej samej kolejnosci co dotad i nie
# powstaja wcale w trybach bez GUI ani w drugiej kopii, ktora zaraz konczy.
foreach ($modulOkna in @("wyglad", "karty", "przeglad", "wykres", "warstwy", "skille", "w-tle", "ladowanie", "okno")) {
  $plikModuluOkna = Join-Path $script:KatalogModulowOkna "$modulOkna.ps1"
  try { . $plikModuluOkna }
  catch { Odmowa-Nadzorcy "nie da sie wczytac modulu $plikModuluOkna ($($_.Exception.Message))" }
  if (-not $script:ModulyOkna[$modulOkna]) {
    Odmowa-Nadzorcy "modul $plikModuluOkna nie wczytal sie do konca (nie ma znacznika na jego koncu - plik pusty albo uciety)"
  }
}

# ----------------------------------------------------------------- ikona i menu

$script:Ikona = New-Object System.Windows.Forms.NotifyIcon
$script:Ikona.Icon = Ikona-Nadzorcy
$script:Ikona.Text = "MegaRuchacz - zbieram dane"
$script:Ikona.Visible = $true

# Dymki (powiadomienia Windows) wylaczone 28.09.2026 na prosbe uzytkownika - wyskakiwaly
# przy kazdym alarmie. Alarm nie znika w cisze: zostaje w podpowiedzi ikony (najechanie
# myszka), w czerwonej karcie na gorze okna i w dzienniku. $true przywraca dymki.
$script:PokazujDymki = $false

function Pokaz-Dymek([string]$tytul, [string]$tresc) {
  if (-not $script:PokazujDymki) {
    try { Notuj "dymek pominiety (dymki wylaczone): $tytul" } catch { Zanotuj-Wywrotke "wpis o pominietym dymku" $_ }
    return
  }
  try {
    $script:Ikona.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Warning
    $script:Ikona.BalloonTipTitle = Skroc-Na-Dymek $tytul $MAX_TYTUL "[skrocone] "
    $script:Ikona.BalloonTipText  = Skroc-Na-Dymek $tresc $MAX_TRESC "[skrocone - calosc w oknie MegaRuchacza] "
    $script:Ikona.ShowBalloonTip(20000)
  } catch { Zanotuj-Wywrotke "pokazanie dymka" $_ }
}
$script:Dymek = { param($tytul, $tresc) Pokaz-Dymek $tytul $tresc }

function Nowa-Pozycja([string]$napis, $akcja) {
  $p = New-Object System.Windows.Forms.ToolStripMenuItem
  $p.Text = $napis
  $p.Add_Click($akcja)
  return $p
}

# W MENU NIE MA JUZ "Uruchom cykl teraz". Ta pozycja wydawala setki tysiecy
# tokenow jednym kliknieciem, bez slowa o koszcie i bez pytania. Czytanie rozmow
# da sie odpalic wylacznie przyciskiem w oknie, ktory pokazuje szacunek i pyta -
# jedna droga do wydawania pieniedzy, i to ta, ktora ostrzega.
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Items.Add((Nowa-Pozycja "Otwórz okno MegaRuchacza" { Pokaz-Okno })) | Out-Null
# Recznemu przeliczeniu zostaje miejsce TUTAJ, a nie w oknie: okno liczy samo,
# ale kto wlasnie cos poprawil (np. skrocil CLAUDE.md), chce zobaczyc skutek
# natychmiast, nie po kwadransie.
#
# Ta pozycja SAMA LICZY i nic nie uruchamia - swiadomie nie wola Dozoru, bo
# dozor przy okazji startuje czytanie rozmow, gdy wypada na nie pora. Pozycja
# menu nazwana "przelicz liczby" nie ma prawa wydac ani jednego tokena.
$menu.Items.Add((Nowa-Pozycja "Przelicz liczby teraz (nic nie kosztuje)" {
  try {
    # P21: w tle - ikona i otwarte okno nie staja na czas liczenia.
    $k = Przelicz-W-Tle 'Zbierz-Wszystko $true $true'
    $script:StanKawalkow["rozbicie"].Czas = $null
    if (-not $k.Po) {
      $k.Po = {
        param($k)
        if (($k.Stan -eq "ok") -or ($k.Stan -eq "uwaga")) { Pokaz-Dymek "MegaRuchacz: przeliczone" "Liczby sa swieze. Kliknij ikone, zeby je zobaczyc." }
        else { Pokaz-Dymek "MegaRuchacz: nie przeliczylem" "Nie udalo sie przeliczyc liczb: $($k.Powod)" }
      }
    }
  } catch {
    Zanotuj-Wywrotke "reczne przeliczenie z menu" $_
    Pokaz-Dymek "MegaRuchacz: nie przeliczylem" "Nie udalo sie przeliczyc liczb: $($_.Exception.Message)"
  }
})) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
$menu.Items.Add((Nowa-Pozycja "Zamknij MegaRuchacza (ikona zniknie)" {
  Notuj "nadzorca zakonczony z menu - do najblizszego zalogowania nikt nie pilnuje cyklu"
  $script:Ikona.Visible = $false
  [System.Windows.Forms.Application]::Exit()
})) | Out-Null
$script:Ikona.ContextMenuStrip = $menu
$script:Ikona.Add_MouseClick({
  param($nadawca, $e)
  if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Pokaz-Okno }
})

# ------------------------------------------------------------------ zegar dozoru

# Pierwszy przebieg po 5 sekundach, a nie od razu: ikona ma sie pojawic
# natychmiast, a nie po kilkunastu sekundach liczenia rachunku.
$script:Pierwszy = $true
$script:Zegar = New-Object System.Windows.Forms.Timer
$script:Zegar.Interval = 5000
$script:Zegar.Add_Tick({
  if ($script:Pierwszy) {
    $script:Pierwszy = $false
    $script:Zegar.Interval = [math]::Max(1, $Minut) * 60 * 1000
  }
  try {
    # $zSieci = $true: po nowsza wersje zaglada dozor, bo tu nikt nie czeka
    # przed ekranem. Od P21 dane licza sie w watku w tle (git fetch potrafi trwac
    # do 25 s, a otwarte okno ani ikona nie maja wtedy stawac); decyzje, alarmy
    # i odmalowanie otwartego okna - w Po-Dozorze, gdy dane przyjda.
    Rusz-Dozor
  } catch { Zanotuj-Wywrotke "przebieg dozoru" $_ }
})
$script:Zegar.Start()

# Wywrotki z poprzedniego uruchomienia - nadzorca, ktory sie wczoraj wywrocil,
# ma o tym powiedziec, a nie udawac, ze wstal czysty. Zostaja tez w pamieci
# sesji, zeby okno pokazalo je jako zolta karte w sekcji problemow.
try {
  $stare = Odbierz-Wywrotki
  $script:Wywrotki = @($stare)
  if ($script:Wywrotki.Count -gt 0) {
    $ogon = ""
    if ($script:Wywrotki.Count -gt 1) { $ogon = " (i jeszcze $($script:Wywrotki.Count - 1))" }
    Pokaz-Dymek "MegaRuchacz: nadzorca wywrocil sie poprzednio" (
      "$($script:Wywrotki[0])${ogon}. Kliknij ikone - w oknie jest komplet. " +
      "Dziennik: $(Join-Path $KatalogDomowy '.claude\.megaruchacz-zasobnik.log')")
  }
} catch { Zanotuj-Wywrotke "odczyt wywrotek przy starcie" $_ }

Notuj "nadzorca wystartowal (zrodlo $Zrodlo, dozor co $Minut min)"
Zapisz-Obecnosc "start"
if ($Pokaz) { Pokaz-Okno }

try {
  [System.Windows.Forms.Application]::Run()
} catch {
  # Wywrotka calego programu. Slad idzie na dysk, zeby nastepny start mogl
  # o niej zameldowac - nadzorca ginacy po cichu bylby dokladnie tym samym
  # problemem, dla ktorego rozwiazania powstal.
  Zanotuj-Wywrotke "petla glowna nadzorcy" $_
  Zapisz-Obecnosc "wywrotka"
} finally {
  try { $script:Ikona.Visible = $false; $script:Ikona.Dispose() }
  catch { Notuj "nie udalo sie sprzatnac ikony przy zamykaniu" }
}
