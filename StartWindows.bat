@echo off
setlocal enabledelayedexpansion
title Kill-Metraj Launcher

:: ── KILL OLD PROCESSES ───────────────────────────────────────────
taskkill /F /IM node.exe >nul 2>nul

:MAIN_MENU
cls
echo.
echo  ===========================================================
echo   Kill-Metraj Local Launcher
echo  ===========================================================
echo   1. Start Application  (auto in 5 sec)
echo   2. Update from GitHub (no Git needed)
echo   3. Reinstall Dependencies
echo   4. Reset Database (wipe SQLite)
echo   5. Open Logs Folder
echo   6. Exit
echo  ===========================================================
echo.
choice /C 123456 /T 5 /D 1 /M "Select: "

if !errorlevel! equ 6 exit /b 0
if !errorlevel! equ 5 goto :OPEN_LOGS
if !errorlevel! equ 4 goto :RESET_DB
if !errorlevel! equ 3 goto :FORCE_REINSTALL
if !errorlevel! equ 2 goto :UPDATE_GIT
goto :START_LAUNCH

:: ──────────────────────────────────────────────────────────────────
:UPDATE_GIT
echo.
echo [*] Downloading update from GitHub...
powershell -NoProfile -Command ^
  "$z='%TEMP%\km_upd.zip'; $d='%TEMP%\km_upd'; " ^
  "if(Test-Path $d){Remove-Item $d -Recurse -Force}; " ^
  "Invoke-WebRequest 'https://github.com/qara666/Kill_metraj_Web1/archive/refs/heads/main.zip' -OutFile $z -UseBasicParsing; " ^
  "Expand-Archive $z $d -Force; " ^
  "robocopy \"$d\Kill_metraj_Web1-main\" '%CD%' /E /IS /IT /XF .env database.sqlite /XD .git .portable-node node_modules | Out-Null; " ^
  "Remove-Item $z,$d -Recurse -Force -ErrorAction SilentlyContinue"
echo [OK] Done.
pause
goto :MAIN_MENU

:: ──────────────────────────────────────────────────────────────────
:OPEN_LOGS
if not exist "backend\logs" mkdir "backend\logs"
explorer "%CD%\backend\logs"
goto :MAIN_MENU

:: ──────────────────────────────────────────────────────────────────
:RESET_DB
echo.
echo [*] Deleting database...
if exist "backend\database.sqlite" del /F /Q "backend\database.sqlite"
echo [OK] Fresh database will be created on next start.
pause
goto :MAIN_MENU

:: ──────────────────────────────────────────────────────────────────
:FORCE_REINSTALL
echo.
echo [*] Removing node_modules...
if exist "backend\node_modules"  rmdir /S /Q "backend\node_modules"
if exist "frontend\node_modules" rmdir /S /Q "frontend\node_modules"
echo [OK] Will reinstall on launch.
goto :START_LAUNCH

:: ──────────────────────────────────────────────────────────────────
:START_LAUNCH
echo.
echo [*] Locating Node.js...

set "PORTABLE_DIR=%CD%\.portable-node\node-v20.14.0-win-x64"
set "NODE_BIN="
set "NPM_BIN="

:: 1 - portable node already extracted
if exist "%PORTABLE_DIR%\node.exe" (
    set "NODE_BIN=%PORTABLE_DIR%\node.exe"
    set "NPM_BIN=%PORTABLE_DIR%\npm.cmd"
    set "PATH=%PORTABLE_DIR%;!PATH!"
    echo [OK] Portable Node.js ready.
    goto :CHECK_DEPS
)

:: 2 - system node
where node >nul 2>nul
if !errorlevel! equ 0 (
    for /f "tokens=*" %%i in ('where node') do set "NODE_BIN=%%i" & goto :FOUND_SYSTEM
    :FOUND_SYSTEM
    for /f "tokens=*" %%i in ('where npm 2^>nul') do set "NPM_BIN=%%i" & goto :FOUND_NPM
    :FOUND_NPM
    echo [OK] System Node.js found.
    goto :CHECK_DEPS
)

:: 3 - docker fallback
where docker >nul 2>nul
if !errorlevel! equ 0 goto :START_DOCKER

:: 4 - extract bundled zip
echo [*] Extracting portable Node.js...
if not exist ".portable-node" mkdir ".portable-node"
if not exist ".portable-node-installer\node.zip" (
    echo [ERROR] node.zip not found. Download Node.js from nodejs.org/en/download/
    pause & exit /b 1
)
powershell -NoProfile -Command "Expand-Archive '.portable-node-installer\node.zip' '.portable-node' -Force"
if !errorlevel! neq 0 ( echo [ERROR] Extraction failed. & pause & exit /b 1 )
if not exist "%PORTABLE_DIR%\node.exe" ( echo [ERROR] node.exe not found after extract. & pause & exit /b 1 )
set "NODE_BIN=%PORTABLE_DIR%\node.exe"
set "NPM_BIN=%PORTABLE_DIR%\npm.cmd"
set "PATH=%PORTABLE_DIR%;!PATH!"
echo [OK] Portable Node.js extracted.
goto :CHECK_DEPS

:START_DOCKER
docker-compose up --build -d
if !errorlevel! neq 0 ( echo [ERROR] Docker failed. & pause & exit /b 1 )
echo Site: http://localhost:80  /  API: http://localhost:5001
pause >nul
docker-compose down
exit /b 0

:: ──────────────────────────────────────────────────────────────────
:CHECK_DEPS
echo.
echo [*] Checking dependencies...

if not exist "backend\node_modules\.bin\nodemon.cmd" (
    echo [*] Installing backend packages...
    cd backend
    call "!NPM_BIN!" install --no-fund --no-audit
    if !errorlevel! neq 0 ( cd .. & echo [ERROR] Backend install failed! & pause & exit /b 1 )
    cd ..
) else (
    if not exist "backend\node_modules\sqlite3" (
        echo [*] Adding sqlite3...
        cd backend & call "!NPM_BIN!" install sqlite3 --no-fund --no-audit & cd ..
    )
)

if not exist "frontend\node_modules\.bin\vite.cmd" (
    echo [*] Installing frontend packages...
    cd frontend
    call "!NPM_BIN!" install --no-fund --no-audit
    if !errorlevel! neq 0 ( cd .. & echo [ERROR] Frontend install failed! & pause & exit /b 1 )
    cd ..
)

:: ──────────────────────────────────────────────────────────────────
:: Write helper scripts — use SETLOCAL/ENDLOCAL trick to write the
:: exact npm path without Windows mangling the percent signs
set "ROOT=%CD%"
set "NPM_PATH=!NPM_BIN!"

(
    echo @echo off
    echo title Backend (port 5001)
    echo cd /d "!ROOT!\backend"
    echo set "USE_SQLITE=true"
    echo set "PORT=5001"
    echo "!NPM_PATH!" run dev
    echo pause
) > "%TEMP%\km_backend.bat"

(
    echo @echo off
    echo title Frontend (port 5174)
    echo cd /d "!ROOT!\frontend"
    echo "!NPM_PATH!" run dev
    echo pause
) > "%TEMP%\km_frontend.bat"

:: ──────────────────────────────────────────────────────────────────
echo.
echo [*] Launching servers...
start "Backend  (5001)" cmd /k "%TEMP%\km_backend.bat"
start "Frontend (5174)" cmd /k "%TEMP%\km_frontend.bat"

echo [*] Waiting (up to 90 sec) for both servers...
set ATTEMPT=0
:WAIT_LOOP
set /a ATTEMPT+=1
if !ATTEMPT! GTR 90 goto :OPEN_BROWSER
powershell -NoProfile -Command ^
  "try{ Invoke-WebRequest 'http://localhost:5001/api/health' -UseBasicParsing -TimeoutSec 1 -EA Stop | Out-Null; " ^
  "Invoke-WebRequest 'http://localhost:5174' -UseBasicParsing -TimeoutSec 1 -EA Stop | Out-Null; exit 0 }catch{ exit 1 }" >nul 2>nul
if !errorlevel! equ 0 goto :OPEN_BROWSER
timeout /t 1 /nobreak >nul
goto :WAIT_LOOP

:OPEN_BROWSER
echo.
echo  ===========================================================
echo   READY
echo   Site     : http://localhost:5174
echo   API      : http://localhost:5001
echo   Login    : admin
echo   Password : password2026
echo  ===========================================================
echo.
start "" "http://localhost:5174"
pause
exit /b 0
