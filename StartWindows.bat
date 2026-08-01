@echo off
setlocal enabledelayedexpansion
title Kill-Metraj Launcher

:: Убиваем старые процессы node
taskkill /F /IM node.exe >nul 2>nul

:MAIN_MENU
cls
echo.
echo   ================================================================
echo    [  KILL-METRAJ  ^|  Local Launcher  ]
echo   ================================================================
echo.
echo     1.  Start Application         (auto in 5 sec)
echo     2.  Update from GitHub        (download latest)
echo     3.  Rebuild Dependencies      (fix broken packages)
echo     4.  Reset Database            (wipe SQLite)
echo     5.  Open Logs Folder
echo     6.  Exit
echo.
echo   ================================================================
echo.
choice /C 123456 /T 5 /D 1 /M "  Select: "

if errorlevel 6 exit /b 0
if errorlevel 5 goto :OPEN_LOGS
if errorlevel 4 goto :RESET_DB
if errorlevel 3 goto :REINSTALL
if errorlevel 2 goto :UPDATE_GIT
goto :START

:UPDATE_GIT
echo.
echo [*] Downloading update from GitHub...
powershell -NoProfile -Command "$z='%TEMP%\km.zip';$d='%TEMP%\km_upd';if(Test-Path $d){Remove-Item $d -Recurse -Force};Invoke-WebRequest 'https://github.com/qara666/Kill_metraj_Web1/archive/refs/heads/main.zip' -OutFile $z -UseBasicParsing;Expand-Archive $z $d -Force;robocopy ($d+'\Kill_metraj_Web1-main') '%CD%' /E /IS /IT /XF .env database.sqlite /XD .git node_modules | Out-Null;Remove-Item $z,$d -Recurse -Force -EA SilentlyContinue"
echo [OK] Done.
pause
goto :MAIN_MENU

:OPEN_LOGS
if not exist "backend\logs" mkdir "backend\logs"
explorer "%CD%\backend\logs"
goto :MAIN_MENU

:RESET_DB
echo.
echo [*] Deleting database...
if exist "backend\database.sqlite" del /F /Q "backend\database.sqlite"
echo [OK] Fresh start.
pause
goto :MAIN_MENU

:REINSTALL
echo.
echo [*] Removing node_modules...
if exist "backend\node_modules"  rmdir /S /Q "backend\node_modules"
if exist "frontend\node_modules" rmdir /S /Q "frontend\node_modules"
echo [OK] Done.
goto :START

:: ================================================================
:START
cls
echo.
echo   ================================================================
echo    [  KILL-METRAJ  ^|  Starting up...  ]
echo   ================================================================
echo.

:: Запоминаем корневую папку проекта
set "ROOT=%~dp0"
:: Убираем обратный слэш в конце если есть
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

:: --- Найти npm ---
set "NPM=npm"

set "PNODE=%ROOT%\.portable-node\node-v20.14.0-win-x64"
if exist "%PNODE%\npm.cmd" (
    set "NPM=%PNODE%\npm.cmd"
    set "PATH=%PNODE%;%PATH%"
    echo [OK] Portable Node.js: %PNODE%
    goto :CHECK_DEPS
)

where npm >nul 2>nul
if not errorlevel 1 (
    echo [OK] System Node.js found.
    goto :CHECK_DEPS
)

echo.
echo   [WARN] Node.js not found! Downloading portable version...
if not exist ".portable-node" mkdir ".portable-node"
if not exist "%PNODE%\node.exe" (
    echo   Downloading Node.js v20.14.0 (about 30MB)...
    powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://nodejs.org/dist/v20.14.0/node-v20.14.0-win-x64.zip' -OutFile '.portable-node\node.zip'"
    echo   Extracting Node.js...
    powershell -NoProfile -Command "Expand-Archive -Path '.portable-node\node.zip' -DestinationPath '.portable-node' -Force"
    del ".portable-node\node.zip"
)
set "NPM=%PNODE%\npm.cmd"
set "PATH=%PNODE%;%PATH%"
echo [OK] Portable Node.js installed: %PNODE%

:: ================================================================
:CHECK_DEPS
echo.
echo [*] Checking packages...

if not exist "%ROOT%\backend\node_modules\express" (
    echo [*] Installing backend packages (first time ~1 min)...
    pushd "%ROOT%\backend"
    call "%NPM%" install --no-fund --no-audit
    set ERRLVL=%errorlevel%
    popd
    if %ERRLVL% neq 0 (
        echo [ERROR] Backend install failed!
        pause
        exit /b 1
    )
    echo [OK] Backend packages installed.
)

if not exist "%ROOT%\frontend\node_modules\vite" (
    echo [*] Installing frontend packages (first time ~1 min)...
    pushd "%ROOT%\frontend"
    call "%NPM%" install --no-fund --no-audit
    set ERRLVL=%errorlevel%
    popd
    if %ERRLVL% neq 0 (
        echo [ERROR] Frontend install failed!
        pause
        exit /b 1
    )
    echo [OK] Frontend packages installed.
)

:: ================================================================
:LAUNCH
echo.
echo [*] Writing launch scripts...

:: Записываем backend скрипт (используем %VAR% - они раскроются при записи)
(
    echo @echo off
    echo title Backend-5001
    echo set "USE_SQLITE=true"
    echo set "PORT=5001"
    echo pushd "%ROOT%\backend"
    echo call "%NPM%" run dev
    echo popd
    echo echo.
    echo echo Backend stopped. Press any key...
    echo pause ^>nul
) > "%ROOT%\_launch_backend.bat"

:: Записываем frontend скрипт
(
    echo @echo off
    echo title Frontend-5174
    echo pushd "%ROOT%\frontend"
    echo call "%NPM%" run dev
    echo popd
    echo echo.
    echo echo Frontend stopped. Press any key...
    echo pause ^>nul
) > "%ROOT%\_launch_frontend.bat"

echo [*] Starting Backend...
start "Backend-5001"  cmd /k "%ROOT%\_launch_backend.bat"
timeout /t 3 /nobreak >nul

echo [*] Starting Frontend...
start "Frontend-5174" cmd /k "%ROOT%\_launch_frontend.bat"

:: ================================================================
echo.
echo [*] Waiting for servers to be ready...
set /a CNT=0

:WAIT
set /a CNT+=1
if %CNT% gtr 90 (
    echo [!] Timeout - opening anyway.
    goto :OPEN
)

powershell -NoProfile -Command "try{iwr 'http://localhost:5001/api/health' -UseBasicParsing -TimeoutSec 1 -EA Stop | Out-Null;iwr 'http://localhost:5174' -UseBasicParsing -TimeoutSec 1 -EA Stop | Out-Null;exit 0}catch{exit 1}" >nul 2>nul
if errorlevel 1 (
    timeout /t 1 /nobreak >nul
    goto :WAIT
)

:: ================================================================
:OPEN
echo.
echo   ================================================================
echo    [  KILL-METRAJ  ^|  READY!  ]
echo   ================================================================
echo.
echo      Site     :  http://localhost:5174
echo      API      :  http://localhost:5001
echo.
echo      Login    :  admin
echo      Password :  password2026
echo.
echo   ================================================================
echo.
echo   Press any key to STOP all servers and exit.
echo.
start "" "http://localhost:5174"
pause >nul

taskkill /F /IM node.exe >nul 2>nul
del /F /Q "%ROOT%\_launch_backend.bat" >nul 2>nul
del /F /Q "%ROOT%\_launch_frontend.bat" >nul 2>nul
exit /b 0
