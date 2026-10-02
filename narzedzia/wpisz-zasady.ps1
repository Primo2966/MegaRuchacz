# Wpisuje zasady pamieci MegaRuchacza do plikow instrukcji narzedzi AI uzytkownika.
# Od P59a dwa bloki, kazdy dla wlasnego modulu instalatora (regula skladania: zasady-bloki.ps1):
#   lore    zasady-lore.md   -> <!-- MegaRuchacz:lore:start -->   ... <!-- MegaRuchacz:lore:koniec -->
#   wiedza  zasady-wiedza.md -> <!-- MegaRuchacz:wiedza:start --> ... <!-- MegaRuchacz:wiedza:koniec -->
# Zrodlo tresci: tylko to, co w pliku stoi pod linia-znacznikiem. Stary wspolny blok
# <!-- MegaRuchacz:start --> (do P59a) zamieniany jest na nowe NA SWOIM MIEJSCU - "Co wiem"
# nad nim i reszta pliku zostaja co do bajtu.
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

function Czytaj($sciezka) {
  return [System.IO.File]::ReadAllText($sciezka, $Utf8Odczyt)
}

function Zapisz($sciezka, $tekst) {
  Zapisz-Trwale $sciezka $tekst $Utf8Zapis
}

# Bajt 0x00 w pliku zasad to slad zepsutego zapisu, nie tresc uzytkownika: taki plik
# zostaje nietkniety i bez kopii, a uzytkownik dostaje adres zdrowej kopii.
function Wyzerowany($plik, $nazwa) {
  if (-not (Ma-Zera $plik)) { return $false }
  $opis = Opis-Wyzerowanych (Wyzerowane-Pliki-Z @($plik)) $KatalogDomowy $Zrodlo
  Write-Host "BLAD  $nazwa - $opis" -ForegroundColor Red
  $script:Bledy++
  $script:Raport += "$nazwa : NIETKNIETY - plik ma bajty 0x00"
  return $true
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
function Sprawdz-Zapis($plik, $nazwa, $bloki, $zdjete) {
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

function Popraw-Plik($plik, $nazwa) {
  $istnieje = Test-Path $plik
  $stary = ""
  if ($istnieje -and (Wyzerowany $plik $nazwa)) { return }
  if ($istnieje) {
    try { $stary = Czytaj $plik }
    catch {
      Write-Host "BLAD  $nazwa - nie umiem odczytac $plik jako UTF-8, nie ruszam go" -ForegroundColor Red
      $script:Bledy++
      return
    }
  }
  $znalezione = Znajdz-Bloki-Zasad $stary
  if ($znalezione.Blad) {
    Write-Host "BLAD  $nazwa - w $plik $($znalezione.Blad), nie ruszam go" -ForegroundColor Red
    $script:Bledy++
    return
  }

  $plan = Ktore-Bloki @(Obecne-Bloki-Zasad $stary)
  $chciane = @($plan.Chciane)
  $zdjac = @($plan.Zdjac)
  $tresci = [ordered]@{}
  foreach ($n in (Bloki-Zasad)) { if ($chciane -contains $n) { $tresci[$n] = $script:Tresci[$n] } }

  $nowy = Zloz-Plik-Zasad $stary $tresci $zdjac
  if ($nowy -ceq $stary) {
    if ($istnieje) { Write-Host "--  $nazwa - bloki zasad juz sa aktualne: $plik" }
    else { Write-Host "--  $nazwa - nie ma pliku $plik i nie ma czego do niego wpisac" }
    $script:Raport += "$nazwa : bez zmian"
    return
  }
  $co = (Roznice-Zasad $stary $tresci $zdjac) -join "; "
  if (-not $istnieje) { $co = "zakladam plik ($co)" }

  if ($Proba) {
    Write-Host "PROBA  $nazwa - $co w $plik"
    if ($istnieje) { Write-Host "PROBA  $nazwa - kopia trafilaby do $plik.bak-$Stempel" }
    $script:Raport += "$nazwa : PROBA, $co"
    return
  }

  $katalog = Split-Path -Parent $plik
  if (-not (Test-Path $katalog)) { New-Item -ItemType Directory -Force -Path $katalog | Out-Null }
  $bak = $null
  if ($istnieje) { $bak = Kopia-Zapasowa $plik }
  Zapisz $plik $nowy

  $nl = "`r`n"
  if (-not $nowy.Contains("`r`n") -and $nowy.Contains("`n")) { $nl = "`n" }
  $bloki = @($tresci.Keys | ForEach-Object { Tekst-Bloku-Zasad $_ $tresci[$_] $nl })
  # stary wspolny blok po zlozeniu nie zostaje nigdy - zamieniony albo zdjety
  $zdjete = @($zdjac | Where-Object { -not $tresci.Contains($_) }) + @("stary")
  if (-not (Sprawdz-Zapis $plik $nazwa $bloki $zdjete)) { return }

  Write-Host "OK  $nazwa - ${co}: $plik"
  $wpis = "$nazwa : $co"
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

$script:Chciane = Chciane-Bloki-Zasad $KatalogDomowy
if (($Blok.Count -eq 0) -and -not $Usun) {
  if ($script:Chciane.Blad) {
    Write-Host "UWAGA  $($script:Chciane.Blad) - wpisuje oba bloki zasad i niczego nie zdejmuje." -ForegroundColor Yellow
  } else {
    $opis = if ($script:Chciane.Nazwy.Count -gt 0) { $script:Chciane.Nazwy -join ", " } else { "zaden" }
    Write-Host "Bloki wedlug rejestru instalacji ($($script:Chciane.Zrodlo)): $opis"
  }
}

# Tresci ze zrodla - potrzebne zawsze poza pelnym -Usun (przy -Usun -Blok stary blok zamienia
# sie na bloki, ktore maja zostac, wiec ich tresc tez musi byc pod reka).
$script:Tresci = @{}
if ($Blok.Count -gt 0 -or -not $Usun) {
  if (-not (Test-Path $Zrodlo)) { Write-Error "Nie ma takiego katalogu zrodlowego: $Zrodlo"; exit 1 }
  $Zrodlo = (Resolve-Path $Zrodlo).Path
  foreach ($n in (Bloki-Zasad)) {
    try { $script:Tresci[$n] = Tresc-Zrodla-Zasad $Zrodlo $n }
    catch { Write-Error "Zasady ${n}: $($_.Exception.Message)"; exit 1 }
    Write-Host "Zrodlo: $(Join-Path $Zrodlo "zasady-$n.md") ($(@($script:Tresci[$n]).Count) linii tresci)"
  }
}

if ($Proba) { Write-Host "TRYB PROBY - nic nie zostanie zapisane" -ForegroundColor Yellow }

$Cele = @(
  @{ Nazwa = "Claude Code"; Katalog = (Join-Path $KatalogDomowy ".claude"); Plik = "CLAUDE.md"; Zakladaj = $true  },
  @{ Nazwa = "Codex";       Katalog = (Join-Path $KatalogDomowy ".codex");  Plik = "AGENTS.md"; Zakladaj = $false }
)

foreach ($cel in $Cele) {
  if (-not (Test-Path $cel.Katalog) -and -not $cel.Zakladaj) {
    Write-Host "--  $($cel.Nazwa) - nie ma $($cel.Katalog), czyli nie ma tego narzedzia na tej maszynie: pomijam"
    $script:Raport += "$($cel.Nazwa) : pominiete (brak narzedzia)"
    continue
  }
  try { Popraw-Plik (Join-Path $cel.Katalog $cel.Plik) $cel.Nazwa }
  catch {
    Write-Host "BLAD  $($cel.Nazwa) - $($_.Exception.Message)" -ForegroundColor Red
    $script:Bledy++
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
else           { Write-Host "Gotowe - zasady wpisane. Zamknij i otworz narzedzie na nowo." }
exit 0
