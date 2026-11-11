@echo off
rem Dotabata! - compile le jeu en un seul exe : godot\build\windows\Dotabata.exe
rem Ensuite, lancer.cmd lance cet exe (et c'est le seul fichier a copier sur les PC des joueurs).
chcp 65001 >nul
setlocal
cd /d "%~dp0"

rem --- Godot 4.7 : dans le PATH, sinon l'installation winget ---
rem La version console d'abord : godot.exe (fenetree) n'ecrit rien dans la console,
rem ni sa version ni les messages d'erreur de l'export.
set "GODOT="
for /f "delims=" %%G in ('where godot_console 2^>nul') do if not defined GODOT set "GODOT=%%G"
if not defined GODOT (
  for /f "delims=" %%G in ('dir /b /s "%LOCALAPPDATA%\Microsoft\WinGet\Packages\Godot_v4*_win64_console.exe" 2^>nul') do if not defined GODOT set "GODOT=%%G"
)
if not defined GODOT (
  for /f "delims=" %%G in ('where godot 2^>nul') do if not defined GODOT set "GODOT=%%G"
)
if not defined GODOT (
  echo Godot 4.7 est introuvable. Installe-le avec :
  echo   winget install GodotEngine.GodotEngine
  pause
  exit /b 1
)

rem --- modeles d'export de la version de Godot installee : telecharges une fois si besoin ---
set "TPL_ARGS="
rem compilation automatique (GitHub Actions) : pas de question, on telecharge directement
if defined CI set "TPL_ARGS=%TPL_ARGS% -Yes"
powershell -NoProfile -ExecutionPolicy Bypass -File godot\tools\install-templates.ps1 -Godot "%GODOT%" %TPL_ARGS%
if errorlevel 2 (
  echo Compilation annulee : les modeles d'export sont necessaires.
  pause
  exit /b 1
)
if errorlevel 1 (
  pause
  exit /b 1
)

rem --- l'exe ne peut pas etre remplace pendant qu'il tourne ---
tasklist /fi "imagename eq Dotabata.exe" 2>nul | "%SystemRoot%\System32\find.exe" /i "Dotabata.exe" >nul
if not errorlevel 1 (
  echo Le jeu est ouvert : ferme Dotabata! puis relance compiler.cmd.
  pause
  exit /b 1
)

echo Godot : %GODOT%
echo.
echo [1/2] Import des ressources...
"%GODOT%" --headless --path godot --import >nul 2>&1

echo [2/2] Compilation de godot\build\windows\Dotabata.exe...
if not exist godot\build\windows mkdir godot\build\windows
"%GODOT%" --headless --path godot --export-release "Windows Desktop" build/windows/Dotabata.exe
if errorlevel 1 goto :fail
if not exist godot\build\windows\Dotabata.exe goto :fail

echo.
echo Termine : godot\build\windows\Dotabata.exe
echo Lance le jeu avec lancer.cmd.
endlocal
exit /b 0

:fail
echo.
echo La compilation a echoue (voir les messages ci-dessus).
pause
exit /b 1
