@echo off
setlocal enabledelayedexpansion
title Kill-Metraj Simple Launcher
echo ==============================================
echo   KILL-METRAJ ULTRA SIMPLE LAUNCHER
echo ==============================================
echo.

taskkill /F /IM node.exe >nul 2>nul

set "ROOT=%~dp0"
if "!ROOT:~-1!"=="\" set "ROOT=!ROOT:~0,-1!"

set "PNODE=!ROOT!\.portable-node\node-v20.14.0-win-x64"

:: Find NPM
set "NPM_EXEC=npm"
if exist "!PNODE!\npm.cmd" (
    set "NPM_EXEC=!PNODE!\npm.cmd"
    set "PATH=!PNODE!;!PATH!"
    echo [OK] Portable Node.js found
)

:: Install deps if missing
if not exist "!ROOT!\backend\node_modules\express" (
    echo [*] Installing backend packages...
    pushd "!ROOT!\backend"
    call "!NPM_EXEC!" install --no-fund --no-audit
    popd
)

if not exist "!ROOT!\frontend\node_modules\vite" (
    echo [*] Installing frontend packages...
    pushd "!ROOT!\frontend"
    call "!NPM_EXEC!" install --no-fund --no-audit
    popd
)

echo [*] Starting Backend...
> "%TEMP%\start_back.bat" (
    echo @echo off
    echo set "PATH=!PNODE!;%%PATH%%"
    echo cd /d "!ROOT!\backend"
    echo set USE_SQLITE=true
    echo set PORT=5001
    echo "!NPM_EXEC!" run dev
    echo pause
)
start "Backend (5001)" cmd /c "%TEMP%\start_back.bat"

echo [*] Starting Frontend...
> "%TEMP%\start_front.bat" (
    echo @echo off
    echo set "PATH=!PNODE!;%%PATH%%"
    echo cd /d "!ROOT!\frontend"
    echo "!NPM_EXEC!" run dev
    echo pause
)
start "Frontend (5174)" cmd /c "%TEMP%\start_front.bat"

echo [*] Waiting 8 seconds...
timeout /t 8 /nobreak >nul

echo [*] Opening site...
start http://127.0.0.1:5174

echo ==============================================
echo   Site should be open now!
echo ==============================================
pause
