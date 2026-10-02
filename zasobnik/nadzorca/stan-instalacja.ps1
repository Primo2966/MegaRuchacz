# zasobnik\nadzorca\stan-instalacja.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Ktore moduly MegaRuchacza sa zainstalowane (P59d): odczyt
# wspolnego rejestru (Stan-Instalacji), pytanie o jeden modul (Modul-Jest), tematy
# alarmow rachunku nalezace do nauki z rozmow (Temat-Nauki), nazwy i opis po ludzku
# (Nazwy-Modulow, Opis-Instalacji), porownanie dwoch odczytow (Moduly-Rowne) i alarm
# przy nieczytelnym rejestrze (Alarm-Instalacji).
# Skad wolane: stan-zbieranie.ps1 (Zbierz-Wszystko -> $d.Instalacja), stan-cykl.ps1
# i stan-skille.ps1 (decyzje dozoru), stan-alarmy.ps1, stan-po-ludzku.ps1, stan-koszt.ps1,
# stan-kopia.ps1, moduly okna (co pokazac). Wczytuje go stan-nadzorcy.ps1 kropka -
# poza stalymi same definicje.
#
# Rejestr pisze instalator (instalator\, narzedzia\instalacja\modul-*.ps1). Format
# i zasady odczytu sa w naglowku narzedzia\instalacja\stan.ps1 i TU ICH NIE POWTARZAMY:
# Stan-Instalacji wczytuje tamten plik kropka, zeby nadzorca, straznik i hooki czytaly
# rejestr jednym kodem i nie rozjechaly sie przy pierwszej zmianie umowy. Dla okna
# i dozoru znaczy to:
#   - brak pliku = instalacja sprzed rejestru (komputery sprzed instalatora): wszystko
#     jak dotad - nauka, Lore, kierownik i skille wlaczone, kopia tylko tam, gdzie juz
#     chodzila (jest jej plik stanu);
#   - plik nieczytelny (pusty, wyzerowany, zly JSON) albo nie da sie wczytac samej umowy
#     = WSZYSTKO wlaczone, takze kopia, i pilny alarm. Pokazac za duzo jest bezpieczniej
#     niz schowac cos, co uzytkownik ma: dozor dalej rusza nauke i skille, okno dalej
#     pokazuje ich stan, dopoki ktos nie naprawi rejestru (umowa: przy bledzie nic nie
#     wolno odinstalowac).

$NADZ_MODULY = @("wiedza", "lore", "kierownik", "skille", "kopia")
$NAZWY_MODULOW = @{ wiedza = "Wiedza"; lore = "Lore"; kierownik = "Kierownik"; skille = "Skille"; kopia = "Kopia zapasowa" }

function Plik-Rejestru-Instalacji { return (Join-Path $script:NadzDom ".claude\mr\instalacja.json") }

# Odczyt rejestru. Zwraca obiekt zawsze; Blad mowi, czego nie dalo sie odczytac
# (wtedy Moduly = wszystkie wlaczone). Czas = chwila odczytu - okno nie przyjmuje
# odczytu starszego niz ten, ktory juz ma (dozor liczony przed zmiana instalacji).
function Stan-Instalacji {
  $w = [pscustomobject]@{
    Moduly = $null; Zrodlo = ""; Blad = ""; Plik = (Plik-Rejestru-Instalacji); Kopia = $null; Data = ""
    Czas = [datetime]::Now
  }
  $umowa = Join-Path $script:NadzZrodlo "narzedzia\instalacja\stan.ps1"
  $s = $null
  try {
    if (-not (Test-Path -LiteralPath $umowa -PathType Leaf)) { throw "nie ma pliku $umowa" }
    # Kropka wewnatrz funkcji: funkcje umowy (Czytaj-Instalacje i reszta) zyja tylko do
    # konca tej funkcji - nie zasmiecaja nadzorcy i nie zderzaja sie z jego nazwami.
    . $umowa
    $s = Czytaj-Instalacje $script:NadzDom
  } catch {
    $w.Blad = "nie da się wczytać umowy rejestru ($umowa): $($_.Exception.Message)"
  }
  $m = [ordered]@{}
  foreach ($n in $NADZ_MODULY) { $m[$n] = $true }
  if ($s) {
    $w.Zrodlo = "$($s.zrodlo)"
    $w.Data = "$($s.data)"
    $w.Kopia = $s.kopia
    if ($s.blad) { $w.Blad = "$($s.blad)" }
    elseif ($s.moduly) {
      # [bool] jak w Modul-Wlaczony umowy - ta sama odpowiedz, co u straznika i instalatora
      foreach ($n in $NADZ_MODULY) { if ($null -ne $s.moduly.$n) { $m[$n] = [bool]$s.moduly.$n } }
    }
  }
  if ($w.Blad) {
    $w.Zrodlo = "awaryjne"
    foreach ($n in $NADZ_MODULY) { $m[$n] = $true }
  }
  $w.Moduly = [pscustomobject]$m
  return $w
}

# Czy modul jest. Bez odczytu (wywrotka, stare dane bez pola) = jest - tak samo jak
# przy nieczytelnym rejestrze: lepiej pokazac i pilnowac za duzo niz za malo.
function Modul-Jest($inst, [string]$nazwa) {
  if (-not $inst -or -not $inst.Moduly) { return $true }
  $v = $inst.Moduly.$nazwa
  if ($null -eq $v) { return $true }
  return [bool]$v
}

# Alarmy i informacje z rachunku, ktore mowia o NAUCE Z ROZMOW (koszt-pamieci.ps1,
# narzedzia\koszt\alarmy.ps1 i nauka.ps1): cykl-zwykly, cykl-rosnie, cykl-nadrabianie,
# cykl-nieznany i dziennik kosztow nauki (historia). Bez modulu Wiedza nie ma o czym
# mowic - stare pliki kosztu nauki zostaja na dysku, ale nauka juz nie chodzi.
function Temat-Nauki([string]$temat) {
  return ($temat -match '^(codex-)?(cykl-|historia$)')
}

# "Wiedza, Lore, Kierownik" - nazwy wlaczonych ($true) albo wylaczonych ($false) modulow.
function Nazwy-Modulow($inst, [bool]$wlaczone = $true) {
  $l = @()
  foreach ($n in $NADZ_MODULY) { if ((Modul-Jest $inst $n) -eq $wlaczone) { $l += $NAZWY_MODULOW[$n] } }
  return ,$l
}

# Ten sam zestaw modulow w dwoch odczytach (bez patrzenia na czas i sciezki).
function Moduly-Rowne($a, $b) {
  foreach ($n in $NADZ_MODULY) { if ((Modul-Jest $a $n) -ne (Modul-Jest $b $n)) { return $false } }
  return ($("$($a.Blad)" -eq "") -eq $("$($b.Blad)" -eq ""))
}

# Wiersze do Szczegolow (sekcja "Nadzorca i gdzie co leży").
function Opis-Instalacji($inst) {
  $w = @()
  if (-not $inst) {
    $w += Wiersz "Moduły" "nie wiem - odczyt rejestru instalacji się wywrócił; pokazuję wszystko jak przy pełnej instalacji" "uwaga"
    return ,$w
  }
  $jest = Nazwy-Modulow $inst $true
  $nie = Nazwy-Modulow $inst $false
  $w += Wiersz "Moduły" ("$(if ($jest.Count -gt 0) { $jest -join ', ' } else { 'żaden' }) - i zawsze aplikacja przy zegarze z aktualizacjami") $(if ($inst.Blad) { "uwaga" } else { "" })
  if ($nie.Count -gt 0) { $w += Wiersz "Niezainstalowane" ($nie -join ", ") "szary" }
  switch ("$($inst.Zrodlo)") {
    "plik"     { $w += Wiersz "Rejestr instalacji" "$($inst.Plik)$(if ($inst.Data) { ' (zapisany ' + $inst.Data + ')' })" "szary" }
    "domyslne" { $w += Wiersz "Rejestr instalacji" "nie ma pliku $($inst.Plik) - instalacja sprzed rejestru, więc wszystko jak dotąd (kopia zapasowa tylko, gdy już chodziła)" "szary" }
    default    { $w += Wiersz "Rejestr instalacji" "NIECZYTELNY: $($inst.Blad) - dopóki tak jest, okno i dozór działają jak przy pełnej instalacji" "pilne" }
  }
  return ,$w
}

# Pilny alarm przy nieczytelnym rejestrze (temat "instalacja" - jeden na dobe w dzienniku).
# Naprawa: instalator zapisuje wybor od nowa; dopoki go nie ma - usuniecie pliku wraca
# do zestawu sprzed rejestru (umowa: brak pliku = stara instalacja).
function Alarm-Instalacji($inst) {
  if (-not $inst -or -not $inst.Blad) { return $null }
  $instalator = Test-Path -LiteralPath (Join-Path $script:NadzZrodlo "instalator\okno.ps1") -PathType Leaf
  $naprawa = $(if ($instalator) { "Kliknij `„Zmień instalację`” na dole okna i zapisz wybór modułów jeszcze raz." }
               else { "Instalator jest jeszcze w przygotowaniu - usuń uszkodzony plik rejestru (ścieżka w szczegółach), a MegaRuchacz wróci do zestawu sprzed rejestru." })
  return (Alarm "instalacja" "MegaRuchacz: nie umiem odczytać, co jest zainstalowane" (
    "Rejestr zainstalowanych modułów jest nieczytelny: $($inst.Blad). " +
    "Do czasu naprawy okno i dozór działają jak przy pełnej instalacji (wszystkie moduły włączone) i nic nie jest odinstalowywane. " +
    "$naprawa Plik rejestru: $($inst.Plik)") "pilne" (
    "Plik, w którym zapisany jest wybór modułów, jest uszkodzony (zwykle po zaniku prądu). Do czasu naprawy pokazuję i pilnuję wszystkiego jak przy pełnej instalacji. $naprawa"))
}

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["instalacja"] = $true
