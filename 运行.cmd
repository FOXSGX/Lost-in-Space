@echo off
chcp 936 >nul
setlocal
set "GODOT=%LOCALAPPDATA%\Programs\Godot\4.7.2\Godot_v4.7.2-stable_win64.exe"
if defined GODOT_PATH set "GODOT=%GODOT_PATH%"

:menu
echo.
echo  ===== 迷失太空 · 运行入口 =====
echo    1  主游戏（主菜单 → 新航程）
echo    2  美术演示 ART-SAMPLE-002（空格拉锤、F1 切机位）
echo    3  物理沙盒（左键抓箱子、推重柜）
echo    4  霜烬星 0.4 科考站（独立预览）
echo    5  共振星五幕试玩版（导出包，独立的 exe）
echo    0  退出
echo.
set /p "pick=输入编号并回车: "
if not defined pick exit /b 1
if "%pick%"=="1" call :run "%~dp0game" "" & goto menu
if "%pick%"=="2" call :run "%~dp0art-source\deliveries\ART-SAMPLE-002_TEAM_KIT\01_GODOT_DEMO" "" & goto menu
if "%pick%"=="3" call :run "%~dp0game" "res://examples/first_person_sandbox/first_person_sandbox.tscn" & goto menu
if "%pick%"=="4" call :run "%~dp0game" "res://previews/frost_station/adventure.tscn" & goto menu
if "%pick%"=="5" call :runexe "%~dp0builds\Resonance_FiveActs_20261121\迷失太空_共振星试玩版.exe" & goto menu
if "%pick%"=="0" exit /b 0
echo 没有这个编号。
goto menu

:runexe
if not exist "%~1" (
  echo.
  echo 找不到试玩包: %~1
  pause
  exit /b 1
)
start "" "%~1"
exit /b 0

:run
if not exist "%GODOT%" (
  echo.
  echo 找不到 Godot: %GODOT%
  echo 请把 GODOT_PATH 设为 Godot 4.7 可执行文件路径后重试。
  pause
  exit /b 1
)
if not exist "%~1\.godot\imported" (
  echo 首次运行，正在导入资源，请稍等……
  "%GODOT%" --headless --path "%~1" --import >nul 2>&1
)
if "%~2"=="" (
  start "" "%GODOT%" --path "%~1"
) else (
  start "" "%GODOT%" --path "%~1" %~2
)
exit /b 0
