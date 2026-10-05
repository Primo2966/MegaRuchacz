# zasobnik\nadzorca\stan-terminy.ps1 - czesc zasobnik\stan-nadzorcy.ps1 (patrz
# BUDOWA w jego naglowku). Przypomnienia z terminem (2026-10-05): kiedy dozor ma
# zawolac zasobnik\terminy.ps1 (Czy-Sprawdzac-Terminy) i start w tle (Ruszaj-Terminy).
# Cala reszta - samoczynne otwarcie Claude Code, okno z przyciskami, odlozenie krzyzykiem
# o 2 godziny, jedno uruchomienie na przypomnienie - siedzi w terminy.ps1 i narzedzia\terminy.js.
# Nalezy do bazy (bez modulu w rejestrze instalacji): nadzorca jest zawsze, wiec i to.
# Skad wolane: dozor.ps1 (Dozor-Po-Danych). Wczytuje go stan-nadzorcy.ps1 kropka -
# poza stalymi same definicje.

# ------------------------------------------------------------ przypomnienia z terminem

# Rytm ustalony z uzytkownikiem: przy starcie nadzorca (= zalogowanie, start komputera)
# zawsze, potem najwyzej raz na godzine i tylko 8:00-20:00 - poza tymi godzinami nikt nie
# siedzi przy komputerze, a okno Claude Code otwarte w nocy czekaloby do rana na nic.
$MINUT_MIEDZY_TERMINAMI = 60
$GODZINA_TERMINOW_OD = 8
$GODZINA_TERMINOW_DO = 20
# Kiedy dozor ostatnio wolal terminy.ps1 w TYM procesie. $null = jeszcze ani razu od
# startu nadzorcy, czyli pierwszy przebieg po zalogowaniu - ten idzie zawsze.
$script:NadzTerminyOstatnio = $null

function Skrypt-Terminow { return (Join-Path $script:NadzZrodlo "zasobnik\terminy.ps1") }

function Czy-Sprawdzac-Terminy([datetime]$teraz = [datetime]::Now) {
  $w = [pscustomobject]@{ Ruszac = $false; Powod = "" }
  $skrypt = Skrypt-Terminow
  if (-not (Test-Path -LiteralPath $skrypt)) { $w.Powod = "nie ma $skrypt"; return $w }
  if ($null -eq $script:NadzTerminyOstatnio) {
    $w.Ruszac = $true
    $w.Powod = "pierwszy przebieg od startu nadzorcy"
    return $w
  }
  if ($teraz.Hour -lt $GODZINA_TERMINOW_OD -or $teraz.Hour -ge $GODZINA_TERMINOW_DO) {
    $w.Powod = "poza godzinami $GODZINA_TERMINOW_OD-$GODZINA_TERMINOW_DO"
    return $w
  }
  $minut = ($teraz - $script:NadzTerminyOstatnio).TotalMinutes
  if ($minut -lt $MINUT_MIEDZY_TERMINAMI) {
    $w.Powod = "sprawdzone o $($script:NadzTerminyOstatnio.ToString('HH:mm')), nastepne po $MINUT_MIEDZY_TERMINAMI min"
    return $w
  }
  $w.Ruszac = $true
  $w.Powod = "ostatnio o $($script:NadzTerminyOstatnio.ToString('HH:mm'))"
  return $w
}

# Start w tle przez conhost --headless (Odpal-W-Tle) - konsoli nie widac, a okna, ktore
# terminy.ps1 otwiera (Claude Code w Windows Terminal, okno z przyciskami), sa zwyklymi
# oknami pulpitu. Slad i bledy pisze terminy.ps1 do ~\.claude\mr\przypomnienia.log.
function Ruszaj-Terminy {
  $script:NadzTerminyOstatnio = [datetime]::Now
  $skrypt = Skrypt-Terminow
  $arg = '-Zrodlo "' + $script:NadzZrodlo + '" -KatalogDomowy "' + $script:NadzDom + '"'
  if ($script:NadzProba) {
    Write-Host "[proba] NIE startuje przypomnien: powershell -File ${skrypt} ${arg}"
    return $true
  }
  $poszlo = Odpal-W-Tle $skrypt $arg
  if ($poszlo) { Notuj "wystartowalo sprawdzenie przypomnien z terminem" }
  return $poszlo
}

# Znacznik dla stan-nadzorcy.ps1: ten plik wczytal sie do konca.
$script:NadzModuly["terminy"] = $true
