@echo off
title Kill-Metraj Simple Launcher
echo ==============================================
echo   KILL-METRAJ ULTRA SIMPLE LAUNCHER
echo ==============================================
echo.

taskkill /F /IM node.exe >nul 2>nul

set "ROOT=%CD%"
set "PORTABLE_NODE=%ROOT%\.portable-node\node-v20.14.0-win-x64"

:: Find NPM
set "NPM_EXEC=npm"
if exist "%PORTABLE_NODE%\npm.cmd" (
    set "NPM_EXEC=%PORTABLE_NODE%\npm.cmd"
    set "PATH=%PORTABLE_NODE%;%PATH%"
)

echo [*] Starting Backend...
(
    echo @echo off
    echo title Backend (5001)
    echo set "PATH=%%PATH%%"
    echo cd /d "%ROOT%\backend"
    echo set USE_SQLITE=true
    echo set PORT=5001
    echo call "%NPM_EXEC%" run dev
    echo pause
) > "%TEMP%\start_back.bat"
start "Backend (5001)" cmd /k "%TEMP%\start_back.bat"

echo [*] Starting Frontend...
(
    echo @echo off
    echo title Frontend (5174)
    echo set "PATH=%%PATH%%"
    echo cd /d "%ROOT%\frontend"
    echo call "%NPM_EXEC%" run dev
    echo pause
) > "%TEMP%\start_front.bat"
start "Frontend (5174)" cmd /k "%TEMP%\start_front.bat"

echo [*] Waiting 8 seconds...
timeout /t 8 /nobreak >nul

echo [*] Opening site...
start http://127.0.0.1:5174

echo ==============================================
echo   Site should be open now!
echo ==============================================
pause
