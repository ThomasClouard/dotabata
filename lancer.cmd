@echo off
rem Dotabata! - lance le jeu. Un seul programme : depuis le menu, chacun peut creer une partie
rem ou rejoindre celles du reseau local.
rem   lancer.cmd                    menu principal
rem   lancer.cmd --host --bots=5    cree directement une partie et la remplit de bots
rem Les options sont passees au jeu (voir godot/README.md).
rem L'exe se fabrique avec compiler.cmd ; sans lui, le jeu est lance depuis les sources avec Godot.
chcp 65001 >nul
setlocal
cd /d "%~dp0"

if exist godot\build\windows\Dotabata.exe (
  start "" godot\build\windows\Dotabata.exe -- %*
  goto :done
)

rem --- Godot 4.7 : dans le PATH, sinon l'installation winget ---
set "GODOT="
for /f "delims=" %%G in ('where godot 2^>nul') do if not defined GODOT set "GODOT=%%G"
if not defined GODOT (
  for /f "delims=" %%G in ('dir /b /s "%LOCALAPPDATA%\Microsoft\WinGet\Packages\Godot_v4*_win64.exe" 2^>nul') do if not defined GODOT set "GODOT=%%G"
)
if defined GODOT (
  echo Pas d'exe compile ^(compiler.cmd^) : lancement du jeu depuis les sources...
  start "" "%GODOT%" --path godot -- %*
  goto :done
)
echo Ni l'exe compile (godot\build\windows\Dotabata.exe) ni Godot 4.7 ne sont installes.
echo Installe Godot : winget install GodotEngine.GodotEngine
echo puis compile le jeu avec compiler.cmd.
pause
exit /b 1

:done
endlocal
