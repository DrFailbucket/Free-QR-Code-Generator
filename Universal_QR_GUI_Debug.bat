@echo off
setlocal
cd /d "%~dp0"
title Universal QR-Code Generator WPF v2 - Debug
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0src\Universal_QR_GUI.ps1"
if errorlevel 1 (
    echo.
    echo Die Anwendung wurde mit einem Fehler beendet.
    echo.
    pause
)
endlocal
