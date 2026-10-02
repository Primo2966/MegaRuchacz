# narzedzia\koszt\pomiar.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz BUDOWA
# w jego naglowku). Pierwszy etap rachunku (Etap-Pomiar): co NAPRAWDE leci do modelu
# na tej maszynie - warstwy CLAUDE.md ($w), ktore narzedzie tu jest ($jestClaude,
# $jestCodex), co czytaja hooki Claude Code, ladunki hookow obu narzedzi i lista
# sufitow ($sufity). Skad wolane: koszt-pamieci.ps1 kropka (". Etap-Pomiar") zaraz
# po sciezkach; zmienne stad czyta caly dalszy przebieg. Funkcje nad etapem uzywa
# tez Etap-Kubelki (Klucz-Sciezki), tryb -Warstwy (Czy-Hook-Czyta) i tryb -Rozbicie
# oraz pelny raport (Powod-Pustej-Sesji).

function Powod-Pustej-Sesji($sciezkaClaude) {
  # dlaczego rachunek za start sesji wyszedl pusty - zdanie do wypisania zamiast
  # zera, bo zero czyta sie jak "za darmo", a to znaczy "nie bylo czego policzyc".
  # Sciezka idzie parametrem, zeby to samo zdanie dalo sie pokazac i pelna
  # sciezka (raport), i skrocona (rozbicie).
  if (-not $w.Jest) {
    if ($w.Blad) { return "plik $sciezkaClaude jest, ale nie da sie go odczytac" }
    return "nie ma pliku $sciezkaClaude"
  }
  if (-not $w.MaSekcje) { return "w $sciezkaClaude nie ma ani bloku zasad, ani sekcji '## Co wiem'" }
  return "w $sciezkaClaude nie ma nic do policzenia i zaden hook nie wstrzykuje zasad"
}

# Ten sam plik czytamy raz na zdarzenie - jego usterka ma trafic do Uwag raz.
function Dodaj-Uwage($tekst) {
  if (@($script:UwagiWarstw) -notcontains $tekst) { $script:UwagiWarstw += $tekst }
}

function Polecenia-Hookow($plik, $zdarzenie) {
  $wynik = @()
  if (-not (Test-Path -LiteralPath $plik -PathType Leaf)) { return $wynik }
  $tekst = $null
  try { $tekst = Czytaj $plik }
  catch {
    Dodaj-Uwage "nie da sie odczytac $plik ($($_.Exception.Message)) - nie wiem, co czytaja zapisane tam hooki"
    return $wynik
  }
  $j = $null
  try { $j = $tekst | ConvertFrom-Json }
  catch {
    Dodaj-Uwage "$plik nie jest poprawnym JSON-em ($($_.Exception.Message)) - nie wiem, co czytaja zapisane tam hooki"
    return $wynik
  }
  if (-not $j -or -not $j.hooks) { return $wynik }
  foreach ($grupa in @($j.hooks.$zdarzenie)) {
    if (-not $grupa) { continue }
    foreach ($h in @($grupa.hooks)) {
      if (-not $h) { continue }
      $wynik += ("" + $h.command + " " + $h.commandWindows)
    }
  }
  return $wynik
}

function Klucz-Sciezki($sciezka) { return ("$sciezka" -replace '/', '\').ToLowerInvariant() }

# Czy ktorys hook naprawde wczytuje ten plik - po pelnej sciezce w poleceniu,
# z $CLAUDE_PROJECT_DIR podmienionym na katalog projektu.
function Czy-Hook-Czyta($polecenia, $sciezka, $katProj) {
  if (-not $sciezka) { return $false }
  $cel = Klucz-Sciezki $sciezka
  foreach ($pol in @($polecenia)) {
    $t = "$pol"
    if ($katProj) { $t = $t.Replace('$CLAUDE_PROJECT_DIR', $katProj) }
    if ((Klucz-Sciezki $t).Contains($cel)) { return $true }
  }
  return $false
}

# Etap-Pomiar - warstwy, narzedzia na maszynie, hooki, ladunki i sufity.
# Wola go koszt-pamieci.ps1 KROPKA (". Etap-Pomiar"), wiec biegnie w zasiegu skryptu
# glownego: zmienne i funkcje, ktore tu powstaja, widzi dalszy przebieg - tak samo,
# jak gdy ten kod stal w koszt-pamieci.ps1 wprost.
function Etap-Pomiar {
  $w = Zmierz-Warstwy $plikClaude

  # jednym zdaniem: dlaczego z CLAUDE.md nic nie policzylismy. Brak pliku i plik
  # nie do odczytania to dwa rozne powody i wszedzie nizej podajemy ten wlasciwy.
  $powodBrakuClaude = "nie ma pliku $plikClaude"
  if ($w.Blad) { $powodBrakuClaude = $w.Blad }

  # --- sufity: pomiary ---------------------------------------------------------

  $limitAgents  = Limit-Z-Pliku $plikStraznika '(?m)^\s*\$LIMIT_AGENTS\s*=\s*(\d+)'
  $limitZasad   = Limit-Hooka $plikHookow "zasady-sesja.json"
  $limitPrzyp   = Limit-Hooka $plikHookow "przypomnienie.json"
  $limitWejscia = Limit-Z-Pliku $plikFaktow  '(?m)^MAX_INPUT_CHARS\s*=\s*([\d_]+)'
  $limitKawalka = Limit-Z-Pliku $plikIndeksu '(?m)^CHUNK_SIZE\s*=\s*([\d_]+)'

  # AGENTS.md Codeksa - sufit jest w BAJTACH, bo tyle czyta Codex
  $agentsTresc = Czytaj-Cicho $plikAgents
  $agentsBajty = $null
  if ($agentsTresc -ne $null) {
    try { $agentsBajty = [long](Get-Item -LiteralPath $plikAgents).Length } catch { $agentsBajty = $null }
  }

  # KTORE narzedzie naprawde siedzi na tej maszynie. Od tego zalezy, co wchodzi do
  # rachunkow nizej: liczymy to, co NAPRAWDE leci do modelu tutaj, a nie to, co
  # poleci u kogos innego. Codeksa poznajemy po jego pliku instrukcji, Claude Code
  # po plikach, ktore prowadzi sam - katalog ~\.claude zaklada takze MegaRuchacz,
  # wiec sam katalog nie dowodzi niczego (to samo rozroznienie robi
  # narzedzia\straznik-zasad.ps1 w Cisza-Claude-Linia).
  $jestCodex  = ($agentsTresc -ne $null)
  $jestClaude = ((Test-Path -LiteralPath (Join-Path $katKlaudii "history.jsonl")) -or
                 (Test-Path -LiteralPath (Join-Path $KatalogDomowy ".claude.json")))

  # --- co naprawde czytaja hooki Claude Code -----------------------------------
  # Rachunek i tryb -Warstwy pytaja o to samo: ktory plik wczytuje hook. Do
  # 2026-09-25 wiedzial to tylko tryb -Warstwy, a rachunek zgadywal po sciezce -
  # i w trybie globalnym mierzyl kopie przypomnienia, ktorej zaden hook nie czyta.
  # Nieczytelny settings.json to nie cisza: idzie do Uwag (okno pokazuje je nad
  # lista, rachunek - przy pozycji, ktorej dotyczy).
  $script:UwagiWarstw = @()

  # Projekt, w ktorym ogladamy hooki. Bez -Projekt to katalog narzedzia -
  # tak samo wola ten skrypt nadzorca, ktory w zadnym projekcie nie siedzi.
  $katProjektu = $Projekt
  if (-not $katProjektu) { $katProjektu = $Zrodlo }
  $katProjektu = "$katProjektu".TrimEnd('\', '/')
  $trybGlobalny = Test-Path -LiteralPath (Join-Path $katKlaudii ".megaruchacz-global")

  $polStart = @()
  $polWiad  = @()
  foreach ($pu in @((Join-Path $katKlaudii "settings.json"), (Join-Path $katKlaudii "settings.local.json"),
                    (Join-Path $katProjektu ".claude\settings.json"), (Join-Path $katProjektu ".claude\settings.local.json"))) {
    $polStart += @(Polecenia-Hookow $pu "SessionStart")
    $polWiad  += @(Polecenia-Hookow $pu "UserPromptSubmit")
  }

  # Ktory ladunek przypomnienia NAPRAWDE leci: ten, ktory hook UserPromptSubmit
  # podaje narzedzia\przypomnienie.js. Pierwszy trafiony wygrywa (globalny
  # settings.json jest czytany pierwszy).
  $przypUzywany = $null
  foreach ($pol in $polWiad) {
    $m = [regex]::Match("$pol", 'przypomnienie\.js"?\s+(?:"(?<a>[^"]+)"|(?<a>\S+))')
    if ($m.Success) {
      $przypUzywany = ($m.Groups['a'].Value.Replace('$CLAUDE_PROJECT_DIR', $katProjektu) -replace '/', '\')
      break
    }
  }

  # Zasady wysylane Codeksowi na starcie sesji. Gdy podano projekt i lezy w nim
  # gotowy ladunek - mierzymy JEGO, bo to jest to, co naprawde leci. Bez projektu
  # mierzymy szablon zlozony tak samo jak sklada go straznik: to wariant pelny,
  # czyli ten, ktory dostaje projekt bez zasad w AGENTS.md.
  $zasadyTresc = $null
  $zasadySkad  = $null
  $zasadyWdrozone = $false
  if ($Projekt) {
    $p = Join-Path $Projekt ".megaruchacz\zasady-sesja.json"
    $t = Ladunek-Hooka $p
    if ($t) { $zasadyTresc = $t; $zasadySkad = $p; $zasadyWdrozone = $true }
  }
  if (-not $zasadyTresc) {
    $t = Czytaj-Cicho $plikZasadWzor
    if ($t) {
      $zasadyTresc = $PrzedrostekZasad + $t
      $zasadySkad  = "$plikZasadWzor (wariant pelny - tyle leci do projektu, ktory nie ma zasad w AGENTS.md)"
    }
  }
  $zasadyZnaki = $null
  if ($zasadyTresc) { $zasadyZnaki = $zasadyTresc.Length }

  # Przypomnienie doklejane w Codeksie do KAZDEJ wiadomosci uzytkownika
  $przypTresc = $null
  $przypSkad  = $null
  if ($Projekt) {
    $p = Join-Path $Projekt ".megaruchacz\przypomnienie.json"
    $t = Ladunek-Hooka $p
    if ($t) { $przypTresc = $t; $przypSkad = $p }
  }
  if (-not $przypTresc) {
    $t = Ladunek-Hooka $plikPrzypWzor
    if ($t) { $przypTresc = $t; $przypSkad = $plikPrzypWzor }
  }
  $przypZnaki = $null
  if ($przypTresc) { $przypZnaki = $przypTresc.Length }

  # To samo przypomnienie po stronie Claude Code - inny plik, ten sam ladunek
  # hooka UserPromptSubmit. Sufitu tu nie ma (Claude Code nie przycina wyjscia
  # hooka), wiec nie jest to sufit, tylko pozycja w rachunku za wiadomosc.
  $przypCcTresc = $null
  $przypCcSkad  = $null
  # Zdanie do wypisania przy rachunku, gdy liczba NIE pochodzi z pliku wskazanego
  # przez hook albo gdy tego pliku nie da sie zmierzyc - $null, gdy wszystko gra.
  $przypCcUwaga = $null
  # Tryb globalny (~\.claude\.megaruchacz-global): przypomnienie czyta hook
  # z globalnego settings.json, np. ~\.claude\mr\orchestrator-reminder.json - i TEN
  # plik mierzymy, a nie kopie w projekcie. Do 2026-09-25 rachunek mierzyl kopie;
  # liczby zgadzaly sie tylko dlatego, ze obie mialy akurat po 725 znakow.
  # Gdy hook wskazuje plik bez ladunku, do modelu nie leci nic - kopia zastepcza
  # podalaby wtedy liczbe, ktorej nikt nie wysyla, wiec jej nie bierzemy.
  $przypZHooka = ($trybGlobalny -and $przypUzywany)
  if ($przypZHooka) {
    $t = Ladunek-Hooka $przypUzywany
    if ($t) {
      $przypCcTresc = $t; $przypCcSkad = $przypUzywany
    } elseif (-not (Test-Path -LiteralPath $przypUzywany -PathType Leaf)) {
      $przypCcUwaga = "hook UserPromptSubmit czyta $przypUzywany, a tego pliku nie ma - do wiadomosci nie dokleja sie nic"
    } else {
      $przypCcUwaga = "hook UserPromptSubmit czyta $przypUzywany, ale nie ma w nim pola hookSpecificOutput.additionalContext - do wiadomosci nie dokleja sie nic"
    }
  }
  if ((-not $przypZHooka) -and $Projekt) {
    $p = Join-Path $Projekt ".claude\orchestrator-reminder.json"
    $t = Ladunek-Hooka $p
    if ($t) { $przypCcTresc = $t; $przypCcSkad = $p }
  }
  # Kopia z katalogu narzedzia ratuje przebieg bez -Projekt (tak chodzi rachunek
  # pokazywany przy starcie sesji): wdrozenia roznia sie wtedy tylko sciezka.
  # Ale TYLKO na maszynie, na ktorej Claude Code w ogole jest. Bez tego warunku
  # wdrozenie z samym Codeksem dostawalo w rachunku ladunek Claude'a wziety
  # z katalogu narzedzia - liczbe, ktorej nikt nikomu nie wysyla - a pozycja
  # Codeksa nie pokazywala sie nigdy (sprawdzone 2026-09-17).
  if ((-not $przypZHooka) -and (-not $przypCcTresc) -and $jestClaude) {
    $p = Join-Path $Zrodlo ".claude\orchestrator-reminder.json"
    $t = Ladunek-Hooka $p
    if ($t) { $przypCcTresc = $t; $przypCcSkad = $p }
  }
  # Tryb globalny bez hooka, ktory wskazuje przypomnienie (settings.json nieczytelny
  # albo hook zdjety) - liczba z kopii to zgadywanie i ma to byc napisane.
  if ($trybGlobalny -and (-not $przypUzywany) -and $przypCcTresc) {
    $przypCcUwaga = "w trybie globalnym zaden hook UserPromptSubmit w settings.json nie wskazuje przypomnienia - liczona kopia zastepcza $przypCcSkad, moze nie trafiac do modelu wcale"
    if (@($script:UwagiWarstw).Count -gt 0) { $przypCcUwaga += " (" + (@($script:UwagiWarstw) -join "; ") + ")" }
  }
  # Modul kierownik wylaczony w rejestrze instalacji (P59a, koszt-pamieci.ps1): przypomnienie.js nie
  # dokleja ladunku z pliku ani w Claude Code, ani w Codeksie - liczba z pliku bylaby kosztem, ktorego
  # nikt nie placi. Linia cyklu i "Z ARCHIWUM" sa doklejane dalej, ale tych nie liczylismy nigdy.
  if ($script:KierownikWylaczony) {
    $przypCcTresc = $null; $przypCcSkad = $null
    $przypCcUwaga = "modul kierownik wylaczony w rejestrze instalacji - narzedzia\przypomnienie.js nie dokleja ladunku z pliku"
    $przypTresc = $null; $przypSkad = $null; $przypZnaki = $null
  }
  $przypCcZnaki = $null
  if ($przypCcTresc) { $przypCcZnaki = $przypCcTresc.Length }

  # Zasady kierownika wstrzykiwane hookiem startowym po stronie Claude Code.
  # Szablonu tu NIE mierzymy: szablon sam z siebie nikomu nic nie wysyla, wiec
  # doliczony do rachunku podawalby koszt, ktorego nikt nie placi.
  $zasadyCcTresc = $null
  $zasadyCcSkad  = $null
  # W trybie globalnym zasady kierownika ida blokiem w ~\.claude\CLAUDE.md (liczony
  # nizej), a straznik zdejmuje hook "cat ...megaruchacz-sesja.json" jako duplikat.
  # Ladunek, ktorego zaden hook SessionStart nie czyta, doliczylby te same zasady
  # drugi raz - wiec wtedy go pomijamy i mowimy o tym w raporcie.
  $zasadyCcPominiete = $null
  if ($Projekt) {
    $p = Join-Path $Projekt ".claude\megaruchacz-sesja.json"
    $t = Ladunek-Hooka $p
    if ($t) {
      if ($trybGlobalny -and -not (Czy-Hook-Czyta $polStart $p $katProjektu)) { $zasadyCcPominiete = $p }
      else { $zasadyCcTresc = $t; $zasadyCcSkad = $p }
    }
  }

  $sufity = @()

  $sufity += Sufit ([ordered]@{
    Nazwa      = "pamiec stala w CLAUDE.md (sekcja 'Co wiem')"
    Krotka     = "pamiec stala"
    Narzedzie  = "Claude"
    Teraz      = $(if ($w.Jest) { $w.Stala.Znaki } else { $null })
    Limit      = $ProgStalej
    Jednostka  = "znakow"
    Czyj       = "NASZ - sami go sobie ustawilismy"
    SkadLimitu = "narzedzia\koszt-pamieci.ps1 (`$ProgStalej)"
    Plik       = $plikClaude
    Skutek     = "nic sie nie ucina: to prog ostrzegawczy, sygnal zeby przeniesc rzadziej potrzebna wiedze do plikow w wiedza\"
    Ucina      = $false
    Uwaga      = (Powod-Braku $(if ($w.Jest) { $w.Stala.Znaki } else { $null }) $ProgStalej $powodBrakuClaude "tego skryptu")
  })

  $sufity += Sufit ([ordered]@{
    Nazwa      = "instrukcje dla Codeksa (~\.codex\AGENTS.md)"
    Krotka     = "instrukcje dla Codeksa"
    Narzedzie  = "Codex"
    Teraz      = $agentsBajty
    Limit      = $limitAgents
    Jednostka  = "bajtow"
    Czyj       = "NARZUCONY przez Codeksa - tego nie podniesiemy, trzeba sie zmiescic"
    SkadLimitu = "narzedzia\straznik-zasad.ps1 (`$LIMIT_AGENTS)"
    Plik       = $plikAgents
    Skutek     = "UCINA PO CICHU: Codex czyta tylko poczatek pliku, koniec zasad nie dociera do niego wcale"
    Ucina      = $true
    Tresc      = $agentsTresc
    Uwaga      = (Powod-Braku $agentsBajty $limitAgents "nie ma pliku $plikAgents - Codeksa nie ma na tej maszynie, wiec ten sufit dzis nikogo nie dotyczy" "narzedzia\straznik-zasad.ps1")
  })

  $sufity += Sufit ([ordered]@{
    Nazwa      = "zasady kierownika wstrzykiwane Codeksowi przy starcie sesji"
    Krotka     = "zasady dla Codeksa"
    Narzedzie  = "Codex"
    Teraz      = $zasadyZnaki
    Limit      = $limitZasad
    Jednostka  = "znakow"
    Czyj       = "NASZ - liczba wpisana w $skadHookow, do podniesienia jedna linijka"
    SkadLimitu = "$skadHookow (additionalContextLimit hooka SessionStart)"
    Plik       = $zasadySkad
    Skutek     = "UCINA PO CICHU: Codex dostaje tylko poczatek zasad, konca nikt mu nie pokaze i nikt go nie ostrzeze"
    Ucina      = $true
    Tresc      = $zasadyTresc
    Uwaga      = (Powod-Braku $zasadyZnaki $limitZasad "nie ma czego mierzyc: brak $plikZasadWzor" $skadHookow)
  })

  $sufity += Sufit ([ordered]@{
    Nazwa      = "przypomnienie doklejane w Codeksie do kazdej wiadomosci"
    Krotka     = "przypomnienie dla Codeksa"
    Narzedzie  = "Codex"
    Teraz      = $przypZnaki
    Limit      = $limitPrzyp
    Jednostka  = "znakow"
    Czyj       = "NASZ - liczba wpisana w $skadHookow, do podniesienia jedna linijka"
    SkadLimitu = "$skadHookow (additionalContextLimit hooka UserPromptSubmit)"
    Plik       = $przypSkad
    Skutek     = "UCINA PO CICHU: koniec przypomnienia przepada przy kazdej wiadomosci"
    Ucina      = $true
    Tresc      = $przypTresc
    Uwaga      = (Powod-Braku $przypZnaki $limitPrzyp "nie ma czego mierzyc: brak $plikPrzypWzor" $skadHookow)
  })

  # Ladunki hookow Claude Code - mierzymy je tylko wtedy, gdy podano projekt, bo
  # poza nim nie ma czego mierzyc. Sufitu dla nich w settings.json DZIS NIE MA:
  # obowiazuje wtedy wartosc domyslna Claude Code, ktorej nie znamy - i raport ma
  # to powiedziec wprost, a nie przemilczec.
  if ($Projekt) {
    $plikUstawien = Join-Path $Projekt ".claude\settings.json"
    foreach ($paraCC in @(
        @{ nazwa = "zasady kierownika wstrzykiwane na starcie sesji Claude Code"
           krotka = "zasady dla Claude Code"; plik = ".claude\megaruchacz-sesja.json"
           zdarzenie = "SessionStart" },
        @{ nazwa = "przypomnienie doklejane w Claude Code do kazdej wiadomosci"
           krotka = "przypomnienie dla Claude Code"; plik = ".claude\orchestrator-reminder.json"
           zdarzenie = "UserPromptSubmit" })) {
      # Brak ladunku NIE kasuje tu calego wiersza: pominiety wiersz czyta sie jak
      # "tego sufitu nie ma", a jest wprost przeciwnie - jest, tylko nie wiemy,
      # ile pod nim siedzi. Idzie wiec jako pozycja bez pomiaru, z powodem.
      $plikCC = Join-Path $Projekt $paraCC.plik
      $trescCC = Ladunek-Hooka $plikCC
      $znakiCC = $null
      if ($trescCC) { $znakiCC = $trescCC.Length }
      $brakCC = "nie da sie odczytac ladunku z $plikCC"
      if (-not (Test-Path -LiteralPath $plikCC)) {
        $brakCC = "nie ma pliku $plikCC - tego hooka nie ma w tym projekcie (wgrywa go wdroz.ps1)"
      }
      $limitCC = Limit-Hooka $plikUstawien (Split-Path $paraCC.plik -Leaf)
      $sufity += Sufit ([ordered]@{
        Nazwa      = $paraCC.nazwa
        Krotka     = $paraCC.krotka
        Narzedzie  = "Claude"
        Teraz      = $znakiCC
        Limit      = $limitCC
        Jednostka  = "znakow"
        Czyj       = "NARZUCONY przez Claude Code, dopoki nie wpiszemy wlasnego additionalContextLimit do settings.json"
        SkadLimitu = "$plikUstawien (additionalContextLimit hooka $($paraCC.zdarzenie))"
        Plik       = $plikCC
        Skutek     = "UCINA PO CICHU: koniec ladunku przepada, gdy przekroczy sufit narzedzia"
        Ucina      = $true
        Tresc      = $trescCC
        Uwaga      = (Powod-Braku $znakiCC $limitCC $brakCC `
                      "$plikUstawien - nie ma tam additionalContextLimit, wiec sufitem jest wartosc domyslna Claude Code")
      })
    }
  }
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["pomiar"] = $true
