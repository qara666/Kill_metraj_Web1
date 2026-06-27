@echo off
setlocal enabledelayedexpansion
chcp 65001 > nul
title Запуск проекта

:: Подрубаем цвета для красивого вывода
for /F "delims=" %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set "R=%ESC%[91m"
set "G=%ESC%[92m"
set "Y=%ESC%[93m"
set "B=%ESC%[94m"
set "C=%ESC%[96m"
set "Z=%ESC%[0m"

cls
echo %C%==========================================================
echo   Автоматический запуск проекта (без установки)
echo ==========================================================%Z%
echo.

:: 1. Ищем локальный Node.js
where node >nul 2>nul
if %errorlevel% equ 0 (
    echo %G%[+] Нашли Node.js в системе. Отлично.%Z%
    goto :START_NODE
)

:: 2. Ищем портативный Node.js (если уже качали)
if exist ".portable-node\node-v20.14.0-win-x64\node.exe" (
    echo %G%[+] Нашли портативный Node.js. Запускаем из него...%Z%
    set "PATH=%CD%\.portable-node\node-v20.14.0-win-x64;%PATH%"
    goto :START_NODE
)

:: 3. Если нет Node, проверяем Docker
where docker-compose >nul 2>nul
if %errorlevel% equ 0 (
    echo %Y%[~] Node.js нет, но есть Docker. Поднимаем контейнеры...%Z%
    goto :START_DOCKER
)
where docker >nul 2>nul
if %errorlevel% equ 0 (
    echo %Y%[~] Node.js нет, но есть Docker. Поднимаем контейнеры...%Z%
    goto :START_DOCKER
)

:: 4. Если ничего нет — качаем портативную версию (ZIP), права админа не нужны
echo %Y%[~] Ни Node.js, ни Docker не найдены.%Z%
echo %B%[*] Скачиваем портативный Node.js (весит ~30 МБ, ставится сам в скрытую папку)...%Z%

if not exist ".portable-node" mkdir ".portable-node"
powershell -NoProfile -Command "$ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://nodejs.org/dist/v20.14.0/node-v20.14.0-win-x64.zip' -OutFile '.portable-node\node.zip'"

echo %B%[*] Распаковываем архив...%Z%
powershell -NoProfile -Command "Expand-Archive -Path '.portable-node\node.zip' -DestinationPath '.portable-node' -Force"
del /q ".portable-node\node.zip"

set "PATH=%CD%\.portable-node\node-v20.14.0-win-x64;%PATH%"
echo %G%[+] Готово! Теперь всё запустится.%Z%
goto :START_NODE


:: ---------------------------------------------------------
:: БЛОК ЗАПУСКА DOCKER
:: ---------------------------------------------------------
:START_DOCKER
echo.
echo %C%Запускаем базу, бэкенд и фронт через Docker...%Z%
docker-compose up --build -d
echo.
echo %G%==========================================================
echo   Всё поднято через Docker!
echo   Сайт     : http://localhost:80 (первый запуск займет секунд 30)
echo   API      : http://localhost:5001
echo ==========================================================%Z%
echo %Y%Нажми любую кнопку в этом окне, чтобы выключить серверы...%Z%
pause >nul
echo %C%Останавливаем контейнеры...%Z%
docker-compose down
exit /b 0


:: ---------------------------------------------------------
:: БЛОК ЗАПУСКА NODE.JS
:: ---------------------------------------------------------
:START_NODE
echo.
echo %C%Проверяем зависимости...%Z%

if not exist "backend\node_modules\" (
    echo %B%[*] Ставим пакеты для бэкенда...%Z%
    cd backend
    call npm install
    cd ..
)

if not exist "frontend\node_modules\" (
    echo %B%[*] Ставим пакеты для фронтенда...%Z%
    cd frontend
    call npm install
    cd ..
)

echo.
echo %C%Поднимаем серверы...%Z%
set "ROOT_DIR=%CD%"

start "Бэкенд (порт 5001)" cmd /k "title Бэкенд && cd /d %ROOT_DIR%\backend && npm run dev"
start "Фронтенд (порт 5174)" cmd /k "title Фронтенд && cd /d %ROOT_DIR%\frontend && npm run dev"

echo.
echo %B%[*] Ждем, пока проснется сайт...%Z%
set ATTEMPT=0
set MAX=25

:WAIT_LOOP
set /a ATTEMPT+=1
if !ATTEMPT! GTR %MAX% goto :OPEN_BROWSER
powershell -NoProfile -Command "try{Invoke-WebRequest -Uri 'http://localhost:5174' -UseBasicParsing -TimeoutSec 1 | Out-Null; exit 0}catch{exit 1}" >nul 2>nul
if %errorlevel% equ 0 goto :OPEN_BROWSER
timeout /t 1 /nobreak >nul
goto :WAIT_LOOP

:OPEN_BROWSER
echo.
echo %G%[+] Всё работает! Открываю браузер...%Z%
start "" "http://localhost:5174"

echo.
echo %G%==========================================================
echo   ВСЁ УСПЕШНО ЗАПУЩЕНО
echo ==========================================================%Z%
echo   Сайт     : %C%http://localhost:5174%Z%
echo   API      : %C%http://localhost:5001%Z%
echo.
echo   %Y%Чтобы выключить, просто закрой два черных окна консоли.%Z%
echo %G%==========================================================%Z%
pause
exit /b 0
