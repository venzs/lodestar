@echo off
rem Copies your Lodestar harvest file to the Desktop so you can send it on.
rem Double-click this, or pass the WoW folder as the first argument:
rem     collect-harvest.cmd "D:\Games\World of Warcraft"
rem Nothing is uploaded and nothing is deleted; it only copies.
setlocal enabledelayedexpansion

set "WOW=%~1"
if "%WOW%"=="" set "WOW=C:\Program Files (x86)\World of Warcraft"
set "BETA=%WOW%\_classic_beta_"
if not exist "%BETA%\WTF\Account" set "BETA=%WOW%\_retail_"
if not exist "%BETA%\WTF\Account" (
  echo Could not find WoW's WTF\Account folder under:
  echo   %WOW%
  echo.
  echo Pass your World of Warcraft folder as the first argument, e.g.
  echo   collect-harvest.cmd "D:\Games\World of Warcraft"
  pause
  exit /b 1
)

for /f "tokens=2 delims==" %%D in ('wmic os get localdatetime /value 2^>nul ^| find "="') do set "LDT=%%D"
set "STAMP=%LDT:~0,8%"
if "%STAMP%"=="" set "STAMP=undated"

set "DESK=%USERPROFILE%\Desktop"
if not exist "%DESK%" set "DESK=%USERPROFILE%"

set /a FOUND=0
for /d %%A in ("%BETA%\WTF\Account\*") do (
  set "SRC=%%~fA\SavedVariables\Lodestar_Guide.lua"
  if exist "!SRC!" (
    set "NAME=Lodestar-harvest-%USERNAME%-%%~nxA-%STAMP%.lua"
    set "NAME=!NAME:#=-!"
    copy /y "!SRC!" "%DESK%\!NAME!" >nul
    if errorlevel 1 (
      echo Could not copy !SRC!
    ) else (
      echo Copied to Desktop: !NAME!
      set /a FOUND+=1
    )
  )
)

echo.
if %FOUND%==0 (
  echo No Lodestar_Guide.lua found. Log in once with Lodestar installed, type /reload, then run this again.
) else (
  echo Done - %FOUND% file^(s^) on your Desktop. Send them on; that is all that is needed.
  echo Reminder: type /reload in game before quitting, or the last session is not saved.
)
pause
