param(
    [ValidateSet("status", "enable", "disable")]
    [string]$Action = "status"
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if (-not $root) {
    $root = Split-Path -Parent $MyInvocation.MyCommand.Path
}

$enabled = 0
$disabled = 0

foreach ($dir in Get-ChildItem -LiteralPath $root -Directory) {
    $on = Join-Path $dir.FullName "project.godot"
    $off = Join-Path $dir.FullName "project.godot.disabled"

    switch ($Action) {
        "enable" {
            if (Test-Path -LiteralPath $off) {
                if (Test-Path -LiteralPath $on) {
                    Write-Warning "skip (both exist): $($dir.Name)"
                } else {
                    Rename-Item -LiteralPath $off -NewName "project.godot"
                    $enabled++
                }
            }
        }
        "disable" {
            if (Test-Path -LiteralPath $on) {
                if (Test-Path -LiteralPath $off) {
                    Write-Warning "skip (both exist): $($dir.Name)"
                } else {
                    Rename-Item -LiteralPath $on -NewName "project.godot.disabled"
                    $disabled++
                }
            }
        }
        "status" {
            $state = if (Test-Path -LiteralPath $on) { "enabled " } elseif (Test-Path -LiteralPath $off) { "disabled" } else { "missing " }
            Write-Host ("{0}  {1}" -f $state, $dir.Name)
        }
    }
}

if ($Action -eq "enable") {
    Write-Host "Enabled $enabled preview project(s)."
} elseif ($Action -eq "disable") {
    Write-Host "Disabled $disabled preview project(s)."
}
