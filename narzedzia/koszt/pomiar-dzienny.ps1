# narzedzia\koszt\pomiar-dzienny.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz
# BUDOWA w jego naglowku). Dzienny pomiar: zadanie LoreKoszt w Harmonogramie, ktore
# raz na dobe zapisuje pelny raport do <dom>\.claude\wiedza\koszt-ostatni.txt
# (Zaloz-Zadanie, Usun-Zadanie), i odczyt linii POMIAR z tego raportu do porownania
# (Poprzedni-Pomiar). Skad wolane: Zaloz-Zadanie / Usun-Zadanie - koszt-pamieci.ps1
# przy -ZalozZadanie / -UsunZadanie (exit wewnatrz tych funkcji konczy caly skrypt);
# Poprzedni-Pomiar - Rachunek-Narzedzia (alarmy.ps1). Linie POMIAR wypisuje pelny
# raport (raport-pelny.ps1). Wczytuje go koszt-pamieci.ps1 kropka przy starcie.

# --- poprzedni pomiar --------------------------------------------------------

function Poprzedni-Pomiar($plik, $narz, $nazwa) {
  # Dzienny raport zapisany przez zadanie z harmonogramu. Od 2026-09-28 kazde
  # narzedzie ma w nim WLASNA linie maszynowa: "POMIAR narzedzie=claude tokenow=..."
  # i "POMIAR narzedzie=codex tokenow=...". Porownujemy wylacznie linie TEGO
  # narzedzia - Claude Code z Claude Code, Codex z Codeksem.
  # Starsze raporty ("POMIAR tokenow=..." bez narzedzia, jeszcze starsze - linia
  # RAZEM) maja jedna sume dla wszystkich narzedzi naraz: na maszynie z Codeksem
  # siedzial w niej ~\.codex\AGENTS.md, ktorego Claude Code nie czyta. Porownanie
  # z taka suma dawaloby falszywy skok (w dol albo w gore), wiec takiego pomiaru
  # NIE bierzemy - zwracamy go z Porownywalny = $false i powodem do wypisania.
  $tekst = Czytaj-Cicho $plik
  if (-not $tekst) { return $null }
  $data = $null
  try { $data = (Get-Item -LiteralPath $plik).LastWriteTime } catch { $data = $null }
  $m = [regex]::Match($tekst, "(?m)^\s*POMIAR\s+narzedzie=$narz\s+tokenow=(\d+)")
  if ($m.Success) {
    return [pscustomobject]@{ Tokeny = [int]$m.Groups[1].Value; Data = $data; Porownywalny = $true; Powod = "" }
  }
  $stary = ([regex]::IsMatch($tekst, '(?m)^\s*POMIAR\s+tokenow=\d+') -or
            [regex]::IsMatch($tekst, '(?m)^\s*RAZEM.*?~\s*[\d ]+\s*tokenow'))
  if ($stary) {
    return [pscustomobject]@{ Tokeny = 0; Data = $data; Porownywalny = $false
      Powod = "poprzedni pomiar jest w starym formacie - jedna suma dla wszystkich narzedzi naraz, nie da sie z niej wyjac samego $nazwa" }
  }
  if ([regex]::IsMatch($tekst, '(?m)^\s*POMIAR\s+narzedzie=')) {
    # raport w nowym formacie, ale bez linii tego narzedzia - np. Codeksa wtedy nie bylo
    return [pscustomobject]@{ Tokeny = 0; Data = $data; Porownywalny = $false
      Powod = "w poprzednim pomiarze nie ma linii dla $nazwa - tego narzedzia wtedy na maszynie nie bylo" }
  }
  return $null
}

# --- zadanie w harmonogramie -------------------------------------------------

function Zaloz-Zadanie($skrypt, $dom, $plikRaportu) {
  # katalog musi istniec wczesniej - Set-Content nie zaklada brakujacych katalogow
  $katalog = Split-Path -Parent $plikRaportu
  if (-not (Test-Path -LiteralPath $katalog)) {
    New-Item -ItemType Directory -Force -Path $katalog | Out-Null
    Write-Host "  zalozony katalog $katalog"
  }

  $s = $skrypt      -replace "'", "''"
  $d = $dom         -replace "'", "''"
  $r = $plikRaportu -replace "'", "''"
  # -Zwykly obowiazkowo: kolorowe linie ida przez Write-Host, a tego Set-Content
  # nie lapie - raport w pliku byloby wtedy bez ostrzezen, czyli klamalby
  $polecenie = "& '$s' -KatalogDomowy '$d' -Zwykly | Set-Content -LiteralPath '$r' -Encoding UTF8"
  # conhost --headless: raport leci raz dziennie i nikt nie chce mrugniecia konsoli
  $argumenty = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ""$polecenie"""

  # UWAGA - tak samo jak w instaluj-lore.ps1: zakladanie zadania przez obiekty
  # (New-ScheduledTaskPrincipal + -Principal) konczy sie "Odmowa dostepu"
  # u zwyklego uzytkownika. Ten sam zapis podany jako XML przechodzi. Dlatego XML.
  try {
    $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    $start = (Get-Date -Format "yyyy-MM-dd") + "T" + $GodzinaZadania + ":00"
    $argXml = [System.Security.SecurityElement]::Escape($argumenty)
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>MegaRuchacz - dzienny raport o koszcie pamieci agenta</Description>
    <URI>\$NazwaZadania</URI>
  </RegistrationInfo>
  <Principals>
    <Principal id="Author">
      <UserId>$sid</UserId>
      <LogonType>InteractiveToken</LogonType>
    </Principal>
  </Principals>
  <Settings>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>PT10M</ExecutionTimeLimit>
    <Enabled>true</Enabled>
  </Settings>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>$start</StartBoundary>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
      <Enabled>true</Enabled>
    </CalendarTrigger>
  </Triggers>
  <Actions Context="Author">
    <Exec>
      <Command>conhost.exe</Command>
      <Arguments>$argXml</Arguments>
    </Exec>
  </Actions>
</Task>
"@
    Register-ScheduledTask -TaskName $NazwaZadania -Xml $xml -Force -ErrorAction Stop | Out-Null
  } catch {
    Write-Host "BLAD  nie udalo sie zalozyc zadania: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
  }
  Write-Host "OK  zadanie $NazwaZadania - codziennie o $GodzinaZadania, raport do $plikRaportu"
  Write-Host "    po wylaczonym komputerze nadrobi przy najblizszym wlaczeniu"
  exit 0
}

function Usun-Zadanie {
  $jest = Get-ScheduledTask -TaskName $NazwaZadania -ErrorAction SilentlyContinue
  if (-not $jest) {
    Write-Host "--  nie ma zadania $NazwaZadania, nie ma czego usuwac"
    exit 0
  }
  try { Unregister-ScheduledTask -TaskName $NazwaZadania -Confirm:$false -ErrorAction Stop }
  catch {
    Write-Host "BLAD  nie udalo sie usunac zadania: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
  }
  Write-Host "OK  zadanie $NazwaZadania usuniete"
  exit 0
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["pomiar-dzienny"] = $true
