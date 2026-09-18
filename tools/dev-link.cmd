@echo off
rem Links every Lodestar addon folder from this repo into the WoW: Forever beta AddOns folder
rem with NTFS junctions, so edits in the repo show up in game after /reload.
rem Usage: double-click, or  dev-link.cmd "D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns"
setlocal
set "REPO=%~dp0.."
set "ADDONS=%~1"
if "%ADDONS%"=="" set "ADDONS=C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns"
if not exist "%ADDONS%" (
  echo AddOns folder not found: "%ADDONS%"
  echo Pass the path as the first argument.
  pause
  exit /b 1
)
for %%M in (Lodestar Lodestar_Leveling Lodestar_Economy Lodestar_UI Lodestar_Guild) do (
  if exist "%ADDONS%\%%M" (
    echo already present: "%ADDONS%\%%M"  ^(delete it first if it is a plain copy^)
  ) else (
    mklink /J "%ADDONS%\%%M" "%REPO%\%%M"
  )
)
echo.
echo Done. In game: /reload, then /lode
pause
