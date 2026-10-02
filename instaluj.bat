@echo off
rem MegaRuchacz - instalator. Dwuklik otwiera okno instalatora (instalator\okno.ps1).
rem
rem W folderze MegaRuchacza (obok lezy instalator\okno.ps1) od razu otwiera okno.
rem Sam (np. pobrany z GitHuba bez reszty plikow) najpierw pobiera MegaRuchacza - ZIP z GitHuba,
rem ok. 1 MB - do folderu tymczasowego i otwiera okno stamtad: okno zapyta, gdzie zainstalowac,
rem zdobedzie gita i sklonuje repozytorium (klon jest potrzebny do aktualizacji).
rem
rem Okno startuje przez "conhost.exe --headless": PowerShell nie dostaje zadnej widocznej konsoli,
rem wiec nic nie mignie - takze tam, gdzie domyslnym terminalem jest Windows Terminal (jego okna
rem -WindowStyle Hidden nie chowa). Ta konsola czeka, az okno zostawi znacznik "stoje", i znika.
rem Zostaje tylko przy bledzie, z powodem do przeczytania.
rem
rem MR_ZIP_URL (zmienna srodowiskowa) podmienia adres ZIP-a - do testow i forkow.
rem Ten plik ma zostac czystym ASCII z koncami linii CRLF: cmd.exe z samym LF potrafi nie
rem znalezc etykiety przy goto.
setlocal
set "OKNO=%~dp0instalator\okno.ps1"
set "ROBOCZY=%TEMP%\MegaRuchacz-instalator"
set "ZNACZNIK=%ROBOCZY%\okno-wstalo.txt"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%ROBOCZY%" mkdir "%ROBOCZY%"
if exist "%OKNO%" goto uruchom

if not defined MR_ZIP_URL set "MR_ZIP_URL=https://github.com/Primo2966/MegaRuchacz/archive/refs/heads/main.zip"
set "ZIP=%ROBOCZY%\MegaRuchacz.zip"
set "ROZPAK=%ROBOCZY%\rozpakowany"
echo.
echo  MegaRuchacz - pobieram instalator z GitHuba (ok. 1 MB)...
if exist "%ROZPAK%" rmdir /s /q "%ROZPAK%"
if exist "%ZIP%" del /q "%ZIP%"
rem curl i tar z System32 (Windows 10 1803+), a nie z PATH: tar z Git Basha nie rozpakuje ZIP-a.
"%SystemRoot%\System32\curl.exe" -fsSL --retry 2 -o "%ZIP%" "%MR_ZIP_URL%"
if errorlevel 1 goto pobierz_ps
goto rozpakuj

:pobierz_ps
echo  curl nie zadzialal - probuje przez PowerShell...
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-WebRequest -UseBasicParsing -Uri $env:MR_ZIP_URL -OutFile $env:ZIP"
if errorlevel 1 goto blad_pobrania

:rozpakuj
mkdir "%ROZPAK%"
"%SystemRoot%\System32\tar.exe" -xf "%ZIP%" -C "%ROZPAK%"
if errorlevel 1 goto rozpakuj_ps
goto znajdz

:rozpakuj_ps
"%PS%" -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath $env:ZIP -DestinationPath $env:ROZPAK -Force"
if errorlevel 1 goto blad_rozpakowania

:znajdz
rem ZIP z GitHuba ma w srodku jeden folder (MegaRuchacz-main).
set "OKNO="
for /d %%D in ("%ROZPAK%\*") do if exist "%%~fD\instalator\okno.ps1" set "OKNO=%%~fD\instalator\okno.ps1"
if not defined OKNO goto blad_zawartosci

:uruchom
if exist "%ZNACZNIK%" del /q "%ZNACZNIK%"
start "" "%SystemRoot%\System32\conhost.exe" --headless "%PS%" -NoProfile -ExecutionPolicy Bypass -File "%OKNO%" -Znacznik "%ZNACZNIK%" %*
set /a PROBY=0

:czekaj
if exist "%ZNACZNIK%" goto stoi
set /a PROBY+=1
if %PROBY% GEQ 30 goto nie_wstalo
ping -n 2 127.0.0.1 >nul
goto czekaj

:stoi
findstr /b /c:"ODMOWA" "%ZNACZNIK%" >nul
if errorlevel 1 goto koniec
echo.
echo  Instalator MegaRuchacza nie wystartowal. Powod:
"%PS%" -NoProfile -Command "Get-Content -LiteralPath $env:ZNACZNIK -Encoding UTF8"
echo.
pause
goto koniec

:nie_wstalo
echo.
echo  Okno instalatora nie pojawilo sie w ciagu 30 sekund.
echo  Uruchamiam je jeszcze raz w tym oknie, zeby bylo widac, co poszlo nie tak:
echo.
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%OKNO%" -Znacznik "%ZNACZNIK%" %*
echo.
pause
goto koniec

:blad_pobrania
echo.
echo  Nie udalo sie pobrac MegaRuchacza z GitHuba.
echo  Sprawdz polaczenie z internetem i uruchom instaluj.bat jeszcze raz.
echo.
pause
goto koniec

:blad_rozpakowania
echo.
echo  Pobralem plik, ale nie udalo sie go rozpakowac. Uruchom instaluj.bat jeszcze raz.
echo.
pause
goto koniec

:blad_zawartosci
echo.
echo  W pobranym pliku nie ma instalatora (instalator\okno.ps1) - wersja na GitHubie
echo  jest starsza niz ten plik instaluj.bat. Sprobuj pozniej albo daj znac autorowi.
echo.
pause
goto koniec

:koniec
endlocal
exit /b 0
