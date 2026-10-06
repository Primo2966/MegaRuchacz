# Wpisuje zasady pamieci MegaRuchacza do plikow instrukcji narzedzi AI uzytkownika - KAZDEGO
# narzedzia z listy narzedzi (kierownik-cele.ps1 Narzedzia-AI: Claude Code ~\.claude\CLAUDE.md,
# Codex ~\.codex\AGENTS.md, OpenCode ~\.config\opencode\AGENTS.md), ktore jest na tej maszynie
# (polecenie w PATH, slad w domu albo nasze bloki juz w jego pliku). Zadnego = nic do zrobienia
# i glosna UWAGA.
# Od P59a dwa bloki, kazdy dla wlasnego modulu instalatora (regula skladania: zasady-bloki.ps1):
#   lore    zasady-lore.md   -> <!-- MegaRuchacz:lore:start -->   ... <!-- MegaRuchacz:lore:koniec -->
#   wiedza  zasady-wiedza.md -> <!-- MegaRuchacz:wiedza:start --> ... <!-- MegaRuchacz:wiedza:koniec -->
# Zrodlo tresci: tylko to, co w pliku stoi pod linia-znacznikiem. Stary wspolny blok
# <!-- MegaRuchacz:start --> (do P59a) zamieniany jest na nowe NA SWOIM MIEJSCU - "Co wiem"
# nad nim i reszta pliku zostaja co do bajtu.
# Przy wlaczonym module wiedza kazdy plik dostaje tez pusty szkielet sekcji "## Co wiem", jesli
# jej nie ma (cykl wiedzy pisze fakty do kazdego pliku z ta sekcja); istniejacej nie ruszamy.
# Sekcja pusta (same naglowki - zakladana teraz albo zastana) dostaje tresc "Co wiem" z najbogatszego
# pliku z listy (kierownik-cele.ps1 Zrodlo-Co-Wiem) - wiedza ma byc ta sama w kazdym CLI. Sekcji
# z wpisami nie nadpisujemy; rozne sekcje w roznych plikach = UWAGA na koncu, bez scalania.
# Plik, ktorego narzedzie jeszcze nie ma, zaczyna sie od Tekst-Startowy: OpenCode - od tresci
# CLAUDE.md, ktory czytal dotad zamiast wlasnego; stara kopia dla opencode traci linie naglowka.
# Plik, ktory po zapisie przekroczylby limit narzedzia (Codex: 32 KiB), NIE jest zapisywany -
# ostrzezenie stoi w PIERWSZEJ linii wyjscia, kod 1. Tak samo zasiew "Co wiem" ponad limit - wtedy
# odpada sam zasiew (sekcja zostaje pusta), a reszta pliku jest zapisywana.
#
# Uzycie:
#   powershell -File C:\dev\claude-worker\narzedzia\wpisz-zasady.ps1
#                             bloki wedlug rejestru instalacji (~\.claude\mr\instalacja.json):
#                             modul wlaczony - blok wpisany albo odswiezony, wylaczony - zdjety;
#                             brak rejestru = oba bloki; rejestr nieczytelny = oba, nic nie zdejmuje
#     -Blok lore,wiedza       tylko te bloki (wpisz albo odswiez); pozostale zostaja, jakie sa
#     -Usun                   wycina bloki razem ze znacznikami (z -Blok - tylko te)
#     -Proba                  wypisuje, co by zrobil, ale nic nie zapisuje
#     -Zrodlo <katalog>       katalog glowny repo (domyslnie katalog nad narzedzia\)
#     -KatalogDomowy <kat>    wewnetrzne: podmiana bazy sciezek docelowych (testy)
#
# Reszta pliku - czyli wlasne zapiski uzytkownika - zostaje nietknieta. Przed kazda zmiana kopia.

param(
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [string]$KatalogDomowy = $HOME,
  [string[]]$Blok = @(),
  [switch]$Usun,
  [switch]$Proba
)

$Stempel = Get-Date -Format "yyyyMMdd-HHmmss"

# UTF-8 bez BOM przy zapisie, UTF-8 rzucajacy bledem przy odczycie -
# zepsute polskie znaki maja wywalic skrypt, a nie przejsc po cichu.
$Utf8Zapis  = New-Object System.Text.UTF8Encoding($false)
$Utf8Odczyt = New-Object System.Text.UTF8Encoding($false, $true)

$script:Bledy = 0
$script:Raport = @()

# Zapis odporny na zanik pradu i rozpoznawanie wyzerowanych plikow (awaria 2026-10-02:
# ten skrypt dokleil blok do CLAUDE.md, ktory po zaniku pradu mial w srodku same bajty 0x00).
$plikZapisu = Join-Path $PSScriptRoot "zapis-trwaly.ps1"
if (-not (Test-Path $plikZapisu)) { Write-Error "Nie ma $plikZapisu - bez niego nie zapisuje plikow zasad."; exit 1 }
. $plikZapisu
# Znaczniki, regula skladania blokow i odczyt rejestru instalacji - wspolne ze straznikiem.
$plikBlokow = Join-Path $PSScriptRoot "zasady-bloki.ps1"
if (-not (Test-Path $plikBlokow)) { Write-Error "Nie ma $plikBlokow - bez niego nie wiem, jak skladac bloki zasad."; exit 1 }
. $plikBlokow
# Lista narzedzi AI, poczatek pliku, szkielet "Co wiem", limit - wspolne ze straznikiem.
$plikCeli = Join-Path $PSScriptRoot "kierownik-cele.ps1"
if (-not (Test-Path $plikCeli)) { Write-Error "Nie ma $plikCeli - bez niego nie wiem, ktore narzedzia AI tu sa."; exit 1 }
. $plikCeli

function Czytaj($sciezka) {
  return [System.IO.File]::ReadAllText($sciezka, $Utf8Odczyt)
}

function Zapisz($sciezka, $tekst) {
  Zapisz-Trwale $sciezka $tekst $Utf8Zapis
}

function Wyzerowane-Pliki-Z($pliki) {
  $wynik = @()
  foreach ($p in $pliki) {
    $b = [System.IO.File]::ReadAllBytes($p)
    $zer = 0
    foreach ($x in $b) { if ($x -eq 0) { $zer++ } }
    $wynik += [pscustomobject]@{ Sciezka = $p; Zera = $zer; Rozmiar = $b.Length }
  }
  return ,$wynik
}

function Kopia-Zapasowa($sciezka) {
  $bak = "$sciezka.bak-$Stempel"
  Kopiuj-Trwale $sciezka $bak   # odmawia kopii pliku z bajtami 0x00
  return $bak
}

# Odczyt kontrolny po zapisie - najczestsza cicha wpadka na Windowsie to rozsypane polskie
# znaki, wiec porownujemy to, co wyszlo, z tym, co mialo wejsc: kazdy blok, ktory ma stac,
# stoi co do znaku, a po blokach zdjetych nie zostal ani jeden znacznik.
function Sprawdz-Zapis($plik, $nazwa, $bloki, $zdjete, [bool]$szkielet, [bool]$zasiew = $false) {
  try { $sprawdzony = Czytaj $plik }
  catch {
    Write-Host "BLAD  $nazwa - po zapisie $plik nie daje sie odczytac jako UTF-8" -ForegroundColor Red
    $script:Bledy++
    return $false
  }
  if ($sprawdzony.IndexOf([char]0xFFFD) -ge 0) {
    Write-Host "BLAD  $nazwa - w $plik siedza rozsypane znaki po zapisie" -ForegroundColor Red
    $script:Bledy++
    return $false
  }
  foreach ($b in $bloki) {
    if ($sprawdzony.IndexOf($b, [System.StringComparison]::Ordinal) -lt 0) {
      Write-Host "BLAD  $nazwa - blok w $plik nie zgadza sie z tym, co mialo byc zapisane" -ForegroundColor Red
      $script:Bledy++
      return $false
    }
  }
  foreach ($n in $zdjete) {
    foreach ($znacznik in (Znaczniki-Zasad $n)) {
      if ($sprawdzony.Contains($znacznik)) {
        Write-Host "BLAD  $nazwa - w $plik dalej siedzi znacznik $znacznik" -ForegroundColor Red
        $script:Bledy++
        return $false
      }
    }
  }
  if ($szkielet -and -not (Ma-Co-Wiem $sprawdzony)) {
    Write-Host "BLAD  $nazwa - po zapisie w $plik nie ma sekcji '## Co wiem'" -ForegroundColor Red
    $script:Bledy++
    return $false
  }
  if ($zasiew -and (Pusta-Co-Wiem $sprawdzony)) {
    Write-Host "BLAD  $nazwa - po zapisie sekcja '## Co wiem' w $plik jest nadal pusta (zasiew nie wszedl)" -ForegroundColor Red
    $script:Bledy++
    return $false
  }
  return $true
}

# --- jeden plik docelowy -----------------------------------------------------

# Ktore bloki maja w tym pliku stac, a ktore zniknac - wedlug trybu, w jakim skrypt wywolano.
# $obecne liczy stary wspolny blok za oba, wiec "-Blok lore" na starym bloku nie gubi wiedzy.
function Ktore-Bloki($obecne) {
  $wszystkie = @(Bloki-Zasad)
  $w = [pscustomobject]@{ Chciane = @(); Zdjac = @() }
  if ($Blok.Count -gt 0) {
    if ($Usun) {
      $w.Chciane = @($obecne | Where-Object { $Blok -notcontains $_ })
      $w.Zdjac = @($Blok)
    } else {
      $w.Chciane = @($wszystkie | Where-Object { ($obecne -contains $_) -or ($Blok -contains $_) })
    }
  } elseif ($Usun) {
    $w.Zdjac = $wszystkie
  } else {
    $w.Chciane = @($script:Chciane.Nazwy)
    if ($script:Chciane.Zdejmuj) { $w.Zdjac = @($wszystkie | Where-Object { $script:Chciane.Nazwy -notcontains $_ }) }
  }
  return $w
}

# Plan dla jednego narzedzia - bez zapisu. .Blad (powod, dla ktorego pliku nie ruszamy) albo .Nowy
# (tekst do zapisu; rowny .Stary = nic do zrobienia). .Limit - powod odmowy z sufitu albo $null,
# .OdmowaZasiewu - powod, dla ktorego pusta "Co wiem" nie dostala tresci (sufit), albo $null.
function Planuj-Plik($n) {
  $p = [pscustomobject]@{ N = $n; Nazwa = $n.Nazwa; Plik = $n.Sciezka; Istnieje = $false; Stary = ""; Nowy = ""; Co = ""
                          Tresci = [ordered]@{}; Zdjac = @(); Szkielet = $false; Blad = $null; Limit = $null; Start = $null
                          Zasiew = $null; OdmowaZasiewu = $null }
  $p.Istnieje = Test-Path -LiteralPath $n.Sciezka -PathType Leaf
  if ($p.Istnieje -and (Ma-Zera $n.Sciezka)) {
    $p.Blad = Opis-Wyzerowanych (Wyzerowane-Pliki-Z @($n.Sciezka)) $KatalogDomowy $Zrodlo
    $p.Co = "NIETKNIETY - plik ma bajty 0x00"
    return $p
  }
  try {
    $start = Tekst-Startowy $n $KatalogDomowy
    if ($p.Istnieje) { $p.Stary = Czytaj $n.Sciezka }
  } catch {
    $p.Blad = "nie umiem odczytac $($n.Sciezka) (albo pliku, od ktorego sie zaczyna): $($_.Exception.Message) - nie ruszam go"
    $p.Co = "NIETKNIETY - blad odczytu"
    return $p
  }
  $p.Start = $start
  $znalezione = Znajdz-Bloki-Zasad $start.Tekst
  if ($znalezione.Blad) {
    $p.Blad = "w $($n.Sciezka) $($znalezione.Blad), nie ruszam go"
    $p.Co = "NIETKNIETY - zle znaczniki"
    return $p
  }
  $plan = Ktore-Bloki @(Obecne-Bloki-Zasad $start.Tekst)
  $chciane = @($plan.Chciane)
  $p.Zdjac = @($plan.Zdjac)
  foreach ($b in (Bloki-Zasad)) { if ($chciane -contains $b) { $p.Tresci[$b] = $script:Tresci[$b] } }
  $p.Szkielet = $script:Szkielet
  $pp = Plan-Pliku-Narzedzia $n $start $p.Stary $p.Tresci $p.Zdjac $p.Szkielet $script:ZrodloCoWiem
  $p.Nowy = $pp.Nowy
  $p.Zasiew = $pp.Zasiew
  $p.OdmowaZasiewu = $pp.OdmowaZasiewu
  if ($p.Nowy -ceq $p.Stary) { return $p }
  $opisy = @(Roznice-Zasad $start.Tekst $p.Tresci $p.Zdjac)
  if ($p.Szkielet -and -not (Ma-Co-Wiem $start.Tekst)) { $opisy += "szkielet sekcji '## Co wiem'" }
  if ($p.Zasiew) { $opisy += $p.Zasiew }
  if ($start.Opis) { $opisy = @($start.Opis) + $opisy }
  $p.Co = $opisy -join "; "
  if (-not $p.Istnieje) { $p.Co = "zakladam plik ($($p.Co))" }
  $p.Limit = $pp.Limit
  return $p
}

function Wykonaj-Plan($p) {
  $nazwa = $p.Nazwa; $plik = $p.Plik
  if ($p.Blad) {
    Write-Host "BLAD  $nazwa - $($p.Blad)" -ForegroundColor Red
    $script:Bledy++
    $script:Raport += "$nazwa : $($p.Co)"
    return
  }
  if ($p.OdmowaZasiewu) { $script:Raport += "$nazwa : ODMOWA ZASIEWU 'Co wiem' - ponad limit" }
  if ($p.Nowy -ceq $p.Stary) {
    if ($p.Istnieje) { Write-Host "--  $nazwa - bloki zasad juz sa aktualne: $plik" }
    else { Write-Host "--  $nazwa - nie ma pliku $plik i nie ma czego do niego wpisac" }
    $script:Raport += "$nazwa : bez zmian"
    return
  }
  if ($p.Limit) {
    # ostrzezenie poszlo juz w pierwszych liniach wyjscia - tu tylko slad w podsumowaniu
    $script:Raport += "$nazwa : ODMOWA ZAPISU - ponad limit"
    return
  }
  if ($Proba) {
    Write-Host "PROBA  $nazwa - $($p.Co) w $plik"
    if ($p.Istnieje) { Write-Host "PROBA  $nazwa - kopia trafilaby do $plik.bak-$Stempel" }
    $script:Raport += "$nazwa : PROBA, $($p.Co)"
    return
  }

  $katalog = Split-Path -Parent $plik
  if (-not (Test-Path $katalog)) { New-Item -ItemType Directory -Force -Path $katalog | Out-Null }
  $bak = $null
  if ($p.Istnieje) { $bak = Kopia-Zapasowa $plik }
  Zapisz $plik $p.Nowy

  $nl = "`r`n"
  if (-not $p.Nowy.Contains("`r`n") -and $p.Nowy.Contains("`n")) { $nl = "`n" }
  $bloki = @($p.Tresci.Keys | ForEach-Object { Tekst-Bloku-Zasad $_ $p.Tresci[$_] $nl })
  # stary wspolny blok po zlozeniu nie zostaje nigdy - zamieniony albo zdjety
  $zdjete = @($p.Zdjac | Where-Object { -not $p.Tresci.Contains($_) }) + @("stary")
  if (-not (Sprawdz-Zapis $plik $nazwa $bloki $zdjete $p.Szkielet ([bool]$p.Zasiew))) { return }

  Write-Host "OK  $nazwa - $($p.Co): $plik"
  $wpis = "$nazwa : $($p.Co)"
  if ($bak) {
    Write-Host "    kopia: $bak"
    $wpis = "$wpis, kopia $bak"
  }
  $script:Raport += $wpis
}

# --- przebieg ----------------------------------------------------------------

if (-not (Test-Path $KatalogDomowy)) {
  Write-Error "Nie ma takiego katalogu domowego: $KatalogDomowy"
  exit 1
}
$KatalogDomowy = (Resolve-Path $KatalogDomowy).Path

# "-Blok lore,wiedza" z powershell -File przychodzi jako jeden napis
$Blok = @($Blok | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
foreach ($n in $Blok) {
  if ((Bloki-Zasad) -notcontains $n) {
    Write-Error "Nie znam bloku zasad '$n' - sa: $((Bloki-Zasad) -join ', ')."
    exit 1
  }
}

# Naglowek przebiegu wypisujemy DOPIERO po planie - pierwsze linie wyjscia naleza do odmow
# z sufitu (ktos, kto czyta tylko poczatek, ma je zobaczyc zawsze).
$script:Naglowek = @()
$script:Chciane = Chciane-Bloki-Zasad $KatalogDomowy
if (($Blok.Count -eq 0) -and -not $Usun) {
  if ($script:Chciane.Blad) {
    $script:Naglowek += [pscustomobject]@{ T = "UWAGA  $($script:Chciane.Blad) - wpisuje oba bloki zasad i niczego nie zdejmuje."; K = "Yellow" }
  } else {
    $opis = if ($script:Chciane.Nazwy.Count -gt 0) { $script:Chciane.Nazwy -join ", " } else { "zaden" }
    $script:Naglowek += [pscustomobject]@{ T = "Bloki wedlug rejestru instalacji ($($script:Chciane.Zrodlo)): $opis"; K = $null }
  }
}
# Szkielet "Co wiem" idzie tylko w przebiegu wedlug rejestru, przy wlaczonym module wiedza.
$script:Szkielet = ($Blok.Count -eq 0) -and (-not $Usun) -and ($script:Chciane.Nazwy -contains "wiedza")
# Skad tresc dla pustych sekcji "Co wiem": najbogatsza sekcja z plikow narzedzi, przed zapisem.
$script:ZrodloCoWiem = $null
if ($script:Szkielet) { $script:ZrodloCoWiem = Zrodlo-Co-Wiem $KatalogDomowy }

# Tresci ze zrodla - potrzebne zawsze poza pelnym -Usun (przy -Usun -Blok stary blok zamienia
# sie na bloki, ktore maja zostac, wiec ich tresc tez musi byc pod reka).
$script:Tresci = @{}
if ($Blok.Count -gt 0 -or -not $Usun) {
  if (-not (Test-Path $Zrodlo)) { Write-Error "Nie ma takiego katalogu zrodlowego: $Zrodlo"; exit 1 }
  $Zrodlo = (Resolve-Path $Zrodlo).Path
  foreach ($n in (Bloki-Zasad)) {
    try { $script:Tresci[$n] = Tresc-Zrodla-Zasad $Zrodlo $n }
    catch { Write-Error "Zasady ${n}: $($_.Exception.Message)"; exit 1 }
    $script:Naglowek += [pscustomobject]@{ T = "Zrodlo: $(Join-Path $Zrodlo "zasady-$n.md") ($(@($script:Tresci[$n]).Count) linii tresci)"; K = $null }
  }
}
if ($Proba) { $script:Naglowek += [pscustomobject]@{ T = "TRYB PROBY - nic nie zostanie zapisane"; K = "Yellow" } }

# Pliki narzedzi, ktore tu sa - z jednej listy (kierownik-cele.ps1 Narzedzia-AI).
$Wszystkie = Wykryj-Narzedzia-AI $KatalogDomowy
$Cele = @($Wszystkie | Where-Object { $_.Jest })
$Plany = @()
foreach ($c in $Cele) {
  try { $Plany += Planuj-Plik $c }
  catch {
    $Plany += [pscustomobject]@{ N = $c; Nazwa = $c.Nazwa; Plik = $c.Sciezka; Istnieje = $false; Stary = ""; Nowy = ""; Co = "NIETKNIETY - wyjatek"
                                 Tresci = [ordered]@{}; Zdjac = @(); Szkielet = $false; Blad = $_.Exception.Message; Limit = $null; Start = $null
                                 Zasiew = $null; OdmowaZasiewu = $null }
  }
}

foreach ($p in @($Plany | Where-Object { $_.Limit -and -not $_.Blad -and ($_.Nowy -cne $_.Stary) })) {
  Write-Host "BLAD  ODMOWA ZAPISU ($($p.Nazwa)): $($p.Limit)" -ForegroundColor Red
  $script:Bledy++
}
foreach ($p in @($Plany | Where-Object { $_.OdmowaZasiewu -and -not $_.Blad -and -not $_.Limit })) {
  Write-Host "BLAD  ODMOWA ZAPISU ($($p.Nazwa)): $($p.OdmowaZasiewu)" -ForegroundColor Red
  $script:Bledy++
}
foreach ($l in $script:Naglowek) { if ($l.K) { Write-Host $l.T -ForegroundColor $l.K } else { Write-Host $l.T } }

if ($Cele.Count -eq 0) {
  Write-Host ("UWAGA  nie widze tu zadnego narzedzia AI (" + (($Wszystkie | ForEach-Object { $_.Nazwa }) -join ", ") +
              ") - zasad nie ma gdzie wpisac. Wpisze je straznik zasad, gdy ktores sie pojawi.") -ForegroundColor Yellow
  $script:Raport += "zadne narzedzie AI : pominiete"
}
foreach ($n in @($Wszystkie | Where-Object { -not $_.Jest })) {
  Write-Host "--  $($n.Nazwa) - nie widze go na tej maszynie: pomijam $($n.Sciezka)"
  $script:Raport += "$($n.Nazwa) : pominiete (brak narzedzia)"
}
foreach ($p in $Plany) {
  try { Wykonaj-Plan $p }
  catch {
    Write-Host "BLAD  $($p.Nazwa) - $($_.Exception.Message)" -ForegroundColor Red
    $script:Bledy++
  }
}

# Po zapisie: czy "Co wiem" jest wszedzie ta sama. Roznica to meldunek, nie blad - scala czlowiek.
if ($script:Szkielet) {
  $rozjazd = $null
  try { $rozjazd = Rozjazd-Co-Wiem $KatalogDomowy } catch { $rozjazd = "nie umiem porownac sekcji 'Co wiem' ($($_.Exception.Message))" }
  if ($rozjazd) {
    Write-Host "UWAGA  $rozjazd" -ForegroundColor Yellow
    $script:Raport += "Co wiem : rozni sie miedzy narzedziami - UWAGA wyzej"
  }
}

Write-Host ""
Write-Host "Podsumowanie:"
foreach ($linia in $script:Raport) { Write-Host "  $linia" }

if ($script:Bledy -gt 0) {
  Write-Host ""
  Write-Host "Zakonczone bledem - $($script:Bledy) plik(ow) nie przeszlo." -ForegroundColor Red
  exit 1
}

Write-Host ""
if ($Proba)    { Write-Host "Proba zakonczona - zaden plik nie ruszony." }
elseif ($Usun) { Write-Host "Gotowe - bloki zasad MegaRuchacza usuniete, reszta plikow bez zmian." }
elseif ($Cele.Count -eq 0) { Write-Host "Gotowe - nic do wpisania (zadnego narzedzia AI)." }
else           { Write-Host "Gotowe - zasady wpisane. Zamknij i otworz narzedzie na nowo." }
exit 0
