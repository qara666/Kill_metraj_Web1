@echo off
title Kill-Metraj Simple Launcher

echo ==============================================
echo   KILL-METRAJ ULTRA SIMPLE LAUNCHER
echo ==============================================
echo.

:: 1. Убиваем старые процессы, если они зависли
taskkill /F /IM node.exe >nul 2>nul

:: 2. Подключаем портативный Node.js, если он есть
set "PORTABLE_NODE=%CD%\.portable-node\node-v20.14.0-win-x64"
if exist "%PORTABLE_NODE%\node.exe" (
    set "PATH=%PORTABLE_NODE%;%PATH%"
)

:: 3. Запускаем Бэкенд
echo [*] Starting Backend...
start "Backend (5001)" cmd /k "cd backend && set USE_SQLITE=true && set PORT=5001 && npm run dev"

:: 4. Запускаем Фронтенд
echo [*] Starting Frontend...
start "Frontend (5174)" cmd /k "cd frontend && npm run dev"

:: 5. Просто ждем 8 секунд без всяких проверок
echo [*] Waiting 8 seconds for servers to wake up...
timeout /t 8 /nobreak >nul

:: 6. Открываем браузер
echo [*] Opening site...
start http://127.0.0.1:5174

echo.
echo ==============================================
echo   Сайт открыт! 
echo   Логин: admin / Пароль: password2026
echo ==============================================
pause
