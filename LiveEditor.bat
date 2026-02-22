@echo off
title Palworld Live Editor
echo Starting Palworld Live Editor...
start "" powershell.exe -ExecutionPolicy Bypass -File "%~dp0scripts\live-editor-server.ps1"
timeout /t 2 >nul
start "" http://localhost:8213
