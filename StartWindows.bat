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

:: 1. Сначала проверяем, есть ли уже портативная версия (чтобы запуститься мгновенно)
if exist ".portable-node\node-v20.14.0-win-x64\node.exe" (
    echo %G%[+] Используем скачанный портативный Node.js. Запуск...%Z%
    set "PATH=%CD%\.portable-node\node-v20.14.0-win-x64;%PATH%"
    set "USE_SQLITE=true"
    goto :START_NODE
)

:: 2. Иначе ищем локальный Node.js в системе
where node >nul 2>nul
if %errorlevel% equ 0 (
    echo %G%[+] Нашли Node.js в системе. Отлично.%Z%
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

:: 4. Если ничего нет — распаковываем локальный оффлайн-архив!
echo %Y%[~] Ни Node.js, ни Docker не найдены.%Z%
echo %B%[*] Распаковываем встроенный портативный Node.js (работает 100%% оффлайн без интернета)...%Z%

if not exist ".portable-node" mkdir ".portable-node"

if exist ".portable-node-installer\node.zip" (
    powershell -NoProfile -Command "Expand-Archive -Path '.portable-node-installer\node.zip' -DestinationPath '.portable-node' -Force"
) else (
    echo %R%[ERROR] Оффлайн архив не найден! Обратитесь к разработчику.%Z%
    pause
    exit /b 1
)

set "PATH=%CD%\.portable-node\node-v20.14.0-win-x64;%PATH%"
set "USE_SQLITE=true"
echo %G%[+] Готово! Теперь всё запустится (с локальной базой).%Z%
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

cd backend
if not exist "node_modules" (
    echo %B%[*] Устанавливаем зависимости бэкенда...%Z%
    call npm install --no-fund --no-audit
) else if not exist "node_modules\sqlite3" (
    echo %B%[*] Доустанавливаем драйвер SQLite...%Z%
    call npm install sqlite3 --no-fund --no-audit
)
cd ..

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
