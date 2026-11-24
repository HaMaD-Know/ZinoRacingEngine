# Builds the Zino Racing Engine release into builds/ZinoEditor:
#   Zino.exe (Windows), engine/addons (runtime + Godot bridge copied into new projects),
#   docs/, Samples/, zino_config.json (path of the Godot editor used for Godot integration and exports).
param([string]$Godot = 'F:\Godot\Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
$proj = Join-Path $repo 'ZinoEditor'
$out = Join-Path $repo 'builds\ZinoEditor'
New-Item -ItemType Directory -Force $out | Out-Null
& $Godot --headless --path $proj --import | Out-Null
& $Godot --headless --path $proj --export-release 'Windows Desktop' (Join-Path $out 'Zino.exe')
if (-not (Test-Path (Join-Path $out 'Zino.exe'))) { throw 'Export failed' }
foreach ($a in 'zino_runtime', 'zino_bridge') {
    $dst = Join-Path $out "engine\addons\$a"
    New-Item -ItemType Directory -Force $dst | Out-Null
    Copy-Item -Recurse -Force (Join-Path $proj "addons\$a\*") $dst
}
$docs = Join-Path $out 'docs'
New-Item -ItemType Directory -Force $docs | Out-Null
Copy-Item -Force (Join-Path $repo '*.md') $docs
Copy-Item -Force (Join-Path $repo 'docs\*.md') $docs
$editorGodot = $Godot.Replace('_console.exe', '.exe')
@{ godotPath = $editorGodot.Replace([string][char]92, '/'); version = '1.1.0' } | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $out 'zino_config.json')
$samples = Join-Path $out 'Samples'
# Samples are build output: regenerate them so they always match this engine version.
if (Test-Path $samples) { Remove-Item -Recurse -Force $samples }
& $Godot --headless --path $proj -s res://tools/make_samples.gd -- $samples
Write-Host "Release ready: $out"
