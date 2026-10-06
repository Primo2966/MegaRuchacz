# narzedzia\koszt\kubelki.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz BUDOWA
# w jego naglowku). Drugi etap (Etap-Kubelki): rachunki narzedzi - kazde ma wlasne
# dwa kubelki, przy kazdej wiadomosci i raz przy starcie sesji: Claude Code
# ($kubWiadomosc, $kubSesja), Codex ($kubWiadomoscCx, $kubSesjaCx) i OpenCode
# ($kubWiadomoscOc - zawsze pusty, $kubSesjaOc) - oraz ktore
# narzedzie jest domyslne ($narzDomyslne). Skad wolane: koszt-pamieci.ps1 kropka
# (". Etap-Kubelki") po Etap-Pomiar; kubelki czytaja tryby -Start, -Warstwy
# i -Rozbicie, etap Etap-Ocena (alarmy.ps1) i pelny raport.

# Blok kierownika ma dwa warianty (od 0.21.0): Claude Code z
# szablony-global\claude\zasady-kierownika.md i opencode/Codex z
# szablony-opencode\zasady-kierownika.md. Rada "gdzie skracac" ma wskazac ten
# szablon, z ktorego blok NAPRAWDE pochodzi - poznajemy go po naglowku wariantu.
function Szablon-Kierownika($tekstBloku) {
  if ("$tekstBloku" -match '\(opencode / Codex CLI\)') { return "szablony-opencode\zasady-kierownika.md" }
  return "szablony-global\claude\zasady-kierownika.md"
}

# Pozycje MegaRuchacza w pliku instrukcji narzedzia innego niz Claude Code (AGENTS.md
# Codeksa, plik, ktory czyta OpenCode): bloki zasad (znaczniki MegaRuchacz:...:start/koniec)
# i sekcja "Co wiem" (stala i biezaca) - to samo, co u Claude Code w CLAUDE.md. Reszta
# pliku to Twoje wlasne instrukcje, a nie koszt MegaRuchacza - do rachunku nie wchodzi.
# $wX - wynik Zmierz-Warstwy na tym pliku, $gdzie - jak nazwac plik w nazwie pozycji.
function Pozycje-MegaRuchacza($wX, $plikX, $gdzie, $uwagaBiezacej) {
  $poz = @()
  if (-not $wX -or -not $wX.Jest) { return $poz }
  if ($wX.Blok.Znaki -gt 0) {
    $poz += Pozycja "blok zasad MegaRuchacza w $gdzie (stary, wspolny)" $wX.Blok.Znaki $plikX `
      "ten blok nalezy do narzedzia - straznik zamieni go na bloki lore i wiedza przy najblizszym przebiegu" `
      "zasady globalne"
  }
  if ($wX.Stala.Znaki -gt 0) {
    $poz += Pozycja "warstwa STALA (Co wiem) w $gdzie" $wX.Stala.Znaki $plikX `
      "przenies najdluzsze zestawienie do pliku w $katWiedzy i zostaw tu jedna linie odsylacza - warstwa referencyjna nie kosztuje nic" `
      "warstwa stala" "  nie wygasa"
  }
  if ($wX.Biezaca.Znaki -gt 0) {
    $poz += Pozycja "warstwa BIEZACA w $gdzie" $wX.Biezaca.Znaki $plikX `
      "skasuj wpisy starsze niz $DniWaznosci dni albo przenies te trwale do warstwy stalej" `
      "warstwa biezaca" $uwagaBiezacej
  }
  foreach ($b in @($wX.Bloki)) {
    if ($b.Znaki -le 0) { continue }
    if ($b.Nazwa -eq "kierownik") {
      $poz += Pozycja "zasady kierownika w $gdzie (blok kierownik)" $b.Znaki $plikX `
        "ten blok wgrywa narzedzia\instaluj-globalnie.ps1 - skracaj go w $(Szablon-Kierownika $b.Tekst) i wgraj ponownie, nie recznie" `
        "zasady kierownika"
    } elseif ($b.Nazwa -eq "lore") {
      $poz += Pozycja "zasady Lore w $gdzie (blok lore)" $b.Znaki $plikX `
        "ten blok wpisuje straznik (narzedzia\wpisz-zasady.ps1) z zasady-lore.md - skracaj go w zrodle, nie recznie" `
        "zasady Lore"
    } elseif ($b.Nazwa -eq "wiedza") {
      $poz += Pozycja "zasady wiedzy w $gdzie (blok wiedza)" $b.Znaki $plikX `
        "ten blok wpisuje straznik (narzedzia\wpisz-zasady.ps1) z zasady-wiedza.md - skracaj go w zrodle, nie recznie" `
        "zasady wiedzy"
    } else {
      $poz += Pozycja "blok '$($b.Nazwa)' w $gdzie" $b.Znaki $plikX `
        "ten blok nalezy do narzedzia - skracaj go w zrodle i wgraj ponownie, nie recznie" `
        (Skroc "blok $($b.Nazwa)" 20)
    }
  }
  return $poz
}

# Etap-Kubelki - dwa rachunki kazdego narzedzia i narzedzie domyslne.
# Wola go koszt-pamieci.ps1 KROPKA (". Etap-Kubelki"), wiec biegnie w zasiegu skryptu
# glownego: zmienne i funkcje, ktore tu powstaja, widzi dalszy przebieg - tak samo,
# jak gdy ten kod stal w koszt-pamieci.ps1 wprost.
function Etap-Kubelki {
  # --- dwa rachunki: za wiadomosc i za start sesji ------------------------------
  # To sa rozne pieniadze i dlatego nie sumuja sie w jedna liczbe. Pierwszy placi
  # sie przy kazdym zdaniu uzytkownika, drugi raz, przy otwarciu sesji.
  # Do rachunku wchodzi tylko to, co na TEJ maszynie naprawde leci - szablon,
  # ktorego nikt nie wysyla, jest wymieniony w raporcie, ale nie jest doliczany.

  # RACHUNKI NARZEDZI. Kazde narzedzie ma WLASNE dwa kubelki - z tego, co trafia
  # do JEGO modelu - i wlasne sprawdzenie progow. Oba narzedzia naraz to
  # codziennosc tej maszyny, ale kazde placi tylko swoje: Claude Code nie czyta
  # ~\.codex\AGENTS.md, a Codex nie czyta ~\.claude\CLAUDE.md. Do 2026-09-28 obie
  # strony szly do JEDNEJ sumy: start sesji wychodzil ~11 900 tokenow zamiast
  # ~7 000 po stronie Claude Code i swiecil falszywy alarm przy progu 7 500 (to
  # samo przy wiadomosci: 115 Claude + 198 Codex = 313 przy progu 300).
  # $kubWiadomosc / $kubSesja - Claude Code (te nazwy czytaja tez -Warstwy i -Start),
  # $kubWiadomoscCx / $kubSesjaCx - Codex.
  $kubWiadomosc = @()
  if ($przypCcZnaki -ne $null) {
    $kubWiadomosc += Pozycja "przypomnienie zasad (Claude Code)" $przypCcZnaki $przypCcSkad `
      "skroc tresc 'additionalContext' w tym pliku - kazde zdanie stad placi sie przy kazdej wiadomosci" `
      "przypomnienie Claude"
  }
  $kubWiadomoscCx = @()
  if (($przypZnaki -ne $null) -and $jestCodex) {
    $kubWiadomoscCx += Pozycja "przypomnienie zasad (Codex)" $przypZnaki $przypSkad `
      "skroc tresc 'additionalContext' w tym pliku - kazde zdanie stad placi sie przy kazdej wiadomosci" `
      "przypomnienie Codex"
  }
  $tokWiadomosc   = Policz-Udzialy $kubWiadomosc
  $tokWiadomoscCx = Policz-Udzialy $kubWiadomoscCx

  # Ktora warstwa pamieci jest tymczasowa, a ktora rosnie na zawsze - to widac
  # tylko wtedy, gdy stoi napisane przy pozycji. Warstwa biezaca ma daty waznosci
  # ($DniWaznosci dni, sekcja "Wygasanie" w zasady-globalne.md - sprawdzone
  # 2026-09-17), stala nie wygasa wcale, a referencyjna nie kosztuje, dopoki
  # rozmowa jej nie dotyczy (osobna linia na koncu rozbicia).
  $wpisyBiezace = @($w.Wpisy)
  $wpisyStare   = @($wpisyBiezace | Where-Object { $_.Stary })
  $uwagaBiezaca = "  tymczasowa, $($wpisyBiezace.Count) wpisow"
  if ($wpisyStare.Count -gt 0) { $uwagaBiezaca += ", $($wpisyStare.Count) po terminie" }

  $kubSesja = @()
  if ($w.Blok.Znaki -gt 0) {
    # stary wspolny blok (do P59a) - do najblizszego przebiegu straznika, ktory zamieni go na lore + wiedza
    $kubSesja += Pozycja "blok zasad MegaRuchacza w CLAUDE.md (stary, wspolny)" $w.Blok.Znaki $plikClaude `
      "ten blok nalezy do narzedzia - straznik zamieni go na bloki lore i wiedza przy najblizszym otwarciu okna" `
      "zasady globalne"
  }
  if ($w.Stala.Znaki -gt 0) {
    $kubSesja += Pozycja "warstwa STALA (Co wiem)" $w.Stala.Znaki $plikClaude `
      "przenies najdluzsze zestawienie do pliku w $katWiedzy i zostaw tu jedna linie odsylacza - warstwa referencyjna nie kosztuje nic" `
      "warstwa stala" "  nie wygasa"
  }
  if ($w.Biezaca.Znaki -gt 0) {
    $kubSesja += Pozycja "warstwa BIEZACA" $w.Biezaca.Znaki $plikClaude `
      "skasuj wpisy starsze niz $DniWaznosci dni albo przenies te trwale do warstwy stalej" `
      "warstwa biezaca" $uwagaBiezaca
  }
  # Bloki nazwane w CLAUDE.md (zasady kierownika z instaluj-globalnie.ps1, ~12 tys.
  # znakow; od P59a takze zasady pamieci: bloki lore i wiedza, ktore zastapily blok
  # glowny). Claude Code wczytuje CALY plik, wiec leca do modelu przy
  # kazdym starcie sesji - do 2026-09-25 rachunek ich nie liczyl, bo mierzyl
  # tylko blok glowny i sekcje "Co wiem". Pozycja na blok, klucz = nazwa bloku
  # (z tej tablicy bierze liczby tryb -Warstwy, zeby nie liczyc drugi raz).
  $pozycjeBlokow = @{}
  foreach ($b in @($w.Bloki)) {
    if ($b.Znaki -le 0) { continue }
    if ($b.Nazwa -eq "kierownik") {
      $poz = Pozycja "zasady kierownika w CLAUDE.md (blok kierownik)" $b.Znaki $plikClaude `
        "ten blok wgrywa narzedzia\instaluj-globalnie.ps1 - skracaj go w $(Szablon-Kierownika $b.Tekst) i wgraj ponownie, nie recznie" `
        "zasady kierownika"
    } elseif ($b.Nazwa -eq "lore") {
      $poz = Pozycja "zasady Lore w CLAUDE.md (blok lore)" $b.Znaki $plikClaude `
        "ten blok wpisuje straznik (narzedzia\wpisz-zasady.ps1) z zasady-lore.md - skracaj go w zrodle, nie recznie" `
        "zasady Lore"
    } elseif ($b.Nazwa -eq "wiedza") {
      $poz = Pozycja "zasady wiedzy w CLAUDE.md (blok wiedza)" $b.Znaki $plikClaude `
        "ten blok wpisuje straznik (narzedzia\wpisz-zasady.ps1) z zasady-wiedza.md - skracaj go w zrodle, nie recznie" `
        "zasady wiedzy"
    } else {
      $poz = Pozycja "blok '$($b.Nazwa)' w CLAUDE.md" $b.Znaki $plikClaude `
        "ten blok nalezy do narzedzia - skracaj go w zrodle i wgraj ponownie, nie recznie" `
        (Skroc "blok $($b.Nazwa)" 20)
    }
    $kubSesja += $poz
    $pozycjeBlokow[$b.Nazwa] = $poz
  }

  # CLAUDE.md projektu - Claude Code wczytuje go sam na starcie kazdej sesji w tym
  # projekcie, obok globalnego. Do 0.21.0 rachunek go nie znal (raporty P4, P5),
  # a w C:\dev\claude-worker bylo to ~15 tys. znakow. Liczymy go TYLKO przy jawnym
  # -Projekt: bez niego rachunek jest "maszynowy" (tak liczy linie straznik na
  # starcie sesji) i nie wie, w ktorym projekcie sesja sie otworzy.
  if ($Projekt -and $jestClaude) {
    $plikClaudeProjektu = Join-Path $Projekt "CLAUDE.md"
    $toSamoCoGlobalny = ((Klucz-Sciezki $plikClaudeProjektu) -eq (Klucz-Sciezki $plikClaude))
    if (-not $toSamoCoGlobalny) {
      $claudeProjektu = Czytaj-Cicho $plikClaudeProjektu
      if ($claudeProjektu) {
        $kubSesja += Pozycja "CLAUDE.md projektu (Claude Code czyta go sam)" $claudeProjektu.Length $plikClaudeProjektu `
          "to plik projektu - trzymaj w nim tylko reguly tego repo; zasady kierownika sa w bloku globalnym" `
          "CLAUDE.md projektu"
      }
    }
  }

  # Codex czyta ~\.codex\AGENTS.md SAM, bez zadnego hooka - to jego odpowiednik CLAUDE.md.
  # Do 2026-09-17 nie bylo go w ZADNYM kubelku, do 2026-09-28 wpadal do kubelka Claude
  # Code, ktory go nie czyta, a do 06.10.2026 rachunek Codeksa liczyl CALY plik - razem
  # z Twoimi wlasnymi instrukcjami, czyli zawyzal koszt MegaRuchacza i liczyl inaczej niz
  # Claude Code i OpenCode. Teraz tak samo jak tam: bloki MegaRuchacza i "Co wiem"
  # (Pozycje-MegaRuchacza); reszta pliku to Twoje wlasne instrukcje ($wlasneCxZnaki -
  # pokazuje je pelny raport). Caly plik dalej widac jako warstwe "codex-globalny" w
  # -Warstwy (tryb-warstwy.ps1 bierze jej rozmiar z samego pliku, nie z rachunku).
  $kubSesjaCx = @()
  $wCx = $null; $wpisyStareCx = @(); $wlasneCxZnaki = $null
  if ($jestCodex) {
    $nCx = Narzedzie-Po-Kluczu "codex"
    if ($nCx -and $nCx.Warstwy -and ((Klucz-Sciezki $nCx.Instrukcje) -eq (Klucz-Sciezki $plikAgents))) { $wCx = $nCx.Warstwy }
    else { $wCx = Zmierz-Warstwy $plikAgents }
    $wpisyCx = @($wCx.Wpisy)
    $wpisyStareCx = @($wpisyCx | Where-Object { $_.Stary })
    $uwagaBiezacaCx = "  tymczasowa, $($wpisyCx.Count) wpisow"
    if ($wpisyStareCx.Count -gt 0) { $uwagaBiezacaCx += ", $($wpisyStareCx.Count) po terminie" }
    $kubSesjaCx += @(Pozycje-MegaRuchacza $wCx $plikAgents "AGENTS.md Codeksa" $uwagaBiezacaCx)
    if ($wCx.Jest -and ($null -ne $agentsTresc)) {
      $mrCx = 0
      foreach ($p in $kubSesjaCx) { $mrCx += [long]$p.Znaki }
      $wlasneCxZnaki = [math]::Max(0, [long]$agentsTresc.Length - $mrCx)
    }
    if ($Projekt) {
      $plikAgentsProjektu = Join-Path $Projekt "AGENTS.md"
      $agentsProjektu = Czytaj-Cicho $plikAgentsProjektu
      if ($agentsProjektu) {
        $kubSesjaCx += Pozycja "AGENTS.md projektu (Codex czyta go sam)" $agentsProjektu.Length $plikAgentsProjektu `
          "zasady kierownika skracaj w szablony-codex\zasady-kierownika.md i wgraj przez wdroz.ps1" `
          "AGENTS.md projektu"
      }
    }
  }
  # Tak samo jak przy przypomnieniu: gdy stoja oba wdrozenia, placi sie oba
  # ladunki - kazdy w swoim oknie, wiec kazdy w rachunku swojego narzedzia.
  if ($zasadyCcTresc) {
    $kubSesja += Pozycja "zasady kierownika z hooka (Claude Code)" $zasadyCcTresc.Length $zasadyCcSkad `
      "to zasady projektu wstrzykiwane hookiem - skracaj je w szablony-global\claude\zasady-kierownika.md i wgraj przez wdroz.ps1" `
      "zasady z hooka (CC)"
  }
  if ($jestCodex -and $zasadyWdrozone -and $zasadyTresc) {
    $kubSesjaCx += Pozycja "zasady kierownika z hooka (Codex)" $zasadyTresc.Length $zasadySkad `
      "to zasady projektu wstrzykiwane hookiem - skracaj je w szablony-codex\zasady-kierownika.md i wgraj przez wdroz.ps1" `
      "zasady z hooka (Cx)"
  }
  $tokSesja   = Policz-Udzialy $kubSesja
  $tokSesjaCx = Policz-Udzialy $kubSesjaCx

  # RACHUNEK OPENCODE (od 06.10.2026). OpenCode czyta sam na starcie kazdej rozmowy swoj
  # plik instrukcji ($plikOc: ~\.config\opencode\AGENTS.md, a bez niego ~\.claude\CLAUDE.md -
  # Etap-Pomiar). Liczymy w nim TO SAMO, co u Claude Code w CLAUDE.md: bloki MegaRuchacza
  # i sekcje "Co wiem" (stala i biezaca) - reszta pliku to Twoje wlasne instrukcje. Do
  # 06.10.2026 rachunku OpenCode nie bylo wcale i okno na komputerze z samym OpenCode
  # mowilo o Claude Code. Przy kazdej wiadomosci: nic - OpenCode nie ma hooka wiadomosci,
  # a wtyczka mr-log.js do wiadomosci niczego nie dokleja (pusty kubelek to tu prawda,
  # nie brak pomiaru - Rachunek-Narzedzia mowi to wprost).
  $kubWiadomoscOc = @()
  $kubSesjaOc = @()
  $wpisyStareOc = @()
  if ($jestOpenCode -and $wOc -and $wOc.Jest) {
    $gdzieOc = "AGENTS.md OpenCode"
    if ($ocZastepczy) { $gdzieOc = "CLAUDE.md, ktory czyta OpenCode" }
    $wpisyOc = @($wOc.Wpisy)
    $wpisyStareOc = @($wpisyOc | Where-Object { $_.Stary })
    $uwagaBiezacaOc = "  tymczasowa, $($wpisyOc.Count) wpisow"
    if ($wpisyStareOc.Count -gt 0) { $uwagaBiezacaOc += ", $($wpisyStareOc.Count) po terminie" }
    $kubSesjaOc += @(Pozycje-MegaRuchacza $wOc $plikOc $gdzieOc $uwagaBiezacaOc)
  }
  # AGENTS.md projektu - OpenCode czyta go sam, tak jak Codex (a bez niego CLAUDE.md
  # projektu). Liczymy caly plik, tak samo jak w rachunku Codeksa - tylko przy -Projekt.
  if ($jestOpenCode -and $Projekt) {
    $plikOcProjektu = Join-Path $Projekt "AGENTS.md"
    $ocProjektu = Czytaj-Cicho $plikOcProjektu
    $nazwaOcProjektu = "AGENTS.md projektu (OpenCode czyta go sam)"
    if (-not $ocProjektu) {
      $plikOcProjektu = Join-Path $Projekt "CLAUDE.md"
      $ocProjektu = Czytaj-Cicho $plikOcProjektu
      $nazwaOcProjektu = "CLAUDE.md projektu (OpenCode czyta go, bo nie ma AGENTS.md)"
    }
    if ($ocProjektu) {
      $kubSesjaOc += Pozycja $nazwaOcProjektu $ocProjektu.Length $plikOcProjektu `
        "to plik projektu - trzymaj w nim tylko reguly tego repo; zasady kierownika skracaj w szablony-opencode\zasady-kierownika.md" `
        "plik projektu (OC)"
    }
  }
  if ($zasadyOcTresc) {
    $kubSesjaOc += Pozycja "zasady kierownika z wtyczki (OpenCode, mr-log.js)" $zasadyOcTresc.Length $zasadyOcSkad `
      "wtyczka dokleja ten plik, bo zasad nie ma ani w AGENTS.md projektu, ani w globalnym - skracaj je w szablony-opencode\zasady-kierownika.md" `
      "zasady z wtyczki (OC)"
  }
  $tokWiadomoscOc = Policz-Udzialy $kubWiadomoscOc
  $tokSesjaOc     = Policz-Udzialy $kubSesjaOc

  # Czyj rachunek jest domyslny: jawne -Narzedzie, a bez niego Claude Code, gdy
  # jest na maszynie (jego linie pokazuje hook Claude Code i nadzorca). Maszyna
  # z samym Codeksem dostaje domyslnie rachunek Codeksa - inaczej jego ladunek
  # hooka pokazywalby liczby plikow, ktorych Codex nie czyta.
  # Przed tym - narzedzie, ktorego naprawde UZYWASZ (rozmowa w ostatnich $DniUzywania
  # dniach, pomiar.ps1): na komputerze z samym Codeksem ~\.claude.json potrafi lezec
  # po jednym uruchomieniu Claude Code i rachunek mowil wtedy o narzedziu, ktorego nikt
  # tu nie uzywa. OpenCode (od 06.10.2026) - po Codeksie: na komputerze z samym OpenCode
  # rachunek, linia i werdykt okna mowia o OpenCode, a nie o Claude Code.
  $narzDomyslne = $Narzedzie
  if (-not $narzDomyslne) {
    $uzCc = Narzedzie-Po-Kluczu "claude"; $uzCx = Narzedzie-Po-Kluczu "codex"
    if ($uzCc -and $uzCc.Uzywane) { $narzDomyslne = "Claude" }
    elseif ($uzCx -and $uzCx.Uzywane -and $jestCodex) { $narzDomyslne = "Codex" }
    elseif ($nOc -and $nOc.Uzywane -and $jestOpenCode) { $narzDomyslne = "OpenCode" }
    elseif ($jestClaude) { $narzDomyslne = "Claude" }
    elseif ($jestCodex) { $narzDomyslne = "Codex" }
    elseif ($jestOpenCode) { $narzDomyslne = "OpenCode" }
    else { $narzDomyslne = "Claude" }
  }
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["kubelki"] = $true
