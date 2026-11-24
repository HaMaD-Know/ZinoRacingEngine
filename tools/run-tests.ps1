# Runs the headless test suite (unit, physics and Godot-editor bridge end-to-end tests).
# Usage: .\tools\run-tests.ps1 [-Filter vehicle]
param([string]$Filter = '')
$godot = if ($env:ZINO_GODOT) { $env:ZINO_GODOT } else { 'F:\Godot\Godot_v4.7.2-stable_win64_console.exe' }
$proj = Join-Path $PSScriptRoot '..\ZinoEditor'
& $godot --headless --path $proj --import | Out-Null
$godotArgs = @('--headless', '--path', $proj, '-s', 'res://tests/run_tests.gd')
if ($Filter) { $godotArgs += @('--', "--filter=$Filter") }
& $godot @godotArgs
exit $LASTEXITCODE
