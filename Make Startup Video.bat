@echo off
title FK8 Startup Video Maker
rem Double-click this file, or drag a video onto it.
if not exist "%~dp0convert.ps1" goto notunzipped
if not exist "%~dp0gui.ps1" goto notunzipped
if "%~1"=="" goto nofile
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0gui.ps1" -Mode startup -InputFile "%~1"
exit /b

:nofile
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0gui.ps1" -Mode startup
exit /b

:notunzipped
echo.
echo   This tool has to be unzipped before it will run.
echo.
echo   1. Close this window.
echo   2. Right-click the zip file you downloaded and choose "Extract All".
echo   3. Open the new folder and double-click this file again.
echo.
pause
