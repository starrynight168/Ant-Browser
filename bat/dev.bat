@echo off
setlocal
cd /d "%~dp0.."

if not "%~1"=="" echo Native Flutter dev launcher ignores extra arguments.
powershell -NoProfile -ExecutionPolicy Bypass -File "%CD%\start-dev.ps1"
exit /b %ERRORLEVEL%
