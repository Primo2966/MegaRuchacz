# narzedzia\koszt\sufity.ps1 - czesc narzedzia\koszt-pamieci.ps1 (patrz BUDOWA
# w jego naglowku). Sufity: odczyt limitu z pliku, ktory go ustala (Limit-Z-Pliku,
# Limit-Hooka), tresc ladunku hooka (Ladunek-Hooka), jeden wiersz audytu (Sufit)
# i kolejnosc wierszy (Sortuj-Sufity), a na koncu tryb -TylkoSufity (Tryb-Sufity).
# Skad wolane: liste sufitow buduje Etap-Pomiar (pomiar.ps1), sufity Lore dokleja
# pelny raport (raport-pelny.ps1); Tryb-Sufity wola koszt-pamieci.ps1 kropka i to on
# daje kod wyjscia. Wczytuje go koszt-pamieci.ps1 kropka przy starcie.

# --- sufity ------------------------------------------------------------------

function Limit-Z-Pliku($plik, $wzorzec) {
  # jedna liczba wyluskana ze zrodla, ktore ja naprawde ustala; $null, gdy pliku
  # nie ma albo wzorzec nie pasuje - wtedy raport mowi "nie znam sufitu" zamiast
  # podawac wartosc z pamieci
  $tekst = Czytaj-Cicho $plik
  if (-not $tekst) { return $null }
  $m = [regex]::Match($tekst, $wzorzec)
  if (-not $m.Success) { return $null }
  $cyfry = ($m.Groups[1].Value -replace '[^\d]', '')
  if (-not $cyfry) { return $null }
  return [int]$cyfry
}

function Limit-Hooka($plikHookow, $fragmentPolecenia) {
  # additionalContextLimit hooka rozpoznanego po tym, jaki plik wczytuje
  $tekst = Czytaj-Cicho $plikHookow
  if (-not $tekst) { return $null }
  try { $j = $tekst | ConvertFrom-Json } catch { return $null }
  if (-not $j.hooks) { return $null }
  foreach ($zdarzenie in $j.hooks.PSObject.Properties) {
    foreach ($grupa in @($zdarzenie.Value)) {
      foreach ($h in @($grupa.hooks)) {
        if (-not $h) { continue }
        if ($h.PSObject.Properties.Name -notcontains "additionalContextLimit") { continue }
        $polecenie = "" + $h.command + " " + $h.commandWindows
        if ($polecenie -like "*$fragmentPolecenia*") { return [int]$h.additionalContextLimit }
      }
    }
  }
  return $null
}

function Ladunek-Hooka($plikJson) {
  # tresc, ktora hook naprawde wysyla (additionalContext z gotowego ladunku)
  $tekst = Czytaj-Cicho $plikJson
  if (-not $tekst) { return $null }
  try { $j = $tekst | ConvertFrom-Json } catch { return $null }
  if (-not $j.hookSpecificOutput) { return $null }
  $tresc = [string]$j.hookSpecificOutput.additionalContext
  if (-not $tresc) { return $null }
  return $tresc
}

function Znaki-W-Bajtach($tresc, $bajty) {
  # ile ZNAKOW miesci sie w podanej liczbie bajtow UTF-8 - sufit AGENTS.md jest
  # w bajtach, a naglowka szukamy w tekscie
  $enc = New-Object System.Text.UTF8Encoding($false)
  if ($enc.GetByteCount($tresc) -le $bajty) { return $tresc.Length }
  $lo = 0
  $hi = $tresc.Length
  while ($lo -lt $hi) {
    $sr = [int][math]::Floor(($lo + $hi + 1) / 2)
    if ($enc.GetByteCount($tresc.Substring(0, $sr)) -le $bajty) { $lo = $sr } else { $hi = $sr - 1 }
  }
  return $lo
}

function Pierwszy-Utracony-Naglowek($tresc, $limit, $jednostka) {
  # od ktorego naglowka zaczyna sie czesc, ktora przepada - zeby bylo widac,
  # CO konkretnie ginie, a nie tylko ile znakow
  if (-not $tresc) { return $null }
  $ciecie = $limit
  if ($jednostka -eq "bajtow") { $ciecie = Znaki-W-Bajtach $tresc $limit }
  if ($ciecie -ge $tresc.Length) { return $null }
  $m = [regex]::Match($tresc.Substring($ciecie), '(?m)^#{1,6}\s+.+$')
  if (-not $m.Success) { return $null }
  return $m.Value.Trim()
}

function Sufit($pola) {
  # Pola obowiazkowe: Nazwa, Krotka, Teraz, Limit, Jednostka, Czyj, SkadLimitu,
  # Plik, Skutek, Ucina. Nieobowiazkowe: Tresc, Uwaga, Informacyjny, Narzedzie
  # (Claude / Codex - czyj ladunek tnie ten sufit; puste = wspolny, np. Lore).
  # Teraz albo Limit rowne $null znacza "nie zmierzone" - i tak to wypisujemy.
  $s = [pscustomobject]$pola
  foreach ($k in @("Nazwa","Krotka","Teraz","Limit","Jednostka","Czyj","SkadLimitu",
                   "Plik","Skutek","Ucina","Tresc","Uwaga","Informacyjny","Narzedzie")) {
    if ($s.PSObject.Properties.Name -notcontains $k) {
      $s | Add-Member -NotePropertyName $k -NotePropertyValue $null
    }
  }
  $zmierzony = (($s.Teraz -ne $null) -and ($s.Limit -ne $null) -and ([int]$s.Limit -gt 0))
  $s | Add-Member -NotePropertyName "Zmierzony"    -NotePropertyValue $zmierzony
  $s | Add-Member -NotePropertyName "Procent"      -NotePropertyValue 0
  $s | Add-Member -NotePropertyName "Zapas"        -NotePropertyValue 0
  $s | Add-Member -NotePropertyName "Przekroczony" -NotePropertyValue $false
  $s | Add-Member -NotePropertyName "Strata"       -NotePropertyValue 0
  $s | Add-Member -NotePropertyName "Naglowek"     -NotePropertyValue $null
  if (-not $zmierzony -and -not $s.Uwaga) {
    # Niezmierzony sufit BEZ powodu wypisuje sie jako "nie zmierzone: " i nic
    # wiecej - czyli cisza w miejscu, w ktorym mial stac powod. Ten dopisek jest
    # po to, zeby zadna sciezka nie zostawila tej linii pustej.
    $b = @()
    if ($null -eq $s.Teraz) { $b += "nie ma czego mierzyc" }
    if ($null -eq $s.Limit) { $b += "nie umiem odczytac sufitu z $($s.SkadLimitu)" }
    elseif ([int]$s.Limit -le 0) { $b += "sufit odczytany z $($s.SkadLimitu) to $($s.Limit) - to nie jest zaden limit" }
    if ($b.Count -eq 0) { $b += "nie umiem powiedziec czego brakuje - to blad w tym skrypcie" }
    $s.Uwaga = ($b -join "; ")
  }
  if ($zmierzony) {
    $s.Procent = [int][math]::Round(100.0 * [double]$s.Teraz / [double]$s.Limit)
    $s.Zapas   = 100 - $s.Procent
    if ($s.Zapas -lt 0) { $s.Zapas = 0 }
    if ([long]$s.Teraz -gt [long]$s.Limit) {
      $s.Przekroczony = $true
      $s.Strata       = [long]$s.Teraz - [long]$s.Limit
      $s.Naglowek     = Pierwszy-Utracony-Naglowek $s.Tresc $s.Limit $s.Jednostka
    }
  }
  return $s
}

function Powod-Braku($teraz, $limit, $coMierzone, $skadLimitu) {
  $b = @()
  if ($teraz -eq $null) { $b += $coMierzone }
  if ($limit -eq $null) { $b += "nie umiem odczytac sufitu z $skadLimitu" }
  if ($b.Count -eq 0) { return $null }
  return ($b -join "; ")
}

function Sortuj-Sufity($lista) {
  # przekroczone i ciasne na GORZE - dolna czesc listy to ta, ktorej nikt nie czyta
  $klucze = @(
    @{ Expression = { if ($_.Informacyjny -or (-not $_.Zmierzony)) { 1 } else { 0 } } },
    @{ Expression = { if ($_.Zmierzony) { 0 - $_.Procent } else { 0 } } }
  )
  return @($lista | Sort-Object -Property $klucze)
}

# --- wypisanie: same sufity (jedno polecenie do odpalenia po zmianie zasad) ---
# Przechodzi po WSZYSTKICH parach (ladunek, sufit), ktore juz sa policzone wyzej -
# drugi raz tego nie liczymy. Kod wyjscia 1 przy jakimkolwiek przekroczeniu, zeby
# dalo sie to wpiac jako bramke. Sufitow z Lore tu nie ma: niczego nie ucinaja
# przed modelem, a zapytania do bazy trwaja.
# Tryb-Sufity wola koszt-pamieci.ps1 kropka (". Tryb-Sufity") i to on konczy
# skrypt kodem: 1, gdy cokolwiek jest ucinane ($cosUcinane z Etap-Ocena), inaczej 0.
function Tryb-Sufity {
  Write-Output "Sufity ladunkow - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
  foreach ($s in (Sortuj-Sufity $sufity)) {
    if (-not $s.Zmierzony) {
      Write-Output ("  ?     {0} - nie zmierzone: {1}" -f $s.Krotka, $s.Uwaga)
      continue
    }
    if ($s.Przekroczony -and $s.Ucina) {
      $opisU = "  UCINA {0} - {1} z {2} {3}, przepada {4}; sufit: {5}" -f `
               $s.Krotka, (Liczba $s.Teraz), (Liczba $s.Limit), $s.Jednostka, (Liczba $s.Strata), $s.SkadLimitu
      if ($s.Naglowek) { $opisU = $opisU + " (ginie od ""$(Skroc $s.Naglowek 40)"")" }
      Write-Output $opisU
    } elseif ($s.Przekroczony) {
      Write-Output ("  PROG  {0} - {1} z {2} {3}, ale ten sufit niczego nie ucina" -f `
                    $s.Krotka, (Liczba $s.Teraz), (Liczba $s.Limit), $s.Jednostka)
    } else {
      Write-Output ("  ok    {0} - {1} z {2} {3} ({4}% sufitu)" -f `
                    $s.Krotka, (Liczba $s.Teraz), (Liczba $s.Limit), $s.Jednostka, $s.Procent)
    }
  }
  if ($cosUcinane) {
    Write-Output "BLAD  cos jest ucinane po cichu - podnies limit we wskazanym pliku albo skroc tresc."
  } else {
    Write-Output "Nic nie jest ucinane."
  }
}

# Znacznik dla koszt-pamieci.ps1: ten plik wczytal sie do konca.
$script:ModulyKosztu["sufity"] = $true
