# narzedzia\koszt\tryb-dane.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz BUDOWA
# w jego naglowku). Tryb -Dane (Tryb-Dane): linie "klucz: wartosc" dla okna nadzorcy
# (zasobnik\stan-nadzorcy.ps1, Linia-Rachunku) - linia rachunku, alarmy z waga
# i okresem, ocena kosztu nauki i dni do wykresu. Skad wolane: koszt-pamieci.ps1
# kropka po Etap-Ocena; kod $kodDanych ustawia sie tutaj, exit daje tamten plik.

# --- wypisanie: dane dla nadzorcy (-Dane) --------------------------------------
# Nadzorca w zasobniku NICZEGO nie liczy drugi raz - dostaje stad linie, alarmy
# z waga i okresem, ocene kosztu nauki i dni do wykresu. Format "klucz: wartosc",
# ten sam co pozostale pliki stanu; kazda wartosc w jednej linii.

function Wartosc-Linii($v) {
  if ($null -eq $v) { return "" }
  if ($v -is [datetime]) { return $v.ToString('yyyy-MM-dd') }
  return ((("" + $v) -replace '[\r\n\t]+', ' ').Trim())
}

function Para($klucz, $wartosc) {
  Write-Output ("{0}: {1}" -f $klucz, (Wartosc-Linii $wartosc))
}

# Tryb-Dane - wypisuje dane dla nadzorcy i ustawia $kodDanych.
# Wola go koszt-pamieci.ps1 KROPKA (". Tryb-Dane"), wiec biegnie w zasiegu skryptu
# glownego: zmienne i funkcje, ktore tu powstaja, widzi dalszy przebieg - tak samo,
# jak gdy ten kod stal w koszt-pamieci.ps1 wprost.
function Tryb-Dane {
  # Linia i jej alarmy mowia o domyslnym narzedziu. Alarmy DRUGIEGO narzedzia
  # (tematy z przedrostkiem, np. "codex-otwarcie", i jego ucinanie) tez ida na
  # liste - kazde ma wlasne progi i nie wolno ich przemilczec - ale z jego nazwa
  # w opisie i bez mieszania liczb. Kod 1 = cokolwiek czerwonego na liscie.
  $alarmyInnego = @()
  $informacjeInnego = @()
  if ($rInny.Jest) {
    $alarmyInnego = @($rInny.AlarmyUcinania) + @($rInny.Alarmy)
    $informacjeInnego = @($rInny.Informacje)
  }
  $kodDanych = $kodWyjscia
  if ($alarmyInnego.Count -gt 0) { $kodDanych = 1 }
  Para "linia" $liniaZwiezla
  Para "kod" $kodDanych
  Para "narzedzie" $rDom.Nazwa
  $liniaInnego = Linia-Narzedzia $rInny
  Para "inne.narzedzie" $rInny.Nazwa
  Para "inne.linia" $liniaInnego.Linia
  # Udzial MegaRuchacza w calym otwarciu sesji (domyslne narzedzie) - okno dopisuje
  # z tego procent obok kazdej liczby tokenow. Pusta calosc = nie zmierzono,
  # a udzial.powod mowi dlaczego (okno pokazuje to szaro, bez alarmu).
  # udzial.prog_tokeny - prog czesci MegaRuchacza w TOKENACH ($AlarmCzesciOtwarcia):
  # werdykt okna porownuje z nim udzial.mr, tak samo jak alarm "otwarcie". Do
  # 30.09.2026 byl tu udzial.prog w procentach calosci - nowa nazwa, zeby stare okno
  # nie wzielo tokenow za procent (bez klucza mowi "nie znam progu").
  Para "udzial.mr"        $rDom.Mr
  Para "udzial.start"     $rDom.TokS
  Para "udzial.wiadomosc" $rDom.TokW
  Para "udzial.calosc"    $rDom.Calosc
  Para "udzial.sesji"     $rDom.Sesji
  Para "udzial.prog_tokeny" $AlarmCzesciOtwarcia
  Para "udzial.powod"     $rDom.PowodCalosci

  # Narzedzia AI tej maszyny (lista $NARZEDZIA_AI, pomiar.ps1), kazde osobno: czy go
  # uzywasz (narz.N.uzywane - od tego zalezy, czy brak czegos jest usterka, czy "nie
  # dotyczy"), czy w jego pliku instrukcji stoi sekcja "## Co wiem", otwarcie okna
  # rozmowy (mediana tokenow) i zuzycie dzienne. Okno sklada z tego zdanie "Na tym
  # komputerze: ...", sprawy wymagajace uwagi i liczby Codeksa obok Claude Code.
  # narz.N.zuzycie_w_oknie = 1: zuzycie tego narzedzia liczy samo okno (Claude Code,
  # zasobnik\nadzorca\stan-zuzycie.ps1) - tu go nie ma i to nie jest brak.
  # Brak liczby to pusta wartosc z powodem obok, nigdy zero.
  $nrN = 0
  foreach ($n in @($narzedzia)) {
    $nrN++
    $pom = $null
    if ($pomiaryNarzedzi) { $pom = $pomiaryNarzedzi[$n.Klucz] }
    $mrN = $null
    if ($n.Narz -eq "Codex") { $mrN = $rCx.Mr } elseif ($n.Narz -eq "Claude") { $mrN = $rCc.Mr }
    Para "narz.$nrN.klucz"           $n.Klucz
    Para "narz.$nrN.nazwa"           $n.Nazwa
    Para "narz.$nrN.uzywane"         ([int][bool]$n.Uzywane)
    Para "narz.$nrN.ostatnio"        $(if ($n.Ostatnio) { $n.Ostatnio.ToString("yyyy-MM-dd HH:mm") } else { "" })
    Para "narz.$nrN.instrukcje"      $n.Instrukcje
    Para "narz.$nrN.instrukcje_jest" ([int][bool]$n.InstrukcjeJest)
    Para "narz.$nrN.cowiem"          ([int][bool]($n.Warstwy -and $n.Warstwy.MaSekcje))
    Para "narz.$nrN.mr"              $mrN
    if ($pom) {
      $ot = $pom.Otwarcie
      Para "narz.$nrN.otwarcie"       $(if ($ot -and ($null -ne $ot.Mediana)) { $ot.Mediana } else { "" })
      Para "narz.$nrN.otwarcie_sesji" $(if ($ot) { $ot.Liczba } else { "" })
      Para "narz.$nrN.otwarcie_powod" $pom.Powod
      Para "narz.$nrN.zuzycie_w_oknie" ([int][bool]$pom.ZuzycieWOknie)
      $zu = $pom.Zuzycie
      if ($zu) {
        Para "narz.$nrN.dzis"            $zu.Dzis
        Para "narz.$nrN.srednia"         $zu.Srednia
        Para "narz.$nrN.zuzycie_dni"     $zu.Dni
        Para "narz.$nrN.zuzycie_dni_z_rozmowami" $zu.DniZRozmowami
        Para "narz.$nrN.zuzycie_od"      $zu.Od
        Para "narz.$nrN.zuzycie_do"      $zu.Do
        Para "narz.$nrN.zuzycie_bufor"   $zu.Bufor
        Para "narz.$nrN.zuzycie_pliki"   $zu.Pliki
        Para "narz.$nrN.zuzycie_powod"   $zu.Powod
      } elseif (-not $pom.ZuzycieWOknie) {
        Para "narz.$nrN.zuzycie_powod"   $(if ($pom.Powod) { $pom.Powod } else { "zuzycia w tym trybie nie licze" })
      }
    }
  }
  Para "narzedzia" $nrN
  Para "narzedzia.uzywane" (Nazwy-Narzedzi @($narzedzia | Where-Object { $_.Uzywane }))
  # Gdzie stoi sekcja "## Co wiem" - w pliku instrukcji ktoregokolwiek narzedzia.
  # Pusta lista przy wlaczonym module Wiedza = pamiec o Tobie nie trafia do zadnego.
  Para "cowiem.gdzie"      (@($narzedzia | Where-Object { $_.Warstwy -and $_.Warstwy.MaSekcje } | ForEach-Object { $_.Instrukcje }) -join "; ")
  Para "cowiem.sprawdzone" (@($narzedzia | ForEach-Object { $_.Instrukcje }) -join "; ")
  Para "cowiem.wiedza_wylaczona" ([int][bool]$script:WiedzaWylaczona)
  $nr = 0
  foreach ($a in (@($rDom.Alarmy) + @($alarmyInnego) + @($alarmy) + @($informacje) + @($informacjeInnego))) {
    $nr++
    Para "alarm.$nr.temat"  $a.Temat
    Para "alarm.$nr.waga"   $a.Waga
    Para "alarm.$nr.liczba" $a.Liczba
    Para "alarm.$nr.prog"   $a.Prog
    Para "alarm.$nr.okres"  $a.Okres
    Para "alarm.$nr.krotko" $a.Krotko
    Para "alarm.$nr.pelny"  $a.Pelny
  }
  Para "alarmy" $nr

  Para "cykl.prog"            $AlarmCyklu
  Para "cykl.dni_zwyklego"    $DniMaterialuZwyklego
  Para "cykl.dni_wzrostu"     $DniWzrostuCyklu
  if ($cykl) {
    Para "cykl.data"          $cykl.Data
    Para "cykl.wiek"          $cykl.Wiek
    Para "cykl.tokeny"        $cykl.Tokeny
    Para "cykl.wywolania"     $cykl.Wywolania
    Para "cykl.zrodlo"        $cykl.Zrodlo
  }
  Para "cykl.rodzaj"          $ocena.Rodzaj
  Para "cykl.ocena_z"         $ocena.Zrodlo
  Para "cykl.wiadomosci"      $ocena.Wiadomosci
  Para "cykl.zakres_od"       $ocena.ZakresOd
  Para "cykl.zakres_do"       $ocena.ZakresDo
  Para "cykl.zwykle"          $ocena.Zwykle
  Para "cykl.nadrabianie"     $ocena.Nadrabianie
  Para "cykl.nieznane"        $ocena.Nieznane
  Para "cykl.typowy_dzien"    $ocena.TypowyDzien
  Para "cykl.typowych_dni"    $ocena.TypowychDni
  Para "cykl.wzrosty"         $ocena.Wzrosty
  Para "cykl.wzrost_od"       $ocena.WzrostOd
  Para "cykl.wzrost_od_tokeny" $ocena.WzrostOdTokeny
  Para "cykl.wzrost_do"       $ocena.WzrostDo
  Para "cykl.wzrost_do_tokeny" $ocena.WzrostDoTokeny
  Para "cykl.proc_wzrostu"    $ProcWzrostuCyklu
  Para "cykl.prog_informacji" $ProgInformacjiNauki

  Para "stat.zrodlo"          $statystyka.Zrodlo
  Para "stat.powod"           $statystyka.Powod
  Para "stat.pominiete"       $statystyka.Pominiete
  Para "stat.okno_dni"        $DniStatystyki
  Para "stat.suma7"           $statystyka.Suma7
  Para "stat.suma7_od"        $statystyka.Suma7Od
  Para "stat.suma30"          $statystyka.Suma30
  Para "stat.suma30_od"       $statystyka.Suma30Od
  Para "stat.sumy_z"          $statystyka.SumyZ
  Para "stat.podsumowanie_z"  $statystyka.PodsumowanieZ
  Para "stat.srednia"         $statystyka.Srednia
  Para "stat.srednia_dni"     $statystyka.SredniaDni
  Para "stat.plik"            $plikHistoria
  # dzien|razem|zwykle|nadrabianie|nieznane|przebiegi|wiadomosci - tylko dni z danymi
  $nrDnia = 0
  foreach ($d in @($statystyka.Dni)) {
    $nrDnia++
    Para "stat.dzien.$nrDnia" ("{0}|{1}|{2}|{3}|{4}|{5}|{6}" -f $d.Dzien.ToString('yyyy-MM-dd'), $d.Razem, $d.Zwykle,
                               $d.Nadrabianie, $d.Nieznane, $d.Przebiegi, $d.Wiadomosci)
  }
  Para "stat.dni" $nrDnia
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["tryb-dane"] = $true
