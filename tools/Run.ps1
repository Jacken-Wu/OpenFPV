param([string]$GodotPath, [switch]$Editor, [switch]$Smoke)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$exe = Resolve-Godot $GodotPath
$gamePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'game'
$arguments = @('--path', $gamePath)
if ($Editor) { $arguments += '--editor' }
if ($Smoke) { $arguments += @('--', '--smoke') }
& $exe @arguments
exit $LASTEXITCODE
