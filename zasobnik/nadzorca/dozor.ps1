# zasobnik\nadzorca\dozor.ps1 - czesc zasobnik\nadzorca.ps1 (patrz BUDOWA
# w jego naglowku). Dozor: jeden przebieg (Dozor - dane i decyzje naraz, tryb
# -Raz), decyzje na gotowych danych (Dozor-Po-Danych: cykl wiedzy, skille, alarmy,
# slad obecnosci), dozor co kwadrans w tle (Rusz-Dozor -> Po-Dozorze; kroki
# i watki sa w w-tle.ps1) i podpowiedz przy ikonie (Podpowiedz).
# Skad wolane: tryb -Raz i zegar dozoru w nadzorca.ps1, Po-Kroku w w-tle.ps1
# (Podpowiedz). Wczytuje go nadzorca.ps1 kropka PRZED trybami bez GUI - tu sa
# same definicje.

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
  # Cykl wiedzy - to jest teraz GLOWNY wyzwalacz, niezalezny od hookow.
  try {
    $czy = Czy-Ruszac-Cykl
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
    $cs = Czy-Sprawdzac-Skille
    if ($cs.Ruszac) {
      Notuj "dozor: sprawdzam skille ($($cs.Powod))"
      if (-not (Ruszaj-Skille)) { Zanotuj-Wywrotke "start codziennego sprawdzenia skilli" "Odpal-W-Tle nie wystartowal narzedzia\skille.ps1" }
    } else {
      Notuj "dozor: skilli nie sprawdzam - $($cs.Powod)"
    }
  } catch { Zanotuj-Wywrotke "decyzja o sprawdzeniu skilli" $_ }

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
  Po-Kroku "dane"
  # P26: liczby "dzis" rosna w ciagu dnia - przy otwartym oknie odswiezaja sie razem
  # z dozorem (co kwadrans), tak jak obiecuje podtytul okna.
  try {
    if ($script:Okno -and (-not $script:Okno.IsDisposed) -and $script:Okno.Visible -and (Nieswiezy-Kawalek "koszt")) { [void](Rusz-Krok "koszt") }
  } catch { Zanotuj-Wywrotke "odswiezenie prawdziwego kosztu po dozorze" $_ }
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
  if ($t.Length -gt 63) { $t = $t.Substring(0, 63) }
  return $t
}

# Znacznik dla nadzorca.ps1: ten plik wczytal sie do konca.
$script:ModulyOkna["dozor"] = $true
