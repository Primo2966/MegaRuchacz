# narzedzia\koszt\kubelki.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz BUDOWA
# w jego naglowku). Drugi etap (Etap-Kubelki): rachunki narzedzi - kazde ma wlasne
# dwa kubelki, przy kazdej wiadomosci i raz przy starcie sesji: Claude Code
# ($kubWiadomosc, $kubSesja) i Codex ($kubWiadomoscCx, $kubSesjaCx) - oraz ktore
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
    $kubSesja += Pozycja "blok zasad MegaRuchacza w CLAUDE.md" $w.Blok.Znaki $plikClaude `
      "ten blok nalezy do narzedzia - skracaj go w zrodle i wgraj przez wdroz.ps1, nie recznie" `
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
  # Bloki nazwane w CLAUDE.md (dzis: zasady kierownika z instaluj-globalnie.ps1,
  # ~12 tys. znakow). Claude Code wczytuje CALY plik, wiec leca do modelu przy
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

  # Codex czyta AGENTS.md SAM, bez zadnego hooka - to jego odpowiednik CLAUDE.md
  # i najwiekszy staly koszt jego sesji. Do 2026-09-17 nie bylo go w ZADNYM
  # kubelku, a do 2026-09-28 wpadal do kubelka Claude Code, ktory go nie czyta.
  # Teraz stoi w rachunku Codeksa i tylko tam.
  $kubSesjaCx = @()
  if ($jestCodex) {
    $kubSesjaCx += Pozycja "instrukcje domowe Codeksa (~\.codex\AGENTS.md)" $agentsTresc.Length $plikAgents `
      "to odpowiednik CLAUDE.md po stronie Codeksa - skracaj go tak samo, warstwami" `
      "AGENTS.md domowy"
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

  # Czyj rachunek jest domyslny: jawne -Narzedzie, a bez niego Claude Code, gdy
  # jest na maszynie (jego linie pokazuje hook Claude Code i nadzorca). Maszyna
  # z samym Codeksem dostaje domyslnie rachunek Codeksa - inaczej jego ladunek
  # hooka pokazywalby liczby plikow, ktorych Codex nie czyta.
  $narzDomyslne = $Narzedzie
  if (-not $narzDomyslne) {
    if ($jestClaude -or (-not $jestCodex)) { $narzDomyslne = "Claude" } else { $narzDomyslne = "Codex" }
  }
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["kubelki"] = $true
