@echo off
chcp 65001 >nul
rem 奶龙星 · 三关挑战（源码运行，需本机 Godot 4.7.2）
start "" "C:\Users\31798\Downloads\迷失太空\迷失太空\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe" --path "%~dp0" --rendering-method gl_compatibility --resolution 1600x900 
