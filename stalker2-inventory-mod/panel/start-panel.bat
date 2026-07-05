@echo off
rem Запуск панели «Выгодный хабар» поверх игры (WPF требует STA).
start "" powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0LootPanel.ps1"
