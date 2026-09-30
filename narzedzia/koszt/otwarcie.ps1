# narzedzia\koszt\otwarcie.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz BUDOWA
# w jego naglowku). Pomiar calego otwarcia sesji Claude Code z transkryptow
# (Pomiar-Otwarcia) i tryb -Start, ktory oddaje ten pomiar jako JSON (Tryb-Start) -
# czyta go okno nadzorcy (zasobnik\stan-nadzorcy.ps1, Pomiar-Startu).
# Skad wolane: Tryb-Start - koszt-pamieci.ps1 kropka (exit 0 daje on);
# Pomiar-Otwarcia bez workerow - etap Etap-Ocena (alarmy.ps1), jako podstawa progu
# udzialu MegaRuchacza w otwarciu sesji.

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
# Ten sam pomiar (same sesje, bez workerow) jest podstawa progu udzialu
# MegaRuchacza w otwarciu sesji ($AlarmUdzialuOtwarcia) - patrz Rachunek-Narzedzia.
function Pomiar-Otwarcia([bool]$zWorkerami) {
  $katTranskryptow = Join-Path $katKlaudii "projects"
  # ta sama lista co $RoleClaude w narzedzia\instaluj-globalnie.ps1
  $rolyWorkerow = @("implementer", "scout", "verifier", "zastepca", "projektant")
  # Ile ostatnich sesji / workerow do mediany i z jakiego okresu. 10 sesji i 14 dni,
  # bo zestaw narzedzi (serwery MCP) zmienia sie co kilka tygodni, a starsze sesje
  # mierzylyby inna konfiguracje niz dzisiejsza. Workerow jest wiecej - 20.
  $ileSesji = 10; $ileWorkerow = 20; $dniWstecz = 14
  $odKiedy = (Get-Date).AddDays(-$dniWstecz)

  $serializer = $null
  try {
    Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = [int]::MaxValue
  } catch { $serializer = $null; $bladParsera = $_.Exception.Message }

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

  function Mediana($liczby) {
    $s = @($liczby | Sort-Object)
    if ($s.Count -eq 0) { return $null }
    $p = [int][math]::Floor($s.Count / 2)
    if ($s.Count % 2 -eq 1) { return [long]$s[$p] }
    return [long][math]::Round(([double]$s[$p - 1] + [double]$s[$p]) / 2)
  }

  function Pomiar($kandydaci, $ile, $czyWorker) {
    $w = [pscustomobject]@{ Liczba = 0; Mediana = $null; Min = $null; Max = $null; Powod = ""; Pominiete = 0; Bledy = @(); Lista = @() }
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
    $w.Lista = @($lista)
    $w.Liczba = $lista.Count
    if ($lista.Count -gt 0) {
      $liczby = @($lista | ForEach-Object { $_.BezWiadomosci })
      $w.Mediana = Mediana $liczby
      $w.Min = [long](($liczby | Measure-Object -Minimum).Minimum)
      $w.Max = [long](($liczby | Measure-Object -Maximum).Maximum)
    }
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

# Tryb-Start - JSON z pomiarem otwarcia sesji (same znaki ASCII); exit 0 daje koszt-pamieci.ps1.
# Wola go koszt-pamieci.ps1 KROPKA (". Tryb-Start"), wiec biegnie w zasiegu skryptu
# glownego: zmienne i funkcje, ktore tu powstaja, widzi dalszy przebieg - tak samo,
# jak gdy ten kod stal w koszt-pamieci.ps1 wprost.
function Tryb-Start {
  $json = (Pomiar-Otwarcia $true) | ConvertTo-Json -Depth 6 -Compress
  $json = [regex]::Replace($json, '[^\x00-\x7F]', { param($m) '\u{0:x4}' -f [int][char]$m.Value })
  Write-Output $json
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["otwarcie"] = $true
