param(
  [string]$Root = '',
  [string]$Only = '',
  [int]$Repeat = 1,
  [int]$TimeoutSec = 300,
  [string]$LogDir = '',
  [switch]$AllowProbes
)
# LIS Physics SDK · 统一测试运行器
#
#   pwsh -NoProfile -File tools\run_tests.ps1
#   pwsh -NoProfile -File tools\run_tests.ps1 -Only smoke_core -Repeat 5
#   pwsh -NoProfile -File tools\run_tests.ps1 -Only core_rigidbody,core_friction -Repeat 5
#
# 判定口径（任务书 §18.E，六条全过才算 PASS）：
#   1. 退出码 == 0（非零一律不算通过，**包括** 0xC0000005）
#   2. 期望断言数 == 实际执行数（COUNT-MISMATCH 判失败）
#   3. 运行器自己数出的 FAIL 行 == 0
#   4. 套件必须打印 LIS_DONE 结果行
#   5. SCRIPT ERROR / Parse Error / previously freed == 0
#   6. SKIP 单独计数，**不计入 PASS**
#
# 运行器**不信**测试自报的 pass 数：它自己从 stdout 数 PASS/FAIL 行。

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
if ($LogDir -eq '') { $LogDir = Join-Path $Root 'runs\test_logs' }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# 套件 -> 期望断言数。数值必须与测试脚本里 _configure() 的 expected_checks 一致。
# 0 = 诊断探针（不要求断言），记 RAN 而非 PASS。
$expect = [ordered]@{
  'smoke_core'                = 9
  'core_profile'              = 10
  'core_mass_inertia'         = 11
  'core_friction'             = 9
  'core_contacts'             = 12
  'core_lifecycle'            = 11
  'machines_wheel_cart'       = 15
  'machines_lever'            = 11
  'machines_door'             = 15
  'machines_rope'             = 14
  'machines_brake'            = 11
  'interaction_grab'          = 18
  'interaction_multiplayer'   = 15
  'interaction_first_person'  = 17
  'integration_combined'      = 12
  'integration_lifecycle'     = 10
  'integration_first_person'  = 12
}

$names = @()
if ($Only -ne '') {
  $names = @($Only -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
} else {
  $names = @($expect.Keys)
}

$noise = 'Godot Engine v|Could not create directory|Failed to open log file|Failed to read the root certificate|root certificate|at: make_dir|at: rotate_file|at: get_system|^\s*$'
$rows = New-Object System.Collections.Generic.List[object]

foreach ($name in $names) {
  # 测试脚本可以放在 tests/ 的子目录里（core/ interaction/ machines/ integration/），
  # 所以按文件名递归查找，并用相对路径构造 res:// 场景地址。
  $gdFile = Get-ChildItem -LiteralPath (Join-Path $lab 'tests') -Recurse -Filter "$name.gd" -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $gdFile) {
    $rows.Add([pscustomobject]@{ Suite=$name; Round=1; Exit='NA'; Verdict='MISSING'; Pass=0; Fail=0; Skip=0; Checks=0; Need=0; Elapsed=0; Note="缺少 tests/$name.gd" })
    continue
  }
  $rel = $gdFile.FullName.Substring((Join-Path $lab 'tests').Length).TrimStart('\','/') -replace '\\','/'
  $scene = "res://tests/$rel"
  $scene = $scene -replace '\.gd$', '.tscn'
  $need = if ($expect.Contains($name)) { [int]$expect[$name] } else { -1 }

  for ($r = 1; $r -le $Repeat; $r++) {
    $so = Join-Path $LogDir "$name.r$r.out.txt"
    $se = Join-Path $LogDir "$name.r$r.err.txt"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath $godot -ArgumentList @(
      '--headless', '--path', $lab, $scene
    ) -RedirectStandardOutput $so -RedirectStandardError $se -NoNewWindow -PassThru
    $ok = $p.WaitForExit($TimeoutSec * 1000)
    $timedOut = $false
    if (-not $ok) { $timedOut = $true; try { $p.Kill($true) } catch {}; Start-Sleep -Milliseconds 300 }
    $sw.Stop()
    $code = if ($timedOut) { 'TIMEOUT' } else { $p.ExitCode }

    $lines = @()
    foreach ($f in @($so, $se)) {
      if (Test-Path -LiteralPath $f) { $lines += (Get-Content -LiteralPath $f) }
    }
    $meaning = @($lines | Where-Object { $_ -notmatch $noise })
    # 运行器自己数行，不信测试自报的汇总
    $pass = @($meaning | Where-Object { $_ -match '^PASS ' }).Count
    $fail = @($meaning | Where-Object { $_ -match '^FAIL ' }).Count
    $skip = @($meaning | Where-Object { $_ -match '^SKIP ' }).Count
    $scriptErr = @($meaning | Where-Object {
        $_ -match 'SCRIPT ERROR|Parse Error|Compile Error|previously freed|Invalid access to property|Attempt to call function .* on a null'
      }).Count
    $doneLine = @($meaning | Where-Object { $_ -match '^LIS_DONE ' }) | Select-Object -Last 1
    $resLine = @($meaning | Where-Object { $_ -match '^LIS_RESULT ' }) | Select-Object -Last 1
    $checks = 0
    if ($resLine) {
      $m = [regex]::Match($resLine, 'checks=(\d+)')
      if ($m.Success) { $checks = [int]$m.Groups[1].Value }
    }

    $verdict = ''
    $note = ''
    if ($timedOut) {
      $verdict = 'TIMEOUT'; $note = "超过 ${TimeoutSec}s"
    } elseif ($scriptErr -gt 0) {
      $verdict = 'SCRIPT-ERROR'; $note = "$scriptErr 条脚本错误"
    } elseif ($code -ne 0) {
      $verdict = 'CRASH'; $note = "退出码 $code（崩溃或异常退出）"
    } elseif (-not $doneLine) {
      $verdict = 'NO-RESULT'; $note = '没有打印 LIS_DONE 结果行'
    } elseif ($checks -eq 0 -and $need -gt 0) {
      $verdict = 'NO-ASSERTIONS'; $note = '0 条断言执行'
    } elseif ($need -ge 0 -and $checks -ne $need) {
      $verdict = 'COUNT-MISMATCH'; $note = "执行 $checks 条，期望 $need 条"
    } elseif ($fail -gt 0) {
      $verdict = 'FAIL'; $note = "$fail 条断言失败"
    } elseif ($need -eq 0 -and $pass -eq 0) {
      $verdict = if ($AllowProbes) { 'RAN' } else { 'PROBE' }
      $note = '诊断探针：只证明跑过，不计作 PASS'
    } elseif ($pass -eq 0) {
      $verdict = 'NO-PASS'; $note = '没有任何 PASS 断言'
    } else {
      $verdict = 'PASS'; $note = ''
    }

    $rows.Add([pscustomobject]@{
      Suite=$name; Round=$r; Exit=$code; Verdict=$verdict; Pass=$pass; Fail=$fail; Skip=$skip;
      Checks=$checks; Need=$need; Elapsed=[math]::Round($sw.Elapsed.TotalSeconds,2); Note=$note
    })
  }
}

$rows | Format-Table -AutoSize | Out-String -Width 200 | Write-Output

$sumPass = @($rows | Where-Object { $_.Verdict -eq 'PASS' }).Count
$sumFail = @($rows | Where-Object { $_.Verdict -in @('FAIL','CRASH','SCRIPT-ERROR','TIMEOUT','NO-RESULT','NO-ASSERTIONS','COUNT-MISMATCH','NO-PASS','MISSING') }).Count
$sumProbe = @($rows | Where-Object { $_.Verdict -in @('PROBE','RAN') }).Count
$totalChecks = ($rows | Measure-Object -Property Checks -Sum).Sum
$totalPassAssertions = ($rows | Measure-Object -Property Pass -Sum).Sum
$totalFailAssertions = ($rows | Measure-Object -Property Fail -Sum).Sum

Write-Output ("SUMMARY runs={0} pass={1} fail={2} probe={3} assertions={4} pass_assertions={5} fail_assertions={6}" -f `
  $rows.Count, $sumPass, $sumFail, $sumProbe, $totalChecks, $totalPassAssertions, $totalFailAssertions)

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$jsonPath = Join-Path $LogDir "summary-$stamp.json"
$rows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $jsonPath -Encoding utf8
Write-Output "LOG $jsonPath"

if ($sumFail -gt 0) { exit 1 } else { exit 0 }
