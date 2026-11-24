# Launches the Zino Editor. Override the Godot path with $env:ZINO_GODOT.
$godot = if ($env:ZINO_GODOT) { $env:ZINO_GODOT } else { 'F:\Godot\Godot_v4.7.2-stable_win64.exe' }
$proj = Join-Path $PSScriptRoot '..\ZinoEditor'
if (-not (Test-Path (Join-Path $proj '.godot'))) {
    & ($godot -replace 'win64\.exe$', 'win64_console.exe') --headless --path $proj --import | Out-Null
}
Start-Process -FilePath $godot -ArgumentList @('--path', "`"$proj`"")
