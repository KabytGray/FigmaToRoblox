@echo off
title FigmaToRoblox - Uploader
cd /d "%~dp0"
node uploader.js
if errorlevel 1 pause
