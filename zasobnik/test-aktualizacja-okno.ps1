# Sprawdzenie okna aktualizacji MegaRuchacza (2026-10-07): pasek z czterema krokami w karcie
# Stan, linia wyniku, sprawa na Przegladzie przy bledzie, nieswiezy wynik i przycisk, ktory
# uruchamia aktualizacje w tle i nie czeka. Brak sieci / pobieranie zajete: szara linia bez
# sprawy do doby od udanego sprawdzenia, z sabotazami na kopii stan-wersja.ps1.
#   powershell -ExecutionPolicy Bypass -File zasobnik\test-aktualizacja-okno.ps1 [-Zasobnik <kat zasobnik>] [-Zrodlo <repo>] [-Zrzuty <kat>] [-BezOkna]
# Wszystko na sztucznym katalogu domowym (atrapa ~\.claude\mr\aktualizacja.json w kazdym etapie)
# i na atrapie narzedzia\aktualizuj-megaruchacza.ps1 w sztucznym zrodle - prawdziwego domu,
# prawdziwej aktualizacji ani dzialajacego nadzorcy test nie dotyka.
# Czesc z oknem: formularz z karta Stan, sprawami i przyciskami, poza ekranem (-5000, 0), bez paska
# zadan, bez aktywacji (nie zabiera klawiatury), bez ikony i bez dozoru; zrzuty przez DrawToBitmap.
param(
  [string]$Zasobnik = $PSScriptRoot,
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [string]$Zrzuty = "",
  [switch]$BezOkna
)
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { Write-Warning "konsola bez UTF-8: $($_.Exception.Message)" }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("test-akt-okno-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
if (-not $Zrzuty) { $Zrzuty = Join-Path $tmp "zrzuty" }
New-Item -ItemType Directory -Force -Path $Zrzuty | Out-Null
$dom = Join-Path $tmp "dom"
$katMr = Join-Path $dom ".claude\mr"
New-Item -ItemType Directory -Force -Path $katMr | Out-Null
$plikAkt = Join-Path $katMr "aktualizacja.json"

$script:wyniki = @()
function Wynik($nazwa, $ok, $opis) {
  $script:wyniki += [pscustomobject]@{ Test = $nazwa; OK = [bool]$ok; Opis = $opis }
  $z = "NIE"; if ($ok) { $z = "TAK" }
  Write-Host ("[{0}] {1} - {2}" -f $z, $nazwa, $opis)
}
function Iso($d) { return $d.ToString("yyyy-MM-ddTHH:mm:ss") }
function Godz($d) { return $d.ToString("HH:mm") }
# Atrapa pliku stanu - pola z kontraktu z mechanika aktualizacji.
function Atrapa([hashtable]$pola) {
  $o = [ordered]@{ etap = "gotowe"; krok = 4; krokow = 4; opis = ""; wynik = ""; wersja_przed = "0.28.0"; wersja_po = "0.28.0"
                   start = (Iso (Get-Date)); koniec = ""; sprawdzone = ""; powod = ""; reczna = $false }
  foreach ($k in $pola.Keys) { $o[$k] = $pola[$k] }
  [System.IO.File]::WriteAllText($plikAkt, ($o | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
}
function Bez-Pliku { if (Test-Path -LiteralPath $plikAkt) { Remove-Item -LiteralPath $plikAkt -Force } }

# ---------------------------------------------------------------- wczytanie modulow
. (Join-Path $Zasobnik "stan-nadzorcy.ps1")
Ustaw-Nadzorce $Zrodlo $dom $true
$script:ModulyOkna = @{}
. (Join-Path $Zasobnik "nadzorca\przeglad-tresc.ps1")

$inst = [pscustomobject]@{ Moduly = [pscustomobject]@{ wiedza = $false; lore = $false; skille = $false; kopia = $false; kierownik = $true } }
$k = [ordered]@{ narzedzia = "1"; "narz.1.klucz" = "claude"; "narz.1.nazwa" = "Claude Code"; "narz.1.uzywane" = "1"; "narz.1.zuzycie_w_oknie" = "1" }
$D = [pscustomobject]@{ Rachunek = [pscustomobject]@{ Klucze = $k; Linia = "x" }; Cykl = $null; Alarmy = @(); Informacje = @()
  Instalacja = $inst; Przeliczanie = $null; Kopia = $null; Pamiec = $null
  Wersja = [pscustomobject]@{ Lokalna = "0.28.0"; Nowsza = 0; Nasze = 0; Pobrano = (Get-Date); Powod = "" } }

$teraz = Get-Date
function O($nadzOd = $null, $klik = $null, [string]$klikPowod = "") { return (Ocena-Aktualizacji (Stan-Aktualizacji) (Get-Date) $nadzOd $klik $klikPowod "0.28.0") }
function Kroki($o) { return ((@($o.Kroki) | ForEach-Object { $_.Stan }) -join ",") }
function Uwagi { return (Ile-Wymaga-Uwagi (Zbierz-Problemy $D @() "" (Get-Date))) }
function Przod { return ((Zbuduj-Przod $D (Zbierz-Problemy $D @() "" (Get-Date)) (Get-Date) $null $null $null) -join "`n") }
$ZNAKOK = [string][char]0x2713
$ZNAKZLE = [string][char]0x2717

# ---------------------------------------------------------------- A. tresc (bez okna)
Bez-Pliku
$o = O
Wynik "brak pliku, nadzorca nieznany: stara linia wersji, bez sprawy" ((-not $o.ZPliku) -and (-not $o.Problem) -and ((Uwagi) -eq 0)) "ZPliku=$($o.ZPliku) uwagi=$(Uwagi)"
$p = Przod
Wynik "brak pliku: wydruk ze stara linia 'Wersja MegaRuchacza' i 'Wszystko gra'" (($p -match 'Wersja MegaRuchacza: 0\.28\.0') -and ($p -match 'Wszystko gra')) (([regex]::Match($p, '(?s)STAN .*?\n\n')).Value)
$o = O $teraz.AddMinutes(-60)
Wynik "negatywna: brak pliku, nadzorca chodzi od godziny -> sprawa 'ani razu'" ($o.Problem -and ($o.Problem.Waga -eq "uwaga") -and ($o.Problem.Tytul -match 'ani razu')) "$($o.Problem.Tytul)"
$o = O $teraz.AddMinutes(-5)
Wynik "brak pliku, nadzorca od 5 min -> jeszcze bez sprawy" (-not $o.Problem) "$($o.Problem.Tytul)"

$etapy = @(
  @{ etap = "sprawdzam"; krok = 1; opis = "Sprawdzam, czy jest coś nowego..."; kroki = "trwa,czeka,czeka,czeka" },
  @{ etap = "pobieram"; krok = 2; opis = "Pobieram nową wersję..."; kroki = "zrobione,trwa,czeka,czeka" },
  @{ etap = "nanosze"; krok = 3; opis = "Wgrywam do Claude Code..."; kroki = "zrobione,zrobione,trwa,czeka" },
  @{ etap = "restart"; krok = 4; opis = ""; kroki = "zrobione,zrobione,zrobione,trwa" })
foreach ($e in $etapy) {
  Atrapa @{ etap = $e.etap; krok = $e.krok; opis = $e.opis }
  $o = O
  $opis = $e.opis; if (-not $opis) { $opis = "Uruchamiam MegaRuchacza ponownie..." }
  $n = Napisy-Przyciskow $D $null $inst
  $ok = $o.Trwa -and ($o.Naglowek -eq "$opis ($($e.krok) z 4)") -and ((Kroki $o) -eq $e.kroki) -and (-not $o.Problem) -and
        (-not $n.AktualizujWlaczony) -and ($n.AktualizujOpis -like "Aktualizacja trwa*") -and ([math]::Abs($o.Postep - (($e.krok - 0.5) / 4)) -lt 0.001)
  Wynik "etap $($e.etap): pasek '$($o.Naglowek)', kroki, przycisk wyszarzony" $ok "kroki=$(Kroki $o) postep=$($o.Postep) przycisk=$($n.AktualizujWlaczony) '$($n.AktualizujOpis)'"
}
Atrapa @{ etap = "pobieram"; krok = 2; opis = "Pobieram nową wersję..." }
$p = Przod
$stan = ([regex]::Match($p, '(?s)STAN .*?\n\n')).Value
Wynik "wydruk w trakcie: pasek i kroki zamiast linii wersji" (($stan -match 'Aktualizacja MegaRuchacza: \[#+-+\]  Pobieram nową wersję\.\.\. \(2 z 4\)') -and
  ($stan -match "1\. Sprawdzam, czy jest coś nowego  $ZNAKOK") -and ($stan -match '2\. Pobieram  \.\.\.') -and ($stan -match '4\. Uruchamiam ponownie') -and
  ($stan -notmatch 'Wersja MegaRuchacza') -and ($p -match '\[Sprawdź i pobierz nowszą wersję MegaRuchacza\]  \(przycisk nieaktywny\)')) $stan

$kon = $teraz.AddMinutes(-3)
Atrapa @{ etap = "gotowe"; wynik = "zaktualizowano"; wersja_po = "0.29.0"; koniec = (Iso $kon); sprawdzone = (Iso $kon) }
$o = O
Wynik "zaktualizowano: linia jak w makiecie, zielona, bez sprawy" ((-not $o.Trwa) -and ($o.Znak -eq $ZNAKOK) -and ($o.Linia -eq "Zaktualizowano do najnowszej wersji 0.29.0 (dziś $(Godz $kon))") -and ($o.Waga -eq "dobrze") -and (-not $o.Problem)) "$($o.Znak) $($o.Linia) [$($o.Waga)]"
Atrapa @{ etap = "gotowe"; wynik = "aktualne"; koniec = (Iso $kon); sprawdzone = (Iso $kon) }
$o = O
$n = Napisy-Przyciskow $D $null $inst
Wynik "aktualne: 'Masz najnowszą wersję 0.28.0 (sprawdzone dziś HH:mm)', przycisk aktywny" (($o.Linia -eq "Masz najnowszą wersję 0.28.0 (sprawdzone dziś $(Godz $kon))") -and ($o.Waga -eq "dobrze") -and $n.AktualizujWlaczony -and ((Uwagi) -eq 0)) "$($o.Znak) $($o.Linia); uwagi=$(Uwagi)"
$p = Przod
Wynik "aktualne: wydruk z linia wyniku i 'Wszystko gra'" (($p -match "Aktualizacja MegaRuchacza: $ZNAKOK Masz najnowszą wersję 0\.28\.0 \(sprawdzone dziś \d\d:\d\d\)  \(zielony napis\)") -and ($p -match 'Wszystko gra')) (([regex]::Match($p, '(?s)STAN .*?\n\n')).Value)

# blad - czerwony, sprawa pilna, bez "Wszystko gra"
Atrapa @{ etap = "blad"; wynik = "blad"; koniec = (Iso $kon); powod = "Nie ma połączenia z serwerem. Sprawdź internet - spróbuję sam za godzinę." }
$o = O
Wynik "negatywna: blad -> czerwona linia z powodem i sprawa pilna" (($o.Znak -eq $ZNAKZLE) -and ($o.Waga -eq "pilne") -and ($o.Linia -eq "Nie udało się zaktualizować: Nie ma połączenia z serwerem. Sprawdź internet - spróbuję sam za godzinę.") -and ($o.Problem.Waga -eq "pilne")) "$($o.Znak) $($o.Linia)"
$p = Przod
Wynik "negatywna: blad -> w wydruku [!] na gorze i bez 'Wszystko gra'" (((Uwagi) -eq 1) -and ($p -match '\[!\] Nie udało się zaktualizować MegaRuchacza') -and ($p -notmatch 'Wszystko gra') -and ($p -match "$ZNAKZLE Nie udało się zaktualizować: .*\(czerwony napis\)")) "uwagi=$(Uwagi)"
Atrapa @{ etap = "blad"; wynik = "blad"; koniec = (Iso $kon); powod = "" }
$o = O
Wynik "negatywna: blad bez powodu -> mowi, ze powodu nie podano" (($o.Waga -eq "pilne") -and ($o.Linia -match 'nie podała powodu')) $o.Linia
Atrapa @{ etap = "gotowe"; wynik = ""; koniec = (Iso $kon) }
$o = O
Wynik "negatywna: gotowe bez wyniku -> sprawa zolta" (($o.Waga -eq "uwaga") -and ($o.Problem.Waga -eq "uwaga")) $o.Linia

# brak sieci / pobieranie zajete (2026-10-07): szara linia bez sprawy, dopoki od ostatniego
# UDANEGO sprawdzenia nie minie doba; martwy zegar (3 h bez proby) dalej widac; inne przyczyny czerwone.
# Kazda proba to funkcja - te same proby ida nizej na sabotowanej kopii stan-wersja.ps1.
$POWOD_SIEC = "Nie udało się połączyć z serwerem z nowymi wersjami (brak internetu albo dostępu). Spróbuję znowu za godzinę."
function Proba-BezSieciSwieza {
  $spr = (Get-Date).AddHours(-2)
  Atrapa @{ etap = "blad"; wynik = "blad"; przyczyna = "bez-sieci"; koniec = (Iso (Get-Date).AddMinutes(-1)); sprawdzone = (Iso $spr); powod = $POWOD_SIEC }
  $o = O (Get-Date).AddHours(-5)
  $p = Przod
  $ok = (-not $o.Problem) -and ($o.Waga -eq "szary") -and (-not $o.Znak) -and
        ($o.Linia -eq "Nie sprawdziłem aktualizacji - brak internetu. Spróbuję sam za godzinę. Ostatnio sprawdzone: dziś $(Godz $spr).") -and
        ((Uwagi) -eq 0) -and ($p -match 'Wszystko gra') -and ($p -notmatch '\(czerwony napis\)')
  return [pscustomobject]@{ Ok = $ok; Opis = "$($o.Znak) $($o.Linia) [$($o.Waga)] uwagi=$(Uwagi) sprawa=$($o.Problem.Tytul)" }
}
function Proba-BezSieciNigdy {
  Bez-Pliku
  Atrapa @{ etap = "blad"; wynik = "blad"; przyczyna = "bez-sieci"; koniec = (Iso (Get-Date)); sprawdzone = ""; powod = $POWOD_SIEC }
  [System.IO.File]::SetCreationTime($plikAkt, (Get-Date).AddMinutes(-30))
  $o = O (Get-Date).AddHours(-5)
  $ok = (-not $o.Problem) -and ($o.Waga -eq "szary") -and ($o.Linia -match 'Ostatnio sprawdzone: jeszcze nigdy\.$')
  return [pscustomobject]@{ Ok = $ok; Opis = "$($o.Linia) [$($o.Waga)] sprawa=$($o.Problem.Tytul)" }
}
function Proba-Zajete {
  Atrapa @{ etap = "blad"; wynik = "blad"; przyczyna = "zajete"; koniec = (Iso (Get-Date).AddMinutes(-1)); sprawdzone = (Iso (Get-Date).AddHours(-1)); powod = "Inny przebieg właśnie pobierał nową wersję." }
  $o = O (Get-Date).AddHours(-5)
  $ok = (-not $o.Problem) -and ($o.Waga -eq "szary") -and ($o.Linia -eq "Aktualizację właśnie pobiera inny proces - sprawdzę za godzinę.") -and ((Uwagi) -eq 0)
  return [pscustomobject]@{ Ok = $ok; Opis = "$($o.Linia) [$($o.Waga)] uwagi=$(Uwagi)" }
}
function Proba-BezSieciDoba {
  $spr = (Get-Date).AddHours(-25)
  Atrapa @{ etap = "blad"; wynik = "blad"; przyczyna = "bez-sieci"; koniec = (Iso (Get-Date).AddMinutes(-1)); sprawdzone = (Iso $spr); powod = $POWOD_SIEC }
  $o = O (Get-Date).AddHours(-30)
  $p = Przod
  $ok = ($o.Waga -eq "pilne") -and ($o.Znak -eq $ZNAKZLE) -and ($o.Linia -match '^Od ponad doby nie mogę sprawdzić aktualizacji - brak połączenia z GitHubem') -and
        ($o.Problem.Waga -eq "pilne") -and ($o.Problem.Tytul -eq "Od ponad doby nie mogę sprawdzić aktualizacji MegaRuchacza") -and ($o.Problem.Porada -match 'Sprawdź internet') -and
        ((Uwagi) -eq 1) -and ($p -notmatch 'Wszystko gra') -and ($p -match '\[!\] Od ponad doby')
  return [pscustomobject]@{ Ok = $ok; Opis = "$($o.Znak) $($o.Linia) | $($o.Problem.Tytul) | uwagi=$(Uwagi)" }
}
function Proba-BezSieciNigdyDoba {
  Atrapa @{ etap = "blad"; wynik = "blad"; przyczyna = "bez-sieci"; koniec = (Iso (Get-Date)); sprawdzone = ""; powod = $POWOD_SIEC }
  [System.IO.File]::SetCreationTime($plikAkt, (Get-Date).AddHours(-25))
  $o = O (Get-Date).AddHours(-30)
  $ok = ($o.Problem.Waga -eq "pilne") -and ($o.Linia -match 'ostatnio sprawdzone: jeszcze nigdy')
  [System.IO.File]::SetCreationTime($plikAkt, (Get-Date))
  return [pscustomobject]@{ Ok = $ok; Opis = "$($o.Linia) | $($o.Problem.Tytul)" }
}
function Proba-BezSieciPrawieDoba {
  Atrapa @{ etap = "blad"; wynik = "blad"; przyczyna = "bez-sieci"; koniec = (Iso (Get-Date).AddMinutes(-1)); sprawdzone = (Iso (Get-Date).AddHours(-23)); powod = $POWOD_SIEC }
  $o = O (Get-Date).AddHours(-30)
  return [pscustomobject]@{ Ok = ((-not $o.Problem) -and ($o.Waga -eq "szary")); Opis = "$($o.Linia) [$($o.Waga)] sprawa=$($o.Problem.Tytul)" }
}
function Proba-BezSieciMartwyZegar {
  $prob = (Get-Date).AddHours(-4)
  Atrapa @{ etap = "blad"; wynik = "blad"; przyczyna = "bez-sieci"; start = (Iso $prob); koniec = (Iso $prob); sprawdzone = (Iso (Get-Date).AddHours(-6)); powod = $POWOD_SIEC }
  $o = O (Get-Date).AddHours(-5)
  $ok = ($o.Problem.Waga -eq "uwaga") -and ($o.Problem.Tytul -match 'nie próbowała sprawdzać serwera od') -and ($o.Dopisek -match 'Od ponad 3 godzin') -and ((Uwagi) -eq 1)
  return [pscustomobject]@{ Ok = $ok; Opis = "$($o.Problem.Tytul) | $($o.Dopisek)" }
}
function Proba-InnaPrzyczynaCzerwona {
  Atrapa @{ etap = "blad"; wynik = "blad"; przyczyna = "nanoszenie"; koniec = (Iso (Get-Date).AddMinutes(-1)); sprawdzone = (Iso (Get-Date).AddMinutes(-2)); powod = "Nowa wersja jest pobrana, ale nie udało się jej wgrać." }
  $o = O (Get-Date).AddHours(-5)
  $ok = ($o.Waga -eq "pilne") -and ($o.Problem.Waga -eq "pilne") -and ($o.Linia -eq "Nie udało się zaktualizować: Nowa wersja jest pobrana, ale nie udało się jej wgrać.") -and ((Uwagi) -eq 1)
  return [pscustomobject]@{ Ok = $ok; Opis = "$($o.Znak) $($o.Linia) [$($o.Waga)]" }
}
$PROBY_SIECI = [ordered]@{
  "bez-sieci swieze (sprawdzone 2 h temu) -> szara linia, bez sprawy, 'Wszystko gra'" = "Proba-BezSieciSwieza"
  "bez-sieci, udanego sprawdzenia nie bylo nigdy (plik od 30 min) -> szara linia 'jeszcze nigdy'" = "Proba-BezSieciNigdy"
  "zajete -> szara linia 'inny proces', bez sprawy" = "Proba-Zajete"
  "bez-sieci 23 h od udanego sprawdzenia -> jeszcze bez sprawy" = "Proba-BezSieciPrawieDoba"
  "negatywna: bez-sieci 25 h od udanego sprawdzenia -> czerwona sprawa 'Od ponad doby', bez 'Wszystko gra'" = "Proba-BezSieciDoba"
  "negatywna: bez-sieci, nigdy udane, pierwsza proba 25 h temu -> czerwona sprawa" = "Proba-BezSieciNigdyDoba"
  "negatywna: bez-sieci, ale ostatnia proba 4 h temu (martwy zegar) -> zolta sprawa" = "Proba-BezSieciMartwyZegar"
  "negatywna: blad z inna przyczyna (nanoszenie) -> dalej czerwono" = "Proba-InnaPrzyczynaCzerwona"
}
foreach ($nazwa in $PROBY_SIECI.Keys) {
  $w = & $PROBY_SIECI[$nazwa]
  Wynik $nazwa $w.Ok $w.Opis
}

# Sabotaz: kopia stan-wersja.ps1 z wylaczonym jednym warunkiem, wczytana w miejsce prawdziwej.
# Wlasciwa proba MUSI wtedy paść - inaczej nie pilnuje niczego. Kotwica sprawdzana przed podmiana
# (brak kotwicy = porazka testu, a nie sabotaz, ktory po cichu niczego nie zmienil).
$plikWersji = Join-Path $Zasobnik "nadzorca\stan-wersja.ps1"
$oryginal = [System.IO.File]::ReadAllText($plikWersji, [System.Text.Encoding]::UTF8)
$sabotaze = @(
  @{ Nazwa = "warunek doby wylaczony"; Proba = "Proba-BezSieciDoba"
     Kotwica = '(($teraz - $odKiedy).TotalHours -ge $GODZIN_BEZ_UDANEGO_SPRAWDZENIA)'; Zamiana = '$false' },
  @{ Nazwa = "kazda przyczyna uznana za chwilowa"; Proba = "Proba-InnaPrzyczynaCzerwona"
     Kotwica = '($PRZYCZYNY_CHWILOWE -contains $a.Przyczyna)'; Zamiana = '$true' },
  @{ Nazwa = "bez-sieci znowu czerwone co godzine"; Proba = "Proba-BezSieciSwieza"
     Kotwica = '$PRZYCZYNY_CHWILOWE = @("bez-sieci", "zajete")'; Zamiana = '$PRZYCZYNY_CHWILOWE = @()' },
  @{ Nazwa = "martwy zegar przy bez-sieci niewidoczny"; Proba = "Proba-BezSieciMartwyZegar"
     Kotwica = '(($teraz - $proba).TotalHours -ge $GODZIN_BEZ_SPRAWDZENIA_AKTUALIZACJI)'; Zamiana = '$false' })
$kopiaSabotazu = Join-Path $tmp "stan-wersja-sabotaz.ps1"
foreach ($s in $sabotaze) {
  if (-not $oryginal.Contains($s.Kotwica)) { Wynik "sabotaz '$($s.Nazwa)' wylapany" $false "kotwicy nie ma w ${plikWersji}: $($s.Kotwica)"; continue }
  [System.IO.File]::WriteAllText($kopiaSabotazu, $oryginal.Replace($s.Kotwica, $s.Zamiana), (New-Object System.Text.UTF8Encoding($true)))
  . $kopiaSabotazu
  $pod = $null
  try { $pod = & $s.Proba } catch { $pod = [pscustomobject]@{ Ok = $false; Opis = "WYWROTKA: $($_.Exception.Message)" } }
  . $plikWersji
  $po = & $s.Proba
  Wynik "sabotaz '$($s.Nazwa)' wylapany przez $($s.Proba)" ((-not $pod.Ok) -and $po.Ok) "z sabotazem: $($pod.Opis) || po przywroceniu: Ok=$($po.Ok)"
}
. $plikWersji

# nieswiezy wynik
$stary = $teraz.AddHours(-4)
Atrapa @{ etap = "gotowe"; wynik = "aktualne"; koniec = (Iso $stary); sprawdzone = (Iso $stary) }
$o = O
Wynik "negatywna: 4 h bez sprawdzenia -> zolta linia, dopisek i sprawa" (($o.Waga -eq "uwaga") -and $o.Dopisek -and ($o.Problem.Waga -eq "uwaga") -and ($o.Problem.Tytul -match 'nie sprawdzała serwera')) "$($o.Problem.Tytul) | $($o.Dopisek)"
$o = O $teraz.AddMinutes(-5)
Wynik "4 h bez sprawdzenia, ale nadzorca od 5 min (komputer byl wylaczony) -> bez sprawy" (-not $o.Problem) "$($o.Problem.Tytul)"
$o = O $teraz.AddHours(-5)
Wynik "negatywna: 4 h bez sprawdzenia przy nadzorcy od 5 h -> sprawa" ($o.Problem.Waga -eq "uwaga") "$($o.Problem.Tytul)"
$s2 = $teraz.AddHours(-2)
Atrapa @{ etap = "gotowe"; wynik = "aktualne"; koniec = (Iso $s2); sprawdzone = (Iso $s2) }
$o = O $teraz.AddHours(-5)
Wynik "2 h od sprawdzenia -> jeszcze swiezo" ((-not $o.Problem) -and ($o.Waga -eq "dobrze")) $o.Linia

# urwana w polowie, nieczytelny plik, nieznany etap
Atrapa @{ etap = "pobieram"; krok = 2; start = (Iso $teraz.AddMinutes(-40)) }
[System.IO.File]::SetLastWriteTime($plikAkt, $teraz.AddMinutes(-30))
$o = O
Wynik "negatywna: pobieranie bez zapisu od 30 min -> czerwone 'stanęła', nie wieczny pasek" ((-not $o.Trwa) -and ($o.Waga -eq "pilne") -and ($o.Linia -match 'stanęła na kroku 2 z 4') -and ($o.Problem.Waga -eq "pilne")) $o.Linia
[System.IO.File]::WriteAllText($plikAkt, '{"etap": "pobi', (New-Object System.Text.UTF8Encoding($false)))
$o = O
Wynik "negatywna: nieczytelny plik -> zolta linia i sprawa" (($o.Waga -eq "uwaga") -and ($o.Problem.Tytul -match 'Nie umiem odczytać') -and $o.ZPliku) "$($o.Problem.Tytul) | $($o.Problem.Pelne)"
Atrapa @{ etap = "lece" }
$o = O
Wynik "negatywna: nieznany etap -> zolta sprawa" (($o.Problem.Waga -eq "uwaga") -and ($o.Problem.Pelne -match "nieznany etap 'lece'")) $o.Problem.Pelne

# klikniecie
Atrapa @{ etap = "gotowe"; wynik = "aktualne"; start = (Iso $teraz.AddMinutes(-30)); koniec = (Iso $teraz.AddMinutes(-30)); sprawdzone = (Iso $teraz.AddMinutes(-30)) }
$o = O $null $teraz.AddSeconds(-5)
Wynik "klik 5 s temu, plik jeszcze stary -> od razu pasek na kroku 1" ($o.Trwa -and ($o.Naglowek -like "*(1 z 4)") -and (-not $o.Przycisk)) $o.Naglowek
$o = O $null $teraz.AddSeconds(-40)
Wynik "negatywna: klik 40 s temu bez sladu w pliku -> czerwone 'nie udało się uruchomić'" ((-not $o.Trwa) -and ($o.Waga -eq "pilne") -and ($o.Linia -match 'nie zapisała ani śladu')) $o.Linia
$o = O $null $teraz.AddSeconds(-1) "brakuje pliku X\aktualizuj-megaruchacza.ps1"
Wynik "negatywna: skrypt nie ruszyl -> czerwone z powodem od razu" ((-not $o.Trwa) -and ($o.Linia -eq "Nie udało się uruchomić aktualizacji: brakuje pliku X\aktualizuj-megaruchacza.ps1.")) $o.Linia
Atrapa @{ etap = "pobieram"; krok = 2; start = (Iso (Get-Date)) }
$o = O $null $teraz.AddSeconds(-1)
Wynik "klik, plik odpowiedzial -> postep z pliku" ($o.Trwa -and ($o.Naglowek -like "*(2 z 4)")) $o.Naglowek

# przycisk: Aktualizuj nie czeka na skrypt
$zr = Join-Path $tmp "zrodlo"
New-Item -ItemType Directory -Force -Path (Join-Path $zr "narzedzia") | Out-Null
[System.IO.File]::WriteAllText((Join-Path $zr "dom.txt"), $dom)
[System.IO.File]::WriteAllText((Join-Path $zr "opoznienie.txt"), "3000")
$atrapa = @'
param([string]$Zrodlo, [switch]$Reczna)
$ErrorActionPreference = "Stop"
$dom = ([System.IO.File]::ReadAllText((Join-Path $Zrodlo "dom.txt"))).Trim()
$opoz = [int](([System.IO.File]::ReadAllText((Join-Path $Zrodlo "opoznienie.txt"))).Trim())
[System.IO.File]::AppendAllText((Join-Path $Zrodlo "wywolania.txt"), "$Zrodlo|$Reczna|$(Get-Date -Format o)`r`n")
$plik = Join-Path $dom ".claude\mr\aktualizacja.json"
$start = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
function Z($etap, $krok, $opis, $wynik) {
  $o = [ordered]@{ etap = $etap; krok = $krok; krokow = 4; opis = $opis; wynik = $wynik; wersja_przed = "0.28.0"; wersja_po = "0.28.0"
                   start = $start; koniec = ""; sprawdzone = ""; powod = ""; reczna = [bool]$Reczna }
  if ($etap -eq "gotowe") { $o.koniec = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss"); $o.sprawdzone = $o.koniec }
  $t = "$plik.tmp"
  [System.IO.File]::WriteAllText($t, ($o | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $t -Destination $plik -Force
}
Z "sprawdzam" 1 "Sprawdzam, czy jest cos nowego..." ""
Start-Sleep -Milliseconds $opoz
Z "pobieram" 2 "Pobieram nowa wersje..." ""
Start-Sleep -Milliseconds $opoz
Z "gotowe" 4 "" "aktualne"
'@
$skryptAtrapy = Join-Path $zr "narzedzia\aktualizuj-megaruchacza.ps1"
$zrBez = Join-Path $tmp "zrodlo-bez"
New-Item -ItemType Directory -Force -Path (Join-Path $zrBez "narzedzia") | Out-Null
$r = $null
Ustaw-Nadzorce $zrBez $dom $false
try { $r = Aktualizuj } catch { $r = [pscustomobject]@{ Ok = $true; Powod = "WYWROTKA: $($_.Exception.Message)" } }
Wynik "negatywna: przycisk bez skryptu aktualizacji -> Ok=false z powodem" ((-not $r.Ok) -and ($r.Powod -match 'brakuje pliku')) $r.Powod
[System.IO.File]::WriteAllText($skryptAtrapy, $atrapa, (New-Object System.Text.UTF8Encoding($true)))
Ustaw-Nadzorce $zr $dom $true
$r = Aktualizuj
Wynik "przycisk w trybie probnym niczego nie uruchamia" ($r.Proba -and (-not $r.Ok) -and -not (Test-Path (Join-Path $zr "wywolania.txt"))) $r.Powod
if (-not $BezOkna) {
  # bez okna przycisk sprawdzamy tylko w czesci z oknem (klikniecie), tu - samo uruchomienie
}
[System.IO.File]::WriteAllText((Join-Path $zr "opoznienie.txt"), "300")
Bez-Pliku
Ustaw-Nadzorce $zr $dom $false
$t0 = [datetime]::Now
$r = Aktualizuj
$ile = ([datetime]::Now - $t0).TotalSeconds
$wyw = ""
for ($i = 0; $i -lt 60; $i++) { if (Test-Path (Join-Path $zr "wywolania.txt")) { $wyw = [System.IO.File]::ReadAllText((Join-Path $zr "wywolania.txt")) }; if ($wyw -and (Test-Path $plikAkt) -and ((Stan-Aktualizacji).Etap -eq "gotowe")) { break }; Start-Sleep -Milliseconds 250 }
Wynik "przycisk: skrypt w tle z -Zrodlo i -Reczna, powrot bez czekania" ($r.Ok -and ($ile -lt 2) -and ($wyw -like "$zr|True|*")) ("{0:N2} s, pid {1}, wywolanie: {2}" -f $ile, $r.Pid, $wyw.Trim())
Wynik "przycisk: atrapa doszla do konca (gotowe/aktualne)" (((Stan-Aktualizacji).Wynik -eq "aktualne")) "$((Stan-Aktualizacji).Etap)/$((Stan-Aktualizacji).Wynik)"
Remove-Item -LiteralPath (Join-Path $zr "wywolania.txt") -Force -ErrorAction SilentlyContinue
Ustaw-Nadzorce $Zrodlo $dom $true

# ---------------------------------------------------------------- B. okno poza ekranem
if (-not $BezOkna) {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
public class OknoTestoweAktualizacji : System.Windows.Forms.Form {
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override System.Windows.Forms.CreateParams CreateParams {
    get { System.Windows.Forms.CreateParams cp = base.CreateParams; cp.ExStyle |= 0x08000000 | 0x00000080; return cp; }
  }
}
'@
  $script:NadzWywrotki = @()
  foreach ($m in @("wyglad", "karty", "przeglad", "okno")) { . (Join-Path $Zasobnik "nadzorca\$m.ps1") }
  # podsluch: po udanej aktualizacji (bez restartu) liczby licza sie od nowa - tylko wtedy
  $script:PrzeliczenPoAktualizacji = 0
  function Przelicz-W-Tle { $script:PrzeliczenPoAktualizacji++; return $null }
  $script:StanKawalkow = @{ rozbicie = [pscustomobject]@{ Czas = (Get-Date) }; warstwy = [pscustomobject]@{ Czas = (Get-Date) } }

  $f = New-Object OknoTestoweAktualizacji
  $f.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
  $f.Location = New-Object System.Drawing.Point(-5000, 0)
  $f.ShowInTaskbar = $false
  $f.KeyPreview = $true
  $f.Add_KeyDown({ param($n, $e) $e.Handled = $true; $e.SuppressKeyPress = $true })
  $f.ClientSize = New-Object System.Drawing.Size($script:SzerOkna, 640)
  $f.BackColor = $script:TloOkna
  $f.Font = $script:CzZwykla
  $script:WidokPrzeglad = New-Object System.Windows.Forms.Panel
  $script:WidokPrzeglad.Dock = [System.Windows.Forms.DockStyle]::Fill
  $script:WidokPrzeglad.AutoScroll = $true
  $script:WidokPrzeglad.Padding = New-Object System.Windows.Forms.Padding($script:Margines, 8, $script:Margines, 8)
  $script:Root = Pionowy $script:SzerTresc
  $script:Root.Dock = [System.Windows.Forms.DockStyle]::Top
  $script:PanelProblemy = Pionowy $script:SzerTresc
  $script:PanelProblemy.Visible = $false
  $script:PanelStan = Nowa-Karta $script:SzerKarty
  $script:Root.Controls.Add($script:PanelProblemy)
  $script:Root.Controls.Add($script:PanelStan)
  $script:WidokPrzeglad.Controls.Add($script:Root)
  $pasek = New-Object System.Windows.Forms.FlowLayoutPanel
  $pasek.Dock = [System.Windows.Forms.DockStyle]::Bottom
  $pasek.Height = 90
  $pasek.BackColor = $script:TloPaska
  $script:BAktualizuj = Nowy-Przycisk "x"
  $script:BAktualizuj.Width = 420
  # to samo podpiecie co w Pokaz-Okno (okno.ps1)
  $script:BAktualizuj.Add_Click({ try { Kliknij-Aktualizuj } catch { Zanotuj-Wywrotke "przycisk aktualizacji" $_ } })
  $script:LAktualizuj = Etykieta-Zawijana "" $script:CzMala $script:KolSzary 400
  $script:BCykl = Nowy-Przycisk "x"; $script:LCykl = Etykieta "" $script:CzMala $script:KolSzary
  $script:BInstalacja = Nowy-Przycisk "x"; $script:LInstalacja = Etykieta "" $script:CzMala $script:KolSzary
  foreach ($c in @($script:BAktualizuj, $script:LAktualizuj)) { $pasek.Controls.Add($c) }
  $f.Controls.Add($script:WidokPrzeglad)
  $f.Controls.Add($pasek)
  $script:Okno = $f
  $script:Dane = $D
  $script:Instalacja = $inst
  $script:Widok = "przeglad"
  $f.Show()
  [System.Windows.Forms.Application]::DoEvents()

  function Teksty($c) {
    $l = @()
    foreach ($d in $c.Controls) { if (-not $d.Visible) { continue }; if ("$($d.Text)") { $l += "$($d.Text)" }; $l += Teksty $d }
    return $l
  }
  function Paski($c) {
    $n = 0
    foreach ($d in $c.Controls) { if (-not $d.Visible) { continue }; if ($d -is [System.Windows.Forms.PictureBox]) { $n++ }; $n += Paski $d }
    return $n
  }
  function Zrzut([string]$nazwa) {
    $f.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    $b = New-Object System.Drawing.Bitmap($f.Width, $f.Height)
    $f.DrawToBitmap($b, (New-Object System.Drawing.Rectangle(0, 0, $f.Width, $f.Height)))
    $p = Join-Path $Zrzuty "akt-$nazwa.png"
    $b.Save($p); $b.Dispose()
    return $p
  }
  function Krok-Okna { Sprawdz-Aktualizacje; [System.Windows.Forms.Application]::DoEvents() }

  try {
    Bez-Pliku
    Krok-Okna
    $t = (Teksty $script:PanelStan) -join " | "
    Wynik "okno: brak pliku -> stary wiersz wersji, 'Wszystko gra'" (($t -match 'Wersja MegaRuchacza') -and ($t -match 'Wszystko gra') -and ($t -notmatch 'Aktualizacja MegaRuchacza')) $t
    [void](Zrzut "0-brak-pliku")

    Atrapa @{ etap = "pobieram"; krok = 2; opis = "Pobieram nową wersję..." }
    Krok-Okna
    $t = (Teksty $script:PanelStan) -join " | "
    $ok = ($t -match 'Aktualizacja MegaRuchacza') -and ($t -match 'Pobieram nową wersję\.\.\. \(2 z 4\)') -and ($t -match "1\. Sprawdzam, czy jest coś nowego \| $ZNAKOK") -and
          ($t -match '2\. Pobieram \| \.\.\.') -and ($t -match '3\. Wgrywam do Claude Code / Codeksa / OpenCode') -and ($t -notmatch 'Wersja MegaRuchacza') -and ((Paski $script:PanelStan) -eq 1)
    Wynik "okno: w trakcie pasek, opis kroku i cztery kroki zamiast wiersza wersji" $ok $t
    Wynik "okno: w trakcie przycisk wyszarzony z opisem 'Aktualizacja trwa'" ((-not $script:BAktualizuj.Enabled) -and ($script:LAktualizuj.Text -like "Aktualizacja trwa*")) "$($script:BAktualizuj.Enabled) '$($script:LAktualizuj.Text)'"
    Wynik "zrzut w trakcie" $true (Zrzut "1-w-trakcie")

    $kon = (Get-Date).AddMinutes(-1)
    Atrapa @{ etap = "gotowe"; wynik = "zaktualizowano"; wersja_po = "0.29.0"; koniec = (Iso $kon); sprawdzone = (Iso $kon) }
    Krok-Okna
    $t = (Teksty $script:PanelStan) -join " | "
    Wynik "okno: po aktualizacji sama linia wyniku, bez paska" (($t -match "$ZNAKOK Zaktualizowano do najnowszej wersji 0\.29\.0 \(dziś $(Godz $kon)\)") -and ((Paski $script:PanelStan) -eq 0) -and $script:BAktualizuj.Enabled) $t
    Wynik "okno: po udanej aktualizacji liczby licza sie od nowa (raz)" ($script:PrzeliczenPoAktualizacji -eq 1) "przeliczen: $($script:PrzeliczenPoAktualizacji)"
    Wynik "zrzut po aktualizacji" $true (Zrzut "2-zaktualizowano")

    Atrapa @{ etap = "gotowe"; wynik = "aktualne"; koniec = (Iso $kon); sprawdzone = (Iso $kon) }
    Krok-Okna
    $t = (Teksty $script:PanelStan) -join " | "
    Wynik "okno: aktualne -> linia i 'Wszystko gra'" (($t -match "$ZNAKOK Masz najnowszą wersję 0\.28\.0 \(sprawdzone dziś") -and ($t -match 'Wszystko gra') -and (-not $script:PanelProblemy.Visible)) $t
    [void](Zrzut "3-aktualne")

    Atrapa @{ etap = "blad"; wynik = "blad"; koniec = (Iso $kon); powod = "Nie ma połączenia z serwerem. Sprawdź internet - spróbuję sam za godzinę." }
    Krok-Okna
    $t = (Teksty $script:PanelStan) -join " | "
    $tp = (Teksty $script:PanelProblemy) -join " | "
    $czerw = $false
    foreach ($c in $script:PanelStan.Controls) { foreach ($x in $c.Controls) { foreach ($y in $x.Controls) { if (("$($y.Text)" -like "$ZNAKZLE*") -and ($y.ForeColor.ToArgb() -eq $script:KolPilne.ToArgb())) { $czerw = $true } } } }
    Wynik "negatywna okno: blad -> czerwona linia, karta 'Wymaga działania' na gorze, bez 'Wszystko gra'" ($czerw -and ($t -notmatch 'Wszystko gra') -and $script:PanelProblemy.Visible -and
      ($tp -match 'WYMAGA DZIAŁANIA') -and ($tp -match 'Nie udało się zaktualizować MegaRuchacza') -and ((Ile-Wymaga-Uwagi $script:Problemy) -ge 1)) "$t || $tp"
    Wynik "zrzut bledu" $true (Zrzut "4-blad")

    Atrapa @{ etap = "blad"; wynik = "blad"; przyczyna = "bez-sieci"; koniec = (Iso $kon); sprawdzone = (Iso (Get-Date).AddHours(-2)); powod = $POWOD_SIEC }
    Krok-Okna
    $t = (Teksty $script:PanelStan) -join " | "
    $szara = $false
    foreach ($c in $script:PanelStan.Controls) { foreach ($x in $c.Controls) { foreach ($y in $x.Controls) { if (("$($y.Text)" -like "Nie sprawdziłem aktualizacji*") -and ($y.ForeColor.ToArgb() -eq $script:KolSzary.ToArgb())) { $szara = $true } } } }
    Wynik "okno: bez-sieci -> szara linia, bez karty spraw, 'Wszystko gra'" ($szara -and ($t -match 'brak internetu') -and ($t -match 'Wszystko gra') -and (-not $script:PanelProblemy.Visible)) $t
    [void](Zrzut "4b-bez-sieci")

    $st = (Get-Date).AddHours(-4)
    Atrapa @{ etap = "gotowe"; wynik = "aktualne"; koniec = (Iso $st); sprawdzone = (Iso $st) }
    $script:NadzorcaOd = (Get-Date).AddHours(-6)
    Krok-Okna
    $t = (Teksty $script:PanelStan) -join " | "
    $tp = (Teksty $script:PanelProblemy) -join " | "
    Wynik "negatywna okno: nieswiezy wynik -> dopisek i zolta karta, bez 'Wszystko gra'" (($t -match 'Od ponad 3 godzin') -and ($tp -match 'nie sprawdzała serwera') -and ($t -notmatch 'Wszystko gra')) "$t || $tp"
    [void](Zrzut "5-nieswieze")

    # zegar okna: aktualizacja, ktorej nikt nie kliknal, pokazuje sie sama
    Atrapa @{ etap = "gotowe"; wynik = "aktualne"; koniec = (Iso (Get-Date)); sprawdzone = (Iso (Get-Date)) }
    Krok-Okna
    Rusz-Zegar-Aktualizacji
    Atrapa @{ etap = "nanosze"; krok = 3; opis = "Wgrywam do Claude Code / Codeksa / OpenCode..." }
    $widac = $false; $najdluzej = 0.0
    $do = [datetime]::Now.AddSeconds(6)
    while ([datetime]::Now -lt $do) {
      $t1 = [datetime]::Now
      [System.Windows.Forms.Application]::DoEvents()
      $najdluzej = [math]::Max($najdluzej, ([datetime]::Now - $t1).TotalMilliseconds)
      if (((Teksty $script:PanelStan) -join " ") -match '\(3 z 4\)') { $widac = $true; break }
      Start-Sleep -Milliseconds 50
    }
    Wynik "okno: zegar sam pokazuje aktualizacje bez klikniecia" $widac ("najdluzszy przebieg petli komunikatow {0:N0} ms" -f $najdluzej)

    # klikniecie w trybie probnym: nic nie rusza, mowi to pod przyciskiem
    Atrapa @{ etap = "gotowe"; wynik = "aktualne"; koniec = (Iso (Get-Date)); sprawdzone = (Iso (Get-Date)) }
    Krok-Okna
    $script:BAktualizuj.PerformClick()
    [System.Windows.Forms.Application]::DoEvents()
    Wynik "okno: klikniecie w trybie probnym -> 'Tryb próbny' i nic nie ruszylo" (($script:LAktualizuj.Text -like "Tryb próbny*") -and -not (Test-Path (Join-Path $zr "wywolania.txt"))) $script:LAktualizuj.Text

    # klikniecie naprawde: atrapa w tle, okno nie zamarza, pasek -> wynik
    [System.IO.File]::WriteAllText((Join-Path $zr "opoznienie.txt"), "2500")
    Atrapa @{ etap = "gotowe"; wynik = "aktualne"; start = (Iso (Get-Date).AddHours(-1)); koniec = (Iso (Get-Date).AddHours(-1)); sprawdzone = (Iso (Get-Date).AddHours(-1)) }
    $script:NadzorcaOd = (Get-Date).AddMinutes(-30)
    $script:NadzZrodlo = $zr; $script:NadzProba = $false
    Krok-Okna
    $t0 = [datetime]::Now
    $script:BAktualizuj.PerformClick()
    $klik = ([datetime]::Now - $t0).TotalSeconds
    $odRazu = ((Teksty $script:PanelStan) -join " ") -match '\(1 z 4\)'
    $widziane = @{}
    $do = [datetime]::Now.AddSeconds(20)
    while ([datetime]::Now -lt $do) {
      [System.Windows.Forms.Application]::DoEvents()
      $tx = (Teksty $script:PanelStan) -join " "
      foreach ($w in @('\(1 z 4\)', '\(2 z 4\)', 'Masz najnowszą wersję')) { if ($tx -match $w) { $widziane[$w] = $true } }
      if ($widziane['Masz najnowszą wersję']) { break }
      Start-Sleep -Milliseconds 50
    }
    Wynik "okno: klikniecie wraca od razu i od razu pokazuje krok 1" (($klik -lt 2) -and $odRazu -and (-not $script:BAktualizuj.Enabled -or $widziane['Masz najnowszą wersję'])) ("klikniecie {0:N2} s" -f $klik)
    Wynik "okno: po kliknieciu widac krok 2 i wynik, bez czekania na reke" ($widziane['\(2 z 4\)'] -and $widziane['Masz najnowszą wersję'] -and $script:BAktualizuj.Enabled) (($widziane.Keys) -join ", ")
    [void](Zrzut "6-po-kliknieciu")
    $script:NadzZrodlo = $Zrodlo; $script:NadzProba = $true
  } catch {
    Wynik "okno: WYWROTKA TESTU" $false "$($_.Exception.Message) @ $($_.InvocationInfo.PositionMessage)"
  } finally {
    if ($script:ZegarAktualizacji) { $script:ZegarAktualizacji.Stop() }
    $f.Close(); $f.Dispose()
  }
  $wywr = @($script:NadzWywrotki)
  Wynik "okno: bez wywrotek nadzorcy" ($wywr.Count -eq 0) ($wywr -join " || ")
}

Write-Host ""
Write-Host "Zrzuty: $Zrzuty"
Write-Host "Wynik: $(@($script:wyniki | Where-Object { $_.OK }).Count) z $($script:wyniki.Count) TAK. Pliki robocze: $tmp"
if (@($script:wyniki | Where-Object { -not $_.OK }).Count -gt 0) { exit 1 }
exit 0
