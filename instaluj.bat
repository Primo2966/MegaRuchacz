@echo off
rem MegaRuchacz - instalator. Dwuklik otwiera okno instalatora (instalator\okno.ps1).
rem Cala robota jest w Zainstaluj-MegaRuchacza.bat obok - ten plik zostal pod stara nazwa,
rem bo wskazuja go instrukcje i okno instalatora ("uruchom instaluj.bat jeszcze raz").
rem Sam, bez reszty folderu MegaRuchacza, nic nie zrobi - wtedy mowi, skad wziac wlasciwy plik.
rem Ten plik ma zostac czystym ASCII z koncami linii CRLF.
if exist "%~dp0Zainstaluj-MegaRuchacza.bat" goto uruchom
echo.
echo  Ten plik dziala tylko w folderze MegaRuchacza.
echo  Do instalacji pobierz jeden plik Zainstaluj-MegaRuchacza.bat:
echo  https://github.com/Primo2966/MegaRuchacz/releases/download/instalator/Zainstaluj-MegaRuchacza.bat
echo.
pause
exit /b 1

:uruchom
call "%~dp0Zainstaluj-MegaRuchacza.bat" %*
exit /b %ERRORLEVEL%
