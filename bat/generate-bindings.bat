@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0.."

set "TEMP_WEB_DIR=0"
if not exist "frontend_flutter\build\web" (
    mkdir "frontend_flutter\build\web" >nul 2>&1
    echo placeholder> "frontend_flutter\build\web\__embed_placeholder__.txt"
    set "TEMP_WEB_DIR=1"
)

if exist ".tools\wails.exe" (
    ".tools\wails.exe" generate module
) else (
    wails generate module
)
if errorlevel 1 goto :fail

if not exist "frontend_flutter\web\wailsjs\wailsjs\go\main\App.js" (
    echo [ERROR] Wails bindings were not generated in frontend_flutter\web\wailsjs.
    goto :fail
)

echo Wails bindings generated in frontend_flutter\web\wailsjs.
if "%TEMP_WEB_DIR%"=="1" rmdir /s /q "frontend_flutter\build\web" >nul 2>&1
exit /b 0

:fail
if "%TEMP_WEB_DIR%"=="1" rmdir /s /q "frontend_flutter\build\web" >nul 2>&1
exit /b 1
