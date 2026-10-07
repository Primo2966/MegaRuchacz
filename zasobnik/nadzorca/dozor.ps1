# zasobnik\nadzorca\dozor.ps1 - czesc zasobnik\nadzorca.ps1 (patrz BUDOWA
# w jego naglowku). Dozor: jeden przebieg (Dozor - dane i decyzje naraz, tryb
# -Raz), decyzje na gotowych danych (Dozor-Po-Danych: cykl wiedzy i skille - tylko
# z ich modulem w rejestrze instalacji, przypomnienia z terminem, alarmy, slad obecnosci), dozor co kwadrans
# w tle (Rusz-Dozor -> Po-Dozorze; kroki
# i watki sa w w-tle.ps1), podpowiedz przy ikonie (Podpowiedz) i aktualizacja
# automatyczna MegaRuchacza (Zaplanuj-Aktualizacje -> Ruszaj-Aktualizacje: ~1 min po
# starcie i co 60 min narzedzia\aktualizuj-megaruchacza.ps1 w tle; alarm o jej ciszy
# w stan-zbieranie.ps1 Alarm-Aktualizacji).
# Skad wolane: tryb -Raz i zegar dozoru w nadzorca.ps1, Po-Kroku w w-tle.ps1
# (Podpowiedz). Wczytuje go nadzorca.ps1 kropka PRZED trybami bez GUI - tu sa
# same definicje i stale.

# -------------------------------------------------------------------- dozor

# Jeden przebieg dozoru: zebrac stan, ruszyc cykl jesli trzeba, wystrzelic
# alarmy, zostawic slad "bylem tu". Wolany z zegara co $Minut i raz przy starcie.
# $pokazDymek to skrypt-blok przyjmujacy tytul i tresc - dzieki temu ten sam
# dozor dziala z ikona w zasobniku i bez niej (tryb -Raz).
#
# $zSieci: to DOZOR zaglada po nowsza wersje, a nie okno. Pobranie potrafi trwac
# kilkanascie sekund, a okno ma sie otwierac natychmiast - wiec siec obslugujemy
# tam, gdzie nikt nie czeka. Samo pobranie i tak jest dlawione do raz na pol
# godziny wewnatrz Stan-Wersji.
function Dozor($pokazDymek, [bool]$zKolejka, [bool]$zSieci) {
  $d = Zbierz-Wszystko $zSieci $zKolejka
  Dozor-Po-Danych $d $pokazDymek
  return $d
}

# Druga polowa dozoru - decyzje na gotowych danych. Osobno od P21: w ikonie dane
# licza sie w watku w tle (Rusz-Dozor), a decyzje zapadaja tu, w watku okna,
# gdy dane przyjda - w tej samej kolejnosci co dotad.
function Dozor-Po-Danych($d, $pokazDymek) {
  # P59d: nauka tylko z modulem Wiedza, skille tylko z modulem Skille - decyduja
  # Czy-Ruszac-Cykl i Czy-Sprawdzac-Skille na odczycie rejestru z tego samego przebiegu.
  $inst = $null
  if ($d) { $inst = $d.Instalacja }
  # Cykl wiedzy - to jest teraz GLOWNY wyzwalacz, niezalezny od hookow.
  try {
    $czy = Czy-Ruszac-Cykl $inst
    if ($czy.Ruszac) {
      Notuj "dozor: ruszam cykl wiedzy ($($czy.Powod))"
      $poszlo = Ruszaj-Cykl
      if (-not $poszlo) {
        & $pokazDymek "MegaRuchacz: nie udalo sie ruszyc cyklu" (
          "Proba startu narzedzia\cykl-dzienny.ps1 nie powiodla sie. " +
          "Uruchom recznie: powershell -ExecutionPolicy Bypass -File $Zrodlo\narzedzia\cykl-dzienny.ps1")
      }
    } else {
      Notuj "dozor: cyklu nie ruszam - $($czy.Powod)"
    }
  } catch { Zanotuj-Wywrotke "decyzja o starcie cyklu" $_ }

  # Polecane skille (P18) - raz na dobe sprawdzenie i pobranie nowszych wersji,
  # w tle i bez okna. Pierwszy przebieg na maszynie tylko spisuje, co jest.
  try {
    $cs = Czy-Sprawdzac-Skille $inst
    if ($cs.Ruszac) {
      Notuj "dozor: sprawdzam skille ($($cs.Powod))"
      if (-not (Ruszaj-Skille)) { Zanotuj-Wywrotke "start codziennego sprawdzenia skilli" "Odpal-W-Tle nie wystartowal narzedzia\skille.ps1" }
    } else {
      Notuj "dozor: skilli nie sprawdzam - $($cs.Powod)"
    }
  } catch { Zanotuj-Wywrotke "decyzja o sprawdzeniu skilli" $_ }

  # Przypomnienia z terminem (2026-10-05) - przy starcie i co godzine 8-20; baza, bez
  # modulu w rejestrze. Co uruchomic i co pokazac, rozstrzyga zasobnik\terminy.ps1.
  try {
    $ct = Czy-Sprawdzac-Terminy
    if ($ct.Ruszac) {
      Notuj "dozor: sprawdzam przypomnienia z terminem ($($ct.Powod))"
      if (-not (Ruszaj-Terminy)) { Zanotuj-Wywrotke "start sprawdzenia przypomnien" "Odpal-W-Tle nie wystartowal zasobnik\terminy.ps1" }
    } else {
      Notuj "dozor: przypomnien nie sprawdzam - $($ct.Powod)"
    }
  } catch { Zanotuj-Wywrotke "decyzja o sprawdzeniu przypomnien" $_ }

  # Alarmy - jeden na sprawe na dobe, zeby nie uczyly ignorowania.
  foreach ($a in @($d.Alarmy)) {
    if (Alarm-Juz-Byl $a.Temat) { Notuj "alarm [$($a.Temat)] juz dzis byl - nie powtarzam"; continue }
    & $pokazDymek $a.Tytul $a.Tresc
    Notuj "ALARM [$($a.Temat)] $($a.Tytul) :: $($a.Tresc)"
    Odnotuj-Alarm $a.Temat
  }

  Zapisz-Obecnosc "dozor"
}

# Dozor co kwadrans: dane w tle, decyzje po powrocie (Dozor-Po-Danych). Gdy
# poprzedni przebieg jeszcze trwa, ten jest pomijany - dwa naraz nie maja sensu.
function Rusz-Dozor {
  # Zegar aktualizacji wstaje przy pierwszym dozorze (5 s po starcie ikony) - tylko w ikonie,
  # nie w trybach -Raz/-Raport, ktore koncza sie po jednym przebiegu.
  try { Zaplanuj-Aktualizacje } catch { Zanotuj-Wywrotke "zegar aktualizacji automatycznej" $_ }
  if (Krok-Trwa $script:KrokDozoru) {
    Notuj "dozor: poprzedni przebieg jeszcze trwa (od $($script:KrokDozoru.Od)) - ten pomijam"
    return
  }
  $k = Nowy-Krok "dozor" "" "Dozór" "dane" $true $LIMIT_DOZORU
  $k.Po = { param($k) Po-Dozorze $k }
  $script:KrokDozoru = $k
  [void]$script:KolejkaKrokow.Add($k)
  Wlacz-Zegar-Krokow
  Obsluz-Kroki
}

function Po-Dozorze($k) {
  if (($k.Stan -eq "blad") -or ($k.Stan -eq "czas")) {
    Zanotuj-Wywrotke "przebieg dozoru" $k.Powod
    return
  }
  $d = $k.Wynik
  try { Dozor-Po-Danych $d $script:Dymek } catch { Zanotuj-Wywrotke "przebieg dozoru (decyzje)" $_ }
  $script:Dane = $d
  $script:DaneCzas = [datetime]::Now
  $script:DaneBlad = $null
  # P59d: instalacja mogla sie zmienic (przycisk "Zmień instalację") - zakladki za nia
  try { if ($d) { Ustaw-Instalacje-Okna $d.Instalacja } } catch { Zanotuj-Wywrotke "zakladki wedlug rejestru instalacji (dozor)" $_ }
  Po-Kroku "dane"
  # P26: liczby "dzis" rosna w ciagu dnia - przy otwartym oknie odswiezaja sie razem
  # z dozorem (co kwadrans), tak jak obiecuje podtytul okna.
  try {
    if ($script:Okno -and (-not $script:Okno.IsDisposed) -and $script:Okno.Visible -and (Nieswiezy-Kawalek "koszt")) { [void](Rusz-Krok "koszt") }
  } catch { Zanotuj-Wywrotke "odswiezenie prawdziwego kosztu po dozorze" $_ }
}

# ------------------------------------------- aktualizacja automatyczna (2026-10-07)
# Decyzja uzytkownika: aktualizacja MegaRuchacza zawsze sama, bez klikania - przy starcie
# nadzorcy (= zalogowanie) i potem okresowo. Cala robota (pobranie, naniesienie, restart
# nadzorcy) jest w narzedzia\aktualizuj-megaruchacza.ps1; tu tylko zegar i start w tle.
# Pierwszy raz po minucie, nie od razu: zaraz po zalogowaniu dysk i siec maja co robic,
# a pierwszy dozor (5 s po starcie) liczy rachunek - aktualizacja nie ma zwalniac logowania.
# Potem co 60 min: tak samo czesto zaglada do sieci hook straznika (dlawik 60 min
# w Odswiez-Zrodlo), a nowe wersje wychodza najwyzej kilka razy dziennie.
$SEKUNDY_DO_PIERWSZEJ_AKTUALIZACJI = 60
$MINUT_MIEDZY_AKTUALIZACJAMI = 60
$script:ZegarAutoAktualizacji = $null

function Skrypt-Aktualizacji { return (Join-Path $script:NadzZrodlo "narzedzia\aktualizuj-megaruchacza.ps1") }

# Slady "bylem tu" w pliku stanu nadzorcy: zegar wstal (aktualizacja.zaplanowana) i odpala
# (aktualizacja.zlecona). Ich nieswiezosc przy zywym nadzorcy to alarm (Alarm-Aktualizacji).
function Odnotuj-Aktualizacje([string]$klucz) {
  if ($script:NadzProba) { return }
  try { Dopisz-Klucze $script:NadzPlikStanu @{ "aktualizacja.$klucz" = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') } }
  catch { Zanotuj-Wywrotke "slad aktualizacji ($klucz) w pliku stanu nadzorcy" $_ }
}

function Zaplanuj-Aktualizacje {
  if ($script:ZegarAutoAktualizacji) { return }
  $script:ZegarAutoAktualizacji = New-Object System.Windows.Forms.Timer
  $script:ZegarAutoAktualizacji.Interval = [math]::Max(1, $SEKUNDY_DO_PIERWSZEJ_AKTUALIZACJI) * 1000
  $script:ZegarAutoAktualizacji.Add_Tick({
    $script:ZegarAutoAktualizacji.Interval = [math]::Max(1, $MINUT_MIEDZY_AKTUALIZACJAMI) * 60 * 1000
    try {
      if (-not (Ruszaj-Aktualizacje)) { Zanotuj-Wywrotke "start aktualizacji automatycznej" "Odpal-W-Tle nie wystartowal narzedzia\aktualizuj-megaruchacza.ps1" }
    } catch { Zanotuj-Wywrotke "start aktualizacji automatycznej" $_ }
  })
  $script:ZegarAutoAktualizacji.Start()
  Odnotuj-Aktualizacje "zaplanowana"
  Notuj "aktualizacja automatyczna: pierwsza za $SEKUNDY_DO_PIERWSZEJ_AKTUALIZACJI s, potem co $MINUT_MIEDZY_AKTUALIZACJAMI min"
}

# Start w tle przez conhost --headless (Odpal-W-Tle). Jeden przebieg naraz pilnuje sam skrypt
# (blokada) - start w trakcie dlugiej aktualizacji konczy sie u niego od razu, bez zapisu.
function Ruszaj-Aktualizacje {
  $skrypt = Skrypt-Aktualizacji
  $arg = '-Zrodlo "' + $script:NadzZrodlo + '" -KatalogDomowy "' + $script:NadzDom + '"'
  if ($script:NadzProba) {
    Write-Host "[proba] NIE startuje aktualizacji: powershell -File ${skrypt} ${arg}"
    return $true
  }
  if (-not (Test-Path -LiteralPath $skrypt)) { throw "nie ma $skrypt" }
  $poszlo = Odpal-W-Tle $skrypt $arg
  if ($poszlo) {
    Odnotuj-Aktualizacje "zlecona"
    Notuj "wystartowala aktualizacja automatyczna MegaRuchacza"
  }
  return $poszlo
}

# Podpowiedz przy ikonie. NotifyIcon.Text ma twardy sufit 63 znakow, wiec tekst
# jest budowany tak, zeby sie zmiescil, a nie ciety po fakcie.
function Podpowiedz($d) {
  $w = "?"
  if ($d -and $d.Wersja -and $d.Wersja.Lokalna) { $w = $d.Wersja.Lokalna }
  $c = "nauka ?"
  if ($d -and $d.Cykl) {
    $g = Godzin-Od-Cyklu $d.Cykl
    if ($null -eq $g) { $c = "nauka NIGDY" }
    elseif ($g -lt 24) { $c = "nauka dzis" }
    else { $c = "nauka stoi $([int]($g / 24)) dni" }
  }
  $a = ""
  if ($d -and (@($d.Alarmy).Count -gt 0)) { $a = " UWAGA x$(@($d.Alarmy).Count)" }
  $t = "MegaRuchacz ${w} - ${c}${a}"
  # P59d: bez modulu Wiedza nie ma nauki, o ktorej mozna by cos powiedziec
  if ($d -and -not (Modul-Jest $d.Instalacja "wiedza")) { $t = "MegaRuchacz ${w}${a}" }
  if ($t.Length -gt 63) { $t = $t.Substring(0, 63) }
  return $t
}

# Znacznik dla nadzorca.ps1: ten plik wczytal sie do konca.
$script:ModulyOkna["dozor"] = $true
