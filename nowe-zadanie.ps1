# Zaklada izolowana kopie repo (git worktree) na jedno zadanie,
# wdraza do niej MegaRuchacza i otwiera w NOWYM oknie VS Code,
# ktore ma wlasny kolor paska i tytul - zeby nie pomylic go z glownym.
#
# Uzycie:  /rownolegle nazwa-zadania

param(
  [Parameter(Mandatory=$true)][string]$Nazwa,
  [string]$Repo = (Get-Location).Path
)

$Czysta = ($Nazwa -replace '[^a-zA-Z0-9\-_]', '-').Trim('-').ToLower()
if (-not $Czysta) { Write-Error "Podaj sensowna nazwe zadania"; exit 1 }
if (-not (Test-Path (Join-Path $Repo ".git"))) { Write-Error "$Repo nie jest repozytorium git"; exit 1 }

$Rodzic = Split-Path -Parent $Repo
$Folder = Join-Path $Rodzic "wt-$Czysta"

if (Test-Path $Folder) {
  Write-Host "Folder juz istnieje, otwieram go zamiast tworzyc nowy: $Folder" -ForegroundColor Yellow
} else {
  Write-Host "Tworze izolowana kopie: $Folder"
  git -C $Repo worktree add $Folder -b $Czysta
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Galaz istnieje - podpinam ja bez tworzenia nowej." -ForegroundColor Yellow
    git -C $Repo worktree add $Folder $Czysta
    if ($LASTEXITCODE -ne 0) { Write-Error "Nie udalo sie zalozyc worktree"; exit 1 }
  }
}

Write-Host ""
$wdroz = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "wdroz.ps1"
& powershell -ExecutionPolicy Bypass -File $wdroz $Folder

# Plik workspace lezy POZA repo, w katalogu nadrzednym - git go nie widzi,
# wiec kolory i tytul nie wejda zespolowi do commita.
$palet = @("#7c3aed", "#0e7490", "#b45309", "#be123c", "#15803d")
$suma = 0
foreach ($z in $Czysta.ToCharArray()) { $suma += [int]$z }
$tlo = $palet[$suma % $palet.Count]

$kolory = [ordered]@{
  "titleBar.activeBackground"   = $tlo
  "titleBar.inactiveBackground" = $tlo
  "titleBar.activeForeground"   = "#ffffff"
  "titleBar.inactiveForeground" = "#ffffff"
  "statusBar.background"        = $tlo
  "statusBar.foreground"        = "#ffffff"
  "activityBar.background"      = $tlo
}

$plikLog = Join-Path $Folder ".megaruchacz\worklog.md"

$zadania = [ordered]@{
  version = "2.0.0"
  tasks   = @(
    [ordered]@{
      label   = "1. Scal te galaz do glownej"
      type    = "shell"
      command = "git -C '$Repo' merge $Czysta"
      problemMatcher = @()
      presentation = [ordered]@{ reveal = "always"; panel = "new" }
    },
    [ordered]@{
      label   = "2. Usun ta kopie (po scaleniu)"
      type    = "shell"
      command = "git -C '$Repo' worktree remove '$Folder'; Remove-Item '$plikWsSciezka' -ErrorAction SilentlyContinue"
      problemMatcher = @()
      presentation = [ordered]@{ reveal = "always"; panel = "new" }
    },
    [ordered]@{
      label   = "3. Podglad rejestru workerow na zywo"
      type    = "shell"
      command = "Get-Content '$plikLog' -Wait -Tail 20"
      problemMatcher = @()
      isBackground = $true
      presentation = [ordered]@{ reveal = "always"; panel = "dedicated" }
    }
  )
}

$plikWs = Join-Path $Rodzic "wt-$Czysta.code-workspace"
$plikWsSciezka = $plikWs
$zadania.tasks[1].command = "git -C '$Repo' worktree remove '$Folder'; Remove-Item '$plikWs' -ErrorAction SilentlyContinue"
[ordered]@{
  folders  = @([ordered]@{ path = $Folder })
  settings = [ordered]@{
    "window.title"                  = "GALAZ $Czysta - kopia robocza"
    "workbench.colorCustomizations" = $kolory
  }
  tasks    = $zadania
} | ConvertTo-Json -Depth 8 | Out-File -FilePath $plikWs -Encoding utf8
Write-Host "OK  okno zadania: $plikWs (pasek $tlo)"

$plikGlowne = Join-Path $Rodzic "GLOWNE.code-workspace"
if (-not (Test-Path $plikGlowne)) {
  [ordered]@{
    folders  = @([ordered]@{ path = $Rodzic })
    settings = [ordered]@{
      "window.title"                  = "GLOWNE - tu scalasz"
      "workbench.colorCustomizations" = [ordered]@{
        "titleBar.activeBackground"   = "#1f2937"
        "titleBar.inactiveBackground" = "#1f2937"
        "titleBar.activeForeground"   = "#ffffff"
        "statusBar.background"        = "#1f2937"
        "statusBar.foreground"        = "#ffffff"
        "activityBar.background"      = "#1f2937"
      }
    }
  } | ConvertTo-Json -Depth 6 | Out-File -FilePath $plikGlowne -Encoding utf8
  Write-Host "OK  okno glowne: $plikGlowne (pasek ciemnoszary)"
}

Write-Host ""
Write-Host "Otwieram nowe okno VS Code..."
$code = Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\bin\code.cmd"
if (Test-Path $code) { & $code $plikWs } else { Start-Process "explorer.exe" $Rodzic }

Write-Host ""
Write-Host "GOTOWE. Nowe okno: kolorowy pasek, tytul 'GALAZ $Czysta'."
Write-Host "Glowne okno otwieraj przez GLOWNE.code-workspace - pasek ciemnoszary."
Write-Host ""
Write-Host "Po skonczeniu, w glownym oknie:"
Write-Host "  git -C `"$Repo`" merge $Czysta"
Write-Host "  git -C `"$Repo`" worktree remove `"$Folder`""
Write-Host "  Remove-Item `"$plikWs`""
