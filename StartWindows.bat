@echo off
setlocal enabledelayedexpansion
chcp 65001 > nul

:: Настройка цветов ANSI
for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set "RED=%ESC%[91m"
set "GREEN=%ESC%[92m"
set "YELLOW=%ESC%[93m"
set "BLUE=%ESC%[94m"
set "CYAN=%ESC%[96m"
set "RESET=%ESC%[0m"

title Kill Metraj - Dev Server

echo %CYAN%=======================================================
echo   _  __ _  _  _   __  __      _                 _ 
echo  ^| ^|/ /(^|)^| ^|^| ^| ^|  \/  ^|    ^| ^|               (_)
echo  ^| ' /  _ ^| ^|^| ^| ^| \  / ^| ___^| ^|_ _ __ __ _     _ 
echo  ^|  ^<  ^| ^|^| ^|^| ^| ^| ^|\/^| ^|/ _ \ __^| '__/ _` ^|   ^| ^|
echo  ^| . \ ^| ^|^| ^|^| ^| ^| ^|  ^| ^|  __/ ^|_^| ^| ^| (_^| ^|   ^| ^|
echo  ^|_^|\_\^|_^|^|_^|^|_^| ^|_^|  ^|_^|\___^|\__^|_^|  \__,_^|   ^| ^|
echo                                               _/ ^|
echo                                              ^|__/ 
echo =======================================================%RESET%
echo.

:: 1. Проверка окружения
echo %YELLOW%[1/4] Проверка окружения...%RESET%
where node >nul 2>nul
if %errorlevel% neq 0 (
    echo %RED%[ERROR] Node.js не найден! Скачайте с https://nodejs.org/%RESET%
    pause
    exit /b 1
)
for /f "tokens=*" %%i in ('node -v') do set NODE_VER=%%i
echo %GREEN%[OK] Node.js найден: %NODE_VER%%RESET%

:: 2. Установка зависимостей
echo.
echo %YELLOW%[2/4] Проверка зависимостей...%RESET%

if not exist "backend\node_modules\" (
    echo %BLUE%Установка npm пакетов для Backend...%RESET%
    cd backend
    call npm install
    cd ..
    echo %GREEN%[OK] Backend зависимости установлены.%RESET%
) else (
    echo %GREEN%[OK] Backend зависимости уже установлены.%RESET%
)

if not exist "frontend\node_modules\" (
    echo %BLUE%Установка npm пакетов для Frontend...%RESET%
    cd frontend
    call npm install
    cd ..
    echo %GREEN%[OK] Frontend зависимости установлены.%RESET%
) else (
    echo %GREEN%[OK] Frontend зависимости уже установлены.%RESET%
)

:: 3. Запуск серверов
echo.
echo %YELLOW%[3/4] Запуск серверов...%RESET%

cd backend
start "Kill Metraj - Backend (5001)" cmd /c "title Backend Server && npm run dev"
cd ..
echo %GREEN%[+] Backend запускается в отдельном окне (порт 5001)%RESET%

cd frontend
start "Kill Metraj - Frontend (5174)" cmd /c "title Frontend Server && npm run dev"
cd ..
echo %GREEN%[+] Frontend запускается в отдельном окне (порт 5174)%RESET%

:: 4. Ожидание готовности
echo.
echo %YELLOW%[4/4] Ожидание готовности фронтенда...%RESET%

set MAX_ATTEMPTS=25
set ATTEMPT=0

:WAIT_LOOP
set /a ATTEMPT+=1
if %ATTEMPT% GTR %MAX_ATTEMPTS% (
    echo %RED%[WARN] Превышено время ожидания. Пробуем открыть браузер...%RESET%
    goto OPEN_BROWSER
)

powershell -Command "try { $null = Invoke-WebRequest -Uri 'http://localhost:5174' -UseBasicParsing -ErrorAction Stop; exit 0 } catch { exit 1 }" >nul 2>nul
if %errorlevel% neq 0 (
    echo %BLUE%Ожидание ответа сервера... Попытка %ATTEMPT% из %MAX_ATTEMPTS%%RESET%
    timeout /t 2 /nobreak > nul
    goto WAIT_LOOP
)

echo %GREEN%[OK] Серверы успешно запущены и отвечают!%RESET%

:OPEN_BROWSER
echo.
echo %CYAN%Открытие Google Chrome...%RESET%
start chrome "http://localhost:5174" || start http://localhost:5174

echo.
echo %GREEN%=======================================================
echo Система работает. Логи доступны в открытых окнах.
echo Чтобы выключить проект, закрой черные окна cmd.
echo =======================================================%RESET%
echo.
pause
