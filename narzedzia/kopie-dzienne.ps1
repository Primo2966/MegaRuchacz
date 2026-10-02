# Kopie dzienne plikow pamieci: "wczoraj" i "przedwczoraj" w ~\.claude\mr\kopie-dzienne\.
#
# Po co: 2026-10-02 zanik pradu zaraz po porannym cyklu wiedzy wyzerowal CLAUDE.md i jedenascie
# plikow w wiedza\ (patrz naglowek narzedzia\zapis-trwaly.ps1). Kopie, ktore robil sam cykl,
# padly razem z nimi - powstaly w tej samej sekundzie. Dlatego te kopie robimy RAZ DZIENNIE,
# PRZED cyklem (wola nas cykl-dzienny.ps1 na samym poczatku), z plikow, ktore przezyly noc.
#
# Zasady:
#   - kopia powstaje WYLACZNIE ze zdrowych plikow (bez bajtow 0x00). Gdy ktorykolwiek plik
#     pamieci ma zera, rotacja staje w miejscu, kopie zostaja nietkniete, a skrypt konczy sie
#     kodem 2 z alarmem - cykl-dzienny.ps1 wtedy nie rusza, straznik i okno nadzorcy alarmuja,
#   - rotacja: przedwczoraj <- wczoraj <- biezace, najwyzej raz na dobe (.ostatnia-rotacja),
#   - "wczoraj" z zerami (np. padla sama rotacja) nie wypycha zdrowego "przedwczoraj" - idzie
#     na bok jako uszkodzona-<stempel>\, a przedwczorajsza zostaje.
#
# Co jest w kopii: ~\.claude\CLAUDE.md, ~\.codex\AGENTS.md, ~\.config\opencode\AGENTS.md
# i pliki tekstowe z wierzchu ~\.claude\wiedza\ (razem z plikami stanu) - w tym samym ukladzie
# katalogow co w katalogu domowym, wiec przywrocenie to zwykle skopiowanie z powrotem.
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File narzedzia\kopie-dzienne.ps1 -Przywroc
#       przywraca WYZEROWANE pliki z najnowszej zdrowej kopii (wczoraj, a gdy ta nie ma
#       zdrowego pliku - przedwczoraj). Obecny stan idzie najpierw do przed-przywroceniem-<stempel>\.
#   ... -Przywroc -Plik CLAUDE.md [-Skad przedwczoraj]
#       przywraca wskazany plik (nazwa albo sciezka wzgledem katalogu domowego, np.
#       .claude\wiedza\zrodla.md; "wszystko" = caly komplet), takze zdrowy
#   ... -Stan        jakie kopie sa, z kiedy i czy sa zdrowe
#   ... -Rotuj       rotacja (wola ja cykl-dzienny.ps1); -Proba = tylko plan
#   ... -KatalogDomowy <kat>   podmiana katalogu domowego (testy)
# Kody wyjscia: 0 = w porzadku, 2 = wyzerowane pliki pamieci (alarm), 1 = inny blad.

param(
  [string]$KatalogDomowy = $HOME,
  [string]$Zrodlo = (Split-Path -Parent $PSScriptRoot),
  [switch]$Rotuj,
  [switch]$Przywroc,
  [switch]$Stan,
  [string]$Plik = "",
  [ValidateSet("", "wczoraj", "przedwczoraj")]
  [string]$Skad = "",
  [switch]$Proba
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "zapis-trwaly.ps1")

$Dom    = (Resolve-Path -LiteralPath $KatalogDomowy).Path
$Baza   = Join-Path $Dom ".claude\mr\kopie-dzienne"
$Sloty  = @("wczoraj", "przedwczoraj")
$PlikRotacji = Join-Path $Baza ".ostatnia-rotacja"
$Stempel = Get-Date -Format "yyyyMMdd-HHmmss"

function Pliki-Slotu([string]$slot) {
  $kat = Join-Path $Baza $slot
  if (-not (Test-Path -LiteralPath $kat)) { return ,@() }
  return ,@(Get-ChildItem -LiteralPath $kat -Recurse -File -Force | Where-Object { $_.Name -ne ".kiedy" } |
            ForEach-Object { $_.FullName.Substring($kat.Length + 1) })
}

function Kiedy-Slot([string]$slot) {
  $p = Join-Path $Baza "$slot\.kiedy"
  if (Test-Path -LiteralPath $p) { return ([System.IO.File]::ReadAllText($p)).Trim() }
  return "nie wiadomo kiedy"
}

function Slot-Ma-Zera([string]$slot) {
  foreach ($w in (Pliki-Slotu $slot)) { if (Ma-Zera (Join-Path $Baza "$slot\$w")) { return $true } }
  return $false
}

# ------------------------------------------------------------------ rotacja

function Wykonaj-Rotacje {
  $wyz = Wyzerowane-Pliki $Dom
  if ($wyz.Count -gt 0) {
    Write-Output (Opis-Wyzerowanych $wyz $Dom $Zrodlo)
    Write-Output "kopie dzienne: rotacja wstrzymana - kopie wczoraj/przedwczoraj zostaja nietkniete"
    exit 2
  }
  $dzis = Get-Date -Format "yyyy-MM-dd"
  if ((Test-Path -LiteralPath $PlikRotacji) -and (([System.IO.File]::ReadAllText($PlikRotacji)).Trim() -eq $dzis)) {
    Write-Output "kopie dzienne: dzisiejsza juz jest ($(Kiedy-Slot 'wczoraj'))"
    exit 0
  }
  $pliki = Pliki-Pamieci $Dom
  if ($Proba) {
    Write-Output "kopie dzienne [proba]: skopiowalbym $($pliki.Count) plikow do $Baza\wczoraj (obecna 'wczoraj' -> 'przedwczoraj')"
    exit 0
  }
  New-Item -ItemType Directory -Force -Path $Baza | Out-Null
  # niedokonczona rotacja sprzed zaniku pradu - to tylko czesciowa kopia, nic w niej nie ma
  foreach ($stara in @(Get-ChildItem -LiteralPath $Baza -Directory -Force -Filter ".nowa-*")) {
    Remove-Item -LiteralPath $stara.FullName -Recurse -Force
  }
  $nowa = Join-Path $Baza ".nowa-$Stempel"
  foreach ($p in $pliki) {
    $wzgl = Sciezka-Wzgledna $Dom $p
    Kopiuj-Trwale $p (Join-Path $nowa $wzgl)
  }
  Zapisz-Trwale (Join-Path $nowa ".kiedy") ((Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "`r`n")
  $wcz = Join-Path $Baza "wczoraj"
  $prz = Join-Path $Baza "przedwczoraj"
  $notka = ""
  if (Test-Path -LiteralPath $wcz) {
    if (Slot-Ma-Zera "wczoraj") {
      Move-Item -LiteralPath $wcz -Destination (Join-Path $Baza "uszkodzona-$Stempel")
      $notka = " UWAGA: dotychczasowa 'wczoraj' miala bajty 0x00 - odlozona jako uszkodzona-$Stempel, 'przedwczoraj' zostaje stara."
    } else {
      if (Test-Path -LiteralPath $prz) { Remove-Item -LiteralPath $prz -Recurse -Force }
      Move-Item -LiteralPath $wcz -Destination $prz
    }
  }
  Move-Item -LiteralPath $nowa -Destination $wcz
  Zapisz-Trwale $PlikRotacji ($dzis + "`r`n")
  Write-Output "kopie dzienne: $($pliki.Count) plikow pamieci skopiowane do $wcz$notka"
  exit 0
}

# ------------------------------------------------------------------ przywracanie

function Rozpoznaj-Pliki {
  if (-not $Plik) {
    return ,@((Wyzerowane-Pliki $Dom) | ForEach-Object { Sciezka-Wzgledna $Dom $_.Sciezka })
  }
  $wszystkie = @()
  foreach ($s in $Sloty) { $wszystkie += (Pliki-Slotu $s) }
  $wszystkie = @($wszystkie | Sort-Object -Unique)
  if ($Plik -eq "wszystko") { return ,$wszystkie }
  $szukany = $Plik.Replace('/', '\').TrimStart('\')
  if ($szukany.Contains('\')) { return ,@($wszystkie | Where-Object { $_ -ieq $szukany }) }
  $pasuje = @($wszystkie | Where-Object { (Split-Path -Leaf $_) -ieq $szukany })
  if ($pasuje.Count -gt 1) {
    Write-Output "BLAD: nazwa $Plik pasuje do kilku plikow: $($pasuje -join ', ') - podaj sciezke wzgledna."
    exit 1
  }
  return ,$pasuje
}

function Wykonaj-Przywrocenie {
  $cele = Rozpoznaj-Pliki
  if ($cele.Count -eq 0) {
    if ($Plik) { Write-Output "BLAD: w kopiach dziennych nie ma pliku '$Plik' (zobacz: -Stan)"; exit 1 }
    Write-Output "Zaden plik pamieci nie jest wyzerowany - nie ma czego przywracac. Konkretny plik: -Przywroc -Plik CLAUDE.md"
    exit 0
  }
  $bledy = 0
  $odlozone = Join-Path $Baza "przed-przywroceniem-$Stempel"
  foreach ($wzgl in $cele) {
    $zKopii = if ($Skad) { @($Skad) } else { $Sloty }
    $zrodlowy = $null
    foreach ($s in $zKopii) {
      $k = Join-Path $Baza "$s\$wzgl"
      $i = Pierwsze-Zero $k
      if (($null -ne $i) -and ($i -lt 0)) { $zrodlowy = $k; $slotZ = $s; break }
    }
    if (-not $zrodlowy) {
      Write-Output "BLAD: $wzgl - w kopiach ($($zKopii -join ', ')) nie ma jego zdrowej wersji"
      $bledy++
      continue
    }
    $cel = Join-Path $Dom $wzgl
    if ($Proba) { Write-Output "[proba] $wzgl <- $slotZ ($(Kiedy-Slot $slotZ))"; continue }
    if (Test-Path -LiteralPath $cel) {
      # obecny stan zostaje jako dowod - takze wyzerowany (to nie jest kopia do odtwarzania)
      $dowod = Join-Path $odlozone $wzgl
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dowod) | Out-Null
      Copy-Item -LiteralPath $cel -Destination $dowod -Force
    }
    Kopiuj-Trwale $zrodlowy $cel
    Write-Output "PRZYWROCONY $wzgl <- kopia '$slotZ' z $(Kiedy-Slot $slotZ)"
  }
  if (-not $Proba -and (Test-Path -LiteralPath $odlozone)) { Write-Output "stan sprzed przywrocenia: $odlozone" }
  Write-Output "Uwaga: przywrocony plik ma stan z chwili kopii - fakty dopisane pozniej odtworzy kolejny cykl wiedzy, gdy przeczyta rozmowy jeszcze raz."
  if ($bledy -gt 0) { exit 1 }
  exit 0
}

# ------------------------------------------------------------------ stan

function Pokaz-Stan {
  foreach ($s in $Sloty) {
    $pliki = Pliki-Slotu $s
    if ($pliki.Count -eq 0) { Write-Output "${s}: brak"; continue }
    $zdrowa = if (Slot-Ma-Zera $s) { "MA BAJTY 0x00" } else { "zdrowa" }
    Write-Output "${s}: $(Kiedy-Slot $s), $($pliki.Count) plikow, $zdrowa"
  }
  $wyz = Wyzerowane-Pliki $Dom
  if ($wyz.Count -gt 0) { Write-Output (Opis-Wyzerowanych $wyz $Dom $Zrodlo); exit 2 }
  Write-Output "obecne pliki pamieci: bez zer"
  exit 0
}

if ($Rotuj)    { Wykonaj-Rotacje }
if ($Przywroc) { Wykonaj-Przywrocenie }
Pokaz-Stan
