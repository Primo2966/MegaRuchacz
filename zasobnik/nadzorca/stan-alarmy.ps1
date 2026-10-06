# zasobnik\nadzorca\stan-alarmy.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Alarmy: jeden na sprawe na dobe (Alarm, Alarm-Juz-Byl,
# Odnotuj-Alarm), wywrotki straznika (Wywrotki-Straznika) i zlozenie wszystkich
# alarmow z cyklu i rachunku (Zbierz-Alarmy).
# Skad wolane: stan-zbieranie.ps1 (Zbierz-Alarmy), dozor.ps1 (Alarm-Juz-Byl,
# Odnotuj-Alarm). Wczytuje go stan-nadzorcy.ps1 kropka - same definicje.

# -------------------------------------------------------------------- alarmy

# Kazdy alarm ma TEMAT (po nim liczy sie "jeden na dobe"), TYTUL (do paska
# powiadomienia) i TRESC, ktora mowi CO ZROBIC. Alarm bez porady uczy tylko
# tego, zeby go zamykac nie czytajac.
# WAGA ("pilne" / "uwaga" / "info") - pusta znaczy "wedlug tematu" (Waga-Alarmu).
# PORADA - gotowe zdania dla czlowieka; pusta znaczy "odsiej je z tresci"
# (Porada-Ludzka), tak jak dotad.
function Alarm([string]$temat, [string]$tytul, [string]$tresc, [string]$waga = "", [string]$porada = "") {
  return [pscustomobject]@{ Temat = $temat; Tytul = $tytul; Tresc = $tresc; Waga = $waga; Porada = $porada }
}

# Czy alarm o tym temacie juz dzis poszedl. Jeden na sprawe na dobe - inaczej
# nadzorca zasypuje pulpit i uczy ignorowania.
function Alarm-Juz-Byl([string]$temat) {
  $stan = Czytaj-Klucze $script:NadzPlikStanu
  return ($stan["alarm.$temat"] -eq (Get-Date -Format 'yyyy-MM-dd'))
}

function Odnotuj-Alarm([string]$temat) {
  if ($script:NadzProba) { return }
  try { Dopisz-Klucze $script:NadzPlikStanu @{ "alarm.$temat" = (Get-Date -Format 'yyyy-MM-dd') } }
  catch { Notuj "nie udalo sie odnotowac alarmu ${temat} - moze sie powtorzyc" }
}

# Wywrotki straznika czytamy BEZ czyszczenia: klucze blad.* naleza do straznika
# i to on melduje je w sesji (Odbierz-Wywrotki). Gdybysmy je tu sprzatneli,
# meldunek w oknie Claude Code przepadlby na zawsze.
function Wywrotki-Straznika {
  $plik = Join-Path $script:NadzDom ".claude\.megaruchacz-straznik.txt"
  $stan = Czytaj-Klucze $plik
  $linie = @()
  foreach ($k in @($stan.Keys)) {
    if ($k -notmatch '^blad\.\d+$') { continue }
    $cz = "$($stan[$k])" -split '\s*\|\s*', 4
    if ($cz.Count -eq 4) { $linie += "$($cz[2]) - $($cz[3]) ($($cz[1]))" }
    else { $linie += "$($stan[$k])" }
  }
  return ,$linie
}

# Cztery sprawy ze zlecenia plus piata: wlasne potkniecia nadzorcy z poprzedniego
# przebiegu. Zwraca komplet alarmow BEZ patrzenia na "raz na dobe" - o tym
# decyduje ten, kto je pokazuje.
# $inst = Stan-Instalacji (P59d): alarmy modulow, ktorych nie ma w instalacji, nie
# powstaja - bez modulu Wiedza nie ma nauki, ktora moglaby stac ($cykl jest wtedy
# pusty), bez modulu Kopia nie ma kopii, ktora moglaby byc stara.
function Zbierz-Alarmy($cykl, $rachunek, $inst = $null) {
  $alarmy = @()
  $wiedza = Modul-Jest $inst "wiedza"

  # TRESC ALARMU PISZEMY PO POLSKU Z OGONKAMI I BEZ ZARGONU, bo trafia prosto
  # na wierzch okna, do sekcji "co wymaga uwagi". Zdania z komendami i sciezkami
  # sa CELOWO osobnymi zdaniami: Porada-Ludzka odsiewa je z okna, a caly tekst
  # i tak zostaje w szczegolach i w dzienniku, wiec nic nie ginie.

  # 1. Nauka z rozmow stoi. Prog: doba - taki jest jej rytm pracy.
  $godzin = $null
  if ($cykl) { $godzin = Godzin-Od-Cyklu $cykl }
  if (-not ($wiedza -and $cykl)) {
    # nauki nie ma w instalacji - nie ma czego alarmowac
  } elseif ($null -eq $godzin) {
    $alarmy += Alarm "cykl" "MegaRuchacz: nauka z rozmów nie przeszła ani razu" (
      "Nie ma zapisu ani jednego zakończonego przebiegu, więc MegaRuchacz niczego się jeszcze nie nauczył z Twoich rozmów. " +
      "Kliknij ikonę MegaRuchacza i użyj przycisku [Przeczytaj teraz nowe rozmowy] - pokaże koszt i zapyta o zgodę. " +
      "Jesli to nie pomoze, sprawdz recznie: powershell -ExecutionPolicy Bypass -File " +
      "$($script:NadzZrodlo)\narzedzia\cykl-dzienny.ps1 -Proba")
  } elseif ($godzin -gt $GODZIN_CYKL_STOI) {
    $dni = [int]($godzin / 24)
    $ile = if ($dni -ge 1) { "${dni} $(Odmiana $dni 'dnia' 'dni' 'dni')" } else { "${godzin} $(Odmiana $godzin 'godziny' 'godzin' 'godzin')" }
    $czeka = ""
    if ($null -ne $cykl.Kawalki)       { $czeka = " Czeka $(Liczba-Ludzka $cykl.Kawalki) $(Odmiana ([int]$cykl.Kawalki) 'fragment rozmów' 'fragmenty rozmów' 'fragmentów rozmów')." }
    elseif ($null -ne $cykl.Zaleglosc) { $czeka = " Zaległość: $($cykl.Zaleglosc) $(Odmiana ([int]$cykl.Zaleglosc) 'porcja' 'porcje' 'porcji')." }
    $alarmy += Alarm "cykl" "MegaRuchacz: nauka z rozmów stoi od ${ile}" (
      "Ostatnio przeszła $(Kiedy-Ludzko $cykl.Data).${czeka} " +
      "Kliknij ikonę MegaRuchacza i użyj przycisku [Przeczytaj teraz nowe rozmowy] - pokaże koszt i zapyta o zgodę. " +
      "Jesli to nie rusza, sprawdz co blokuje: powershell -ExecutionPolicy Bypass -File " +
      "$($script:NadzZrodlo)\narzedzia\cykl-dzienny.ps1 -Proba")
  }

  # 2. Ucinanie - widac po kodzie 1 i slowie UCINANE w linii rachunku.
  if (($rachunek.Kod -eq 1) -and $rachunek.Linia -and ($rachunek.Linia -match 'UCINANE')) {
    $alarmy += Alarm "ucinane" "MegaRuchacz: część tekstu jest ucinana po cichu" (
      "Skrócony tekst nie dochodzi do modelu, a nikt o tym nie mówi. " +
      "Kliknij ikonę MegaRuchacza i otwórz zakładkę Szczegóły - tam widać, która pozycja nie mieści się w limicie. " +
      "Najczęściej pomaga skrócenie sekcji 'Co wiem' w Twoim pliku z wiedzą. " +
      "Rachunek mowi: $($rachunek.Linia). " +
      "Plik do skrocenia: $($script:NadzDom)\.claude\CLAUDE.md")
  }

  # 3. Progi kosztu - KAZDY alarm osobno, z tym, ZA CO i ZA JAKI OKRES jest
  # liczba. Do 24.09.2026 stal tu jeden zbiorczy "pamiec kosztuje wiecej, niz
  # powinna", ktory za jednorazowe nadrabianie zaleglosci swiecil na czerwono
  # i mowil o pamieci, choc chodzilo o nauke z rozmow. Zolte informacje (waga
  # "info") ida osobna droga - Zbierz-Informacje - i nie wyskakuja w dymku.
  $ocena = Ocena-Nauki $rachunek
  $czerwonych = 0
  foreach ($a in (Alarmy-Rachunku $rachunek)) {
    if ($a.Waga -eq "info") { continue }
    # koszt nauki z rozmow bez modulu Wiedza: stare pliki kosztu, nauka nie chodzi (P59d)
    if ((-not $wiedza) -and (Temat-Nauki $a.Temat)) { continue }
    if ($a.Waga -eq "pilne") { $czerwonych++ }
    $alarmy += Alarm-Z-Rachunku $a $ocena
  }
  # Kod 1 bez ucinania i bez ani jednego czerwonego alarmu na liscie znaczy, ze
  # nie umiemy odczytac, co rachunek zglasza - mowimy to wprost, zamiast zgadywac.
  if (($rachunek.Kod -eq 1) -and $rachunek.Linia -and ($rachunek.Linia -notmatch 'UCINANE') -and ($czerwonych -eq 0)) {
    $alarmy += Alarm "koszt" "MegaRuchacz: rachunek zgłasza przekroczony próg" (
      "Nie umiem odczytać, który próg - pełna treść jest w zakładce Szczegóły. " +
      "Rachunek mowi: $($rachunek.Linia). " +
      "Progi i ich uzasadnienie sa w $($script:NadzZrodlo)\narzedzia\koszt-pamieci.ps1") "uwaga"
  }
  if ((-not $rachunek.Linia) -and $rachunek.Powod) {
    $alarmy += Alarm "rachunek" "MegaRuchacz: nie umiem policzyć, ile kosztuje pamięć" (
      "Dopóki to trwa, nikt nie wie, ile kosztuje pamięć ani czy coś jest ucinane. " +
      "Powod: $($rachunek.Powod). " +
      "Sprawdz recznie: powershell -ExecutionPolicy Bypass -File " +
      "$($script:NadzZrodlo)\narzedzia\koszt-pamieci.ps1 -Rozbicie")
  }
  # 4. Straznik zanotowal wywrotke przy przebiegu, ktorego nikt nie ogladal.
  $wyw = Wywrotki-Straznika
  if ($wyw.Count -gt 0) {
    $ogon = ""
    if ($wyw.Count -gt 1) { $ogon = " (i jeszcze $($wyw.Count - 1))" }
    $alarmy += Alarm "wywrotka" "MegaRuchacz: aktualizacja w tle się wywróciła" (
      "Coś poszło nie tak przy przebiegu, którego nikt nie oglądał. " +
      "Kliknij ikonę MegaRuchacza i użyj przycisku [Pobierz nowszą wersję] - przejdzie jeszcze raz i powie, czy to się powtarza. " +
      "Blad: $($wyw[0])${ogon}. " +
      "Komplet w $($script:NadzDom)\.claude\.megaruchacz-straznik.txt (klucze blad.*) " +
      "oraz w $($script:NadzDom)\.claude\.megaruchacz-tlo.log")
  }
  # 5. Wyzerowane pliki pamięci - patrz Alarm-Wyzerowanej-Pamieci.
  $zera = Alarm-Wyzerowanej-Pamieci
  if ($zera) { $alarmy += $zera }
  # 6. Kopia zapasowa na Dysk Google stara albo z pominietymi uszkodzonymi plikami (P62) -
  # progi z uzasadnieniem w stan-kopia.ps1. Tylko z modulem Kopia (P59d).
  if (Modul-Jest $inst "kopia") {
    try {
      $kop = Alarm-Kopii $inst
      if ($kop) { $alarmy += $kop }
    } catch { Zanotuj-Wywrotke "alarm kopii zapasowej" $_ }
  }

  return ,$alarmy
}

# Pliki pamięci z bajtami 0x00 w środku. 2026-10-02 zanik prądu tuż po porannym cyklu
# zostawił CLAUDE.md i jedenaście plików wiedzy z pełną długością i samymi zerami - i nic
# tego nie zgłosiło. Żaden nasz plik tekstowy nie ma prawa mieć zera, więc próg to jedno
# zero (fałszywego alarmu z tego nie będzie). Lista plików ta sama, co w
# narzedzia\zapis-trwaly.ps1 (Pliki-Pamieci): pliki instrukcji z JEDNEJ listy narzędzi AI
# (narzedzia\kierownik-cele.ps1 Narzedzia-AI - czwarte CLI dopisane tam trafia tu samo),
# plus wiedza\. Moduły nadzorcy nie wczytują narzędzi, więc listę dołączamy tu, w zasięgu
# funkcji; bez niej (starsza kopia, wywrotka) - trzy pliki jak dotąd, a wywrotka idzie do
# stanu. Cykl i strażnik i tak nic na takich plikach nie robią; to jest głos do człowieka,
# który musi je przywrócić.
function Pliki-Instrukcji-Z-Listy {
  $lista = $null
  try {
    if (-not (Get-Command Narzedzia-AI -ErrorAction SilentlyContinue)) {
      $plikListy = Join-Path $script:NadzZrodlo "narzedzia\kierownik-cele.ps1"
      if (Test-Path -LiteralPath $plikListy) { . $plikListy }
    }
    if (Get-Command Narzedzia-AI -ErrorAction SilentlyContinue) { $lista = @(Narzedzia-AI | ForEach-Object { $_.Plik }) }
  } catch { Zanotuj-Wywrotke "lista narzedzi AI do alarmu o zerach" $_ }
  if (-not $lista) { $lista = @(".claude\CLAUDE.md", ".codex\AGENTS.md", ".config\opencode\AGENTS.md") }
  return ,$lista
}

function Alarm-Wyzerowanej-Pamieci {
  $dom = $script:NadzDom
  $pliki = @()
  foreach ($w in (Pliki-Instrukcji-Z-Listy)) {
    $p = Join-Path $dom $w
    if (Test-Path -LiteralPath $p -PathType Leaf) { $pliki += $p }
  }
  $wiedza = Join-Path $dom ".claude\wiedza"
  if (Test-Path -LiteralPath $wiedza) {
    foreach ($f in @(Get-ChildItem -LiteralPath $wiedza -File -Force)) {
      if ($f.Name -like "*.tmp-*") { continue }
      if ((@(".md", ".txt", ".tsv", ".json", ".jsonl", "") -contains $f.Extension.ToLower()) -or $f.Name.StartsWith(".")) { $pliki += $f.FullName }
    }
  }
  $zle = @()
  foreach ($p in $pliki) {
    try { $b = [System.IO.File]::ReadAllBytes($p) } catch { continue }
    if ([Array]::IndexOf($b, [byte]0) -ge 0) { $zle += $p }
  }
  if ($zle.Count -eq 0) { return $null }
  $polecenie = "powershell -ExecutionPolicy Bypass -File `"$($script:NadzZrodlo)\narzedzia\kopie-dzienne.ps1`" -Przywroc"
  return (Alarm "zera" "MegaRuchacz: pliki pamięci są wyzerowane" (
    "W środku zostały same zera, zwykle po zaniku prądu tuż po zapisie: " + ($zle -join ", ") + ". " +
    "Nauka z rozmów i strażnik nic na nich nie budują, dopóki ich nie przywrócisz. " +
    "Przywroc je z kopii dziennej (wczoraj albo przedwczoraj): $polecenie") "pilne" (
    "Przywróć pliki z kopii dziennej - gotowe polecenie jest w szczegółach. Do tego czasu nauka z rozmów stoi."))
}

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["alarmy"] = $true
