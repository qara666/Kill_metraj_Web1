@echo off
echo [Caveman] Smashing fat folders...
FOR /d /r . %%d IN (node_modules) DO @IF EXIST "%%d" rd /s /q "%%d"
FOR /d /r . %%d IN (.next) DO @IF EXIST "%%d" rd /s /q "%%d"
echo [Caveman] Folders smashed. Project clean!
pause
