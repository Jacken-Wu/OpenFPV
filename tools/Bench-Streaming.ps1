param([string]$GodotPath = '', [ValidateRange(10,600)][int]$Seconds = 60, [string]$BaselinePack = '')
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/common.ps1"
$engine = Resolve-Godot $GodotPath
$workspace = Split-Path $PSScriptRoot -Parent
$directory = Join-Path $workspace ('.local/test-results/streaming-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss'))
$script = Join-Path $workspace 'game/tests/streaming_tour_tests.gd'
$runs = if ($BaselinePack) { @('before','after') } else { @('after') }
foreach ($run in $runs) {
    $destination = Join-Path $directory $run
    New-Item -ItemType Directory -Force $destination | Out-Null
    $engineArguments = @('--script', $script, '--log-file', (Join-Path $destination 'engine.log'), '--quit-after', '150000')
    if ($run -eq 'before') { $engineArguments += @('--main-pack', (Resolve-Path -LiteralPath $BaselinePack).Path) }
    else { $engineArguments += @('--path', (Join-Path $workspace 'game')) }
    $engineArguments += @('--', '--test-session', "--capture-dir=$destination", "--seconds=$Seconds")
    $output = & $engine @engineArguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or $output -match '(?m)SCRIPT ERROR:|^ERROR:' -or -not $output.Contains('STREAMING_TOUR_RESULT')) { throw "Streaming benchmark failed: $destination" }
    Write-Host "$run report: $(Join-Path $destination 'crossing.json')"
}
Write-Host 'This measures scripted normal-window crossings, not human RC flight or all world seeds.'
