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
