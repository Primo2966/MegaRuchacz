# narzedzia\koszt\tryb-rozbicie.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz
# BUDOWA w jego naglowku). Tryb -Rozbicie (Tryb-Rozbicie): trzy rachunki rozbite na
# pozycje, z paskiem i sciezka przy kazdej. Czyta go straznik
# (narzedzia\straznik-zasad.ps1, Policz-Rozbicie - pokazuje raz dziennie przy
# pierwszej sesji) i okno nadzorcy (zasobnik\stan-nadzorcy.ps1, Rachunek-Rozbicie).
# Skad wolane: koszt-pamieci.ps1 kropka po Etap-Ocena (exit 0 daje on).

# --- wypisanie: rozbicie na pozycje (raz dziennie, przy pierwszej sesji) ------
# Sama suma nie mowi, CO skrocic, gdy zrobi sie drogo - a uzytkownik poprosil
# wprost, zeby przy kazdej pozycji stalo, gdzie ona siedzi i do czego jest
# doklejana. Stad trzy kubelki, sciezka przy kazdym i pasek, ktory widac bez
# czytania liczb. Blok idzie prosto do kontekstu modelu (straznik-zasad.ps1
# czyta go z pliku podrecznego), wiec kazda zbedna linia placi sie przy kazdej
# pierwszej sesji dnia - dlatego jest tak krotki, jak sie da.

function Pasek($ile, $max) {
  if (($null -eq $ile) -or ($ile -le 0) -or ($null -eq $max) -or ($max -le 0)) { return "|" }
  $dlugosc = [int][math]::Round(20.0 * $ile / $max)
  if ($dlugosc -lt 1) { return "|" }     # pozycja mala, ale istniejaca - ma byc widoczna
  return ("#" * $dlugosc)
}

# Sciezka tak, jak ja widzi czlowiek: katalog domowy jako "~", katalog projektu
# zdjety w calosci. Pelne sciezki sa w pelnym raporcie i tam ich miejsce.
function Sciezka-Ludzka($sciezka) {
  if (-not $sciezka) { return "" }
  $s = "$sciezka"
  if ($Projekt -and $s.StartsWith($Projekt, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $s.Substring($Projekt.Length).TrimStart("\", "/")
  }
  if ($s.StartsWith($KatalogDomowy, [System.StringComparison]::OrdinalIgnoreCase)) {
    return "~" + $s.Substring($KatalogDomowy.Length)
  }
  return $s
}

function Wiersz-Rozbicia($etykieta, $pasek, $liczba, $ogon) {
  return ("  {0,-20} {1,-20} {2,8}{3}" -f $etykieta, $pasek, $liczba, $ogon)
}

# Kubelek, ktorego nie da sie policzyc, MA SIE WYPISAC. Naglowek niesie
# informacje "taka pozycja w tym rachunku istnieje", a kubelek, ktory znika,
# czyta sie jak zero - uzytkownik nie ma wtedy szans zauwazyc, ze czegos brakuje.
# To ten sam wzorzec, co "? nie zmierzone: ..." przy sufitach.
function Kubelek-Niezmierzony($naglowek, $stan, $powod) {
  return @("$naglowek - $stan", ("  {0,-20} {1}" -f "", $powod))
}

# Kubelek: naglowek z suma, pozycje malejaco, a sciezki zbiorczo, gdy wszystkie
# pozycje siedza w jednym pliku (tak jest z CLAUDE.md - trzy warstwy, jeden plik).
function Kubelek-Rozbicia($naglowek, $pozycje, $razem, $powodBraku, $dopisek = "") {
  if (@($pozycje).Count -eq 0) {
    if (-not $powodBraku) { $powodBraku = "nie umiem powiedziec czego brakuje - to blad w tym skrypcie" }
    return Kubelek-Niezmierzony $naglowek "nie zmierzone" $powodBraku
  }
  $wynik = @()
  $wynik += "$naglowek - ~$(Liczba $razem) tokenow$dopisek"
  $posortowane = @($pozycje | Sort-Object -Property Tokeny -Descending)
  $max = $posortowane[0].Tokeny
  $sciezki = @($pozycje | ForEach-Object { Sciezka-Ludzka $_.Skad } | Select-Object -Unique)
  $jednaSciezka = ($sciezki.Count -eq 1)
  foreach ($p in $posortowane) {
    $udzial = ""
    if (@($pozycje).Count -gt 1) { $udzial = "{0,5}%" -f $p.Procent }
    $wynik += Wiersz-Rozbicia $p.Krotka (Pasek $p.Tokeny $max) (Liczba $p.Tokeny) ($udzial + $p.Uwaga)
    if (-not $jednaSciezka) { $wynik += ("  {0,-20} {1}" -f "", (Sciezka-Ludzka $p.Skad)) }
  }
  if ($jednaSciezka) { $wynik += ("  {0,-20} wszystko w {1}" -f "", $sciezki[0]) }
  return $wynik
}

# Tryb-Rozbicie - wypisuje rozbicie; exit 0 daje koszt-pamieci.ps1.
# Wola go koszt-pamieci.ps1 KROPKA (". Tryb-Rozbicie"), wiec biegnie w zasiegu skryptu
# glownego: zmienne i funkcje, ktore tu powstaja, widzi dalszy przebieg - tak samo,
# jak gdy ten kod stal w koszt-pamieci.ps1 wprost.
function Tryb-Rozbicie {
  # Kazde narzedzie ma wlasne dwa kubelki pod wlasnym naglowkiem - domyslne
  # pierwsze. Drugie stoi tylko wtedy, gdy jest na maszynie: rozbicie idzie
  # do kontekstu modelu, a linia "Codeksa tu nie ma" w oknie Claude Code nic
  # nikomu nie mowi. Wyjatek: jawne -Narzedzie Codex bez Codeksa - wtedy
  # rachunek Codeksa MOWI "brak Codeksa" zamiast pokazac zero.
  function Kubelki-Claude {
    # Powody, dla ktorych kubelek moze byc pusty - kazdy nazwany po imieniu, bo
    # w tym rachunku brak liczby jest osobna wiadomoscia, a nie brakiem wiadomosci.
    $brakWiadomosc = $null
    if (@($kubWiadomosc).Count -eq 0) {
      if ($przypCcUwaga) {
        $brakWiadomosc = $przypCcUwaga
      } else {
        $brakWiadomosc = "nie ma ladunku hooka Claude Code (.claude\orchestrator-reminder.json)"
      }
    }
    $brakSesja = $null
    if (@($kubSesja).Count -eq 0) { $brakSesja = Powod-Pustej-Sesji (Sciezka-Ludzka $plikClaude) }
    # Procent calego otwarcia sesji przy kazdej sumie - "~7 000 tokenow" samo
    # nic nie mowi; bez zmierzonej calosci stoi zdanie, dlaczego procentu nie ma.
    $dopW = ""; $dopS = ""
    if ($null -ne $rCc.Calosc) {
      $dopW = " = $(Procent-Tekst (100.0 * $tokWiadomosc / $rCc.Calosc)) otwarcia sesji"
      $dopS = " = $(Procent-Tekst (100.0 * $tokSesja / $rCc.Calosc)) otwarcia sesji (reszta to sam Claude Code)"
    }
    $b = @()
    $b += Kubelek-Rozbicia "Claude Code - przy KAZDEJ Twojej wiadomosci" $kubWiadomosc $tokWiadomosc $brakWiadomosc $dopW
    if ($przypCcUwaga -and (@($kubWiadomosc).Count -gt 0)) {
      $b += ("  {0,-20} {1}" -f "", "UWAGA: $przypCcUwaga")
    }
    $b += Kubelek-Rozbicia "Claude Code - RAZ, przy starcie sesji" $kubSesja $tokSesja $brakSesja $dopS
    if ($null -ne $rCc.Calosc) {
      $b += ("  {0,-20} {1}" -f "", "Razem MegaRuchacz: ~$(Liczba $rCc.Mr) z ~$(Liczba $rCc.Calosc) tokenow otwarcia sesji = $(Procent-Tekst $rCc.Udzial) (prog $AlarmUdzialuOtwarcia%; calosc z $($rCc.Sesji) ostatnich sesji).")
    } else {
      $b += ("  {0,-20} {1}" -f "", "Udzialu w calym otwarciu sesji nie porownuje, bo $($rCc.PowodCalosci).")
    }
    foreach ($nb in @($w.BlokiBezKonca)) {
      $b += ("  {0,-20} {1}" -f "", "UWAGA: blok '$nb' w $(Sciezka-Ludzka $plikClaude) nie ma znacznika konca - nie umiem go policzyc.")
    }
    # Przeterminowana wiedza jest gorsza niz jej brak - wyglada na aktualna.
    # Dlatego nie sama liczba w wierszu, tylko rzecz do zrobienia, wprost.
    if ($wpisyStare.Count -gt 0) {
      $b += ("  {0,-20} {1}" -f "", "Do zrobienia: $(Ile-Wpisow $wpisyStare.Count) starsze niz $DniWaznosci dni - przejrzyj albo odswiez date.")
    }
    return $b
  }
  function Kubelki-Codex {
    $b = @()
    if (-not $jestCodex) {
      $b += Kubelek-Niezmierzony "Codex (osobny rachunek)" "brak Codeksa" "$($rCx.Brak) - nie ma czego liczyc"
      return $b
    }
    $brakWiadomosc = $null
    if (@($kubWiadomoscCx).Count -eq 0) {
      $brakWiadomosc = "nie ma gotowego przypomnienia Codeksa - ani w projekcie, ani $(Sciezka-Ludzka $plikPrzypWzor)"
    }
    $b += Kubelek-Rozbicia "Codex - przy KAZDEJ wiadomosci (Claude Code tego nie dostaje)" $kubWiadomoscCx $tokWiadomoscCx $brakWiadomosc
    $b += Kubelek-Rozbicia "Codex - RAZ, przy starcie sesji (Claude Code tego nie czyta)" $kubSesjaCx $tokSesjaCx "nie ma czego liczyc"
    $b += ("  {0,-20} {1}" -f "", "Udzialu w calym otwarciu sesji nie porownuje, bo $($rCx.PowodCalosci).")
    # Wdrozenie dla Codeksa bez AGENTS.md w projekcie: pozycji nie ma, wiec trzeba
    # powiedziec DLACZEGO - inaczej czyta sie to jak "zasady nic nie kosztuja".
    if ($Projekt -and (Test-Path -LiteralPath (Join-Path $Projekt ".megaruchacz")) -and
        -not (Test-Path -LiteralPath (Join-Path $Projekt "AGENTS.md"))) {
      $b += ("  {0,-20} {1}" -f "", "AGENTS.md projektu: nie ma go - zasady kierownika ida do Codeksa wylacznie hookiem.")
    }
    return $b
  }

  $blok = @()
  $blok += "MegaRuchacz - pamiec i koszty"
  if ($narzDomyslne -eq "Codex") {
    $blok += Kubelki-Codex
    if ($jestClaude) { $blok += Kubelki-Claude }
  } else {
    $blok += Kubelki-Claude
    if ($jestCodex) { $blok += Kubelki-Codex }
  }

  # Trzeci kubelek to inne pieniadze: prawdziwe wolanie modelu, nie doklejony tekst.
  # Dlatego nie sumuje sie z niczym, a pasek skaluje sie do POPRZEDNIEGO przebiegu -
  # jedna pozycja nie ma udzialu procentowego, ale porownanie z wczoraj ma sens.
  # Naglowek stoi tu ZAWSZE, takze bez ani jednej liczby: zniknal 2026-09-17
  # i przez to rachunek milczal o calym trzecim rodzaju kosztu.
  $naglowekCyklu = "RAZ NA DOBE - uczenie sie na wczesniejszych rozmowach"
  if (-not $cykl) {
    $blok += Kubelek-Niezmierzony $naglowekCyklu "jeszcze nie liczone" `
      "cykl nie mial okazji sie odpalic (brak $(Sciezka-Ludzka $plikCyklKoszt))"
  } elseif ($null -eq $cykl.Tokeny) {
    $blok += Kubelek-Niezmierzony $naglowekCyklu "nie zmierzone" `
      "cykl chodzil, ale nie podal liczby tokenow ($(Sciezka-Ludzka $plikCyklKoszt))"
  } else {
    $blok += $naglowekCyklu
    $poprzedniCykl = $cykl.Poprzedni
    $maxCykl = [long]$cykl.Tokeny
    if ($poprzedniCykl -and ($null -ne $poprzedniCykl.Tokeny) -and ([long]$poprzedniCykl.Tokeny -gt $maxCykl)) {
      $maxCykl = [long]$poprzedniCykl.Tokeny
    }
    $kiedy = Kiedy-Cykl $cykl.Wiek
    if (-not $kiedy) { $kiedy = "ostatnio" }
    $zrodloCykl = $cykl.Zrodlo
    if (-not $zrodloCykl) { $zrodloCykl = "?" }
    $blok += Wiersz-Rozbicia $kiedy (Pasek $cykl.Tokeny $maxCykl) (Liczba $cykl.Tokeny) "  $zrodloCykl"
    $szczegoly = @()
    if ($null -ne $cykl.Wywolania) { $szczegoly += "$(Liczba $cykl.Wywolania) wywolan" }
    if ($null -ne $cykl.Fakty)     { $szczegoly += "$(Liczba $cykl.Fakty) faktow" }
    if ($szczegoly.Count -gt 0) { $blok += ("  {0,-20} {1}" -f "", ($szczegoly -join ", ")) }
    # Za jaki okres i czy to nadrabianie - bez tego drogi dzien nadrabiania
    # wyglada w rozbiciu jak nowa norma.
    $okresR = Zakres-Krotko $ocena.ZakresOd $ocena.ZakresDo
    $wiadR = ""
    if ($null -ne $ocena.Wiadomosci) { $wiadR = "$(Liczba $ocena.Wiadomosci) wiadomosci" }
    if ($okresR) { $wiadR = ("$wiadR z $okresR").Trim() }
    $rodzajR = ""
    switch ($ocena.Rodzaj) {
      "nadrabianie" { $rodzajR = "nadrabianie zaleglosci (jednorazowo)" }
      "mieszany"    { $rodzajR = "czesciowo nadrabianie zaleglosci" }
      "zwykly"      { $rodzajR = "zwykly dzien" }
      "nieznany"    { $rodzajR = "okres nieznany" }
    }
    $czesciR = @(@($rodzajR, $wiadR) | Where-Object { $_ })
    if ($czesciR.Count -gt 0) { $blok += ("  {0,-20} {1}" -f "", ($czesciR -join ": ")) }
    if ($poprzedniCykl -and ($null -ne $poprzedniCykl.Tokeny)) {
      $blok += Wiersz-Rozbicia "poprzednio" (Pasek $poprzedniCykl.Tokeny $maxCykl) (Liczba $poprzedniCykl.Tokeny) ""
    }
    $blok += "  Jedyna pozycja placona prawdziwym wolaniem modelu."
  }

  if (Test-Path -LiteralPath $katWiedzy) {
    $blok += "Pliki w $(Sciezka-Ludzka $katWiedzy) - nie wygasaja i kosztuja 0 tokenow, dopoki rozmowa ich nie dotyczy."
  } else {
    # bez tego linia mowila o plikach w katalogu, ktorego nie ma
    $blok += "Warstwy referencyjnej jeszcze nie ma (brak $(Sciezka-Ludzka $katWiedzy)) - 0 tokenow."
  }
  foreach ($l in $blok) { Write-Output $l }
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["tryb-rozbicie"] = $true
