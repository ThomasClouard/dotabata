@echo off
rem Dotabata! - lance le jeu. Un seul programme : depuis l'accueil, chacun peut creer un serveur
rem ou rejoindre ceux du reseau local.
rem   lancer.cmd                    accueil (liste des serveurs, creation d'un serveur)
rem   lancer.cmd --host --bots=5    cree directement un serveur et le remplit de bots
rem Les options sont passees au jeu (voir godot/README.md).
chcp 65001 >nul
setlocal
cd /d "%~dp0"

if exist godot\build\windows\Dotabata.exe (
  start "" godot\build\windows\Dotabata.exe -- %*
  goto :done
)
where godot >nul 2>nul && (
  echo Lancement du jeu depuis les sources...
  start "" godot --path godot -- %*
  goto :done
)
echo Ni l'exe exporte (godot\build\windows\Dotabata.exe) ni Godot 4.7 ne sont installes.
echo Installe Godot : winget install GodotEngine.GodotEngine
pause
exit /b 1

:done
endlocal
