param(
  [string]$Root = '',
  [Parameter(Mandatory=$true)][string]$Scene,
  [int]$TimeoutSec = 150,
  [string]$LogName = ''
)
# LIS Physics SDK · 单场景运行助手（带硬超时，防止脚本解析失败时无限挂起）
#
#   pwsh -NoProfile -File tools\run_one.ps1 -Scene core/core_contacts
#   pwsh -NoProfile -File tools\run_one.ps1 -Scene examples/first_person_sandbox/first_person_sandbox -TimeoutSec 20
#
# 退出码：0 = 进程正常退出且无 SCRIPT ERROR；1 = 有脚本错误 / 非零退出；2 = 超时。

$ErrorActionPreference = 'Continue'
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
$lab = Join-Path $Root 'lab'
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
if ($LogName -eq '') { $LogName = ($Scene -replace '[\\/]', '_') }
$so = Join-Path $runs "$LogName.out.txt"
$se = Join-Path $runs "$LogName.err.txt"

$res = if ($Scene.StartsWith('res://')) { $Scene } else { "res://tests/$Scene.tscn" }
$p = Start-Process -FilePath $godot -ArgumentList @('--headless','--path',$lab,$res) `
  -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -PassThru
$ok = $p.WaitForExit($TimeoutSec * 1000)
$timedOut = $false
if (-not $ok) {
  $timedOut = $true
  try { $p.Kill($true) } catch {}
  Start-Sleep -Milliseconds 400
}

$lines = @()
foreach ($f in @($so, $se)) { if (Test-Path -LiteralPath $f) { $lines += (Get-Content -LiteralPath $f) } }
$meaning = @($lines | Where-Object {
  $_ -notmatch 'Godot Engine v|Could not create directory|Failed to open log file|root certificate|at: make_dir|at: rotate_file|at: get_system|^\s*$'
})
$meaning | ForEach-Object { Write-Output $_ }

$errs = @($meaning | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|Compile Error|previously freed' })
$exitCode = if ($timedOut) { 'TIMEOUT' } else { $p.ExitCode }
Write-Output "RUN_ONE scene=$Scene exit=$exitCode script_errors=$($errs.Count)"
if ($timedOut) { exit 2 }
if ($errs.Count -gt 0) { exit 1 }
if (-not $timedOut -and $p.ExitCode -ne 0) { exit 1 }
exit 0
