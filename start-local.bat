@echo off
title Dubber Local Server + Phone Bridge
echo ============================================
echo   DUBBER LOCAL SERVER + PHONE USB BRIDGE
echo ============================================
echo.

REM Start the Dubber backend on this PC (port 8000)
echo [1/2] Starting local Dubber server on http://localhost:8000 ...
start "Dubber Server" cmd /k "cd /d %~dp0 && python -m uvicorn server.main:app --host 0.0.0.0 --port 8000"

REM Wait for server to boot
timeout /t 4 /nobreak >nul

REM Keep the USB bridge alive: re-apply adb reverse whenever the phone reconnects
echo [2/2] Keeping phone USB bridge alive (adb reverse tcp:8000)...
echo       Plug/unplug your phone freely - this window will re-bridge it.
echo.
:loop
for /f "tokens=1,2" %%a in ('D:\Android\Sdk\platform-tools\adb devices ^| findstr /v "List" ^| findstr "device"') do (
    if "%%b"=="device" (
        D:\Android\Sdk\platform-tools\adb -s %%a reverse tcp:8000 tcp:8000 >nul 2>&1
        echo     [OK] Phone %%a bridged - app can reach the server.
    )
)
timeout /t 3 /nobreak >nul
goto loop
