@echo off
title NOVAGEN // Zero-Trace Deep Uninstaller Pro
setlocal

:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [NOVAGEN] Requesting Administrator elevation for 100%% Deep System Access...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0NovaGen-Engine.ps1\"' -Verb RunAs"
    exit /b
)

:: Already Administrator -> Launch GUI directly
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0NovaGen-Engine.ps1"
exit /b
