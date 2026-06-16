@echo off
setlocal enabledelayedexpansion
chcp 65001 > nul
title Kill Metraj - Dev Server

for /F "delims=" %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set "R=%ESC%[91m"
set "G=%ESC%[92m"
set "Y=%ESC%[93m"
set "B=%ESC%[94m"
set "C=%ESC%[96m"
set "Z=%ESC%[0m"

cls
echo %C%=========================================================
echo   _  ___ _ _   __  __      _
echo  ^| ^|/ (_) ^| ^| ^|  \/  ^|    ^| ^|
echo  ^| ' / _^| ^| ^|_^| \  / ^|___^| ^|_ _ __ __ _ _
echo  ^|  ^< ^| ^| ^| ^| ^__^| ^|\/^| / _ \ __^| '__/ _  ^| ^|
echo  ^| . \^| ^| ^| ^| ^|_^| ^|  ^| ^|  __/ ^|_^| ^| ^| (_^| ^| ^|
echo  ^|_^|\_\_^|_^|_^|\__^|_^|  ^|_^|\___^|\__^|_^|  \__,_^|_^|
echo.
echo                     Dev Server Launcher
echo ==========================================================%Z%
echo.

::---[ STEP 1: Check Node.js ]---
echo %Y%[1/4] Checking Node.js...%Z%
where node >nul 2>nul
if %errorlevel% neq 0 (
    echo %R%[ERROR] Node.js not found! Download: https://nodejs.org/%Z%
    pause
    exit /b 1
)
for /f "tokens=*" %%i in ('node -v') do set NODE_VER=%%i
for /f "tokens=*" %%i in ('npm -v') do set NPM_VER=%%i
echo %G%[OK] Node.js %NODE_VER%  ^|  npm v%NPM_VER%%Z%

::---[ STEP 2: Install deps ]---
echo.
echo %Y%[2/4] Checking dependencies...%Z%

if not exist "backend\node_modules\" (
    echo %B%[..] Installing backend packages...%Z%
    cd backend
    call npm install
    if %errorlevel% neq 0 (
        echo %R%[ERROR] npm install failed in backend/%Z%
        cd ..
        pause
        exit /b 1
    )
    cd ..
    echo %G%[OK] Backend packages installed.%Z%
) else (
    echo %G%[OK] Backend node_modules found.%Z%
)

if not exist "frontend\node_modules\" (
    echo %B%[..] Installing frontend packages...%Z%
    cd frontend
    call npm install
    if %errorlevel% neq 0 (
        echo %R%[ERROR] npm install failed in frontend/%Z%
        cd ..
        pause
        exit /b 1
    )
    cd ..
    echo %G%[OK] Frontend packages installed.%Z%
) else (
    echo %G%[OK] Frontend node_modules found.%Z%
)

::---[ STEP 3: Start servers ]---
echo.
echo %Y%[3/4] Starting servers...%Z%

set "ROOT_DIR=%CD%"

start "Backend (port 5001)" cmd /k "title Backend ^| port 5001 && cd /d %ROOT_DIR%\backend && npm run dev"
echo %G%[+] Backend started in new window (port 5001)%Z%

start "Frontend (port 5174)" cmd /k "title Frontend ^| port 5174 && cd /d %ROOT_DIR%\frontend && npm run dev"
echo %G%[+] Frontend started in new window (port 5174)%Z%

::---[ STEP 4: Wait for frontend ]---
echo.
echo %Y%[4/4] Waiting for frontend to be ready...%Z%

set ATTEMPT=0
set MAX=30

:WAIT_LOOP
set /a ATTEMPT+=1
if !ATTEMPT! GTR %MAX% (
    echo %R%[WARN] Timeout reached. Opening browser anyway...%Z%
    goto :OPEN_BROWSER
)

powershell -NoProfile -Command "try{Invoke-WebRequest -Uri 'http://localhost:5174' -UseBasicParsing -TimeoutSec 1 | Out-Null; exit 0}catch{exit 1}" >nul 2>nul
if %errorlevel% equ 0 goto :READY

set /a DOT_POS=!ATTEMPT!*3
echo %B%  Attempt !ATTEMPT!/%MAX% - waiting...%Z%
timeout /t 2 /nobreak >nul
goto :WAIT_LOOP

:READY
echo %G%[OK] Frontend is up and responding!%Z%

:OPEN_BROWSER
echo.
echo %C%Opening Chrome...%Z%

:: Try Chrome first, fallback to default browser
where chrome >nul 2>nul
if %errorlevel% equ 0 (
    start "" chrome "http://localhost:5174"
) else (
    start "" "http://localhost:5174"
)

echo.
echo %G%=========================================================
echo   STATUS
echo ==========================================================%Z%
echo   Frontend : %G%http://localhost:5174%Z%
echo   Backend  : %G%http://localhost:5001%Z%
echo %C%=========================================================
echo   Close the black cmd windows to stop the servers.
echo ==========================================================%Z%
echo.
pause
