param(
  [string]$Root = '',
  [string]$Zip = '',
  [string]$Godot = '',
  [switch]$KeepWork
)
# LIS Physics SDK · 发布包独立安装验证
#
#   pwsh -NoProfile -File tools\verify_package.ps1
#
# 按任务书 §19 的八步验证：
#   1. 生成压缩包（由 build_package.ps1 负责，本脚本只消费）
#   2. 计算 SHA-256（同上）
#   3. 解压到全新目录        ← 本脚本
#   4. 检查文件完整性        ← 本脚本
#   5. 导入干净 Godot 工程    ← 本脚本
#   6. 运行最小第一人称示例   ← 本脚本
#   7. 运行关键物理测试       ← 本脚本
#   8. 验证没有原项目路径依赖 ← 本脚本
#
# 不使用符号链接 / junction：全部真实复制。
# 退出码：0 = 全部通过；1 = 有失败项。

$ErrorActionPreference = 'Continue'
if ($Root -eq '') { $Root = Split-Path -Parent $PSScriptRoot }
if ($Zip -eq '') {
  $cand = Get-ChildItem -LiteralPath (Join-Path $Root 'release') -Filter '*.zip' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($null -eq $cand) { throw '找不到发布包，请先运行 tools\build_package.ps1' }
  $Zip = $cand.FullName
}

function Resolve-Godot {
  param([string]$Root, [string]$Explicit)
  if ($Explicit -ne '' -and (Test-Path -LiteralPath $Explicit)) { return $Explicit }
  if ($env:GODOT_BIN -and (Test-Path -LiteralPath $env:GODOT_BIN)) { return $env:GODOT_BIN }
  foreach ($cand in @(
    (Join-Path $Root 'godot\Godot_v4.7.2-stable_win64_console.exe'),
    (Join-Path $Root '..\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'),
    (Join-Path $Root '..\..\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe'),
    (Join-Path $Root '..\..\..\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe')
  )) {
    if (Test-Path -LiteralPath $cand) { return (Resolve-Path -LiteralPath $cand).Path }
  }
  foreach ($nm in @('godot','godot4')) {
    $cmd = Get-Command $nm -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
  }
  return $null
}

$godot = Resolve-Godot -Root $Root -Explicit $Godot
if (-not $godot) { throw 'GODOT_NOT_FOUND 请设置环境变量 GODOT_BIN' }

$work = Join-Path $Root '_verify_package'
if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
$extract = Join-Path $work 'extracted'
New-Item -ItemType Directory -Force -Path $extract | Out-Null

$failures = New-Object System.Collections.Generic.List[string]
function Check {
  param([string]$Name, [bool]$Ok, [string]$Detail = '')
  $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
  if (-not $Ok) { $failures.Add($Name) }
  Write-Output ("VERIFY_{0} {1}  |  {2}" -f $tag, $Name, $Detail)
}

# ---- 3) 解压到全新目录 ------------------------------------------------------
Write-Output "== 解压 =="
Expand-Archive -LiteralPath $Zip -DestinationPath $extract -Force
$zipName = [IO.Path]::GetFileNameWithoutExtension($Zip)
$pkgRoot = Join-Path $extract $zipName
if (-not (Test-Path -LiteralPath $pkgRoot)) { $pkgRoot = $extract }   # 压缩包无顶层目录时
$sdkSrc = Join-Path $pkgRoot 'addons\lis_physics'
Check '解压后存在 addons/lis_physics' (Test-Path -LiteralPath $sdkSrc) $sdkSrc

# ---- 4) 文件完整性（SHA-256SUMS.txt 逐条核对）------------------------------
Write-Output "== 文件完整性 =="
$sumsPath = Join-Path $pkgRoot 'SHA256SUMS.txt'
Check '发布包含 SHA256SUMS.txt' (Test-Path -LiteralPath $sumsPath) $sumsPath
if (Test-Path -LiteralPath $sumsPath) {
  $missing = 0; $mismatch = 0; $count = 0
  foreach ($line in (Get-Content -LiteralPath $sumsPath)) {
    if ($line.Trim() -eq '') { continue }
    $parts = $line -split '  ', 2
    if ($parts.Count -lt 2) { continue }
    $want = $parts[0]; $rel = $parts[1]; $count++
    $target = Join-Path $pkgRoot ($rel -replace '/','\')
    if (-not (Test-Path -LiteralPath $target)) { $missing++; continue }
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLower() -ne $want) { $mismatch++ }
  }
  Check 'SHA-256 清单逐条一致' ($missing -eq 0 -and $mismatch -eq 0 -and $count -gt 0) `
    ("共 {0} 个文件，缺失 {1}，不一致 {2}" -f $count, $missing, $mismatch)
}

# ---- 8) 没有原项目路径依赖 ------------------------------------------------
Write-Output "== 路径依赖检查 =="
$bs = [string][char]92; $sl = [string][char]47; $dl = [char]67
$absPat = @(
  ("{0}:{1}Users{1}" -f $dl, $bs), ("{0}:{1}Users{1}" -f $dl, $sl),
  ("{0}:{1}Desktop" -f $dl, $bs), ("{0}:{1}Desktop" -f $dl, $sl),
  ($bs + $bs + '?' + $bs), ('file:' + $sl + $sl + $sl), ('res:' + $sl + $sl + '..' + $sl)
)
$hits = @()
foreach ($f in (Get-ChildItem -LiteralPath $pkgRoot -Recurse -File)) {
  if ($f.Extension -in @('.png','.jpg','.jpeg','.webp','.ogg','.wav','.ttf','.otf')) { continue }
  $t = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
  if ($null -eq $t) { continue }
  foreach ($p in $absPat) { if ($p -ne '' -and $t.Contains($p)) { $hits += $f.Name } }
}
Check '发布包内无绝对路径' ($hits.Count -eq 0) (($hits | Select-Object -Unique) -join ', ')

# ---- 5) 导入干净 Godot 工程 ------------------------------------------------
Write-Output "== 干净工程导入 =="
$proj = Join-Path $work 'clean_project'
New-Item -ItemType Directory -Force -Path $proj | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $proj 'addons') | Out-Null
# 只复制 SDK（模拟"干净工程只导入 SDK"）
Copy-Item -LiteralPath $sdkSrc -Destination (Join-Path $proj 'addons\lis_physics') -Recurse -Force

@'
config_version=5

[application]

config/name="LIS SDK 干净工程验证"
config/features=PackedStringArray("4.7", "GL Compatibility")

[physics]

3d/physics_engine="Jolt Physics"
common/physics_ticks_per_second=60

[layer_names]

3d_physics/layer_3="interactable"

[rendering]

renderer/rendering_method="gl_compatibility"
'@ | Set-Content -LiteralPath (Join-Path $proj 'project.godot') -Encoding utf8

$impOut = Join-Path $work 'import.txt'
$impErr = Join-Path $work 'import.err.txt'
$p = Start-Process -FilePath $godot -ArgumentList @('--headless','--path',$proj,'--import') `
  -RedirectStandardOutput $impOut -RedirectStandardError $impErr -NoNewWindow -PassThru
$impDone = $p.WaitForExit(180000)
if (-not $impDone) { try { $p.Kill($true) } catch {} }
$impLines = @()
foreach ($f in @($impOut, $impErr)) { if (Test-Path -LiteralPath $f) { $impLines += Get-Content -LiteralPath $f } }
$impErrs = @($impLines | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|Compile Error' })
Check '干净工程可导入 SDK（无脚本错误）' ($impErrs.Count -eq 0 -and $impDone) `
  ("脚本错误 {0} 条" -f $impErrs.Count)
if ($impErrs.Count -gt 0) { $impErrs | Select-Object -First 5 | ForEach-Object { Write-Output "    $_" } }

# ---- 5b) 工程体检工具 ------------------------------------------------------
$chkOut = Join-Path $work 'check.txt'
$p2 = Start-Process -FilePath $godot -ArgumentList @(
  '--headless','--path',$proj,'--script','res://addons/lis_physics/tools/lis_project_check.gd'
) -RedirectStandardOutput $chkOut -RedirectStandardError ($chkOut + '.err') -NoNewWindow -PassThru
$chkDone = $p2.WaitForExit(120000)
if (-not $chkDone) { try { $p2.Kill($true) } catch {} }
$chkLines = @(Get-Content -LiteralPath $chkOut -ErrorAction SilentlyContinue)
$chkVerdict = @($chkLines | Where-Object { $_ -match '^LIS_CHECK ' }) | Select-Object -Last 1
$chkOk = $chkVerdict -and ($chkVerdict -notmatch 'verdict=FAIL')
Check '工程体检工具在干净工程可用' $chkOk $chkVerdict

# ---- 6) 运行最小第一人称示例 ----------------------------------------------
Write-Output "== 最小第一人称示例 =="
Copy-Item -LiteralPath (Join-Path $pkgRoot 'examples') -Destination (Join-Path $proj 'examples') -Recurse -Force
$exScene = 'res://examples/minimal_planet/minimal_planet.tscn'
$exOut = Join-Path $work 'example.txt'
$p3 = Start-Process -FilePath $godot -ArgumentList @(
  '--headless','--path',$proj,'--quit-after','300',$exScene
) -RedirectStandardOutput $exOut -RedirectStandardError ($exOut + '.err') -NoNewWindow -PassThru
$exDone = $p3.WaitForExit(180000)
if (-not $exDone) { try { $p3.Kill($true) } catch {} }
$exLines = @()
foreach ($f in @($exOut, $exOut + '.err')) { if (Test-Path -LiteralPath $f) { $exLines += Get-Content -LiteralPath $f } }
$exErrs = @($exLines | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|previously freed' })
Check '最小第一人称示例可运行（无脚本错误、正常退出）' `
  ($exErrs.Count -eq 0 -and $exDone -and $p3.ExitCode -eq 0) `
  ("退出码 {0}，脚本错误 {1} 条" -f $p3.ExitCode, $exErrs.Count)

# ---- 7) 运行关键物理测试 ---------------------------------------------------
Write-Output "== 关键物理测试 =="
Copy-Item -LiteralPath (Join-Path $pkgRoot 'tests') -Destination (Join-Path $proj 'tests') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $pkgRoot 'tools\run_tests.ps1') -Destination (Join-Path $proj 'tools_run_tests.ps1') -Force
$keySuites = @('core_profile','core_friction','interaction_grab','machines_door','machines_lever','integration_lifecycle')
foreach ($suite in $keySuites) {
  $gdFile = Get-ChildItem -LiteralPath (Join-Path $proj 'tests') -Recurse -Filter "$suite.gd" -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $gdFile) { Check "关键测试 $suite" $false '找不到测试脚本'; continue }
  $rel = $gdFile.FullName.Substring((Join-Path $proj 'tests').Length).TrimStart('\','/') -replace '\\','/'
  $scene = ('res://tests/' + ($rel -replace '\.gd$','.tscn'))
  $tOut = Join-Path $work ("test_$suite.txt")
  $pt = Start-Process -FilePath $godot -ArgumentList @('--headless','--path',$proj,$scene) `
    -RedirectStandardOutput $tOut -RedirectStandardError ($tOut + '.err') -NoNewWindow -PassThru
  $tDone = $pt.WaitForExit(240000)
  if (-not $tDone) { try { $pt.Kill($true) } catch {} }
  $tLines = @()
  foreach ($f in @($tOut, $tOut + '.err')) { if (Test-Path -LiteralPath $f) { $tLines += Get-Content -LiteralPath $f } }
  $meaning = @($tLines | Where-Object { $_ -notmatch 'Godot Engine v|Could not create directory|Failed to open log file|root certificate|at: make_dir|at: rotate_file|at: get_system' })
  $pass = @($meaning | Where-Object { $_ -match '^PASS ' }).Count
  $fail = @($meaning | Where-Object { $_ -match '^FAIL ' }).Count
  $done = @($meaning | Where-Object { $_ -match '^LIS_DONE ' }).Count -gt 0
  $scriptErr = @($meaning | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|previously freed' }).Count
  $ok = $done -and $fail -eq 0 -and $scriptErr -eq 0 -and $pass -gt 0 -and $tDone -and $pt.ExitCode -eq 0
  Check "关键测试 $suite" $ok ("PASS {0} / FAIL {1} / 退出码 {2} / 脚本错误 {3}" -f $pass, $fail, $pt.ExitCode, $scriptErr)
}

# ---- 汇总 -----------------------------------------------------------------
Write-Output ""
Write-Output ("VERIFY_RESULT zip={0}" -f $Zip)
Write-Output ("VERIFY_SUMMARY failures={0}" -f $failures.Count)
if ($failures.Count -gt 0) {
  Write-Output "FAILED ITEMS:"
  $failures | ForEach-Object { Write-Output "  - $_" }
}
if (-not $KeepWork) { Write-Output ("工作目录保留在 {0}（可用 -KeepWork 之外的手动删除）" -f $work) }
if ($failures.Count -gt 0) { exit 1 } else { exit 0 }
