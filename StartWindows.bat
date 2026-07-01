@echo off
setlocal enabledelayedexpansion
chcp 65001 > nul
title Kill-Metraj Запуск

echo ==========================================================
echo   Автоматический запуск Kill-Metraj (SQLite, без установки)
echo ==========================================================
echo.

:: ── 1. Ищем Node.js ──────────────────────────────────────────────
if exist ".portable-node\node-v20.14.0-win-x64\node.exe" (
    echo [+] Портативный Node.js найден. Используем его.
    set "PATH=%CD%\.portable-node\node-v20.14.0-win-x64;%PATH%"
    goto :CHECK_DEPS
)

where node >nul 2>nul
if %errorlevel% equ 0 (
    echo [+] Node.js найден в системе.
    goto :CHECK_DEPS
)

where docker >nul 2>nul
if %errorlevel% equ 0 (
    echo [~] Node.js не найден, но найден Docker. Запускаем через Docker...
    goto :START_DOCKER
)

echo [ERROR] Node.js не найден! Установите Node.js с https://nodejs.org/
echo.
pause
exit /b 1


:: ── DOCKER ───────────────────────────────────────────────────────
:START_DOCKER
docker-compose up --build -d
if %errorlevel% neq 0 (
    echo [ERROR] Docker упал при запуске!
    pause
    exit /b 1
)
echo.
echo   Сайт : http://localhost:80
echo   API  : http://localhost:5001
echo.
echo Нажми любую кнопку для остановки...
pause >nul
docker-compose down
exit /b 0


:: ── ПРОВЕРКА И УСТАНОВКА ЗАВИСИМОСТЕЙ ───────────────────────────
:CHECK_DEPS
echo.
echo [*] Проверяем зависимости...

:: Backend deps
if not exist "backend\node_modules" (
    echo [*] Устанавливаем зависимости backend...
    cd backend
    call npm install --no-fund --no-audit
    if %errorlevel% neq 0 (
        echo [ERROR] npm install backend завершился с ошибкой!
        cd ..
        pause
        exit /b 1
    )
    cd ..
)

:: SQLite driver
if not exist "backend\node_modules\sqlite3" (
    echo [*] Доустанавливаем sqlite3...
    cd backend
    call npm install sqlite3 --no-fund --no-audit
    cd ..
)

:: Frontend deps
if not exist "frontend\node_modules" (
    echo [*] Устанавливаем зависимости frontend...
    cd frontend
    call npm install --no-fund --no-audit
    if %errorlevel% neq 0 (
        echo [ERROR] npm install frontend завершился с ошибкой!
        cd ..
        pause
        exit /b 1
    )
    cd ..
)

:: ── ГЕНЕРИРУЕМ ХЕЛПЕР-СКРИПТЫ ────────────────────────────────────
set "ROOT=%CD%"

:: Пишем backend-helper.bat
(
echo @echo off
echo title Backend ^(5001^)
echo cd /d "%ROOT%\backend"
echo set USE_SQLITE=true
echo set PORT=5001
echo npm run dev
echo pause
) > "%TEMP%\km_backend.bat"

:: Пишем frontend-helper.bat
(
echo @echo off
echo title Frontend ^(5174^)
echo cd /d "%ROOT%\frontend"
echo npm run dev
echo pause
) > "%TEMP%\km_frontend.bat"


:: ── ЗАПУСК ───────────────────────────────────────────────────────
echo.
echo [*] Запускаем Backend и Frontend...

start "Backend (5001)" cmd /c "%TEMP%\km_backend.bat"
start "Frontend (5174)" cmd /c "%TEMP%\km_frontend.bat"


:: ── ЖДЁМ ПОКА ПОДНИМЕТСЯ ФРОНТЕНД ────────────────────────────────
echo.
echo [*] Ждем запуска сайта (до 60 секунд)...
set /a ATTEMPT=0

:WAIT_LOOP
set /a ATTEMPT+=1
if %ATTEMPT% GTR 60 (
    echo [~] Таймаут — открываем браузер принудительно...
    goto :OPEN_BROWSER
)
powershell -NoProfile -Command "try{$r=Invoke-WebRequest 'http://localhost:5174' -UseBasicParsing -TimeoutSec 1;exit 0}catch{exit 1}" >nul 2>nul
if %errorlevel% equ 0 goto :OPEN_BROWSER
timeout /t 1 /nobreak >nul
goto :WAIT_LOOP


:OPEN_BROWSER
echo.
echo [+] Сайт готов! Открываю браузер...
start "" "http://localhost:5174"

echo.
echo ==========================================================
echo   ВСЁ ЗАПУЩЕНО
echo   Сайт : http://localhost:5174
echo   API  : http://localhost:5001
echo.
echo   Чтобы выключить - закрой окна Backend и Frontend
echo ==========================================================
echo.
pause
exit /b 0
