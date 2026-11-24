param(
  [string]$Root = '',
  [string]$Version = '1.0.0-rc1',
  [string]$PackageName = 'LIS-PHYSICS-V1.0.0-RC1',
  [switch]$SkipVerify
)
# LIS Physics SDK · 打包发布（ZIP + SHA-256 清单）
#
#   pwsh -NoProfile -File tools\build_package.ps1
#
# 产物：
#   release\<PackageName>.zip          发布包
#   release\<PackageName>.zip.sha256   压缩包的 SHA-256
#   release\<PackageName>.sha256.txt   包内每个文件的 SHA-256 完整清单
#   release\VERSION.json               版本与依赖信息
#
# 打包内容：
#   addons/lis_physics/   公共 SDK（含 tools：检查工具 + 性能基准）
#   examples/             八个示例场景
#   tests/                自动化测试
#   tools/                运行器脚本（PowerShell）
#   docs/                 中文文档
#   VERSION.json          版本信息
#   SHA256SUMS.txt        文件级 SHA-256 清单
#
# 约束：
#   * 不把原项目绝对路径写进包里（打包后扫描校验）；
#   * 不包含任何来源不明或需授权的第三方资源（SDK 全部程序化生成）；
#   * 不使用硬链接 / junction / 符号链接，全部真实复制。

$ErrorActionPreference = 'Stop'
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }

$pkgSrc   = Join-Path $Root 'package\addons\lis_physics'
$examples = Join-Path $Root 'examples'
$tests    = Join-Path $Root 'tests'
$tools    = Join-Path $Root 'tools'
$docs     = Join-Path $Root 'docs'
$release  = Join-Path $Root 'release'
$stage    = Join-Path $Root ("_stage\" + $PackageName)

foreach ($p in @($pkgSrc, $examples, $tests, $tools, $docs)) {
  if (-not (Test-Path -LiteralPath $p)) { throw "缺少打包源：$p" }
}
New-Item -ItemType Directory -Force -Path $release | Out-Null
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

function Copy-Tree {
  param([string]$From, [string]$To)
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $To) | Out-Null
  Copy-Item -LiteralPath $From -Destination $To -Recurse -Force
}

Write-Output "== staging =="
Copy-Tree $pkgSrc   (Join-Path $stage 'addons\lis_physics')
Copy-Tree $examples (Join-Path $stage 'examples')
Copy-Tree $tests    (Join-Path $stage 'tests')
Copy-Tree $docs     (Join-Path $stage 'docs')

# tools：只带运行器脚本（.ps1），不带开发期临时产物
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'tools') | Out-Null
foreach ($f in @('sync_lab.ps1','install_into.ps1','run_tests.ps1','run_one.ps1','run_coop_smoke.ps1','build_package.ps1','verify_package.ps1')) {
  $p = Join-Path $tools $f
  if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination (Join-Path $stage 'tools') -Force }
}

# 清掉不该进包的东西
Get-ChildItem -LiteralPath $stage -Recurse -Force -Include '*.uid','.godot','*.tmp','*.log' -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
Get-ChildItem -LiteralPath $stage -Recurse -Directory -Filter '.godot' -ErrorAction SilentlyContinue |
  ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }

# ---- VERSION.json ----------------------------------------------------------
$godotVer = '4.7.2-stable'
$files = Get-ChildItem -LiteralPath $stage -Recurse -File
$versionJson = [ordered]@{
  sdk_id           = 'lis_physics'
  name             = 'LIS Physics · 第一人称通用真实物理系统'
  version          = $Version
  channel          = 'rc'
  built_at         = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
  godot_required   = '>=4.7'
  godot_verified   = $godotVer
  physics_engine   = 'Jolt Physics'
  physics_tick_hz  = 60
  target_platform  = 'Windows PC'
  language         = 'GDScript'
  install_path     = 'addons/lis_physics'
  entry_docs       = @('docs/README.md','docs/QUICKSTART.md','docs/TEAM_HANDOFF.md','docs/第一人称物理SDK接入指令.md')
  check_tool       = 'addons/lis_physics/tools/lis_project_check.gd'
  perf_tool        = 'addons/lis_physics/tools/lis_perf_bench.tscn'
  dependencies     = @{
    third_party_assets = 'none（全部程序化生成，无外部素材、无授权问题）'
    autoloads          = 'none'
    required_settings  = @{
      'physics/3d/physics_engine'              = 'Jolt Physics'
      'physics/common/physics_ticks_per_second' = 60
    }
    optional_settings  = @{
      'layer_names/3d_physics/layer_3'         = 'interactable（建议，不强制）'
    }
  }
  status           = @{
    functional_acceptance = 'passed'
    performance_acceptance = 'NOT VERIFIED（性能门禁未通过）'
    network_beyond_smoke   = 'NOT VERIFIED（高延迟/丢包/重连未验证）'
    human_playtest         = 'NOT DONE'
    note = 'RC 候选版本，不得作为正式稳定版 V1.0.0 发布'
  }
  file_count       = $files.Count
}
$versionJson | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $stage 'VERSION.json') -Encoding utf8

# ---- 绝对路径扫描（不得写入发布包）----------------------------------------
#
# 只拦**绝对路径**（会指向某台机器上的具体位置）。
# 相对来源注释（例如 "来源：work/final-integration-001/project/scripts/physics/phys_prop.gd"）
# 是**必须保留**的可追溯信息，不是绝对路径，因此放行。
Write-Output "== scanning for absolute paths =="
$driveLetter = [char]67           # 'C'，不写字面量以免脚本自身命中
$bs = [string][char]92            # 反斜杠
$sl = [string][char]47            # 正斜杠
$absPatterns = @(
  ("{0}:{1}Users{1}" -f $driveLetter, $bs),
  ("{0}:{1}Users{1}" -f $driveLetter, $sl),
  ("{0}:{1}Desktop" -f $driveLetter, $bs),
  ("{0}:{1}Desktop" -f $driveLetter, $sl),
  ($bs + $bs + '?' + $bs),                    # UNC 长路径前缀
  ('file:' + $sl + $sl + $sl),                # file URI 形式
  ('res:' + $sl + $sl + '..' + $sl)           # 越出工程根的 res:// 路径
)
# 同时拦本工作区根目录的字面量（若被写进任何文件都算泄漏）
$wsRoot = (Resolve-Path -LiteralPath $Root).Path
$absPatterns += $wsRoot
$absPatterns += ($wsRoot -replace '\\','/')

$bad = @()
foreach ($f in (Get-ChildItem -LiteralPath $stage -Recurse -File)) {
  if ($f.Extension -in @('.png','.jpg','.jpeg','.webp','.ogg','.wav','.ttf','.otf')) { continue }
  $text = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
  if ($null -eq $text) { continue }
  foreach ($pat in $absPatterns) {
    if ($pat -ne '' -and $text.Contains($pat)) {
      $bad += ("{0} :: {1}" -f $f.FullName.Substring($stage.Length), $pat)
    }
  }
}
if ($bad.Count -gt 0) {
  Write-Output "ABSOLUTE-PATH VIOLATIONS:"
  $bad | Select-Object -Unique | ForEach-Object { Write-Output "  $_" }
  throw "发布包内发现绝对路径引用，已中止打包"
}
Write-Output "OK 未发现绝对路径（相对来源注释已放行，属于必要的可追溯信息）"

# ---- SHA-256 清单 ---------------------------------------------------------
Write-Output "== hashing =="
$manifest = @()
foreach ($f in (Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName)) {
  $rel = $f.FullName.Substring($stage.Length).TrimStart('\','/') -replace '\\','/'
  $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
  $manifest += ("{0}  {1}" -f $hash, $rel)
}
$manifestPath = Join-Path $stage 'SHA256SUMS.txt'
$manifest | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Output ("files={0}" -f $manifest.Count)

# ---- 压缩 ----------------------------------------------------------------
Write-Output "== zipping =="
$zip = Join-Path $release ("{0}.zip" -f $PackageName)
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
$zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
$zipSize = (Get-Item -LiteralPath $zip).Length
("SHA256 {0}  {1}" -f $zipHash, ("{0}.zip" -f $PackageName)) | Set-Content -LiteralPath ($zip + '.sha256') -Encoding utf8
$manifest | Set-Content -LiteralPath (Join-Path $release ("{0}.sha256.txt" -f $PackageName)) -Encoding utf8
Copy-Item -LiteralPath (Join-Path $stage 'VERSION.json') -Destination (Join-Path $release 'VERSION.json') -Force

Write-Output "PACKAGE_ZIP $zip"
Write-Output "PACKAGE_SIZE_BYTES $zipSize"
Write-Output "PACKAGE_SHA256 $zipHash"
Write-Output "PACKAGE_FILES $($manifest.Count)"

if ($SkipVerify) { exit 0 }

# ---- 解压复验 ------------------------------------------------------------
Write-Output "== verifying by extraction =="
$verify = Join-Path $Root '_verify_extract'
if (Test-Path -LiteralPath $verify) { Remove-Item -LiteralPath $verify -Recurse -Force }
New-Item -ItemType Directory -Force -Path $verify | Out-Null
Expand-Archive -LiteralPath $zip -DestinationPath $verify -Force

$expanded = Join-Path $verify 'addons\lis_physics'
if (-not (Test-Path -LiteralPath $expanded)) { throw "解压后找不到 addons/lis_physics" }

# 1) 文件清单逐一核对
$missing = 0; $mismatch = 0
foreach ($line in $manifest) {
  $parts = $line -split '  ', 2
  $want = $parts[0]; $rel = $parts[1]
  $target = Join-Path $verify ($rel -replace '/','\')
  if (-not (Test-Path -LiteralPath $target)) { $missing++; Write-Output "  MISSING $rel"; continue }
  $got = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLower()
  if ($got -ne $want) { $mismatch++; Write-Output "  HASH-MISMATCH $rel" }
}
Write-Output ("VERIFY files={0} missing={1} mismatch={2}" -f $manifest.Count, $missing, $mismatch)
if ($missing -gt 0 -or $mismatch -gt 0) { throw "解压复验失败：清单不一致" }
Write-Output "VERIFY_OK 解压后文件与 SHA-256 清单完全一致"
