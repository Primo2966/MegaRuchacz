# narzedzia\koszt\tryb-warstwy.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz BUDOWA
# w jego naglowku). Tryb -Warstwy (Tryb-Warstwy): JSON z lista WSZYSTKICH warstw
# pamieci dla zakladki "Warstwy pamieci" w oknie nadzorcy (zasobnik\stan-nadzorcy.ps1,
# Warstwy-Pamieci). Skad wolane: koszt-pamieci.ps1 kropka po Etap-Kubelki (exit 0
# daje on) - liczby bierze z tych samych pozycji, co rachunek (kubelki.ps1).

# --- tryb -Warstwy: inwentarz warstw pamieci dla okna nadzorcy ---------------
# Jedna lista, z ktorej zakladka "Warstwy pamieci" w zasobnik\nadzorca.ps1
# rysuje wszystko. Start sesji i kazda wiadomosc biora sie z tych samych pozycji,
# co rachunek wyzej ($kubSesja, $kubWiadomosc) - okno niczego nie liczy drugi
# raz. Warstwy na zadanie i nieuzywane, ktorych rachunek nie zna (nic nie
# kosztuja, dopoki nikt po nie nie siegnie), sa dolozone TUTAJ, zeby lista
# warstw zyla w jednym miejscu.
# BRAK PLIKU NIGDY NIE USUWA WARSTWY Z LISTY: warstwa zostaje ze stanem "brak"
# i zdaniem, czego brakuje. Pominiety wiersz czytalby sie jak "tej warstwy nie
# ma", a to jest wprost odwrotnie - jest, tylko jej plik zniknal.
# Stany: jest / pusty / brak / blad (plik jest, ale nie do odczytania) /
# nieaktywna (doklejka, ktora w tej chwili nic nie dokleja - to nie usterka).
# Wola go koszt-pamieci.ps1 KROPKA (". Tryb-Warstwy"), wiec funkcje zdefiniowane
# w srodku i zmienne trafiaja do zasiegu skryptu glownego - tak samo, jak gdy ten
# kod stal w koszt-pamieci.ps1 wprost; exit 0 po wypisaniu JSON-u daje tamten plik.
function Tryb-Warstwy {
  # $script:UwagiWarstw, $katProjektu, $trybGlobalny, $polStart, $polWiad
  # i $przypUzywany sa policzone wyzej, przy rachunku - tu uzywamy tych samych.

  function Stan-Pliku($sciezka, [bool]$czytaj = $true) {
    $s = [pscustomobject]@{ Istnieje = $false; Stan = "brak"; Brak = ""; Znaki = $null; Bajty = $null; Zmieniony = $null }
    if (-not $sciezka) { $s.Brak = "nie wiadomo, gdzie lezy ten plik"; return $s }
    if (-not (Test-Path -LiteralPath $sciezka -PathType Leaf)) { $s.Brak = "nie ma pliku $sciezka"; return $s }
    $s.Istnieje = $true
    try {
      $el = Get-Item -LiteralPath $sciezka -Force -ErrorAction Stop
      $s.Bajty = [long]$el.Length
      $s.Zmieniony = $el.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
    } catch {
      $s.Stan = "blad"
      $s.Brak = "plik $sciezka jest, ale nie da sie odczytac jego danych ($($_.Exception.Message))"
      return $s
    }
    if (-not $czytaj) {
      if ($s.Bajty -gt 0) { $s.Stan = "jest" } else { $s.Stan = "pusty"; $s.Brak = "plik jest, ale pusty" }
      return $s
    }
    $tekst = $null
    try { $tekst = Czytaj $sciezka }
    catch {
      # plik JEST, tylko nie da sie go przeczytac - to co innego niz jego brak
      $s.Stan = "blad"
      $s.Brak = "plik $sciezka jest, ale nie da sie go odczytac ($($_.Exception.Message))"
      return $s
    }
    $s.Znaki = ("" + $tekst).Length
    if ($s.Znaki -gt 0) { $s.Stan = "jest" } else { $s.Stan = "pusty"; $s.Brak = "plik jest, ale pusty" }
    return $s
  }

  function Warstwa($id, $nazwa, $sciezka, $kiedy, $trwalosc, $ktoPisze, $opis, $rodzaj = "plik", $rodzic = "", $narz = "") {
    # Kiedy: start / wiadomosc / zadanie / nieuzywane. Trwalosc: stala / tymczasowa
    # (albo mieszana - plik, ktory dzieli sie na podwarstwy obu rodzajow).
    # Rodzaj: plik / ladunek (JSON hooka - Tresc to to, co naprawde leci do modelu) /
    # podwarstwa (kawalek pliku - Tresc to ten kawalek) / katalog / baza / doklejka.
    # Narzedzie: klucz z $NARZEDZIA_AI, gdy warstwa trafia TYLKO do tego narzedzia
    # (pusty = do kazdego / niczyja). Brak takiej warstwy przy narzedziu, ktorego tu nie
    # uzywasz, to stan "nie-dotyczy" (szary), nie "brak" (czerwony) - patrz koniec listy.
    return [pscustomobject]@{
      Id = $id; Nazwa = $nazwa; Sciezka = "$sciezka"; Kiedy = $kiedy; Trwalosc = $trwalosc
      KtoPisze = $ktoPisze; Opis = $opis; Rodzaj = $rodzaj; Rodzic = $rodzic
      Istnieje = $false; Stan = "brak"; Brak = ""; Znaki = $null; Tokeny = $null
      Bajty = $null; Zmieniony = $null; Limit = $null; Tresc = $null; Pliki = @()
      Narzedzie = $narz; NarzedzieNazwa = ""
    }
  }

  # Gdzie jeszcze stoi sekcja "## Co wiem" - zdanie do braku sekcji w jednym pliku,
  # zeby "brak" mowil tez, gdzie ta sekcja jest (albo ze nie ma jej nigdzie).
  function Gdzie-Indziej-Co-Wiem($bezPliku) {
    $inne = @($narzedzia | Where-Object { $_.Warstwy -and $_.Warstwy.MaSekcje -and ((Klucz-Sciezki $_.Instrukcje) -ne (Klucz-Sciezki $bezPliku)) })
    if ($inne.Count -eq 0) { return " - i nie ma jej w zadnym innym pliku instrukcji ($((@($narzedzia | ForEach-Object { $_.Instrukcje })) -join ', '))" }
    return " - sekcja jest w: " + ((@($inne | ForEach-Object { "$($_.Instrukcje) (czyta $($_.Nazwa))" })) -join ", ")
  }

  function Z-Pliku($wa, [bool]$czytaj = $true) {
    $s = Stan-Pliku $wa.Sciezka $czytaj
    $wa.Istnieje = $s.Istnieje; $wa.Stan = $s.Stan; $wa.Brak = $s.Brak
    $wa.Znaki = $s.Znaki; $wa.Bajty = $s.Bajty; $wa.Zmieniony = $s.Zmieniony
    if ($null -ne $s.Znaki) { $wa.Tokeny = Tokeny $s.Znaki }
    return $wa
  }

  # Sekcja "## Co wiem" w pliku instrukcji narzedzia innego niz Claude Code (AGENTS.md
  # Codeksa, AGENTS.md OpenCode) - te same podwarstwy, co w CLAUDE.md: tam narzedzie ma
  # pamiec o Tobie i firmie. Pokazujemy je, gdy sekcja tam jest albo gdy narzedzia uzywasz -
  # wtedy jej brak jest usterka. Liczby z pomiaru Etap-Pomiar (Zmierz-Warstwy na tym
  # pliku) - nic sie nie liczy drugi raz. Id: <id pliku>-stala i <id pliku>-biezace.
  function Podwarstwy-Co-Wiem($wa, $nN, $plikOpis, $kto, $opis) {
    $wynik = @()
    if (-not $nN -or -not $nN.Warstwy -or -not ($nN.Warstwy.MaSekcje -or $nN.Uzywane)) { return }
    $wc = $nN.Warstwy
    $wa.Trwalosc = "mieszana"
    $brakCw = "w $($nN.Instrukcje) nie ma sekcji '## Co wiem'$(Gdzie-Indziej-Co-Wiem $nN.Instrukcje)"
    $brakBz = $brakCw
    if ($wc.MaSekcje) { $brakBz = "w sekcji '## Co wiem' w $($nN.Instrukcje) nie ma podsekcji '### Biezace'" }
    foreach ($pc in @(
        @{ Id = "$($wa.Id)-stala"; Nazwa = "Co wiem - czesc stala ($plikOpis)"; Trwalosc = "stala"; M = $wc.Stala; Tekst = $wc.StalaTekst; Brak = $brakCw },
        @{ Id = "$($wa.Id)-biezace"; Nazwa = "Co wiem - Biezace ($plikOpis)"; Trwalosc = "tymczasowa"; M = $wc.Biezaca; Tekst = $wc.BiezacaTekst; Brak = $brakBz })) {
      $sub = Warstwa $pc.Id $pc.Nazwa $nN.Instrukcje "start" $pc.Trwalosc $kto $opis "podwarstwa" $wa.Id $nN.Klucz
      $sub.Istnieje = $wa.Istnieje; $sub.Bajty = $wa.Bajty; $sub.Zmieniony = $wa.Zmieniony
      if ($pc.M.Znaki -gt 0) {
        $sub.Stan = "jest"; $sub.Znaki = $pc.M.Znaki; $sub.Tokeny = $pc.M.Tokeny; $sub.Tresc = $pc.Tekst
      } elseif ($wc.Blad) {
        $sub.Stan = "blad"; $sub.Brak = $wc.Blad
      } else {
        $sub.Stan = "brak"; $sub.Brak = $pc.Brak
      }
      $wynik += $sub
    }
    return $wynik
  }

  function Opis-Limitu($n, $plik) {
    if ($null -eq $n) { return "limitu nie znam (nie znalazlem go w $plik)" }
    return "do $n znakow"
  }

  $lista = @()
  $juz = @{}

  # --- RAZ, przy starcie sesji -------------------------------------------------

  $plikClaudeProj = Join-Path $katProjektu "CLAUDE.md"
  $lista += Z-Pliku (Warstwa "claude-projekt" "CLAUDE.md projektu" $plikClaudeProj "start" "stala" `
    "czlowiek recznie + git (repozytorium projektu)" `
    "Claude Code wczytuje go sam na starcie kazdej sesji w projekcie $katProjektu" "plik" "" "claude")
  $juz[(Klucz-Sciezki $plikClaudeProj)] = $true

  $wGlob = Z-Pliku (Warstwa "claude-globalny" "CLAUDE.md globalny (caly plik)" $plikClaude "start" "mieszana" `
    "czlowiek recznie + automaty (straznik-zasad.ps1, cykl wiedzy)" `
    "Claude Code wczytuje go sam na starcie KAZDEJ sesji, w kazdym projekcie na tej maszynie. Dzieli sie na podwarstwy ponizej - kazda da sie obejrzec osobno." `
    "plik" "" "claude")
  $lista += $wGlob
  $juz[(Klucz-Sciezki $plikClaude)] = $true

  # Podwarstwy globalnego CLAUDE.md - liczby z pozycji rachunku ($kubSesja),
  # teksty z Zmierz-Warstwy. Brak sekcji to wiersz ze stanem "brak", nie dziura.
  $uwagaBiez = "tymczasowa"
  $pozBiez = @($kubSesja | Where-Object { $_.Krotka -eq "warstwa biezaca" }) | Select-Object -First 1
  if ($pozBiez -and $pozBiez.Uwaga) { $uwagaBiez = $pozBiez.Uwaga.Trim() }
  $podwarstwy = @(
    @{ Krotka = "zasady globalne"; Id = "claude-globalny-blok"; Nazwa = "blok zasad MegaRuchacza"; Trwalosc = "stala"
       Kto = "automat Pilnuj-Zasad w narzedzia\straznik-zasad.ps1 (kopia zasad narzedzia)"; Tekst = $w.BlokTekst
       Opis = "stala kopia zasad narzedzia (Lore, wiedza) - skraca sie ja w zrodle i wgrywa przez wdroz.ps1, nie recznie"
       BrakSekcji = "w $plikClaude nie ma bloku $ZnacznikStart ... $ZnacznikKoniec" },
    @{ Krotka = "warstwa stala"; Id = "claude-globalny-stala"; Nazwa = "Co wiem - czesc stala"; Trwalosc = "stala"
       Kto = "czlowiek recznie + narzedzia\aktualizuj-wiedze.ps1 (awans z Biezace)"; Tekst = $w.StalaTekst
       Opis = "nie wygasa; prog ostrzegawczy $ProgStalej znakow"
       BrakSekcji = "w $plikClaude nie ma sekcji '## Co wiem'$(Gdzie-Indziej-Co-Wiem $plikClaude)" },
    @{ Krotka = "warstwa biezaca"; Id = "claude-globalny-biezace"; Nazwa = "Co wiem - Biezace"; Trwalosc = "tymczasowa"
       Kto = "narzedzia\wyciagnij-fakty.ps1 + aktualizuj-wiedze.ps1 (cykl dzienny)"; Tekst = $w.BiezacaTekst
       Opis = "$uwagaBiez; wpis starszy niz $DniWaznosci dni jest podejrzany"
       BrakSekcji = $(if ($w.MaSekcje) { "w sekcji '## Co wiem' nie ma podsekcji '### Biezace'" } else { "w $plikClaude nie ma sekcji '## Co wiem'$(Gdzie-Indziej-Co-Wiem $plikClaude)" }) })
  # Od P59a zasady pamieci to bloki nazwane lore i wiedza (petla nizej) - wiersz starego wspolnego
  # bloku pokazujemy tylko wtedy, gdy ten jeszcze stoi albo gdy nie ma zadnego z nowych (wtedy "brak").
  $saNoweBloki = (@($w.Bloki | Where-Object { $_.Nazwa -in @("lore", "wiedza") }).Count -gt 0)
  foreach ($pw in $podwarstwy) {
    if (($pw.Id -eq "claude-globalny-blok") -and $saNoweBloki -and ($w.Blok.Znaki -le 0)) { continue }
    $poz = @($kubSesja | Where-Object { ($_.Krotka -eq $pw.Krotka) -and ($_.Skad -eq $plikClaude) }) | Select-Object -First 1
    $sub = Warstwa $pw.Id $pw.Nazwa $plikClaude "start" $pw.Trwalosc $pw.Kto $pw.Opis "podwarstwa" "claude-globalny" "claude"
    $sub.Istnieje = $wGlob.Istnieje; $sub.Bajty = $wGlob.Bajty; $sub.Zmieniony = $wGlob.Zmieniony
    if ($poz) {
      $sub.Stan = "jest"; $sub.Znaki = $poz.Znaki; $sub.Tokeny = $poz.Tokeny; $sub.Tresc = $pw.Tekst
    } elseif (-not $w.Jest) {
      $sub.Stan = $wGlob.Stan; $sub.Brak = $powodBrakuClaude
    } else {
      $sub.Stan = "brak"; $sub.Brak = $pw.BrakSekcji
    }
    $lista += $sub
  }
  # Pozostale bloki MegaRuchacza (np. zasady kierownika) - liczby z tych samych
  # pozycji rachunku za start sesji ($pozycjeBlokow), nic nie liczy sie drugi raz.
  foreach ($b in @($w.Bloki)) {
    if (-not $b.Nazwa) { continue }
    $kto = "automat Pilnuj-Zasad w narzedzia\straznik-zasad.ps1 (kopia zasad narzedzia)"
    if ($b.Nazwa -eq "kierownik") { $kto = "instalator globalny (narzedzia\instaluj-globalnie.ps1, zrodlo: $(Szablon-Kierownika $b.Tekst))" }
    elseif ($b.Nazwa -in @("lore", "wiedza")) { $kto = "automat Pilnuj-Zasad w narzedzia\straznik-zasad.ps1 (zrodlo: zasady-$($b.Nazwa).md, modul $($b.Nazwa) instalatora)" }
    $sub = Warstwa ("claude-globalny-blok-" + $b.Nazwa) "blok zasad MegaRuchacza: $($b.Nazwa)" $plikClaude "start" "stala" `
      $kto "wchodzi na start sesji razem z calym plikiem; rachunek za start sesji liczy go jako osobna pozycje" `
      "podwarstwa" "claude-globalny" "claude"
    $sub.Istnieje = $true; $sub.Stan = "jest"; $sub.Znaki = $b.Znaki; $sub.Tokeny = Tokeny $b.Znaki
    $pozB = $pozycjeBlokow[$b.Nazwa]
    if ($pozB) { $sub.Znaki = $pozB.Znaki; $sub.Tokeny = $pozB.Tokeny }
    $sub.Bajty = $wGlob.Bajty; $sub.Zmieniony = $wGlob.Zmieniony; $sub.Tresc = $b.Tekst
    $lista += $sub
  }

  # Natywna pamiec Claude Code dla projektu. Katalog nazywa sie od sciezki
  # projektu: kazdy znak inny niz litera i cyfra zamieniony na "-"
  # (C:\dev\claude-worker -> C--dev-claude-worker).
  $katPamieci = Join-Path $katKlaudii ("projects\" + ($katProjektu -replace '[^A-Za-z0-9]', '-') + "\memory")
  $wp = Z-Pliku (Warstwa "pamiec-natywna" "natywna pamiec Claude Code (MEMORY.md)" (Join-Path $katPamieci "MEMORY.md") "start" "stala" `
    "Claude Code sam (automatyczna pamiec projektu)" `
    "Claude Code wczytuje ja sam na starcie sesji w tym projekcie - o ile plik istnieje" "plik" "" "claude")
  if ((-not $wp.Istnieje) -and (Test-Path -LiteralPath $katPamieci -PathType Container)) {
    $wp.Stan = "pusty"
    $wp.Brak = "katalog $katPamieci jest, ale pusty - Claude Code nic tu jeszcze nie zapisal, wiec nic sie nie wczytuje"
  }
  $lista += $wp

  # Reszta rachunku za start sesji (Codex, ladunki hookow przy -Projekt).
  $nr = 0
  foreach ($poz in @($kubSesja)) {
    if ($poz.Skad -eq $plikClaude) { continue }
    # CLAUDE.md projektu stoi juz wyzej jako warstwa "claude-projekt"
    if ($juz.ContainsKey((Klucz-Sciezki $poz.Skad))) { continue }
    $nr++
    $jsonowy = ("$($poz.Skad)" -like "*.json")
    $rodzaj = "plik"
    if ($jsonowy) { $rodzaj = "ladunek" }
    $kiedy = "start"
    $opis = "wchodzi na start sesji (pozycja rachunku: $($poz.Krotka))"
    if (($poz.Krotka -eq "zasady z hooka (CC)") -and -not (Czy-Hook-Czyta $polStart $poz.Skad $katProjektu)) {
      $kiedy = "nieuzywane"
      $opis = "zaden hook SessionStart w settings.json go nie wczytuje - plik lezy, ale nie trafia do modelu"
    }
    $wa = Z-Pliku (Warstwa "sesja-$nr" $poz.Nazwa $poz.Skad $kiedy "stala" "instalator MegaRuchacza (wdroz.ps1)" $opis $rodzaj "" "claude")
    $wa.Znaki = $poz.Znaki; $wa.Tokeny = $poz.Tokeny
    if ($jsonowy) { $wa.Tresc = Ladunek-Hooka $poz.Skad }
    $lista += $wa
    $juz[(Klucz-Sciezki $poz.Skad)] = $true
  }
  # Rachunek Codeksa za start sesji - osobne pozycje, bo Claude Code tych plikow
  # nie czyta. Nazwa i opis mowia to wprost, zeby nikt nie doliczal ich do
  # startu sesji Claude Code (do 2026-09-28 robil to sam rachunek).
  foreach ($poz in @($kubSesjaCx)) {
    if ($juz.ContainsKey((Klucz-Sciezki $poz.Skad))) { continue }
    $nr++
    $jsonowy = ("$($poz.Skad)" -like "*.json")
    $rodzaj = "plik"
    if ($jsonowy) { $rodzaj = "ladunek" }
    $kto = "instalator MegaRuchacza (wdroz.ps1)"
    $id = "sesja-$nr"
    if ($poz.Krotka -eq "AGENTS.md domowy") { $kto = "czlowiek recznie + instalator globalny (narzedzia\instaluj-globalnie.ps1, blok zasad)"; $id = "codex-globalny" }
    $wa = Z-Pliku (Warstwa $id "$($poz.Nazwa) - czyta tylko Codex" $poz.Skad "start" "stala" $kto `
      "czyta tylko Codex - Claude Code tego pliku nie wczytuje. Wchodzi na start sesji Codeksa (pozycja rachunku Codeksa: $($poz.Krotka))" $rodzaj "" "codex")
    $wa.Znaki = $poz.Znaki; $wa.Tokeny = $poz.Tokeny
    if ($jsonowy) { $wa.Tresc = Ladunek-Hooka $poz.Skad }
    $lista += $wa
    $juz[(Klucz-Sciezki $poz.Skad)] = $true
    # Sekcja "## Co wiem" w AGENTS.md (Codex ma w niej pamiec o Tobie i firmie) -
    # podwarstwy jak w CLAUDE.md, patrz Podwarstwy-Co-Wiem.
    if ($id -eq "codex-globalny") {
      $lista += @(Podwarstwy-Co-Wiem $wa (Narzedzie-Po-Kluczu "codex") "AGENTS.md" "czlowiek recznie (kopia wiedzy dla Codeksa)" `
        "czyta tylko Codex - wchodzi na start jego sesji razem z calym AGENTS.md (rachunek liczy caly plik jedna pozycja)")
    }
  }

  # OpenCode (od 06.10.2026) czyta ~\.config\opencode\AGENTS.md sam, na starcie kazdej
  # rozmowy - to jego odpowiednik CLAUDE.md. Rachunek MegaRuchacza za OpenCode nie powstaje
  # (kubelki.ps1 zna Claude Code i Codeksa), wiec rozmiar idzie z samego pliku, a sekcja
  # "Co wiem" ma te same podwarstwy, co w AGENTS.md Codeksa. Brak pliku przy OpenCode,
  # ktorego tu nie uzywasz, zamienia sie nizej w "nie dotyczy".
  $nOc = Narzedzie-Po-Kluczu "opencode"
  if ($nOc -and -not $juz.ContainsKey((Klucz-Sciezki $nOc.Instrukcje))) {
    $wa = Z-Pliku (Warstwa "opencode-globalny" "instrukcje domowe OpenCode (~\.config\opencode\AGENTS.md) - czyta tylko OpenCode" $nOc.Instrukcje "start" "stala" `
      "czlowiek recznie + straznik zasad i instalator globalny (bloki zasad MegaRuchacza)" `
      "czyta tylko OpenCode - wczytuje go sam na starcie kazdej rozmowy; Claude Code i Codex tego pliku nie czytaja" "plik" "" "opencode")
    $lista += $wa
    $juz[(Klucz-Sciezki $nOc.Instrukcje)] = $true
    $lista += @(Podwarstwy-Co-Wiem $wa $nOc "AGENTS.md OpenCode" "czlowiek recznie (kopia wiedzy dla OpenCode)" `
      "czyta tylko OpenCode - wchodzi na start jego rozmowy razem z calym AGENTS.md")
  }

  # --- przy KAZDEJ wiadomosci ---------------------------------------------------

  # Ktory ladunek przypomnienia NAPRAWDE leci ($przypUzywany) - policzone wyzej,
  # przy rachunku. W trybie globalnym rachunek mierzy wlasnie ten plik; poza nim
  # moze mierzyc kopie w projekcie i wtedy mowimy to przy wierszu.
  $pozCC = @($kubWiadomosc | Where-Object { $_.Krotka -eq "przypomnienie Claude" }) | Select-Object -First 1
  $sciezkaPrzyp = $przypUzywany
  $opisPrzyp = "hook UserPromptSubmit (narzedzia\przypomnienie.js) dokleja ten ladunek do KAZDEJ wiadomosci"
  if ($pozCC -and $przypUzywany -and ((Klucz-Sciezki $pozCC.Skad) -ne (Klucz-Sciezki $przypUzywany))) {
    $opisPrzyp += ". Uwaga: rachunek w koszt-pamieci.ps1 liczy inna kopie ($($pozCC.Skad)) - ta nizej jest w grupie nieuzywanych"
  }
  if ((-not $sciezkaPrzyp) -and $pozCC) {
    $sciezkaPrzyp = $pozCC.Skad
    $opisPrzyp = "zaden hook UserPromptSubmit w settings.json nie wskazuje ladunku przypomnienia - pokazany plik, ktory liczy rachunek"
  }
  $wa = Z-Pliku (Warstwa "przypomnienie" "przypomnienie zasad (Claude Code)" $sciezkaPrzyp "wiadomosc" "stala" `
    "instalator MegaRuchacza (instaluj-globalnie.ps1 / wdroz.ps1)" $opisPrzyp "ladunek" "" "claude")
  if (-not $sciezkaPrzyp) {
    $wa.Brak = "nie znalazlem ladunku przypomnienia: zaden hook UserPromptSubmit w settings.json go nie wskazuje, a w $Zrodlo nie ma .claude\orchestrator-reminder.json"
  } elseif ($wa.Istnieje -and ($wa.Stan -eq "jest")) {
    $wa.Tresc = Ladunek-Hooka $sciezkaPrzyp
    if ($wa.Tresc) {
      $wa.Znaki = $wa.Tresc.Length; $wa.Tokeny = Tokeny $wa.Znaki
    } else {
      $wa.Stan = "blad"
      $wa.Brak = "plik jest, ale nie ma w nim pola hookSpecificOutput.additionalContext - hook nic z niego nie dokleja"
    }
  }
  $lista += $wa
  if ($sciezkaPrzyp) { $juz[(Klucz-Sciezki $sciezkaPrzyp)] = $true }

  foreach ($poz in @($kubWiadomoscCx)) {
    $wa = Z-Pliku (Warstwa "przypomnienie-codex" "$($poz.Nazwa) - czyta tylko Codex" $poz.Skad "wiadomosc" "stala" "instalator MegaRuchacza (wdroz.ps1)" `
      "czyta tylko Codex - hook UserPromptSubmit Codeksa dokleja ten ladunek do kazdej wiadomosci w Codeksie; Claude Code go nie dostaje" "ladunek" "" "codex")
    $wa.Znaki = $poz.Znaki; $wa.Tokeny = $poz.Tokeny; $wa.Tresc = Ladunek-Hooka $poz.Skad
    $lista += $wa
    $juz[(Klucz-Sciezki $poz.Skad)] = $true
  }

  # Doklejki: tresc powstaje przy kazdej wiadomosci od nowa i nigdzie sie nie
  # zapisuje, wiec podglad pokazuje plik stanu. Limity czytamy ze zrodla,
  # ktore je ustala - wpisane tu na sztywno zaczelyby klamac.
  $plikPrzypJs = Join-Path $Zrodlo "narzedzia\przypomnienie.js"
  $maxArch = Limit-Z-Pliku $plikPrzypJs '(?m)^const\s+MAX_ARCHIWUM\s*=\s*(\d+)'
  $maxStan = Limit-Z-Pliku $plikPrzypJs '(?m)^const\s+MAX_STAN\s*=\s*(\d+)'

  $plikArchStan = Join-Path $katWiedzy ".archiwum-stan.json"
  $wa = Z-Pliku (Warstwa "doklejka-archiwum" "fragmenty 'Z ARCHIWUM' z Lore" $plikArchStan "wiadomosc" "tymczasowa" `
    "narzedzia\przypomnienie.js + lore\lore\recall.py, przy kazdej wiadomosci od nowa" `
    ("1-2 fragmenty dawnych rozmow dobrane do tresci wiadomosci, $(Opis-Limitu $maxArch $plikPrzypJs); doklejane tylko do tej jednej wiadomosci. " +
     "Samej doklejki nikt nie zapisuje - podglad pokazuje plik stanu (co juz pokazano w ktorej sesji).") "doklejka")
  $wa.Limit = $maxArch; $wa.Znaki = $null; $wa.Tokeny = $null
  if (-not (Test-Path -LiteralPath $bazaLore -PathType Leaf)) {
    $wa.Stan = "brak"; $wa.Brak = "nie ma bazy Lore $bazaLore - fragmentow z archiwum nie bedzie"
  } elseif (-not $wa.Istnieje) {
    $wa.Stan = "nieaktywna"; $wa.Brak = "archiwum nic jeszcze nie pokazalo (nie ma pliku stanu $plikArchStan)"
  }
  $lista += $wa

  $plikCyklPostep = Join-Path $katWiedzy ".cykl-postep"
  $wa = Z-Pliku (Warstwa "doklejka-cykl" "linia o stanie cyklu wiedzy" $plikCyklPostep "wiadomosc" "tymczasowa" `
    "narzedzia\cykl-dzienny.ps1 zapisuje stan, narzedzia\przypomnienie.js dokleja" `
    "jedna linia, $(Opis-Limitu $maxStan $plikPrzypJs), tylko gdy cykl wiedzy akurat pracuje albo wlasnie skonczyl; znika po pierwszym pokazaniu" "doklejka")
  $wa.Limit = $maxStan; $wa.Znaki = $null; $wa.Tokeny = $null
  if (-not $wa.Istnieje) {
    $wa.Stan = "nieaktywna"; $wa.Brak = "nie ma pliku $plikCyklPostep - teraz nic sie nie dokleja (plik pojawia sie tylko, gdy cykl pracuje)"
  }
  $lista += $wa

  # --- tylko na zadanie ---------------------------------------------------------

  $lista += Z-Pliku (Warstwa "mapa" "mapa projektu" (Join-Path $katProjektu ".megaruchacz\mapa.md") "zadanie" "stala" `
    "scout (dopisuje) + kierownik" "zaden hook jej nie wczytuje - model czyta ja sam, gdy siegnie po nia narzedziem")
  $lista += Z-Pliku (Warstwa "worklog" "rejestr zadan (worklog)" (Join-Path $katProjektu ".megaruchacz\worklog.md") "zadanie" "tymczasowa" `
    "automat megaruchacz-mr-log.js (start i koniec workera) + kierownik" "biezacy stan zadan; zaden hook go nie wczytuje - model czyta go sam")

  $wk = Warstwa "wiedza" "wiedza referencyjna (katalog)" $katWiedzy "zadanie" "stala" "cykl wiedzy + czlowiek recznie" `
    "pliki czytane tylko wtedy, gdy rozmowa ich dotyczy (odsylacze w globalnym CLAUDE.md)" "katalog"
  $plikiWiedzy = @()
  if (Test-Path -LiteralPath $katWiedzy -PathType Container) {
    $wk.Istnieje = $true
    try {
      $plikiWiedzy = @(Get-ChildItem -LiteralPath $katWiedzy -File -Force -ErrorAction Stop | Sort-Object Name)
      $opisy = @()
      foreach ($pl in $plikiWiedzy) {
        $opisy += [pscustomobject]@{ Nazwa = $pl.Name; Bajty = [long]$pl.Length; Zmieniony = $pl.LastWriteTime.ToString("yyyy-MM-dd HH:mm") }
      }
      $wk.Pliki = @($opisy)
      if ($opisy.Count -gt 0) { $wk.Stan = "jest" } else { $wk.Stan = "pusty"; $wk.Brak = "katalog jest, ale pusty" }
    } catch {
      $wk.Stan = "blad"; $wk.Brak = "katalog $katWiedzy jest, ale nie da sie go wylistowac ($($_.Exception.Message))"
    }
  } else {
    $wk.Brak = "nie ma katalogu $katWiedzy"
  }
  $lista += $wk
  foreach ($pl in @($plikiWiedzy | Where-Object { $_.Extension -eq ".md" })) {
    $tr = "stala"
    $op = "czytany tylko wtedy, gdy rozmowa go dotyczy"
    if ($pl.Name -eq "kandydaci.md") {
      $tr = "tymczasowa"
      $op = "poczekalnia propozycji faktow wylowionych z rozmow - nic stad nie trafia do CLAUDE.md samo"
    }
    $lista += Z-Pliku (Warstwa ("wiedza-" + $pl.BaseName) $pl.Name $pl.FullName "zadanie" $tr "cykl wiedzy + czlowiek recznie" $op "plik" "wiedza")
  }
  # Katalog ze stalymi plikami i tymczasowa poczekalnia to warstwa mieszana - tak
  # samo jak globalny CLAUDE.md. Kolumna "Trwalosc" w oknie i zdanie nad lista
  # maja mowic to samo.
  $trWiedzy = @($lista | Where-Object { $_.Rodzic -eq "wiedza" } | ForEach-Object { $_.Trwalosc } | Select-Object -Unique)
  if ($trWiedzy.Count -gt 1) { $wk.Trwalosc = "mieszana" }

  $lista += Z-Pliku (Warstwa "lore" "baza Lore (pamiec wszystkich rozmow)" $bazaLore "zadanie" "stala" `
    "indeksowanie Lore (lore\lore\index.py)" `
    "model siega do niej narzedziami lore_search / lore_context; do podgladu sie jej nie wczytuje - tylko rozmiar i data" "baza") $false

  # --- nieuzywane ----------------------------------------------------------------
  # Ladunki hookow, ktore leza na dysku, a nie ma ich wyzej. Zanim trafia tutaj,
  # sprawdzamy settings.json - jesli jednak jakis hook je czyta, ida tam, gdzie
  # naprawde wchodza. Kandydata, ktorego pliku nie ma, pomijamy: to nie warstwa,
  # tylko miejsce, w ktorym starsze wersje kladly ladunek.
  $kandydaci = @(
    @{ Sciezka = (Join-Path $katKlaudii "mr\megaruchacz-sesja.json"); Nazwa = "zasady kierownika dla hooka startowego (kopia globalna)"
       Zdarzenie = "start"; Kto = "narzedzia\straznik-zasad.ps1 (Zbuduj-Sesje)" },
    @{ Sciezka = (Join-Path $katProjektu ".claude\megaruchacz-sesja.json"); Nazwa = "zasady kierownika dla hooka startowego (kopia projektu)"
       Zdarzenie = "start"; Kto = "narzedzia\straznik-zasad.ps1 (Zbuduj-Sesje)" },
    @{ Sciezka = (Join-Path $katKlaudii "mr\orchestrator-reminder.json"); Nazwa = "przypomnienie zasad (kopia globalna)"
       Zdarzenie = "wiadomosc"; Kto = "instalator MegaRuchacza (instaluj-globalnie.ps1)" },
    @{ Sciezka = (Join-Path $katProjektu ".claude\orchestrator-reminder.json"); Nazwa = "przypomnienie zasad (kopia projektu)"
       Zdarzenie = "wiadomosc"; Kto = "instalator MegaRuchacza (wdroz.ps1)" })
  $nr = 0
  foreach ($k in $kandydaci) {
    if ($juz.ContainsKey((Klucz-Sciezki $k.Sciezka))) { continue }
    if (-not (Test-Path -LiteralPath $k.Sciezka -PathType Leaf)) { continue }
    $nr++
    $pol = $polWiad
    if ($k.Zdarzenie -eq "start") { $pol = $polStart }
    if (Czy-Hook-Czyta $pol $k.Sciezka $katProjektu) {
      $kiedy = $k.Zdarzenie
      $opis = "hook w settings.json wczytuje ten plik"
    } else {
      $kiedy = "nieuzywane"
      $opis = "nikt go nie czyta: zaden hook w settings.json (globalnym ani projektu) nie wczytuje tego pliku - lezy, ale nie trafia do modelu"
      if ($trybGlobalny) {
        $opis = "nikt go nie czyta w trybie globalnym: zaden hook w settings.json (globalnym ani projektu) nie wczytuje tego pliku - lezy, ale nie trafia do modelu"
      }
    }
    $wa = Z-Pliku (Warstwa "ladunek-$nr" $k.Nazwa $k.Sciezka $kiedy "stala" $k.Kto $opis "ladunek")
    $t = Ladunek-Hooka $k.Sciezka
    if ($t) { $wa.Tresc = $t; $wa.Znaki = $t.Length; $wa.Tokeny = Tokeny $t.Length }
    $lista += $wa
    $juz[(Klucz-Sciezki $k.Sciezka)] = $true
  }

  # NARZEDZIE, KTOREGO TU NIE UZYWASZ: jego warstwa bez pliku albo bez sekcji to nie
  # usterka, tylko "nie dotyczy" - na czerwono swiecilaby falszywym alarmem (komputer
  # z samym Codeksem nie ma po co miec natywnej pamieci Claude Code ani AGENTS.md
  # OpenCode). Powod braku
  # zostaje w zdaniu, wiec nic nie znika po cichu.
  foreach ($wa in $lista) {
    if (-not $wa.Narzedzie) { continue }
    $nw = Narzedzie-Po-Kluczu $wa.Narzedzie
    if (-not $nw) { continue }
    $wa.NarzedzieNazwa = $nw.Nazwa
    if ($nw.Uzywane -or (@("brak", "pusty", "blad") -notcontains "$($wa.Stan)")) { continue }
    $pow = ""
    if ($wa.Brak) { $pow = " ($($wa.Brak))" }
    $wa.Stan = "nie-dotyczy"
    $wa.Brak = "nie dotyczy - nie uzywasz tu $($nw.Nazwa): w ostatnich $DniUzywania dniach nie bylo w nim rozmowy$pow"
  }
  $infoNarz = @()
  foreach ($n in @($narzedzia)) {
    $infoNarz += [pscustomobject]@{ Klucz = $n.Klucz; Nazwa = $n.Nazwa; Uzywane = [bool]$n.Uzywane
      Instrukcje = $n.Instrukcje; CoWiem = [bool]($n.Warstwy -and $n.Warstwy.MaSekcje) }
  }

  $wynikW = [pscustomobject]@{
    Wersja        = 1
    Wygenerowano  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    KatalogDomowy = $KatalogDomowy
    Projekt       = $katProjektu
    TrybGlobalny  = [bool]$trybGlobalny
    ZnakiNaToken  = $ZnakiNaToken
    Uwagi         = @($script:UwagiWarstw)
    Narzedzia     = @($infoNarz)
    Warstwy       = @($lista)
  }
  $json = $wynikW | ConvertTo-Json -Depth 6 -Compress
  # Samo ASCII na wyjsciu: wolajacy czyta przekierowane wyjscie, a PowerShell 5.1
  # pisze je w stronie kodowej konsoli - ogonki wyszlyby krzakami.
  $json = [regex]::Replace($json, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
  Write-Output $json
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["tryb-warstwy"] = $true
