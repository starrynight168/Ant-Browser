@echo off
setlocal
cd /d "%~dp0.."

if not "%~1"=="" echo Flutter UI migration uses the standard Wails dev mode; extra arguments are ignored.
powershell -NoProfile -ExecutionPolicy Bypass -File "%CD%\start-dev.ps1"
exit /b %ERRORLEVEL%
