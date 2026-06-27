@echo off
chcp 65001 > nul
title Kill Metraj - Docker Server

echo ==========================================================
echo   Docker Server Launcher (No Node.js Required)
echo ==========================================================
echo.

echo [1/3] Checking Docker...
docker -v >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Docker is not installed or not running!
    echo To run this project without Node.js, you need Docker Desktop.
    echo Please install it from: https://www.docker.com/products/docker-desktop/
    pause
    exit /b 1
)
echo [OK] Docker is running.

echo.
echo [2/3] Building and starting services...
docker-compose up --build -d

echo.
echo [3/3] Services are starting!
echo.
echo ==========================================================
echo   STATUS
echo ==========================================================
echo   Frontend : http://localhost:80  (Wait 30-60 sec to compile)
echo   Backend  : http://localhost:5001
echo   Database : postgres:5432
echo   Cache    : redis:6379
echo ==========================================================
echo.
echo Servers are running in the background.
echo You can open your browser at http://localhost:80
echo.
echo Press ANY KEY to STOP the servers and exit...
pause >nul

echo.
echo [!] Stopping services...
docker-compose down
echo [OK] Services stopped.
pause
