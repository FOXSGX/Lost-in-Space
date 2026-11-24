param(
  [string]$Root = '',
  [int]$Port = 45871,
  [int]$TimeoutSec = 60
)
# LIS Physics SDK · 双进程基础冒烟（验证工程 B）
#
#   pwsh -NoProfile -File tools\run_coop_smoke.ps1
#
# 启动 **两个独立 Godot 进程**（host / client），确认：
#   1. 两个进程都能启动并进入场景
#   2. ENet 连接建立
#   3. 客户端发出的一条交互意图被主机接收并转成真实抓握
#   4. 两个进程都不产生脚本错误
#
# ⚠ 这是**基础连通冒烟**，不是网络质量验证：
#   高延迟、丢包、断线重连均未验证（任务书 §12 明确不做专项研发）。

$ErrorActionPreference = 'Continue'
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
$proj = Join-Path $Root 'verification\project_b_coop'
# Godot 可执行文件定位（**不硬编码绝对路径**，便于发布包在任意机器上使用）：
#   1) 环境变量 GODOT_BIN
#   2) 常见本地位置 tools/godot-4.7.2/
#   3) PATH 里的 godot
function Resolve-Godot {
  param([string]$Root)
  if ($env:GODOT_BIN -and (Test-Path -LiteralPath $env:GODOT_BIN)) { return $env:GODOT_BIN }
  foreach ($cand in @(
    (Join-Path $Root 'godot\Godot_v4.7.2-stable_win64_console.exe'),
    (Join-Path $Root '..\..\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'),
    (Join-Path $Root '..\..\..\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe')
  )) {
    if (Test-Path -LiteralPath $cand) { return (Resolve-Path -LiteralPath $cand).Path }
  }
  foreach ($nm in @('godot','godot4','Godot_v4.7.2-stable_win64_console.exe')) {
    $cmd = Get-Command $nm -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
  }
  return $null
}
$godot = Resolve-Godot -Root $Root
if (-not $godot) {
  Write-Output 'GODOT_NOT_FOUND 请设置环境变量 GODOT_BIN 指向 Godot 4.7+ 可执行文件'
  exit 4
}
$runs = Join-Path $Root 'runs'
New-Item -ItemType Directory -Force -Path $runs | Out-Null
$hostOut = Join-Path $runs 'coop_host.txt'
$cliOut = Join-Path $runs 'coop_client.txt'

if (-not (Test-Path -LiteralPath (Join-Path $proj 'addons\lis_physics'))) {
  throw "验证工程 B 未安装 SDK：$proj"
}

Write-Output "COOP launching host ..."
$h = Start-Process -FilePath $godot -ArgumentList @(
  '--headless','--path',$proj,'--quit-after','900','--','--host'
) -RedirectStandardOutput $hostOut -RedirectStandardError ($hostOut+'.err') -NoNewWindow -PassThru
Start-Sleep -Seconds 4

Write-Output "COOP launching client ..."
$c = Start-Process -FilePath $godot -ArgumentList @(
  '--headless','--path',$proj,'--quit-after','700','--','--client'
) -RedirectStandardOutput $cliOut -RedirectStandardError ($cliOut+'.err') -NoNewWindow -PassThru

$cDone = $c.WaitForExit($TimeoutSec * 1000)
if (-not $cDone) { try { $c.Kill($true) } catch {} }
$hDone = $h.WaitForExit($TimeoutSec * 1000)
if (-not $hDone) { try { $h.Kill($true) } catch {} }
Start-Sleep -Milliseconds 500

$hostLines = @(Get-Content $hostOut -ErrorAction SilentlyContinue)
$cliLines = @(Get-Content $cliOut -ErrorAction SilentlyContinue)
Write-Output "--- host ---"
$hostLines | Where-Object { $_ -match 'COOP_SMOKE' } | ForEach-Object { Write-Output $_ }
Write-Output "--- client ---"
$cliLines | Where-Object { $_ -match 'COOP_SMOKE' } | ForEach-Object { Write-Output $_ }

$hostJoined = @($hostLines | Where-Object { $_ -match 'COOP_SMOKE peer_connected' }).Count -gt 0
$clientJoined = @($cliLines | Where-Object { $_ -match 'COOP_SMOKE connected' }).Count -gt 0
$intentRecv = @($hostLines | Where-Object { $_ -match 'COOP_SMOKE host received intent' }).Count -gt 0
$grabOk = @($hostLines | Where-Object { $_ -match 'COOP_SMOKE host applied grab ok=true' }).Count -gt 0

$errs = 0
foreach ($f in @($hostOut, $hostOut + '.err', $cliOut, $cliOut + '.err')) {
  if (Test-Path -LiteralPath $f) {
    $errs += @(Get-Content $f | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|previously freed' }).Count
  }
}

$verdict = 'FAIL'
if ($hostJoined -and $clientJoined -and $intentRecv -and $grabOk -and $errs -eq 0) { $verdict = 'PASS' }
Write-Output ("COOP_SMOKE_RESULT host_joined={0} client_joined={1} intent_received={2} grab_applied={3} script_errors={4} verdict={5}" -f `
  $hostJoined, $clientJoined, $intentRecv, $grabOk, $errs, $verdict)

if ($verdict -ne 'PASS') { exit 1 } else { exit 0 }
