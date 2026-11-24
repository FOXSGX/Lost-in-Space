param(
  [string]$Root = ''
)
# LIS Physics SDK · 把 package/ + examples/ + tests/ 真实复制进 lab/ 工程
#
#   pwsh -NoProfile -File tools\sync_lab.ps1
#
# 只复制，不建链接（任务书 §4.9）：全部是真实文件副本。
# lab/ 是开发验证场地，交付物是 package/addons/lis_physics。

$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }

$lab = Join-Path $Root 'lab'
if (-not (Test-Path -LiteralPath $lab)) { New-Item -ItemType Directory -Force -Path $lab | Out-Null }

function Sync-Dir {
  param([string]$From, [string]$To)
  if (-not (Test-Path -LiteralPath $From)) { return 0 }
  if (Test-Path -LiteralPath $To) { Remove-Item -LiteralPath $To -Recurse -Force }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $To) | Out-Null
  Copy-Item -LiteralPath $From -Destination $To -Recurse -Force
  return (Get-ChildItem -LiteralPath $To -Recurse -File | Measure-Object).Count
}

$addons = Join-Path $lab 'addons'
New-Item -ItemType Directory -Force -Path $addons | Out-Null
$n1 = Sync-Dir (Join-Path $Root 'package\addons\lis_physics') (Join-Path $addons 'lis_physics')
$n2 = Sync-Dir (Join-Path $Root 'examples') (Join-Path $lab 'examples')
$n3 = Sync-Dir (Join-Path $Root 'tests') (Join-Path $lab 'tests')

Write-Output "SYNCED lab  addons=$n1 examples=$n2 tests=$n3"
