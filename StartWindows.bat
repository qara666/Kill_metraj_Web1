@echo off
setlocal enabledelayedexpansion
title Kill-Metraj Launcher

echo.
echo  ===========================================================
echo   Kill-Metraj Local Launcher  (SQLite, no install needed)
echo  ===========================================================
echo.

:: ── 1. Find Node.js ──────────────────────────────────────────────

if exist ".portable-node\node-v20.14.0-win-x64\node.exe" (
    echo [OK] Portable Node.js found.
    set "PATH=%CD%\.portable-node\node-v20.14.0-win-x64;%PATH%"
    goto :CHECK_DEPS
)

where node >nul 2>nul
if %errorlevel% equ 0 (
    echo [OK] Node.js found in PATH.
    goto :CHECK_DEPS
)

where docker >nul 2>nul
if %errorlevel% equ 0 (
    echo [INFO] Node.js not found, using Docker...
    goto :START_DOCKER
)

echo [INFO] Node.js and Docker not found.
echo [*] Extracting bundled portable Node.js (100%% offline)...

if not exist ".portable-node" mkdir ".portable-node"

if exist ".portable-node-installer\node.zip" (
    powershell -NoProfile -Command "Expand-Archive -Path '.portable-node-installer\node.zip' -DestinationPath '.portable-node' -Force"
) else (
    echo [ERROR] Offline archive not found! Contact developer.
    pause
    exit /b 1
)

set "PATH=%CD%\.portable-node\node-v20.14.0-win-x64;%PATH%"
echo [OK] Extracted! Ready to launch with local database.
goto :CHECK_DEPS


:: ── DOCKER ───────────────────────────────────────────────────────
:START_DOCKER
docker-compose up --build -d
if %errorlevel% neq 0 (
    echo [ERROR] Docker failed to start!
    pause
    exit /b 1
)
echo.
echo   Site : http://localhost:80
echo   API  : http://localhost:5001
echo.
echo Press any key to stop...
pause >nul
docker-compose down
exit /b 0


:: ── DEPS ─────────────────────────────────────────────────────────
:CHECK_DEPS
echo.
echo [*] Checking dependencies...

if not exist "backend\node_modules" (
    echo [*] Installing backend packages...
    cd backend
    call npm install --no-fund --no-audit
    if %errorlevel% neq 0 (
        echo [ERROR] Backend npm install failed!
        cd ..
        pause
        exit /b 1
    )
    cd ..
) else (
    if not exist "backend\node_modules\sqlite3" (
        echo [*] Installing sqlite3 driver...
        cd backend
        call npm install sqlite3 --no-fund --no-audit
        cd ..
    )
)

if not exist "frontend\node_modules" (
    echo [*] Installing frontend packages...
    cd frontend
    call npm install --no-fund --no-audit
    if %errorlevel% neq 0 (
        echo [ERROR] Frontend npm install failed!
        cd ..
        pause
        exit /b 1
    )
    cd ..
)


:: ── GENERATE HELPER SCRIPTS ──────────────────────────────────────
set "ROOT=%CD%"

> "%TEMP%\km_backend.bat" (
    echo @echo off
    echo title Backend ^(port 5001^)
    echo cd /d "%ROOT%\backend"
    echo set "USE_SQLITE=true"
    echo set "PORT=5001"
    echo npm run dev
    echo pause
)

> "%TEMP%\km_frontend.bat" (
    echo @echo off
    echo title Frontend ^(port 5174^)
    echo cd /d "%ROOT%\frontend"
    echo npm run dev
    echo pause
)


:: ── LAUNCH ───────────────────────────────────────────────────────
echo.
echo [*] Starting Backend and Frontend...

start "Backend  (5001)" cmd /c "%TEMP%\km_backend.bat"
start "Frontend (5174)" cmd /c "%TEMP%\km_frontend.bat"


:: ── WAIT FOR SITE ────────────────────────────────────────────────
echo.
echo [*] Waiting for site to start (up to 60 sec)...
set ATTEMPT=0

:WAIT_LOOP
set /a ATTEMPT+=1
if %ATTEMPT% GTR 60 goto :OPEN_BROWSER
powershell -NoProfile -Command "try{Invoke-WebRequest 'http://localhost:5174' -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop | Out-Null; exit 0}catch{exit 1}" >nul 2>nul
if %errorlevel% equ 0 goto :OPEN_BROWSER
timeout /t 1 /nobreak >nul
goto :WAIT_LOOP


:OPEN_BROWSER
echo.
echo [OK] Site is ready! Opening browser...
start "" "http://localhost:5174"

echo.
echo  ===========================================================
echo   ALL SYSTEMS GO
echo   Site : http://localhost:5174
echo   API  : http://localhost:5001
echo.
echo   Login:    admin
echo   Password: password2026
echo.
echo   To stop: close the Backend and Frontend windows
echo  ===========================================================
echo.
pause
exit /b 0
