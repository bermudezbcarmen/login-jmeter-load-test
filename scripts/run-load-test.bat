@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-test.ps1" -Mode load
exit /b %errorlevel%
