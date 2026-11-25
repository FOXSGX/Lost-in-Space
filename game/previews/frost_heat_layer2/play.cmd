@echo off
setlocal
set "FROST_GODOT=%LOCALAPPDATA%\Programs\Godot\4.7.2\Godot_v4.7.2-stable_win64.exe"
if defined GODOT_PATH set "FROST_GODOT=%GODOT_PATH%"
if not exist "%FROST_GODOT%" (
  echo Set GODOT_PATH to your Godot 4 executable.
  pause
  exit /b 1
)
start "" "%FROST_GODOT%" --path "%~dp0..\.." res://previews/frost_heat_layer2/preview.tscn
