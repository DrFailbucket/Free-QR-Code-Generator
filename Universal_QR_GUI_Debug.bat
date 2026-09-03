@echo off
setlocal
cd /d "%~dp0"
title Universal QR-Code Generator v2.5 - Debug
set "UQRG_DEBUG=1"

echo ============================================================
echo  Universal QR-Code Generator v2.5 - DEBUG MODE
echo ============================================================
echo  QR payload contents are NOT printed to this console.
echo  Close the GUI when you are finished testing.
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0src\Universal_QR_GUI.ps1"
set "APP_EXIT=%ERRORLEVEL%"

echo.
if not "%APP_EXIT%"=="0" (
    echo [DEBUG] Application exited with error code %APP_EXIT%.
)
echo.
pause
exit /b %APP_EXIT%
