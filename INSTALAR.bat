@echo off
title FigmaToRoblox - instalacao
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0setup.ps1"
pause
