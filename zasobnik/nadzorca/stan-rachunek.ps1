# zasobnik\nadzorca\stan-rachunek.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Rachunek za pamiec - wywolania
# narzedzia\koszt-pamieci.ps1 w osobnym procesie: -Rozbicie (Rachunek-Rozbicie),
# -Dane (Linia-Rachunku), -Warstwy (Warstwy-Pamieci), -Start (Pomiar-Startu) - i
# otwarcie okna rozmowy w jednej mierze (Opis-Startu, Procent-Ludzko,
# Procent-Drobny, Proc-Sesji, Jak-Sesji).
# Skad wolane: stan-zbieranie.ps1 (Linia-Rachunku), kroki w tle w w-tle.ps1,
# tryb -Raport w nadzorca.ps1, karty i sekcje okna. Wczytuje go stan-nadzorcy.ps1
# kropka - same definicje.

# ------------------------------------------------------------ rachunek za pamiec

# Rozbicie na trzy kubelki - JEDEN i ten sam wydruk, ktory uzytkownik zna
# z narzedzia\koszt-pamieci.ps1 -Rozbicie. Drugiego renderowania tu nie ma
# i nie ma go byc: dwie kopie tego samego rachunku rozjechalyby sie przy
# pierwszej poprawce. -Projekt nie podajemy z rozmyslem - nadzorca nie siedzi
# w zadnym projekcie, a skrypt mierzy wtedy ladunki z szablonow w $Zrodlo,
# ktore i tak sa te same, co wdrozone w projektach.
function Rachunek-Rozbicie {
  $skrypt = Join-Path $script:NadzZrodlo "narzedzia\koszt-pamieci.ps1"
  $r = Wolaj-Skrypt $skrypt @("-KatalogDomowy", ('"' + $script:NadzDom + '"'), "-Zrodlo", ('"' + $script:NadzZrodlo + '"'), "-Rozbicie", "-Zwykly") 120
  if (-not $r.ok) {
    return ,@("  NIE UDALO SIE POLICZYC RACHUNKU: $($r.powod)",
             "  sprobuj recznie: powershell -ExecutionPolicy Bypass -File ${skrypt} -Rozbicie")
  }
  $linie = @(($r.tekst -split '\r?\n') | ForEach-Object { "$_".TrimEnd() })
  while ($linie.Count -gt 0 -and $linie[-1] -eq "") { $linie = $linie[0..($linie.Count - 2)] }
  if ($linie.Count -lt 2) {
    $powod = $r.powod
    if (-not $powod) { $powod = "skrypt nic nie wypisal (kod $($r.kod))" }
    return ,@("  RACHUNEK PUSTY: $powod")
  }
  return ,$linie
}

# Rachunek za pamiec jednym wywolaniem: narzedzia\koszt-pamieci.ps1 -Dane oddaje
# linie (te sama, co -Zwiezle), alarmy z waga i okresem, ocene kosztu nauki
# (zwykly dzien czy nadrabianie) i dni do wykresu - w liniach "klucz: wartosc".
# Kod wyjscia: 0 = nic nie jest ucinane i zaden CZERWONY prog nie przekroczony,
# 1 = jedno z dwojga; zolta informacja kodu nie podnosi. Progi siedza
# w koszt-pamieci.ps1 razem z uzasadnieniem - nadzorca ich NIE powtarza, bo drugi
# komplet liczb zaczalby klamac przy pierwszej zmianie tamtych.
function Linia-Rachunku {
  $skrypt = Join-Path $script:NadzZrodlo "narzedzia\koszt-pamieci.ps1"
  $r = Wolaj-Skrypt $skrypt @("-KatalogDomowy", ('"' + $script:NadzDom + '"'), "-Zrodlo", ('"' + $script:NadzZrodlo + '"'), "-Dane", "-Zwykly") 120
  $w = [pscustomobject]@{ Linia = $null; Kod = $null; Powod = ""; Klucze = [ordered]@{} }
  if (-not $r.ok) {
    $w.Powod = $r.powod
    return $w
  }
  $w.Klucze = Klucze-Z-Tekstu $r.tekst
  $w.Kod = $r.kod
  if ($w.Klucze.Contains("linia")) { $w.Linia = "$($w.Klucze['linia'])".Trim() }
  if (-not $w.Linia) {
    $w.Powod = "koszt-pamieci.ps1 -Dane nie oddal linii rachunku (kod $($r.kod))"
    if ($r.powod) { $w.Powod = $w.Powod + " - " + $r.powod }
  }
  return $w
}

# Warstwy pamieci dla zakladki "Warstwy pamieci": narzedzia\koszt-pamieci.ps1
# -Warstwy oddaje JSON z lista warstw (kiedy sie wczytuje, stala czy tymczasowa,
# kto pisze, ile znakow, czy plik jest). Lista warstw zyje TYLKO tam - tutaj
# jest wywolanie i odczyt, bez drugiej kopii sciezek. Nieudane wywolanie albo
# smiec zamiast JSON-u to Powod, ktory okno pokazuje zamiast pustej listy.
function Warstwy-Pamieci {
  $w = [pscustomobject]@{ Warstwy = @(); Uwagi = @(); Powod = ""; Wygenerowano = ""; TrybGlobalny = $null; Projekt = "" }
  $skrypt = Join-Path $script:NadzZrodlo "narzedzia\koszt-pamieci.ps1"
  $r = Wolaj-Skrypt $skrypt @("-KatalogDomowy", ('"' + $script:NadzDom + '"'), "-Zrodlo", ('"' + $script:NadzZrodlo + '"'), "-Warstwy") 120
  if (-not $r.ok) {
    $w.Powod = $r.powod
    return $w
  }
  $tekst = "$($r.tekst)".Trim()
  if (-not $tekst) {
    $w.Powod = "koszt-pamieci.ps1 -Warstwy nic nie wypisal (kod $($r.kod))"
    if ($r.powod) { $w.Powod = $w.Powod + " - " + $r.powod }
    return $w
  }
  $j = $null
  try { $j = $tekst | ConvertFrom-Json }
  catch {
    Zanotuj-Wywrotke "odczyt listy warstw pamieci" $_
    $w.Powod = "koszt-pamieci.ps1 -Warstwy oddal cos, co nie jest JSON-em: $($_.Exception.Message)"
    return $w
  }
  if (-not $j -or ($null -eq $j.Warstwy)) {
    $w.Powod = "w odpowiedzi koszt-pamieci.ps1 -Warstwy nie ma listy warstw (kod $($r.kod))"
    return $w
  }
  $w.Warstwy = @($j.Warstwy)
  $w.Uwagi = @($j.Uwagi | Where-Object { $_ })
  $w.Wygenerowano = "$($j.Wygenerowano)"
  $w.TrybGlobalny = $j.TrybGlobalny
  $w.Projekt = "$($j.Projekt)"
  if ($r.kod -ne 0) {
    $w.Uwagi += "koszt-pamieci.ps1 -Warstwy skonczyl z kodem $($r.kod)$(if ($r.powod) { ': ' + $r.powod })"
  }
  return $w
}

# OTWARCIE SESJI - CALOSC I UDZIAL MEGARUCHACZA. Calosci nie zgadujemy:
# narzedzia\koszt-pamieci.ps1 -Start mierzy ja z transkryptow Claude Code
# (pierwsza odpowiedz modelu w sesji, pole usage) i oddaje JSON z mediana
# i liczba sesji, a obok czesc MegaRuchacza z tego samego rachunku, co reszta
# okna. Tutaj tylko wywolanie i odczyt. Nieudany pomiar to Powod, ktory okno
# pokazuje slowami "nie zmierzono, bo ..." - nigdy zero i nigdy 0%.
function Pomiar-Startu {
  $w = [pscustomobject]@{
    Powod = ""; Sesje = $null; Workerzy = $null; Metoda = ""; Katalog = ""; DniWstecz = $null
    MrSesja = $null; MrStart = $null; MrWiadomosc = $null; MrWorker = $null; Wygenerowano = ""
  }
  $skrypt = Join-Path $script:NadzZrodlo "narzedzia\koszt-pamieci.ps1"
  $r = Wolaj-Skrypt $skrypt @("-KatalogDomowy", ('"' + $script:NadzDom + '"'), "-Zrodlo", ('"' + $script:NadzZrodlo + '"'), "-Start") 120
  if (-not $r.ok) { $w.Powod = "pomiar się nie uruchomił ($($r.powod))"; return $w }
  $tekst = "$($r.tekst)".Trim()
  if (-not $tekst) {
    $w.Powod = "koszt-pamieci.ps1 -Start nic nie wypisał (kod $($r.kod))"
    if ($r.powod) { $w.Powod = $w.Powod + " - " + $r.powod }
    return $w
  }
  $j = $null
  try { $j = $tekst | ConvertFrom-Json }
  catch {
    Zanotuj-Wywrotke "odczyt pomiaru otwarcia okna rozmowy" $_
    $w.Powod = "koszt-pamieci.ps1 -Start oddał coś, co nie jest JSON-em: $($_.Exception.Message)"
    return $w
  }
  $w.Powod = "$($j.Powod)"
  $w.Sesje = $j.Sesje
  $w.Workerzy = $j.Workerzy
  $w.Metoda = "$($j.Metoda)"
  $w.Katalog = "$($j.Katalog)"
  $w.DniWstecz = $j.DniWstecz
  $w.Wygenerowano = "$($j.Wygenerowano)"
  $w.MrSesja = $j.MegaRuchaczSesja
  $w.MrStart = $j.MegaRuchaczStart
  $w.MrWiadomosc = $j.MegaRuchaczWiadomosc
  $w.MrWorker = $j.MegaRuchaczWorker
  if ((-not $w.Powod) -and ((-not $w.Sesje) -or ($null -eq $w.Sesje.Mediana))) {
    $w.Powod = "pomiar nie oddał mediany z rozmów (kod $($r.kod))"
  }
  return $w
}

# "3%" albo "mniej niż 1%" - zero procent czytaloby sie jak "nic", a to nie to samo.
function Procent-Ludzko([double]$czesc, [double]$calosc) {
  if ($calosc -le 0) { return "?" }
  $p = 100.0 * $czesc / $calosc
  if (($p -gt 0) -and ($p -lt 1)) { return "mniej niż 1%" }
  return "$([int][math]::Round($p))%"
}

# To samo, ale drobne kawalki pokazuje dokladniej (28.09.2026, P14): na
# Przegladzie kazda liczba MegaRuchacza stoi w JEDNEJ mierze - procent jednego
# otwarcia sesji - wiec "przy kazdej wiadomosci +115" nie moze byc wrzucone do
# worka "mniej niz 1%" razem z czyms dziesiec razy wiekszym. Od 10% w gore -
# calosci, ponizej - jedno miejsce po przecinku (skladnik 3,6% pod wierszem
# "razem 4%" nie wyglada wtedy jak ta sama liczba drugi raz), ponizej 0,1% -
# "mniej niz 0,1%". Zero procent nie powstaje nigdy dla niezerowej czesci.
function Procent-Drobny([double]$czesc, [double]$calosc) {
  if ($calosc -le 0) { return "?" }
  $p = 100.0 * $czesc / $calosc
  if ($p -ge 10) { return "$([int][math]::Round($p))%" }
  if ($p -le 0) { return "0%" }
  if ($p -lt 0.1) { return "mniej niż 0,1%" }
  return ([math]::Round($p, 1).ToString("0.0", [System.Globalization.CultureInfo]::GetCultureInfo("pl-PL")) + "%")
}

# Pomiar ubrany w zdania: jedna struktura dla karty w oknie i dla wydruku -Raport.
# Zmierzone = $false znaczy, ze calosci nie ma - wtedy Powod mowi dlaczego,
# a liczby calosci i procentu w ogole nie powstaja.
function Opis-Startu($p) {
  $o = [pscustomobject]@{
    Zmierzone = $false; Powod = ""; Razem = $null; Mr = $null; Cc = $null
    MrProc = ""; CcProc = ""; UdzialMr = $null; Sesji = 0; Podstawa = ""; Portfel = ""; Zakres = ""
    Worker = $null; WorkerZdanie = ""
  }
  if (-not $p) { $o.Powod = "pomiaru nie było"; return $o }
  if ($null -ne $p.MrSesja) { $o.Mr = [long]$p.MrSesja }
  if ($p.Powod) { $o.Powod = $p.Powod; return $o }
  if ($null -eq $o.Mr) { $o.Powod = "rachunek nie podał części MegaRuchacza"; return $o }
  $o.Zmierzone = $true
  $o.Razem = [long]$p.Sesje.Mediana
  $o.Sesji = [int]$p.Sesje.Liczba
  $o.Cc = [long][math]::Max(0, $o.Razem - $o.Mr)
  $o.UdzialMr = [double]$o.Mr / [double][math]::Max(1, $o.Razem)
  $o.MrProc = Procent-Ludzko $o.Mr $o.Razem
  $o.CcProc = Procent-Ludzko $o.Cc $o.Razem
  # Podstawa i zakres po ludzku (P15, 28.09.2026): czytelnik nie wie, co to
  # transkrypt ani mediana - wie, ile rozmow mial. Metoda stoi w Szczegolach.
  $o.Podstawa = "Policzone z Twoich ostatnich $($o.Sesji) $(Odmiana $o.Sesji 'rozmowy' 'rozmów' 'rozmów') z Claude (z $($p.DniWstecz) dni)."
  if (($null -ne $p.Sesje.Min) -and ($null -ne $p.Sesje.Max)) {
    $o.Zakres = "Najmniejsza zaczynała się od ~$(Okolo $p.Sesje.Min), największa od ~$(Okolo $p.Sesje.Max) tokenów."
  }
  # Zdanie o portfelu skrocone 28.09.2026 (P15). Uzytkownik: "ma byc jasno jak
  # dla laika". Wczesniejsze wyjasnienie pamieci modelu i bufora wymagalo
  # wiedzy, ktorej laik nie ma; zostaje jedna rzecz, ktora laik ma zrozumiec:
  # wylaczenie MegaRuchacza oszczedza tylko niebieski kawalek paska.
  $o.Portfel = "Gdyby wyłączyć MegaRuchacza, każda rozmowa i tak zaczynałaby się od szarej części paska - oszczędzisz najwyżej niebieski kawałek."
  $wk = $p.Workerzy
  if ($wk -and ($null -ne $wk.Mediana) -and ($wk.Liczba -gt 0)) {
    $mrW = $null
    if ($null -ne $p.MrWorker) { $mrW = [long]$p.MrWorker }
    $o.Worker = [pscustomobject]@{ Razem = [long]$wk.Mediana; Mr = $mrW; Liczba = [int]$wk.Liczba }
    $o.WorkerZdanie = "Start jednego workera: ~$(Okolo $wk.Mediana) tokenów"
    if ($null -ne $mrW) { $o.WorkerZdanie += ", z tego MegaRuchacz ~$(Okolo $mrW) ($(Procent-Ludzko $mrW $wk.Mediana))" }
    $o.WorkerZdanie += " - mediana z $($wk.Liczba) $(Odmiana ([int]$wk.Liczba) 'ostatniego workera' 'ostatnich workerów' 'ostatnich workerów')."
  } else {
    $pw = "brak danych"
    if ($wk -and $wk.Powod) { $pw = $wk.Powod }
    $o.WorkerZdanie = "Start jednego workera: nie zmierzono, bo $pw."
  }
  return $o
}

# JEDNA MIARA WSZEDZIE (P15, 28.09.2026): kazda liczba tokenow MegaRuchacza
# stoi obok jako procent jednego otwarcia sesji, bo "40 477 tokenow" laikowi
# nic nie mowi, a "jak 21% jednej sesji" mowi wszystko. Bez zmierzonego
# otwarcia procentu nie ma - oddajemy pusty tekst i wolajacy pokazuje wtedy
# same tokeny z powodem, nigdy zgadniety procent.
function Proc-Sesji($tokeny, $o) {
  if (($null -eq $tokeny) -or (-not $o) -or (-not $o.Zmierzone) -or ($o.Razem -le 0)) { return "" }
  return (Procent-Drobny ([double]$tokeny) ([double]$o.Razem))
}

function Jak-Sesji($tokeny, $o) {
  $p = Proc-Sesji $tokeny $o
  if (-not $p) { return "" }
  return "jak $p otwarcia okna rozmowy"
}

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["rachunek"] = $true
