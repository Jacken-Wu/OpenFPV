param([string]$GodotPath = '')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/common.ps1"
$engine = Resolve-Godot $GodotPath
$workspace = Split-Path $PSScriptRoot -Parent
$project = Join-Path $workspace 'game'
$bundle = Join-Path $workspace 'builds/OpenFPV-P1'
$logs = Join-Path $workspace '.local'
New-Item -ItemType Directory -Force $bundle, $logs | Out-Null
$pack = Join-Path $bundle 'OpenFPV.pck'
$output = & $engine --headless --path $project --export-pack Windows $pack 2>&1 | Out-String
$output | Set-Content -LiteralPath (Join-Path $logs 'build.log') -Encoding utf8
if ($LASTEXITCODE -ne 0 -or $output -match '(?m)SCRIPT ERROR:|^ERROR:' -or -not (Test-Path -LiteralPath $pack)) {
    throw 'Resource-pack build failed; see .local/build.log'
}
# A local portable runner uses the verified installed engine. Standard release export
# remains separate and requires matching Godot export templates.
$runner = $engine -replace '_console\.exe$', '.exe'
Copy-Item -LiteralPath $runner -Destination (Join-Path $bundle 'OpenFPV.exe') -Force
@'
@echo off
start "" "%~dp0OpenFPV.exe" --main-pack "%~dp0OpenFPV.pck"
'@ | Set-Content -LiteralPath (Join-Path $bundle 'Play.cmd') -Encoding ascii
$notices = Join-Path $bundle 'GODOT-NOTICES.txt'
$output = & $engine --headless --path $project --script res://tests/write_engine_notices.gd --quit-after 120 -- "--output=$notices" 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or -not $output.Contains('ENGINE_NOTICES_OK')) { throw 'Engine notices could not be written' }
$output = & $engine --headless --main-pack $pack --quit-after 1800 -- --smoke 2>&1 | Out-String
$output | Set-Content -LiteralPath (Join-Path $logs 'bundle-smoke.log') -Encoding utf8
if ($LASTEXITCODE -ne 0 -or $output -match '(?m)SCRIPT ERROR:|^ERROR:' -or -not $output.Contains('SMOKE_OK')) { throw 'Packaged-game smoke failed' }
$packedFingerprint = [regex]::Match($output, 'CONTENT_FINGERPRINT (\w+)').Groups[1].Value
$output = & $engine --headless --path $project --quit-after 1800 -- --smoke 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $output -match '(?m)SCRIPT ERROR:|^ERROR:' -or -not $output.Contains('SMOKE_OK')) { throw 'Source-game smoke failed' }
$sourceFingerprint = [regex]::Match($output, 'CONTENT_FINGERPRINT (\w+)').Groups[1].Value
if (-not $sourceFingerprint -or $sourceFingerprint -ne $packedFingerprint) { throw 'Source and packaged content fingerprints differ' }
@'
OpenFPV P1 - local portable prototype

Double-click Play.cmd, or OpenFPV.exe. F1: help; F2: RC calibration; P: resume.
The pack uses the installed Godot editor-capable binary as its local runtime.
It is larger than a standard release export. Matching export templates are not installed.
Generated scenes/textures need no external assets. Project source license is not selected yet.
Godot and bundled component notices are in GODOT-NOTICES.txt.
'@ | Set-Content -LiteralPath (Join-Path $bundle 'README.txt') -Encoding utf8
Write-Host "Bundle ready: $bundle"
