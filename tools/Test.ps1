param([string]$GodotPath = '', [switch]$Window)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/common.ps1"
$engine = Resolve-Godot $GodotPath
$project = Join-Path (Split-Path $PSScriptRoot -Parent) 'game'
$logs = Join-Path (Split-Path $PSScriptRoot -Parent) '.local/test-results'
New-Item -ItemType Directory -Path $logs -Force | Out-Null

function Invoke-EngineCheck([string]$Name, [string[]]$EngineArgs, [string]$Marker) {
    $output = & $engine @EngineArgs 2>&1 | Out-String
    $code = $LASTEXITCODE
    $output | Set-Content -LiteralPath (Join-Path $logs "$Name.log") -Encoding utf8
    if ($code -ne 0 -or $output -match '(?m)SCRIPT ERROR:|^ERROR:|^FAIL' -or ($Marker -and -not $output.Contains($Marker))) {
        Write-Host $output
        throw "Check failed: $Name (exit $code)"
    }
    Write-Host "PASS $Name"
}

Invoke-EngineCheck 'import' @('--headless', '--path', $project, '--editor', '--import') ''
foreach ($suite in @('input', 'content', 'world', 'flight', 'integration')) {
    $marker = if ($suite -eq 'flight') { 'FLIGHT_TESTS: 0 failure(s)' } else { "$($suite.ToUpper())_RESULT failures=0" }
    Invoke-EngineCheck $suite @('--headless', '--path', $project, '--script', "res://tests/${suite}_tests.gd", '--quit-after', '5000', '--', '--test-session') $marker
}
Invoke-EngineCheck 'smoke' @('--headless', '--path', $project, '--quit-after', '1800', '--', '--smoke') 'SMOKE_OK'
if ($Window) {
    Invoke-EngineCheck 'window-tour' @('--path', $project, '--quit-after', '3000', '--', '--tour', "--capture-dir=$logs") 'SMOKE_OK'
}
Write-Host "All checks passed. Logs: $logs"
