# Sufity ladunkow hookow - JEDNO miejsce dla instalatora i straznika.
# Dot-source'uja ten plik wdroz.ps1 (przy wdrozeniu) i straznik-zasad.ps1 (przy
# samoaktualizacji). Osobne kopie tego samego komunikatu rozjechalyby sie przy
# pierwszej poprawce, a model dostawalby raz jedno brzmienie, raz drugie.
#
# Hook wstrzykuje modelowi tresc z pola hookSpecificOutput.additionalContext.
# Gdy jest dluzsza niz additionalContextLimit, narzedzie ucina KONIEC i nie mowi
# o tym ani slowa - przez tydzien szly tak do Codeksa kadlubki zasad, a instalator
# meldowal sukces. Od teraz kazde miejsce, w ktorym cos moze zostac uciete, albo
# temu zapobiega, albo krzyczy.
#
# Mierzymy dokladnie to, czego dotyczy sufit: ZNAKI samej tresci additionalContext,
# bez otoczki JSON-a - tak samo liczy narzedzia\koszt-pamieci.ps1 (Ladunek-Hooka),
# zeby obie liczby zawsze mowily to samo.

# Ostrzezenie z poprzedniego przebiegu - rozpoznajemy je, zeby nie wliczac go do
# pomiaru i nie zostawiac w pliku, ktory juz sie miesci.
$OstrzezenieUciecia = '^UWAGA: ten tekst ma \d+ znakow, a zmiesci sie \d+[^\r\n]*\r?\n'

function Ostrzezenie-O-Ucieciu($znakow, $limit) {
  # Ucinany jest KONIEC, wiec jedyne miejsce, ktore na pewno dojdzie do modelu,
  # to pierwsza linia. Alarm ma stac tam i nigdzie indziej.
  return "UWAGA: ten tekst ma $znakow znakow, a zmiesci sie $limit - koniec zostal uciety. " +
         "Powiedz o tym uzytkownikowi i nie zakladaj, ze znasz cale zasady.`n"
}

# additionalContextLimit hooka rozpoznanego po pliku, ktory ten hook wczytuje.
# Czytamy z konfiguracji, ktora NAPRAWDE lezy w projekcie - cudzy hooks.json moze
# miec nasza grupe z innym limitem i to on rzadzi, nie szablon ani kopia w pamieci.
function Limit-Ladunku($plikKonfiguracji, $fragmentPolecenia) {
  if (-not $plikKonfiguracji -or -not (Test-Path $plikKonfiguracji)) { return $null }
  try { $j = ([System.IO.File]::ReadAllText($plikKonfiguracji, [System.Text.Encoding]::UTF8)).TrimStart([char]0xFEFF) | ConvertFrom-Json } catch { return $null }
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

# Porownuje ladunek z sufitem jego hooka. Przy $naprawiaj = $true dopisuje
# ostrzezenie na POCZATEK wstrzykiwanej tresci (i zdejmuje je, gdy ladunek znow
# sie miesci). Samo sprawdzenie niczego nie zapisuje.
function Pilnuj-Sufitu($plikLadunku, $plikKonfiguracji, $fragmentPolecenia, $skadLimitu, $opis, $naprawiaj) {
  $w = [pscustomobject]@{ Opis = $opis; Plik = $plikLadunku; Znaki = $null; Limit = $null;
                          SkadLimitu = $skadLimitu; Przekroczony = $false; Zmierzony = $false; Czemu = "" }
  if (-not (Test-Path $plikLadunku)) { $w.Czemu = "nie ma pliku $plikLadunku"; return $w }
  $surowy = $null
  try { $surowy = ([System.IO.File]::ReadAllText($plikLadunku, [System.Text.Encoding]::UTF8)).TrimStart([char]0xFEFF) } catch { }
  if (-not $surowy) { $w.Czemu = "nie da sie odczytac $plikLadunku"; return $w }
  $j = $null
  try { $j = $surowy | ConvertFrom-Json } catch { $w.Czemu = "$plikLadunku nie jest poprawnym JSON-em"; return $w }
  if (-not $j.hookSpecificOutput -or -not $j.hookSpecificOutput.additionalContext) {
    $w.Czemu = "w $plikLadunku nie ma hookSpecificOutput.additionalContext"
    return $w
  }
  $tresc  = [string]$j.hookSpecificOutput.additionalContext
  $czysta = [regex]::Replace($tresc, $OstrzezenieUciecia, "")
  $w.Znaki = $czysta.Length
  $w.Limit = Limit-Ladunku $plikKonfiguracji $fragmentPolecenia
  if ($null -eq $w.Limit -or $w.Limit -le 0) {
    $w.Czemu = "w $skadLimitu nie ma additionalContextLimit przy hooku od $fragmentPolecenia - nie wiem, gdzie stoi sufit"
    return $w
  }
  $w.Zmierzony    = $true
  $w.Przekroczony = ($w.Znaki -gt $w.Limit)
  $docelowa = $czysta
  if ($w.Przekroczony) { $docelowa = (Ostrzezenie-O-Ucieciu $w.Znaki $w.Limit) + $czysta }
  # Odczyt MUSI byc jawnie w UTF-8 (wyzej): Get-Content -Raw w PowerShell 5.1
  # czyta w ANSI, wiec polskie znaki wracaja jako krzaki, zapis je utrwala,
  # a plik rosnie przy kazdym przebiegu. Sprawdzone 2026-09-17: 13763 -> 15415.
  if ($naprawiaj -and $docelowa -ne $tresc) {
    $j.hookSpecificOutput.additionalContext = $docelowa
    [System.IO.File]::WriteAllText($plikLadunku, ($j | ConvertTo-Json -Depth 5 -Compress),
                                   (New-Object System.Text.UTF8Encoding($false)))
  }
  return $w
}
