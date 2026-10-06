# narzedzia\koszt\otwarcie.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz BUDOWA
# w jego naglowku). Pomiar calego otwarcia sesji Claude Code z transkryptow
# (Pomiar-Otwarcia), od 06.10.2026 (P71) takze Codeksa: otwarcie i zuzycie dzienne
# z ~\.codex\sessions (Pomiar-Otwarcia-Codex, Zuzycie-Codex) i OpenCode (czytnik bazy
# w opencode.ps1), wybor czytnika dla
# narzedzia z listy $NARZEDZIA_AI (Pomiar-Narzedzia) - i tryb -Start, ktory oddaje
# pomiar glownego narzedzia jako JSON (Tryb-Start) - czyta go okno nadzorcy
# (zasobnik\stan-nadzorcy.ps1, Pomiar-Startu). Etap-Ocena (alarmy.ps1) wola
# Pomiar-Narzedzia dla kazdego narzedzia; liczby ida do -Dane (klucze narz.N.*).
# Skad wolane: Tryb-Start - koszt-pamieci.ps1 kropka (exit 0 daje on);
# Pomiar-Otwarcia bez workerow - etap Etap-Ocena (alarmy.ps1), jako calosc do
# procentu MegaRuchacza w otwarciu sesji (tylko do pokazania - prog jest w tokenach).

# --- tryb -Start: ile naprawde kosztuje otwarcie sesji (pomiar, nie szacunek) --
# Rachunek wyzej liczy tylko to, co dokleja MegaRuchacz (znaki / 3). Nie zna
# reszty paczki, ktora Claude Code wysyla przy pierwszej wiadomosci: wlasnych
# instrukcji, opisow narzedzi (takze z serwerow MCP), listy skilli. Tej reszty
# NIE WOLNO zgadywac - bierzemy ja z transkryptow Claude Code
# (<dom>\.claude\projects\<projekt>\*.jsonl): pierwsza odpowiedz modelu w sesji
# ma pole message.usage, a input_tokens + cache_creation_input_tokens +
# cache_read_input_tokens to rozmiar calego kontekstu przy tej odpowiedzi.
# Od tego odejmujemy sama wiadomosc uzytkownika (jej znaki / 3 - szacunek, bo
# transkrypt nie podaje jej tokenow osobno). Wynik: MEDIANA z ostatnich sesji,
# z liczba sesji obok - pojedyncza sesja potrafi byc nietypowa.
# Workerzy (podagenci) maja osobne pliki: <sesja>\subagents\agent-*.jsonl, a przy
# nich agent-*.meta.json z polem agentType. Liczymy tylko role MegaRuchacza.
# Zmierzone 2026-09-25: sesje ~180-200 tys. tokenow, workerzy o waskim zestawie
# narzedzi ~27-40 tys., a podagenci ze wszystkimi narzedziami ~150-180 tys. -
# roznice robia opisy narzedzi, nie tekst MegaRuchacza.
# Brak transkryptow to NIE zero: JSON ma wtedy Powod i okno mowi "nie zmierzono".
# Ten sam pomiar (same sesje, bez workerow) daje procent MegaRuchacza w otwarciu
# sesji - do pokazania; o alarmie decyduje prog w tokenach ($AlarmCzesciOtwarcia,
# od 30.09.2026) - patrz Rachunek-Narzedzia.
# Codex (od 06.10.2026) - Pomiar-Otwarcia-Codex nizej, ten sam ksztalt wyniku; OpenCode
# (tez od 06.10.2026) - opencode.ps1; ktorym czytnikiem mierzyc narzedzie z listy
# $NARZEDZIA_AI (pomiar.ps1), mowi Pomiar-Narzedzia.

# Ile ostatnich rozmow do mediany otwarcia (kazde narzedzie tak samo). 10, bo zestaw
# narzedzi (serwery MCP) zmienia sie co kilka tygodni, a starsze rozmowy mierzylyby
# inna konfiguracje niz dzisiejsza.
$OtwarcieSesji = 10
# Ile pelnych dni sredniej zuzycia Codeksa - tyle samo, co srednia Claude Code w oknie
# ($DNI_ZUZYCIA w zasobnik\nadzorca\stan-zuzycie.ps1), zeby obie liczby staly obok siebie uczciwie.
$DniZuzyciaCodeksa = 7

# Czytnik JSON (System.Web.Extensions). $null = nie da sie go zaladowac; powod idzie
# do $blad, a wolajacy mowi go zamiast pomiaru.
function Czytnik-Json([ref]$blad) {
  try {
    Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
    $s = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $s.MaxJsonLength = [int]::MaxValue
    return $s
  } catch { $blad.Value = $_.Exception.Message; return $null }
}

function Mediana-Liczb($liczby) {
  $s = @($liczby | Sort-Object)
  if ($s.Count -eq 0) { return $null }
  $p = [int][math]::Floor($s.Count / 2)
  if ($s.Count % 2 -eq 1) { return [long]$s[$p] }
  return [long][math]::Round(([double]$s[$p - 1] + [double]$s[$p]) / 2)
}

# Lista zmierzonych otwarc ($lista: obiekty z BezWiadomosci) -> Liczba, Mediana, Min, Max w $w.
function Podsumuj-Otwarcia($w, $lista) {
  $w.Lista = @($lista)
  $w.Liczba = @($lista).Count
  if ($w.Liczba -gt 0) {
    $liczby = @($lista | ForEach-Object { $_.BezWiadomosci })
    $w.Mediana = Mediana-Liczb $liczby
    $w.Min = [long](($liczby | Measure-Object -Minimum).Minimum)
    $w.Max = [long](($liczby | Measure-Object -Maximum).Maximum)
  }
}

function Pomiar-Otwarcia([bool]$zWorkerami) {
  $katTranskryptow = Join-Path $katKlaudii "projects"
  # ta sama lista co $RoleClaude w narzedzia\instaluj-globalnie.ps1
  $rolyWorkerow = @("implementer", "scout", "verifier", "zastepca", "projektant")
  # Ile ostatnich sesji / workerow do mediany i z jakiego okresu. 10 sesji i 14 dni,
  # bo zestaw narzedzi (serwery MCP) zmienia sie co kilka tygodni, a starsze sesje
  # mierzylyby inna konfiguracje niz dzisiejsza. Workerow jest wiecej - 20.
  # Okno 14 dni to $DniUzywania (pomiar.ps1) - te same dni mowia, ktorego narzedzia uzywasz.
  $ileSesji = $OtwarcieSesji; $ileWorkerow = 20; $dniWstecz = $DniUzywania
  $odKiedy = (Get-Date).AddDays(-$dniWstecz)

  $bladParsera = ""
  $serializer = Czytnik-Json ([ref]$bladParsera)

  function Tekst-Wiadomosci($tresc) {
    # tresc wiadomosci uzytkownika: napis albo lista blokow {type:text,text:...}
    if ($null -eq $tresc) { return 0 }
    if ($tresc -is [string]) { return $tresc.Length }
    $n = 0
    foreach ($b in @($tresc)) {
      if ($b -is [System.Collections.IDictionary]) {
        if ($b.ContainsKey("text")) { $n += ("" + $b["text"]).Length }
        elseif ($b.ContainsKey("content")) { $n += ("" + $b["content"]).Length }
      }
    }
    return $n
  }

  # Pierwsza odpowiedz modelu w pliku: rozmiar kontekstu i dlugosc ostatniej
  # wiadomosci uzytkownika przed nia. Czyta tylko poczatek pliku (transkrypty
  # potrafia miec ponad 100 MB). $null = w pliku nie ma odpowiedzi z liczbami.
  function Pierwsza-Odpowiedz($plik) {
    $czytnik = $null
    try {
      $czytnik = New-Object System.IO.StreamReader($plik, [System.Text.Encoding]::UTF8)
      $znakiUzytkownika = 0
      $nr = 0
      while ((-not $czytnik.EndOfStream) -and ($nr -lt 600)) {
        $linia = $czytnik.ReadLine(); $nr++
        if (-not $linia) { continue }
        $jestUser = $linia.Contains('"type":"user"')
        $jestAsystent = $linia.Contains('"type":"assistant"') -and $linia.Contains('"usage"')
        if (-not ($jestUser -or $jestAsystent)) { continue }
        $o = $null
        try { $o = $serializer.DeserializeObject($linia) } catch { continue }
        if (-not ($o -is [System.Collections.IDictionary])) { continue }
        $typ = "" + $o["type"]
        $m = $o["message"]
        if (-not ($m -is [System.Collections.IDictionary])) { continue }
        if ($typ -eq "user") { $znakiUzytkownika = Tekst-Wiadomosci $m["content"]; continue }
        if ($typ -ne "assistant") { continue }
        $u = $m["usage"]
        if (-not ($u -is [System.Collections.IDictionary])) { continue }
        $we = [long]0; $zap = [long]0; $odc = [long]0
        if ($u.ContainsKey("input_tokens")) { $we = [long]$u["input_tokens"] }
        if ($u.ContainsKey("cache_creation_input_tokens")) { $zap = [long]$u["cache_creation_input_tokens"] }
        if ($u.ContainsKey("cache_read_input_tokens")) { $odc = [long]$u["cache_read_input_tokens"] }
        $razem = $we + $zap + $odc
        # "<synthetic>" i zera to odpowiedz bez prawdziwego wywolania modelu
        if ($razem -le 0) { return $null }
        $bezW = $razem - [long](Tokeny $znakiUzytkownika)
        return [pscustomobject]@{
          Kiedy = ("" + $o["timestamp"]); Model = ("" + $m["model"]); Kontekst = $razem
          ZnakiWiadomosci = $znakiUzytkownika; BezWiadomosci = [long][math]::Max(0, $bezW)
        }
      }
      return $null
    } finally { if ($czytnik) { $czytnik.Dispose() } }
  }

  function Pomiar($kandydaci, $ile, $czyWorker) {
    $w = [pscustomobject]@{ Liczba = 0; Mediana = $null; Min = $null; Max = $null; Powod = ""; Pominiete = 0; Bledy = @(); Lista = @(); Narzedzie = "Claude Code" }
    $lista = @()
    foreach ($pl in $kandydaci) {
      if ($lista.Count -ge $ile) { break }
      $rola = ""
      if ($czyWorker) {
        $meta = [System.IO.Path]::ChangeExtension($pl.FullName, ".meta.json")
        if (-not (Test-Path -LiteralPath $meta)) { continue }
        try { $mo = $serializer.DeserializeObject([System.IO.File]::ReadAllText($meta)); $rola = "" + $mo["agentType"] }
        catch { $w.Bledy += "nie odczytalem $meta ($($_.Exception.Message))"; continue }
        if ($rolyWorkerow -notcontains $rola) { continue }
      }
      $p = $null
      try { $p = Pierwsza-Odpowiedz $pl.FullName }
      catch { $w.Bledy += "nie odczytalem $($pl.FullName) ($($_.Exception.Message))"; continue }
      if ($null -eq $p) { $w.Pominiete++; continue }
      $lista += [pscustomobject]@{
        Plik = $pl.FullName.Substring($katTranskryptow.Length).TrimStart('\'); Rola = $rola
        Kiedy = $p.Kiedy; Model = $p.Model; Kontekst = $p.Kontekst
        ZnakiWiadomosci = $p.ZnakiWiadomosci; BezWiadomosci = $p.BezWiadomosci
      }
    }
    Podsumuj-Otwarcia $w $lista
    return $w
  }

  $wynikS = [pscustomobject]@{
    Wersja = 1
    Wygenerowano = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Katalog = $katTranskryptow
    DniWstecz = $dniWstecz
    ZnakiNaToken = $ZnakiNaToken
    Metoda = ("pierwsza odpowiedz modelu w kazdej sesji: input_tokens + cache_creation_input_tokens + cache_read_input_tokens " +
              "z message.usage, minus wiadomosc uzytkownika (znaki / $ZnakiNaToken); mediana z ostatnich sesji")
    Powod = ""
    Sesje = $null
    Workerzy = $null
    MegaRuchaczSesja = [long]($tokSesja + $tokWiadomosc)
    MegaRuchaczStart = [long]$tokSesja
    MegaRuchaczWiadomosc = [long]$tokWiadomosc
    MegaRuchaczWorker = [long]$tokSesja
  }
  if (-not $serializer) {
    $wynikS.Powod = "nie zaladowal sie czytnik JSON (System.Web.Extensions): $bladParsera"
  } elseif (-not (Test-Path -LiteralPath $katTranskryptow -PathType Container)) {
    $wynikS.Powod = "nie ma katalogu z transkryptami Claude Code ($katTranskryptow)"
  } else {
    $pliki = @()
    try {
      $pliki = @(Get-ChildItem -LiteralPath $katTranskryptow -Directory -ErrorAction Stop |
        ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter *.jsonl -File -ErrorAction SilentlyContinue } |
        Where-Object { $_.LastWriteTime -ge $odKiedy } | Sort-Object LastWriteTime -Descending)
      $wynikS.Sesje = Pomiar $pliki $ileSesji $false
      if ($wynikS.Sesje.Liczba -eq 0) {
        $wynikS.Powod = "w $katTranskryptow nie ma ani jednej sesji z ostatnich $dniWstecz dni z odpowiedzia modelu ($($pliki.Count) plikow przejrzanych)"
      }
      if ($zWorkerami) {
        $pod = @(Get-ChildItem -LiteralPath $katTranskryptow -Directory -ErrorAction Stop |
          ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory -ErrorAction SilentlyContinue } |
          ForEach-Object { $k = Join-Path $_.FullName "subagents"; if (Test-Path -LiteralPath $k) { Get-ChildItem -LiteralPath $k -Filter *.jsonl -File -ErrorAction SilentlyContinue } } |
          Where-Object { $_.LastWriteTime -ge $odKiedy } | Sort-Object LastWriteTime -Descending)
        $wynikS.Workerzy = Pomiar $pod $ileWorkerow $true
        if ($wynikS.Workerzy.Liczba -eq 0) {
          $wynikS.Workerzy.Powod = "brak workerow (role: $($rolyWorkerow -join ', ')) z ostatnich $dniWstecz dni w $katTranskryptow"
        }
      }
    } catch {
      $wynikS.Powod = "nie udalo sie przejrzec $katTranskryptow ($($_.Exception.Message))"
    }
  }
  return $wynikS
}

# --- Codex: transkrypty <dom>\.codex\sessions\RRRR\MM\DD\rollout-*.jsonl -------
# Jedna linia = jeden zapis {"timestamp", "type", "payload"} (ten sam ksztalt czyta
# lore\lore\index.py, _read_codex_record). Liczby tokenow niesie zapis "event_msg"
# z payload.type "token_count": payload.info.last_token_usage (ostatnie wywolanie
# modelu) i payload.info.total_token_usage (narastajaco od poczatku rozmowy), kazde
# z polami input_tokens (CALE wejscie - cached_input_tokens to jego czesc czytana
# z pamieci podrecznej), output_tokens i total_tokens = wejscie + wyjscie. info bywa
# null (zdarzenie z samymi limitami) - takie pomijamy. Wiadomosci uzytkownika: zapis
# "response_item", payload.type "message", role "user", bloki "input_text"; te
# zaczynajace sie od "<" albo "# AGENTS.md" dokleja sam Codex (instrukcje, opis
# srodowiska) - to czesc otwarcia, nie Twoja wiadomosc.
# ROZNICA WOBEC CLAUDE CODE: input_tokens Codeksa juz zawiera odczyt z pamieci
# podrecznej, wiec "caly kontekst" to samo input_tokens (u Claude Code trzeba bylo
# sumowac trzy pola), a zuzycie to total_tokens - te same tokeny, ktore Claude Code
# liczy jako wejscie + bufor + wyjscie.
# SPRAWDZONE NA PRAWDZIWYCH ROZMOWACH 06.10.2026 (Codex na komputerze domowym, 3 pliki
# z 30.09-04.10): token_count wyglada dokladnie jak wyzej, w usage dochodzi pole
# cache_write_input_tokens (zero), a obok stoi nowy zapis "token_usage_record" z tymi samymi
# liczbami dla jednego wywolania - nie czytamy go, bo token_count wystarcza i liczylby sie
# drugi raz. Pierwszy zapis pliku to session_meta; PODAGENT (worker odpalony przez inna
# rozmowe) ma w nim payload.source.subagent i thread_source "subagent", a zaraz za nim
# leza session_meta i wiadomosci rozmowy-rodzica (kopia jej kontekstu). Takiego pliku nie
# liczymy do otwarcia okna (to nie Twoje okno, tylko cudzy kontekst), ale jego tokeny ida
# do zuzycia - total_token_usage podagenta liczy sie od zera, bez rodzica. Rozmowy
# "codex exec" (source "exec") to zwykle okna bez ekranu - liczone jak kazde inne.

# Pierwsze wywolanie modelu w rozmowie Codeksa: rozmiar kontekstu i Twoja wiadomosc
# przed nim. Czyta tylko poczatek pliku. $null = w pliku nie ma liczb tokenow;
# obiekt z Podagent = $true = rozmowa podagenta (patrz wyzej), bez liczb.
function Pierwsza-Odpowiedz-Codex($plik, $serializer) {
  $czytnik = $null
  try {
    $czytnik = New-Object System.IO.StreamReader($plik, [System.Text.Encoding]::UTF8)
    $znakiUzytkownika = 0
    $model = ""
    $projekt = ""
    $pierwszaMeta = $true
    $nr = 0
    while ((-not $czytnik.EndOfStream) -and ($nr -lt 3000)) {
      $linia = $czytnik.ReadLine(); $nr++
      if (-not $linia) { continue }
      $tokeny = $linia.Contains('token_count')
      $wiad = $linia.Contains('input_text')
      $kontekst = $linia.Contains('turn_context') -or $linia.Contains('session_meta')
      if (-not ($tokeny -or $wiad -or $kontekst)) { continue }
      $o = $null
      try { $o = $serializer.DeserializeObject($linia) } catch { continue }
      if (-not ($o -is [System.Collections.IDictionary])) { continue }
      $p = $o["payload"]
      if (-not ($p -is [System.Collections.IDictionary])) { continue }
      $typ = "" + $o["type"]
      if ($typ -eq "turn_context") { if ($p["model"]) { $model = "" + $p["model"] }; continue }
      # katalog rozmowy -> nazwa projektu do tabeli w Szczegolach (jak u Claude Code)
      if ($typ -eq "session_meta") {
        if ($pierwszaMeta) {
          $pierwszaMeta = $false
          $zrodloRozmowy = $p["source"]
          if ((("" + $p["thread_source"]) -eq "subagent") -or
              (($zrodloRozmowy -is [System.Collections.IDictionary]) -and $zrodloRozmowy.ContainsKey("subagent"))) {
            return [pscustomobject]@{ Podagent = $true }
          }
          if ($p["cwd"]) { $projekt = [System.IO.Path]::GetFileName(("" + $p["cwd"]).TrimEnd('\', '/')) }
        }
        continue
      }
      if (($typ -eq "response_item") -and (("" + $p["type"]) -eq "message") -and (("" + $p["role"]) -eq "user")) {
        $n = 0
        foreach ($b in @($p["content"])) {
          if (-not ($b -is [System.Collections.IDictionary]) -or (("" + $b["type"]) -ne "input_text")) { continue }
          $t = ("" + $b["text"]).TrimStart()
          if ($t.StartsWith("<") -or $t.StartsWith("# AGENTS.md")) { continue }
          $n += $t.Length
        }
        if ($n -gt 0) { $znakiUzytkownika = $n }
        continue
      }
      if (($typ -ne "event_msg") -or (("" + $p["type"]) -ne "token_count")) { continue }
      $info = $p["info"]
      if (-not ($info -is [System.Collections.IDictionary])) { continue }
      $ost = $info["last_token_usage"]
      if (-not ($ost -is [System.Collections.IDictionary])) { continue }
      $razem = [long]0
      if ($ost.ContainsKey("input_tokens")) { $razem = [long]$ost["input_tokens"] }
      if ($razem -le 0) { continue }
      $bezW = $razem - [long](Tokeny $znakiUzytkownika)
      return [pscustomobject]@{
        Kiedy = ("" + $o["timestamp"]); Model = $model; Kontekst = $razem; Projekt = $projekt
        ZnakiWiadomosci = $znakiUzytkownika; BezWiadomosci = [long][math]::Max(0, $bezW); Podagent = $false
      }
    }
    return $null
  } finally { if ($czytnik) { $czytnik.Dispose() } }
}

# Otwarcie okna rozmowy Codeksa - mediana z ostatnich rozmow, ten sam ksztalt co
# Sesje w Pomiar-Otwarcia. Brak katalogu i brak liczb to Powod, nigdy zero.
function Pomiar-Otwarcia-Codex($n, $serializer) {
  $w = [pscustomobject]@{ Liczba = 0; Mediana = $null; Min = $null; Max = $null; Powod = ""; Pominiete = 0; Bledy = @(); Lista = @(); Narzedzie = $n.Nazwa }
  if (-not (Test-Path -LiteralPath $n.KatRozmow -PathType Container)) {
    $w.Powod = "nie ma katalogu z rozmowami $($n.Nazwa) ($($n.KatRozmow))"
    return $w
  }
  $pliki = @(Pliki-Rozmow $n ((Get-Date).AddDays(-$DniUzywania)))
  $lista = @()
  $podagenci = 0
  foreach ($pl in $pliki) {
    if ($lista.Count -ge $OtwarcieSesji) { break }
    $p = $null
    try { $p = Pierwsza-Odpowiedz-Codex $pl.FullName $serializer }
    catch { $w.Bledy += "nie odczytalem $($pl.FullName) ($($_.Exception.Message))"; continue }
    if ($null -eq $p) { $w.Pominiete++; continue }
    if ($p.Podagent) { $podagenci++; continue }
    # Plik zaczyna sie od projektu (jak u Claude Code: <projekt>\<rozmowa>) - tabela
    # w Szczegolach bierze z niego pierwszy czlon; bez projektu zostaje data RRRR\MM\DD.
    $wzgl = $pl.FullName.Substring($n.KatRozmow.Length).TrimStart('\')
    if ($p.Projekt) { $wzgl = "$($p.Projekt)\$($pl.Name)" }
    $lista += [pscustomobject]@{
      Plik = $wzgl; Rola = ""
      Kiedy = $p.Kiedy; Model = $p.Model; Kontekst = $p.Kontekst
      ZnakiWiadomosci = $p.ZnakiWiadomosci; BezWiadomosci = $p.BezWiadomosci
    }
  }
  Podsumuj-Otwarcia $w $lista
  if ($w.Liczba -eq 0) {
    $w.Powod = "w $($n.KatRozmow) nie ma ani jednej rozmowy z ostatnich $DniUzywania dni z liczba tokenow ($($pliki.Count) plikow przejrzanych)"
    if ($podagenci -gt 0) { $w.Powod += "; $podagenci to rozmowy podagentow - tych nie licze do otwarcia" }
  }
  return $w
}

# Zuzycie tokenow w rozmowach z Codeksem: dzis i srednio dziennie z $DniZuzyciaCodeksa
# PELNYCH dni (bez dzisiejszego; suma dzielona przez liczbe dni - takze tych bez rozmow,
# tak samo jak srednia Claude Code w oknie). Z kazdego zdarzenia token_count bierzemy
# PRZYROST total_tokens wzgledem poprzedniego w tym samym pliku - zdarzenie powtorzone
# z ta sama suma daje zero, wiec nic sie nie liczy dwa razy. Spadek sumy (rozmowa
# wznowiona od zera) = bierzemy last_token_usage. Dzien wedlug lokalnej daty pola
# timestamp (UTC). Linie z tekstem "token_count" wyciaga Select-String (szybko),
# a dopiero te parsujemy.
function Zuzycie-Codex($n, $serializer) {
  $dzis = [datetime]::Today
  $od = $dzis.AddDays(-$DniZuzyciaCodeksa)
  $z = [pscustomobject]@{
    Dzis = $null; Srednia = $null; Dni = $DniZuzyciaCodeksa; DniZRozmowami = 0
    Od = $od.ToString("yyyy-MM-dd"); Do = $dzis.AddDays(-1).ToString("yyyy-MM-dd")
    Pliki = 0; Zdarzenia = 0; Bufor = $null; Powod = ""; Bledy = @()
  }
  if (-not (Test-Path -LiteralPath $n.KatRozmow -PathType Container)) {
    $z.Powod = "nie ma katalogu z rozmowami $($n.Nazwa) ($($n.KatRozmow))"
    return $z
  }
  $pliki = @(Pliki-Rozmow $n $od)
  $z.Pliki = $pliki.Count
  # Brak plikow z tych dni = naprawde nic (katalog przejrzany), nie "nie wiem".
  $z.Dzis = [long]0; $z.Srednia = [long]0
  if ($pliki.Count -eq 0) { return $z }
  $dni = @{}; $bufor = [long]0; $suma = [long]0
  $bl = @()
  # Podagent ma na poczatku pliku KOPIE rozmowy-rodzica, razem z jej zdarzeniami token_count
  # (sumy rodzica: na komputerze domowym 14 z 43 plikow podagentow, po 18-143 mln tokenow,
  # z data skopiowania). Wlasna historia podagenta zaczyna sie od zapisu o numerze
  # payload.subagent_history_start_ordinal z pierwszego session_meta - wczesniejsze
  # zdarzenia pomijamy, bo liczylyby tokeny rodzica drugi raz.
  $startPodagenta = @{}
  foreach ($pl in $pliki) {
    $czyt = $null
    try {
      $czyt = New-Object System.IO.StreamReader($pl.FullName, [System.Text.Encoding]::UTF8)
      $o = $serializer.DeserializeObject($czyt.ReadLine())
      $p = $null
      if ($o -is [System.Collections.IDictionary]) { $p = $o["payload"] }
      if (($p -is [System.Collections.IDictionary]) -and ((("" + $p["thread_source"]) -eq "subagent") -or
          (($p["source"] -is [System.Collections.IDictionary]) -and $p["source"].ContainsKey("subagent"))) -and
          ("" + $p["subagent_history_start_ordinal"]) -match '^\d+$') {
        $startPodagenta[$pl.FullName] = [long]$p["subagent_history_start_ordinal"]
      }
    } catch {
      $z.Bledy += "nie odczytalem poczatku $($pl.FullName) ($($_.Exception.Message))"
    } finally { if ($czyt) { $czyt.Dispose() } }
  }
  $trafienia = @(Select-String -LiteralPath @($pliki | ForEach-Object { $_.FullName }) -Pattern 'token_count' -SimpleMatch -ErrorAction SilentlyContinue -ErrorVariable +bl)
  foreach ($b in @($bl)) { $z.Bledy += "nie odczytalem pliku rozmowy ($b)" }
  $poprz = @{}
  foreach ($t in $trafienia) {
    $o = $null
    try { $o = $serializer.DeserializeObject($t.Line) } catch { continue }
    if (-not ($o -is [System.Collections.IDictionary]) -or (("" + $o["type"]) -ne "event_msg")) { continue }
    if ($startPodagenta.ContainsKey($t.Path) -and ([long](Pole-Liczba $o "ordinal") -lt $startPodagenta[$t.Path])) { continue }
    $p = $o["payload"]
    if (-not ($p -is [System.Collections.IDictionary]) -or (("" + $p["type"]) -ne "token_count")) { continue }
    $info = $p["info"]
    if (-not ($info -is [System.Collections.IDictionary])) { continue }
    $cal = $info["total_token_usage"]; $ost = $info["last_token_usage"]
    if (-not ($cal -is [System.Collections.IDictionary])) { continue }
    $kiedy = [datetime]::MinValue
    if (-not [datetime]::TryParse(("" + $o["timestamp"]), [Globalization.CultureInfo]::InvariantCulture,
                                  [Globalization.DateTimeStyles]::RoundtripKind, [ref]$kiedy)) { continue }
    $z.Zdarzenia++
    $teraz = [long]$cal["total_tokens"]; $terazBuf = [long]$cal["cached_input_tokens"]
    $byl = $poprz[$t.Path]
    if ($null -eq $byl) { $byl = @([long]0, [long]0) }
    $przyrost = $teraz - $byl[0]; $przyrostBuf = $terazBuf - $byl[1]
    if ($przyrost -lt 0) {
      $przyrost = [long]0; $przyrostBuf = [long]0
      if ($ost -is [System.Collections.IDictionary]) { $przyrost = [long]$ost["total_tokens"]; $przyrostBuf = [long]$ost["cached_input_tokens"] }
    }
    $poprz[$t.Path] = @($teraz, $terazBuf)
    $dzien = $kiedy.ToLocalTime().Date
    if ($dzien -lt $od) { continue }
    $k = $dzien.ToString("yyyy-MM-dd")
    if (-not $dni.ContainsKey($k)) { $dni[$k] = [long]0 }
    $dni[$k] += $przyrost
    if ($dzien -lt $dzis) { $suma += $przyrost; $bufor += [math]::Max([long]0, $przyrostBuf) }
  }
  if ($z.Zdarzenia -eq 0) {
    $z.Dzis = $null; $z.Srednia = $null
    $z.Powod = "w $($pliki.Count) plikach rozmow $($n.Nazwa) z ostatnich $DniZuzyciaCodeksa dni nie znalazlem ani jednej liczby tokenow (zdarzenie token_count)"
    if ($z.Bledy.Count -gt 0) { $z.Powod += "; $($z.Bledy[0])" }
    return $z
  }
  $kDzis = $dzis.ToString("yyyy-MM-dd")
  if ($dni.ContainsKey($kDzis)) { $z.Dzis = [long]$dni[$kDzis] }
  $z.DniZRozmowami = @($dni.Keys | Where-Object { ($_ -ne $kDzis) -and ($dni[$_] -gt 0) }).Count
  $z.Srednia = [long][math]::Round($suma / [double]$DniZuzyciaCodeksa)
  $z.Bufor = [long][math]::Round($bufor / [double]$DniZuzyciaCodeksa)
  return $z
}

# Pomiar JEDNEGO narzedzia z listy $NARZEDZIA_AI - wybor czytnika po polu Format.
# Nowe narzedzie z tym samym formatem nie potrzebuje tu nic; nowy format to nowa
# galaz tutaj, a bez niej okno mowi wprost, ze tych rozmow jeszcze nie umiemy czytac.
# Wynik: Otwarcie (ksztalt Sesje z Pomiar-Otwarcia) z Powod, Workerzy (tylko Claude
# Code), Zuzycie (Dzis, Srednia ... albo $null, gdy liczy je ktos inny - ZuzycieWOknie:
# Claude Code liczy okno nadzorcy, zasobnik\nadzorca\stan-zuzycie.ps1) i Blad, gdy
# pomiar sie wywrocil.
function Pomiar-Narzedzia($n, [bool]$zWorkerami, [bool]$zZuzyciem) {
  $p = [pscustomobject]@{
    Klucz = $n.Klucz; Nazwa = $n.Nazwa; Uzywane = [bool]$n.Uzywane; Ostatnio = ""
    Katalog = $n.KatRozmow; Metoda = ""; Powod = ""; Otwarcie = $null; Workerzy = $null
    Zuzycie = $null; ZuzycieWOknie = $false; Blad = ""
  }
  if ($n.Ostatnio) { $p.Ostatnio = $n.Ostatnio.ToString("yyyy-MM-dd HH:mm") }
  try {
    switch ($n.Format) {
      "claude" {
        $o = Pomiar-Otwarcia $zWorkerami
        $p.Otwarcie = $o.Sesje; $p.Workerzy = $o.Workerzy; $p.Powod = $o.Powod
        $p.Katalog = $o.Katalog; $p.Metoda = $o.Metoda; $p.ZuzycieWOknie = $true
      }
      "codex" {
        $bladParsera = ""
        $ser = Czytnik-Json ([ref]$bladParsera)
        $p.Metoda = ("pierwsze wywolanie modelu w kazdej rozmowie Codeksa: input_tokens z payload.info.last_token_usage " +
                     "(zdarzenie token_count; zawiera tez odczyt z pamieci podrecznej), minus Twoja wiadomosc (znaki / $ZnakiNaToken); " +
                     "mediana z ostatnich rozmow")
        if (-not $ser) {
          $p.Powod = "nie zaladowal sie czytnik JSON (System.Web.Extensions): $bladParsera"
        } else {
          $p.Otwarcie = Pomiar-Otwarcia-Codex $n $ser
          $p.Powod = $p.Otwarcie.Powod
          if ($zZuzyciem) { $p.Zuzycie = Zuzycie-Codex $n $ser }
        }
        $p.Workerzy = [pscustomobject]@{ Liczba = 0; Mediana = $null; Min = $null; Max = $null
          Powod = "start workera mierze tylko w Claude Code"; Pominiete = 0; Bledy = @(); Lista = @() }
      }
      "opencode" {
        # Rozmowy w bazie SQLite, czytanej tylko do odczytu - opencode.ps1.
        $bladParsera = ""
        $ser = Czytnik-Json ([ref]$bladParsera)
        $p.Katalog = $n.Baza
        $p.Metoda = ("pierwsza odpowiedz modelu w kazdej rozmowie OpenCode (baza opencode.db, tylko odczyt): tokens.input + cache.read + cache.write " +
                     "z message.data, minus Twoja wiadomosc (znaki / $ZnakiNaToken); mediana z ostatnich rozmow, bez podagentow, rozmow rozwidlonych " +
                     "i rozmow cyklu wiedzy")
        if (-not $ser) {
          $p.Powod = "nie zaladowal sie czytnik JSON (System.Web.Extensions): $bladParsera"
        } else {
          $roz = Rozmowy-OpenCode $n $ser
          $p.Otwarcie = Pomiar-Otwarcia-OpenCode $n $roz $ser
          $p.Powod = $p.Otwarcie.Powod
          if ($zZuzyciem) { $p.Zuzycie = Zuzycie-OpenCode $n $roz }
        }
        $p.Workerzy = [pscustomobject]@{ Liczba = 0; Mediana = $null; Min = $null; Max = $null
          Powod = "start workera mierze tylko w Claude Code"; Pominiete = 0; Bledy = @(); Lista = @() }
      }
      default {
        $p.Powod = "nie umiem jeszcze odczytac rozmow $($n.Nazwa) - MegaRuchacz nie ma czytnika ich zapisu"
      }
    }
  } catch {
    $p.Blad = "pomiar $($n.Nazwa) sie wywrocil ($($_.Exception.Message))"
    if (-not $p.Powod) { $p.Powod = $p.Blad }
  }
  return $p
}

# Tryb-Start - JSON z pomiarem otwarcia sesji (same znaki ASCII); exit 0 daje koszt-pamieci.ps1.
# Wola go koszt-pamieci.ps1 KROPKA (". Tryb-Start"), wiec biegnie w zasiegu skryptu
# glownego: zmienne i funkcje, ktore tu powstaja, widzi dalszy przebieg - tak samo,
# jak gdy ten kod stal w koszt-pamieci.ps1 wprost.
# Pola na wierzchu (Sesje, Workerzy, Powod, MegaRuchacz*) mowia o GLOWNYM narzedziu tej
# maszyny ($narzDomyslne - tego, ktorego uzywasz; z samym Codeksem to Codex), zeby okno
# nadzorcy pokazywalo otwarcie, ktore naprawde placisz. Sesje.Narzedzie i Narzedzie
# mowia, czyje to liczby. Narzedzia - pomiar kazdego narzedzia z listy osobno.
function Tryb-Start {
  $wynikS = Pomiar-Otwarcia $true
  $pomiary = @()
  foreach ($n in @($narzedzia)) {
    if ($n.Format -eq "claude") {
      $pomiary += [pscustomobject]@{ Klucz = $n.Klucz; Nazwa = $n.Nazwa; Uzywane = [bool]$n.Uzywane
        Ostatnio = $(if ($n.Ostatnio) { $n.Ostatnio.ToString("yyyy-MM-dd HH:mm") } else { "" })
        Powod = $wynikS.Powod; Otwarcie = $wynikS.Sesje; MegaRuchacz = [long]($tokSesja + $tokWiadomosc) }
    } else {
      $pn = Pomiar-Narzedzia $n $false $false
      # Czesc MegaRuchacza z rachunku TEGO narzedzia (kubelki.ps1): Codex i od 06.10.2026
      # OpenCode. Narzedzie bez rachunku zostaje z pusta - nigdy z pozyczona liczba.
      $mrN = $null
      if ($n.Narz -eq "Codex") { $mrN = [long]($tokSesjaCx + $tokWiadomoscCx) }
      elseif ($n.Narz -eq "OpenCode") { $mrN = [long]($tokSesjaOc + $tokWiadomoscOc) }
      $pomiary += [pscustomobject]@{ Klucz = $pn.Klucz; Nazwa = $pn.Nazwa; Uzywane = $pn.Uzywane; Ostatnio = $pn.Ostatnio
        Powod = $pn.Powod; Otwarcie = $pn.Otwarcie; MegaRuchacz = $mrN; Pomiar = $pn }
    }
  }
  # Glowne narzedzie inne niz Claude Code (z samym Codeksem albo z samym OpenCode) - na
  # wierzch idzie jego pomiar i jego czesc MegaRuchacza (start + wiadomosc z jego rachunku).
  $glowne = "Claude Code"
  $doms = @{
    "Codex"    = @{ Klucz = "codex";    Start = $tokSesjaCx; Wiadomosc = $tokWiadomoscCx }
    "OpenCode" = @{ Klucz = "opencode"; Start = $tokSesjaOc; Wiadomosc = $tokWiadomoscOc } }
  $dom = $doms["$narzDomyslne"]
  if ($dom) {
    $px = @($pomiary | Where-Object { $_.Klucz -eq $dom.Klucz }) | Select-Object -First 1
    if ($px) {
      $glowne = $px.Nazwa
      $wynikS.Katalog = $px.Pomiar.Katalog
      $wynikS.Metoda = $px.Pomiar.Metoda
      $wynikS.Powod = $px.Powod
      $wynikS.Sesje = $px.Otwarcie
      $wynikS.Workerzy = $px.Pomiar.Workerzy
      $wynikS.MegaRuchaczSesja = [long]($dom.Start + $dom.Wiadomosc)
      $wynikS.MegaRuchaczStart = [long]$dom.Start
      $wynikS.MegaRuchaczWiadomosc = [long]$dom.Wiadomosc
      $wynikS.MegaRuchaczWorker = $null
    }
  }
  foreach ($x in $pomiary) { if ($x.PSObject.Properties["Pomiar"]) { $x.PSObject.Properties.Remove("Pomiar") } }
  $wynikS | Add-Member -NotePropertyName Narzedzie -NotePropertyValue $glowne
  $wynikS | Add-Member -NotePropertyName Narzedzia -NotePropertyValue @($pomiary)
  $json = $wynikS | ConvertTo-Json -Depth 6 -Compress
  $json = [regex]::Replace($json, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
  Write-Output $json
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["otwarcie"] = $true
