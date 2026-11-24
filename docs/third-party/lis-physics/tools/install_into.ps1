param(
  [string]$Root = '',
  
)
# LIS Physics SDK · 安装 SDK 到目标 Godot 工程
#
#   pwsh -NoProfile -File tools\install_into.ps1 -Target <project_dir>
#
# 行为（任务书 §15）：
#   * 只**新增/更新** <project>/addons/lis_physics 下的文件；
#   * 绝不修改 project.godot、场景、脚本、InputMap、碰撞层名、autoload；
#   * 目标目录已存在同名 SDK 时先清空该 SDK 目录（只清 lis_physics/，不碰同级其它 addon）。
#   * 不使用符号链接 / junction / 硬链接：全部真实复制。

$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
$src = Join-Path $Root 'package\addons\lis_physics'

function Install-Sdk {
  param([string]$Target)

  if (-not (Test-Path -LiteralPath $src)) {
    throw "找不到 SDK 源：$src（请先运行 tools\build_package.ps1）"
  }
  if (-not (Test-Path -LiteralPath $Target)) {
    throw "目标工程不存在：$Target"
  }
  $addons = Join-Path $Target 'addons'
  $dest = Join-Path $addons 'lis_physics'
  New-Item -ItemType Directory -Force -Path $addons | Out-Null
  if (Test-Path -LiteralPath $dest) {
    Remove-Item -LiteralPath $dest -Recurse -Force
  }
  Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force
  # Godot 的 .godot 缓存里可能残留旧 class_name 记录，删掉让它重建。
  $cache = Join-Path $Target '.godot'
  if (Test-Path -LiteralPath $cache) {
    Remove-Item -LiteralPath $cache -Recurse -Force -ErrorAction SilentlyContinue
  }
  $count = (Get-ChildItem -LiteralPath $dest -Recurse -File | Measure-Object).Count
  Write-Output "INSTALLED $Target  files=$count"
}

if ($PSBoundParameters.ContainsKey('Target') -or $args.Count -gt 0) {
  $t = if ($PSBoundParameters.ContainsKey('Target')) { $Target } else { $args[0] }
  Install-Sdk -Target $t
}

# 直接把本文件当模块 dot-source 时，可使用 Install-Sdk 函数。
